import QtQuick
import GameCompanion
import "theme.js" as Theme
import "launch.js" as Launch

// Proton versions (design L3Proton): the builds installed, grouped by where
// they come from, the games that use each, and a quick change per game.
// SAVE writes each changed game's launcher file (a backup first).
Column {
    id: view
    /// The library (Games.library's visible games).
    property var games: []
    property var choices: null
    /// Height the whole view may take on the screen.
    property real room: 700
    signal closed()
    signal saved(string warning)

    property var overview: null
    /// id → the build picked here, for games changed but not saved.
    property var picks: ({})
    property bool saving: false
    property var errors: []
    property bool steamRunning: false

    readonly property var tools: overview ? overview.tools.filter((t) => t.kind !== "tool") : []
    readonly property var used: overview ? overview.games : []
    readonly property var changedIds: Object.keys(picks).filter((id) => {
        const g = used.find((u) => u.id === id)
        return g && picks[id] !== g.choice
    })
    function nameOf(id) {
        const g = games.find((x) => x.id === id)
        return g ? g.name : id
    }
    readonly property var rows: {
        const list = used.filter((u) => u.canSet).slice()
        const last = (id) => { const g = games.find((x) => x.id === id); return g ? g.lastPlayed : 0 }
        list.sort((a, b) => (last(b.id) - last(a.id)) || nameOf(a.id).localeCompare(nameOf(b.id)))
        return list
    }

    spacing: 0

    Requests { id: req }

    function load() {
        const ids = games.filter((g) => !g.own).map((g) => g.id)
        req.ask(Games.protonOverview(JSON.stringify(ids)), (a) => {
            if (!a) return
            view.overview = a
            if (a.games.some((g) => g.launcher === "steam")) view.checkSteam()
        })
    }
    function checkSteam() {
        req.ask(Games.launcherState("steam:0"), (a) => view.steamRunning = !!a && a.running === true)
    }
    Component.onCompleted: load()

    Timer {
        interval: 3000
        repeat: true
        running: view.steamRunning && view.visible
        onTriggered: view.checkSteam()
    }

    function save() {
        const ids = changedIds
        if (ids.length === 0) return
        saving = true
        errors = []
        let waiting = ids.length
        const warnings = []
        for (const id of ids) {
            req.ask(Games.setProton(id, picks[id]), (a) => {
                if (!a || a.error.length > 0) view.errors = view.errors.concat([view.nameOf(id) + ": " + (a ? a.error : "no answer") + "."])
                else if (a.warning.length > 0 && warnings.indexOf(a.warning) < 0) warnings.push(a.warning)
                waiting -= 1
                if (waiting > 0) return
                view.saving = false
                if (view.errors.length === 0) {
                    view.saved(warnings.join(" "))
                } else {
                    // What was saved shows as saved; the rest stays picked.
                    view.load()
                }
            })
        }
    }

    // Header
    Item {
        width: parent.width
        height: 34
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                text: "PROTON VERSIONS"
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 16
                font.weight: Font.Bold
                font.letterSpacing: 2
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                text: view.overview ? view.tools.length + " INSTALLED" : "READING…"
                color: Theme.muted()
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
        }
        IconButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            tip: "Back to the games"
            color: Theme.dim()
            onClicked: view.closed()
        }
    }

    // Steam runs: it would undo a change when it quits.
    Rectangle {
        visible: view.steamRunning
        width: parent.width
        height: visible ? steamText.implicitHeight + 18 : 0
        color: Qt.rgba(214 / 255, 69 / 255, 61 / 255, 0.14)
        Rectangle { width: parent.width; height: 2; color: Theme.red }
        HudIcon { x: 12; y: 10; name: "warning"; size: 16; lineWidth: 2; color: Launch.red }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            id: steamText
            x: 38
            y: 9
            width: parent.width - 50
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            text: "<b>CLOSE STEAM FIRST</b>&nbsp;&nbsp;Steam writes its settings when it quits, which would undo a change to a Steam game."
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
        }
    }

    Item {
        width: parent.width
        height: Math.max(150, Math.min(content.implicitHeight, view.room - 34 - 50 - (view.steamRunning ? 60 : 0) - view.errors.length * 22))
        clip: true
        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: content
                width: flick.width
                bottomPadding: 6
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: view.overview === null
                    padding: 16
                    text: "Reading the launchers' folders…"
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: view.overview !== null && view.tools.length === 0
                    width: parent.width
                    padding: 16
                    wrapMode: Text.WordWrap
                    text: "No Proton or Wine build found in Steam, compatibilitytools.d, Heroic or Lutris."
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Repeater {
                    model: Launch.sourceOrder.filter((s) => view.tools.some((t) => t.source === s))
                    delegate: Column {
                        id: group
                        required property var modelData
                        width: content.width
                        Row {
                            x: 16
                            height: 34
                            spacing: 10
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                text: Launch.sources[group.modelData].name
                                color: Theme.text()
                                font.family: Theme.display
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 7
                                text: Launch.sources[group.modelData].path
                                color: Theme.dim()
                                font.family: Launch.mono
                                font.pixelSize: 11
                            }
                        }
                        Repeater {
                            model: view.tools.filter((t) => t.source === group.modelData)
                            delegate: VersionRow {}
                        }
                    }
                }

                // Quick change per game.
                Item {
                    visible: view.rows.length > 0
                    width: parent.width
                    height: 40
                    Rectangle { y: 6; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: quickTitle
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: "QUICK CHANGE PER GAME"
                        color: Theme.text()
                        font.family: Theme.display
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.baseline: quickTitle.baseline
                        text: "Only versions the game's launcher can use are listed."
                        color: Theme.dim()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                }
                Repeater {
                    model: view.rows
                    delegate: GameRow {}
                }
            }
        }
        WheelScroll { flick: flick; step: 90 }
        Rectangle {
            visible: flick.contentHeight > flick.height + 1
            anchors.right: parent.right
            width: 3
            height: parent.height
            color: Theme.trackDark
            Rectangle {
                width: parent.width
                height: Math.max(24, parent.height * flick.height / flick.contentHeight)
                y: (parent.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
                color: Theme.track
            }
        }
    }

    Repeater {
        model: view.errors
        delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow
            required property var modelData
            width: view.width
            topPadding: 6
            wrapMode: Text.WordWrap
            text: "Couldn't save " + modelData
            color: Theme.red
            font.family: Theme.body
            font.pixelSize: 12
        }
    }

    // Footer
    Item {
        width: parent.width
        height: 50
        Rectangle { x: -14; y: 4; width: parent.width + 28; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Row {
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            height: 34
            spacing: 8
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: Theme.accent }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 14
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: "Read from the launchers' folders on this PC. A change is written to that launcher's file; a backup is kept first. Steam must be closed."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 10
            TextButton { text: "Cancel"; onClicked: view.closed() }
            Rectangle {
                readonly property bool ready: view.changedIds.length > 0 && !view.saving
                    && !(view.steamRunning && view.changedIds.some((id) => id.indexOf("steam:") === 0))
                width: saveText.implicitWidth + 32
                height: 34
                color: ready ? (saveMouse.containsMouse ? Theme.accentLight : Theme.accent) : "transparent"
                border.color: ready ? Theme.accent : "#3a3842"
                Text {
                    id: saveText
                    anchors.centerIn: parent
                    text: view.saving ? "SAVING…" : "SAVE"
                    color: parent.ready ? "#121116" : Theme.dim()
                    style: parent.ready ? Text.Normal : Theme.textStyle()
                    styleColor: Theme.shadow
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                MouseArea {
                    id: saveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: parent.ready
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.save()
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Save"
            }
        }
    }

    // One build: the games that use it, Steam's default.
    component VersionRow: Item {
        id: version
        required property var modelData
        readonly property var t: modelData
        readonly property var users: view.used.filter((u) => u.inUse === t.name)
        readonly property bool isDefault: view.overview !== null && view.overview.steamDefault === t.name
        width: content.width
        height: Math.max(40, gamesFlow.implicitHeight + 12)
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
        Rectangle {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            color: version.users.length > 0 ? Theme.accent : "#5a5764"
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 34
            width: 230
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: version.t.label + (version.t.kind === "wine" ? " (Wine)" : "")
            color: version.users.length > 0 ? Theme.text() : Theme.muted()
            font.family: Theme.body
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Flow {
            id: gamesFlow
            x: 276
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - (defaultTag.visible ? defaultTag.width + 12 : 0) - 60
            spacing: 4
            Repeater {
                model: version.users
                delegate: Rectangle {
                    required property var modelData
                    width: Math.min(useText.implicitWidth + 14, gamesFlow.width)
                    height: 20
                    color: "#1b1a20"
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: useText
                        x: 7
                        width: parent.width - 14
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: view.nameOf(modelData.id) + (modelData.choice === "" ? " · default" : "")
                        color: Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: version.users.length === 0
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: "Not used"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Tag {
            id: defaultTag
            visible: version.isDefault
            anchors.right: countText.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "STEAM DEFAULT"
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            id: countText
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            horizontalAlignment: Text.AlignRight
            text: version.users.length
            color: Theme.muted()
            font.family: Theme.display
            font.pixelSize: 14
            font.weight: Font.Bold
        }
    }

    // One game with its build to pick.
    component GameRow: Item {
        id: row
        required property var modelData
        readonly property var u: modelData
        readonly property string pick: view.picks[u.id] !== undefined ? view.picks[u.id] : u.choice
        width: content.width
        height: 46
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 16 - 60 - 230 - 44
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: view.nameOf(row.u.id)
            color: Theme.text()
            font.family: Theme.body
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Rectangle {
            anchors.right: select.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 60
            height: 18
            color: "transparent"
            border.color: "#5a5764"
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.centerIn: parent
                text: Launch.launcherName(row.u.launcher).toUpperCase()
                color: Theme.textSoft()
                font.family: Theme.display
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
        SelectBox {
            id: select
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 230
            height: 34
            choices: view.choices
            options: Launch.choicesFor(view.tools, row.u.launcher, view.overview ? view.overview.steamDefault : "")
            current: row.pick
            changed: row.pick !== row.u.choice
            accessibleName: "Proton for " + view.nameOf(row.u.id)
            onChosen: (id) => {
                const p = Object.assign({}, view.picks)
                p[row.u.id] = id
                view.picks = p
            }
        }
    }
}
