import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "marketkit.js" as MK

// The AION 2 module's Market (the Clicktrough Market plugin, in QML): your
// server's market prices, what the gathered materials bring, what they cost
// made from Odyle (Substance Morph), what each recipe costs and brings,
// where each material goes, everything listed and the anomalies. Its logic
// and tables are the plugin's (marketkit.js). Prices come from Clicktrough's
// hourly copy on GitHub first, else from aion2.exchange (Aion2.webGet: only
// those two); icons from the game's icon server, kept on disk.
Panel {
    id: panel
    panelId: "market"
    title: width < 460 ? "Market" : "Market"
    tag: width < 460 ? "" : "AION 2"
    width: 640
    minWidth: 420
    maxWidth: 1400
    stretchy: true
    minGrow: -200

    /// A gathered material's map button: where it grows, on the Map.
    signal showOnMap(string name)
    /// The NPC prices of the bound tools shown under the recipes.
    property bool npcShown: false

    readonly property string copyUrl: "https://raw.githubusercontent.com/Xzero3007/A2Tools-DPS-Meter_Clicktrough/market-data/"
    readonly property string apiUrl: "https://aion2.exchange/api/"
    readonly property int staleMs: 20 * 60000
    readonly property int copyOldMs: 3 * 3600000

    // ---- what is kept ----
    property var settings: ({
        server: null, region: "", tab: "gather", fee: 10, npc: {}, prof: "all", sort: "profit", priced: true, kind: "all",
        search: {}, faction: null, fav: [], pins: true, cat: "all", minGrade: 0, allSort: "name", listedOnly: true
    })
    property var servers: []
    property var prices: new Map()
    property real fetchedAt: 0
    property string snapshot: ""
    property string source: ""
    property bool busy: false
    property string error: ""
    property var hist: null
    property var opened: ({})
    property var shown: ({ recipes: 80, materials: 80, listings: 80 })
    /// The player's server, the game's number (from the DPS module), 0 unknown.
    readonly property int gameServer: {
        try { const e = JSON.parse(Aion2.fight).extras; return e && e.server ? e.server : 0 } catch (x) { return 0 }
    }
    // The game named the server you play on: its market, unless it is the one shown.
    onGameServerChanged: {
        if (!servers.length) return
        const mine = MK.C.serverOf(servers, gameServer)
        if (mine && mine.id !== settings.server) { takeServer(mine.id); loadPrices(true) }
        else if (settings.server == null) { pickServer(); loadPrices(false) }
    }
    /// The region whose servers the list shows: the one picked, else the shown server's.
    readonly property string region: {
        if (settings.region) return settings.region
        const s = server()
        return s ? s.region : ""
    }
    readonly property var regions: {
        const seen = []
        for (const s of servers) if (s.hasData && seen.indexOf(s.region) < 0) seen.push(s.region)
        return seen.sort((a, b) => (b === "Europe") - (a === "Europe") || a.localeCompare(b))
    }
    function takeServer(id) {
        prices = new Map()
        hist = null
        fetchedAt = 0
        opened = ({})
        change("server", id)
        const s = server()
        if (s) change("region", s.region)
    }

    function change(key, value) {
        const s = Object.assign({}, settings)
        s[key] = value
        settings = s
        saveTimer.restart()
        refresh()
    }
    Timer { id: saveTimer; interval: 400; onTriggered: Aion2.keepStore("market", JSON.stringify(panel.settings)) }

    function server() { for (const s of servers) if (s.id === settings.server) return s; return null }
    function faction() { const s = server(); return settings.faction || (s ? s.faction : null) }
    function npc() { return Object.assign({}, MK.D.npcPrices, settings.npc) }
    function fee() { return Math.max(0, Math.min(50, Number(settings.fee) || 0)) / 100 }
    function kina(v) { return MK.C.kina(v) }
    function fold(t) { return String(t).toLowerCase() }
    function when(iso) {
        if (!iso) return "earlier"
        const d = new Date(iso)
        if (isNaN(d.getTime())) return "earlier"
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        const two = (n) => (n < 10 ? "0" : "") + n
        return two(d.getDate()) + " " + months[d.getMonth()] + ", " + two(d.getHours()) + ":" + two(d.getMinutes())
    }

    // ---- the downloads: one request at a time per caller, answered by id ----
    property int nextId: 1
    property var waiting: ({})
    function get(url) {
        return new Promise((resolve, reject) => {
            const id = nextId++
            waiting[id] = { resolve: resolve, reject: reject }
            Aion2.webGet(id, url)
        })
    }
    Connections {
        target: Aion2
        function onWebGot(id, ok, body) {
            const w = panel.waiting[id]
            if (!w) return
            delete panel.waiting[id]
            if (!ok) { w.reject(new Error(body)); return }
            try { w.resolve(JSON.parse(body)) } catch (e) { w.reject(new Error("the answer is no JSON")) }
        }
        function onIconReady(name) { panel.iconsRevision++ }
    }
    property int iconsRevision: 0
    function iconOf(id) {
        iconsRevision
        const name = MK.C.icon(id)
        return name ? Aion2.icon(name) : ""
    }

    function loadServers() {
        let failure = null
        const tryUrl = (urls) => {
            if (!urls.length) return Promise.resolve([])
            return get(urls[0]).then((res) => {
                const list = MK.C.readServers(res)
                return list.length ? list : tryUrl(urls.slice(1))
            }, (e) => { failure = e; return tryUrl(urls.slice(1)) })
        }
        return tryUrl([copyUrl + "servers.json", apiUrl + "servers"]).then((list) => {
            if (list.length) {
                servers = list
                error = ""
                Aion2.keepStore("market-servers", JSON.stringify({ at: Date.now(), servers: list }))
            } else if (!servers.length) {
                error = "aion2.exchange: " + (failure ? failure.message : "no servers in its answer")
            }
            pickServer()
            refresh()
        })
    }
    function pickServer() {
        if (settings.server != null && servers.some((s) => s.id === settings.server)) return
        const mine = MK.C.serverOf(servers, gameServer)
        if (mine) takeServer(mine.id)
    }
    function directRows(id) {
        const rows = []
        const page = (n) => get(apiUrl + "items?server=" + id + "&limit=1000&offset=" + rows.length).then((res) => {
            const items = Array.isArray(res && res.items) ? res.items : []
            for (const it of items) rows.push(it)
            if (!items.length || rows.length >= (Number(res && res.total) || 0) || n >= 9) return rows
            return page(n + 1)
        })
        return page(0)
    }
    function loadPrices(force) {
        const s = server()
        if (!s || busy) return
        if (!force && fetchedAt && Date.now() - fetchedAt < staleMs && prices.size) return
        busy = true
        error = ""
        let copy = null
        let failure = null
        get(copyUrl + "prices/" + s.id + ".json").then((doc) => { copy = MK.C.readCopy(doc) }, () => {}).then(() => {
            const copyOld = !copy || Date.now() - (Date.parse(copy.copied) || 0) > copyOldMs
            if (!copyOld) return null
            return directRows(s.id).then((rows) => rows.length ? {
                prices: MK.C.readPrices(rows),
                snapshot: rows.map((r) => r.captured_at).filter(Boolean).sort().pop() || "",
                source: "aion2.exchange"
            } : null, (e) => { failure = e; return null })
        }).then((got) => {
            if (!got && copy) got = { prices: copy.prices, snapshot: copy.snapshot || "", source: "copy" }
            if (!got) throw failure || new Error("no prices for this server yet")
            if (s.id !== settings.server) return
            prices = got.prices
            snapshot = got.snapshot
            source = got.source
            fetchedAt = Date.now()
            if (failure) error = "aion2.exchange: " + failure.message + " · showing the copy of " + when(snapshot)
            const keep = Array.from(prices).map((e) => [e[0], e[1].price, e[1].listings, e[1].sold, e[1].soldAvg, e[1].change])
            Aion2.keepStore("market-prices", JSON.stringify({ server: s.id, at: fetchedAt, snapshot: snapshot, source: source, rows: keep }))
            return get(copyUrl + "history/" + s.id + ".json").then((doc) => {
                const h = MK.A.readHistory(doc)
                if (h && s.id === settings.server) {
                    hist = h
                    Aion2.keepStore("market-history", JSON.stringify({ server: s.id, doc: Object.assign({ v: 1 }, h) }))
                }
            }, () => {})
        }).catch((e) => {
            error = "aion2.exchange: " + (e && e.message ? e.message : e) + (prices.size ? " · showing the prices from before" : "")
        }).then(() => { busy = false; refresh() })
    }
    // While open: every 30 minutes (no timer while closed).
    Timer { interval: 30 * 60000; repeat: true; running: panel.visible; onTriggered: panel.loadPrices(true) }

    Component.onCompleted: {
        try {
            const s = JSON.parse(Aion2.loadStore("market") || "{}")
            const merged = Object.assign({}, settings, s)
            merged.npc = Object.assign({}, s.npc || {})
            merged.search = Object.assign({}, s.search || {})
            if (!Array.isArray(merged.fav)) merged.fav = []
            settings = merged
        } catch (e) { }
        try {
            const c = JSON.parse(Aion2.loadStore("market-servers") || "{}")
            if (Array.isArray(c.servers)) servers = MK.C.readServers(c)
        } catch (e) { }
        try {
            const p = JSON.parse(Aion2.loadStore("market-prices") || "{}")
            if (p.server === settings.server && Array.isArray(p.rows)) {
                const m = new Map()
                for (const r of p.rows) m.set(String(r[0]), { price: r[1], listings: r[2], sold: r[3], soldAvg: r[4], change: r[5] })
                prices = m
                fetchedAt = p.at || 0
                snapshot = p.snapshot || ""
                source = p.source || ""
            }
        } catch (e) { }
        try {
            const h = JSON.parse(Aion2.loadStore("market-history") || "{}")
            if (h.server === settings.server) hist = MK.A.readHistory(h.doc)
        } catch (e) { }
        refresh()
        loadServers().then(() => loadPrices(false))
    }

    // ---- what the list shows: rows worked out again when something changes ----
    property var rows: []
    property var pinRows: []
    property var head: []
    property var widths: []
    property string note: ""
    function refresh() { refreshLater.restart() }
    Timer { id: refreshLater; interval: 1; onTriggered: panel.build() }

    function isFav(id) { return settings.fav.indexOf(Number(id)) >= 0 }
    function toggleFav(id) {
        const n = Number(id)
        change("fav", isFav(n) ? settings.fav.filter((x) => x !== n) : settings.fav.concat([n]))
    }
    function toggle(key) {
        const o = Object.assign({}, opened)
        if (o[key]) delete o[key]; else o[key] = true
        opened = o
        refresh()
    }
    function favsOf(list, idOf) { return settings.pins === false ? [] : list.filter((x) => isFav(idOf(x))) }
    function tone(v) { return v == null ? "none" : v > 0 ? "gain" : v < 0 ? "loss" : "" }
    function price(v) { return { t: kina(v), tone: v == null ? "none" : "" } }
    function changeCell(v) {
        return { t: v == null ? "—" : v >= 900 ? "×" + kina(1 + v / 100) : (v > 0 ? "+" : "") + Math.round(v) + "%", tone: tone(v) }
    }
    function judged(id) { return MK.A.judge(prices.get(String(id)), MK.A.usual(hist, id)) }
    function flagOf(j) {
        if (!j || !j.kind) return null
        const t = j.kind === "high" ? "×" + (j.ratio >= 100 ? kina(j.ratio) : j.ratio.toFixed(j.ratio >= 10 ? 0 : 1)) : Math.round(j.ratio * 100) + " %"
        return { t: t, kind: j.kind }
    }
    function sourceTag(cost) {
        if (cost.source === "morph") return { t: "morph", kind: "morph" }
        if (cost.source === "npc") return { t: "NPC", kind: "npc" }
        return null
    }
    /// An item's row: the name cell (star, icon, name, what follows, a tag) and the others.
    function itemRow(id, key, cells, opts) {
        opts = opts || {}
        return { kind: "item", id: Number(id), key: key, label: opts.label || MK.C.name(id), grade: opts.grade || 0,
            after: opts.after || "", sub: opts.sub || "", tag: opts.tag || null, cells: cells, open: !!opened[key], click: opts.click !== false,
            map: !!MK.C.kindOf(id) }
    }
    function usesRows(id) {
        const n = npc()
        const us = MK.C.usesOf(faction()).get(String(id)) || []
        if (!us.length) return [{ kind: "text", text: "No " + (faction() || "") + " recipe needs " + MK.C.name(id) + "." }]
        const best = MK.C.unitCost(prices, n, id)
        const out = [{ kind: "subhead", cells: ["Used in", "Count", "Costs", "Product sells for"] }]
        const list = us.slice().sort((a, b) => b.count - a.count || MK.C.name(a.recipe[6]).localeCompare(MK.C.name(b.recipe[6])))
        for (const u of list) {
            const s = MK.C.recipeSums(u.recipe, prices, n, { fee: fee() })
            out.push({ kind: "sub", id: u.recipe[6], label: MK.C.name(u.recipe[6]), after: " · " + u.recipe[2],
                cells: [{ t: "× " + u.count }, price(best.unit == null ? null : best.unit * u.count), price(s.net)] })
        }
        return out
    }
    function itemDetail(id) {
        const p = prices.get(String(id)) || {}
        const usual = MK.A.usual(hist, id)
        const j = MK.A.judge(p, usual)
        const out = []
        if (usual) out.push({ kind: "text", text: "Usual price " + kina(usual.price) + " (median of " + usual.n + " " + usual.from + ")." })
        if (j && (j.kind || j.coded || j.thin))
            out.push({ kind: "text", text: (j.kind === "high" ? "Far above it: " : j.kind === "low" ? "Far below it: " : "") + MK.A.reason(j, kina) + "." })
        if (j && j.kind === "high")
            out.push({ kind: "text", text: "Only the lowest listing is known: whether anyone buys at that price, the copy can't tell." })
        const it = hist && hist.items ? hist.items[String(id)] : null
        if (!it) out.push({ kind: "text", text: "No course yet: the hourly copy keeps one from 10 Nov 2026 on." })
        else {
            out.push({ kind: "course", title: "Last " + (it.h || []).length + " hours", values: it.h || [], usual: usual ? usual.price : 0 })
            out.push({ kind: "course", title: "Last " + (it.d || []).length + " days (median of each)", values: it.d || [], usual: usual ? usual.price : 0 })
        }
        return out
    }
    function withDetail(row, detail) { return row.open ? [row].concat(detail()) : [row] }

    function build() {
        const tab = settings.tab
        const q = fold((settings.search || {})[tab] || "")
        const fac = faction()
        let out = [], pins = []
        note = ""
        if (tab === "gather") {
            const groups = [["Odyle", [MK.D.odyle]]].concat(Object.entries(MK.D.gather))
            const titles = { Odyle: "Odyle", Ore: "Ore", Gemstone: "Gemstones", Log: "Logs", Herb: "Herbs", Cooking: "Cooking ingredients" }
            const flat = (lists) => [].concat.apply([], lists.map((l) => Array.isArray(l) ? l : [l]))
            const all = []
            const sections = []
            for (const g of groups) {
                const ids = flat(g[1]).filter((id) => MK.C.ofFaction(id, fac) && (!q || fold(MK.C.name(id)).indexOf(q) >= 0))
                if (ids.length) { sections.push([titles[g[0]] || g[0], ids]); for (const id of ids) all.push(id) }
            }
            const sales = all.some((id) => { const p = prices.get(String(id)); return p && (p.sold != null || p.soldAvg != null) })
            head = sales ? ["Material", "Lowest", "Listed", "Sold 28 d", "Avg sold", "Change"] : ["Material", "Lowest", "Listed", "Change"]
            widths = sales ? [0.34, 0.14, 0.11, 0.13, 0.14, 0.14] : [0.46, 0.2, 0.16, 0.18]
            const rowsOf = (id, pre) => {
                const p = prices.get(String(id)) || {}
                const cells = [price(p.price), { t: p.listings ? kina(p.listings) : "—" }]
                if (sales) cells.push({ t: p.sold != null ? kina(p.sold) : "—" }, price(p.soldAvg))
                cells.push(changeCell(p.change))
                return withDetail(itemRow(id, pre + "g:" + id, cells, { tag: flagOf(judged(id)) }), () => usesRows(id))
            }
            for (const s of sections) {
                out.push({ kind: "group", title: s[0] })
                for (const id of s[1]) out = out.concat(rowsOf(id, ""))
            }
            const everyone = []
            for (const g of groups) for (const id of flat(g[1])) if (MK.C.ofFaction(id, fac)) everyone.push(id)
            for (const id of favsOf(everyone, (x) => x)) pins = pins.concat(rowsOf(id, "p"))
            if (!out.length) out.push({ kind: "empty", text: "Nothing matches." })
        } else if (tab === "odyle") {
            const e = MK.C.energyMorphCost(prices)
            note = "Odyle Energy (Bound), +40: 25 Odyle, 5 Fine Odyle, 1 Pure Odyle and 50,000 Kina"
                + (e ? " = " + kina(e.total) + " Kina, " + kina(e.perEnergy) + " per energy" : " (no Odyle prices yet)")
                + " · at most 4 a week per character, 16 per server. What morphing makes is bound: it goes into your own crafting."
            head = ["Material", "Market", "Odyle used", "Odyle price", "Morph saves"]
            widths = [0.34, 0.14, 0.16, 0.14, 0.22]
            const rowsOf = (r, pre) => {
                const save = r.saving == null ? { t: "—", tone: "none" }
                    : { t: r.saving > 0 ? kina(r.saving) + " (" + Math.round(r.savingPct * 100) + "%)" : "buy (" + kina(-r.saving) + " cheaper)", tone: r.saving > 0 ? "gain" : "loss" }
                return withDetail(itemRow(r.item, pre + "o:" + r.item, [price(r.market), { t: MK.C.name(r.odyle), tone: "sub" }, price(r.odylePrice), save]), () => usesRows(r.item))
            }
            const list = MK.C.morphTable(prices, fac)
            for (const r of list) out = out.concat(rowsOf(r, ""))
            for (const r of favsOf(list, (x) => x.item)) pins = pins.concat(rowsOf(r, "p"))
        } else if (tab === "recipes") {
            head = ["Product", "Sells for", "Cost: market", "Cost: morph", "Profit"]
            widths = [0.34, 0.15, 0.15, 0.15, 0.21]
            if (!fac) out.push({ kind: "empty", text: "Pick your server or faction above: its recipes and its prices." })
            else {
                const n = npc()
                const sums = (r) => ({ r: r, s: MK.C.recipeSums(r, prices, n, { fee: fee() }) })
                let list = MK.C.recipesOf(fac)
                    .filter((r) => settings.prof === "all" || r[2] === settings.prof)
                    .filter((r) => !q || fold(MK.C.name(r[6])).indexOf(q) >= 0 || r[8].some((m) => fold(MK.C.name(m[0])).indexOf(q) >= 0))
                    .map(sums)
                if (settings.priced) list = list.filter((x) => x.s.sell != null || isFav(x.r[6]))
                const neg = -Infinity
                const by = {
                    profit: (a, b) => (b.s.profit != null ? b.s.profit : neg) - (a.s.profit != null ? a.s.profit : neg),
                    margin: (a, b) => (b.s.margin != null ? b.s.margin : neg) - (a.s.margin != null ? a.s.margin : neg),
                    level: (a, b) => a.r[4] - b.r[4],
                    name: (a, b) => MK.C.name(a.r[6]).localeCompare(MK.C.name(b.r[6]))
                }[settings.sort] || (() => 0)
                const order = (a, b) => (by(a, b) || 0) || MK.C.name(a.r[6]).localeCompare(MK.C.name(b.r[6]))
                list.sort(order)
                const rowsOf = (x, pre) => {
                    const r = x.r, s = x.s
                    const profit = s.profit == null ? { t: s.complete ? "—" : "prices missing", tone: "none" }
                        : { t: (s.profit >= 0 ? "+" : "") + kina(s.profit) + (s.margin != null ? "  " + Math.round(s.margin * 100) + "%" : ""), tone: s.profit >= 0 ? "gain" : "loss" }
                    const row = itemRow(r[6], pre + "r:" + r[0], [price(s.net), price(s.complete ? s.costBuy : null), price(s.complete ? s.costBest : null), profit],
                        { after: (r[7] > 1 ? " × " + r[7] : "") + " · " + r[2] })
                    return withDetail(row, () => recipeDetail(s, r))
                }
                for (const x of list.slice(0, shown.recipes)) out = out.concat(rowsOf(x, ""))
                if (!list.length) out.push({ kind: "empty", text: prices.size ? "Nothing matches." : "No prices yet." })
                if (list.length > shown.recipes) out.push({ kind: "more", tab: "recipes", left: list.length - shown.recipes })
                const favs = favsOf(MK.C.recipesOf(fac), (r) => r[6]).map(sums).sort(order)
                for (const x of favs) pins = pins.concat(rowsOf(x, "p"))
            }
            if (npcShown) {
                out.push({ kind: "group", title: "NPC prices of the bound tools" })
                out.push({ kind: "text", text: "What the NPC shops ask (as MetaBot.GG lists it from the game files); change one if the shop asks otherwise." })
                const ids = Object.keys(MK.D.npcPrices).sort((a, b) => MK.C.name(a).localeCompare(MK.C.name(b)))
                for (const id of ids) out.push({ kind: "npc", id: Number(id), label: MK.C.name(id), value: settings.npc[id] != null ? settings.npc[id] : MK.D.npcPrices[id], base: MK.D.npcPrices[id] })
            }
        } else if (tab === "materials") {
            head = ["Material", "Market", "Best", "Recipes"]
            widths = [0.52, 0.17, 0.17, 0.14]
            if (!fac) out.push({ kind: "empty", text: "Pick your server or faction above." })
            else {
                const n = npc()
                const uses = MK.C.usesOf(fac)
                const kindOf = (id) => {
                    if (MK.C.kindOf(id)) return "gathered"
                    if (MK.D.npcPrices[String(id)] != null) return "npc"
                    const g = Number(String(id).slice(0, 2))
                    return g >= 61 && g <= 63 ? "crafted" : "gear"
                }
                const entries = Array.from(uses.entries())
                const list = entries
                    .filter((e) => settings.kind === "all" || kindOf(e[0]) === settings.kind)
                    .filter((e) => !q || fold(MK.C.name(e[0])).indexOf(q) >= 0 || e[1].some((u) => fold(MK.C.name(u.recipe[6])).indexOf(q) >= 0))
                    .sort((a, b) => b[1].length - a[1].length || MK.C.name(a[0]).localeCompare(MK.C.name(b[0])))
                const rowsOf = (e, pre) => {
                    const id = e[0]
                    const best = MK.C.unitCost(prices, n, id)
                    return withDetail(itemRow(id, pre + "m:" + id, [price(best.source === "npc" ? best.unit : MK.C.market(prices, id)), price(best.unit), { t: String(e[1].length) }],
                        { tag: sourceTag(best) }), () => usesRows(id))
                }
                for (const e of list.slice(0, shown.materials)) out = out.concat(rowsOf(e, ""))
                if (!list.length) out.push({ kind: "empty", text: "Nothing matches." })
                if (list.length > shown.materials) out.push({ kind: "more", tab: "materials", left: list.length - shown.materials })
                const favs = favsOf(entries, (e) => e[0]).sort((a, b) => MK.C.name(a[0]).localeCompare(MK.C.name(b[0])))
                for (const e of favs) pins = pins.concat(rowsOf(e, "p"))
            }
        } else {
            head = ["Item", "Lowest", "Listed", "Usual", "Change"]
            widths = [0.46, 0.16, 0.1, 0.16, 0.12]
            const cat = {}
            for (const c of MK.C.CATEGORIES) cat[c[0]] = c[1]
            const listRow = (r, key) => withDetail(itemRow(r.id, key, [price(r.p.price), { t: r.p.listings ? kina(r.p.listings) : "—" },
                { t: r.usual ? kina(r.usual.price) : "—", tone: r.usual ? "" : "none" }, changeCell(r.p.change)],
                { label: r.name, grade: r.grade, tag: flagOf(r.j), sub: [MK.C.GRADES[r.grade], cat[r.category]].filter(Boolean).join(" · ") }), () => itemDetail(r.id))
            if (!prices.size) out.push({ kind: "empty", text: server() ? "No prices yet." : "Pick your server above." })
            else if (tab === "listings") {
                const list = MK.C.listing(prices, hist, { search: (settings.search || {}).listings || "", cat: settings.cat, minGrade: settings.minGrade, listedOnly: settings.listedOnly, sort: settings.allSort })
                const odd = list.filter((r) => r.j && r.j.kind).length
                note = kina(list.length) + " items" + (odd ? " · " + odd + " far from their usual price (see Anomalies)" : "") + " · what aion2.exchange saw on your server's market"
                for (const r of list.slice(0, shown.listings)) out = out.concat(listRow(r, "l:" + r.id))
                if (!list.length) out.push({ kind: "empty", text: "Nothing matches." })
                if (list.length > shown.listings) out.push({ kind: "more", tab: "listings", left: list.length - shown.listings })
                for (const r of favsOf(MK.C.listing(prices, hist, { listedOnly: false }), (r) => r.id)) pins = pins.concat(listRow(r, "pl:" + r.id))
            } else {
                note = "Lowest listings far from the item's usual price (the median of its lowest listing over the last days, or hours). Far above: ×5 or more; far below: 40 % or less."
                const everything = MK.C.listing(prices, hist, { listedOnly: false })
                const a = MK.C.anomalies(everything.filter((r) => r.p.price > 0))
                const groups = [["Far above the usual price (" + a.high.length + ")", a.high, "Nothing far above its usual price right now."],
                    ["Far below the usual price: bargains (" + a.low.length + ")", a.low, hist ? "Nothing far below its usual price right now." : "Bargains need the course of a few hours first."]]
                for (const g of groups) {
                    out.push({ kind: "group", title: g[0] })
                    if (!g[1].length) out.push({ kind: "text", text: g[2] })
                    for (const r of g[1]) {
                        out = out.concat(listRow(r, "a:" + r.id))
                        if (!opened["a:" + r.id]) out.push({ kind: "text", text: MK.A.reason(r.j, kina) })
                    }
                }
                for (const r of favsOf(everything, (r) => r.id)) pins = pins.concat(listRow(r, "pa:" + r.id))
            }
        }
        if (pins.length) pins.unshift({ kind: "group", title: "★ Favorites (" + pins.filter((r) => r.kind === "item").length + ")" })
        pinRows = pins
        rows = out
    }
    function recipeDetail(s, r) {
        const out = [{ kind: "subhead", cells: ["Material", "Count", "Market each", "Best each", "Total"], five: true }]
        for (const l of s.lines) {
            out.push({ kind: "sub", five: true, id: l.item, label: MK.C.name(l.item), tag: sourceTag(l.best),
                cells: [{ t: "× " + l.count }, price(l.buy.source === "npc" ? l.buy.unit : MK.C.market(prices, l.item)), price(l.best.unit), price(l.bestTotal)] })
        }
        const extra = []
        if (r[9]) {
            const pct = r[9][0], item = r[9][1], n = r[9][2]
            const p = MK.C.market(prices, item)
            extra.push("Combo " + pct + "%: " + (n > 1 ? n + " × " : "") + MK.C.name(item) + (p != null ? " (" + kina(p) + " each)" : ""))
        }
        if (r[4] > 0) extra.push("Level " + r[4])
        extra.push(r[5] === "Auto" ? "learnt by level" : r[5] === "Advancement" ? "mastery advancement" : r[5])
        out.push({ kind: "text", text: extra.join(" · ") })
        return out
    }

    onSettingsChanged: refresh()

    // ---- what it looks like ----
    function toneColor(t) {
        return t === "gain" ? "#7fdc9a" : t === "loss" ? "#ff8a7a" : t === "none" ? Theme.dim() : t === "sub" ? Theme.muted() : Theme.text()
    }
    readonly property var gradeColors: ["#c8ccd2", "#c8ccd2", "#7fdc9a", "#4fa8ff", "#f2c46b", "#ffb066", "#ff7a6b", "#7fe0c8"]
    function tagColor(kind) { return kind === "high" ? "#ffb0a5" : kind === "low" || kind === "morph" ? "#a9ebbd" : kind === "npc" ? "#ffe199" : Theme.muted() }

    Column {
        width: parent.width
        spacing: 8

        // The server, Update, the faction, the favourites.
        Item {
            width: parent.width
            height: 32
            z: 30
            // First the region, then that region's servers (the game's own
            // server is picked by itself once the game names it).
            Dropdown {
                id: regionPick
                anchors.left: parent.left
                width: Math.min(190, (parent.width - barTools.width - 16) * 0.4)
                label: "Region"
                current: panel.region
                options: {
                    const out = [{ id: "", name: panel.regions.length ? "Pick" : "…" }]
                    for (const r of panel.regions) out.push({ id: r, name: r })
                    return out
                }
                onChosen: (id) => {
                    panel.change("region", id)
                    const s = panel.server()
                    if (s && s.region !== id) {
                        panel.prices = new Map()
                        panel.hist = null
                        panel.fetchedAt = 0
                        panel.opened = ({})
                        panel.change("server", null)
                        panel.refresh()
                    }
                }
            }
            Dropdown {
                id: serverPick
                anchors.left: regionPick.right
                anchors.leftMargin: 6
                anchors.right: barTools.left
                anchors.rightMargin: 8
                label: "Server"
                current: panel.settings.server != null ? String(panel.settings.server) : ""
                options: {
                    const out = [{ id: "", name: !panel.servers.length ? "Servers …" : panel.region ? "Pick your server" : "Pick a region first" }]
                    const list = panel.servers.filter((s) => s.hasData && s.region === panel.region).slice()
                    list.sort((a, b) => String(a.faction).localeCompare(String(b.faction)) || a.name.localeCompare(b.name))
                    for (const s of list) out.push({ id: String(s.id), name: s.name + " · " + (s.faction || "") })
                    return out
                }
                onChosen: (id) => {
                    if (id) panel.takeServer(Number(id))
                    else {
                        panel.prices = new Map()
                        panel.hist = null
                        panel.fetchedAt = 0
                        panel.opened = ({})
                        panel.change("server", null)
                    }
                    panel.loadPrices(true)
                }
            }
            Row {
                id: barTools
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Chip { text: panel.busy ? "…" : "Update"; onClicked: { if (!panel.servers.length) panel.loadServers().then(() => panel.loadPrices(true)); else panel.loadPrices(true) } }
                Chip { text: "Asmodian"; on: panel.faction() === "Asmodian"; onClicked: { panel.opened = ({}); panel.change("faction", "Asmodian") } }
                Chip { text: "Elyos"; on: panel.faction() === "Elyos"; onClicked: { panel.opened = ({}); panel.change("faction", "Elyos") } }
                Chip { text: "★"; on: panel.settings.pins !== false; onClicked: panel.change("pins", panel.settings.pins === false) }
            }
        }

        // Where the prices come from, or what went wrong.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: panel.error ? "#ff8a7a" : Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
            text: {
                if (panel.error) return panel.error
                if (panel.busy) return "Getting prices …"
                if (!panel.server()) return "Pick your server for its prices."
                if (!panel.fetchedAt) return "No prices yet."
                let listed = 0
                for (const p of panel.prices.values()) if (p.price != null) listed++
                const from = panel.source === "copy" ? " · Clicktrough's copy" : panel.source ? " · " + panel.source : ""
                return "Prices of " + panel.when(panel.snapshot || new Date(panel.fetchedAt).toISOString()) + " · " + listed + " items listed" + from
            }
        }

        // The tabs.
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: [["gather", "Gatherables"], ["odyle", "Odyle morph"], ["recipes", "Recipes"], ["materials", "Materials"], ["listings", "All listings"], ["anomalies", "Anomalies"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.settings.tab === modelData[0]
                        width: tabText.implicitWidth
                        height: 32
                        Text {
                            id: tabText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.change("tab", modelData[0]) }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // The tab's own choices.
        Flow {
            width: parent.width
            spacing: 6
            visible: children.length > 0
            Repeater {
                model: panel.settings.tab === "recipes" ? [["all", "All"], ["Alchemy", "Alchemy"], ["Blacksmithing", "Blacksmithing"], ["Jewelcrafting", "Jewelcrafting"], ["Tailoring", "Tailoring"], ["Cooking", "Cooking"]]
                    : panel.settings.tab === "materials" ? [["all", "All"], ["gathered", "Gathered"], ["crafted", "Crafted materials"], ["npc", "NPC tools"], ["gear", "Earlier tiers"]]
                    : panel.settings.tab === "listings" ? [["all", "All"]].concat(MK.C.CATEGORIES) : []
                delegate: Chip {
                    required property var modelData
                    readonly property string field: panel.settings.tab === "recipes" ? "prof" : panel.settings.tab === "materials" ? "kind" : "cat"
                    text: modelData[1]
                    on: panel.settings[field] === modelData[0]
                    onClicked: { panel.shown = { recipes: 80, materials: 80, listings: 80 }; panel.change(field, modelData[0]) }
                }
            }
        }
        Flow {
            width: parent.width
            spacing: 6
            visible: panel.settings.tab === "recipes" || panel.settings.tab === "listings"
            Chip {
                visible: panel.settings.tab === "recipes"
                text: "Sold on the market"
                on: !!panel.settings.priced
                onClicked: panel.change("priced", !panel.settings.priced)
            }
            Repeater {
                model: panel.settings.tab === "recipes" ? [["profit", "Profit"], ["margin", "Margin"], ["level", "Level"], ["name", "Name"]]
                    : panel.settings.tab === "listings" ? [["name", "Name"], ["price", "Price"], ["listings", "Listed"], ["change", "Change"], ["ratio", "× usual"]] : []
                delegate: Chip {
                    required property var modelData
                    readonly property string field: panel.settings.tab === "recipes" ? "sort" : "allSort"
                    text: "Sort: " + modelData[1]
                    on: panel.settings[field] === modelData[0]
                    onClicked: panel.change(field, modelData[0])
                }
            }
            Chip {
                visible: panel.settings.tab === "listings"
                text: "Listed now"
                on: !!panel.settings.listedOnly
                onClicked: panel.change("listedOnly", !panel.settings.listedOnly)
            }
            Chip {
                visible: panel.settings.tab === "listings"
                text: "Grade: " + (panel.settings.minGrade > 0 ? MK.C.GRADES[panel.settings.minGrade] + "+" : "Any")
                on: panel.settings.minGrade > 0
                onClicked: panel.change("minGrade", (Number(panel.settings.minGrade) + 1) % 7)
            }
            Chip {
                visible: panel.settings.tab === "recipes"
                text: "NPC prices"
                on: panel.npcShown
                onClicked: { panel.npcShown = !panel.npcShown; panel.refresh(); if (panel.npcShown) Qt.callLater(() => list.positionViewAtEnd()) }
            }
            Chip {
                visible: panel.settings.tab === "recipes"
                text: "Fee " + panel.settings.fee + "%"
                onClicked: panel.change("fee", panel.settings.fee >= 15 ? 0 : panel.settings.fee + 2.5)
            }
        }

        // The search of the tab (not in Odyle morph and Anomalies).
        Item {
            visible: ["gather", "recipes", "materials", "listings"].indexOf(panel.settings.tab) >= 0
            width: parent.width
            height: visible ? 32 : 0
            Rectangle {
                anchors.fill: parent
                color: "#1b1a20"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: search.activeFocus ? Theme.accent : "#3a3842" }
            }
            HudIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 13; lineWidth: 2; color: Theme.muted() }
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text()
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Theme.body
                font.pixelSize: 13
                clip: true
                text: (panel.settings.search || {})[panel.settings.tab] || ""
                onTextEdited: {
                    const s = Object.assign({}, panel.settings.search || {})
                    s[panel.settings.tab] = text
                    panel.shown = { recipes: 80, materials: 80, listings: 80 }
                    panel.change("search", s)
                }
                Keys.onEscapePressed: focus = false
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text.length === 0
                    text: ({ gather: "Search: Orichalcum, Aria, Odyle …", recipes: "Search a product or material …", materials: "Search a material …", listings: "Search anything on the market …" })[panel.settings.tab] || ""
                    color: Theme.dim()
                    font: search.font
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }

        Text {
            visible: panel.note.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: panel.note
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        // The column heads.
        Row {
            width: parent.width
            Repeater {
                model: panel.head
                delegate: Text {
                    required property var modelData
                    required property int index
                    width: parent.width * (panel.widths[index] || 0)
                    horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                    rightPadding: index === 0 ? 0 : 8
                    text: modelData.toUpperCase()
                    color: Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                    elide: Text.ElideRight
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }

        // The favourites, pinned above the list. An opened one shows all it
        // has (up to most of the list's room); the list below gives up that
        // room, so the panel keeps its height.
        ListView {
            id: pinList
            visible: count > 0
            width: parent.width
            height: visible ? Math.min(contentHeight, Math.max(150, (360 + panel.grow) * 0.7)) : 0
            clip: true
            interactive: false
            model: panel.pinRows
            delegate: rowDelegate
            WheelScroll { flick: pinList; step: 90 }
            // More below (the wheel shows it): a line and a fade at the edge.
            Rectangle {
                visible: pinList.contentHeight > pinList.height + 1 && !pinList.atYEnd
                anchors.bottom: parent.bottom
                width: parent.width
                height: 18
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.panel(Math.max(0.6, panel.ground)) }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.5) }
            }
        }

        // The list.
        ListView {
            id: list
            width: parent.width
            height: 360 + panel.grow - Math.max(0, pinList.height - 150)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            model: panel.rows
            delegate: rowDelegate
            WheelScroll { flick: list; step: 90 }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Prices: aion2.exchange (players' collected market prices), copied hourly by Clicktrough · recipes, names and pictures: the game client, via SkeeveAN's Aion-DPS-Meter (MIT) and Aion2Data. Unofficial, not affiliated with NCSOFT or aion2.exchange."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 10
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }

    Component {
        id: rowDelegate
        Item {
            id: row
            required property var modelData
            readonly property var r: modelData
            width: ListView.view ? ListView.view.width : 0
            height: r.kind === "item" ? (r.sub ? 40 : 32) : r.kind === "npc" ? 30 : r.kind === "course" ? 64 : r.kind === "more" ? 34 : r.kind === "text" || r.kind === "empty" ? textLine.implicitHeight + 8 : 26

            Rectangle {
                anchors.fill: parent
                visible: r.kind === "item"
                color: r.open ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08) : rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            }
            Rectangle { visible: r.kind === "item"; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }

            // A group's title.
            Text {
                visible: r.kind === "group"
                anchors.verticalCenter: parent.verticalCenter
                text: r.kind === "group" ? r.title.toUpperCase() : ""
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.4
                style: Theme.textStyle(); styleColor: Theme.shadow
            }

            // A line of words (why, a recipe's extras, nothing matches).
            Text {
                id: textLine
                visible: r.kind === "text" || r.kind === "empty"
                x: r.kind === "text" ? 34 : 0
                y: 4
                width: parent.width - x
                wrapMode: Text.WordWrap
                text: r.kind === "text" || r.kind === "empty" ? r.text : ""
                color: r.kind === "empty" ? Theme.muted() : Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
                style: Theme.textStyle(); styleColor: Theme.shadow
            }

            // An NPC price, changeable.
            Item {
                visible: r.kind === "npc"
                anchors.fill: parent
                Text {
                    x: 34
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 34 - 130
                    elide: Text.ElideRight
                    text: r.kind === "npc" ? r.label : ""
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    height: 24
                    color: "#1b1a20"
                    border.color: npcInput.activeFocus ? Theme.accent : "#3a3842"
                    TextInput {
                        id: npcInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignRight
                        color: r.kind === "npc" && r.value !== r.base ? Theme.accent : Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 12
                        validator: IntValidator { bottom: 0; top: 100000000 }
                        text: r.kind === "npc" ? String(r.value) : ""
                        onEditingFinished: {
                            const v = Number(text)
                            const n = Object.assign({}, panel.settings.npc)
                            if (isFinite(v) && v > 0 && v !== r.base) n[String(r.id)] = v
                            else delete n[String(r.id)]
                            panel.change("npc", n)
                        }
                    }
                }
            }

            // Show more.
            Chip {
                visible: r.kind === "more"
                anchors.centerIn: parent
                text: r.kind === "more" ? "Show more (" + r.left + ")" : ""
                onClicked: {
                    const s = Object.assign({}, panel.shown)
                    s[r.tab] += 80
                    panel.shown = s
                    panel.refresh()
                }
            }

            // An item: star, icon, name and its cells; a sub row (inside an open one) likewise, smaller.
            Item {
                visible: r.kind === "item" || r.kind === "sub" || r.kind === "subhead"
                anchors.fill: parent
                readonly property bool inner: r.kind !== "item"
                readonly property var w: inner ? (r.five ? [0.4, 0.12, 0.16, 0.16, 0.16] : [0.46, 0.14, 0.2, 0.2]) : panel.widths
                Item {
                    id: nameCell
                    x: parent.inner ? 34 : 0
                    width: parent.width * (parent.w[0] || 0.4) - x
                    height: parent.height
                    HudIcon {
                        id: starIcon
                        visible: r.kind === "item"
                        anchors.verticalCenter: parent.verticalCenter
                        name: "star"
                        size: 13
                        lineWidth: 1.6
                        filled: r.kind === "item" && panel.isFav(r.id)
                        color: r.kind === "item" && panel.isFav(r.id) ? Theme.accent : (starMouse.containsMouse ? Theme.text() : Theme.dim())
                        MouseArea { id: starMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.toggleFav(r.id) }
                    }
                    Rectangle {
                        id: iconBox
                        visible: r.kind !== "subhead"
                        x: r.kind === "item" ? 20 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: r.kind === "item" ? 26 : 18
                        height: width
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: panel.gradeColors[r.kind === "item" ? r.grade || MK.C.grade(r.id) : MK.C.grade(r.id || 0)] || "#555"
                        Text {
                            anchors.centerIn: parent
                            visible: pic.status !== Image.Ready
                            text: r.label ? r.label.slice(0, 1) : ""
                            color: Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 11
                        }
                        Image {
                            id: pic
                            anchors.fill: parent
                            anchors.margins: 1
                            asynchronous: true
                            sourceSize.width: 52
                            source: r.id && r.kind !== "subhead" ? panel.iconOf(r.id) : ""
                        }
                    }
                    HudIcon {
                        id: mapIcon
                        visible: !!r.map && r.kind !== "subhead"
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        z: 2
                        name: "map"
                        size: 13
                        lineWidth: 1.6
                        color: mapMouse.containsMouse ? Theme.accent : Theme.dim()
                        MouseArea {
                            id: mapMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.showOnMap(MK.C.name(r.id))
                        }
                    }
                    Column {
                        x: r.kind === "subhead" ? 0 : iconBox.x + iconBox.width + 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 4 - (mapIcon.visible ? 22 : 0)
                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                id: nameText
                                width: Math.min(implicitWidth, parent.width - (tagBox.visible ? tagBox.width + 6 : 0))
                                elide: Text.ElideRight
                                text: r.kind === "subhead" ? String(r.cells[0]).toUpperCase() : (r.label || "") + (r.after || "")
                                color: r.kind === "subhead" ? Theme.dim() : r.grade ? panel.gradeColors[r.grade] : Theme.text()
                                font.family: r.kind === "subhead" ? Theme.display : Theme.body
                                font.pixelSize: r.kind === "item" ? 13 : 11
                                font.weight: r.kind === "subhead" ? Font.Bold : Font.Normal
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Rectangle {
                                id: tagBox
                                visible: !!r.tag
                                anchors.verticalCenter: nameText.verticalCenter
                                width: tagText.implicitWidth + 8
                                height: 16
                                color: "transparent"
                                border.color: r.tag ? panel.tagColor(r.tag.kind) : "transparent"
                                Text {
                                    id: tagText
                                    anchors.centerIn: parent
                                    text: r.tag ? r.tag.t : ""
                                    color: r.tag ? panel.tagColor(r.tag.kind) : "transparent"
                                    font.family: Theme.body
                                    font.pixelSize: 10
                                }
                            }
                        }
                        Text {
                            visible: !!r.sub
                            width: parent.width
                            elide: Text.ElideRight
                            text: r.sub || ""
                            color: Theme.dim()
                            font.family: Theme.body
                            font.pixelSize: 10
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                    }
                }
                Repeater {
                    model: r.kind === "subhead" ? r.cells.slice(1) : r.cells || []
                    delegate: Text {
                        required property var modelData
                        required property int index
                        readonly property var w: parent.w
                        x: {
                            let at = parent.width * (w[0] || 0)
                            for (let i = 1; i <= index; i++) at += parent.width * (w[i] || 0)
                            return at
                        }
                        width: parent.width * (w[index + 1] || 0)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 8
                        elide: Text.ElideRight
                        text: typeof modelData === "string" ? modelData.toUpperCase() : modelData.t
                        color: typeof modelData === "string" ? Theme.dim() : panel.toneColor(modelData.tone)
                        font.family: typeof modelData === "string" ? Theme.display : Theme.body
                        font.pixelSize: typeof modelData === "string" ? 11 : r.kind === "item" ? 13 : 12
                        font.weight: typeof modelData === "string" ? Font.Bold : Font.Normal
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                }
            }

            // An item's course: its lowest listing over hours or days, the usual price dashed.
            Canvas {
                id: spark
                visible: r.kind === "course"
                x: 34
                width: Math.min(parent.width - 34, 420)
                height: parent.height
                renderStrategy: Canvas.Immediate
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    if (r.kind !== "course") return
                    const vals = r.values
                    const pts = []
                    for (let i = 0; i < vals.length; i++) if (vals[i] > 0) pts.push([i, vals[i]])
                    ctx.font = "11px sans-serif"
                    ctx.fillStyle = "#8a8794"
                    if (!pts.length) { ctx.fillText(r.title + ": not listed", 0, 14); return }
                    const all = pts.map((p) => p[1]).concat(r.usual ? [r.usual] : [])
                    const lo = Math.min.apply(null, all), hi = Math.max.apply(null, all)
                    ctx.fillText(r.title + " · " + panel.kina(lo) + " to " + panel.kina(hi), 0, 12)
                    const top = 18, H = height - top - 4, W = width - 4
                    const y = (v) => hi === lo ? top + H / 2 : top + H - ((Math.log(v) - Math.log(lo)) / (Math.log(hi) - Math.log(lo))) * H
                    const x = (i) => vals.length <= 1 ? W / 2 : 2 + (i / (vals.length - 1)) * W
                    if (r.usual) {
                        ctx.strokeStyle = "rgba(255,255,255,0.35)"
                        ctx.lineWidth = 1
                        if (ctx.setLineDash) ctx.setLineDash([4, 4])
                        ctx.beginPath(); ctx.moveTo(0, y(r.usual)); ctx.lineTo(width, y(r.usual)); ctx.stroke()
                        if (ctx.setLineDash) ctx.setLineDash([])
                    }
                    ctx.strokeStyle = Theme.accent
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    pts.forEach((p, i) => { if (i === 0) ctx.moveTo(x(p[0]), y(p[1])); else ctx.lineTo(x(p[0]), y(p[1])) })
                    ctx.stroke()
                }
                Component.onCompleted: if (visible) requestPaint()
            }

            MouseArea {
                id: rowMouse
                visible: r.kind === "item"
                // Under the star and the map button, which take their own clicks.
                z: -1
                anchors.fill: parent
                anchors.leftMargin: 20
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.toggle(r.key)
            }
        }
    }
}
