import QtQuick
import GameCompanion
import "bossdata.js" as BD
import "bossnotes.js" as BN
import "callouts.js" as CL
import "bossstarters.js" as BS

// The AION 2 module's Boss area (Boss Notes and Boss Callouts in one; canvas
// page "Boss (Kampf)", MN 2026-11-13): hears what bosses do (Aion2.bossHeard,
// at once) and who is fought (Aion2.combat), and runs both old plugins'
// rules on it. Callouts: the game's own calls (its lines, the checked
// mechanics) spoken and shown big. Notes: your sheets per boss (phases and
// alerts), every boss fight recorded. Lives as long as the app; timers run
// only while a fight or a call goes on. Kept in aion2-boss*.json.
QtObject {
    id: brain

    readonly property var bossData: BD.D
    readonly property var dungeons: BS.dungeons
    readonly property var demo: nativeWindow.demo.split(",")

    // ---- choices (VOICE tab) ----
    property var prefs: ({
        enabled: true, style: "both", widget: true, speakMine: true, waves: {}, offBoss: {}, offCall: {}, custom: {},
        volume: 70, rate: 1.0, colours: "game", size: 56, ground: 0.8,
        overlay: true, showNext: true, showNotes: true, keep: false, inDungeon: true, keepFights: 10,
        callX: -1, callY: -1, sheetX: -1, sheetY: -1, roles: {}
    })
    function change(key, value) {
        const p = Object.assign({}, prefs)
        p[key] = value
        prefs = p
        prefsTimer.restart()
    }
    /// One key of an object pref (offCall, custom, roles ...).
    function changeIn(key, sub, value) {
        const o = Object.assign({}, prefs[key] || {})
        if (value === undefined || value === null || value === "") delete o[sub]; else o[sub] = value
        change(key, o)
    }
    property Timer prefsTimer: Timer { interval: 400; onTriggered: Aion2.keepStore("boss", JSON.stringify(brain.prefs)) }

    // ---- sheets: yours, else a dungeon's starter ----
    property var own: ({})
    property int sheetsRevision: 0
    function sheet(key) {
        sheetsRevision
        return own[key] || BS.sheets[key] || null
    }
    function isStarter(key) { return !own[key] && !!BS.sheets[key] }
    function keepSheet(key, s) {
        const o = Object.assign({}, own)
        if (s) o[key] = s; else delete o[key]
        own = o
        sheetsRevision++
        sheetsTimer.restart()
    }
    /// A sheet to change: yours (a starter becomes yours on the first change).
    function editable(key) {
        const s = sheet(key) || { notes: "", entries: [] }
        return JSON.parse(JSON.stringify(s))
    }
    function addEntry(key, entry) {
        const s = editable(key)
        entry.id = entry.id || ("e" + Date.now().toString(36) + Math.floor(Math.random() * 1000))
        s.entries.push(entry)
        keepSheet(key, s)
        return entry.id
    }
    function changeEntry(key, id, patch) {
        const s = editable(key)
        s.entries = s.entries.map((e) => e.id === id ? Object.assign(e, patch) : e)
        keepSheet(key, s)
    }
    function removeEntry(key, id) {
        const s = editable(key)
        s.entries = s.entries.filter((e) => e.id !== id)
        keepSheet(key, s)
    }
    function moveEntry(key, id, by) {
        const s = editable(key)
        const i = s.entries.findIndex((e) => e.id === id)
        const j = i + by
        if (i < 0 || j < 0 || j >= s.entries.length) return
        const e = s.entries.splice(i, 1)[0]
        s.entries.splice(j, 0, e)
        keepSheet(key, s)
    }
    function setNotes(key, text) {
        const s = editable(key)
        s.notes = text
        keepSheet(key, s)
    }
    function resetSheet(key) { keepSheet(key, null) }
    function allEntries() {
        const out = []
        for (const k in own) for (const e of own[k].entries || []) out.push(e)
        for (const k in BS.sheets) if (!own[k]) for (const e of BS.sheets[k].entries) out.push(e)
        return out
    }
    property Timer sheetsTimer: Timer { interval: 600; onTriggered: Aion2.keepStore("boss-sheets", JSON.stringify(brain.own)) }

    /// Copy all sheets: as text (JSON), for the clipboard.
    function exportSheets() { return JSON.stringify({ bossNotes: 1, sheets: own }) }
    /// Paste sheets: adds or replaces those given; how many.
    function importSheets(text) {
        let got = null
        try { got = JSON.parse(String(text).trim()) } catch (e) { return 0 }
        const sheets = got && got.sheets ? got.sheets : got
        if (!sheets || typeof sheets !== "object") return 0
        const o = Object.assign({}, own)
        let n = 0
        for (const k in sheets) {
            const s = sheets[k]
            if (!s || !Array.isArray(s.entries) || String(k).length > 80) continue
            o[k] = { notes: String(s.notes || "").slice(0, 4000), entries: s.entries.filter((e) => e && e.when && e.name).slice(0, 80) }
            n++
        }
        own = o
        sheetsRevision++
        sheetsTimer.restart()
        return n
    }

    // ---- recorded fights ----
    property var fights: []
    function keepFight(record) {
        const list = [record].concat(fights.filter((f) => f.id !== record.id))
        fights = list.slice(0, Math.max(5, Math.min(20, prefs.keepFights || 10)))
        fightsTimer.restart()
    }
    function removeFight(id) {
        fights = fights.filter((f) => f.id !== id)
        fightsTimer.restart()
    }
    property Timer fightsTimer: Timer { interval: 800; onTriggered: Aion2.keepStore("boss-fights", JSON.stringify(brain.fights)) }

    // ---- names ----
    function lang() { return "en" }
    function txt(i) {
        if (i === null || i === undefined) return ""
        const t = bossData.texts[i]
        return (t && (t[lang()] || t.en)) || ""
    }
    function bossName(key) {
        const b = bossData.bosses[key]
        if (b) return txt(b.n)
        for (const id in BS.dungeons) for (const x of BS.dungeons[id].bosses) if (x.key === key) return x.name
        const f = fights.find((r) => r.key === key)
        return f ? f.name : key
    }
    /// The bosses by dungeon, as the data has them, plus the cheat sheets'.
    readonly property var groups: {
        const out = []
        const seen = {}
        for (const id in BS.dungeons) {
            const d = BS.dungeons[id]
            const keys = d.bosses.map((b) => b.key)
            for (const b in bossData.bosses) if (BS.dungeonOf(b) === id && keys.indexOf(b) < 0) keys.push(b)
            out.push({ id: "c:" + id, name: d.name, bosses: keys })
            for (const k of keys) seen[k] = true
        }
        for (const g in bossData.groups) {
            const keys = []
            for (const b in bossData.bosses) if (bossData.bosses[b].g === g && !seen[b]) keys.push(b)
            if (keys.length) out.push({ id: g, name: txt(bossData.groups[g].n), bosses: keys })
        }
        return out
    }
    /// The game's calls of a boss.
    function callsOf(key) { return bossData.calls.filter((c) => c.b === key) }
    /// What a call shows: its short call (or line) and its trigger in words.
    function callText(c) {
        const act = txt(c.act), line = txt(c.line), buff = c.t === "abnormal" ? txt(c.n) : ""
        return { act: act, line: line || buff, own: String((prefs.custom || {})[c.k] || ""),
            trigger: c.t === "cast" ? "Cast" + (c.lead ? ", " + (c.lead / 1000).toFixed(1) + " s" : "") : c.t === "use" ? "Skill" : "Buff on the boss",
            phase: c.phase ? txt(c.phase.label) + " · " + Math.round(c.phase.ms / 1000) + " s · Safe" : "" }
    }
    /// The game's line for a trigger, if it has one.
    function lineOf(type, id) { return notes ? notes.lineOf(type, id, lang()) : "" }
    function describe(when) { return BN.describe(when, when ? lineOf(when.type, when.value) : "") }

    // ---- the voice ----
    function say(words, priority, own) {
        if (prefs.enabled === false || !words) return
        Aion2.say(words, priority !== "low", !!own, prefs.volume, prefs.rate)
    }

    // ---- the rules ----
    property var later: []
    property var callItems: []
    property var notes: null
    property var calls: null
    property var noteState: ({ fight: null })
    property bool fighting: false

    function now() { return Date.now() }
    function start() {
        notes = BN.create(bossData, {
            now: now,
            sheet: (key) => brain.sheet(key),
            allEntries: () => brain.allEntries(),
            done: (record) => { if (record.events.length > 1 || record.end - record.start > 15000) brain.keepFight(record) },
            changed: () => {}
        })
        calls = CL.create(bossData, {
            now: now,
            prefs: () => brain.prefs,
            lang: lang,
            say: (w, p) => { if (!brain.isOwn(w)) brain.say(w, p, false); else brain.say(w, p, true) },
            show: (items) => { brain.callItems = items.slice(); brain.wake() },
            beep: () => { if (prefs.enabled !== false) Aion2.beep(prefs.volume) },
            later: (fn, ms) => { brain.later = brain.later.concat([{ at: Date.now() + ms, fn: fn }]); brain.wake() }
        })
    }
    /// The person's own words for a call: said by the computer's voice.
    function isOwn(words) {
        const c = prefs.custom || {}
        for (const k in c) if (c[k] === words) return true
        return false
    }

    /// What bosses did (Aion2.bossHeard).
    function hear(events) {
        if (!notes) return
        for (const d of events) {
            const at = d.at || now()
            if (d.t === "cast") { notes.cast(d, at); calls.cast(d, at) }
            else if (d.t === "use") { notes.skill(d, at); calls.use(d, at) }
            else if (d.t === "wave") calls.wave(d, at)
            else if (d.t === "added") { notes.added(d, at); calls.added(d, at) }
            else if (d.t === "removed") { notes.removed(d, at); calls.removed(d, at) }
        }
        refresh()
    }
    /// Who is fought (Aion2.combat).
    property var combat: ({ fought: [], dungeon: 0 })
    function fought(c) {
        combat = c
        if (!notes) return
        notes.combat({ at: now(), fought: (c.fought || []).map((f) => ({ entity: f.entity, npc: f.npc, name: f.name, boss: f.boss,
            hp: f.hp, maxHp: f.maxHp, since: f.since })) })
        refresh()
    }

    /// The fight's state again; your phases and alerts spoken as they come.
    property var spoken: ({})
    function refresh() {
        if (!notes) return
        const s = notes.state(lang())
        if (prefs.speakMine !== false && s.fight) {
            const heard = Object.assign({}, spoken)
            if (s.phase && !heard["p:" + s.phase.id + ":" + s.fight.key]) { say(s.phase.name, "high", true); heard["p:" + s.phase.id + ":" + s.fight.key] = true }
            for (const a of s.alerts) {
                const k = "a:" + a.id + ":" + Math.round((Date.now() + a.left) / 1000)
                if (!heard["a:" + a.id] || heard["a:" + a.id] !== k) { if (!heard["a:" + a.id]) say(a.name, "high", true); heard["a:" + a.id] = k }
            }
            for (const k in heard) if (k.indexOf("a:") === 0 && !s.alerts.some((a) => "a:" + a.id === k)) delete heard[k]
            spoken = heard
        }
        if (!s.fight) spoken = ({})
        noteState = s
        fighting = !!s.fight
        if (s.fight) lastKey = s.fight.key
    }
    /// The last boss fought (shown between fights with "keep it up").
    property string lastKey: ""

    property Timer ticker: Timer {
        interval: 100
        repeat: true
        running: brain.callItems.length > 0 || brain.later.length > 0 || brain.fighting
        onTriggered: brain.tick()
    }
    property int ticks: 0
    function wake() { if (!ticker.running) ticker.start() }
    function tick() {
        const t = now()
        if (later.length) {
            const due = later.filter((l) => l.at <= t)
            if (due.length) {
                later = later.filter((l) => l.at > t)
                for (const l of due) l.fn()
            }
        }
        if (calls) calls.tick()
        // The notes' countdowns: four times a second is enough.
        if (++ticks % 3 === 0 && fighting) refresh()
    }

    // ---- where you are ----
    /// The dungeon with a cheat sheet you are in ("" none): the game's word,
    /// a boss fought there, or its monsters around you.
    readonly property string dungeon: {
        const c = combat
        if (c && c.dungeon && BS.dungeons[String(c.dungeon)]) return String(c.dungeon)
        for (const f of (c && c.fought) || []) if (f.dungeon && BS.dungeons[String(f.dungeon)]) return String(f.dungeon)
        let w = null
        try { w = JSON.parse(Aion2.world) } catch (e) { }
        for (const id in BS.dungeons) {
            const want = BS.dungeons[id].npcs
            for (const n of (w && w.npcs) || []) if (want.indexOf(n[1]) >= 0) return id
        }
        return demo.indexOf("ludra") >= 0 ? "600082" : ""
    }
    /// The cheat sheet shown by hand, outside its dungeon (SHEETS → "Show
    /// over game", MN 2026-11-13: "how can I see the Ludra things?"). Not
    /// kept: it ends with the app or "Close".
    property string previewDungeon: ""
    /// The entry played last in the preview (shown as the phase you are in).
    property string previewPhase: ""
    /// The boss tab the preview shows.
    property string previewKey: ""
    readonly property string shownDungeon: previewDungeon || dungeon
    function startPreview(dungeonId, key) { previewPhase = ""; previewKey = key || ""; previewDungeon = dungeonId }
    function stopPreview() {
        previewDungeon = ""; previewPhase = ""
        if (callItems.length && callItems[0].key === "sheet") callItems = []
        Aion2.hush()
    }
    /// A sheet entry as the fight would bring it: the big call and its words.
    function playEntry(key, e) {
        previewPhase = e.id
        if (previewDungeon) previewKey = key
        const at = now()
        const item = { key: "sheet", kind: "call", text: e.name, sub: bossName(key) + (e.role ? " · " + e.role : ""), start: at, end: at + 6000, until: at + 6000 }
        callItems = [item]
        sheetCall.restart()
        say(e.name + (e.text ? ". " + e.text : ""), "high", true)
    }
    property Timer sheetCall: Timer {
        interval: 6000
        onTriggered: if (brain.callItems.length && brain.callItems[0].key === "sheet") brain.callItems = []
    }
    function myRoles(dungeonId) { return ((prefs.roles || {})[dungeonId] || []) }
    function toggleRole(dungeonId, role) {
        const mine = myRoles(dungeonId).slice()
        const i = mine.indexOf(role)
        if (i >= 0) mine.splice(i, 1); else mine.push(role)
        changeIn("roles", dungeonId, mine)
    }

    property Connections listen: Connections {
        target: Aion2
        function onBossHeard(json) { try { brain.hear(JSON.parse(json)) } catch (e) { } }
        function onCombatChanged() { try { brain.fought(JSON.parse(Aion2.combat)) } catch (e) { } }
        function onActiveChanged() { if (!Aion2.active && brain.calls) { brain.calls.clear(); Aion2.hush() } }
    }

    /// The test: a made-up purple phase (Thamon's), then "Safe".
    function test() { if (calls) calls.test() }
    function preview(k) { if (calls) calls.preview(k) }

    Component.onCompleted: {
        try { prefs = Object.assign({}, prefs, JSON.parse(Aion2.loadStore("boss") || "{}")) } catch (e) { }
        try { own = JSON.parse(Aion2.loadStore("boss-sheets") || "{}") || {} } catch (e) { }
        try { fights = JSON.parse(Aion2.loadStore("boss-fights") || "[]") || [] } catch (e) { }
        start()
        if (demo.indexOf("bossfight") >= 0 || demo.indexOf("ludra") >= 0) Qt.callLater(demoFight)
        // GC_DEMO=boss,sheets,preview: the Ludra sheet shown by hand, "Grid" played.
        if (demo.indexOf("preview") >= 0) Qt.callLater(() => { brain.startPreview("600082", "eternal-ludra"); brain.playEntry("eternal-ludra", brain.sheet("eternal-ludra").entries[1]) })
    }

    // GC_DEMO=boss,bossfight: Thamon at 62 % with a sheet, the purple call
    // up; ,ludra: in Ludra fighting Eternal Ludra. Nothing is kept.
    function demoFight() {
        prefsTimer.interval = 1e9; sheetsTimer.interval = 1e9; fightsTimer.interval = 1e9
        const t = now()
        if (demo.indexOf("ludra") >= 0) {
            prefs = Object.assign({}, prefs, { roles: { "600082": ["Party 2"] } })
            fought({ fought: [{ entity: 9, npc: 2301014, name: "Eternal Ludra", boss: true, hp: 7100, maxHp: 10000, since: t - 108000, dungeon: 600082 }], dungeon: 600082 })
            return
        }
        own = { thamon: { notes: "Stand behind the boss, never in front of it.", entries: [
            { id: "d1", kind: "phase", name: "Opening", role: "", when: { type: "start" }, text: "Tank turns him away from the group." },
            { id: "d2", kind: "phase", name: "Colours", role: "", when: { type: "hp", value: 70 }, text: "Purple: stop magic. Red: stop physical. Healers top up before each." },
            { id: "d3", kind: "alert", name: "Adds spawn: tank picks them up", role: "", when: { type: "time", value: 100 }, ms: 12000, text: "" },
            { id: "d4", kind: "phase", name: "Burn", role: "", when: { type: "hp", value: 30 }, text: "All cooldowns." }] } }
        sheetsRevision++
        fought({ fought: [{ entity: 5, npc: 2300581, name: "Thamon", boss: true, hp: 620, maxHp: 1000, since: t - 108000 }], dungeon: 0 })
        hear([{ t: "cast", caster: 5, skill: 1604670, at: t }])
        fights = [{ id: "demo", key: "thamon", name: "Thamon", npc: 2300581, start: t - 600000, end: t - 408000, hp: 0, low: 0,
            events: [[0, "s", 1604610, 0], [41000, "h", 78, 0], [41000, "c", 1604670, 0], [43000, "b", 16046701, 10000], [80000, "h", 64, 0],
                [80000, "c", 1604660, 0], [95000, "b", 16046601, 10000], [168000, "h", 18, 0], [192000, "h", 0, 0]] }]
    }
}
