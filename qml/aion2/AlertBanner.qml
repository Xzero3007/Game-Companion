import QtQuick
import ".."
import "../theme.js" as Theme
import "timekit.js" as TK

// The Schedule's alert over the game (design board T2): a slanted strip at
// the top centre with what starts and when; it goes after 20 seconds, or
// at a click. Its surface exists only while it shows.
Item {
    id: banner
    property var store
    property string name: ""
    property string where: ""
    property real start: 0
    property bool shown: false
    width: strip.width
    height: 34

    function show(n, w, s) {
        name = n
        where = w
        start = s
        shown = true
        hideTimer.restart()
    }
    Timer { id: hideTimer; interval: 20000; onTriggered: banner.shown = false }

    readonly property string head: {
        const left = Math.round((start - Date.now()) / 60000)
        return (name + (left > 0 ? " in " + left + " min" : " now")).toUpperCase()
    }

    Rectangle {
        id: strip
        width: row.implicitWidth + 40
        height: parent.height
        color: Theme.panel(0.92)
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10
            HudIcon { anchors.verticalCenter: parent.verticalCenter; name: "bell"; size: 13; color: Theme.accent }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: banner.head
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 1.5
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (banner.where ? banner.where + " · " : "") + (banner.store ? TK.clock(banner.store.region, banner.start) : "")
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: banner.shown = false }
    }
}
