.pragma library
.import "chartickets.js" as T

// The Characters area's rules (the original Roster / Content Overview plugin
// by Nullception, GPL-3.0, with the Clicktrough changes; the limits from the
// Clicktrough Inventory plugin): every character the game showed, kept once
// (the characters store, `merge`), what refills and recharges while one is
// away, and the game's resets. No page here: CharacterStore.qml keeps the
// store, CharactersPanel.qml draws it. Pure functions, `now` passed in.

var HOUR = 3600000
var DAY = 86400000

// ── Odyle energy ───────────────────────────────────────────────────────────
// Basic energy: +15 every 3 hours, on the hours that meet the 07:00 UTC
// daily reset (01:00, 04:00, 07:00 … UTC), up to the cap. One refill was
// seen at 16:00 UTC; the rest of the rule is from another app, not checked.
var STEP = 15
var EVERY = 3 * HOUR
var OFFSET = 1 * HOUR
// The cap: 840 with a membership, 560 without. Charged energy never refills.
var CAPS = [840, 560]

function tick(t) { return Math.floor((t - OFFSET) / EVERY) }
/// When the next refill comes after `now`.
function nextRefill(now) { return (tick(now) + 1) * EVERY + OFFSET }
/// How many refills came after `from`, up to and with `to`.
function refillsBetween(from, to) { return to > from ? tick(to) - tick(from) : 0 }

/// What energy seen as `seen` ({ basic, charged, at }) is likely to be at
/// `now`: { basic, charged, gained, full }; gained: what refills added since.
function estimate(seen, now, cap) {
    if (!seen) return null
    const grown = Math.min(cap, seen.basic + refillsBetween(seen.at, now) * STEP)
    const basic = Math.max(seen.basic, grown)
    return { basic: basic, charged: seen.charged, gained: basic - seen.basic, full: basic >= cap }
}

/// When basic energy reaches the cap: null when it already has.
function fullAt(seen, cap) {
    if (!seen || seen.basic >= cap) return null
    const needed = Math.ceil((cap - seen.basic) / STEP)
    return nextRefill(seen.at) + (needed - 1) * EVERY
}

// A membership is the account's, not a character's: once any character has
// been seen over 560, every one fills to 840. The evidence holds a month,
// each sighting over 560 renews it.
var MEMBER_KEEP_MS = 31 * DAY
function memberSince(ch) { return ch.memberAt || (ch.cap === CAPS[0] && ch.energy ? ch.energy.at || 0 : 0) }
function capFor(state, ch, now) {
    // Set by hand (a click on its cap): the player's word.
    if (ch.capSet) return ch.cap
    let latest = 0
    for (const k in state.chars) latest = Math.max(latest, memberSince(state.chars[k]))
    return latest && now - latest <= MEMBER_KEEP_MS ? CAPS[0] : (ch.cap != null ? ch.cap : CAPS[1])
}

// ── The game's resets: 07:00 UTC daily, Wednesday 07:00 UTC weekly ─────────
function nextDaily(now) {
    const d = new Date(now)
    let t = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 7)
    if (t <= now) t += DAY
    return t
}
function nextWeekly(now) {
    let t = nextDaily(now)
    while (new Date(t).getUTCDay() !== 3) t += DAY
    return t
}
/// The recharges between two times: daily or weekly resets passed.
function resetsBetween(every, from, to) {
    let n = 0
    const step = every === "daily" ? DAY : 7 * DAY
    for (let t = every === "daily" ? nextDaily(from) : nextWeekly(from); t <= to && n < 60; t += step) n++
    return n
}

