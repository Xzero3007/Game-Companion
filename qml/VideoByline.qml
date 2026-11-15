import QtQuick
import "theme.js" as Theme

// Under a video's title: its channel (a click opens the channel's videos)
// and when the video came out; `tail` (in the accent) after them.
Item {
    id: byline
    property var video: null
    property string when: ""
    property string tail: ""
    property int pixelSize: 11
    signal openChannel()
    readonly property bool linked: !!video && !!video.channelId
    implicitHeight: name.implicitHeight

    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        id: name
        width: Math.min(implicitWidth, Math.max(0, byline.width - rest.implicitWidth))
        elide: Text.ElideRight
        text: byline.video ? byline.video.channel || "" : ""
        color: nameMouse.containsMouse ? Theme.text() : Theme.dim()
        font.family: Theme.body
        font.pixelSize: byline.pixelSize
        font.underline: nameMouse.containsMouse
        MouseArea {
            id: nameMouse
            anchors.fill: parent
            enabled: byline.linked
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: byline.openChannel()
        }
    }
    Row {
        id: rest
        anchors.left: name.right
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            text: (name.text && byline.when ? " · " : "") + byline.when + (byline.tail && (name.text || byline.when) ? " · " : "")
            color: Theme.dim()
            font: name.font
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            visible: byline.tail.length > 0
            text: byline.tail
            color: Theme.accent
            font.family: Theme.body
            font.pixelSize: byline.pixelSize
        }
    }
}
