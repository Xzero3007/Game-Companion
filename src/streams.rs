//! Twitch and YouTube for the Streams panel, moved over from the Clicktrough
//! meter's Streams plugin (meter patches 0047, 0059 to 0061, 0068) with the
//! same reach: Twitch's public API (fixed queries, the client id its own web
//! page uses; the user's twitch.tv token only for the followed channels, to
//! Twitch alone), YouTube's channel feeds, YouTube's search through the
//! user's yt-dlp, FreeTube's subscriptions file (read only), and Twitch
//! through the user's Streamlink. Requests go through the user's curl.

use std::io::{BufRead, BufReader, Write};
use std::os::fd::IntoRawFd;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const TWITCH_GQL: &str = "https://gql.twitch.tv/gql";
/// The client id Twitch's own web page uses, as other players do.
const TWITCH_CLIENT_ID: &str = "kimne78kx3ncx6brgo4mv6wki5h1ko";
const USER: &str = "id login displayName profileImageURL(width: 70) \
    stream { title viewersCount createdAt previewImageURL(width: 320, height: 180) game { displayName } }";
const STREAM: &str = "title viewersCount createdAt previewImageURL(width: 320, height: 180) game { displayName } \
    broadcaster { login displayName profileImageURL(width: 70) }";

pub fn valid_login(login: &str) -> bool {
    !login.is_empty() && login.len() <= 25 && login.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

pub fn valid_video_id(id: &str) -> bool {
    id.len() == 11 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// A YouTube channel id: `UC` and 22 more.
pub fn valid_channel_id(id: &str) -> bool {
    id.len() == 24 && id.starts_with("UC") && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// The address mpv plays: a Twitch channel's page or a YouTube video's.
pub fn stream_url(kind: &str, id: &str) -> Result<String, String> {
    match kind {
        "twitch" if valid_login(id) => Ok(format!("https://www.twitch.tv/{}", id.to_ascii_lowercase())),
        "youtube" if valid_video_id(id) => Ok(format!("https://www.youtube.com/watch?v={id}")),
        "twitch" | "youtube" => Err("not a channel or video".into()),
        _ => Err("only Twitch and YouTube play here".into()),
    }
}

/// yt-dlp's format for a quality: the best up to that height, or sound only.
pub fn ytdl_format(quality: &str) -> String {
    match quality {
        "audio" => "bestaudio/best".to_string(),
        q => match q.parse::<u32>() {
            Ok(h) if (144..=2160).contains(&h) => format!("bestvideo[height<=?{h}]+bestaudio/best[height<=?{h}]/best"),
            _ => "bestvideo[height<=?1080]+bestaudio/best".to_string(),
        },
    }
}

/// A YouTube video id out of what was pasted into the search (a link or the
/// id itself).
pub fn video_id_of(text: &str) -> Option<String> {
    let t = text.trim();
    if valid_video_id(t) {
        return Some(t.to_string());
    }
    let rest = t.strip_prefix("https://").or_else(|| t.strip_prefix("http://"))?;
    let rest = rest.strip_prefix("www.").or_else(|| rest.strip_prefix("m.")).unwrap_or(rest);
    let id = if let Some(r) = rest.strip_prefix("youtu.be/") {
        r.split(['?', '&', '#', '/']).next()?
    } else {
        let r = rest.strip_prefix("youtube.com/")?;
        match r.strip_prefix("watch?") {
            Some(q) => q.split('&').find_map(|p| p.strip_prefix("v="))?,
            None => r.strip_prefix("shorts/").or_else(|| r.strip_prefix("live/"))?.split(['?', '&', '#', '/']).next()?,
        }
    };
    valid_video_id(id).then(|| id.to_string())
}

/// Twitch's query for a list.
pub fn twitch_query(kind: &str, arg: &Value) -> Result<Value, String> {
    match kind {
        "search" => {
            let text = arg.as_str().map(str::trim).filter(|t| !t.is_empty() && t.len() <= 100).ok_or("no search words")?;
            Ok(json!({
                "query": format!("query($q: String!) {{ searchFor(userQuery: $q, platform: \"web\") {{ channels {{ items {{ {USER} }} }} }} }}"),
                "variables": { "q": text },
            }))
        }
        "user" => {
            let login = arg.as_str().map(str::trim).filter(|l| valid_login(l)).ok_or("not a channel name")?;
            Ok(json!({
                "query": format!("query($l: String!) {{ user(login: $l) {{ {USER} }} }}"),
                "variables": { "l": login.to_ascii_lowercase() },
            }))
        }
        "channels" => {
            let logins: Vec<String> = arg
                .as_array()
                .ok_or("no channels")?
                .iter()
                .filter_map(Value::as_str)
                .filter(|l| valid_login(l))
                .map(str::to_ascii_lowercase)
                .take(100)
                .collect();
            Ok(json!({
                "query": format!("query($l: [String!]) {{ users(logins: $l) {{ {USER} }} }}"),
                "variables": { "l": logins },
            }))
        }
        "live" => match arg.as_str().map(str::trim).filter(|g| !g.is_empty()) {
            Some(game) if game.len() <= 100 => Ok(json!({
                "query": format!("query($g: String!) {{ game(name: $g) {{ streams(first: 30) {{ edges {{ node {{ {STREAM} }} }} }} }} }}"),
                "variables": { "g": game },
            })),
            Some(_) => Err("not a game".into()),
            None => Ok(json!({ "query": format!("query {{ streams(first: 30) {{ edges {{ node {{ {STREAM} }} }} }} }}") })),
        },
        // The signed-in user's followed channels that are live (only
        // `sort: RELEVANCE` answers).
        "followedLive" => Ok(json!({
            "query": format!("query {{ currentUser {{ followedLiveUsers(first: 100, sort: RELEVANCE) {{ edges {{ node {{ {USER} }} }} }} }} }}"),
        })),
        _ => Err("unknown Twitch query".into()),
    }
}

/// One channel or stream of Twitch's answer, as the panel lists it.
fn twitch_card(user: &Value, stream: Option<&Value>) -> Option<Value> {
    let login = user.get("login")?.as_str()?;
    let stream = stream.filter(|s| s.is_object());
    let s = |k: &str| stream.and_then(|s| s.get(k));
    Some(json!({
        "login": login,
        "name": user.get("displayName").and_then(Value::as_str).unwrap_or(login),
        "avatar": user.get("profileImageURL").and_then(Value::as_str).unwrap_or(""),
        "live": stream.is_some(),
        "title": s("title").and_then(Value::as_str).unwrap_or(""),
        "viewers": s("viewersCount").and_then(Value::as_u64).unwrap_or(0),
        "since": s("createdAt").and_then(Value::as_str).unwrap_or(""),
        "picture": s("previewImageURL").and_then(Value::as_str).unwrap_or(""),
        "game": s("game").and_then(|g| g.get("displayName")).and_then(Value::as_str).unwrap_or(""),
    }))
}

/// Twitch's answer (`data`) as cards: live ones first, by viewers.
pub fn twitch_cards(data: &Value) -> Vec<Value> {
    let mut cards: Vec<Value> = Vec::new();
    let mut users: Vec<&Value> = Vec::new();
    if let Some(edges) = data.pointer("/game/streams/edges").or_else(|| data.pointer("/streams/edges")).and_then(Value::as_array) {
        for node in edges.iter().filter_map(|e| e.get("node")) {
            if let Some(card) = node.get("broadcaster").and_then(|b| twitch_card(b, Some(node))) {
                cards.push(card);
            }
        }
    }
    if let Some(items) = data.pointer("/searchFor/channels/items").and_then(Value::as_array) {
        users.extend(items);
    }
    if let Some(list) = data.get("users").and_then(Value::as_array) {
        users.extend(list);
    }
    if let Some(user) = data.get("user").filter(|u| u.is_object()) {
        users.push(user);
    }
    if let Some(edges) = data.pointer("/currentUser/followedLiveUsers/edges").and_then(Value::as_array) {
        users.extend(edges.iter().filter_map(|e| e.get("node")));
    }
    for user in users {
        if let Some(card) = twitch_card(user, user.get("stream")) {
            if !cards.iter().any(|c| c["login"] == card["login"]) {
                cards.push(card);
            }
        }
    }
    cards.sort_by(|a, b| {
        b["live"].as_bool().cmp(&a["live"].as_bool()).then(b["viewers"].as_u64().cmp(&a["viewers"].as_u64()))
    });
    cards
}

/// yt-dlp's search answer, cut to what a list shows.
pub fn search_entries(all: &Value) -> Vec<Value> {
    let entries = all.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
    entries
        .iter()
        .filter_map(|e| {
            let id = e.get("id")?.as_str()?;
            if !valid_video_id(id) {
                return None;
            }
            Some(json!({
                "id": id,
                "title": e.get("title").and_then(Value::as_str).unwrap_or(""),
                "channel": e.get("channel").or_else(|| e.get("uploader")).and_then(Value::as_str).unwrap_or(""),
                "channelId": e.get("channel_id").and_then(Value::as_str).unwrap_or(""),
                "duration": e.get("duration").and_then(Value::as_f64).unwrap_or(0.0),
                "views": e.get("view_count").and_then(Value::as_u64).unwrap_or(0),
                "live": e.get("live_status").and_then(Value::as_str) == Some("is_live"),
                "published": "",
                "picture": format!("https://i.ytimg.com/vi/{id}/mqdefault.jpg"),
            }))
        })
        .collect()
}

/// Search words for a URL's query.
pub fn query_encode(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

/// YouTube's search through yt-dlp: the first 20 videos, newest uploads
/// first if asked (YouTube's results page sorted by upload date).
pub fn youtube_search(text: &str, newest: bool) -> Result<Vec<Value>, String> {
    let text = text.trim().replace(['\n', '\r'], " ");
    if text.is_empty() || text.len() > 100 {
        return Err("no search words".into());
    }
    let target = if newest {
        format!("https://www.youtube.com/results?search_query={}&sp=CAI%3D", query_encode(&text))
    } else {
        format!("ytsearch20:{text}")
    };
    let out = run_with_timeout(
        Command::new("yt-dlp")
            .args(["--ignore-config", "--no-warnings", "--flat-playlist", "--playlist-end", "20", "--dump-single-json", "--"])
            .arg(&target),
        Duration::from_secs(40),
    )
    .map_err(|e| if e.contains("No such file") { "yt-dlp is not installed (sudo pacman -S yt-dlp)".into() } else { e })?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(err.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("yt-dlp failed").chars().take(300).collect());
    }
    let all: Value = serde_json::from_slice(&out.stdout).map_err(|e| e.to_string())?;
    Ok(search_entries(&all))
}

/// The text between `<tag ...>` and `</tag>` from `from` on.
fn xml_text<'a>(s: &'a str, tag: &str) -> Option<&'a str> {
    let start = s.find(&format!("<{tag}"))?;
    let open_end = start + s[start..].find('>')? + 1;
    let close = open_end + s[open_end..].find(&format!("</{tag}>"))?;
    Some(&s[open_end..close])
}

fn xml_unescape(s: &str) -> String {
    s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&apos;", "'").replace("&amp;", "&")
}

/// A channel's public feed (Atom) as videos, newest first.
pub fn parse_feed(xml: &str) -> Vec<Value> {
    let channel = xml_text(xml, "author").and_then(|a| xml_text(a, "name")).map(xml_unescape).unwrap_or_default();
    let channel_id = xml_text(xml, "yt:channelId").unwrap_or("").to_string();
    xml.split("<entry>")
        .skip(1)
        .filter_map(|entry| {
            let id = xml_text(entry, "yt:videoId")?;
            if !valid_video_id(id) {
                return None;
            }
            Some(json!({
                "id": id,
                "title": xml_unescape(xml_text(entry, "title").unwrap_or("")),
                "channel": channel,
                "channelId": channel_id,
                "duration": 0.0,
                "views": 0,
                "live": false,
                "published": xml_text(entry, "published").unwrap_or(""),
                "picture": format!("https://i.ytimg.com/vi/{id}/mqdefault.jpg"),
            }))
        })
        .collect()
}

/// Where FreeTube keeps its profiles: its own folder, or the Flatpak's.
fn freetube_files() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    vec![
        config.join("FreeTube").join("profiles.db"),
        home.join(".var/app/io.freetubeapp.FreeTube/config/FreeTube/profiles.db"),
    ]
}

