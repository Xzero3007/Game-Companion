//! The user's own Jellyfin server, **in the home network only** (ported
//! from the meter's patch 0053 and the Streams plugin's `jellyfin.js`).
//!
//! The server's address must be a private one (10.x, 172.16-31.x,
//! 192.168.x, 127.x, fc00::/7, fe80::/10) or a home network's name
//! (localhost, a name without a dot, `*.local`, `*.lan`, `*.home.arpa`, ...),
//! and a name counts only when every address it has is such a private one.
//! Every request goes through curl with that checked address pinned
//! (`resolve`), no proxy, no redirects and no `~/.curlrc`; the key goes on
//! stdin, never on the command line or in an address. So nothing of this
//! reaches the internet, even by a typo.
//!
//! The address, the user and the server's key (from a sign-in with name and
//! password; the password is never kept) are kept in
//! `~/.config/game-companion/jellyfin.json`, readable by the user alone, and
//! nowhere else. What the server is told: the sign-in, what plays and how far
//! (so Continue watching is right in every Jellyfin app), an item marked
//! watched or not, and the sign-out.

use std::collections::HashMap;
use std::net::{IpAddr, ToSocketAddrs};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::streams::{curl_quote, curl_with};

/// Jellyfin counts time in ticks of 100 ns.
const TICKS: f64 = 10_000_000.0;

/// Whether `ip` is in a home network: private, loopback or link-local.
pub fn local_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => v.is_private() || v.is_loopback() || v.is_link_local(),
        IpAddr::V6(v) => {
            let first = v.segments()[0];
            v.is_loopback()
                || (first & 0xfe00) == 0xfc00
                || (first & 0xffc0) == 0xfe80
                || v.to_ipv4_mapped().is_some_and(|m| local_ip(IpAddr::V4(m)))
        }
    }
}

/// Whether `host` is a home network's name: localhost, a name without a
/// dot, or one ending in a local suffix. Its addresses are checked too.
pub fn local_name(host: &str) -> bool {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() || host.len() > 253 || !host.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.') {
        return false;
    }
    if host.split('.').any(|l| l.is_empty() || l.starts_with('-') || l.ends_with('-')) {
        return false;
    }
    host == "localhost"
        || !host.contains('.')
        || [".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain", ".localhost"]
            .iter()
            .any(|s| host.ends_with(s))
}

/// The host of a server address, as written in it.
#[derive(Debug, Clone, PartialEq)]
pub enum Host {
    Ip(IpAddr),
    Name(String),
}

/// A server address taken apart: http or https, a host in the home network,
/// a port, and a base path (a reverse proxy's `/jellyfin`).
#[derive(Debug, Clone, PartialEq)]
pub struct Server {
    pub https: bool,
    pub host: Host,
    pub port: Option<u16>,
    pub path: String,
}

fn ip_text(ip: IpAddr) -> String {
    match ip {
        IpAddr::V6(v) => format!("[{v}]"),
        v4 => v4.to_string(),
    }
}

impl Server {
    /// The address with `host` written in place of the one given.
    fn with_host(&self, host: &str) -> String {
        let port = self.port.map(|p| format!(":{p}")).unwrap_or_default();
        format!("{}://{host}{port}{}", if self.https { "https" } else { "http" }, self.path)
    }

    fn host_text(&self) -> String {
        match &self.host {
            Host::Ip(ip) => ip_text(*ip),
            Host::Name(n) => n.clone(),
        }
    }

    /// The address, written the one way.
    pub fn base(&self) -> String {
        self.with_host(&self.host_text())
    }

    pub fn port_or_default(&self) -> u16 {
        self.port.unwrap_or(if self.https { 443 } else { 80 })
    }
}

/// A server address as typed (`192.168.1.20:8096`, `http://nas.local:8096`,
/// `https://media.lan/jellyfin`), checked: only a home network's.
pub fn parse_server(input: &str) -> Result<Server, String> {
    const NOT_LOCAL: &str = "Only a Jellyfin server in your home network works here (192.168.x.x, 10.x.x.x, 172.16-31.x.x, localhost, or a name like nas.local).";
    let text = input.trim();
    if text.is_empty() || text.len() > 200 || text.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return Err("Type the server's address, like 192.168.1.20:8096.".into());
    }
    let (https, rest) = if let Some(r) = text.strip_prefix("http://") {
        (false, r)
    } else if let Some(r) = text.strip_prefix("https://") {
        (true, r)
    } else if text.contains("://") {
        return Err("The address starts with http:// or https://.".into());
    } else {
        (false, text)
    };
    let (authority, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    if authority.contains('@') || path.contains(['?', '#', '%', '\\']) || path.contains("..") {
        return Err("Just the server's address, no user, query or extras.".into());
    }
    let path = path.trim_end_matches('/');
    if !path.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '/' | '-' | '_' | '.')) || path.len() > 64 {
        return Err("The address's path has characters it can't have.".into());
    }
    let (host, port) = if let Some(r) = authority.strip_prefix('[') {
        let end = r.find(']').ok_or("An IPv6 address goes in [ ].")?;
        let port = r[end + 1..].strip_prefix(':');
        if !r[end + 1..].is_empty() && port.is_none() {
            return Err("That is not an address.".into());
        }
        (&r[..end], port)
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h, Some(p)),
            None => (authority, None),
        }
    };
    let port = match port {
        Some(p) => Some(p.parse::<u16>().ok().filter(|p| *p > 0).ok_or("The port is a number from 1 to 65535.")?),
        None => None,
    };
    let host = match host.parse::<IpAddr>() {
        Ok(ip) if local_ip(ip) => Host::Ip(ip),
        Ok(_) => return Err(NOT_LOCAL.into()),
        Err(_) if local_name(host) => Host::Name(host.trim_end_matches('.').to_ascii_lowercase()),
        Err(_) => return Err(NOT_LOCAL.into()),
    };
    Ok(Server { https, host, port, path: path.to_string() })
}

/// A local name's addresses, the home network's only (else refused).
pub fn local_addresses(name: &str, port: u16) -> Result<Vec<IpAddr>, String> {
    if !local_name(name) {
        return Err(format!("{name} is not a name in your home network"));
    }
    let all: Vec<IpAddr> = (name, port)
        .to_socket_addrs()
        .map_err(|e| format!("{name}: {e}"))?
        .map(|a| a.ip())
        .collect();
    if all.is_empty() || !all.iter().all(|ip| local_ip(*ip)) {
        return Err(format!("{name} is not only in your home network, so it is not used"));
    }
    Ok(all)
}

