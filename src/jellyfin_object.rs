//! The Streams panel's Jellyfin tab for QML: the sign-in, the lists (in the
//! background), what a video window plays, and what the server is told.
//! Everything goes through `jellyfin`, which reaches the home network only.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::jellyfin::{self, Folder};
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
        /// Who is signed in where: JSON `{"server","serverName","user"}`, or "".
        #[qproperty(QString, account)]
        /// The sign-in: "" (nothing going on), "busy", or why it failed.
        #[qproperty(QString, sign_in_state)]
        /// "continue", "nextup", "libraries", "folder" or "search".
        #[qproperty(QString, view)]
        /// The list (JSON items), its state (idle, loading, ready, failed) and a line about it.
        #[qproperty(QString, items)]
        #[qproperty(QString, state)]
        #[qproperty(QString, message)]
        /// Whether a folder has more than is shown (`more` loads them).
        #[qproperty(bool, has_more)]
        #[qproperty(QString, quality)]
        #[qproperty(bool, auto_skip)]
        #[qproperty(bool, auto_next)]
        type Jellyfin = super::JellyfinRust;

        /// Signs in (the key is kept on this PC, the password nowhere).
        #[qinvokable]
        fn sign_in(self: Pin<&mut Jellyfin>, server: &QString, user: &QString, password: &QString);

        #[qinvokable]
        fn sign_out(self: Pin<&mut Jellyfin>);

        /// Loads a list: "continue", "nextup", "libraries", "folder" (`arg`:
        /// JSON `{id, type, collection, seriesId}`) or "search" (`arg`: the words).
        #[qinvokable]
        fn load(self: Pin<&mut Jellyfin>, view: &QString, arg: &QString);

        /// The next page of the folder shown.
        #[qinvokable]
        fn more(self: Pin<&mut Jellyfin>);

        /// Gets an item ready to play in `slot`: its file and tracks come
        /// with `prepared`, its parts to skip with `segments_loaded`.
        /// `audio` is the server's audio track index (-1: the file's own).
        #[qinvokable]
        fn prepare(self: Pin<&mut Jellyfin>, slot: &QString, item: &QString, quality: &QString, audio: i32);

        /// JSON `{url, header, source, session, transcode, tracks}` or `{error}`.
        #[qsignal]
        fn prepared(self: Pin<&mut Jellyfin>, slot: QString, item: QString, answer: QString);

        /// JSON `[{kind, start, end}]`.
        #[qsignal]
        fn segments_loaded(self: Pin<&mut Jellyfin>, slot: QString, item: QString, segments: QString);

        /// The address of a subtitle file the server has: JSON `{url}` or `{error}`.
        #[qinvokable]
        fn subtitle(self: &Jellyfin, item: &QString, source: &QString, index: i32, format: &QString) -> QString;

        /// Tells the server what plays: `kind` "start", "progress" or
        /// "stopped"; `what` JSON `{item, source, session, position, paused, transcode}`.
        #[qinvokable]
        fn report(self: &Jellyfin, kind: &QString, what: &QString);

        /// Marks an item watched or not, then loads the list again.
        #[qinvokable]
        fn set_played(self: Pin<&mut Jellyfin>, item: &QString, on: bool);

        /// Looks for the episode after `item`; it comes with `next_found`.
        #[qinvokable]
        fn find_next(self: Pin<&mut Jellyfin>, slot: &QString, series: &QString, item: &QString);

        /// Looks for the track `step` places from `item` in its album (1
        /// the next, -1 the one before); it comes with `next_found`.
        #[qinvokable]
        fn find_track(self: Pin<&mut Jellyfin>, slot: &QString, album: &QString, item: &QString, step: i32);

        /// The next episode (JSON item), or "" for none.
        #[qsignal]
        fn next_found(self: Pin<&mut Jellyfin>, slot: QString, after: QString, next: QString);

        #[qinvokable]
        fn save_quality(self: Pin<&mut Jellyfin>, quality: &QString);

        #[qinvokable]
        fn save_auto_skip(self: Pin<&mut Jellyfin>, on: bool);

        #[qinvokable]
        fn save_auto_next(self: Pin<&mut Jellyfin>, on: bool);
    }

    impl cxx_qt::Threading for Jellyfin {}
}

