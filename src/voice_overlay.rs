//! The voice overlay's link to Legcord: who is in the voice channel and
//! who talks, told by Game Companion's own Legcord plugin
//! (`legcord/game-companion-voice`, Legcord 1.3's plugin system).
//!
//! The plugin's main-process part connects to a Unix socket in
//! `$XDG_RUNTIME_DIR` (only this user may, checked by the peer's uid) and
//! writes one JSON object per line: `hello`, `check` (which of Discord's
//! stores it found), `state` (channel and members) and `picture` (an
//! avatar as base64 PNG). Nothing goes over the network here: no port is
//! opened, and Game Companion sends nothing to Legcord or Discord.

use std::io::{BufRead, BufReader, Read};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};

use serde_json::Value;

/// The plugin's id (its folder's name in Legcord's plugins folder).
pub const PLUGIN_ID: &str = "game-companion-voice";
/// The plugin version this build ships.
pub const PLUGIN_VERSION: i64 = 1;

/// The plugin's files, built into the binary: installing or refreshing
/// it needs nothing from the network or from /usr/share.
pub const PLUGIN_FILES: [(&str, &str); 3] = [
    ("manifest.json", include_str!("../legcord/game-companion-voice/manifest.json")),
    ("main.mjs", include_str!("../legcord/game-companion-voice/main.mjs")),
    ("renderer.js", include_str!("../legcord/game-companion-voice/renderer.js")),
];

/// The longest line taken (a 64 px avatar is far smaller).
const LONGEST_LINE: u64 = 512 * 1024;

/// The socket the plugin connects to.
pub fn socket_path() -> Option<PathBuf> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")?;
    Some(PathBuf::from(dir).join("game-companion-voice.sock"))
}

/// Legcord's settings folders that exist (the package's and Flatpak's).
pub fn legcord_dirs() -> Vec<PathBuf> {
    let mut out = Vec::new();
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|h| h.join(".config")));
    if let Some(c) = config {
        out.push(c.join("legcord"));
    }
    if let Some(h) = home {
        out.push(h.join(".var/app/app.legcord.Legcord/config/legcord"));
    }
    out.retain(|d| d.is_dir());
    out
}

/// Whether the plugin is in a Legcord settings folder.
pub fn installed_in(dir: &Path) -> bool {
    dir.join("plugins").join(PLUGIN_ID).join("manifest.json").is_file()
}

pub fn installed() -> bool {
    legcord_dirs().iter().any(|d| installed_in(d))
}

/// Writes the plugin's files into `legcord/plugins/game-companion-voice`
/// (only what differs). Returns whether anything changed.
pub fn write_plugin(legcord: &Path) -> std::io::Result<bool> {
    let dir = legcord.join("plugins").join(PLUGIN_ID);
    std::fs::create_dir_all(&dir)?;
    let mut changed = false;
    for (name, text) in PLUGIN_FILES {
        let path = dir.join(name);
        if std::fs::read_to_string(&path).ok().as_deref() == Some(text) {
            continue;
        }
        let tmp = dir.join(format!(".{name}.new"));
        std::fs::write(&tmp, text)?;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o644))?;
        std::fs::rename(&tmp, &path)?;
        changed = true;
    }
    Ok(changed)
}

/// "Install plugin": into every Legcord settings folder there is.
pub fn install() -> Result<(), String> {
    let dirs = legcord_dirs();
    if dirs.is_empty() {
        return Err("Legcord's settings folder was not found (start Legcord once).".into());
    }
    for d in &dirs {
        write_plugin(d).map_err(|e| format!("Could not write the plugin into {}: {e}", d.display()))?;
    }
    Ok(())
}

/// At start: an installed plugin gets this build's files (a fix arrives
/// with the update; Legcord takes it at its next start).
pub fn refresh() {
    for d in legcord_dirs() {
        if installed_in(&d) {
            if let Err(e) = write_plugin(&d) {
                eprintln!("game-companion: could not refresh the Legcord plugin: {e}");
            }
        }
    }
}

