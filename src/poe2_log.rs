//! PoE 2's own log (`logs/Client.txt` in the game's folder), read for the
//! session tracker (MN, 2026-11-15). Only what is needed is taken: entering
//! an area ("Generating level N area "Id" with seed S", the area's name),
//! level-ups, the own character's deaths and AFK on/off. Chat, whispers,
//! trade lines and server addresses are never matched, never kept and never
//! handed on. Reading starts at the end of the file when PoE 2 runs (old
//! lines are not read) and stops with the game. No network.

use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use serde_json::{json, Value};

/// Lines older than this before the watch began are left out (the game
/// may have written its first area before it was seen running).
const LOOK_BACK_MS: i64 = 3 * 60_000;
/// How far back from the end the first read starts.
const FIRST_READ: u64 = 256 << 10;
/// A name line belongs to the area generated at most this long before.
const NAME_WITHIN_MS: i64 = 30_000;

/// Reads lines and turns the few wanted ones into events (JSON objects
/// with `k` and `t`, the line's time in ms since 1970).
#[derive(Default)]
pub struct Reader {
    /// The last generated area waiting for its name: (time, named).
    area: Option<(i64, bool)>,
    /// The character the level-ups name (the own one).
    own: Option<String>,
    /// The last area name given, and when (one name per area).
    last_name: Option<(i64, String)>,
}

impl Reader {
    /// The events of one line (none for nearly every line).
    pub fn line(&mut self, line: &str) -> Option<Value> {
        let (t, msg) = split_line(line)?;
        if let Some(rest) = msg.strip_prefix("Generating level ") {
            let (level, rest) = rest.split_once(" area \"")?;
            let (id, rest) = rest.split_once("\" with seed ")?;
            let level: u32 = level.trim().parse().ok()?;
            let seed: u64 = rest.trim().parse().ok()?;
            if id.is_empty() || id.len() > 80 {
                return None;
            }
            self.area = Some((t, false));
            return Some(json!({"k": "area", "t": t, "id": id, "level": level, "seed": seed.to_string(), "name": ""}));
        }
        let name = msg
            .strip_prefix("[SCENE] Set Source [")
            .and_then(|r| r.strip_suffix(']'))
            .or_else(|| msg.strip_prefix(": You have entered ").and_then(|r| r.strip_suffix('.')))
            .filter(|n| !n.is_empty() && *n != "(null)" && n.len() <= 80);
        if let Some(name) = name {
            if self.last_name.as_ref().is_some_and(|(at, n)| n == name && t - at <= 5_000) {
                return None;
            }
            self.last_name = Some((t, name.to_string()));
            if let Some((at, named)) = self.area.as_mut() {
                if !*named && t - *at <= NAME_WITHIN_MS && t >= *at {
                    *named = true;
                    return Some(json!({"k": "named", "t": t, "name": name}));
                }
            }
            return Some(json!({"k": "area", "t": t, "id": "", "level": 0, "seed": "", "name": name}));
        }
        let sys = msg.strip_prefix(": ")?;
        if let Some((who, level)) = level_up(sys) {
            let (char_name, class) = who;
            self.own = Some(char_name.to_string());
            return Some(json!({"k": "level", "t": t, "char": char_name, "class": class, "level": level}));
        }
        if let Some(who) = sys.strip_suffix(" has been slain.") {
            if self.own.as_deref().is_none_or(|own| own == who) {
                return Some(json!({"k": "death", "t": t}));
            }
            return None;
        }
        match sys {
            "AFK mode is now ON." => Some(json!({"k": "afk", "t": t, "on": true})),
            "AFK mode is now OFF." => Some(json!({"k": "afk", "t": t, "on": false})),
            _ => None,
        }
    }
}

