// poe.ninja's PoE 2 currency prices (MN, 2026-11-15: on by default, can be
// switched off). One request per league, kept 30 minutes, asked only when
// an item is checked: the currency exchange's overview
//   https://poe.ninja/poe2/api/economy/exchange/current/overview?league=<league>&type=Currency
// which answers { core: { rates: { exalted, chaos }, primary: "divine" },
// lines: [{ id, primaryValue (in divines), sparkline: { totalChange } }],
// items: [{ id, name }] } (MN's copy of 2026-11-15, Runes of Aldur).
// The ids are the trade site's currency ids ("exalted", "annul" …).
import { host } from "./shims/host";

const KEEP_MS = 30 * 60 * 1000;
const RETRY_MS = 4 * 60 * 1000;

interface Table {
  league: string;
  at: number;
  exalted: number; // exalted orbs per divine
  chaos: number;
  byId: Record<string, { div: number; change: number | null; name: string }>;
  byName: Record<string, string>;
}

let table: Table | null = null;
let asking: Promise<Table | null> | null = null;
let askedLeague = "";
let failedAt = 0;
export let lastError = "";

/** Reads poe.ninja's answer (exported for the tests). */
export function readOverview(league: string, text: string): Table {
  const d = JSON.parse(text);
  const rates = (d && d.core && d.core.rates) || {};
  const t: Table = { league, at: Date.now(), exalted: Number(rates.exalted) || 0, chaos: Number(rates.chaos) || 0, byId: {}, byName: {} };
  const names: Record<string, string> = {};
  const items = (d && d.items) || [];
  for (let i = 0; i < items.length; i++) if (items[i] && items[i].id) names[items[i].id] = String(items[i].name || "");
  const lines = (d && d.lines) || [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (!l || !l.id || typeof l.primaryValue !== "number") continue;
    const change = l.sparkline && typeof l.sparkline.totalChange === "number" ? l.sparkline.totalChange : null;
    t.byId[l.id] = { div: l.primaryValue, change, name: names[l.id] || "" };
    if (names[l.id]) t.byName[names[l.id]] = l.id;
  }
  if (!t.byId.divine) t.byId.divine = { div: 1, change: null, name: "Divine Orb" };
  if (!t.exalted || !Object.keys(t.byId).length) throw new Error("poe.ninja sent no prices");
  return t;
}

/** The league's prices, from memory or asked (null when it fails). */
export function load(league: string): Promise<Table | null> {
  const now = Date.now();
  if (table && table.league === league && now - table.at < KEEP_MS) return Promise.resolve(table);
  if (asking && askedLeague === league) return asking;
  if (askedLeague === league && now - failedAt < RETRY_MS) return Promise.resolve(table && table.league === league ? table : null);
  askedLeague = league;
  const url = "https://poe.ninja/poe2/api/economy/exchange/current/overview?league=" + encodeURIComponent(league) + "&type=Currency";
  asking = host.request(url, "GET", "").then((r) => {
    if (r.status !== 200) throw new Error("poe.ninja answered " + r.status);
    table = readOverview(league, r.body);
    lastError = "";
    return table;
  }).catch((e: any) => {
    failedAt = Date.now();
    lastError = String((e && e.message) || e);
    host.log("poe.ninja: " + lastError);
    return table && table.league === league ? table : null;
  }).then((t) => { asking = null; return t; });
  return asking;
}

/** The prices as they are now, without asking (null if not there). */
export function known(league: string): Table | null {
  return table && table.league === league ? table : null;
}

/**
 * A price in exalted orbs, or in divines from one divine up (as poe.ninja
 * and EE2 show it); null when a currency is not known or is the same.
 */
export function normalised(t: Table | null, amount: number, currency: string): { amount: number; currency: string } | null {
  if (!t || !(amount > 0)) return null;
  const v = t.byId[currency];
  if (!v) return null;
  const div = amount * v.div;
  const out = div >= 1 ? { amount: div, currency: "divine" } : { amount: div * t.exalted, currency: "exalted" };
  return out.currency === currency ? null : out;
}

/** poe.ninja's price of one currency item by its name, if it is listed. */
export function priceOf(t: Table | null, name: string): any {
  if (!t) return null;
  const id = t.byName[name];
  const v = id ? t.byId[id] : null;
  if (!v) return null;
  return { id, div: v.div, exalted: v.div * t.exalted, chaos: v.div * t.chaos, change: v.change, league: t.league };
}
