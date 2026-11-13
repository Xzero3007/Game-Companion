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
        /// The world around the player for the map: JSON {"zone", "me"
        /// {x,y,z}, "mobs", "objects", ...} ("{}" until something is known).
        #[qproperty(QString, world)]
        /// Who plays and what the game said of them (the meter's
        /// `character` event, `Engine::character`): JSON, "null" before
        /// anyone is known.
        #[qproperty(QString, character)]
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

        /// The Map's pictures (tiles/, icons/) as a file URL, no slash at the end.
        #[qinvokable]
        fn map_dir(self: &Aion2) -> QString;

        /// The Map's own choices (layers, follow, zoom ...), JSON ("{}" none).
        #[qinvokable]
        fn map_settings(self: &Aion2) -> QString;

        /// Keeps the Map's choices (JSON, at most 64 KB).
        #[qinvokable]
        fn save_map_settings(self: &Aion2, json: &QString);

        /// Asks the Market's price sources for `url` (Clicktrough's copy or
        /// aion2.exchange only); the answer comes as `web_got(id, ...)`.
        #[qinvokable]
        fn web_get(self: Pin<&mut Aion2>, id: i32, url: &QString);

        /// An answer of `web_get`: ok and the text, or not and why.
        #[qsignal]
        fn web_got(self: Pin<&mut Aion2>, id: i32, ok: bool, body: QString);

        /// A game icon as a file URL when it is kept, else "" and it is
        /// downloaded once (`icon_ready` then).
        #[qinvokable]
        fn icon(self: Pin<&mut Aion2>, name: &QString) -> QString;

        /// An icon is kept now.
        #[qsignal]
        fn icon_ready(self: Pin<&mut Aion2>, name: QString);

        /// A module's own file (aion2-<key>.json), "" for none.
        #[qinvokable]
        fn load_store(self: &Aion2, key: &QString) -> QString;

        /// Keeps a module's own file (JSON, at most 4 MB), in the background.
        #[qinvokable]
        fn keep_store(self: &Aion2, key: &QString, json: &QString);

        /// The game's servers by number, their English names: JSON
        /// {"1001": "Siel", ...} (the meter's list, in the package).
        #[qinvokable]
        fn server_names(self: &Aion2) -> QString;
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
    world: QString,
    character: QString,
    opened: QString,
    /// The live fight while a saved one is shown.
    live: String,
    /// `picked`, for the watch thread.
    wanted: Arc<AtomicI32>,
    engine: Option<Arc<Engine>>,
    /// Icons being downloaded (asked once each).
    icons_asked: Arc<Mutex<std::collections::HashSet<String>>>,
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
            world: QString::from("{}"),
            character: QString::from("null"),
            opened: QString::default(),
            live: EMPTY.to_string(),
            wanted: Arc::new(AtomicI32::new(0)),
            engine: None,
            icons_asked: Arc::default(),
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
        // GC_DEMO=dpslive: starts empty, then a made-up fight that changes
        // every half second (as a real measurement does), for input checks.
        if std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "dpslive")) {
            self.as_mut().set_active(true);
            self.as_mut().set_state(QString::from("reading"));
            self.as_mut().set_fight(QString::from(EMPTY));
            let thread = self.qt_thread();
            let _ = std::thread::Builder::new().name("aion2-demo".into()).spawn(move || {
                std::thread::sleep(Duration::from_secs(6));
                for tick in 0u64.. {
                    std::thread::sleep(Duration::from_millis(500));
                    let mut fight: serde_json::Value = serde_json::from_str(DEMO).unwrap_or_default();
                    fight["time"] = (tick * 500).into();
                    if let Some(rows) = fight["rows"].as_array_mut() {
                        rows.truncate(1 + (tick as usize / 4).min(5));
                        for row in rows.iter_mut() {
                            let dps = row["dps"].as_u64().unwrap_or(0);
                            row["dps"] = (dps + tick * 37 % 900).into();
                        }
                    }
                    let fight = fight.to_string();
                    if thread.queue(move |mut obj: Pin<&mut qobject::Aion2>| obj.as_mut().set_fight(QString::from(&fight))).is_err() {
                        break;
                    }
                }
            });
            return;
        }
        // GC_DEMO=map: standing in Verteron with monsters around.
        if std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "map")) {
            self.as_mut().set_active(true);
            self.as_mut().set_world(QString::from(DEMO_WORLD));
        }
        if std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "dps")) {
            self.as_mut().set_active(true);
            self.as_mut().set_state(QString::from("reading"));
            let party = std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "party"));
            self.as_mut().set_fight(QString::from(if party { DEMO_PARTY } else { DEMO }));
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
        let last = Arc::new(Mutex::new((String::new(), Status::Searching, String::new(), 0u64, String::from("null"))));
        let wanted = self.wanted.clone();
        let _ = std::thread::Builder::new().name("aion2".into()).spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(500));
                let snapshot = engine.snapshot();
                let mut fight = engine::summary(&snapshot);
                fight["extras"] = engine.extras();
                let fight = fight.to_string();
                let actor = match wanted.load(Ordering::Relaxed) {
                    0 => snapshot.local_player_id.map_or(0, |id| id as i32),
                    id => id,
                };
                let skills = engine.live_skills(&snapshot, actor).to_string();
                let status = engine.status();
                let mut seen = last.lock().unwrap_or_else(|p| p.into_inner());
                let fight_changed = seen.0 != fight;
                let status_changed = seen.1 != status;
                let skills_changed = seen.2 != skills;
                let saved = engine.saved();
                let history_changed = seen.3 != saved;
                let world = engine.world().map(|w| w.to_string());
                let character = engine.character().to_string();
                let character_changed = seen.4 != character;
                if !fight_changed && !status_changed && !skills_changed && !history_changed && world.is_none() && !character_changed {
                    continue;
                }
                *seen = (fight.clone(), status.clone(), skills.clone(), saved, character.clone());
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
                    if let Some(world) = &world {
                        obj.as_mut().set_world(QString::from(world));
                    }
                    if character_changed {
                        obj.as_mut().set_character(QString::from(&character));
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
        self.as_mut().set_character(QString::from("null"));
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
        let summary = history::summary(&record);
        // The saved fight's skills: the picked player's, else the top row's.
        let picked = *self.picked();
        let actor = summary["rows"]
            .as_array()
            .and_then(|rows| {
                rows.iter()
                    .find(|r| picked != 0 && r["id"].as_i64() == Some(picked as i64))
                    .or_else(|| rows.iter().find(|r| r["me"].as_bool() == Some(true)))
                    .or_else(|| rows.first())
            })
            .and_then(|r| r["id"].as_i64())
            .unwrap_or(0) as i32;
        let skills = engine::detail_skills(&record.details.skills, actor).to_string();
        self.as_mut().set_fight(QString::from(&summary.to_string()));
        self.as_mut().set_skills(QString::from(&skills));
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

    fn map_dir(&self) -> QString {
        let dir = aion2::data_dir().join("map");
        QString::from(&format!("file://{}", dir.display()))
    }

    fn map_settings(&self) -> QString {
        let text = map_settings_file().and_then(|p| std::fs::read_to_string(p).ok()).unwrap_or_default();
        let ok = serde_json::from_str::<serde_json::Value>(&text).is_ok_and(|v| v.is_object());
        QString::from(if ok { text.as_str() } else { "{}" })
    }

    fn save_map_settings(&self, json: &QString) {
        let text = json.to_string();
        if text.len() > 64 * 1024 || !serde_json::from_str::<serde_json::Value>(&text).is_ok_and(|v| v.is_object()) {
            return;
        }
        if let Some(path) = map_settings_file() {
            let tmp = path.with_extension("json.tmp");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, &path);
            }
        }
    }

    fn web_get(self: Pin<&mut Self>, id: i32, url: &QString) {
        let url = url.to_string();
        let thread = self.qt_thread();
        let _ = std::thread::Builder::new().name("aion2-market".into()).spawn(move || {
            let (ok, body) = match crate::market::get(&url) {
                Ok(text) => (true, text),
                Err(why) => (false, why),
            };
            let _ = thread.queue(move |obj: Pin<&mut qobject::Aion2>| obj.web_got(id, ok, QString::from(&body)));
        });
    }

    fn icon(self: Pin<&mut Self>, name: &QString) -> QString {
        let name = name.to_string();
        if let Some(path) = crate::market::icon_file(&name) {
            return QString::from(&format!("file://{}", path.display()));
        }
        if !crate::market::icon_name_ok(&name) || std::env::var("GC_NO_ICON_DOWNLOADS").is_ok_and(|v| !v.is_empty() && v != "0") {
            return QString::default();
        }
        let asked = self.icons_asked.clone();
        if !asked.lock().unwrap_or_else(|p| p.into_inner()).insert(name.clone()) {
            return QString::default();
        }
        let thread = self.qt_thread();
        let _ = std::thread::Builder::new().name("aion2-icon".into()).spawn(move || {
            // One at a time across the app: the icon server is asked gently.
            static TURN: Mutex<()> = Mutex::new(());
            let _turn = TURN.lock().unwrap_or_else(|p| p.into_inner());
            if crate::market::fetch_icon(&name).is_ok() {
                let _ = thread.queue(move |obj: Pin<&mut qobject::Aion2>| obj.icon_ready(QString::from(&name)));
            }
        });
        QString::default()
    }

    fn load_store(&self, key: &QString) -> QString {
        QString::from(&crate::market::load(&key.to_string()))
    }

    fn keep_store(&self, key: &QString, json: &QString) {
        // The newest of a key is written, whichever thread comes first: a
        // thread finding its key taken by a later one's write does nothing.
        static PENDING: Mutex<Option<std::collections::HashMap<String, String>>> = Mutex::new(None);
        let key = key.to_string();
        PENDING.lock().unwrap_or_else(|p| p.into_inner()).get_or_insert_with(Default::default).insert(key.clone(), json.to_string());
        let _ = std::thread::Builder::new().name("aion2-store".into()).spawn(move || {
            static TURN: Mutex<()> = Mutex::new(());
            let _turn = TURN.lock().unwrap_or_else(|p| p.into_inner());
            let json = PENDING.lock().unwrap_or_else(|p| p.into_inner()).as_mut().and_then(|m| m.remove(&key));
            if let Some(json) = json {
                crate::market::keep(&key, &json);
            }
        });
    }

    fn server_names(&self) -> QString {
        QString::from(&server_names_of(&aion2::data_dir().join("servers.json")))
    }

    fn pick(mut self: Pin<&mut Self>, actor: i32) {
        self.wanted.store(actor, Ordering::Relaxed);
        self.as_mut().set_picked(actor);
        // A saved fight shown: its skills follow the pick at once.
        let opened = self.opened().clone();
        if !opened.is_empty() {
            self.open_fight(&opened);
        }
    }
}

