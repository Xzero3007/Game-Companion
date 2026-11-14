//! Pet Finder: every pet's level (0 to 3) and the souls it holds, as the game
//! tells it, kept per server (a pet collection belongs to every character on
//! a server). Only read, never sent.
//!
//! The frames and their checks are Pet Finder's (Clicktrough plugins,
//! plugins/pet-finder 0.4.5: `logic.js`, `manifest.json`), which follow
//! PetTracker's (0Fox2Give, GPLv3) GameProtocol.cs and CollectionWire.cs, so a
//! frame of the same type that is something else is dropped rather than read
//! as pets:
//!
//! - `00 90` at login: equipped u32 | varint n | n × (pet u32, pet u32 again,
//!   level u32 1..3) | varint m | m × (pet u32, souls u32)
//! - `0D 90` souls picked up: count u8 | count × (pet u32, amount u32 1..75)
//! - `14 90` a level reached: status u16 (0) | pet u32 | level u32 1..3
//!
//! Every pet id must be in the catalogue (`pets.json`).

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Souls a pet needs to go from level N to N + 1.
pub const NEEDED: [u32; 3] = [5, 25, 75];
const MAX_LEVEL: u32 = NEEDED.len() as u32;
/// A soul for a pet below level 3 within this long: it is being farmed.
const FARMING_MS: i64 = 30 * 60 * 1000;

/// One server's collection.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Collection {
    pub levels: BTreeMap<u32, u32>,
    pub souls: BTreeMap<u32, u32>,
    /// When the game last sent the whole list (unix ms); 0: never.
    pub synced: i64,
    /// Pets given a soul below level 3, by when (unix ms).
    pub farmed: BTreeMap<u32, i64>,
}

impl Collection {
    /// A soul for `pet`: counted, the level raised when it is enough.
    fn gain(&mut self, pet: u32, amount: u32, at: i64) {
        let mut level = self.levels.get(&pet).copied().unwrap_or(0);
        if level < MAX_LEVEL {
            self.farmed.retain(|_, t| at - *t < FARMING_MS);
            self.farmed.insert(pet, at);
        }
        let souls = self.souls.entry(pet).or_insert(0);
        *souls += amount;
        while level < MAX_LEVEL && *souls >= NEEDED[level as usize] {
            *souls -= NEEDED[level as usize];
            level += 1;
        }
        if level > 0 {
            self.levels.insert(pet, level);
        }
    }

    /// The game raised a pet's level: its souls start again from 0, unless
    /// the souls picked up had raised it already.
    fn level_up(&mut self, pet: u32, level: u32) {
        if self.levels.get(&pet).copied().unwrap_or(0) >= level {
            return;
        }
        self.levels.insert(pet, level);
        self.souls.insert(pet, 0);
    }
}

/// What one frame says.
#[derive(Debug, Clone, PartialEq)]
pub enum Frame {
    List { levels: BTreeMap<u32, u32>, souls: BTreeMap<u32, u32> },
    Souls(Vec<(u32, u32)>),
    Level { pet: u32, level: u32 },
}

fn u32_at(b: &[u8], p: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(p..p + 4)?.try_into().ok()?))
}

