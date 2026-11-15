.pragma library

// The PoE 2 session tracker's rules (MN, 2026-11-15): one session is a
// stretch of play, cut by a new day or by a pause (AFK or the game closed)
// longer than the chosen break (30 min or 1 h). Fed by the game's log
// (src/poe2_log.rs: area, named, level, death, afk) and by the game
// starting and ending. No Qt here: tested by tools/poe2-session-test.js.

var MIN = 60000
var HOUR = 60 * MIN
var KINDS = ["map", "hideout", "town", "campaign", "other"]
var KEEP_MAPS = 300
var KEEP_DEATHS = 50

// What an area is, by the game's id ("MapCrypt", "HideoutFelled",
// "G1_town", "G2_3") or, without one, by its name.
function kindOf(id, name) {
    id = id || ""
    if (/hideout/i.test(id) || (!id && /hideout/i.test(name || ""))) return "hideout"
    if (/town/i.test(id)) return "town"
    if (/^Map/.test(id)) return "map"
    if (/^(C_)?G\d+_/.test(id) || /^P\d+_/.test(id)) return "campaign"
    return "other"
}

// The campaign's act of an area id ("Act 2", "Act 1 (Cruel)", "Interlude 1"), or "".
function actOf(id) {
    var m = /^(C_)?G(\d+)_/.exec(id || "")
    if (m) return "Act " + m[2] + (m[1] ? " (Cruel)" : "")
    m = /^P(\d+)_/.exec(id || "")
    return m ? "Interlude " + m[1] : ""
}

// A readable name from an id when the log gave none ("MapCrypt" → "Crypt").
function nameFromId(id) {
    var s = String(id || "").replace(/^Map/, "").replace(/_/g, " ")
    return s.replace(/([a-z])([A-Z])/g, "$1 $2").trim() || "Unknown area"
}

function newSession(now) {
    return {
        v: 1, start: now, last: null, end: null,
        time: { map: 0, hideout: 0, town: 0, campaign: 0, other: 0 },
        acts: {},
        maps: [],
        deaths: 0, deathsAt: [],
        char: null,
        levels: 0,
        area: null,
        idleSince: now,
        loot: { cur: {}, names: {}, items: [] }
    }
}

function copy(s) { return JSON.parse(JSON.stringify(s)) }

function lootOf(s) {
    if (!s.loot) s.loot = { cur: {}, names: {}, items: [] }
    return s.loot
}

function hasLoot(s) {
    var l = s && s.loot
    if (!l) return false
    for (var k in l.cur) if (l.cur[k]) return true
    return l.items.length > 0
}

function isEmpty(s) { return !s || (s.last == null && !s.maps.length && !s.deaths && !s.levels && !hasLoot(s)) }

// ── Loot (part 2): what you picked up, told by hand ─────────────────────────
// Client.txt names no drops and PoE 2 has no stash API, so currency is
// counted with + and − (or a copied stack) and other items come from the
// price check ("+ Session"), with their price in divines at that moment.

// Adds (or takes away) currency by poe.ninja's id ("divine", "exalted").
function addCurrency(s, id, name, n) {
    var l = lootOf(s)
    l.cur[id] = Math.max(0, (l.cur[id] || 0) + n)
    if (name) l.names[id] = name
    if (!l.cur[id]) delete l.cur[id]
    return s
}

// Adds an item with its worth in divines (null when unknown).
function addItem(s, item) {
    var l = lootOf(s)
    l.items.push({ t: item.t, name: String(item.name || "Item"), div: item.div == null ? null : Number(item.div), how: item.how || "" })
    if (l.items.length > 200) l.items.shift()
    return s
}

function removeItem(s, index) {
    var l = lootOf(s)
    if (index >= 0 && index < l.items.length) l.items.splice(index, 1)
    return s
}

