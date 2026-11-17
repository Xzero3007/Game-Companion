import QtQuick
import GameCompanion
import "theme.js" as Theme

// GET PROTON (MN, 2026-11-16): GE-Proton and Proton-CachyOS from their
// GitHub releases. What is new, whether a game of the library is named in
// the release notes, install with a progress bar, remove old downloads.
// `ProtonGet` asks GitHub only when this view opens (at most every 6 h) or
// on ↻; nothing runs while it is closed.
Column {
    id: box
    /// The library's games (names for the release notes).
    property var games: []
    /// The overview's builds and games, to count the games using a download.
    property var tools: []
    property var used: []

    readonly property var s: {
        try { return JSON.parse(ProtonGet.state) } catch (e) { return ({}) }
    }
    readonly property var flavours: s.flavours || []
    readonly property var targets: s.targets || []
    readonly property var job: s.job || null
    readonly property bool running: job !== null && ["download", "check", "unpack", "steam"].indexOf(job.step) >= 0
    property string target: "steam"
    /// The folder waiting for "Remove?" to be answered.
    property string asking: ""
    /// Flavours with their notes open.
    property var open: ({})

    spacing: 0
    bottomPadding: 6

    function look(force) {
        ProtonGet.look(force, JSON.stringify(games.map((g) => g.name)))
    }
    Component.onCompleted: look(false)

    function usersOf(path) {
        const t = tools.find((x) => x.path === path)
        return t ? used.filter((u) => u.inUse === t.name).length : 0
    }
    // One name column for both flavours, as wide as the longest name
    // (MN, 0.8.70: proton-cachyos names were cut and looked alike).
    FontMetrics { id: nameMetrics; font.family: Theme.body; font.pixelSize: 12 }
    readonly property real nameW: {
        let w = 120
        for (const f of flavours)
            for (const i of (f.installed || []))
                w = Math.max(w, nameMetrics.advanceWidth(i.name))
        return Math.ceil(w) + 6
    }

    function mb(bytes) { return Math.round(bytes / 1048576) + " MB" }
    function ago(seconds) {
        if (!seconds) return "not yet"
        const m = Math.max(0, Math.round((Date.now() / 1000 - seconds) / 60))
        if (m < 2) return "just now"
        if (m < 60) return m + " min ago"
        const h = Math.round(m / 60)
        return h < 48 ? h + " h ago" : Math.round(h / 24) + " days ago"
    }

    // Header: what this is, when GitHub was asked, where it installs.
    Item {
        width: parent.width
        height: 34
        Row {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "GET PROTON"
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: box.s.checking ? "asking GitHub…" : "GitHub releases · looked " + box.ago(box.s.checkedAt)
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: box.targets.length > 1
                anchors.verticalCenter: parent.verticalCenter
                text: "Install for"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
            Repeater {
                model: box.targets.length > 1 ? box.targets : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: box.target === modelData.id
                    anchors.verticalCenter: parent.verticalCenter
                    width: tLabel.implicitWidth + 16
                    height: 22
                    color: "transparent"
                    border.color: on ? Theme.accent : "#3a3842"
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: tLabel
                        anchors.centerIn: parent
                        text: modelData.label.toUpperCase()
                        color: parent.on ? Theme.accent : Theme.muted()
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !box.running
                        onClicked: box.target = parent.modelData.id
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: "Install for " + modelData.label
                }
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "refresh"
                tip: "Ask GitHub again"
                color: Theme.dim()
                enabled: !box.s.checking
                onClicked: box.look(true)
            }
        }
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        visible: (box.s.error || "") !== ""
        x: 16
        width: parent.width - 32
        bottomPadding: 6
        wrapMode: Text.WordWrap
        text: (box.s.error || "") + (box.flavours.some((f) => f.latest) ? " (showing what GitHub said last time)." : ".")
        color: Theme.red
        font.family: Theme.body
        font.pixelSize: 12
    }
    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        visible: box.targets.length === 0 && box.s.flavours !== undefined
        x: 16
        width: parent.width - 32
        bottomPadding: 6
        wrapMode: Text.WordWrap
        text: "No Steam or Heroic folder found to install into."
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 12
    }

    // Steam reads its Protons only when it starts.
    Item {
        visible: box.targets.some((t) => t.id === "steam")
        x: 16
        width: parent.width - 32
        height: visible ? 26 : 0
        Rectangle {
            id: restartBox
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            color: ProtonGet.restartAfter ? Theme.accent : "transparent"
            border.color: ProtonGet.restartAfter ? Theme.accent : Theme.track
            HudIcon {
                anchors.centerIn: parent
                visible: ProtonGet.restartAfter
                name: "check"
                size: 11
                lineWidth: 2.4
                color: "#121116"
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            anchors.left: restartBox.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Restart Steam after installing, so it sees the new Proton (never while a game runs)"
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ProtonGet.setRestart(!ProtonGet.restartAfter)
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: "Restart Steam after installing"
        Accessible.checked: ProtonGet.restartAfter
    }

    Repeater {
        model: box.flavours
        delegate: Flavour {}
    }

    // One flavour: its latest release, why it may be worth it, the job,
    // the installed downloads.
    component Flavour: Column {
        id: fl
        required property var modelData
        readonly property var f: modelData
        readonly property var latest: f.latest || null
        readonly property var myJob: box.job && box.job.flavour === f.id ? box.job : null
        readonly property bool notesOpen: box.open[f.id] === true
        readonly property var pacman: f.id === "cachyos" ? (box.s.pacman || []) : []
        width: box.width
        bottomPadding: 10

        Rectangle { width: parent.width; height: 1; color: Theme.rowLine }
        // Title row
        Item {
            width: parent.width
            height: 36
            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: fl.f.title
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: fl.latest ? fl.latest.tag + " · " + fl.latest.date : (box.s.checking ? "" : "no release known yet")
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Tag {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fl.f.newer
                    text: "NEW"
                    filled: true
                }
                Tag {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fl.f.haveLatest
                    text: "UP TO DATE"
                    tint: Theme.muted()
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                TextButton {
                    visible: !!fl.latest && fl.latest.notes !== ""
                    text: fl.notesOpen ? "What's new ▴" : "What's new ▾"
                    pixelSize: 11
                    pad: 10
                    implicitHeight: 26
                    onClicked: {
                        const o = Object.assign({}, box.open)
                        o[fl.f.id] = !fl.notesOpen
                        box.open = o
                    }
                }
                TextButton {
                    visible: !!fl.latest && fl.latest.page !== ""
                    text: "Release ↗"
                    pixelSize: 11
                    pad: 10
                    implicitHeight: 26
                    onClicked: ProtonGet.openRelease(fl.latest.page)
                }
                TextButton {
                    visible: !!fl.latest && !fl.f.haveLatest && !fl.myJob && box.targets.length > 0
                    enabled: !box.running
                    opacity: enabled ? 1 : 0.4
                    text: "Install" + (fl.latest && fl.latest.size > 0 ? " · " + box.mb(fl.latest.size) : "")
                    pixelSize: 11
                    pad: 10
                    implicitHeight: 26
                    onClicked: ProtonGet.install(fl.f.id, box.targets.some((t) => t.id === box.target) ? box.target : box.targets[0].id)
                }
            }
        }
        // Do I need it?
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 32
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            visible: !!fl.latest
            text: fl.f.named.length > 0
                ? "<b>Worth it:</b> the notes" + (fl.f.since > 1 ? " since your version" : "") + " name " + fl.f.named.join(", ") + "."
                : fl.f.haveLatest ? "You have the newest."
                : fl.f.installed.length > 0 ? "None of your games is named in its notes: you only need it if a game makes trouble."
                : "Not installed. Only needed if a game runs better with it."
            color: fl.f.named.length > 0 ? Theme.accent : Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 32
            topPadding: 3
            wrapMode: Text.WordWrap
            text: fl.f.about
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
        // The release notes
        Rectangle {
            visible: fl.notesOpen && !!fl.latest
            x: 16
            width: parent.width - 32
            height: visible ? notes.implicitHeight + 16 : 0
            color: "#141318"
            border.color: "#2a2830"
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                id: notes
                x: 10
                y: 8
                width: parent.width - 20
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: fl.latest ? fl.latest.notes : ""
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 11
                lineHeight: 1.15
            }
        }
        // The job
        Item {
            visible: fl.myJob !== null
            width: parent.width
            height: visible ? 46 : 0
            readonly property var j: fl.myJob || ({})
            readonly property real share: j.step === "download" && j.total > 0 ? Math.min(1, j.done / j.total) : (["check", "unpack", "steam"].indexOf(j.step) >= 0 ? 1 : 0)
            Rectangle {
                visible: ["download", "check", "unpack", "steam"].indexOf(parent.j.step) >= 0
                x: 16
                y: 10
                width: parent.width - 32 - 90
                height: 4
                color: Theme.trackDark
                Rectangle { width: parent.width * parent.parent.share; height: parent.height; color: Theme.accent }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                x: 16
                y: 20
                width: parent.width - 32 - (parent.j.step === "done" && parent.j.steamRunning ? 220 : 90)
                elide: Text.ElideRight
                text: {
                    const j = parent.j
                    const where = j.target === "heroic" ? "Heroic" : "Steam"
                    if (j.step === "download") return "Downloading " + j.tag + ": " + box.mb(j.done) + (j.total > 0 ? " of " + box.mb(j.total) + " · " + Math.round(parent.share * 100) + " %" : "")
                    if (j.step === "check") return "Checking the checksum…"
                    if (j.step === "unpack") return "Unpacking for " + where + "…"
                    if (j.step === "steam") return "Installed " + j.name + ". Restarting Steam…"
                    if (j.step === "done") return "Installed " + j.name + " for " + where + "."
                        + (j.steam === "restarted" ? " Steam was restarted and sees it." : j.steam ? " Steam not restarted: " + j.steam + "." : j.steamRunning ? " Restart Steam so it sees it." : "")
                        + " Pick it per game below."
                    if (j.step === "stopped") return "Cancelled. Nothing was left behind."
                    if (j.step === "failed") return "Not installed: " + j.error + "."
                    return ""
                }
                color: parent.j.step === "failed" ? Theme.red : parent.j.step === "done" ? Theme.accent : Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
            }
            TextButton {
                id: okButton
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.j.step !== "steam"
                text: box.running ? "Cancel" : "OK"
                danger: box.running
                pixelSize: 11
                pad: 10
                implicitHeight: 26
                onClicked: box.running ? ProtonGet.cancel() : ProtonGet.dismiss()
            }
            TextButton {
                anchors.right: okButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.j.step === "done" && parent.j.steamRunning === true
                text: "Restart Steam"
                pixelSize: 11
                pad: 10
                implicitHeight: 26
                onClicked: ProtonGet.restartSteam()
            }
        }
        // pacman's proton-cachyos
        Repeater {
            model: fl.pacman
            delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow
                required property var modelData
                x: 16
                width: fl.width - 32
                topPadding: 6
                wrapMode: Text.WordWrap
                text: modelData.newer
                    ? "Package " + modelData.pkg + " (pacman) " + modelData.have + ": the package list has " + modelData.repo + ". It comes with your system update."
                    : "Package " + modelData.pkg + " (pacman) " + modelData.have + ": current as far as the package list on disk knows."
                color: modelData.newer ? Theme.accent : Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        // Installed downloads, newest first, under STEAM / HEROIC when
        // both hold some.
        Repeater {
            id: instList
            model: fl.f.installed
            readonly property bool both: {
                const l = fl.f.installed || []
                return l.some((i) => i.target !== (l[0] || {}).target)
            }
            delegate: Item {
                id: inst
                required property var modelData
                required property int index
                readonly property int users: box.usersOf(modelData.path)
                readonly property bool asked: box.asking === modelData.path
                readonly property bool head: instList.both
                    && (index === 0 || fl.f.installed[index - 1].target !== modelData.target)
                readonly property real nameCol: Math.max(120, Math.min(box.nameW, fl.width - 34 - 20 - 420))
                width: fl.width
                readonly property bool notesOpen: box.open[modelData.path] === true
                height: line.y + line.height + (notesOpen ? rowNotes.height + 6 : 0)
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: inst.head
                    x: 16
                    y: 8
                    text: inst.modelData.target === "heroic" ? "HEROIC" : "STEAM"
                    color: Theme.muted()
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                Item {
                    id: line
                    y: inst.head ? 26 : 0
                    width: parent.width
                    height: Math.max(30, nameText.implicitHeight + 12)
                    Rectangle {
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        color: inst.users > 0 ? Theme.accent : "#5a5764"
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: nameText
                        x: 34
                        width: inst.nameCol
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WrapAnywhere
                        text: inst.modelData.name
                        color: inst.users > 0 ? Theme.text() : Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        x: 34 + inst.nameCol + 20
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - removeRow.width - 28
                        wrapMode: Text.Wrap
                        text: (instList.both ? "" : (inst.modelData.target === "heroic" ? "Heroic · " : "Steam · "))
                            + (inst.asked ? (inst.users > 0 ? "Remove it? " + inst.users + (inst.users === 1 ? " game uses" : " games use") + " it and would need another Proton." : "Remove it?")
                                : (inst.users > 0 ? "used by " + inst.users + (inst.users === 1 ? " game" : " games") : "not used")
                                    + (inst.modelData.latest ? " · newest release" : ""))
                        color: inst.asked && inst.users > 0 ? Theme.red
                            : inst.modelData.latest && !inst.asked ? Theme.accent : Theme.dim()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                    Row {
                        id: removeRow
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        TextButton {
                            visible: !inst.asked && inst.modelData.notes !== ""
                            text: inst.notesOpen ? "Notes ▴" : "Notes ▾"
                            pixelSize: 10
                            pad: 8
                            implicitHeight: 22
                            onClicked: {
                                const o = Object.assign({}, box.open)
                                o[inst.modelData.path] = !inst.notesOpen
                                box.open = o
                            }
                        }
                        TextButton {
                            visible: !inst.asked && inst.modelData.page !== ""
                            text: "Release ↗"
                            pixelSize: 10
                            pad: 8
                            implicitHeight: 22
                            onClicked: ProtonGet.openRelease(inst.modelData.page)
                        }
                        TextButton {
                            visible: inst.asked
                            text: "Keep"
                            pixelSize: 10
                            pad: 8
                            implicitHeight: 22
                            onClicked: box.asking = ""
                        }
                        TextButton {
                            enabled: !box.running && !box.s.checking
                            opacity: enabled ? 1 : 0.4
                            text: "Remove"
                            danger: true
                            pixelSize: 10
                            pad: 8
                            implicitHeight: 22
                            onClicked: {
                                if (!inst.asked) { box.asking = inst.modelData.path; return }
                                box.asking = ""
                                ProtonGet.remove(inst.modelData.path)
                            }
                        }
                    }
                }
                // This version's own release notes
                Rectangle {
                    id: rowNotes
                    visible: inst.notesOpen
                    x: 34
                    y: line.y + line.height
                    width: parent.width - 34 - 16
                    height: rowNotesText.implicitHeight + 16
                    color: "#141318"
                    border.color: "#2a2830"
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: rowNotesText
                        x: 10
                        y: 8
                        width: parent.width - 20
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: (inst.modelData.tag ? inst.modelData.tag + " · " + inst.modelData.date + "\n\n" : "") + inst.modelData.notes
                        color: Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 11
                        lineHeight: 1.15
                    }
                }
            }
        }
    }
}
