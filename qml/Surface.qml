import QtQuick
import QtQuick.Window
import GameCompanion

// One part of the overlay (the bar, the player row, a panel, a video) in a
// window of its own on KDE's overlay layer, just as big as the part: the
// rest of the screen stays the game's, and a video redraws only its own
// area. The part keeps its place in screen coordinates (`scene`, the
// item it lives in, is as big as the screen and shifted so that the part
// shows in this window); the window follows it.
Window {
    id: surface
    /// The part: its x and y are screen pixels (scale from its top left).
    property Item part
    /// Whether the part is on screen.
    property bool wanted: true
    /// Whether it takes clicks while the overlay is unlocked.
    property bool clickable: true
    /// What still takes clicks while locked (the bar's lock), or null.
    property Item lockItem: null
    /// Room outside the part, in its own coordinates (a tooltip under it).
    property rect extra: Qt.rect(0, 0, 0, 0)
    /// Stacking for screenshots: higher on top (videos under panels).
    property int stack: 0
    /// The item the part lives in: screen coordinates.
    readonly property Item scene: holder

    /// While a part is dragged or resized: the window covers the whole
    /// screen and stays still, the part moves inside it. A window that
    /// moved with every pointer event jumped about: KDE places it a moment
    /// later, and the pointer's next place came from the old position.
    property bool held: false
    /// Where the window was when the press came (see drag.js).
    property point heldOrigin: Qt.point(0, 0)
    function grab(on) {
        if (on && !held) heldOrigin = Qt.point(area.x, area.y)
        held = on
    }
    /// The window has had time to take the whole screen: pointer places
    /// are measured from it from now on (MoveArea ignores moves until then).
    property bool steady: false
    onHeldChanged: { steady = false; if (held) settle.restart() }
    Timer { id: settle; interval: 120; onTriggered: surface.steady = true }

    property bool attached: false
    transientParent: null
    title: "Game Companion"
    color: "transparent"

    readonly property real screenW: nativeWindow.screenWidth
    readonly property real screenH: nativeWindow.screenHeight
    // The part's rectangle on the screen (with `extra`), whole pixels,
    // cut to the screen.
    readonly property rect area: {
        if (!part) return Qt.rect(0, 0, 1, 1)
        if (held) return Qt.rect(0, 0, screenW, screenH)
        const s = part.scale
        let x1 = part.x, y1 = part.y
        let x2 = part.x + part.width * s, y2 = part.y + part.height * s
        if (extra.width > 0 && extra.height > 0) {
            x1 = Math.min(x1, part.x + extra.x * s)
            y1 = Math.min(y1, part.y + extra.y * s)
            x2 = Math.max(x2, part.x + (extra.x + extra.width) * s)
            y2 = Math.max(y2, part.y + (extra.y + extra.height) * s)
        }
        x1 = Math.max(0, Math.floor(x1)); y1 = Math.max(0, Math.floor(y1))
        x2 = Math.min(screenW, Math.ceil(x2)); y2 = Math.min(screenH, Math.ceil(y2))
        return Qt.rect(x1, y1, Math.max(1, x2 - x1), Math.max(1, y2 - y1))
    }
    visible: attached && wanted && !nativeWindow.screenshotMode && part !== null && part.width > 0 && part.height > 0

    // Screenshots (GC_SCREENSHOT): the part goes into the one window that
    // is grabbed, in its place on the screen.
    readonly property Item home: nativeWindow.screenshotMode && nativeWindow.shotScene ? nativeWindow.shotScene : holder
    onHomeChanged: if (part && attached) { part.parent = home; part.z = stack }
    Binding {
        when: nativeWindow.screenshotMode && surface.part !== null
        target: surface.part
        property: "visible"
        value: surface.wanted
    }

    Item {
        id: holder
        x: -surface.area.x
        y: -surface.area.y
        width: surface.screenW
        height: surface.screenH
    }

    onAreaChanged: if (attached) { nativeWindow.place(surface, area); input(); settleInput.restart() }
    // The compositor takes a new size a moment later: the input region is
    // given again then, so a resized window never keeps a stale one (the
    // DPS panel took no clicks after its first fight grew it, on KWin).
    Timer { id: settleInput; interval: 250; onTriggered: surface.applyInput() }
    // Shown for the first time, a layer surface takes its input region only
    // once the compositor has configured it: given again a moment later
    // (the game row took no clicks on KWin until it was hidden and shown).
    onVisibleChanged: if (visible) { input(); settleInput.restart() }
    Component.onCompleted: {
        if (part) { part.parent = home; part.z = stack; surface.objectName = part.panelId !== undefined ? part.panelId : String(part).split("(")[0] }
        nativeWindow.attach(surface)
        nativeWindow.place(surface, area)
        attached = true
        input()
    }

    // Where it takes clicks: everywhere while unlocked, else only the
    // lock (or nowhere: clicks go through to the game).
    function input() { Qt.callLater(applyInput) }
    function applyInput() {
        const open = !Companion.locked && clickable
        const rects = []
        if (!open && lockItem && lockItem.visible) {
            rects.push(lockItem.mapToItem(surface.contentItem, 0, 0, lockItem.width, lockItem.height))
        }
        nativeWindow.setInput(surface, open, rects)
        nativeWindow.setKeyboard(surface, open)
    }
    Connections {
        target: Companion
        function onLockedChanged() { surface.input() }
    }
    // Another screen (picked, or KDE's primary changed): placed there anew.
    Connections {
        target: nativeWindow
        function onScreenChanged() { if (surface.attached) { nativeWindow.place(surface, surface.area); surface.input() } }
    }
    Connections {
        target: surface.lockItem
        ignoreUnknownSignals: true
        function onXChanged() { surface.input() }
        function onYChanged() { surface.input() }
        // A part that grows or shrinks (the Closet window's list) takes
        // the mouse over its new size.
        function onWidthChanged() { surface.input() }
        function onHeightChanged() { surface.input() }
        function onVisibleChanged() { surface.input() }
    }
}
