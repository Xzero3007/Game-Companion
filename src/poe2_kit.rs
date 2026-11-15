//! The PoE 2 price check's kit (Exiled Exchange 2's parser, filters and
//! trade code, qml/poe2/ee2kit.js) in its own process with QuickJS.
//!
//! Qt's JavaScript crashed in the kit on Arch's Qt 6.12: first its JIT
//! (QA, 2026-11-15), then its interpreter in `newArrayIteratorObject` on
//! real searches (MN, 0.8.43 and 0.8.44: Game Companion died on a price
//! check). So the kit no longer runs in Qt: `game-companion --poe2-kit`
//! runs it in QuickJS and talks JSON lines over stdin/stdout; if it dies,
//! only the price check starts again (MN: "das darf nicht passieren").
//!
//! The child ends with the app: PR_SET_PDEATHSIG (set from the Qt thread,
//! which lives as long as the app), its stdin closing, and a parent check.
//!
//! Lines in (from the app): `{"id": n, "fn": "check", "args": [...]}`.
//! Lines out: `{"id": n, "kind": "reply" | "progress" | "error", "value": ...}`.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io::{BufRead, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::rc::Rc;
use std::sync::mpsc;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const KIT: &str = include_str!("../qml/poe2/ee2kit.js");

/// What Qt's JavaScript has and QuickJS lacks: `console` (to stderr).
const PRELUDE: &str = r#"
var console = (function () {
    var say = function () { __gcSend(JSON.stringify({ kind: "log", value: Array.prototype.join.call(arguments, " ") })); };
    return { log: say, info: say, warn: say, error: say, debug: say, trace: say };
})();
"#;

/// The glue between the kit and this process: the host the kit asks for
/// (requests, timers, data files) and the commands from the app.
const GLUE: &str = r#"
var __gcPending = {}, __gcTimers = {}, __gcNext = 1;
function __gcOut(o) { __gcSend(JSON.stringify(o)); }
var __gcHost = {
    request: function (url, method, body) {
        return new Promise(function (resolve, reject) {
            var id = __gcNext++;
            __gcPending[id] = { resolve: resolve, reject: reject };
            __gcOut({ kind: "request", rid: id, url: url, method: method || "GET", body: body || "" });
        });
    },
    timer: function (ms, cb) {
        var id = __gcNext++;
        __gcTimers[id] = cb;
        __gcOut({ kind: "timer", tid: id, ms: Math.max(0, Number(ms) || 0) });
        return id;
    },
    cancel: function (id) {
        if (__gcTimers[id]) { delete __gcTimers[id]; __gcOut({ kind: "cancel", tid: id }); }
    },
    readData: function (path) { return __gcRead(String(path)); },
    log: function (t) { __gcOut({ kind: "log", value: String(t) }); }
};
function __gcAnswer(id, status, headers, body) {
    var p = __gcPending[id];
    if (!p) return;
    delete __gcPending[id];
    if (status === 0) { p.reject(new Error(body)); return; }
    var h = {};
    try { h = JSON.parse(headers); } catch (e) { }
    p.resolve({ status: status, headers: h, body: body });
}
function __gcFire(id) {
    var cb = __gcTimers[id];
    if (!cb) return;
    delete __gcTimers[id];
    cb();
}
function __gcCommand(line) {
    var m;
    try { m = JSON.parse(line); } catch (e) { return; }
    var reply = function (kind, value) { __gcOut({ id: m.id, kind: kind, value: value === undefined ? null : value }); };
    var fn = EE2[m.fn];
    if (typeof fn !== "function") { reply("error", "no such call: " + m.fn); return; }
    var args = m.args || [];
    if (m.fn === "search") args = [function (r) { reply("progress", r); }];
    try {
        Promise.resolve(fn.apply(null, args)).then(function (v) { reply("reply", v); },
            function (e) { reply("error", String(e && e.message ? e.message : e)); });
    } catch (e) {
        reply("error", String(e && e.message ? e.message : e));
    }
}
EE2.setup(__gcHost);
"#;

