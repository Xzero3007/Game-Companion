import QtQuick
import "theme.js" as Theme

// A small tag in capitals (CURRENT, RECOMMENDED, APPLIED, STEAM DEFAULT):
// outlined, or filled when `filled`.
Rectangle {
    id: tag
    property string text
    property color tint: Theme.accent
    property bool filled: false
    property real size: 10
    width: label.implicitWidth + 12
    height: label.implicitHeight + 2
    color: filled ? tint : "transparent"
    border.width: filled ? 0 : 1
    border.color: tint
    Text {
        id: label
        anchors.centerIn: parent
        text: tag.text
        color: tag.filled ? "#121116" : tag.tint
        style: tag.filled ? Text.Normal : Theme.textStyle()
        styleColor: Theme.shadow
        font.family: Theme.display
        font.pixelSize: tag.size
        font.weight: Font.Bold
        font.letterSpacing: 1.5
    }
}