/// The server and the address to reach it at (checked again, each time).
fn reach(server: &Server) -> Result<IpAddr, String> {
    match &server.host {
        Host::Ip(ip) if local_ip(*ip) => Ok(*ip),
        Host::Ip(_) => Err("not a home network address".into()),
        Host::Name(name) => local_addresses(name, server.port_or_default())?
            .into_iter()
            .next()
            .ok_or_else(|| "the server's name has no home network address".into()),
    }
}

/// A Jellyfin item id: 32 hex digits, or 36 with dashes.
pub fn item_ok(id: &str) -> bool {
    matches!(id.len(), 32 | 36) && id.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

/// A play session or media source id: letters, digits, `-`.
pub fn token_ok(s: &str) -> bool {
    s.len() <= 64 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

/// Percent-encoding for a query's values.
fn encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b',') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A query: `name=value&...`, the values encoded.
pub fn query(pairs: &[(&str, String)]) -> String {
    pairs.iter().map(|(k, v)| format!("{k}={}", encode(v))).collect::<Vec<_>>().join("&")
}

/// What is kept of the sign-in.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Account {
    pub server: String,
    pub server_name: String,
    pub user: String,
    pub user_id: String,
    pub token: String,
    pub device_id: String,
}

impl Account {
    /// What the app's pages see: no key.
    pub fn public(&self) -> Value {
        json!({ "server": self.server, "serverName": self.server_name, "user": self.user })
    }

    /// The header Jellyfin reads who asks from.
    pub fn authorization(&self) -> String {
        let mut h = format!(
            "MediaBrowser Client=\"Game Companion\", Device=\"Game Companion\", DeviceId=\"{}\", Version=\"{}\"",
            self.device_id,
            env!("CARGO_PKG_VERSION")
        );
        if !self.token.is_empty() {
            h.push_str(&format!(", Token=\"{}\"", self.token));
        }
        h
    }
}

/// `~/.config/game-companion/jellyfin.json` (beside the settings).
fn account_file() -> Option<PathBuf> {
    Some(crate::settings::Settings::path()?.with_file_name("jellyfin.json"))
}

/// The kept sign-in, if its address is (still) a home network's.
pub fn load_account() -> Option<Account> {
    let text = std::fs::read_to_string(account_file()?).ok()?;
    let a: Account = serde_json::from_str(&text).ok()?;
    (parse_server(&a.server).is_ok() && !a.token.is_empty() && item_ok(&a.user_id)).then_some(a)
}

fn store_account(account: &Account) -> Result<(), String> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let path = account_file().ok_or("no home folder")?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(account).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    let _ = std::fs::remove_file(&tmp);
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .map_err(|e| e.to_string())?;
    f.write_all(text.as_bytes()).map_err(|e| e.to_string())?;
    drop(f);
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())
}

fn forget_account() {
    if let Some(p) = account_file() {
        let _ = std::fs::remove_file(p);
    }
}

fn device_id() -> String {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(format!("{:?}{}", std::time::SystemTime::now(), std::process::id()).as_bytes());
    if let Ok(id) = std::fs::read_to_string("/etc/machine-id") {
        h.update(id.as_bytes());
    }
    h.finalize().iter().take(16).map(|b| format!("{b:02x}")).collect()
}

/// curl's settings for one request to the server: the checked address
/// pinned, no proxy, no redirects, http(s) only.
pub fn curl_config(server: &Server, ip: IpAddr, account: &Account, method: &str, path: &str, body: Option<&Value>, accept: &str) -> String {
    let mut c = String::from("fail\nsilent\nshow-error\nproto = \"=http,https\"\nnoproxy = \"*\"\nconnect-timeout = 5\nmax-time = 30\nmax-filesize = 8388608\n");
    if let Host::Name(name) = &server.host {
        let addr = match ip {
            IpAddr::V6(v) => format!("[{v}]"),
            v4 => v4.to_string(),
        };
        c.push_str(&format!("resolve = {}\n", curl_quote(&format!("{name}:{}:{addr}", server.port_or_default()))));
    }
    c.push_str(&format!("header = {}\n", curl_quote(&format!("Authorization: {}", account.authorization()))));
    c.push_str(&format!("header = {}\n", curl_quote(&format!("Accept: {accept}"))));
    if method != "GET" {
        c.push_str(&format!("request = {}\n", curl_quote(method)));
    }
    if let Some(b) = body {
        c.push_str("header = \"Content-Type: application/json\"\n");
        c.push_str(&format!("data-binary = {}\n", curl_quote(&b.to_string())));
    } else if method == "POST" {
        c.push_str("data-binary = \"\"\n");
    }
    c.push_str(&format!("url = {}\n", curl_quote(&format!("{}{path}", server.base()))));
    c
}

fn call(account: &Account, method: &str, path: &str, body: Option<&Value>, accept: &str) -> Result<Vec<u8>, String> {
    let server = parse_server(&account.server)?;
    let ip = reach(&server)?;
    let config = curl_config(&server, ip, account, method, path, body, accept);
    curl_with(&["-q"], &config, Duration::from_secs(32)).map_err(|e| friendly(&e))
}

/// What curl said, in plain words.
fn friendly(e: &str) -> String {
    if e.contains("error: 401") {
        "Your server didn't take the sign-in any more: sign out and in again.".into()
    } else if e.contains("Couldn't connect") || e.contains("Failed to connect") || e.contains("timed out") || e.contains("Timeout") {
        "Your Jellyfin server doesn't answer. Is it on, and this PC in the same network?".into()
    } else if let Some(code) = e.split("error: ").nth(1) {
        format!("the server answered {}", code.trim())
    } else {
        e.to_string()
    }
}

