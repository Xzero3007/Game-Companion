//! The app's own log, for finding faults without a terminal (MN,
//! 2026-11-15: "bau ein log ein"): `~/.cache/game-companion/game-companion.log`,
//! moved to `game-companion.log.1` once it passes 2 MB. Only what helps find
//! a fault goes in, never personal data: no tokens, accounts, item or chat
//! texts, and the home folder is written as `~` (MN: "nein zu persönlichen
//! daten und mehr daten als nötig"). Each line is written at once (no
//! buffer), so the last line before a crash is on disk.
//!
//! A crash (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL) writes the signal and
//! a backtrace with `write` only, then the signal goes on as before (core
//! dump, KDE's crash handler). A start after a session that did not end
//! cleanly says so. `GC_LOG=stderr` also prints each line to the terminal;
//! `GC_LOG=off` writes nothing.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Mutex;

/// Size after which the log moves to `.1` and a new one starts.
const LIMIT: u64 = 2 * 1024 * 1024;

struct Log {
    file: File,
    written: u64,
}

static LOG: Mutex<Option<Log>> = Mutex::new(None);
/// The open log's descriptor for the crash handler (-1 = none).
static FD: AtomicI32 = AtomicI32::new(-1);
static MIRROR: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn dir() -> PathBuf {
    crate::updater::cache_dir()
}

pub fn path() -> PathBuf {
    dir().join("game-companion.log")
}

/// Marks a running session; gone when it ends cleanly.
fn marker() -> PathBuf {
    dir().join("running")
}

fn open(path: &PathBuf) -> Option<File> {
    OpenOptions::new().create(true).append(true).mode(0o600).custom_flags(libc::O_CLOEXEC).open(path).ok()
}

/// Opens the log, notes an unclean last session and the start, and sets up
/// the crash handler. Called once, by the copy that holds the lock.
pub fn start() {
    match std::env::var("GC_LOG").as_deref() {
        Ok("off") => return,
        Ok("stderr") => MIRROR.store(true, Ordering::Relaxed),
        _ => {}
    }
    let _ = std::fs::create_dir_all(dir());
    let Some(file) = open(&path()) else { return };
    let written = file.metadata().map(|m| m.len()).unwrap_or(0);
    FD.store(file.as_raw_fd(), Ordering::Relaxed);
    *LOG.lock().unwrap_or_else(|e| e.into_inner()) = Some(Log { file, written });
    let unclean = marker().exists();
    let _ = std::fs::write(marker(), std::process::id().to_string());
    write("app", &format!("start: Game Companion {} (pid {})", crate::companion::version_text(), std::process::id()));
    if unclean {
        write("app", "the last session did not end cleanly (crash, kill or power loss); see the lines before this start");
    }
    crash_handler();
}

/// The app ended cleanly (after Qt, before exit).
pub fn end(code: i32) {
    write("app", &format!("end: exit code {code}"));
    let _ = std::fs::remove_file(marker());
}

/// Writes one line: time, area, text (secrets cut, home folder as `~`).
pub fn write(area: &str, text: &str) {
    let line = format!("{} [{area}] {}\n", now(), clean(text));
    if MIRROR.load(Ordering::Relaxed) {
        eprint!("{line}");
    }
    let mut guard = LOG.lock().unwrap_or_else(|e| e.into_inner());
    let Some(log) = guard.as_mut() else { return };
    if log.written + line.len() as u64 > LIMIT {
        let old = path().with_extension("log.1");
        let _ = std::fs::rename(path(), &old);
        if let Some(file) = open(&path()) {
            FD.store(file.as_raw_fd(), Ordering::Relaxed);
            log.file = file;
            log.written = 0;
        }
    }
    if log.file.write_all(line.as_bytes()).is_ok() {
        log.written += line.len() as u64;
    }
}

/// Shorthand: `log_line!("poe2", "answer {status}")`.
#[macro_export]
macro_rules! log_line {
    ($area:expr, $($arg:tt)*) => { $crate::log::write($area, &format!($($arg)*)) };
}

/// Opens the log's folder in the file manager (detached, no output).
pub fn open_folder() {
    use std::os::unix::process::CommandExt;
    let _ = std::fs::create_dir_all(dir());
    let mut command = std::process::Command::new("xdg-open");
    command.arg(dir()).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null());
    // SAFETY: setsid only, between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    match command.spawn() {
        Ok(mut child) => {
            std::thread::spawn(move || child.wait());
        }
        Err(e) => write("app", &format!("cannot open the log folder: {e}")),
    }
}

