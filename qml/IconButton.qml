import QtQuick
import "theme.js" as Theme

// A small square button with one icon.
Item {
    id: b
    /// In the bar or the player row: darkened as the user set it.
    property bool hud: false
    property string icon
    property string tip
    property bool filled: false
    property color color: Theme.text(b.hud)
    property color hoverColor: Theme.accentFor(b.hud)
    property real iconSize: 13
    property bool framed: false
    signal clicked
    width: 28
    height: 28
    Rectangle {
        anchors.fill: parent
        visible: b.framed
        color: "transparent"
        border.color: b.color
    }
    HudIcon {
        anchors.centerIn: parent
        name: b.icon
        size: b.iconSize
        lineWidth: 2.4
        filled: b.filled
        color: m.containsMouse ? b.hoverColor : b.color
    }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
    Accessible.role: Accessible.Button
    Accessible.name: b.tip
}
