import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "timekit.js" as TK

// The AION 2 module's Schedule (the Event Timers plugin, reworked; design
// boards T1 and T2): the field bosses with when they come back, as the game
// told it when you opened a map (and Aion 2 Timers' feed, when switched
// on), and the fixed events and resets in your server's time. A bell on a
// row sets an alert (TimerStore). Only reads.
Panel {
    id: panel
    panelId: "schedule"
    title: "Schedule"
    tag: width < 460 ? "" : "AION 2"
    width: 560
    minWidth: 420
    maxWidth: 1000
    stretchy: true
    minGrow: -160

    /// The Schedule's store (Main.qml's TimerStore).
    property var store
    /// "Show on map": a boss's world-map id and name.
    signal showOnMap(string id, string name)

    property var view: ({ tab: "bosses", alertsOnly: false })
    function setView(k, v) {
        const p = Object.assign({}, view)
        p[k] = v
        view = p
        viewTimer.restart()
    }
    Timer { id: viewTimer; interval: 400; onTriggered: Aion2.keepStore("schedule-view", JSON.stringify(panel.view)) }
    Component.onCompleted: {
        try { view = Object.assign({}, view, JSON.parse(Aion2.loadStore("schedule-view") || "{}")) } catch (e) { }
        if (nativeWindow.demo.split(",").indexOf("events") >= 0) view = Object.assign({}, view, { tab: "events" })
    }

    // The time the rows are for: again on every change of the store, and
    // every 30 seconds while shown (no timer while closed).
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: panel.visible; onTriggered: panel.now = Date.now() }
    onVisibleChanged: { now = Date.now(); if (store) store.panelShown = visible }
    Connections { target: panel.store; function onRevisionChanged() { panel.now = Date.now() } }

    readonly property var bossRows: {
        if (!store) return []
        store.revision
        const rows = store.bossRows(now)
        const on = store.prefs.on
        return rows.filter((r) => !view.alertsOnly || on[r.id])
    }
    readonly property var eventRows: {
        if (!store) return []
        store.revision; store.prefs
        const on = store.prefs.on
        return store.eventRows(now).filter((r) => !view.alertsOnly || on[r.id])
    }

    function stateColor(s) { return s === "up" ? "#ff8a7a" : s === "soon" ? Theme.accent : s === "upOld" || s === "due" ? "#f2c46b" : Theme.dim() }
    function whenText(r) {
        const reg = store ? store.region : 0
        if (r.state === "up") return "up since " + TK.clock(reg, r.time, now)
        if (r.state === "upOld") return "up at " + TK.clock(reg, r.seen, now) + ", maybe killed"
        if (r.state === "due") return "back since " + TK.clock(reg, r.time, now)
        if (r.state === "unknown") return "no time given"
        return "back at " + TK.clock(reg, r.time, now)
    }
    function leftText(r) {
        if (r.state === "up") return "UP " + TK.span(now - r.time)
        if (r.state === "upOld" || r.state === "due") return "UP?"
        if (r.state === "unknown") return "–"
        return TK.span(r.time - now)
    }

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
    component Figure: Text {
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 15
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    /// A source tag: GAME or A2T (Aion 2 Timers).
    component Source: Rectangle {
        property string src
        property bool guessed: false
        width: 44
        height: 16
        color: "transparent"
        border.color: src === "game" ? "#4a4852" : "#3a3842"
        Text {
            anchors.centerIn: parent
            text: parent.src === "game" ? "GAME" : parent.guessed ? "A2T?" : "A2T"
            color: parent.src === "game" ? "#c9c6d0" : Theme.dim()
            font.family: Theme.display
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
    /// The bell: an alert for this row, in the accent while on.
    component Bell: IconButton {
        property string entry
        readonly property bool on: panel.store ? !!panel.store.prefs.on[entry] : false
        width: 26
        height: 26
        icon: "bell"
        iconSize: 13
        filled: on
        color: on ? Theme.accent : Theme.dim()
        tip: on ? "Alert on: " + panel.store.prefs.lead + " min before (click: off)" : "Alert me before it starts"
        onClicked: panel.store.toggleAlert(entry)
    }

    Column {
        width: parent.width
        spacing: 8

        // Server time and the server.
        Row {
            spacing: 16
            Text {
                text: panel.store && panel.store.region
                    ? "Server time  <b>" + TK.clock(panel.store.region, panel.now) + "</b>" : "Server time: play a character once (or pick the region in Settings)"
                textFormat: Text.StyledText
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Small {
                visible: !!panel.store && panel.store.serverName().length > 0
                text: panel.store ? panel.store.serverName() + (panel.store.side ? " · " + (panel.store.side === "elyos" ? "Elyos" : "Asmodian") : "") : ""
            }
        }

        // The tabs.
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: [["bosses", "Bosses"], ["events", "Events"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.view.tab === modelData[0]
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
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.setView("tab", modelData[0]) }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Chip {
                    visible: panel.view.tab === "bosses" && !!panel.store && panel.store.prefs.a2t
                    text: panel.store && panel.store.feedBusy ? "Asking…" : "Refresh"
                    onClicked: panel.store.refreshFeed(true)
                }
                Chip { text: "Alerts only"; on: panel.view.alertsOnly; onClicked: panel.setView("alertsOnly", !panel.view.alertsOnly) }
            }
        }

        // ---------------- BOSSES ----------------
        Line {
            visible: panel.view.tab === "bosses" && panel.bossRows.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Theme.muted()
            text: panel.view.alertsOnly ? "No boss has an alert yet: switch \"Alerts only\" off and click a bell."
                : "No boss times yet. Open the map in the game (your home map or the Abyss): the game then tells when each field boss comes back."
                  + (panel.store && !panel.store.prefs.a2t ? " Aion 2 Timers can fill in the maps you haven't opened (Settings → Plugins → AION 2 → Event Timers)." : "")
        }
        ListView {
            id: bossList
            visible: panel.view.tab === "bosses" && panel.bossRows.length > 0
            width: parent.width
            height: visible ? Math.max(Math.min(contentHeight, 120), Math.min(contentHeight, 360 + panel.grow)) : 0
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            model: panel.bossRows
            WheelScroll { flick: bossList; step: 74 }
            section.property: "where"
            section.delegate: Item {
                required property string section
                width: ListView.view.width
                height: 26
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: parent.section.toUpperCase()
                    color: "#c9c6d0"
                    font.family: Theme.display
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
            delegate: Rectangle {
                required property var modelData
                readonly property var r: modelData
                width: ListView.view.width
                height: 34
                color: rowMouse.containsMouse ? "#222128" : "#1b1a20"
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 10
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: panel.stateColor(r.state) }
                    Line {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 8 - 130 - 70 - 44 - 26 - 26 - 6 * 10
                        text: r.name
                    }
                    Small { anchors.verticalCenter: parent.verticalCenter; width: 130; horizontalAlignment: Text.AlignRight; text: panel.whenText(r) }
                    Figure {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        text: panel.leftText(r)
                        color: r.state === "up" ? "#ff8a7a" : r.state === "soon" ? Theme.accent : r.state === "due" || r.state === "upOld" ? "#f2c46b" : Theme.text()
                    }
                    Source { anchors.verticalCenter: parent.verticalCenter; src: r.src; guessed: r.guessed }
                    Bell { anchors.verticalCenter: parent.verticalCenter; entry: r.id }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        icon: "place"
                        iconSize: 13
                        color: Theme.dim()
                        tip: "Show on the map"
                        onClicked: panel.showOnMap(r.id, r.name)
                    }
                }
            }
        }

        // ---------------- EVENTS ----------------
        ListView {
            id: eventList
            visible: panel.view.tab === "events"
            width: parent.width
            height: visible ? Math.max(Math.min(contentHeight, 120), Math.min(contentHeight, 360 + panel.grow)) : 0
            clip: true
            spacing: 3
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            model: panel.eventRows
            WheelScroll { flick: eventList; step: 70 }
            delegate: Rectangle {
                required property var modelData
                readonly property var r: modelData
                readonly property bool soon: !r.running && r.start - panel.now <= 15 * 60000
                width: ListView.view.width
                height: 32
                color: r.running ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : evMouse.containsMouse ? "#222128" : "#1b1a20"
                MouseArea { id: evMouse; anchors.fill: parent; hoverEnabled: true }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 10
                    Line {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 150 - 80 - 66 - 26 - 4 * 10
                        text: r.name
                    }
                    Small {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        text: r.kind === "reset" ? (r.id === "energy" ? "every 3 h" : r.id === "weekly" ? "Wednesday, 07:00 UTC" : "07:00 UTC") : r.where
                    }
                    Small {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 80
                        horizontalAlignment: Text.AlignRight
                        text: r.running ? "until " + TK.clock(panel.store.region || 0, r.end, panel.now) : TK.clock(r.kind === "reset" && !panel.store.region ? 0 : panel.store.region, r.start, panel.now)
                    }
                    Figure {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 66
                        text: r.running ? "NOW" : TK.span(r.start - panel.now)
                        color: r.running ? "#ff8a7a" : parent.parent.soon ? Theme.accent : Theme.text()
                    }
                    Bell { anchors.verticalCenter: parent.verticalCenter; entry: r.id }
                }
            }
        }

        // The sources, as text.
        Row {
            width: parent.width
            spacing: 8
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
            Small {
                width: parent.width - 14
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: panel.view.tab === "bosses"
                    ? "Times come when you open a map in the game; other maps keep their last times." + (panel.store && panel.store.prefs.a2t
                        ? " A2T: Aion 2 Timers (aion2timers.com, by HomelessGuyNABox)" + (panel.store.feed() ? ", asked " + TK.ago(panel.store.feed().at, panel.now) : "")
                          + (panel.store.feedProblem ? " — " + panel.store.feedProblem : "") + "." : "")
                    : "Fixed times from the game's own tables (A2 Tools' Event Timers, GPL-3.0), in your server's time. Nothing is fetched."
            }
        }
    }
}
