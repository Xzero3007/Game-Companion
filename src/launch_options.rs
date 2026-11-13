//! Launch options and Proton versions in the launchers' own files, plus
//! suggestions for this computer.
//!
//! Read: Steam's `localconfig.vdf` (each app's `LaunchOptions`) and
//! `config.vdf` (`CompatToolMapping`), a Lutris game's yml (`game: args`,
//! `system: env`, `system: prefix_command`, `wine: version`), Heroic's
//! `GamesConfig/<app>.json` (`launcherArgs`, `enviromentOptions`,
//! `wrapperOptions`, `wineVersion`). Written only when the user asks: the
//! launcher must be closed (it would overwrite the file), a timestamped
//! copy goes next to the file first, the new file replaces the old one in
//! one step, and only the one value changes (every other byte stays).
//!
//! Every launcher's options are shown in Steam's form:
//! `NAME=value wrapper %command% arguments`.

use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::games::{self, parse_vdf};
use crate::system_info::SystemInfo;
use crate::vdf_edit;

/// Where things are: the user's home, the file system's root ("/"; a
/// test's folder otherwise) and `/proc`.
#[derive(Debug, Clone)]
pub struct Places {
    pub home: PathBuf,
    pub root: PathBuf,
    pub proc_root: PathBuf,
}

impl Places {
    fn system(&self, path: &str) -> PathBuf {
        self.root.join(path.trim_start_matches('/'))
    }
}

/// The longest launch option text accepted.
const MAX_TEXT: usize = 2000;

// --------------------------------------------------------------- spec ----

/// Launch options taken apart.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Spec {
    /// `NAME=value` before everything.
    pub env: Vec<(String, String)>,
    /// Programs the game is started through, each with its own words.
    pub wrappers: Vec<Vec<String>>,
    /// An own entry's program and its words (Steam's `%command%` otherwise).
    pub command: Option<Vec<String>>,
    /// Words after the game.
    pub args: Vec<String>,
}

/// Programs that start a new wrapper when they come up in the words before
/// `%command%`.
const WRAPPERS: &[&str] = &[
    "gamemoderun",
    "game-performance",
    "mangohud",
    "gamescope",
    "prime-run",
    "obs-gamecapture",
    "env",
    "nice",
    "ionice",
    "taskset",
    "strace",
    "pvkrun",
    "primusrun",
    "optirun",
    "mangoapp",
];

/// The order new wrappers take: outermost first.
const WRAPPER_ORDER: &[&str] = &["prime-run", "gamemoderun", "game-performance", "gamescope", "obs-gamecapture", "mangohud"];

fn program(word: &str) -> &str {
    word.rsplit('/').next().unwrap_or(word)
}

fn order(word: &str) -> usize {
    WRAPPER_ORDER.iter().position(|w| *w == program(word)).unwrap_or(WRAPPER_ORDER.len() / 2)
}

/// Words before `%command%` (after the settings) grouped per wrapper;
/// gamescope's own words run up to its `--`.
fn group(words: Vec<String>) -> Vec<Vec<String>> {
    let mut groups: Vec<Vec<String>> = Vec::new();
    let mut in_gamescope = false;
    for word in words {
        if in_gamescope {
            in_gamescope = word != "--";
            if let Some(g) = groups.last_mut() {
                g.push(word);
            }
            continue;
        }
        if groups.is_empty() || WRAPPERS.contains(&program(&word)) {
            in_gamescope = program(&word) == "gamescope";
            groups.push(vec![word]);
        } else if let Some(g) = groups.last_mut() {
            g.push(word);
        }
    }
    groups
}

fn check_text(text: &str) -> Result<(), String> {
    if text.len() > MAX_TEXT {
        return Err("The launch options are too long".into());
    }
    if text.chars().any(|c| c.is_control() && c != '\t') {
        return Err("The launch options must be one line".into());
    }
    Ok(())
}

/// Steam's form: without `%command%` everything is an argument (Steam adds
/// it after the game).
pub fn parse(text: &str) -> Result<Spec, String> {
    check_text(text)?;
    let words = games::split_command(text, None).ok_or("A quote is not closed")?;
    let Some(at) = words.iter().position(|w| w == "%command%") else {
        return Ok(Spec { args: words, ..Default::default() });
    };
    let mut words = words;
    let args = words.split_off(at + 1);
    words.pop();
    let (env, rest) = games::command_parts(words);
    Ok(Spec { env, wrappers: group(rest), command: None, args })
}

/// An own entry's command line: settings, then the program and its words.
pub fn parse_own(text: &str) -> Result<Spec, String> {
    check_text(text)?;
    let words = games::split_command(text, None).ok_or("A quote is not closed")?;
    let (env, rest) = games::command_parts(words);
    if rest.is_empty() {
        return Err("The command is missing".into());
    }
    Ok(Spec { env, wrappers: Vec::new(), command: Some(rest), args: Vec::new() })
}

/// A word as the shell reads it back.
fn shell_word(word: &str) -> String {
    let plain = !word.is_empty()
        && word.chars().all(|c| c.is_ascii_alphanumeric() || "_-./:,=+@%^~".contains(c));
    if plain {
        return word.to_string();
    }
    let mut out = String::from("\"");
    for c in word.chars() {
        if matches!(c, '"' | '\\' | '$' | '`') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('"');
    out
}

pub fn render(spec: &Spec) -> String {
    let mut words: Vec<String> = spec.env.iter().map(|(k, v)| format!("{k}={}", shell_word(v))).collect();
    for wrapper in &spec.wrappers {
        words.extend(wrapper.iter().map(|w| shell_word(w)));
    }
    match &spec.command {
        Some(command) => words.extend(command.iter().map(|w| shell_word(w))),
        None if !words.is_empty() => words.push("%command%".into()),
        None => {}
    }
    words.extend(spec.args.iter().map(|w| shell_word(w)));
    words.join(" ")
}

/// Adds `add`'s parts to `base`: a setting already there takes the new
/// value, a wrapper whose program is there already is left out, arguments
/// already there (as a run of words) are not added again. True if anything
/// changed.
pub fn merge(base: &mut Spec, add: &Spec) -> bool {
    let mut changed = false;
    for (name, value) in &add.env {
        match base.env.iter_mut().find(|(n, _)| n == name) {
            Some((_, v)) if v == value => {}
            Some((_, v)) => {
                *v = value.clone();
                changed = true;
            }
            None => {
                base.env.push((name.clone(), value.clone()));
                changed = true;
            }
        }
    }
    for wrapper in &add.wrappers {
        let Some(first) = wrapper.first() else { continue };
        let name = program(first);
        let present = base.wrappers.iter().any(|w| w.first().is_some_and(|f| program(f) == name))
            || base.command.iter().flatten().any(|w| program(w) == name);
        if present {
            continue;
        }
        let at = base.wrappers.iter().position(|w| w.first().is_some_and(|f| order(f) > order(first))).unwrap_or(base.wrappers.len());
        base.wrappers.insert(at, wrapper.clone());
        changed = true;
    }
    if !add.args.is_empty() && !base.args.windows(add.args.len()).any(|w| w == add.args.as_slice()) {
        base.args.extend(add.args.iter().cloned());
        changed = true;
    }
    changed
}

/// Whether `part` is already all in `spec` (for "applied").
fn contains(spec: &Spec, part: &Spec) -> bool {
    let mut copy = spec.clone();
    !merge(&mut copy, part)
}

// ------------------------------------------------------------ writing ----

/// A time as `YYYYMMDD-HHMMSS` (UTC), for backup names.
pub fn stamp(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let rest = seconds % 86_400;
    // Howard Hinnant's days-to-civil.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!("{year:04}{month:02}{day:02}-{:02}{:02}{:02}", rest / 3600, rest / 60 % 60, rest % 60)
}

/// Replaces a launcher's file: a copy of the old one next to it first
/// (`<name>.gc-backup-<time>`), then the new text written beside it and
/// renamed over it (same permissions). Returns the backup's path.
pub fn write_safely(path: &Path, text: &str, now: u64) -> Result<PathBuf, String> {
    use std::io::Write;
    let path = path.canonicalize().map_err(|e| format!("Cannot open {}: {e}", path.display()))?;
    let meta = std::fs::metadata(&path).map_err(|e| format!("Cannot read {}: {e}", path.display()))?;
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let mut backup = path.with_file_name(format!("{name}.gc-backup-{}", stamp(now)));
    let mut n = 2;
    while backup.exists() {
        backup = path.with_file_name(format!("{name}.gc-backup-{}-{n}", stamp(now)));
        n += 1;
    }
    std::fs::copy(&path, &backup).map_err(|e| format!("Cannot make a backup: {e}"))?;
    let temp = path.with_file_name(format!(".{name}.gc-new-{}", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(&temp)?;
        file.write_all(text.as_bytes())?;
        file.set_permissions(meta.permissions())?;
        file.sync_all()?;
        std::fs::rename(&temp, &path)
    })();
    if let Err(e) = result {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("Cannot write {}: {e}", path.display()));
    }
    Ok(backup)
}

/// Whether a process with one of these names runs (`/proc/<pid>/comm`).
pub fn running(proc_root: &Path, names: &[&str]) -> bool {
    let Ok(entries) = std::fs::read_dir(proc_root) else { return false };
    entries.flatten().any(|e| {
        e.file_name().to_string_lossy().bytes().all(|b| b.is_ascii_digit())
            && std::fs::read_to_string(e.path().join("comm")).is_ok_and(|c| names.contains(&c.trim()))
    })
}

fn closed(places: &Places, launcher: &str) -> Result<(), String> {
    let (names, label): (&[&str], &str) = match launcher {
        "steam" => (&["steam", "steamwebhelper"], "Steam"),
        "lutris" => (&["lutris"], "Lutris"),
        "heroic" => (&["heroic"], "Heroic"),
        _ => return Ok(()),
    };
    if running(&places.proc_root, names) {
        return Err(format!("Close {label} first"));
    }
    Ok(())
}

// -------------------------------------------------------------- Steam ----

const STEAM_APPS: [&str; 5] = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"];
const STEAM_COMPAT: [&str; 5] = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"];
/// Steam ids to account ids (the `userdata` folder names).
const STEAM_ID_BASE: u64 = 76_561_197_960_265_728;

