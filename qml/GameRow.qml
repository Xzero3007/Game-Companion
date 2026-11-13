import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme

// The running game's row under the bar (canvas page "Leiste geteilt und
// Overlay-Map", MN 2026-11-13): smaller than the bar, with the game's purple
// tag and its module's buttons (what Settings → Plugins puts in the bar).
// Only there while one of them is; it can be pinned, so it stays while the
// hub is hidden.
Item {
    id: strip
    property string gameName: ""
    property bool dpsShown: false
    property bool dpsOpen: false
    signal dpsClicked
    property bool mapShown: false
    property bool mapOpen: false
    signal mapClicked
    /// A right-click on MAP: the overlay map on or off.
    property bool overlayOn: false
    signal mapOverlayClicked
    property bool marketShown: false
    property bool marketOpen: false
    signal marketClicked
    property bool charactersShown: false
    property bool charactersOpen: false
    signal charactersClicked

    readonly property bool active: dpsShown || mapShown || marketShown || charactersShown
    readonly property bool pinned: Companion.pins.indexOf('"game-row"') >= 0

    implicitWidth: row.implicitWidth + 36
    implicitHeight: 34

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: Theme.panel(Companion.alpha * 0.96)
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: strip.width; y: 0 }
            PathLine { x: strip.width - 12; y: strip.height }
            PathLine { x: 12; y: strip.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Rectangle {
        x: 12
        width: strip.width - 24
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(0.608, 0.42, 0.91, 0.7)
    }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height
        spacing: 2

        Item {
            width: tagBox.width + 8
            height: parent.height
            Rectangle {
                id: tagBox
                anchors.verticalCenter: parent.verticalCenter
                width: tagText.implicitWidth + 12
                height: tagText.implicitHeight + 2
                color: Qt.rgba(0.608, 0.42, 0.91, 0.4)
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: tagText
                    anchors.centerIn: parent
                    text: strip.gameName.toUpperCase()
                    color: Theme.purpleText
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
            }
        }

        GameButton {
            visible: strip.dpsShown
            icon: "dps"
            label: "DPS"
            active: strip.dpsOpen
            tip: strip.gameName + ": DPS meter (listens only)"
            onClicked: strip.dpsClicked()
        }
        GameButton {
            visible: strip.mapShown
            icon: "map"
            label: "Map"
            active: strip.mapOpen
            marked: strip.overlayOn
            tip: strip.gameName + ": map with your position (right-click: the overlay map)"
            onClicked: strip.mapClicked()
            onRightClicked: strip.mapOverlayClicked()
        }
        GameButton {
            visible: strip.marketShown
            icon: "market"
            label: "Market"
            active: strip.marketOpen
            tip: strip.gameName + ": your server's market prices"
            onClicked: strip.marketClicked()
        }
        GameButton {
            visible: strip.charactersShown
            icon: "characters"
            label: "Chars"
            active: strip.charactersOpen
            tip: strip.gameName + ": your characters, their content and limits (listens only)"
            onClicked: strip.charactersClicked()
        }

        Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }

        IconButton {
            hud: true
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            icon: "pin"
            iconSize: 13
            filled: strip.pinned
            color: strip.pinned ? Theme.accentFor(true) : Theme.dim(true)
            tip: strip.pinned ? "Unpin: hide with the hub" : "Pin: stay when the hub is hidden"
            onClicked: Companion.togglePin("game-row")
        }
    }

    // A game's button: a small icon and its name beside it; active, gold
    // with a gold line under it. `marked`: a small gold dot (the overlay map
    // is on).
    component GameButton: Item {
        id: button
        property string icon
        property string label
        property bool active: false
        property bool marked: false
        property string tip
        signal clicked
        signal rightClicked
        width: visible ? content.implicitWidth + 20 : 0
        height: strip.height
        readonly property color tint: active ? Theme.accentFor(true) : (mouse.containsMouse ? Theme.text(true) : Theme.muted(true))
        Row {
            id: content
            anchors.centerIn: parent
            spacing: 6
            HudIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: button.icon
                size: 15
                color: button.tint
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: button.label.toUpperCase()
                color: button.tint
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
        Rectangle {
            visible: button.marked
            x: content.x + 12
            y: 6
            width: 5
            height: 5
            color: Theme.accentFor(true)
        }
        Rectangle {
            visible: button.active
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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => m.button === Qt.RightButton ? button.rightClicked() : button.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: button.tip
        Accessible.onPressAction: button.clicked()
    }
}
