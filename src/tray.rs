//! The tray icon in KDE's panel while the app runs: a StatusNotifierItem
//! with a dbusmenu (ksni, over the same zbus the shortcuts use), so the
//! app needs no QtWidgets. Left click shows or hides the hub; the menu
//! shows or hides it, locks or unlocks, opens Settings, checks for updates
//! and quits.
//!
//! ksni answers the panel on its own threads, which sleep on the D-Bus
//! socket while nothing happens. A click there only queues the action onto
//! the Qt thread (`act`). Everything is local D-Bus: nothing leaves the
//! computer.

use std::sync::Arc;

use ksni::blocking::TrayMethods;
use ksni::menu::StandardItem;
use ksni::{Icon, MenuItem, ToolTip};

/// What a click in the tray asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    ToggleShown,
    ToggleLocked,
    Settings,
    CheckUpdates,
    Quit,
}

/// One line of the menu: a label and its action, or a separator (None).
pub type Entry = Option<(&'static str, Action)>;

/// The menu as it reads for the hub's state.
pub fn entries(shown: bool, locked: bool) -> Vec<Entry> {
    vec![
        Some((if shown { "Hide hub" } else { "Show hub" }, Action::ToggleShown)),
        Some((if locked { "Unlock" } else { "Lock" }, Action::ToggleLocked)),
        None,
        Some(("Settings", Action::Settings)),
        Some(("Check for updates", Action::CheckUpdates)),
        None,
        Some(("Quit", Action::Quit)),
    ]
}

/// The tooltip's second line.
pub fn state_text(shown: bool, locked: bool) -> String {
    format!(
        "{} · {}",
        if shown { "Hub shown" } else { "Hub hidden" },
        if locked { "locked (clicks go to the game)" } else { "unlocked" }
    )
}

/// The pictures in the sizes a panel asks for, from the icon set.
pub const SIZES: [i32; 6] = [16, 22, 24, 32, 48, 64];

pub struct GcTray {
    pub shown: bool,
    pub locked: bool,
    icons: Vec<Icon>,
    act: Arc<dyn Fn(Action) + Send + Sync>,
}

impl GcTray {
    /// `icons`: (size, ARGB32 in network byte order) per size.
    pub fn new(shown: bool, locked: bool, icons: Vec<(i32, Vec<u8>)>, act: impl Fn(Action) + Send + Sync + 'static) -> Self {
        let icons = icons
            .into_iter()
            .filter(|(size, data)| *size > 0 && data.len() == (*size as usize).pow(2) * 4)
            .map(|(size, data)| Icon { width: size, height: size, data })
            .collect();
        Self { shown, locked, icons, act: Arc::new(act) }
    }
}

impl ksni::Tray for GcTray {
    fn id(&self) -> String {
        "game-companion".into()
    }

    fn title(&self) -> String {
        "Game Companion".into()
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        self.icons.clone()
    }

    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            title: "Game Companion".into(),
            description: state_text(self.shown, self.locked),
            icon_name: String::new(),
            icon_pixmap: Vec::new(),
        }
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        (self.act)(Action::ToggleShown);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        entries(self.shown, self.locked)
            .into_iter()
            .map(|entry| match entry {
                Some((label, action)) => StandardItem {
                    label: label.into(),
                    activate: Box::new(move |tray: &mut GcTray| (tray.act)(action)),
                    ..Default::default()
                }
                .into(),
                None => MenuItem::Separator,
            })
            .collect()
    }

    /// The panel's tray went away (Plasma restarting): wait for it to come
    /// back rather than end.
    fn watcher_offline(&self, _reason: ksni::OfflineReason) -> bool {
        true
    }
}

pub type Handle = ksni::blocking::Handle<GcTray>;

/// Puts the icon into the panel. Blocks while it talks to the session bus:
/// call it off the Qt thread. With no tray in the panel yet (the app
/// started with the desktop before Plasma's panel), it waits for one.
pub fn spawn(tray: GcTray) -> Result<Handle, String> {
    tray.assume_sni_available(true).spawn().map_err(|e| e.to_string())
}

/// What the Qt thread tells the tray's worker.
enum Note {
    State { shown: bool, locked: bool },
    Shutdown,
}