/// Removes the plugin from every Legcord settings folder.
pub fn remove() -> Result<(), String> {
    for d in legcord_dirs() {
        let dir = d.join("plugins").join(PLUGIN_ID);
        if dir.is_dir() {
            std::fs::remove_dir_all(&dir).map_err(|e| format!("Could not remove {}: {e}", dir.display()))?;
        }
    }
    Ok(())
}

/// One message from the plugin.
#[derive(Debug, Clone, PartialEq)]
pub enum Message {
    Hello { plugin: i64, legcord: String },
    Check { ok: bool, missing: Vec<String> },
    State(Value),
    Picture { hash: String, png: String },
    /// A picture written to disk (`file://` URL), by the reader thread.
    Saved { hash: String, url: String },
    /// The connection ended.
    Gone,
}

fn is_hash(h: &str) -> bool {
    let h = h.strip_prefix("a_").unwrap_or(h);
    h.len() == 32 && h.bytes().all(|b| b.is_ascii_hexdigit())
}

fn is_base64(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/' || b == b'=')
}

/// A short, clean text (names come from other people).
fn clean(s: &str, longest: usize) -> String {
    s.chars().filter(|c| !c.is_control()).take(longest).collect()
}

/// Reads one line; anything malformed is left out.
pub fn parse(line: &str) -> Option<Message> {
    let v: Value = serde_json::from_str(line).ok()?;
    let text = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or("");
    match text("t") {
        "hello" => Some(Message::Hello {
            plugin: v.get("plugin").and_then(Value::as_i64).unwrap_or(0),
            legcord: clean(text("legcord"), 32),
        }),
        "check" => Some(Message::Check {
            ok: v.get("ok").and_then(Value::as_bool).unwrap_or(false),
            missing: v
                .get("missing")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(Value::as_str).take(12).map(|s| clean(s, 120)).collect())
                .unwrap_or_default(),
        }),
        "state" => Some(Message::State(state(&v))),
        "picture" => {
            let (hash, png) = (text("hash"), text("png"));
            (is_hash(hash) && is_base64(png) && png.len() < 300_000)
                .then(|| Message::Picture { hash: hash.into(), png: png.into() })
        }
        _ => None,
    }
}

