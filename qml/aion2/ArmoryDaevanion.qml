import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// DAEVANION: the offensive stats still behind closed nodes, per board, and
// each board's map with the cheapest way to a node. Improved: the build's
// nodes come first (its closed ones nearest first, with their way), the
// map marks them, and the table says what the build takes per stat.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    readonly property var targets: ui ? ui.targets : BK.emptyTargets()
    property string boardName: ""
    property var pick: null
    property bool all: false
    spacing: 8

    readonly property var sides: [["pve", "PvE and bosses"], ["pvp", "PvP"], ["all", "Both"]]
    readonly property string side: { if (!ui) return "pve"; ui.rev; const s = ui.store.state.settings.daevSide; return ["pve", "pvp", "all"].indexOf(s) >= 0 ? s : "pve" }
    readonly property var boards: { if (!ui) return []; ui.rev; return snap ? (snap.boards || []).filter((b) => b.nodes && b.nodes.length) : [] }
    readonly property var refDaev: build && build.ref ? build.ref.daev || {} : ({})
    readonly property var refIds: { const s = new Set(); for (const k in refDaev) for (const id of refDaev[k] || []) s.add(id); return s }
    readonly property bool hasRef: refIds.size > 0
    readonly property var rows: boards.length ? ck.boardOffense(boards, side, hasRef ? refIds : null) : []
    readonly property var closedRows: rows.filter((r) => r.nodes)
    function offOf(b) { return ck.boardWays(b).filter((n) => !n.open && ck.nodeOffense(n, side).length) }
    readonly property var allOff: { let out = []; for (const b of boards) out = out.concat(offOf(b)); return out }
    readonly property var withClosed: boards.filter((b) => closedRows.some((r) => r.boards[b.name]))
    readonly property var board: {
        const b = boards.find((x) => x.name === boardName)
        if (b) return b
        return boards.length ? boards.slice().sort((a, c) => offOf(c).reduce((s, n) => s + n.points, 0) - offOf(a).reduce((s, n) => s + n.points, 0))[0] : null
    }
    readonly property var ways: board ? ck.boardWays(board) : []
    readonly property var byId: { const m = {}; for (const n of ways) m[n.id] = n; return m }
    readonly property var mine: board ? new Set((refDaev[String(board.id)] || [])) : new Set()
    function isRef(n) { return mine.has(n.id) }
    readonly property var picked: pick != null && byId[pick] ? byId[pick] : null
    readonly property var onWay: picked && !picked.open ? new Set(picked.path) : new Set()

    function val(v, pct) { return "+" + ui.fmt(v, 2) + (pct ? " %" : "") }
    function nodeText(n) {
        if (n.type === "Start") return "Start"
        if (n.skill) return n.skill.name + " +" + n.skill.gives
        return (n.effects || []).join(", ") || n.name || "?"
    }
    function setSide(k) { ui.store.state.settings.daevSide = k; ui.store.changed() }
    function kindOf(n) { return n.type === "Start" ? "start" : n.skill ? "skill" : ck.nodeOffense(n, side).length ? "off" : "other" }

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }
    AUi.Note { visible: !!tab.snap && !tab.boards.length; width: parent.width; text: "No Daevanion board read: Update reads them again." }

    Item {
        visible: tab.boards.length > 0
        width: parent.width
        height: 26
        AUi.Title {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - sideRow.width - 10
            text: tab.closedRows.length ? tab.closedRows.length + " offensive stats still have closed nodes: " + tab.allOff.length + " nodes, " + tab.allOff.reduce((a, n) => a + n.points, 0) + " points" : "✓ Every offensive node is open"
            color: tab.closedRows.length ? Theme.text() : "#7fdc9a"
        }
        Row {
            id: sideRow
            anchors.right: parent.right
            spacing: 6
            Repeater {
                model: tab.sides
                delegate: Chip { required property var modelData; text: modelData[1]; on: tab.side === modelData[0]; onClicked: tab.setSide(modelData[0]) }
            }
        }
    }
    AUi.Note {
        visible: tab.boards.length > 0
        width: parent.width
        text: "Offensive: what makes your hits land, hit harder or come faster (Attack, Accuracy, Critical Hit, Combat Speed, Cooldown, Penetration, Boosts, Multi-hit, Perfect and Double). “PvE and bosses” leaves out what counts against characters only."
    }

    // ---- every offensive stat ----
    Column {
        visible: tab.rows.length > 0
        width: parent.width
        spacing: 0
        readonly property var cols: [["STAT", 170], ["OPEN", 70]].concat(tab.hasRef ? [["BUILD", 70]] : []).concat([["STILL CLOSED", 90], ["NODES", 50], ["POINTS", 54], ["NEAREST", 60]])
        readonly property int boardW: Math.max(54, Math.floor((width - cols.reduce((a, c) => a + c[1], 0)) / Math.max(1, tab.withClosed.length)))
        Row {
            Repeater { model: parent.parent.cols; delegate: AUi.Head { required property var modelData; width: modelData[1]; text: modelData[0]; font.pixelSize: 10 } }
            Repeater { model: tab.withClosed; delegate: AUi.Head { required property var modelData; width: parent.parent.boardW; text: modelData.name.toUpperCase(); font.pixelSize: 10 } }
        }
        Repeater {
            model: tab.rows
            delegate: Row {
                required property var modelData
                readonly property var r: modelData
                height: 20
                opacity: r.nodes ? 1 : 0.6
                AUi.Line { width: 170; text: r.name; font.pixelSize: 11 }
                AUi.Line { width: 70; text: r.have ? tab.val(r.have, r.pct) : "—"; color: r.have ? Theme.text() : Theme.dim(); font.pixelSize: 11 }
                AUi.Line { visible: tab.hasRef; width: 70; text: r.ref ? tab.val(r.ref, r.pct) : "—"; color: r.ref > r.have ? Theme.accentLight : Theme.dim(); font.pixelSize: 11 }
                AUi.Line { width: 90; text: r.nodes ? tab.val(r.closed, r.pct) : "✓ all open"; color: r.nodes ? Theme.accent : "#7fdc9a"; font.pixelSize: 11 }
                AUi.Line { width: 50; text: r.nodes || ""; font.pixelSize: 11 }
                AUi.Line { width: 54; text: r.points || ""; font.pixelSize: 11 }
                AUi.Line { width: 60; text: r.cheapest != null ? r.cheapest + " pt" : ""; font.pixelSize: 11 }
                Repeater {
                    model: tab.withClosed
                    delegate: AUi.Line { required property var modelData; width: parent.parent.parent.boardW; text: r.boards[modelData.name] ? tab.val(r.boards[modelData.name], r.pct) : ""; color: Theme.dim(); font.pixelSize: 11 }
                }
            }
        }
    }

    // ---- one board ----
    Flow {
        visible: tab.boards.length > 0
        width: parent.width
        spacing: 6
        Repeater {
            model: tab.boards
            delegate: Chip {
                required property var modelData
                readonly property int n: tab.offOf(modelData).length
                text: modelData.name + " " + modelData.points + "/" + modelData.maxPoints + (n ? " · " + n + " offensive" : "")
                on: !!tab.board && tab.board.name === modelData.name
                onClicked: { tab.boardName = modelData.name; tab.pick = null }
            }
        }
    }

    Row {
        visible: !!tab.board
        width: parent.width
        spacing: 14

        // The map.
        Column {
            id: mapCol
            readonly property int cell: 24
            readonly property int r0: tab.ways.length ? Math.min(...tab.ways.map((n) => n.row)) : 0
            readonly property int c0: tab.ways.length ? Math.min(...tab.ways.map((n) => n.col)) : 0
            readonly property int w: tab.ways.length ? (Math.max(...tab.ways.map((n) => n.col)) - c0 + 1) * cell : 0
            readonly property int h: tab.ways.length ? (Math.max(...tab.ways.map((n) => n.row)) - r0 + 1) * cell : 0
            width: Math.max(w, 220)
            spacing: 6
            Item {
                width: mapCol.w
                height: mapCol.h
                Repeater {
                    model: tab.ways
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var n: modelData
                        readonly property string kind: tab.kindOf(n)
                        readonly property bool way: tab.onWay.has(n.id)
                        readonly property bool isPick: !!tab.picked && tab.picked.id === n.id
                        x: (n.col - mapCol.c0) * mapCol.cell + 2
                        y: (n.row - mapCol.r0) * mapCol.cell + 2
                        width: mapCol.cell - 4
                        height: mapCol.cell - 4
                        radius: kind === "start" ? 10 : 2
                        color: kind === "start" ? Qt.rgba(1, 1, 1, 0.75) : isPick ? Qt.rgba(1, 1, 1, 0.3)
                            : n.open ? (kind === "off" ? Qt.rgba(242 / 255, 196 / 255, 107 / 255, 0.55) : kind === "skill" ? Qt.rgba(195 / 255, 155 / 255, 1, 0.5) : Qt.rgba(1, 1, 1, 0.16))
                            : Qt.rgba(1, 1, 1, 0.03)
                        border.width: kind === "start" || (n.open && !isPick && !way) ? 0 : (isPick || way || nodeMouse.containsMouse ? 2 : 1)
                        border.color: isPick || way || nodeMouse.containsMouse ? "#ffffff" : kind === "off" ? Qt.rgba(242 / 255, 196 / 255, 107 / 255, 0.75) : kind === "skill" ? Qt.rgba(195 / 255, 155 / 255, 1, 0.75) : Qt.rgba(1, 1, 1, 0.18)
                        Text {
                            anchors.centerIn: parent
                            visible: !parent.n.open
                            text: parent.n.points
                            color: parent.kind === "off" ? "#f2c46b" : parent.kind === "skill" ? "#c39bff" : Qt.rgba(1, 1, 1, 0.4)
                            font.family: Theme.display
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Rectangle { visible: tab.isRef(parent.n); x: parent.width - 6; y: 1; width: 5; height: 5; radius: 2.5; color: "#ffffff"; border.color: Qt.rgba(0, 0, 0, 0.6) }
                        MouseArea { id: nodeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.pick = parent.n.id }
                    }
                }
            }
            Flow {
                width: Math.max(mapCol.w, 220)
                spacing: 10
                Repeater {
                    model: [[Qt.rgba(242 / 255, 196 / 255, 107 / 255, 0.55), "offensive"], [Qt.rgba(195 / 255, 155 / 255, 1, 0.5), "skill level"], [Qt.rgba(1, 1, 1, 0.16), "other"]].concat(tab.hasRef ? [["#ffffff", "• the build takes it"]] : [])
                    delegate: Row {
                        required property var modelData
                        spacing: 4
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: modelData[0] }
                        AUi.Line { text: modelData[1]; color: Theme.dim(); font.pixelSize: 10 }
                    }
                }
                AUi.Line { text: "filled: open · a number: closed, its points"; color: Theme.dim(); font.pixelSize: 10 }
            }
        }

        // The lists.
        Column {
            width: parent.width - mapCol.width - 14
            spacing: 6

            AUi.Box {
                visible: !!tab.picked
                width: parent.width
                AUi.Line { width: parent.width; text: tab.picked ? tab.nodeText(tab.picked) + "  · " + tab.picked.grade + " node, " + tab.picked.points + " pt" : ""; font.bold: true; elide: Text.ElideNone; wrapMode: Text.WordWrap }
                AUi.Line {
                    text: !tab.picked ? "" : tab.picked.open ? "✓ Open." : tab.picked.path.length === 1 ? "Next to an open one." : "The way from what is open: " + tab.picked.path.length + " nodes, " + tab.picked.cost + " points."
                    color: tab.picked && tab.picked.open ? "#7fdc9a" : Theme.muted()
                    font.pixelSize: 11
                }
                Repeater {
                    model: tab.picked && !tab.picked.open && tab.picked.path.length > 1 ? tab.picked.path.slice().reverse().map((id) => tab.byId[id]) : []
                    delegate: AUi.Line {
                        required property var modelData
                        width: parent.width
                        text: "· " + tab.nodeText(modelData) + " (" + modelData.points + " pt)"
                        color: modelData.offensive ? Theme.accentLight : modelData.skill ? "#c39bff" : Theme.muted()
                        font.pixelSize: 11
                    }
                }
            }

            NodeList {
                visible: tab.hasRef
                title: { const l = tab.ways.filter((n) => !n.open && tab.isRef(n)); return l.length ? "The build's nodes still closed: " + l.length + ", " + l.reduce((a, n) => a + n.points, 0) + " points" : "✓ Every node of the build is open here" }
                nodes: tab.ways.filter((n) => !n.open && tab.isRef(n)).sort((a, b) => a.cost - b.cost)
            }
            NodeList {
                title: { const l = tab.board ? tab.offOf(tab.board) : []; return l.length ? tab.board.name + ": offensive nodes still closed" : (tab.board ? tab.board.name + ": every offensive node open" : "") }
                nodes: { const l = tab.board ? tab.offOf(tab.board).sort((a, b) => a.cost - b.cost || b.points - a.points) : []; return tab.all ? l : l.slice(0, 12) }
                more: { const n = tab.board ? tab.offOf(tab.board).length : 0; return n > 12 ? (tab.all ? "Show the nearest only" : "Show all " + n) : "" }
                onMoreClicked: tab.all = !tab.all
            }
            NodeList {
                title: "Skill levels still closed"
                visible: nodes.length > 0
                nodes: tab.ways.filter((n) => n.skill && !n.open).sort((a, b) => a.cost - b.cost)
                skills: true
            }
            NodeList {
                visible: tab.hasRef && nodes.length > 0
                title: { const l = tab.ways.filter((n) => n.open && n.type !== "Start" && !tab.isRef(n)); return "You took, the build not: " + l.length + " nodes, " + l.reduce((a, n) => a + n.points, 0) + " points" }
                nodes: tab.ways.filter((n) => n.open && n.type !== "Start" && !tab.isRef(n))
                folded: true
            }
        }
    }
    AUi.Note {
        visible: tab.boards.length > 0
        width: parent.width
        text: "A node opens next to an open one, side by side. The way's points are every closed node on the cheapest way from what is open, the node itself included; the nodes on the way give their stats too."
    }

    component NodeList: Column {
        id: nl
        property string title
        property var nodes: []
        property bool skills: false
        property bool folded: false
        property string more: ""
        signal moreClicked
        width: parent ? parent.width : 0
        spacing: 1
        Item {
            width: parent.width
            height: 22
            AUi.Head { anchors.verticalCenter: parent.verticalCenter; width: parent.width; text: (nl.folded ? "▸ " : "") + nl.title.toUpperCase() }
            MouseArea { anchors.fill: parent; enabled: nl.nodes.length > 0; cursorShape: Qt.PointingHandCursor; onClicked: nl.folded = !nl.folded }
        }
        Repeater {
            model: nl.folded ? [] : nl.nodes
            delegate: Rectangle {
                required property var modelData
                readonly property var n: modelData
                readonly property var t: n.skill ? tab.targets.skills[n.skill.name] : null
                width: nl.width
                height: 22
                color: tab.picked && tab.picked.id === n.id ? Qt.rgba(224 / 255, 165 / 255, 38 / 255, 0.15) : (m.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                AUi.Line { x: 4; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 200; text: tab.nodeText(parent.n); color: parent.n.skill ? "#c39bff" : parent.n.offensive ? Theme.accentLight : Theme.text(); font.pixelSize: 11 }
                AUi.Line { x: parent.width - 192; anchors.verticalCenter: parent.verticalCenter; width: 80; text: parent.n.grade + " · " + parent.n.points + " pt"; color: Theme.dim(); font.pixelSize: 10 }
                AUi.Line {
                    x: parent.width - 108
                    anchors.verticalCenter: parent.verticalCenter
                    width: 104
                    horizontalAlignment: Text.AlignRight
                    text: parent.t ? "your target " + parent.t : parent.n.open ? "" : parent.n.path.length > 1 ? "way " + parent.n.cost + " pt, " + parent.n.path.length + " nodes" : "next to an open one"
                    color: parent.t ? Theme.accentLight : Theme.dim()
                    font.pixelSize: 10
                }
                MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.pick = parent.n.id }
            }
        }
        AUi.Line {
            visible: nl.more !== "" && !nl.folded
            text: nl.more
            color: Theme.accent
            font.pixelSize: 11
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nl.moreClicked() }
        }
    }
}
