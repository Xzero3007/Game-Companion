//! The Streams panel's lists for QML: Twitch and YouTube, loaded in the
//! background; the running game's preset; favourites and channels; the
//! Twitch sign-in; and the address a video player plays.

use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::settings::{self, GamePreset};
use crate::sponsorblock;
use crate::streams::{self, Channel};

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
        /// The running game's preset, JSON `{"name","twitch","youtube"}`.
        #[qproperty(QString, game)]
        /// "twitch", "youtube" or "jellyfin".
        #[qproperty(QString, tab)]
        #[qproperty(QString, twitch_view)]
        #[qproperty(QString, youtube_view)]
        /// The Twitch list (JSON cards), its state (idle, loading, ready,
        /// failed) and a line about it.
        #[qproperty(QString, twitch)]
        #[qproperty(QString, twitch_state)]
        #[qproperty(QString, twitch_message)]
        #[qproperty(QString, youtube)]
        #[qproperty(QString, youtube_state)]
        #[qproperty(QString, youtube_message)]
        /// Twitch logins kept with the star (JSON list).
        #[qproperty(QString, favourites)]
        /// YouTube channels: added by hand and FreeTube's (JSON `[{"id","name","freetube"}]`).
        #[qproperty(QString, channels)]
        /// Whether Streamlink is installed, who is signed in: JSON `{"streamlink","user"}`.
        #[qproperty(QString, account)]
        #[qproperty(QString, quality)]
        #[qproperty(i32, volume)]
        /// The lists as tiles side by side.
        #[qproperty(bool, grid)]
        /// SponsorBlock: JSON `{"enabled", "categories": {category: "skip"|"show"|"off"}}`.
        #[qproperty(QString, sponsorblock)]
        /// Videos decoded by the graphics card.
        #[qproperty(bool, hwdec)]
        type Streams = super::StreamsRust;

        /// Loads a Twitch list: "game", "following", "favourites", "live" or "search" (with `text`).
        #[qinvokable]
        fn load_twitch(self: Pin<&mut Streams>, view: &QString, text: &QString);

        /// Loads a YouTube list: "game", "subscriptions", "channel" (`text` its id) or "search".
        #[qinvokable]
        fn load_youtube(self: Pin<&mut Streams>, view: &QString, text: &QString);

        #[qinvokable]
        fn choose_tab(self: Pin<&mut Streams>, tab: &QString);

        /// Changes the game's preset (until game detection, by hand).
        #[qinvokable]
        fn change_game(self: Pin<&mut Streams>, name: &QString, twitch: &QString, youtube: &QString);

        #[qinvokable]
        fn toggle_favourite(self: Pin<&mut Streams>, login: &QString);

        /// Adds or removes a YouTube channel of one's own.
        #[qinvokable]
        fn toggle_channel(self: Pin<&mut Streams>, id: &QString, name: &QString);

        /// Signs in with twitch.tv's auth-token (checked with Twitch first).
        #[qinvokable]
        fn sign_in(self: Pin<&mut Streams>, token: &QString);

        #[qinvokable]
        fn sign_out(self: Pin<&mut Streams>);

        /// Asks Twitch who the saved token belongs to (and whether Streamlink is there).
        #[qinvokable]
        fn refresh_account(self: Pin<&mut Streams>);

        #[qinvokable]
        fn save_quality(self: Pin<&mut Streams>, quality: &QString);

        #[qinvokable]
        fn save_volume(self: Pin<&mut Streams>, volume: i32);

        #[qinvokable]
        fn save_grid(self: Pin<&mut Streams>, grid: bool);

        #[qinvokable]
        fn save_hwdec(self: Pin<&mut Streams>, on: bool);

        /// How much of a video window shows, in percent (50 to 100).
        #[qinvokable]
        fn opacity_of(self: &Streams, slot: &QString) -> i32;

        #[qinvokable]
        fn save_opacity(self: Pin<&mut Streams>, slot: &QString, percent: i32);

        #[qinvokable]
        fn set_sponsor_enabled(self: Pin<&mut Streams>, enabled: bool);

        #[qinvokable]
        fn set_sponsor_mode(self: Pin<&mut Streams>, category: &QString, mode: &QString);

        /// Takes FreeTube's SponsorBlock settings; says what happened.
        #[qinvokable]
        fn sponsor_from_freetube(self: Pin<&mut Streams>) -> QString;

        /// Asks SponsorBlock for a YouTube video's segments (when it is on);
        /// they come with `segments_loaded`.
        #[qinvokable]
        fn load_segments(self: Pin<&mut Streams>, slot: &QString, id: &QString);

        /// A video's segments: JSON `[{category, start, end, mode}]`.
        #[qsignal]
        fn segments_loaded(self: Pin<&mut Streams>, slot: QString, id: QString, segments: QString);

        /// Forgets the subscriptions kept for a while: the next load asks again.
        #[qinvokable]
        fn forget(self: Pin<&mut Streams>);

        /// What a player plays: JSON `{"url","format","via"}` or `{"error"}`.
        /// Twitch goes through Streamlink when it is installed.
        #[qinvokable]
        fn source(self: Pin<&mut Streams>, slot: &QString, kind: &QString, id: &QString, quality: &QString) -> QString;

        /// Ends a player's Streamlink, if one runs.
        #[qinvokable]
        fn stop_source(self: &Streams, slot: &QString);

        /// A video id from a pasted YouTube link ("" if it is none).
        #[qinvokable]
        fn video_id(self: &Streams, text: &QString) -> QString;

        /// Streamlink ended with an error while it played for `slot`.
        #[qsignal]
        fn source_failed(self: Pin<&mut Streams>, slot: QString, why: QString);
    }

    impl cxx_qt::Threading for Streams {}
}

