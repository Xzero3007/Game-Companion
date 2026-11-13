//! Clicktrough: what the player owns, for plugins with `events:items`: the
//! inventory, the character storage and the account (server) storage, the
//! items that come in, and what was picked up from the ground.
//!
//! The layouts are as SkeeveAN's Aion-DPS-Meter reads them (MIT,
//! `Aion2Stock.cs`, `Aion2Loot.cs`; the ground drops first seen in
//! StacysView's fork), checked on a capture of 2026-10-31 (Kinah as loot
//! came in, Fresh Raw Meat 1 then 2, a Return Scroll used):
//!
//! ```text
//! 11 56 ...                 at world entry: every container, one record each slot
//! 1B 56 <count u8> ...      a change: one record each slot that changed
//! record: <kind u8> 00 <u32> 00 <u16> 00 <item u32> <quantity u64> <container u8> <slot u8> ...
//!         kind 0 a new slot, 1 changed, 2 gone; gear carries more bytes after
//!         the slot, so a record is found by its item, not by a size
//! 1E 56 01 <monster u32> ... <loot u32 at 33> <item u32 at 37> <count u32 at 41>   a drop on the ground
//! 1F 56 01 <monster u32> <u32> <loot u32 at 9> ...                                 a drop gone from it
//! ```
//!
//! Containers: 1 the inventory (the cube, with the currencies: Kinah is item
//! 930100031, Abyss Points 930100003), 15 the character storage, 2 the
//! account storage, 4 souls, 11 and 17 the worn gear. Moving something
//! between the inventory and a storage sends nothing; a sort resends the
//! whole inventory, so what it has more or less than the changes added up
//! to was taken from (or put into) a storage. The storages are exact at
//! world entry and after a sort.

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::sync::LazyLock;

use parking_lot::Mutex;

pub const INVENTORY: u8 = 1;
pub const ACCOUNT_STORAGE: u8 = 2;
pub const CHARACTER_STORAGE: u8 = 15;
/// The containers a record may name.
const CONTAINERS: [u8; 6] = [1, 2, 4, 11, 15, 17];
/// The containers plugins are told: the three a player keeps things in.
const TOLD: [u8; 3] = [INVENTORY, CHARACTER_STORAGE, ACCOUNT_STORAGE];
/// Abyss Points, an item of the inventory.
pub const ABYSS_POINTS: u32 = 930_100_003;
/// A world entry's frame is 15 KB or more (SkeeveAN); a smaller one of the
/// opcode is something else.
const SNAPSHOT_MIN: usize = 5000;
/// Where a storage's items that a sort says were put away are kept, past
/// the game's slots.
const FIRST_SYNTHETIC_SLOT: u32 = 10_000;
const KEEP_CHANGES: usize = 512;
const KEEP_DROPS: usize = 256;

static KNOWN: LazyLock<HashSet<u32>> = LazyLock::new(|| {
    include_str!("item_ids.txt")
        .lines()
        .filter(|l| !l.starts_with('#'))
        .filter_map(|l| l.trim().parse().ok())
        .collect()
});

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Record {
    /// 0 a new slot, 1 changed, 2 gone.
    pub kind: u8,
    pub container: u8,
    pub slot: u8,
    pub item: u32,
    pub quantity: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    /// World entry: every container.
    Snapshot(Vec<Record>),
    Change(Vec<Record>),
    /// A drop on the ground: loot id, item, count.
    Drop { loot: u32, item: u32, count: u32 },
    /// A drop gone from the ground (picked up by someone, or gone).
    Gone { loot: u32 },
}

