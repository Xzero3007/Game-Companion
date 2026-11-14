import QtQuick
import "theme.js" as Theme

// A bar button: an icon, and its name in capitals under it. Active, it is
// gold with a gold line under it. `dot`: a small square at the top right
// ("run": grey, the program runs; "on": gold, shown over the game).
Item {
    id: button
    property string icon
    property string label
    property bool active: false
    property string tip
    property string dot: ""
    signal clicked
    signal rightClicked

    implicitWidth: label.length > 0 ? 56 : 48
    implicitHeight: 52

    readonly property color tint: active ? Theme.accentFor(true) : (mouse.containsMouse ? Theme.text(true) : Theme.muted(true))

    Column {
        anchors.centerIn: parent
        spacing: 3
        HudIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: button.icon
            color: button.tint
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
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
        visible: button.dot.length > 0
        x: parent.width - 18
        y: 8
        width: 5
        height: 5
        color: button.dot === "on" ? Theme.accentFor(true) : Theme.dim(true)
    }

    Rectangle {
        visible: button.active && button.label.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        color: Theme.accentFor(true)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => m.button === Qt.RightButton ? button.rightClicked() : button.clicked()
    }

    Accessible.role: Accessible.Button
    Accessible.name: button.tip.length > 0 ? button.tip : button.label
}
