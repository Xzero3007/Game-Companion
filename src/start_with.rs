//! Programs that start with a game (MN, 2026-11-14): Game Companion is the
//! watcher. It already looks for games every 3 s (`games_object`); when one
//! starts, its list's programs start too, and when it ends they close. The
//! rules are the old meter's watcher's (Clicktrough patch 0037):
//!
//! - a program starts once per start of the game, and not when it already
//!   runs (started by hand, or still running from a quick restart);
//! - only what Game Companion started closes, and only once the game has
//!   been gone for 10 s (a quick restart keeps it);
//! - a program closed by hand while the game runs comes back only at the
//!   game's next start.
//!
//! Also the starters other programs left in the desktop's autostart for a
//! game (the old meter's `a2tools-game-watch`): shown with what they do and
//! their file, switched off (the file put aside in Game Companion's folder)
//! or on again, or removed. Nothing is sent: only programs on this PC start.

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::games;

/// One program in a game's list (settings `games.start_with`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct StartWith {
    /// Its number in the game's list.
    pub id: u32,
    pub name: String,
    /// The command line (split like a shell, never run by one).
    pub command: String,
    /// Starts with the game (off: kept in the list, not started).
    pub on: bool,
    /// Closes when the game has ended.
    pub close: bool,
    /// Seconds the game must be gone before it closes (a quick restart of
    /// the game keeps it).
    pub delay: u32,
}

impl Default for StartWith {
    fn default() -> Self {
        Self { id: 0, name: String::new(), command: String::new(), on: true, close: true, delay: GONE_FOR }
    }
}

/// How long the game must be gone before its programs close, unless an
/// entry says otherwise (seconds).
pub const GONE_FOR: u32 = 10;

/// The longest wait an entry can have (seconds).
pub const LONGEST_DELAY: u32 = 600;

/// How long a program asked to end may take before it is ended hard.
const GRACE: Duration = Duration::from_secs(10);

/// A program Game Companion started.
#[derive(Debug, Clone)]
struct Started {
    game: String,
    entry: u32,
    /// The process it started: the leader of its own session.
    pid: i32,
    /// Its start time (`/proc/<pid>/stat` field 22), to know it again.
    start: u64,
}

#[derive(Debug, Default)]
struct State {
    /// The game running now ("" for none).
    current: String,
    started: Vec<Started>,
}

static STATE: Mutex<State> = Mutex::new(State { current: String::new(), started: Vec::new() });

fn state() -> std::sync::MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|p| p.into_inner())
}

/// A process's session and start time, from `/proc/<pid>/stat`.
fn stat(proc_root: &Path, pid: i32) -> Option<(i32, u64)> {
    let text = std::fs::read_to_string(proc_root.join(pid.to_string()).join("stat")).ok()?;
    // The name (field 2) may hold spaces and parentheses: fields after it.
    let rest = &text[text.rfind(')')? + 2..];
    let fields: Vec<&str> = rest.split_whitespace().collect();
    // rest[0] is field 3 (state): session is field 6, start time field 22.
    Some((fields.get(3)?.parse().ok()?, fields.get(19)?.parse().ok()?))
}

/// The processes of the session a started program leads: none if its
/// leader's pid now belongs to another program.
fn session_members(proc_root: &Path, started: &Started) -> Vec<i32> {
    if let Some((_, start)) = stat(proc_root, started.pid) {
        if start != started.start {
            return Vec::new();
        }
    }
    let Ok(entries) = std::fs::read_dir(proc_root) else { return Vec::new() };
    entries
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse::<i32>().ok())
        .filter(|&pid| stat(proc_root, pid).is_some_and(|(sid, _)| sid == started.pid))
        .collect()
}

/// Whether a program by this name runs (`comm`, or argv[0]'s file name).
fn runs(proc_root: &Path, name: &str) -> bool {
    let Ok(entries) = std::fs::read_dir(proc_root) else { return false };
    let short: String = name.chars().take(15).collect();
    entries.flatten().any(|e| {
        let dir = e.path();
        if e.file_name().to_str().and_then(|n| n.parse::<i32>().ok()).is_none() {
            return false;
        }
        let comm = std::fs::read_to_string(dir.join("comm")).unwrap_or_default();
        if comm.trim() == short {
            return true;
        }
        let cmdline = std::fs::read(dir.join("cmdline")).unwrap_or_default();
        let first = cmdline.split(|&b| b == 0).next().unwrap_or_default();
        let first = String::from_utf8_lossy(first);
        first.rsplit('/').next() == Some(name)
    })
}

