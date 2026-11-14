//! Battle History: the boss fights the meter counted, one JSON file each
//! (the meter's `FightRecord`), kept on this computer only. Results, never
//! packets: nothing captured is written down.

use std::path::{Path, PathBuf};

use crate::entity::fight_record::FightRecord;

/// The newest fights kept; older ones go.
pub const KEEP: usize = 200;

/// ~/.local/share/game-companion/aion2/fights (or $XDG_DATA_HOME).
pub fn default_dir() -> PathBuf {
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("game-companion").join("aion2").join("fights")
}

/// A fight's id as a file name: letters, digits, `-` and `_` only.
fn file_of(dir: &Path, id: &str) -> Option<PathBuf> {
    let ok = !id.is_empty() && id.len() <= 128 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    ok.then(|| dir.join(format!("{id}.json")))
}

/// One fight in the list: what the panel shows of it, without the details.
fn list_entry(r: &FightRecord) -> serde_json::Value {
    // Each named player's damage (the Armory puts a character's boss fights
    // beside its build): [[name, damage]], the most first.
    let mut damage: std::collections::HashMap<i32, i64> = std::collections::HashMap::new();
    for s in &r.details.skills {
        *damage.entry(s.actor_id).or_default() += s.dmg as i64;
    }
    let mut players: Vec<(String, i64)> = r
        .actors
        .iter()
        .filter(|a| !a.nickname.is_empty())
        .filter_map(|a| damage.get(&a.actor_id).map(|d| (a.nickname.clone(), *d)))
        .collect();
    players.sort_by(|a, b| b.1.cmp(&a.1));
    serde_json::json!({
        "id": r.id,
        "boss": r.boss_name,
        "start": r.start_time_ms,
        "duration": r.duration_ms,
        "total": r.total_damage,
        "jobs": r.jobs.iter().map(|j| crate::job_name(j)).collect::<Vec<_>>(),
        "train": r.is_train,
        "players": players,
    })
}

/// The list kept beside the fights (`index.json`): {"fights": [entries,
/// newest first], "removed": [ids]}, so listing reads one small file and
/// never every fight with all its skills.
#[derive(Default, serde::Serialize, serde::Deserialize)]
struct Index {
    fights: Vec<serde_json::Value>,
    /// Fights the person removed: a later save of the same (live) fight
    /// does not bring it back.
    removed: Vec<String>,
}

/// One writer at a time (the runner's 30 s save, Reset, remove).
static WRITING: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
}

/// Writes next to the target under a name of its own, then renames.
fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("file");
    let tmp = path.with_file_name(format!(".{name}.{}.{n}.tmp", std::process::id()));
    std::fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        e.to_string()
    })
}

/// The index, rebuilt from the fights when it is missing or unreadable
/// (fights that do not read and left-over temp files go then).
fn read_index(dir: &Path) -> Index {
    if let Ok(text) = std::fs::read(index_path(dir))
        && let Ok(index) = serde_json::from_slice::<Index>(&text)
    {
        return index;
    }
    let mut index = Index::default();
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".tmp") {
            let _ = std::fs::remove_file(&path);
            continue;
        }
        if name == "index.json" || path.extension().is_none_or(|e| e != "json") {
            continue;
        }
        match std::fs::read(&path).ok().and_then(|t| serde_json::from_slice::<FightRecord>(&t).ok()) {
            Some(r) => index.fights.push(list_entry(&r)),
            None => {
                let _ = std::fs::remove_file(&path);
            }
        }
    }
    sort(&mut index.fights);
    index
}

fn sort(fights: &mut [serde_json::Value]) {
    fights.sort_by(|a, b| b["start"].as_i64().cmp(&a["start"].as_i64()));
}

fn write_index(dir: &Path, index: &Index) -> Result<(), String> {
    let text = serde_json::to_vec(index).map_err(|e| e.to_string())?;
    write_atomic(&index_path(dir), &text)
}

/// Saves a fight (again: a fight still going is saved every 30 s) and puts
/// it in the list; beyond `KEEP`, the oldest go.
pub fn save(dir: &Path, record: &FightRecord) -> Result<(), String> {
    let path = file_of(dir, &record.id).ok_or("bad fight id")?;
    let _one = WRITING.lock().unwrap_or_else(|p| p.into_inner());
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let mut index = read_index(dir);
    if index.removed.iter().any(|id| *id == record.id) {
        return Ok(());
    }
    let text = serde_json::to_vec(record).map_err(|e| e.to_string())?;
    write_atomic(&path, &text)?;
    index.fights.retain(|f| f["id"].as_str() != Some(&record.id));
    index.fights.push(list_entry(record));
    sort(&mut index.fights);
    for old in index.fights.split_off(index.fights.len().min(KEEP)) {
        if let Some(path) = old["id"].as_str().and_then(|id| file_of(dir, id)) {
            let _ = std::fs::remove_file(path);
        }
    }
    write_index(dir, &index)
}

/// A saved fight, whole.
pub fn load(dir: &Path, id: &str) -> Option<FightRecord> {
    let text = std::fs::read(file_of(dir, id)?).ok()?;
    serde_json::from_slice(&text).ok()
}

/// Removes a saved fight; it stays away even if it is still the live one.
pub fn remove(dir: &Path, id: &str) -> bool {
    let Some(path) = file_of(dir, id) else { return false };
    let _one = WRITING.lock().unwrap_or_else(|p| p.into_inner());
    let mut index = read_index(dir);
    index.fights.retain(|f| f["id"].as_str() != Some(id));
    if !index.removed.iter().any(|r| r == id) {
        index.removed.push(id.to_string());
        let extra = index.removed.len().saturating_sub(KEEP);
        index.removed.drain(..extra);
    }
    let gone = std::fs::remove_file(path).is_ok();
    let _ = write_index(dir, &index);
    gone
}

