//! Missing game covers, downloaded once from the stores' image servers
//! (the person agreed, 2026-11-13): Steam's, Epic's and GOG's, nothing
//! else. Only the game's number or id in the picture address leaves the
//! computer; no account, no library list, no Steam Web API. Each cover is
//! kept under `~/.cache/game-companion/covers/<launcher>-<id>.<ext>` and
//! never asked for again; a cover that could not be had is remembered in
//! `failed.json` and asked for again at most once a week. One request at a
//! time, on a worker thread, through curl (`-q`, https only, no redirects,
//! 5 MB at most, 20 s at most); only JPEG, PNG and WebP are kept.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::games::Game;

/// The image servers a cover may come from, exactly (no wildcards).
pub const ALLOWED_HOSTS: &[&str] = &[
    // Steam's store pictures.
    "shared.akamai.steamstatic.com",
    "cdn.akamai.steamstatic.com",
    "cdn.cloudflare.steamstatic.com",
    "steamcdn-a.akamaihd.net",
    // Epic's key images (Heroic's legendary_library.json art addresses).
    "cdn1.epicgames.com",
    "cdn1.unrealengine.com",
    "cdn2.unrealengine.com",
    // GOG's pictures (Heroic's gog_library.json; GOG's API names the
    // numbered servers too).
    "images.gog-statics.com",
    "images-1.gog-statics.com",
    "images-2.gog-statics.com",
    "images-3.gog-statics.com",
    "images-4.gog-statics.com",
    "images.gog.com",
];

/// The largest cover kept.
pub const MAX_BYTES: usize = 5 * 1024 * 1024;

/// How long a cover that could not be had is left alone.
pub const RETRY_AFTER: u64 = 7 * 24 * 3600;

/// The address's host when it is an https address on an allowed image
/// server (no user, no port, nothing odd in it); None otherwise.
pub fn allowed_host(url: &str) -> Option<&'static str> {
    let rest = url.strip_prefix("https://")?;
    if url.len() > 600 || url.chars().any(|c| c.is_whitespace() || c.is_control() || c == '"' || c == '\\') {
        return None;
    }
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let host = &rest[..end];
    if host.contains(['@', ':']) || !rest[end..].starts_with('/') {
        return None;
    }
    ALLOWED_HOSTS.iter().copied().find(|h| h.eq_ignore_ascii_case(host))
}

/// The addresses to try for a game's cover, best first; empty when it has
/// none on an allowed server. Steam: the tall library picture (and its
/// double size, and the older path on another server), then the wide
/// header. Heroic: its own art address (Epic's resized square first, as
/// Heroic's card asks for it).
pub fn candidates(game: &Game) -> Vec<String> {
    let mut list = Vec::new();
    if game.launcher == "steam" {
        if let Some(id) = game.steam_appid {
            let shared = format!("https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{id}");
            list.push(format!("{shared}/library_600x900.jpg"));
            list.push(format!("{shared}/library_600x900_2x.jpg"));
            list.push(format!("https://cdn.cloudflare.steamstatic.com/steam/apps/{id}/library_600x900.jpg"));
            list.push(format!("{shared}/header.jpg"));
        }
    } else if game.launcher == "heroic" {
        if let Some(url) = &game.cover_url {
            if game.id.starts_with("heroic:legendary:") && !url.contains('?') {
                list.push(format!("{url}?h=400&resize=1&w=300"));
            }
            list.push(url.clone());
        }
    }
    list.retain(|u| allowed_host(u).is_some());
    list
}

/// The picture's kind by its first bytes: "jpg", "png" or "webp".
pub fn image_kind(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("jpg")
    } else if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("png")
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("webp")
    } else {
        None
    }
}

/// The folder the covers live in.
pub fn dir() -> PathBuf {
    crate::updater::cache_dir().join("covers")
}

