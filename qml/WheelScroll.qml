import QtQuick

// The mouse wheel over a list: each notch glides it a set distance (Qt's
// own wheel scrolling crept along). Lies over the list and takes only the
// wheel: clicks and the pointer go through to the rows. A touchpad moves
// it one to one.
MouseArea {
    id: wheelArea
    /// The list (or any Flickable) it scrolls.
    property Flickable flick
    /// Pixels a wheel notch moves.
    property real step: 120
    /// Where the glide goes (notches in a row add up).
    property real target: 0

    anchors.fill: flick
    visible: !!flick && flick.visible
    acceptedButtons: Qt.NoButton

    NumberAnimation {
        id: glide
        target: wheelArea.flick
        property: "contentY"
        duration: 160
        easing.type: Easing.OutCubic
    }

    onWheel: (wheel) => {
        if (!flick) return
        const room = flick.contentHeight + flick.topMargin + flick.bottomMargin - flick.height
        if (room <= 0) { wheel.accepted = false; return }
        const top = flick.originY - flick.topMargin
        const clamp = (y) => Math.max(top, Math.min(top + room, y))
        flick.cancelFlick()
        if (wheel.pixelDelta.y !== 0) {
            // A touchpad says pixels: follow it as it is.
            glide.stop()
            flick.contentY = clamp(flick.contentY - wheel.pixelDelta.y)
            return
        }
        // A wheel says eighths of a degree (120 a notch).
        const from = glide.running ? target : flick.contentY
        target = clamp(from - wheel.angleDelta.y / 120 * step)
        glide.stop()
        glide.from = flick.contentY
        glide.to = target
        glide.start()
    }
}
