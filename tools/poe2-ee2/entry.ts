// Game Companion's door into Exiled Exchange 2's price check (MIT,
// github.com/Kvan7/Exiled-Exchange-2): EE2's own parser, filters and trade
// requests, bundled by build.mjs into qml/poe2/ee2kit.js. Only this file
// and shims/ are Game Companion's; everything under @/ is EE2's unchanged
// (apart from the few patches build.mjs lists).
import { setHost, HostApi } from "./shims/host";
import { setLanguage, setLeague, AppConfig } from "./shims/config";
import * as Data from "@/assets/data";
import { parseClipboard, ParsedItem, ItemRarity, ItemCategory } from "@/parser";
import { createPresets } from "@/web/price-check/filters/create-presets";
import type { FilterPreset, ItemFilters, StatFilter } from "@/web/price-check/filters/interfaces";
import { apiToSatisfySearch } from "@/web/price-check/trade/common";
import { execBulkSearch } from "@/web/price-check/trade/pathofexile-bulk";
import {
  CATEGORY_TO_TRADE_ID,
  createTradeRequest,
  requestTradeResultList,
  requestResults,
  PricingResult,
} from "@/web/price-check/trade/pathofexile-trade";
import { useLeagues } from "@/web/background/Leagues";
import { useI18n } from "./shims/i18n";

// The languages whose data Game Companion ships, told apart by the copied
// text's first line (as EE2's own LANGUAGE_DETECTOR does).
const LANGUAGES = [
  { lang: "en", itemClass: "Item Class: ", rarity: "Rarity: " },
  { lang: "de", itemClass: "Gegenstandsklasse: ", rarity: "Seltenheit: " },
];

let loaded = "";
let leaguesLoaded = false;

export function setup(h: HostApi) {
  setHost(h);
}

/** The language of a copied text, or "" when it is no item of a known one. */
export function languageOf(text: string): string {
  const lines = String(text || "").split(/\r?\n/);
  for (const l of LANGUAGES) {
    for (const line of lines.slice(0, 2)) {
      if (line.indexOf(l.itemClass) === 0 || line.indexOf(l.rarity) === 0) return l.lang;
    }
  }
  return "";
}

/** Whether a text looks like an item copied in the game (Ctrl+C). */
export function looksLikeItem(text: string): boolean {
  return languageOf(text) !== "" && String(text).indexOf("--------") > 0;
}

async function load(lang: string) {
  if (loaded === lang) return;
  setLanguage(lang);
  if (!loaded) await Data.init(lang);
  else await Data.loadForLang(lang);
  loaded = lang;
}

/** The trade site's leagues (asked once), and the chosen one. */
export async function leagues(chosen: string): Promise<{ list: Array<{ id: string; text: string }>; selected: string; error: string }> {
  const l = useLeagues();
  if (chosen) setLeague(chosen);
  if (!leaguesLoaded || l.error.value) {
    await l.load();
    leaguesLoaded = !l.error.value;
  }
  // A saved league that the trade site lists stays chosen: EE2's load()
  // replaced it by the list's third entry when its computed selectedId read
  // stale (QA, 0.8.45: "Runes of Aldur" became Standard).
  const listed = l.list.value.some((x) => x.id === chosen);
  if (chosen && listed) setLeague(chosen);
  return {
    list: l.list.value.map((x) => ({ id: x.id, text: x.text })),
    selected: chosen && listed ? chosen : l.selectedId.value || "",
    error: l.error.value || "",
  };
}

interface Checked {
  item: ParsedItem;
  presets: { active: string; presets: FilterPreset[] };
  run: number;
}
let current: Checked | null = null;

function preset(c: Checked): FilterPreset {
  return c.presets.presets.find((p) => p.id === c.presets.active)!;
}

/**
 * Reads a copied item and makes EE2's filters for it. Resolves to the
 * view (`view`) or { error }.
 */
export async function check(text: string, league: string): Promise<any> {
  const lang = languageOf(text);
  if (!lang) return { error: "not_an_item" };
  await load(lang);
  const lg = await leagues(league);
  if (!lg.selected) return { error: "leagues", detail: lg.error };
  const parsed = parseClipboard(text);
  if (parsed.isErr()) return { error: parsed.error };
  const item = parsed.value;
  const presets = createPresets(item, {
    league: lg.selected,
    currency: undefined,
    listingType: undefined,
    collapseListings: "app",
    activateStockFilter: false,
    searchStatRange: AppConfig("price-check").searchStatRange,
    useEn: true,
    defaultAllSelected: false,
  });
  current = { item, presets, run: 0 };
  const f = preset(current).filters;
  if (api(current) === "bulk") f.trade.listingType = "online";
  return view();
}

