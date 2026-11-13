//! What the overlay remembers between starts, in
//! `~/.config/game-companion/settings.json`.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use serde::{Deserialize, Serialize};

/// The default see-through value of the overlay's panels (0.05 to 1).
pub const DEFAULT_ALPHA: f64 = 0.9;
/// The lowest see-through value: the panels' ground almost gone.
pub const MIN_ALPHA: f64 = 0.05;
/// The lowest text brightness (white and grey text, 0.4 to 1).
pub const MIN_TEXT_LEVEL: f64 = 0.4;
/// The smallest bar (0.6 to 1 of its size).
pub const MIN_BAR_SCALE: f64 = 0.6;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// How solid the panels are, 0.05 (almost see-through) to 1 (solid).
    pub alpha: f64,
    /// How bright the white and grey text of the bar and the player row
    /// is, 0.4 to 1 (as designed; panels stay as designed).
    pub text_level: f64,
    /// How bright the gold of the bar and the player row is, 0.4 to 1.
    pub accent_level: f64,
    /// How far a mouse-wheel notch scrolls the lists, in percent of a
    /// list's own step (50 to 500; MN, 2026-11-13).
    pub wheel_speed: u32,
    /// The three opacity values the buttons P1 to P3 jump to.
    pub alpha_presets: Vec<f64>,
    /// The three text brightness values the buttons P1 to P3 jump to.
    pub text_presets: Vec<f64>,
    /// The three gold brightness values the buttons P1 to P3 jump to.
    pub accent_presets: Vec<f64>,
    /// Where the bar sits and how big it is.
    pub bar: BarSettings,
    /// Where each panel was left, by its id: its top-left corner in pixels.
    pub places: BTreeMap<String, Place>,
    /// Whether the welcome panel shows (it closes for good once closed).
    pub welcome: bool,
    /// Whether updates come from the beta channel (test builds of the
    /// `beta` branch) instead of the stable releases.
    pub beta_updates: bool,
    /// Whether the icon shows in the desktop's tray (panel) while the app
    /// runs.
    pub tray: bool,
    /// Whether the hub shows when a game starts (each game's own start
    /// option applies on top).
    pub show_on_game: bool,
    /// The screen the overlay is on, by its connector name ("" = KDE's
    /// primary screen). Read by the C++ side at the start.
    pub screen: String,
    /// What stays on screen while the hub is hidden, by id (panels, the
    /// player row).
    pub pins: BTreeSet<String>,
    pub radio: RadioSettings,
    /// Saved arrangements, by the name the user gave them.
    pub layouts: BTreeMap<String, Layout>,
    pub streams: StreamsSettings,
    /// The Jellyfin tab's choices (the server and its key are kept apart,
    /// in `jellyfin.json`).
    pub jellyfin: JellyfinSettings,
    /// The Games tab: own entries and hidden games.
    pub games: crate::games::GamesSettings,
    /// Each plugin's choice (Settings → Plugins), by its id; a plugin not
    /// listed is on and in the bar.
    pub plugins: BTreeMap<String, PluginChoice>,
    /// Whether a game's package loads when the game runs, by the
    /// package's id; one not listed loads.
    pub packages: BTreeMap<String, bool>,
}

/// One plugin's choice: on or off, and where its button sits.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct PluginChoice {
    pub on: bool,
    /// "bar" (its own button) or "hidden" (no button; opened from the
    /// Plugins page).
    pub place: String,
}

impl Default for PluginChoice {
    fn default() -> Self {
        Self { on: true, place: "bar".into() }
    }
}

/// The bar at the top: moved sideways by `offset` pixels from the screen's
/// centre, drawn at `scale` (0.6 to 1) of its size.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct BarSettings {
    pub offset: f64,
    pub scale: f64,
}

impl Default for BarSettings {
    fn default() -> Self {
        Self { offset: 0.0, scale: 1.0 }
    }
}