/// "Name (Class) is now level 12" (English) or "… ist jetzt Stufe 12"
/// (German), as Exiled Exchange 2 reads them.
fn level_up(sys: &str) -> Option<((&str, &str), u32)> {
    let (who, level) = sys.rsplit_once(") is now level ").or_else(|| sys.rsplit_once(") ist jetzt Stufe "))?;
    let level: u32 = level.trim().parse().ok()?;
    let (name, class) = who.rsplit_once(" (")?;
    if name.is_empty() || name.len() > 40 || class.is_empty() || class.len() > 40 || name.contains(':') {
        return None;
    }
    Some(((name, class), level))
}

/// A line's time and its message: `2026/11/15 20:15:31 123 abc [INFO
/// Client 1234] message`.
fn split_line(line: &str) -> Option<(i64, &str)> {
    let line = line.trim_end_matches(['\r', '\n']);
    let stamp = line.get(..19)?;
    let t = local_ms(stamp)?;
    let open = line.find(" [")?;
    let close = line[open..].find("] ")? + open;
    if !line[open..close].contains("Client") {
        return None;
    }
    Some((t, &line[close + 2..]))
}

/// "2026/11/15 20:15:31" in the computer's own time zone → ms since 1970.
fn local_ms(stamp: &str) -> Option<i64> {
    let b = stamp.as_bytes();
    if b.len() != 19 || b[4] != b'/' || b[7] != b'/' || b[10] != b' ' || b[13] != b':' || b[16] != b':' {
        return None;
    }
    let num = |r: std::ops::Range<usize>| stamp.get(r)?.parse::<i32>().ok();
    // SAFETY: a zeroed tm is valid; mktime only reads and normalises it.
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    tm.tm_year = num(0..4)? - 1900;
    tm.tm_mon = num(5..7)? - 1;
    tm.tm_mday = num(8..10)?;
    tm.tm_hour = num(11..13)?;
    tm.tm_min = num(14..16)?;
    tm.tm_sec = num(17..19)?;
    tm.tm_isdst = -1;
    let secs = unsafe { libc::mktime(&mut tm) };
    (secs != -1).then_some(secs as i64 * 1000)
}

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

// ---------- finding the file ----------

/// Client.txt of the PoE 2 that runs (its working folder or its program's
/// folder), else of a Steam library, else of a Wine prefix in ~/Games; the
/// newest one found.
pub fn find() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("GC_POE2_LOG").map(PathBuf::from) {
        return Some(p);
    }
    let home = PathBuf::from(std::env::var_os("HOME")?);
    let mut found = running_logs(Path::new("/proc"));
    for root in crate::games::steam_roots(&home) {
        for lib in crate::games::steam_libraries(&root) {
            found.push(lib.join("steamapps/common/Path of Exile 2/logs/Client.txt"));
        }
    }
    if let Ok(dirs) = std::fs::read_dir(home.join("Games")) {
        for d in dirs.flatten() {
            for pf in ["Program Files (x86)", "Program Files"] {
                found.push(d.path().join("drive_c").join(pf).join("Grinding Gear Games/Path of Exile 2/logs/Client.txt"));
            }
        }
    }
    found
        .into_iter()
        .filter_map(|p| std::fs::metadata(&p).ok().filter(|m| m.is_file()).map(|m| (m.modified().ok(), p)))
        .max_by_key(|(m, _)| *m)
        .map(|(_, p)| p)
}

/// Client.txt beside each running PoE 2 (its cwd and its program's folder).
fn running_logs(proc_dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(proc_dir) else { return out };
    for e in entries.flatten() {
        let pid = e.path();
        let comm = std::fs::read_to_string(pid.join("comm")).unwrap_or_default();
        if !comm.trim().starts_with("PathOfExile") {
            continue;
        }
        if let Ok(cwd) = std::fs::read_link(pid.join("cwd")) {
            out.push(cwd.join("logs/Client.txt"));
        }
        let cmdline = std::fs::read(pid.join("cmdline")).unwrap_or_default();
        let first = cmdline.split(|b| *b == 0).next().map(|s| String::from_utf8_lossy(s).to_string()).unwrap_or_default();
        let environ = std::fs::read(pid.join("environ")).unwrap_or_default();
        let env = |key: &str| {
            environ.split(|b| *b == 0).find_map(|kv| {
                let kv = String::from_utf8_lossy(kv);
                kv.strip_prefix(&format!("{key}=")).map(str::to_string)
            })
        };
        let prefix = env("WINEPREFIX").or_else(|| env("STEAM_COMPAT_DATA_PATH").map(|p| format!("{p}/pfx")));
        if let Some(dir) = windows_dir(&first, prefix.as_deref()) {
            out.push(dir.join("logs/Client.txt"));
        }
    }
    out
}

