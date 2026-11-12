import QtQuick
import GameCompanion
import "theme.js" as Theme

// Shows that the overlay is unlocked: a note at the bottom of the screen
// with the key that locks it again (Main draws the gold frame around the
// screen). Never takes clicks.
Item {
    id: frame
    property string lockKey: ""
    width: note.implicitWidth + 28
    height: 26

    Rectangle {
        anchors.fill: parent
        color: Theme.panel(0.92)
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.accent }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: note
            anchors.centerIn: parent
            text: "UNLOCKED · " + (frame.lockKey.length > 0 ? frame.lockKey.toUpperCase() + " LOCKS AGAIN" : "THE LOCK IN THE BAR LOCKS AGAIN")
            color: Theme.accent
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
    }
}
