import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "charkit.js" as CK

// The AION 2 module's Characters (the Roster / Content Overview plugin and
// the limits of the Inventory plugin, in QML; design board C1–C3), one view
// without tabs (MN, 2026-11-15): the server's content as cards, then one
// table, a row per character: Odyle energy and when it is full, what its
// server can still buy and craft (server-wide), its own limits and what it
// has left of the game's content; under it the keys, entries and usage
// time of the character picked in the table. Everything is what the game
// said while you played (CharacterStore, read only); refills and recharges
// since are estimates (≈, striped).
Panel {
    id: panel
    panelId: "characters"
    title: "Characters"
    tag: width < 460 ? "" : "AION 2"
    width: 1180
    minWidth: 620
    maxWidth: 1800
    stretchy: true
    minGrow: -180

    /// The characters store (Main.qml's CharacterStore).
    property var store
    /// The Armory's store: each character's active build and its progress.
    property var armory: null
    readonly property var st: store ? store.state : CK.empty()

    property var prefs: ({ sort: "full", display: "all", limitsOf: "", hidden: [] })
    // ---- what is tracked: cards, columns and entries can be hidden ----
    /// Choosing (CHOOSE above the table): every entry shows, an eye on each.
    property bool choosing: nativeWindow.demo.split(",").indexOf("choose") >= 0
    function shown(id) { return (prefs.hidden || []).indexOf(id) < 0 }
    function toggleShown(id) {
        const h = (prefs.hidden || []).slice()
        const i = h.indexOf(id)
        if (i >= 0) h.splice(i, 1); else h.push(id)
        change("hidden", h)
    }
    /// The entries of a list to show now (all of them while choosing).
    function keep(list) { return choosing ? list : list.filter((x) => shown(x.id)) }
    function change(key, value) {
        const p = Object.assign({}, prefs)
        p[key] = value
        prefs = p
        saveTimer.restart()
    }
    Timer { id: saveTimer; interval: 400; onTriggered: Aion2.keepStore("characters-view", JSON.stringify(panel.prefs)) }
    Component.onCompleted: {
        try { prefs = Object.assign({}, prefs, JSON.parse(Aion2.loadStore("characters-view") || "{}")) } catch (e) { }
    }

    // The time the numbers are for: again with every change of the store,
    // and every minute while shown (no timer while closed).
    property real now: Date.now()
    Timer { interval: 60000; repeat: true; running: panel.visible; onTriggered: panel.now = Date.now() }
    Connections { target: panel.store; function onRevisionChanged() { panel.now = Date.now() } }
    readonly property int rev: store ? store.revision : 0

    // ---- who ----
    function all() {
        rev
        const out = []
        for (const key in st.chars) out.push({ key: key, ch: st.chars[key] })
        return out
    }
    readonly property string current: store ? store.current : ""
    /// The one playing, else the last played.
    function lead() {
        const list = all()
        if (current && st.chars[current]) return { key: current, ch: st.chars[current] }
        list.sort((a, b) => (b.ch.seen || 0) - (a.ch.seen || 0))
        return list.length ? list[0] : null
    }
    function serverName(id) { return store ? store.serverName(id) : String(id) }
    function visibleChar(r) {
        const me = st.chars[current]
        if (!me) return true
        if (prefs.display === "server") return r.ch.serverId === me.serverId
        if (prefs.display === "side") {
            const side = CK.sideOf(me.serverId)
            return !side || CK.sideOf(r.ch.serverId) === side
        }
        return true
    }
    property string search: ""

    // ---- the roster's rows ----
    readonly property var rosterRows: {
        rev; now
        const t = now
        const rows = all().filter(visibleChar).filter((r) => {
            const q = search.trim().toLowerCase()
            return !q || r.ch.name.toLowerCase().indexOf(q) >= 0 || serverName(r.ch.serverId).toLowerCase().indexOf(q) >= 0
        }).map((r) => {
            const cap = CK.capFor(st, r.ch, t)
            const server = st.servers[String(r.ch.serverId)] || {}
            return { key: r.key, ch: r.ch, cap: cap, est: CK.estimate(r.ch.energy, t, cap), full: CK.fullAt(r.ch.energy, cap), playing: r.key === current,
                cells: countCols.map((c) => cell(c, ((c.scope === "server" ? server : r.ch).counts || {})[c.raw], t, true)) }
        })
        const by = {
            name: (a, b) => a.ch.name.localeCompare(b.ch.name),
            cp: (a, b) => (b.ch.cp || 0) - (a.ch.cp || 0),
            gs: (a, b) => (b.ch.gs || 0) - (a.ch.gs || 0),
            energy: (a, b) => (b.est ? b.est.basic : -1) - (a.est ? a.est.basic : -1),
            full: (a, b) => (a.est && a.est.full ? 0 : a.full != null ? a.full : Infinity) - (b.est && b.est.full ? 0 : b.full != null ? b.full : Infinity),
            seen: (a, b) => (b.playing - a.playing) || (b.ch.seen || 0) - (a.ch.seen || 0)
        }[prefs.sort] || ((a, b) => a.ch.name.localeCompare(b.ch.name))
        rows.sort((a, b) => by(a, b) || a.ch.name.localeCompare(b.ch.name))
        return rows
    }
    readonly property var sorts: [["full", "Full soonest"], ["name", "Name"], ["cp", "Combat power"], ["gs", "Gear score"], ["energy", "Energy"], ["seen", "Last played"]]
    function sortName() { for (const s of sorts) if (s[0] === prefs.sort) return s[1]; return "Name" }
    function nextSort() {
        let i = 0
        for (let k = 0; k < sorts.length; k++) if (sorts[k][0] === prefs.sort) i = k
        change("sort", sorts[(i + 1) % sorts.length][0])
    }

    // ---- a count's cell: value, bar, note ----
    function cell(c, seen, t, tight) {
        const num = tight ? CK.compact : CK.grouped
        const cap = CK.capOf(c, seen)
        if (seen && cap === 0) return { value: "—", cap: "", seenW: 0, grownW: 0, note: c.siege ? "your side holds none" : "", tone: "dim" }
        const est = CK.countNow(c, seen, t)
        if (!est) return { value: "?", cap: "/ " + num(cap), seenW: 0, grownW: 0, tone: "dim",
            note: tight ? "" : c.siege && seen ? "after the siege: enter the Abyss" : String(c.id).indexOf("shop:") === 0 ? "open the shop once" : String(c.id).indexOf("craft:") === 0 ? "open crafting once" : "not said yet" }
        const value = (est.gained || est.reset ? "≈ " : "") + num(est.left) + (est.extra && !c.used ? " +" + est.extra : "")
        const next = seen.reset && seen.reset > t ? seen.reset : c.every === "daily" ? CK.nextDaily(t) : CK.nextWeekly(t)
        let note = c.used
            ? (c.siege ? (seen.reset > t ? "until the siege, " + CK.span(seen.reset - t) : "") : est.full ? "all done" : "as said " + CK.ago(seen.at, t))
            : est.full ? "full" : "+" + c.add + " in " + CK.span(next - t)
        // The table's narrow cells: the note in few words.
        if (tight) note = note.replace(/^as said /, "").replace("until the siege, ", "siege in ")
        return { value: value, cap: "/ " + num(cap), seenW: Math.min(1, (est.left - est.gained) / cap), grownW: Math.min(1, est.gained / cap),
            note: note, tone: est.full ? (c.used ? "done" : "full") : "" }
    }
    function toneColor(tone) { return tone === "full" ? "#ff8a7a" : tone === "done" ? Theme.accent : tone === "dim" ? Theme.dim() : Theme.text() }

    // ---- the table's count columns: server-wide, this character, content ----
    // Ids stay those of the old Content and Limits tabs ("c:", "o:"), so
    // what was hidden there stays hidden.
    readonly property var heads: ({ "shop:1210": "Buy", "craft:32070001": "Craft", "shop:1209": "Buy", "craft:32070002": "Craft",
        "kinah:today": "Kinah", "abyss:week": "Abyss pts", "4": "Nightmare", "80000001": "Ascension", "abyss:corridors": "Corridors" })
    readonly property var groupNames: ({ server: "Server-wide", char: "This character", content: "Content left" })
    readonly property var countCols: {
        prefs; choosing
        const of = (list, ids, g, pre) => ids.map((id) => list.filter((c) => String(c.id) === id)[0])
            .filter((c) => c).map((c) => Object.assign({}, c, { raw: c.id, id: pre + c.id, head: heads[String(c.id)] || c.name, group: g }))
        return keep(of(CK.OTHER, ["shop:1210", "craft:32070001"], "server", "o:")
            .concat(of(CK.OTHER, ["shop:1209", "craft:32070002", "kinah:today", "abyss:week"], "char", "o:"))
            .concat(of(CK.CONTENT, ["4", "80000001", "abyss:corridors"], "content", "c:")))
    }
    /// The groups over the count columns: name, first column, how many.
    readonly property var groups: {
        const out = []
        countCols.forEach((c, i) => {
            if (out.length && out[out.length - 1].g === c.group) out[out.length - 1].n++
            else out.push({ g: c.group, name: groupNames[c.group], at: i, n: 1 })
        })
        return out
    }
    // Widths as parts of the table: the roster's columns, then the counts.
    readonly property real rosterPart: countCols.length ? 0.45 : 1
    readonly property var rw: [0.30, 0.12, 0.11, 0.09, 0.25, 0.13].map((x) => x * rosterPart)
    function rx(i) { let x = 0; for (let k = 0; k < i; k++) x += rw[k]; return x }
    readonly property real cw: countCols.length ? (1 - rosterPart) / countCols.length : 0

    // ---- the server's content: the lead's server ----
    readonly property var serverView: {
        rev; now; prefs; choosing
        const t = now
        const l = lead()
        if (!l) return { server: "", cards: [] }
        const sid = l.ch.serverId
        const mine = all().filter((r) => r.ch.serverId === sid)
        const server = st.servers[String(sid)] || {}
        const cards = keep(CK.CONTENT.filter((c) => c.scope === "server").map((c) => {
            const seen = c.ofChars ? CK.sumOfChars(c, mine.map((r) => r.ch), t) : (server.counts || {})[c.id]
            return Object.assign({ id: "c:" + c.id, name: c.name }, cell(c, seen, t))
        }))
        const siege = server.siege && server.siege.next > t ? server.siege.next : 0
        return { server: serverName(sid), cards: cards, siege: siege }
    }

    // ---- keys, entries and time: the character picked in the table ----
    readonly property var extraView: {
        rev; now; choosing
        const t = now
        const key = prefs.limitsOf && st.chars[prefs.limitsOf] ? prefs.limitsOf : (lead() ? lead().key : "")
        const ch = st.chars[key]
        if (!ch) return { key: "", name: "", tickets: [], times: [] }
        const server = st.servers[String(ch.serverId)] || {}
        const tickets = []
        const add = (bag, server) => {
            for (const id in bag || {}) {
                const k = CK.ticketNow(id, bag[id], t)
                if (!k) continue
                tickets.push({ id: "t:" + id, name: k.name, value: k.stale ? "?" : CK.grouped(k.left) + (k.extra ? " +" + k.extra : ""), cap: k.max ? "/ " + k.max : "",
                    w: k.stale || !k.max ? 0 : Math.min(1, k.left / k.max), note: (server ? "server · " : "") + (k.stale ? "a reset passed since, " : "as said ") + CK.ago(k.at, t), tone: k.stale ? "dim" : "" })
            }
        }
        add(ch.tickets, false)
        add(server.tickets, true)
        tickets.sort((a, b) => a.name.localeCompare(b.name))
        for (const id in ch.times || {}) {
            const v = ch.times[id]
            tickets.push({ id: "m:" + id, name: CK.ticketName(id), value: v.v > 0 ? CK.span(v.v) : "none left", note: "usage time · as said " + CK.ago(v.at, t) })
        }
        return { key: key, name: ch.name, server: serverName(ch.serverId), tickets: keep(tickets) }
    }

    // ---- what it looks like ----
    // An entry's eye while choosing: open = tracked, struck through = hidden.
    component Eye: Item {
        property string entry
        readonly property bool on: panel.shown(entry)
        visible: panel.choosing
        width: 22
        height: 22
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45); border.color: parent.on ? Theme.accent : Theme.track }
        HudIcon { anchors.centerIn: parent; name: parent.on ? "eye" : "hide"; size: 12; color: parent.on ? Theme.accent : Theme.dim() }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.toggleShown(parent.entry) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
        Accessible.name: "Track this"
    }
    component Head: Text {
        color: Theme.dim()
        font.family: Theme.display
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Line: Text {
        color: Theme.text()
        font.family: Theme.body
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Figure: Text {
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 15
        font.weight: Font.Bold
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A bar: what the game said solid, refills since striped (ticks).
    component Bar: Item {
        property real seen: 0
        property real grown: 0
        property color colour: Theme.accent
        height: 5
        Rectangle { anchors.fill: parent; color: Theme.trackDark }
        Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.seen)); height: parent.height; color: parent.colour }
        Row {
            x: parent.width * Math.max(0, Math.min(1, parent.seen))
            width: parent.width * Math.max(0, Math.min(1 - parent.seen, parent.grown))
            height: parent.height
            clip: true
            Repeater {
                model: Math.ceil(parent.width / 4)
                Rectangle { width: 4; height: 5; color: index % 2 ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.2) : Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.65) }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 8

        // The next refill, the resets and the siege.
        Row {
            spacing: 16
            Repeater {
                model: {
                    const t = panel.now
                    const out = [["Refill", CK.span(CK.nextRefill(t) - t)], ["Daily reset", CK.span(CK.nextDaily(t) - t)], ["Weekly reset", CK.span(CK.nextWeekly(t) - t)]]
                    if (panel.serverView.siege) out.push(["Siege", CK.span(panel.serverView.siege - t)])
                    return out
                }
                delegate: Text {
                    required property var modelData
                    text: modelData[0] + "  <b>" + modelData[1] + "</b>"
                    textFormat: Text.StyledText
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }

        // Nothing yet.
        Line {
            visible: panel.all().length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Theme.muted()
            text: "No characters yet. They come as you play: start AION 2 with this app running and log in (the game says the most at a login)."
        }

        // Who shows, what is tracked, the order, a search.
        Item {
            visible: panel.all().length > 0
            width: parent.width
            height: visible ? 26 : 0
            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Chip { text: "All"; on: panel.prefs.display === "all"; onClicked: panel.change("display", "all") }
                Chip { text: "This server"; on: panel.prefs.display === "server"; onClicked: panel.change("display", "server") }
                Chip { text: "This side"; on: panel.prefs.display === "side"; onClicked: panel.change("display", "side") }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                // What is tracked: every card, column and entry with an eye while choosing.
                Chip {
                    text: panel.choosing ? "Done" : "Choose" + ((panel.prefs.hidden || []).length ? " (" + panel.prefs.hidden.length + " hidden)" : "")
                    on: panel.choosing
                    onClicked: panel.choosing = !panel.choosing
                }
                Chip { text: "Sort: " + panel.sortName(); onClicked: panel.nextSort() }
                Rectangle {
                    width: 130
                    height: 24
                    color: "#1b1a20"
                    border.color: searchInput.activeFocus ? Theme.accent : "#3a3842"
                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text()
                        selectionColor: Theme.accent
                        font.family: Theme.body
                        font.pixelSize: 12
                        clip: true
                        onTextEdited: panel.search = text
                        Keys.onEscapePressed: focus = false
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Search"
                            color: Theme.dim()
                            font: searchInput.font
                        }
                    }
                }
            }
        }

        // ---------------- one scrolling page ----------------
        Item {
            visible: panel.all().length > 0
            width: parent.width
            height: visible ? Math.max(Math.min(page.contentHeight, 160), Math.min(page.contentHeight, 520 + panel.grow)) : 0
            WheelScroll { flick: page; step: 90; z: 1 }
        Flickable {
            id: page
            anchors.fill: parent
            clip: true
            contentHeight: pageCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            Column {
                id: pageCol
                width: page.width
                spacing: 6
                z: 2

                // The server's content.
                Head { visible: panel.serverView.cards.length > 0; text: ("On server · " + panel.serverView.server).toUpperCase(); color: Theme.textSoft(); font.pixelSize: 12 }
                Grid {
                    width: parent.width
                    columns: 4
                    spacing: 6
                    Repeater {
                        model: panel.serverView.cards
                        delegate: Rectangle {
                            required property var modelData
                            width: (pageCol.width - 18) / 4
                            height: 74
                            color: "#1b1a20"
                            opacity: panel.shown(modelData.id) ? 1 : 0.4
                            Eye { z: 2; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4; entry: modelData.id }
                            Column {
                                anchors.fill: parent
                                anchors.margins: 8
                                anchors.rightMargin: panel.choosing ? 30 : 8
                                spacing: 4
                                Line { width: parent.width; font.pixelSize: 11; color: Theme.muted(); text: modelData.name }
                                Row {
                                    spacing: 4
                                    Figure { text: modelData.value; font.pixelSize: 17; color: panel.toneColor(modelData.tone) }
                                    Line { anchors.baseline: parent.children[0].baseline; font.pixelSize: 11; color: Theme.dim(); text: modelData.cap }
                                }
                                Bar { width: parent.width; height: 4; seen: modelData.seenW; grown: modelData.grownW }
                                Line { width: parent.width; font.pixelSize: 10; color: Theme.dim(); text: modelData.note }
                            }
                        }
                    }
                }
                Item { width: 1; height: 4; visible: panel.serverView.cards.length > 0 }

                // The table's groups over the count columns.
                Item {
                    id: groupRow
                    width: parent.width
                    height: panel.countCols.length ? 16 : 0
                    visible: panel.countCols.length > 0
                    Repeater {
                        model: panel.groups
                        delegate: Item {
                            required property var modelData
                            x: groupRow.width * (panel.rosterPart + modelData.at * panel.cw) + 6
                            width: groupRow.width * modelData.n * panel.cw - 12
                            height: 16
                            Head { anchors.right: parent.right; text: modelData.name.toUpperCase(); color: Theme.textSoft(); font.pixelSize: 10 }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
                        }
                    }
                }
                // The table's columns.
                Item {
                    id: tableHead
                    width: parent.width
                    height: 18
                    Repeater {
                        model: ["Character", "Combat", "Gear", "Level", "Odyle energy", "Full in"]
                        delegate: Head {
                            required property var modelData
                            required property int index
                            x: tableHead.width * panel.rx(index)
                            width: tableHead.width * panel.rw[index]
                            leftPadding: index === 0 ? 10 : 0
                            rightPadding: index === 4 ? 0 : 8
                            horizontalAlignment: index === 0 || index === 4 ? Text.AlignLeft : Text.AlignRight
                            text: modelData.toUpperCase()
                        }
                    }
                    Repeater {
                        model: panel.countCols
                        delegate: Head {
                            required property var modelData
                            required property int index
                            x: tableHead.width * (panel.rosterPart + index * panel.cw)
                            width: tableHead.width * panel.cw
                            horizontalAlignment: Text.AlignRight
                            rightPadding: panel.choosing ? 30 : 10
                            font.letterSpacing: 0.6
                            text: modelData.head.toUpperCase()
                            opacity: panel.shown(modelData.id) ? 1 : 0.4
                            Eye { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; entry: modelData.id }
                        }
                    }
                }

                // A row per character; a click picks it for the entries below.
                Repeater {
                    model: panel.rosterRows
                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        readonly property var r: modelData
                        readonly property bool picked: panel.extraView.key === r.key
                        property bool confirm: false
                        width: pageCol.width
                        height: 44
                        Rectangle {
                            anchors.fill: parent
                            color: r.playing ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : rowMouse.containsMouse ? "#222128" : "#1b1a20"
                        }
                        Rectangle { visible: rowItem.picked; width: 2; height: parent.height; color: Theme.accent }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onExited: rowItem.confirm = false
                            onClicked: panel.change("limitsOf", r.key)
                        }
                        Column {
                            x: 10
                            width: parent.width * panel.rw[0] - 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Row {
                                spacing: 6
                                width: parent.width
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: CK.classColour(r.ch["class"]) }
                                Line {
                                    width: Math.min(implicitWidth, parent.width - 13 - (playTag.visible ? playTag.width + 6 : 0))
                                    text: r.ch.name
                                    font.pixelSize: 13
                                    font.weight: r.playing ? Font.Bold : Font.Medium
                                    color: r.playing ? Theme.accent : Theme.text()
                                }
                                Text {
                                    id: playTag
                                    visible: r.playing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "PLAYING"
                                    color: Theme.accent
                                    font.family: Theme.display
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                }
                            }
                            Line {
                                width: parent.width
                                font.pixelSize: 11
                                color: Theme.dim()
                                text: [r.ch["class"] || "", panel.serverName(r.ch.serverId), r.playing ? "now" : r.ch.seen ? "played " + CK.ago(r.ch.seen, panel.now) : ""].filter((s) => s).join(" · ")
                            }
                        }
                        Figure {
                            x: parent.width * panel.rx(1)
                            width: parent.width * panel.rw[1]
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            rightPadding: 8
                            text: r.ch.cp ? CK.grouped(r.ch.cp) : "?"
                            font.pixelSize: 14
                        }
                        Column {
                            x: parent.width * panel.rx(2)
                            width: parent.width * panel.rw[2]
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property var build: panel.armory ? (panel.armory.revision, panel.armory.progressOf(r.key)) : null
                            Figure {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 8
                                text: r.ch.gs ? CK.grouped(r.ch.gs) : "?"
                                color: Theme.textSoft()
                                font.pixelSize: 14
                            }
                            // The Armory's active build: how far this character is.
                            Line {
                                visible: !!parent.build
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 8
                                font.pixelSize: 10
                                color: Theme.accent
                                text: parent.build ? "build " + (parent.build.p != null ? Math.round(parent.build.p * 100) + " %" : "—") : ""
                            }
                        }
                        Line {
                            x: parent.width * panel.rx(3)
                            width: parent.width * panel.rw[3]
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            rightPadding: 8
                            color: Theme.textSoft()
                            text: r.ch.level ? "Lv " + r.ch.level : ""
                        }
                        Column {
                            x: parent.width * panel.rx(4)
                            width: parent.width * panel.rw[4] - 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Bar {
                                width: parent.width
                                seen: r.est ? (r.est.basic - r.est.gained) / r.cap : 0
                                grown: r.est ? r.est.gained / r.cap : 0
                            }
                            Row {
                                width: parent.width
                                clip: true
                                spacing: 4
                                Line {
                                    font.pixelSize: 11
                                    color: Theme.muted()
                                    text: r.est ? (r.est.gained ? "≈ " : "") + r.est.basic + " /" : "?"
                                }
                                // The cap: a click switches 840 and 560 (a membership ran out).
                                Line {
                                    font.pixelSize: 11
                                    color: capMouse.containsMouse ? Theme.accent : Theme.muted()
                                    text: String(r.cap)
                                    font.underline: capMouse.containsMouse
                                    MouseArea {
                                        id: capMouse
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: panel.store.toggleCap(r.key)
                                    }
                                }
                                Line {
                                    visible: !!(r.est && r.est.charged)
                                    font.pixelSize: 11
                                    color: Theme.dim()
                                    text: r.est ? "+" + r.est.charged + " charged" : ""
                                }
                            }
                        }
                        Item {
                            x: parent.width * panel.rx(5)
                            width: parent.width * panel.rw[5] - 8
                            height: parent.height
                            Line {
                                visible: !removeButton.visible
                                width: parent.width
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                font.weight: Font.DemiBold
                                color: r.est && r.est.full ? "#ff8a7a" : Theme.textSoft()
                                text: !r.est ? "?" : r.est.full ? "FULL" : r.full ? CK.span(r.full - panel.now) : ""
                            }
                            // Take it out (once more to be sure); it comes back when played.
                            Chip {
                                id: removeButton
                                visible: rowMouse.containsMouse && !r.playing || rowItem.confirm
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: rowItem.confirm ? "Remove?" : "×"
                                on: rowItem.confirm
                                onClicked: { if (rowItem.confirm) panel.store.remove(r.key); else rowItem.confirm = true }
                            }
                        }
                        // Server-wide, this character's limits, content left.
                        Repeater {
                            model: r.cells
                            delegate: Column {
                                required property var modelData
                                required property int index
                                x: rowItem.width * (panel.rosterPart + index * panel.cw)
                                width: rowItem.width * panel.cw - 10
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: panel.shown((panel.countCols[index] || {}).id) ? 1 : 0.4
                                Row {
                                    anchors.right: parent.right
                                    spacing: 3
                                    Figure { text: modelData.value; font.pixelSize: 13; color: panel.toneColor(modelData.tone) }
                                    Line { anchors.baseline: parent.children[0].baseline; font.pixelSize: 10; color: Theme.dim(); text: modelData.cap }
                                }
                                Line { anchors.right: parent.right; width: Math.min(implicitWidth, parent.width); horizontalAlignment: Text.AlignRight; font.pixelSize: 10; color: Theme.dim(); text: modelData.note }
                            }
                        }
                    }
                }

                // Keys, entries and usage time of the picked character.
                Item { width: 1; height: 4; visible: panel.extraView.tickets.length > 0 }
                Head {
                    visible: panel.extraView.tickets.length > 0
                    text: ("Keys, entries and time · " + panel.extraView.name).toUpperCase()
                    color: Theme.textSoft()
                    font.pixelSize: 12
                }
                Grid {
                    id: extraCol
                    readonly property int cols: width >= 900 ? 3 : 2
                    width: parent.width
                    columns: cols
                    spacing: 6
                    Repeater {
                        model: panel.extraView.tickets
                        delegate: limitBox
                    }
                }
                Line {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: 11
                    color: Theme.dim()
                    text: "As the game last said. ≈: recharged since, an estimate. +N: from recharge items. Server-wide: what all characters on that server can buy and craft together. Daily Duty: the server's characters together, back to 0 at the daily reset. Abyss Corridors: done of those your side holds since the last Artifact Siege. Shop limits and crafts come once the shop or the crafting window has opened on a character. Click a character for its keys and entries. Names and highest counts: the game client, via SkeeveAN's Aion-DPS-Meter (MIT)."
                }
            }
        }
        }
    }

    Component {
        id: limitBox
        Rectangle {
            required property var modelData
            width: (extraCol.width - 6 * (extraCol.cols - 1)) / extraCol.cols
            // Long names (the game's entries) take a second line, not "…".
            height: Math.max(52, boxColumn.implicitHeight + 16)
            color: "#1b1a20"
            opacity: panel.shown(modelData.id) ? 1 : 0.4
            Eye { z: 2; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 6; entry: modelData.id }
            Column {
                id: boxColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                anchors.rightMargin: panel.choosing ? 36 : 8
                spacing: 4
                Item {
                    width: parent.width
                    height: Math.max(16, nameLine.implicitHeight)
                    Line {
                        id: nameLine
                        width: parent.width - valueRow.width - 6
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        text: modelData.name
                    }
                    Row {
                        id: valueRow
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 4
                        Figure { font.pixelSize: 14; text: modelData.value; color: panel.toneColor(modelData.tone) }
                        Line { anchors.baseline: parent.children[0].baseline; font.pixelSize: 11; color: Theme.dim(); text: modelData.cap || "" }
                    }
                }
                Bar {
                    width: parent.width
                    height: 4
                    visible: modelData.seenW !== undefined || modelData.w !== undefined
                    seen: modelData.seenW !== undefined ? modelData.seenW : modelData.w || 0
                    grown: modelData.grownW || 0
                    colour: modelData.tone === "full" ? "#ff8a7a" : Theme.accent
                }
                Line { width: parent.width; font.pixelSize: 10; color: Theme.dim(); text: (modelData.scope ? modelData.scope + " · " : "") + (modelData.note || "") }
            }
        }
    }
}
