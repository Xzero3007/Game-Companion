//! Brave and Legcord for QML (the `Apps` singleton): the bar's buttons and
//! menus, the shortcuts and Settings → Apps. The work with KWin is in
//! `apps`; every KWin call runs on one worker thread (it waits for KWin),
//! never on the UI thread.

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::mpsc::{channel, Sender};
use std::sync::Arc;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::apps::{self, AppDef, Before, Event, Kwin, Place, Win, APPS};
use crate::{settings, start_with};

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
        /// Each app's state as JSON: `{"available", "apps": {"<id>":
        /// {"name","running","shown","starting","windows","program",
        /// "opacity","withGame","closeOnQuit","command","why"}}}`.
        #[qproperty(QString, state)]
        type Apps = super::AppsRust;

        /// Connects to KWin and starts watching (once, from Main).
        #[qinvokable]
        fn begin(self: Pin<&mut Apps>);

        /// The bar's button or the shortcut: shows the app over the game on
        /// `output` (the overlay's screen), or hides it again; starts it if
        /// it does not run.
        #[qinvokable]
        fn toggle(self: Pin<&mut Apps>, id: &QString, output: &QString);

        /// Opacity over the game, 20 to 100 %.
        #[qinvokable]
        fn set_opacity(self: Pin<&mut Apps>, id: &QString, percent: i32);

        /// Uses the app's next window (it has several).
        #[qinvokable]
        fn next_window(self: Pin<&mut Apps>, id: &QString, output: &QString);

        /// Closes the app's window (as its own close button would).
        #[qinvokable]
        fn close_window(self: Pin<&mut Apps>, id: &QString);

        /// The command line that starts it ("" = find it).
        #[qinvokable]
        fn set_command(self: Pin<&mut Apps>, id: &QString, command: &QString);

        #[qinvokable]
        fn set_with_game(self: Pin<&mut Apps>, id: &QString, on: bool);

        #[qinvokable]
        fn set_close_on_quit(self: Pin<&mut Apps>, id: &QString, on: bool);

        /// "Stay over a full-screen game" on or off.
        #[qinvokable]
        fn set_over_full(self: Pin<&mut Apps>, on: bool);

        /// Forgets the place over the game (the next show uses the first one).
        #[qinvokable]
        fn forget_place(self: Pin<&mut Apps>, id: &QString);

        /// A game started (`game`: its built-in key, or ""): apps set to
        /// start with it start (not shown).
        #[qinvokable]
        fn game_started(self: Pin<&mut Apps>, game: &QString);

        /// The game ended: every window Game Companion moved goes back to
        /// where and how it was.
        #[qinvokable]
        fn game_stopped(self: Pin<&mut Apps>);
    }

    impl cxx_qt::Threading for Apps {}
}

/// What is known about one app.
#[derive(Default)]
struct AppState {
    /// Its windows, oldest first.
    windows: Vec<Win>,
    /// The window it uses (the last one active, or picked by "next").
    chosen: String,
    /// The window shown over the game ("" when not shown) and on which screen.
    shown: String,
    output: String,
    /// Started and waiting for its window, to show it then.
    starting: bool,
    starting_run: u64,
    why: String,
}

/// A KWin call for the worker thread.
type Job = Box<dyn FnOnce(&Kwin) + Send>;

pub struct AppsRust {
    state: QString,
    apps: HashMap<&'static str, AppState>,
    /// The last normal window with the focus that is no app's (the game).
    other: String,
    other_win: Option<Win>,
    /// How often the game took its full screen back since the last show
    /// (it gives up after a few and the apps are minimised as before).
    refulls: u32,
    available: bool,
    work: Option<Sender<Job>>,
    demo: bool,
}

impl Default for AppsRust {
    fn default() -> Self {
        let demo = std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "apps"));
        let mut me = Self {
            state: QString::default(),
            apps: APPS.iter().map(|a| (a.id, AppState::default())).collect(),
            other: String::new(),
            other_win: None,
            refulls: 0,
            available: false,
            work: None,
            demo,
        };
        if demo {
            // Screenshots: Brave shown, Legcord running behind the game.
            let win = |id: &str| Win { id: id.into(), normal: true, ..Default::default() };
            if let Some(b) = me.apps.get_mut("brave") {
                b.windows = vec![win("{b1}"), win("{b2}")];
                b.chosen = "{b1}".into();
                b.shown = "{b1}".into();
            }
            if let Some(l) = me.apps.get_mut("legcord") {
                l.windows = vec![win("{l1}")];
            }
            // `apps,pob`: Path of Building running too (its button shows).
            if std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "pob")) {
                if let Some(p) = me.apps.get_mut("pob") {
                    p.windows = vec![win("{p1}")];
                }
            }
            me.available = true;
        }
        me.state = QString::from(&me.state_json());
        me
    }
}

