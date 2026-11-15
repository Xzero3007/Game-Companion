//! Brave and Legcord over the game (MN, 2026-11-14; plan
//! `brave-legcord-plan.md` in the project folder). They stay the person's
//! own programs: Wayland lets no app embed or move another app's window, so
//! KWin does it, through scripts.
//!
//! - A watcher script, loaded once, reports the windows of the apps (added,
//!   moved, minimised, gone) and which window is active. It only reacts to
//!   KWin's signals: no timer, nothing while idle.
//! - Every action (show, hide, opacity, put back) is a short script of its
//!   own, loaded, run and unloaded again; it says "done" when it ran.
//! - Both talk back over the session bus to this process's own connection
//!   (its unique name, no well-known name), and only KWin's calls count.
//!
//! Found on KWin 6.8 (Arch test bench, 2026-11-14): a window kept above
//! stays over a borderless game window, but a game in real full screen that
//! has the focus lies over every normal window, kept above or not (Proton
//! marks a game's "borderless" window as full screen too). So while an app
//! is shown over such a game, the game's window loses its full-screen mark:
//! same size, no border, nothing changes for the game, and the app stays on
//! top (MN, 2026-11-14; "Stay over a full-screen game", settings
//! `apps_over_full`). When no app is shown any more, the game gets the mark
//! back. With that off, a full-screen game taking the focus minimises the
//! apps on its screen (they would be hidden behind it anyway).
//!
//! Nothing here leaves the computer. Of a game's window only its full-screen
//! mark is ever changed, through KWin, and given back.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use zbus::blocking::Connection;

use crate::start_with;

/// One of the programs the bar can show over the game.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AppDef {
    /// Stable id (settings, shortcuts, QML).
    pub id: &'static str,
    pub name: &'static str,
    /// Programs on the PATH to try, in turn, when none was chosen.
    pub programs: &'static [&'static str],
    /// What its windows' app id or class starts with (lower case).
    pub window: &'static str,
    /// Its first place on the game's screen: width, height, and whether it
    /// sits at the right edge (else the left).
    pub size: (i32, i32),
    pub right: bool,
    /// What follows the program found on the PATH (not a chosen command).
    pub args: &'static str,
    /// The one game it starts with ("With game"), or None for any game.
    pub game: Option<&'static str>,
}

pub const APPS: [AppDef; 3] = [
    AppDef {
        id: "brave",
        name: "Brave",
        programs: &["brave-origin", "brave-origin-beta", "brave-origin-nightly", "brave", "brave-browser", "brave-beta"],
        window: "brave",
        size: (560, 760),
        right: true,
        args: "",
        game: None,
    },
    AppDef { id: "legcord", name: "Legcord", programs: &["legcord"], window: "legcord", size: (560, 640), right: false, args: "", game: None },
    // Path of Building 2 in Rusty Path of Building's runtime (the person's,
    // 2026-11-15): its window's app id is `rusty-path-of-building-2`.
    AppDef {
        id: "pob",
        name: "PoB",
        programs: &["rusty-path-of-building"],
        window: "rusty-path-of-building",
        size: (1280, 800),
        right: false,
        args: "poe2",
        game: Some("poe2"),
    },
];

pub fn def(id: &str) -> Option<&'static AppDef> {
    APPS.iter().find(|a| a.id == id)
}

/// The person's choices for one app (settings `apps.<id>`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AppChoice {
    /// The command line that starts it ("" = the first of `programs` found).
    pub command: String,
    /// Opacity over the game, 20 to 100 %.
    pub opacity: u8,
    /// Its place on the game's screen, relative to that screen's top left
    /// (None until it was shown and moved).
    pub place: Option<Place>,
    /// Starts when a game starts (not shown until asked).
    pub with_game: bool,
    /// Closes with Game Companion if Game Companion started it.
    pub close_on_quit: bool,
}

