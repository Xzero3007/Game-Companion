import QtQuick
import GameCompanion
import "theme.js" as Theme
import "playerkeys.js" as PK

// A plain slider: a dark track, the part up to the value in gold, a square
// handle. With `centre` set (a balance such as ChatMix): a notch above and
// below the track at the centre, the gold part from the centre to the
// value, and a right click goes back to the centre (MN, 2026-11-21: a line
// across looked like a second handle, a double click picked a value first).
// `wheel` makes the mouse wheel step it: `wheelStep` per notch, by default
// the central "Volume step" (Settings → Display); for volume controls only,
// so lists still scroll over the other sliders.
Item {
    id: slider
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0.01
    /// The middle of a balance slider; NaN for a plain one.
    property real centre: NaN
    readonly property bool balanced: !isNaN(centre)
    /// Let go this close to the centre, it rests there (the wheel steps on).
    property real snap: 0
    /// The mouse wheel steps it (volume controls).
    property bool wheel: false
    property real wheelStep: PK.prefs(Streams.player).volume_step
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
    // The centre notches, above and below the track (under the handle).
    Repeater {
        model: slider.balanced ? [-1, 1] : []
        delegate: Rectangle {
            required property int modelData
            x: Math.round(slider.at(slider.centreRatio) - width / 2)
            y: slider.height / 2 + (modelData < 0 ? -2 - height : 2)
            width: 2
            height: 5
            color: Theme.dim()
        }
    }
    Rectangle {
        x: slider.ratio * (slider.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 18
        color: Theme.accent
    }
    function toCentre() {
        changing(centre)
        moved(centre)
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: slider.balanced ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        function valueAt(mx) {
            const r = Math.max(0, Math.min(1, (mx - 5) / (width - 10)))
            const raw = slider.from + r * (slider.to - slider.from)
            return Math.round(raw / slider.stepSize) * slider.stepSize
        }
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) slider.toCentre()
            else slider.changing(valueAt(mouse.x))
        }
        onPositionChanged: (mouse) => { if (pressedButtons & Qt.LeftButton) slider.changing(valueAt(mouse.x)) }
        onReleased: (mouse) => {
            if (mouse.button !== Qt.LeftButton) return
            const v = valueAt(mouse.x)
            slider.moved(slider.balanced && Math.abs(v - slider.centre) < slider.snap ? slider.centre : v)
        }
    }
    // One step per notch (120): a touchpad's small moves add up.
    property real wheelSum: 0
    WheelHandler {
        enabled: slider.wheel && slider.wheelStep > 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            slider.wheelSum += event.angleDelta.y
            const notches = Math.trunc(slider.wheelSum / 120)
            if (notches === 0) return
            slider.wheelSum -= notches * 120
            // At least one of its own steps per notch: ChatMix moves in 5s, so a
            // 1 or 2 % volume step alone would round back to where it was.
            const step = Math.max(slider.wheelStep, slider.stepSize)
            const raw = Math.max(slider.from, Math.min(slider.to, slider.value + notches * step))
            const v = Math.round(raw / slider.stepSize) * slider.stepSize
            slider.changing(v)
            slider.moved(v)
        }
    }
    Accessible.role: Accessible.Slider
}
