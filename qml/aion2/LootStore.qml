import QtQuick
import GameCompanion
import "lootkit.js" as LK
import "marketkit.js" as MK
import "chartickets.js" as T

// What the LOOT panel shows, learnt while the app runs (shared inside the
// AION 2 package, like CharacterStore): the Clicktrough Inventory, Closet
// and Shugo Cards plugins' state, their logic in lootkit.js. Items: each
// character's inventory and storages (the game sends them when you enter
// the world). Drops: the session's drops, the farm days (daily reset to
// reset, by where they came from) and the dungeon runs against the game's
// drop rates. Closet: the closet from the login, the Black Cloud Merchant's
// offers per character, whether you are at the shop (the shop window).
// Cards: the Shugo Festival's and the Dimensional Invasion's card rounds.
// Kept in ~/.local/share/game-companion/aion2/loot/ (Aion2.keepLoot); only
// reads the game (the items event and the decoded frames).
QtObject {
    id: store

    /// Raised on every change the panel shows (it builds again).
    property int revision: 0
    readonly property bool demo: nativeWindow.demo.split(",").indexOf("loot") >= 0
    /// The prices (Main's PriceBook).
    property var book: null

    readonly property var ix: LK.L.index(LK.CD)

    // ---------- settings (one file for all four tabs) ----------
    property var settings: ({
        tab: "items", list: "inv", sort: "value", sellableOnly: false, search: {}, fee: 10, view: null,
        drops: "session", source: "all", breakMin: 180, statSource: "open", statMetric: "kinah", farmWho: null,
        closetTab: "merchant", shopWindow: true, marketWindow: false, farmWindow: true, farmMode: null, farmRows: null, popupMinutes: 1, windowView: "shop", lucky: false, kind: "all", grade: "all", order: "price",
        cards: "round", cardKind: "all", kinds: {}, cardChar: "all"
    })
    function set(key, value) {
        const s = Object.assign({}, settings)
        s[key] = value
        settings = s
        put("settings", settings)
        changed()
    }

    // ---------- storage: a key's doc, written a moment after it changed ----------
    property var dirty: ({})
    function put(key, value) {
        if (demo) return
        dirty[key] = value
        if (!saveTimer.running) saveTimer.start()
    }
    function get(key) {
        if (demo) return null
        try { return JSON.parse(Aion2.loadLoot(key) || "null") } catch (e) { return null }
    }
    function flush() {
        const d = dirty
        dirty = ({})
        for (const k in d) Aion2.keepLoot(k, JSON.stringify(d[k]))
    }
    property Timer saveTimer: Timer { interval: 1500; onTriggered: store.flush() }
    function changed() { if (!buildTimer.running) buildTimer.start() }
    // Many events in a moment build once.
    property Timer buildTimer: Timer { interval: 120; onTriggered: store.revision++ }

    // ---------- who plays ----------
    property var character: null
    function currentKey() { return character && character.name ? LK.C.charKey(character.serverId, character.name) : null }
    property var chars: [] // [{ key, name, serverId, at }]
    function viewKey() { return settings.view || currentKey() || (chars.length ? chars[0].key : null) }
    function nameOf(key) {
        for (const c of chars) if (c.key === key) return c.name
        return character && currentKey() === key ? character.name : key
    }
    property var zone: null

    // ---------- Items ----------
    property var stocks: ({}) // key -> { name, serverId, inv, char, exactAt, at }
    property var accounts: ({}) // serverId -> { acc, exactAt, at }
    function stock(key) {
        if (!key) return null
        if (!(key in stocks)) stocks[key] = get("s-" + key)
        const st = stocks[key]
        if (st && !(String(st.serverId) in accounts)) accounts[String(st.serverId)] = get("acc-" + st.serverId)
        return st
    }
    function account(serverId) {
        if (serverId == null) return null
        if (!(String(serverId) in accounts)) accounts[String(serverId)] = get("acc-" + serverId)
        return accounts[String(serverId)]
    }
    function counts(list) {
        const st = stock(viewKey())
        if (list === "inv") return st && st.inv || {}
        if (list === "char") return st && st.char || {}
        if (list === "acc") { const a = account(st ? st.serverId : character ? character.serverId : null); return a && a.acc || {} }
        return {}
    }
    function noteItems(it) {
        const owner = it.owner || (it.snapshotAt ? null : character && character.name)
        if (!owner || !character || character.serverId == null) return
        const serverId = character.serverId
        const key = LK.C.charKey(serverId, owner)
        const kept = stock(key)
        const acc = account(serverId)
        const next = LK.C.apply({ inv: kept && kept.inv, "char": kept && kept["char"], acc: acc && acc.acc, exactAt: kept && kept.exactAt }, it)
        stocks[key] = { name: owner, serverId: serverId, inv: next.inv, "char": next["char"], exactAt: next.exactAt, at: Date.now() }
        accounts[String(serverId)] = { acc: next.acc, exactAt: it.snapshotAt || (acc && acc.exactAt) || null, at: Date.now() }
        put("s-" + key, stocks[key])
        put("acc-" + serverId, accounts[String(serverId)])
        const c = chars.find((x) => x.key === key)
        if (c) c.at = Date.now()
        else { chars = chars.concat([{ key: key, name: owner, serverId: serverId, at: Date.now() }]); put("chars", chars) }
    }

    // ---------- Drops: the session ----------
    property var session: LK.C.newSession(Date.now())
    property var history: [] // earlier sessions, newest first
    property var pastView: null
    readonly property int keepSessions: 40
    function dropSession() {
        if (pastView != null) for (const h of history) if (h.start === pastView) return h
        return session
    }
    function rollAt(at) {
        if (!LK.C.isBreak(session, at, (Number(settings.breakMin) || 0) * 60000)) return
        if (LK.C.isEmpty(session)) { session = LK.C.newSession(at); return }
        endSession(at)
    }
    function endSession(at) {
        if (!LK.C.isEmpty(session)) {
            history = [LK.C.summary(session)].concat(history.filter((h) => h.start !== session.start)).slice(0, keepSessions)
            put("sessions", history)
        }
        session = LK.C.newSession(at)
        pastView = null
        put("session", session)
        changed()
    }
    function priceOf(item, n) {
        if (!book || !book.prices.size) return null
        const w = LK.C.worth(item, n, book.prices, settings.fee, book.hist)
        if (!w.sellable) return 0
        return w.total == null ? null : w.total
    }
    function placeLabel() { return LK.F.zoneName(zone) }

    // ---------- Drops: farm days ----------
    property var farmKey: null
    property var farmDay: null
    property var farmLists: ({}) // key -> [summaries], oldest first
    property var keyCounts: ({})
    readonly property int farmDays: 400
    function farmList(key) {
        if (!key) return []
        if (!(key in farmLists)) {
            const l = get("f-" + key)
            farmLists[key] = Array.isArray(l) ? l.filter((x) => x && isFinite(x.day)) : []
        }
        return farmLists[key]
    }
    function noteSummary() {
        if (!farmKey || !farmDay || LK.F.isEmpty(farmDay)) return
        const list = farmList(farmKey).filter((x) => x.day !== farmDay.day)
        list.push(LK.F.summary(farmDay))
        list.sort((a, b) => a.day - b.day)
        farmLists[farmKey] = list.slice(-farmDays)
    }
    function saveFarm() {
        if (!farmKey || !farmDay) return
        noteSummary()
        put("f-" + farmKey + "-" + LK.F.dayName(farmDay.day), farmDay)
        put("f-" + farmKey, farmLists[farmKey] || [])
        farmCheck()
        changed()
    }
    /// The day an event at `at` counts in, for the one playing (loaded or new).
    function farmFor(at) {
        const key = currentKey()
        if (!key || !isFinite(at)) return null
        const day = LK.F.dayOf(at)
        if (farmKey === key && farmDay && farmDay.day === day) return farmDay
        if (farmKey === key && farmDay && day < farmDay.day) return null
        if (farmKey && farmDay) saveFarm()
        farmList(key)
        farmKey = key
        farmDay = LK.F.normalize(get("f-" + key + "-" + LK.F.dayName(day))) || LK.F.newDay(at)
        return farmDay
    }
    function farmItems(it) {
        const ats = (it.changes || []).map((c) => c[1]).filter((x) => isFinite(x))
        if (!ats.length) return
        if (!farmFor(Math.max.apply(null, ats))) return
        farmDay = LK.F.addItems(farmDay, it, zone, priceOf, placeLabel())
        saveFarm()
    }
    function farmCharacter(c) {
        const seen = c.seenAt || {}
        const kinah = Number(c.kinahToday)
        const kinahAt = Number(seen.kinahToday) || Date.now()
        const used = []
        const cc = c.contentCounts || {}
        for (const id of Object.keys(LK.F.KEYS)) {
            const v = cc[id]
            if (!Array.isArray(v) || !isFinite(Number(v[0]))) continue
            const left = Number(v[0]) + (Number(v[1]) || 0)
            const before = keyCounts[id]
            keyCounts[id] = left
            if (before != null && left < before) used.push([id, Number((seen.contentCounts || {})[id]) || Date.now()])
        }
        if (!isFinite(kinah) && !used.length) return
        if (c.kinahToday != null && isFinite(kinah) && farmFor(kinahAt)) farmDay = LK.F.addCounter(farmDay, kinah, kinahAt, zone, placeLabel())
        for (const u of used) if (farmFor(u[1])) farmDay = LK.F.keyUsed(farmDay, u[0], u[1])
        saveFarm()
    }
    /// Prices came: the day's items without one get theirs.
    function farmPrices() {
        if (!farmDay) return
        const next = LK.F.settle(farmDay, priceOf)
        if (next !== farmDay) { farmDay = next; saveFarm() }
    }
    function charSums(key) {
        const list = farmList(key).slice()
        if (key === farmKey && farmDay && !LK.F.isEmpty(farmDay)) {
            const s = LK.F.summary(farmDay)
            const i = list.findIndex((x) => x.day === farmDay.day)
            if (i >= 0) list[i] = s
            else list.push(s)
        }
        return list.sort((a, b) => a.day - b.day)
    }
    function allKeys() {
        const keys = chars.map((c) => c.key)
        const cur = currentKey()
        if (cur && keys.indexOf(cur) < 0) keys.push(cur)
        return keys
    }
    /// The days looked at: one character's, or the whole account's.
    function farmSums() {
        if (settings.farmWho === "all") {
            const byChar = {}
            for (const k of allKeys()) byChar[nameOf(k)] = charSums(k)
            return LK.F.mergeSums(byChar)
        }
        const key = viewKey()
        return key ? charSums(key) : []
    }

    // ---------- the farm window (MN, 2026-11-13/14) ----------
    // Shows Kinah toward the daily 1,000,000, the worth per hour, the gold
    // items, a dungeon's run, keys and tickets, Odyle energy and the ping;
    // which of them is the player's choice (MN, 0.8.13: "was er zeigen soll").
    // Modes (settings.farmMode): "always" while AION 2 runs (the default),
    // "popup" while farming (goes in a town, 10 minutes after the last gain
    // in the open world, or with its × until the next place), "off".
    readonly property var farmRowList: [["kinah", "Kinah today"], ["perHour", "Worth per hour"], ["gold", "Gold items"], ["run", "Dungeon run"], ["keys", "Keys and tickets"], ["odyle", "Odyle energy"], ["ping", "Ping"]]
    function farmMode() {
        const m = settings.farmMode
        if (m === "always" || m === "popup" || m === "off") return m
        return settings.farmWindow === false ? "off" : "always"
    }
    function farmRow(k) { const r = settings.farmRows || {}; return r[k] !== undefined ? !!r[k] : true }
    function setFarmRow(k, on) { const r = Object.assign({}, settings.farmRows || {}); r[k] = !!on; set("farmRows", r) }
    property real zoneSince: 0
    property bool farmShown: false
    property bool farmDismissed: false
    readonly property bool farmWanted: !farmDismissed && (settings.farmMode === "always" || (settings.farmMode == null && settings.farmWindow !== false) || (settings.farmMode === "popup" && farmShown))
    property Timer farmIdle: Timer { interval: 600000; onTriggered: store.farmGone() }
    // Farming means gains coming in a row: the first 30 s in a place (a
    // login's or a teleport's items) don't count, then two gains open it
    // (MN, 0.8.12: it opened right after logging in; 0.8.13: three were too
    // many, it never opened). farmWaits says what it waits for.
    property int farmHits: 0
    property real farmLastTo: 0
    property string farmWaits: "Waiting for Kinah or loot in the open world or a dungeon."
    function farmCheck() {
        if (!farmDay || farmKey !== currentKey()) return
        const k = LK.F.zoneSource(zone)
        if (k !== "open" && k !== "dungeon") { farmWaits = "Not in the open world or a dungeon (" + placeLabel() + ")."; return farmGone() }
        const st = farmDay.stints[farmDay.stints.length - 1]
        if (!st || st.to < zoneSince - 1000 || Date.now() - st.to > 600000) return
        if (!(st.kinah > 0 || st.n > 0)) return
        if (st.to !== farmLastTo && st.to - zoneSince > 30000) { farmLastTo = st.to; farmHits++ }
        if (farmHits < 2) { farmWaits = farmHits + " of 2 gains here so far (the first 30 s in a place don't count)."; return }
        farmWaits = "Farming in " + placeLabel() + "."
        farmShown = true
        if (k === "open") farmIdle.restart()
        else farmIdle.stop()
    }
    function farmGone() { farmShown = false; farmIdle.stop(); farmHits = 0 }
    function farmPlace(z) {
        const before = LK.F.zoneSource(zone), now = LK.F.zoneSource(z)
        // From one field to the next it stays; a dungeon is a run of its own.
        if (before === "open" && now === "open") return
        zoneSince = Date.now()
        farmDismissed = false
        farmGone()
    }
    function dismissFarm() { farmDismissed = true; changed() }
    /// What the farm window shows.
    function farmNow() {
        const d = farmDay && farmKey === currentKey() ? farmDay : null
        const mode = LK.F.zoneSource(zone) === "dungeon" ? "dungeon" : "open"
        const none = { kinah: 0, active: 0, gold: 0, worth: 0, n: 0 }
        const src = d ? d.src || {} : {}
        const open = Object.assign({}, none, src.open || {})
        let gold = 0, worth = 0
        for (const k in src) { gold += src[k].gold || 0; worth += src[k].worth || 0 }
        const hours = (open.active || 0) / 3600000
        const run = { kinah: 0, gold: 0, worth: 0, n: 0, from: null }
        if (d && mode === "dungeon") for (const st of d.stints) {
            if (st.to < zoneSince - 1000 || st.zone !== Number(zone)) continue
            run.kinah += st.kinah || 0; run.gold += st.gold || 0; run.worth += st.worth || 0; run.n += st.n || 0
            if (run.from == null || st.from < run.from) run.from = st.from
        }
        return {
            mode: mode, place: placeLabel(),
            kinah: d && d.counter ? d.counter.last : open.kinah, cap: LK.C.KINA_DAILY, capAt: d && d.cap ? d.cap.at : null,
            // Kinah and the loot's worth per hour of open-world farming.
            perHour: hours >= 0.05 ? (open.kinah + open.worth) / hours : null, hours: hours,
            gold: gold, worth: worth, run: run, keys: farmKeys(), extras: farmExtras()
        }
    }
    /// Ping and Odyle energy, as the DPS meter's bar shows them (the engine
    /// counts them whether the DPS panel is open or not).
    function farmExtras() {
        let f = null
        try { f = JSON.parse(Aion2.fight) } catch (e) { }
        const x = f && f.extras ? f.extras : {}
        if (demo) return { ping: 14, odyle: [90, 1850] }
        return { ping: x.ping == null ? null : Number(x.ping), odyle: Array.isArray(x.odyle) ? x.odyle : null }
    }
    /// The keys and tickets the character has now, only those with some
    /// left: Shugo Festival, Nightmare, Dimensional Invasion, Daily Dungeon,
    /// the entry tickets, Subjugation and Ascension Trial; not the many
    /// reward counters (MN, 0.8.12: "was ist das?"). [{ name, left, max }].
    readonly property var keyIds: ["1", "7", "4", "8", "101", "102", "103", "70000001", "80000001"]
    function farmKeys() {
        const counts = character && character.contentCounts || {}
        const out = []
        for (const id of keyIds) {
            const t = T.TICKETS[id], v = counts[id]
            if (!t || t[4] || !Array.isArray(v)) continue
            const left = (Number(v[0]) || 0) + (Number(v[1]) || 0)
            if (left > 0) out.push({ id: id, name: t[0].replace(/ Entry Count$/, ""), left: left, max: t[1] || 0, server: !!t[3] })
        }
        for (const k of out) if (out.some((o) => o !== k && o.name === k.name)) k.name += k.server ? " (account)" : " (character)"
        return out
    }

    // ---------- Drops: dungeon runs ----------
    property var runLists: ({})
    property var energyLast: null
    function runList(key) {
        if (!(key in runLists)) { const l = get("d-" + key); runLists[key] = Array.isArray(l) ? l : [] }
        return runLists[key]
    }
    function runs(fn) {
        const key = currentKey()
        if (!key) return
        const before = runList(key)
        const next = fn(before)
        if (JSON.stringify(next) === JSON.stringify(before)) return
        runLists[key] = next
        put("d-" + key, next)
        changed()
    }
    function runEnergy(c) {
        const key = currentKey()
        const value = LK.DG.energyOf(c)
        if (!key || value == null) return
        const before = energyLast && energyLast.key === key ? energyLast.value : null
        energyLast = { key: key, value: value }
        if (before != null && value < before) {
            const at = Number(((c.seenAt || {}).contentCounts || {})[LK.DG.ENERGY]) || Date.now()
            const z = zone
            runs((l) => LK.DG.spend(l, z, before - value, at))
        }
    }
    function runsShown() {
        if (settings.farmWho === "all") {
            const out = {}
            for (const k of allKeys()) out[nameOf(k)] = runList(k)
            return out
        }
        const key = viewKey()
        return key ? runList(key) : []
    }

    // ---------- Closet ----------
    property var closet: null // Map look -> copies
    property real closetAt: 0
    property var closetChars: ({}) // key -> { name, serverId, stocks: { tab: stock } }
    property var seen: []
    property var learned: ({})
    property var bag: null
    property var recent: []
    property real lastShopOpen: 0
    property var lastStock: null
    /// At the shop or the closet now (the shop window's moment).
    property bool here: false
    property string hereBy: ""
    property real hereSince: 0
    property var hereZone: null
    property var anchor: null
    property real walkingSince: 0
    /// Closed with its × until you come back.
    property bool dismissed: false
    /// The shop window shows now.
    /// "market": the game's Shop or Market opened (a shop opening with no
    /// merchant's stock after it), "hand": the Closet tab's button. Each place has its
    /// own switch (MN, 2026-11-13: at the merchant yes, at the Market no).
    readonly property bool windowWanted: !dismissed && here
        && (hereBy === "hand" || (hereBy === "market" ? settings.marketWindow === true : settings.shopWindow !== false))
    readonly property int goal: LK.L.GOAL
    function saveCloset() {
        put("closet", { ids: closet ? Array.from(closet) : [], at: closetAt, chars: closetChars, seen: seen.slice(-1500), learned: learned })
        changed()
    }
    function arrived(by) {
        if (!here) { dismissed = false; hereZone = zone }
        hereBy = by
        hereSince = Date.now()
        here = true
        anchor = null
        walkingSince = 0
        // Each shop page (a tab) starts it again: a minute after the last
        // one it goes, should nothing else have told that you left (MN, 0.8.13).
        hereTimer.interval = by === "hand" ? 180000 : 60000
        hereTimer.restart()
        changed()
    }
    function left() {
        merchant = null
        merchantMissing = 0
        here = false
        dismissed = false
        hereTimer.stop()
        changed()
    }
    /// The window's × : gone until you come back to the shop or the closet.
    function dismiss() { dismissed = true; changed() }
    /// Shown by hand (the Closet tab's button): as if just arrived.
    function showWindow(view) {
        if (view) set("windowView", view)
        dismissed = false
        arrived("hand")
    }
    property Timer hereTimer: Timer { interval: 180000; onTriggered: store.left() }
    /// The Market and the merchant send the same opening frame; the merchant
    /// sends its stock right after, the Market nothing: a shop opening with
    /// no stock within 4 s was the Market.
    property Timer marketTimer: Timer { interval: 4000; onTriggered: if (!store.here || store.hereBy === "market") store.arrived("market") }
    function closetKey() {
        const c = character
        return c && c.name ? LK.C.charKey(c.serverId, c.name) : "unknown"
    }
    function onStock(stock) {
        const key = closetKey()
        const c = closetChars[key] || (closetChars[key] = { name: character ? character.name : "?", serverId: character ? character.serverId : null, stocks: {} })
        const before = c.stocks[stock.tab]
        const offersOf = (s) => s.offers.map((o) => o.offer).join()
        const paid = !!before && before.refresh === stock.refresh && offersOf(before) !== offersOf(stock)
        const same = !!before && before.refresh === stock.refresh && !paid
        c.stocks[stock.tab] = stock
        for (const tab in c.stocks) if (c.stocks[tab].refresh <= stock.at) delete c.stocks[tab]
        if (!same) {
            const marks = stock.offers.map((o) => LK.L.statusOf(o.item, closet, ix, learned))
            seen.push({ at: stock.at, "char": key, tab: stock.tab, refresh: stock.refresh, paid: paid,
                skins: marks.filter((m) => m.skin).length, fresh: marks.filter((m) => m.status === "new").length })
            if (seen.length > 1600) seen = seen.slice(-1500)
        }
        lastStock = { at: Date.now(), owner: character ? character.name : "" }
        saveCloset()
        if (Date.now() - stock.at < 60000) {
            marketTimer.stop()
            const wasHere = here && hereBy === "shop"
            arrived("shop")
            if (!wasHere || !merchant) pickMerchant()
        }
    }
    function decodedCloset(e) {
        const d = e.data, at = Number(e.at) || Date.now()
        if (e.name === "closet-list") {
            const ids = LK.L.closetFrom(d)
            if (!ids) return
            closet = ids
            closetAt = at
            saveCloset()
            if (Date.now() - at < 60000) arrived("closet")
        } else if (e.name === "closet-add") {
            const added = LK.L.addedFrom(d)
            if (!added || !closet) return
            for (const a of added) {
                const had = closet.has(a.id)
                closet.set(a.id, a.count > 0 && a.count < 100 ? a.count : (closet.get(a.id) || 0) + 1)
                if (had || ix.looks.has(a.id)) continue
                // A look the data has no skin for: the skin item that just came or went is the one.
                const r = recent.filter((x) => Math.abs(x.at - at) < 8000).map((x) => ix.items.get(x.item)).filter((s) => s && !s.look && !learned[s.item])
                if (r.length === 1) learned[r[0].item] = a.id
            }
            closetAt = at
            saveCloset()
        } else if (e.name === "shop") {
            const stock = LK.L.stockFromShop(d, at)
            if (stock) onStock(stock)
        } else if (e.name === "shop-open") {
            if (Date.now() - at > 60000) return
            lastShopOpen = Date.now()
            if (here && hereBy !== "market") return
            marketTimer.restart()
        }
    }
    /// The merchant: the NPC nearest to you when its stock came (within
    /// 15 m). Out of sight (gone from the NPCs around) or 8 m away from it,
    /// you left (MN, 0.8.13: it closed only minutes after leaving).
    property var merchant: null
    property int merchantMissing: 0
    property var lastWorld: null
    function pickMerchant() {
        merchant = null
        merchantMissing = 0
        const w = lastWorld
        const me = w && w.me
        if (!me || !isFinite(me.x) || !isFinite(me.y) || !Array.isArray(w.npcs)) return
        let best = null, bestD = 1500
        for (const n of w.npcs) {
            const d = Math.hypot(n[2] - me.x, n[3] - me.y)
            if (d < bestD) { bestD = d; best = n }
        }
        if (best) merchant = { e: best[0], x: best[2], y: best[3] }
    }
    function closetWorld(w) {
        lastWorld = w
        if (w.zone != null && here && hereZone != null && w.zone !== hereZone) return left()
        if (here && hereZone == null && w.zone != null) hereZone = w.zone
        if (!here) return
        const me = w.me
        if (hereBy === "shop" && merchant && Array.isArray(w.npcs)) {
            const m = w.npcs.find((n) => n[0] === merchant.e)
            if (!m) { if (++merchantMissing >= 2) return left() }
            else {
                merchantMissing = 0
                if (me && me.exact && Math.hypot(me.x - merchant.x, me.y - merchant.y) > 800) return left()
            }
        }
        // Walking means the shop is closed (no frame says so): the client's
        // steps (world.moving) for 1.5 s, from 3 s after arriving, close it
        // (MN, 0.8.12: it stayed open after leaving the merchant). Opened by
        // hand it stays.
        if (hereBy !== "hand" && w.moving === true && Date.now() - hereSince > 3000) {
            if (!walkingSince) walkingSince = Date.now()
            else if (Date.now() - walkingSince >= 1500) { walkingSince = 0; return left() }
        } else if (w.moving === false) walkingSince = 0
        if (!me || !isFinite(me.x) || !isFinite(me.y)) return
        // Positions are in cm. An exact one says 6 m away; the estimated
        // ones (about 10 m off) count from 30 m (MN: it stayed open).
        if (!anchor || (me.exact && !anchor.exact)) anchor = { x: me.x, y: me.y, exact: !!me.exact }
        else if (Math.hypot(me.x - anchor.x, me.y - anchor.y) > (me.exact && anchor.exact ? 600 : 3000)) left()
    }
    function closetItems(it) {
        if (it.snapshotAt && here && hereBy === "closet" && Date.now() - hereSince < 15000) left()
        const inv = it.containers && it.containers["1"]
        if (Array.isArray(inv)) bag = inv
        for (const ch of Array.isArray(it.changes) ? it.changes : []) if (ix.items.has(ch[3])) recent.push({ at: ch[1], item: ch[3] })
        while (recent.length > 50) recent.shift()
    }
    /// The Exchange's prices of the skins (the PriceBook's): item -> { price, listings, at, from }.
    function exchange() {
        const out = new Map()
        if (!book) return out
        for (const e of book.prices) {
            const item = Number(e[0])
            if (ix.items.has(item) && e[1].price > 0) out.set(item, { price: e[1].price, listings: e[1].listings || 0, at: book.fetchedAt, from: "list" })
        }
        return out
    }
    /// A pet offer as Pet Finder's merchant list judges it (PetTracker's
    /// tables: the shop item's pet, the pets only chests and merchants
    /// give): { pet, level (0..3, -1 not read yet), status "buy" (only
    /// chests and merchants give it, not at level 3), "need" (not at
    /// level 3, mobs drop it too), "owned" (level 3) or "" (not known),
    /// portrait }. MN, 0.8.12: the pets first, and which to buy.
    function petInfo(item) {
        const out = { pet: null, level: -1, status: "", portrait: "", watch: false, souls: 0, from: "" }
        if (typeof Aion2.petData !== "function") return out
        try {
            if (!petCatalog) petCatalog = JSON.parse(Aion2.petData())
            let pet = petCatalog.market ? petCatalog.market[String(item)] : null
            if (pet == null) {
                const nm = LK.C.name(item).toLowerCase()
                for (const id in petCatalog.pets || {}) { const p = petCatalog.pets[id]; if (p && p.name && nm.indexOf(String(p.name).toLowerCase()) >= 0) { pet = Number(id); break } }
            }
            if (pet == null) return out
            const info = JSON.parse(Aion2.pets || "{}")
            const synced = info.synced > 0 || demo
            const level = synced ? Number((info.levels || {})[pet]) || (demo ? pet % 4 : 0) : -1
            out.pet = pet
            out.level = level
            out.watch = (petCatalog.watch || []).indexOf(pet) >= 0
            out.portrait = petDir + pet + ".webp"
            out.status = level < 0 ? "" : level >= 3 ? "owned" : out.watch ? "buy" : "need"
            out.souls = synced ? Number((info.souls || {})[pet]) || 0 : 0
            // Where it comes from: only chests and merchants, else the monster
            // seen most often that drops its soul (MN: "ob die nur aus der kiste kommen").
            const d = petCatalog.pets ? petCatalog.pets[pet] : null
            const drops = d && d.drops ? d.drops.slice().sort((a, b) => (b.spawns || 0) - (a.spawns || 0)) : []
            out.from = out.watch || !drops.length ? (d && d.chests && d.chests.length || out.watch ? "Chests and merchants only" : "") : "Drops: " + drops[0].name
        } catch (e) { }
        return out
    }
    readonly property string petDir: typeof Aion2.mapDir === "function" ? Aion2.mapDir().replace(/\/map$/, "") + "/pets/portraits/" : ""
    /// The pets you don't have yet (Pet Finder's levels), each with where it
    /// comes from: chests first (the merchant's and the Battle Pass' boxes),
    /// then the monsters that drop its soul. MN, 2026-11-13.
    property var petCatalog: null
    /// Souls a pet needs at each level to reach the next (Pet Finder's).
    readonly property var petGoals: [5, 25, 75]
    function petsNeeded() {
        if (typeof Aion2.petData !== "function") return { synced: false, rows: [] }
        try {
            if (!petCatalog) petCatalog = JSON.parse(Aion2.petData())
            const p = JSON.parse(Aion2.pets || "{}")
            if (demo && !(p.synced > 0)) { p.synced = 1; p.levels = {}; for (const id in petCatalog.pets) if (Number(id) % 4) p.levels[id] = 2 }
            const lv = p.levels || {}
            const rows = []
            for (const id in petCatalog.pets || {}) {
                const d = petCatalog.pets[id]
                if (!d || !d.name || (lv[id] || 0) > 0) continue
                const chests = (d.chests || []).map((c) => String(c.name).replace("Chestt", "Chest").replace(/\s*\(Bound\)/, "") + (c.chance ? " " + c.chance : "") + (c.from && c.from.length ? " (" + c.from.join(", ") + ")" : ""))
                const drops = (d.drops || []).slice().sort((a, b) => (b.spawns || 0) - (a.spawns || 0))
                const drop = drops.length ? drops[0].name + " · " + (drops[0].zone || drops[0].region || "") + (drops.length > 1 ? " +" + (drops.length - 1) : "") : ""
                if (!chests.length && !drop) continue
                rows.push({ id: id, name: d.name, genus: d.genus || "", chest: chests.length > 0, from: chests.length ? chests.join("; ") + (drop ? " · or " + drop : "") : drop })
            }
            rows.sort((a, b) => Number(b.chest) - Number(a.chest) || a.name.localeCompare(b.name))
            return { synced: p.synced > 0, rows: rows }
        } catch (e) { return { synced: false, rows: [] } }
    }
    /// The offers to show at the shop: the stock opened last this hour (all
    /// its tabs, skins and pets), with whose it is.
    function offersNow() {
        const now = Date.now()
        if (!petCatalog && typeof Aion2.petData === "function") try { petCatalog = JSON.parse(Aion2.petData()) } catch (e) { }
        let best = null
        for (const k in closetChars) {
            const c = closetChars[k]
            if (character && c.serverId != null && character.serverId != null && c.serverId !== character.serverId) continue
            const live = Object.keys(c.stocks).map((t) => c.stocks[t]).filter((s) => s.refresh > now)
            const at = Math.max.apply(null, [0].concat(live.map((s) => s.at || 0)))
            if (live.length && (!best || at > best.at)) best = { c: c, live: live, at: at }
        }
        if (!best) return { offers: [], owner: "", refresh: 0 }
        const offers = []
        for (const s of best.live.sort((x, y) => x.tab - y.tab)) {
            const pets = s.tab % 100 === 4
            for (const o of s.offers) {
                const m = LK.L.statusOf(o.item, closet, ix, learned)
                if (m.skin) offers.push({ item: o.item, name: m.skin.name, sub: (LK.L.GRADES[m.skin.grade] || "") + " · " + m.skin.slot, grade: m.skin.grade, status: m.status, price: o.price, discount: o.discount, tab: s.tabName, soldOut: !!o.soldOut, icon: m.skin.icon ? "Icon_" + m.skin.icon : LK.C.icon(o.item), pet: false })
                else if (pets || (petCatalog && petCatalog.market && petCatalog.market[String(o.item)] != null) || /^Pet:/i.test(LK.C.name(o.item))) {
                    // A pet on any tab: the Special tab has them too (MN, 0.8.13).
                    const pi = petInfo(o.item)
                    if (pi.pet == null && !pets) continue
                    const nm = pi.pet != null && petCatalog.pets[pi.pet] ? petCatalog.pets[pi.pet].name : LK.C.name(o.item).replace(/^Pet:\s*/, "")
                    offers.push({ item: o.item, name: nm, sub: pi.level < 0 ? "Pet" : pi.level >= 3 ? "Pet · level 3" : "Pet · level " + pi.level + " of 3", grade: LK.C.grade(o.item), status: pi.status, price: o.price, discount: o.discount, tab: s.tabName, soldOut: !!o.soldOut, icon: LK.C.icon(o.item), portrait: pi.portrait, pet: true,
                        souls: pi.level >= 0 && pi.level < 3 ? pi.souls + " / " + petGoals[pi.level] + " souls" : "", from: pi.status === "owned" ? "" : pi.from })
                }
            }
        }
        // The tab opened last first: at the Pets tab the pets lead (MN).
        const last = best.live.reduce((x, y) => ((y.at || 0) > (x.at || 0) ? y : x))
        const petsFirst = last.tab % 100 === 4
        const rank = (o) => (o.status === "new" || o.status === "buy" ? 0 : o.status === "need" ? 1 : o.status === "unknown" || o.status === "" ? 2 : 3)
        offers.sort((x, y) => (petsFirst ? Number(y.pet) - Number(x.pet) : Number(x.pet) - Number(y.pet)) || Number(!!x.soldOut) - Number(!!y.soldOut) || rank(x) - rank(y) || y.price - x.price)
        const buy = offers.filter((o) => o.pet && o.status === "buy" && !o.soldOut)
        const need = offers.filter((o) => o.pet && o.status === "need" && !o.soldOut)
        const advice = !offers.some((o) => o.pet) ? "" : buy.length ? "Buy: " + buy.map((o) => o.name).join(", ") + " (only chests and merchants give them)" + (need.length ? ". Still needed, but monsters drop them too: " + need.map((o) => o.name).join(", ") : "")
            : need.length ? "None of these pets is merchant-only. Still needed, but monsters drop them too: " + need.map((o) => o.name).join(", ")
            : offers.some((o) => o.pet && o.status === "") ? "Open the pet collection in the game once: then it says which pets to buy." : "Nothing to buy here: every pet on offer is at level 3."
        return { offers: offers, owner: best.c.name, refresh: Math.min.apply(null, best.live.map((s) => s.refresh)), advice: advice, petsFirst: petsFirst }
    }
    /// The skins you lack listed on the Exchange, cheapest first.
    function exchangeList(limit) {
        if (!closet) return { rows: [], total: 0, note: "Log in while the companion runs: the game sends your closet then." }
        const ex = exchange()
        if (!ex.size) return { rows: [], total: 0, note: book && book.busy ? "The Exchange prices are loading." : "No Exchange prices for your server yet." }
        const listed = LK.L.missing(closet, ix).map((m) => ({ m: m, e: LK.L.exchangeOf(m.look, ix, ex) })).filter((x) => x.e).sort((a, b) => a.e.price - b.e.price)
        if (!listed.length) return { rows: [], total: 0, note: "None of the skins you lack is on the Exchange now." }
        return { total: listed.length, note: "", rows: listed.slice(0, limit).map((x) => ({ item: x.e.item, name: x.m.name, sub: (LK.L.GRADES[x.m.grade] || "") + " · " + x.m.slot, grade: x.m.grade, price: x.e.price, listings: x.e.listings, good: LK.L.goodBuy(x.e.price, x.m.price), icon: x.m.icon ? "Icon_" + x.m.icon : "" })) }
    }
    function advise() {
        const cb = LK.L.combine(closet, ix, { lucky: !!settings.lucky })
        return { combined: cb, extracted: LK.L.extraction(closet, LK.CD.gear, cb) }
    }
    function todo() {
        if (!closet) return ""
        const a = advise()
        const plan = (LK.L.advice(a.combined, a.extracted) || []).find((x) => x.kind === "plan")
        if (!plan) return ""
        if (plan.now.length) return "Combine in the closet: " + plan.now.map((n) => n.times + "× " + n.name).join(", then ")
        return "Nothing to combine yet: keep collecting"
    }
    /// The characters of the server and whether each looked at the shop this hour.
    function closetCharsNow() {
        const now = Date.now()
        const by = {}
        for (const k in closetChars) {
            const c = closetChars[k]
            if (!c.name || c.name === "?") continue
            if (character && c.serverId != null && character.serverId != null && c.serverId !== character.serverId) continue
            const live = Object.keys(c.stocks).map((t) => c.stocks[t]).filter((s) => s.refresh > now)
            let fresh = 0
            for (const s of live) for (const o of s.offers) if (LK.L.statusOf(o.item, closet, ix, learned).status === "new") fresh++
            const row = by[c.name] || { name: c.name, looked: false, fresh: 0 }
            row.looked = row.looked || live.length > 0
            row.fresh += fresh
            by[c.name] = row
        }
        return Object.keys(by).map((n) => by[n])
    }

    // ---------- Cards ----------
    property var rounds: []
    property var odd: []
    property var shownRound: null
    function cardsRound(e) {
        const at = Number(e.at) || Date.now()
        const parsed = LK.S.parseRound(e.data && e.data.body)
        if (!parsed) {
            const body = e.data && e.data.body
            if (typeof body === "string" && !odd.some((o) => o.body === body)) { odd = odd.concat([{ at: at, body: body }]).slice(-5); put("cards", { rounds: rounds, odd: odd }) }
            return
        }
        const kept = LK.S.keep(parsed, at, character ? character.name : null, character ? character.serverId : null)
        const k = rounds.findIndex((r) => r.key === kept.key)
        if (k >= 0) {
            // The second copy: only the picks may have changed.
            const was = rounds[k]
            rounds[k] = Object.assign({}, kept, { at: was.at, who: kept.who || was.who || null, server: kept.who ? kept.server : (was.server == null ? null : was.server) })
        } else {
            rounds = rounds.concat([kept]).slice(-1500)
            shownRound = null
        }
        put("cards", { rounds: rounds, odd: odd })
        changed()
    }
    function cardChar() {
        const c = settings.cardChar
        return c !== "all" && rounds.some((r) => LK.S.charKey(r) === c) ? c : "all"
    }
    function cardRounds(kind) { return LK.S.only(LK.S.ofChar(rounds, cardChar()), kind === undefined ? settings.cardKind : kind, settings.kinds) }

    // ---------- from the game ----------
    property Connections watch: Connections {
        target: Aion2
        enabled: !store.demo
        function onItemsEvent(json) { let it = null; try { it = JSON.parse(json) } catch (e) { return } store.takeItems(it) }
        function onDecoded(json) {
            let list = []
            try { list = JSON.parse(json) } catch (e) { return }
            for (const e of list) store.takeDecoded(e)
        }
        function onCharacterChanged() { let c = null; try { c = JSON.parse(Aion2.character) } catch (e) { } store.takeCharacter(c) }
        function onWorldChanged() { let w = null; try { w = JSON.parse(Aion2.world) } catch (e) { } if (w) store.takeWorld(w) }
        function onActiveChanged() { if (Aion2.active) Qt.callLater(() => { let it = null; try { it = JSON.parse(Aion2.itemsNow()) } catch (e) { } if (it) store.takeItems(it) }) }
    }
    property var lastItems: null
    function takeItems(it) {
        if (!it || typeof it !== "object") return
        lastItems = it
        farmItems(it)
        const any = (it.changes && it.changes.length) || (it.pickups && it.pickups.length)
        if (any) {
            const ats = (it.changes || []).map((c) => c[1]).filter((x) => isFinite(x))
            if (ats.length) rollAt(Math.min.apply(null, ats))
            session = LK.C.addDrops(session, it)
            if (it.changes && it.changes.length) {
                const where = LK.F.trackItems(session.where, it, zone, placeLabel(), priceOf, session.start || 0)
                session = Object.assign({}, session, { where: where })
                const z = zone
                runs((l) => LK.DG.addItems(l, z, it))
            }
            put("session", session)
        }
        noteItems(it)
        closetItems(it)
        changed()
    }
    function takeDecoded(e) {
        if (!e || !e.name) return
        if (e.name === "gathered") {
            if (!e.data || e.data.kind !== 58) return
            const at = Number(e.at) || Date.now()
            rollAt(at)
            session = LK.C.addGather(session, e.data, at, placeLabel())
            put("session", session)
            changed()
        } else if (e.name === "round") cardsRound(e)
        else decodedCloset(e)
    }
    function takeCharacter(c) {
        if (!c || !c.name) return
        const keyBefore = currentKey()
        const serverBefore = character ? character.serverId : null
        character = c
        if (currentKey() !== farmKey) keyCounts = ({})
        farmCharacter(c)
        if (currentKey() !== keyBefore && zone != null) { const z = zone; runs((l) => LK.DG.enter(l, z, Date.now())) }
        runEnergy(c)
        // The first items of a character (sent before its name was known) are its.
        if (c.serverId !== serverBefore && lastItems && !lastItems.snapshotAt) noteItems(lastItems)
        if (!closetChars[closetKey()]) { closetChars[closetKey()] = { name: c.name, serverId: c.serverId, stocks: {} }; saveCloset() }
        changed()
    }
    function takeWorld(w) {
        const z = Number(w.zone)
        if (z > 0 && z !== zone) {
            farmPlace(z)
            zone = z
            runs((l) => LK.DG.enter(l, z, Date.now()))
        }
        closetWorld(w)
    }
    property Connections prices: Connections {
        target: store.book
        function onRevisionChanged() { store.farmPrices(); store.changed() }
    }

    // ---------- the old meter's data (MN, 2026-11-13) ----------
    /// What the last take-over brought, for the panel ("" before one).
    property string meterNote: ""
    property bool meterBusy: false
    /// Reads the Clicktrough meter's Inventory, Closet and Shugo Cards files
    /// (local, read only) and adds what LOOT lacks: once by itself, again
    /// with the Items tab's button. What LOOT has itself wins.
    function readMeter() {
        if (demo || meterBusy || typeof Aion2.meterRead !== "function") return
        meterBusy = true
        changed()
        Aion2.meterRead()
    }
    property Connections meterAnswer: Connections {
        target: Aion2
        ignoreUnknownSignals: true
        function onMeterGot(json) { store.takeMeter(json) }
    }
    function takeMeter(json) {
        meterBusy = false
        let m = {}
        try { m = JSON.parse(json) || {} } catch (e) { }
        const inv = m.inventory || {}, cl = m.closet || {}, sc = m["shugo-cards"] || {}
        const n = { chars: 0, days: 0, runs: 0, sessions: 0, rounds: 0, closet: false }
        // Characters and their items.
        if (Array.isArray(inv.chars)) {
            const known = {}
            for (const c of chars) known[c.key] = true
            const add = inv.chars.filter((c) => c && typeof c.key === "string" && /^c-/.test(c.key) && !known[c.key])
            if (add.length) { chars = chars.concat(add); put("chars", chars); n.chars = add.length }
        }
        for (const k in inv) {
            const v = inv[k]
            if (!v || typeof v !== "object") continue
            if (/^c-[0-9a-z?-]+$/.test(k) && !Array.isArray(v)) {
                const have = stock(k)
                if (!have || (Number(v.at) || 0) > (Number(have.at) || 0) && !have.exactAt) { stocks[k] = v; put("s-" + k, v) }
            } else if (/^acc-\d+$/.test(k)) {
                const sid = k.slice(4), have = account(sid)
                if (!have) { accounts[sid] = v; put(k, v) }
            } else if (/^fc-/.test(k) && Array.isArray(v)) {
                const key = k.slice(1), list = farmList(key), days = {}
                for (const x of list) days[x.day] = true
                const add = v.filter((x) => x && isFinite(x.day) && !days[x.day])
                if (add.length) { farmLists[key] = list.concat(add).sort((a, b) => a.day - b.day).slice(-farmDays); put("f-" + key, farmLists[key]); n.days += add.length }
            } else if (/^fc-.+-\d{8}$/.test(k) && !Array.isArray(v)) {
                if (!get("f-" + k.slice(1))) put("f-" + k.slice(1), v)
            } else if (/^dc-/.test(k) && Array.isArray(v)) {
                const key = k.slice(1), list = runList(key), have = {}
                for (const r of list) have[r.from] = true
                const add = v.filter((r) => r && isFinite(r.from) && !have[r.from])
                if (add.length) { runLists[key] = list.concat(add).sort((a, b) => b.from - a.from); put("d-" + key, runLists[key]); n.runs += add.length }
            }
        }
        // Sessions: the meter's last one counts as an earlier session.
        const old = (Array.isArray(inv.sessions) ? inv.sessions : []).filter((x) => x && isFinite(x.start)).map(LK.C.normalize)
        if (inv.session && inv.session.start) { const cur = LK.C.normalize(inv.session); if (!LK.C.isEmpty(cur)) old.push(LK.C.summary(cur)) }
        const starts = {}
        for (const h of history) starts[h.start] = true
        starts[session.start] = true
        const addS = old.filter((x) => !starts[x.start])
        if (addS.length) { history = history.concat(addS).sort((a, b) => b.start - a.start).slice(0, keepSessions); put("sessions", history); n.sessions = addS.length }
        // The closet.
        let closetChanged = false
        if (cl.closet && Array.isArray(cl.closet.ids) && cl.closet.ids.length && (!closet || (Number(cl.closet.at) || 0) > closetAt)) {
            closet = new Map(cl.closet.ids.map((e) => (Array.isArray(e) ? [e[0], e[1]] : [e, 1])))
            closetAt = Number(cl.closet.at) || 0
            closetChanged = n.closet = true
        }
        if (cl.chars && typeof cl.chars === "object") {
            for (const k in cl.chars) {
                const c = cl.chars[k]
                if (!c || !c.name || c.name === "?") continue
                const key = LK.C.charKey(c.serverId, c.name)
                if (!closetChars[key]) { closetChars[key] = { name: c.name, serverId: c.serverId, stocks: c.stocks || {} }; closetChanged = true }
            }
        }
        if (Array.isArray(cl.seen) && cl.seen.length) {
            const mark = (x) => x.at + "|" + x.tab
            const have = {}
            for (const x of seen) have[mark(x)] = true
            const add = cl.seen.filter((x) => x && isFinite(x.at) && !have[mark(x)]).map((x) => Object.assign({}, x, { "char": typeof x["char"] === "string" && x["char"].indexOf(":") > 0 ? LK.C.charKey(Number(x["char"].split(":")[0]), x["char"].slice(x["char"].indexOf(":") + 1)) : x["char"] }))
            if (add.length) { seen = seen.concat(add).sort((a, b) => a.at - b.at).slice(-1500); closetChanged = true }
        }
        if (cl.learned && typeof cl.learned === "object") {
            for (const k in cl.learned) if (!(k in learned)) { learned[k] = cl.learned[k]; closetChanged = true }
        }
        if (closetChanged) saveCloset()
        // The card rounds.
        if (Array.isArray(sc.rounds) && sc.rounds.length) {
            const have = {}
            for (const r of rounds) have[r.key + "|" + r.at] = true
            const add = sc.rounds.filter((r) => r && Array.isArray(r.cards) && !have[r.key + "|" + r.at])
            if (add.length) { rounds = rounds.concat(add).sort((x, y) => x.at - y.at).slice(-1500); put("cards", { rounds: rounds, odd: odd }); n.rounds = add.length }
        }
        const found = Object.keys(inv).length + Object.keys(cl).length + Object.keys(sc).length
        const parts = []
        if (n.chars) parts.push(n.chars + " characters")
        if (n.days) parts.push(n.days + " farm days")
        if (n.runs) parts.push(n.runs + " dungeon runs")
        if (n.sessions) parts.push(n.sessions + " sessions")
        if (n.closet) parts.push("the closet")
        if (n.rounds) parts.push(n.rounds + " card rounds")
        meterNote = !found ? "No data of the Clicktrough meter found on this computer."
            : parts.length ? "Taken over from the Clicktrough meter: " + parts.join(", ") + "."
            : "The Clicktrough meter's data is already here."
        set("meterTaken", Date.now())
    }

    Component.onCompleted: {
        if (demo) { makeDemo(); return }
        const s = get("settings")
        if (s && typeof s === "object") settings = Object.assign({}, settings, s)
        const c = get("chars")
        if (Array.isArray(c)) chars = c.filter((x) => x && typeof x.key === "string")
        const se = get("session")
        if (se && se.start) session = LK.C.normalize(se)
        const h = get("sessions")
        if (Array.isArray(h)) history = h.filter((x) => x && isFinite(x.start)).map(LK.C.normalize)
        const cl = get("closet")
        if (cl) {
            if (Array.isArray(cl.ids) && cl.ids.length) closet = new Map(cl.ids.map((e) => (Array.isArray(e) ? [e[0], e[1]] : [e, 1])))
            closetAt = cl.at || 0
            closetChars = cl.chars || {}
            seen = Array.isArray(cl.seen) ? cl.seen : []
            learned = cl.learned || {}
        }
        const cd = get("cards")
        if (cd) {
            rounds = Array.isArray(cd.rounds) ? cd.rounds.filter((x) => x && Array.isArray(x.cards)) : []
            odd = Array.isArray(cd.odd) ? cd.odd : []
            if (odd.length) {
                const a = LK.S.adopt(odd, rounds)
                if (a.add.length) { rounds = rounds.concat(a.add).sort((x, y) => x.at - y.at).slice(-1500); odd = a.still; put("cards", { rounds: rounds, odd: odd }) }
            }
        }
        try { const ch = JSON.parse(Aion2.character); if (ch && ch.name) takeCharacter(ch) } catch (e) { }
        if (!settings.meterTaken) readMeter()
        revision++
    }
    // Written at once when the app ends.
    Component.onDestruction: if (!demo) flush()

    // ---------- GC_DEMO=loot: made-up data for screenshots ----------
    function makeDemo() {
        const now = Date.now()
        const h = 3600000
        const items = MK.G.MARKET_ITEMS.items
        const byGrade = {}
        for (const id in items) {
            const g = items[id][1]
            if (/^93/.test(id) || / \(Bound\)/.test(items[id][0])) continue
            if (!byGrade[g]) byGrade[g] = []
            if (byGrade[g].length < 40) byGrade[g].push(Number(id))
        }
        if (book) {
            const m = new Map()
            for (const g in byGrade) byGrade[g].forEach((id, i) => { if (i % 4 !== 3) m.set(String(id), { price: Math.round(800 * Math.pow(6, Number(g)) * (1 + (i % 5) / 3)), listings: 3 + i, sold: 10, soldAvg: null, change: null, last: null }) })
            for (const s of Array.from(ix.items.values()).slice(0, 400)) if (s.item % 3 === 0) m.set(String(s.item), { price: 50000 + (s.item % 97) * 3000, listings: 2, sold: 1, soldAvg: null, change: null, last: null })
            book.demo = true
            book.prices = m
            book.serverName = "[Server]"
            book.fetchedAt = now - 1800000
            book.revision++
        }
        const pick = (g, i) => (byGrade[g] || byGrade[1])[i % (byGrade[g] || byGrade[1]).length]
        character = { name: "[Character 2]", serverId: 2004 }
        const key = LK.C.charKey(2004, "[Character 2]")
        chars = [{ key: key, name: "[Character 2]", serverId: 2004, at: now }, { key: LK.C.charKey(2004, "[Character 1]"), name: "[Character 1]", serverId: 2004, at: now - 50 * h }]
        const inv = {}
        inv[LK.C.KINA] = 18450210
        for (let i = 0; i < 14; i++) inv[pick(1 + (i % 4), i)] = 1 + (i * 7) % 40
        const ch = {}
        for (let i = 0; i < 8; i++) ch[pick(2, i + 20)] = 5 + i
        stocks[key] = { name: "[Character 2]", serverId: 2004, inv: inv, "char": ch, exactAt: now - 2 * h, at: now }
        const acc = {}
        for (let i = 0; i < 6; i++) acc[pick(3, i + 10)] = 1 + i
        accounts["2004"] = { acc: acc, exactAt: now - 2 * h, at: now }
        // A session: gathered, looted and rewards.
        let s = LK.C.newSession(now - 2 * h)
        let seq = 1
        const ev = (at, item, n) => ({ changes: [[seq++, at, "1", item, n]], pickups: [] })
        for (let i = 0; i < 12; i++) {
            const at = now - 2 * h + i * 9 * 60000
            s = LK.C.addGather(s, { great: i % 4 === 0 ? 1 : 0, kind: 58, node: 100 + (i % 3), item: pick(1, 3), amount: 2, bonus: i % 3 === 0 ? 1 : 0 }, at, "Demo region")
            s = LK.C.addDrops(s, ev(at + 200, pick(1, 3), 2 + (i % 3 === 0 ? 1 : 0)))
            s = LK.C.addDrops(s, { changes: [[seq++, at + 3000, "1", pick(2, i), 1]], pickups: [[seq++, at + 2900, pick(2, i), 1]] })
        }
        s = LK.C.addDrops(s, ev(now - 20 * 60000, pick(4, 2), 1))
        s = LK.C.addDrops(s, ev(now - 18 * 60000, LK.C.KINA, 245000))
        session = s
        history = [Object.assign(LK.C.summary(LK.C.addDrops(LK.C.newSession(now - 26 * h), ev(now - 25 * h, pick(2, 5), 4))), { end: now - 24 * h })]
        // Farm days: two weeks.
        const list = []
        for (let d = 13; d >= 1; d--) {
            const at = LK.F.dayOf(now) - d * 86400000 + 9 * h
            let day = LK.F.newDay(at)
            for (let k = 0; k < 40; k++) {
                const t = at + k * 3 * 60000
                day = LK.F.addCounter(day, Math.min(1000000, 22000 * (k + 1) + d * 1500), t, 1, "Demo field")
                day = LK.F.addItems(day, ev(t + 1000, pick(k % 9 === 0 ? 4 : 2, d + k), 1), 1, (it, n) => 20000 * n, "Demo field")
            }
            list.push(LK.F.summary(day))
        }
        farmLists[key] = list
        // Today, for the farm window (GC_DEMO=loot,farm or loot,farm,dungeon).
        const dm = nativeWindow.demo.split(",")
        if (dm.indexOf("farm") >= 0) {
            const dz0 = Number(Object.keys(LK.DG.RATES || {})[0]) || 600001
            const inDungeon = dm.indexOf("dungeon") >= 0
            let day = LK.F.newDay(now - 2 * h)
            for (let k = 0; k < 30; k++) {
                const t = now - 2 * h + k * 3 * 60000
                day = LK.F.addCounter(day, 18000 * (k + 1), t, 1, "Demo field")
                day = LK.F.addItems(day, ev(t + 1000, pick(k % 7 === 0 ? 4 : 2, k), 1), 1, (it, n) => 20000 * n, "Demo field")
            }
            zone = 1
            if (inDungeon) {
                zone = dz0
                zoneSince = now - 15 * 60000
                for (let k = 0; k < 6; k++) day = LK.F.addItems(day, ev(now - 14 * 60000 + k * 120000, k % 2 ? LK.C.KINA : pick(k % 3 === 0 ? 4 : 2, k), k % 2 ? 42000 : 1), dz0, (it, n) => 35000 * n, "Demo dungeon")
            }
            farmKey = key
            farmDay = day
            farmShown = true
            character = Object.assign({}, character, { contentCounts: { "1": [9, 0], "8": [4, 0], "4": [2, 0], "102": [0, 0], "60000003": [14, 0], "60000001": [500, 0] } })
        }
        // Dungeon runs: a dungeon of the rate table.
        const zones = Object.keys(LK.DG.RATES || {})
        const dz = zones.length ? Number(zones[0]) : 600001
        let r = []
        for (let i = 0; i < 9; i++) {
            const at = now - (9 - i) * 7 * h
            r = LK.DG.enter(r, dz, at)
            r = LK.DG.spend(r, dz, 80, at + 600000)
            if (i % 3 === 0) r = LK.DG.addItems(r, dz, ev(at + 700000, pick(4, i), 1))
            r = LK.DG.enter(r, 1, at + 900000)
        }
        runLists[key] = r
        // The closet: most looks, two stocks this hour.
        const looks = Array.from(ix.looks.keys())
        closet = new Map(looks.filter((l, i) => i % 5 < 3).map((l) => [l, 1]))
        closetAt = now - h
        const skins = Array.from(ix.items.values()).filter((x) => x.look)
        const refresh = Math.ceil(now / h) * h
        const offer = (n, item, price, disc) => ({ offer: n, item: item, price: Math.floor(price * (100 - disc) / 100), original: price, discount: disc, soldOut: n === 3 })
        let petItems = []
        try { petCatalog = JSON.parse(Aion2.petData()); petItems = Object.keys(petCatalog.market || {}).filter((it, i) => i % 9 === 0).slice(0, 6).map(Number) } catch (e) { }
        closetChars[key] = { name: "[Character 2]", serverId: 2004, stocks: {
            "103": { tab: 103, tabName: "Skins", at: now - 120000, refresh: refresh, offers: [offer(1, skins[0].item, 480000, 20), offer(2, skins[3].item, 240000, 30), offer(3, skins[7].item, 96000, 10), offer(4, skins[9].item, 960000, 50)] },
            "104": { tab: 104, tabName: "Pets", at: now - (nativeWindow.demo.indexOf("petsfirst") >= 0 ? 60000 : 130000), refresh: refresh, offers: petItems.map((it, i) => offer(10 + i, it, 300000, 20)) } } }
        closetChars[LK.C.charKey(2004, "[Character 1]")] = { name: "[Character 1]", serverId: 2004, stocks: {} }
        seen = [{ at: now - 5 * h, "char": key, tab: 103, refresh: now - 4 * h, paid: false, skins: 4, fresh: 1 }, { at: now - 3 * h, "char": key, tab: 103, refresh: now - 2 * h, paid: true, skins: 4, fresh: 2 }]
        bag = [[1, skins[12].item, 1], [2, skins[15].item, 2]]
        here = nativeWindow.demo.split(",").indexOf("shop") >= 0
        if (here) hereBy = "shop"
        // Card rounds.
        const card = (place, main, mine, bonus) => { const c = { place: place, main: main, mine: mine }; if (bonus) c.bonus = bonus; return c }
        for (let i = 0; i < 24; i++) {
            const at = now - (24 - i) * 2 * h
            rounds.push({ key: "demo" + i, at: at, event: i % 3 ? 21070110 : 22020112, who: i % 4 ? "[Character 2]" : "[Character 1]", server: 2004,
                cards: [card(0, [[pick(2, i), 5], [930100003, 300]], 0), card(1, [[pick(3, i), 2], [930100023, 4]], i % 2 ? 1 : 0),
                    card(2, [[pick(4, i), 1], [pick(2, i + 3), 10]], 0, i % 5 === 0 ? [[pick(4, i + 1), 1]] : null), card(3, [[pick(1, i), 20]], i % 2 ? 0 : 1), card(4, [[pick(2, i + 7), 12]], 0)] })
        }
        const tab = nativeWindow.demo.split(",").find((x) => ["items", "drops", "closet", "cards"].indexOf(x) >= 0)
        const sub = nativeWindow.demo.split(",").find((x) => ["days", "dungeons", "farmwin", "missing", "combine", "gold", "places", "itemlist", "char", "acc"].indexOf(x) >= 0)
        const st = Object.assign({}, settings)
        if (tab) st.tab = tab
        if (sub === "days" || sub === "dungeons") st.drops = sub
        if (sub === "farmwin") { st.drops = "window"; st.farmMode = "popup"; st.farmRows = { gold: false } }
        if (sub === "missing" || sub === "combine") st.closetTab = sub
        if (sub === "gold" || sub === "places") st.cards = sub
        if (sub === "itemlist") st.cards = "items"
        if (sub === "char" || sub === "acc") st.list = sub
        settings = st
        revision++
    }
}
