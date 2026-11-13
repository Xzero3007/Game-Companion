// Loads qml/aion2/armorykit.js and buildkit.js (QML JavaScript libraries)
// into node for the tests, with the package's data.
const fs = require("node:fs");
const path = require("node:path");
const root = path.join(__dirname, "..", "..");
const read = (f) => fs.readFileSync(path.join(root, f), "utf8").replace(/^\.pragma library\n/, "").replace(/^\.import .*\n/gm, "");
(0, eval)(read("qml/aion2/armorykit.js") + "\nglobalThis.__AK = { load, NC, get C() { return C; } };");
const D = JSON.parse(fs.readFileSync(path.join(root, "crates/aion2/data/armory/data.json"), "utf8"));
const C = globalThis.__AK.load(D);
globalThis.AK = globalThis.__AK;
(0, eval)("(function(){" + read("qml/aion2/buildkit.js") + "\nglobalThis.__BK = { emptyState, newBuild, ensureChar, activeBuild, assign, unassign, charsOf, removeBuild, addBuild, noteChange, targetsOf, slotTarget, gearRows, soulPieces, daevOfBuild, gsOf, progress, steps, markDone, recentDone, referenceOfSnapshot, targetsOfSnapshot, targetsOfTop, historyEntry, fightsOf, chanceShort, KINDS };})()");
module.exports = { D, C, NC: globalThis.__AK.NC, BK: globalThis.__BK };
