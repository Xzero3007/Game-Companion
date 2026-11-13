//! The old meter's plugin decoders (Clicktrough `plugins/decoder.rs`, with
//! patch 0042's `rest`), for the AION 2 module's areas: a named layout of
//! numbers read from the start of a frame's body. Each area's decoders are
//! listed here as the old plugins' manifests had them; what they read waits
//! in a short queue until the app asks (`events_since`).
//!
//! Field types: `u8`, `u16`, `u32`, `u64`, `i32` (little-endian), `varint`,
//! `skip:N`, `list` (a `count` of `u8`, `u16`, `u32` or `varint`, then that
//! many entries of the list's own `fields`, nested two deep) and `rest` (the
//! last top-level field: the rest of the frame, at most 4 KB, as hex). Only
//! reads: nothing is written down or sent.

use std::collections::VecDeque;
use std::sync::LazyLock;

use parking_lot::Mutex;
use serde::Deserialize;
use serde_json::{Map, Value};

const MAX_FIELDS: usize = 32;
const MAX_LIST: u64 = 4096;
const MAX_DEPTH: u8 = 2;
const MAX_REST: usize = 4096;
/// Decoded frames kept for the app.
const KEEP: usize = 256;

/// The decoders, as the old plugins' manifests named them.
/// LOOT (Inventory, Closet, Shugo Cards): the gathering result, the closet
/// at login and each look added, the Black Cloud shop's stock and its
/// opening, the card round.
const SPECS: &str = r#"[
  {"name": "gathered", "opcode": "33 8D", "fields": [
    {"name": "great", "type": "u8"}, {"name": "kind", "type": "u8"}, {"name": "node", "type": "varint"},
    {"name": "item", "type": "u32"}, {"name": "amount", "type": "u32"}, {"name": "bonus", "type": "u32"}]},
  {"name": "closet-list", "opcode": "5B 8D", "fields": [
    {"name": "looks", "type": "list", "count": "varint", "fields": [{"name": "id", "type": "u32"}, {"name": "value", "type": "u32"}]}]},
  {"name": "closet-add", "opcode": "5C 8D", "fields": [
    {"name": "looks", "type": "list", "count": "u8", "fields": [{"name": "id", "type": "u32"}, {"name": "value", "type": "u32"}]}]},
  {"name": "shop", "opcode": "91 56", "fields": [
    {"name": "tab", "type": "u8"}, {"name": "count", "type": "u8"}, {"name": "body", "type": "rest"}]},
  {"name": "shop-open", "opcode": "61 E2", "fields": [{"name": "a", "type": "u16"}]},
  {"name": "round", "opcode": "0A 57", "fields": [{"name": "body", "type": "rest"}]}
]"#;

#[derive(Debug, Clone, Deserialize)]
pub struct DecoderSpec {
    pub name: String,
    pub opcode: String,
    pub fields: Vec<FieldSpec>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FieldSpec {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub count: Option<String>,
    #[serde(default)]
    pub fields: Option<Vec<FieldSpec>>,
}

#[derive(Debug, Clone)]
pub struct Decoder {
    pub name: String,
    pub opcode: [u8; 2],
    fields: Vec<FieldSpec>,
}

impl Decoder {
    pub fn compile(spec: &DecoderSpec) -> Result<Self, String> {
        if spec.name.is_empty()
            || spec.name.len() > 40
            || !spec.name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        {
            return Err(format!("decoder name {:?}: lowercase letters, digits and '-' only", spec.name));
        }
        let bytes: Vec<u8> = spec
            .opcode
            .split_whitespace()
            .map(|b| u8::from_str_radix(b, 16))
            .collect::<Result<_, _>>()
            .map_err(|_| format!("decoder {}: opcode {:?} is not hex bytes", spec.name, spec.opcode))?;
        let opcode: [u8; 2] = bytes.try_into().map_err(|_| format!("decoder {}: opcode must be two bytes", spec.name))?;
        check_fields(&spec.fields, 0).map_err(|e| format!("decoder {}: {e}", spec.name))?;
        if spec.fields.iter().rev().skip(1).any(|f| f.kind == "rest") {
            return Err(format!("decoder {}: \"rest\" must be the last field", spec.name));
        }
        Ok(Self { name: spec.name.clone(), opcode, fields: spec.fields.clone() })
    }