/// The records of a body (the bytes after the opcode), by their anchor: a
/// known item (or one whose record has its zero bytes where every record has
/// them), a quantity that fits, a known container and a kind byte of 0 to 2
/// ten bytes before the item.
pub fn records(body: &[u8]) -> Vec<Record> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    let mut i = 10;
    while i + 14 <= body.len() {
        let item = u32::from_le_bytes([body[i], body[i + 1], body[i + 2], body[i + 3]]);
        let container = body[i + 12];
        let kind = body[i - 10];
        let fits = (100_000_000..1_000_000_000).contains(&item)
            && kind <= 2
            && CONTAINERS.contains(&container)
            && body[i + 9..i + 12] == [0, 0, 0]
            && (KNOWN.contains(&item) || (body[i - 9] == 0 && body[i - 4] == 0 && body[i - 1] == 0));
        if !fits {
            i += 1;
            continue;
        }
        let quantity = u64::from_le_bytes(body[i + 4..i + 12].try_into().unwrap());
        let slot = body[i + 13];
        if seen.insert((container, slot)) {
            out.push(Record { kind, container, slot, item, quantity });
        }
        i += 14;
    }
    out
}

/// A frame of items, or None. `packet` starts with its length varint.
pub fn parse(packet: &[u8]) -> Option<Frame> {
    let len = crate::capture::stream_processor::read_varint(packet, 0);
    if len.length <= 0 {
        return None;
    }
    let at = len.length as usize;
    let body = packet.get(at + 2..)?;
    let u32_at = |o: usize| body.get(o..o + 4).map(|b| u32::from_le_bytes(b.try_into().unwrap()));
    match packet.get(at..at + 2)? {
        [0x11, 0x56] if body.len() >= SNAPSHOT_MIN => {
            let records = records(body);
            (!records.is_empty()).then_some(Frame::Snapshot(records))
        }
        [0x1B, 0x56] => {
            let records = records(body);
            (!records.is_empty()).then_some(Frame::Change(records))
        }
        [0x1E, 0x56] if body.len() >= 45 && body[0] == 1 => {
            let (loot, item, count) = (u32_at(33)?, u32_at(37)?, u32_at(41)?);
            ((100_000_000..1_000_000_000).contains(&item) && (1..=1_000_000).contains(&count))
                .then_some(Frame::Drop { loot, item, count })
        }
        [0x1F, 0x56] if body.len() >= 13 && body[0] == 1 => Some(Frame::Gone { loot: u32_at(9)? }),
        _ => None,
    }
}

/// One item's count changing in a container, as one frame left it: the net of
/// its slots, so a stack moved from one slot to another is no change. `delta`
/// is None when the slot's count before is not known (the meter started after
/// the world entry and has not seen the slot yet).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Change {
    pub seq: u64,
    pub at: i64,
    pub container: u8,
    pub item: u32,
    pub delta: Option<i64>,
}

/// An item picked up from the ground (or gone from it while the player's
/// inventory took the same: a plugin matches them by time).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pickup {
    pub seq: u64,
    pub at: i64,
    pub item: u32,
    pub count: u32,
}

#[derive(Default)]
struct Stock {
    /// (container, slot) to (item, quantity).
    slots: BTreeMap<(u8, u32), (u32, u64)>,
    snapshot_at: Option<i64>,
    listed_at: Option<i64>,
    /// Whose the items are: the world entry's frame comes before the record
    /// naming who entered, so it waits for that (`note_self`).
    owner: Option<String>,
    awaiting_owner: bool,
    seq: u64,
    changes: VecDeque<Change>,
    drops: HashMap<u32, (u32, u32)>,
    drop_order: VecDeque<u32>,
    pickups: VecDeque<Pickup>,
    synthetic: u32,
}

static STOCK: LazyLock<Mutex<Stock>> = LazyLock::new(|| Mutex::new(Stock { synthetic: FIRST_SYNTHETIC_SLOT, ..Default::default() }));

impl Stock {
    fn totals(&self, container: u8) -> HashMap<u32, u64> {
        let mut totals = HashMap::new();
        for (&(c, _), &(item, quantity)) in &self.slots {
            if c == container {
                *totals.entry(item).or_default() += quantity;
            }
        }
        totals
    }

