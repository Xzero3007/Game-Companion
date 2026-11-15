// Stands in for EE2's web/background/IPC.ts: requests go to the host
// (Game Companion's Rust side, curl, allowed hosts only).
import { host } from "./host";

class Headers2 {
  private map: Record<string, string> = {};
  constructor(obj: Record<string, string>) {
    for (const k in obj) this.map[k.toLowerCase()] = obj[k];
  }
  get(k: string) { const v = this.map[k.toLowerCase()]; return v === undefined ? null : v; }
  has(k: string) { return this.map[k.toLowerCase()] !== undefined; }
  [Symbol.iterator]() { return Object.keys(this.map).map((k) => [k, this.map[k]])[Symbol.iterator](); }
}

export const Host = {
  isElectron: false,
  proxy(url: string, init?: { method?: string; headers?: Record<string, string>; body?: string; signal?: unknown }) {
    return host.request("https://" + url, init && init.method ? init.method : "GET", init && init.body ? init.body : "").then((r) => ({
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      headers: new Headers2(r.headers || {}),
      text: () => Promise.resolve(r.body),
      json: () => Promise.resolve(JSON.parse(r.body)),
    }));
  },
  sendEvent() {},
  onEvent() {},
};
export const MainProcess = Host;
