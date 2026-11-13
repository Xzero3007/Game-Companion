.pragma library
.import "armorykit.js" as AK
// The Armory's builds, tied to characters (the person, 2026-11-13: builds
// to track better than the old app's references). A build is what a
// character aims at: a reference (gear with soul bindings, skills,
// Daevanion nodes, deity stats, as the old Armory's references) plus the
// targets that were kept apart there (soul binding wishes, skill levels,
// compared items, levels, picks, slots left out, a goal gear score). Each
// character can have several builds, one active; one build can be active on
// several characters (each keeps its own progress). Everything here is
// sums on what NC's page showed (AK.C, the old Armory's calc.js): no page,
// no state of its own; ArmoryStore.qml keeps the state, the tests run it in
// node (tools/armory-test.js).

var KINDS = ["PvE", "PvP", "Both"];
var DONE_SHOWN_MS = 24 * 3600 * 1000;

function C() { return AK.C; }

/** { builds: { id: build }, chars: { key: char }, order: [build ids] } */
function emptyState() {
    return { v: 1, builds: {}, chars: {}, order: [], settings: { tab: "overview", current: null, region: null, daevSide: "pve", goalSwaps: true } };
}

function emptyTargets() {
    return { soul: {}, skills: {}, compare: {}, levels: {}, pick: {}, skip: {}, goalGs: null };
}

/** A new build: from a reference (or none), for a class. */
function newBuild(name, kind, cls, ref, source, now) {
    var id = "b" + Math.floor(now || Date.now()).toString(36) + Math.floor(Math.random() * 1296).toString(36);
    return {
        id: id, name: name || "New build", kind: KINDS.indexOf(kind) >= 0 ? kind : "PvE", cls: cls || "",
        source: source || (ref && ref.source) || "own", ref: ref || null, targets: emptyTargets(),
        version: 1, versions: [{ v: 1, at: now || Date.now(), what: "made" + (source ? " from " + source : "") }], made: now || Date.now()
    };
}

/** A character's record: who it is on NC's pages and its builds. */
function charOf(state, key) {
    return state.chars[key] || null;
}
function ensureChar(state, key, info) {
    var c = state.chars[key];
    if (!c) c = state.chars[key] = { builds: [], active: null, mineAt: {}, done: {}, start: {} };
    for (var k in info || {}) if (info[k] !== undefined && info[k] !== null && info[k] !== "") c[k] = info[k];
    if (!c.builds) c.builds = [];
    if (!c.mineAt) c.mineAt = {};
    if (!c.done) c.done = {};
    if (!c.start) c.start = {};
    return c;
}

/** The build a character tracks now, or null. */
function activeBuild(state, key) {
    var c = state.chars[key];
    if (!c || !c.active) return null;
    return state.builds[c.active] || null;
}

/** Puts a build on a character (and makes it active there). */
function assign(state, key, buildId, gsNow) {
    var c = ensureChar(state, key);
    if (c.builds.indexOf(buildId) < 0) c.builds.push(buildId);
    c.active = buildId;
    if (gsNow && !c.start[buildId]) c.start[buildId] = gsNow;
}
/** Takes a build off a character. */
function unassign(state, key, buildId) {
    var c = state.chars[key];
    if (!c) return;
    c.builds = c.builds.filter(function (b) { return b !== buildId; });
    if (c.active === buildId) c.active = c.builds[0] || null;
}
/** The characters a build is on: [{ key, active }]. */
function charsOf(state, buildId) {
    var out = [];
    for (var key in state.chars) {
        var c = state.chars[key];
        if ((c.builds || []).indexOf(buildId) >= 0) out.push({ key: key, active: c.active === buildId, name: c.name || key });
    }
    return out;
}
function removeBuild(state, buildId) {
    for (var key in state.chars) unassign(state, key, buildId);
    delete state.builds[buildId];
    state.order = (state.order || []).filter(function (b) { return b !== buildId; });
}
function addBuild(state, build) {
    state.builds[build.id] = build;
    if (!state.order) state.order = [];
    state.order.push(build.id);
    return build;
}

