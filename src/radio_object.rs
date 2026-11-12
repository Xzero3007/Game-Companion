//! The radio for QML: what plays, its state and volume, favourites and the
//! panel's filters. The player (mpv) lives here, not in any window, so the
//! sound goes on with the radio panel closed or the hub hidden.

use std::pin::Pin;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::radio::{self, Event, Player};
use crate::settings;

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
        /// The chosen station's id ("" for none).
        #[qproperty(QString, station)]
        /// Its name, for the player row.
        #[qproperty(QString, name)]
        /// idle, connecting, playing, buffering, paused or failed.
        #[qproperty(QString, status)]
        /// Why it failed, in plain words.
        #[qproperty(QString, why)]
        /// 0 to 100.
        #[qproperty(i32, volume)]
        /// JSON lists of station ids.
        #[qproperty(QString, favourites)]
        #[qproperty(QString, recent)]
        /// The panel's list and filters, kept between starts.
        #[qproperty(QString, tab)]
        #[qproperty(QString, country)]
        #[qproperty(QString, genre)]
        type Radio = super::RadioRust;

        /// The station list for the panel, as JSON (no stream addresses).
        #[qinvokable]
        fn catalog(self: &Radio) -> QString;

        #[qinvokable]
        fn play(self: Pin<&mut Radio>, id: &QString);

        /// Pause holds the station; play goes on live.
        #[qinvokable]
        fn toggle_pause(self: Pin<&mut Radio>);

        /// Stops and leaves the player row.
        #[qinvokable]
        fn stop(self: Pin<&mut Radio>);

        /// The next (or previous) station in the given list of ids (JSON).
        #[qinvokable]
        fn skip(self: Pin<&mut Radio>, ids: &QString, forward: bool);

        /// Louder or quieter by `delta` (the − and + buttons, the wheel).
        #[qinvokable]
        fn step_volume(self: Pin<&mut Radio>, delta: i32);

        /// Sets the volume (a click or drag on the bar).
        #[qinvokable]
        fn set_volume_to(self: Pin<&mut Radio>, volume: i32);

        #[qinvokable]
        fn toggle_favourite(self: Pin<&mut Radio>, id: &QString);

        #[qinvokable]
        fn set_view(self: Pin<&mut Radio>, tab: &QString, country: &QString, genre: &QString);
    }

    impl cxx_qt::Threading for Radio {}
}

pub struct RadioRust {
    station: QString,
    name: QString,
    status: QString,
    why: QString,
    volume: i32,
    favourites: QString,
    recent: QString,
    tab: QString,
    country: QString,
    genre: QString,
    player: Option<Player>,
    stream_index: usize,
    /// Counts loads, so a watchdog only acts on its own.
    generation: u64,
}

fn list_json(ids: &[String]) -> QString {
    QString::from(&serde_json::to_string(ids).unwrap_or_else(|_| "[]".into()))
}

impl Default for RadioRust {
    fn default() -> Self {
        let r = settings::read(|s| s.radio.clone());
        // Screenshots only: GC_DEMO=radio-playing shows Best FM as playing.
        let demo = std::env::var("GC_DEMO").is_ok_and(|d| d.split(',').any(|p| p == "radio-playing"));
        let station = if demo { Some("best-fm".to_string()) } else { r.station.clone() };
        let name = station.as_deref().and_then(radio::station).map(|s| s.name.clone()).unwrap_or_default();
        Self {
            station: QString::from(station.as_deref().unwrap_or("")),
            name: QString::from(&name),
            status: QString::from(if demo { "playing" } else { "idle" }),
            why: QString::default(),
            volume: i32::from(r.volume),
            favourites: list_json(&r.favourites),
            recent: list_json(&r.recent),
            tab: QString::from(&r.tab),
            country: QString::from(&r.country),
            genre: QString::from(&r.genre),
            player: None,
            stream_index: 0,
            generation: 0,
        }
    }
}

impl qobject::Radio {
    fn catalog(&self) -> QString {
        QString::from(&radio::catalog_for_ui())
    }

    fn set_state(mut self: Pin<&mut Self>, status: &str, why: &str) {
        self.as_mut().set_status(QString::from(status));
        self.set_why(QString::from(why));
    }

    fn play(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let Some(station) = radio::station(&id) else { return };
        let recent = settings::change(|s| {
            s.radio.station = Some(id.clone());
            radio::remember(&mut s.radio.recent, &id);
            s.radio.recent.clone()
        });
        self.as_mut().set_recent(list_json(&recent));
        self.as_mut().set_station(QString::from(&id));
        self.as_mut().set_name(QString::from(&station.name));
        self.as_mut().rust_mut().stream_index = 0;
        self.try_stream();
    }