/// The last `lines` lines of the log (for "Copy log").
pub fn tail(lines: usize) -> String {
    let text = std::fs::read_to_string(path()).unwrap_or_default();
    let all: Vec<&str> = text.lines().collect();
    all[all.len().saturating_sub(lines)..].join("\n")
}

/// Local time with milliseconds.
fn now() -> String {
    let mut tv = libc::timeval { tv_sec: 0, tv_usec: 0 };
    // SAFETY: plain calls filling our own structs.
    let tm = unsafe {
        libc::gettimeofday(&mut tv, std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&tv.tv_sec, &mut tm);
        tm
    };
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec,
        tv.tv_usec / 1000
    )
}

/// Cuts what must never be written: tokens and keys after their marks, the
/// home folder (it holds the user name).
pub fn clean(text: &str) -> String {
    let mut out = text.replace(['\r', '\n'], " ");
    if let Some(home) = std::env::var_os("HOME").and_then(|h| h.into_string().ok()).filter(|h| h.len() > 1) {
        out = out.replace(home.trim_end_matches('/'), "~");
    }
    for mark in ["oauth:", "token=", "token:", "Token ", "Bearer ", "Authorization:", "authorization:", "api_key=", "ApiKey=", "password", "PASS "] {
        let mut from = 0;
        while let Some(at) = out[from..].find(mark) {
            let start = from + at + mark.len();
            let rest = &out[start..];
            let skip = rest.len() - rest.trim_start_matches([' ', '"', '=', ':']).len();
            let value = start + skip;
            let end = out[value..].find([' ', '"', '\'', ',', '&', ';', '}']).map_or(out.len(), |e| value + e);
            if end > value {
                out.replace_range(value..end, "<hidden>");
            }
            from = (value + "<hidden>".len()).min(out.len());
        }
    }
    if out.len() > 2000 {
        let mut cut = 2000;
        while !out.is_char_boundary(cut) {
            cut -= 1;
        }
        out.truncate(cut);
        out.push_str(" …");
    }
    out
}

extern "C" {
    fn backtrace(buffer: *mut *mut libc::c_void, size: libc::c_int) -> libc::c_int;
    fn backtrace_symbols_fd(buffer: *const *mut libc::c_void, size: libc::c_int, fd: libc::c_int);
}

/// On a fatal signal: the signal and a backtrace into the log with `write`
/// only (nothing that allocates or locks), then the signal's own handling.
fn crash_handler() {
    extern "C" fn on_crash(sig: libc::c_int) {
        let fd = FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let name: &[u8] = match sig {
                libc::SIGSEGV => b"SIGSEGV",
                libc::SIGABRT => b"SIGABRT",
                libc::SIGBUS => b"SIGBUS",
                libc::SIGFPE => b"SIGFPE",
                libc::SIGILL => b"SIGILL",
                _ => b"signal",
            };
            let put = |b: &[u8]| {
                // SAFETY: write is async-signal-safe.
                unsafe { libc::write(fd, b.as_ptr().cast(), b.len()) };
            };
            put(b"\n=== CRASH: ");
            put(name);
            put(b" on thread ");
            let mut tname = [0u8; 16];
            // SAFETY: reads this thread's name into our buffer.
            unsafe { libc::pthread_getname_np(libc::pthread_self(), tname.as_mut_ptr().cast(), tname.len()) };
            let n = tname.iter().position(|&c| c == 0).unwrap_or(tname.len());
            put(&tname[..n]);
            put(b"; backtrace:\n");
            let mut frames = [std::ptr::null_mut::<libc::c_void>(); 64];
            // SAFETY: glibc's backtrace was loaded at start (see below), so
            // it does not load libgcc here; symbols go straight to the fd.
            unsafe {
                let got = backtrace(frames.as_mut_ptr(), frames.len() as libc::c_int);
                backtrace_symbols_fd(frames.as_ptr(), got, fd);
            }
            put(b"=== end of crash report\n");
        }
        // SAFETY: SA_RESETHAND put the default back: raise it again so the
        // crash goes on as it would have (core dump, crash handler).
        unsafe { libc::raise(sig) };
    }
    // backtrace() loads libgcc on its first call; do that now, not in the
    // handler.
    let mut warm = [std::ptr::null_mut::<libc::c_void>(); 2];
    // SAFETY: fills our own buffer.
    unsafe { backtrace(warm.as_mut_ptr(), 2) };
    // A stack of its own, so a stack overflow can still be reported.
    const STACK: usize = 64 * 1024;
    let stack = Box::leak(vec![0u8; STACK].into_boxed_slice());
    let ss = libc::stack_t { ss_sp: stack.as_mut_ptr().cast(), ss_flags: 0, ss_size: STACK };
    // SAFETY: installs the alternate stack for this (the main) thread and the
    // handler for the fatal signals.
    unsafe {
        libc::sigaltstack(&ss, std::ptr::null_mut());
        for sig in [libc::SIGSEGV, libc::SIGABRT, libc::SIGBUS, libc::SIGFPE, libc::SIGILL] {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_crash as *const () as usize;
            action.sa_flags = libc::SA_RESETHAND | libc::SA_ONSTACK | libc::SA_NODEFER;
            libc::sigemptyset(&mut action.sa_mask);
            libc::sigaction(sig, &action, std::ptr::null_mut());
        }
    }
}

