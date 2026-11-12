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
    /// How much of the video shows (0.5 to 1), kept for each window.
    property real videoOpacity: Streams.opacityOf(slot) / 100
    function setOpacity(o) {
        videoOpacity = Math.max(0.5, Math.min(1, Math.round(o * 10) / 10))
        Streams.saveOpacity(slot, Math.round(videoOpacity * 100))
    }
    readonly property var qualities: [
        { id: "best", name: "SOURCE" }, { id: "1080", name: "1080P" }, { id: "720", name: "720P" },
        { id: "480", name: "480P" }, { id: "360", name: "360P" }, { id: "audio", name: "SOUND ONLY" }
    ]
    readonly property var opacities: [
        { id: "100", name: "100 %" }, { id: "90", name: "90 %" }, { id: "80", name: "80 %" },
        { id: "70", name: "70 %" }, { id: "60", name: "60 %" }, { id: "50", name: "50 %" }
    ]
    function qualityName(q) {
        for (const o of qualities) if (o.id === q) return o.name
        return q + "P"
    }
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
        tries = 0
        segments = []
        skipped = ({})
        skipNote = ""
        load(0)
        if (what.kind === "youtube") Streams.loadSegments(slot, what.id)
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
    // Development only (GC_TEST_VIDEO): a local file, to check the drawing.
    function playFile(path) {
        item = { kind: "file", id: path, name: "test", title: path }
        video.play(path, "", 0)
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
    // Stuck: the time stands still for 4 seconds while it should play (20
    // while it loads): a fresh address from yt-dlp (or Streamlink), at the
    // same spot. Three tries in a row, then it says so.
    property real lastPosition: -1
    property int stillFor: 0
    property int tries: 0
    property int goodFor: 0
    property bool reconnecting: false
    Timer {
        interval: 1000
        repeat: true
        running: win.active && win.item.kind !== "file" && !video.paused
            && (video.state === "playing" || video.state === "buffering" || video.state === "loading")
        onRunningChanged: { win.stillFor = 0; win.lastPosition = video.position }
        onTriggered: {
            if (Math.abs(video.position - win.lastPosition) > 0.05 && video.state !== "loading") {
                win.lastPosition = video.position
                win.stillFor = 0
                win.reconnecting = false
                if (++win.goodFor >= 30) win.tries = 0
                return
            }
            win.goodFor = 0
            win.stillFor++
            if (win.stillFor >= (video.state === "loading" ? 20 : 4)) win.reconnect()
        }
    }
    function reconnect() {
        stillFor = 0
        if (tries >= 3) {
            reconnecting = false
            failure = "Stuck: it played no further after three new tries. Play starts it again."
            video.stop()
            return
        }
        tries++
        reconnecting = true
        const at = item.kind === "youtube" ? Math.max(0, video.position) : 0
        load(at)
    }

    // SponsorBlock (when on in Settings): its parts marked on the time line,
    // those set to skip jumped over, with a moment to go back.
    property var segments: []
    property var skipped: ({})
    property var lastSkip: null
    property string skipNote: ""
    readonly property var segmentNames: ({
        sponsor: "Sponsor", selfpromo: "Self-promotion", interaction: "Interaction reminder", intro: "Intro",
        outro: "Outro", preview: "Preview", filler: "Filler", music_offtopic: "Non-music part"
    })
    function segmentColor(c) {
        return ({ sponsor: "#5fcf7a", selfpromo: "#e8d44d", interaction: "#c4a8f0", intro: "#a9a6b2",
                  outro: "#6f6b78", preview: "#e07a3c", filler: "#9b6be8", music_offtopic: "#f2c46b" })[c] || Theme.muted
    }
    Connections {
        target: Streams
        function onSegmentsLoaded(slot, id, list) {
            if (slot !== win.slot || !win.item || win.item.id !== id) return
            win.segments = JSON.parse(list)
            win.skipped = ({})
        }
    }
    Connections {
        target: video
        function onPositionChanged() {
            const at = video.position
            for (let i = 0; i < win.segments.length; i++) {
                const seg = win.segments[i]
                if (seg.mode !== "skip" || win.skipped[i]) continue
                if (at >= seg.start && at < seg.end - 0.5) {
                    const done = win.skipped
                    done[i] = true
                    win.skipped = done
                    win.lastSkip = seg
                    win.skipNote = "SKIPPED: " + (win.segmentNames[seg.category] || seg.category).toUpperCase()
                    skipNoteTimer.restart()
                    video.seek(seg.end, false)
                    return
                }
            }
        }
    }
    Timer { id: skipNoteTimer; interval: 6000; onTriggered: win.skipNote = "" }

    // Full screen: over everything, the game and the panels; Esc or the
    // button leaves it. Where it was is kept.
    property bool fullScreen: false
    property rect before
    function toggleFullScreen() {
        if (!parent) return
        if (!fullScreen) {
            before = Qt.rect(x, y, width, height)
            fullScreen = true
            fitScreen()
        } else {
            fullScreen = false
            x = before.x; y = before.y; width = before.width; height = before.height
        }
    }
    function fitScreen() { x = 0; y = 0; width = parent.width; height = parent.height }
    onActiveChanged: if (!active && fullScreen) toggleFullScreen()
    Shortcut {
        sequence: "Escape"
        enabled: win.fullScreen && !Companion.locked
        onActivated: win.toggleFullScreen()
    }

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
    Component.onCompleted: {
        place()
        // Screenshots: GC_DEMO=video,quality or video,opacity opens that list.
        if (nativeWindow.demo.indexOf("quality") >= 0) qualityPicker.open = true
        if (nativeWindow.demo.indexOf("opacity") >= 0) opacityPicker.open = true
        if (nativeWindow.demo.indexOf("fullscreen") >= 0) Qt.callLater(toggleFullScreen)
        if (nativeWindow.demo.indexOf("sponsor") >= 0) {
            segments = [{ category: "sponsor", start: 1, end: 2.5, mode: "skip" }, { category: "outro", start: 6.5, end: 8, mode: "show" }]
            lastSkip = segments[0]
            skipNote = "SKIPPED: SPONSOR"
        }
    }
    Connections {
        target: win.parent
        function onWidthChanged() { win.place(); if (win.fullScreen) win.fitScreen() }
        function onHeightChanged() { win.place(); if (win.fullScreen) win.fitScreen() }
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
        visible: !video.drawable || win.playState === "loading" || win.reconnecting || win.playState === "failed" || win.failure.length > 0
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: win.failure.length > 0 ? win.failure
            : win.playState === "failed" ? "Doesn't play: " + video.error
            : win.reconnecting ? "RECONNECTING…"
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

    // The pointer anywhere on the window, its buttons too, keeps the bars;
    // they go a moment after it leaves (no flicker between the buttons).
    HoverHandler {
        id: pointerOn
        enabled: !Companion.locked
    }
    readonly property bool barsWanted: pointerOn.hovered || qualityPicker.open || opacityPicker.open
    onBarsWantedChanged: if (!barsWanted) barsLinger.restart()
    Timer { id: barsLinger; interval: 700 }

    // Dragging, and a double click pauses (unlocked only; locked, nothing
    // here takes the pointer).
    MouseArea {
        id: hover
        anchors.fill: parent
        enabled: !Companion.locked
        hoverEnabled: true
        drag.target: win.fullScreen ? null : win
        drag.minimumX: 0
        drag.minimumY: 0
        drag.maximumX: win.parent ? win.parent.width - win.width : 0
        drag.maximumY: win.parent ? win.parent.height - 40 : 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onReleased: if (!win.fullScreen) win.remember()
        onDoubleClicked: win.togglePause()
    }
    readonly property bool showBars: !Companion.locked && (barsWanted || barsLinger.running || nativeWindow.demo.indexOf("video") >= 0)
    onShowBarsChanged: if (!showBars) { qualityPicker.open = false; opacityPicker.open = false }

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
                    text: win.qualityName(win.quality) + " ▾"
                    color: qualityPicker.open ? Theme.accent : qualityMouse.containsMouse ? Theme.text : Theme.muted
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
                    onClicked: { opacityPicker.open = false; qualityPicker.open = !qualityPicker.open }
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Quality: " + win.qualityName(win.quality)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: win.fullScreen ? "shrink" : "expand"
                iconSize: 13
                color: win.fullScreen ? Theme.accent : Theme.muted
                tip: win.fullScreen ? "Leave full screen (Esc)" : "Full screen"
                onClicked: win.toggleFullScreen()
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
            SeekButton { back: true }
            SeekButton { back: false }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Small, the time line's own label says it.
                visible: video.duration > 0 && win.width >= 470
                text: win.clock(timeLine.dragging ? timeLine.at : video.position) + " / " + win.clock(video.duration)
                color: timeLine.dragging ? Theme.accent : Theme.muted
                font.family: Theme.body
                font.pixelSize: 11
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
                text: "◐ " + Math.round(win.videoOpacity * 100) + " % ▾"
                color: opacityPicker.open ? Theme.accent : opacityMouse.containsMouse ? Theme.text : Theme.muted
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            MouseArea {
                id: opacityMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // A list of 100 to 50 %; the wheel steps by 10 too.
                onClicked: { qualityPicker.open = false; opacityPicker.open = !opacityPicker.open }
                onWheel: (w) => win.setOpacity(win.videoOpacity + (w.angleDelta.y > 0 ? 0.1 : -0.1))
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: "How much of the video shows: " + opacityText.text
        }
    }
    // The time line over the bottom bar: a click jumps, dragging shows
    // where to and jumps on letting go.
    Item {
        id: timeLine
        visible: win.showBars && video.duration > 0
        anchors.bottom: bottomBar.top
        width: parent.width
        height: 16
        readonly property bool dragging: seekMouse.pressed
        readonly property bool hot: seekMouse.containsMouse || dragging
        property real at: 0
        function timeAt(px) { return video.duration * Math.max(0, Math.min(1, px / width)) }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: timeLine.hot ? 8 : 5
            color: Qt.rgba(58 / 255, 56 / 255, 66 / 255, 0.9)
            Rectangle {
                width: video.duration > 0 ? parent.width * (timeLine.dragging ? timeLine.at : video.position) / video.duration : 0
                height: parent.height
                color: Theme.accent
            }
            Repeater {
                model: video.duration > 0 ? win.segments : []
                delegate: Rectangle {
                    required property var modelData
                    x: parent.width * modelData.start / video.duration
                    width: Math.max(2, parent.width * (modelData.end - modelData.start) / video.duration)
                    height: parent.height
                    color: win.segmentColor(modelData.category)
                    opacity: 0.9
                }
            }
        }
        Rectangle {
            visible: timeLine.hot
            x: Math.max(0, Math.min(parent.width - width, (video.duration > 0 ? parent.width * (timeLine.dragging ? timeLine.at : video.position) / video.duration : 0) - width / 2))
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -3
            width: 4
            height: 14
            color: Theme.accentLight
        }
        // The time under the pointer.
        Rectangle {
            visible: seekMouse.containsMouse || timeLine.dragging
            x: Math.max(0, Math.min(parent.width - width, seekMouse.mouseX - width / 2))
            y: -height - 4
            width: hoverTime.implicitWidth + 10
            height: hoverTime.implicitHeight + 4
            color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.9)
            Text {
                id: hoverTime
                anchors.centerIn: parent
                text: win.clock(timeLine.timeAt(seekMouse.mouseX))
                color: Theme.text
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        MouseArea {
            id: seekMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed: (m) => timeLine.at = timeLine.timeAt(m.x)
            onPositionChanged: (m) => { if (pressed) timeLine.at = timeLine.timeAt(m.x) }
            onReleased: (m) => video.seek(timeLine.timeAt(m.x), false)
        }
        Accessible.role: Accessible.Slider
        Accessible.name: "Time line"
    }

    component SeekButton: Item {
        property bool back
        anchors.verticalCenter: parent.verticalCenter
        visible: video.duration > 0
        width: seekRow.implicitWidth + 10
        height: 26
        Row {
            id: seekRow
            anchors.centerIn: parent
            spacing: 3
            HudIcon {
                visible: back
                anchors.verticalCenter: parent.verticalCenter
                name: "rewind"
                size: 13
                lineWidth: 2.2
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "10"
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            HudIcon {
                visible: !back
                anchors.verticalCenter: parent.verticalCenter
                name: "forwardWind"
                size: 13
                lineWidth: 2.2
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text
            }
        }
        MouseArea {
            id: seekButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: video.seek(back ? -10 : 10, true)
        }
        Accessible.role: Accessible.Button
        Accessible.name: back ? "Back 10 seconds" : "On 10 seconds"
    }

    // What SponsorBlock skipped, with a way back (unlocked).
    Rectangle {
        visible: win.skipNote.length > 0
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: win.showBars ? 62 : 12
        width: skipRow.implicitWidth + 20
        height: 30
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.9)
        Rectangle { width: 2; height: parent.height; color: win.lastSkip ? win.segmentColor(win.lastSkip.category) : Theme.accent }
        Row {
            id: skipRow
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.skipNote
                color: Theme.text
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Text {
                visible: !Companion.locked
                anchors.verticalCenter: parent.verticalCenter
                text: "UNDO"
                color: undoMouse.containsMouse ? Theme.accentLight : Theme.accent
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1
                MouseArea {
                    id: undoMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (win.lastSkip) video.seek(win.lastSkip.start, false)
                        win.skipNote = ""
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Play the skipped part"
            }
        }
    }

    // The lists: quality under the top bar, opacity over the bottom bar.
    Picker {
        id: qualityPicker
        anchors.right: parent.right
        anchors.rightMargin: 36
        y: 36
        maxHeight: win.height - y - 4
        options: win.qualities
        current: win.quality
        onChosen: (id) => win.setQuality(id)
    }
    Picker {
        id: opacityPicker
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.bottom: bottomBar.top
        anchors.bottomMargin: 6
        maxHeight: win.height - 48
        options: win.opacities
        current: String(Math.round(win.videoOpacity * 100))
        onChosen: (id) => win.setOpacity(Number(id) / 100)
    }

    function clock(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        const two = (n) => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
    }

    // The size corner (unlocked): 16:9 kept.
    Item {
        visible: !Companion.locked && !win.fullScreen
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
