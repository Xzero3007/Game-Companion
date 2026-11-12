import QtQuick
import GameCompanion
import "theme.js" as Theme

// Streams: Twitch and YouTube (Jellyfin next). The running game's lists
// come first, under its purple tag; a click plays in that site's video
// window over the game.
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

    readonly property var game: JSON.parse(Streams.game)
    readonly property var twitchList: JSON.parse(Streams.twitch)
    readonly property var youtubeList: JSON.parse(Streams.youtube)
    readonly property var favs: JSON.parse(Streams.favourites)
    readonly property var channels: JSON.parse(Streams.channels)
    readonly property var account: JSON.parse(Streams.account)
    readonly property bool onTwitch: Streams.tab === "twitch"
    property bool editingGame: false
    /// YouTube: the channel whose videos show ("" for none).
    property var channel: null

    badge: onTwitch ? (Streams.twitchState === "ready" ? Streams.twitchMessage.toUpperCase() : "")
        : (Streams.youtubeState === "ready" ? Streams.youtubeMessage.toUpperCase() : "")

    property bool loadedOnce: false
    onVisibleChanged: if (visible && !loadedOnce) firstLoad()
    Component.onCompleted: if (visible) firstLoad()
    function firstLoad() {
        loadedOnce = true
        Streams.refreshAccount()
        reload()
    }
    function reload() {
        if (onTwitch) {
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
        if (!onTwitch) {
            // A pasted link plays at once.
            const id = Streams.videoId(text)
            if (id.length > 0) { panel.playRequested({ kind: "youtube", id: id, title: "", name: "" }); return }
            Streams.loadYoutube("search", text)
        } else {
            Streams.loadTwitch("search", text)
        }
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
    function since(iso) {
        if (!iso) return ""
        const m = Math.round((Date.now() - Date.parse(iso)) / 60000)
        if (!(m >= 0)) return ""
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    Column {
        width: parent.width
        spacing: 10

        // Twitch / YouTube / Jellyfin
        Row {
            spacing: 18
            height: 30
            SiteTab { name: "twitch"; label: "Twitch" }
            SiteTab { name: "youtube"; label: "YouTube" }
            SiteTab { name: "jellyfin"; label: "Jellyfin"; enabled: false }
        }

        // The game's preset, in purple.
        Rectangle {
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
                visible: !panel.onTwitch
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
            visible: (panel.onTwitch ? Streams.twitchView : Streams.youtubeView) === "search"
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
                    text: panel.onTwitch ? "A channel's name, then Enter" : "Search words or a video's link, then Enter"
                    color: Theme.dim
                    font: search.font
                }
                Accessible.name: panel.onTwitch ? "Search Twitch" : "Search YouTube"
            }
        }

        // The channel whose videos show (My channels → one).
        Row {
            visible: !panel.onTwitch && Streams.youtubeView === "channel" && panel.channel !== null
            spacing: 10
            TextButton { text: "‹ Channels"; onClicked: { panel.channel = null; Streams.loadYoutube("channels", "") } }
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
            x: -14
            width: parent.width + 28
            height: 79 * 4 + panel.grow
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !(!panel.onTwitch && Streams.youtubeView === "channels")
                model: panel.onTwitch ? panel.twitchList : panel.youtubeList
                delegate: panel.onTwitch ? twitchRow : videoRow
            }
            ListView {
                id: channelList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !panel.onTwitch && Streams.youtubeView === "channels"
                model: panel.channels
                delegate: channelRow
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                readonly property string st: panel.onTwitch ? Streams.twitchState : Streams.youtubeState
                readonly property int count: channelList.visible ? panel.channels.length : list.count
                visible: st === "loading" || st === "failed" || count === 0
                text: st === "loading" ? "Loading…"
                    : st === "failed" ? (panel.onTwitch ? Streams.twitchMessage : Streams.youtubeMessage)
                    : channelList.visible ? "No channels yet: FreeTube's subscriptions show here, and channels you keep with the star beside a video."
                    : (panel.onTwitch ? Streams.twitchView : Streams.youtubeView) === "search" ? "Type, then Enter."
                    : panel.onTwitch && Streams.twitchView === "favourites" ? "No favorites yet: the star beside a channel keeps it."
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
                    text: panel.onTwitch
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
                onClicked: panel.reload()
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
                onClicked: { panel.channel = row.modelData; Streams.loadYoutube("channel", row.modelData.id) }
            }
            Column {
                x: 14
                anchors.right: star.left
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
            sourceSize.width: 224
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
                Streams.chooseTab(parent.name)
                panel.reload()
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
        readonly property bool current: (twitch ? Streams.twitchView : (Streams.youtubeView === "channel" ? "channels" : Streams.youtubeView)) === name
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
            onClicked: {
                if (twitch) {
                    if (name === "search") { Streams.loadTwitch("search", ""); search.forceActiveFocus(); return }
                    Streams.loadTwitch(name, "")
                } else {
                    panel.channel = null
                    if (name === "search") { Streams.loadYoutube("search", ""); search.forceActiveFocus(); return }
                    if (name === "channels") { Streams.loadYoutube("channels", ""); return }
                    Streams.loadYoutube(name, "")
                }
            }
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
