//! The AION 2 module at work: starts the capture helper, feeds what it
//! captures through the meter's dispatcher and parser, and hands out the
//! fight as the meter's page got it (`DpsData`). Runs only while AION 2
//! runs; everything stops with `stop` (or when dropped).

use std::collections::{HashMap, HashSet};
use std::io::{BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

use parking_lot::Mutex;

use crate::capture::combat_port_detector::CombatPortDetector;
use crate::combat::capture_dispatcher::CaptureDispatcher;
use crate::combat::data_storage::DataStorage;
use crate::combat::dps_calculator::DpsCalculator;
use crate::combat::ping_tracker::PingTracker;
use crate::entity::dps_data::DpsData;
use crate::i18n::lookup::{self, NpcLookup, SkillLookup};
use crate::history;
use crate::pets::Pets;
use crate::world::World;
use crate::link::{self, State};
use crate::platform::window_detector;

/// Where the package puts the helper.
pub const HELPER: &str = "/usr/lib/game-companion/game-companion-capture";

/// What the module is doing, for the panel.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Waiting for the game's connection.
    Searching,
    /// The game's connection is found (its server port).
    Reading(u16),
    /// The helper could not start or ended: why.
    Failed(String),
}

pub struct Engine {
    /// None until the runner has loaded the game's tables.
    calculator: Arc<Mutex<Option<DpsCalculator>>>,
    detector: Arc<CombatPortDetector>,
    helper: Arc<Mutex<Option<Child>>>,
    failure: Arc<Mutex<Option<String>>>,
    running: Arc<AtomicBool>,
    /// Raised each time fights were written to the history.
    saved: Arc<AtomicU64>,
    history: PathBuf,
    /// The world around the player (zone, place, monsters, objects).
    world: Arc<Mutex<World>>,
    /// Pet Finder: the pet collection per server.
    pets: Arc<Mutex<Pets>>,
    /// What bosses do, for the Boss panel, and who to tell at once.
    boss: Arc<Mutex<crate::boss::Feed>>,
    boss_notify: Arc<Mutex<Option<Notify>>>,
}

/// Told (on the parser's thread) when bosses did something.
pub type Notify = Arc<dyn Fn() + Send + Sync>;

/// How often fights still on the meter are written to the history.
const SAVE_EVERY: Duration = Duration::from_secs(30);

impl Engine {
    /// Starts at once and does the work on a thread of its own: loads the
    /// game's tables (in `language`), starts the helper at `helper` (HELPER
    /// unless testing) and keeps it fed. Fights go to `history`.
    pub fn start(helper: &Path, data_dir: &Path, language: &str, history: &Path) -> Engine {
        let engine = Engine {
            calculator: Arc::new(Mutex::new(None)),
            detector: Arc::new(CombatPortDetector::new()),
            helper: Arc::new(Mutex::new(None)),
            failure: Arc::new(Mutex::new(None)),
            running: Arc::new(AtomicBool::new(true)),
            saved: Arc::new(AtomicU64::new(0)),
            history: history.to_path_buf(),
            world: Arc::new(Mutex::new(World::default())),
            pets: Arc::new(Mutex::new(Pets::open(crate::pets::catalog(data_dir), Some(crate::pets::default_file())))),
            boss: Arc::new(Mutex::new(crate::boss::Feed::new(
                &std::fs::read_to_string(data_dir.join("boss/watch.json")).unwrap_or_default(),
            ))),
            boss_notify: Arc::new(Mutex::new(None)),
        };
        window_detector::set_running(true);
        let runner = Runner {
            helper: helper.to_path_buf(),
            data_dir: data_dir.to_path_buf(),
            language: language.to_string(),
            calculator: engine.calculator.clone(),
            detector: engine.detector.clone(),
            child: engine.helper.clone(),
            failure: engine.failure.clone(),
            running: engine.running.clone(),
            saved: engine.saved.clone(),
            history: engine.history.clone(),
            world: engine.world.clone(),
            pets: engine.pets.clone(),
            boss: engine.boss.clone(),
            boss_notify: engine.boss_notify.clone(),
        };
        // The helper dies with the thread that started it (PR_SET_PDEATHSIG):
        // the runner starts it and lives as long as the engine runs.
        let _ = std::thread::Builder::new().name("aion2-runner".into()).spawn(move || runner.run());
        engine
    }

