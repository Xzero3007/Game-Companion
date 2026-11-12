//! What the overlay remembers between starts, in
//! `~/.config/game-companion/settings.json`.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use serde::{Deserialize, Serialize};

/// The default see-through value of the overlay's panels (0.5 to 1).
pub const DEFAULT_ALPHA: f64 = 0.9;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// How solid the panels are, 0.5 (see-through) to 1 (solid).
    pub alpha: f64,
    /// Where each panel was left, by its id: its top-left corner in pixels.
    pub places: BTreeMap<String, Place>,
    /// Whether the welcome panel shows (it closes for good once closed).
    pub welcome: bool,
    /// What stays on screen while the hub is hidden, by id (panels, the
    /// player row).
    pub pins: BTreeSet<String>,
    pub radio: RadioSettings,
    /// Saved arrangements, by the name the user gave them.
    pub layouts: BTreeMap<String, Layout>,
    pub streams: StreamsSettings,
}

/// What a game brings to the Streams panel: its Twitch category and its
/// YouTube search words.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct GamePreset {
    pub name: String,
    pub twitch: String,
    pub youtube: String,
}

impl Default for GamePreset {
    fn default() -> Self {
        // Until game detection: AION 2, as the meter's plugin had it.
        Self { name: "AION 2".into(), twitch: "AION 2".into(), youtube: "AION 2".into() }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct StreamsSettings {
    pub game: GamePreset,
    /// Twitch channels kept with the star, by login.
    pub favourites: Vec<String>,
    /// YouTube channels added by hand (FreeTube's are read from FreeTube).
    pub channels: Vec<crate::streams::Channel>,
    /// The panel's tabs: "twitch" or "youtube", and each one's list.
    pub tab: String,
    pub twitch_view: String,
    pub youtube_view: String,
    /// "best", "1080" down to "360", or "audio".
    pub quality: String,
    /// 0 to 100, as the bars show it.
    pub volume: u8,
    /// The lists as tiles side by side (true) or as rows.
    pub grid: bool,
    /// How much of each video window shows, in percent (50 to 100), by slot.
    pub video_opacity: BTreeMap<String, u8>,
    /// SponsorBlock: off until switched on.
    pub sponsorblock: crate::sponsorblock::SponsorSettings,
}

impl Default for StreamsSettings {
    fn default() -> Self {
        Self {
            game: GamePreset::default(),
            favourites: Vec::new(),
            channels: Vec::new(),
            tab: "twitch".into(),
            twitch_view: "game".into(),
            youtube_view: "game".into(),
            quality: "1080".into(),
            volume: 70,
            grid: true,
            video_opacity: BTreeMap::new(),
            sponsorblock: Default::default(),
        }
    }
}

/// An arrangement to come back to: which panels are open, where and how
/// big they are, what is pinned, how solid the panels are.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Layout {
    pub open: Vec<String>,
    pub places: BTreeMap<String, Place>,
    pub pins: BTreeSet<String>,
    pub alpha: f64,
}

/// A layout's name: trimmed, at most 40 characters, not empty.
pub fn layout_name(name: &str) -> Option<String> {
    let name: String = name.trim().chars().filter(|c| !c.is_control()).take(40).collect();
    (!name.is_empty()).then_some(name)
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct RadioSettings {
    /// The station last played.
    pub station: Option<String>,
    /// 0 to 100, as the volume bar shows it.
    pub volume: u8,
    pub favourites: Vec<String>,
    /// The stations played last, newest first.
    pub recent: Vec<String>,
    /// The panel's list: "favourites", "all" or "recent".
    pub tab: String,
    /// "" for all countries, else a country id.
    pub country: String,
    /// "" for all genres, else a genre id.
    pub genre: String,
}

impl Default for RadioSettings {
    fn default() -> Self {
        Self {
            station: None,
            volume: 60,
            favourites: Vec::new(),
            recent: Vec::new(),
            tab: "all".into(),
            country: String::new(),
            genre: String::new(),
        }
    }
}

/// The settings, shared by everything in the app, loaded once.
fn shared() -> &'static Mutex<Settings> {
    static SHARED: OnceLock<Mutex<Settings>> = OnceLock::new();
    SHARED.get_or_init(|| Mutex::new(Settings::load()))
}

/// Reads the shared settings.
pub fn read<T>(f: impl FnOnce(&Settings) -> T) -> T {
    f(&shared().lock().unwrap_or_else(|p| p.into_inner()))
}

/// Changes the shared settings and saves them.
pub fn change<T>(f: impl FnOnce(&mut Settings) -> T) -> T {
    let mut guard = shared().lock().unwrap_or_else(|p| p.into_inner());
    let out = f(&mut guard);
    guard.save();
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct Place {
    pub x: f64,
    pub y: f64,
    /// The width the user gave it; 0 for its own.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub w: f64,
    /// The height the user added to its list or video; 0 for none.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub grow: f64,
}

fn is_zero(v: &f64) -> bool {
    *v == 0.0
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            alpha: DEFAULT_ALPHA,
            places: BTreeMap::new(),
            welcome: true,
            pins: BTreeSet::new(),
            radio: RadioSettings::default(),
            layouts: BTreeMap::new(),
            streams: StreamsSettings::default(),
        }
    }
}

