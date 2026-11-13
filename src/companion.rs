//! The overlay's state, for QML: the lock, shown or hidden, how solid the
//! panels are, where they were left, and the global shortcuts.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::settings::{self, Place};
use crate::shortcuts;
use crate::tray;

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
        /// Locked: every click goes to the game. Unlocked: panels move and
        /// their buttons work.
        #[qproperty(bool, locked)]
        /// Whether the hub shows (the bar, the player row, the panels).
        /// Hidden, only what is pinned stays on screen.
        #[qproperty(bool, shown)]
        /// How the companion starts with the desktop (KDE's autostart
        /// folder holds its entry): "off", "hidden" (only the tray icon
        /// until a game starts) or "visible" (the hub at once).
        #[qproperty(QString, autostart_mode)]
        /// Whether the hub shows when a game starts.
        #[qproperty(bool, show_on_game)]
        /// Whether the icon shows in the desktop's tray.
        #[qproperty(bool, tray)]
        /// How solid the panels are, 0.05 to 1. QML may set it while a
        /// slider moves; `save_alpha` keeps it.
        #[qproperty(f64, alpha)]
        /// How bright the bar's and the player row's white and grey text
        /// is, 0.4 to 1.
        #[qproperty(f64, text_level)]
        /// How bright the bar's and the player row's gold is, 0.4 to 1.
        #[qproperty(f64, accent_level)]
        /// The gold brightness presets P1 to P3, as a JSON list.
        #[qproperty(QString, accent_presets)]
        /// The opacity presets P1 to P3, as a JSON list of three numbers.
        #[qproperty(QString, alpha_presets)]
        /// The text brightness presets P1 to P3, as a JSON list.
        #[qproperty(QString, text_presets)]
        /// The bar's distance from the screen's centre, in pixels.
        #[qproperty(f64, bar_offset)]
        /// The bar's size (with the player row), 0.6 to 1.
        #[qproperty(f64, bar_scale)]
        /// Whether the welcome panel shows.
        #[qproperty(bool, welcome)]
        /// The shortcuts and what the desktop said about them, as JSON:
        /// `[{"id","description","key","state"}]`.
        #[qproperty(QString, shortcuts)]
        /// What stays while the hub is hidden, as a JSON list of ids.
        #[qproperty(QString, pins)]
        /// The saved layouts' names, as a JSON list.
        #[qproperty(QString, layouts)]
        /// Goes up when a layout is loaded: panels then take their places again.
        #[qproperty(i32, layout_revision)]
        type Companion = super::CompanionRust;

        /// Pins or unpins something (a panel, the player row) by its id.
        #[qinvokable]
        fn toggle_pin(self: Pin<&mut Companion>, id: &QString);

        #[qinvokable]
        fn toggle_locked(self: Pin<&mut Companion>);

        #[qinvokable]
        fn toggle_shown(self: Pin<&mut Companion>);

        /// Starts with the desktop or not: "off", "hidden" or "visible"
        /// (writes, rewrites or removes the entry).
        #[qinvokable]
        fn set_autostart_to(self: Pin<&mut Companion>, mode: &QString);

        /// Shows the hub when a game starts, or not.
        #[qinvokable]
        fn set_show_on_game_on(self: Pin<&mut Companion>, on: bool);

        /// Shows the tray icon or takes it away.
        #[qinvokable]
        fn set_tray_on(self: Pin<&mut Companion>, on: bool);

        /// The tray's "Settings": QML opens the settings panel.
        #[qsignal]
        fn settings_requested(self: Pin<&mut Companion>);

        /// The tray's "Check for updates": QML asks Updates and opens
        /// Settings → General, where the answer shows.
        #[qsignal]
        fn updates_requested(self: Pin<&mut Companion>);

        /// Keeps the screen the user picked ("" = KDE's primary screen).
        #[qinvokable]
        fn save_screen(self: Pin<&mut Companion>, name: &QString);

        /// The screen the user picked, "" for KDE's primary screen.
        #[qinvokable]
        fn chosen_screen(self: &Companion) -> QString;

        /// Sets and keeps how solid the panels are.
        #[qinvokable]
        fn save_alpha(self: Pin<&mut Companion>, alpha: f64);

        /// Sets and keeps how bright the white and grey text is.
        #[qinvokable]
        fn save_text_level(self: Pin<&mut Companion>, level: f64);

        /// Sets and keeps how bright the bar's gold is.
        #[qinvokable]
        fn save_accent_level(self: Pin<&mut Companion>, level: f64);

        /// Keeps a value on a preset button: `kind` "alpha", "text" or "accent",
        /// `index` 0 to 2.
        #[qinvokable]
        fn save_preset(self: Pin<&mut Companion>, kind: &QString, index: i32, value: f64);

        /// Sets and keeps where the bar is (pixels from the centre).
        #[qinvokable]
        fn save_bar_offset(self: Pin<&mut Companion>, offset: f64);

        /// Sets and keeps the bar's size.
        #[qinvokable]
        fn save_bar_scale(self: Pin<&mut Companion>, scale: f64);

        /// Closes the welcome panel for good.
        #[qinvokable]
        fn close_welcome(self: Pin<&mut Companion>);

        /// Where a panel was left and its size, as JSON
        /// `{"x","y","w","grow"}`, or "" if never moved.
        #[qinvokable]
        fn place_of(self: &Companion, id: &QString) -> QString;

        /// Keeps where a panel was left and its size (0: its own).
        #[qinvokable]
        fn save_place(self: Pin<&mut Companion>, id: &QString, x: f64, y: f64, w: f64, grow: f64);

        /// Saves the arrangement as it is under a name (replacing one of
        /// that name); `open` is the open panels' ids as a JSON list.
        #[qinvokable]
        fn save_layout(self: Pin<&mut Companion>, name: &QString, open: &QString) -> bool;

        /// Takes a layout's places, sizes, pins, opacity, text brightness
        /// and bar; returns the
        /// panels to open as a JSON list ("" if there is no such layout).
        #[qinvokable]
        fn load_layout(self: Pin<&mut Companion>, name: &QString) -> QString;

        #[qinvokable]
        fn rename_layout(self: Pin<&mut Companion>, name: &QString, new_name: &QString) -> bool;

        #[qinvokable]
        fn delete_layout(self: Pin<&mut Companion>, name: &QString);

        /// Opens KDE's shortcut settings, to change the keys.
        #[qinvokable]
        fn open_shortcut_settings(self: &Companion) -> bool;

        /// The version, as Settings and the title's tooltip show it.
        #[qinvokable]
        fn version(self: &Companion) -> QString;
    }

    impl cxx_qt::Threading for Companion {}
    impl cxx_qt::Initialize for Companion {}
}