/// A game's file name without extension: its id with ':' as '-', anything
/// but letters, digits, '.', '_' and '-' as '_' ("steam:10" → "steam-10").
pub fn base_name(id: &str) -> String {
    let name: String = id
        .chars()
        .map(|c| match c {
            ':' => '-',
            c if c.is_ascii_alphanumeric() || c == '_' || c == '-' => c,
            '.' => '.',
            _ => '_',
        })
        .take(120)
        .collect();
    // Never a hidden file or a step up.
    name.trim_start_matches('.').to_string()
}

/// A cover already downloaded for the game.
pub fn cached(dir: &Path, id: &str) -> Option<PathBuf> {
    let base = base_name(id);
    if base.is_empty() {
        return None;
    }
    ["jpg", "png", "webp"].iter().map(|ext| dir.join(format!("{base}.{ext}"))).find(|p| p.is_file())
}

/// Gives games without a picture their downloaded cover.
pub fn fill_cached(games: &mut [Game], dir: &Path) {
    for game in games.iter_mut().filter(|g| g.picture.is_none()) {
        game.picture = cached(dir, &game.id);
    }
}

/// When each cover was last asked for in vain (unix seconds), by game id.
fn failed_file(dir: &Path) -> PathBuf {
    dir.join("failed.json")
}

pub fn read_failed(dir: &Path) -> BTreeMap<String, u64> {
    std::fs::read(failed_file(dir)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("part");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(&tmp, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&tmp);
    })
}

/// Whether a cover that failed at `failed` may be asked for again `now`.
pub fn may_retry(failed: Option<u64>, now: u64) -> bool {
    failed.is_none_or(|t| now.saturating_sub(t) >= RETRY_AFTER || t > now)
}

/// One answer from the image server.
#[derive(Debug, Clone, PartialEq)]
pub enum Fetched {
    /// Status 200 and the body.
    Body(Vec<u8>),
    /// Another status (a redirect included: it is not followed).
    Status(u16),
    /// Refused here (too large, not https, ...): try the next address.
    Refused(String),
    /// No connection or no answer in time: try again another day, and
    /// stop for now.
    Offline(String),
}

/// What became of one game's cover.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    Saved(PathBuf),
    /// Already there, failed this week, or no address to ask.
    Skipped,
    /// None of its addresses gave a picture (remembered for a week).
    Failed,
    /// No connection: nothing remembered, the rest left for later.
    Offline,
}

/// Gets one game's cover through `fetch` (curl in the app, made-up answers
/// in tests) and stores it.
pub fn download(game: &Game, dir: &Path, now: u64, fetch: &dyn Fn(&str) -> Fetched) -> Outcome {
    if cached(dir, &game.id).is_some() {
        return Outcome::Skipped;
    }
    let urls = candidates(game);
    let failed = read_failed(dir);
    if urls.is_empty() || !may_retry(failed.get(&game.id).copied(), now) {
        return Outcome::Skipped;
    }
    if std::fs::create_dir_all(dir).is_err() {
        return Outcome::Offline;
    }
    for url in &urls {
        // Checked once more right before asking.
        if allowed_host(url).is_none() {
            continue;
        }
        match fetch(url) {
            Fetched::Body(bytes) if bytes.len() <= MAX_BYTES => {
                let Some(ext) = image_kind(&bytes) else { continue };
                let path = dir.join(format!("{}.{ext}", base_name(&game.id)));
                if write_atomic(&path, &bytes).is_ok() {
                    forget_failure(dir, &game.id);
                    return Outcome::Saved(path);
                }
                return Outcome::Offline;
            }
            Fetched::Offline(_) => return Outcome::Offline,
            Fetched::Body(_) | Fetched::Status(_) | Fetched::Refused(_) => {}
        }
    }
    remember_failure(dir, &game.id, now);
    Outcome::Failed
}

fn remember_failure(dir: &Path, id: &str, now: u64) {
    let mut failed = read_failed(dir);
    failed.insert(id.to_string(), now);
    if let Ok(text) = serde_json::to_vec(&failed) {
        let _ = write_atomic(&failed_file(dir), &text);
    }
}