/// The state as QML gets it: only the known fields, names cleaned.
fn state(v: &Value) -> Value {
    let channel = v.get("channel").filter(|c| c.is_object()).map(|c| {
        serde_json::json!({
            "id": clean(c.get("id").and_then(Value::as_str).unwrap_or(""), 32),
            "name": clean(c.get("name").and_then(Value::as_str).unwrap_or(""), 100),
        })
    });
    let members: Vec<Value> = v
        .get("members")
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .take(100)
                .map(|m| {
                    let s = |k: &str| m.get(k).and_then(Value::as_str).unwrap_or("");
                    let b = |k: &str| m.get(k).and_then(Value::as_bool).unwrap_or(false);
                    let avatar = s("avatar");
                    serde_json::json!({
                        "id": clean(s("id"), 32),
                        "name": clean(s("name"), 64),
                        "avatar": if is_hash(avatar) { avatar } else { "" },
                        "speaking": b("speaking"),
                        "muted": b("muted"),
                        "deafened": b("deafened"),
                        "joined": m.get("joined").and_then(Value::as_f64).unwrap_or(0.0),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    serde_json::json!({
        "channel": channel,
        "me": clean(v.get("me").and_then(Value::as_str).unwrap_or(""), 32),
        "members": members,
    })
}

/// The uid of the process on the other end.
fn peer_uid(stream: &UnixStream) -> Option<u32> {
    let mut cred = libc::ucred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: getsockopt writes at most `len` bytes into `cred`.
    let r = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&mut cred as *mut libc::ucred).cast(),
            &mut len,
        )
    };
    (r == 0).then_some(cred.uid)
}

/// Listens on the socket on a thread of its own (blocked in `accept`, so
/// it costs nothing while idle) and hands every message to `deliver`.
/// One connection at a time: a new one replaces the old.
pub fn listen(deliver: impl Fn(Message) + Send + Sync + 'static) -> Result<(), String> {
    listen_at(&socket_path().ok_or("no XDG_RUNTIME_DIR")?, deliver)
}

fn listen_at(path: &Path, deliver: impl Fn(Message) + Send + Sync + 'static) -> Result<(), String> {
    // One Game Companion at a time (main.rs), so a socket there is a stale one.
    let _ = std::fs::remove_file(path);
    let listener = UnixListener::bind(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    let deliver = std::sync::Arc::new(deliver);
    // SAFETY: getuid has no preconditions.
    let me = unsafe { libc::getuid() };
    std::thread::Builder::new()
        .name("voice-socket".into())
        .spawn(move || {
            let current: std::sync::Arc<std::sync::Mutex<Option<UnixStream>>> = Default::default();
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };
                if peer_uid(&stream) != Some(me) {
                    continue;
                }
                if let Some(old) = current.lock().ok().and_then(|mut c| c.replace(stream.try_clone().ok()?)) {
                    let _ = old.shutdown(std::net::Shutdown::Both);
                }
                let deliver = deliver.clone();
                std::thread::Builder::new()
                    .name("voice-reader".into())
                    .spawn(move || {
                        read_lines(stream, &*deliver);
                        deliver(Message::Gone);
                    })
                    .ok();
            }
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}

fn read_lines(stream: UnixStream, deliver: &dyn Fn(Message)) {
    let mut reader = BufReader::new(stream);
    loop {
        let mut line = String::new();
        match (&mut reader).take(LONGEST_LINE).read_line(&mut line) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        if !line.ends_with('\n') {
            // Too long or cut off: the rest of that line is dropped.
            let mut rest = Vec::new();
            if reader.read_until(b'\n', &mut rest).map(|n| n == 0).unwrap_or(true) {
                return;
            }
            continue;
        }
        match parse(line.trim_end()) {
            Some(Message::Picture { hash, png }) => {
                if let Some(url) = save_picture(&hash, &png) {
                    deliver(Message::Saved { hash, url });
                }
            }
            Some(m) => deliver(m),
            None => {}
        }
    }
}

/// Decodes standard base64 (no line breaks).
pub fn base64_decode(text: &str) -> Option<Vec<u8>> {
    let value = |c: u8| -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32)
    };
    let bytes = text.trim_end_matches('=').as_bytes();
    let mut out = Vec::with_capacity(bytes.len() * 3 / 4);
    for chunk in bytes.chunks(4) {
        let mut n = 0u32;
        for (i, &c) in chunk.iter().enumerate() {
            n |= value(c)? << (18 - 6 * i as u32);
        }
        let got = chunk.len();
        if got < 2 {
            return None;
        }
        out.push((n >> 16) as u8);
        if got > 2 {
            out.push((n >> 8) as u8);
        }
        if got > 3 {
            out.push(n as u8);
        }
    }
    Some(out)
}

/// Where the avatars are kept while Game Companion runs (only this user's).
pub fn pictures_dir() -> Option<PathBuf> {
    let dir = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?).join("game-companion-voice");
    std::fs::create_dir_all(&dir).ok()?;
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).ok()?;
    Some(dir)
}

/// Writes an avatar (a PNG, checked by its signature) as `<hash>.png`.
fn save_picture(hash: &str, b64: &str) -> Option<String> {
    let png = base64_decode(b64)?;
    if !png.starts_with(b"\x89PNG\r\n\x1a\n") {
        return None;
    }
    let path = pictures_dir()?.join(format!("{hash}.png"));
    if !path.is_file() {
        let tmp = path.with_extension("new");
        std::fs::write(&tmp, &png).ok()?;
        std::fs::rename(&tmp, &path).ok()?;
    }
    Some(format!("file://{}", path.display()))
}

