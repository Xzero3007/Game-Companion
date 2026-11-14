//! Game Companion: one overlay for every game on Linux (KDE Plasma, Wayland).

mod aion2_object;
mod alert;
mod aion2timers;
mod appinfo;
mod apps;
mod apps_object;
mod armory;
mod companion;
mod covers;
mod emotes;
mod games;
mod games_object;
mod instance;
mod jellyfin;
mod jellyfin_object;
mod library;
mod library_object;
mod launch_check;
mod launch_demo;
mod launch_options;
mod market;
mod meter_import;
mod native;
mod protondb;
mod radio;
mod radio_object;
mod settings;
mod shortcuts;
mod sponsorblock;
mod start_with;
mod streams;
mod streams_object;
mod tray;
mod system_info;
mod updater;
mod updates_object;
mod vdf_edit;
mod voice;

fn main() {
    if std::env::args().any(|a| a == "--version") {
        println!("Game Companion {}", companion::version_text());
        return;
    }
    // One Game Companion at a time: a second start brings the running one
    // forward (unless it was started hidden, as with the desktop) and ends.
    let dir = instance::runtime_dir();
    let Some(_lock) = instance::lock(&dir) else {
        if std::env::args().any(|a| a == "--hidden") {
            return;
        }
        if !instance::ask_to_show(&dir) {
            eprintln!("Game Companion is already running.");
        }
        return;
    };
    if let Some(listener) = instance::bind(&dir) {
        instance::keep(listener);
    }
    quit_on_signals();
    cxx_qt::init_crate!(game_companion);
    cxx_qt::init_qml_module!("GameCompanion");
    let code = native::run();
    // Where the last video stopped, if not yet written.
    library::save_now();
    // Brave and Legcord back as they were; what Game Companion started for
    // them closes (unless the person chose otherwise).
    apps::quit();
    std::process::exit(code);
}

/// SIGTERM, SIGINT or SIGHUP (the session ending, `kill`): the app quits as
/// if "Turn off" was pressed, so everything it leaves (Brave and Legcord put
/// back, what it started closed, the last video's place) is tidied. Should
/// that hang, it ends anyway after 10 s; a second signal ends it at once.
fn quit_on_signals() {
    use std::sync::atomic::{AtomicI32, Ordering};
    static WRITE: AtomicI32 = AtomicI32::new(-1);
    extern "C" fn on_signal(_: libc::c_int) {
        let fd = WRITE.load(Ordering::Relaxed);
        if fd >= 0 {
            // SAFETY: write is async-signal-safe; one byte to our own pipe.
            unsafe { libc::write(fd, b"q".as_ptr().cast(), 1) };
        }
    }
    let mut fds = [0 as libc::c_int; 2];
    // SAFETY: a fresh close-on-exec pipe for this process.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return;
    }
    WRITE.store(fds[1], Ordering::Relaxed);
    for sig in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        // SAFETY: installs a handler that only writes to the pipe; children
        // get the default handling back when they start a program (exec).
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_signal as *const () as usize;
            action.sa_flags = libc::SA_RESTART;
            libc::sigemptyset(&mut action.sa_mask);
            libc::sigaction(sig, &action, std::ptr::null_mut());
        }
    }
    let read = fds[0];
    std::thread::Builder::new()
        .name("signals".into())
        .spawn(move || {
            let mut byte = [0u8; 1];
            let mut seen = 0;
            // SAFETY: reads from our own pipe; blocks until a signal came.
            while unsafe { libc::read(read, byte.as_mut_ptr().cast(), 1) } == 1 {
                seen += 1;
                if seen > 1 {
                    // SAFETY: ends the process at once (second signal).
                    unsafe { libc::_exit(1) };
                }
                native::quit();
                std::thread::spawn(|| {
                    std::thread::sleep(std::time::Duration::from_secs(10));
                    // SAFETY: the tidy quit hung: end anyway.
                    unsafe { libc::_exit(1) };
                });
            }
        })
        .ok();
}

