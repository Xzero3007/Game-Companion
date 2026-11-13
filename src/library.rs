//! YouTube kept on this computer: the user's playlists (one of them the
//! "quick" list the bookmark on every video fills), what was watched and
//! where it stopped. Nothing here goes out. Kept in `youtube.json` beside
//! the settings; FreeTube's playlists and history can be taken over once
//! (its files are only read).

use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::streams::{valid_channel_id, valid_video_id};

/// At most this many videos are remembered as watched.
pub const MAX_HISTORY: usize = 1000;
/// At most this many videos in one playlist, and this many playlists.
pub const MAX_IN_PLAYLIST: usize = 5000;
pub const MAX_PLAYLISTS: usize = 500;
/// A video counts as watched this close to its end (seconds), or past 92 %.
const NEAR_END: f64 = 30.0;
/// Under this many seconds in, a video starts from the beginning again.
const RESUME_FROM: f64 = 15.0;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Video {
    pub id: String,
    pub title: String,
    pub channel: String,
    #[serde(rename = "channelId")]
    pub channel_id: String,
    /// Seconds; 0 when not known.
    pub duration: f64,
    /// When it was published (ISO), "" when not known.
    pub published: String,
}

impl Video {
    /// A video as a list hands it over (the panel's JSON), checked.
    pub fn from_json(v: &Value) -> Option<Video> {
        let id = v.get("id")?.as_str()?;
        if !valid_video_id(id) {
            return None;
        }
        let text = |k: &str, max: usize| v.get(k).and_then(Value::as_str).unwrap_or("").chars().filter(|c| !c.is_control()).take(max).collect::<String>();
        let channel_id = text("channelId", 24);
        Some(Video {
            id: id.to_string(),
            title: text("title", 300),
            channel: text("channel", 100),
            channel_id: if valid_channel_id(&channel_id) { channel_id } else { String::new() },
            duration: v.get("duration").and_then(Value::as_f64).filter(|d| d.is_finite() && *d >= 0.0).unwrap_or(0.0),
            published: text("published", 40),
        })
    }

