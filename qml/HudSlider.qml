import QtQuick
import GameCompanion
import "theme.js" as Theme

// A plain slider: a dark track, the part up to the value in gold, a square
// handle. With `centre` set (a balance such as ChatMix): a mark at the
// centre, the gold part from the centre to the value, and a double click
// goes back to the centre (MN, 2026-11-20: "wo die Mitte ist").
Item {
    id: slider
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0.01
    /// The middle of a balance slider; NaN for a plain one.
    property real centre: NaN
    readonly property bool balanced: !isNaN(centre)
    /// While dragging; `moved` once let go.
    signal changing(real value)
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 24

    readonly property real ratio: (value - from) / (to - from)
    readonly property real centreRatio: balanced ? (centre - from) / (to - from) : 0
    // Where the handle's middle is for a ratio (the handle stays inside).
    function at(r) { return r * (width - 10) + 5 }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 3
        color: Theme.trackDark
        Rectangle {
            readonly property real a: slider.balanced ? slider.at(slider.centreRatio) : 0
            readonly property real b: slider.balanced ? slider.at(slider.ratio) : parent.width * slider.ratio
            x: Math.min(a, b)
            width: Math.abs(b - a)
            height: parent.height
            color: Theme.accent
        }
    }
    // The centre mark: under the handle, so it shows once the handle leaves it.
    Rectangle {
        visible: slider.balanced
        x: Math.round(slider.at(slider.centreRatio) - width / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 14
        color: Theme.muted()
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
            const r = Math.max(0, Math.min(1, (mx - 5) / (width - 10)))
            const raw = slider.from + r * (slider.to - slider.from)
            return Math.round(raw / slider.stepSize) * slider.stepSize
        }
        onPressed: (mouse) => slider.changing(valueAt(mouse.x))
        onPositionChanged: (mouse) => { if (pressed) slider.changing(valueAt(mouse.x)) }
        onReleased: (mouse) => slider.moved(valueAt(mouse.x))
        onDoubleClicked: { if (slider.balanced) { slider.changing(slider.centre); slider.moved(slider.centre) } }
    }
    Accessible.role: Accessible.Slider
}
