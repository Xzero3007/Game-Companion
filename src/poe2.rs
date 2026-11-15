//! Path of Exile 2's price check (the person's choice, 2026-11-15: Exiled
//! Exchange 2 rebuilt so it works reliably on KDE Wayland). Exiled Exchange
//! 2's own parser and trade requests run in QML (`qml/poe2/ee2kit.js`, made
//! by `tools/poe2-ee2/build.mjs`); this side does what QML must not:
//!
//! - the trade site's requests (www.pathofexile.com/api/trade2/ only,
//!   curl in the background, its rate limits kept: a 429 stops every
//!   request until its wait is over),
//! - EE2's item and stat data (data/poe2, read only),
//! - the clipboard: the game copies an item's text itself when the person
//!   presses Ctrl+C over it. PoE 2 runs through Proton in XWayland, so its
//!   clipboard is XWayland's: an X client is told of every change (XFixes)
//!   without needing the focus, which a Wayland client would. Only texts
//!   that look like an item go to QML; nothing is ever sent to the game.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The only host asked, and the only part of it.
pub const TRADE_API: &str = "https://www.pathofexile.com/api/trade2/";

/// Whether an address may be asked: the trade site's API, a plain path and
/// query (no `..`, no fragment, no other host or port).
pub fn allowed(url: &str) -> bool {
    let Some(rest) = url.strip_prefix(TRADE_API) else { return false };
    let path = rest.split('?').next().unwrap_or("");
    let first = path.split('/').next().unwrap_or("");
    ["search", "fetch", "exchange", "data"].contains(&first)
        && !rest.contains("..")
        && !rest.contains('#')
        && !rest.contains('\\')
        && !rest.chars().any(|c| c.is_control() || c == ' ')
}

/// The folder with EE2's data: $GC_POE2_DATA, the installed one, else (a
/// build run from the repository) the repository's.
pub fn data_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("GC_POE2_DATA") {
        return Some(PathBuf::from(dir));
    }
    let installed = Path::new("/usr/share/game-companion/poe2");
    if installed.is_dir() {
        return Some(installed.to_path_buf());
    }
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("data/poe2");
    repo.is_dir().then_some(repo)
}

/// A data file's text ("" if it is not there). `name` is a relative path
/// of plain parts (`en/items.ndjson`).
pub fn data_file(name: &str) -> String {
    if !data_name_ok(name) {
        return String::new();
    }
    data_dir().and_then(|d| std::fs::read_to_string(d.join(name)).ok()).unwrap_or_default()
}

fn data_name_ok(name: &str) -> bool {
    !name.is_empty()
        && name.len() < 100
        && !name.starts_with('/')
        && name.split('/').all(|p| !p.is_empty() && p != "." && p != "..")
        && name.chars().all(|c| c.is_ascii_alphanumeric() || "/._-".contains(c))
}

/// Whether a copied text is an item from the game (its first lines name
/// the item class or the rarity, in a language EE2's data covers), so that
/// nothing else copied ever reaches QML.
pub fn looks_like_item(text: &str) -> bool {
    const STARTS: [&str; 4] = ["Item Class: ", "Rarity: ", "Gegenstandsklasse: ", "Seltenheit: "];
    text.len() < 64 * 1024
        && text.contains("--------")
        && text.lines().take(2).any(|l| STARTS.iter().any(|s| l.starts_with(s)))
}

/// The trade site's answer: status, headers (names in lower case) and body.
pub struct Answer {
    pub status: u16,
    pub headers: serde_json::Map<String, serde_json::Value>,
    pub body: String,
}

/// When the trade site said to wait (429), the moment that wait ends.
static BLOCKED: Mutex<Option<Instant>> = Mutex::new(None);
/// One request at a time.
static TURN: Mutex<()> = Mutex::new(());

const SPLIT: &str = "\n\u{1}gc-poe2-split\u{1}";

/// Percent-encodes what a browser would before asking: spaces and other
/// bytes not allowed in an address (a league's name such as "Runes of Aldur"
/// comes from EE2 unencoded; Electron's fetch encoded it, curl does not).
pub fn encode_address(url: &str) -> String {
    let mut out = String::with_capacity(url.len());
    for b in url.bytes() {
        if b <= b' ' || b >= 0x7f || b"\"<>\\^`{|}".contains(&b) {
            out.push_str(&format!("%{b:02X}"));
        } else {
            out.push(b as char);
        }
    }
    out
}