/// The Linux folder of a Windows program path ("Z:\games\PoE2\x.exe",
/// "C:\Program Files\…" inside a Wine prefix).
fn windows_dir(program: &str, prefix: Option<&str>) -> Option<PathBuf> {
    let (drive, rest) = program.split_once(":\\")?;
    let rest = rest.replace('\\', "/");
    let file = match drive.to_ascii_uppercase().as_str() {
        "Z" => PathBuf::from(format!("/{rest}")),
        "C" => PathBuf::from(prefix?).join("drive_c").join(rest),
        _ => return None,
    };
    file.parent().map(Path::to_path_buf)
}

// ---------- following the file ----------

static RUN: AtomicU64 = AtomicU64::new(0);

/// Follows the log in the background until `stop` is called or another
/// watch starts. `path` "" finds it (and looks again every 10 s while it is
/// missing). `told` gets the file read (or "" while none is found).
pub fn watch(path: String, events: impl Fn(Vec<Value>) + Send + 'static, told: impl Fn(String) + Send + 'static) {
    let run = RUN.fetch_add(1, Ordering::SeqCst) + 1;
    let since = now_ms() - LOOK_BACK_MS;
    let _ = std::thread::Builder::new().name("poe2-log".into()).spawn(move || {
        let live = || RUN.load(Ordering::SeqCst) == run;
        let mut file: Option<PathBuf> = None;
        let mut said: Option<String> = None;
        let mut tail = Tail::default();
        let mut reader = Reader::default();
        let mut wait_find = 0;
        while live() {
            if file.is_none() {
                if wait_find == 0 {
                    file = if path.is_empty() { find() } else { Some(PathBuf::from(&path)).filter(|p| p.is_file()) };
                    wait_find = 10;
                }
                wait_find -= 1;
            }
            let now = file.as_ref().map(|p| p.display().to_string()).unwrap_or_default();
            if said.as_deref() != Some(&now) {
                crate::log::write("poe2", if now.is_empty() { "session: Client.txt not found" } else { "session: reading Client.txt" });
                told(crate::log::clean(&now));
                said = Some(now);
            }
            if let Some(p) = &file {
                match tail.read(p) {
                    Ok(lines) => {
                        let got: Vec<Value> = lines
                            .iter()
                            .filter_map(|l| reader.line(l))
                            .filter(|e| e["t"].as_i64().unwrap_or(0) >= since)
                            .collect();
                        if !got.is_empty() && live() {
                            events(got);
                        }
                    }
                    Err(_) => {
                        file = None;
                        tail = Tail::default();
                        wait_find = 0;
                    }
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    });
}

/// Stops following the log.
pub fn stop() {
    RUN.fetch_add(1, Ordering::SeqCst);
}

/// Where reading got to in a file (by inode, so a new file starts again).
#[derive(Default)]
struct Tail {
    inode: u64,
    pos: u64,
    rest: Vec<u8>,
    started: bool,
}

impl Tail {
    fn read(&mut self, path: &Path) -> std::io::Result<Vec<String>> {
        let meta = std::fs::metadata(path)?;
        let len = meta.len();
        if !self.started || meta.ino() != self.inode || len < self.pos {
            let first = !self.started;
            self.inode = meta.ino();
            self.pos = if first { len.saturating_sub(FIRST_READ) } else { 0 };
            self.rest.clear();
            self.started = true;
            if first && self.pos > 0 {
                // Begin at a line's start.
                self.rest = b"\0skip".to_vec();
            }
        }
        if len == self.pos {
            return Ok(Vec::new());
        }
        let mut f = std::fs::File::open(path)?;
        f.seek(SeekFrom::Start(self.pos))?;
        let mut buf = Vec::new();
        f.take((len - self.pos).min(4 << 20)).read_to_end(&mut buf)?;
        self.pos += buf.len() as u64;
        let mut all = std::mem::take(&mut self.rest);
        all.extend_from_slice(&buf);
        let mut lines: Vec<String> = Vec::new();
        let mut start = 0;
        for (i, b) in all.iter().enumerate() {
            if *b == b'\n' {
                lines.push(String::from_utf8_lossy(&all[start..i]).to_string());
                start = i + 1;
            }
        }
        self.rest = all[start..].to_vec();
        if self.rest.len() > 64 << 10 {
            self.rest.clear();
        }
        if lines.first().is_some_and(|l| l.starts_with("\0skip")) {
            lines.remove(0);
        }
        Ok(lines)
    }
}

// ---------- the tracker's own files ----------

/// ~/.local/share/game-companion/poe2/session/<key>.json; keys short and plain.
fn store_file(key: &str) -> Option<PathBuf> {
    let ok = (1..=64).contains(&key.len()) && key.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    if !ok {
        return None;
    }
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))?;
    let dir = base.join("game-companion/poe2/session");
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir.join(format!("{key}.json")))
}

