import QtQuick
import GameCompanion

// The mouse wheel over a list: each notch glides it a set distance (Qt's
// own wheel scrolling crept along). Lies over the list and takes only the
// wheel: clicks and the pointer go through to the rows. A touchpad moves
// it one to one. Notches in a row, and the many small steps of a
// high-resolution wheel, add to where the glide goes without starting it
// again (SmoothedAnimation keeps its speed when the goal moves): the list
// runs on evenly instead of jerking at every step. Settings → Display
// "Scroll speed" scales every step (Companion.wheelSpeed, percent).
//
// A notch is told by its angle (a multiple of 120): on KDE Wayland Qt
// gives a mouse wheel's notch a small pixel delta as well (about 15 px),
// which was taken for a touchpad and scrolled almost nothing (MN).
MouseArea {
    id: wheelArea
    /// The list (or any Flickable) it scrolls.
    property Flickable flick
    /// Pixels a wheel notch moves.
    property real step: 120
    /// Where the glide goes.
    property real target: 0
    /// The glide's place; the list follows it while it glides.
    property real pos: 0
    property bool gliding: false

    anchors.fill: flick
    visible: !!flick && flick.visible
    acceptedButtons: Qt.NoButton

    Behavior on pos {
        enabled: wheelArea.gliding
        SmoothedAnimation { id: glide; velocity: -1; duration: 180 }
    }
    onPosChanged: if (gliding && flick) flick.contentY = pos

    onWheel: (wheel) => {
        if (!flick) return
        const room = flick.contentHeight + flick.topMargin + flick.bottomMargin - flick.height
        if (room <= 0) { wheel.accepted = false; return }
        const top = flick.originY - flick.topMargin
        const clamp = (y) => Math.max(top, Math.min(top + room, y))
        flick.cancelFlick()
        const speed = Companion.wheelSpeed / 100
        const angle = wheel.angleDelta.y
        const notch = angle !== 0 && (angle % 120 === 0 || wheel.pixelDelta.y === 0)
        if (!notch && wheel.pixelDelta.y !== 0) {
            // A touchpad (or a fine wheel) says pixels: follow them.
            gliding = false
            flick.contentY = clamp(flick.contentY - wheel.pixelDelta.y * speed)
            return
        }
        if (angle === 0) { wheel.accepted = false; return }
        if (!glide.running) {
            // Start from where the list is now (it may have moved otherwise).
            gliding = false
            pos = flick.contentY
            target = flick.contentY
            gliding = true
        }
        // A wheel says eighths of a degree (120 a notch).
        target = clamp(target - angle / 120 * step * speed)
        pos = target
    }
}