/// The program a command line starts (its file name), for "already runs".
fn program_name(command: &str) -> Option<String> {
    let mut words = games::split_command(command, None)?;
    // `env A=1 program`: the program after env's settings.
    if words.first().is_some_and(|w| w == "env" || w == "/usr/bin/env") {
        words.remove(0);
    }
    let (_, words) = games::command_parts(words);
    let program = words.first()?;
    let name = program.rsplit('/').next()?.to_string();
    (!name.is_empty()).then_some(name)
}

/// Starts a program in a session of its own; its pid and start time.
fn spawn(command: &str, home: Option<&Path>) -> Option<(i32, u64)> {
    use std::os::unix::process::CommandExt;
    use std::process::{Command, Stdio};
    let words = games::split_command(command, home)?;
    let (env, words) = games::command_parts(words);
    let (program, args) = words.split_first()?;
    let mut cmd = Command::new(program);
    cmd.args(args).envs(env).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    if let Some(home) = home {
        cmd.current_dir(home);
    }
    // SAFETY: setsid only, between fork and exec.
    unsafe {
        cmd.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    match cmd.spawn() {
        Ok(mut child) => {
            let pid = child.id() as i32;
            std::thread::spawn(move || child.wait());
            let start = stat(Path::new("/proc"), pid).map(|(_, s)| s).unwrap_or(0);
            Some((pid, start))
        }
        Err(e) => {
            eprintln!("game-companion: cannot start {program}: {e}");
            None
        }
    }
}

/// A game started: its programs that are on start, unless they run.
pub fn game_started(game: &str, entries: &[StartWith], home: Option<&Path>) {
    let proc_root = Path::new("/proc");
    let mut state = state();
    state.current = game.to_string();
    for entry in entries.iter().filter(|e| e.on && !e.command.trim().is_empty()) {
        // Still running from the game's last start (a quick restart).
        let ours = state
            .started
            .iter()
            .any(|s| s.game == game && s.entry == entry.id && !session_members(proc_root, s).is_empty());
        if ours {
            continue;
        }
        if program_name(&entry.command).is_some_and(|name| runs(proc_root, &name)) {
            continue;
        }
        state.started.retain(|s| !(s.game == game && s.entry == entry.id));
        if let Some((pid, start)) = spawn(&entry.command, home) {
            state.started.push(Started { game: game.to_string(), entry: entry.id, pid, start });
        }
    }
}

/// A game ended: once it has been gone for each entry's wait, what Game
/// Companion started for it closes (the entries that say so, as they are
/// then: `entries` is asked again). Asked to end first; still running
/// `GRACE` later, ended hard.
pub fn game_stopped(game: &str, entries: impl Fn() -> Vec<StartWith> + Send + 'static) {
    {
        let mut state = state();
        if state.current == game {
            state.current.clear();
        }
        if !state.started.iter().any(|s| s.game == game) {
            return;
        }
    }
    let game = game.to_string();
    std::thread::Builder::new()
        .name("start-with".into())
        .spawn(move || {
            let proc_root = Path::new("/proc");
            let mut waited = 0u32;
            let mut asked: Vec<Started> = Vec::new();
            loop {
                std::thread::sleep(Duration::from_secs(1));
                waited += 1;
                let list = entries();
                let mut state = state();
                // Back again (a quick restart): the rest stays.
                if state.current == game {
                    return;
                }
                let due = |s: &Started| {
                    list.iter()
                        .find(|e| e.id == s.entry)
                        .is_none_or(|e| !e.close || waited >= e.delay.min(LONGEST_DELAY))
                };
                let (now, later): (Vec<Started>, Vec<Started>) =
                    state.started.drain(..).partition(|s| s.game == game && due(s));
                state.started = later;
                let closing: Vec<u32> = list.iter().filter(|e| e.close).map(|e| e.id).collect();
                for started in now.into_iter().filter(|s| closing.contains(&s.entry)) {
                    signal(proc_root, &started, libc::SIGTERM);
                    asked.push(started);
                }
                let left = state.started.iter().any(|s| s.game == game);
                drop(state);
                if !left {
                    break;
                }
            }
            if asked.is_empty() {
                return;
            }
            std::thread::sleep(GRACE);
            for started in &asked {
                signal(proc_root, started, libc::SIGKILL);
            }
        })
        .ok();
}

/// Sends a signal to every process of a session Game Companion started.
fn signal(proc_root: &Path, started: &Started, sig: libc::c_int) {
    for pid in session_members(proc_root, started) {
        // SAFETY: a plain signal to a process of that session.
        unsafe {
            libc::kill(pid, sig);
        }
    }
}

/// Whether a list's program runs now because Game Companion started it.
pub fn running_entries(game: &str) -> Vec<u32> {
    let proc_root = Path::new("/proc");
    let state = state();
    state
        .started
        .iter()
        .filter(|s| s.game == game && !session_members(proc_root, s).is_empty())
        .map(|s| s.entry)
        .collect()
}

/// A command line that can start: it splits and names a program.
pub fn valid_command(command: &str) -> bool {
    games::split_command(command, None).is_some_and(|w| !games::command_parts(w).1.is_empty())
}

// ----------------------------------------------------------- starters ----

/// A starter another program puts in the desktop's autostart for a game.
pub struct KnownStarter {
    /// Its file in `~/.config/autostart/`.
    pub file: &'static str,
    /// The built-in game it starts things for (`games::Known::key`).
    pub game: &'static str,
    pub name: &'static str,
    /// What it does, in plain words.
    pub about: &'static str,
    /// What Game Companion starts instead when it takes over: a name and a
    /// command for the game's list.
    pub takes_over: (&'static str, &'static str),
}

pub const STARTERS: &[KnownStarter] = &[KnownStarter {
    file: "a2tools-game-watch.desktop",
    game: "aion2",
    name: "Old DPS meter's watcher (Clicktrough)",
    about: "Put into the desktop's autostart by the old Clicktrough DPS meter (its setting \"Start and close with AION2\", \
            meter patch 0037). The small program a2tools-game-watch runs from login on, without a window, and looks \
            through the process list every 3 s. When AION 2 starts and no meter is open, it starts the meter \
            (a2tools-dps-meter --with-game); that meter closes 10 s after the game is gone. Turned off here, its \
            entry is put aside in Game Companion's folder and the watcher stops by itself within 3 s; on again puts \
            it back. If you open the old meter by hand while its setting is still on, the meter writes the entry \
            again.",
    // The meter's own note "started with the game" (patch 0037), so it
    // knows how it was started.
    takes_over: ("A2Tools DPS Meter", "a2tools-dps-meter --with-game"),
}];

fn config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
}

