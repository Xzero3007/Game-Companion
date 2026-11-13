import QtQuick
import GameCompanion
import "theme.js" as Theme
import "launch.js" as Launch

// Suggestions for this PC (design L2Suggestions): what fits this computer
// and the game's Proton build, one per group, a preview of the combined
// options (new parts in gold) and what others use (ProtonDB's export).
// APPLY hands the preview to the form's launch options; SAVE there writes.
Column {
    id: view
    required property var game
    /// The form's launch options now, and as the launcher keeps them.
    property string fieldText: ""
    property string savedText: ""
    /// Height the user added to the panel (the list takes it).
    /// Screenshots: scroll the list to a share of its length once loaded.
    property real demoScroll: -1
    /// Height the whole view may take on the screen.
    property real room: 700
    signal applied(string text)
    signal canceled()

    property var suggest: null
    property var sys: null
    /// id → true for the suggestions to have on.
    property var chosen: ({})
    property var preview: null
    property int previewRequest: -1
    property bool previewing: false

    readonly property var list: suggest ? suggest.suggestions : []
    readonly property var singles: list.filter((s) => s.group.length === 0)
    readonly property var groups: {
        const names = []
        for (const s of list) if (s.group.length > 0 && names.indexOf(s.group) < 0) names.push(s.group)
        return names
    }
    readonly property bool edited: fieldText.trim() !== savedText.trim()
    /// What the suggestions start from: the field as it is now (its unsaved
    /// edits stay), or the saved options when the field is empty.
    readonly property string base: fieldText.trim().length > 0 ? fieldText : savedText

    spacing: 0

    Requests { id: req }
    Timer {
        id: demoTimer
        interval: 600
        onTriggered: listFlick.contentY = Math.max(0, (listFlick.contentHeight - listFlick.height) * view.demoScroll)
    }

    Component.onCompleted: {
        req.ask(Games.suggestions(game.id, view.base), (a) => {
            if (!a) return
            view.suggest = a
            // Applied ones stay on; recommended ones start on unless their
            // group has another one set already.
            const on = {}
            for (const s of a.suggestions) if (s.applied) on[s.id] = true
            for (const s of a.suggestions) {
                if (!s.recommended || s.applied || !view.usable(s)) continue
                if (s.group.length > 0 && a.suggestions.some((o) => o.group === s.group && on[o.id])) continue
                on[s.id] = true
            }
            view.chosen = on
            view.combine()
            if (view.demoScroll >= 0) demoTimer.start()
        })
        req.ask(Games.systemInfo(), (a) => view.sys = a)
    }

    /// A suggestion that does something with the game's build (a missing
    /// `available` counts as yes); why not, when it does nothing.
    function usable(s) { return s.available !== false }
    function whyNot(s) { return s.unavailable_why || s.unavailableWhy || "It does nothing with this game's Proton build." }

    function toggle(s) {
        // One that does nothing here can still be taken out (or kept) when
        // the options have it already.
        if (!usable(s) && !s.applied) return
        const on = Object.assign({}, chosen)
        if (on[s.id]) delete on[s.id]
        else {
            if (s.group.length > 0) for (const o of list) if (o.group === s.group) delete on[o.id]
            on[s.id] = true
        }
        chosen = on
        combine()
    }
    function groupOff(group) {
        const on = Object.assign({}, chosen)
        for (const o of list) if (o.group === group) delete on[o.id]
        chosen = on
        combine()
    }
    function combine() {
        req.forget(previewRequest)
        previewing = true
        const ids = Object.keys(chosen).filter((k) => chosen[k])
        const r = Games.combineOptions(game.id, JSON.stringify(ids), view.base)
        previewRequest = r
        req.ask(r, (a) => {
            if (r !== view.previewRequest) return
            view.previewing = false
            view.preview = a
        })
    }

    // Header
    Item {
        id: headerItem
        width: parent.width
        height: 34
        Row {
            anchors.left: parent.left
            anchors.right: headerTag.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                text: "SUGGESTIONS FOR THIS PC"
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 16
                font.weight: Font.Bold
                font.letterSpacing: 2
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 260)
                elide: Text.ElideRight
                text: view.game.name || ""
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
        Tag {
            id: headerTag
            anchors.right: closeButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: Launch.launcherName(view.game.launcher).toUpperCase()
            tint: "#5a5764"
            size: 11
        }
        IconButton {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            tip: "Back to the game"
            color: Theme.dim()
            onClicked: view.canceled()
        }
    }
    Item { width: 1; height: 8 }

    // This computer.
    Rectangle {
        id: sysBox
        width: parent.width
        height: sysColumn.implicitHeight + 20
        color: "#15151a"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Column {
            id: sysColumn
            x: 12
            y: 10
            width: parent.width - 24
            spacing: 8
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "SYSTEM"
                color: Theme.muted()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: view.sys === null
                text: "Reading this PC…"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 12
            }
            Grid {
                id: sysGrid
                visible: view.sys !== null
                width: parent.width
                columns: 4
                columnSpacing: 16
                rowSpacing: 8
                readonly property real cell: (width - 3 * columnSpacing) / 4
                Repeater {
                    model: {
                        const s = view.sys
                        if (!s) return []
                        const vendor = (v) => v === "nvidia" ? "NVIDIA" : v === "amd" ? "AMD" : v === "intel" ? "Intel" : v
                        const gpu = s.gpus.map((g) => vendor(g.vendor) + (g.vendor === "nvidia" && s.nvidiaVersion ? " · driver " + s.nvidiaVersion : " · " + g.driver)).join(", ")
                        const d = s.display
                        const ctx = view.suggest ? view.suggest.context : null
                        return [
                            ["GPU", gpu || "Unknown"],
                            ["CPU", s.cpu || "Unknown"],
                            ["RAM", s.ramMb > 0 ? Math.round(s.ramMb / 1024) + " GB" : "Unknown"],
                            ["SESSION", [s.desktop, s.session === "wayland" ? "Wayland" : s.session === "x11" ? "X11" : s.session].filter((x) => x).join(" · ") || "Unknown"],
                            ["DISPLAY", d ? d.width + " × " + d.height + (d.refresh > 0 ? " · " + d.refresh + " Hz" : "") : "Unknown"],
                            ["HDR", d ? (d.hdr ? "On" : "Off") : "Unknown"],
                            ["NTSYNC", (s.ntsync ? "Yes" : "No") + (s.kernel ? " · kernel " + s.kernel : "")],
                            ["PROTON", ctx && ctx.label ? ctx.label : "Unknown"]
                        ]
                    }
                    delegate: Column {
                        required property var modelData
                        width: sysGrid.cell
                        spacing: 1
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            text: modelData[0]
                            color: Theme.dim()
                            font.family: Theme.display
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                        }
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData[1]
                            color: Theme.text()
                            font.family: Theme.body
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                }
            }
            Flow {
                visible: view.sys !== null
                width: parent.width
                spacing: 6
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: 4
                    text: "TOOLS FOUND"
                    color: Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                Repeater {
                    model: view.sys ? view.sys.tools : []
                    delegate: Rectangle {
                        required property var modelData
                        width: toolRow.implicitWidth + 16
                        height: 22
                        color: "transparent"
                        border.color: "#3a3842"
                        Row {
                            id: toolRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                                text: modelData
                                color: Theme.text()
                                font.family: Launch.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: view.sys !== null && view.sys.tools.length === 0
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: "None of GameMode, MangoHud, gamescope"
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
        }
    }

    // Things to know first.
    Column {
        id: warningsColumn
        width: parent.width
    Repeater {
        model: view.suggest ? view.suggest.warnings : []
        delegate: Rectangle {
            required property var modelData
            width: view.width
            height: warnText.implicitHeight + 14
            color: Qt.rgba(214 / 255, 69 / 255, 61 / 255, 0.12)
            HudIcon { x: 12; y: 8; name: "warning"; size: 14; lineWidth: 2; color: Launch.red }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                id: warnText
                x: 34
                y: 7
                width: parent.width - 46
                wrapMode: Text.WordWrap
                text: modelData
                color: Theme.textSoft()
                font.family: Theme.body
                font.pixelSize: 12
            }
        }
    }
    }

    // The suggestions, the groups and what others use (scrolls).
    Item {
        width: parent.width
        readonly property real fixed: headerItem.height + 8 + sysBox.height + warningsColumn.height + previewColumn.height + footerItem.height
        height: Math.max(150, Math.min(listColumn.implicitHeight, view.room - fixed))
        clip: true
        Flickable {
            id: listFlick
            anchors.fill: parent
            contentHeight: listColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: listColumn
                width: listFlick.width
                topPadding: 4
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: view.suggest === null
                    width: parent.width
                    padding: 16
                    text: "Looking at this PC and the game's Proton…"
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: view.suggest !== null && view.list.length === 0
                    width: parent.width
                    padding: 16
                    wrapMode: Text.WordWrap
                    text: "Nothing to suggest for this game on this PC."
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 12
                }
                Repeater {
                    model: view.singles
                    delegate: SuggestionRow {}
                }
                Repeater {
                    model: view.groups
                    delegate: GroupBlock {}
                }
                Loader {
                    width: parent.width
                    active: view.suggest !== null && view.suggest.others !== null
                    visible: active
                    sourceComponent: Others { others: view.suggest.others }
                }
            }
        }
        WheelScroll { flick: listFlick; step: 90 }
        Rectangle {
            visible: listFlick.contentHeight > listFlick.height + 1
            anchors.right: parent.right
            width: 3
            height: parent.height
            color: Theme.trackDark
            Rectangle {
                width: parent.width
                height: Math.max(24, parent.height * listFlick.height / listFlick.contentHeight)
                y: (parent.height - height) * (listFlick.contentY / Math.max(1, listFlick.contentHeight - listFlick.height))
                color: Theme.track
            }
        }
    }

    // The combined options.
    Column {
        id: previewColumn
        width: parent.width
        topPadding: 12
        bottomPadding: 12
        spacing: 6
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Item { width: 1; height: 4 }
        Row {
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "PREVIEW"
                color: Theme.muted()
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                visible: view.previewing
                text: "putting it together…"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Rectangle {
            width: parent.width
            height: previewFlow.implicitHeight + 20
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.accent }
            Flow {
                id: previewFlow
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8
                opacity: view.previewing ? 0.6 : 1
                Repeater {
                    model: view.preview ? Launch.diffWords(view.base, view.preview.text) : []
                    delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        required property var modelData
                        text: modelData.text
                        color: modelData.fresh ? Theme.accentLight : Theme.textSoft()
                        font.family: Launch.mono
                        font.pixelSize: 13
                    }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    visible: !view.preview || view.preview.text.length === 0
                    text: view.preview ? "(no launch options)" : "…"
                    color: Theme.dim()
                    font.family: Launch.mono
                    font.pixelSize: 13
                }
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            width: parent.width
            wrapMode: Text.WordWrap
            text: view.preview && view.preview.error.length > 0 ? view.preview.error
                : "Gold = new. Your own parts stay where they are." + (view.edited && view.base === view.fieldText ? " Built from the options in the field, your unsaved edits included." : "")
            color: view.preview && view.preview.error.length > 0 ? Launch.red : Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
        }
    }

    // Footer
    Item {
        id: footerItem
        width: parent.width
        height: 46
        Rectangle { x: -14; width: parent.width + 28; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Row {
            anchors.left: parent.left
            anchors.right: footerButtons.left
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
                text: "Read from this PC only. APPLY puts this into the launch options; SAVE writes " + Launch.launcherName(view.game.launcher) + "'s file, a backup is kept first."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Row {
            id: footerButtons
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 10
            TextButton { text: "Cancel"; onClicked: view.canceled() }
            Rectangle {
                readonly property bool ready: view.preview !== null && !view.previewing && view.preview.error.length === 0
                width: applyText.implicitWidth + 32
                height: 34
                color: ready ? (applyMouse.containsMouse ? Theme.accentLight : Theme.accent) : "transparent"
                border.color: ready ? Theme.accent : "#3a3842"
                Text {
                    id: applyText
                    anchors.centerIn: parent
                    text: "APPLY"
                    color: parent.ready ? "#121116" : Theme.dim()
                    style: parent.ready ? Text.Normal : Theme.textStyle()
                    styleColor: Theme.shadow
                    font.family: Theme.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                MouseArea {
                    id: applyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: parent.ready
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.applied(view.preview.text)
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Apply"
            }
        }
    }

    // The option in Steam's form, as a small code box.
    component Code: Rectangle {
        property alias text: codeText.text
        property real maxWidth: 300
        width: Math.min(codeText.implicitWidth + 16, maxWidth)
        height: 22
        color: "#1b1a20"
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            id: codeText
            x: 8
            width: parent.width - 16
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: Theme.textSoft()
            font.family: Launch.mono
            font.pixelSize: 11
        }
    }

    component Small: Text {
        style: Theme.textStyle(); styleColor: Theme.shadow
        visible: text.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.muted()
        font.family: Theme.body
        font.pixelSize: 12
    }

    // How many others use it: on systems like this one, and in all.
    function usageLine(p) {
        if (!p) return ""
        const like = p.like && p.like.group !== undefined && p.like.reports < p.reports
            ? Launch.percent(p.like.share) + " of reports on " + p.like.label + ", " : ""
        return "Others: " + like + Launch.percent(p.share) + " of all " + p.reports + " reports."
    }

    // A suggestion with its checkbox.
    component SuggestionRow: Rectangle {
        id: row
        required property var modelData
        readonly property var s: modelData
        readonly property bool on: view.chosen[s.id] === true
        readonly property bool usable: view.usable(s)
        width: listColumn.width
        height: rowColumn.implicitHeight + 20
        color: on ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.05) : rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: row.usable || row.s.applied
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.toggle(row.s)
        }
        Rectangle {
            x: 16
            y: 11
            width: 18
            height: 18
            opacity: row.usable ? 1 : 0.4
            color: row.on ? Theme.accent : row.usable ? "transparent" : Theme.trackDark
            border.color: row.on ? Theme.accent : Theme.track
            HudIcon { anchors.centerIn: parent; visible: row.on; name: "check"; size: 14; lineWidth: 2.4; color: "#121116" }
        }
        Column {
            id: rowColumn
            x: 46
            y: 10
            width: parent.width - 46 - code.width - 32
            spacing: 3
            Row {
                spacing: 8
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.s.label
                    color: !row.usable ? Theme.dim() : row.on ? Theme.text() : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Tag { visible: row.s.recommended; text: "RECOMMENDED"; filled: true; anchors.verticalCenter: parent.verticalCenter }
                Tag { visible: row.s.applied; text: "APPLIED"; tint: "#5a5764"; anchors.verticalCenter: parent.verticalCenter }
                Tag { visible: !row.usable; text: "NO EFFECT HERE"; tint: Theme.dim(); anchors.verticalCenter: parent.verticalCenter }
            }
            // Short while off; all of it once on.
            Small {
                text: row.usable && row.s.why.length > 0 ? row.s.explanation + " " + row.s.why : row.s.explanation
                color: row.usable ? Theme.muted() : Theme.dim()
                maximumLineCount: row.on ? 12 : 1
                elide: Text.ElideRight
            }
            Small { text: row.usable ? "" : view.whyNot(row.s); color: Theme.textSoft(); font.pixelSize: 11 }
            Small { text: row.s.warning; color: Launch.red; font.pixelSize: 11; maximumLineCount: row.on ? 12 : 1; elide: Text.ElideRight }
            Small { visible: row.on && text.length > 0; text: view.usageLine(row.s.popular); color: Theme.dim(); font.pixelSize: 11 }
        }
        Code {
            id: code
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 10
            opacity: row.usable ? 1 : 0.5
            text: row.s.option
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: s.label
        Accessible.description: usable ? s.explanation : view.whyNot(s)
        Accessible.checked: on
    }

    // Suggestions of which one can be on (e.g. how the game is shown).
    component GroupBlock: Column {
        id: block
        required property var modelData
        readonly property string group: modelData
        readonly property var members: view.list.filter((s) => s.group === group)
        readonly property bool none: !members.some((s) => view.chosen[s.id])
        width: listColumn.width
        topPadding: 10
        bottomPadding: 10
        spacing: 2
        Row {
            x: 16
            spacing: 8
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: block.group === "display" ? "Display" : block.group === "performance" ? "Performance" : block.group.charAt(0).toUpperCase() + block.group.slice(1)
                color: Theme.text()
                font.family: Theme.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.baseline: parent.children[0].baseline
                text: "PICK ONE"
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 32
            bottomPadding: 4
            wrapMode: Text.WordWrap
            text: block.group === "display" ? "How the game's window is shown: one of these at a time."
                : block.group === "performance" ? "Programs that raise the computer's speed while the game runs: one of these at a time."
                : "One of these at a time."
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
        }
        Radio {
            label: "Off"
            on: block.none
            code: "no change"
            onPicked: view.groupOff(block.group)
        }
        Repeater {
            model: block.members
            delegate: Radio {
                required property var modelData
                label: modelData.label
                on: view.chosen[modelData.id] === true
                code: modelData.option
                recommended: modelData.recommended
                applied: modelData.applied
                why: modelData.why
                warning: modelData.warning
                popular: modelData.popular
                usable: view.usable(modelData)
                whyNot: usable ? "" : view.whyNot(modelData)
                onPicked: if (!on) view.toggle(modelData)
            }
        }
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
    }

    component Radio: Item {
        id: radio
        property string label
        property bool on: false
        property string code
        property bool recommended: false
        property bool applied: false
        property string why: ""
        property string warning: ""
        property var popular: null
        property bool usable: true
        property string whyNot: ""
        signal picked()
        width: listColumn.width
        height: Math.max(34, radioColumn.implicitHeight + 10)
        Rectangle {
            anchors.fill: parent
            color: radio.on && radio.label !== "Off" ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.05) : radioMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
        }
        MouseArea {
            id: radioMouse
            anchors.fill: parent
            enabled: radio.usable || radio.applied
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: radio.picked()
        }
        Rectangle {
            x: 17
            y: 9
            width: 16
            height: 16
            radius: 8
            opacity: radio.usable ? 1 : 0.4
            color: "transparent"
            border.color: radio.on ? Theme.accent : Theme.track
            border.width: radio.on ? 2 : 1
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.accent; visible: radio.on }
        }
        Column {
            id: radioColumn
            x: 46
            y: 8
            width: parent.width - 46 - radioCode.width - 32
            spacing: 2
            Row {
                spacing: 8
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.verticalCenter: parent.verticalCenter
                    text: radio.label
                    color: !radio.usable ? Theme.dim() : radio.on ? Theme.text() : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 13
                }
                Tag { visible: radio.recommended; text: "RECOMMENDED"; filled: true; anchors.verticalCenter: parent.verticalCenter }
                Tag { visible: radio.applied; text: "APPLIED"; tint: "#5a5764"; anchors.verticalCenter: parent.verticalCenter }
                Tag { visible: !radio.usable; text: "NO EFFECT HERE"; tint: Theme.dim(); anchors.verticalCenter: parent.verticalCenter }
            }
            Small { text: radio.whyNot; color: Theme.textSoft(); font.pixelSize: 11 }
            Small { visible: radio.on && radio.usable && text.length > 0; text: radio.why; font.pixelSize: 11 }
            Small { visible: radio.on && text.length > 0; text: radio.warning; color: Launch.red; font.pixelSize: 11 }
            Small { visible: radio.on && text.length > 0; text: view.usageLine(radio.popular); color: Theme.dim(); font.pixelSize: 11 }
        }
        Code {
            id: radioCode
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 6
            maxWidth: 360
            text: radio.code
        }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: on
    }

    // WHAT OTHERS USE: ProtonDB's reports for this game.
    component Others: Column {
        id: others
        required property var others
        width: listColumn.width
        topPadding: 12
        bottomPadding: 8
        spacing: 6
        Row {
            x: 16
            spacing: 10
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                text: "WHAT OTHERS USE"
                color: Theme.text()
                font.family: Theme.display
                font.pixelSize: 13
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                anchors.baseline: parent.children[0].baseline
                text: others.others.reports + " reports for " + others.others.title + ", last " + others.others.months + " months"
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 32
            wrapMode: Text.WordWrap
            text: others.others.groups.length > 0
                ? "Systems like this one: " + others.others.groups.map((g) => g.label + " (" + g.reports + ")").join(", ") + ". Shares below: among the first of these, then among all reports."
                : "Too few reports from systems like this one: shares among all reports."
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
        }
        Repeater {
            model: others.others.options
            delegate: Item {
                required property var modelData
                readonly property var o: modelData
                readonly property var like: o.usage && o.usage.like ? o.usage.like : null
                readonly property string status: o.check ? o.check.status : "unknown"
                readonly property string about: o.check ? [o.check.note || o.check.explanation, o.check.replacement ? "Use instead: " + o.check.replacement : ""].filter((x) => x).join(" ") : ""
                property bool open: false
                id: otherRow
                width: others.width
                height: 30 + (open && about.length > 0 ? aboutText.implicitHeight + 8 : 0)
                Rectangle { anchors.bottom: parent.bottom; x: 16; width: parent.width - 32; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                MouseArea {
                    anchors.fill: parent
                    enabled: otherRow.about.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: otherRow.open = !otherRow.open
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    id: aboutText
                    visible: otherRow.open
                    x: 34
                    y: 28
                    width: parent.width - 34 - 16
                    wrapMode: Text.WordWrap
                    text: otherRow.about
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
                StatusMark { x: 18; y: 11; status: parent.status }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    x: 34
                    width: parent.width - 34 - 430
                    y: 15 - height / 2
                    elide: Text.ElideRight
                    text: parent.o.text
                    color: Theme.text()
                    font.family: Launch.mono
                    font.pixelSize: 12
                }
                // Share among systems like this one, as a bar.
                Rectangle {
                    id: bar
                    x: parent.width - 410
                    y: 15 - height / 2
                    width: 60
                    height: 4
                    color: Theme.trackDark
                    Rectangle { width: parent.width * Math.min(1, parent.parent.like ? parent.parent.like.share : parent.parent.o.usage.share); height: parent.height; color: Theme.accent }
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.left: bar.right
                    anchors.leftMargin: 8
                    y: 15 - height / 2
                    width: 150
                    elide: Text.ElideRight
                    text: parent.like ? Launch.percent(parent.like.share) + " " + parent.like.label : Launch.percent(parent.o.usage.share) + " of all"
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    x: parent.width - 184
                    y: 15 - height / 2
                    width: 60
                    text: parent.like ? Launch.percent(parent.o.usage.share) + " all" : ""
                    color: Theme.dim()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    y: 15 - height / 2
                    text: Launch.status(parent.status).label
                    color: Launch.status(parent.status).color
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }
            }
        }
        Flow {
            x: 16
            width: parent.width - 32
            spacing: 6
            topPadding: 4
            Text { style: Theme.textStyle(); styleColor: Theme.shadow
                height: 22
                verticalAlignment: Text.AlignVCenter
                rightPadding: 4
                text: "PROTON USED"
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Repeater {
                model: others.others.proton
                delegate: Rectangle {
                    required property var modelData
                    width: variantText.implicitWidth + 14
                    height: 22
                    color: "#1b1a20"
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow
                        id: variantText
                        anchors.centerIn: parent
                        text: modelData.label + "  " + Launch.percent(modelData.share)
                        color: Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 11
                    }
                }
            }
        }
        Text { style: Theme.textStyle(); styleColor: Theme.shadow
            x: 16
            width: parent.width - 32
            topPadding: 2
            wrapMode: Text.WordWrap
            text: "Data: ProtonDB export (ODbL), " + others.others.export + ". Others' choices never make a suggestion recommended."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 10
        }
    }
}
