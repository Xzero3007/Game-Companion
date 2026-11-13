//! The AION 2 module for QML: runs the meter's capture and parser
//! (`aion2::engine`) while AION 2 runs, and gives the DPS panel the fight.
//! Only reads: nothing is sent to the game or anywhere else. Quiet while
//! nothing changes: QML hears of the fight only when it differs.

use std::path::PathBuf;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use aion2::engine::{self, Engine, Status};

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
        /// Whether the module reads now (AION 2 runs).
        #[qproperty(bool, active)]
        /// "off", "searching", "reading" or "failed".
        #[qproperty(QString, state)]
        /// Why it failed (empty otherwise).
        #[qproperty(QString, problem)]
        /// JSON {"time" ms, "target", "boss", "hpMax", "hpNow", "rows":
        /// [{"id","name","job","dps","amount","share","hps","heal","me","others"}]}.
        #[qproperty(QString, fight)]
        type Aion2 = super::Aion2Rust;

        /// Starts reading (AION 2 started).
        #[qinvokable]
        fn start(self: Pin<&mut Aion2>);

        /// Stops reading (AION 2 ended); the last fight stays shown.
        #[qinvokable]
        fn stop(self: Pin<&mut Aion2>);

        /// A new fight: what is counted goes.
        #[qinvokable]
        fn reset(self: Pin<&mut Aion2>);
    }

    impl cxx_qt::Threading for Aion2 {}
    impl cxx_qt::Initialize for Aion2 {}
}

pub struct Aion2Rust {
    active: bool,
    state: QString,
    problem: QString,
    fight: QString,
    engine: Option<Arc<Engine>>,
    /// Ends the watch thread of the engine that runs now.
    watching: Option<Arc<AtomicBool>>,
}

impl Default for Aion2Rust {
    fn default() -> Self {
        Aion2Rust {
            active: false,
            state: QString::from("off"),
            problem: QString::default(),
            fight: QString::from(EMPTY),
            engine: None,
            watching: None,
        }
    }
}

const EMPTY: &str = r#"{"time":0,"target":"","boss":false,"hpMax":0,"hpNow":0,"rows":[]}"#;

/// The helper: the package's, or GC_AION2_HELPER (a build of it, for tests).
fn helper() -> PathBuf {
    std::env::var_os("GC_AION2_HELPER").map_or_else(|| PathBuf::from(engine::HELPER), PathBuf::from)
}

impl cxx_qt::Initialize for qobject::Aion2 {
    fn initialize(mut self: Pin<&mut Self>) {
        if std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "dps")) {
            self.as_mut().set_active(true);
            self.as_mut().set_state(QString::from("reading"));
            self.as_mut().set_fight(QString::from(DEMO));
        }
    }
}

impl qobject::Aion2 {
    fn start(mut self: Pin<&mut Self>) {
        if self.engine.is_some() {
            return;
        }
        let engine = Arc::new(Engine::start(&helper(), &aion2::data_dir(), "en"));
        let stop = Arc::new(AtomicBool::new(false));
        self.as_mut().rust_mut().engine = Some(engine.clone());
        self.as_mut().rust_mut().watching = Some(stop.clone());
        self.as_mut().set_active(true);
        self.as_mut().set_state(QString::from("searching"));
        self.as_mut().set_problem(QString::default());

        // Every half second: the fight and the state, to QML only on change.
        let thread = self.qt_thread();
        let last = Arc::new(Mutex::new((String::new(), Status::Searching)));
        let _ = std::thread::Builder::new().name("aion2".into()).spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(500));
                let fight = engine::summary(&engine.snapshot()).to_string();
                let status = engine.status();
                let mut seen = last.lock().unwrap_or_else(|p| p.into_inner());
                let fight_changed = seen.0 != fight;
                let status_changed = seen.1 != status;
                if !fight_changed && !status_changed {
                    continue;
                }
                *seen = (fight.clone(), status.clone());
                drop(seen);
                let stop = stop.clone();
                let queued = thread.queue(move |mut obj: Pin<&mut qobject::Aion2>| {
                    if stop.load(Ordering::Relaxed) {
                        return;
                    }
                    if fight_changed {
                        obj.as_mut().set_fight(QString::from(&fight));
                    }
                    if status_changed {
                        let (state, problem) = match status {
                            Status::Searching => ("searching", String::new()),
                            Status::Reading(_) => ("reading", String::new()),
                            Status::Failed(why) => ("failed", why),
                        };
                        obj.as_mut().set_state(QString::from(state));
                        obj.as_mut().set_problem(QString::from(&problem));
                    }
                });
                if queued.is_err() {
                    break;
                }
            }
        });
    }

    fn stop(mut self: Pin<&mut Self>) {
        if let Some(stop) = self.as_mut().rust_mut().watching.take() {
            stop.store(true, Ordering::Relaxed);
        }
        if let Some(engine) = self.as_mut().rust_mut().engine.take() {
            engine.stop();
        }
        self.as_mut().set_active(false);
        self.as_mut().set_state(QString::from("off"));
    }

    fn reset(mut self: Pin<&mut Self>) {
        if let Some(engine) = &self.engine {
            engine.reset();
        }
        self.as_mut().set_fight(QString::from(EMPTY));
    }
}

/// A made-up fight for screenshots (GC_DEMO=dps).
const DEMO: &str = r#"{"time":134000,"target":"Training Scarecrow","boss":false,"hpMax":0,"hpNow":0,"rows":[
{"id":1,"name":"Lumen","job":"Sorcerer","dps":41200,"amount":5520800,"share":26.0,"hps":0,"heal":0,"me":true,"others":false},
{"id":2,"name":"Party 2","job":"Gladiator","dps":35400,"amount":4743600,"share":22.3,"hps":0,"heal":0,"me":false,"others":false},
{"id":3,"name":"Party 3","job":"Ranger","dps":29300,"amount":3926200,"share":18.4,"hps":0,"heal":0,"me":false,"others":false},
{"id":4,"name":"Party 4","job":"Assassin","dps":23900,"amount":3202600,"share":15.0,"hps":0,"heal":0,"me":false,"others":false},
{"id":5,"name":"Party 5","job":"Templar","dps":16500,"amount":2211000,"share":10.4,"hps":1200,"heal":160800,"me":false,"others":false},
{"id":6,"name":"Party 6","job":"Cleric","dps":9100,"amount":1219400,"share":7.7,"hps":14800,"heal":1983200,"me":false,"others":false}]}"#;

#[cfg(test)]
mod tests {
    #[test]
    fn the_demo_and_the_empty_fight_read() {
        for text in [super::DEMO, super::EMPTY] {
            let v: serde_json::Value = serde_json::from_str(text).unwrap();
            assert!(v["rows"].is_array());
        }
    }
}
