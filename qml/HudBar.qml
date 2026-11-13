import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme
import "drag.js" as Drag

// The bar docked at the top centre of the screen, with slanted ends and a
// thin gold line under it: the name, the game module (none yet), the
// modules' buttons (none yet), then lock, settings and hide.
Item {
    id: bar
    property bool settingsOpen: false
    property bool radioOpen: false
    signal radioClicked
    property bool gamesOpen: false
    signal gamesClicked
    /// The AION 2 module's DPS meter: its button while AION 2 runs.
    property bool dpsShown: false
    property bool dpsOpen: false
    signal dpsClicked
    property bool mapShown: false
    property bool mapOpen: false
    signal mapClicked
    property bool marketShown: false
    property bool marketOpen: false
    signal marketClicked
    /// The running game has a module (purple); else it just shows its name.
    property bool gameHasModule: false
    property bool streamsOpen: false
    signal streamsClicked
    property string gameName: ""
    signal settingsClicked
    signal hideClicked
    signal updateClicked

    // Where the lock button is, for the input region while locked.
    readonly property Item lockButton: lockButton

    /// While the user drags the bar sideways: how far, in screen pixels.
    property real dragShift: 0
    /// Let go after dragging: the window keeps the new place.
    signal dropped
    /// The title's tooltip shows (under the bar: its window grows for it).
    readonly property bool tipShown: titleDrag.containsMouse && !titleDrag.pressed

    implicitWidth: row.implicitWidth + 44
    implicitHeight: 52

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: Theme.panel(Companion.alpha)
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: bar.width; y: 0 }
            PathLine { x: bar.width - 18; y: bar.height }
            PathLine { x: 18; y: bar.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Rectangle {
        x: 18
        width: bar.width - 36
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.accentFor(true)
    }

    // The slanted ends move the bar (the name does too).
    DragArea { x: 0; width: 24; height: parent.height }
    DragArea { x: bar.width - 24; width: 24; height: parent.height }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height

        Item {
            width: title.implicitWidth + 22
            height: parent.height
            Column {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                x: 6
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: "GAME COMPANION"
                    color: Theme.accentFor(true)
                    font.family: Theme.display
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    text: bar.gameName.length === 0 ? "NO GAME RUNNING"
                        : (bar.gameHasModule ? "MODULE · " : "PLAYING · ") + bar.gameName.toUpperCase()
                    color: bar.gameName.length > 0 && bar.gameHasModule ? Theme.purpleText
                        : bar.gameName.length > 0 ? Theme.textSoft(true) : Theme.dim(true)
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height
                color: Theme.divider
            }
            DragArea {
                id: titleDrag
                anchors.fill: parent
                // The version, as a tooltip would show it.
                ToolTipText { visible: bar.tipShown; text: "Game Companion " + Companion.version() + " · drag to move the bar" }
            }
        }

        Item { width: 6; height: 1 }

        HudButton {
            icon: "games"
            label: "Games"
            active: bar.gamesOpen
            tip: "Games: your library and what runs"
            onClicked: bar.gamesClicked()
        }
        HudButton {
            visible: bar.dpsShown
            icon: "dps"
            label: "DPS"
            active: bar.dpsOpen
            tip: "AION 2: DPS meter (listens only)"
            onClicked: bar.dpsClicked()
        }
        HudButton {
            visible: bar.mapShown
            icon: "map"
            label: "Map"
            active: bar.mapOpen
            tip: "AION 2: map with your position (listens only)"
            onClicked: bar.mapClicked()
        }
        HudButton {
            visible: bar.marketShown
            icon: "market"
            label: "Market"
            active: bar.marketOpen
            tip: "AION 2: your server's market prices"
            onClicked: bar.marketClicked()
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height - 24
            color: Qt.rgba(1, 1, 1, 0.1)
        }
        Item { width: 6; height: 1 }

        HudButton {
            icon: "radio"
            label: "Radio"
            active: bar.radioOpen
            tip: "Radio"
            onClicked: bar.radioClicked()
        }
        HudButton {
            icon: "tv"
            label: "TV"
            active: bar.streamsOpen
            tip: "Streams: Twitch and YouTube"
            onClicked: bar.streamsClicked()
        }

        Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
        Item { width: 6; height: 1 }

        HudButton {
            visible: Updates.state === "available" || Updates.state === "downloading" || Updates.state === "installing"
            icon: "update"
            label: Updates.state === "available" ? "Update" : "Wait"
            active: true
            tip: "Install update " + Updates.latest
            onClicked: bar.updateClicked()
        }
        HudButton {
            id: lockButton
            icon: Companion.locked ? "lock" : "unlock"
            active: !Companion.locked
            tip: Companion.locked ? "Unlock the overlay" : "Lock the overlay: clicks go through to the game"
            onClicked: Companion.toggleLocked()
        }
        HudButton {
            icon: "settings"
            active: bar.settingsOpen
            tip: "Settings"
            onClicked: bar.settingsClicked()
        }
        HudButton {
            icon: "hide"
            tip: "Hide the hub (pinned things stay)"
            onClicked: bar.hideClicked()
        }
    }

    // Dragging moves the bar sideways (measured on the screen: the bar's
    // window moves along, and its own scale does not matter).
    component DragArea: MouseArea {
        property real startX: 0
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        // The window holds the whole screen while dragging (Surface.held).
        property point start
        property var dragState: ({})
        function hold(on) { if (on) Drag.begin(Window.window); else Drag.end(Window.window) }
        onPressed: (mouse) => { start = mapToItem(bar.parent, mouse.x, mouse.y); startX = start.x; dragState = {}; hold(true) }
        onPositionChanged: (mouse) => {
            if (!pressed || !Drag.steady(Window.window)) return
            bar.dragShift = Drag.fix(Window.window, mapToItem(bar.parent, mouse.x, mouse.y), start, dragState).x - startX
        }
        onReleased: { bar.dropped(); hold(false) }
        onCanceled: { bar.dragShift = 0; hold(false) }
    }

    component ToolTipText: Rectangle {
        property alias text: label.text
        x: 0
        y: bar.height + 6
        width: label.implicitWidth + 16
        height: label.implicitHeight + 10
        color: Theme.panel(0.95)
        border.color: Theme.divider
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: label
            anchors.centerIn: parent
            color: Theme.textSoft(true)
            font.family: Theme.body
            font.pixelSize: 12
        }
    }
}