/// A JSON request to the signed-in server.
pub fn request(account: &Account, method: &str, path: &str, body: Option<Value>) -> Result<Value, String> {
    let bytes = call(account, method, path, body.as_ref(), "application/json")?;
    if bytes.is_empty() {
        return Ok(Value::Null);
    }
    Ok(serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// Signs in with name and password; the key is kept, the password not.
pub fn sign_in(server: &str, user: &str, password: &str) -> Result<Account, String> {
    let server = parse_server(server)?;
    let user = user.trim();
    if user.is_empty() || user.len() > 100 {
        return Err("Type your Jellyfin user name.".into());
    }
    if password.len() > 200 {
        return Err("The password is too long.".into());
    }
    let mut account = Account {
        server: server.base(),
        device_id: load_account().map(|a| a.device_id).filter(|d| !d.is_empty()).unwrap_or_else(device_id),
        ..Default::default()
    };
    let info = request(&account, "GET", "/System/Info/Public", None)
        .map_err(|e| format!("No Jellyfin server answered at {}: {e}", account.server))?;
    if info.get("Id").and_then(Value::as_str).is_none() {
        return Err("That is not a Jellyfin server.".into());
    }
    account.server_name = info.get("ServerName").and_then(Value::as_str).unwrap_or("Jellyfin").chars().take(80).collect();
    let auth = request(&account, "POST", "/Users/AuthenticateByName", Some(json!({ "Username": user, "Pw": password })))
        .map_err(|e| if e.contains("sign-in") || e.contains("401") { "Wrong user name or password.".to_string() } else { e })?;
    account.token = auth
        .get("AccessToken")
        .and_then(Value::as_str)
        .filter(|t| !t.is_empty() && t.len() <= 200 && t.chars().all(|c| c.is_ascii_alphanumeric()))
        .ok_or("The server gave no key.")?
        .to_string();
    account.user_id = auth.pointer("/User/Id").and_then(Value::as_str).filter(|u| item_ok(u)).ok_or("The server gave no user.")?.to_string();
    account.user = auth.pointer("/User/Name").and_then(Value::as_str).unwrap_or(user).chars().take(100).collect();
    store_account(&account)?;
    Ok(account)
}

/// Signs out: the server forgets the key, and so does this PC.
pub fn sign_out() {
    if let Some(a) = load_account() {
        let _ = request(&a, "POST", "/Sessions/Logout", None);
    }
    forget_account();
    pictures().lock().unwrap_or_else(|p| p.into_inner()).clear();
}

// ---------- the lists ----------

/// What a list asks the server for.
const FIELDS: &str = "PrimaryImageAspectRatio,ParentId,SeriesPrimaryImage,MediaSourceCount";

fn list_query(account: &Account, extra: &[(&str, String)]) -> String {
    let mut pairs = vec![
        ("userId", account.user_id.clone()),
        ("Fields", FIELDS.to_string()),
        ("EnableImageTypes", "Primary,Thumb,Backdrop".to_string()),
        ("ImageTypeLimit", "1".to_string()),
        ("EnableUserData", "true".to_string()),
    ];
    pairs.extend(extra.iter().map(|(k, v)| (*k, v.clone())));
    query(&pairs)
}

/// The first path the server knows (newer servers' first, then older ones').
fn get_first(account: &Account, paths: &[String], q: &str) -> Result<Value, String> {
    let mut last = String::new();
    for p in paths {
        match request(account, "GET", &format!("{p}?{q}"), None) {
            Ok(v) => return Ok(v),
            Err(e) if e.contains("answered 404") || e.contains("answered 405") => last = e,
            Err(e) => return Err(e),
        }
    }
    Err(last)
}

fn user_paths(account: &Account, new: &str, old: &str) -> Vec<String> {
    vec![new.to_string(), old.replace("{user}", &account.user_id)]
}

pub fn continue_watching(account: &Account) -> Result<Vec<Value>, String> {
    let q = list_query(account, &[("Limit", "40".into()), ("MediaTypes", "Video".into())]);
    Ok(series_first(items(&get_first(account, &user_paths(account, "/UserItems/Resume", "/Users/{user}/Items/Resume"), &q)?)))
}

pub fn next_up(account: &Account) -> Result<Vec<Value>, String> {
    let q = list_query(account, &[("Limit", "40".into())]);
    Ok(series_first(items(&get_first(account, &["/Shows/NextUp".to_string()], &q)?)))
}

/// Continue and Next up as the person wants them: an episode shows its
/// series' name on top and the episode below, with the series' picture
/// (its thumb, else its backdrop, else its poster), not a still from the
/// episode; a film its own thumb or backdrop (as already).
pub fn series_first(list: Vec<Value>) -> Vec<Value> {
    list.into_iter()
        .map(|mut v| {
            if v["type"] == "Episode" && !v["series"].as_str().unwrap_or("").is_empty() {
                let episode = v["name"].as_str().unwrap_or("").to_string();
                let code = v["code"].as_str().unwrap_or("").to_string();
                v["name"] = v["series"].clone();
                v["sub"] = json!([code.as_str(), episode.as_str()].iter().filter(|t| !t.is_empty()).cloned().collect::<Vec<_>>().join(" · "));
                let series_picture = v["seriesPicture"].as_str().unwrap_or("").to_string();
                if !series_picture.is_empty() {
                    v["picture"] = json!(series_picture);
                }
            }
            v
        })
        .collect()
}

pub fn libraries(account: &Account) -> Result<Vec<Value>, String> {
    let q = query(&[("userId", account.user_id.clone())]);
    Ok(libraries_of(&get_first(account, &user_paths(account, "/UserViews", "/Users/{user}/Views"), &q)?))
}

/// One step into the libraries: a library, a show, a season, a folder.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Folder {
    pub id: String,
    /// "lib" (a library), "Series", "Season", or another folder's type.
    #[serde(rename = "type")]
    pub kind: String,
    /// A library's kind: "movies", "tvshows", ...
    pub collection: String,
    pub series_id: String,
}

/// Items asked per page of a library.
pub const PAGE: usize = 120;

/// A folder's items (from `start`) and how many it has.
pub fn folder(account: &Account, f: &Folder, start: usize) -> Result<(Vec<Value>, usize), String> {
    if !item_ok(&f.id) || (!f.series_id.is_empty() && !item_ok(&f.series_id)) {
        return Err("not a folder".into());
    }
    let answer = match f.kind.as_str() {
        "Series" => get_first(account, &[format!("/Shows/{}/Seasons", f.id)], &list_query(account, &[]))?,
        "Season" => get_first(account, &[format!("/Shows/{}/Episodes", f.series_id)], &list_query(account, &[("seasonId", f.id.clone())]))?,
        _ => {
            let types = match f.collection.as_str() {
                "movies" => "Movie",
                "tvshows" => "Series",
                _ => "",
            };
            let mut extra = vec![
                ("ParentId", f.id.clone()),
                ("SortBy", "SortName".to_string()),
                ("SortOrder", "Ascending".to_string()),
                ("StartIndex", start.to_string()),
                ("Limit", PAGE.to_string()),
            ];
            if !types.is_empty() {
                extra.push(("IncludeItemTypes", types.to_string()));
                extra.push(("Recursive", "true".to_string()));
            }
            get_first(account, &user_paths(account, "/Items", "/Users/{user}/Items"), &list_query(account, &extra))?
        }
    };
    let got = items(&answer);
    let total = answer.get("TotalRecordCount").and_then(Value::as_u64).map(|n| n as usize).unwrap_or(start + got.len());
    Ok((got, total))
}

pub fn search(account: &Account, text: &str) -> Result<Vec<Value>, String> {
    let text: String = text.trim().chars().filter(|c| !c.is_control()).take(100).collect();
    let q = list_query(account, &[
        ("searchTerm", text),
        ("IncludeItemTypes", "Movie,Series,Episode".into()),
        ("Recursive", "true".into()),
        ("Limit", "60".into()),
    ]);
    Ok(items(&get_first(account, &user_paths(account, "/Items", "/Users/{user}/Items"), &q)?))
}

/// The episode after `item` in its series (across seasons), if any.
pub fn next_episode(account: &Account, series: &str, item: &str) -> Result<Option<Value>, String> {
    if !item_ok(series) || !item_ok(item) {
        return Err("not an episode".into());
    }
    let q = list_query(account, &[("startItemId", item.to_string()), ("Limit", "2".into())]);
    let all = items(&get_first(account, &[format!("/Shows/{series}/Episodes")], &q)?);
    Ok(all.into_iter().find(|e| e["id"] != item))
}

/// Marks an item watched (`on`) or not.
pub fn set_played(account: &Account, item: &str, on: bool) -> Result<(), String> {
    if !item_ok(item) {
        return Err("not an item".into());
    }
    request(account, if on { "POST" } else { "DELETE" }, &format!("/Users/{}/PlayedItems/{item}", account.user_id), None).map(|_| ())
}

// ---------- playing ----------

/// How a video is fetched: the server's file as it is ("original" and
/// "audio"), or the server's conversion down to a height (HLS).
pub fn stream_path(item: &str, source: &str, session: &str, quality: &str, audio_index: Option<u32>) -> String {
    let src = if source.is_empty() { item } else { source };
    let bitrate = match quality {
        "1080" => Some((1080, 10_000_000)),
        "720" => Some((720, 4_000_000)),
        "480" => Some((480, 2_000_000)),
        "360" => Some((360, 1_000_000)),
        _ => None,
    };
    match bitrate {
        Some((h, br)) => {
            let mut p = format!(
                "/Videos/{item}/master.m3u8?MediaSourceId={src}&VideoCodec=h264&AudioCodec=aac,mp3&MaxHeight={h}\
                 &VideoBitrate={br}&AudioBitrate=192000&TranscodingMaxAudioChannels=2&SegmentContainer=ts\
                 &BreakOnNonKeyFrames=true"
            );
            if !session.is_empty() {
                p.push_str(&format!("&PlaySessionId={session}"));
            }
            if let Some(a) = audio_index {
                p.push_str(&format!("&AudioStreamIndex={a}"));
            }
            p
        }
        None => format!("/Videos/{item}/stream?static=true&mediaSourceId={src}"),
    }
}

/// The address mpv plays and the header it sends along (the key goes in
/// the header, never in the address). For plain http a name is replaced by
/// its checked home network address; https keeps its name for its
/// certificate (its addresses are checked all the same).
pub fn mpv_source(account: &Account, path: &str) -> Result<(String, String), String> {
    let server = parse_server(&account.server)?;
    let ip = reach(&server)?;
    let base = match (&server.host, server.https) {
        (Host::Name(_), false) => server.with_host(&ip_text(ip)),
        _ => server.base(),
    };
    Ok((format!("{base}{path}"), format!("Authorization: {}", account.authorization())))
}

/// What is needed to play an item: the file, the play session, the tracks.
pub fn playback_info(account: &Account, item: &str) -> Result<Value, String> {
    if !item_ok(item) {
        return Err("not an item".into());
    }
    request(account, "POST", &format!("/Items/{item}/PlaybackInfo?UserId={}", account.user_id), Some(json!({})))
}

/// The parts of an item to skip: Media Segments (Jellyfin 10.10 and newer),
/// else the Intro Skipper plugin's own answers.
pub fn skip_segments(account: &Account, item: &str) -> Vec<Value> {
    if !item_ok(item) {
        return Vec::new();
    }
    let tries = [
        format!("/MediaSegments/{item}"),
        format!("/Episode/{item}/IntroSkipperSegments"),
        format!("/Episode/{item}/IntroTimestamps/v1"),
    ];
    for (n, path) in tries.iter().enumerate() {
        if let Ok(answer) = request(account, "GET", path, None) {
            let answer = if n == 2 { json!({ "Introduction": answer }) } else { answer };
            let segs = segments_of(&answer);
            if !segs.is_empty() {
                return segs;
            }
        }
    }
    Vec::new()
}

/// Tells the server what plays: "start", "progress" or "stopped".
#[allow(clippy::too_many_arguments)]
pub fn report(account: &Account, kind: &str, item: &str, source: &str, session: &str, position: f64, paused: bool, transcode: bool) -> Result<(), String> {
    if !item_ok(item) || !token_ok(source) || !token_ok(session) {
        return Err("not an item".into());
    }
    let path = match kind {
        "start" => "/Sessions/Playing",
        "progress" => "/Sessions/Playing/Progress",
        "stopped" => "/Sessions/Playing/Stopped",
        _ => return Err("report start, progress or stopped".into()),
    };
    let seconds = if position.is_finite() && position >= 0.0 { position } else { 0.0 };
    let mut body = json!({
        "ItemId": item,
        "MediaSourceId": if source.is_empty() { item } else { source },
        "PositionTicks": (seconds * TICKS) as u64,
        "IsPaused": paused,
        "IsMuted": false,
        "PlayMethod": if transcode { "Transcode" } else { "DirectPlay" },
        "CanSeek": true,
    });
    if !session.is_empty() {
        body["PlaySessionId"] = json!(session);
    }
    request(account, "POST", path, Some(body)).map(|_| ())
}

// ---------- pictures ----------

fn pictures() -> &'static Mutex<HashMap<String, Vec<u8>>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Vec<u8>>>> = OnceLock::new();
    CACHE.get_or_init(Mutex::default)
}

