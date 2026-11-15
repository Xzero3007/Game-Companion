//! The PoE 2 session tracker's link to the game's log for QML (the
//! `Poe2Log` singleton): follows Client.txt while PoE 2 runs and keeps the
//! tracker's own files. See src/poe2_log.rs for what is read.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

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
        /// The log being read (home folder as `~`), "" while none is found.
        #[qproperty(QString, file)]
        /// Whether the log is followed now.
        #[qproperty(bool, watching)]
        type Poe2Log = super::Poe2LogRust;

        /// Follows the log (`path` "" finds it) or stops.
        #[qinvokable]
        fn watch(self: Pin<&mut Poe2Log>, on: bool, path: &QString);

        /// The tracker's file under a key (JSON, "" for none).
        #[qinvokable]
        fn load(self: &Poe2Log, key: &QString) -> QString;

        /// Keeps the tracker's file under a key, in the background.
        #[qinvokable]
        fn keep(self: &Poe2Log, key: &QString, json: &QString);

        /// What the log said: a JSON list of events (k: area, named, level,
        /// death, afk; t in ms).
        #[qsignal]
        fn heard(self: Pin<&mut Poe2Log>, events: QString);
    }

    impl cxx_qt::Threading for Poe2Log {}
}

#[derive(Default)]
pub struct Poe2LogRust {
    file: QString,
    watching: bool,
    path: String,
}

impl qobject::Poe2Log {
    fn watch(mut self: Pin<&mut Self>, on: bool, path: &QString) {
        let path = path.to_string();
        if on == *self.watching() && (!on || path == self.rust().path) {
            return;
        }
        self.as_mut().rust_mut().path = path.clone();
        if !on {
            crate::poe2_log::stop();
            self.as_mut().set_watching(false);
            self.as_mut().set_file(QString::default());
            return;
        }
        let heard = self.qt_thread();
        let told = self.qt_thread();
        crate::poe2_log::watch(
            path,
            move |events| {
                let text = serde_json::Value::Array(events).to_string();
                let _ = heard.queue(move |obj: Pin<&mut qobject::Poe2Log>| obj.heard(QString::from(&text)));
            },
            move |file| {
                let _ = told.queue(move |obj: Pin<&mut qobject::Poe2Log>| {
                    if *obj.watching() {
                        obj.set_file(QString::from(&file));
                    }
                });
            },
        );
        self.as_mut().set_watching(true);
    }

    fn load(&self, key: &QString) -> QString {
        QString::from(&crate::poe2_log::load(&key.to_string()))
    }

    fn keep(&self, key: &QString, json: &QString) {
        crate::poe2_log::keep(key.to_string(), json.to_string());
    }
}