/// The servers' English names from the meter's list ({"servers": {"1001":
/// {"en": "Siel", ...}}}), "{}" when it can't be read.
fn server_names_of(path: &std::path::Path) -> String {
    let Ok(text) = std::fs::read_to_string(path) else { return "{}".into() };
    let Ok(doc) = serde_json::from_str::<serde_json::Value>(&text) else { return "{}".into() };
    let names: serde_json::Map<String, serde_json::Value> = doc["servers"]
        .as_object()
        .map(|all| {
            all.iter()
                .filter_map(|(id, n)| n["en"].as_str().map(|en| (id.clone(), serde_json::Value::from(en))))
                .collect()
        })
        .unwrap_or_default();
    serde_json::Value::Object(names).to_string()
}

/// The Map's choices, beside settings.json.
fn map_settings_file() -> Option<PathBuf> {
    crate::settings::Settings::path().map(|p| p.with_file_name("aion2-map.json"))
}

/// A made-up world for screenshots (GC_DEMO=map): Verteron.
const DEMO_WORLD: &str = r#"{"at":0,"zone":902,"me":{"x":-108000,"y":-56000,"exact":true},"moving":false,
"npcs":[[11,2100002,-110660,-58525],[12,2100006,-74581,-53904],[13,2100015,-74634,-51920],[14,2100009,-111486,-24906]],"objects":[]}"#;