pub struct StreamsRust {
    game: QString,
    tab: QString,
    twitch_view: QString,
    youtube_view: QString,
    twitch: QString,
    twitch_state: QString,
    twitch_message: QString,
    youtube: QString,
    youtube_state: QString,
    youtube_message: QString,
    favourites: QString,
    channels: QString,
    account: QString,
    quality: QString,
    volume: i32,
    grid: bool,
    sponsorblock: QString,
    hwdec: bool,
    twitch_request: u64,
    youtube_request: u64,
}

fn q(s: &str) -> QString {
    QString::from(s)
}

fn channels_json(own: &[Channel]) -> String {
    let mut list: Vec<Value> = own.iter().map(|c| json!({ "id": c.id, "name": c.name, "freetube": false })).collect();
    for c in streams::freetube().unwrap_or_default() {
        if !own.iter().any(|o| o.id == c.id) {
            list.push(json!({ "id": c.id, "name": c.name, "freetube": true }));
        }
    }
    Value::Array(list).to_string()
}

/// At most this many channels' feeds make the subscriptions.
const MAX_CHANNELS: usize = 120;
/// Feeds asked at once.
const FEEDS_AT_ONCE: usize = 8;
/// How long loaded subscriptions are kept (the refresh button asks again).
const KEEP_SUBSCRIPTIONS: Duration = Duration::from_secs(15 * 60);

type Kept = Option<(Instant, Vec<String>, Vec<Value>)>;

fn subscriptions_kept() -> &'static Mutex<Kept> {
    static KEPT: OnceLock<Mutex<Kept>> = OnceLock::new();
    KEPT.get_or_init(|| Mutex::new(None))
}

/// The subscriptions loaded a little earlier for the same channels.
fn kept_subscriptions(ids: &[String]) -> Option<Vec<Value>> {
    let kept = subscriptions_kept().lock().unwrap_or_else(|p| p.into_inner());
    kept.as_ref().filter(|(at, kept_ids, _)| at.elapsed() < KEEP_SUBSCRIPTIONS && kept_ids == ids).map(|(_, _, v)| v.clone())
}

fn keep_subscriptions(ids: &[String], videos: &[Value]) {
    *subscriptions_kept().lock().unwrap_or_else(|p| p.into_inner()) = Some((Instant::now(), ids.to_vec(), videos.to_vec()));
}

/// The newest 60 videos, newest first.
fn newest(mut all: Vec<Value>) -> Vec<Value> {
    all.sort_by(|a, b| b["published"].as_str().cmp(&a["published"].as_str()));
    all.truncate(60);
    all
}

