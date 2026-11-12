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
        /// How solid the panels are, 0.5 to 1.
        #[qproperty(f64, alpha)]
        /// Whether the welcome panel shows.
        #[qproperty(bool, welcome)]
        /// The shortcuts and what the desktop said about them, as JSON:
        /// `[{"id","description","key","state"}]`.
        #[qproperty(QString, shortcuts)]
        /// What stays while the hub is hidden, as a JSON list of ids.
        #[qproperty(QString, pins)]
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

        /// Closes the welcome panel for good.
        #[qinvokable]
        fn close_welcome(self: Pin<&mut Companion>);

        /// Where a panel was left, as JSON `{"x":..,"y":..}`, or "" if never moved.
        #[qinvokable]
        fn place_of(self: &Companion, id: &QString) -> QString;

        /// Keeps where a panel was left.
        #[qinvokable]
        fn save_place(self: Pin<&mut Companion>, id: &QString, x: f64, y: f64);

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
    welcome: bool,
    shortcuts: QString,
    pins: QString,
    shortcut_state: Vec<(&'static str, shortcuts::Status)>,
}

impl Default for CompanionRust {
    fn default() -> Self {
        let (alpha, welcome, pins) = settings::read(|s| (s.alpha, s.welcome, pins_json(&s.pins)));
        let shortcut_state: Vec<_> = shortcuts::ALL.iter().map(|s| (s.id, shortcuts::Status::Bound(None))).collect();
        Self {
            // Always start locked: the game gets every click until the user
            // unlocks the overlay.
            locked: true,
            shown: true,
            alpha,
            welcome,
            shortcuts: QString::from(&shortcuts_json(&shortcut_state)),
            pins: QString::from(&pins),
            shortcut_state,
        }
    }
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

    fn close_welcome(self: Pin<&mut Self>) {
        settings::change(|s| s.welcome = false);
        self.set_welcome(false);
    }

    fn place_of(&self, id: &QString) -> QString {
        match settings::read(|s| s.places.get(&id.to_string()).copied()) {
            Some(p) => QString::from(&serde_json::json!({ "x": p.x, "y": p.y }).to_string()),
            None => QString::default(),
        }
    }

    fn save_place(self: Pin<&mut Self>, id: &QString, x: f64, y: f64) {
        if !(x.is_finite() && y.is_finite()) {
            return;
        }
        let place = Place { x: x.round(), y: y.round() };
        let id = id.to_string();
        if settings::read(|s| s.places.get(&id) == Some(&place)) {
            return;
        }
        settings::change(|s| {
            s.places.insert(id, place);
        });
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
