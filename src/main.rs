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
mod ending;
mod emotes;
mod games;
mod games_object;
mod instance;
mod jellyfin;
mod jellyfin_object;
mod library;
mod log;
mod library_object;
mod launch_check;
mod launch_demo;
mod launch_options;
mod market;
mod meter_import;
mod native;
mod poe2;
mod poe2_kit;
mod poe2_log;
mod poe2_log_object;
mod poe2_object;
mod protondb;
mod proton_get;
mod proton_object;
mod radio;
mod radio_object;
mod settings;
mod shortcuts;
mod sound;
mod sound_object;
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
mod voice_object;
mod yt_hdr;
mod voice_overlay;

fn main() {
    // The PoE 2 price check's kit in its own process (src/poe2_kit.rs).
    if std::env::args().nth(1).as_deref() == Some("--poe2-kit") {
        std::process::exit(poe2_kit::main());
    }
    // Qt's JavaScript without its JIT: Qt 6.12's JIT crashed in the PoE 2
    // price check's parser (Exiled Exchange 2's code; QA on Arch,
    // 2026-11-15: SIGSEGV in ArrayLiteral → newArrayObject, every run, none
    // with the interpreter). The interpreter cost no more CPU in the demos
    // (most bindings are compiled ahead anyway). `GC_JIT=1` keeps the JIT.
    // Set before any thread starts.
    if std::env::var_os("GC_JIT").is_none() && std::env::var_os("QV4_FORCE_INTERPRETER").is_none() {
        std::env::set_var("QV4_FORCE_INTERPRETER", "1");
    }
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
    log::start();
    if let Some(listener) = instance::bind(&dir) {
        instance::keep(listener);
    }
    quit_on_signals();
    cxx_qt::init_crate!(game_companion);
    cxx_qt::init_qml_module!("GameCompanion");
    // Qt's own reconnect after a broken Wayland connection (KDE sets
    // QT_WAYLAND_RECONNECT) ended the app without a word at logout: it
    // connected again to nothing and Qt called _exit (MN, 0.8.64). Without
    // it, a broken connection reaches `gc_display_lost`, which ends cleanly.
    // GC_WAYLAND_RECONNECT=1 keeps Qt's way.
    if std::env::var_os("GC_WAYLAND_RECONNECT").is_none() {
        std::env::remove_var("QT_WAYLAND_RECONNECT");
    }
    quit_step(QuitStep::Qt);
    let code = native::run();
    tidy();
    quit_step(QuitStep::Done);
    log::end(code);
    std::process::exit(code);
}

/// What is put in order after Qt (or without it, `gc_display_lost`).
fn tidy() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        // Where the last video stopped, if not yet written.
        quit_step(QuitStep::Library);
        library::save_now();
        // Brave and Legcord back as they were; what Game Companion started
        // for them closes (unless the person chose otherwise).
        quit_step(QuitStep::Apps);
        apps::quit();
        quit_step(QuitStep::Children);
        poe2_kit::stop();
        // A Proton download: curl or tar ended, half-done files removed.
        proton_get::stop();
        poe2_log::stop();
        voice_overlay::quit();
        // Anything still running that we started (mpv, the sound chains,
        // the meter's helper, a curl): none stays behind.
        ending::children();
    });
}

/// Called by cpp/native.cpp when the Wayland connection broke (the session
/// ends, or KWin went away): Qt would end the process right after, without
/// its windows and the QML taken down. Puts everything in order and ends.
#[no_mangle]
pub extern "C" fn gc_display_lost() {
    log::write("app", "quit: the Wayland connection broke (the session ends or KWin went away)");
    std::thread::spawn(|| {
        std::thread::sleep(std::time::Duration::from_secs(8));
        log::forced(&format!("quit hung for 8 s after the Wayland connection broke while {}: ending anyway", quit_step_text()));
        // SAFETY: the tidy quit hung: end anyway.
        unsafe { libc::_exit(1) };
    });
    quit_step(QuitStep::QtWindows);
    // What modules finish themselves when Qt takes them down (the meter's
    // battle history).
    ending::run_hooks();
    tidy();
    quit_step(QuitStep::Done);
    log::end(0);
    // Not exit(): Qt's and C++'s own clean-up would talk to a display that
    // is gone.
    // SAFETY: ends the process; everything is written and put in order.
    unsafe { libc::_exit(0) };
}

/// Where the app is on its way out, for the log when a quit hangs.
#[derive(Clone, Copy)]
#[repr(usize)]
enum QuitStep {
    Qt = 0,
    QtWindows,
    Library,
    Apps,
    Children,
    Done,
}

static QUIT_STEP: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

fn quit_step(step: QuitStep) {
    QUIT_STEP.store(step as usize, std::sync::atomic::Ordering::SeqCst);
}

/// What the app was doing at the step it reached, in words.
fn quit_step_text() -> &'static str {
    match QUIT_STEP.load(std::sync::atomic::Ordering::SeqCst) {
        0 => "Qt's event loop had not ended",
        1 => "closing the windows, the QML and the modules",
        2 => "writing the YouTube library",
        3 => "putting Brave and Legcord back (KWin)",
        4 => "ending the child processes",
        _ => "writing the end",
    }
}

/// Called by cpp/native.cpp when Qt's event loop has ended, before Qt
/// takes its windows and the QML down.
#[no_mangle]
pub extern "C" fn gc_loop_ended() {
    quit_step(QuitStep::QtWindows);
    log::write("app", "Qt's event loop ended");
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
                log::write("app", if seen > 1 { "quit: second signal, ending at once" } else { "quit: signal (SIGTERM, SIGINT or SIGHUP)" });
                if seen > 1 {
                    // SAFETY: ends the process at once (second signal).
                    unsafe { libc::_exit(1) };
                }
                native::quit();
                std::thread::spawn(|| {
                    std::thread::sleep(std::time::Duration::from_secs(10));
                    log::forced(&format!("quit hung for 10 s after the signal while {}: ending anyway", quit_step_text()));
                    // SAFETY: the tidy quit hung: end anyway.
                    unsafe { libc::_exit(1) };
                });
            }
        })
        .ok();
}

