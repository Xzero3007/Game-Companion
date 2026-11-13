import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "armorykit.js" as AK
import "buildkit.js" as BK

// The AION 2 module's Armory (the Clicktrough Armory plugin in QML; canvas
// page "Armory mit Builds", boards AR1–AR4): a character as NC's official
// character pages show it, every value written out, and builds tied to
// characters. The active build is what every tab measures against: its
// progress, the next steps (ticked by themselves when a reading shows
// them done), the gear slot by slot, soul binding wishes, skill targets,
// Daevanion nodes, the goal gear score, and the history with boss fights.
Panel {
    id: panel
    panelId: "armory"
    title: "Armory"
    tag: width < 620 ? "" : "AION 2"
    width: 860
    minWidth: 640
    maxWidth: 1400
    stretchy: true
    minGrow: -200

    property var store
    /// Characters from CHARACTERS (Main's CharacterStore): picked here too.
    property var characters: null
    readonly property int rev: store ? store.revision : 0
    readonly property bool ready: !!store && store.ready
    readonly property var ck: ready ? AK.C : null
    readonly property var snap: { rev; return store ? store.snap : null }
    readonly property var build: { rev; return store ? store.build() : null }
    readonly property var targets: { rev; return store ? store.targets() : BK.emptyTargets() }
    readonly property var charRec: { rev; return store && store.current ? store.state.chars[store.current] : null }
    readonly property string tab: { rev; return store ? store.state.settings.tab || "overview" : "overview" }
    property int iconRev: 0
    Connections { target: Aion2; function onIconReady(name) { panel.iconRev++ } }

    function setTab(t) { if (!store) return; store.state.settings.tab = t; store.changed() }
    function fmt(v, d) { return ck ? ck.fmt(v, d || 0) : String(v) }
    function brief(v) { return ck ? ck.brief(v) : String(v) }
    function label(slot) { return ck ? (ck.SLOT_LABEL[slot] || slot) : slot }
    function levelText(x) { return "+" + ((x && x.enchant) || 0) + (x && x.amplify ? " A" + x.amplify : "") }
    function plusMinus(v) { return v > 0 ? "+" + fmt(v) : v < 0 ? "−" + fmt(-v) : "±0" }
    function matsText(mats) {
        const out = []
        for (const k in mats || {}) out.push(fmt(Math.ceil(mats[k])) + " " + ck.material(k).name.replace(/ \(Bound\)$/, ""))
        return out.join(" + ") || "nothing"
    }
    function chanceText(p) {
        if (p == null) return ""
        if (p <= 0) return "never (more than the piece takes, or one it can't get)"
        if (p >= 0.995) return "certain"
        if (p >= 0.1) return fmt(p * 100) + " %"
        if (p >= 0.01) return fmt(p * 100, 1) + " %, about 1 in " + fmt(Math.round(1 / p))
        return "about 1 in " + fmt(Math.round(1 / p))
    }
    function gradeColour(g) { return g === "Unique" ? "#f2c46b" : g === "Legend" ? "#4fa8ff" : g === "Rare" ? "#7fdc9a" : g === "Epic" ? "#c4a8f0" : Theme.text() }
    readonly property var classColours: ({ Gladiator: "#e0a04a", Templar: "#7fa7d9", Assassin: "#c46ad1", Ranger: "#7cc46a", Sorcerer: "#e06a6a", Spiritmaster: "#6ad1c4", Cleric: "#f0d36a", Chanter: "#d18f6a" })

    // The characters to pick: the Armory's and those CHARACTERS knows.
    function knownChars() {
        rev
        const out = {}
        if (store) for (const k in store.state.chars) out[k] = { key: k, name: store.state.chars[k].name || k.split("@")[0], serverId: store.state.chars[k].serverId, cls: store.state.chars[k].className || "" }
        if (characters) { characters.revision; for (const k in characters.state.chars) { const c = characters.state.chars[k]; if (!out[k]) out[k] = { key: k, name: c.name, serverId: c.serverId, cls: c["class"] || "" } } }
        return Object.keys(out).map((k) => out[k]).sort((a, b) => (store && b.key === store.current) - (store && a.key === store.current) || a.name.localeCompare(b.name))
    }
    function serverName(id) { return characters ? characters.serverName(id) : String(id) }
    function openChar(c) {
        store.open(c.key)
        if (!store.snap) store.read({ name: c.name, serverId: c.serverId, characterId: (store.state.chars[c.key] || {}).characterId })
    }

    property bool picking: false
    property var results: []
    property string lookError: ""
    readonly property var regions: [[1, "NA East"], [2, "NA West"], [3, "Europe"], [4, "South America"], [5, "Asia"]]
    function regionName(r) { for (const x of regions) if (x[0] === r) return x[1]; return "Europe" }
    function region() {
        rev
        if (store && store.state.settings.region) return store.state.settings.region
        const sid = (snap && snap.profile && snap.profile.serverId) || (store && store.playing && store.playing.serverId) || 2300
        return Math.floor(sid / 100) % 10 || 3
    }
    Timer { id: lookTimer; interval: 500; onTriggered: panel.lookUp() }
    function lookUp() {
        const q = lookField.text.trim()
        lookError = ""
        if (q.length < 2) { results = []; return }
        store.lookUp(q, region()).then((list) => {
            results = list.slice(0, 12)
            if (!list.length) lookError = "No one by that name in " + regionName(region()) + "."
        }, (e) => { lookError = String(e && e.message ? e.message : e) })
    }

    Component.onCompleted: if (store) store.ensure()

    Column {
        width: parent.width
        spacing: 8

        // ---- the character ----
        Item {
            width: parent.width
            height: 58
            Rectangle {
                id: face
                width: 52
                height: 52
                color: "#1b1a20"
                Image {
                    id: classMark
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    visible: !portrait.visible && status === Image.Ready
                    sourceSize.width: 68
                    source: {
                        const f = { Gladiator: "gladiator", Templar: "templar", Assassin: "assassin", Ranger: "ranger", Sorcerer: "sorcerer", Spiritmaster: "spiritmaster",
                            Elementalist: "spiritmaster", Cleric: "cleric", Chanter: "chanter", Brawler: "brawler" }[panel.snap && panel.snap.profile ? panel.snap.profile.className : ""]
                        return f ? "qrc:/qt/qml/GameCompanion/assets/aion2/classes/" + f + ".png" : ""
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !portrait.visible && !classMark.visible
                    text: panel.snap && panel.snap.profile ? String(panel.snap.profile.className || "?").slice(0, 2).toUpperCase() : "?"
                    color: panel.snap && panel.snap.profile ? (panel.classColours[panel.snap.profile.className] || Theme.text()) : Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Image {
                    id: portrait
                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    source: panel.snap && panel.snap.profile && panel.snap.profile.portrait ? panel.snap.profile.portrait : ""
                    visible: status === Image.Ready
                }
            }
            Column {
                x: 64
                width: parent.width - 64 - figures.width - 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Row {
                    spacing: 8
                    width: parent.width
                    Text {
                        id: nameText
                        text: (panel.snap && panel.snap.profile ? panel.snap.profile.name : (panel.store && panel.store.current ? panel.store.current.split("@")[0] : "No character yet")) + "  ▾"
                        color: nameMouse.containsMouse ? Theme.accent : Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        style: Theme.textStyle(); styleColor: Theme.shadow
                        MouseArea { id: nameMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.picking = !panel.picking }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Pick a character"
                    }
                    AUi.Line {
                        anchors.baseline: nameText.baseline
                        width: Math.max(0, parent.width - nameText.width - playTag.width - 16)
                        color: Theme.muted()
                        text: {
                            const p = panel.snap && panel.snap.profile
                            return p ? [p.className, "Lv " + p.level, p.serverName, p.legion].filter((x) => x).join(" · ") : ""
                        }
                    }
                    Text {
                        id: playTag
                        anchors.baseline: nameText.baseline
                        visible: !!panel.store && !!panel.store.playing && panel.store.playing.key === panel.store.current
                        text: "PLAYING"
                        color: Theme.accent
                        font.family: Theme.display
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }
                }
                Row {
                    spacing: 6
                    AUi.Line {
                        font.pixelSize: 11
                        color: panel.store && panel.store.error ? "#ff8a7a" : Theme.dim()
                        text: panel.store ? (panel.store.error || panel.store.status || (panel.snap ? "" : "Play a character (it is read by itself), or look one up by name.")) : ""
                        width: Math.min(implicitWidth, 420)
                    }
                    Text {
                        visible: !!panel.store && !!panel.store.current && !panel.store.loading
                        text: "UPDATE"
                        color: updMouse.containsMouse ? Theme.accentLight : Theme.accent
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                        MouseArea {
                            id: updMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const c = panel.store.state.chars[panel.store.current]
                                if (c && c.name) panel.store.read(c)
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Read again from NC's page"
                    }
                }
            }
            Row {
                id: figures
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18
                Repeater {
                    model: {
                        const p = panel.snap && panel.snap.profile
                        const live = panel.store && panel.store.playing && panel.store.playing.key === panel.store.current ? panel.store.playing : null
                        const gs = panel.snap && panel.ck ? BK.gsOf(panel.snap) : null
                        return [
                            ["COMBAT POWER", p ? panel.fmt(p.cp) : "—", Theme.text(), live && live.cp && p && live.cp !== p.cp ? "in the game " + panel.fmt(live.cp) : ""],
                            ["GEAR SCORE", gs ? panel.fmt(gs) : "—", Theme.accent, live && live.gs && live.gs !== gs ? "in the game " + panel.fmt(live.gs) : ""]
                        ]
                    }
                    delegate: Column {
                        required property var modelData
                        spacing: 0
                        AUi.Head { anchors.right: parent.right; text: modelData[0] }
                        AUi.Figure { anchors.right: parent.right; text: modelData[1]; color: modelData[2]; font.pixelSize: 22 }
                        AUi.Line { anchors.right: parent.right; visible: modelData[3] !== ""; text: modelData[3]; font.pixelSize: 10; color: Theme.dim() }
                    }
                }
            }
        }

        // ---- the characters to pick, and looking someone up ----
        AUi.Box {
            visible: panel.picking
            width: parent.width
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: panel.picking ? panel.knownChars() : []
                    delegate: Chip {
                        required property var modelData
                        text: modelData.name + " · " + panel.serverName(modelData.serverId)
                        dot: panel.classColours[modelData.cls] || "transparent"
                        on: !!panel.store && modelData.key === panel.store.current
                        onClicked: { panel.picking = false; panel.openChar(modelData) }
                    }
                }
            }
            Row {
                spacing: 6
                AUi.Field {
                    id: lookField
                    width: 220
                    placeholder: "Look up a name"
                    onEdited: lookTimer.restart()
                    onAccepted: { lookTimer.stop(); panel.lookUp() }
                }
                Chip {
                    text: panel.regionName(panel.region()) + " ▾"
                    onClicked: {
                        const r = panel.region() % 5 + 1
                        panel.store.state.settings.region = r
                        panel.store.changed()
                        if (lookField.text.trim().length >= 2) panel.lookUp()
                    }
                }
                AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: panel.lookError; color: Theme.dim(); font.pixelSize: 11 }
            }
            Flow {
                width: parent.width
                spacing: 6
                visible: panel.results.length > 0
                Repeater {
                    model: panel.results
                    delegate: Chip {
                        required property var modelData
                        text: modelData.name + " · " + modelData.serverName + " · Lv " + modelData.level
                        onClicked: {
                            panel.picking = false
                            panel.results = []
                            lookField.text = ""
                            panel.store.read({ name: modelData.name, serverId: modelData.serverId, characterId: modelData.characterId })
                        }
                    }
                }
            }
        }

        // ---- the active build ----
        Rectangle {
            width: parent.width
            height: 40
            color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08)
            border.color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.35)
            visible: !!panel.store && !!panel.store.current
            Row {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                AUi.Head { anchors.verticalCenter: parent.verticalCenter; text: "ACTIVE BUILD" }
                Repeater {
                    model: {
                        panel.rev
                        const c = panel.charRec
                        return c ? (c.builds || []).map((id) => panel.store.state.builds[id]).filter((b) => b) : []
                    }
                    delegate: Chip {
                        required property var modelData
                        text: modelData.name + " · " + modelData.kind
                        on: !!panel.build && panel.build.id === modelData.id
                        onClicked: panel.store.setActive(modelData.id)
                    }
                }
                AUi.Line {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !panel.build
                    color: Theme.muted()
                    text: "No build on this character yet:"
                }
                Chip {
                    visible: !panel.build
                    text: "Make or pick one"
                    onClicked: panel.setTab("builds")
                }
                AUi.Line {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!panel.build
                    font.pixelSize: 11
                    color: Theme.muted()
                    text: {
                        if (!panel.build) return ""
                        const others = BK.charsOf(panel.store.state, panel.build.id).filter((c) => c.key !== panel.store.current && c.active).map((c) => c.name)
                        return "from " + panel.build.source + " · v" + panel.build.version + (others.length ? " · also on " + others.join(", ") : "")
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: !!panel.build && !!panel.targets.goalGs
                AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: "Goal"; color: Theme.muted(); font.pixelSize: 11 }
                AUi.Figure { anchors.verticalCenter: parent.verticalCenter; text: "GS " + panel.fmt(panel.targets.goalGs || 0); font.pixelSize: 16 }
            }
        }

        // ---- the tabs ----
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 16
                Repeater {
                    model: [["overview", "Overview"], ["gear", "Gear"], ["soul", "Soul binding"], ["skills", "Skills"], ["daevanion", "Daevanion"],
                        ["stats", "Stats"], ["goals", "Goals"], ["builds", "Builds"], ["history", "History"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: panel.tab === modelData[0]
                        width: tabText.implicitWidth
                        height: 32
                        Text {
                            id: tabText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.setTab(modelData[0]) }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // ---- the tab ----
        Item {
            width: parent.width
            height: Math.max(220, 520 + panel.grow)
            WheelScroll { flick: page; step: 120; z: 1 }
            Flickable {
            id: page
            anchors.fill: parent
            contentHeight: pageLoader.item ? pageLoader.item.height + 8 : 0
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: pageLoader
                width: page.width
                active: panel.ready
                source: {
                    const files = { overview: "ArmoryOverview.qml", gear: "ArmoryGear.qml", soul: "ArmorySoul.qml", skills: "ArmorySkills.qml",
                        daevanion: "ArmoryDaevanion.qml", stats: "ArmoryStats.qml", goals: "ArmoryGoals.qml", builds: "ArmoryBuilds.qml", history: "ArmoryHistory.qml" }
                    return files[panel.tab] || files.overview
                }
                onLoaded: { item.ui = panel; page.contentY = 0 }
                onStatusChanged: if (status === Loader.Error) console.warn("Armory: the tab " + source + " failed to load")
            }
            }
        }
    }
}
