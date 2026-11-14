// Game Companion voice overlay: Legcord's main-process part.
//
// It passes what the Discord page's part (renderer.js) reports on to Game
// Companion over a Unix socket in $XDG_RUNTIME_DIR. No TCP port: Legcord
// cancels WebSockets to localhost, and the page's CSP may forbid them.
// The page reaches this part through a DevTools binding (`gcVoice`), or a
// tagged console line when the binding cannot be added.
// Avatars are fetched through Legcord's own session (Discord's CDN, which
// Legcord loads them from anyway) and handed on as small PNGs.
import net from "node:net";
import path from "node:path";
import fs from "node:fs";

const PLUGIN = 1;
const TAG = "\u0001gcvoice ";
const CDN = "cdn.discordapp.com";

export default function activate(api) {
  const { app, BrowserWindow } = api.electron;
  const dir = process.env.XDG_RUNTIME_DIR || "";
  const sockPath = dir ? path.join(dir, "game-companion-voice.sock") : "";
  let sock = null;
  let ready = false;
  let retry = null;
  let stopped = false;
  let last = "";
  let hello = null;
  const pictures = new Map(); // hash -> base64, kept while Legcord runs
  const asked = new Set();
  const windows = new Set();

  function send(obj) {
    if (!ready || !sock) return;
    try { sock.write(JSON.stringify(obj) + "\n"); } catch (e) { /* reconnects */ }
  }

  function connect() {
    retry = null;
    if (stopped || !sockPath) return;
    // Game Companion not running: try again later, no busy loop.
    if (!fs.existsSync(sockPath)) { retry = setTimeout(connect, 5000); return; }
    const s = net.createConnection(sockPath);
    s.on("connect", () => {
      sock = s; ready = true;
      send({ t: "hello", plugin: PLUGIN, legcord: app.getVersion() });
      if (hello) send(hello);
      if (last) sock.write(last + "\n");
      for (const [hash, png] of pictures) send({ t: "picture", hash, png });
    });
    s.on("data", () => {});
    s.on("error", () => {});
    s.on("close", () => {
      if (sock === s) { sock = null; ready = false; }
      if (!stopped && !retry) retry = setTimeout(connect, 5000);
    });
  }

  async function picture(id, hash) {
    if (!/^\d{5,25}$/.test(String(id)) || !/^(a_)?[0-9a-f]{32}$/.test(String(hash))) return;
    if (asked.has(hash)) return;
    asked.add(hash);
    const url = `https://${CDN}/avatars/${id}/${hash}.png?size=64`;
    try {
      const win = [...windows][0];
      const ses = win && !win.isDestroyed() ? win.webContents.session : null;
      const res = ses ? await ses.fetch(url) : await fetch(url);
      if (!res.ok) return;
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length > 200000) return;
      const png = buf.toString("base64");
      pictures.set(hash, png);
      send({ t: "picture", hash, png });
    } catch (e) {
      asked.delete(hash);
    }
  }

  function take(text) {
    let m;
    try { m = JSON.parse(text); } catch (e) { return; }
    if (!m || typeof m !== "object") return;
    if (m.t === "state") {
      last = JSON.stringify(m);
      if (ready) sock.write(last + "\n");
      for (const u of m.members || []) if (u.avatar) picture(u.id, u.avatar);
    } else if (m.t === "check") {
      hello = m;
      send(m);
    }
  }

  function attach(win) {
    if (windows.has(win)) return;
    windows.add(win);
    const wc = win.webContents;
    // Electron 35+ hands one event with `message`; older ones a third argument.
    const onConsole = function (e) {
      const msg = e && typeof e.message === "string" ? e.message : arguments[2];
      if (typeof msg === "string" && msg.startsWith(TAG)) take(msg.slice(TAG.length));
    };
    wc.on("console-message", onConsole);
    const bind = () => {
      try {
        if (!wc.debugger.isAttached()) wc.debugger.attach("1.3");
        wc.debugger.sendCommand("Runtime.addBinding", { name: "gcVoice" }).catch(() => {});
      } catch (e) {
        api.logger.warn("no binding, using the console:", String(e));
      }
    };
    const onMessage = (_e, method, params) => {
      if (method === "Runtime.bindingCalled" && params && params.name === "gcVoice") take(params.payload);
    };
    wc.debugger.on("message", onMessage);
    // DevTools opened or the page reloaded: bound again.
    wc.debugger.on("detach", () => setTimeout(() => { if (!wc.isDestroyed()) bind(); }, 2000));
    wc.on("did-start-navigation", (_e, _u, inPlace, mainFrame) => { if (mainFrame && !inPlace) bind(); });
    bind();
    win.on("closed", () => windows.delete(win));
    api.onCleanup(() => {
      wc.off?.("console-message", onConsole);
      try { wc.debugger.off?.("message", onMessage); if (wc.debugger.isAttached()) wc.debugger.detach(); } catch (e) {}
    });
  }

  for (const w of BrowserWindow.getAllWindows()) attach(w);
  const onCreated = (_e, w) => attach(w);
  app.on("browser-window-created", onCreated);
  connect();
  api.onCleanup(() => {
    stopped = true;
    app.off("browser-window-created", onCreated);
    if (retry) clearTimeout(retry);
    if (sock) sock.destroy();
  });
}
