import QtQuick
import GameCompanion
import GameCompanion.Chat
import "theme.js" as Theme

// The chat of the Twitch channel that plays: docked right of the Twitch
// video (it follows the video until it is moved; "Dock" brings it back),
// pinnable, and as see-through as the user likes. Signed in to Twitch,
// messages can be written (Settings → Streams → Twitch "Write in chat").
// Twitch's emotes, 7TV's and BTTV's show as still pictures (nothing moves
// while idle); names keep the colours their owners chose.
Panel {
    id: panel
    panelId: "chat"
    title: "Chat"
    icon: "chat"
    width: 340
    minWidth: 260
    maxWidth: 700
    stretchy: true
    ground: Companion.alpha * opacityPercent / 100
    badge: chat.state === "joined" ? channel.toUpperCase() : chat.state === "connecting" ? "CONNECTING" : chat.state === "failed" ? "OFFLINE" : ""
    actionText: docked ? "" : "Dock"
    onActionClicked: { Streams.saveChatDocked(true); dock() }

    /// The Twitch video window it docks to.
    property Item video
    /// Whether it is on screen (it reads the chat only then).
    property bool running: false
    readonly property string channel: video && video.item && video.item.kind === "twitch" ? String(video.item.id) : ""
    readonly property bool docked: Streams.chatDocked
    property int opacityPercent: Streams.opacityOf("chat")
    readonly property bool outline: ground < 0.5

    // Docked: beside the video (right of it, or left when there is no room).
    readonly property real dockX: {
        if (!video || !parent) return defaultX
        const right = video.x + video.width + 6
        return right + width <= parent.width ? right : Math.max(0, video.x - width - 6)
    }
    readonly property real dockY: video && parent ? Math.max(0, Math.min(video.y, parent.height - height)) : defaultY
    defaultX: dockX
    defaultY: dockY
    property bool docking: false
    function dock() {
        if (!docked || !placed) return
        docking = true
        x = dockX
        y = dockY
        docking = false
    }
    onDockXChanged: dock()
    onDockYChanged: dock()
    onPlacedChanged: dock()
    // Moved by hand: it stays where it was left.
    onXChanged: if (docked && placed && !docking && Math.abs(x - dockX) > 2) Streams.saveChatDocked(false)
    onYChanged: if (docked && placed && !docking && Math.abs(y - dockY) > 2) Streams.saveChatDocked(false)

    // ---- the connection ----
    TwitchChat {
        id: chat
        onRoomIdChanged: if (roomId.length > 0) Streams.loadEmotes(roomId)
        onMessage: (name, colour, text, emotes, own, system) => panel.add(name, colour, text, emotes, own, system)
    }
    function connectChat() {
        // Screenshots never connect.
        if (!running || channel.length === 0 || nativeWindow.demo.length > 0) { chat.leave(); return }
        const auth = JSON.parse(Streams.chatAuth())
        chat.join(channel, auth.user || "", auth.token || "")
    }
    onRunningChanged: connectChat()
    onChannelChanged: { lines.clear(); pending = []; newCount = 0; extra = {}; connectChat() }
    Component.onCompleted: { connectChat(); if (nativeWindow.demo.indexOf("chat") >= 0) demo() }
    Component.onDestruction: chat.leave()
    Connections {
        target: Streams
        function onAccountChanged() { panel.connectChat() }
        function onChatWriteChanged() { panel.connectChat() }
        function onEmotesLoaded(room, list) { if (room === chat.roomId) panel.extra = JSON.parse(list) }
    }

    // ---- the lines ----
    /// 7TV and BTTV emotes: name → [picture, width, height].
    property var extra: ({})
    property var pending: []
    property int newCount: 0
    readonly property int keep: 200

    // Twitch's colours for names that chose none.
    readonly property var defaults: ["#FF0000", "#0000FF", "#00FF00", "#B22222", "#FF7F50", "#9ACD32", "#FF4500", "#2E8B57",
                                     "#DAA520", "#D2691E", "#5F9EA0", "#1E90FF", "#FF69B4", "#8A2BE2", "#00FF7F"]
    function nameColour(name, colour) {
        let c = colour
        if (!/^#[0-9a-fA-F]{6}$/.test(c)) {
            let h = 0
            for (let i = 0; i < name.length; ++i) h = (h * 31 + name.charCodeAt(i)) % 997
            c = defaults[h % defaults.length]
        }
        // Too dark on the dark ground: lighter, the same hue.
        const r = parseInt(c.substr(1, 2), 16), g = parseInt(c.substr(3, 2), 16), b = parseInt(c.substr(5, 2), 16)
        const light = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        if (light >= 0.45) return c
        const t = Math.min(0.7, 0.45 - light + 0.25)
        const mix = (v) => Math.round(v + (255 - v) * t).toString(16).padStart(2, "0")
        return "#" + mix(r) + mix(g) + mix(b)
    }
    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    }
    // A picture as tall as a line and a bit (its width kept in proportion).
    function img(url, w, h) {
        const height = 22, width = Math.round(Math.min(4, w / h) * height)
        return '<img src="' + esc(url) + '" width="' + width + '" height="' + height + '" align="middle">'
    }
    // The text with its emotes as pictures: Twitch's by place (in code
    // points), 7TV's and BTTV's by word.
    function render(text, emotes) {
        const cps = Array.from(text)
        const at = {}
        if (emotes.length > 0) {
            for (const part of emotes.split("/")) {
                const [id, places] = part.split(":")
                if (!/^[A-Za-z0-9_]+$/.test(id) || !places) continue
                for (const p of places.split(",")) {
                    const [a, b] = p.split("-").map(Number)
                    if (a >= 0 && b >= a && b < cps.length) at[a] = { end: b, id: id }
                }
            }
        }
        let out = "", word = ""
        const flush = () => {
            if (word.length === 0) return
            // Only the map's own names ("constructor" is a word, too).
            const e = Object.prototype.hasOwnProperty.call(extra, word) ? extra[word] : null
            out += e ? img(e[0], e[1], e[2]) : esc(word)
            word = ""
        }
        for (let i = 0; i < cps.length; ++i) {
            const e = at[i]
            if (e) {
                flush()
                out += img("https://static-cdn.jtvnw.net/emoticons/v2/" + e.id + "/static/dark/1.0", 28, 28)
                i = e.end
                continue
            }
            if (cps[i] === " ") { flush(); out += " " } else word += cps[i]
        }
        flush()
        return out
    }
    function add(name, colour, text, emotes, own, system) {
        const html = system ? '<i>' + esc(text) + '</i>'
                            : '<b><font color="' + nameColour(name, colour) + '">' + esc(name) + '</font></b>: ' + render(text, emotes)
        pending.push({ html: html, system: system, own: own })
        // Busy chats come in bursts: shown together, a few times a second.
        if (!flushTimer.running) flushTimer.start()
    }
    Timer {
        id: flushTimer
        interval: 250
        onTriggered: {
            const atEnd = list.atYEnd || lines.count === 0
            for (const l of panel.pending) lines.append(l)
            const added = panel.pending.length
            panel.pending = []
            // Scrolled up, old lines stay a while longer (trimming would
            // move what is being read); at most twice as many.
            const most = atEnd ? panel.keep : panel.keep * 2
            if (lines.count > most) lines.remove(0, lines.count - panel.keep)
            if (atEnd) list.positionViewAtEnd()
            else panel.newCount += added
        }
    }
    ListModel { id: lines }

    function demo() {
        extra = {}
        add("", "", "Welcome to the chat room!", "", false, true)
        add("NightOwl", "#1E90FF", "that pull was clean", "", false, false)
        add("tankmain_", "", "Kappa first try", "0:0-4", false, false)
        add("Gildra", "#8A2BE2", "what build is that? looks strong on the boss", "", false, false)
        add("darkness", "#000080", "dark names get lighter so they stay readable", "", false, false)
        add("Ari", "#DAA520", "gg", "", false, false)
        add("", "", "Ari subscribed at Tier 1. They've subscribed for 5 months!", "", false, true)
        add("me_myself", "#FF69B4", "hello from the overlay", "", true, false)
    }

    // ---- the view ----
    Item {
        width: parent.width
        height: 360 + panel.grow

        ListView {
            id: list
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.bottom: bottomRow.top
            anchors.bottomMargin: 6
            clip: true
            model: lines
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            onAtYEndChanged: if (atYEnd) panel.newCount = 0
            delegate: Text {
                width: ListView.view.width
                text: model.html
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                color: model.system ? Theme.dim() : Theme.text()
                font.family: Theme.body
                font.pixelSize: 13
                style: panel.outline ? Text.Outline : Theme.textStyle()
                styleColor: Theme.shadow
            }
        }
        WheelScroll { flick: list; step: 60 }

        // New lines while scrolled up.
        Rectangle {
            visible: panel.newCount > 0
            anchors.horizontalCenter: list.horizontalCenter
            anchors.bottom: list.bottom
            anchors.bottomMargin: 6
            width: newText.implicitWidth + 20
            height: 24
            color: "#1b1a20"
            border.color: Theme.accent
            border.width: 1
            Text {
                id: newText
                anchors.centerIn: parent
                text: panel.newCount + " NEW"
                color: Theme.accent
                font.family: Theme.display
                font.weight: Font.Bold
                font.pixelSize: 12
                font.letterSpacing: 1
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { list.positionViewAtEnd(); panel.newCount = 0 }
            }
        }

        // Writing, or why not; and the ground's opacity.
        Item {
            id: bottomRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            height: 34

            Rectangle {
                visible: chat.canSend
                anchors.left: parent.left
                anchors.right: opacityButton.left
                anchors.rightMargin: 8
                height: parent.height
                color: "#1b1a20"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
                TextInput {
                    id: input
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: sendButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text()
                    selectionColor: Theme.accent
                    selectedTextColor: "#0c0c0f"
                    font.family: Theme.body
                    font.pixelSize: 13
                    maximumLength: 500
                    clip: true
                    onAccepted: if (chat.send(text)) text = ""
                    Text {
                        visible: input.text.length === 0
                        text: "Send a message"
                        color: Theme.dim()
                        font: input.font
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Accessible.name: "Chat message"
                }
                IconButton {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "send"
                    iconSize: 13
                    color: input.text.length > 0 ? Theme.accent : Theme.muted()
                    tip: "Send"
                    onClicked: if (chat.send(input.text)) input.text = ""
                }
            }
            Text {
                visible: !chat.canSend
                anchors.left: parent.left
                anchors.right: opacityButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: panel.channel.length === 0 ? "No Twitch stream plays."
                    : chat.note.length > 0 ? chat.note
                    : chat.state === "connecting" ? "Connecting to the chat…" : ""
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                style: panel.outline ? Text.Outline : Theme.textStyle(); styleColor: Theme.shadow
            }
            // 100, 75, 50, 25 % ground, round.
            TextButton {
                id: opacityButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 28
                text: panel.opacityPercent + "%"
                onClicked: {
                    const steps = [100, 75, 50, 25]
                    const i = steps.indexOf(panel.opacityPercent)
                    panel.opacityPercent = steps[(i + 1) % steps.length]
                    Streams.saveOpacity("chat", panel.opacityPercent)
                }
            }
        }
    }
}
