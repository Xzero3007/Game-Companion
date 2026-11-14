// The Armory plugin's sums (calc.js) and its reading of NC's pages (nc.js)
// and of a saved questlog.gg build page, on made-up characters.
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
// Taken over from the Clicktrough Armory plugin (dev/tests, GPL-3.0) and run
// against Game Companion's armorykit.js (tools/aion2-armory-import.py).
const { D, C, NC } = require(path.join(__dirname, "kit.cjs"));

const near = (a, b, tol, what) => assert.ok(Math.abs(a - b) <= tol, `${what}: ${a} is not ${b} (± ${tol})`);
const idOf = (name, il) => Number(Object.keys(D.items).find((k) => D.items[k][0] === name && (!il || D.items[k][3] === il)));

test("the data: the game's enhance tables and the enhanceable items", () => {
  assert.ok(Object.keys(D.items).length > 3000);
  assert.equal(D.enchant.Enchant_Unique_86.filter((s) => s[0] > 0).length, 15);
  assert.ok(Object.keys(D.amplify).length > 50);
  assert.equal(D.mats.CoinEnchant.name, "Enhance Stone");
  assert.equal(D.mats.Enchant_Amplify_A_s_02a_f.id, 516530001);
  const bow = D.items[String(idOf("Enraged Kromede Longbow", 86))];
  assert.deepEqual(bow.slice(1, 4), ["Unique", "Bow", 86]);
  assert.equal(bow[5], "Enchant_Unique_86");
});

test("one step's tries, its chance rising after each failure", () => {
  assert.deepEqual(C.stepTries(10000, 0), { expected: 1, certain: 1, p90: 1 });
  // 20 % and 5 % more a failure: about 3.4 tries, certain by the 17th.
  const t = C.stepTries(2000, 500);
  near(t.expected, 3.4, 0.05, "tries");
  assert.equal(t.certain, 17);
  assert.ok(t.p90 >= 5 && t.p90 <= 7);
});

test("enhancing as Aion2Data's calculator has it: +0 to +15 on an item level 86 Unique", () => {
  const item = { id: idOf("Enraged Kromede Longbow", 86) };
  const c = C.climb(C.enchantTable(item), 0, 15);
  assert.equal(c.steps.length, 15);
  near(c.sum.tries, 22.24, 0.01, "tries");
  near(c.sum.kinah, 12628926, 2, "Kinah");
  near(c.sum.mats.CoinEnchant, 160752, 2, "Enhance Stones");
  // Only the last steps: +14 to +15.
  const last = C.climb(C.enchantTable(item), 14, 15);
  near(last.sum.kinah, 5376096, 2, "+14 → +15 Kinah");
});

test("a step that loses a level on failure counts the climb back (Clash Rune)", () => {
  const rune = C.climb(D.enchant.Rune_PvE_Unique, 0, 10);
  // Aion2Data: 68,978 tries and 4,230,566,866 Kinah on average to +10.
  near(rune.sum.tries, 68978, 2, "tries");
  near(rune.sum.kinah, 4230566866, 5000, "Kinah");
});

test("the gear score from its parts, as the game counts it", () => {
  const snap = {
    items: [
      { slot: "MainHand", il: 86, enchant: 15, amplify: 4, stones: [{ grade: "Rare" }, { grade: "Legend" }], theostones: [{ grade: "Rare" }] },
      { slot: "Helmet", il: 86, enchant: 13, amplify: 0, stones: [{ grade: "Common" }, { grade: "Unique" }] },
      { slot: "Arcana1", il: 80, enchant: 3, arcana: true },
    ],
    boards: [{ points: 107 }, { points: 98 }],
  };
  const g = C.gearScore(snap);
  assert.deepEqual(g.parts, { level: 252, enchant: 31, amplify: 20, manastones: 10, theostones: 3, daevanion: 205 });
  assert.equal(g.total, 252 + 31 + 20 + 10 + 3 + 205);
});

