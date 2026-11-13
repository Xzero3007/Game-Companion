import QtQuick
import GameCompanion
import "theme.js" as Theme
import "launch.js" as Launch

// The LAUNCH tab of a game's form (design L1Options): the launcher's own
// launch options in Steam's form, read as chips with each part's check
// (Games.checkOptions), the Proton build, and the way to the suggestions.
// Nothing is written here: the form's SAVE calls `save`.
Column {
    id: tab
    required property var game
    /// The ChoiceList for the Proton choice.
    property var choices: null
    /// An own entry's command as the GENERAL tab has it now.
    property string ownText: ""
    readonly property bool own: game.own === true
    signal ownTextEdited(string text)
    signal showSuggestions()

    /// Games.launchOptions's answer (null while it loads).
    property var info: null
    property string savedText: ""
    property var check: null
    property bool checking: false
    property int checkRequest: -1
    /// Games.suggestions's answer.
    property var suggest: null
    property var tools: []
    property string steamDefault: ""
    /// The Proton or Wine build picked here (a protonVersions name).
    property string protonPick: ""
    /// The text of the chip whose explanation is open ("" = none).
    property string openChip: ""
    /// Screenshots: open the first flagged part once checked.
    property bool demoDetail: false
    /// Screenshots: open the Proton list once the versions are read.
    property bool demoPicker: false

    readonly property string text: field.text
    readonly property bool supported: info !== null && info.supported === true
    readonly property bool running: info !== null && info.running === true
    readonly property bool canSetProton: supported && info.proton.canSet === true
    readonly property bool textDirty: supported && !own && field.text.trim() !== savedText.trim()
    readonly property bool protonDirty: canSetProton && protonPick !== (info.proton.name || "")
    readonly property bool dirty: textDirty || protonDirty
    readonly property var chips: Launch.chips(field.text, check, own)
    readonly property var openToken: {
        for (const c of chips) if (c.text === openChip && c.token) return c
        return null
    }
    readonly property string fileName: supported && info.file ? info.file.split("/").pop() : ""
    readonly property var protonChoices: canSetProton ? Launch.choicesFor(tools, info.launcher, steamDefault) : []

    function setText(t) {
        field.text = t
        checkTimer.restart()
    }

    spacing: 12

    Requests { id: req }

    Component.onCompleted: {
        req.ask(Games.launchOptions(game.id), (a) => {
            if (!a) return
            tab.info = a
            tab.savedText = a.text || ""
            field.text = tab.own && tab.ownText.length > 0 ? tab.ownText : (a.text || "")
            tab.protonPick = a.proton ? (a.proton.name || "") : ""
            tab.steamDefault = a.proton ? (a.proton.global || "") : ""
            tab.runCheck()
        })
        req.ask(Games.protonVersions(false), (a) => {
            tab.tools = a || []
            if (tab.demoPicker) demoPickerTimer.start()
        })
        req.ask(Games.suggestions(game.id), (a) => tab.suggest = a)
    }
    onVisibleChanged: if (visible && own && supported && ownText !== field.text) setText(ownText)

    function runCheck() {
        if (field.text.trim().length === 0) {
            check = null
            checking = false
            return
        }
        checking = true
        const asked = field.text
        const r = Games.checkOptions(game.id, asked)
        checkRequest = r
        req.ask(r, (a) => {
            if (r !== tab.checkRequest) return
            tab.checking = false
            if (a && field.text === asked) tab.check = a
            if (tab.demoDetail && tab.check) {
                tab.demoDetail = false
                const flagged = tab.chips.find((c) => c.token && c.status !== "ok")
                if (flagged) tab.openChip = flagged.text
            }
        })
    }
    Timer {
        id: demoPickerTimer
        interval: 500
        onTriggered: if (tab.choices) tab.choices.show(protonSelect, protonSelect.options, protonSelect.current, (id) => tab.protonPick = id)
    }
    Timer { id: checkTimer; interval: 400; onTriggered: tab.runCheck() }

    // While the launcher runs, look again every 3 s (only then).
    Timer {
        interval: 3000
        repeat: true
        running: tab.running && tab.visible
        onTriggered: req.ask(Games.launcherState(tab.game.id), (a) => {
            if (!a || !tab.info) return
            const i = Object.assign({}, tab.info)
            i.running = a.running === true
            tab.info = i
        })
    }

    // Loading, or a game whose options cannot be set here.
    Text { style: Theme.textStyle(); styleColor: Theme.shadow
        visible: !tab.supported
        width: parent.width
        topPadding: 8
        bottomPadding: 8
        wrapMode: Text.WordWrap
        text: tab.info === null ? "Reading " + Launch.launcherName(tab.game.launcher) + "'s settings…"
            : (tab.info.error || "This game has no launch options to set here.")
        color: tab.info === null ? Theme.dim() : Theme.textSoft()
        font.family: Theme.body
        font.pixelSize: 13
    }

    // The launcher runs: it would undo the change when it quits.
    Rectangle {
        visible: tab.supported && tab.running
        width: parent.width
        height: bannerColumn.implicitHeight + 20
        color: Qt.rgba(214 / 255, 69 / 255, 61 / 255, 0.14)
        Rectangle { width: parent.width; height: 2; color: Theme.red }
        HudIcon {
            x: 12
            y: 11
            name: "warning"
            size: 16
            lineWidth: 2
            color: Launch.red
        }
        Column {
            id: bannerColumn
            x: 38
            y: 10
            width: parent.width - 50
            spacing: 2
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "CLOSE " + Launch.launcherName(tab.info ? tab.info.launcher : "").toUpperCase() + " FIRST"
                color: Launch.red
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width
                wrapMode: Text.WordWrap
                readonly property string name: Launch.launcherName(tab.info ? tab.info.launcher : "")
                text: name + " is running and writes its settings file when it quits, which would undo this change. Close " + name + ", then save."
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
                lineHeight: 1.15
            }
        }
    }

    // The options as text.
    Column {
        visible: tab.supported
        width: parent.width
        spacing: 6
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            text: tab.own ? "COMMAND" : "LAUNCH OPTIONS"
            color: Theme.muted()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Rectangle {
            width: parent.width
            height: Math.max(60, field.contentHeight + 18)
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.accent }
            TextEdit {
                id: field
                x: 10
                y: 9
                width: parent.width - 20
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                color: Theme.text()
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Launch.mono
                font.pixelSize: 13
                selectByMouse: true
                // One line: Enter does nothing, pasted line breaks become spaces.
                Keys.onReturnPressed: (event) => event.accepted = true
                Keys.onEnterPressed: (event) => event.accepted = true
                onTextChanged: {
                    if (text.indexOf("\n") >= 0) {
                        text = text.replace(/\s*\n\s*/g, " ")
                        cursorPosition = text.length
                    }
                    if (activeFocus) {
                        checkTimer.restart()
                        if (tab.own) tab.ownTextEdited(text)
                    }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: field.text.length === 0
                    text: tab.own ? "e.g. umu-run ~/Games/game.exe" : "e.g. gamemoderun %command%"
                    color: Theme.dim()
                    font: field.font
                }
                Accessible.name: tab.own ? "Command" : "Launch options"
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            width: parent.width
            wrapMode: Text.WordWrap
            text: !tab.info ? "" : tab.own ? "The game's command, the same as \"Start with\" in GENERAL."
                : tab.info.launcher === "steam" ? "The same text as in Steam's Properties → Launch Options. Edit it here or pick suggestions below."
                : "In Steam's form: " + Launch.launcherName(tab.info.launcher) + " keeps the variables, the programs before the game and its arguments apart; SAVE puts them back there."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    // The parts as the checker read them.
    Column {
        visible: tab.supported && field.text.trim().length > 0
        width: parent.width
        spacing: 8
        Row {
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "READ AS"
                color: Theme.muted()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: tab.checking
                text: "checking…"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: !tab.checking && tab.check !== null && !!tab.check.proton && tab.check.proton.label.length > 0
                text: tab.check && tab.check.proton ? "for " + tab.check.proton.label : ""
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Flow {
            width: parent.width
            spacing: 6
            opacity: tab.checking ? 0.6 : 1
            Repeater {
                model: tab.chips
                delegate: Chip {}
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            visible: tab.check !== null && tab.check.error.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: tab.check ? tab.check.error : ""
            color: Launch.red
            font.family: Theme.body
            font.pixelSize: 12
        }
        Repeater {
            model: tab.check ? tab.check.problems : []
            delegate: Row {
                required property var modelData
                width: parent.width
                spacing: 8
                HudIcon { name: "warning"; size: 13; lineWidth: 2; color: Launch.red; y: 1 }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    width: parent.width - 21
                    wrapMode: Text.WordWrap
                    text: modelData.message
                    color: Launch.red
                    font.family: Theme.body
                    font.pixelSize: 12
                }
            }
        }

        // One part's explanation, opened by a click on its chip.
        Rectangle {
            visible: tab.openToken !== null
            width: parent.width
            height: visible ? detail.implicitHeight + 20 : 0
            color: "#15151a"
            readonly property var c: tab.openToken
            readonly property var t: c ? c.token : null
            readonly property var look: Launch.status(c ? c.status : "ok")
            Rectangle { width: 2; height: parent.height; color: parent.look.color }
            Column {
                id: detail
                x: 14
                y: 10
                width: parent.width - 28
                spacing: 4
                Item {
                    width: parent.width
                    height: Math.max(fixButton.visible ? 30 : 0, statusRow.implicitHeight)
                    Row {
                        id: statusRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: fixButton.visible ? fixButton.left : parent.right
                        anchors.rightMargin: 10
                        spacing: 8
                        StatusMark { status: tab.openToken ? tab.openToken.status : "ok"; anchors.verticalCenter: parent.verticalCenter }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.verticalCenter: parent.verticalCenter
                            text: Launch.status(tab.openToken ? tab.openToken.status : "ok").label
                            color: Launch.status(tab.openToken ? tab.openToken.status : "ok").color
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, statusRow.width - 140)
                            elide: Text.ElideRight
                            text: tab.openToken && tab.openToken.token ? tab.openToken.token.name : ""
                            color: Theme.text()
                            font.family: Launch.mono
                            font.pixelSize: 12
                        }
                    }
                    TextButton {
                        id: fixButton
                        readonly property var fix: tab.openToken && tab.openToken.token ? tab.openToken.token.fix : null
                        visible: fix !== null && fix !== undefined
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        text: fix === "" ? "Take it out" : "Fix: " + (fix && fix.length > 34 ? fix.slice(0, 33) + "…" : fix)
                        onClicked: {
                            const next = Launch.applyFix(field.text, tab.openToken)
                            tab.openChip = ""
                            tab.setText(next)
                        }
                    }
                }
                Info { text: tab.openToken && tab.openToken.token ? tab.openToken.token.explanation : ""; color: Theme.textSoft(); size: 12 }
                Info { text: tab.openToken && tab.openToken.token ? tab.openToken.token.note : "" }
                Info {
                    text: tab.openToken && tab.openToken.token && tab.openToken.token.replacement.length > 0 && tab.openToken.token.fix === null
                        ? "Use instead: " + tab.openToken.token.replacement : ""
                    color: Theme.accentLight
                }
                Info { text: tab.openToken && tab.openToken.token ? tab.openToken.token.warning : ""; color: Launch.red }
                Repeater {
                    model: tab.openToken && tab.openToken.token ? tab.openToken.token.flags : []
                    delegate: Row {
                        required property var modelData
                        width: detail.width
                        spacing: 8
                        topPadding: 4
                        StatusMark { status: modelData.status; y: 9 }
                        Column {
                            width: parent.width - 15
                            spacing: 1
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                text: modelData.flag + "  ·  " + Launch.status(modelData.status).label
                                color: Theme.text()
                                font.family: Launch.mono
                                font.pixelSize: 12
                            }
                            Info { width: parent.width; text: modelData.note }
                            Info { width: parent.width; text: modelData.suggestion.length > 0 ? "Instead: " + modelData.suggestion : ""; color: Theme.accentLight }
                        }
                    }
                }
            }
        }

        // What the marks say, and a fix for all at once.
        Item {
            visible: tab.check !== null && tab.chips.length > 0
            width: parent.width
            height: Math.max(legend.implicitHeight, fixAll.visible ? 30 : 0)
            Flow {
                id: legend
                anchors.left: parent.left
                anchors.right: fixAll.visible ? fixAll.left : parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Repeater {
                    model: Launch.order.filter((s) => tab.check && tab.check.summary && tab.check.summary[s] > 0)
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        StatusMark { status: modelData; anchors.verticalCenter: parent.verticalCenter }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            text: tab.check.summary[modelData] + " " + Launch.status(modelData).label
                            color: Theme.muted()
                            font.family: Theme.display
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }
                    }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: tab.chips.some((c) => c.token !== null)
                    text: tab.openChip.length > 0 ? "Click the part again to close." : "Click a part to see what it does."
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            TextButton {
                id: fixAll
                visible: tab.check !== null && tab.check.fixed.length > 0 && tab.check.fixed !== field.text
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                text: "Fix all"
                onClicked: { tab.openChip = ""; tab.setText(tab.check.fixed) }
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            width: parent.width
            wrapMode: Text.WordWrap
            text: tab.own ? "Order matters: variables first, then wrappers, then the game's program and its arguments."
                : "Order matters: variables first, then wrappers, then %command% (the game), then the game's own arguments."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    // Suggestions for this PC (opens LaunchSuggestions).
    Rectangle {
        visible: tab.supported
        width: parent.width
        height: 58
        color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.06)
        border.color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.35)
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: showButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "SUGGESTIONS FOR THIS PC"
                color: Theme.accentLight
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                width: parent.width
                elide: Text.ElideRight
                text: {
                    const s = tab.suggest
                    if (!s) return "Looking at this PC…"
                    const list = (s.suggestions || []).filter((x) => x.available !== false)
                    if (list.length === 0) return "Nothing to suggest for this game here."
                    const rec = list.filter((x) => x.recommended && !x.applied).length
                    const applied = list.filter((x) => x.applied).length
                    let line = list.length + (list.length === 1 ? " option fits" : " options fit") + " this PC"
                    if (rec > 0) line += ", " + rec + " recommended"
                    line += applied > 0 ? ", " + applied + " already set." : "."
                    if (s.others) line += " Others' choices from " + s.others.reports + " reports."
                    return line
                }
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
            }
        }
        TextButton {
            id: showButton
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            enabled: tab.suggest !== null
            opacity: enabled ? 1 : 0.5
            text: "Show"
            onClicked: tab.showSuggestions()
        }
    }

    // The Proton or Wine build.
    Column {
        visible: tab.supported
        width: parent.width
        spacing: 6
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Item { width: 1; height: 6 }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            text: tab.info && (tab.info.launcher === "lutris" || (tab.info.proton && tab.info.proton.name.indexOf("Wine") === 0)) ? "PROTON / WINE" : "PROTON"
            color: Theme.muted()
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Item {
            visible: tab.canSetProton
            width: parent.width
            height: 36
            SelectBox {
                id: protonSelect
                anchors.left: parent.left
                anchors.right: currentTag.visible ? currentTag.left : parent.right
                anchors.rightMargin: currentTag.visible ? 10 : 0
                height: 36
                choices: tab.choices
                options: tab.protonChoices
                current: tab.protonPick
                changed: tab.protonDirty
                placeholder: tab.tools.length === 0 ? "Reading the installed versions…" : "Not installed: " + tab.protonPick
                accessibleName: "Proton version"
                onChosen: (id) => tab.protonPick = id
            }
            Tag {
                id: currentTag
                visible: !tab.protonDirty
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "CURRENT"
                size: 11
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
                if (!tab.info) return ""
                if (!tab.canSetProton)
                    return tab.own ? "Part of the command (e.g. umu-run or a Proton folder)." : "This game does not run through Wine here; set its runner in " + Launch.launcherName(tab.info.launcher) + "."
                const nameOf = (id) => { for (const o of tab.protonChoices) if (o.id === id) return o.name; return id }
                const fits = tab.tools.filter((t) => t.launchers.indexOf(tab.info.launcher) >= 0)
                const where = []
                for (const t of fits) {
                    const w = t.source === "steam" ? "Steam" : t.source === "custom" ? "compatibilitytools.d" : t.source === "system" ? "the system's compatibilitytools.d" : t.source === "heroic" ? "Heroic's tools" : "Lutris's runners"
                    if (where.indexOf(w) < 0) where.push(w)
                }
                let line = tab.protonDirty ? "Was: " + nameOf(tab.info.proton.name || "") + ". " : ""
                if (where.length > 0) line += "Found in " + where.join(", ") + "."
                return line
            }
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    component Info: Text {
        property real size: 11
        style: Theme.textStyle(); styleColor: Theme.shadow
        visible: text.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: size
        lineHeight: 1.1
    }

    // One part: its kind, its text, its check's mark.
    component Chip: Rectangle {
        id: chip
        required property var modelData
        readonly property var c: modelData
        readonly property bool game: c.kind === "command"
        readonly property bool open: tab.openChip === c.text && c.token !== null
        readonly property var look: Launch.status(c.status)
        readonly property bool flagged: c.status !== "ok"
        width: Math.min(chipRow.implicitWidth, parent.width)
        height: 28
        color: open ? "#24232b" : chipMouse.containsMouse && c.token ? "#202027" : "#1b1a20"
        border.color: open ? look.color : flagged ? look.color : game ? Theme.accent : "#3a3842"
        Row {
            id: chipRow
            height: parent.height
            Rectangle {
                height: parent.height
                width: kindText.implicitWidth + 14
                color: chip.c.kind === "env" ? Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.4)
                    : chip.game ? Theme.accent : chip.c.kind === "wrapper" ? "#34323c" : "#24232b"
                Text {
                    id: kindText
                    anchors.centerIn: parent
                    text: chip.c.label
                    color: chip.c.kind === "env" ? "#e6dbfa" : chip.game ? "#121116" : chip.c.kind === "wrapper" ? Theme.text() : Theme.textSoft()
                    style: chip.game ? Text.Normal : Theme.textStyle()
                    styleColor: Theme.shadow
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                id: chipText
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 9
                rightPadding: chip.game ? 9 : 6
                width: Math.min(implicitWidth, chip.parent.width - kindText.implicitWidth - 30)
                elide: Text.ElideRight
                text: chip.c.text
                color: chip.game ? Theme.accentLight : chip.c.kind === "arg" ? Theme.textSoft() : Theme.text()
                font.family: Launch.mono
                font.pixelSize: 12
            }
            Item {
                visible: !chip.game
                width: 15
                height: parent.height
                StatusMark { status: chip.c.status; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            enabled: chip.c.token !== null
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.openChip = chip.open ? "" : chip.c.text
        }
        Accessible.role: Accessible.Button
        Accessible.name: c.label + " " + c.text + ", " + look.label
    }
}
