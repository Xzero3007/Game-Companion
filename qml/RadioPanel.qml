import QtQuick
import GameCompanion
import "theme.js" as Theme

// The radio: search, country and genre, favourites / all / recent, the
// stations, and what plays with its volume. Closing it leaves the sound on.
Panel {
    id: panel
    panelId: "radio"
    title: "Radio"
    icon: "radio"
    width: 480
    stretchy: true
    minWidth: 400

    readonly property var cat: JSON.parse(Radio.catalog())
    readonly property var favs: JSON.parse(Radio.favourites)
    readonly property var recents: JSON.parse(Radio.recent)
    property string query: ""
    badge: cat.stations.length + " STATIONS"

    readonly property var countryOptions: [{ id: "", name: "All" }].concat(cat.countries)
    readonly property var genreOptions: {
        const here = []
        for (const s of cat.stations) {
            if (Radio.country.length > 0 && s.country !== Radio.country) continue
            for (const g of s.genres) if (here.indexOf(g) < 0) here.push(g)
        }
        return [{ id: "", name: "All" }].concat(cat.genres.filter((g) => here.indexOf(g.id) >= 0))
    }

    function fold(s) {
        return String(s || "").toLocaleLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ı/g, "i")
    }
    function byId(id) {
        for (const s of cat.stations) if (s.id === id) return s
        return null
    }
    function countryName(id) {
        for (const c of cat.countries) if (c.id === id) return c.name
        return id
    }
    function genreName(id) {
        for (const g of cat.genres) if (g.id === id) return g.name
        return id
    }
    // The stations the tab, filters and search show.
    readonly property var shown: {
        let list
        if (Radio.tab === "favourites") list = favs.map(byId).filter((s) => s)
        else if (Radio.tab === "recent") list = recents.map(byId).filter((s) => s)
        else list = cat.stations
        const q = fold(query).trim()
        return list.filter((s) => {
            if (Radio.country.length > 0 && s.country !== Radio.country) return false
            if (Radio.genre.length > 0 && s.genres.indexOf(Radio.genre) < 0) return false
            if (q.length > 0 && fold(s.name + " " + s.info + " " + s.genres.map(genreName).join(" ")).indexOf(q) < 0) return false
            return true
        })
    }
    function view(tab, country, genre) { Radio.setView(tab, country, genre) }

    Column {
        width: parent.width
        spacing: 8

        // Search
        Rectangle {
            width: parent.width
            height: 36
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: search.activeFocus ? Theme.accent : "#3a3842" }
            HudIcon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 15
                lineWidth: 2
                color: Theme.dim
            }
            TextInput {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Theme.body
                font.pixelSize: 13
                clip: true
                onTextChanged: panel.query = text
                Text {
                    visible: search.text.length === 0
                    text: "Search stations"
                    color: Theme.dim
                    font: search.font
                }
                Accessible.name: "Search stations"
            }
        }

        // Country and genre
        Row {
            width: parent.width
            spacing: 8
            z: 10
            Dropdown {
                width: (parent.width - 8) / 2
                label: "Country"
                options: panel.countryOptions
                current: Radio.country
                onChosen: (id) => panel.view(Radio.tab, id, "")
            }
            Dropdown {
                width: (parent.width - 8) / 2
                label: "Genre"
                options: panel.genreOptions
                current: Radio.genre
                onChosen: (id) => panel.view(Radio.tab, Radio.country, id)
            }
        }

        // Favourites / all / recent
        Item {
            width: parent.width
            height: 36
            Row {
                spacing: 18
                height: parent.height
                Tab { name: "favourites"; label: "Favorites · " + panel.favs.length }
                Tab { name: "all"; label: "All stations" }
                Tab { name: "recent"; label: "Recent" }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        }

        // The stations
        Item {
            x: -14
            width: parent.width + 28
            height: 46 * 6 + panel.grow
            clip: true
            ListView {
                id: stations
                anchors.fill: parent
                clip: true
                model: panel.shown
                boundsBehavior: Flickable.StopAtBounds
                delegate: StationRow {}
            }
            Text {
                anchors.centerIn: parent
                visible: panel.shown.length === 0
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Radio.tab === "favourites" && panel.favs.length === 0
                    ? "No favorites yet: the star beside a station adds it."
                    : Radio.tab === "recent" && panel.recents.length === 0 ? "Nothing played yet." : "No station here."
                color: Theme.dim
                font.family: Theme.body
                font.pixelSize: 12
            }
        }

        // Now playing
        Item {
            width: parent.width
            height: 48
            Rectangle {
                x: -14
                width: parent.width + 28
                height: parent.height
                color: Theme.headerTint
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            }
            IconButton {
                id: playButton
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                framed: true
                icon: panel.playingNow ? "pause" : "play"
                filled: !panel.playingNow
                color: Theme.accent
                tip: panel.playingNow ? "Pause" : "Play"
                onClicked: Radio.togglePause()
            }
            Column {
                anchors.left: playButton.right
                anchors.leftMargin: 12
                anchors.right: volume.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: Radio.status === "failed" ? "DOESN'T PLAY" : Radio.status === "connecting" ? "CONNECTING" : Radio.status === "buffering" ? "BUFFERING" : Radio.status === "paused" ? "PAUSED" : "NOW PLAYING"
                    color: Radio.status === "failed" ? Theme.red : Theme.dim
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Radio.status === "failed" ? Radio.name + " · " + Radio.why : (Radio.name.length > 0 ? Radio.name : "Pick a station")
                    color: Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
            VolumeBar {
                id: volume
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                value: Radio.volume
                onStepped: (d) => Radio.stepVolume(d)
                onPicked: (v) => Radio.setVolumeTo(v)
            }
        }
    }

    readonly property bool playingNow: ["connecting", "playing", "buffering"].indexOf(Radio.status) >= 0

    component Tab: Item {
        property string name
        property string label
        width: tabText.implicitWidth
        height: parent.height
        readonly property bool current: Radio.tab === name
        Text {
            id: tabText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text : Theme.muted)
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Rectangle {
            visible: parent.current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.accent
        }
        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.view(parent.name, Radio.country, Radio.genre)
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }

    component StationRow: Item {
        id: row
        required property var modelData
        required property int index
        width: ListView.view.width
        height: 46
        readonly property bool current: modelData.id === Radio.station && Radio.status !== "idle"
        readonly property bool fav: panel.favs.indexOf(modelData.id) >= 0

        Rectangle {
            anchors.fill: parent
            color: row.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
        }
        Rectangle { visible: row.current; width: 2; height: parent.height; color: Theme.accent }
        Rectangle { visible: !row.current; anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.current ? Radio.togglePause() : Radio.play(row.modelData.id)
        }

        Rectangle {
            id: square
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            color: "#2a2830"
            HudIcon {
                anchors.centerIn: parent
                size: 12
                lineWidth: 2.6
                name: row.current && panel.playingNow ? "pause" : "play"
                filled: !(row.current && panel.playingNow)
                color: row.current ? Theme.accent : Theme.textSoft
            }
        }
        Column {
            anchors.left: square.right
            anchors.leftMargin: 10
            anchors.right: star.left
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: row.modelData.name
                color: row.current ? Theme.accent : Theme.text
                font.family: Theme.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    const parts = []
                    if (row.current) parts.push(Radio.status === "playing" ? "Playing" : Radio.status === "failed" ? "Doesn't play" : Radio.status === "paused" ? "Paused" : "Connecting")
                    if (row.modelData.genres.length > 0) parts.push(panel.genreName(row.modelData.genres[0]))
                    parts.push(row.modelData.country)
                    if (row.modelData.info.length > 0) parts.push(row.modelData.info)
                    return parts.join(" · ")
                }
                color: row.current && Radio.status === "failed" ? Theme.red : Theme.muted
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        IconButton {
            id: star
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            icon: "star"
            iconSize: 16
            filled: row.fav
            color: row.fav ? Theme.accent : Theme.dim
            tip: row.fav ? "Remove from favorites" : "Add to favorites"
            onClicked: Radio.toggleFavourite(row.modelData.id)
        }
    }
}
