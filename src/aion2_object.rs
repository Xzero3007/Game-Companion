//! The AION 2 module for QML: runs the meter's capture and parser
//! (`aion2::engine`) while AION 2 runs, and gives the DPS panel the fight.
//! Only reads: nothing is sent to the game or anywhere else. Quiet while
//! nothing changes: QML hears of the fight only when it differs.

use std::path::PathBuf;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use aion2::engine::{self, Engine, Status};
use aion2::history;

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
        /// The player whose skills show (0: the one playing).
        #[qproperty(i32, picked)]
        /// That player's skills: JSON [{"code","name","casts","damage",
        /// "share","crit","back","perfect","double","parry"}].
        #[qproperty(QString, skills)]
        /// Battle History, newest first: JSON [{"id","boss","start",
        /// "duration","total","jobs","train"}].
        #[qproperty(QString, history)]
        /// A saved fight shown in place of the live one ("" for live).
        #[qproperty(QString, opened)]
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

        /// Shows a saved fight (its id), or the live one again ("").
        #[qinvokable]
        fn open_fight(self: Pin<&mut Aion2>, id: &QString);

        /// Removes a saved fight.
        #[qinvokable]
        fn remove_fight(self: Pin<&mut Aion2>, id: &QString);

        /// Shows this player's skills (0: the one playing).
        #[qinvokable]
        fn pick(self: Pin<&mut Aion2>, actor: i32);
    }

    impl cxx_qt::Threading for Aion2 {}
    impl cxx_qt::Initialize for Aion2 {}
}

pub struct Aion2Rust {
    active: bool,
    state: QString,
    problem: QString,
    fight: QString,
    picked: i32,
    skills: QString,
    history: QString,
    opened: QString,
    /// The live fight while a saved one is shown.
    live: String,
    /// `picked`, for the watch thread.
    wanted: Arc<AtomicI32>,
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
            picked: 0,
            skills: QString::from("[]"),
            history: QString::from("[]"),
            opened: QString::default(),
            live: EMPTY.to_string(),
            wanted: Arc::new(AtomicI32::new(0)),
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
            self.as_mut().set_skills(QString::from(DEMO_SKILLS));
            self.as_mut().set_history(QString::from(DEMO_HISTORY));
            return;
        }
        let list = history::list(&history::default_dir()).to_string();
        self.as_mut().set_history(QString::from(&list));
    }
}

