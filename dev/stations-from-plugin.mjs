// Writes data/stations.json from the Clicktrough Radio plugin's station list
// (Xzero3007/A2Tools-Clicktrough-Plugins, plugins/radio/stations.js, GPL-3.0).
// Usage: node dev/stations-from-plugin.mjs <path to stations.js>
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";

const source = process.argv[2];
if (!source) {
  console.error("usage: node dev/stations-from-plugin.mjs <plugins/radio/stations.js>");
  process.exit(2);
}
createRequire(import.meta.url)(resolve(source));
const out = {
  countries: globalThis.RADIO_COUNTRIES.filter(([id]) => id !== "fav" && id !== "all").map(([id, name]) => ({ id, name })),
  genres: Object.entries(globalThis.RADIO_GENRES).map(([id, name]) => ({ id, name })),
  stations: globalThis.RADIO_STATIONS.map((s) => ({
    id: s.id, name: s.name, country: s.country, info: s.info || "", genres: s.genres || [], streams: s.streams,
  })),
};
writeFileSync(new URL("../data/stations.json", import.meta.url), JSON.stringify(out, null, 1) + "\n");
console.log(`${out.stations.length} stations`);