function api(c: Checked) {
  const p = preset(c);
  return apiToSatisfySearch(c.item, p.stats, p.filters);
}

/** Whether EE2 would search at once (uniques, unidentified and the like). */
function searchesAtOnce(item: ParsedItem) {
  return Boolean(
    item.rarity === ItemRarity.Unique ||
      item.category === ItemCategory.Charm ||
      !CATEGORY_TO_TRADE_ID.has(item.category!) ||
      item.isUnidentified ||
      item.isVeiled,
  );
}

const NUMERIC: Array<[keyof ItemFilters, string]> = [
  ["itemLevel", "Item level"],
  ["quality", "Quality"],
  ["gemLevel", "Gem level"],
  ["mapTier", "Tier"],
  ["areaLevel", "Area level"],
  ["socketNumber", "Sockets"],
  ["augmentSockets", "Rune sockets"],
  ["stackSize", "Stack"],
  ["awardedAscendancyPoints", "Ascendancy points"],
];

const RARITY: Record<string, string> = { nonunique: "Not unique", normal: "Normal", magic: "Magic", rare: "Rare", unique: "Unique", uniquefoil: "Foil unique" };

/** What QML shows: the item, its filters and whether it searches at once. */
export function view(): any {
  const c = current;
  if (!c) return null;
  const p = preset(c);
  const f = p.filters;
  const it = c.item;
  const filters = [] as any[];
  for (const [key, label] of NUMERIC) {
    const v = f[key] as any;
    if (v && typeof v.value === "number") filters.push({ key, label, value: v.value, max: v.max === undefined ? null : v.max, disabled: !!v.disabled });
  }
  if (f.corrupted) filters.push({ key: "corrupted", label: f.corrupted.value ? "Corrupted" : "Not corrupted", value: null, max: null, disabled: false, fixed: true });
  if (f.unidentified) filters.push({ key: "unidentified", label: "Unidentified", value: null, max: null, disabled: !!f.unidentified.disabled });
  if (f.rarity && f.rarity.value) filters.push({ key: "rarity", label: RARITY[f.rarity.value] || f.rarity.value, value: null, max: null, disabled: false, fixed: true });
  return {
    name: it.info.name,
    refName: it.info.refName,
    baseType: it.info.namespace === "UNIQUE" ? (it.info.unique ? it.info.unique.base : "") : "",
    rarity: it.rarity || "",
    category: it.category || "",
    itemLevel: it.itemLevel || 0,
    corrupted: !!it.isCorrupted,
    unidentified: !!it.isUnidentified,
    searchName: f.searchExact ? (f.searchExact.name || f.searchExact.baseType || "") : "",
    presets: c.presets.presets.map((x) => ({ id: x.id, active: x.id === c.presets.active })),
    api: api(c),
    atOnce: searchesAtOnce(it),
    filters,
    stats: p.stats.map((s: StatFilter, i: number) => ({
      index: i,
      text: s.text,
      tag: s.tag,
      hidden: s.hidden ? hiddenWhy(s.hidden) : "",
      disabled: !!s.disabled,
      value: s.roll ? s.roll.value : null,
      min: s.roll && typeof s.roll.min === "number" ? s.roll.min : null,
      max: s.roll && typeof s.roll.max === "number" ? s.roll.max : null,
      option: s.option ? s.option.value : null,
    })),
  };
}

// EE2's reasons for leaving a line out of the search at first, in its words.
function hiddenWhy(key: string) {
  const text = useI18n().t(key);
  return text && text !== key ? text : "left out at first";
}

/** Switches a stat line on or off; `min`/`max` (numbers or null) narrow it. */
export function setStat(index: number, disabled: boolean, min?: number | null, max?: number | null) {
  if (!current) return view();
  const s = preset(current).stats[index];
  if (!s) return view();
  s.disabled = disabled;
  if (s.roll && min !== undefined) s.roll.min = min === null ? "" : min;
  if (s.roll && max !== undefined) s.roll.max = max === null ? "" : max;
  return view();
}

/** Switches an item filter (item level, quality …) on or off, or sets its value. */
export function setFilter(key: string, disabled: boolean, value?: number) {
  if (!current) return view();
  const f = preset(current).filters as any;
  const v = f[key];
  if (v && typeof v === "object") {
    if ("disabled" in v || typeof v.value === "number") v.disabled = disabled;
    if (typeof value === "number" && typeof v.value === "number") v.value = value;
  }
  return view();
}

export function setPreset(id: string) {
  if (current && current.presets.presets.some((p) => p.id === id)) current.presets.active = id;
  return view();
}