/// Asks the trade site (GET, or POST with a JSON body).
pub fn request(method: &str, url: &str, body: &str) -> Result<Answer, String> {
    let url = &encode_address(url);
    if !allowed(url) {
        return Err("not the trade site's API".into());
    }
    if method != "GET" && method != "POST" {
        return Err("only GET and POST".into());
    }
    let _turn = TURN.lock().unwrap_or_else(|p| p.into_inner());
    if let Some(until) = *BLOCKED.lock().unwrap_or_else(|p| p.into_inner()) {
        let now = Instant::now();
        if now < until {
            let secs = until.duration_since(now).as_secs() + 1;
            return Ok(Answer {
                status: 429,
                headers: serde_json::Map::new(),
                body: serde_json::json!({ "error": { "code": 3, "message": format!("Rate limit: wait {secs} s") } }).to_string(),
            });
        }
    }
    let config = curl_config(method, url, body);
    let mut child = Command::new("curl")
        .args(["-q", "--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl did not start: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(config.as_bytes()).map_err(|e| e.to_string())?;
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let line = err.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("no answer").trim().to_string();
        return Err(line.trim_start_matches("curl: ").chars().take(200).collect());
    }
    let answer = parse_output(&String::from_utf8_lossy(&out.stdout))?;
    if answer.status == 429 {
        let wait = answer.headers.get("retry-after").and_then(|v| v.as_str()).and_then(|v| v.trim().parse::<u64>().ok()).unwrap_or(60);
        *BLOCKED.lock().unwrap_or_else(|p| p.into_inner()) = Some(Instant::now() + Duration::from_secs(wait.clamp(1, 3600)));
    }
    Ok(answer)
}

fn curl_config(method: &str, url: &str, body: &str) -> String {
    use crate::streams::curl_quote;
    let mut c = String::from("silent\nshow-error\nproto = \"=https\"\nmax-time = 20\nmax-filesize = 16777216\ncompressed\n");
    c.push_str(&format!("user-agent = {}\n", curl_quote(&format!("GameCompanion/{} (Linux; PoE 2 price check)", env!("CARGO_PKG_VERSION")))));
    c.push_str("header = \"Accept: application/json\"\n");
    if let Some(jar) = cookie_jar() {
        // The site's own cookies (Cloudflare's), kept for this session only.
        let jar = curl_quote(&jar.to_string_lossy());
        c.push_str(&format!("cookie = {jar}\ncookie-jar = {jar}\n"));
    }
    if method == "POST" {
        c.push_str("header = \"Content-Type: application/json\"\n");
        c.push_str(&format!("data-binary = {}\n", curl_quote(body)));
    }
    c.push_str(&format!("write-out = {}\n", curl_quote(&format!("{SPLIT}%{{http_code}} %{{header_json}}"))));
    // No [] or {} ranges: the address is taken as it is.
    c.push_str("globoff\n");
    c.push_str(&format!("url = {}\n", curl_quote(url)));
    c
}

/// $XDG_RUNTIME_DIR/game-companion-poe2.cookies: gone with the session.
fn cookie_jar() -> Option<PathBuf> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")?;
    Some(PathBuf::from(dir).join("game-companion-poe2.cookies"))
}

/// curl's output: the body, then our marker, the status and the headers
/// as JSON (each name with a list of values).
fn parse_output(out: &str) -> Result<Answer, String> {
    let at = out.rfind(SPLIT).ok_or("no answer")?;
    let (body, tail) = out.split_at(at);
    let tail = &tail[SPLIT.len()..];
    let (code, json) = tail.split_once(' ').unwrap_or((tail, "{}"));
    let status: u16 = code.trim().parse().map_err(|_| "no status")?;
    let mut headers = serde_json::Map::new();
    if let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(json.trim()) {
        for (k, v) in map {
            let v = match v {
                serde_json::Value::Array(list) => list.last().and_then(|x| x.as_str()).unwrap_or("").to_string(),
                serde_json::Value::String(s) => s,
                _ => continue,
            };
            headers.insert(k.to_lowercase(), serde_json::Value::String(v));
        }
    }
    Ok(Answer { status, headers, body: body.to_string() })
}