pub struct JellyfinRust {
    account: QString,
    sign_in_state: QString,
    view: QString,
    items: QString,
    state: QString,
    message: QString,
    has_more: bool,
    quality: QString,
    auto_skip: bool,
    auto_next: bool,
    request: u64,
    /// The folder shown, how many of its items are loaded, and its total.
    folder: Option<Folder>,
    loaded: usize,
    total: usize,
}

fn q(s: &str) -> QString {
    QString::from(s)
}

fn demo_mode() -> bool {
    std::env::var("GC_DEMO").is_ok_and(|d| d.contains("jellyfin"))
}

impl Default for JellyfinRust {
    fn default() -> Self {
        let s = settings::read(|s| s.jellyfin.clone());
        let account = if demo_mode() {
            json!({ "server": "http://192.168.1.20:8096", "serverName": "Home server", "user": "you" }).to_string()
        } else {
            jellyfin::load_account().map(|a| a.public().to_string()).unwrap_or_default()
        };
        let mut me = Self {
            account: q(&account),
            sign_in_state: QString::default(),
            view: q(&s.view),
            items: q("[]"),
            state: q("idle"),
            message: QString::default(),
            has_more: false,
            quality: q(&s.quality),
            auto_skip: s.auto_skip,
            auto_next: s.auto_next,
            request: 0,
            folder: None,
            loaded: 0,
            total: 0,
        };
        if demo_mode() {
            me.items = q(&demo_items().to_string());
            me.state = q("ready");
        }
        me
    }
}

/// Screenshots (GC_DEMO=streams,jellyfin): made-up items, nothing fetched.
fn demo_items() -> Value {
    let one = |i: usize, name: &str, sub: &str, kind: &str, runtime: f64, position: f64| {
        json!({ "id": format!("{i:0>32}"), "type": kind, "name": name, "sub": sub, "series": "", "code": "",
                "playable": true, "openable": false, "seriesId": "", "seasonId": "", "collection": "", "runtime": runtime,
                "position": position, "percent": if runtime > 0.0 { position / runtime * 100.0 } else { 0.0 },
                "played": false, "unplayed": 0, "picture": "", "poster": "" })
    };
    json!([
        one(1, "Episode title", "Series name · S2 E5", "Episode", 2700.0, 1620.0),
        one(2, "Movie title", "2021", "Movie", 7200.0, 2280.0),
        one(3, "Another episode", "Series name · S1 E9", "Episode", 1800.0, 1440.0),
        one(4, "Season opener", "Series name · S4 E1", "Episode", 2640.0, 240.0)
    ])
}

impl qobject::Jellyfin {
    fn signed_out(mut self: Pin<&mut Self>, why: &str) {
        self.as_mut().set_account(QString::default());
        self.as_mut().set_items(q("[]"));
        self.as_mut().set_state(q("failed"));
        self.set_message(q(why));
    }

