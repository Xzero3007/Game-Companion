//! The old Clicktrough meter's LOOT data, read once to take it over (MN,
//! 2026-11-13: "kannst du bitte von der anderen app die daten übernehmen"),
//! and its Armory history for the Armory (MN, 2026-11-14).
//! Only reads local files: the meter kept each plugin's storage as one JSON
//! file per key in `$XDG_DATA_HOME/com.a2tools.dps-meter/plugin-data/<plugin>/`.
//! Nothing is written there and nothing leaves the computer.

use serde_json::{Map, Value};
use std::path::{Path, PathBuf};

/// The meter's plugins whose data LOOT takes over.
const PLUGINS: [&str; 3] = ["inventory", "closet", "shugo-cards"];
/// The meter's Armory plugin, whose readings and history the Armory takes over.
const ARMORY: [&str; 1] = ["armory"];
/// A plugin's storage file is at most 1 MB in the meter; a bit of room.
const LARGEST: u64 = 2 << 20;
/// At most this many files a plugin (the Inventory keeps one per farm day).
const MOST: usize = 4000;

/// Where the meter kept its plugins' data, if `$XDG_DATA_HOME` or `$HOME` says.
pub fn meter_dir() -> Option<PathBuf> {
    let env = |k: &str| std::env::var(k).ok().filter(|v| v.starts_with('/'));
    let data = env("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env("HOME").map(|h| Path::new(&h).join(".local/share")))?;
    Some(data.join("com.a2tools.dps-meter").join("plugin-data"))
}

/// A storage key as the meter allowed it: `[A-Za-z0-9_-]{1,64}`.
fn good_key(key: &str) -> bool {
    !key.is_empty() && key.len() <= 64 && key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Every plugin's files under `dir` as JSON `{"inventory": {key: value},
/// "closet": {...}, "shugo-cards": {...}}`; a plugin without files is left
/// out, so `{}` means nothing was found.
pub fn read_from(dir: &Path) -> String {
    read_plugins(dir, &PLUGINS)
}

/// The given plugins' files under `dir`, as `read_from`.
fn read_plugins(dir: &Path, plugins: &[&str]) -> String {
    let mut out = Map::new();
    for &plugin in plugins {
        let Ok(entries) = std::fs::read_dir(dir.join(plugin)) else { continue };
        let mut docs = Map::new();
        for entry in entries.flatten().take(MOST) {
            let path = entry.path();
            let Some(key) = path.file_name().and_then(|n| n.to_str()).and_then(|n| n.strip_suffix(".json")) else { continue };
            if !good_key(key) {
                continue;
            }
            // Plain files only, not links: only what the meter wrote itself.
            let Ok(meta) = std::fs::symlink_metadata(&path) else { continue };
            if !meta.is_file() || meta.len() > LARGEST {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            if let Ok(value) = serde_json::from_str::<Value>(&text) {
                docs.insert(key.to_string(), value);
            }
        }
        if !docs.is_empty() {
            out.insert(plugin.to_string(), Value::Object(docs));
        }
    }
    Value::Object(out).to_string()
}

/// The meter's LOOT data on this computer (see `read_from`), `{}` if none.
pub fn read() -> String {
    meter_dir().map(|d| read_from(&d)).unwrap_or_else(|| "{}".into())
}

/// The meter's Armory data on this computer as `{"armory": {key: value}}`
/// (settings, references, one reading `c-…` and one history `hc-…` per
/// character), `{}` if none.
pub fn read_armory() -> String {
    meter_dir().map(|d| read_plugins(&d, &ARMORY)).unwrap_or_else(|| "{}".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_plugins_files_only() {
        let dir = std::env::temp_dir().join(format!("gc-meter-import-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        for p in ["inventory", "closet", "streams"] {
            std::fs::create_dir_all(dir.join(p)).unwrap();
        }
        std::fs::write(dir.join("inventory/settings.json"), r#"{"a":1}"#).unwrap();
        std::fs::write(dir.join("inventory/c-2004-abc.json"), r#"[1,2]"#).unwrap();
        std::fs::write(dir.join("inventory/broken.json"), "{").unwrap();
        std::fs::write(dir.join("inventory/bad key.json"), "{}").unwrap();
        std::fs::write(dir.join("inventory/notes.txt"), "{}").unwrap();
        std::fs::write(dir.join("closet/closet.json"), r#"{"ids":[[5,1]]}"#).unwrap();
        std::fs::write(dir.join("streams/x.json"), "{}").unwrap();
        let v: Value = serde_json::from_str(&read_from(&dir)).unwrap();
        assert_eq!(v["inventory"]["settings"]["a"], 1);
        assert_eq!(v["inventory"]["c-2004-abc"][1], 2);
        assert!(v["inventory"].get("broken").is_none());
        assert!(v["inventory"].get("bad key").is_none());
        assert_eq!(v["closet"]["closet"]["ids"][0][0], 5);
        assert!(v.get("streams").is_none());
        assert!(v.get("shugo-cards").is_none());
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(read_from(&dir), "{}");
    }

    #[test]
    fn reads_the_armory_alone() {
        let dir = std::env::temp_dir().join(format!("gc-meter-armory-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        for p in ["armory", "closet"] {
            std::fs::create_dir_all(dir.join(p)).unwrap();
        }
        std::fs::write(dir.join("armory/hc-2004-Diabolia.json"), r#"[{"at":1,"cp":5}]"#).unwrap();
        std::fs::write(dir.join("closet/closet.json"), "{}").unwrap();
        let v: Value = serde_json::from_str(&read_plugins(&dir, &ARMORY)).unwrap();
        assert_eq!(v["armory"]["hc-2004-Diabolia"][0]["cp"], 5);
        assert!(v.get("closet").is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