/// The Steam user's `localconfig.vdf`: the most recent login's, else the
/// newest one there is. Its account id too.
fn steam_localconfig(home: &Path) -> Option<(PathBuf, String)> {
    for root in games::steam_roots(home) {
        let users = std::fs::read_to_string(root.join("config/loginusers.vdf")).map(|t| parse_vdf(&t)).ok();
        let recent = users.as_ref().and_then(|u| {
            u.get("users")?.items().iter().find(|(_, v)| v.str("MostRecent") == Some("1")).and_then(|(id, _)| id.parse::<u64>().ok())
        });
        if let Some(account) = recent.and_then(|id| id.checked_sub(STEAM_ID_BASE)) {
            let file = root.join(format!("userdata/{account}/config/localconfig.vdf"));
            if file.is_file() {
                return Some((file, account.to_string()));
            }
        }
        let newest = std::fs::read_dir(root.join("userdata"))
            .into_iter()
            .flat_map(|d| d.flatten())
            .filter_map(|e| {
                let file = e.path().join("config/localconfig.vdf");
                let time = std::fs::metadata(&file).and_then(|m| m.modified()).ok()?;
                Some((time, file, e.file_name().to_string_lossy().into_owned()))
            })
            .max_by(|a, b| a.0.cmp(&b.0));
        if let Some((_, file, account)) = newest {
            return Some((file, account));
        }
    }
    None
}

fn steam_config(home: &Path) -> Option<PathBuf> {
    games::steam_roots(home).into_iter().map(|r| r.join("config/config.vdf")).find(|f| f.is_file())
}

fn steam_appid(id: &str) -> Option<&str> {
    id.strip_prefix("steam:").filter(|a| !a.is_empty() && a.bytes().all(|b| b.is_ascii_digit()))
}

/// A game's chosen compatibility tool ("" for Steam's default) and the
/// default chosen for all games ("0").
fn steam_compat(home: &Path, appid: &str) -> (String, String) {
    let Some(text) = steam_config(home).and_then(|f| std::fs::read_to_string(f).ok()) else { return Default::default() };
    let get = |app: &str| {
        let path: Vec<&str> = STEAM_COMPAT.iter().copied().chain([app, "name"]).collect();
        vdf_edit::get_str(&text, &path).unwrap_or_default()
    };
    (get(appid), get("0"))
}

// ------------------------------------------------------------- Lutris ----

/// A Lutris game's yml and its runner, from `pga.db` (read-only).
fn lutris_game(home: &Path, id: &str) -> Option<(PathBuf, String)> {
    use rusqlite::{Connection, OpenFlags};
    let number: i64 = id.strip_prefix("lutris:")?.parse().ok()?;
    let places = [
        (home.join(".local/share/lutris"), home.join(".config/lutris")),
        (home.join(".var/app/net.lutris.Lutris/data/lutris"), home.join(".var/app/net.lutris.Lutris/config/lutris")),
    ];
    for (data, config) in places {
        let db = data.join("pga.db");
        if !db.is_file() {
            continue;
        }
        let query = |conn: Connection| -> rusqlite::Result<(String, String)> {
            conn.query_row("SELECT COALESCE(configpath, ''), COALESCE(runner, '') FROM games WHERE id = ?1", [number], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
        };
        let read_only = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let uri = format!("file:{}?immutable=1", games::uri_path(&db));
        let Ok((configpath, runner)) = Connection::open_with_flags(uri, read_only | OpenFlags::SQLITE_OPEN_URI)
            .and_then(query)
            .or_else(|_| Connection::open_with_flags(&db, read_only).and_then(query))
        else {
            continue;
        };
        if configpath.is_empty() || configpath.contains('/') || configpath.starts_with('.') {
            continue;
        }
        for dir in [data.join("games"), config.join("games")] {
            let file = dir.join(format!("{configpath}.yml"));
            if file.is_file() {
                return Some((file, runner));
            }
        }
    }
    None
}

/// The small part of YAML that Lutris's game files use: sections with
/// `key: value` and one level of maps (`env:`). Lines are changed in place;
/// anything else (block scalars, flow lists) is refused, not guessed.
mod yml {
    struct Line {
        start: usize,
        end: usize,
        indent: usize,
        blank: bool,
    }

    fn lines(text: &str) -> Vec<Line> {
        let mut out = Vec::new();
        let mut start = 0;
        while start < text.len() {
            let end = text[start..].find('\n').map(|n| start + n + 1).unwrap_or(text.len());
            let body = text[start..end].trim_end_matches(['\n', '\r']);
            let indent = body.len() - body.trim_start_matches(' ').len();
            let rest = body.trim();
            out.push(Line { start, end, indent, blank: rest.is_empty() || rest.starts_with('#') });
            start = end;
        }
        out
    }

    /// A key and the lines it spans (trailing blank lines excluded).
    struct Item {
        key: String,
        raw: String,
        first: usize,
        last: usize,
    }

    fn unquote_key(key: &str) -> String {
        let key = key.trim();
        if key.len() >= 2 && ((key.starts_with('\'') && key.ends_with('\'')) || (key.starts_with('"') && key.ends_with('"'))) {
            key[1..key.len() - 1].replace("''", "'")
        } else {
            key.to_string()
        }
    }

    /// The items at `indent` in lines `from..to`.
    fn items(text: &str, ls: &[Line], from: usize, to: usize, indent: usize) -> Result<Vec<Item>, String> {
        let mut out: Vec<Item> = Vec::new();
        for (i, l) in ls.iter().enumerate().take(to).skip(from) {
            if l.blank {
                continue;
            }
            if l.indent > indent {
                match out.last_mut() {
                    Some(item) => item.last = i,
                    None => return Err("Lutris's file has a form this app does not change".into()),
                }
                continue;
            }
            if l.indent < indent {
                return Err("Lutris's file has a form this app does not change".into());
            }
            let body = text[l.start..l.end].trim();
            let colon = if body.starts_with(['\'', '"']) {
                let q = body.as_bytes()[0] as char;
                body[1..].find(q).map(|n| n + 1).and_then(|close| body[close..].find(':').map(|c| close + c))
            } else {
                body.find(": ").or_else(|| body.ends_with(':').then(|| body.len() - 1))
            };
            let Some(colon) = colon else {
                // A list item or something else: kept, never changed.
                out.push(Item { key: String::new(), raw: String::new(), first: i, last: i });
                continue;
            };
            out.push(Item { key: unquote_key(&body[..colon]), raw: body[colon + 1..].trim().to_string(), first: i, last: i });
        }
        Ok(out)
    }

    fn child_indent(ls: &[Line], from: usize, to: usize) -> Option<usize> {
        ls[from..to].iter().find(|l| !l.blank).map(|l| l.indent)
    }

    /// A scalar's value, with folded continuation lines.
    fn scalar(text: &str, ls: &[Line], item: &Item) -> Result<String, String> {
        let mut raw = item.raw.clone();
        for l in &ls[item.first + 1..=item.last] {
            let part = text[l.start..l.end].trim();
            if part.is_empty() {
                return Err("Lutris's file has a form this app does not change".into());
            }
            raw.push(' ');
            raw.push_str(part);
        }
        decode(&raw)
    }

    fn decode(raw: &str) -> Result<String, String> {
        let odd = || Err("Lutris's file has a form this app does not change".to_string());
        if raw.starts_with('\'') {
            if raw.len() < 2 || !raw.ends_with('\'') {
                return odd();
            }
            return Ok(raw[1..raw.len() - 1].replace("''", "'"));
        }
        if raw.starts_with('"') {
            if raw.len() < 2 || !raw.ends_with('"') {
                return odd();
            }
            let mut out = String::new();
            let mut chars = raw[1..raw.len() - 1].chars();
            while let Some(c) = chars.next() {
                if c == '\\' {
                    match chars.next() {
                        Some('n') => out.push('\n'),
                        Some('t') => out.push('\t'),
                        Some(c) => out.push(c),
                        None => {}
                    }
                } else {
                    out.push(c);
                }
            }
            return Ok(out);
        }
        if raw.starts_with(['|', '>', '[', '{', '&', '*', '!']) {
            return odd();
        }
        if raw == "~" || raw == "null" {
            return Ok(String::new());
        }
        Ok(raw.to_string())
    }

    pub fn encode(value: &str) -> String {
        format!("'{}'", value.replace('\'', "''"))
    }

    /// A section's item, its children and their indentation.
    type Section<'a> = (&'a Item, Vec<Item>, usize);

    fn section<'a>(text: &str, ls: &[Line], top: &'a [Item], name: &str) -> Result<Option<Section<'a>>, String> {
        let Some(sec) = top.iter().find(|i| i.key == name) else { return Ok(None) };
        if !sec.raw.is_empty() && sec.raw != "{}" {
            return Err("Lutris's file has a form this app does not change".into());
        }
        let indent = child_indent(ls, sec.first + 1, sec.last + 1).unwrap_or(2);
        let children = items(text, ls, sec.first + 1, sec.last + 1, indent)?;
        Ok(Some((sec, children, indent)))
    }

    pub fn get(text: &str, sec: &str, key: &str) -> Result<Option<String>, String> {
        let ls = lines(text);
        let top = items(text, &ls, 0, ls.len(), 0)?;
        let Some((_, children, _)) = section(text, &ls, &top, sec)? else { return Ok(None) };
        match children.iter().find(|i| i.key == key) {
            Some(item) => scalar(text, &ls, item).map(Some),
            None => Ok(None),
        }
    }

    pub fn get_map(text: &str, sec: &str, key: &str) -> Result<Vec<(String, String)>, String> {
        let ls = lines(text);
        let top = items(text, &ls, 0, ls.len(), 0)?;
        let Some((_, children, _)) = section(text, &ls, &top, sec)? else { return Ok(Vec::new()) };
        let Some(item) = children.iter().find(|i| i.key == key) else { return Ok(Vec::new()) };
        if item.raw == "{}" || (item.raw.is_empty() && item.first == item.last) {
            return Ok(Vec::new());
        }
        if !item.raw.is_empty() {
            return Err("Lutris's file has a form this app does not change".into());
        }
        let indent = child_indent(&ls, item.first + 1, item.last + 1).unwrap_or(0);
        items(text, &ls, item.first + 1, item.last + 1, indent)?
            .iter()
            .map(|i| scalar(text, &ls, i).map(|v| (i.key.clone(), v)))
            .collect()
    }

    /// Replaces `key` in `sec` with `new` lines (built for the indentation
    /// given; empty removes it), adding the section when it is missing.
    fn put(text: &str, sec: &str, key: &str, new: &dyn Fn(usize) -> String) -> Result<String, String> {
        let ls = lines(text);
        let top = items(text, &ls, 0, ls.len(), 0)?;
        match section(text, &ls, &top, sec)? {
            None => {
                let body = new(2);
                if body.is_empty() {
                    return Ok(text.to_string());
                }
                let gap = if text.is_empty() || text.ends_with('\n') { "" } else { "\n" };
                Ok(format!("{text}{gap}{sec}:\n{body}"))
            }
            Some((sec_item, children, indent)) => {
                let body = new(indent);
                if let Some(item) = children.iter().find(|i| i.key == key) {
                    let (a, b) = (ls[item.first].start, ls[item.last].end);
                    let mut out = format!("{}{}{}", &text[..a], body, &text[b..]);
                    // The last line had no line end: neither has its new one.
                    if !body.is_empty() && !text[..b].ends_with('\n') {
                        out.pop();
                    }
                    return Ok(out);
                }
                if body.is_empty() {
                    return Ok(text.to_string());
                }
                if sec_item.raw == "{}" {
                    let line = &ls[sec_item.first];
                    return Ok(format!("{}{sec}:\n{body}{}", &text[..line.start], &text[line.end..]));
                }
                let last = children.last().map(|i| i.last).unwrap_or(sec_item.first);
                let at = ls[last].end;
                let gap = if text[..at].ends_with('\n') { "" } else { "\n" };
                Ok(format!("{}{gap}{body}{}", &text[..at], &text[at..]))
            }
        }
    }

    /// Sets a scalar (None removes it). Unchanged values leave the text as
    /// it is.
    pub fn set(text: &str, sec: &str, key: &str, value: Option<&str>) -> Result<String, String> {
        if get(text, sec, key)?.as_deref() == value {
            return Ok(text.to_string());
        }
        let value = value.map(encode);
        put(text, sec, key, &|indent| match &value {
            Some(v) => format!("{}{key}: {v}\n", " ".repeat(indent)),
            None => String::new(),
        })
    }

    /// Sets a map of plain keys (empty removes it).
    pub fn set_map(text: &str, sec: &str, key: &str, map: &[(String, String)]) -> Result<String, String> {
        if get_map(text, sec, key)? == map {
            return Ok(text.to_string());
        }
        put(text, sec, key, &|indent| {
            if map.is_empty() {
                return String::new();
            }
            let pad = " ".repeat(indent);
            let mut out = format!("{pad}{key}:\n");
            for (k, v) in map {
                out.push_str(&format!("{pad}  {k}: {}\n", encode(v)));
            }
            out
        })
    }
}

