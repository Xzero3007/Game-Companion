//! The voice overlay for QML (the `VoiceChat` singleton): who is in your
//! Legcord voice channel and who talks (`voice_overlay`), the plugin's
//! state and the overlay's choices (Settings → Apps → Legcord).

use std::collections::BTreeMap;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::settings;
use crate::voice_overlay::{self, Message, PLUGIN_VERSION};

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
        /// `{"connected","installed","plugin","shipped","legcord","ok",
        /// "missing","channel","me","members":[{"id","name","avatar",
        /// "speaking","muted","deafened","joined"}]}`.
        #[qproperty(QString, state)]
        /// Avatars by hash: `{"<hash>": "file:///run/user/…/<hash>.png"}`.
        #[qproperty(QString, pictures)]
        /// The overlay's choices as JSON (QML fills in the defaults).
        #[qproperty(QString, prefs)]
        type VoiceChat = super::VoiceChatRust;

        /// Starts listening for the plugin (once, from Main).
        #[qinvokable]
        fn begin(self: Pin<&mut VoiceChat>);

        /// Puts the plugin into Legcord's plugins folder; "" or why not.
        #[qinvokable]
        fn install(self: Pin<&mut VoiceChat>) -> QString;

        /// Takes the plugin out of Legcord again; "" or why not.
        #[qinvokable]
        fn remove(self: Pin<&mut VoiceChat>) -> QString;

        /// Keeps one choice (`value` is JSON).
        #[qinvokable]
        fn set_pref(self: Pin<&mut VoiceChat>, key: &QString, value: &QString);
    }

    impl cxx_qt::Threading for VoiceChat {}
}

pub struct VoiceChatRust {
    state: QString,
    pictures: QString,
    prefs: QString,
    connected: bool,
    plugin: i64,
    legcord: String,
    ok: Option<bool>,
    missing: Vec<String>,
    live: Value,
    pics: BTreeMap<String, String>,
    started: bool,
    demo: bool,
}

impl Default for VoiceChatRust {
    fn default() -> Self {
        let demo = std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "voice"));
        let prefs = Value::Object(settings::read(|s| s.voice.clone())).to_string();
        let mut me = Self {
            state: QString::default(),
            pictures: QString::from("{}"),
            prefs: QString::from(&prefs),
            connected: false,
            plugin: 0,
            legcord: String::new(),
            ok: None,
            missing: Vec::new(),
            live: json!({ "channel": null, "me": "", "members": [] }),
            pics: BTreeMap::new(),
            started: false,
            demo,
        };
        if demo {
            me.connected = true;
            me.plugin = PLUGIN_VERSION;
            me.legcord = "1.3.1".into();
            me.ok = Some(true);
            me.live = demo_state();
            // One made-up picture: shows that pictures come through.
            let url = voice_overlay::base64_decode(DEMO_PNG)
                .and_then(|png| {
                    let path = voice_overlay::pictures_dir()?.join(format!("{DEMO_HASH}.png"));
                    std::fs::write(&path, png).ok()?;
                    Some(format!("file://{}", path.display()))
                })
                .unwrap_or_default();
            me.pics.insert(DEMO_HASH.into(), url);
            me.pictures = QString::from(&serde_json::to_string(&me.pics).unwrap_or_default());
        }
        me.state = QString::from(&me.state_json());
        me
    }
}

const DEMO_HASH: &str = "0123456789abcdef0123456789abcdef";
const DEMO_PNG: &str = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAABEklEQVR42u2a0Q3CMAxEG6vzsAgjMAMb8MkqDAQTMQAVTXznxmnOn1Vl37OdNI5a7tf3MrLZMrgJQAACEIAA5gZYg/w+bpffh8/Xhx6o0I8Sm9LjMJgAu9IjMKyLesf7sQA+NRQG66WexTD9dwBPIehh7gqwdhLEj85CAhCAAAYGYJ0oET/TtxBeBNCDFjGWQryA1nEVUvYAWgu1qmHtYLqVaMEY417oYFsPS39QEWgVcExVFBgCADhYghgQAGsmRjAsg3rEm6cCXOlgKSyVeod/S6XeEcWyqW+NZQnVN0WcY6A5Pv31cS2t+sroZ2+hvumv0XDqCmRI/64S3QsJIAogzwL4r0ctJIDZAYp+/hYAZl97jGHBz+5eEgAAAABJRU5ErkJggg==";