    /// Decode a frame's body (the bytes after its type) into the fields.
    pub fn decode(&self, body: &[u8]) -> Option<Value> {
        let mut pos = 0;
        decode_fields(&self.fields, body, &mut pos).map(Value::Object)
    }
}

fn check_fields(fields: &[FieldSpec], depth: u8) -> Result<(), String> {
    if fields.len() > MAX_FIELDS {
        return Err(format!("more than {MAX_FIELDS} fields"));
    }
    for field in fields {
        let kind = field.kind.as_str();
        let named = field.name.as_deref().is_some_and(|n| !n.is_empty());
        match kind {
            "u8" | "u16" | "u32" | "u64" | "i32" | "varint" => {
                if !named {
                    return Err(format!("a {kind} field needs a name"));
                }
            }
            "rest" => {
                if depth > 0 || !named {
                    return Err("\"rest\" only at the top level, with a name".into());
                }
            }
            "list" => {
                if depth >= MAX_DEPTH {
                    return Err("lists nest too deep".into());
                }
                if !named {
                    return Err("a list needs a name".into());
                }
                match field.count.as_deref() {
                    Some("u8" | "u16" | "u32" | "varint") => {}
                    _ => return Err("a list's count must be u8, u16, u32 or varint".into()),
                }
                check_fields(field.fields.as_deref().unwrap_or(&[]), depth + 1)?;
            }
            skip if skip.starts_with("skip:") => {
                let n: usize = skip[5..].parse().map_err(|_| format!("bad {skip}"))?;
                if n == 0 || n > 4096 {
                    return Err(format!("bad {skip}"));
                }
            }
            other => return Err(format!("unknown field type {other:?}")),
        }
    }
    Ok(())
}

fn take<'a>(body: &'a [u8], pos: &mut usize, n: usize) -> Option<&'a [u8]> {
    let end = pos.checked_add(n)?;
    let bytes = body.get(*pos..end)?;
    *pos = end;
    Some(bytes)
}

