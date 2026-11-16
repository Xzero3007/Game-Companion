//! The sound module for QML (the `Sound` singleton): its settings, the
//! streams and their channels, and the live changes (`sound`).

use std::pin::Pin;
use std::sync::mpsc::Sender;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::settings;
use crate::sound::{self, Cmd, Event, SoundSettings};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        /// `{"running","why","easyEffects","mics":[{"name","desc"}],
        /// "rnnoise","compressor","presets":[{"name","values","own"}]}`.
        #[qproperty(QString, state)]
        /// `[{"index","name","binary","channel","fixed"}]`.
        #[qproperty(QString, apps)]
        /// The settings (`SoundSettings`) as JSON.
        #[qproperty(QString, prefs)]
        /// The finished mic's level, 0 to 100 (only while the meter runs).
        #[qproperty(i32, level)]
        /// A voice passes the gate (only while the meter runs).
        #[qproperty(bool, talking)]
        /// The hear test: "recording", "playing" or "".
        #[qproperty(QString, hearing)]
        type Sound = super::SoundRust;

        /// Starts the worker (once, from Main).
        #[qinvokable]
        fn begin(self: Pin<&mut Sound>);

        /// Module on or off.
        #[qinvokable]
        fn set_on(self: Pin<&mut Sound>, on: bool);

        /// A channel's preset ("" = own values), own EQ values (JSON array
        /// of six dB values, or "") and volume (−1 = unchanged).
        #[qinvokable]
        fn set_channel(self: Pin<&mut Sound>, key: &QString, preset: &QString, eq: &QString, volume: i32);

        #[qinvokable]
        fn set_chatmix(self: Pin<&mut Sound>, mix: i32);

        /// The mic's settings as JSON (fields of `Mic`; missing ones kept).
        #[qinvokable]
        fn set_mic(self: Pin<&mut Sound>, json: &QString);

        /// The stream mix: on, and sources as JSON
        /// (`{"music":{"on":true,"volume":80}}`; missing ones kept).
        #[qinvokable]
        fn set_stream(self: Pin<&mut Sound>, on: bool, sources: &QString);

        /// Puts a running stream on a channel now; `always` keeps the choice
        /// for its program.
        #[qinvokable]
        fn move_app(self: Pin<&mut Sound>, index: i32, key: &QString, always: bool);

        /// Forgets a program's fixed channel.
        #[qinvokable]
        fn forget_route(self: Pin<&mut Sound>, program: &QString);

        /// Keeps own EQ values as a preset (JSON array of six dB values).
        #[qinvokable]
        fn save_preset(self: Pin<&mut Sound>, name: &QString, values: &QString);

        #[qinvokable]
        fn delete_preset(self: Pin<&mut Sound>, name: &QString);

        /// The running game (Games.running): its streams go on Spiel.
        #[qinvokable]
        fn set_game(self: Pin<&mut Sound>, id: &QString);

        /// Looks at the streams again.
        #[qinvokable]
        fn refresh(self: Pin<&mut Sound>);

        /// The mic's meter: on only while the MIC tab or the quick row shows.
        #[qinvokable]
        fn set_meter(self: Pin<&mut Sound>, on: bool);

        /// Records the mic 10 s and plays it back.
        #[qinvokable]
        fn hear(self: Pin<&mut Sound>);

        /// Asks EasyEffects to quit.
        #[qinvokable]
        fn close_easy_effects(self: Pin<&mut Sound>);
    }

    impl cxx_qt::Threading for Sound {}
}

pub struct SoundRust {
    state: QString,
    apps: QString,
    prefs: QString,
    level: i32,
    talking: bool,
    hearing: QString,
    tx: Option<Sender<Cmd>>,
    running: bool,
    why: String,
    easy: bool,
    mics: Vec<(String, String)>,
    meter_on: bool,
}

impl Default for SoundRust {
    fn default() -> Self {
        let s = settings::read(|s| s.sound.clone());
        // GC_DEMO=sound: running, with made-up programs and inputs.
        if demo() {
            return Self::demo(s);
        }
        let mut me = Self { state: QString::default(), apps: QString::from("[]"), prefs: QString::from(&json_of(&s)), level: 0, talking: false, hearing: QString::default(), tx: None, running: false, why: String::new(), easy: false, mics: Vec::new(), meter_on: false };
        me.state = QString::from(&me.state_json(&s));
        me
    }
}