/** A change to a build that changes what it aims at: a new version, so
 *  HISTORY shows progress against the build as it was. Several changes
 *  within 10 minutes are one version. */
function noteChange(build, what, now) {
    now = now || Date.now();
    var last = build.versions[build.versions.length - 1];
    if (last && now - last.at < 10 * 60000 && last.v === build.version && last.v > 1) {
        if (last.what.indexOf(what) < 0) last.what = (last.what + "; " + what).slice(0, 160);
        last.at = now;
        return;
    }
    build.version++;
    build.versions.push({ v: build.version, at: now, what: what });
    if (build.versions.length > 40) build.versions.splice(0, build.versions.length - 40);
}

/** The targets as the old Armory's code wants them, with the character's
 *  own `mineAt` (your piece enhanced on). */
function targetsOf(build, ch) {
    var t = build ? build.targets : emptyTargets();
    return { soul: t.soul || {}, skills: t.skills || {}, compare: t.compare || {}, levels: t.levels || {}, pick: t.pick || {},
        skip: t.skip || {}, goalGs: t.goalGs || null, mineAt: (ch && ch.mineAt) || {} };
}

// ---- the old Armory's slot targets, kept as they were ------------------

function pieceOf(slot, id, enchant, amplify) {
    var row = C().itemRow(id);
    return row ? { slot: slot, id: Number(id), name: row[0], grade: row[1], il: row[3], icon: C().itemIcon(id), enchant: enchant || 0, amplify: amplify || 0 } : null;
}
function refPieceAt(targets, slot, b) {
    return b && targets.levels && targets.levels[slot] ? Object.assign({}, b, targets.levels[slot]) : b;
}
/** A slot's target: { piece, from: reference | yours | compared } or null. */
function slotTarget(targets, slot, mine, refPiece) {
    var pick = targets.pick && targets.pick[slot];
    if (pick && pick.kind === "mine" && mine) return { piece: Object.assign({}, mine, (targets.mineAt || {})[slot] || {}), from: "yours" };
    if (pick && pick.kind === "cand") {
        var c = (targets.compare[slot] || []).find(function (x) { return x.id === pick.id; });
        var p = c ? pieceOf(slot, c.id, c.enchant, c.amplify) : null;
        if (p) return { piece: p, from: "compared" };
    }
    return refPiece && refPiece.id ? { piece: refPieceAt(targets, slot, refPiece), from: "reference" } : null;
}
/** The reference with its paired pieces put against yours. */
function aligned(snap, ref) {
    return ref && snap ? C().alignReference(snap, ref) : ref;
}

/** Every slot against the build: { slot, mine, ref, target, up, reached,
 *  skipped }. */
function gearRows(snap, build, targets, prices) {
    if (!snap) return [];
    var ref = build ? build.ref : null;
    var rows = C().compareGear(snap, ref);
    var seen = {};
    var out = rows.map(function (r) {
        seen[r.slot] = true;
        var t = slotTarget(targets, r.slot, r.mine, r.ref);
        var up = t ? C().upgradeOf(r.mine, t.piece, prices) : null;
        var reached = !!t && !!r.mine && (r.mine.id === t.piece.id || r.mine.name === t.piece.name) && (up ? up.gain <= 0 : true);
        return { slot: r.slot, mine: r.mine, ref: r.ref, status: r.status, levelsToGo: r.levelsToGo, target: t, up: up,
            reached: reached, skipped: !!(targets.skip || {})[r.slot] };
    });
    // A slot only compared (no reference piece, nothing worn) still counts.
    for (var slot in targets.pick || {}) {
        if (seen[slot]) continue;
        var t2 = slotTarget(targets, slot, null, null);
        if (t2) out.push({ slot: slot, mine: null, ref: null, status: "missing", target: t2, up: C().upgradeOf(null, t2.piece, prices), reached: false, skipped: !!(targets.skip || {})[slot] });
    }
    return out;
}

/** The pieces with a soul binding and the wishes on them (the old Soul
 *  binding tab's soulPieces): [{ it, slot, pool, own, ref, refPool }]. */