/// A picture of an item ("<item>/<Primary|Thumb|Backdrop>/<width>"), kept in
/// memory while the app runs.
pub fn picture(id: &str) -> Result<Vec<u8>, String> {
    let mut parts = id.split('/');
    let (Some(item), Some(kind), Some(width), None) = (parts.next(), parts.next(), parts.next(), parts.next()) else {
        return Err("not a picture".into());
    };
    let width: u32 = width.parse().map_err(|_| "not a picture")?;
    if !item_ok(item) || !["Primary", "Thumb", "Backdrop"].contains(&kind) {
        return Err("not a picture".into());
    }
    let width = width.clamp(60, 720);
    let key = format!("{item}/{kind}/{width}");
    if let Some(hit) = pictures().lock().unwrap_or_else(|p| p.into_inner()).get(&key) {
        return Ok(hit.clone());
    }
    let account = load_account().ok_or("not signed in")?;
    let bytes = call(&account, "GET", &format!("/Items/{item}/Images/{kind}?fillWidth={width}&quality=80"), None, "image/webp,image/jpeg,image/png")?;
    let mut cache = pictures().lock().unwrap_or_else(|p| p.into_inner());
    // About 300 pictures of some 20 KB each, then it starts over.
    if cache.len() >= 300 {
        cache.clear();
    }
    cache.insert(key, bytes.clone());
    Ok(bytes)
}