// ------------------------------------------------------------- Heroic ----

fn heroic_app(id: &str) -> Option<&str> {
    let rest = id.strip_prefix("heroic:")?;
    let (_, app) = rest.split_once(':')?;
    (!app.is_empty() && !app.contains('/') && !app.starts_with('.')).then_some(app)
}

fn heroic_bases(home: &Path) -> [PathBuf; 2] {
    [home.join(".config/heroic"), home.join(".var/app/com.heroicgameslauncher.hgl/config/heroic")]
}

fn heroic_config(home: &Path, app: &str) -> Option<PathBuf> {
    heroic_bases(home).into_iter().map(|b| b.join(format!("GamesConfig/{app}.json"))).find(|f| f.is_file())
}

fn heroic_spec(game: &Value) -> Result<Spec, String> {
    let s = |v: &Value, key: &str| v.get(key).and_then(Value::as_str).unwrap_or("").to_string();
    let env = game
        .get("enviromentOptions")
        .and_then(Value::as_array)
        .map(|list| list.iter().map(|e| (s(e, "key"), s(e, "value"))).filter(|(k, _)| !k.is_empty()).collect())
        .unwrap_or_default();
    let mut wrappers = Vec::new();
    for w in game.get("wrapperOptions").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default() {
        let exe = s(w, "exe");
        if exe.is_empty() {
            continue;
        }
        let mut words = vec![exe];
        words.extend(games::split_command(&s(w, "args"), None).ok_or("Heroic's wrapper has an unclosed quote")?);
        wrappers.push(words);
    }
    let args = games::split_command(&s(game, "launcherArgs"), None).ok_or("Heroic's arguments have an unclosed quote")?;
    Ok(Spec { env, wrappers, command: None, args })
}

// ------------------------------------------------------ Proton / Wine ----

/// An installed Proton (or Wine) build a launcher can use.
#[derive(Debug, Clone, PartialEq)]
pub struct Tool {
    /// What the launcher calls it: Steam's internal name ("proton_9",
    /// "GE-Proton10-25"), Heroic's "Proton - <folder>", Lutris's folder.
    pub name: String,
    pub label: String,
    pub path: PathBuf,
    /// "steam" (Valve's), "custom" (compatibilitytools.d in the home),
    /// "system" (/usr/share/steam/compatibilitytools.d), "heroic", "lutris".
    pub source: &'static str,
    /// "proton", "wine" or "tool".
    pub kind: &'static str,
    pub launchers: Vec<&'static str>,
}

impl Tool {
    fn to_json(&self) -> Value {
        json!({
            "name": self.name, "label": self.label, "path": self.path.to_string_lossy(),
            "source": self.source, "kind": self.kind, "launchers": self.launchers,
        })
    }
}

/// Steam's internal name for its own Proton folders ("Proton 9.0" →
/// "proton_9", "Proton 5.13" → "proton_513", "Proton - Experimental" →
/// "proton_experimental").
pub fn official_name(folder: &str) -> Option<String> {
    let rest = folder.strip_prefix("Proton")?.trim_start_matches([' ', '-']).trim();
    let lower = rest.to_ascii_lowercase();
    if lower.starts_with("experimental") {
        return Some("proton_experimental".into());
    }
    if lower.starts_with("hotfix") {
        return Some("proton_hotfix".into());
    }
    let version = rest.split_whitespace().next()?;
    let (major, minor) = version.split_once('.').unwrap_or((version, "0"));
    if major.is_empty() || !major.bytes().all(|b| b.is_ascii_digit()) || !minor.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    Some(if minor.trim_start_matches('0').is_empty() { format!("proton_{major}") } else { format!("proton_{major}{minor}") })
}

/// The compatibility tools Steam can use: its own Protons in every library
/// and the ones in the compatibilitytools.d folders (by their
/// compatibilitytool.vdf).
pub fn steam_tools(places: &Places) -> Vec<Tool> {
    let home = &places.home;
    let mut tools: Vec<Tool> = Vec::new();
    let mut add = |tool: Tool| {
        if !tools.iter().any(|t| t.name == tool.name) {
            tools.push(tool);
        }
    };
    for root in games::steam_roots(home) {
        for library in games::steam_libraries(&root) {
            let Ok(entries) = std::fs::read_dir(library.join("steamapps/common")) else { continue };
            let mut found: Vec<(String, PathBuf)> = entries
                .flatten()
                .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
                .filter(|(_, p)| p.join("proton").is_file())
                .collect();
            found.sort();
            for (folder, path) in found {
                if let Some(name) = official_name(&folder) {
                    add(Tool { name, label: folder, path, source: "steam", kind: "proton", launchers: vec!["steam", "heroic"] });
                }
            }
        }
    }
    let user = [
        ".steam/root/compatibilitytools.d",
        ".steam/steam/compatibilitytools.d",
        ".local/share/Steam/compatibilitytools.d",
        ".var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d",
        ".var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d",
    ]
    .map(|d| (home.join(d), "custom"));
    let system = ["/usr/share/steam/compatibilitytools.d", "/usr/local/share/steam/compatibilitytools.d"].map(|d| (places.system(d), "system"));
    let mut seen: Vec<PathBuf> = Vec::new();
    for (dir, source) in user.into_iter().chain(system) {
        let Ok(dir) = dir.canonicalize() else { continue };
        if seen.contains(&dir) {
            continue;
        }
        seen.push(dir.clone());
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        let mut folders: Vec<PathBuf> = entries.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
        folders.sort();
        for folder in folders {
            let Ok(text) = std::fs::read_to_string(folder.join("compatibilitytool.vdf")) else { continue };
            let vdf = parse_vdf(&text);
            let Some(list) = vdf.get("compatibilitytools").and_then(|c| c.get("compat_tools")) else { continue };
            for (name, entry) in list.items() {
                let label = entry.str("display_name").unwrap_or(name).to_string();
                let path = folder.join(entry.str("install_path").unwrap_or("."));
                let path = path.canonicalize().unwrap_or(path);
                let proton = path.join("proton").is_file();
                let kind = if proton || (name.to_ascii_lowercase() + &label.to_ascii_lowercase()).contains("proton") { "proton" } else { "tool" };
                let launchers = if proton { vec!["steam", "heroic"] } else { vec!["steam"] };
                add(Tool { name: name.clone(), label, path, source, kind, launchers });
            }
        }
    }
    tools
}

/// Heroic's own downloads (`tools/proton`, `tools/wine`) and Lutris's
/// runners (`runners/wine`, `runners/proton`).
fn launcher_tools(places: &Places) -> Vec<Tool> {
    let mut tools = Vec::new();
    let folders = |dir: PathBuf, f: &mut dyn FnMut(String, PathBuf)| {
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        let mut list: Vec<(String, PathBuf)> = entries.flatten().map(|e| (e.file_name().to_string_lossy().into_owned(), e.path())).collect();
        list.sort();
        for (name, path) in list {
            f(name, path);
        }
    };
    for base in heroic_bases(&places.home) {
        folders(base.join("tools/proton"), &mut |name, path| {
            if path.join("proton").is_file() {
                tools.push(Tool { name: format!("Proton - {name}"), label: name, path, source: "heroic", kind: "proton", launchers: vec!["heroic"] });
            }
        });
        folders(base.join("tools/wine"), &mut |name, path| {
            if path.join("bin/wine").is_file() {
                tools.push(Tool { name: format!("Wine - {name}"), label: name, path, source: "heroic", kind: "wine", launchers: vec!["heroic"] });
            }
        });
    }
    for data in [places.home.join(".local/share/lutris"), places.home.join(".var/app/net.lutris.Lutris/data/lutris")] {
        for (sub, kind) in [("runners/wine", "wine"), ("runners/proton", "proton")] {
            folders(data.join(sub), &mut |name, path| {
                if path.is_dir() && !tools.iter().any(|t: &Tool| t.source == "lutris" && t.name == name) {
                    tools.push(Tool { name: name.clone(), label: name, path, source: "lutris", kind, launchers: vec!["lutris"] });
                }
            });
        }
    }
    tools
}

