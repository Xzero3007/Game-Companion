//! The Games tab and game detection for QML: the library (read on a worker
//! thread), own entries, starting a game through its launcher, and which
//! game runs now (a look at `/proc` every 3 s on its own thread; QML hears
//! of it only when it changes).

// add_own and update_own take every field of an entry.
#![allow(clippy::too_many_arguments)]

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use std::collections::BTreeSet;

use crate::covers;
use crate::games::{self, Game, GameOptions, GamesSettings, Matcher, OwnGame};
use crate::launch_check;
use crate::launch_demo;
use crate::launch_options::{self, Places};
use crate::protondb;
use crate::settings;
use crate::start_with::{self, StartWith};
use crate::system_info;

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
        /// "showOnStart","radioOnStart","layout","installed","note"}]`,
        /// sorted by name. `installed` false: owned but not installed
        /// (`launch` opens the launcher's install for it), `note` where it
        /// was found ("Known to Steam on this PC", ...).
        #[qproperty(QString, library)]
        /// The tab lists only installed games (settings
        /// `games.installed_only`).
        #[qproperty(bool, installed_only)]
        /// Whether the libraries are being read.
        #[qproperty(bool, scanning)]
        /// Missing covers are downloaded from Steam's, Epic's and GOG's
        /// image servers (settings `games.download_covers`).
        #[qproperty(bool, download_covers)]
        type Games = super::GamesRust;

        /// A missing cover was downloaded: the game's id and its picture
        /// (a file:// address). The library follows when all are done.
        #[qsignal]
        fn cover_arrived(self: Pin<&mut Games>, id: QString, picture: QString);

        /// Switches cover downloads and keeps the choice.
        #[qinvokable]
        fn save_download_covers(self: Pin<&mut Games>, on: bool);

        /// Detection saw a game start (its id).
        #[qsignal]
        fn started(self: Pin<&mut Games>, id: QString);

        /// The game that ran has ended (its id).
        #[qsignal]
        fn stopped(self: Pin<&mut Games>, id: QString);

        /// Reads the launchers' libraries again (in the background).
        #[qinvokable]
        fn refresh(self: Pin<&mut Games>);

        /// Starts a game through its launcher (or an own entry's command),
        /// or for a game that is not installed opens the launcher's install
        /// for it; false if it could not be started.
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

        /// Switches INSTALLED ONLY and keeps the choice.
        #[qinvokable]
        fn save_installed_only(self: Pin<&mut Games>, on: bool);

        /// The saved layout a game loads when it starts ("" = none).
        #[qinvokable]
        fn set_layout(self: Pin<&mut Games>, id: &QString, layout: &QString);

        /// The answer to one of the launch option calls below. Those calls
        /// do their work on a worker thread (they read and write the
        /// launchers' files) and return a request number at once; the
        /// answer comes here with that number, `json` as each call says.
        #[qsignal]
        fn launch_result(self: Pin<&mut Games>, request: i32, json: QString);

        /// A game's launch options as its launcher keeps them, in Steam's
        /// form. Answer: JSON `{"id","launcher","supported","text","env":
        /// [{"name","value"}],"wrappers":[..],"args","file","user","proton":
        /// {"current","label","name","inUse","global","canSet"},"running",
        /// "error"}`: `name` the choice as a protonVersions name ("" =
        /// the launcher's default), `inUse` the build that runs ("" when
        /// unknown), `running` whether the launcher runs now (writes
        /// refuse then).
        #[qinvokable]
        fn launch_options(self: &Games, id: &QString) -> i32;

        /// Options that fit this computer and this game's Proton build,
        /// the current options checked, and what others use (ProtonDB,
        /// Steam games). Answer: JSON `{"suggestions":[{"id","label",
        /// "explanation","option","recommended","why","warning","group",
        /// "applied","flavours":[..],"popular":<usage>|null,"available",
        /// "unavailable_why"}],"context":
        /// {"flavour","label","sure","cachyos"},"check":<as checkOptions>,
        /// "warnings":[..],"others":{"title","reports","export","months",
        /// "source","groups":[{"group","label","reports"}],"proton":
        /// [{"variant","label","count","share"}],"options":[{"kind","name",
        /// "value","text","usage":<usage>,"check":<token>}]}|null}`; one
        /// per group can be on. `<usage>` is `{"count","reports","share",
        /// "similar":[{"group","label","count","reports","share"}],"like":
        /// {..}}` (`like`: the first of this PC's groups, GPU, distro, CPU,
        /// with 5 reports or more, else all reports). `available` false: a
        /// switch this exact build no longer needs or reads (greyed out,
        /// `unavailable_why` says why; combineOptions refuses it). `text`:
        /// the form's options to judge "applied" by ("" = the saved ones).
        #[qinvokable]
        fn suggestions(self: &Games, id: &QString, text: &QString) -> i32;

        /// Checks launch options word by word for the game's Proton build
        /// (`text` "" = the game's current options). Answer: JSON
        /// `{"text","proton":{"flavour","label","sure","cachyos"},"tokens":
        /// [{"text","kind","name","value","status","explanation","note",
        /// "warning","replacement","fix","source","flags":[{"flag","status",
        /// "note","suggestion"}]}],"problems":[{"kind","message","name"}],
        /// "summary":{"ok",..},"fixed","error"}`. status: ok, outdated,
        /// invalid, no_effect, not_recommended, unknown; fix: the word's
        /// replacement ("" = take it out) or null; fixed: the whole text
        /// with every fix ("" when none or not safely possible). Only the
        /// newest check's answer is sent: an older request still waiting
        /// or running when a newer one comes gets no launchResult.
        #[qinvokable]
        fn check_options(self: &Games, id: &QString, text: &QString) -> i32;

        /// The game's launch options with the suggestions in `chosen` (a
        /// JSON list of ids: the ones to have on; applied ones left out are
        /// taken out) put into its text, not written. Answer: JSON
        /// `{"text","error"}` (text too complex to change, or an unavailable
        /// suggestion chosen to be added, is refused in "error", with the
        /// text as it was). `text`: the form's options to start from, so
        /// unsaved edits stay ("" = the saved ones).
        #[qinvokable]
        fn combine_options(self: &Games, id: &QString, chosen: &QString, text: &QString) -> i32;

        /// Writes a game's launch options (Steam's form) to its launcher's
        /// file, or an own entry's command. Answer: JSON `{"error"}`, ""
        /// when done, else why not (e.g. "Close Steam first").
        #[qinvokable]
        fn set_launch_options(self: &Games, id: &QString, text: &QString) -> i32;

        /// The Proton and Wine builds installed, as last read (`refresh`
        /// reads the folders again). Answer: JSON `[{"name","label","path",
        /// "source","kind","launchers"}]`.
        #[qinvokable]
        fn proton_versions(self: &Games, refresh: bool) -> i32;

        /// Sets a game's Proton or Wine build by its `name` ("" = Steam's
        /// default). Answer: JSON `{"error","warning"}`: error "" when done;
        /// warning for the user (Heroic: moving between Wine and Proton
        /// changes the game's prefix), else "".
        #[qinvokable]
        fn set_proton(self: &Games, id: &QString, name: &QString) -> i32;

        /// Whether the game's launcher runs now (it writes its settings when
        /// it quits, undoing a change). Answer: JSON `{"running"}`.
        #[qinvokable]
        fn launcher_state(self: &Games, id: &QString) -> i32;

        /// The Proton overview: the builds installed and which build each
        /// of these games (`ids`, a JSON list) uses. Answer: JSON `{"tools":
        /// [as protonVersions],"steamDefault","games":[{"id","launcher",
        /// "choice","inUse","proton","canSet"}]}` with the games that run
        /// through Proton or Wine (`choice` "" = the launcher's default,
        /// `inUse` the build that runs, "" when unknown); own entries are
        /// left out.
        #[qinvokable]
        fn proton_overview(self: &Games, ids: &QString) -> i32;

        /// This computer as the suggestions see it. Answer: JSON `{"gpus":
        /// [{"vendor","driver","card"}],"nvidiaVersion","cpu","threads",
        /// "ramMb","kernel","tools":[..],"session","desktop","ntsync",
        /// "display":{"name","width","height","refresh","hdr"}|null,
        /// "hdrLayer","os","osLike":[..],"cachyos","cpuVendor","ananicy",
        /// "displayCard"}`.
        #[qinvokable]
        fn system_info(self: &Games) -> i32;

        /// What starts with a game: JSON `{"entries":[{"id","name","command",
        /// "on","close","running"}],"starters":[{"file","name","about","on",
        /// "path","content"}]}` (starters: what other programs left in the
        /// desktop's autostart for this game, `start_with::STARTERS`).
        #[qinvokable]
        fn start_with(self: &Games, id: &QString) -> QString;

        /// Adds a program to a game's list; false if its command can't start.
        #[qinvokable]
        fn add_start_with(self: &Games, id: &QString, name: &QString, command: &QString, close: bool, delay: i32) -> bool;

        /// Changes a program in a game's list (by its number).
        #[qinvokable]
        fn update_start_with(self: &Games, id: &QString, entry: i32, name: &QString, command: &QString, on: bool, close: bool, delay: i32) -> bool;

        /// Removes a program from a game's list.
        #[qinvokable]
        fn remove_start_with(self: &Games, id: &QString, entry: i32);

        /// Empties a game's list.
        #[qinvokable]
        fn clear_start_with(self: &Games, id: &QString);

        /// Switches another program's starter off (its autostart file put
        /// aside) or on again; false if that did not work.
        #[qinvokable]
        fn set_starter(self: &Games, file: &QString, on: bool) -> bool;

        /// Removes another program's starter for good.
        #[qinvokable]
        fn remove_starter(self: &Games, file: &QString) -> bool;

        /// The desktop's programs to pick from: JSON `[{"name","command","icon"}]`.
        #[qinvokable]
        fn programs(self: &Games) -> QString;
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
    installed_only: bool,
    scanning: bool,
    download_covers: bool,
    /// The library as last put together (own entries, the launchers'
    /// games, installed or not).
    composed: Vec<Game>,
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
            installed_only: settings::read(|s| s.games.installed_only),
            scanning: false,
            download_covers: settings::read(|s| s.games.download_covers),
            composed: Vec::new(),
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