    fn take(&mut self, container: u8, item: u32, wanted: u64) -> u64 {
        let mut taken = 0;
        let keys: Vec<(u8, u32)> =
            self.slots.iter().filter(|(k, v)| k.0 == container && v.0 == item).map(|(k, _)| *k).collect();
        for key in keys {
            if taken >= wanted {
                break;
            }
            let have = self.slots[&key].1;
            let here = have.min(wanted - taken);
            taken += here;
            if have - here == 0 {
                self.slots.remove(&key);
            } else {
                self.slots.insert(key, (item, have - here));
            }
        }
        taken
    }

    /// A sort's listing differs from the changes added up by what went to or
    /// came from a storage: more came from the character storage first, then
    /// the account storage; less was put into the character storage.
    fn settle(&mut self, before: &HashMap<u32, u64>, after: &HashMap<u32, u64>) {
        let items: HashSet<u32> = before.keys().chain(after.keys()).copied().collect();
        for item in items {
            let delta = *after.get(&item).unwrap_or(&0) as i64 - *before.get(&item).unwrap_or(&0) as i64;
            if delta > 0 {
                let mut left = delta as u64;
                for container in [CHARACTER_STORAGE, ACCOUNT_STORAGE] {
                    left -= self.take(container, item, left);
                }
            } else if delta < 0 {
                let slot = self.synthetic;
                self.synthetic += 1;
                self.slots.insert((CHARACTER_STORAGE, slot), (item, (-delta) as u64));
            }
        }
    }

    fn push_change(&mut self, change: Change) {
        self.changes.push_back(change);
        while self.changes.len() > KEEP_CHANGES {
            self.changes.pop_front();
        }
    }
}

/// Take in a frame of items at `now` (unix ms). Returns the net change of
/// Abyss Points in the inventory, when known and not zero.
pub fn note(frame: Frame, now: i64) -> Option<i64> {
    let mut s = STOCK.lock();
    match frame {
        Frame::Snapshot(records) => {
            s.slots.clear();
            s.synthetic = FIRST_SYNTHETIC_SLOT;
            for r in records.iter().filter(|r| r.kind != 2 && r.quantity > 0) {
                s.slots.insert((r.container, r.slot as u32), (r.item, r.quantity));
            }
            s.snapshot_at = Some(now);
            s.listed_at = Some(now);
            s.owner = None;
            s.awaiting_owner = true;
            s.seq += 1;
            tracing::info!("Items: world entry, {} slots", s.slots.len());
            None
        }
        Frame::Change(records) => {
            let inventory: Vec<&Record> = records.iter().filter(|r| r.container == INVENTORY).collect();
            // A sort resends the inventory: many records of kind 1 on
            // consecutive slots (eight new items at once are kind 0).
            let listing = inventory.len() >= 8 && inventory.iter().all(|r| r.kind == 1) && {
                let min = inventory.iter().map(|r| r.slot as usize).min().unwrap_or(0);
                let max = inventory.iter().map(|r| r.slot as usize).max().unwrap_or(0);
                max - min + 1 == inventory.len()
            };
            let before_listing = (listing && s.snapshot_at.is_some()).then(|| s.totals(INVENTORY));
            // The net of each item in each container: (container, item) to
            // (delta, every slot's count before was known).
            let mut net: BTreeMap<(u8, u32), (i64, bool)> = BTreeMap::new();
            for r in &records {
                let key = (r.container, r.slot as u32);
                let before = s.slots.get(&key).copied();
                let known = before.is_some() || r.kind == 0 || s.snapshot_at.is_some();
                let after = if r.kind == 2 { 0 } else { r.quantity };
                // The slot may have held another item before: that one is gone.
                if let Some((was_item, was)) = before.filter(|b| b.0 != r.item) {
                    let e = net.entry((r.container, was_item)).or_insert((0, true));
                    e.0 -= was as i64;
                }
                let was = before.filter(|b| b.0 == r.item).map(|b| b.1).unwrap_or(0);
                let e = net.entry((r.container, r.item)).or_insert((0, true));
                e.0 += after as i64 - was as i64;
                e.1 &= known;
                if after == 0 {
                    s.slots.remove(&key);
                } else {
                    s.slots.insert(key, (r.item, after));
                }
            }
            if let Some(before) = before_listing {
                let first = inventory.iter().map(|r| r.slot as u32).min().unwrap_or(0);
                let listed: HashSet<u32> = inventory.iter().map(|r| r.slot as u32).collect();
                let gone: Vec<(u8, u32)> = s
                    .slots
                    .keys()
                    .filter(|k| k.0 == INVENTORY && k.1 >= first && !listed.contains(&k.1))
                    .copied()
                    .collect();
                for k in gone {
                    s.slots.remove(&k);
                }
                let after = s.totals(INVENTORY);
                s.settle(&before, &after);
                s.listed_at = Some(now);
            }
            let mut abyss = None;
            for ((container, item), (delta, known)) in net {
                if delta == 0 && known {
                    continue;
                }
                // A sort's own records are no gain or loss.
                if listing && container == INVENTORY {
                    continue;
                }
                if container == INVENTORY && item == ABYSS_POINTS && known && delta != 0 {
                    abyss = Some(delta);
                }
                s.seq += 1;
                let seq = s.seq;
                s.push_change(Change { seq, at: now, container, item, delta: known.then_some(delta) });
            }
            s.seq += 1;
            abyss
        }
        Frame::Drop { loot, item, count } => {
            if s.drops.insert(loot, (item, count)).is_none() {
                s.drop_order.push_back(loot);
                while s.drop_order.len() > KEEP_DROPS {
                    if let Some(old) = s.drop_order.pop_front() {
                        s.drops.remove(&old);
                    }
                }
            }
            None
        }
        Frame::Gone { loot } => {
            if let Some((item, count)) = s.drops.remove(&loot) {
                s.seq += 1;
                let seq = s.seq;
                s.pickups.push_back(Pickup { seq, at: now, item, count });
                while s.pickups.len() > KEEP_DROPS {
                    s.pickups.pop_front();
                }
            }
            None
        }
    }
}

