import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// GOALS: a gear score to reach (the build's goal, so its progress counts
// it) and the cheapest way there: enhancing what you wear, or changing
// pieces first (each slot's target in GEAR), with Kinah, materials at
// market prices and the steps cheapest per point first. Improved: the goal
// belongs to the build, the combat power it means beside it, the plan only
// counted again when something it depends on changes.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var targets: ui ? ui.targets : BK.emptyTargets()
    readonly property var prices: ui && ui.store ? ui.store.prices : null
    spacing: 10

    readonly property int current: snap ? BK.gsOf(snap) : 0
    readonly property int cp: snap && snap.profile ? snap.profile.cp || 0 : 0
    readonly property var rate: { if (!ui) return { rate: 0, own: false }; ui.rev; return ck.cpPerGearScore(ui.store.history) }
    readonly property int goal: {
        if (!ui) return 0
        ui.rev
        const g = build ? targets.goalGs : ui.store.state.settings.goalGs
        if (g > 0) return g
        const refGs = build && build.ref ? build.ref.gearScore : 0
        return refGs && refGs > current ? refGs : current + 50
    }
    readonly property bool swapsOn: { if (!ui) return true; ui.rev; return ui.store.state.settings.goalSwaps !== false }
    function setGoal(v) {
        v = Math.max(0, Math.round(v))
        if (build) ui.store.changeTargets("goal gear score", (t) => { t.goalGs = v })
        else { ui.store.state.settings.goalGs = v; ui.store.changed() }
    }

    readonly property var skip: Object.keys(targets.skip || {})
    // Each slot's target where it is another item (GEAR's targets).
    readonly property var options: {
        if (!ui || !snap) return []
        ui.rev
        return BK.gearRows(snap, build, targets, prices).filter((r) => r.target && !r.skipped && !/^Arcana/.test(r.slot) && r.target.piece.id && !(r.mine && (r.mine.id === r.target.piece.id || r.mine.name === r.target.piece.name)))
            .map((r) => ({ slot: r.slot, item: r.target.piece, from: r.target.from }))
    }
    // The plan with changed pieces takes a moment: kept while nothing it
    // depends on changes (changed in place, so no binding follows it).
    readonly property var memo: ({ key: "", plain: null, plan: null })
    readonly property var plans: {
        if (!ui || !snap) return null
        ui.rev
        const only = new Set((snap.items || []).filter((it) => !it.arcana && skip.indexOf(it.slot) < 0).map((it) => it.slot))
        const useSwaps = swapsOn && options.length > 0
        const key = JSON.stringify([current, goal, snap.at, prices ? prices.size : 0, useSwaps, options.map((o) => [o.slot, o.item.id, o.item.enchant, o.item.amplify]), skip])
        if (memo.key === key) return { plain: memo.plain, plan: memo.plan }
        const plain = ck.planGearScore(snap, current, goal, prices, only)
        const plan = useSwaps ? ck.planWithSwaps(snap, current, goal, prices, options, new Set(skip)) : Object.assign({}, plain, { swaps: [] })
        memo.key = key
        memo.plain = plain
        memo.plan = plan
        return { plain: plain, plan: plan }
    }
    readonly property var plan: plans ? plans.plan : null
    readonly property int need: Math.max(0, goal - current)
    function ceilMats(m) { const o = {}; for (const k in m) o[k] = Math.ceil(m[k]); return o }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }

    // ---- the goal ----
    AUi.Box {
        visible: !!tab.snap
        width: parent.width
        Row {
            spacing: 10
            AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: tab.build ? "Goal of " + tab.build.name + ": gear score" : "Target gear score"; color: Theme.muted() }
            AUi.Field {
                id: gsField
                width: 80
                anchors.verticalCenter: parent.verticalCenter
                text: String(tab.goal)
                input.validator: IntValidator { bottom: 0; top: 99999 }
                onAccepted: tab.setGoal(Number(text))
            }
            AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: "or combat power ≈"; color: Theme.muted() }
            AUi.Field {
                width: 96
                anchors.verticalCenter: parent.verticalCenter
                text: String(Math.round(tab.cp + (tab.goal - tab.current) * tab.rate.rate))
                input.validator: IntValidator { bottom: 0; top: 99999999 }
                onAccepted: tab.setGoal(tab.current + (Number(text) - tab.cp) / Math.max(1, tab.rate.rate))
            }
            Chip {
                visible: !!tab.build && !!tab.build.ref && tab.build.ref.gearScore > 0
                text: "The build's gear " + (tab.build && tab.build.ref ? tab.ui.fmt(tab.build.ref.gearScore) : "")
                onClicked: tab.setGoal(tab.build.ref.gearScore)
            }
            Chip { text: "+50"; onClicked: tab.setGoal(tab.current + 50) }
            Chip { text: "+100"; onClicked: tab.setGoal(tab.current + 100) }
        }
        AUi.Note {
            width: parent.width
            text: "Enter to take a number. " + (tab.rate.own ? "Combat power from your own history: " + tab.ui.fmt(tab.rate.rate) + " a gear score point." : "About " + tab.rate.rate + " combat power a gear score point (24 characters, 2026-10-28) until your own history says better.")
                + (tab.build ? " The goal is the build's: its progress counts it from where this character stood when the build came." : "")
        }
        Row {
            spacing: 8
            AUi.Tick { anchors.verticalCenter: parent.verticalCenter; on: tab.swapsOn; onToggled: { tab.ui.store.state.settings.goalSwaps = !tab.swapsOn; tab.ui.store.changed() } }
            AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: "Count changing pieces: each slot's target in GEAR (the build's piece, or what you picked in Compare)"; font.pixelSize: 11 }
        }
        AUi.Line {
            visible: tab.skip.length > 0
            width: parent.width
            text: "Left out (unticked in GEAR): " + tab.skip.map((s) => tab.ui.label(s)).join(", ")
            color: Theme.dim()
            font.pixelSize: 11
        }
    }

    // ---- the plan ----
    AUi.Box {
        visible: !!tab.plan
        width: parent.width
        AUi.Title {
            width: parent.width
            text: {
                const p = tab.plan
                if (!p) return ""
                const how = p.swaps.length ? "by changing " + p.swaps.length + " piece" + (p.swaps.length === 1 ? "" : "s") + " and enhancing" : "by enhancing what you wear"
                if (tab.need === 0) return "You are at " + tab.ui.fmt(tab.current) + ": the goal is reached."
                return p.reached ? tab.ui.fmt(tab.current) + " → " + tab.ui.fmt(p.gs) + " " + how : tab.ui.fmt(tab.current) + " → " + tab.ui.fmt(p.gs) + " at most " + (p.swaps.length ? "with the pieces counted" : "with what you wear")
            }
            color: tab.need === 0 ? "#7fdc9a" : Theme.text()
        }
        AUi.Line {
            visible: tab.need > 0
            width: parent.width
            text: tab.plan ? tab.ui.plusMinus(tab.plan.total.gain) + " gear score · combat power ≈ " + tab.ui.plusMinus(Math.round(tab.plan.total.gain * tab.rate.rate)) : ""
            color: Theme.muted()
        }
        AUi.Line {
            visible: tab.need > 0 && !!tab.plan && tab.plan.swaps.length > 0
            width: parent.width
            text: tab.plans && tab.plans.plain ? "Enhancing only: " + (tab.plans.plain.reached ? tab.ui.brief(tab.plans.plain.total.worth.total) + " Kinah" : tab.ui.fmt(tab.plans.plain.gs) + " at most") + "; with the changes: " + tab.ui.brief(tab.plan.total.worth.total) + " Kinah." : ""
            color: Theme.muted()
            font.pixelSize: 11
        }
        AUi.Line {
            visible: tab.need > 0 && !!tab.plan && !tab.plan.reached
            width: parent.width
            text: tab.plan ? "The last " + tab.ui.fmt(tab.goal - tab.plan.gs) + " need better pieces (or the free points below): your gear has " + tab.ui.fmt(tab.ck.gearRoom(tab.snap)) + " points of room left." : ""
            color: Theme.accentLight
            font.pixelSize: 11
        }
        // Totals.
        Flow {
            visible: !!tab.plan && (tab.plan.pieces.length > 0 || tab.plan.swaps.length > 0)
            width: parent.width
            spacing: 18
            Column {
                AUi.Head { text: "KINAH ⌀" }
                AUi.Figure { text: tab.plan ? tab.ui.brief(tab.plan.total.kinah) : "" }
            }
            Column {
                AUi.Head { text: "9 TIMES IN 10" }
                AUi.Figure { text: tab.plan ? tab.ui.brief(tab.plan.total.kinahP90) : "" }
            }
            Repeater {
                model: tab.plan ? Object.keys(tab.plan.total.mats).sort((a, b) => tab.plan.total.mats[b] - tab.plan.total.mats[a]) : []
                delegate: Column {
                    required property string modelData
                    readonly property var m: tab.ck.material(modelData)
                    readonly property var price: tab.ck.materialPrice(modelData, tab.prices)
                    AUi.Head { text: m.name.replace(/ \(Bound\)$/, "").toUpperCase() }
                    AUi.Figure { text: tab.ui.fmt(Math.ceil(tab.plan.total.mats[modelData])) }
                    AUi.Line { text: parent.price ? "≈ " + tab.ui.brief(tab.plan.total.mats[modelData] * parent.price) + " at " + tab.ui.fmt(parent.price) : parent.m.bound ? "bound" : "no price"; color: Theme.dim(); font.pixelSize: 10 }
                }
            }
            Column {
                AUi.Head { text: "ALL IN KINAH" }
                AUi.Figure { text: tab.plan ? tab.ui.brief(tab.plan.total.worth.total) : ""; color: Theme.accent }
                AUi.Line { text: tab.plan && Object.keys(tab.plan.total.worth.unpriced).length ? "priced ones; the rest by count" : "at market prices"; color: Theme.dim(); font.pixelSize: 10 }
            }
        }
    }

    // ---- the steps ----
    AUi.Head { visible: !!tab.plan && (tab.plan.pieces.length > 0 || tab.plan.swaps.length > 0); text: "STEPS, CHEAPEST PER POINT FIRST" }
    Repeater {
        model: tab.plan ? tab.plan.swaps.map((o) => ({ swap: true, o: o })).concat(tab.plan.pieces.map((p) => ({ swap: false, o: p }))) : []
        delegate: Rectangle {
            required property var modelData
            readonly property var o: modelData.o
            readonly property var it: modelData.o.item
            width: tab.width
            height: 40
            color: modelData.swap ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.07) : "#1b1a20"
            Row {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                AUi.Icon { anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; icon: it.icon || ""; grade: it.grade; rev: tab.ui.iconRev }
                Column {
                    width: 230
                    anchors.verticalCenter: parent.verticalCenter
                    AUi.Line { width: parent.width; text: it.name; color: tab.ui.gradeColour(it.grade); font.pixelSize: 11 }
                    AUi.Line { visible: modelData.swap; width: parent.width; text: modelData.swap ? tab.ui.label(o.slot) + ": for " + (o.mine ? o.mine.name : "nothing worn") : ""; color: Theme.dim(); font.pixelSize: 10 }
                }
                Column {
                    width: 170
                    anchors.verticalCenter: parent.verticalCenter
                    AUi.Line { text: modelData.swap ? "Change, +0 → " + tab.ui.levelText(o.up.to) : o.kind === "enchant" ? "+" + o.from + " → +" + o.to : "Amplify " + o.from + " → " + o.to; font.pixelSize: 11 }
                    AUi.Line { visible: modelData.swap; text: modelData.swap ? (o.from === "reference" ? "the build's" : "your pick") + " · at +0: " + tab.ui.plusMinus(o.up.at0) : ""; color: Theme.dim(); font.pixelSize: 10 }
                }
                AUi.Line { width: 50; anchors.verticalCenter: parent.verticalCenter; text: "+" + (modelData.swap ? o.up.gain : o.gain); color: Theme.accent; font.bold: true; font.pixelSize: 11 }
                AUi.Line { width: 64; anchors.verticalCenter: parent.verticalCenter; text: tab.ui.brief(modelData.swap ? o.up.cost.kinah : o.kinah); font.pixelSize: 11 }
                AUi.Line { width: 64; anchors.verticalCenter: parent.verticalCenter; text: tab.ui.brief(modelData.swap ? o.up.cost.kinahP90 : o.kinahP90); color: Theme.dim(); font.pixelSize: 11 }
                AUi.Line {
                    width: tab.width - 8 - 28 - 230 - 170 - 50 - 64 - 64 - 7 * 8 - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.ui.matsText(tab.ceilMats(modelData.swap ? o.up.cost.mats : o.mats))
                    color: Theme.dim()
                    font.pixelSize: 10
                }
            }
        }
    }
    AUi.Note {
        visible: !!tab.plan && (tab.plan.pieces.length > 0 || tab.plan.swaps.length > 0)
        width: parent.width
        text: "Columns: gear score, Kinah on average, Kinah 9 times in 10, materials on average. From the game's enhance tables: each try's chance, the chance a failure adds, Kinah and materials a try. Enhancement Supplements are not counted. Amplify starts once a piece is at its enhance top."
            + (tab.plan && tab.plan.swaps.length ? " A changed piece counts its enhancing from +0, not the item itself; Manastones stay on the old piece." : "")
    }

    // ---- free points ----
    AUi.Box {
        visible: !!tab.snap
        width: parent.width
        readonly property int daev: tab.snap ? (tab.snap.boards || []).reduce((a, b) => a + Math.max(0, (b.maxPoints || 0) - (b.points || 0)), 0) : 0
        readonly property int empty: tab.snap ? (tab.snap.items || []).reduce((a, it) => a + Math.max(0, (it.stoneSlots || 0) - (it.stones || []).length), 0) : 0
        AUi.Title { text: "Other ways to gear score" }
        Item {
            width: parent.width
            height: 18
            AUi.Line { text: "Daevanion points still open (1 each)"; font.pixelSize: 11 }
            AUi.Line { anchors.right: parent.right; text: "+" + tab.ui.fmt(parent.parent.parent.daev); font.bold: true; font.pixelSize: 11 }
        }
        Item {
            width: parent.width
            height: 18
            AUi.Line { text: "Empty Manastone slots (1 to 4 each, by grade)"; font.pixelSize: 11 }
            AUi.Line { anchors.right: parent.right; readonly property int e: parent.parent.parent.empty; text: e ? "+" + e + " to +" + e * 4 : "none"; font.bold: true; font.pixelSize: 11 }
        }
    }
}
