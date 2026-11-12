import QtQuick
import "theme.js" as Theme

// A short list to choose from, opened by a button (a video's quality or
// opacity): the current entry in the accent.
Rectangle {
    id: picker
    /// [{id, name}]
    property var options: []
    property string current: ""
    property bool open: false
    /// Room it may take; longer lists scroll.
    property real maxHeight: 200
    signal chosen(string id)

    visible: open
    z: 30
    width: 112
    height: Math.min(column.implicitHeight + 2, maxHeight)
    color: "#16151b"
    border.color: Theme.divider

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            width: flick.width
            Repeater {
                model: picker.options
                delegate: Item {
                    required property var modelData
                    width: column.width
                    height: 28
                    readonly property bool chosenNow: modelData.id === picker.current
                    Rectangle {
                        anchors.fill: parent
                        color: optionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                    }
                    Rectangle {
                        visible: parent.chosenNow
                        width: 2
                        height: parent.height
                        color: Theme.accent
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: parent.chosenNow ? Theme.accent : Theme.textSoft()
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            picker.open = false
                            picker.chosen(modelData.id)
                        }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                }
            }
        }
    }
    WheelScroll { flick: flick }
}
