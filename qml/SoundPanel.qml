import QtQuick
import GameCompanion
import "theme.js" as Theme

// The sound module (canvas page "Sound", MIXER variant A; MN 2026-11-16):
// four channels with volume, preset and EQ plus ChatMix (MIXER), the mic
// chain that opens only for a voice (MIC), which program plays on which
// channel (APPS) and what OBS gets (STREAM). Everything runs in Sound's
// own PipeWire child; this panel only shows and changes its settings.
// The mic's meter runs only while the MIC tab shows.
Panel {
    id: panel
    panelId: "sound"
    title: "Sound"
    icon: "equalizer"
    width: 600
    minWidth: 540
    maxWidth: 820

    readonly property var st: JSON.parse(Sound.state)
    readonly property var prefs: JSON.parse(Sound.prefs)
    readonly property var apps: JSON.parse(Sound.apps)
    readonly property bool on: prefs.on === true
    property string tab: {
        const d = nativeWindow.demo
        if (d.indexOf("soundmic") >= 0) return "mic"
        if (d.indexOf("soundapps") >= 0) return "apps"
        if (d.indexOf("soundstream") >= 0) return "stream"
        return "mixer"
    }
    /// Which channel's preset list or EQ is open ("" = none).
    property string presetsFor: ""
    property string eqFor: nativeWindow.demo.indexOf("soundeq") >= 0 ? "game" : ""
    property bool micListOpen: false

    /// The MIC tab could show the meter (Main runs it while the panel shows).
    readonly property bool meterWanted: tab === "mic" && on && prefs.mic && prefs.mic.on === true
    // The channels' meters run only while the MIXER shows (Main switches them).
    readonly property bool channelMetersWanted: tab === "mixer" && on
    readonly property var levels: Sound.channelLevels.split(",").map(Number)
    readonly property var levelIndex: ({ game: 0, chat: 1, media: 2, music: 3 })

    readonly property var channelKeys: ["game", "chat", "media", "music"]
    readonly property var names: ({ game: "Game", chat: "Chat", media: "Media", music: "Music", mic: "Mic" })
    readonly property var marks: ({ game: Theme.purple, chat: "#4fa8ff", media: "#c9c6d0", music: Theme.accentLight, mic: Theme.accent })
    readonly property var monitors: ({ game: "Game Companion Spiel", chat: "Game Companion Chat", media: "Game Companion Medien", music: "Game Companion Musik" })

    function channel(key) { return (prefs.channels && prefs.channels[key]) || ({ preset: "Flat", eq: [0, 0, 0, 0, 0, 0], volume: 100 }) }
    function presetValues(name) {
        for (const p of st.presets || []) if (p.name === name) return p.values
        return null
    }
    function eqOf(key) {
        const c = channel(key)
        return (c.preset && presetValues(c.preset)) || c.eq || [0, 0, 0, 0, 0, 0]
    }
    /// What plays on a channel, one line each (same names counted):
    /// Game Companion's own by what they are ("YouTube", "Radio").
    function appsOn(key) {
        const counts = {}
        const order = []
        for (const a of apps) {
            if (a.channel !== key) continue
            const n = (a.name || a.binary || "?").replace(/^Game Companion · /, "")
            if (counts[n] === undefined) { counts[n] = 0; order.push(n) }
            counts[n]++
        }
        return order.length > 0 ? order.map((n) => counts[n] > 1 ? n + " ×" + counts[n] : n) : ["nothing plays"]
    }
    /// ChatMix's share for game or chat in percent (as `sound::chatmix`).
    function mixPart(key) {
        const m = Math.max(-100, Math.min(100, prefs.chatmix || 0))
        if (key === "game") return m <= 0 ? 100 : 100 - m
        if (key === "chat") return m >= 0 ? 100 : 100 + m
        return 100
    }
    function mic() { return prefs.mic || ({}) }
    function minLevel() { const v = mic().min_level; return v === undefined ? -50 : v }
    readonly property var micPresetHelp: ({
        "Flat": "Nothing changed: your mic as it is.",
        "Clear voice": "The everyday choice: a little less boom, a little more presence. Easy to follow in Legcord.",
        "Radio": "Full and close like a radio host: more body, less mud, clear top. Sounds best with Clean up on.",
        "Podcast": "Like Radio, but gentler: natural with a bit of polish, good for long talks and streams.",
        "Warm": "Softer and rounder, less sharp. Good if your mic sounds harsh or thin.",
        "Deep": "Much more body and depth. Good for a thin-sounding mic; too much on a close mic gets boomy.",
        "Bright": "Less boom, more air and detail. Good for a dull mic or one far away."
    })
    function micName() {
        const d = mic().device || ""
        for (const m of st.mics || []) if (m.name === d) return m.desc
        return d.length > 0 ? d : "Choose the input"
    }

    headerTools: Component {
        Row {
            spacing: 10
            layoutDirection: Qt.RightToLeft
            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.on
                onToggled: (v) => Sound.setOn(v)
                Accessible.name: "Sound on"
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: panel.st.running ? Theme.accent : (panel.st.why ? Theme.red : Theme.dim()) }
                Small { text: panel.st.running ? "Running" : panel.on ? (panel.st.why ? "Not running" : "Starting…") : "Off" }
            }
        }
    }

    Column {
        width: parent.width
        spacing: 10

        // Tabs
        Item {
            width: parent.width
            height: 30
            Row {
                height: parent.height
                spacing: 18
                Tab { name: "mixer"; label: "Mixer" }
                Tab { name: "mic"; label: "Mic" }
                Tab { name: "apps"; label: "Apps" }
                Tab { name: "stream"; label: "Stream" }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // EasyEffects runs: it caused the dropouts (MN's logs).
        Note {
            visible: panel.st.easyEffects === true
            warn: true
            text: "EasyEffects is running. Its filters caused your dropouts; Sound does that job now."
            button: "Close EasyEffects"
            onPressed: Sound.closeEasyEffects()
        }
        Note {
            visible: panel.on && (panel.st.why || "").length > 0
            warn: true
            text: "Sound did not start: " + (panel.st.why || "")
        }
        Note {
            visible: !panel.on
            text: "Sound is off. On, every program plays through its channel and the mic gets its filters. Your system's PipeWire is not changed; off puts everything back."
            button: "Turn on"
            onPressed: Sound.setOn(true)
        }

        // ---------------------------------------------------------- MIXER
        Column {
            visible: panel.tab === "mixer"
            width: parent.width
            spacing: 2
            Repeater {
                model: panel.channelKeys
                delegate: ChannelRow { width: parent.width }
            }
            Item { width: 1; height: 8 }
            Row {
                width: parent.width
                height: 28
                spacing: 10
                Head { width: 76; anchors.verticalCenter: parent.verticalCenter; text: "CHATMIX" }
                Small { anchors.verticalCenter: parent.verticalCenter; text: "GAME" }
                HudSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 76 - 90 - 30
                    from: -100; to: 100; stepSize: 5
                    centre: 0
                    value: panel.prefs.chatmix || 0
                    onChanging: (v) => Sound.setChatmix(v)
                    onMoved: (v) => Sound.setChatmix(Math.abs(v) < 8 ? 0 : v)
                    Accessible.name: "ChatMix"
                    Accessible.description: mixReadout.text
                }
                Small { anchors.verticalCenter: parent.verticalCenter; text: "CHAT" }
            }
            // How far it is from the middle (MN, 2026-11-20).
            Text {
                id: mixReadout
                x: 86
                width: parent.width - 86
                readonly property int m: panel.prefs.chatmix || 0
                text: m === 0 ? "Middle: game and chat as set above"
                    : "Game " + panel.mixPart("game") + " % · Chat " + panel.mixPart("chat") + " %  ("
                      + (m < 0 ? "toward game" : "toward chat") + ")"
                color: m === 0 ? Theme.textSoft() : Theme.accent
                font.family: Theme.body; font.pixelSize: 12; font.weight: Font.DemiBold
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            Small {
                x: 86
                width: parent.width - 86
                wrapMode: Text.WordWrap
                text: "Turns the game down as you turn the chat up, and the other way; heard only while both play. Double click: back to the middle."
            }
        }

        // ------------------------------------------------------------ MIC
        Column {
            visible: panel.tab === "mic"
            width: parent.width
            spacing: 10

            Rectangle {
                width: parent.width
                height: 50
                color: "#1b1a20"
                HudIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "mic"; size: 20; color: Sound.talking ? Theme.accent : Theme.muted() }
                Column {
                    x: 44
                    anchors.verticalCenter: parent.verticalCenter
                    Line { text: "Game Companion Mikro"; font.weight: Font.DemiBold }
                    Small { text: "Pick this as the microphone in Legcord and in OBS." }
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Rectangle {
                        visible: panel.meterWanted
                        anchors.verticalCenter: parent.verticalCenter
                        width: talkText.implicitWidth + 16
                        height: 22
                        color: "transparent"
                        border.color: Sound.talking ? Theme.accent : Theme.track
                        Head { id: talkText; anchors.centerIn: parent; text: Sound.talking ? "TALKING" : "QUIET"; color: Sound.talking ? Theme.accent : Theme.muted() }
                    }
                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: panel.mic().on === true
                        onToggled: (v) => Sound.setMic(JSON.stringify({ on: v }))
                        Accessible.name: "Mic chain on"
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 14
                // Left: input and gate.
                Column {
                    width: (parent.width - 14) / 2
                    spacing: 8
                    Head { text: "INPUT" }
                    PickBox {
                        width: parent.width
                        text: panel.micName()
                        open: panel.micListOpen
                        onPressed: panel.micListOpen = !panel.micListOpen
                    }
                    Column {
                        visible: panel.micListOpen
                        width: parent.width
                        Repeater {
                            model: panel.st.mics || []
                            delegate: PickRow {
                                required property var modelData
                                width: parent.width
                                text: modelData.desc
                                current: modelData.name === panel.mic().device
                                onPressed: { panel.micListOpen = false; Sound.setMic(JSON.stringify({ device: modelData.name })) }
                            }
                        }
                        Small { visible: (panel.st.mics || []).length === 0; text: "No microphone found." }
                    }
                    Row {
                        spacing: 6
                        Line { width: 62; anchors.verticalCenter: parent.verticalCenter; text: "Channel" }
                        Chip { text: "Input 1"; on: panel.mic().channel !== "FR"; onClicked: Sound.setMic(JSON.stringify({ channel: "FL" })) }
                        Chip { text: "Input 2"; on: panel.mic().channel === "FR"; onClicked: Sound.setMic(JSON.stringify({ channel: "FR" })) }
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "Only this input is taken, so the voice is not on one side only." }

                    Head { text: "ONLY WHEN YOU TALK"; topPadding: 6 }
                    Item {
                        width: parent.width
                        height: 14
                        Rectangle { anchors.fill: parent; color: Theme.trackDark }
                        Rectangle { height: parent.height; width: parent.width * Sound.level / 100; color: Sound.talking ? Theme.accent : Theme.track }
                        // Where the level gate opens (the bar spans -60 to 0 dBFS).
                        Rectangle {
                            readonly property real at: panel.minLevel()
                            visible: at > -60
                            x: parent.width * (at + 60) / 60
                            width: 2; height: parent.height; color: Theme.text()
                        }
                        Accessible.role: Accessible.ProgressBar
                        Accessible.name: "Mic level " + Sound.level
                    }
                    SliderRow {
                        width: parent.width
                        label: "Mic gain"
                        from: 0; to: 30; step: 1
                        value: panel.mic().gain !== undefined ? panel.mic().gain : 12
                        unit: " dB"
                        onPicked: (v) => Sound.setMic(JSON.stringify({ gain: Math.round(v) }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "Turns the mic up before anything else. Set it so the bar above reaches about two thirds when you talk normally. Too quiet, and the gate opens late." }
                    SliderRow {
                        width: parent.width
                        label: "Floor"
                        from: -70; to: -20; step: 1
                        value: panel.minLevel()
                        unit: " dB"
                        onPicked: (v) => Sound.setMic(JSON.stringify({ min_level: Math.round(v) }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: panel.minLevel() <= -70 ? "Off: only the voice filter decides." : (panel.st.levelGate ? "The mic stays shut below this level (the white mark on the bar), so hiss and what is left of the speakers stay out between words. Talk normally: your voice should end well right of the mark. Too far right, and quiet words are cut." : "Needs swh-plugins.") }
                    SliderRow {
                        width: parent.width
                        label: "Opens at"
                        from: 50; to: 99; step: 1
                        value: panel.mic().threshold || 60
                        unit: " %"
                        onPicked: (v) => Sound.setMic(JSON.stringify({ threshold: v }))
                    }
                    SliderRow {
                        width: parent.width
                        label: "Stays open"
                        from: 100; to: 1500; step: 50
                        value: panel.mic().grace || 500
                        unit: " ms"
                        onPicked: (v) => Sound.setMic(JSON.stringify({ grace: Math.round(v) }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "The gate asks the noise filter how sure it is that this is a voice, not how loud it is: keys and a fan stay out. Opens at: lower lets quiet words through, higher keeps more noise out. Stays open: longer cuts fewer word ends." }
                }
                // Right: speakers, voice, hear it.
                Column {
                    width: (parent.width - 14) / 2
                    spacing: 8
                    Head { text: "SPEAKERS" }
                    SwitchRow {
                        width: parent.width
                        text: "Take the speakers' sound out of the mic"
                        checked: panel.mic().echo !== false
                        onToggled: (v) => Sound.setMic(JSON.stringify({ echo: v }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "On with speakers: what they play is taken back out of the mic. Off with a headset: nothing to take out, and the voice stays untouched." }
                    SwitchRow {
                        width: parent.width
                        text: "Duck while I talk"
                        checked: panel.mic().duck === true
                        onToggled: (v) => Sound.setMic(JSON.stringify({ duck: v }))
                    }
                    SliderRow {
                        visible: panel.mic().duck === true
                        width: parent.width
                        label: "Quieter by"
                        from: -30; to: -3; step: 1
                        value: panel.mic().duck_db === undefined ? -12 : panel.mic().duck_db
                        unit: " dB"
                        onPicked: (v) => Sound.setMic(JSON.stringify({ duck_db: Math.round(v) }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "While you talk, everything the computer plays (game, chat, videos, music) gets quieter, and comes back half a second after you stop. Less of the speakers reaches the mic, so the echo canceller takes out less of you: on with speakers, when you sound like under water while a video or Discord talks. -12 dB is clearly quieter; -6 dB if you still want to hear everyone well. Not needed with a headset. The stream mix (Game Companion Stream) keeps the full sound." }
                    SwitchRow {
                        width: parent.width
                        text: "Extra noise suppression"
                        checked: panel.mic().extra_ns === true
                        onToggled: (v) => Sound.setMic(JSON.stringify({ extra_ns: v }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "Takes out a little more of what is left of the speakers, but with music or voices playing your voice can sound like under water. Mostly off." }
                    SwitchRow {
                        width: parent.width
                        text: "Auto level"
                        checked: panel.mic().auto_level === true
                        onToggled: (v) => Sound.setMic(JSON.stringify({ auto_level: v }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "Turns quiet talking up and loud talking down by itself, like EasyEffects' auto gain. Handy if you move away from the mic; it can lift the room in pauses. Mic gain first, this only if needed." }
                    Head { text: "VOICE"; topPadding: 6 }
                    Item {
                        width: parent.width
                        height: 22
                        Line { anchors.verticalCenter: parent.verticalCenter; text: "Noise filter (rnnoise)" }
                        Small { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: panel.st.rnnoise ? "installed" : "missing"; color: panel.st.rnnoise ? Theme.accent : Theme.red }
                    }
                    Small { visible: !panel.st.rnnoise; width: parent.width; wrapMode: Text.WordWrap; color: Theme.red; text: "Install noise-suppression-for-voice: without it the mic does not open and close by itself." }
                    SwitchRow {
                        width: parent.width
                        text: "Clean up: no rumble"
                        checked: panel.mic().voice !== false
                        onToggled: (v) => Sound.setMic(JSON.stringify({ voice: v }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "Cuts the hum and rumble below 80 Hz (desk, fan, mains): the voice itself is not touched. Leave it on." }
                    SwitchRow {
                        width: parent.width
                        text: "Even out"
                        checked: panel.mic().even_out === true
                        onToggled: (v) => Sound.setMic(JSON.stringify({ even_out: v }))
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: !panel.st.compressor ? "Needs swh-plugins." : "A gentle compressor: loud words a little quieter, so loud and quiet ones sit closer together. On if you get loud in a fight and people turn you down; off if your voice seems to rise and fall by itself." }
                    Item {
                        width: parent.width
                        height: 22
                        Line { anchors.verticalCenter: parent.verticalCenter; text: "Limiter" }
                        Small { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: panel.st.limiter ? "always on" : "needs swh-plugins"; color: panel.st.limiter ? Theme.accent : Theme.red }
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: "At the very end: never lets the mic go past full, however loud you shout. You don't hear it work." }
                    Head { text: "HEAR IT"; topPadding: 6 }
                    Chip {
                        text: Sound.hearing === "recording" ? "Recording… talk now" : Sound.hearing === "playing" ? "Playing back…" : "Record 10 s and play back"
                        on: Sound.hearing.length > 0
                        onClicked: if (panel.on && Sound.hearing.length === 0) Sound.hear()
                    }
                    Small { width: parent.width; wrapMode: Text.WordWrap; text: panel.on && panel.mic().on ? "Your voice as Legcord gets it, after the filters." : "Needs Sound and the mic on." }
                }
            }

            // The mic's EQ: presets and five voice bands, live.
            Item { width: 1; height: 2 }
            Item {
                width: parent.width
                height: 20
                Head { anchors.verticalCenter: parent.verticalCenter; text: "MIC EQ" }
                Small { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (panel.mic().eq_preset || "Own") }
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: panel.st.micPresets || []
                    delegate: Chip {
                        required property var modelData
                        text: modelData.name
                        on: (panel.mic().eq_preset === undefined ? "Clear voice" : panel.mic().eq_preset) === modelData.name
                        onClicked: Sound.setMic(JSON.stringify({ eq_preset: modelData.name }))
                    }
                }
            }
            Small { width: parent.width; wrapMode: Text.WordWrap; text: panel.micPresetHelp[panel.mic().eq_preset === undefined ? "Clear voice" : panel.mic().eq_preset] || "Your own values." }
            Item {
                width: parent.width
                height: 150
                Row {
                    spacing: 14
                    Repeater {
                        model: [["Body", "120 Hz"], ["Mud", "300 Hz"], ["Nasal", "1 kHz"], ["Presence", "4 kHz"], ["Air", "10 kHz"]]
                        delegate: Band {
                            required property var modelData
                            required property int index
                            label: modelData[0]
                            value: (panel.st.micEq || [0, 0, 0, 0, 0])[index] || 0
                            onPicked: (v) => {
                                const e = (panel.st.micEq || [0, 0, 0, 0, 0]).slice()
                                e[index] = v
                                Sound.setMic(JSON.stringify({ eq_preset: "", eq: e }))
                            }
                        }
                    }
                }
                Column {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    spacing: 6
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 110; height: 24; color: "transparent"; border.color: micName.activeFocus ? Theme.accent : "#3a3842"
                            TextInput {
                                id: micName
                                x: 6; width: parent.width - 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text(); font.family: Theme.body; font.pixelSize: 11; clip: true
                                selectionColor: Theme.accent
                                Small { visible: micName.text.length === 0; text: "Preset name" }
                                Accessible.name: "Mic preset name"
                            }
                        }
                        Chip {
                            text: "Save"
                            onClicked: if (micName.text.trim().length > 0) { Sound.saveMicPreset(micName.text.trim(), JSON.stringify(panel.st.micEq || [0, 0, 0, 0, 0])); micName.text = "" }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 6
                        Chip {
                            visible: (panel.st.micPresets || []).some((p) => p.own && p.name === panel.mic().eq_preset)
                            text: "Delete preset"
                            onClicked: Sound.deleteMicPreset(panel.mic().eq_preset)
                        }
                        Chip { text: "Flat"; onClicked: Sound.setMic(JSON.stringify({ eq_preset: "Flat" })) }
                    }
                }
            }
            Small { width: parent.width; wrapMode: Text.WordWrap; text: "Body: fullness of the voice. Mud: boomy, boxy sound, usually turned down. Nasal: honky, as through the nose. Presence: clear and in front, words easy to follow. Air: breath and shine; too much hisses. Changes are heard at once: try them with Record 10 s and play back." }
        }

        // ----------------------------------------------------------- APPS
        Column {
            visible: panel.tab === "apps"
            width: parent.width
            spacing: 2
            Item {
                width: parent.width
                height: 20
                Head { anchors.verticalCenter: parent.verticalCenter; text: "PLAYING NOW" }
                Small { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "always there" }
            }
            Repeater {
                model: panel.apps
                delegate: AppRow { width: parent.width }
            }
            Small { visible: panel.apps.length === 0; text: panel.on ? "Nothing plays right now." : "Shows what plays once Sound is on." }
            Item { width: 1; height: 8 }
            Head { text: "HOW A NEW PROGRAM IS SORTED" }
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 16
                rowSpacing: 3
                Line { width: (parent.width - 16) / 2; text: "1. Your choice, if \"always there\" is on" }
                Line { width: (parent.width - 16) / 2; text: "3. Legcord, Discord, Vesktop → CHAT" }
                Line { width: (parent.width - 16) / 2; text: "2. The running game → GAME" }
                Line { width: (parent.width - 16) / 2; text: "4. Music players, the radio → MUSIC" }
                Item { width: 1; height: 1 }
                Line { width: (parent.width - 16) / 2; text: "5. Everything else → MEDIA" }
            }
        }

        // --------------------------------------------------------- STREAM
        Row {
            visible: panel.tab === "stream"
            width: parent.width
            spacing: 14
            Column {
                width: (parent.width - 14) / 2
                spacing: 6
                Item {
                    width: parent.width
                    height: 22
                    Head { anchors.verticalCenter: parent.verticalCenter; text: "STREAM MIX" }
                    Switch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: panel.prefs.stream && panel.prefs.stream.on === true
                        onToggled: (v) => Sound.setStream(v, "{}")
                        Accessible.name: "Stream mix on"
                    }
                }
                Small { width: parent.width; wrapMode: Text.WordWrap; text: "One source for OBS: \"Game Companion Stream\". What is in it is set here, apart from what you hear." }
                Repeater {
                    model: ["mic", "game", "chat", "media", "music"]
                    delegate: SendRow { width: parent.width }
                }
                Small { width: parent.width; wrapMode: Text.WordWrap; text: "Music is out of the stream until you put it in: you hear it, the stream doesn't." }
            }
            Column {
                width: (parent.width - 14) / 2
                spacing: 6
                Head { text: "OWN TRACKS FOR THE VOD"; height: 22; verticalAlignment: Text.AlignVCenter }
                Small { width: parent.width; wrapMode: Text.WordWrap; text: "Each channel is there on its own too. Add them in OBS as separate audio sources, each on its own track." }
                Repeater {
                    model: [
                        { n: "1", what: "Stream mix (live)", src: "Game Companion Stream" },
                        { n: "2", what: "Your voice", src: "Game Companion Mikro" },
                        { n: "3", what: "Game", src: panel.monitors.game + " · monitor" },
                        { n: "4", what: "Chat", src: panel.monitors.chat + " · monitor" },
                        { n: "5", what: "Music", src: panel.monitors.music + " · monitor" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 34
                        color: "#1b1a20"
                        Rectangle {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; color: "transparent"; border.color: Theme.track
                            Head { anchors.centerIn: parent; text: modelData.n; color: Theme.text() }
                        }
                        Column {
                            x: 40; width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            Line { width: parent.width; text: modelData.what }
                            Small { width: parent.width; text: modelData.src; font.pixelSize: 10 }
                        }
                    }
                }
                Chip {
                    property bool done: false
                    text: done ? "Copied" : "Copy the names for OBS"
                    onClicked: { nativeWindow.copyText("Game Companion Stream\nGame Companion Mikro\nMonitor of " + panel.monitors.game + "\nMonitor of " + panel.monitors.chat + "\nMonitor of " + panel.monitors.media + "\nMonitor of " + panel.monitors.music); done = true }
                }
                Small { width: parent.width; wrapMode: Text.WordWrap; text: "Twitch gets track 1; the VOD keeps 2 to 5. Leave out track 5 and the music is gone." }
            }
        }

        // Footer
        Rectangle { width: parent.width; height: 1; color: Theme.divider }
        Small {
            width: parent.width
            wrapMode: Text.WordWrap
            text: panel.tab === "apps" ? "A click moves the program at once. Without \"always there\" it is sorted again next time."
                : panel.tab === "stream" ? "Nothing is sent anywhere: OBS reads these sources on this PC."
                : panel.tab === "mic" ? "In Legcord switch its own noise filter, echo and auto volume off: ours does it."
                : "Runs in Game Companion's own PipeWire part; your system's PipeWire is not changed."
        }
        // The sound log (MN, 2026-11-16): a fresh snapshot of the graph,
        // then the log's last lines on the clipboard.
        Row {
            spacing: 8
            Chip {
                id: copyLog
                property bool waiting: false
                property bool done: false
                text: waiting ? "Looking (5 s)…" : done ? "Copied" : "Copy sound log"
                onClicked: { if (waiting) return; done = false; waiting = true; Sound.report() }
                Connections {
                    target: Sound
                    function onReportingChanged() {
                        if (!Sound.reporting && copyLog.waiting) {
                            copyLog.waiting = false
                            nativeWindow.copyText(Sound.logText(700))
                            copyLog.done = true
                        }
                    }
                }
            }
            Chip { text: "Open log folder"; onClicked: Companion.openLogFolder() }
            Small { anchors.verticalCenter: parent.verticalCenter; text: "sound.log: setup, PipeWire's warnings, dropouts" }
        }
    }

    // ------------------------------------------------------------ parts ----

    component Line: Text {
        color: Theme.text()
        font.family: Theme.body
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Small: Text {
        color: Theme.muted()
        font.family: Theme.body
        font.pixelSize: 11
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Head: Text {
        color: Theme.muted()
        font.family: Theme.display
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        style: Theme.textStyle(); styleColor: Theme.shadow
    }

    component Tab: Item {
        property string name
        property string label
        width: tabText.implicitWidth
        height: parent.height
        readonly property bool current: panel.tab === name
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: tabText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
            font.family: Theme.display
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Rectangle { visible: parent.current; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.tab = parent.name }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }

    /// On or off, in the accent while on.
    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool on)
        width: 34
        height: 18
        color: "transparent"
        border.color: checked ? Theme.accent : Theme.track
        Rectangle { width: 12; height: 12; y: 3; x: sw.checked ? sw.width - width - 3 : 3; color: sw.checked ? Theme.accent : Theme.muted() }
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: checked
    }
    component SwitchRow: Item {
        property alias text: rowText.text
        property alias checked: rowSwitch.checked
        signal toggled(bool on)
        height: Math.max(22, rowText.implicitHeight)
        Line { id: rowText; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.WordWrap }
        Switch { id: rowSwitch; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; onToggled: (v) => parent.toggled(v); Accessible.name: rowText.text }
    }
    component SliderRow: Item {
        id: sr
        property string label
        property real from: 0
        property real to: 100
        property real step: 1
        property real value: 0
        property string unit: ""
        /// Shown while dragging, sent once let go.
        property real shown: value
        onValueChanged: shown = value
        signal picked(real v)
        height: 24
        Line { width: 70; anchors.verticalCenter: parent.verticalCenter; text: sr.label }
        HudSlider {
            x: 74
            width: parent.width - 74 - 54
            anchors.verticalCenter: parent.verticalCenter
            from: sr.from; to: sr.to; stepSize: sr.step
            value: sr.shown
            onChanging: (v) => sr.shown = v
            onMoved: (v) => { sr.shown = v; sr.picked(v) }
            Accessible.name: sr.label
        }
        Line { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.round(sr.shown) + sr.unit }
    }
    component Note: Rectangle {
        id: note
        property alias text: noteText.text
        property string button: ""
        property bool warn: false
        signal pressed
        width: parent ? parent.width : 300
        height: visible ? Math.max(36, noteText.implicitHeight + 16) : 0
        color: warn ? Qt.rgba(214 / 255, 69 / 255, 61 / 255, 0.14) : "#1b1a20"
        border.color: warn ? Qt.rgba(214 / 255, 69 / 255, 61 / 255, 0.5) : Theme.divider
        Line {
            id: noteText
            x: 10
            width: parent.width - 20 - (noteButton.visible ? noteButton.width + 10 : 0)
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            color: note.warn ? "#ffd0d2" : Theme.textSoft()
        }
        Chip { id: noteButton; visible: note.button.length > 0; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: note.button; onClicked: note.pressed() }
    }
    component PickBox: Rectangle {
        property alias text: pickText.text
        property bool open: false
        signal pressed
        height: 28
        color: "transparent"
        border.color: open ? Theme.accent : "#3a3842"
        Line { id: pickText; x: 10; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter }
        HudIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron"; size: 12; color: Theme.muted() }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.pressed() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: pickText.text
    }
    component PickRow: Rectangle {
        property alias text: pickRowText.text
        property bool current: false
        signal pressed
        height: 26
        color: pickRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "#1b1a20"
        Line { id: pickRowText; x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; color: parent.current ? Theme.accent : Theme.textSoft() }
        MouseArea { id: pickRowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.pressed() }
        Accessible.role: Accessible.ListItem
        Accessible.name: pickRowText.text
    }

    /// One channel: name and what plays on it, volume, preset, EQ.
    component ChannelRow: Rectangle {
        id: ch
        required property string modelData
        readonly property string key: modelData
        readonly property var c: panel.channel(key)
        readonly property var eq: panel.eqOf(key)
        readonly property bool presetsOpen: panel.presetsFor === key
        readonly property bool eqOpen: panel.eqFor === key
        // Taller when more programs play on it: each on its own line.
        readonly property real headH: Math.max(44, nameCol.height + 14)
        height: headH + (presetsOpen ? presetFlow.height + 10 : 0) + (eqOpen ? eqBox.height + 10 : 0)
        color: "#1b1a20"
        Rectangle { x: 10; y: 9; width: 3; height: 26; color: panel.marks[ch.key] }
        Column {
            id: nameCol
            x: 22; y: 7
            width: 112
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: panel.names[ch.key].toUpperCase(); color: Theme.text()
                font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1.5 }
            Repeater {
                model: panel.appsOn(ch.key)
                delegate: Small { required property string modelData; width: nameCol.width; text: modelData; elide: Text.ElideRight }
            }
        }
        VolumeBar {
            x: 138
            y: 8
            value: Math.min(100, ch.c.volume)
            // ChatMix turns game or chat down: the bar shows what is heard.
            heard: ch.key === "game" || ch.key === "chat" ? Math.round(value * panel.mixPart(ch.key) / 100) : -1
            onStepped: (d) => Sound.setChannel(ch.key, "", "", Math.max(0, Math.min(100, ch.c.volume + d)))
            onPicked: (v) => Sound.setChannel(ch.key, "", "", v)
        }
        // What plays on the channel now (before its EQ): moves with the
        // sound, so one sees the channel works (MN, 2026-11-16).
        Row {
            anchors.right: chipRow.left
            anchors.rightMargin: 14
            y: 14
            height: 16
            spacing: 2
            Accessible.name: panel.names[ch.key] + " level"
            Repeater {
                model: 10
                delegate: Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: 4
                    height: 4 + index * 1.3
                    color: (panel.levels[panel.levelIndex[ch.key]] || 0) > index * 10 ? Theme.accent : Theme.track
                }
            }
        }
        Row {
            id: chipRow
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 10
            spacing: 6
            Chip {
                width: 104
                text: (ch.c.preset || "Own") + " ▾"
                on: ch.presetsOpen
                onClicked: { panel.presetsFor = ch.presetsOpen ? "" : ch.key; panel.eqFor = "" }
            }
            Chip {
                text: "EQ"
                on: ch.eqOpen
                onClicked: { panel.eqFor = ch.eqOpen ? "" : ch.key; panel.presetsFor = "" }
                Accessible.name: "Equalizer of " + panel.names[ch.key]
            }
        }
        // The presets, in place (a list under a panel's end would open past its surface).
        Flow {
            id: presetFlow
            visible: ch.presetsOpen
            x: 22; y: ch.headH
            width: parent.width - 32
            spacing: 6
            Repeater {
                model: panel.st.presets || []
                delegate: Chip {
                    required property var modelData
                    text: modelData.name
                    on: ch.c.preset === modelData.name
                    onClicked: { Sound.setChannel(ch.key, modelData.name, "", -1); panel.presetsFor = "" }
                }
            }
        }
        // The five bands and the pre-gain, in place.
        Item {
            id: eqBox
            visible: ch.eqOpen
            x: 22; y: ch.headH
            width: parent.width - 32
            height: 150
            Row {
                spacing: 14
                Repeater {
                    model: ["PRE", "80", "250", "1k", "3.5k", "9k"]
                    delegate: Band {
                        required property string modelData
                        required property int index
                        label: modelData
                        value: ch.eq[index] || 0
                        onPicked: (v) => {
                            const e = ch.eq.slice()
                            e[index] = v
                            Sound.setChannel(ch.key, "", JSON.stringify(e), -1)
                        }
                    }
                }
            }
            Column {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                spacing: 6
                Row {
                    spacing: 6
                    Rectangle {
                        width: 110; height: 24; color: "transparent"; border.color: nameInput.activeFocus ? Theme.accent : "#3a3842"
                        TextInput {
                            id: nameInput
                            x: 6; width: parent.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text(); font.family: Theme.body; font.pixelSize: 11; clip: true
                            selectionColor: Theme.accent
                            Small { visible: nameInput.text.length === 0; text: "Preset name" }
                            Accessible.name: "Preset name"
                        }
                    }
                    Chip {
                        text: "Save"
                        onClicked: if (nameInput.text.trim().length > 0) { Sound.savePreset(nameInput.text.trim(), JSON.stringify(ch.eq)); Sound.setChannel(ch.key, nameInput.text.trim(), "", -1); nameInput.text = "" }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 6
                    Chip {
                        visible: (panel.st.presets || []).some((p) => p.own && p.name === ch.c.preset)
                        text: "Delete preset"
                        onClicked: Sound.deletePreset(ch.c.preset)
                    }
                    Chip { text: "Flat"; onClicked: Sound.setChannel(ch.key, "Flat", "", -1) }
                }
            }
        }
    }

    /// One EQ band: −12 to +12 dB, upright; sent once let go.
    component Band: Item {
        id: band
        property string label
        property real value: 0
        property real shown: value
        onValueChanged: shown = value
        signal picked(real v)
        width: 44
        height: 150
        Small { anchors.horizontalCenter: parent.horizontalCenter; text: (band.shown > 0 ? "+" : "") + band.shown.toFixed(0) + " dB"; color: band.shown === 0 ? Theme.muted() : Theme.text() }
        Item {
            id: track
            y: 20
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: 104
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4; height: parent.height; color: Theme.trackDark }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height / 2; width: 12; height: 1; color: Theme.track }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 18; height: 6
                y: (12 - band.shown) / 24 * (parent.height - height)
                color: Theme.accent
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function at(my) { return Math.round(Math.max(-12, Math.min(12, 12 - my / height * 24))) }
                onPressed: (m) => band.shown = at(m.y)
                onPositionChanged: (m) => { if (pressed) band.shown = at(m.y) }
                onReleased: (m) => { band.shown = at(m.y); band.picked(band.shown) }
                onWheel: (w) => { const v = Math.max(-12, Math.min(12, band.shown + (w.angleDelta.y > 0 ? 1 : -1))); band.shown = v; band.picked(v) }
            }
            Accessible.role: Accessible.Slider
            Accessible.name: band.label + " " + band.shown + " dB"
        }
        Small { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; text: band.label }
    }

    /// A playing program and its channel.
    component AppRow: Rectangle {
        id: app
        required property var modelData
        height: 44
        color: "#1b1a20"
        Rectangle {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; color: Theme.trackDark
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.centerIn: parent
                text: (app.modelData.name || "?").replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase()
                color: Theme.textSoft(); font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold }
        }
        Column {
            x: 48; width: parent.width - 48 - choices.width - 70
            anchors.verticalCenter: parent.verticalCenter
            Line { width: parent.width; text: app.modelData.name; font.weight: Font.DemiBold }
            Small { width: parent.width; text: app.modelData.fixed ? "your choice" : app.modelData.binary || "" ; color: app.modelData.fixed ? Theme.accent : Theme.muted() }
        }
        Row {
            id: choices
            anchors.right: parent.right
            anchors.rightMargin: 60
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: panel.channelKeys
                delegate: Chip {
                    required property string modelData
                    text: panel.names[modelData]
                    on: app.modelData.channel === modelData
                    onClicked: Sound.moveApp(app.modelData.index, modelData, app.modelData.fixed === true)
                }
            }
        }
        Switch {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            checked: app.modelData.fixed === true
            onToggled: (v) => {
                if (v) Sound.moveApp(app.modelData.index, app.modelData.channel || "media", true)
                else Sound.forgetRoute(app.modelData.program)
            }
            Accessible.name: "Always this channel for " + app.modelData.name
        }
    }

    /// One source of the stream mix: in or out, how loud.
    component SendRow: Rectangle {
        id: send
        required property string modelData
        readonly property var s: (panel.prefs.stream && panel.prefs.stream.sources && panel.prefs.stream.sources[modelData]) || ({ on: modelData !== "music", volume: 100 })
        function put(on, vol) {
            const o = {}
            o[modelData] = { on: on, volume: Math.max(0, Math.min(100, vol)) }
            Sound.setStream(panel.prefs.stream && panel.prefs.stream.on === true, JSON.stringify(o))
        }
        height: 34
        color: "#1b1a20"
        Switch {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            checked: send.s.on === true
            onToggled: (v) => send.put(v, send.s.volume)
            Accessible.name: panel.names[send.modelData] + " into the stream"
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 50; width: 50; anchors.verticalCenter: parent.verticalCenter
            text: panel.names[send.modelData].toUpperCase()
            color: send.s.on ? Theme.text() : Theme.muted()
            font.family: Theme.display; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2 }
        VolumeBar {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            value: send.s.volume
            onStepped: (d) => send.put(send.s.on, send.s.volume + d)
            onPicked: (v) => send.put(send.s.on, v)
        }
    }
}
