import QtQuick
import GameCompanion
import "theme.js" as Theme

// The game library (design G4Library / G4AddGame): Steam, Lutris and Heroic
// read from this PC, plus own entries. PLAY starts a game through its
// launcher; the companion notices it running (Games.running). The form
// adds an own game, or sets a library game's preset search and what
// happens when it starts.
Panel {
    id: panel
    panelId: "games"
    title: "Games"
    icon: "games"
    width: 860
    minWidth: 620
    maxWidth: 1200
    stretchy: true

    readonly property var library: JSON.parse(Games.library)
    readonly property var visibleGames: library.filter((g) => !g.hidden)
    badge: visibleGames.length + (visibleGames.length === 1 ? " GAME" : " GAMES")

    /// recent, favorites, module, steam, lutris, heroic, own
    property string tab: "recent"
    property string query: ""
    /// The form: null (the list), {} (a new own game) or the game to edit.
    property var editing: null

    function count(launcher) { return visibleGames.filter((g) => g.launcher === launcher).length }
    function fold(s) { return String(s || "").toLocaleLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }

    readonly property var shown: {
        let list = visibleGames.slice()
        if (tab === "favorites") list = list.filter((g) => g.fav)
        else if (tab === "module") list = list.filter((g) => g.known.length > 0)
        else if (tab !== "recent") list = list.filter((g) => g.launcher === tab)
        const q = fold(query).trim()
        if (q.length > 0) list = list.filter((g) => fold(g.name).indexOf(q) >= 0)
        if (tab === "recent") {
            // Played ones first, newest first; the rest by name.
            list.sort((a, b) => (b.lastPlayed - a.lastPlayed) || a.name.localeCompare(b.name))
        } else {
            list.sort((a, b) => a.name.localeCompare(b.name))
        }
        return list
    }

    function ago(seconds) {
        if (!seconds) return "never"
        const d = Date.now() / 1000 - seconds
        if (d < 3600 * 20) return "today"
        const days = Math.floor(d / 86400)
        if (days <= 1) return "yesterday"
        if (days < 7) return days + " days ago"
        if (days < 14) return "last week"
        if (days < 31) return Math.floor(days / 7) + " weeks ago"
        if (days < 62) return "last month"
        return Math.floor(days / 30) + " months ago"
    }
    function launcherName(l) {
        return l === "steam" ? "Steam" : l === "lutris" ? "Lutris" : l === "heroic" ? "Heroic" : "Own"
    }

    Component.onCompleted: Games.refresh()

    Column {
        width: parent.width
        spacing: 0
        visible: panel.editing === null

        // Search, add, read again
        Item {
            width: parent.width
            height: 44
            Rectangle {
                id: searchBox
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(300, parent.width - addButton.width - refreshButton.width - 40)
                height: 32
                color: "#1b1a20"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: search.activeFocus ? Theme.accent : "#3a3842" }
                HudIcon {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    lineWidth: 2
                    color: Theme.dim()
                }
                TextInput {
                    id: search
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text()
                    selectionColor: Theme.accent
                    selectedTextColor: "#0c0c0f"
                    font.family: Theme.body
                    font.pixelSize: 13
                    clip: true
                    onTextChanged: panel.query = text
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        visible: search.text.length === 0
                        text: "Search games"
                        color: Theme.dim()
                        font: search.font
                    }
                    Accessible.name: "Search games"
                }
            }
            IconButton {
                id: refreshButton
                anchors.right: addButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                icon: "refresh"
                tip: Games.scanning ? "Reading the launchers…" : "Read the launchers again"
                color: Games.scanning ? Theme.accent : Theme.muted()
                onClicked: Games.refresh()
            }
            TextButton {
                id: addButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 32
                text: "+ Add game"
                onClicked: panel.editing = {}
            }
        }

        // Tabs
        Item {
            width: parent.width
            height: 36
            Row {
                spacing: 18
                height: parent.height
                Tab { name: "recent"; label: "Recent" }
                Tab { name: "favorites"; label: "Favorites" }
                Tab { name: "module"; label: "With module"; purple: true }
                Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
                Tab { name: "steam"; label: "Steam · " + panel.count("steam") }
                Tab { name: "lutris"; label: "Lutris · " + panel.count("lutris") }
                Tab { name: "heroic"; label: "Heroic · " + panel.count("heroic") }
                Tab { name: "own"; label: "Own · " + panel.count("own") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        }

        Item { width: 1; height: 14 }

        // The games
        Item {
            id: gridBox
            width: parent.width
            height: 2 * 152 + panel.grow
            clip: true
            readonly property int columns: Math.max(2, Math.round(width / 210))
            GridView {
                id: grid
                anchors.fill: parent
                clip: true
                cellWidth: width / gridBox.columns
                cellHeight: 152
                model: panel.shown
                boundsBehavior: Flickable.StopAtBounds
                delegate: Card {}
            }
            WheelScroll { flick: grid; step: 152 }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.centerIn: parent
                visible: panel.shown.length === 0
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Games.scanning ? "Reading Steam, Lutris and Heroic…"
                    : panel.query.length > 0 ? "No game matches."
                    : panel.tab === "favorites" ? "No favorites yet: the star on a game adds it."
                    : panel.tab === "module" ? "No game with a module here yet: AION 2 and Path of Exile 2 have one."
                    : panel.tab === "own" ? "No own games yet: + ADD GAME adds one."
                    : panel.tab === "recent" ? "No games found. + ADD GAME adds one by hand."
                    : "No game from " + panel.launcherName(panel.tab) + " on this PC."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
            }
        }

        // Footer
        Item {
            width: parent.width
            height: 40
            Rectangle { x: -14; width: parent.width + 28; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "Read from Steam, Lutris and Heroic on this PC. PLAY starts the game through its launcher, the companion follows."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
    }

    // Add an own game, or edit a game's preset search and start options.
    Loader {
        width: parent.width
        active: panel.editing !== null
        visible: active
        sourceComponent: GameForm {}
    }

    component Tab: Item {
        property string name
        property string label
        property bool purple: false
        width: tabRow.implicitWidth
        height: parent.height
        readonly property bool current: panel.tab === name
        Row {
            id: tabRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                visible: parent.parent.purple
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                color: Theme.purple
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                text: parent.parent.label.toUpperCase()
                color: parent.parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
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
            onClicked: panel.tab = parent.name
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }

    component Card: Item {
        id: card
        required property var modelData
        readonly property var g: modelData
        readonly property bool running: Games.running === g.id
        readonly property bool module: g.known.length > 0
        width: GridView.view.cellWidth
        height: GridView.view.cellHeight

        Rectangle {
            id: face
            anchors.fill: parent
            anchors.rightMargin: 14
            anchors.bottomMargin: 14
            color: card.running ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10)
                : faceHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
            Rectangle {
                width: parent.width
                height: 2
                z: 2
                color: card.running ? Theme.accent : card.module ? Theme.purple : "transparent"
            }
            HoverHandler { id: faceHover }
            MouseArea {
                id: cardMouse
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: panel.editing = card.g
            }

            // Cover: the launcher's own picture on disk, else the name.
            Rectangle {
                id: cover
                width: parent.width
                height: 92
                color: "#24232b"
                clip: true
                Image {
                    id: picture
                    anchors.fill: parent
                    source: card.g.picture
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 320
                    visible: status === Image.Ready
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: picture.status !== Image.Ready
                    anchors.centerIn: parent
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: card.g.name.toUpperCase()
                    color: "#4f4c58"
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }
                Rectangle {
                    visible: card.module
                    x: 6
                    y: 6
                    width: moduleText.implicitWidth + 12
                    height: moduleText.implicitHeight + 2
                    color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.55)
                    Text {
                        id: moduleText
                        anchors.centerIn: parent
                        text: "MODULE"
                        color: "#e6dbfa"
                        font.family: Theme.display
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 26
                    height: 26
                    visible: card.g.fav || faceHover.hovered
                    icon: "star"
                    filled: card.g.fav
                    color: card.g.fav ? Theme.accent : Theme.textSoft()
                    tip: card.g.fav ? "Remove from favorites" : "Add to favorites"
                    onClicked: Games.favorite(card.g.id, !card.g.fav)
                }
            }

            Item {
                anchors.top: cover.bottom
                width: parent.width
                height: parent.height - cover.height
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: play.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.g.name
                        color: Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.running ? panel.launcherName(card.g.launcher) + " · running"
                            : panel.launcherName(card.g.launcher) + " · " + panel.ago(card.g.lastPlayed)
                        color: card.running ? Theme.accent : Theme.dim()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                }
                IconButton {
                    id: edit
                    anchors.right: play.left
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    visible: faceHover.hovered
                    icon: "edit"
                    color: Theme.muted()
                    tip: card.g.own ? "Edit this game" : "Preset search and start options"
                    onClicked: panel.editing = card.g
                }
                Rectangle {
                    id: play
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: playText.implicitWidth + 20
                    height: 28
                    color: card.running ? Theme.accent : playMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                    border.color: Theme.accent
                    Text {
                        id: playText
                        anchors.centerIn: parent
                        text: card.running ? "RUNNING" : "PLAY"
                        color: card.running ? "#121116" : Theme.accent
                        style: card.running ? Text.Normal : Theme.textStyle()
                        styleColor: Theme.shadow
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !card.running
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Games.launch(card.g.id)
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Play " + card.g.name
                }
            }
        }
    }

    component GameForm: Column {
        id: form
        readonly property var g: panel.editing || ({})
        readonly property bool isNew: g.id === undefined
        readonly property bool own: isNew || g.own === true
        spacing: 14
        topPadding: 6
        bottomPadding: 4

        Component.onCompleted: {
            nameField.text = g.name || ""
            commandField.text = g.command || ""
            processField.text = (g.processes || []).join(", ")
            twitchField.text = g.twitch || ""
            youtubeField.text = g.youtube || ""
            showBox.checked = g.showOnStart === undefined ? true : g.showOnStart
            radioBox.checked = g.radioOnStart === true
        }

        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: form.isNew ? "ADD GAME" : form.own ? "EDIT GAME" : g.name.toUpperCase()
            color: Theme.text()
            font.family: Theme.display
            font.pixelSize: 16
            font.weight: Font.Bold
            font.letterSpacing: 2
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: !form.own
            width: parent.width
            wrapMode: Text.WordWrap
            text: "From " + panel.launcherName(g.launcher) + ". Its name and how it starts come from there; here you set what the companion does with it."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 12
        }

        Labeled {
            visible: form.own
            label: "Name"
            Field { id: nameField; width: parent.width; placeholder: "Game name" }
        }
        Labeled {
            visible: form.own
            label: "Start with"
            Field { id: commandField; width: parent.width; placeholder: "Program, script or launcher command" }
        }
        Labeled {
            visible: form.own
            label: "Process name"
            hint: "So the companion knows when the game runs, also when you start it elsewhere. Several: separate with commas."
            Field { id: processField; width: parent.width; placeholder: "e.g. Game.exe" }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: "PRESET SEARCH"
            color: Theme.text()
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Row {
            width: parent.width
            spacing: 10
            Labeled {
                width: (parent.width - 10) / 2
                label: "Twitch category"
                small: true
                Field { id: twitchField; width: parent.width; placeholder: "As Twitch names it" }
            }
            Labeled {
                width: (parent.width - 10) / 2
                label: "YouTube search"
                small: true
                Field { id: youtubeField; width: parent.width; placeholder: "Search words" }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: "WHEN IT STARTS"
            color: Theme.text()
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Check { id: showBox; text: "Show the companion over the game" }
        Check { id: radioBox; text: "Start the radio with my last station" }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: "LOAD LAYOUT"
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Flow {
            id: layoutChoice
            width: parent.width
            spacing: 8
            property string picked: form.g.layout || ""
            readonly property var names: JSON.parse(Companion.layouts)
            Repeater {
                model: [""].concat(layoutChoice.names)
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: layoutChoice.picked === modelData
                    width: chipText.implicitWidth + 20
                    height: 28
                    color: chipMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                    border.color: on ? Theme.accent : Theme.track
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.length > 0 ? modelData : "None"
                        color: parent.on ? Theme.accent : Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: layoutChoice.picked = parent.modelData
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: "Layout " + chipText.text
                    Accessible.checked: on
                }
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: layoutChoice.names.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Save a layout in Settings → Layouts to have the game load it."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }

        Item {
            width: parent.width
            height: 40
            Rectangle { x: -14; width: parent.width + 28; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            TextButton {
                visible: !form.isNew && form.own
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                danger: true
                text: "Remove"
                onClicked: { Games.removeOwn(form.g.id); panel.editing = null }
            }
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 10
                TextButton { text: "Cancel"; onClicked: panel.editing = null }
                Rectangle {
                    width: saveText.implicitWidth + 32
                    height: 34
                    readonly property bool ready: !form.own || (nameField.text.trim().length > 0 && commandField.text.trim().length > 0)
                    color: ready ? (saveMouse.containsMouse ? Theme.accentLight : Theme.accent) : "transparent"
                    border.color: ready ? Theme.accent : Theme.track
                    Text {
                        id: saveText
                        anchors.centerIn: parent
                        text: "SAVE"
                        color: parent.ready ? "#121116" : Theme.dim()
                        font.family: Theme.display
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: parent.ready
                        cursorShape: Qt.PointingHandCursor
                        onClicked: form.save()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Save"
                }
            }
        }

        function save() {
            const processes = processField.text.split(",").map((s) => s.trim()).filter((s) => s.length > 0).join(", ")
            let newId = ""
            if (isNew) {
                newId = Games.addOwn(nameField.text.trim(), commandField.text.trim(), processes,
                             twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
            } else if (own) {
                Games.updateOwn(g.id, nameField.text.trim(), commandField.text.trim(), processes,
                                twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
            } else {
                Games.setOptions(g.id, twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
            }
            const id = isNew ? newId : g.id
            if (id && id.length > 0) Games.setLayout(id, layoutChoice.picked)
            panel.editing = null
        }
    }

    component Labeled: Column {
        property string label
        property string hint: ""
        property bool small: false
        default property alias field: holder.data
        width: parent.width
        spacing: 6
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: parent.label.toUpperCase()
            color: parent.small ? Theme.dim() : Theme.muted()
            font.family: Theme.display
            font.pixelSize: parent.small ? 11 : 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Item {
            id: holder
            width: parent.width
            height: childrenRect.height
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: parent.hint.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: parent.hint
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    component Check: Item {
        id: check
        property string text
        property bool checked: false
        width: parent.width
        height: 24
        Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            color: check.checked ? Theme.accent : "transparent"
            border.color: check.checked ? Theme.accent : Theme.track
            HudIcon {
                anchors.centerIn: parent
                visible: check.checked
                name: "check"
                size: 13
                lineWidth: 2.4
                color: "#121116"
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.left: box.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: check.text
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: check.checked = !check.checked
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: text
        Accessible.checked: checked
    }

    component Field: Rectangle {
        property alias text: input.text
        property string placeholder
        height: 34
        color: "#1b1a20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text()
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: Theme.body
            font.pixelSize: 13
            maximumLength: 400
            clip: true
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: parent.parent.placeholder
                color: Theme.dim()
                font: input.font
            }
            Accessible.name: parent.placeholder
        }
    }
}
