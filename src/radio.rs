//! Internet radio: the station list, the network guard for it, and a player
//! that runs the user's mpv in the background. The sound does not depend on
//! any window: it plays on with the radio panel closed or the hub hidden.
//!
//! The stations come from the Clicktrough Radio plugin
//! (`Xzero3007/A2Tools-Clicktrough-Plugins`, `plugins/radio/stations.js`,
//! GPL-3.0), converted by `dev/stations-from-plugin.mjs`. Only their own
//! stream addresses are played (the person's yes, 2026-11-10: radio streams,
//! listening only).

use std::collections::HashSet;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub country: String,
    #[serde(default)]
    pub info: String,
    #[serde(default)]
    pub genres: Vec<String>,
    pub streams: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Named {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Catalog {
    pub countries: Vec<Named>,
    pub genres: Vec<Named>,
    pub stations: Vec<Station>,
}

/// The station list, built into the app.
pub fn catalog() -> &'static Catalog {
    static CATALOG: OnceLock<Catalog> = OnceLock::new();
    CATALOG.get_or_init(|| serde_json::from_str(include_str!("../data/stations.json")).expect("data/stations.json"))
}

pub fn station(id: &str) -> Option<&'static Station> {
    catalog().stations.iter().find(|s| s.id == id)
}

/// The list for the panel, without the stream addresses (QML never sees
/// them).
pub fn catalog_for_ui() -> String {
    let c = catalog();
    let stations: Vec<serde_json::Value> = c
        .stations
        .iter()
        .map(|s| serde_json::json!({ "id": s.id, "name": s.name, "country": s.country, "info": s.info, "genres": s.genres }))
        .collect();
    serde_json::json!({ "countries": c.countries, "genres": c.genres, "stations": stations }).to_string()
}

/// The network guard for the radio: the servers of the station list, and
/// nothing else.
pub fn allowed_hosts() -> &'static HashSet<String> {
    static HOSTS: OnceLock<HashSet<String>> = OnceLock::new();
    HOSTS.get_or_init(|| {
        catalog()
            .stations
            .iter()
            .flat_map(|s| s.streams.iter())
            .filter_map(|u| host_of(u))
            .collect()
    })
}

/// `host[:port]` of an http(s) address, lower case.
pub fn host_of(url: &str) -> Option<String> {
    let rest = url.strip_prefix("https://").or_else(|| url.strip_prefix("http://"))?;
    let authority = rest.split(['/', '?', '#']).next()?;
    if authority.is_empty() || authority.contains('@') {
        return None;
    }
    Some(authority.to_ascii_lowercase())
}

/// Whether the radio may play this address.
pub fn is_allowed(url: &str) -> bool {
    host_of(url).is_some_and(|h| allowed_hosts().contains(&h))
}

/// mpv's volume for the bar's 0 to 100. mpv's volume is cubic; this makes the
/// bar sound like a browser's (meter patch 0063).
pub fn mpv_volume(bar: u8) -> f64 {
    let v = f64::from(bar.min(100)) / 100.0;
    (100.0 * v.cbrt() * 1000.0).round() / 1000.0
}

/// What the player reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// Sound is coming.
    Playing,
    /// Waiting for the stream.
    Buffering,
    /// This address did not play (why, in plain words).
    Failed(String),
    /// The stream ended (the server dropped it).
    Ended,
    /// mpv itself is gone.
    Gone,
}

/// The user's mpv, started once and kept idle between stations, controlled
/// through its JSON IPC socket.
pub struct Player {
    child: Child,
    socket: PathBuf,
    writer: Mutex<UnixStream>,
}

