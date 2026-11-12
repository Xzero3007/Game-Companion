//! What the overlay remembers between starts, in
//! `~/.config/game-companion/settings.json`.

use std::collections::BTreeMap;
use std::path::PathBuf;

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
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Place {
    pub x: f64,
    pub y: f64,
}

impl Default for Settings {
    fn default() -> Self {
        Self { alpha: DEFAULT_ALPHA, places: BTreeMap::new(), welcome: true }
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
        s.places.insert("welcome".into(), Place { x: 24.0, y: 120.0 });
        s.save_to(&path).unwrap();
        assert_eq!(Settings::load_from(&path), s);
    }

    #[test]
    fn broken_file_and_odd_values_fall_back() {
        let path = temp_file("broken");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(Settings::load_from(&path), Settings::default());
        std::fs::write(&path, r#"{"alpha": 3.0}"#).unwrap();
        assert_eq!(Settings::load_from(&path).alpha, 1.0);
        assert_eq!(clamp_alpha(f64::NAN), DEFAULT_ALPHA);
        assert_eq!(clamp_alpha(0.1), 0.5);
    }
}