impl qobject::Aion2 {
    fn start(mut self: Pin<&mut Self>) {
        if self.engine.is_some() {
            return;
        }
        let engine = Arc::new(Engine::start(&helper(), &aion2::data_dir(), "en", &history::default_dir()));
        let stop = Arc::new(AtomicBool::new(false));
        self.as_mut().rust_mut().engine = Some(engine.clone());
        self.as_mut().rust_mut().watching = Some(stop.clone());
        self.as_mut().set_active(true);
        self.as_mut().set_state(QString::from("searching"));
        self.as_mut().set_problem(QString::default());

        // Every half second: the fight and the state, to QML only on change.
        let thread = self.qt_thread();
        let last = Arc::new(Mutex::new((String::new(), Status::Searching, String::new(), 0u64)));
        let wanted = self.wanted.clone();
        let _ = std::thread::Builder::new().name("aion2".into()).spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(500));
                let snapshot = engine.snapshot();
                let fight = engine::summary(&snapshot).to_string();
                let actor = match wanted.load(Ordering::Relaxed) {
                    0 => snapshot.local_player_id.map_or(0, |id| id as i32),
                    id => id,
                };
                let skills = engine::skills(&snapshot, actor).to_string();
                let status = engine.status();
                let mut seen = last.lock().unwrap_or_else(|p| p.into_inner());
                let fight_changed = seen.0 != fight;
                let status_changed = seen.1 != status;
                let skills_changed = seen.2 != skills;
                let saved = engine.saved();
                let history_changed = seen.3 != saved;
                if !fight_changed && !status_changed && !skills_changed && !history_changed {
                    continue;
                }
                *seen = (fight.clone(), status.clone(), skills.clone(), saved);
                let list = history_changed.then(|| history::list(&history::default_dir()).to_string());
                drop(seen);
                let stop = stop.clone();
                let queued = thread.queue(move |mut obj: Pin<&mut qobject::Aion2>| {
                    if stop.load(Ordering::Relaxed) {
                        return;
                    }
                    if let Some(list) = &list {
                        obj.as_mut().set_history(QString::from(list));
                    }
                    // A saved fight shown: the live one waits.
                    let showing_saved = !obj.opened().is_empty();
                    if fight_changed {
                        if showing_saved {
                            obj.as_mut().rust_mut().live = fight;
                        } else {
                            obj.as_mut().set_fight(QString::from(&fight));
                        }
                    }
                    if skills_changed && !showing_saved {
                        obj.as_mut().set_skills(QString::from(&skills));
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
            // Saves what is still on the meter.
            engine.stop();
            let list = history::list(&history::default_dir()).to_string();
            self.as_mut().set_history(QString::from(&list));
        }
        self.as_mut().set_active(false);
        self.as_mut().set_state(QString::from("off"));
    }

    fn reset(mut self: Pin<&mut Self>) {
        if let Some(engine) = &self.engine {
            engine.reset();
            let list = history::list(&history::default_dir()).to_string();
            self.as_mut().set_history(QString::from(&list));
        }
        self.as_mut().set_fight(QString::from(EMPTY));
        self.as_mut().set_skills(QString::from("[]"));
    }

    fn open_fight(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        if id.is_empty() {
            if !self.opened.is_empty() {
                let live = std::mem::take(&mut self.as_mut().rust_mut().live);
                self.as_mut().set_opened(QString::default());
                self.as_mut().set_fight(QString::from(if live.is_empty() { EMPTY } else { &live }));
                self.as_mut().set_skills(QString::from("[]"));
            }
            return;
        }
        let Some(record) = history::load(&history::default_dir(), &id) else { return };
        if self.opened.is_empty() {
            let live = self.fight.to_string();
            self.as_mut().rust_mut().live = live;
        }
        self.as_mut().set_opened(QString::from(&id));
        self.as_mut().set_fight(QString::from(&history::summary(&record).to_string()));
        self.as_mut().set_skills(QString::from("[]"));
    }

    fn remove_fight(mut self: Pin<&mut Self>, id: &QString) {
        let dir = history::default_dir();
        if history::remove(&dir, &id.to_string()) {
            if self.opened == *id {
                self.as_mut().open_fight(&QString::default());
            }
            let list = history::list(&dir).to_string();
            self.as_mut().set_history(QString::from(&list));
        }
    }

    fn pick(mut self: Pin<&mut Self>, actor: i32) {
        self.wanted.store(actor, Ordering::Relaxed);
        self.as_mut().set_picked(actor);
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

/// Made-up history for screenshots (GC_DEMO=dps,history).
const DEMO_HISTORY: &str = r#"[
{"id":"f3","boss":"Tahabata","start":1794549600000,"duration":312000,"total":48210000,"jobs":["Sorcerer","Gladiator","Cleric"],"train":false},
{"id":"f2","boss":"Brigade General Vasharti","start":1794546000000,"duration":201000,"total":30400000,"jobs":["Sorcerer","Ranger"],"train":false},
{"id":"f1","boss":"Training Scarecrow","start":1794542400000,"duration":60000,"total":2400000,"jobs":["Sorcerer"],"train":true}]"#;

/// Made-up skills for screenshots (GC_DEMO=dps,skills).
const DEMO_SKILLS: &str = r#"[
{"code":1,"name":"Flame Cascade","casts":38,"damage":1876500,"share":34.0,"crit":42.1,"back":0.0,"perfect":10.5,"double":13.2,"parry":0.0},
{"code":2,"name":"Frost Lance","casts":61,"damage":1214600,"share":22.0,"crit":36.0,"back":0.0,"perfect":8.2,"double":9.8,"parry":1.6},
{"code":3,"name":"Burning Mark","casts":12,"damage":993700,"share":18.0,"crit":25.0,"back":0.0,"perfect":0.0,"double":0.0,"parry":0.0},
{"code":4,"name":"Arcane Bolt","casts":94,"damage":828100,"share":15.0,"crit":30.9,"back":0.0,"perfect":5.3,"double":7.4,"parry":2.1},
{"code":5,"name":"Meteor","casts":4,"damage":607900,"share":11.0,"crit":50.0,"back":0.0,"perfect":25.0,"double":0.0,"parry":0.0}]"#;

#[cfg(test)]
mod tests {
    #[test]
    fn the_demo_and_the_empty_fight_read() {
        for text in [super::DEMO, super::EMPTY] {
            let v: serde_json::Value = serde_json::from_str(text).unwrap();
            assert!(v["rows"].is_array());
        }
        let history: serde_json::Value = serde_json::from_str(super::DEMO_HISTORY).unwrap();
        assert_eq!(history.as_array().map(|a| a.len()), Some(3));
        let skills: serde_json::Value = serde_json::from_str(super::DEMO_SKILLS).unwrap();
        assert_eq!(skills.as_array().map(|a| a.len()), Some(5));
    }
}
