import QtQuick
import "theme.js" as Theme

// A bar button: an icon, and its name in capitals under it. Active, it is
// gold with a gold line under it.
Item {
    id: button
    property string icon
    property string label
    property bool active: false
    property string tip
    signal clicked

    implicitWidth: label.length > 0 ? 56 : 48
    implicitHeight: 52

    readonly property color tint: active ? Theme.accent : (mouse.containsMouse ? Theme.text : Theme.muted)

    Column {
        anchors.centerIn: parent
        spacing: 3
        HudIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: button.icon
            color: button.tint
        }
        Text {
            visible: button.label.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: button.label.toUpperCase()
            color: button.tint
            font.family: Theme.display
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
    }

    Rectangle {
        visible: button.active && button.label.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        color: Theme.accent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    Accessible.role: Accessible.Button
    Accessible.name: button.tip.length > 0 ? button.tip : button.label
}
