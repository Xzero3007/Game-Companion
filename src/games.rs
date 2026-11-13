//! The Games tab and game detection: the games Steam, Lutris and Heroic
//! have installed, read from their files on disk (nothing is fetched, and
//! the launchers' files are only read), the user's own entries, and which
//! game runs now, from `/proc` (only read: nothing is sent to a game).

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// One game in the library (or a built-in one, for detection only).
#[derive(Debug, Clone, PartialEq)]
pub struct Game {
    /// Stable: "steam:<appid>", "lutris:<id>", "heroic:<runner>:<app>",
    /// "own:<n>", or "known:<key>" for a built-in game no launcher lists.
    pub id: String,
    pub name: String,
    /// "steam", "lutris", "heroic", "own" or "known".
    pub launcher: String,
    /// What starts it: a launcher's address, or an own entry's command line.
    pub launch: String,
    /// Process names that mean it runs (`comm`, or argv[0]'s file name).
    pub processes: Vec<String>,
    /// Its Steam app id: Steam's `reaper` carries it while the game runs.
    pub steam_appid: Option<u32>,
    /// A cover picture already on disk (the launchers' own caches).
    pub picture: Option<PathBuf>,
    /// The built-in game it is (`Known::key`).
    pub known: Option<&'static str>,
    /// Folders whose paths in a process's command line mean it runs, as
    /// lower-case needles ending in "/" (Steam's "/steamapps/common/<dir>/",
    /// a Lutris or Heroic install folder).
    pub dirs: Vec<String>,
    /// What it brings to the Streams panel: a Twitch category and YouTube
    /// search words (own choice, else the built-in game's).
    pub twitch: String,
    pub youtube: String,
    /// When it starts: show the hub, start the radio.
    pub show_on_start: bool,
    pub radio_on_start: bool,
    /// Installed: false for a game the launcher knows but has not installed
    /// (its `launch` then opens the launcher's install for it, and
    /// detection leaves it out).
    pub installed: bool,
    /// The public address of its cover, for downloading missing covers
    /// later (not used yet: nothing is fetched without the person's yes).
    #[allow(dead_code)]
    pub cover_url: Option<String>,
    /// Where a not-installed game was found ("" for the plain case).
    pub note: String,
}

impl Game {
    pub fn new(id: impl Into<String>, name: impl Into<String>, launcher: &str, launch: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            launcher: launcher.into(),
            launch: launch.into(),
            processes: Vec::new(),
            steam_appid: None,
            picture: None,
            known: None,
            dirs: Vec::new(),
            twitch: String::new(),
            youtube: String::new(),
            show_on_start: true,
            radio_on_start: false,
            installed: true,
            cover_url: None,
            note: String::new(),
        }
    }
}

/// A game Game Companion knows: how to find it, and what it brings to the
/// Streams panel.
#[derive(Debug, PartialEq)]
pub struct Known {
    pub key: &'static str,
    pub name: &'static str,
    pub steam_appid: Option<u32>,
    pub processes: &'static [&'static str],
    /// Its Twitch category and its YouTube search words.
    pub twitch: &'static str,
    pub youtube: &'static str,
}

pub const KNOWN: &[Known] = &[
    Known {
        key: "aion2",
        name: "AION 2",
        steam_appid: None,
        // As the meter finds it (procfs::is_aion2_process): the Wine
        // process named AION2.exe; its launcher is not the game.
        processes: &["AION2.exe"],
        twitch: "AION 2",
        youtube: "AION 2",
    },
    Known {
        key: "poe2",
        name: "Path of Exile 2",
        steam_appid: Some(2_694_490),
        processes: &["PathOfExile.exe", "PathOfExile_x64.exe", "PathOfExileSteam.exe", "PathOfExile_x64Steam.exe"],
        twitch: "Path of Exile 2",
        youtube: "Path of Exile 2",
    },
];

/// A game the user added by hand (settings `games.own`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct OwnGame {
    /// Its number: the game's id is "own:<n>".
    pub id: u32,
    pub name: String,
    /// The command line that starts it (split like a shell, never run by one).
    pub command: String,
    pub processes: Vec<String>,
    /// Its Twitch category and YouTube search words ("" for the built-in
    /// game's, if it is one).
    pub twitch: String,
    pub youtube: String,
    pub show_on_start: bool,
    pub radio_on_start: bool,
}

impl Default for OwnGame {
    fn default() -> Self {
        Self {
            id: 0,
            name: String::new(),
            command: String::new(),
            processes: Vec::new(),
            twitch: String::new(),
            youtube: String::new(),
            show_on_start: true,
            radio_on_start: false,
        }
    }
}

/// The same choices for a launcher's game (settings `games.options`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct GameOptions {
    pub twitch: String,
    pub youtube: String,
    pub show_on_start: bool,
    pub radio_on_start: bool,
}

impl Default for GameOptions {
    fn default() -> Self {
        Self { twitch: String::new(), youtube: String::new(), show_on_start: true, radio_on_start: false }
    }
}

/// The Games tab's settings.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct GamesSettings {
    pub own: Vec<OwnGame>,
    /// Games hidden from the library, by id (still detected).
    pub hidden: BTreeSet<String>,
    /// Games marked as favourites, by id.
    pub favorites: BTreeSet<String>,
    /// When each game last started (unix seconds), by id.
    pub last_played: BTreeMap<String, u64>,
    /// Choices for launchers' (and built-in) games, by id.
    pub options: BTreeMap<String, GameOptions>,
    /// The saved layout (Settings → Layouts) each game loads when it
    /// starts, by id.
    pub layouts: BTreeMap<String, String>,
    /// The tab lists only installed games.
    pub installed_only: bool,
}

/// A name for comparing: lower case letters and digits only
/// ("AION 2" and "Aion2" are the same).
fn plain(name: &str) -> String {
    name.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
}

/// The built-in game a library game is: by Steam app id, else by name.
pub fn match_known(name: &str, steam_appid: Option<u32>) -> Option<&'static Known> {
    if let Some(id) = steam_appid {
        if let Some(k) = KNOWN.iter().find(|k| k.steam_appid == Some(id)) {
            return Some(k);
        }
    }
    let name = plain(name);
    KNOWN.iter().find(|k| !name.is_empty() && plain(k.name) == name)
}

/// Process names too general to mean any one game.
const GENERAL: &[&str] = &[
    "sh", "bash", "zsh", "env", "python", "python3", "java", "mono", "wine", "wine64", "steam", "flatpak", "lutris", "heroic",
    "gamescope", "gamemoderun", "xdg-open",
];

/// The process name an executable runs under; None for scripts and
/// interpreters, which would match more than the game.
pub fn process_name(executable: &str) -> Option<String> {
    let name = executable.trim().rsplit(['/', '\\']).next()?.trim();
    let lower = name.to_ascii_lowercase();
    let script = [".sh", ".py", ".bat", ".cmd", ".desktop"].iter().any(|ext| lower.ends_with(ext));
    (!name.is_empty() && !script && !GENERAL.contains(&lower.as_str())).then(|| name.to_string())
}

// ---------------------------------------------------------------- VDF ----

/// Valve's KeyValues text (`.vdf`, `.acf`): a key and a string or a block.
#[derive(Debug, Clone, PartialEq)]
pub enum Vdf {
    Str(String),
    Map(Vec<(String, Vdf)>),
}

impl Vdf {
    /// A child by key, ignoring case.
    pub fn get(&self, key: &str) -> Option<&Vdf> {
        match self {
            Vdf::Map(items) => items.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v),
            Vdf::Str(_) => None,
        }
    }

    pub fn str(&self, key: &str) -> Option<&str> {
        match self.get(key)? {
            Vdf::Str(s) => Some(s),
            Vdf::Map(_) => None,
        }
    }

    pub fn items(&self) -> &[(String, Vdf)] {
        match self {
            Vdf::Map(items) => items,
            Vdf::Str(_) => &[],
        }
    }
}

/// Reads KeyValues text tolerantly: comments, unquoted words, escapes and
/// missing closing braces are all fine; the top level is a block.
pub fn parse_vdf(text: &str) -> Vdf {
    #[derive(PartialEq)]
    enum Token {
        Open,
        Close,
        Word(String),
    }
    let mut tokens = Vec::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '{' => tokens.push(Token::Open),
            '}' => tokens.push(Token::Close),
            '"' => {
                let mut word = String::new();
                while let Some(c) = chars.next() {
                    match c {
                        '"' => break,
                        '\\' => match chars.next() {
                            Some('n') => word.push('\n'),
                            Some('t') => word.push('\t'),
                            Some(other) => word.push(other),
                            None => break,
                        },
                        _ => word.push(c),
                    }
                }
                tokens.push(Token::Word(word));
            }
            '/' if chars.peek() == Some(&'/') => {
                for c in chars.by_ref() {
                    if c == '\n' {
                        break;
                    }
                }
            }
            c if c.is_whitespace() => {}
            c => {
                let mut word = String::from(c);
                while let Some(&c) = chars.peek() {
                    if c.is_whitespace() || c == '{' || c == '}' || c == '"' {
                        break;
                    }
                    word.push(c);
                    chars.next();
                }
                // [$WIN32]-style conditions belong to the line before.
                if !(word.starts_with('[') && word.ends_with(']')) {
                    tokens.push(Token::Word(word));
                }
            }
        }
    }
    fn block(tokens: &mut std::iter::Peekable<std::vec::IntoIter<Token>>) -> Vec<(String, Vdf)> {
        let mut items = Vec::new();
        while let Some(token) = tokens.next() {
            match token {
                Token::Close => break,
                Token::Open => {
                    // A block without a key: keep its contents out of the way.
                    block(tokens);
                }
                Token::Word(key) => match tokens.peek() {
                    Some(Token::Open) => {
                        tokens.next();
                        items.push((key, Vdf::Map(block(tokens))));
                    }
                    Some(Token::Word(_)) => {
                        if let Some(Token::Word(value)) = tokens.next() {
                            items.push((key, Vdf::Str(value)));
                        }
                    }
                    _ => {}
                },
            }
        }
        items
    }
    Vdf::Map(block(&mut tokens.into_iter().peekable()))
}

