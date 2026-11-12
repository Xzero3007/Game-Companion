import QtQuick
import QtQuick.Shapes
import GameCompanion
import GameCompanion.Video
import "theme.js" as Theme

// A video over the game: Twitch's or YouTube's, each in its own window.
// Unlocked, the pointer on it shows its bars (name, pin, quality, close;
// pause, volume, time line); it moves by dragging and changes size by the
// corner. Locked, it takes no clicks: they go to the game.
Item {
    id: win
    /// "twitch" or "youtube": the player's slot, remembered under "video-<slot>".
    property string slot
    readonly property string panelId: "video-" + slot
    readonly property string label: slot === "twitch" ? "Twitch" : "YouTube"
    /// What plays: { kind, id, name, title }.
    property var item: null
    readonly property bool active: item !== null
    readonly property bool pinned: Companion.pins.indexOf('"' + panelId + '"') >= 0
    /// Where it starts: bottom left (Twitch) or bottom right (YouTube).
    property bool rightSide: slot === "youtube"
    property string quality: Streams.quality
    /// 0 to 100, as the bars show it.
    property int volume: Streams.volume
    /// How much of the video shows (0.2 to 1).
    property real videoOpacity: 1
    property string via: ""
    signal areaChanged

    width: 432
    height: 243
    onXChanged: areaChanged()
    onYChanged: areaChanged()
    onWidthChanged: areaChanged()
    onHeightChanged: areaChanged()
    onVisibleChanged: areaChanged()

    readonly property bool paused: video.paused
    readonly property bool playing: video.state === "playing" || video.state === "buffering" || video.state === "loading"
    readonly property string playState: !active ? "idle" : video.state

    function play(what) {
        item = what
        load(0)
    }
    function load(start) {
        if (!item) return
        const src = JSON.parse(Streams.source(slot, item.kind, item.id, quality))
        if (src.error) {
            failure = src.error
            return
        }
        failure = ""
        via = src.via
        video.volume = mpvVolume(volume)
        video.play(src.url, src.format, start || 0)
    }
    function stop() {
        video.stop()
        Streams.stopSource(slot)
        item = null
        failure = ""
    }
    function togglePause() {
        if (video.state === "ended" || video.state === "failed" || video.state === "idle") load(0)
        else video.paused = !video.paused
    }
    function setVolume(v) {
        volume = Math.max(0, Math.min(100, v))
        video.volume = mpvVolume(volume)
        Streams.saveVolume(volume)
    }
    // mpv's volume is cubic: the bar works like a browser's.
    function mpvVolume(v) { return 100 * Math.cbrt(v / 100) }
    function setQuality(q) {
        Streams.saveQuality(q)
        quality = q
        const at = item && item.kind === "youtube" ? video.position : 0
        load(at)
    }

    property string failure: ""
    Connections {
        target: Streams
        function onSourceFailed(slot, why) { if (slot === win.slot) win.failure = why }
    }

    // Placed like a panel: where it was left and its size.
    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0 || parent.height <= 0) return
        const saved = Companion.placeOf(panelId)
        if (saved.length > 0) {
            const p = JSON.parse(saved)
            if (p.w > 0) width = Math.max(240, Math.min(p.w, parent.width))
            if (p.grow > 0) height = Math.max(135, Math.min(p.grow, parent.height))
            x = p.x
            y = p.y
        } else {
            x = rightSide ? parent.width - width - 40 : 40
            y = parent.height - height - 120
        }
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - 40))
        placed = true
    }
    Component.onCompleted: place()
    Connections {
        target: win.parent
        function onWidthChanged() { win.place() }
        function onHeightChanged() { win.place() }
    }
    Connections {
        target: Companion
        function onLayoutRevisionChanged() { win.placed = false; win.place() }
    }
    function remember() { Companion.savePlace(panelId, x, y, width, height) }

    Rectangle {
        anchors.fill: parent
        color: "#0e0d11"
        opacity: win.videoOpacity
    }
    MpvVideo {
        id: video
        anchors.fill: parent
        opacity: win.videoOpacity
        visible: drawable
    }
    // Where frames can't be drawn (screenshots), or while it loads.
    Text {
        anchors.centerIn: parent
        visible: !video.drawable || win.playState === "loading" || win.playState === "failed" || win.failure.length > 0
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: win.failure.length > 0 ? win.failure
            : win.playState === "failed" ? "Doesn't play: " + video.error
            : win.playState === "loading" ? "LOADING…"
            : win.label.toUpperCase() + " VIDEO"
        color: win.failure.length > 0 || win.playState === "failed" ? Theme.red : "#5b5866"
        font.family: Theme.display
        font.pixelSize: 13
        font.weight: Font.Bold
        font.letterSpacing: 3
    }
    Rectangle {
        visible: !Companion.locked
        anchors.top: parent.top
        width: parent.width
        height: 2
        color: Theme.accent
    }

    // Hover: the bars (unlocked only; locked, nothing here takes the pointer).
    MouseArea {
        id: hover
        anchors.fill: parent
        enabled: !Companion.locked
        hoverEnabled: true
        drag.target: win
        drag.minimumX: 0
        drag.minimumY: 0
        drag.maximumX: win.parent ? win.parent.width - win.width : 0
        drag.maximumY: win.parent ? win.parent.height - 40 : 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onReleased: win.remember()
        onDoubleClicked: win.togglePause()
    }
    readonly property bool showBars: !Companion.locked && (hover.containsMouse || nativeWindow.demo.indexOf("video") >= 0)

    // Top bar: name, pin, quality, close.
    Rectangle {
        visible: win.showBars
        anchors.top: parent.top
        anchors.topMargin: 2
        width: parent.width
        height: 34
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.85)
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: topButtons.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                color: win.playState === "playing" ? Theme.red : win.playState === "failed" ? Theme.red : Theme.dim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.label.toUpperCase()
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 90
                elide: Text.ElideRight
                text: win.item ? (win.item.kind === "twitch" ? win.item.name + (win.item.game ? " · " + win.item.game : "") : (win.item.title || video.title)) : ""
                color: Theme.textSoft
                font.family: Theme.body
                font.pixelSize: 12
            }
        }
        Row {
            id: topButtons
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: pinRow.implicitWidth + 16
                height: 26
                color: win.pinned ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.16) : "transparent"
                Row {
                    id: pinRow
                    anchors.centerIn: parent
                    spacing: 4
                    HudIcon { anchors.verticalCenter: parent.verticalCenter; name: "pin"; size: 12; filled: win.pinned; color: win.pinned ? Theme.accent : Theme.muted }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.pinned ? "PINNED" : "PIN"
                        color: win.pinned ? Theme.accent : Theme.muted
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Companion.togglePin(win.panelId)
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: win.pinned ? "Pinned: stays when the hub is hidden" : "Pin: stay when the hub is hidden"
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: qualityText.implicitWidth + 14
                height: 26
                Text {
                    id: qualityText
                    anchors.centerIn: parent
                    text: win.quality === "audio" ? "SOUND" : win.quality + "P"
                    color: qualityMouse.containsMouse ? Theme.text : Theme.muted
                    font.family: Theme.display
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
                MouseArea {
                    id: qualityMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Steps through the qualities.
                    onClicked: {
                        const all = ["1080", "720", "480", "360", "audio"]
                        win.setQuality(all[(all.indexOf(win.quality) + 1) % all.length])
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Quality " + qualityText.text + " (click: the next one)"
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                iconSize: 12
                color: Theme.muted
                tip: "Close the video"
                onClicked: win.stop()
            }
        }
    }

    // Bottom bar: pause, volume, time line, opacity, the size corner.
    Rectangle {
        id: bottomBar
        visible: win.showBars
        anchors.bottom: parent.bottom
        width: parent.width
        height: 38
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.85)
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: win.playing && !video.paused ? "pause" : "play"
                filled: !(win.playing && !video.paused)
                tip: win.playing && !video.paused ? "Pause" : "Play"
                onClicked: win.togglePause()
            }
            VolumeBar {
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                value: win.volume
                onStepped: (d) => win.setVolume(win.volume + d)
                onPicked: (v) => win.setVolume(v)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: video.duration > 0
                text: win.clock(video.position) + " / " + win.clock(video.duration)
                color: Theme.muted
                font.family: Theme.body
                font.pixelSize: 11
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: video.duration > 0
                icon: "prev"
                iconSize: 11
                tip: "Back 10 seconds"
                onClicked: video.seek(-10, true)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: video.duration > 0
                icon: "next"
                iconSize: 11
                tip: "On 30 seconds"
                onClicked: video.seek(30, true)
            }
        }
        Item {
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            width: opacityText.implicitWidth + 12
            height: 26
            Text {
                id: opacityText
                anchors.centerIn: parent
                text: "◐ " + Math.round(win.videoOpacity * 100) + "%"
                color: opacityMouse.containsMouse ? Theme.text : Theme.muted
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            MouseArea {
                id: opacityMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // 100, 80, 60, 40, 20, then 100 again; the wheel steps by 10.
                onClicked: win.videoOpacity = win.videoOpacity <= 0.21 ? 1 : Math.round((win.videoOpacity - 0.2) * 10) / 10
                onWheel: (w) => win.videoOpacity = Math.max(0.2, Math.min(1, Math.round((win.videoOpacity + (w.angleDelta.y > 0 ? 0.1 : -0.1)) * 10) / 10))
            }
            Accessible.role: Accessible.Button
            Accessible.name: "How much of the video shows: " + opacityText.text
        }
    }
    // Time line, along the bottom bar's top edge.
    Rectangle {
        visible: win.showBars && video.duration > 0
        anchors.bottom: bottomBar.top
        width: parent.width
        height: 4
        color: "#3a3842"
        Rectangle {
            width: video.duration > 0 ? parent.width * video.position / video.duration : 0
            height: parent.height
            color: Theme.accent
        }
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => video.seek(video.duration * m.x / width, false)
        }
    }

    function clock(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        const two = (n) => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
    }

    // The size corner (unlocked): 16:9 kept.
    Item {
        visible: !Companion.locked
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 18
        height: 18
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: "transparent"
                fillColor: Theme.accent
                startX: 18; startY: 4
                PathLine { x: 18; y: 18 }
                PathLine { x: 4; y: 18 }
                PathLine { x: 18; y: 4 }
            }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.SizeFDiagCursor
            property point start
            property real startWidth
            onPressed: (m) => { start = mapToItem(null, m.x, m.y); startWidth = win.width }
            onPositionChanged: (m) => {
                if (!pressed) return
                const p = mapToItem(null, m.x, m.y)
                const room = win.parent ? Math.min(win.parent.width - win.x, (win.parent.height - win.y) * 16 / 9) : 1920
                win.width = Math.max(240, Math.min(startWidth + p.x - start.x, room))
                win.height = Math.round(win.width * 9 / 16)
            }
            onReleased: win.remember()
        }
        Accessible.role: Accessible.Grip
        Accessible.name: "Resize the video"
    }
}