test("the cheapest way to a target gear score", () => {
  const bow = idOf("Enraged Kromede Longbow", 86);
  const snap = { items: [
    { slot: "MainHand", id: bow, il: 86, enchant: 15, amplify: 0, maxEnchant: 15, maxAmplify: 5 },
    { slot: "Bracelet1", id: idOf("Ascension Bracelet", 51), il: 51, enchant: 10, amplify: 0, maxEnchant: 15, maxAmplify: 0 },
  ] };
  // Without a price for Amplify Stones, the bow's first Amplify level (600k
  // Kinah for 5 points) is the cheapest a point.
  const plan = C.planGearScore(snap, 1000, 1005, null);
  assert.ok(plan.reached);
  assert.equal(plan.gs, 1005);
  assert.deepEqual([plan.pieces[0].slot, plan.pieces[0].kind, plan.pieces[0].to], ["MainHand", "amplify", 1]);
  // Dear Amplify Stones: the bracelet's cheaper enhance levels come first
  // (+11 to +13), then the Amplify level beats its dearer +14.
  const dear = C.planGearScore(snap, 1000, 1005, new Map([["516530001", 1e6]]));
  assert.deepEqual(dear.pieces.map((p) => [p.slot, p.kind, p.from, p.to]), [["Bracelet1", "enchant", 10, 13], ["MainHand", "amplify", 0, 1]]);
  assert.equal(dear.gs, 1008);
  // Everything there is: 5 enhance levels and 5 Amplify levels.
  const all = C.planGearScore(snap, 1000, 9999, null);
  assert.equal(all.reached, false);
  assert.equal(all.gs, 1000 + 5 + 25);
  assert.equal(C.gearRoom(snap), 30);
  // Amplify Stones at a market price count in Kinah.
  const priced = C.planGearScore(snap, 1000, 9999, new Map([["516530001", 50000]]));
  assert.ok(priced.total.worth.total > priced.total.kinah);
  assert.ok(!("Enchant_Amplify_A_s_02a_f" in priced.total.worth.unpriced));
});

test("where a skill's level comes from, and what is left to 20", () => {
  const snap = {
    skills: [
      { name: "Snipe", category: "Active", level: 16 },
      { name: "Explosion Trap", category: "Active", level: 7 },
      { name: "Griffon Arrow", category: "Dp", level: 16 },
    ],
    items: [{ slot: "Arcana2", name: "Parchment of Magic", arcana: true, subSkills: [{ name: "Snipe", level: 2 }] }],
    boards: [
      { name: "Nezekan", nodes: [
        { type: "SkillLevel", grade: "Legend", open: true, effects: ["Snipe +1"] },
        { type: "SkillLevel", grade: "Legend", open: false, effects: ["Explosion Trap +1"] },
      ] },
      { name: "Zikel", nodes: [{ type: "SkillLevel", grade: "Rare", open: true, effects: ["Snipe +3"] }] },
    ],
  };
  const [snipe, trap, stigma] = C.skillSources(snap);
  assert.deepEqual([snipe.base, snipe.fromDaev, snipe.fromGear, snipe.to20, snipe.gearFor20], [10, 4, 2, 4, 4]);
  assert.deepEqual([trap.base, trap.baseRoom, trap.closedNodes.length, trap.closedNodes[0].points], [7, 3, 1, 3]);
  assert.equal(stigma.gearFor20, null);
});

