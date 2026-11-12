//! Updates for QML: looks at the start, every 20 minutes and when asked; the
//! bar's update button and Settings show it, and install it.

use std::pin::Pin;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::updater::{self, Release};

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
        /// idle, checking, current, available, downloading, installing, failed.
        #[qproperty(QString, state)]
        /// The latest release ("0.3.0 (build 12)"), once known.
        #[qproperty(QString, latest)]
        /// A line for Settings: what happened, in plain words.
        #[qproperty(QString, message)]
        type Updates = super::UpdatesRust;

        /// Looks for an update now.
        #[qinvokable]
        fn check(self: Pin<&mut Updates>);

        /// Downloads the update, starts the installer and quits; the app
        /// starts again once it is installed.
        #[qinvokable]
        fn install(self: Pin<&mut Updates>);
    }

    impl cxx_qt::Threading for Updates {}
    impl cxx_qt::Initialize for Updates {}
}

pub struct UpdatesRust {
    state: QString,
    latest: QString,
    message: QString,
    release: Option<Release>,
}

impl Default for UpdatesRust {
    fn default() -> Self {
        Self {
            state: QString::from("idle"),
            latest: QString::default(),
            message: QString::default(),
            release: None,
        }
    }
}

impl cxx_qt::Initialize for qobject::Updates {
    fn initialize(mut self: Pin<&mut Self>) {
        if std::env::var("GC_DEMO").is_ok_and(|d| d.contains("update")) {
            self.as_mut().set_latest(QString::from("0.3.0 (build 7)"));
            self.as_mut().say("available", "Update 0.3.0 (build 7) is ready to install.");
            return;
        }
        if std::env::var_os("GC_NO_UPDATES").is_some() {
            return;
        }
        // Shortly after the start, then every 20 minutes.
        let thread = self.qt_thread();
        std::thread::Builder::new()
            .name("updates".into())
            .spawn(move || {
                std::thread::sleep(Duration::from_secs(10));
                loop {
                    if thread.queue(|obj: Pin<&mut qobject::Updates>| obj.check()).is_err() {
                        break;
                    }
                    std::thread::sleep(Duration::from_secs(20 * 60));
                }
            })
            .ok();
    }
}

impl qobject::Updates {
    fn say(mut self: Pin<&mut Self>, state: &str, message: &str) {
        self.as_mut().set_state(QString::from(state));
        self.set_message(QString::from(message));
    }

    fn check(mut self: Pin<&mut Self>) {
        let state = self.state().to_string();
        if matches!(state.as_str(), "checking" | "downloading" | "installing") {
            return;
        }
        self.as_mut().say("checking", "Looking for an update…");
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = updater::fetch_latest();
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Updates>| match result {
                Ok(release) => {
                    obj.as_mut().set_latest(QString::from(&release.label()));
                    let newer = updater::is_newer(&release, updater::current_build());
                    let label = release.label();
                    obj.as_mut().rust_mut().release = Some(release);
                    if newer {
                        obj.say("available", &format!("Update {label} is ready to install."));
                    } else {
                        obj.say("current", "Game Companion is up to date.");
                    }
                }
                Err(why) => obj.say("failed", &why),
            });
        });
    }

    fn install(mut self: Pin<&mut Self>) {
        let Some(release) = self.rust().release.clone() else { return };
        if self.state().to_string() != "available" {
            return;
        }
        if !updater::installed_by_pacman() {
            self.say(
                "available",
                "This copy was built by hand: install the update with \"git pull\" and \"makepkg -si\", or install the release package once with pacman.",
            );
            return;
        }
        self.as_mut().say("downloading", &format!("Downloading {}…", release.label()));
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            // The latest release again, right now: the root script installs
            // only that one, so an older one found earlier would be refused
            // (and the password asked).
            let result = updater::fetch_latest()
                .map(|latest| if latest.build >= release.build { latest } else { release })
                .and_then(|release| updater::download(&release))
                .and_then(|file| updater::start_install(&file));
            let _ = thread.queue(move |obj: Pin<&mut qobject::Updates>| match result {
                Ok(()) => {
                    obj.say("installing", "Installing; Game Companion starts again in a moment.");
                    // The installer waits for the app to close.
                    quit_soon();
                }
                Err(why) => obj.say("failed", &why),
            });
        });
    }
}

/// Quits the app after a moment, so the last message shows.
fn quit_soon() {
    std::thread::spawn(|| {
        std::thread::sleep(Duration::from_millis(800));
        crate::native::quit();
        // The installer waits for this process to end: should Qt not
        // finish closing, it ends anyway (mpv goes with it).
        std::thread::sleep(Duration::from_secs(5));
        std::process::exit(0);
    });
}
