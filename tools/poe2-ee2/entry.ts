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
import * as Ninja from "./ninja";

// The languages whose data Game Companion ships, told apart by the copied
// text's first line (as EE2's own LANGUAGE_DETECTOR does).
const LANGUAGES = [
  { lang: "en", itemClass: "Item Class: ", rarity: "Rarity: " },
  { lang: "de", itemClass: "Gegenstandsklasse: ", rarity: "Seltenheit: " },
];

let loaded = "";

/** Game Companion's price check settings (Settings → Plugins → PoE 2). */
export interface Prefs {
  searchStatRange: number; // min = value − N % (EE2's default 10)
  fillMax: boolean; // max = value + N % too
  defaultAllSelected: boolean;
  smartInitialSearch: boolean; // uniques and the like search at once
  listingType: string; // "securable" (instant buyout), "available" (in person), "any"
  currency: string; // "" (any), "exalted", "divine", "chaos"
  collapseListings: "app" | "api";
  showSeller: "account" | "ign" | "";
  accountName: string;
  ninja: boolean; // poe.ninja's prices (on by default)
}
const prefs: Prefs = {
  searchStatRange: 10,
  fillMax: false,
  defaultAllSelected: false,
  smartInitialSearch: true,
  listingType: "securable",
  currency: "",
  collapseListings: "app",
  showSeller: "account",
  accountName: "",
  ninja: true,
};
/** poe.ninja's prices for the search being shown (null when off or not there). */
let ninjaNow: any = null;
/** Takes the settings over (missing ones keep EE2's defaults). */
export function setPrefs(p: Partial<Prefs>) {
  for (const k in p) if ((p as any)[k] !== undefined && k in prefs) (prefs as any)[k] = (p as any)[k];
  const w = AppConfig("price-check");
  w.searchStatRange = prefs.searchStatRange;
  w.collapseListings = prefs.collapseListings;
  w.defaultAllSelected = prefs.defaultAllSelected;
  w.smartInitialSearch = prefs.smartInitialSearch;
  AppConfig().accountName = prefs.accountName;
}
let leaguesLoaded = false;

/** poe.ninja's answer read as the kit does (for the tests). */
export const ninjaRead = Ninja.readOverview;
export const ninjaNorm = Ninja.normalised;

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
    currency: prefs.currency || undefined,
    listingType: prefs.listingType || undefined,
    collapseListings: prefs.collapseListings,
    activateStockFilter: false,
    searchStatRange: prefs.searchStatRange,
    useEn: true,
    defaultAllSelected: prefs.defaultAllSelected,
  });
  current = { item, presets, run: 0 };
  // poe.ninja's prices, asked in the background (the search waits for them).
  if (prefs.ninja) Ninja.load(lg.selected);
  const f = preset(current).filters;
  if (api(current) === "bulk") f.trade.listingType = "online";
  if (prefs.fillMax) {
    for (const st of preset(current).stats) {
      if (st.roll && typeof st.roll.min === "number") {
        const v = st.roll.value;
        const d = Math.abs(v) * prefs.searchStatRange / 100;
        st.roll.max = st.roll.dp ? Math.round((v + d) * 100) / 100 : Math.ceil(v + d);
      }
    }
  }
  return view();
}

function api(c: Checked) {
  const p = preset(c);
  return apiToSatisfySearch(c.item, p.stats, p.filters);
}

/** Whether EE2 would search at once (uniques, unidentified and the like). */
function searchesAtOnce(item: ParsedItem) {
  if (!prefs.smartInitialSearch) return false;
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
    ninja: prefs.ninja ? Ninja.priceOf(Ninja.known(p.filters.trade.league), it.info.refName) : null,
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
      dp: !!(s.roll && s.roll.dp),
      ...placeOf(s),
    })),
    listingType: f.trade.listingType,
    currency: f.trade.currency || "",
    advanced: hasModInfo(it),
    mods: hasModInfo(it) ? modsOf(it, p.stats) : [],
  };
}

