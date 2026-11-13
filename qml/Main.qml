import QtQuick
import GameCompanion
import "theme.js" as Theme

// The overlay: every part (the bar, the player row, each panel, each
// video) in a small window of its own on the overlay layer (Surface), as
// big as the part; the rest of the screen is the game's. Locked, only the
// lock button takes clicks. Parts are placed in screen coordinates.
// The root is no Item (see Overlay.qml).
Overlay {
    id: root
    readonly property real width: nativeWindow.screenWidth
    readonly property real height: nativeWindow.screenHeight

    property bool settingsOpen: false
    property bool radioOpen: false
    property bool streamsOpen: false
    property bool gamesOpen: false
    readonly property var keys: JSON.parse(Companion.shortcuts)
    readonly property var pins: JSON.parse(Companion.pins)

    // On screen: with the hub, or pinned while it is hidden.
    function onScreen(id) { return Companion.shown || pins.indexOf(id) >= 0 }

    function keyOf(id) {
        for (const k of keys) if (k.id === id) return k.key
        return ""
    }

    // Layouts: which panels are open (Settings itself is not part of one).
    function openPanels() {
        const ids = []
        if (gamesOpen) ids.push("games")
        if (radioOpen) ids.push("radio")
        if (streamsOpen) ids.push("streams")
        return ids
    }
    function openFrom(ids) {
        gamesOpen = ids.indexOf("games") >= 0
        radioOpen = ids.indexOf("radio") >= 0
        streamsOpen = ids.indexOf("streams") >= 0
    }

    Component.onCompleted: {
        const demo = nativeWindow.demo.split(",")
        if (demo.indexOf("unlocked") >= 0 && Companion.locked) Companion.toggleLocked()
        if (demo.indexOf("settings") >= 0) settingsOpen = true
        if (demo.indexOf("radio") >= 0) radioOpen = true
        if (demo.indexOf("games") >= 0) gamesOpen = true
        if (demo.indexOf("gameform") >= 0) games.editing = {}
        if (demo.indexOf("streams") >= 0) streamsOpen = true
        if (demo.indexOf("video") >= 0) twitchVideo.item = { kind: "twitch", id: "streamer_one", name: "streamer_one", game: "AION 2", title: "" }
        if (demo.indexOf("jellyvideo") >= 0) jellyfinVideo.demo()
        if (nativeWindow.testVideo.length > 0) Qt.callLater(() => twitchVideo.playFile(nativeWindow.testVideo))
        if (demo.indexOf("hidden") >= 0 && Companion.shown) Companion.toggleShown()
    }


    Connections {
        target: Companion
        function onShownChanged() { if (!Companion.shown) hubHint.flash() }
    }

    // A game started: its preset search in Streams, and what the user
    // picked for its start (show the hub, start the radio).
    // Shown because a game started: hidden again when it ends.
    property bool shownForGame: false
    Connections {
        target: Companion
        function onShownChanged() { if (!Companion.shown) root.shownForGame = false }
    }
    Connections {
        target: Games
        function onStopped(id) {
            if (root.shownForGame && Companion.shown) Companion.toggleShown()
            root.shownForGame = false
        }
        function onStarted(id) {
            // Built-in games no launcher lists (known:…) are not in the library.
            const g = JSON.parse(Games.library).find((x) => x.id === id)
                || { name: Games.runningName, twitch: Games.twitchPreset, youtube: Games.youtubePreset, showOnStart: true, radioOnStart: false }
            if (g.twitch.length > 0 || g.youtube.length > 0) Streams.changeGame(g.name, g.twitch, g.youtube)
            if (g.showOnStart && !Companion.shown) { Companion.toggleShown(); root.shownForGame = true }
            if (g.layout && g.layout.length > 0) {
                const open = Companion.loadLayout(g.layout)
                if (open.length > 0) root.openFrom(JSON.parse(open))
            }
            if (g.radioOnStart) {
                // The last station, unless something plays already.
                const recent = JSON.parse(Radio.recent)
                if (Radio.status === "paused") Radio.togglePause()
                else if (Radio.status === "idle" && recent.length > 0) Radio.play(recent[0])
            }
        }
    }


    // Screenshots (GC_SCREENSHOT): every part in one window, grabbed whole.
    Window {
        visible: nativeWindow.screenshotMode
        width: root.width
        height: root.height
        color: "transparent"
        title: "Game Companion screenshot"
        Item {
            id: shotScene
            anchors.fill: parent
            Component.onCompleted: nativeWindow.shotScene = shotScene
        }
    }

    // Screenshots only (GC_DEMO=backdrop): a stand-in for the game
    // (GC_DEMO=backdrop,bright: a light sky, the hardest ground for text).
    Surface {
        wanted: nativeWindow.demo.indexOf("backdrop") >= 0
        clickable: false
        stack: -1
        part: Rectangle {
            width: root.width
            height: root.height
            color: "#262a2e"
            gradient: nativeWindow.demo.indexOf("bright") >= 0 ? sky : null
            Gradient {
                id: sky
                GradientStop { position: 0; color: "#c9d2dc" }
                GradientStop { position: 0.6; color: "#e9edf1" }
                GradientStop { position: 1; color: "#8f9fb2" }
            }
            Text {
                anchors.centerIn: parent
                text: "GAME VIEW"
                color: "#4c5157"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.letterSpacing: 6
            }
        }
    }

    Surface {
        wanted: Companion.shown
        stack: 5
        lockItem: bar.lockButton
        extra: bar.tipShown ? Qt.rect(0, 0, bar.width, bar.height + 40) : Qt.rect(0, 0, 0, 0)
        part: HudBar {
            id: bar
            // Sideways where the user left it, never off the screen.
            transformOrigin: Item.TopLeft
            scale: Companion.barScale
            readonly property real shownWidth: width * scale
            x: Math.max(0, Math.min(root.width - shownWidth, (root.width - shownWidth) / 2 + Companion.barOffset + dragShift))
            y: 0
            settingsOpen: root.settingsOpen
            radioOpen: root.radioOpen
            gamesOpen: root.gamesOpen
            onGamesClicked: root.gamesOpen = !root.gamesOpen
            gameName: Games.runningName
            gameHasModule: Games.runningKnown.length > 0
            streamsOpen: root.streamsOpen
            onStreamsClicked: root.streamsOpen = !root.streamsOpen
            onSettingsClicked: root.settingsOpen = !root.settingsOpen
            onUpdateClicked: { root.settingsOpen = true; Updates.install() }
            onRadioClicked: root.radioOpen = !root.radioOpen
            onHideClicked: Companion.toggleShown()
            onDropped: {
                Companion.saveBarOffset(x - (root.width - shownWidth) / 2)
                dragShift = 0
            }
        }
    }

    // Videos sit under the panels, over the game; full screen, the video's
    // window covers the screen.
    Surface {
        wanted: twitchVideo.active && root.onScreen(twitchVideo.panelId)
        stack: twitchVideo.fullScreen ? 100 : 2
        part: VideoWindow { id: twitchVideo; slot: "twitch" }
    }
    Surface {
        wanted: youtubeVideo.active && root.onScreen(youtubeVideo.panelId)
        stack: youtubeVideo.fullScreen ? 100 : 2
        part: VideoWindow { id: youtubeVideo; slot: "youtube" }
    }
    Surface {
        wanted: jellyfinVideo.active && root.onScreen(jellyfinVideo.panelId)
        stack: jellyfinVideo.fullScreen ? 100 : 2
        part: VideoWindow { id: jellyfinVideo; slot: "jellyfin" }
    }

    Surface {
        wanted: playerRow.active && root.onScreen("player-row")
        stack: 5
        part: PlayerRow {
            id: playerRow
            videos: [twitchVideo, youtubeVideo, jellyfinVideo]
            // Under the bar, as big as it, following it sideways.
            transformOrigin: Item.TopLeft
            scale: Companion.barScale
            x: Math.max(0, Math.min(root.width - width * scale, bar.x + (bar.shownWidth - width * scale) / 2))
            y: Companion.shown ? bar.height * bar.scale : 0
        }
    }

    Surface {
        wanted: hubHint.opacity > 0
        clickable: false
        stack: 6
        part: HubHint {
            id: hubHint
            x: (root.width - width) / 2
            y: playerRowShown ? playerRow.y + playerRow.height * playerRow.scale + 6 : 6
            readonly property bool playerRowShown: playerRow.active && root.onScreen("player-row")
            key: root.keyOf("toggle")
        }
    }

    Surface {
        wanted: Companion.welcome && Companion.shown
        stack: 3
        part: WelcomePanel {
            id: welcome
            defaultX: 24
            defaultY: 120
        }
    }

    Surface {
        wanted: root.gamesOpen && root.onScreen("games")
        stack: 3
        part: GamesPanel {
            id: games
            defaultX: Math.max(24, (root.width - width) / 2)
            defaultY: 120
            onCloseClicked: root.gamesOpen = false
        }
    }

    Surface {
        wanted: root.radioOpen && root.onScreen("radio")
        stack: 3
        part: RadioPanel {
            id: radio
            defaultX: 24
            defaultY: 120
            onCloseClicked: root.radioOpen = false
        }
    }

    Surface {
        wanted: root.streamsOpen && root.onScreen("streams")
        stack: 3
        part: StreamsPanel {
            id: streams
            defaultX: 520
            defaultY: 120
            playingTwitch: twitchVideo.item && twitchVideo.item.kind === "twitch" ? twitchVideo.item.id : ""
            playingYoutube: youtubeVideo.item && youtubeVideo.item.kind === "youtube" ? youtubeVideo.item.id : ""
            playingJellyfin: jellyfinVideo.item ? jellyfinVideo.item.id : ""
            onCloseClicked: root.streamsOpen = false
            onPlayRequested: (what) => (what.kind === "twitch" ? twitchVideo : what.kind === "jellyfin" ? jellyfinVideo : youtubeVideo).play(what)
        }
    }

    Surface {
        wanted: root.settingsOpen && Companion.shown
        stack: 4
        part: SettingsPanel {
            id: settings
            pinnable: false
            defaultX: root.width - width - 24
            defaultY: 120
            onCloseClicked: root.settingsOpen = false
            onSaveLayoutRequested: (name) => Companion.saveLayout(name, JSON.stringify(root.openPanels()))
            onLoadLayoutRequested: (name) => {
                const open = Companion.loadLayout(name)
                if (open.length > 0) root.openFrom(JSON.parse(open))
            }
        }
    }

}