fn autostart_dir() -> Option<PathBuf> {
    config_dir().map(|d| d.join("autostart"))
}

/// Where a starter switched off lies.
fn off_dir() -> Option<PathBuf> {
    config_dir().map(|d| d.join("game-companion").join("autostart-off"))
}

fn known_starter(file: &str) -> Option<&'static KnownStarter> {
    STARTERS.iter().find(|s| s.file == file)
}

/// The starters found for a built-in game: `[{"file","name","about",
/// "on","path","content"}]` (on: in the autostart; off: put aside).
pub fn starters_json(game: &str) -> Value {
    starters_in(game, autostart_dir().as_deref(), off_dir().as_deref())
}

fn starters_in(game: &str, autostart: Option<&Path>, off: Option<&Path>) -> Value {
    let list: Vec<Value> = STARTERS
        .iter()
        .filter(|s| !game.is_empty() && s.game == game)
        .filter_map(|s| {
            let on_path = autostart.map(|d| d.join(s.file)).filter(|p| p.is_file());
            let off_path = off.map(|d| d.join(s.file)).filter(|p| p.is_file());
            let (on, path) = match (on_path, off_path) {
                (Some(p), _) => (true, p),
                (None, Some(p)) => (false, p),
                (None, None) => return None,
            };
            let content: String = std::fs::read_to_string(&path).unwrap_or_default().chars().take(4000).collect();
            Some(json!({
                "file": s.file,
                "name": s.name,
                "about": s.about,
                "on": on,
                "path": path.display().to_string(),
                "content": content,
                "takeName": s.takes_over.0,
                "takeCommand": s.takes_over.1,
            }))
        })
        .collect();
    Value::Array(list)
}