pub struct CompanionRust {
    locked: bool,
    shown: bool,
    autostart_mode: QString,
    show_on_game: bool,
    tray: bool,
    alpha: f64,
    text_level: f64,
    accent_level: f64,
    accent_presets: QString,
    alpha_presets: QString,
    text_presets: QString,
    bar_offset: f64,
    bar_scale: f64,
    welcome: bool,
    shortcuts: QString,
    pins: QString,
    layouts: QString,
    layout_revision: i32,
    shortcut_state: Vec<(&'static str, shortcuts::Status)>,
    /// The tray icon while it shows.
    tray_handle: Option<tray::Worker>,
    /// Goes up whenever the tray is switched on or off: a tray that
    /// finishes starting after it was switched off again goes away.
    tray_generation: u64,
}

impl Default for CompanionRust {
    fn default() -> Self {
        let (alpha, welcome, pins, layouts) =
            settings::read(|s| (s.alpha, s.welcome, pins_json(&s.pins), layouts_json(&s.layouts)));
        let (text_level, alpha_presets, text_presets, bar) = settings::read(|s| {
            (s.text_level, numbers_json(&s.alpha_presets), numbers_json(&s.text_presets), s.bar)
        });
        let (accent_level, accent_presets) = settings::read(|s| (s.accent_level, numbers_json(&s.accent_presets)));
        let (show_on_game, tray) = settings::read(|s| (s.show_on_game, s.tray));
        let shortcut_state: Vec<_> = shortcuts::ALL.iter().map(|s| (s.id, shortcuts::Status::Bound(None))).collect();
        Self {
            // Always start locked: the game gets every click until the user
            // unlocks the overlay.
            locked: true,
            // Started with the desktop (--hidden): out of sight until a game
            // starts or the user shows it.
            shown: !std::env::args().any(|a| a == "--hidden"),
            autostart_mode: QString::from(autostart_mode()),
            show_on_game,
            tray,
            alpha,
            text_level,
            accent_level,
            accent_presets: QString::from(&accent_presets),
            alpha_presets: QString::from(&alpha_presets),
            text_presets: QString::from(&text_presets),
            bar_offset: bar.offset,
            bar_scale: bar.scale,
            welcome,
            shortcuts: QString::from(&shortcuts_json(&shortcut_state)),
            pins: QString::from(&pins),
            layouts: QString::from(&layouts),
            layout_revision: 0,
            shortcut_state,
            tray_handle: None,
            tray_generation: 0,
        }
    }
}

fn layouts_json(layouts: &std::collections::BTreeMap<String, settings::Layout>) -> String {
    serde_json::to_string(&layouts.keys().collect::<Vec<_>>()).unwrap_or_else(|_| "[]".into())
}

fn numbers_json(values: &[f64]) -> String {
    serde_json::to_string(values).unwrap_or_else(|_| "[]".into())
}

fn pins_json(pins: &std::collections::BTreeSet<String>) -> String {
    serde_json::to_string(pins).unwrap_or_else(|_| "[]".into())
}

/// The desktop's autostart entry: hidden (only the tray icon until a game
/// starts) or with the hub shown.
fn autostart_entry(hidden: bool) -> String {
    let (comment, exec) = if hidden {
        ("Starts hidden in the tray; shows when a game starts", "game-companion --hidden")
    } else {
        ("Starts with the hub shown", "game-companion")
    };
    format!(
        "[Desktop Entry]
Type=Application
Name=Game Companion
Comment={comment}
Exec={exec}
Icon=input-gaming
Terminal=false
X-KDE-autostart-phase=2
"
    )
}

/// The start mode an autostart entry stands for: "hidden" when its Exec
/// line passes `--hidden` (every entry before 0.6.0 did), else "visible".
fn mode_of_entry(text: &str) -> &'static str {
    let hidden = text
        .lines()
        .filter_map(|l| l.trim().strip_prefix("Exec="))
        .any(|exec| exec.split_whitespace().any(|a| a == "--hidden"));
    if hidden {
        "hidden"
    } else {
        "visible"
    }
}