impl Default for AppChoice {
    fn default() -> Self {
        Self { command: String::new(), opacity: 90, place: None, with_game: false, close_on_quit: true }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Place {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

pub const MIN_OPACITY: u8 = 20;

/// The choices for an app, with the defaults where nothing was chosen.
pub fn choice(id: &str) -> AppChoice {
    crate::settings::read(|s| s.apps.get(id).cloned()).unwrap_or_default()
}

/// The command to start an app: the chosen one, else the first program of
/// its list on the PATH.
pub fn command_for(app: &AppDef, choice: &AppChoice) -> Option<String> {
    command_in(app, choice, &std::env::var_os("PATH").unwrap_or_default())
}

fn command_in(app: &AppDef, choice: &AppChoice, path: &std::ffi::OsStr) -> Option<String> {
    let chosen = choice.command.trim();
    if !chosen.is_empty() {
        return Some(chosen.to_string());
    }
    app.programs
        .iter()
        .find(|p| std::env::split_paths(path).any(|dir| is_program(&dir.join(p))))
        .map(|p| if app.args.is_empty() { p.to_string() } else { format!("{p} {}", app.args) })
}

fn is_program(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

/// A Chromium site app's id (`brave-<32 letters a to p>-Default`): its own
/// window, not the browser's.
fn site_app(key: &str) -> bool {
    key.split('-').any(|part| part.len() == 32 && part.bytes().all(|b| (b'a'..=b'p').contains(&b)))
}

/// Whether a window belongs to an app (by its app id or class).
pub fn belongs(app: &AppDef, win: &Win) -> bool {
    if !win.normal {
        return false;
    }
    [&win.app, &win.cls].iter().any(|k| {
        let k = k.to_lowercase();
        // `com.brave.Browser`: any part of a reverse-domain id.
        k.split('.').any(|part| part.starts_with(app.window)) && !site_app(&k)
    })
}

// ------------------------------------------------------------ events ----

/// A window as the scripts describe it.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct Win {
    pub id: String,
    pub cls: String,
    pub app: String,
    pub pid: i32,
    pub normal: bool,
    pub full: bool,
    pub min: bool,
    pub above: bool,
    pub opacity: f64,
    /// Its screen's name and top left.
    pub out: String,
    pub ox: i32,
    pub oy: i32,
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    /// Being moved or resized by hand right now.
    pub moving: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    /// An app's window appeared or changed.
    Window(Win),
    /// A window went away (its id).
    Removed(String),
    /// Another window took the focus (None: no normal window has it).
    Active(Option<Win>),
    /// A window that is no app's went full screen.
    Full(Win),
    /// The watcher has reported every window there was.
    Ready,
}

pub fn parse_event(kind: &str, data: &str) -> Option<Event> {
    match kind {
        "window" => serde_json::from_str::<Win>(data).ok().filter(|w| !w.id.is_empty()).map(Event::Window),
        "removed" => {
            let v: Value = serde_json::from_str(data).ok()?;
            Some(Event::Removed(v.get("id")?.as_str()?.to_string()))
        }
        "active" => Some(Event::Active(serde_json::from_str::<Win>(data).ok().filter(|w| !w.id.is_empty()))),
        "full" => serde_json::from_str::<Win>(data).ok().filter(|w| !w.id.is_empty()).map(Event::Full),
        "ready" => Some(Event::Ready),
        _ => None,
    }
}

// ----------------------------------------------------------- scripts ----

const PATH: &str = "/io/github/xzero3007/GameCompanion/Apps";
const IFACE: &str = "io.github.xzero3007.GameCompanion.Apps";
/// The watcher's name in KWin (a copy that crashed left it: replaced).
const WATCHER: &str = "game-companion-apps";

fn js(value: impl Serialize) -> String {
    serde_json::to_string(&value).unwrap_or_else(|_| "null".into())
}

/// What every script starts with: where to call back, and how a window is
/// described.
fn prelude(bus: &str) -> String {
    format!(
        r#"var GC_BUS = {bus}, GC_PATH = {path}, GC_IFACE = {iface};
function gcInfo(w) {{
    var o = w.output, g = w.frameGeometry;
    return JSON.stringify({{ id: String(w.internalId), cls: String(w.resourceClass || ""), app: String(w.desktopFileName || ""),
        pid: w.pid, normal: !!w.normalWindow, full: !!w.fullScreen, min: !!w.minimized, above: !!w.keepAbove,
        opacity: w.opacity, out: o ? String(o.name) : "", ox: o ? o.geometry.x : 0, oy: o ? o.geometry.y : 0,
        x: Math.round(g.x), y: Math.round(g.y), w: Math.round(g.width), h: Math.round(g.height), moving: !!(w.move || w.resize) }});
}}
"#,
        bus = js(bus),
        path = js(PATH),
        iface = js(IFACE),
    )
}

/// The watcher: reports the windows whose app id or class contains one of
/// `keys`, and every change of focus.
pub fn watcher_script(bus: &str, keys: &[&str]) -> String {
    let keys: Vec<String> = keys.iter().map(|k| k.to_lowercase()).collect();
    prelude(bus)
        + &format!(
            r#"var GC_KEYS = {keys};
function gcSend(kind, data) {{ callDBus(GC_BUS, GC_PATH, GC_IFACE, "Event", kind, data); }}
function gcWatched(w) {{
    if (!w || !w.normalWindow || w.transient) return false;
    var k = (String(w.desktopFileName || "") + " " + String(w.resourceClass || "")).toLowerCase();
    for (var i = 0; i < GC_KEYS.length; i++) if (k.indexOf(GC_KEYS[i]) >= 0) return true;
    return false;
}}
function gcHook(w) {{
    if (!gcWatched(w)) {{
        // Any other window going full screen (a game taking its mark back).
        if (w && w.normalWindow) w.fullScreenChanged.connect(function () {{ if (w.fullScreen) gcSend("full", gcInfo(w)); }});
        return;
    }}
    gcSend("window", gcInfo(w));
    w.frameGeometryChanged.connect(function () {{ if (!w.move && !w.resize) gcSend("window", gcInfo(w)); }});
    w.interactiveMoveResizeFinished.connect(function () {{ gcSend("window", gcInfo(w)); }});
    w.minimizedChanged.connect(function () {{ gcSend("window", gcInfo(w)); }});
    w.fullScreenChanged.connect(function () {{ gcSend("window", gcInfo(w)); }});
}}
workspace.windowAdded.connect(gcHook);
workspace.windowRemoved.connect(function (w) {{ if (gcWatched(w)) gcSend("removed", JSON.stringify({{ id: String(w.internalId) }})); }});
workspace.windowActivated.connect(function (w) {{ gcSend("active", w && w.normalWindow ? gcInfo(w) : "{{}}"); }});
var gcAll = workspace.windowList();
for (var i = 0; i < gcAll.length; i++) gcHook(gcAll[i]);
var gcNow = workspace.activeWindow;
gcSend("active", gcNow && gcNow.normalWindow ? gcInfo(gcNow) : "{{}}");
gcSend("ready", "{{}}");
"#,
            keys = js(keys)
        )
}

/// A one-off script: `body` runs with `gcFind(id)` and `gcOutput(name)`,
/// then it says it is done.
pub fn command_script(bus: &str, token: &str, body: &str) -> String {
    prelude(bus)
        + &format!(
            r#"function gcFind(id) {{
    var a = workspace.windowList();
    for (var i = 0; i < a.length; i++) if (String(a[i].internalId) === id) return a[i];
    return null;
}}
function gcOutput(name) {{
    var s = workspace.screens;
    for (var i = 0; i < s.length; i++) if (String(s[i].name) === name) return s[i];
    return workspace.activeScreen;
}}
try {{
{body}
}} finally {{
    callDBus(GC_BUS, GC_PATH, GC_IFACE, "Done", {token});
}}
"#,
            token = js(token)
        )
}

/// Shows a window over the game: on `output` at `place` (relative to that
/// screen; None: the app's first place), kept above, at `opacity` (0 to 1),
/// with the focus.
pub fn show_body(id: &str, output: &str, place: Option<Place>, app: &AppDef, opacity: f64) -> String {
    format!(
        r#"var w = gcFind({id});
if (w) {{
    var o = gcOutput({output}), g = o.geometry, p = {place};
    if (!p) {{ var pw = Math.min({dw}, g.width - 80), ph = Math.min({dh}, g.height - 160);
        p = {{ x: {right} ? g.width - pw - 40 : 40, y: 110, w: pw, h: ph }}; }}
    var pw2 = Math.max(240, Math.min(p.w, g.width)), ph2 = Math.max(200, Math.min(p.h, g.height));
    var px = Math.max(0, Math.min(p.x, g.width - pw2)), py = Math.max(0, Math.min(p.y, g.height - ph2));
    if (w.minimized) w.minimized = false;
    if (w.fullScreen) w.fullScreen = false;
    if (w.setMaximize) w.setMaximize(false, false);
    w.keepAbove = true;
    w.opacity = {opacity};
    w.frameGeometry = {{ x: g.x + px, y: g.y + py, width: pw2, height: ph2 }};
    workspace.activeWindow = w;
}}"#,
        id = js(id),
        output = js(output),
        place = js(place.map(|p| json!({ "x": p.x, "y": p.y, "w": p.w, "h": p.h }))),
        dw = app.size.0,
        dh = app.size.1,
        right = app.right,
        opacity = opacity.clamp(0.2, 1.0),
    )
}

/// Minimises a window and gives the focus back to `focus` (the game).
pub fn hide_body(id: &str, focus: &str) -> String {
    format!(
        r#"var w = gcFind({id});
if (w) w.minimized = true;
var f = {focus} ? gcFind({focus}) : null;
if (f && !f.minimized) workspace.activeWindow = f;"#,
        id = js(id),
        focus = js(focus)
    )
}

/// Takes the full-screen mark off a game's window so that a window kept
/// above stays over it: the same size on its screen, no border.
pub fn unfull_body(id: &str) -> String {
    format!(
        r#"var w = gcFind({id});
if (w && w.fullScreen) {{
    var g = w.output.geometry;
    w.fullScreen = false;
    w.noBorder = true;
    w.frameGeometry = {{ x: g.x, y: g.y, width: g.width, height: g.height }};
}}"#,
        id = js(id)
    )
}

/// Gives a game's window its full-screen mark back.
pub fn refull_body(id: &str) -> String {
    format!(
        r#"var w = gcFind({id});
if (w && !w.fullScreen) {{
    w.noBorder = false;
    w.fullScreen = true;
}}"#,
        id = js(id)
    )
}

pub fn opacity_body(id: &str, opacity: f64) -> String {
    format!("var w = gcFind({}); if (w) w.opacity = {};", js(id), opacity.clamp(0.2, 1.0))
}

pub fn close_body(id: &str) -> String {
    format!("var w = gcFind({}); if (w) w.closeWindow();", js(id))
}

/// How a window was before Game Companion first showed it.
#[derive(Debug, Clone, PartialEq)]
pub struct Before {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    pub above: bool,
    pub opacity: f64,
    pub min: bool,
}

impl Before {
    pub fn of(win: &Win) -> Self {
        Self { x: win.x, y: win.y, w: win.w, h: win.h, above: win.above, opacity: win.opacity, min: win.min }
    }
}

/// Puts a window back as it was (the game ended, or Game Companion quits).
pub fn restore_body(id: &str, before: &Before) -> String {
    format!(
        r#"var w = gcFind({id});
if (w) {{
    w.keepAbove = {above};
    w.opacity = {opacity};
    w.frameGeometry = {{ x: {x}, y: {y}, width: {w}, height: {h} }};
    w.minimized = {min};
}}"#,
        id = js(id),
        above = before.above,
        opacity = if before.opacity > 0.0 { before.opacity.clamp(0.2, 1.0) } else { 1.0 },
        x = before.x,
        y = before.y,
        w = before.w.max(100),
        h = before.h.max(100),
        min = before.min,
    )
}

// ------------------------------------------------------------- KWin ----

type OnEvent = Box<dyn Fn(Event) + Send + Sync>;

/// What KWin's calls reach.
struct Listener {
    on_event: OnEvent,
    /// KWin's unique name on the bus: only its calls count.
    kwin: Arc<Mutex<String>>,
    done: Arc<(Mutex<Vec<String>>, Condvar)>,
}

impl Listener {
    fn sent_by_kwin(&self, header: &zbus::message::Header<'_>) -> bool {
        let kwin = self.kwin.lock().unwrap_or_else(|p| p.into_inner());
        !kwin.is_empty() && header.sender().is_some_and(|s| s.as_str() == kwin.as_str())
    }
}

#[zbus::interface(name = "io.github.xzero3007.GameCompanion.Apps")]
impl Listener {
    fn event(&self, #[zbus(header)] header: zbus::message::Header<'_>, kind: String, data: String) {
        if !self.sent_by_kwin(&header) {
            return;
        }
        if let Some(event) = parse_event(&kind, &data) {
            (self.on_event)(event);
        }
    }

