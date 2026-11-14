import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "lootkit.js" as LK

// The AION 2 module's LOOT (canvas page "Besitz und Beute"): the Clicktrough
// Inventory, Closet and Shugo Cards plugins in one panel. ITEMS: inventory,
// character storage and server storage with what the sellable ones bring.
// DROPS: the session, the farm days and the dungeon runs. CLOSET: the Black
// Cloud Merchant's offers, the skins you lack, combining and extracting.
// CARDS: the card rounds of the Shugo Festival and the Dimensional Invasion.
// What it shows is LootStore's; prices are the Market's (PriceBook). The
// tabs follow Settings → Plugins (Inventory: ITEMS and DROPS, Closet,
// Shugo Cards).
Panel {
    id: panel
    panelId: "loot"
    title: "Loot"
    tag: width < 460 ? "" : "AION 2"
    width: 660
    minWidth: 440
    maxWidth: 1400
    stretchy: true
    minGrow: -200

    property var store: null
    property var book: null
    /// Which tabs Settings → Plugins allows.
    property bool itemsOn: true
    property bool closetOn: true
    property bool cardsOn: true

    readonly property var st: store ? store.settings : ({})
    readonly property var tabs: {
        const out = []
        if (itemsOn) out.push(["items", "Items"], ["drops", "Drops"])
        if (closetOn) out.push(["closet", "Closet"])
        if (cardsOn) out.push(["cards", "Cards"])
        return out
    }
    readonly property string tab: {
        for (const t of tabs) if (t[0] === st.tab) return t[0]
        return tabs.length ? tabs[0][0] : ""
    }
    badge: store && tab === "cards" ? "Rounds " + store.cardRounds().length : store && tab === "closet" && store.closet ? store.closet.size + " / " + store.goal : ""

    // ---- words and numbers ----
    readonly property var gradeColors: ["#c8ccd2", "#c8ccd2", "#7fdc9a", "#4fa8ff", "#f2c46b", "#ffb066", "#ff7a6b", "#7fe0c8"]
    readonly property color gold: "#f2c46b"
    readonly property color good: "#7fdc9a"
    readonly property color bad: "#ff8a7a"
    function kina(n) { return n == null ? "—" : LK.C.kina(n) }
    function shortK(n) { return n == null || !isFinite(n) ? "—" : LK.C.short(n) }
    function two(n) { return (n < 10 ? "0" : "") + n }
    readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    function clock(ms) { const d = new Date(ms); return two(d.getHours()) + ":" + two(d.getMinutes()) }
    function when(ms) { if (!ms) return "—"; const d = new Date(ms); return two(d.getDate()) + " " + months[d.getMonth()] + ", " + clock(ms) }
    function dayLabel(day) { const d = new Date(day); return weekdays[d.getDay()] + " " + two(d.getDate()) + " " + months[d.getMonth()] }
    function span(ms) { const m = Math.max(0, Math.round(ms / 60000)); return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min" }
    function hours(ms) { return ms ? span(ms) : "—" }
    function pct(x) { return x == null ? "—" : Math.round(x * 1000) / 10 + " %" }
    function pctBox(x) { return x == null ? "—" : (x * 100).toFixed(x < 0.1 ? 1 : 0) + " %" }
    function pctText(x) { return (x >= 0 ? "+" : "−") + Math.abs(Math.round(x * 100)) + " %" }
    function pText(p) { return p < 0.001 ? "p < 0.001" : "p = " + p.toFixed(p < 0.01 ? 3 : 2) }
    function plural(n, one, many) { return n + " " + (n === 1 ? one : (many || one + "s")) }

    property int iconsRevision: 0
    Connections { target: Aion2; function onIconReady(name) { panel.iconsRevision++ } }
    function iconUrl(name) { iconsRevision; return name ? Aion2.icon(name) : "" }

    // ---- what the controls do ----
    function act(a) {
        if (!store || !a) return
        if (a.set) {
            store.set(a.set, a.v)
            if (a.set === "farmMode" && a.v !== "off") store.showFarm()
            if (a.set === "list" || a.set === "source" || a.set === "tab") shown = 250
        } else if (a.newSession) store.endSession(Date.now())
        else if (a.session !== undefined) { store.pastView = a.session === "" ? null : Number(a.session); store.changed() }
        else if (a.view !== undefined) { store.set("view", a.view && a.view !== store.currentKey() ? a.view : null) }
        else if (a.day !== undefined) { dayView = Number(a.day) === LK.F.dayOf(Date.now()) ? null : Number(a.day); refresh() }
        else if (a.step) stepRound(a.step)
        else if (a.farmRow) store.setFarmRow(a.farmRow, a.v)
        else if (a.farmShow) { if (store.farmMode() === "off") store.set("farmMode", "always"); store.showFarm() }
        else if (a.kindOf) { const k = Object.assign({}, st.kinds); k[a.kindOf] = a.v; store.set("kinds", k) }
        else if (a.window) store.showWindow(a.window)
        else if (a.meter) store.readMeter()
        else if (a.more) { shown += 250; refresh() }
    }
    property int shown: 250
    property var dayView: null

    // ---- the build: the controls and the rows of the tab shown ----
    property var controls: []
    property string controlsKey: ""
    property var rows: []
    property string note: ""
    function refresh() { if (!buildLater.running) buildLater.start() }
    Timer { id: buildLater; interval: 1; onTriggered: panel.build() }
    Connections { target: panel.store; function onRevisionChanged() { if (panel.visible) panel.refresh() } }
    Connections { target: panel.book; function onRevisionChanged() { if (panel.visible) panel.refresh() } }
    onVisibleChanged: if (visible) refresh()
    onTabChanged: refresh()
    Component.onCompleted: refresh()

    function build() {
        if (!store) return
        let out = { controls: [], rows: [], note: "", search: "" }
        if (tab === "items") buildItems(out)
        else if (tab === "drops") buildDrops(out)
        else if (tab === "closet") buildCloset(out)
        else if (tab === "cards") buildCards(out)
        // The controls only change with what they show (an open menu stays open).
        const key = JSON.stringify(out.controls)
        if (key !== controlsKey) { controlsKey = key; controls = out.controls }
        searchKey = out.search
        note = out.note
        rows = out.rows
    }

    // A chip, a menu, a line of words for the controls.
    function chip(text, on, a) { return { type: "chip", text: text, on: !!on, a: a } }
    function drop(label, current, options, a, w) { return { type: "drop", label: label, current: String(current), options: options, a: a, w: w || 200 } }
    function words(text) { return { type: "text", text: text } }
    // Rows.
    function group(title) { return { kind: "group", title: title } }
    function text(t, color) { return { kind: "text", text: t, color: color || "" } }
    function head(cells, w) { return { kind: "head", cells: cells.map((c) => [c, ""]), w: w } }
    function cells(list, w, strong) { return { kind: "cells", cells: list.map((c) => (Array.isArray(c) ? c : [c, ""])), w: w, strong: !!strong } }
    function item(id, name, tags, list, w, extra) {
        return Object.assign({ kind: "item", id: id, icon: id ? LK.C.icon(id) : "", grade: id ? LK.C.grade(id) : 0, name: name || (id ? LK.C.name(id) : ""), tags: tags || [], cells: list.map((c) => (Array.isArray(c) ? c : [c, ""])), w: w }, extra || {})
    }
    function gradeTag(g) { return LK.C.GRADES[g] ? [LK.C.GRADES[g], gradeColors[g] || ""] : null }

    // ---------- ITEMS ----------
    function charOptions() {
        const cur = store.currentKey()
        const list = store.chars.slice().sort((a, b) => (b.key === cur) - (a.key === cur) || b.at - a.at)
        if (cur && !list.some((c) => c.key === cur)) list.unshift({ key: cur, name: store.character.name })
        if (!list.length) return [{ id: "", name: "No character yet" }]
        return list.map((c) => ({ id: c.key, name: c.name + (c.key === cur ? " (playing)" : "") }))
    }
    function listRows(out, counts, opts) {
        const prices = book ? book.prices : new Map()
        const res = LK.C.list(counts, prices, { fee: st.fee, sort: st.sort, search: opts.search, sellableOnly: !!st.sellableOnly, hist: book ? book.hist : null })
        const w = [0.13, 0.13, 0.17]
        const parts = [res.rows.filter((r) => !r.currency).length + " items"]
        if (prices.size) parts.push(res.sum.sellable + " sellable", "worth " + kina(res.sum.total) + " Kina (after the " + st.fee + " % fee " + kina(res.sum.net) + ")")
        if (opts.kinah) parts.push("Kina " + kina(opts.kinah))
        out.rows.push(text(parts.join(" · "), Theme.textSoft()))
        if (opts.hint) out.rows.push(text(opts.hint))
        if (!res.rows.length) { out.rows.push(text(opts.empty)); return }
        out.rows.push(head(["Item", "Count", "Each", "Worth"], w))
        let lastGroup = null
        for (const r of res.rows.slice(0, shown)) {
            if (r.currency && lastGroup !== "c") { out.rows.push(group("Currencies")); lastGroup = "c" }
            const tags = []
            const g = gradeTag(r.grade)
            if (g) tags.push(g)
            if (r.sellable) tags.push(["Sellable", good])
            else if (r.bound) tags.push(["Bound", ""])
            if (r.odd) tags.push(["Usual price", gold])
            if (opts.sources) for (const s of opts.sources) if (s.map[r.item]) tags.push([s.name + " " + kina(s.map[r.item]), ""])
            out.rows.push(item(r.item, r.name, tags, [kina(r.count), r.unit != null ? shortK(r.unit) : "", r.total != null ? [kina(r.total), gold] : ""], w))
        }
        if (res.rows.length > shown) out.rows.push({ kind: "more", left: res.rows.length - shown })
    }
    function buildItems(out) {
        const list = ["inv", "char", "acc"].indexOf(st.list) >= 0 ? st.list : "inv"
        out.controls.push([drop("Character", store.viewKey() || "", charOptions(), "view", 230),
            chip("Inventory", list === "inv", { set: "list", v: "inv" }), chip("Character storage", list === "char", { set: "list", v: "char" }), chip("Server storage", list === "acc", { set: "list", v: "acc" })])
        out.controls.push([chip("Sellable only", st.sellableOnly, { set: "sellableOnly", v: !st.sellableOnly }),
            chip("Sort: " + ({ value: "Worth", name: "Name", count: "Count", grade: "Grade" })[st.sort || "value"], false, { set: "sort", v: ({ value: "name", name: "count", count: "grade", grade: "value" })[st.sort || "value"] }),
            chip(store.meterBusy ? "Reading the meter…" : "Take over the meter's data", false, { meter: true })])
        if (store.meterNote) out.rows.push(text(store.meterNote, Theme.textSoft()))
        out.search = "items"
        const sk = store.stock(store.viewKey())
        let hint = ""
        if (!sk) hint = "Enter the world (log in, or switch character) while AION 2 runs with the companion: the game sends the inventory and both storages then."
        else if (!sk.exactAt && list !== "inv") hint = "Not seen yet: the game sends the storages when you enter the world. Log in again (or switch character) while the companion runs."
        else if (!sk.exactAt) hint = "Only what changed since the companion started: log in again (or switch character) for the whole inventory."
        else if (list !== "inv") hint = "Moving items to or from a storage sends nothing to read: the storages are exact as of the last login, and after sorting your inventory."
        else hint = "Complete as of " + when(sk.exactAt) + "."
        listRows(out, store.counts(list), { search: (st.search || {}).items || "", hint: hint, kinah: list === "inv" && sk && sk.inv ? sk.inv[LK.C.KINA] : 0, empty: st.sellableOnly ? "Nothing sellable here." : "No items." })
    }

    // ---------- DROPS ----------
    function buildDrops(out) {
        const sub = ["session", "days", "dungeons", "window"].indexOf(st.drops) >= 0 ? st.drops : "session"
        out.controls.push([chip("Session", sub === "session", { set: "drops", v: "session" }), chip("Farm days", sub === "days", { set: "drops", v: "days" }), chip("Dungeons", sub === "dungeons", { set: "drops", v: "dungeons" }),
            chip("Farm window", sub === "window", { set: "drops", v: "window" })])
        if (sub === "session") buildSession(out)
        else if (sub === "days") buildDays(out)
        else if (sub === "window") buildFarmWindow(out)
        else buildDungeons(out)
    }
    /// The farm window's choices (MN, 0.8.13): when it shows and what.
    function buildFarmWindow(out) {
        const mode = store.farmMode()
        out.controls.push([words("Show"), chip("Always while AION 2 runs", mode === "always", { set: "farmMode", v: "always" }), chip("Only while farming", mode === "popup", { set: "farmMode", v: "popup" }), chip("Off", mode === "off", { set: "farmMode", v: "off" }),
            chip("Show now", false, { farmShow: true })])
        const op = store.farmOpacity(), fsz = store.farmText()
        out.controls.push([words("Opacity")].concat([100, 75, 50, 25, 10].map((v) => chip(v + " %", op === v, { set: "farmOpacity", v: v })))
            .concat([words("Text")]).concat([["S", 0.85], ["M", 1], ["L", 1.2], ["XL", 1.45]].map((x) => chip(x[0], Math.abs(fsz - x[1]) < 0.01, { set: "farmText", v: x[1] }))))
        out.controls.push([words("Rows")].concat(store.farmRowList.map((r) => chip(r[1], store.farmRow(r[0]), { farmRow: r[0], v: !store.farmRow(r[0]) }))))
        out.rows.push(group("When it shows"))
        out.rows.push(text(mode === "always" ? "The farm window stays while AION 2 runs; its × hides it until you go to another place or press Show now."
            : mode === "popup" ? "It opens when Kinah or loot comes in a row in the open world or a dungeon (the first 30 s in a place don't count, then two gains), and goes in a town or 10 minutes after the last gain in the open world."
            : "The farm window is off."))
        if (mode === "popup") out.rows.push(text("Now: " + store.farmWaits, Theme.textSoft()))
        out.rows.push(group("The rows"))
        out.rows.push(text("Kinah today counts toward the daily 1,000,000. Worth per hour: Kinah and the loot's Market worth per hour of farming in the open world today. Gold items: today's. Dungeon run: what this run brought. Keys and tickets: those you have left. Odyle energy and the ping come from the game as the DPS meter shows them; the DPS panel need not be open. Width and height: drag the window's corner (double-click it for the size it had)."))
    }
    function buildSession(out) {
        const ds = store.dropSession()
        const past = ds !== store.session
        const label = (h, cur) => (cur ? "This session" : when(h.start) + " – " + clock(h.end || h.last || h.start)) + (h.active ? " (" + span(h.active) + ")" : "")
        const opts = [{ id: "", name: label(store.session, true) }].concat(store.history.map((h) => ({ id: String(h.start), name: label(h, false) })))
        const src = LK.C.bySource(ds)
        const n = (m) => Object.keys(m || {}).filter((k) => m[k] > 0).length
        const breaks = [0, 60, 120, 180, 360]
        const bm = Number(st.breakMin == null ? 180 : st.breakMin)
        out.controls.push([drop("Session", past ? String(ds.start) : "", opts, "session", 260)].concat(past ? [] : [chip("New session", false, { newSession: true })],
            [chip("Break: " + (bm ? (bm >= 60 ? bm / 60 + " h" : bm + " min") : "by hand"), false, { set: "breakMin", v: breaks[(breaks.indexOf(bm) + 1) % breaks.length] })]))
        out.controls.push(["all", "gathered", "loot", "reward", "other"].map((k) => chip(({ all: "All", gathered: "Gathered", loot: "Loot", reward: "Rewards", other: "Other" })[k] + " " + (k === "all" ? n(ds.items) : n(src[k])), (st.source || "all") === k, { set: "source", v: k })))
        out.search = "drops"
        const played = ds.active || 0
        const perHour = (v) => (played >= 300000 ? v / (played / 3600000) : null)
        const bits = ["Since " + when(ds.start)]
        if (played) bits.push("played " + span(played))
        if (ds.kinah) { const h = perHour(ds.kinah); bits.push("Kina +" + kina(ds.kinah) + (h != null ? " (" + shortK(h) + "/h)" : "")) }
        if (ds.abyss) bits.push("Abyss Points +" + kina(ds.abyss))
        out.rows.push(text(bits.join(" · "), Theme.textSoft()))
        const source = st.source || "all"
        const g = ds.gather || {}
        if (g.n && (source === "all" || source === "gathered")) {
            const got = (g.amount || 0) + (g.bonus || 0)
            let worth = 0
            for (const id in src.gathered) { const w = book ? LK.C.worth(Number(id), src.gathered[id], book.prices, st.fee, book.hist) : null; worth += w && w.total || 0 }
            const wh = perHour(worth)
            out.rows.push(text("Gathering: " + kina(g.n) + " times at " + kina(g.spots || 0) + " spots · " + kina(got) + " items (" + (got / g.n).toFixed(1) + " a time) · great " + kina(g.great || 0) + " (" + Math.round((g.great || 0) / g.n * 100) + " %) · bonus +" + kina(g.bonus || 0)
                + (book && book.prices.size ? " · worth " + kina(worth) + (wh != null ? " (" + shortK(wh) + "/h)" : "") : "")))
            const areas = Object.keys(g.byArea || {}).map((a) => [a, g.byArea[a]]).sort((a, b) => b[1].n - a[1].n)
            if (areas.length && !(areas.length === 1 && areas[0][0] === "Unknown")) out.rows.push(text("Where: " + areas.map((a) => a[0] + " " + kina(a[1].n)).join(" · ")))
        }
        const d = ds.dismantled || {}
        if (d.pieces && (source === "all" || source === "other")) out.rows.push(text("Dismantled: " + kina(d.pieces) + " pieces → " + kina(d.stones) + " Enhance Stones" + (d.kinahBound ? " · −" + kina(d.kinahBound) + " bound Kina" : "")))
        const counts = source === "all" ? ds.items || {} : src[source] || {}
        const sources = source === "all" ? [{ name: "Gathered", map: ds.gathered || {} }, { name: "Loot", map: ds.loot || {} }, { name: "Reward", map: ds.reward || {} }] : null
        listRows(out, counts, { search: (st.search || {}).drops || "", sources: sources, empty: source !== "all" ? "Nothing of this kind in the session." : "Nothing came in since the session started. Items you gather, pick up or get count here, each with where it came from." })
        const where = ds.where || []
        if (where.length && source === "all") { out.rows.push(group("Where and when")); stintRows(out, where, false) }
    }
    function stintRows(out, list, account) {
        const w = [0.16, 0.13, 0.13, 0.12, 0.08]
        out.rows.push(head(["When · where", "Played", "Kina", "Worth", "Gold"], w))
        for (const x of list.slice().sort((a, b) => b.from - a.from)) {
            out.rows.push(cells([clock(x.from) + "–" + clock(x.to) + "  " + x.place + " · " + (LK.F.NAMES[x.src] || x.src) + (account && x.who ? " · " + x.who : ""), hours(x.active), kina(x.kinah), [shortK(x.worth), gold], [String(x.gold || 0), x.gold ? gold : ""]], w))
        }
    }
    function metricText(metric, v) { return v == null ? "—" : metric === "gold" ? v.toFixed(2) : metric === "toCap" ? v.toFixed(1) + " h" : shortK(v) }
    function buildDays(out) {
        const account = st.farmWho === "all"
        const name = store.nameOf(store.viewKey()) || "This character"
        const sums = store.farmSums()
        const today = LK.F.dayOf(Date.now())
        const shownDay = sums.find((s) => s.day === (dayView == null ? today : dayView)) || (dayView == null ? null : sums[sums.length - 1]) || null
        const opts = sums.slice().reverse()
        if (!opts.some((s) => s.day === today)) opts.unshift({ day: today })
        out.controls.push([chip(name, !account, { set: "farmWho", v: null }), chip("Whole account", account, { set: "farmWho", v: "all" }),
            drop("Day", shownDay ? shownDay.day : today, opts.map((s) => ({ id: String(s.day), name: dayLabel(s.day) + (s.day === today ? " (today)" : "") + (s.account ? (s.capped ? " · " + plural(s.capped, "cap") : "") : s.cap ? " · cap" : "") })), "day", 220)])
        const metric = LK.F.METRICS[st.statMetric] ? st.statMetric : "kinah"
        const k = st.statSource || "open"
        out.controls.push([words("Statistics:")].concat([["all", "All"]].concat(LK.F.SOURCES.map((x) => [x, LK.F.NAMES[x]])).map((x) => chip(x[1], k === x[0], { set: "statSource", v: x[0] }))))
        out.controls.push([words("Measure:")].concat(Object.keys(LK.F.METRICS).map((m) => chip(LK.F.METRICS[m].label, metric === m, { set: "statMetric", v: m }))))
        // The day.
        const s = shownDay
        out.rows.push(group(s ? dayLabel(s.day) : "Today"))
        if (!s) out.rows.push(text("Nothing yet this day. Gains count from the daily reset (07:00 UTC) to the next, each with where it came from."))
        else {
            const open = (s.src || {}).open || {}
            if (s.account) {
                out.rows.push(text(plural(s.chars, "character") + " played" + (s.capped ? " · " + s.capped + " reached the Kina cap" + (s.cap && s.cap.hoursEach ? ", after " + span(s.cap.hoursEach * 3600000) + " on average in the open world" : "") : "") + " · Kina toward the caps " + kina(s.counter || 0), Theme.textSoft()))
            } else if (s.cap) {
                let t = "Kina cap reached at " + clock(s.cap.at) + " after " + hours(s.cap.active) + " in the open world" + (s.cap.sinceFirst ? " (" + span(s.cap.sinceFirst) + " since its first Kina)" : "")
                const after = { active: (open.active || 0) - (s.cap.active || 0), gold: (open.gold || 0) - (s.cap.gold || 0), worth: (open.worth || 0) - (s.cap.worth || 0) }
                if (after.active > 0 || after.gold > 0 || after.worth > 0) t += " · After it: " + hours(after.active) + ", " + after.gold + " gold, worth " + shortK(after.worth)
                out.rows.push(text(t, Theme.textSoft()))
            } else {
                const kk = s.counter != null ? s.counter : open.kinah || 0
                out.rows.push(text("Kina toward the cap " + kina(kk) + " / " + shortK(LK.C.KINA_DAILY) + (open.active ? " after " + hours(open.active) + " in the open world" : ""), Theme.textSoft()))
            }
            const w = [0.14, 0.15, 0.12, 0.13, 0.08]
            const tot = { active: 0, kinah: 0, n: 0, worth: 0, gold: 0 }
            const list = []
            for (const key of LK.F.SOURCES) {
                const p = (s.src || {})[key]
                if (!p || !(p.n || p.kinah || p.active)) continue
                for (const f in tot) tot[f] += p[f] || 0
                list.push(cells([LK.F.NAMES[key], hours(p.active), kina(p.kinah), kina(p.n), [shortK(p.worth), gold], [String(p.gold || 0), p.gold ? gold : ""]], w))
            }
            if (list.length) {
                out.rows.push(head(["Where", "Played", "Kina", "Items", "Worth", "Gold"], w))
                out.rows = out.rows.concat(list)
                if (list.length > 1) out.rows.push(cells(["All", hours(tot.active), kina(tot.kinah), kina(tot.n), [shortK(tot.worth), gold], String(tot.gold)], w, true))
            } else out.rows.push(text("Nothing came in yet this day."))
            if ((s.stints || []).length) { out.rows.push(group("Where and when")); stintRows(out, s.stints, s.account) }
            const golds = (s.gold || []).slice().sort((a, b) => b[0] - a[0])
            out.rows.push(group("Gold items"))
            if (!golds.length) out.rows.push(text("No gold items this day."))
            for (const gl of golds) {
                const tags = [gradeTag(LK.C.grade(gl[1])), [LK.F.NAMES[gl[3]] || gl[3], ""], [LK.F.zoneName(gl[4]), ""]].filter(Boolean)
                if (s.account && gl[6]) tags.unshift([gl[6], ""])
                out.rows.push(item(gl[1], LK.C.name(gl[1]) + (gl[2] > 1 ? " ×" + gl[2] : ""), tags, [clock(gl[0]), gl[5] != null ? [kina(gl[5]), gold] : ""], [0.12, 0.17]))
            }
        }
        // The statistics.
        const pts = LK.F.points(sums, k, metric)
        const where = metric === "toCap" ? "the open world" : k === "all" ? "anywhere" : LK.F.NAMES[k]
        out.rows.push(group("Statistics · " + LK.F.METRICS[metric].label + " · " + where))
        if (pts.length) out.rows.push({ kind: "bars", values: pts.map((p) => p.value), labels: pts.map((p, i) => (i === 0 || i === pts.length - 1 ? dayLabel(p.day) : "")), top: "max " + metricText(metric, Math.max.apply(null, pts.map((p) => p.value))) })
        const ready = LK.F.readiness(pts, metric)
        const avg = pts.length ? pts.reduce((t, p) => t + p.value, 0) / pts.length : null
        out.rows.push(text(LK.F.METRICS[metric].label + " in " + where + ": " + metricText(metric, avg) + " on average over " + plural(pts.length, "day") + (metric === "gold" && ready.gold != null ? " (" + Math.round(ready.gold) + " gold items)" : ""), Theme.textSoft()))
        const missing = []
        if (ready.needDays) missing.push(plural(ready.needDays, "more day") + " with half an hour or more here")
        if (ready.needGold) missing.push(plural(ready.needGold, "more gold item"))
        out.rows.push(text(ready.ready ? "Statistically meaningful: " + pts.length + " days" + (metric === "gold" ? " and " + Math.round(ready.gold) + " gold items" : "") + "."
            : "Not meaningful yet: it needs " + LK.F.MIN_DAYS + " days" + (metric === "gold" ? " and " + LK.F.MIN_GOLD + " gold items" : "") + "; " + missing.join(" and ") + " to go. Until then a trend is only a hint.", ready.ready ? good : ""))
        const tr = LK.F.trend(pts)
        if (tr) out.rows.push(text("Trend: " + (tr.p < 0.05 ? (tr.perWeek >= 0 ? "rising " : "falling ") + pctText(tr.perWeek) + " a week" : "none to see") + " (" + (tr.p < 0.05 ? "" : "a slope of " + pctText(tr.perWeek) + " a week is chance, ") + pText(tr.p) + ")"))
        const ch = metric === "gold" ? LK.F.goldChange(pts) : LK.F.change(pts)
        if (ch) out.rows.push(text("Last " + LK.F.RECENT_DAYS + " days against the " + (ch.nBefore != null ? ch.nBefore : pts.length - LK.F.RECENT_DAYS) + " before: " + metricText(metric, ch.before) + " → " + metricText(metric, ch.after) + " (" + pctText(ch.rel) + "): " + (ch.p < 0.05 ? "the drops changed" : "no change to see") + " (" + pText(ch.p) + ")"))
        else if (pts.length) out.rows.push(text("Changes: from " + (LK.F.RECENT_DAYS + 3) + " days on, the last " + LK.F.RECENT_DAYS + " days are compared with the ones before."))
        if (ready.detect != null && isFinite(ready.detect)) out.rows.push(text("With these days a change of about " + Math.round(ready.detect * 100) + " % shows" + (ready.daysFor10 ? "; for 10 % about " + ready.daysFor10 + " days" : "") + "."))
        const places = LK.F.byPlace(sums, metric === "toCap" ? "open" : k).filter((p) => p.hours >= LK.F.MIN_HOURS)
        if (places.length) {
            const w = [0.08, 0.11, 0.12, 0.12, 0.1]
            const ph = (v, h) => (h ? v / h : null)
            out.rows.push(head(["By place", "Days", "Played", "Kina/h", "Worth/h", "Gold/h"], w))
            for (const p of places.slice(0, 15)) out.rows.push(cells([p.place, String(p.days), p.hours.toFixed(1) + " h", shortK(ph(p.kinah, p.hours)), [shortK(ph(p.worth, p.hours)), gold], ph(p.gold, p.hours).toFixed(2)], w))
        }
        const byHour = LK.F.goldByHour(sums, metric === "toCap" ? "open" : k, (at) => new Date(at).getHours())
        if (Math.max.apply(null, byHour) > 0) {
            out.rows.push(group("Gold items by the hour of the day"))
            out.rows.push({ kind: "bars", values: byHour, labels: byHour.map((v, h) => (h % 3 ? "" : String(h))), top: "" })
        }
    }
    readonly property var verdicts: ({ "in": ["In range", ""], above: ["Above the range", "#7fdc9a"], below: ["Below the range", "#ff8a7a"], none: ["No boxes yet", ""], rate: ["Rate only", ""] })
    function buildDungeons(out) {
        const account = st.farmWho === "all"
        const name = store.nameOf(store.viewKey()) || "This character"
        out.controls.push([chip(name, !account, { set: "farmWho", v: null }), chip("Whole account", account, { set: "farmWho", v: "all" })])
        const all = LK.DG.summarize(store.runsShown())
        if (!all.length) { out.rows.push(text("Your dungeon runs show here: each visit with the Odyle Energy spent (40 a reward box) and what dropped, against the game's own drop rates.")); return }
        const w = [0.2, 0.17, 0.11, 0.18]
        for (const d of all) {
            const t = d.total
            out.rows.push(group(d.name + (d.level ? " · " + d.level : "")))
            out.rows.push(text(plural(t.runs, "run") + " · " + plural(t.boxes, "box", "boxes") + " (" + kina(t.energy) + " Odyle Energy) · " + plural(t.gold, "gold item") + (t.boxless ? " · " + plural(t.boxless, "visit") + " without a box" : ""), Theme.textSoft()))
            if (d.rows) {
                out.rows.push(head(["Drops", "You (a box)", "Expected", "Range", "Verdict"], w))
                for (const v of d.rows) {
                    const vd = verdicts[v.verdict] || verdicts.none
                    if (v.unrated) out.rows.push(cells([v.label, v.boxes ? v.found + " (" + (v.rate || 0).toFixed(1) + ")" : String(v.found), "—", "—", vd[0]], w))
                    else out.rows.push(cells([v.label, v.found + " (" + pctBox(v.rate) + ")", v.expectedLo < v.expected * 0.97 ? v.expectedLo.toFixed(1) + "–" + v.expected.toFixed(1) : v.expected.toFixed(1) + " (" + pctBox(v.chance) + ")",
                        v.boxes ? v.lo + "–" + v.hi : "—", [vd[0] + (v.sure ? "" : " (hint)"), vd[1]]], w, v.main && v.key === "gold"))
                }
                if (d.recent) {
                    const v = d.recent.rows.find((x) => x.main)
                    if (v) out.rows.push(text("Last 7 days: " + v.found + " in " + v.boxes + " boxes (" + pctBox(v.rate) + " a box, expected " + (v.chanceLo < v.chance * 0.97 ? pctBox(v.chanceLo) + "–" : "") + pctBox(v.chance) + "): " + (verdicts[v.verdict] || verdicts.none)[0] + " (" + pText(v.p) + ")"))
                }
                if (d.weeks.length > 1 || (d.weeks.length && !d.recent)) {
                    const ww = [0.14, 0.18, 0.16, 0.2]
                    out.rows.push(head(["Week from", "Boxes", "Found", "Expected", "Verdict"], ww))
                    for (const wk of d.weeks.slice(0, 12)) {
                        const v = wk.all
                        out.rows.push(cells([dayLabel(wk.week), String(wk.total.boxes), v ? v.found + " (" + pctBox(v.rate) + ")" : "—", v ? (v.expectedLo < v.expected * 0.97 ? v.expectedLo.toFixed(1) + "–" + v.expected.toFixed(1) : v.expected.toFixed(1)) : "—", (verdicts[v ? v.verdict : "none"] || verdicts.none)[0]], ww))
                    }
                }
            } else out.rows.push(text("Gold items: " + (t.boxes ? (t.gold / t.boxes).toFixed(2) : "—") + " a box. The game's drop rates for this dungeon and mode are not in the data."))
            out.rows.push(text("Last runs: " + d.last.slice(0, 5).map((r) => dayLabel(r.from) + " " + clock(r.from) + (account && r.who ? " " + r.who : "") + " (" + (r.boxes ? plural(r.boxes, "box", "boxes") : "no box") + (Object.keys(r.items).length ? ": " + Object.keys(r.items).map((id) => LK.C.name(Number(id)) + (r.items[id] > 1 ? " ×" + r.items[id] : "")).join(", ") : "") + ")").join(" · ")))
        }
    }

    // ---------- CLOSET ----------
    function buildCloset(out) {
        const sub = ["merchant", "missing", "combine"].indexOf(st.closetTab) >= 0 ? st.closetTab : "merchant"
        out.controls.push([chip("Merchant", sub === "merchant", { set: "closetTab", v: "merchant" }), chip("Missing", sub === "missing", { set: "closetTab", v: "missing" }), chip("Combine and extract", sub === "combine", { set: "closetTab", v: "combine" })])
        out.controls.push([chip("Open at the merchant", st.shopWindow !== false, { set: "shopWindow", v: st.shopWindow === false }), chip("Open at the Shop and Market", st.marketWindow === true, { set: "marketWindow", v: st.marketWindow !== true })])
        out.controls.push([chip("Show the window", false, { window: "shop" }), chip("Exchange", false, { window: "exchange" })])
        const n = store.closet ? store.closet.size : null
        out.rows.push(text(n == null ? "Log in while the companion runs: the game sends your closet at login." : n + " of " + LK.L.GOAL + " skins for Empty Closet" + (n >= LK.L.GOAL ? ": reached" : " · " + (LK.L.GOAL - n) + " to go") + " · closet as of " + when(store.closetAt), Theme.textSoft()))
        if (sub === "merchant") buildMerchant(out)
        else if (sub === "missing") buildMissing(out)
        else buildCombine(out)
    }
    function offerRow(o, w) {
        const tags = [[o.sub, ""]]
        const hot = o.status === "new" || o.status === "buy"
        if (o.status) tags.push([o.status === "new" ? "New" : o.status === "buy" ? "Buy" : o.status === "need" ? "Needed (monsters drop it too)" : o.status === "owned" ? (o.pet ? "Level 3" : "Owned") : "?", hot ? gold : ""])
        if (o.soldOut) tags.push(["Bought", ""])
        return item(o.item, o.name, tags, [o.discount ? "−" + o.discount + " %" : "", [kina(o.price), hot ? gold : ""]], w, { icon: o.icon || LK.C.icon(o.item), grade: o.grade })
    }
    function buildMerchant(out) {
        const now = Date.now()
        const why = store.windowWanted ? (store.hereBy === "hand" ? "open (by hand)" : store.hereBy === "market" ? "open (at the Shop or Market)" : "open (at the merchant or the closet)") : store.dismissed ? "closed with its × until you leave" : st.shopWindow === false ? "off at the merchant: switch on Open at the merchant" : "opens at the Black Cloud merchant and the closet" + (st.marketWindow === true ? ", and at the Shop and Market" : "")
        out.rows.push(text("Shop window: " + why + (store.lastStock ? " · last shop list " + clock(store.lastStock.at) + (store.lastStock.owner ? " (" + store.lastStock.owner + ")" : "") : "")))
        const w = [0.1, 0.16]
        let any = false
        for (const key in store.closetChars) {
            const c = store.closetChars[key]
            const stocks = Object.keys(c.stocks).map((t) => c.stocks[t]).filter((s) => s.refresh > now).sort((x, y) => x.tab - y.tab)
            if (!stocks.length) continue
            any = true
            out.rows.push(group(c.name + " · changes at " + clock(Math.min.apply(null, stocks.map((s) => s.refresh)))))
            for (const s of stocks) {
                const pets = s.tab % 100 === 4
                const list = []
                for (const o of s.offers) {
                    const m = LK.L.statusOf(o.item, store.closet, store.ix, store.learned)
                    if (m.skin) list.push({ item: o.item, name: m.skin.name, sub: (LK.L.GRADES[m.skin.grade] || "") + " · " + m.skin.slot, grade: m.skin.grade, status: m.status, price: o.price, discount: o.discount, soldOut: o.soldOut, icon: m.skin.icon ? "Icon_" + m.skin.icon : "" })
                    else if (pets) { const pi = store.petInfo(o.item); list.push({ item: o.item, name: LK.C.name(o.item), sub: pi.level < 0 ? "Pet" : "Pet · level " + pi.level + " of 3", grade: LK.C.grade(o.item), status: pi.status, price: o.price, discount: o.discount, soldOut: o.soldOut, pet: true }) }
                }
                const others = s.offers.length - list.length
                out.rows.push(text(s.tabName + (others ? " · " + plural(others, "other item") : "")))
                const rank = (o) => (o.status === "new" || o.status === "buy" ? 0 : o.status === "owned" ? 2 : 1)
                for (const o of list.sort((x, y) => rank(x) - rank(y) || y.price - x.price)) out.rows.push(offerRow(o, w))
                if (!list.length) out.rows.push(text("No skins or pets in this tab"))
            }
        }
        if (!any) out.rows.push(text("No offers this hour yet: open the Black Cloud shop (Shop, tab Black Cloud) and look at its tabs. Each character has its own offers, changing every full hour."))
        const un = store.closetCharsNow().filter((c) => !c.looked && !(store.character && c.name === store.character.name)).map((c) => c.name)
        if (un.length) out.rows.push(text("Not looked at this hour: " + un.join(", "), gold))
        const ms = LK.L.merchantStats(store.seen)
        out.rows.push(group("Paid changes"))
        if (!ms.offers) out.rows.push(text("Counted from the stocks you open: how often a skin you lack is on offer, and what a paid change of the stock is worth."))
        else {
            out.rows.push(text(ms.stocks + " stocks seen, " + ms.offers + " skin offers, " + ms.fresh + " of them new to you then (" + pct(ms.rate) + "). A paid change shows a new skin about " + pct(ms.perChange) + " of the time."))
            const ww = [0.3, 0.3]
            out.rows.push(head(["Paid change", "Costs", "Per new skin"], ww))
            for (const r of ms.refreshCost) out.rows.push(cells([r.n + ".", kina(r.cost), r.perNew ? "≈ " + kina(r.perNew) : "–"], ww))
        }
    }
    function buildMissing(out) {
        out.search = "missing"
        out.controls.push([["all", "All"], ["weapon", "Weapons"], ["armour", "Armour"], ["jewel", "Jewellery"], ["other", "Other"]].map((x) => chip(x[1], (st.kind || "all") === x[0], { set: "kind", v: x[0] })))
        out.controls.push([["all", "Every grade"], ["shop", "Merchant"], ["exchange", "On the Exchange"], ["1", "Common"], ["2", "Rare"], ["3", "Epic"], ["4", "Unique"]].map((x) => chip(x[1], (st.grade || "all") === x[0], { set: "grade", v: x[0] }))
            .concat([chip("Sort: " + ({ price: "Price", name: "Name", grade: "Grade", exchange: "Exchange" })[st.order || "price"], false, { set: "order", v: ({ price: "exchange", exchange: "name", name: "grade", grade: "price" })[st.order || "price"] })]))
        if (!store.closet) return
        const ex = store.exchange()
        const miss = LK.L.missing(store.closet, store.ix).map((m) => Object.assign({}, m, { ex: LK.L.exchangeOf(m.look, store.ix, ex) }))
        const need = Math.max(0, LK.L.GOAL - store.closet.size)
        const c = LK.L.costs(miss, need)
        if (c) out.rows.push({ kind: "tiles", tiles: [["Cheapest " + c.n, shortK(c.cheapest), "all at 50% off"], ["Average", shortK(c.average), "the usual discount"], ["Dearest", shortK(c.dearest), "at 10% off"], ["All " + c.count, shortK(c.all), "every merchant skin you lack"]] })
        const q = String((st.search || {}).missing || "").trim().toLowerCase()
        const kind = st.kind || "all", grade = st.grade || "all"
        let list = miss.filter((m) => (kind === "all" || m.kind === kind)
            && (grade === "all" || (grade === "shop" ? m.price > 0 : grade === "exchange" ? !!m.ex : String(m.grade) === grade))
            && (!q || m.name.toLowerCase().indexOf(q) >= 0 || m.slot.toLowerCase().indexOf(q) >= 0))
        const inf = Number.MAX_VALUE
        const by = { price: (x, y) => (x.price || inf) - (y.price || inf) || x.name.localeCompare(y.name), name: (x, y) => x.name.localeCompare(y.name) || x.slot.localeCompare(y.slot),
            grade: (x, y) => y.grade - x.grade || x.name.localeCompare(y.name), exchange: (x, y) => (x.ex ? x.ex.price : inf) - (y.ex ? y.ex.price : inf) || (x.price || inf) - (y.price || inf) || x.name.localeCompare(y.name) }
        list = list.sort(by[st.order] || by.price)
        const listed = miss.filter((m) => m.ex)
        out.rows.push(text(listed.length ? "On the Exchange: " + listed.length + " of the skins you lack, from " + kina(Math.min.apply(null, listed.map((m) => m.ex.price))) + " Kina; gold where cheaper than the merchant asks. Prices of " + when(book ? book.fetchedAt : 0) + "."
            : "On the Exchange: none of the skins you lack known yet."))
        out.rows.push(text(list.length + " of the " + miss.length + " skins you lack" + (list.length > shown ? " (the first " + shown + " shown)" : "") + ". Skins without a number in the game's data (sets, costumes) are not listed."))
        const w = [0.24, 0.24]
        out.rows.push(head(["Skin", "Merchant (50% off)", "Exchange"], w))
        for (const m of list.slice(0, shown)) {
            const goodBuy = m.ex && LK.L.goodBuy(m.ex.price, m.price)
            out.rows.push(item(m.item, m.name, [[(LK.L.GRADES[m.grade] || "") + " · " + m.slot, gradeColors[m.grade] || ""]], [m.price ? kina(m.price) + " (" + kina(m.price / 2) + ")" : "not sold", m.ex ? [kina(m.ex.price) + (m.ex.listings ? " · " + m.ex.listings + " listed" : ""), goodBuy ? gold : ""] : "—"], w, { icon: m.icon ? "Icon_" + m.icon : "", grade: m.grade }))
        }
        if (list.length > shown) out.rows.push({ kind: "more", left: list.length - shown })
    }
    readonly property var combineVerdicts: ({ yes: ["Combine", "#7fdc9a"], ok: ["Worth it", ""], feed: ["Only to climb a grade", ""], no: ["Stop", "#ff8a7a"], cheap: ["Only cheap pieces", ""] })
    function buildCombine(out) {
        out.controls.push([chip("Lucky Aura", st.lucky, { set: "lucky", v: !st.lucky })])
        const t = store.todo()
        if (t) out.rows.push(text(t, gold))
        const a = store.advise()
        const has = !!store.closet
        // Four short columns, the rest as a line under each grade: seven
        // columns were cut off in a panel of normal width (MN, 2026-11-13).
        const w = [0.2, 0.32, 0.24]
        out.rows.push(group("Combining"))
        out.rows.push(head(["Grade", "You lack", "Next grade", "Verdict"], w))
        for (const x of a.combined.rows) {
            const vd = combineVerdicts[x.verdict] || ["–", ""]
            out.rows.push(cells([[x.name, gradeColors[x.grade] || ""], has ? x.lackSame + " of " + x.totalSame : "–",
                has ? (x.assumed ? (x.next || "next") : x.next + " · lack " + x.lackNext) + " · " + Math.round(x.up * 100) + "% up" : "–", has ? vd : "–"], w))
            if (has) out.rows.push(text("New skin per combine " + pct(x.yieldNew) + (x.kinah ? " · ≈ " + shortK(x.kinah) + " Kinah per new skin" : "") + " · " + x.spares + " spare " + (x.spares === 1 ? "piece" : "pieces") + (x.possible ? ", enough for " + x.possible + "×" : "")))
        }
        out.rows.push(group("Extract settings"))
        const set = has ? LK.L.extractSettings(a.extracted) : null
        if (!set) out.rows.push(text("Log in while the companion runs: the settings follow from your closet."))
        else {
            out.rows.push(text("Auto Extract: " + (set.on ? "ON" : "OFF"), set.on ? good : ""))
            for (const g of set.grades) out.rows.push(text((g.tick ? "✓ " : "✗ ") + g.name + ": " + g.why, g.tick ? Theme.text() : ""))
            out.rows.push(text("✓ Select gear that cannot be equipped and has a low base item level · ✓ Exclude Supply Request Gear · the level range as you have it. Quick Select (by hand): the same grades."))
        }
        out.rows.push(group("Gear in your bag with a look you lack"))
        const pieces = has ? LK.L.bagGear(store.bag, store.closet, LK.CD, store.ix) : []
        if (!has || !store.bag) out.rows.push(text("Gear in your bag that would give a new skin shows here once your inventory was seen (at a world entry)."))
        else if (!pieces.length) out.rows.push(text("No gear in your bag has a look you lack: sell or dismantle it."))
        else for (const p of pieces.slice(0, 60)) out.rows.push(item(p.item || 0, p.name || "Look " + p.look, [[(LK.L.GRADES[p.grade] || "") + " gear" + (p.slot ? " · " + p.slot : "") + (p.count > 1 ? " · " + p.count + " pieces" : ""), ""]], [[pct(1 - Math.pow(1 - p.chance, p.count)), gold]], [0.2], { icon: p.icon ? "Icon_" + p.icon : "", grade: p.grade }))
    }

    // ---------- CARDS ----------
    readonly property var curNames: ({ "930100003": "Abyss Points", "930100023": "Enhance Stones", "930100011": "Centuryroot Tokens" })
    function stepRound(d) {
        const list = store.cardRounds()
        let i = store.shownRound == null ? list.length - 1 : list.findIndex((r) => r.key === store.shownRound)
        if (i < 0) i = list.length - 1
        const j = Math.max(0, Math.min(list.length - 1, i + d))
        store.shownRound = j === list.length - 1 ? null : (list[j] ? list[j].key : null)
        refresh()
    }
    function buildCards(out) {
        const sub = ["round", "gold", "places", "items"].indexOf(st.cards) >= 0 ? st.cards : "round"
        const chars = LK.S.characters(store.rounds)
        out.controls.push([drop("Character", store.cardChar(), [{ id: "all", name: "All characters " + store.rounds.length }].concat(chars.map((c) => ({ id: c.key, name: (c.name || "No character") + " " + c.n }))), "cardChar", 220)]
            .concat(["all", "shugo", "di"].map((k) => chip((k === "all" ? "All" : k === "di" ? "Invasion" : "Shugo") + " " + store.cardRounds(k).length, (st.cardKind || "all") === k, { set: "cardKind", v: k }))))
        out.controls.push([chip("Last round", sub === "round", { set: "cards", v: "round" }), chip("Gold", sub === "gold", { set: "cards", v: "gold" }), chip("Places", sub === "places", { set: "cards", v: "places" }), chip("Items", sub === "items", { set: "cards", v: "items" })])
        const list = store.cardRounds()
        // Rounds the game sent that this version can't read (kept as they came).
        if (store.odd.length) out.rows.push(text(store.odd.length + (store.odd.length === 1 ? " round" : " rounds") + " came that this version can't read yet (kept; the last at " + clock(store.odd[store.odd.length - 1].at) + ").", Theme.textSoft()))
        const prices = book ? book.prices : new Map()
        const hist = book ? book.hist : null
        if (sub === "round") {
            let i = store.shownRound == null ? list.length - 1 : list.findIndex((r) => r.key === store.shownRound)
            if (i < 0) i = list.length - 1
            const r = list[i] || null
            if (!r) { out.rows.push(text("No round yet. After a Shugo Festival's or a Dimensional Invasion's card round the game sends what lay behind all five cards and who picked which: each round is kept here.")); return }
            const k = LK.S.kindOf(r, st.kinds)
            out.controls.push([chip("‹", false, { step: -1 }), words("Round " + (i + 1) + " of " + list.length), chip("›", false, { step: 1 })]
                .concat(st.kinds[r.event] || !LK.S.EVENTS[r.event] ? [chip("Shugo", k.sure && k.kind === "shugo", { kindOf: r.event, v: "shugo" }), chip("Invasion", k.sure && k.kind === "di", { kindOf: r.event, v: "di" })] : []))
            const ws = r.cards.map((c) => LK.S.cardWorth(c, prices, hist))
            const best = Math.max.apply(null, ws.map((w) => w.kinah))
            let mine = 0
            r.cards.forEach((c, n) => { if (c.mine) mine += ws[n].kinah })
            out.rows.push(text(LK.S.KINDS[k.kind] + (k.sure ? "" : " (guessed by the time)") + " · " + when(r.at) + (r.who ? " · " + r.who : "") + (prices.size ? " · your cards " + shortK(mine) + " Kina" : ""), Theme.textSoft()))
            const lines = (pairs) => {
                const m = new Map()
                for (const p of pairs) if (!LK.S.currency(p[0])) m.set(p[0], (m.get(p[0]) || 0) + p[1])
                return Array.from(m).sort((a, b) => LK.S.gold(b[0]) - LK.S.gold(a[0]))
            }
            // [name, grade colour, gold, item, count]: the card shows each
            // item as the game does, its picture framed in its grade's colour.
            const line = (p) => [LK.C.name(p[0]), gradeColors[LK.C.grade(p[0])] || "", LK.S.gold(p[0]), p[0], p[1]]
            out.rows.push({ kind: "cards", cards: r.cards.map((c, n) => {
                const w = ws[n]
                const cur = Object.keys(w.cur).map((id) => kina(w.cur[id]) + " " + (curNames[id] || LK.C.name(Number(id))))
                return { title: "Card " + (c.place + 1), you: c.mine ? (c.mine > 1 ? "YOU ×" + c.mine : "YOU") : c.others ? "OTHER" : "",
                    bonus: (c.bonus || []).length ? lines(c.bonus).map(line) : [], lines: lines(c.main).map(line).concat(cur.map((t) => [t, "", false, 0, 0])),
                    worth: w.priced ? (w.guess ? "≈ " : "") + shortK(w.kinah) : "—", best: w.kinah === best && best > 0 }
            }) })
            return
        }
        const s = LK.S.stats(list, prices, hist)
        if (sub === "gold") {
            out.rows.push(text(plural(s.golds.length, "gold item") + " in " + plural(s.rounds, "round") + " · " + s.golds.filter((g) => g.mine).length + " on cards you picked · " + s.bonusGold + " of " + s.bonusCards + " bonus layers with gold", Theme.textSoft()))
            const by = new Map()
            for (const g of s.golds) {
                const x = by.get(g.item) || { item: g.item, seen: 0, mine: 0, places: [0, 0, 0, 0, 0] }
                x.seen++
                if (g.mine) x.mine++
                x.places[g.place]++
                by.set(g.item, x)
            }
            const w = [0.2, 0.22, 0.12]
            out.rows.push(group("By item"))
            if (!by.size) out.rows.push(text("No gold item yet."))
            for (const x of Array.from(by.values()).sort((a, b) => b.seen - a.seen)) {
                const wv = LK.S.worth(x.item, 1, prices, hist)
                out.rows.push(item(x.item, "", [gradeTag(LK.C.grade(x.item))].filter(Boolean), [x.seen + "× seen, " + x.mine + "× yours", x.places.map((v, n) => (v ? "#" + (n + 1) + ": " + v : "")).filter(Boolean).join("  "), [wv.total != null ? (wv.guess ? "≈" : "") + shortK(wv.total) : "—", gold]], w))
            }
            out.rows.push(group("Every gold item"))
            for (const g of s.golds.slice(0, 200)) out.rows.push(item(g.item, "", [], [when(g.at), "Card " + (g.place + 1) + (g.bonus ? " (bonus)" : ""), [g.mine ? "Yours" : "Not picked", g.mine ? gold : ""]], [0.17, 0.15, 0.12]))
        } else if (sub === "places") {
            const advice = (t, a, what) => (a.sure ? "Pick card " + (a.place + 1) + ": " + what + " lay there " + Math.round(t.share * 100) + " % of the time (" + t.n + " cases; by chance it would be 20 %, and a spread like this comes by chance only " + (t.p * 100).toFixed(1) + " % of the time)."
                : what.charAt(0).toUpperCase() + what.slice(1) + ": " + plural(t.n, "case") + " so far. No card is better than chance yet." + (t.n ? " Card " + (t.best + 1) + " leads with " + Math.round(t.share * 100) + " %, which chance explains (" + Math.round(t.p * 100) + " %)." : "") + " A strong lead shows after about " + LK.S.NEED_STRONG + ", a moderate one after about " + LK.S.NEED_MODERATE + ".")
            out.rows.push(text(advice(s.goldTest, s.goldAdvice, "gold on the card"), s.goldAdvice.sure ? gold : ""))
            out.rows.push(text(advice(s.bestTest, s.bestAdvice, "the most valuable card"), s.bestAdvice.sure ? gold : ""))
            const w = [0.15, 0.15, 0.15, 0.15, 0.12]
            const pc = (v, n) => (n ? v + " (" + Math.round(v / n * 100) + " %)" : "—")
            out.rows.push(head(["Card", "Gold", "Bonus", "Best", "Average", "Picked"], w))
            s.place.forEach((p, n) => out.rows.push(cells(["Card " + (n + 1), pc(p.gold, p.cards), pc(p.bonus, p.cards), pc(p.best, s.full), prices.size && p.avg != null ? shortK(p.avg) : "—", String(p.mine)], w, s.goldAdvice.sure && s.goldAdvice.place === n)))
            out.rows.push(text(plural(s.full, "full round") + " · " + plural(s.doubles, "card") + " picked twice" + (prices.size ? " · your cards " + shortK(s.yours) + " Kina, the best card each round " + shortK(s.bestSum) : "")))
            out.rows.push(group("Gold by card place"))
            out.rows.push({ kind: "bars", values: s.place.map((p) => p.gold), labels: s.place.map((p, n) => "Card " + (n + 1)), top: "" })
        } else {
            const w = [0.12, 0.14, 0.14]
            out.rows.push(head(["Item", "On cards", "Count in all", "Each"], w))
            for (const x of s.items) {
                const wv = LK.S.worth(x.item, 1, prices, hist)
                out.rows.push(item(x.item, "", [gradeTag(LK.C.grade(x.item))].filter(Boolean), [String(x.seen), kina(x.count), wv.unit != null ? (wv.guess ? "≈" : "") + shortK(wv.unit) : "—"], w))
            }
        }
    }

    // ---------- the panel ----------
    property string searchKey: ""
    Column {
        width: parent.width
        spacing: 8

        // Where the prices come from.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: panel.book && panel.book.error ? "#ff8a7a" : Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
            text: {
                const b = panel.book
                if (!b) return ""
                b.revision
                if (b.error) return b.error
                if (b.busy) return "Getting prices …"
                if (!b.fetchedAt) return "No prices yet: they come from the Market's sources once your server is known."
                return (b.serverName ? b.serverName + ": " : "") + "prices of " + panel.when(Date.parse(b.snapshot) || b.fetchedAt) + " (the Market's)"
            }
        }

        // The tabs.
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: panel.tabs
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.tab === modelData[0]
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
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.act({ set: "tab", v: modelData[0] }) }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // The tab's controls: rows of chips, menus and words.
        Column {
            width: parent.width
            spacing: 6
            z: 30
            Repeater {
                model: panel.controls
                delegate: Flow {
                    id: flow
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: 6
                    z: 30 - index
                    Repeater {
                        model: flow.modelData
                        delegate: Item {
                            id: ctl
                            required property var modelData
                            readonly property var c: modelData
                            width: c.type === "chip" ? chipItem.width : c.type === "drop" ? Math.min(c.w, flow.width) : wordsText.implicitWidth
                            height: c.type === "drop" ? 32 : 26
                            z: c.type === "drop" ? 2 : 1
                            Chip {
                                id: chipItem
                                visible: ctl.c.type === "chip"
                                text: ctl.c.text || ""
                                on: !!ctl.c.on
                                onClicked: panel.act(ctl.c.a)
                            }
                            Dropdown {
                                visible: ctl.c.type === "drop"
                                width: parent.width
                                label: ctl.c.label || ""
                                current: ctl.c.current || ""
                                options: ctl.c.type === "drop" ? ctl.c.options : []
                                onChosen: (id) => {
                                    const a = {}
                                    if (ctl.c.a === "cardChar") { a.set = "cardChar"; a.v = id; store.shownRound = null }
                                    else a[ctl.c.a] = id
                                    panel.act(a)
                                }
                            }
                            Text {
                                id: wordsText
                                visible: ctl.c.type === "text"
                                anchors.verticalCenter: parent.verticalCenter
                                text: ctl.c.type === "text" ? ctl.c.text : ""
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 12
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                        }
                    }
                }
            }
        }

        // The search (Items, the session's drops, the skins you lack).
        Item {
            visible: panel.searchKey.length > 0
            width: parent.width
            height: visible ? 30 : 0
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
                text: ((panel.st.search || {})[panel.searchKey]) || ""
                onTextEdited: {
                    const s = Object.assign({}, panel.st.search || {})
                    s[panel.searchKey] = text
                    panel.shown = 250
                    panel.store.set("search", s)
                }
                Keys.onEscapePressed: focus = false
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text.length === 0
                    text: panel.searchKey === "missing" ? "Search a skin or a slot …" : "Search an item …"
                    color: Theme.dim()
                    font: search.font
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: 380 + panel.grow
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            cacheBuffer: 600
            model: panel.rows
            delegate: rowDelegate
            WheelScroll { flick: list; step: 90 }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Prices: aion2.exchange (players' collected market prices), copied hourly by Clicktrough · item names, skins, dungeon drop rates and pictures: the game client, via SkeeveAN's Aion-DPS-Meter (MIT) and Aion2Data · logic: the Clicktrough Inventory, Closet and Shugo Cards plugins (GPL-3.0). Unofficial, not affiliated with NCSOFT or aion2.exchange."
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
            height: r.kind === "item" ? 40 : r.kind === "cells" || r.kind === "head" ? 26 : r.kind === "group" ? 30 : r.kind === "more" ? 34
                : r.kind === "bars" ? 86 : r.kind === "tiles" ? 58 : r.kind === "cards" ? cardsRow.height + 8 : textLine.implicitHeight + 6

            // The cells' places: the first column takes what the others leave.
            function cellX(i) {
                let x = width
                for (let k = r.w.length - 1; k >= i; k--) x -= width * r.w[k]
                return x
            }

            Rectangle { visible: r.kind === "item" || r.kind === "cells"; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }

            Text {
                visible: r.kind === "group"
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                width: parent.width
                elide: Text.ElideRight
                text: r.kind === "group" ? r.title.toUpperCase() : ""
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.4
                style: Theme.textStyle(); styleColor: Theme.shadow
            }

            Text {
                id: textLine
                visible: r.kind === "text"
                y: 3
                width: parent.width
                wrapMode: Text.WordWrap
                text: r.kind === "text" ? r.text : ""
                color: r.kind === "text" && r.color ? r.color : Theme.muted()
                font.family: Theme.body
                font.pixelSize: 12
                style: Theme.textStyle(); styleColor: Theme.shadow
            }

            Chip {
                visible: r.kind === "more"
                anchors.centerIn: parent
                text: r.kind === "more" ? "Show more (" + r.left + ")" : ""
                onClicked: panel.act({ more: true })
            }

            // A row of cells, or the column heads.
            Repeater {
                model: r.kind === "cells" || r.kind === "head" ? r.cells : []
                delegate: Text {
                    required property var modelData
                    required property int index
                    x: index === 0 ? 0 : row.cellX(index - 1)
                    width: index === 0 ? row.cellX(0) - 6 : row.width * row.r.w[index - 1] - 6
                    height: row.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                    elide: Text.ElideRight
                    text: row.r.kind === "head" ? String(modelData[0]).toUpperCase() : modelData[0]
                    color: row.r.kind === "head" ? Theme.dim() : modelData[1] ? modelData[1] : index === 0 ? Theme.textSoft() : Theme.text()
                    font.family: row.r.kind === "head" ? Theme.display : Theme.body
                    font.pixelSize: row.r.kind === "head" ? 11 : 12
                    font.weight: row.r.kind === "head" || row.r.strong ? Font.Bold : Font.Normal
                    font.letterSpacing: row.r.kind === "head" ? 1.2 : 0
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }

            // An item: picture, name, tags, cells.
            Item {
                visible: r.kind === "item"
                anchors.fill: parent
                Rectangle {
                    id: iconBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: panel.gradeColors[r.grade || 0] || "#555"
                    Text {
                        anchors.centerIn: parent
                        visible: pic.status !== Image.Ready
                        text: r.kind === "item" && r.name ? r.name.slice(0, 1) : ""
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                    Image {
                        id: pic
                        anchors.fill: parent
                        anchors.margins: 1
                        asynchronous: true
                        sourceSize.width: 56
                        source: r.kind === "item" && r.icon ? panel.iconUrl(r.icon) : ""
                    }
                }
                Column {
                    x: 38
                    anchors.verticalCenter: parent.verticalCenter
                    width: (r.kind === "item" ? row.cellX(0) : 0) - x - 6
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: r.kind === "item" ? r.name : ""
                        color: r.kind === "item" && r.grade >= 4 ? panel.gold : Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Row {
                        spacing: 8
                        visible: r.kind === "item" && r.tags.length > 0
                        Repeater {
                            model: r.kind === "item" ? r.tags : []
                            delegate: Row {
                                required property var modelData
                                required property int index
                                spacing: 4
                                Rectangle {
                                    visible: index === 0 && !!modelData[1] && row.r.grade > 1 && modelData[0] === LK.C.GRADES[row.r.grade]
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6
                                    height: 6
                                    color: modelData[1] || "transparent"
                                }
                                Text {
                                    text: modelData[0]
                                    color: modelData[1] ? modelData[1] : Theme.muted()
                                    font.family: Theme.body
                                    font.pixelSize: 11
                                    style: Theme.textStyle(); styleColor: Theme.shadow
                                }
                            }
                        }
                    }
                }
                Repeater {
                    model: r.kind === "item" ? r.cells : []
                    delegate: Text {
                        required property var modelData
                        required property int index
                        x: row.cellX(index)
                        width: row.width * row.r.w[index] - 6
                        height: row.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: modelData[0]
                        color: modelData[1] ? modelData[1] : Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 12
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                }
            }

            // Bars: a column a value, a label under some.
            Item {
                visible: r.kind === "bars"
                anchors.fill: parent
                readonly property var vals: r.kind === "bars" ? r.values : []
                readonly property real most: Math.max.apply(null, [1].concat(vals))
                Text {
                    anchors.right: parent.right
                    text: r.kind === "bars" ? r.top : ""
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 10
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Repeater {
                    model: parent.vals.length
                    delegate: Item {
                        required property int index
                        readonly property real slot: row.width / Math.max(1, row.r.values ? row.r.values.length : 1)
                        x: index * slot
                        width: slot
                        height: row.height
                        Rectangle {
                            x: 1
                            width: Math.max(2, parent.width - 3)
                            height: Math.max(1, (row.height - 30) * (row.r.values[index] / parent.parent.most))
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            color: Theme.accent
                            opacity: 0.8
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: row.r.labels ? row.r.labels[index] || "" : ""
                            color: Theme.dim()
                            font.family: Theme.body
                            font.pixelSize: 10
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                    }
                }
            }

            // Key figures side by side (the Closet's costs).
            Row {
                visible: r.kind === "tiles"
                width: parent.width
                height: parent.height - 6
                spacing: 6
                Repeater {
                    model: r.kind === "tiles" ? r.tiles : []
                    delegate: Rectangle {
                        required property var modelData
                        width: (row.width - 18) / 4
                        height: parent.height
                        color: "#1b1a20"
                        Column {
                            anchors.fill: parent
                            anchors.margins: 6
                            Text { text: modelData[0]; color: Theme.muted(); font.family: Theme.body; font.pixelSize: 11; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Text { text: modelData[1]; color: panel.gold; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.Bold; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData[2]; color: Theme.dim(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                        }
                    }
                }
            }

            // The five cards of a round.
            Row {
                id: cardsRow
                visible: r.kind === "cards"
                y: 4
                width: parent.width
                spacing: 6
                Repeater {
                    model: r.kind === "cards" ? r.cards : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var c: modelData
                        width: (row.width - 24) / 5
                        height: Math.max(170, cardCol.implicitHeight + 16)
                        color: "#1b1a20"
                        border.color: c.best ? Theme.accent : "#2f2d36"
                        Column {
                            id: cardCol
                            x: 6
                            y: 8
                            width: parent.width - 12
                            spacing: 4
                            Item {
                                width: parent.width
                                height: 18
                                Text { text: c.title; color: "#c9c6d0"; font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold; style: Theme.textStyle(); styleColor: Theme.shadow }
                                Text { anchors.right: parent.right; text: c.you; color: c.you === "OTHER" ? Theme.dim() : Theme.accent; font.family: Theme.display; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1; style: Theme.textStyle(); styleColor: Theme.shadow }
                            }
                            Text { visible: c.bonus.length > 0; text: "BONUS"; color: "#c4a8f0"; font.family: Theme.display; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Repeater {
                                model: c.bonus.concat(c.lines)
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool pic: modelData[3] > 0
                                    width: cardCol.width
                                    height: pic ? Math.max(34, nameText.implicitHeight) : nameText.implicitHeight
                                    // The item's picture in a frame of its grade's colour, the count on it.
                                    Rectangle {
                                        id: frame
                                        visible: parent.pic
                                        width: 32
                                        height: 32
                                        color: "#2a2930"
                                        border.color: modelData[1] || "#4a4852"
                                        border.width: modelData[2] ? 2 : 1
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            asynchronous: true
                                            sourceSize.width: 56
                                            source: parent.visible ? panel.iconUrl(LK.C.icon(modelData[3])) : ""
                                        }
                                        Text {
                                            visible: modelData[4] > 1
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 2
                                            text: panel.shortK(modelData[4])
                                            color: "#ffffff"
                                            font.family: Theme.display
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            style: Text.Outline; styleColor: "#000000"
                                        }
                                    }
                                    Text {
                                        id: nameText
                                        x: parent.pic ? 38 : 0
                                        anchors.verticalCenter: parent.pic ? parent.verticalCenter : undefined
                                        width: parent.width - x
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: modelData[0]
                                        color: modelData[2] ? panel.gold : modelData[1] ? modelData[1] : Theme.muted()
                                        font.family: Theme.body
                                        font.pixelSize: 10
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                }
                            }
                            Text { text: c.worth; color: c.best ? Theme.accent : Theme.muted(); font.family: Theme.display; font.pixelSize: 14; font.weight: Font.Bold; style: Theme.textStyle(); styleColor: Theme.shadow }
                        }
                    }
                }
            }
        }
    }
}