impl BarSettings {
    pub fn tidy(self) -> Self {
        let offset = if self.offset.is_finite() { self.offset.clamp(-10_000.0, 10_000.0).round() } else { 0.0 };
        Self { offset, scale: clamp_bar_scale(self.scale) }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct JellyfinSettings {
    /// "continue", "nextup", "libraries" or "search".
    pub view: String,
    /// "original" (the file as it is), "1080" down to "360", or "audio".
    pub quality: String,
    /// Skip intros and credits by themselves.
    pub auto_skip: bool,
    /// Play a show's next episode when one ends.
    pub auto_next: bool,
}

impl Default for JellyfinSettings {
    fn default() -> Self {
        Self { view: "continue".into(), quality: "original".into(), auto_skip: false, auto_next: true }
    }
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
    /// Videos decoded by the graphics card (less work for the processor,
    /// more video memory).
    pub hwdec: bool,
    /// YouTube lists: Shorts left out, watched videos left out, channels and
    /// words whose videos never show.
    pub hide_shorts: bool,
    pub hide_watched: bool,
    pub hidden_channels: Vec<crate::streams::Channel>,
    pub hidden_words: Vec<String>,
    /// Videos whose title or channel is written in an Indian script left
    /// out (the person, 2026-11-13).
    pub hide_indian: bool,
    /// FreeTube's subscriptions are read from its file as they are (until
    /// they are taken over: then only `channels` count).
    pub freetube_live: bool,
    /// The subscriptions group shown ("" = all channels).
    pub group: String,
    /// The YouTube search's filter.
    pub search: SearchFilter,
    /// The languages YouTube's videos should be in (searches and Trending
    /// ask in them; [] = as YouTube gives it). By default the desktop's.
    pub video_languages: Vec<String>,
    /// The Trending tab's part, and search words changed from the default
    /// (by part).
    pub trend_section: String,
    pub trend_words: BTreeMap<String, Vec<String>>,
    /// YouTube channels' pictures by channel id, asked once each.
    pub channel_pictures: BTreeMap<String, String>,
    /// Twitch: a note when followed or favourite channels go live (asked
    /// every two minutes while on), and the channels left out of it.
    pub alerts: bool,
    pub alerts_off: BTreeSet<String>,
    /// The quality last chosen for a Twitch channel, by login.
    pub channel_quality: BTreeMap<String, String>,
    /// Twitch lists: only these languages ([] = all), reruns left out, and
    /// the order ("viewers" or "new").
    pub languages: Vec<String>,
    pub hide_reruns: bool,
    pub twitch_sort: String,
    /// Twitch chat: shown beside the Twitch video, and written in with the
    /// twitch.tv sign-in (off: reading only).
    pub chat_open: bool,
    pub chat_write: bool,
    /// The chat follows the Twitch video (until it is moved by hand).
    pub chat_docked: bool,
}

/// YouTube's search filter: sort ("relevance", "date", "views"), uploaded
/// ("any", "today", "week", "month", "year") and length ("any", "short",
/// "medium", "long").
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SearchFilter {
    pub sort: String,
    pub date: String,
    pub length: String,
}

impl Default for SearchFilter {
    fn default() -> Self {
        Self { sort: "relevance".into(), date: "any".into(), length: "any".into() }
    }
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
            hwdec: true,
            hide_shorts: true,
            hide_watched: false,
            hidden_channels: Vec::new(),
            hidden_words: Vec::new(),
            hide_indian: true,
            freetube_live: true,
            group: String::new(),
            search: SearchFilter::default(),
            video_languages: crate::streams::system_languages(),
            trend_section: "gaming".into(),
            trend_words: BTreeMap::new(),
            channel_pictures: BTreeMap::new(),
            alerts: false,
            alerts_off: BTreeSet::new(),
            channel_quality: BTreeMap::new(),
            languages: Vec::new(),
            hide_reruns: false,
            twitch_sort: "viewers".into(),
            chat_open: false,
            chat_write: true,
            chat_docked: true,
        }
    }
}