fn read_vdf(path: &Path) -> Option<Vdf> {
    std::fs::read_to_string(path).ok().map(|t| parse_vdf(&t))
}

// -------------------------------------------------------------- Steam ----

/// Steam's own tools that sit among the games.
const STEAM_TOOLS: &[u32] = &[228_980, 1_070_560, 1_391_110, 1_628_350, 1_493_710, 2_180_100, 1_826_330, 1_161_040, 2_348_590, 3_658_110];

fn is_steam_tool(appid: u32, name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    STEAM_TOOLS.contains(&appid)
        || lower.starts_with("proton ")
        || lower == "proton"
        || lower.starts_with("steam linux runtime")
        || lower.starts_with("steamworks common redistributables")
        || lower.starts_with("steam runtime")
}

/// The Steam folders there are: native, the `~/.steam` links, Flatpak.
pub(crate) fn steam_roots(home: &Path) -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = Vec::new();
    for rel in [".local/share/Steam", ".steam/steam", ".steam/root", ".var/app/com.valvesoftware.Steam/.local/share/Steam"] {
        let Ok(root) = home.join(rel).canonicalize() else { continue };
        if root.join("steamapps").is_dir() && !roots.contains(&root) {
            roots.push(root);
        }
    }
    roots
}

/// The library folders a Steam folder lists (new and old
/// `libraryfolders.vdf`), the folder itself first.
pub(crate) fn steam_libraries(root: &Path) -> Vec<PathBuf> {
    let mut libraries = vec![root.to_path_buf()];
    for file in [root.join("steamapps/libraryfolders.vdf"), root.join("config/libraryfolders.vdf")] {
        let Some(vdf) = read_vdf(&file) else { continue };
        let Some((_, top)) = vdf.items().first() else { continue };
        for (key, value) in top.items() {
            if !key.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let path = match value {
                Vdf::Str(path) => Some(path.as_str()),
                Vdf::Map(_) => value.str("path"),
            };
            if let Some(path) = path.filter(|p| !p.is_empty()) {
                libraries.push(PathBuf::from(path));
            }
        }
    }
    libraries
}

/// Cover names in Steam's cache, best first: the tall library picture
/// (and its double size), the library capsule, the wide headers.
const STEAM_COVERS: [&str; 6] =
    ["library_600x900.jpg", "library_600x900_2x.jpg", "library_capsule.jpg", "header.jpg", "library_header.jpg", "library_header_2x.jpg"];

/// A game's cover in Steam's cache: the old flat names
/// (`<appid>_library_600x900.jpg`) and the newer folder per game
/// (`<appid>/<name>`, or one folder deeper, `<appid>/<hash>/<name>`).
fn steam_picture(roots: &[PathBuf], appid: u32) -> Option<PathBuf> {
    for root in roots {
        let cache = root.join("appcache/librarycache");
        let folder = cache.join(appid.to_string());
        let deeper: Vec<PathBuf> = std::fs::read_dir(&folder)
            .map(|entries| entries.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect())
            .unwrap_or_default();
        for name in STEAM_COVERS {
            let flat = cache.join(format!("{appid}_{name}"));
            if flat.is_file() {
                return Some(flat);
            }
            if folder.join(name).is_file() {
                return Some(folder.join(name));
            }
            if let Some(found) = deeper.iter().map(|d| d.join(name)).find(|p| p.is_file()) {
                return Some(found);
            }
        }
    }
    None
}

/// The public address of a Steam game's tall cover (Steam's store
/// pictures). Only for a later download of missing covers, once the person
/// agrees: nothing calls it to fetch anything yet.
pub fn steam_cover_url(appid: u32) -> String {
    format!("https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg")
}

/// The Steam account that signed in last (`loginusers.vdf`, MostRecent),
/// as its `userdata` folder name (the 32-bit account id).
fn steam_recent_user(root: &Path) -> Option<String> {
    let vdf = read_vdf(&root.join("config/loginusers.vdf"))?;
    let users = vdf.get("users")?;
    let (id64, _) = users.items().iter().find(|(_, u)| u.str("MostRecent") == Some("1")).or_else(|| users.items().first())?;
    let account = id64.trim().parse::<u64>().ok()?.checked_sub(76_561_197_960_265_728)?;
    Some(account.to_string())
}

/// App ids this computer's Steam has seen for the account: apps it ran or
/// set (localconfig.vdf, sharedconfig.vdf), apps it keeps library data or
/// covers for. Owned games mostly, but not only (free weekends, demos,
/// tools): `read_steam_known` keeps only what appinfo calls a game.
pub(crate) fn steam_seen_apps(root: &Path) -> BTreeSet<u32> {
    let number = |s: &str| s.trim().parse::<u32>().ok().filter(|&n| n > 0);
    let mut apps = BTreeSet::new();
    let userdata = root.join("userdata");
    let users: Vec<PathBuf> = match steam_recent_user(root).map(|u| userdata.join(u)).filter(|p| p.is_dir()) {
        Some(user) => vec![user],
        None => std::fs::read_dir(&userdata)
            .map(|e| {
                e.flatten()
                    .map(|e| e.path())
                    .filter(|p| p.file_name().and_then(|n| n.to_str()).and_then(number).is_some())
                    .collect()
            })
            .unwrap_or_default(),
    };
    let steam_apps = |vdf: &Vdf| -> Vec<u32> {
        let Some((_, top)) = vdf.items().first() else { return Vec::new() };
        let apps = top.get("Software").and_then(|s| s.get("Valve")).and_then(|v| v.get("Steam")).and_then(|s| s.get("apps"));
        apps.map(|a| a.items().iter().filter_map(|(k, _)| number(k)).collect()).unwrap_or_default()
    };
    for user in users {
        for file in [user.join("config/localconfig.vdf"), user.join("7/remote/sharedconfig.vdf")] {
            if let Some(vdf) = read_vdf(&file) {
                apps.extend(steam_apps(&vdf));
            }
        }
        // config/librarycache/<appid>.json: the library's data per app.
        if let Ok(entries) = std::fs::read_dir(user.join("config/librarycache")) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                if let Some(id) = name.to_str().and_then(|n| n.strip_suffix(".json")).and_then(number) {
                    apps.insert(id);
                }
            }
        }
    }
    // appcache/librarycache: "<appid>" folders and "<appid>_<name>" files.
    if let Ok(entries) = std::fs::read_dir(root.join("appcache/librarycache")) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            let id = name.split(['_', '.']).next().and_then(number);
            apps.extend(id);
        }
    }
    apps
}

/// Games this computer's Steam knows for the account but has not
/// installed (see `steam_seen_apps`): only apps whose appinfo type is
/// "game", without Steam's tools. Their address opens Steam's install.
pub fn read_steam_known(home: &Path, installed: &[Game]) -> Vec<Game> {
    let roots = steam_roots(home);
    let mut games: Vec<Game> = Vec::new();
    for root in &roots {
        let have: BTreeSet<u32> =
            installed.iter().chain(games.iter()).filter_map(|g| g.steam_appid).collect();
        let wanted: BTreeSet<u32> = steam_seen_apps(root).into_iter().filter(|id| !have.contains(id)).collect();
        let metas = crate::appinfo::lookup(&root.join("appcache/appinfo.vdf"), &wanted);
        for appid in wanted {
            let Some(meta) = metas.get(&appid) else { continue };
            if meta.kind != "game" || meta.name.is_empty() || is_steam_tool(appid, &meta.name) {
                continue;
            }
            let mut game = Game::new(format!("steam:{appid}"), meta.name.clone(), "steam", format!("steam://install/{appid}"));
            game.steam_appid = Some(appid);
            game.installed = false;
            game.picture = steam_picture(&roots, appid);
            game.cover_url = Some(steam_cover_url(appid));
            game.note = "Known to Steam on this PC".into();
            games.push(game);
        }
    }
    games
}