/// The record naming who the player is: a world entry's items are theirs.
pub fn note_self(name: Option<&str>) {
    let mut s = STOCK.lock();
    let name = name.map(str::trim).filter(|n| !n.is_empty());
    if s.awaiting_owner || s.owner.is_none() {
        if let Some(name) = name {
            s.owner = Some(name.to_string());
            s.awaiting_owner = false;
            s.seq += 1;
        }
    }
}

/// The items as plugins see them, with the changes and pickups after `since`
/// (a sequence number); None when nothing happened since.
pub fn event_since(since: u64) -> Option<(u64, serde_json::Value)> {
    let s = STOCK.lock();
    (s.seq > since).then(|| (s.seq, event_of(&s, since)))
}

/// The items now (a plugin's start): no changes.
pub fn event_now() -> serde_json::Value {
    let s = STOCK.lock();
    event_of(&s, s.seq)
}

fn event_of(s: &Stock, since: u64) -> serde_json::Value {
    let mut containers = serde_json::Map::new();
    for c in TOLD {
        let list: Vec<serde_json::Value> = s
            .slots
            .iter()
            .filter(|(k, _)| k.0 == c)
            .map(|(k, v)| serde_json::json!([k.1, v.0, v.1]))
            .collect();
        containers.insert(c.to_string(), serde_json::Value::Array(list));
    }
    let changes: Vec<serde_json::Value> = s
        .changes
        .iter()
        .filter(|c| c.seq > since)
        .map(|c| serde_json::json!([c.seq, c.at, c.container, c.item, c.delta]))
        .collect();
    let pickups: Vec<serde_json::Value> = s
        .pickups
        .iter()
        .filter(|p| p.seq > since)
        .map(|p| serde_json::json!([p.seq, p.at, p.item, p.count]))
        .collect();
    serde_json::json!({
        "owner": s.owner,
        "snapshotAt": s.snapshot_at,
        "listedAt": s.listed_at,
        "containers": containers,
        "changes": changes,
        "pickups": pickups,
    })
}