fn demo() -> bool {
    std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p.starts_with("sound")))
}

impl SoundRust {
    fn demo(mut s: SoundSettings) -> Self {
        s.on = true;
        s.mic.on = true;
        s.mic.device = "alsa_input.usb-Yamaha_Steinberg_UR22mkII-00.pro-input-0".into();
        s.chatmix = 15;
        if let Some(c) = s.channels.get_mut("game") {
            c.preset = "Racing".into();
            c.volume = 72;
        }
        if let Some(c) = s.channels.get_mut("chat") {
            c.preset = "Sprache".into();
            c.volume = 85;
        }
        if let Some(c) = s.channels.get_mut("media") {
            c.volume = 50;
        }
        if let Some(c) = s.channels.get_mut("music") {
            c.preset = "Bass-Boost".into();
            c.volume = 40;
        }
        s.routes.insert("brave".into(), "music".into());
        let apps = json!([
            { "index": 41, "name": "Path of Exile 2", "binary": "PathOfExileSteam.exe", "program": "PathOfExileSteam.exe", "channel": "game", "fixed": false },
            { "index": 42, "name": "Legcord", "binary": "legcord", "program": "legcord", "channel": "chat", "fixed": false },
            { "index": 43, "name": "Game Companion radio", "binary": "mpv", "program": "mpv", "channel": "music", "fixed": false },
            { "index": 44, "name": "Brave · YouTube", "binary": "brave", "program": "brave", "channel": "music", "fixed": true },
            { "index": 45, "name": "System sounds", "binary": "", "program": "System sounds", "channel": "media", "fixed": false }
        ]);
        let mut me = Self {
            state: QString::default(),
            apps: QString::from(&apps.to_string()),
            prefs: QString::from(&json_of(&s)),
            level: 78,
            talking: true,
            hearing: QString::default(),
            tx: None,
            running: true,
            why: String::new(),
            easy: std::env::var("GC_DEMO").is_ok_and(|d| d.contains("soundee")),
            mics: vec![
                ("alsa_input.usb-Yamaha_Steinberg_UR22mkII-00.pro-input-0".into(), "UR22mkII Pro Audio".into()),
                ("alsa_input.pci-0000_0c_00.4.analog-stereo".into(), "Starship/Matisse HD Audio Analog Stereo".into()),
            ],
            meter_on: false,
        };
        me.state = QString::from(&me.state_json(&s));
        me
    }
}

fn json_of(s: &SoundSettings) -> String {
    serde_json::to_string(s).unwrap_or_else(|_| "{}".into())
}

fn eq_from(text: &str) -> Option<[f64; 6]> {
    let v: Vec<f64> = serde_json::from_str(text).ok()?;
    <[f64; 6]>::try_from(v).ok().map(sound::clamp_eq)
}

impl SoundRust {
    fn state_json(&self, s: &SoundSettings) -> String {
        let inst = sound::Installed::look();
        let mut presets: Vec<Value> = sound::PRESETS.iter().map(|(n, v)| json!({ "name": n, "values": v, "own": false })).collect();
        presets.extend(s.presets.iter().map(|(n, v)| json!({ "name": n, "values": v, "own": true })));
        json!({
            "running": self.running,
            "why": self.why,
            "easyEffects": self.easy,
            "mics": self.mics.iter().map(|(n, d)| json!({ "name": n, "desc": d })).collect::<Vec<_>>(),
            "rnnoise": inst.rnnoise.is_some(),
            "compressor": inst.compressor.is_some(),
            "presets": presets,
        })
        .to_string()
    }
}

impl qobject::Sound {
    fn send(&self, cmd: Cmd) {
        if let Some(tx) = &self.rust().tx {
            let _ = tx.send(cmd);
        }
    }

    /// Changes the settings, saves them and shows them.
    fn change(mut self: Pin<&mut Self>, f: impl FnOnce(&mut SoundSettings)) -> SoundSettings {
        let s = settings::change(|all| {
            f(&mut all.sound);
            all.sound.clone()
        });
        self.as_mut().set_prefs(QString::from(&json_of(&s)));
        s
    }

    fn show_state(mut self: Pin<&mut Self>) {
        let s = settings::read(|s| s.sound.clone());
        let json = self.rust().state_json(&s);
        if self.rust().state.to_string() != json {
            self.as_mut().set_state(QString::from(&json));
        }
    }