/// Removes the socket when Game Companion quits.
pub fn quit() {
    if let Some(p) = socket_path() {
        let _ = std::fs::remove_file(p);
    }
    if let Some(d) = std::env::var_os("XDG_RUNTIME_DIR") {
        let _ = std::fs::remove_dir_all(PathBuf::from(d).join("game-companion-voice"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_state() {
        let line = r#"{"t":"state","plugin":1,"channel":{"id":"12","name":"Raid\u0007","guild":"9"},"me":"5","members":[{"id":"5","name":"Kael","avatar":"0123456789abcdef0123456789abcdef","speaking":true,"muted":false,"deafened":false,"joined":17},{"id":"6","name":"Mira","avatar":"<script>","speaking":false,"muted":true}]}"#;
        let Some(Message::State(s)) = parse(line) else { panic!("no state") };
        assert_eq!(s["channel"]["name"], "Raid");
        assert_eq!(s["me"], "5");
        assert_eq!(s["members"][0]["speaking"], true);
        assert_eq!(s["members"][0]["avatar"], "0123456789abcdef0123456789abcdef");
        assert_eq!(s["members"][1]["avatar"], "");
        assert_eq!(s["members"][1]["muted"], true);
    }

    #[test]
    fn not_in_voice() {
        let Some(Message::State(s)) = parse(r#"{"t":"state","channel":null,"me":"5","members":[]}"#) else { panic!() };
        assert!(s["channel"].is_null());
        assert_eq!(s["members"].as_array().map(Vec::len), Some(0));
    }

    #[test]
    fn checks_and_pictures() {
        assert_eq!(
            parse(r#"{"t":"check","ok":false,"missing":["SpeakingStore"]}"#),
            Some(Message::Check { ok: false, missing: vec!["SpeakingStore".into()] })
        );
        assert!(parse(r#"{"t":"picture","hash":"a_0123456789abcdef0123456789abcdef","png":"iVBORw0KGgo="}"#).is_some());
        assert!(parse(r#"{"t":"picture","hash":"../x","png":"iVBORw0KGgo="}"#).is_none());
        assert!(parse(r#"{"t":"picture","hash":"0123456789abcdef0123456789abcdef","png":"no\"pe"}"#).is_none());
        assert!(parse("not json").is_none());
        assert!(parse(r#"{"t":"other"}"#).is_none());
    }

    #[test]
    fn decodes_base64() {
        assert_eq!(base64_decode("aGVsbG8=").unwrap(), b"hello");
        assert_eq!(base64_decode("aGk=").unwrap(), b"hi");
        assert_eq!(base64_decode("YWJj").unwrap(), b"abc");
        assert!(base64_decode("a$==").is_none());
    }

    #[test]
    fn writes_only_what_changed() {
        let dir = std::env::temp_dir().join(format!("gc-voice-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(write_plugin(&dir).unwrap());
        assert!(installed_in(&dir));
        assert!(!write_plugin(&dir).unwrap());
        let manifest: Value = serde_json::from_str(PLUGIN_FILES[0].1).unwrap();
        assert_eq!(manifest["id"], PLUGIN_ID);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn socket_takes_lines() {
        let dir = std::env::temp_dir().join(format!("gc-voice-sock-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("voice.sock");
        let (tx, rx) = std::sync::mpsc::channel();
        let tx = std::sync::Mutex::new(tx);
        listen_at(&path, move |m| {
            let _ = tx.lock().unwrap().send(m);
        })
        .unwrap();
        let mut s = UnixStream::connect(&path).unwrap();
        use std::io::Write;
        writeln!(s, r#"{{"t":"hello","plugin":1,"legcord":"1.3.1"}}"#).unwrap();
        writeln!(s, "{}", "x".repeat(600 * 1024)).unwrap();
        writeln!(s, r#"{{"t":"check","ok":true,"missing":[]}}"#).unwrap();
        drop(s);
        let wait = std::time::Duration::from_secs(5);
        assert_eq!(rx.recv_timeout(wait).unwrap(), Message::Hello { plugin: 1, legcord: "1.3.1".into() });
        assert_eq!(rx.recv_timeout(wait).unwrap(), Message::Check { ok: true, missing: vec![] });
        assert_eq!(rx.recv_timeout(wait).unwrap(), Message::Gone);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