/// The saved fights, newest first: JSON [{"id","boss","start","duration",
/// "total","jobs","train","players"}] ("players" [[name, damage]] in fights
/// saved since the Armory came). Reads only the index.
pub fn list(dir: &Path) -> serde_json::Value {
    serde_json::Value::Array(read_index(dir).fights)
}

/// Keeps the newest `keep` fights.
pub fn prune(dir: &Path, keep: usize) {
    let _one = WRITING.lock().unwrap_or_else(|p| p.into_inner());
    let mut index = read_index(dir);
    let old = index.fights.split_off(index.fights.len().min(keep));
    if old.is_empty() {
        return;
    }
    for f in old {
        if let Some(path) = f["id"].as_str().and_then(|id| file_of(dir, id)) {
            let _ = std::fs::remove_file(path);
        }
    }
    let _ = write_index(dir, &index);
}

pub fn summary(record: &FightRecord) -> serde_json::Value {
    use std::collections::HashMap;
    let mut damage: HashMap<i32, i64> = HashMap::new();
    for s in &record.details.skills {
        *damage.entry(s.actor_id).or_default() += s.dmg as i64;
    }
    let mut heal: HashMap<i32, i64> = HashMap::new();
    for s in &record.details.heal_skills {
        *heal.entry(s.actor_id).or_default() += s.dmg as i64;
    }
    let total: i64 = damage.values().sum();
    let seconds = (record.duration_ms as f64 / 1000.0).max(1.0);
    let mut rows: Vec<_> = record
        .actors
        .iter()
        .filter(|a| damage.contains_key(&a.actor_id) || heal.contains_key(&a.actor_id))
        .map(|a| {
            let d = damage.get(&a.actor_id).copied().unwrap_or(0);
            let h = heal.get(&a.actor_id).copied().unwrap_or(0);
            serde_json::json!({
                "id": a.actor_id,
                "name": if a.nickname.is_empty() { format!("[{}]", crate::job_name(&a.job)) } else { a.nickname.clone() },
                "job": crate::job_name(&a.job),
                "dps": (d as f64 / seconds).round() as i64,
                "amount": d,
                "share": if total > 0 { ((d as f64) / (total as f64) * 1000.0).round() / 10.0 } else { 0.0 },
                "hps": (h as f64 / seconds).round() as i64,
                "heal": h,
                "me": false,
                "others": false,
            })
        })
        .collect();
    rows.sort_by(|a, b| b["amount"].as_i64().cmp(&a["amount"].as_i64()));
    serde_json::json!({
        "time": record.duration_ms,
        "target": record.boss_name,
        "boss": !record.is_train,
        "hpMax": 0,
        "hpNow": 0,
        "rows": rows,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(id: &str, start: i64) -> FightRecord {
        serde_json::from_value(serde_json::json!({
            "id": id, "bossName": "Boss", "targetId": 1, "startTimeMs": start,
            "durationMs": 60000, "totalDamage": 300, "jobs": ["Sorcerer"],
            "details": {"targetId": 1, "totalTargetDamage": 300, "battleTime": 60000,
                "skills": [
                    {"actorId": 5, "code": 1, "name": "A", "time": 1, "dmg": 200, "multiHitCount": 0, "multiHitDamage": 0, "crit": 0, "parry": 0, "back": 0, "perfect": 0, "double": 0, "regen": 0},
                    {"actorId": 6, "code": 2, "name": "B", "time": 1, "dmg": 100, "multiHitCount": 0, "multiHitDamage": 0, "crit": 0, "parry": 0, "back": 0, "perfect": 0, "double": 0, "regen": 0}
                ]},
            "actors": [{"actorId": 5, "nickname": "Me", "job": "Sorcerer"}, {"actorId": 6, "nickname": "", "job": "Cleric"}]
        }))
        .unwrap()
    }

    #[test]
    fn fights_are_saved_listed_newest_first_and_pruned() {
        let dir = std::env::temp_dir().join(format!("gc-history-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        for (i, id) in ["a1", "b2", "c3"].iter().enumerate() {
            save(&dir, &record(id, 1000 + i as i64)).unwrap();
        }
        assert!(save(&dir, &record("../x", 1)).is_err());
        let list = list(&dir);
        let ids: Vec<_> = list.as_array().unwrap().iter().map(|f| f["id"].as_str().unwrap().to_string()).collect();
        assert_eq!(ids, ["c3", "b2", "a1"]);
        prune(&dir, 2);
        assert!(load(&dir, "a1").is_none() && load(&dir, "c3").is_some());
        // Removed stays removed, even when the live fight is saved again.
        assert!(remove(&dir, "b2"));
        save(&dir, &record("b2", 1001)).unwrap();
        assert!(load(&dir, "b2").is_none());
        // A lost index is rebuilt from the fights; junk goes.
        std::fs::write(dir.join("junk.json"), "nope").unwrap();
        std::fs::write(dir.join(".x.tmp"), "half").unwrap();
        std::fs::remove_file(dir.join("index.json")).unwrap();
        assert_eq!(super::list(&dir).as_array().unwrap().len(), 1);
        assert!(!dir.join("junk.json").exists() && !dir.join(".x.tmp").exists());
        let s = summary(&load(&dir, "c3").unwrap());
        let rows = s["rows"].as_array().unwrap();
        assert_eq!((rows[0]["name"].as_str(), rows[0]["dps"].as_i64()), (Some("Me"), Some(3)));
        assert_eq!((rows[1]["name"].as_str(), rows[1]["share"].as_f64()), (Some("[Cleric]"), Some(33.3)));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
