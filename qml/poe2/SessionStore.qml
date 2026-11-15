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
    function viewOf(s, now) { return SK.view(s, now) }

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