    fn sign_in(mut self: Pin<&mut Self>, server: &QString, user: &QString, password: &QString) {
        let (server, user, password) = (server.to_string(), user.to_string(), password.to_string());
        if demo_mode() {
            return;
        }
        // Checked here at once: an address that isn't a home network's is never tried.
        if let Err(e) = jellyfin::parse_server(&server) {
            self.set_sign_in_state(q(&e));
            return;
        }
        self.as_mut().set_sign_in_state(q("busy"));
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = jellyfin::sign_in(&server, &user, &password);
            drop(password);
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Jellyfin>| match result {
                Ok(account) => {
                    obj.as_mut().set_sign_in_state(QString::default());
                    obj.as_mut().set_account(q(&account.public().to_string()));
                    obj.load(&q("continue"), &QString::default());
                }
                Err(e) => obj.set_sign_in_state(q(&e)),
            });
        });
    }

    fn sign_out(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().request += 1;
        if !demo_mode() {
            std::thread::spawn(jellyfin::sign_out);
        }
        self.as_mut().set_account(QString::default());
        self.as_mut().set_items(q("[]"));
        self.as_mut().set_state(q("idle"));
        self.as_mut().set_has_more(false);
        self.set_message(QString::default());
    }

    fn load(mut self: Pin<&mut Self>, view: &QString, arg: &QString) {
        let (view, arg) = (view.to_string(), arg.to_string());
        if !matches!(view.as_str(), "continue" | "nextup" | "libraries" | "folder" | "search") {
            return;
        }
        self.as_mut().set_view(q(&view));
        if view != "folder" && view != "search" {
            settings::change(|s| s.jellyfin.view = view.clone());
        }
        if demo_mode() {
            return;
        }
        let Some(account) = jellyfin::load_account() else {
            self.as_mut().rust_mut().request += 1;
            self.signed_out("");
            return;
        };
        let folder: Option<Folder> = if view == "folder" { serde_json::from_str(&arg).ok() } else { None };
        if (view == "folder" && folder.is_none()) || (view == "search" && arg.trim().is_empty()) {
            self.as_mut().rust_mut().request += 1;
            self.as_mut().set_items(q("[]"));
            self.as_mut().set_state(q("idle"));
            self.as_mut().set_has_more(false);
            self.set_message(QString::default());
            return;
        }
        let request = {
            let mut r = self.as_mut().rust_mut();
            r.request += 1;
            r.folder = folder.clone();
            r.loaded = 0;
            r.total = 0;
            r.request
        };
        self.as_mut().set_state(q("loading"));
        self.as_mut().set_has_more(false);
        self.as_mut().set_message(QString::default());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result: Result<(Vec<Value>, usize), String> = match view.as_str() {
                "continue" => jellyfin::continue_watching(&account).map(|l| { let n = l.len(); (l, n) }),
                "nextup" => jellyfin::next_up(&account).map(|l| { let n = l.len(); (l, n) }),
                "libraries" => jellyfin::libraries(&account).map(|l| { let n = l.len(); (l, n) }),
                "folder" => jellyfin::folder(&account, folder.as_ref().unwrap_or(&Folder::default()), 0),
                _ => jellyfin::search(&account, &arg).map(|l| { let n = l.len(); (l, n) }),
            };
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Jellyfin>| {
                if obj.rust().request != request {
                    return;
                }
                match result {
                    Ok((list, total)) => {
                        {
                            let mut r = obj.as_mut().rust_mut();
                            r.loaded = list.len();
                            r.total = total;
                        }
                        obj.as_mut().set_has_more(total > list.len());
                        let n = total.max(list.len());
                        obj.as_mut().set_message(q(&format!("{n} {}", if n == 1 { "item" } else { "items" })));
                        obj.as_mut().set_items(q(&Value::Array(list).to_string()));
                        obj.set_state(q("ready"));
                    }
                    Err(why) => {
                        obj.as_mut().set_items(q("[]"));
                        obj.as_mut().set_state(q("failed"));
                        obj.set_message(q(&why));
                    }
                }
            });
        });
    }

    fn more(mut self: Pin<&mut Self>) {
        let (folder, start, total) = {
            let r = self.rust();
            (r.folder.clone(), r.loaded, r.total)
        };
        let Some(folder) = folder else { return };
        if start >= total || self.state().to_string() == "loading" || demo_mode() {
            return;
        }
        let Some(account) = jellyfin::load_account() else { return };
        let request = self.rust().request;
        self.as_mut().set_state(q("loading"));
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = jellyfin::folder(&account, &folder, start);
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Jellyfin>| {
                if obj.rust().request != request {
                    return;
                }
                match result {
                    Ok((more, total)) => {
                        let mut all: Vec<Value> = serde_json::from_str(&obj.items().to_string()).unwrap_or_default();
                        all.extend(more);
                        {
                            let mut r = obj.as_mut().rust_mut();
                            r.loaded = all.len();
                            r.total = total;
                        }
                        obj.as_mut().set_has_more(total > all.len());
                        obj.as_mut().set_items(q(&Value::Array(all).to_string()));
                        obj.set_state(q("ready"));
                    }
                    Err(why) => {
                        obj.as_mut().set_state(q("ready"));
                        obj.set_message(q(&why));
                    }
                }
            });
        });
    }

    fn prepare(self: Pin<&mut Self>, slot: &QString, item: &QString, quality: &QString, audio: i32) {
        let (slot, item, quality) = (slot.to_string(), item.to_string(), quality.to_string());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let answer = (|| -> Result<Value, String> {
                if !jellyfin::item_ok(&item) {
                    return Err("not a Jellyfin item".into());
                }
                let account = jellyfin::load_account().ok_or("Sign in to your Jellyfin server first.")?;
                // Without the server's play info it still plays (the file as it is).
                let info = jellyfin::playback_info(&account, &item).unwrap_or(Value::Null);
                let source = info.pointer("/MediaSources/0").cloned().unwrap_or(Value::Null);
                let source_id = source.get("Id").and_then(Value::as_str).filter(|s| jellyfin::token_ok(s)).unwrap_or(&item).to_string();
                let session = info.get("PlaySessionId").and_then(Value::as_str).filter(|s| jellyfin::token_ok(s)).unwrap_or("").to_string();
                let tracks = if source.is_null() { json!({ "audio": [], "subs": [], "audioIndex": -1, "subIndex": -1 }) } else { jellyfin::tracks_of(&source) };
                // A music track: its file as it is, whatever the video quality.
                let music = jellyfin::sound_only(&source);
                let transcode = !music && !matches!(quality.as_str(), "original" | "audio");
                let audio_index = if audio >= 0 { Some(audio as u32) } else { tracks["audioIndex"].as_i64().filter(|a| *a >= 0).map(|a| a as u32) };
                let path = if music {
                    jellyfin::audio_path(&item, &source_id)
                } else {
                    jellyfin::stream_path(&item, &source_id, &session, &quality, if transcode { audio_index } else { None })
                };
                let (url, header) = jellyfin::mpv_source(&account, &path)?;
                Ok(json!({ "url": url, "header": header, "source": source_id, "session": session, "transcode": transcode, "tracks": tracks, "music": music }))
            })();
            let music = answer.as_ref().is_ok_and(|a| a["music"] == true);
            let answer = answer.unwrap_or_else(|e| json!({ "error": e })).to_string();
            let (s2, i2) = (slot.clone(), item.clone());
            let _ = thread.queue(move |obj: Pin<&mut qobject::Jellyfin>| obj.prepared(q(&slot), q(&item), q(&answer)));
            // Then the parts to skip, which may take a few tries (music has none).
            if music {
                return;
            }
            if let Some(account) = jellyfin::load_account() {
                let segs = Value::Array(jellyfin::skip_segments(&account, &i2)).to_string();
                let _ = thread.queue(move |obj: Pin<&mut qobject::Jellyfin>| obj.segments_loaded(q(&s2), q(&i2), q(&segs)));
            }
        });
    }

    fn subtitle(&self, item: &QString, source: &QString, index: i32, format: &QString) -> QString {
        let (item, source, format) = (item.to_string(), source.to_string(), format.to_string());
        let answer = (|| -> Result<String, String> {
            if !jellyfin::item_ok(&item) || !jellyfin::token_ok(&source) || !(0..1000).contains(&index) || !["srt", "vtt", "ass", "ssa"].contains(&format.as_str()) {
                return Err("not a subtitle".into());
            }
            let account = jellyfin::load_account().ok_or("not signed in")?;
            let src = if source.is_empty() { item.clone() } else { source };
            let (url, _) = jellyfin::mpv_source(&account, &format!("/Videos/{item}/{src}/Subtitles/{index}/0/Stream.{format}"))?;
            Ok(url)
        })();
        q(&match answer {
            Ok(url) => json!({ "url": url }),
            Err(e) => json!({ "error": e }),
        }
        .to_string())
    }

    fn report(&self, kind: &QString, what: &QString) {
        let kind = kind.to_string();
        let what: Value = serde_json::from_str(&what.to_string()).unwrap_or(Value::Null);
        if demo_mode() || !what.is_object() {
            return;
        }
        let text = |k: &str| what.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let (item, source, session) = (text("item"), text("source"), text("session"));
        let position = what.get("position").and_then(Value::as_f64).unwrap_or(0.0);
        let paused = what.get("paused").and_then(Value::as_bool).unwrap_or(false);
        let transcode = what.get("transcode").and_then(Value::as_bool).unwrap_or(false);
        std::thread::spawn(move || {
            if let Some(account) = jellyfin::load_account() {
                let _ = jellyfin::report(&account, &kind, &item, &source, &session, position, paused, transcode);
            }
        });
    }

    fn set_played(self: Pin<&mut Self>, item: &QString, on: bool) {
        let item = item.to_string();
        let Some(account) = jellyfin::load_account() else { return };
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = jellyfin::set_played(&account, &item, on);
            let _ = thread.queue(move |obj: Pin<&mut qobject::Jellyfin>| {
                if let Err(e) = result {
                    obj.set_message(q(&e));
                    return;
                }
                // The list as the server has it now.
                let view = obj.view().to_string();
                let arg = match view.as_str() {
                    "folder" => obj.rust().folder.as_ref().map(|f| json!({ "id": f.id, "type": f.kind, "collection": f.collection, "seriesId": f.series_id }).to_string()),
                    _ => None,
                };
                if view != "search" {
                    obj.load(&q(&view), &q(&arg.unwrap_or_default()));
                }
            });
        });
    }

    fn find_next(self: Pin<&mut Self>, slot: &QString, series: &QString, item: &QString) {
        let (slot, series, item) = (slot.to_string(), series.to_string(), item.to_string());
        let Some(account) = jellyfin::load_account() else { return };
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let next = jellyfin::next_episode(&account, &series, &item).ok().flatten().map(|v| v.to_string()).unwrap_or_default();
            let _ = thread.queue(move |obj: Pin<&mut qobject::Jellyfin>| obj.next_found(q(&slot), q(&item), q(&next)));
        });
    }

    fn find_track(self: Pin<&mut Self>, slot: &QString, album: &QString, item: &QString, step: i32) {
        let (slot, album, item) = (slot.to_string(), album.to_string(), item.to_string());
        let Some(account) = jellyfin::load_account() else { return };
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let next = jellyfin::album_track(&account, &album, &item, step.signum() as i64).ok().flatten().map(|v| v.to_string()).unwrap_or_default();
            let _ = thread.queue(move |obj: Pin<&mut qobject::Jellyfin>| obj.next_found(q(&slot), q(&item), q(&next)));
        });
    }

    fn save_quality(self: Pin<&mut Self>, quality: &QString) {
        let quality = quality.to_string();
        if !matches!(quality.as_str(), "original" | "1080" | "720" | "480" | "360" | "audio") {
            return;
        }
        settings::change(|s| s.jellyfin.quality = quality.clone());
        self.set_quality(q(&quality));
    }

    fn save_auto_skip(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.jellyfin.auto_skip = on);
        self.set_auto_skip(on);
    }

    fn save_auto_next(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.jellyfin.auto_next = on);
        self.set_auto_next(on);
    }
}

