//! Game Companion: what bosses do, for the Boss panel (Boss Notes and Boss
//! Callouts in one). The frames are read as the Clicktrough Boss Notes
//! plugin and A2 Tools' Enhanced Boss Telegraph (GPL-3.0,
//! https://github.com/taengu/A2Tools-Plugins) read them:
//!
//! - `09 38` a cast bar starts: caster varint | 1 byte | skill u32
//! - `02 38` a skill goes off: caster varint | 1 byte | skill u32
//! - `03 38` a skill's later hits: caster varint | source varint | skill u32
//! - `2A 38` a buff lands: entity varint | 1 byte | flags u8 | instance
//!   varint | abnormal u32 | length u32 (ms) ...
//! - `2C 38` a buff ends: entity varint | count u8 | kind u8 | instance varint
//!
//! They come for every entity, players too. Only these are passed on: a
//! cast or skill the boss data names (its caster is then remembered for
//! half an hour), anything the bosses being fought do, a buff the boss data
//! names, and buffs on and off a remembered or fought entity. Nothing about
//! players is kept.

use std::collections::{HashMap, HashSet};

use serde_json::{json, Value};

use crate::capture::stream_processor::read_varint;

/// A caster of a boss's skill is remembered this long.
const BIND_MS: i64 = 30 * 60 * 1000;
/// Events waiting for the panel: at most this many (older ones go).
const MAX_WAITING: usize = 200;

#[derive(Default)]
pub struct Feed {
    /// Skills and buffs the boss data names (`boss/watch.json`).
    skills: HashSet<u32>,
    buffs: HashSet<u32>,
    /// Entities that cast a boss's skill: when last.
    bound: HashMap<i32, i64>,
    /// The bosses being fought now (the meter's list).
    fought: HashSet<i32>,
    /// Buff instances passed on, so their end is too.
    instances: HashSet<(i32, i32)>,
    out: Vec<Value>,
}

impl Feed {
    /// The skill and buff ids to listen for, from `watch.json`
    /// (`{"skills": [...], "buffs": [...]}`).
    pub fn new(watch: &str) -> Feed {
        let v: Value = serde_json::from_str(watch).unwrap_or(Value::Null);
        let ids = |k: &str| -> HashSet<u32> {
            v[k].as_array().map(|a| a.iter().filter_map(|x| x.as_u64()).map(|x| x as u32).collect()).unwrap_or_default()
        };
        Feed { skills: ids("skills"), buffs: ids("buffs"), ..Feed::default() }
    }

    /// The bosses being fought now.
    pub fn set_fought(&mut self, entities: impl IntoIterator<Item = i32>) {
        self.fought = entities.into_iter().collect();
    }

    fn known(&self, entity: i32, now_ms: i64) -> bool {
        self.fought.contains(&entity) || self.bound.get(&entity).is_some_and(|&at| now_ms - at < BIND_MS)
    }

    fn push(&mut self, ev: Value) {
        if self.out.len() >= MAX_WAITING {
            self.out.remove(0);
        }
        self.out.push(ev);
    }

    /// One frame (its opcode and what follows it); true when something was
    /// passed on.
    pub fn feed(&mut self, opcode: [u8; 2], body: &[u8], now_ms: i64) -> bool {
        match opcode {
            [0x09, 0x38] | [0x02, 0x38] => {
                let Some((caster, skill)) = cast(body) else { return false };
                let theirs = self.skills.contains(&skill);
                if theirs {
                    self.bound.insert(caster, now_ms);
                    if self.bound.len() > 300 {
                        self.bound.retain(|_, &mut at| now_ms - at < BIND_MS);
                    }
                }
                if !theirs && !self.fought.contains(&caster) {
                    return false;
                }
                let t = if opcode[0] == 0x09 { "cast" } else { "use" };
                self.push(json!({ "t": t, "caster": caster, "skill": skill, "at": now_ms }));
                true
            }
            [0x03, 0x38] => {
                let Some((caster, skill)) = later_hit(body) else { return false };
                if !self.skills.contains(&skill) || !self.known(caster, now_ms) {
                    return false;
                }
                self.push(json!({ "t": "wave", "caster": caster, "skill": skill, "at": now_ms }));
                true
            }
            [0x2a, 0x38] => {
                let Some((entity, instance, abnormal, length)) = buff_on(body) else { return false };
                if !self.buffs.contains(&abnormal) && !self.known(entity, now_ms) {
                    return false;
                }
                self.instances.insert((entity, instance));
                if self.instances.len() > 2000 {
                    self.instances.clear();
                }
                self.push(json!({ "t": "added", "entity": entity, "instance": instance, "abnormal": abnormal, "length": length, "at": now_ms }));
                true
            }
            [0x2c, 0x38] => {
                let Some((entity, instance)) = buff_off(body) else { return false };
                if !self.instances.remove(&(entity, instance)) {
                    return false;
                }
                self.push(json!({ "t": "removed", "entity": entity, "instance": instance, "at": now_ms }));
                true
            }
            _ => false,
        }
    }

