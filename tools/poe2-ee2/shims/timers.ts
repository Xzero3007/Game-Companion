// setTimeout for QML's JavaScript (it has none): the host's timers.
import { host } from "./host";
import { makeIndex } from "./indexes";
export function setTimeout(cb: () => void, ms?: number) { return host.timer(ms || 0, cb); }
export function clearTimeout(id: number) { if (id) host.cancel(id); }
export const performance = { now: () => Date.now(), mark() {}, measure() {} };
export class AbortController { signal = { aborted: false }; abort() { this.signal.aborted = true; } }
// EE2's data loader asks `fetch` for its files: they come from the host.
export function fetch(url: string) {
  const path = String(url).replace(/^.*?data\//, "");
  const bin = /^(.*\/)((items|stats)-[a-z]+\.index\.bin)$/.exec(path);
  const text = bin ? "" : host.readData(path);
  return Promise.resolve({
    ok: true,
    text: () => Promise.resolve(text),
    json: () => Promise.resolve(JSON.parse(text)),
    arrayBuffer: () => Promise.resolve(bin ? makeIndex(bin[2], host.readData(bin[1] + bin[3] + ".ndjson")) : new ArrayBuffer(0)),
  });
}
// EE2's background refreshers (trade data every 30 min) do not run: nothing
// ticks while idle; the data is asked again when an item is checked.
export function setInterval(_cb: () => void, _ms?: number) { return 0; }
export function clearInterval(_id: number) {}

// Named groups: Qt 6.4 reads `(?<name>…)` but gives a match no `groups`
// (and its built-ins cannot be replaced). build.mjs turns `a.match(re)` and
// `re.exec(a)` in EE2's files into these, which fill `groups` in from the
// expression's source where it is missing.
const groupNames: Record<string, Array<string | null>> = {};
function namesOf(src: string) {
  if (groupNames[src]) return groupNames[src];
  const out: Array<string | null> = [];
  let inClass = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") { i++; continue; }
    if (inClass) { if (c === "]") inClass = false; continue; }
    if (c === "[") { inClass = true; continue; }
    if (c !== "(") continue;
    if (src[i + 1] !== "?") { out.push(null); continue; }
    if (src[i + 2] === "<" && src[i + 3] !== "=" && src[i + 3] !== "!") out.push(src.slice(i + 3, src.indexOf(">", i)));
  }
  groupNames[src] = out;
  return out;
}
function withGroups(m: any, re: any) {
  if (!m || m.groups !== undefined || !(re instanceof RegExp) || re.source.indexOf("(?<") < 0) return m;
  const g: Record<string, string> = {};
  namesOf(re.source).forEach((name, i) => { if (name) g[name] = m[i + 1]; });
  m.groups = g;
  return m;
}
export function __gcMatch(s: any, re: any) {
  const m = s.match(re);
  return re instanceof RegExp && !re.global ? withGroups(m, re) : m;
}
export function __gcExec(re: any, s: any) {
  return withGroups(re.exec(s), re);
}
