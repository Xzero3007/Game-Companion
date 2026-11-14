import QtQuick
import GameCompanion
import "armorykit.js" as AK
import "buildkit.js" as BK

// The Armory's memory (lives as long as the app, in Main.qml): the builds
// and which characters they are on (aion2-armory.json), each character's
// last reading of NC's character pages and its history (aion2-armory-s-
// and -h-<hash>.json). The character you play is read by itself when its
// last reading is older than 6 hours (the old Armory's rule), and the
// game's own combat power and gear score go into its history as they
// change. Nothing is read from NC while AION 2 is closed unless asked
// (Update, Look up). The data (1 MB, the game's tables) is loaded the first
// time it is needed.
QtObject {
    id: store

    readonly property var demoList: nativeWindow.demo.split(",")
    readonly property bool demo: demoList.indexOf("armory") >= 0
    readonly property int autoEvery: 6 * 3600 * 1000
    /// History entries kept per character (the old Armory kept 300; its
    /// history taken over comes on top of this one's).
    readonly property int keep: 600

    /// The plugin's calc (AK.C) once the data is loaded.
    property bool ready: false
    /// The Armory is switched on (Settings → Plugins): only then is a
    /// played character read from NC's pages by itself.
    property bool on: true
    function ensure() {
        if (ready) return true
        let data = null
        try { data = JSON.parse(Aion2.armoryData() || "{}") } catch (e) { data = null }
        if (!data || !data.items) { error = "The Armory's tables are missing (armory/data.json)"; return false }
        AK.load(data)
        ready = true
        return true
    }

    /// BK.emptyState(): builds, chars, order, settings.
    property var state: BK.emptyState()
    /// Raised on every change (bindings follow it; state is changed in place).
    property int revision: 0
    /// The character shown ("name@server"), its reading and history.
    property string current: ""
    property var snap: null
    property var history: []
    /// Who plays now: { key, name, serverId, cp, gs } or null.
    property var playing: null
    property bool loading: false
    property string status: ""
    property string error: ""
    /// Prices (Main's PriceBook): Amplify Stones and the like in Kinah.
    property var book: null
    readonly property var prices: book && book.prices && book.prices.size ? book.prices : null
    /// The DPS history's fights (Aion2.history), for HISTORY.
    readonly property var fights: { try { return JSON.parse(Aion2.history) } catch (e) { return [] } }

    // ---- files ----
    function hash(key) {
        let h = 0x811c9dc5
        for (let i = 0; i < key.length; i++) { h ^= key.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0 }
        return ("0000000" + h.toString(16)).slice(-8)
    }
    function save() { if (!demo) saveTimer.restart() }
    function changed() { revision++; save() }
    property Timer saveTimer: Timer { interval: 400; onTriggered: Aion2.keepStore("armory", JSON.stringify(store.state)) }
    function keepSnap(key, s) { if (!demo) Aion2.keepStore("armory-s-" + hash(key), JSON.stringify(s)) }
    function keepHistory(key, h) { if (!demo) Aion2.keepStore("armory-h-" + hash(key), JSON.stringify(h)) }
    function loadSnap(key) { try { return JSON.parse(Aion2.loadStore("armory-s-" + hash(key)) || "null") } catch (e) { return null } }
    function loadHistory(key) { try { const h = JSON.parse(Aion2.loadStore("armory-h-" + hash(key)) || "[]"); return Array.isArray(h) ? h : [] } catch (e) { return [] } }

    // ---- who ----
    function keyOf(name, serverId) { return name + "@" + Number(serverId) }
    function charInfo(key) { return state.chars[key] || null }
    function build() { revision; return current ? BK.activeBuild(state, current) : null }
    function targets() { revision; return BK.targetsOf(build(), state.chars[current]) }

    function open(key) {
        if (!key) return
        current = key
        state.settings.current = key
        snap = loadSnap(key)
        history = loadHistory(key)
        save()
        revision++
        if (snap) status = "Read " + when(snap.at)
        if (book && snap && snap.profile) book.gameServer = snap.profile.serverId
    }

    function when(ms) {
        if (!ms) return "—"
        const d = new Date(ms)
        const two = (n) => (n < 10 ? "0" : "") + n
        return two(d.getDate()) + "." + two(d.getMonth() + 1) + "., " + two(d.getHours()) + ":" + two(d.getMinutes())
    }

    // ---- NC's pages, through Aion2.webGet (armory::allowed) ----
    property int nextId: 950000
    property var waiting: ({})
    function get(url) {
        return new Promise((resolve, reject) => {
            const id = nextId++
            waiting[id] = { resolve: resolve, reject: reject }
            Aion2.webGet(id, url)
        })
    }
    property Connections answers: Connections {
        target: Aion2
        function onWebGot(id, ok, body) {
            const w = store.waiting[id]
            if (!w) return
            delete store.waiting[id]
            if (!ok) { w.reject(new Error(body)); return }
            try { w.resolve(JSON.parse(body)) } catch (e) { w.reject(new Error("NC's page answered no JSON")) }
        }
    }

    /// Reads a character from NC's pages (the old Armory's loadCharacter):
    /// its info, gear piece by piece and Daevanion boards, one request at a
    /// time. The active build's steps before and after: the ones gone are
    /// ticked. (Promises, not async: Qt 6.4's QML has no async functions.)
    function read(target) {
        if (loading || !target || !target.name || !target.serverId || !ensure()) return
        loading = true
        error = ""
        const ref = { serverId: Number(target.serverId), characterId: target.characterId || null }
        let info = null, equipment = null
        const items = [], boards = []
        const quiet = (p) => p.then((x) => x, () => null)
        const each = (list, f) => list.reduce((p, x, i) => p.then(() => f(x, i)), Promise.resolve())
        let first = Promise.resolve()
        if (!ref.characterId) {
            status = "Looking up " + target.name + " …"
            first = get(AK.NC.searchUrl(target.name, target.serverId)).then((res) => {
                const found = AK.NC.readSearch(res, target.name, target.serverId)
                if (!found) throw new Error(target.name + " isn't on NC's character pages (yet): try again after logging out once")
                ref.characterId = found.characterId
            })
        }
        first.then(() => {
            status = "Reading the character …"
            return get(AK.NC.infoUrl(ref))
        }).then((res) => {
            info = AK.NC.readInfo(res)
            if (!info) throw new Error("NC's character page gave no answer")
            return quiet(get(AK.NC.equipmentUrl(ref)))
        }).then((res) => {
            equipment = (res && AK.NC.readEquipment(res)) || { slots: [], skills: [] }
            return each(equipment.slots, (sl, i) => {
                status = "Reading the gear " + (i + 1) + "/" + equipment.slots.length + " …"
                return quiet(get(AK.NC.itemUrl(ref, sl))).then((d) => { items.push(AK.NC.readItem(d, sl)) })
            })
        }).then(() => each(info.boards, (bd, i) => {
            status = "Reading Daevanion " + (i + 1) + "/" + info.boards.length + " …"
            return quiet(get(AK.NC.boardUrl(ref, bd.id))).then((d) => {
                boards.push(d ? AK.NC.readBoard(d, bd) : Object.assign({}, bd, { points: 0, maxPoints: 0, nodes: [], unread: true }))
            })
        })).then(() => {
            const sn = AK.NC.snapshotOf({ info: info, equipment: equipment, items: items, boards: boards, at: Date.now() })
            take(sn, ref.characterId)
            status = "Read " + when(sn.at)
        }).catch((e) => {
            error = String(e && e.message ? e.message : e)
            status = ""
        }).then(() => { loading = false })
    }

    /// A new reading: kept, its history noted, the steps done ticked.
    function take(s, characterId) {
        const key = keyOf(s.profile.name, s.profile.serverId)
        const ch = BK.ensureChar(state, key, { name: s.profile.name, serverId: s.profile.serverId, characterId: characterId,
            className: s.profile.className, level: s.profile.level, serverName: s.profile.serverName })
        const old = key === current ? snap : loadSnap(key)
        const b = BK.activeBuild(state, key)
        if (b && old) BK.markDone(ch, b.id, BK.steps(old, b, ch, prices), BK.steps(s, b, ch, prices), Date.now())
        let h = key === current ? history : loadHistory(key)
        h = AK.C.addHistory(h, BK.historyEntry(s, b, ch, prices), store.keep)
        keepSnap(key, s)
        keepHistory(key, h)
        if (key === current || !current) { current = key; state.settings.current = key; snap = s; history = h }
        if (book) book.gameServer = s.profile.serverId
        changed()
    }

    /// NC's search in a region (1 NA East … 5 Asia): [{ name, serverId, serverName, level }].
    function lookUp(name, region) {
        if (!ensure()) return Promise.resolve([])
        const url = AK.NC.searchUrl(name, region * 100 + 1).replace(/&serverId=\d+/, "")
        return get(url).then((res) => AK.NC.readSearchList(res))
    }

    // ---- builds ----
    function makeBuild(name, kind, ref, source, targetsFrom) {
        if (!ensure()) return null
        const cls = snap && snap.profile ? snap.profile.className : ""
        const b = BK.newBuild(name, kind, cls, ref, source, Date.now())
        if (targetsFrom) b.targets = targetsFrom
        BK.addBuild(state, b)
        if (current) BK.assign(state, current, b.id, BK.gsOf(snap))
        changed()
        return b
    }
    function setActive(buildId) {
        if (!current) return
        BK.assign(state, current, buildId, BK.gsOf(snap))
        noteProgress()
        changed()
    }
    function putOn(key, buildId) {
        const other = key === current ? snap : loadSnap(key)
        BK.assign(state, key, buildId, BK.gsOf(other))
        changed()
    }
    function takeOff(key, buildId) { BK.unassign(state, key, buildId); changed() }
    function removeBuild(buildId) { BK.removeBuild(state, buildId); changed() }
    function renameBuild(buildId, name, kind) {
        const b = state.builds[buildId]
        if (!b) return
        if (name) b.name = name
        if (kind) b.kind = kind
        changed()
    }
    /// A change to what the active build aims at: f(targets, build) changes
    /// it in place; a new version when it changes the aim.
    function changeTargets(what, f) {
        const b = build()
        if (!b) return
        f(b.targets, b)
        BK.noteChange(b, what, Date.now())
        noteProgress()
        changed()
    }
    /// The character's own levels on a piece (Compare: yours enhanced on).
    function changeMine(f) {
        const ch = state.chars[current]
        if (!ch) return
        f(ch.mineAt)
        changed()
    }
    /// A character's active build and how far it is, for CHARACTERS:
    /// { name, p } or null; kept per revision (read from disk once).
    readonly property var progressCache: ({})
    function progressOf(key) {
        const ch = state.chars[key]
        if (!ch || !ch.active) return null
        const c = progressCache[key]
        if (c && c.rev === revision) return c.v
        const b = BK.activeBuild(state, key)
        let v = null
        if (b && ensure()) {
            const s = key === current ? snap : loadSnap(key)
            const pr = s ? BK.progress(s, b, state.chars[key], prices) : null
            v = { name: b.name, p: pr && pr.total != null ? pr.total : null }
        }
        progressCache[key] = { rev: revision, v: v }
        return v
    }
    /// The progress noted in the history when the build or its aim changes.
    function noteProgress() {
        if (!snap || !current) return
        const b = BK.activeBuild(state, current)
        const e = BK.historyEntry(Object.assign({}, snap, { at: Date.now() }), b, state.chars[current], prices)
        history = AK.C.addHistory(history, e, store.keep)
        keepHistory(current, history)
    }

    // ---- the old Clicktrough Armory's data (MN, 2026-11-14) ----
    /// What the last take-over brought, for HISTORY ("" before one).
    property string meterNote: ""
    property bool meterBusy: false
    /// Reads the meter's Armory files (local, read only): once by itself,
    /// again with HISTORY's button. Readings and history are added where
    /// this Armory lacks them; the old references become builds, and a
    /// character's old targets a build on that character if it has none.
    /// Taken parts are noted, so a second take makes no copies.
    function readMeter() {
        if (demo || meterBusy || typeof Aion2.meterReadArmory !== "function") return
        meterBusy = true
        revision++
        Aion2.meterReadArmory()
    }
    property Connections meterAnswer: Connections {
        target: Aion2
        ignoreUnknownSignals: true
        function onMeterArmoryGot(json) { store.takeMeter(json) }
    }
    function takeMeter(json) {
        meterBusy = false
        if (!ensure()) return
        let files = {}
        try { files = (JSON.parse(json) || {}).armory || {} } catch (e) { files = {} }
        const old = BK.readOld(files, keyOf)
        const taken = Object.assign({}, state.settings.meterBuilds || {})
        const n = { chars: 0, entries: 0, readings: 0, builds: 0 }
        const copy = (o) => JSON.parse(JSON.stringify(o))
        for (const c of old.chars) {
            const have = state.chars[c.key]
            const info = {}
            for (const k in c.info) if (!have || have[k] == null || have[k] === "") info[k] = c.info[k]
            const ch = BK.ensureChar(state, c.key, info)
            const ours = c.key === current ? history : loadHistory(c.key)
            const merged = BK.mergeHistory(ours, c.history, keep)
            const added = Math.max(0, merged.length - ours.length)
            if (added > 0) { keepHistory(c.key, merged); if (c.key === current) history = merged; n.entries += added }
            let s = c.key === current ? snap : loadSnap(c.key)
            const newer = c.snap && (!s || (s.at || 0) < (c.snap.at || 0))
            if (newer) { keepSnap(c.key, c.snap); if (c.key === current) snap = c.snap; s = c.snap; n.readings++ }
            if (added > 0 || newer || !have) n.chars++
            if (BK.hasTargets(c.targets) && !ch.active && !taken["t:" + c.key]) {
                const ref = old.refs[old.active] || null
                const b = BK.newBuild((ref && ref.name ? ref.name : "Old Armory") + " · " + c.info.name, "PvE", c.info.className || "",
                    ref ? copy(ref) : null, "the old Armory", Date.now())
                b.targets = BK.targetsFromOld(c.targets, old.goalGs)
                BK.addBuild(state, b)
                BK.assign(state, c.key, b.id, BK.gsOf(s))
                if (c.targets.mineAt && typeof c.targets.mineAt === "object") for (const slot in c.targets.mineAt) if (!ch.mineAt[slot]) ch.mineAt[slot] = c.targets.mineAt[slot]
                taken["t:" + c.key] = b.id
                if (ref) taken["r:" + (ref.id || ref.qid || ref.name || old.active)] = b.id
                n.builds++
            }
        }
        old.refs.forEach((r, i) => {
            const id = "r:" + (r.id || r.qid || r.name || i)
            if (taken[id]) return
            const b = BK.newBuild(r.name || "Old reference " + (i + 1), "PvE", r.className || "", copy(r), "the old Armory", Date.now())
            if (old.goalGs) b.targets.goalGs = old.goalGs
            BK.addBuild(state, b)
            taken[id] = b.id
            n.builds++
        })
        state.settings.meterBuilds = taken
        state.settings.meterTaken = true
        const parts = []
        if (n.entries) parts.push(n.entries + " history " + (n.entries === 1 ? "entry" : "entries"))
        if (n.readings) parts.push(n.readings + (n.readings === 1 ? " reading" : " readings"))
        if (n.builds) parts.push(n.builds + (n.builds === 1 ? " build" : " builds"))
        meterNote = !old.chars.length && !old.refs.length ? "No data of the old Armory found on this computer."
            : parts.length ? "Taken over from the old Armory: " + parts.join(", ") + (n.chars ? " for " + n.chars + (n.chars === 1 ? " character" : " characters") : "") + "."
            : "The old Armory's data was already taken over."
        if (current && !snap) { snap = loadSnap(current); history = loadHistory(current) }
        else if (!current && old.chars.length) open(old.chars[0].key)
        changed()
    }

    // ---- the game's own numbers, between readings ----
    property Timer liveTimer: Timer {
        interval: 5000
        onTriggered: {
            const p = store.playing
            if (!p || !(p.cp > 0) || !(p.gs > 0) || !store.ready) return
            const h = p.key === store.current ? store.history : store.loadHistory(p.key)
            let last = null
            for (let i = h.length - 1; i >= 0; i--) if (h[i] && isFinite(h[i].cp)) { last = h[i]; break }
            if (last && last.cp === p.cp && last.gs === p.gs) return
            const next = AK.C.addHistory(h, { at: Date.now(), cp: p.cp, gs: p.gs, live: true }, store.keep)
            if (p.key === store.current) store.history = next
            store.keepHistory(p.key, next)
        }
    }
    property Connections game: Connections {
        target: Aion2
        function onCharacterChanged() {
            if (store.demo || !store.on) return
            let c = null
            try { c = JSON.parse(Aion2.character) } catch (e) { return }
            if (!c || !c.name || !c.serverId) return
            const key = store.keyOf(c.name, c.serverId)
            const was = store.playing
            store.playing = { key: key, name: c.name, serverId: Number(c.serverId), cp: c.combatPower || null, gs: c.gearScore || null }
            if (!store.state.chars[key]) { BK.ensureChar(store.state, key, { name: c.name, serverId: Number(c.serverId), className: c["class"] || "" }); store.changed() }
            store.liveTimer.restart()
            if (was && was.key === key) return
            if (!store.current || store.current !== key) store.open(key)
            if (!store.snap || Date.now() - (store.snap.at || 0) > store.autoEvery) store.read(store.state.chars[key])
        }
        function onActiveChanged() { if (!Aion2.active) store.playing = null }
    }

    Component.onCompleted: {
        if (demo) { demoState(); return }
        try {
            const s = JSON.parse(Aion2.loadStore("armory") || "{}")
            if (s && s.builds && s.chars) state = Object.assign(BK.emptyState(), s, { settings: Object.assign(BK.emptyState().settings, s.settings || {}) })
        } catch (e) { }
        if (state.settings.current) {
            current = state.settings.current
            snap = loadSnap(current)
            history = loadHistory(current)
        }
        revision++
        if (!state.settings.meterTaken) readMeter()
    }

    // ---- GC_DEMO=armory: a made-up character and build for screenshots ----
    function demoState() {
        if (!ensure()) return
        const C = AK.C
        const idOf = (name, il) => { for (const k in AK.G.ARMORY_DATA.items) { const r = AK.G.ARMORY_DATA.items[k]; if (r[0] === name && (!il || r[3] === il)) return Number(k) } return 0 }
        const piece = (slot, name, il, e, a, extra) => {
            const id = idOf(name, il)
            const row = C.itemRow(id) || [name, "Legend", "", il]
            return Object.assign({ slot: slot, id: id, name: row[0], grade: row[1], il: row[3], icon: C.itemIcon(id), enchant: e, amplify: a, maxEnchant: 15, maxAmplify: 5,
                main: [], sub: [], subSkills: [], stones: [], stoneSlots: 0, theostones: [] }, extra || {})
        }
        const now = Date.now()
        const s = {
            at: now - 3 * 3600000,
            profile: { characterId: "x", name: "[Character 2]", level: 45, className: "Ranger", race: "Asmodians", serverId: 2004, serverName: "[Server A]",
                legion: "[Legion]", title: "Celebrity", cp: 52880, gs: null, portrait: null },
            stats: { STR: { name: "Might", value: 105, effects: ["Attack increase +10.5%"] }, DEX: { name: "Dexterity", value: 52, effects: [] },
                Justice: { name: "Justice [Nezekan]", value: 51, effects: [] }, Time: { name: "Time [Siel]", value: 76, effects: [] } },
            titles: { owned: 41, total: 120, list: [] }, rankings: [],
            items: [
                piece("MainHand", "Enraged Kromede Longbow", 86, 15, 2, { sub: [{ id: 1, name: "Combat Speed", value: "9.1%" }, { id: 2, name: "Attack", value: "38" }], stoneSlots: 4,
                    stones: [{ name: "Attack", value: "+12", grade: "Legend" }, { name: "Critical Hit", value: "+20", grade: "Rare" }] }),
                piece("Bracelet1", "Ascension Bracelet", 51, 10, 0),
                piece("Helmet", "", 0, 11, 0, { name: "[Helmet]", grade: "Legend", il: 80, id: 0 })
            ],
            skills: [{ id: 1, name: "Arrow Storm", category: "Active", level: 11, acquired: true, equipped: true },
                { id: 2, name: "Snipe", category: "Active", level: 14, acquired: true, equipped: true }],
            pet: null, wing: null,
            boards: [{ id: 31, name: "Nezekan", points: 3, maxPoints: 12, open: 2, total: 5, nodes: [
                { id: 1, type: "Start", grade: "Common", open: true, row: 0, col: 0, effects: [] },
                { id: 2, type: "Stat", grade: "Legend", open: true, row: 0, col: 1, effects: ["Attack +5"] },
                { id: 3, type: "Stat", grade: "Legend", open: false, row: 0, col: 2, effects: ["Critical Hit +30"] },
                { id: 4, type: "Stat", grade: "Legend", open: false, row: 1, col: 2, effects: ["Accuracy +40"] },
                { id: 5, type: "SkillLevel", grade: "Rare", open: false, row: 1, col: 1, effects: ["Arrow Storm +1"] }] }]
        }
        const key = keyOf(s.profile.name, s.profile.serverId)
        const ref = { name: "PvE Bossing", source: "questlog.gg", author: "[Author]", gear: [
            piece("MainHand", "Enraged Kromede Longbow", 86, 15, 3), piece("Bracelet1", "Ascension Bracelet", 51, 13, 0)
        ], skills: [{ id: 1, name: "Arrow Storm", level: 13, spec: [] }], soul: { MainHand: [{ name: "Combat Speed", value: "13%" }, { name: "Weapon Damage Boost", value: null }] },
            daev: { 31: [2, 3, 4] }, deity: { Time: 80 }, boards: [], gearScore: null }
        const b = BK.newBuild("PvE Bossing", "PvE", "Ranger", ref, "questlog.gg", now - 12 * 86400000)
        b.targets.skills = { "Arrow Storm": 13, Snipe: 14 }
        b.targets.soul = { MainHand: ["Combat Speed", "Weapon Damage Boost"] }
        b.targets.goalGs = BK.gsOf(s) + 40
        b.versions.push({ v: 2, at: now - 4 * 86400000, what: "skill targets from the strongest Rangers" })
        b.version = 2
        BK.addBuild(state, b)
        const pvp = BK.newBuild("Abyss PvP", "PvP", "Ranger", null, "a copy of [Character 2]", now - 2 * 86400000)
        BK.addBuild(state, pvp)
        BK.ensureChar(state, key, { name: s.profile.name, serverId: s.profile.serverId, className: "Ranger", serverName: "[Server A]" })
        BK.assign(state, key, pvp.id, BK.gsOf(s) - 30)
        BK.assign(state, key, b.id, BK.gsOf(s) - 30)
        BK.ensureChar(state, "[Character 6]@2004", { name: "[Character 6]", serverId: 2004, className: "Assassin" })
        BK.assign(state, "[Character 6]@2004", b.id, 2400)
        state.chars[key].done[b.id] = { "gear:Gloves": { what: "Gloves +12 → +13", kind: "gear", at: now - 2 * 3600000 } }
        current = key
        snap = s
        const h = []
        for (let i = 0; i < 12; i++) h.push({ at: now - (30 - i * 2.5) * 86400000, cp: 47000 + i * 480 + (i % 3) * 300, gs: BK.gsOf(s) - 40 + i * 3 + (i > 6 ? 6 : 0), p: 20 + Math.sqrt(i) * 5, b: b.id, bv: i < 8 ? 1 : 2 })
        history = h
        state.settings.tab = demoList.indexOf("builds") >= 0 ? "builds" : demoList.indexOf("gear") >= 0 ? "gear" : demoList.indexOf("ahistory") >= 0 ? "history"
            : demoList.indexOf("goals") >= 0 ? "goals" : demoList.indexOf("soul") >= 0 ? "soul" : demoList.indexOf("askills") >= 0 ? "skills"
            : demoList.indexOf("daev") >= 0 ? "daevanion" : demoList.indexOf("stats") >= 0 ? "stats" : "overview"
        status = "Read " + when(s.at)
        revision++
    }
}
