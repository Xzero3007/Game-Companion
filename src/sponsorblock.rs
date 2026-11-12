//! SponsorBlock: the parts of a YouTube video its viewers marked (sponsor,
//! self-promotion, intro…), from sponsor.ajay.app. Only the first four
//! characters of the video id's SHA-256 go there (its k-anonymity lookup):
//! the server never learns which video plays. Segments: SponsorBlock
//! (https://sponsor.ajay.app), CC BY-NC-SA 4.0.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::streams;

/// The categories, in the order Settings shows them.
pub const CATEGORIES: [&str; 8] = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "filler", "music_offtopic"];

/// On or off, and what each category does: "skip", "show" (marked on the
/// time line) or "off".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SponsorSettings {
    pub enabled: bool,
    pub categories: BTreeMap<String, String>,
}

impl Default for SponsorSettings {
    fn default() -> Self {
        let mut categories = BTreeMap::new();
        for c in CATEGORIES {
            let mode = match c {
                "sponsor" | "selfpromo" => "skip",
                "interaction" => "show",
                _ => "off",
            };
            categories.insert(c.to_string(), mode.to_string());
        }
        Self { enabled: false, categories }
    }
}

impl SponsorSettings {
    pub fn mode(&self, category: &str) -> &str {
        self.categories.get(category).map(String::as_str).unwrap_or("off")
    }

    /// The categories asked for (those not off).
    pub fn wanted(&self) -> Vec<&'static str> {
        CATEGORIES.iter().copied().filter(|c| self.mode(c) != "off").collect()
    }
}

/// The address asked: the hash's first four characters and the categories.
pub fn lookup_url(video_id: &str, categories: &[&str]) -> Option<String> {
    if !streams::valid_video_id(video_id) || categories.is_empty() {
        return None;
    }
    let hash = Sha256::digest(video_id.as_bytes());
    let prefix: String = hash.iter().take(2).map(|b| format!("{b:02x}")).collect();
    let list = Value::from(categories.to_vec()).to_string();
    Some(format!(
        "https://sponsor.ajay.app/api/skipSegments/{prefix}?categories={}&actionTypes=%5B%22skip%22%5D",
        streams::query_encode(&list)
    ))
}

/// The video's segments out of the answer (it holds every video whose hash
/// starts alike): `[{category, start, end}]`, in time order.
pub fn segments_of(answer: &Value, video_id: &str) -> Vec<Value> {
    let mut out: Vec<Value> = answer
        .as_array()
        .into_iter()
        .flatten()
        .filter(|v| v.get("videoID").and_then(Value::as_str) == Some(video_id))
        .flat_map(|v| v.get("segments").and_then(Value::as_array).cloned().unwrap_or_default())
        .filter_map(|s| {
            let category = s.get("category")?.as_str()?;
            if !CATEGORIES.contains(&category) {
                return None;
            }
            let span = s.get("segment")?.as_array()?;
            let (start, end) = (span.first()?.as_f64()?, span.get(1)?.as_f64()?);
            (end > start && start >= 0.0).then(|| json!({ "category": category, "start": start, "end": end }))
        })
        .collect();
    out.sort_by(|a, b| a["start"].as_f64().partial_cmp(&b["start"].as_f64()).unwrap_or(std::cmp::Ordering::Equal));
    out
}

/// Asks SponsorBlock for a video's segments (none found is no error).
pub fn segments(video_id: &str, settings: &SponsorSettings) -> Result<Vec<Value>, String> {
    let Some(url) = lookup_url(video_id, &settings.wanted()) else { return Ok(Vec::new()) };
    match streams::get(&url, Duration::from_secs(10)) {
        Ok(bytes) => {
            let answer: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
            Ok(segments_of(&answer, video_id))
        }
        // SponsorBlock answers 404 when no video with that hash start has any.
        Err(e) if e.contains("404") => Ok(Vec::new()),
        Err(e) => Err(format!("SponsorBlock: {e}")),
    }
}

fn freetube_settings_files() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    vec![
        config.join("FreeTube").join("settings.db"),
        home.join(".var/app/io.freetubeapp.FreeTube/config/FreeTube/settings.db"),
    ]
}

