import QtQuick
import "theme.js" as Theme

// The volume as one bar: − and + change it in steps, a click or drag on the
// bar sets it, the wheel over it steps too; the number beside it.
Item {
    id: vol
    /// In the player row: darkened as the user set it.
    property bool hud: false
    property int value: 0
    property int step: 5
    /// Narrower, for the player row.
    property bool compact: false
    /// What is heard after something else turned it down (ChatMix), 0 to
    /// 100; -1 for none. The bar past it is drawn faint.
    property int heard: -1
    signal stepped(int delta)
    signal picked(int value)

    implicitWidth: row.implicitWidth
    implicitHeight: 28

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        StepButton { icon: "minus"; tip: "Quieter"; onClicked: vol.stepped(-vol.step) }

        Item {
            width: vol.compact ? 64 : 110
            height: 28
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                color: "#3a3842"
                Rectangle {
                    width: parent.width * vol.value / 100
                    height: parent.height
                    color: Theme.accentFor(vol.hud)
                    opacity: vol.heard >= 0 && vol.heard < vol.value ? 0.3 : 1
                }
                Rectangle {
                    visible: vol.heard >= 0 && vol.heard < vol.value
                    width: parent.width * Math.max(0, vol.heard) / 100
                    height: parent.height
                    color: Theme.accentFor(vol.hud)
                }
            }
            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * vol.value / 100 - 1))
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 13
                color: Theme.text(vol.hud)
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function at(mx) { return Math.round(Math.max(0, Math.min(1, mx / width)) * 100) }
                onPressed: (mouse) => vol.picked(at(mouse.x))
                onPositionChanged: (mouse) => { if (pressed) vol.picked(at(mouse.x)) }
            }
            Accessible.role: Accessible.Slider
            Accessible.name: "Volume " + vol.value + (vol.heard >= 0 && vol.heard < vol.value ? ", heard " + vol.heard : "")
        }

        StepButton { icon: "plus"; tip: "Louder"; onClicked: vol.stepped(vol.step) }

        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            horizontalAlignment: Text.AlignRight
            text: vol.value
            color: Theme.muted(vol.hud)
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    // One step per notch (120), as the video window's wheel: a touchpad's
    // or a smooth wheel's small moves add up (MN, 2026-11-18: the strip
    // jumped by more than the player).
    property real wheelSum: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            vol.wheelSum += event.angleDelta.y
            const notches = Math.trunc(vol.wheelSum / 120)
            if (notches === 0) return
            vol.wheelSum -= notches * 120
            vol.stepped(notches * vol.step)
        }
    }

    component StepButton: Item {
        id: sb
        property string icon
        property string tip
        signal clicked
        width: 24
        height: 28
        HudIcon {
            anchors.centerIn: parent
            name: sb.icon
            size: 12
            lineWidth: 2.4
            color: sbMouse.containsMouse ? Theme.accentFor(vol.hud) : Theme.muted(vol.hud)
        }
        MouseArea {
            id: sbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: sb.tip
    }
}
