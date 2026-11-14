//! The AION 2 Market's downloads (the Clicktrough Market plugin's `a2.web`):
//! the market prices from Clicktrough's hourly copy on GitHub and from
//! aion2.exchange, and the game's item icons from NC's icon server, kept on
//! disk. Only these addresses, https only, nothing sent but the request
//! (the person's yes, 2026-11-13).

use std::path::PathBuf;
use std::time::Duration;

/// Clicktrough's hourly copy of the prices (the app repo's `market-data` branch).
pub const COPY: &str = "https://raw.githubusercontent.com/Xzero3007/A2Tools-DPS-Meter_Clicktrough/market-data/";
/// aion2.exchange's public API.
pub const API: &str = "https://aion2.exchange/api/";
/// The game's icons.
pub const ICONS: &str = "https://assets.playnccdn.com/static-aion2-gamedata/resources/";

/// Whether an address may be asked: the copy's files or aion2.exchange's
/// API, nothing else (no `..`, no user part, no other port).
pub fn allowed(url: &str) -> bool {
    let rest = if let Some(rest) = url.strip_prefix(COPY) {
        if rest.contains('?') {
            return false;
        }
        rest
    } else if let Some(rest) = url.strip_prefix(API) {
        rest
    } else {
        return false;
    };
    !rest.is_empty()
        && !rest.contains("..")
        && !rest.contains('#')
        && !rest.contains('\\')
        && rest.chars().all(|c| c.is_ascii_alphanumeric() || "/._-?=&".contains(c))
}

/// One answer as text (the Market's addresses or the Armory's): https, no redirect followed, no `~/.curlrc`, at most
/// 16 MB and 45 s.
pub fn get(url: &str) -> Result<String, String> {
    if !allowed(url) && !crate::armory::allowed(url) {
        return Err("not an allowed address".into());
    }
    let config = format!(
        "fail\nsilent\nshow-error\nproto = \"=https\"\nmax-time = 45\nconnect-timeout = 15\nmax-filesize = 16777216\nurl = {}\n",
        crate::streams::curl_quote(url)
    );
    let bytes = crate::streams::curl_with(&["-q"], &config, Duration::from_secs(50)).map_err(|e| plain(&e))?;
    String::from_utf8(bytes).map_err(|_| "the answer is not text".into())
}

/// curl's complaint in plain words.
pub(crate) fn plain(err: &str) -> String {
    let lower = err.to_lowercase();
    if let Some(at) = lower.find("returned error: ") {
        let code: String = lower[at + 16..].chars().take_while(char::is_ascii_digit).collect();
        return match code.as_str() {
            "503" | "502" | "504" => "the service is down right now".into(),
            "" => "it refused".into(),
            code => format!("it answered {code}"),
        };
    }
    if lower.contains("timed out") || lower.contains("timeout") {
        return "no answer in time".into();
    }
    if lower.contains("resolve") || lower.contains("connect") {
        return format!("could not connect: {}", err.trim_start_matches(|c: char| c == '(' || c.is_ascii_digit() || c == ')' || c == ' '));
    }
    err.to_string()
}

/// Whether an icon's name is one of the game's (`Icon_...` and such).
pub fn icon_name_ok(name: &str) -> bool {
    (1..=96).contains(&name.len()) && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Where the icons are kept: ~/.cache/game-companion/aion2/icons.
pub fn icon_dir() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    Some(base.join("game-companion").join("aion2").join("icons"))
}

/// The kept icon's file, if it is there.
pub fn icon_file(name: &str) -> Option<PathBuf> {
    if !icon_name_ok(name) {
        return None;
    }
    let path = icon_dir()?.join(format!("{name}.png"));
    path.is_file().then_some(path)
}

/// Downloads an icon once and keeps it: a PNG of at most 1 MB.
pub fn fetch_icon(name: &str) -> Result<PathBuf, String> {
    if !icon_name_ok(name) {
        return Err("not an icon name".into());
    }
    let dir = icon_dir().ok_or("no cache folder")?;
    let url = format!("{ICONS}{name}.png");
    let config = format!(
        "fail\nsilent\nshow-error\nproto = \"=https\"\nmax-time = 20\nconnect-timeout = 10\nmax-filesize = 1048576\nurl = {}\n",
        crate::streams::curl_quote(&url)
    );
    let bytes = crate::streams::curl_with(&["-q"], &config, Duration::from_secs(25))?;
    if !is_png(&bytes) {
        return Err("not a picture".into());
    }
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(format!("{name}.png"));
    let tmp = dir.join(format!("{name}.png.tmp"));
    std::fs::write(&tmp, &bytes).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
    Ok(path)
}

