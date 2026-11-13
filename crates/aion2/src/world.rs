//! Clicktrough: the world around the player, for plugins with the permission
//! `events:world` (a map, a pet tracker).
//!
//! The game never sends the player's own position on a regular beat: only with
//! some actions (an action pose, an effect the player puts on, a teleport or a
//! loading screen). It does announce every monster, player and object that
//! comes into range (roughly 65 m) with its place, and moves them with the
//! movement frames. So the position plugins get is the last exact report while
//! it is fresh (4 s), else the middle of the entities that moved or appeared
//! around the player in the last seconds, which is about 10 m off in the median.
//!
//! The frame layouts and the estimate follow SkeeveAN's Aion-DPS-Meter (MIT,
//! Copyright (c) 2026 SkeeveTV, https://github.com/SkeeveAN/Aion-DPS-Meter),
//! where they were checked against recordings:
//!
//! - `21 36` zone: counter u32 | zone id u32 | 8 bytes | x f32 | y f32 ...
//! - `41 36` monster appears: entity varint | 2 bytes | flag u8 (1: a
//!   length-prefixed owner name follows) | npc id u32 | 2 bytes | x f32 | y f32
//! - `42 36` monster gone: entity varint | 2 bytes (exactly)
//! - `34 36` object appears (gathering, Hidden Cubes ...): entity varint |
//!   2 bytes | object id u32 | x f32 | y f32 | 4 bytes at least
//! - `35 36` object gone: entity varint
//! - `xx 37` movement of others: entity varint | 1 or 2 bytes | x f32 | y f32
//! - `3C 37` action pose: entity varint | 03 | x f32 | y f32 (the player's
//!   own: an exact report)
//! - `2A 38` / `2B 38` effect on / renewed: target varint | (on: 01) | type |
//!   instance varint | effect, duration, flag (u32 each) | 8 bytes | caster
//!   varint | ... | x, y, z f32 at the end: the caster's place
//! - `23 36` teleport: a flag u8 | 5 bytes | x, y, z f32: where it put the
//!   player (as A2 Tools' Pet Soul Tracker 0.5.0 reads it, GPL-3.0,
//!   https://github.com/taengu/A2Tools-Plugins): exact at once after a
//!   Kibelisk, not only with the next action
//!
//! World units are centimetres.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

/// An exact report stays the player's position this long.
const FIX_TRUST: Duration = Duration::from_secs(4);
/// Entities that moved or appeared within this long count as "around"; with
/// too few that fresh, those of the last 20 s.
const AROUND_FRESH: Duration = Duration::from_secs(5);
const AROUND_OLD: Duration = Duration::from_secs(20);
const AROUND_MIN: usize = 3;
/// After a teleport, what came into range this shortly before it belongs to
/// the new place (its spawns can come just before the frame).
const TELEPORT_KEEP: Duration = Duration::from_secs(3);
/// Plugins hear the world at most this often, and at least this often while
/// there is something to tell.
pub const EMIT_EVERY: Duration = Duration::from_millis(250);
pub const HEARTBEAT: Duration = Duration::from_secs(2);
/// More than this many entities around: the removals were lost; start over.
const MAX_AROUND: usize = 1500;
const MAX_NPCS: usize = 1000;
const MAX_ENV: usize = 3000;
/// An object never reported gone is dropped after this long.
const ENV_STALE: Duration = Duration::from_secs(15 * 60);
/// Clicktrough: walking on from the last exact place. The client sends its
/// movement about 10 times a second while the player moves (encrypted, so
/// only that it moves is known, not where): segments of 29 to 31 bytes on
/// foot, 40 to 43 mounted or flying, two of them together. Smaller ones are
/// its heartbeat (11 bytes, 20 a second) and acknowledgements; an action
/// counted as a step only walks on a little, a step missed would leave the
/// player standing where he was.
const STEP_BYTES: std::ops::RangeInclusive<usize> = 28..=96;
/// Moving while a step came this shortly before.
const STEP_GAP: Duration = Duration::from_millis(400);
/// At most this much of a gap between steps counts as moving time.
const STEP_MOST: Duration = Duration::from_millis(150);
/// The speed between two exact places counts if they are this far apart in
/// time, and is taken at this share (a turn costs less than a straight line).
const SPEED_FROM: Duration = Duration::from_millis(200);
const SPEED_TO: Duration = Duration::from_secs(6);
const SPEED_SHARE: f32 = 0.8;
/// Faster than this (cm/s) between two exact places: not walking or riding.
const SPEED_MOST: f32 = 2000.0;
/// Walked on from the last exact place for at most this much moving time.
const RECKON_MOST: Duration = Duration::from_secs(4);