// The item's mods as the game's advanced copy lists them (MN: "what is on
// the item, what comes from prefixes, what from suffixes"): each with its
// own lines (the rolled values with the tier's range in brackets, as the
// game writes them), its tier, and the stat line that searches for it, or
// where EE2 counted it instead (a total, the item's values).
interface ModRow {
  group: string;
  name: string;
  tier: number | null;
  lines: { text: string; parts: Array<{ t: string; range: boolean }> }[];
  filter: number | null;
  folded: string;
}
function modsOf(item: ParsedItem, stats: StatFilter[]): ModRow[] {
  const out: ModRow[] = [];
  const used = new Set<object>();
  const sections = item.rawText.split(/\r?\n--------\r?\n/);
  const filterOf = (mod: object | null, text: string) => {
    let filter: number | null = null;
    let folded = "";
    stats.forEach((st, i) => {
      if (filter !== null) return;
      const own = (st.sources || []).some((x) => x.modifier === mod);
      const tag = st.tag as string;
      if (tag === "property" || tag === "pseudo") {
        if (own && !folded) folded = tag === "pseudo" ? "totals" : "values";
        return;
      }
      if (own || (!mod && sameLine(st.text, text))) filter = i;
    });
    return { filter, folded: filter === null ? folded : "" };
  };
  for (const section of sections) {
    const rows = section.split(/\r?\n/).filter((l) => l.length > 0);
    if (!rows.some((l) => /^\{.*\}$/.test(l))) {
      // A section of fixed lines without headers (runes, enchants).
      for (const l of rows) {
        const m = l.match(/^(.*\S) \(([^()]+)\)$/);
        if (!m || !/^(rune|added rune|enchant|implicit|Rune|Verzauberung|implizit)$/i.test(m[2])) continue;
        const text = m[1];
        out.push({ group: "fixed", name: "", tier: null, lines: [line(text)], ...filterOf(null, text) });
      }
      continue;
    }
    let row: ModRow | null = null;
    for (const l of rows) {
      if (/^\{.*\}$/.test(l)) {
        const name = (l.match(/"([^"]+)"/) || [])[1] || "";
        const num = l.match(/\((?:[^():]+):\s*(\d+)\)/);
        const tier = num ? Number(num[1]) : null;
        const mod = item.newMods.find((m) => !used.has(m) && (m.info.name || "") === name && (name || m.info.tier === undefined || m.info.tier === tier) && (name !== "" || (m.info.type as string) !== "explicit"))
          || item.newMods.find((m) => !used.has(m) && (m.info.name || "") === name);
        if (mod) used.add(mod);
        const type = mod ? (mod.info.type as string) : "";
        const gen = mod ? mod.info.generation : undefined;
        const group = gen === "prefix" || gen === "suffix" ? gen : type === "explicit" || type === "" ? "lines" : "fixed";
        const tierNo = mod && typeof mod.info.tier === "number" ? mod.info.tier : tier;
        row = { group, name, tier: tierNo, lines: [], filter: null, folded: "", mod } as any;
        out.push(row!);
        continue;
      }
      if (!row) continue;
      row.lines.push(line(l.replace(/ \((implicit|enchant|rune|added rune|crafted|fractured|desecrated|implizit)\)$/i, "")));
    }
  }
  for (const r of out as any[]) {
    if (r.mod === undefined) continue;
    const f = r.mod ? filterOf(r.mod, "") : filterOf(null, r.lines.length ? r.lines[0].text : "");
    r.filter = f.filter;
    r.folded = f.folded;
    delete r.mod;
  }
  return out.filter((r) => r.lines.length > 0);
}
// A line split into the rolled text and the tier's ranges: "+33(31-35)%"
// becomes "+33", range "31–35", "%".
function line(text: string) {
  const parts: Array<{ t: string; range: boolean }> = [];
  const re = /(\d)\((-?[\d.]+)-(-?[\d.]+)\)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    parts.push({ t: text.slice(last, m.index + 1), range: false });
    parts.push({ t: m[2] + "\u2013" + m[3], range: true });
    last = m.index + m[0].length;
  }
  parts.push({ t: text.slice(last), range: false });
  return { text: parts.filter((x) => !x.range).map((x) => x.t).join(""), parts };
}
function sameLine(template: string, text: string) {
  const esc = template.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/#/g, "[+-]?[\\d.]+");
  return new RegExp("^\\+?" + esc + "$").test(text);
}

