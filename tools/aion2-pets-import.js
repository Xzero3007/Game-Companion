#!/usr/bin/env node
// Takes Pet Finder's tables over from the Clicktrough plugins (same author;
// its Pets list is A2 Tools' Pet Soul Tracker, GPL-3.0, and its catalogue
// and portraits come from PetTracker, GPLv3) into crates/aion2/data/pets/:
// pets.json (English names, genus, where each pet's souls drop, and the ids
// the game's pet frames may carry) and portraits/ (the 256 px pictures).
//
//     node tools/aion2-pets-import.js <A2Tools-Clicktrough-Plugins>/plugins/pet-finder
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = process.argv[2];
if (!src) {
  console.error("usage: aion2-pets-import.js <plugins/pet-finder>");
  process.exit(2);
}
const out = path.join(__dirname, "..", "crates", "aion2", "data", "pets");

// The plugin's tables are plain scripts: run them in a sandbox of their own.
const box = { globalThis: {} };
vm.createContext(box);
for (const file of ["pets.js", "sources.js", "data.js"]) {
  const text = fs.readFileSync(path.join(src, file), "utf8").replace(/^const /gm, "var ");
  vm.runInContext(text, box, { filename: file });
}
const { PET_NAMES, PET_GENUS, GENUS_NAMES, PET_SOURCES, SOURCE_TEXT } = box;
const PET_DATA = box.globalThis.PET_DATA;

const en = (key) => {
  const t = SOURCE_TEXT[key];
  return (t && (t.en || Object.values(t)[0])) || null;
};
const kibelisk = (name) => (name ? (en(name) || name).replace(/^Kibelisk:?\s*/i, "") : null);

const pets = {};
for (const id of Object.keys(PET_NAMES).map(Number).sort((a, b) => a - b)) {
  const s = PET_SOURCES[id] || { drops: [], chests: [] };
  pets[id] = {
    name: PET_NAMES[id].en,
    genus: PET_GENUS[id] || null,
    drops: (s.drops || []).map((d) => ({
      npc: d.npcId,
      name: en(d.npc) || `Monster ${d.npcId}`,
      level: d.level ?? null,
      chance: d.chance || null,
      region: d.region || en(d.map) || null,
      zone: (d.zones || []).map(en).filter(Boolean)[0] || null,
      spawns: d.spawns ?? null,
      kibelisk: d.kibelisk ? { name: kibelisk(d.kibelisk.name), m: d.kibelisk.m } : null,
    })),
    chests: (s.chests || []).map((c) => ({
      name: en(c.name) || c.name,
      chance: c.chance || null,
      from: (c.from || []).map(en).filter(Boolean),
    })),
  };
}
const genus = Object.fromEntries(Object.entries(GENUS_NAMES).map(([k, v]) => [k, v.en]));
const catalog = [...new Set(PET_DATA.catalog.map(Number))].sort((a, b) => a - b);

fs.mkdirSync(path.join(out, "portraits"), { recursive: true });
fs.writeFileSync(path.join(out, "pets.json"), JSON.stringify({
  source: "Clicktrough Pet Finder 0.4.5: A2 Tools' Pet Soul Tracker (GPL-3.0) and PetTracker (GPLv3)",
  genus, catalog, pets,
}) + "\n");
let n = 0;
for (const f of fs.readdirSync(path.join(src, "portraits"))) {
  if (!/^\d+\.webp$/.test(f)) continue;
  fs.copyFileSync(path.join(src, "portraits", f), path.join(out, "portraits", f));
  n++;
}
fs.copyFileSync(path.join(src, "NOTICE-PetSoulTracker.txt"), path.join(out, "NOTICE-PetSoulTracker.txt"));
console.log(`${Object.keys(pets).length} pets, ${catalog.length} in the catalogue, ${n} portraits`);