    fn done(&self, #[zbus(header)] header: zbus::message::Header<'_>, token: String) {
        if !self.sent_by_kwin(&header) {
            return;
        }
        let (list, ready) = &*self.done;
        list.lock().unwrap_or_else(|p| p.into_inner()).push(token);
        ready.notify_all();
    }
}

/// The session bus connection that talks to KWin.
pub struct Kwin {
    conn: Connection,
    kwin: Arc<Mutex<String>>,
    done: Arc<(Mutex<Vec<String>>, Condvar)>,
    next: AtomicU64,
}

/// Whether this is a KDE Plasma session (KWin runs the windows).
pub fn on_kde() -> bool {
    std::env::var("XDG_CURRENT_DESKTOP").is_ok_and(|d| d.split(':').any(|p| p.eq_ignore_ascii_case("KDE")))
        || std::env::var_os("KDE_FULL_SESSION").is_some()
}

impl Kwin {
    /// Connects and serves the listener; `on_event` runs on zbus's thread.
    pub fn connect(on_event: impl Fn(Event) + Send + Sync + 'static) -> zbus::Result<Kwin> {
        let conn = Connection::session()?;
        let kwin = Arc::new(Mutex::new(String::new()));
        let done = Arc::new((Mutex::new(Vec::new()), Condvar::new()));
        let listener = Listener { on_event: Box::new(on_event), kwin: kwin.clone(), done: done.clone() };
        conn.object_server().at(PATH, listener)?;
        let me = Kwin { conn, kwin, done, next: AtomicU64::new(1) };
        me.find_kwin()?;
        Ok(me)
    }