/// FreeTube's subscriptions out of its profiles file (NeDB: a JSON document
/// a line, a later line of the same `_id` replacing an earlier one).
pub fn freetube_subscriptions(text: &str) -> Vec<Channel> {
    let mut profiles: Vec<(String, Value)> = Vec::new();
    for line in text.lines() {
        let Ok(doc) = serde_json::from_str::<Value>(line) else { continue };
        let Some(key) = doc.get("_id").and_then(Value::as_str).map(str::to_string) else { continue };
        profiles.retain(|(k, _)| *k != key);
        if doc.get("$$deleted").and_then(Value::as_bool) != Some(true) {
            profiles.push((key, doc));
        }
    }
    let mut out: Vec<Channel> = Vec::new();
    for (_, profile) in &profiles {
        for sub in profile.get("subscriptions").and_then(Value::as_array).into_iter().flatten() {
            let Some(id) = sub.get("id").and_then(Value::as_str) else { continue };
            if valid_channel_id(id) && !out.iter().any(|c| c.id == id) {
                out.push(Channel { id: id.into(), name: sub.get("name").and_then(Value::as_str).unwrap_or(id).into() });
            }
        }
    }
    out
}

/// FreeTube's subscriptions on this computer; None without FreeTube.
pub fn freetube() -> Option<Vec<Channel>> {
    freetube_files().iter().find_map(|f| std::fs::read_to_string(f).ok()).map(|t| freetube_subscriptions(&t))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Channel {
    pub id: String,
    pub name: String,
}

/// One request at a time, a quarter second apart (as the meter asks).
fn wait_turn() {
    static NEXT: OnceLock<Mutex<Instant>> = OnceLock::new();
    let mut next = NEXT.get_or_init(|| Mutex::new(Instant::now())).lock().unwrap_or_else(|p| p.into_inner());
    let now = Instant::now();
    if *next > now {
        std::thread::sleep(*next - now);
    }
    *next = Instant::now() + Duration::from_millis(250);
}

fn run_with_timeout(command: &mut Command, limit: Duration) -> Result<std::process::Output, String> {
    let child = command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().map_err(|e| e.to_string())?;
    finish(child, limit)
}

fn finish(child: Child, limit: Duration) -> Result<std::process::Output, String> {
    let pid = child.id();
    let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = done.clone();
    std::thread::spawn(move || {
        let end = Instant::now() + limit;
        while Instant::now() < end {
            if flag.load(std::sync::atomic::Ordering::Relaxed) {
                return;
            }
            std::thread::sleep(Duration::from_millis(200));
        }
        if !flag.load(std::sync::atomic::Ordering::Relaxed) {
            unsafe { libc::kill(pid as i32, libc::SIGKILL) };
        }
    });
    let out = child.wait_with_output().map_err(|e| e.to_string());
    done.store(true, std::sync::atomic::Ordering::Relaxed);
    out
}

/// A string for curl's config file (between double quotes).
fn curl_quote(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// curl, its settings (headers, body, address) on stdin: a token never
/// shows in the process list.
fn curl(config: &str, limit: Duration) -> Result<Vec<u8>, String> {
    let mut child = Command::new("curl")
        .args(["--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl did not start: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(config.as_bytes()).map_err(|e| e.to_string())?;
    }
    let out = finish(child, limit)?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let line = err.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("no answer").trim().to_string();
        return Err(line.trim_start_matches("curl: ").chars().take(200).collect());
    }
    Ok(out.stdout)
}

fn curl_base() -> String {
    "fail\nsilent\nshow-error\nlocation\nproto = \"=https\"\nproto-redir = \"=https\"\nmax-redirs = 3\nmax-time = 20\nmax-filesize = 4194304\n"
        .to_string()
}

/// Twitch's answer (its `data`).
pub fn twitch(body: &Value, token: Option<&str>) -> Result<Value, String> {
    wait_turn();
    let mut config = curl_base();
    config.push_str(&format!("header = {}\n", curl_quote(&format!("Client-Id: {TWITCH_CLIENT_ID}"))));
    config.push_str("header = \"Content-Type: application/json\"\n");
    if let Some(t) = token {
        config.push_str(&format!("header = {}\n", curl_quote(&format!("Authorization: OAuth {t}"))));
    }
    config.push_str(&format!("data-binary = {}\n", curl_quote(&body.to_string())));
    config.push_str(&format!("url = {}\n", curl_quote(TWITCH_GQL)));
    let bytes = curl(&config, Duration::from_secs(25)).map_err(|e| format!("Twitch: {e}"))?;
    let answer: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    if let Some(err) = answer.pointer("/errors/0/message").and_then(Value::as_str) {
        if answer.get("data").is_none_or(Value::is_null) {
            return Err(format!("Twitch: {err}"));
        }
    }
    Ok(answer.get("data").cloned().unwrap_or(Value::Null))
}

/// A YouTube channel's newest videos (its public feed).
pub fn youtube_feed(channel: &str) -> Result<Vec<Value>, String> {
    if !valid_channel_id(channel) {
        return Err("not a YouTube channel".into());
    }
    wait_turn();
    let mut config = curl_base();
    config.push_str(&format!("url = \"https://www.youtube.com/feeds/videos.xml?channel_id={channel}\"\n"));
    let bytes = curl(&config, Duration::from_secs(25)).map_err(|e| format!("YouTube: {e}"))?;
    Ok(parse_feed(&String::from_utf8_lossy(&bytes)))
}

/// The twitch.tv `auth-token` as pasted (with or without "OAuth ").
pub fn twitch_token_of(text: &str) -> Option<String> {
    let t = text.trim();
    let t = t.strip_prefix("OAuth ").or_else(|| t.strip_prefix("oauth:")).unwrap_or(t).trim();
    (t.len() >= 20 && t.len() <= 64 && t.chars().all(|c| c.is_ascii_alphanumeric())).then(|| t.to_ascii_lowercase())
}

/// The token's own file, readable by the user alone, apart from the
/// settings (so a settings file shared for help holds no token).
fn token_file() -> Option<PathBuf> {
    crate::settings::Settings::path().map(|p| p.with_file_name("twitch.json"))
}

pub fn twitch_token() -> Option<String> {
    let text = std::fs::read_to_string(token_file()?).ok()?;
    let v: Value = serde_json::from_str(&text).ok()?;
    twitch_token_of(v.get("token")?.as_str()?)
}

pub fn save_twitch_token(token: Option<&str>) -> Result<(), String> {
    use std::os::unix::fs::OpenOptionsExt;
    let path = token_file().ok_or("no settings folder")?;
    match token {
        None => {
            let _ = std::fs::remove_file(&path);
            Ok(())
        }
        Some(t) => {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
            }
            let _ = std::fs::remove_file(&path);
            let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path).map_err(|e| e.to_string())?;
            f.write_all(json!({ "token": t }).to_string().as_bytes()).map_err(|e| e.to_string())
        }
    }
}

