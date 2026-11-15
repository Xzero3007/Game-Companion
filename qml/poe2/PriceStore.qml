import QtQuick
import GameCompanion
import "ee2kit.js" as Kit

// The PoE 2 price check's brain (in Main, lives with the app): Exiled
// Exchange 2's parser, filters and trade requests (ee2kit.js) with the
// app's own requests (Poe2.request, the trade site only), timers (one
// single-shot Timer per wait, gone after it) and data files. While PoE 2
// runs and the price check is on, an item copied in the game (Ctrl+C over
// it) is read and its window opens; uniques and the like search at once,
// others when SEARCH is pressed, as EE2 does.
QtObject {
    id: store
    /// Whether it may look at copied items (PoE 2 runs, the plugin is on).
    property bool on: false
    property string demo: ""

    /// The window shows.
    property bool shown: false
    /// EE2's view of the checked item (ee2kit's `view()`), or null.
    property var view: null
    /// The last search's result (kind trade/bulk, listed, total, done, error).
    property var result: null
    property bool busy: false
    property string error: ""
    property var leagues: []

    readonly property var prefs: { try { return JSON.parse(Poe2.prefs) } catch (e) { return {} } }
    readonly property string league: prefs.league || ""
    readonly property bool autoOpen: prefs.autoOpen !== false

    onOnChanged: Poe2.watch(on)
    Component.onCompleted: {
        Kit.EE2.setup(host)
        if (on) Poe2.watch(true)
        if (demo.indexOf("price") >= 0) Qt.callLater(showDemo)
    }

    // What the kit asks of the app.
    property var pending: ({})
    property int nextId: 1
    property var timers: ({})
    readonly property Component timerComp: Component {
        Timer { property var cb; onTriggered: { const f = cb; cb = null; destroy(); if (f) f() } }
    }
    readonly property var host: ({
        request: function (url, method, body) {
            return new Promise(function (resolve, reject) {
                const id = store.nextId++
                store.pending[id] = { resolve: resolve, reject: reject }
                if (store.demo.indexOf("price") >= 0) Qt.callLater(function () { store.demoAnswer(id, url) })
                else Poe2.request(id, method, url, body)
            })
        },
        timer: function (ms, cb) {
            const id = store.nextId++
            const t = store.timerComp.createObject(store, { interval: Math.max(1, ms), cb: function () { delete store.timers[id]; cb() } })
            store.timers[id] = t
            t.start()
            return id
        },
        cancel: function (id) {
            const t = store.timers[id]
            if (t) { t.stop(); t.cb = null; t.destroy(); delete store.timers[id] }
        },
        readData: function (path) { return Poe2.dataFile(path) },
        log: function (t) { console.log("poe2:", t) }
    })
    property Connections answers: Connections {
        target: Poe2
        function onAnswered(id, status, headers, body) {
            const p = store.pending[id]
            if (!p) return
            delete store.pending[id]
            if (status === 0) { p.reject(new Error(body)); return }
            let h = {}
            try { h = JSON.parse(headers) } catch (e) { }
            p.resolve({ status: status, headers: h, body: body })
        }
        function onCopied(text) { store.check(text) }
    }

    /// Reads a copied item and opens the window.
    function check(text) {
        if (!autoOpen && !shown) return
        error = ""
        result = null
        busy = true
        shown = true
        Kit.EE2.check(text, league).then(function (v) {
            busy = false
            if (!v || v.error) { view = null; error = why(v ? v.error : "", v ? v.detail : ""); return }
            view = v
            if (v.atOnce || demo.indexOf("results") >= 0) search()
        }, function (e) { busy = false; view = null; error = String(e) })
    }

    function why(code, detail) {
        if (code === "leagues") return "The trade site gave no leagues" + (detail ? ": " + detail : "")
        if (code === "item.parse_error") return "This item could not be read"
        if (code === "item.unknown") return "Exiled Exchange 2's data does not know this item yet"
        if (code === "not_an_item") return "No item text"
        if (String(code).indexOf("item.wrong_language") === 0) return "Only English and German game texts can be read"
        return code || "Something went wrong"
    }

    function search() {
        if (!view) return
        busy = true
        error = ""
        Kit.EE2.search(function (r) { if (r) result = r }).then(function (r) {
            busy = false
            if (r && r.error) error = r.error
        }, function (e) { busy = false; error = String(e); console.log("poe2: search failed:", e, e && e.stack) })
    }

    function toggleStat(i) {
        const s = view && view.stats[i]
        if (!s) return
        view = Kit.EE2.setStat(i, !s.disabled)
        result = null
    }
    function toggleFilter(key) {
        const f = view && view.filters.find(function (x) { return x.key === key })
        if (!f || f.fixed) return
        view = Kit.EE2.setFilter(key, !f.disabled)
        result = null
    }
    function close() {
        shown = false
        Kit.EE2.clear()
        view = null
        result = null
        error = ""
        busy = false
    }
    function chooseLeague(id) {
        Poe2.setPref("league", JSON.stringify(id))
        if (view) { result = null; Kit.EE2.leagues(id).then(function () { search() }) }
    }
    function loadLeagues() {
        Kit.EE2.leagues(league).then(function (l) {
            leagues = l.list
            if (!league && l.selected) Poe2.setPref("league", JSON.stringify(l.selected))
        })
    }
    onShownChanged: if (shown && leagues.length === 0) loadLeagues()

    // GC_DEMO=price: a made-up check with made-up answers (no network).
    // (Exiled Exchange 2's own test item, specs/Parser/items.ts.)
    readonly property string demoItem: "Item Class: Bows\nRarity: Rare\nOblivion Strike\nRider Bow\n--------\nPhysical Damage: 36-61\nElemental Damage: 27-36 (fire), 9-13 (cold), 5-82 (lightning)\nCritical Hit Chance: 5.00%\nAttacks per Second: 1.20\n--------\nRequires: Level 51, 103 (augmented) Dex\n--------\nItem Level: 80\n--------\n{ Prefix Modifier \"Shocking\" (Tier: 4) \u2014 Damage, Elemental, Lightning, Attack }\nAdds 5(1-5) to 82(62-89) Lightning Damage\n{ Prefix Modifier \"Scorching\" (Tier: 5) \u2014 Damage, Elemental, Fire, Attack }\nAdds 27(20-30) to 36(31-46) Fire Damage\n{ Prefix Modifier \"Icy\" (Tier: 8) \u2014 Damage, Elemental, Cold, Attack }\nAdds 9(6-9) to 13(10-15) Cold Damage\n{ Suffix Modifier \"of Radiance\" (Tier: 1) \u2014 Attack }\n+57(41-60) to Accuracy Rating\n15% increased Light Radius\n"
    function showDemo() { check(demoItem) }
    function demoAnswer(id, url) {
        const listing = function (i, amount, currency, account, hours, online) {
            return { id: "r" + i, listing: { indexed: new Date(Date.now() - hours * 3600000).toISOString(), price: { type: "~price", amount: amount, currency: currency }, account: { name: account, lastCharacterName: account, online: online ? { league: "Standard" } : null } }, item: { ilvl: 79 + (i % 3), properties: [] } }
        }
        let body = "{}"
        if (url.indexOf("/data/leagues") >= 0) body = JSON.stringify({ result: [{ id: "Standard", text: "Standard" }, { id: "Hardcore", text: "Hardcore" }, { id: "Rise of the Abyssal", text: "Rise of the Abyssal" }, { id: "HC Rise of the Abyssal", text: "Hardcore Rise of the Abyssal" }] })
        else if (url.indexOf("/data/") >= 0) body = JSON.stringify({ result: [] })
        else if (url.indexOf("/search/") >= 0) body = JSON.stringify({ id: "demo", total: 143, result: ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"] })
        else if (url.indexOf("/fetch/") >= 0) body = JSON.stringify({ result: [
            listing(0, 1, "exalted", "Kestrel_Arrow", 0.2, true), listing(1, 2, "exalted", "VaalTrader", 1, true), listing(2, 2, "exalted", "VaalTrader", 1, true),
            listing(3, 3, "exalted", "Mireth", 3, false), listing(4, 5, "exalted", "Oriathan", 5, true), listing(5, 8, "exalted", "Doryani_Fan", 9, true),
            listing(6, 10, "exalted", "Sekhema", 20, false), listing(7, 1, "divine", "Azmeri", 26, true), listing(8, 1, "divine", "Ezomyte", 50, false),
            listing(9, 2, "divine", "Karui_King", 72, true)] })
        const p = pending[id]
        if (!p) return
        delete pending[id]
        p.resolve({ status: 200, headers: {}, body: body })
    }
}
