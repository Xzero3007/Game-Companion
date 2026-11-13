import QtQuick
import GameCompanion
import "theme.js" as Theme
import "plugins.js" as Plugins
import "aion2/timekit.js" as TK

// Settings: how solid the panels are, the shortcuts, and what this is.
Panel {
    id: settings
    panelId: "settings"
    title: "Settings"
    width: 500

    property string tab: nativeWindow.demo.indexOf("display") >= 0 ? "display"
        : nativeWindow.demo.indexOf("timers") >= 0 ? "plugins"
        : nativeWindow.demo.indexOf("sponsor") >= 0 || nativeWindow.demo.indexOf("jellyfin") >= 0 || nativeWindow.demo.indexOf("hwdec") >= 0
        || nativeWindow.demo.indexOf("ytsettings") >= 0 ? "streams" : "general"
    property var keys: JSON.parse(Companion.shortcuts)
    readonly property var layouts: JSON.parse(Companion.layouts)
    /// The layout being renamed ("" for none).
    property string renaming: ""
    property string layoutMessage: ""
    minWidth: 400
    /// The Map panel: the overlay map's settings are kept in its own.
    property var mapSource: null
    /// The Schedule's store (its settings fold out under Event Timers).
    property var timerStore: null
    function keyOf(id) {
        for (const k of keys) if (k.id === id) return k.key
        return ""
    }
    signal saveLayoutRequested(string name)
    signal loadLayoutRequested(string name)
    Component.onCompleted: {
        for (const t of ["display", "layouts", "streams-settings", "shortcuts", "about", "plugins"]) if (nativeWindow.demo.indexOf(t) >= 0) tab = t.replace("-settings", "")
        if (nativeWindow.demo.indexOf("startmenu") >= 0) startChoice.open = true
    }

    Column {
        width: parent.width
        spacing: 12

        Row {
            spacing: 12
            Tab { name: "general"; label: "General" }
            Tab { name: "plugins"; label: "Plugins" }
            Tab { name: "display"; label: "Display" }
            Tab { name: "layouts"; label: "Layouts" }
            Tab { name: "streams"; label: "Streams" }
            Tab { name: "shortcuts"; label: "Shortcuts" }
            Tab { name: "about"; label: "About" }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.divider; anchors.topMargin: -12 }

        // Plugins: grouped by package (global, then one per game), each
        // plugin on or off and with its button in the bar or not.
        Column {
            id: pluginsPage
            visible: settings.tab === "plugins"
            width: parent.width
            spacing: 10
            readonly property var all: JSON.parse(Companion.plugins)
            property string packageId: nativeWindow.demo.indexOf("pluginsglobal") >= 0 ? "global" : "aion2"
            readonly property var pack: Plugins.packages.filter((p) => p.id === packageId)[0]

            Row {
                spacing: 16
                Repeater {
                    model: Plugins.packages
                    delegate: Item {
                        required property var modelData
                        readonly property bool chosen: pluginsPage.packageId === modelData.id
                        readonly property bool loaded: modelData.id === "aion2" && Aion2.active
                        width: packRow.implicitWidth
                        height: 26
                        Row {
                            id: packRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                color: !modelData.game ? Theme.muted() : parent.parent.loaded ? Theme.purple : "transparent"
                                border.color: modelData.game ? Theme.purple : Theme.muted()
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                text: modelData.name.toUpperCase()
                                color: parent.parent.chosen ? Theme.accent : (packMouse.containsMouse ? Theme.text() : Theme.dim())
                                font.family: Theme.display
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                            }
                        }
                        Rectangle { visible: parent.chosen; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
                        MouseArea {
                            id: packMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pluginsPage.packageId = modelData.id
                        }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.name
                    }
                }
            }

            Hint {
                text: pluginsPage.pack.about
                    + (pluginsPage.pack.id === "aion2" ? (Aion2.active ? " Running now: loaded." : " Not running: nothing loaded.") : "")
            }
            OnOff {
                visible: pluginsPage.pack.game
                width: parent.width
                text: "Load with the game"
                on: Plugins.loads(pluginsPage.all, pluginsPage.pack.id)
                onToggled: Companion.setPackage(pluginsPage.pack.id, !Plugins.loads(pluginsPage.all, pluginsPage.pack.id))
            }
            Hint {
                visible: pluginsPage.pack.plugins.length === 0
                text: "No plugins in this package yet."
            }

            Repeater {
                model: pluginsPage.pack.plugins
                delegate: Item {
                    id: plugRow
                    required property var modelData
                    readonly property var p: modelData
                    readonly property var c: Plugins.choice(pluginsPage.all, p.id)
                    readonly property bool usable: !pluginsPage.pack.game || Plugins.loads(pluginsPage.all, pluginsPage.pack.id)
                    width: pluginsPage.width
                    readonly property real headHeight: Math.max(48, plugText.implicitHeight + 16)
                    // The Map's overlay map: its settings fold out under it.
                    readonly property bool hasOverlay: p.id === "aion2.map" && !!settings.mapSource
                    // The Event Timers' sources and alerts fold out the same way.
                    readonly property bool hasTimers: p.id === "aion2.timers" && !!settings.timerStore
                    property bool expanded: (hasOverlay && nativeWindow.demo.indexOf("overlay") >= 0)
                        || (hasTimers && nativeWindow.demo.indexOf("timers") >= 0)
                    height: headHeight + (expanded ? overlayBox.height + 12 : 0)
                    opacity: (p.fixed || c.on) && usable ? 1 : 0.55
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                    Rectangle {
                        y: 8
                        width: 30
                        height: 30
                        color: pluginsPage.pack.game ? Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.25) : Qt.rgba(1, 1, 1, 0.08)
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.centerIn: parent
                            text: plugRow.p.short
                            color: pluginsPage.pack.game ? "#e6dbfa" : Theme.textSoft()
                            font.family: Theme.display
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                    Column {
                        id: plugText
                        x: 42
                        y: 8
                        width: parent.width - 42 - controls.width - 10
                        spacing: 2
                        Row {
                            spacing: 8
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                text: plugRow.p.name
                                color: Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                visible: !plugRow.p.built
                                anchors.verticalCenter: parent.verticalCenter
                                width: comingText.implicitWidth + 10
                                height: 16
                                color: "transparent"
                                border.color: Theme.dim()
                                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                    id: comingText
                                    anchors.centerIn: parent
                                    text: "COMING"
                                    color: Theme.dim()
                                    font.family: Theme.display
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                }
                            }
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: plugRow.p.about
                            color: Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 12
                        }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right
                        y: 10
                        spacing: 8
                        SmallToggle {
                            visible: plugRow.hasTimers
                            width: 92
                            text: "SETTINGS " + (plugRow.expanded ? "▴" : "▾")
                            on: plugRow.expanded
                            tip: "Where the times come from, and the alerts"
                            onClicked: plugRow.expanded = !plugRow.expanded
                        }
                        SmallToggle {
                            visible: plugRow.hasOverlay
                            width: 92
                            text: "OVERLAY " + (plugRow.expanded ? "▴" : "▾")
                            on: plugRow.expanded
                            tip: "The overlay map's settings"
                            onClicked: plugRow.expanded = !plugRow.expanded
                        }
                        // Where its button sits: the bar, or none.
                        SmallToggle {
                            visible: !plugRow.p.fixed
                            enabled: plugRow.c.on
                            width: 78
                            text: plugRow.c.place === "bar" ? "IN ROW" : "HIDDEN"
                            on: plugRow.c.on && plugRow.c.place === "bar"
                            tip: "Whether its button shows in the game's row under the bar"
                            onClicked: Companion.setPlugin(plugRow.p.id, plugRow.c.on, plugRow.c.place === "bar" ? "hidden" : "bar")
                        }
                        SmallToggle {
                            width: 52
                            text: plugRow.p.fixed ? "CORE" : plugRow.c.on ? "ON" : "OFF"
                            on: plugRow.p.fixed || plugRow.c.on
                            enabled: !plugRow.p.fixed
                            tip: plugRow.p.fixed ? "Part of Game Companion itself" : "Switch the plugin on or off"
                            onClicked: Companion.setPlugin(plugRow.p.id, !plugRow.c.on, plugRow.c.place)
                        }
                    }
                    Loader {
                        id: overlayBox
                        active: plugRow.expanded
                        x: 42
                        y: plugRow.headHeight
                        width: plugRow.width - 42
                        height: item ? item.implicitHeight : 0
                        sourceComponent: plugRow.hasTimers ? timersComponent : overlayComponent
                    }
                }
            }
            Hint { text: pluginsPage.pack.game
                ? "Global plugins sit in their own group and are never mixed with a game's. A plugin marked COMING is still being moved over from the AION 2 meter; your choice is kept for when it arrives."
                : "Radio and Streams are part of Game Companion and always there." }
        }

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
            Label { text: "Start" }
            Dropdown {
                id: startChoice
                width: parent.width
                z: 30
                label: "With the desktop"
                options: [
                    { id: "off", name: "Off" },
                    { id: "hidden", name: Companion.tray ? "Hidden (tray icon only)" : "Hidden" },
                    { id: "visible", name: "Visible (hub shown)" }
                ]
                current: Companion.autostartMode
                onChosen: (id) => Companion.setAutostartTo(id)
            }
            Hint { text: Companion.autostartMode === "hidden"
                ? (Companion.tray
                    ? "Starts when you log in with only the tray icon; the hub shows when a game starts or from the tray."
                    : "Starts hidden when you log in, with no tray icon (it is off below); the hub shows when a game starts, with Alt+Y, or when you start Game Companion again from the application menu.")
                : Companion.autostartMode === "visible"
                ? "Starts when you log in with the hub shown."
                : "Start it yourself from the application menu. Starting it again while it runs brings the hub forward." }
            OnOff {
                width: parent.width
                text: "Show the hub when a game starts"
                on: Companion.showOnGame
                onToggled: Companion.setShowOnGameOn(!Companion.showOnGame)
            }
            Hint { text: "Hides again when the game ends. Each game's own start options (Games) apply on top." }
            OnOff {
                width: parent.width
                text: "Tray icon"
                on: Companion.tray
                onToggled: Companion.setTrayOn(!Companion.tray)
            }
            Hint { text: "A gold gamepad in the panel while Game Companion runs: a click shows or hides the hub, a right click opens its menu." }

            Item { width: 1; height: 6 }
            Label { text: "Games" }
            OnOff {
                width: parent.width
                text: "Download missing covers"
                on: Games.downloadCovers
                onToggled: Games.saveDownloadCovers(!Games.downloadCovers)
            }
            Hint { text: "From Steam, Epic and GOG image servers; only the game's id is sent. Each cover is fetched once and kept." }

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
            Label { text: "Scrolling" }
            Dropdown {
                width: parent.width
                z: 29
                label: "Scroll speed"
                options: [50, 100, 150, 200, 300].map((p) => ({ id: String(p), name: p + " %" }))
                current: String(Companion.wheelSpeed)
                onChosen: (id) => Companion.saveWheelSpeed(parseInt(id))
            }
            Hint { text: "How far one notch of the mouse wheel moves a list." }

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
                : nativeWindow.demo.indexOf("hwdec") >= 0 ? "videos"
                : nativeWindow.demo.indexOf("ytsettings") >= 0 ? "youtube" : "twitch"

            Row {
                spacing: 16
                Repeater {
                    model: [["twitch", "Twitch"], ["youtube", "YouTube"], ["sponsorblock", "SponsorBlock"], ["jellyfin", "Jellyfin"], ["videos", "Videos"]]
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
            Label { text: "Live notes" }
            OnOff {
                width: parent.width
                text: "Tell me when followed or favorite channels go live"
                on: Streams.alerts
                onToggled: Streams.switchAlerts(!Streams.alerts)
            }
            Hint { text: "Asks Twitch every two minutes while on. A red count shows on the Streams panel's Following tab and the channels show at the top of the list; no pop-up, no sound. Leave one channel out with ⋯ beside it." }

            Item { width: 1; height: 4 }
            Label { text: "Chat" }
            OnOff {
                width: parent.width
                text: "Write in chat with this sign-in"
                on: Streams.chatWrite
                onToggled: Streams.saveChatWrite(!Streams.chatWrite)
            }
            Hint { text: "Show the chat with the speech bubble on the Twitch video. Off, or not signed in, the chat is read only. Emotes come from Twitch, 7TV and BTTV." }

            Item { width: 1; height: 4 }
            Label { text: "Preset search for the game" }
            Hint { text: "Now: " + parent.game.name + " · Twitch category \u201c" + parent.game.twitch + "\u201d · YouTube \u201c" + parent.game.youtube + "\u201d. Change it with CHANGE in the Streams panel; with game detection, each game brings its own." }
            }

            Column {
            visible: parent.part === "youtube"
            width: parent.width
            spacing: 10
            readonly property var filters: JSON.parse(Streams.filters)
            readonly property var words: JSON.parse(Streams.trendWords)
            Label { text: "FreeTube" }
            Row {
                spacing: 10
                TextButton {
                    text: Streams.freetubeLive ? "Take over from FreeTube" : "Take over again"
                    onClicked: takeNote.text = Streams.takeFreetube()
                }
            }
            Connections {
                target: Streams
                function onFreetubeTaken(note) { takeNote.text = note; Library.refresh() }
            }
            Hint {
                id: takeNote
                text: Streams.freetubeLive
                    ? "Now FreeTube's subscriptions are read from its file as they are. Taking over copies its subscriptions (with its profiles as groups), playlists, bookmark list and history into Game Companion once; then FreeTube is no longer needed. FreeTube's files are only read."
                    : "Your subscriptions, playlists and history live here now. Taking over again adds what is new in FreeTube (nothing is doubled)."
            }

            Item { width: 1; height: 4 }
            Label { text: "In the lists" }
            OnOff { width: parent.width; text: "Leave Shorts out"; on: parent.filters.shorts; onToggled: Streams.setHideShorts(!parent.filters.shorts) }
            OnOff { width: parent.width; text: "Leave watched videos out"; on: parent.filters.watched; onToggled: Streams.setHideWatched(!parent.filters.watched) }
            OnOff { width: parent.width; text: "Leave Indian content out"; on: parent.filters.indian !== false; onToggled: Streams.setHideIndian(parent.filters.indian === false) }
            Hint { text: "Videos whose title or channel is written in an Indian script (Hindi, Bengali, Tamil, Telugu and others)." }
            Row {
                width: parent.width
                spacing: 8
                NameField {
                    id: wordsField
                    width: parent.width - wordsSave.width - 8
                    wrap: true
                    placeholder: "Words whose videos never show, with commas"
                    maxLength: 400
                    text: parent.parent.filters.words.join(", ")
                    onAccepted: wordsSave.clicked()
                }
                TextButton { id: wordsSave; text: "Save"; onClicked: Streams.setHiddenWords(wordsField.text) }
            }
            Flow {
                visible: parent.filters.channels.length > 0
                width: parent.width
                spacing: 6
                Repeater {
                    model: parent.parent.filters.channels
                    delegate: Chip {
                        required property var modelData
                        text: modelData.name + "  ×"
                        onClicked: Streams.toggleHiddenChannel(modelData.id, modelData.name)
                    }
                }
            }
            Hint { text: parent.filters.channels.length > 0 ? "Hidden channels: a click shows one again. Hide one with ⋯ beside its video." : "Hide a channel with ⋯ beside one of its videos." }

            Item { width: 1; height: 4 }
            Label { text: "Video languages" }
            Flow {
                width: parent.width
                spacing: 6
                readonly property var chosen: JSON.parse(Streams.videoLanguages)
                Repeater {
                    model: [["de", "German"], ["tr", "Turkish"], ["en", "English"], ["fr", "French"], ["it", "Italian"], ["es", "Spanish"], ["nl", "Dutch"], ["pl", "Polish"]]
                    delegate: Chip {
                        required property var modelData
                        text: modelData[1]
                        on: parent.chosen.indexOf(modelData[0]) >= 0
                        onClicked: Streams.toggleVideoLanguage(modelData[0])
                    }
                }
            }
            Hint { text: "Searches and Trending ask YouTube in these languages, so videos from those countries come first; Gaming, Europe and the national teams also search with each language's word (\u201cgaming deutsch\u201d). None chosen: as YouTube gives it. Takes effect on the next load." }

            Item { width: 1; height: 4 }
            Label { text: "Trending: search words" }
            Repeater {
                model: [["gaming", "Gaming"], ["europe", "Europe"], ["national", "National teams"], ["tr", "Süper Lig"], ["de", "Bundesliga"],
                        ["en", "Premier League"], ["fr", "Ligue 1"], ["it", "Serie A"], ["es", "LaLiga"]]
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    spacing: 8
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        y: 9
                        width: 110
                        wrapMode: Text.WordWrap
                        text: modelData[1]
                        color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 12 }
                    NameField {
                        id: trendField
                        width: parent.width - 118
                        wrap: true
                        maxLength: 400
                        placeholder: "Search words, with commas (empty: as it came)"
                        text: (JSON.parse(Streams.trendWords)[modelData[0]] || []).join(", ")
                        onAccepted: Streams.changeTrendWords(modelData[0], text)
                    }
                }
            }
            Hint { text: "Each part asks YouTube's search (through yt-dlp) for this week's videos with these words and mixes the answers; Gaming takes this week's most watched. Enter saves a line." }
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

    // A line of the overlay map's settings: its name, then its choices.
    component OverlayLine: Row {
        property string label
        default property alias content: holder.data
        width: parent ? parent.width : 400
        spacing: 10
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            width: 92
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: parent.label
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
        }
        Flow { id: holder; width: parent.width - 102; spacing: 6 }
    }

    Component { id: overlayComponent; OverlaySettings { map: settings.mapSource } }
    Component { id: timersComponent; ScheduleSettings { store: settings.timerStore } }

    // The Event Timers' settings (canvas board T3): where the times come
    // from, and how alerts show.
    component ScheduleSettings: Column {
        id: sch
        property var store
        readonly property var p: store.prefs
        spacing: 8
        OverlayLine {
            label: "The game"
            Chip { text: sch.p.game ? "On" : "Off"; on: sch.p.game; onClicked: sch.store.change({ game: !sch.p.game }) }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width - 60; wrapMode: Text.WordWrap; topPadding: 4
                text: "boss times when you open a map; read only"; color: Theme.dim(); font.family: Theme.body; font.pixelSize: 12 }
        }
        OverlayLine {
            label: "Fixed times"
            Chip { text: sch.p.fixed ? "On" : "Off"; on: sch.p.fixed; onClicked: sch.store.change({ fixed: !sch.p.fixed }) }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width - 60; wrapMode: Text.WordWrap; topPadding: 4
                text: "events and scheduled bosses from the game's tables; offline"; color: Theme.dim(); font.family: Theme.body; font.pixelSize: 12 }
        }
        OverlayLine {
            label: "Aion 2 Timers"
            Chip { text: sch.p.a2t ? "On" : "Off"; on: sch.p.a2t; onClicked: { sch.store.change({ a2t: !sch.p.a2t }); if (sch.store.prefs.a2t) sch.store.refreshFeed(true) } }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width - 60; wrapMode: Text.WordWrap
                text: "aion2timers.com (by HomelessGuyNABox) fills in the maps you haven't opened: one request every 5 minutes while the Schedule is open, else every 15 while a boss alert waits. Asks with your server's name only."
                    + (sch.store.serverSlug() ? " (" + sch.store.serverSlug() + ")" : "")
                color: Theme.dim(); font.family: Theme.body; font.pixelSize: 12 }
        }
        OverlayLine {
            label: "Server time"
            Chip { text: "From my server"; on: sch.p.region === "auto"; onClicked: sch.store.change({ region: "auto" }) }
            Repeater {
                model: [1, 2, 3, 4, 5]
                delegate: Chip {
                    required property int modelData
                    text: TK.REGIONS[modelData].name
                    on: sch.p.region !== "auto" && Number(sch.p.region) === modelData
                    onClicked: sch.store.change({ region: modelData })
                }
            }
        }
        OverlayLine {
            label: "Alert"
            Repeater {
                model: [1, 3, 5, 10, 15]
                delegate: Chip {
                    required property int modelData
                    text: modelData + " min before"
                    on: sch.p.lead === modelData
                    onClicked: sch.store.change({ lead: modelData })
                }
            }
            Chip { text: "Also as it starts"; on: sch.p.atStart; onClicked: sch.store.change({ atStart: !sch.p.atStart }) }
        }
        OverlayLine {
            label: "Show"
            Chip { text: "Banner"; on: sch.p.banner; onClicked: sch.store.change({ banner: !sch.p.banner }) }
            Chip { text: "Voice"; on: sch.p.voice; visible: Aion2.canSpeak() || sch.p.voice; onClicked: sch.store.change({ voice: !sch.p.voice }) }
            Chip { text: "Also while AION 2 is closed"; on: sch.p.closed; onClicked: sch.store.change({ closed: !sch.p.closed }) }
        }
        OverlayLine {
            label: "Sound"
            Chip { text: "None"; on: sch.p.sound === "none"; onClicked: sch.store.change({ sound: "none" }) }
            Repeater {
                model: ["chime", "bell", "ping", "gong", "soft"]
                delegate: Chip {
                    required property string modelData
                    text: modelData
                    on: sch.p.sound === modelData
                    onClicked: { sch.store.change({ sound: modelData }); Aion2.chime(modelData, sch.p.volume) }
                }
            }
        }
        OverlayLine {
            label: "Volume"
            HudSlider {
                width: 150
                from: 0
                to: 100
                value: sch.p.volume
                onMoved: (v) => { sch.store.change({ volume: Math.round(v) }); Aion2.chime(sch.p.sound === "none" ? "chime" : sch.p.sound, Math.round(v)) }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24; verticalAlignment: Text.AlignVCenter
                text: sch.p.volume + " %"; color: Theme.accent; font.family: Theme.body; font.pixelSize: 12 }
        }
        OverlayLine {
            label: ""
            Chip { text: "Forget this server's boss times"; onClicked: sch.store.forget() }
        }
    }

    // The overlay map's settings (canvas board O2Settings): on, size,
    // opacity, marks, what it shows, where it hides, places 1 to 3.
    component OverlaySettings: Column {
        id: ovs
        property var map
        readonly property var o: map.settings.overlay
        spacing: 8
        OverlayLine {
            label: "Overlay map"
            Chip { text: ovs.o.on ? "Shown over the game" : "Off"; on: ovs.o.on; onClicked: ovs.map.toggleOverlay() }
        }
        OverlayLine {
            label: "Size"
            Repeater {
                model: ["s", "m", "l", "xl"]
                delegate: Chip {
                    required property string modelData
                    text: modelData
                    on: ovs.o.w <= 0 && ovs.o.size === modelData
                    onClicked: ovs.map.changeOverlay({ size: modelData, w: 0, slot: -1 })
                }
            }
        }
        OverlayLine {
            label: "Opacity"
            HudSlider {
                width: 150
                from: 0.1
                to: 1
                value: ovs.o.opacity
                onChanging: (v) => ovs.map.changeOverlay({ opacity: v })
                onMoved: (v) => ovs.map.changeOverlay({ opacity: v })
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.StyledText
                text: Math.round(ovs.o.opacity * 100) + " % <font color='" + Theme.dim() + "'>(marks stay solid)</font>"
                color: Theme.accent
                font.family: Theme.body
                font.pixelSize: 12
            }
        }
        OverlayLine {
            label: "Marks"
            Repeater {
                model: [1, 1.25, 1.5, 1.75]
                delegate: Chip {
                    required property real modelData
                    text: Math.round(modelData * 100) + " %"
                    on: Math.abs(ovs.o.markScale - modelData) < 0.01
                    onClicked: ovs.map.changeOverlay({ markScale: modelData })
                }
            }
        }
        OverlayLine {
            label: "Shows"
            Chip { text: "The Map's layers"; on: !ovs.o.own; onClicked: ovs.map.changeOverlay({ own: false }) }
            Chip { text: "Own choice"; on: ovs.o.own; onClicked: ovs.map.changeOverlay({ own: true }) }
        }
        OverlayLine {
            visible: ovs.o.own
            label: ""
            Repeater {
                model: [["pets", "Pets"], ["monsters", "Monsters"], ["gather", "Gathering"], ["cubes", "Hidden Cubes"], ["monoliths", "Feathers"],
                        ["kibelisks", "Kibelisks"], ["places", "Places"], ["services", "Services"], ["quests", "Quests"], ["npcs", "NPCs"]]
                delegate: Chip {
                    required property var modelData
                    text: modelData[1]
                    on: !!ovs.o.layers[modelData[0]]
                    onClicked: {
                        const l = Object.assign({}, ovs.o.layers)
                        l[modelData[0]] = !l[modelData[0]]
                        ovs.map.changeOverlay({ layers: l })
                    }
                }
            }
        }
        OverlayLine {
            label: "Hide in"
            Repeater {
                model: [["instance", "Dungeons"], ["arena", "Arena"], ["abyss", "Abyss"]]
                delegate: Chip {
                    required property var modelData
                    text: modelData[1]
                    on: !!ovs.o.hideIn[modelData[0]]
                    onClicked: {
                        const h = Object.assign({}, ovs.o.hideIn)
                        h[modelData[0]] = !h[modelData[0]]
                        ovs.map.changeOverlay({ hideIn: h })
                    }
                }
            }
        }
        OverlayLine {
            label: "Places"
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: slotBox
                    required property int index
                    readonly property bool kept: !!ovs.o.slots[index]
                    readonly property bool current: ovs.o.slot === index
                    property bool justKept: false
                    width: 34
                    height: 24
                    color: current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.14) : slotMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                    border.color: current || justKept ? Theme.accent : "#3a3842"
                    opacity: kept || justKept ? 1 : 0.6
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        anchors.centerIn: parent
                        text: slotBox.justKept ? "✓" : String(slotBox.index + 1)
                        color: slotBox.current || slotBox.justKept ? Theme.accent : Theme.muted()
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Timer { id: slotKeptTimer; interval: 900; onTriggered: slotBox.justKept = false }
                    MouseArea {
                        id: slotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) { ovs.map.keepSlot(slotBox.index); slotBox.justKept = true; slotKeptTimer.restart() }
                            else ovs.map.useSlot(slotBox.index)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Place " + (index + 1) + " (right-click: keep where it is now)"
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: "right-click keeps where it is now"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        OverlayLine {
            label: "Shortcut"
            Rectangle {
                width: keyText.implicitWidth + 16
                height: 24
                color: "transparent"
                border.color: "#3a3842"
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    id: keyText
                    anchors.centerIn: parent
                    text: (settings.keyOf("map-overlay") || "Alt+M").toUpperCase()
                    color: Theme.textSoft()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width - keyText.implicitWidth - 24
                topPadding: 4
                wrapMode: Text.WordWrap
                text: "or right-click MAP in the game row. KDE keeps the keys (Shortcuts tab)."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
    }

    // A small framed switch: its text in the accent while on.
    component SmallToggle: Rectangle {
        id: smallToggle
        property string text
        property bool on: false
        property string tip: ""
        signal clicked
        height: 26
        color: smallMouse.containsMouse && enabled ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
        border.color: on ? Theme.accent : Theme.track
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            anchors.centerIn: parent
            text: smallToggle.text
            color: smallToggle.on ? Theme.accent : Theme.dim()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        MouseArea {
            id: smallMouse
            anchors.fill: parent
            enabled: smallToggle.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: smallToggle.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.description: tip
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
        // Long text wraps onto more lines instead of scrolling out of sight.
        property bool wrap: false
        signal accepted
        function forceActiveFocus() { input.forceActiveFocus() }
        height: wrap ? Math.max(34, input.contentHeight + 16) : 34
        color: "#1b1a20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: input.activeFocus ? Theme.accent : "#3a3842" }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            wrapMode: parent.wrap ? TextInput.WrapAtWordBoundaryOrAnywhere : TextInput.NoWrap
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