function soulPieces(snap, build) {
    var cls = (snap.profile && snap.profile.className) || "";
    var al = aligned(snap, build ? build.ref : null);
    var refBySlot = {};
    ((al && al.gear) || []).forEach(function (g) { refBySlot[g.slot] = g; });
    var out = [], none = [];
    C().SLOT_ORDER.forEach(function (slot) {
        var it = (snap.items || []).find(function (x) { return x.slot === slot; });
        if (!it) return;
        var ref = refBySlot[slot];
        var other = ref && ref.id && ref.id !== it.id ? ref : null;
        var own = C().soulPool(it.id, cls);
        var refPool = other ? C().soulPool(other.id, cls) : null;
        if (own || refPool) out.push({ it: it, slot: slot, pool: own || refPool, own: !!own, ref: other, refPool: refPool });
        else none.push(it);
    });
    return { cls: cls, out: out, none: none };
}

/** The build's Daevanion nodes on the character's boards (its node ids per
 *  board, as questlog.gg names them and NC's page too): { has(board, node),
 *  open, total, points, openPoints, nodes: true } or, for a build with
 *  points per board only, the points; null without either. */
function daevOfBuild(snap, build) {
    var ref = build ? build.ref : null;
    if (!ref || !snap) return null;
    var d = ref.daev || {};
    var sets = {};
    var any = false;
    for (var b in d) { sets[b] = new Set(d[b] || []); if ((d[b] || []).length) any = true; }
    var has = function (board, n) { var s = sets[String(board.id)]; return !!s && s.has(n.id); };
    if (any) {
        var open = 0, total = 0, points = 0, openPoints = 0;
        (snap.boards || []).forEach(function (board) {
            (board.nodes || []).forEach(function (n) {
                if (!has(board, n) || n.type === "Start") return;
                var p = C().nodePoints(n.grade);
                total++; points += p;
                if (n.open) { open++; openPoints += p; }
            });
        });
        if (total) return { has: has, nodes: true, open: open, total: total, points: points, openPoints: openPoints };
    }
    // No nodes: its points per board (a saved page).
    var rb = C().referenceBoards(ref, snap);
    if (!rb.length) return null;
    var mine = {};
    (snap.boards || []).forEach(function (bd) { mine[bd.name] = bd.points || 0; });
    var want = 0, have = 0;
    rb.forEach(function (bd) { want += bd.points; have += Math.min(bd.points, mine[bd.name] || 0); });
    return want ? { has: null, nodes: false, open: have, total: want, points: want, openPoints: have } : null;
}

/** The gear score now: the game's (NC's page) else the sum. */
function gsOf(snap) {
    if (!snap) return 0;
    return (snap.profile && snap.profile.gs) || C().gearScore(snap).total;
}

/** How far a character is on a build: { total (0..1 or null), areas: [{ id,
 *  name, have, of, p, text }] }. Each area with something to reach counts
 *  the same. */
