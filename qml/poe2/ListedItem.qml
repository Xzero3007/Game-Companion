import QtQuick
import ".."
import "../theme.js" as Theme

// One listed item as the trade site shows it (the kit's `item`: EE2's
// DisplayItem): its name in the rarity's colour, then block by block its
// values, requirements, enchants, runes, implicits and mods, each line in
// the trade site's colour with its tier on the right. Shown under a
// listing when it is clicked.
Rectangle {
    id: shown
    property var item: null
    /// A word under the name, e.g. "Corrupted".
    property string note: ""
    width: parent ? parent.width : 300
    height: body.height + 16
    color: Qt.rgba(1, 1, 1, 0.03)

    function rarityColour(r) {
        switch (r) {
        case "Magic": return "#8888ff"
        case "Rare": return "#ffff77"
        case "Unique": return "#af6025"
        case "Gem": return "#1ba29b"
        case "Currency": return "#aa9e82"
        default: return "#c8c8c8"
        }
    }
    // The trade site's colour per kind of line (EE2's number colours).
    function lineColour(c) {
        switch (c) {
        case "augmented": return "#8888ff"
        case "skill": return "#8888ff"
        case "enchant": return "#b8b8ff"
        case "unmet": return Theme.red
        case "fire": return "#d0392b"
        case "cold": return "#5b8fe0"
        case "lightning": return "#e8cf4a"
        case "chaos": return "#c0408a"
        case "unique": return "#af6025"
        case "fractured": return "#c9a66b"
        case "sanctified": return "#e0b070"
        case "desecrated": return "#6fbf73"
        case "mutated": return "#c75b7a"
        default: return Theme.textSoft()
        }
    }

    Column {
        id: body
        x: 10
        y: 8
        width: parent.width - 20
        spacing: 4
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: shown.item ? shown.item.title.join(" · ") : ""
            color: shown.rarityColour(shown.item ? shown.item.rarity : "")
            font.family: Theme.display
            font.pixelSize: 14
            font.weight: Font.Bold
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            visible: shown.note !== ""
            text: shown.note
            color: Theme.red
            font.family: Theme.body
            font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Repeater {
            model: shown.item ? shown.item.blocks : []
            delegate: Column {
                id: block
                required property var modelData
                required property int index
                width: body.width
                spacing: 2
                Rectangle { width: parent.width; height: 1; color: Theme.rowLine; visible: block.index > 0 }
                Item { width: 1; height: 1 }
                Repeater {
                    model: block.modelData.lines
                    delegate: Item {
                        id: row
                        required property var modelData
                        width: block.width
                        height: lineText.height
                        Text {
                            id: lineText
                            width: parent.width - (tierText.text !== "" ? tierText.width + 8 : 0)
                            wrapMode: Text.Wrap
                            text: row.modelData.text
                            color: shown.lineColour(row.modelData.colour)
                            font.family: Theme.body
                            font.pixelSize: 12
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Text {
                            id: tierText
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: row.modelData.tier
                            color: Theme.muted()
                            font.family: Theme.display
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                    }
                }
            }
        }
    }
}
