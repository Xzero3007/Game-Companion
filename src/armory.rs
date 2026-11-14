//! The AION 2 Armory's downloads: NC's official character pages (the AION 2
//! site's character info and its character search), read only, no account,
//! nothing sent but the lookup itself (a name, or a server and a character's
//! id). The person's yes, 2026-11-13. Pictures: the game's icons go through
//! the Market's icon cache, NC's portraits through `PictureNetwork`.

/// The character pages' API (info, equipment, an item, a Daevanion board).
pub const SITE: &str = "https://aion2.plaync.com/api/character/";
/// NC's character search.
pub const SEARCH: &str = "https://api-search.plaync.com/aion2global/search/v2/character?";

/// Whether an address may be asked: one of the character pages or the
/// search, with a plain query (no `..`, no fragment, no other host or port).
pub fn allowed(url: &str) -> bool {
    let rest = if let Some(rest) = url.strip_prefix(SITE) {
        let path = rest.split('?').next().unwrap_or("");
        if !["info", "equipment", "equipment/item", "daevanion/detail"].contains(&path) {
            return false;
        }
        rest
    } else if let Some(rest) = url.strip_prefix(SEARCH) {
        rest
    } else {
        return false;
    };
    rest.contains('?') == url.starts_with(SITE)
        && !rest.contains("..")
        && !rest.contains('#')
        && !rest.contains('\\')
        && rest.chars().all(|c| c.is_ascii_alphanumeric() || "/._-?=&%+".contains(c))
}

/// The Downloads folder: XDG's (user-dirs.dirs) else ~/Downloads.
fn downloads() -> Option<std::path::PathBuf> {
    let home = std::path::PathBuf::from(std::env::var_os("HOME")?);
    let config = std::env::var_os("XDG_CONFIG_HOME").map(std::path::PathBuf::from).unwrap_or_else(|| home.join(".config"));
    if let Ok(text) = std::fs::read_to_string(config.join("user-dirs.dirs")) {
        for line in text.lines() {
            if let Some(v) = line.trim().strip_prefix("XDG_DOWNLOAD_DIR=") {
                let v = v.trim_matches('"').replace("$HOME", &home.to_string_lossy());
                let p = std::path::PathBuf::from(v);
                if p.is_absolute() {
                    return Some(p);
                }
            }
        }
    }
    Some(home.join("Downloads"))
}

/// A bookmark file's name: armory-<letters, digits, -_.>.json.
fn bookmark_name_ok(name: &str) -> bool {
    name.len() <= 128
        && name.starts_with("armory-")
        && name.ends_with(".json")
        && name.chars().all(|c| c.is_ascii_alphanumeric() || "-_.() ".contains(c))
        && !name.contains("..")
}

/// The Armory bookmark's files in Downloads, the newest first:
/// [{name, at (ms), size}].
pub fn bookmark_files() -> serde_json::Value {
    let mut out: Vec<(u128, serde_json::Value)> = Vec::new();
    if let Some(entries) = downloads().and_then(|d| std::fs::read_dir(d).ok()) {
        for e in entries.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            let Ok(meta) = e.metadata() else { continue };
            if !bookmark_name_ok(&name) || !meta.is_file() {
                continue;
            }
            let at = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_millis()).unwrap_or(0);
            out.push((at, serde_json::json!({ "name": name, "at": at as u64, "size": meta.len() })));
        }
    }
    out.sort_by_key(|b| std::cmp::Reverse(b.0));
    serde_json::Value::Array(out.into_iter().take(20).map(|x| x.1).collect())
}

/// One bookmark file's text, by its name in Downloads (at most 8 MB).
pub fn bookmark_file(name: &str) -> Option<String> {
    if !bookmark_name_ok(name) {
        return None;
    }
    let path = downloads()?.join(name);
    if std::fs::metadata(&path).ok()?.len() > 8 << 20 {
        return None;
    }
    std::fs::read_to_string(path).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_character_pages_and_the_search() {
        assert!(allowed(&format!("{SITE}info?lang=en-US&region=eu&serverId=2305&characterId=abc%3D")));
        assert!(allowed(&format!("{SITE}equipment/item?lang=en-US&id=1&enchantLevel=3&slotPos=1")));
        assert!(allowed(&format!("{SITE}daevanion/detail?boardId=3")));
        assert!(allowed(&format!("{SEARCH}keyword=Some+Name&page=1&size=40&region=eu&localeInfo=en-US")));
        assert!(!allowed(&format!("{SITE}info")));
        assert!(!allowed(&format!("{SITE}other?x=1")));
        assert!(!allowed(&format!("{SITE}../account?x=1")));
        assert!(!allowed(&format!("{SITE}info?x=1#y")));
        assert!(!allowed("https://aion2.plaync.com.evil.net/api/character/info?x=1"));
        assert!(!allowed("http://aion2.plaync.com/api/character/info?x=1"));
        assert!(!allowed("https://api-search.plaync.com/aion2global/search/v2/other?x=1"));
        assert!(!allowed(&format!("{SEARCH}a b")));
    }

    #[test]
    fn bookmark_files_by_name_only() {
        assert!(bookmark_name_ok("armory-some-char.json"));
        assert!(bookmark_name_ok("armory-x (1).json"));
        assert!(!bookmark_name_ok("armory-../x.json"));
        assert!(!bookmark_name_ok("other.json"));
        assert!(!bookmark_name_ok("armory-x.html"));
        assert!(!bookmark_name_ok("armory-a/b.json"));
    }
}
