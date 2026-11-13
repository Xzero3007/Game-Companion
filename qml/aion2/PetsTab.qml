import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "mapkit.js" as MK

// The Map's PETS tab (Pet Finder: the Pet Soul Tracker's list; canvas page
// "Pet Finder in der Map", board PF1Pets, MN 2026-11-13): every pet's level
// (0 to 3) and the souls it still needs, the favourites (★) the map follows,
// and where each pet's souls drop. "Show on map" goes to the MAP tab with that
// monster's spawn points, and the map works out the way there (Kibelisk or
// walking), as for anything else it shows. The collection is the game's
// (`Aion2.pets`), the tables Pet Finder's (`MapPanel.petData`).
Column {
    id: tab
    /// The Map panel: its collection, favourites, world and settings.
    property var map: null
    spacing: 8

    readonly property var s: map ? map.settings : ({})
    readonly property bool synced: !!map && map.pets.synced > 0
    readonly property var allIds: map && map.petData.pets ? Object.keys(map.petData.pets) : []
    property string open: nativeWindow.demo.split(",").indexOf("petopen") >= 0 ? "1004" : ""
    property string query: ""

    // Metres to each pet's nearest spawn point on the map you are on.
    readonly property var nearest: {
        if (!map || !map.world || !map.world.me || !visible) return ({})
        const here = map.whereAmI()
        return here ? MK.M.nearestByPet(here.key, map.world.me) : ({})
    }

    readonly property int atMax: { let n = 0; for (const id of allIds) if (map.petLevel(id) >= 3) n++; return n }
    readonly property int toGo: { let n = 0; for (const id of allIds) n += map.petToGo(id); return n }

    readonly property var rows: {
        if (!map) return []
        const q = query.trim().toLowerCase()
        const out = []
        for (const id of allIds) {
            const p = map.petData.pets[id]
            const fav = map.isFav(id)
            const level = map.petLevel(id)
            const farmedAt = (map.pets.farmed || {})[id] || 0
            const farming = farmedAt > 0 && level < 3 && Date.now() - farmedAt < 30 * 60 * 1000
            if (q.length > 0) {
                const hit = p.name.toLowerCase().indexOf(q) >= 0 || (p.drops || []).some((d) => d.name.toLowerCase().indexOf(q) >= 0)
                if (!hit) continue
            } else {
                if (s.petShow === "favs" && !fav && !farming) continue
                if (s.petShow === "needed" && synced && level >= 3 && !fav) continue
            }
            if (s.petGenus && p.genus !== s.petGenus) continue
            out.push({ id: id, name: p.name, genus: p.genus, fav: fav, farming: farming, farmedAt: farmedAt, level: level,
                toGo: map.petToGo(id), metres: tab.nearest[id], drops: p.drops || [], chests: p.chests || [] })
        }
        const sort = s.petSort || "nearest"
        const far = (r) => r.metres == null ? Infinity : r.metres
        out.sort((a, b) => {
            // The pet being farmed, then favourites, first.
            const ra = (a.farming ? 2 : 0) + (a.fav ? 1 : 0), rb = (b.farming ? 2 : 0) + (b.fav ? 1 : 0)
            if (ra !== rb) return rb - ra
            if (sort === "nearest" && far(a) !== far(b)) return far(a) - far(b)
            if (sort === "left" && a.toGo !== b.toGo) return a.toGo - b.toGo
            if (sort === "level" && a.level !== b.level) return b.level - a.level
            return a.name.localeCompare(b.name)
        })
        return out
    }

    function genusColor(g) {
        return ({ cogni: "#b99bff", fera: "#ff9f66", natura: "#74d99a", varian: "#5cc9e6", special: "#f2c46b" })[g] || "#8d8996"
    }
    function genusName(g) { return map && map.petData.genus ? (map.petData.genus[g] || "") : "" }
    function ago(ms) {
        const m = Math.round((Date.now() - ms) / 60000)
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : Math.round(m / 60) + " h ago"
    }

    // How far along, in all.
    Item {
        width: parent.width
        height: 22
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: !tab.synced
                ? "Your pets' levels come at login: start this app before you log in."
                : tab.atMax + " / " + tab.allIds.length + " at level 3 · <b>" + tab.toGo.toLocaleString(Qt.locale("en_US"), "f", 0) + "</b> souls to go"
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
    Rectangle {
        visible: tab.synced
        width: parent.width
        height: 3
        color: "#2a2930"
        Rectangle { height: 3; width: tab.allIds.length ? parent.width * tab.atMax / tab.allIds.length : 0; color: Theme.accent }
    }

    // Which pets, sorted how, a search.
    Flow {
        width: parent.width
        spacing: 6
        z: 10
        Repeater {
            model: [["needed", "Not at 3"], ["favs", "★ Favourites"], ["all", "All"]]
            delegate: Chip {
                required property var modelData
                text: modelData[1]
                on: (tab.s.petShow || "needed") === modelData[0]
                onClicked: tab.map.change("petShow", modelData[0])
            }
        }
        Dropdown {
            width: 150
            height: 28
            label: "Genus"
            options: [{ id: "", name: "All" }].concat(["cogni", "fera", "natura", "varian", "special"].map((g) => ({ id: g, name: tab.genusName(g) || g })))
            current: tab.s.petGenus || ""
            onChosen: (id) => tab.map.change("petGenus", id)
        }
        Dropdown {
            width: 150
            height: 28
            label: "Sort"
            options: [{ id: "nearest", name: "Nearest" }, { id: "left", name: "Fewest left" }, { id: "level", name: "Level" }, { id: "name", name: "Name" }]
            current: tab.s.petSort || "nearest"
            onChosen: (id) => tab.map.change("petSort", id)
        }
    }
    Item {
        width: parent.width
        height: 30
        Rectangle {
            anchors.fill: parent
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: petSearch.activeFocus ? Theme.accent : "#3a3842" }
        }
        HudIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 13; lineWidth: 2; color: Theme.muted() }
        TextInput {
            id: petSearch
            anchors.fill: parent
            anchors.leftMargin: 30
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text()
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: Theme.body
            font.pixelSize: 13
            clip: true
            onTextChanged: tab.query = text
            Keys.onEscapePressed: { text = ""; focus = false }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: petSearch.text.length === 0
                text: "Search a pet or a monster …"
                color: Theme.dim()
                font: petSearch.font
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }
    }

    // The list.
    ListView {
        id: list
        width: parent.width
        height: Math.max(120, 420 + (tab.map ? tab.map.grow : 0))
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        cacheBuffer: 600
        model: tab.rows
        WheelScroll { flick: list; step: 98 }
        delegate: Item {
            id: row
            required property var modelData
            readonly property var r: modelData
            readonly property bool expanded: tab.open === r.id
            width: ListView.view.width
            height: 46 + (expanded ? detail.height : 0)
            Rectangle {
                anchors.fill: parent
                color: r.farming ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : rowMouse.containsMouse ? "#222128" : "#1b1a20"
            }
            MouseArea {
                id: rowMouse
                width: parent.width
                height: 46
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tab.open = row.expanded ? "" : r.id
            }
            // The portrait, its genus as the stripe beside it.
            Rectangle { width: 3; height: 46; color: tab.genusColor(r.genus) }
            Rectangle {
                x: 3
                width: 46
                height: 46
                color: "#2a2930"
                Image {
                    anchors.fill: parent
                    source: tab.map ? tab.map.dir.replace(/\/map$/, "") + "/pets/portraits/" + r.id + ".webp" : ""
                    sourceSize.width: 92
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
            }
            Column {
                x: 59
                y: 6
                width: parent.width - 59 - 236
                spacing: 2
                Row {
                    spacing: 6
                    Text {
                        width: Math.min(implicitWidth, row.width - 59 - 236 - (farmTag.visible ? farmTag.width + 6 : 0))
                        elide: Text.ElideRight
                        text: r.name
                        color: r.farming ? Theme.accent : Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Text {
                        id: farmTag
                        visible: r.farming
                        anchors.verticalCenter: parent.verticalCenter
                        text: "FARMING"
                        color: Theme.accent
                        font.family: Theme.display
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tab.genusName(r.genus) + (r.farmedAt > 0 && r.level < 3 ? " · soul " + tab.ago(r.farmedAt) : "")
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
            // Level: three steps.
            Row {
                x: parent.width - 236
                y: 19
                spacing: 3
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: 18
                        height: 8
                        color: tab.synced && r.level > index ? Theme.accent : "#2a2930"
                    }
                }
            }
            Text {
                x: parent.width - 166
                width: 60
                height: 46
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: !tab.synced ? "?" : r.level >= 3 ? "MAX" : String(r.toGo)
                color: r.level >= 3 && tab.synced ? Theme.dim() : Theme.text()
                font.family: Theme.display
                font.pixelSize: 14
                font.weight: Font.Bold
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Text {
                x: parent.width - 100
                width: 66
                height: 46
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: r.metres != null ? r.metres + " m" : "—"
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            // ★: a favourite the map follows.
            Item {
                x: parent.width - 30
                width: 30
                height: 46
                Text {
                    anchors.centerIn: parent
                    text: r.fav ? "★" : "☆"
                    color: r.fav ? Theme.accent : (starMouse.containsMouse ? Theme.text() : "#6e6a78")
                    font.pixelSize: 17
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                MouseArea { id: starMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.map.toggleFav(r.id) }
                Accessible.role: Accessible.Button
                Accessible.name: r.fav ? "Remove " + r.name + " from the favourites" : "Make " + r.name + " a favourite"
            }

            // Where its souls drop.
            Column {
                id: detail
                visible: row.expanded
                x: 59
                y: 46
                width: parent.width - 59 - 10
                spacing: 2
                bottomPadding: 10
                Rectangle { width: parent.width; height: 1; color: Theme.divider }
                Text {
                    topPadding: 4
                    text: r.drops.length ? "SOULS DROP FROM" : "No monster drops its souls."
                    color: Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Repeater {
                    model: row.expanded ? r.drops : []
                    delegate: Item {
                        required property var modelData
                        readonly property var d: modelData
                        width: detail.width
                        height: 28
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - showButton.width - 8
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: "<b>" + d.name + "</b>" + (d.level != null ? " <font color='" + Theme.dim() + "'>Lv " + d.level + "</font>" : "")
                                + "  " + (d.chance || "") + "  <font color='" + Theme.muted() + "'>" + [d.region, d.zone].filter((x) => !!x).join(" · ")
                                + (d.spawns ? " · " + d.spawns + " spawns" : "") + "</font>"
                            color: Theme.text()
                            font.family: Theme.body
                            font.pixelSize: 12
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Chip {
                            id: showButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Show on map"
                            onClicked: {
                                tab.map.change("tab", "map")
                                tab.map.setFocus({ type: "npc", ids: [String(d.npc)], label: d.name })
                            }
                        }
                    }
                }
                Text {
                    visible: r.chests.length > 0
                    width: detail.width
                    wrapMode: Text.WordWrap
                    text: "Also in: " + r.chests.map((c) => c.name + (c.chance ? " · " + c.chance + " per opening" : "") + (c.from.length ? " (" + c.from.join(", ") + ")" : "")).join("; ")
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }
    }

    // What it reads, and the pet being farmed.
    Item {
        width: parent.width
        height: 22
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - farmLine.width - 10
            elide: Text.ElideRight
            text: "Read from the game at login and with every soul; kept per server."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            id: farmLine
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !!tab.map && tab.map.farming !== null
            text: tab.map && tab.map.farming ? "FARMING: " + tab.map.farming.name.toUpperCase() + " " + tab.map.farming.souls + " / " + tab.map.farming.goal : ""
            color: Theme.muted()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Pet Finder: A2 Tools' Pet Soul Tracker (GPL-3.0) and PetTracker (GPLv3); portraits are the game's."
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 10
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
}
