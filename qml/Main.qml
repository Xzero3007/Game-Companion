import QtQuick
import GameCompanion

// The overlay: one transparent window over the whole screen. Only the bar
// and the panels take clicks (the input region); everywhere else clicks go
// to the game. Locked, only the lock button takes them.
Window {
    id: root
    visible: false          // shown by the native side once it is on the overlay layer
    color: "transparent"
    title: "Game Companion"
    width: 1280
    height: 720

    property bool settingsOpen: false
    property bool radioOpen: false
    property bool streamsOpen: false
    readonly property var keys: JSON.parse(Companion.shortcuts)
    readonly property var pins: JSON.parse(Companion.pins)

    // On screen: with the hub, or pinned while it is hidden.
    function onScreen(id) { return Companion.shown || pins.indexOf(id) >= 0 }

    function keyOf(id) {
        for (const k of keys) if (k.id === id) return k.key
        return ""
    }

    function rectOf(item) {
        const p = item.mapToItem(null, 0, 0)
        return Qt.rect(p.x, p.y, item.width, item.height)
    }

    // The input region: what takes clicks right now.
    function updateInput() {
        const rects = []
        if (Companion.locked) {
            if (bar.visible) rects.push(rectOf(bar.lockButton))
        } else {
            for (const item of [bar, playerRow, welcome, settings, radio, streams, twitchVideo, youtubeVideo]) {
                if (item.visible) rects.push(rectOf(item))
            }
        }
        nativeWindow.setInputRects(rects)
        nativeWindow.setKeyboard(!Companion.locked && rects.length > 0)
    }
    function requestInput() { Qt.callLater(updateInput) }

    // Layouts: which panels are open (Settings itself is not part of one).
    function openPanels() {
        const ids = []
        if (radioOpen) ids.push("radio")
        if (streamsOpen) ids.push("streams")
        return ids
    }
    function openFrom(ids) {
        radioOpen = ids.indexOf("radio") >= 0
        streamsOpen = ids.indexOf("streams") >= 0
    }

    Component.onCompleted: {
        const demo = nativeWindow.demo.split(",")
        if (demo.indexOf("unlocked") >= 0 && Companion.locked) Companion.toggleLocked()
        if (demo.indexOf("settings") >= 0) settingsOpen = true
        if (demo.indexOf("radio") >= 0) radioOpen = true
        if (demo.indexOf("streams") >= 0) streamsOpen = true
        if (demo.indexOf("video") >= 0) twitchVideo.item = { kind: "twitch", id: "streamer_one", name: "streamer_one", game: "AION 2", title: "" }
        if (nativeWindow.testVideo.length > 0) twitchVideo.playFile(nativeWindow.testVideo)
        if (demo.indexOf("hidden") >= 0 && Companion.shown) Companion.toggleShown()
        requestInput()
    }
    onWidthChanged: requestInput()
    onHeightChanged: requestInput()

    Connections {
        target: Companion
        function onLockedChanged() { root.requestInput() }
        function onWelcomeChanged() { root.requestInput() }
        function onPinsChanged() { root.requestInput() }
        function onShownChanged() { root.requestInput(); if (!Companion.shown) hubHint.flash() }
    }

    Item {
        id: scene
        anchors.fill: parent

        // Screenshots only (GC_DEMO=backdrop): a stand-in for the game.
        Rectangle {
            anchors.fill: parent
            visible: nativeWindow.demo.indexOf("backdrop") >= 0
            color: "#262a2e"
            Text {
                anchors.centerIn: parent
                text: "GAME VIEW"
                color: "#4c5157"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.letterSpacing: 6
            }
        }

        UnlockedFrame {
            anchors.fill: parent
            visible: !Companion.locked && (Companion.shown || root.pins.length > 0)
            lockKey: root.keyOf("lock")
        }

        HudBar {
            id: bar
            visible: Companion.shown
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            settingsOpen: root.settingsOpen
            radioOpen: root.radioOpen
            streamsOpen: root.streamsOpen
            onStreamsClicked: root.streamsOpen = !root.streamsOpen
            onSettingsClicked: root.settingsOpen = !root.settingsOpen
            onUpdateClicked: { root.settingsOpen = true; Updates.install() }
            onRadioClicked: root.radioOpen = !root.radioOpen
            onHideClicked: Companion.toggleShown()
            onWidthChanged: root.requestInput()
            onXChanged: root.requestInput()
            onVisibleChanged: root.requestInput()
        }

        // Videos sit under the panels, over the game.
        VideoWindow {
            id: twitchVideo
            z: fullScreen ? 100 : 0
            slot: "twitch"
            visible: active && root.onScreen(panelId)
            onAreaChanged: root.requestInput()
        }
        VideoWindow {
            id: youtubeVideo
            z: fullScreen ? 100 : 0
            slot: "youtube"
            visible: active && root.onScreen(panelId)
            onAreaChanged: root.requestInput()
        }

        PlayerRow {
            id: playerRow
            videos: [twitchVideo, youtubeVideo]
            visible: active && root.onScreen("player-row")
            anchors.horizontalCenter: parent.horizontalCenter
            y: Companion.shown ? bar.height : 0
            onWidthChanged: root.requestInput()
            onXChanged: root.requestInput()
            onYChanged: root.requestInput()
            onVisibleChanged: root.requestInput()
        }

        HubHint {
            id: hubHint
            anchors.horizontalCenter: parent.horizontalCenter
            y: playerRow.visible ? playerRow.height + 6 : 6
            key: root.keyOf("toggle")
        }

        WelcomePanel {
            id: welcome
            visible: Companion.welcome && Companion.shown
            defaultX: 24
            defaultY: 120
            onAreaChanged: root.requestInput()
        }

        RadioPanel {
            id: radio
            visible: root.radioOpen && root.onScreen("radio")
            defaultX: 24
            defaultY: 120
            onCloseClicked: root.radioOpen = false
            onAreaChanged: root.requestInput()
        }

        StreamsPanel {
            id: streams
            visible: root.streamsOpen && root.onScreen("streams")
            defaultX: 520
            defaultY: 120
            playingTwitch: twitchVideo.item && twitchVideo.item.kind === "twitch" ? twitchVideo.item.id : ""
            playingYoutube: youtubeVideo.item && youtubeVideo.item.kind === "youtube" ? youtubeVideo.item.id : ""
            onCloseClicked: root.streamsOpen = false
            onAreaChanged: root.requestInput()
            onPlayRequested: (what) => (what.kind === "twitch" ? twitchVideo : youtubeVideo).play(what)
        }

        SettingsPanel {
            id: settings
            pinnable: false
            visible: root.settingsOpen && Companion.shown
            defaultX: scene.width - width - 24
            defaultY: 120
            onCloseClicked: root.settingsOpen = false
            onAreaChanged: root.requestInput()
            onSaveLayoutRequested: (name) => Companion.saveLayout(name, JSON.stringify(root.openPanels()))
            onLoadLayoutRequested: (name) => {
                const open = Companion.loadLayout(name)
                if (open.length > 0) root.openFrom(JSON.parse(open))
            }
        }
    }
}