fn varint(b: &[u8], p: &mut usize) -> Option<u32> {
    let mut value: u32 = 0;
    for i in 0..5 {
        let byte = *b.get(*p)?;
        *p += 1;
        value |= u32::from(byte & 0x7f) << (7 * i);
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

/// Reads a frame of type `opcode` (None: not a pet frame, or one that fails
/// the checks).
pub fn read(opcode: [u8; 2], b: &[u8], catalog: &HashSet<u32>) -> Option<Frame> {
    match opcode {
        [0x00, 0x90] => {
            let equipped = u32_at(b, 0)?;
            let mut p = 4;
            let n = varint(b, &mut p)? as usize;
            if n > catalog.len() {
                return None;
            }
            let mut levels = BTreeMap::new();
            for _ in 0..n {
                let (pet, again, level) = (u32_at(b, p)?, u32_at(b, p + 4)?, u32_at(b, p + 8)?);
                p += 12;
                if !catalog.contains(&pet) || again != pet || !(1..=MAX_LEVEL).contains(&level) || levels.insert(pet, level).is_some() {
                    return None;
                }
            }
            if equipped != 0 && !levels.contains_key(&equipped) {
                return None;
            }
            let m = varint(b, &mut p)? as usize;
            if m > catalog.len() {
                return None;
            }
            let mut souls = BTreeMap::new();
            for _ in 0..m {
                let (pet, count) = (u32_at(b, p)?, u32_at(b, p + 4)?);
                p += 8;
                let level = levels.get(&pet).copied().unwrap_or(0);
                let cap = if level == 1 || level == 2 { NEEDED[level as usize] } else { u32::MAX };
                if !catalog.contains(&pet) || count > cap || souls.insert(pet, count).is_some() {
                    return None;
                }
            }
            Some(Frame::List { levels, souls })
        }
        [0x0d, 0x90] => {
            let n = *b.first()? as usize;
            if n == 0 {
                return None;
            }
            let mut out = Vec::with_capacity(n);
            for i in 0..n {
                let (pet, amount) = (u32_at(b, 1 + i * 8)?, u32_at(b, 5 + i * 8)?);
                if !catalog.contains(&pet) || !(1..=75).contains(&amount) || out.iter().any(|(p, _)| *p == pet) {
                    return None;
                }
                out.push((pet, amount));
            }
            Some(Frame::Souls(out))
        }
        [0x14, 0x90] => {
            let status = u16::from_le_bytes(b.get(0..2)?.try_into().ok()?);
            let (pet, level) = (u32_at(b, 2)?, u32_at(b, 6)?);
            (status == 0 && catalog.contains(&pet) && (1..=MAX_LEVEL).contains(&level)).then_some(Frame::Level { pet, level })
        }
        _ => None,
    }
}

/// Every server's collection, and whose is shown.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Saved {
    /// By server id ("0": a character with no server yet).
    pub servers: BTreeMap<String, Collection>,
    /// The server last played on.
    pub last: String,
}

#[derive(Debug, Default)]
pub struct Pets {
    catalog: HashSet<u32>,
    saved: Saved,
    path: Option<PathBuf>,
    changed: bool,
    dirty: bool,
}

/// The catalogue from `pets.json` in the module's data.
pub fn catalog(data_dir: &Path) -> HashSet<u32> {
    let text = std::fs::read_to_string(data_dir.join("pets").join("pets.json")).unwrap_or_default();
    let value: Value = serde_json::from_str(&text).unwrap_or_default();
    value["catalog"].as_array().map(|a| a.iter().filter_map(|v| v.as_u64()).map(|v| v as u32).collect()).unwrap_or_default()
}

/// Where the collections are kept.
pub fn default_file() -> PathBuf {
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("game-companion").join("aion2").join("pets.json")
}

/// The last server's collection as kept on disk, for the panel before the
/// game runs.
pub fn load_shown(path: &Path) -> Value {
    Pets::open(HashSet::new(), Some(path.to_path_buf())).snapshot()
}

impl Pets {
    pub fn open(catalog: HashSet<u32>, path: Option<PathBuf>) -> Pets {
        let saved = path
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        Pets { catalog, saved, path, changed: true, dirty: false }
    }

    /// One game frame, while a character of `server` (0: not known) plays.
    pub fn feed(&mut self, opcode: [u8; 2], body: &[u8], server: u32, now_ms: i64) {
        if opcode[1] != 0x90 || self.catalog.is_empty() {
            return;
        }
        let Some(frame) = read(opcode, body, &self.catalog) else { return };
        // A whole list goes to its own server (one with none yet keeps its
        // own, or a new character would wipe the last server's); single souls
        // fall back to the last server, for an app started mid-session.
        let key = match (&frame, server) {
            (_, s) if s > 0 => s.to_string(),
            (Frame::List { .. }, _) => "0".to_string(),
            _ if !self.saved.last.is_empty() => self.saved.last.clone(),
            _ => "0".to_string(),
        };
        let c = self.saved.servers.entry(key.clone()).or_default();
        match frame {
            Frame::List { levels, souls } => {
                c.levels = levels;
                c.souls = souls;
                c.synced = now_ms;
            }
            Frame::Souls(list) => {
                for (pet, amount) in list {
                    c.gain(pet, amount, now_ms);
                }
            }
            Frame::Level { pet, level } => c.level_up(pet, level),
        }
        self.saved.last = key;
        self.changed = true;
        self.dirty = true;
    }

    /// The collection shown: the last server's.
    pub fn snapshot(&self) -> Value {
        let c = self.saved.servers.get(&self.saved.last).cloned().unwrap_or_default();
        let server: Option<u32> = self.saved.last.parse().ok().filter(|s| *s > 0);
        json!({
            "server": server,
            "synced": c.synced,
            "levels": c.levels,
            "souls": c.souls,
            "farmed": c.farmed,
        })
    }

    /// The collection when it changed since last asked; written to disk then.
    pub fn take(&mut self) -> Option<Value> {
        if !self.changed {
            return None;
        }
        self.changed = false;
        self.save();
        Some(self.snapshot())
    }

    fn save(&mut self) {
        if !self.dirty {
            return;
        }
        self.dirty = false;
        let Some(path) = &self.path else { return };
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = path.with_extension("json.tmp");
        if let Ok(text) = serde_json::to_string(&self.saved) {
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(mut n: u32) -> Vec<u8> {
        let mut out = vec![];
        loop {
            let b = (n & 127) as u8;
            n >>= 7;
            out.push(b | if n > 0 { 128 } else { 0 });
            if n == 0 {
                return out;
            }
        }
    }
    fn u(x: u32) -> [u8; 4] {
        x.to_le_bytes()
    }
    fn cat() -> HashSet<u32> {
        [1007, 1029, 1086, 1098, 1163].into_iter().collect()
    }
    /// The collection at login, as Pet Finder's test frames build it.
    fn login() -> Vec<u8> {
        let mut b = u(0).to_vec();
        b.extend(v(3));
        for (k, r) in [(1007, 1), (1086, 2), (1163, 1)] {
            b.extend(u(k));
            b.extend(u(k));
            b.extend(u(r));
        }
        b.extend(v(2));
        for (k, s) in [(1007, 24), (1086, 45)] {
            b.extend(u(k));
            b.extend(u(s));
        }
        b
    }

    #[test]
    fn the_list_at_login_reads() {
        let f = read([0x00, 0x90], &login(), &cat()).unwrap();
        let Frame::List { levels, souls } = f else { panic!() };
        assert_eq!(levels[&1086], 2);
        assert_eq!(souls[&1007], 24);
        assert_eq!(read([0x00, 0x90], &hex(b"0102030405060708090A0B0C"), &cat()), None);
    }

    fn hex(s: &[u8]) -> Vec<u8> {
        s.chunks(2).map(|c| u8::from_str_radix(std::str::from_utf8(c).unwrap(), 16).unwrap()).collect()
    }

    #[test]
    fn souls_count_and_raise_the_level() {
        let mut pets = Pets::open(cat(), None);
        pets.feed([0x00, 0x90], &login(), 7, 1000);
        // 1007 at level 1 with 24 souls: one more is 25, level 2 with 0.
        let mut b = vec![1];
        b.extend(u(1007));
        b.extend(u(1));
        pets.feed([0x0d, 0x90], &b, 7, 2000);
        let s = pets.take().unwrap();
        assert_eq!(s["levels"]["1007"], 2);
        assert_eq!(s["souls"]["1007"], 0);
        assert_eq!(s["farmed"]["1007"], 2000);
        assert_eq!(s["server"], 7);
        // The game's own level-up after it changes nothing.
        let mut r = vec![0u8; 23];
        r[2..6].copy_from_slice(&u(1007));
        r[6..10].copy_from_slice(&u(2));
        pets.feed([0x14, 0x90], &r, 7, 3000);
        assert_eq!(pets.take().unwrap()["souls"]["1007"], 0);
        // Two pets in one frame.
        let mut b = vec![2];
        for p in [1029, 1098] {
            b.extend(u(p));
            b.extend(u(1));
        }
        pets.feed([0x0d, 0x90], &b, 0, 4000);
        assert_eq!(pets.take().unwrap()["souls"]["1098"], 1);
        // A status other than 0 is no level reached.
        let mut r = vec![0u8; 23];
        r[0] = 1;
        r[2..6].copy_from_slice(&u(1163));
        r[6..10].copy_from_slice(&u(3));
        pets.feed([0x14, 0x90], &r, 7, 5000);
        assert!(pets.take().is_none());
    }

    #[test]
    fn a_new_character_without_a_server_keeps_the_last_list() {
        let mut pets = Pets::open(cat(), None);
        pets.feed([0x00, 0x90], &login(), 7, 1000);
        let mut empty = u(0).to_vec();
        empty.extend([0, 0]);
        pets.feed([0x00, 0x90], &empty, 0, 2000);
        assert_eq!(pets.saved.servers["7"].levels.len(), 3);
        assert!(pets.saved.servers["0"].levels.is_empty());
    }

    #[test]
    fn kept_on_disk() {
        let dir = std::env::temp_dir().join(format!("gc-pets-{}", std::process::id()));
        let path = dir.join("pets.json");
        let mut pets = Pets::open(cat(), Some(path.clone()));
        pets.feed([0x00, 0x90], &login(), 7, 1000);
        pets.take();
        assert_eq!(load_shown(&path)["levels"]["1086"], 2);
        let _ = std::fs::remove_dir_all(dir);
    }
}
