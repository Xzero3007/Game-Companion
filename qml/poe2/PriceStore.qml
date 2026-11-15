import QtQuick
import GameCompanion

// The PoE 2 price check's brain (in Main, lives with the app). Exiled
// Exchange 2's parser, filters and trade requests (ee2kit.js) run in their
// own process with QuickJS (src/poe2_kit.rs; Qt's JavaScript crashed in
// them, MN 0.8.44): `kit(fn, args)` asks it and gives a promise. If that
// process ends, only the price check starts again. While PoE 2 runs and
// the price check is on, an item copied in the game (Ctrl+C over it) is
// read and its window opens; uniques and the like search at once, others
// when SEARCH is pressed, as EE2 does.
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
        if (on) Poe2.watch(true)
        if (demo.indexOf("price") >= 0) Qt.callLater(showDemo)
    }

    // The kit's process: one call per id, answered by kitSaid.
    property var calls: ({})
    property int nextCall: 1
    function kit(fn, args, progress) {
        return new Promise(function (resolve, reject) {
            const id = store.nextCall++
            store.calls[id] = { resolve: resolve, reject: reject, progress: progress || null }
            if (!Poe2.kitCall(JSON.stringify({ id: id, fn: fn, args: args || [] }))) {
                delete store.calls[id]
                reject(new Error("The price check could not start"))
            }
        })
    }
    property Connections answers: Connections {
        target: Poe2
        function onKitSaid(line) {
            let m
            try { m = JSON.parse(line) } catch (e) { return }
            const c = store.calls[m.id]
            if (!c) return
            if (m.kind === "progress") { if (c.progress) c.progress(m.value); return }
            delete store.calls[m.id]
            if (m.kind === "reply") c.resolve(m.value)
            else c.reject(new Error(m.value))
        }
        function onKitGone(why) {
            const open = store.calls
            store.calls = ({})
            for (const id in open) open[id].reject(new Error("gone"))
            // What the kit knew is gone with it: the next item starts afresh.
            if (store.busy || store.view) {
                store.view = null
                store.result = null
                store.busy = false
                store.error = "The price check stopped (" + why + ") and starts again with the next copy."
            }
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
        Companion.log("poe2", "check: start")
        kit("check", [text, league]).then(function (v) {
            busy = false
            if (!v || v.error) { Companion.log("poe2", "check: done, " + (v ? v.error : "no result")); view = null; error = why(v ? v.error : "", v ? v.detail : ""); return }
            Companion.log("poe2", "check: done, item read" + (v.atOnce ? ", searching at once" : ""))
            view = v
            if (v.atOnce || demo.indexOf("results") >= 0) search()
        }, function (e) { Companion.log("poe2", "check: failed: " + e); if (e.message === "gone") return; busy = false; view = null; error = String(e.message || e) })
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
        Companion.log("poe2", "search: start")
        kit("search", [], function (r) { if (r) { Companion.log("poe2", "search: part of the results in"); result = r } }).then(function (r) {
            busy = false
            Companion.log("poe2", "search: done" + (r && r.error ? ", " + r.error : ""))
            if (r && r.error) error = r.error
        }, function (e) { Companion.log("poe2", "search: failed: " + e); if (e.message === "gone") return; busy = false; error = String(e.message || e) })
    }

    function toggleStat(i) {
        const s = view && view.stats[i]
        if (!s) return
        result = null
        kit("setStat", [i, !s.disabled]).then(function (v) { if (v) view = v }, function () { })
    }
    function toggleFilter(key) {
        const f = view && view.filters.find(function (x) { return x.key === key })
        if (!f || f.fixed) return
        result = null
        kit("setFilter", [key, !f.disabled]).then(function (v) { if (v) view = v }, function () { })
    }
    function close() {
        shown = false
        kit("clear").then(function () { }, function () { })
        view = null
        result = null
        error = ""
        busy = false
    }
    function chooseLeague(id) {
        Poe2.setPref("league", JSON.stringify(id))
        if (view) { result = null; kit("leagues", [id]).then(function () { search() }, function () { }) }
    }
    function loadLeagues() {
        kit("leagues", [league]).then(function (l) {
            leagues = l.list
            if (!league && l.selected) Poe2.setPref("league", JSON.stringify(l.selected))
        }, function () { })
    }
    onShownChanged: if (shown && leagues.length === 0) loadLeagues()

    // GC_DEMO=price: a made-up check; the kit's process answers with
    // made-up listings (src/poe2_kit.rs DEMO, no network).
    // (Exiled Exchange 2's own test item, specs/Parser/items.ts.)
    readonly property string demoItem: "Item Class: Bows\nRarity: Rare\nOblivion Strike\nRider Bow\n--------\nPhysical Damage: 36-61\nElemental Damage: 27-36 (fire), 9-13 (cold), 5-82 (lightning)\nCritical Hit Chance: 5.00%\nAttacks per Second: 1.20\n--------\nRequires: Level 51, 103 (augmented) Dex\n--------\nItem Level: 80\n--------\n{ Prefix Modifier \"Shocking\" (Tier: 4) \u2014 Damage, Elemental, Lightning, Attack }\nAdds 5(1-5) to 82(62-89) Lightning Damage\n{ Prefix Modifier \"Scorching\" (Tier: 5) \u2014 Damage, Elemental, Fire, Attack }\nAdds 27(20-30) to 36(31-46) Fire Damage\n{ Prefix Modifier \"Icy\" (Tier: 8) \u2014 Damage, Elemental, Cold, Attack }\nAdds 9(6-9) to 13(10-15) Cold Damage\n{ Suffix Modifier \"of Radiance\" (Tier: 1) \u2014 Attack }\n+57(41-60) to Accuracy Rating\n15% increased Light Radius\n"
    function showDemo() { check(demoItem) }
}