    /// This connection's unique name (where the scripts call back).
    fn bus_name(&self) -> String {
        self.conn.unique_name().map(|n| n.to_string()).unwrap_or_default()
    }

    /// Asks the bus who KWin is now (it may have restarted).
    fn find_kwin(&self) -> zbus::Result<()> {
        let dbus = zbus::blocking::fdo::DBusProxy::new(&self.conn)?;
        let owner = dbus.get_name_owner("org.kde.KWin".try_into()?)?;
        *self.kwin.lock().unwrap_or_else(|p| p.into_inner()) = owner.to_string();
        Ok(())
    }

    fn scripting(&self) -> zbus::Result<zbus::blocking::Proxy<'_>> {
        zbus::blocking::Proxy::new(&self.conn, "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting")
    }

    /// Loads a script file under `name` (one by that name goes first) and
    /// runs it.
    fn load(&self, file: &Path, name: &str) -> zbus::Result<()> {
        let scripting = self.scripting()?;
        let loaded: bool = scripting.call("isScriptLoaded", &(name,)).unwrap_or(false);
        if loaded {
            let _: bool = scripting.call("unloadScript", &(name,))?;
        }
        let id: i32 = scripting.call("loadScript", &(file.to_string_lossy().as_ref(), name))?;
        if id < 0 {
            return Err(zbus::Error::Failure(format!("KWin did not load {name}")));
        }
        let path = format!("/Scripting/Script{id}");
        let script = zbus::blocking::Proxy::new(&self.conn, "org.kde.KWin", path.as_str(), "org.kde.kwin.Script")?;
        let () = script.call("run", &())?;
        Ok(())
    }