    /// As the panel's lists show a video.
    pub fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "title": self.title,
            "channel": self.channel,
            "channelId": self.channel_id,
            "duration": self.duration,
            "views": 0,
            "live": false,
            "published": self.published,
            "picture": format!("https://i.ytimg.com/vi/{}/mqdefault.jpg", self.id),
        })
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    /// Unix seconds.
    pub created: u64,
    pub updated: u64,
    pub played: u64,
    pub videos: Vec<Video>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Watched {
    #[serde(flatten)]
    pub video: Video,
    /// When it was last watched (Unix seconds).
    pub at: u64,
    /// Where it stopped, and how long it is (seconds).
    pub position: f64,
    pub length: f64,
    /// Watched to the end (or marked so).
    pub done: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Library {
    pub playlists: Vec<Playlist>,
    /// The playlist the bookmark on every video fills ("" = none yet: the
    /// first bookmark makes "Watch later").
    pub quick: String,
    /// Newest first.
    pub history: Vec<Watched>,
    /// FreeTube's playlists and history were taken over (once).
    pub freetube_taken: bool,
}

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn clean_name(name: &str) -> String {
    name.trim().chars().filter(|c| !c.is_control()).take(80).collect()
}

impl Library {
    fn new_id(&self) -> String {
        let mut n = now();
        loop {
            let id = format!("p{n:x}");
            if !self.playlists.iter().any(|p| p.id == id) {
                return id;
            }
            n += 1;
        }
    }

    pub fn playlist(&self, id: &str) -> Option<&Playlist> {
        self.playlists.iter().find(|p| p.id == id)
    }

    fn playlist_mut(&mut self, id: &str) -> Option<&mut Playlist> {
        self.playlists.iter_mut().find(|p| p.id == id)
    }

    /// A new, empty playlist; its id ("" when the name is empty or there
    /// are too many).
    pub fn create(&mut self, name: &str) -> String {
        let name = clean_name(name);
        if name.is_empty() || self.playlists.len() >= MAX_PLAYLISTS {
            return String::new();
        }
        let id = self.new_id();
        let t = now();
        self.playlists.push(Playlist { id: id.clone(), name, created: t, updated: t, played: 0, videos: Vec::new() });
        id
    }

    pub fn rename(&mut self, id: &str, name: &str) -> bool {
        let name = clean_name(name);
        match self.playlist_mut(id) {
            Some(p) if !name.is_empty() => {
                p.name = name;
                p.updated = now();
                true
            }
            _ => false,
        }
    }

    pub fn delete(&mut self, id: &str) -> bool {
        let before = self.playlists.len();
        self.playlists.retain(|p| p.id != id);
        if self.quick == id {
            self.quick.clear();
        }
        self.playlists.len() != before
    }

    /// The quick list, made ("Watch later") if there is none.
    pub fn quick_id(&mut self) -> String {
        if self.playlist(&self.quick).is_none() {
            self.quick = match self.playlists.iter().find(|p| p.name == "Watch later") {
                Some(p) => p.id.clone(),
                None => self.create("Watch later"),
            };
        }
        self.quick.clone()
    }

    /// Adds a video to a playlist (once); false if it was there already.
    pub fn add(&mut self, id: &str, video: Video) -> bool {
        let Some(p) = self.playlist_mut(id) else { return false };
        if p.videos.iter().any(|v| v.id == video.id) || p.videos.len() >= MAX_IN_PLAYLIST {
            return false;
        }
        p.videos.push(video);
        p.updated = now();
        true
    }

    pub fn remove(&mut self, id: &str, video: &str) -> bool {
        let Some(p) = self.playlist_mut(id) else { return false };
        let before = p.videos.len();
        p.videos.retain(|v| v.id != video);
        let changed = p.videos.len() != before;
        if changed {
            p.updated = now();
        }
        changed
    }

    /// Moves a playlist's video from one place to another.
    pub fn move_video(&mut self, id: &str, from: usize, to: usize) -> bool {
        let Some(p) = self.playlist_mut(id) else { return false };
        if from >= p.videos.len() || to >= p.videos.len() || from == to {
            return false;
        }
        let v = p.videos.remove(from);
        p.videos.insert(to, v);
        p.updated = now();
        true
    }

    pub fn mark_played(&mut self, id: &str) {
        if let Some(p) = self.playlist_mut(id) {
            p.played = now();
        }
    }

    /// The bookmark: in the quick list or not (switched).
    pub fn toggle_quick(&mut self, video: Video) -> bool {
        let quick = self.quick_id();
        if self.playlist(&quick).is_some_and(|p| p.videos.iter().any(|v| v.id == video.id)) {
            self.remove(&quick, &video.id);
            false
        } else {
            self.add(&quick, video);
            true
        }
    }

    pub fn in_quick(&self, video: &str) -> bool {
        self.playlist(&self.quick).is_some_and(|p| p.videos.iter().any(|v| v.id == video))
    }

    /// The playlists holding a video, by id.
    pub fn holding(&self, video: &str) -> Vec<String> {
        self.playlists.iter().filter(|p| p.videos.iter().any(|v| v.id == video)).map(|p| p.id.clone()).collect()
    }

    /// Where a video stopped: kept at the front of the history.
    pub fn record(&mut self, video: Video, position: f64, length: f64) {
        if !position.is_finite() || !length.is_finite() || position < 0.0 {
            return;
        }
        let length = if length > 0.0 { length } else { video.duration };
        let done = length > 0.0 && (position >= length - NEAR_END || position >= length * 0.92);
        let earlier = self.history.iter().position(|w| w.video.id == video.id).map(|i| self.history.remove(i));
        let mut video = video;
        if let Some(e) = &earlier {
            // A bare video (a pasted link) keeps what was known of it.
            if video.title.is_empty() {
                video.title = e.video.title.clone();
            }
            if video.channel.is_empty() {
                video.channel = e.video.channel.clone();
                video.channel_id = e.video.channel_id.clone();
            }
            if video.published.is_empty() {
                video.published = e.video.published.clone();
            }
        }
        if length > 0.0 {
            video.duration = length;
        }
        let was_done = earlier.is_some_and(|e| e.done);
        // Watched to the end, then started again: it stays watched.
        let position = if done { length } else { position };
        self.history.insert(0, Watched { video, at: now(), position, length, done: done || was_done });
        self.history.truncate(MAX_HISTORY);
    }

    pub fn set_done(&mut self, video: Video, done: bool) {
        match self.history.iter_mut().find(|w| w.video.id == video.id) {
            Some(w) => {
                w.done = done;
                if !done {
                    w.position = 0.0;
                }
            }
            None if done => {
                let length = video.duration;
                self.history.insert(0, Watched { video, at: now(), position: length, length, done: true });
                self.history.truncate(MAX_HISTORY);
            }
            None => {}
        }
    }

    pub fn forget(&mut self, video: &str) {
        self.history.retain(|w| w.video.id != video);
    }

    /// How far a video is watched (0 to 1) and whether it is done.
    pub fn progress(&self, video: &str) -> (f64, bool) {
        match self.history.iter().find(|w| w.video.id == video) {
            Some(w) if w.done => (1.0, true),
            Some(w) if w.length > 0.0 => ((w.position / w.length).clamp(0.0, 1.0), false),
            _ => (0.0, false),
        }
    }

    pub fn watched(&self, video: &str) -> bool {
        self.history.iter().any(|w| w.video.id == video && w.done)
    }

    /// Where to start a video again: where it stopped, unless near the
    /// start or done.
    pub fn resume_at(&self, video: &str) -> f64 {
        match self.history.iter().find(|w| w.video.id == video) {
            Some(w) if !w.done && w.position >= RESUME_FROM && (w.length <= 0.0 || w.position < w.length - NEAR_END) => w.position,
            _ => 0.0,
        }
    }

    /// The playlists for the Playlists tab: `[{id, name, count, picture,
    /// created, updated, played, quick}]`.
    pub fn summary(&self) -> Value {
        Value::Array(
            self.playlists
                .iter()
                .map(|p| {
                    json!({
                        "id": p.id,
                        "name": p.name,
                        "count": p.videos.len(),
                        "picture": p.videos.first().map(|v| format!("https://i.ytimg.com/vi/{}/mqdefault.jpg", v.id)).unwrap_or_default(),
                        "created": p.created,
                        "updated": p.updated,
                        "played": p.played,
                        "quick": p.id == self.quick,
                        "titles": p.videos.iter().map(|v| v.title.to_lowercase()).collect::<Vec<_>>().join("\n"),
                    })
                })
                .collect(),
        )
    }

    /// The history as list entries, newest first (`text` narrows it).
    pub fn history_list(&self, text: &str) -> Vec<Value> {
        let text = text.trim().to_lowercase();
        self.history
            .iter()
            .filter(|w| text.is_empty() || w.video.title.to_lowercase().contains(&text) || w.video.channel.to_lowercase().contains(&text))
            .take(300)
            .map(|w| {
                let mut v = w.video.to_json();
                v["watchedAt"] = json!(w.at);
                v
            })
            .collect()
    }

    /// Takes over FreeTube's playlists (merged by name) and history (what is
    /// not known here yet). Says what came.
    pub fn take_freetube(&mut self, playlists: Option<&str>, history: Option<&str>, quick: Option<&str>) -> (usize, usize) {
        let mut lists = 0;
        let mut seen = 0;
        if let Some(text) = playlists {
            for doc in nedb(text) {
                let name = clean_name(doc.get("playlistName").and_then(Value::as_str).unwrap_or(""));
                if name.is_empty() {
                    continue;
                }
                let ft_id = doc.get("_id").and_then(Value::as_str).unwrap_or("");
                let id = match self.playlists.iter().find(|p| p.name == name) {
                    Some(p) => p.id.clone(),
                    None => {
                        let id = self.create(&name);
                        if id.is_empty() {
                            continue;
                        }
                        lists += 1;
                        if let Some(p) = self.playlist_mut(&id) {
                            let ms = |k: &str| doc.get(k).and_then(Value::as_u64).map(|t| t / 1000);
                            p.created = ms("createdAt").unwrap_or(p.created);
                            p.updated = ms("lastUpdatedAt").unwrap_or(p.updated);
                            p.played = ms("lastPlayedAt").unwrap_or(0);
                        }
                        id
                    }
                };
                if quick == Some(ft_id) && !ft_id.is_empty() {
                    self.quick = id.clone();
                }
                for v in doc.get("videos").and_then(Value::as_array).into_iter().flatten() {
                    if let Some(video) = freetube_video(v) {
                        let updated = self.playlist(&id).map(|p| p.updated);
                        self.add(&id, video);
                        // Taking over is not a change of the user's.
                        if let (Some(u), Some(p)) = (updated, self.playlist_mut(&id)) {
                            p.updated = u;
                        }
                    }
                }
            }
        }
        if let Some(text) = history {
            let mut docs: Vec<Value> = nedb(text);
            docs.sort_by_key(|d| std::cmp::Reverse(d.get("timeWatched").and_then(Value::as_u64).unwrap_or(0)));
            for d in docs {
                let Some(video) = freetube_video(&d) else { continue };
                if self.history.iter().any(|w| w.video.id == video.id) {
                    continue;
                }
                let length = video.duration;
                let position = d.get("watchProgress").and_then(Value::as_f64).unwrap_or(0.0).max(0.0);
                let done = length > 0.0 && (position >= length - NEAR_END || position >= length * 0.92);
                let at = d.get("timeWatched").and_then(Value::as_u64).map(|t| t / 1000).unwrap_or(0);
                self.history.push(Watched { video, at, position, length, done });
                seen += 1;
            }
            self.history.sort_by_key(|w| std::cmp::Reverse(w.at));
            self.history.truncate(MAX_HISTORY);
        }
        self.freetube_taken = true;
        (lists, seen)
    }
}

/// A FreeTube video (playlist entry or history entry).
fn freetube_video(v: &Value) -> Option<Video> {
    let id = v.get("videoId")?.as_str()?;
    if !valid_video_id(id) {
        return None;
    }
    let published = v.get("published").and_then(Value::as_u64).and_then(iso_of_ms).unwrap_or_default();
    Video::from_json(&json!({
        "id": id,
        "title": v.get("title").and_then(Value::as_str).unwrap_or(""),
        "channel": v.get("author").and_then(Value::as_str).unwrap_or(""),
        "channelId": v.get("authorId").and_then(Value::as_str).unwrap_or(""),
        "duration": v.get("lengthSeconds").and_then(|l| l.as_f64().or_else(|| l.as_str().and_then(|s| s.parse().ok()))).unwrap_or(0.0),
        "published": published,
    }))
}

/// Milliseconds since 1970 as an ISO date-time (UTC).
fn iso_of_ms(ms: u64) -> Option<String> {
    let secs = (ms / 1000) as i64;
    if secs <= 0 {
        return None;
    }
    let days = secs.div_euclid(86_400);
    let rest = secs.rem_euclid(86_400);
    // Civil from days (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    Some(format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", rest / 3600, rest % 3600 / 60, rest % 60))
}

/// A NeDB file's documents (a JSON document a line; a later line of the
/// same `_id` replaces an earlier one; deleted ones go).
pub fn nedb(text: &str) -> Vec<Value> {
    // The last line of an id wins (NeDB appends changes), in the order the
    // ids last came; looked up by id, so a long history stays quick.
    let mut docs: Vec<Option<Value>> = Vec::new();
    let mut at: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for line in text.lines() {
        let Ok(doc) = serde_json::from_str::<Value>(line) else { continue };
        let Some(key) = doc.get("_id").and_then(Value::as_str).map(str::to_string) else { continue };
        if let Some(i) = at.remove(&key) {
            docs[i] = None;
        }
        if doc.get("$$deleted").and_then(Value::as_bool) != Some(true) {
            at.insert(key, docs.len());
            docs.push(Some(doc));
        }
    }
    docs.into_iter().flatten().collect()
}

/// FreeTube's folder (its own, or the Flatpak's) if there is one.
pub fn freetube_dir() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    [config.join("FreeTube"), home.join(".var/app/io.freetubeapp.FreeTube/config/FreeTube")].into_iter().find(|d| d.is_dir())
}