/// Steam's installed games, from every library's `appmanifest_*.acf`.
pub fn read_steam(home: &Path) -> Vec<Game> {
    let roots = steam_roots(home);
    let mut seen_libraries = Vec::new();
    let mut games: Vec<Game> = Vec::new();
    for root in &roots {
        for library in steam_libraries(root) {
            let library = library.canonicalize().unwrap_or(library);
            if seen_libraries.contains(&library) {
                continue;
            }
            seen_libraries.push(library.clone());
            let Ok(entries) = std::fs::read_dir(library.join("steamapps")) else { continue };
            let mut files: Vec<PathBuf> = entries
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("appmanifest_") && n.ends_with(".acf"))
                })
                .collect();
            files.sort();
            for file in files {
                let Some(acf) = read_vdf(&file) else { continue };
                let Some(state) = acf.get("AppState") else { continue };
                let Some(appid) = state.str("appid").and_then(|a| a.trim().parse::<u32>().ok()) else { continue };
                let name = state.str("name").unwrap_or("").trim().to_string();
                let installdir = state.str("installdir").unwrap_or("").trim().trim_matches(['/', '\\']).to_lowercase();
                if name.is_empty() || is_steam_tool(appid, &name) || games.iter().any(|g| g.steam_appid == Some(appid)) {
                    continue;
                }
                let mut game = Game::new(format!("steam:{appid}"), name, "steam", format!("steam://rungameid/{appid}"));
                game.steam_appid = Some(appid);
                game.picture = steam_picture(&roots, appid);
                game.cover_url = Some(steam_cover_url(appid));
                if !installdir.is_empty() && !installdir.contains(['/', '\\']) {
                    game.dirs.push(format!("/steamapps/common/{installdir}/"));
                }
                games.push(game);
            }
        }
    }
    games
}

// ------------------------------------------------------------- Lutris ----

/// Lutris's games, from its `pga.db`, opened read-only: installed ones,
/// the ones it lists as not installed, and the games of its services
/// (GOG, Epic, the lutris.net library, ...; not Steam's, which the Steam
/// tab has) that are not in its list yet.
pub fn read_lutris(home: &Path) -> Vec<Game> {
    let places = [
        (home.join(".local/share/lutris"), home.join(".cache/lutris")),
        (home.join(".var/app/net.lutris.Lutris/data/lutris"), home.join(".var/app/net.lutris.Lutris/cache/lutris")),
    ];
    let mut games: Vec<Game> = Vec::new();
    for (data, cache) in places {
        let db = data.join("pga.db");
        if !db.is_file() {
            continue;
        }
        let picture = |slug: &str| -> Option<PathBuf> {
            if slug.is_empty() || slug.contains('/') {
                return None;
            }
            [data.join("coverart"), cache.join("coverart"), data.join("banners"), cache.join("banners")]
                .iter()
                .flat_map(|dir| ["jpg", "png"].map(|ext| dir.join(format!("{slug}.{ext}"))))
                .find(|p| p.is_file())
        };
        let (rows, services) = lutris_rows(&db);
        let mut slugs: BTreeSet<String> = BTreeSet::new();
        let mut names: BTreeSet<String> = BTreeSet::new();
        for row in rows {
            let id = format!("lutris:{}", row.id);
            if row.name.trim().is_empty() || games.iter().any(|g| g.id == id) {
                continue;
            }
            slugs.insert(row.slug.clone());
            names.insert(plain(&row.name));
            let launch = if row.installed {
                format!("lutris:rungameid/{}", row.id)
            } else if !row.slug.is_empty() {
                format!("lutris:{}", row.slug)
            } else {
                // Lutris asks to install a game it lists as not installed.
                format!("lutris:rungameid/{}", row.id)
            };
            let mut game = Game::new(id, row.name.trim(), "lutris", launch);
            game.picture = picture(&row.slug);
            game.installed = row.installed;
            if row.installed {
                game.processes = process_name(&row.executable).into_iter().collect();
                game.dirs = dir_needle(&row.directory).into_iter().collect();
            }
            games.push(game);
        }
        for s in services {
            let slug = if s.lutris_slug.is_empty() { s.slug.clone() } else { s.lutris_slug.clone() };
            if s.name.trim().is_empty() || slug.is_empty() || slugs.contains(&slug) || names.contains(&plain(&s.name)) {
                continue;
            }
            let id = format!("lutris:{}:{}", s.service, s.appid);
            if games.iter().any(|g| g.id == id) {
                continue;
            }
            slugs.insert(slug.clone());
            let mut game = Game::new(id, s.name.trim(), "lutris", format!("lutris:{slug}"));
            game.picture = picture(&slug).or_else(|| picture(&s.slug));
            game.installed = false;
            game.note = format!("In Lutris's {} library", lutris_service_name(&s.service));
            games.push(game);
        }
    }
    games
}

fn lutris_service_name(service: &str) -> String {
    match service {
        "gog" => "GOG".into(),
        "egs" => "Epic".into(),
        "lutris" => "lutris.net".into(),
        "humblebundle" => "Humble".into(),
        "itchio" => "itch.io".into(),
        "ea_app" | "origin" => "EA".into(),
        "ubisoft" => "Ubisoft".into(),
        "battlenet" => "Battle.net".into(),
        "amazon" => "Amazon".into(),
        other => other.to_string(),
    }
}

struct LutrisRow {
    id: i64,
    name: String,
    slug: String,
    executable: String,
    directory: String,
    installed: bool,
}

struct LutrisServiceGame {
    service: String,
    appid: String,
    name: String,
    slug: String,
    lutris_slug: String,
}

/// The games and the service games: first as an unchanging file (no
/// locks at all, so Lutris is never held up), else plainly read-only. An
/// older database without `service_games` gives only the games.
fn lutris_rows(db: &Path) -> (Vec<LutrisRow>, Vec<LutrisServiceGame>) {
    use rusqlite::{Connection, OpenFlags};
    let games = |conn: &Connection| -> rusqlite::Result<Vec<LutrisRow>> {
        let mut statement = conn.prepare(
            "SELECT id, COALESCE(name, ''), COALESCE(slug, ''), COALESCE(executable, ''), COALESCE(directory, ''), \
             COALESCE(installed, 0) FROM games",
        )?;
        let rows = statement.query_map([], |r| {
            Ok(LutrisRow {
                id: r.get(0)?,
                name: r.get(1)?,
                slug: r.get(2)?,
                executable: r.get(3)?,
                directory: r.get(4)?,
                installed: r.get::<_, i64>(5)? != 0,
            })
        })?;
        rows.collect()
    };
    let services = |conn: &Connection| -> rusqlite::Result<Vec<LutrisServiceGame>> {
        let mut statement = conn.prepare(
            "SELECT COALESCE(service, ''), COALESCE(CAST(appid AS TEXT), ''), COALESCE(name, ''), COALESCE(slug, ''), \
             COALESCE(lutris_slug, '') FROM service_games WHERE COALESCE(service, '') != 'steam'",
        )?;
        let rows = statement.query_map([], |r| {
            Ok(LutrisServiceGame { service: r.get(0)?, appid: r.get(1)?, name: r.get(2)?, slug: r.get(3)?, lutris_slug: r.get(4)? })
        })?;
        rows.collect()
    };
    let read_only = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    let uri = format!("file:{}?immutable=1", uri_path(db));
    let both = |conn: Connection| -> rusqlite::Result<(Vec<LutrisRow>, Vec<LutrisServiceGame>)> {
        let list = games(&conn)?;
        Ok((list, services(&conn).unwrap_or_default()))
    };
    Connection::open_with_flags(uri, read_only | OpenFlags::SQLITE_OPEN_URI)
        .and_then(both)
        .or_else(|_| Connection::open_with_flags(db, read_only).and_then(both))
        .unwrap_or_default()
}

/// A path for an SQLite URI (`?` and `#` would end it).
pub(crate) fn uri_path(path: &Path) -> String {
    encode_path(path)
}

// ------------------------------------------------------------- Heroic ----

fn read_json(path: &Path) -> Option<serde_json::Value> {
    serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()
}

fn heroic_game(runner: &str, app: &str, name: &str, executable: &str, folder: &str, picture: Option<PathBuf>) -> Game {
    let launch = format!("heroic://launch?appName={}&runner={runner}", encode_query(app));
    let mut game = Game::new(format!("heroic:{runner}:{app}"), name.trim(), "heroic", launch);
    game.processes = process_name(executable).into_iter().collect();
    game.dirs = dir_needle(folder).into_iter().collect();
    game.picture = picture;
    game
}

/// A folder's last part, for a game whose name is nowhere else.
fn folder_name(path: &str) -> String {
    path.trim_end_matches(['/', '\\']).rsplit(['/', '\\']).next().unwrap_or("").to_string()
}

/// A picture in Heroic's `images-cache`: each file is named by the
/// SHA-256 of the address it was downloaded from (Heroic's
/// `images_cache.ts`), without an extension.
fn heroic_cached(base: &Path, url: &str) -> Option<PathBuf> {
    use sha2::{Digest, Sha256};
    if !url.starts_with("http") {
        return None;
    }
    let hash: String = Sha256::digest(url.as_bytes()).iter().map(|b| format!("{b:02x}")).collect();
    let path = base.join("images-cache").join(hash);
    path.is_file().then_some(path)
}

