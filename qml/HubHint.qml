import QtQuick
import "theme.js" as Theme

// A short note at the top centre when the hub hides: how to bring it back.
// Fades after two seconds; never takes clicks.
Rectangle {
    id: hint
    property string key: ""
    width: label.implicitWidth + 28
    height: 28
    color: Theme.panel(0.9)
    opacity: 0
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.accent }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        id: label
        anchors.centerIn: parent
        text: "HUB HIDDEN" + (hint.key.length > 0 ? " · " + hint.key.toUpperCase() + " BRINGS IT BACK" : "")
        color: Theme.accent
        font.family: Theme.display
        font.pixelSize: 12
        font.weight: Font.Bold
        font.letterSpacing: 1.5
    }
    function flash() { fade.restart() }
    SequentialAnimation {
        id: fade
        PropertyAction { target: hint; property: "opacity"; value: 1 }
        PauseAnimation { duration: 2000 }
        NumberAnimation { target: hint; property: "opacity"; to: 0; duration: 400 }
    }
}
