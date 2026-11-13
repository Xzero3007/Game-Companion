import QtQuick
import "theme.js" as Theme

// A choice shown like a field (the design's select): the chosen entry's
// name and a chevron; a click opens `choices` (a ChoiceList) under it.
Rectangle {
    id: select
    /// [{id, name}]
    property var options: []
    property string current: ""
    /// The ChoiceList that shows the options.
    property var choices: null
    /// Shown with a gold line (a change not saved yet).
    property bool changed: false
    property string placeholder: "Choose"
    property string accessibleName: placeholder
    signal chosen(string id)

    implicitHeight: 36
    color: "#1b1a20"
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: select.changed || selectMouse.containsMouse ? Theme.accent : "#3a3842"
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: chevron.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: {
            for (const o of select.options) if (o.id === select.current) return o.name
            return select.current.length > 0 ? select.current : select.placeholder
        }
        color: select.enabled ? Theme.text() : Theme.dim()
        font.family: Theme.body
        font.pixelSize: 13
    }
    HudIcon {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron"
        size: 14
        lineWidth: 2
        color: Theme.muted()
    }
    MouseArea {
        id: selectMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (select.choices) select.choices.show(select, select.options, select.current, (id) => select.chosen(id))
    }
    Accessible.role: Accessible.ComboBox
    Accessible.name: accessibleName
}
