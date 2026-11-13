//! Game Companion's capture helper: the one program allowed to listen to
//! the network (`cap_net_raw`, set by the package), so the app itself needs
//! no rights. It copies TCP segments to its stdout for the app, which reads
//! AION 2 out of them. It never sends anything anywhere and keeps nothing.
//!
//! So that it is of no use for anything else, it:
//! - runs only as the child of the installed app (checked by file identity),
//!   and ends with it;
//! - listens only while an AION 2 process runs, and ends soon after it;
//! - never captures the web's ports (80, 443) or any port below 1024, and
//!   never captures without a filter, whatever the app asks.

use std::io::{BufRead, BufWriter, Write};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use aion2::capture::combat_port_detector::CombatPortDetector;
use aion2::capture::pcap_capturer::PcapCapturer;
use aion2::link::{self, State};

const APP: &str = "/usr/bin/game-companion";
const INSTALLED_DIR: &str = "/usr/lib/game-companion/";
/// How long AION 2 may be gone before the helper ends.
const GONE_FOR: Duration = Duration::from_secs(10);

fn main() {
    if !started_by_the_app() {
        fail(2, "runs only as part of Game Companion");
    }
    // SAFETY: prctl with these arguments only sets a flag on this process.
    unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) };
    if !may_capture() {
        fail(1, aion2::platform::pcap::MISSING_HELP);
    }

    let detector = Arc::new(CombatPortDetector::new());
    // The app's word on the game's connection. Ports the helper never
    // captures are not taken; "AION 2 runs" is not taken either (it would
    // let the capture drop its filter after a minute without the game).
    {
        let detector = detector.clone();
        std::thread::spawn(move || {
            for line in std::io::stdin().lock().lines() {
                let Ok(line) = line else { break };
                if let Some(state) = State::parse(&line) {
                    detector.mirror(state.port.filter(|&p| allowed_port(p)), state.last_parsed_ms, state.last_from_port_ms);
                }
            }
            // The app is gone.
            std::process::exit(0);
        });
    }

    // Only while AION 2 runs.
    while !aion2_runs() {
        std::thread::sleep(Duration::from_secs(2));
    }
    // Never without the filter (see REQUIRE_FILTER).
    aion2::capture::pcap_capturer::REQUIRE_FILTER.store(true, std::sync::atomic::Ordering::SeqCst);
    let (tx, mut rx) = tokio::sync::mpsc::channel(4096);
    let capturer = PcapCapturer::new(tx, detector);
    capturer.start();
    if !capturer.is_running() {
        fail(1, "libpcap could not start capturing (is libpcap installed?)");
    }
    std::thread::spawn(|| {
        let mut seen = Instant::now();
        loop {
            std::thread::sleep(Duration::from_secs(3));
            if aion2_runs() {
                seen = Instant::now();
            } else if seen.elapsed() >= GONE_FOR {
                std::process::exit(0);
            }
        }
    });

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

fn fail(code: i32, why: &str) -> ! {
    eprintln!("game-companion-capture: {why}");
    std::process::exit(code);
}

/// Ports the helper may narrow its filter to: never the web's, never a
/// system service's.
fn allowed_port(port: u16) -> bool {
    port >= 1024
}

/// Whether the parent process is Game Companion: for the installed helper
/// the very file /usr/bin/game-companion (root's, not writable by others);
/// a build elsewhere (no rights, for tests) only checks the name.
fn started_by_the_app() -> bool {
    let parent = format!("/proc/{}/exe", std::os::unix::process::parent_id());
    let installed = std::env::current_exe().is_ok_and(|exe| exe.starts_with(INSTALLED_DIR));
    if installed {
        let (Ok(theirs), Ok(app)) = (std::fs::metadata(&parent), std::fs::metadata(APP)) else { return false };
        theirs.dev() == app.dev() && theirs.ino() == app.ino() && app.uid() == 0 && app.mode() & 0o022 == 0
    } else {
        std::fs::read_link(&parent)
            .ok()
            .and_then(|exe| exe.file_name().map(|n| n.to_string_lossy().into_owned()))
            .is_some_and(|name| name == "game-companion")
    }
}

/// Whether this process may capture: root, or CAP_NET_RAW in effect.
fn may_capture() -> bool {
    // SAFETY: geteuid has no preconditions.
    if unsafe { libc::geteuid() } == 0 {
        return true;
    }
    let status = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    cap_net_raw_in(&status)
}

fn cap_net_raw_in(status: &str) -> bool {
    status
        .lines()
        .find_map(|l| l.strip_prefix("CapEff:"))
        .and_then(|hex| u64::from_str_radix(hex.trim(), 16).ok())
        .is_some_and(|caps| caps & (1 << 13) != 0)
}

/// Whether an AION 2 process runs (its Windows program under Proton).
fn aion2_runs() -> bool {
    let Ok(entries) = std::fs::read_dir("/proc") else { return false };
    entries.flatten().any(|entry| {
        let name = entry.file_name();
        if !name.to_string_lossy().bytes().all(|b| b.is_ascii_digit()) {
            return false;
        }
        is_aion2(&entry.path())
    })
}

fn is_aion2(proc_dir: &Path) -> bool {
    let comm = std::fs::read_to_string(proc_dir.join("comm")).unwrap_or_default();
    if comm.trim().eq_ignore_ascii_case("AION2.exe") {
        return true;
    }
    std::fs::read(proc_dir.join("cmdline")).is_ok_and(|cmd| {
        cmd.split(|&b| b == 0)
            .next()
            .map(|first| String::from_utf8_lossy(first).replace('\\', "/"))
            .is_some_and(|first| first.rsplit('/').next().is_some_and(|f| f.eq_ignore_ascii_case("AION2.exe")))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_capability_is_read_from_the_status() {
        assert!(cap_net_raw_in("Name:\tx\nCapEff:\t0000000000002000\n"));
        assert!(!cap_net_raw_in("CapEff:\t0000000000000000\n"));
        assert!(!cap_net_raw_in("nothing"));
    }

    #[test]
    fn system_and_web_ports_are_never_taken() {
        assert!(!allowed_port(80) && !allowed_port(443) && !allowed_port(22));
        assert!(allowed_port(13328));
    }
}
