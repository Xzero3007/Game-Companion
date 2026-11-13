import QtQuick
import "theme.js" as Theme

// A small choice in a row of them (a Trending part, a group, a filter): the
// chosen one in the accent.
Item {
    id: chip
    property string text
    property bool on: false
    /// A small mark before the text (the game's purple, a live count).
    property color dot: "transparent"
    signal clicked
    implicitWidth: row.implicitWidth + 18
    implicitHeight: 24
    Rectangle {
        anchors.fill: parent
        color: chip.on ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.14) : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        border.color: chip.on ? Theme.accent : "#3a3842"
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle { visible: chip.dot.a > 0; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: chip.dot }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: chip.text.toUpperCase()
            color: chip.on ? Theme.accent : (mouse.containsMouse ? Theme.text() : Theme.muted())
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.2
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
    Accessible.role: Accessible.RadioButton
    Accessible.name: chip.text
    Accessible.checked: chip.on
}