impl AppsRust {
    fn state_json(&self) -> String {
        let mut apps = serde_json::Map::new();
        for app in &APPS {
            let s = &self.apps[app.id];
            let choice = apps::choice(app.id);
            let alive = || {
                let started = apps::runtime(|r| r.started.get(app.id).copied());
                started.is_some_and(|(pid, start)| start_with::program_alive(pid, start))
            };
            apps.insert(
                app.id.into(),
                json!({
                    "name": app.name,
                    "running": !s.windows.is_empty() || alive(),
                    "shown": !s.shown.is_empty(),
                    "starting": s.starting,
                    "windows": s.windows.len(),
                    "program": apps::command_for(app, &choice).unwrap_or_default(),
                    "command": choice.command,
                    "opacity": choice.opacity,
                    "withGame": choice.with_game,
                    "closeOnQuit": choice.close_on_quit,
                    "placed": choice.place.is_some(),
                    "why": s.why,
                }),
            );
        }
        let over_full = crate::settings::read(|s| s.apps_over_full);
        json!({ "available": self.available, "overFull": over_full, "apps": Value::Object(apps) }).to_string()
    }
}

fn find(id: &str) -> Option<&'static AppDef> {
    apps::def(id)
}

/// The app a window belongs to.
fn owner(win: &Win) -> Option<&'static AppDef> {
    APPS.iter().find(|a| apps::belongs(a, win))
}

fn save_choice(id: &str, f: impl FnOnce(&mut apps::AppChoice)) {
    settings::change(|s| f(s.apps.entry(id.to_string()).or_default()));
}

impl qobject::Apps {
    fn refresh(mut self: Pin<&mut Self>) {
        // No app shown any more: the game gets its full screen back.
        if self.rust().apps.values().all(|s| s.shown.is_empty()) {
            if let Some(id) = apps::runtime(|r| r.unfull.take()) {
                self.as_mut().rust_mut().refulls = 0;
                self.kwin(move |k| {
                    let _ = k.run(&apps::refull_body(&id));
                });
            }
        }
        let json = self.rust().state_json();
        self.as_mut().set_state(QString::from(&json));
    }

    /// Hands a KWin call to the worker thread.
    fn kwin(&self, job: impl FnOnce(&Kwin) + Send + 'static) {
        if let Some(work) = &self.rust().work {
            let _ = work.send(Box::new(job));
        }
    }

    /// Whether an app is shown on screen `out` ("" = any).
    fn shown_on(&self, out: &str) -> bool {
        self.rust().apps.values().any(|s| !s.shown.is_empty() && s.windows.iter().any(|w| w.id == s.shown && (out.is_empty() || w.out == out)))
    }

    /// Keeps the shown apps over a game in full screen by taking its
    /// full-screen mark off (`apps`); false when that is off or the game
    /// keeps taking it back.
    fn keep_over(mut self: Pin<&mut Self>, game: &Win) -> bool {
        if !crate::settings::read(|s| s.apps_over_full) || self.rust().refulls >= 5 {
            return false;
        }
        if apps::runtime(|r| r.unfull.as_deref() == Some(game.id.as_str())) {
            self.as_mut().rust_mut().refulls += 1;
        }
        let id = game.id.clone();
        apps::runtime(|r| r.unfull = Some(id.clone()));
        if let Some(w) = self.as_mut().rust_mut().other_win.as_mut().filter(|w| w.id == id) {
            w.full = false;
        }
        self.kwin(move |k| {
            let _ = k.run(&apps::unfull_body(&id));
        });
        true
    }

    fn begin(mut self: Pin<&mut Self>) {
        if self.rust().work.is_some() || self.rust().demo || !apps::on_kde() || std::env::var_os("WAYLAND_DISPLAY").is_none() {
            return;
        }
        let (tx, rx) = channel::<Job>();
        self.as_mut().rust_mut().work = Some(tx);
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("apps-kwin".into())
            .spawn(move || {
                let events = thread.clone();
                let kwin = Kwin::connect(move |event| {
                    let _ = events.queue(move |obj: Pin<&mut qobject::Apps>| obj.on_event(event));
                });
                let kwin = match kwin {
                    Ok(k) => Arc::new(k),
                    Err(e) => {
                        eprintln!("game-companion: no KWin for Brave and Legcord: {e}");
                        return;
                    }
                };
                let keys: Vec<&str> = APPS.iter().map(|a| a.window).collect();
                if let Err(e) = kwin.watch(&keys) {
                    eprintln!("game-companion: KWin did not take the window watcher: {e}");
                    return;
                }
                apps::runtime(|r| r.kwin = Some(kwin.clone()));
                let _ = thread.queue(|mut obj: Pin<&mut qobject::Apps>| {
                    obj.as_mut().rust_mut().available = true;
                    obj.refresh();
                });
                // Waits for work; ends when the app goes.
                for job in rx {
                    job(&kwin);
                }
            })
            .ok();
    }

