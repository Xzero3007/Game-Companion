//! One Game Companion at a time, and a second start brings the running one
//! forward.
//!
//! The running copy holds an exclusive lock on `game-companion.lock` and
//! listens on the Unix socket `game-companion.sock` beside it (both in the
//! runtime folder, which only the user can open). A second start finds the
//! lock taken, writes "show" to the socket and ends. The running copy's
//! listener thread blocks in `accept` (no polling) and queues the request
//! onto the Qt thread. Nothing here leaves the computer.

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

/// What a second start sends.
const SHOW: &[u8] = b"show\n";

/// The listener made at the start, until Companion takes it.
static LISTENER: Mutex<Option<UnixListener>> = Mutex::new(None);

/// `$XDG_RUNTIME_DIR`, or the cache folder where there is none.
pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(crate::updater::cache_dir)
}

fn socket_path(dir: &Path) -> PathBuf {
    dir.join("game-companion.sock")
}

/// Holds an exclusive lock on `game-companion.lock` in `dir` for as long as
/// the file lives; None if another copy holds it. The system lets go of it
/// when the process ends, however it ends.
pub fn lock(dir: &Path) -> Option<std::fs::File> {
    use std::os::unix::io::AsRawFd;
    let _ = std::fs::create_dir_all(dir);
    let path = dir.join("game-companion.lock");
    // Opened close-on-exec (Rust's default): mpv and the installer never
    // inherit it.
    let file = match std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(&path) {
        Ok(file) => file,
        // No lock file possible: run rather than not at all.
        Err(_) => return std::fs::File::open("/dev/null").ok(),
    };
    // SAFETY: flock on a file descriptor this function owns.
    let locked = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0;
    locked.then_some(file)
}

/// Opens the socket a second start writes to. Call only while holding the
/// lock: a socket file left by a copy that crashed is replaced.
pub fn bind(dir: &Path) -> Option<UnixListener> {
    use std::os::unix::fs::PermissionsExt;
    let path = socket_path(dir);
    let _ = std::fs::remove_file(&path);
    // Close-on-exec (Rust's default): no child inherits it.
    let listener = UnixListener::bind(&path).ok()?;
    // Only the user may connect (the runtime folder is theirs already; the
    // cache folder fallback may not be).
    let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
    Some(listener)
}

/// Keeps the listener until `serve` takes it.
pub fn keep(listener: UnixListener) {
    if let Ok(mut slot) = LISTENER.lock() {
        *slot = Some(listener);
    }
}

/// Asks the running copy to show its hub; true if it took the request.
pub fn ask_to_show(dir: &Path) -> bool {
    let Ok(mut stream) = UnixStream::connect(socket_path(dir)) else { return false };
    let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
    stream.write_all(SHOW).is_ok()
}

/// Reads one request from a second start: true for "show".
fn read_request(mut stream: UnixStream) -> bool {
    // A client that never writes cannot hold the listener for long.
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    let mut buf = [0u8; 16];
    let mut len = 0;
    while len < buf.len() {
        match stream.read(&mut buf[len..]) {
            Ok(0) => break,
            Ok(n) => {
                len += n;
                if buf[..len].contains(&b'\n') {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    &buf[..len] == SHOW
}

/// Calls `show` for every "show" a second start sends, on a thread of its
/// own that sleeps in `accept`. Does nothing without a listener (or when
/// called again).
pub fn serve(show: impl Fn() + Send + 'static) {
    let Some(listener) = LISTENER.lock().ok().and_then(|mut slot| slot.take()) else { return };
    serve_on(listener, show);
}

fn serve_on(listener: UnixListener, show: impl Fn() + Send + 'static) {
    let _ = std::thread::Builder::new().name("instance".into()).spawn(move || {
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    if read_request(stream) {
                        show();
                    }
                }
                // The socket broke for good: stop listening.
                Err(e) if matches!(e.raw_os_error(), Some(libc::EBADF | libc::EINVAL | libc::ENOTSOCK)) => break,
                Err(_) => {}
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("gc-instance-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn second_lock_is_refused() {
        let dir = scratch("lock");
        let first = lock(&dir);
        assert!(first.is_some());
        assert!(lock(&dir).is_none());
        drop(first);
        assert!(lock(&dir).is_some());
    }

    #[test]
    fn a_second_start_asks_to_show() {
        let dir = scratch("show");
        assert!(!ask_to_show(&dir), "nobody listens yet");
        let listener = bind(&dir).unwrap();
        let (tx, rx) = mpsc::channel();
        serve_on(listener, move || tx.send(()).unwrap());
        assert!(ask_to_show(&dir));
        rx.recv_timeout(Duration::from_secs(3)).expect("show arrives");
        // Anything else is ignored.
        let mut other = UnixStream::connect(socket_path(&dir)).unwrap();
        other.write_all(b"quit\n").unwrap();
        drop(other);
        assert!(ask_to_show(&dir));
        rx.recv_timeout(Duration::from_secs(3)).expect("the second show arrives");
        assert!(rx.try_recv().is_err(), "quit was not taken as show");
    }

    #[test]
    fn a_stale_socket_is_replaced() {
        let dir = scratch("stale");
        drop(bind(&dir).unwrap());
        assert!(socket_path(&dir).exists());
        assert!(bind(&dir).is_some());
    }
}
