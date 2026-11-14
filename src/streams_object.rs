//! The Streams panel's lists for QML: Twitch and YouTube, loaded in the
//! background; the running game's preset; favourites and channels; the
//! Twitch sign-in; and the address a video player plays.

use std::pin::Pin;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
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
        /// YouTube channels' pictures: JSON `{channel id: address}` ("" =
        /// the channel has none).
        #[qproperty(QString, channel_pictures)]
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
        /// Videos made louder by this many dB (0, 3, 6, 9).
        #[qproperty(i32, video_boost)]
        /// Videos' quiet and loud passages evened out.
        #[qproperty(bool, even_loudness)]
        /// YouTube lists: what is left out. JSON `{"shorts", "watched",
        /// "channels": [{id, name}], "words": [..]}`.
        #[qproperty(QString, filters)]
        /// The subscriptions' groups (JSON list of names) and the one shown
        /// ("" all).
        #[qproperty(QString, groups)]
        #[qproperty(QString, group)]
        /// FreeTube's subscriptions are still read from its file.
        #[qproperty(bool, freetube_live)]
        /// The YouTube search's filter: JSON `{"sort", "date", "length"}`.
        #[qproperty(QString, search_filter)]
        /// The Trending tab's part ("gaming", "europe", "national", "tr", ...)
        /// and each part's search words: JSON `{part: [words]}`.
        #[qproperty(QString, trend_section)]
        #[qproperty(QString, trend_words)]
        /// The video languages chosen: JSON `["de", …]`.
        #[qproperty(QString, video_languages)]
        /// Twitch: live notes on, and the channels left out (JSON list).
        #[qproperty(bool, alerts)]
        #[qproperty(QString, alerts_off)]
        /// Channels that went live since the Twitch tab was last looked at:
        /// JSON `[{login, name, title, game, at}]` (newest first), and how many.
        #[qproperty(QString, live_news)]
        #[qproperty(i32, live_new_count)]
        /// Twitch lists: JSON `{"languages": [..], "reruns": bool, "sort"}`.
        #[qproperty(QString, twitch_filter)]
        /// The Twitch list has another page, and it is being loaded.
        #[qproperty(bool, twitch_has_more)]
        #[qproperty(bool, twitch_loading_more)]
        /// Why the last "Load more" brought nothing ("" it did).
        #[qproperty(QString, twitch_more_note)]
        /// The same for the YouTube list.
        #[qproperty(bool, youtube_has_more)]
        #[qproperty(bool, youtube_loading_more)]
        #[qproperty(QString, youtube_more_note)]
        /// Twitch chat beside the Twitch video, and writing in it.
        #[qproperty(bool, chat_open)]
        #[qproperty(bool, chat_write)]
        #[qproperty(bool, chat_docked)]
        type Streams = super::StreamsRust;

        /// Loads a Twitch list: "game", "following", "favourites", "live" or "search" (with `text`).
        #[qinvokable]
        fn load_twitch(self: Pin<&mut Streams>, view: &QString, text: &QString);

        /// Loads a YouTube list: "game", "subscriptions", "channel" (`text` its id) or "search".
        #[qinvokable]
        fn load_youtube(self: Pin<&mut Streams>, view: &QString, text: &QString);

        /// The Twitch list's next page, added at its end (scrolled to the
        /// end, or "Load more").
        #[qinvokable]
        fn load_more_twitch(self: Pin<&mut Streams>);
        /// The YouTube list's next page (searches, Trending, the game's,
        /// a channel's older videos, more subscriptions).
        #[qinvokable]
        fn load_more_youtube(self: Pin<&mut Streams>);

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

        /// Asks the pictures of channels that have none yet (once each,
        /// FreeTube's first, then yt-dlp, a few at a time, in the background).
        #[qinvokable]
        fn fetch_channel_pictures(self: Pin<&mut Streams>);

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

        /// Settings → Streams → Videos "Video loudness".
        #[qinvokable]
        fn save_video_boost(self: Pin<&mut Streams>, db: i32);

        /// Settings → Streams → Videos "Even out loudness".
        #[qinvokable]
        fn save_even_loudness(self: Pin<&mut Streams>, on: bool);

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

        /// Leaves Shorts out of the YouTube lists, or not.
        #[qinvokable]
        fn set_hide_shorts(self: Pin<&mut Streams>, on: bool);
        #[qinvokable]
        fn set_hide_watched(self: Pin<&mut Streams>, on: bool);
        /// Leaves videos in Indian scripts out, or not.
        #[qinvokable]
        fn set_hide_indian(self: Pin<&mut Streams>, on: bool);
        /// A channel's videos never show (switched).
        #[qinvokable]
        fn toggle_hidden_channel(self: Pin<&mut Streams>, id: &QString, name: &QString);
        /// Words whose videos never show, separated by commas.
        #[qinvokable]
        fn set_hidden_words(self: Pin<&mut Streams>, text: &QString);
        /// Shows one subscriptions group ("" all).
        #[qinvokable]
        fn choose_group(self: Pin<&mut Streams>, group: &QString);
        /// Puts a kept channel into a group or takes it out (switched); a new
        /// name makes the group.
        #[qinvokable]
        fn toggle_channel_group(self: Pin<&mut Streams>, id: &QString, group: &QString);
        /// Takes over FreeTube: its subscriptions (with their groups), its
        /// playlists and history; after it FreeTube's file is no longer read.
        /// Runs in the background ("Taking over…"); `freetube_taken` says
        /// what came.
        #[qinvokable]
        fn take_freetube(self: Pin<&mut Streams>) -> QString;
        /// FreeTube was taken over: what came.
        #[qsignal]
        fn freetube_taken(self: Pin<&mut Streams>, note: QString);
        /// The search's filter: one of "sort", "date", "length" and its value.
        #[qinvokable]
        fn change_search_filter(self: Pin<&mut Streams>, key: &QString, value: &QString);
        /// A Trending part's search words, separated by commas ("" = the default).
        #[qinvokable]
        fn change_trend_words(self: Pin<&mut Streams>, section: &QString, text: &QString);
        /// Takes a video language in or out ("de", "tr", …; see
        /// `streams::VIDEO_LANGUAGES`).
        #[qinvokable]
        fn toggle_video_language(self: Pin<&mut Streams>, code: &QString);
        #[qinvokable]
        fn switch_alerts(self: Pin<&mut Streams>, on: bool);
        /// Leaves a channel out of the live notes, or takes it in again.
        #[qinvokable]
        fn toggle_alert(self: Pin<&mut Streams>, login: &QString);
        /// The live notes were seen: the count goes back to 0.
        #[qinvokable]
        fn seen_news(self: Pin<&mut Streams>);
        /// The quality last chosen for a Twitch channel ("" none).
        #[qinvokable]
        fn quality_for(self: &Streams, login: &QString) -> QString;
        #[qinvokable]
        fn save_channel_quality(self: Pin<&mut Streams>, login: &QString, quality: &QString);
        /// Twitch's filter: "languages" (comma separated codes), "reruns"
        /// ("on"/"off") or "sort" ("viewers"/"new").
        #[qinvokable]
        fn change_twitch_filter(self: Pin<&mut Streams>, key: &QString, value: &QString);
        /// At the start: the live notes begin if they are on.
        #[qinvokable]
        fn begin(self: Pin<&mut Streams>);
        /// Shows or hides the chat beside the Twitch video (kept).
        #[qinvokable]
        fn save_chat_open(self: Pin<&mut Streams>, on: bool);
        #[qinvokable]
        fn save_chat_write(self: Pin<&mut Streams>, on: bool);
        #[qinvokable]
        fn save_chat_docked(self: Pin<&mut Streams>, on: bool);
        /// The chat's sign-in: JSON `{"user", "token"}` when signed in to
        /// Twitch and writing is on, else `{}` (reading only). The token goes
        /// only to Twitch's chat server.
        #[qinvokable]
        fn chat_auth(self: &Streams) -> QString;
        /// A chat's 7TV and BTTV emotes (by the channel's Twitch id), in the
        /// background: `emotes_loaded`.
        #[qinvokable]
        fn load_emotes(self: Pin<&mut Streams>, room: &QString);
        /// JSON `{name: picture}`.
        #[qsignal]
        fn emotes_loaded(self: Pin<&mut Streams>, room: QString, emotes: QString);

        /// A channel went live (live notes on).
        #[qsignal]
        fn went_live(self: Pin<&mut Streams>, name: QString, title: QString);

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
    channel_pictures: QString,
    account: QString,
    quality: QString,
    volume: i32,
    grid: bool,
    sponsorblock: QString,
    hwdec: bool,
    video_boost: i32,
    even_loudness: bool,
    filters: QString,
    groups: QString,
    group: QString,
    freetube_live: bool,
    search_filter: QString,
    trend_section: QString,
    trend_words: QString,
    alerts: bool,
    alerts_off: QString,
    live_news: QString,
    live_new_count: i32,
    twitch_filter: QString,
    chat_open: bool,
    chat_write: bool,
    chat_docked: bool,
    twitch_request: u64,
    youtube_request: u64,
    video_languages: QString,
    /// The list shown and where its next page starts.
    twitch_more: Option<(String, String, Value)>,
    twitch_has_more: bool,
    twitch_loading_more: bool,
    twitch_more_note: QString,
    youtube_has_more: bool,
    youtube_loading_more: bool,
    youtube_more_note: QString,
    /// The YouTube list shown and how many pages of it came.
    youtube_more: Option<(String, String, usize)>,
}

