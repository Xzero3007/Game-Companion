//! The AION 2 module at work: starts the capture helper, feeds what it
//! captures through the meter's dispatcher and parser, and hands out the
//! fight as the meter's page got it (`DpsData`). Runs only while AION 2
//! runs; everything stops with `stop` (or when dropped).

use std::collections::HashSet;
use std::io::{BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use parking_lot::Mutex;

use crate::capture::combat_port_detector::CombatPortDetector;
use crate::combat::capture_dispatcher::CaptureDispatcher;
use crate::combat::data_storage::DataStorage;
use crate::combat::dps_calculator::DpsCalculator;
use crate::combat::ping_tracker::PingTracker;
use crate::entity::dps_data::DpsData;
use crate::i18n::lookup::{self, NpcLookup, SkillLookup};
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
    calculator: Arc<Mutex<DpsCalculator>>,
    detector: Arc<CombatPortDetector>,
    helper: Arc<Mutex<Option<Child>>>,
    failure: Arc<Mutex<Option<String>>>,
    running: Arc<AtomicBool>,
}

impl Engine {
    /// Loads the game's tables (in `language`) and starts the helper at
    /// `helper` (HELPER unless testing).
    pub fn start(helper: &Path, data_dir: &Path, language: &str) -> Engine {
        let skills = SkillLookup::new();
        let npcs = NpcLookup::new();
        lookup::load_language(&skills, &npcs, data_dir, language);
        let skills = Arc::new(skills);
        let npcs = Arc::new(npcs);
        let storage = Arc::new(DataStorage::new());
        if let Ok(text) = std::fs::read_to_string(data_dir.join("abnormals.json")) {
            storage.set_abnormal_stack_limits(crate::capture::abnormal::stack_limits(&text));
        }
        let ping = Arc::new(PingTracker::new());
        let detector = Arc::new(CombatPortDetector::new());
        let calculator = Arc::new(Mutex::new(DpsCalculator::new(
            storage.clone(),
            skills.clone(),
            npcs.clone(),
            ping.clone(),
        )));
        let mut dispatcher = CaptureDispatcher::new(storage, skills, npcs, detector.clone(), ping);
        dispatcher.set_dot_skill_ids(dot_skill_ids(data_dir));

        let engine = Engine {
            calculator,
            detector,
            helper: Arc::new(Mutex::new(None)),
            failure: Arc::new(Mutex::new(None)),
            running: Arc::new(AtomicBool::new(true)),
        };
        window_detector::set_running(true);
        engine.spawn(helper.to_path_buf(), dispatcher);
        engine
    }

    fn spawn(&self, helper: PathBuf, dispatcher: CaptureDispatcher) {
        let child = Command::new(&helper)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match child {
            Ok(child) => child,
            Err(e) => {
                *self.failure.lock() = Some(format!("the capture helper did not start ({}): {e}", helper.display()));
                return;
            }
        };
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let mut stdin = child.stdin.take();
        *self.helper.lock() = Some(child);

        let (tx, rx) = tokio::sync::mpsc::channel(4096);
        // Helper → parser.
        let running = self.running.clone();
        if let Some(stdout) = stdout {
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
        let failure = self.failure.clone();
        if let Some(stderr) = stderr {
            std::thread::spawn(move || {
                let mut text = String::new();
                let _ = std::io::Read::read_to_string(&mut BufReader::new(stderr), &mut text);
                let text = text.trim();
                if !text.is_empty() {
                    *failure.lock() = Some(text.lines().last().unwrap_or(text).to_string());
                }
            });
        }
        // The parser, on a thread of its own.
        std::thread::spawn(move || {
            let Ok(runtime) = tokio::runtime::Builder::new_current_thread().enable_time().build() else { return };
            runtime.block_on(dispatcher.run(rx));
        });
        // The detector's state → helper, so its filter follows the game.
        let running = self.running.clone();
        let detector = self.detector.clone();
        std::thread::spawn(move || {
            let mut last = None;
            let mut quiet = 0;
            while running.load(Ordering::Relaxed) {
                let state = State {
                    port: detector.locked_port_now(),
                    last_parsed_ms: detector.last_parsed_at_ms(),
                    last_from_port_ms: detector.last_from_port_ms(),
                    game_running: window_detector::find_aion2_window_title().is_some(),
                };
                // On change, else every 5 s (the filter widens on quiet ports).
                quiet += 1;
                if last != Some(state) || quiet >= 5 {
                    quiet = 0;
                    last = Some(state);
                    let Some(pipe) = stdin.as_mut() else { break };
                    if pipe.write_all(state.line().as_bytes()).and_then(|_| pipe.flush()).is_err() {
                        break;
                    }
                }
                std::thread::sleep(Duration::from_secs(1));
            }
        });
    }

    /// The fight now, as the meter's page asked for it every 200 ms.
    pub fn snapshot(&self) -> DpsData {
        self.calculator.lock().get_dps()
    }

    pub fn status(&self) -> Status {
        if let Some(failure) = self.failure.lock().clone() {
            return Status::Failed(failure);
        }
        let mut helper = self.helper.lock();
        if let Some(child) = helper.as_mut()
            && let Ok(Some(code)) = child.try_wait()
        {
            return Status::Failed(format!("the capture helper ended ({code})"));
        }
        match self.detector.current_port() {
            Some(port) => Status::Reading(port),
            None => Status::Searching,
        }
    }

    /// A new fight: what is counted goes.
    pub fn reset(&self) {
        self.calculator.lock().restart_target_selection(true);
    }

    pub fn stop(&self) {
        if !self.running.swap(false, Ordering::SeqCst) {
            return;
        }
        window_detector::set_running(false);
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

/// The fight as the panel shows it: rows by damage, the fight's time (ms)
/// and its target.
pub fn summary(data: &DpsData) -> serde_json::Value {
    let mut rows: Vec<_> = data
        .map
        .iter()
        .filter(|(_, p)| p.amount > 0.0 || p.heal_amount > 0.0)
        .map(|(id, p)| {
            let me = data.local_player_id == Some(*id as i64);
            let name = if !p.nickname.is_empty() {
                p.nickname.clone()
            } else if p.is_others {
                "Others".to_string()
            } else {
                format!("[{}]", p.job)
            };
            serde_json::json!({
                "id": id,
                "name": name,
                "job": p.job,
                "dps": p.dps.round() as i64,
                "amount": p.amount.round() as i64,
                "share": (p.damage_contribution * 10.0).round() / 10.0,
                "hps": p.hps.round() as i64,
                "heal": p.heal_amount.round() as i64,
                "me": me,
                "others": p.is_others,
            })
        })
        .collect();
    rows.sort_by(|a, b| b["amount"].as_i64().cmp(&a["amount"].as_i64()));
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
    fn a_missing_helper_says_so_and_the_tables_load() {
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("data");
        let engine = Engine::start(Path::new("/nonexistent/helper"), &data, "en");
        assert!(matches!(engine.status(), Status::Failed(ref why) if why.contains("did not start")));
        assert!(!dot_skill_ids(&data).is_empty());
        assert!(engine.snapshot().map.is_empty());
        engine.stop();
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
}
