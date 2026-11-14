import QtQuick
import GameCompanion
import "theme.js" as Theme

// Who is in your Legcord voice channel and who talks, over the game:
// only each person's picture and name, no ground unless chosen (Settings →
// Apps → Legcord). Talking shows as a gold frame (N1, the default), a glow
// or still sound bars. Nothing moves: it redraws only when someone starts
// or stops talking.
Item {
    id: ov

    readonly property var st: { try { return JSON.parse(VoiceChat.state) } catch (e) { return ({}) } }
    readonly property var pics: { try { return JSON.parse(VoiceChat.pictures) } catch (e) { return ({}) } }
    readonly property var raw: { try { return JSON.parse(VoiceChat.prefs) } catch (e) { return ({}) } }
    function pref(k, d) { return ov.raw[k] !== undefined ? ov.raw[k] : d }

    readonly property bool on: pref("on", true)
    readonly property string show: pref("show", "everyone")      // everyone | talking
    readonly property string look: pref("look", "column")        // column | pictures | row
    readonly property string talk: pref("talk", "frame")         // frame | glow | bars
    readonly property string quiet: pref("quiet", "half")        // half | full
    readonly property int ground: pref("background", 0)          // 0 to 100 %
    readonly property int stay: pref("stay", 1)                  // seconds
    readonly property string order: pref("order", "talking")     // talking | joined | az
    readonly property bool self: pref("self", true)
    readonly property string mutedLook: pref("muted", "icon")    // icon | hide
    readonly property bool names: pref("names", true)
    readonly property string size: pref("size", "m")             // s | m | l
    readonly property string when: pref("when", "voice")         // voice | game

    readonly property int pic: size === "s" ? 20 : size === "l" ? 32 : 24
    readonly property int fontPx: size === "s" ? 12 : size === "l" ? 15 : 13
    readonly property bool unlocked: !Companion.locked

    /// Who stopped talking a moment ago still counts as talking (`stay`):
    /// id → when they stopped.
    property var stopped: ({})
    property var wasSpeaking: ({})
    property real now: Date.now()
    function talking(m) { return m.speaking || (ov.stay > 0 && ov.stopped[m.id] !== undefined && ov.now - ov.stopped[m.id] < ov.stay * 1000) }
    function sweep() {
        const t = Date.now()
        const left = {}
        let soonest = 0
        for (const id in ov.stopped) {
            const rest = ov.stay * 1000 - (t - ov.stopped[id])
            if (rest > 0) { left[id] = ov.stopped[id]; soonest = soonest ? Math.min(soonest, rest) : rest }
        }
        ov.stopped = left
        ov.now = t
        // One single-shot timer, only while someone's talk mark fades out.
        if (soonest > 0) { fade.interval = Math.max(50, soonest + 20); fade.restart() }
    }
    onStChanged: {
        const t = Date.now()
        const s = Object.assign({}, ov.stopped)
        const speaking = {}
        for (const m of (st.members || [])) {
            if (m.speaking) { speaking[m.id] = true; delete s[m.id] }
            else if (ov.wasSpeaking[m.id] && ov.stay > 0) s[m.id] = t
        }
        ov.wasSpeaking = speaking
        ov.stopped = s
        sweep()
    }
    Timer { id: fade; repeat: false; onTriggered: ov.sweep() }

    readonly property var people: {
        const all = (st.members || []).filter((m) => (ov.self || m.id !== st.me) && !(ov.mutedLook === "hide" && (m.muted || m.deafened)))
        let list = ov.show === "talking" ? all.filter((m) => ov.talking(m)) : all.slice()
        const byName = (a, b) => a.name.localeCompare(b.name)
        if (ov.order === "az") list.sort(byName)
        else if (ov.order === "joined") list.sort((a, b) => (a.joined - b.joined) || byName(a, b))
        else list.sort((a, b) => ((ov.talking(b) ? 1 : 0) - (ov.talking(a) ? 1 : 0)) || (a.joined - b.joined) || byName(a, b))
        return list
    }

    readonly property bool gameOk: ov.when !== "game" || Games.running.length > 0
    /// Whether it is on screen (unlocked, an empty channel shows its place).
    readonly property bool wanted: ov.on && !!st.channel && ov.gameOk && (ov.people.length > 0 || ov.unlocked)

    width: Math.max(ov.look === "row" ? 60 : 40, box.width + 12)
    height: Math.max(ov.pic + 12, box.height + 12)

    // Its place: dragged while unlocked, kept in the choices.
    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0) return
        const px = pref("x", -1), py = pref("y", -1)
        x = px >= 0 ? px : ov.look === "row" ? (parent.width - width) / 2 : 24
        y = py >= 0 ? py : ov.look === "row" ? 62 : 120
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - height))
        placed = true
    }
    Component.onCompleted: place()
    onParentChanged: place()
    onLookChanged: { if (pref("x", -1) < 0) { placed = false; place() } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(12 / 255, 12 / 255, 15 / 255, ov.ground / 100)
        visible: ov.ground > 0
    }
    // While unlocked: a thin line shows where it is and that it moves.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        visible: ov.unlocked
    }
    Text {
        visible: ov.unlocked && ov.people.length === 0
        anchors.centerIn: parent
        text: "VOICE"
        color: Theme.dim()
        font.family: Theme.display
        font.weight: Font.Bold
        font.pixelSize: 11
        font.letterSpacing: 1.5
        style: Text.Outline; styleColor: Theme.shadow
    }
    MoveArea {
        anchors.fill: parent
        enabled: ov.unlocked
        target: ov
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onReleased: { VoiceChat.setPref("x", String(Math.round(ov.x))); VoiceChat.setPref("y", String(Math.round(ov.y))) }
    }

    Grid {
        id: box
        x: 6
        y: 6
        columns: ov.look === "row" ? Math.max(1, ov.people.length) : 1
        columnSpacing: 12
        rowSpacing: ov.look === "row" ? 0 : 6

        Repeater {
            model: ov.people
            delegate: Item {
                id: person
                required property var modelData
                readonly property var who: modelData
                readonly property bool speaking: ov.talking(who)
                readonly property bool showName: ov.names && (ov.look !== "pictures" || speaking)
                readonly property bool rowLook: ov.look === "row"
                opacity: speaking || ov.quiet === "full" ? 1 : 0.5
                width: rowLook ? Math.max(face.width, label.width) : face.width + (showName ? 8 + label.width + extras.width : extras.width > 0 ? 6 + extras.width : 0)
                height: rowLook ? face.height + (showName ? 5 + label.height : 0) : face.height

                Item {
                    id: face
                    width: ov.pic
                    height: ov.pic
                    x: person.rowLook ? (person.width - width) / 2 : 0
                    // Glow: soft rings of gold, no shader (Qt 6.4 has no MultiEffect).
                    Repeater {
                        model: person.speaking && ov.talk === "glow" ? [1, 3, 5] : []
                        Rectangle {
                            required property int modelData
                            x: -modelData; y: -modelData
                            width: face.width + 2 * modelData; height: face.height + 2 * modelData
                            color: "transparent"
                            border.color: Theme.accent
                            border.width: 2
                            opacity: modelData === 1 ? 0.9 : modelData === 3 ? 0.4 : 0.15
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#2f2d36"
                        visible: img.status !== Image.Ready
                        Text {
                            anchors.centerIn: parent
                            text: (person.who.name || "?").slice(0, 2).toUpperCase()
                            color: "#dddae2"
                            font.family: Theme.display
                            font.weight: Font.Bold
                            font.pixelSize: Math.round(ov.pic * 0.45)
                        }
                    }
                    Image {
                        id: img
                        anchors.fill: parent
                        source: person.who.avatar && ov.pics[person.who.avatar] ? ov.pics[person.who.avatar] : ""
                        sourceSize.width: 64
                        sourceSize.height: 64
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: false
                    }
                    // N1: a thin gold frame (rows: a line under the picture).
                    Rectangle {
                        visible: person.speaking && ov.talk === "frame" && !person.rowLook
                        x: -3; y: -3
                        width: face.width + 6; height: face.height + 6
                        color: "transparent"
                        border.color: Theme.accent
                        border.width: 2
                    }
                    Rectangle {
                        visible: person.speaking && ov.talk === "frame" && person.rowLook
                        width: face.width; height: 2
                        y: face.height + 2
                        color: Theme.accent
                    }
                }
                Text {
                    id: label
                    visible: person.showName
                    x: person.rowLook ? (person.width - width) / 2 : face.width + 8
                    y: person.rowLook ? face.height + 5 : (face.height - height) / 2
                    text: person.who.id === ov.st.me ? person.who.name + " (you)" : person.who.name
                    color: ov.talk === "glow" && person.speaking ? Theme.accentLight : Theme.text()
                    font.family: Theme.body
                    font.weight: Font.DemiBold
                    font.pixelSize: person.rowLook ? ov.fontPx - 1 : ov.fontPx
                    style: Text.Outline; styleColor: Theme.shadow
                }
                Row {
                    id: extras
                    visible: !person.rowLook
                    x: person.showName ? label.x + label.width + 6 : face.width + 6
                    anchors.verticalCenter: face.verticalCenter
                    spacing: 4
                    // N3: three still sound bars while talking.
                    Row {
                        visible: person.speaking && ov.talk === "bars"
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: [0.5, 1, 0.7]
                            Rectangle {
                                required property real modelData
                                width: 3
                                height: Math.round(ov.fontPx * modelData)
                                anchors.bottom: parent.bottom
                                color: Theme.accent
                                border.color: Qt.rgba(0, 0, 0, 0.6)
                                border.width: 0
                            }
                        }
                    }
                    HudIcon {
                        visible: person.who.muted || person.who.deafened
                        size: 13
                        lineWidth: 2.2
                        anchors.verticalCenter: parent.verticalCenter
                        name: person.who.deafened ? "deaf" : "mute"
                        color: Theme.red
                    }
                }
            }
        }
    }
}