fn q(s: &str) -> QString {
    QString::from(s)
}

/// The subscribed channels: kept here, then FreeTube's (while read live).
fn all_channels(s: &settings::StreamsSettings) -> Vec<(Channel, bool)> {
    let mut list: Vec<(Channel, bool)> = s.channels.iter().map(|c| (c.clone(), false)).collect();
    if s.freetube_live {
        for c in streams::freetube().unwrap_or_default() {
            if !s.channels.iter().any(|o| o.id == c.id) {
                list.push((c, true));
            }
        }
    }
    list
}

fn channels_json(s: &settings::StreamsSettings) -> String {
    Value::Array(all_channels(s).into_iter().map(|(c, ft)| json!({ "id": c.id, "name": c.name, "groups": c.groups, "freetube": ft })).collect()).to_string()
}

fn pictures_json(s: &settings::StreamsSettings) -> String {
    serde_json::to_string(&s.channel_pictures).unwrap_or_else(|_| "{}".into())
}

/// Channels whose picture was asked in this run (a failed one is asked again
/// at the next start, not over and over).
fn pictures_asked() -> &'static Mutex<std::collections::HashSet<String>> {
    static ASKED: OnceLock<Mutex<std::collections::HashSet<String>>> = OnceLock::new();
    ASKED.get_or_init(Default::default)
}

/// yt-dlp asks for this many channel pictures at once.
const PICTURES_AT_ONCE: usize = 3;

fn groups_json(s: &settings::StreamsSettings) -> String {
    let mut names: Vec<String> = Vec::new();
    for (c, _) in all_channels(s) {
        for g in c.groups {
            if !names.contains(&g) {
                names.push(g);
            }
        }
    }
    names.sort_by_key(|n| n.to_lowercase());
    serde_json::to_string(&names).unwrap_or_else(|_| "[]".into())
}

fn filters_json(s: &settings::StreamsSettings) -> String {
    json!({ "shorts": s.hide_shorts, "watched": s.hide_watched, "channels": s.hidden_channels, "words": s.hidden_words, "indian": s.hide_indian }).to_string()
}

fn trend_words_json(s: &settings::StreamsSettings) -> String {
    let mut m = serde_json::Map::new();
    for part in streams::TREND_SECTIONS {
        m.insert(part.into(), json!(s.trend_words.get(part).cloned().unwrap_or_else(|| streams::trend_words(part))));
    }
    Value::Object(m).to_string()
}

fn twitch_filter_json(s: &settings::StreamsSettings) -> String {
    json!({ "languages": s.languages, "reruns": s.hide_reruns, "sort": s.twitch_sort }).to_string()
}

/// What the YouTube lists leave out, applied: (kept, how many left out).
pub fn filter_videos(list: Vec<Value>, s: &settings::StreamsSettings) -> (Vec<Value>, usize) {
    let words: Vec<String> = s.hidden_words.iter().map(|w| w.to_lowercase()).filter(|w| !w.is_empty()).collect();
    let before = list.len();
    let kept: Vec<Value> = list
        .into_iter()
        .filter(|v| {
            if s.hide_shorts && v["short"] == true {
                return false;
            }
            let cid = v["channelId"].as_str().unwrap_or("");
            let cname = v["channel"].as_str().unwrap_or("");
            if s.hidden_channels.iter().any(|c| (!cid.is_empty() && c.id == cid) || (cid.is_empty() && !cname.is_empty() && c.name == cname)) {
                return false;
            }
            if s.hide_indian && (streams::indian_script(v["title"].as_str().unwrap_or("")) || streams::indian_script(cname)) {
                return false;
            }
            let title = v["title"].as_str().unwrap_or("").to_lowercase();
            if words.iter().any(|w| title.contains(w.as_str())) {
                return false;
            }
            if s.hide_watched && crate::library::read(|l| l.watched(v["id"].as_str().unwrap_or(""))) {
                return false;
            }
            true
        })
        .collect();
    let gone = before - kept.len();
    (kept, gone)
}

thread_local! {
    /// How the last Twitch list of this thread was asked (said under the
    /// list when a page brought nothing new).
    static TWITCH_WAY: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
}

fn say_way(way: String) {
    TWITCH_WAY.with(|w| *w.borrow_mut() = way);
}

fn last_way() -> String {
    TWITCH_WAY.with(|w| w.borrow().clone())
}

/// All live's page `p` without a cursor: the streams of the most watched
/// categories `p * SWEEP + 1` on (see `streams::SWEEP`).
fn sweep_page(p: usize, st: &settings::StreamsSettings) -> Result<(Vec<Value>, Value), String> {
    let n = (p + 1) * streams::SWEEP;
    if n > streams::SWEEP_LONGEST {
        return Ok((Vec::new(), json!({})));
    }
    let cats = streams::twitch_categories(&streams::twitch(&streams::twitch_query_page("categories", &Value::Null, None, Some(n))?, None)?);
    let names: Vec<String> = cats.iter().skip(p * streams::SWEEP).take(streams::SWEEP).filter_map(|c| c["name"].as_str().map(str::to_string)).collect();
    if names.is_empty() {
        return Ok((Vec::new(), json!({})));
    }
    let filtered = !st.languages.is_empty() || st.hide_reruns;
    let asked = if filtered {
        match streams::twitch(&streams::twitch_sweep_query(&names, true)?, None) {
            Ok(data) if data.get("_errors").is_none() => Ok(data),
            _ => streams::twitch(&streams::twitch_sweep_query(&names, false)?, None),
        }
    } else {
        streams::twitch(&streams::twitch_sweep_query(&names, false)?, None)
    };
    let data = asked?;
    say_way(format!("categories {} to {}", p * streams::SWEEP + 1, p * streams::SWEEP + names.len()));
    let next = if names.len() == streams::SWEEP && n < streams::SWEEP_LONGEST { json!({ "sweep": p + 1 }) } else { json!({}) };
    Ok((filter_cards(streams::sweep_cards(&data), st), next))
}

