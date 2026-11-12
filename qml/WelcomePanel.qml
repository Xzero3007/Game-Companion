import QtQuick
import GameCompanion
import "theme.js" as Theme

// The first start: what the overlay does and how to use it.
Panel {
    id: welcome
    panelId: "welcome"
    title: "Welcome"
    badge: "STEP 2"
    pinnable: false
    width: 420

    property var keys: JSON.parse(Companion.shortcuts)
    function keyOf(id) {
        for (const k of keys) if (k.id === id) return k.key.length > 0 ? k.key : "no key"
        return ""
    }

    Column {
        width: parent.width
        spacing: 10

        Para { text: "Game Companion sits above your game, so one screen is enough." }
        Para {
            text: "<b>Locked</b> (as it starts): every click goes to the game. Only the lock in the bar takes clicks."
        }
        Para { text: "<b>Unlocked</b>: a gold frame shows. Move panels by their header and use their buttons." }

        Column {
            width: parent.width
            topPadding: 4
            KeyRow { key: welcome.keyOf("lock"); what: "Use the overlay / let clicks through" }
            KeyRow { key: welcome.keyOf("toggle"); what: "Hide the hub; pinned things stay" }
        }

        Para {
            color: Theme.dim()
            text: "The pin in a panel's header keeps it on screen while the hub is hidden. Videos and game modules come in the next steps."
        }

        Item {
            width: parent.width
            height: 40
            TextButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "Got it"
                onClicked: Companion.closeWelcome()
            }
        }
    }

    onCloseClicked: Companion.closeWelcome()

    component Para: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        color: Theme.textSoft()
        font.family: Theme.body
        font.pixelSize: 13
        lineHeight: 1.2
    }
    component KeyRow: Item {
        property string key
        property string what
        width: parent.width
        height: 34
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            text: parent.key.toUpperCase()
            color: Theme.accent
            font.family: Theme.display
            font.pixelSize: 15
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            x: 118
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 118
            elide: Text.ElideRight
            text: parent.what
            color: Theme.text()
            font.family: Theme.body
            font.pixelSize: 13
        }
    }
}
