//! Aion 2 Timers (aion2timers.com, by HomelessGuyNABox): its field boss
//! feed for one server, read only, for the Schedule's maps the player has
//! not opened in the game (the person's yes, 2026-11-13: rare requests,
//! cached, credited as text). Only this one address is asked; nothing is
//! sent but the request.

use std::time::Duration;

/// The feed, before the server's name.
pub const FEED: &str = "https://www.aion2timers.com/api/fieldboss.php?action=feed&server=";

/// A server's name as the site writes it ("eu-marchutan"): lower case
/// letters, digits and dashes only.
pub fn slug_ok(slug: &str) -> bool {
    !slug.is_empty() && slug.len() <= 40 && slug.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// The feed of one server (JSON text, at most 1 MB).
pub fn feed(slug: &str) -> Result<String, String> {
    if !slug_ok(slug) {
        return Err("not a server name".into());
    }
    let url = format!("{FEED}{slug}");
    let config = format!(
        "fail\nsilent\nshow-error\nproto = \"=https\"\nmax-time = 30\nconnect-timeout = 10\nmax-filesize = 1048576\nuser-agent = \"GameCompanion (+https://github.com/xzero3007/game-companion)\"\nurl = {}\n",
        crate::streams::curl_quote(&url)
    );
    let bytes = crate::streams::curl_with(&["-q"], &config, Duration::from_secs(35)).map_err(|e| crate::market::plain(&e))?;
    let text = String::from_utf8(bytes).map_err(|_| "the answer is not text".to_string())?;
    match serde_json::from_str::<serde_json::Value>(&text) {
        Ok(v) if v["ok"].as_bool() == Some(true) && v["kills"].is_object() => Ok(text),
        _ => Err("the answer is not the feed".into()),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn only_plain_server_names() {
        assert!(super::slug_ok("eu-marchutan"));
        assert!(!super::slug_ok("eu-marchutan&x=1"));
        assert!(!super::slug_ok("../x"));
        assert!(!super::slug_ok(""));
        assert!(!super::slug_ok("EU"));
        assert!(super::feed("a b").is_err());
    }
}