#[derive(Debug, Clone, Copy, PartialEq)]
struct Fix {
    x: f32,
    y: f32,
    at: Instant,
    how: &'static str,
}

#[derive(Debug, Clone, Copy)]
struct Placed {
    id: u32,
    x: f32,
    y: f32,
    at: Instant,
}

#[derive(Debug, Default)]
pub struct World {
    zone: u32,
    fix: Option<Fix>,
    around: HashMap<i64, (f32, f32, Instant)>,
    npcs: HashMap<i64, Placed>,
    env: HashMap<i64, Placed>,
    changed: bool,
    sent: Option<Instant>,
    /// The speed (x, y per second) between the last two exact places.
    velocity: Option<(f32, f32)>,
    /// The client's last movement step, and the moving time since the fix.
    last_step: Option<Instant>,
    moved: Duration,
}

fn varint(b: &[u8], p: &mut usize) -> Option<i64> {
    let mut value: i64 = 0;
    for i in 0..5 {
        let byte = *b.get(*p)?;
        *p += 1;
        value |= i64::from(byte & 0x7f) << (7 * i);
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

fn u32_at(b: &[u8], p: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(p..p + 4)?.try_into().ok()?))
}

fn f32_at(b: &[u8], p: usize) -> Option<f32> {
    Some(f32::from_le_bytes(b.get(p..p + 4)?.try_into().ok()?))
}

/// x, y at `p` when they are plausible world coordinates.
fn place_at(b: &[u8], p: usize, min: f32, max: f32) -> Option<(f32, f32)> {
    let (x, y) = (f32_at(b, p)?, f32_at(b, p + 4)?);
    let ok = |v: f32| v.is_finite() && v.abs() >= min && v.abs() < max;
    (ok(x) && ok(y)).then_some((x, y))
}

/// Where the position sits after the entity id in a movement frame (`xx 37`),
/// by its first byte; None for the others.
fn movement_offset(first: u8) -> Option<usize> {
    match first {
        0x1a | 0x1b | 0x1c | 0x1e | 0x20 | 0x28 | 0x29 | 0x2a => Some(2),
        0x1f | 0x2f => Some(1),
        _ => None,
    }
}

impl World {
    /// One game frame: its 2-byte type and body. `me` is the local player's
    /// entity id, when known.
    pub fn feed(&mut self, opcode: [u8; 2], body: &[u8], me: Option<i64>, now: Instant) {
        match opcode {
            [0x21, 0x36] => self.zone_frame(body, now),
            [0x23, 0x36] => self.teleport(body, now),
            [0x41, 0x36] => self.npc_spawn(body, now),
            [0x42, 0x36] => self.npc_gone(body),
            [0x34, 0x36] => self.env_spawn(body, now),
            [0x35, 0x36] => self.env_gone(body),
            [0x3c, 0x37] => self.pose(body, me, now),
            [0x2a, 0x38] => self.effect(body, me, false, now),
            [0x2b, 0x38] => self.effect(body, me, true, now),
            [first, 0x37] => {
                if let Some(offset) = movement_offset(first) {
                    self.movement(body, offset, me, now);
                }
            }
            _ => {}
        }
    }

    /// Clicktrough: a segment the game client sent to the server, by its
    /// length. Movement steps tell whether the player is moving.
    pub fn client_sent(&mut self, len: usize, now: Instant) {
        if !STEP_BYTES.contains(&len) {
            return;
        }
        if let Some(last) = self.last_step {
            self.moved += now.saturating_duration_since(last).min(STEP_MOST);
        }
        self.last_step = Some(now);
    }

    /// Whether the player is moving, when the client's steps are heard.
    fn moving(&self, now: Instant) -> Option<bool> {
        self.last_step.map(|last| now.saturating_duration_since(last) <= STEP_GAP)
    }

