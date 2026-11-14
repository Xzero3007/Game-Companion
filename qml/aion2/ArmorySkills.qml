import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// SKILLS: each skill's level, where it comes from (skill points,
// Daevanion, gear and Arcana) and the build's target with the way to it.
// Improved: targets set with − / + in the row (the old list of numbers),
// "Aim" takes the build's level or the strongest players' median as a
// start, rows without a target fold away per group.
Column {
    id: tab
    property var ui
    readonly property var me: tab
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var targets: ui ? ui.targets : BK.emptyTargets()
    property var unfolded: ({})
    property bool clearArmed: false
    spacing: 8

    readonly property string cls: snap && snap.profile ? snap.profile.className || "" : ""
    readonly property var topInfo: snap ? ck.topOf(cls) : null
    readonly property var topLevels: snap ? ck.topSkillLevels(cls) : ({})
    readonly property var learnt: { if (!ui) return []; ui.rev; return snap ? ck.compareSkills(ck.skillSources(snap), build ? build.ref : null).filter((s) => s.acquired || s.level > 0) : [] }
    readonly property var tracked: learnt.filter((s) => targets.skills[s.name] != null)
    readonly property int span: Math.max(20, ...learnt.map((s) => s.level), ...Object.keys(targets.skills).map((k) => targets.skills[k]))
    readonly property var purple: "#c39bff"

    function setTarget(name, level) { ui.store.changeTargets("skill targets", (t) => { if (level > 0) t.skills[name] = level; else delete t.skills[name] }) }
    function startFor(s) {
        const t = topLevels[s.name]
        const v = s.refLevel != null ? s.refLevel : t && t.median >= 10 ? Math.round(t.median) : s.level + 1
        return s.category === "Dp" ? Math.max(1, Math.min(20, v)) : Math.max(10, Math.min(30, v))
    }
    function sourceName(w) { return w.indexOf("Arcana: ") === 0 ? w.slice(8) + " (Arcana)" : (ck.SLOT_LABEL[w] || w) }
    function hint(s, target) {
        if (target == null) return s.gear.length ? "Now from: " + s.gear.map((g) => g.item + " +" + g.level).join(", ") : ""
        if (s.level >= target) return "✓ At the target."
        if (s.category === "Dp") return (target - s.level) + " to go: Stigma levels come from Stigma Shards."
        const way = ck.skillWay(s, target)
        const parts = []
        if (way.points) parts.push(way.points + " from skill points (to 10)")
        if (way.daevanion.length) parts.push(way.daevanion.reduce((a, n) => a + n.gives, 0) + " from Daevanion: " + way.daevanion.map((n) => n.board + " (" + n.grade + ", " + n.points + " pt)").join(", "))
        if (way.gear) {
            const t = topLevels[s.name]
            const from = ((t && t.sources) || []).slice(0, 3).map((x) => sourceName(x[0]))
            parts.push(way.gear + " from extra skill levels on gear and Arcana" + (from.length ? " (the top players have theirs from " + from.join(", ") + ")" : ""))
        }
        return "To " + target + ": " + parts.join("; ") + "."
    }
    Timer { id: disarm; interval: 3000; onTriggered: tab.clearArmed = false }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }

    Item {
        visible: !!tab.snap
        width: parent.width
        height: 26
        AUi.Title {
            anchors.verticalCenter: parent.verticalCenter
            text: tab.tracked.length ? tab.tracked.filter((s) => s.level >= tab.targets.skills[s.name]).length + " of " + tab.tracked.length + " skills at their target" : (tab.build ? "No skill targets yet" : "Skills")
        }
        Row {
            anchors.right: parent.right
            spacing: 6
            visible: !!tab.build
            AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: "Targets:"; color: Theme.dim(); font.pixelSize: 11 }
            Chip {
                visible: tab.learnt.some((s) => s.refLevel != null)
                text: "The build's levels"
                onClicked: tab.ui.store.changeTargets("skill targets from the build", (t) => { for (const s of tab.learnt) if (s.refLevel != null) t.skills[s.name] = s.refLevel })
            }
            Chip {
                visible: !!tab.topInfo
                text: "The top " + tab.cls + "s' levels"
                onClicked: tab.ui.store.changeTargets("skill targets from the strongest " + tab.cls + "s", (t) => {
                    for (const s of tab.learnt) { const l = tab.topLevels[s.name]; if (l && l.median >= 10) t.skills[s.name] = Math.round(l.median) }
                })
            }
            Chip {
                visible: tab.tracked.length > 0
                text: tab.clearArmed ? "Press again to clear" : "Clear"
                on: tab.clearArmed
                onClicked: {
                    if (!tab.clearArmed) { tab.clearArmed = true; disarm.restart(); return }
                    tab.clearArmed = false
                    tab.ui.store.changeTargets("skill targets cleared", (t) => { t.skills = {} })
                }
            }
        }
    }
    AUi.Note {
        visible: !!tab.snap
        width: parent.width
        text: (tab.build ? "" : "Targets belong to a build (BUILDS). ") + "A skill reaches 10 with skill points, up to 14 with the Daevanion boards (one node on each of the first four), and more with extra skill levels on gear and Arcana (soul binding rolls: its tab shows the chance)."
    }
    // The legend.
    Flow {
        visible: !!tab.snap
        width: parent.width
        spacing: 14
        Repeater {
            model: [[Qt.rgba(1, 1, 1, 0.5), "skill points", 10], [tab.purple, "Daevanion", 10], ["#f2c46b", "gear and Arcana", 10], [Theme.accent, "your target", 3], ["#ffffff", "the build's level", 3]]
            delegate: Row {
                required property var modelData
                spacing: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: modelData[2]; height: modelData[2] === 3 ? 12 : 6; color: modelData[0] }
                AUi.Line { text: modelData[1]; color: Theme.dim(); font.pixelSize: 11 }
            }
        }
        AUi.Line { text: "marks at 10, 14, 20" + (tab.topInfo ? " · “top”: the median of the " + tab.topInfo.n + " strongest " + tab.cls + "s" : ""); color: Theme.dim(); font.pixelSize: 11 }
    }

    Repeater {
        model: tab.snap ? [["Active", "Active skills"], ["Passive", "Passive skills"], ["Dp", "Stigmas"]] : []
        delegate: Column {
            id: grp
            required property var modelData
            readonly property string cat: modelData[0]
            readonly property var list: tab.learnt.filter((s) => s.category === cat).sort((a, b) => (b.equipped - a.equipped) || (b.level - a.level))
            readonly property var on: list.filter((s) => tab.targets.skills[s.name] != null)
            readonly property var off: list.filter((s) => tab.targets.skills[s.name] == null)
            readonly property bool openOff: tab.unfolded[cat] !== undefined ? tab.unfolded[cat] : !on.length
            visible: list.length > 0
            width: tab.width
            spacing: 2
            AUi.Head { text: modelData[1].toUpperCase(); topPadding: 6 }
            Repeater { model: grp.on; delegate: ArmorySkillRow { tab: me } }
            Item {
                visible: grp.off.length > 0
                width: parent.width
                height: 24
                AUi.Line {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (grp.openOff ? "▾ " : "▸ ") + (grp.on.length ? grp.off.length + " more without a target" : grp.off.length + " skills without a target")
                    color: Theme.accent
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { const u = Object.assign({}, tab.unfolded); u[grp.cat] = !grp.openOff; tab.unfolded = u }
                }
            }
            Repeater { model: grp.openOff ? grp.off : []; delegate: ArmorySkillRow { tab: me } }
        }
    }
}