/// A made-up fight for screenshots (GC_DEMO=dps).
const DEMO: &str = r#"{"time":242000,"target":"Brigade General Vasharti","boss":true,"hpMax":161000000,"hpNow":61200000,"rows":[
{"id":1,"name":"Lumen","job":"Ranger","dps":168400,"amount":40752800,"share":40.8,"hps":0,"heal":0,"me":true,"others":false,"cp":210400,"gs":3072},
{"id":2,"name":"Party 2","job":"Spiritmaster","dps":121300,"amount":29354600,"share":29.4,"hps":0,"heal":0,"me":false,"others":false,"cp":205100,"gs":3050},
{"id":3,"name":"Party 3","job":"Chanter","dps":64200,"amount":15536400,"share":15.6,"hps":3100,"heal":750200,"me":false,"others":false,"cp":197300,"gs":3013},
{"id":4,"name":"Party 4","job":"Templar","dps":36900,"amount":8929800,"share":8.9,"hps":1200,"heal":290400,"me":false,"others":false,"cp":210000,"gs":3032},
{"id":5,"name":"Party 5","job":"Cleric","dps":21800,"amount":5275600,"share":5.3,"hps":14800,"heal":3581600,"me":false,"others":false,"cp":208200,"gs":2965}],"extras":{"ping":14,"odyle":[90,1850]}}"#;