/// The launchers' and the system's places on this computer.
fn places() -> Option<Places> {
    Some(Places { home: home()?, root: PathBuf::from("/"), proc_root: PathBuf::from("/proc") })
}

/// An own entry's command line (None for other games).
fn own_command(id: &str) -> Option<String> {
    let n = id.strip_prefix("own:")?.parse::<u32>().ok()?;
    settings::read(|s| s.games.own.iter().find(|o| o.id == n).map(|o| o.command.clone()))
}

/// This computer, read now (a few small files; nothing is run).
fn system() -> system_info::SystemInfo {
    if demo_mode() {
        return launch_demo::system();
    }
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| home().map(|h| h.join(".config")))
        .unwrap_or_default();
    let screen = settings::read(|s| s.screen.clone());
    system_info::detect(Path::new("/"), &config, &|k| std::env::var(k).ok(), &screen)
}

/// A worker's answer for `launch_result`; `rebuild` puts the library
/// together again first (an own entry changed).
struct Answer {
    json: String,
    rebuild: bool,
    /// A newer request of the same kind came: send nothing.
    stale: bool,
}

impl Answer {
    fn json(value: Value) -> Self {
        Answer { json: value.to_string(), rebuild: false, stale: false }
    }

    fn stale() -> Self {
        Answer { json: String::new(), rebuild: false, stale: true }
    }
}

