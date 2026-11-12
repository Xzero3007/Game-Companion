import QtQuick

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
    onPressed: (m) => {
        if (!target || !moves) return
        start = onScreen(m)
        from = Qt.point(target.x, target.y)
    }
    onPositionChanged: (m) => {
        if (!pressed || !target || !moves) return
        const p = onScreen(m)
        target.x = Math.max(minimumX, Math.min(maximumX, from.x + p.x - start.x))
        target.y = Math.max(minimumY, Math.min(maximumY, from.y + p.y - start.y))
    }
}