pub fn all_tools(places: &Places) -> Vec<Tool> {
    let mut tools = steam_tools(places);
    tools.extend(launcher_tools(places));
    tools
}

pub fn tools_json(tools: &[Tool]) -> String {
    Value::Array(tools.iter().map(Tool::to_json).collect()).to_string()
}

/// A Proton build's family, for what its options can do.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Flavour {
    /// GloriousEggroll's (major, release).
    Ge(u32, u32),
    CachyOs,
    Experimental,
    /// Valve's numbered Proton (major).
    Valve(u32),
    Unknown,
}

pub fn flavour(name: &str) -> Flavour {
    let lower = name.to_ascii_lowercase();
    let number = |s: &str| s.bytes().take_while(u8::is_ascii_digit).fold(0u32, |n, b| n.saturating_mul(10).saturating_add(u32::from(b - b'0')));
    if lower.contains("cachyos") {
        return Flavour::CachyOs;
    }
    if let Some(rest) = lower.split("ge-proton").nth(1) {
        let (major, release) = rest.split_once('-').unwrap_or((rest, "0"));
        if major.starts_with(|c: char| c.is_ascii_digit()) {
            return Flavour::Ge(number(major), number(release));
        }
    }
    if lower.contains("experimental") {
        return Flavour::Experimental;
    }
    if let Some(rest) = lower.strip_prefix("proton_").or_else(|| lower.strip_prefix("proton ")) {
        if rest.starts_with(|c: char| c.is_ascii_digit()) {
            // "proton_513" is 5.13, "proton_9" and "proton_10" whole.
            let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
            let packed = lower.starts_with("proton_")
                && ((digits.len() == 3 && !digits.starts_with('1')) || (digits.len() == 2 && !matches!(digits.as_str(), "10" | "11" | "12")));
            let major = if packed {
                number(&digits[..1])
            } else {
                number(&digits)
            };
            return Flavour::Valve(major);
        }
    }
    Flavour::Unknown
}

impl Flavour {
    /// Wine's Wayland driver behind `PROTON_ENABLE_WAYLAND`.
    pub fn wayland(self) -> bool {
        matches!(self, Flavour::Ge(m, _) if m >= 10) || matches!(self, Flavour::CachyOs | Flavour::Experimental) || matches!(self, Flavour::Valve(m) if m >= 10)
    }

    /// `PROTON_ENABLE_HDR` (needs the Wayland driver).
    pub fn hdr(self) -> bool {
        matches!(self, Flavour::Ge(m, _) if m >= 10) || matches!(self, Flavour::CachyOs | Flavour::Experimental)
    }

    /// `PROTON_USE_NTSYNC`.
    pub fn ntsync(self) -> bool {
        matches!(self, Flavour::Ge(m, _) if m >= 10) || matches!(self, Flavour::CachyOs)
    }
}

// ----------------------------------------------------------- current ----

/// A game's launch options as its launcher keeps them.
#[derive(Debug, Clone, Default)]
pub struct Current {
    pub launcher: String,
    /// The launcher's options can be read and written here.
    pub supported: bool,
    pub text: String,
    pub spec: Spec,
    pub file: Option<PathBuf>,
    /// Steam's account id whose options these are.
    pub user: String,
    /// The game's Proton or Wine choice ("" = the launcher's default).
    pub tool: String,
    /// Steam's default for all games ("" = Steam's own default).
    pub global_tool: String,
    /// Whether the game runs through Proton: Some(false) for none, None
    /// when it cannot be told (a Steam game without a choice may be native).
    pub proton: Option<bool>,
    /// Lutris's runner.
    pub runner: String,
    pub error: String,
}

impl Current {
    pub fn to_json(&self, id: &str, tools: &[Tool]) -> Value {
        let label = |name: &str| tools.iter().find(|t| t.name == name).map(|t| t.label.clone()).unwrap_or_else(|| name.to_string());
        json!({
            "id": id,
            "launcher": self.launcher,
            "supported": self.supported,
            "text": self.text,
            "env": self.spec.env.iter().map(|(k, v)| json!({"name": k, "value": v})).collect::<Vec<_>>(),
            "wrappers": self.spec.wrappers.iter().map(|w| w.join(" ")).collect::<Vec<_>>(),
            "args": self.spec.args.join(" "),
            "file": self.file.as_ref().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(),
            "user": self.user,
            "proton": {
                "current": self.tool,
                "label": if self.tool.is_empty() { String::new() } else { label(&self.tool) },
                "global": self.global_tool,
                "canSet": matches!(self.launcher.as_str(), "steam" | "heroic") || (self.launcher == "lutris" && self.runner == "wine"),
            },
            "error": self.error,
        })
    }
}

fn unsupported(launcher: &str, error: &str) -> Current {
    Current { launcher: launcher.into(), error: error.into(), ..Default::default() }
}

/// Reads a game's options. `own_command` is an own entry's command line.
pub fn read(places: &Places, id: &str, own_command: Option<&str>) -> Current {
    let home = &places.home;
    if let Some(command) = own_command {
        let spec = parse_own(command).unwrap_or_default();
        let lower = command.to_ascii_lowercase();
        let proton = lower.contains("proton") || lower.contains("umu-run");
        return Current {
            launcher: "own".into(),
            supported: true,
            text: command.into(),
            spec,
            proton: Some(proton),
            ..Default::default()
        };
    }
    if let Some(appid) = steam_appid(id) {
        let (tool, global_tool) = steam_compat(home, appid);
        let mut current = Current {
            launcher: "steam".into(),
            proton: if tool.is_empty() { None } else { Some(true) },
            tool,
            global_tool,
            ..Default::default()
        };
        let Some((file, user)) = steam_localconfig(home) else {
            current.error = "Steam's settings for this user were not found".into();
            return current;
        };
        let text = match std::fs::read_to_string(&file) {
            Ok(t) => t,
            Err(e) => {
                current.error = format!("Cannot read Steam's settings: {e}");
                return current;
            }
        };
        let path: Vec<&str> = STEAM_APPS.iter().copied().chain([appid, "LaunchOptions"]).collect();
        current.text = vdf_edit::get_str(&text, &path).unwrap_or_default();
        current.spec = parse(&current.text).unwrap_or_default();
        current.file = Some(file);
        current.user = user;
        current.supported = true;
        return current;
    }
    if id.starts_with("lutris:") {
        let Some((file, runner)) = lutris_game(home, id) else { return unsupported("lutris", "Lutris's file for this game was not found") };
        let mut current = Current { launcher: "lutris".into(), file: Some(file.clone()), runner: runner.clone(), ..Default::default() };
        let text = match std::fs::read_to_string(&file) {
            Ok(t) => t,
            Err(e) => {
                current.error = format!("Cannot read Lutris's file: {e}");
                return current;
            }
        };
        let parts = (|| -> Result<(Spec, String), String> {
            let args = yml::get(&text, "game", "args")?.unwrap_or_default();
            let prefix = yml::get(&text, "system", "prefix_command")?.unwrap_or_default();
            let env = yml::get_map(&text, "system", "env")?;
            let version = yml::get(&text, "wine", "version")?.unwrap_or_default();
            let wrappers = group(games::split_command(&prefix, None).ok_or("Lutris's command prefix has an unclosed quote")?);
            let args = games::split_command(&args, None).ok_or("Lutris's arguments have an unclosed quote")?;
            Ok((Spec { env, wrappers, command: None, args }, version))
        })();
        match parts {
            Ok((spec, version)) => {
                current.text = render(&spec);
                current.spec = spec;
                current.proton = Some(runner == "wine" && version.to_ascii_lowercase().contains("proton"));
                current.tool = if runner == "wine" { version } else { String::new() };
                current.supported = true;
            }
            Err(e) => current.error = e,
        }
        return current;
    }
    if let Some(app) = heroic_app(id) {
        let Some(file) = heroic_config(home, app) else {
            return unsupported("heroic", "Open the game's settings in Heroic once first");
        };
        let mut current = Current { launcher: "heroic".into(), file: Some(file.clone()), ..Default::default() };
        let value = std::fs::read_to_string(&file).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok());
        let Some(game) = value.as_ref().and_then(|v| v.get(app)).filter(|g| g.is_object()) else {
            current.error = "Heroic's file for this game has an unexpected form".into();
            return current;
        };
        match heroic_spec(game) {
            Ok(spec) => {
                current.text = render(&spec);
                current.spec = spec;
                current.supported = true;
            }
            Err(e) => current.error = e,
        }
        let version = game.get("wineVersion");
        let field = |k: &str| version.and_then(|v| v.get(k)).and_then(Value::as_str).unwrap_or("").to_string();
        current.tool = field("name");
        current.proton = Some(field("type") == "proton");
        return current;
    }
    unsupported("", "This game has no launch options to set here")
}