/// GC_DEMO=price: made-up trade answers instead of the network.
const DEMO: &str = r#"
__gcHost.request = function (url) {
    var listing = function (i, amount, currency, account, hours, online) {
        return { id: "r" + i, listing: { indexed: new Date(Date.now() - hours * 3600000).toISOString(), price: { type: "~price", amount: amount, currency: currency }, account: { name: account, lastCharacterName: account, online: online ? { league: "Standard" } : null } }, item: { ilvl: 79 + (i % 3), properties: [] } };
    };
    var body = "{}";
    if (url.indexOf("/data/leagues") >= 0) body = JSON.stringify({ result: [{ id: "Standard", text: "Standard" }, { id: "Hardcore", text: "Hardcore" }, { id: "Rise of the Abyssal", text: "Rise of the Abyssal" }, { id: "HC Rise of the Abyssal", text: "Hardcore Rise of the Abyssal" }] });
    else if (url.indexOf("/data/") >= 0) body = JSON.stringify({ result: [] });
    else if (url.indexOf("/search/") >= 0) body = JSON.stringify({ id: "demo", total: 143, result: ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"] });
    else if (url.indexOf("/exchange/") >= 0) body = JSON.stringify({ id: "x1", total: 1, result: { r1: { id: "r1", listing: { indexed: new Date().toISOString(), account: { name: "Bulk1", lastCharacterName: "B", online: { league: "Standard" } }, offers: [{ exchange: { currency: "exalted", amount: 3 }, item: { currency: "x", amount: 1, stock: 20 } }] } } } });
    else if (url.indexOf("/fetch/") >= 0) body = JSON.stringify({ result: [
        listing(0, 1, "exalted", "Kestrel_Arrow", 0.2, true), listing(1, 2, "exalted", "VaalTrader", 1, true), listing(2, 2, "exalted", "VaalTrader", 1, true),
        listing(3, 3, "exalted", "Mireth", 3, false), listing(4, 5, "exalted", "Oriathan", 5, true), listing(5, 8, "exalted", "Doryani_Fan", 9, true),
        listing(6, 10, "exalted", "Sekhema", 20, false), listing(7, 1, "divine", "Azmeri", 26, true), listing(8, 1, "divine", "Ezomyte", 50, false),
        listing(9, 2, "divine", "Karui_King", 72, true)] });
    return Promise.resolve({ status: 200, headers: {}, body: body });
};
EE2.setup(__gcHost);
"#;

enum Event {
    Line(String),
    Answer(u64, Result<crate::poe2::Answer, String>),
    Closed,
}

/// `game-companion --poe2-kit`: runs until stdin closes or the parent goes.
pub fn main() -> i32 {
    match run(std::io::BufReader::new(std::io::stdin()), &mut std::io::stdout(), Some(unsafe { libc::getppid() })) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("game-companion: PoE 2 kit: {e}");
            1
        }
    }
}

type Requester = dyn Fn(&str, &str, &str) -> Result<crate::poe2::Answer, String> + Send + Sync;

fn run(input: impl BufRead + Send + 'static, out: &mut impl Write, parent: Option<i32>) -> Result<(), String> {
    run_with(input, out, parent, std::sync::Arc::new(|m: &str, u: &str, b: &str| crate::poe2::request(m, u, b)), "")
}

