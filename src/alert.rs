//! The Schedule's alerts: a short sound, made here (no sound files), played
//! by the desktop's player (pw-play, paplay, aplay or mpv, the first there),
//! and the desktop's speech (speech-dispatcher's spd-say) when asked. Both
//! run in the background and die with the app. Nothing leaves the computer.

use std::f32::consts::TAU;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// The sounds there are, as Settings lists them.
pub const SOUNDS: &[&str] = &["chime", "bell", "ping", "gong", "soft"];

const RATE: u32 = 44_100;

/// One sound as 16-bit mono samples: a few decaying sine notes.
fn samples(sound: &str) -> Vec<i16> {
    // (frequency Hz, start s, length s, loudness)
    let notes: &[(f32, f32, f32, f32)] = match sound {
        "bell" => &[(880.0, 0.0, 1.2, 0.5), (1760.0, 0.0, 0.8, 0.2), (2640.0, 0.0, 0.5, 0.1)],
        "ping" => &[(1568.0, 0.0, 0.35, 0.5)],
        "gong" => &[(196.0, 0.0, 1.8, 0.6), (293.7, 0.0, 1.4, 0.3), (392.0, 0.0, 1.0, 0.15)],
        "soft" => &[(523.3, 0.0, 0.6, 0.3), (659.3, 0.18, 0.6, 0.3)],
        _ => &[(659.3, 0.0, 0.6, 0.45), (880.0, 0.15, 0.6, 0.45), (1318.5, 0.3, 0.9, 0.4)],
    };
    let length = notes.iter().map(|n| n.1 + n.2).fold(0.0, f32::max);
    let count = (length * RATE as f32) as usize;
    let mut out = vec![0f32; count];
    for &(freq, start, len, loud) in notes {
        let from = (start * RATE as f32) as usize;
        let n = (len * RATE as f32) as usize;
        for i in 0..n.min(count.saturating_sub(from)) {
            let t = i as f32 / RATE as f32;
            // A quick rise (5 ms, no click) and a falling tail.
            let rise = (t / 0.005).min(1.0);
            let fall = (-4.0 * t / len).exp() * (1.0 - t / len);
            out[from + i] += loud * rise * fall * (TAU * freq * t).sin();
        }
    }
    out.iter().map(|v| (v.clamp(-1.0, 1.0) * 30_000.0) as i16).collect()
}

/// A sound as a WAV file's bytes.
fn wav(sound: &str, volume: i32) -> Vec<u8> {
    let gain = volume.clamp(0, 100) as f32 / 100.0;
    let data: Vec<u8> = samples(sound).iter().flat_map(|s| ((*s as f32 * gain) as i16).to_le_bytes()).collect();
    let mut out = Vec::with_capacity(44 + data.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&(RATE * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(&data);
    out
}

/// A program in PATH.
fn program(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")?.to_str()?.split(':').map(|d| Path::new(d).join(name)).find(|p| p.is_file())
}

/// Runs a player in the background; it ends with the app.
fn run(mut command: Command) {
    command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    // SAFETY: prctl only, between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    if let Ok(mut child) = command.spawn() {
        let _ = std::thread::Builder::new().name("alert-wait".into()).spawn(move || {
            let _ = child.wait();
        });
    }
}

/// Plays a sound (an unknown name plays the chime).
pub fn chime(sound: &str, volume: i32) {
    let sound: &'static str = SOUNDS.iter().copied().find(|s| *s == sound).unwrap_or(SOUNDS[0]);
    let volume = volume.clamp(0, 100);
    let _ = std::thread::Builder::new().name("alert".into()).spawn(move || {
        let dir = std::env::var_os("XDG_RUNTIME_DIR").map_or_else(std::env::temp_dir, PathBuf::from);
        let file = dir.join(format!("game-companion-{sound}-{volume}.wav"));
        if !file.is_file() && std::fs::write(&file, wav(sound, volume)).is_err() {
            return;
        }
        for (name, args) in [("pw-play", &[][..]), ("paplay", &[]), ("aplay", &["-q"]), ("mpv", &["--no-video", "--really-quiet", "--no-config"])] {
            if let Some(path) = program(name) {
                let mut command = Command::new(path);
                command.args(args).arg(&file);
                run(command);
                return;
            }
        }
    });
}

/// Whether spd-say is there.
pub fn can_speak() -> bool {
    program("spd-say").is_some()
}

/// Says a line with speech-dispatcher (English).
pub fn speak(text: &str) {
    let text: String = text.chars().filter(|c| !c.is_control()).take(200).collect();
    if text.trim().is_empty() {
        return;
    }
    if let Some(path) = program("spd-say") {
        let mut command = Command::new(path);
        command.args(["-l", "en", "--"]).arg(text);
        run(command);
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn every_sound_is_a_wav() {
        for sound in super::SOUNDS {
            let bytes = super::wav(sound, 80);
            assert_eq!(&bytes[..4], b"RIFF");
            assert!(bytes.len() > 44 + 10_000, "{sound} is too short");
        }
        assert_eq!(super::wav("chime", 0)[44..].iter().filter(|b| **b != 0).count(), 0);
    }
}
