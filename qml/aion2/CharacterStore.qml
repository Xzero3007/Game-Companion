import QtQuick
import GameCompanion
import "charkit.js" as CK

// The characters store (shared inside the AION 2 package): every character
// the game showed, once, with what it last said of them (CK.merge). Lives as
// long as the app, so it learns while the Characters panel is closed; kept in
// aion2-characters.json beside settings.json. Other areas read `state`.
QtObject {
    id: store

    /// { chars: { "name@server": {...} }, servers: { id: {...} } }
    property var state: CK.empty()
    /// Raised on every change (bindings follow it, `state` is changed in place).
    property int revision: 0
    /// The key of who plays now ("" when nobody or the game isn't running).
    property string current: ""
    /// Server names by number (the meter's list).
    readonly property var serverNames: { try { return JSON.parse(Aion2.serverNames()) } catch (e) { return {} } }
    readonly property bool demo: nativeWindow.demo.split(",").indexOf("chars") >= 0

    function serverName(id) { return serverNames[String(id)] || (id ? "Server " + id : "") }
    function save() { if (!demo) saveTimer.restart() }
    function changed() { revision++; save() }

    /// Takes a character out (it comes back when played).
    function remove(key) {
        if (!state.chars[key]) return
        delete state.chars[key]
        changed()
    }
    /// A click on a cap: 840 ↔ 560, the player's word until the game says more.
    function toggleCap(key) {
        const ch = state.chars[key]
        if (!ch) return
        ch.cap = CK.capFor(state, ch, Date.now()) === CK.CAPS[0] ? CK.CAPS[1] : CK.CAPS[0]
        ch.capSet = true
        changed()
    }

    function take(json) {
        let c = null
        try { c = JSON.parse(json) } catch (e) { return }
        const now = Date.now()
        const key = CK.merge(state, c, now)
        if (!key) return
        const ch = state.chars[key]
        // Seen now: refreshed at most every 5 minutes, so an event alone writes little.
        if (key !== current || now - (ch.seen || 0) > 300000) ch.seen = now
        current = key
        changed()
    }

    property Connections watch: Connections {
        target: Aion2
        function onCharacterChanged() { if (!store.demo) store.take(Aion2.character) }
        function onActiveChanged() {
            if (Aion2.active || !store.current) return
            const ch = store.state.chars[store.current]
            if (ch) ch.seen = Date.now()
            store.current = ""
            store.changed()
        }
    }
    property Timer saveTimer: Timer {
        interval: 400
        onTriggered: Aion2.keepStore("characters", JSON.stringify(store.state))
    }

    Component.onCompleted: {
        if (demo) { state = demoState(); current = "[Character 2]@2004"; revision++; return }
        try {
            const s = JSON.parse(Aion2.loadStore("characters") || "{}")
            if (s && s.chars && s.servers) state = s
        } catch (e) { }
        revision++
    }

    // GC_DEMO=chars: made-up characters for screenshots.
    function demoState() {
        const now = Date.now()
        const h = 3600000
        const s = CK.empty()
        const add = (name, server, cls, lv, cp, gs, basic, charged, seenAgo, extra) => {
            const ch = { name: name, serverId: server, "class": cls, level: lv, cp: cp, gs: gs, cap: 840,
                energy: { basic: basic, charged: charged, at: now - seenAgo }, seen: now - seenAgo, memberAt: now - h }
            Object.assign(ch, extra || {})
            s.chars[name + "@" + server] = ch
        }
        add("[Character 1]", 2004, "Cleric", 45, 41210, 3120, 840, 0, 50 * h)
        add("[Character 2]", 2004, "Ranger", 45, 52880, 3405, 610, 120, 0, {
            counts: { "4": { v: [12, 2], at: now - h }, "80000001": { v: [3, 0], at: now - h }, "0": { v: [3, 5], at: now - h },
                "abyss:corridors": { v: [1, 0], at: now - h, cap: 2, reset: now + 70 * h },
                "kinah:today": { v: [640000, 0], at: now - h }, "abyss:week": { v: [812400, 0], at: now - h, cap: 2000000 },
                "craft:32070002": { v: [4, 0], at: now - 2 * h }, "shop:1209": { v: [2, 0], at: now - 2 * h, reset: now + 50 * h } },
            tickets: { "102": { v: [5, 0], at: now - 2 * h }, "60000003": { v: [9, 0], at: now - 2 * h }, "70000001": { v: [1, 0], at: now - 2 * h } },
            times: { "3": { v: 2 * h + 600000, at: now - h } }
        })
        add("[Character 3]", 2004, "Templar", 45, 38740, 2980, 600, 0, 20 * h, {
            counts: { "4": { v: [6, 0], at: now - 20 * h }, "80000001": { v: [3, 0], at: now - 20 * h }, "abyss:corridors": { v: [0, 0], at: now - 20 * h, cap: 2, guess: true } } })
        add("[Character 4]", 2011, "Sorcerer", 42, 30115, 2610, 420, 0, 72 * h)
        add("[Character 5]", 2011, "Chanter", 38, 22460, 2240, 390, 40, 120 * h)
        add("[Character 6]", 2004, "Assassin", 40, 27390, 2455, 280, 0, 6 * h, { counts: { "4": { v: [5, 0], at: now - 6 * h } } })
        s.servers["2004"] = { counts: { "1": { v: [15, 0], at: now - 3 * h }, "8": { v: [4, 0], at: now - 2 * h }, "101": { v: [9, 0], at: now - 3 * h },
            "craft:32070001": { v: [9, 0], at: now - 2 * h }, "shop:1210": { v: [6, 0], at: now - 2 * h, reset: now + 50 * h } },
            siege: { holders: { "1001": "asmodian", "1002": "elyos", "1003": "asmodian" }, next: now + 70 * h, at: now - h } }
        return s
    }
}