// ---------- the server's answers, as the panel shows them ----------

fn s(v: &Value, k: &str) -> String {
    v.get(k).and_then(Value::as_str).unwrap_or("").to_string()
}

fn n(v: &Value, k: &str) -> f64 {
    v.get(k).and_then(Value::as_f64).filter(|x| x.is_finite()).unwrap_or(0.0)
}

fn picture_url(id: &str, kind: &str, width: u32) -> String {
    if item_ok(id) {
        format!("image://jellyfin/{id}/{kind}/{width}")
    } else {
        String::new()
    }
}

/// An item as the panel shows it: `{ id, type, name, sub, series, code,
/// playable, openable, seriesId, seasonId, runtime, position, percent,
/// played, unplayed, picture, poster }` (times in seconds; pictures as
/// `image://jellyfin/...`).
pub fn item(i: &Value) -> Option<Value> {
    let id = s(i, "Id");
    if !item_ok(&id) {
        return None;
    }
    let kind = s(i, "Type");
    let ud = i.get("UserData").cloned().unwrap_or(Value::Null);
    let tags = i.get("ImageTags").cloned().unwrap_or(Value::Null);
    let has = |k: &str| tags.get(k).is_some_and(|t| !t.is_null());
    let runtime = n(i, "RunTimeTicks") / TICKS;
    let position = n(&ud, "PlaybackPositionTicks") / TICKS;
    let episode = kind == "Episode";
    let season = i.get("ParentIndexNumber").and_then(Value::as_u64);
    let number = i.get("IndexNumber").and_then(Value::as_u64);
    let code = match (episode, number) {
        (true, Some(e)) => format!("{}E{e}", season.map(|s| format!("S{s} ")).unwrap_or_default()),
        _ => String::new(),
    };
    let year = i.get("ProductionYear").and_then(Value::as_u64).map(|y| y.to_string()).unwrap_or_default();
    let backdrops = |k: &str| i.get(k).and_then(Value::as_array).is_some_and(|a| !a.is_empty());
    // Wide: an episode's own still, a film's thumb or backdrop, else the series'.
    let wide = if episode && has("Primary") {
        picture_url(&id, "Primary", 400)
    } else if has("Thumb") {
        picture_url(&id, "Thumb", 400)
    } else if backdrops("BackdropImageTags") {
        picture_url(&id, "Backdrop", 400)
    } else if item_ok(&s(i, "ParentThumbItemId")) {
        picture_url(&s(i, "ParentThumbItemId"), "Thumb", 400)
    } else if backdrops("ParentBackdropImageTags") {
        picture_url(&s(i, "ParentBackdropItemId"), "Backdrop", 400)
    } else if has("Primary") {
        picture_url(&id, "Primary", 400)
    } else {
        String::new()
    };
    let poster = if has("Primary") {
        picture_url(&id, "Primary", 240)
    } else if episode && i.get("SeriesPrimaryImageTag").is_some_and(|t| !t.is_null()) {
        picture_url(&s(i, "SeriesId"), "Primary", 240)
    } else {
        String::new()
    };
    // The series' own wide picture (for Continue and Next up).
    let series_picture = if !episode {
        String::new()
    } else if item_ok(&s(i, "ParentThumbItemId")) {
        picture_url(&s(i, "ParentThumbItemId"), "Thumb", 400)
    } else if backdrops("ParentBackdropImageTags") {
        picture_url(&s(i, "ParentBackdropItemId"), "Backdrop", 400)
    } else if i.get("SeriesPrimaryImageTag").is_some_and(|t| !t.is_null()) {
        picture_url(&s(i, "SeriesId"), "Primary", 400)
    } else {
        String::new()
    };
    let series = s(i, "SeriesName");
    let sub = if episode {
        [series.as_str(), code.as_str()].iter().filter(|t| !t.is_empty()).cloned().collect::<Vec<_>>().join(" · ")
    } else {
        [year.as_str(), if kind == "Series" { "Series" } else { "" }].iter().filter(|t| !t.is_empty()).cloned().collect::<Vec<_>>().join(" · ")
    };
    let openable_types = ["Series", "Season", "BoxSet", "Folder", "CollectionFolder", "Playlist"];
    let playable_types = ["Movie", "Episode", "Video", "MusicVideo", "Trailer"];
    let openable = openable_types.contains(&kind.as_str()) || i.get("IsFolder").and_then(Value::as_bool).unwrap_or(false);
    let playable = playable_types.contains(&kind.as_str()) || (!openable && s(i, "MediaType") == "Video");
    let position = if position > 0.0 && (runtime == 0.0 || position < runtime) { position } else { 0.0 };
    let percent = {
        let p = n(&ud, "PlayedPercentage");
        let p = if p > 0.0 { p } else if runtime > 0.0 && position > 0.0 { position / runtime * 100.0 } else { 0.0 };
        p.clamp(0.0, 100.0)
    };
    let name = s(i, "Name");
    Some(json!({
        "id": id,
        "type": kind,
        "name": if name.is_empty() { "Untitled".to_string() } else { name.chars().take(200).collect() },
        "sub": sub,
        "series": series,
        "code": code,
        "playable": playable,
        "openable": openable,
        "seriesId": s(i, "SeriesId"),
        "seasonId": s(i, "SeasonId"),
        "collection": s(i, "CollectionType"),
        "runtime": runtime,
        "position": position,
        "percent": percent,
        "played": ud.get("Played").and_then(Value::as_bool).unwrap_or(false),
        "unplayed": n(&ud, "UnplayedItemCount").max(0.0),
        "picture": wide,
        "poster": poster,
        "seriesPicture": series_picture,
    }))
}