test("NC's pages read into a snapshot", () => {
  assert.equal(NC.regionOf(2305), "eu");
  assert.equal(NC.regionOf(1101), "nae");
  assert.equal(NC.regionOf(2501), "as");
  const ref = { serverId: 2305, characterId: "AbC-d_e=" };
  assert.match(NC.infoUrl(ref), /^https:\/\/aion2\.plaync\.com\/api\/character\/info\?lang=en-US&region=eu&serverId=2305&characterId=AbC-d_e%3D$/);
  assert.match(NC.searchUrl("Some Name", 2305), /^https:\/\/api-search\.plaync\.com\/aion2global\/search\/v2\/character\?keyword=Some\+Name&.*region=eu/);
  const found = NC.readSearch({ list: [
    { characterId: "x%3D", name: "<strong>Other</strong>", serverId: 2305 },
    { characterId: "AbC%3D", name: "<strong>Tester</strong>", serverId: 2305, level: 45, serverName: "Marchutan", profileImageUrl: "/game_profile_images/a?b=1" },
  ] }, "tester", 2305);
  assert.equal(found.characterId, "AbC=");
  assert.equal(found.portrait, "https://profileimg.plaync.com/game_profile_images/a?b=1");
  const info = NC.readInfo({
    profile: { characterId: "AbC=", characterName: "Tester", characterLevel: 45, className: "Ranger", combatPower: 1000, serverId: 2305, serverName: "Marchutan" },
    stat: { statList: [{ type: "STR", name: "Might", value: 56, statSecondList: ["Attack increase +5.6%"] }, { type: "ItemLevel", name: "?", value: 2626 }] },
    title: { ownedCount: 3, totalCount: 9, titleList: [] }, ranking: { rankingList: null },
    daevanion: { boardList: [{ id: 31, name: "Nezekan", openNodeCount: 2, totalNodeCount: 3 }] },
  });
  assert.equal(info.profile.gs, 2626);
  assert.equal(info.stats.STR.value, 56);
  assert.deepEqual(info.rankings, []);
  const eq = NC.readEquipment({ equipment: { equipmentList: [
    { slotPos: 1, slotPosName: "MainHand", id: 7, name: "Bow", grade: "Unique", enchantLevel: 15, exceedLevel: 4 },
    { slotPos: 41, slotPosName: "Arcana1", id: 8, name: "Card", grade: "Unique", enchantLevel: 3, exceedLevel: 0 },
  ] }, skill: { skillList: [{ id: 1, name: "Snipe", category: "Active", skillLevel: 16, acquired: 1, equip: 1 }] }, petwing: {} });
  assert.deepEqual(eq.slots.map((s) => [s.slot, s.enchant, s.amplify, s.arcana]), [["MainHand", 15, 4, false], ["Arcana1", 3, 0, true]]);
  const item = NC.readItem({ name: "Bow", level: 86, maxEnchantLevel: 15, maxExceedEnchantLevel: 5,
    mainStats: [{ id: "WeaponFixingDamage", name: "Attack", value: "431", extra: "146" }],
    magicStoneStat: [{ name: "MP", value: "+30", grade: "Rare" }], magicStoneSlotCount: 4,
    godStoneStat: [{ name: "Theostone", desc: "…", grade: "Rare" }], subSkills: [{ name: "Tempest Shot", level: 1 }] }, eq.slots[0]);
  assert.deepEqual([item.il, item.maxEnchant, item.maxAmplify, item.stones.length, item.stoneSlots, item.subSkills[0].level], [86, 15, 5, 1, 4, 1]);
  const board = NC.readBoard({ nodeList: [
    { nodeId: 1, type: "Start", grade: "None", open: 1, effectList: [] },
    { nodeId: 2, type: "Stat", grade: "Common", open: 1, effectList: [{ desc: "HP +600" }] },
    { nodeId: 3, type: "SkillLevel", grade: "Legend", open: 1, effectList: [{ desc: "Snipe +1" }] },
    { nodeId: 4, type: "Stat", grade: "Unique", open: 0, effectList: [{ desc: "Combat Speed +1.5%" }] },
    { nodeId: 5, type: "None", grade: "None", open: 0, effectList: [] },
  ] }, { id: 31, name: "Nezekan" });
  assert.deepEqual([board.points, board.maxPoints, board.open, board.total], [4, 8, 2, 3]);
  const snap = NC.snapshotOf({ info, equipment: eq, items: [item], boards: [board], at: 5 });
  assert.equal(snap.items[0].il, 86);
  assert.equal(snap.items[1].slot, "Arcana1");
  assert.equal(NC.keyOf(2305, "Tes ter"), "c-2305-Tes_ter");
});

// A saved build page, cut down to what the reading looks at.
const PAGE = `<!doctype html><html><head><title>Testbuild | AION2 Build | questlog.gg</title>
<script>var x = "<img src=nope.webp>";</script></head><body>
<div><img alt="Splendent Ebony Dragon Lord Bow" src="./p_files/Icon_WP_BW_0100_T06.webp"></div>
<span>Create New Build</span>
<div><span>+</span><span>20</span><img src="./p_files/UT_SlotGrade_Unique.webp"><img src="./p_files/Icon_WP_BW_0100_T06.webp"></div>
<div><span>+</span><span>10</span><img src="./p_files/UT_SlotGrade_Unique.webp"><img src="./p_files/Icon_Equip_AR_L_Idris_01_Helmet.webp"></div>
<div><span>+</span><span>20</span><img src="./p_files/UT_SlotGrade_Unique.webp"><img src="./p_files/Icon_ACC_ER_0047.webp"></div>
<div><span>+</span><span>20</span><img src="./p_files/UT_SlotGrade_Unique.webp"><img src="./p_files/Icon_ACC_ER_0047.webp"></div>
<div><span>+</span><span>7</span><img src="./p_files/UT_SlotGrade_Special.webp"><img src="./p_files/Icon_Acc_Rune_R_002.webp"></div>
<span>Equipment</span><span>Skills</span>
<span>Skills</span><span>Active</span>
<img src="./p_files/ICON_RA_SKILL_001.webp"><span>16</span>
<img src="./p_files/ICON_RA_SKILL_002.webp">
<img src="./p_files/ICON_RA_SKILL_013.webp"><span>12</span>
<span>Stigma</span>
<img src="./p_files/ICON_RA_SKILL_006.webp"><img src="./p_files/ICON_RA_SKILL_022.webp">
<img src="./p_files/ICON_RA_SKILL_001.webp"><span>16</span><span>1</span>
<span>Board Points</span><span>Nezekan</span><span>97 / 134</span><span>Ariel</span><span>60 / 232</span><span>Nezekan</span>
<span>Justice [Nezekan]</span><span>51</span><span>Time [Siel]</span><span>110</span>
<span>Gear Score</span><span>3107</span><span>Max Attack</span><span>1.099</span>
</body></html>`;

