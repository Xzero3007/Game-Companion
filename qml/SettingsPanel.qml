import QtQuick
import GameCompanion
import "theme.js" as Theme

// Settings: how solid the panels are, the shortcuts, and what this is.
Panel {
    id: settings
    panelId: "settings"
    title: "Settings"
    width: 440

    property string tab: nativeWindow.demo.indexOf("sponsor") >= 0 || nativeWindow.demo.indexOf("jellyfin") >= 0 || nativeWindow.demo.indexOf("hwdec") >= 0 ? "streams" : "general"
    property var keys: JSON.parse(Companion.shortcuts)
    readonly property var layouts: JSON.parse(Companion.layouts)
    /// The layout being renamed ("" for none).
    property string renaming: ""
    property string layoutMessage: ""
    minWidth: 400
    signal saveLayoutRequested(string name)
    signal loadLayoutRequested(string name)
    Component.onCompleted: {
        for (const t of ["display", "layouts", "streams-settings", "shortcuts", "about"]) if (nativeWindow.demo.indexOf(t) >= 0) tab = t.replace("-settings", "")
    }

    Column {
        width: parent.width
        spacing: 12

        Row {
            spacing: 12
            Tab { name: "general"; label: "General" }
            Tab { name: "display"; label: "Display" }
            Tab { name: "layouts"; label: "Layouts" }
            Tab { name: "streams"; label: "Streams" }
            Tab { name: "shortcuts"; label: "Shortcuts" }
            Tab { name: "about"; label: "About" }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.divider; anchors.topMargin: -12 }

        // General
        Column {
            visible: settings.tab === "general"
            width: parent.width
            spacing: 10

            Label { text: "Overlay" }
            Hint { text: nativeWindow.layerShell
                ? "On KDE's overlay layer: above games in fullscreen, borderless or windowed mode."
                : "Not on KDE's overlay layer (no Wayland, or built without it): above other windows where the desktop allows it." }

            Item { width: 1; height: 6 }
            Label { text: "Updates" }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                width: parent.width
                wrapMode: Text.WordWrap
                text: "This is " + Companion.version() + "."
                    + (Updates.latest.length > 0 ? " Latest release: " + Updates.latest + "." : "")
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 13
            }
            Hint {
                visible: Updates.message.length > 0
                text: Updates.message
                color: Updates.state === "failed" ? Theme.red
                    : Updates.state === "available" || Updates.state === "installing" ? Theme.accent : Theme.dim()
            }
            Row {
                spacing: 10
                TextButton {
                    text: Updates.state === "checking" ? "Checking…" : "Check for updates"
                    onClicked: Updates.check()
                }
                TextButton {
                    visible: Updates.state === "available"
                    text: "Install update"
                    onClicked: Updates.install()
                }
            }
            OnOff {
                width: parent.width
                text: "Beta updates (test builds)"
                on: Updates.beta
                onToggled: Updates.setChannel(!Updates.beta)
            }
            Hint { text: (Updates.runningBeta ? "This copy is a beta build. " : "")
                + "Beta builds bring new things first and may break; switching back off installs the latest stable release." }
            Hint { text: "Looks at Game Companion's own releases on GitHub when it starts and every 20 minutes. Nothing else is sent." }

            Item { width: 1; height: 6 }
            Label { text: "Turn off" }
            Hint { text: "Closes the hub completely, with the radio. Start it again from the application menu." }
            TextButton {
                text: "Turn off Game Companion"
                danger: true
                onClicked: Qt.quit()
            }
        }

        // Display
        Column {
            visible: settings.tab === "display"
            width: parent.width
            spacing: 10

            Label { text: "Screen" }
            Dropdown {
                id: screenChoice
                width: parent.width
                z: 30
                label: "Show on"
                property string picked: Companion.chosenScreen()
                options: [{ id: "", name: "KDE's primary screen" }].concat(JSON.parse(nativeWindow.screenList))
                current: picked
                onChosen: (id) => {
                    picked = id
                    Companion.saveScreen(id)
                    nativeWindow.setPreferredScreen(id)
                }
            }
            Hint { text: "Where the bar and the panels show. Now on " + nativeWindow.screenName + "." }

            Item { width: 1; height: 6 }
            Label { text: "Panel opacity" }
            Level {
                from: 0.05
                value: Companion.alpha
                onChanging: (v) => Companion.alpha = v
                onMoved: (v) => Companion.saveAlpha(v)
            }
            Presets {
                kind: "alpha"
                values: JSON.parse(Companion.alphaPresets)
                current: Companion.alpha
                onPicked: (v) => Companion.saveAlpha(v)
            }
            Hint { text: "How much of the game shows through the bar and the panels. Under half, text gets a dark outline to stay readable." }

            Item { width: 1; height: 6 }
            Label { text: "Bar text brightness" }
            Level {
                from: 0.4
                value: Companion.textLevel
                onChanging: (v) => Companion.textLevel = v
                onMoved: (v) => Companion.saveTextLevel(v)
            }
            Presets {
                kind: "text"
                values: JSON.parse(Companion.textPresets)
                current: Companion.textLevel
                onPicked: (v) => Companion.saveTextLevel(v)
            }
            Hint { text: "Darkens the white and grey text of the bar and the player row. Panels stay as they are." }

            Item { width: 1; height: 6 }
            Label { text: "Bar accent brightness" }
            Level {
                from: 0.4
                value: Companion.accentLevel
                onChanging: (v) => Companion.accentLevel = v
                onMoved: (v) => Companion.saveAccentLevel(v)
            }
            Presets {
                kind: "accent"
                values: JSON.parse(Companion.accentPresets)
                current: Companion.accentLevel
                onPicked: (v) => Companion.saveAccentLevel(v)
            }
            Hint { text: "Darkens the gold of the bar and the player row." }

            Item { width: 1; height: 6 }
            Label { text: "Bar size" }
            Level {
                from: 0.6
                value: Companion.barScale
                onChanging: (v) => Companion.barScale = v
                onMoved: (v) => Companion.saveBarScale(v)
            }
            Hint { text: "Shrinks the bar and the player row under it. Unlocked, drag the bar by its name or its slanted ends to move it sideways." }
            TextButton {
                text: "Center bar"
                onClicked: Companion.saveBarOffset(0)
            }

            Hint { text: "P1 to P3: a click uses the value, holding or a right click keeps the current one there." }
        }

        // Layouts
        Column {
            visible: settings.tab === "layouts"
            width: parent.width
            spacing: 10

            Label { text: "Save this arrangement" }
            Row {
                width: parent.width
                spacing: 10
                NameField {
                    id: newName
                    width: parent.width - saveButton.width - 10
                    placeholder: "Name, e.g. Raid or Farming"
                    onAccepted: saveButton.clicked()
                }
                TextButton {
                    id: saveButton
                    text: "Save"
                    onClicked: {
                        const name = newName.text.trim()
                        if (name.length === 0) { settings.layoutMessage = "Give it a name first."; return }
                        const replaced = settings.layouts.indexOf(name) >= 0
                        settings.saveLayoutRequested(name)
                        settings.layoutMessage = (replaced ? "Replaced " : "Saved ") + "\u201c" + name + "\u201d."
                        newName.text = ""
                    }
                }
            }
            Hint { text: "Keeps which panels are open, where they are, their size, what is pinned and the opacity. A name that exists is replaced." }
            Hint {
                visible: settings.layoutMessage.length > 0
                text: settings.layoutMessage
                color: Theme.accent
            }

            Item { width: 1; height: 4 }
            Label { text: "Saved layouts" }
            Hint {
                visible: settings.layouts.length === 0
                text: "None yet."
            }
            Repeater {
                model: settings.layouts
                delegate: Item {
                    id: layoutRow
                    required property string modelData
                    readonly property bool editing: settings.renaming === modelData
                    width: parent.width
                    height: 46
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        visible: !layoutRow.editing
                        anchors.left: parent.left
                        anchors.right: rowButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: layoutRow.modelData
                        color: Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                    NameField {
                        id: renameField
                        visible: layoutRow.editing
                        anchors.left: parent.left
                        anchors.right: rowButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        onVisibleChanged: if (visible) { text = layoutRow.modelData; forceActiveFocus() }
                        onAccepted: renameOk.clicked()
                    }
                    Row {
                        id: rowButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        TextButton {
                            visible: !layoutRow.editing
                            text: "Load"
                            onClicked: {
                                settings.loadLayoutRequested(layoutRow.modelData)
                                settings.layoutMessage = "Loaded \u201c" + layoutRow.modelData + "\u201d."
                            }
                        }
                        TextButton {
                            visible: !layoutRow.editing
                            text: "Rename"
                            onClicked: settings.renaming = layoutRow.modelData
                        }
                        TextButton {
                            id: renameOk
                            visible: layoutRow.editing
                            text: "OK"
                            onClicked: {
                                const name = renameField.text.trim()
                                if (name === layoutRow.modelData) { settings.renaming = ""; return }
                                if (Companion.renameLayout(layoutRow.modelData, name)) settings.renaming = ""
                                else settings.layoutMessage = name.length === 0 ? "A layout needs a name." : "\u201c" + name + "\u201d exists already."
                            }
                        }
                        TextButton {
                            visible: layoutRow.editing
                            text: "Cancel"
                            onClicked: settings.renaming = ""
                        }
                        IconButton {
                            visible: !layoutRow.editing
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "close"
                            tip: "Delete " + layoutRow.modelData
                            color: Theme.dim()
                            hoverColor: Theme.red
                            onClicked: {
                                Companion.deleteLayout(layoutRow.modelData)
                                settings.layoutMessage = "Deleted \u201c" + layoutRow.modelData + "\u201d."
                            }
                        }
                    }
                }
            }
            Hint { text: "Later, each game can bring its own layout, loaded when it starts." }
        }

        // Streams
        Column {
            visible: settings.tab === "streams"
            width: parent.width
            spacing: 10
            readonly property var account: JSON.parse(Streams.account)
            readonly property var game: JSON.parse(Streams.game)
            onVisibleChanged: if (visible) Streams.refreshAccount()
            property string part: nativeWindow.demo.indexOf("sponsor") >= 0 ? "sponsorblock"
                : nativeWindow.demo.indexOf("jellyfin") >= 0 ? "jellyfin"
                : nativeWindow.demo.indexOf("hwdec") >= 0 ? "videos" : "twitch"

            Row {
                spacing: 16
                Repeater {
                    model: [["twitch", "Twitch"], ["sponsorblock", "SponsorBlock"], ["jellyfin", "Jellyfin"], ["videos", "Videos"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool chosen: parent.parent.part === modelData[0]
                        width: partText.implicitWidth
                        height: 26
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            id: partText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.chosen ? Theme.accent : (partMouse.containsMouse ? Theme.text() : Theme.dim())
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                        }
                        Rectangle { visible: parent.chosen; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
                        MouseArea {
                            id: partMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.parent.parent.part = modelData[0]
                        }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }

            Column {
            visible: parent.part === "twitch"
            width: parent.width
            spacing: 10
            readonly property var account: parent.account
            readonly property var game: parent.game
            Label { text: "Twitch token" }
            Row {
                width: parent.width
                spacing: 8
                visible: !parent.account.user || parent.account.user === "?"
                NameField {
                    id: tokenField
                    width: parent.width - showToken.width - signIn.width - 16
                    placeholder: "twitch.tv's auth-token"
                    secret: !showToken.shown
                    maxLength: 80
                    onAccepted: signIn.clicked()
                }
                TextButton {
                    id: showToken
                    property bool shown: false
                    text: shown ? "Hide" : "Show"
                    onClicked: shown = !shown
                }
                TextButton {
                    id: signIn
                    text: "Sign in"
                    onClicked: { Streams.signIn(tokenField.text); tokenField.text = "" }
                }
            }
            Row {
                visible: !!parent.account.user && parent.account.user !== "?"
                spacing: 12
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.account.user === "…" ? "Checking with Twitch…" : "Signed in as " + parent.parent.account.user
                    color: Theme.accent
                    font.family: Theme.body
                    font.pixelSize: 13
                }
                TextButton { text: "Sign out"; danger: true; onClicked: Streams.signOut() }
            }
            Hint {
                visible: !!parent.account.error
                text: parent.account.error || ""
                color: Theme.red
            }
            Hint { text: "For the Following tab, and Twitch without ads with Turbo or a subscription. Sent only to Twitch; kept in its own file on this PC. Find it in your browser on twitch.tv: developer tools → Storage → Cookies → auth-token." }
            Hint {
                text: parent.account.streamlink ? "Streamlink is installed: Twitch plays without the ad breaks."
                    : "Streamlink is not installed: Twitch plays through yt-dlp, with its ad breaks (sudo pacman -S streamlink)."
                color: parent.account.streamlink ? Theme.dim() : Theme.textSoft()
            }

            Item { width: 1; height: 4 }
            Label { text: "Preset search for the game" }
            Hint { text: "Now: " + parent.game.name + " · Twitch category \u201c" + parent.game.twitch + "\u201d · YouTube \u201c" + parent.game.youtube + "\u201d. Change it with CHANGE in the Streams panel; with game detection, each game brings its own." }
            }

            Column {
            visible: parent.part === "sponsorblock"
            width: parent.width
            spacing: 10
            Item {
                id: sbHead
                width: parent.width
                height: 26
                readonly property var sb: JSON.parse(Streams.sponsorblock)
                property string message: ""
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Label { text: "SponsorBlock" }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        text: sbHead.sb.enabled ? "ON" : "OFF"
                        color: sbHead.sb.enabled ? Theme.accent : Theme.dim()
                        font.family: Theme.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    TextButton {
                        text: "Take from FreeTube"
                        onClicked: sbHead.message = Streams.sponsorFromFreetube()
                    }
                    TextButton {
                        text: sbHead.sb.enabled ? "Switch off" : "Switch on"
                        onClicked: Streams.setSponsorEnabled(!sbHead.sb.enabled)
                    }
                }
            }
            Hint { visible: sbHead.message.length > 0; text: sbHead.message; color: Theme.textSoft() }
            Column {
                width: parent.width
                opacity: sbHead.sb.enabled ? 1 : 0.45
                Repeater {
                    model: [["sponsor", "Sponsor"], ["selfpromo", "Self-promotion"], ["interaction", "Interaction reminder"],
                            ["intro", "Intro"], ["outro", "Outro"], ["preview", "Preview, recap"],
                            ["filler", "Filler, jokes"], ["music_offtopic", "Non-music part (music videos)"]]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 28
                        readonly property string mode: (sbHead.sb.categories || {})[modelData[0]] || "off"
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: Theme.textSoft()
                            font.family: Theme.body
                            font.pixelSize: 12
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Repeater {
                                model: [["skip", "Skip"], ["show", "Show"], ["off", "Off"]]
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool chosen: parent.parent.mode === modelData[0]
                                    width: choiceText.implicitWidth
                                    height: 24
                                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                        id: choiceText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData[1].toUpperCase()
                                        color: parent.chosen ? Theme.accent : (choiceMouse.containsMouse ? Theme.text() : Theme.dim())
                                        font.family: Theme.display
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                    }
                                    Rectangle { visible: parent.chosen; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
                                    MouseArea {
                                        id: choiceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Streams.setSponsorMode(parent.parent.parent.modelData[0], modelData[0])
                                    }
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData[1]
                                }
                            }
                        }
                    }
                }
            }
            Hint { text: "Skips or marks the parts of YouTube videos that viewers flagged. Asks sponsor.ajay.app with only the first four characters of the video's hash, so it never learns which video plays. Segments: SponsorBlock, CC BY-NC-SA 4.0." }
            }

            Column {
            visible: parent.part === "jellyfin"
            width: parent.width
            spacing: 10
            readonly property var jf: Jellyfin.account.length > 0 ? JSON.parse(Jellyfin.account) : null
            Label { text: "Jellyfin server" }
            JellyfinSignIn { visible: !parent.jf; width: parent.width }
            Item {
                visible: !!parent.jf
                width: parent.width
                height: 34
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        text: parent.parent.parent.jf ? "Signed in as " + parent.parent.parent.jf.user + " on " + parent.parent.parent.jf.serverName : ""
                        color: Theme.accent
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        text: parent.parent.parent.jf ? parent.parent.parent.jf.server : ""
                        color: Theme.dim()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                }
                TextButton { anchors.right: parent.right; text: "Sign out"; danger: true; onClicked: Jellyfin.signOut() }
            }
            Hint {
                visible: !!parent.jf
                text: "Signing out tells your server to forget this PC's key, and deletes it here."
            }
            Item { width: 1; height: 4 }
            OnOff {
                width: parent.width
                text: "Skip intros and credits by themselves"
                on: Jellyfin.autoSkip
                onToggled: Jellyfin.saveAutoSkip(!Jellyfin.autoSkip)
            }
            OnOff {
                width: parent.width
                text: "Play a show's next episode"
                on: Jellyfin.autoNext
                onToggled: Jellyfin.saveAutoNext(!Jellyfin.autoNext)
            }
            Hint { text: "Only a server in your home network (192.168.x.x, 10.x.x.x, 172.16-31.x.x, localhost, nas.local) is ever asked; anything else is refused before it is tried, and nothing goes through a proxy. Your server learns what plays and how far, so Continue watching is right in every Jellyfin app." }
            }

            Column {
            visible: parent.part === "videos"
            width: parent.width
            spacing: 10
            OnOff {
                width: parent.width
                text: "Hardware decoding"
                on: Streams.hwdec
                onToggled: Streams.saveHwdec(!Streams.hwdec)
            }
            Hint { text: "On: the graphics card unpacks the videos. The processor has less to do, and the video takes some video memory (a few hundred MB for a stream). Off: the processor does it, which leaves the video memory to the game but costs processor time. Changes take hold at once." }
            }
        }

        // Shortcuts
        Column {
            visible: settings.tab === "shortcuts"
            width: parent.width
            spacing: 6
            Repeater {
                model: settings.keys
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 46
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rowLine }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.description
                            color: Theme.text()
                            font.family: Theme.body
                            font.pixelSize: 13
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.state === "bound" ? "Set in KDE"
                                : modelData.state === "suggested" ? "Suggested, waiting for KDE"
                                : modelData.state === "nokey" ? "KDE gave it no key: set one in System Settings"
                                : "No shortcuts: " + modelData.state.replace("unavailable: ", "")
                            color: modelData.state === "bound" || modelData.state === "suggested" ? Theme.dim() : Theme.red
                            font.family: Theme.body
                            font.pixelSize: 11
                        }
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.key.length > 0 ? modelData.key.toUpperCase() : "—"
                        color: Theme.accent
                        font.family: Theme.display
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                }
            }
            Hint { text: "KDE keeps the keys. Change them in System Settings → Keyboard → Shortcuts → Game Companion." }
            Item {
                width: parent.width
                height: 40
                TextButton {
                    anchors.bottom: parent.bottom
                    text: "Open KDE shortcuts"
                    onClicked: Companion.openShortcutSettings()
                }
            }
        }

        // About
        Column {
            visible: settings.tab === "about"
            width: parent.width
            spacing: 8
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                text: "GAME COMPANION " + Companion.version().toUpperCase()
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 16
                font.weight: Font.Bold
                font.letterSpacing: 2
            }
            Hint { text: "One overlay for every game on Linux. Free software under the GNU GPL 3.0." }
            Hint { text: "The overlay works without the internet. It goes online only for the radio you play, Twitch and YouTube in Streams, SponsorBlock when you switch it on, and to look for its own updates on GitHub." }
            Hint { text: "Fonts: Rajdhani by the Indian Type Foundry and Inter by The Inter Project Authors, both under the SIL Open Font License 1.1." }
        }
    }

    component Tab: Item {
        property string name
        property string label
        width: tabText.implicitWidth
        height: 32
        readonly property bool current: settings.tab === name
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
        Rectangle {
            visible: parent.current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: Theme.accent
        }
        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: settings.tab = parent.name
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }
    component Label: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        text: ""
        color: Theme.text()
        font.family: Theme.display
        font.pixelSize: 13
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        Component.onCompleted: text = text.toUpperCase()
    }
    component NameField: Rectangle {
        property alias text: input.text
        property string placeholder: ""
        property bool secret: false
        property int maxLength: 40
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
            color: Theme.text()
            selectionColor: Theme.accent
            selectedTextColor: "#0c0c0f"
            font.family: Theme.body
            font.pixelSize: 13
            maximumLength: parent.maxLength
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: parent.accepted()
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: parent.parent.placeholder
                color: Theme.dim()
                font: input.font
            }
            Accessible.name: parent.placeholder
        }
    }
    // A choice that is on or off: its name, ON/OFF in the accent, a click switches.
    component OnOff: Item {
        id: onOff
        property string text
        property bool on: false
        signal toggled
        height: 30
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 70
            elide: Text.ElideRight
            text: onOff.text
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 13
        }
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            height: 26
            color: onOffMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
            border.color: onOff.on ? Theme.accent : Theme.track
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.centerIn: parent
                text: onOff.on ? "ON" : "OFF"
                color: onOff.on ? Theme.accent : Theme.dim()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
        MouseArea {
            id: onOffMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: onOff.toggled()
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: onOff.text
        Accessible.checked: onOff.on
    }
    // A slider from `from` to 100 %, with its value in the accent beside it.
    component Level: Row {
        id: level
        property real from: 0
        property real value: 1
        signal changing(real value)
        signal moved(real value)
        width: parent ? parent.width : 300
        spacing: 12
        HudSlider {
            width: parent.width - 60
            from: level.from
            to: 1
            value: level.value
            onChanging: (v) => level.changing(v)
            onMoved: (v) => level.moved(v)
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            text: Math.round(level.value * 100) + " %"
            color: Theme.accent
            font.family: Theme.display
            font.pixelSize: 15
            font.weight: Font.Bold
        }
    }
    // P1 to P3: a click jumps to the kept value, a long press or a right
    // click keeps the current one. The one matching now is gold.
    component Presets: Row {
        id: presets
        property string kind
        property var values: []
        property real current: 0
        signal picked(real value)
        spacing: 8
        Repeater {
            model: presets.values.length
            delegate: Rectangle {
                id: preset
                required property int index
                readonly property real value: presets.values[index]
                readonly property bool on: Math.abs(value - presets.current) < 0.005
                property bool kept: false
                width: 74
                height: 28
                color: presetMouse.containsMouse ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                border.color: on || kept ? Theme.accent : Theme.track
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.centerIn: parent
                    text: preset.kept ? "KEPT" : "P" + (preset.index + 1) + "  " + Math.round(preset.value * 100) + " %"
                    color: preset.on || preset.kept ? Theme.accent : Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
                Timer { id: keptTimer; interval: 900; onTriggered: preset.kept = false }
                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    pressAndHoldInterval: 600
                    property bool held: false
                    function keep() {
                        Companion.savePreset(presets.kind, preset.index, presets.current)
                        preset.kept = true
                        keptTimer.restart()
                    }
                    onPressed: held = false
                    onPressAndHold: { held = true; keep() }
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) keep()
                        else if (!held) presets.picked(preset.value)
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Preset " + (index + 1)
            }
        }
    }
    component Hint: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
        width: parent ? parent.width : 300
        wrapMode: Text.WordWrap
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 12
        lineHeight: 1.15
    }
}
