// EE2 loads a language's client strings by dynamic import; Qt's JavaScript
// has none, so the shipped languages are bundled.
// @ts-ignore
import en from "gc:client-strings/en";
// @ts-ignore
import de from "gc:client-strings/de";
const ALL: Record<string, any> = { en, de };
export async function loadClientStrings(lang: string) {
  return ALL[lang] || en;
}
