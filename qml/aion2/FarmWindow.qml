import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "lootkit.js" as LK

// The farm window (MN, 2026-11-13/14): always while AION 2 runs, or only
// while you farm (LOOT → DROPS → Farm window). Kinah today toward the daily
// 1,000,000, the worth per hour (Kinah and the loot's Market worth per hour
// of open-world farming), the gold items of today, in a dungeon what this
// run brought, the keys and tickets you have, Odyle energy and the ping;
// each row can be switched off. Nothing moves on its own: it builds again
// when the LOOT store or the fight (ping, Odyle) changes.
// Compact (MN, 0.8.16, design E5a): no header; the Kinah bar with Kinah and
// worth per hour in it, and one line of values and the keys you chose
// (the game's icon, three letters, the count).
Panel {
    id: win
    panelId: "farm-window"
    title: "Farm"
    bare: true
    width: 400
    minWidth: 240
    maxWidth: 700
    ground: Companion.alpha * (store ? store.farmOpacity() : 100) / 100
    // Its height follows its rows; dragging the corner down makes all of it
    // bigger (MN, 0.8.19: "wieso kann ich die höhe nicht verstellen?"),
    // double-click the corner for its own size.
    stretchy: true
    maxGrow: 120
    readonly property real fs: (store ? store.farmText() : 1) * (1 + grow / 60)
    pinnable: false

    property var store: null
    property var f: null
    function build() { if (store && visible) f = store.farmNow() }
    Connections { target: win.store; function onRevisionChanged() { win.build() } }
    Connections { target: Aion2; enabled: win.visible && (win.on("ping") || win.on("odyle")); function onFightChanged() { win.build() } }
    function on(k) { return !!store && store.farmRow(k) }
    onVisibleChanged: build()
    Component.onCompleted: build()
    // The game's icons come from the Market's icon store (kept on disk).
    property int iconsRevision: 0
    Connections { target: Aion2; function onIconReady(name) { win.iconsRevision++ } }
    function iconUrl(name) { iconsRevision; return name ? Aion2.icon(name) : "" }
    readonly property bool dungeon: !!f && f.mode === "dungeon"
    readonly property real share: f && f.cap ? Math.min(1, f.kinah / f.cap) : 0
    function kina(n) { return LK.C.kina(Math.round(n || 0)) }
    function shortN(n) {
        n = Math.round(n || 0)
        return n >= 1e6 ? (n % 1e6 === 0 ? n / 1e6 : (n / 1e6).toFixed(n >= 1e7 ? 1 : 2)) + "M" : n >= 1e4 ? Math.round(n / 1000) + "K" : String(n)
    }
    function grouped(n) { return Number(n || 0).toLocaleString(Qt.locale("en_US"), "f", 0) }
    function clock(ms) { const d = new Date(ms); return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes() }
    readonly property int px: Math.round(11 * fs)

    // A number in Rajdhani with a dim word after it ("2.76M" "/h").
    component Pair: Row {
        property string label
        property string value
        property string unit
        property color tint: Theme.text()
        property color unitTint: Theme.muted()
        property bool unitBold: false
        spacing: 3
        Text {
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label; color: Theme.muted()
            font.family: Theme.display; font.pixelSize: Math.round(10 * win.fs); font.weight: Font.Bold
            font.letterSpacing: 0.6
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            text: parent.value; color: parent.tint
            font.family: Theme.display; font.pixelSize: Math.round(12 * win.fs); font.weight: Font.Bold
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            visible: text.length > 0
            anchors.baseline: parent.children[1].baseline
            text: parent.unit; color: parent.unitTint
            font.family: parent.unitBold ? Theme.display : Theme.body
            font.pixelSize: parent.unitBold ? Math.round(12 * win.fs) : win.px
            font.weight: parent.unitBold ? Font.Bold : Font.Normal
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }

    // Moves the window while unlocked (it has no header).
    // Sized by the content, never by the window (that made a loop that
    // kept an old, taller height: MN, 0.8.19).
    MoveArea {
        width: win.width
        height: content.height
        enabled: !Companion.locked
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        target: win
        onReleased: win.remember()
    }

    Column {
        id: content
        width: parent.width
        spacing: 0

        // Kinah today toward the cap, the number written in the bar.
        Item {
            visible: win.on("kinah")
            width: parent.width
            height: Math.round(18 * win.fs)
            Rectangle { anchors.fill: parent; color: "#2a2930"; opacity: 0.9 }
            Rectangle { width: parent.width * win.share; height: parent.height; color: Qt.rgba(0.878, 0.647, 0.149, 0.6) }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                text: !win.f ? "" : win.kina(win.f.kinah) + " / " + win.shortN(win.f.cap) + " · " + (win.f.capAt ? "cap " + win.clock(win.f.capAt) : Math.floor(win.share * 100) + " %")
                color: "#ffffff"
                font.family: Theme.display; font.pixelSize: Math.round(12 * win.fs); font.weight: Font.Bold
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: closeBox.visible ? closeBox.width + 2 : 7
                anchors.verticalCenter: parent.verticalCenter
                // Worth per hour (the open world) or this run's Kinah (a dungeon).
                text: !win.f ? "" : win.dungeon ? (win.on("run") ? "RUN " + win.shortN(win.f.run.kinah) : "") : win.on("perHour") ? (win.f.perHour != null ? win.shortN(win.f.perHour) : "–") + "/h" : ""
                color: "#ffffff"
                font.family: Theme.display; font.pixelSize: Math.round(12 * win.fs); font.weight: Font.Bold
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }

        // One line (design E5a): gold items, valuables, Odyle energy, ping,
        // then the keys you chose (the game's icon, three letters, count);
        // it wraps when it does not fit.
        Item {
            id: values
            readonly property bool anyValue: (!win.on("kinah") && win.on("perHour")) || win.on("gold") || win.on("valuables") || win.on("odyle") || win.on("ping") || (win.dungeon && win.on("run"))
            readonly property bool anyKey: win.on("keys") && !!win.f && win.f.keys.length > 0
            visible: anyValue || anyKey
            width: parent.width
            height: line.implicitHeight + 7
            Flow {
                id: line
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.right: parent.right; anchors.rightMargin: 6
                y: 3
                spacing: 7
                Pair { visible: win.dungeon && win.on("run"); label: "WTH"; value: win.f ? win.shortN(win.f.run.worth) : "" }
                Pair { visible: !win.on("kinah") && !win.dungeon && win.on("perHour"); label: "K/H"; value: win.f && win.f.perHour != null ? win.shortN(win.f.perHour) : "–" }
                Pair {
                    visible: win.on("gold") || (win.dungeon && win.on("run"))
                    value: win.f ? String(win.dungeon ? win.f.run.gold : win.f.gold) : ""
                    label: "GOLD"
                    tint: win.f && (win.dungeon ? win.f.run.gold : win.f.gold) ? "#f2c46b" : Theme.text()
                }
                Pair {
                    // Its own switch (MN, 0.8.24: "valuables nicht brauche").
                    visible: win.on("valuables") && !!win.f && (win.dungeon ? win.f.run.valuables : win.f.valuables) > 0
                    value: win.f ? String(win.dungeon ? win.f.run.valuables : win.f.valuables) : ""
                    label: "VAL"
                    tint: "#f2c46b"
                }
                Row {
                    visible: win.on("odyle")
                    spacing: 3
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(17 * win.fs); height: width
                        sourceSize: Qt.size(26, 26)
                        source: "qrc:/qt/qml/GameCompanion/assets/aion2/odyle.png"
                        Accessible.ignored: true
                    }
                    Pair {
                        // Easier to read (MN, 0.8.24): a word before it and
                        // the charged part as bright as the energy itself.
                        label: "ODYLE"
                        value: win.f && win.f.extras.odyle ? win.grouped(win.f.extras.odyle[0]) : "–"
                        unit: win.f && win.f.extras.odyle ? "+" + win.grouped(win.f.extras.odyle[1]) : ""
                        tint: Theme.purpleText
                        unitTint: Theme.purpleText
                        unitBold: true
                    }
                }
                Pair {
                    visible: win.on("ping")
                    value: win.f && win.f.extras.ping != null ? String(win.f.extras.ping) : "–"
                    label: "PING"
                    // Green up to 100 ms, red above (MN, 0.8.24).
                    tint: !win.f || win.f.extras.ping == null ? Theme.text() : win.f.extras.ping > 100 ? Theme.red : "#7fdc9a"
                }
                Rectangle {
                    visible: values.anyValue && values.anyKey
                    width: 1
                    height: Math.round(13 * win.fs)
                    color: "#3a3842"
                }
                Repeater {
                    model: values.anyKey ? win.f.keys : []
                    delegate: Row {
                        id: keyItem
                        required property var modelData
                        // Icons are kept as "Icon_<name>" (as the Market's).
                        readonly property string pic: win.iconUrl(modelData.icon ? "Icon_" + modelData.icon : "")
                        spacing: 3
                        // The game's icon; nothing until it is kept (MN: no empty boxes).
                        Item {
                            visible: keyPic.status === Image.Ready
                            anchors.verticalCenter: parent.verticalCenter
                            width: visible ? Math.round(14 * win.fs) : 0; height: Math.round(14 * win.fs)
                            Image {
                                id: keyPic
                                anchors.fill: parent
                                visible: status === Image.Ready
                                source: keyItem.pic
                                sourceSize: Qt.size(32, 32)
                                asynchronous: true
                                Accessible.ignored: true
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: keyItem.modelData.abbr
                            color: Theme.muted()
                            font.family: Theme.display; font.pixelSize: Math.round(10 * win.fs); font.weight: Font.Bold
                            font.letterSpacing: 0.6
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(keyItem.modelData.left)
                            color: Theme.text()
                            font.family: Theme.display; font.pixelSize: Math.round(12 * win.fs); font.weight: Font.Bold
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Accessible.name: keyItem.modelData.name + " " + keyItem.modelData.left
                    }
                }
            }
        }

        Text {
            visible: !win.f || (!win.on("kinah") && !values.visible)
            leftPadding: 7; topPadding: 3; bottomPadding: 3
            text: "Farm: nothing switched on (LOOT → DROPS → Farm window)"
            color: Theme.muted()
            font.family: Theme.body; font.pixelSize: win.px
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }

    // × while unlocked only (locked, the window lets clicks through).
    Item {
        id: closeBox
        visible: !Companion.locked
        anchors.right: parent.right
        width: Math.round(18 * win.fs)
        height: Math.round(18 * win.fs)
        HudIcon {
            anchors.centerIn: parent
            name: "close"
            size: Math.round(10 * win.fs)
            lineWidth: 2
            color: closeMouse.containsMouse ? Theme.text() : "#ffffff"
        }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.closeClicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Close the farm window"
    }
}
