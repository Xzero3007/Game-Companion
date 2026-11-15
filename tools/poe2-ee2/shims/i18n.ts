// vue-i18n's `useI18n`: the English texts of EE2's app_i18n.json.
import { host } from "./host";
let messages: any = null;
function lookup(path: string): string {
  if (!messages) { try { messages = JSON.parse(host.readData("en/app_i18n.json")); } catch (e) { messages = {}; } }
  let v: any = messages;
  for (const p of path.split(".")) { v = v && v[p]; }
  return typeof v === "string" ? v : path;
}
function t(path: string, args?: any) {
  let s = lookup(path);
  if (args && typeof args === "object") for (const k in args) s = s.split("{" + k + "}").join(String(args[k]));
  if (Array.isArray(args)) args.forEach((a, i) => { s = s.split("{" + i + "}").join(String(a)); });
  return s;
}
export function useI18n() { return { t }; }
export function useI18nNs(name: string) {
  return { t: (path: string, ...args: any[]) => t(path.startsWith(":") ? path.replace(":", name + ".") : path, ...args) };
}
export function createI18n() { return { global: { t } }; }