/// Made-up people for screenshots (`GC_DEMO=voice`).
fn demo_state() -> Value {
    let m = |id: &str, name: &str, speaking: bool, muted: bool, joined: i64| {
        json!({ "id": id, "name": name, "avatar": "", "speaking": speaking, "muted": muted, "deafened": false, "joined": joined })
    };
    json!({
        "channel": { "id": "1", "name": "Raid" },
        "me": "5",
        "members": [json!({ "id": "1", "name": "Kael", "avatar": DEMO_HASH, "speaking": true, "muted": false, "deafened": false, "joined": 1 }), m("2", "Mira", false, false, 2), m("3", "Toru", true, false, 3), m("4", "Lyra", false, true, 4), m("5", "MN", false, false, 5)],
    })
}

impl VoiceChatRust {
    fn state_json(&self) -> String {
        json!({
            "connected": self.connected,
            "installed": self.demo || voice_overlay::installed(),
            "legcordFound": self.demo || !voice_overlay::legcord_dirs().is_empty(),
            "plugin": self.plugin,
            "shipped": PLUGIN_VERSION,
            "legcord": self.legcord,
            "ok": self.ok,
            "missing": self.missing,
            "channel": self.live["channel"],
            "me": self.live["me"],
            "members": self.live["members"],
        })
        .to_string()
    }
}

impl qobject::VoiceChat {
    fn refresh(mut self: Pin<&mut Self>) {
        let json = self.rust().state_json();
        if self.rust().state.to_string() != json {
            self.as_mut().set_state(QString::from(&json));
        }
    }

    fn begin(mut self: Pin<&mut Self>) {
        if self.rust().started || self.rust().demo {
            return;
        }
        self.as_mut().rust_mut().started = true;
        voice_overlay::refresh();
        let thread = self.qt_thread();
        let result = voice_overlay::listen(move |m| {
            let _ = thread.queue(move |obj: Pin<&mut qobject::VoiceChat>| obj.take(m));
        });
        if let Err(e) = result {
            eprintln!("game-companion: voice overlay cannot listen: {e}");
        }
        self.refresh();
    }

    fn take(mut self: Pin<&mut Self>, m: Message) {
        {
            let mut r = self.as_mut().rust_mut();
            match m {
                Message::Hello { plugin, legcord } => {
                    r.connected = true;
                    r.plugin = plugin;
                    r.legcord = legcord;
                }
                Message::Check { ok, missing } => {
                    r.connected = true;
                    r.ok = Some(ok);
                    r.missing = missing;
                }
                Message::State(s) => {
                    r.connected = true;
                    r.live = s;
                }
                Message::Picture { .. } => {}
                Message::Saved { hash, url } => {
                    r.pics.insert(hash, url);
                    // Kept small: the people of a few channels.
                    while r.pics.len() > 300 {
                        let first = r.pics.keys().next().cloned();
                        if let Some(k) = first {
                            r.pics.remove(&k);
                        }
                    }
                }
                Message::Gone => {
                    r.connected = false;
                    r.live = json!({ "channel": null, "me": "", "members": [] });
                }
            }
        }
        let pics_changed = {
            let r = self.rust();
            let json = serde_json::to_string(&r.pics).unwrap_or_default();
            (r.pictures.to_string() != json).then_some(json)
        };
        if let Some(json) = pics_changed {
            self.as_mut().set_pictures(QString::from(&json));
        }
        self.refresh();
    }

    fn install(mut self: Pin<&mut Self>) -> QString {
        let why = voice_overlay::install().err().unwrap_or_default();
        self.as_mut().refresh();
        QString::from(&why)
    }

    fn remove(mut self: Pin<&mut Self>) -> QString {
        let why = voice_overlay::remove().err().unwrap_or_default();
        self.as_mut().refresh();
        QString::from(&why)
    }

    fn set_pref(mut self: Pin<&mut Self>, key: &QString, value: &QString) {
        let key = key.to_string();
        let Ok(value) = serde_json::from_str::<Value>(&value.to_string()) else { return };
        let mut prefs = match serde_json::from_str::<Value>(&self.rust().prefs.to_string()) {
            Ok(Value::Object(o)) => o,
            _ => serde_json::Map::new(),
        };
        prefs.insert(key.clone(), value.clone());
        if !self.rust().demo {
            settings::change(|s| {
                s.voice.insert(key, value);
            });
        }
        self.as_mut().set_prefs(QString::from(&Value::Object(prefs).to_string()));
    }
}