/// The newest request of one kind, so older answers can be dropped.
struct Newest(AtomicU64);

impl Newest {
    const fn new() -> Self {
        Newest(AtomicU64::new(0))
    }

    /// A new request: its generation.
    fn begin(&self) -> u64 {
        self.0.fetch_add(1, Ordering::Relaxed) + 1
    }

    fn is_newest(&self, generation: u64) -> bool {
        self.0.load(Ordering::Relaxed) == generation
    }
}

/// The Proton and Wine builds installed, read once and kept until asked
/// to read them again (`refresh`).
fn tools(places: &Places, refresh: bool) -> Arc<Vec<launch_options::Tool>> {
    if demo_mode() {
        return Arc::new(launch_demo::tools());
    }
    static TOOLS: Mutex<Option<Arc<Vec<launch_options::Tool>>>> = Mutex::new(None);
    let mut kept = TOOLS.lock().unwrap_or_else(|p| p.into_inner());
    match kept.as_ref() {
        Some(list) if !refresh => list.clone(),
        _ => {
            let list = Arc::new(launch_options::all_tools(places));
            *kept = Some(list.clone());
            list
        }
    }
}

/// A game's launch options as its launcher keeps them (the demo's made-up
/// ones in demo mode).
fn current(places: &Places, id: &str) -> launch_options::Current {
    if demo_mode() {
        return launch_demo::current(id, own_command(id).as_deref());
    }
    launch_options::read(places, id, own_command(id).as_deref())
}

