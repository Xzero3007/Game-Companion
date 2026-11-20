//! Which YouTube videos have HDR (MN, 2026-11-19: "bei allen fenster wo
//! videos angezeigt werden ... einblenden wenn das video hdr hat"). Feeds
//! and lists don't say; only a video's own formats do. So each video of an
//! open list is looked at once with yt-dlp in the background (two at once,
//! never while a game runs), and the answer is kept for good in
//! ~/.cache/game-companion/youtube-hdr.json. A video the player showed in
//! HDR is noted without a look.
//!
//! The looks run on two threads of their own; each yt-dlp ends with the app
//! (PR_SET_PDEATHSIG, set by the thread that waits for it).

use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet, VecDeque};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::Duration;

/// How many answers are kept (the newest asked).
const KEEP: usize = 5000;
/// Looks at once.
const WORKERS: usize = 2;

#[derive(Default)]
struct State {
    loaded: bool,
    /// id → "hdr" or "sdr", with the order they came in (for trimming).
    known: HashMap<String, String>,
    order: VecDeque<String>,
    /// Waiting to be looked at (the open list's unknown ones).
    queue: VecDeque<String>,
    /// Being looked at now, or failed this session (not asked again).
    busy: HashSet<String>,
    failed: HashSet<String>,
    paused: bool,
    started: bool,
    unsaved: usize,
    /// Called on each new answer (from a worker thread).
    on_change: Option<std::sync::Arc<dyn Fn() + Send + Sync>>,
}

fn state() -> &'static (Mutex<State>, Condvar) {
    static S: OnceLock<(Mutex<State>, Condvar)> = OnceLock::new();
    S.get_or_init(|| (Mutex::new(State::default()), Condvar::new()))
}

fn path() -> PathBuf {
    crate::updater::cache_dir().join("youtube-hdr.json")
}

fn load(st: &mut State) {
    if st.loaded {
        return;
    }
    st.loaded = true;
    let map = std::fs::read_to_string(path())
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| match v {
            Value::Object(m) => Some(m),
            _ => None,
        })
        .unwrap_or_default();
    for (id, v) in map {
        if let Some(kind) = v.as_str().filter(|k| *k == "hdr" || *k == "sdr") {
            st.order.push_back(id.clone());
            st.known.insert(id, kind.to_string());
        }
    }
}