test("a saved questlog.gg build page read into a reference", () => {
  const ref = C.readQuestlogPage(PAGE);
  assert.equal(ref.name, "Testbuild");
  assert.equal(ref.gearScore, 3107);
  assert.deepEqual(ref.gear.map((g) => [g.slot, g.name, g.enchant, g.amplify]), [
    ["MainHand", "Splendent Ebony Dragon Lord Bow", 15, 5],
    ["Helmet", "Nuakum Helm", 10, 0],
    // The earrings have only their picture: the set of the weapon's name.
    ["Earring1", "Splendent Ebony Dragon Lord Earrings", 15, 5],
    ["Earring2", "Splendent Ebony Dragon Lord Earrings", 15, 5],
    ["Rune1", "Clash Rune", 7, 0],
  ]);
  assert.equal(ref.gear[0].guessed, false);
  assert.equal(ref.gear[2].guessed, true);
  assert.deepEqual(ref.skills, [
    { icon: "ICON_RA_SKILL_001.webp", level: 16 },
    { icon: "ICON_RA_SKILL_002.webp", level: 20 },
    { icon: "ICON_RA_SKILL_013.webp", level: 12 },
  ]);
  assert.deepEqual(ref.stigmas, ["ICON_RA_SKILL_006.webp", "ICON_RA_SKILL_022.webp"]);
  assert.deepEqual(ref.boards, [{ name: "Nezekan", points: 97, total: 134 }, { name: "Ariel", points: 60, total: 232 }]);
  assert.deepEqual(ref.deity, { Justice: 51, Time: 110 });
  // Two saved tabs of one build add up.
  const merged = C.mergeReference({ ...ref, gear: [] }, ref);
  assert.equal(merged.gear.length, 5);
  // Compared with a character's gear.
  const rows = C.compareGear({ items: [{ slot: "Helmet", id: idOf("Nuakum Helm", 86), name: "Nuakum Helm", enchant: 13 }] }, ref);
  assert.deepEqual(rows.find((r) => r.slot === "Helmet").status, "done");
  assert.deepEqual(rows.find((r) => r.slot === "MainHand").status, "missing");
});

test("the history keeps what changed", () => {
  const snap = (cp, e) => ({ at: cp, profile: { cp, gs: 2000 + e }, items: [{ slot: "Helmet", id: idOf("Nuakum Helm", 86), enchant: e }], skills: [{ name: "Snipe", level: 16 }], boards: [{ points: 5 }], titles: { owned: 3 } });
  let h = C.addHistory([], C.historyEntry(snap(100, 13)));
  h = C.addHistory(h, { ...C.historyEntry(snap(100, 13)), at: 200 });
  assert.equal(h.length, 1);
  assert.equal(h[0].seen, 200);
  h = C.addHistory(h, C.historyEntry(snap(300, 14)));
  assert.equal(h.length, 2);
  assert.deepEqual(C.historyChanges(h[0], h[1]), ["Nuakum Helm +13 → +14"]);
  // Small gear score steps say little: rises of 5 or more, three of them.
  assert.deepEqual(C.cpPerGearScore([{ cp: 100, gs: 10 }, { cp: 3000, gs: 11 }, { cp: 3400, gs: 13 }]),
    { rate: C.CP_PER_GS_SAMPLE, own: false, samples: 0 });
  const rising = [{ cp: 1000, gs: 100 }, { cp: 1300, gs: 105 }, { cp: 1310, gs: 106 }, { cp: 1700, gs: 110 }, { cp: 2400, gs: 120 }];
  assert.deepEqual(C.cpPerGearScore(rising), { rate: 70, own: true, samples: 3 });
  assert.equal(C.cpPerGearScore([]).rate, C.CP_PER_GS_SAMPLE);
});