    fn on_event(mut self: Pin<&mut Self>, event: Event) {
        match event {
            Event::Window(win) => {
                let Some(app) = owner(&win) else { return };
                let (show_now, place) = {
                    let mut rust = self.as_mut().rust_mut();
                    let s = rust.apps.get_mut(app.id).expect("every app has a state");
                    match s.windows.iter_mut().find(|w| w.id == win.id) {
                        Some(w) => *w = win.clone(),
                        None => s.windows.push(win.clone()),
                    }
                    let mut place = None;
                    if s.shown == win.id {
                        if win.min {
                            s.shown.clear();
                        } else if win.above && !win.moving && win.out == s.output && win.w > 0 {
                            // Moved or resized by hand over the game: kept.
                            place = Some(Place { x: win.x - win.ox, y: win.y - win.oy, w: win.w, h: win.h });
                        }
                    }
                    let show_now = s.starting && !win.min;
                    if show_now {
                        s.starting = false;
                        s.chosen = win.id.clone();
                    }
                    (show_now, place)
                };
                if let Some(place) = place {
                    if apps::choice(app.id).place != Some(place) {
                        save_choice(app.id, |c| c.place = Some(place));
                    }
                }
                if show_now {
                    let output = self.rust().apps[app.id].output.clone();
                    self.as_mut().show(app, &output);
                }
            }
            Event::Removed(id) => {
                for s in self.as_mut().rust_mut().apps.values_mut() {
                    s.windows.retain(|w| w.id != id);
                    if s.shown == id {
                        s.shown.clear();
                    }
                }
                apps::runtime(|r| {
                    r.before.remove(&id);
                    if r.unfull.as_deref() == Some(id.as_str()) {
                        r.unfull = None;
                    }
                });
            }
            // Game Companion's own parts (KWin lists them as normal windows).
            Event::Active(Some(win)) if win.pid == std::process::id() as i32 => {}
            Event::Active(Some(win)) => {
                if let Some(app) = owner(&win) {
                    let mut rust = self.as_mut().rust_mut();
                    rust.apps.get_mut(app.id).expect("every app has a state").chosen = win.id;
                } else {
                    self.as_mut().rust_mut().other = win.id.clone();
                    self.as_mut().rust_mut().other_win = Some(win.clone());
                    // A game in real full screen took the focus: it lies over
                    // every normal window on its screen now (KWin 6.8, see
                    // `apps`). It loses its full-screen mark, or the apps
                    // shown there go.
                    let kept = win.full && self.shown_on(&win.out) && self.as_mut().keep_over(&win);
                    if win.full && !kept {
                        let hide: Vec<String> = {
                            let mut rust = self.as_mut().rust_mut();
                            let mut list = Vec::new();
                            for s in rust.apps.values_mut() {
                                let on_screen = s.windows.iter().any(|w| w.id == s.shown && w.out == win.out);
                                if on_screen {
                                    list.push(std::mem::take(&mut s.shown));
                                }
                            }
                            list
                        };
                        for id in hide {
                            self.kwin(move |k| {
                                let _ = k.run(&apps::hide_body(&id, ""));
                            });
                        }
                    }
                }
            }
            // The game took its full screen back while an app is shown.
            Event::Full(win) if win.pid == std::process::id() as i32 || owner(&win).is_some() => {}
            Event::Full(win) => {
                if self.rust().other == win.id {
                    self.as_mut().rust_mut().other_win = Some(win.clone());
                }
                if self.shown_on(&win.out) && !self.as_mut().keep_over(&win) {
                    let hide: Vec<String> = {
                        let mut rust = self.as_mut().rust_mut();
                        let mut list = Vec::new();
                        for s in rust.apps.values_mut() {
                            if s.windows.iter().any(|w| w.id == s.shown && w.out == win.out) {
                                list.push(std::mem::take(&mut s.shown));
                            }
                        }
                        list
                    };
                    for id in hide {
                        self.kwin(move |k| {
                            let _ = k.run(&apps::hide_body(&id, ""));
                        });
                    }
                }
            }
            Event::Active(None) | Event::Ready => {}
        }
        self.refresh();
    }