    fn unload(&self, name: &str) {
        if let Ok(scripting) = self.scripting() {
            let _: zbus::Result<bool> = scripting.call("unloadScript", &(name,));
        }
    }

    /// Loads the watcher (again).
    pub fn watch(&self, keys: &[&str]) -> zbus::Result<()> {
        self.find_kwin()?;
        let file = script_file(WATCHER)?;
        std::fs::write(&file, watcher_script(&self.bus_name(), keys)).map_err(io)?;
        let result = self.load(&file, WATCHER);
        let _ = std::fs::remove_file(&file);
        result
    }

    pub fn stop_watching(&self) {
        self.unload(WATCHER);
    }

    /// Runs a one-off script and waits (at most 2 s) until it ran.
    pub fn run(&self, body: &str) -> zbus::Result<()> {
        let token = format!("{}-{}", std::process::id(), self.next.fetch_add(1, Ordering::Relaxed));
        let name = format!("game-companion-do-{token}");
        let file = script_file(&name)?;
        std::fs::write(&file, command_script(&self.bus_name(), &token, body)).map_err(io)?;
        let loaded = self.load(&file, &name);
        if loaded.is_ok() {
            let (list, ready) = &*self.done;
            let mut list = list.lock().unwrap_or_else(|p| p.into_inner());
            let deadline = std::time::Instant::now() + Duration::from_secs(2);
            while !list.contains(&token) {
                let left = deadline.saturating_duration_since(std::time::Instant::now());
                if left.is_zero() {
                    break;
                }
                list = ready.wait_timeout(list, left).map(|(l, _)| l).unwrap_or_else(|p| p.into_inner().0);
            }
            list.retain(|t| t != &token);
        }
        self.unload(&name);
        let _ = std::fs::remove_file(&file);
        loaded
    }
}

