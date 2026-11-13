//! Chat emotes beyond Twitch's own: 7TV's and BTTV's, global and a
//! channel's. Asked from 7tv.io and api.betterttv.net (the person's yes,
//! 2026-11-13); the pictures come from cdn.7tv.app and cdn.betterttv.net
//! (through `PictureNetwork`). Nothing about the person is sent: only the
//! channel's public Twitch id.

use std::collections::BTreeMap;
use std::sync::Mutex;
use std::time::Duration;

use serde_json::Value;

use crate::streams;

/// Emote name → picture address with its size at 1x (`[url, w, h]`), so
/// the chat can make room before the picture came.
pub type Emotes = BTreeMap<String, (String, u32, u32)>;

static GLOBAL: Mutex<Option<Emotes>> = Mutex::new(None);

fn valid_name(s: &str) -> bool {
    !s.is_empty() && s.len() <= 100 && !s.chars().any(char::is_whitespace)
}

fn valid_id(s: &str) -> bool {
    !s.is_empty() && s.len() <= 40 && s.chars().all(|c| c.is_ascii_alphanumeric())
}

fn fetch(url: &str) -> Option<Value> {
    let bytes = streams::get(url, Duration::from_secs(15)).ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// 7TV's emotes in a list (`[{name, id, data: {host: {files}}}]`).
pub fn seventv(list: &Value, into: &mut Emotes) {
    for e in list.as_array().into_iter().flatten() {
        let (Some(name), Some(id)) = (e["name"].as_str(), e["id"].as_str()) else { continue };
        if valid_name(name) && valid_id(id) {
            let files = e.pointer("/data/host/files").and_then(Value::as_array);
            let one = files.and_then(|f| f.iter().find(|x| x["name"] == "1x.webp"));
            let size = |k: &str| one.and_then(|x| x[k].as_u64()).map_or(32, |v| v.clamp(8, 128) as u32);
            into.insert(name.to_string(), (format!("https://cdn.7tv.app/emote/{id}/1x.webp"), size("width"), size("height")));
        }
    }
}

/// BTTV's emotes in a list (`[{code, id}]`).
pub fn bttv(list: &Value, into: &mut Emotes) {
    for e in list.as_array().into_iter().flatten() {
        let (Some(name), Some(id)) = (e["code"].as_str(), e["id"].as_str()) else { continue };
        if valid_name(name) && valid_id(id) {
            into.insert(name.to_string(), (format!("https://cdn.betterttv.net/emote/{id}/1x"), 28, 28));
        }
    }
}

fn global() -> Emotes {
    if let Some(g) = GLOBAL.lock().unwrap().clone() {
        return g;
    }
    let mut g = Emotes::new();
    if let Some(v) = fetch("https://api.betterttv.net/3/cached/emotes/global") {
        bttv(&v, &mut g);
    }
    if let Some(v) = fetch("https://7tv.io/v3/emote-sets/global") {
        seventv(&v["emotes"], &mut g);
    }
    if !g.is_empty() {
        *GLOBAL.lock().unwrap() = Some(g.clone());
    }
    g
}

/// The emotes for a channel's chat (its Twitch id): global ones, the
/// channel's own win on the same name. Unreachable parts are left out.
pub fn for_room(room: &str) -> Emotes {
    let mut all = global();
    if !room.chars().all(|c| c.is_ascii_digit()) || room.is_empty() || room.len() > 20 {
        return all;
    }
    if let Some(v) = fetch(&format!("https://api.betterttv.net/3/cached/users/twitch/{room}")) {
        bttv(&v["channelEmotes"], &mut all);
        bttv(&v["sharedEmotes"], &mut all);
    }
    if let Some(v) = fetch(&format!("https://7tv.io/v3/users/twitch/{room}")) {
        seventv(&v["emote_set"]["emotes"], &mut all);
    }
    all
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_both_lists() {
        let mut e = Emotes::new();
        bttv(&json!([{ "id": "54fa8f1401e468494b85b537", "code": "KEKW" }, { "id": "x y", "code": "bad" }]), &mut e);
        let files = json!({ "host": { "files": [{ "name": "1x.webp", "width": 64, "height": 32 }] } });
        seventv(&json!([{ "id": "01F6MQ33FG000FFJ97ZB8MWV52", "name": "catJAM", "data": files }, { "id": "1", "name": "two words" }]), &mut e);
        assert_eq!(e.len(), 2);
        assert_eq!(e["KEKW"], ("https://cdn.betterttv.net/emote/54fa8f1401e468494b85b537/1x".to_string(), 28, 28));
        assert_eq!(e["catJAM"], ("https://cdn.7tv.app/emote/01F6MQ33FG000FFJ97ZB8MWV52/1x.webp".to_string(), 64, 32));
    }
}