impl Player {
    /// Starts mpv. `on_event` runs on the reader thread.
    pub fn start(volume: u8, on_event: impl Fn(Event) + Send + 'static) -> Result<Player, String> {
        let name = format!("game-companion-radio-{}.sock", std::process::id());
        let socket = std::env::var_os("XDG_RUNTIME_DIR")
            .map(|dir| PathBuf::from(dir).join(&name))
            // A socket's path must stay short (about 100 bytes).
            .filter(|p| p.as_os_str().len() < 100)
            .unwrap_or_else(|| std::env::temp_dir().join(&name));
        let _ = std::fs::remove_file(&socket);
        let mut command = Command::new("mpv");
        command
            .arg("--idle=yes")
            .arg("--no-video")
            .arg("--no-terminal")
            .arg("--really-quiet")
            .arg("--no-config")
            // Radio only: no yt-dlp, no playlists pointing elsewhere.
            .arg("--ytdl=no")
            .arg("--load-unsafe-playlists=no")
            .arg("--audio-display=no")
            .arg("--network-timeout=15")
            .arg(format!("--volume={}", mpv_volume(volume)))
            .arg("--volume-max=100")
            .arg(format!("--input-ipc-server={}", socket.display()))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        // mpv ends with the app, even if the app is killed.
        // SAFETY: prctl only sets a flag on the child; no allocation.
        unsafe {
            command.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let child = command
            .spawn()
            .map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    "mpv is not installed (pacman -S mpv)".to_string()
                } else {
                    format!("mpv did not start: {e}")
                }
            })?;
        let started = Instant::now();
        let stream = loop {
            match UnixStream::connect(&socket) {
                Ok(s) => break s,
                Err(_) if started.elapsed() < Duration::from_secs(5) => std::thread::sleep(Duration::from_millis(50)),
                Err(e) => return Err(format!("mpv did not answer: {e}")),
            }
        };
        let reader = stream.try_clone().map_err(|e| e.to_string())?;
        let player = Player { child, socket, writer: Mutex::new(stream) };
        player.send(&serde_json::json!({ "command": ["observe_property", 1, "paused-for-cache"] }));
        std::thread::Builder::new()
            .name("radio-mpv".into())
            .spawn(move || {
                for line in BufReader::new(reader).lines().map_while(Result::ok) {
                    if let Some(event) = parse_event(&line) {
                        on_event(event);
                    }
                }
                on_event(Event::Gone);
            })
            .map_err(|e| e.to_string())?;
        Ok(player)
    }

    fn send(&self, message: &serde_json::Value) -> bool {
        let mut writer = self.writer.lock().unwrap_or_else(|p| p.into_inner());
        writeln!(writer, "{message}").is_ok()
    }

    /// Plays an address from the station list; refuses any other.
    pub fn load(&self, url: &str) -> bool {
        if !is_allowed(url) {
            return false;
        }
        self.send(&serde_json::json!({ "command": ["loadfile", url, "replace"] }))
    }

    pub fn stop(&self) {
        self.send(&serde_json::json!({ "command": ["stop"] }));
    }

    pub fn set_volume(&self, bar: u8) {
        self.send(&serde_json::json!({ "command": ["set_property", "volume", mpv_volume(bar)] }));
    }

}

impl Drop for Player {
    fn drop(&mut self) {
        self.send(&serde_json::json!({ "command": ["quit"] }));
        let deadline = Instant::now() + Duration::from_millis(500);
        while Instant::now() < deadline && matches!(self.child.try_wait(), Ok(None)) {
            std::thread::sleep(Duration::from_millis(20));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_file(&self.socket);
    }
}

/// One line from mpv's IPC, as the player's event, if it is one.
pub fn parse_event(line: &str) -> Option<Event> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    match v.get("event")?.as_str()? {
        "playback-restart" => Some(Event::Playing),
        "end-file" => match v.get("reason").and_then(|r| r.as_str()) {
            Some("error") => Some(Event::Failed(plain_error(v.get("file_error").and_then(|e| e.as_str()).unwrap_or("")))),
            Some("eof") => Some(Event::Ended),
            _ => None,
        },
        "property-change" if v.get("name").and_then(|n| n.as_str()) == Some("paused-for-cache") => {
            match v.get("data").and_then(|d| d.as_bool()) {
                Some(true) => Some(Event::Buffering),
                Some(false) => Some(Event::Playing),
                None => None,
            }
        }
        _ => None,
    }
}

/// mpv's error, in plain words.
fn plain_error(error: &str) -> String {
    let e = error.to_ascii_lowercase();
    if e.contains("loading failed") || e.contains("network") || e.contains("open") {
        "The station's server doesn't answer".into()
    } else if e.contains("unrecognized") || e.contains("format") || e.contains("demux") {
        "The stream couldn't be read".into()
    } else if e.contains("audio") {
        "No sound device".into()
    } else {
        "It doesn't play from here".into()
    }
}

/// The station after (or before) this one in a list of ids, wrapping round.
pub fn neighbour(ids: &[String], current: &str, forward: bool) -> Option<String> {
    if ids.is_empty() {
        return None;
    }
    let i = ids.iter().position(|id| id == current);
    let next = match (i, forward) {
        (None, _) => 0,
        (Some(i), true) => (i + 1) % ids.len(),
        (Some(i), false) => (i + ids.len() - 1) % ids.len(),
    };
    ids.get(next).cloned()
}

