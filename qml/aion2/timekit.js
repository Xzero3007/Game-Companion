.pragma library
.import "schedule.js" as S

// The Schedule's rules (the Event Timers plugin, reworked; design boards
// T1–T3): server time per region, the next times of the fixed events
// (schedule.js), the field bosses as the game told them when a map was
// opened (TimerStore), and when the next alert is due. No Qt here: tested
// by tools/timekit-test.js.

var MIN = 60000
var HOUR = 60 * MIN
var DAY = 24 * HOUR

// ── Server time ─────────────────────────────────────────────────────────────
// Each Global region's servers keep their own clock (the second digit of the
// server's number): 1 NA East (New York), 2 NA West (Los Angeles), 3 Europe
// (Berlin), 4 South America (São Paulo), 5 Asia (Seoul). Their daylight
// saving rules, as the law has them now (Qt's JavaScript has no time zones).
var REGIONS = {
    1: { name: "NA East", slug: "na-east" },
    2: { name: "NA West", slug: "na-west" },
    3: { name: "Europe", slug: "eu" },
    4: { name: "South America", slug: "sa" },
    5: { name: "Asia", slug: "asia" }
}

function regionOf(serverId) {
    const s = String(serverId == null ? "" : serverId)
    const r = s.length >= 4 ? Number(s[1]) : 0
    return REGIONS[r] ? r : 0
}
function sideOf(serverId) { return ({ "1": "elyos", "2": "asmodian" })[String(serverId == null ? "" : serverId)[0]] || "" }

/// The n-th Sunday (n = -1: the last) of a month, as a UTC day start.
function sunday(year, month, n) {
    if (n > 0) {
        const first = new Date(Date.UTC(year, month, 1)).getUTCDay()
        return Date.UTC(year, month, 1 + (7 - first) % 7 + 7 * (n - 1))
    }
    const lastDay = new Date(Date.UTC(year, month + 1, 0))
    return lastDay.getTime() - lastDay.getUTCDay() * DAY
}

/// Minutes the region's clock is ahead of UTC at a moment.
function offset(region, at) {
    const y = new Date(at).getUTCFullYear()
    if (region === 1 || region === 2) {
        // US: second Sunday of March 02:00 local to first Sunday of November 02:00 local.
        const std = region === 1 ? -300 : -480
        const from = sunday(y, 2, 2) + 2 * HOUR - std * MIN
        const to = sunday(y, 10, 1) + 2 * HOUR - (std + 60) * MIN
        return at >= from && at < to ? std + 60 : std
    }
    if (region === 3) {
        // EU: last Sunday of March to last Sunday of October, 01:00 UTC.
        const from = sunday(y, 2, -1) + HOUR
        const to = sunday(y, 9, -1) + HOUR
        return at >= from && at < to ? 120 : 60
    }
    if (region === 4) return -180
    if (region === 5) return 540
    return 0
}

/// A wall-clock time in the region (minutes after that day's midnight) as a moment.
function moment(region, y, m, d, minutes) {
    const wall = Date.UTC(y, m, d) + minutes * MIN
    let t = wall - offset(region, wall) * MIN
    t = wall - offset(region, t) * MIN
    return t
}

/// The region's date at a moment: {y, m, d, wd, minutes}.
function wallOf(region, at) {
    const w = new Date(at + offset(region, at) * MIN)
    return { y: w.getUTCFullYear(), m: w.getUTCMonth(), d: w.getUTCDate(), wd: w.getUTCDay(), minutes: w.getUTCHours() * 60 + w.getUTCMinutes() }
}

/// A moment as the region's clock: "18:04", with the weekday when not today.
function clock(region, at, now) {
    const w = wallOf(region, at)
    const pad = (n) => (n < 10 ? "0" : "") + n
    const hm = pad(Math.floor(w.minutes / 60)) + ":" + pad(w.minutes % 60)
    if (now == null) return hm
    const n = wallOf(region, now)
    if (n.y === w.y && n.m === w.m && n.d === w.d) return hm
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][w.wd] + " " + hm
}

