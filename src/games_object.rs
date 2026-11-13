//! The Games tab and game detection for QML: the library (read on a worker
//! thread), own entries, starting a game through its launcher, and which
//! game runs now (a look at `/proc` every 3 s on its own thread; QML hears
//! of it only when it changes).

// add_own and update_own take every field of an entry.
#![allow(clippy::too_many_arguments)]

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use std::collections::BTreeSet;

use crate::games::{self, Game, GameOptions, GamesSettings, Matcher, OwnGame};
use crate::settings;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        /// The running game's id ("" when none runs).
        #[qproperty(QString, running)]
        #[qproperty(QString, running_name)]
        /// The running game's built-in key ("aion2", "poe2"; "" for others).
        #[qproperty(QString, running_known)]
        /// The running game's Twitch category and YouTube search words
        /// (its own choice, else the built-in game's; "" otherwise).
        #[qproperty(QString, twitch_preset)]
        #[qproperty(QString, youtube_preset)]
        /// JSON `[{"id","name","launcher","picture","known","own","hidden",
        /// "fav","lastPlayed","processes","command","twitch","youtube",
        /// "showOnStart","radioOnStart"}]`, sorted by name.
        #[qproperty(QString, library)]
        /// Whether the libraries are being read.
        #[qproperty(bool, scanning)]
        type Games = super::GamesRust;

        /// Detection saw a game start (its id).
        #[qsignal]
        fn started(self: Pin<&mut Games>, id: QString);

        /// The game that ran has ended (its id).
        #[qsignal]
        fn stopped(self: Pin<&mut Games>, id: QString);

        /// Reads the launchers' libraries again (in the background).
        #[qinvokable]
        fn refresh(self: Pin<&mut Games>);

        /// Starts a game through its launcher (or an own entry's command);
        /// false if it could not be started.
        #[qinvokable]
        fn launch(self: Pin<&mut Games>, id: &QString) -> bool;

        /// Adds an own entry; `processes` separated by commas or new lines
        /// (guessed from the command when empty). Its id, or "" when the
        /// name or the command is missing or the command cannot be split.
        #[qinvokable]
        fn add_own(
            self: Pin<&mut Games>,
            name: &QString,
            command: &QString,
            processes: &QString,
            twitch: &QString,
            youtube: &QString,
            show_on_start: bool,
            radio_on_start: bool,
        ) -> QString;

        /// Changes an own entry (the same fields); false if it is none or
        /// the name or the command is missing.
        #[qinvokable]
        fn update_own(
            self: Pin<&mut Games>,
            id: &QString,
            name: &QString,
            command: &QString,
            processes: &QString,
            twitch: &QString,
            youtube: &QString,
            show_on_start: bool,
            radio_on_start: bool,
        ) -> bool;

        #[qinvokable]
        fn remove_own(self: Pin<&mut Games>, id: &QString);

        /// A game's Streams presets ("" for the built-in game's) and what
        /// happens when it starts; for own entries it changes the entry.
        #[qinvokable]
        fn set_options(self: Pin<&mut Games>, id: &QString, twitch: &QString, youtube: &QString, show_on_start: bool, radio_on_start: bool);

        /// Hides a game from the library, or shows it again (it is still
        /// detected).
        #[qinvokable]
        fn hide(self: Pin<&mut Games>, id: &QString, hidden: bool);

        #[qinvokable]
        fn favorite(self: Pin<&mut Games>, id: &QString, favorite: bool);
    }

    impl cxx_qt::Threading for Games {}
    impl cxx_qt::Initialize for Games {}
}

pub struct GamesRust {
    running: QString,
    running_name: QString,
    running_known: QString,
    twitch_preset: QString,
    youtube_preset: QString,
    library: QString,
    scanning: bool,
    /// The launchers' games, as last read.
    scanned: Vec<Game>,
    /// What detection looks for (the library and the built-in games).
    watch: Arc<Matcher>,
}

impl Default for GamesRust {
    fn default() -> Self {
        Self {
            running: QString::default(),
            running_name: QString::default(),
            running_known: QString::default(),
            twitch_preset: QString::default(),
            youtube_preset: QString::default(),
            library: QString::from("[]"),
            scanning: false,
            scanned: Vec::new(),
            watch: Arc::new(Matcher::default()),
        }
    }
}

fn q(s: &str) -> QString {
    QString::from(s)
}

/// The detection table, shared with the detection thread; replaced (not
/// changed) when the library changes.
fn watched() -> &'static Mutex<Arc<Matcher>> {
    static WATCHED: OnceLock<Mutex<Arc<Matcher>>> = OnceLock::new();
    WATCHED.get_or_init(|| Mutex::new(Arc::new(Matcher::default())))
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from).filter(|p| p.is_absolute())
}

