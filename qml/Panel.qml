import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme
import "drag.js" as Drag

// A window of the overlay: square corners, a header in capitals (no gold
// line on top: MN, 2026-11-14). Unlocked, it moves by its header, changes size by the
// gold corner at its bottom right, and remembers both; locked, clicks go
// through it to the game.
Item {
    id: panel
    /// Remembered under this id.
    property string panelId
    property string title
    /// Text right of the title, in gold (a count, a state).
    property string badge: ""
    /// An icon left of the title (HudIcon names).
    property string icon: ""
    /// A game module's purple tag beside the title ("AION 2"), or "".
    property string tag: ""
    /// A button in the header before the pin ("Reset"), or "".
    property string actionText: ""
    signal actionClicked
    /// Whether it can be pinned (it then stays while the hub is hidden).
    property bool pinnable: true
    readonly property bool pinned: Companion.pins.indexOf('"' + panelId + '"') >= 0
    property real defaultX: 24
    property real defaultY: 120
    /// Whether the corner changes its size.
    property bool resizable: true
    property real minWidth: 340
    property real maxWidth: 1000
    /// Whether it also grows downwards: its list or video takes `grow`.
    property bool stretchy: false
    /// The height the user added (for the panel's list or video to use).
    property real grow: 0
    property real maxGrow: 700
    /// Below 0: the list can be made shorter than it starts.
    property real minGrow: 0
    /// Its own width, before the user changed it.
    property real ownWidth: 0
    /// How solid its ground is (the opacity setting; the chat goes clearer).
    property real ground: Companion.alpha
    /// Slim (the DPS meter, like the old meter): a 30 px header with smaller
    /// buttons, and the body edge to edge with 8 px sides.
    property bool compact: false
    /// Shown in the header after the title (a slim panel's tabs).
    property Component headerTools: null
    default property alias content: body.data
    signal closeClicked
    /// Emitted when it moves, resizes, shows or hides: the input region changes.
    signal areaChanged

    width: 400
    height: header.height + (compact ? 0 : 12) + body.height + (compact ? 0 : 14)

    // Placed once the screen's size is known: where it was left, else at
    // its default place, always on the screen.
    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0) return
        if (ownWidth <= 0) ownWidth = width
        const saved = panelId.length > 0 ? Companion.placeOf(panelId) : ""
        if (saved.length > 0) {
            const p = JSON.parse(saved)
            width = resizable && p.w > 0 ? Math.max(minWidth, Math.min(p.w, maxWidth)) : ownWidth
            grow = resizable && stretchy ? Math.max(minGrow, Math.min(p.grow || 0, maxGrow)) : 0
            x = p.x
            y = p.y
        } else {
            width = ownWidth
            grow = 0
            x = defaultX
            y = defaultY
        }
        keepOnScreen()
        placed = true
    }
    Component.onCompleted: place()
    // Its window (Surface) takes it in after it was made.
    onParentChanged: place()
    Connections {
        target: panel.parent
        // Another screen (Settings → Display "Show on"): stay on it.
        function onWidthChanged() { if (panel.placed) panel.keepOnScreen(); else panel.place() }
        function onHeightChanged() { if (panel.placed) panel.keepOnScreen() }
    }
    // A layout was loaded: take its place and size.
    Connections {
        target: Companion
        function onLayoutRevisionChanged() { panel.placed = false; panel.place() }
    }
    function remember() {
        Companion.savePlace(panelId, x, y, width !== ownWidth ? width : 0, grow)
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
        color: Theme.panel(panel.ground)
    }
    Rectangle {
        id: header
        width: parent.width
        height: panel.compact ? 30 : 40
        color: Theme.headerTint

        MoveArea {
            anchors.fill: parent
            enabled: !Companion.locked
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            target: panel
            onReleased: panel.remember()
        }

        HudIcon {
            id: titleIcon
            visible: panel.icon.length > 0
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            name: panel.icon
            color: Theme.accent
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: titleText
            anchors.left: panel.icon.length > 0 ? titleIcon.right : parent.left
            anchors.leftMargin: panel.icon.length > 0 ? 10 : (panel.compact ? 10 : 14)
            anchors.verticalCenter: parent.verticalCenter
            text: panel.title.toUpperCase()
            color: Theme.text()
            font.family: Theme.display
            font.pixelSize: panel.compact ? 13 : 15
            font.weight: Font.Bold
            font.letterSpacing: 2
        }
        Rectangle {
            id: tagBox
            visible: panel.tag.length > 0
            anchors.left: titleText.right
            anchors.leftMargin: panel.compact ? 8 : 10
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? tagText.implicitWidth + (panel.compact ? 10 : 14) : 0
            height: tagText.implicitHeight + 2
            color: Qt.rgba(0.608, 0.42, 0.91, 0.4)
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: tagText
                anchors.centerIn: parent
                text: panel.tag.toUpperCase()
                color: Theme.purpleText
                font.family: Theme.display
                font.pixelSize: panel.compact ? 10 : 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
        Loader {
            active: panel.headerTools !== null
            sourceComponent: panel.headerTools
            anchors.left: tagBox.visible ? tagBox.right : titleText.right
            anchors.leftMargin: 14
            anchors.right: badgeText.visible ? badgeText.left : actionButton.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
        Item {
            id: pinButton
            visible: panel.pinnable
            anchors.right: closeButton.left
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? (panel.compact ? 24 : 32) : 0
            height: panel.compact ? 24 : 32
            HudIcon {
                anchors.centerIn: parent
                name: "pin"
                size: panel.compact ? 12 : 15
                filled: panel.pinned
                color: panel.pinned ? Theme.accent : (pinMouse.containsMouse ? Theme.text() : Theme.dim())
            }
            MouseArea {
                id: pinMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !Companion.locked
                onClicked: Companion.togglePin(panel.panelId)
            }
            Accessible.role: Accessible.CheckBox
            Accessible.name: panel.pinned ? "Unpin: hide with the hub" : "Pin: stay when the hub is hidden"
        }
        TextButton {
            id: actionButton
            visible: panel.actionText.length > 0
            anchors.right: pinButton.left
            anchors.rightMargin: visible ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? implicitWidth : 0
            implicitHeight: panel.compact ? 20 : 28
            pixelSize: panel.compact ? 11 : 13
            pad: panel.compact ? 7 : 14
            text: panel.actionText
            onClicked: if (!Companion.locked) panel.actionClicked()
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: badgeText
            anchors.right: actionButton.left
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
            anchors.rightMargin: panel.compact ? 3 : 6
            anchors.verticalCenter: parent.verticalCenter
            width: panel.compact ? 24 : 32
            height: panel.compact ? 24 : 32
            HudIcon {
                anchors.centerIn: parent
                name: "close"
                size: panel.compact ? 11 : 14
                lineWidth: 2
                color: closeMouse.containsMouse ? Theme.text() : Theme.dim()
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
        anchors.margins: panel.compact ? 8 : 14
        anchors.topMargin: panel.compact ? 0 : 12
        height: childrenRect.height
    }

    // The corner that changes the size (unlocked only).
    Item {
        id: grip
        visible: panel.resizable && !Companion.locked
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 18
        height: 18
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: "transparent"
                fillColor: gripMouse.containsMouse || gripMouse.pressed ? Theme.accent : Qt.rgba(0.878, 0.647, 0.149, 0.55)
                startX: grip.width; startY: 4
                PathLine { x: grip.width; y: grip.height }
                PathLine { x: 4; y: grip.height }
                PathLine { x: grip.width; y: 4 }
            }
        }
        MouseArea {
            id: gripMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: panel.stretchy ? Qt.SizeFDiagCursor : Qt.SizeHorCursor
            property point start
            property real startWidth
            property real startGrow
            // The window holds the whole screen while resizing (Surface.held).
            property var dragState: ({})
            function hold(on) { if (on) Drag.begin(Window.window); else Drag.end(Window.window) }
            function steady() { return Drag.steady(Window.window) }
            onPressed: (mouse) => {
                start = mapToItem(panel.parent, mouse.x, mouse.y)
                startWidth = panel.width
                startGrow = panel.grow
                dragState = {}
                hold(true)
            }
            onCanceled: hold(false)
            onPositionChanged: (mouse) => {
                if (!pressed || !steady()) return
                const p = Drag.fix(Window.window, mapToItem(panel.parent, mouse.x, mouse.y), start, dragState)
                const room = panel.parent ? panel.parent.width - panel.x : panel.maxWidth
                panel.width = Math.max(panel.minWidth, Math.min(startWidth + p.x - start.x, panel.maxWidth, room))
                if (panel.stretchy) {
                    const below = panel.parent ? panel.parent.height - panel.y - panel.height + panel.grow : panel.maxGrow
                    panel.grow = Math.max(panel.minGrow, Math.min(startGrow + p.y - start.y, panel.maxGrow, below))
                }
            }
            onReleased: { panel.remember(); hold(false) }
            onDoubleClicked: { panel.width = panel.ownWidth; panel.grow = 0; panel.remember() }
        }
        Accessible.role: Accessible.Grip
        Accessible.name: "Resize " + panel.title + " (double-click: back to its size)"
    }
}