// Where a line stands on the item, as the game's tooltip orders it: fixed
// lines (implicit, enchant, runes), prefixes, suffixes, EE2's totals. The
// prefix/suffix split, the tier and its range come only with the game's
// advanced copy (Ctrl+C with Alt held); without it explicit lines are "lines".
function placeOf(s: StatFilter): { group: string; tier: number | null; low: number | null; high: number | null } {
  const src = s.sources && s.sources.length ? s.sources : [];
  const types = src.map((x) => x.modifier.info.type as string);
  const tag = s.tag as string;
  let group = "lines";
  if (tag === "property") group = "properties";
  else if (tag === "pseudo") group = "totals";
  else if (types.some((t) => t === "implicit" || t === "enchant" || t === "rune" || t === "added-rune" || t === "skill") || tag === "implicit" || tag === "enchant" || tag === "rune" || tag === "added-rune") group = "fixed";
  else {
    const gen = src.map((x) => x.modifier.info.generation).find((g) => g === "prefix" || g === "suffix");
    if (gen) group = gen;
    else if (tag === "fractured" || tag === "desecrated" || tag === "crafted") group = "lines";
  }
  let tier: number | null = null;
  let low: number | null = null;
  let high: number | null = null;
  if (src.length === 1 && group !== "totals" && group !== "properties") {
    const one = src[0];
    if (typeof one.modifier.info.tier === "number") tier = one.modifier.info.tier;
    const c = one.contributes;
    if (c && typeof c.min === "number" && typeof c.max === "number" && (c.min !== c.max || tier !== null)) {
      low = c.min;
      high = c.max;
    }
  }
  return { group, tier, low, high };
}

function hasModInfo(item: ParsedItem) {
  return item.newMods.some((m) => typeof m.info.tier === "number" || m.info.generation === "prefix" || m.info.generation === "suffix");
}

