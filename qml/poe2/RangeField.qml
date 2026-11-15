import QtQuick
import "../theme.js" as Theme

// A min or max for a stat line of the price check: typed (needs the
// overlay unlocked for keys) or turned with the mouse wheel (works locked
// too). Empty means no bound.
Rectangle {
    id: field
    property var value: null
    property string placeholder: "min"
    /// Values with decimals (attacks per second, regeneration …).
    property bool dp: false
    property bool dimmed: false
    signal edited(var value)
    objectName: "rangeField"
    width: 46
    height: 22
    color: "#1b1a20"
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }

    function shown(v) { return v === null || v === undefined || v === "" ? "" : String(Math.round(v * 100) / 100) }
    function step() {
        const v = typeof value === "number" ? Math.abs(value) : 0
        if (dp) return v >= 10 ? 1 : 0.1
        return v >= 200 ? 5 : 1
    }
    function send(text) {
        const t = String(text).trim().replace(",", ".")
        if (t === "") { field.edited(null); return }
        const n = Number(t)
        if (!isNaN(n)) field.edited(dp ? Math.round(n * 100) / 100 : Math.round(n))
        else input.text = shown(field.value)
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignRight
        text: field.shown(field.value)
        color: field.dimmed ? Theme.muted() : Theme.accent
        selectionColor: Theme.accent
        selectedTextColor: "#0c0c0f"
        font.family: Theme.display
        font.pixelSize: 13
        font.weight: Font.Bold
        maximumLength: 8
        clip: true
        validator: RegularExpressionValidator { regularExpression: /-?[0-9]*([.,][0-9]{0,2})?/ }
        onEditingFinished: if (text !== field.shown(field.value)) field.send(text)
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0 && !input.activeFocus
            text: field.placeholder
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 10
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
    // The wheel: up raises, down lowers; from empty it starts at the line's value.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const dir = event.angleDelta.y > 0 ? 1 : event.angleDelta.y < 0 ? -1 : 0
            if (dir === 0) return
            const base = typeof field.value === "number" ? field.value : (typeof field.start === "number" ? field.start : 0)
            const n = base + dir * field.step()
            field.edited(field.dp ? Math.round(n * 100) / 100 : Math.round(n))
        }
    }
    /// Where the wheel starts from an empty field (the line's own value).
    property var start: null
}