/// Writes a game's launch options (Steam's form) to its launcher's file.
/// Own entries are changed in the settings by the caller.
pub fn write(places: &Places, id: &str, text: &str, now: u64) -> Result<(), String> {
    let text = text.trim();
    let spec = parse(text)?;
    let current = read(places, id, None);
    if !current.supported {
        return Err(if current.error.is_empty() { "This game has no launch options to set here".into() } else { current.error });
    }
    let file = current.file.clone().ok_or("The launcher's file was not found")?;
    closed(places, &current.launcher)?;
    let old = std::fs::read_to_string(&file).map_err(|e| format!("Cannot read {}: {e}", file.display()))?;
    let new = match current.launcher.as_str() {
        "steam" => {
            if current.text == text {
                return Ok(());
            }
            let appid = steam_appid(id).ok_or("Not a Steam game")?;
            let path: Vec<&str> = STEAM_APPS.iter().copied().chain([appid, "LaunchOptions"]).collect();
            vdf_edit::set_str(&old, &path, text, 4)?
        }
        "lutris" => {
            let prefix: Vec<String> = spec.wrappers.iter().flatten().cloned().collect();
            let prefix = prefix.iter().map(|w| shell_word(w)).collect::<Vec<_>>().join(" ");
            let args = spec.args.iter().map(|w| shell_word(w)).collect::<Vec<_>>().join(" ");
            let mut new = old.clone();
            if current.spec.args != spec.args {
                new = yml::set(&new, "game", "args", Some(&args).filter(|a| !a.is_empty()).map(String::as_str))?;
            }
            if current.spec.wrappers != spec.wrappers {
                new = yml::set(&new, "system", "prefix_command", Some(&prefix).filter(|p| !p.is_empty()).map(String::as_str))?;
            }
            if current.spec.env != spec.env {
                new = yml::set_map(&new, "system", "env", &spec.env)?;
            }
            new
        }
        "heroic" => {
            let app = heroic_app(id).ok_or("Not a Heroic game")?;
            heroic_with(&old, app, |game| {
                game.insert("launcherArgs".into(), json!(spec.args.iter().map(|w| shell_word(w)).collect::<Vec<_>>().join(" ")));
                game.insert("enviromentOptions".into(), Value::Array(spec.env.iter().map(|(k, v)| json!({"key": k, "value": v})).collect()));
                let wrappers = spec
                    .wrappers
                    .iter()
                    .filter_map(|w| w.split_first())
                    .map(|(exe, args)| json!({"exe": exe, "args": args.iter().map(|a| shell_word(a)).collect::<Vec<_>>().join(" ")}))
                    .collect();
                game.insert("wrapperOptions".into(), Value::Array(wrappers));
            })?
        }
        _ => return Err("This game has no launch options to set here".into()),
    };
    if new != old {
        write_safely(&file, &new, now)?;
    }
    Ok(())
}

/// Heroic's file with one game's settings changed (key order kept, written
/// as Heroic writes it: two spaces).
fn heroic_with(old: &str, app: &str, change: impl FnOnce(&mut serde_json::Map<String, Value>)) -> Result<String, String> {
    let mut value: Value = serde_json::from_str(old).map_err(|_| "Heroic's file cannot be read")?;
    let game = value.get_mut(app).and_then(Value::as_object_mut).ok_or("Heroic's file for this game has an unexpected form")?;
    change(game);
    let mut text = serde_json::to_string_pretty(&value).map_err(|e| e.to_string())?;
    if old.ends_with('\n') {
        text.push('\n');
    }
    Ok(text)
}

/// Sets a game's Proton or Wine build by its name from `all_tools` ("" =
/// the launcher's default; Steam only).
pub fn set_tool(places: &Places, id: &str, name: &str, now: u64) -> Result<(), String> {
    let home = &places.home;
    let tools = all_tools(places);
    if let Some(appid) = steam_appid(id) {
        if !name.is_empty() && !tools.iter().any(|t| t.name == name && t.launchers.contains(&"steam")) {
            return Err("This version is not installed".into());
        }
        let file = steam_config(home).ok_or("Steam's config.vdf was not found")?;
        closed(places, "steam")?;
        let old = std::fs::read_to_string(&file).map_err(|e| format!("Cannot read {}: {e}", file.display()))?;
        let block: Vec<&str> = STEAM_COMPAT.iter().copied().chain([appid]).collect();
        let name_path: Vec<&str> = block.iter().copied().chain(["name"]).collect();
        let new = if name.is_empty() {
            vdf_edit::remove(&old, &block)
        } else {
            let had_block = vdf_edit::keys(&old, &STEAM_COMPAT).iter().any(|k| k == appid);
            let mut new = vdf_edit::set_str(&old, &name_path, name, 4)?;
            if !had_block {
                let config: Vec<&str> = block.iter().copied().chain(["config"]).collect();
                let priority: Vec<&str> = block.iter().copied().chain(["priority"]).collect();
                new = vdf_edit::set_str(&new, &config, "", 4)?;
                new = vdf_edit::set_str(&new, &priority, "250", 4)?;
            }
            new
        };
        if new != old {
            write_safely(&file, &new, now)?;
        }
        return Ok(());
    }
    if name.is_empty() {
        return Err("Choose a version".into());
    }
    if id.starts_with("lutris:") {
        let (file, runner) = lutris_game(home, id).ok_or("Lutris's file for this game was not found")?;
        if runner != "wine" {
            return Err("This Lutris game does not run through Wine".into());
        }
        if !tools.iter().any(|t| t.name == name && t.launchers.contains(&"lutris")) {
            return Err("This version is not installed".into());
        }
        closed(places, "lutris")?;
        let old = std::fs::read_to_string(&file).map_err(|e| format!("Cannot read {}: {e}", file.display()))?;
        let new = yml::set(&old, "wine", "version", Some(name))?;
        if new != old {
            write_safely(&file, &new, now)?;
        }
        return Ok(());
    }
    if let Some(app) = heroic_app(id) {
        let tool = tools.iter().find(|t| t.launchers.contains(&"heroic") && (t.name == name || (t.source != "heroic" && t.label == name)));
        let tool = tool.ok_or("This version is not installed")?;
        let file = heroic_config(home, app).ok_or("Open the game's settings in Heroic once first")?;
        closed(places, "heroic")?;
        let old = std::fs::read_to_string(&file).map_err(|e| format!("Cannot read {}: {e}", file.display()))?;
        let (bin, kind) = if tool.kind == "wine" { (tool.path.join("bin/wine"), "wine") } else { (tool.path.join("proton"), "proton") };
        let label = if tool.source == "heroic" { tool.name.clone() } else { format!("Proton - {}", tool.label) };
        let new = heroic_with(&old, app, |game| {
            let mut version = game.get("wineVersion").and_then(Value::as_object).cloned().unwrap_or_default();
            version.insert("bin".into(), json!(bin.to_string_lossy()));
            version.insert("name".into(), json!(label));
            version.insert("type".into(), json!(kind));
            game.insert("wineVersion".into(), Value::Object(version));
        })?;
        if new != old {
            write_safely(&file, &new, now)?;
        }
        return Ok(());
    }
    Err("This game's launcher has no Proton choice".into())
}

// -------------------------------------------------------- suggestions ----

#[derive(Debug, Clone, PartialEq)]
pub struct Suggestion {
    pub id: &'static str,
    pub label: String,
    /// What it does, in one plain sentence.
    pub explanation: String,
    /// Steam's form, e.g. "gamemoderun %command%".
    pub option: String,
    pub recommended: bool,
    /// Why it fits this computer.
    pub why: String,
    /// Suggestions in one group exclude each other.
    pub group: &'static str,
    /// Already in the game's options.
    pub applied: bool,
}

impl Suggestion {
    fn to_json(&self) -> Value {
        json!({
            "id": self.id, "label": self.label, "explanation": self.explanation, "option": self.option,
            "recommended": self.recommended, "why": self.why, "group": self.group, "applied": self.applied,
        })
    }
}

/// The Proton build a game will use, as far as can be told: its own
/// choice, Steam's default for all games, else (Steam) the newest of
/// Valve's numbered Protons installed, which Steam picks by itself.
fn proton_in_use(current: &Current, tools: &[Tool]) -> Option<(Flavour, String)> {
    let label_of = |name: &str| tools.iter().find(|t| t.name == name).map(|t| t.label.clone()).unwrap_or_else(|| name.to_string());
    let chosen = [current.tool.as_str(), if current.launcher == "steam" { current.global_tool.as_str() } else { "" }]
        .into_iter()
        .find(|n| !n.is_empty());
    if let Some(name) = chosen {
        let label = label_of(name);
        let f = match flavour(name) {
            Flavour::Unknown => flavour(&label),
            f => f,
        };
        return Some((f, label));
    }
    if current.launcher == "steam" {
        return tools
            .iter()
            .filter(|t| t.source == "steam")
            .filter_map(|t| match flavour(&t.name) {
                Flavour::Valve(m) => Some((m, t)),
                _ => None,
            })
            .max_by_key(|(m, _)| *m)
            .map(|(m, t)| (Flavour::Valve(m), t.label.clone()));
    }
    None
}