/// The tray as the Qt thread holds it: changes go to a worker thread that
/// owns ksni's handle, since `Handle::update` blocks until ksni's own
/// thread has taken the change (it must never hold up the Qt thread). The
/// worker sleeps on its channel; only the newest state waiting is sent.
pub struct Worker {
    notes: std::sync::mpsc::Sender<Note>,
}

impl Worker {
    pub fn new(handle: Handle) -> Worker {
        Worker::with(move |note| match note {
            Some((shown, locked)) => {
                handle.update(|t| {
                    t.shown = shown;
                    t.locked = locked;
                });
            }
            None => drop(handle.shutdown()),
        })
    }

    /// `apply` gets each newest state, and None once to shut down.
    fn with(apply: impl Fn(Option<(bool, bool)>) + Send + 'static) -> Worker {
        let (notes, rx) = std::sync::mpsc::channel::<Note>();
        let _ = std::thread::Builder::new().name("tray-update".into()).spawn(move || {
            while let Ok(mut note) = rx.recv() {
                // Skip to the newest state; a shutdown wins.
                while let Ok(next) = rx.try_recv() {
                    if !matches!(note, Note::Shutdown) {
                        note = next;
                    }
                }
                match note {
                    Note::State { shown, locked } => apply(Some((shown, locked))),
                    Note::Shutdown => {
                        apply(None);
                        return;
                    }
                }
            }
        });
        Worker { notes }
    }

    /// Hands the hub's and the lock's state on; returns at once.
    pub fn set(&self, shown: bool, locked: bool) {
        let _ = self.notes.send(Note::State { shown, locked });
    }

    /// Takes the icon out of the panel (on the worker); returns at once.
    pub fn shutdown(self) {
        let _ = self.notes.send(Note::Shutdown);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ksni::Tray;
    use std::sync::Mutex;

    fn labels(shown: bool, locked: bool) -> Vec<&'static str> {
        entries(shown, locked).into_iter().map(|e| e.map_or("-", |(l, _)| l)).collect()
    }

    #[test]
    fn the_worker_sends_the_newest_state_off_the_caller() {
        use std::sync::mpsc;
        use std::time::Duration;
        let (tx, rx) = mpsc::channel();
        let slow = Mutex::new(tx);
        let worker = Worker::with(move |note| {
            // As slow as a busy ksni thread: the caller must not wait.
            std::thread::sleep(Duration::from_millis(100));
            let _ = slow.lock().unwrap().send(note);
        });
        let start = std::time::Instant::now();
        worker.set(true, true);
        worker.set(false, true);
        worker.set(false, false);
        assert!(start.elapsed() < Duration::from_millis(50));
        // Waiting ones become one: the newest arrives, at most one before.
        let mut got = Vec::new();
        while got.last() != Some(&Some((false, false))) {
            got.push(rx.recv_timeout(Duration::from_secs(2)).unwrap());
        }
        assert!(got.len() <= 2, "{got:?}");
        worker.shutdown();
        assert_eq!(rx.recv_timeout(Duration::from_secs(2)).unwrap(), None);
    }

    #[test]
    fn menu_follows_the_state() {
        assert_eq!(labels(true, true), ["Hide hub", "Unlock", "-", "Settings", "Check for updates", "-", "Quit"]);
        assert_eq!(labels(false, false), ["Show hub", "Lock", "-", "Settings", "Check for updates", "-", "Quit"]);
        assert!(state_text(false, true).starts_with("Hub hidden"));
    }

    #[test]
    fn clicks_ask_for_their_action() {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = seen.clone();
        let mut tray = GcTray::new(true, true, vec![(2, vec![0; 16]), (3, vec![0; 5])], move |a| log.lock().unwrap().push(a));
        assert_eq!(tray.icon_pixmap().len(), 1, "a picture of the wrong length is left out");
        tray.activate(0, 0);
        let menu = tray.menu();
        assert_eq!(menu.len(), 7);
        for item in &menu {
            if let MenuItem::Standard(item) = item {
                (item.activate)(&mut tray);
            }
        }
        assert_eq!(
            *seen.lock().unwrap(),
            [Action::ToggleShown, Action::ToggleShown, Action::ToggleLocked, Action::Settings, Action::CheckUpdates, Action::Quit]
        );
    }
}
