import QtQuick

// The mouse wheel over a list: each notch moves it a set distance at once
// (Qt's own wheel scrolling crept along). Lies over the list and takes
// only the wheel: clicks and the pointer go through to the rows.
MouseArea {
    /// The list (or any Flickable) it scrolls.
    property Flickable flick
    /// Pixels a wheel notch moves.
    property real step: 120

    anchors.fill: flick
    visible: !!flick && flick.visible
    acceptedButtons: Qt.NoButton
    onWheel: (wheel) => {
        if (!flick) return
        const room = flick.contentHeight + flick.topMargin + flick.bottomMargin - flick.height
        if (room <= 0) { wheel.accepted = false; return }
        // A touchpad says pixels; a wheel says eighths of a degree (120 a notch).
        const by = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * step
        const top = flick.originY - flick.topMargin
        flick.cancelFlick()
        flick.contentY = Math.max(top, Math.min(top + room, flick.contentY - by))
    }
}