    /// A new exact place; `walked` when it follows the last one on foot (or
    /// mounted), so the speed between them counts.
    fn set_fix(&mut self, fix: Fix, walked: bool) {
        // The same place again (an effect renewed reports where it was cast):
        // nothing new, and the player may have walked on since.
        if walked && self.fix.is_some_and(|old| old.x == fix.x && old.y == fix.y) {
            return;
        }
        if let (true, Some(old)) = (walked, self.fix) {
            let dt = fix.at.saturating_duration_since(old.at);
            if dt < SPEED_FROM {
                // The same place reported twice: the speed stays.
            } else if dt <= SPEED_TO {
                let secs = dt.as_secs_f32();
                let (vx, vy) = ((fix.x - old.x) / secs, (fix.y - old.y) / secs);
                self.velocity = ((vx * vx + vy * vy).sqrt() <= SPEED_MOST).then_some((vx * SPEED_SHARE, vy * SPEED_SHARE));
            } else {
                self.velocity = None;
            }
        } else {
            self.velocity = None;
        }
        self.fix = Some(fix);
        self.moved = Duration::ZERO;
        self.changed = true;
    }

    fn zone_frame(&mut self, b: &[u8], now: Instant) {
        let Some(zone) = u32_at(b, 4).filter(|z| *z > 0) else { return };
        if zone != self.zone {
            self.zone = zone;
            self.changed = true;
        }
        // Where the frame puts the player (a teleport, a loading screen): an
        // exact place, and what was around belongs to the place he left.
        if let Some((x, y)) = place_at(b, 16, 100.0, 500_000.0) {
            self.set_fix(Fix { x, y, at: now, how: "zone" }, false);
            self.around.clear();
            self.npcs.clear();
            self.env.clear();
            self.changed = true;
        }
    }

    fn teleport(&mut self, b: &[u8], now: Instant) {
        if b.len() < 18 {
            return;
        }
        let Some((x, y)) = place_at(b, 6, 100.0, 500_000.0) else { return };
        if !f32_at(b, 14).is_some_and(|z| z.is_finite() && z.abs() < 50_000.0) {
            return;
        }
        self.set_fix(Fix { x, y, at: now, how: "teleport" }, false);
        // What was around belongs to the place left, but for what came with
        // the teleport.
        let fresh = |at: Instant| now.saturating_duration_since(at) <= TELEPORT_KEEP;
        self.around.retain(|_, (_, _, at)| fresh(*at));
        self.npcs.retain(|_, n| fresh(n.at));
        self.env.retain(|_, e| fresh(e.at));
        self.changed = true;
    }