/// A list answer (`{ Items: [...] }` or `[...]`) as items.
pub fn items(answer: &Value) -> Vec<Value> {
    let all = answer.get("Items").and_then(Value::as_array).or_else(|| answer.as_array());
    all.map(|a| a.iter().filter_map(item).collect()).unwrap_or_default()
}

/// The libraries a user has, films' and shows' first (music, books and the
/// like left out: they don't play here).
pub fn libraries_of(answer: &Value) -> Vec<Value> {
    let rank = |k: &str| match k {
        "movies" => 0,
        "tvshows" => 1,
        "boxsets" => 2,
        "homevideos" => 2,
        "musicvideos" => 3,
        "mixed" | "" => 4,
        _ => 9,
    };
    let mut libs: Vec<Value> = items(answer)
        .into_iter()
        // Collections (boxsets) stay: each opens to its films and shows.
        .filter(|v| !["music", "books", "playlists", "livetv", "photos"].contains(&v["collection"].as_str().unwrap_or("")))
        .map(|mut v| {
            v["type"] = json!("lib");
            v["openable"] = json!(true);
            v["playable"] = json!(false);
            if v["picture"].as_str().unwrap_or("").is_empty() {
                v["picture"] = v["poster"].clone();
            }
            v
        })
        .collect();
    libs.sort_by(|a, b| {
        let (ka, kb) = (a["collection"].as_str().unwrap_or(""), b["collection"].as_str().unwrap_or(""));
        rank(ka).cmp(&rank(kb)).then_with(|| a["name"].as_str().cmp(&b["name"].as_str()))
    });
    libs
}

/// The parts to skip, in seconds: `[{ kind, start, end }]` from Media
/// Segments (`{ Items: [{ Type, StartTicks, EndTicks }] }`) or the Intro
/// Skipper plugin (`{ Introduction: { IntroStart, IntroEnd, Valid }, ... }`).
pub fn segments_of(answer: &Value) -> Vec<Value> {
    let kind_of = |k: &str| match k {
        "Intro" | "Introduction" => Some("intro"),
        "Recap" => Some("recap"),
        "Outro" | "Credits" => Some("credits"),
        "Preview" => Some("preview"),
        _ => None,
    };
    let mut out: Vec<(f64, Value)> = Vec::new();
    if let Some(list) = answer.get("Items").and_then(Value::as_array) {
        for seg in list {
            let (Some(kind), start, end) = (kind_of(&s(seg, "Type")), n(seg, "StartTicks") / TICKS, n(seg, "EndTicks") / TICKS) else { continue };
            if end > start + 1.0 {
                out.push((start, json!({ "kind": kind, "start": start, "end": end })));
            }
        }
    } else if let Some(map) = answer.as_object() {
        for (k, seg) in map {
            let Some(kind) = kind_of(k) else { continue };
            if !seg.is_object() || seg.get("Valid").and_then(Value::as_bool) == Some(false) {
                continue;
            }
            let start = seg.get("IntroStart").or_else(|| seg.get("Start")).and_then(Value::as_f64).unwrap_or(0.0);
            let end = seg.get("IntroEnd").or_else(|| seg.get("End")).and_then(Value::as_f64).unwrap_or(0.0);
            if end > start + 1.0 {
                out.push((start, json!({ "kind": kind, "start": start, "end": end })));
            }
        }
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out.into_iter().map(|(_, v)| v).collect()
}

/// A subtitle codec as a file mpv can take from the server.
fn sub_format(codec: &str) -> Option<&'static str> {
    match codec.to_ascii_lowercase().as_str() {
        "subrip" | "srt" => Some("srt"),
        "webvtt" | "vtt" => Some("vtt"),
        "ass" => Some("ass"),
        "ssa" => Some("ssa"),
        _ => None,
    }
}