/// A picture for the C++ image provider (`image://jellyfin/<item>/<kind>/<width>`):
/// its bytes, or nothing. Called on Qt's picture threads.
///
/// # Safety
/// `id` points at `len` bytes; `out` and `out_len` are writable. What
/// `out` gets is given back with `gc_jellyfin_picture_free`.
#[no_mangle]
pub unsafe extern "C" fn gc_jellyfin_picture(id: *const u8, len: usize, out: *mut *mut u8, out_len: *mut usize) -> bool {
    if id.is_null() || out.is_null() || out_len.is_null() || len > 200 || demo_mode() {
        return false;
    }
    let Ok(id) = std::str::from_utf8(std::slice::from_raw_parts(id, len)) else { return false };
    match jellyfin::picture(id) {
        Ok(bytes) if !bytes.is_empty() => {
            let boxed = bytes.into_boxed_slice();
            *out_len = boxed.len();
            *out = Box::into_raw(boxed) as *mut u8;
            true
        }
        _ => false,
    }
}

/// Gives back what `gc_jellyfin_picture` handed out.
///
/// # Safety
/// Only with a pointer and length `gc_jellyfin_picture` gave.
#[no_mangle]
pub unsafe extern "C" fn gc_jellyfin_picture_free(data: *mut u8, len: usize) {
    if !data.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, len)));
    }
}