    /// Shows the app's window over the game (the chosen one, else its
    /// newest).
    fn show(mut self: Pin<&mut Self>, app: &'static AppDef, output: &str) {
        let (id, win) = {
            let s = &self.rust().apps[app.id];
            let win = s.windows.iter().find(|w| w.id == s.chosen).or_else(|| s.windows.last());
            match win {
                Some(w) => (w.id.clone(), w.clone()),
                None => return,
            }
        };
        apps::runtime(|r| {
            r.before.entry(id.clone()).or_insert_with(|| Before::of(&win));
        });
        {
            let mut rust = self.as_mut().rust_mut();
            let s = rust.apps.get_mut(app.id).expect("every app has a state");
            s.shown = id.clone();
            s.chosen = id.clone();
            s.output = output.to_string();
            s.why.clear();
        }
        let choice = apps::choice(app.id);
        let body = apps::show_body(&id, output, choice.place, app, f64::from(choice.opacity) / 100.0);
        self.kwin(move |k| {
            let _ = k.run(&body);
        });
        // A game in full screen on that screen: its mark goes now, so that
        // clicking into it later keeps the app on top.
        self.as_mut().rust_mut().refulls = 0;
        let game = self.rust().other_win.clone().filter(|g| g.full && (output.is_empty() || g.out == output));
        if let Some(game) = game {
            self.as_mut().keep_over(&game);
        }
    }

    fn toggle(mut self: Pin<&mut Self>, id: &QString, output: &QString) {
        let Some(app) = find(&id.to_string()) else { return };
        let output = output.to_string();
        let (shown, has_window, starting) = {
            let s = &self.rust().apps[app.id];
            (s.shown.clone(), !s.windows.is_empty(), s.starting)
        };
        if !shown.is_empty() {
            let other = self.rust().other.clone();
            self.as_mut().rust_mut().apps.get_mut(app.id).expect("every app has a state").shown.clear();
            self.kwin(move |k| {
                let _ = k.run(&apps::hide_body(&shown, &other));
            });
        } else if has_window && self.rust().available {
            self.as_mut().show(app, &output);
        } else if starting {
            // A second press while it starts: it will not be shown.
            self.as_mut().rust_mut().apps.get_mut(app.id).expect("every app has a state").starting = false;
        } else {
            self.as_mut().start(app, &output, true);
        }
        self.refresh();
    }