/// A media source's tracks: `{ audio: [{index, ord, label}], subs: [{index,
/// ord, external, format, label}], audioIndex, subIndex }`. `ord` is mpv's
/// number for it (the n-th of its kind in the file); a subtitle outside the
/// file comes from the server.
pub fn tracks_of(source: &Value) -> Value {
    let mut streams: Vec<&Value> = source.get("MediaStreams").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    streams.sort_by(|a, b| n(a, "Index").total_cmp(&n(b, "Index")));
    let label = |st: &Value| {
        let t = s(st, "DisplayTitle");
        if !t.is_empty() {
            return t.chars().take(80).collect::<String>();
        }
        let t = [s(st, "Language").to_uppercase(), s(st, "Codec")].iter().filter(|x| !x.is_empty()).cloned().collect::<Vec<_>>().join(" ");
        if t.is_empty() { format!("Track {}", n(st, "Index")) } else { t }
    };
    let (mut audio, mut subs) = (Vec::new(), Vec::new());
    let (mut a, mut t) = (0, 0);
    for st in streams {
        let external = st.get("IsExternal").and_then(Value::as_bool).unwrap_or(false);
        let index = n(st, "Index") as i64;
        match s(st, "Type").as_str() {
            "Audio" if !external => {
                a += 1;
                audio.push(json!({ "index": index, "ord": a, "label": label(st) }));
            }
            "Subtitle" if external => {
                if let Some(f) = sub_format(&s(st, "Codec")) {
                    subs.push(json!({ "index": index, "ord": 0, "external": true, "format": f, "label": label(st) }));
                }
            }
            "Subtitle" => {
                t += 1;
                subs.push(json!({ "index": index, "ord": t, "external": false, "format": sub_format(&s(st, "Codec")).unwrap_or(""), "label": label(st) }));
            }
            _ => {}
        }
    }
    let def_audio = source.get("DefaultAudioStreamIndex").and_then(Value::as_i64);
    let def_sub = source.get("DefaultSubtitleStreamIndex").and_then(Value::as_i64).unwrap_or(-1);
    let audio_index = def_audio.filter(|d| audio.iter().any(|x| x["index"] == *d)).or_else(|| audio.first().and_then(|x| x["index"].as_i64()));
    let sub_index = if subs.iter().any(|x| x["index"] == def_sub) { def_sub } else { -1 };
    json!({ "audio": audio, "subs": subs, "audioIndex": audio_index.unwrap_or(-1), "subIndex": sub_index })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_server_in_the_home_network() {
        for (input, base) in [
            ("192.168.1.20:8096", "http://192.168.1.20:8096"),
            ("http://10.0.0.5:8096/", "http://10.0.0.5:8096"),
            ("https://172.20.1.1/jellyfin", "https://172.20.1.1/jellyfin"),
            ("localhost:8096", "http://localhost:8096"),
            ("127.0.0.1:8096", "http://127.0.0.1:8096"),
            ("http://NAS.local:8096", "http://nas.local:8096"),
            ("nas:8096", "http://nas:8096"),
            ("media.home.arpa", "http://media.home.arpa"),
            ("http://[fd00::12]:8096", "http://[fd00::12]:8096"),
            ("[fe80::1]:8096", "http://[fe80::1]:8096"),
        ] {
            assert_eq!(parse_server(input).map(|s| s.base()), Ok(base.to_string()), "{input}");
        }
        for bad in [
            "jellyfin.example.com", "https://demo.jellyfin.org/stable", "8.8.8.8:8096", "http://1.2.3.4",
            "172.32.0.1", "100.64.0.1", "[2001:db8::1]:8096", "[::ffff:8.8.8.8]", "user@192.168.1.2",
            "192.168.1.2:8096/x?y=1", "192.168.1.2/../x", "ftp://192.168.1.2", "192.168.1.2:99999",
            "192.168.1.2 :8096", "", "nas.local.evil.com", "my-nas.de", "192.168.1.2.nip.io",
        ] {
            assert!(parse_server(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn public_names_are_never_looked_up() {
        assert!(local_addresses("example.com", 80).is_err());
        assert!(local_addresses("localhost", 80).is_ok());
        let server = Server { https: false, host: Host::Ip("8.8.8.8".parse().unwrap()), port: None, path: String::new() };
        assert!(reach(&server).is_err());
    }

    #[test]
    fn curl_goes_straight_to_the_checked_address() {
        let account = Account { server: "http://nas.local:8096".into(), token: "abc123".into(), device_id: "d1".into(), ..Default::default() };
        let server = parse_server(&account.server).unwrap();
        let c = curl_config(&server, "192.168.1.20".parse().unwrap(), &account, "POST", "/Sessions/Playing", Some(&json!({ "a": 1 })), "application/json");
        assert!(c.contains("noproxy = \"*\""), "{c}");
        assert!(c.contains("resolve = \"nas.local:8096:192.168.1.20\""), "{c}");
        assert!(c.contains("proto = \"=http,https\""), "{c}");
        assert!(!c.contains("location"), "no redirects: {c}");
        assert!(c.contains("url = \"http://nas.local:8096/Sessions/Playing\""), "{c}");
        assert!(c.contains("Token=\\\"abc123\\\""), "the key in the header: {c}");
        assert!(!c.lines().any(|l| l.starts_with("url") && l.contains("abc123")));
    }

    #[test]
    fn the_key_goes_in_the_header_only() {
        let a = Account { server: "http://192.168.1.20:8096".into(), token: "abc123".into(), device_id: "d1".into(), ..Default::default() };
        assert!(a.authorization().ends_with(", Token=\"abc123\""));
        assert!(!a.public().to_string().contains("abc123"));
        let (url, header) = mpv_source(&a, &stream_path("0123456789abcdef0123456789abcdef", "", "", "original", None)).unwrap();
        assert!(!url.contains("abc123") && url.starts_with("http://192.168.1.20:8096/Videos/"), "{url}");
        assert!(header.starts_with("Authorization: MediaBrowser ") && header.contains("abc123"));
    }

    #[test]
    fn the_stream_is_the_file_or_the_servers_conversion() {
        let id = "0123456789abcdef0123456789abcdef";
        assert_eq!(stream_path(id, "", "", "original", None), format!("/Videos/{id}/stream?static=true&mediaSourceId={id}"));
        assert_eq!(stream_path(id, "", "", "audio", None), format!("/Videos/{id}/stream?static=true&mediaSourceId={id}"));
        let p = stream_path(id, id, "abc", "720", Some(2));
        assert!(p.starts_with(&format!("/Videos/{id}/master.m3u8?")) && p.contains("MaxHeight=720") && p.contains("PlaySessionId=abc") && p.contains("AudioStreamIndex=2"), "{p}");
    }

    #[test]
    fn continue_shows_the_series_first() {
        let ep = "0123456789abcdef0123456789abcdef";
        let series = "fedcba9876543210fedcba9876543210";
        let raw = json!([{ "Id": ep, "Type": "Episode", "Name": "Pilot", "SeriesName": "Show", "SeriesId": series, "ParentIndexNumber": 1, "IndexNumber": 2,
            "ImageTags": { "Primary": "still" }, "ParentThumbItemId": series, "ParentThumbImageTag": "t" }]);
        let v = &series_first(items(&raw))[0];
        assert_eq!(v["name"], "Show");
        assert_eq!(v["sub"], "S1 E2 · Pilot");
        assert_eq!(v["picture"], format!("image://jellyfin/{series}/Thumb/400"));
        // Without a series thumb: its backdrop, else its poster.
        let raw = json!([{ "Id": ep, "Type": "Episode", "Name": "Pilot", "SeriesName": "Show", "SeriesId": series, "SeriesPrimaryImageTag": "p", "ImageTags": { "Primary": "still" } }]);
        assert_eq!(series_first(items(&raw))[0]["picture"], format!("image://jellyfin/{series}/Primary/400"));
    }

    #[test]
    fn a_query_is_encoded() {
        assert_eq!(query(&[("searchTerm", "a&b=c d".into()), ("Limit", "20".into())]), "searchTerm=a%26b%3Dc%20d&Limit=20");
    }

    #[test]
    fn items_as_the_panel_shows_them() {
        let id = "0123456789abcdef0123456789abcdef";
        let series = "fedcba9876543210fedcba9876543210";
        let answer = json!({ "Items": [
            { "Id": id, "Type": "Episode", "Name": "Pilot", "SeriesName": "Show", "SeriesId": series, "ParentIndexNumber": 1, "IndexNumber": 2,
              "RunTimeTicks": 36_000_000_000u64, "UserData": { "PlaybackPositionTicks": 9_000_000_000u64, "Played": false },
              "ImageTags": { "Primary": "t" }, "SeriesPrimaryImageTag": "s" },
            { "Id": series, "Type": "Series", "Name": "Show", "ProductionYear": 2020, "ImageTags": {}, "IsFolder": true },
            { "Id": "not-an-id", "Type": "Movie" }
        ]});
        let list = items(&answer);
        assert_eq!(list.len(), 2);
        let ep = &list[0];
        assert_eq!(ep["code"], "S1 E2");
        assert_eq!(ep["sub"], "Show · S1 E2");
        assert_eq!(ep["position"], 900.0);
        assert_eq!(ep["percent"], 25.0);
        assert_eq!(ep["playable"], true);
        assert_eq!(ep["picture"], format!("image://jellyfin/{id}/Primary/400"));
        assert_eq!(list[1]["openable"], true);
        assert_eq!(list[1]["playable"], false);
        assert_eq!(list[1]["sub"], "2020 · Series");
    }

    #[test]
    fn libraries_films_and_shows_first() {
        let lib = |id: char, name: &str, kind: &str| json!({ "Id": id.to_string().repeat(32), "Name": name, "CollectionType": kind, "Type": "CollectionFolder" });
        let libs = libraries_of(&json!({ "Items": [lib('a', "Music", "music"), lib('b', "Shows", "tvshows"), lib('c', "Films", "movies"), lib('d', "Home", "homevideos")] }));
        let names: Vec<&str> = libs.iter().map(|l| l["name"].as_str().unwrap()).collect();
        assert_eq!(names, ["Films", "Shows", "Home"]);
        assert_eq!(libs[0]["type"], "lib");
    }

    #[test]
    fn parts_to_skip() {
        let segs = segments_of(&json!({ "Items": [
            { "Type": "Outro", "StartTicks": 12_000_000_000u64, "EndTicks": 13_000_000_000u64 },
            { "Type": "Intro", "StartTicks": 100_000_000u64, "EndTicks": 900_000_000u64 },
            { "Type": "Commercial", "StartTicks": 0, "EndTicks": 50_000_000 }
        ]}));
        assert_eq!(segs.len(), 2);
        assert_eq!(segs[0]["kind"], "intro");
        assert_eq!(segs[1]["kind"], "credits");
        let skipper = segments_of(&json!({ "Introduction": { "IntroStart": 5.0, "IntroEnd": 65.0, "Valid": true }, "Credits": { "Valid": false } }));
        assert_eq!(skipper, vec![json!({ "kind": "intro", "start": 5.0, "end": 65.0 })]);
    }

    #[test]
    fn tracks_with_mpv_numbers() {
        let t = tracks_of(&json!({ "DefaultAudioStreamIndex": 2, "DefaultSubtitleStreamIndex": 4, "MediaStreams": [
            { "Index": 0, "Type": "Video" },
            { "Index": 1, "Type": "Audio", "DisplayTitle": "English" },
            { "Index": 2, "Type": "Audio", "DisplayTitle": "Deutsch" },
            { "Index": 3, "Type": "Subtitle", "Codec": "subrip", "DisplayTitle": "English" },
            { "Index": 4, "Type": "Subtitle", "Codec": "srt", "IsExternal": true, "DisplayTitle": "Deutsch (external)" },
            { "Index": 5, "Type": "Subtitle", "Codec": "pgssub", "IsExternal": true }
        ]}));
        assert_eq!(t["audio"][1]["ord"], 2);
        assert_eq!(t["audioIndex"], 2);
        assert_eq!(t["subs"].as_array().unwrap().len(), 2);
        assert_eq!(t["subs"][0]["ord"], 1);
        assert_eq!(t["subs"][1]["external"], true);
        assert_eq!(t["subIndex"], 4);
    }

    #[test]
    fn pictures_only_of_items() {
        assert!(picture("../etc/passwd/Primary/300").is_err());
        assert!(picture("0123456789abcdef0123456789abcdef/Logo/300").is_err());
        assert!(picture("0123456789abcdef0123456789abcdef/Primary").is_err());
    }

    /// Against a made-up server on this PC (GC_FAKE_JELLYFIN=127.0.0.1:8096,
    /// with XDG_CONFIG_HOME pointing at a scratch folder): the whole way
    /// from signing in to signing out.
    #[test]
    #[ignore]
    fn a_made_up_server_from_start_to_end() {
        let server = std::env::var("GC_FAKE_JELLYFIN").expect("GC_FAKE_JELLYFIN");
        assert!(sign_in(&server, "me", "wrong").unwrap_err().contains("Wrong user name"));
        let a = sign_in(&server, "me", "pw").unwrap();
        assert_eq!(a.server_name, "Fake home server");
        assert_eq!(load_account().unwrap().token, "tok123");
        #[allow(clippy::unnecessary_cast)]
        let mode = std::os::unix::fs::PermissionsExt::mode(&std::fs::metadata(account_file().unwrap()).unwrap().permissions()) & 0o777;
        assert_eq!(mode, 0o600, "only the user reads the key");
        let resume = continue_watching(&a).unwrap();
        assert_eq!(resume.len(), 2, "the older path when the newer one is missing");
        assert_eq!(next_up(&a).unwrap().len(), 1);
        let libs = libraries(&a).unwrap();
        assert_eq!(libs.len(), 2, "music left out");
        let shows = Folder { id: libs[1]["id"].as_str().unwrap().into(), kind: "lib".into(), collection: "tvshows".into(), series_id: String::new() };
        let (series, total) = folder(&a, &shows, 0).unwrap();
        assert_eq!((series.len(), total), (1, 1));
        let next = next_episode(&a, &"3".repeat(32), &"2".repeat(32)).unwrap().unwrap();
        assert_eq!(next["id"], "7".repeat(32));
        let info = playback_info(&a, &"1".repeat(32)).unwrap();
        assert_eq!(tracks_of(&info["MediaSources"][0])["subs"][0]["external"], true);
        assert_eq!(skip_segments(&a, &"1".repeat(32)).len(), 1);
        report(&a, "start", &"1".repeat(32), "", "sess1", 3.0, false, false).unwrap();
        set_played(&a, &"1".repeat(32), true).unwrap();
        assert!(picture(&format!("{}/Primary/240", "1".repeat(32))).unwrap().starts_with(&[0xff, 0xd8]));
        sign_out();
        assert!(load_account().is_none());
    }
}