fn io(e: std::io::Error) -> zbus::Error {
    zbus::Error::Failure(e.to_string())
}

/// A file for a script in the runtime folder (0600; KWin reads it by path).
fn script_file(name: &str) -> zbus::Result<std::path::PathBuf> {
    use std::os::unix::fs::OpenOptionsExt;
    let dir = crate::instance::runtime_dir();
    let path = dir.join(format!("{name}.js"));
    std::fs::OpenOptions::new().create(true).write(true).truncate(true).mode(0o600).open(&path).map_err(io)?;
    Ok(path)
}

// ------------------------------------------------------------ state ----

/// What Game Companion started and changed, kept apart from Qt so that
/// quitting can put it all back after the windows are gone.
#[derive(Default)]
pub struct Runtime {
    pub kwin: Option<Arc<Kwin>>,
    /// Programs Game Companion started: app id → (pid, start time).
    pub started: HashMap<&'static str, (i32, u64)>,
    /// Windows Game Companion moved: window id → how they were.
    pub before: BTreeMap<String, Before>,
    /// The game window whose full-screen mark was taken off (`unfull_body`).
    pub unfull: Option<String>,
}

pub static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);

pub fn runtime<R>(f: impl FnOnce(&mut Runtime) -> R) -> R {
    let mut guard = RUNTIME.lock().unwrap_or_else(|p| p.into_inner());
    f(guard.get_or_insert_with(Runtime::default))
}

/// Puts every moved window back as it was, and a game its full screen.
pub fn restore_all() {
    let (kwin, before, unfull) = runtime(|r| (r.kwin.clone(), std::mem::take(&mut r.before), r.unfull.take()));
    let Some(kwin) = kwin else { return };
    if let Some(id) = unfull {
        let _ = kwin.run(&refull_body(&id));
    }
    for (id, b) in before {
        let _ = kwin.run(&restore_body(&id, &b));
    }
}