/// Switches a known starter off (its file put aside) or on (put back).
pub fn set_starter(file: &str, on: bool) -> bool {
    match (autostart_dir(), off_dir()) {
        (Some(a), Some(o)) => set_starter_in(file, on, &a, &o),
        _ => false,
    }
}

fn set_starter_in(file: &str, on: bool, autostart: &Path, off: &Path) -> bool {
    if known_starter(file).is_none() {
        return false;
    }
    let (from, to) = if on { (off.join(file), autostart.join(file)) } else { (autostart.join(file), off.join(file)) };
    if !from.is_file() {
        return to.is_file();
    }
    let Some(dir) = to.parent() else { return false };
    std::fs::create_dir_all(dir).is_ok() && std::fs::rename(&from, &to).is_ok()
}

/// Removes a known starter for good (from the autostart and from aside).
pub fn remove_starter(file: &str) -> bool {
    match (autostart_dir(), off_dir()) {
        (Some(a), Some(o)) => remove_starter_in(file, &a, &o),
        _ => false,
    }
}

fn remove_starter_in(file: &str, autostart: &Path, off: &Path) -> bool {
    if known_starter(file).is_none() {
        return false;
    }
    let mut ok = true;
    for path in [autostart.join(file), off.join(file)] {
        if path.is_file() && std::fs::remove_file(&path).is_err() {
            ok = false;
        }
    }
    ok
}

// ----------------------------------------------------------- programs ----