    /// Plays the chosen station's current address, or reports that none played.
    fn try_stream(mut self: Pin<&mut Self>) {
        let id = self.station().to_string();
        let Some(station) = radio::station(&id) else { return };
        if self.rust().player.is_none() {
            let thread = self.qt_thread();
            let volume = u8::try_from(*self.volume()).unwrap_or(60);
            let started = Player::start(volume, move |event| {
                let _ = thread.queue(move |obj: Pin<&mut qobject::Radio>| obj.on_event(event));
            });
            match started {
                Ok(player) => self.as_mut().rust_mut().player = Some(player),
                Err(why) => {
                    self.set_state("failed", &why);
                    return;
                }
            }
        }
        let index = self.rust().stream_index;
        let Some(url) = station.streams.get(index) else {
            let why = self.why().to_string();
            let why = if why.is_empty() { "None of its addresses plays from here".to_string() } else { why };
            if let Some(p) = &self.rust().player {
                p.stop();
            }
            self.set_state("failed", &why);
            return;
        };
        self.as_mut().set_state("connecting", "");
        let loaded = self.rust().player.as_ref().is_some_and(|p| p.load(url));
        if !loaded {
            self.as_mut().rust_mut().stream_index += 1;
            return self.try_stream();
        }
        let generation = {
            let mut rust = self.as_mut().rust_mut();
            rust.generation += 1;
            rust.generation
        };
        // A server that takes the request and sends nothing.
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(15));
            let _ = thread.queue(move |obj: Pin<&mut qobject::Radio>| {
                if obj.rust().generation == generation && obj.status().to_string() == "connecting" {
                    obj.on_event(Event::Failed("No answer".into()));
                }
            });
        });
    }

    fn on_event(mut self: Pin<&mut Self>, event: Event) {
        let status = self.status().to_string();
        let active = matches!(status.as_str(), "connecting" | "playing" | "buffering");
        match event {
            Event::Playing if active => self.set_state("playing", ""),
            Event::Buffering if active => self.set_state("buffering", ""),
            Event::Failed(why) if active => {
                self.as_mut().set_why(QString::from(&why));
                self.as_mut().rust_mut().stream_index += 1;
                self.try_stream();
            }
            // The server dropped the stream: connect again.
            Event::Ended if active => self.try_stream(),
            Event::Gone => {
                self.as_mut().rust_mut().player = None;
                if active {
                    self.set_state("failed", "mpv stopped");
                }
            }
            _ => {}
        }
    }

    fn toggle_pause(mut self: Pin<&mut Self>) {
        match self.status().to_string().as_str() {
            "paused" | "failed" | "idle" => {
                if self.station().is_empty() {
                    return;
                }
                self.as_mut().rust_mut().stream_index = 0;
                self.as_mut().set_why(QString::default());
                self.try_stream();
            }
            _ => {
                if let Some(p) = &self.rust().player {
                    p.stop();
                }
                self.set_state("paused", "");
            }
        }
    }

    fn stop(mut self: Pin<&mut Self>) {
        if let Some(p) = &self.rust().player {
            p.stop();
        }
        self.as_mut().rust_mut().generation += 1;
        self.set_state("idle", "");
    }

    fn skip(self: Pin<&mut Self>, ids: &QString, forward: bool) {
        let ids: Vec<String> = serde_json::from_str(&ids.to_string()).unwrap_or_default();
        if let Some(next) = radio::neighbour(&ids, &self.station().to_string(), forward) {
            self.play(&QString::from(&next));
        }
    }

    fn step_volume(self: Pin<&mut Self>, delta: i32) {
        let volume = *self.volume() + delta;
        self.set_volume_to(volume);
    }

    fn set_volume_to(mut self: Pin<&mut Self>, volume: i32) {
        let volume = volume.clamp(0, 100);
        if volume == *self.volume() {
            return;
        }
        let bar = u8::try_from(volume).unwrap_or(0);
        if let Some(p) = &self.rust().player {
            p.set_volume(bar);
        }
        settings::change(|s| s.radio.volume = bar);
        self.as_mut().set_volume(volume);
    }

    fn toggle_favourite(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        if radio::station(&id).is_none() {
            return;
        }
        let favourites = settings::change(|s| {
            let list = &mut s.radio.favourites;
            if let Some(i) = list.iter().position(|f| f == &id) {
                list.remove(i);
            } else {
                list.push(id);
            }
            list.clone()
        });
        self.set_favourites(list_json(&favourites));
    }

    fn set_view(mut self: Pin<&mut Self>, tab: &QString, country: &QString, genre: &QString) {
        let (t, c, g) = (tab.to_string(), country.to_string(), genre.to_string());
        settings::change(|s| {
            s.radio.tab = t;
            s.radio.country = c;
            s.radio.genre = g;
        });
        self.as_mut().set_tab(tab.clone());
        self.as_mut().set_country(country.clone());
        self.set_genre(genre.clone());
    }
}