/// A Twitch list, from its page cursors on (`more`, as the last page gave
/// them; None: the first page): its cards (filtered as set) and where the
/// next page starts (`{}` when there is none; one cursor per part).
fn fetch_twitch(view: &str, text: &str, st: &settings::StreamsSettings, token: Option<&str>, more: Option<&Value>) -> Result<(Vec<Value>, Value), String> {
    say_way(String::new());
    if view == "live" {
        if let Some(p) = more.and_then(|m| m.get("sweep")).and_then(Value::as_u64) {
            return sweep_page(p as usize, st);
        }
    }
    let cursor = |k: &str| more.and_then(|m| m.get(k)).and_then(Value::as_str).map(str::to_string);
    // A longer list from the top instead of a cursor (`{"first": n}`), and
    // the next one's length while there may be more.
    let first = more.and_then(|m| m.get("first")).and_then(Value::as_u64).map(|n| n as usize);
    let mut next = serde_json::Map::new();
    let longer = |got: usize, next: &mut serde_json::Map<String, Value>| {
        if let Some(n) = first {
            if got >= n.saturating_sub(5) && n < streams::TWITCH_LONGEST {
                next.insert("first".into(), json!((n + 30).min(streams::TWITCH_LONGEST)));
            }
        }
    };
    let filtered = !st.languages.is_empty() || st.hide_reruns;
    // Live lists: with the stream's kind and language while a filter is on
    // (plain if Twitch refuses those fields).
    let mut live = |game: Value| -> Result<Vec<Value>, String> {
        let after = cursor("live");
        let page = |data: &Value, next: &mut serde_json::Map<String, Value>| {
            let at = if game.is_null() { "/streams" } else { "/game/streams" };
            if first.is_some() {
                let got = data.pointer(&format!("{at}/edges")).and_then(Value::as_array).map_or(0, Vec::len);
                longer(got, next);
            } else if let Some(c) = streams::next_cursor(data, at) {
                next.insert("live".into(), json!(c));
            }
        };
        // All live: Twitch's own directory query first (the only one it
        // pages); the written-out query if none of its ids answers.
        if game.is_null() {
            match streams::twitch_browse(after.as_deref(), first) {
                Ok(data) => {
                    say_way("directory query".into());
                    page(&data, &mut next);
                    return Ok(streams::twitch_cards(&data));
                }
                Err(why) => say_way(format!("written-out query; directory query: {}", why.chars().take(80).collect::<String>())),
            }
        }
        // Sorted by viewers first; the fields for the filters while one is
        // on; plain if Twitch refuses either.
        let kinds: &[&str] = if filtered { &["liveMoreSorted", "liveSorted", "liveMore", "live"] } else { &["liveSorted", "live"] };
        let (last, tries) = kinds.split_last().unwrap_or((&"live", &[]));
        for kind in tries {
            if let Ok(data) = streams::twitch(&streams::twitch_query_page(kind, &game, after.as_deref(), first)?, None) {
                if data.get("_errors").is_none() {
                    page(&data, &mut next);
                    return Ok(streams::twitch_cards(&data));
                }
            }
        }
        let data = streams::twitch(&streams::twitch_query_page(last, &game, after.as_deref(), first)?, None)?;
        page(&data, &mut next);
        Ok(streams::twitch_cards(&data))
    };
    let cards = match view {
        "game" => live(json!(st.game.twitch))?,
        "category" => live(json!(text))?,
        "live" => live(Value::Null)?,
        "categories" if text.trim().is_empty() => {
            let data = streams::twitch(&streams::twitch_query_page("categories", &Value::Null, cursor("live").as_deref(), first)?, None)?;
            if first.is_some() {
                longer(data.pointer("/games/edges").and_then(Value::as_array).map_or(0, Vec::len), &mut next);
            } else if let Some(c) = streams::next_cursor(&data, "/games") {
                next.insert("live".into(), json!(c));
            }
            streams::twitch_categories(&data)
        }
        "categories" => streams::twitch_categories(&streams::twitch(&streams::twitch_query("searchCategories", &json!(text))?, None)?),
        "recordings" => {
            // Past broadcasts and clips: each on its own, so one refused
            // leaves the other; a later page asks only the parts with more.
            let mut out = Vec::new();
            let mut failed = None;
            for (k, at) in [("videos", "/user/videos"), ("clips", "/user/clips")] {
                let after = cursor(k);
                if more.is_some() && after.is_none() {
                    continue;
                }
                match streams::twitch(&streams::twitch_query_after(k, &json!(text), after.as_deref())?, None) {
                    Ok(data) => {
                        if let Some(c) = streams::next_cursor(&data, at) {
                            next.insert(k.into(), json!(c));
                        }
                        out.extend(streams::twitch_recordings(&data));
                    }
                    Err(e) => failed = Some(e),
                }
            }
            match failed {
                Some(e) if out.is_empty() => return Err(e),
                _ => out,
            }
        }
        "favourites" if st.favourites.is_empty() => Vec::new(),
        "favourites" => streams::twitch_cards(&streams::twitch(&streams::twitch_query("channels", &json!(st.favourites))?, None)?),
        "following" => streams::twitch_followed(token.unwrap_or_default())?,
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
            cards
        }
    };
    let cards = if matches!(view, "categories" | "recordings") { cards } else { filter_cards(cards, st) };
    Ok((cards, Value::Object(next)))
}

/// What tells a Twitch card from another (channels, categories, videos).
fn card_key(c: &Value) -> String {
    format!("{}{}{}", c["login"].as_str().unwrap_or(""), c["name"].as_str().unwrap_or(""), c["id"].as_str().unwrap_or(""))
}

/// Twitch's filters applied to live cards, and the order.
pub fn filter_cards(mut cards: Vec<Value>, s: &settings::StreamsSettings) -> Vec<Value> {
    let langs: Vec<String> = s.languages.iter().map(|l| l.to_ascii_lowercase()).collect();
    cards.retain(|c| {
        if s.hide_reruns && c["rerun"] == true {
            return false;
        }
        let lang = c["language"].as_str().unwrap_or("");
        langs.is_empty() || lang.is_empty() || c["live"] != true || langs.iter().any(|l| l == lang)
    });
    if s.twitch_sort == "new" {
        cards.sort_by(|a, b| b["live"].as_bool().cmp(&a["live"].as_bool()).then(b["since"].as_str().cmp(&a["since"].as_str())));
    }
    cards
}

/// At most this many channels' feeds make the subscriptions.
const MAX_CHANNELS: usize = 120;
/// Feeds asked at once.
const FEEDS_AT_ONCE: usize = 8;
/// How long loaded subscriptions are kept (the refresh button asks again).
const KEEP_SUBSCRIPTIONS: Duration = Duration::from_secs(15 * 60);

type Kept = Option<(Instant, Vec<String>, Vec<Value>)>;

/// Which live-notes thread may go on (a new one, or none when switched off).
static ALERTS_RUN: AtomicU64 = AtomicU64::new(0);

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
fn newest(all: Vec<Value>) -> Vec<Value> {
    newest_of(all, 60)
}

