import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK
import "armorykit.js" as AK

// STATS: the ten deity stats round a circle with the six base stats inside
// (the build's deity stats where they differ), what each point gives, and
// what every stat does in the game's own words with where yours come from.
// Improved: the build's deity stats listed against yours with what is
// missing, the glossary searchable.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    property bool everyStat: false
    property string query: ""
    spacing: 10

    readonly property var deity: ["Justice", "Freedom", "Illusion", "Life", "Time", "Destruction", "Death", "Wisdom", "Destiny", "Space"]
    readonly property var base: ["STR", "DEX", "INT", "CON", "AGI", "WIS"]
    readonly property var stats: snap ? snap.stats || {} : {}
    readonly property var refDeity: build && build.ref ? build.ref.deity || {} : ({})
    readonly property int half: Math.floor((width - 10) / 2)
    readonly property var gloss: {
        if (!ui || !snap) return []
        ui.rev
        const mine = ck.characterStats(snap)
        let list = everyStat
            ? ((AK.G && AK.G.ARMORY_DATA) || {}).glossary || []
            : null
        if (list) {
            list = list.map((x) => ({ name: x[0], entry: ck.explainStat(x[0], x[1]), from: ((mine.find((m) => m.name === x[0]) || {}).from) || [] })).filter((x) => x.entry)
            const order = (g) => (ck.STAT_GROUPS.indexOf(g) + 100) % 100
            list.sort((a, b) => order(a.entry.group) - order(b.entry.group))
        } else list = mine
        const q = query.trim().toLowerCase()
        return q ? list.filter((x) => x.name.toLowerCase().indexOf(q) >= 0 || (x.entry && x.entry.desc.toLowerCase().indexOf(q) >= 0)) : list
    }
    function label(k) { const s = stats[k]; return (s && s.name ? s.name : k).replace(/\s*\[.*\]$/, "") }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }

    Row {
        visible: !!tab.snap
        width: parent.width
        spacing: 10

        AUi.Box {
            width: tab.half
            AUi.Title { text: "Base and deity stats" }
            Item {
                id: wheel
                width: parent.width
                height: 300
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                readonly property real r: 118
                Rectangle { x: wheel.cx - wheel.r - 22; y: wheel.cy - wheel.r - 22; width: 2 * (wheel.r + 22); height: width; radius: width / 2; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.08) }
                Rectangle { x: wheel.cx - 72; y: wheel.cy - 72; width: 144; height: 144; radius: 72; color: Qt.rgba(1, 1, 1, 0.03); border.color: Qt.rgba(1, 1, 1, 0.08) }
                Repeater {
                    model: tab.deity
                    delegate: Column {
                        required property string modelData
                        required property int index
                        readonly property real a: (-90 + index * 36) * Math.PI / 180
                        readonly property var st: tab.stats[modelData]
                        readonly property var want: tab.refDeity[modelData]
                        x: wheel.cx + Math.cos(a) * wheel.r - width / 2
                        y: wheel.cy + Math.sin(a) * wheel.r - 18
                        width: 90
                        AUi.Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: tab.label(modelData); color: Theme.dim(); font.pixelSize: 10 }
                        AUi.Figure { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: parent.st ? tab.ui.fmt(parent.st.value) : "—" }
                        AUi.Line {
                            visible: parent.want != null && !!parent.st && parent.want !== parent.st.value
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "build " + parent.want
                            color: "#f2c46b"
                            font.pixelSize: 10
                        }
                    }
                }
                Grid {
                    x: wheel.cx - 66
                    y: wheel.cy - 40
                    columns: 2
                    Repeater {
                        model: tab.base
                        delegate: Column {
                            required property string modelData
                            width: 66
                            height: 27
                            AUi.Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: tab.label(modelData); color: Theme.dim(); font.pixelSize: 10 }
                            AUi.Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: tab.stats[modelData] ? tab.ui.fmt(tab.stats[modelData].value) : "—"; font.bold: true }
                        }
                    }
                }
            }
            AUi.Note { visible: Object.keys(tab.refDeity).length > 0; width: parent.width; text: "Gold: the build's deity stats where they differ from yours." }
        }

        AUi.Box {
            width: tab.half
            AUi.Title { text: "What each point gives" }
            Repeater {
                model: tab.base.concat(tab.deity).filter((k) => !!tab.stats[k])
                delegate: Item {
                    required property string modelData
                    readonly property var st: tab.stats[modelData]
                    readonly property var want: tab.refDeity[modelData]
                    width: parent.width
                    height: 18
                    AUi.Line {
                        width: parent.width - v.width - 8
                        text: parent.st.name + ((parent.st.effects || []).length ? "  · " + parent.st.effects.join(", ") : "")
                        font.pixelSize: 11
                    }
                    AUi.Line {
                        id: v
                        anchors.right: parent.right
                        text: tab.ui.fmt(parent.st.value) + (parent.want != null ? " / " + parent.want : "")
                        color: parent.want != null && parent.want > parent.st.value ? Theme.accentLight : Theme.text()
                        font.bold: true
                        font.pixelSize: 11
                    }
                }
            }
            AUi.Note { width: parent.width; text: "Each point of a base or deity stat gives 0.1 % of what it names, the same for every point." + (Object.keys(tab.refDeity).length ? " After the slash: the build's." : "") }
        }
    }

    AUi.Box {
        visible: !!tab.snap
        width: parent.width
        AUi.Title { text: "In short" }
        Repeater {
            model: [
                ["Bonus or increase: ", "a Bonus adds a flat amount (Attack Bonus +30); an increase multiplies the total (Attack increase +5.6 %)."],
                ["Chance, Resist, Penetration: ", "your Perfect and Double Chance are lowered by the target's Perfect and Double Resist; a target's Regeneration and Endurance by your Regeneration and Endurance Penetration; Block by Block Penetration."],
                ["Perfect, Double, Multi-hit: ", "Perfect deals more damage from the weapon's Max Attack; Double greatly increased damage from the final damage; Multi-hit up to 4 more hits, by Attack. Endurance halves the damage taken; Regeneration heals a part of it."],
                ["Boost and Tolerance: ", "a Damage Boost (also Critical, Weapon, PvE, Boss, PvP) is weakened by the target's Tolerance of the same kind; Attack and Defense against monsters, bosses or characters count only against those."],
                ["Caps the game states: ", "Critical Hit rate 50 % (less the target's Critical Hit Resist), Evasion 30 %, Cooldown and MP cost reduction 60 %, Move Speed 150 %, Defense never below 0."]
            ]
            delegate: Text {
                required property var modelData
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                text: "<b>" + modelData[0] + "</b>" + modelData[1]
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
        }
    }

    Item {
        visible: !!tab.snap
        width: parent.width
        height: 26
        AUi.Title { anchors.verticalCenter: parent.verticalCenter; text: tab.everyStat ? "What every stat does" : "What your stats do" }
        Row {
            anchors.right: parent.right
            spacing: 8
            AUi.Field { width: 180; placeholder: "Find a stat"; onEdited: (t) => tab.query = t }
            Chip { text: "Every stat the game has"; on: tab.everyStat; onClicked: tab.everyStat = !tab.everyStat }
        }
    }
    AUi.Note { visible: !!tab.snap; width: parent.width; text: "The game's own descriptions of its stats (its files, as Aion2Data lists them), with where yours come from." }
    Repeater {
        model: tab.gloss
        delegate: Column {
            required property var modelData
            required property int index
            readonly property string group: (modelData.entry && modelData.entry.group) || "Other"
            readonly property bool first: index === 0 || ((tab.gloss[index - 1].entry && tab.gloss[index - 1].entry.group) || "Other") !== group
            width: tab.width
            spacing: 1
            AUi.Head { visible: parent.first; text: (parent.group === "Other stats" ? "Base and deity stats, bonuses and increases" : parent.group).toUpperCase(); topPadding: 8 }
            Row {
                spacing: 6
                AUi.Line { text: modelData.name; font.bold: true; font.pixelSize: 11 }
                AUi.Line { visible: (modelData.from || []).length > 0; text: "· from " + (modelData.from || []).join(", "); color: Theme.dim(); font.pixelSize: 11 }
            }
            AUi.Note { width: parent.width; text: modelData.entry ? modelData.entry.desc : "The game describes it nowhere." }
        }
    }
}
