//! One voice for the AION 2 module (the Boss panel's calls now, the other
//! areas' reminders later): the built-in English clips (A2 Tools' Boss
//! Callouts voice, made with Kokoro; `aion2/boss/voice`) played by mpv, and
//! for words with no clip (the person's own) the computer's voice through
//! speech-dispatcher's `spd-say`, when it is installed (else a beep). Nothing
//! goes online.
//!
//! Lines queue, two at most; a high line (what to do now) cuts off a low one
//! (a boss's line still being read). One worker thread for the app's life:
//! the players it starts die with it (PR_SET_PDEATHSIG follows the thread).

use std::collections::{HashMap, VecDeque};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq)]
pub struct Line {
    pub text: String,
    /// What to do now: cuts off a low line still being read.
    pub high: bool,
    /// The person's own words: always the computer's voice.
    pub own: bool,
    /// 0 to 100.
    pub volume: u8,
    /// 0.5 to 2.
    pub rate: f32,
}

enum Job {
    Say(Line),
    Beep(u8),
    Hush,
}

/// Lines waiting besides the one being read.
const QUEUE: usize = 2;

fn sender() -> &'static Mutex<Sender<Job>> {
    static SENDER: OnceLock<Mutex<Sender<Job>>> = OnceLock::new();
    SENDER.get_or_init(|| {
        let (tx, rx) = mpsc::channel();
        let _ = std::thread::Builder::new().name("voice".into()).spawn(move || work(rx));
        Mutex::new(tx)
    })
}

pub fn say(line: Line) {
    let text: String = line.text.trim().chars().filter(|c| !c.is_control()).take(300).collect();
    if text.is_empty() {
        return;
    }
    let _ = sender().lock().unwrap_or_else(|p| p.into_inner()).send(Job::Say(Line { text, ..line }));
}

pub fn beep(volume: u8) {
    let _ = sender().lock().unwrap_or_else(|p| p.into_inner()).send(Job::Beep(volume));
}

/// Stops what is being read and what waits.
pub fn hush() {
    let _ = sender().lock().unwrap_or_else(|p| p.into_inner()).send(Job::Hush);
}

/// Whether the computer's voice (speech-dispatcher's spd-say) is there.
pub fn system_voice() -> bool {
    find("spd-say").is_some()
}

fn find(program: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")?.to_str()?.split(':').map(|d| PathBuf::from(d).join(program)).find(|p| p.is_file())
}

/// The built-in clips: line → file.
fn clips() -> &'static HashMap<String, PathBuf> {
    static CLIPS: OnceLock<HashMap<String, PathBuf>> = OnceLock::new();
    CLIPS.get_or_init(|| {
        let dir = aion2::data_dir().join("boss/voice");
        let index: HashMap<String, String> = std::fs::read_to_string(dir.join("index.json"))
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        index
            .into_iter()
            .filter(|(_, f)| !f.contains('/') && f.ends_with(".ogg"))
            .map(|(t, f)| (t, dir.join(f)))
            .collect()
    })
}

/// A built-in clip for these words, if there is one.
pub fn clip_for(text: &str) -> Option<PathBuf> {
    clips().get(text.trim()).filter(|p| p.is_file()).cloned()
}

fn work(rx: Receiver<Job>) {
    let mut waiting: VecDeque<Job> = VecDeque::new();
    let mut now: Option<(Child, bool)> = None;
    loop {
        let job = if now.is_none() && waiting.is_empty() {
            match rx.recv() {
                Ok(job) => Some(job),
                Err(_) => return,
            }
        } else {
            match rx.recv_timeout(Duration::from_millis(40)) {
                Ok(job) => Some(job),
                Err(RecvTimeoutError::Timeout) => None,
                Err(RecvTimeoutError::Disconnected) => return,
            }
        };
        match job {
            Some(Job::Hush) => {
                waiting.clear();
                if let Some((mut child, _)) = now.take() {
                    let _ = child.kill();
                    let _ = child.wait();
                }
            }
            Some(job) => {
                let high = matches!(&job, Job::Say(l) if l.high) || matches!(job, Job::Beep(_));
                // A high line cuts off a low one being read.
                if high && now.as_ref().is_some_and(|(_, h)| !h) {
                    if let Some((mut child, _)) = now.take() {
                        let _ = child.kill();
                        let _ = child.wait();
                    }
                    waiting.retain(|j| matches!(j, Job::Say(l) if l.high) || matches!(j, Job::Beep(_)));
                }
                if waiting.len() < QUEUE {
                    if high {
                        // Ahead of low lines waiting.
                        let at = waiting.iter().position(|j| matches!(j, Job::Say(l) if !l.high)).unwrap_or(waiting.len());
                        waiting.insert(at, job);
                    } else {
                        waiting.push_back(job);
                    }
                }
            }
            None => {}
        }
        if let Some((child, _)) = now.as_mut() {
            if !matches!(child.try_wait(), Ok(None)) {
                now = None;
            }
        }
        if now.is_none() {
            while let Some(job) = waiting.pop_front() {
                let started = match job {
                    Job::Say(line) => start(&line).map(|c| (c, line.high)),
                    Job::Beep(volume) => beep_file().and_then(|f| play(&f, volume, 1.0)).map(|c| (c, true)),
                    Job::Hush => None,
                };
                if started.is_some() {
                    now = started;
                    break;
                }
            }
        }
    }
}