// ── What is counted ────────────────────────────────────────────────────────
// id: its entry in the game's entry counts (2026-10-24: Nightmare 1+1 and
// Ascension 3+1 as the game showed; Invasion 7 to 6 as a key was used).
// Daily Duty (id 0) is no entry of the game's: the meter reads the Daily
// Duty board, [completed, taken] today; only completed counts ("used").
// From the game's tooltips: Nightmare +2 a day (cap 14), Shugo +3 a day
// (cap 21), Ascension Trial +3 a week (cap 3), Daily Dungeon 14 a week.
// Not from the game, so less sure: Invasion cap 7 at +1 a day, Daily Duty 5
// a day shared by the server's characters.
var CONTENT = [
    { name: "Nightmare", id: 4, scope: "char", cap: 14, add: 2, every: "daily" },
    { name: "Shugo Festival", id: 1, scope: "server", cap: 21, add: 3, every: "daily" },
    { name: "Invasion", id: 8, scope: "server", cap: 7, add: 1, every: "daily" },
    { name: "Daily Duty", id: 0, scope: "server", ofChars: true, cap: 5, add: 5, every: "daily", used: true },
    { name: "Ascension Trial", id: 80000001, scope: "char", cap: 3, add: 3, every: "weekly" },
    { name: "Abyss Corridors", id: "abyss:corridors", scope: "char", cap: 3, add: 3, every: "weekly", used: true, siege: true },
    { name: "Daily Dungeon", id: 101, scope: "server", cap: 14, add: 14, every: "weekly" }
]
function content(id) { for (const c of CONTENT) if (String(c.id) === String(id)) return c; return null }

// The week's limits from the shop and the crafting window: id "shop:<item>"
// or "craft:<recipe>". The shop's Odyle Energy, 4 a character and 16 a
// server (BMShopGoods 1209 and 1210), replaced 20 a character (100134) and
// Rift Stones (100135) on 2026-10-29. Each side crafts its own recipe:
// 3207000N Asmodian, 3107000N Elyos; kept under the Asmodian id either way.
var OTHER = [
    { name: "Kinah gained today", id: "kinah:today", scope: "char", cap: 1000000, add: 0, every: "daily", used: true },
    { name: "Abyss Points this week", id: "abyss:week", scope: "char", cap: 2000000, add: 0, every: "weekly", used: true, capFromGame: true },
    { name: "Odyle Energy crafts", id: "craft:32070002", elyos: "31070002", scope: "char", cap: 4, add: 4, every: "weekly", used: true },
    { name: "Odyle Energy crafts (server)", id: "craft:32070001", elyos: "31070001", scope: "server", cap: 16, add: 16, every: "weekly", used: true },
    { name: "Buy Odyle Energy", id: "shop:1209", scope: "char", cap: 4, add: 4, every: "weekly", used: true },
    { name: "Buy Odyle Energy (server)", id: "shop:1210", scope: "server", cap: 16, add: 16, every: "weekly", used: true }
]
// Abyss passages: 1000000N is the corridor of artifact 100N (Reshanta's
// Root, Sulfur Tree Island, Siel's Wings).
var PASSAGES = [10000001, 10000002, 10000003]
// The entries Content and the energy show; the Limits tab shows the others.
var SHOWN_ELSEWHERE = { "0": true, "1": true, "4": true, "8": true, "101": true, "80000001": true, "60000001": true }

/// A server's side, as its id says: 1xxx Elyos, 2xxx Asmodian.
function sideOf(serverId) { return ({ "1": "elyos", "2": "asmodian" })[String(serverId == null ? "" : serverId)[0]] }

// ── Keeping what the game said ─────────────────────────────────────────────
function num(v) { return typeof v === "number" && isFinite(v) && v > 0 ? v : null }
function sameBut(a, b) {
    const x = Object.assign({}, a, { at: 0 }), y = Object.assign({}, b, { at: 0 })
    return JSON.stringify(x) === JSON.stringify(y)
}
/// What was seen again unchanged keeps when it was first seen.
function kept(prev, next) { return prev && sameBut(prev, next) ? prev : next }
/// The time the game said it, where the meter says (also when unchanged).
function stamped(prev, next, at) {
    return typeof at === "number" && isFinite(at) && at > 0 ? Object.assign({}, next, { at: at }) : kept(prev, next)
}
function serverOf(state, id) {
    const key = String(id == null ? "" : id)
    if (!state.servers[key]) state.servers[key] = {}
    return state.servers[key]
}