function trade(r: any) {
  return {
    amount: r.priceAmount,
    currency: r.priceCurrency,
    times: r.listedTimes || 1,
    stack: r.stackSize || 0,
    account: r.accountName,
    status: r.accountStatus,
    age: r.relativeDate,
    itemLevel: r.itemLevel || "",
    quality: r.quality || "",
    level: r.level || "",
    corrupted: !!r.corrupted,
    instant: !!r.isInstantBuyout,
    mine: !!r.isMine,
  };
}

/**
 * Searches the trade site for the checked item with the filters as they
 * are. `update(result)` gets each step (listings come in tens).
 */
export async function search(update: (r: any) => void): Promise<any> {
  const c = current;
  if (!c) return { error: "nothing" };
  const run = ++c.run;
  const p = preset(c);
  const kind = api(c);
  if (kind === "bulk") {
    try {
      const have = ["exalted", "divine"];
      const res = await execBulkSearch(c.item, p.filters, have, { accountName: AppConfig().accountName });
      if (run !== c.run || current !== c) return null;
      const out = {
        kind,
        done: true,
        groups: res.filter((g) => g).map((g) => ({
          have: g!.haveTag,
          total: g!.total,
          listed: g!.listed.map((r) => ({
            rate: r.itemAmount ? r.exchangeAmount / r.itemAmount : 0,
            exchangeAmount: r.exchangeAmount,
            itemAmount: r.itemAmount,
            stock: r.stock,
            account: r.accountName,
            status: r.accountStatus,
            age: r.relativeDate,
            mine: r.isMine,
          })),
        })),
      };
      update(out);
      return out;
    } catch (e) {
      const out = { kind, done: true, error: String((e as Error).message || e) };
      update(out);
      return out;
    }
  }
  // As EE2's trade-api.ts (useTradeApi), without Vue's computed values:
  // the first twenty at once, then tens until enough sellers show.
  const fetched: PricingResult[] = [];
  let total = 0;
  const snapshot = (done: boolean, error = "") => ({ kind, done, error, total, listed: grouped(fetched).map(trade) });
  try {
    const result = await requestTradeResultList(createTradeRequest(p.filters, p.stats, c.item), p.filters.trade.league);
    if (run !== c.run || current !== c) return null;
    total = result.total;
    update(snapshot(false));
    const opts = { accountName: AppConfig().accountName };
    const r1 = result.result.length > 0 ? requestResults(result.id, result.result.slice(0, 10), opts) : Promise.resolve([] as PricingResult[]);
    const r2 = result.result.length > 10 ? requestResults(result.id, result.result.slice(10, 20), opts) : Promise.resolve([] as PricingResult[]);
    const first = await r1;
    fetched.push(...first);
    const second = await r2;
    fetched.push(...second);
    if (run !== c.run || current !== c) return null;
    update(snapshot(false));
    let count = 20;
    for (;;) {
      const g = grouped(fetched);
      const notGrouped = g.reduce((n, r) => (r.listedTimes <= 2 ? n + 1 : n), 0);
      if (!((notGrouped < MIN_NOT_GROUPED || g.length < MIN_GROUPED) && count < result.result.length && count < API_FETCH_LIMIT)) break;
      const more = await requestResults(result.id, result.result.slice(count, count + 10), opts);
      if (run !== c.run || current !== c) return null;
      fetched.push(...more);
      count += 10;
      update(snapshot(false));
    }
  } catch (e) {
    if (run !== c.run || current !== c) return null;
    const out = snapshot(true, String((e as Error).message || e));
    update(out);
    return out;
  }
  const out = snapshot(true);
  update(out);
  return out;
}

const API_FETCH_LIMIT = 100;
const MIN_NOT_GROUPED = 7;
const MIN_GROUPED = 10;

// trade-api.ts's groupedResults: one seller's same price (or their next
// listings) counted as one line.
function grouped(results: PricingResult[]) {
  const out: Array<PricingResult & { listedTimes: number }> = [];
  for (const result of results) {
    if (result == null) break;
    if (out.length === 0) { out.push(Object.assign({ listedTimes: 1 }, result)); continue; }
    const existing = out.find(
      (added, idx) =>
        (added.accountName === result.accountName && added.priceCurrency === result.priceCurrency && added.priceAmount === result.priceAmount) ||
        (added.accountName === result.accountName && out.length - idx <= 2),
    );
    if (existing) {
      if (existing.stackSize) existing.stackSize += result.stackSize!;
      else existing.listedTimes += 1;
    } else {
      out.push(Object.assign({ listedTimes: 1 }, result));
    }
  }
  return out;
}

/** Forgets the checked item. */
export function clear() {
  if (current) current.run++;
  current = null;
}