/// Qt's and QML's messages (cpp/native.cpp's message handler): warnings and
/// errors (QML's errors are warnings); console.log lines are left out.
#[no_mangle]
pub extern "C" fn gc_log_qt(kind: i32, text: *const libc::c_char) {
    if text.is_null() {
        return;
    }
    // SAFETY: Qt hands a NUL-terminated UTF-8 string valid for this call.
    let text = unsafe { std::ffi::CStr::from_ptr(text) }.to_string_lossy();
    // QtMsgType: 0 debug, 1 warning, 2 critical, 3 fatal, 4 info.
    let area = match kind {
        1 => "qt-warning",
        2 => "qt-critical",
        3 => "qt-fatal",
        _ => return,
    };
    if kind == 1 && !qt_worth_writing(&text) {
        return;
    }
    write(area, &text);
}

/// Most Qt warnings come in floods of one kind (a missing picture format for
/// every tile, the JS engine's lint for a library): each kind is written
/// once per session (numbers ignored), the lint never, and after
/// `QT_KINDS` kinds the rest is left out, so a start costs a few lines.
fn qt_worth_writing(text: &str) -> bool {
    const QT_KINDS: usize = 300;
    static SEEN: Mutex<Option<std::collections::HashSet<String>>> = Mutex::new(None);
    if text.contains("is used before its declaration") {
        return false;
    }
    let kind: String = text.chars().filter(|c| !c.is_ascii_digit()).take(160).collect();
    let mut guard = SEEN.lock().unwrap_or_else(|e| e.into_inner());
    let seen = guard.get_or_insert_with(Default::default);
    if seen.contains(&kind) || seen.len() > QT_KINDS {
        return false;
    }
    seen.insert(kind);
    if seen.len() > QT_KINDS {
        drop(guard);
        write("qt-warning", "more kinds of Qt warnings than this; the rest of this session's are left out");
        return false;
    }
    true
}

/// One line from C++ (cpp/native.cpp).
#[no_mangle]
pub extern "C" fn gc_log(area: *const libc::c_char, text: *const libc::c_char) {
    if area.is_null() || text.is_null() {
        return;
    }
    // SAFETY: NUL-terminated strings valid for this call.
    let (area, text) = unsafe { (std::ffi::CStr::from_ptr(area).to_string_lossy(), std::ffi::CStr::from_ptr(text).to_string_lossy()) };
    write(&area, &text);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secrets_are_cut() {
        let t = clean("PASS oauth:abc123 x token=zzz&y=1 Authorization: MediaBrowser Token=\"k\" Bearer qq");
        assert!(!t.contains("abc123"), "{t}");
        assert!(!t.contains("zzz"), "{t}");
        assert!(!t.contains("qq"), "{t}");
        assert!(t.contains("y=1"), "{t}");
    }

    #[test]
    fn home_becomes_tilde() {
        let home = std::env::var("HOME").unwrap_or_default();
        if home.len() > 1 {
            assert_eq!(clean(&format!("{home}/.config/x")), "~/.config/x");
        }
    }

    #[test]
    fn qt_floods_are_written_once() {
        assert!(qt_worth_writing("Image: Error decoding: tiles/1_2.webp"));
        assert!(!qt_worth_writing("Image: Error decoding: tiles/3_4.webp"));
        assert!(!qt_worth_writing("kit.js:1:2 Variable \"x\" is used before its declaration at 3:4."));
    }

    #[test]
    fn lines_stay_one_line() {
        assert_eq!(clean("a\nb"), "a b");
    }
}