function progress(snap, build, ch, prices) {
    if (!snap || !build) return { total: null, areas: [] };
    var targets = targetsOf(build, ch);
    var areas = [];
    // Gear: slots at their target.
    var rows = gearRows(snap, build, targets, prices).filter(function (r) { return r.target && !r.skipped && !/^Arcana/.test(r.slot); });
    if (rows.length) {
        var at = rows.filter(function (r) { return r.reached; }).length;
        areas.push({ id: "gear", name: "Gear", have: at, of: rows.length, text: at + " of " + rows.length + " slots at target" });
    }
    // Soul binding: wanted properties on the pieces.
    var sp = soulPieces(snap, build);
    var wantedN = 0, hits = 0;
    sp.out.forEach(function (x) {
        var w = C().soulCompare(x.it, targets.soul[x.slot], x.pool).wanted;
        wantedN += w.length;
        hits += w.filter(function (y) { return y.have; }).length;
    });
    if (wantedN) areas.push({ id: "soul", name: "Soul binding", have: hits, of: wantedN, text: hits + " of " + wantedN + " wanted properties" });
    // Skills: target levels reached.
    var skills = C().skillSources(snap);
    var tracked = skills.filter(function (s) { return targets.skills[s.name] != null; });
    if (tracked.length) {
        var reached = tracked.filter(function (s) { return s.level >= targets.skills[s.name]; }).length;
        areas.push({ id: "skills", name: "Skills", have: reached, of: tracked.length, text: reached + " of " + tracked.length + " target levels" });
    }
    // Daevanion: the build's nodes (or points) open.
    var dv = daevOfBuild(snap, build);
    if (dv) areas.push({ id: "daevanion", name: "Daevanion", have: dv.openPoints, of: dv.points,
        text: dv.nodes ? dv.open + " of " + dv.total + " nodes of the build" : dv.openPoints + " of " + dv.points + " points of the build" });
    // The goal gear score: from where the character stood when the build came.
    var gs = gsOf(snap);
    if (targets.goalGs && targets.goalGs > 0) {
        var start = (ch && ch.start && ch.start[build.id]) || gs;
        var span = Math.max(1, targets.goalGs - Math.min(start, targets.goalGs - 1));
        var done = Math.max(0, Math.min(span, gs - Math.min(start, targets.goalGs - 1)));
        areas.push({ id: "goal", name: "Gear score goal", have: gs >= targets.goalGs ? span : done, of: span,
            text: C().fmt(gs) + " of " + C().fmt(targets.goalGs) });
    }
    areas.forEach(function (a) { a.p = a.of ? Math.max(0, Math.min(1, a.have / a.of)) : 0; });
    var total = areas.length ? areas.reduce(function (s, a) { return s + a.p; }, 0) / areas.length : null;
    return { total: total, areas: areas };
}

var levelText = function (x) { return "+" + ((x && x.enchant) || 0) + (x && x.amplify ? " A" + x.amplify : ""); };

/** The next steps, cheapest first: free ones (Daevanion points, skill
 *  points) first, then the gear by Kinah a gear score point, then the soul
 *  bindings (a matter of luck). [{ id, kind, what, where, kinah, gain }]:
 *  an id names what is to be reached, so a step that is gone from the
 *  next reading's list was done. */
function steps(snap, build, ch, prices) {
    if (!snap || !build) return [];
    var targets = targetsOf(build, ch);
    var out = [];
    var label = function (slot) { return C().SLOT_LABEL[slot] || slot; };
    // Daevanion: the build's closed nodes, per board.
    var dv = daevOfBuild(snap, build);
    if (dv && dv.nodes) {
        (snap.boards || []).forEach(function (board) {
            var closed = (board.nodes || []).filter(function (n) { return dv.has(board, n) && !n.open && n.type !== "Start"; });
            if (!closed.length) return;
            var pts = closed.reduce(function (s, n) { return s + C().nodePoints(n.grade); }, 0);
            out.push({ id: "daev:" + board.name + ":" + closed.map(function (n) { return n.id; }).sort().join("."), kind: "daevanion", order: 0,
                what: "Daevanion " + board.name + ": " + closed.length + " node" + (closed.length === 1 ? "" : "s") + " of the build",
                where: pts + " points", kinah: 0, gain: pts });
        });
    } else if (dv && dv.openPoints < dv.points) {
        out.push({ id: "daev:points:" + dv.points, kind: "daevanion", order: 0, what: "Daevanion: " + (dv.points - dv.openPoints) + " points to the build's",
            where: "points per board", kinah: 0, gain: dv.points - dv.openPoints });
    }
    // Skills under their target.
    C().skillSources(snap).forEach(function (s) {
        var t = targets.skills[s.name];
        if (t == null || s.level >= t) return;
        var where = "";
        if (s.category === "Dp") where = "Stigma Shards";
        else {
            var way = C().skillWay(s, t);
            var parts = [];
            if (way.points) parts.push(way.points + " skill points");
            if (way.daevanion.length) parts.push(way.daevanion.map(function (n) { return n.board; }).join(", ") + " node" + (way.daevanion.length === 1 ? "" : "s"));
            if (way.gear) parts.push(way.gear + " from gear or Arcana");
            where = parts.join(", then ");
        }
        out.push({ id: "skill:" + s.name + ":" + t, kind: "skill", order: 1, what: "Skill " + s.name + " " + s.level + " → " + t, where: where, kinah: 0, gain: 0 });
    });
    // Gear: each slot's upgrade to its target, best value first.
    var gear = gearRows(snap, build, targets, prices).filter(function (r) { return r.target && r.up && r.up.gain > 0 && !r.skipped; });
    gear.sort(function (a, b) {
        return (a.up.perPoint == null) - (b.up.perPoint == null) || (a.up.perPoint || 0) - (b.up.perPoint || 0) || b.up.gain - a.up.gain;
    });
    gear.forEach(function (r) {
        var b = r.target.piece;
        var what = r.up.same ? label(r.slot) + " " + levelText(r.up.from) + " → " + levelText(r.up.to)
            : label(r.slot) + ": change to " + b.name + " " + levelText(r.up.to);
        var where = r.up.same ? (r.up.to.amplify > (r.up.from.amplify || 0) ? "Amplify" : "Enhance")
            : (r.target.from === "reference" ? "the build's item" : "your pick") + " · enhancing from +0";
        out.push({ id: "gear:" + r.slot + ":" + b.id + ":" + (b.enchant || 0) + ":" + (b.amplify || 0), kind: "gear", order: 2, slot: r.slot,
            what: what, where: where, kinah: r.up.cost.known ? r.up.cost.kinah : null, gain: r.up.gain });
    });
    // Soul bindings missing a wanted property.
    var sp = soulPieces(snap, build);
    sp.out.forEach(function (x) {
        var wanted = targets.soul[x.slot] || [];
        if (!wanted.length) return;
        var cmp = C().soulCompare(x.it, wanted, x.pool);
        var miss = cmp.wanted.filter(function (w) { return !w.have; });
        if (!miss.length) return;
        var p = C().soulChance(x.pool, wanted);
        out.push({ id: "soul:" + x.slot + ":" + wanted.slice().sort().join("|"), kind: "soul", order: 3, slot: x.slot,
            what: label(x.slot) + " soul binding: " + miss.map(function (w) { return w.name; }).join(", "),
            where: p > 0 ? "chance of a new binding " + chanceShort(p) : "not all on this piece", kinah: null, gain: 0 });
    });
    return out;
}

