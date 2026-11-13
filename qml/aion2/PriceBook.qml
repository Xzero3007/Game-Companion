import QtQuick
import GameCompanion
import "lootkit.js" as LK
import "marketkit.js" as MK

// The Market's prices as one service for the other areas (LOOT: Items,
// Drops, Closet, Cards): the same sources as the Market (Clicktrough's
// hourly copy first, else aion2.exchange; Aion2.webGet allows only those)
// and the same anomaly check (the copy's price history). It shares the
// Market's kept files (market-servers, market-prices, market-history), so
// what one loaded the other has. Lives as long as the app; asks only while
// someone wants prices (`wanted`) and at most every 20 minutes.
QtObject {
    id: book

    /// item id (string) -> { price, listings, sold, soldAvg, change, last }
    property var prices: new Map()
    /// The copy's price history (anomaly.js), or null.
    property var hist: null
    /// aion2.exchange's server id the prices are of (0 none yet).
    property int server: 0
    property string serverName: ""
    property real fetchedAt: 0
    property string snapshot: ""
    property bool busy: false
    property string error: ""
    /// Raised when prices change (bindings follow it).
    property int revision: 0
    /// Someone shows prices now: they are kept fresh while true.
    property bool wanted: false
    /// The game's number of the server played on (0 unknown).
    property int gameServer: 0

    readonly property string copyUrl: "https://raw.githubusercontent.com/Xzero3007/A2Tools-DPS-Meter_Clicktrough/market-data/"
    readonly property string apiUrl: "https://aion2.exchange/api/"
    readonly property int staleMs: 20 * 60000
    property var servers: []

    // ---- downloads, answered by id (ids far from the Market panel's) ----
    property int nextId: 900000
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
            const w = book.waiting[id]
            if (!w) return
            delete book.waiting[id]
            if (!ok) { w.reject(new Error(body)); return }
            try { w.resolve(JSON.parse(body)) } catch (e) { w.reject(new Error("the answer is no JSON")) }
        }
    }

    /// What one item is worth (Inventory's rules): see lootkit C.worth.
    function worth(item, count, fee) {
        revision
        return LK.C.worth(item, count, prices, fee === undefined ? 10 : fee, hist)
    }
    /// A plain unit price (lowest listing, else average sale, else last), or null.
    function unit(item) {
        const w = worth(item, 1)
        return w.sellable ? w.unit : null
    }

    function pickServer() {
        if (!servers.length) return 0
        const mine = gameServer ? LK.C.serverOf(servers, gameServer) : null
        if (mine) return mine.id
        try {
            const m = JSON.parse(Aion2.loadStore("market") || "{}")
            if (m.server) return m.server
        } catch (e) { }
        return 0
    }

    function restore() {
        try {
            const c = JSON.parse(Aion2.loadStore("market-servers") || "{}")
            if (Array.isArray(c.servers)) servers = LK.C.readServers(c)
        } catch (e) { }
        const id = pickServer()
        try {
            const p = JSON.parse(Aion2.loadStore("market-prices") || "{}")
            if (Array.isArray(p.rows) && (!id || p.server === id)) {
                const m = new Map()
                for (const r of p.rows) m.set(String(r[0]), { price: r[1], listings: r[2], sold: r[3], soldAvg: r[4], change: r[5], last: r[6] === undefined ? null : r[6] })
                prices = m
                server = p.server || 0
                fetchedAt = p.at || 0
                snapshot = p.snapshot || ""
            }
            const h = JSON.parse(Aion2.loadStore("market-history") || "{}")
            if (h.server === server && h.doc) hist = MK.A.readHistory(h.doc)
        } catch (e) { }
        nameServer()
        revision++
    }
    function nameServer() {
        for (const s of servers) if (s.id === server) { serverName = s.name; return }
        serverName = ""
    }

    function loadServers() {
        if (servers.length) return Promise.resolve()
        return get(copyUrl + "servers.json").then((res) => {
            const list = LK.C.readServers(res)
            if (list.length) {
                servers = list
                Aion2.keepStore("market-servers", JSON.stringify({ at: Date.now(), servers: list }))
            }
        }, () => {})
    }

    function load(force) {
        if (busy) return
        if (!force && fetchedAt && Date.now() - fetchedAt < staleMs && prices.size && server === pickServer()) return
        busy = true
        error = ""
        loadServers().then(() => {
            const id = pickServer()
            if (!id) throw new Error("no server yet: play a character, or pick one in Market")
            return get(copyUrl + "prices/" + id + ".json").then((doc) => LK.C.readCopy(doc), () => null).then((copy) => {
                if (copy) return { prices: copy.prices, snapshot: copy.snapshot || "" }
                return get(apiUrl + "items?server=" + id + "&limit=1000&offset=0").then((res) => {
                    const rows = Array.isArray(res && res.items) ? res.items : []
                    if (!rows.length) throw new Error("no prices for this server yet")
                    return { prices: LK.C.readRows(rows), snapshot: rows.map((r) => r.captured_at).filter(Boolean).sort().pop() || "" }
                })
            }).then((got) => {
                prices = got.prices
                snapshot = got.snapshot
                server = id
                fetchedAt = Date.now()
                nameServer()
                const keep = Array.from(prices).map((e) => [e[0], e[1].price, e[1].listings, e[1].sold, e[1].soldAvg, e[1].change, e[1].last])
                Aion2.keepStore("market-prices", JSON.stringify({ server: id, at: fetchedAt, snapshot: snapshot, source: "copy", rows: keep }))
                revision++
                return get(copyUrl + "history/" + id + ".json").then((doc) => {
                    const h = MK.A.readHistory(doc)
                    if (h) {
                        hist = h
                        Aion2.keepStore("market-history", JSON.stringify({ server: id, doc: Object.assign({ v: 1 }, h) }))
                        revision++
                    }
                }, () => {})
            })
        }).catch((e) => {
            error = "Prices: " + (e && e.message ? e.message : e) + (prices.size ? " (showing the earlier ones)" : "")
        }).then(() => { busy = false })
    }

    /// Made-up prices (GC_DEMO): nothing is asked.
    property bool demo: false
    onWantedChanged: if (wanted && !demo) load(false)
    onGameServerChanged: if (gameServer && wanted && !demo) load(false)
    // While wanted: every 30 minutes (no timer otherwise).
    property Timer refresh: Timer { interval: 30 * 60000; repeat: true; running: book.wanted && !book.demo; onTriggered: book.load(true) }

    Component.onCompleted: if (!demo) restore()
}
