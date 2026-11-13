import QtQuick
import "theme.js" as Theme

// A list to choose from that opens over everything in its host (give it
// `parent: <the panel>` and `anchors.fill: parent`), under the button that
// opened it, or above when there is no room below. A click outside closes
// it.
Item {
    id: host
    visible: false
    z: 100
    property var options: []
    property string current: ""
    property var then: null

    function show(anchor, options, current, then) {
        host.options = options
        host.current = current
        host.then = then
        const p = anchor.mapToItem(host, 0, 0)
        const h = Math.min(options.length * 30 + 2, 242)
        box.width = Math.max(anchor.width, 160)
        box.height = h
        box.x = Math.max(0, Math.min(p.x, host.width - box.width))
        box.y = p.y + anchor.height + h <= host.height - 4 ? p.y + anchor.height : Math.max(0, p.y - h)
        host.visible = true
        flick.contentY = 0
    }
    function close() { host.visible = false; host.then = null }

    MouseArea {
        anchors.fill: parent
        onClicked: host.close()
        onWheel: (wheel) => wheel.accepted = true
    }
    Rectangle {
        id: box
        color: "#16151b"
        border.color: Theme.accent
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
                    model: host.options
                    delegate: Item {
                        required property var modelData
                        width: column.width
                        height: 30
                        readonly property bool chosenNow: modelData.id === host.current
                        Rectangle {
                            anchors.fill: parent
                            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        }
                        Rectangle {
                            visible: parent.chosenNow
                            width: 2
                            height: parent.height
                            color: Theme.accent
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: modelData.name
                            color: parent.chosenNow ? Theme.accent : Theme.textSoft()
                            font.family: Theme.body
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const then = host.then
                                host.close()
                                if (then) then(parent.modelData.id)
                            }
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name
                    }
                }
            }
        }
        WheelScroll { flick: flick; step: 90 }
    }
}
