import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme

// The PoE 2 price check over the game (Exiled Exchange 2 rebuilt, MN
// 2026-11-15): opens when an item is copied in the game (Ctrl+C over it).
// The item in its rarity's colour, EE2's filters (item level, quality …)
// and stat lines to switch on and off, SEARCH, and the trade site's
// cheapest listings (or the currency exchange's rates for stackables).
// It takes clicks also while the overlay is locked; × closes it.
Panel {
    id: win
    panelId: "poe2-price"
    title: "Price check"
    tag: "PoE 2"
    width: 420
    minWidth: 340
    maxWidth: 700
    stretchy: true
    minGrow: -160
    maxGrow: 600
    pinnable: false
    badge: store && store.busy ? "ASKING…" : ""

    property var store: null
    readonly property var v: store ? store.view : null
    readonly property var r: store ? store.result : null
    property bool showHidden: false
    onVChanged: if (!v) showHidden = false

    // The game's rarity colours.
    function rarityColour(rarity) {
        switch (rarity) {
        case "Magic": return "#8888ff"
        case "Rare": return "#ffff77"
        case "Unique": return "#af6025"
        case "Gem": return "#1ba29b"
        case "Currency": return "#aa9e82"
        case "Divination Card": return "#c8c8c8"
        default: return "#c8c8c8"
        }
    }
    function currencyName(c) {
        const names = { exalted: "ex", divine: "div", chaos: "chaos", "no price": "no price" }
        return names[c] || c
    }
    // A stat's value as the game shows it (18.8 stays 18.8).
    function statAmount(n) { return String(Math.round(n * 100) / 100) }
    function amount(n) { return Math.abs(n) < 10 ? String(Math.round(n * 100) / 100) : String(Math.round(n)) }
    function statusColour(s) { return s === "online" ? Theme.accent : s === "afk" ? Theme.muted() : "#5b5862" }

    Column {
        width: parent.width
        spacing: 10

        // The item.
        Column {
            width: parent.width
            spacing: 2
            visible: win.v !== null
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: win.v ? win.v.name : ""
                color: win.rarityColour(win.v ? win.v.rarity : "")
                font.family: Theme.display
                font.pixelSize: 19
                font.weight: Font.Bold
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (!win.v) return ""
                    const parts = [win.v.rarity]
                    if (win.v.baseType) parts.push(win.v.baseType)
                    if (win.v.itemLevel) parts.push("Item level " + win.v.itemLevel)
                    if (win.v.corrupted) parts.push("Corrupted")
                    if (win.v.unidentified) parts.push("Unidentified")
                    return parts.join(" · ")
                }
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }

        Text {
            width: parent.width
            visible: text.length > 0
            wrapMode: Text.WordWrap
            text: win.store ? win.store.error : ""
            color: Theme.red
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            width: parent.width
            visible: !win.v && win.store && !win.store.busy && win.store.error.length === 0
            wrapMode: Text.WordWrap
            text: "Hover an item in Path of Exile 2 and press Ctrl+C: its price shows here."
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        // The league the trade site is asked for.
        Dropdown {
            width: parent.width
            visible: win.v !== null && win.store && win.store.leagues.length > 0
            label: "League"
            options: win.store ? win.store.leagues.map(function (l) { return { id: l.id, name: l.text } }) : []
            current: win.store ? win.store.league : ""
            onChosen: (id) => win.store.chooseLeague(id)
        }

        // The item filters.
        Flow {
            width: parent.width
            spacing: 6
            visible: win.v !== null
            Repeater {
                model: win.v ? win.v.filters : []
                delegate: Chip {
                    required property var modelData
                    text: modelData.label + (modelData.value !== null ? " " + modelData.value + (modelData.max !== null && modelData.max !== modelData.value ? "–" + modelData.max : "") : "")
                    on: !modelData.disabled
                    onClicked: win.store.toggleFilter(modelData.key)
                }
            }
        }

        // One list for the stats and the listings: scrolls with the wheel
        // and grows with the lower corner.
        Item {
            width: parent.width
            height: Math.max(80, Math.min(pageColumn.implicitHeight, 380 + win.grow))
            visible: win.v !== null
            WheelScroll { flick: page; step: 90 }
            Flickable {
                id: page
                anchors.fill: parent
                contentHeight: pageColumn.implicitHeight
                clip: true
                interactive: false
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: pageColumn
                    width: page.width
                    spacing: 0

                    Repeater {
                        model: win.v ? win.v.stats.filter(function (s) { return !s.hidden || win.showHidden }) : []
                        delegate: Item {
                            required property var modelData
                            width: pageColumn.width
                            height: Math.max(26, statText.implicitHeight + 8)
                            Rectangle { anchors.fill: parent; color: statMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent" }
                            Rectangle {
                                id: box
                                x: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12
                                color: modelData.disabled ? "transparent" : Theme.accent
                                border.color: modelData.disabled ? "#5b5862" : Theme.accent
                            }
                            Text {
                                id: statText
                                anchors.left: box.right
                                anchors.leftMargin: 9
                                anchors.right: valueText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.WordWrap
                                // EE2's stat texts leave out the game's "+" ("# to
                                // Accuracy Rating"): a positive flat "to" gets it back.
                                text: (modelData.value > 0 ? modelData.text.replace(/^#(%?) to /, "+#$1 to ") : modelData.text)
                                    .replace(/#/g, modelData.value !== null ? win.statAmount(modelData.value) : "#")
                                    + (modelData.hidden ? "  <font color=\"#8d8996\">(" + modelData.hidden + ")</font>" : "")
                                textFormat: Text.StyledText
                                color: modelData.disabled ? Theme.muted() : Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 12
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Text {
                                id: valueText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !modelData.disabled && modelData.min !== null
                                text: "≥ " + (modelData.min !== null ? win.statAmount(modelData.min) : "")
                                color: Theme.accent
                                font.family: Theme.display
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                            MouseArea { id: statMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.store.toggleStat(modelData.index) }
                        }
                    }

                    // The lines EE2 leaves out at first (counted elsewhere,
                    // always the same …), on request.
                    Item {
                        width: pageColumn.width
                        height: hiddenCount > 0 ? 28 : 0
                        visible: hiddenCount > 0
                        readonly property int hiddenCount: win.v ? win.v.stats.filter(function (s) { return !!s.hidden }).length : 0
                        Chip {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.showHidden ? "Fewer lines" : parent.hiddenCount + (parent.hiddenCount === 1 ? " more line" : " more lines")
                            on: win.showHidden
                            onClicked: win.showHidden = !win.showHidden
                        }
                    }

                    Item { width: 1; height: 10 }

                    // SEARCH and what came back.
                    Item {
                        width: pageColumn.width
                        height: 34
                        TextButton {
                            id: searchButton
                            anchors.left: parent.left
                            text: win.store && win.store.busy ? "Searching" : "Search"
                            onClicked: win.store.search()
                        }
                        Text {
                            anchors.left: searchButton.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: {
                                if (!win.r) return win.v && win.v.api === "bulk" ? "Currency exchange" : ""
                                if (win.r.kind === "bulk") return "Currency exchange" + (win.r.done ? "" : " …")
                                return win.r.listed.length + " shown · " + win.r.total + " listed" + (win.r.done ? "" : " …")
                            }
                            color: Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 11
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                    }

                    Item { width: 1; height: 8 }

                    // Listings: the price, how often, the seller's state, how old.
                    Repeater {
                        model: win.r && win.r.kind === "trade" ? win.r.listed : []
                        delegate: Item {
                            required property var modelData
                            width: pageColumn.width
                            height: 24
                            Rectangle { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: win.statusColour(modelData.status) }
                            Text {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92
                                text: win.amount(modelData.amount) + " " + win.currencyName(modelData.currency)
                                color: modelData.currency === "divine" ? Theme.accentLight : Theme.text()
                                font.family: Theme.display
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Text {
                                x: 110
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                text: modelData.times > 1 ? "×" + modelData.times : (modelData.stack > 1 ? modelData.stack + "×" : "")
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 11
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Text {
                                x: 148
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 148 - 84
                                elide: Text.ElideRight
                                text: modelData.account + (modelData.itemLevel ? " · ilvl " + modelData.itemLevel : "")
                                color: modelData.mine ? Theme.accent : Theme.textSoft()
                                font.family: Theme.body
                                font.pixelSize: 11
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.age
                                color: Theme.dim()
                                font.family: Theme.body
                                font.pixelSize: 11
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                        }
                    }

                    // The currency exchange: what one costs, per currency asked.
                    Repeater {
                        model: win.r && win.r.kind === "bulk" ? win.r.groups : []
                        delegate: Column {
                            id: group
                            required property var modelData
                            readonly property string have: modelData.have
                            width: pageColumn.width
                            spacing: 0
                            Text {
                                text: ("Paid in " + win.currencyName(modelData.have) + " · " + modelData.total + " offers").toUpperCase()
                                color: Theme.dim()
                                font.family: Theme.display
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                                topPadding: 6
                                bottomPadding: 4
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            Repeater {
                                model: modelData.listed
                                delegate: Item {
                                    required property var modelData
                                    width: pageColumn.width
                                    height: 24
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: win.statusColour(modelData.status) }
                                    Text {
                                        x: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: win.amount(modelData.rate) + " " + win.currencyName(group.have)
                                        color: Theme.text()
                                        font.family: Theme.display
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                    Text {
                                        x: 110
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 110 - 84
                                        elide: Text.ElideRight
                                        text: modelData.stock + " in stock · " + modelData.account
                                        color: modelData.mine ? Theme.accent : Theme.textSoft()
                                        font.family: Theme.body
                                        font.pixelSize: 11
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.age
                                        color: Theme.dim()
                                        font.family: Theme.body
                                        font.pixelSize: 11
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                                }
                            }
                        }
                    }
                }
            }
        }

    }
}
