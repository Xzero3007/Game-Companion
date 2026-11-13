import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "lootkit.js" as LK

// The farm window (MN, 2026-11-13): opens by itself while you farm. In the
// open world: Kinah today toward the daily 1,000,000, the worth per hour
// (Kinah and the loot's Market worth per hour of open-world farming) and
// the gold items of today. In a dungeon: what this run brought (Kinah,
// gold items, the items' worth). Below, the keys and tickets you have.
// Nothing moves on its own: it builds again when the LOOT store changes.
Panel {
    id: win
    panelId: "farm-window"
    title: "Farm"
    tag: "AION 2"
    width: 320
    minWidth: 280
    maxWidth: 520
    pinnable: false

    property var store: null
    property var f: null
    function build() { if (store && visible) f = store.farmNow() }
    Connections { target: win.store; function onRevisionChanged() { win.build() } }
    onVisibleChanged: build()
    Component.onCompleted: build()

    readonly property bool dungeon: !!f && f.mode === "dungeon"
    readonly property real share: f && f.cap ? Math.min(1, f.kinah / f.cap) : 0
    badge: f ? (dungeon ? "RUN" : Math.floor(share * 100) + " %") : ""
    function kina(n) { return LK.C.kina(Math.round(n || 0)) }
    function shortN(n) {
        n = Math.round(n || 0)
        return n >= 1e6 ? (n % 1e6 === 0 ? n / 1e6 : (n / 1e6).toFixed(n >= 1e7 ? 1 : 2)) + "M" : n >= 1e4 ? Math.round(n / 1000) + "K" : String(n)
    }
    function clock(ms) { const d = new Date(ms); return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes() }

    component Label: Text {
        color: Theme.muted()
        font.family: Theme.display
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Value: Text {
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 20
        font.weight: Font.Bold
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Stat: Column {
        property string label
        property string value
        property color tint: Theme.text()
        spacing: 1
        Label { text: parent.label }
        Value { text: parent.value; color: parent.tint }
    }

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: !win.f ? "" : win.dungeon ? win.f.place + (win.f.run.from ? " · since " + win.clock(win.f.run.from) : "") : win.f.place
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        // The run (in a dungeon).
        Row {
            visible: win.dungeon
            width: parent.width
            spacing: 12
            Stat { width: (parent.width - 24) / 3; label: "KINAH"; value: win.f ? win.shortN(win.f.run.kinah) : "" }
            Stat { width: (parent.width - 24) / 3; label: "GOLD ITEMS"; value: win.f ? String(win.f.run.gold) : ""; tint: win.f && win.f.run.gold ? "#f2c46b" : Theme.text() }
            Stat { width: (parent.width - 24) / 3; label: "ITEM WORTH"; value: win.f ? win.shortN(win.f.run.worth) : "" }
        }

        // Kinah today toward the cap.
        Column {
            width: parent.width
            spacing: 4
            Item {
                width: parent.width
                height: big.implicitHeight
                Label { anchors.bottom: parent.bottom; anchors.bottomMargin: 3; text: "KINAH TODAY" }
                Text {
                    id: big
                    anchors.right: parent.right
                    text: win.f ? win.kina(win.f.kinah) + "  / " + win.shortN(win.f.cap) : ""
                    color: win.f && win.f.capAt ? Theme.accent : Theme.text()
                    font.family: Theme.display
                    font.pixelSize: win.dungeon ? 14 : 20
                    font.weight: Font.Bold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
            Rectangle {
                width: parent.width
                height: 6
                color: "#2a2930"
                Rectangle { width: parent.width * win.share; height: parent.height; color: Theme.accent }
            }
            Text {
                visible: !!win.f && !!win.f.capAt
                text: win.f && win.f.capAt ? "Cap reached at " + win.clock(win.f.capAt) : ""
                color: Theme.accent
                font.family: Theme.body
                font.pixelSize: 11
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }

        // Worth per hour and gold items of today (the open world).
        Row {
            visible: !win.dungeon
            width: parent.width
            spacing: 12
            Stat { width: (parent.width - 12) / 2; label: "WORTH / HOUR"; value: win.f && win.f.perHour != null ? win.shortN(win.f.perHour) : "–" }
            Stat { width: (parent.width - 12) / 2; label: "GOLD ITEMS TODAY"; value: win.f ? String(win.f.gold) : ""; tint: win.f && win.f.gold ? "#f2c46b" : Theme.text() }
        }

        // Keys and tickets you have.
        Flow {
            visible: !!win.f && win.f.keys.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: win.f ? win.f.keys : []
                delegate: Rectangle {
                    required property var modelData
                    width: keyText.implicitWidth + 14
                    height: 22
                    color: "#1b1a20"
                    border.color: "#2f2d36"
                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: modelData.name + "  " + modelData.left + (modelData.max ? " / " + modelData.max : "")
                        color: Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 11
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: win.dungeon ? "Worth: the Market's prices less its fee. Kinah today counts the open world's Kinah." : "Worth per hour: Kinah and the loot's Market worth, per hour of farming in the open world today."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 10
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
}
