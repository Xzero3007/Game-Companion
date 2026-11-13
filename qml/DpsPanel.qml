import QtQuick
import GameCompanion
import "theme.js" as Theme

// The AION 2 module's DPS meter (design "4 · Ein AION-2-Fenster im neuen
// Stil"): the fight's time, a row per player with a bar for their share,
// the player in gold. Reads the game's traffic only (Aion2), never sends.
Panel {
    id: panel
    panelId: "dps"
    title: "DPS Meter"
    tag: "AION 2"
    width: 512
    minWidth: 380
    maxWidth: 900
    badge: clock(fight.time)

    readonly property var fight: JSON.parse(Aion2.fight)
    /// damage, healing, skills
    property string tab: nativeWindow.demo.indexOf("skills") >= 0 ? "skills" : "damage"
    readonly property bool skillsShown: tab === "skills"
    readonly property var skills: JSON.parse(Aion2.skills)
    readonly property real mostSkill: skills.length > 0 ? skills[0].damage : 1
    /// The player whose skills show: picked, else the one playing.
    readonly property var pickedRow: {
        for (const r of fight.rows) if (Aion2.picked !== 0 ? r.id === Aion2.picked : r.me) return r
        return null
    }
    readonly property bool healing: tab === "healing"
    readonly property var rows: {
        const list = fight.rows.filter((r) => healing ? r.heal > 0 : r.amount > 0)
        if (healing) list.sort((a, b) => b.heal - a.heal)
        return list
    }
    readonly property real most: rows.length > 0 ? (healing ? rows[0].heal : rows[0].amount) : 1

    function clock(ms) {
        const s = Math.floor(ms / 1000)
        const m = Math.floor(s / 60)
        return (m < 10 ? "0" : "") + m + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }
    function number(n) { return Math.round(n).toLocaleString(Qt.locale("en_US"), "f", 0) }

    Column {
        width: parent.width
        spacing: 0

        // Tabs, the target and RESET.
        Item {
            width: parent.width
            height: 34
            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 18
                DpsTab { name: "damage"; label: "Damage" }
                DpsTab { name: "healing"; label: "Healing" }
                DpsTab { name: "skills"; label: "Skills" }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.right: resetButton.left
                anchors.rightMargin: 10
                anchors.left: parent.left
                anchors.leftMargin: 250
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: panel.skillsShown ? (panel.pickedRow ? panel.pickedRow.name : "") : panel.fight.target
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 12
            }
            TextButton {
                id: resetButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 26
                text: "Reset"
                onClicked: Aion2.reset()
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.divider }

        // The target's HP, for a boss.
        Item {
            visible: panel.fight.boss && panel.fight.hpMax > 0
            width: parent.width
            height: visible ? 14 : 0
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 3
                color: Theme.trackDark
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, panel.fight.hpNow / Math.max(1, panel.fight.hpMax)))
                    height: parent.height
                    color: Theme.red
                }
            }
        }

        Item { width: 1; height: 10 }

        // SKILLS: the picked player's skills (a click on a row picks).
        Column {
            visible: panel.skillsShown
            width: parent.width
            spacing: 4
            Item {
                width: parent.width
                height: 18
                Repeater {
                    model: [["Skill", 10, false], ["Casts", 186, true], ["Damage", 106, true], ["Crit", 52, true], ["%", 10, true]]
                    delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        required property var modelData
                        x: modelData[2] ? parent.width - modelData[1] - implicitWidth : modelData[1]
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[0].toUpperCase()
                        color: Theme.dim()
                        font.family: Theme.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }
            }
            Repeater {
                model: panel.skillsShown ? panel.skills : []
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 32
                    Rectangle { anchors.fill: parent; color: "#1b1a20" }
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, modelData.damage / Math.max(1, panel.mostSkill)))
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: casts.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: modelData.name
                        color: Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: casts
                        anchors.right: parent.right
                        anchors.rightMargin: 186
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.casts
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.right: parent.right
                        anchors.rightMargin: 106
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.number(modelData.damage)
                        color: Theme.text()
                        font.family: Theme.display
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.right: parent.right
                        anchors.rightMargin: 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(modelData.crit) + "%"
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(modelData.share) + "%"
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + ", " + modelData.casts + " casts, " + panel.number(modelData.damage) + " damage"
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                visible: panel.skills.length === 0
                width: parent.width
                topPadding: 18
                bottomPadding: 18
                horizontalAlignment: Text.AlignHCenter
                text: "No skills counted yet. A click on a player in Damage shows theirs."
                wrapMode: Text.Wrap
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 13
            }
        }

        Column {
            visible: !panel.skillsShown
            width: parent.width
            spacing: 4
            Repeater {
                model: panel.rows
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property real value: panel.healing ? modelData.heal : modelData.amount
                    width: parent.width
                    height: 38
                    Rectangle { anchors.fill: parent; color: "#1b1a20" }
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, value / Math.max(1, panel.most)))
                        color: modelData.me ? Qt.rgba(0.878, 0.647, 0.149, 0.32) : Qt.rgba(1, 1, 1, 0.08)
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: rank
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        text: index + 1
                        color: Theme.dim()
                        font.family: Theme.display
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        anchors.left: rank.right
                        anchors.leftMargin: 10
                        anchors.right: perSecond.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: modelData.name + (modelData.job.length > 0 && modelData.name.indexOf("[") !== 0 ? "  ·  " + modelData.job : "")
                        color: modelData.me ? Theme.accent : Theme.text()
                        font.family: Theme.body
                        font.pixelSize: 13
                        font.weight: modelData.me ? Font.Bold : Font.Medium
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: perSecond
                        anchors.right: share.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.number(panel.healing ? modelData.hps : modelData.dps)
                        color: Theme.text()
                        font.family: Theme.display
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        id: share
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        horizontalAlignment: Text.AlignRight
                        text: panel.healing
                            ? Math.round(value / Math.max(1, panel.rows.reduce((s, r) => s + r.heal, 0)) * 100) + "%"
                            : Math.round(modelData.share) + "%"
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !Companion.locked
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Aion2.pick(modelData.me ? 0 : modelData.id); panel.tab = "skills" }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + ", " + perSecond.text + (panel.healing ? " healing" : " damage") + " per second, " + share.text
                }
            }
            // Nothing counted yet: what the module is doing.
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                visible: panel.rows.length === 0
                width: parent.width
                topPadding: 18
                bottomPadding: 18
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Aion2.state === "failed" ? "Cannot read the game: " + Aion2.problem
                    : Aion2.state === "off" ? "Starts by itself when AION 2 runs."
                    : Aion2.state === "searching" ? "Looking for the game's connection…"
                    : "Waiting for the first hit."
                color: Aion2.state === "failed" ? Theme.red : Theme.muted()
                font.family: Theme.body
                font.pixelSize: 13
            }
        }

        Item { width: 1; height: 10 }
        Rectangle { width: parent.width + 28; x: -14; height: 1; color: Theme.divider }

        // Foot: what it does, and how many.
        Item {
            width: parent.width
            height: 38
            Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                color: Aion2.state === "reading" ? Theme.accent : Aion2.state === "failed" ? Theme.red : Theme.track
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: dot.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Listens only. Never sends anything to the game."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "PARTY · " + panel.fight.rows.filter((r) => !r.others).length
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
        }
    }

    component DpsTab: Item {
        property string name
        property string label
        readonly property bool current: panel.tab === name
        width: tabText.implicitWidth
        height: 32
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: tabText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
            font.family: Theme.display
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 1.5
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            color: parent.current ? Theme.accent : "transparent"
        }
        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !Companion.locked
            onClicked: panel.tab = parent.name
        }
        Accessible.role: Accessible.PageTab
        Accessible.name: label
    }
}