/// The desktop's programs (their `.desktop` files), to pick from:
/// `[{"name","command","icon"}]`, sorted by name.
pub fn programs_json() -> Value {
    let mut dirs: Vec<PathBuf> = Vec::new();
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")));
    dirs.extend(data_home);
    let data_dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    dirs.extend(data_dirs.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
    let mut seen = std::collections::BTreeSet::new();
    let mut list: Vec<(String, String, String)> = Vec::new();
    for dir in dirs {
        let Ok(entries) = std::fs::read_dir(dir.join("applications")) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(file) = path.file_name().and_then(|f| f.to_str()).map(str::to_string) else { continue };
            if !file.ends_with(".desktop") || !seen.insert(file) {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            if let Some(program) = desktop_program(&text) {
                list.push(program);
            }
        }
    }
    list.sort_by_key(|(name, _, _)| name.to_lowercase());
    list.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
    Value::Array(list.into_iter().map(|(name, command, icon)| json!({ "name": name, "command": command, "icon": icon })).collect())
}

/// A `.desktop` file's program: its name, command (field codes left out)
/// and icon; None for hidden entries and those that are not programs.
fn desktop_program(text: &str) -> Option<(String, String, String)> {
    let mut in_entry = false;
    let (mut name, mut exec, mut icon) = (None, None, String::new());
    let mut is_app = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else { continue };
        match key.trim() {
            "Name" => name = Some(value.trim().to_string()),
            "Exec" => exec = Some(value.trim().to_string()),
            "Icon" => icon = value.trim().to_string(),
            "Type" => is_app = value.trim() == "Application",
            "NoDisplay" | "Hidden" if value.trim() == "true" => return None,
            _ => {}
        }
    }
    let exec = exec?;
    let command: String = exec
        .split_whitespace()
        .filter(|w| !(w.len() == 2 && w.starts_with('%')))
        .collect::<Vec<_>>()
        .join(" ")
        .replace("%%", "%");
    let name = name?;
    (is_app && !command.is_empty()).then_some((name, command, icon))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_files_give_their_program() {
        let text = "[Desktop Entry]\nType=Application\nName=OBS Studio\nExec=obs %U\nIcon=obs\n[Desktop Action x]\nName=Other\nExec=obs --other\n";
        assert_eq!(desktop_program(text), Some(("OBS Studio".into(), "obs".into(), "obs".into())));
        assert_eq!(desktop_program("[Desktop Entry]\nType=Application\nName=X\nExec=x\nNoDisplay=true\n"), None);
        assert_eq!(desktop_program("[Desktop Entry]\nType=Link\nName=X\nURL=y\n"), None);
    }

    #[test]
    fn program_names_come_from_the_command() {
        assert_eq!(program_name("env A=1 /usr/bin/discord --start-minimized"), Some("discord".into()));
        assert_eq!(program_name("'/opt/My App/app' x"), Some("app".into()));
        assert!(valid_command("obs"));
        assert!(!valid_command("\"open"));
        assert!(!valid_command("   "));
    }

    #[test]
    fn a_starter_goes_aside_comes_back_and_goes() {
        let root = std::env::temp_dir().join(format!("gc-starters-{}", std::process::id()));
        let (auto, off) = (root.join("autostart"), root.join("off"));
        std::fs::create_dir_all(&auto).unwrap();
        let file = "a2tools-game-watch.desktop";
        std::fs::write(auto.join(file), "[Desktop Entry]\nExec=\"/usr/bin/a2tools-game-watch\"\n").unwrap();
        let list = starters_in("aion2", Some(&auto), Some(&off));
        assert_eq!(list[0]["on"], true);
        assert!(list[0]["content"].as_str().unwrap().contains("a2tools-game-watch"));
        assert_eq!(starters_in("poe2", Some(&auto), Some(&off)), json!([]));
        assert!(set_starter_in(file, false, &auto, &off));
        assert!(!auto.join(file).exists() && off.join(file).exists());
        assert_eq!(starters_in("aion2", Some(&auto), Some(&off))[0]["on"], false);
        assert!(set_starter_in(file, true, &auto, &off));
        assert!(auto.join(file).exists() && !off.join(file).exists());
        // Only known starters are touched.
        std::fs::write(auto.join("other.desktop"), "x").unwrap();
        assert!(!set_starter_in("other.desktop", false, &auto, &off));
        assert!(!remove_starter_in("other.desktop", &auto, &off));
        assert!(auto.join("other.desktop").exists());
        assert!(remove_starter_in(file, &auto, &off));
        assert_eq!(starters_in("aion2", Some(&auto), Some(&off)), json!([]));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn started_programs_start_once_and_close_after_the_game() {
        // A program this test starts itself: a copy of `sleep` under a name
        // nothing else runs.
        let dir = std::env::temp_dir().join(format!("gc-sw-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let program = dir.join(format!("gcsl{}", std::process::id() % 100_000));
        std::fs::copy("/bin/sleep", &program).unwrap();
        let game = "test:start-with";
        let entry = StartWith { id: 1, name: "Sleep".into(), command: format!("{} 600", program.display()), ..Default::default() };
        game_started(game, std::slice::from_ref(&entry), None);
        let first = running_entries(game);
        assert_eq!(first, vec![1]);
        let pid = state().started.iter().find(|s| s.game == game).map(|s| s.pid).unwrap();
        // Started again (a quick restart): not twice.
        game_started(game, std::slice::from_ref(&entry), None);
        assert_eq!(state().started.iter().filter(|s| s.game == game).count(), 1);
        // The session's members are found by its session id.
        let started = state().started.iter().find(|s| s.game == game).cloned().unwrap();
        assert!(session_members(Path::new("/proc"), &started).contains(&pid));
        // A different start time means another program got the pid.
        let other = Started { start: started.start + 1, ..started.clone() };
        assert!(session_members(Path::new("/proc"), &other).is_empty());
        // SAFETY: the test's own child.
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }
        std::thread::sleep(Duration::from_millis(300));
        assert!(running_entries(game).is_empty());
        state().started.retain(|s| s.game != game);
        state().current.clear();
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn a_program_closes_after_its_wait_and_a_quick_restart_keeps_it() {
        let dir = std::env::temp_dir().join(format!("gc-sw2-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let program = dir.join(format!("gcsw{}", std::process::id() % 100_000));
        std::fs::copy("/bin/sleep", &program).unwrap();
        let game = "test:start-with-close";
        let entry = StartWith { id: 7, command: format!("{} 600", program.display()), delay: 2, ..Default::default() };
        let list = vec![entry.clone()];
        game_started(game, &list, None);
        assert_eq!(running_entries(game), vec![7]);
        // Gone for a moment, then back: it stays.
        let again = list.clone();
        game_stopped(game, move || again.clone());
        std::thread::sleep(Duration::from_millis(1200));
        state().current = game.to_string();
        std::thread::sleep(Duration::from_millis(2500));
        assert_eq!(running_entries(game), vec![7]);
        // Gone for good: closed after its 2 s.
        let again = list.clone();
        game_stopped(game, move || again.clone());
        std::thread::sleep(Duration::from_millis(3800));
        assert!(running_entries(game).is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }
}
