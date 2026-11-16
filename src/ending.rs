//! What has to happen when the app ends without Qt's own way out: the
//! Wayland connection broke (the session ends, MN 2026-11-16: logging out
//! of KDE left no end in the log), so Qt's windows and the QML are not
//! taken down. Modules that own something to finish (the AION 2 meter's
//! battle history) add a hook; `children` ends every child process still
//! running in our own session.

use std::sync::Mutex;
use std::time::{Duration, Instant};

type Hook = Box<dyn Fn() + Send>;

static HOOKS: Mutex<Vec<Hook>> = Mutex::new(Vec::new());

/// Runs `hook` when the app ends without Qt's own way out.
pub fn add(hook: impl Fn() + Send + 'static) {
    HOOKS.lock().unwrap_or_else(|p| p.into_inner()).push(Box::new(hook));
}

/// Runs every hook once (they are taken).
pub fn run_hooks() {
    let hooks = std::mem::take(&mut *HOOKS.lock().unwrap_or_else(|p| p.into_inner()));
    for hook in hooks {
        hook();
    }
}

/// Our direct children that are still in our own session (programs started
/// on their own with `setsid`, such as the installer, Brave, Legcord or a
/// game, are left to their own rules).
fn own_children(proc_root: &std::path::Path, me: i32, session: i32) -> Vec<i32> {
    let Ok(dir) = std::fs::read_dir(proc_root) else { return Vec::new() };
    dir.filter_map(|e| e.ok()?.file_name().to_str()?.parse::<i32>().ok())
        .filter(|&pid| {
            let Ok(stat) = std::fs::read_to_string(proc_root.join(pid.to_string()).join("stat")) else { return false };
            let Some(close) = stat.rfind(')') else { return false };
            // After the name: state, ppid, pgrp, session.
            let f: Vec<&str> = stat[close + 2..].split_whitespace().collect();
            f.first() != Some(&"Z") && f.get(1).and_then(|p| p.parse::<i32>().ok()) == Some(me) && f.get(3).and_then(|s| s.parse::<i32>().ok()) == Some(session)
        })
        .collect()
}

/// Ends the children still running (SIGTERM, SIGKILL after 1.5 s) and
/// logs how many there were.
pub fn children() {
    let proc_root = std::path::Path::new("/proc");
    // SAFETY: plain queries of this process.
    let (me, session) = unsafe { (libc::getpid(), libc::getsid(0)) };
    let left = own_children(proc_root, me, session);
    if left.is_empty() {
        return;
    }
    let names: Vec<String> = left
        .iter()
        .map(|pid| std::fs::read_to_string(proc_root.join(pid.to_string()).join("comm")).map(|c| c.trim().to_string()).unwrap_or_default())
        .collect();
    crate::log::write("child", &format!("ending {} child process(es) still running: {}", left.len(), names.join(", ")));
    for &pid in &left {
        // SAFETY: a signal to our own child.
        unsafe { libc::kill(pid, libc::SIGTERM) };
    }
    let deadline = Instant::now() + Duration::from_millis(1500);
    let mut still = left.clone();
    while !still.is_empty() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(50));
        still = own_children(proc_root, me, session).into_iter().filter(|p| left.contains(p)).collect();
    }
    for &pid in &still {
        // SAFETY: a signal to our own child that did not end.
        unsafe { libc::kill(pid, libc::SIGKILL) };
    }
    if !still.is_empty() {
        crate::log::write("child", &format!("{} child process(es) still there after 1.5 s: SIGKILL", still.len()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_own_children_only() {
        let dir = std::env::temp_dir().join(format!("gc-ending-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let put = |pid: i32, stat: &str| {
            std::fs::create_dir_all(dir.join(pid.to_string())).unwrap();
            std::fs::write(dir.join(pid.to_string()).join("stat"), stat).unwrap();
        };
        put(10, "10 (mpv) S 1 10 1 0 -1");
        put(11, "11 (pipewire) S 5 11 5 0 -1");
        put(12, "12 (sh) S 5 12 12 0 -1"); // own session (setsid)
        put(13, "13 (curl) Z 5 13 5 0 -1"); // already ended
        put(14, "14 (a b) c) S 5 14 5 0 -1"); // a name with ") "
        let mut found = own_children(&dir, 5, 5);
        found.sort_unstable();
        assert_eq!(found, vec![11, 14]);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
