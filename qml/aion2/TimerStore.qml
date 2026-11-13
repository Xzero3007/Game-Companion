import QtQuick
import GameCompanion
import "timekit.js" as TK

// The Schedule's memory and its alerts (shared inside the AION 2 package):
// the field bosses of every map the game told about (opening the map in the
// game), per server, and the person's alert choices; kept in
// aion2-timers.json beside settings.json. One single-shot timer waits for
// the next alert: nothing ticks while nothing is due.
QtObject {
    id: store

    /// The characters store: who plays, so whose server and side.
    property var characters
    /// { servers: { id: { maps: { mapId: {seen, bosses} } } } }
    property var state: ({ servers: {} })
    property var prefs: defaults()
    /// Raised on every change (bindings follow it; `state` changes in place).
    property int revision: 0
    readonly property bool demo: nativeWindow.demo.split(",").indexOf("schedule") >= 0

    function defaults() {
        return { on: {}, lead: 5, atStart: false, banner: true, sound: "chime", volume: 70, voice: false,
            closed: false, region: "auto", lastServer: 0, game: true, fixed: true, a2t: false }
    }

    // ---- whose server ----
    readonly property int serverId: {
        const c = characters
        const ch = c && c.current ? c.state.chars[c.current] : null
        return ch && ch.serverId ? ch.serverId : (prefs.lastServer || 0)
    }
    onServerIdChanged: {
        if (serverId && serverId !== prefs.lastServer && !demo) change({ lastServer: serverId })
        else plan()
    }
    readonly property int region: prefs.region !== "auto" ? Number(prefs.region) : TK.regionOf(serverId)
    readonly property string side: TK.sideOf(serverId)
    function serverName() { return characters && serverId ? characters.serverName(serverId) : "" }

    function change(p) {
        prefs = Object.assign({}, prefs, p)
        save()
        plan()
    }
    function toggleAlert(id) {
        const on = Object.assign({}, prefs.on)
        if (on[id]) delete on[id]; else on[id] = true
        change({ on: on })
    }

    // ---- the bosses the game told ----
    function kept() {
        const s = state.servers[String(serverId)]
        return s ? s.maps : {}
    }
    function take(json) {
        let maps = []
        try { maps = JSON.parse(json) } catch (e) { return }
        if (!serverId || !prefs.game) return
        const key = String(serverId)
        const s = state.servers[key] || (state.servers[key] = { maps: {} })
        let changed = false
        for (const m of maps) changed = TK.takeMap(s.maps, m) || changed
        if (!changed) return
        if (s.a2t) TK.learn(s.links || (s.links = {}), s.maps, s.a2t.kills)
        revision++
        save()
        plan()
    }
    /// Forgets what the game told of this server's bosses.
    function forget() {
        delete state.servers[String(serverId)]
        revision++
        save()
        plan()
    }

    // ---- Aion 2 Timers (off until switched on) ----
    /// The Schedule is open: its feed is read every 5 minutes, else every 15
    /// while an alert waits on a boss.
    property bool panelShown: false
    property bool feedBusy: false
    property string feedProblem: ""
    function serverSlug() {
        const r = TK.REGIONS[region]
        const name = serverName().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        return r && name ? r.slug + "-" + name : ""
    }
    function feed() { const s = state.servers[String(serverId)]; return s && s.a2t ? s.a2t : null }
    function refreshFeed(force) {
        if (!prefs.a2t || feedBusy || demo) return
        const slug = serverSlug()
        if (!slug) { feedProblem = "your server isn't known yet: play a character once"; return }
        const f = feed()
        if (!force && f && Date.now() - f.at < 4.5 * 60000) return
        feedBusy = true
        feedFor = String(serverId)
        Aion2.timersGet(slug)
    }
    property string feedFor: ""
    property Connections feedWatch: Connections {
        target: Aion2
        function onTimersGot(ok, body) {
            store.feedBusy = false
            if (!ok) { store.feedProblem = body; return }
            let f = null
            try { f = JSON.parse(body) } catch (e) { store.feedProblem = "the answer is not the feed"; return }
            store.feedProblem = ""
            const s = store.state.servers[store.feedFor] || (store.state.servers[store.feedFor] = { maps: {} })
            s.a2t = { at: Date.now(), kills: f.kills || {} }
            s.links = s.links || {}
            TK.learn(s.links, s.maps, s.a2t.kills)
            store.revision++
            store.save()
            store.plan()
        }
    }
    readonly property bool bossAlertOn: { for (const id in prefs.on) if (TK.bossInfo(id)) return true; return false }
    property Timer feedTimer: Timer {
        interval: store.panelShown ? 5 * 60000 : 15 * 60000
        repeat: true
        triggeredOnStart: true
        running: store.prefs.a2t && !store.demo && (store.panelShown || (store.listening && store.bossAlertOn))
        onTriggered: store.refreshFeed(false)
    }

    function eventRows(now) { return prefs.fixed ? TK.events(region, side, now) : TK.events(0, side, now).filter((r) => r.kind === "reset") }
    function bossRows(now) {
        revision
        const s = state.servers[String(serverId)]
        return TK.bosses(kept(), now, prefs.a2t && s ? s.a2t : null, s ? s.links : null)
    }

    // ---- alerts ----
    /// An alert went off: the banner shows it.
    signal alerted(string name, string where, real start)
    property var next: null
    property real after: 0
    readonly property bool listening: demo || prefs.closed || Aion2.active
    onListeningChanged: plan()

    function plan() {
        const now = Date.now()
        const from = Math.max(after, now - 1000)
        next = listening && Object.keys(prefs.on).length ? TK.nextAlert(eventRows(now), bossRows(now), prefs.on, prefs.lead, prefs.atStart, from) : null
        alarm.stop()
        if (!next) return
        alarm.interval = Math.max(500, Math.min(next.at - now, 6 * 3600000))
        alarm.start()
    }
    function fire(a) {
        if (prefs.banner) alerted(a.name, a.where, a.start)
        if (prefs.sound !== "none") Aion2.chime(prefs.sound, prefs.volume)
        if (prefs.voice) {
            const left = Math.round((a.start - Date.now()) / 60000)
            Aion2.speak(a.name + (left > 0 ? " in " + left + (left === 1 ? " minute" : " minutes") : " now"))
        }
    }
    property Timer alarm: Timer {
        onTriggered: {
            const a = store.next
            // A long wait is cut in parts (a sleeping computer); only a due alert goes off.
            if (a && Date.now() >= a.at - 1000) {
                store.after = a.at
                store.fire(a)
            }
            store.plan()
        }
    }

    // ---- kept on disk ----
    function save() { if (!demo) saveTimer.restart() }
    property Timer saveTimer: Timer {
        interval: 400
        onTriggered: Aion2.keepStore("timers", JSON.stringify({ state: store.state, prefs: store.prefs }))
    }
    property Connections watch: Connections {
        target: Aion2
        function onBossMapsChanged() { if (!store.demo) store.take(Aion2.bossMaps) }
    }

    Component.onCompleted: {
        if (demo) { demoState(); plan(); return }
        try {
            const s = JSON.parse(Aion2.loadStore("timers") || "{}")
            if (s.state && s.state.servers) state = s.state
            if (s.prefs) prefs = Object.assign(defaults(), s.prefs)
        } catch (e) { }
        revision++
        plan()
    }

    // GC_DEMO=schedule: made-up bosses on Verteron for screenshots (an
    // Elyos character on a European server).
    function demoState() {
        const now = Date.now()
        const m = 60000
        const s = { servers: {} }
        s.servers["1301"] = { maps: { "1010": { seen: now - 6 * m, bosses: [
            { id: 101003, up: true, time: now - 21 * m }, { id: 101006, up: false, time: now + 12 * m },
            { id: 101002, up: false, time: now + 108 * m }, { id: 101001, up: false, time: now - 4 * m },
            { id: 101008, up: false, time: now + 47 * m }, { id: 101012, up: false, time: now + 3 * 60 * m + 20 * m }] } } }
        state = s
        prefs = Object.assign(defaults(), { lastServer: 1301, on: { "101006": true, "101003": true, "festival-elyos": true, "artifact": true } })
        revision++
    }
}