test("what the stats do: the game's own descriptions", () => {
  assert.ok(D.glossary.length > 150);
  assert.equal(C.statName("Combat Speed +7.4%"), "Combat Speed");
  assert.equal(C.statName("Cooldown -4.8%"), "Cooldown");
  assert.match(C.explainStat("Double Chance +3.3%").desc, /Double Resist/);
  assert.equal(C.explainStat("anything", "AmplifyWeaponDamage").name, "Weapon Damage Boost");
  const list = C.characterStats({
    stats: { Wisdom: { name: "Wisdom [Lumiel]", value: 33, effects: ["MP Cost -3.3%", "Double Chance +3.3%"] } },
    items: [{ slot: "MainHand", main: [{ id: "WeaponFixingDamage", name: "Attack" }], sub: [{ id: "CombatSpeed", name: "Combat Speed" }], stones: [{ name: "Critical Hit", value: "+7" }] }],
    titles: { list: [{ stats: ["Block +10"], equipStats: ["HP +900"] }] },
    boards: [{ nodes: [{ type: "Stat", open: true, effects: ["Critical Hit +5"] }, { type: "Stat", open: false, effects: ["Evasion +5"] }] }],
  });
  const of = (n) => list.find((x) => x.name === n);
  assert.deepEqual(of("Double Chance").from, ["Wisdom [Lumiel]"]);
  assert.deepEqual(of("Critical Hit").from.sort(), ["Daevanion", "Manastones"]);
  assert.equal(of("Evasion"), undefined);
  assert.ok(list.every((x) => x.entry));
});

test("soul binding: what a piece can get, from the game's item data", () => {
  const pool = C.soulPool(idOf("Enraged Kromede Longbow", 86), "Ranger");
  assert.equal(pool.count, 3);
  const cs = pool.stats.find((p) => p.name === "Combat Speed");
  assert.deepEqual([cs.min, cs.max, cs.pct], [10.63, 12.29, true]);
  assert.ok(pool.skills.some((p) => p.name === "Deadshot"));
  // The stats share 80 % of a pick, the class's skill effects 20 %.
  near(pool.stats.reduce((a, p) => a + p.first, 0), 0.8, 1e-9, "stats");
  near(pool.skills.reduce((a, p) => a + p.first, 0), 0.2, 1e-9, "skills");
  assert.equal(C.soulPool(idOf("Enraged Kromede Longbow", 86), "Gladiator").skills.some((p) => p.name === "Deadshot"), false);
});

test("soul binding: the chance a new binding gives the wanted properties", () => {
  const pool = { count: 2, stats: [{ kind: "stat", name: "A", first: 0.25 }, { kind: "stat", name: "B", first: 0.25 }, { kind: "stat", name: "C", first: 0.5 }], skills: [] };
  // A first (1/4), or B then A (1/4 · 1/3), or C then A (1/2 · 1/2).
  near(C.soulChance(pool, ["A"]), 0.25 + 0.25 / 3 + 0.25, 1e-12, "A");
  // A then B or B then A: 2 · 1/4 · 1/3.
  near(C.soulChance(pool, ["A", "B"]), 1 / 6, 1e-12, "A and B");
  assert.equal(C.soulChance(pool, ["A", "B", "C"]), 0, "more than the piece takes");
  assert.equal(C.soulChance(pool, ["D"]), 0, "one it can't get");
  assert.equal(C.soulChance(pool, []), null);
  // A real piece, every property wanted that it takes: small but not nothing.
  const bow = C.soulPool(idOf("Enraged Kromede Longbow", 86), "Ranger");
  const p = C.soulChance(bow, ["Combat Speed", "Weapon Damage Boost", "Might"]);
  assert.ok(p > 1e-4 && p < 1e-3, String(p));
});

test("soul binding: what a piece has against what is wanted", () => {
  const pool = C.soulPool(idOf("Enraged Kromede Longbow", 86), "Ranger");
  const item = { sub: [{ name: "Combat Speed", value: "11.46%" }, { name: "Attack", value: "40" }], subSkills: [{ name: "Deadshot", level: 1 }] };
  const c = C.soulCompare(item, ["Combat Speed", "Might"], pool);
  assert.deepEqual(c.wanted.map((w) => [w.name, w.have]), [["Combat Speed", true], ["Might", false]]);
  near(c.wanted[0].quality, 0.5, 0.01, "half way up its range");
  assert.deepEqual(c.extra.map((h) => h.name), ["Attack", "Deadshot"]);
});

test("skill targets: skill points first, then the cheapest Daevanion nodes, then gear", () => {
  const s = { level: 12, baseRoom: 1, closedNodes: [{ board: "Zikel", points: 3, gives: 1 }, { board: "Nezekan", points: 2, gives: 1 }] };
  const w = C.skillWay(s, 16);
  assert.equal(w.left, 4);
  assert.equal(w.points, 1);
  assert.deepEqual(w.daevanion.map((n) => n.board), ["Nezekan", "Zikel"]);
  assert.equal(w.gear, 1);
  assert.equal(C.skillWay({ level: 18 }, 16).left, 0);
});

