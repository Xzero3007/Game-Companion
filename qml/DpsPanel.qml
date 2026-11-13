import QtQuick
import GameCompanion
import "theme.js" as Theme

// The AION 2 module's DPS meter (design "4 · Ein AION-2-Fenster im neuen
// Stil"): the fight's time and RESET in the header, a row per player with
// a bar for their share, the player in gold; Healing, the picked player's
// Skills, and the Battle History of saved fights. Reads the game's
// traffic only (Aion2), never sends.
Panel {
    id: panel
    panelId: "dps"
    // Narrow: shorter header, fewer words in the foot.
    readonly property bool narrow: width < 400
    title: width < 330 ? "DPS" : "DPS Meter"
    tag: narrow ? "" : "AION 2"
    width: 512
    minWidth: 280
    stretchy: true
    // Down to two rows.
    minGrow: -42 * 4
    maxWidth: 900
    badge: clock(fight.time)
    actionText: Aion2.opened.length > 0 ? "" : "Reset"
    onActionClicked: Aion2.reset()

    readonly property var fight: JSON.parse(Aion2.fight)
    /// Ping and Odyle energy, as the old meter's bar showed them.
    readonly property var extras: fight.extras || ({ ping: null, odyle: null })
    /// Its own ground opacity (100, 75, 50, 25 %), on top of the overall one.
    property int opacityPercent: Streams.opacityOf("dps")
    ground: Companion.alpha * opacityPercent / 100
    /// damage, healing, skills, history
    property string tab: {
        const demo = nativeWindow.demo
        return demo.indexOf("skills") >= 0 ? "skills" : demo.indexOf("history") >= 0 ? "history" : "damage"
    }
    readonly property bool healing: tab === "healing"
    readonly property var skills: JSON.parse(Aion2.skills)
    readonly property real mostSkill: skills.length > 0 ? skills[0].damage : 1
    readonly property var history: JSON.parse(Aion2.history)
    /// The player whose skills show: picked, else the one playing.
    readonly property var pickedRow: {
        for (const r of fight.rows) if (Aion2.picked !== 0 ? r.id === Aion2.picked : r.me) return r
        return null
    }
    readonly property var savedFight: {
        for (const f of history) if (f.id === Aion2.opened) return f
        return null
    }

    // The rows, kept in a model changed in place: a fight changes every
    // half second, and only the values that change are drawn again.
    property real most: 1
    ListModel { id: rowsModel }
    function syncRows() {
        const list = fight.rows.filter((r) => healing ? r.heal > 0 : r.amount > 0)
        if (healing) list.sort((a, b) => b.heal - a.heal)
        most = list.length > 0 ? Math.max(1, healing ? list[0].heal : list[0].amount) : 1
        let total = 0
        for (const r of list) total += r.heal
        for (let i = 0; i < list.length; i++) {
            const r = list[i]
            const row = {
                actor: r.id, name: r.name, job: r.job, me: r.me,
                value: healing ? r.heal : r.amount,
                perSecond: healing ? r.hps : r.dps,
                share: healing ? (total > 0 ? r.heal / total * 100 : 0) : r.share
            }
            if (i < rowsModel.count) rowsModel.set(i, row)
            else rowsModel.append(row)
        }
        if (rowsModel.count > list.length) rowsModel.remove(list.length, rowsModel.count - list.length)
    }
    onFightChanged: syncRows()
    onHealingChanged: syncRows()
    Component.onCompleted: syncRows()

    function clock(ms) {
        const s = Math.floor(ms / 1000)
        const m = Math.floor(s / 60)
        return (m < 10 ? "0" : "") + m + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }
    function number(n) { return Math.round(n).toLocaleString(Qt.locale("en_US"), "f", 0) }
    function compact(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(0) + "K"
        return String(n)
    }
    function when(ms) { return Qt.formatDateTime(new Date(ms), "ddd d MMM · HH:mm") }

    Column {
        width: parent.width
        spacing: 0

        // Tabs, and the target or the picked player.
        Item {
            width: parent.width
            height: 34
            Row {
                id: tabs
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 18
                DpsTab { name: "damage"; label: "Damage" }
                DpsTab { name: "healing"; label: "Healing" }
                DpsTab { name: "skills"; label: "Skills" }
                DpsTab { name: "history"; label: "History" }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: tabs.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                visible: panel.tab !== "history"
                text: panel.tab === "skills" ? (panel.pickedRow ? panel.pickedRow.name : "") : panel.fight.target
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 12
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.divider }

        // A saved fight shown: say so, and the way back.
        Item {
            visible: Aion2.opened.length > 0 && panel.tab !== "history"
            width: parent.width
            height: visible ? 34 : 0
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: parent.left
                anchors.right: backText.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: panel.savedFight ? "SAVED · " + panel.when(panel.savedFight.start) : "SAVED FIGHT"
                color: Theme.purpleText
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: backText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "BACK TO LIVE"
                color: backMouse.containsMouse ? Theme.accentLight : Theme.accent
                font.family: Theme.display
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.5
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    enabled: !Companion.locked
                    onClicked: Aion2.openFight("")
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Back to the live fight"
            }
        }

        // The target's HP, for a boss.
        Item {
            visible: panel.fight.boss && panel.fight.hpMax > 0 && (panel.tab === "damage" || panel.tab === "healing")
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

        // The lists keep one height (dragged taller or shorter at the corner)
        // and scroll: the panel's window keeps its size while a fight counts.
        Item {
            width: parent.width
            height: 42 * 6 + panel.grow
            clip: true
            Flickable {
                id: listFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: lists.height
                boundsBehavior: Flickable.StopAtBounds
                interactive: !Companion.locked
                Column {
                    id: lists
                    width: listFlick.width
                // DAMAGE and HEALING: a row per player (a click shows their skills).
                Column {
                    visible: panel.tab === "damage" || panel.tab === "healing"
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: rowsModel
                        delegate: Item {
                            required property int index
                            required property int actor
                            required property string name
                            required property string job
                            required property bool me
                            required property real value
                            required property real perSecond
                            required property real share
                            width: parent.width
                            height: 38
                            Rectangle { anchors.fill: parent; color: "#1b1a20" }
                            Rectangle {
                                height: parent.height
                                width: parent.width * Math.max(0, Math.min(1, value / panel.most))
                                color: me ? Qt.rgba(0.878, 0.647, 0.149, 0.32) : Qt.rgba(1, 1, 1, 0.08)
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
                                anchors.right: perSecondText.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: name + (job.length > 0 && name.indexOf("[") !== 0 ? "  ·  " + job : "")
                                color: me ? Theme.accent : Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 13
                                font.weight: me ? Font.Bold : Font.Medium
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: perSecondText
                                anchors.right: shareText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.number(perSecond)
                                color: Theme.text()
                                font.family: Theme.display
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: shareText
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(share) + "%"
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !Companion.locked && Aion2.opened.length === 0
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: { Aion2.pick(me ? 0 : actor); panel.tab = "skills" }
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: name + ", " + perSecondText.text + (panel.healing ? " healing" : " damage") + " per second, " + shareText.text
                        }
                    }
                    // Nothing counted yet: what the module is doing.
                    Item {
                        visible: rowsModel.count === 0
                        width: parent.width
                        height: visible ? stateText.height + (retry.visible ? retry.height + 8 : 0) : 0
                        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                            id: stateText
                            width: parent.width
                            topPadding: 18
                            bottomPadding: 18
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: Aion2.opened.length > 0 ? "Nothing was counted in this fight."
                                : Aion2.state === "failed" ? "Cannot read the game: " + Aion2.problem
                                : Aion2.state === "off" ? "Starts by itself when AION 2 runs."
                                : Aion2.state === "searching" ? "Looking for the game's connection…"
                                : "Waiting for the first hit."
                            color: Aion2.state === "failed" && Aion2.opened.length === 0 ? Theme.red : Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 13
                        }
                        TextButton {
                            id: retry
                            visible: Aion2.state === "failed" && Aion2.opened.length === 0
                            anchors.top: stateText.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: 28
                            text: "Try again"
                            onClicked: if (!Companion.locked) { Aion2.stop(); Aion2.start() }
                        }
                    }
                }

                // SKILLS: the picked player's skills.
                Column {
                    visible: panel.tab === "skills"
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
                        model: panel.tab === "skills" ? panel.skills : []
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
                        text: Aion2.opened.length > 0 ? "Skills are shown for the live fight."
                            : "No skills counted yet. A click on a player in Damage shows theirs."
                        wrapMode: Text.Wrap
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                }

                // HISTORY: the saved boss fights, newest first (a click shows one).
                Column {
                    visible: panel.tab === "history"
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: panel.tab === "history" ? panel.history.slice(0, 30) : []
                        delegate: Item {
                            required property var modelData
                            readonly property bool current: modelData.id === Aion2.opened
                            width: parent.width
                            height: 44
                            Rectangle {
                                anchors.fill: parent
                                color: current ? Qt.rgba(0.878, 0.647, 0.149, 0.18) : (fightMouse.containsMouse ? "#24222a" : "#1b1a20")
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: bossText
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: totalText.left
                                anchors.rightMargin: 10
                                y: 6
                                elide: Text.ElideRight
                                text: modelData.boss.length > 0 ? modelData.boss : "Unknown target"
                                color: current ? Theme.accent : Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.left: bossText.left
                                anchors.right: bossText.right
                                anchors.top: bossText.bottom
                                anchors.topMargin: 2
                                elide: Text.ElideRight
                                text: panel.when(modelData.start) + " · " + panel.clock(modelData.duration) + (modelData.train ? " · training" : "")
                                color: Theme.dim()
                                font.family: Theme.body
                                font.pixelSize: 11
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: totalText
                                anchors.right: removeButton.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.compact(modelData.total)
                                color: Theme.text()
                                font.family: Theme.display
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: fightMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !Companion.locked
                                onClicked: { Aion2.openFight(modelData.id); panel.tab = "damage" }
                            }
                            Item {
                                id: removeButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                HudIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 12
                                    lineWidth: 2
                                    color: removeMouse.containsMouse ? Theme.red : Theme.dim()
                                }
                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !Companion.locked
                                    onClicked: Aion2.removeFight(modelData.id)
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove this fight"
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: bossText.text + ", " + totalText.text + " damage"
                        }
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        visible: panel.history.length === 0
                        width: parent.width
                        topPadding: 18
                        bottomPadding: 18
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Boss fights are kept here (on this computer only)."
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 13
                    }
                }
                }
            }
            WheelScroll { flick: listFlick; step: 42 * 3 }
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
                anchors.right: liveInfo.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                visible: panel.width >= 470
                text: "Listens only. Never sends anything to the game."
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
            // Odyle energy (basic, + charged) and the ping, as in the old meter.
            Row {
                id: liveInfo
                anchors.right: partyText.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: !!panel.extras.odyle && Aion2.opened.length === 0
                    textFormat: Text.StyledText
                    text: panel.extras.odyle
                        ? "<font color='" + Theme.dim() + "'>ODYLE</font> " + panel.extras.odyle[0].toLocaleString(Qt.locale("en_US"), "f", 0)
                          + " <font color='" + Theme.purpleText + "'>(+" + panel.extras.odyle[1].toLocaleString(Qt.locale("en_US"), "f", 0) + ")</font>"
                        : ""
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: panel.extras.ping !== null && panel.extras.ping !== undefined && Aion2.opened.length === 0
                    text: panel.extras.ping + " ms"
                    color: panel.extras.ping > 150 ? Theme.red : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: partyText
                anchors.right: opacityButton.left
                anchors.rightMargin: panel.narrow ? 0 : 10
                width: panel.narrow ? 0 : implicitWidth
                visible: !panel.narrow
                anchors.verticalCenter: parent.verticalCenter
                text: "PARTY · " + panel.fight.rows.filter((r) => !r.others).length
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            // 100, 75, 50, 25 % ground, round.
            TextButton {
                id: opacityButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 24
                text: panel.opacityPercent + "%"
                onClicked: {
                    const steps = [100, 75, 50, 25]
                    const i = steps.indexOf(panel.opacityPercent)
                    panel.opacityPercent = steps[(i + 1) % steps.length]
                    Streams.saveOpacity("dps", panel.opacityPercent)
                }
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
