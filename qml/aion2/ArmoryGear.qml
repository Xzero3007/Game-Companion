import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// GEAR (board AR2): the old Gear and Reference tabs in one. Each slot in a
// row: yours, the build's target, what the upgrade gives and costs, a tick
// to count it (unticked slots are left out of the build's progress, its
// steps and Goals), and its details: the piece's stats, stones and next
// enhance step, then Compare (your piece enhanced on, the build's piece at
// the levels you set, any item by name; "Use" makes one the slot's target
// in the build). On top the calculator's sums for the ticked upgrades.
Column {
    id: tab
    property var ui
    readonly property var me: tab
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var targets: ui ? ui.targets : BK.emptyTargets()
    readonly property var prices: ui && ui.store ? ui.store.prices : null
    readonly property real rate: { if (!ui) return 0; ui.rev; return tab.ck.cpPerGearScore(ui.store.history).rate }
    /// The slots opened, several at once (MN, 2026-11-14): { slot: true }.
    property var opened: ({})
    function toggle(slot) { const o = Object.assign({}, opened); if (o[slot]) delete o[slot]; else o[slot] = true; opened = o }
    Component.onCompleted: if (ui && ui.store.demo && ui.store.demoList.indexOf("compare") >= 0) opened = { MainHand: true, Helmet: true }
    onUiChanged: if (ui && ui.store.demo && ui.store.demoList.indexOf("compare") >= 0) opened = { MainHand: true, Helmet: true }
    spacing: 8

    readonly property var groups: [["Weapons", ["MainHand", "SubHand"]], ["Armor", ["Helmet", "Shoulder", "Torso", "Pants", "Gloves", "Boots", "Cape", "Belt"]],
        ["Accessories", ["Necklace", "Earring1", "Earring2", "Ring1", "Ring2", "Bracelet1", "Bracelet2", "Amulet", "Rune1", "Rune2"]],
        ["Arcana", ["Arcana1", "Arcana2", "Arcana3", "Arcana4", "Arcana5"]]]
    readonly property var catsOfSlot: ({
        MainHand: ["Greatsword", "Longsword", "Dagger", "Bow", "Spellbook", "Orb", "Mace", "Staff"], SubHand: ["Guard"],
        Helmet: ["Helm"], Shoulder: ["Pauldrons"], Torso: ["Top"], Pants: ["Legs"], Gloves: ["Gloves"], Boots: ["Shoes"], Cape: ["Cloak"],
        Belt: ["Belt"], Necklace: ["Necklace"], Earring1: ["Earrings"], Earring2: ["Earrings"], Ring1: ["Ring"], Ring2: ["Ring"],
        Bracelet1: ["Bracelet"], Bracelet2: ["Bracelet"], Amulet: ["Amulet"], Rune1: ["Rune"], Rune2: ["Rune"] })

    readonly property var rows: { if (!ui) return []; ui.rev; return snap ? BK.gearRows(snap, build, targets, prices) : [] }
    readonly property var sum: {
        const all = rows.filter((r) => r.target && r.up && r.up.gain > 0)
        const on = all.filter((r) => !r.skipped)
        const s = { all: all.length, on: on.length, gain: 0, kinah: 0, p90: 0, mats: {}, unknown: false, reached: rows.filter((r) => r.target && !r.skipped && r.reached).length, aimed: rows.filter((r) => r.target && !r.skipped).length }
        for (const r of on) {
            s.gain += r.up.gain
            if (!r.up.cost.known) { s.unknown = true; continue }
            s.kinah += r.up.cost.kinah
            s.p90 += r.up.cost.kinahP90
            for (const m in r.up.cost.mats) s.mats[m] = (s.mats[m] || 0) + r.up.cost.mats[m]
        }
        return s
    }
    function rowsOf(slots) { return rows.filter((r) => slots.indexOf(r.slot) >= 0).sort((a, b) => slots.indexOf(a.slot) - slots.indexOf(b.slot)) }
    readonly property var rest: rows.filter((r) => !groups.some((g) => g[1].indexOf(r.slot) >= 0))
    function tick(slots, on) { ui.store.changeTargets("slots counted", (t) => { for (const sl of slots) { if (on) delete t.skip[sl]; else t.skip[sl] = true } }) }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }

    // ---- the calculator's sums ----
    AUi.Box {
        visible: !!tab.snap
        width: parent.width
        Item {
            width: parent.width
            height: 22
            AUi.Title {
                anchors.verticalCenter: parent.verticalCenter
                text: tab.build ? "Against " + tab.build.name + ": " + tab.sum.reached + " of " + tab.sum.aimed + " slots at target" : "Your gear"
            }
            Row {
                anchors.right: parent.right
                spacing: 6
                visible: tab.sum.all > 0
                Chip { text: "Count all"; onClicked: tab.tick(tab.rows.filter((r) => r.target && r.up && r.up.gain > 0).map((r) => r.slot), true) }
                Chip { text: "None"; onClicked: tab.tick(tab.rows.filter((r) => r.target && r.up && r.up.gain > 0).map((r) => r.slot), false) }
            }
        }
        Row {
            visible: tab.sum.all > 0
            spacing: 18
            Column {
                AUi.Head { text: "UPGRADES COUNTED" }
                AUi.Figure { text: tab.sum.on + " of " + tab.sum.all }
            }
            Column {
                AUi.Head { text: "GEAR SCORE" }
                AUi.Figure { text: "+" + tab.sum.gain + "  (" + tab.ui.fmt(BK.gsOf(tab.snap)) + " → " + tab.ui.fmt(BK.gsOf(tab.snap) + tab.sum.gain) + ")"; color: Theme.accent }
            }
            Column {
                AUi.Head { text: "KINAH ⌀ / 9 IN 10" }
                AUi.Figure { text: tab.ui.brief(tab.sum.kinah) + " / " + tab.ui.brief(tab.sum.p90) }
            }
            Column {
                AUi.Head { text: "≈ COMBAT POWER" }
                AUi.Figure { text: tab.ui.plusMinus(Math.round(tab.sum.gain * tab.rate)) }
            }
        }
        AUi.Note {
            width: parent.width
            text: tab.sum.all === 0
                ? (tab.build ? "Nothing to upgrade to: every slot is at its target." : "Without a build each piece shows itself and its next enhance step. With a build (BUILDS), each slot shows its target and what it takes.")
                : "Materials on average: " + tab.ui.matsText(tab.sum.mats) + "." + (tab.sum.unknown ? ". Arcana: their enhancing isn't in the data (not in the Kinah)." : "")
                  + " Tick what you mean to do: unticked slots are left out of the progress, the steps and Goals."
        }
    }

    // ---- the slots ----
    Repeater {
        model: tab.snap ? tab.groups.concat(tab.rest.length ? [["Other", tab.rest.map((r) => r.slot)]] : []) : []
        delegate: Column {
            required property var modelData
            readonly property var list: tab.rowsOf(modelData[1])
            visible: list.length > 0
            width: tab.width
            spacing: 4
            AUi.Head { text: modelData[0].toUpperCase(); topPadding: 4 }
            Repeater {
                model: parent.list
                delegate: Column {
                    id: slotRow
                    required property var modelData
                    readonly property var r: modelData
                    readonly property bool expanded: !!tab.opened[r.slot]
                    width: tab.width
                    spacing: 0
                    Rectangle {
                        width: parent.width
                        height: 44
                        color: slotRow.expanded ? "#24222a" : (rowMouse.containsMouse ? "#201f25" : "#1b1a20")
                        opacity: slotRow.r.skipped ? 0.55 : 1
                        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.toggle(slotRow.r.slot) }
                        AUi.Tick {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!slotRow.r.target
                            on: !slotRow.r.skipped
                            onToggled: tab.tick([slotRow.r.slot], slotRow.r.skipped)
                        }
                        AUi.Line { x: 30; anchors.verticalCenter: parent.verticalCenter; width: 72; text: tab.ui.label(slotRow.r.slot); color: Theme.muted(); font.pixelSize: 11 }
                        // Yours.
                        Row {
                            x: 104
                            width: (parent.width - 104 - 210) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            AUi.Icon { visible: !!slotRow.r.mine; icon: slotRow.r.mine ? slotRow.r.mine.icon || "" : ""; grade: slotRow.r.mine ? slotRow.r.mine.grade : ""; rev: tab.ui.iconRev }
                            Column {
                                width: parent.width - 40
                                AUi.Line { width: parent.width; text: slotRow.r.mine ? slotRow.r.mine.name : "—"; color: slotRow.r.mine ? tab.ui.gradeColour(slotRow.r.mine.grade) : Theme.dim() }
                                AUi.Line { visible: !!slotRow.r.mine; text: slotRow.r.mine ? tab.ui.levelText(slotRow.r.mine) + (slotRow.r.mine.il ? " · IL " + slotRow.r.mine.il : "") : ""; color: Theme.dim(); font.pixelSize: 11 }
                            }
                        }
                        // The target.
                        Row {
                            x: 104 + (parent.width - 104 - 210) / 2 + 6
                            width: (parent.width - 104 - 210) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            readonly property var p: slotRow.r.target ? slotRow.r.target.piece : null
                            AUi.Icon { visible: !!parent.p; icon: parent.p ? parent.p.icon || "" : ""; grade: parent.p ? parent.p.grade : ""; rev: tab.ui.iconRev }
                            Column {
                                width: parent.width - 40
                                AUi.Line {
                                    width: parent.width
                                    text: parent.parent.p ? (slotRow.r.up && slotRow.r.up.same ? "same item" : parent.parent.p.name) : (tab.build ? "the build has none" : "")
                                    color: parent.parent.p && !(slotRow.r.up && slotRow.r.up.same) ? tab.ui.gradeColour(parent.parent.p.grade) : Theme.dim()
                                }
                                AUi.Line {
                                    visible: !!parent.parent.p
                                    width: parent.width
                                    text: parent.parent.p ? "→ " + tab.ui.levelText(parent.parent.p) + " · " + (slotRow.r.target.from === "reference" ? "the build's" : slotRow.r.target.from === "yours" ? "yours enhanced on" : "compared, your pick") : ""
                                    color: slotRow.r.target && slotRow.r.target.from !== "reference" ? Theme.accentLight : Theme.dim()
                                    font.pixelSize: 11
                                }
                            }
                        }
                        // What it gives and costs.
                        Column {
                            x: parent.width - 206
                            width: 110
                            anchors.verticalCenter: parent.verticalCenter
                            AUi.Line {
                                text: slotRow.r.reached ? "✓ at target" : slotRow.r.up && slotRow.r.up.gain ? tab.ui.plusMinus(slotRow.r.up.gain) + " GS" : ""
                                color: slotRow.r.reached ? "#7fdc9a" : slotRow.r.up && slotRow.r.up.gain > 0 ? Theme.accent : "#ff8a7a"
                                font.bold: true
                            }
                            AUi.Line {
                                visible: !!slotRow.r.up && slotRow.r.up.gain > 0
                                text: slotRow.r.up ? (slotRow.r.up.cost.known ? "≈ " + tab.ui.brief(slotRow.r.up.cost.kinah) + " Kinah" : "cost ?") : ""
                                color: Theme.dim()
                                font.pixelSize: 11
                            }
                        }
                        AUi.Line {
                            x: parent.width - 94
                            width: 66
                            anchors.verticalCenter: parent.verticalCenter
                            text: slotRow.r.skipped ? "left out" : ({ done: "", levels: slotRow.r.levelsToGo + " level" + (slotRow.r.levelsToGo === 1 ? "" : "s"), other: "other item", missing: "not worn", none: "" })[slotRow.r.status] || ""
                            color: Theme.dim()
                            font.pixelSize: 11
                        }
                        AUi.Line {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: slotRow.expanded ? "▴" : ((tab.targets.compare[slotRow.r.slot] || []).length ? "▾ " + tab.targets.compare[slotRow.r.slot].length : "▾")
                            color: Theme.accent
                        }
                    }
                    // Its height follows the details and is 0 when closed: a
                    // Loader keeps the last item's height otherwise (MN saw
                    // an empty gap under closed rows).
                    Loader {
                        active: slotRow.expanded && !!tab.ck
                        width: parent.width
                        height: active && item ? item.implicitHeight : 0
                        sourceComponent: Component { ArmoryGearDetails { tab: me; r: slotRow.r } }
                    }
                }
            }
        }
    }

    AUi.Note {
        visible: !!tab.snap
        width: parent.width
        text: "Gear score by item level, enhance level and 5 an Amplify level; Manastones and Theostones stay on the old piece and are not counted. Kinah: the enhancing, from +0 for another item (the item itself not counted), from your levels for yours and the same item. Chances and costs are the game's enhance tables."
    }
}