test("Daevanion: the offensive nodes still closed and the cheapest way to them", () => {
  // A row from the start: open, then closed Common (1), Rare (2), Legend (3);
  // a closed Unique (4) beside the start; one corner to corner only.
  const node = (id, row, col, grade, open, effects, type = "Stat") => ({ id, row, col, grade, open, effects, type });
  const board = { name: "Test", nodes: [
    node(1, 8, 8, "None", true, [], "Start"),
    node(2, 8, 9, "Common", true, ["Attack Bonus +3"]),
    node(3, 8, 10, "Common", false, ["Defense Bonus +30"]),
    node(4, 8, 11, "Rare", false, ["PvE Accuracy +5", "PvE Evasion +5"]),
    node(5, 8, 12, "Legend", false, ["Critical Hit +10"]),
    node(6, 9, 8, "Unique", false, ["PvP Attack +5"]),
    node(7, 9, 9, "Common", false, ["Skill +1"], "SkillLevel"),
    node(8, 10, 10, "Common", false, ["Combat Speed +1%"]),
  ] };
  const ways = new Map(C.boardWays(board).map((n) => [n.id, n]));
  assert.equal(ways.get(3).cost, 1);
  assert.equal(ways.get(4).cost, 3);
  assert.equal(ways.get(5).cost, 6);
  assert.deepEqual(ways.get(5).path, [5, 4, 3]);
  assert.equal(ways.get(8).cost, null, "corner to corner is no way");
  assert.equal(ways.get(3).offensive, false);
  assert.equal(ways.get(4).offensive, true);
  const pve = C.boardOffense([board], "pve");
  assert.deepEqual(pve.filter((r) => r.nodes).map((r) => [r.name, r.closed, r.points]), [["Critical Hit", 10, 3], ["PvE Accuracy", 5, 2], ["Combat Speed", 1, 1]]);
  assert.equal(pve.find((r) => r.name === "Attack Bonus").have, 3);
  assert.ok(!pve.some((r) => r.name === "PvP Attack"));
  assert.ok(C.boardOffense([board], "pvp").some((r) => r.name === "PvP Attack"));
  assert.ok(!C.boardOffense([board], "pvp").some((r) => r.name === "PvE Accuracy"));
  for (const [name, off] of [["Multi-hit Chance", true], ["Multi-hit Resist", false], ["Boss Damage Boost", true], ["PvE Damage Tolerance", false], ["MP", false], ["Cooldown Reduction", true], ["Status Effect Chance", false]]) {
    assert.equal(C.isOffensive(name), off, name);
  }
});

test("the strongest players: counted without names", () => {
  const top = C.topOf("Ranger");
  assert.ok(top.n >= 20);
  const json = JSON.stringify(D.top);
  for (const key of ["name\":", "characterId", "serverId"]) assert.ok(!json.includes(key), key);
  const pool = C.soulPool(idOf("Enraged Kromede Longbow", 86), "Ranger");
  const picks = C.topPicks("Ranger", "MainHand", pool);
  assert.equal(picks.length, 3);
  assert.ok(picks.includes("Combat Speed"));
});

