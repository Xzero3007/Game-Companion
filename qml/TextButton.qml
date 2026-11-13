import QtQuick
import GameCompanion
import "theme.js" as Theme

// A flat button with a capitals label: gold outline and text; red for
// something that ends things.
Item {
    id: button
    property string text
    property bool danger: false
    /// Smaller for a slim header (the DPS meter's RESET).
    property real pixelSize: 13
    property int pad: 14
    signal clicked
    readonly property color tint: danger ? Theme.red : Theme.accent

    implicitWidth: label.implicitWidth + 2 * pad
    implicitHeight: 34

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse ? Qt.rgba(button.tint.r, button.tint.g, button.tint.b, 0.12) : "transparent"
        border.color: button.tint
        border.width: 1
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        id: label
        anchors.centerIn: parent
        text: button.text.toUpperCase()
        color: button.tint
        font.family: Theme.display
        font.pixelSize: button.pixelSize
        font.weight: Font.Bold
        font.letterSpacing: 1.5
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    Accessible.role: Accessible.Button
    Accessible.name: button.text
}
