import QtQuick
import GameCompanion
import "theme.js" as Theme

// A window of the overlay: square corners, a 2 px gold line on top, a
// header in capitals. Unlocked, it moves by its header and remembers where
// it was left; locked, clicks go through it to the game.
Item {
    id: panel
    /// Remembered under this id.
    property string panelId
    property string title
    /// Text right of the title, in gold (a count, a state).
    property string badge: ""
    property real defaultX: 24
    property real defaultY: 120
    default property alias content: body.data
    signal closeClicked
    /// Emitted when it moves, resizes, shows or hides: the input region changes.
    signal areaChanged

    width: 400
    height: 2 + header.height + 12 + body.height + 14

    // Placed once the screen's size is known: where it was left, else at
    // its default place, always on the screen.
    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0) return
        const saved = panelId.length > 0 ? Companion.placeOf(panelId) : ""
        if (saved.length > 0) {
            const p = JSON.parse(saved)
            x = p.x
            y = p.y
        } else {
            x = defaultX
            y = defaultY
        }
        keepOnScreen()
        placed = true
    }
    Component.onCompleted: place()
    Connections {
        target: panel.parent
        function onWidthChanged() { panel.place() }
    }
    onXChanged: areaChanged()
    onYChanged: areaChanged()
    onWidthChanged: areaChanged()
    onHeightChanged: areaChanged()
    onVisibleChanged: areaChanged()

    function keepOnScreen() {
        if (!parent) return
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - 40))
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel(Companion.alpha)
    }
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 2
        color: Theme.accent
    }

    Rectangle {
        id: header
        y: 2
        width: parent.width
        height: 40
        color: Theme.headerTint

        MouseArea {
            anchors.fill: parent
            enabled: !Companion.locked
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: panel
            drag.minimumX: 0
            drag.minimumY: 0
            drag.maximumX: panel.parent ? panel.parent.width - panel.width : 0
            drag.maximumY: panel.parent ? panel.parent.height - 40 : 0
            onReleased: Companion.savePlace(panel.panelId, panel.x, panel.y)
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: panel.title.toUpperCase()
            color: Theme.text
            font.family: Theme.display
            font.pixelSize: 15
            font.weight: Font.Bold
            font.letterSpacing: 2
        }
        Text {
            anchors.right: closeButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.badge.length > 0
            text: panel.badge
            color: Theme.accent
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        Item {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            HudIcon {
                anchors.centerIn: parent
                name: "close"
                size: 14
                lineWidth: 2
                color: closeMouse.containsMouse ? Theme.text : Theme.dim
            }
            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !Companion.locked
                onClicked: panel.closeClicked()
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Close " + panel.title
        }
    }

    Item {
        id: body
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        anchors.topMargin: 12
        height: childrenRect.height
    }
}
