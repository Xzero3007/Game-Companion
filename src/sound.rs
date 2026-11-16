//! The sound module ("Sonar light" in Game Companion; plan: the project
//! folder's sound/ and the doc "Sound-Modul: Bauplan", MN 2026-11-15).
//!
//! Four channels (game, chat, media, music) as virtual outputs with their
//! own EQ, a microphone chain (echo cancellation, rnnoise with its voice
//! gate, a voice EQ) that comes out as "Game Companion Mikro", and a stream
//! mix for OBS.
//!
//! All sound work runs in PipeWire's own code: Game Companion starts
//! `pipewire -c <file>` as a child (a client hosting the filter chains, as
//! PipeWire's own filter-chain examples do). Nothing is written to
//! ~/.config/pipewire, the system's PipeWire is never restarted, and the
//! chains end with the app (PR_SET_PDEATHSIG): apps then play to the
//! default device again. Game Companion only moves streams (`pactl`) and
//! changes values (`pw-cli set-param`), on its own worker thread.
//!
//! Lessons from MN's logs (EasyEffects with 20 filters: 2 ms per cycle and
//! dropouts; without: 0.04 ms and none): few, cheap filters; no
//! DeepFilterNet, nothing with look-ahead.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The channels: key, node name, shown name.
pub const CHANNELS: [(&str, &str, &str); 4] = [
    ("game", "sonar_game", "Game Companion Spiel"),
    ("chat", "sonar_chat", "Game Companion Chat"),
    ("media", "sonar_media", "Game Companion Medien"),
    ("music", "sonar_music", "Game Companion Musik"),
];

/// The EQ's bands: name, filter, frequency (Hz), Q. As in Sonar light.
pub const BANDS: [(&str, &str, f64, f64); 5] = [
    ("b1", "bq_lowshelf", 80.0, 0.7),
    ("b2", "bq_peaking", 250.0, 1.0),
    ("b3", "bq_peaking", 1000.0, 1.0),
    ("b4", "bq_peaking", 3500.0, 1.0),
    ("b5", "bq_highshelf", 9000.0, 0.7),
];

/// Built-in presets: pre-gain, then the five bands, in dB (Sonar light's).
pub const PRESETS: [(&str, [f64; 6]); 5] = [
    ("Flat", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
    ("Bass-Boost", [-5.0, 6.0, 2.0, 0.0, 0.0, 1.0]),
    ("Racing", [-4.0, 4.0, 1.0, -1.0, 2.0, 2.0]),
    ("Sprache", [-3.0, -4.0, -1.0, 1.0, 3.0, 1.0]),
    ("Film", [-3.0, 3.0, 0.0, 0.0, 2.0, 1.0]),
];

/// The echo canceller's reference: it listens to the default output's
/// monitor (monitor mode). Played sound never runs through the canceller:
/// with the old sink in between, everything heard was distorted on MN's
/// UR22 (2026-11-16, 0.8.60).
pub const ECHO_REF: &str = "gc_aec.reference";
pub const MIC: &str = "gc_mic";
/// The stream mix: OBS records the source `gc_stream`; the sources play
/// into the sink `gc_stream_in`.
pub const STREAM: &str = "gc_stream";
pub const STREAM_IN: &str = "gc_stream_in";
/// The child's PipeWire client name; its own nodes are never moved.
pub const CLIENT: &str = "game-companion-sound";
const RNNOISE: &str = "/usr/lib/ladspa/librnnoise_ladspa.so";
const SC4M: &str = "/usr/lib/ladspa/sc4m_1916.so";

// ------------------------------------------------------------ settings ----

/// settings.json → "sound".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SoundSettings {
    /// The module runs (channels exist while Game Companion runs).
    pub on: bool,
    pub channels: BTreeMap<String, Channel>,
    /// -100 only game, 0 both full, 100 only chat.
    pub chatmix: i32,
    /// Fixed choices: program (binary or app name) → channel key.
    pub routes: BTreeMap<String, String>,
    /// Own presets, by name.
    pub presets: BTreeMap<String, [f64; 6]>,
    pub mic: Mic,
    pub stream: StreamMix,
    /// ~/.config/sonar was looked at once.
    pub took_sonar: bool,
}