// The median of some prices in divines, by poe.ninja's rates
// ({ byId: { id: div } }); null when none can be turned into divines.
function medianDiv(prices, rates) {
    var list = []
    for (var i = 0; i < prices.length; i++) {
        var p = prices[i]
        var r = rates && rates.byId ? rates.byId[p.currency] : null
        if (p.currency === "divine") list.push(p.amount)
        else if (r && r.div > 0) list.push(p.amount * r.div)
    }
    if (!list.length) return null
    list.sort(function (a, b) { return a - b })
    var m = Math.floor(list.length / 2)
    return list.length % 2 ? list[m] : (list[m - 1] + list[m]) / 2
}

// What the loot is worth now: currency by today's rates, items as priced.
function worth(s, rates) {
    var l = (s && s.loot) || { cur: {}, items: [] }
    var div = 0, unknown = 0, any = false
    for (var id in l.cur) {
        if (!l.cur[id]) continue
        any = true
        var r = id === "divine" ? { div: 1 } : (rates && rates.byId ? rates.byId[id] : null)
        if (r && r.div > 0) div += l.cur[id] * r.div
        else unknown++
    }
    for (var i = 0; i < l.items.length; i++) {
        any = true
        if (l.items[i].div != null) div += l.items[i].div
        else unknown++
    }
    return { any: any, div: div, exalted: rates && rates.exalted ? div * rates.exalted : 0, unknown: unknown, priced: !!(rates && rates.exalted) }
}

function dayKey(t) { var d = new Date(t); return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate() }

function midnightAfter(t) { var d = new Date(t); d.setHours(24, 0, 0, 0); return d.getTime() }

// Counts the time in the current area up to `t` (none while idle).
function advance(s, t) {
    if (!s.area) return
    if (s.idleSince == null && t > s.area.since) {
        var dt = t - s.area.since
        s.time[s.area.kind] = (s.time[s.area.kind] || 0) + dt
        if (s.area.act) s.acts[s.area.act] = (s.acts[s.area.act] || 0) + dt
        if (s.area.map != null && s.maps[s.area.map]) s.maps[s.area.map].time += dt
    }
    if (t > s.area.since) s.area.since = t
}

function touch(s, t) { if (s.last == null || t > s.last) s.last = t }

// Whether `ev` (at ev.t) belongs to a new session: the break was longer
// than `breakMs` or the day changed. Gives the moment the old one ends
// (its last moment of play, or midnight), or null.
function cutAt(s, t, breakMs) {
    if (isEmpty(s)) return null
    if (s.idleSince != null && t - s.idleSince > breakMs) return s.idleSince
    if (dayKey(t) !== dayKey(s.start)) return Math.min(midnightAfter(s.start), t)
    return null
}

// Ends a session at `t` (for the list of earlier ones).
function finish(s, t) {
    var out = copy(s)
    advance(out, Math.max(t, out.area ? out.area.since : t))
    out.end = Math.max(out.last || out.start, t)
    delete out.area
    delete out.idleSince
    return out
}

// The new session after a cut at `at`: you are still where you were (a
// day change while playing goes on in the same map).
function carryOn(old, at) {
    var s = newSession(at)
    if (old.area && old.idleSince == null) {
        s.idleSince = null
        s.area = { kind: old.area.kind, name: old.area.name, id: old.area.id, level: old.area.level, seed: old.area.seed, act: old.area.act, since: at, map: null }
        if (s.area.kind === "map") {
            s.maps.push({ name: s.area.name, id: s.area.id, level: s.area.level, seed: s.area.seed, start: at, time: 0, deaths: 0 })
            s.area.map = 0
        }
    }
    if (old.char) s.char = { name: old.char.name, cls: old.char.cls, from: old.char.to, to: old.char.to }
    return s
}

