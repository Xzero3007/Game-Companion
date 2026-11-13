import QtQuick
import QtQuick.Shapes
import GameCompanion
import GameCompanion.Video
import "theme.js" as Theme
import "drag.js" as Drag

// A video over the game: Twitch's, YouTube's or the Jellyfin server's, each
// in its own window.
// Unlocked, the pointer on it shows its bars (name, pin, quality, close;
// pause, volume, time line); it moves by dragging and changes size by the
// corner. Locked, it takes no clicks: they go to the game.
Item {
    id: win
    /// "twitch", "youtube" or "jellyfin": the player's slot, remembered under "video-<slot>".
    property string slot
    readonly property string panelId: "video-" + slot
    readonly property bool jelly: slot === "jellyfin"
    /// A Jellyfin music track: its album's cover shows, and the album plays on.
    readonly property bool music: jelly && !!item && !!item.item && item.item.type === "Audio"
    readonly property string label: slot === "twitch" ? "Twitch" : jelly ? "Jellyfin" : "YouTube"
    /// What plays: { kind, id, name, title } (Jellyfin: and `item`, the
    /// panel's item, and `start`, where to begin).
    property var item: null
    readonly property bool active: item !== null
    readonly property bool pinned: Companion.pins.indexOf('"' + panelId + '"') >= 0
    /// Where it starts: bottom left (Twitch) or bottom right (YouTube).
    property bool rightSide: slot === "youtube"
    property string quality: jelly ? Jellyfin.quality : Streams.quality
    /// 0 to 100, as the bars show it.
    property int volume: Streams.volume
    /// How much of the video shows (0.5 to 1), kept for each window.
    property real videoOpacity: Streams.opacityOf(slot) / 100
    function setOpacity(o) {
        videoOpacity = Math.max(0.5, Math.min(1, Math.round(o * 10) / 10))
        Streams.saveOpacity(slot, Math.round(videoOpacity * 100))
    }
    // Jellyfin: the file as it is, or the server's conversion down to a height.
    readonly property var qualities: jelly ? [
        { id: "original", name: "ORIGINAL" }, { id: "1080", name: "1080P" }, { id: "720", name: "720P" },
        { id: "480", name: "480P" }, { id: "360", name: "360P" }, { id: "audio", name: "SOUND ONLY" }
    ] : [
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

    // ---------- YouTube: where it stopped, playlists ----------
    /// Seekable: YouTube, Jellyfin, Twitch's past broadcasts and clips.
    readonly property bool seekable: !!item && (item.kind === "youtube" || item.kind === "twitchvod" || item.kind === "twitchclip" || jelly)
    /// The YouTube video's details as the lists have them.
    function videoJson() {
        if (!item) return ""
        const v = item.video || {}
        return JSON.stringify({ id: item.id, title: v.title || item.title || video.title || "", channel: v.channel || item.name || "",
                                channelId: v.channelId || "", duration: video.duration || v.duration || 0, published: v.published || "" })
    }
    // save: written now and the marks follow (pause, end, close, switch);
    // else kept in memory (every 10 s while it plays).
    function keepPosition(save) {
        if (item && item.kind === "youtube" && video.position > 0) Library.record(videoJson(), video.position, video.duration, save !== false)
    }
    Timer {
        // Every 10 seconds while a YouTube video plays: where it is (to go on later).
        interval: 10000
        repeat: true
        running: win.active && !!win.item && win.item.kind === "youtube" && video.state === "playing" && !video.paused
        onTriggered: win.keepPosition(false)
    }
    /// The next in a playlist played through, or null.
    readonly property var nextInQueue: {
        if (!item || !item.queue) return null
        const i = item.index + 1
        if (i < item.queue.length) return { at: i, v: item.queue[i] }
        return item.loop && item.queue.length > 0 ? { at: 0, v: item.queue[0] } : null
    }
    function playNext() {
        const n = nextInQueue
        if (!n) return
        play({ kind: "youtube", id: n.v.id, title: n.v.title, name: n.v.channel, video: n.v, queue: item.queue, index: n.at, loop: item.loop, playlist: item.playlist })
    }
    Connections {
        target: !win.jelly ? video : null
        function onStateChanged() {
            if (video.state === "ended" && win.item && win.item.kind === "youtube") {
                Library.record(win.videoJson(), video.duration, video.duration, true)
                if (win.nextInQueue) win.playNext()
            }
        }
        function onPausedChanged() { if (video.paused) win.keepPosition(true) }
    }

    function play(what) {
        if (jelly && item && jf.started) jfStopped()
        keepPosition()
        item = what
        if (what.kind === "twitch") quality = Streams.qualityFor(what.id) || Streams.quality
        else if (!jelly) quality = Streams.quality
        tries = 0
        segments = []
        skipped = ({})
        skipNote = ""
        nextNote = ""
        nextTimer.stop()
        if (jelly) {
            jf = { source: "", session: "", transcode: false, tracks: null, started: false, audioIndex: -1, subIndex: -2 }
            jfSegs = []
            jfSegment = null
            jfSkipped = ({})
            load(what.start || 0)
            return
        }
        load(what.kind === "youtube" ? Library.resumeAt(what.id) : 0)
        if (what.kind === "youtube") Streams.loadSegments(slot, what.id)
    }
    function load(start) {
        if (!item) return
        if (jelly) {
            // The server's file and tracks first (prepared), then mpv.
            failure = ""
            pendingStart = start || 0
            preparing = true
            Jellyfin.prepare(slot, item.id, quality, jf.audioIndex >= 0 ? jf.audioIndex : -1)
            return
        }
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
    // Screenshots (GC_DEMO=jellyvideo): an episode with its tracks, in its intro.
    function demo() {
        item = { kind: "jellyfin", id: "0".repeat(32), title: "Episode title", name: "Series name · S2 E5", item: null, start: 0 }
        jf = { source: "", session: "", transcode: false, started: false, audioIndex: 1, subIndex: -1,
               tracks: { audio: [{ index: 1, ord: 1, label: "English - AAC - Stereo" }, { index: 2, ord: 2, label: "Deutsch - AC3 - 5.1" }],
                         subs: [{ index: 3, ord: 1, external: false, format: "srt", label: "English" }] } }
        jfSegment = { kind: "intro", start: 0, end: 60 }
    }
    // Development only (GC_TEST_VIDEO): a local file, to check the drawing.
    function playFile(path) {
        item = { kind: "file", id: path, name: "test", title: path }
        video.play(path, "", 0)
    }
    function stop() {
        if (jelly && jf.started) jfStopped()
        keepPosition()
        nextTimer.stop()
        nextNote = ""
        video.stop()
        Streams.stopSource(slot)
        item = null
        failure = ""
    }
    function togglePause() {
        if (video.state === "ended" || video.state === "failed" || video.state === "idle") load(jelly && video.state !== "ended" ? jf.last || 0 : 0)
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
        const at = seekable ? Math.max(0, video.position) : 0
        load(at)
    }

    // ---------- Jellyfin ----------
    // What plays on the server: its file and play session, the tracks, the
    // parts to skip; the server hears what plays and how far.
    property var jf: ({})
    property real pendingStart: 0
    property bool preparing: false
    property var jfSegs: []
    property var jfSegment: null
    property var jfSkipped: ({})
    property string nextNote: ""
    property var nextItem: null
    readonly property var skipNames: ({ intro: "SKIP INTRO", recap: "SKIP RECAP", credits: "SKIP CREDITS", preview: "SKIP PREVIEW" })
    Connections {
        target: Jellyfin
        enabled: win.jelly
        function onPrepared(slot, id, answer) {
            if (slot !== win.slot || !win.item || win.item.id !== id) return
            win.preparing = false
            const a = JSON.parse(answer)
            if (a.error) { win.failure = a.error; return }
            const keep = win.jf
            win.jf = { source: a.source, session: a.session, transcode: a.transcode, tracks: a.tracks, started: false,
                       audioIndex: keep.audioIndex >= 0 ? keep.audioIndex : a.tracks.audioIndex,
                       subIndex: keep.subIndex !== undefined && keep.subIndex > -2 ? keep.subIndex : a.tracks.subIndex,
                       last: win.pendingStart }
            video.volume = win.mpvVolume(win.volume)
            video.play(a.url, "", win.pendingStart, a.header)
        }
        function onSegmentsLoaded(slot, id, list) {
            if (slot !== win.slot || !win.item || win.item.id !== id) return
            win.jfSegs = JSON.parse(list)
        }
        function onNextFound(slot, after, next) {
            if (slot !== win.slot || !win.item || win.item.id !== after || next.length === 0) return
            const it = JSON.parse(next)
            // The album's next (or previous) track: at once.
            if (it.type === "Audio") {
                win.play({ kind: "jellyfin", id: it.id, title: it.name, name: it.sub, item: it, start: 0 })
                return
            }
            win.nextItem = it
            win.nextNote = "NEXT: " + (it.code ? it.code + " · " : "") + it.name
            nextTimer.restart()
        }
    }
    Timer {
        id: nextTimer
        interval: 5000
        onTriggered: {
            const it = win.nextItem
            win.nextNote = ""
            if (it) win.play({ kind: "jellyfin", id: it.id, title: it.name, name: it.sub, item: it, start: 0 })
        }
    }
    function jfReport(kind) {
        if (!jelly || !item) return
        Jellyfin.report(kind, JSON.stringify({ item: item.id, source: jf.source || "", session: jf.session || "",
                                               position: jf.last || 0, paused: video.paused, transcode: !!jf.transcode }))
    }
    function jfStopped() {
        const j = jf
        j.started = false
        jf = j
        jfReport("stopped")
        listsAgain.restart()
    }
    // Continue watching and Next up as the server has them now.
    Timer {
        id: listsAgain
        interval: 1200
        onTriggered: if (Jellyfin.view === "continue" || Jellyfin.view === "nextup") Jellyfin.load(Jellyfin.view, "")
    }
    // Tracks as chosen: the file's own straight in mpv; with the server's
    // conversion, sound comes in the stream and subtitles from the server.
    function jfApplyTracks() {
        const t = jf.tracks
        if (!t) return
        if (!jf.transcode) {
            const a = t.audio.find((x) => x.index === jf.audioIndex)
            if (a) video.setTrack("audio", a.ord)
        }
        const s = t.subs.find((x) => x.index === jf.subIndex)
        if (!s) video.setTrack("subtitle", 0)
        else if (!s.external && !jf.transcode) video.setTrack("subtitle", s.ord)
        else if (s.format) {
            const u = JSON.parse(Jellyfin.subtitle(item.id, jf.source, s.index, s.format))
            if (u.url) video.addSubtitle(u.url)
        }
    }
    function chooseAudio(index) {
        const j = jf
        j.audioIndex = index
        jf = j
        if (jf.transcode) load(video.position)
        else jfApplyTracks()
    }
    function chooseSubtitle(index) {
        const j = jf
        j.subIndex = index
        jf = j
        jfApplyTracks()
    }
    function jfSkip() {
        const seg = jfSegment
        if (!seg) return
        const done = jfSkipped
        done[seg.start] = true
        jfSkipped = done
        jfSegment = null
        video.seek(seg.end, false)
    }
    Timer {
        // Every 10 seconds while it plays: how far (Continue watching).
        interval: 10000
        repeat: true
        running: win.jelly && win.active && !!win.jf.started && !video.paused
        onTriggered: win.jfReport("progress")
    }
    Connections {
        target: win.jelly ? video : null
        function onStateChanged() {
            if (video.state === "playing" && !win.jf.started) {
                const j = win.jf
                j.started = true
                win.jf = j
                win.jfApplyTracks()
                win.jfReport("start")
            } else if (video.state === "ended" && win.jf.started) {
                const j = win.jf
                j.last = video.duration || j.last
                win.jf = j
                win.jfStopped()
                const it = win.item.item
                if (Jellyfin.autoNext && it && it.type === "Episode" && it.seriesId) Jellyfin.findNext(win.slot, it.seriesId, win.item.id)
                else if (it && it.type === "Audio" && it.albumId) Jellyfin.findTrack(win.slot, it.albumId, win.item.id, 1)
            }
        }
        function onPausedChanged() { if (win.jf.started) win.jfReport("progress") }
        function onPositionChanged() {
            const at = video.position
            if (at > 0) { const j = win.jf; j.last = at }
            let seg = null
            for (const s of win.jfSegs) if (at >= s.start && at < s.end - 1) { seg = s; break }
            if (seg !== win.jfSegment) {
                win.jfSegment = seg
                if (seg && Jellyfin.autoSkip && !win.jfSkipped[seg.start]) win.jfSkip()
            }
        }
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
                  outro: "#6f6b78", preview: "#e07a3c", filler: "#9b6be8", music_offtopic: "#f2c46b" })[c] || Theme.muted()
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
        if (jelly) Jellyfin.saveQuality(q)
        else Streams.saveQuality(q)
        quality = q
        if (item && item.kind === "twitch") Streams.saveChannelQuality(item.id, q)
        const at = seekable ? video.position : 0
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
            x = jelly ? (parent.width - width) / 2 : rightSide ? parent.width - width - 40 : 40
            y = parent.height - height - 120
        }
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - 40))
        placed = true
    }
    // Another screen (Settings → Display "Show on"): stay on it.
    function keepOnScreen() {
        if (!placed || fullScreen || !parent || parent.width <= 0) return
        width = Math.min(width, parent.width)
        height = Math.min(height, parent.height)
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - 40))
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
    onParentChanged: place()
    Connections {
        target: win.parent
        function onWidthChanged() { win.place(); win.keepOnScreen(); if (win.fullScreen) win.fitScreen() }
        function onHeightChanged() { win.place(); win.keepOnScreen(); if (win.fullScreen) win.fitScreen() }
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
    // The player exists only while something plays: closed, mpv and all
    // its video memory (decoder, frames) are let go.
    Loader {
        id: videoLoader
        anchors.fill: parent
        active: win.active
        sourceComponent: Component {
            MpvVideo {
                opacity: win.videoOpacity
                visible: drawable
                hwdec: Streams.hwdec
                // Jellyfin: the home network's server, nothing else.
                local: win.jelly
            }
        }
    }
    // A music track: its album's cover over the (empty or tiny) picture.
    Rectangle {
        anchors.fill: parent
        visible: win.music
        color: "#0e0d11"
        opacity: win.videoOpacity
        Image {
            anchors.fill: parent
            anchors.margins: 12
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: win.music ? (win.item.item.picture || "") : ""
        }
    }
    readonly property var video: videoLoader.item || idleVideo
    QtObject {
        id: idleVideo
        property string state: "idle"
        property string error: ""
        property string title: ""
        property bool paused: false
        property bool muted: false
        property real volume: 0
        property real position: 0
        property real duration: 0
        property bool drawable: true
        property var chapters: []
        property real speed: 1
        function play(url, format, start, header) { return false }
        function setTrack(kind, id) {}
        function addSubtitle(url) {}
        function stop() {}
        function seek(seconds, relative) {}
    }
    // Where frames can't be drawn (screenshots), or while it loads.
    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        anchors.centerIn: parent
        visible: !video.drawable || win.preparing || win.playState === "loading" || win.reconnecting || win.playState === "failed" || win.failure.length > 0
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: win.failure.length > 0 ? win.failure
            : win.playState === "failed" ? "Doesn't play: " + video.error
            : win.reconnecting ? "RECONNECTING…"
            : win.playState === "loading" || win.preparing ? "LOADING…"
            : win.label.toUpperCase() + " VIDEO"
        color: win.failure.length > 0 || win.playState === "failed" ? Theme.red : "#5b5866"
        font.family: Theme.display
        font.pixelSize: 13
        font.weight: Font.Bold
        font.letterSpacing: 3
    }

    // The pointer anywhere on the window, its buttons too, keeps the bars;
    // they go a moment after it leaves (no flicker between the buttons).
    HoverHandler {
        id: pointerOn
        enabled: !Companion.locked
    }
    readonly property bool barsWanted: pointerOn.hovered || qualityPicker.open || opacityPicker.open || audioPicker.open || subtitlePicker.open
        || speedPicker.open || chapterPicker.open
    onBarsWantedChanged: if (!barsWanted) barsLinger.restart()
    Timer { id: barsLinger; interval: 700 }

    // Dragging, and a double click pauses (unlocked only; locked, nothing
    // here takes the pointer).
    MoveArea {
        id: hover
        anchors.fill: parent
        enabled: !Companion.locked
        hoverEnabled: true
        target: win
        moves: !win.fullScreen
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onReleased: if (!win.fullScreen) win.remember()
        onDoubleClicked: win.togglePause()
    }
    readonly property bool showBars: !Companion.locked && (barsWanted || barsLinger.running || nativeWindow.demo.indexOf("video") >= 0)
    onShowBarsChanged: if (!showBars) closePickers()
    function closePickers() {
        qualityPicker.open = false; opacityPicker.open = false; audioPicker.open = false; subtitlePicker.open = false
        speedPicker.open = false; chapterPicker.open = false
    }
    /// The chapter at a time ("" none).
    function chapterAt(t) {
        let name = ""
        for (const c of video.chapters) if (c.time <= t) name = c.title || ""
        return name
    }

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
                color: win.playState === "playing" ? Theme.red : win.playState === "failed" ? Theme.red : Theme.dim()
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: win.label.toUpperCase()
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 90
                elide: Text.ElideRight
                text: win.item ? (win.item.kind === "twitch" ? win.item.name + (win.item.game ? " · " + win.item.game : "")
                    : win.item.kind === "twitchvod" || win.item.kind === "twitchclip" ? [win.item.name, win.item.title].filter((t) => t).join(" · ")
                    : win.jelly ? [win.item.title, win.item.name].filter((t) => t).join(" · ")
                    : (win.item.title || video.title)) : ""
                color: Theme.textSoft()
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
                    HudIcon { anchors.verticalCenter: parent.verticalCenter; name: "pin"; size: 12; filled: win.pinned; color: win.pinned ? Theme.accent : Theme.muted() }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.pinned ? "PINNED" : "PIN"
                        color: win.pinned ? Theme.accent : Theme.muted()
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
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: qualityText
                    anchors.centerIn: parent
                    text: win.qualityName(win.quality) + " ▾"
                    color: qualityPicker.open ? Theme.accent : qualityMouse.containsMouse ? Theme.text() : Theme.muted()
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
                    onClicked: { const o = !qualityPicker.open; win.closePickers(); qualityPicker.open = o }
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Quality: " + win.qualityName(win.quality)
            }
            TrackButton {
                visible: video.chapters.length > 1
                text: "CHAPTERS"
                picker: chapterPicker
            }
            IconButton {
                visible: !!win.item && win.item.kind === "youtube"
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool on: Library.revision >= 0 && !!win.item && JSON.parse(Library.mark(win.item.id)).quick
                icon: "bookmark"
                iconSize: 13
                filled: on
                color: on ? Theme.accent : Theme.muted()
                tip: on ? "Remove from the bookmark list" : "Bookmark"
                onClicked: Library.toggleQuick(win.videoJson())
            }
            TrackButton {
                visible: win.jelly && !!win.jf.tracks && win.jf.tracks.audio.length > 1
                text: "SOUND"
                picker: audioPicker
            }
            TrackButton {
                visible: win.jelly && !!win.jf.tracks && win.jf.tracks.subs.length > 0
                text: "SUBS"
                picker: subtitlePicker
            }
            IconButton {
                visible: !!win.item && win.item.kind === "twitch"
                anchors.verticalCenter: parent.verticalCenter
                icon: "chat"
                iconSize: 13
                filled: Streams.chatOpen
                color: Streams.chatOpen ? Theme.accent : Theme.muted()
                tip: Streams.chatOpen ? "Hide the chat" : "Show the chat"
                onClicked: Streams.saveChatOpen(!Streams.chatOpen)
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: win.fullScreen ? "shrink" : "expand"
                iconSize: 13
                color: win.fullScreen ? Theme.accent : Theme.muted()
                tip: win.fullScreen ? "Leave full screen (Esc)" : "Full screen"
                onClicked: win.toggleFullScreen()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                iconSize: 12
                color: Theme.muted()
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
            IconButton {
                visible: win.music && !!win.item.item.albumId
                anchors.verticalCenter: parent.verticalCenter
                icon: "prev"
                iconSize: 13
                color: Theme.text()
                tip: "Previous track"
                onClicked: Jellyfin.findTrack(win.slot, win.item.item.albumId, win.item.id, -1)
            }
            IconButton {
                visible: win.music && !!win.item.item.albumId
                anchors.verticalCenter: parent.verticalCenter
                icon: "next"
                iconSize: 13
                color: Theme.text()
                tip: "Next track"
                onClicked: Jellyfin.findTrack(win.slot, win.item.item.albumId, win.item.id, 1)
            }
            SeekButton { back: true; visible: !win.music && video.duration > 0 }
            SeekButton { back: false; visible: !win.music && video.duration > 0 }
            IconButton {
                visible: !!win.nextInQueue
                anchors.verticalCenter: parent.verticalCenter
                icon: "next"
                iconSize: 13
                color: Theme.text()
                tip: win.nextInQueue ? "Next: " + win.nextInQueue.v.title : ""
                onClicked: win.playNext()
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                // Small, the time line's own label says it.
                visible: video.duration > 0 && win.width >= 470
                text: win.clock(timeLine.dragging ? timeLine.at : video.position) + " / " + win.clock(video.duration)
                color: timeLine.dragging ? Theme.accent : Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Item {
            visible: win.seekable && video.duration > 0
            anchors.right: opacityItem.left
            anchors.verticalCenter: parent.verticalCenter
            width: speedText.implicitWidth + 12
            height: 26
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: speedText
                anchors.centerIn: parent
                text: (Math.round(video.speed * 100) / 100) + "× ▾"
                color: speedPicker.open || Math.abs(video.speed - 1) > 0.01 ? Theme.accent : speedMouse.containsMouse ? Theme.text() : Theme.muted()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            MouseArea {
                id: speedMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { const o = !speedPicker.open; win.closePickers(); speedPicker.open = o }
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: "Speed: " + speedText.text
        }
        Item {
            id: opacityItem
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            width: opacityText.implicitWidth + 12
            height: 26
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: opacityText
                anchors.centerIn: parent
                text: "◐ " + Math.round(win.videoOpacity * 100) + " % ▾"
                color: opacityPicker.open ? Theme.accent : opacityMouse.containsMouse ? Theme.text() : Theme.muted()
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
                onClicked: { const o = !opacityPicker.open; win.closePickers(); opacityPicker.open = o }
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
            // Chapters: a thin gap where each begins.
            Repeater {
                model: video.duration > 0 ? video.chapters : []
                delegate: Rectangle {
                    required property var modelData
                    visible: modelData.time > 0
                    x: parent.width * modelData.time / video.duration - 1
                    width: 2
                    height: parent.height
                    color: "#0c0c0f"
                    z: 2
                }
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
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: hoverTime
                anchors.centerIn: parent
                text: { const t = timeLine.timeAt(seekMouse.mouseX); const c = win.chapterAt(t); return win.clock(t) + (c ? " · " + c : "") }
                color: Theme.text()
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

    component TrackButton: Item {
        property string text
        property Item picker
        anchors.verticalCenter: parent.verticalCenter
        width: trackText.implicitWidth + 14
        height: 26
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: trackText
            anchors.centerIn: parent
            text: parent.text + " ▾"
            color: parent.picker.open ? Theme.accent : trackMouse.containsMouse ? Theme.text() : Theme.muted()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        MouseArea {
            id: trackMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { const o = !parent.picker.open; win.closePickers(); parent.picker.open = o }
        }
        Accessible.role: Accessible.ComboBox
        Accessible.name: text === "SOUND" ? "Sound track" : "Subtitles"
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
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text()
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: "10"
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text()
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
                color: seekButtonMouse.containsMouse ? Theme.accent : Theme.text()
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
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: win.skipNote
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
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
        id: chapterPicker
        anchors.right: parent.right
        anchors.rightMargin: 36
        y: 36
        width: Math.min(300, win.width - 48)
        maxHeight: win.height - y - 44
        options: video.chapters.map((c, i) => ({ id: String(i), name: win.clock(c.time) + "  " + (c.title || "Chapter " + (i + 1)) }))
        current: { let at = -1; video.chapters.forEach((c, i) => { if (c.time <= video.position) at = i }); return String(at) }
        onChosen: (id) => video.seek(video.chapters[Number(id)].time, false)
    }
    Picker {
        id: speedPicker
        anchors.right: parent.right
        anchors.rightMargin: 90
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: 90
        maxHeight: win.height - 80
        options: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map((v) => ({ id: String(v), name: v + "×" }))
        current: String(Math.round(video.speed * 100) / 100)
        onChosen: (id) => video.speed = Number(id)
    }
    Picker {
        id: audioPicker
        anchors.right: parent.right
        anchors.rightMargin: 36
        y: 36
        width: 220
        maxHeight: win.height - y - 4
        options: win.jf.tracks ? win.jf.tracks.audio.map((a) => ({ id: String(a.index), name: a.label })) : []
        current: String(win.jf.audioIndex)
        onChosen: (id) => win.chooseAudio(Number(id))
    }
    Picker {
        id: subtitlePicker
        anchors.right: parent.right
        anchors.rightMargin: 36
        y: 36
        width: 220
        maxHeight: win.height - y - 4
        options: win.jf.tracks ? [{ id: "-1", name: "Off" }].concat(win.jf.tracks.subs
            .filter((s) => !(s.external || win.jf.transcode) || s.format)
            .map((s) => ({ id: String(s.index), name: s.label }))) : []
        current: String(win.jf.subIndex)
        onChosen: (id) => win.chooseSubtitle(Number(id))
    }

    // Jellyfin: skip the intro or the credits (by itself when set so), and
    // what plays next.
    Rectangle {
        visible: win.jelly && !!win.jfSegment && !Companion.locked
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: win.showBars ? 64 : 14
        width: skipText.implicitWidth + 28
        height: 34
        // No gold frame on a video (MN): the gold label is enough.
        color: skipMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.25) : Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.85)
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: skipText
            anchors.centerIn: parent
            text: win.jfSegment ? (win.skipNames[win.jfSegment.kind] || "SKIP") : ""
            color: Theme.accent
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        MouseArea {
            id: skipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.jfSkip()
        }
        Accessible.role: Accessible.Button
        Accessible.name: skipText.text
    }
    Rectangle {
        visible: win.nextNote.length > 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, nextColumn.implicitWidth + 32)
        height: nextColumn.implicitHeight + 24
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, 0.9)
        Column {
            id: nextColumn
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 8
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: win.nextNote
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
            Row {
                visible: !Companion.locked
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                TextButton { text: "Play now"; onClicked: { nextTimer.stop(); nextTimer.triggered() } }
                TextButton { text: "Cancel"; onClicked: { nextTimer.stop(); win.nextNote = "" } }
            }
        }
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

    // The size corner (unlocked, with the bars while the pointer is on the
    // video): 16:9 kept. No gold edge otherwise (MN: it was in the way
    // while watching).
    Item {
        visible: !Companion.locked && !win.fullScreen && (win.showBars || sizeMouse.pressed)
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
            id: sizeMouse
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.SizeFDiagCursor
            property point start
            property real startWidth
            // The window holds the whole screen while resizing (Surface.held).
            property var dragState: ({})
            function hold(on) { if (on) Drag.begin(Window.window); else Drag.end(Window.window) }
            onPressed: (m) => { start = mapToItem(win.parent, m.x, m.y); startWidth = win.width; dragState = {}; hold(true) }
            onPositionChanged: (m) => {
                if (!pressed || !Drag.steady(Window.window)) return
                const p = Drag.fix(Window.window, mapToItem(win.parent, m.x, m.y), start, dragState)
                const room = win.parent ? Math.min(win.parent.width - win.x, (win.parent.height - win.y) * 16 / 9) : 1920
                win.width = Math.max(240, Math.min(startWidth + p.x - start.x, room))
                win.height = Math.round(win.width * 9 / 16)
            }
            onReleased: { win.remember(); hold(false) }
            onCanceled: hold(false)
        }
        Accessible.role: Accessible.Grip
        Accessible.name: "Resize the video"
    }
}