    /// One player's skills in the fight now, from the fight's targets'
    /// details (the fast snapshot leaves its per-skill lists empty).
    pub fn live_skills(&self, data: &DpsData, actor: i32) -> serde_json::Value {
        let calc = self.calculator.lock();
        let Some(calc) = calc.as_ref() else { return serde_json::json!([]) };
        let mut targets = data.detail_target_ids.clone();
        if targets.is_empty() && data.target_id != 0 {
            targets.push(data.target_id);
        }
        let mut entries = Vec::new();
        for target in targets {
            entries.extend(calc.get_target_details(target, Some(&[actor])).skills);
        }
        if entries.is_empty() {
            return skills(data, actor);
        }
        detail_skills(&entries, actor)
    }

    /// Ping (ms) and Odyle energy, as the meter's bar showed them, and the
    /// player's server: {"ping": ms|null, "odyle": [basic, charged]|null,
    /// "server": the game's number|null}.
    pub fn extras(&self) -> serde_json::Value {
        let calc = self.calculator.lock();
        let Some(calc) = calc.as_ref() else { return serde_json::json!({ "ping": null, "odyle": null, "server": null }) };
        let server = calc.server_id();
        serde_json::json!({
            "ping": calc.ping_ms(),
            "server": (server != 0).then_some(server),
            "odyle": calc.odyle_energy().map(|(basic, charged)| [basic, charged]),
        })
    }

    /// Who plays and what the game said of them, as the meter's
    /// `character` event gave it to plugins (Roster): name, server, class,
    /// level, combat power, gear score, and from the entry list (only once
    /// it is known to be theirs) Odyle energy, content counts, shop limits,
    /// crafts, Kinah today, Abyss Points, the Abyss passages' times and when
    /// the game last said each. With it the Abyss artifacts' holders as the
    /// game last told them (`abyss`, null before). Null before anyone is
    /// known.
    pub fn character(&self) -> serde_json::Value {
        let calc = self.calculator.lock();
        let Some(calc) = calc.as_ref() else { return serde_json::Value::Null };
        character_of(calc.data_storage())
    }

    /// The field bosses of the maps the player opened, when one was opened
    /// since `seq` (`capture::boss_map`): the new count and JSON
    /// [{"map", "seen" ms, "bosses": [{"id", "up", "time" ms}]}], only the
    /// player's own side's maps (header 0). The Schedule's bosses.
    pub fn boss_maps(&self, seq: u64) -> Option<(u64, serde_json::Value)> {
        let calc = self.calculator.lock();
        let (next, maps) = calc.as_ref()?.data_storage().boss_maps_since(seq)?;
        Some((next, boss_maps_json(&maps)))
    }

    /// The fight now, as the meter's page asked for it every 200 ms.
    pub fn snapshot(&self) -> DpsData {
        self.calculator.lock().as_mut().map_or_else(DpsData::new, |c| c.get_dps())
    }

    pub fn status(&self) -> Status {
        if let Some(failure) = self.failure.lock().clone() {
            return Status::Failed(failure);
        }
        let mut helper = self.helper.lock();
        if let Some(child) = helper.as_mut()
            && let Ok(Some(code)) = child.try_wait()
            // Ended quietly (the game is gone): the runner starts it again.
            && !code.success()
        {
            return Status::Failed(format!("the capture helper ended ({code})"));
        }
        match self.detector.current_port() {
            Some(port) => Status::Reading(port),
            None => Status::Searching,
        }
    }

    /// The world around the player, when there is news (at most four times
    /// a second, at least every 2 s while something is around).
    pub fn world(&self) -> Option<serde_json::Value> {
        let now = std::time::Instant::now();
        let mut world = self.world.lock();
        world.due(now).then(|| world.snapshot(now, crate::clock::now_ms()))
    }

    /// The pet collection shown, when it changed (written to disk then).
    pub fn pets(&self) -> Option<serde_json::Value> {
        self.pets.lock().take()
    }

    /// Who to tell at once when bosses did something (none: nobody).
    pub fn on_boss(&self, notify: Option<Notify>) {
        *self.boss_notify.lock() = notify;
    }

    /// What bosses did since the last call (casts, skills, buffs on and off).
    pub fn boss_events(&self) -> Vec<serde_json::Value> {
        self.boss.lock().take()
    }

