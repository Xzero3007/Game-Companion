import QtQuick
import QtQuick.Shapes
import GameCompanion
import "theme.js" as Theme

// The sound's quick row (canvas board 6, MN 2026-11-16: opens with a right
// click on SOUND): a slanted strip under the bar like the player row, with
// the mic's state, the four channels' volumes and ChatMix. Pinnable. The
// mic's meter runs only while it shows; it redraws only on a change.
Item {
    id: strip
    signal closeClicked
    readonly property var prefs: JSON.parse(Sound.prefs)
    readonly property bool pinned: Companion.pins.indexOf('"sound-row"') >= 0
    readonly property bool micOn: prefs.on === true && prefs.mic && prefs.mic.on === true

    readonly property var keys: ["game", "chat", "media", "music"]
    readonly property var names: ({ game: "GAME", chat: "CHAT", media: "MEDIA", music: "MUSIC" })
    function volumeOf(key) { return prefs.channels && prefs.channels[key] ? Math.min(100, prefs.channels[key].volume) : 100 }

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 36

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: Theme.panel(Companion.alpha)
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: strip.width; y: 0 }
            PathLine { x: strip.width - 12; y: strip.height }
            PathLine { x: 12; y: strip.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height
        spacing: 10

        // The mic: off, quiet or talking.
        Row {
            height: parent.height
            spacing: 6
            leftPadding: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7
                color: !strip.micOn ? Theme.dim(true) : Sound.talking ? Theme.accentFor(true) : Theme.muted(true)
            }
            HudIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "mic"; size: 14
                color: strip.micOn && Sound.talking ? Theme.accentFor(true) : Theme.muted(true)
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: Sound.prefs.length === 0 ? "" : !(strip.prefs.on === true) ? "SOUND OFF" : !strip.micOn ? "MIC OFF" : Sound.talking ? "TALKING" : "MIC QUIET"
                color: strip.micOn && Sound.talking ? Theme.accentFor(true) : Theme.textSoft(true)
                font.family: Theme.display; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.5
            }
        }
        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Theme.divider }

        Repeater {
            model: strip.keys
            delegate: Row {
                required property string modelData
                height: row.height
                spacing: 2
                leftPadding: 4
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    text: strip.names[modelData]
                    color: Theme.textSoft(true)
                    font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2
                }
                VolumeBar {
                    hud: true
                    compact: true
                    anchors.verticalCenter: parent.verticalCenter
                    value: strip.volumeOf(modelData)
                    onStepped: (d) => Sound.setChannel(modelData, "", "", Math.max(0, Math.min(100, strip.volumeOf(modelData) + d)))
                    onPicked: (v) => Sound.setChannel(modelData, "", "", v)
                }
            }
        }
        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Theme.divider }

        Row {
            height: parent.height
            spacing: 6
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                text: "MIX"
                color: Theme.textSoft(true)
                font.family: Theme.display; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2
            }
            HudSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                from: -100; to: 100; stepSize: 5
                value: strip.prefs.chatmix || 0
                onChanging: (v) => Sound.setChatmix(v)
                onMoved: (v) => Sound.setChatmix(Math.abs(v) < 8 ? 0 : v)
                Accessible.name: "ChatMix: game to chat"
            }
        }

        IconButton {
            hud: true
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            icon: "pin"
            iconSize: 14
            filled: strip.pinned
            color: strip.pinned ? Theme.accentFor(true) : Theme.dim(true)
            tip: strip.pinned ? "Unpin: hide with the hub" : "Pin: stay when the hub is hidden"
            onClicked: Companion.togglePin("sound-row")
        }
        IconButton {
            hud: true
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            icon: "close"
            iconSize: 12
            color: Theme.dim(true)
            tip: "Close the quick row (right click on SOUND opens it)"
            onClicked: strip.closeClicked()
        }
    }
}
