import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "charkit.js" as CK

// The AION 2 module's Characters (the Roster / Content Overview plugin and
// the limits of the Inventory plugin, in QML; design board C1–C3): every
// character you play with Odyle energy and when it is full, what each has
// left of the game's content, and the day's and week's limits. Everything
// is what the game said while you played (CharacterStore, read only);
// refills and recharges since are estimates (≈, striped).
Panel {
    id: panel
    panelId: "characters"
    title: "Characters"
    tag: width < 460 ? "" : "AION 2"
    width: 640
    minWidth: 460
    maxWidth: 1200
    stretchy: true
    minGrow: -180

    /// The characters store (Main.qml's CharacterStore).
    property var store
    readonly property var st: store ? store.state : CK.empty()

    property var prefs: ({ tab: "roster", sort: "full", display: "all", limitsOf: "", hidden: [] })
    // ---- what is tracked: Content's and Limits' entries can be hidden ----
    /// Choosing (CHOOSE in the tab row): every entry shows, an eye on each.
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
        // Screenshots: GC_DEMO=chars,limits (or ,content) opens that tab.
        for (const t of ["content", "limits"]) if (nativeWindow.demo.split(",").indexOf(t) >= 0) prefs = Object.assign({}, prefs, { tab: t })
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
            return { key: r.key, ch: r.ch, cap: cap, est: CK.estimate(r.ch.energy, t, cap), full: CK.fullAt(r.ch.energy, cap), playing: r.key === current }
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
    function cell(c, seen, t) {
        const cap = CK.capOf(c, seen)
        if (seen && cap === 0) return { value: "—", cap: "", seenW: 0, grownW: 0, note: c.siege ? "your side holds none" : "", tone: "dim" }
        const est = CK.countNow(c, seen, t)
        if (!est) return { value: "?", cap: "/ " + CK.grouped(cap), seenW: 0, grownW: 0, tone: "dim",
            note: c.siege && seen ? "after the siege: enter the Abyss" : String(c.id).indexOf("shop:") === 0 ? "open the shop once" : String(c.id).indexOf("craft:") === 0 ? "open crafting once" : "not said yet" }
        const value = (est.gained || est.reset ? "≈ " : "") + CK.grouped(est.left) + (est.extra && !c.used ? " +" + est.extra : "")
        const next = seen.reset && seen.reset > t ? seen.reset : c.every === "daily" ? CK.nextDaily(t) : CK.nextWeekly(t)
        const note = c.used
            ? (c.siege ? (seen.reset > t ? "until the siege, " + CK.span(seen.reset - t) : "") : est.full ? "all done" : "as said " + CK.ago(seen.at, t))
            : est.full ? "full" : "+" + c.add + " in " + CK.span(next - t)
        return { value: value, cap: "/ " + CK.grouped(cap), seenW: Math.min(1, (est.left - est.gained) / cap), grownW: Math.min(1, est.gained / cap),
            note: note, tone: est.full ? (c.used ? "done" : "full") : "" }
    }
    function toneColor(tone) { return tone === "full" ? "#ff8a7a" : tone === "done" ? Theme.accent : tone === "dim" ? Theme.dim() : Theme.text() }

    // ---- Content: the lead's server, its characters ----
    readonly property var contentView: {
        rev; now; prefs; choosing
        const t = now
        const l = lead()
        if (!l) return { server: "", cards: [], chars: [] }
        const sid = l.ch.serverId
        const mine = all().filter((r) => r.ch.serverId === sid)
        const server = st.servers[String(sid)] || {}
        const cards = keep(CK.CONTENT.filter((c) => c.scope === "server").map((c) => {
            const seen = c.ofChars ? CK.sumOfChars(c, mine.map((r) => r.ch), t) : (server.counts || {})[c.id]
            return Object.assign({ id: "c:" + c.id, name: c.name }, cell(c, seen, t))
        }))
        const cols = keep(CK.CONTENT.filter((c) => c.scope === "char").map((c) => Object.assign({ id: "c:" + c.id }, c)))
        const chars = mine.filter(visibleChar)
            .sort((a, b) => (b.key === current) - (a.key === current) || a.ch.name.localeCompare(b.ch.name))
            .map((r) => ({ key: r.key, name: r.ch.name, playing: r.key === current,
                cells: cols.map((c) => cell(c, (r.ch.counts || {})[c.id], t)) }))
        const siege = server.siege && server.siege.next > t ? server.siege.next : 0
        return { server: serverName(sid), cards: cards, heads: cols.map((c) => c.name), headIds: cols.map((c) => c.id), chars: chars, siege: siege }
    }

    // ---- Limits: one character's ----
    readonly property var limitsView: {
        rev; now; choosing
        const t = now
        const key = prefs.limitsOf && st.chars[prefs.limitsOf] ? prefs.limitsOf : (lead() ? lead().key : "")
        const ch = st.chars[key]
        if (!ch) return { key: "", rows: [], tickets: [], times: [] }
        const server = st.servers[String(ch.serverId)] || {}
        const rows = CK.OTHER.map((c) => {
            const home = c.scope === "server" ? server : ch
            return Object.assign({ id: "o:" + c.id, name: c.name, scope: c.scope === "server" ? "all characters on " + serverName(ch.serverId) : "this character" }, cell(c, (home.counts || {})[c.id], t))
        })
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
        const times = []
        for (const id in ch.times || {}) {
            const v = ch.times[id]
            times.push({ id: "m:" + id, name: CK.ticketName(id), value: v.v > 0 ? CK.span(v.v) : "none left", note: "as said " + CK.ago(v.at, t) })
        }
        times.sort((a, b) => a.name.localeCompare(b.name))
        return { key: key, name: ch.name, server: serverName(ch.serverId), playing: key === current, rows: keep(rows), tickets: keep(tickets), times: keep(times) }
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

        // The next refill and the resets.
        Row {
            spacing: 16
            Repeater {
                model: {
                    const t = panel.now
                    const out = []
                    if (panel.prefs.tab === "roster") out.push(["Refill", CK.span(CK.nextRefill(t) - t)])
                    out.push(["Daily reset", CK.span(CK.nextDaily(t) - t)], ["Weekly reset", CK.span(CK.nextWeekly(t) - t)])
                    if (panel.prefs.tab === "content" && panel.contentView.siege) out.push(["Siege", CK.span(panel.contentView.siege - t)])
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

        // The tabs.
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: [["roster", "Roster"], ["content", "Content"], ["limits", "Limits"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.prefs.tab === modelData[0]
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
            // What is tracked: every entry with an eye while choosing.
            Chip {
                visible: panel.prefs.tab !== "roster" && panel.all().length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.choosing ? "Done" : "Choose" + ((panel.prefs.hidden || []).length ? " (" + panel.prefs.hidden.length + " hidden)" : "")
                on: panel.choosing
                onClicked: panel.choosing = !panel.choosing
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

        // ---------------- ROSTER ----------------
        Item {
            visible: panel.prefs.tab === "roster" && panel.all().length > 0
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
        Row {
            id: rosterHead
            visible: panel.prefs.tab === "roster" && panel.all().length > 0
            readonly property var w: [0.36, 0.13, 0.1, 0.08, 0.21, 0.12]
            width: parent.width
            Repeater {
                model: ["Character", "Combat", "Gear", "Level", "Odyle energy", "Full in"]
                delegate: Head {
                    required property var modelData
                    required property int index
                    width: rosterHead.width * rosterHead.w[index]
                    leftPadding: index === 0 ? 10 : 0
                    rightPadding: index === 4 ? 0 : 8
                    horizontalAlignment: index === 0 || index === 4 ? Text.AlignLeft : Text.AlignRight
                    text: modelData.toUpperCase()
                }
            }
        }
        ListView {
            id: rosterList
            visible: panel.prefs.tab === "roster" && panel.all().length > 0
            width: parent.width
            height: visible ? Math.max(Math.min(contentHeight, 120), Math.min(contentHeight, 330 + panel.grow)) : 0
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            model: panel.rosterRows
            WheelScroll { flick: rosterList; step: 94 }
            delegate: Item {
                id: rowItem
                required property var modelData
                readonly property var r: modelData
                readonly property var w: rosterHead.w
                property bool confirm: false
                width: ListView.view.width
                height: 44
                Rectangle {
                    anchors.fill: parent
                    color: r.playing ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : rowMouse.containsMouse ? "#222128" : "#1b1a20"
                }
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; onExited: rowItem.confirm = false }
                Column {
                    x: 10
                    width: parent.width * w[0] - 10
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
                    x: parent.width * w[0]
                    width: parent.width * w[1]
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    text: r.ch.cp ? CK.grouped(r.ch.cp) : "?"
                    font.pixelSize: 14
                }
                Figure {
                    x: parent.width * (w[0] + w[1])
                    width: parent.width * w[2]
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    text: r.ch.gs ? CK.grouped(r.ch.gs) : "?"
                    color: Theme.textSoft()
                    font.pixelSize: 14
                }
                Line {
                    x: parent.width * (w[0] + w[1] + w[2])
                    width: parent.width * w[3]
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    color: Theme.textSoft()
                    text: r.ch.level ? "Lv " + r.ch.level : ""
                }
                Column {
                    x: parent.width * (w[0] + w[1] + w[2] + w[3])
                    width: parent.width * w[4] - 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Bar {
                        width: parent.width
                        seen: r.est ? (r.est.basic - r.est.gained) / r.cap : 0
                        grown: r.est ? r.est.gained / r.cap : 0
                    }
                    Row {
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
                Line {
                    visible: !removeButton.visible
                    x: parent.width * (1 - w[5])
                    width: parent.width * w[5] - 8
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
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.confirm ? "Remove?" : "×"
                    on: rowItem.confirm
                    onClicked: { if (rowItem.confirm) panel.store.remove(r.key); else rowItem.confirm = true }
                }
            }
        }

        // ---------------- CONTENT and LIMITS: a scrolling page ----------------
        Item {
            visible: panel.prefs.tab !== "roster" && panel.all().length > 0
            width: parent.width
            height: visible ? Math.max(Math.min(page.contentHeight, 120), Math.min(page.contentHeight, 420 + panel.grow)) : 0
            WheelScroll { flick: page; step: 90; z: 1 }
        Flickable {
            id: page
            anchors.fill: parent
            clip: true
            contentHeight: panel.prefs.tab === "content" ? contentCol.height : limitsCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            Column {
                id: contentCol
                visible: panel.prefs.tab === "content"
                width: page.width
                spacing: 6
                Head { text: ("On server · " + panel.contentView.server).toUpperCase(); color: Theme.textSoft(); font.pixelSize: 12 }
                Grid {
                    width: parent.width
                    columns: 4
                    spacing: 6
                    Repeater {
                        model: panel.contentView.cards
                        delegate: Rectangle {
                            required property var modelData
                            width: (contentCol.width - 18) / 4
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
                Item { width: 1; height: 4 }
                Head { text: "PER CHARACTER · LEFT"; color: Theme.textSoft(); font.pixelSize: 12 }
                Row {
                    id: charHead
                    width: parent.width
                    readonly property real first: 0.34
                    Head { width: charHead.width * charHead.first; leftPadding: 10; text: "CHARACTER" }
                    Repeater {
                        model: panel.contentView.heads || []
                        delegate: Head {
                            required property var modelData
                            required property int index
                            readonly property string entry: (panel.contentView.headIds || [])[index] || ""
                            width: charHead.width * (1 - charHead.first) / Math.max(1, (panel.contentView.heads || []).length)
                            horizontalAlignment: Text.AlignRight
                            rightPadding: panel.choosing ? 30 : 10
                            text: modelData.toUpperCase()
                            opacity: panel.shown(entry) ? 1 : 0.4
                            Eye { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; entry: parent.entry }
                        }
                    }
                }
                Repeater {
                    model: panel.contentView.chars
                    delegate: Rectangle {
                        required property var modelData
                        width: contentCol.width
                        height: 40
                        color: modelData.playing ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : "#1b1a20"
                        Line {
                            x: 10
                            width: parent.width * charHead.first - 10
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 13
                            font.weight: modelData.playing ? Font.Bold : Font.Medium
                            color: modelData.playing ? Theme.accent : Theme.text()
                            text: modelData.name
                        }
                        Repeater {
                            model: modelData.cells
                            delegate: Column {
                                required property var modelData
                                required property int index
                                readonly property real cw: contentCol.width * (1 - charHead.first) / Math.max(1, (panel.contentView.heads || []).length)
                                x: contentCol.width * charHead.first + index * cw
                                width: cw - 10
                                anchors.verticalCenter: parent.verticalCenter
                                Row {
                                    anchors.right: parent.right
                                    spacing: 4
                                    Figure { text: modelData.value; color: panel.toneColor(modelData.tone) }
                                    Line { anchors.baseline: parent.children[0].baseline; font.pixelSize: 11; color: Theme.dim(); text: modelData.cap }
                                }
                                Line { anchors.right: parent.right; font.pixelSize: 10; color: Theme.dim(); text: modelData.note }
                            }
                        }
                    }
                }
                Line {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: 11
                    color: Theme.dim()
                    text: "As the game last said. ≈: recharged since, an estimate. +N: from recharge items. Daily Duty: the server's characters together, back to 0 at the daily reset. Abyss Corridors: done of those your side holds since the last Artifact Siege (the holders as the game said when you were in the Abyss)."
                }
            }

            Column {
                id: limitsCol
                visible: panel.prefs.tab === "limits"
                width: page.width
                spacing: 6
                z: 2
                Item {
                    width: parent.width
                    height: 36
                    z: 10
                    Dropdown {
                        id: charPick
                        width: Math.min(parent.width, 300)
                        label: "Character"
                        current: panel.limitsView.key
                        options: panel.all().slice().sort((a, b) => (b.ch.seen || 0) - (a.ch.seen || 0)).map((r) => ({ id: r.key, name: r.ch.name + " · " + panel.serverName(r.ch.serverId) }))
                        onChosen: (id) => panel.change("limitsOf", id)
                    }
                    Line {
                        anchors.left: charPick.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.dim()
                        font.pixelSize: 11
                        text: panel.limitsView.playing ? "playing now" : ""
                    }
                }
                Head { text: "TODAY AND THIS WEEK"; color: Theme.textSoft(); font.pixelSize: 12 }
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: panel.limitsView.rows
                        delegate: limitBox
                    }
                }
                Head { visible: panel.limitsView.tickets.length > 0; text: "KEYS AND ENTRIES"; color: Theme.textSoft(); font.pixelSize: 12 }
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: panel.limitsView.tickets
                        delegate: limitBox
                    }
                }
                Head { visible: panel.limitsView.times.length > 0; text: "USAGE TIME LEFT"; color: Theme.textSoft(); font.pixelSize: 12 }
                Grid {
                    width: parent.width
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: panel.limitsView.times
                        delegate: limitBox
                    }
                }
                Line {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: 11
                    color: Theme.dim()
                    text: "Shop limits and crafts come once the shop or the crafting window has opened on a character; keys and entries at each login and when they change. Names and highest counts: the game client, via SkeeveAN's Aion-DPS-Meter (MIT)."
                }
            }
        }
        }
    }

    Component {
        id: limitBox
        Rectangle {
            required property var modelData
            width: (limitsCol.width - 6) / 2
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