impl Settings {
    /// The settings file: `$XDG_CONFIG_HOME/game-companion/settings.json`.
    pub fn path() -> Option<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
        Some(base.join("game-companion").join("settings.json"))
    }

    pub fn load() -> Self {
        Self::path().map(|p| Self::load_from(&p)).unwrap_or_default()
    }

    /// The settings in that file; defaults for a missing or broken file.
    pub fn load_from(path: &std::path::Path) -> Self {
        let mut settings: Self = std::fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        settings.alpha = clamp_alpha(settings.alpha);
        settings.radio.volume = settings.radio.volume.min(100);
        settings.streams.volume = settings.streams.volume.min(100);
        settings
    }

    pub fn save(&self) {
        if let Some(path) = Self::path() {
            if let Err(e) = self.save_to(&path) {
                eprintln!("game-companion: cannot save settings to {}: {e}", path.display());
            }
        }
    }

    /// Writes to a temporary file first, so a crash never leaves half a file.
    pub fn save_to(&self, path: &std::path::Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let text = serde_json::to_string_pretty(self).map_err(std::io::Error::other)?;
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, text)?;
        std::fs::rename(&tmp, path)
    }
}

/// Keeps the see-through value where panels stay readable.
pub fn clamp_alpha(alpha: f64) -> f64 {
    if alpha.is_finite() { alpha.clamp(0.5, 1.0) } else { DEFAULT_ALPHA }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_file(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir.join("settings.json")
    }

    #[test]
    fn missing_file_gives_defaults() {
        let s = Settings::load_from(&temp_file("missing"));
        assert_eq!(s, Settings::default());
        assert!(s.welcome);
    }

    #[test]
    fn saves_and_loads_places() {
        let path = temp_file("roundtrip");
        let mut s = Settings { alpha: 0.7, ..Default::default() };
        s.places.insert("welcome".into(), Place { x: 24.0, y: 120.0, ..Default::default() });
        s.places.insert("radio".into(), Place { x: 30.0, y: 140.0, w: 520.0, grow: 90.0 });
        s.layouts.insert(
            "Raid".into(),
            Layout { open: vec!["radio".into()], places: s.places.clone(), pins: s.pins.clone(), alpha: 0.8 },
        );
        s.pins.insert("radio".into());
        s.radio.favourites.push("best-fm".into());
        s.radio.volume = 45;
        s.save_to(&path).unwrap();
        assert_eq!(Settings::load_from(&path), s);
    }

    #[test]
    fn old_places_still_load_and_names_are_tidied() {
        let path = temp_file("old");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, r#"{"places": {"radio": {"x": 10, "y": 20}}}"#).unwrap();
        assert_eq!(Settings::load_from(&path).places["radio"], Place { x: 10.0, y: 20.0, w: 0.0, grow: 0.0 });
        assert_eq!(layout_name("  Raid night \n"), Some("Raid night".into()));
        assert_eq!(layout_name("   "), None);
        assert_eq!(layout_name(&"x".repeat(80)).unwrap().len(), 40);
    }

    #[test]
    fn broken_file_and_odd_values_fall_back() {
        let path = temp_file("broken");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(Settings::load_from(&path), Settings::default());
        std::fs::write(&path, r#"{"alpha": 3.0}"#).unwrap();
        assert_eq!(Settings::load_from(&path).alpha, 1.0);
        std::fs::write(&path, r#"{"radio": {"volume": 250}}"#).unwrap();
        assert_eq!(Settings::load_from(&path).radio.volume, 100);
        std::fs::write(&path, r#"{"alpha": 0.8}"#).unwrap();
        assert_eq!(Settings::load_from(&path).radio, RadioSettings::default());
        assert_eq!(clamp_alpha(f64::NAN), DEFAULT_ALPHA);
        assert_eq!(clamp_alpha(0.1), 0.5);
    }
}
