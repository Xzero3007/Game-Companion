import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "sessionkit.js" as SK

// The session window over the game (like the AION 2 farm window): one
// line with the session's play time, the map you are in and how long,
// maps and maps per hour, deaths. Builds again on each event of the log
// and once a minute while it shows and PoE 2 runs; nothing else moves.
Panel {
    id: win
    panelId: "poe2-session-window"
    title: "Session"
    bare: true
    pinnable: false
    width: 420
    minWidth: 260
    maxWidth: 800

    property var store: null
    property real now: Date.now()
    Timer { interval: 60000; repeat: true; running: win.visible && !!win.store && win.store.on; onTriggered: { win.now = Date.now(); win.store.freshen() } }
    onVisibleChanged: { now = Date.now(); if (visible && store) store.freshen() }
    Connections { target: win.store; function onUpdated() { win.now = Date.now() } }
    readonly property var v: store ? (store.revision, store.viewOf(store.session, now)) : null

    component Pair: Row {
        property string value
        property string unit
        property color tint: Theme.text()
        spacing: 3
        Text {
            text: parent.value; color: parent.tint
            font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            visible: text.length > 0
            anchors.baseline: parent.children[0].baseline
            text: parent.unit; color: Theme.muted()
            font.family: Theme.body; font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }

    MoveArea {
        width: win.width
        height: line.height
        enabled: !Companion.locked
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        target: win
        onReleased: win.remember()
    }

    Item {
        id: line
        width: parent.width
        height: 26
        Rectangle { width: 3; height: parent.height; color: Theme.purple }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Pair { value: win.v ? SK.span(win.v.played) : "–"; unit: win.v && win.v.idle ? "paused" : ""; tint: win.v && win.v.idle ? Theme.dim() : Theme.text() }
            Pair {
                visible: !!win.v && !!win.v.current
                value: win.v && win.v.current ? SK.span(win.v.current.time) : ""
                unit: win.v && win.v.current ? (win.v.current.name || "map") : ""
                tint: Theme.accent
            }
            Pair { value: win.v ? String(win.v.mapCount) : "0"; unit: win.v && win.v.mapsPerHour ? "maps · " + win.v.mapsPerHour.toFixed(1) + "/h" : "maps" }
            Pair { visible: !!win.v && win.v.deaths > 0; value: win.v ? "✝" + win.v.deaths : ""; tint: "#ff8a7a" }
            Pair {
                visible: !!win.v && win.v.worth.any && win.v.worth.div > 0
                value: win.v ? "≈" + (win.v.worth.div < 10 ? win.v.worth.div.toFixed(2) : win.v.worth.div.toFixed(1)) : ""
                unit: "div"
                tint: Theme.accent
            }
            Pair {
                visible: !!win.v && !!win.v.char && win.v.char.to > win.v.char.from
                value: win.v && win.v.char ? "+" + (win.v.char.to - win.v.char.from) : ""
                unit: "level"
            }
        }
    }
}