/// An arrangement to come back to: which panels are open, where and how
/// big they are, what is pinned, how solid the panels are, how bright the
/// text is, and where the bar is and its size (the last two missing in
/// layouts saved before they existed).
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Layout {
    pub open: Vec<String>,
    pub places: BTreeMap<String, Place>,
    pub pins: BTreeSet<String>,
    pub alpha: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text_level: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accent_level: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bar: Option<BarSettings>,
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
            text_level: 1.0,
            accent_level: 1.0,
            wheel_speed: 100,
            accent_presets: DEFAULT_TEXT_PRESETS.to_vec(),
            alpha_presets: DEFAULT_ALPHA_PRESETS.to_vec(),
            text_presets: DEFAULT_TEXT_PRESETS.to_vec(),
            bar: BarSettings::default(),
            places: BTreeMap::new(),
            welcome: true,
            beta_updates: false,
            tray: true,
            show_on_game: true,
            screen: String::new(),
            pins: BTreeSet::new(),
            radio: RadioSettings::default(),
            layouts: BTreeMap::new(),
            streams: StreamsSettings::default(),
            jellyfin: JellyfinSettings::default(),
            games: Default::default(),
            plugins: BTreeMap::new(),
            packages: BTreeMap::new(),
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
        settings.text_level = clamp_text_level(settings.text_level);
        settings.alpha_presets = presets(&settings.alpha_presets, &DEFAULT_ALPHA_PRESETS, clamp_alpha);
        settings.text_presets = presets(&settings.text_presets, &DEFAULT_TEXT_PRESETS, clamp_text_level);
        settings.accent_level = clamp_text_level(settings.accent_level);
        settings.accent_presets = presets(&settings.accent_presets, &DEFAULT_TEXT_PRESETS, clamp_text_level);
        settings.bar = settings.bar.tidy();
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

pub const DEFAULT_ALPHA_PRESETS: [f64; 3] = [0.9, 0.6, 0.2];
pub const DEFAULT_TEXT_PRESETS: [f64; 3] = [1.0, 0.8, 0.6];

/// Keeps the see-through value between almost see-through and solid.
pub fn clamp_alpha(alpha: f64) -> f64 {
    if alpha.is_finite() { alpha.clamp(MIN_ALPHA, 1.0) } else { DEFAULT_ALPHA }
}

/// Keeps the text brightness where text can still be read.
pub fn clamp_wheel_speed(percent: i32) -> u32 {
    percent.clamp(50, 500) as u32
}

pub fn clamp_text_level(level: f64) -> f64 {
    if level.is_finite() { level.clamp(MIN_TEXT_LEVEL, 1.0) } else { 1.0 }
}

pub fn clamp_bar_scale(scale: f64) -> f64 {
    if scale.is_finite() { scale.clamp(MIN_BAR_SCALE, 1.0) } else { 1.0 }
}

/// Always three presets, each in range; missing ones from the defaults.
fn presets(values: &[f64], defaults: &[f64; 3], clamp: fn(f64) -> f64) -> Vec<f64> {
    (0..3).map(|i| clamp(values.get(i).copied().unwrap_or(defaults[i]))).collect()
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
    fn older_files_keep_the_tray_and_show_on_game() {
        let path = temp_file("older");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, r#"{"alpha":0.5}"#).unwrap();
        let s = Settings::load_from(&path);
        assert!(s.tray && s.show_on_game);
        assert_eq!(s.alpha, 0.5);
    }

    #[test]
    fn saves_and_loads_places() {
        let path = temp_file("roundtrip");
        let mut s = Settings { alpha: 0.7, ..Default::default() };
        s.places.insert("welcome".into(), Place { x: 24.0, y: 120.0, ..Default::default() });
        s.places.insert("radio".into(), Place { x: 30.0, y: 140.0, w: 520.0, grow: 90.0 });
        s.layouts.insert(
            "Raid".into(),
            Layout {
                open: vec!["radio".into()],
                places: s.places.clone(),
                pins: s.pins.clone(),
                alpha: 0.8,
                text_level: Some(0.7),
                accent_level: Some(0.8),
                bar: Some(BarSettings { offset: -300.0, scale: 0.8 }),
            },
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
        assert_eq!(clamp_alpha(0.01), MIN_ALPHA);
        assert_eq!(clamp_alpha(0.1), 0.1);
        std::fs::write(&path, r#"{"text_level": 0.1, "alpha_presets": [0.3], "bar": {"offset": 1e9, "scale": 9}}"#).unwrap();
        let s = Settings::load_from(&path);
        assert_eq!(s.text_level, MIN_TEXT_LEVEL);
        assert_eq!(s.alpha_presets, vec![0.3, 0.6, 0.2]);
        assert_eq!(s.text_presets, DEFAULT_TEXT_PRESETS.to_vec());
        assert_eq!(s.bar, BarSettings { offset: 10_000.0, scale: 1.0 });
    }

    #[test]
    fn layouts_from_before_keep_loading() {
        let path = temp_file("oldlayout");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, r#"{"layouts": {"Raid": {"open": ["radio"], "alpha": 0.7}}}"#).unwrap();
        let layout = &Settings::load_from(&path).layouts["Raid"];
        assert_eq!(layout.text_level, None);
        assert_eq!(layout.accent_level, None);
        assert_eq!(layout.bar, None);
    }

    #[test]
    fn games_keep_loading() {
        let path = temp_file("games");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        // Files from before the Games tab, and odd entries.
        std::fs::write(&path, r#"{"alpha": 0.7}"#).unwrap();
        assert_eq!(Settings::load_from(&path).games, crate::games::GamesSettings::default());
        std::fs::write(&path, r#"{"games": {"own": [{"id": 2, "name": "Mine"}], "hidden": ["steam:10"]}}"#).unwrap();
        let s = Settings::load_from(&path);
        assert_eq!(s.games.own[0].name, "Mine");
        assert!(s.games.own[0].processes.is_empty());
        // Missing choices: the hub shows when it starts, the radio does not.
        assert!(s.games.own[0].show_on_start);
        assert!(!s.games.own[0].radio_on_start);
        assert!(s.games.hidden.contains("steam:10"));
        let mut s = Settings::default();
        s.games.own.push(crate::games::OwnGame {
            id: 1,
            name: "AION 2".into(),
            command: "wine x.exe".into(),
            processes: vec!["AION2.exe".into()],
            twitch: "AION 2".into(),
            ..Default::default()
        });
        s.games.favorites.insert("own:1".into());
        s.games.last_played.insert("own:1".into(), 1_700_000_000);
        s.games.options.insert("steam:10".into(), crate::games::GameOptions { radio_on_start: true, ..Default::default() });
        s.save_to(&path).unwrap();
        assert_eq!(Settings::load_from(&path), s);
    }
}