impl Default for SoundSettings {
    fn default() -> Self {
        let channels = CHANNELS
            .iter()
            .map(|(k, _, _)| (k.to_string(), Channel { preset: if *k == "chat" { "Sprache" } else { "Flat" }.into(), ..Channel::default() }))
            .collect();
        Self { on: false, channels, chatmix: 0, routes: BTreeMap::new(), presets: BTreeMap::new(), mic: Mic::default(), stream: StreamMix::default(), took_sonar: false }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Channel {
    /// A preset's name, or "" for own values (`eq`).
    pub preset: String,
    /// Own values when `preset` is "": pre-gain and five bands, dB.
    pub eq: [f64; 6],
    /// Percent, 0 to 150.
    pub volume: u32,
}

impl Default for Channel {
    fn default() -> Self {
        Self { preset: "Flat".into(), eq: [0.0; 6], volume: 100 }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Mic {
    pub on: bool,
    /// The microphone's PipeWire node name (a hardware source).
    pub device: String,
    /// Which input carries it: "FL"/"FR" (stereo profiles) or "AUX0"/"AUX1"
    /// (Pro Audio).
    pub channel: String,
    /// Echo cancellation (speakers instead of a headset).
    pub echo: bool,
    /// rnnoise's voice gate: open above this voice likelihood (%).
    pub threshold: f64,
    /// How long it stays open after the last word (ms).
    pub grace: u32,
    /// Voice EQ (high-pass 80 Hz, presence) and, if installed, a gentle
    /// compressor.
    pub voice: bool,
}

impl Default for Mic {
    fn default() -> Self {
        Self { on: false, device: String::new(), channel: "FL".into(), echo: true, threshold: 85.0, grace: 300, voice: true }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct StreamMix {
    pub on: bool,
    /// game, chat, media, music, mic → in the stream mix and how loud.
    pub sources: BTreeMap<String, Send>,
}

impl Default for StreamMix {
    fn default() -> Self {
        let sources = ["game", "chat", "media", "music", "mic"]
            .iter()
            .map(|k| (k.to_string(), Send { on: *k != "music", volume: 100 }))
            .collect();
        Self { on: false, sources }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Send {
    pub on: bool,
    pub volume: u32,
}

impl Default for Send {
    fn default() -> Self {
        Self { on: true, volume: 100 }
    }
}

impl SoundSettings {
    /// A channel's EQ values (its preset's, or its own).
    pub fn eq_of(&self, key: &str) -> [f64; 6] {
        let Some(ch) = self.channels.get(key) else { return [0.0; 6] };
        if ch.preset.is_empty() {
            return ch.eq;
        }
        preset(&self.presets, &ch.preset).unwrap_or(ch.eq)
    }
}

/// A preset by name: own ones first, then the built-in ones.
pub fn preset(own: &BTreeMap<String, [f64; 6]>, name: &str) -> Option<[f64; 6]> {
    own.get(name).copied().or_else(|| PRESETS.iter().find(|(n, _)| *n == name).map(|(_, v)| *v))
}

pub fn db_to_linear(db: f64) -> f64 {
    10f64.powf(db / 20.0)
}

/// Clamps EQ values to ±12 dB (pre-gain to −12..+6).
pub fn clamp_eq(v: [f64; 6]) -> [f64; 6] {
    let mut out = v;
    out[0] = v[0].clamp(-12.0, 6.0);
    for x in out.iter_mut().skip(1) {
        *x = x.clamp(-12.0, 12.0);
    }
    out
}

/// ChatMix (−100..100) → game and chat volume factors in percent.
pub fn chatmix(mix: i32) -> (u32, u32) {
    let m = mix.clamp(-100, 100);
    if m <= 0 {
        (100, (100 + m) as u32)
    } else {
        ((100 - m) as u32, 100)
    }
}

/// A volume in percent as PipeWire's linear factor (cubic, like pulse).
pub fn volume_factor(percent: u32) -> f64 {
    let p = f64::from(percent.min(150)) / 100.0;
    p * p * p
}

// ------------------------------------------------------- the PW config ----

/// What is installed (LADSPA plugins for the mic chain).
#[derive(Debug, Clone, Default)]
pub struct Installed {
    pub rnnoise: Option<PathBuf>,
    pub compressor: Option<PathBuf>,
}

impl Installed {
    pub fn look() -> Self {
        let found = |p: &str| Some(PathBuf::from(p)).filter(|p| p.exists());
        Self { rnnoise: found(RNNOISE), compressor: found(SC4M) }
    }
}

/// A string for PipeWire's SPA-JSON (quoted, quotes and backslashes escaped).
fn sj(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' | '\\' => {
                out.push('\\');
                out.push(c);
            }
            c if c.is_control() => {}
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Pro Audio devices name their channels AUX0, AUX1, …
fn is_pro(device: &str) -> bool {
    device.contains(".pro-input") || device.contains(".pro-output")
}

/// The child's whole PipeWire config.
pub fn config(s: &SoundSettings, inst: &Installed) -> String {
    let mut c = String::new();
    c.push_str("# Made by Game Companion (sound module) for its own `pipewire -c` child.\n");
    c.push_str("# Not read by the system's PipeWire; changes here are overwritten.\n");
    let _ = writeln!(c, "context.properties = {{ log.level = 2 core.daemon = false core.name = {} }}", sj(CLIENT));
    c.push_str("context.spa-libs = {\n  audio.convert.* = audioconvert/libspa-audioconvert\n  support.* = support/libspa-support\n}\n");
    c.push_str("context.modules = [\n");
    c.push_str("  { name = libpipewire-module-rt args = { nice.level = -11 } flags = [ ifexists nofail ] }\n");
    c.push_str("  { name = libpipewire-module-protocol-native }\n");
    c.push_str("  { name = libpipewire-module-client-node }\n");
    c.push_str("  { name = libpipewire-module-adapter }\n");
    let echo = s.mic.on && s.mic.echo && !s.mic.device.is_empty();
    if echo {
        echo_cancel(&mut c, &s.mic);
    }
    for (key, node, desc) in CHANNELS {
        channel(&mut c, key, node, desc, &s.eq_of(key));
    }
    if s.mic.on && !s.mic.device.is_empty() {
        mic_chain(&mut c, &s.mic, echo, inst);
    }
    if s.stream.on {
        for (key, node, desc) in CHANNELS {
            let send = s.stream.sources.get(key).cloned().unwrap_or_default();
            sendto(&mut c, key, node, desc, true, &send);
        }
        if s.mic.on && !s.mic.device.is_empty() {
            let send = s.stream.sources.get("mic").cloned().unwrap_or_default();
            sendto(&mut c, "mic", MIC, "Game Companion Mikro", false, &send);
        }
    }
    if s.stream.on {
        stream_mix(&mut c);
    }
    c.push_str("]\n");
    c
}

/// Low priority: a virtual sink must never become the default output
/// (its sound goes to the default output: a loop).
const LOW: &str = "priority.session = 0 priority.driver = 0";

fn echo_cancel(c: &mut String, mic: &Mic) {
    let capture_pos = if is_pro(&mic.device) { "[ AUX0 AUX1 ]" } else { "[ FL FR ]" };
    let _ = writeln!(
        c,
        "  {{ name = libpipewire-module-echo-cancel\n    args = {{\n      library.name = aec/libspa-aec-webrtc\n      monitor.mode = true\n      audio.channels = 2\n      audio.position = [ FL FR ]\n      aec.args = {{ webrtc.extended_filter = true webrtc.delay_agnostic = true webrtc.high_pass_filter = true webrtc.noise_suppression = false webrtc.gain_control = false }}\n      capture.props = {{ node.name = \"gc_aec.capture\" target.object = {} audio.position = {capture_pos} node.passive = true }}\n      source.props = {{ node.name = \"gc_aec.source\" node.description = {} {LOW} }}\n      sink.props = {{ node.name = {} }}\n    }}\n  }}",
        sj(&mic.device),
        sj("Game Companion Mikro (roh)"),
        sj(ECHO_REF),
    );
}

fn channel(c: &mut String, key: &str, node: &str, desc: &str, eq: &[f64; 6]) {
    let eq = clamp_eq(*eq);
    let _ = writeln!(c, "  {{ name = libpipewire-module-filter-chain\n    args = {{\n      node.description = {}\n      media.name = {}\n      filter.graph = {{\n        nodes = [", sj(desc), sj(desc));
    let _ = writeln!(c, "          {{ type = builtin name = pre label = linear control = {{ \"Mult\" = {:.6} \"Add\" = 0.0 }} }}", db_to_linear(eq[0]));
    for (i, (name, label, freq, q)) in BANDS.iter().enumerate() {
        let _ = writeln!(c, "          {{ type = builtin name = {name} label = {label} control = {{ \"Freq\" = {freq:.1} \"Q\" = {q:.2} \"Gain\" = {:.2} }} }}", eq[i + 1]);
    }
    c.push_str("        ]\n        links = [\n");
    let names = ["pre", "b1", "b2", "b3", "b4", "b5"];
    for w in names.windows(2) {
        let _ = writeln!(c, "          {{ output = \"{}:Out\" input = \"{}:In\" }}", w[0], w[1]);
    }
    c.push_str("        ]\n      }\n      audio.channels = 2\n      audio.position = [ FL FR ]\n");
    let _ = writeln!(c, "      capture.props = {{ node.name = {} media.class = Audio/Sink {LOW} gc.channel = {} }}", sj(node), sj(key));
    let _ = writeln!(c, "      playback.props = {{ node.name = {} node.passive = true }}\n    }}\n  }}", sj(&format!("{node}.out")));
}

fn mic_chain(c: &mut String, mic: &Mic, echo: bool, inst: &Installed) {
    // Nodes in order: rnnoise (noise and voice gate), then the voice EQ
    // and the compressor. rnnoise first: it expects a plain voice.
    let mut nodes: Vec<String> = Vec::new();
    let mut chain: Vec<(&str, &str, &str)> = Vec::new(); // name, in port, out port
    if let Some(rn) = &inst.rnnoise {
        nodes.push(format!(
            "          {{ type = ladspa name = rn plugin = {} label = noise_suppressor_mono control = {{ \"VAD Threshold (%)\" = {:.1} \"VAD Grace Period (ms)\" = {} \"Retroactive VAD Grace (ms)\" = 0 }} }}",
            sj(&rn.display().to_string()),
            mic.threshold.clamp(0.0, 99.0),
            mic.grace.min(2000)
        ));
        chain.push(("rn", "Input", "Output"));
    }
    if mic.voice {
        nodes.push("          { type = builtin name = hp label = bq_highpass control = { \"Freq\" = 80.0 \"Q\" = 0.70 } }".into());
        nodes.push("          { type = builtin name = pres label = bq_peaking control = { \"Freq\" = 4000.0 \"Q\" = 1.00 \"Gain\" = 3.00 } }".into());
        chain.push(("hp", "In", "Out"));
        chain.push(("pres", "In", "Out"));
        if let Some(sc4) = &inst.compressor {
            nodes.push(format!(
                "          {{ type = ladspa name = comp plugin = {} label = sc4m control = {{ \"RMS/peak\" = 0.5 \"Attack time (ms)\" = 10.0 \"Release time (ms)\" = 150.0 \"Threshold level (dB)\" = -20.0 \"Ratio (1:n)\" = 3.0 \"Knee radius (dB)\" = 6.0 \"Makeup gain (dB)\" = 4.0 }} }}",
                sj(&sc4.display().to_string())
            ));
            chain.push(("comp", "Input", "Output"));
        }
    }
    if nodes.is_empty() {
        // Nothing to do on the voice: a plain copy keeps the node.
        nodes.push("          { type = builtin name = pass label = copy }".into());
        chain.push(("pass", "In", "Out"));
    }
    let _ = writeln!(c, "  {{ name = libpipewire-module-filter-chain\n    args = {{\n      node.description = {}\n      media.name = {}\n      filter.graph = {{\n        nodes = [", sj("Game Companion Mikro"), sj("Game Companion Mikro"));
    for n in &nodes {
        c.push_str(n);
        c.push('\n');
    }
    c.push_str("        ]\n        links = [\n");
    for w in chain.windows(2) {
        let _ = writeln!(c, "          {{ output = \"{}:{}\" input = \"{}:{}\" }}", w[0].0, w[0].2, w[1].0, w[1].1);
    }
    c.push_str("        ]\n      }\n      audio.channels = 1\n      audio.rate = 48000\n");
    let (source, pos) = if echo {
        ("gc_aec.source".to_string(), if mic.channel == "FR" || mic.channel == "AUX1" { "FR" } else { "FL" })
    } else {
        // Pro Audio devices call their inputs AUX0, AUX1.
        let pos = match (is_pro(&mic.device), mic.channel.as_str()) {
            (true, "FL") => "AUX0",
            (true, "FR") => "AUX1",
            (_, p) => p,
        };
        (mic.device.clone(), pos)
    };
    let pos = if ["FL", "FR", "AUX0", "AUX1", "MONO"].contains(&pos) { pos } else { "FL" };
    let _ = writeln!(c, "      capture.props = {{ node.name = \"gc_mic.in\" target.object = {} audio.position = [ {pos} ] stream.dont-remix = true node.passive = true }}", sj(&source));
    let _ = writeln!(c, "      playback.props = {{ node.name = {} node.description = {} media.class = Audio/Source audio.position = [ MONO ] {LOW} }}\n    }}\n  }}", sj(MIC), sj("Game Companion Mikro"));
}

/// The stream mix: a sink the sources play into and a source OBS records
/// (a client can't make a plain null sink, so a filter chain that copies).
fn stream_mix(c: &mut String) {
    let _ = writeln!(
        c,
        "  {{ name = libpipewire-module-filter-chain\n    args = {{\n      node.description = {}\n      media.name = {}\n      filter.graph = {{ nodes = [ {{ type = builtin name = copy label = copy }} ] }}\n      audio.channels = 2\n      audio.position = [ FL FR ]\n      capture.props = {{ node.name = {} node.description = {} media.class = Audio/Sink node.passive = true {LOW} }}\n      playback.props = {{ node.name = {} node.description = {} media.class = Audio/Source {LOW} }}\n    }}\n  }}",
        sj("Game Companion Stream"),
        sj("Game Companion Stream"),
        sj(STREAM_IN),
        sj("Game Companion Stream (Eingang)"),
        sj(STREAM),
        sj("Game Companion Stream"),
    );
}

/// One source into the stream mix: a loopback from a channel's monitor (or
/// the mic) to the stream mix, passive (idle until OBS records it).
fn sendto(c: &mut String, key: &str, node: &str, desc: &str, monitor: bool, send: &Send) {
    let factor = if send.on { volume_factor(send.volume) } else { 0.0 };
    let capture = if monitor { " stream.capture.sink = true" } else { "" };
    let (channels, pos) = if monitor { (2, "[ FL FR ]") } else { (1, "[ MONO ]") };
    let vols = if monitor { format!("{factor:.4} {factor:.4}") } else { format!("{factor:.4}") };
    let _ = writeln!(
        c,
        "  {{ name = libpipewire-module-loopback\n    args = {{\n      node.description = {}\n      audio.channels = {channels}\n      audio.position = {pos}\n      capture.props = {{ node.name = {} target.object = {}{capture} node.passive = true }}\n      playback.props = {{ node.name = {} target.object = {} node.passive = true channelmix.normalize = false channelVolumes = [ {vols} ] }}\n    }}\n  }}",
        sj(&format!("Stream: {desc}")),
        sj(&format!("gc_send_{key}")),
        sj(node),
        sj(&format!("gc_send_{key}.out")),
        sj(STREAM_IN),
    );
}

/// `pw-cli set-param` Props for a channel's EQ.
pub fn eq_params(eq: &[f64; 6]) -> String {
    let eq = clamp_eq(*eq);
    let mut p = format!("{{ params = [ \"pre:Mult\" {:.6}", db_to_linear(eq[0]));
    for (i, (name, _, _, _)) in BANDS.iter().enumerate() {
        let _ = write!(p, " \"{name}:Gain\" {:.2}", eq[i + 1]);
    }
    p.push_str(" ] }");
    p
}

/// `pw-cli set-param` Props for the voice gate.
pub fn gate_params(threshold: f64, grace: u32) -> String {
    format!("{{ params = [ \"rn:VAD Threshold (%)\" {:.1} \"rn:VAD Grace Period (ms)\" {:.1} ] }}", threshold.clamp(0.0, 99.0), f64::from(grace.min(2000)))
}

/// `pw-cli set-param` Props for a stream-mix source.
pub fn send_params(send: &Send, channels: usize) -> String {
    let f = if send.on { volume_factor(send.volume) } else { 0.0 };
    let vols = vec![format!("{f:.4}"); channels.max(1)].join(", ");
    format!("{{ channelVolumes = [ {vols} ] }}")
}

// ------------------------------------------------------------- streams ----

/// A playing stream, from `pactl -f json list sink-inputs`.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct App {
    pub index: u64,
    /// The sink's name it plays to now.
    pub sink: String,
    pub name: String,
    pub binary: String,
    pub pid: u32,
    pub node: String,
}

/// Streams from pactl's JSON (`sinks` maps the sink index to its name).
pub fn parse_apps(inputs: &str, sinks: &str) -> Vec<App> {
    let sinks: Vec<Value> = serde_json::from_str(sinks).unwrap_or_default();
    let names: BTreeMap<u64, String> = sinks
        .iter()
        .filter_map(|s| Some((s.get("index")?.as_u64()?, s.get("name")?.as_str()?.to_string())))
        .collect();
    let inputs: Vec<Value> = serde_json::from_str(inputs).unwrap_or_default();
    inputs
        .iter()
        .filter_map(|i| {
            let p = i.get("properties")?;
            let s = |k: &str| p.get(k).and_then(Value::as_str).unwrap_or("").to_string();
            let sink = i.get("sink").and_then(Value::as_u64).and_then(|n| names.get(&n).cloned()).unwrap_or_default();
            Some(App {
                index: i.get("index")?.as_u64()?,
                sink,
                name: s("application.name"),
                binary: s("application.process.binary"),
                pid: s("application.process.id").parse().unwrap_or(0),
                node: s("node.name"),
            })
        })
        .filter(|a| !is_own(a))
        .collect()
}

/// Our own chains' streams and EasyEffects' are never moved.
fn is_own(a: &App) -> bool {
    a.node.starts_with("sonar_") || a.node.starts_with("gc_") || a.name == CLIENT || a.node.starts_with("ee_") || a.binary == "easyeffects"
}

/// The running game, as far as sound needs it.
#[derive(Debug, Clone, Default)]
pub struct GameAudio {
    /// Lower-case process names.
    pub processes: Vec<String>,
    pub steam_appid: Option<u32>,
}

/// Whether a process (or one of its parents) is the running game's.
pub fn is_game(pid: u32, game: &GameAudio, proc_root: &Path) -> bool {
    if pid == 0 || (game.processes.is_empty() && game.steam_appid.is_none()) {
        return false;
    }
    let mut pid = pid;
    for _ in 0..8 {
        let dir = proc_root.join(pid.to_string());
        let comm = std::fs::read_to_string(dir.join("comm")).unwrap_or_default().trim().to_lowercase();
        if !comm.is_empty() && game.processes.iter().any(|p| p == &comm || (comm.len() == 15 && p.starts_with(&comm))) {
            return true;
        }
        if let Some(id) = game.steam_appid {
            let env = std::fs::read(dir.join("environ")).unwrap_or_default();
            let want = [format!("SteamAppId={id}"), format!("STEAM_COMPAT_APP_ID={id}")];
            if env.split(|&b| b == 0).any(|e| want.iter().any(|w| e == w.as_bytes())) {
                return true;
            }
        }
        // The parent, from /proc/<pid>/stat (the field after the name).
        let stat = std::fs::read_to_string(dir.join("stat")).unwrap_or_default();
        let parent = stat.rsplit_once(')').and_then(|(_, rest)| rest.split_whitespace().nth(1)).and_then(|p| p.parse::<u32>().ok());
        match parent {
            Some(p) if p > 1 => pid = p,
            _ => return false,
        }
    }
    false
}

/// Which channel a stream belongs on: a fixed choice first, then the running
/// game, then known programs; everything else on media (with speakers every
/// stream must pass the echo reference).
pub fn channel_for(app: &App, routes: &BTreeMap<String, String>, game: &GameAudio, proc_root: &Path) -> &'static str {
    let key = |k: &str| CHANNELS.iter().find(|(c, _, _)| *c == k).map(|(c, _, _)| *c);
    for who in [&app.binary, &app.name] {
        if who.is_empty() {
            continue;
        }
        if let Some(k) = routes.get(who.as_str()).and_then(|k| key(k)) {
            return k;
        }
    }
    if is_game(app.pid, game, proc_root) {
        return "game";
    }
    let b = app.binary.to_lowercase();
    let n = app.name.to_lowercase();
    if b.contains("legcord") || n.contains("legcord") || b == "discord" || n == "discord" || b.contains("vesktop") {
        return "chat";
    }
    // Game Companion's own radio (its mpv names itself so).
    if n.contains("game-companion-radio") {
        return "music";
    }
    if ["spotify", "strawberry", "elisa", "audacious", "rhythmbox", "lollypop", "amarok", "clementine", "deadbeef", "cmus", "mpd", "tidal-hifi", "feishin"].iter().any(|m| b == *m || n == *m) {
        return "music";
    }
    "media"
}

/// The moves that put every stream on its channel: (stream index, sink).
pub fn moves(apps: &[App], s: &SoundSettings, game: &GameAudio, proc_root: &Path) -> Vec<(u64, &'static str)> {
    apps.iter()
        .filter_map(|a| {
            let k = channel_for(a, &s.routes, game, proc_root);
            let sink = CHANNELS.iter().find(|(c, _, _)| *c == k).map(|(_, n, _)| *n)?;
            (a.sink != sink).then_some((a.index, sink))
        })
        .collect()
}

/// pw-dump's array (it may print more after it while things change).
fn first_json(dump: &str) -> Vec<Value> {
    serde_json::Deserializer::from_str(dump).into_iter::<Vec<Value>>().next().and_then(Result::ok).unwrap_or_default()
}

/// Node ids by name, from `pw-dump`.
pub fn node_ids(dump: &str) -> BTreeMap<String, u64> {
    let all = first_json(dump);
    all.iter()
        .filter(|o| o.get("type").and_then(Value::as_str) == Some("PipeWire:Interface:Node"))
        .filter_map(|o| Some((o.pointer("/info/props/node.name")?.as_str()?.to_string(), o.get("id")?.as_u64()?)))
        .collect()
}

/// Hardware microphones from `pw-dump`: (node name, description).
pub fn microphones(dump: &str) -> Vec<(String, String)> {
    let all = first_json(dump);
    all.iter()
        .filter(|o| o.get("type").and_then(Value::as_str) == Some("PipeWire:Interface:Node"))
        .filter_map(|o| {
            let p = o.pointer("/info/props")?;
            (p.get("media.class")?.as_str()? == "Audio/Source" && p.get("device.id").is_some()).then(|| {
                let name = p.get("node.name").and_then(Value::as_str).unwrap_or("").to_string();
                let desc = p.get("node.description").and_then(Value::as_str).unwrap_or(&name).to_string();
                (name, desc)
            })
        })
        .filter(|(n, _)| !n.is_empty())
        .collect()
}

/// Whether EasyEffects runs (it grabs every stream and adds its filters:
/// the cause of MN's dropouts).
pub fn easyeffects_running(proc_root: &Path) -> bool {
    std::fs::read_dir(proc_root)
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| std::fs::read_to_string(e.path().join("comm")).is_ok_and(|c| c.trim() == "easyeffects"))
}

// ------------------------------------------------------- Sonar light ----

/// Takes over Sonar light's choices once (~/.config/sonar): own presets,
/// each channel's preset, fixed routes. Aux becomes music.
pub fn take_sonar(dir: &Path, s: &mut SoundSettings) -> bool {
    if !dir.is_dir() {
        return false;
    }
    if let Ok(entries) = std::fs::read_dir(dir.join("presets")) {
        for e in entries.flatten() {
            let path = e.path();
            let Some(name) = path.file_stem().and_then(|n| n.to_str()).map(str::to_string) else { continue };
            if path.extension().and_then(|x| x.to_str()) != Some("preset") || PRESETS.iter().any(|(n, _)| *n == name) {
                continue;
            }
            let text = std::fs::read_to_string(&path).unwrap_or_default();
            let line = text.lines().find(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#')).unwrap_or("");
            let nums: Vec<f64> = line.split_whitespace().filter_map(|n| n.parse().ok()).collect();
            if let Ok(v) = <[f64; 6]>::try_from(nums) {
                s.presets.insert(name, clamp_eq(v));
            }
        }
    }
    let map = |k: &str| if k == "aux" { "music".to_string() } else { k.to_string() };
    for line in std::fs::read_to_string(dir.join("state")).unwrap_or_default().lines() {
        let mut w = line.split_whitespace();
        if let (Some(ch), Some(p)) = (w.next(), w.next()) {
            if let Some(c) = s.channels.get_mut(&map(ch)) {
                if preset(&s.presets, p).is_some() {
                    c.preset = p.to_string();
                }
            }
        }
    }
    for line in std::fs::read_to_string(dir.join("routes")).unwrap_or_default().lines() {
        let mut w = line.split_whitespace();
        if let (Some(prog), Some(ch)) = (w.next(), w.next()) {
            let ch = map(ch);
            if CHANNELS.iter().any(|(c, _, _)| *c == ch) {
                s.routes.insert(prog.to_string(), ch);
            }
        }
    }
    true
}

// ------------------------------------------------------------ runtime ----

/// Asks for the worker thread.
#[derive(Debug, Clone)]
pub enum Cmd {
    /// New settings: the child starts, restarts (config changed) or stops.
    Apply(Box<SoundSettings>),
    /// A channel's EQ, live (no restart).
    Eq(String, [f64; 6]),
    /// Channel volumes and ChatMix, live.
    Volumes(Box<SoundSettings>),
    /// The voice gate, live.
    Gate(f64, u32),
    /// A stream-mix source, live: key, send.
    Send(String, Send),
    /// The running game changed.
    Game(GameAudio),
    /// Move one stream now (index, channel key).
    Move(u64, String),
    /// Look at the streams again (and move them).
    Refresh,
    /// The mic's level meter on or off (only while something shows it).
    Meter(bool),
    /// From the meter's reader: level 0 to 100, voice passes the gate.
    Level(u8, bool),
    /// Record the mic 10 s and play it back.
    Hear,
    /// From the hear test: "recording", "playing" or "" (done).
    Hearing(String),
    /// Ask EasyEffects to quit (the person's click).
    CloseEasyEffects,
    /// The channels' level meters on or off (only while the MIXER shows).
    ChannelMeters(bool),
    /// From a channel meter's reader: channel index, level 0 to 100.
    ChannelLevel(u8, u8),
    /// Write a snapshot of the graph into the sound log ("Copy sound log").
    Report,
    /// From the snapshot's thread: done.
    Reported,
}

/// What the worker tells the Qt side.
#[derive(Debug, Clone)]
pub enum Event {
    /// The child runs (true) or not, and why not.
    Running(bool, String),
    /// The streams and the channel each is on.
    Apps(Vec<(App, String)>),
    /// Hardware microphones (node name, description).
    Mics(Vec<(String, String)>),
    /// EasyEffects runs.
    EasyEffects(bool),
    /// The mic after its chain: level 0 to 100, voice passes the gate.
    Level(u8, bool),
    /// The hear test: "recording", "playing" or "".
    Hearing(String),
    /// A snapshot is being written (true) or done (false).
    Reporting(bool),
    /// A channel's level (index in CHANNELS, 0 to 100).
    ChannelLevel(u8, u8),
}

/// Starts the worker thread (once, from the Qt thread; the children it
/// starts end with the app: PR_SET_PDEATHSIG follows this long-lived thread).
pub fn start(tell: impl Fn(Event) + std::marker::Send + 'static) -> Option<std::sync::mpsc::Sender<Cmd>> {
    let (tx, rx) = std::sync::mpsc::channel::<Cmd>();
    let watcher_tx = tx.clone();
    std::thread::Builder::new()
        .name("sound".into())
        .spawn(move || Worker::new(tell, watcher_tx).run(rx))
        .ok()?;
    Some(tx)
}

struct Worker<F: Fn(Event)> {
    tell: F,
    me: std::sync::mpsc::Sender<Cmd>,
    settings: SoundSettings,
    game: GameAudio,
    child: Option<std::process::Child>,
    watcher: Option<std::process::Child>,
    running_conf: String,
    ids: BTreeMap<String, u64>,
    proc_root: PathBuf,
    /// Streams put on a channel by hand (index → channel): left there.
    pinned: BTreeMap<u64, String>,
    /// The meter's `parec` (only while wanted and the chains run).
    meter: Option<std::process::Child>,
    meter_wanted: bool,
    hearing: bool,
    /// The channels' meters (`parec` of each channel's monitor).
    channel_meters: Vec<std::process::Child>,
    channel_meters_wanted: bool,
}

fn tool(name: &str) -> std::process::Command {
    let mut c = std::process::Command::new(name);
    c.stdin(std::process::Stdio::null()).stderr(std::process::Stdio::null());
    c
}

fn output(name: &str, args: &[&str]) -> Option<String> {
    let out = tool(name).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

fn quiet(name: &str, args: &[&str]) -> bool {
    tool(name).args(args).stdout(std::process::Stdio::null()).status().is_ok_and(|s| s.success())
}

/// The child's config file: in the runtime dir, never in ~/.config.
fn conf_path() -> Option<PathBuf> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).filter(|p| p.is_absolute())?;
    Some(dir.join("game-companion-sound.conf"))
}

fn ours(node: &str) -> bool {
    node.starts_with("sonar_") || node.starts_with("gc_")
}

impl<F: Fn(Event)> Worker<F> {
    fn new(tell: F, me: std::sync::mpsc::Sender<Cmd>) -> Self {
        Self { tell, me, settings: SoundSettings::default(), game: GameAudio::default(), child: None, watcher: None, running_conf: String::new(), ids: BTreeMap::new(), proc_root: PathBuf::from("/proc"), pinned: BTreeMap::new(), meter: None, meter_wanted: false, hearing: false, channel_meters: Vec::new(), channel_meters_wanted: false }
    }

    fn run(mut self, rx: std::sync::mpsc::Receiver<Cmd>) {
        while let Ok(cmd) = rx.recv() {
            // Rapid changes (a slider): only the newest of a kind counts.
            let mut cmds = vec![cmd];
            while let Ok(more) = rx.try_recv() {
                cmds.push(more);
            }
            let mut refresh = false;
            for (i, cmd) in cmds.iter().enumerate() {
                let later_same = cmds[i + 1..].iter().any(|c| std::mem::discriminant(c) == std::mem::discriminant(cmd) && same_target(c, cmd));
                if later_same {
                    continue;
                }
                match cmd {
                    Cmd::Apply(s) => self.apply(s),
                    Cmd::Eq(key, eq) => self.eq(key, eq),
                    Cmd::Volumes(s) => {
                        self.settings.channels = s.channels.clone();
                        self.settings.chatmix = s.chatmix;
                        self.volumes();
                    }
                    Cmd::Gate(t, g) => self.set_props(MIC, &gate_params(*t, *g)),
                    Cmd::Send(key, send) => {
                        let channels = if key == "mic" { 1 } else { 2 };
                        self.set_props(&format!("gc_send_{key}.out"), &send_params(send, channels));
                    }
                    Cmd::Game(g) => {
                        self.game = g.clone();
                        refresh = true;
                    }
                    Cmd::Move(index, key) => {
                        if let Some((_, node, _)) = CHANNELS.iter().find(|(k, _, _)| k == key) {
                            quiet("pactl", &["move-sink-input", &index.to_string(), node]);
                            self.pinned.insert(*index, key.clone());
                        }
                        refresh = true;
                    }
                    Cmd::Refresh => refresh = true,
                    Cmd::Meter(on) => {
                        self.meter_wanted = *on;
                        self.meter();
                    }
                    Cmd::Level(level, voice) => (self.tell)(Event::Level(*level, *voice)),
                    Cmd::Hear => self.hear(),
                    Cmd::Hearing(stage) => {
                        self.hearing = !stage.is_empty();
                        (self.tell)(Event::Hearing(stage.clone()));
                    }
                    Cmd::ChannelMeters(on) => {
                        self.channel_meters_wanted = *on;
                        self.channel_meters();
                    }
                    Cmd::ChannelLevel(i, level) => (self.tell)(Event::ChannelLevel(*i, *level)),
                    Cmd::Report => self.report(0),
                    Cmd::Reported => (self.tell)(Event::Reporting(false)),
                    Cmd::CloseEasyEffects => {
                        quiet("easyeffects", &["--quit"]);
                        std::thread::sleep(std::time::Duration::from_millis(600));
                        (self.tell)(Event::EasyEffects(easyeffects_running(&self.proc_root)));
                    }
                }
            }
            if refresh {
                self.streams(true);
            }
        }
        self.stop();
    }

    fn apply(&mut self, s: &SoundSettings) {
        self.settings = s.clone();
        (self.tell)(Event::EasyEffects(easyeffects_running(&self.proc_root)));
        if let Some(dump) = output("pw-dump", &[]) {
            (self.tell)(Event::Mics(microphones(&dump)));
        }
        if !s.on {
            self.stop();
            (self.tell)(Event::Running(false, String::new()));
            return;
        }
        let inst = Installed::look();
        let conf = config(s, &inst);
        let alive = self.child.as_mut().is_some_and(|c| matches!(c.try_wait(), Ok(None)));
        if alive && conf == self.running_conf {
            self.volumes();
            self.streams(true);
            return;
        }
        self.stop_child();
        crate::log::sound(&format!(
            "== start: mic {} (device {}, input {}, echo {}, gate {:.0} % / {} ms, voice {}), stream mix {}, chatmix {}, rnnoise {}, compressor {}",
            s.mic.on,
            if s.mic.device.is_empty() { "-" } else { &s.mic.device },
            s.mic.channel,
            s.mic.echo,
            s.mic.threshold,
            s.mic.grace,
            s.mic.voice,
            s.stream.on,
            s.chatmix,
            inst.rnnoise.is_some(),
            inst.compressor.is_some()
        ));
        for (key, _, _) in CHANNELS {
            let ch = s.channels.get(key).cloned().unwrap_or_default();
            crate::log::sound(&format!("channel {key}: preset {:?} eq {:?} volume {}", ch.preset, s.eq_of(key), ch.volume));
        }
        crate::log::sound(&format!("== config\n{conf}== end of config"));
        match self.spawn(&conf) {
            Ok(()) => {
                crate::log::sound("chains running");
                self.report(8);
                self.running_conf = conf;
                (self.tell)(Event::Running(true, String::new()));
                self.volumes();
                self.watch();
                self.streams(true);
                self.meter();
                self.channel_meters();
            }
            Err(why) => {
                crate::log::write("sound", &format!("chains did not start: {why}"));
                crate::log::sound(&format!("chains did not start: {why}"));
                (self.tell)(Event::Running(false, why));
            }
        }
    }

    fn spawn(&mut self, conf: &str) -> Result<(), String> {
        use std::os::unix::process::CommandExt;
        let path = conf_path().ok_or("no XDG_RUNTIME_DIR")?;
        std::fs::write(&path, conf).map_err(|e| e.to_string())?;
        let before_sink = output("pactl", &["get-default-sink"]).unwrap_or_default().trim().to_string();
        let before_source = output("pactl", &["get-default-source"]).unwrap_or_default().trim().to_string();
        let mut cmd = std::process::Command::new("pipewire");
        cmd.arg("-c").arg(&path).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::piped());
        // SAFETY: prctl only sets a flag on the child; no allocation.
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let mut child = cmd.spawn().map_err(|e| if e.kind() == std::io::ErrorKind::NotFound { "pipewire is not installed".to_string() } else { e.to_string() })?;
        crate::log::write("child", &format!("sound chains started (pid {})", child.id()));
        // PipeWire's own warnings and errors (xruns, failed links) into the
        // sound log, at most 400 lines per run.
        if let Some(err) = child.stderr.take() {
            std::thread::Builder::new()
                .name("sound-stderr".into())
                .spawn(move || {
                    use std::io::BufRead;
                    let mut n = 0;
                    for line in std::io::BufReader::new(err).lines().map_while(Result::ok) {
                        n += 1;
                        if n <= 400 {
                            crate::log::sound(&format!("pipewire: {line}"));
                        } else if n == 401 {
                            crate::log::sound("pipewire: (more lines left out)");
                        }
                    }
                    crate::log::sound("pipewire child ended");
                })
                .ok();
        }
        // Wait until the channels exist (or the child ends: a bad config).
        let started = std::time::Instant::now();
        loop {
            if let Ok(Some(status)) = child.try_wait() {
                return Err(format!("pipewire ended at once ({status})"));
            }
            if let Some(dump) = output("pw-dump", &[]) {
                self.ids = node_ids(&dump);
                if CHANNELS.iter().all(|(_, n, _)| self.ids.contains_key(*n)) {
                    break;
                }
            }
            if started.elapsed() > std::time::Duration::from_secs(5) {
                let _ = child.kill();
                let _ = child.wait();
                return Err("the channels did not appear".into());
            }
            std::thread::sleep(std::time::Duration::from_millis(150));
        }
        self.child = Some(child);
        // A virtual sink or source must never become the default (its sound
        // goes to the default: a loop). Put back what was there.
        let now_sink = output("pactl", &["get-default-sink"]).unwrap_or_default().trim().to_string();
        if ours(&now_sink) && !before_sink.is_empty() && !ours(&before_sink) {
            quiet("pactl", &["set-default-sink", &before_sink]);
        }
        let now_source = output("pactl", &["get-default-source"]).unwrap_or_default().trim().to_string();
        if ours(&now_source) && !before_source.is_empty() && !ours(&before_source) {
            quiet("pactl", &["set-default-source", &before_source]);
        }
        Ok(())
    }

    /// `pactl subscribe` while the chains run: a new stream → look again.
    fn watch(&mut self) {
        use std::io::BufRead;
        use std::os::unix::process::CommandExt;
        if self.watcher.as_mut().is_some_and(|c| matches!(c.try_wait(), Ok(None))) {
            return;
        }
        let mut cmd = tool("pactl");
        cmd.arg("subscribe").stdout(std::process::Stdio::piped());
        // SAFETY: as above.
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else { return };
        let Some(out) = child.stdout.take() else { return };
        let me = self.me.clone();
        std::thread::Builder::new()
            .name("sound-watch".into())
            .spawn(move || {
                for line in std::io::BufReader::new(out).lines().map_while(Result::ok) {
                    if line.contains("'new' on sink-input") && me.send(Cmd::Refresh).is_err() {
                        break;
                    }
                }
            })
            .ok();
        self.watcher = Some(child);
    }

    fn eq(&mut self, key: &str, eq: &[f64; 6]) {
        if let Some((_, node, _)) = CHANNELS.iter().find(|(k, _, _)| *k == key) {
            self.set_props(node, &eq_params(eq));
            // Read it back: what the filter now holds (MN, 2026-11-16: no
            // difference heard when switching presets).
            let held = self.ids.get(*node).and_then(|id| output("pw-cli", &["enum-params", &id.to_string(), "Props"])).map(|t| held_params(&t)).unwrap_or_else(|| "(not read)".into());
            crate::log::sound(&format!("eq {key}: asked {eq:?}; the filter holds {held}"));
        }
    }

    fn set_props(&mut self, node: &str, props: &str) {
        if self.child.is_none() {
            return;
        }
        let id = match self.ids.get(node) {
            Some(id) => *id,
            None => {
                self.ids = output("pw-dump", &[]).map(|d| node_ids(&d)).unwrap_or_default();
                match self.ids.get(node) {
                    Some(id) => *id,
                    None => return,
                }
            }
        };
        if !quiet("pw-cli", &["set-param", &id.to_string(), "Props", props]) {
            // The id may be stale (the child restarted): once more, fresh.
            self.ids = output("pw-dump", &[]).map(|d| node_ids(&d)).unwrap_or_default();
            if let Some(id) = self.ids.get(node) {
                quiet("pw-cli", &["set-param", &id.to_string(), "Props", props]);
            }
        }
    }

    fn volumes(&self) {
        if self.child.is_none() {
            return;
        }
        let (game, chat) = chatmix(self.settings.chatmix);
        let mut vols = Vec::new();
        for (key, node, _) in CHANNELS {
            let base = self.settings.channels.get(key).map_or(100, |c| c.volume.min(150));
            let v = match key {
                "game" => base * game / 100,
                "chat" => base * chat / 100,
                _ => base,
            };
            quiet("pactl", &["set-sink-volume", node, &format!("{v}%")]);
            vols.push(format!("{key} {v}%"));
        }
        crate::log::sound(&format!("volumes: {}", vols.join(", ")));
    }

    /// Lists the streams, moves each onto its channel (when `move_them`),
    /// tells the Qt side.
    fn streams(&mut self, move_them: bool) {
        let (Some(inputs), Some(sinks)) = (output("pactl", &["-f", "json", "list", "sink-inputs"]), output("pactl", &["-f", "json", "list", "sinks"])) else { return };
        let mut apps = parse_apps(&inputs, &sinks);
        self.pinned.retain(|i, _| apps.iter().any(|a| a.index == *i));
        if move_them && self.child.is_some() {
            let free: Vec<App> = apps.iter().filter(|a| !self.pinned.contains_key(&a.index)).cloned().collect();
            for (index, sink) in moves(&free, &self.settings, &self.game, &self.proc_root) {
                let ok = quiet("pactl", &["move-sink-input", &index.to_string(), sink]);
                let who = apps.iter().find(|a| a.index == index).map(|a| if a.binary.is_empty() { a.name.clone() } else { a.binary.clone() }).unwrap_or_default();
                crate::log::sound(&format!("stream {index} ({who}) → {sink}{}", if ok { "" } else { " FAILED" }));
                if ok {
                    if let Some(a) = apps.iter_mut().find(|a| a.index == index) {
                        a.sink = sink.to_string();
                    }
                }
            }
        }
        let listed = apps
            .into_iter()
            .map(|a| {
                let key = CHANNELS.iter().find(|(_, n, _)| *n == a.sink).map(|(k, _, _)| k.to_string()).unwrap_or_default();
                (a, key)
            })
            .collect();
        (self.tell)(Event::Apps(listed));
    }

    /// Runs or ends the level meter: `parec` of the finished mic
    /// (after its gate), 16 kHz mono, read in 100 ms pieces on its own
    /// thread; a change is told only when it shows.
    fn meter(&mut self) {
        use std::io::Read;
        use std::os::unix::process::CommandExt;
        let want = self.meter_wanted && self.child.is_some() && self.settings.mic.on;
        if !want {
            if let Some(mut m) = self.meter.take() {
                let _ = m.kill();
                let _ = m.wait();
                (self.tell)(Event::Level(0, false));
            }
            return;
        }
        if self.meter.as_mut().is_some_and(|c| matches!(c.try_wait(), Ok(None))) {
            return;
        }
        // parec (libpulse, beside pactl): plain samples on stdout, and a
        // latency of 100 ms keeps its wake-ups few.
        let mut cmd = tool("parec");
        cmd.args(["--raw", "--format=s16le", "--rate=16000", "--channels=1", "--latency-msec=100", &format!("--device={MIC}")]).stdout(std::process::Stdio::piped());
        // SAFETY: as above.
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else { return };
        let Some(mut out) = child.stdout.take() else { return };
        let me = self.me.clone();
        std::thread::Builder::new()
            .name("sound-meter".into())
            .spawn(move || {
                let mut buf = vec![0u8; 3200];
                let mut last = (255u8, false);
                while out.read_exact(&mut buf).is_ok() {
                    let (level, voice) = level_of(&buf);
                    if (level as i16 - last.0 as i16).abs() >= 3 || voice != last.1 {
                        last = (level, voice);
                        if me.send(Cmd::Level(level, voice)).is_err() {
                            break;
                        }
                    }
                }
            })
            .ok();
        self.meter = Some(child);
    }

    /// One `parec` per channel on its monitor (8 kHz mono, 100 ms blocks),
    /// only while the MIXER shows and the chains run; a level is told only
    /// when it changed.
    fn channel_meters(&mut self) {
        use std::io::Read;
        use std::os::unix::process::CommandExt;
        let want = self.channel_meters_wanted && self.child.is_some();
        let alive = !self.channel_meters.is_empty() && self.channel_meters.iter_mut().all(|c| matches!(c.try_wait(), Ok(None)));
        if want && alive {
            return;
        }
        for mut m in self.channel_meters.drain(..) {
            let _ = m.kill();
            let _ = m.wait();
        }
        if !want {
            for i in 0..CHANNELS.len() {
                (self.tell)(Event::ChannelLevel(i as u8, 0));
            }
            return;
        }
        for (i, (_, node, _)) in CHANNELS.iter().enumerate() {
            let mut cmd = tool("parec");
            cmd.args(["--raw", "--format=s16le", "--rate=8000", "--channels=1", "--latency-msec=100", &format!("--device={node}.monitor")]).stdout(std::process::Stdio::piped());
            // SAFETY: as above.
            unsafe {
                cmd.pre_exec(|| {
                    libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                    Ok(())
                });
            }
            let Ok(mut child) = cmd.spawn() else { continue };
            let Some(mut out) = child.stdout.take() else { continue };
            let me = self.me.clone();
            std::thread::Builder::new()
                .name("sound-chmeter".into())
                .spawn(move || {
                    let mut buf = vec![0u8; 1600];
                    let mut last = 255u8;
                    while out.read_exact(&mut buf).is_ok() {
                        let (level, _) = level_of(&buf);
                        if (level as i16 - last as i16).abs() >= 3 {
                            last = level;
                            if me.send(Cmd::ChannelLevel(i as u8, level)).is_err() {
                                break;
                            }
                        }
                    }
                })
                .ok();
            self.channel_meters.push(child);
        }
    }

    /// The hear test: 10 s of the finished mic into a file in the runtime
    /// dir, then played back (to the default output), then deleted.
    fn hear(&mut self) {
        use std::os::unix::process::CommandExt;
        if self.hearing || self.child.is_none() || !self.settings.mic.on {
            return;
        }
        let Some(dir) = conf_path().and_then(|p| p.parent().map(Path::to_path_buf)) else { return };
        let file = dir.join("game-companion-mic-test.wav");
        let me = self.me.clone();
        self.hearing = true;
        std::thread::Builder::new()
            .name("sound-hear".into())
            .spawn(move || {
                // This thread waits for both children: PR_SET_PDEATHSIG holds.
                let run = |mut cmd: std::process::Command, secs: u64| {
                    // SAFETY: as above.
                    unsafe {
                        cmd.pre_exec(|| {
                            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                            Ok(())
                        });
                    }
                    let Ok(mut c) = cmd.spawn() else { return };
                    let end = std::time::Instant::now() + std::time::Duration::from_secs(secs);
                    while matches!(c.try_wait(), Ok(None)) && std::time::Instant::now() < end {
                        std::thread::sleep(std::time::Duration::from_millis(100));
                    }
                    let _ = c.kill();
                    let _ = c.wait();
                };
                let _ = me.send(Cmd::Hearing("recording".into()));
                let mut rec = tool("pw-record");
                rec.args(["--target", MIC, "--rate", "48000", "--channels", "1"]).arg(&file).stdout(std::process::Stdio::null());
                run(rec, 10);
                let _ = me.send(Cmd::Hearing("playing".into()));
                let mut play = tool("pw-play");
                play.arg(&file).stdout(std::process::Stdio::null());
                run(play, 12);
                let _ = std::fs::remove_file(&file);
                let _ = me.send(Cmd::Hearing(String::new()));
            })
            .ok();
    }

    /// A snapshot of the graph into the sound log, on its own thread (pw-top
    /// takes a few seconds): versions, clock settings, cards and profiles,
    /// sinks, sources, the streams and where they play, our sinks' volumes,
    /// pw-top's rates, quantum and errors, the child's CPU.
    fn report(&mut self, delay: u64) {
        (self.tell)(Event::Reporting(true));
        let pid = self.child.as_ref().map(std::process::Child::id);
        let me = self.me.clone();
        let proc_root = self.proc_root.clone();
        std::thread::Builder::new()
            .name("sound-report".into())
            .spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(delay));
                crate::log::sound(&snapshot(pid, &proc_root));
                let _ = me.send(Cmd::Reported);
            })
            .ok();
    }

    fn stop_child(&mut self) {
        for mut m in self.channel_meters.drain(..) {
            let _ = m.kill();
            let _ = m.wait();
        }
        if let Some(mut m) = self.meter.take() {
            let _ = m.kill();
            let _ = m.wait();
        }
        if let Some(mut c) = self.child.take() {
            let _ = c.kill();
            let _ = c.wait();
            crate::log::write("child", "sound chains ended");
        }
        self.running_conf.clear();
        self.ids.clear();
    }

    fn stop(&mut self) {
        self.stop_child();
        if let Some(mut w) = self.watcher.take() {
            let _ = w.kill();
            let _ = w.wait();
        }
    }
}

/// 100 ms of 16-bit mono: the level 0 to 100 (−60 to 0 dBFS) and whether a
/// voice passes (the gate leaves near silence when closed).
/// CPU ticks (user + system) of a process.
fn ticks(proc_root: &Path, pid: u32) -> Option<u64> {
    let stat = std::fs::read_to_string(proc_root.join(pid.to_string()).join("stat")).ok()?;
    let rest = &stat[stat.rfind(')')? + 2..];
    let f: Vec<&str> = rest.split_whitespace().collect();
    Some(f.get(11)?.parse::<u64>().ok()? + f.get(12)?.parse::<u64>().ok()?)
}

/// The text of a snapshot (see `Worker::report`). Only names, formats,
/// volumes and timings: no media titles.
fn snapshot(child: Option<u32>, proc_root: &Path) -> String {
    let run = |name: &str, args: &[&str]| -> String {
        match tool(name).args(args).output() {
            Ok(o) => {
                let mut t = String::from_utf8_lossy(&o.stdout).into_owned();
                if !o.status.success() {
                    t.push_str(&format!("({name} failed: {})", String::from_utf8_lossy(&o.stderr).trim()));
                }
                t
            }
            Err(e) => format!("({name}: {e})"),
        }
    };
    let keep = |text: String, marks: &[&str]| -> String {
        text.lines().filter(|l| marks.iter().any(|m| l.trim_start().starts_with(m))).collect::<Vec<_>>().join("\n")
    };
    let mut o = String::from("== snapshot\n");
    o.push_str(&format!("-- versions\n{}", run("pipewire", &["--version"])));
    o.push_str(&format!("-- clock (pw-metadata settings)\n{}", run("pw-metadata", &["-n", "settings", "0"])));
    o.push_str(&format!("-- defaults\n{}\n", keep(run("pactl", &["info"]), &["Server Name", "Default Sample", "Default Channel", "Default Sink", "Default Source"])));
    o.push_str(&format!("-- cards\n{}\n", keep(run("pactl", &["list", "cards"]), &["Name:", "Active Profile:", "device.description"])));
    o.push_str(&format!("-- sinks\n{}", run("pactl", &["list", "sinks", "short"])));
    o.push_str(&format!("-- sink volumes\n{}\n", keep(run("pactl", &["list", "sinks"]), &["Name:", "Volume:", "Sample Specification:", "Mute:"])));
    o.push_str(&format!("-- sources\n{}", run("pactl", &["list", "sources", "short"])));
    o.push_str(&format!(
        "-- streams\n{}\n",
        keep(run("pactl", &["list", "sink-inputs"]), &["Sink Input #", "Sink:", "Sample Specification:", "Volume:", "Mute:", "application.process.binary", "node.name"])
    ));
    o.push_str(&format!("-- easyeffects running: {}\n", easyeffects_running(proc_root)));
    let before = child.and_then(|p| ticks(proc_root, p));
    let started = std::time::Instant::now();
    // pw-top: the last of four looks (each a second apart).
    let top = run("pw-top", &["-b", "-n", "4"]);
    let last: Vec<&str> = top.lines().collect();
    let from = last.iter().rposition(|l| l.trim_start().starts_with("S ") && l.contains("QUANT")).unwrap_or(0);
    o.push_str(&format!("-- pw-top (ERR = xruns since start)\n{}\n", last[from..].join("\n")));
    if let (Some(pid), Some(a)) = (child, before) {
        if let Some(b) = ticks(proc_root, pid) {
            // SAFETY: sysconf only reads a value.
            let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
            let secs = started.elapsed().as_secs_f64().max(0.1);
            o.push_str(&format!("-- sound child (pid {pid}) CPU: {:.1} % of one core\n", (b - a) as f64 / hz / secs * 100.0));
        }
    }
    o.push_str("== end of snapshot");
    o
}

/// The filter's values from `pw-cli enum-params <id> Props`: each
/// `String "name"` followed by its `Float`, as "name=value" pairs.
pub fn held_params(text: &str) -> String {
    let mut out = Vec::new();
    let mut name: Option<String> = None;
    for line in text.lines().map(str::trim) {
        if let Some(rest) = line.strip_prefix("String ") {
            let n = rest.trim_matches('"');
            name = (n.starts_with("pre:") || n.starts_with('b') && n.contains(":Gain")).then(|| n.to_string());
        } else if let (Some(n), Some(v)) = (name.take(), line.strip_prefix("Float ")) {
            let v: f64 = v.trim().parse().unwrap_or(f64::NAN);
            out.push(format!("{n}={v:.2}"));
        }
    }
    if out.is_empty() {
        "(nothing)".into()
    } else {
        out.join(" ")
    }
}

pub fn level_of(pcm: &[u8]) -> (u8, bool) {
    let n = pcm.len() / 2;
    if n == 0 {
        return (0, false);
    }
    let sum: f64 = (0..n).map(|i| f64::from(i16::from_le_bytes([pcm[2 * i], pcm[2 * i + 1]])) / 32768.0).map(|v| v * v).sum();
    let rms = (sum / n as f64).sqrt();
    let db = if rms > 0.0 { 20.0 * rms.log10() } else { -120.0 };
    let level = ((db + 60.0) / 60.0 * 100.0).clamp(0.0, 100.0).round() as u8;
    (level, db > -50.0)
}

/// Whether two asks change the same thing (then only the newer counts).
fn same_target(a: &Cmd, b: &Cmd) -> bool {
    match (a, b) {
        (Cmd::Eq(x, _), Cmd::Eq(y, _)) | (Cmd::Send(x, _), Cmd::Send(y, _)) => x == y,
        (Cmd::Move(x, _), Cmd::Move(y, _)) => x == y,
        (Cmd::ChannelLevel(x, _), Cmd::ChannelLevel(y, _)) => x == y,
        (Cmd::ChannelMeters(_), Cmd::ChannelMeters(_)) => true,
        (Cmd::Apply(_), Cmd::Apply(_)) | (Cmd::Level(..), Cmd::Level(..)) | (Cmd::Meter(_), Cmd::Meter(_)) | (Cmd::Volumes(_), Cmd::Volumes(_)) | (Cmd::Gate(..), Cmd::Gate(..)) | (Cmd::Game(_), Cmd::Game(_)) => true,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(index: u64, name: &str, binary: &str, pid: u32, sink: &str) -> App {
        App { index, sink: sink.into(), name: name.into(), binary: binary.into(), pid, node: String::new() }
    }

    #[test]
    fn filter_values_read_back() {
        let t = "Object: size 96\n  Prop: key params\n    Struct: size 72\n      String \"pre:Mult\"\n      Float 0.562341\n      String \"b1:Gain\"\n      Float 6.000000\n      String \"b1:Freq\"\n      Float 80.0\n";
        assert_eq!(held_params(t), "pre:Mult=0.56 b1:Gain=6.00");
        assert_eq!(held_params(""), "(nothing)");
    }

    #[test]
    fn radio_goes_on_music() {
        let a = App { index: 1, sink: String::new(), name: "game-companion-radio".into(), binary: "mpv".into(), pid: 0, node: String::new() };
        assert_eq!(channel_for(&a, &BTreeMap::new(), &GameAudio::default(), Path::new("/nonexistent")), "music");
    }

    #[test]
    fn level_from_pcm() {
        assert_eq!(level_of(&[0u8; 3200]), (0, false));
        let loud: Vec<u8> = (0..1600).flat_map(|i| if i % 2 == 0 { 16384i16 } else { -16384 }.to_le_bytes()).collect();
        let (level, voice) = level_of(&loud);
        assert!(voice && (88..=92).contains(&level), "{level}");
        let faint: Vec<u8> = (0..1600).flat_map(|i| if i % 2 == 0 { 50i16 } else { -50 }.to_le_bytes()).collect();
        assert!(!level_of(&faint).1);
    }

    #[test]
    fn pro_audio_inputs_are_aux() {
        let s = SoundSettings {
            on: true,
            mic: Mic { on: true, echo: false, device: "alsa_input.usb-Yamaha_Steinberg_UR22mkII-00.pro-input-0".into(), channel: "FR".into(), ..Mic::default() },
            ..SoundSettings::default()
        };
        assert!(config(&s, &Installed::default()).contains("audio.position = [ AUX1 ] stream.dont-remix"));
    }

    #[test]
    fn chatmix_like_sonar() {
        assert_eq!(chatmix(0), (100, 100));
        assert_eq!(chatmix(-100), (100, 0));
        assert_eq!(chatmix(40), (60, 100));
        assert_eq!(chatmix(500), (0, 100));
    }

    #[test]
    fn config_has_channels_and_no_mic_by_default() {
        let c = config(&SoundSettings::default(), &Installed::default());
        for (_, node, _) in CHANNELS {
            assert!(c.contains(&format!("node.name = \"{node}\"")), "{node}");
        }
        assert!(!c.contains(MIC));
        assert!(!c.contains("echo-cancel"));
        assert!(c.contains("name = b5 label = bq_highshelf control = { \"Freq\" = 9000.0 \"Q\" = 0.70 \"Gain\" = 0.00 }"));
        // Chat starts with Sonar's "Sprache".
        assert!(c.contains("name = b1 label = bq_lowshelf control = { \"Freq\" = 80.0 \"Q\" = 0.70 \"Gain\" = -4.00 }"));
    }

    #[test]
    fn config_with_mic_and_stream() {
        let mut s = SoundSettings::default();
        s.mic.on = true;
        s.mic.device = "alsa_input.usb-Yamaha_Corporation_Steinberg_UR22mkII-00.pro-input-0".into();
        s.mic.channel = "AUX0".into();
        s.stream.on = true;
        let inst = Installed { rnnoise: Some(PathBuf::from("/x/rn.so")), compressor: None };
        let c = config(&s, &inst);
        assert!(c.contains("libpipewire-module-echo-cancel"));
        assert!(c.contains("audio.position = [ AUX0 AUX1 ]"));
        // The canceller only listens (monitor mode): no channel plays
        // through it.
        assert!(c.contains("monitor.mode = true"));
        assert!(c.contains("playback.props = { node.name = \"sonar_game.out\" node.passive = true }"));
        assert!(!c.contains("target.object = \"gc_aec.reference\""));
        assert!(c.contains("\"VAD Threshold (%)\" = 85.0"));
        assert!(c.contains("{ output = \"rn:Output\" input = \"hp:In\" }"));
        assert!(c.contains("node.name = \"gc_mic\""));
        // Music is not in the stream by default.
        assert!(c.contains("node.name = \"gc_send_music.out\" target.object = \"gc_stream_in\" node.passive = true channelmix.normalize = false channelVolumes = [ 0.0000 0.0000 ]"));
        assert!(c.contains("node.name = \"gc_stream\" node.description = \"Game Companion Stream\" media.class = Audio/Source"));
        // Braces balance (a broken file would stop the child).
        assert_eq!(c.matches('{').count(), c.matches('}').count());
        assert_eq!(c.matches('[').count(), c.matches(']').count());
    }

    #[test]
    fn spa_strings_are_escaped() {
        assert_eq!(sj("a\"b\\c\n"), "\"a\\\"b\\\\c\"");
    }

    #[test]
    fn params_for_live_changes() {
        let p = eq_params(&[-5.0, 6.0, 2.0, 0.0, 0.0, 20.0]);
        assert!(p.starts_with("{ params = [ \"pre:Mult\" 0.562341"));
        assert!(p.contains("\"b5:Gain\" 12.00"));
        assert_eq!(send_params(&Send { on: false, volume: 100 }, 2), "{ channelVolumes = [ 0.0000, 0.0000 ] }");
        assert!(gate_params(150.0, 300).contains("99.0"));
    }

    #[test]
    fn streams_go_to_their_channels() {
        let tmp = std::env::temp_dir().join(format!("gc-sound-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        // 500: wine's game process; 501: a child of it with a cut name; 600: steam
        for (pid, comm, env, ppid) in [(500, "PathOfExileStea", "SteamAppId=2694490\0", 1), (501, "wine64-preloade", "", 500), (600, "steam", "", 1)] {
            let d = tmp.join(pid.to_string());
            std::fs::create_dir_all(&d).unwrap();
            std::fs::write(d.join("comm"), format!("{comm}\n")).unwrap();
            std::fs::write(d.join("environ"), env).unwrap();
            std::fs::write(d.join("stat"), format!("{pid} ({comm}) S {ppid} 0 0")).unwrap();
        }
        let game = GameAudio { processes: vec!["pathofexilesteam.exe".into()], steam_appid: Some(2_694_490) };
        let mut s = SoundSettings::default();
        s.routes.insert("mpv".into(), "music".into());
        let apps = vec![
            app(1, "wine", "wine64-preloader", 501, "sonar_media"),
            app(2, "Legcord", "electron", 700, "alsa_output.x"),
            app(3, "Brave", "brave", 800, "sonar_media"),
            app(4, "mpv", "mpv", 900, "alsa_output.x"),
            app(5, "Steam", "steam", 600, "alsa_output.x"),
        ];
        assert!(is_game(501, &game, &tmp));
        assert!(!is_game(600, &game, &tmp));
        let m = moves(&apps, &s, &game, &tmp);
        assert_eq!(m, vec![(1, "sonar_game"), (2, "sonar_chat"), (4, "sonar_music"), (5, "sonar_media")]);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn pactl_json_is_read_and_own_streams_left_alone() {
        let sinks = r#"[{"index":40,"name":"sonar_media"},{"index":41,"name":"alsa_output.usb"}]"#;
        let inputs = r#"[
          {"index":7,"sink":41,"properties":{"application.name":"Brave","application.process.binary":"brave","application.process.id":"1234","node.name":"Brave"}},
          {"index":8,"sink":41,"properties":{"application.name":"game-companion-sound","node.name":"sonar_game.out"}},
          {"index":9,"sink":40,"properties":{"application.name":"Easy Effects","node.name":"ee_soe_output_level","application.process.binary":"easyeffects"}}
        ]"#;
        let apps = parse_apps(inputs, sinks);
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].sink, "alsa_output.usb");
        assert_eq!(apps[0].pid, 1234);
    }

    #[test]
    fn dump_gives_ids_and_mics() {
        let dump = r#"[
          {"id":31,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"sonar_game","media.class":"Audio/Sink"}}},
          {"id":65,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_input.usb-UR22.analog-stereo","node.description":"UR22mkII","media.class":"Audio/Source","device.id":50}}},
          {"id":70,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"gc_mic","media.class":"Audio/Source"}}},
          {"id":2,"type":"PipeWire:Interface:Client","info":{}}
        ]"#;
        assert_eq!(node_ids(dump).get("sonar_game"), Some(&31));
        assert_eq!(microphones(dump), vec![("alsa_input.usb-UR22.analog-stereo".to_string(), "UR22mkII".to_string())]);
    }

    #[test]
    fn sonar_light_is_taken_over() {
        let tmp = std::env::temp_dir().join(format!("gc-sonar-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join("presets")).unwrap();
        std::fs::write(tmp.join("presets/Mein.preset"), "# mine\n-2 3 0 0 1 99\n").unwrap();
        std::fs::write(tmp.join("presets/Flat.preset"), "1 1 1 1 1 1\n").unwrap();
        std::fs::write(tmp.join("state"), "game Mein\naux Film\nchat Nope\n").unwrap();
        std::fs::write(tmp.join("routes"), "acs.exe game\nspotify aux\nfoo bar\n").unwrap();
        let mut s = SoundSettings::default();
        assert!(take_sonar(&tmp, &mut s));
        assert_eq!(s.presets.get("Mein"), Some(&[-2.0, 3.0, 0.0, 0.0, 1.0, 12.0]));
        assert!(!s.presets.contains_key("Flat"));
        assert_eq!(s.channels["game"].preset, "Mein");
        assert_eq!(s.channels["music"].preset, "Film");
        assert_eq!(s.channels["chat"].preset, "Sprache");
        assert_eq!(s.routes.get("spotify").map(String::as_str), Some("music"));
        assert!(!s.routes.contains_key("foo"));
        let _ = std::fs::remove_dir_all(&tmp);
    }
}

/// Writes a full config (mic on `GC_SOUND_MIC`, stream mix on) to
/// `GC_SOUND_CONF`, to run it by hand: `pipewire -c <file>` against a real
/// (or headless) PipeWire.
#[cfg(test)]
#[test]
#[ignore]
fn write_config_for_bench() {
    let mut s = SoundSettings::default();
    s.mic.on = true;
    s.mic.device = std::env::var("GC_SOUND_MIC").unwrap_or_else(|_| "fake_mic".into());
    s.stream.on = true;
    let path = std::env::var("GC_SOUND_CONF").expect("GC_SOUND_CONF");
    std::fs::write(path, config(&s, &Installed::look())).unwrap();
}