function chanceShort(p) {
    if (p == null) return "";
    if (p >= 0.995) return "certain";
    if (p >= 0.1) return Math.round(p * 100) + " %";
    if (p >= 0.01) return (Math.round(p * 1000) / 10) + " %";
    return "1 in " + Math.round(1 / p);
}

/** Steps gone between two readings were done: kept on the character per
 *  build ({ id: { what, at } }), the last 60. */
function markDone(ch, buildId, before, after, now) {
    if (!ch || !buildId) return [];
    var still = {};
    after.forEach(function (s) { still[s.id] = true; });
    var gone = before.filter(function (s) { return !still[s.id]; });
    var book = ch.done[buildId] || (ch.done[buildId] = {});
    gone.forEach(function (s) { book[s.id] = { what: s.what, kind: s.kind, at: now }; });
    var ids = Object.keys(book).sort(function (a, b) { return book[b].at - book[a].at; });
    ids.slice(60).forEach(function (id) { delete book[id]; });
    return gone;
}
/** The steps done in the last day, newest first. */
function recentDone(ch, buildId, now) {
    var book = (ch && ch.done && ch.done[buildId]) || {};
    return Object.keys(book).map(function (id) { return Object.assign({ id: id }, book[id]); })
        .filter(function (d) { return now - d.at < DONE_SHOWN_MS; })
        .sort(function (a, b) { return b.at - a.at; });
}

// ---- making builds ------------------------------------------------------

/** A build from a character as read: its gear, soul bindings, skill
 *  levels and open Daevanion nodes become what the build aims at (to put
 *  a strong character's build on another, or keep today's as a goal). */