/// The signed-in user's login, or why the token is refused.
pub fn twitch_whoami(token: &str) -> Result<String, String> {
    let data = twitch(&json!({ "query": "query { currentUser { login } }" }), Some(token))?;
    data.pointer("/currentUser/login").and_then(Value::as_str).map(str::to_string).ok_or_else(|| "Twitch did not take the token".into())
}

/// `streamlink` on the PATH.
pub fn streamlink_path() -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?).map(|d| d.join("streamlink")).find(|p| p.is_file())
}

pub fn streamlink_quality(q: &str) -> String {
    match q {
        "audio" => "audio_only,worst".into(),
        q => match q.parse::<u32>() {
            Ok(h) if (144..=2160).contains(&h) => format!("{h}p60,{h}p,best"),
            _ => "best".into(),
        },
    }
}

pub fn streamlink_args(url: &str, quality: &str, token: Option<&str>) -> Vec<String> {
    let mut a: Vec<String> = vec!["--stdout".into(), "--loglevel".into(), "error".into()];
    if let Some(t) = token {
        a.push("--twitch-api-header".into());
        a.push(format!("Authorization=OAuth {t}"));
    }
    a.push(url.into());
    a.push(streamlink_quality(quality));
    a
}

fn streamlinks() -> &'static Mutex<Vec<(String, Child)>> {
    static C: OnceLock<Mutex<Vec<(String, Child)>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(Vec::new()))
}

