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

    // Taken over by hand, so the list keeps its scroll place when a star,
    // an option or a game start changes the library.
    property var library: JSON.parse(Games.library)
    /// Covers downloaded since the library was last read (id → picture);
    /// the library brings them along once all have arrived.
    property var arrivedCovers: ({})
    Connections {
        target: Games
        function onCoverArrived(id, picture) {
            const next = Object.assign({}, panel.arrivedCovers)
            next[id] = picture
            panel.arrivedCovers = next
        }
        function onLibraryChanged() {
            const y = grid.contentY
            panel.arrivedCovers = ({})
            panel.library = JSON.parse(Games.library)
            Qt.callLater(() => grid.contentY = Math.max(0, Math.min(y, grid.contentHeight - grid.height)))
        }
    }
    /// Why the form could not save, shown in it.
    property string formError: ""
    readonly property var visibleGames: library.filter((g) => !g.hidden)
    readonly property int installedCount: visibleGames.filter((g) => g.installed).length
    badge: installedCount === visibleGames.length
        ? visibleGames.length + (visibleGames.length === 1 ? " GAME" : " GAMES")
        : installedCount + " OF " + visibleGames.length + " INSTALLED"

    /// recent, favorites, module, steam, lutris, heroic, own
    property string tab: "recent"
    property string query: ""
    /// The form: null (the list), {} (a new own game) or the game to edit.
    property var editing: null
    /// The form's tab: general, presets, launch.
    property string formPage: "general"
    /// The suggestions for the edited game are shown (over its form).
    property bool suggesting: false
    /// The Proton overview is shown instead of the list.
    property bool protonView: false
    /// Something to know after a save (e.g. Heroic's prefix), over the list.
    property string notice: ""
    /// The height the panel's body may take: the screen under its top less
    /// its frame (the launch views scroll inside it).
    readonly property real room: (parent ? parent.height : 900) - Math.max(0, y) - 68 - 12
    /// The form's LAUNCH tab while it exists (the suggestions fill it).
    property var launchTab: null
    onEditingChanged: { formPage = "general"; suggesting = false }

    /// "installed/all" for a launcher's tab ("n" when all are installed).
    function count(launcher) {
        const all = visibleGames.filter((g) => g.launcher === launcher)
        const installed = all.filter((g) => g.installed).length
        return installed === all.length ? String(all.length) : installed + "/" + all.length
    }
    function fold(s) { return String(s || "").toLocaleLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }

    readonly property var shown: {
        let list = visibleGames.slice()
        if (Games.installedOnly) list = list.filter((g) => g.installed)
        if (tab === "favorites") list = list.filter((g) => g.fav)
        else if (tab === "module") list = list.filter((g) => g.known.length > 0)
        else if (tab !== "recent") list = list.filter((g) => g.launcher === tab)
        const q = fold(query).trim()
        if (q.length > 0) list = list.filter((g) => fold(g.name).indexOf(q) >= 0)
        if (tab === "recent") {
            // Played ones first, newest first; then installed ones, the rest
            // by name.
            list.sort((a, b) => (b.lastPlayed - a.lastPlayed) || (b.installed - a.installed) || a.name.localeCompare(b.name))
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

    // Screenshots: GC_DEMO=games,launch (the LAUNCH tab of the demo's
    // racing game; ,detail opens its first flagged part, ,launcherrunning
    // shows Steam running), games,suggestions, games,proton, games,launchown.
    property bool demoDetail: false
    property real demoScroll: -1
    property bool demoPicker: false
    function demo(words) {
        const has = (w) => words.indexOf(w) >= 0
        const find = (id) => library.find((g) => g.id === id)
        if (has("launch") || has("suggestions")) {
            demoDetail = has("detail")
            demoPicker = has("picker")
            editing = find("steam:2483190") || null
            formPage = "launch"
            if (has("suggestions")) suggesting = true
            demoScroll = has("rows") ? 0.3 : has("middle") ? 0.5 : has("others") ? 0.75 : has("end") ? 1 : -1
        } else if (has("startwith")) {
            // games,startwith[,starterfile|,addprogram]: AION 2's WITH GAME tab.
            editing = find("own:1") || null
            formPage = "withgame"
        } else if (has("launchown")) {
            editing = find("own:1") || null
            formPage = "launch"
        } else if (has("proton")) {
            protonView = true
        }
        // ,tabsteam / ,tabheroic / ,tablutris open that launcher's tab.
        for (const l of ["steam", "heroic", "lutris"]) if (has("tab" + l)) tab = l
    }

    // Choices (the Proton lists) open over the whole panel.
    ChoiceList {
        id: choiceList
        parent: panel
        anchors.fill: parent
    }

    Column {
        width: parent.width
        spacing: 0
        visible: panel.editing === null && !panel.protonView
        // The body takes its children's whole rect, hidden ones too.
        height: visible ? implicitHeight : 0

        // Search, add, read again
        Item {
            width: parent.width
            height: 44
            Rectangle {
                id: searchBox
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(300, parent.width - addButton.width - refreshButton.width - protonButton.width - installedSwitch.width - 66)
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
            // INSTALLED ONLY: hides games that are owned but not installed.
            Item {
                id: installedSwitch
                anchors.left: searchBox.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: switchRow.implicitWidth
                height: 32
                Row {
                    id: switchRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        color: Games.installedOnly ? Theme.accent : "transparent"
                        border.color: Games.installedOnly ? Theme.accent : (switchMouse.containsMouse ? Theme.textSoft() : Theme.track)
                        HudIcon {
                            anchors.centerIn: parent
                            visible: Games.installedOnly
                            name: "check"
                            size: 11
                            lineWidth: 2.4
                            color: "#121116"
                        }
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.verticalCenter: parent.verticalCenter
                        text: "INSTALLED ONLY"
                        color: Games.installedOnly ? Theme.accent : (switchMouse.containsMouse ? Theme.text() : Theme.muted())
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                MouseArea {
                    id: switchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Games.saveInstalledOnly(!Games.installedOnly)
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Installed only"
                Accessible.checked: Games.installedOnly
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
                id: protonButton
                anchors.right: refreshButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 32
                text: "Proton"
                onClicked: panel.protonView = true
                Accessible.description: "Proton versions and which games use them"
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

        // A note from the last save.
        Rectangle {
            visible: panel.notice.length > 0
            width: parent.width
            height: visible ? noticeText.implicitHeight + 20 : 0
            color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08)
            Rectangle { width: parent.width; height: 2; color: Theme.accent }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: noticeText
                x: 12
                y: 10
                width: parent.width - 60
                wrapMode: Text.WordWrap
                text: "Saved. " + panel.notice
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
            }
            IconButton {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                icon: "close"
                tip: "Close the note"
                color: Theme.muted()
                onClicked: panel.notice = ""
            }
        }
        Item { visible: panel.notice.length > 0; width: 1; height: 14 }

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
                cellHeight: 168
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
                    : Games.installedOnly && panel.tab !== "own" && panel.tab !== "favorites" && panel.tab !== "module"
                        ? "No installed game here. INSTALLED ONLY hides the others."
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
                text: "Read from Steam, Lutris and Heroic on this PC. PLAY starts the game through its launcher, the companion follows; INSTALL opens the launcher's install."
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
        visible: active && !panel.suggesting
        height: visible && item ? item.implicitHeight : 0
        sourceComponent: GameForm {}
        onActiveChanged: panel.formError = ""
    }

    // Suggestions for the edited game (design L2Suggestions); APPLY puts
    // the result into the form's launch options.
    Loader {
        width: parent.width
        active: panel.editing !== null && panel.suggesting && panel.launchTab !== null
        visible: active
        height: active && item ? item.implicitHeight : 0
        sourceComponent: LaunchSuggestions {
            game: panel.editing
            fieldText: panel.launchTab ? panel.launchTab.text : ""
            savedText: panel.launchTab ? panel.launchTab.savedText : ""
            room: panel.room
            demoScroll: panel.demoScroll
            onApplied: (text) => { if (panel.launchTab) panel.launchTab.setText(text); panel.suggesting = false }
            onCanceled: panel.suggesting = false
        }
    }

    // The Proton overview (design L3Proton).
    Loader {
        width: parent.width
        active: panel.editing === null && panel.protonView
        visible: active
        height: active && item ? item.implicitHeight : 0
        sourceComponent: ProtonOverview {
            games: panel.visibleGames
            choices: choiceList
            room: panel.room
            onClosed: panel.protonView = false
            onSaved: (warning) => { panel.notice = warning; panel.protonView = false }
        }
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
        readonly property bool installed: g.installed !== false
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

            // Cover: the launcher's own picture on disk (or one downloaded),
            // else the name.
            Rectangle {
                id: cover
                width: parent.width
                height: 92
                color: "#24232b"
                clip: true
                Image {
                    id: picture
                    anchors.fill: parent
                    source: panel.arrivedCovers[card.g.id] || card.g.picture
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 320
                    visible: status === Image.Ready
                    // Not installed: the cover greyed.
                    opacity: card.installed ? 1 : 0.32
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: picture.status !== Image.Ready
                    opacity: card.installed ? 1 : 0.6
                    anchors.centerIn: parent
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
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
                        style: Theme.textStyle(); styleColor: Theme.shadow
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
                    // Up to two lines; a longer name shows whole on pointing.
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        width: parent.width
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: faceHover.hovered ? 4 : 2
                        elide: Text.ElideRight
                        lineHeight: 0.95
                        text: card.g.name
                        color: card.installed ? Theme.text() : Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.running ? panel.launcherName(card.g.launcher) + " · running"
                            : !card.installed && faceHover.hovered && card.g.note ? card.g.note
                            : !card.installed ? "Not installed"
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
                    // INSTALL is grey until pointed at, like the card.
                    readonly property color tint: card.installed || playMouse.containsMouse ? Theme.accent : Theme.muted()
                    color: card.running ? Theme.accent : playMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                    border.color: tint
                    Text {
                        id: playText
                        anchors.centerIn: parent
                        text: card.running ? "RUNNING" : card.installed ? "PLAY" : "INSTALL"
                        color: card.running ? "#121116" : play.tint
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
                    Accessible.name: (card.installed ? "Play " : "Install ") + card.g.name
                }
            }
        }
    }

    component GameForm: Column {
        id: form
        readonly property var g: panel.editing || ({})
        readonly property bool isNew: g.id === undefined
        readonly property bool own: isNew || g.own === true
        /// general, presets, launch
        property string page: panel.formPage
        /// The LAUNCH tab once it was opened (it reads the launcher's files).
        property bool launchOpened: page === "launch"
        readonly property var launch: launchLoader.item
        property bool saving: false
        /// Answers still out while saving, and what they said.
        property int waiting: 0
        property var errors: []
        property string warning: ""
        /// The GENERAL and PRESET SEARCH fields as last saved (or opened).
        property var base: ({})
        function snapshot() {
            return { name: nameField.text, command: commandField.text, processes: processField.text,
                twitch: twitchField.text, youtube: youtubeField.text, show: showBox.checked,
                radio: radioBox.checked, layout: layoutChoice.picked }
        }
        readonly property bool generalDirty: isNew || nameField.text !== base.name || commandField.text !== base.command
            || processField.text !== base.processes || twitchField.text !== base.twitch || youtubeField.text !== base.youtube
            || showBox.checked !== base.show || radioBox.checked !== base.radio || layoutChoice.picked !== base.layout
        readonly property bool launchDirty: launch !== null && launch.dirty
        /// The LAUNCH part cannot be written while its launcher runs; the
        /// rest still saves.
        readonly property bool launchBlocked: launchDirty && launch.running
        /// Cancel was pressed with unsaved LAUNCH edits: asks once, inline.
        property bool confirmCancel: false
        function cancel() {
            if (launchDirty && !confirmCancel) confirmCancel = true
            else panel.editing = null
        }
        spacing: 14
        topPadding: 2
        bottomPadding: 4

        onPageChanged: if (page === "launch") launchOpened = true
        Component.onCompleted: {
            nameField.text = g.name || ""
            commandField.text = g.command || ""
            processField.text = (g.processes || []).join(", ")
            twitchField.text = g.twitch || ""
            youtubeField.text = g.youtube || ""
            showBox.checked = g.showOnStart === undefined ? true : g.showOnStart
            radioBox.checked = g.radioOnStart === true
            base = snapshot()
            panel.launchTab = Qt.binding(() => form.launch)
        }
        Component.onDestruction: panel.launchTab = null

        // Header: what is edited, from where.
        Item {
            width: parent.width
            height: 30
            Row {
                anchors.left: parent.left
                anchors.right: launcherTag.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    text: form.isNew ? "ADD GAME" : "EDIT GAME"
                    color: Theme.text()
                    font.family: Theme.display
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !form.isNew
                    width: Math.min(implicitWidth, parent.width - 120)
                    elide: Text.ElideRight
                    text: form.g.name || ""
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
            Tag {
                id: launcherTag
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.launcherName(form.isNew ? "own" : form.g.launcher).toUpperCase()
                tint: "#5a5764"
                size: 11
            }
        }

        // Tabs
        Item {
            width: parent.width
            height: 34
            Row {
                spacing: 18
                height: parent.height
                FormTab { name: "general"; label: "General" }
                FormTab { name: "presets"; label: "Preset search" }
                FormTab { name: "launch"; label: "Launch"; visible: !form.isNew }
                FormTab { name: "withgame"; label: "With game"; visible: !form.isNew }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        }

        // GENERAL
        Column {
            visible: form.page === "general"
            width: parent.width
            spacing: 14
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                visible: !form.own
                width: parent.width
                wrapMode: Text.WordWrap
                text: "From " + panel.launcherName(form.g.launcher) + ". Its name and how it starts come from there; here you set what the companion does with it."
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
            Rectangle { visible: form.own; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
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
        }

        // PRESET SEARCH
        Column {
            visible: form.page === "presets"
            width: parent.width
            spacing: 14
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                width: parent.width
                wrapMode: Text.WordWrap
                text: "What the Streams panel's game tab looks for while this game runs. Empty: the built-in game's search, if it has one."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
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
        }

        // LAUNCH (read when first opened); scrolls when the screen is too
        // short for it.
        Item {
            id: launchBox
            visible: form.page === "launch"
            width: parent.width
            // The room left on the screen under the panel's top, less the
            // panel's frame, the form's header, tabs and footer.
            readonly property real room: panel.room - 30 - 34 - 46 - 4 * 14 - (panel.formError.length > 0 ? 40 : 0)
            height: Math.max(160, Math.min(launchLoader.height, room))
            clip: launchFlick.contentHeight > height
            Flickable {
                id: launchFlick
                anchors.fill: parent
                contentHeight: launchLoader.height
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Loader {
                    id: launchLoader
                    width: launchBox.width - (launchFlick.interactive ? 12 : 0)
                    active: form.launchOpened && !form.isNew
                    sourceComponent: LaunchTab {
                        width: launchLoader.width
                        game: form.g
                        choices: choiceList
                        ownText: commandField.text
                        onOwnTextEdited: (text) => commandField.text = text
                        onShowSuggestions: panel.suggesting = true
                        demoDetail: panel.demoDetail
                        demoPicker: panel.demoPicker
                    }
                }
            }
            WheelScroll { flick: launchFlick; step: 90 }
            // Where the list stands (only when it scrolls).
            Rectangle {
                visible: launchFlick.interactive
                anchors.right: parent.right
                width: 3
                height: parent.height
                color: Theme.trackDark
                Rectangle {
                    width: parent.width
                    height: Math.max(24, parent.height * launchFlick.height / launchFlick.contentHeight)
                    y: (parent.height - height) * (launchFlick.contentY / Math.max(1, launchFlick.contentHeight - launchFlick.height))
                    color: Theme.track
                }
            }
        }

        // WITH GAME (MN, 2026-11-14): what starts and closes with it; saved
        // at once. Scrolls when the screen is too short for it.
        Item {
            id: withBox
            visible: form.page === "withgame"
            width: parent.width
            readonly property real room: panel.room - 30 - 34 - 46 - 4 * 14 - (panel.formError.length > 0 ? 40 : 0)
            height: Math.max(160, Math.min(withLoader.height, room))
            clip: withFlick.contentHeight > height
            Flickable {
                id: withFlick
                anchors.fill: parent
                contentHeight: withLoader.height
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Loader {
                    id: withLoader
                    width: withBox.width - (withFlick.interactive ? 12 : 0)
                    active: form.page === "withgame" && !form.isNew
                    sourceComponent: StartWithTab { width: withLoader.width; game: form.g }
                }
            }
            // Screenshots (games,startwith,addprogram): scrolled to the end.
            Timer {
                running: withBox.visible && nativeWindow.demo.indexOf("addprogram") >= 0
                interval: 400
                onTriggered: withFlick.contentY = Math.max(0, withFlick.contentHeight - withFlick.height)
            }
            WheelScroll { flick: withFlick; step: 90 }
            Rectangle {
                visible: withFlick.interactive
                anchors.right: parent.right
                width: 3
                height: parent.height
                color: Theme.trackDark
                Rectangle {
                    width: parent.width
                    height: Math.max(24, parent.height * withFlick.height / withFlick.contentHeight)
                    y: (parent.height - height) * (withFlick.contentY / Math.max(1, withFlick.contentHeight - withFlick.height))
                    color: Theme.track
                }
            }
        }

        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            visible: panel.formError.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: panel.formError
            color: Theme.red
            font.family: Theme.body
            font.pixelSize: 12
        }
        Item {
            width: parent.width
            height: 46
            Rectangle { x: -14; width: parent.width + 28; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            TextButton {
                visible: !form.isNew && form.own && form.page === "general"
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                danger: true
                text: "Remove"
                onClicked: { Games.removeOwn(form.g.id); panel.editing = null }
            }
            // Where the change goes (LAUNCH).
            Row {
                visible: form.page === "launch" && form.launch !== null && form.launch.supported && !form.own && !form.confirmCancel
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.rightMargin: 14
                anchors.bottom: parent.bottom
                height: 34
                spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 14
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: form.launch && form.launch.fileName.length > 0
                        ? "A backup of " + panel.launcherName(form.g.launcher) + "'s " + form.launch.fileName + " is kept before each save."
                        : "A backup of the launcher's file is kept before each save."
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 10
                visible: !form.confirmCancel
                TextButton { text: "Cancel"; onClicked: form.cancel() }
                Rectangle {
                    width: saveText.implicitWidth + 32
                    height: 34
                    readonly property bool ready: !form.saving
                        && (form.generalDirty || (form.launchDirty && !form.launchBlocked))
                        && (!form.own || (nameField.text.trim().length > 0 && commandField.text.trim().length > 0))
                    color: ready ? (saveMouse.containsMouse ? Theme.accentLight : Theme.accent) : "transparent"
                    border.color: ready ? Theme.accent : "#3a3842"
                    Text {
                        style: parent.ready ? Text.Normal : Theme.textStyle(); styleColor: Theme.shadow
                        id: saveText
                        anchors.centerIn: parent
                        text: form.saving ? "SAVING…" : "SAVE"
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
            // Cancel with unsaved LAUNCH edits: one question, in place.
            Row {
                visible: form.confirmCancel
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Discard changes?"
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                TextButton { text: "Discard"; danger: true; onClicked: panel.editing = null }
                TextButton { text: "Keep editing"; onClicked: form.confirmCancel = false }
            }
        }

        Requests { id: saveRequests }

        // The companion's own settings at once; the launcher's file and the
        // Proton choice on the worker, the form closing when both are done.
        function save() {
            const processes = processField.text.split(",").map((s) => s.trim()).filter((s) => s.length > 0).join(", ")
            let newId = ""
            let ok = true
            if (isNew) {
                newId = Games.addOwn(nameField.text.trim(), commandField.text.trim(), processes,
                             twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
                ok = newId.length > 0
            } else if (own) {
                ok = Games.updateOwn(g.id, nameField.text.trim(), commandField.text.trim(), processes,
                                twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
            } else {
                Games.setOptions(g.id, twitchField.text.trim(), youtubeField.text.trim(), showBox.checked, radioBox.checked)
            }
            if (!ok) {
                panel.formError = "Couldn't save: check \"Start with\" (a quote left open?)."
                return
            }
            const id = isNew ? newId : g.id
            if (id && id.length > 0) Games.setLayout(id, layoutChoice.picked)
            errors = []
            warning = ""
            waiting = 0
            // What is saved now counts as unchanged from here on.
            base = snapshot()
            confirmCancel = false
            // The launcher runs: its part waits, the form stays open.
            const held = launchBlocked
            const heldNote = held ? "Saved, except the launch options: close " + panel.launcherName(g.launcher) + " first, then save again." : ""
            const done = () => {
                form.waiting -= 1
                if (form.waiting > 0) return
                form.saving = false
                if (form.errors.length > 0) {
                    panel.formError = "Couldn't save: " + form.errors.join(" ")
                    return
                }
                panel.notice = form.warning
                panel.editing = null
            }
            if (!held && launch && launch.textDirty) {
                waiting += 1
                const text = launch.text.trim()
                saveRequests.ask(Games.setLaunchOptions(g.id, text), (a) => {
                    if (!a || a.error.length > 0) form.errors = form.errors.concat([(a ? a.error : "no answer") + "."])
                    else if (form.launch) form.launch.markTextSaved(text)
                    done()
                })
            }
            if (!held && launch && launch.protonDirty) {
                waiting += 1
                const pick = launch.protonPick
                saveRequests.ask(Games.setProton(g.id, pick), (a) => {
                    if (!a || a.error.length > 0) form.errors = form.errors.concat([(a ? a.error : "no answer") + "."])
                    else {
                        if (a.warning.length > 0) form.warning = a.warning
                        if (form.launch) form.launch.markProtonSaved(pick)
                    }
                    done()
                })
            }
            if (waiting > 0) {
                saving = true
                panel.formError = ""
                return
            }
            if (held) {
                panel.formError = heldNote
                return
            }
            panel.editing = null
        }
    }

    component FormTab: Item {
        property string name
        property string label
        width: formTabText.implicitWidth
        height: parent.height
        readonly property bool current: panel.formPage === name
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: formTabText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: parent.current ? Theme.accent : (formTabMouse.containsMouse ? Theme.text() : Theme.muted())
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
            id: formTabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.formPage = parent.name
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
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