/// A library entry's cover: a cached copy of one of its art addresses (the
/// card's own form first: Heroic asks Epic for a resized square picture),
/// or a cover that is a file on this computer (added games).
fn heroic_picture(base: &Path, runner: &str, game: &serde_json::Value) -> Option<PathBuf> {
    let art = |key: &str| game.get(key).and_then(serde_json::Value::as_str).unwrap_or("").to_string();
    let (cover, square) = (art("art_cover"), art("art_square"));
    let mut urls = Vec::new();
    if runner == "legendary" && !square.is_empty() {
        urls.push(format!("{square}?h=400&resize=1&w=300"));
    }
    urls.extend([square.clone(), cover.clone(), art("art_background")]);
    urls.iter().filter(|u| !u.is_empty()).find_map(|u| heroic_cached(base, u)).or_else(|| {
        [cover, square]
            .into_iter()
            .map(|p| PathBuf::from(p.strip_prefix("file://").unwrap_or(&p)))
            .find(|p| p.is_absolute() && p.is_file())
    })
}

/// A library entry's public cover address (for a later download).
fn heroic_cover_url(game: &serde_json::Value) -> Option<String> {
    ["art_square", "art_cover"]
        .iter()
        .filter_map(|k| game.get(*k).and_then(serde_json::Value::as_str))
        .find(|u| u.starts_with("https://"))
        .map(str::to_string)
}

/// Heroic's games: Epic (Legendary), GOG, Amazon (Nile) and its own added
/// ones. Installed ones from each store's installed list; the rest of each
/// store's library (`store_cache/*_library.json`) as not installed (Heroic
/// asks to install them when started). Missing or odd files give nothing.
pub fn read_heroic(home: &Path) -> Vec<Game> {
    use serde_json::Value;
    let s = |v: &Value, key: &str| v.get(key).and_then(Value::as_str).unwrap_or("").to_string();
    let dlc = |v: &Value| {
        v.get("is_dlc").and_then(Value::as_bool) == Some(true)
            || v.get("install").and_then(|i| i.get("is_dlc")).and_then(Value::as_bool) == Some(true)
    };
    let mut games: Vec<Game> = Vec::new();
    for base in [home.join(".config/heroic"), home.join(".var/app/com.heroicgameslauncher.hgl/config/heroic")] {
        if !base.is_dir() {
            continue;
        }
        let mut add = |game: Game| {
            if !game.name.is_empty() && !games.iter().any(|g| g.id == game.id) {
                games.push(game);
            }
        };
        // Epic: { appName: { app_name, title, executable, is_dlc } }.
        if let Some(Value::Object(map)) = read_json(&base.join("legendaryConfig/legendary/installed.json")) {
            for (key, game) in &map {
                if dlc(game) {
                    continue;
                }
                let app = Some(s(game, "app_name")).filter(|a| !a.is_empty()).unwrap_or_else(|| key.clone());
                add(heroic_game("legendary", &app, &s(game, "title"), &s(game, "executable"), &s(game, "install_path"), None));
            }
        }
        // GOG: { installed: [{ appName, install_path, is_dlc }] }, names in library.json.
        let gog_names: Vec<(String, String)> = read_json(&base.join("gog_store/library.json"))
            .and_then(|v| v.get("games").and_then(Value::as_array).cloned())
            .unwrap_or_default()
            .iter()
            .map(|g| (s(g, "app_name"), s(g, "title")))
            .collect();
        if let Some(list) = read_json(&base.join("gog_store/installed.json")).and_then(|v| v.get("installed").cloned()) {
            for game in list.as_array().map(Vec::as_slice).unwrap_or_default() {
                let app = s(game, "appName");
                if app.is_empty() || dlc(game) {
                    continue;
                }
                let name = gog_names
                    .iter()
                    .find(|(a, t)| *a == app && !t.is_empty())
                    .map(|(_, t)| t.clone())
                    .unwrap_or_else(|| folder_name(&s(game, "install_path")));
                add(heroic_game("gog", &app, &name, &s(game, "executable"), &s(game, "install_path"), None));
            }
        }
        // Amazon: [{ id, path }], names in library.json ([{ id, product: { title } }]).
        let nile_names: Vec<(String, String)> = read_json(&base.join("nile_config/nile/library.json"))
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default()
            .iter()
            .map(|g| (s(g, "id"), g.get("product").map(|p| s(p, "title")).unwrap_or_default()))
            .collect();
        if let Some(Value::Array(list)) = read_json(&base.join("nile_config/nile/installed.json")) {
            for game in &list {
                let app = s(game, "id");
                if app.is_empty() {
                    continue;
                }
                let name = nile_names
                    .iter()
                    .find(|(a, t)| *a == app && !t.is_empty())
                    .map(|(_, t)| t.clone())
                    .unwrap_or_else(|| folder_name(&s(game, "path")));
                add(heroic_game("nile", &app, &name, "", &s(game, "path"), None));
            }
        }
        // The stores' libraries as Heroic keeps them (its CacheStore,
        // electron-store JSON): { library | games: [GameInfo] }, GameInfo
        // { app_name, title, runner, is_installed, art_cover, art_square,
        // install: { executable, install_path, is_dlc } }. Added games:
        // sideload_apps/library.json { games: [GameInfo] }.
        let libraries = [
            ("legendary", base.join("store_cache/legendary_library.json"), "library"),
            ("gog", base.join("store_cache/gog_library.json"), "games"),
            ("nile", base.join("store_cache/nile_library.json"), "library"),
            ("sideload", base.join("sideload_apps/library.json"), "games"),
        ];
        for (runner, file, key) in libraries {
            let Some(list) = read_json(&file).and_then(|v| v.get(key).cloned()) else { continue };
            for game in list.as_array().map(Vec::as_slice).unwrap_or_default() {
                let app = s(game, "app_name");
                if app.is_empty() || dlc(game) {
                    continue;
                }
                let id = format!("heroic:{runner}:{app}");
                let picture = heroic_picture(&base, runner, game);
                let cover_url = heroic_cover_url(game);
                if let Some(known) = games.iter_mut().find(|g| g.id == id) {
                    // Installed already: the library brings the cover.
                    if known.picture.is_none() {
                        known.picture = picture;
                    }
                    if known.cover_url.is_none() {
                        known.cover_url = cover_url;
                    }
                    continue;
                }
                let install = game.get("install").cloned().unwrap_or(Value::Null);
                let executable = s(&install, "executable");
                let folder = s(&install, "install_path");
                let mut entry = heroic_game(runner, &app, &s(game, "title"), &executable, &folder, picture);
                entry.cover_url = cover_url;
                // Its store's installed list is the truth; an entry it lacks
                // counts as installed only where the library says so (added
                // games: unless it says not).
                let flag = game.get("is_installed").and_then(Value::as_bool);
                entry.installed = if runner == "sideload" { flag != Some(false) } else { flag == Some(true) };
                if !entry.installed {
                    entry.processes.clear();
                    entry.dirs.clear();
                }
                if entry.name.is_empty() {
                    continue;
                }
                games.push(entry);
            }
        }
    }
    games
}

// ------------------------------------------------------------ library ----

/// Every launcher's games, installed or not (no own entries; see
/// `compose`).
pub fn read_library(home: &Path) -> Vec<Game> {
    let mut games = read_steam(home);
    let known = read_steam_known(home, &games);
    games.extend(known);
    games.extend(read_lutris(home));
    games.extend(read_heroic(home));
    games
}

/// The library as the tab shows it: own entries first, then the launchers'
/// games, each matched to a built-in game (whose process names it takes),
/// with the user's choices for it.
pub fn compose(scanned: &[Game], settings: &GamesSettings) -> Vec<Game> {
    let mut games: Vec<Game> = settings
        .own
        .iter()
        .map(|o| {
            let mut game = Game::new(format!("own:{}", o.id), o.name.clone(), "own", o.command.clone());
            game.processes = o.processes.clone();
            game.twitch = o.twitch.clone();
            game.youtube = o.youtube.clone();
            game.show_on_start = o.show_on_start;
            game.radio_on_start = o.radio_on_start;
            game
        })
        .collect();
    games.extend(scanned.iter().cloned().map(|mut game| {
        if let Some(o) = settings.options.get(&game.id) {
            game.twitch = o.twitch.clone();
            game.youtube = o.youtube.clone();
            game.show_on_start = o.show_on_start;
            game.radio_on_start = o.radio_on_start;
        } else {
            // Not chosen yet: only games with a module bring the hub up by
            // themselves (with autostart, not over every Steam game).
            game.show_on_start = match_known(&game.name, game.steam_appid).is_some();
        }
        game
    }));
    for game in &mut games {
        if let Some(k) = match_known(&game.name, game.steam_appid) {
            take_known(game, k);
        }
    }
    games
}

/// A built-in game's key, process names and (where none is chosen) presets.
fn take_known(game: &mut Game, k: &'static Known) {
    game.known = Some(k.key);
    for p in k.processes {
        if !game.processes.iter().any(|q| q.eq_ignore_ascii_case(p)) {
            game.processes.push((*p).to_string());
        }
    }
    if game.twitch.trim().is_empty() {
        game.twitch = k.twitch.into();
    }
    if game.youtube.trim().is_empty() {
        game.youtube = k.youtube.into();
    }
}