// ── The fixed events ────────────────────────────────────────────────────────
/// The next showing of an event that has not ended yet: {start, end} (end =
/// start when the tables give no length), or null within a week.
function nextOf(ev, region, now) {
    const zone = ev.utc ? 0 : region
    const today = wallOf(zone, now)
    let best = null
    for (let k = -1; k <= 8; k++) {
        const day = new Date(Date.UTC(today.y, today.m, today.d + k))
        if (ev.days.indexOf(day.getUTCDay()) < 0) continue
        for (const s of ev.starts) {
            const start = zone ? moment(zone, day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), s) : Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate()) + s * MIN
            const end = start + (ev.minutes || 0) * MIN
            if (end < now || (end === start && start <= now)) continue
            if (!best || start < best.start) best = { start: start, end: end }
        }
    }
    return best
}

/// Odyle energy: +15 every 3 hours on the hours that meet the 07:00 UTC reset.
function nextRefill(now) { return (Math.floor((now - HOUR) / (3 * HOUR)) + 1) * 3 * HOUR + HOUR }

/// The Events tab's rows, soonest first: {id, kind, name, where, start, end,
/// running}. `side` "" shows both sides' events, each with its map.
function events(region, side, now) {
    const out = []
    for (const ev of S.EVENTS) {
        if (ev.side && side && ev.side !== side) continue
        if (!region && !ev.utc) continue
        const next = nextOf(ev, region, now)
        if (!next) continue
        out.push({ id: ev.id, kind: ev.kind, name: ev.name, where: ev.where.join(" · "), start: next.start, end: next.end,
            running: next.start <= now && now < next.end })
    }
    out.push({ id: "energy", kind: "reset", name: "Odyle energy +15", where: "", start: nextRefill(now), end: nextRefill(now), running: false })
    out.sort((a, b) => a.start - b.start)
    return out
}

// ── The field bosses ────────────────────────────────────────────────────────
/// Seen up this long ago and not since: shown as "up?" (someone may have killed it).
var UP_STALE = 2 * HOUR
/// Coming back within this: "soon" (gold).
var SOON = 15 * MIN

function bossInfo(id) { return S.FIELD_BOSSES[String(id)] || null }

/// Takes a map the game told (Aion2.bossMaps) into a server's kept maps.
/// Returns true if anything changed.
function takeMap(kept, map) {
    if (!map || !map.bosses) return false
    const known = map.bosses.filter((b) => bossInfo(b.id))
    if (!known.length) return false
    const key = String(map.map)
    const old = kept[key]
    if (old && old.seen >= map.seen) return false
    kept[key] = { seen: map.seen, bosses: known.map((b) => ({ id: b.id, up: !!b.up, time: b.time || 0 })) }
    return true
}

/// Aion 2 Timers' name of a boss ("asmo07") as its world-map id, as
/// learnt (`links`, from times that matched the game's), else by its number
/// (asmoNN: Altgard's NN-th, elyosNN: Verteron's): {id, sure} or null.
function linkOf(slug, links) {
    if (links && links[slug]) return { id: String(links[slug]), sure: true }
    const m = /^(asmo|elyos|ely|light)(\d\d)$/.exec(slug)
    if (!m) return null
    const id = String((m[1] === "asmo" ? 111000 : 101000) + Number(m[2]))
    return bossInfo(id) ? { id: id, sure: false } : null
}

/// Learns which of Aion 2 Timers' names is which boss: a dead boss whose
/// return the game gave matches one name's next spawn within 2 minutes, and
/// only that one. Returns true if anything new was learnt.
function learn(links, kept, kills) {
    let changed = false
    for (const key in kept) {
        for (const b of kept[key].bosses) {
            if (b.up || !b.time) continue
            const hits = []
            for (const slug in kills) {
                const k = kills[slug]
                if (k && k.st === "dead" && k.ns && Math.abs(k.ns * 1000 - b.time) <= 120000) hits.push(slug)
            }
            if (hits.length === 1 && links[hits[0]] !== b.id) { links[hits[0]] = b.id; changed = true }
        }
    }
    return changed
}

