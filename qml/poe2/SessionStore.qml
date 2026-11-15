import QtQuick
import GameCompanion
import "sessionkit.js" as SK

// The PoE 2 session tracker's memory (in Main, lives with the app; MN,
// 2026-11-15, "dieselbe Art Session-Tracker wie bei AION 2"). While PoE 2
// runs and the plugin is on, the game's log is followed (Poe2Log: areas,
// level-ups, the own deaths, AFK; never chat or whispers) and fed into the
// running session; a new day or a pause longer than the break (30 min or
// 1 h) starts a new one. Earlier sessions are kept (newest first). Files:
// ~/.local/share/game-companion/poe2/session/ (current, history, prefs).
QtObject {
    id: store
    /// PoE 2 runs and the plugin is on: the log is followed.
    property bool on: false
    property string demo: ""
    readonly property bool demoOn: demo.split(",").indexOf("session") >= 0

    property var session: SK.newSession(Date.now())
    property var history: []
    readonly property int keepSessions: 60
    property var prefs: ({ breakMin: 30, window: true, path: "" })
    property int revision: 0
    signal updated

    readonly property int breakMs: (Number(prefs.breakMin) === 60 ? 60 : 30) * SK.MIN
    /// The session window shows (PoE 2 runs, switched on).
    readonly property bool windowWanted: (on || demoOn) && prefs.window !== false

    function setPref(k, v) {
        const p = Object.assign({}, prefs)
        p[k] = v
        prefs = p
        put("prefs", prefs)
        if (k === "path" && on) Poe2Log.watch(true, String(v || ""))
        bump()
    }
    function bump() { revision++; updated() }

    // ---------- storage, written a moment after a change ----------
    property var dirty: ({})
    function put(key, value) {
        if (demoOn) return
        dirty[key] = value
        if (!saveTimer.running) saveTimer.start()
    }
    function get(key) {
        if (demoOn) return null
        try { return JSON.parse(Poe2Log.load(key) || "null") } catch (e) { return null }
    }
    function flush() {
        const d = dirty
        dirty = ({})
        for (const k in d) Poe2Log.keep(k, JSON.stringify(d[k]))
    }
    property Timer saveTimer: Timer { interval: 1500; onTriggered: store.flush() }

    // ---------- sessions ----------
    function keepOld(done) {
        if (SK.isEmpty(done)) return
        history = [done].concat(history.filter((h) => h.start !== done.start)).slice(0, keepSessions)
        put("history", history)
    }
    /// Ends the running session now and starts another.
    function startNew() {
        const now = Date.now()
        keepOld(SK.finish(session, now))
        session = SK.carryOn(session, now)
        put("current", session)
        bump()
    }
    function heard(events) {
        let s = SK.copy(session)
        for (let i = 0; i < events.length; i++) {
            const ev = events[i]
            const cut = SK.cutAt(s, ev.t, breakMs)
            if (cut !== null) {
                keepOld(SK.finish(s, cut))
                s = s.idleSince != null && ev.t - s.idleSince > breakMs ? SK.newSession(ev.t) : SK.carryOn(s, cut)
            } else if (SK.isEmpty(s)) {
                s.start = ev.t
            }
            SK.apply(s, ev)
        }
        session = s
        put("current", session)
        bump()
    }
    /// What the panel and the window show (counted up to `now`).
    function viewOf(s, now) { rates; return SK.view(s, now, rates) }

    // ---------- loot (part 2): told by hand, priced by poe.ninja ----------
    // Client.txt names no drops and PoE 2 has no stash API (MN, 2026-11-15:
    // to be talked over again later). Currency is counted with + and − or a
    // copied stack; other items come from the price check's "+ Session".
    // poe.ninja (the price check's switch, Settings → Plugins → PoE 2) gives
    // the rates: its exchange overview, asked only while loot needs a price,
    // kept 30 minutes (Poe2.request: poe.ninja's PoE 2 economy only).
    readonly property var priceChoices: { try { return JSON.parse(Poe2.prefs) } catch (e) { return {} } }
    readonly property bool ninjaOn: priceChoices.ninja !== false
    /// { league, at, exalted, byId: { id: { div, name } }, list: [{ id, name, div }] } or null.
    property var rates: null
    property string ratesError: ""
    property bool ratesAsking: false
    property real ratesFailedAt: 0
    readonly property int requestBase: 77000
    property int requestNext: 0
    property var waiting: ({})
    /// The price check's store (its kit knows the trade site's leagues).
    property var price: null
    /// The default rows of the currency list.
    readonly property var usualCurrency: [["divine", "Divine Orb"], ["exalted", "Exalted Orb"], ["chaos", "Chaos Orb"]]

    function ask(url) {
        return new Promise(function (resolve, reject) {
            const id = store.requestBase + (store.requestNext++ % 1000)
            store.waiting[id] = { resolve: resolve, reject: reject }
            Poe2.request(id, "GET", url, "")
        })
    }
    property Connections answers: Connections {
        target: Poe2
        function onAnswered(id, status, headers, body) {
            const w = store.waiting[id]
            if (!w) return
            delete store.waiting[id]
            if (status === 200) w.resolve(body)
            else w.reject(new Error(status ? "poe.ninja answered " + status : body))
        }
    }
    /// A copied item's stack size (1 if none is written).
    function stackOf(text) {
        const m = /^(?:Stack Size|Stapelgröße): *([\d.,\s]+)\//m.exec(String(text || ""))
        return m ? Math.max(1, Number(m[1].replace(/[.,\s]/g, "")) || 1) : 1
    }
    /// Asks poe.ninja for the rates if loot needs them and they are old.
    function needRates() {
        if (!ninjaOn || demoOn || ratesAsking) return
        const now = Date.now()
        if (rates && now - rates.at < 30 * SK.MIN) return
        if (now - ratesFailedAt < 4 * SK.MIN) return
        ratesAsking = true
        const base = "https://poe.ninja/poe2/api/economy/"
        const chosen = String(priceChoices.league || "")
        // No league chosen yet: the price check's own pick (the trade site's
        // league list, kept as the price check's league), poe.ninja's list
        // only if that fails (its shape not seen yet).
        const fromNinja = function () {
            return ask(base + "leagues").then(function (b) {
                const d = JSON.parse(b)
                const list = Array.isArray(d) ? d : (d && (d.leagues || d.items)) || []
                const first = list.length ? (list[0].id || list[0].name || list[0]) : ""
                if (!first) throw new Error("poe.ninja named no league")
                return String(first)
            })
        }
        const fromTrade = function () {
            return store.price.kit("leagues", [""]).then(function (l) {
                if (!l || !l.selected) throw new Error("no league")
                Poe2.setPref("league", JSON.stringify(l.selected))
                return String(l.selected)
            })
        }
        const league = chosen ? Promise.resolve(chosen) : store.price ? fromTrade().then(null, fromNinja) : fromNinja()
        league.then(function (lg) {
            return ask(base + "exchange/current/overview?league=" + encodeURIComponent(lg) + "&type=Currency").then(function (b) { return store.readRates(lg, b) })
        }).then(function (r) {
            rates = r
            ratesError = ""
            ratesAsking = false
            bump()
        }, function (e) {
            ratesFailedAt = Date.now()
            ratesError = String(e && e.message || e)
            ratesAsking = false
            Companion.log("poe2", "session: poe.ninja: " + ratesError)
            bump()
        })
    }
    /// poe.ninja's exchange overview, read as the price check does.
    function readRates(league, text) {
        const d = JSON.parse(text)
        const core = (d && d.core) || {}
        const exalted = Number((core.rates || {}).exalted) || 0
        const names = {}
        const items = (d && d.items) || []
        for (let i = 0; i < items.length; i++) if (items[i] && items[i].id) names[items[i].id] = String(items[i].name || "")
        const byId = {}
        const list = []
        const lines = (d && d.lines) || []
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i]
            if (!l || !l.id || typeof l.primaryValue !== "number") continue
            byId[l.id] = { div: l.primaryValue, name: names[l.id] || l.id }
            list.push({ id: l.id, name: names[l.id] || l.id, div: l.primaryValue })
        }
        if (!byId.divine) byId.divine = { div: 1, name: "Divine Orb" }
        if (!exalted || !list.length) throw new Error("poe.ninja sent no prices")
        list.sort(function (a, b) { return b.div - a.div })
        return { league: league, at: Date.now(), exalted: exalted, byId: byId, list: list }
    }

    function changeLoot(fn) {
        let s = SK.copy(session)
        const now = Date.now()
        const cut = SK.cutAt(s, now, breakMs)
        if (cut !== null) {
            keepOld(SK.finish(s, cut))
            s = SK.carryOn(s, now)
        } else if (SK.isEmpty(s)) s.start = now
        fn(s, now)
        session = s
        put("current", session)
        needRates()
        bump()
    }
    function addCurrency(id, name, n) { changeLoot(function (s) { SK.addCurrency(s, id, name, n) }) }
    function removeItem(index) { changeLoot(function (s) { SK.removeItem(s, index) }) }
    /// "+ Session" in the price check: a currency item adds its stack to the
    /// currency list; another item its price (poe.ninja's, else the median
    /// of the five cheapest listings) in divines.
    function addFromPrice(view, result, text) {
        if (!view) return
        const ninja = (result && result.ninja) || view.ninja
        if (ninja && ninja.id) {
            addCurrency(ninja.id, view.name, stackOf(text))
            return
        }
        const listed = result && result.kind === "trade" ? (result.listed || []).slice(0, 5) : []
        const prices = listed.map(function (l) { return { amount: Number(l.amount) || 0, currency: String(l.currency || "") } }).filter(function (p) { return p.amount > 0 })
        const div = SK.medianDiv(prices, rates)
        changeLoot(function (s, now) { SK.addItem(s, { t: now, name: view.name, div: div, how: div == null ? "" : "listings" }) })
    }
    /// Asks poe.ninja again if the running session holds loot and the
    /// rates are old (the panel and the window call it while they show).
    function freshen() { if (SK.hasLoot(session)) needRates() }

    onOnChanged: {
        Poe2Log.watch(on, String(prefs.path || ""))
        if (!on && !demoOn) {
            session = SK.pause(SK.copy(session), Date.now())
            put("current", session)
            flush()
            bump()
        }
    }
    property Connections log: Connections {
        target: Poe2Log
        function onHeard(text) {
            if (store.demoOn) return
            let list
            try { list = JSON.parse(text) } catch (e) { return }
            if (Array.isArray(list) && list.length) store.heard(list)
        }
    }

    Component.onCompleted: {
        if (demoOn) { showDemo(); return }
        const p = get("prefs")
        if (p) prefs = Object.assign({}, prefs, p)
        const h = get("history")
        if (Array.isArray(h)) history = h.filter((x) => x && isFinite(x.start))
        const c = get("current")
        if (c && c.start) {
            // The app ended while playing: the session paused at its last event.
            session = c.idleSince == null ? SK.pause(c, c.last || c.start) : c
        }
        if (on) Poe2Log.watch(true, String(prefs.path || ""))
        bump()
    }

    // A made-up evening (GC_DEMO=session).
    function showDemo() {
        const MIN = SK.MIN
        const now = Date.now()
        const t0 = now - 98 * MIN
        let s = SK.newSession(t0)
        const ev = (m, e) => SK.apply(s, Object.assign({ t: t0 + m * MIN }, e))
        ev(0, { k: "area", id: "HideoutFelled", name: "Felled Hideout", seed: "1", level: 1 })
        const maps = [["MapCrypt", "Crypt", 79], ["MapBluff", "Bluff", 80], ["MapSavannah", "Savannah", 80], ["MapLostTowers", "Lost Towers", 81],
                      ["MapForge", "Forge", 81], ["MapAugury", "Augury", 81], ["MapWetlands", "Wetlands", 82], ["MapSulphuricCaverns", "Sulphuric Caverns", 82],
                      ["MapHiddenGrotto", "Hidden Grotto", 82], ["MapCrimsonShores", "Crimson Shores", 83], ["MapRavine", "Ravine", 83]]
        let m = 3
        for (let i = 0; i < maps.length; i++) {
            ev(m, { k: "area", id: maps[i][0], name: maps[i][1], seed: String(100 + i), level: maps[i][2] })
            if (i === 3) ev(m + 4, { k: "death" })
            if (i === 6) ev(m + 5, { k: "level", char: "Kaelith", class: "Mercenary", level: 91 })
            if (i === 9) ev(m + 2, { k: "death" })
            const len = 5 + (i * 3) % 4
            if (i < maps.length - 1) {
                ev(m + len, { k: "area", id: "HideoutFelled", name: "Felled Hideout", seed: String(200 + i), level: 1 })
                m += len + 2
            }
        }
        if (s.char) s.char.from = 90
        SK.addCurrency(s, "divine", "Divine Orb", 1)
        SK.addCurrency(s, "exalted", "Exalted Orb", 146)
        SK.addCurrency(s, "chaos", "Chaos Orb", 22)
        SK.addCurrency(s, "annul", "Orb of Annulment", 3)
        SK.addItem(s, { t: t0 + 41 * MIN, name: "Ingenuity, Utility Belt", div: 0.85, how: "listings" })
        SK.addItem(s, { t: t0 + 77 * MIN, name: "Sacred Focus", div: null, how: "" })
        const list = [{ id: "divine", name: "Divine Orb", div: 1 }, { id: "annul", name: "Orb of Annulment", div: 0.06 },
                      { id: "chaos", name: "Chaos Orb", div: 0.021 }, { id: "exalted", name: "Exalted Orb", div: 1 / 410 },
                      { id: "regal", name: "Regal Orb", div: 0.0009 }]
        const byId = {}
        for (let i = 0; i < list.length; i++) byId[list[i].id] = { div: list[i].div, name: list[i].name }
        rates = { league: "Demo", at: now, exalted: 410, byId: byId, list: list }
        session = s
        const day = 24 * 60 * MIN
        const past = (startAgo, played, n, deaths) => {
            let p = SK.newSession(now - startAgo)
            p.time = { map: played * 0.72, hideout: played * 0.18, town: played * 0.04, campaign: 0, other: played * 0.06 }
            for (let i = 0; i < n; i++) p.maps.push({ name: maps[i % maps.length][1], id: maps[i % maps.length][0], level: maps[i % maps.length][2], seed: "p" + i, start: now - startAgo + i * 6 * MIN, time: played * 0.72 / n, deaths: i === 2 ? deaths : 0 })
            p.deaths = deaths
            p.last = now - startAgo + played
            return SK.finish(p, p.last)
        }
        history = [past(day + 3 * 3600000, 2.6 * 3600000, 24, 2), past(2 * day + 5 * 3600000, 1.4 * 3600000, 11, 1)]
        bump()
    }
}
