import QtQuick
import QtQuick.Shapes
import GameCompanion
import ".."
import "../theme.js" as Theme
import "../drag.js" as Drag
import "mapkit.js" as MK

// The overlay map (canvas page "Leiste geteilt und Overlay-Map", board
// O1Overlay; MN 2026-11-13): a small map over the game that follows you,
// as the old meter's. Always the map you are on, with your arrow and what
// the Map shows (or its own layers). Unlocked: a title strip with S, M, L,
// XL and close, drag by it, resize by the corner, the wheel zooms. Locked:
// only the map, clicks go to the game. Its settings are the Map's
// (`source.settings.overlay`, Settings → Plugins → Map). Works only while
// it is shown: hidden, nothing is built or drawn.
Item {
    id: ov
    /// The Map panel: its world, its settings, its tracked monsters.
    property var source: null
    /// Shown for a screenshot (GC_DEMO=overlay) without changing the settings.
    property bool demo: false
    /// Whether its surface shows now (Main): only then is anything built.
    property bool shown: false

    readonly property var o: source ? source.settings.overlay : null
    readonly property bool on: demo || (!!o && o.on)
    readonly property var sides: ({ s: 180, m: 240, l: 320, xl: 420 })
    /// The side while its corner is dragged (kept once let go).
    property real dragSide: 0
    readonly property real side: dragSide > 0 ? dragSide : !o ? 240 : o.w > 0 ? o.w : (sides[o.size] || 240)
    readonly property int strip: 24

    width: side
    height: strip + side

    // ---- where you are, and whether it hides there ----
    readonly property string key: {
        if (!source || !source.world) return ""
        source.settings.lastKey
        const w = source.whereAmI()
        return w ? w.key : ""
    }
    /// "instance", "arena", "abyss" or "" (the open world).
    readonly property string zoneKind: {
        if (!source || !source.world) return ""
        const zone = source.world.zone
        const name = zone != null ? String(MK.D.zoneNames[String(zone)] || "") : ""
        if (/arena/i.test(name)) return "arena"
        if (key.indexOf("abyss") === 0) return "abyss"
        if (key.length > 0 && MK.D.maps[key] && MK.D.maps[key].instance) return "instance"
        // A zone the tables have no map for: most likely a dungeon.
        if (key.length === 0 && zone != null) return "instance"
        return ""
    }
    /// Whether it wants to be on screen (Main adds Aion2.active).
    readonly property bool wanted: on && !(o && zoneKind.length > 0 && o.hideIn[zoneKind])

    // ---- what it shows, built again when the world or a setting changes ----
    property var built: null
    function update() {
        if (!shown || !source) return
        const s = source.settings
        built = key.length === 0 ? null : MK.M.build({ key: key, world: source.world, tracked: source.tracked, needed: null, heading: source.heading,
            layers: o.own ? o.layers : s.layers, gatherKinds: s.gatherKinds, petsMode: s.petsMode, focus: s.focus, nextFor: s.nextFor })
        map.marks = built ? built.marks : []
        const me = source.world ? source.world.me : null
        if (me && key.length > 0) {
            if (o.zoom > 0) map.setZoom(o.zoom)
            else map.setPxPerMetre(1.2)
            map.centerOn(me.x, me.y)
        }
    }
    onShownChanged: if (shown) Qt.callLater(update)
    onKeyChanged: Qt.callLater(update)
    Connections {
        target: ov.source
        function onWorldChanged() { ov.update() }
        function onSettingsChanged() { ov.update() }
        function onOverlayPlaced() { ov.placed = false; ov.place() }
    }

    // ---- its place: kept in the Map's settings, always on the screen ----
    property bool placed: false
    /// The kept place it was put at: another one (loaded late, a place 1
    /// to 3) puts it there.
    property var placedFrom: [-1, -1]
    function place() {
        if (placed || !parent || parent.width <= 0 || !o) return
        x = o.x >= 0 ? o.x : parent.width - side - 24
        y = o.y >= 0 ? o.y : 120
        keepOnScreen()
        placed = true
        placedFrom = [o.x, o.y]
    }
    function keepOnScreen() {
        if (!parent) return
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - height))
    }
    Component.onCompleted: place()
    onParentChanged: place()
    onOChanged: if (o && (o.x !== placedFrom[0] || o.y !== placedFrom[1])) { placed = false; place() }
    onSideChanged: if (placed && dragSide <= 0) { keepOnScreen(); Qt.callLater(update) }
    Connections {
        target: ov.parent
        function onWidthChanged() { if (ov.placed) ov.keepOnScreen(); else ov.place() }
        function onHeightChanged() { if (ov.placed) ov.keepOnScreen() }
    }
    function remember() { source.changeOverlay({ x: Math.round(x), y: Math.round(y), slot: -1 }) }

    // ---- the title strip (unlocked only) ----
    Rectangle {
        id: head
        visible: !Companion.locked
        width: parent.width
        height: ov.strip
        color: Theme.panel(Companion.alpha)
        Rectangle { width: parent.width; height: 2; color: Theme.accent }
        MoveArea {
            anchors.fill: parent
            target: ov
            maximumY: ov.parent ? ov.parent.height - ov.height : 0
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onReleased: ov.remember()
        }
        Row {
            x: 8
            height: parent.height
            spacing: 6
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                text: "MAP"
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, ov.width - 8 - 30 - sizes.width - 40)
                elide: Text.ElideRight
                text: ov.key.length > 0 && MK.D.maps[ov.key] ? MK.D.maps[ov.key].title : ""
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 10
            }
        }
        Row {
            id: sizes
            anchors.right: closeButton.left
            anchors.rightMargin: 2
            height: parent.height
            Repeater {
                model: ["s", "m", "l", "xl"]
                delegate: Item {
                    required property string modelData
                    readonly property bool chosen: !!ov.o && ov.o.w <= 0 && ov.o.size === modelData
                    width: sizeText.implicitWidth + 10
                    height: parent.height
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: sizeText
                        anchors.centerIn: parent
                        text: parent.modelData.toUpperCase()
                        color: parent.chosen ? Theme.accent : sizeMouse.containsMouse ? Theme.text() : Theme.muted()
                        font.family: Theme.display
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: sizeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ov.source.changeOverlay({ size: parent.modelData, w: 0, slot: -1 })
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Size " + modelData.toUpperCase()
                }
            }
        }
        IconButton {
            id: closeButton
            anchors.right: parent.right
            width: 24
            height: parent.height
            icon: "close"
            iconSize: 10
            tip: "Hide the overlay map (Alt+M, or right-click MAP)"
            onClicked: ov.source.changeOverlay({ on: false })
        }
    }

    // ---- the map ----
    MapView {
        id: map
        y: ov.strip
        width: ov.side
        height: ov.side
        dir: ov.source ? ov.source.dir : ""
        mapKey: ov.key
        markScale: ov.o ? ov.o.markScale : 1.25
        tileOpacity: ov.o ? ov.o.opacity : 0.75
        interactive: !Companion.locked
        draggable: false
        onZoomed: (z) => ov.source.changeOverlay({ zoom: z })
        onFittedNow: Qt.callLater(ov.update)
        Rectangle { anchors.fill: parent; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.18) }
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        visible: ov.key.length === 0
        anchors.centerIn: map
        width: map.width - 24
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Aion2.active ? "Waiting for your position" : "Shows where you are while AION 2 runs"
        color: Theme.muted()
        font.family: Theme.body
        font.pixelSize: 11
    }

    // Next, under the map.
    Rectangle {
        readonly property var next: ov.built && ov.source && ov.source.world && ov.source.world.me ? ov.built.next : null
        visible: next !== null
        anchors.bottom: map.bottom
        width: map.width
        height: 20
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.7)
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 6
            width: parent.width - 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: {
                const n = parent.next
                if (!n) return ""
                const way = n.via ? "Kibelisk " + n.via.name + ", then " + Math.round(n.via.metres) + " m" : MK.M.arrow(n.bearing) + " " + Math.round(n.metres) + " m"
                return "<font color='" + Theme.accent + "'>Next</font> " + n.name + " · " + way
            }
            color: Theme.text()
            font.family: Theme.body
            font.pixelSize: 10
        }
    }

    // Gold corners while unlocked; the bottom right one changes the size.
    Repeater {
        model: !Companion.locked ? [[0, 0], [1, 0], [0, 1]] : []
        delegate: Item {
            required property var modelData
            x: modelData[0] ? map.width - 7 : -3
            y: map.y + (modelData[1] ? map.height - 7 : -3)
            width: 10
            height: 10
            Rectangle { y: parent.modelData[1] ? 8 : 0; width: 10; height: 2; color: Theme.accent }
            Rectangle { x: parent.modelData[0] ? 8 : 0; width: 2; height: 10; color: Theme.accent }
        }
    }
    Item {
        id: grip
        visible: !Companion.locked
        x: map.width - 14
        y: map.y + map.height - 14
        width: 17
        height: 17
        Rectangle { x: 6; y: 14; width: 11; height: 2; color: gripMouse.containsMouse || gripMouse.pressed ? Theme.text() : Theme.accent }
        Rectangle { x: 15; y: 6; width: 2; height: 10; color: gripMouse.containsMouse || gripMouse.pressed ? Theme.text() : Theme.accent }
        MouseArea {
            id: gripMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property point start
            property real startSide
            property var dragState: ({})
            function hold(on) { if (on) Drag.begin(Window.window); else Drag.end(Window.window) }
            onPressed: (mouse) => {
                start = mapToItem(ov.parent, mouse.x, mouse.y)
                startSide = ov.side
                dragState = {}
                hold(true)
            }
            onCanceled: hold(false)
            onPositionChanged: (mouse) => {
                if (!pressed || !Drag.steady(Window.window)) return
                const p = Drag.fix(Window.window, mapToItem(ov.parent, mouse.x, mouse.y), start, dragState)
                const room = ov.parent ? Math.min(ov.parent.width - ov.x, ov.parent.height - ov.y - ov.strip) : 640
                const grown = Math.max(p.x - start.x, p.y - start.y)
                ov.dragSide = Math.round(Math.max(140, Math.min(startSide + grown, 640, room)))
            }
            onReleased: {
                if (ov.dragSide > 0) ov.source.changeOverlay({ w: ov.dragSide, slot: -1 })
                ov.dragSide = 0
                hold(false)
            }
            onDoubleClicked: ov.source.changeOverlay({ w: 0 })
        }
        Accessible.role: Accessible.Grip
        Accessible.name: "Resize the overlay map (double-click: back to its size)"
    }
}