/// What detection looks for: the library's installed games, plus each
/// built-in game that none of them is ("known:<key>", with the user's
/// choices for that id). A game that is not installed cannot run.
pub fn watch_list(library: &[Game], settings: &GamesSettings) -> Vec<Game> {
    let mut list: Vec<Game> = library.iter().filter(|g| g.installed).cloned().collect();
    let library = list.clone();
    for k in KNOWN {
        if !library.iter().any(|g| g.known == Some(k.key)) {
            let mut game = Game::new(format!("known:{}", k.key), k.name, "known", "");
            game.steam_appid = k.steam_appid;
            if let Some(o) = settings.options.get(&game.id) {
                game.twitch = o.twitch.clone();
                game.youtube = o.youtube.clone();
                game.show_on_start = o.show_on_start;
                game.radio_on_start = o.radio_on_start;
            }
            take_known(&mut game, k);
            list.push(game);
        }
    }
    list
}

/// An install folder as a needle for command lines: lower case, "/" at the
/// end; None for folders too general to mean one game (fewer than three
/// parts, like "/home/p").
pub fn dir_needle(folder: &str) -> Option<String> {
    let folder = folder.trim().replace('\\', "/").to_lowercase();
    let folder = folder.trim_end_matches('/');
    let parts = folder.split('/').filter(|p| !p.is_empty()).count();
    (folder.starts_with('/') && parts >= 3).then(|| format!("{folder}/"))
}

// ---------------------------------------------------------- detection ----

/// The kernel keeps 15 bytes of a process name.
const COMM_LEN: usize = 15;

/// Wine and Proton processes: their argv[0] is worth reading.
fn looks_like_wine(comm: &str) -> bool {
    comm.ends_with(".exe") || comm.starts_with("wine") || comm.contains("preloader") || comm.starts_with("proton")
}

/// One command-line argument as a path to compare: lower case, "/" for
/// "\\", and Wine's "Z:" (the whole file system) dropped.
fn plain_arg(arg: &[u8]) -> String {
    let arg = String::from_utf8_lossy(arg).replace('\\', "/").to_lowercase();
    match arg.strip_prefix("z:") {
        Some(rest) if rest.starts_with('/') => rest.to_string(),
        _ => arg,
    }
}

/// How a process was matched to a game, surest first.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Sure {
    Certain,
    Name,
    Folder,
}

/// The detection table, built once per library (not per look at `/proc`).
#[derive(Debug, Default)]
pub struct Matcher {
    pub games: Vec<Game>,
    /// Lower-case process name to the first game with it.
    names: HashMap<String, usize>,
    /// Names longer than the kernel keeps, lower case.
    long_names: Vec<(String, usize)>,
    appids: HashMap<u32, usize>,
    dirs: Vec<(String, usize)>,
}

impl Matcher {
    pub fn new(games: Vec<Game>) -> Self {
        let mut m = Matcher::default();
        for (i, game) in games.iter().enumerate() {
            for p in &game.processes {
                let lower = p.to_lowercase();
                if lower.len() > COMM_LEN {
                    m.long_names.push((lower.clone(), i));
                }
                m.names.entry(lower).or_insert(i);
            }
            if let Some(id) = game.steam_appid {
                m.appids.entry(id).or_insert(i);
            }
            m.dirs.extend(game.dirs.iter().map(|d| (d.clone(), i)));
        }
        // A folder that holds another game's folder (a shared ~/Games or a
        // Wine prefix of several games) says nothing about which one runs.
        let all: Vec<(String, usize)> = m.dirs.clone();
        m.dirs.retain(|(d, i)| !all.iter().any(|(other, j)| j != i && other != d && other.starts_with(d.as_str())));
        m.games = games;
        m
    }

    /// The game a process belongs to, and how sure: Steam's `reaper` app id
    /// or a Steam install folder (Certain), a process name games can share
    /// (Name), another launcher's install folder (Folder: a file manager
    /// opened there counts too, so a name wins over it).
    fn process(&self, dir: &Path, comm: &str) -> Option<(usize, Sure)> {
        let comm = comm.to_lowercase();
        if let Some(&i) = self.names.get(&comm) {
            return Some((i, Sure::Name));
        }
        let reaper = comm == "reaper" && !self.appids.is_empty();
        // A name cut to 15 bytes: argv[0] says which one it is.
        let truncated = if comm.len() == COMM_LEN {
            self.long_names.iter().find(|(n, _)| n.starts_with(&comm)).map(|(_, i)| *i)
        } else {
            None
        };
        if !(reaper || truncated.is_some() || !self.dirs.is_empty() || looks_like_wine(&comm)) {
            return None;
        }
        let cmdline = std::fs::read(dir.join("cmdline")).unwrap_or_default();
        let mut args = cmdline.split(|&b| b == 0).filter(|a| !a.is_empty());
        if reaper {
            // reaper SteamLaunch AppId=<id> -- ...
            let appid = args
                .clone()
                .take_while(|a| *a != b"--")
                .find_map(|a| std::str::from_utf8(a).ok()?.strip_prefix("AppId=")?.parse::<u32>().ok());
            if let Some(&i) = appid.and_then(|id| self.appids.get(&id)) {
                return Some((i, Sure::Certain));
            }
        }
        let argv0 = args.next().map(plain_arg);
        if let Some(argv0) = &argv0 {
            // Only argv[0] for names: Proton's wrappers carry the game's path
            // further along.
            let file = argv0.rsplit('/').next().unwrap_or("").trim();
            if let Some(&i) = self.names.get(file) {
                return Some((i, Sure::Name));
            }
        } else if let Some(i) = truncated {
            // No command line to read (a zombie): the cut name alone.
            return Some((i, Sure::Name));
        }
        if self.dirs.is_empty() {
            return None;
        }
        // An install folder anywhere in the command line (a Proton game's
        // wrappers too: they run as long as it does).
        argv0.into_iter().chain(args.map(plain_arg)).find_map(|arg| {
            self.dirs.iter().find(|(needle, _)| arg.contains(needle.as_str())).map(|(needle, i)| {
                (*i, if needle.starts_with("/steamapps/common/") { Sure::Certain } else { Sure::Folder })
            })
        })
    }

    /// Which game runs now: reads each process's `comm`, and its `cmdline`
    /// when that can tell more (Wine, Steam's reaper, a cut name, or any
    /// process while some game is known by its folder). A certain match
    /// wins over a name; otherwise the earlier game in the list.
    pub fn scan(&self, proc_root: &Path) -> Option<&Game> {
        if self.games.is_empty() {
            return None;
        }
        let entries = std::fs::read_dir(proc_root).ok()?;
        let own_pid = std::process::id().to_string();
        let mut by_name: Option<usize> = None;
        let mut certain: Option<usize> = None;
        let mut by_folder: Option<usize> = None;
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            let Some(pid) = file_name.to_str() else { continue };
            if pid.is_empty() || !pid.bytes().all(|b| b.is_ascii_digit()) || pid == own_pid {
                continue;
            }
            let dir = entry.path();
            let Ok(comm) = std::fs::read_to_string(dir.join("comm")) else { continue };
            match self.process(&dir, comm.trim_end_matches('\n')) {
                Some((i, Sure::Certain)) => certain = Some(certain.map_or(i, |b| b.min(i))),
                Some((i, Sure::Name)) => by_name = Some(by_name.map_or(i, |b| b.min(i))),
                Some((i, Sure::Folder)) => by_folder = Some(by_folder.map_or(i, |b| b.min(i))),
                None => {}
            }
        }
        certain.or(by_name).or(by_folder).map(|i| &self.games[i])
    }
}

/// Which game runs now, by its id (see `Matcher::scan`; the app keeps
/// one `Matcher` per library instead).
#[cfg(test)]
pub fn scan_running(proc_root: &Path, games: &[Game]) -> Option<String> {
    Matcher::new(games.to_vec()).scan(proc_root).map(|g| g.id.clone())
}

// -------------------------------------------------------------- start ----

/// Splits a command line like a shell does (quotes, backslashes, `~/`),
/// without running one. None for unclosed quotes.
pub fn split_command(line: &str, home: Option<&Path>) -> Option<Vec<String>> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut in_word = false;
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match c {
            '\'' => {
                in_word = true;
                loop {
                    match chars.next()? {
                        '\'' => break,
                        c => word.push(c),
                    }
                }
            }
            '"' => {
                in_word = true;
                loop {
                    match chars.next()? {
                        '"' => break,
                        '\\' => match chars.next()? {
                            c @ ('"' | '\\' | '$' | '`') => word.push(c),
                            '\n' => {}
                            c => {
                                word.push('\\');
                                word.push(c);
                            }
                        },
                        c => word.push(c),
                    }
                }
            }
            '\\' => {
                in_word = true;
                match chars.next() {
                    Some('\n') | None => {}
                    Some(c) => word.push(c),
                }
            }
            c if c.is_whitespace() => {
                if in_word {
                    words.push(std::mem::take(&mut word));
                    in_word = false;
                }
            }
            '~' if !in_word && home.is_some() && matches!(chars.clone().next(), None | Some('/')) => {
                in_word = true;
                word.push_str(&home?.to_string_lossy());
            }
            c => {
                in_word = true;
                word.push(c);
            }
        }
    }
    if in_word {
        words.push(word);
    }
    Some(words)
}