fn run_with(
    input: impl BufRead + Send + 'static,
    out: &mut impl Write,
    parent: Option<i32>,
    requester: std::sync::Arc<Requester>,
    extra: &str,
) -> Result<(), String> {
    use rquickjs::{Context, Function, Runtime};

    let rt = Runtime::new().map_err(|e| e.to_string())?;
    rt.set_memory_limit(768 * 1024 * 1024);
    rt.set_max_stack_size(8 * 1024 * 1024);
    let ctx = Context::full(&rt).map_err(|e| e.to_string())?;
    let said: Rc<RefCell<Vec<String>>> = Rc::new(RefCell::new(Vec::new()));
    let kit = KIT.strip_prefix(".pragma library").unwrap_or(KIT);
    ctx.with(|ctx| -> Result<(), String> {
        let g = ctx.globals();
        let s = said.clone();
        let send = Function::new(ctx.clone(), move |t: String| s.borrow_mut().push(t)).map_err(|e| e.to_string())?;
        g.set("__gcSend", send).map_err(|e| e.to_string())?;
        let read = Function::new(ctx.clone(), |p: String| crate::poe2::data_file(&p)).map_err(|e| e.to_string())?;
        g.set("__gcRead", read).map_err(|e| e.to_string())?;
        eval(&ctx, PRELUDE)?;
        eval(&ctx, kit)?;
        eval(&ctx, GLUE)?;
        if std::env::var("GC_DEMO").is_ok_and(|d| d.contains("price")) {
            eval(&ctx, DEMO)?;
        }
        if !extra.is_empty() {
            eval(&ctx, extra)?;
        }
        Ok(())
    })?;

    let (tx, rx) = mpsc::channel::<Event>();
    {
        let tx = tx.clone();
        std::thread::Builder::new()
            .name("poe2-kit-in".into())
            .spawn(move || {
                for line in input.lines() {
                    match line {
                        Ok(l) => {
                            if tx.send(Event::Line(l)).is_err() {
                                return;
                            }
                        }
                        Err(_) => break,
                    }
                }
                let _ = tx.send(Event::Closed);
            })
            .map_err(|e| e.to_string())?;
    }

    // Log lines go to the app (which writes the crash log), never the texts.
    let log = |out: &mut dyn Write, text: String| {
        let _ = writeln!(out, "{}", serde_json::json!({ "kind": "log", "value": text }));
        let _ = out.flush();
    };
    let mut timers: BTreeMap<(Instant, u64), ()> = BTreeMap::new();
    let mut ids: BTreeMap<u64, Instant> = BTreeMap::new();
    loop {
        // Promise jobs, then what the kit said.
        loop {
            match rt.execute_pending_job() {
                Ok(true) => continue,
                Ok(false) => break,
                Err(_) => continue,
            }
        }
        let lines: Vec<String> = said.borrow_mut().drain(..).collect();
        for line in lines {
            let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) else { continue };
            match v["kind"].as_str() {
                Some("request") => {
                    let rid = v["rid"].as_u64().unwrap_or(0);
                    let (url, method, body) = (str_of(&v["url"]), str_of(&v["method"]), str_of(&v["body"]));
                    log(out, format!("request {rid}: {method} {}", crate::poe2_object::endpoint(&url)));
                    let tx = tx.clone();
                    let requester = requester.clone();
                    std::thread::spawn(move || {
                        let _ = tx.send(Event::Answer(rid, requester(&method, &url, &body)));
                    });
                }
                Some("timer") => {
                    let tid = v["tid"].as_u64().unwrap_or(0);
                    let at = Instant::now() + Duration::from_millis(v["ms"].as_f64().unwrap_or(0.0).clamp(0.0, 3.6e6) as u64);
                    timers.insert((at, tid), ());
                    ids.insert(tid, at);
                }
                Some("cancel") => {
                    let tid = v["tid"].as_u64().unwrap_or(0);
                    if let Some(at) = ids.remove(&tid) {
                        timers.remove(&(at, tid));
                    }
                }
                Some("log") => log(out, format!("kit: {}", str_of(&v["value"]))),
                _ => {
                    if v["kind"] != "progress" {
                        log(out, format!("{} {}", str_of(&v["kind"]), v["id"]));
                    }
                    let _ = writeln!(out, "{line}");
                    let _ = out.flush();
                }
            }
        }
        if !said.borrow().is_empty() {
            continue;
        }

        // The next timer, an answer, a command, or a look at the parent.
        let now = Instant::now();
        if let Some((&(at, tid), _)) = timers.iter().next() {
            if at <= now {
                timers.remove(&(at, tid));
                ids.remove(&tid);
                log(out, format!("timer {tid} fired"));
                ctx.with(|ctx| call(&ctx, "__gcFire", (tid as f64,)));
                continue;
            }
        }
        let wait = timers.keys().next().map(|(at, _)| at.saturating_duration_since(now)).unwrap_or(Duration::from_secs(5)).min(Duration::from_secs(5));
        match rx.recv_timeout(wait) {
            Ok(Event::Line(l)) => {
                let what = serde_json::from_str::<serde_json::Value>(&l).ok().map(|v| format!("{} {}", str_of(&v["fn"]), v["id"])).unwrap_or_default();
                log(out, format!("call {what}"));
                ctx.with(|ctx| call(&ctx, "__gcCommand", (l,)))
            }
            Ok(Event::Answer(rid, answer)) => {
                let (status, headers, body) = match answer {
                    Ok(a) => (f64::from(a.status), serde_json::Value::Object(a.headers).to_string(), a.body),
                    Err(e) => (0.0, "{}".to_string(), e),
                };
                if status == 0.0 {
                    log(out, format!("request {rid}: no answer: {body}"));
                } else {
                    log(out, format!("request {rid}: HTTP {status}, {} bytes; answer into the kit", body.len()));
                }
                ctx.with(|ctx| call(&ctx, "__gcAnswer", (rid as f64, status, headers, body)));
            }
            Ok(Event::Closed) | Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if let Some(p) = parent {
                    if unsafe { libc::getppid() } != p {
                        return Ok(());
                    }
                }
            }
        }
    }
}