function referenceOfSnapshot(snap) {
    var gear = (snap.items || []).filter(function (it) { return it.id; }).map(function (it) {
        return { slot: it.slot, id: it.id, name: it.name, grade: it.grade, il: it.il, icon: it.icon, enchant: it.enchant || 0, amplify: it.amplify || 0,
            shown: (it.enchant || 0) + (it.amplify || 0), guessed: false };
    });
    var soul = {};
    (snap.items || []).forEach(function (it) {
        var s = C().soulOf(it);
        if (s && s.length) soul[it.slot] = s.map(function (x) { return { name: x.name, value: x.value }; });
    });
    var skills = (snap.skills || []).filter(function (s) { return s.level > 0; }).map(function (s) {
        return { id: s.id, name: s.name, level: s.level, icon: s.icon, spec: [] };
    });
    var deity = {};
    ["Justice", "Freedom", "Illusion", "Life", "Time", "Destruction", "Death", "Wisdom", "Destiny", "Space"].forEach(function (k) {
        if (snap.stats && snap.stats[k]) deity[k] = snap.stats[k].value;
    });
    var boards = (snap.boards || []).map(function (b) { return { name: b.name, points: b.points || 0, total: b.maxPoints || 0 }; });
    var daev = {};
    (snap.boards || []).forEach(function (b) {
        var open = (b.nodes || []).filter(function (n) { return n.open && n.type !== "Start"; }).map(function (n) { return n.id; });
        if (open.length) daev[String(b.id)] = open;
    });
    var p = snap.profile || {};
    return { name: (p.name || "Character") + "'s build", source: "a copy of " + (p.name || "a character"), gear: gear, soul: soul, skills: skills,
        deity: deity, boards: boards, daev: daev, gearScore: gsOf(snap), className: p.className || "" };
}

/** Targets from a character as read: its skill levels and soul bindings
 *  as wishes (the same build on another character aims at them). */
function targetsOfSnapshot(snap) {
    var t = emptyTargets();
    (snap.skills || []).forEach(function (s) { if (s.level >= 10 && s.category !== "Passive") t.skills[s.name] = s.level; });
    (snap.items || []).forEach(function (it) {
        var s = C().soulOf(it);
        if (s && s.length) t.soul[it.slot] = s.map(function (x) { return x.name; });
    });
    return t;
}

/** Targets from the strongest players of a class: their soul binding picks
 *  on each piece the character wears and their median skill levels. */
function targetsOfTop(snap) {
    var t = emptyTargets();
    var cls = (snap.profile && snap.profile.className) || "";
    if (!C().topOf(cls)) return null;
    soulPieces(snap, null).out.forEach(function (x) {
        var p = C().topPicks(cls, x.slot, x.pool, x.it.arcana ? x.it.category : null);
        if (p.length) t.soul[x.slot] = p;
    });
    var levels = C().topSkillLevels(cls);
    C().skillSources(snap).forEach(function (s) {
        var l = levels[s.name];
        if (l && l.median >= 10) t.skills[s.name] = Math.round(l.median);
    });
    return t;
}

// ---- history ------------------------------------------------------------

/** A history entry with the build's progress beside the reading. */
function historyEntry(snap, build, ch, prices) {
    var e = C().historyEntry(snap, gsOf(snap));
    if (build) {
        var pr = progress(snap, build, ch, prices);
        if (pr.total != null) { e.p = Math.round(pr.total * 1000) / 10; e.b = build.id; e.bv = build.version; }
    }
    return e;
}

/** A character's boss fights from the DPS history (fights saved with each
 *  player's damage), with the build's version and progress at the time:
 *  [{ boss, at, dps, p, v }], newest first. */
function fightsOf(list, name, history, buildId) {
    var out = [];
    var hist = (history || []).filter(function (e) { return e && e.at; });
    (list || []).forEach(function (f) {
        if (f.train || !Array.isArray(f.players)) return;
        var me = f.players.find(function (p) { return p[0] === name; });
        if (!me) return;
        var secs = Math.max(1, (f.duration || 0) / 1000);
        // The last reading before the fight.
        var before = null;
        for (var i = hist.length - 1; i >= 0; i--) if (hist[i].at <= f.start && hist[i].b === buildId) { before = hist[i]; break; }
        out.push({ id: f.id, boss: f.boss, at: f.start, dps: Math.round(me[1] / secs), p: before ? before.p : null, v: before ? before.bv : null });
    });
    return out.sort(function (a, b) { return b.at - a.at; });
}
