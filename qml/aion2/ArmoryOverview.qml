import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// OVERVIEW (board AR1): the active build's progress per area and the next
// steps, cheapest first (ticked by themselves when a reading shows them
// done); beside it the old Overview's boxes: gear score piece by piece,
// Daevanion boards (the build's points as a white mark), titles, pet and
// wings. Improved over the old tab: the build is the first thing seen, a
// step opens the tab it belongs to, the boards show the build's aim.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var ch: ui ? ui.charRec : null
    readonly property var prices: ui && ui.store ? ui.store.prices : null
    spacing: 10

    readonly property var pr: { if (!ui) return null; ui.rev; return snap && build ? BK.progress(snap, build, ch, prices) : null }
    readonly property var next: { if (!ui) return []; ui.rev; return snap && build ? BK.steps(snap, build, ch, prices).sort((a, b) => a.order - b.order || ((a.kinah == null) - (b.kinah == null)) || (a.kinah || 0) - (b.kinah || 0)) : [] }
    readonly property var done: { if (!ui) return []; ui.rev; return build ? BK.recentDone(ch, build.id, Date.now()) : [] }
    readonly property var gs: { if (!ui) return null; ui.rev; return snap ? ck.gearScore(snap) : null }
    readonly property var refBoards: { if (!ui) return ({}); ui.rev; const m = {}; if (snap && build && build.ref) for (const b of ck.referenceBoards(build.ref, snap)) m[b.name] = b; return m }
    readonly property var partColours: ({ level: Qt.rgba(1, 1, 1, 0.55), enchant: "#ffffff", amplify: "#f2c46b", manastones: "#7fdc9a", theostones: "#ff9a7a", daevanion: "#c39bff" })
    readonly property var partNames: ({ level: "Item levels", enchant: "Enhance levels", amplify: "Amplify (5 each)", manastones: "Manastones", theostones: "Theostones", daevanion: "Daevanion points" })
    readonly property int half: Math.floor((width - 10) / 2)

    AUi.Note {
        visible: !tab.snap
        width: parent.width
        text: "Nothing read yet: play a character (it is read by itself), or look one up by name above."
    }

    // ---- the build ----
    Row {
        visible: !!tab.snap
        width: parent.width
        spacing: 10

        AUi.Box {
            width: tab.half
            AUi.Title { text: tab.build ? "Progress on " + tab.build.name : "No active build" }
            AUi.Note {
                visible: !tab.build
                width: parent.width
                text: "A build is what this character aims at: gear with its levels, soul bindings, skill levels, Daevanion nodes and a goal gear score. Make one in BUILDS (from questlog.gg, from a character, or the strongest players), and every tab measures against it."
            }
            Row {
                visible: !!tab.pr && tab.pr.total != null
                spacing: 10
                AUi.Figure { text: tab.pr && tab.pr.total != null ? Math.round(tab.pr.total * 100) + " %" : ""; color: Theme.accent; font.pixelSize: 30 }
                AUi.Note {
                    anchors.verticalCenter: parent.verticalCenter
                    width: tab.half - 110
                    text: "Every area with something to reach counts the same. The build's version " + (tab.build ? tab.build.version : "") + "; HISTORY shows how it went."
                }
            }
            AUi.Note {
                visible: !!tab.pr && tab.pr.total == null && !!tab.build
                width: parent.width
                text: "The build aims at nothing yet: give it gear, skill targets, soul binding wishes or a goal gear score."
            }
            Repeater {
                model: tab.pr ? tab.pr.areas : []
                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: 3
                    Item {
                        width: parent.width
                        height: 16
                        AUi.Line {
                            text: modelData.name
                            width: parent.width - pct.width - 8
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tab.ui.setTab(modelData.id === "goal" ? "goals" : modelData.id)
                            }
                        }
                        AUi.Line { id: pct; anchors.right: parent.right; text: modelData.text; color: modelData.p >= 1 ? "#7fdc9a" : Theme.muted(); font.pixelSize: 11 }
                    }
                    AUi.Bar { width: parent.width; value: modelData.p; colour: modelData.p >= 1 ? "#7fdc9a" : Theme.accent }
                }
            }
        }

        AUi.Box {
            width: tab.half
            AUi.Title { text: tab.next.length ? "Next steps" : (tab.build ? "Next steps: none" : "Next steps") }
            AUi.Note {
                visible: !tab.next.length
                width: parent.width
                text: tab.build ? "Everything the build asks for is reached (or left out)." : "With a build, the steps to it show here: free ones first, then the gear by Kinah a gear score point, then soul bindings."
            }
            Repeater {
                model: tab.next.slice(0, 7)
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 34
                    Rectangle { anchors.fill: parent; color: stepMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
                    Rectangle {
                        x: 0
                        y: 8
                        width: 6
                        height: 6
                        color: modelData.kind === "daevanion" ? "#c39bff" : modelData.kind === "skill" ? "#4fa8ff" : modelData.kind === "soul" ? "#f2c46b" : Theme.text()
                    }
                    AUi.Line { x: 14; y: 1; width: parent.width - 14 - cost.width - 6; text: modelData.what }
                    AUi.Line { x: 14; y: 17; width: parent.width - 14 - cost.width - 6; text: modelData.where; color: Theme.dim(); font.pixelSize: 11 }
                    Column {
                        id: cost
                        anchors.right: parent.right
                        y: 1
                        AUi.Line {
                            anchors.right: parent.right
                            text: modelData.kinah == null ? (modelData.kind === "gear" ? "cost ?" : "") : modelData.kinah === 0 ? "free" : tab.ui.brief(modelData.kinah) + " Kinah"
                            color: modelData.kinah === 0 ? "#7fdc9a" : Theme.text()
                            font.pixelSize: 11
                        }
                        AUi.Line {
                            anchors.right: parent.right
                            visible: modelData.gain > 0
                            text: "+" + modelData.gain + (modelData.kind === "daevanion" ? " points" : " GS")
                            color: Theme.accent
                            font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        id: stepMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.ui.setTab(modelData.kind === "skill" ? "skills" : modelData.kind === "gear" ? "gear" : modelData.kind)
                    }
                }
            }
            AUi.Line {
                visible: tab.next.length > 7
                text: (tab.next.length - 7) + " more in their tabs"
                color: Theme.dim()
                font.pixelSize: 11
            }
            AUi.Head { visible: tab.done.length > 0; text: "DONE SINCE YESTERDAY"; topPadding: 4 }
            Repeater {
                model: tab.done.slice(0, 5)
                delegate: AUi.Line {
                    required property var modelData
                    width: parent.width
                    text: "✓  " + modelData.what + "  · " + tab.ui.store.when(modelData.at)
                    color: "#7fdc9a"
                    font.pixelSize: 11
                }
            }
        }
    }

    // ---- the old Overview's boxes ----
    Row {
        visible: !!tab.snap
        width: parent.width
        spacing: 10

        AUi.Box {
            width: tab.half
            AUi.Title { text: "Gear score, piece by piece" }
            Row {
                width: parent.width
                height: 10
                Repeater {
                    model: tab.gs ? Object.keys(tab.gs.parts) : []
                    delegate: Rectangle {
                        required property string modelData
                        width: parent.width * tab.gs.parts[modelData] / Math.max(1, tab.gs.total)
                        height: 10
                        color: tab.partColours[modelData] || "#888"
                    }
                }
            }
            Grid {
                columns: 2
                columnSpacing: 16
                rowSpacing: 2
                Repeater {
                    model: tab.gs ? Object.keys(tab.gs.parts) : []
                    delegate: Row {
                        required property string modelData
                        spacing: 6
                        width: (tab.half - 36) / 2
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: tab.partColours[modelData] || "#888" }
                        AUi.Line { text: tab.partNames[modelData] || modelData; width: parent.width - 60; color: Theme.muted(); font.pixelSize: 11 }
                        AUi.Line { text: tab.ui.fmt(tab.gs.parts[modelData]); font.pixelSize: 11; font.bold: true }
                    }
                }
            }
            AUi.Line {
                text: {
                    if (!tab.gs) return ""
                    const own = tab.snap.profile && tab.snap.profile.gs
                    if (own == null) return "Sum " + tab.ui.fmt(tab.gs.total)
                    if (own === tab.gs.total) return "= " + tab.ui.fmt(tab.gs.total) + ", the game's own number"
                    return "Sum " + tab.ui.fmt(tab.gs.total) + "; the game says " + tab.ui.fmt(own) + " (" + tab.ui.plusMinus(own - tab.gs.total) + ", a part not read)"
                }
                color: tab.gs && tab.snap.profile && tab.snap.profile.gs === tab.gs.total ? "#7fdc9a" : Theme.accentLight
                font.pixelSize: 11
            }
            AUi.Note {
                width: parent.width
                text: "Each worn piece (Arcana too) counts its item level and enhance level; every Amplify level 5; Manastones 1 to 4 by grade; Theostones 3 (Rare) or 5 (Legend); every Daevanion point spent 1. Titles don't count."
            }
        }

        AUi.Box {
            width: tab.half
            AUi.Title { text: "Daevanion boards" }
            Repeater {
                model: tab.snap ? tab.snap.boards || [] : []
                delegate: Row {
                    required property var modelData
                    readonly property var r: tab.refBoards[modelData.name] || null
                    readonly property int max: modelData.maxPoints || (r ? r.total : 0) || 1
                    width: parent.width
                    spacing: 8
                    AUi.Line { anchors.verticalCenter: parent.verticalCenter; width: 84; text: modelData.name; font.pixelSize: 11 }
                    AUi.Bar {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 84 - 70 - 16
                        value: modelData.points / parent.max
                        mark: parent.r ? Math.min(1, parent.r.points / parent.max) : -1
                    }
                    AUi.Line {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        horizontalAlignment: Text.AlignRight
                        text: modelData.points + "/" + parent.max + (parent.r ? "  ▸" + parent.r.points : "")
                        font.pixelSize: 11
                    }
                }
            }
            AUi.Note {
                width: parent.width
                text: {
                    if (!tab.snap) return ""
                    const b = tab.snap.boards || []
                    const pts = b.reduce((a, x) => a + (x.points || 0), 0), max = b.reduce((a, x) => a + (x.maxPoints || 0), 0)
                    return tab.ui.fmt(pts) + " of " + tab.ui.fmt(max) + " points spent; each point is 1 gear score. A node costs 1 to 4 points by grade." + (Object.keys(tab.refBoards).length ? " White mark (▸): the build's points." : "")
                }
            }
        }
    }

    Row {
        visible: !!tab.snap
        width: parent.width
        spacing: 10

        AUi.Box {
            id: titleBox
            width: tab.half
            readonly property var t: tab.snap ? tab.snap.titles || {} : {}
            AUi.Title { text: "Titles · " + tab.ui.fmt(titleBox.t.owned || 0) + " of " + tab.ui.fmt(titleBox.t.total || 0) }
            Repeater {
                model: (titleBox.t.list || []).slice(0, 8)
                delegate: Column {
                    required property var modelData
                    width: parent.width
                    Row {
                        spacing: 6
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: tab.ui.gradeColour(modelData.grade) }
                        AUi.Line { text: modelData.name; color: tab.ui.gradeColour(modelData.grade) }
                        AUi.Line { text: "· " + modelData.category + " · " + modelData.owned + "/" + modelData.total; color: Theme.dim(); font.pixelSize: 11 }
                    }
                    AUi.Line {
                        visible: !!(modelData.equipStats && modelData.equipStats.length)
                        width: parent.width
                        x: 12
                        text: "Worn: " + (modelData.equipStats || []).join(", ")
                        color: Theme.muted()
                        font.pixelSize: 11
                    }
                }
            }
            AUi.Note { width: parent.width; text: "Titles add stats (combat power), not gear score." }
        }

        AUi.Box {
            width: tab.half
            AUi.Title { text: "Pet, wings and rankings" }
            Repeater {
                model: {
                    if (!tab.snap) return []
                    const out = []
                    if (tab.snap.pet) out.push(["Pet: " + tab.snap.pet.name, "Level " + tab.snap.pet.level, Theme.text()])
                    if (tab.snap.wing) out.push(["Wings: " + tab.snap.wing.name, "+" + tab.snap.wing.enchant, tab.ui.gradeColour(tab.snap.wing.grade)])
                    for (const r of tab.snap.rankings || []) out.push([r.name, "#" + tab.ui.fmt(r.rank) + " " + r.grade, Theme.text()])
                    if (!out.length) out.push(["Nothing on NC's page.", "", Theme.dim()])
                    return out
                }
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 18
                    AUi.Line { text: modelData[0]; color: modelData[2]; width: parent.width - v.width - 8 }
                    AUi.Line { id: v; anchors.right: parent.right; text: modelData[1]; font.bold: true }
                }
            }
        }
    }
}
