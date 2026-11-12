//! The overlay's state, for QML: the lock, shown or hidden, how solid the
//! panels are, where they were left, and the global shortcuts.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::settings::{self, Place};
use crate::shortcuts;

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
}

impl Default for CompanionRust {
    fn default() -> Self {
        let (alpha, welcome, pins, layouts) =
            settings::read(|s| (s.alpha, s.welcome, pins_json(&s.pins), layouts_json(&s.layouts)));
        let (text_level, alpha_presets, text_presets, bar) = settings::read(|s| {
            (s.text_level, numbers_json(&s.alpha_presets), numbers_json(&s.text_presets), s.bar)
        });
        let (accent_level, accent_presets) = settings::read(|s| (s.accent_level, numbers_json(&s.accent_presets)));
        let shortcut_state: Vec<_> = shortcuts::ALL.iter().map(|s| (s.id, shortcuts::Status::Bound(None))).collect();
        Self {
            // Always start locked: the game gets every click until the user
            // unlocks the overlay.
            locked: true,
            shown: true,
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

/// "0.1.0", or "0.1.0 (build 12)" for a release built on GitHub.
pub fn version_text() -> String {
    let version = env!("CARGO_PKG_VERSION");
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
    fn initialize(self: Pin<&mut Self>) {
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
    fn version_has_the_package_version() {
        assert!(version_text().starts_with(env!("CARGO_PKG_VERSION")));
    }
}
