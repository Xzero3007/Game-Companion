//! The PoE 2 price check for QML (the `Poe2` singleton): the trade site's
//! requests in the background, EE2's data files, the clipboard watcher and
//! the price check's choices (`poe2`).

use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::Value;

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
        /// The price check's choices as JSON (QML fills in the defaults).
        #[qproperty(QString, prefs)]
        /// Whether copied items are looked at now (PoE 2 runs, price check on).
        #[qproperty(bool, watching)]
        /// Why the clipboard cannot be watched, or "".
        #[qproperty(QString, watch_error)]
        type Poe2 = super::Poe2Rust;

        /// Asks the trade site (www.pathofexile.com/api/trade2/ only) in
        /// the background; the answer comes as `answered(id, …)`.
        #[qinvokable]
        fn request(self: Pin<&mut Poe2>, id: i32, method: &QString, url: &QString, body: &QString);

        /// A file of EE2's data (`en/items.ndjson`), "" if missing.
        #[qinvokable]
        fn data_file(self: &Poe2, name: &QString) -> QString;

        /// Keeps one choice (`value` is JSON).
        #[qinvokable]
        fn set_pref(self: Pin<&mut Poe2>, key: &QString, value: &QString);

        /// Looks at copied items or stops (the watcher starts on first use).
        #[qinvokable]
        fn watch(self: Pin<&mut Poe2>, on: bool);

        /// The answer of `request`: status (0 = no answer, then `body`
        /// says why), the headers as JSON, the body.
        #[qsignal]
        fn answered(self: Pin<&mut Poe2>, id: i32, status: i32, headers: QString, body: QString);

        /// An item's text, copied in the game (Ctrl+C over it).
        #[qsignal]
        fn copied(self: Pin<&mut Poe2>, text: QString);
    }

    impl cxx_qt::Threading for Poe2 {}
}

pub struct Poe2Rust {
    prefs: QString,
    watching: bool,
    watch_error: QString,
    on: Arc<AtomicBool>,
    started: bool,
}

impl Default for Poe2Rust {
    fn default() -> Self {
        let prefs = Value::Object(settings::read(|s| s.poe2.clone())).to_string();
        Self { prefs: QString::from(&prefs), watching: false, watch_error: QString::default(), on: Arc::new(AtomicBool::new(false)), started: false }
    }
}

impl qobject::Poe2 {
    fn request(self: Pin<&mut Self>, id: i32, method: &QString, url: &QString, body: &QString) {
        let (method, url, body) = (method.to_string(), url.to_string(), body.to_string());
        let thread = self.qt_thread();
        let _ = std::thread::Builder::new().name("poe2-trade".into()).spawn(move || {
            let (status, headers, body) = match crate::poe2::request(&method, &url, &body) {
                Ok(a) => (i32::from(a.status), Value::Object(a.headers).to_string(), a.body),
                Err(why) => (0, "{}".to_string(), why),
            };
            let _ = thread.queue(move |obj: Pin<&mut qobject::Poe2>| obj.answered(id, status, QString::from(&headers), QString::from(&body)));
        });
    }

    fn data_file(&self, name: &QString) -> QString {
        QString::from(&crate::poe2::data_file(&name.to_string()))
    }

    fn set_pref(mut self: Pin<&mut Self>, key: &QString, value: &QString) {
        let key = key.to_string();
        let Ok(value) = serde_json::from_str::<Value>(&value.to_string()) else { return };
        let all = settings::change(|s| {
            s.poe2.insert(key, value);
            s.poe2.clone()
        });
        self.as_mut().set_prefs(QString::from(&Value::Object(all).to_string()));
    }

    fn watch(mut self: Pin<&mut Self>, on: bool) {
        self.rust().on.store(on, Ordering::Relaxed);
        if on && !self.rust().started {
            self.as_mut().rust_mut().started = true;
            let flag = self.rust().on.clone();
            let thread = self.qt_thread();
            let told = self.qt_thread();
            let result = crate::poe2::watch_clipboard(
                move || flag.load(Ordering::Relaxed),
                move |text| {
                    let _ = thread.queue(move |obj: Pin<&mut qobject::Poe2>| obj.copied(QString::from(&text)));
                },
                move |why| {
                    let why = why.unwrap_or_default();
                    let _ = told.queue(move |obj: Pin<&mut qobject::Poe2>| obj.set_watch_error(QString::from(&why)));
                },
            );
            if let Err(why) = result {
                self.as_mut().rust_mut().started = false;
                self.as_mut().set_watch_error(QString::from(&why));
            } else {
                self.as_mut().set_watch_error(QString::default());
            }
        }
        self.as_mut().set_watching(on);
    }
}
