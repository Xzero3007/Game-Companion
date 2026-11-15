// Checks qml/poe2/ee2kit.js: every sample item (EE2's own test items,
// specs/Parser/items.ts, MIT) is read and gets filters, and a search runs
// against made-up trade answers. Runs under node:
//   node tools/poe2-ee2/test/run.js
// and the same code under Qt's JavaScript (see test/v4.qml).
"use strict";
// Known to fail outside EE2's own test data (a Tablet base newer than the shipped data).
var EXPECTED = ["TwoLineOneImplicitItem"]
function run(EE2, host, items, log, done) {
    var answers = []
    // The trade site's real limit headers (several windows per rule).
    var limits = function (n) { return { "x-rate-limit-policy": "trade-search-request-limit", "x-rate-limit-rules": "Ip", "x-rate-limit-ip": "8:1:60,15:2:300,60:300:1800", "x-rate-limit-ip-state": n + ":1:0," + n + ":2:0," + n + ":300:0" } }
    var searches = 0
    // poe.ninja's currency overview, shaped as its answer (made-up prices).
    var ninja = { core: { items: [], rates: { exalted: 500, chaos: 7 }, primary: "divine", secondary: "chaos" },
        lines: [{ id: "divine", primaryValue: 1 }, { id: "exalted", primaryValue: 0.002, sparkline: { totalChange: 5.5, data: [] } },
            { id: "chaos", primaryValue: 0.14, sparkline: { totalChange: 30, data: [] } }, { id: "annul", primaryValue: 0.4, sparkline: { totalChange: -2.5, data: [] } }],
        items: [{ id: "divine", name: "Divine Orb" }, { id: "exalted", name: "Exalted Orb" }, { id: "chaos", name: "Chaos Orb" }, { id: "annul", name: "Orb of Annulment" }] }
    host.request = function (url, method, body) {
        answers.push(url)
        if (url.indexOf("https://poe.ninja/poe2/api/economy/exchange/current/overview?league=Standard&type=Currency") === 0) return Promise.resolve({ status: 200, headers: {}, body: JSON.stringify(ninja) })
        if (url.indexOf("/data/leagues") >= 0) return Promise.resolve({ status: 200, headers: {}, body: JSON.stringify({ result: [{ id: "Standard", text: "Standard" }, { id: "Hardcore", text: "Hardcore" }, { id: "Rise of the Abyssal", text: "Rise of the Abyssal" }] }) })
        if (url.indexOf("/data/stats") >= 0 || url.indexOf("/data/items") >= 0) return Promise.resolve({ status: 200, headers: {}, body: JSON.stringify({ result: [] }) })
        if (url.indexOf("/search/") >= 0) return Promise.resolve({ status: 200, headers: limits(++searches), body: JSON.stringify({ id: "q1", total: 2, result: ["a", "b"] }) })
        if (url.indexOf("/fetch/") >= 0) return Promise.resolve({ status: 200, headers: { "x-rate-limit-rules": "Ip", "x-rate-limit-ip": "12:4:10,16:12:300", "x-rate-limit-ip-state": "1:4:0,1:12:0" }, body: JSON.stringify({ result: [listing("a", 3, "exalted", "Seller1"), listing("b", 1, "divine", "Seller2")] }) })
        if (url.indexOf("/exchange/") >= 0) return Promise.resolve({ status: 200, headers: {}, body: JSON.stringify({ id: "x1", total: 1, result: { r1: { id: "r1", listing: { indexed: new Date().toISOString(), account: { name: "Bulk1", lastCharacterName: "B", online: { league: "Standard" } }, offers: [{ exchange: { currency: "exalted", amount: 3 }, item: { currency: "x", amount: 1, stock: 20 } }] } } } }) })
        return Promise.resolve({ status: 404, headers: {}, body: "{}" })
    }
    EE2.setup(host)
    function listing(id, amount, currency, account) {
        return { id: id, gone: false, listing: { indexed: new Date(Date.now() - 3600000).toISOString(), price: { type: "~price", amount: amount, currency: currency }, account: { name: account, lastCharacterName: account + "C", online: { league: "Standard" } } }, item: { ilvl: 80, frameType: 2, rarity: "Rare", name: "Gale Song", typeLine: "Test", identified: true, properties: [], requirements: [{ name: "Level", values: [["51", 0]], displayMode: 0 }, { name: "Dex", values: [["103", 1]], displayMode: 1 }], implicitMods: ["+57 to Accuracy Rating"], explicitMods: [{ description: "+32 to Spirit", hash: "h1", mods: [{ tier: "P2" }] }, { description: "15% increased Light Radius", hash: "h2", mods: [{ tier: "S5" }] }], extended: { mods: {}, hashes: {} } } }
    }
    var names = Object.keys(items), failed = [], i = 0
    function next() {
        if (i >= names.length) return finish()
        var name = names[i++]
        EE2.check(items[name], "Standard").then(function (v) {
            if ((!v || v.error) && EXPECTED.indexOf(name) < 0) failed.push(name + ": " + (v ? v.error : "nothing"))
            next()
        }, function (e) { failed.push(name + ": " + e + (e && e.stack ? " " + e.stack.split("\n")[0] : "")); next() })
    }
    function finish() {
        log("read " + (names.length - failed.length) + " of " + names.length + " items")
        failed.forEach(function (f) { log("  FAILED " + f) })
        EE2.check(items.RareItem, "Standard").then(function (v) {
            log("rare: " + v.name + " · " + v.rarity + " · api " + v.api + " · " + v.stats.length + " stats · filters " + v.filters.map(function (f) { return f.key }).join(","))
            v.stats.forEach(function (s) { log("   " + (s.disabled ? "[ ]" : "[x]") + " " + s.text + (s.min !== null ? " min " + s.min : "")) })
            // The advanced copy's mods: prefixes and suffixes with tiers and ranges.
            var mods = v.mods || []
            log("mods: " + mods.map(function (m) { return m.group + (m.tier !== null ? " T" + m.tier : "") + " " + m.lines.map(function (l) { return l.text }).join(" / ") + (m.filter !== null ? " [" + m.filter + "]" : m.folded ? " (" + m.folded + ")" : "") }).join("; "))
            if (!mods.some(function (m) { return m.group === "prefix" }) || !mods.some(function (m) { return m.group === "suffix" })) failed.push("mods: no prefixes or suffixes")
            if (!mods.some(function (m) { return m.filter !== null })) failed.push("mods: none tied to a stat line")
            EE2.setStat(0, false)
            return EE2.search(function () { })
        }).then(function (r) {
            log("search: " + (r.error ? "error " + r.error : r.total + " total, " + r.listed.map(function (l) { return l.amount + " " + l.currency + " " + l.account + " " + l.age }).join("; ")))
            if (r.error) failed.push("search: " + r.error)
            // Each listing carries its item as the trade site shows it.
            var shown = r.listed && r.listed[0] && r.listed[0].item
            log("listed item: " + JSON.stringify(shown))
            var lines = shown ? [].concat.apply([], shown.blocks.map(function (b) { return b.lines })) : []
            if (!shown || shown.title.join(" ") !== "Gale Song Test") failed.push("listed item: title")
            if (!lines.some(function (l) { return l.text === "+32 to Spirit" && l.tier === "P2" })) failed.push("listed item: explicit with tier")
            if (!lines.some(function (l) { return l.text.indexOf("Item Level: 80") === 0 })) failed.push("listed item: item level")
            if (!lines.some(function (l) { return l.text === "+57 to Accuracy Rating" })) failed.push("listed item: implicit")
            // poe.ninja: 3 ex stays, 1 divine stays; nothing to convert. A chaos price would.
            var t = EE2.ninjaRead("Standard", JSON.stringify(ninja))
            log("ninja: " + t.exalted + " ex per div, annul " + t.byId.annul.div + " div")
            if (!r.listed.every(function (l) { return l.norm === null })) failed.push("ninja: converted a price in its own currency")
            var n1 = EE2.ninjaNorm(t, 4, "chaos"), n2 = EE2.ninjaNorm(t, 600, "exalted"), n3 = EE2.ninjaNorm(t, 2, "mirror")
            log("ninja: 4 chaos = " + JSON.stringify(n1) + ", 600 ex = " + JSON.stringify(n2))
            if (!n1 || n1.currency !== "exalted" || Math.abs(n1.amount - 280) > 0.01) failed.push("ninja: 4 chaos")
            if (!n2 || n2.currency !== "divine" || Math.abs(n2.amount - 1.2) > 0.01) failed.push("ninja: 600 ex")
            if (n3 !== null) failed.push("ninja: an unknown currency")
            // Again after the limits' windows passed (their handles leave the stack).
            return new Promise(function (res) { host.timer(4000, res) }).then(function () { return EE2.check(items.UniqueItem, "Standard") }).then(function () { return EE2.search(function () { }) })
        }).then(function (r) {
            log("search again: " + (r.error ? "error " + r.error : r.total + " total"))
            if (r.error) failed.push("search: " + r.error)
            var link = EE2.tradeLink()
            log("trade link: " + link.slice(0, 90) + "…")
            var q = link.split("?q=")[1]
            if (link.indexOf("https://www.pathofexile.com/trade2/search/poe2/Standard?q=") !== 0 || !q || !JSON.parse(decodeURIComponent(q)).query)
                failed.push("trade link: " + link.slice(0, 120))
            return EE2.check("Item Class: Stackable Currency\nRarity: Currency\nOrb of Annulment\n--------\nStack Size: 3/20\n--------\nRemoves a random modifier from an item\n--------\nRight click this item then left click a magic or rare item to apply it.\n", "Standard")
        }).then(function (v) {
            log("annul: " + v.name + " · api " + v.api + " · ninja " + JSON.stringify(v.ninja))
            if (!v.ninja || v.ninja.div !== 0.4 || v.ninja.exalted !== 200 || v.ninja.change !== -2.5) failed.push("ninja: no price for Orb of Annulment")
            return EE2.search(function () { })
        }).then(function (r) {
            log("annul search: " + JSON.stringify(r).slice(0, 400))
            if (!r.ninja) failed.push("ninja: not in the exchange's result")
            return EE2.check(items.UncutSkillGem, "Standard")
        }).then(function (v) {
            log("gem: " + v.name + " · api " + v.api)
            return EE2.search(function () { })
        }).then(function (r) {
            log("gem search: " + JSON.stringify(r).slice(0, 300))
            log("gem trade link: " + EE2.tradeLink())
            if (EE2.tradeLink().indexOf("https://www.pathofexile.com/trade2/exchange/poe2/Standard") !== 0) failed.push("gem trade link")
            log("requests: " + answers.map(function (u) { return u.replace(/\?.*/, "").replace("https://www.pathofexile.com", "") }).join(" "))
            done(failed.length === 0)
        }).catch(function (e) { log("ERROR " + e + (e && e.stack ? "\n" + e.stack : "")); done(false) })
    }
    next()
}

if (typeof module !== "undefined" && typeof require !== "undefined" && require.main === module) {
    var fs = require("fs"), path = require("path")
    var repo = path.resolve(__dirname, "../../..")
    var src = fs.readFileSync(path.join(repo, "qml/poe2/ee2kit.js"), "utf8").replace(/^\.pragma library/, "")
    var EE2 = new Function(src + "\nreturn EE2;")()
    var timers = {}, nextId = 1
    var host = {
        request: null,
        timer: function (ms, cb) { var id = nextId++; timers[id] = setTimeout(function () { delete timers[id]; cb() }, ms); return id },
        cancel: function (id) { clearTimeout(timers[id]); delete timers[id] },
        readData: function (p) { return fs.readFileSync(path.join(repo, "data/poe2", p), "utf8") },
        log: function (t) { console.log(t) },
    }
    EE2.setup(host)
    var items = JSON.parse(fs.readFileSync(path.join(__dirname, "items.json"), "utf8"))
    run(EE2, host, items, console.log, function (ok) { process.exit(ok ? 0 : 1) })
}
if (typeof module !== "undefined") module.exports = { run: run }