fn varint(body: &[u8], pos: &mut usize) -> Option<u64> {
    let mut value = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *take(body, pos, 1)?.first()?;
        value |= u64::from(byte & 0x7F) << shift;
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

fn number(kind: &str, body: &[u8], pos: &mut usize) -> Option<u64> {
    Some(match kind {
        "u8" => u64::from(take(body, pos, 1)?[0]),
        "u16" => u64::from(u16::from_le_bytes(take(body, pos, 2)?.try_into().ok()?)),
        "u32" => u64::from(u32::from_le_bytes(take(body, pos, 4)?.try_into().ok()?)),
        "u64" => u64::from_le_bytes(take(body, pos, 8)?.try_into().ok()?),
        "varint" => varint(body, pos)?,
        _ => return None,
    })
}

fn decode_fields(fields: &[FieldSpec], body: &[u8], pos: &mut usize) -> Option<Map<String, Value>> {
    let mut out = Map::new();
    for field in fields {
        let kind = field.kind.as_str();
        if let Some(n) = kind.strip_prefix("skip:") {
            take(body, pos, n.parse().ok()?)?;
            continue;
        }
        let name = field.name.clone().unwrap_or_default();
        match kind {
            "i32" => {
                let v = i32::from_le_bytes(take(body, pos, 4)?.try_into().ok()?);
                out.insert(name, Value::from(v));
            }
            "rest" => {
                let rest = body.get(*pos..)?;
                if rest.len() > MAX_REST {
                    return None;
                }
                *pos = body.len();
                let hex: String = rest.iter().map(|b| format!("{b:02x}")).collect();
                out.insert(name, Value::from(hex));
            }
            "list" => {
                let count = number(field.count.as_deref()?, body, pos)?;
                if count > MAX_LIST {
                    return None;
                }
                let inner = field.fields.as_deref().unwrap_or(&[]);
                let mut items = Vec::with_capacity(count as usize);
                for _ in 0..count {
                    items.push(Value::Object(decode_fields(inner, body, pos)?));
                }
                out.insert(name, Value::Array(items));
            }
            _ => {
                out.insert(name, Value::from(number(kind, body, pos)?));
            }
        }
    }
    Some(out)
}

static DECODERS: LazyLock<Vec<Decoder>> = LazyLock::new(|| {
    let specs: Vec<DecoderSpec> = serde_json::from_str(SPECS).expect("the decoders' list is JSON");
    specs.iter().map(|s| Decoder::compile(s).expect("a listed decoder compiles")).collect()
});

#[derive(Default)]
struct Queue {
    seq: u64,
    events: VecDeque<(u64, Value)>,
}

static QUEUE: LazyLock<Mutex<Queue>> = LazyLock::new(Mutex::default);

/// Reads one frame (its length varint, its type, its body) with every
/// decoder of its type; what reads is queued with `at` (unix ms).
pub fn feed(opcode: [u8; 2], body: &[u8], at: i64) {
    let mut decoded = Vec::new();
    for d in DECODERS.iter().filter(|d| d.opcode == opcode) {
        if let Some(data) = d.decode(body) {
            decoded.push(serde_json::json!({ "name": d.name, "at": at, "data": data }));
        }
    }
    if decoded.is_empty() {
        return;
    }
    let mut q = QUEUE.lock();
    for event in decoded {
        q.seq += 1;
        let seq = q.seq;
        q.events.push_back((seq, event));
        while q.events.len() > KEEP {
            q.events.pop_front();
        }
    }
}

/// The frames decoded after `since` (a sequence number), oldest first, and
/// the newest number; None when nothing came since.
pub fn events_since(since: u64) -> Option<(u64, Vec<Value>)> {
    let q = QUEUE.lock();
    if q.seq <= since {
        return None;
    }
    let list = q.events.iter().filter(|(s, _)| *s > since).map(|(_, e)| e.clone()).collect();
    Some((q.seq, list))
}

/// The newest sequence number (nothing before it is wanted).
pub fn newest() -> u64 {
    QUEUE.lock().seq
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(json: &str) -> Decoder {
        Decoder::compile(&serde_json::from_str(json).unwrap()).unwrap()
    }

    #[test]
    fn the_listed_decoders_compile() {
        assert_eq!(DECODERS.len(), 6);
    }

    #[test]
    fn a_varint_count_past_127() {
        let d = spec(r#"{"name":"pet-list","opcode":"00 90","fields":[
            {"type":"skip:4"},
            {"name":"levels","type":"list","count":"varint","fields":[
                {"name":"pet","type":"u32"},{"type":"skip:4"},{"name":"level","type":"u32"}]}]}"#);
        let mut body = vec![0x13, 0x05, 0, 0, 0x87, 0x01];
        for i in 0..135u32 {
            body.extend((1001 + i).to_le_bytes());
            body.extend((1001 + i).to_le_bytes());
            body.extend((1 + i % 3).to_le_bytes());
        }
        let v = d.decode(&body).unwrap();
        let levels = v["levels"].as_array().unwrap();
        assert_eq!(levels.len(), 135);
        assert_eq!(levels[134]["pet"], 1135);
        assert_eq!(levels[134]["level"], 3);
    }

    #[test]
    fn the_rest_as_hex() {
        let d = spec(r#"{"name":"shop","opcode":"91 56","fields":[
            {"name":"tab","type":"u8"},{"name":"count","type":"u8"},{"name":"body","type":"rest"}]}"#);
        assert_eq!(d.decode(&[103, 10, 0xab, 0x01]).unwrap(), serde_json::json!({"tab": 103, "count": 10, "body": "ab01"}));
        assert!(d.decode(&vec![0; 5000]).is_none());
    }

    #[test]
    fn a_short_frame_decodes_to_nothing_and_bad_decoders_are_refused() {
        let d = spec(r#"{"name":"x","opcode":"0D 90","fields":[{"name":"a","type":"u32"}]}"#);
        assert!(d.decode(&[1, 2]).is_none());
        for json in [
            r#"{"name":"x","opcode":"0D","fields":[]}"#,
            r#"{"name":"X!","opcode":"0D 90","fields":[]}"#,
            r#"{"name":"x","opcode":"0D 90","fields":[{"name":"r","type":"rest"},{"name":"a","type":"u8"}]}"#,
            r#"{"name":"x","opcode":"0D 90","fields":[{"type":"u32"}]}"#,
        ] {
            assert!(Decoder::compile(&serde_json::from_str(json).unwrap()).is_err(), "{json}");
        }
    }

    #[test]
    fn frames_are_queued_by_number() {
        let before = newest();
        // A gathering: great 1, kind 58, node 300 (varint ac 02), item, 2, 1.
        let mut body = vec![1, 58, 0xac, 0x02];
        body.extend(150_000_001u32.to_le_bytes());
        body.extend(2u32.to_le_bytes());
        body.extend(1u32.to_le_bytes());
        feed([0x33, 0x8D], &body, 1_000);
        feed([0x34, 0x8D], &body, 1_000);
        let (seq, list) = events_since(before).unwrap();
        let mine: Vec<_> = list.iter().filter(|e| e["name"] == "gathered" && e["at"] == 1_000).collect();
        assert!(!mine.is_empty());
        assert_eq!(mine[0]["data"]["node"], 300);
        assert_eq!(mine[0]["data"]["item"], 150_000_001u64);
        assert!(seq > before);
        assert!(events_since(seq).is_none());
    }
}
