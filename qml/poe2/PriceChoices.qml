import QtQuick
import ".."
import "../theme.js" as Theme

// A label with a row of chips, one of them chosen (the price check's settings).
Column {
        id: ch
        property string label
        property string hint: ""
        property var options: []
        property var current
        signal chosen(var value)
        
        spacing: 4
        Text {
            text: ch.label.toUpperCase()
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Flow {
            width: ch.width
            spacing: 6
            Repeater {
                model: ch.options
                delegate: Chip {
                    required property var modelData
                    text: modelData.name
                    on: modelData.id === ch.current
                    onClicked: ch.chosen(modelData.id)
                }
            }
        }
        Text {
            width: ch.width
            visible: ch.hint.length > 0
            wrapMode: Text.WordWrap
            text: ch.hint
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