/// The Bosses tab's rows: {id, name, where, side, level, state, time, seen,
/// src, sort} with state "up" (since time), "soon" / "wait" (back at time),
/// "due" (back at time, which has passed: likely up), "unknown"; src "game"
/// or "a2t" (Aion 2 Timers, newer than what the game told). `feed`:
/// {at, kills} or null; `links` as `learn` keeps them.
function bosses(kept, now, feed, links) {
    const readings = {}
    for (const key in kept) {
        const map = kept[key]
        for (const b of map.bosses) readings[String(b.id)] = { up: b.up, time: b.time, seen: map.seen, src: "game" }
    }
    const kills = feed && feed.kills ? feed.kills : {}
    for (const slug in kills) {
        const k = kills[slug]
        const l = linkOf(slug, links)
        if (!k || !l) continue
        const seen = (k.u || 0) * 1000
        const old = readings[l.id]
        if (old && old.seen >= seen) continue
        if (k.st === "up") readings[l.id] = { up: true, time: (k.ra || k.t || 0) * 1000, seen: seen, src: "a2t", sure: l.sure }
        else if (k.st === "dead" && k.ns) readings[l.id] = { up: false, time: k.ns * 1000, seen: seen, src: "a2t", sure: l.sure }
    }
    const out = []
    for (const id in readings) {
        const r = readings[id]
        const info = bossInfo(id)
        if (!info) continue
        let state = "unknown"
        if (r.up) state = now - r.seen > UP_STALE ? "upOld" : "up"
        else if (r.time > now) state = r.time - now <= SOON ? "soon" : "wait"
        else if (r.time > 0) state = "due"
        // Up first, then due, then by when they come back.
        const sort = state === "up" ? 0 : state === "upOld" || state === "due" ? 1 : state === "unknown" ? 3 : 2
        out.push({ id: id, name: info.name, where: info.where, side: info.side, level: info.level,
            state: state, time: r.time, seen: r.seen, src: r.src, guessed: r.src === "a2t" && !r.sure, sort: sort })
    }
    out.sort((a, b) => a.sort - b.sort || (a.sort === 2 ? a.time - b.time : b.time - a.time) || a.name.localeCompare(b.name))
    return out
}

// ── Alerts ──────────────────────────────────────────────────────────────────
/// The next alert after `after`: {at, id, name, where, start} or null.
/// `on`: {id: true} for every event or boss with its bell on; `lead`
/// minutes before; `atStart` also as it starts. Bosses alert before they
/// come back (only a time the game gave).
function nextAlert(eventRows, bossRows, on, lead, atStart, after) {
    let best = null
    const consider = (id, name, where, start) => {
        if (!on[id] || !start) return
        const times = [start - lead * MIN]
        if (atStart && lead > 0) times.push(start)
        for (const at of times) if (at > after && (!best || at < best.at)) best = { at: at, id: id, name: name, where: where, start: start }
    }
    for (const r of eventRows) if (!r.running) consider(r.id, r.name, r.where, r.start)
    for (const r of bossRows) if (r.state === "soon" || r.state === "wait") consider(r.id, r.name, r.where, r.time)
    return best
}

/// "12m", "1h 48m", "2d 3h" (as the Characters panel writes spans).
function span(ms) {
    const m = Math.max(0, Math.ceil(ms / 60000))
    if (m >= 1440) return Math.floor(m / 1440) + "d " + Math.floor((m % 1440) / 60) + "h"
    if (m >= 60) return Math.floor(m / 60) + "h " + (m % 60) + "m"
    return m + "m"
}
function ago(at, now) {
    const m = Math.round((now - at) / 60000)
    if (m < 2) return "just now"
    if (m < 60) return m + " min ago"
    if (m < 48 * 60) return Math.round(m / 60) + " h ago"
    return Math.round(m / 1440) + " days ago"
}