/// A command split into leading `NAME=value` settings and the program
/// with its arguments.
pub fn command_parts(words: Vec<String>) -> (Vec<(String, String)>, Vec<String>) {
    let mut env = Vec::new();
    let mut rest = words.into_iter().peekable();
    while let Some(word) = rest.peek() {
        let Some((name, value)) = word.split_once('=') else { break };
        let valid = !name.is_empty()
            && !name.starts_with(|c: char| c.is_ascii_digit())
            && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
        if !valid {
            break;
        }
        env.push((name.to_string(), value.to_string()));
        rest.next();
    }
    (env, rest.collect())
}

/// The process names to look for, from what the user typed (commas or new
/// lines between them); without any, guessed from the command: its last
/// `.exe`, else the program's own name.
pub fn own_processes(typed: &str, command: &str) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    for name in typed.split([',', ';', '\n']).map(str::trim).filter(|n| !n.is_empty()) {
        if !names.iter().any(|n| n.eq_ignore_ascii_case(name)) {
            names.push(name.chars().take(200).collect());
        }
    }
    if names.is_empty() {
        let (_, words) = command_parts(split_command(command, None).unwrap_or_default());
        let exe = words.iter().rev().find(|w| w.to_ascii_lowercase().ends_with(".exe"));
        if let Some(name) = exe.or(words.first()).and_then(|w| process_name(w)) {
            names.push(name);
        }
    }
    names
}

// -------------------------------------------------------------- paths ----