/// Options that fit this computer and this game, each only when what it
/// needs is there.
pub fn suggest(sys: &SystemInfo, current: &Current, tools: &[Tool]) -> Vec<Suggestion> {
    let mut out: Vec<Suggestion> = Vec::new();
    let mut add = |id: &'static str, label: &str, explanation: &str, option: String, recommended: bool, why: String, group: &'static str| {
        out.push(Suggestion { id, label: label.into(), explanation: explanation.into(), option, recommended, why, group, applied: false });
    };
    if sys.has_tool("gamemoderun") {
        add(
            "gamemode",
            "GameMode",
            "Asks the system for full processor speed and priority while the game runs.",
            "gamemoderun %command%".into(),
            true,
            "GameMode is installed.".into(),
            "",
        );
    }
    if sys.hybrid() && sys.has_tool("prime-run") {
        add(
            "prime_run",
            "Run on the NVIDIA card",
            "Starts the game on the NVIDIA card instead of the built-in graphics.",
            "prime-run %command%".into(),
            true,
            "This computer has an NVIDIA card next to other graphics, and prime-run is installed.".into(),
            "",
        );
    }
    if sys.has_tool("mangohud") {
        add(
            "mangohud",
            "MangoHud",
            "Shows frame rate, frame times and temperatures over the game.",
            "mangohud %command%".into(),
            false,
            "MangoHud is installed.".into(),
            "",
        );
    }
    if sys.has_tool("obs-gamecapture") {
        add(
            "obs_capture",
            "OBS game capture",
            "Lets OBS record the game directly through obs-vkcapture, with less load than screen capture.",
            "obs-gamecapture %command%".into(),
            false,
            "obs-vkcapture is installed.".into(),
            "",
        );
    }
    if let (true, Some(d)) = (sys.has_tool("gamescope"), sys.display.as_ref()) {
        let rate = d.refresh.map(|r| format!(" -r {r}")).unwrap_or_default();
        let size = format!("{}×{}{}", d.width, d.height, d.refresh.map(|r| format!(" at {r} Hz")).unwrap_or_default());
        let nvidia_note = if sys.has_gpu("nvidia") { " It can be less smooth on NVIDIA cards." } else { "" };
        add(
            "gamescope",
            "Gamescope",
            "Runs the game in its own small compositor at the screen's size, which helps games that pick a wrong size or tear.",
            format!("gamescope -W {} -H {}{rate} -f -- %command%", d.width, d.height),
            false,
            format!("gamescope is installed; uses your main screen ({}, {size}).{nvidia_note}", d.name),
            "gamescope",
        );
        if d.hdr {
            add(
                "gamescope_hdr",
                "Gamescope with HDR",
                "Like Gamescope, with HDR passed through to the screen.",
                format!("DXVK_HDR=1 gamescope -W {} -H {}{rate} -f --hdr-enabled -- %command%", d.width, d.height),
                false,
                format!("HDR is on for {} in KDE's display settings.", d.name),
                "gamescope",
            );
        }
    }
    let proton = current.proton != Some(false);
    let in_use = if proton { proton_in_use(current, tools) } else { None };
    if let Some((f, label)) = in_use {
        if sys.ntsync && f.ntsync() {
            add(
                "ntsync",
                "NTSync",
                "Uses the kernel's Windows-style sync driver, which makes many games run smoother.",
                "PROTON_USE_NTSYNC=1 %command%".into(),
                true,
                format!("/dev/ntsync exists and {label} supports it."),
                "",
            );
        }
        let wayland = sys.session == "wayland" && f.wayland();
        if wayland {
            add(
                "wayland",
                "Native Wayland",
                "Runs the game as a Wayland window instead of through XWayland; some games or overlays may not work.",
                "PROTON_ENABLE_WAYLAND=1 %command%".into(),
                false,
                format!("You use a Wayland session and {label} has the Wayland driver."),
                "",
            );
        }
        let hdr_screen = sys.display.as_ref().is_some_and(|d| d.hdr);
        if hdr_screen && wayland && f.hdr() {
            add(
                "proton_hdr",
                "HDR (Proton)",
                "Turns on HDR for games that support it, through Proton's Wayland driver.",
                "PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_HDR=1 %command%".into(),
                false,
                format!("HDR is on in KDE's display settings and {label} supports it."),
                "hdr",
            );
        } else if hdr_screen && sys.hdr_layer {
            add(
                "hdr_wsi",
                "HDR (Vulkan layer)",
                "Turns on HDR for games that support it, through the Vulkan HDR layer.",
                "ENABLE_HDR_WSI=1 DXVK_HDR=1 %command%".into(),
                false,
                "HDR is on in KDE's display settings and the Vulkan HDR layer is installed.".into(),
                "hdr",
            );
        }
    }
    if proton && sys.has_gpu("nvidia") && sys.nvidia_driver() {
        add(
            "nvapi",
            "NVIDIA features (DLSS, Reflex)",
            "Lets Windows games find NVIDIA's features such as DLSS and Reflex.",
            "PROTON_ENABLE_NVAPI=1 %command%".into(),
            true,
            "NVIDIA's own driver is in use.".into(),
            "",
        );
    }
    if sys.nvidia_driver() {
        add(
            "nv_shader_cache",
            "Keep NVIDIA's shader cache",
            "Stops the NVIDIA driver from clearing its shader cache, so games stutter less after the first run.",
            "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1 %command%".into(),
            true,
            "NVIDIA's own driver is in use.".into(),
            "",
        );
    }
    for s in &mut out {
        s.applied = parse(&s.option).is_ok_and(|part| contains(&current.spec, &part));
    }
    out
}

pub fn suggestions_json(list: &[Suggestion]) -> String {
    Value::Array(list.iter().map(Suggestion::to_json).collect()).to_string()
}

