// Stands in for EE2's web/Config.ts: Game Companion's fixed choices, the
// price-check widget's defaults as EE2 ships them. `setLanguage` follows the
// language of the copied item.
import { reactive } from "vue";

const priceCheck = {
  wmType: "price-check",
  showSeller: false,
  searchStatRange: 10,
  showRateLimitState: false,
  apiLatencySeconds: 2,
  collapseListings: "app",
  smartInitialSearch: true,
  lockedInitialSearch: true,
  activateStockFilter: false,
  showCursor: true,
  requestPricePrediction: false,
  builtinBrowser: false,
  rememberCurrency: false,
  defaultAllSelected: false,
  itemHoverTooltip: "off",
  alwaysShowTier: false,
  coreCurrency: "exalted",
  currencyVolume: "none",
  rememberListingType: false,
  initialDelay: 0,
  savedAugments: {},
};

// Reactive like EE2's own config: its leagues' `selectedId` is computed from it.
const config: any = reactive({
  language: "en",
  realm: "pc-ggg",
  preferredTradeSite: "www",
  accountName: "",
  leagueId: undefined,
  tipsFrequency: 0,
  widgets: [priceCheck],
});

export function AppConfig(type?: string): any {
  if (!type) return config;
  return config.widgets.find((w: any) => w.wmType === type);
}
export function setLanguage(lang: string) { config.language = lang; }
export function setLeague(id: string) { config.leagueId = id; }
export function updateConfig() {}
export function saveConfig() {}
export function pushHostConfig() {}
export async function initConfig() {}
// Every request goes to www.pathofexile.com (one host; stat ids and the
// English names EE2 sends with `useEn` work there for every language).
export function poeWebApi() { return "www.pathofexile.com"; }
export enum TipsFrequency { Always = 0, Never = 1 }
