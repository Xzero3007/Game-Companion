import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme
import "drag.js" as Drag

// The bar docked at the top centre of the screen, with slanted ends and a
// thin gold line under it: the name and the running game, the core's
// buttons (Games, Radio, TV), Brave and Legcord (their real windows over
// the game, `Apps`; a right click opens their menu), then lock, settings
// and hide. The running
// game's buttons are in the smaller row under it (GameRow).
Item {
    id: bar
    property bool settingsOpen: false
    property bool radioOpen: false
    signal radioClicked
    property bool gamesOpen: false
    signal gamesClicked
    /// The running game has a module (purple); else it just shows its name.
    property bool gameHasModule: false
    property bool streamsOpen: false
    signal streamsClicked
    property string gameName: ""
    signal settingsClicked
    signal hideClicked
    signal updateClicked
    /// Settings → Apps, from an app's menu.
    signal appSettingsClicked

    /// Brave and Legcord (Apps.state) and the app whose menu is open.
    readonly property var apps: JSON.parse(Apps.state)
    property string menuFor: ""
    readonly property bool menuShown: menuFor.length > 0
    /// The keys KDE gave the shortcuts (Companion.shortcuts).
    property var keys: []
    function keyOf(id) {
        for (const k of keys) if (k.id === id) return k.key
        return ""
    }
    function app(id) { return apps.apps && apps.apps[id] ? apps.apps[id] : ({ name: id, running: false, shown: false, windows: 0, opacity: 90, why: "" }) }
    function toggleApp(id) { menuFor = ""; Apps.toggle(id, nativeWindow.screenName) }
    onVisibleChanged: if (!visible) menuFor = ""
    Connections {
        target: Companion
        function onLockedChanged() { if (Companion.locked) bar.menuFor = "" }
    }
    /// The room the open menu needs under the bar (the bar's window grows).
    readonly property real menuBottom: menuShown ? appMenu.y + appMenu.height + 2 : 0

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
        AppButton { id: braveButton; appId: "brave"; icon: "browser" }
        AppButton { id: legcordButton; appId: "legcord"; icon: "headset" }

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

    // An app's menu (C1, MN 2026-11-14): under its button, inside the bar's
    // window (which grows for it, `menuBottom`).
    Rectangle {
        id: appMenu
        readonly property var info: bar.app(bar.menuFor)
        readonly property Item button: bar.menuFor === "legcord" ? legcordButton : braveButton
        visible: bar.menuShown
        x: Math.max(0, Math.min(bar.width - width, button.mapToItem(bar, 0, 0).x + button.width / 2 - width / 2))
        y: bar.height + 4
        width: 230
        height: menuColumn.implicitHeight + 12
        color: Theme.panel(0.95)
        border.color: Theme.divider
        HoverHandler { id: menuHover }
        // The pointer left the menu: it closes (a timer only while open).
        Timer {
            running: bar.menuShown && !menuHover.hovered
            interval: 1600
            onTriggered: bar.menuFor = ""
        }
        Column {
            id: menuColumn
            x: 0
            y: 6
            width: parent.width
            MenuText { text: appMenu.info.name.toUpperCase(); header: true
                note: appMenu.info.starting ? "STARTING" : appMenu.info.shown ? "SHOWN" : appMenu.info.running ? "RUNNING" : "NOT RUNNING" }
            MenuRow {
                text: "Over the game"
                on: appMenu.info.shown === true
                note: bar.keyOf(bar.menuFor).toUpperCase()
                onClicked: bar.toggleApp(bar.menuFor)
            }
            Item {
                width: parent.width
                height: 30
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Opacity"
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    IconButton { icon: "minus"; width: 24; height: 24; tip: "Less"; onClicked: Apps.setOpacity(bar.menuFor, appMenu.info.opacity - 10) }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        width: 40
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: appMenu.info.opacity + " %"
                        color: Theme.accent
                        font.family: Theme.display
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    IconButton { icon: "plus"; width: 24; height: 24; tip: "More"; onClicked: Apps.setOpacity(bar.menuFor, appMenu.info.opacity + 10) }
                }
            }
            MenuRow {
                visible: appMenu.info.windows > 1
                text: "Next window (" + appMenu.info.windows + " open)"
                onClicked: { Apps.nextWindow(bar.menuFor, nativeWindow.screenName); bar.menuFor = "" }
            }
            MenuRow {
                text: "Settings"
                onClicked: { bar.menuFor = ""; bar.appSettingsClicked() }
            }
            MenuRow {
                visible: appMenu.info.windows > 0
                text: "Close " + appMenu.info.name
                onClicked: { Apps.closeWindow(bar.menuFor); bar.menuFor = "" }
            }
            MenuText {
                visible: (appMenu.info.why || "").length > 0
                text: appMenu.info.why || ""
                warn: true
            }
        }
    }

    // Brave or Legcord: a click shows its real window over the game or hides
    // it, a right click opens its menu. The square: grey, it runs; gold,
    // shown over the game.
    component AppButton: HudButton {
        property string appId
        readonly property var info: bar.app(appId)
        label: info.name
        active: info.shown === true || bar.menuFor === appId
        dot: info.shown ? "on" : info.running ? "run" : ""
        tip: info.name + (info.shown ? ": hide it" : info.running ? ": show it over the game" : ": start it and show it over the game")
            + (bar.keyOf(appId).length > 0 ? " (" + bar.keyOf(appId) + ")" : "") + " · right click: menu"
        onClicked: bar.toggleApp(appId)
        onRightClicked: bar.menuFor = bar.menuFor === appId ? "" : appId
    }
    component MenuText: Item {
        property alias text: menuLabel.text
        property string note: ""
        property bool header: false
        property bool warn: false
        width: parent ? parent.width : 200
        height: menuLabel.implicitHeight + (header ? 12 : 10)
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: menuLabel
            x: 12
            width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            color: parent.warn ? Theme.red : parent.header ? Theme.dim() : Theme.textSoft()
            font.family: parent.header ? Theme.display : Theme.body
            font.pixelSize: parent.header ? 11 : 12
            font.weight: parent.header ? Font.Bold : Font.Normal
            font.letterSpacing: parent.header ? 2 : 0
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: parent.note.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: parent.note
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
    }
    component MenuRow: Item {
        id: menuRow
        property string text
        property string note: ""
        property bool on: false
        signal clicked
        width: parent ? parent.width : 200
        height: visible ? 30 : 0
        Rectangle { anchors.fill: parent; color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 80
            elide: Text.ElideRight
            text: menuRow.text
            color: menuRow.on ? Theme.accent : (rowMouse.containsMouse ? Theme.text() : Theme.textSoft())
            font.family: Theme.body
            font.pixelSize: 12
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: menuRow.note.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.note
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRow.clicked()
        }
        Accessible.role: Accessible.MenuItem
        Accessible.name: menuRow.text
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