/// The game's options with the chosen suggestions added (in the list's
/// order; a second choice from one group is left out). The text as it was
/// when nothing new is added.
pub fn combine(current: &Current, list: &[Suggestion], chosen: &[String]) -> Result<String, String> {
    let mut spec = current.spec.clone();
    if current.launcher == "own" {
        spec = parse_own(&current.text)?;
    } else {
        parse(&current.text)?;
    }
    let mut changed = false;
    let mut groups: Vec<&str> = Vec::new();
    for s in list.iter().filter(|s| chosen.iter().any(|c| c == s.id)) {
        if !s.group.is_empty() {
            if groups.contains(&s.group) {
                continue;
            }
            groups.push(s.group);
        }
        changed |= merge(&mut spec, &parse(&s.option)?);
    }
    Ok(if changed { render(&spec) } else { current.text.clone() })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::system_info::{Display, Gpu};

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-launch-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write(path: &Path, text: &str) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn places(root: &Path) -> Places {
        let home = root.join("home");
        std::fs::create_dir_all(root.join("proc")).unwrap();
        Places { home, root: root.to_path_buf(), proc_root: root.join("proc") }
    }

    fn backups(dir: &Path) -> Vec<String> {
        let mut list: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.contains(".gc-backup-"))
            .collect();
        list.sort();
        list
    }

    const LOCALCONFIG: &str = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t\t\"10\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1700000000\"\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid\"\n\t\t\t\t\t}\n\t\t\t\t\t\"20\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n";

    const CONFIG: &str = "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"proton_9\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"75\"\n\t\t\t\t\t}\n\t\t\t\t\t\"10\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton10-25\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t\t\"SomethingElse\"\t\t\"1\"\n\t\t\t}\n\t\t}\n\t}\n}\n";

    /// A Steam folder with two users (the second the most recent), Valve's
    /// Protons and a GE-Proton.
    fn fake_steam(root: &Path) -> PathBuf {
        let steam = root.join("home/.local/share/Steam");
        std::fs::create_dir_all(steam.join("steamapps")).unwrap();
        write(
            &steam.join("config/loginusers.vdf"),
            "\"users\"\n{\n\t\"76561197960265729\"\n\t{\n\t\t\"MostRecent\"\t\t\"0\"\n\t}\n\t\"76561197960265828\"\n\t{\n\t\t\"MostRecent\"\t\t\"1\"\n\t}\n}\n",
        );
        write(&steam.join("userdata/1/config/localconfig.vdf"), "\"UserLocalConfigStore\" { }");
        write(&steam.join("userdata/100/config/localconfig.vdf"), LOCALCONFIG);
        write(&steam.join("config/config.vdf"), CONFIG);
        for dir in ["Proton 9.0", "Proton 10.0", "Proton - Experimental", "Proton 5.13"] {
            write(&steam.join("steamapps/common").join(dir).join("proton"), "");
        }
        write(&steam.join("steamapps/common/Some Game/game.exe"), "");
        let ge = steam.join("compatibilitytools.d/GE-Proton10-25");
        write(&ge.join("proton"), "");
        write(
            &ge.join("compatibilitytool.vdf"),
            "\"compatibilitytools\"\n{\n  \"compat_tools\"\n  {\n    \"GE-Proton10-25\"\n    {\n      \"install_path\" \".\"\n      \"display_name\" \"GE-Proton10-25\"\n      \"from_oslist\"  \"windows\"\n      \"to_oslist\"    \"linux\"\n    }\n  }\n}\n",
        );
        let cachy = root.join("usr/share/steam/compatibilitytools.d/proton-cachyos");
        write(&cachy.join("proton"), "");
        write(&cachy.join("compatibilitytool.vdf"), "\"compatibilitytools\" { \"compat_tools\" { \"proton-cachyos\" { \"install_path\" \".\" \"display_name\" \"Proton CachyOS\" } } }");
        steam
    }

    #[test]
    fn takes_launch_options_apart() {
        let spec = parse("PROTON_LOG=1 DXVK_HUD=\"fps,gpuload\" gamemoderun gamescope -W 1920 -H 1080 -- mangohud %command% -novid +fps_max 0").unwrap();
        assert_eq!(spec.env, vec![("PROTON_LOG".into(), "1".into()), ("DXVK_HUD".into(), "fps,gpuload".into())]);
        assert_eq!(spec.wrappers.len(), 3);
        assert_eq!(spec.wrappers[1], ["gamescope", "-W", "1920", "-H", "1080", "--"]);
        assert_eq!(spec.wrappers[2], ["mangohud"]);
        assert_eq!(spec.args, ["-novid", "+fps_max", "0"]);
        assert_eq!(render(&spec), "PROTON_LOG=1 DXVK_HUD=fps,gpuload gamemoderun gamescope -W 1920 -H 1080 -- mangohud %command% -novid +fps_max 0");
        // Without %command% everything is an argument.
        assert_eq!(parse("-novid -high").unwrap().args, ["-novid", "-high"]);
        assert_eq!(render(&parse("-novid").unwrap()), "-novid");
        assert!(parse("\"open").is_err());
        assert!(parse("a\nb").is_err());
        assert_eq!(render(&parse("A=\"x y\" %command% \"a b\" 'c$'").unwrap()), "A=\"x y\" %command% \"a b\" \"c\\$\"");
    }

    #[test]
    fn merges_without_doubles() {
        let mut spec = parse("PROTON_LOG=1 mangohud %command% -novid").unwrap();
        assert!(merge(&mut spec, &parse("gamemoderun %command%").unwrap()));
        assert!(merge(&mut spec, &parse("PROTON_USE_NTSYNC=1 %command%").unwrap()));
        assert!(!merge(&mut spec, &parse("gamemoderun %command%").unwrap()));
        assert!(!merge(&mut spec, &parse("PROTON_LOG=1 %command% -novid").unwrap()));
        assert!(merge(&mut spec, &parse("prime-run %command%").unwrap()));
        assert_eq!(render(&spec), "PROTON_LOG=1 PROTON_USE_NTSYNC=1 prime-run gamemoderun mangohud %command% -novid");
        // A changed value replaces the old one.
        assert!(merge(&mut spec, &parse("PROTON_LOG=0 %command%").unwrap()));
        assert!(render(&spec).starts_with("PROTON_LOG=0 PROTON_USE_NTSYNC=1"));
        // Own entries: wrappers go before the program, once.
        let mut own = parse_own("WINEPREFIX=/p wine a.exe -x").unwrap();
        assert!(merge(&mut own, &parse("gamemoderun %command%").unwrap()));
        assert_eq!(render(&own), "WINEPREFIX=/p gamemoderun wine a.exe -x");
        let mut again = parse_own(&render(&own)).unwrap();
        assert!(!merge(&mut again, &parse("gamemoderun %command%").unwrap()));
    }

    #[test]
    fn makes_backup_names() {
        assert_eq!(stamp(0), "19700101-000000");
        assert_eq!(stamp(1_794_572_730), "20261113-122530");
        assert_eq!(stamp(951_782_400), "20000229-000000");
    }

    #[test]
    fn names_valve_protons_like_steam() {
        assert_eq!(official_name("Proton 9.0").as_deref(), Some("proton_9"));
        assert_eq!(official_name("Proton 10.0").as_deref(), Some("proton_10"));
        assert_eq!(official_name("Proton 5.13").as_deref(), Some("proton_513"));
        assert_eq!(official_name("Proton 6.3").as_deref(), Some("proton_63"));
        assert_eq!(official_name("Proton - Experimental").as_deref(), Some("proton_experimental"));
        assert_eq!(official_name("Proton Hotfix").as_deref(), Some("proton_hotfix"));
        assert_eq!(official_name("Proton EasyAntiCheat Runtime"), None);
        assert_eq!(flavour("GE-Proton10-25"), Flavour::Ge(10, 25));
        assert_eq!(flavour("Proton - GE-Proton9-20"), Flavour::Ge(9, 20));
        assert_eq!(flavour("proton-cachyos"), Flavour::CachyOs);
        assert_eq!(flavour("proton_experimental"), Flavour::Experimental);
        assert_eq!(flavour("proton_9"), Flavour::Valve(9));
        assert_eq!(flavour("proton_10"), Flavour::Valve(10));
        assert_eq!(flavour("proton_513"), Flavour::Valve(5));
        assert_eq!(flavour("proton_63"), Flavour::Valve(6));
        assert_eq!(flavour("Proton 9.0"), Flavour::Valve(9));
        assert_eq!(flavour("lutris-7.2"), Flavour::Unknown);
        assert!(Flavour::Ge(10, 1).ntsync() && !Flavour::Ge(9, 27).ntsync() && !Flavour::Valve(10).ntsync());
        assert!(Flavour::Valve(10).wayland() && !Flavour::Valve(9).wayland());
    }

    #[test]
    fn lists_proton_versions() {
        let root = temp("tools");
        fake_steam(&root);
        let heroic = root.join("home/.config/heroic/tools");
        write(&heroic.join("proton/GE-Proton9-20/proton"), "");
        write(&heroic.join("wine/Wine-GE-Proton8-26/bin/wine"), "");
        std::fs::create_dir_all(root.join("home/.local/share/lutris/runners/wine/wine-ge-8-26-x86_64")).unwrap();
        let tools = all_tools(&places(&root));
        let names: Vec<(&str, &str)> = tools.iter().map(|t| (t.name.as_str(), t.source)).collect();
        assert_eq!(
            names,
            vec![
                ("proton_experimental", "steam"),
                ("proton_10", "steam"),
                ("proton_513", "steam"),
                ("proton_9", "steam"),
                ("GE-Proton10-25", "custom"),
                ("proton-cachyos", "system"),
                ("Proton - GE-Proton9-20", "heroic"),
                ("Wine - Wine-GE-Proton8-26", "heroic"),
                ("wine-ge-8-26-x86_64", "lutris"),
            ]
        );
        assert_eq!(tools[5].label, "Proton CachyOS");
        assert_eq!(tools[0].launchers, ["steam", "heroic"]);
        let v: Value = serde_json::from_str(&tools_json(&tools)).unwrap();
        assert_eq!(v[4]["kind"], "proton");
    }

    #[test]
    fn reads_and_writes_steam_options() {
        let root = temp("steam");
        let steam = fake_steam(&root);
        let p = places(&root);
        let current = read(&p, "steam:10", None);
        assert!(current.supported, "{}", current.error);
        assert_eq!(current.text, "-novid");
        assert_eq!(current.user, "100");
        assert_eq!(current.tool, "GE-Proton10-25");
        assert_eq!(current.global_tool, "proton_9");
        let v = current.to_json("steam:10", &all_tools(&p));
        assert_eq!(v["proton"]["label"], "GE-Proton10-25");
        assert_eq!(v["args"], "-novid");

        // Steam runs: nothing is written.
        write(&root.join("proc/4242/comm"), "steam\n");
        assert_eq!(write_options(&p, "steam:10", "gamemoderun %command%"), Err("Close Steam first".to_string()));
        std::fs::remove_dir_all(root.join("proc/4242")).unwrap();

        let file = steam.join("userdata/100/config/localconfig.vdf");
        write_options(&p, "steam:10", "gamemoderun %command% -novid").unwrap();
        let after = std::fs::read_to_string(&file).unwrap();
        assert_eq!(after, LOCALCONFIG.replace("\"-novid\"", "\"gamemoderun %command% -novid\""));
        assert_eq!(backups(file.parent().unwrap()), ["localconfig.vdf.gc-backup-20261113-122530"]);
        assert_eq!(std::fs::read_to_string(file.with_file_name("localconfig.vdf.gc-backup-20261113-122530")).unwrap(), LOCALCONFIG);
        // A game without options gets the key added.
        write_options(&p, "steam:20", "PROTON_LOG=1 %command%").unwrap();
        assert_eq!(read(&p, "steam:20", None).text, "PROTON_LOG=1 %command%");
        assert_eq!(backups(file.parent().unwrap()).len(), 2);
        // The same text again writes nothing.
        write_options(&p, "steam:20", "PROTON_LOG=1 %command%").unwrap();
        assert_eq!(backups(file.parent().unwrap()).len(), 2);
        // The other user's file is untouched.
        assert_eq!(std::fs::read_to_string(steam.join("userdata/1/config/localconfig.vdf")).unwrap(), "\"UserLocalConfigStore\" { }");
        assert!(read(&p, "lutris:1", None).error.contains("not found"));
        assert!(!read(&p, "known:aion2", None).supported);
    }

    fn write_options(p: &Places, id: &str, text: &str) -> Result<(), String> {
        super::write(p, id, text, 1_794_572_730)
    }

    #[test]
    fn sets_steam_proton() {
        let root = temp("compat");
        let steam = fake_steam(&root);
        let p = places(&root);
        let file = steam.join("config/config.vdf");
        assert_eq!(set_tool(&p, "steam:10", "Proton 99", 1), Err("This version is not installed".to_string()));
        set_tool(&p, "steam:10", "proton-cachyos", 1).unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), CONFIG.replace("\"GE-Proton10-25\"", "\"proton-cachyos\""));
        set_tool(&p, "steam:30", "proton_10", 2).unwrap();
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(text.contains("\t\t\t\t\t\"30\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"proton_10\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t\t\"SomethingElse\""));
        assert_eq!(read(&p, "steam:30", None).tool, "proton_10");
        // Back to Steam's default: the game's entry goes, the rest stays.
        set_tool(&p, "steam:30", "", 3).unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), CONFIG.replace("\"GE-Proton10-25\"", "\"proton-cachyos\""));
        assert_eq!(backups(file.parent().unwrap()).len(), 3);
        write(&root.join("proc/7/comm"), "steamwebhelper\n");
        assert_eq!(set_tool(&p, "steam:10", "proton_9", 4), Err("Close Steam first".to_string()));
    }

    const LUTRIS_YML: &str = "game:\n  args: -windowed\n  exe: /home/p/Games/x/x.exe\n  prefix: /home/p/Games/x\ngame_slug: x\nname: X\nrunner: wine\nsystem:\n  env:\n    DXVK_HUD: '1'\n  gamemode: true\nwine:\n  version: lutris-GE-Proton8-26-x86_64\n";

    fn fake_lutris(root: &Path, yml: &str) -> PathBuf {
        let data = root.join("home/.local/share/lutris");
        std::fs::create_dir_all(&data).unwrap();
        let conn = rusqlite::Connection::open(data.join("pga.db")).unwrap();
        conn.execute_batch(
            "CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, runner TEXT, configpath TEXT, installed INTEGER);
             INSERT INTO games VALUES (3, 'X', 'wine', 'x-1700000000', 1);
             INSERT INTO games VALUES (4, 'Native', 'linux', 'native-1', 1);
             INSERT INTO games VALUES (5, 'Bad', 'wine', '../evil', 1);",
        )
        .unwrap();
        let file = root.join("home/.config/lutris/games/x-1700000000.yml");
        write(&file, yml);
        write(&root.join("home/.config/lutris/games/native-1.yml"), "game:\n  exe: /opt/n\n");
        std::fs::create_dir_all(data.join("runners/wine/wine-ge-8-26-x86_64")).unwrap();
        file
    }

    #[test]
    fn reads_and_writes_lutris_files() {
        let root = temp("lutris");
        let file = fake_lutris(&root, LUTRIS_YML);
        let p = places(&root);
        let current = read(&p, "lutris:3", None);
        assert!(current.supported, "{}", current.error);
        assert_eq!(current.text, "DXVK_HUD=1 %command% -windowed");
        assert_eq!(current.tool, "lutris-GE-Proton8-26-x86_64");
        assert_eq!(current.proton, Some(true));
        assert!(!read(&p, "lutris:5", None).supported);

        write_options(&p, "lutris:3", "DXVK_HUD=1 PROTON_USE_NTSYNC=1 gamemoderun %command% -windowed").unwrap();
        let text = std::fs::read_to_string(&file).unwrap();
        assert_eq!(
            text,
            LUTRIS_YML.replace("    DXVK_HUD: '1'\n  gamemode: true\n", "    DXVK_HUD: '1'\n    PROTON_USE_NTSYNC: '1'\n  gamemode: true\n  prefix_command: 'gamemoderun'\n")
        );
        assert_eq!(read(&p, "lutris:3", None).text, "DXVK_HUD=1 PROTON_USE_NTSYNC=1 gamemoderun %command% -windowed");
        // Clearing everything removes the keys.
        write_options(&p, "lutris:3", "").unwrap();
        let text = std::fs::read_to_string(&file).unwrap();
        assert_eq!(text, "game:\n  exe: /home/p/Games/x/x.exe\n  prefix: /home/p/Games/x\ngame_slug: x\nname: X\nrunner: wine\nsystem:\n  gamemode: true\nwine:\n  version: lutris-GE-Proton8-26-x86_64\n");
        // A file without a system section gets one.
        let native = root.join("home/.config/lutris/games/native-1.yml");
        write_options(&p, "lutris:4", "A=1 %command% \"two words\"").unwrap();
        assert_eq!(std::fs::read_to_string(&native).unwrap(), "game:\n  exe: /opt/n\n  args: '\"two words\"'\nsystem:\n  env:\n    A: '1'\n");
        assert_eq!(read(&p, "lutris:4", None).text, "A=1 %command% \"two words\"");

        set_tool(&p, "lutris:3", "wine-ge-8-26-x86_64", 5).unwrap();
        assert!(std::fs::read_to_string(&file).unwrap().ends_with("wine:\n  version: 'wine-ge-8-26-x86_64'\n"));
        assert_eq!(set_tool(&p, "lutris:4", "wine-ge-8-26-x86_64", 5), Err("This Lutris game does not run through Wine".to_string()));
        write(&root.join("proc/9/comm"), "lutris\n");
        assert_eq!(write_options(&p, "lutris:3", "-x"), Err("Close Lutris first".to_string()));
    }

    #[test]
    fn lutris_yaml_edges() {
        // Folded long values and quoted ones are read; odd forms refused.
        let folded = "game:\n  args: -a -b\n    -c\nsystem:\n  prefix_command: 'it''s'\n";
        assert_eq!(yml::get(folded, "game", "args").unwrap().as_deref(), Some("-a -b -c"));
        assert_eq!(yml::get(folded, "system", "prefix_command").unwrap().as_deref(), Some("it's"));
        let out = yml::set(folded, "game", "args", Some("-z")).unwrap();
        assert_eq!(out, "game:\n  args: '-z'\nsystem:\n  prefix_command: 'it''s'\n");
        assert!(yml::get("game:\n  args: |\n    x\n", "game", "args").is_err());
        assert!(yml::set("system:\n  env: [a]\n", "system", "env", None).is_err() || yml::get_map("system:\n  env: [a]\n", "system", "env").is_err());
        assert_eq!(yml::get_map("system:\n  env: {}\n", "system", "env").unwrap(), vec![]);
        let out = yml::set_map("system: {}\n", "system", "env", &[("A".into(), "1".into())]).unwrap();
        assert_eq!(out, "system:\n  env:\n    A: '1'\n");
        // No newline at the end.
        let out = yml::set("game:\n  exe: x", "game", "args", Some("-a")).unwrap();
        assert_eq!(out, "game:\n  exe: x\n  args: '-a'\n");
        let out = yml::set("game:\n  args: x", "game", "args", Some("y")).unwrap();
        assert_eq!(out, "game:\n  args: 'y'");
        assert_eq!(yml::set("a: 1\n", "game", "args", None).unwrap(), "a: 1\n");
    }

    const HEROIC: &str = "{\n  \"Fort\": {\n    \"autoInstallDxvk\": true,\n    \"launcherArgs\": \"-nolauncher\",\n    \"enviromentOptions\": [\n      {\n        \"key\": \"DXVK_HUD\",\n        \"value\": \"1\"\n      }\n    ],\n    \"wrapperOptions\": [],\n    \"wineVersion\": {\n      \"bin\": \"/x/proton\",\n      \"name\": \"Proton - GE-Proton9-20\",\n      \"type\": \"proton\"\n    },\n    \"zLast\": 1\n  },\n  \"version\": \"v0\",\n  \"explicit\": true\n}\n";

    #[test]
    fn reads_and_writes_heroic_files() {
        let root = temp("heroic");
        let file = root.join("home/.config/heroic/GamesConfig/Fort.json");
        write(&file, HEROIC);
        let tool = root.join("home/.config/heroic/tools/proton/GE-Proton10-25");
        write(&tool.join("proton"), "");
        let p = places(&root);
        let current = read(&p, "heroic:legendary:Fort", None);
        assert!(current.supported, "{}", current.error);
        assert_eq!(current.text, "DXVK_HUD=1 %command% -nolauncher");
        assert_eq!(current.tool, "Proton - GE-Proton9-20");
        assert_eq!(current.proton, Some(true));
        assert_eq!(read(&p, "heroic:gog:1", None).error, "Open the game's settings in Heroic once first");

        // Writing back what was read changes not a byte (order and form kept).
        write_options(&p, "heroic:legendary:Fort", "DXVK_HUD=1 %command% -nolauncher").unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), HEROIC);
        assert!(backups(file.parent().unwrap()).is_empty());

        write_options(&p, "heroic:legendary:Fort", "DXVK_HUD=1 gamemoderun gamescope -f -- %command% -nolauncher").unwrap();
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
        assert_eq!(v["Fort"]["wrapperOptions"], json!([{"exe": "gamemoderun", "args": ""}, {"exe": "gamescope", "args": "-f --"}]));
        assert_eq!(v["Fort"]["autoInstallDxvk"], true);
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(text.find("autoInstallDxvk").unwrap() < text.find("zLast").unwrap());
        assert_eq!(read(&p, "heroic:legendary:Fort", None).text, "DXVK_HUD=1 gamemoderun gamescope -f -- %command% -nolauncher");

        set_tool(&p, "heroic:legendary:Fort", "Proton - GE-Proton10-25", 9).unwrap();
        let v: Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
        assert_eq!(v["Fort"]["wineVersion"]["name"], "Proton - GE-Proton10-25");
        assert_eq!(v["Fort"]["wineVersion"]["type"], "proton");
        assert!(v["Fort"]["wineVersion"]["bin"].as_str().unwrap().ends_with("GE-Proton10-25/proton"));
        write(&root.join("proc/3/comm"), "heroic\n");
        assert_eq!(write_options(&p, "heroic:legendary:Fort", "-x"), Err("Close Heroic first".to_string()));
    }

    fn system(nvidia: bool, hdr: bool) -> SystemInfo {
        let mut gpus = vec![Gpu { vendor: "amd".into(), driver: "amdgpu".into(), card: "card0".into() }];
        if nvidia {
            gpus.push(Gpu { vendor: "nvidia".into(), driver: "nvidia".into(), card: "card1".into() });
        }
        SystemInfo {
            gpus,
            tools: ["gamemoderun", "mangohud", "gamescope", "prime-run"].iter().map(|t| (t.to_string(), PathBuf::from("/usr/bin").join(t))).collect(),
            session: "wayland".into(),
            ntsync: true,
            display: Some(Display { name: "DP-2".into(), width: 2560, height: 1440, refresh: Some(165), hdr }),
            hdr_layer: true,
            ..Default::default()
        }
    }

    #[test]
    fn suggests_what_this_computer_has() {
        let root = temp("suggest");
        fake_steam(&root);
        let p = places(&root);
        let tools = all_tools(&p);
        let current = read(&p, "steam:10", None);
        let list = suggest(&system(true, true), &current, &tools);
        let ids: Vec<&str> = list.iter().map(|s| s.id).collect();
        assert_eq!(ids, ["gamemode", "prime_run", "mangohud", "gamescope", "gamescope_hdr", "ntsync", "wayland", "proton_hdr", "nvapi", "nv_shader_cache"]);
        let gamescope = &list[3];
        assert_eq!(gamescope.option, "gamescope -W 2560 -H 1440 -r 165 -f -- %command%");
        assert!(list.iter().all(|s| !s.explanation.is_empty() && !s.why.is_empty()));
        assert!(list[5].why.contains("GE-Proton10-25"));

        // An AMD desktop with Steam's default (Valve's Proton 10): no
        // NVIDIA options, no NTSync (not in Valve's build), no HDR.
        let current = read(&p, "steam:20", None);
        assert_eq!(current.tool, "");
        let mut sys = system(false, false);
        sys.tools.retain(|(t, _)| t == "gamemoderun");
        let mut no_global = current.clone();
        no_global.global_tool.clear();
        let ids: Vec<&str> = suggest(&sys, &no_global, &tools).iter().map(|s| s.id).collect();
        assert_eq!(ids, ["gamemode", "wayland"]);
        // Steam's default for all games (proton_9): no Wayland driver yet.
        let ids: Vec<&str> = suggest(&sys, &current, &tools).iter().map(|s| s.id).collect();
        assert_eq!(ids, ["gamemode"]);
        // A game known not to run on Proton gets no Proton options.
        let mut native = current.clone();
        native.proton = Some(false);
        native.tool = "GE-Proton10-25".into();
        let ids: Vec<&str> = suggest(&system(true, false), &native, &tools).iter().map(|s| s.id).collect();
        assert_eq!(ids, ["gamemode", "prime_run", "mangohud", "gamescope", "nv_shader_cache"]);
        assert_eq!(SystemInfo::default().tools.len(), 0);
        assert!(suggest(&SystemInfo::default(), &current, &tools).is_empty());
    }

    #[test]
    fn combines_chosen_suggestions() {
        let root = temp("combine");
        fake_steam(&root);
        let p = places(&root);
        let tools = all_tools(&p);
        let current = read(&p, "steam:10", None);
        let list = suggest(&system(true, true), &current, &tools);
        let chosen: Vec<String> = ["gamemode", "ntsync", "gamescope", "gamescope_hdr", "nvapi", "mangohud"].iter().map(|s| s.to_string()).collect();
        let text = combine(&current, &list, &chosen).unwrap();
        assert_eq!(text, "PROTON_USE_NTSYNC=1 PROTON_ENABLE_NVAPI=1 gamemoderun gamescope -W 2560 -H 1440 -r 165 -f -- mangohud %command% -novid");
        // Already there: the text stays as it was, and "applied" says so.
        let mut again = current.clone();
        again.text = text.clone();
        again.spec = parse(&text).unwrap();
        assert_eq!(combine(&again, &list, &chosen).unwrap(), text);
        let applied: Vec<&str> = suggest(&system(true, true), &again, &tools).iter().filter(|s| s.applied).map(|s| s.id).collect();
        assert_eq!(applied, ["gamemode", "mangohud", "gamescope", "ntsync", "nvapi"]);
        assert_eq!(combine(&current, &list, &[]).unwrap(), "-novid");
        // Own entries.
        let own = read(&p, "own:1", Some("wine ~/a.exe"));
        let list = suggest(&system(false, false), &own, &tools);
        assert!(list.iter().all(|s| s.id != "ntsync"));
        assert_eq!(combine(&own, &list, &["gamemode".to_string()]).unwrap(), "gamemoderun wine ~/a.exe");
    }

    #[test]
    fn refuses_to_write_where_it_should_not() {
        let root = temp("refuse");
        let p = places(&root);
        assert!(write_options(&p, "steam:10", "x").is_err());
        assert!(write_options(&p, "known:aion2", "x").is_err());
        assert!(set_tool(&p, "own:1", "x", 1).is_err());
        assert!(write_safely(&root.join("missing.vdf"), "x", 1).is_err());
        assert!(!running(&root.join("proc"), &["steam"]));
    }
}