/// What is kept under a key ("" for nothing).
pub fn load(key: &str) -> String {
    store_file(key)
        .and_then(|p| std::fs::read_to_string(p).ok())
        .filter(|t| serde_json::from_str::<Value>(t).is_ok())
        .unwrap_or_default()
}

/// Keeps JSON under a key in the background (at most 4 MB, whole or not
/// at all); the newest of a key wins.
pub fn keep(key: String, text: String) {
    static PENDING: Mutex<Option<std::collections::HashMap<String, String>>> = Mutex::new(None);
    if text.len() > 4 << 20 || serde_json::from_str::<Value>(&text).is_err() {
        return;
    }
    PENDING.lock().unwrap_or_else(|p| p.into_inner()).get_or_insert_with(Default::default).insert(key.clone(), text);
    let _ = std::thread::Builder::new().name("poe2-session-store".into()).spawn(move || {
        static TURN: Mutex<()> = Mutex::new(());
        let _turn = TURN.lock().unwrap_or_else(|p| p.into_inner());
        let text = PENDING.lock().unwrap_or_else(|p| p.into_inner()).as_mut().and_then(|m| m.remove(&key));
        if let (Some(text), Some(path)) = (text, store_file(&key)) {
            let tmp = path.with_extension("json.tmp");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, &path);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(stamp: &str) -> i64 {
        local_ms(stamp).unwrap()
    }

    #[test]
    fn wanted_lines_only() {
        let mut r = Reader::default();
        let gen = r.line("2026/11/15 20:15:31 123456 cffb0719 [DEBUG Client 2244] Generating level 79 area \"MapCrypt\" with seed 1923847").unwrap();
        assert_eq!(gen["k"], "area");
        assert_eq!(gen["id"], "MapCrypt");
        assert_eq!(gen["level"], 79);
        assert_eq!(gen["seed"], "1923847");
        assert_eq!(gen["t"], at("2026/11/15 20:15:31"));
        let named = r.line("2026/11/15 20:15:33 123460 cffb0719 [INFO Client 2244] [SCENE] Set Source [Crypt]").unwrap();
        assert_eq!(named["k"], "named");
        assert_eq!(named["name"], "Crypt");
        // The same name again (the chat line after the scene line): nothing.
        assert!(r.line("2026/11/15 20:15:33 123461 cffb0719 [INFO Client 2244] : You have entered Crypt.").is_none());
        assert!(r.line("2026/11/15 20:15:34 1 a [INFO Client 2244] [SCENE] Set Source [(null)]").is_none());

        let lvl = r.line("2026/11/15 20:20:00 1 a [INFO Client 2244] : Kael (Mercenary) is now level 81").unwrap();
        assert_eq!(lvl["k"], "level");
        assert_eq!(lvl["char"], "Kael");
        assert_eq!(lvl["class"], "Mercenary");
        assert_eq!(lvl["level"], 81);
        let de = r.line("2026/11/15 20:21:00 1 a [INFO Client 2244] : Kael (Söldner) ist jetzt Stufe 82").unwrap();
        assert_eq!(de["level"], 82);

        assert_eq!(r.line("2026/11/15 20:25:00 1 a [INFO Client 2244] : Kael has been slain.").unwrap()["k"], "death");
        // Someone else's death is not counted, and their name not kept.
        assert!(r.line("2026/11/15 20:25:01 1 a [INFO Client 2244] : Other has been slain.").is_none());
        assert_eq!(r.line("2026/11/15 20:30:00 1 a [INFO Client 2244] : AFK mode is now ON. Autoreply \"x\"").map(|v| v["k"].clone()), None);
        assert_eq!(r.line("2026/11/15 20:30:00 1 a [INFO Client 2244] : AFK mode is now ON.").unwrap()["on"], true);
        assert_eq!(r.line("2026/11/15 20:31:00 1 a [INFO Client 2244] : AFK mode is now OFF.").unwrap()["on"], false);
    }

    #[test]
    fn chat_and_whispers_are_never_taken() {
        let mut r = Reader::default();
        for line in [
            "2026/11/15 20:15:31 1 a [INFO Client 2244] @From Trader: Hi, I would like to buy your Kael (Mercenary) is now level 99",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] @To Trader: : Kael has been slain.",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] #Someone: : You have entered Crypt.",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] $Seller: Generating level 1 area \"X\" with seed 1",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] %Party: AFK mode is now ON.",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] Connecting to instance server at 1.2.3.4:6112",
            "2026/11/15 20:15:31 1 a [INFO Client 2244] : Trade accepted.",
            "not a log line",
            "",
        ] {
            assert!(r.line(line).is_none(), "{line}");
        }
    }

    #[test]
    fn a_name_without_its_area_is_an_area() {
        let mut r = Reader::default();
        let e = r.line("2026/11/15 20:15:31 1 a [INFO Client 2244] : You have entered Felled Hideout.").unwrap();
        assert_eq!(e["k"], "area");
        assert_eq!(e["name"], "Felled Hideout");
        assert_eq!(e["id"], "");
    }

    #[test]
    fn program_folders() {
        assert_eq!(windows_dir("Z:\\home\\p\\Games\\PoE2\\PathOfExile.exe", None), Some(PathBuf::from("/home/p/Games/PoE2")));
        assert_eq!(
            windows_dir("C:\\Program Files (x86)\\Grinding Gear Games\\Path of Exile 2\\PathOfExile.exe", Some("/pfx")),
            Some(PathBuf::from("/pfx/drive_c/Program Files (x86)/Grinding Gear Games/Path of Exile 2"))
        );
        assert_eq!(windows_dir("C:\\x.exe", None), None);
    }

    #[test]
    fn follows_the_end_only() {
        let dir = std::env::temp_dir().join(format!("gc-poe2-log-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("Client.txt");
        std::fs::write(&file, "old line one\nold line two\n").unwrap();
        let mut tail = Tail::default();
        // Small file: read from the top (the time filter drops old events).
        assert_eq!(tail.read(&file).unwrap(), ["old line one", "old line two"]);
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new().append(true).open(&file).unwrap();
        f.write_all(b"new one\nhalf").unwrap();
        assert_eq!(tail.read(&file).unwrap(), ["new one"]);
        f.write_all(b" done\n").unwrap();
        assert_eq!(tail.read(&file).unwrap(), ["half done"]);
        // Cut short (the game starts it again): from the top.
        std::fs::write(&file, "fresh\n").unwrap();
        assert_eq!(tail.read(&file).unwrap(), ["fresh"]);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn plain_keys_only() {
        assert!(store_file("../x").is_none());
        assert!(store_file("Sessions").is_none());
        assert!(store_file("").is_none());
    }
}
