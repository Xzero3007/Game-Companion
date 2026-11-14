import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// One slot opened in GEAR: the piece's stats, stones and next enhance
// step, then Compare (its own file: Qt 6.4 crashed on an inline component
// made inside a Repeater's row).
Rectangle {
            id: det
            property var tab
            property var r: null
            readonly property var mine: r ? r.mine : null
            readonly property var refPiece: r ? r.ref : null
            readonly property string slot: r ? r.slot : ""
            readonly property var list: { tab.ui.rev; return (tab.targets.compare[slot] || []) }
            readonly property var pick: { tab.ui.rev; return (tab.targets.pick || {})[slot] || null }
            property var found: []
            color: "#24222a"
            implicitHeight: dcol.implicitHeight + 20

            function nextLine(it) {
                if (!it || it.arcana) return ""
                const et = tab.ck.enchantTable(it)
                const top = Math.min(it.maxEnchant || 0, et ? et.length : 0)
                if (et && it.enchant < top) {
                    const c = tab.ck.climb(et, it.enchant, it.enchant + 1).steps[0]
                    if (!c) return ""
                    return "Next +" + (it.enchant + 1) + ": " + Math.round(c.chance * 100) + " %" + (c.perFail ? " (+" + Math.round(c.perFail * 100) + " % a failure)" : "") + (c.loses ? ", a failure loses a level" : "")
                        + " · " + (c.kinahPerTry ? tab.ui.brief(c.kinahPerTry) + " Kinah + " : "") + tab.ui.matsText(c.matsPerTry) + " a try · on average " + tab.ui.fmt(c.tries, 1) + " tries" + (c.kinah ? ", " + tab.ui.brief(c.kinah) + " Kinah" : "")
                }
                const at = tab.ck.amplifyTable(it)
                const atop = Math.min(it.maxAmplify != null ? it.maxAmplify : 99, tab.ck.amplifyTop(it))
                if (at && (it.amplify || 0) < atop) {
                    const c2 = tab.ck.climb(at, it.amplify || 0, (it.amplify || 0) + 1).steps[0]
                    if (!c2) return ""
                    return "Next Amplify " + ((it.amplify || 0) + 1) + ": " + Math.round(c2.chance * 100) + " % (+" + Math.round(c2.perFail * 100) + " % a failure) · " + tab.ui.brief(c2.kinahPerTry) + " Kinah + " + tab.ui.matsText(c2.matsPerTry) + " a try · on average " + tab.ui.brief(c2.kinah) + " Kinah"
                }
                return top ? "At its top." : ""
            }
            // Compare's rows: yours enhanced on, the build's at the levels
            // set, then the items compared (best value first).
            readonly property var cmp: {
                tab.ui.rev
                if (!r) return []
                const t = tab.targets
                const out = []
                if (mine && mine.id && tab.ck.tops(mine).enchant) out.push({ kind: "mine", piece: Object.assign({}, mine, (t.mineAt || {})[slot] || {}) })
                if (refPiece && refPiece.id) out.push({ kind: "ref", piece: BK.refPieceAt(t, slot, refPiece), set: !!(t.levels || {})[slot] })
                const cands = []
                list.forEach((c, i) => { const p = BK.pieceOf(slot, c.id, c.enchant, c.amplify); if (p) cands.push({ kind: "cand", piece: p, idx: i }) })
                for (const x of out.concat(cands)) x.up = tab.ck.upgradeOf(mine, x.piece, tab.prices)
                cands.sort((a, b) => (a.up.perPoint == null) - (b.up.perPoint == null) || (a.up.perPoint || 0) - (b.up.perPoint || 0) || b.up.gain - a.up.gain)
                return out.concat(cands)
            }
            function isUsed(x) {
                if (x.kind === "mine") return !!pick && pick.kind === "mine"
                if (x.kind === "ref") return !pick || (pick.kind === "cand" && !list.some((c) => c.id === pick.id))
                return !!pick && pick.kind === "cand" && pick.id === x.piece.id
            }
            function use(x) {
                tab.ui.store.changeTargets(tab.ui.label(slot), (t) => {
                    if (x.kind === "ref") delete t.pick[slot]
                    else t.pick[slot] = x.kind === "mine" ? { kind: "mine" } : { kind: "cand", id: x.piece.id }
                })
            }
            function setLevels(x, lv) {
                if (x.kind === "mine") {
                    tab.ui.store.changeMine((m) => { if (lv.enchant === (mine.enchant || 0) && lv.amplify === (mine.amplify || 0)) delete m[slot]; else m[slot] = lv })
                } else if (x.kind === "ref") {
                    tab.ui.store.changeTargets(tab.ui.label(slot) + " levels", (t) => { if (lv.enchant === (refPiece.enchant || 0) && lv.amplify === (refPiece.amplify || 0)) delete t.levels[slot]; else t.levels[slot] = lv })
                } else {
                    tab.ui.store.changeTargets(tab.ui.label(slot) + " compared", (t) => { t.compare[slot] = list.map((c, j) => j === x.idx ? Object.assign({}, c, lv) : c) })
                }
            }
            function remove(x) {
                tab.ui.store.changeTargets(tab.ui.label(slot) + " compared", (t) => {
                    if (t.pick[slot] && t.pick[slot].kind === "cand" && t.pick[slot].id === x.piece.id) delete t.pick[slot]
                    const next = list.filter((c, j) => j !== x.idx)
                    if (next.length) t.compare[slot] = next; else delete t.compare[slot]
                })
            }
            function search(q) {
                q = q.trim()
                if (q.length < 2) { found = []; return }
                let ids = []
                for (const cat of (tab.catsOfSlot[slot] || [null])) ids = ids.concat(tab.ck.searchItems(q, cat, 12))
                found = ids.slice(0, 14)
            }
            function add(id) {
                const t0 = tab.ck.tops({ id: id })
                const same = refPiece && refPiece.id === id
                tab.ui.store.changeTargets(tab.ui.label(slot) + " compared", (t) => { t.compare[slot] = list.concat([{ id: id, enchant: same ? refPiece.enchant : t0.enchant, amplify: same ? refPiece.amplify : 0 }]) })
                found = []
                addField.text = ""
            }

            Column {
                id: dcol
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 6

                // The piece itself (the old Gear tab's card).
                Flow {
                    visible: !!det.mine
                    width: parent.width
                    spacing: 14
                    Repeater {
                        model: det.mine ? (det.mine.main || []).concat(det.mine.sub || []) : []
                        delegate: AUi.Line {
                            required property var modelData
                            text: modelData.name + " " + (modelData.min ? modelData.min + "–" + modelData.value : modelData.value) + (Number(modelData.extra) ? "  +" + modelData.extra : "")
                            color: Theme.muted()
                            font.pixelSize: 11
                        }
                    }
                }
                Flow {
                    visible: !!det.mine && ((det.mine.stones || []).length > 0 || det.mine.stoneSlots > 0 || (det.mine.subSkills || []).length > 0)
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: det.mine ? det.mine.stones || [] : []
                        delegate: Chip { required property var modelData; text: modelData.name + " " + modelData.value; dot: tab.ui.gradeColour(modelData.grade) }
                    }
                    Repeater {
                        model: det.mine ? Math.max(0, (det.mine.stoneSlots || 0) - (det.mine.stones || []).length) : 0
                        delegate: Chip { text: "empty slot" }
                    }
                    Repeater {
                        model: det.mine ? det.mine.subSkills || [] : []
                        delegate: Chip { required property var modelData; text: modelData.name + " +" + modelData.level; dot: "#4fa8ff" }
                    }
                }
                Repeater {
                    model: det.mine ? det.mine.theostones || [] : []
                    delegate: AUi.Note { required property var modelData; width: dcol.width; text: modelData.name + ": " + modelData.desc; color: tab.ui.gradeColour(modelData.grade) }
                }
                AUi.Line { visible: text !== ""; width: parent.width; text: det.nextLine(det.mine); color: Theme.accentLight; font.pixelSize: 11; elide: Text.ElideNone; wrapMode: Text.WordWrap }

                // Compare.
                Row {
                    spacing: 10
                    AUi.Title { anchors.verticalCenter: parent.verticalCenter; text: "Compare: " + tab.ui.label(det.slot) }
                    AUi.Line {
                        anchors.verticalCenter: parent.verticalCenter
                        text: det.mine ? "you have " + tab.ui.fmt(tab.ck.pieceGearScore(det.mine)) + " (IL " + det.mine.il + " + enhance " + (det.mine.enchant || 0) + " + Amplify 5 × " + (det.mine.amplify || 0) + ")" : "nothing worn there: you have 0"
                        color: Theme.muted()
                        font.pixelSize: 11
                    }
                }
                Row {
                    visible: det.cmp.length > 0
                    spacing: 0
                    Repeater {
                        model: [["ITEM", 210], ["LEVELS", 160], ["GS", 46], ["DIFF.", 50], ["AT +0", 50], ["EVEN FROM", 70], ["KINAH ⌀", 60], ["9 IN 10", 60], ["≈ CP", 56], ["", 80]]
                        delegate: AUi.Head { required property var modelData; width: modelData[1]; text: modelData[0]; font.pixelSize: 10 }
                    }
                }
                Repeater {
                    model: det.cmp
                    delegate: Row {
                        required property var modelData
                        readonly property var x0: modelData
                        readonly property var up: modelData.up
                        height: 34
                        spacing: 0
                        Row {
                            width: 210
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter
                            AUi.Icon { width: 26; height: 26; icon: x0.piece.icon || ""; grade: x0.piece.grade; rev: tab.ui.iconRev }
                            Column {
                                width: 176
                                AUi.Line { width: parent.width; text: x0.piece.name; color: tab.ui.gradeColour(x0.piece.grade); font.pixelSize: 11 }
                                AUi.Line {
                                    width: parent.width
                                    text: x0.kind === "mine" ? "yours, now " + tab.ui.levelText(det.mine) : x0.kind === "ref" ? "the build's" + (x0.set ? ", set (its own " + tab.ui.levelText(det.refPiece) + ")" : "") : x0.piece.grade + " · IL " + x0.piece.il
                                    color: Theme.dim()
                                    font.pixelSize: 10
                                }
                            }
                        }
                        AUi.LevelSet { kit: tab.ck; width: 160; anchors.verticalCenter: parent.verticalCenter; piece: x0.piece; min: x0.kind === "mine" ? det.mine : null; onPicked: (lv) => det.setLevels(x0, lv) }
                        AUi.Line { width: 46; anchors.verticalCenter: parent.verticalCenter; text: tab.ui.fmt(tab.ck.pieceGearScore(Object.assign({ il: x0.piece.il }, up.to))); font.pixelSize: 11 }
                        AUi.Line { width: 50; anchors.verticalCenter: parent.verticalCenter; text: tab.ui.plusMinus(up.gain); color: up.gain > 0 ? "#7fdc9a" : up.gain < 0 ? "#ff8a7a" : Theme.text(); font.pixelSize: 11 }
                        AUi.Line { width: 50; anchors.verticalCenter: parent.verticalCenter; text: up.same ? "—" : tab.ui.plusMinus(up.at0); font.pixelSize: 11 }
                        AUi.Line { width: 70; anchors.verticalCenter: parent.verticalCenter; text: up.same || !up.evenKnown ? "—" : up.even ? tab.ui.levelText(up.even) : "never"; font.pixelSize: 11 }
                        AUi.Line { width: 60; anchors.verticalCenter: parent.verticalCenter; text: up.cost.known ? tab.ui.brief(up.cost.kinah) : "?"; font.pixelSize: 11 }
                        AUi.Line { width: 60; anchors.verticalCenter: parent.verticalCenter; text: up.cost.known ? tab.ui.brief(up.cost.kinahP90) : "?"; font.pixelSize: 11 }
                        AUi.Line { width: 56; anchors.verticalCenter: parent.verticalCenter; text: up.gain ? tab.ui.plusMinus(Math.round(up.gain * tab.rate)) : "—"; font.pixelSize: 11 }
                        Row {
                            width: 80
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter
                            AUi.Line { visible: det.isUsed(x0); text: "✓ target"; color: Theme.accent; font.pixelSize: 11; font.bold: true }
                            Chip { visible: !det.isUsed(x0) && !!tab.build; text: "Use"; onClicked: det.use(x0) }
                            Chip { visible: x0.kind === "cand"; text: "×"; onClicked: det.remove(x0) }
                        }
                    }
                }
                Row {
                    spacing: 8
                    AUi.Field { id: addField; width: 260; placeholder: "Add an item to compare: its name …"; onEdited: (t) => det.search(t) }
                    AUi.Line { anchors.verticalCenter: parent.verticalCenter; visible: !tab.build; text: "With a build, “Use” makes a row this slot's target."; color: Theme.dim(); font.pixelSize: 11 }
                }
                Flow {
                    visible: det.found.length > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: det.found
                        delegate: Chip {
                            required property var modelData
                            readonly property var row: tab.ck.itemRow(modelData)
                            text: row[0] + " · " + row[1] + " · IL " + row[3]
                            dot: tab.ui.gradeColour(row[1])
                            onClicked: det.add(modelData)
                        }
                    }
                }
            }
        }
