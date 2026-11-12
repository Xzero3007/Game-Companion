import QtQuick
import GameCompanion
import "theme.js" as Theme

// Streams: Twitch, YouTube and the user's own Jellyfin server (home network
// only). The running game's lists come first, under its purple tag; a click
// plays in that site's video window over the game.
Panel {
    id: panel
    panelId: "streams"
    title: "Streams"
    icon: "tv"
    width: 480
    minWidth: 420
    stretchy: true

    signal playRequested(var what)
    /// What plays now in each window (to mark its row).
    property string playingTwitch: ""
    property string playingYoutube: ""
    property string playingJellyfin: ""

    readonly property var game: JSON.parse(Streams.game)
    readonly property var twitchList: JSON.parse(Streams.twitch)
    readonly property var youtubeList: JSON.parse(Streams.youtube)
    readonly property var favs: JSON.parse(Streams.favourites)
    readonly property var channels: JSON.parse(Streams.channels)
    readonly property var account: JSON.parse(Streams.account)
    readonly property bool onTwitch: Streams.tab === "twitch"
    readonly property bool onJelly: Streams.tab === "jellyfin"
    readonly property var jellyList: JSON.parse(Jellyfin.items)
    readonly property var jfAccount: Jellyfin.account.length > 0 ? JSON.parse(Jellyfin.account) : null
    /// Jellyfin's libraries: the way in (library, show, season), each
    /// `{ id, type, collection, seriesId, name }`.
    property var jfPath: []
    property bool editingGame: false
    /// YouTube: the channel whose videos show ("" for none).
    property var channel: null

    // The count, or how far a long load is (YouTube's subscriptions).
    badge: onJelly ? (Jellyfin.state === "ready" && jfAccount ? Jellyfin.message.toUpperCase() : "")
        : onTwitch ? (Streams.twitchState === "ready" ? Streams.twitchMessage.toUpperCase() : "")
        : (Streams.youtubeState === "ready" || Streams.youtubeState === "loading" ? Streams.youtubeMessage.toUpperCase() : "")
    readonly property bool tiles: Streams.grid
    readonly property bool channelsView: Streams.tab === "youtube" && Streams.youtubeView === "channels"

    // Back and forth through tabs, lists, searches and channels, as in a
    // browser: { tab, view, text, channel }.
    property var history: []
    property int at: -1
    readonly property bool canBack: at > 0
    readonly property bool canForward: at < history.length - 1
    function stateNow() {
        return { tab: Streams.tab, view: onJelly ? Jellyfin.view : onTwitch ? Streams.twitchView : Streams.youtubeView,
                 text: search.text, channel: channel, path: jfPath }
    }
    function go(s) {
        let h = history.slice(0, at + 1)
        // An empty search tab is replaced by its search.
        const last = h.length > 0 ? h[h.length - 1] : null
        if (last && last.tab === s.tab && last.view === "search" && !last.text && s.view === "search") h.pop()
        h.push(s)
        if (h.length > 50) h = h.slice(h.length - 50)
        history = h
        at = h.length - 1
        apply(s)
    }
    function apply(s) {
        if (Streams.tab !== s.tab) Streams.chooseTab(s.tab)
        search.text = s.text || ""
        channel = s.channel || null
        if (s.tab === "jellyfin") {
            jfPath = s.path || []
            if (s.view === "folder" && jfPath.length > 0) Jellyfin.load("folder", JSON.stringify(jfPath[jfPath.length - 1]))
            else Jellyfin.load(s.view === "folder" ? "libraries" : s.view, s.view === "search" ? search.text : "")
        } else if (s.tab === "twitch") {
            Streams.loadTwitch(s.view, s.view === "search" ? search.text : "")
        } else if (s.view === "channel" && channel) {
            Streams.loadYoutube("channel", channel.id)
        } else {
            Streams.loadYoutube(s.view === "channel" ? "channels" : s.view, s.view === "search" ? search.text : "")
        }
        if (s.view === "search" && !s.text) search.forceActiveFocus()
    }
    function back() { if (canBack) { at = at - 1; apply(history[at]) } }
    function forward() { if (canForward) { at = at + 1; apply(history[at]) } }
    Shortcut {
        sequences: ["Alt+Left", StandardKey.Back]
        enabled: panel.visible && !Companion.locked
        onActivated: panel.back()
    }
    Shortcut {
        sequences: ["Alt+Right", StandardKey.Forward]
        enabled: panel.visible && !Companion.locked
        onActivated: panel.forward()
    }

    property bool loadedOnce: false
    onVisibleChanged: if (visible && !loadedOnce) firstLoad()
    Component.onCompleted: if (visible && !loadedOnce) firstLoad()
    function firstLoad() {
        loadedOnce = true
        Streams.refreshAccount()
        if (Streams.youtubeView === "channel") Streams.loadYoutube("channels", "")
        history = [stateNow()]
        at = 0
        reload()
    }
    function reload() {
        if (onJelly) {
            if (!jfAccount) return
            if (Jellyfin.view === "search") { if (search.text.trim().length > 0) Jellyfin.load("search", search.text) }
            else if (Jellyfin.view === "folder" && jfPath.length > 0) Jellyfin.load("folder", JSON.stringify(jfPath[jfPath.length - 1]))
            else Jellyfin.load(Jellyfin.view === "folder" ? "libraries" : Jellyfin.view, "")
        } else if (onTwitch) {
            if (Streams.twitchView === "search") { if (search.text.trim().length > 0) Streams.loadTwitch("search", search.text) }
            else Streams.loadTwitch(Streams.twitchView, "")
        } else {
            if (Streams.youtubeView === "search") { if (search.text.trim().length > 0) Streams.loadYoutube("search", search.text) }
            else if (Streams.youtubeView === "channel" && channel) Streams.loadYoutube("channel", channel.id)
            else if (Streams.youtubeView === "channels") return
            else Streams.loadYoutube(Streams.youtubeView === "channel" ? "subscriptions" : Streams.youtubeView, "")
        }
    }
    function runSearch() {
        const text = search.text.trim()
        if (text.length === 0) return
        if (Streams.tab === "youtube") {
            // A pasted link plays at once.
            const id = Streams.videoId(text)
            if (id.length > 0) { panel.playRequested({ kind: "youtube", id: id, title: "", name: "" }); return }
        }
        go({ tab: Streams.tab, view: "search", text: text, channel: null })
    }
    function ago(iso) {
        if (!iso) return ""
        const s = (Date.now() - Date.parse(iso)) / 1000
        if (!(s >= 0)) return ""
        if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        const d = Math.round(s / 86400)
        return d === 1 ? "yesterday" : d + " days ago"
    }
    function clock(sec) {
        sec = Math.floor(sec || 0)
        if (sec <= 0) return ""
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
        const two = (n) => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s)
    }
    // Jellyfin: into a library, a show or a season; or play.
    function jfOpen(it) {
        if (it.openable) {
            const at = jfPath.length > 0 ? jfPath[jfPath.length - 1] : null
            const step = { id: it.id, type: it.type, collection: it.collection || (at ? at.collection : ""),
                           seriesId: it.seriesId || (at && at.type === "Series" ? at.id : ""), name: it.name }
            go({ tab: "jellyfin", view: "folder", text: "", channel: null, path: jfPath.concat([step]) })
        } else if (it.playable) {
            panel.playRequested({ kind: "jellyfin", id: it.id, title: it.name, name: it.sub, item: it, start: it.position || 0 })
        }
    }
    function timeLeft(it) {
        const s = Math.max(0, (it.runtime || 0) - (it.position || 0))
        if (!(it.position > 0) || s <= 0) return ""
        const m = Math.round(s / 60)
        if (m < 1) return "under a minute left"
        return (m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min") + " left"
    }
    function since(iso) {
        if (!iso) return ""
        const m = Math.round((Date.now() - Date.parse(iso)) / 60000)
        if (!(m >= 0)) return ""
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    Column {
        width: parent.width
        spacing: 10

        // Twitch / YouTube / Jellyfin; back, forth, tiles or rows.
        Item {
            width: parent.width
            height: 30
            Row {
                spacing: 18
                height: 30
                SiteTab { name: "twitch"; label: "Twitch" }
                SiteTab { name: "youtube"; label: "YouTube" }
                SiteTab { name: "jellyfin"; label: "Jellyfin" }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: -6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                IconButton {
                    icon: "back"
                    iconSize: 16
                    color: panel.canBack ? Theme.muted : Theme.track
                    hoverColor: panel.canBack ? Theme.accent : Theme.track
                    tip: "Back (Alt+Left, the mouse's back button)"
                    onClicked: panel.back()
                }
                IconButton {
                    icon: "forward"
                    iconSize: 16
                    color: panel.canForward ? Theme.muted : Theme.track
                    hoverColor: panel.canForward ? Theme.accent : Theme.track
                    tip: "Forward (Alt+Right, the mouse's forward button)"
                    onClicked: panel.forward()
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 16; color: Theme.divider }
                IconButton {
                    icon: "grid"
                    iconSize: 14
                    color: panel.tiles ? Theme.accent : Theme.muted
                    tip: "Tiles side by side"
                    onClicked: Streams.saveGrid(true)
                }
                IconButton {
                    icon: "list"
                    iconSize: 14
                    color: !panel.tiles ? Theme.accent : Theme.muted
                    tip: "Rows"
                    onClicked: Streams.saveGrid(false)
                }
            }
        }

        // Jellyfin: the home network, or signing in.
        Rectangle {
            visible: panel.onJelly
            width: parent.width
            height: panel.jfAccount ? 36 : signInColumn.implicitHeight + 24
            color: Qt.rgba(1, 1, 1, 0.04)
            Rectangle { width: 2; height: parent.height; color: panel.jfAccount ? Theme.accent : Theme.track }
            Row {
                visible: !!panel.jfAccount
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7
                    color: Jellyfin.state === "failed" ? Theme.track : Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - homeOnly.implicitWidth - 37
                    elide: Text.ElideRight
                    text: panel.jfAccount ? "Home network · " + panel.jfAccount.serverName + " · " + panel.jfAccount.user : ""
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text {
                    id: homeOnly
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HOME ONLY"
                    color: Theme.dim
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
            }
            Column {
                id: signInColumn
                visible: !panel.jfAccount
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8
                Text {
                    text: "SIGN IN TO YOUR JELLYFIN SERVER"
                    color: Theme.text
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                JellyfinSignIn { id: signIn; width: parent.width }
            }
        }

        // The game's preset, in purple.
        Rectangle {
            visible: !panel.onJelly
            width: parent.width
            height: panel.editingGame ? gameEdit.implicitHeight + 20 : 44
            color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.14)
            Rectangle { width: 2; height: parent.height; color: Theme.purple }
            Row {
                visible: !panel.editingGame
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: gameTag.implicitWidth + 16
                    height: 20
                    color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.35)
                    Text {
                        id: gameTag
                        anchors.centerIn: parent
                        text: panel.game.name.toUpperCase()
                        color: "#e6dbfa"
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - gameTag.implicitWidth - changeGame.width - 46
                    elide: Text.ElideRight
                    text: panel.onTwitch ? "Twitch category: " + panel.game.twitch : "Preset search: “" + panel.game.youtube + "”, newest first"
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Rectangle {
                    id: changeGame
                    anchors.verticalCenter: parent.verticalCenter
                    width: changeText.implicitWidth + 16
                    height: 28
                    color: changeMouse.containsMouse ? Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.2) : "transparent"
                    border.color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.5)
                    Text {
                        id: changeText
                        anchors.centerIn: parent
                        text: "CHANGE"
                        color: "#e6dbfa"
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: changeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            gameName.text = panel.game.name
                            gameTwitch.text = panel.game.twitch
                            gameYoutube.text = panel.game.youtube
                            panel.editingGame = true
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Change the game's preset"
                }
            }
            Column {
                id: gameEdit
                visible: panel.editingGame
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 6
                Text {
                    text: "Until games are found by themselves, set the one you play here."
                    color: "#d8d4e0"
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Field { id: gameName; width: parent.width; placeholder: "Game, e.g. AION 2" }
                Field { id: gameTwitch; width: parent.width; placeholder: "Twitch category, as Twitch names it" }
                Field { id: gameYoutube; width: parent.width; placeholder: "YouTube search words" }
                Row {
                    spacing: 8
                    TextButton {
                        text: "Save"
                        onClicked: {
                            Streams.changeGame(gameName.text, gameTwitch.text, gameYoutube.text)
                            panel.editingGame = false
                            panel.reload()
                        }
                    }
                    TextButton { text: "Cancel"; onClicked: panel.editingGame = false }
                }
            }
        }

        // The lists
        Item {
            visible: !panel.onJelly || !!panel.jfAccount
            width: parent.width
            height: 36
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            Row {
                visible: panel.onTwitch
                height: parent.height
                spacing: 16
                ListTab { name: "game"; label: panel.game.name; purple: true; twitch: true }
                ListTab { name: "following"; label: "Following"; twitch: true }
                ListTab { name: "favourites"; label: "Favorites"; twitch: true }
                ListTab { name: "live"; label: "All live"; twitch: true }
                ListTab { name: "search"; label: ""; searchIcon: true; twitch: true }
            }
            Row {
                visible: panel.onJelly
                height: parent.height
                spacing: 16
                ListTab { name: "continue"; label: "Continue"; site: "jellyfin" }
                ListTab { name: "nextup"; label: "Next up"; site: "jellyfin" }
                ListTab { name: "libraries"; label: "Libraries"; site: "jellyfin" }
                ListTab { name: "search"; label: ""; searchIcon: true; site: "jellyfin" }
            }
            Row {
                visible: Streams.tab === "youtube"
                height: parent.height
                spacing: 16
                ListTab { name: "game"; label: panel.game.name + " new"; purple: true }
                ListTab { name: "subscriptions"; label: "Subscriptions" }
                ListTab { name: "channels"; label: "My channels" }
                ListTab { name: "search"; label: ""; searchIcon: true }
            }
        }

        // Search
        Rectangle {
            visible: (panel.onJelly ? (!!panel.jfAccount && Jellyfin.view) : panel.onTwitch ? Streams.twitchView : Streams.youtubeView) === "search"
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
                maximumLength: 100
                onAccepted: panel.runSearch()
                Text {
                    visible: search.text.length === 0
                    text: panel.onJelly ? "A film, a show or an episode, then Enter"
                        : panel.onTwitch ? "A channel's name, then Enter" : "Search words or a video's link, then Enter"
                    color: Theme.dim
                    font: search.font
                }
                Accessible.name: panel.onJelly ? "Search Jellyfin" : panel.onTwitch ? "Search Twitch" : "Search YouTube"
            }
        }

        // Jellyfin: where in the libraries (a click goes back there).
        Flow {
            visible: panel.onJelly && Jellyfin.view === "folder" && panel.jfPath.length > 0
            width: parent.width
            spacing: 6
            TextButton { text: "‹ Libraries"; onClicked: panel.go({ tab: "jellyfin", view: "libraries", text: "", channel: null, path: [] }) }
            Repeater {
                model: panel.jfPath
                delegate: Text {
                    required property var modelData
                    required property int index
                    readonly property bool last: index === panel.jfPath.length - 1
                    height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: "/  " + modelData.name
                    color: last ? Theme.text : (crumbMouse.containsMouse ? Theme.accent : Theme.muted)
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: last ? Font.DemiBold : Font.Normal
                    MouseArea {
                        id: crumbMouse
                        anchors.fill: parent
                        enabled: !parent.last
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.go({ tab: "jellyfin", view: "folder", text: "", channel: null, path: panel.jfPath.slice(0, parent.index + 1) })
                    }
                }
            }
        }

        // The channel whose videos show (My channels → one).
        Row {
            visible: Streams.tab === "youtube" && Streams.youtubeView === "channel" && panel.channel !== null
            spacing: 10
            TextButton { text: "‹ Channels"; onClicked: panel.go({ tab: "youtube", view: "channels", text: "", channel: null }) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.channel ? panel.channel.name : ""
                color: Theme.text
                font.family: Theme.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Item {
            id: listArea
            visible: !panel.onJelly || !!panel.jfAccount
            x: -14
            width: parent.width + 28
            // Rows: four; tiles: two rows of them.
            height: (panel.tiles && !panel.channelsView ? Math.max(79 * 4, grid.cellHeight * 2) : 79 * 4) + panel.grow
            clip: true
            readonly property int columns: Math.max(2, Math.min(4, Math.floor((width - 16) / 230)))
            readonly property int channelColumns: Math.max(2, Math.min(5, Math.floor((width - 16) / 190)))
            readonly property Flickable shown: panel.channelsView ? (panel.tiles ? channelGrid : channelList) : (panel.tiles ? grid : list)
            // The mouse's back and forward buttons.
            TapHandler {
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                onTapped: (point, button) => button === Qt.BackButton ? panel.back() : panel.forward()
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !panel.channelsView && !panel.tiles
                model: visible ? (panel.onJelly ? panel.jellyList : panel.onTwitch ? panel.twitchList : panel.youtubeList) : []
                delegate: panel.onJelly ? jellyRow : panel.onTwitch ? twitchRow : videoRow
                onAtYEndChanged: if (atYEnd && panel.onJelly && Jellyfin.hasMore) Jellyfin.more()
            }
            GridView {
                id: grid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !panel.channelsView && panel.tiles
                cellWidth: Math.floor(width / listArea.columns)
                cellHeight: Math.round((cellWidth - 12) * 9 / 16) + (panel.onJelly ? 58 : 78)
                model: visible ? (panel.onJelly ? panel.jellyList : panel.onTwitch ? panel.twitchList : panel.youtubeList) : []
                delegate: panel.onJelly ? jellyTile : panel.onTwitch ? twitchTile : videoTile
                onAtYEndChanged: if (atYEnd && panel.onJelly && Jellyfin.hasMore) Jellyfin.more()
            }
            ListView {
                id: channelList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: panel.channelsView && !panel.tiles
                model: visible ? panel.channels : []
                delegate: channelRow
            }
            GridView {
                id: channelGrid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: panel.channelsView && panel.tiles
                cellWidth: Math.floor(width / listArea.channelColumns)
                cellHeight: 62
                model: visible ? panel.channels : []
                delegate: channelTile
            }
            WheelScroll { flick: list; step: 79 * 2 }
            WheelScroll { flick: grid; step: grid.cellHeight }
            WheelScroll { flick: channelList; step: 46 * 3 }
            WheelScroll { flick: channelGrid; step: 62 * 2 }
            Text {
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                readonly property string st: panel.onJelly ? Jellyfin.state : panel.onTwitch ? Streams.twitchState : Streams.youtubeState
                readonly property int count: listArea.shown.count
                visible: (st === "loading" && count === 0) || st === "failed" || (st !== "loading" && count === 0)
                text: st === "loading" ? "Loading…"
                    : st === "failed" ? (panel.onJelly ? Jellyfin.message : panel.onTwitch ? Streams.twitchMessage : Streams.youtubeMessage)
                    : panel.onJelly ? (Jellyfin.view === "search" ? "Type, then Enter."
                        : Jellyfin.view === "continue" ? "Nothing half watched right now."
                        : Jellyfin.view === "nextup" ? "No next episodes right now."
                        : st === "idle" ? "" : "Nothing in here.")
                    : panel.channelsView ? "No channels yet: FreeTube's subscriptions show here, and channels you keep with the star beside a video."
                    : (panel.onTwitch ? Streams.twitchView : Streams.youtubeView) === "search" ? "Type, then Enter."
                    : panel.onTwitch && Streams.twitchView === "favourites" ? "No favorites yet: the star beside a channel keeps it."
                    : panel.onTwitch && Streams.twitchView === "following" ? "You follow no channels yet."
                    : st === "idle" ? "" : "Nothing here right now."
                color: st === "failed" ? Theme.red : Theme.dim
                font.family: Theme.body
                font.pixelSize: 12
            }
        }

        // What it goes through
        Item {
            x: -14
            width: parent.width + 28
            height: 30
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.onJelly ? "Your own server, in your home network only · nothing goes out"
                        : panel.onTwitch
                        ? (panel.account.streamlink ? "Ad-free via Streamlink" : "Through yt-dlp (install streamlink for no ad breaks)")
                          + (panel.account.user && panel.account.user !== "?" && panel.account.user !== "…" ? " · signed in as " + panel.account.user : "")
                        : "Subscriptions read from FreeTube · search via yt-dlp"
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                icon: "refresh"
                iconSize: 13
                color: Theme.dim
                tip: "Load again"
                onClicked: { if (!panel.onJelly) Streams.forget(); panel.reload() }
            }
        }
    }

    Component {
        id: twitchRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingTwitch === modelData.login
            readonly property bool fav: panel.favs.indexOf(modelData.login.toLowerCase()) >= 0
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
                cursorShape: row.modelData.live ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.modelData.live) panel.playRequested({ kind: "twitch", id: row.modelData.login, name: row.modelData.name, game: row.modelData.game, title: row.modelData.title })
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.live ? row.modelData.picture : row.modelData.avatar
                dimmed: !row.modelData.live
                Rectangle {
                    visible: row.modelData.live
                    x: 4; y: 4
                    width: liveText.implicitWidth + 8
                    height: liveText.implicitHeight + 2
                    color: Theme.red
                    Text { id: liveText; anchors.centerIn: parent; text: "LIVE"; color: "#ffffff"; font.pixelSize: 9; font.weight: Font.Bold; font.family: Theme.body }
                }
                Text {
                    visible: row.current
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: "PLAYING"
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: star.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
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
                    text: row.modelData.live ? row.modelData.title : "Offline"
                    color: Theme.textSoft
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: row.modelData.live
                    text: {
                        const parts = [Number(row.modelData.viewers).toLocaleString(Qt.locale("en_US"), "f", 0) + " viewers"]
                        if (row.modelData.game && Streams.twitchView !== "game") parts.push(row.modelData.game)
                        const t = panel.since(row.modelData.since)
                        if (t) parts.push(t)
                        return parts.join(" · ")
                    }
                    color: Theme.dim
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
                onClicked: Streams.toggleFavourite(row.modelData.login)
            }
        }
    }

    Component {
        id: videoRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingYoutube === modelData.id
            readonly property bool kept: !!modelData.channelId && panel.channels.some((c) => c.id === modelData.channelId && !c.freetube)
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
                onClicked: panel.playRequested({ kind: "youtube", id: row.modelData.id, title: row.modelData.title, name: row.modelData.channel })
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.picture
                Rectangle {
                    visible: row.modelData.duration > 0 || row.modelData.live
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: lengthText.implicitWidth + 8
                    height: lengthText.implicitHeight + 2
                    color: row.modelData.live ? Theme.red : Qt.rgba(0, 0, 0, 0.75)
                    Text {
                        id: lengthText
                        anchors.centerIn: parent
                        text: row.modelData.live ? "LIVE" : panel.clock(row.modelData.duration)
                        color: Theme.text
                        font.family: Theme.body
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: star.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    text: row.modelData.title
                    color: row.current ? Theme.accent : Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    lineHeight: 1.1
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [row.modelData.channel, panel.ago(row.modelData.published)].filter((t) => t).join(" · ")
                        + (row.current ? " · " : "")
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                    Text {
                        anchors.left: parent.right
                        visible: row.current
                        text: "watching"
                        color: Theme.accent
                        font: parent.font
                    }
                }
            }
            IconButton {
                id: star
                visible: !!row.modelData.channelId
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                icon: "star"
                iconSize: 16
                filled: row.kept
                color: row.kept ? Theme.accent : Theme.dim
                tip: row.kept ? "Remove the channel from My channels" : "Keep the channel in My channels"
                onClicked: Streams.toggleChannel(row.modelData.channelId, row.modelData.channel)
            }
        }
    }

    Component {
        id: channelRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 46
            Rectangle { anchors.fill: parent; color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent" }
            Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: Theme.rowLine }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "youtube", view: "channel", text: "", channel: row.modelData })
            }
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: star.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: row.modelData.freetube ? "From FreeTube" : "Kept here"
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                id: star
                visible: !row.modelData.freetube
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                icon: "star"
                iconSize: 16
                filled: true
                color: Theme.accent
                tip: "Remove the channel"
                onClicked: Streams.toggleChannel(row.modelData.id, row.modelData.name)
            }
        }
    }

    // Tiles: side by side, two to four a row as the panel is wide.
    component Tile: Item {
        id: tile
        property bool current: false
        property bool hovered: tileMouse.containsMouse
        readonly property Item thumb: tileThumb
        property string picture
        property bool dimmed: false
        default property alias extra: info.data
        signal clicked
        width: GridView.view.cellWidth
        height: GridView.view.cellHeight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            color: tile.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : (tile.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
            Rectangle { visible: tile.current; width: parent.width; height: 2; color: Theme.accent }
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
        Thumb {
            id: tileThumb
            source: tile.picture
            dimmed: tile.dimmed
            x: 6
            y: 6
            width: parent.width - 12
            height: Math.round(width * 9 / 16)
        }
        Item {
            id: info
            x: 6
            anchors.top: tileThumb.bottom
            anchors.topMargin: 6
            width: parent.width - 12
            anchors.bottom: parent.bottom
        }
    }

    Component {
        id: twitchTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingTwitch === modelData.login
            readonly property bool fav: panel.favs.indexOf(modelData.login.toLowerCase()) >= 0
            picture: modelData.live ? modelData.picture : modelData.avatar
            dimmed: !modelData.live
            onClicked: if (modelData.live) panel.playRequested({ kind: "twitch", id: modelData.login, name: modelData.name, game: modelData.game, title: modelData.title })
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.live
                x: 4; y: 4
                width: tileLive.implicitWidth + 8
                height: tileLive.implicitHeight + 2
                color: Theme.red
                Text { id: tileLive; anchors.centerIn: parent; text: "LIVE"; color: "#ffffff"; font.pixelSize: 9; font.weight: Font.Bold; font.family: Theme.body }
            }
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.live
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: tileViewers.implicitWidth + 8
                height: tileViewers.implicitHeight + 2
                color: Qt.rgba(0, 0, 0, 0.75)
                Text {
                    id: tileViewers
                    anchors.centerIn: parent
                    text: Number(tile.modelData.viewers).toLocaleString(Qt.locale("en_US"), "f", 0) + " viewers"
                    color: Theme.text
                    font.family: Theme.body
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Text {
                parent: tile.thumb
                visible: tile.current
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                text: "PLAYING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileStar.left
                anchors.rightMargin: 4
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.current ? Theme.accent : Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.live ? tile.modelData.title : "Offline"
                    color: Theme.textSoft
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: tile.modelData.live
                    text: {
                        const parts = []
                        if (tile.modelData.game && Streams.twitchView !== "game") parts.push(tile.modelData.game)
                        const t = panel.since(tile.modelData.since)
                        if (t) parts.push(t)
                        return parts.join(" · ")
                    }
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                id: tileStar
                anchors.right: parent.right
                anchors.rightMargin: -6
                y: -6
                width: 30
                height: 30
                icon: "star"
                iconSize: 15
                filled: tile.fav
                color: tile.fav ? Theme.accent : Theme.dim
                tip: tile.fav ? "Remove from favorites" : "Add to favorites"
                onClicked: Streams.toggleFavourite(tile.modelData.login)
            }
        }
    }

    Component {
        id: videoTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingYoutube === modelData.id
            readonly property bool kept: !!modelData.channelId && panel.channels.some((c) => c.id === modelData.channelId && !c.freetube)
            picture: modelData.picture
            onClicked: panel.playRequested({ kind: "youtube", id: modelData.id, title: modelData.title, name: modelData.channel })
            Rectangle {
                parent: tile.thumb
                visible: tile.modelData.duration > 0 || tile.modelData.live
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: tileLength.implicitWidth + 8
                height: tileLength.implicitHeight + 2
                color: tile.modelData.live ? Theme.red : Qt.rgba(0, 0, 0, 0.75)
                Text {
                    id: tileLength
                    anchors.centerIn: parent
                    text: tile.modelData.live ? "LIVE" : panel.clock(tile.modelData.duration)
                    color: Theme.text
                    font.family: Theme.body
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Text {
                parent: tile.thumb
                visible: tile.current
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 4
                text: "WATCHING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileStar.left
                anchors.rightMargin: 4
                spacing: 2
                Text {
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    text: tile.modelData.title
                    color: tile.current ? Theme.accent : Theme.text
                    font.family: Theme.body
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    lineHeight: 1.05
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [tile.modelData.channel, panel.ago(tile.modelData.published)].filter((t) => t).join(" · ")
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                id: tileStar
                visible: !!tile.modelData.channelId
                anchors.right: parent.right
                anchors.rightMargin: -6
                y: -6
                width: visible ? 30 : 0
                height: 30
                icon: "star"
                iconSize: 15
                filled: tile.kept
                color: tile.kept ? Theme.accent : Theme.dim
                tip: tile.kept ? "Remove the channel from My channels" : "Keep the channel in My channels"
                onClicked: Streams.toggleChannel(tile.modelData.channelId, tile.modelData.channel)
            }
        }
    }

    Component {
        id: channelTile
        Item {
            id: tile
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.025)
                Rectangle { width: 2; height: parent.height; color: tile.modelData.freetube ? Theme.track : Theme.accent }
            }
            MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.go({ tab: "youtube", view: "channel", text: "", channel: tile.modelData })
            }
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: tileStar.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: tile.modelData.freetube ? "From FreeTube" : "Kept here"
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            IconButton {
                id: tileStar
                visible: !tile.modelData.freetube
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 30 : 4
                height: 30
                icon: "star"
                iconSize: 15
                filled: true
                color: Theme.accent
                tip: "Remove the channel"
                onClicked: Streams.toggleChannel(tile.modelData.id, tile.modelData.name)
            }
        }
    }

    Component {
        id: jellyRow
        Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: 79
            readonly property bool current: panel.playingJellyfin === modelData.id
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
                onClicked: panel.jfOpen(row.modelData)
            }
            Thumb {
                id: thumb
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                source: row.modelData.picture
                Progress { item: row.modelData }
            }
            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 12
                anchors.right: watched.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
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
                    text: [row.modelData.sub, panel.timeLeft(row.modelData)].filter((t) => t).join(" · ")
                    color: Theme.dim
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            WatchedButton { id: watched; item: row.modelData; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    Component {
        id: jellyTile
        Tile {
            id: tile
            required property var modelData
            current: panel.playingJellyfin === modelData.id
            picture: modelData.picture
            onClicked: panel.jfOpen(modelData)
            Progress { parent: tile.thumb; item: tile.modelData }
            Text {
                parent: tile.thumb
                visible: tile.current
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                text: "PLAYING"
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Column {
                anchors.left: parent.left
                anchors.right: tileWatched.left
                anchors.rightMargin: 2
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.current ? Theme.accent : Theme.text
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [tile.modelData.sub, panel.timeLeft(tile.modelData)].filter((t) => t).join(" · ")
                    color: Theme.muted
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            WatchedButton { id: tileWatched; item: tile.modelData; anchors.right: parent.right; anchors.rightMargin: -6; y: -6 }
        }
    }

    // How far an item is watched: a thin gold line along the picture's foot;
    // a watched one gets a check mark.
    component Progress: Item {
        property var item
        anchors.fill: parent
        Rectangle {
            visible: !!item && item.percent > 0 && !item.played
            anchors.bottom: parent.bottom
            width: parent.width
            height: 3
            color: "#3a3842"
            Rectangle { width: parent.width * (item ? item.percent : 0) / 100; height: 3; color: Theme.accent }
        }
        Rectangle {
            visible: !!item && (item.played || item.unplayed > 0)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            width: Math.max(18, unplayedText.implicitWidth + 8)
            height: 18
            color: item && item.played ? Theme.accent : Qt.rgba(0, 0, 0, 0.75)
            HudIcon { visible: !!item && item.played; anchors.centerIn: parent; name: "check"; size: 12; lineWidth: 2.6; color: "#0c0c0f" }
            Text {
                id: unplayedText
                visible: !!item && !item.played && item.unplayed > 0
                anchors.centerIn: parent
                text: item ? String(item.unplayed) : ""
                color: Theme.text
                font.family: Theme.body
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    // Marks an item watched or not (films and episodes).
    component WatchedButton: IconButton {
        property var item
        visible: !!item && item.playable
        width: visible ? 30 : 0
        height: 30
        icon: "check"
        iconSize: 15
        color: item && item.played ? Theme.accent : Theme.dim
        tip: item && item.played ? "Mark as not watched" : "Mark as watched"
        onClicked: Jellyfin.setPlayed(item.id, !item.played)
    }

    component Thumb: Rectangle {
        property alias source: img.source
        property bool dimmed: false
        width: 112
        height: 63
        color: "#1f1e25"
        clip: true
        Image {
            id: img
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            opacity: parent.dimmed ? 0.5 : 1
            sourceSize.width: 320
        }
    }

    component SiteTab: Item {
        property string name
        property string label
        width: siteText.implicitWidth
        height: 30
        readonly property bool current: Streams.tab === name
        Text {
            id: siteText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: !parent.enabled ? Theme.dim : parent.current ? Theme.accent : (siteMouse.containsMouse ? Theme.text : Theme.muted)
            font.family: Theme.display
            font.pixelSize: 14
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Text {
            visible: !parent.enabled
            anchors.left: siteText.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "NEXT"
            color: Theme.dim
            font.family: Theme.display
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        Rectangle {
            visible: parent.current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.accent
        }
        MouseArea {
            id: siteMouse
            anchors.fill: parent
            enabled: parent.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Streams.tab === parent.name) return
                const view = parent.name === "twitch" ? Streams.twitchView
                    : parent.name === "jellyfin" ? (Jellyfin.view === "folder" || Jellyfin.view === "search" ? "libraries" : Jellyfin.view)
                    : (Streams.youtubeView === "channel" ? "channels" : Streams.youtubeView)
                panel.go({ tab: parent.name, view: view, text: "", channel: null, path: [] })
            }
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }

    component ListTab: Item {
        property string name
        property string label
        property bool purple: false
        property bool searchIcon: false
        property bool twitch: false
        /// "twitch", "youtube" or "jellyfin" (twitch: true says "twitch").
        property string site: twitch ? "twitch" : "youtube"
        readonly property bool current: (site === "jellyfin" ? (Jellyfin.view === "folder" ? "libraries" : Jellyfin.view)
            : site === "twitch" ? Streams.twitchView : (Streams.youtubeView === "channel" ? "channels" : Streams.youtubeView)) === name
        width: searchIcon ? 20 : tabRow.implicitWidth
        height: parent.height
        Row {
            id: tabRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle { visible: purple; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: Theme.purple }
            Text {
                visible: !searchIcon
                text: label.toUpperCase()
                color: current ? Theme.accent : (tabMouse.containsMouse ? Theme.text : Theme.muted)
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            HudIcon {
                visible: searchIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 15
                lineWidth: 2
                color: current ? Theme.accent : (tabMouse.containsMouse ? Theme.text : Theme.muted)
            }
        }
        Rectangle {
            visible: current
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
            onClicked: panel.go({ tab: site, view: name, text: "", channel: null, path: [] })
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: searchIcon ? "Search" : label
    }

    component Field: Rectangle {
        property alias text: input.text
        property string placeholder
        height: 32
        color: "#1b1a20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: Theme.body
            font.pixelSize: 13
            maximumLength: 80
            clip: true
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: parent.parent.placeholder
                color: Theme.dim
                font: input.font
            }
            Accessible.name: parent.placeholder
        }
    }
}