/** Sets a trade choice of the checked item: listingType or currency. */
export function setTrade(key: "listingType" | "currency", value: string) {
  if (!current) return view();
  const t = preset(current).filters.trade as any;
  t[key] = value || undefined;
  if (key === "listingType" && !value) t.listingType = "any";
  return view();
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

// The trade site's colour numbers (EE2's TradeNumberColors) as names.
const LINE_COLOURS: Record<number, string> = {
  1: "augmented", 2: "unmet", 3: "physical", 4: "fire", 5: "cold", 6: "lightning", 7: "chaos",
  8: "unique", 25: "skill", 8729: "enchant", 8730: "fractured", 8731: "desecrated",
  8732: "sanctified", 8733: "mutated",
};

/**
 * A listed item as the trade site shows it (EE2's DisplayItem, made by
 * its parseFetchResult): title, then blocks of lines (values, requirements,
 * granted skills, enchants, runes, implicits, fractured, explicits …),
 * each line's text with its tier where the site gave one.
 */
function shownItem(d: any) {
  if (!d) return null;
  const t = useI18n().t;
  const line = (l: any) => {
    const value = l.value === undefined || l.value === null ? "" : String(l.value);
    let text = String(l.text || "");
    if (text.indexOf("item.") === 0) {
      text = t(text, [value]);
      // "Critical Hit Chance: {0}%" with the site's "5.00%".
      text = text.split("%%").join("%");
    }
    else if (text.indexOf("{0}") >= 0) text = text.split("{0}").join(value);
    else if (value !== "") text = text + value;
    return { text: text.trim(), tier: l.tier ? String(l.tier) : "", colour: LINE_COLOURS[l.color] || "" };
  };
  const keys = [
    "nameBlock", "itemProps", "grantSkill", "enchantMods", "runeMods", "implicitMods",
    "fracturedMods", "explicitMods", "desecratedMods", "mutatedMods", "veiledMods", "itemTags",
  ];
  const blocks: any[] = [];
  for (let k = 0; k < keys.length; k++) {
    const list = d[keys[k]];
    if (!list || !list.length) continue;
    const lines = list.map(line);
    // EE2 leaves the requirements' "Requires" to its page.
    if (keys[k] === "itemProps") {
      for (let n = 0; n < list.length; n++) if (String(list[n].text || "").indexOf("item.") !== 0) lines[n].text = "Requires " + lines[n].text;
    }
    blocks.push({ kind: keys[k], lines });
  }
  return { title: d.title || [], rarity: d.rarity || "", blocks };
}

function trade(r: any) {
  const norm = Ninja.normalised(ninjaNow, r.priceAmount, r.priceCurrency);
  return {
    id: r.id,
    norm,
    item: shownItem(r.displayItem),
    amount: r.priceAmount,
    currency: r.priceCurrency,
    times: r.listedTimes || 1,
    stack: r.stackSize || 0,
    account: prefs.showSeller === "ign" ? (r.ign || r.accountName) : prefs.showSeller === "" ? "" : r.accountName,
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
  ninjaNow = prefs.ninja ? await Ninja.load(p.filters.trade.league) : null;
  if (run !== c.run || current !== c) return null;
  const ninja = Ninja.priceOf(ninjaNow, c.item.info.refName);
  if (kind === "bulk") {
    try {
      const have = ["exalted", "divine"];
      const res = await execBulkSearch(c.item, p.filters, have, { accountName: AppConfig().accountName });
      if (run !== c.run || current !== c) return null;
      const firstGroup = res.find((g) => g && g.queryId);
      lastBulk = firstGroup ? { league: p.filters.trade.league, id: firstGroup.queryId } : null;
      const out = {
        kind,
        done: true,
        ninja,
        groups: res.filter((g) => g).map((g) => ({
          have: g!.haveTag,
          total: g!.total,
          listed: g!.listed.map((r) => ({
            rate: r.itemAmount ? r.exchangeAmount / r.itemAmount : 0,
            norm: Ninja.normalised(ninjaNow, r.itemAmount ? r.exchangeAmount / r.itemAmount : 0, g!.haveTag),
            exchangeAmount: r.exchangeAmount,
            itemAmount: r.itemAmount,
            stock: r.stock,
            account: prefs.showSeller === "ign" ? (r.ign || r.accountName) : prefs.showSeller === "" ? "" : r.accountName,
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
  const snapshot = (done: boolean, error = "") => ({ kind, done, error, total, ninja, listed: grouped(fetched).map(trade) });
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

let lastBulk: { league: string; id: string } | null = null;

/**
 * The trade site's page for this search (EE2's "open on the trade site"),
 * opened in the person's browser only when they click it.
 */
export function tradeLink(): string {
  const c = current;
  if (!c) return "";
  const p = preset(c);
  const league = encodeURIComponent(p.filters.trade.league);
  if (api(c) === "bulk") {
    return lastBulk && lastBulk.league === p.filters.trade.league
      ? `https://www.pathofexile.com/trade2/exchange/poe2/${league}/${encodeURIComponent(lastBulk.id)}`
      : `https://www.pathofexile.com/trade2/exchange/poe2/${league}`;
  }
  const q = JSON.stringify(createTradeRequest(p.filters, p.stats, c.item));
  return `https://www.pathofexile.com/trade2/search/poe2/${league}?q=${encodeURIComponent(q)}`;
}

/** Forgets the checked item. */
export function clear() {
  if (current) current.run++;
  current = null;
}
