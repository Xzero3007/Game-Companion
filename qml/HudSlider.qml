import QtQuick
import GameCompanion
import "theme.js" as Theme

// A plain slider: a dark track, the part up to the value in gold, a square
// handle.
Item {
    id: slider
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0.01
    /// While dragging; `moved` once let go.
    signal changing(real value)
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 24

    readonly property real ratio: (value - from) / (to - from)

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 3
        color: Theme.trackDark
        Rectangle {
            width: parent.width * slider.ratio
            height: parent.height
            color: Theme.accent
        }
    }
    Rectangle {
        x: slider.ratio * (slider.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 18
        color: Theme.accent
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function valueAt(mx) {
            const r = Math.max(0, Math.min(1, mx / width))
            const raw = slider.from + r * (slider.to - slider.from)
            return Math.round(raw / slider.stepSize) * slider.stepSize
        }
        onPressed: (mouse) => slider.changing(valueAt(mouse.x))
        onPositionChanged: (mouse) => { if (pressed) slider.changing(valueAt(mouse.x)) }
        onReleased: (mouse) => slider.moved(valueAt(mouse.x))
    }
    Accessible.role: Accessible.Slider
}
