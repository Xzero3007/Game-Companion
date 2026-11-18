import QtQuick
import GameCompanion
import "theme.js" as Theme

// HDR test (MN, 2026-11-18, "Weg C" step 1): grey patches of known
// brightness on a Wayland subsurface of our own, described to KWin as HDR
// (PQ, BT.2020), under this window, which stays see-through over them and
// labels them. With HDR on in KDE, the bright patches glow
// brighter than this window's white text. Opened from Settings → Streams
// → Videos; nothing runs while it is closed.
Item {
    id: test
    property bool shown: false
    signal closeClicked
    width: 680
    height: head.height + area.height + foot.height
    property string report: ""
    readonly property var nits: nativeWindow.hdrNits()

    function start() {
        const w = test.Window.window
        if (!w || !shown) return
        const r = area.mapToItem(w.contentItem, 0, 0, area.width, area.height)
        report = nativeWindow.hdrTest(w, r)
        Companion.log("hdr", "test: " + report.trim().split("\n").join("; "))
    }
    onShownChanged: if (shown) startLater.restart(); else { startLater.stop(); nativeWindow.hdrTestOff() }
    // The window must be on screen (its surface made) first.
    Timer { id: startLater; interval: 400; onTriggered: test.start() }
    Component.onDestruction: nativeWindow.hdrTestOff()

    Rectangle {
        id: head
        width: parent.width
        height: 40
        color: Theme.panel(0.95)
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "HDR TEST"
            color: Theme.text()
            font.family: Theme.display
            font.pixelSize: 15
            font.weight: Font.Bold
            font.letterSpacing: 2
        }
        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            tip: "Close"
            onClicked: test.closeClicked()
        }
    }
    // See-through: the subsurface with the patches lies right under this.
    Item {
        id: area
        anchors.top: head.bottom
        width: parent.width
        height: 300
        Row {
            x: 8
            y: 30
            spacing: 8
            Repeater {
                model: test.nits
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    required property int modelData
                    width: (area.width - 8 * (test.nits.length + 1)) / test.nits.length
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData + " NITS"
                    color: Theme.text()
                    font.family: Theme.display
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 8
            y: area.height * 0.78 - 20
            text: "0 → 2000 NITS"
            color: Theme.textSoft()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
    }
    Rectangle {
        id: foot
        anchors.top: area.bottom
        width: parent.width
        height: footCol.implicitHeight + 24
        color: Theme.panel(0.95)
        Column {
            id: footCol
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 8
            Row {
                spacing: 10
                // This window's own white: plain SDR, for comparison.
                Rectangle { width: 46; height: 22; color: "#ffffff" }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: "This window's white (SDR). With HDR working, the 1200 and 1900 nit patches are clearly brighter, and each one at least as bright as the last."
                    width: footCol.width - 56
                    wrapMode: Text.WordWrap
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width
                wrapMode: Text.WordWrap
                text: test.report.length > 0 ? test.report.trim() : "Starting…"
                color: Theme.dim()
                font.family: "monospace"
                font.pixelSize: 11
            }
        }
    }
}