fn str_of(v: &serde_json::Value) -> String {
    v.as_str().unwrap_or("").to_string()
}

fn eval(ctx: &rquickjs::Ctx<'_>, code: &str) -> Result<(), String> {
    use rquickjs::CatchResultExt;
    ctx.eval::<(), _>(code).catch(ctx).map_err(|e| e.to_string())
}

fn call<A: for<'js> rquickjs::function::IntoArgs<'js>>(ctx: &rquickjs::Ctx<'_>, name: &str, args: A) {
    use rquickjs::CatchResultExt;
    let f: rquickjs::Result<rquickjs::Function> = ctx.globals().get(name);
    if let Ok(f) = f {
        if let Err(e) = f.call::<_, ()>(args).catch(ctx) {
            eprintln!("poe2 kit: {name}: {e}");
        }
    }
}

// --- The app's side: one child, started when first needed. -------------

struct Kit {
    child: Child,
    stdin: ChildStdin,
}

static KIT_PROCESS: Mutex<Option<Kit>> = Mutex::new(None);
/// Which child is the current one: an old child's end, told late, must
/// not cancel the calls of the one started after it.
static GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Sends one command line to the kit, starting it if needed. `said` gets
/// every line it writes back, `gone` is called when it ends (crashed or
/// stopped). Call from the Qt thread: PR_SET_PDEATHSIG follows the thread
/// that started the child.
pub fn send(line: &str, said: impl Fn(String) + Send + 'static, gone: impl FnOnce(String) + Send + 'static) -> Result<(), String> {
    let mut slot = KIT_PROCESS.lock().map_err(|_| "kit lock".to_string())?;
    let (alive, ended) = match slot.as_mut() {
        Some(k) => match k.child.try_wait() {
            Ok(None) => (true, None),
            Ok(Some(status)) => (false, Some(status.to_string())),
            Err(e) => (false, Some(e.to_string())),
        },
        None => (false, None),
    };
    if !alive {
        if let Some(how) = ended {
            crate::log::write("poe2", &format!("kit ended ({how}); kit restarted"));
        }
        *slot = Some(start(said, gone)?);
    }
    let k = slot.as_mut().ok_or("no kit")?;
    writeln!(k.stdin, "{line}").and_then(|_| k.stdin.flush()).map_err(|e| format!("kit: {e}"))
}

/// Ends the kit (on quit; it would end with the app anyway).
pub fn stop() {
    if let Ok(mut slot) = KIT_PROCESS.lock() {
        if let Some(mut k) = slot.take() {
            drop(k.stdin);
            let _ = k.child.kill();
            let _ = k.child.wait();
        }
    }
}