/// Watches XWayland's clipboard (XFixes) on its own thread and hands every
/// item text to `copied` while `on()` says so. The thread waits on the X
/// connection: nothing runs between copies.
pub fn watch_clipboard(on: impl Fn() -> bool + Send + 'static, copied: impl Fn(String) + Send + 'static) -> Result<(), String> {
    use x11rb::connection::Connection;
    use x11rb::protocol::xfixes::{ConnectionExt as _, SelectionEventMask};
    use x11rb::protocol::xproto::{AtomEnum, ConnectionExt as _, CreateWindowAux, EventMask, WindowClass};
    use x11rb::protocol::Event;

    if std::env::var_os("DISPLAY").is_none() {
        return Err("no XWayland display (DISPLAY is not set)".into());
    }
    let (conn, screen) = x11rb::connect(None).map_err(|e| format!("XWayland: {e}"))?;
    let root = conn.setup().roots[screen].root;
    let win = conn.generate_id().map_err(|e| e.to_string())?;
    conn.create_window(0, win, root, -1, -1, 1, 1, 0, WindowClass::INPUT_ONLY, 0, &CreateWindowAux::new().event_mask(EventMask::PROPERTY_CHANGE))
        .map_err(|e| e.to_string())?;
    let atom = |name: &str| -> Result<u32, String> {
        Ok(conn.intern_atom(false, name.as_bytes()).map_err(|e| e.to_string())?.reply().map_err(|e| e.to_string())?.atom)
    };
    let clipboard = atom("CLIPBOARD")?;
    let utf8 = atom("UTF8_STRING")?;
    let prop = atom("GC_POE2_CLIP")?;
    conn.xfixes_query_version(5, 0).map_err(|e| e.to_string())?.reply().map_err(|e| format!("XFixes: {e}"))?;
    conn.xfixes_select_selection_input(win, clipboard, SelectionEventMask::SET_SELECTION_OWNER).map_err(|e| e.to_string())?;
    conn.flush().map_err(|e| e.to_string())?;
    std::thread::Builder::new()
        .name("poe2-clipboard".into())
        .spawn(move || loop {
            let Ok(event) = conn.wait_for_event() else {
                crate::log::write("poe2", "clipboard watcher: XWayland connection lost, watcher stopped");
                return;
            };
            match event {
                Event::XfixesSelectionNotify(e) if e.selection == clipboard => {
                    if on() {
                        let _ = conn.convert_selection(win, clipboard, utf8, prop, e.selection_timestamp);
                        let _ = conn.flush();
                    }
                }
                Event::SelectionNotify(e) if e.requestor == win && e.property == prop => {
                    let reply = conn.get_property(true, win, prop, AtomEnum::ANY, 0, 64 * 1024 / 4).ok().and_then(|c| c.reply().ok());
                    let _ = conn.flush();
                    if let Some(r) = reply {
                        if r.type_ == utf8 || r.type_ == u32::from(AtomEnum::STRING) {
                            let text = String::from_utf8_lossy(&r.value).replace("\r\n", "\n");
                            if on() {
                                let item = looks_like_item(&text);
                                // Never the text itself: only whether it was an item.
                                crate::log::write("poe2", &format!("copy seen: {} ({} bytes)", if item { "item, checking" } else { "not an item, ignored" }, text.len()));
                                if item {
                                    copied(text);
                                }
                            }
                        }
                    }
                }
                _ => {}
            }
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_trade_api() {
        assert!(allowed("https://www.pathofexile.com/api/trade2/search/Standard"));
        assert!(allowed("https://www.pathofexile.com/api/trade2/search/Rise%20of%20the%20Abyssal"));
        assert!(allowed("https://www.pathofexile.com/api/trade2/fetch/a,b?query=q1"));
        assert!(allowed("https://www.pathofexile.com/api/trade2/data/leagues"));
        assert!(allowed("https://www.pathofexile.com/api/trade2/exchange/Standard"));
        assert!(!allowed("https://www.pathofexile.com/api/trade2/../account"));
        assert!(!allowed("https://www.pathofexile.com/api/trade2/whisper"));
        assert!(!allowed("https://www.pathofexile.com/api/profile"));
        assert!(!allowed("https://www.pathofexile.com.evil.example/api/trade2/search/x"));
        assert!(!allowed("https://www.pathofexile.com:8443/api/trade2/search/x"));
        assert!(!allowed("http://www.pathofexile.com/api/trade2/search/x"));
        assert!(!allowed("https://poe.ninja/api/trade2/search/x"));
        assert!(!allowed("https://www.pathofexile.com/api/trade2/search/x#y"));
        assert!(!allowed("https://www.pathofexile.com/api/trade2/search/a b"));
        // A league with spaces, as EE2 writes it, is encoded first (MN, 0.8.42:
        // "Runes of Aldur" was refused).
        let league = encode_address("https://www.pathofexile.com/api/trade2/search/poe2/Runes of Aldur");
        assert_eq!(league, "https://www.pathofexile.com/api/trade2/search/poe2/Runes%20of%20Aldur");
        assert!(allowed(&league));
        assert_eq!(encode_address("a\"b{c}ä"), "a%22b%7Bc%7D%C3%A4");
        assert!(!allowed(&encode_address("https://www.pathofexile.com/api/trade2/search/../x")));
    }

    #[test]
    fn data_names() {
        assert!(data_name_ok("en/items.ndjson"));
        assert!(data_name_ok("item-drop.json"));
        assert!(!data_name_ok("../settings.json"));
        assert!(!data_name_ok("/etc/passwd"));
        assert!(!data_name_ok("en//x"));
        assert!(!data_name_ok("en/./x"));
    }

    #[test]
    fn data_is_there() {
        assert!(data_file("en/stats.ndjson").len() > 1000);
        assert!(data_file("de/items.ndjson").len() > 1000);
    }

    #[test]
    fn items_and_other_texts() {
        assert!(looks_like_item("Item Class: Bows\nRarity: Rare\nDire Nock\nRider Bow\n--------\nQuality: +20%"));
        assert!(looks_like_item("Gegenstandsklasse: Bögen\nSeltenheit: Selten\nX\n--------\n"));
        assert!(looks_like_item("Rarity: Gem\nMeta\n--------\n"));
        assert!(!looks_like_item("hello"));
        assert!(!looks_like_item("Item Class: in a chat line without sections"));
        assert!(!looks_like_item("some text\n--------\nItem Class: Bows"));
    }

    #[test]
    fn curl_output() {
        let a = parse_output(&format!("{{\"id\":\"q\"}}{SPLIT}200 {{\"X-Rate-Limit-Ip\":[\"8:10:60\"],\"retry-after\":[\"5\"]}}")).unwrap();
        assert_eq!(a.status, 200);
        assert_eq!(a.body, "{\"id\":\"q\"}");
        assert_eq!(a.headers["x-rate-limit-ip"], "8:10:60");
        assert_eq!(a.headers["retry-after"], "5");
        // A body that holds the marker's start is cut at the last marker.
        let b = parse_output(&format!("a\nb{SPLIT}404 {{}}")).unwrap();
        assert_eq!((b.status, b.body.as_str()), (404, "a\nb"));
        assert!(parse_output("no marker").is_err());
    }

    #[test]
    fn curl_settings() {
        let c = curl_config("POST", "https://www.pathofexile.com/api/trade2/search/Standard", "{\"query\":{}}");
        assert!(c.contains("proto = \"=https\""));
        assert!(c.contains("data-binary = \"{\\\"query\\\":{}}\""));
        assert!(c.contains("Content-Type: application/json"));
        assert!(!c.contains("location"), "never follows a redirect to another host");
    }

    /// Under an X server with xclip: `xvfb-run cargo test --no-default-features
    /// copied_items_are_seen -- --ignored`.
    #[test]
    #[ignore]
    fn copied_items_are_seen() {
        use std::io::Write;
        use std::sync::mpsc;
        let (tx, rx) = mpsc::channel();
        watch_clipboard(|| true, move |t| tx.send(t).unwrap()).expect("watcher");
        std::thread::sleep(std::time::Duration::from_millis(200));
        let copy = |text: &str| {
            let mut c = std::process::Command::new("xclip")
                .args(["-selection", "clipboard", "-loops", "1"])
                .stdin(std::process::Stdio::piped())
                .spawn()
                .expect("xclip");
            c.stdin.take().unwrap().write_all(text.as_bytes()).unwrap();
            c
        };
        let mut chat = copy("just a chat line");
        std::thread::sleep(std::time::Duration::from_millis(500));
        let _ = chat.kill();
        let _ = chat.wait();
        let item = "Item Class: Bows\r\nRarity: Rare\r\nDire Nock\r\nRider Bow\r\n--------\r\nItem Level: 80\r\n";
        let mut item_copy = copy(item);
        let seen = rx.recv_timeout(std::time::Duration::from_secs(5)).expect("the item was not seen");
        assert!(seen.starts_with("Item Class: Bows\nRarity: Rare\n"), "{seen:?}");
        let _ = item_copy.kill();
        let _ = item_copy.wait();
        assert!(rx.try_recv().is_err(), "the chat line was taken for an item");
    }
}
