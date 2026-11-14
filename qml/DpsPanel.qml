import QtQuick
import GameCompanion
import "theme.js" as Theme

// The AION 2 module's DPS meter, slim like the old meter (canvas page
// "DPS-Fenster schlank", MN 2026-11-13): a 30 px header with the tabs in it,
// 28 px rows with the class symbol, combat power and gear score, the whole
// party from the moment it forms; Healing, the picked player's Skills with
// their pictures, and the Battle History. Reads the game's traffic only
// (Aion2), never sends.
Panel {
    id: panel
    panelId: "dps"
    compact: true
    // Narrow: short tab names, fewer things in the foot.
    readonly property bool narrow: width < 400
    title: "DPS"
    tag: width < 380 ? "" : "AION 2"
    width: 440
    minWidth: 300
    stretchy: true
    // Down to two rows.
    minGrow: -30 * 4
    maxWidth: 900
    actionText: Aion2.opened.length > 0 ? "" : "Reset"
    onActionClicked: Aion2.reset()
    headerTools: Component {
        Row {
            spacing: panel.narrow ? 9 : 12
            DpsTab { name: "damage"; label: panel.narrow ? "Dmg" : "Damage" }
            DpsTab { name: "healing"; label: panel.narrow ? "Heal" : "Healing" }
            DpsTab { name: "skills"; label: "Skills" }
            DpsTab { name: "history"; label: panel.narrow ? "Hist" : "History" }
        }
    }

    readonly property var fight: JSON.parse(Aion2.fight)
    /// Ping and Odyle energy, as the old meter's bar showed them.
    readonly property var extras: fight.extras || ({ ping: null, odyle: null })
    /// Its own ground opacity (100, 75, 50, 25 or 10 %), on top of the overall one.
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
    readonly property real skillTotal: skills.reduce((sum, s) => sum + s.damage, 0)
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
    readonly property real totalDps: fight.rows.reduce((sum, r) => sum + (healing ? r.hps : r.dps), 0)
    readonly property real totalAmount: fight.rows.reduce((sum, r) => sum + (healing ? r.heal : r.amount), 0)

    // Combat power and gear score in the game's cyan.
    readonly property color cpColour: "#6fd3e6"
    readonly property string assets: "qrc:/qt/qml/GameCompanion/assets/aion2/"
    /// A class's symbol (the old meter's pictures); "" when unknown.
    function classIcon(job) {
        const files = {
            Gladiator: "gladiator", Templar: "templar", Assassin: "assassin", Ranger: "ranger",
            Sorcerer: "sorcerer", Spiritmaster: "spiritmaster", Elementalist: "spiritmaster",
            Cleric: "cleric", Chanter: "chanter", Brawler: "brawler", "권성": "brawler"
        }
        return files[job] ? assets + "classes/" + files[job] + ".png" : ""
    }
    /// A class's colour for its bars (the old meter's "AION 2 classes" theme):
    /// strong enough to read with the ground almost clear.
    function classColour(job) {
        const colours = {
            Spiritmaster: "#e06bff", Elementalist: "#e06bff", Ranger: "#41d98a", Assassin: "#7be35a", Templar: "#5f8cff",
            Sorcerer: "#9a6bff", Chanter: "#ff9a3d", Cleric: "#f2c15a", Gladiator: "#4fd1c5", Brawler: "#e85d5d", "권성": "#e85d5d"
        }
        return colours[job] || "#b8b5c0"
    }
    function tint(colour, alpha) { const c = Qt.color(colour); return Qt.rgba(c.r, c.g, c.b, alpha) }
    // Skill pictures come from the game's icon server once and stay on disk.
    property int iconsRevision: 0
    Connections {
        target: Aion2
        function onIconReady(name) { panel.iconsRevision++ }
    }
    function skillPicture(name) {
        iconsRevision
        return name.length > 0 && name !== "basic" ? Aion2.icon(name) : ""
    }

    // The rows, kept in a model changed in place: a fight changes every
    // half second, and only the values that change are drawn again.
    property real most: 1
    ListModel { id: rowsModel }
    function syncRows() {
        // The party shows from the start, damage or not; Others only with some.
        const list = fight.rows.filter((r) => !r.others || (healing ? r.heal > 0 : r.amount > 0))
        if (healing) list.sort((a, b) => b.heal - a.heal)
        most = list.length > 0 ? Math.max(1, healing ? list[0].heal : list[0].amount) : 1
        let total = 0
        for (const r of list) total += r.heal
        for (let i = 0; i < list.length; i++) {
            const r = list[i]
            const row = {
                actor: r.id, name: r.name, job: r.job, me: r.me,
                cp: r.cp || 0, gs: r.gs || 0,
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
        return m + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }
    function number(n) { return Math.round(n).toLocaleString(Qt.locale("en_US"), "f", 0) }
    /// 168k, 3.36m: the old meter's short numbers.
    function brief(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(2) + "b"
        if (n >= 1e6) return (n / 1e6).toFixed(2) + "m"
        if (n >= 1e4) return Math.round(n / 1e3) + "k"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return String(Math.round(n))
    }
    function compact(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(0) + "K"
        return String(n)
    }
    function when(ms) { return Qt.formatDateTime(new Date(ms), "ddd d MMM HH:mm") }

    Column {
        width: parent.width
        spacing: 0

        // A saved fight shown: say so, and the way back.
        Item {
            visible: Aion2.opened.length > 0 && panel.tab !== "history"
            width: parent.width
            height: visible ? 24 : 0
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.right: backText.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: panel.savedFight ? "SAVED · " + panel.when(panel.savedFight.start) : "SAVED FIGHT"
                color: Theme.purpleText
                font.family: Theme.display
                font.pixelSize: 11
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
                font.pixelSize: 11
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

        // The target: its name in its HP bar.
        Item {
            visible: (panel.tab === "damage" || panel.tab === "healing") && panel.fight.target.length > 0
            width: parent.width
            height: visible ? 20 : 0
            Rectangle {
                id: hpBar
                y: 4
                width: parent.width
                height: 16
                color: Theme.trackDark
                readonly property real hpLeft: panel.fight.hpMax > 0 ? Math.max(0, Math.min(1, panel.fight.hpNow / panel.fight.hpMax)) : 0
                Rectangle {
                    width: parent.width * hpBar.hpLeft
                    height: parent.height
                    color: Qt.rgba(0.898, 0.282, 0.302, 0.55)
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: bossTag
                    visible: panel.fight.boss
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? implicitWidth : 0
                    text: "BOSS"
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    anchors.left: bossTag.right
                    anchors.leftMargin: bossTag.visible ? 6 : 6
                    anchors.right: hpText.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: panel.fight.target
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: hpText
                    visible: panel.fight.hpMax > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(hpBar.hpLeft * 100) + "% · " + panel.brief(panel.fight.hpNow) + " / " + panel.brief(panel.fight.hpMax)
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 10
                }
            }
        }

        // SKILLS: whose they are.
        Item {
            visible: panel.tab === "skills" && panel.pickedRow !== null
            width: parent.width
            height: visible ? 26 : 0
            Image {
                id: whoIcon
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                sourceSize: Qt.size(32, 32)
                fillMode: Image.PreserveAspectFit
                source: panel.pickedRow ? panel.classIcon(panel.pickedRow.job) : ""
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: whoName
                anchors.left: whoIcon.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: panel.pickedRow ? panel.pickedRow.name : ""
                color: Theme.accent
                font.family: Theme.body
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: whoName.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: panel.pickedRow ? panel.pickedRow.job + " · " + panel.brief(panel.skillTotal) + " in " + panel.clock(panel.fight.time) : ""
                color: Theme.dim()
                font.family: Theme.body
                font.pixelSize: 11
            }
        }
        // SKILLS: the columns' names.
        Item {
            visible: panel.tab === "skills" && panel.skills.length > 0
            width: parent.width
            height: visible ? 16 : 0
            Repeater {
                model: [["Skill", 6, false], ["Casts", 166, true], ["Damage", 96, true], ["Crit", 52, true], ["%", 8, true]]
                delegate: Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    required property var modelData
                    x: modelData[2] ? parent.width - modelData[1] - implicitWidth : modelData[1]
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[0].toUpperCase()
                    color: Theme.dim()
                    font.family: Theme.display
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
            }
        }

        Item { width: 1; height: 5 }

        // The lists keep one height (dragged taller or shorter at the corner)
        // and scroll: the panel's window keeps its size while a fight counts.
        Item {
            width: parent.width
            height: 30 * 6 + panel.grow
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
                    spacing: 2
                    Repeater {
                        model: rowsModel
                        delegate: Item {
                            id: row
                            required property int index
                            required property int actor
                            required property string name
                            required property string job
                            required property bool me
                            required property real cp
                            required property real gs
                            required property real value
                            required property real perSecond
                            required property real share
                            width: parent.width
                            height: 28
                            Rectangle { anchors.fill: parent; color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.035) }
                            // The bar in the class's colour, fading in to the right.
                            Rectangle {
                                id: dmgBar
                                height: parent.height
                                width: parent.width * Math.max(0, Math.min(1, value / panel.most))
                                readonly property color base: panel.classColour(job)
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: panel.tint(dmgBar.base, 0.32) }
                                    GradientStop { position: 1; color: panel.tint(dmgBar.base, 0.68) }
                                }
                            }
                            Rectangle { visible: me; width: 2; height: parent.height; color: Theme.accent }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: rank
                                x: 4
                                width: 12
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: index + 1
                                color: Theme.dim()
                                font.family: Theme.body
                                font.pixelSize: 10
                            }
                            Image {
                                id: classPicture
                                anchors.left: rank.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                sourceSize: Qt.size(36, 36)
                                fillMode: Image.PreserveAspectFit
                                source: panel.classIcon(job)
                                Accessible.ignored: true
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: nameText
                                anchors.left: classPicture.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, perSecondText.x - x - 8 - (cpText.visible ? Math.min(cpText.implicitWidth + 6, 90) : 0))
                                elide: Text.ElideRight
                                text: name
                                color: me ? Theme.accent : Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: cpText
                                visible: cp > 0 && !panel.narrow
                                anchors.left: nameText.right
                                anchors.leftMargin: 6
                                anchors.right: perSecondText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: panel.brief(cp) + (gs > 0 ? " · " + panel.number(gs) : "")
                                color: panel.cpColour
                                font.family: Theme.body
                                font.pixelSize: 10
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: perSecondText
                                anchors.right: shareText.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.brief(perSecond) + "/s"
                                color: perSecond > 0 ? Theme.text() : Theme.dim()
                                font.family: Theme.display
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: shareText
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                horizontalAlignment: Text.AlignRight
                                text: share.toFixed(1) + "%"
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !Companion.locked && Aion2.opened.length === 0
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: { Aion2.pick(me ? 0 : actor); panel.tab = "skills" }
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: name + ", " + job + ", " + perSecondText.text + (panel.healing ? " healing" : " damage") + ", " + shareText.text
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
                            topPadding: 14
                            bottomPadding: 14
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: (Aion2.opened.length > 0 ? "Nothing was counted in this fight."
                                : Aion2.state === "failed" ? "Cannot read the game: " + Aion2.problem
                                : Aion2.state === "off" ? "Starts by itself when AION 2 runs."
                                : Aion2.state === "searching" ? "Looking for the game's connection…"
                                : "Waiting for the first hit.") + "\nListens only. Never sends anything to the game."
                            color: Aion2.state === "failed" && Aion2.opened.length === 0 ? Theme.red : Theme.muted()
                            font.family: Theme.body
                            font.pixelSize: 12
                        }
                        TextButton {
                            id: retry
                            visible: Aion2.state === "failed" && Aion2.opened.length === 0
                            anchors.top: stateText.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: 24
                            pixelSize: 11
                            text: "Try again"
                            onClicked: if (!Companion.locked) { Aion2.stop(); Aion2.start() }
                        }
                    }
                }

                // SKILLS: the picked player's skills, with their pictures.
                Column {
                    visible: panel.tab === "skills"
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: panel.tab === "skills" ? panel.skills : []
                        delegate: Item {
                            required property var modelData
                            width: parent.width
                            height: 24
                            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.035) }
                            Rectangle {
                                height: parent.height
                                width: parent.width * Math.max(0, Math.min(1, modelData.damage / Math.max(1, panel.mostSkill)))
                                id: skillBar
                                readonly property color base: panel.classColour(panel.pickedRow ? panel.pickedRow.job : "")
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: panel.tint(skillBar.base, 0.25) }
                                    GradientStop { position: 1; color: panel.tint(skillBar.base, 0.55) }
                                }
                            }
                            Item {
                                id: skillPictureBox
                                x: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                readonly property string picture: panel.skillPicture(modelData.icon || "")
                                Rectangle {
                                    anchors.fill: parent
                                    visible: skillPictureBox.picture.length === 0
                                    color: Theme.trackDark
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    border.width: 1
                                }
                                HudIcon {
                                    anchors.centerIn: parent
                                    visible: skillPictureBox.picture.length === 0
                                    name: modelData.icon === "basic" ? "swords" : "wand"
                                    size: 13
                                    lineWidth: 2
                                    color: Theme.muted()
                                }
                                Image {
                                    anchors.fill: parent
                                    visible: skillPictureBox.picture.length > 0
                                    source: skillPictureBox.picture
                                    sourceSize: Qt.size(40, 40)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.left: skillPictureBox.right
                                anchors.leftMargin: 6
                                anchors.right: casts.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData.name
                                color: Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 12
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: casts
                                anchors.right: parent.right
                                anchors.rightMargin: 166
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.casts
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 11
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.right: parent.right
                                anchors.rightMargin: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.number(modelData.damage)
                                color: Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.right: parent.right
                                anchors.rightMargin: 52
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.crit > 0 ? Math.round(modelData.crit) + "%" : "–"
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 11
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.share.toFixed(1) + "%"
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 11
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.name + ", " + modelData.casts + " casts, " + panel.number(modelData.damage) + " damage"
                        }
                    }
                    Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                        visible: panel.skills.length === 0
                        width: parent.width
                        topPadding: 14
                        bottomPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: Aion2.opened.length > 0 ? "Skills are shown for the live fight."
                            : "No skills counted yet. A click on a player in Damage shows theirs."
                        wrapMode: Text.Wrap
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                }

                // HISTORY: the saved boss fights, newest first (a click shows one).
                Column {
                    visible: panel.tab === "history"
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: panel.tab === "history" ? panel.history.slice(0, 30) : []
                        delegate: Item {
                            required property var modelData
                            readonly property bool current: modelData.id === Aion2.opened
                            width: parent.width
                            height: 28
                            Rectangle {
                                anchors.fill: parent
                                color: current ? Qt.rgba(0.878, 0.647, 0.149, 0.18) : (fightMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.035))
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: kindText
                                x: 8
                                width: 36
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.train ? "TRAIN" : "BOSS"
                                color: modelData.train ? Theme.dim() : Theme.accent
                                font.family: Theme.display
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: bossText
                                anchors.left: kindText.right
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, (dpsText.x - x) * 0.6)
                                elide: Text.ElideRight
                                text: modelData.boss.length > 0 ? modelData.boss : "Unknown target"
                                color: current ? Theme.accent : Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.left: bossText.right
                                anchors.leftMargin: 8
                                anchors.right: dpsText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: panel.when(modelData.start) + " · " + panel.clock(modelData.duration)
                                color: Theme.dim()
                                font.family: Theme.body
                                font.pixelSize: 10
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: dpsText
                                visible: !panel.narrow
                                anchors.right: totalText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? implicitWidth : 0
                                text: modelData.duration > 0 ? panel.brief(modelData.total / modelData.duration * 1000) + "/s" : ""
                                color: Theme.muted()
                                font.family: Theme.body
                                font.pixelSize: 10
                            }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                id: totalText
                                anchors.right: removeButton.left
                                anchors.rightMargin: 2
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
                                width: 24
                                height: 24
                                HudIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 10
                                    lineWidth: 2.2
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
                        topPadding: 14
                        bottomPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Boss fights are kept here (on this computer only)."
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                    }
                }
                }
            }
            WheelScroll { flick: listFlick; step: 30 * 3 }
        }

        Item { width: 1; height: 6 }
        Rectangle { width: parent.width + 16; x: -8; height: 1; color: Theme.divider }

        // Foot: the fight's time and totals; Odyle, ping, party, opacity.
        Item {
            width: parent.width
            height: 22
            Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                color: Aion2.state === "reading" ? Theme.accent : Aion2.state === "failed" ? Theme.red : Theme.track
                Accessible.role: Accessible.StaticText
                Accessible.name: "Listens only. Never sends anything to the game."
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                anchors.left: dot.right
                anchors.leftMargin: 7
                anchors.right: liveInfo.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: panel.tab === "history"
                    ? panel.history.length + (panel.history.length === 1 ? " fight saved" : " fights saved")
                    : "<b><font color='" + Theme.accent + "'>" + panel.clock(panel.fight.time) + "</font></b>"
                      + (panel.totalAmount > 0 ? " · " + panel.brief(panel.totalDps) + "/s · " + panel.brief(panel.totalAmount) : "")
                color: Theme.muted()
                font.family: Theme.body
                font.pixelSize: 11
            }
            // Odyle energy (basic, + charged) and the ping, as in the old meter.
            Row {
                id: liveInfo
                anchors.right: partyText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Image {
                    visible: odyleText.visible
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13
                    height: 13
                    sourceSize: Qt.size(26, 26)
                    source: panel.assets + "odyle.png"
                    Accessible.ignored: true
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    id: odyleText
                    visible: !!panel.extras.odyle && Aion2.opened.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: panel.extras.odyle
                        ? panel.extras.odyle[0].toLocaleString(Qt.locale("en_US"), "f", 0)
                          + " <font color='" + Theme.purpleText + "'>(+" + panel.extras.odyle[1].toLocaleString(Qt.locale("en_US"), "f", 0) + ")</font>"
                        : ""
                    color: Theme.text()
                    font.family: Theme.body
                    font.pixelSize: 11
                    Accessible.name: "Odyle energy " + text
                }
                Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                    visible: panel.extras.ping !== null && panel.extras.ping !== undefined && Aion2.opened.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.extras.ping + " ms"
                    color: panel.extras.ping > 150 ? Theme.red : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 11
                }
            }
            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                id: partyText
                anchors.right: opacityButton.left
                anchors.rightMargin: panel.narrow ? 0 : 8
                width: panel.narrow ? 0 : implicitWidth
                visible: !panel.narrow
                anchors.verticalCenter: parent.verticalCenter
                text: "PARTY · " + panel.fight.rows.filter((r) => !r.others).length
                color: Theme.dim()
                font.family: Theme.display
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }
            // The ground's opacity: a short list opening upwards (100 to 10 %).
            TextButton {
                id: opacityButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 16
                pixelSize: 10
                pad: 4
                text: panel.opacityPercent + "% " + (opacityList.visible ? "▴" : "▾")
                onClicked: opacityList.visible = !opacityList.visible
            }
            Rectangle {
                id: opacityList
                visible: false
                z: 50
                anchors.right: parent.right
                anchors.bottom: opacityButton.top
                anchors.bottomMargin: 2
                width: 56
                height: opacityColumn.height + 2
                color: "#16151b"
                border.color: Theme.divider
                Column {
                    id: opacityColumn
                    x: 1
                    y: 1
                    width: parent.width - 2
                    Repeater {
                        model: [100, 75, 50, 25, 10]
                        delegate: Item {
                            required property int modelData
                            width: opacityColumn.width
                            height: 20
                            Rectangle { anchors.fill: parent; color: optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent" }
                            Rectangle { visible: parent.modelData === panel.opacityPercent; width: 2; height: parent.height; color: Theme.accent }
                            Text { style: Theme.textStyle(); styleColor: Theme.shadow;
                                anchors.centerIn: parent
                                text: parent.modelData + " %"
                                color: parent.modelData === panel.opacityPercent ? Theme.accent : Theme.textSoft()
                                font.family: Theme.display
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.opacityPercent = parent.modelData
                                    Streams.saveOpacity("dps", parent.modelData)
                                    opacityList.visible = false
                                }
                            }
                            Accessible.role: Accessible.MenuItem
                            Accessible.name: modelData + " percent"
                        }
                    }
                }
            }
        }
    }

    component DpsTab: Item {
        property string name
        property string label
        readonly property bool current: panel.tab === name
        width: tabText.implicitWidth
        height: 30
        Text { style: Theme.textStyle(); styleColor: Theme.shadow;
            id: tabText
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label.toUpperCase()
            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
            font.family: Theme.display
            font.pixelSize: 11
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