/// FreeTube's SponsorBlock settings (its settings file, NeDB: a JSON
/// document a line, a later one of the same `_id` winning).
pub fn from_freetube_text(text: &str) -> Option<SponsorSettings> {
    let mut values: BTreeMap<String, Value> = BTreeMap::new();
    for line in text.lines() {
        let Ok(doc) = serde_json::from_str::<Value>(line) else { continue };
        if let (Some(id), Some(value)) = (doc.get("_id").and_then(Value::as_str), doc.get("value")) {
            values.insert(id.to_string(), value.clone());
        }
    }
    let enabled = values.get("useSponsorBlock").and_then(Value::as_bool)?;
    let mut out = SponsorSettings { enabled, ..SponsorSettings::default() };
    for (category, key) in [
        ("sponsor", "sponsorBlockSponsor"),
        ("selfpromo", "sponsorBlockSelfPromo"),
        ("interaction", "sponsorBlockInteraction"),
        ("intro", "sponsorBlockIntro"),
        ("outro", "sponsorBlockOutro"),
        ("preview", "sponsorBlockRecap"),
        ("filler", "sponsorBlockFiller"),
        ("music_offtopic", "sponsorBlockMusicOffTopic"),
    ] {
        let Some(skip) = values.get(key).and_then(|v| v.get("skip")).and_then(Value::as_str) else { continue };
        let mode = match skip {
            "autoSkip" => "skip",
            "promptToSkip" | "showInSeekBar" => "show",
            _ => "off",
        };
        out.categories.insert(category.to_string(), mode.to_string());
    }
    Some(out)
}

/// FreeTube's SponsorBlock settings on this computer, if FreeTube has any.
pub fn from_freetube() -> Option<SponsorSettings> {
    freetube_settings_files().iter().find_map(|f| std::fs::read_to_string(f).ok()).and_then(|t| from_freetube_text(&t))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_hash_start_is_sent() {
        let url = lookup_url("dQw4w9WgXcQ", &["sponsor", "intro"]).unwrap();
        assert!(url.starts_with("https://sponsor.ajay.app/api/skipSegments/"));
        assert!(!url.contains("dQw4w9WgXcQ"));
        let prefix = url.trim_start_matches("https://sponsor.ajay.app/api/skipSegments/").split('?').next().unwrap();
        assert_eq!(prefix.len(), 4);
        assert!(url.contains("categories=%5B%22sponsor%22%2C%22intro%22%5D"));
        assert_eq!(lookup_url("bad id!", &["sponsor"]), None);
        assert_eq!(lookup_url("dQw4w9WgXcQ", &[]), None);
    }

    #[test]
    fn segments_of_that_video_only() {
        let answer = json!([
            { "videoID": "other000000", "segments": [{ "category": "sponsor", "segment": [1.0, 2.0] }] },
            { "videoID": "dQw4w9WgXcQ", "segments": [
                { "category": "intro", "segment": [30.0, 40.0] },
                { "category": "sponsor", "segment": [5.0, 12.5] },
                { "category": "nonsense", "segment": [1.0, 2.0] },
                { "category": "outro", "segment": [9.0, 3.0] }
            ] }
        ]);
        let s = segments_of(&answer, "dQw4w9WgXcQ");
        assert_eq!(s.len(), 2);
        assert_eq!(s[0], json!({ "category": "sponsor", "start": 5.0, "end": 12.5 }));
        assert_eq!(s[1]["category"], "intro");
    }

    #[test]
    fn freetube_settings_taken_over() {
        let text = concat!(
            "{\"_id\":\"useSponsorBlock\",\"value\":false}\n",
            "{\"_id\":\"sponsorBlockSponsor\",\"value\":{\"color\":\"Green\",\"skip\":\"autoSkip\"}}\n",
            "{\"_id\":\"sponsorBlockIntro\",\"value\":{\"color\":\"Cyan\",\"skip\":\"showInSeekBar\"}}\n",
            "{\"_id\":\"sponsorBlockSelfPromo\",\"value\":{\"color\":\"Yellow\",\"skip\":\"doNothing\"}}\n",
            "{\"_id\":\"useSponsorBlock\",\"value\":true}\n"
        );
        let s = from_freetube_text(text).unwrap();
        assert!(s.enabled);
        assert_eq!(s.mode("sponsor"), "skip");
        assert_eq!(s.mode("intro"), "show");
        assert_eq!(s.mode("selfpromo"), "off");
        assert_eq!(s.mode("interaction"), "show");
        assert_eq!(from_freetube_text("{}"), None);
    }
}