/// Game Companion quits: windows put back, the watcher gone, and what it
/// started closed (asked first, ended hard if still there after 3 s).
pub fn quit() {
    restore_all();
    let (kwin, started) = runtime(|r| (r.kwin.take(), std::mem::take(&mut r.started)));
    if let Some(kwin) = kwin {
        kwin.stop_watching();
    }
    let closing: Vec<(i32, u64)> = started
        .into_iter()
        .filter(|(id, _)| choice(id).close_on_quit)
        .map(|(_, p)| p)
        .filter(|&(pid, start)| start_with::program_alive(pid, start))
        .collect();
    if closing.is_empty() {
        return;
    }
    for &(pid, start) in &closing {
        eprintln!("game-companion: closing pid {pid}");
        start_with::signal_program(pid, start, libc::SIGTERM);
    }
    for _ in 0..30 {
        if !closing.iter().any(|&(pid, start)| start_with::program_alive(pid, start)) {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    for &(pid, start) in &closing {
        start_with::signal_program(pid, start, libc::SIGKILL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn win(app: &str, cls: &str) -> Win {
        Win { id: "{1}".into(), app: app.into(), cls: cls.into(), normal: true, ..Default::default() }
    }

    #[test]
    fn windows_belong_by_app_id_or_class() {
        let brave = def("brave").unwrap();
        let legcord = def("legcord").unwrap();
        assert!(belongs(brave, &win("brave-origin", "brave-origin")));
        assert!(belongs(brave, &win("brave-browser", "")));
        assert!(belongs(brave, &win("", "Brave-browser")));
        assert!(belongs(brave, &win("com.brave.Browser", "")));
        assert!(!belongs(brave, &win("brave-abcdefghijklmnopabcdefghijklmnop-Default", "")));
        assert!(!belongs(brave, &win("legcord", "legcord")));
        assert!(belongs(legcord, &win("legcord", "")));
        let mut popup = win("legcord", "legcord");
        popup.normal = false;
        assert!(!belongs(legcord, &popup));
    }

    #[test]
    fn events_come_from_the_scripts_json() {
        let e = parse_event("window", r#"{"id":"{a}","app":"legcord","normal":true,"x":5,"w":300,"out":"DP-2"}"#);
        let Some(Event::Window(w)) = e else { panic!("{e:?}") };
        assert_eq!((w.id.as_str(), w.x, w.w, w.out.as_str()), ("{a}", 5, 300, "DP-2"));
        assert_eq!(parse_event("removed", r#"{"id":"{a}"}"#), Some(Event::Removed("{a}".into())));
        assert_eq!(parse_event("active", "{}"), Some(Event::Active(None)));
        assert_eq!(parse_event("ready", "{}"), Some(Event::Ready));
        let e = parse_event("full", r#"{"id":"{g}","cls":"aion2.exe","normal":true,"full":true,"out":"DP-2"}"#);
        let Some(Event::Full(g)) = e else { panic!("{e:?}") };
        assert!(g.full && g.out == "DP-2");
        assert_eq!(parse_event("window", "{}"), None);
        assert_eq!(parse_event("other", "{}"), None);
    }

    #[test]
    fn scripts_carry_their_values_as_json() {
        let brave = def("brave").unwrap();
        let s = command_script(":1.42", "7-1", &show_body("{x\"y}", "DP-2", None, brave, 0.88));
        assert!(s.contains(r#"var GC_BUS = ":1.42""#));
        assert!(s.contains(r#"gcFind("{x\"y}")"#));
        assert!(s.contains(r#"gcOutput("DP-2")"#));
        assert!(s.contains("p = null"));
        assert!(s.contains("w.opacity = 0.88"));
        assert!(s.contains(r#""Done", "7-1""#));
        let s = show_body("{a}", "DP-2", Some(Place { x: 10, y: 20, w: 300, h: 400 }), brave, 5.0);
        assert!(s.contains(r#""x":10"#) && s.contains(r#""h":400"#), "{s}");
        assert!(s.contains("w.opacity = 1"));
        let w = watcher_script(":1.42", &["brave", "Legcord"]);
        assert!(w.contains(r#"var GC_KEYS = ["brave","legcord"]"#));
        let b = Before { x: 1, y: 2, w: 30, h: 40, above: false, opacity: 0.0, min: true };
        let r = restore_body("{a}", &b);
        assert!(r.contains("w.opacity = 1;") && r.contains("width: 100") && r.contains("w.minimized = true"));
        assert!(w.contains(r#"gcSend("full", gcInfo(w))"#));
        let u = unfull_body("{g}");
        assert!(u.contains(r#"gcFind("{g}")"#) && u.contains("w.fullScreen = false") && u.contains("w.noBorder = true"));
        assert!(refull_body("{g}").contains("w.fullScreen = true"));
    }

    #[test]
    fn the_first_program_found_starts_an_app() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("gc-apps-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let program = dir.join("brave");
        std::fs::write(&program, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::fs::write(dir.join("brave-origin"), "not a program").unwrap();
        let path = dir.as_os_str();
        let brave = def("brave").unwrap();
        assert_eq!(command_in(brave, &AppChoice::default(), path).as_deref(), Some("brave"));
        let chosen = AppChoice { command: " brave-origin --x ".into(), ..Default::default() };
        assert_eq!(command_in(brave, &chosen, path).as_deref(), Some("brave-origin --x"));
        assert_eq!(command_in(def("legcord").unwrap(), &AppChoice::default(), path), None);
        // Path of Building starts in its PoE 2 mode; a chosen command as it is.
        let pob_program = dir.join("rusty-path-of-building");
        std::fs::write(&pob_program, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&pob_program, std::fs::Permissions::from_mode(0o755)).unwrap();
        let pob = def("pob").unwrap();
        assert_eq!(command_in(pob, &AppChoice::default(), path).as_deref(), Some("rusty-path-of-building poe2"));
        let chosen = AppChoice { command: "rusty-path-of-building poe1".into(), ..Default::default() };
        assert_eq!(command_in(pob, &chosen, path).as_deref(), Some("rusty-path-of-building poe1"));
        assert!(belongs(pob, &win("rusty-path-of-building-2", "")));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