/// FreeTube's quick bookmark playlist, from its settings file.
pub fn freetube_quick(settings: &str) -> Option<String> {
    nedb(settings)
        .into_iter()
        .find(|d| d.get("_id").and_then(Value::as_str) == Some("quickBookmarkTargetPlaylistId"))
        .and_then(|d| d.get("value").and_then(Value::as_str).map(str::to_string))
}

fn file_path() -> Option<PathBuf> {
    crate::settings::Settings::path().map(|p| p.with_file_name("youtube.json"))
}

fn store() -> &'static Mutex<Option<Library>> {
    static L: OnceLock<Mutex<Option<Library>>> = OnceLock::new();
    L.get_or_init(|| Mutex::new(None))
}

fn load_from(path: &Path) -> Library {
    std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn save_to(path: &Path, lib: &Library) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(text) = serde_json::to_string(lib) else { return };
    // Written beside and moved over, so a crash never leaves half a file.
    let tmp = path.with_extension("json.new");
    if std::fs::write(&tmp, text).is_ok() {
        let _ = std::fs::rename(&tmp, path);
    }
}

/// Reads the library (loaded once).
pub fn read<T>(f: impl FnOnce(&Library) -> T) -> T {
    let mut guard = store().lock().unwrap_or_else(|p| p.into_inner());
    let lib = guard.get_or_insert_with(|| file_path().map(|p| load_from(&p)).unwrap_or_default());
    f(lib)
}