test("questlog.gg builds: what the Armory bookmark saves, read as references", () => {
  const bow = idOf("Enraged Kromede Longbow", 86);
  const doc = { armory: "questlog", url: "https://questlog.gg/aion-2/en/character-builder/x",
    characterBuilder: {
      character: { name: "Tester", classId: "ranger", url: "x" },
      builds: [{ id: 7, name: "Made-up build", daevanionBuildId: 70, skillBuildId: 71,
        equipment: {
          weapon: { id: String(bow), lvl: 17, substats: { 0: { id: "combatspeed", value: 1229 }, 1: { id: "str", value: 31 }, 2: { id: null, value: null } },
            magicstone: { id: "1", substats: { 0: { statId: "weaponfixingdamage", value: 10 }, 1: { statId: "weaponfixingdamage", value: 3 } } },
            godstone: { 0: { id: "513850011" } } },
          leftRing: { id: "", lvl: 0, substats: {} },
        },
        arcana: { grail: { id: "810130001", lvl: 5, subSkills: { 0: { id: "14010000", lvl: 3 }, 1: { id: null, lvl: 4 } } }, libra: { id: "", lvl: 0 } } }],
      externalBuilds: [] },
    daevanionPlanner: { builds: [{ id: 70, name: "Boards", selectedNodes: { 31: ["310037", "310038"] } }], externalBuilds: [] },
    skillBuilder: { builds: [{ id: 71, name: "Skills", skills: { 14010000: { id: "14010000", lvl: 20, specializations: [14010050, 14010020, 14010030] } } }], externalBuilds: [] },
  };
  const [b] = C.readQuestlogBuilds(doc);
  assert.equal(b.name, "Made-up build");
  assert.equal(b.author, "Tester");
  const weapon = b.gear.find((g) => g.slot === "MainHand");
  assert.deepEqual([weapon.id, weapon.enchant, weapon.amplify], [bow, 15, 2]);
  assert.deepEqual(b.soul.MainHand, [{ kind: "stat", name: "Combat Speed", value: "12.29%" }, { kind: "stat", name: "Might", value: "31" }]);
  assert.deepEqual(weapon.stones.map((s) => s.grade), ["Unique", "Rare"]);
  assert.equal(weapon.theostones[0].grade, "Rare");
  const arc = b.gear.find((g) => g.slot === "Arcana1");
  assert.equal(arc.name, "Chalice of Vigor");
  assert.deepEqual(b.soul.Arcana1, [{ kind: "skill", name: "Deadshot", value: "+3" }]);
  assert.deepEqual(b.skills, [{ id: 14010000, name: "Deadshot", level: 20, spec: [2, 3, 5] }]);
  assert.deepEqual(b.daev, { 31: [310037, 310038] });
  // Its Daevanion points counted on the character's board; the gear score
  // from the items, levels, stones and those points.
  const snap = { boards: [{ id: 31, name: "Nezekan", maxPoints: 134, nodes: [
    { id: 310037, grade: "Rare", type: "SkillLevel" }, { id: 310038, grade: "Common", type: "Stat" }, { id: 310039, grade: "Legend", type: "Stat" }] }] };
  const ref = C.questlogReference(b, snap);
  assert.deepEqual(ref.boards, [{ name: "Nezekan", points: 3, total: 134 }]);
  const il = D.items[String(bow)][3];
  assert.equal(ref.gearScore, il + 15 + 2 * 5 + 4 + 2 + 3 + (80 + 5) + 3);
  // Skills against it by id, with its specializations.
  const [s] = C.compareSkills([{ id: 14010000, name: "Deadshot", level: 18 }], ref);
  assert.deepEqual([s.refLevel, s.refSpec], [20, [2, 3, 5]]);
  // The probe's file (the page state under "pinia") reads the same.
  const probe = { pinia: { A2CharacterBuilder: doc.characterBuilder, A2DaevanionPlanner: doc.daevanionPlanner, A2SkillBuilder: doc.skillBuilder } };
  assert.equal(C.readQuestlogBuilds(probe).length, 1);
  assert.deepEqual(C.readQuestlogBuilds({ something: 1 }), []);
});

test("Daevanion: what the reference takes, summed by stat", () => {
  const board = { name: "B", nodes: [
    { id: 1, row: 8, col: 8, grade: "None", open: true, effects: [], type: "Start" },
    { id: 2, row: 8, col: 9, grade: "Common", open: true, effects: ["Critical Hit +5"], type: "Stat" },
    { id: 3, row: 8, col: 10, grade: "Common", open: false, effects: ["Critical Hit +5"], type: "Stat" },
  ] };
  const [r] = C.boardOffense([board], "pve", new Set([3]));
  assert.deepEqual([r.name, r.have, r.ref, r.closed], ["Critical Hit", 5, 5, 5]);
});

test("changing a piece: the gear score it gives, at +0, from which level, the enhancing", () => {
  const kromede = idOf("Enraged Kromede Longbow", 86);
  const il = D.items[String(kromede)][3];
  const mine = { slot: "MainHand", id: 1, name: "Old bow", il: 70, enchant: 15, amplify: 1, stones: [{ grade: "Legend" }] };
  const up = C.upgradeOf(mine, { slot: "MainHand", id: kromede, name: "Enraged Kromede Longbow", il, enchant: 15, amplify: 5 }, null);
  assert.equal(up.same, false);
  assert.equal(up.gain, il + 15 + 25 - (70 + 15 + 5));
  assert.equal(up.at0, il - 90);
  // Enhance first, then Amplify, to match the old piece's 90.
  assert.deepEqual(up.even, il >= 90 ? { enchant: 0, amplify: 0 } : { enchant: Math.min(90 - il, 15), amplify: 0 });
  const full = C.enhanceCost({ id: kromede }, { enchant: 0, amplify: 0 }, { enchant: 15, amplify: 5 });
  near(up.cost.kinah, full.kinah, 1e-6, "from +0");
  assert.ok(up.cost.known && up.perPoint > 0);
  assert.equal(up.stones.mine, 3, "the old piece's Manastones apart");
  // The same item goes on from its own levels.
  const same = C.upgradeOf({ ...mine, id: kromede, il }, { id: kromede, il, enchant: 15, amplify: 5 }, null);
  assert.equal(same.same, true);
  assert.equal(same.gain, 4 * 5);
  near(same.cost.kinah, C.enhanceCost({ id: kromede }, { enchant: 15, amplify: 1 }, { enchant: 15, amplify: 5 }).kinah, 1e-6, "from A1");
  // A piece without tables (an Arcana card): the cost isn't known.
  const arc = C.upgradeOf({ id: 810130001, il: 80, enchant: 3 }, { id: 810130001, il: 80, enchant: 5 }, null);
  assert.deepEqual([arc.gain, arc.cost.known, arc.perPoint], [2, false, null]);
});

