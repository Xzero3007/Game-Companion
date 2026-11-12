import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme

// The bar docked at the top centre of the screen, with slanted ends and a
// thin gold line under it: the name, the game module (none yet), the
// modules' buttons (none yet), then lock, settings and hide.
Item {
    id: bar
    property bool settingsOpen: false
    property bool radioOpen: false
    signal radioClicked
    property bool streamsOpen: false
    signal streamsClicked
    property string gameName: ""
    signal settingsClicked
    signal hideClicked
    signal updateClicked

    // Where the lock button is, for the input region while locked.
    readonly property Item lockButton: lockButton

    implicitWidth: row.implicitWidth + 44
    implicitHeight: 52

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: Theme.panel(Companion.alpha)
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: bar.width; y: 0 }
            PathLine { x: bar.width - 18; y: bar.height }
            PathLine { x: 18; y: bar.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Rectangle {
        x: 18
        width: bar.width - 36
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.accent
    }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height

        Item {
            width: title.implicitWidth + 22
            height: parent.height
            Column {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                x: 6
                Text {
                    text: "GAME COMPANION"
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }
                Text {
                    text: bar.gameName.length > 0 ? "MODULE · " + bar.gameName.toUpperCase() : "NO GAME RUNNING"
                    color: bar.gameName.length > 0 ? Theme.purpleText : Theme.dim
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height
                color: Theme.divider
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                // The version, as a tooltip would show it.
                ToolTipText { visible: parent.containsMouse; text: "Game Companion " + Companion.version() }
            }
        }

        Item { width: 6; height: 1 }

        HudButton {
            icon: "radio"
            label: "Radio"
            active: bar.radioOpen
            tip: "Radio"
            onClicked: bar.radioClicked()
        }
        HudButton {
            icon: "tv"
            label: "TV"
            active: bar.streamsOpen
            tip: "Streams: Twitch and YouTube"
            onClicked: bar.streamsClicked()
        }

        Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
        Item { width: 6; height: 1 }

        HudButton {
            visible: Updates.state === "available" || Updates.state === "downloading" || Updates.state === "installing"
            icon: "update"
            label: Updates.state === "available" ? "Update" : "Wait"
            active: true
            tip: "Install update " + Updates.latest
            onClicked: bar.updateClicked()
        }
        HudButton {
            id: lockButton
            icon: Companion.locked ? "lock" : "unlock"
            active: !Companion.locked
            tip: Companion.locked ? "Unlock the overlay" : "Lock the overlay: clicks go through to the game"
            onClicked: Companion.toggleLocked()
        }
        HudButton {
            icon: "settings"
            active: bar.settingsOpen
            tip: "Settings"
            onClicked: bar.settingsClicked()
        }
        HudButton {
            icon: "hide"
            tip: "Hide the hub (pinned things stay)"
            onClicked: bar.hideClicked()
        }
    }

    component ToolTipText: Rectangle {
        property alias text: label.text
        x: 0
        y: bar.height + 6
        width: label.implicitWidth + 16
        height: label.implicitHeight + 10
        color: Theme.panel(0.95)
        border.color: Theme.divider
        Text {
            id: label
            anchors.centerIn: parent
            color: Theme.textSoft
            font.family: Theme.body
            font.pixelSize: 12
        }
    }
}