fn now_seconds() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn demo_mode() -> bool {
    std::env::var("GC_DEMO").is_ok_and(|d| d.contains("games"))
}

/// How often `/proc` is looked at.
const POLL: Duration = Duration::from_secs(3);

/// A name, a Streams preset: one line, trimmed, not too long.
fn line(text: &QString, max: usize) -> String {
    text.to_string().trim().chars().filter(|c| !c.is_control()).take(max).collect()
}

fn library_json(library: &[Game], settings: &GamesSettings) -> String {
    let mut list: Vec<&Game> = library.iter().collect();
    list.sort_by_cached_key(|g| (g.name.to_lowercase(), g.id.clone()));
    let list: Vec<Value> = list
        .into_iter()
        .map(|g| {
            let own = g.launcher == "own";
            json!({
                "id": g.id,
                "name": g.name,
                "launcher": g.launcher,
                "picture": g.picture.as_deref().map(games::file_url).unwrap_or_default(),
                "known": g.known.unwrap_or(""),
                "own": own,
                "hidden": settings.hidden.contains(&g.id),
                "fav": settings.favorites.contains(&g.id),
                "lastPlayed": settings.last_played.get(&g.id).copied().unwrap_or(0),
                "processes": g.processes,
                "command": if own { g.launch.as_str() } else { "" },
                "twitch": g.twitch,
                "youtube": g.youtube,
                "showOnStart": g.show_on_start,
                "radioOnStart": g.radio_on_start,
            })
        })
        .collect();
    Value::Array(list).to_string()
}

/// Starts a program in its own session, so it outlives the app; a thread
/// collects it when it ends.
fn spawn_detached(program: &str, args: &[String], env: &[(String, String)]) -> bool {
    use std::os::unix::process::CommandExt;
    let mut command = Command::new(program);
    command.args(args).envs(env.iter().cloned()).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    if let Some(home) = home() {
        command.current_dir(home);
    }
    // SAFETY: setsid only, between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    match command.spawn() {
        Ok(mut child) => {
            std::thread::spawn(move || child.wait());
            true
        }
        Err(e) => {
            eprintln!("game-companion: cannot start {program}: {e}");
            false
        }
    }
}

impl cxx_qt::Initialize for qobject::Games {
    fn initialize(mut self: Pin<&mut Self>) {
        if demo_mode() {
            self.as_mut().demo();
            return;
        }
        // The built-in games are looked for before the libraries are read.
        self.as_mut().rebuild();
        self.as_mut().refresh();
        if std::env::var_os("GC_NO_GAMES").is_some() {
            return;
        }
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("games".into())
            .spawn(move || {
                let proc_root = Path::new("/proc");
                let mut last: Option<String> = None;
                loop {
                    let matcher = watched().lock().unwrap_or_else(|p| p.into_inner()).clone();
                    let now = matcher.scan(proc_root).map(|g| g.id.clone());
                    if now != last {
                        last = now.clone();
                        if thread.queue(move |obj: Pin<&mut qobject::Games>| obj.detected(now)).is_err() {
                            break;
                        }
                    }
                    std::thread::sleep(POLL);
                }
            })
            .ok();
    }
}

impl qobject::Games {
    /// Screenshots (GC_DEMO=games): a made-up library, AION 2 running;
    /// nothing read from disk.
    fn demo(mut self: Pin<&mut Self>) {
        let scanned = vec![
            Game::new("steam:2694490", "Path of Exile 2", "steam", ""),
            Game::new("steam:1000001", "Space Game", "steam", ""),
            Game::new("lutris:3", "Dungeon Crawler", "lutris", ""),
            Game::new("heroic:legendary:demo", "Racing Game", "heroic", ""),
            Game::new("heroic:gog:1207", "Old Adventure", "heroic", ""),
        ];
        let mut settings = GamesSettings {
            own: vec![OwnGame { id: 1, name: "AION 2".into(), command: "wine ~/Games/aion2/AION2.exe".into(), ..Default::default() }],
            ..Default::default()
        };
        settings.hidden.insert("heroic:gog:1207".into());
        settings.favorites.insert("own:1".into());
        settings.last_played.insert("own:1".into(), now_seconds());
        settings.last_played.insert("steam:2694490".into(), now_seconds().saturating_sub(86_400));
        let list = games::compose(&scanned, &settings);
        self.as_mut().set_library(q(&library_json(&list, &settings)));
        self.as_mut().rust_mut().watch = Arc::new(Matcher::new(games::watch_list(&list, &settings)));
        self.show_running("own:1");
    }

