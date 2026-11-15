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
    /// The item's own mods are listed (advanced copy): ranges sit in the text.
    readonly property bool modsShown: v !== null && (v.mods || []).length > 0
    property bool showSettings: false
    onVChanged: if (!v) showHidden = false
    readonly property bool tiersShown: store && store.showTiers && v !== null && ((v.mods || []).some(function (m) { return m.tier !== null }) || v.stats.some(function (s) { return s.tier !== null || s.low !== null }))

    // The stat lines in the game's order, in groups with their headers.
    readonly property var groups: {
        if (!v) return []
        const order = [
            { key: "properties", title: "VALUES" },
            { key: "fixed", title: "IMPLICIT · ENCHANT · RUNES" },
            { key: "prefix", title: "PREFIXES" },
            { key: "suffix", title: "SUFFIXES" },
            { key: "lines", title: v.rarity === "Unique" ? "MODS" : "LINES" },
            { key: "totals", title: "TOTALS" }
        ]
        const out = []
        // With the advanced copy the item's own mods make the fixed lines,
        // prefixes and suffixes (each with the stat line that searches for it).
        const mods = v.mods || []
        const linked = {}
        // Index loops: no array iterators in Qt's JavaScript (0.8.43 crashed in one).
        for (let k = 0; k < mods.length; k++) if (mods[k].filter !== null) linked[mods[k].filter] = true
        for (let n = 0; n < order.length; n++) {
            const g = order[n]
            let list = []
            let count = 0
            if (mods.length > 0 && (g.key === "fixed" || g.key === "prefix" || g.key === "suffix")) {
                const own = mods.filter(function (m) { return m.group === g.key })
                count = own.length
                list = own.map(function (m) { return { mod: m, stat: m.filter !== null ? v.stats[m.filter] : null } })
            } else {
                const all = v.stats.filter(function (s) {
                    if (linked[s.index]) return false
                    if (mods.length > 0 && g.key === "lines") return s.group === "lines" || s.group === "fixed" || s.group === "prefix" || s.group === "suffix"
                    return s.group === g.key
                })
                count = all.length
                list = all.filter(function (s) { return !s.hidden || showHidden }).map(function (s) { return { mod: null, stat: s } })
            }
            if (list.length === 0) continue
            const counted = g.key === "prefix" || g.key === "suffix"
            out.push({ key: g.key, title: g.title + (counted ? "  " + count : ""), stats: list, first: out.length === 0 })
        }
        return out
    }
    // A mod's lines as the game's advanced copy writes them: the rolled
    // value, the tier's range dim in brackets.
    function modText(m) {
        return m.lines.map(function (l) {
            return l.parts.map(function (p) {
                const t = String(p.t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                return p.range ? "<font color=\"#8d8996\">(" + t + ")</font>" : t
            }).join("")
        }).join("<br>")
    }
    // A line as the game writes it: EE2's text with the value put in; a
    // positive flat "to" gets back the game's "+" ("# to Accuracy Rating").
    function lineText(s) {
        const t = s.value > 0 ? s.text.replace(/^#(%?) to /, "+#$1 to ") : s.text
        return t.replace(/#/g, s.value !== null ? statAmount(s.value) : "#")
    }
    // Whether the wheel at (x, y) of the list is over a min/max field.
    function overField(item, x, y) {
        let it = item
        let px = x, py = y
        for (let depth = 0; it && depth < 12; depth++) {
            const c = it.childAt(px, py)
            if (!c) return false
            if (c.objectName === "rangeField") return c.visible
            const p = it.mapToItem(c, px, py)
            px = p.x; py = p.y
            it = c
        }
        return false
    }

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
        // Why a Ctrl+C in the game would not be heard (shown, not guessed).
        Text {
            width: parent.width
            visible: text.length > 0
            wrapMode: Text.WordWrap
            text: {
                if (!win.store) return ""
                if (Poe2.watchError.length > 0) return "Copies can't be read: " + Poe2.watchError
                if (!win.store.on && !win.v) return "Copies are read only while Path of Exile 2 runs and Game Companion sees it (the game row shows PATH OF EXILE 2)."
                return ""
            }
            color: Poe2.watchError.length > 0 ? Theme.red : Theme.muted()
            font.family: Theme.body
            font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        // The league the trade site is asked for.
        // The league, and the settings (⚙).
        Item {
            width: parent.width
            height: Math.max(leagueBox.height, 30)
            visible: win.store !== null
            Dropdown {
                id: leagueBox
                anchors.left: parent.left
                anchors.right: gear.left
                anchors.rightMargin: 8
                visible: win.store && win.store.leagues.length > 0
                label: "League"
                options: win.store ? win.store.leagues.map(function (l) { return { id: l.id, name: l.text } }) : []
                current: win.store ? win.store.league : ""
                onChosen: (id) => win.store.chooseLeague(id)
            }
            IconButton {
                id: gear
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                icon: "settings"
                framed: true
                color: win.showSettings ? Theme.accent : Theme.text()
                tip: win.showSettings ? "Back to the item" : "Price check settings"
                onClicked: win.showSettings = !win.showSettings
            }
        }

        // The item filters, then what kind of listings and which currency.
        Flow {
            width: parent.width
            spacing: 6
            visible: win.v !== null && !win.showSettings
            Chip {
                visible: win.v !== null && win.v.api !== "bulk"
                readonly property var kinds: ({ securable: "Instant buyout", available: "In person", any: "Any listing", online: "Online" })
                text: win.v ? (kinds[win.v.listingType] || win.v.listingType) : ""
                on: true
                onClicked: win.store.setTrade("listingType", win.v.listingType === "securable" ? "available" : win.v.listingType === "available" ? "any" : "securable")
            }
            Chip {
                visible: win.v !== null && win.v.api !== "bulk"
                text: win.v && win.v.currency ? "In " + win.v.currency : "Any currency"
                on: win.v !== null && win.v.currency !== ""
                onClicked: {
                    const next = { "": "exalted", exalted: "divine", divine: "chaos", chaos: "" }
                    win.store.setTrade("currency", next[win.v.currency] !== undefined ? next[win.v.currency] : "")
                }
            }
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
            WheelScroll {
                flick: page
                step: 90
                passAt: function (x, y) { const p = mapToItem(page.contentItem, x, y); return win.overField(page.contentItem, p.x, p.y) }
            }
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

                    // The settings (⚙ in the window), in place of the item.
                    PriceSettings {
                        width: pageColumn.width
                        visible: win.showSettings
                        store: win.store
                    }

                    // The lines as the game's tooltip orders them: the
                    // weapon's or armour's values, fixed lines (implicit,
                    // enchant, runes), prefixes, suffixes, then EE2's totals.
                    // Without the advanced copy explicit lines are one group.
                    Repeater {
                        model: win.showSettings ? [] : win.groups
                        delegate: Column {
                            id: groupBox
                            required property var modelData
                            width: pageColumn.width
                            spacing: 0
                            Item {
                                width: parent.width
                                height: 26
                                Text {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    text: groupBox.modelData.title
                                    color: groupBox.modelData.key === "prefix" || groupBox.modelData.key === "suffix" ? Theme.textSoft() : Theme.dim()
                                    font.family: Theme.display
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    style: Theme.textStyle(); styleColor: Theme.shadow
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    visible: groupBox.modelData.first
                                    text: "MIN      MAX" + (win.tiersShown ? (win.modsShown ? "      TIER" : "                 RANGE  TIER") : "")
                                    color: Theme.dim()
                                    font.family: Theme.display
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    style: Theme.textStyle(); styleColor: Theme.shadow
                                }
                            }
                            Repeater {
                                model: groupBox.modelData.stats
                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    // The stat line (searchable), and the item's mod it stands for.
                                    readonly property var st: modelData.stat
                                    readonly property var md: modelData.mod
                                    readonly property bool off: !st || st.disabled
                                    width: groupBox.width
                                    height: Math.max(30, statText.implicitHeight + 10)
                                    readonly property bool hasRange: !!st && (st.value !== null && st.group !== "totals" || st.min !== null)
                                    Rectangle { anchors.fill: parent; color: statMouse.containsMouse && row.st ? Qt.rgba(1, 1, 1, 0.04) : "transparent" }
                                    MouseArea { id: statMouse; anchors.fill: parent; hoverEnabled: true; enabled: !!row.st; cursorShape: Qt.PointingHandCursor; onClicked: win.store.toggleStat(row.st.index) }
                                    Rectangle {
                                        id: box
                                        x: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12
                                        visible: !!row.st
                                        color: row.off ? "transparent" : Theme.accent
                                        border.color: row.off ? "#5b5862" : Theme.accent
                                    }
                                    Text {
                                        id: statText
                                        anchors.left: box.right
                                        anchors.leftMargin: 9
                                        anchors.right: fields.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        wrapMode: Text.WordWrap
                                        text: row.md
                                            ? win.modText(row.md) + (row.md.folded ? "  <font color=\"#8d8996\">(" + (row.md.folded === "totals" ? "in the totals" : "in the item's values") + ")</font>" : "")
                                            : win.lineText(row.st) + (row.st.hidden ? "  <font color=\"#8d8996\">(" + row.st.hidden + ")</font>" : "")
                                        textFormat: Text.StyledText
                                        color: row.off ? Theme.muted() : Theme.text()
                                        font.family: Theme.body
                                        font.pixelSize: 12
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                    Row {
                                        id: fields
                                        anchors.right: tierBox.left
                                        anchors.rightMargin: win.tiersShown ? 10 : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        RangeField {
                                            visible: row.hasRange
                                            placeholder: "min"
                                            value: row.st ? row.st.min : null
                                            start: row.st ? row.st.value : null
                                            dp: !!row.st && row.st.dp
                                            dimmed: row.off
                                            onEdited: (n) => win.store.setRange(row.st.index, n, undefined)
                                        }
                                        RangeField {
                                            visible: row.hasRange
                                            placeholder: "max"
                                            value: row.st ? row.st.max : null
                                            start: row.st ? row.st.value : null
                                            dp: !!row.st && row.st.dp
                                            dimmed: row.off
                                            onEdited: (n) => win.store.setRange(row.st.index, undefined, n)
                                        }
                                    }
                                    // Its tier and that tier's range (from the advanced copy).
                                    Item {
                                        id: tierBox
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: win.tiersShown ? (win.modsShown ? 30 : 78) : 0
                                        height: 20
                                        visible: win.tiersShown
                                        Row {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            Text {
                                                anchors.baseline: tierText.baseline
                                                visible: !row.md && !!row.st && row.st.low !== null
                                                text: visible ? win.statAmount(row.st.low) + "–" + win.statAmount(row.st.high) : ""
                                                color: Theme.dim()
                                                font.family: Theme.body
                                                font.pixelSize: 10
                                                style: Theme.textStyle(); styleColor: Theme.shadow
                                            }
                                            Text {
                                                id: tierText
                                                width: 22
                                                horizontalAlignment: Text.AlignRight
                                                readonly property var tier: row.md ? row.md.tier : row.st ? row.st.tier : null
                                                text: tier !== null && tier !== undefined ? "T" + tier : ""
                                                color: tier === 1 ? Theme.accent : Theme.textSoft()
                                                font.family: Theme.display
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                style: Theme.textStyle(); styleColor: Theme.shadow
                                            }
                                        }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                                }
                            }
                        }
                    }

                    // The lines EE2 leaves out at first (counted elsewhere,
                    // always the same …), on request.
                    Item {
                        width: pageColumn.width
                        height: hiddenCount > 0 && !win.showSettings ? 32 : 0
                        visible: hiddenCount > 0 && !win.showSettings
                        readonly property int hiddenCount: win.v ? win.v.stats.filter(function (s) { return !!s.hidden }).length : 0
                        Chip {
                            anchors.bottom: parent.bottom
                            text: win.showHidden ? "Fewer lines" : parent.hiddenCount + (parent.hiddenCount === 1 ? " more line" : " more lines")
                            on: win.showHidden
                            onClicked: win.showHidden = !win.showHidden
                        }
                    }
                    Text {
                        width: pageColumn.width
                        visible: win.v !== null && !win.v.advanced && !win.showSettings
                        topPadding: 8
                        wrapMode: Text.WordWrap
                        text: "For prefixes, suffixes and tiers hold Alt (the game's advanced mod key) while pressing Ctrl+C."
                        color: Theme.dim()
                        font.family: Theme.body
                        font.pixelSize: 11
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }

                    Item { width: 1; height: 10 }

                    // SEARCH and what came back.
                    Item {
                        width: pageColumn.width
                        height: win.showSettings ? 0 : 34
                        visible: !win.showSettings
                        TextButton {
                            id: searchButton
                            anchors.left: parent.left
                            text: win.store && win.store.busy ? "Searching" : "Search"
                            onClicked: win.store.search()
                        }
                        // The same search on the trade site, in the browser (only on a click).
                        TextButton {
                            id: siteButton
                            anchors.left: searchButton.right
                            anchors.leftMargin: 6
                            text: "Trade site ↗"
                            onClicked: win.store.openTrade()
                        }
                        Text {
                            anchors.left: siteButton.right
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
                        model: win.r && win.r.kind === "trade" && !win.showSettings ? win.r.listed : []
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
                        model: win.r && win.r.kind === "bulk" && !win.showSettings ? win.r.groups : []
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