    /// Starts the app's program (unless Game Companion's start still runs);
    /// with `show`, it is shown when its window comes.
    fn start(mut self: Pin<&mut Self>, app: &'static AppDef, output: &str, show: bool) {
        let choice = apps::choice(app.id);
        let Some(command) = apps::command_for(app, &choice) else {
            let why = format!("{} was not found: set its program in Settings → Apps", app.name);
            self.as_mut().rust_mut().apps.get_mut(app.id).expect("every app has a state").why = why;
            return;
        };
        let ours = apps::runtime(|r| r.started.get(app.id).copied());
        let running_ours = ours.is_some_and(|(pid, start)| start_with::program_alive(pid, start));
        if !running_ours {
            // Already running without a window (Legcord in the tray): the new
            // start only brings its window back, and it stays the person's.
            let name = command.split_whitespace().next().unwrap_or("").rsplit('/').next().unwrap_or("").to_string();
            let was_running = !name.is_empty() && start_with::program_runs(&name);
            match start_with::spawn_program(&command) {
                Some(started) if !was_running => {
                    eprintln!("game-companion: started {} (pid {})", app.name, started.0);
                    apps::runtime(|r| r.started.insert(app.id, started));
                }
                Some(_) => {}
                None => {
                    let why = format!("{} did not start ({command})", app.name);
                    self.as_mut().rust_mut().apps.get_mut(app.id).expect("every app has a state").why = why;
                    return;
                }
            }
        }
        if !show || !self.rust().available {
            return;
        }
        let run = {
            let mut rust = self.as_mut().rust_mut();
            let s = rust.apps.get_mut(app.id).expect("every app has a state");
            s.starting = true;
            s.starting_run += 1;
            s.output = output.to_string();
            s.why.clear();
            s.starting_run
        };
        // No window after 30 s: given up.
        let thread = self.qt_thread();
        let id = app.id;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(30));
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Apps>| {
                let gave_up = {
                    let mut rust = obj.as_mut().rust_mut();
                    let s = rust.apps.get_mut(id).expect("every app has a state");
                    let gave_up = s.starting && s.starting_run == run;
                    if gave_up {
                        s.starting = false;
                        s.why = "No window came within 30 s".into();
                    }
                    gave_up
                };
                if gave_up {
                    obj.refresh();
                }
            });
        });
    }

    fn set_opacity(self: Pin<&mut Self>, id: &QString, percent: i32) {
        let Some(app) = find(&id.to_string()) else { return };
        let percent = percent.clamp(i32::from(apps::MIN_OPACITY), 100) as u8;
        save_choice(app.id, |c| c.opacity = percent);
        let shown = self.rust().apps[app.id].shown.clone();
        if !shown.is_empty() {
            self.kwin(move |k| {
                let _ = k.run(&apps::opacity_body(&shown, f64::from(percent) / 100.0));
            });
        }
        self.refresh();
    }

    fn next_window(mut self: Pin<&mut Self>, id: &QString, output: &QString) {
        let Some(app) = find(&id.to_string()) else { return };
        let (next, shown) = {
            let s = &self.rust().apps[app.id];
            if s.windows.len() < 2 {
                return;
            }
            let current = if s.shown.is_empty() { &s.chosen } else { &s.shown };
            let at = s.windows.iter().position(|w| &w.id == current).unwrap_or(0);
            (s.windows[(at + 1) % s.windows.len()].id.clone(), s.shown.clone())
        };
        if !shown.is_empty() {
            self.kwin(move |k| {
                let _ = k.run(&apps::hide_body(&shown, ""));
            });
        }
        self.as_mut().rust_mut().apps.get_mut(app.id).expect("every app has a state").chosen = next;
        self.as_mut().show(app, &output.to_string());
        self.refresh();
    }

    fn close_window(self: Pin<&mut Self>, id: &QString) {
        let Some(app) = find(&id.to_string()) else { return };
        let target = {
            let s = &self.rust().apps[app.id];
            if !s.shown.is_empty() {
                s.shown.clone()
            } else if s.windows.iter().any(|w| w.id == s.chosen) {
                s.chosen.clone()
            } else {
                s.windows.last().map(|w| w.id.clone()).unwrap_or_default()
            }
        };
        if target.is_empty() {
            return;
        }
        self.kwin(move |k| {
            let _ = k.run(&apps::close_body(&target));
        });
        self.refresh();
    }

    fn set_command(self: Pin<&mut Self>, id: &QString, command: &QString) {
        let Some(app) = find(&id.to_string()) else { return };
        let command = command.to_string().trim().to_string();
        if !command.is_empty() && !start_with::valid_command(&command) {
            return;
        }
        save_choice(app.id, |c| c.command = command);
        self.refresh();
    }

    fn set_with_game(self: Pin<&mut Self>, id: &QString, on: bool) {
        let Some(app) = find(&id.to_string()) else { return };
        save_choice(app.id, |c| c.with_game = on);
        self.refresh();
    }

    fn set_close_on_quit(self: Pin<&mut Self>, id: &QString, on: bool) {
        let Some(app) = find(&id.to_string()) else { return };
        save_choice(app.id, |c| c.close_on_quit = on);
        self.refresh();
    }

    fn set_over_full(mut self: Pin<&mut Self>, on: bool) {
        crate::settings::change(|s| s.apps_over_full = on);
        if !on {
            // Back to full screen now; the next click into it minimises the apps.
            if let Some(id) = apps::runtime(|r| r.unfull.take()) {
                self.kwin(move |k| {
                    let _ = k.run(&apps::refull_body(&id));
                });
            }
        }
        self.as_mut().rust_mut().refulls = 0;
        self.refresh();
    }

    fn forget_place(self: Pin<&mut Self>, id: &QString) {
        let Some(app) = find(&id.to_string()) else { return };
        save_choice(app.id, |c| c.place = None);
        self.refresh();
    }

    fn game_started(mut self: Pin<&mut Self>, game: &QString) {
        let game = game.to_string();
        for app in &APPS {
            let running = !self.rust().apps[app.id].windows.is_empty();
            let fits = app.game.is_none_or(|g| g == game);
            if apps::choice(app.id).with_game && !running && fits {
                self.as_mut().start(app, "", false);
            }
        }
        self.refresh();
    }

    fn game_stopped(mut self: Pin<&mut Self>) {
        for s in self.as_mut().rust_mut().apps.values_mut() {
            s.shown.clear();
            s.starting = false;
        }
        self.kwin(|_| apps::restore_all());
        self.refresh();
    }
}