/// Puts a station first in the recent list, keeping ten.
pub fn remember(recent: &mut Vec<String>, id: &str) {
    recent.retain(|r| r != id);
    recent.insert(0, id.to_string());
    recent.truncate(10);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_list_has_every_station_and_best_fm_first() {
        let c = catalog();
        assert_eq!(c.stations.len(), 109);
        assert_eq!(c.stations[0].id, "best-fm");
        let ids: HashSet<_> = c.stations.iter().map(|s| &s.id).collect();
        assert_eq!(ids.len(), c.stations.len(), "station ids are unique");
        for s in &c.stations {
            assert!(!s.streams.is_empty(), "{} has a stream", s.id);
            assert!(c.countries.iter().any(|k| k.id == s.country), "{}'s country is listed", s.id);
            for g in &s.genres {
                assert!(c.genres.iter().any(|k| &k.id == g), "{}'s genre {g} is listed", s.id);
            }
        }
    }

    #[test]
    fn the_guard_allows_only_the_stations_servers() {
        for s in &catalog().stations {
            for u in &s.streams {
                assert!(is_allowed(u), "{u}");
            }
        }
        assert!(!is_allowed("https://example.com/stream.mp3"));
        assert!(!is_allowed("file:///etc/passwd"));
        assert!(!is_allowed("https://user@bestfm.turkhosted.com/;stream.mp3"));
        assert_eq!(host_of("https://Bestfm.Turkhosted.com/;stream.mp3").as_deref(), Some("bestfm.turkhosted.com"));
        assert_eq!(host_of("http://46.20.7.126/bestfmmp3").as_deref(), Some("46.20.7.126"));
    }

    #[test]
    fn the_ui_list_holds_no_stream_addresses() {
        assert!(!catalog_for_ui().contains("http"));
    }

    #[test]
    fn volume_sounds_like_a_browser() {
        assert_eq!(mpv_volume(0), 0.0);
        assert_eq!(mpv_volume(100), 100.0);
        assert_eq!(mpv_volume(255), 100.0);
        // Half the amplitude: mpv needs about 79.4 for it.
        assert!((mpv_volume(50) - 79.37).abs() < 0.01);
    }

    #[test]
    fn mpv_events() {
        assert_eq!(parse_event(r#"{"event":"playback-restart"}"#), Some(Event::Playing));
        assert_eq!(parse_event(r#"{"event":"end-file","reason":"eof"}"#), Some(Event::Ended));
        assert_eq!(parse_event(r#"{"event":"end-file","reason":"stop"}"#), None);
        assert_eq!(
            parse_event(r#"{"event":"end-file","reason":"error","file_error":"loading failed"}"#),
            Some(Event::Failed("The station's server doesn't answer".into()))
        );
        assert_eq!(
            parse_event(r#"{"event":"property-change","id":1,"name":"paused-for-cache","data":true}"#),
            Some(Event::Buffering)
        );
        assert_eq!(parse_event(r#"{"request_id":0,"error":"success"}"#), None);
        assert_eq!(parse_event("not json"), None);
    }

    #[test]
    fn next_and_previous_wrap_round() {
        let ids: Vec<String> = ["a", "b", "c"].iter().map(|s| s.to_string()).collect();
        assert_eq!(neighbour(&ids, "c", true).as_deref(), Some("a"));
        assert_eq!(neighbour(&ids, "a", false).as_deref(), Some("c"));
        assert_eq!(neighbour(&ids, "x", true).as_deref(), Some("a"));
        assert_eq!(neighbour(&[], "a", true), None);
    }

    /// Needs mpv: starts it, plays Best FM and waits for an answer (sound,
    /// or an error where there is no network or sound device).
    #[test]
    #[ignore]
    fn mpv_answers() {
        let (tx, rx) = std::sync::mpsc::channel();
        let player = Player::start(10, move |e| {
            let _ = tx.send(e);
        })
        .expect("mpv starts");
        assert!(player.load(&station("best-fm").unwrap().streams[0]));
        let event = rx.recv_timeout(Duration::from_secs(30)).expect("an event");
        eprintln!("mpv: {event:?}");
        assert!(!player.load("https://example.com/x.mp3"));
        drop(player);
    }

    #[test]
    fn recent_keeps_ten_newest_first() {
        let mut recent = Vec::new();
        for i in 0..12 {
            remember(&mut recent, &format!("s{i}"));
        }
        remember(&mut recent, "s5");
        assert_eq!(recent.len(), 10);
        assert_eq!(recent[0], "s5");
        assert_eq!(recent[1], "s11");
    }
}