/// Changes the library and writes it down (not in screenshots).
pub fn change<T>(f: impl FnOnce(&mut Library) -> T) -> T {
    let mut guard = store().lock().unwrap_or_else(|p| p.into_inner());
    let lib = guard.get_or_insert_with(|| file_path().map(|p| load_from(&p)).unwrap_or_default());
    let out = f(lib);
    if !DEMO.load(std::sync::atomic::Ordering::Relaxed) {
        if let Some(p) = file_path() {
            save_to(&p, lib);
            DIRTY.store(false, std::sync::atomic::Ordering::Relaxed);
        }
    }
    out
}

/// Kept in memory but not yet written (a playing video's place).
static DIRTY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static LAST_SAVE: Mutex<Option<std::time::Instant>> = Mutex::new(None);

/// Changes the library in memory only (a playing video's place every few
/// seconds); `save_soon` or `save_now` writes it.
pub fn change_quiet<T>(f: impl FnOnce(&mut Library) -> T) -> T {
    let mut guard = store().lock().unwrap_or_else(|p| p.into_inner());
    let lib = guard.get_or_insert_with(|| file_path().map(|p| load_from(&p)).unwrap_or_default());
    let out = f(lib);
    DIRTY.store(true, std::sync::atomic::Ordering::Relaxed);
    out
}