test("the way to a target gear score with pieces changed: cheaper where a change is", () => {
  const kromede = idOf("Enraged Kromede Longbow", 86);
  const il = D.items[String(kromede)][3];
  // An old bow at its top: only a change gives more.
  const snap = { items: [{ slot: "MainHand", id: kromede, name: "Enraged Kromede Longbow", il, grade: "Unique", enchant: 15, amplify: 5, maxEnchant: 15, maxAmplify: 5 },
    { slot: "Amulet", id: 1, name: "Old amulet", il: 13, grade: "Rare", enchant: 0, amplify: 0, maxEnchant: 0 }] };
  const amulet = Number(Object.keys(D.items).find((k) => D.items[k][2] === "Amulet" && D.items[k][3] >= 60 && D.items[k][5]));
  const row = D.items[String(amulet)];
  const swaps = [{ slot: "Amulet", item: { slot: "Amulet", id: amulet, name: row[0], il: row[3], grade: row[1], enchant: 0, amplify: 0 } }];
  const plain = C.planGearScore(snap, 100, 120, null);
  assert.equal(plain.reached, false);
  const plan = C.planWithSwaps(snap, 100, 120, null, swaps);
  assert.equal(plan.reached, true);
  assert.equal(plan.swaps.length, 1);
  assert.equal(plan.swaps[0].up.gain, row[3] - 13);
  // Nothing to change: the same as enhancing alone.
  assert.equal(C.planWithSwaps(snap, 100, 120, null, []).swaps.length, 0);
});

test("pieces worn in pairs are put against the reference's item to item", () => {
  const asc = idOf("Ascension Bracelet"), lib = idOf("Liberator Bracelet");
  const snap = { items: [{ slot: "Bracelet1", id: lib, name: "Liberator Bracelet" }, { slot: "Bracelet2", id: asc, name: "Ascension Bracelet" }] };
  const ref = { gear: [{ slot: "Bracelet1", id: asc, name: "Ascension Bracelet" }, { slot: "Bracelet2", id: lib, name: "Liberator Bracelet" }],
    soul: { Bracelet1: [{ name: "Time [Siel]" }] } };
  assert.deepEqual(C.pairedSlots(snap, ref), { Bracelet1: "Bracelet2", Bracelet2: "Bracelet1" });
  const rows = C.compareGear(snap, ref);
  assert.deepEqual(rows.map((r) => [r.slot, r.mine.name, r.ref.name]), [["Bracelet1", "Liberator Bracelet", "Liberator Bracelet"], ["Bracelet2", "Ascension Bracelet", "Ascension Bracelet"]]);
  assert.deepEqual(Object.keys(C.alignReference(snap, ref).soul), ["Bracelet2"], "its soul binding goes with it");
  // Already matched, or nothing to gain: as it was.
  assert.deepEqual(C.pairedSlots({ items: [{ slot: "Bracelet1", id: asc, name: "Ascension Bracelet" }] }, ref), {});
});

test("item icons: the game's own name where Aion2Data's list names another", () => {
  const helm = idOf("Nuakum Helm", 86);
  assert.match(C.itemIcon(helm), /^Icon_Equip_AR_/);
  assert.equal(C.itemIcon(idOf("Enraged Kromede Longbow", 86)), D.items[String(idOf("Enraged Kromede Longbow", 86))][4]);
});

test("Goals: slots left out are neither enhanced nor changed", () => {
  const kromede = idOf("Enraged Kromede Longbow", 86);
  const il = D.items[String(kromede)][3];
  const snap = { items: [{ slot: "MainHand", id: kromede, name: "Bow", il, grade: "Unique", enchant: 10, amplify: 0, maxEnchant: 15, maxAmplify: 5 },
    { slot: "Belt", id: 1, name: "Old belt", il: 13, grade: "Rare", enchant: 0, amplify: 0, maxEnchant: 0 }] };
  const plan = C.planWithSwaps(snap, 100, 103, null, [], new Set(["MainHand"]));
  assert.equal(plan.pieces.length, 0);
  assert.equal(plan.reached, false);
  assert.ok(C.planWithSwaps(snap, 100, 103, null, [], null).reached);
});
