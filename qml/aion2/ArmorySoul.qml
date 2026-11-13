import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// SOUL BINDING: what each piece's soul binding has and the properties the
// build wants on it (the old tab's wishes, now kept in the build, so a
// second character on the same build wants the same). Improved: the
// pieces in two columns, the build's progress on top, the chance of a new
// binding beside the misses, "Pick …" folds the list of what the piece can
// get open in place.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var targets: ui ? ui.targets : BK.emptyTargets()
    property string open: ""
    Component.onCompleted: if (ui && ui.store.demo && ui.store.demoList.indexOf("pick") >= 0) open = "MainHand"
    onUiChanged: if (ui && ui.store.demo && ui.store.demoList.indexOf("pick") >= 0) open = "MainHand"
    property bool clearArmed: false
    spacing: 8

    readonly property var sp: { if (!ui) return null; ui.rev; return snap ? BK.soulPieces(snap, build) : null }
    readonly property var refSoul: { if (!ui) return ({}); ui.rev; const al = snap && build ? BK.aligned(snap, build.ref) : null; return (al && al.soul) || {} }
    readonly property var topInfo: sp ? ck.topOf(sp.cls) : null
    readonly property var count: {
        let n = 0, hits = 0
        if (sp) for (const x of sp.out) { const w = ck.soulCompare(x.it, targets.soul[x.slot], x.pool).wanted; n += w.length; hits += w.filter((y) => y.have).length }
        return { n: n, hits: hits }
    }
    property var chances: ({})
    function chanceOf(pool, id, wanted) {
        if (!pool || !wanted || !wanted.length) return null
        const key = id + "|" + pool.count + "|" + wanted.join("|")
        if (!(key in chances)) chances[key] = ck.soulChance(pool, wanted)
        return chances[key]
    }
    function rangeText(o) { return o.kind === "skill" ? (o.top > 1 ? "+1 to +" + o.top : "+1") : ui.fmt(o.min, 2) + "–" + ui.fmt(o.max, 2) + (o.pct ? " %" : "") }
    function shareOf(x) {
        const t = ck.topSlot(sp.cls, x.slot, x.it.arcana ? x.it.category : null)
        const m = {}
        for (const p of ((t && t.stats) || []).concat((t && t.skills) || [])) m[p[0].toLowerCase()] = p[1]
        return m
    }
    /// The build's properties a piece's binding can give, as many as it takes.
    function refPicks(x) {
        const props = refSoul[x.slot] || []
        if (!props.length || !x.pool) return []
        const can = {}
        for (const p of x.pool.stats.concat(x.pool.skills)) can[p.name.toLowerCase()] = true
        const share = shareOf(x)
        return props.map((p) => p.name).filter((n, i, a) => can[n.toLowerCase()] && a.indexOf(n) === i)
            .sort((a, b) => (share[b.toLowerCase()] || 0) - (share[a.toLowerCase()] || 0)).slice(0, x.pool.count)
    }
    function setWanted(slot, list) {
        ui.store.changeTargets(ui.label(slot) + " soul binding", (t) => { if (list && list.length) t.soul[slot] = list; else delete t.soul[slot] })
    }
    function fillAll(f, what) {
        ui.store.changeTargets(what, (t) => { for (const x of sp.out) { if ((t.soul[x.slot] || []).length) continue; const p = f(x); if (p.length) t.soul[x.slot] = p } })
    }
    Timer { id: disarm; interval: 3000; onTriggered: tab.clearArmed = false }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }
    AUi.Note {
        visible: !!tab.snap && !tab.build
        width: parent.width
        text: "The properties you want on a piece belong to a build: make or pick one in BUILDS, then pick them here."
    }

    Item {
        visible: !!tab.snap && !!tab.build
        width: parent.width
        height: 26
        AUi.Title {
            anchors.verticalCenter: parent.verticalCenter
            text: tab.count.n ? tab.count.hits + " of " + tab.count.n + " wanted properties are on your pieces" : "No properties picked yet"
            color: tab.count.n && tab.count.hits === tab.count.n ? "#7fdc9a" : Theme.text()
        }
        Row {
            anchors.right: parent.right
            spacing: 6
            Chip { visible: !!tab.topInfo; text: "Top players' picks where none"; onClicked: tab.fillAll((x) => tab.ck.topPicks(tab.sp.cls, x.slot, x.pool, x.it.arcana ? x.it.category : null), "soul bindings from the strongest players") }
            Chip { visible: Object.keys(tab.refSoul).length > 0; text: "The build's where none"; onClicked: tab.fillAll((x) => tab.refPicks(x), "soul bindings from the build's gear") }
            Chip {
                visible: tab.count.n > 0
                text: tab.clearArmed ? "Press again to clear all" : "Clear all"
                on: tab.clearArmed
                onClicked: {
                    if (!tab.clearArmed) { tab.clearArmed = true; disarm.restart(); return }
                    tab.clearArmed = false
                    tab.ui.store.changeTargets("soul bindings cleared", (t) => { t.soul = {} })
                }
            }
        }
    }
    AUi.Note {
        visible: !!tab.snap
        width: parent.width
        text: "A new binding picks its properties one after another, never one twice: the stats share 80 % of each pick by their weights, your class's skill effects 20 %. "
            + (tab.topInfo ? "“top”: how many of the " + tab.topInfo.n + " strongest " + tab.sp.cls + "s (Shugo.GG's Global leaderboard, " + tab.ui.brief(tab.topInfo.cp[0]) + " to " + tab.ui.brief(tab.topInfo.cp[2]) + " combat power) have it on that piece." : "No strongest players counted for this class yet.")
    }

    Flow {
        visible: !!tab.sp
        width: parent.width
        spacing: 10
        Repeater {
            model: tab.sp ? tab.sp.out : []
            delegate: AUi.Box {
                id: card
                required property var modelData
                readonly property var x0: modelData
                readonly property var wanted: { tab.ui.rev; return tab.targets.soul[x0.slot] || [] }
                readonly property var cmp: tab.ck.soulCompare(x0.it, wanted, x0.pool)
                readonly property var share: tab.shareOf(x0)
                readonly property bool opened: tab.open === x0.slot
                readonly property var p: wanted.length && cmp.wanted.some((w) => !w.have) ? tab.chanceOf(x0.pool, x0.own ? x0.it.id : x0.ref.id, wanted) : null
                readonly property var refProps: tab.refSoul[x0.slot] || []
                width: opened ? tab.width : (tab.width - 10) / 2
                Row {
                    width: parent.width
                    spacing: 8
                    AUi.Icon { icon: card.x0.it.icon || ""; grade: card.x0.it.grade; rev: tab.ui.iconRev }
                    Column {
                        width: parent.width - 40 - pickChip.width - 16
                        AUi.Line { width: parent.width; text: card.x0.it.name; color: tab.ui.gradeColour(card.x0.it.grade) }
                        AUi.Line {
                            width: parent.width
                            text: tab.ui.label(card.x0.slot) + " · " + card.x0.pool.count + " properties" + (card.x0.own ? "" : " on the build's " + card.x0.ref.name)
                                + (card.x0.own && card.x0.ref && card.x0.refPool && (card.x0.ref.name !== card.x0.it.name || card.x0.refPool.count !== card.x0.pool.count) ? " · the build's: " + card.x0.ref.name + " (" + card.x0.refPool.count + ")" : "")
                            color: Theme.dim()
                            font.pixelSize: 11
                        }
                    }
                    Chip { id: pickChip; visible: !!tab.build; text: card.opened ? "Done" : "Pick …"; on: card.opened; onClicked: tab.open = card.opened ? "" : card.x0.slot }
                }
                // Wanted ones first (✓ on it, ✗ not, ! the piece can't get it), then the rest it has.
                Repeater {
                    model: card.cmp.wanted.map((w) => ({ w: w, wanted: true })).concat(card.cmp.extra.map((h) => ({ w: h, wanted: false })))
                    delegate: Row {
                        required property var modelData
                        readonly property var w: modelData.w
                        width: card.width - 20
                        spacing: 6
                        AUi.Line {
                            width: 14
                            text: modelData.wanted ? (w.have ? "✓" : w.prop ? "✗" : "!") : "·"
                            color: modelData.wanted ? (w.have ? "#7fdc9a" : "#ff8a7a") : Theme.dim()
                            font.bold: true
                        }
                        AUi.Line { width: parent.width - 14 - 90 - 60 - 52 - 24; text: w.name; color: modelData.wanted ? Theme.text() : (card.wanted.length ? Theme.dim() : Theme.muted()) }
                        AUi.Line { width: 90; text: w.have || !modelData.wanted ? w.value : w.prop ? tab.rangeText(w.prop) : "not on this piece"; color: modelData.wanted && !w.have ? Theme.dim() : Theme.text(); font.pixelSize: 11 }
                        Item {
                            width: 60
                            height: 12
                            anchors.verticalCenter: parent.verticalCenter
                            AUi.Bar {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: (w.have || !modelData.wanted) && w.quality != null
                                width: parent.width
                                height: 4
                                value: Math.max(0.04, w.quality || 0)
                                colour: (w.quality || 0) >= 0.9 ? "#7fdc9a" : Theme.accent
                            }
                        }
                        AUi.Line {
                            width: 52
                            text: card.share[w.name.toLowerCase()] ? "top " + Math.round(card.share[w.name.toLowerCase()] * 100) + " %" : ""
                            color: Theme.dim()
                            font.pixelSize: 10
                        }
                    }
                }
                AUi.Line { visible: !card.cmp.wanted.length && !card.cmp.extra.length; text: "Nothing on it yet."; color: Theme.dim(); font.pixelSize: 11 }
                AUi.Line {
                    visible: card.wanted.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: 11
                    color: card.cmp.wanted.every((w) => w.have) ? "#7fdc9a" : Theme.accentLight
                    text: card.cmp.wanted.every((w) => w.have) ? "✓ Every wanted property is on it." : "A new binding gives all " + card.wanted.length + " wanted: " + tab.ui.chanceText(card.p)
                }
                Row {
                    visible: card.refProps.length > 0 && !!tab.build
                    width: parent.width
                    spacing: 6
                    AUi.Line {
                        width: parent.width - takeChip.width - 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "The build's gear: " + card.refProps.map((r) => r.value ? r.name + " " + r.value : r.name).join(" · ")
                        color: Theme.dim()
                        font.pixelSize: 11
                    }
                    Chip { id: takeChip; text: "Take"; onClicked: tab.setWanted(card.x0.slot, tab.refPicks(card.x0)) }
                }
                // The picker: what the piece can get.
                Loader {
                    active: card.opened
                    width: parent.width
                    sourceComponent: Column {
                        spacing: 2
                        readonly property bool full: card.wanted.length >= card.x0.pool.count
                        readonly property var theirs: { const m = {}; for (const r of card.refProps) m[r.name.toLowerCase()] = r; return m }
                        readonly property var picks: tab.ck.topPicks(tab.sp.cls, card.x0.slot, card.x0.pool, card.x0.it.arcana ? card.x0.it.category : null)
                        function order(list) { return list.slice().sort((a, b) => (card.share[b.name.toLowerCase()] || 0) - (card.share[a.name.toLowerCase()] || 0) || b.first - a.first) }
                        function isOn(n) { return card.wanted.some((w) => w.toLowerCase() === n.toLowerCase()) }
                        Rectangle { width: parent.width; height: 1; color: Theme.divider }
                        Item {
                            width: parent.width
                            height: 26
                            AUi.Head { anchors.verticalCenter: parent.verticalCenter; text: "UP TO " + card.x0.pool.count + ": " + card.wanted.length + " PICKED" }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Chip { visible: parent.parent.parent.picks.length > 0; text: "Top players' picks"; onClicked: tab.setWanted(card.x0.slot, parent.parent.parent.picks) }
                                Chip { visible: card.wanted.length > 0; text: "None"; onClicked: tab.setWanted(card.x0.slot, []) }
                            }
                        }
                        Repeater {
                            model: [["Stats", parent.order(card.x0.pool.stats)], [tab.sp.cls + " skill effects", parent.order(card.x0.pool.skills)]].filter((g) => g[1].length)
                            delegate: Column {
                                id: grp
                                required property var modelData
                                width: card.width - 20
                                AUi.Head { text: modelData[0].toUpperCase() + "  ·  range · first pick · top"; topPadding: 4; font.pixelSize: 10 }
                                Grid {
                                    columns: 2
                                    columnSpacing: 16
                                    width: parent.width
                                    Repeater {
                                        model: grp.modelData[1]
                                        delegate: Row {
                                            required property var modelData
                                            readonly property var picker: grp.parent
                                            readonly property bool isOn: picker.isOn(modelData.name)
                                            readonly property bool off: !isOn && picker.full
                                            width: (grp.width - 16) / 2
                                            height: 22
                                            spacing: 6
                                            opacity: off ? 0.45 : 1
                                            AUi.Tick {
                                                anchors.verticalCenter: parent.verticalCenter
                                                on: parent.isOn
                                                enabled: !parent.off
                                                onToggled: tab.setWanted(card.x0.slot, parent.isOn ? card.wanted.filter((w) => w.toLowerCase() !== modelData.name.toLowerCase()) : card.wanted.concat([modelData.name]))
                                            }
                                            AUi.Line {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 16 - 84 - 46 - 46 - 24
                                                text: modelData.name + (parent.picker.theirs[modelData.name.toLowerCase()] ? "  ◆" : "")
                                                color: parent.isOn ? Theme.accent : Theme.text()
                                                font.pixelSize: 11
                                            }
                                            AUi.Line { anchors.verticalCenter: parent.verticalCenter; width: 84; text: tab.rangeText(modelData); color: Theme.dim(); font.pixelSize: 10 }
                                            AUi.Line { anchors.verticalCenter: parent.verticalCenter; width: 46; text: tab.ui.fmt(modelData.first * 100, modelData.first < 0.01 ? 2 : 1) + " %"; color: Theme.dim(); font.pixelSize: 10 }
                                            AUi.Line {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 46
                                                text: card.share[modelData.name.toLowerCase()] ? "top " + Math.round(card.share[modelData.name.toLowerCase()] * 100) + " %" : ""
                                                color: Theme.accentLight
                                                font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        AUi.Note { width: parent.width; text: "◆ the build's gear has it. First pick: the chance to be a binding's first property." }
                    }
                }
            }
        }
    }
    AUi.Note {
        visible: !!tab.sp && tab.sp.none.length > 0
        width: parent.width
        text: tab.sp ? "No soul binding in the game's item data: " + tab.sp.none.map((it) => it.name).join(", ") + "." : ""
    }
}