/// The tests share the one stock: each holds this while it runs.
#[cfg(test)]
static TEST_LOCK: Mutex<()> = Mutex::new(());

#[cfg(test)]
pub fn reset_for_test() -> parking_lot::MutexGuard<'static, ()> {
    let guard = TEST_LOCK.lock();
    *STOCK.lock() = Stock { synthetic: FIRST_SYNTHETIC_SLOT, ..Default::default() };
    guard
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A record as the game writes it (non-gear: 39 bytes).
    fn record(kind: u8, container: u8, slot: u8, item: u32, quantity: u64) -> Vec<u8> {
        let mut r = vec![kind, 0];
        r.extend_from_slice(&123_456u32.to_le_bytes());
        r.push(0);
        r.extend_from_slice(&86u16.to_le_bytes());
        r.push(0);
        r.extend_from_slice(&item.to_le_bytes());
        r.extend_from_slice(&quantity.to_le_bytes());
        r.push(container);
        r.push(slot);
        r.extend_from_slice(&[0; 13]);
        r.extend_from_slice(&[5, 0]);
        r
    }

    /// A packet: its length varint (the bytes after it, plus 4), opcode, body.
    fn packet(op: [u8; 2], body: &[u8]) -> Vec<u8> {
        let mut p = vec![];
        let mut v = body.len() + 2 + 4;
        while v >= 0x80 {
            p.push((v & 0x7F) as u8 | 0x80);
            v >>= 7;
        }
        p.push(v as u8);
        p.extend_from_slice(&op);
        p.extend_from_slice(body);
        p
    }

    fn change(records: &[Vec<u8>]) -> Vec<u8> {
        let mut body = vec![records.len() as u8];
        for r in records {
            body.extend_from_slice(r);
        }
        body.push(0);
        packet([0x1B, 0x56], &body)
    }

    #[test]
    fn a_change_reads_its_records() {
        let p = change(&[record(1, 1, 0, 930_100_031, 4_033_120)]);
        assert_eq!(
            parse(&p),
            Some(Frame::Change(vec![Record { kind: 1, container: 1, slot: 0, item: 930_100_031, quantity: 4_033_120 }]))
        );
        let two = change(&[record(0, 1, 41, 930_100_001, 9), record(1, 1, 40, 610_530_014, 1)]);
        let Some(Frame::Change(r)) = parse(&two) else { panic!() };
        assert_eq!(r.len(), 2);
        assert_eq!((r[1].item, r[1].slot, r[1].quantity), (610_530_014, 40, 1));
    }

    #[test]
    fn items_add_up_and_move() {
        let _guard = reset_for_test();
        let now = 1_761_900_000_000;
        // No world entry seen: a slot not seen before has no known change.
        note(parse(&change(&[record(1, 1, 17, 610_531_001, 1)])).unwrap(), now);
        let (seq, ev) = event_since(0).unwrap();
        assert_eq!(ev["changes"][0][4], serde_json::Value::Null);
        note(parse(&change(&[record(1, 1, 17, 610_531_001, 2)])).unwrap(), now + 1);
        let (_, ev) = event_since(seq).unwrap();
        assert_eq!(ev["changes"].as_array().unwrap().len(), 1);
        assert_eq!(ev["changes"][0][4], 1);
        assert_eq!(ev["containers"]["1"][0], serde_json::json!([17, 610_531_001, 2]));
        // A stack moved to another slot: no change.
        let (seq, _) = event_since(0).unwrap();
        note(parse(&change(&[record(2, 1, 17, 610_531_001, 0), record(0, 1, 20, 610_531_001, 2)])).unwrap(), now + 2);
        let (_, ev) = event_since(seq).unwrap();
        assert!(ev["changes"].as_array().unwrap().is_empty(), "{ev}");
        assert_eq!(ev["containers"]["1"][0], serde_json::json!([20, 610_531_001, 2]));
    }

    #[test]
    fn a_world_entry_waits_for_its_owner_and_abyss_points_count() {
        let _guard = reset_for_test();
        let now = 1_761_900_000_000;
        let mut body = vec![0u8; 40];
        for (i, r) in [
            record(0, 1, 0, 930_100_031, 4_000_000),
            record(0, 1, 1, ABYSS_POINTS, 1000),
            record(0, 15, 3, 610_530_014, 25),
            record(0, 2, 7, 610_531_001, 40),
        ]
        .iter()
        .enumerate()
        {
            body.extend_from_slice(r);
            body.extend_from_slice(&vec![0x33; 1500 + i]);
        }
        let Some(Frame::Snapshot(r)) = parse(&packet([0x11, 0x56], &body)) else { panic!("no snapshot") };
        assert_eq!(r.len(), 4);
        note(Frame::Snapshot(r), now);
        assert_eq!(event_now()["owner"], serde_json::Value::Null);
        note_self(Some("Tester"));
        let ev = event_now();
        assert_eq!(ev["owner"], "Tester");
        assert_eq!(ev["containers"]["15"][0], serde_json::json!([3, 610_530_014, 25]));
        assert_eq!(ev["containers"]["2"][0], serde_json::json!([7, 610_531_001, 40]));
        // Abyss Points gained: their net.
        assert_eq!(note(parse(&change(&[record(1, 1, 1, ABYSS_POINTS, 1350)])).unwrap(), now + 5), Some(350));
    }

    #[test]
    fn a_sort_settles_with_the_storages() {
        let _guard = reset_for_test();
        let now = 1_761_900_000_000;
        note(
            Frame::Snapshot(vec![
                Record { kind: 0, container: 1, slot: 0, item: 610_530_014, quantity: 5 },
                Record { kind: 0, container: 15, slot: 0, item: 610_531_001, quantity: 10 },
            ]),
            now,
        );
        // Taken 10 meat from storage (nothing sent), then a sort lists 8 slots.
        let mut recs = vec![record(1, 1, 0, 610_530_014, 5), record(1, 1, 1, 610_531_001, 10)];
        for slot in 2..8 {
            recs.push(record(1, 1, slot, 930_100_001 + slot as u32, 1));
        }
        let (seq, _) = event_since(0).unwrap();
        note(parse(&change(&recs)).unwrap(), now + 1);
        let (_, ev) = event_since(seq).unwrap();
        assert!(ev["changes"].as_array().unwrap().is_empty(), "a sort is no gain: {ev}");
        assert!(ev["containers"]["15"].as_array().unwrap().is_empty(), "the meat left the storage: {ev}");
    }

    #[test]
    fn a_drop_picked_up() {
        let _guard = reset_for_test();
        let mut drop = vec![1u8];
        drop.extend_from_slice(&[0; 32]);
        drop.extend_from_slice(&10_644_586u32.to_le_bytes());
        drop.extend_from_slice(&610_531_001u32.to_le_bytes());
        drop.extend_from_slice(&1u32.to_le_bytes());
        drop.extend_from_slice(&[0; 20]);
        let f = parse(&packet([0x1E, 0x56], &drop)).unwrap();
        assert_eq!(f, Frame::Drop { loot: 10_644_586, item: 610_531_001, count: 1 });
        note(f, 1);
        let mut gone = vec![1u8];
        gone.extend_from_slice(&[0; 8]);
        gone.extend_from_slice(&10_644_586u32.to_le_bytes());
        gone.extend_from_slice(&[0; 9]);
        note(parse(&packet([0x1F, 0x56], &gone)).unwrap(), 2);
        let (_, ev) = event_since(0).unwrap();
        assert_eq!(ev["pickups"][0], serde_json::json!([1, 2, 610_531_001, 1]));
    }
}