fn is_png(bytes: &[u8]) -> bool {
    bytes.len() <= 1 << 20 && bytes.starts_with(b"\x89PNG\r\n\x1a\n")
}

/// A module's own file beside settings.json (`aion2-<key>.json`): its
/// choices, the last prices. Keys are short and plain.
pub fn store_file(key: &str) -> Option<PathBuf> {
    let ok = (1..=64).contains(&key.len()) && key.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    if !ok {
        return None;
    }
    // LOOT keeps many small files (a day each, per character): in the
    // module's data folder, not beside settings.json.
    if let Some(rest) = key.strip_prefix("loot-") {
        let dir = aion2::history::default_dir().parent()?.join("loot");
        std::fs::create_dir_all(&dir).ok()?;
        return Some(dir.join(format!("{rest}.json")));
    }
    crate::settings::Settings::path().map(|p| p.with_file_name(format!("aion2-{key}.json")))
}

/// What is kept under a key, JSON ("" for nothing).
pub fn load(key: &str) -> String {
    store_file(key)
        .and_then(|p| std::fs::read_to_string(p).ok())
        .filter(|t| serde_json::from_str::<serde_json::Value>(t).is_ok())
        .unwrap_or_default()
}

/// Keeps JSON under a key (at most 4 MB), written whole or not at all.
pub fn keep(key: &str, json: &str) -> bool {
    if json.len() > 4 << 20 || serde_json::from_str::<serde_json::Value>(json).is_err() {
        return false;
    }
    let Some(path) = store_file(key) else { return false };
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, json).is_ok() && std::fs::rename(&tmp, &path).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_copy_and_aion2_exchange() {
        assert!(allowed(&format!("{COPY}servers.json")));
        assert!(allowed(&format!("{COPY}prices/12305.json")));
        assert!(allowed(&format!("{API}items?server=12305&limit=1000&offset=0")));
        assert!(allowed(&format!("{API}servers")));
        assert!(!allowed(&format!("{COPY}../main/x.json")));
        assert!(!allowed(&format!("{COPY}a.json?x=1")));
        assert!(!allowed("https://raw.githubusercontent.com/someone/else/market-data/servers.json"));
        assert!(!allowed("http://aion2.exchange/api/servers"));
        assert!(!allowed("https://aion2.exchange.evil.net/api/servers"));
        assert!(!allowed("https://aion2.exchange/api/"));
        assert!(!allowed("https://aion2.exchange/apix"));
        assert!(!allowed(&format!("{API}servers#x")));
        assert!(!allowed(&format!("{API}a b")));
    }

    #[test]
    fn curl_complaints_in_plain_words() {
        assert_eq!(plain("(22) The requested URL returned error: 503"), "the service is down right now");
        assert_eq!(plain("(22) The requested URL returned error: 403"), "it answered 403");
        assert_eq!(plain("(28) Operation timed out after 45000 milliseconds"), "no answer in time");
        assert_eq!(plain("(6) Could not resolve host: aion2.exchange"), "could not connect: Could not resolve host: aion2.exchange");
    }

    #[test]
    fn icon_names_are_plain() {
        assert!(icon_name_ok("Icon_Item_Ore_01"));
        assert!(!icon_name_ok(""));
        assert!(!icon_name_ok("../x"));
        assert!(!icon_name_ok("a/b"));
        assert!(!icon_name_ok(&"a".repeat(97)));
        assert!(is_png(b"\x89PNG\r\n\x1a\nrest"));
        assert!(!is_png(b"<html>"));
    }

    #[test]
    fn store_keys_are_plain() {
        assert!(store_file("market").is_some() || crate::settings::Settings::path().is_none());
        assert!(store_file("../x").is_none());
        assert!(store_file("Market").is_none());
        assert!(store_file("").is_none());
    }
}
