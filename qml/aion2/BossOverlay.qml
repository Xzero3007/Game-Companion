import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme

// Your sheet over the game (Boss Notes' overlay and the dungeon cheat sheet;
// boards K1 and K5): in a boss fight the boss's name, HP and time, your
// alerts with their countdown, the phase you are in, what comes next and
// the notes. In a dungeon with a cheat sheet (Ludra) also between fights:
// every boss of it as a tab (the one fought picked by itself), MY ROLE, and
// the whole sheet with the phase you are in big. Its own surface; dragged
// by its head while unlocked.
Item {
    id: ov

    property var brain: null
    readonly property var p: brain ? brain.prefs : ({})
    readonly property var st: brain ? brain.noteState : ({ fight: null })
    readonly property string dungeon: brain ? brain.shownDungeon : ""
    readonly property bool previewing: !!brain && brain.previewDungeon !== "" && !st.fight
    readonly property var dinfo: dungeon && brain ? brain.dungeons[dungeon] : null
    /// The boss tab picked by hand (else the one fought, else the first).
    property string picked: ""
    onDungeonChanged: picked = ""
    readonly property string bossKey: {
        if (st.fight) return st.fight.key
        if (previewing && brain.previewKey) return brain.previewKey
        if (picked) return picked
        if (dinfo) return brain.lastKey && brain.dungeons[dungeon].bosses.some((b) => b.key === brain.lastKey) ? brain.lastKey : dinfo.bosses[0].key
        return p.keep && brain ? brain.lastKey : ""
    }
    readonly property var sheet: brain && bossKey ? (brain.sheetsRevision, brain.sheet(bossKey)) : null
    readonly property bool cheat: !!dinfo && (p.inDungeon !== false || previewing)
    readonly property bool wanted: previewing || p.overlay !== false && !!brain
        && ((st.fight && (st.hasSheet || cheat)) || cheat || (p.keep && !!sheet && !!brain.lastKey))
    readonly property var mine: brain && dungeon ? brain.myRoles(dungeon) : []

    function forMe(e) { return !e.role || mine.length === 0 || mine.indexOf(e.role) >= 0 }
    /// The sheet's entries as shown: in a fight from its state (fired,
    /// current), else straight from the sheet.
    readonly property var rows: {
        if (!sheet) return []
        const cur = st.fight && st.phase ? st.phase.id : previewing ? brain.previewPhase : ""
        const list = st.fight && st.list ? st.list : (sheet.entries || []).map((e) => ({ id: e.id, kind: e.kind, name: e.name, text: e.text || "", role: e.role || "",
            when: brain.describe(e.when), fired: false }))
        return list.filter((e) => e.kind !== "alert" || !st.fight).map((e) => Object.assign({}, e, { current: e.id === cur, mine: forMe(e) }))
    }

    width: 400
    height: col.height + 2

    property bool placed: false
    function place() {
        if (placed || !parent || parent.width <= 0) return
        x = p.sheetX >= 0 ? p.sheetX : parent.width - width - 40
        y = p.sheetY >= 0 ? p.sheetY : 110
        x = Math.max(0, Math.min(x, parent.width - width))
        y = Math.max(0, Math.min(y, parent.height - 80))
        placed = true
    }
    Component.onCompleted: place()
    onParentChanged: place()

    Rectangle { anchors.fill: parent; color: Theme.panel(Companion.alpha) }
    Rectangle { width: parent.width; height: 2; color: Theme.accent }

    component Small: Text {
        color: Theme.dim()
        font.family: Theme.body
        font.pixelSize: 11
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }
    component Caps: Text {
        color: Theme.text()
        font.family: Theme.display
        font.weight: Font.Bold
        font.letterSpacing: 1.5
        elide: Text.ElideRight
        style: Theme.textStyle(); styleColor: Theme.shadow
    }

    Column {
        id: col
        y: 2
        width: parent.width

        // Head: dragged while unlocked.
        Item {
            width: parent.width
            height: 30
            MoveArea {
                anchors.fill: parent
                enabled: !Companion.locked
                target: ov
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onReleased: { ov.brain.change("sheetX", Math.round(ov.x)); ov.brain.change("sheetY", Math.round(ov.y)) }
            }
            Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                width: parent.width - 20
                Caps {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (ov.st.fight ? ov.st.fight.name : ov.previewing ? "Preview" : ov.cheat ? "Cheat sheet" : ov.brain ? ov.brain.bossName(ov.bossKey) : "").toUpperCase()
                    font.pixelSize: 13
                    width: Math.min(implicitWidth, parent.width - 120)
                }
                Small {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ov.dinfo ? ov.dinfo.name : ""
                    width: Math.min(implicitWidth, 150)
                }
            }
            IconButton {
                visible: ov.previewing
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                tip: "Close the preview"
                onClicked: ov.brain.stopPreview()
            }
            Caps {
                visible: !!ov.st.fight
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ov.st.fight ? Math.floor(ov.st.fight.elapsed / 60000) + ":" + String(Math.floor(ov.st.fight.elapsed / 1000) % 60).padStart(2, "0") : ""
                font.pixelSize: 13
            }
        }
        // HP.
        Item {
            visible: !!ov.st.fight && ov.st.fight.hp !== null
            width: parent.width
            height: visible ? 18 : 0
            Rectangle { x: 10; width: parent.width - 20; height: 14; color: Theme.trackDark }
            Rectangle { x: 10; width: (parent.width - 20) * Math.max(0, Math.min(1, (ov.st.fight ? ov.st.fight.hp || 0 : 0) / 100)); height: 14; color: Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.6) }
            Small { x: parent.width - 16 - width; y: 0; height: 14; verticalAlignment: Text.AlignVCenter; text: ov.st.fight ? Math.round(ov.st.fight.hp) + " %" : ""; color: Theme.text(); font.pixelSize: 10 }
        }
        // The dungeon's bosses as tabs.
        Row {
            visible: ov.cheat
            x: 10
            spacing: 14
            height: visible ? 28 : 0
            Repeater {
                model: ov.cheat ? ov.dinfo.bosses : []
                delegate: Item {
                    required property var modelData
                    readonly property bool current: ov.bossKey === modelData.key
                    width: tabText.implicitWidth
                    height: 28
                    Caps { id: tabText; anchors.verticalCenter: parent.verticalCenter; text: modelData.name.toUpperCase(); font.pixelSize: 11; color: parent.current ? Theme.accent : Theme.muted() }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                    MouseArea { anchors.fill: parent; enabled: !Companion.locked; cursorShape: Qt.PointingHandCursor; onClicked: { if (ov.previewing) { ov.brain.previewKey = modelData.key; ov.brain.previewPhase = "" } else ov.picked = modelData.key } }
                }
            }
        }
        // MY ROLE.
        Rectangle {
            visible: ov.cheat && ov.mine.length > 0
            x: 10
            width: parent.width - 20
            height: visible ? 26 : 0
            color: Qt.rgba(155 / 255, 107 / 255, 232 / 255, 0.16)
            Row {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Caps { anchors.verticalCenter: parent.verticalCenter; text: "MY ROLE"; font.pixelSize: 10; color: Theme.purpleText }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ov.mine.join(" · "); color: Theme.text(); font.family: Theme.body; font.pixelSize: 12; font.weight: Font.DemiBold; style: Theme.textStyle(); styleColor: Theme.shadow }
            }
        }
        Item { width: 1; height: 6 }
        // Alerts with their countdown.
        Repeater {
            model: ov.st.fight ? ov.st.alerts : []
            delegate: Item {
                required property var modelData
                width: col.width
                height: 32
                Rectangle {
                    x: 10; width: parent.width - 20; height: 28
                    color: Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.16)
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: "#e5484d" }
                    Text {
                        x: 22; width: parent.width - 70; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name + (modelData.text ? " · " + modelData.text : "")
                        color: Theme.text(); font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Caps { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Math.ceil(modelData.left / 1000) + " s"; font.pixelSize: 14; color: "#ff8a8e" }
                }
            }
        }
        // The sheet: the phase you are in big, the rest small.
        Repeater {
            model: ov.st.fight && !ov.cheat ? [] : ov.rows
            delegate: Item {
                required property var modelData
                width: col.width
                height: entry.height + 4
                opacity: modelData.mine ? 1 : 0.45
                Rectangle {
                    x: 10; width: parent.width - 20; height: entry.height
                    color: modelData.current ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.10) : "#1b1a20"
                    Rectangle { visible: modelData.current; width: 3; height: parent.height; color: Theme.accent }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: ov.previewing && !Companion.locked
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { const e = (ov.sheet.entries || []).find((x) => x.id === modelData.id); if (e) ov.brain.playEntry(ov.bossKey, e) }
                }
                Column {
                    id: entry
                    x: 20
                    width: parent.width - 40
                    topPadding: 5
                    bottomPadding: 6
                    spacing: 2
                    Row {
                        spacing: 6
                        Caps { text: modelData.name; font.pixelSize: modelData.current ? 20 : 13; color: modelData.current ? Theme.accent : Theme.text(); font.letterSpacing: 1 }
                        Small { anchors.baseline: parent.children[0].baseline; text: modelData.when + (modelData.role ? " · " + modelData.role : "") }
                    }
                    Text {
                        visible: text.length > 0
                        width: parent.width
                        text: modelData.text
                        wrapMode: Text.WordWrap
                        color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 12
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                }
            }
        }
        // In a plain fight: the phase and what comes next.
        Item {
            visible: !!ov.st.fight && !ov.cheat && !!ov.st.phase
            width: parent.width
            height: visible ? phaseCol.height + 6 : 0
            Rectangle { x: 10; width: parent.width - 20; height: phaseCol.height; color: Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.08) }
            Column {
                id: phaseCol
                x: 18
                width: parent.width - 36
                topPadding: 4
                bottomPadding: 6
                spacing: 2
                Caps { text: "PHASE"; font.pixelSize: 10; color: Theme.dim() }
                Caps { text: ov.st.phase ? ov.st.phase.name : ""; font.pixelSize: 20; color: Theme.accent; width: parent.width }
                Text {
                    visible: text.length > 0; width: parent.width; wrapMode: Text.WordWrap
                    text: ov.st.phase ? ov.st.phase.text : ""
                    color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 12; style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }
        Text {
            visible: !!ov.st.fight && !ov.cheat && !!ov.st.next && ov.p.showNext !== false
            x: 10; width: parent.width - 20
            height: visible ? implicitHeight + 6 : 0
            textFormat: Text.StyledText
            text: ov.st.next ? "<font color='" + Theme.dim() + "'>NEXT</font>  " + ov.st.next.when + " · <b>" + ov.st.next.name + "</b>" : ""
            color: Theme.muted(); font.family: Theme.body; font.pixelSize: 12; elide: Text.ElideRight
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Text {
            readonly property string notes: ov.cheat && ov.dinfo && !(ov.sheet && ov.sheet.notes) ? ov.dinfo.notes : (ov.sheet ? ov.sheet.notes || "" : "")
            visible: notes.length > 0 && ov.p.showNotes !== false
            x: 10; width: parent.width - 20
            topPadding: 4
            bottomPadding: 8
            wrapMode: Text.WordWrap
            text: "Notes: " + notes
            color: Theme.dim(); font.family: Theme.body; font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
}