fn newest_of(mut all: Vec<Value>, n: usize) -> Vec<Value> {
    all.sort_by(|a, b| b["published"].as_str().cmp(&a["published"].as_str()));
    all.truncate(n);
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
            channels: q(&channels_json(&s)),
            channel_pictures: q(&pictures_json(&s)),
            // Who is signed in is asked of Twitch once the panel opens.
            account: q(&account_json(if streams::twitch_token().is_some() { "…" } else { "" })),
            quality: q(&s.quality),
            volume: i32::from(s.volume),
            grid: s.grid,
            sponsorblock: q(&serde_json::to_string(&s.sponsorblock).unwrap_or_default()),
            hwdec: s.hwdec,
            video_boost: i32::from(s.video_boost),
            even_loudness: s.even_loudness,
            filters: q(&filters_json(&s)),
            groups: q(&groups_json(&s)),
            group: q(&s.group),
            freetube_live: s.freetube_live,
            search_filter: q(&serde_json::to_string(&s.search).unwrap_or_default()),
            trend_section: q(&s.trend_section),
            trend_words: q(&trend_words_json(&s)),
            video_languages: q(&serde_json::to_string(&s.video_languages).unwrap_or_else(|_| "[]".into())),
            alerts: s.alerts,
            alerts_off: q(&serde_json::to_string(&s.alerts_off).unwrap_or_else(|_| "[]".into())),
            live_news: q("[]"),
            live_new_count: 0,
            twitch_filter: q(&twitch_filter_json(&s)),
            chat_open: s.chat_open || demo.contains("chat"),
            chat_write: s.chat_write,
            chat_docked: s.chat_docked,
            twitch_request: 0,
            twitch_more: None,
            twitch_has_more: demo.contains("more"),
            twitch_loading_more: false,
            twitch_more_note: QString::default(),
            youtube_has_more: false,
            youtube_loading_more: false,
            youtube_more_note: QString::default(),
            youtube_more: None,
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
        // GC_DEMO=streams,youtube,yt-<view> or streams,tw-<view>: that list.
        for part in demo.split(',') {
            if let Some(v) = part.strip_prefix("yt-") {
                self.tab = q("youtube");
                self.youtube_view = q(v);
                if v == "trending" {
                    self.trend_section = q("tr");
                }
            }
            if let Some(v) = part.strip_prefix("tw-") {
                self.tab = q("twitch");
                self.twitch_view = q(v);
                if v == "categories" {
                    let c: Vec<Value> = [("Just Chatting", 312_000), ("Path of Exile 2", 48_000), ("AION 2", 21_000), ("Lost Ark", 9_000), ("Sim Racing", 4_000), ("Music", 3_000)]
                        .iter()
                        .map(|(n, v)| json!({ "name": n, "title": n, "viewers": v, "picture": "" }))
                        .collect();
                    self.twitch = q(&Value::Array(c).to_string());
                }
                if v == "recordings" {
                    let r: Vec<Value> = (0..4)
                        .map(|i| json!({ "kind": if i == 3 { "clip" } else { "vod" }, "id": format!("10{i}"), "title": format!("Raid night part {}", i + 1),
                            "length": 3600 + i * 900, "published": "2026-11-11T20:00:00Z", "views": 1200 - i * 100, "picture": "", "game": "AION 2" }))
                        .collect();
                    self.twitch = q(&Value::Array(r).to_string());
                }
            }
        }
        if demo.contains("news") {
            self.alerts = true;
            self.live_news = q(&json!([{ "login": "streamer_two", "name": "streamer_two", "title": "Raid night, come along", "game": "AION 2", "at": 0 }]).to_string());
            self.live_new_count = 1;
        }
        if demo.contains("groups") {
            self.groups = q("[\"Gaming\",\"Tech\"]");
            self.channels = q(&json!([{ "id": "UCaaaaaaaaaaaaaaaaaaaaaa", "name": "channel_name", "groups": ["Gaming"], "freetube": false },
                { "id": "UCbbbbbbbbbbbbbbbbbbbbbb", "name": "another_channel", "groups": ["Tech"], "freetube": false }]).to_string());
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
        if !matches!(view.as_str(), "game" | "following" | "favourites" | "live" | "search" | "categories" | "category" | "recordings") {
            return;
        }
        // Another kind of list (categories, recordings, channels): the old
        // one goes at once, so no row reads fields it lacks.
        let kind = |v: &str| match v {
            "categories" => 1,
            "recordings" => 2,
            _ => 0,
        };
        if kind(&view) != kind(&self.as_ref().twitch_view().to_string()) {
            self.as_mut().set_twitch(q("[]"));
        }
        self.as_mut().set_twitch_view(q(&view));
        // A new list: no next page until it says so.
        self.as_mut().rust_mut().twitch_more = None;
        let demo_more = Self::demo_mode() && std::env::var("GC_DEMO").is_ok_and(|d| d.contains("more"));
        self.as_mut().set_twitch_has_more(demo_more);
        self.as_mut().set_twitch_loading_more(false);
        self.as_mut().set_twitch_more_note(QString::default());
        if !matches!(view.as_str(), "search" | "category" | "recordings") {
            settings::change(|s| s.streams.twitch_view = view.clone());
        }
        if view == "following" || view == "favourites" {
            self.as_mut().seen_news();
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
        let st = settings::read(|s| s.streams.clone());
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
            let result = fetch_twitch(&view, &text, &st, token.as_deref(), None);
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                if obj.rust().twitch_request != request {
                    return;
                }
                let has_more = matches!(&result, Ok((_, more)) if more.as_object().is_some_and(|m| !m.is_empty()));
                obj.as_mut().rust_mut().twitch_more = match &result {
                    Ok((_, more)) if has_more => Some((view.clone(), text.clone(), more.clone())),
                    _ => None,
                };
                obj.as_mut().set_twitch_has_more(has_more);
                obj.as_mut().set_twitch_loading_more(false);
                match result.map(|(cards, _)| cards) {
                    Ok(cards) => {
                        let live = cards.iter().filter(|c| c["live"] == true).count();
                        let message = match view.as_str() {
                            "following" => format!("{live} live · {} followed", cards.len()),
                            "categories" => format!("{} categories", cards.len()),
                            "recordings" => format!("{} videos", cards.len()),
                            _ => format!("{live} live"),
                        };
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

    fn load_more_twitch(mut self: Pin<&mut Self>) {
        if *self.twitch_loading_more() || Self::demo_mode() {
            return;
        }
        let Some((view, text, more)) = self.rust().twitch_more.clone() else { return };
        if view != self.twitch_view().to_string() {
            return;
        }
        let request = self.rust().twitch_request;
        self.as_mut().set_twitch_loading_more(true);
        self.as_mut().set_twitch_more_note(QString::default());
        let st = settings::read(|s| s.streams.clone());
        let shown: Vec<Value> = serde_json::from_str(&self.twitch().to_string()).unwrap_or_default();
        let known: std::collections::HashSet<String> = shown.iter().map(card_key).collect();
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let mut result = fetch_twitch(&view, &text, &st, None, Some(&more));
            let mut ways = vec![last_way()];
            let nothing_new = |r: &Result<(Vec<Value>, Value), String>| match r {
                Ok((cards, _)) => cards.iter().all(|c| known.contains(&card_key(c))),
                Err(_) => true,
            };
            // Twitch may send the first page again for a cursor (MN's
            // 0.7.7): then ask for a longer list from the top instead.
            let pages = matches!(view.as_str(), "game" | "category" | "live" | "categories");
            if pages && more.get("first").is_none() && more.get("sweep").is_none() && result.is_ok() && nothing_new(&result) {
                let n = (known.len() + 30).min(streams::TWITCH_LONGEST);
                if n > known.len() {
                    result = fetch_twitch(&view, &text, &st, None, Some(&json!({ "first": n })));
                    ways.push(format!("longer list: {}", last_way()));
                }
            }
            // All live still the same (MN's 0.8.12): the streams of the most
            // watched categories, a few categories a page, until new ones come.
            if view == "live" {
                let mut tries = 0;
                while nothing_new(&result) && tries < 3 {
                    let p = match &result {
                        Ok((_, next)) => next.get("sweep").and_then(Value::as_u64),
                        Err(_) => None,
                    };
                    let p = match p {
                        Some(p) => p,
                        None if tries == 0 && more.get("sweep").is_none() => 0,
                        None => break,
                    };
                    let swept = fetch_twitch(&view, &text, &st, None, Some(&json!({ "sweep": p })));
                    ways.push(match &swept {
                        Ok(_) => last_way(),
                        Err(e) => format!("categories: {e}"),
                    });
                    // A failed sweep keeps what the cursor brought.
                    if swept.is_ok() || result.is_err() {
                        result = swept;
                    }
                    tries += 1;
                }
            }
            let ways: Vec<String> = ways.into_iter().filter(|w| !w.is_empty()).collect();
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                // Another list came meanwhile: this page is not its.
                if obj.rust().twitch_request != request {
                    return;
                }
                obj.as_mut().set_twitch_loading_more(false);
                let (cards, next) = match result {
                    Ok(r) => r,
                    Err(why) => {
                        // Said under the list: the button tries again.
                        obj.set_twitch_more_note(q(&format!("Twitch gave no more: {why}")));
                        return;
                    }
                };
                let mut all: Vec<Value> = serde_json::from_str(&obj.twitch().to_string()).unwrap_or_default();
                let before = all.len();
                for c in cards {
                    if !all.iter().any(|x| card_key(x) == card_key(&c)) {
                        all.push(c);
                    }
                }
                // Twitch answered without anything new: say so, not nothing.
                let note = match (all.len() == before, ways.is_empty()) {
                    (false, _) => String::new(),
                    (true, true) => "Twitch sent nothing new (the filters may leave everything out).".into(),
                    (true, false) => format!("Twitch sent nothing new ({}). The filters may leave everything out.", ways.join("; ")),
                };
                obj.as_mut().set_twitch_more_note(q(&note));
                let has_more = next.as_object().is_some_and(|m| !m.is_empty());
                obj.as_mut().rust_mut().twitch_more = has_more.then(|| (view.clone(), text.clone(), next));
                obj.as_mut().set_twitch_has_more(has_more);
                let live = all.iter().filter(|c| c["live"] == true).count();
                let message = match view.as_str() {
                    "categories" => format!("{} categories", all.len()),
                    "recordings" => format!("{} videos", all.len()),
                    _ => format!("{live} live"),
                };
                obj.as_mut().set_twitch(q(&Value::Array(all).to_string()));
                obj.set_twitch_message(q(&message));
            });
        });
    }

    fn load_more_youtube(mut self: Pin<&mut Self>) {
        if *self.youtube_loading_more() || Self::demo_mode() {
            return;
        }
        let Some((view, text, page)) = self.rust().youtube_more.clone() else { return };
        if view != self.youtube_view().to_string() {
            return;
        }
        let request = self.rust().youtube_request;
        self.as_mut().set_youtube_loading_more(true);
        self.as_mut().set_youtube_more_note(QString::default());
        let st = settings::read(|s| s.streams.clone());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let lang = st.video_languages.first().map(String::as_str).unwrap_or("");
            let mut last_page = false;
            let result = match view.as_str() {
                "game" => streams::youtube_search_range(&st.game.youtube, "CAI%3D", page * 20 + 1, (page + 1) * 20, lang),
                "search" => {
                    let f = &st.search;
                    streams::youtube_search_range(&text, &streams::search_param(&f.sort, &f.date, &f.length), page * 30 + 1, (page + 1) * 30, lang)
                }
                "trending" => {
                    let part = if streams::TREND_SECTIONS.contains(&text.as_str()) { text.clone() } else { st.trend_section.clone() };
                    let words = st.trend_words.get(&part).cloned().unwrap_or_else(|| streams::trend_words(&part));
                    streams::youtube_trending_page(&part, &words, &st.video_languages, page)
                }
                // The feed gave the newest 15; then the videos tab, 30 at a time.
                "channel" => streams::youtube_channel_range(text.trim(), 16 + (page - 1) * 30, 15 + page * 30),
                // More of the subscriptions already loaded (60 a page).
                _ => {
                    let ids: Vec<String> = all_channels(&st)
                        .into_iter()
                        .filter(|(c, _)| st.group.is_empty() || c.groups.contains(&st.group))
                        .map(|(c, _)| c.id)
                        .take(MAX_CHANNELS)
                        .collect();
                    match kept_subscriptions(&ids) {
                        Some(all) => {
                            let (kept, _) = filter_videos(all, &st);
                            last_page = kept.len() <= (page + 1) * 60;
                            Ok(kept.into_iter().skip(page * 60).take(60).collect())
                        }
                        None => Err("The subscriptions are older than 15 minutes: load them again (↻).".into()),
                    }
                }
            };
            let result = result.map(|list| if view == "subscriptions" { list } else { filter_videos(list, &st).0 });
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                if obj.rust().youtube_request != request {
                    return;
                }
                obj.as_mut().set_youtube_loading_more(false);
                let list = match result {
                    Ok(l) => l,
                    Err(why) => {
                        obj.set_youtube_more_note(q(&format!("YouTube gave no more: {why}")));
                        return;
                    }
                };
                let mut all: Vec<Value> = serde_json::from_str(&obj.youtube().to_string()).unwrap_or_default();
                let before = all.len();
                for v in list {
                    if !all.iter().any(|x| x["id"] == v["id"]) {
                        all.push(v);
                    }
                }
                let added = all.len() - before;
                let more = added > 0 && !last_page;
                obj.as_mut().rust_mut().youtube_more = more.then(|| (view.clone(), text.clone(), page + 1));
                obj.as_mut().set_youtube_has_more(more);
                if added == 0 {
                    obj.as_mut().set_youtube_more_note(q("Nothing more came."));
                }
                let n = all.len();
                obj.as_mut().set_youtube(q(&Value::Array(all).to_string()));
                obj.set_youtube_message(q(&format!("{n} videos")));
            });
        });
    }

    fn load_youtube(mut self: Pin<&mut Self>, view: &QString, text: &QString) {
        let view = view.to_string();
        let text = text.to_string();
        if !matches!(view.as_str(), "game" | "subscriptions" | "channels" | "channel" | "search" | "trending" | "playlists" | "playlist" | "history") {
            return;
        }
        self.as_mut().set_youtube_view(q(&view));
        // A new list: no next page until it says so.
        self.as_mut().rust_mut().youtube_more = None;
        self.as_mut().set_youtube_has_more(false);
        self.as_mut().set_youtube_loading_more(false);
        self.as_mut().set_youtube_more_note(QString::default());
        if matches!(view.as_str(), "game" | "subscriptions" | "channels" | "trending" | "playlists" | "history") {
            settings::change(|s| s.streams.youtube_view = view.clone());
        }
        if view == "trending" && streams::TREND_SECTIONS.contains(&text.as_str()) {
            settings::change(|s| s.streams.trend_section = text.clone());
            self.as_mut().set_trend_section(q(&text));
        }
        if Self::demo_mode() && !matches!(view.as_str(), "playlist" | "history") {
            return;
        }
        // The user's own lists: at once, nothing fetched.
        if view == "playlist" || view == "history" {
            let list = crate::library::read(|l| {
                if view == "history" {
                    l.history_list(&text)
                } else {
                    l.playlist(&text).map(|p| p.videos.iter().map(|v| v.to_json()).collect()).unwrap_or_default()
                }
            });
            let n = list.len();
            self.as_mut().rust_mut().youtube_request += 1;
            self.as_mut().set_youtube(q(&Value::Array(list).to_string()));
            self.as_mut().set_youtube_state(q("ready"));
            self.set_youtube_message(q(&format!("{n} videos")));
            return;
        }
        if view == "channels" || view == "playlists" || (view == "search" && text.trim().is_empty()) {
            // The channel list or the playlists (no request), or the search
            // before anything is typed.
            if view == "channels" {
                let (channels, groups) = settings::read(|s| (channels_json(&s.streams), groups_json(&s.streams)));
                self.as_mut().set_channels(q(&channels));
                self.as_mut().set_groups(q(&groups));
            }
            self.as_mut().rust_mut().youtube_request += 1;
            self.as_mut().set_youtube(q("[]"));
            self.as_mut().set_youtube_state(q("idle"));
            self.set_youtube_message(QString::default());
            return;
        }
        let st = settings::read(|s| s.streams.clone());
        let request = {
            let mut r = self.as_mut().rust_mut();
            r.youtube_request += 1;
            r.youtube_request
        };
        self.as_mut().set_youtube_state(q("loading"));
        self.as_mut().set_youtube_message(QString::default());
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            // Searches ask in the first chosen language.
            let lang = st.video_languages.first().map(String::as_str).unwrap_or("");
            let result = (|| -> Result<Vec<Value>, String> {
                match view.as_str() {
                    "game" => streams::youtube_search(&st.game.youtube, true, lang),
                    "search" => {
                        let f = &st.search;
                        streams::youtube_search_with(&text, &streams::search_param(&f.sort, &f.date, &f.length), 30, lang)
                    }
                    "channel" => streams::youtube_feed(text.trim()),
                    "trending" => {
                        let part = if streams::TREND_SECTIONS.contains(&text.as_str()) { text.clone() } else { st.trend_section.clone() };
                        let words = st.trend_words.get(&part).cloned().unwrap_or_else(|| streams::trend_words(&part));
                        streams::youtube_trending(&part, &words, &st.video_languages)
                    }
                    _ => {
                        let mut ids: Vec<String> = all_channels(&st)
                            .into_iter()
                            .filter(|(c, _)| st.group.is_empty() || c.groups.contains(&st.group))
                            .map(|(c, _)| c.id)
                            .collect();
                        if ids.is_empty() {
                            return Err(if st.group.is_empty() {
                                "No channels yet: subscribe with the star beside a video, or take over FreeTube's in Settings → Streams.".into()
                            } else {
                                "No channels in this group yet: add some in My channels.".into()
                            });
                        }
                        ids.truncate(MAX_CHANNELS);
                        if let Some(kept) = kept_subscriptions(&ids) {
                            return Ok(kept);
                        }
                        let total = ids.len();
                        let progress = thread.clone();
                        let st2 = st.clone();
                        let (all, failed) = fetch_feeds(ids.clone(), move |done, so_far| {
                            // What came so far shows while the rest loads.
                            let (so_far, _) = filter_videos(newest(so_far.to_vec()), &st2);
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
                        // Kept before leaving anything out: a changed filter
                        // needs no new fetch.
                        let all = newest_of(all, 200);
                        keep_subscriptions(&ids, &all);
                        Ok(all)
                    }
                }
            })();
            let result = result.map(|list| {
                let (mut kept, gone) = filter_videos(list, &st);
                let more = if view == "subscriptions" { kept.len() > 60 } else { !kept.is_empty() && matches!(view.as_str(), "game" | "search" | "trending" | "channel") };
                kept.truncate(if view == "subscriptions" { 60 } else { kept.len() });
                (kept, gone, more)
            });
            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                if obj.rust().youtube_request != request {
                    return;
                }
                let more = matches!(&result, Ok((_, _, true)));
                obj.as_mut().rust_mut().youtube_more = more.then(|| (view.clone(), text.clone(), 1));
                obj.as_mut().set_youtube_has_more(more);
                match result {
                    Ok((videos, gone, _)) => {
                        let n = videos.len();
                        let message = if gone > 0 { format!("{n} videos · {gone} hidden") } else { format!("{n} videos") };
                        obj.as_mut().set_youtube(q(&Value::Array(videos).to_string()));
                        obj.as_mut().set_youtube_state(q("ready"));
                        obj.set_youtube_message(q(&message));
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

    fn toggle_channel(mut self: Pin<&mut Self>, id: &QString, name: &QString) {
        let id = id.to_string();
        if !streams::valid_channel_id(&id) {
            return;
        }
        let name: String = name.to_string().trim().chars().take(100).collect();
        let (channels, groups) = settings::change(|s| {
            let c = &mut s.streams.channels;
            match c.iter().position(|x| x.id == id) {
                Some(i) => {
                    c.remove(i);
                }
                None => {
                    // A FreeTube channel kept here keeps its groups.
                    let groups = streams::freetube().unwrap_or_default().into_iter().find(|f| f.id == id).map(|f| f.groups).unwrap_or_default();
                    c.push(Channel { id, name, groups })
                }
            }
            (channels_json(&s.streams), groups_json(&s.streams))
        });
        self.as_mut().set_channels(q(&channels));
        self.set_groups(q(&groups));
    }

    fn fetch_channel_pictures(self: Pin<&mut Self>) {
        static RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
        if Self::demo_mode() || RUNNING.swap(true, Ordering::SeqCst) {
            return;
        }
        let missing: Vec<String> = {
            let asked = pictures_asked().lock().unwrap_or_else(|p| p.into_inner());
            settings::read(|s| {
                all_channels(&s.streams)
                    .into_iter()
                    .map(|(c, _)| c.id)
                    .filter(|id| !s.streams.channel_pictures.contains_key(id) && !asked.contains(id))
                    .collect()
            })
        };
        if missing.is_empty() {
            RUNNING.store(false, Ordering::SeqCst);
            return;
        }
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let (tx, rx) = mpsc::channel::<(String, String)>();
            // FreeTube's file first: no request for those.
            let freetube = streams::freetube_pictures_here();
            let mut todo = Vec::new();
            for id in missing {
                match freetube.iter().find(|(f, _)| *f == id) {
                    Some((_, pic)) => {
                        let _ = tx.send((id, pic.clone()));
                    }
                    None => todo.push(id),
                }
            }
            todo.reverse();
            let todo = Arc::new(Mutex::new(todo));
            for _ in 0..PICTURES_AT_ONCE {
                let (todo, tx) = (todo.clone(), tx.clone());
                std::thread::spawn(move || loop {
                    let Some(id) = todo.lock().unwrap_or_else(|p| p.into_inner()).pop() else { break };
                    pictures_asked().lock().unwrap_or_else(|p| p.into_inner()).insert(id.clone());
                    match streams::channel_picture(&id) {
                        // "" is kept too: a channel without a picture is not asked again.
                        Ok(pic) => {
                            let _ = tx.send((id, pic));
                        }
                        // No yt-dlp: the others need not try.
                        Err(e) if e.contains("No such file") => {
                            todo.lock().unwrap_or_else(|p| p.into_inner()).clear();
                            break;
                        }
                        Err(_) => {}
                    }
                });
            }
            drop(tx);
            // Kept and shown every two seconds, not per picture.
            let mut found: Vec<(String, String)> = Vec::new();
            let mut shown = Instant::now();
            loop {
                let done = match rx.recv_timeout(Duration::from_millis(500)) {
                    Ok(p) => {
                        found.push(p);
                        false
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => false,
                    Err(mpsc::RecvTimeoutError::Disconnected) => true,
                };
                if !found.is_empty() && (done || shown.elapsed() >= Duration::from_secs(2)) {
                    let j = settings::change(|s| {
                        s.streams.channel_pictures.extend(found.drain(..));
                        pictures_json(&s.streams)
                    });
                    let _ = thread.queue(move |obj| obj.set_channel_pictures(q(&j)));
                    shown = Instant::now();
                }
                if done {
                    break;
                }
            }
            RUNNING.store(false, Ordering::SeqCst);
        });
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

    fn save_video_boost(self: Pin<&mut Self>, db: i32) {
        let db = settings::clamp_video_boost(db);
        settings::change(|s| s.streams.video_boost = db);
        self.set_video_boost(i32::from(db));
    }

    fn save_even_loudness(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.even_loudness = on);
        self.set_even_loudness(on);
    }

    fn save_hwdec(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.hwdec = on);
        self.set_hwdec(on);
    }

    fn opacity_of(&self, slot: &QString) -> i32 {
        let slot = slot.to_string();
        // The chat's and the DPS meter's ground can go almost clear (their
        // text keeps an outline).
        let low = if slot == "chat" || slot == "dps" { 10 } else { 50 };
        settings::read(|s| s.streams.video_opacity.get(&slot).copied()).map_or(100, |p| i32::from(p.clamp(low, 100)))
    }

    fn save_opacity(self: Pin<&mut Self>, slot: &QString, percent: i32) {
        let slot = slot.to_string();
        if slot == "twitch" || slot == "youtube" || slot == "chat" || slot == "dps" {
            let p = percent.clamp(if slot == "chat" || slot == "dps" { 10 } else { 50 }, 100) as u8;
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

    fn set_hide_shorts(self: Pin<&mut Self>, on: bool) {
        let j = settings::change(|s| {
            s.streams.hide_shorts = on;
            filters_json(&s.streams)
        });
        self.set_filters(q(&j));
    }

    fn set_hide_indian(self: Pin<&mut Self>, on: bool) {
        let j = settings::change(|s| {
            s.streams.hide_indian = on;
            filters_json(&s.streams)
        });
        self.set_filters(q(&j));
    }

    fn set_hide_watched(self: Pin<&mut Self>, on: bool) {
        let j = settings::change(|s| {
            s.streams.hide_watched = on;
            filters_json(&s.streams)
        });
        self.set_filters(q(&j));
    }

    fn toggle_hidden_channel(self: Pin<&mut Self>, id: &QString, name: &QString) {
        let (id, name) = (id.to_string(), name.to_string().trim().chars().filter(|c| !c.is_control()).take(100).collect::<String>());
        if !streams::valid_channel_id(&id) && (!id.is_empty() || name.is_empty()) {
            return;
        }
        let j = settings::change(|s| {
            let h = &mut s.streams.hidden_channels;
            match h.iter().position(|c| (!id.is_empty() && c.id == id) || (id.is_empty() && c.name == name)) {
                Some(i) => {
                    h.remove(i);
                }
                None => h.push(Channel { id, name, groups: Vec::new() }),
            }
            filters_json(&s.streams)
        });
        self.set_filters(q(&j));
    }

    fn set_hidden_words(self: Pin<&mut Self>, text: &QString) {
        let words: Vec<String> = text
            .to_string()
            .split(',')
            .map(|w| w.trim().chars().filter(|c| !c.is_control()).take(60).collect::<String>())
            .filter(|w| !w.is_empty())
            .take(100)
            .collect();
        let j = settings::change(|s| {
            s.streams.hidden_words = words;
            filters_json(&s.streams)
        });
        self.set_filters(q(&j));
    }

    fn choose_group(self: Pin<&mut Self>, group: &QString) {
        let g: String = group.to_string().trim().chars().take(40).collect();
        settings::change(|s| s.streams.group = g.clone());
        self.set_group(q(&g));
    }

    fn toggle_channel_group(mut self: Pin<&mut Self>, id: &QString, group: &QString) {
        let id = id.to_string();
        let group: String = group.to_string().trim().chars().filter(|c| !c.is_control()).take(40).collect();
        if !streams::valid_channel_id(&id) || group.is_empty() {
            return;
        }
        let (channels, groups) = settings::change(|s| {
            // A FreeTube channel is kept here once it gets a group of its own.
            if !s.streams.channels.iter().any(|c| c.id == id) {
                if let Some(f) = all_channels(&s.streams).into_iter().find(|(c, _)| c.id == id) {
                    s.streams.channels.push(f.0);
                }
            }
            if let Some(c) = s.streams.channels.iter_mut().find(|c| c.id == id) {
                match c.groups.iter().position(|g| *g == group) {
                    Some(i) => {
                        c.groups.remove(i);
                    }
                    None => c.groups.push(group.clone()),
                }
            }
            (channels_json(&s.streams), groups_json(&s.streams))
        });
        self.as_mut().set_channels(q(&channels));
        self.set_groups(q(&groups));
    }

    fn take_freetube(self: Pin<&mut Self>) -> QString {
        let Some(dir) = crate::library::freetube_dir() else {
            return q("FreeTube's files were not found.");
        };
        // Reading a long history takes a moment: in the background.
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let read = |f: &str| std::fs::read_to_string(dir.join(f)).ok();
            let subs = read("profiles.db").map(|t| streams::freetube_subscriptions(&t)).unwrap_or_default();
            let quick = read("settings.db").and_then(|t| crate::library::freetube_quick(&t));
            let (playlists, history) = (read("playlists.db"), read("history.db"));
            let (lists, seen) = crate::library::change(|l| l.take_freetube(playlists.as_deref(), history.as_deref(), quick.as_deref()));
            let (added, channels, groups) = settings::change(|s| {
                let mut added = 0;
                for c in subs {
                    match s.streams.channels.iter_mut().find(|o| o.id == c.id) {
                        Some(o) => {
                            for g in c.groups {
                                if !o.groups.contains(&g) {
                                    o.groups.push(g);
                                }
                            }
                        }
                        None => {
                            s.streams.channels.push(c);
                            added += 1;
                        }
                    }
                }
                s.streams.freetube_live = false;
                (added, channels_json(&s.streams), groups_json(&s.streams))
            });
            *subscriptions_kept().lock().unwrap_or_else(|p| p.into_inner()) = None;
            let note = format!("Taken over: {added} channels, {lists} playlists, {seen} watched videos. FreeTube's files are no longer read.");
            let _ = thread.queue(move |mut obj| {
                obj.as_mut().set_channels(q(&channels));
                obj.as_mut().set_groups(q(&groups));
                obj.as_mut().set_freetube_live(false);
                obj.freetube_taken(q(&note));
            });
        });
        q("Taking over…")
    }

    fn change_search_filter(self: Pin<&mut Self>, key: &QString, value: &QString) {
        let (key, value) = (key.to_string(), value.to_string());
        let ok = match key.as_str() {
            "sort" => matches!(value.as_str(), "relevance" | "date" | "views"),
            "date" => matches!(value.as_str(), "any" | "hour" | "today" | "week" | "month" | "year"),
            "length" => matches!(value.as_str(), "any" | "short" | "medium" | "long"),
            _ => false,
        };
        if !ok {
            return;
        }
        let j = settings::change(|s| {
            match key.as_str() {
                "sort" => s.streams.search.sort = value,
                "date" => s.streams.search.date = value,
                _ => s.streams.search.length = value,
            }
            serde_json::to_string(&s.streams.search).unwrap_or_default()
        });
        self.set_search_filter(q(&j));
    }

    fn toggle_video_language(self: Pin<&mut Self>, code: &QString) {
        let code = code.to_string();
        if !streams::valid_language(&code) {
            return;
        }
        let j = settings::change(|s| {
            let l = &mut s.streams.video_languages;
            match l.iter().position(|c| *c == code) {
                Some(i) => {
                    l.remove(i);
                }
                None => l.push(code.clone()),
            }
            serde_json::to_string(l).unwrap_or_else(|_| "[]".into())
        });
        self.set_video_languages(q(&j));
    }

    fn change_trend_words(self: Pin<&mut Self>, section: &QString, text: &QString) {
        let section = section.to_string();
        if !streams::TREND_SECTIONS.contains(&section.as_str()) {
            return;
        }
        let words: Vec<String> = text
            .to_string()
            .split(',')
            .map(|w| w.trim().chars().filter(|c| !c.is_control()).take(100).collect::<String>())
            .filter(|w| !w.is_empty())
            .take(6)
            .collect();
        let j = settings::change(|s| {
            if words.is_empty() || words == streams::trend_words(&section) {
                s.streams.trend_words.remove(&section);
            } else {
                s.streams.trend_words.insert(section.clone(), words);
            }
            trend_words_json(&s.streams)
        });
        self.set_trend_words(q(&j));
    }

    fn switch_alerts(mut self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.alerts = on);
        self.as_mut().set_alerts(on);
        if on {
            self.start_alerts();
        } else {
            ALERTS_RUN.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn toggle_alert(self: Pin<&mut Self>, login: &QString) {
        let login = login.to_string().to_ascii_lowercase();
        if !streams::valid_login(&login) {
            return;
        }
        let j = settings::change(|s| {
            if !s.streams.alerts_off.remove(&login) {
                s.streams.alerts_off.insert(login);
            }
            serde_json::to_string(&s.streams.alerts_off).unwrap_or_else(|_| "[]".into())
        });
        self.set_alerts_off(q(&j));
    }

    fn begin(self: Pin<&mut Self>) {
        if settings::read(|s| s.streams.alerts) && !Self::demo_mode() {
            self.start_alerts();
        }
    }

    fn seen_news(self: Pin<&mut Self>) {
        if *self.live_new_count() != 0 {
            self.set_live_new_count(0);
        }
    }

    fn quality_for(&self, login: &QString) -> QString {
        let login = login.to_string().to_ascii_lowercase();
        q(&settings::read(|s| s.streams.channel_quality.get(&login).cloned()).unwrap_or_default())
    }

    fn save_channel_quality(self: Pin<&mut Self>, login: &QString, quality: &QString) {
        let (login, quality) = (login.to_string().to_ascii_lowercase(), quality.to_string());
        let ok = quality == "audio" || quality == "best" || quality.parse::<u32>().is_ok_and(|h| (144..=2160).contains(&h));
        if streams::valid_login(&login) && ok {
            settings::change(|s| {
                s.streams.channel_quality.insert(login, quality);
                // Kept small: the 300 last chosen.
                while s.streams.channel_quality.len() > 300 {
                    let first = s.streams.channel_quality.keys().next().cloned().unwrap_or_default();
                    s.streams.channel_quality.remove(&first);
                }
            });
        }
    }

    fn save_chat_open(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.chat_open = on);
        self.set_chat_open(on);
    }

    fn save_chat_write(self: Pin<&mut Self>, on: bool) {
        settings::change(|s| s.streams.chat_write = on);
        self.set_chat_write(on);
    }

    fn save_chat_docked(self: Pin<&mut Self>, on: bool) {
        if *self.chat_docked() != on {
            settings::change(|s| s.streams.chat_docked = on);
            self.set_chat_docked(on);
        }
    }

    fn chat_auth(&self) -> QString {
        let user = serde_json::from_str::<Value>(&self.account().to_string()).ok().and_then(|v| v["user"].as_str().map(str::to_string)).unwrap_or_default();
        let ok = *self.chat_write() && !user.is_empty() && user != "…" && !Self::demo_mode();
        let j = match streams::twitch_token() {
            Some(token) if ok => json!({ "user": user, "token": token }),
            _ => json!({}),
        };
        QString::from(&j.to_string())
    }

    fn load_emotes(self: Pin<&mut Self>, room: &QString) {
        let room = room.to_string();
        if Self::demo_mode() {
            return;
        }
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let list = crate::emotes::for_room(&room);
            let text = serde_json::to_string(&list).unwrap_or_else(|_| "{}".into());
            let _ = thread.queue(move |obj| obj.emotes_loaded(q(&room), q(&text)));
        });
    }

    fn change_twitch_filter(self: Pin<&mut Self>, key: &QString, value: &QString) {
        let (key, value) = (key.to_string(), value.to_string());
        let j = settings::change(|s| {
            match key.as_str() {
                "languages" => {
                    s.streams.languages = value
                        .split(',')
                        .map(|l| l.trim().to_ascii_lowercase())
                        .filter(|l| (2..=3).contains(&l.len()) && l.chars().all(|c| c.is_ascii_alphabetic()))
                        .take(20)
                        .collect();
                }
                "reruns" => s.streams.hide_reruns = value == "on",
                "sort" if value == "viewers" || value == "new" => s.streams.twitch_sort = value,
                _ => {}
            }
            twitch_filter_json(&s.streams)
        });
        self.set_twitch_filter(q(&j));
    }

    /// Live notes: every two minutes while on, the followed and favourite
    /// channels live now; the ones new since the last look are told.
    fn start_alerts(self: Pin<&mut Self>) {
        let run = ALERTS_RUN.fetch_add(1, Ordering::Relaxed) + 1;
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let mut known: Option<Vec<String>> = None;
            loop {
                if ALERTS_RUN.load(Ordering::Relaxed) != run {
                    return;
                }
                let st = settings::read(|s| s.streams.clone());
                let mut live: Vec<Value> = Vec::new();
                let mut ok = false;
                if let Some(token) = streams::twitch_token() {
                    if let Ok(q) = streams::twitch_query("followedLive", &Value::Null) {
                        if let Ok(data) = streams::twitch(&q, Some(&token)) {
                            live.extend(streams::twitch_cards(&data));
                            ok = true;
                        }
                    }
                }
                if !st.favourites.is_empty() {
                    if let Ok(q) = streams::twitch_query("channels", &json!(st.favourites)) {
                        if let Ok(data) = streams::twitch(&q, None) {
                            for c in streams::twitch_cards(&data) {
                                if c["live"] == true && !live.iter().any(|x| x["login"] == c["login"]) {
                                    live.push(c);
                                }
                            }
                            ok = true;
                        }
                    }
                }
                if ok {
                    let logins: Vec<String> = live.iter().filter_map(|c| c["login"].as_str().map(str::to_string)).collect();
                    if let Some(before) = &known {
                        let new: Vec<Value> = live
                            .iter()
                            .filter(|c| {
                                let l = c["login"].as_str().unwrap_or("");
                                !before.iter().any(|b| b == l) && !st.alerts_off.contains(l)
                            })
                            .map(|c| json!({ "login": c["login"], "name": c["name"], "title": c["title"], "game": c["game"], "at": crate::library::now() }))
                            .collect();
                        if !new.is_empty() {
                            let _ = thread.queue(move |mut obj: Pin<&mut qobject::Streams>| {
                                if ALERTS_RUN.load(Ordering::Relaxed) != run {
                                    return;
                                }
                                let mut news: Vec<Value> = serde_json::from_str(&obj.live_news().to_string()).unwrap_or_default();
                                let n = new.len() as i32;
                                for c in new.iter().rev() {
                                    news.retain(|x| x["login"] != c["login"]);
                                    news.insert(0, c.clone());
                                }
                                news.truncate(10);
                                obj.as_mut().set_live_news(q(&Value::Array(news).to_string()));
                                let count = obj.live_new_count() + n;
                                obj.as_mut().set_live_new_count(count);
                                for c in new {
                                    obj.as_mut().went_live(q(c["name"].as_str().unwrap_or("")), q(c["title"].as_str().unwrap_or("")));
                                }
                            });
                        }
                    }
                    known = Some(logins);
                }
                for _ in 0..120 {
                    std::thread::sleep(Duration::from_secs(1));
                    if ALERTS_RUN.load(Ordering::Relaxed) != run {
                        return;
                    }
                }
            }
        });
    }

    fn stop_source(&self, slot: &QString) {
        streams::streamlink_stop(&slot.to_string());
    }

    fn video_id(&self, text: &QString) -> QString {
        q(&streams::video_id_of(&text.to_string()).unwrap_or_default())
    }
}