    /// What was passed on since the last call.
    pub fn take(&mut self) -> Vec<Value> {
        std::mem::take(&mut self.out)
    }
}

fn varint(b: &[u8], at: usize) -> Option<(i32, usize)> {
    let v = read_varint(b, at);
    (v.length > 0).then(|| (v.value, at + v.length as usize))
}

fn u32_at(b: &[u8], at: usize) -> Option<u32> {
    b.get(at..at + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

fn cast(b: &[u8]) -> Option<(i32, u32)> {
    let (caster, at) = varint(b, 0)?;
    Some((caster, u32_at(b, at + 1)?))
}

fn later_hit(b: &[u8]) -> Option<(i32, u32)> {
    let (caster, at) = varint(b, 0)?;
    let (_, at) = varint(b, at)?;
    Some((caster, u32_at(b, at)?))
}

fn buff_on(b: &[u8]) -> Option<(i32, i32, u32, u32)> {
    let (entity, at) = varint(b, 0)?;
    let (instance, at) = varint(b, at + 2)?;
    let abnormal = u32_at(b, at)?;
    let length = u32_at(b, at + 4)?;
    Some((entity, instance, abnormal, length))
}

fn buff_off(b: &[u8]) -> Option<(i32, i32)> {
    let (entity, at) = varint(b, 0)?;
    let (instance, _) = varint(b, at + 2)?;
    Some((entity, instance))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed() -> Feed {
        Feed::new(r#"{"skills": [1604670], "buffs": [16046701]}"#)
    }

    #[test]
    fn a_boss_cast_binds_its_caster_and_its_buffs_follow() {
        let mut f = feed();
        // entity 300 (AC 02), a byte, skill 1604670
        let mut cast = vec![0xac, 0x02, 0x00];
        cast.extend(1_604_670u32.to_le_bytes());
        assert!(f.feed([0x09, 0x38], &cast, 1000));
        // a buff no data names, on that entity: passed on (bound)
        let mut on = vec![0xac, 0x02, 0x01, 0x00, 0x05];
        on.extend(999u32.to_le_bytes());
        on.extend(10_000u32.to_le_bytes());
        on.extend([0u8; 4]);
        assert!(f.feed([0x2a, 0x38], &on, 1100));
        // its end
        assert!(f.feed([0x2c, 0x38], &[0xac, 0x02, 0x01, 0x00, 0x05], 2000));
        let got = f.take();
        assert_eq!(got.len(), 3);
        assert_eq!(got[0]["t"], "cast");
        assert_eq!(got[0]["caster"], 300);
        assert_eq!(got[0]["skill"], 1_604_670);
        assert_eq!(got[1]["abnormal"], 999);
        assert_eq!(got[1]["length"], 10_000);
        assert_eq!(got[1]["instance"], 5);
        assert_eq!(got[2]["t"], "removed");
    }

    #[test]
    fn players_are_left_out() {
        let mut f = feed();
        let mut cast = vec![0x07, 0x00];
        cast.extend(12_345u32.to_le_bytes());
        assert!(!f.feed([0x09, 0x38], &cast, 1000));
        let mut on = vec![0x07, 0x00, 0x01, 0x03];
        on.extend(999u32.to_le_bytes());
        on.extend(5_000u32.to_le_bytes());
        assert!(!f.feed([0x2a, 0x38], &on, 1000));
        assert!(!f.feed([0x2c, 0x38], &[0x07, 0x01, 0x00, 0x03], 1000));
        assert!(f.take().is_empty());
    }

    #[test]
    fn a_fought_boss_is_heard_whatever_it_casts() {
        let mut f = feed();
        f.set_fought([7]);
        let mut cast = vec![0x07, 0x00];
        cast.extend(12_345u32.to_le_bytes());
        assert!(f.feed([0x02, 0x38], &cast, 1000));
        assert_eq!(f.take()[0]["t"], "use");
    }

    #[test]
    fn short_frames_do_nothing() {
        let mut f = feed();
        assert!(!f.feed([0x09, 0x38], &[0xac], 0));
        assert!(!f.feed([0x2a, 0x38], &[0x01, 0x00], 0));
    }
}