/// An empty store.
function empty() { return { chars: {}, servers: {} } }

/// Takes in what the game says of who plays (Engine::character, the meter's
/// `character` event) and returns their key ("name@server"), or null while
/// the server isn't known (a name alone made a second, empty character).
function merge(state, c, now) {
    if (!c || !c.name || !c.serverId) return null
    const key = c.name + "@" + c.serverId
    // 560 until more is seen: only a membership goes over it.
    if (!state.chars[key]) state.chars[key] = { name: c.name, serverId: c.serverId, cap: CAPS[1] }
    const ch = state.chars[key]
    ch.name = c.name
    ch.serverId = c.serverId
    if (c["class"]) ch["class"] = c["class"]
    if (num(c.level)) ch.level = c.level
    if (num(c.combatPower)) ch.cp = c.combatPower
    if (num(c.gearScore)) ch.gs = c.gearScore
    const said = c.seenAt || {}
    const e = c.odyleEnergy
    if (e && isFinite(e.basic) && isFinite(e.charged)) {
        ch.energy = stamped(ch.energy, { basic: e.basic, charged: e.charged, at: now }, said.odyleEnergy)
        // Over 560 can only be with a membership: the game's word over a cap set by hand.
        if (e.basic > CAPS[1]) {
            ch.cap = CAPS[0]
            ch.memberAt = now
            ch.capSet = false
        }
    }
    // Content counts, each kept with the character or its server.
    const counts = c.contentCounts
    const saidCounts = said.contentCounts || {}
    if (counts && typeof counts === "object") {
        for (const x of CONTENT) {
            const v = typeof x.id === "number" ? counts[x.id] : null
            if (!Array.isArray(v)) continue
            const home = x.scope === "server" && !x.ofChars ? serverOf(state, ch.serverId) : ch
            if (!home.counts) home.counts = {}
            home.counts[x.id] = stamped(home.counts[x.id], { v: [Number(v[0]) || 0, Number(v[1]) || 0], at: now }, saidCounts[x.id])
        }
        // The other entries the game keeps (keys, reward counts): for Limits.
        for (const id in counts) {
            const t = T.TICKETS[id]
            const v = counts[id]
            if (!t || t[4] || SHOWN_ELSEWHERE[id] || !Array.isArray(v)) continue
            const home = t[3] ? serverOf(state, ch.serverId) : ch
            if (!home.tickets) home.tickets = {}
            home.tickets[id] = stamped(home.tickets[id], { v: [Number(v[0]) || 0, Number(v[1]) || 0], at: now }, saidCounts[id])
        }
    }
    // Usage times the game keeps (the Abyss's hours …), as last sent.
    const times = c.contentTimes
    if (times && typeof times === "object") {
        for (const id in times) {
            const t = T.TICKETS[id]
            if (!t || !t[4]) continue
            const v = Array.isArray(times[id]) ? times[id] : [times[id], 0]
            if (!ch.times) ch.times = {}
            ch.times[id] = { v: Number(v[0]) || 0, at: Number(v[1]) || now }
        }
    }
    // The shop's weekly limits and the crafts made, once the shop or the
    // crafting window has opened; Kinah gained today and the week's Abyss
    // Points, with its limit (it grows each week).
    const from = { shop: c.shopLimits, craft: c.crafts, kinah: { today: c.kinahToday }, abyss: { week: c.abyssPoints } }
    const saidAt = { shop: said.shopLimits, craft: said.crafts, kinah: { today: said.kinahToday }, abyss: { week: said.abyssPoints } }
    for (const x of OTHER) {
        const parts = x.id.split(":")
        const kind = parts[0], id = parts[1]
        const src = from[kind] || {}
        // An Elyos character's own recipe first: the game lists both sides'.
        const own = x.elyos && sideOf(ch.serverId) === "elyos" ? src[x.elyos] : undefined
        let v = own != null ? own : src[id]
        if (v == null && x.elyos) v = src[x.elyos]
        if (v == null) continue
        const home = x.scope === "server" ? serverOf(state, ch.serverId) : ch
        const n = Array.isArray(v) ? v[0] : v
        // A shop limit past its reset comes as [0, null]: the game's weekly one counts.
        const second = Array.isArray(v) && isFinite(v[1]) && v[1] !== null ? v[1] : undefined
        const seen = { v: [Number(n) || 0, 0], at: now }
        if (x.capFromGame) seen.cap = second
        else if (second !== undefined) seen.reset = second
        if (!home.counts) home.counts = {}
        home.counts[x.id] = stamped(home.counts[x.id], seen, (saidAt[kind] || {})[id])
    }
    // Abyss Corridors: one still to run has its usage time left, a used one
    // comes as a plain 0. Kept only when all three are known.
    if (counts && typeof counts === "object") {
        const t = c.contentTimes || {}
        const time = (id) => Number(Array.isArray(t[id]) ? t[id][0] : t[id])
        const states = PASSAGES.map((id) => (time(id) > 0 ? "left" : Array.isArray(counts[id]) ? "used" : null))
        if (states.indexOf(null) < 0) ch.passages = states
        const server = state.servers[String(ch.serverId)]
        const until = server && server.siege ? server.siege.next : undefined
        const left = ch.passagesLeft
        if (states.indexOf("left") >= 0 && (!left || left.until !== until || now - left.at > 300000)) ch.passagesLeft = { at: now, until: until }
    }
    // The Abyss artifacts' holders, as the game told this player.
    if (c.abyss) keepSiege(state, ch.serverId, c.abyss, now)
    corridors(state, ch, now)
    return key
}