    fn npc_spawn(&mut self, b: &[u8], now: Instant) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p).filter(|e| *e > 0) else { return };
        // A flag 1: an owner's name (length-prefixed UTF-8) before the npc id.
        if b.get(p + 2) == Some(&1) {
            let Some(&len) = b.get(p + 3) else { return };
            let len = usize::from(len);
            let name = b.get(p + 4..p + 4 + len);
            if len < 2 || name.is_none_or(|n| std::str::from_utf8(n).is_err()) {
                return;
            }
            p += 1 + len;
        }
        p += 3;
        let Some(npc) = u32_at(b, p) else { return };
        let Some((x, y)) = place_at(b, p + 6, 0.0, 1_000_000.0) else { return };
        if self.npcs.len() >= MAX_NPCS {
            self.npcs.clear();
        }
        self.npcs.insert(entity, Placed { id: npc, x, y, at: now });
        self.note_around(entity, x, y, now);
        self.changed = true;
    }

    fn npc_gone(&mut self, b: &[u8]) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p) else { return };
        if b.len() != p + 2 {
            return;
        }
        let gone = self.npcs.remove(&entity).is_some();
        self.around.remove(&entity);
        self.changed |= gone;
    }

    fn env_spawn(&mut self, b: &[u8], now: Instant) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p).filter(|e| *e > 0) else { return };
        if b.len() < p + 18 {
            return;
        }
        let Some(id) = u32_at(b, p + 2) else { return };
        let Some((x, y)) = place_at(b, p + 6, 0.0, 1_000_000.0) else { return };
        if self.env.len() >= MAX_ENV {
            self.env.clear();
        }
        self.env.insert(entity, Placed { id, x, y, at: now });
        self.changed = true;
    }

    fn env_gone(&mut self, b: &[u8]) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p) else { return };
        self.changed |= self.env.remove(&entity).is_some();
    }

    fn pose(&mut self, b: &[u8], me: Option<i64>, now: Instant) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p).filter(|e| *e > 0) else { return };
        if b.get(p) != Some(&3) || b.len() < p + 9 {
            return;
        }
        if Some(entity) == me {
            if let Some((x, y)) = place_at(b, p + 1, 0.0, 1_000_000.0) {
                self.set_fix(Fix { x, y, at: now, how: "pose" }, true);
                self.changed = true;
            }
        } else if let Some((x, y)) = place_at(b, p + 1, 1.0, 200_000.0) {
            // Somebody else's dash or correction.
            self.moved(entity, x, y, now);
        }
    }

    fn effect(&mut self, b: &[u8], me: Option<i64>, renewed: bool, now: Instant) {
        let Some(me) = me else { return };
        let mut p = 0;
        if varint(b, &mut p).filter(|t| (1..=10_000_000).contains(t)).is_none() || p + 2 > b.len() {
            return;
        }
        if !renewed {
            if b[p] != 1 {
                return;
            }
            p += 1;
        }
        p += 1; // type
        if varint(b, &mut p).is_none() || p + 20 > b.len() {
            return;
        }
        let Some(effect) = u32_at(b, p) else { return };
        p += 20;
        let Some(caster) = varint(b, &mut p) else { return };
        if caster != me || !(10..=2_999_999_999).contains(&effect) || b.len() < p + 12 {
            return;
        }
        // The last 12 bytes: the caster's place (x, y, z).
        let end = b.len() - 12;
        let Some((x, y)) = place_at(b, end, 100.0, 500_000.0) else { return };
        if f32_at(b, end + 8).is_some_and(|z| z.is_finite() && z.abs() < 50_000.0) {
            self.set_fix(Fix { x, y, at: now, how: "effect" }, true);
            self.changed = true;
        }
    }

    fn movement(&mut self, b: &[u8], offset: usize, me: Option<i64>, now: Instant) {
        let mut p = 0;
        let Some(entity) = varint(b, &mut p).filter(|e| (1..=10_000_000).contains(e)) else { return };
        if Some(entity) == me {
            return;
        }
        if let Some((x, y)) = place_at(b, p + offset, 1.0, 200_000.0) {
            self.moved(entity, x, y, now);
        }
    }

    fn moved(&mut self, entity: i64, x: f32, y: f32, now: Instant) {
        if let Some(npc) = self.npcs.get_mut(&entity) {
            npc.x = x;
            npc.y = y;
            self.changed = true;
        }
        self.note_around(entity, x, y, now);
    }

    fn note_around(&mut self, entity: i64, x: f32, y: f32, now: Instant) {
        if self.around.len() >= MAX_AROUND {
            self.around.clear();
        }
        self.around.insert(entity, (x, y, now));
    }

    /// The middle of the entities around that moved or appeared within
    /// `within`, and how many; None with fewer than three.
    fn middle(&self, now: Instant, within: Duration) -> Option<(f32, f32, usize)> {
        let (mut sx, mut sy, mut n) = (0f64, 0f64, 0usize);
        for (x, y, at) in self.around.values() {
            if now.saturating_duration_since(*at) <= within {
                sx += f64::from(*x);
                sy += f64::from(*y);
                n += 1;
            }
        }
        (n >= AROUND_MIN).then(|| ((sx / n as f64) as f32, (sy / n as f64) as f32, n))
    }

    /// The best guess of where the player is: (x, y, exact, how, when).
    fn position(&self, now: Instant) -> Option<(f32, f32, bool, &'static str, Instant)> {
        if let Some(fix) = self.fix {
            // Clicktrough: with the client's steps heard, no step since the
            // fix means standing there; with steps and a speed, walked on.
            if self.last_step.is_some() {
                let moved = self.moved.min(RECKON_MOST);
                if moved.is_zero() {
                    return Some((fix.x, fix.y, true, fix.how, fix.at));
                }
                if let Some((vx, vy)) = self.velocity {
                    if self.moved <= RECKON_MOST {
                        let s = moved.as_secs_f32();
                        return Some((fix.x + vx * s, fix.y + vy * s, false, "reckoned", fix.at));
                    }
                }
                // Moved since, with no speed to go on: not there any more.
                return self.around_or(fix, now);
            } else if let (Some((vx, vy)), true) = (self.velocity, now.saturating_duration_since(fix.at) <= FIX_TRUST) {
                let s = now.saturating_duration_since(fix.at).as_secs_f32();
                return Some((fix.x + vx * s, fix.y + vy * s, false, "reckoned", fix.at));
            }
            if now.saturating_duration_since(fix.at) <= FIX_TRUST {
                return Some((fix.x, fix.y, true, fix.how, fix.at));
            }
        }
        match self.fix {
            Some(fix) => self.around_or(fix, now),
            None => self.middle(now, AROUND_FRESH).or_else(|| self.middle(now, AROUND_OLD)).map(|(x, y, _)| (x, y, false, "around", now)),
        }
    }

    /// The middle of what is around, unless further from the last exact
    /// place than the player could have walked since (10 m/s plus 30 m, for
    /// at most 12 s: a group announced far away, not where he is); else that
    /// place, not exact.
    fn around_or(&self, fix: Fix, now: Instant) -> Option<(f32, f32, bool, &'static str, Instant)> {
        if let Some((x, y, _)) = self.middle(now, AROUND_FRESH).or_else(|| self.middle(now, AROUND_OLD)) {
            let secs = now.saturating_duration_since(fix.at).as_secs_f32().min(12.0);
            if ((x - fix.x).powi(2) + (y - fix.y).powi(2)).sqrt() <= 3000.0 + 1000.0 * secs {
                return Some((x, y, false, "around", now));
            }
        }
        Some((fix.x, fix.y, false, fix.how, fix.at))
    }

    /// Whether plugins should hear the world now.
    pub fn due(&self, now: Instant) -> bool {
        let since = self.sent.map(|s| now.saturating_duration_since(s));
        let has = self.fix.is_some() || !self.npcs.is_empty() || !self.env.is_empty();
        match since {
            None => self.changed || has,
            Some(since) => (self.changed && since >= EMIT_EVERY) || (has && since >= HEARTBEAT),
        }
    }

    /// What plugins hear (`a2.on("world")`); times in unix ms.
    pub fn snapshot(&mut self, now: Instant, now_ms: i64) -> Value {
        self.env.retain(|_, e| now.saturating_duration_since(e.at) <= ENV_STALE);
        self.changed = false;
        self.sent = Some(now);
        let ms = |at: Instant| now_ms - now.saturating_duration_since(at).as_millis() as i64;
        let me = self.position(now).map(|(x, y, exact, how, at)| {
            json!({ "x": x.round(), "y": y.round(), "exact": exact, "from": how, "at": ms(at) })
        });
        let fix = self.fix.map(|f| json!({ "x": f.x.round(), "y": f.y.round(), "from": f.how, "at": ms(f.at) }));
        let list = |m: &HashMap<i64, Placed>| -> Vec<Value> {
            m.iter().map(|(e, p)| json!([e, p.id, p.x.round(), p.y.round()])).collect()
        };
        json!({
            "at": now_ms,
            "zone": (self.zone > 0).then_some(self.zone),
            "me": me,
            "fix": fix,
            "moving": self.moving(now),
            "npcs": list(&self.npcs),
            "objects": list(&self.env),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f(v: f32) -> [u8; 4] {
        v.to_le_bytes()
    }

    fn body(parts: &[&[u8]]) -> Vec<u8> {
        parts.concat()
    }

    #[test]
    fn a_monster_appears_moves_and_goes() {
        let mut w = World::default();
        let t = Instant::now();
        // entity 300 (AC 02), 2 bytes, flag 0, npc 2100481, 00 02, x, y, more
        let spawn = body(&[&[0xac, 0x02, 0x10, 0x20, 0x00], &2_100_481u32.to_le_bytes(), &[0, 2], &f(1000.0), &f(-2000.0), &[0; 8]]);
        w.feed([0x41, 0x36], &spawn, Some(7), t);
        assert_eq!(w.npcs.get(&300).map(|p| (p.id, p.x, p.y)), Some((2_100_481, 1000.0, -2000.0)));
        // 1B 37: entity | 2 bytes | x | y
        let walk = body(&[&[0xac, 0x02, 4, 0], &f(1500.0), &f(-2500.0), &[1]]);
        w.feed([0x1b, 0x37], &walk, Some(7), t);
        assert_eq!(w.npcs.get(&300).map(|p| (p.x, p.y)), Some((1500.0, -2500.0)));
        w.feed([0x42, 0x36], &[0xac, 0x02, 0, 1], Some(7), t);
        assert!(w.npcs.is_empty());
    }

    #[test]
    fn an_owner_name_is_skipped() {
        let mut w = World::default();
        let t = Instant::now();
        let name = b"Psefon";
        // entity | 2 bytes | flag 1 | length | name | npc id | 00 02 | x | y
        let spawn = body(&[&[0x05, 0x10, 0x20, 0x01, name.len() as u8], name, &2_000_123u32.to_le_bytes(), &[0, 2], &f(10.0), &f(20.0)]);
        w.feed([0x41, 0x36], &spawn, None, t);
        assert!(w.npcs.get(&5).is_some_and(|p| p.id == 2_000_123 && p.x == 10.0));
    }

    #[test]
    fn objects_appear_and_go() {
        let mut w = World::default();
        let t = Instant::now();
        let spawn = body(&[&[0x09, 0, 0], &1_200_036u32.to_le_bytes(), &f(5000.0), &f(6000.0), &[0; 8]]);
        w.feed([0x34, 0x36], &spawn, None, t);
        assert_eq!(w.env.get(&9).map(|p| p.id), Some(1_200_036));
        w.feed([0x35, 0x36], &[0x09], None, t);
        assert!(w.env.is_empty());
    }

    #[test]
    fn the_players_own_pose_is_exact_and_trusted_four_seconds() {
        let mut w = World::default();
        let t = Instant::now();
        let pose = body(&[&[0x07, 3], &f(12345.0), &f(-678.0), &f(100.0)]);
        w.feed([0x3c, 0x37], &pose, Some(7), t);
        let (x, y, exact, how, _) = w.position(t + Duration::from_secs(3)).unwrap();
        assert_eq!((x, y, exact, how), (12345.0, -678.0, true, "pose"));
        // Later, with nothing around: the old report, not exact.
        let (_, _, exact, ..) = w.position(t + Duration::from_secs(10)).unwrap();
        assert!(!exact);
    }

    fn pose_at(w: &mut World, x: f32, y: f32, t: Instant) {
        w.feed([0x3c, 0x37], &body(&[&[0x07, 3], &f(x), &f(y), &f(0.0)]), Some(7), t);
    }

    /// The client's movement steps, ten a second, from `from` for `secs`.
    fn steps(w: &mut World, from: Instant, secs: u64) {
        for i in 0..=secs * 10 {
            w.client_sent(31, from + Duration::from_millis(i * 100));
        }
    }

    #[test]
    fn walking_on_from_the_last_two_exact_places() {
        let mut w = World::default();
        let t = Instant::now();
        // 5 m/s east, as two poses a second apart say.
        pose_at(&mut w, 0.0, 0.0, t);
        steps(&mut w, t, 1);
        pose_at(&mut w, 500.0, 0.0, t + Duration::from_secs(1));
        steps(&mut w, t + Duration::from_millis(1100), 2);
        let (x, y, exact, how, _) = w.position(t + Duration::from_millis(3100)).unwrap();
        assert_eq!((exact, how, y), (false, "reckoned", 0.0));
        // 2.1 s of moving at 80 % of 5 m/s: 8.4 m further.
        assert!((x - 1340.0).abs() < 30.0, "{x}");
        assert_eq!(w.moving(t + Duration::from_millis(3200)), Some(true));
        // Stopped: the place stays where the steps ended.
        let later = w.position(t + Duration::from_secs(30)).unwrap();
        assert!((later.0 - x).abs() < 1.0 && !later.2);
        assert_eq!(w.moving(t + Duration::from_secs(30)), Some(false));
    }

    #[test]
    fn standing_since_an_exact_place_keeps_it() {
        let mut w = World::default();
        let t = Instant::now();
        steps(&mut w, t, 1);
        pose_at(&mut w, 100.0, 200.0, t + Duration::from_secs(2));
        let (x, y, exact, ..) = w.position(t + Duration::from_secs(60)).unwrap();
        assert_eq!((x, y, exact), (100.0, 200.0, true), "no step since: still there, a minute on");
    }

    #[test]
    fn walked_too_long_the_middle_of_those_around_again() {
        let mut w = World::default();
        let t = Instant::now();
        pose_at(&mut w, 0.0, 0.0, t);
        pose_at(&mut w, 500.0, 0.0, t + Duration::from_secs(1));
        steps(&mut w, t + Duration::from_millis(1100), 6);
        for (i, (x, y)) in [(2000.0, 100.0), (2400.0, 400.0), (2400.0, -400.0)].into_iter().enumerate() {
            w.feed([0x1a, 0x37], &body(&[&[10 + i as u8, 0, 0], &f(x), &f(y)]), Some(7), t + Duration::from_secs(7));
        }
        let (.., how, _) = w.position(t + Duration::from_millis(7200)).unwrap();
        assert_eq!(how, "around");
    }

    #[test]
    fn mounted_steps_count_and_the_same_place_again_is_nothing_new() {
        let mut w = World::default();
        let t = Instant::now();
        pose_at(&mut w, 0.0, 0.0, t);
        pose_at(&mut w, 1000.0, 0.0, t + Duration::from_secs(1));
        // Mounted: bigger steps.
        for i in 0..=10 {
            w.client_sent(41, t + Duration::from_millis(1100 + i * 100));
        }
        // An effect renewed, with the place it was cast at.
        pose_at(&mut w, 1000.0, 0.0, t + Duration::from_millis(1600));
        let (x, _, exact, how, _) = w.position(t + Duration::from_millis(2100)).unwrap();
        assert_eq!((exact, how), (false, "reckoned"));
        assert!(x > 1700.0, "{x}");
        // The heartbeat is no step.
        let mut still = World::default();
        pose_at(&mut still, 5.0, 5.0, t);
        for i in 0..20 {
            still.client_sent(11, t + Duration::from_millis(i * 50));
        }
        assert!(still.last_step.is_none());
    }

    #[test]
    fn a_teleport_starts_without_a_speed() {
        let mut w = World::default();
        let t = Instant::now();
        pose_at(&mut w, 0.0, 0.0, t);
        pose_at(&mut w, 500.0, 0.0, t + Duration::from_secs(1));
        assert!(w.velocity.is_some());
        let tp = body(&[&[1, 0, 0, 0, 0, 0], &f(90_000.0), &f(90_000.0), &f(10.0)]);
        w.feed([0x23, 0x36], &tp, Some(7), t + Duration::from_secs(2));
        assert!(w.velocity.is_none());
    }

    #[test]
    fn without_a_fresh_report_the_middle_of_those_around() {
        let mut w = World::default();
        let t = Instant::now();
        for (i, (x, y)) in [(1000.0, 1000.0), (3000.0, 1000.0), (2000.0, 4000.0)].into_iter().enumerate() {
            let walk = body(&[&[10 + i as u8, 0, 0], &f(x), &f(y)]);
            w.feed([0x1a, 0x37], &walk, Some(7), t);
        }
        let (x, y, exact, how, _) = w.position(t + Duration::from_secs(1)).unwrap();
        assert_eq!((x.round(), y.round(), exact, how), (2000.0, 2000.0, false, "around"));
        // The player's own movement frames don't count.
        let mut own = World::default();
        for i in 0..3 {
            own.feed([0x1a, 0x37], &body(&[&[7, 0, 0], &f(1000.0 * i as f32 + 500.0), &f(500.0)]), Some(7), t);
        }
        assert!(own.position(t).is_none());
    }

    #[test]
    fn a_guess_far_from_the_last_report_is_not_taken() {
        let mut w = World::default();
        let t = Instant::now();
        w.feed([0x3c, 0x37], &body(&[&[0x07, 3], &f(0.0), &f(0.0), &f(0.0)]), Some(7), t);
        for i in 0..3u8 {
            w.feed([0x1a, 0x37], &body(&[&[20 + i, 0, 0], &f(90_000.0), &f(90_000.0)]), Some(7), t + Duration::from_secs(5));
        }
        let (x, _, exact, ..) = w.position(t + Duration::from_secs(6)).unwrap();
        assert_eq!((x, exact), (0.0, false));
    }

    #[test]
    fn an_effect_of_the_players_ends_with_his_place() {
        let mut w = World::default();
        let t = Instant::now();
        // target 7 | 01 | type | instance 3 | effect 1234560, duration, flag | 8 bytes | caster 7 | 1 byte | x y z
        let on = body(&[&[0x07, 0x01, 0x02, 0x03], &1_234_560u32.to_le_bytes(), &5000u32.to_le_bytes(), &0u32.to_le_bytes(), &[0; 8], &[0x07, 0x00], &f(4321.0), &f(8765.0), &f(120.0)]);
        w.feed([0x2a, 0x38], &on, Some(7), t);
        assert_eq!(w.fix.map(|f| (f.x, f.y, f.how)), Some((4321.0, 8765.0, "effect")));
        // Cast by somebody else: nothing.
        let mut other = World::default();
        let mut theirs = on.clone();
        theirs[24] = 0x08;
        other.feed([0x2a, 0x38], &theirs, Some(7), t);
        assert!(other.fix.is_none());
    }

    #[test]
    fn a_teleport_places_the_player_and_leaves_what_was_around() {
        let mut w = World::default();
        let t = Instant::now();
        // A monster at the old place, then one that comes with the teleport.
        w.feed([0x41, 0x36], &body(&[&[0x05, 0, 0, 0], &2_000_000u32.to_le_bytes(), &[0, 2], &f(10.0), &f(20.0)]), None, t);
        let later = t + Duration::from_secs(30);
        w.feed([0x41, 0x36], &body(&[&[0x06, 0, 0, 0], &2_000_001u32.to_le_bytes(), &[0, 2], &f(90_100.0), &f(-40_100.0)]), None, later);
        let teleport = body(&[&[0, 1, 2, 3, 4, 5], &f(90_000.0), &f(-40_000.0), &f(1200.0)]);
        w.feed([0x23, 0x36], &teleport, Some(7), later + Duration::from_millis(500));
        let snap = w.snapshot(later + Duration::from_secs(1), 1_000);
        assert_eq!(snap["me"]["x"], 90_000.0);
        assert_eq!(snap["me"]["y"], -40_000.0);
        assert_eq!(snap["me"]["exact"], true);
        assert_eq!(snap["me"]["from"], "teleport");
        let npcs = snap["npcs"].as_array().unwrap();
        assert_eq!(npcs.len(), 1, "only the monster that came with it");
        assert_eq!(npcs[0][1], 2_000_001);
        // Nonsense in its place: no teleport.
        let mut other = World::default();
        other.feed([0x23, 0x36], &body(&[&[0; 6], &f(f32::NAN), &f(1.0), &f(1.0)]), Some(7), t);
        assert!(other.snapshot(t, 0)["me"].is_null());
    }

    #[test]
    fn a_zone_frame_names_the_zone_and_places_the_player() {
        let mut w = World::default();
        let t = Instant::now();
        w.feed([0x41, 0x36], &body(&[&[0x05, 0, 0, 0], &2_000_000u32.to_le_bytes(), &[0, 2], &f(10.0), &f(20.0)]), None, t);
        let zone = body(&[&1u32.to_le_bytes(), &1010u32.to_le_bytes(), &[0; 8], &f(-50_000.0), &f(70_000.0), &[0; 12]]);
        w.feed([0x21, 0x36], &zone, Some(7), t);
        assert_eq!(w.zone, 1010);
        assert!(w.npcs.is_empty(), "what was around belongs to the place he left");
        let snap = w.snapshot(t, 1_000_000);
        assert_eq!(snap["zone"], 1010);
        assert_eq!(snap["me"]["x"], -50_000.0);
        assert_eq!(snap["me"]["exact"], true);
    }

    #[test]
    fn heard_at_most_four_times_a_second_and_every_two_seconds_while_there_is_something() {
        let mut w = World::default();
        let t = Instant::now();
        assert!(!w.due(t));
        w.feed([0x34, 0x36], &body(&[&[0x09, 0, 0], &1u32.to_le_bytes(), &f(1.0), &f(2.0), &[0; 8]]), None, t);
        assert!(w.due(t));
        let snap = w.snapshot(t, 5000);
        assert_eq!(snap["objects"][0], json!([9, 1, 1.0, 2.0]));
        w.feed([0x35, 0x36], &[0x09], None, t);
        assert!(!w.due(t + Duration::from_millis(100)));
        assert!(w.due(t + Duration::from_millis(300)));
        w.snapshot(t + Duration::from_millis(300), 5300);
        assert!(!w.due(t + Duration::from_secs(10)), "nothing left to tell");
    }
}
