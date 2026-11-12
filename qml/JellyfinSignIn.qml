import QtQuick
import GameCompanion
import "theme.js" as Theme

// Signing in to one's own Jellyfin server (Settings → Streams → Jellyfin,
// and the Streams panel's Jellyfin tab before it): the server's address,
// the user's name and password. Only a home network's address is taken.
Column {
    id: form
    spacing: 8
    readonly property bool busy: Jellyfin.signInState === "busy"
    readonly property string problem: busy ? "" : Jellyfin.signInState

    function send() {
        if (busy) return
        Jellyfin.signIn(server.text, user.text, password.text)
        password.text = ""
    }

    Field { id: server; width: parent.width; placeholder: "Server, e.g. 192.168.1.20:8096 or nas.local:8096"; maxLength: 200; onAccepted: user.forceActiveFocus() }
    Row {
        width: parent.width
        spacing: 8
        Field { id: user; width: (parent.width - 8) / 2; placeholder: "User name"; maxLength: 100; onAccepted: password.forceActiveFocus() }
        Field { id: password; width: (parent.width - 8) / 2; placeholder: "Password"; secret: true; maxLength: 200; onAccepted: form.send() }
    }
    Row {
        spacing: 12
        TextButton { text: form.busy ? "Signing in…" : "Sign in"; onClicked: form.send() }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: form.problem.length > 0
            width: form.width - 140
            wrapMode: Text.WordWrap
            text: form.problem
            color: Theme.red
            font.family: Theme.body
            font.pixelSize: 12
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Home network addresses only. The password is never kept; the server's key stays in a file on this PC that only you can read."
        color: Theme.dim
        font.family: Theme.body
        font.pixelSize: 11
        lineHeight: 1.15
    }

    component Field: Rectangle {
        property alias text: input.text
        property string placeholder
        property bool secret: false
        property int maxLength: 80
        signal accepted
        function forceActiveFocus() { input.forceActiveFocus() }
        height: 34
        color: "#1b1a20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: Theme.body
            font.pixelSize: 13
            maximumLength: parent.maxLength
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: parent.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: parent.parent.placeholder
                color: Theme.dim
                font: input.font
            }
            Accessible.name: parent.placeholder
        }
    }
}