/// Starts Streamlink for player `slot` (stopping an earlier one): the
/// address mpv reads (`fdclose://` its pipe). `failed` gets Streamlink's
/// last error when it ends with one.
pub fn streamlink_start(slot: &str, url: &str, quality: &str, failed: impl FnOnce(String) + Send + 'static) -> Result<String, String> {
    use std::os::unix::process::CommandExt;
    streamlink_stop(slot);
    let exe = streamlink_path().ok_or("Streamlink isn't installed")?;
    let token = twitch_token();
    let mut command = Command::new(exe);
    command.args(streamlink_args(url, quality, token.as_deref())).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    // Ends with the app.
    unsafe {
        command.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let mut child = command.spawn().map_err(|e| format!("Streamlink didn't start: {e}"))?;
    let out = child.stdout.take().ok_or("Streamlink gave no output")?;
    let err = child.stderr.take();
    let pid = child.id();
    streamlinks().lock().unwrap_or_else(|p| p.into_inner()).push((slot.to_string(), child));
    let slot = slot.to_string();
    let _ = std::thread::Builder::new().name("streamlink".into()).spawn(move || {
        let mut last = String::new();
        if let Some(err) = err {
            for line in BufReader::new(err).lines().map_while(Result::ok) {
                let line = line.trim().trim_start_matches("error:").trim().to_string();
                if !line.is_empty() {
                    last = line.chars().take(240).collect();
                }
            }
        }
        let mut list = streamlinks().lock().unwrap_or_else(|p| p.into_inner());
        if let Some(i) = list.iter().position(|(s, c)| *s == slot && c.id() == pid) {
            let (_, mut c) = list.remove(i);
            drop(list);
            let ok = c.wait().map(|s| s.success()).unwrap_or(false);
            if !ok && !last.is_empty() {
                failed(last);
            }
        }
    });
    Ok(format!("fdclose://{}", out.into_raw_fd()))
}

pub fn streamlink_stop(slot: &str) {
    let mut list = streamlinks().lock().unwrap_or_else(|p| p.into_inner());
    while let Some(i) = list.iter().position(|(s, _)| s == slot) {
        let (_, mut c) = list.remove(i);
        let _ = c.kill();
        let _ = c.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_only_of_twitch_and_youtube() {
        assert_eq!(stream_url("twitch", "Some_One").unwrap(), "https://www.twitch.tv/some_one");
        assert_eq!(stream_url("youtube", "dQw4w9WgXcQ").unwrap(), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
        assert!(stream_url("twitch", "a/b").is_err());
        assert!(stream_url("youtube", "short").is_err());
        assert!(stream_url("file", "x").is_err());
    }

    #[test]
    fn pasted_links_give_the_video() {
        for t in [
            "dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10",
            "https://youtu.be/dQw4w9WgXcQ?si=x",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ",
        ] {
            assert_eq!(video_id_of(t).as_deref(), Some("dQw4w9WgXcQ"), "{t}");
        }
        assert_eq!(video_id_of("aion 2 guide"), None);
        assert_eq!(video_id_of("https://example.com/watch?v=dQw4w9WgXcQ"), None);
    }

    #[test]
    fn twitch_answers_become_cards() {
        let data = json!({ "game": { "streams": { "edges": [
            { "node": { "title": "T", "viewersCount": 5, "createdAt": "2026-11-12T10:00:00Z",
              "previewImageURL": "https://static-cdn.jtvnw.net/p.jpg", "game": { "displayName": "AION 2" },
              "broadcaster": { "login": "one", "displayName": "One", "profileImageURL": "" } } },
            { "node": { "title": "U", "viewersCount": 50, "broadcaster": { "login": "two", "displayName": "Two" } } }
        ] } } });
        let cards = twitch_cards(&data);
        assert_eq!(cards.len(), 2);
        assert_eq!(cards[0]["login"], "two");
        assert_eq!(cards[1]["game"], "AION 2");
        assert_eq!(cards[1]["live"], true);
        let data = json!({ "users": [ { "login": "off", "stream": null }, { "login": "on", "stream": { "viewersCount": 1 } } ] });
        let cards = twitch_cards(&data);
        assert_eq!(cards[0]["login"], "on");
        assert_eq!(cards[1]["live"], false);
    }

    #[test]
    fn twitch_queries_check_what_they_send() {
        assert!(twitch_query("search", &json!("")).is_err());
        assert!(twitch_query("user", &json!("no spaces")).is_err());
        let q = twitch_query("channels", &json!(["Good", "bad name", "x"])).unwrap();
        assert_eq!(q["variables"]["l"], json!(["good", "x"]));
        assert!(twitch_query("live", &json!("AION 2")).unwrap()["query"].as_str().unwrap().contains("game(name"));
        assert!(twitch_query("other", &Value::Null).is_err());
    }

    #[test]
    fn feeds_and_freetube_and_tokens() {
        let xml = r#"<feed><yt:channelId>UCabcdefghijklmnopqrstuv</yt:channelId><author><name>A &amp; B</name></author>
            <entry><yt:videoId>dQw4w9WgXcQ</yt:videoId><title>Hi &quot;there&quot;</title><published>2026-11-12T08:00:00+00:00</published></entry>
            <entry><yt:videoId>bad</yt:videoId><title>x</title></entry></feed>"#;
        let v = parse_feed(xml);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["title"], "Hi \"there\"");
        assert_eq!(v[0]["channel"], "A & B");
        let db = r#"{"_id":"allChannels","subscriptions":[{"id":"UCabcdefghijklmnopqrstuv","name":"One"}]}
{"_id":"p2","subscriptions":[{"id":"UCabcdefghijklmnopqrstuv","name":"One"},{"id":"nope","name":"x"}]}"#;
        assert_eq!(freetube_subscriptions(db), vec![Channel { id: "UCabcdefghijklmnopqrstuv".into(), name: "One".into() }]);
        assert_eq!(twitch_token_of(" OAuth abcdefghij0123456789ABCDEFGHIJ "), Some("abcdefghij0123456789abcdefghij".into()));
        assert_eq!(twitch_token_of("short"), None);
        assert_eq!(query_encode("AION 2 türkçe&x"), "AION+2+t%C3%BCrk%C3%A7e%26x");
        assert_eq!(curl_quote("a\"b\\c"), "\"a\\\"b\\\\c\"");
    }

    #[test]
    fn streamlink_gets_the_channel_and_a_quality() {
        assert_eq!(streamlink_quality("720"), "720p60,720p,best");
        assert_eq!(streamlink_quality("audio"), "audio_only,worst");
        let a = streamlink_args("https://www.twitch.tv/x", "1080", Some("tok"));
        assert_eq!(&a[3..5], ["--twitch-api-header", "Authorization=OAuth tok"]);
        assert_eq!(ytdl_format("audio"), "bestaudio/best");
    }

    // Online (cargo test -- --ignored): Twitch and YouTube answer as expected.
    #[test]
    #[ignore]
    fn twitch_and_youtube_answer() {
        let cards = twitch_cards(&twitch(&twitch_query("live", &json!("Just Chatting")).unwrap(), None).unwrap());
        assert!(!cards.is_empty(), "no live streams");
        assert!(cards[0]["live"].as_bool().unwrap());
        let found = youtube_search("aion 2", true).unwrap();
        assert!(!found.is_empty());
        let channel = found.iter().find_map(|v| v["channelId"].as_str().filter(|c| valid_channel_id(c))).unwrap().to_string();
        assert!(!youtube_feed(&channel).unwrap().is_empty());
    }
}