/// The channels' feeds, several at once (each channel's newest five).
/// `progress` hears how many are done and what came so far, now and then.
fn fetch_feeds(ids: Vec<String>, progress: impl Fn(usize, &[Value])) -> (Vec<Value>, Option<String>) {
    let ids = Arc::new(ids);
    let next = Arc::new(AtomicUsize::new(0));
    let (tx, rx) = mpsc::channel();
    for _ in 0..FEEDS_AT_ONCE.min(ids.len()) {
        let (ids, next, tx) = (ids.clone(), next.clone(), tx.clone());
        std::thread::spawn(move || loop {
            let i = next.fetch_add(1, Ordering::Relaxed);
            let Some(id) = ids.get(i) else { break };
            if tx.send(streams::youtube_feed(id)).is_err() {
                break;
            }
        });
    }
    drop(tx);
    let mut all = Vec::new();
    let mut failed = None;
    let mut done = 0;
    let mut told = Instant::now();
    for result in rx {
        done += 1;
        match result {
            Ok(v) => all.extend(v.into_iter().take(5)),
            Err(e) => failed = Some(e),
        }
        if told.elapsed() > Duration::from_millis(700) && done < ids.len() {
            progress(done, &all);
            told = Instant::now();
        }
    }
    (all, failed)
}

fn account_json(user: &str) -> String {
    json!({ "streamlink": streams::streamlink_path().is_some(), "user": user }).to_string()
}

impl Default for StreamsRust {
    fn default() -> Self {
        let s = settings::read(|s| s.streams.clone());
        let demo = std::env::var("GC_DEMO").unwrap_or_default();
        let mut me = Self {
            game: q(&serde_json::to_string(&s.game).unwrap_or_default()),
            tab: q(&s.tab),
            twitch_view: q(&s.twitch_view),
            youtube_view: q(&s.youtube_view),
            twitch: q("[]"),
            twitch_state: q("idle"),
            twitch_message: QString::default(),
            youtube: q("[]"),
            youtube_state: q("idle"),
            youtube_message: QString::default(),
            favourites: q(&serde_json::to_string(&s.favourites).unwrap_or_else(|_| "[]".into())),
            channels: q(&channels_json(&s.channels)),
            // Who is signed in is asked of Twitch once the panel opens.
            account: q(&account_json(if streams::twitch_token().is_some() { "…" } else { "" })),
            quality: q(&s.quality),
            volume: i32::from(s.volume),
            grid: s.grid,
            sponsorblock: q(&serde_json::to_string(&s.sponsorblock).unwrap_or_default()),
            hwdec: s.hwdec,
            twitch_request: 0,
            youtube_request: 0,
        };
        if demo.contains("streams") {
            me.demo(&demo);
        }
        me
    }
}

impl StreamsRust {
    /// Screenshots (GC_DEMO=streams[,youtube]): made-up lists, nothing fetched.
    fn demo(&mut self, demo: &str) {
        let twitch: Vec<Value> = [("streamer_one", 1204, "Stream title goes here, shortened if long"), ("streamer_two", 860, "Another stream title"),
            ("streamer_three", 412, "Raid night, come along"), ("streamer_four", 95, "Farming and chatting")]
            .iter()
            .map(|(l, v, t)| json!({ "login": l, "name": l, "live": true, "viewers": v, "title": t, "game": "AION 2", "picture": "", "since": "" }))
            .collect();
        let youtube: Vec<Value> = [("AION 2 class guide: every skill explained", "channel_name", 1102.0), ("Patch notes in ten minutes", "another_channel", 587.0),
            ("Raid boss walkthrough", "channel_name", 1865.0), ("First look at the new region", "third_channel", 3730.0)]
            .iter()
            .enumerate()
            .map(|(i, (t, c, d))| json!({ "id": format!("demo000000{i}"), "title": t, "channel": c, "duration": d, "views": 0, "live": false,
                "published": format!("2026-11-1{}T08:00:00Z", 2 - i.min(2)), "picture": "" }))
            .collect();
        self.twitch = q(&Value::Array(twitch).to_string());
        self.twitch_state = q("ready");
        self.youtube = q(&Value::Array(youtube).to_string());
        self.youtube_state = q("ready");
        self.favourites = q("[\"streamer_one\"]");
        self.account = q(&json!({ "streamlink": true, "user": "" }).to_string());
        if demo.contains("youtube") {
            self.tab = q("youtube");
        }
        if demo.contains("jellyfin") {
            self.tab = q("jellyfin");
        }
    }
}

