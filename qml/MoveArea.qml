import QtQuick
import "drag.js" as Drag

// Moves `target` while dragged, measured on the screen (the target's
// parent is as big as the screen): its window moves along with it, so the
// pointer's place in the window cannot be used.
MouseArea {
    id: area
    property Item target
    /// Whether dragging moves the target now.
    property bool moves: true
    property real minimumX: 0
    property real minimumY: 0
    property real maximumX: target && target.parent ? target.parent.width - target.width : 0
    property real maximumY: target && target.parent ? target.parent.height - 40 : 0
    property point start
    property point from

    function onScreen(m) { return mapToItem(target.parent, m.x, m.y) }
    // The window holds the whole screen while dragging (see Surface.held).
    property var dragState: ({})
    function hold(on) { if (on) Drag.begin(area.Window.window); else Drag.end(area.Window.window) }
    function steady() { return Drag.steady(area.Window.window) }
    onPressed: (m) => {
        if (!target || !moves) return
        start = onScreen(m)
        from = Qt.point(target.x, target.y)
        dragState = {}
        hold(true)
    }
    onReleased: hold(false)
    onCanceled: hold(false)
    onPositionChanged: (m) => {
        if (!pressed || !target || !moves || !steady()) return
        const p = Drag.fix(area.Window.window, onScreen(m), start, dragState)
        target.x = Math.max(minimumX, Math.min(maximumX, from.x + p.x - start.x))
        target.y = Math.max(minimumY, Math.min(maximumY, from.y + p.y - start.y))
    }
}