    /// The monsters fought now (bosses first, at most 6) and the dungeon
    /// you are in (0: none), as Boss Notes heard them (`events:combat`).
    pub fn combat(&self) -> serde_json::Value {
        let calc = self.calculator.lock();
        let Some(calc) = calc.as_ref() else { return serde_json::json!({ "fought": [], "dungeon": 0 }) };
        let (fought, dungeon) = calc.fought_now(crate::clock::now_ms());
        self.boss.lock().set_fought(fought.iter().filter(|f| f.0.boss).map(|f| f.0.entity));
        let fought: Vec<_> = fought
            .iter()
            .map(|(f, name, dungeon)| {
                serde_json::json!({
                    "entity": f.entity, "npc": f.npc, "name": name, "boss": f.boss,
                    "hp": f.hp, "maxHp": f.max_hp, "since": f.first_hit, "dungeon": dungeon,
                })
            })
            .collect();
        serde_json::json!({ "fought": fought, "dungeon": dungeon })
    }

    /// How many times fights were saved (to notice new ones).
    pub fn saved(&self) -> u64 {
        self.saved.load(Ordering::Relaxed)
    }

    /// A new fight: what is counted is saved, then goes.
    pub fn reset(&self) {
        if let Some(c) = self.calculator.lock().as_mut() {
            save_fights(c.snapshot_boss_fights_force(), &self.history, &self.saved);
            c.restart_target_selection(true);
        }
    }

    pub fn stop(&self) {
        if !self.running.swap(false, Ordering::SeqCst) {
            return;
        }
        window_detector::set_running(false);
        crate::capture::frame_tap::set(None);
        crate::platform::on_client_sent(None);
        *self.boss_notify.lock() = None;
        if let Some(c) = self.calculator.lock().as_mut() {
            save_fights(c.snapshot_boss_fights_force(), &self.history, &self.saved);
        }
        if let Some(mut child) = self.helper.lock().take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.stop();
    }
}

fn save_fights(records: Vec<crate::entity::fight_record::FightRecord>, dir: &Path, saved: &AtomicU64) {
    if records.is_empty() {
        return;
    }
    for record in &records {
        let _ = history::save(dir, record);
    }
    history::prune(dir, history::KEEP);
    saved.fetch_add(1, Ordering::Relaxed);
}

/// The engine's work, on its own thread.
struct Runner {
    helper: PathBuf,
    data_dir: PathBuf,
    language: String,
    calculator: Arc<Mutex<Option<DpsCalculator>>>,
    detector: Arc<CombatPortDetector>,
    child: Arc<Mutex<Option<Child>>>,
    failure: Arc<Mutex<Option<String>>>,
    running: Arc<AtomicBool>,
    saved: Arc<AtomicU64>,
    history: PathBuf,
    world: Arc<Mutex<World>>,
    pets: Arc<Mutex<Pets>>,
    boss: Arc<Mutex<crate::boss::Feed>>,
    boss_notify: Arc<Mutex<Option<Notify>>>,
}

impl Runner {
    fn run(self) {
        let skills = SkillLookup::new();
        let npcs = NpcLookup::new();
        lookup::load_language(&skills, &npcs, &self.data_dir, &self.language);
        let skills = Arc::new(skills);
        let npcs = Arc::new(npcs);
        let storage = Arc::new(DataStorage::new());
        if let Ok(text) = std::fs::read_to_string(self.data_dir.join("abnormals.json")) {
            storage.set_abnormal_stack_limits(crate::capture::abnormal::stack_limits(&text));
        }
        let ping = Arc::new(PingTracker::new());
        *self.calculator.lock() = Some(DpsCalculator::new(storage.clone(), skills.clone(), npcs.clone(), ping.clone()));
        let mut dispatcher = CaptureDispatcher::new(storage.clone(), skills, npcs, self.detector.clone(), ping);
        dispatcher.set_dot_skill_ids(dot_skill_ids(&self.data_dir));
        if !self.running.load(Ordering::SeqCst) {
            return;
        }
        // Every frame the parser reads also goes to the world (as the
        // meter's `events:world` for plugins).
        // Checked again just before: a stop during the loading leaves the
        // hooks alone (they are global).
        if self.running.load(Ordering::SeqCst) {
            let world = self.world.clone();
            let pets = self.pets.clone();
            let storage = storage.clone();
            let boss = self.boss.clone();
            let boss_notify = self.boss_notify.clone();
            crate::capture::frame_tap::set(Some(Arc::new(move |packet: &[u8]| {
                let len = crate::capture::stream_processor::read_varint(packet, 0).length;
                if len <= 0 {
                    return;
                }
                let at = len as usize;
                let Some(opcode) = packet.get(at..at + 2) else { return };
                let me = storage.local_player_id();
                world.lock().feed([opcode[0], opcode[1]], &packet[at + 2..], me, std::time::Instant::now());
                // Pet Finder's frames (`xx 90`): whose server it is only then.
                if opcode[1] == 0x90 {
                    let server = u32::from(storage.local_profile().server_id);
                    pets.lock().feed([opcode[0], opcode[1]], &packet[at + 2..], server, crate::clock::now_ms());
                }
                if boss.lock().feed([opcode[0], opcode[1]], &packet[at + 2..], crate::clock::now_ms()) {
                    let notify = boss_notify.lock().clone();
                    if let Some(notify) = notify {
                        notify();
                    }
                }
                // The areas' decoders (Closet, Shugo Cards, gathering).
                crate::decoders::feed([opcode[0], opcode[1]], &packet[at + 2..], crate::clock::now_ms());
            })));
            let world = self.world.clone();
            crate::platform::on_client_sent(Some(Arc::new(move |len| world.lock().client_sent(len, std::time::Instant::now()))));
        }

        let (tx, rx) = tokio::sync::mpsc::channel(4096);
        // The parser, on a thread of its own, for every helper run.
        std::thread::spawn(move || {
            let Ok(runtime) = tokio::runtime::Builder::new_current_thread().enable_time().build() else { return };
            runtime.block_on(dispatcher.run(rx));
        });

        // The helper ends by itself 10 s after AION 2 is gone (exit 0);
        // while the engine still runs (the game started again from its
        // launcher), it starts again.
        let mut last_save = std::time::Instant::now();
        while self.running.load(Ordering::SeqCst) {
            match self.run_helper(&tx, &storage, &mut last_save) {
                Ended::Quietly => std::thread::sleep(Duration::from_secs(2)),
                Ended::Stopped | Ended::Failed => return,
            }
        }
    }

