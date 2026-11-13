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

/// Writes (or overwrites: a fight still running is saved again) a fight.
pub fn save(dir: &Path, record: &FightRecord) -> Result<(), String> {
    let path = file_of(dir, &record.id).ok_or("bad fight id")?;
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let text = serde_json::to_vec(record).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())
}

pub fn load(dir: &Path, id: &str) -> Option<FightRecord> {
    let text = std::fs::read(file_of(dir, id)?).ok()?;
    serde_json::from_slice(&text).ok()
}

pub fn remove(dir: &Path, id: &str) -> bool {
    file_of(dir, id).is_some_and(|p| std::fs::remove_file(p).is_ok())
}

/// Every fight, newest first: [{"id","boss","start","duration","total","jobs","train"}].
pub fn list(dir: &Path) -> serde_json::Value {
    let mut fights = Vec::new();
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "json") {
            continue;
        }
        let Ok(text) = std::fs::read(&path) else { continue };
        let Ok(r) = serde_json::from_slice::<FightRecord>(&text) else { continue };
        fights.push(serde_json::json!({
            "id": r.id,
            "boss": r.boss_name,
            "start": r.start_time_ms,
            "duration": r.duration_ms,
            "total": r.total_damage,
            "jobs": r.jobs,
            "train": r.is_train,
        }));
    }
    fights.sort_by(|a, b| b["start"].as_i64().cmp(&a["start"].as_i64()));
    serde_json::Value::Array(fights)
}

/// Removes the oldest fights beyond `keep` (by their start).
pub fn prune(dir: &Path, keep: usize) {
    let list = list(dir);
    for old in list.as_array().into_iter().flatten().skip(keep) {
        if let Some(id) = old["id"].as_str() {
            remove(dir, id);
        }
    }
}

/// A saved fight as the panel shows a live one (`engine::summary`'s shape).
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
                "name": if a.nickname.is_empty() { format!("[{}]", a.job) } else { a.nickname.clone() },
                "job": a.job,
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
        let s = summary(&load(&dir, "c3").unwrap());
        let rows = s["rows"].as_array().unwrap();
        assert_eq!((rows[0]["name"].as_str(), rows[0]["dps"].as_i64()), (Some("Me"), Some(3)));
        assert_eq!((rows[1]["name"].as_str(), rows[1]["share"].as_f64()), (Some("[Cleric]"), Some(33.3)));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