    fn begin(mut self: Pin<&mut Self>) {
        if self.rust().tx.is_some() || demo() {
            return;
        }
        // Sonar light's choices, once.
        if !settings::read(|s| s.sound.took_sonar) {
            let dir = std::env::var_os("XDG_CONFIG_HOME")
                .map(std::path::PathBuf::from)
                .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))
                .map(|c| c.join("sonar"));
            self.as_mut().change(|s| {
                if let Some(dir) = dir {
                    if sound::take_sonar(&dir, s) {
                        crate::log::write("sound", "Sonar light's presets and routes taken over");
                    }
                }
                s.took_sonar = true;
            });
        }
        let thread = self.qt_thread();
        let tx = sound::start(move |e| {
            let _ = thread.queue(move |obj: Pin<&mut qobject::Sound>| obj.take(e));
        });
        self.as_mut().rust_mut().tx = tx;
        let s = settings::read(|s| s.sound.clone());
        self.send(Cmd::Apply(Box::new(s)));
        if self.rust().meter_on {
            self.send(Cmd::Meter(true));
        }
    }

    fn take(mut self: Pin<&mut Self>, e: Event) {
        match e {
            Event::Running(on, why) => {
                self.as_mut().rust_mut().running = on;
                self.as_mut().rust_mut().why = why;
            }
            Event::EasyEffects(on) => self.as_mut().rust_mut().easy = on,
            Event::Level(level, voice) => {
                if self.rust().level != i32::from(level) {
                    self.as_mut().set_level(i32::from(level));
                }
                if self.rust().talking != voice {
                    self.as_mut().set_talking(voice);
                }
                return;
            }
            Event::Hearing(stage) => {
                self.as_mut().set_hearing(QString::from(&stage));
                return;
            }
            Event::Mics(m) => self.as_mut().rust_mut().mics = m,
            Event::Apps(list) => {
                let routes = settings::read(|s| s.sound.routes.clone());
                let apps: Vec<Value> = list
                    .iter()
                    .map(|(a, key)| {
                        let program = if a.binary.is_empty() { &a.name } else { &a.binary };
                        json!({ "index": a.index, "name": a.name, "binary": a.binary, "program": program, "channel": key, "fixed": routes.contains_key(program.as_str()) })
                    })
                    .collect();
                let text = Value::Array(apps).to_string();
                if self.rust().apps.to_string() != text {
                    self.as_mut().set_apps(QString::from(&text));
                }
            }
        }
        self.show_state();
    }

    fn set_on(mut self: Pin<&mut Self>, on: bool) {
        crate::log::write("sound", if on { "module on" } else { "module off" });
        let s = self.as_mut().change(|s| s.on = on);
        self.send(Cmd::Apply(Box::new(s)));
    }

    fn set_channel(mut self: Pin<&mut Self>, key: &QString, preset: &QString, eq: &QString, volume: i32) {
        let key = key.to_string();
        if !sound::CHANNELS.iter().any(|(k, _, _)| *k == key) {
            return;
        }
        let preset = preset.to_string();
        let eq = eq_from(&eq.to_string());
        let mut eq_changed = false;
        let mut vol_changed = false;
        let s = self.as_mut().change(|s| {
            let own = s.presets.clone();
            if let Some(ch) = s.channels.get_mut(&key) {
                if let Some(values) = eq {
                    ch.eq = values;
                    ch.preset = String::new();
                    eq_changed = true;
                } else if !preset.is_empty() && sound::preset(&own, &preset).is_some() && ch.preset != preset {
                    ch.preset = preset.clone();
                    eq_changed = true;
                }
                if volume >= 0 {
                    ch.volume = (volume as u32).min(150);
                    vol_changed = true;
                }
            }
        });
        if eq_changed {
            self.send(Cmd::Eq(key.clone(), s.eq_of(&key)));
        }
        if vol_changed {
            self.send(Cmd::Volumes(Box::new(s)));
        }
    }

    fn set_chatmix(mut self: Pin<&mut Self>, mix: i32) {
        let s = self.as_mut().change(|s| s.chatmix = mix.clamp(-100, 100));
        self.send(Cmd::Volumes(Box::new(s)));
    }

    fn set_mic(mut self: Pin<&mut Self>, json: &QString) {
        let Ok(Value::Object(new)) = serde_json::from_str::<Value>(&json.to_string()) else { return };
        let before = settings::read(|s| s.sound.mic.clone());
        let mut merged = serde_json::to_value(&before).unwrap_or(Value::Null);
        if let Value::Object(m) = &mut merged {
            m.extend(new);
        }
        let Ok(mic) = serde_json::from_value::<sound::Mic>(merged) else { return };
        // Only the gate changed: live, no restart.
        let gate_only = sound::Mic { threshold: before.threshold, grace: before.grace, ..mic.clone() } == before;
        let s = self.as_mut().change(|s| s.mic = mic.clone());
        if gate_only {
            self.send(Cmd::Gate(mic.threshold, mic.grace));
        } else {
            self.send(Cmd::Apply(Box::new(s)));
        }
    }

    fn set_stream(mut self: Pin<&mut Self>, on: bool, sources: &QString) {
        let new: serde_json::Map<String, Value> = serde_json::from_str(&sources.to_string()).unwrap_or_default();
        let was_on = settings::read(|s| s.sound.stream.on);
        let mut changed: Vec<(String, sound::Send)> = Vec::new();
        let s = self.as_mut().change(|s| {
            s.stream.on = on;
            for (k, v) in new {
                if let Ok(send) = serde_json::from_value::<sound::Send>(v) {
                    changed.push((k.clone(), send.clone()));
                    s.stream.sources.insert(k, send);
                }
            }
        });
        if was_on != on {
            self.send(Cmd::Apply(Box::new(s)));
        } else {
            for (k, send) in changed {
                self.send(Cmd::Send(k, send));
            }
        }
    }

    fn move_app(mut self: Pin<&mut Self>, index: i32, key: &QString, always: bool) {
        let key = key.to_string();
        if index < 0 || !sound::CHANNELS.iter().any(|(k, _, _)| *k == key) {
            return;
        }
        if always {
            let apps: Vec<Value> = serde_json::from_str(&self.rust().apps.to_string()).unwrap_or_default();
            let program = apps.iter().find(|a| a["index"].as_i64() == Some(i64::from(index))).and_then(|a| a["program"].as_str()).map(str::to_string);
            if let Some(program) = program.filter(|p| !p.is_empty()) {
                self.as_mut().change(|s| {
                    s.routes.insert(program, key.clone());
                });
            }
        }
        if always {
            let s = settings::read(|s| s.sound.clone());
            self.send(Cmd::Apply(Box::new(s)));
        }
        self.send(Cmd::Move(index as u64, key));
    }

    fn forget_route(mut self: Pin<&mut Self>, program: &QString) {
        let program = program.to_string();
        let s = self.as_mut().change(|s| {
            s.routes.remove(&program);
        });
        self.send(Cmd::Apply(Box::new(s)));
    }

    fn save_preset(mut self: Pin<&mut Self>, name: &QString, values: &QString) {
        let name = name.to_string().trim().to_string();
        let Some(v) = eq_from(&values.to_string()) else { return };
        if name.is_empty() || sound::PRESETS.iter().any(|(n, _)| *n == name) {
            return;
        }
        self.as_mut().change(|s| {
            s.presets.insert(name, v);
        });
        self.show_state();
    }

    fn delete_preset(mut self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        self.as_mut().change(|s| {
            if let Some(v) = s.presets.remove(&name) {
                // A channel on it keeps its values as own ones.
                for ch in s.channels.values_mut().filter(|c| c.preset == name) {
                    ch.preset = String::new();
                    ch.eq = v;
                }
            }
        });
        self.show_state();
    }

    fn set_game(self: Pin<&mut Self>, id: &QString) {
        let game = crate::games_object::game_audio(&id.to_string()).unwrap_or_default();
        self.send(Cmd::Game(game));
    }

    fn refresh(self: Pin<&mut Self>) {
        self.send(Cmd::Refresh);
    }

    fn set_meter(mut self: Pin<&mut Self>, on: bool) {
        // Kept: the worker may not run yet (begin sends it then).
        self.as_mut().rust_mut().meter_on = on;
        self.send(Cmd::Meter(on));
    }

    fn hear(self: Pin<&mut Self>) {
        self.send(Cmd::Hear);
    }

    fn close_easy_effects(self: Pin<&mut Self>) {
        crate::log::write("sound", "EasyEffects asked to quit");
        self.send(Cmd::CloseEasyEffects);
    }
}