    /// One run of the helper: started, fed with the detector's state, until
    /// it ends or the engine stops.
    fn run_helper(
        &self,
        tx: &tokio::sync::mpsc::Sender<crate::capture::captured_payload::CapturedPayload>,
        storage: &Arc<DataStorage>,
        last_save: &mut std::time::Instant,
    ) -> Ended {

        let child = Command::new(&self.helper)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match child {
            Ok(child) => child,
            Err(e) => {
                *self.failure.lock() = Some(format!("the capture helper did not start ({}): {e}", self.helper.display()));
                return Ended::Failed;
            }
        };
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let mut stdin = child.stdin.take();
        {
            let mut slot = self.child.lock();
            if !self.running.load(Ordering::SeqCst) {
                let _ = child.kill();
                let _ = child.wait();
                return Ended::Stopped;
            }
            *slot = Some(child);
        }

        // Helper → parser.
        if let Some(stdout) = stdout {
            let running = self.running.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let mut input = BufReader::with_capacity(1 << 16, stdout);
                while running.load(Ordering::Relaxed) {
                    match link::read_segment(&mut input) {
                        Ok(Some(segment)) => {
                            if tx.blocking_send(segment).is_err() {
                                break;
                            }
                        }
                        _ => break,
                    }
                }
            });
        }
        // Why the helper ended, if it says.
        if let Some(stderr) = stderr {
            let failure = self.failure.clone();
            std::thread::spawn(move || {
                let mut text = String::new();
                let _ = std::io::Read::read_to_string(&mut BufReader::new(stderr), &mut text);
                let text = text.trim();
                if !text.is_empty() {
                    *failure.lock() = Some(text.lines().last().unwrap_or(text).to_string());
                }
            });
        }
        // The detector's state → helper, so its filter follows the game;
        // fights to the history every 30 s.
        let mut last = None;
        let mut quiet = 0;
        while self.running.load(Ordering::Relaxed) {
            // Ended by itself: quietly (the game is gone), or with a reason.
            let ended = self.child.lock().as_mut().and_then(|c| c.try_wait().ok().flatten());
            if let Some(code) = ended {
                if code.success() && self.failure.lock().is_none() {
                    *self.child.lock() = None;
                    return Ended::Quietly;
                }
                return Ended::Failed;
            }
            let state = State {
                port: self.detector.locked_port_now(),
                last_parsed_ms: self.detector.last_parsed_at_ms(),
                last_from_port_ms: self.detector.last_from_port_ms(),
                game_running: window_detector::find_aion2_window_title().is_some(),
            };
            // On change, else every 5 s (the filter widens on quiet ports).
            quiet += 1;
            if last != Some(state) || quiet >= 5 {
                quiet = 0;
                last = Some(state);
                // A closed pipe: the helper is ending; its exit is seen above.
                if let Some(pipe) = stdin.as_mut()
                    && pipe.write_all(state.line().as_bytes()).and_then(|_| pipe.flush()).is_err()
                {
                    stdin = None;
                }
            }
            if last_save.elapsed() >= SAVE_EVERY {
                *last_save = std::time::Instant::now();
                if storage.damage_generation() > 0 {
                    let records = self.calculator.try_lock().and_then(|mut c| c.as_mut().map(|c| c.snapshot_boss_fights()));
                    if let Some(records) = records {
                        save_fights(records, &self.history, &self.saved);
                    }
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
        Ended::Stopped
    }
}

/// How one run of the helper ended.
enum Ended {
    /// By itself without a reason: AION 2 is gone.
    Quietly,
    /// The engine stopped.
    Stopped,
    /// It could not start, or ended with a reason (shown).
    Failed,
}

/// `Engine::boss_maps`' JSON.
pub fn boss_maps_json(maps: &[crate::capture::boss_map::BossMap]) -> serde_json::Value {
    let maps: Vec<_> = maps
        .iter()
        .filter(|m| m.header == 0)
        .map(|m| {
            let bosses: Vec<_> = m
                .bosses
                .iter()
                .map(|b| serde_json::json!({ "id": b.id, "up": b.up, "time": b.time_ms }))
                .collect();
            serde_json::json!({ "map": m.map_id, "seen": m.seen_ms, "bosses": bosses })
        })
        .collect();
    serde_json::Value::Array(maps)
}

/// `Engine::character` from what the parser keeps (the meter's
/// `plugins::character`, with the class in English).
pub fn character_of(storage: &DataStorage) -> serde_json::Value {
    let p = storage.local_profile();
    if p.name.is_none() {
        return serde_json::Value::Null;
    }
    // Owner, energy, counts, times, shop limits, crafts, Kinah and Abyss
    // Points from one moment: a login's list replaces them all at once.
    let list = storage.entry_list();
    let theirs = matches!((list.owner.as_deref(), p.name.as_deref()), (Some(o), Some(n)) if o.trim() == n.trim());
    let odyle = list
        .odyle_energy
        .filter(|_| theirs)
        .map(|(basic, charged)| serde_json::json!({ "basic": basic, "charged": charged }));
    let content = (theirs && !list.counts.is_empty()).then(|| serde_json::json!(list.counts));
    let shop = (theirs && !list.shop_limits.is_empty()).then(|| serde_json::json!(list.shop_limits));
    let crafts = (theirs && !list.crafts.is_empty()).then(|| serde_json::json!(list.crafts));
    let abyss = storage.abyss_artifacts_since(0).map(|(_, state, seen_ms)| {
        let secs = |ms: i64| (ms > 0).then_some(ms / 1000);
        let wars: Vec<_> = state
            .wars
            .iter()
            .map(|w| serde_json::json!({ "event": w.event_id, "since": secs(w.since_ms), "until": secs(w.until_ms) }))
            .collect();
        let artifacts: Vec<_> = state
            .artifacts
            .iter()
            .map(|a| serde_json::json!({ "id": a.id, "event": a.event_id(), "owner": a.owner.name() }))
            .collect();
        serde_json::json!({ "observedAt": seen_ms / 1000, "wars": wars, "artifacts": artifacts })
    });
    serde_json::json!({
        "name": p.name,
        "serverId": (p.server_id != 0).then_some(p.server_id),
        "level": p.level,
        "class": p.class.map(|c| crate::job_name(c.class_name())),
        "combatPower": p.combat_power,
        "gearScore": p.gear_score,
        "odyleEnergy": odyle,
        "contentCounts": content,
        "shopLimits": shop,
        "crafts": crafts,
        "kinahToday": list.kinah_today.filter(|_| theirs),
        "abyssPoints": list.abyss_points.filter(|_| theirs).map(|(p, l)| [p, l]),
        "contentTimes": Some(list.times).filter(|t| theirs && !t.is_empty()),
        "seenAt": theirs.then(|| serde_json::json!({
            "odyleEnergy": list.seen.odyle_energy,
            "contentCounts": list.seen.counts,
            "shopLimits": list.seen.shop_limits,
            "crafts": list.seen.crafts,
            "kinahToday": list.seen.kinah_today,
            "abyssPoints": list.seen.abyss_points,
        })),
        "abyss": abyss,
    })
}

/// The fight as the panel shows it: rows by damage, the fight's time (ms)
/// and its target.
pub fn summary(data: &DpsData) -> serde_json::Value {
    let mut rows: Vec<_> = data
        .map
        .iter()
        // Party members show as soon as the party forms, damage or not
        // (`DpsCalculator::add_party_rows` gives them their class).
        .filter(|(_, p)| p.amount > 0.0 || p.heal_amount > 0.0 || (!p.nickname.is_empty() && !p.job.is_empty()))
        .map(|(id, p)| {
            let me = data.local_player_id == Some(*id as i64);
            let name = if !p.nickname.is_empty() {
                p.nickname.clone()
            } else if p.is_others {
                "Others".to_string()
            } else {
                format!("[{}]", crate::job_name(&p.job))
            };
            serde_json::json!({
                "id": id,
                "name": name,
                "job": crate::job_name(&p.job),
                "dps": p.dps.round() as i64,
                "amount": p.amount.round() as i64,
                "share": (p.damage_contribution * 10.0).round() / 10.0,
                "hps": p.hps.round() as i64,
                "heal": p.heal_amount.round() as i64,
                "me": me,
                "others": p.is_others,
                "cp": p.combat_power,
                "gs": p.gear_score,
            })
        })
        .collect();
    rows.sort_by(|a, b| {
        b["amount"].as_i64().cmp(&a["amount"].as_i64())
            .then_with(|| b["heal"].as_i64().cmp(&a["heal"].as_i64()))
            .then_with(|| a["name"].as_str().cmp(&b["name"].as_str()))
    });
    serde_json::json!({
        "time": data.battle_time,
        "target": data.target_name,
        "boss": data.target_is_boss,
        "hpMax": data.target_max_hp,
        "hpNow": if data.target_current_hp >= 0 {
            data.target_current_hp
        } else {
            (data.target_max_hp - data.target_total_damage).max(0)
        },
        "rows": rows,
    })
}

/// One player's skills in the fight, most damage first (the SKILLS tab).
pub fn skills(data: &DpsData, actor: i32) -> serde_json::Value {
    let Some(p) = data.map.get(&actor) else { return serde_json::json!([]) };
    let total: f64 = p.analyzed_data.values().map(|s| (s.damage_amount as f64) + (s.dot_damage_amount as f64)).sum();
    let mut list: Vec<_> = p
        .analyzed_data
        .values()
        .filter(|s| s.times > 0 || s.damage_amount > 0 || s.dot_damage_amount > 0)
        .map(|s| {
            let damage = s.damage_amount as i64 + s.dot_damage_amount as i64;
            let hits = s.times.max(1) as f64;
            let rate = |n: i32| ((n as f64) / hits * 1000.0).round() / 10.0;
            serde_json::json!({
                "code": s.skill_code,
                "icon": crate::skill_icon(s.skill_code as i64),
                "name": if s.skill_name.is_empty() { format!("#{}", s.skill_code) } else { s.skill_name.clone() },
                "casts": s.times,
                "damage": damage,
                "share": if total > 0.0 { ((damage as f64) / total * 1000.0).round() / 10.0 } else { 0.0 },
                "crit": rate(s.crit_times),
                "back": rate(s.back_times),
                "perfect": rate(s.perfect_times),
                "double": rate(s.double_times),
                "parry": rate(s.parry_times),
            })
        })
        .collect();
    list.sort_by(|a, b| b["damage"].as_i64().cmp(&a["damage"].as_i64()));
    serde_json::Value::Array(list)
}

/// One player's skills from a fight's details (live or saved), merged by
/// skill, most damage first: the SKILLS tab's rows.
pub fn detail_skills(entries: &[crate::entity::details_context::DetailSkillEntry], actor: i32) -> serde_json::Value {
    #[derive(Default)]
    struct Sum {
        name: String,
        hits: i64,
        damage: i64,
        crit: i64,
        back: i64,
        perfect: i64,
        double: i64,
        parry: i64,
    }
    let mut by_code: HashMap<i32, Sum> = HashMap::new();
    for e in entries.iter().filter(|e| e.actor_id == actor) {
        let s = by_code.entry(e.code).or_default();
        if s.name.is_empty() {
            s.name = e.name.clone();
        }
        s.hits += e.time as i64;
        s.damage += e.dmg as i64;
        s.crit += e.crit as i64;
        s.back += e.back as i64;
        s.perfect += e.perfect as i64;
        s.double += e.double as i64;
        s.parry += e.parry as i64;
    }
    let total: i64 = by_code.values().map(|s| s.damage).sum();
    let mut list: Vec<_> = by_code
        .into_iter()
        .filter(|(_, s)| s.hits > 0 || s.damage > 0)
        .map(|(code, s)| {
            let hits = s.hits.max(1) as f64;
            let rate = |n: i64| ((n as f64) / hits * 1000.0).round() / 10.0;
            serde_json::json!({
                "code": code,
                "icon": crate::skill_icon(code as i64),
                "name": if s.name.is_empty() { format!("#{code}") } else { s.name.clone() },
                "casts": s.hits,
                "damage": s.damage,
                "share": if total > 0 { ((s.damage as f64) / (total as f64) * 1000.0).round() / 10.0 } else { 0.0 },
                "crit": rate(s.crit),
                "back": rate(s.back),
                "perfect": rate(s.perfect),
                "double": rate(s.double),
                "parry": rate(s.parry),
            })
        })
        .collect();
    list.sort_by(|a, b| b["damage"].as_i64().cmp(&a["damage"].as_i64()));
    serde_json::Value::Array(list)
}

/// Skills whose damage comes over time (language-independent).
fn dot_skill_ids(data_dir: &Path) -> HashSet<i32> {
    std::fs::read_to_string(data_dir.join("dot_skill_ids.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<Vec<i32>>(&text).ok())
        .map(|ids| ids.into_iter().collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_character_as_the_meter_gave_it_to_plugins() {
        let storage = DataStorage::new();
        assert!(character_of(&storage).is_null());
        storage.set_local_character_name(Some("Nully".into()));
        storage.note_self_profile("Nully", Some(crate::entity::job_class::JobClass::Elementalist), Some(45));
        storage.note_self_gear_score("Nully", 3100);
        storage.note_self_combat_power("Nully", 41_210);
        let c = character_of(&storage);
        assert_eq!(c["name"], "Nully");
        assert_eq!(c["class"], "Spiritmaster");
        assert_eq!(c["level"], 45);
        assert_eq!(c["gearScore"], 3100);
        assert_eq!(c["combatPower"], 41_210);
        // Nothing of the entry list until it is known to be theirs.
        assert!(c["odyleEnergy"].is_null());
        assert!(c["seenAt"].is_null());
        assert!(c["abyss"].is_null());
    }

    #[test]
    fn a_missing_helper_says_so_and_the_tables_load() {
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("data");
        let history = std::env::temp_dir().join(format!("gc-engine-{}", std::process::id()));
        let engine = Engine::start(Path::new("/nonexistent/helper"), &data, "en", &history);
        let mut waited = 0;
        while !matches!(engine.status(), Status::Failed(_)) && waited < 100 {
            std::thread::sleep(Duration::from_millis(50));
            waited += 1;
        }
        assert!(matches!(engine.status(), Status::Failed(ref why) if why.contains("did not start")));
        assert!(!dot_skill_ids(&data).is_empty());
        assert!(engine.snapshot().map.is_empty());
        engine.stop();
    }

    #[test]
    fn a_helper_that_ends_quietly_starts_again_and_one_that_fails_does_not() {
        use std::os::unix::fs::PermissionsExt;
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("data");
        let dir = std::env::temp_dir().join(format!("gc-engine-restart-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for (name, end) in [("quiet", "exit 0"), ("loud", "echo broken >&2; exit 1")] {
            let script = dir.join(name);
            let runs = dir.join(format!("{name}.runs"));
            std::fs::write(&script, format!("#!/bin/sh\necho run >> {}\n{end}\n", runs.display())).unwrap();
            std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
            let engine = Engine::start(&script, &data, "en", &dir.join("history"));
            std::thread::sleep(Duration::from_secs(8));
            let count = std::fs::read_to_string(&runs).unwrap_or_default().lines().count();
            if name == "quiet" {
                assert!(count >= 2, "started {count} times");
                assert!(!matches!(engine.status(), Status::Failed(_)));
            } else {
                assert_eq!(count, 1);
                assert!(matches!(engine.status(), Status::Failed(ref why) if why == "broken"));
            }
            engine.stop();
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_summary_puts_the_most_damage_first_and_marks_the_player() {
        use crate::entity::personal_data::PersonalData;
        let mut data = DpsData::new();
        let mut a = PersonalData::new(String::new());
        a.job = "Gladiator".into();
        a.amount = 100.0;
        a.dps = 10.4;
        a.damage_contribution = 33.333;
        let mut b = PersonalData::new(String::new());
        b.nickname = "Me".into();
        b.amount = 200.0;
        data.map.insert(1, a);
        data.map.insert(2, b);
        data.map.insert(3, PersonalData::new(String::new()));
        data.local_player_id = Some(2);
        data.target_max_hp = 1000;
        data.target_total_damage = 300;
        let s = summary(&data);
        let rows = s["rows"].as_array().unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!((rows[0]["name"].as_str(), rows[0]["me"].as_bool()), (Some("Me"), Some(true)));
        assert_eq!((rows[1]["name"].as_str(), rows[1]["dps"].as_i64()), (Some("[Gladiator]"), Some(10)));
        assert_eq!(rows[1]["share"].as_f64(), Some(33.3));
        assert_eq!(s["hpNow"].as_i64(), Some(700));
    }

    #[test]
    fn party_members_show_before_they_hit_anything() {
        use crate::entity::personal_data::PersonalData;
        let mut data = DpsData::new();
        let mut me = PersonalData::new("Me".into());
        me.job = "궁성".into();
        me.amount = 500.0;
        let mut b = PersonalData::new("Zed".into());
        b.job = "치유성".into();
        b.combat_power = 205_000;
        b.gear_score = 3050;
        let mut c = PersonalData::new("Amy".into());
        c.job = "Unknown".into();
        data.map.insert(1, me);
        data.map.insert(90_000_002, b);
        data.map.insert(90_000_003, c);
        let rows = summary(&data)["rows"].as_array().unwrap().clone();
        let names: Vec<_> = rows.iter().map(|r| r["name"].as_str().unwrap().to_string()).collect();
        assert_eq!(names, ["Me", "Amy", "Zed"]);
        assert_eq!((rows[2]["job"].as_str(), rows[2]["cp"].as_i64(), rows[2]["gs"].as_i64()), (Some("Cleric"), Some(205_000), Some(3050)));
    }

    #[test]
    fn detail_skills_merge_by_skill_for_one_player() {
        use crate::entity::details_context::DetailSkillEntry;
        let entry = |actor: i32, code: i32, hits: i32, dmg: i32, crit: i32| {
            let mut e: DetailSkillEntry = serde_json::from_value(serde_json::json!({
                "actorId": actor, "code": code, "name": "", "time": hits, "dmg": dmg,
                "multiHitCount": 0, "multiHitDamage": 0, "crit": crit, "parry": 0, "back": 0,
                "perfect": 0, "double": 0, "regen": 0
            }))
            .unwrap_or_else(|e| panic!("{e}"));
            e.name = if code == 1 { "Strike".into() } else { String::new() };
            e
        };
        // Two targets' entries of the same skill add up; another player's stay out.
        let list = detail_skills(&[entry(5, 1, 4, 100, 2), entry(5, 1, 4, 100, 0), entry(5, 2, 1, 600, 1), entry(6, 1, 9, 900, 0)], 5);
        let list = list.as_array().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!((list[0]["name"].as_str(), list[0]["damage"].as_i64(), list[0]["share"].as_f64()), (Some("#2"), Some(600), Some(75.0)));
        assert_eq!((list[1]["casts"].as_i64(), list[1]["crit"].as_f64()), (Some(8), Some(25.0)));
        assert_eq!(crate::job_name("궁성"), "Ranger");
        assert_eq!(crate::job_name("Cleric"), "Cleric");
    }

    #[test]
    fn skills_come_by_damage_with_their_rates() {
        use crate::entity::analyzed_skill::AnalyzedSkill;
        use crate::entity::personal_data::PersonalData;
        let mut data = DpsData::new();
        let mut p = PersonalData::new("Me".into());
        let mut a = AnalyzedSkill::new(11, "Strike".into());
        a.times = 4;
        a.damage_amount = 100;
        a.crit_times = 1;
        let mut b = AnalyzedSkill::new(12, String::new());
        b.times = 1;
        b.damage_amount = 250;
        b.dot_damage_amount = 50;
        p.analyzed_data.insert(11, a);
        p.analyzed_data.insert(12, b);
        data.map.insert(7, p);
        let list = skills(&data, 7);
        let list = list.as_array().unwrap();
        assert_eq!(list[0]["name"].as_str(), Some("#12"));
        assert_eq!(list[0]["damage"].as_i64(), Some(300));
        assert_eq!(list[1]["crit"].as_f64(), Some(25.0));
        assert_eq!(list[0]["share"].as_f64(), Some(75.0));
        assert!(skills(&data, 8).as_array().unwrap().is_empty());
    }
}