impl qobject::Streams {
    fn demo_mode() -> bool {
        std::env::var("GC_DEMO").is_ok_and(|d| d.contains("streams"))
    }

    fn load_twitch(mut self: Pin<&mut Self>, view: &QString, text: &QString) {
        let view = view.to_string();
        let text = text.to_string();
        if !matches!(view.as_str(), "game" | "following" | "favourites" | "live" | "search") {
            return;
        }
        self.as_mut().set_twitch_view(q(&view));
        if view != "search" {
            settings::change(|s| s.streams.twitch_view = view.clone());
        }
        if Self::demo_mode() {
            return;
        }
        if view == "search" && text.trim().is_empty() {
            // The search tab, before anything is typed.
            self.as_mut().rust_mut().twitch_request += 1;
            self.as_mut().set_twitch(q("[]"));
            self.as_mut().set_twitch_state(q("idle"));
            self.set_twitch_message(QString::default());
            return;
        }
        let (game, favourites) = settings::read(|s| (s.streams.game.twitch.clone(), s.streams.favourites.clone()));
        let token = streams::twitch_token();
        if view == "following" && token.is_none() {
            self.as_mut().set_twitch(q("[]"));
            self.as_mut().set_twitch_state(q("failed"));
            self.set_twitch_message(q("Sign in to Twitch in Settings → Streams to see the channels you follow."));
            return;
        }
        let request = {
            let mut r = self.as_mut().rust_mut();
            r.twitch_request += 1;
            r.twitch_request
        };
        self.as_mut().set_twitch_state(q("loading"));
        self.as_mut().set_twitch_message(QString::default());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = (|| -> Result<Vec<Value>, String> {
                let (body, token) = match view.as_str() {
                    "game" => (streams::twitch_query("live", &json!(game))?, None),
                    "live" => (streams::twitch_query("live", &Value::Null)?, None),
                    "favourites" if favourites.is_empty() => return Ok(Vec::new()),
                    "favourites" => (streams::twitch_query("channels", &json!(favourites))?, None),
                    "following" => return streams::twitch_followed(token.as_deref().unwrap_or_default()),
                    _ => {
                        // An exact name finds that channel too, first.
                        let mut cards = Vec::new();
                        if streams::valid_login(text.trim()) {
                            if let Ok(data) = streams::twitch(&streams::twitch_query("user", &json!(text.trim()))?, None) {
                                cards = streams::twitch_cards(&data);
                            }
                        }
                        let data = streams::twitch(&streams::twitch_query("search", &json!(text))?, None)?;
                        for c in streams::twitch_cards(&data) {
                            if !cards.iter().any(|x| x["login"] == c["login"]) {
                                cards.push(c);
                            }
                        }
                        return Ok(cards);
                    }
                };
                Ok(streams::twitch_cards(&streams::twitch(&body, token)?))
            })();
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                if obj.rust().twitch_request != request {
                    return;
                }
                match result {
                    Ok(cards) => {
                        let live = cards.iter().filter(|c| c["live"] == true).count();
                        let message = if view == "following" { format!("{live} live · {} followed", cards.len()) } else { format!("{live} live") };
                        obj.as_mut().set_twitch(q(&Value::Array(cards).to_string()));
                        obj.as_mut().set_twitch_state(q("ready"));
                        obj.set_twitch_message(q(&message));
                    }
                    Err(why) => {
                        obj.as_mut().set_twitch(q("[]"));
                        obj.as_mut().set_twitch_state(q("failed"));
                        obj.set_twitch_message(q(&why));
                    }
                }
            });
        });
    }

    fn load_youtube(mut self: Pin<&mut Self>, view: &QString, text: &QString) {
        let view = view.to_string();
        let text = text.to_string();
        if !matches!(view.as_str(), "game" | "subscriptions" | "channels" | "channel" | "search") {
            return;
        }
        self.as_mut().set_youtube_view(q(&view));
        if matches!(view.as_str(), "game" | "subscriptions" | "channels") {
            settings::change(|s| s.streams.youtube_view = view.clone());
        }
        if Self::demo_mode() {
            return;
        }
        if view == "channels" || (view == "search" && text.trim().is_empty()) {
            // The channel list (no request), or the search before anything is typed.
            if view == "channels" {
                let own = settings::read(|s| s.streams.channels.clone());
                self.as_mut().set_channels(q(&channels_json(&own)));
            }
            self.as_mut().rust_mut().youtube_request += 1;
            self.as_mut().set_youtube(q("[]"));
            self.as_mut().set_youtube_state(q("idle"));
            self.set_youtube_message(QString::default());
            return;
        }
        let (game, own) = settings::read(|s| (s.streams.game.youtube.clone(), s.streams.channels.clone()));
        let request = {
            let mut r = self.as_mut().rust_mut();
            r.youtube_request += 1;
            r.youtube_request
        };
        self.as_mut().set_youtube_state(q("loading"));
        self.as_mut().set_youtube_message(QString::default());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = (|| -> Result<Vec<Value>, String> {
                match view.as_str() {
                    "game" => streams::youtube_search(&game, true),
                    "search" => streams::youtube_search(&text, false),
                    "channel" => streams::youtube_feed(text.trim()),
                    _ => {
                        let mut ids: Vec<String> = own.iter().map(|c| c.id.clone()).collect();
                        for c in streams::freetube().unwrap_or_default() {
                            if !ids.contains(&c.id) {
                                ids.push(c.id);
                            }
                        }
                        if ids.is_empty() {
                            return Err("No channels yet: FreeTube's subscriptions show here, and channels you add with the star.".into());
                        }
                        ids.truncate(MAX_CHANNELS);
                        if let Some(kept) = kept_subscriptions(&ids) {
                            return Ok(kept);
                        }
                        let total = ids.len();
                        let progress = thread.clone();
                        let (all, failed) = fetch_feeds(ids.clone(), move |done, so_far| {
                            // What came so far shows while the rest loads.
                            let so_far = newest(so_far.to_vec());
                            let _ = progress.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                                if obj.rust().youtube_request != request {
                                    return;
                                }
                                obj.as_mut().set_youtube(q(&Value::Array(so_far).to_string()));
                                obj.set_youtube_message(q(&format!("{done} of {total} channels")));
                            });
                        });
                        if all.is_empty() {
                            return Err(failed.unwrap_or_else(|| "Nothing new.".into()));
                        }
                        let all = newest(all);
                        keep_subscriptions(&ids, &all);
                        Ok(all)
                    }
                }
            })();
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                if obj.rust().youtube_request != request {
                    return;
                }
                match result {
                    Ok(videos) => {
                        let n = videos.len();
                        obj.as_mut().set_youtube(q(&Value::Array(videos).to_string()));
                        obj.as_mut().set_youtube_state(q("ready"));
                        obj.set_youtube_message(q(&format!("{n} videos")));
                    }
                    Err(why) => {
                        obj.as_mut().set_youtube(q("[]"));
                        obj.as_mut().set_youtube_state(q("failed"));
                        obj.set_youtube_message(q(&why));
                    }
                }
            });
        });
    }

    fn choose_tab(self: Pin<&mut Self>, tab: &QString) {
        let tab = tab.to_string();
        if tab == "twitch" || tab == "youtube" || tab == "jellyfin" {
            settings::change(|s| s.streams.tab = tab.clone());
            self.set_tab(q(&tab));
        }
    }

    fn change_game(self: Pin<&mut Self>, name: &QString, twitch: &QString, youtube: &QString) {
        let clean = |s: &QString| s.to_string().trim().chars().filter(|c| !c.is_control()).take(80).collect::<String>();
        let preset = GamePreset { name: clean(name), twitch: clean(twitch), youtube: clean(youtube) };
        if preset.name.is_empty() {
            return;
        }
        let json = serde_json::to_string(&preset).unwrap_or_default();
        settings::change(|s| s.streams.game = preset);
        self.set_game(q(&json));
    }

    fn toggle_favourite(self: Pin<&mut Self>, login: &QString) {
        let login = login.to_string().to_ascii_lowercase();
        if !streams::valid_login(&login) {
            return;
        }
        let json = settings::change(|s| {
            let f = &mut s.streams.favourites;
            match f.iter().position(|l| *l == login) {
                Some(i) => {
                    f.remove(i);
                }
                None => f.push(login),
            }
            serde_json::to_string(f).unwrap_or_else(|_| "[]".into())
        });
        self.set_favourites(q(&json));
    }

    fn toggle_channel(self: Pin<&mut Self>, id: &QString, name: &QString) {
        let id = id.to_string();
        if !streams::valid_channel_id(&id) {
            return;
        }
        let name: String = name.to_string().trim().chars().take(100).collect();
        let own = settings::change(|s| {
            let c = &mut s.streams.channels;
            match c.iter().position(|x| x.id == id) {
                Some(i) => {
                    c.remove(i);
                }
                None => c.push(Channel { id, name }),
            }
            c.clone()
        });
        self.set_channels(q(&channels_json(&own)));
    }

    fn sign_in(mut self: Pin<&mut Self>, token: &QString) {
        let Some(token) = streams::twitch_token_of(&token.to_string()) else {
            self.set_account(q(&json!({ "streamlink": streams::streamlink_path().is_some(), "user": "", "error": "That is not a twitch.tv auth-token." }).to_string()));
            return;
        };
        self.as_mut().set_account(q(&account_json("…")));
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = streams::twitch_whoami(&token).and_then(|login| streams::save_twitch_token(Some(&token)).map(|_| login));
            let _ = thread.queue(move |obj: Pin<&mut qobject::Streams>| match result {
                Ok(login) => obj.set_account(q(&account_json(&login))),
                Err(why) => obj.set_account(q(&json!({ "streamlink": streams::streamlink_path().is_some(), "user": "", "error": why }).to_string())),
            });
        });
    }

    fn refresh_account(mut self: Pin<&mut Self>) {
        if Self::demo_mode() {
            return;
        }
        let Some(token) = streams::twitch_token() else {
            self.set_account(q(&account_json("")));
            return;
        };
        self.as_mut().set_account(q(&account_json("…")));
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = streams::twitch_whoami(&token);
            let _ = thread.queue(move |obj: Pin<&mut qobject::Streams>| match result {
                Ok(login) => obj.set_account(q(&account_json(&login))),
                // Offline or refused: the token stays; Settings says why.
                Err(why) => obj.set_account(q(&json!({ "streamlink": streams::streamlink_path().is_some(), "user": "?", "error": why }).to_string())),
            });
        });
    }

    fn sign_out(self: Pin<&mut Self>) {
        let _ = streams::save_twitch_token(None);
        self.set_account(q(&account_json("")));
    }

    fn save_quality(self: Pin<&mut Self>, quality: &QString) {
        let quality = quality.to_string();
        if quality == "audio" || quality == "best" || quality.parse::<u32>().is_ok_and(|h| (144..=2160).contains(&h)) {
            settings::change(|s| s.streams.quality = quality.clone());
            self.set_quality(q(&quality));
        }
    }

    fn save_grid(self: Pin<&mut Self>, grid: bool) {
        settings::change(|s| s.streams.grid = grid);
        self.set_grid(grid);
    }

    fn save_hwdec(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.hwdec = on);
        self.set_hwdec(on);
    }

    fn opacity_of(&self, slot: &QString) -> i32 {
        let slot = slot.to_string();
        settings::read(|s| s.streams.video_opacity.get(&slot).copied()).map_or(100, |p| i32::from(p.clamp(50, 100)))
    }

    fn save_opacity(self: Pin<&mut Self>, slot: &QString, percent: i32) {
        let slot = slot.to_string();
        if slot == "twitch" || slot == "youtube" {
            let p = percent.clamp(50, 100) as u8;
            settings::change(|s| s.streams.video_opacity.insert(slot.clone(), p));
        }
    }

    fn set_sponsor_enabled(self: Pin<&mut Self>, enabled: bool) {
        let json = settings::change(|s| {
            s.streams.sponsorblock.enabled = enabled;
            serde_json::to_string(&s.streams.sponsorblock).unwrap_or_default()
        });
        self.set_sponsorblock(q(&json));
    }

    fn set_sponsor_mode(self: Pin<&mut Self>, category: &QString, mode: &QString) {
        let (category, mode) = (category.to_string(), mode.to_string());
        if !sponsorblock::CATEGORIES.contains(&category.as_str()) || !matches!(mode.as_str(), "skip" | "show" | "off") {
            return;
        }
        let json = settings::change(|s| {
            s.streams.sponsorblock.categories.insert(category.clone(), mode.clone());
            serde_json::to_string(&s.streams.sponsorblock).unwrap_or_default()
        });
        self.set_sponsorblock(q(&json));
    }

    fn sponsor_from_freetube(self: Pin<&mut Self>) -> QString {
        let Some(taken) = sponsorblock::from_freetube() else {
            return q("FreeTube's SponsorBlock settings were not found.");
        };
        let json = serde_json::to_string(&taken).unwrap_or_default();
        settings::change(|s| s.streams.sponsorblock = taken);
        self.set_sponsorblock(q(&json));
        q("Taken from FreeTube.")
    }

    fn load_segments(self: Pin<&mut Self>, slot: &QString, id: &QString) {
        let (slot, id) = (slot.to_string(), id.to_string());
        let sb = settings::read(|s| s.streams.sponsorblock.clone());
        if !sb.enabled || Self::demo_mode() {
            return;
        }
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            // Unreachable or refused: the video plays as it is.
            let list = sponsorblock::segments(&id, &sb).unwrap_or_default();
            let list: Vec<Value> = list
                .into_iter()
                .map(|mut v| {
                    let mode = sb.mode(v["category"].as_str().unwrap_or("")).to_string();
                    v["mode"] = json!(mode);
                    v
                })
                .collect();
            let text = Value::Array(list).to_string();
            let _ = thread.queue(move |obj: Pin<&mut qobject::Streams>| obj.segments_loaded(q(&slot), q(&id), q(&text)));
        });
    }

    fn forget(self: Pin<&mut Self>) {
        *subscriptions_kept().lock().unwrap_or_else(|p| p.into_inner()) = None;
    }

    fn save_volume(self: Pin<&mut Self>, volume: i32) {
        let v = volume.clamp(0, 100);
        settings::change(|s| s.streams.volume = v as u8);
        self.set_volume(v);
    }

    fn source(self: Pin<&mut Self>, slot: &QString, kind: &QString, id: &QString, quality: &QString) -> QString {
        let (slot, kind, id, quality) = (slot.to_string(), kind.to_string(), id.to_string(), quality.to_string());
        let url = match streams::stream_url(&kind, &id) {
            Ok(u) => u,
            Err(e) => return q(&json!({ "error": e }).to_string()),
        };
        if kind == "twitch" && streams::streamlink_path().is_some() {
            let thread = self.qt_thread();
            let failed_slot = slot.clone();
            return match streams::streamlink_start(&slot, &url, &quality, move |why| {
                let _ = thread.queue(move |obj: Pin<&mut qobject::Streams>| {
                    obj.source_failed(q(&failed_slot), q(&format!("Streamlink: {why}")));
                });
            }) {
                Ok(pipe) => q(&json!({ "url": pipe, "format": "", "via": "streamlink" }).to_string()),
                Err(e) => q(&json!({ "error": e }).to_string()),
            };
        }
        streams::streamlink_stop(&slot);
        q(&json!({ "url": url, "format": streams::ytdl_format(&quality), "via": "yt-dlp" }).to_string())
    }

    fn stop_source(&self, slot: &QString) {
        streams::streamlink_stop(&slot.to_string());
    }

    fn video_id(&self, text: &QString) -> QString {
        q(&streams::video_id_of(&text.to_string()).unwrap_or_default())
    }
}
