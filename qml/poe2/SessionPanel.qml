import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "sessionkit.js" as SK

// The PoE 2 session tracker (MN, 2026-11-15; like LOOT → DROPS → Session in
// the AION 2 module): the running session or an earlier one, its numbers,
// where the time went, the maps run and the campaign's acts. Read from the
// game's log only. Counts up once a minute while shown and PoE 2 runs.
Panel {
    id: panel
    panelId: "poe2-session"
    title: "Session"
    tag: width < 440 ? "" : "PATH OF EXILE 2"
    width: 520
    minWidth: 400
    maxWidth: 900
    stretchy: true
    minGrow: -160

    property var store: null
    /// The earlier session looked at (its start), or 0 for the running one.
    property real pastStart: 0

    property real now: Date.now()
    Timer { interval: 60000; repeat: true; running: panel.visible && !!panel.store && panel.store.on && panel.pastStart === 0; onTriggered: { panel.now = Date.now(); panel.store.freshen() } }
    onVisibleChanged: { now = Date.now(); if (visible && store) store.freshen() }
    Connections { target: panel.store; function onUpdated() { panel.now = Date.now() } }

    readonly property var shown: {
        if (!store) return null
        store.revision
        if (pastStart) {
            for (let i = 0; i < store.history.length; i++) if (store.history[i].start === pastStart) return store.history[i]
        }
        return store.session
    }
    readonly property var v: shown ? store.viewOf(shown, pastStart ? (shown.end || shown.start) : now) : null

    /// A worth in divines, small ones in exalted.
    function worthText(div) {
        if (div == null) return "no price"
        const ex = store && store.rates ? store.rates.exalted : 0
        if (div < 1 && ex) return Math.round(div * ex) + " ex"
        return (div < 10 ? div.toFixed(2) : div.toFixed(1)) + " div"
    }
    /// The currency rows: the usual three, then what the session holds.
    readonly property var curRows: {
        if (!store || !v) return []
        const rows = store.usualCurrency.map((u) => ({ id: u[0], name: u[1] }))
        const known = rows.map((r) => r.id)
        for (const id in v.loot.cur) if (known.indexOf(id) < 0) rows.push({ id: id, name: v.loot.names[id] || id })
        return rows
    }
    readonly property var addOptions: {
        if (!store || !store.rates) return []
        const have = curRows.map((r) => r.id)
        return [{ id: "", name: "" }].concat(store.rates.list.filter((c) => have.indexOf(c.id) < 0).slice(0, 60).map((c) => ({ id: c.id, name: c.name })))
    }

    function when(t) { return Qt.formatDateTime(new Date(t), "ddd d MMM, hh:mm") }
    function clockOf(t) { return Qt.formatDateTime(new Date(t), "hh:mm") }
    readonly property var options: {
        if (!store) return []
        store.revision
        const label = (h) => panel.when(h.start) + " – " + panel.clockOf(h.end || h.last || h.start) + "  (" + SK.span(SK.view(h, h.end || h.start).played) + ")"
        return [{ id: "", name: "This session" }].concat(store.history.map((h) => ({ id: String(h.start), name: label(h) })))
    }

    readonly property var kinds: [
        { k: "map", name: "Maps", color: Theme.accent },
        { k: "hideout", name: "Hideout", color: "#8d8996" },
        { k: "town", name: "Town", color: "#d9d6de" },
        { k: "campaign", name: "Campaign", color: Theme.purple },
        { k: "other", name: "Other", color: "#4fa8ff" }
    ]

    component Line: Text {
        color: Theme.text()
        font.family: Theme.body
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Small: Text {
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 11
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Head: Text {
        color: Theme.muted()
        font.family: Theme.display
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A number with its label under it.
    component Tile: Rectangle {
        id: tile
        property string label
        property string value
        property string sub: ""
        property color tint: Theme.text()
        width: (tiles.width - tiles.spacing * 2) / 3
        height: 52
        color: Qt.rgba(1, 1, 1, 0.03)
        border.color: Theme.divider
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Row {
                spacing: 5
                Text {
                    text: tile.value
                    color: tile.tint
                    font.family: Theme.display
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    visible: text.length > 0
                    text: tile.sub
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
            Text {
                text: tile.label.toUpperCase()
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }
    }

    Column {
        width: parent.width
        spacing: 10

        // Which session, and a new one.
        Item {
            width: parent.width
            height: 32
            z: 5
            Dropdown {
                id: pick
                width: Math.min(parent.width - (newChip.visible ? newChip.width + 8 : 0), 340)
                label: "Session"
                options: panel.options
                current: panel.pastStart ? String(panel.pastStart) : ""
                onChosen: (id) => panel.pastStart = id === "" ? 0 : Number(id)
            }
            Chip {
                id: newChip
                visible: panel.pastStart === 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "New session"
                onClicked: panel.store.startNew()
            }
        }

        // Where the numbers come from.
        Small {
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            visible: panel.pastStart === 0
            text: !panel.store ? "" : panel.store.demoOn ? "Made-up evening (demo)."
                : !panel.store.on ? "Counts while Path of Exile 2 runs (from the game's own log, Client.txt)."
                : Poe2Log.file ? "Reading " + Poe2Log.file + (panel.v && panel.v.idle ? " · paused (AFK or not in an area)" : "")
                : "Looking for Client.txt… If it is not found, give its path below."
        }

        Grid {
            id: tiles
            width: parent.width
            columns: 3
            spacing: 6
            Tile { label: "Played"; value: panel.v ? SK.span(panel.v.played) : "–" }
            Tile { label: "Maps"; value: panel.v ? String(panel.v.mapCount) : "–"; sub: panel.v && panel.v.mapsPerHour ? panel.v.mapsPerHour.toFixed(1) + " / h" : "" }
            Tile { label: "Per map"; value: panel.v && panel.v.avgMap ? SK.clock(panel.v.avgMap) : "–"; sub: panel.v && panel.v.avgMap ? "min" : "" }
            Tile { label: "Deaths"; value: panel.v ? String(panel.v.deaths) : "–"; tint: panel.v && panel.v.deaths ? "#ff8a7a" : Theme.text() }
            Tile {
                label: panel.v && panel.v.char ? "Level · " + panel.v.char.cls : "Level"
                value: panel.v && panel.v.char ? (panel.v.char.to > panel.v.char.from ? panel.v.char.from + " → " + panel.v.char.to : String(panel.v.char.to)) : "–"
            }
            Tile {
                label: panel.v && panel.v.current ? "In map now" : "Where"
                value: panel.v && panel.v.current ? SK.span(panel.v.current.time) : panel.v && panel.v.area ? "" : "–"
                sub: panel.v && panel.v.area ? panel.v.area.name : ""
            }
        }

        // Where the time went.
        Head { text: "TIME" }
        Row {
            width: parent.width
            height: 10
            Repeater {
                model: panel.kinds
                delegate: Rectangle {
                    required property var modelData
                    readonly property real share: panel.v && panel.v.played ? (panel.v.time[modelData.k] || 0) / panel.v.played : 0
                    width: parent.width * share
                    height: 10
                    color: modelData.color
                    opacity: 0.85
                }
            }
            Rectangle { visible: !panel.v || !panel.v.played; width: parent.width; height: 10; color: Theme.trackDark }
        }
        Flow {
            width: parent.width
            spacing: 14
            Repeater {
                model: panel.kinds
                delegate: Row {
                    required property var modelData
                    readonly property real ms: panel.v ? (panel.v.time[modelData.k] || 0) : 0
                    visible: ms > 0
                    spacing: 5
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: modelData.color }
                    Small { text: modelData.name + "  " + SK.span(parent.ms); color: Theme.muted() }
                }
            }
        }

        // Loot told by hand (Client.txt names no drops; PoE 2 has no stash API).
        Item {
            width: parent.width
            height: 22
            Head { anchors.bottom: parent.bottom; text: "LOOT" }
            Line {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: !!panel.v && panel.v.worth.any
                text: !panel.v ? "" : "≈ " + panel.worthText(panel.v.worth.div)
                    + (panel.v.worthPerHour ? "  ·  " + panel.worthText(panel.v.worthPerHour) + " / h" : "")
                    + (panel.v.worth.unknown ? "  ·  " + panel.v.worth.unknown + " without price" : "")
                color: Theme.accent
                font.family: Theme.display
                font.weight: Font.Bold
                font.pixelSize: 13
            }
        }
        Grid {
            id: curGrid
            width: parent.width
            columns: width >= 460 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 3
            Repeater {
                model: panel.curRows
                delegate: Item {
                    required property var modelData
                    readonly property int count: panel.v ? (panel.v.loot.cur[modelData.id] || 0) : 0
                    readonly property var rate: panel.store && panel.store.rates ? panel.store.rates.byId[modelData.id] : null
                    width: (curGrid.width - (curGrid.columns - 1) * curGrid.columnSpacing) / curGrid.columns
                    height: 26
                    Line {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (worthNote.visible ? 160 : 100)
                        text: modelData.name
                        color: parent.count ? Theme.text() : Theme.muted()
                    }
                    Small {
                        id: worthNote
                        anchors.right: minus.left
                        anchors.rightMargin: 40
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.count > 0 && !!parent.rate && modelData.id !== "divine" && modelData.id !== "exalted"
                        text: parent.rate ? panel.worthText(parent.count * parent.rate.div) : ""
                    }
                    Text {
                        anchors.right: minus.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(parent.count)
                        color: parent.count ? Theme.text() : Theme.dim()
                        font.family: Theme.display
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Chip {
                        id: minus
                        anchors.right: plus.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.pastStart === 0
                        enabled: parent.count > 0
                        opacity: enabled ? 1 : 0.4
                        text: "−"
                        onClicked: panel.store.addCurrency(modelData.id, modelData.name, -1)
                    }
                    Chip {
                        id: plus
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.pastStart === 0
                        text: "+"
                        onClicked: panel.store.addCurrency(modelData.id, modelData.name, 1)
                    }
                }
            }
        }
        Item {
            width: parent.width
            height: 32
            z: 6
            visible: panel.pastStart === 0
            Dropdown {
                id: addCur
                visible: panel.addOptions.length > 1
                width: Math.min(parent.width, 300)
                label: "Add currency"
                options: panel.addOptions
                current: ""
                onChosen: (id) => {
                    const r = panel.store.rates.byId[id]
                    if (id) panel.store.addCurrency(id, r ? r.name : id, 1)
                }
            }
            Small {
                visible: !addCur.visible
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: !panel.store ? "" : !panel.store.ninjaOn ? "poe.ninja prices are off (Settings → Plugins → PoE 2): currency is counted without worth."
                    : panel.store.ratesAsking ? "Asking poe.ninja for prices…"
                    : panel.store.ratesError ? "poe.ninja: " + panel.store.ratesError
                    : "More currency to pick once poe.ninja's prices are in (asked when the session has loot)."
            }
        }
        Repeater {
            model: panel.v ? panel.v.loot.items.map((it, i) => ({ it: it, i: i })).reverse() : []
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                height: 26
                color: index % 2 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)
                Line {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 200
                    text: modelData.it.name || "Item"
                }
                Small {
                    x: parent.width - 186
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.clockOf(modelData.it.t)
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 34
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.worthText(modelData.it.div)
                    color: modelData.it.div == null ? Theme.dim() : Theme.text()
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                IconButton {
                    visible: panel.pastStart === 0
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    tip: "Take out"
                    width: 24
                    height: 24
                    iconSize: 11
                    onClicked: panel.store.removeItem(modelData.i)
                }
            }
        }
        Small {
            visible: !!panel.v && panel.v.loot.items.length === 0 && panel.pastStart === 0
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: "Items: copy one in the game (Ctrl+C) and press “+ Session” in the price check; its price is taken along. A copied currency stack adds its size above."
        }

        // The campaign's acts.
        Head { visible: actRow.count > 0; text: "CAMPAIGN" }
        Flow {
            width: parent.width
            spacing: 14
            visible: actRow.count > 0
            Repeater {
                id: actRow
                model: panel.v ? Object.keys(panel.v.acts).sort() : []
                delegate: Small { required property string modelData; text: modelData + "  " + SK.span(panel.v.acts[modelData]); color: Theme.purpleText }
            }
        }

        // The maps, newest first.
        Item {
            width: parent.width
            height: 22
            Head { anchors.bottom: parent.bottom; text: "MAPS" }
            Small {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: !!panel.v && panel.v.deathsAt.length > 0
                text: panel.v && panel.v.deathsAt.length ? "Last death: " + panel.clockOf(panel.v.deathsAt[panel.v.deathsAt.length - 1].t) + (panel.v.deathsAt[panel.v.deathsAt.length - 1].where ? ", " + panel.v.deathsAt[panel.v.deathsAt.length - 1].where : "") : ""
            }
        }
        Line {
            visible: !panel.v || panel.v.mapCount === 0
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Theme.muted()
            text: "No map yet. Each map you enter shows here with its area level, how long you were in it and your deaths; going back in through a portal counts as the same map."
        }
        ListView {
            id: mapList
            visible: !!panel.v && panel.v.mapCount > 0
            width: parent.width
            height: visible ? Math.max(Math.min(contentHeight, 90), Math.min(contentHeight, 260 + panel.grow)) : 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            model: panel.v ? panel.v.maps.slice().reverse() : []
            WheelScroll { flick: mapList; step: 60 }
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool live: index === 0 && !!panel.v.current && panel.v.current.start === modelData.start
                width: ListView.view.width
                height: 26
                color: live ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08) : (index % 2 ? "transparent" : Qt.rgba(1, 1, 1, 0.02))
                Line {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 220
                    text: modelData.name || SK.nameFromId(modelData.id)
                    color: parent.live ? Theme.accent : Theme.text()
                }
                Small {
                    x: parent.width - 210
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.level ? "Level " + modelData.level : ""
                }
                Small {
                    x: parent.width - 140
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.clockOf(modelData.start)
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: SK.clock(modelData.time)
                    color: Theme.text()
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.deaths > 0
                    text: "✝" + modelData.deaths
                    color: "#ff8a7a"
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }

        // Choices.
        Rectangle { width: parent.width; height: 1; color: Theme.divider }
        Flow {
            width: parent.width
            spacing: 6
            Head { height: 24; verticalAlignment: Text.AlignVCenter; text: "NEW SESSION AFTER  " }
            Chip { text: "30 min"; on: !!panel.store && panel.store.breakMs === 30 * SK.MIN; onClicked: panel.store.setPref("breakMin", 30) }
            Chip { text: "1 h"; on: !!panel.store && panel.store.breakMs === 60 * SK.MIN; onClicked: panel.store.setPref("breakMin", 60) }
            Item { width: 10; height: 24 }
            Chip { text: "Session window"; on: !!panel.store && panel.store.prefs.window !== false; onClicked: panel.store.setPref("window", !(panel.store.prefs.window !== false)) }
        }
        Small {
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: "A new day starts a new session too. Paused time (AFK, game closed) does not count."
        }
        Row {
            width: parent.width
            spacing: 8
            Small { anchors.verticalCenter: parent.verticalCenter; text: "Client.txt"; color: Theme.muted() }
            Rectangle {
                width: parent.width - 80
                height: 26
                color: "#1b1a20"
                border.color: pathInput.activeFocus ? Theme.accent : "#3a3842"
                TextInput {
                    id: pathInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text()
                    selectionColor: Theme.accent
                    font.family: Theme.body
                    font.pixelSize: 12
                    clip: true
                    maximumLength: 400
                    text: panel.store ? String(panel.store.prefs.path || "") : ""
                    onEditingFinished: if (panel.store && text !== String(panel.store.prefs.path || "")) panel.store.setPref("path", text.trim())
                    Keys.onEscapePressed: focus = false
                    Text {
                        visible: pathInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "found by itself (Steam, Lutris, Heroic)"
                        color: Theme.dim()
                        font: pathInput.font
                    }
                }
            }
        }
    }
}