fn start(said: impl Fn(String) + Send + 'static, gone: impl FnOnce(String) + Send + 'static) -> Result<Kit, String> {
    use std::os::unix::process::CommandExt;
    let mut cmd = Command::new("/proc/self/exe");
    cmd.arg("--poe2-kit").stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit());
    unsafe {
        cmd.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL);
            Ok(())
        });
    }
    let mut child = cmd.spawn().map_err(|e| format!("PoE 2 kit: {e}"))?;
    let generation = GENERATION.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
    crate::log::write("poe2", &format!("kit started (pid {})", child.id()));
    let stdin = child.stdin.take().ok_or("kit stdin")?;
    let stdout = child.stdout.take().ok_or("kit stdout")?;
    std::thread::Builder::new()
        .name("poe2-kit-out".into())
        .spawn(move || {
            for line in std::io::BufReader::new(stdout).lines() {
                match line {
                    Ok(l) => {
                        // The kit's log lines go to the crash log, the rest to QML.
                        if l.starts_with(r#"{"kind":"log""#) {
                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&l) {
                                crate::log::write("poe2", v["value"].as_str().unwrap_or(""));
                            }
                        } else {
                            said(l);
                        }
                    }
                    Err(_) => break,
                }
            }
            crate::log::write("poe2", &format!("kit ended (its output closed, generation {generation})"));
            if GENERATION.load(std::sync::atomic::Ordering::SeqCst) == generation {
                gone("its process ended".into());
            }
        })
        .map_err(|e| e.to_string())?;
    Ok(Kit { child, stdin })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The kit runs in QuickJS: an item is read, a search runs against
    /// made-up trade answers (as tools/poe2-ee2/test/run.js under Node).
    /// The kit's output for a test: kept whole, and each line's id sent on
    /// when it is a reply or an error.
    struct Lines {
        seen: std::sync::mpsc::Sender<u64>,
        text: String,
        part: String,
    }

    impl Write for Lines {
        fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
            self.part.push_str(&String::from_utf8_lossy(b));
            while let Some(end) = self.part.find('\n') {
                let line: String = self.part.drain(..=end).collect();
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) {
                    if v["kind"] == "reply" || v["kind"] == "error" {
                        if let Some(id) = v["id"].as_u64() {
                            let _ = self.seen.send(id);
                        }
                    }
                }
                self.text.push_str(&line);
            }
            Ok(b.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    /// Waits up to 60 s for the answer to call `id` (the assertions then
    /// say what is missing).
    fn wait_for(answers: &std::sync::mpsc::Receiver<u64>, id: u64) {
        let until = std::time::Instant::now() + Duration::from_secs(60);
        while let Some(left) = until.checked_duration_since(std::time::Instant::now()) {
            match answers.recv_timeout(left) {
                Ok(n) if n == id => return,
                Ok(_) => {}
                Err(_) => return,
            }
        }
    }

    #[test]
    fn kit_runs_in_quickjs() {
        let item = "Item Class: Bows\nRarity: Rare\nOblivion Strike\nRider Bow\n--------\nPhysical Damage: 36-61\nCritical Hit Chance: 5.00%\nAttacks per Second: 1.20\n--------\nRequires: Level 51, 103 (augmented) Dex\n--------\nItem Level: 80\n--------\n+57 to Accuracy Rating\n15% increased Light Radius\n";
        let cmds = [
            serde_json::json!({ "id": 1, "fn": "leagues", "args": ["Runes of Aldur"] }),
            serde_json::json!({ "id": 2, "fn": "check", "args": [item, "Runes of Aldur"] }),
            serde_json::json!({ "id": 3, "fn": "search", "args": [] }),
        ];
        let lines: Vec<String> = cmds.iter().map(|c| c.to_string() + "\n").collect();
        let requester = std::sync::Arc::new(|_m: &str, url: &str, _b: &str| {
            let body = if url.contains("/data/leagues") {
                // The real order: the saved league is not the third (QA, 0.8.45).
                r#"{"result":[{"id":"Runes of Aldur","text":"Runes of Aldur"},{"id":"HC Runes of Aldur","text":"HC Runes of Aldur"},{"id":"Standard","text":"Standard"},{"id":"Hardcore","text":"Hardcore"}]}"#.to_string()
            } else if url.contains("/data/") {
                r#"{"result":[]}"#.to_string()
            } else if url.contains("/search/") {
                r#"{"id":"q1","total":1,"result":["a"]}"#.to_string()
            } else if url.contains("/fetch/") {
                r#"{"result":[{"id":"a","listing":{"indexed":"2026-11-15T10:00:00Z","price":{"type":"~price","amount":3,"currency":"exalted"},"account":{"name":"S","lastCharacterName":"C","online":{"league":"Standard"}}},"item":{"ilvl":80,"properties":[]}}]}"#.to_string()
            } else {
                "{}".to_string()
            };
            Ok(crate::poe2::Answer { status: 200, headers: serde_json::Map::new(), body })
        });
        // Each line goes in once the one before answered; stdin closes after
        // the search's answer (fixed sleeps were too short under a full,
        // parallel `cargo test`: QA, 0.8.48).
        let (mut w, r) = std::os::unix::net::UnixStream::pair().unwrap();
        let (seen, answers) = std::sync::mpsc::channel();
        let feeder = std::thread::spawn(move || {
            for (n, l) in lines.into_iter().enumerate() {
                std::io::Write::write_all(&mut w, l.as_bytes()).unwrap();
                wait_for(&answers, n as u64 + 1);
            }
            drop(w);
        });
        let mut out = Lines { seen, text: String::new(), part: String::new() };
        run_with(std::io::BufReader::new(r), &mut out, None, requester, "").unwrap();
        feeder.join().unwrap();
        let out = out.text.into_bytes();
        let text = String::from_utf8(out).unwrap();
        let replies: Vec<serde_json::Value> = text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
        let reply = |id: u64| replies.iter().rev().find(|v| v["id"] == id && v["kind"] == "reply").cloned();
        let leagues = reply(1).unwrap_or_else(|| panic!("no leagues reply in {text}"));
        assert_eq!(leagues["value"]["selected"], "Runes of Aldur", "{leagues}");
        let check = reply(2).unwrap_or_else(|| panic!("no check reply in {text}"));
        assert_eq!(check["value"]["name"], "Rider Bow");
        let search = reply(3).unwrap_or_else(|| panic!("no search reply in {text}"));
        assert_eq!(search["value"]["total"], 1, "{search}");
    }

    /// tools/poe2-ee2/test/run.js in QuickJS: EE2's 27 sample items, two
    /// searches with the trade site's real limit headers, a currency.
    #[test]
    fn sample_items_in_quickjs() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tools/poe2-ee2/test/");
        let script = std::fs::read_to_string(format!("{dir}run.js")).unwrap();
        let items = std::fs::read_to_string(format!("{dir}items.json")).unwrap();
        let extra = format!(
            "{script}\nrun(EE2, __gcHost, {items}, function (t) {{ __gcOut({{ id: 0, kind: \"log\", value: String(t) }}); }}, function (ok) {{ __gcOut({{ id: 0, kind: \"reply\", value: ok }}); }});"
        );
        let (w, r) = std::os::unix::net::UnixStream::pair().unwrap();
        let (seen, answers) = std::sync::mpsc::channel();
        let closer = std::thread::spawn(move || {
            wait_for(&answers, 0);
            drop(w);
        });
        let mut out = Lines { seen, text: String::new(), part: String::new() };
        let none = std::sync::Arc::new(|_m: &str, _u: &str, _b: &str| Err::<crate::poe2::Answer, String>("run.js answers".into()));
        run_with(std::io::BufReader::new(r), &mut out, None, none, &extra).unwrap();
        closer.join().unwrap();
        let text = out.text;
        assert!(text.contains(r#"{"id":0,"kind":"reply","value":true}"#), "{text}");
    }
}