fn forget_failure(dir: &Path, id: &str) {
    let mut failed = read_failed(dir);
    if failed.remove(id).is_some() {
        if let Ok(text) = serde_json::to_vec(&failed) {
            let _ = write_atomic(&failed_file(dir), &text);
        }
    }
}

/// curl's settings for one cover: https only, no redirect followed, no
/// `~/.curlrc` (`-q` comes first on the command line), size and time
/// capped; the status code after the body.
fn curl_config(url: &str) -> String {
    format!(
        "silent\nshow-error\nproto = \"=https\"\nmax-time = 20\nconnect-timeout = 10\nmax-filesize = {MAX_BYTES}\nwrite-out = \"\\n%{{http_code}}\"\nurl = {}\n",
        crate::streams::curl_quote(url)
    )
}

/// Splits curl's output into the body and the status code after it.
fn split_status(out: &[u8]) -> Option<(&[u8], u16)> {
    let at = out.iter().rposition(|&b| b == b'\n')?;
    let code = std::str::from_utf8(&out[at + 1..]).ok()?.trim().parse().ok()?;
    Some((&out[..at], code))
}

/// One cover through the user's curl.
pub fn fetch_with_curl(url: &str) -> Fetched {
    use std::io::Write;
    use std::process::{Command, Stdio};
    if allowed_host(url).is_none() {
        return Fetched::Refused("not an allowed image server".into());
    }
    let child = Command::new("curl")
        .args(["-q", "--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    let Ok(mut child) = child else { return Fetched::Offline("curl did not start".into()) };
    if let Some(mut stdin) = child.stdin.take() {
        if stdin.write_all(curl_config(url).as_bytes()).is_err() {
            return Fetched::Offline("curl took no settings".into());
        }
    }
    let out = match crate::streams::finish(child, Duration::from_secs(30)) {
        Ok(out) => out,
        Err(e) => return Fetched::Offline(e),
    };
    match out.status.code() {
        Some(0) => {}
        // 63: larger than allowed; 1: a protocol it may not use.
        Some(63) | Some(1) => return Fetched::Refused(format!("curl exit {:?}", out.status.code())),
        _ => return Fetched::Offline(String::from_utf8_lossy(&out.stderr).trim().chars().take(200).collect()),
    }
    match split_status(&out.stdout) {
        Some((body, 200)) if body.len() <= MAX_BYTES => Fetched::Body(body.to_vec()),
        Some((_, 200)) => Fetched::Refused("too large".into()),
        Some((_, code)) => Fetched::Status(code),
        None => Fetched::Refused("no status".into()),
    }
}

/// Whether downloads may happen at all: not in demo modes, not with
/// `GC_NO_COVER_DOWNLOADS=1`, and only when the setting is on.
pub fn allowed_now(setting: bool) -> bool {
    setting && std::env::var_os("GC_DEMO").is_none() && std::env::var("GC_NO_COVER_DOWNLOADS").map_or(true, |v| v.is_empty() || v == "0")
}

/// The gap between two requests.
pub const GAP: Duration = Duration::from_millis(250);

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-covers-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn steam(appid: u32) -> Game {
        let mut g = Game::new(format!("steam:{appid}"), "S", "steam", "");
        g.steam_appid = Some(appid);
        g
    }

    const JPEG: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, b'J', b'F', b'I', b'F'];

    #[test]
    fn only_exact_allowed_https_hosts() {
        assert_eq!(allowed_host("https://cdn1.epicgames.com/offer/x/y.jpg"), Some("cdn1.epicgames.com"));
        assert!(allowed_host("https://images.gog-statics.com/abc.jpg").is_some());
        assert!(allowed_host("https://images-2.gog-statics.com/abc_glx_master_256.jpg").is_some());
        assert!(allowed_host("https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1/header.jpg").is_some());
        assert!(allowed_host("https://SHARED.akamai.steamstatic.com/x").is_some());
        // Not https, other hosts, look-alikes, users, ports, odd text.
        for bad in [
            "http://cdn1.epicgames.com/x.jpg",
            "ftp://cdn1.epicgames.com/x.jpg",
            "https://m.media-amazon.com/images/x.jpg",
            "https://evil.cdn1.epicgames.com/x.jpg",
            "https://cdn1.epicgames.com.evil.net/x.jpg",
            "https://user@cdn1.epicgames.com/x.jpg",
            "https://cdn1.epicgames.com:8443/x.jpg",
            "https://cdn1.epicgames.com",
            "https://cdn1.epicgames.com?x=1",
            "https://cdn1.epicgames.com/x y.jpg",
            "https://cdn1.epicgames.com/x\".jpg",
            "file:///home/p/cover.jpg",
        ] {
            assert_eq!(allowed_host(bad), None, "{bad}");
        }
    }

    #[test]
    fn candidates_per_launcher() {
        let urls = candidates(&steam(2694490));
        assert_eq!(urls[0], "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2694490/library_600x900.jpg");
        assert!(urls.last().unwrap().ends_with("/2694490/header.jpg"));
        assert_eq!(urls.len(), 4);
        let mut epic = Game::new("heroic:legendary:Fort", "F", "heroic", "");
        epic.cover_url = Some("https://cdn1.epicgames.com/item/fort_tall.jpg".into());
        assert_eq!(
            candidates(&epic),
            ["https://cdn1.epicgames.com/item/fort_tall.jpg?h=400&resize=1&w=300", "https://cdn1.epicgames.com/item/fort_tall.jpg"]
        );
        let mut amazon = Game::new("heroic:nile:a", "A", "heroic", "");
        amazon.cover_url = Some("https://m.media-amazon.com/images/a.jpg".into());
        assert!(candidates(&amazon).is_empty());
        let mut own = Game::new("own:1", "O", "own", "");
        own.steam_appid = Some(5);
        assert!(candidates(&own).is_empty());
        let mut lutris = Game::new("lutris:x", "L", "lutris", "");
        lutris.cover_url = Some("https://images.gog-statics.com/a.jpg".into());
        assert!(candidates(&lutris).is_empty());
    }

    #[test]
    fn cache_names() {
        assert_eq!(base_name("steam:2694490"), "steam-2694490");
        assert_eq!(base_name("heroic:legendary:Fortnite"), "heroic-legendary-Fortnite");
        assert_eq!(base_name("heroic:gog:../../x y"), "heroic-gog-.._.._x_y");
        assert_eq!(base_name("../x"), "_x");
        assert!(!base_name("a/b").contains('/'));
        let dir = temp("names");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("steam-10.webp"), b"x").unwrap();
        assert_eq!(cached(&dir, "steam:10"), Some(dir.join("steam-10.webp")));
        assert_eq!(cached(&dir, "steam:11"), None);
        let mut games = vec![steam(10), steam(11)];
        fill_cached(&mut games, &dir);
        assert_eq!(games[0].picture, Some(dir.join("steam-10.webp")));
        assert_eq!(games[1].picture, None);
    }

    #[test]
    fn magic_bytes() {
        assert_eq!(image_kind(JPEG), Some("jpg"));
        assert_eq!(image_kind(b"\x89PNG\r\n\x1a\n...."), Some("png"));
        assert_eq!(image_kind(b"RIFF\x10\0\0\0WEBPVP8 "), Some("webp"));
        assert_eq!(image_kind(b"<html>not found</html>"), None);
        assert_eq!(image_kind(b"RIFF\x10\0\0\0WAVE"), None);
        assert_eq!(image_kind(b""), None);
    }

    #[test]
    fn retry_once_a_week() {
        let now = 10_000_000;
        assert!(may_retry(None, now));
        assert!(!may_retry(Some(now - 3600), now));
        assert!(!may_retry(Some(now - RETRY_AFTER + 1), now));
        assert!(may_retry(Some(now - RETRY_AFTER), now));
        // A clock that went back does not lock it out.
        assert!(may_retry(Some(now + 100), now));
    }

    #[test]
    fn downloads_through_fallbacks_and_remembers_failures() {
        let dir = temp("download");
        let asked = RefCell::new(Vec::new());
        // The tall picture is missing, its double size is an HTML page, the
        // other server redirects: the header is taken.
        let fetch = |url: &str| {
            asked.borrow_mut().push(url.to_string());
            if url.contains("library_600x900.jpg") && url.contains("shared") {
                Fetched::Status(404)
            } else if url.contains("_2x") {
                Fetched::Body(b"<html></html>".to_vec())
            } else if url.contains("cloudflare") {
                Fetched::Status(302)
            } else {
                Fetched::Body(JPEG.to_vec())
            }
        };
        let now = 1_000_000;
        let out = download(&steam(7), &dir, now, &fetch);
        assert_eq!(out, Outcome::Saved(dir.join("steam-7.jpg")));
        assert_eq!(asked.borrow().len(), 4);
        assert_eq!(std::fs::read(dir.join("steam-7.jpg")).unwrap(), JPEG);
        assert!(!dir.join("steam-7.part").exists());
        // There: never asked again.
        assert_eq!(download(&steam(7), &dir, now, &fetch), Outcome::Skipped);
        assert_eq!(asked.borrow().len(), 4);

        // Nothing anywhere: remembered, left alone for a week.
        let none = |_: &str| Fetched::Status(404);
        assert_eq!(download(&steam(8), &dir, now, &none), Outcome::Failed);
        assert_eq!(read_failed(&dir).get("steam:8"), Some(&now));
        let counted = RefCell::new(0);
        let count = |_: &str| {
            *counted.borrow_mut() += 1;
            Fetched::Body(JPEG.to_vec())
        };
        assert_eq!(download(&steam(8), &dir, now + 3600, &count), Outcome::Skipped);
        assert_eq!(*counted.borrow(), 0);
        assert!(matches!(download(&steam(8), &dir, now + RETRY_AFTER, &count), Outcome::Saved(_)));
        assert!(!read_failed(&dir).contains_key("steam:8"));

        // Too large: refused; offline: nothing remembered.
        let big = |_: &str| Fetched::Body([JPEG, &vec![0u8; MAX_BYTES]].concat());
        assert_eq!(download(&steam(9), &dir, now, &big), Outcome::Failed);
        let offline = |_: &str| Fetched::Offline("no route".into());
        assert_eq!(download(&steam(12), &dir, now, &offline), Outcome::Offline);
        assert!(!read_failed(&dir).contains_key("steam:12"));

        // A cover address on another server is never asked for.
        let mut other = Game::new("heroic:nile:a", "A", "heroic", "");
        other.cover_url = Some("https://example.com/a.jpg".into());
        let never = |u: &str| panic!("asked {u}");
        assert_eq!(download(&other, &dir, now, &never), Outcome::Skipped);
    }

    #[test]
    fn curl_settings_follow_no_redirect() {
        let config = curl_config("https://cdn1.epicgames.com/a.jpg");
        assert!(!config.contains("location"));
        assert!(config.contains("proto = \"=https\""));
        assert!(config.contains("max-filesize = 5242880"));
        assert!(config.contains("max-time = 20"));
        assert!(config.contains("url = \"https://cdn1.epicgames.com/a.jpg\""));
        assert_eq!(split_status(b"\xff\xd8\n\xff\n200"), Some((&b"\xff\xd8\n\xff"[..], 200)));
        assert_eq!(split_status(b"\n301"), Some((&b""[..], 301)));
        assert_eq!(split_status(b"garbage"), None);
        // Not even curl is started for another host or plain http.
        assert!(matches!(fetch_with_curl("http://cdn1.epicgames.com/a.jpg"), Fetched::Refused(_)));
        assert!(matches!(fetch_with_curl("https://example.com/a.jpg"), Fetched::Refused(_)));
    }
}
