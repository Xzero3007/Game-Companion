import QtQuick
import "theme.js" as Theme

// A choice from a short list: the button shows the label and the choice;
// the list opens under it.
Item {
    id: dd
    property string label
    /// [{id, name}]; the first entry is "all" (id "").
    property var options: []
    property string current: ""
    signal chosen(string id)
    property bool open: false

    implicitHeight: 32
    z: open ? 20 : 0

    function nameOf(id) {
        for (const o of options) if (o.id === id) return o.name
        return "All"
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: dd.open ? Theme.accent : "#3a3842"
    }
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: dd.label.toUpperCase()
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: dd.nameOf(dd.current)
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
        }
    }
    HudIcon {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron"
        size: 12
        lineWidth: 2.2
        color: Theme.muted()
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dd.open = !dd.open
    }
    Accessible.role: Accessible.ComboBox
    Accessible.name: dd.label + ": " + dd.nameOf(dd.current)

    Rectangle {
        visible: dd.open
        y: dd.height + 2
        width: dd.width
        height: Math.min(list.contentHeight, 240)
        color: "#16151b"
        border.color: Theme.divider
        ListView {
            id: list
            anchors.fill: parent
            clip: true
            model: dd.options
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                required property var modelData
                width: list.width
                height: 30
                Rectangle {
                    anchors.fill: parent
                    color: optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                }
                Rectangle {
                    visible: modelData.id === dd.current
                    width: 2
                    height: parent.height
                    color: Theme.accent
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: modelData.id === dd.current ? Theme.accent : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                MouseArea {
                    id: optMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { dd.open = false; dd.chosen(modelData.id) }
                }
            }
        }
        WheelScroll { flick: list; step: 30 * 3 }
    }
}
