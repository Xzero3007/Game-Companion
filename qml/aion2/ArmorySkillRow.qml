import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// One skill's row in SKILLS (its own file: Qt 6.4 crashed on an inline
// component made by a Repeater inside another).
Rectangle {
            id: row
            property var tab
            required property var modelData
            readonly property var s: modelData
            readonly property var target: tab.targets.skills[s.name] != null ? tab.targets.skills[s.name] : null
            readonly property var topL: tab.topLevels[s.name]
            readonly property bool reached: target != null && s.level >= target
            width: tab.width
            height: 46
            color: "#1b1a20"
            function w(v) { return Math.max(0, Math.min(v, tab.span)) / tab.span }
            Row {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                AUi.Icon { anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; icon: row.s.icon || ""; rev: tab.ui.iconRev }
                Column {
                    width: 160
                    anchors.verticalCenter: parent.verticalCenter
                    AUi.Line { width: parent.width; text: row.s.name }
                    AUi.Line {
                        width: parent.width
                        text: (row.s.equipped && row.s.category !== "Passive" ? "in use" : "") + (row.s.refSpec && row.s.refSpec.length ? (row.s.equipped ? " · " : "") + "spec " + row.s.refSpec.join(" ") : "")
                        color: Theme.dim()
                        font.pixelSize: 10
                    }
                }
                Column {
                    width: 46
                    anchors.verticalCenter: parent.verticalCenter
                    AUi.Figure { text: row.s.level; color: row.reached ? "#7fdc9a" : Theme.text() }
                    AUi.Line { visible: row.s.refLevel != null; text: "build " + row.s.refLevel; color: row.s.refLevel > row.s.level ? Theme.accentLight : Theme.dim(); font.pixelSize: 10 }
                }
                Column {
                    width: 96
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        visible: row.target != null
                        spacing: 4
                        AUi.Stepper {
                            value: row.target || 0
                            from: row.s.category === "Dp" ? 1 : 10
                            to: row.s.category === "Dp" ? 20 : 30
                            onChanged: (v) => tab.setTarget(row.s.name, v)
                        }
                        AUi.Line { anchors.verticalCenter: parent.verticalCenter; text: "×"; color: Theme.dim(); MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: tab.setTarget(row.s.name, 0) } }
                    }
                    Chip { visible: row.target == null && !!tab.build; text: "Aim"; onClicked: tab.setTarget(row.s.name, tab.startFor(row.s)) }
                    AUi.Line {
                        visible: !!row.topL && row.topL.median > 0
                        text: row.topL ? "top " + tab.ui.fmt(row.topL.median, 1) : ""
                        color: Theme.dim()
                        font.pixelSize: 10
                    }
                }
                // Where the level comes from.
                Column {
                    width: 150
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.s.category !== "Dp"
                    spacing: 3
                    Item {
                        width: parent.width
                        height: 8
                        Rectangle { anchors.fill: parent; color: Theme.trackDark }
                        Rectangle { width: parent.width * row.w(row.s.base); height: parent.height; color: Qt.rgba(1, 1, 1, 0.5) }
                        Rectangle { x: parent.width * row.w(row.s.base); width: parent.width * (row.w(row.s.base + row.s.fromDaev) - row.w(row.s.base)); height: parent.height; color: tab.purple }
                        Rectangle { x: parent.width * row.w(row.s.base + row.s.fromDaev); width: parent.width * (row.w(row.s.base + row.s.fromDaev + row.s.fromGear) - row.w(row.s.base + row.s.fromDaev)); height: parent.height; color: "#f2c46b" }
                        Repeater {
                            model: [10, 14, 20].filter((m) => m < tab.span)
                            delegate: Rectangle { required property int modelData; x: parent.width * row.w(modelData); width: 1; height: parent.height; color: "#0c0c0f" }
                        }
                        Rectangle { visible: row.s.refLevel != null; x: parent.width * row.w(row.s.refLevel || 0) - 1; y: -2; width: 2; height: 12; color: "#ffffff" }
                        Rectangle { visible: row.target != null; x: parent.width * row.w(row.target || 0) - 1; y: -3; width: 3; height: 14; color: Theme.accent }
                    }
                    AUi.Line { text: row.s.base + " + " + row.s.fromDaev + " + " + row.s.fromGear; color: Theme.dim(); font.pixelSize: 10 }
                }
                AUi.Note {
                    width: tab.width - 8 - 28 - 160 - 46 - 96 - 150 - 6 * 8 - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.hint(row.s, row.target)
                    color: row.reached ? "#7fdc9a" : Theme.dim()
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: 10
                }
            }
        }