fn encode_query(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn encode_path(path: &Path) -> String {
    use std::os::unix::ffi::OsStrExt;
    let mut out = String::new();
    for &b in path.as_os_str().as_bytes() {
        if b.is_ascii_alphanumeric() || b"-._~/".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A local picture as a `file://` address for QML.
pub fn file_url(path: &Path) -> String {
    format!("file://{}", encode_path(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-games-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write(path: &Path, text: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn acf(appid: u32, name: &str) -> String {
        format!("\"AppState\"\n{{\n\t\"appid\"\t\t\"{appid}\"\n\t\"name\"\t\t\"{name}\"\n\t\"installdir\"\t\t\"x\"\n}}\n")
    }

    #[test]
    fn reads_valve_text() {
        let v = parse_vdf(
            "// comment\n\"LibraryFolders\" {\n \"0\" { \"path\" \"/a \\\"b\\\"\" \"apps\" { \"10\" \"1\" } }\n unquoted value [$WIN32]\n \"1\" \"/old\"\n",
        );
        let top = v.get("libraryfolders").unwrap();
        assert_eq!(top.get("0").unwrap().str("path"), Some("/a \"b\""));
        assert_eq!(top.str("unquoted"), Some("value"));
        assert_eq!(top.str("1"), Some("/old"));
        // Broken text gives what could be read.
        assert_eq!(parse_vdf("\"a\" { \"b\" \"c\"").get("a").unwrap().str("b"), Some("c"));
        assert_eq!(parse_vdf("}}}{"), Vdf::Map(vec![]));
    }

    #[test]
    fn reads_steam_libraries_and_skips_tools() {
        let home = temp("steam");
        let root = home.join(".local/share/Steam");
        let extra = home.join("games/SteamLibrary");
        write(
            &root.join("steamapps/libraryfolders.vdf"),
            format!("\"libraryfolders\"\n{{\n\"0\" {{ \"path\" \"{}\" }}\n\"1\" {{ \"path\" \"{}\" }}\n}}", root.display(), extra.display())
                .as_bytes(),
        );
        write(&root.join("steamapps/appmanifest_2694490.acf"), acf(2694490, "Path of Exile 2").as_bytes());
        write(&root.join("steamapps/appmanifest_1493710.acf"), acf(1493710, "Proton Experimental").as_bytes());
        write(&root.join("steamapps/appmanifest_1628350.acf"), acf(1628350, "Steam Linux Runtime 3.0 (sniper)").as_bytes());
        write(&root.join("steamapps/appmanifest_228980.acf"), acf(228980, "Steamworks Common Redistributables").as_bytes());
        write(&extra.join("steamapps/appmanifest_10.acf"), acf(10, "Counter-Strike").as_bytes());
        write(&extra.join("steamapps/appmanifest_bad.acf"), b"garbage");
        // ~/.steam/steam links to the same folder: no doubles.
        std::fs::create_dir_all(home.join(".steam")).unwrap();
        std::os::unix::fs::symlink(&root, home.join(".steam/steam")).unwrap();
        // The old flat cover and the newer folder per game.
        write(&root.join("appcache/librarycache/2694490_library_600x900.jpg"), b"jpg");
        write(&root.join("appcache/librarycache/10/abc123/library_600x900.jpg"), b"jpg");

        let games = read_steam(&home);
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["steam:2694490", "steam:10"]);
        assert_eq!(games[0].launch, "steam://rungameid/2694490");
        assert!(games[0].picture.as_ref().unwrap().ends_with("2694490_library_600x900.jpg"));
        assert!(games[1].picture.as_ref().unwrap().ends_with("10/abc123/library_600x900.jpg"));
        // Matched to the built-in game by app id, with its process names.
        assert_eq!(games[0].dirs, ["/steamapps/common/x/"]);
        let library = compose(&games, &GamesSettings::default());
        assert_eq!(library[0].known, Some("poe2"));
        assert_eq!(library[0].twitch, "Path of Exile 2");
        assert!(library[0].processes.contains(&"PathOfExileSteam.exe".to_string()));
        assert_eq!(library[1].known, None);
    }

    #[test]
    fn reads_lutris_read_only() {
        let home = temp("lutris");
        let data = home.join(".local/share/lutris");
        std::fs::create_dir_all(&data).unwrap();
        let db = data.join("pga.db");
        {
            let conn = rusqlite::Connection::open(&db).unwrap();
            conn.execute_batch(
                "CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, slug TEXT, runner TEXT, executable TEXT, directory TEXT, installed INTEGER);
                 INSERT INTO games VALUES (3, 'Aion2', 'aion-2', 'wine', '/home/p/Games/aion2/AION2Launcher.exe', '/home/p/Games/aion-2', 1);
                 INSERT INTO games VALUES (4, 'Not here', 'gone', 'wine', '', NULL, 0);
                 INSERT INTO games VALUES (5, 'Native', 'native-game', 'linux', '/opt/native/run.sh', NULL, 1);
                 CREATE TABLE service_games (id INTEGER PRIMARY KEY, service TEXT, appid TEXT, name TEXT, slug TEXT, icon TEXT, logo TEXT, url TEXT, details TEXT, lutris_slug TEXT);
                 INSERT INTO service_games VALUES (1, 'gog', '1207', 'Star Drifter', 'star-drifter', '', '', '', '{}', 'star-drifter');
                 INSERT INTO service_games VALUES (2, 'steam', '10', 'Counter-Strike', 'counter-strike', '', '', '', '{}', '');
                 INSERT INTO service_games VALUES (3, 'egs', 'x', 'Native', 'native-game', '', '', '', '{}', '');",
            )
            .unwrap();
        }
        write(&home.join(".cache/lutris/coverart/aion-2.png"), b"png");
        write(&home.join(".local/share/lutris/banners/star-drifter.jpg"), b"jpg");
        let before = std::fs::metadata(&db).unwrap().modified().unwrap();
        let games = compose(&read_lutris(&home), &GamesSettings::default());
        assert_eq!(std::fs::metadata(&db).unwrap().modified().unwrap(), before);
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        // Steam's service games are left out (the Steam tab has them), and
        // a service game already in the list.
        assert_eq!(ids, ["lutris:3", "lutris:4", "lutris:5", "lutris:gog:1207"]);
        assert!(games[0].installed && games[2].installed);
        assert!(!games[1].installed && !games[3].installed);
        assert_eq!(games[1].launch, "lutris:gone");
        assert_eq!(games[3].launch, "lutris:star-drifter");
        assert_eq!(games[3].note, "In Lutris's GOG library");
        assert!(games[3].picture.as_ref().unwrap().ends_with("banners/star-drifter.jpg"));
        // Not installed: never a detection candidate.
        let watch = watch_list(&games, &GamesSettings::default());
        assert!(!watch.iter().any(|g| g.id == "lutris:4" || g.id == "lutris:gog:1207"));
        assert_eq!(games[0].id, "lutris:3");
        assert_eq!(games[0].launch, "lutris:rungameid/3");
        assert_eq!(games[0].known, Some("aion2"));
        assert_eq!(games[0].processes, ["AION2Launcher.exe", "AION2.exe"]);
        assert!(games[0].picture.as_ref().unwrap().ends_with("coverart/aion-2.png"));
        assert_eq!(games[0].dirs, ["/home/p/games/aion-2/"]);
        // A script would match every shell.
        assert!(games[2].processes.is_empty());
        assert!(!data.join("pga.db-journal").exists());
    }

    #[test]
    fn reads_heroic_tolerantly() {
        let home = temp("heroic");
        let base = home.join(".config/heroic");
        write(
            &base.join("legendaryConfig/legendary/installed.json"),
            br#"{"Fortnite": {"app_name": "Fortnite", "title": "Fort Game", "executable": "Binaries/Win64/Game.exe", "install_path": "/home/p/Games/Heroic/Fort", "is_dlc": false},
                 "Dlc1": {"app_name": "Dlc1", "title": "A DLC", "is_dlc": true}}"#,
        );
        write(&base.join("gog_store/installed.json"), br#"{"installed": [{"appName": "1207", "install_path": "/g/Some Game"}, {"appName": "99", "install_path": "/g/Other/"}]}"#);
        write(&base.join("gog_store/library.json"), br#"{"games": [{"app_name": "1207", "title": "Some GOG Game"}]}"#);
        write(&base.join("nile_config/nile/installed.json"), br#"[{"id": "amzn1.x", "path": "/g/Amazon Game"}]"#);
        let cover = home.join("cover.jpg");
        write(&cover, b"jpg");
        write(
            &base.join("sideload_apps/library.json"),
            format!(
                r#"{{"games": [{{"app_name": "abc", "title": "Mine", "install": {{"executable": "/opt/mine/mine"}}, "is_installed": true, "art_cover": "{}"}}]}}"#,
                cover.display()
            )
            .as_bytes(),
        );
        // A broken file elsewhere changes nothing.
        write(&home.join(".var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store/installed.json"), b"{ nope");
        let games = read_heroic(&home);
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["heroic:legendary:Fortnite", "heroic:gog:1207", "heroic:gog:99", "heroic:nile:amzn1.x", "heroic:sideload:abc"]);
        assert_eq!(games[0].launch, "heroic://launch?appName=Fortnite&runner=legendary");
        assert_eq!(games[0].processes, ["Game.exe"]);
        assert_eq!(games[0].dirs, ["/home/p/games/heroic/fort/"]);
        // Too general a folder to mean one game.
        assert!(games[1].dirs.is_empty());
        assert_eq!(games[1].name, "Some GOG Game");
        assert_eq!(games[2].name, "Other");
        assert_eq!(games[3].name, "Amazon Game");
        assert_eq!(games[3].launch, "heroic://launch?appName=amzn1.x&runner=nile");
        assert_eq!(games[4].picture.as_deref(), Some(cover.as_path()));
        assert!(games.iter().all(|g| g.installed));
        assert!(read_heroic(&temp("noheroic")).is_empty());
    }

    fn sha256_hex(text: &str) -> String {
        use sha2::{Digest, Sha256};
        Sha256::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn reads_heroic_libraries_with_covers() {
        let home = temp("heroiclib");
        let base = home.join(".config/heroic");
        write(
            &base.join("legendaryConfig/legendary/installed.json"),
            br#"{"Fort": {"app_name": "Fort", "title": "Fort Game", "install_path": "/home/p/Games/Heroic/Fort"}}"#,
        );
        // Heroic's CacheStore files, with their timestamp entries.
        write(
            &base.join("store_cache/legendary_library.json"),
            br#"{"library": [
                {"app_name": "Fort", "title": "Fort Game", "runner": "legendary", "is_installed": true,
                 "art_square": "https://cdn.example/fort_tall.jpg", "art_cover": "https://cdn.example/fort.jpg"},
                {"app_name": "Puzzle", "title": "Weekly Puzzle", "runner": "legendary", "is_installed": false,
                 "art_square": "https://cdn.example/puzzle_tall.jpg", "install": {}},
                {"app_name": "Addon", "title": "An Addon", "install": {"is_dlc": true}},
                {"title": "No app name"}],
              "__timestamp": {"library": "Thu Nov 13 2026"}}"#,
        );
        write(
            &base.join("store_cache/gog_library.json"),
            br#"{"games": [{"app_name": "1208", "title": "Pixel Knights", "runner": "gog", "is_installed": false,
                 "art_cover": "https://images.example/pk.jpg", "art_square": "https://images.example/pk_tall.jpg"}]}"#,
        );
        write(
            &base.join("store_cache/nile_library.json"),
            br#"{"library": [{"app_name": "amz1", "title": "Harbor Tales", "runner": "nile", "is_installed": false}]}"#,
        );
        // Covers in Heroic's cache, named by the SHA-256 of their address:
        // Epic's card picture is the resized square one.
        let cache = base.join("images-cache");
        write(&cache.join(sha256_hex("https://cdn.example/fort_tall.jpg?h=400&resize=1&w=300")), b"jpg");
        write(&cache.join(sha256_hex("https://images.example/pk_tall.jpg")), b"jpg");
        let games = read_heroic(&home);
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["heroic:legendary:Fort", "heroic:legendary:Puzzle", "heroic:gog:1208", "heroic:nile:amz1"]);
        assert!(games[0].installed);
        assert_eq!(games[0].processes, Vec::<String>::new());
        assert_eq!(games[0].dirs, ["/home/p/games/heroic/fort/"]);
        assert!(games[0].picture.as_ref().unwrap().starts_with(&cache));
        assert_eq!(games[0].cover_url.as_deref(), Some("https://cdn.example/fort_tall.jpg"));
        assert!(!games[1].installed && games[1].picture.is_none());
        assert_eq!(games[1].launch, "heroic://launch?appName=Puzzle&runner=legendary");
        assert!(games[1].dirs.is_empty() && games[1].processes.is_empty());
        assert_eq!(games[2].name, "Pixel Knights");
        assert!(games[2].picture.as_ref().unwrap().ends_with(sha256_hex("https://images.example/pk_tall.jpg")));
        assert!(!games[3].installed && games[3].cover_url.is_none());
        let watch = watch_list(&games, &GamesSettings::default());
        assert_eq!(watch.iter().filter(|g| g.launcher == "heroic").count(), 1);
    }

    #[test]
    fn finds_games_steam_knows_but_has_not_installed() {
        use crate::appinfo::fixture::{appinfo, App};
        let home = temp("steamknown");
        let root = home.join(".local/share/Steam");
        write(&root.join("steamapps/appmanifest_10.acf"), acf(10, "Counter-Strike").as_bytes());
        write(
            &root.join("config/loginusers.vdf"),
            b"\"users\" { \"76561197960265829\" { \"AccountName\" \"x\" \"MostRecent\" \"0\" }\n\"76561197960265828\" { \"MostRecent\" \"1\" } }",
        );
        // Account 100 signed in last; account 101's apps are not this one's.
        let user = root.join("userdata/100");
        write(
            &user.join("config/localconfig.vdf"),
            b"\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"10\" { \"LastPlayed\" \"1\" } \"20\" { } \"30\" { } } } } } }",
        );
        write(
            &user.join("7/remote/sharedconfig.vdf"),
            b"\"UserRoamingConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"Apps\" { \"40\" { \"hidden\" \"0\" } } } } } }",
        );
        write(&user.join("config/librarycache/50.json"), b"[]");
        write(&root.join("userdata/101/config/localconfig.vdf"), b"\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"70\" { } } } } } }");
        // Covers Steam keeps: an app id of its own, in the newer layout.
        write(&root.join("appcache/librarycache/60/0a1b2c/library_600x900.jpg"), b"jpg");
        write(&root.join("appcache/librarycache/40/header.jpg"), b"jpg");
        let apps = [
            App { id: 10, name: "Counter-Strike", kind: "Game", pad: 0 },
            App { id: 20, name: "A Soundtrack", kind: "Music", pad: 100 },
            App { id: 30, name: "Proton 9.0", kind: "Tool", pad: 0 },
            App { id: 40, name: "Castle Builder", kind: "Game", pad: 3000 },
            App { id: 50, name: "Night Racer", kind: "game", pad: 0 },
            App { id: 60, name: "Free Weekend Game", kind: "Game", pad: 0 },
            App { id: 70, name: "Someone Else's", kind: "Game", pad: 0 },
        ];
        write(&root.join("appcache/appinfo.vdf"), &appinfo(29, &apps));
        let games = read_library(&home);
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["steam:10", "steam:40", "steam:50", "steam:60"]);
        assert!(games[0].installed);
        assert!(games[1..].iter().all(|g| !g.installed && g.note == "Known to Steam on this PC"));
        assert_eq!(games[1].launch, "steam://install/40");
        assert!(games[1].picture.as_ref().unwrap().ends_with("librarycache/40/header.jpg"));
        assert!(games[3].picture.as_ref().unwrap().ends_with("60/0a1b2c/library_600x900.jpg"));
        assert_eq!(games[1].cover_url.as_deref(), Some(steam_cover_url(40).as_str()));
        // Detection looks only at the installed one.
        let watch = watch_list(&compose(&games, &GamesSettings::default()), &GamesSettings::default());
        assert_eq!(watch.iter().filter(|g| g.launcher == "steam").count(), 1);
    }

    #[test]
    fn matches_known_games() {
        assert_eq!(match_known("Aion 2", None).unwrap().key, "aion2");
        assert_eq!(match_known("AION2", None).unwrap().key, "aion2");
        assert_eq!(match_known("path of exile 2", None).unwrap().key, "poe2");
        assert_eq!(match_known("Something", Some(2694490)).unwrap().key, "poe2");
        assert_eq!(match_known("Path of Exile", Some(238960)), None);
        assert_eq!(match_known("", None), None);
        // Known games are looked for even when no launcher lists them.
        let none = GamesSettings::default();
        let list = watch_list(&compose(&[], &none), &none);
        assert_eq!(list.iter().map(|g| g.id.as_str()).collect::<Vec<_>>(), ["known:aion2", "known:poe2"]);
        assert_eq!((list[0].twitch.as_str(), list[0].show_on_start, list[0].radio_on_start), ("AION 2", true, false));
        let mut settings = GamesSettings {
            own: vec![OwnGame { id: 1, name: "AION 2".into(), command: "x".into(), youtube: "aion 2 guide".into(), ..Default::default() }],
            ..Default::default()
        };
        settings.options.insert(
            "known:poe2".into(),
            GameOptions { twitch: "PoE".into(), youtube: String::new(), show_on_start: false, radio_on_start: true },
        );
        let list = watch_list(&compose(&[], &settings), &settings);
        assert_eq!(list.iter().map(|g| g.id.as_str()).collect::<Vec<_>>(), ["own:1", "known:poe2"]);
        assert_eq!(list[0].processes, ["AION2.exe"]);
        // Own choices win; empty ones take the built-in game's.
        assert_eq!((list[0].twitch.as_str(), list[0].youtube.as_str()), ("AION 2", "aion 2 guide"));
        assert_eq!((list[1].twitch.as_str(), list[1].youtube.as_str()), ("PoE", "Path of Exile 2"));
        assert_eq!((list[1].show_on_start, list[1].radio_on_start), (false, true));
    }

    fn process(root: &Path, pid: u32, comm: &str, cmdline: &[u8]) {
        write(&root.join(pid.to_string()).join("comm"), format!("{comm}\n").as_bytes());
        write(&root.join(pid.to_string()).join("cmdline"), cmdline);
    }

    #[test]
    fn finds_running_games_in_proc() {
        let none = GamesSettings::default();
        let games = watch_list(&compose(&[], &none), &none);
        let root = temp("proc");
        std::fs::create_dir_all(root.join("self")).unwrap();
        process(&root, 1, "systemd", b"/sbin/init\0");
        // Proton's wrapper only mentions the game, and the launcher is not it.
        process(&root, 20, "python3", b"python3\0/proton\0waitforexitandrun\0Z:\\games\\AION2.exe\0");
        process(&root, 21, "AION2Launcher.e", b"C:\\AION2\\AION2Launcher.exe\0");
        assert_eq!(scan_running(&root, &games), None);
        // The game itself under Wine.
        process(&root, 30, "wine64-preload", b"Z:\\home\\p\\Games\\AION2\\Binaries\\Win64\\AION2.exe\0-arg\0");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("known:aion2"));

        let root = temp("proc2");
        process(&root, 5, "aion2.exe", b"");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("known:aion2"));

        // Cut to 15 bytes: argv[0] says which.
        let root = temp("proc3");
        process(&root, 7, "PathOfExile_x64", b"C:\\Program Files\\PoE2\\PathOfExile_x64Steam.exe\0");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("known:poe2"));
        let root = temp("proc4");
        process(&root, 7, "PathOfExile_x64", b"/usr/bin/PathOfExile_x64Tools\0");
        assert_eq!(scan_running(&root, &games), None);
        // No cmdline to read (a zombie): the cut name alone.
        let root = temp("proc5");
        process(&root, 7, "PathOfExileStea", b"");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("known:poe2"));
        assert_eq!(scan_running(&temp("empty"), &games), None);
        assert_eq!(scan_running(&root.join("missing"), &games), None);
        assert_eq!(scan_running(&root, &[]), None);
    }

    #[test]
    fn steam_reaper_names_the_game() {
        let steam = |appid: u32, name: &str| {
            let mut game = Game::new(format!("steam:{appid}"), name, "steam", "");
            game.steam_appid = Some(appid);
            game
        };
        // Path of Exile 1 shares its process names with 2: Steam's app id decides.
        let none = GamesSettings::default();
        let games = watch_list(&compose(&[steam(2694490, "Path of Exile 2"), steam(238960, "Path of Exile")], &none), &none);
        let root = temp("reaper");
        process(&root, 40, "reaper", b"/home/p/.steam/ubuntu12_32/reaper\0SteamLaunch\0AppId=238960\0--\0/x/AppId=1\0");
        process(&root, 41, "PathOfExile_x64", b"C:\\poe\\PathOfExile_x64Steam.exe\0");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("steam:238960"));
        let root = temp("reaper2");
        process(&root, 41, "PathOfExile_x64", b"C:\\poe\\PathOfExile_x64Steam.exe\0");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("steam:2694490"));
    }

    #[test]
    fn finds_a_real_process() {
        let mut game = Game::new("own:1", "Sleeper", "own", "sleep 30");
        game.processes.push("sleep".into());
        let matcher = Matcher::new(vec![game]);
        let mut child = std::process::Command::new("sleep").arg("30").spawn().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(100));
        let found = matcher.scan(Path::new("/proc")).map(|g| g.id.clone());
        child.kill().unwrap();
        child.wait().unwrap();
        assert_eq!(found.as_deref(), Some("own:1"));
    }

    #[test]
    fn install_folders_name_the_game() {
        let mut steam = Game::new("steam:5", "Some Game", "steam", "");
        steam.dirs.push("/steamapps/common/some game/".into());
        let mut lutris = Game::new("lutris:2", "Other", "lutris", "");
        lutris.dirs = dir_needle("/home/p/Games/Other/").into_iter().collect();
        let games = [steam, lutris];
        let root = temp("dirs");
        process(&root, 1, "bash", b"/bin/bash -c ls /steamapps/common/some gamer/ ");
        process(&root, 2, "steamwebhelper", b"/home/p/.steam/steamwebhelper ");
        assert_eq!(scan_running(&root, &games), None);
        // Proton's wrapper: the game's folder further along (Windows form).
        process(&root, 3, "python3", b"python3 /x/proton waitforexitandrun Z:\\home\\p\\.steam\\steamapps\\common\\Some Game\\g.exe ");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("steam:5"));
        let root = temp("dirs2");
        process(&root, 4, "Main-Thread", b"/home/p/Games/other/bin/game ");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("lutris:2"));
        assert_eq!(dir_needle("/home/p"), None);
        assert_eq!(dir_needle("relative/a/b"), None);
        assert_eq!(dir_needle("C:\\a\\b"), None);
        assert_eq!(dir_needle("/a/b/C").as_deref(), Some("/a/b/c/"));
    }

    #[test]
    fn broad_folders_and_names() {
        // A Lutris game in ~/Games itself, another one inside it.
        let mut broad = Game::new("lutris:1", "Broad", "lutris", "");
        broad.dirs = dir_needle("/home/p/Games").into_iter().collect();
        let mut inner = Game::new("lutris:2", "Inner", "lutris", "");
        inner.dirs = dir_needle("/home/p/Games/inner").into_iter().collect();
        let mut named = Game::new("own:1", "Named", "own", "");
        named.processes = vec!["Named.exe".into()];
        let games = [broad, inner, named];
        let root = temp("broad");
        // In ~/Games but neither game's own: the shared parent does not count.
        process(&root, 1, "dolphin", b"/usr/bin/dolphin /home/p/Games/else/ ");
        assert_eq!(scan_running(&root, &games), None);
        // A name beats a folder (a file manager opened in the inner folder).
        process(&root, 2, "dolphin", b"/usr/bin/dolphin /home/p/Games/inner/ ");
        process(&root, 3, "Named.exe", b"Z:\\home\\p\\Games\\inner\\Named.exe ");
        assert_eq!(scan_running(&root, &games).as_deref(), Some("own:1"));
    }

    #[test]
    fn splits_commands_without_a_shell() {
        let home = Path::new("/home/p");
        assert_eq!(
            split_command(r#"WINEPREFIX=~/pfx wine "/g/My Game/game.exe" --x 'a b' c\ d ~/e x~"#, Some(home)).unwrap(),
            ["WINEPREFIX=~/pfx", "wine", "/g/My Game/game.exe", "--x", "a b", "c d", "/home/p/e", "x~"]
        );
        assert_eq!(split_command("a \"b", None), None);
        assert_eq!(split_command("   ", None).unwrap(), Vec::<String>::new());
        assert_eq!(split_command(r#""a\"b\n""#, None).unwrap(), ["a\"b\\n"]);
        let (env, rest) = command_parts(split_command("A=1 B_2=x y game --z=1", None).unwrap());
        assert_eq!(env, [("A".to_string(), "1".to_string()), ("B_2".to_string(), "x".to_string())]);
        assert_eq!(rest, ["y", "game", "--z=1"]);
    }

    #[test]
    fn guesses_own_process_names() {
        assert_eq!(own_processes("", "wine '/g/My Game/Game.exe' -x"), ["Game.exe"]);
        assert_eq!(own_processes("", "/usr/bin/factorio --fast"), ["factorio"]);
        assert_eq!(own_processes("", "FOO=1 ~/bin/start.sh"), Vec::<String>::new());
        assert_eq!(own_processes("a.exe, b ;A.EXE\n", "x"), ["a.exe", "b"]);
        assert_eq!(process_name("C:\\x\\Y.exe").as_deref(), Some("Y.exe"));
        assert_eq!(process_name("python3"), None);
        assert_eq!(process_name(""), None);
    }

    #[test]
    fn makes_addresses() {
        assert_eq!(file_url(Path::new("/home/p/a b#1.jpg")), "file:///home/p/a%20b%231.jpg");
        assert_eq!(encode_query("a&b c"), "a%26b%20c");
    }
}
