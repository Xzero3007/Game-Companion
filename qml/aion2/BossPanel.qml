import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "bossnotes.js" as BN

// The AION 2 module's Boss window (Boss Notes and Boss Callouts in one;
// canvas page "Boss (Kampf)", boards K1 to K5): NOW (the fight), SHEETS
// (a boss's calls from the game and your phases and alerts), FIGHTS (the
// recorded boss fights, + Phase / + Alert from a moment) and VOICE (how
// calls sound and look). The rules live in BossBrain.
Panel {
    id: panel
    panelId: "boss"
    title: "Boss"
    tag: width < 480 ? "" : "AION 2"
    width: 660
    minWidth: 520
    maxWidth: 1100
    stretchy: true
    minGrow: -200

    property var brain: null
    readonly property var p: brain ? brain.prefs : ({})
    property string tab: "now"
    /// The boss open in SHEETS.
    property string bossKey: "thamon"
    /// The entry being edited (its id), "" none.
    property string editing: ""
    /// The fight open in FIGHTS.
    property string fightId: ""
    property string search: ""
    property string note: ""

    readonly property var st: brain ? brain.noteState : ({ fight: null })
    readonly property var sheet: brain ? (brain.sheetsRevision, brain.sheet(bossKey)) : null
    readonly property string sheetDungeon: {
        if (!brain) return ""
        for (const id in brain.dungeons) if (brain.dungeons[id].bosses.some((b) => b.key === bossKey)) return id
        return ""
    }

    Component.onCompleted: {
        const d = nativeWindow.demo.split(",")
        for (const t of ["sheets", "fights", "voice"]) if (d.indexOf(t) >= 0) tab = t
        if (d.indexOf("ludra") >= 0 || d.indexOf("preview") >= 0) bossKey = "eternal-ludra"
    }

    // ---- small parts ----
    component Caps: Text {
        color: Theme.text()
        font.family: Theme.display
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Line: Text {
        color: Theme.text()
        font.family: Theme.body
        font.pixelSize: 12
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder: ""
        property bool wrap: false
        signal edited(string text)
        height: wrap ? Math.max(28, input.contentHeight + 12) : 26
        color: "#1b1a20"
        border.color: input.activeFocus ? Theme.accent : "#3a3842"
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: field.wrap ? 6 : 0
            verticalAlignment: field.wrap ? TextInput.AlignTop : TextInput.AlignVCenter
            wrapMode: field.wrap ? TextInput.WordWrap : TextInput.NoWrap
            color: Theme.text()
            selectionColor: Theme.accent
            font.family: Theme.body
            font.pixelSize: 12
            clip: true
            maximumLength: field.wrap ? 600 : 120
            onTextEdited: field.edited(text)
            Keys.onEscapePressed: focus = false
            Text {
                visible: input.text.length === 0
                text: field.placeholder
                color: Theme.dim()
                font: input.font
                anchors.verticalCenter: field.wrap ? undefined : parent.verticalCenter
            }
        }
    }
    component Check: Rectangle {
        property bool on: false
        signal toggled
        width: 16
        height: 16
        color: "transparent"
        border.color: on ? Theme.accent : Theme.track
        Rectangle { anchors.centerIn: parent; width: 8; height: 8; color: Theme.accent; visible: parent.on }
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }
    component Toggle: Row {
        property string text
        property bool on: false
        signal toggled
        spacing: 8
        Check { anchors.verticalCenter: parent.verticalCenter; on: parent.on; onToggled: parent.toggled() }
        Line { anchors.verticalCenter: parent.verticalCenter; text: parent.text }
    }
    component Slider: Row {
        property string label
        property real from: 0
        property real to: 100
        property real value: 0
        property real step: 1
        property string shown: ""
        signal moved(real value)
        spacing: 8
        height: 22
        Line { width: 70; anchors.verticalCenter: parent.verticalCenter; text: parent.label }
        HudSlider {
            width: 150
            anchors.verticalCenter: parent.verticalCenter
            from: parent.from; to: parent.to; stepSize: parent.step; value: parent.value
            onMoved: (v) => parent.moved(v)
        }
        Line { anchors.verticalCenter: parent.verticalCenter; text: parent.shown; color: Theme.textSoft() }
    }

    Column {
        width: parent.width
        spacing: 8

        // The tabs.
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: [["now", "Now"], ["sheets", "Sheets"], ["fights", "Fights"], ["voice", "Voice"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.tab === modelData[0]
                        width: tabText.implicitWidth
                        height: 32
                        Caps {
                            id: tabText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.tab = modelData[0] }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Line {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: "Callouts <b><font color='" + (panel.p.enabled !== false ? Theme.accent : Theme.dim()) + "'>" + (panel.p.enabled !== false ? "ON" : "OFF") + "</font></b>"
                color: Theme.muted()
                font.pixelSize: 11
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.brain.change("enabled", panel.p.enabled === false) }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // ---------------- NOW ----------------
        Column {
            visible: panel.tab === "now"
            width: parent.width
            spacing: 6
            Line {
                visible: !panel.st.fight
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: Theme.muted()
                text: !Aion2.active ? "Listens while AION 2 runs. In a boss fight your sheet shows here and over the game; the game's own calls are spoken and shown big."
                    : panel.brain && panel.brain.dungeon ? "In " + panel.brain.dungeons[panel.brain.dungeon].name + ": its cheat sheet is over the game. Set MY ROLE in SHEETS."
                    : "No boss fight now. Calls come as soon as a boss casts."
            }
            Row {
                visible: !panel.st.fight
                spacing: 6
                Chip { text: "Test: a purple phase"; onClicked: panel.brain.test() }
                Chip { visible: panel.brain && panel.brain.dungeon !== ""; text: "Open the cheat sheet"; onClicked: { panel.bossKey = panel.brain.dungeons[panel.brain.dungeon].bosses[0].key; panel.tab = "sheets" } }
            }
            Item {
                visible: !!panel.st.fight
                width: parent.width
                height: visible ? 26 : 0
                Caps { anchors.verticalCenter: parent.verticalCenter; text: panel.st.fight ? panel.st.fight.name.toUpperCase() : ""; font.pixelSize: 16; width: parent.width - 220 }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Line { anchors.verticalCenter: parent.verticalCenter; text: panel.st.fight && panel.st.fight.hp !== null ? Math.round(panel.st.fight.hp) + " % HP" : ""; color: "#ff8a8e" }
                    Caps { anchors.verticalCenter: parent.verticalCenter; text: panel.st.fight ? BN.fmtTime(panel.st.fight.elapsed) : ""; font.pixelSize: 14 }
                    Chip { text: "Edit sheet"; onClicked: { panel.bossKey = panel.st.fight.key; panel.tab = "sheets" } }
                }
            }
            Repeater {
                model: panel.st.fight ? panel.st.alerts : []
                delegate: Rectangle {
                    required property var modelData
                    width: panel.width - 28
                    height: 30
                    color: Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.16)
                    Line { x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 70; text: modelData.name + (modelData.text ? " · " + modelData.text : ""); font.weight: Font.DemiBold }
                    Caps { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: Math.ceil(modelData.left / 1000) + " s"; color: "#ff8a8e"; font.pixelSize: 14 }
                }
            }
            Repeater {
                model: panel.st.fight && panel.st.list ? panel.st.list.filter((e) => e.kind !== "alert") : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool current: panel.st.phase && panel.st.phase.id === modelData.id
                    width: panel.width - 28
                    height: nowCol.height + 8
                    color: current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : "#1b1a20"
                    Rectangle { visible: parent.current; width: 3; height: parent.height; color: Theme.accent }
                    Column {
                        id: nowCol
                        x: 12; y: 4
                        width: parent.width - 24
                        spacing: 2
                        Row {
                            spacing: 8
                            Caps { text: modelData.name; font.pixelSize: parent.parent.parent.current ? 18 : 13; color: parent.parent.parent.current ? Theme.accent : Theme.text() }
                            Line { anchors.bottom: parent.children[0].bottom; anchors.bottomMargin: 2; text: modelData.when + (modelData.role ? " · " + modelData.role : ""); color: Theme.dim(); font.pixelSize: 11 }
                        }
                        Line { visible: modelData.text.length > 0; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; text: modelData.text; color: Theme.textSoft() }
                    }
                }
            }
            Line {
                visible: !!panel.st.fight && !panel.st.hasSheet
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: Theme.muted()
                text: "No sheet for this boss yet. The fight is recorded: after it, open FIGHTS and turn a moment into a phase with one click."
            }
        }

        // ---------------- SHEETS ----------------
        Item {
            visible: panel.tab === "sheets"
            width: parent.width
            height: visible ? 470 + panel.grow : 0

            // The bosses by dungeon.
            Item {
                id: bossList
                width: 180
                height: parent.height
                Field { id: searchField; width: parent.width - 10; placeholder: "Search boss"; onEdited: (t) => panel.search = t }
                WheelScroll { flick: bossFlick; step: 78; z: 1; y: 32; width: parent.width; height: parent.height - 32 }
                Flickable {
                    id: bossFlick
                    y: 32
                    width: parent.width
                    height: parent.height - 32
                    clip: true
                    contentHeight: bossCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: false
                    Column {
                        id: bossCol
                        width: parent.width - 10
                        Repeater {
                            model: {
                                if (!panel.brain) return []
                                const q = panel.search.trim().toLowerCase()
                                return panel.brain.groups.map((g) => ({ id: g.id, name: g.name, bosses: g.bosses.filter((k) => !q || panel.brain.bossName(k).toLowerCase().indexOf(q) >= 0 || g.name.toLowerCase().indexOf(q) >= 0) }))
                                    .filter((g) => g.bosses.length)
                            }
                            delegate: Column {
                                required property var modelData
                                width: bossCol.width
                                Caps { width: parent.width; topPadding: 6; text: modelData.name.toUpperCase(); font.pixelSize: 10; color: Theme.dim(); wrapMode: Text.WordWrap; elide: Text.ElideNone }
                                Repeater {
                                    model: modelData.bosses
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool current: panel.bossKey === modelData
                                        width: bossCol.width
                                        height: 24
                                        color: current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : (bm.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                                        Line { x: 8; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; text: panel.brain.bossName(modelData); color: parent.current ? Theme.accent : Theme.textSoft() }
                                        Rectangle {
                                            visible: { panel.brain.sheetsRevision; const s = panel.brain.sheet(modelData); return !!s && ((s.entries || []).length > 0 || !!s.notes) }
                                            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                                            width: 6; height: 6; color: Theme.accent
                                        }
                                        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { panel.bossKey = modelData; panel.editing = "" } }
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Theme.divider }
            }

            // One boss's sheet.
            WheelScroll { flick: sheetFlick; step: 90; z: 1; x: sheetFlick.x; width: sheetFlick.width; height: sheetFlick.height }
            Flickable {
                id: sheetFlick
                x: 192
                width: parent.width - 192
                height: parent.height
                clip: true
                contentHeight: sheetCol.height + 10
                boundsBehavior: Flickable.StopAtBounds
                interactive: false
                Column {
                    id: sheetCol
                    width: sheetFlick.width - 6
                    spacing: 6
                    Item {
                        width: parent.width
                        height: 26
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Caps { anchors.verticalCenter: parent.verticalCenter; text: panel.brain ? panel.brain.bossName(panel.bossKey).toUpperCase() : ""; font.pixelSize: 17 }
                            Line {
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.dim(); font.pixelSize: 11
                                text: {
                                    if (!panel.brain) return ""
                                    const n = panel.brain.fights.filter((f) => f.key === panel.bossKey).length
                                    return (panel.brain.isStarter(panel.bossKey) ? "starter sheet" : "") + (n ? (panel.brain.isStarter(panel.bossKey) ? " · " : "") + "fought " + n + "×" : "")
                                }
                            }
                        }
                        Chip {
                            visible: panel.brain && !panel.brain.isStarter(panel.bossKey) && !!panel.sheet
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.brain && panel.brain.dungeons && panel.sheetDungeon ? "Reset to starter" : "Clear sheet"
                            onClicked: { panel.brain.resetSheet(panel.bossKey); panel.editing = "" }
                        }
                    }

                    // MY ROLE for a dungeon with a cheat sheet.
                    Column {
                        visible: panel.sheetDungeon !== ""
                        width: parent.width
                        spacing: 4
                        Caps { text: "MY ROLE IN " + (panel.sheetDungeon ? panel.brain.dungeons[panel.sheetDungeon].name.toUpperCase() : ""); font.pixelSize: 11; color: Theme.purpleText }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: panel.sheetDungeon ? panel.brain.dungeons[panel.sheetDungeon].roles : []
                                delegate: Chip {
                                    required property var modelData
                                    text: modelData
                                    on: panel.brain.myRoles(panel.sheetDungeon).indexOf(modelData) >= 0
                                    onClicked: panel.brain.toggleRole(panel.sheetDungeon, modelData)
                                }
                            }
                        }
                        Line { width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11; text: "Entries for other roles fade over the game. The cheat sheet shows by itself in this dungeon." }
                        Row {
                            spacing: 8
                            Chip {
                                readonly property bool shown: panel.brain && panel.brain.previewDungeon === panel.sheetDungeon
                                text: shown ? "Close preview" : "Show over game"
                                on: shown
                                onClicked: shown ? panel.brain.stopPreview() : panel.brain.startPreview(panel.sheetDungeon, panel.bossKey)
                            }
                            Line {
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.dim(); font.pixelSize: 11
                                text: "Try it outside the dungeon: ▶ on an entry plays it as in the fight."
                            }
                        }
                    }

                    // The game's calls.
                    Caps {
                        visible: panel.brain && panel.brain.callsOf(panel.bossKey).length > 0
                        text: "THE GAME'S CALLS"
                        font.pixelSize: 11
                        color: Theme.dim()
                    }
                    Repeater {
                        model: panel.brain ? panel.brain.callsOf(panel.bossKey) : []
                        delegate: Rectangle {
                            required property var modelData
                            readonly property var c: panel.brain.callText(modelData)
                            property bool ownOpen: false
                            width: sheetCol.width
                            height: callCol.height + 10
                            color: "#1b1a20"
                            Check {
                                x: 8; y: 8
                                on: !(panel.p.offCall || {})[modelData.k] && !(panel.p.offBoss || {})[modelData.b]
                                onToggled: panel.brain.changeIn("offCall", modelData.k, on ? true : undefined)
                            }
                            Column {
                                id: callCol
                                x: 32; y: 5
                                width: parent.width - 100
                                spacing: 2
                                Line {
                                    width: parent.width
                                    wrapMode: Text.WordWrap; elide: Text.ElideNone
                                    font.weight: Font.DemiBold
                                    color: parent.parent.c.own ? Theme.accent : parent.parent.c.act ? Theme.accentLight : Theme.text()
                                    text: (parent.parent.c.own || parent.parent.c.act || parent.parent.c.line) + (parent.parent.c.phase ? " · " + parent.parent.c.phase : "")
                                }
                                Line {
                                    width: parent.width
                                    wrapMode: Text.WordWrap; elide: Text.ElideNone
                                    color: Theme.dim(); font.pixelSize: 11
                                    text: parent.parent.c.trigger + (parent.parent.c.act || parent.parent.c.own ? " · “" + parent.parent.c.line + "”" : "")
                                }
                                Field {
                                    visible: parent.parent.ownOpen
                                    width: parent.width
                                    placeholder: "Your own words (said by the computer's voice)"
                                    text: parent.parent.c.own
                                    onEdited: (t) => panel.brain.changeIn("custom", modelData.k, t.trim() || undefined)
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                y: 4
                                IconButton { icon: "play"; tip: "Play this call"; onClicked: panel.brain.preview(modelData.k) }
                                IconButton { icon: "edit"; tip: "Your own words"; onClicked: parent.parent.ownOpen = !parent.parent.ownOpen }
                            }
                        }
                    }

                    // Your phases and alerts.
                    Caps { text: "YOUR PHASES AND ALERTS"; font.pixelSize: 11; color: Theme.dim(); topPadding: 4 }
                    Line {
                        visible: !panel.sheet || !(panel.sheet.entries || []).length
                        width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.muted()
                        text: "None yet. + Phase stays until the next phase; + Alert shows a while with a countdown. Or fight the boss once and take moments from FIGHTS."
                    }
                    Repeater {
                        model: panel.sheet ? panel.sheet.entries || [] : []
                        delegate: Rectangle {
                            id: entryRow
                            required property var modelData
                            required property int index
                            readonly property bool open: panel.editing === modelData.id
                            width: sheetCol.width
                            height: (open ? form.height : entryCol.height) + 10
                            color: "#1b1a20"
                            border.color: open ? Theme.accent : "transparent"
                            Rectangle {
                                visible: !entryRow.open
                                x: 8; y: 7
                                width: 56; height: 18
                                color: "transparent"
                                border.color: entryRow.modelData.kind === "alert" ? "#ff8a8e" : Theme.accent
                                Caps { anchors.centerIn: parent; text: entryRow.modelData.kind === "alert" ? "ALERT" : "PHASE"; font.pixelSize: 10; color: parent.border.color }
                            }
                            Column {
                                id: entryCol
                                visible: !entryRow.open
                                x: 72; y: 5
                                width: parent.width - 180
                                spacing: 1
                                Line {
                                    width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                    textFormat: Text.StyledText
                                    text: "<b>" + entryRow.modelData.name + "</b> <font color='" + Theme.dim() + "'>· " + panel.brain.describe(entryRow.modelData.when)
                                        + (entryRow.modelData.kind === "alert" ? " · " + Math.round((entryRow.modelData.ms || 8000) / 1000) + " s" : "")
                                        + (entryRow.modelData.role ? " · " + entryRow.modelData.role : "") + "</font>"
                                }
                                Line { visible: (entryRow.modelData.text || "").length > 0; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.textSoft(); text: entryRow.modelData.text || "" }
                            }
                            Row {
                                visible: !entryRow.open
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                y: 3
                                IconButton { icon: "play"; tip: "Play this entry as in the fight"; onClicked: panel.brain.playEntry(panel.bossKey, entryRow.modelData) }
                                IconButton { icon: "back"; rotation: 90; tip: "Earlier"; onClicked: panel.brain.moveEntry(panel.bossKey, entryRow.modelData.id, -1) }
                                IconButton { icon: "edit"; tip: "Edit"; onClicked: panel.editing = entryRow.modelData.id }
                            }
                            // The form.
                            Column {
                                id: form
                                visible: entryRow.open
                                x: 10; y: 5
                                width: parent.width - 20
                                spacing: 6
                                readonly property var e: entryRow.modelData
                                function set(patch) { panel.brain.changeEntry(panel.bossKey, form.e.id, patch) }
                                Row {
                                    spacing: 6
                                    Chip { text: "Phase"; on: form.e.kind !== "alert"; onClicked: form.set({ kind: "phase" }) }
                                    Chip { text: "Alert"; on: form.e.kind === "alert"; onClicked: form.set({ kind: "alert" }) }
                                }
                                Field { width: parent.width; placeholder: "Name (shown big, said aloud)"; text: form.e.name; onEdited: (t) => form.set({ name: t }) }
                                Field { width: parent.width; wrap: true; placeholder: "What to do"; text: form.e.text || ""; onEdited: (t) => form.set({ text: t }) }
                                Line { text: "Starts"; color: Theme.dim(); font.pixelSize: 11 }
                                Flow {
                                    width: parent.width
                                    spacing: 6
                                    Repeater {
                                        model: [["start", "At the pull"], ["hp", "HP at or under %"], ["time", "Seconds in"], ["cast", "Boss casts"], ["skill", "Boss uses"], ["buff", "Buff lands"], ["buffEnd", "Buff ends"], ["none", "By hand"]]
                                        delegate: Chip {
                                            required property var modelData
                                            text: modelData[1]
                                            on: form.e.when && form.e.when.type === modelData[0]
                                            onClicked: form.set({ when: { type: modelData[0], value: modelData[0] === "hp" ? 50 : modelData[0] === "time" ? 60 : (form.e.when || {}).value || 0 } })
                                        }
                                    }
                                }
                                Row {
                                    visible: form.e.when && ["start", "none"].indexOf(form.e.when.type) < 0
                                    spacing: 8
                                    Line { anchors.verticalCenter: parent.verticalCenter; text: form.e.when && form.e.when.type === "hp" ? "HP %" : form.e.when && form.e.when.type === "time" ? "Seconds" : "Skill or buff id"; color: Theme.dim() }
                                    Field {
                                        width: 110
                                        text: form.e.when ? String(form.e.when.value || "") : ""
                                        onEdited: (t) => { const v = Number(t); if (isFinite(v)) form.set({ when: { type: form.e.when.type, value: v } }) }
                                    }
                                    Line { anchors.verticalCenter: parent.verticalCenter; width: 200; color: Theme.dim(); font.pixelSize: 11; text: form.e.when ? panel.brain.lineOf(form.e.when.type === "buffEnd" ? "buff" : form.e.when.type, form.e.when.value) : "" }
                                }
                                Row {
                                    visible: form.e.kind === "alert"
                                    spacing: 8
                                    Line { anchors.verticalCenter: parent.verticalCenter; text: "Shows for (s)"; color: Theme.dim() }
                                    Field { width: 70; text: String(Math.round((form.e.ms || 8000) / 1000)); onEdited: (t) => { const v = Number(t); if (v > 0) form.set({ ms: v * 1000 }) } }
                                }
                                Row {
                                    visible: panel.sheetDungeon !== ""
                                    spacing: 6
                                    Line { anchors.verticalCenter: parent.verticalCenter; text: "For"; color: Theme.dim() }
                                    Chip { text: "Everyone"; on: !form.e.role; onClicked: form.set({ role: "" }) }
                                    Repeater {
                                        model: panel.sheetDungeon ? panel.brain.dungeons[panel.sheetDungeon].roles : []
                                        delegate: Chip { required property var modelData; text: modelData; on: form.e.role === modelData; onClicked: form.set({ role: modelData }) }
                                    }
                                }
                                Row {
                                    spacing: 8
                                    TextButton { text: "Done"; onClicked: panel.editing = "" }
                                    TextButton { text: "Delete"; danger: true; onClicked: { panel.brain.removeEntry(panel.bossKey, form.e.id); panel.editing = "" } }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 6
                        Chip { text: "+ Phase"; on: true; onClicked: panel.editing = panel.brain.addEntry(panel.bossKey, { kind: "phase", name: "New phase", text: "", role: "", when: { type: "hp", value: 50 } }) }
                        Chip { text: "+ Alert"; onClicked: panel.editing = panel.brain.addEntry(panel.bossKey, { kind: "alert", name: "New alert", text: "", role: "", ms: 8000, when: { type: "time", value: 60 } }) }
                    }
                    Line { text: "General notes"; color: Theme.dim(); font.pixelSize: 11; topPadding: 4 }
                    Field {
                        width: parent.width
                        wrap: true
                        placeholder: "Shown under the sheet over the game"
                        text: panel.sheet ? panel.sheet.notes || "" : ""
                        onEdited: (t) => panel.brain.setNotes(panel.bossKey, t)
                    }
                    Row {
                        spacing: 6
                        topPadding: 6
                        Chip { text: "Copy all sheets"; onClicked: { clip.text = panel.brain.exportSheets(); clip.selectAll(); clip.copy(); panel.note = "Copied: paste them to your group." } }
                        Chip { text: "Paste sheets"; onClicked: { clip.text = ""; clip.paste(); const n = panel.brain.importSheets(clip.text); panel.note = n ? n + " sheets added." : "Nothing to paste: copy sheets from Boss first." } }
                        Line { anchors.verticalCenter: parent.verticalCenter; text: panel.note; color: Theme.muted(); font.pixelSize: 11 }
                    }
                    TextEdit { id: clip; visible: false }
                }
            }
        }

        // ---------------- FIGHTS ----------------
        Column {
            visible: panel.tab === "fights"
            width: parent.width
            spacing: 6
            readonly property var fight: {
                if (!panel.brain) return null
                const list = panel.brain.fights
                return list.find((f) => f.id === panel.fightId) || list[0] || null
            }
            readonly property var sum: fight ? BN.summary(fight, panel.brain.bossData, "en") : null
            Line {
                visible: !parent.fight
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.muted()
                text: "No boss fight recorded yet. Every boss fight is recorded: what the boss cast and used, its buffs and its HP (only the boss's, never a player's)."
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: panel.brain ? panel.brain.fights : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: parent.parent.fight && parent.parent.fight.id === modelData.id
                        width: fCol.width + 18
                        height: 36
                        color: current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.12) : "transparent"
                        border.color: current ? Theme.accent : "#3a3842"
                        Column {
                            id: fCol
                            x: 9; anchors.verticalCenter: parent.verticalCenter
                            Line { text: modelData.name; font.weight: Font.DemiBold; color: parent.parent.current ? Theme.accent : Theme.text() }
                            Line {
                                font.pixelSize: 10; color: Theme.dim()
                                text: new Date(modelData.start).toLocaleTimeString(Qt.locale(), "HH:mm") + " · " + BN.fmtTime(modelData.end - modelData.start) + " · " + (modelData.low !== null && modelData.low <= 0.5 ? "killed" : modelData.low !== null ? "ended at " + Math.round(modelData.low) + " %" : "")
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.fightId = modelData.id }
                    }
                }
            }
            // The HP's course.
            Rectangle {
                visible: !!parent.fight
                width: parent.width
                height: visible ? 40 : 0
                color: "#1b1a20"
                Row {
                    anchors.fill: parent
                    anchors.margins: 2
                    Repeater {
                        model: {
                            const f = parent.parent.parent.fight
                            if (!f) return []
                            const hs = (f.events || []).filter((e) => e[1] === "h")
                            const out = []
                            const n = 40
                            const dur = Math.max(1, f.end - f.start)
                            let hp = 100, j = 0
                            for (let i = 0; i < n; i++) {
                                const t = dur * (i + 1) / n
                                while (j < hs.length && hs[j][0] <= t) { hp = hs[j][2]; j++ }
                                out.push(hp)
                            }
                            return out
                        }
                        delegate: Item {
                            required property var modelData
                            width: (panel.width - 32) / 40
                            height: 36
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width - 1; height: Math.max(1, parent.height * modelData / 100); color: Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.5) }
                        }
                    }
                }
            }
            Row {
                visible: !!parent.fight
                x: 8
                Repeater {
                    model: [["TIME", 50], ["HP", 46], ["WHAT THE BOSS DID", panel.width - 300], ["×", 34], ["", 140]]
                    delegate: Caps { required property var modelData; width: modelData[1]; text: modelData[0]; font.pixelSize: 10; color: Theme.dim() }
                }
            }
            Item {
                visible: !!parent.fight
                width: parent.width
                height: visible ? 300 + panel.grow : 0
                WheelScroll { flick: fightFlick; step: 84; z: 1 }
                Flickable {
                    id: fightFlick
                    anchors.fill: parent
                    clip: true
                    contentHeight: fightCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: false
                    Column {
                        id: fightCol
                        width: parent.width
                        spacing: 3
                        Repeater {
                            model: {
                                const s = fightFlick.parent.parent.sum
                                if (!s) return []
                                const rows = s.list.map((g) => ({ t: g.first, hp: g.firstHp, kind: g.kind, id: g.id, line: g.line, count: g.count, length: g.length }))
                                for (const m of s.marks) rows.push({ t: m.t, hp: m.hp, kind: "hp", id: Math.floor(m.hp / 10) * 10, line: "", count: 0 })
                                rows.sort((a, b) => a.t - b.t)
                                return rows
                            }
                            delegate: Rectangle {
                                required property var modelData
                                width: fightCol.width
                                height: Math.max(36, rowCol.height + 8)
                                color: "#1b1a20"
                                Row {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    Line { width: 50; text: BN.fmtTime(modelData.t); color: Theme.textSoft() }
                                    Line { width: 46; text: modelData.hp !== null && modelData.hp !== undefined ? Math.round(modelData.hp) + " %" : ""; color: Theme.textSoft() }
                                    Column {
                                        id: rowCol
                                        width: panel.width - 300
                                        Line {
                                            width: parent.width
                                            textFormat: Text.StyledText
                                            readonly property string kc: ({ cast: Theme.purpleText, skill: Theme.textSoft(), buff: Theme.accent, buffEnd: Theme.dim(), hp: "#ff8a8e" })[modelData.kind]
                                            text: "<font color='" + kc + "'><b>" + ({ cast: "CAST", skill: "SKILL", buff: "BUFF", buffEnd: "BUFF END", hp: "HP" })[modelData.kind] + "</b></font> "
                                                + (modelData.kind === "hp" ? "under " + (modelData.id + 10) + " %" : (modelData.kind === "cast" || modelData.kind === "skill" ? "Skill " : "") + modelData.id + (modelData.length ? " · " + Math.round(modelData.length / 1000) + " s" : ""))
                                        }
                                        Line { visible: modelData.kind !== "hp"; width: parent.width; font.pixelSize: 11; color: Theme.dim(); text: modelData.line ? "The game shows: “" + modelData.line + "”" : "No line in the game" }
                                    }
                                    Line { width: 34; text: modelData.count ? modelData.count + "×" : ""; color: Theme.muted() }
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Repeater {
                                        model: ["phase", "alert"]
                                        delegate: Chip {
                                            required property var modelData
                                            text: "+ " + (modelData === "phase" ? "Phase" : "Alert")
                                            onClicked: {
                                                const r = parent.parent.modelData
                                                const f = fightFlick.parent.parent.fight
                                                const when = r.kind === "hp" ? { type: "hp", value: r.id + 10 } : { type: r.kind, value: r.id }
                                                const name = r.line ? r.line.slice(0, 40) : (modelData === "phase" ? "New phase" : "New alert")
                                                panel.bossKey = f.key
                                                panel.editing = panel.brain.addEntry(f.key, { kind: modelData, name: name, text: "", role: "", ms: r.length > 0 && r.length < 600000 ? r.length : 8000, when: when })
                                                panel.tab = "sheets"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Line {
                visible: !!parent.fight
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11
                text: "Only the boss is recorded, never a player. Each thing once, when it came first. The last " + (panel.p.keepFights || 10) + " fights are kept."
            }
        }

        // ---------------- VOICE ----------------
        Row {
            visible: panel.tab === "voice"
            width: parent.width
            spacing: 18
            Column {
                width: (parent.width - 18) / 2
                spacing: 8
                Caps { text: "CALLS"; font.pixelSize: 11; color: Theme.dim() }
                Line { text: "Call style" }
                Flow {
                    width: parent.width
                    spacing: 4
                    Chip { text: "Call and line"; on: (panel.p.style || "both") === "both"; onClicked: panel.brain.change("style", "both") }
                    Chip { text: "Call only"; on: panel.p.style === "act"; onClicked: panel.brain.change("style", "act") }
                    Chip { text: "Line only"; on: panel.p.style === "line"; onClicked: panel.brain.change("style", "line") }
                }
                Line { width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11; text: "Call: “Purple — stop magic attacks”. Line: what the boss says." }
                Toggle { text: "Big call on screen (off: spoken only)"; on: panel.p.widget !== false; onToggled: panel.brain.change("widget", !on) }
                Toggle { text: "Speak my phases and alerts too"; on: panel.p.speakMine !== false; onToggled: panel.brain.change("speakMine", !on) }
                Toggle { text: "Beep on Vakron's jump waves"; on: (panel.p.waves || {})["vakron-jump"] !== false; onToggled: panel.brain.changeIn("waves", "vakron-jump", on ? false : undefined) }
                Caps { text: "VOICE"; font.pixelSize: 11; color: Theme.dim(); topPadding: 6 }
                Line {
                    width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11
                    text: "Built-in: the game's lines, recorded once in English (Kokoro, Apache 2.0). Your own words: the computer's voice (speech-dispatcher), "
                        + (Aion2.systemVoice() ? "installed." : "not installed: pacman -S speech-dispatcher espeak-ng")
                }
                Slider { label: "Volume"; from: 0; to: 100; value: panel.p.volume === undefined ? 70 : panel.p.volume; shown: String(Math.round(value)); onMoved: (v) => panel.brain.change("volume", Math.round(v)) }
                Slider { label: "Speed"; from: 0.5; to: 2; step: 0.1; value: panel.p.rate || 1; shown: (value).toFixed(1) + "×"; onMoved: (v) => panel.brain.change("rate", Math.round(v * 10) / 10) }
                Chip { text: "Test: a purple phase"; on: true; onClicked: panel.brain.test() }
            }
            Column {
                width: (parent.width - 18) / 2
                spacing: 8
                Caps { text: "BIG CALL"; font.pixelSize: 11; color: Theme.dim() }
                Line { text: "Colours" }
                Row {
                    spacing: 4
                    Chip { text: "As the game"; on: panel.p.colours !== "contrast"; onClicked: panel.brain.change("colours", "game") }
                    Chip { text: "High contrast"; on: panel.p.colours === "contrast"; onClicked: panel.brain.change("colours", "contrast") }
                }
                Line { width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11; text: "As the game: purple and red as the boss glows, “Safe” in white. High contrast: yellow on black." }
                Slider { label: "Text size"; from: 32; to: 80; value: panel.p.size || 56; shown: Math.round(value) + " px"; onMoved: (v) => panel.brain.change("size", Math.round(v)) }
                Row {
                    spacing: 4
                    Line { width: 70; anchors.verticalCenter: parent.verticalCenter; text: "Ground" }
                    Repeater {
                        model: [1, 0.8, 0.5, 0.25, 0.1]
                        delegate: Chip { required property var modelData; text: String(Math.round(modelData * 100)); on: Math.abs((panel.p.ground === undefined ? 0.8 : panel.p.ground) - modelData) < 0.01; onClicked: panel.brain.change("ground", modelData) }
                    }
                }
                Caps { text: "SHEET OVER THE GAME"; font.pixelSize: 11; color: Theme.dim(); topPadding: 6 }
                Toggle { text: "Show my sheet in a boss fight"; on: panel.p.overlay !== false; onToggled: panel.brain.change("overlay", !on) }
                Toggle { text: "Cheat sheet in its dungeon (Ludra)"; on: panel.p.inDungeon !== false; onToggled: panel.brain.change("inDungeon", !on) }
                Toggle { text: "Next phase"; on: panel.p.showNext !== false; onToggled: panel.brain.change("showNext", !on) }
                Toggle { text: "General notes"; on: panel.p.showNotes !== false; onToggled: panel.brain.change("showNotes", !on) }
                Toggle { text: "Keep it up between fights"; on: !!panel.p.keep; onToggled: panel.brain.change("keep", !on) }
                Row {
                    spacing: 4
                    Line { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Fights kept" }
                    Repeater {
                        model: [5, 10, 20]
                        delegate: Chip { required property var modelData; text: String(modelData); on: (panel.p.keepFights || 10) === modelData; onClicked: panel.brain.change("keepFights", modelData) }
                    }
                }
            }
        }
        Line {
            visible: panel.tab === "voice"
            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Theme.dim(); font.pixelSize: 11
            text: "Only what a sighted player sees: no hidden timers, no guesses. Nothing is sent. Boss data and voice: A2 Tools' Boss Callouts (GPL-3.0)."
        }
    }
}