/// Whether the game's launcher runs now.
fn launcher_running(places: &Places, launcher: &str) -> bool {
    if demo_mode() {
        return launcher == "steam" && launch_demo::launcher_running();
    }
    launch_options::launcher_running(places, launcher)
}

/// Changes an own entry's command; its process names are guessed again
/// from the new command, as when adding one, unless the user typed their
/// own. False if there is no such entry.
fn set_own_command(games: &mut GamesSettings, n: u32, command: String) -> bool {
    let Some(own) = games.own.iter_mut().find(|o| o.id == n) else { return false };
    let guessed = own.processes.is_empty() || own.processes == games::own_processes("", &own.command);
    if guessed {
        own.processes = games::own_processes("", &command);
    }
    own.command = command;
    true
}

fn now_seconds() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Whether the cover thread runs, and whether it may go on (the switch).
static COVERS_RUNNING: AtomicBool = AtomicBool::new(false);
static COVERS_ON: AtomicBool = AtomicBool::new(false);

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
                "layout": settings.layouts.get(&g.id).cloned().unwrap_or_default(),
                "installed": g.installed,
                "note": g.note,
            })
        })
        .collect();
    Value::Array(list).to_string()
}

/// A game's programs to start with it (settings `games.start_with`).
fn start_with_list(id: &str) -> Vec<StartWith> {
    if demo_mode() {
        return Vec::new();
    }
    settings::read(|s| s.games.start_with.get(id).cloned().unwrap_or_default())
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
        let not_installed = |id: &str, name: &str, launcher: &str, note: &str| {
            let mut game = Game::new(id, name, launcher, "");
            game.installed = false;
            game.note = note.into();
            game
        };
        let mut scanned = vec![
            Game::new("steam:2694490", "Path of Exile 2", "steam", ""),
            Game::new("steam:1000001", "Space Game", "steam", ""),
            Game::new(launch_demo::RACER, "Forza Horizon 6", "steam", ""),
            Game::new("lutris:3", "Dungeon Crawler", "lutris", ""),
            Game::new("heroic:legendary:demo", "Racing Game", "heroic", ""),
            Game::new("heroic:gog:1207", "Old Adventure", "heroic", ""),
            not_installed("steam:1000002", "Castle Builder", "steam", "Known to Steam on this PC"),
            not_installed("steam:1000003", "Night Racer", "steam", "Known to Steam on this PC"),
            not_installed("heroic:legendary:free1", "Free Weekly Puzzle", "heroic", ""),
            not_installed("heroic:gog:1208", "Pixel Knights", "heroic", ""),
            not_installed("heroic:nile:amz1", "Harbor Tales", "heroic", ""),
            not_installed("lutris:gog:42", "Starfield Drifter", "lutris", "In Lutris's GOG library"),
        ];
        // Made-up covers for screenshots: GC_DEMO_PICTURES=<folder> with
        // "<id, ':' as '_'>.png" files.
        if let Some(dir) = std::env::var_os("GC_DEMO_PICTURES").map(PathBuf::from) {
            for game in &mut scanned {
                let file = dir.join(format!("{}.png", game.id.replace(':', "_")));
                game.picture = file.is_file().then_some(file);
            }
        }
        let mut settings = GamesSettings {
            own: vec![OwnGame { id: 1, name: "AION 2".into(), command: "wine ~/Games/aion2/AION2.exe".into(), ..Default::default() }],
            ..Default::default()
        };
        settings.hidden.insert("heroic:gog:1207".into());
        settings.favorites.insert("own:1".into());
        settings.last_played.insert("own:1".into(), now_seconds());
        settings.last_played.insert("steam:2694490".into(), now_seconds().saturating_sub(86_400));
        settings.last_played.insert(launch_demo::RACER.into(), now_seconds().saturating_sub(3 * 86_400));
        let list = games::compose(&scanned, &settings);
        self.as_mut().set_library(q(&library_json(&list, &settings)));
        self.as_mut().rust_mut().watch = Arc::new(Matcher::new(games::watch_list(&list, &settings)));
        self.as_mut().rust_mut().composed = list;
        if std::env::var("GC_DEMO").is_ok_and(|d| d.contains("installedonly")) {
            self.as_mut().set_installed_only(true);
        }
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
            let game = before.clone();
            start_with::game_stopped(&before, move || start_with_list(&game));
            self.as_mut().stopped(q(&before));
        }
        if !now.is_empty() {
            start_with::game_started(&now, &start_with_list(&now), home().as_deref());
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
        self.as_mut().rust_mut().composed = list;
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
            let mut scanned = home().map(|h| games::read_library(&h)).unwrap_or_default();
            covers::fill_cached(&mut scanned, &covers::dir());
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Games>| {
                obj.as_mut().rust_mut().scanned = scanned;
                obj.as_mut().rebuild();
                obj.as_mut().set_scanning(false);
                obj.start_covers();
            });
        });
    }

    fn launch(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let id = id.to_string();
        let watch = self.rust().watch.clone();
        let game = match watch.games.iter().find(|g| g.id == id) {
            Some(game) => game.clone(),
            // Not watched: a game that is not installed (its address opens
            // the launcher's install).
            None => match self.rust().composed.iter().find(|g| g.id == id && !g.installed) {
                Some(game) => game.clone(),
                None => return false,
            },
        };
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
        if started && game.installed && !demo_mode() {
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
            // Its programs go with it.
            s.games.start_with.remove(&id);
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

    fn set_layout(self: Pin<&mut Self>, id: &QString, layout: &QString) {
        let id = id.to_string();
        if id.is_empty() {
            return;
        }
        let layout = line(layout, 80);
        settings::change(|s| {
            if layout.is_empty() {
                s.games.layouts.remove(&id);
            } else {
                s.games.layouts.insert(id, layout);
            }
        });
        self.rebuild();
    }

    /// Runs a launch option job on a worker thread (one at a time, in the
    /// order asked) and sends its answer with `launch_result`.
    fn work(&self, job: impl FnOnce() -> Answer + Send + 'static) -> i32 {
        static NEXT: AtomicI32 = AtomicI32::new(1);
        static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
        let request = NEXT.fetch_add(1, Ordering::Relaxed);
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new().name("launch-options".into()).spawn(move || {
            let answer = {
                let _turn = ONE_AT_A_TIME.lock().unwrap_or_else(|p| p.into_inner());
                job()
            };
            if answer.stale {
                return;
            }
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Games>| {
                if answer.rebuild {
                    obj.as_mut().rebuild();
                }
                obj.launch_result(request, q(&answer.json));
            });
        });
        if spawned.is_err() {
            return -1;
        }
        request
    }

    fn launch_options(&self, id: &QString) -> i32 {
        let id = id.to_string();
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!({"id": id, "supported": false, "error": "No home folder"})) };
            let current = current(&places, &id);
            let mut answer = current.to_json(&id, &tools(&places, false));
            answer["running"] = json!(current.supported && launcher_running(&places, &current.launcher));
            Answer::json(answer)
        })
    }

    fn suggestions(&self, id: &QString, text: &QString) -> i32 {
        let id = id.to_string();
        let text = text.to_string();
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!({"suggestions": [], "warnings": [], "others": null})) };
            let current = current(&places, &id).with_text(&text);
            if !current.supported {
                return Answer::json(json!({"suggestions": [], "warnings": [], "others": null}));
            }
            let pdb = launch_options::steam_appid(&id).and_then(|appid| protondb::load(&protondb::data_path()?, appid));
            let mut answer = launch_check::suggestions_answer(&system(), &current, &tools(&places, false), pdb);
            if demo_mode() {
                launch_demo::add_unavailable(&mut answer);
            }
            Answer::json(answer)
        })
    }

    fn check_options(&self, id: &QString, text: &QString) -> i32 {
        // Rapid checks (typing): only the newest is worked out and answered.
        static CHECKS: Newest = Newest::new();
        let generation = CHECKS.begin();
        let stale = move || !CHECKS.is_newest(generation);
        let id = id.to_string();
        let text = text.to_string();
        self.work(move || {
            if stale() {
                return Answer::stale();
            }
            let Some(places) = places() else { return Answer::json(json!({"error": "No home folder"})) };
            let current = current(&places, &id);
            let text = if text.trim().is_empty() { current.text.clone() } else { text };
            let ctx = launch_check::context(&system(), &current, &tools(&places, false));
            let answer = Answer::json(launch_check::check(&text, &ctx).to_json(&text));
            if stale() {
                Answer::stale()
            } else {
                answer
            }
        })
    }

    fn combine_options(&self, id: &QString, chosen: &QString, text: &QString) -> i32 {
        let id = id.to_string();
        let chosen: Vec<String> = serde_json::from_str(&chosen.to_string()).unwrap_or_default();
        let text = text.to_string();
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!({"text": "", "error": "No home folder"})) };
            let current = current(&places, &id).with_text(&text);
            let result = if current.supported {
                let list = launch_options::suggest(&system(), &current, &tools(&places, false));
                launch_options::combine(&current, &list, &chosen)
            } else {
                Err(current.error.clone())
            };
            Answer::json(match result {
                Ok(text) => json!({"text": text, "error": ""}),
                Err(e) => json!({"text": current.text, "error": e}),
            })
        })
    }

    fn set_launch_options(&self, id: &QString, text: &QString) -> i32 {
        let id = id.to_string();
        let text = text.to_string();
        let error = |e: &str| Answer::json(json!({"error": e}));
        self.work(move || {
            if demo_mode() {
                return error("Not in the demo");
            }
            if let Some(n) = id.strip_prefix("own:").and_then(|n| n.parse::<u32>().ok()) {
                let command = text.trim().to_string();
                if let Err(e) = launch_options::parse_own(&command) {
                    return error(&e);
                }
                if !settings::change(|s| set_own_command(&mut s.games, n, command)) {
                    return error("This game was not found");
                }
                return Answer { json: json!({"error": ""}).to_string(), rebuild: true, stale: false };
            }
            let Some(places) = places() else { return error("No home folder") };
            match launch_options::write(&places, &id, &text, now_seconds()) {
                Ok(()) => error(""),
                Err(e) => error(&e),
            }
        })
    }

    fn proton_versions(&self, refresh: bool) -> i32 {
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!([])) };
            Answer { json: launch_options::tools_json(&tools(&places, refresh)), rebuild: false, stale: false }
        })
    }

    fn set_proton(&self, id: &QString, name: &QString) -> i32 {
        let id = id.to_string();
        let name = name.to_string().trim().to_string();
        self.work(move || {
            let answer = |error: &str, warning: &str| Answer::json(json!({"error": error, "warning": warning}));
            if demo_mode() {
                // Shows how a warning looks: Heroic between Wine and Proton.
                let warning = if id.starts_with("heroic:") { launch_options::PREFIX_WARNING } else { "" };
                return answer("", warning);
            }
            let Some(places) = places() else { return answer("No home folder", "") };
            let mut list = tools(&places, false);
            if !name.is_empty() && !list.iter().any(|t| t.name == name) {
                // Installed since the list was read?
                list = tools(&places, true);
            }
            match launch_options::set_tool(&places, &list, &id, &name, now_seconds()) {
                Ok(warning) => answer("", &warning),
                Err(e) => answer(&e, ""),
            }
        })
    }

    fn launcher_state(&self, id: &QString) -> i32 {
        let id = id.to_string();
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!({"running": false})) };
            let launcher = if launch_options::steam_appid(&id).is_some() {
                "steam"
            } else {
                id.split(':').next().unwrap_or("")
            };
            Answer::json(json!({"running": launcher_running(&places, launcher)}))
        })
    }

    fn proton_overview(&self, ids: &QString) -> i32 {
        let ids: Vec<String> = serde_json::from_str(&ids.to_string()).unwrap_or_default();
        self.work(move || {
            let Some(places) = places() else { return Answer::json(json!({"tools": [], "steamDefault": "", "games": []})) };
            let list = tools(&places, false);
            let (games, steam_default) = if demo_mode() {
                (ids.iter().map(|id| (id.clone(), launch_demo::current(id, None))).collect(), launch_demo::STEAM_DEFAULT.to_string())
            } else {
                launch_options::tool_choices(&places, &ids)
            };
            Answer::json(launch_options::usage_json(&games, &list, &steam_default))
        })
    }

    fn system_info(&self) -> i32 {
        self.work(|| Answer { json: system().to_json().to_string(), rebuild: false, stale: false })
    }

    /// Downloads the missing covers one after another on a worker thread
    /// (when allowed: the switch, no demo, no GC_NO_COVER_DOWNLOADS); each
    /// one arriving goes to QML at once, the library once at the end.
    fn start_covers(self: Pin<&mut Self>) {
        let on = covers::allowed_now(*self.download_covers()) && !demo_mode();
        COVERS_ON.store(on, Ordering::Relaxed);
        if !on {
            return;
        }
        let mut jobs: Vec<Game> =
            self.rust().scanned.iter().filter(|g| g.picture.is_none() && !covers::candidates(g).is_empty()).cloned().collect();
        if jobs.is_empty() || COVERS_RUNNING.swap(true, Ordering::AcqRel) {
            return;
        }
        // Installed games first.
        jobs.sort_by_key(|g| !g.installed);
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new().name("covers".into()).spawn(move || {
            let dir = covers::dir();
            let mut any = false;
            for game in jobs {
                if !COVERS_ON.load(Ordering::Relaxed) {
                    break;
                }
                match covers::download(&game, &dir, now_seconds(), &covers::fetch_with_curl) {
                    covers::Outcome::Saved(path) => {
                        any = true;
                        let id = game.id.clone();
                        let _ = thread.queue(move |obj: Pin<&mut qobject::Games>| obj.cover_saved(id, path));
                    }
                    covers::Outcome::Offline => break,
                    covers::Outcome::Skipped => continue,
                    covers::Outcome::Failed => {}
                }
                std::thread::sleep(covers::GAP);
            }
            COVERS_RUNNING.store(false, Ordering::Release);
            if any {
                let _ = thread.queue(|obj: Pin<&mut qobject::Games>| obj.rebuild());
            }
        });
        if spawned.is_err() {
            COVERS_RUNNING.store(false, Ordering::Release);
        }
    }

    /// A downloaded cover: kept with the game, and its card told.
    fn cover_saved(mut self: Pin<&mut Self>, id: String, path: PathBuf) {
        if let Some(game) = self.as_mut().rust_mut().scanned.iter_mut().find(|g| g.id == id) {
            game.picture = Some(path.clone());
        }
        if let Some(game) = self.as_mut().rust_mut().composed.iter_mut().find(|g| g.id == id) {
            game.picture = Some(path.clone());
        }
        self.cover_arrived(q(&id), q(&games::file_url(&path)));
    }

    fn save_download_covers(mut self: Pin<&mut Self>, on: bool) {
        if demo_mode() {
            self.set_download_covers(on);
            return;
        }
        settings::change(|s| s.games.download_covers = on);
        self.as_mut().set_download_covers(on);
        self.start_covers();
    }

    fn save_installed_only(self: Pin<&mut Self>, on: bool) {
        if !demo_mode() {
            settings::change(|s| s.games.installed_only = on);
        }
        self.set_installed_only(on);
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

impl qobject::Games {
    fn start_with(&self, id: &QString) -> QString {
        let id = id.to_string();
        let running = start_with::running_entries(&id);
        let entries: Vec<Value> = if demo_mode() {
            start_with_demo(&id)
        } else {
            start_with_list(&id)
                .into_iter()
                .map(|e| {
                    json!({"id": e.id, "name": e.name, "command": e.command, "on": e.on, "close": e.close,
                           "delay": e.delay, "running": running.contains(&e.id)})
                })
                .collect()
        };
        let known = self.rust().composed.iter().find(|g| g.id == id).and_then(|g| g.known).unwrap_or("");
        let starters = if demo_mode() { start_with_demo_starters(known) } else { start_with::starters_json(known) };
        q(&json!({ "entries": entries, "starters": starters }).to_string())
    }

    fn add_start_with(&self, id: &QString, name: &QString, command: &QString, close: bool, delay: i32) -> bool {
        let (id, name, command) = (id.to_string(), line(name, 80), line(command, 400));
        if id.is_empty() || !start_with::valid_command(&command) {
            return false;
        }
        settings::change(|s| {
            let list = s.games.start_with.entry(id).or_default();
            let next = list.iter().map(|e| e.id).max().unwrap_or(0) + 1;
            let name = if name.is_empty() { command.clone() } else { name };
            let delay = clamp_delay(delay);
            list.push(StartWith { id: next, name, command, on: true, close, delay });
        });
        true
    }

    fn update_start_with(&self, id: &QString, entry: i32, name: &QString, command: &QString, on: bool, close: bool, delay: i32) -> bool {
        let (id, name, command) = (id.to_string(), line(name, 80), line(command, 400));
        if !start_with::valid_command(&command) {
            return false;
        }
        let Ok(entry) = u32::try_from(entry) else { return false };
        settings::change(|s| {
            let Some(e) = s.games.start_with.get_mut(&id).and_then(|l| l.iter_mut().find(|e| e.id == entry)) else {
                return false;
            };
            e.name = if name.is_empty() { command.clone() } else { name };
            e.command = command;
            e.on = on;
            e.close = close;
            e.delay = clamp_delay(delay);
            true
        })
    }

    fn remove_start_with(&self, id: &QString, entry: i32) {
        let id = id.to_string();
        let Ok(entry) = u32::try_from(entry) else { return };
        settings::change(|s| {
            if let Some(list) = s.games.start_with.get_mut(&id) {
                list.retain(|e| e.id != entry);
                if list.is_empty() {
                    s.games.start_with.remove(&id);
                }
            }
        });
    }

    fn clear_start_with(&self, id: &QString) {
        let id = id.to_string();
        settings::change(|s| s.games.start_with.remove(&id));
    }

    fn set_starter(&self, file: &QString, on: bool) -> bool {
        !demo_mode() && start_with::set_starter(&file.to_string(), on)
    }

    fn remove_starter(&self, file: &QString) -> bool {
        !demo_mode() && start_with::remove_starter(&file.to_string())
    }

    fn programs(&self) -> QString {
        if demo_mode() {
            return q(&json!([
                {"name": "Discord", "command": "discord", "icon": "discord"},
                {"name": "OBS Studio", "command": "obs", "icon": "com.obsproject.Studio"},
                {"name": "TeamSpeak", "command": "teamspeak3", "icon": "teamspeak3"},
            ])
            .to_string());
        }
        q(&start_with::programs_json().to_string())
    }
}

fn clamp_delay(delay: i32) -> u32 {
    u32::try_from(delay).unwrap_or(start_with::GONE_FOR).min(start_with::LONGEST_DELAY)
}

/// Screenshots (GC_DEMO=games,startwith): a made-up list for AION 2.
fn start_with_demo(id: &str) -> Vec<Value> {
    if id != "own:1" {
        return Vec::new();
    }
    vec![
        json!({"id": 1, "name": "Discord", "command": "discord --start-minimized", "on": true, "close": false, "delay": 10, "running": true}),
        json!({"id": 2, "name": "OBS Studio", "command": "obs --minimize-to-tray", "on": false, "close": true, "delay": 30, "running": false}),
    ]
}

fn start_with_demo_starters(known: &str) -> Value {
    let Some(s) = start_with::STARTERS.iter().find(|s| s.game == known) else { return json!([]) };
    json!([{
        "file": s.file, "name": s.name, "about": s.about, "on": true,
        "takeName": s.takes_over.0, "takeCommand": s.takes_over.1,
        "path": format!("~/.config/autostart/{}", s.file),
        "content": "[Desktop Entry]\nType=Application\nName=A2Tools DPS Meter: start with AION2\nComment=Starts the meter when AION2 starts. Turn it off in the meter's Settings.\nExec=\"/usr/bin/a2tools-game-watch\"\nIcon=a2tools-dps-meter\nNoDisplay=true\nTerminal=false\nX-GNOME-Autostart-enabled=true\n",
    }])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_newest_check_counts() {
        let checks = Newest::new();
        let first = checks.begin();
        assert!(checks.is_newest(first));
        let second = checks.begin();
        assert!(!checks.is_newest(first) && checks.is_newest(second));
        assert!(Answer::stale().stale && !Answer::json(json!({})).stale);
    }

    #[test]
    fn own_command_change_guesses_processes_again() {
        let mut settings = GamesSettings {
            own: vec![
                OwnGame { id: 1, name: "A".into(), command: "wine ~/a/A.exe".into(), processes: vec!["A.exe".into()], ..Default::default() },
                OwnGame { id: 2, name: "B".into(), command: "wine ~/b/B.exe".into(), processes: vec!["mine".into()], ..Default::default() },
            ],
            ..Default::default()
        };
        assert_eq!(games::own_processes("", "wine ~/a/A.exe"), ["A.exe"]);
        assert!(set_own_command(&mut settings, 1, "gamemoderun wine ~/a/A2.exe".into()));
        assert_eq!(settings.own[0].processes, games::own_processes("", "gamemoderun wine ~/a/A2.exe"));
        assert_eq!(settings.own[0].command, "gamemoderun wine ~/a/A2.exe");
        // Typed by the user: kept.
        assert!(set_own_command(&mut settings, 2, "wine ~/b/C.exe".into()));
        assert_eq!(settings.own[1].processes, ["mine"]);
        assert!(!set_own_command(&mut settings, 9, "x".into()));
    }

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
        assert_eq!((v[1]["installed"].as_bool(), v[1]["note"].as_str()), (Some(true), Some("")));
    }
}