    /// The running game's properties, from the detection table ("" for none).
    fn show_running(mut self: Pin<&mut Self>, id: &str) {
        let watch = self.rust().watch.clone();
        let game = watch.games.iter().find(|g| !id.is_empty() && g.id == id);
        self.as_mut().set_running(q(id));
        self.as_mut().set_running_name(q(game.map(|g| g.name.as_str()).unwrap_or("")));
        self.as_mut().set_running_known(q(game.and_then(|g| g.known).unwrap_or("")));
        self.as_mut().set_twitch_preset(q(game.map(|g| g.twitch.as_str()).unwrap_or("")));
        self.set_youtube_preset(q(game.map(|g| g.youtube.as_str()).unwrap_or("")));
    }

    /// Detection's news: a game started, ended, or another took its place.
    fn detected(mut self: Pin<&mut Self>, now: Option<String>) {
        let before = self.running().to_string();
        let now = now.unwrap_or_default();
        if before == now {
            return;
        }
        if !now.is_empty() {
            settings::change(|s| s.games.last_played.insert(now.clone(), now_seconds()));
            self.as_mut().rebuild();
        }
        self.as_mut().show_running(&now);
        if !before.is_empty() {
            self.as_mut().stopped(q(&before));
        }
        if !now.is_empty() {
            self.started(q(&now));
        }
    }

    /// Puts own entries and the launchers' games together again, for the
    /// tab and for detection.
    fn rebuild(mut self: Pin<&mut Self>) {
        if demo_mode() {
            return;
        }
        let settings = settings::read(|s| s.games.clone());
        let list = games::compose(&self.rust().scanned, &settings);
        let matcher = Arc::new(Matcher::new(games::watch_list(&list, &settings)));
        *watched().lock().unwrap_or_else(|p| p.into_inner()) = matcher.clone();
        self.as_mut().set_library(q(&library_json(&list, &settings)));
        self.as_mut().rust_mut().watch = matcher;
        // Its presets or name may have changed.
        let running = self.running().to_string();
        if !running.is_empty() {
            self.show_running(&running);
        }
    }