/// Writes what changed quietly, in the background: at once with `now`,
/// else at most once a minute.
pub fn save_soon(now: bool) {
    if !DIRTY.load(std::sync::atomic::Ordering::Relaxed) || DEMO.load(std::sync::atomic::Ordering::Relaxed) {
        return;
    }
    {
        let mut last = LAST_SAVE.lock().unwrap_or_else(|p| p.into_inner());
        if !now && last.is_some_and(|t| t.elapsed() < std::time::Duration::from_secs(60)) {
            return;
        }
        *last = Some(std::time::Instant::now());
    }
    std::thread::spawn(save_now);
}

/// Writes what changed quietly, here and now (on quitting).
pub fn save_now() {
    if !DIRTY.swap(false, std::sync::atomic::Ordering::Relaxed) || DEMO.load(std::sync::atomic::Ordering::Relaxed) {
        return;
    }
    let guard = store().lock().unwrap_or_else(|p| p.into_inner());
    if let (Some(lib), Some(p)) = (guard.as_ref(), file_path()) {
        save_to(&p, lib);
    }
}

static DEMO: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Screenshots (GC_DEMO=streams): made-up playlists and history, kept in
/// memory only.
pub fn demo() {
    DEMO.store(true, std::sync::atomic::Ordering::Relaxed);
    let mut l = Library::default();
    let names = [("arr stack", 7), ("Jellyfin", 5), ("aion2", 4), ("POE2", 6), ("linux", 9), ("grade aktuell", 15), ("Sim Racing", 4), ("Unraid Docker", 3)];
    for (i, (name, n)) in names.iter().enumerate() {
        let id = l.create(name);
        if let Some(p) = l.playlist_mut(&id) {
            p.id = format!("demo{i}");
            p.played = 1_700_000_000 - i as u64 * 1000;
            for k in 0..*n {
                p.videos.push(Video { id: format!("demo{i:02}{k:05}"), title: format!("{name} video {}", k + 1), channel: "channel_name".into(), duration: 600.0 + k as f64 * 60.0, ..Default::default() });
            }
        }
    }
    l.quick = "demo2".into();
    l.record(Video { id: "demo0000000".into(), title: "AION 2 class guide: every skill explained".into(), channel: "channel_name".into(), duration: 1102.0, ..Default::default() }, 700.0, 1102.0);
    l.record(Video { id: "demo0000001".into(), title: "Patch notes in ten minutes".into(), channel: "another_channel".into(), duration: 587.0, ..Default::default() }, 587.0, 587.0);
    *store().lock().unwrap_or_else(|p| p.into_inner()) = Some(l);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(id: &str) -> Video {
        Video { id: id.into(), title: format!("Title {id}"), duration: 600.0, ..Default::default() }
    }

    #[test]
    fn playlists_add_once_move_and_go() {
        let mut l = Library::default();
        let a = l.create("  Linux  ");
        assert_eq!(l.playlist(&a).unwrap().name, "Linux");
        assert!(l.create("").is_empty());
        assert!(l.add(&a, v("aaaaaaaaaaa")));
        assert!(!l.add(&a, v("aaaaaaaaaaa")));
        assert!(l.add(&a, v("bbbbbbbbbbb")));
        assert!(l.move_video(&a, 1, 0));
        assert_eq!(l.playlist(&a).unwrap().videos[0].id, "bbbbbbbbbbb");
        assert_eq!(l.holding("aaaaaaaaaaa"), vec![a.clone()]);
        assert!(l.remove(&a, "aaaaaaaaaaa"));
        assert!(l.rename(&a, "Linux stuff"));
        assert!(l.delete(&a));
        assert!(l.playlists.is_empty());
    }

    #[test]
    fn the_bookmark_makes_watch_later() {
        let mut l = Library::default();
        assert!(l.toggle_quick(v("aaaaaaaaaaa")));
        assert_eq!(l.playlist(&l.quick).unwrap().name, "Watch later");
        assert!(l.in_quick("aaaaaaaaaaa"));
        assert!(!l.toggle_quick(v("aaaaaaaaaaa")));
        assert!(!l.in_quick("aaaaaaaaaaa"));
        assert_eq!(l.playlists.len(), 1);
    }

    #[test]
    fn history_resumes_and_marks_watched() {
        let mut l = Library::default();
        l.record(v("aaaaaaaaaaa"), 120.0, 600.0);
        assert_eq!(l.resume_at("aaaaaaaaaaa"), 120.0);
        assert_eq!(l.progress("aaaaaaaaaaa"), (0.2, false));
        l.record(v("bbbbbbbbbbb"), 5.0, 600.0);
        assert_eq!(l.resume_at("bbbbbbbbbbb"), 0.0);
        assert_eq!(l.history[0].video.id, "bbbbbbbbbbb");
        l.record(v("aaaaaaaaaaa"), 590.0, 600.0);
        assert!(l.watched("aaaaaaaaaaa"));
        assert_eq!(l.resume_at("aaaaaaaaaaa"), 0.0);
        // Started again from the start: still watched.
        l.record(v("aaaaaaaaaaa"), 20.0, 600.0);
        assert!(l.watched("aaaaaaaaaaa"));
        l.set_done(v("aaaaaaaaaaa"), false);
        assert!(!l.watched("aaaaaaaaaaa"));
        // A bare video keeps the title known before.
        l.record(Video { id: "bbbbbbbbbbb".into(), ..Default::default() }, 30.0, 600.0);
        assert_eq!(l.history[0].video.title, "Title bbbbbbbbbbb");
        assert_eq!(l.history_list("title b").len(), 1);
        l.forget("bbbbbbbbbbb");
        assert_eq!(l.history.len(), 1);
    }

    #[test]
    fn freetube_is_taken_over_once_merged() {
        let playlists = concat!(
            r#"{"playlistName":"Favorites","protected":true,"videos":[{"videoId":"aaaaaaaaaaa","title":"One","author":"Chan","authorId":"UCaaaaaaaaaaaaaaaaaaaaaa","lengthSeconds":61}],"_id":"favorites","createdAt":1700000000000}"#,
            "\n",
            r#"{"playlistName":"aion2","videos":[{"videoId":"bbbbbbbbbbb","title":"Two","lengthSeconds":"300"},{"videoId":"bad"}],"_id":"x1"}"#,
            "\n",
            r#"{"playlistName":"gone","videos":[],"_id":"x2"}"#,
            "\n",
            r#"{"_id":"x2","$$deleted":true}"#,
        );
        let history = r#"{"videoId":"ccccccccccc","title":"Three","lengthSeconds":600,"watchProgress":580,"timeWatched":1700000500000,"_id":"h1"}"#;
        let mut l = Library::default();
        let quick = freetube_quick(r#"{"_id":"quickBookmarkTargetPlaylistId","value":"x1"}"#);
        assert_eq!(l.take_freetube(Some(playlists), Some(history), quick.as_deref()), (2, 1));
        assert_eq!(l.playlists.len(), 2);
        assert_eq!(l.playlist(&l.quick).unwrap().name, "aion2");
        assert_eq!(l.playlists[1].videos.len(), 1);
        assert_eq!(l.playlists[1].videos[0].duration, 300.0);
        assert_eq!(l.playlists[0].created, 1_700_000_000);
        assert!(l.watched("ccccccccccc"));
        // Again: nothing doubled.
        assert_eq!(l.take_freetube(Some(playlists), Some(history), None), (0, 0));
        assert_eq!(l.playlists[0].videos.len(), 1);
    }

    #[test]
    fn dates_from_milliseconds() {
        assert_eq!(iso_of_ms(1_700_000_000_000).as_deref(), Some("2023-11-14T22:13:20Z"));
        assert_eq!(iso_of_ms(0), None);
    }
}
