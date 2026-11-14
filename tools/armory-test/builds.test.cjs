// The Armory's builds tied to characters (qml/aion2/buildkit.js): progress,
// next steps, steps ticked by the next reading, copies, fights beside the
// build. Made-up characters.
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { D, C, BK } = require(path.join(__dirname, "kit.cjs"));

const idOf = (name, il) => Number(Object.keys(D.items).find((k) => D.items[k][0] === name && (!il || D.items[k][3] === il)));
const bow = idOf("Enraged Kromede Longbow", 86);
const bracelet = idOf("Ascension Bracelet", 51);

function snapOf(bowAt, braceletAt, open) {
  return {
    at: 1, profile: { name: "[Character 2]", serverId: 2305, className: "Ranger", gs: null, cp: 50000 },
    items: [
      { slot: "MainHand", id: bow, name: D.items[bow][0], grade: "Unique", il: 86, enchant: bowAt, amplify: 0, maxEnchant: 15, maxAmplify: 5 },
      { slot: "Bracelet1", id: bracelet, name: D.items[bracelet][0], grade: "Legend", il: 51, enchant: braceletAt, amplify: 0, maxEnchant: 15, maxAmplify: 0 },
    ],
    skills: [{ id: 1, name: "Snipe", category: "Active", level: 12, acquired: true }],
    boards: [{ id: 31, name: "Nezekan", points: open ? 3 : 0, maxPoints: 6, nodes: [
      { id: 1, type: "Start", grade: "Common", open: true, row: 0, col: 0, effects: [] },
      { id: 2, type: "Stat", grade: "Legend", open: !!open, row: 0, col: 1, effects: ["Attack +5"] },
      { id: 3, type: "Stat", grade: "Legend", open: false, row: 0, col: 2, effects: ["Attack +5"] },
    ] }],
    stats: {},
  };
}

function buildOf() {
  const ref = { name: "Bossing", source: "questlog.gg", gear: [
    { slot: "MainHand", id: bow, name: D.items[bow][0], grade: "Unique", il: 86, enchant: 15, amplify: 0 },
    { slot: "Bracelet1", id: bracelet, name: D.items[bracelet][0], grade: "Legend", il: 51, enchant: 13, amplify: 0 },
  ], skills: [], soul: {}, daev: { 31: [2, 3] }, deity: {}, boards: [] };
  const b = BK.newBuild("PvE Bossing", "PvE", "Ranger", ref, "questlog.gg", 1000);
  b.targets.skills.Snipe = 14;
  return b;
}

test("a build on a character: active, on two characters, taken off", () => {
  const st = BK.emptyState();
  const b = BK.addBuild(st, buildOf());
  BK.ensureChar(st, "c1", { name: "[Character 2]" });
  BK.assign(st, "c1", b.id, 3000);
  BK.assign(st, "c2", b.id, 2400);
  assert.equal(BK.activeBuild(st, "c1").id, b.id);
  assert.deepEqual(BK.charsOf(st, b.id).map((c) => c.key), ["c1", "c2"]);
  assert.equal(st.chars.c1.start[b.id], 3000);
  BK.unassign(st, "c2", b.id);
  assert.equal(BK.activeBuild(st, "c2"), null);
  BK.removeBuild(st, b.id);
  assert.equal(BK.activeBuild(st, "c1"), null);
  assert.deepEqual(st.order, []);
});

test("progress: gear, skills and Daevanion of the build, each the same weight", () => {
  const b = buildOf();
  const ch = { mineAt: {}, start: {}, done: {} };
  const pr = BK.progress(snapOf(15, 10, false), b, ch, null);
  const by = Object.fromEntries(pr.areas.map((a) => [a.id, a]));
  assert.deepEqual([by.gear.have, by.gear.of], [1, 2]);
  assert.deepEqual([by.skills.have, by.skills.of], [0, 1]);
  assert.deepEqual([by.daevanion.have, by.daevanion.of], [0, 6]);
  assert.ok(Math.abs(pr.total - (0.5 + 0 + 0) / 3) < 1e-9);
  // All reached.
  const done = BK.progress(Object.assign(snapOf(15, 13, true), { boards: [Object.assign(snapOf(15, 13, true).boards[0], { nodes: snapOf(15, 13, true).boards[0].nodes.map((n) => Object.assign({}, n, { open: true })) })],
    skills: [{ id: 1, name: "Snipe", category: "Active", level: 14, acquired: true }] }), b, ch, null);
  assert.equal(done.total, 1);
});

test("next steps cheapest first, ticked when the next reading shows them done", () => {
  const b = buildOf();
  const ch = { mineAt: {}, start: {}, done: {} };
  const before = BK.steps(snapOf(15, 10, false), b, ch, null);
  assert.deepEqual(before.map((s) => s.kind), ["daevanion", "skill", "gear"]);
  assert.match(before[2].what, /Bracelet \+10 → \+13/);
  assert.ok(before[2].kinah > 0 && before[2].gain === 3);
  const after = BK.steps(snapOf(15, 13, true), b, ch, null);
  const gone = BK.markDone(ch, b.id, before, after, 5000);
  assert.deepEqual(gone.map((s) => s.kind).sort(), ["daevanion", "gear"]);
  // The Daevanion step is a new one (one node left): the old one counts done.
  assert.equal(after.filter((s) => s.kind === "daevanion").length, 1);
  assert.equal(BK.recentDone(ch, b.id, 6000).length, 2);
  assert.equal(BK.recentDone(ch, b.id, 5000 + 25 * 3600 * 1000).length, 0);
});