    fn refresh(mut self: Pin<&mut Self>) {
        if *self.scanning() || demo_mode() {
            return;
        }
        self.as_mut().set_scanning(true);
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let scanned = home().map(|h| games::read_library(&h)).unwrap_or_default();
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Games>| {
                obj.as_mut().rust_mut().scanned = scanned;
                obj.as_mut().rebuild();
                obj.set_scanning(false);
            });
        });
    }

    fn launch(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let id = id.to_string();
        let watch = self.rust().watch.clone();
        let Some(game) = watch.games.iter().find(|g| g.id == id) else { return false };
        let started = if game.launcher == "own" {
            let home = home();
            let Some(words) = games::split_command(&game.launch, home.as_deref()) else { return false };
            let (env, words) = games::command_parts(words);
            let Some((program, args)) = words.split_first() else { return false };
            spawn_detached(program, args, &env)
        } else if game.launch.is_empty() {
            false
        } else {
            // The launcher's own address (steam://, lutris:, heroic://).
            spawn_detached("xdg-open", std::slice::from_ref(&game.launch), &[])
        };
        if started && !demo_mode() {
            settings::change(|s| s.games.last_played.insert(id, now_seconds()));
            self.as_mut().rebuild();
        }
        started
    }

    /// An own entry from the fields QML sends; None if the name or the
    /// command is missing.
    fn own_entry(
        id: u32,
        name: &QString,
        command: &QString,
        processes: &QString,
        twitch: &QString,
        youtube: &QString,
        show_on_start: bool,
        radio_on_start: bool,
    ) -> Option<OwnGame> {
        let name = line(name, 80);
        let command = command.to_string().trim().to_string();
        let words = games::split_command(&command, None).unwrap_or_default();
        if name.is_empty() || games::command_parts(words).1.is_empty() {
            return None;
        }
        Some(OwnGame {
            id,
            name,
            processes: games::own_processes(&processes.to_string(), &command),
            command,
            twitch: line(twitch, 100),
            youtube: line(youtube, 100),
            show_on_start,
            radio_on_start,
        })
    }

    fn add_own(
        mut self: Pin<&mut Self>,
        name: &QString,
        command: &QString,
        processes: &QString,
        twitch: &QString,
        youtube: &QString,
        show_on_start: bool,
        radio_on_start: bool,
    ) -> QString {
        let Some(entry) = Self::own_entry(0, name, command, processes, twitch, youtube, show_on_start, radio_on_start) else {
            return QString::default();
        };
        let id = settings::change(|s| {
            let id = s.games.own.iter().map(|o| o.id).max().unwrap_or(0) + 1;
            s.games.own.push(OwnGame { id, ..entry });
            id
        });
        self.as_mut().rebuild();
        q(&format!("own:{id}"))
    }

    fn update_own(
        self: Pin<&mut Self>,
        id: &QString,
        name: &QString,
        command: &QString,
        processes: &QString,
        twitch: &QString,
        youtube: &QString,
        show_on_start: bool,
        radio_on_start: bool,
    ) -> bool {
        let Some(n) = id.to_string().strip_prefix("own:").and_then(|n| n.parse::<u32>().ok()) else { return false };
        let Some(entry) = Self::own_entry(n, name, command, processes, twitch, youtube, show_on_start, radio_on_start) else {
            return false;
        };
        let changed = settings::change(|s| match s.games.own.iter_mut().find(|o| o.id == n) {
            Some(own) => {
                *own = entry;
                true
            }
            None => false,
        });
        if changed {
            self.rebuild();
        }
        changed
    }

    fn remove_own(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let Some(n) = id.strip_prefix("own:").and_then(|n| n.parse::<u32>().ok()) else { return };
        settings::change(|s| {
            s.games.own.retain(|o| o.id != n);
            s.games.hidden.remove(&id);
            s.games.favorites.remove(&id);
            s.games.last_played.remove(&id);
        });
        self.rebuild();
    }

    fn set_options(self: Pin<&mut Self>, id: &QString, twitch: &QString, youtube: &QString, show_on_start: bool, radio_on_start: bool) {
        let id = id.to_string();
        if id.is_empty() {
            return;
        }
        let options = GameOptions { twitch: line(twitch, 100), youtube: line(youtube, 100), show_on_start, radio_on_start };
        settings::change(|s| {
            if let Some(n) = id.strip_prefix("own:").and_then(|n| n.parse::<u32>().ok()) {
                if let Some(own) = s.games.own.iter_mut().find(|o| o.id == n) {
                    own.twitch = options.twitch;
                    own.youtube = options.youtube;
                    own.show_on_start = show_on_start;
                    own.radio_on_start = radio_on_start;
                }
            } else if options == GameOptions::default() {
                s.games.options.remove(&id);
            } else {
                s.games.options.insert(id, options);
            }
        });
        self.rebuild();
    }

    fn hide(self: Pin<&mut Self>, id: &QString, hidden: bool) {
        self.mark(id, hidden, |s| &mut s.hidden);
    }

    fn favorite(self: Pin<&mut Self>, id: &QString, favorite: bool) {
        self.mark(id, favorite, |s| &mut s.favorites);
    }

    /// Puts an id in one of the settings' sets, or takes it out.
    fn mark(self: Pin<&mut Self>, id: &QString, on: bool, set: fn(&mut GamesSettings) -> &mut BTreeSet<String>) {
        let id = id.to_string();
        if id.is_empty() {
            return;
        }
        settings::change(|s| {
            let set = set(&mut s.games);
            if on {
                set.insert(id);
            } else {
                set.remove(&id);
            }
        });
        self.rebuild();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_lists_what_qml_needs() {
        let mut settings = GamesSettings {
            own: vec![OwnGame { id: 1, name: "aion 2".into(), command: "wine a.exe".into(), radio_on_start: true, ..Default::default() }],
            ..Default::default()
        };
        settings.hidden.insert("steam:10".into());
        settings.favorites.insert("own:1".into());
        settings.last_played.insert("steam:10".into(), 1_700_000_000);
        settings.options.insert("steam:10".into(), GameOptions { twitch: "Beta TV".into(), show_on_start: false, ..Default::default() });
        let mut steam = Game::new("steam:10", "Beta", "steam", "steam://rungameid/10");
        steam.steam_appid = Some(10);
        steam.picture = Some("/c/10 a.jpg".into());
        let v: Value = serde_json::from_str(&library_json(&games::compose(&[steam], &settings), &settings)).unwrap();
        assert_eq!(v[0]["id"], "own:1");
        assert_eq!(v[0]["known"], "aion2");
        assert_eq!(v[0]["own"], true);
        assert_eq!(v[0]["fav"], true);
        assert_eq!(v[0]["lastPlayed"], 0);
        assert_eq!(v[0]["command"], "wine a.exe");
        assert_eq!(v[0]["picture"], "");
        assert_eq!(v[0]["twitch"], "AION 2");
        assert_eq!((v[0]["showOnStart"].as_bool(), v[0]["radioOnStart"].as_bool()), (Some(true), Some(true)));
        assert_eq!(v[1]["picture"], "file:///c/10%20a.jpg");
        assert_eq!(v[1]["hidden"], true);
        assert_eq!(v[1]["fav"], false);
        assert_eq!(v[1]["lastPlayed"], 1_700_000_000u64);
        assert_eq!(v[1]["command"], "");
        assert_eq!(v[1]["launcher"], "steam");
        assert_eq!(v[1]["twitch"], "Beta TV");
        assert_eq!(v[1]["youtube"], "");
        assert_eq!(v[1]["showOnStart"], false);
    }
}