/// A party that just formed (GC_DEMO=dps,party): only the player has hit.
const DEMO_PARTY: &str = r#"{"time":20000,"target":"Melee Training Scarecrow","boss":false,"hpMax":119700,"hpNow":119700,"rows":[
{"id":1,"name":"Lumen","job":"Ranger","dps":168000,"amount":3360000,"share":100.0,"hps":0,"heal":0,"me":true,"others":false,"cp":210400,"gs":3072},
{"id":90000002,"name":"Party 2","job":"Spiritmaster","dps":0,"amount":0,"share":0.0,"hps":0,"heal":0,"me":false,"others":false,"cp":205100,"gs":3050},
{"id":90000003,"name":"Party 3","job":"Chanter","dps":0,"amount":0,"share":0.0,"hps":0,"heal":0,"me":false,"others":false,"cp":197300,"gs":3013},
{"id":90000004,"name":"Party 4","job":"Cleric","dps":0,"amount":0,"share":0.0,"hps":0,"heal":0,"me":false,"others":false,"cp":208200,"gs":2965},
{"id":90000005,"name":"Party 5","job":"Templar","dps":0,"amount":0,"share":0.0,"hps":0,"heal":0,"me":false,"others":false,"cp":210000,"gs":3032}],"extras":{"ping":14,"odyle":[90,1850]}}"#;

/// Made-up history for screenshots (GC_DEMO=dps,history).
const DEMO_HISTORY: &str = r#"[
{"id":"f3","boss":"Tahabata","start":1794549600000,"duration":312000,"total":48210000,"jobs":["Sorcerer","Gladiator","Cleric"],"train":false},
{"id":"f2","boss":"Brigade General Vasharti","start":1794546000000,"duration":201000,"total":30400000,"jobs":["Sorcerer","Ranger"],"train":false},
{"id":"f1","boss":"Training Scarecrow","start":1794542400000,"duration":60000,"total":2400000,"jobs":["Sorcerer"],"train":true}]"#;

/// Made-up skills for screenshots (GC_DEMO=dps,skills).
const DEMO_SKILLS: &str = r#"[
{"code":14010100,"icon":"ICON_RA_SKILL_001","name":"Spiral Arrow","casts":14,"damage":1104000,"share":32.9,"crit":46.0,"back":0.0,"perfect":10.5,"double":13.2,"parry":0.0},
{"code":14020100,"icon":"ICON_RA_SKILL_002","name":"Snipe","casts":9,"damage":742500,"share":22.1,"crit":51.0,"back":0.0,"perfect":8.2,"double":9.8,"parry":1.6},
{"code":14030100,"icon":"ICON_RA_SKILL_003","name":"Rapid Fire","casts":31,"damage":538800,"share":16.0,"crit":38.0,"back":0.0,"perfect":0.0,"double":0.0,"parry":0.0},
{"code":14040100,"icon":"ICON_RA_SKILL_004","name":"Arrow Storm","casts":4,"damage":401200,"share":11.9,"crit":44.0,"back":0.0,"perfect":5.3,"double":7.4,"parry":2.1},
{"code":14000001,"icon":"basic","name":"Basic attack","casts":88,"damage":264000,"share":7.9,"crit":29.0,"back":0.0,"perfect":0.0,"double":0.0,"parry":0.0},
{"code":14050100,"icon":"ICON_RA_SKILL_005","name":"Gale Arrow","casts":7,"damage":152600,"share":4.5,"crit":40.0,"back":0.0,"perfect":0.0,"double":0.0,"parry":0.0},
{"code":99999999,"icon":"","name":"Unknown skill","casts":6,"damage":58600,"share":1.7,"crit":0.0,"back":0.0,"perfect":0.0,"double":0.0,"parry":0.0}]"#;

#[cfg(test)]
mod tests {
    #[test]
    fn server_names_in_english() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("crates/aion2/data/servers.json");
        let names: serde_json::Value = serde_json::from_str(&super::server_names_of(&path)).unwrap();
        assert_eq!(names["1001"], "Siel");
        assert_eq!(super::server_names_of(std::path::Path::new("/nonexistent")), "{}");
    }

    #[test]
    fn the_demo_and_the_empty_fight_read() {
        for text in [super::DEMO, super::DEMO_PARTY, super::EMPTY] {
            let v: serde_json::Value = serde_json::from_str(text).unwrap();
            assert!(v["rows"].is_array());
        }
        let history: serde_json::Value = serde_json::from_str(super::DEMO_HISTORY).unwrap();
        assert_eq!(history.as_array().map(|a| a.len()), Some(3));
        let skills: serde_json::Value = serde_json::from_str(super::DEMO_SKILLS).unwrap();
        assert_eq!(skills.as_array().map(|a| a.len()), Some(7));
    }
}