/// Who holds each corridor's artifact and when the holding resets, kept
/// per server; true when it changed.
function keepSiege(state, serverId, d, now) {
    if (!serverId || !d || !Array.isArray(d.artifacts)) return false
    const holders = {}
    for (const a of d.artifacts) if (a && a.id) holders[a.id] = a.owner
    let next
    for (const w of d.wars || []) if (w && w.event === 1001 && Number(w.until) > 0) next = Number(w.until) * 1000
    const server = serverOf(state, serverId)
    const siege = { holders: holders, next: next, at: (Number(d.observedAt) || 0) * 1000 || now }
    if (server.siege && sameBut(server.siege, siege)) return false
    server.siege = siege
    for (const k in state.chars) if (state.chars[k].serverId === serverId) corridors(state, state.chars[k], now)
    return true
}

/// The corridors a character has done since the last siege: a side can run
/// only the ones it holds. Without the siege known, all three count and the
/// weekly reset stands in for it (an estimate).
function corridors(state, ch, now) {
    const states = ch.passages
    if (!states) return
    const server = state.servers[String(ch.serverId)]
    const siege = server ? server.siege : null
    const side = sideOf(ch.serverId)
    const holders = siege ? siege.holders || {} : {}
    const ours = PASSAGES.map((_, k) => {
        const h = holders[1001 + k]
        return !side || !h || h === side || String(h).indexOf("unknown") === 0
    })
    const cap = ours.filter(Boolean).length
    const done = states.filter((st, k) => ours[k] && st === "used").length
    if (!ch.counts) ch.counts = {}
    const prev = ch.counts["abyss:corridors"]
    const inPeriod = (x) => {
        if (!x) return false
        const end = x.until != null ? x.until : x.reset
        return end ? now < end : !resetsBetween("weekly", x.at, now)
    }
    const sure = cap === 0 || done < cap || inPeriod(ch.passagesLeft) || (prev && !prev.guess && inPeriod(prev))
    const next = siege ? siege.next : undefined
    ch.counts["abyss:corridors"] = sure
        ? kept(prev, { v: [done, 0], at: now, reset: next, cap: cap })
        : kept(prev, { v: [0, 0], at: now, reset: next, cap: cap, guess: true })
}