fn start(line: &Line) -> Option<Child> {
    if !line.own {
        if let Some(clip) = clip_for(&line.text) {
            return play(&clip, line.volume, line.rate);
        }
    }
    // Without the computer's voice a beep at least says something came
    // (MN, 0.8.12: the Ludra preview showed its calls without a sound).
    let Some(spd) = find("spd-say") else {
        return beep_file().and_then(|f| play(&f, line.volume, 1.0));
    };
    let rate = ((line.rate - 1.0) * 100.0).round().clamp(-100.0, 100.0) as i32;
    let volume = (i32::from(line.volume.min(100)) * 2 - 100).clamp(-100, 100);
    let mut command = Command::new(spd);
    command
        .args(["-w", "-l", "en", "-r", &rate.to_string(), "-i", &volume.to_string(), "--"])
        .arg(&line.text);
    spawn(command)
}

fn play(file: &std::path::Path, volume: u8, rate: f32) -> Option<Child> {
    let mut command = Command::new("mpv");
    command
        .args(["--no-config", "--no-video", "--no-terminal", "--really-quiet", "--ytdl=no", "--audio-display=no"])
        .arg(format!("--volume={}", crate::radio::mpv_volume(volume)))
        .arg(format!("--speed={:.2}", rate.clamp(0.5, 2.0)))
        .arg("--")
        .arg(file);
    spawn(command)
}

fn spawn(mut command: Command) -> Option<Child> {
    command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    // SAFETY: prctl only sets a flag on the child; no allocation.
    unsafe {
        command.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    command.spawn().ok()
}

/// A short beep (880 Hz, 120 ms), written once where the app may write.
fn beep_file() -> Option<PathBuf> {
    static FILE: OnceLock<Option<PathBuf>> = OnceLock::new();
    FILE.get_or_init(|| {
        let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
        let path = dir.join("game-companion-beep.wav");
        std::fs::write(&path, wav_beep()).ok().map(|_| path)
    })
    .clone()
}

fn wav_beep() -> Vec<u8> {
    const RATE: u32 = 22050;
    let n = RATE * 12 / 100;
    let samples: Vec<i16> = (0..n)
        .map(|i| {
            let t = i as f32 / RATE as f32;
            let fade = (1.0 - i as f32 / n as f32).min(i as f32 / 200.0).min(1.0);
            ((t * 880.0 * std::f32::consts::TAU).sin() * fade * 12000.0) as i16
        })
        .collect();
    let data = n * 2;
    let mut w = Vec::with_capacity(44 + data as usize);
    w.extend(b"RIFF");
    w.extend((36 + data).to_le_bytes());
    w.extend(b"WAVEfmt ");
    w.extend(16u32.to_le_bytes());
    w.extend(1u16.to_le_bytes());
    w.extend(1u16.to_le_bytes());
    w.extend(RATE.to_le_bytes());
    w.extend((RATE * 2).to_le_bytes());
    w.extend(2u16.to_le_bytes());
    w.extend(16u16.to_le_bytes());
    w.extend(b"data");
    w.extend(data.to_le_bytes());
    for s in samples {
        w.extend(s.to_le_bytes());
    }
    w
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_beep_is_a_wav() {
        let w = wav_beep();
        assert_eq!(&w[0..4], b"RIFF");
        assert_eq!(w.len(), 44 + 22050 * 12 / 100 * 2);
    }

    #[test]
    fn the_built_in_voice_has_the_checked_calls() {
        assert!(clip_for("Surging violet!").is_some());
        assert!(clip_for("no such line at all").is_none());
    }
}
