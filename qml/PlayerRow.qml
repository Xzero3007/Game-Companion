import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme

// The strip under the bar while something plays: one part per player
// (the radio now; videos later), each with its state, pause, volume and
// stop. It can be pinned, so it stays while the hub is hidden.
Item {
    id: strip
    readonly property bool active: Radio.status !== "idle"
    readonly property bool pinned: Companion.pins.indexOf('"player-row"') >= 0

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 36

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: Theme.panel(Companion.alpha)
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: strip.width; y: 0 }
            PathLine { x: strip.width - 12; y: strip.height }
            PathLine { x: 12; y: strip.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height

        // The radio
        Row {
            height: parent.height
            spacing: 8
            leftPadding: 10
            rightPadding: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                color: Radio.status === "playing" ? Theme.accent : Radio.status === "failed" ? Theme.red : Theme.dim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "RADIO"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 180)
                elide: Text.ElideRight
                text: Radio.status === "failed" ? Radio.why : Radio.name
                color: Radio.status === "failed" ? Theme.red : Theme.textSoft
                font.family: Theme.body
                font.pixelSize: 12
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool on: ["connecting", "playing", "buffering"].indexOf(Radio.status) >= 0
                icon: on ? "pause" : "play"
                filled: !on
                tip: on ? "Pause the radio" : "Play the radio"
                onClicked: Radio.togglePause()
            }
            VolumeBar {
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                value: Radio.volume
                onStepped: (d) => Radio.stepVolume(d)
                onPicked: (v) => Radio.setVolumeTo(v)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                iconSize: 12
                color: Theme.dim
                tip: "Stop the radio"
                onClicked: Radio.stop()
            }
        }

        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Theme.divider }

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            icon: "pin"
            iconSize: 14
            filled: strip.pinned
            color: strip.pinned ? Theme.accent : Theme.dim
            tip: strip.pinned ? "Unpin: hide with the hub" : "Pin: stay when the hub is hidden"
            onClicked: Companion.togglePin("player-row")
        }
    }
}
