//! Game Companion's capture helper: the one program allowed to listen to
//! the network (`cap_net_raw`, set by the package), so the app itself needs
//! no rights. It copies TCP segments (not the web's ports 80 and 443, and
//! once the game's connection is known only that one) to its stdout for the
//! app, which reads AION 2 out of them. It never sends anything anywhere,
//! keeps nothing, and runs only as the app's child.

use std::io::{BufRead, BufWriter, Write};
use std::sync::Arc;

use aion2::capture::combat_port_detector::CombatPortDetector;
use aion2::capture::pcap_capturer::PcapCapturer;
use aion2::link::{self, State};
use aion2::platform::window_detector;

fn main() {
    // Only for Game Companion: started by it, ending with it.
    if !started_by_the_app() {
        eprintln!("game-companion-capture: runs only as part of Game Companion");
        std::process::exit(2);
    }
    // SAFETY: prctl with these arguments only sets a flag on this process.
    unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) };

    let detector = Arc::new(CombatPortDetector::new());
    let (tx, mut rx) = tokio::sync::mpsc::channel(4096);
    let capturer = PcapCapturer::new(tx, detector.clone());

    // The app's word on the game's connection and whether AION 2 runs.
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if let Some(state) = State::parse(&line) {
                detector.mirror(state.port, state.last_parsed_ms, state.last_from_port_ms);
                window_detector::set_running(state.game_running);
            }
        }
        // The app is gone.
        std::process::exit(0);
    });

    capturer.start();
    if !capturer.is_running() {
        eprintln!("game-companion-capture: {}", aion2::platform::pcap::MISSING_HELP);
        std::process::exit(1);
    }
    let mut out = BufWriter::new(std::io::stdout().lock());
    while let Some(payload) = rx.blocking_recv() {
        if link::write_segment(&mut out, &payload).is_err() {
            break;
        }
        if rx.is_empty() && out.flush().is_err() {
            break;
        }
    }
}

/// Whether the parent process is Game Companion.
fn started_by_the_app() -> bool {
    let parent = std::os::unix::process::parent_id();
    std::fs::read_link(format!("/proc/{parent}/exe"))
        .ok()
        .and_then(|exe| exe.file_name().map(|n| n.to_string_lossy().into_owned()))
        .is_some_and(|name| name == "game-companion")
}