// One event of the log into the session (changes and returns it).
function apply(s, ev) {
    var t = Number(ev.t) || 0
    if (ev.k === "area") {
        advance(s, t)
        var name = ev.name || (ev.id ? nameFromId(ev.id) : "")
        var kind = kindOf(ev.id, name)
        var area = { kind: kind, name: name, id: ev.id || "", level: Number(ev.level) || 0, seed: ev.seed || "", act: kind === "campaign" ? actOf(ev.id) : "", since: t, map: null }
        if (kind === "map") {
            // Back through a portal into the same map: the same entry.
            var found = -1
            for (var i = s.maps.length - 1; i >= 0; i--) {
                var m = s.maps[i]
                if ((area.seed && m.seed === area.seed && m.id === area.id) || (!area.seed && !m.seed && m.name === area.name && i === s.maps.length - 1)) { found = i; break }
            }
            if (found < 0) {
                s.maps.push({ name: name, id: area.id, level: area.level, seed: area.seed, start: t, time: 0, deaths: 0 })
                if (s.maps.length > KEEP_MAPS) s.maps.splice(0, s.maps.length - KEEP_MAPS)
                found = s.maps.length - 1
            }
            area.map = found
        }
        s.area = area
        s.idleSince = null
        touch(s, t)
    } else if (ev.k === "named") {
        if (s.area && !s.area.nameGiven) {
            s.area.name = ev.name
            s.area.nameGiven = true
            if (!s.area.id) s.area.kind = kindOf("", ev.name)
            if (s.area.map != null && s.maps[s.area.map]) s.maps[s.area.map].name = ev.name
        }
    } else if (ev.k === "level") {
        advance(s, t)
        var lv = Number(ev.level) || 0
        if (!s.char || s.char.name !== ev.char) s.char = { name: ev.char, cls: ev["class"], from: lv - 1, to: lv }
        else { s.char.to = Math.max(s.char.to, lv); s.char.cls = ev["class"] }
        s.levels++
        touch(s, t)
    } else if (ev.k === "death") {
        advance(s, t)
        s.deaths++
        s.deathsAt.push({ t: t, where: s.area ? s.area.name : "" })
        if (s.deathsAt.length > KEEP_DEATHS) s.deathsAt.shift()
        if (s.area && s.area.map != null && s.maps[s.area.map]) s.maps[s.area.map].deaths++
        touch(s, t)
    } else if (ev.k === "afk") {
        advance(s, t)
        if (ev.on) { if (s.idleSince == null) s.idleSince = t }
        else if (s.idleSince != null && s.area) { s.idleSince = null; s.area.since = t }
        touch(s, t)
    }
    return s
}

// The game ended (or the app found the session it left): no more time.
function pause(s, t) {
    advance(s, t)
    if (s.idleSince == null) s.idleSince = t
    s.area = null
    return s
}

// The numbers shown, with the area you are in counted up to `now`.
function view(s, now, rates) {
    var v = copy(s)
    if (v.area && v.idleSince == null) advance(v, now)
    var played = 0
    for (var i = 0; i < KINDS.length; i++) played += v.time[KINDS[i]] || 0
    var mapTime = 0, timed = 0
    for (var j = 0; j < v.maps.length; j++) if (v.maps[j].time > 0) { mapTime += v.maps[j].time; timed++ }
    var current = v.area && v.area.map != null ? v.maps[v.area.map] : null
    return {
        played: played,
        time: v.time,
        acts: v.acts,
        maps: v.maps,
        mapCount: v.maps.length,
        mapsPerHour: played >= 5 * MIN ? v.maps.length / (played / HOUR) : 0,
        avgMap: timed ? mapTime / timed : 0,
        deaths: v.deaths,
        deathsAt: v.deathsAt,
        char: v.char,
        levels: v.levels,
        levelsPerHour: played >= 5 * MIN ? v.levels / (played / HOUR) : 0,
        area: v.area,
        current: current,
        idle: v.idleSince != null,
        start: v.start,
        end: v.end || v.last || v.start,
        loot: v.loot || { cur: {}, names: {}, items: [] },
        worth: worth(v, rates),
        worthPerHour: played >= 5 * MIN ? worth(v, rates).div / (played / HOUR) : 0
    }
}

// "2h 05m", "12m", "45s".
function span(ms) {
    ms = Math.max(0, ms || 0)
    var m = Math.floor(ms / MIN)
    if (m >= 60) return Math.floor(m / 60) + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
    if (m >= 1) return m + "m"
    return Math.floor(ms / 1000) + "s"
}

// "6:12" for a map's time.
function clock(ms) {
    var s = Math.floor(Math.max(0, ms || 0) / 1000)
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (r < 10 ? "0" : "") + r
}
