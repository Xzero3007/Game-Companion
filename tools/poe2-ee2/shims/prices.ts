// Stands in for EE2's web/background/Prices.ts (poe.ninja): not asked yet,
// so prices stay in the currency the seller asked for.
import { shallowRef } from "vue";
export interface CoreCurrency { id: "exalted" | "chaos" | "div"; abbrev: string; ref: string; text: string; icon: string }
export interface CurrencyValue { min: number; max: number; currency: "chaos" | "exalted" | "div" }
export const DivCurrency: CoreCurrency = { id: "div", abbrev: "div", ref: "Divine Orb", text: "Divine Orb", icon: "" };
export function displayRounding(value: number, fraction = false): string {
  if (fraction && Math.abs(value) < 1) {
    if (value === 0) return "0";
    const r = `1∕${displayRounding(1 / value)}`;
    return r === "1∕1" ? "1" : r;
  }
  if (Math.abs(value) < 10) return Number(value.toFixed(1)).toString().replace(/\.0$/, "");
  return Math.round(value).toString();
}
const xchgRateCurrency = shallowRef<CoreCurrency | undefined>(undefined);
export function usePoeninja() {
  return {
    xchgRateCurrency,
    cachedCurrencyByQuery: (_q: unknown, _amount: number): CurrencyValue | undefined => undefined,
    findPriceByQuery: () => undefined,
    autoCurrency: () => undefined,
    queuePricesFetch: () => {},
    selectedCoreCurrency: shallowRef(undefined),
    ITEM_DROP: shallowRef([]),
  };
}