test("slots left out count neither for progress nor as a step", () => {
  const b = buildOf();
  b.targets.skip.Bracelet1 = true;
  const ch = { mineAt: {}, start: {}, done: {} };
  const pr = BK.progress(snapOf(15, 10, false), b, ch, null);
  assert.deepEqual(pr.areas.find((a) => a.id === "gear").of, 1);
  assert.ok(!BK.steps(snapOf(15, 10, false), b, ch, null).some((s) => s.kind === "gear"));
});

test("a goal gear score counts from where the character stood", () => {
  const b = buildOf();
  b.targets.goalGs = 300;
  const snap = snapOf(15, 10, false);
  const gs = BK.gsOf(snap);
  const ch = { mineAt: {}, start: { [b.id]: gs - 10 }, done: {} };
  const goal = BK.progress(snap, b, ch, null).areas.find((a) => a.id === "goal");
  assert.equal(goal.have, 10);
  assert.equal(goal.of, 300 - (gs - 10));
});

test("versions: changes within 10 minutes are one", () => {
  const b = buildOf();
  BK.noteChange(b, "Ring 2", 2000);
  BK.noteChange(b, "skills", 3000);
  assert.equal(b.version, 2);
  assert.match(b.versions[1].what, /Ring 2; skills/);
  BK.noteChange(b, "soul", 3000 + 11 * 60000);
  assert.equal(b.version, 3);
});

test("a build copied from a character aims at what it has", () => {
  const snap = snapOf(15, 13, true);
  const ref = BK.referenceOfSnapshot(snap);
  assert.equal(ref.gear.length, 2);
  assert.deepEqual(ref.daev, { 31: [2] });
  const b = BK.newBuild("Copy", "PvE", "Ranger", ref, "copy", 1);
  b.targets = BK.targetsOfSnapshot(snap);
  const pr = BK.progress(snap, b, { mineAt: {}, start: {}, done: {} }, null);
  assert.equal(pr.total, 1);
  // On a weaker character: the bracelet's levels to go.
  const weaker = BK.progress(snapOf(15, 10, false), b, { mineAt: {}, start: {}, done: {} }, null);
  assert.ok(weaker.total < 1);
});

test("boss fights beside the build: the character's damage, the build's version then", () => {
  const hist = [{ at: 100, p: 40, b: "x", bv: 1 }, { at: 300, p: 55, b: "x", bv: 2 }];
  const list = [
    { id: "f2", boss: "Boss A", start: 400, duration: 10000, train: false, players: [["[Character 2]", 200000], ["Other", 1]] },
    { id: "f1", boss: "Boss A", start: 200, duration: 20000, train: false, players: [["[Character 2]", 200000]] },
    { id: "f0", boss: "Scarecrow", start: 250, duration: 10000, train: true, players: [["[Character 2]", 5]] },
    { id: "old", boss: "Boss B", start: 50, duration: 10000, train: false },
  ];
  const f = BK.fightsOf(list, "[Character 2]", hist, "x");
  assert.deepEqual(f.map((x) => [x.id, x.dps, x.p, x.v]), [["f2", 20000, 55, 2], ["f1", 10000, 40, 1]]);
});

test("the old Armory's files: characters, history merged by time, references", () => {
  const keyOf = (n, s) => n + "@" + Number(s);
  const files = {
    settings: { chars: { "c-2305-_Character_2_": { name: "[Character 2]", serverId: 2305, className: "Ranger" } }, goalGs: 3200 },
    "c-2305-_Character_2_": snapOf(10, 5),
    "hc-2305-_Character_2_": [{ at: 100, cp: 1 }, { at: 200, cp: 2 }, null, { at: "x" }],
    "tc-2305-_Character_2_": { skills: { Snipe: 16 }, mineAt: { MainHand: { enchant: 15 } } },
    "hc-1-orphan": [{ at: 5 }],
    references: { active: 0, list: [{ id: 7, name: "Old ref", items: [] }] },
    "bad key!": {},
  };
  const old = BK.readOld(files, keyOf);
  assert.equal(old.chars.length, 1);
  const c = old.chars[0];
  assert.equal(c.key, "[Character 2]@2305");
  assert.equal(c.history.length, 2);
  assert.ok(c.snap);
  assert.equal(old.refs.length, 1);
  assert.equal(old.goalGs, 3200);
  assert.ok(BK.hasTargets(c.targets));
  const t = BK.targetsFromOld(c.targets, old.goalGs);
  assert.equal(t.skills.Snipe, 16);
  assert.equal(t.goalGs, 3200);
  assert.equal(t.mineAt, undefined);
  const merged = BK.mergeHistory([{ at: 200, cp: 9 }, { at: 300, cp: 3 }], c.history, 600);
  assert.deepEqual(merged.map((e) => [e.at, e.cp]), [[100, 1], [200, 9], [300, 3]]);
  assert.equal(BK.mergeHistory(merged, [], 2).length, 2);
});