// ── What it likely is now ──────────────────────────────────────────────────
/// A count as it likely is now: { left, extra, gained, full, reset }, from
/// what the game last said and the recharges since; null when not known.
function countNow(c, seen, now) {
    if (!seen) return null
    // Past a siege the corridors may or may not have reset: not known.
    if (c.siege && seen.reset && now >= seen.reset) return null
    if (seen.guess) return { left: 0, extra: 0, gained: 0, full: false, reset: true }
    const passed = seen.reset ? (now >= seen.reset ? 1 : 0) : resetsBetween(c.every, seen.at, now)
    const was = seen.v[0], extra = seen.v[1]
    // Taken today: none again after a reset.
    if (c.used) {
        const left = passed ? 0 : was
        return { left: left, extra: extra, gained: 0, full: left >= capOf(c, seen), reset: passed > 0 }
    }
    const grown = Math.min(c.cap, was + passed * c.add)
    const left = Math.max(was, grown)
    return { left: left, extra: extra, gained: left - was, full: left >= c.cap, reset: false }
}
/// The cap a count goes to: the game's own where it sends one (Abyss
/// Points, the corridors your side holds).
function capOf(c, seen) {
    return seen && typeof seen.cap === "number" && (seen.cap > 0 || c.siege) ? seen.cap : c.cap
}

/// A server's total of a count kept per character (Daily Duty): each one's
/// today (none after a reset) added up; undefined before any.
function sumOfChars(c, chars, now) {
    const today = []
    for (const ch of chars) {
        const seen = ch.counts ? ch.counts[c.id] : null
        if (seen && !countNow(c, seen, now).reset) today.push(seen)
    }
    if (!today.length) return undefined
    return {
        v: [today.reduce((n, s) => n + s.v[0], 0), today.reduce((n, s) => n + s.v[1], 0)],
        at: Math.max.apply(null, today.map((s) => s.at))
    }
}

/// A kept ticket (key, reward count) as it likely is now: { left, max,
/// stale } where stale means a reset has passed since the game said it.
function ticketNow(id, seen, now) {
    const t = T.TICKETS[id]
    if (!t || !seen) return null
    const every = t[5] === "d" ? "daily" : t[5] === "w" ? "weekly" : null
    return { name: t[0], left: seen.v[0], extra: seen.v[1], max: t[1], stale: every ? resetsBetween(every, seen.at, now) > 0 : false, at: seen.at, server: t[3] }
}
function ticketName(id) { const t = T.TICKETS[id]; return t ? t[0] : "" }

// ── Words ──────────────────────────────────────────────────────────────────
function span(ms) {
    const m = Math.max(0, Math.round(ms / 60000))
    if (m >= 1440) return Math.floor(m / 1440) + "d " + Math.floor((m % 1440) / 60) + "h"
    if (m >= 60) return Math.floor(m / 60) + "h " + (m % 60) + "m"
    return m + "m"
}
function ago(at, now) {
    const m = Math.round((now - at) / 60000)
    if (m < 2) return "just now"
    if (m < 60) return m + "m ago"
    if (m < 48 * 60) return Math.round(m / 60) + "h ago"
    return Math.round(m / 1440) + "d ago"
}
function grouped(v) {
    const n = Math.round(v)
    let t = String(Math.abs(n)), o = ""
    while (t.length > 3) { o = "," + t.slice(-3) + o; t = t.slice(0, -3) }
    return (n < 0 ? "-" : "") + t + o
}

// The classes' colours (as the Roster showed them).
var CLASS_COLOURS = {
    Gladiator: "#e0a04a", Templar: "#7fa7d9", Assassin: "#c46ad1", Ranger: "#7cc46a", Sorcerer: "#e06a6a",
    Spiritmaster: "#6ad1c4", Cleric: "#f0d36a", Chanter: "#d18f6a"
}
function classColour(name) { return CLASS_COLOURS[name] || "#8a8794" }
