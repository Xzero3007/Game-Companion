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
    readonly property var keys: JSON.parse(Companion.shortcuts)

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
        if (Companion.shown) {
            if (Companion.locked) {
                rects.push(rectOf(bar.lockButton))
            } else {
                rects.push(rectOf(bar))
                for (const panel of [welcome, settings]) {
                    if (panel.visible) rects.push(rectOf(panel))
                }
            }
        }
        nativeWindow.setInputRects(rects)
        nativeWindow.setKeyboard(Companion.shown && !Companion.locked)
    }
    function requestInput() { Qt.callLater(updateInput) }

    Component.onCompleted: {
        const demo = nativeWindow.demo.split(",")
        if (demo.indexOf("unlocked") >= 0 && Companion.locked) Companion.toggleLocked()
        if (demo.indexOf("settings") >= 0) settingsOpen = true
        requestInput()
    }
    onWidthChanged: requestInput()
    onHeightChanged: requestInput()

    Connections {
        target: Companion
        function onLockedChanged() { root.requestInput() }
        function onShownChanged() { root.requestInput() }
        function onWelcomeChanged() { root.requestInput() }
    }

    Item {
        id: scene
        anchors.fill: parent
        visible: Companion.shown

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
            visible: !Companion.locked
            lockKey: root.keyOf("lock")
        }

        HudBar {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            settingsOpen: root.settingsOpen
            onSettingsClicked: root.settingsOpen = !root.settingsOpen
            onHideClicked: Companion.toggleShown()
            onWidthChanged: root.requestInput()
            onXChanged: root.requestInput()
        }

        WelcomePanel {
            id: welcome
            visible: Companion.welcome
            defaultX: 24
            defaultY: 120
            onAreaChanged: root.requestInput()
        }

        SettingsPanel {
            id: settings
            visible: root.settingsOpen
            defaultX: scene.width - width - 24
            defaultY: 120
            onCloseClicked: root.settingsOpen = false
            onAreaChanged: root.requestInput()
        }
    }
}
