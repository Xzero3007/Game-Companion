import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme

// The big call over the game (Boss Callouts' widget; board K1): what to do
// now in big letters, the boss's line over it, a countdown bar while a cast
// bar or the boss's buff runs. Its own small surface, shown only while a call
// runs (nothing drawn in between). Dragged by its head while unlocked.
Item {
    id: call

    property var brain: null
    /// Shown as a test while placing it (VOICE → Test, ▶).
    readonly property var items: brain ? brain.callItems : []
    readonly property var p: brain ? brain.prefs : ({})
    readonly property bool wanted: items.length > 0 && p.widget !== false && p.enabled !== false

    readonly property bool contrast: p.colours === "contrast"
    readonly property int size: Math.max(32, Math.min(80, p.size || 56))
    width: Math.max(480, Math.min(900, size * 12))
    height: column.height + 28

    // Colours: as the game (purple and red as the boss glows, "Safe" white)
    // or high contrast (yellow on black).
    function tint(item) {
        if (contrast) return item.kind === "safe" ? "#7dff9a" : "#ffe14d"
        if (item.kind === "safe") return Theme.text()
        const t = (item.text + " " + item.sub).toLowerCase()
        if (t.indexOf("purple") >= 0 || t.indexOf("violet") >= 0 || t.indexOf("magic") >= 0) return Theme.purpleText
        if (t.indexOf("red") >= 0 || t.indexOf("burn") >= 0 || t.indexOf("physical") >= 0) return "#ff8a8e"
        return Theme.accentLight
    }

    // Countdowns move only while a call shows (the brain ticks then).
    property real now: Date.now()
    Timer { interval: 100; repeat: true; running: call.wanted && call.visible; onTriggered: call.now = Date.now() }

    // ---- its place, kept in the Boss choices ----
    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0) return
        x = p.callX >= 0 ? p.callX : (parent.width - width) / 2
        y = p.callY >= 0 ? p.callY : Math.round(parent.height * 0.2)
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - height))
        placed = true
    }
    Component.onCompleted: place()
    onParentChanged: place()

    Rectangle {
        anchors.fill: parent
        color: call.contrast ? Qt.rgba(0, 0, 0, Math.max(0.85, call.p.ground || 0.8)) : Theme.panel(call.p.ground === undefined ? 0.8 : call.p.ground)
    }
    MoveArea {
        anchors.fill: parent
        enabled: !Companion.locked
        target: call
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onReleased: { call.brain.change("callX", Math.round(call.x)); call.brain.change("callY", Math.round(call.y)) }
    }

    Column {
        id: column
        x: 24
        y: 14
        width: parent.width - 48
        spacing: 10
        Repeater {
            model: call.items.slice(0, 2)
            delegate: Column {
                required property var modelData
                required property int index
                width: column.width
                spacing: 6
                readonly property real scaleBy: index === 0 ? 1 : 0.55
                Text {
                    visible: text.length > 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.sub.toUpperCase()
                    color: call.contrast ? "#ffffff" : Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: Math.round(14 * parent.scaleBy + 2)
                    font.weight: Font.Bold
                    font.letterSpacing: 3
                    elide: Text.ElideRight
                    style: Text.Outline; styleColor: Theme.shadow
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.text.toUpperCase()
                    color: call.tint(modelData)
                    font.family: Theme.display
                    font.pixelSize: Math.round(call.size * parent.scaleBy)
                    font.weight: Font.Bold
                    lineHeight: 0.95
                    wrapMode: Text.WordWrap
                    style: Text.Outline; styleColor: Theme.shadow
                }
                // The countdown: the cast bar or the boss's buff.
                Row {
                    readonly property real remaining: Math.max(0, modelData.end - call.now)
                    visible: modelData.end > 0 && remaining > 0
                    width: parent.width
                    height: visible ? 26 * parent.scaleBy + 4 : 0
                    spacing: 12
                    Item {
                        width: parent.width - secs.width - 12
                        height: parent.height
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; color: Theme.trackDark }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * Math.min(1, parent.parent.remaining / Math.max(1, modelData.end - (modelData.start || (modelData.end - 10000))))
                            height: 6
                            color: call.tint(modelData)
                        }
                    }
                    Text {
                        id: secs
                        anchors.verticalCenter: parent.verticalCenter
                        text: (parent.remaining / 1000).toFixed(1) + " s"
                        color: call.contrast ? "#ffffff" : Theme.text()
                        font.family: Theme.display
                        font.pixelSize: Math.round(24 * parent.parent.scaleBy)
                        font.weight: Font.Bold
                        style: Text.Outline; styleColor: Theme.shadow
                    }
                }
            }
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: items.length ? items[0].text : ""
}