fn save(st: &mut State) {
    st.unsaved = 0;
    let map: Map<String, Value> = st.order.iter().filter_map(|id| Some((id.clone(), Value::from(st.known.get(id)?.clone())))).collect();
    let path = path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = path.with_extension("json.tmp");
    if std::fs::write(&tmp, Value::Object(map).to_string()).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

fn remember(st: &mut State, id: &str, hdr: bool) -> bool {
    let kind = if hdr { "hdr" } else { "sdr" };
    if st.known.get(id).map(String::as_str) == Some(kind) {
        return false;
    }
    if st.known.insert(id.to_string(), kind.to_string()).is_none() {
        st.order.push_back(id.to_string());
    }
    while st.order.len() > KEEP {
        if let Some(old) = st.order.pop_front() {
            st.known.remove(&old);
        }
    }
    st.unsaved += 1;
    true
}

/// "hdr", "sdr" or "" (not known yet).
pub fn kind_of(id: &str) -> String {
    let (lock, _) = state();
    let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
    load(&mut st);
    st.known.get(id).cloned().unwrap_or_default()
}

/// What to call on each new answer (once, from the Qt side).
pub fn on_change(f: impl Fn() + Send + Sync + 'static) {
    let (lock, _) = state();
    lock.lock().unwrap_or_else(|e| e.into_inner()).on_change = Some(std::sync::Arc::new(f));
}

/// The open list's videos: those not known yet are looked at, in this
/// order; whatever an earlier list still waited for is dropped.
pub fn want(ids: &[String]) {
    let (lock, wake) = state();
    let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
    load(&mut st);
    let mut seen = HashSet::new();
    let queue: VecDeque<String> = ids
        .iter()
        .filter(|id| crate::streams::valid_video_id(id))
        .filter(|id| !st.known.contains_key(*id) && !st.busy.contains(*id) && !st.failed.contains(*id))
        .filter(|id| seen.insert((*id).clone()))
        .cloned()
        .collect();
    st.queue = queue;
    if !st.queue.is_empty() && !st.started {
        st.started = true;
        for _ in 0..WORKERS {
            std::thread::spawn(work);
        }
    }
    wake.notify_all();
}

/// No list shows: nothing more is looked at (a look under way finishes).
pub fn stop() {
    let (lock, _) = state();
    let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
    st.queue.clear();
    if st.unsaved > 0 {
        save(&mut st);
    }
}

/// While a game runs, no looks start.
pub fn set_paused(on: bool) {
    let (lock, wake) = state();
    lock.lock().unwrap_or_else(|e| e.into_inner()).paused = on;
    wake.notify_all();
}

/// The player showed this video in HDR (only HDR is noted: a video can
/// play in an SDR format of its own).
pub fn note_hdr(id: &str) {
    if !crate::streams::valid_video_id(id) {
        return;
    }
    let (lock, _) = state();
    let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
    load(&mut st);
    st.queue.retain(|q| q != id);
    if remember(&mut st, id, true) {
        save(&mut st);
        if let Some(f) = st.on_change.clone() {
            drop(st);
            f();
        }
    }
}

fn work() {
    let (lock, wake) = state();
    loop {
        let id = {
            let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
            loop {
                if !st.paused {
                    if let Some(id) = st.queue.pop_front() {
                        st.busy.insert(id.clone());
                        break id;
                    }
                }
                if st.unsaved > 0 && st.queue.is_empty() && st.busy.is_empty() {
                    save(&mut st);
                }
                st = wake.wait(st).unwrap_or_else(|e| e.into_inner());
            }
        };
        let answer = look(&id);
        let mut st = lock.lock().unwrap_or_else(|e| e.into_inner());
        st.busy.remove(&id);
        let changed = match answer {
            Some(hdr) => remember(&mut st, &id, hdr),
            None => {
                st.failed.insert(id);
                false
            }
        };
        if st.unsaved >= 10 || (st.unsaved > 0 && st.queue.is_empty() && st.busy.is_empty()) {
            save(&mut st);
        }
        let f = if changed { st.on_change.clone() } else { None };
        drop(st);
        if let Some(f) = f {
            f();
        }
    }
}

/// Whether one of the video's formats is HDR (None: no answer).
fn look(id: &str) -> Option<bool> {
    let mut cmd = Command::new("yt-dlp");
    cmd.args(["--ignore-config", "--no-warnings", "--skip-download", "--no-playlist", "--ignore-no-formats-error"])
        .args(["--print", "%(formats.:.dynamic_range)l", "--"])
        .arg(format!("https://www.youtube.com/watch?v={id}"))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    // Ends with the app (this thread waits for it, so it outlives it).
    unsafe {
        cmd.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL);
            Ok(())
        });
    }
    let child = cmd.spawn().ok()?;
    let out = crate::streams::finish(child, Duration::from_secs(40)).ok()?;
    if !out.status.success() {
        return None;
    }
    hdr_in(&String::from_utf8_lossy(&out.stdout))
}

/// yt-dlp's dynamic ranges of all formats ("SDR, SDR, HDR10, …"): HDR if
/// any is HDR10, HDR10+, HDR12, HLG or DV; None if it named none.
pub fn hdr_in(text: &str) -> Option<bool> {
    let ranges: Vec<&str> = text.split([',', '\n']).map(str::trim).filter(|r| !r.is_empty() && *r != "NA").collect();
    if ranges.is_empty() {
        return None;
    }
    Some(ranges.iter().any(|r| r.starts_with("HDR") || *r == "HLG" || *r == "DV"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranges() {
        assert_eq!(hdr_in("SDR, SDR, HDR10\n"), Some(true));
        assert_eq!(hdr_in("SDR, SDR\n"), Some(false));
        assert_eq!(hdr_in("HLG"), Some(true));
        assert_eq!(hdr_in("NA\n"), None);
        assert_eq!(hdr_in(""), None);
    }

    #[test]
    fn trimmed() {
        let mut st = State { loaded: true, ..Default::default() };
        for i in 0..KEEP + 5 {
            remember(&mut st, &format!("v{i}"), i % 2 == 0);
        }
        assert_eq!(st.known.len(), KEEP);
        assert!(!st.known.contains_key("v0"));
        assert_eq!(st.known.get(&format!("v{}", KEEP + 4)).map(String::as_str), Some("hdr"));
        assert!(!remember(&mut st, &format!("v{}", KEEP + 4), true));
    }
}
