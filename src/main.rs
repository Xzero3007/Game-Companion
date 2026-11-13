//! Game Companion: one overlay for every game on Linux (KDE Plasma, Wayland).

mod companion;
mod games;
mod games_object;
mod jellyfin;
mod jellyfin_object;
mod launch_check;
mod launch_options;
mod native;
mod protondb;
mod radio;
mod radio_object;
mod settings;
mod shortcuts;
mod sponsorblock;
mod streams;
mod streams_object;
mod system_info;
mod updater;
mod updates_object;
mod vdf_edit;

fn main() {
    if std::env::args().any(|a| a == "--version") {
        println!("Game Companion {}", companion::version_text());
        return;
    }
    // One Game Companion at a time: a second start ends at once.
    let Some(_lock) = single_instance() else {
        eprintln!("Game Companion is already running.");
        return;
    };
    cxx_qt::init_crate!(game_companion);
    cxx_qt::init_qml_module!("GameCompanion");
    std::process::exit(native::run());
}

/// Holds an exclusive lock on `game-companion.lock` (in the runtime
/// folder) for as long as the app runs; None if another copy holds it. The
/// system lets go of it when the process ends, however it ends.
fn single_instance() -> Option<std::fs::File> {
    use std::os::unix::io::AsRawFd;
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(updater::cache_dir);
    let _ = std::fs::create_dir_all(&dir);
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