/// How the companion starts with the desktop now: "off", "hidden" or
/// "visible".
fn autostart_mode() -> &'static str {
    match autostart_file().map(std::fs::read_to_string) {
        Some(Ok(text)) => mode_of_entry(&text),
        // There but unreadable: it still starts the companion.
        Some(Err(e)) if e.kind() != std::io::ErrorKind::NotFound => "hidden",
        _ => "off",
    }
}

/// `$XDG_CONFIG_HOME/autostart/io.github.xzero3007.GameCompanion.desktop`.
fn autostart_file() -> Option<std::path::PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))?;
    Some(base.join("autostart").join("io.github.xzero3007.GameCompanion.desktop"))
}

/// "0.1.0", or "0.1.0 (build 12)" for a release built on GitHub, "0.1.0
/// beta (build 12)" for a beta build.
pub fn version_text() -> String {
    let version = if crate::updater::running_beta() {
        format!("{} beta", env!("CARGO_PKG_VERSION"))
    } else {
        env!("CARGO_PKG_VERSION").to_string()
    };
    match option_env!("GC_BUILD") {
        Some(build) if !build.is_empty() => format!("{version} (build {build})"),
        _ => version.to_string(),
    }
}

/// The shortcuts for QML, each with the key the desktop gave it, or the
/// suggested key while the desktop has not answered.
fn shortcuts_json(state: &[(&'static str, shortcuts::Status)]) -> String {
    let list: Vec<serde_json::Value> = shortcuts::ALL
        .iter()
        .map(|s| {
            let status = state.iter().find(|(id, _)| *id == s.id).map(|(_, st)| st.clone());
            let (key, state) = match status {
                Some(shortcuts::Status::Bound(Some(key))) => (key, "bound".to_string()),
                Some(shortcuts::Status::Bound(None)) | None => (shortcuts::readable(s.trigger), "suggested".to_string()),
                Some(shortcuts::Status::NoKey) => (String::new(), "nokey".to_string()),
                Some(shortcuts::Status::Unavailable(why)) => (shortcuts::readable(s.trigger), format!("unavailable: {why}")),
            };
            serde_json::json!({ "id": s.id, "description": s.description, "key": key, "state": state })
        })
        .collect();
    serde_json::Value::Array(list).to_string()
}

impl cxx_qt::Initialize for qobject::Companion {
    fn initialize(mut self: Pin<&mut Self>) {
        // A second start asks for the hub.
        let show_thread = self.qt_thread();
        crate::instance::serve(move || {
            let _ = show_thread.queue(|obj: Pin<&mut qobject::Companion>| {
                if !*obj.shown() {
                    obj.set_shown(true);
                }
            });
        });
        // The tray's menu follows the hub and the lock.
        self.as_mut().on_shown_changed(|obj| obj.sync_tray()).release();
        self.as_mut().on_locked_changed(|obj| obj.sync_tray()).release();
        if *self.tray() && std::env::var_os("GC_NO_TRAY").is_none() {
            self.as_mut().start_tray();
        }

        if std::env::var_os("GC_NO_SHORTCUTS").is_some() {
            return;
        }
        let fire_thread = self.qt_thread();
        let status_thread = self.qt_thread();
        std::thread::Builder::new()
            .name("shortcuts".into())
            .spawn(move || {
                shortcuts::listen(
                    move |id, status| {
                        let id = shortcuts::ALL.iter().find(|s| s.id == id).map(|s| s.id);
                        let Some(id) = id else { return };
                        let _ = status_thread.queue(move |mut obj: Pin<&mut qobject::Companion>| {
                            let mut rust = obj.as_mut().rust_mut();
                            match rust.shortcut_state.iter_mut().find(|(i, _)| *i == id) {
                                Some(slot) => slot.1 = status,
                                None => rust.shortcut_state.push((id, status)),
                            }
                            let json = shortcuts_json(&rust.shortcut_state);
                            obj.set_shortcuts(QString::from(&json));
                        });
                    },
                    move |id| {
                        let id = id.to_string();
                        let _ = fire_thread.queue(move |obj: Pin<&mut qobject::Companion>| match id.as_str() {
                            "lock" => obj.toggle_locked(),
                            "toggle" => obj.toggle_shown(),
                            _ => {}
                        });
                    },
                )
            })
            .ok();
    }
}

impl qobject::Companion {
    fn toggle_locked(self: Pin<&mut Self>) {
        let locked = !*self.locked();
        self.set_locked(locked);
    }

    fn save_screen(self: Pin<&mut Self>, name: &QString) {
        let name: String = name.to_string().chars().filter(|c| !c.is_control()).take(64).collect();
        settings::change(|s| s.screen = name);
    }

    fn chosen_screen(&self) -> QString {
        QString::from(&settings::read(|s| s.screen.clone()))
    }

    fn set_autostart_to(mut self: Pin<&mut Self>, mode: &QString) {
        let mode = mode.to_string();
        let Some(file) = autostart_file() else { return };
        let done = match mode.as_str() {
            "hidden" | "visible" => file
                .parent()
                .map(std::fs::create_dir_all)
                .transpose()
                .and_then(|_| std::fs::write(&file, autostart_entry(mode == "hidden"))),
            "off" => match std::fs::remove_file(&file) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
                _ => Ok(()),
            },
            _ => return,
        };
        if done.is_ok() {
            self.as_mut().set_autostart_mode(QString::from(&mode));
        }
    }

    fn set_show_on_game_on(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.show_on_game = on);
        self.set_show_on_game(on);
    }

    fn set_tray_on(mut self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.tray = on);
        self.as_mut().set_tray(on);
        if on {
            self.as_mut().start_tray();
        } else {
            let mut rust = self.as_mut().rust_mut();
            rust.tray_generation += 1;
            if let Some(worker) = rust.tray_handle.take() {
                // Ends on the tray's worker; nothing to wait for here.
                worker.shutdown();
            }
        }
    }

    /// Puts the icon into the panel, on a thread of its own (it talks to
    /// the session bus first).
    fn start_tray(mut self: Pin<&mut Self>) {
        if self.rust().tray_handle.is_some() {
            return;
        }
        let generation = {
            let mut rust = self.as_mut().rust_mut();
            rust.tray_generation += 1;
            rust.tray_generation
        };
        let icons = crate::native::tray_icons();
        let (shown, locked) = (*self.shown(), *self.locked());
        let act_thread = std::sync::Mutex::new(self.qt_thread());
        let done_thread = self.qt_thread();
        let _ = std::thread::Builder::new().name("tray".into()).spawn(move || {
            let tray = tray::GcTray::new(shown, locked, icons, move |action| {
                if let Ok(thread) = act_thread.lock() {
                    let _ = thread.queue(move |obj: Pin<&mut qobject::Companion>| obj.tray_action(action));
                }
            });
            let started = tray::spawn(tray);
            let _ = done_thread.queue(move |mut obj: Pin<&mut qobject::Companion>| match started {
                Ok(handle) if obj.rust().tray_generation == generation && *obj.tray() => {
                    obj.as_mut().rust_mut().tray_handle = Some(tray::Worker::new(handle));
                    // The hub or the lock may have changed meanwhile.
                    obj.sync_tray();
                }
                Ok(handle) => drop(handle.shutdown()),
                Err(e) => eprintln!("game-companion: no tray icon: {e}"),
            });
        });
    }

    /// Brings the tray's menu and tooltip up to the hub and the lock.
    fn sync_tray(&self) {
        // Off the Qt thread: ksni's update waits for its own thread.
        let Some(worker) = self.rust().tray_handle.as_ref() else { return };
        worker.set(*self.shown(), *self.locked());
    }

    fn tray_action(mut self: Pin<&mut Self>, action: tray::Action) {
        match action {
            tray::Action::ToggleShown => self.toggle_shown(),
            tray::Action::ToggleLocked => self.toggle_locked(),
            tray::Action::Settings => {
                self.as_mut().set_shown(true);
                self.settings_requested();
            }
            tray::Action::CheckUpdates => {
                self.as_mut().set_shown(true);
                self.updates_requested();
            }
            // As Settings' "Turn off": mpv and the capture helper end with
            // the app.
            tray::Action::Quit => crate::native::quit(),
        }
    }

    fn toggle_shown(self: Pin<&mut Self>) {
        // The lock stays as it is: hidden, the pinned things keep it.
        let shown = !*self.shown();
        self.set_shown(shown);
    }

    fn toggle_pin(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        if id.is_empty() {
            return;
        }
        let json = settings::change(|s| {
            if !s.pins.remove(&id) {
                s.pins.insert(id);
            }
            pins_json(&s.pins)
        });
        self.set_pins(QString::from(&json));
    }

    fn save_alpha(self: Pin<&mut Self>, alpha: f64) {
        let alpha = settings::clamp_alpha(alpha);
        settings::change(|s| s.alpha = alpha);
        self.set_alpha(alpha);
    }

    fn save_text_level(self: Pin<&mut Self>, level: f64) {
        let level = settings::clamp_text_level(level);
        settings::change(|s| s.text_level = level);
        self.set_text_level(level);
    }

    fn save_accent_level(self: Pin<&mut Self>, level: f64) {
        let level = settings::clamp_text_level(level);
        settings::change(|s| s.accent_level = level);
        self.set_accent_level(level);
    }

    fn save_preset(self: Pin<&mut Self>, kind: &QString, index: i32, value: f64) {
        let Ok(index) = usize::try_from(index) else { return };
        if index > 2 {
            return;
        }
        match kind.to_string().as_str() {
            "alpha" => {
                let value = (settings::clamp_alpha(value) * 100.0).round() / 100.0;
                let json = settings::change(|s| {
                    s.alpha_presets[index] = value;
                    numbers_json(&s.alpha_presets)
                });
                self.set_alpha_presets(QString::from(&json));
            }
            "text" => {
                let value = (settings::clamp_text_level(value) * 100.0).round() / 100.0;
                let json = settings::change(|s| {
                    s.text_presets[index] = value;
                    numbers_json(&s.text_presets)
                });
                self.set_text_presets(QString::from(&json));
            }
            "accent" => {
                let value = (settings::clamp_text_level(value) * 100.0).round() / 100.0;
                let json = settings::change(|s| {
                    s.accent_presets[index] = value;
                    numbers_json(&s.accent_presets)
                });
                self.set_accent_presets(QString::from(&json));
            }
            _ => {}
        }
    }

    fn save_bar_offset(self: Pin<&mut Self>, offset: f64) {
        let bar = settings::change(|s| {
            s.bar = settings::BarSettings { offset, ..s.bar }.tidy();
            s.bar
        });
        self.set_bar_offset(bar.offset);
    }

    fn save_bar_scale(self: Pin<&mut Self>, scale: f64) {
        let bar = settings::change(|s| {
            s.bar = settings::BarSettings { scale, ..s.bar }.tidy();
            s.bar
        });
        self.set_bar_scale(bar.scale);
    }

    fn close_welcome(self: Pin<&mut Self>) {
        settings::change(|s| s.welcome = false);
        self.set_welcome(false);
    }

    fn place_of(&self, id: &QString) -> QString {
        match settings::read(|s| s.places.get(&id.to_string()).copied()) {
            Some(p) => QString::from(&serde_json::json!({ "x": p.x, "y": p.y, "w": p.w, "grow": p.grow }).to_string()),
            None => QString::default(),
        }
    }

    fn save_place(self: Pin<&mut Self>, id: &QString, x: f64, y: f64, w: f64, grow: f64) {
        if ![x, y, w, grow].iter().all(|v| v.is_finite()) {
            return;
        }
        let place = Place { x: x.round(), y: y.round(), w: w.max(0.0).round(), grow: grow.max(0.0).round() };
        let id = id.to_string();
        if settings::read(|s| s.places.get(&id) == Some(&place)) {
            return;
        }
        settings::change(|s| {
            s.places.insert(id, place);
        });
    }

    fn save_layout(self: Pin<&mut Self>, name: &QString, open: &QString) -> bool {
        let Some(name) = settings::layout_name(&name.to_string()) else { return false };
        let open: Vec<String> = serde_json::from_str(&open.to_string()).unwrap_or_default();
        let json = settings::change(|s| {
            let layout = settings::Layout {
                open,
                places: s.places.clone(),
                pins: s.pins.clone(),
                alpha: s.alpha,
                text_level: Some(s.text_level),
                accent_level: Some(s.accent_level),
                bar: Some(s.bar),
            };
            s.layouts.insert(name, layout);
            layouts_json(&s.layouts)
        });
        self.set_layouts(QString::from(&json));
        true
    }

    fn load_layout(mut self: Pin<&mut Self>, name: &QString) -> QString {
        let name = name.to_string();
        let loaded = settings::change(|s| {
            let layout = s.layouts.get(&name)?.clone();
            s.places = layout.places;
            s.pins = layout.pins;
            s.alpha = settings::clamp_alpha(layout.alpha);
            if let Some(level) = layout.text_level {
                s.text_level = settings::clamp_text_level(level);
            }
            if let Some(level) = layout.accent_level {
                s.accent_level = settings::clamp_text_level(level);
            }
            if let Some(bar) = layout.bar {
                s.bar = bar.tidy();
            }
            Some((layout.open, s.alpha, s.text_level, s.accent_level, s.bar, pins_json(&s.pins)))
        });
        let Some((open, alpha, text_level, accent_level, bar, pins)) = loaded else { return QString::default() };
        self.as_mut().set_alpha(alpha);
        self.as_mut().set_text_level(text_level);
        self.as_mut().set_accent_level(accent_level);
        self.as_mut().set_bar_offset(bar.offset);
        self.as_mut().set_bar_scale(bar.scale);
        self.as_mut().set_pins(QString::from(&pins));
        let revision = self.layout_revision().wrapping_add(1);
        self.as_mut().set_layout_revision(revision);
        QString::from(&serde_json::to_string(&open).unwrap_or_else(|_| "[]".into()))
    }

    fn rename_layout(self: Pin<&mut Self>, name: &QString, new_name: &QString) -> bool {
        let name = name.to_string();
        let Some(new_name) = settings::layout_name(&new_name.to_string()) else { return false };
        let json = settings::change(|s| {
            if name == new_name || s.layouts.contains_key(&new_name) {
                return None;
            }
            let layout = s.layouts.remove(&name)?;
            // Games that load it keep loading it under its new name.
            for game_layout in s.games.layouts.values_mut() {
                if *game_layout == name {
                    *game_layout = new_name.clone();
                }
            }
            s.layouts.insert(new_name, layout);
            Some(layouts_json(&s.layouts))
        });
        match json {
            Some(json) => {
                self.set_layouts(QString::from(&json));
                true
            }
            None => false,
        }
    }

    fn delete_layout(self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        let json = settings::change(|s| {
            s.layouts.remove(&name);
            s.games.layouts.retain(|_, l| *l != name);
            layouts_json(&s.layouts)
        });
        self.set_layouts(QString::from(&json));
    }

    fn open_shortcut_settings(&self) -> bool {
        shortcuts::open_desktop_settings()
    }

    fn version(&self) -> QString {
        QString::from(&version_text())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shortcuts_json_shows_suggested_keys_first() {
        let state = vec![("lock", shortcuts::Status::Bound(None)), ("toggle", shortcuts::Status::NoKey)];
        let v: serde_json::Value = serde_json::from_str(&shortcuts_json(&state)).unwrap();
        assert_eq!(v[0]["key"], "Alt+Q");
        assert_eq!(v[0]["state"], "suggested");
        assert_eq!(v[1]["key"], "");
        assert_eq!(v[1]["state"], "nokey");
    }

    #[test]
    fn autostart_entries_say_how_to_start() {
        assert_eq!(mode_of_entry(&autostart_entry(true)), "hidden");
        assert_eq!(mode_of_entry(&autostart_entry(false)), "visible");
        // The entry written before 0.6.0 starts hidden.
        let old = "[Desktop Entry]\nType=Application\nName=Game Companion\nComment=Starts hidden; shows when a game starts\nExec=game-companion --hidden\n";
        assert_eq!(mode_of_entry(old), "hidden");
        assert_eq!(mode_of_entry("[Desktop Entry]\nComment=--hidden\nExec=/usr/bin/game-companion\n"), "visible");
    }

    #[test]
    fn version_has_the_package_version() {
        assert!(version_text().starts_with(env!("CARGO_PKG_VERSION")));
    }
}
