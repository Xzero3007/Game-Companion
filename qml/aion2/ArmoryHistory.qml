import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "buildkit.js" as BK

// HISTORY (board AR4): every reading of NC's page and the game's own
// numbers while you play, as a chart (combat power, gear score and the
// active build's progress, a mark where the build got a new version) and
// as a list with what changed. New: the boss fights of the DPS meter
// beside the build, with the character's damage per second and how far
// the build was then. The chart is drawn once per change, nothing moves.
Column {
    id: tab
    property var ui
    readonly property var ck: ui ? ui.ck : null
    readonly property var snap: ui ? ui.snap : null
    readonly property var build: ui ? ui.build : null
    spacing: 10

    readonly property var h: { if (!ui) return []; ui.rev; return (ui.store.history || []).filter((e) => e && e.at) }
    readonly property var fights: {
        if (!ui || !snap || !build) return []
        ui.rev
        return BK.fightsOf(ui.store.fights, snap.profile.name, h, build.id)
    }
    readonly property var rows: {
        const out = []
        for (let i = h.length - 1; i >= 0 && out.length < 80; i--) {
            const e = h[i], prev = h[i - 1]
            let full = null
            for (let j = i - 1; j >= 0; j--) if (!h[j].live) { full = h[j]; break }
            out.push({ e: e, prev: prev || null, changes: e.live ? "In the game (the meter's reading)" : full ? (ck.historyChanges(full, e).join(" · ") || "—") : "First reading of NC's page" })
        }
        return out
    }
    onHChanged: chart.requestPaint()
    onBuildChanged: chart.requestPaint()

    AUi.Note { visible: !tab.snap; width: parent.width; text: "Nothing read yet." }
    AUi.Note {
        visible: !!tab.snap
        width: parent.width
        text: "Every reading of NC's page (Update, or by itself every 6 hours while you play) is kept when something changed; while you play, the game's own combat power and gear score are noted as they change."
    }

    // The old Clicktrough Armory's history (MN, 2026-11-14): taken over once
    // by itself, again with this button.
    Item {
        visible: !!tab.ui
        width: parent.width
        height: 26
        AUi.Line {
            anchors.left: parent.left
            anchors.right: oldButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: !tab.ui ? "" : tab.ui.store.meterBusy ? "Reading the old Armory's data …"
                : tab.ui.store.meterNote || "The old Armory's history, readings and references are taken over once by themselves."
            color: Theme.muted()
            font.pixelSize: 11
        }
        Chip {
            id: oldButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Take over the old Armory's data"
            onClicked: tab.ui.store.readMeter()
        }
    }

    AUi.Box {
        visible: tab.h.length > 0
        width: parent.width
        Row {
            spacing: 16
            Repeater {
                model: [["#ffffff", "Combat power"], ["#f2c46b", "Gear score"]].concat(tab.build ? [["#c39bff", "Progress on " + tab.build.name]] : [])
                delegate: Row {
                    required property var modelData
                    spacing: 5
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 2; color: modelData[0] }
                    AUi.Line { text: modelData[1]; color: Theme.muted(); font.pixelSize: 11 }
                }
            }
            AUi.Line { visible: !!tab.build; text: "┆ a new version of the build"; color: Theme.dim(); font.pixelSize: 11 }
        }
        Canvas {
            id: chart
            width: parent.width
            height: 190
            renderStrategy: Canvas.Immediate
            onWidthChanged: requestPaint()
            onPaint: {
                const g = getContext("2d")
                g.reset()
                const h = tab.h
                if (!h.length) return
                const W = width, H = height, L = 56, R = 56, T = 10, B = 20
                const t0 = h[0].at, t1 = Math.max(h[h.length - 1].seen || h[h.length - 1].at, t0 + 1)
                const x = (t) => L + (t - t0) / (t1 - t0) * (W - L - R)
                g.strokeStyle = "rgba(255,255,255,0.07)"
                g.lineWidth = 1
                for (let i = 0; i <= 4; i++) { const y = T + i * (H - T - B) / 4; g.beginPath(); g.moveTo(L, y); g.lineTo(W - R, y); g.stroke() }
                g.font = "11px Inter"
                const series = (key, colour, side, label, fmt, only) => {
                    const pts = h.filter((e) => isFinite(e[key]) && (!only || only(e)))
                    if (!pts.length) return
                    let lo = Math.min(...pts.map((e) => e[key])), hi = Math.max(...pts.map((e) => e[key]))
                    if (hi === lo) { lo -= 1; hi += 1 }
                    const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B)
                    g.strokeStyle = colour
                    g.lineWidth = 1.6
                    g.beginPath()
                    pts.forEach((e, i) => { if (i) g.lineTo(x(e.at), y(e[key])); else g.moveTo(x(e.at), y(e[key])); if (e.seen) g.lineTo(x(e.seen), y(e[key])) })
                    g.stroke()
                    if (pts.length === 1) { g.fillStyle = colour; g.fillRect(x(pts[0].at) - 2, y(pts[0][key]) - 2, 4, 4) }
                    if (side) {
                        g.fillStyle = colour
                        g.textAlign = side === "left" ? "left" : "right"
                        const tx = side === "left" ? 2 : W - 2
                        g.fillText(fmt(hi), tx, T + 9)
                        g.fillText(fmt(lo), tx, H - B)
                        g.fillText(label, tx, H - 4)
                    }
                }
                series("cp", "#ffffff", "left", "Combat power", (v) => tab.ui.brief(v))
                series("gs", "#f2c46b", "right", "Gear score", (v) => tab.ui.fmt(v))
                const b = tab.build
                if (b) {
                    series("p", "#c39bff", null, "", null, (e) => e.b === b.id)
                    // The build's new versions.
                    g.strokeStyle = "rgba(255,255,255,0.35)"
                    g.setLineDash ? g.setLineDash([3, 3]) : null
                    let last = null
                    for (const e of h) {
                        if (e.b !== b.id || !e.bv) continue
                        if (last != null && e.bv !== last) { g.beginPath(); g.moveTo(x(e.at), T); g.lineTo(x(e.at), H - B); g.stroke() }
                        last = e.bv
                    }
                }
            }
        }
    }

    // ---- boss fights beside the build ----
    AUi.Box {
        visible: !!tab.build && !!tab.snap
        width: parent.width
        AUi.Title { text: "Boss fights beside " + (tab.build ? tab.build.name : "the build") }
        AUi.Note {
            visible: !tab.fights.length
            width: parent.width
            text: "No boss fight of " + (tab.snap && tab.snap.profile ? tab.snap.profile.name : "this character") + " in the DPS meter's Battle History yet (fights saved from now on carry each player's damage)."
        }
        Row {
            visible: tab.fights.length > 0
            Repeater {
                model: [["BOSS", 260], ["WHEN", 130], ["DPS", 90], ["BUILD THEN", 110], ["VERSION", 80]]
                delegate: AUi.Head { required property var modelData; width: modelData[1]; text: modelData[0]; font.pixelSize: 10 }
            }
        }
        Repeater {
            model: tab.fights.slice(0, 20)
            delegate: Row {
                required property var modelData
                required property int index
                readonly property var older: tab.fights.slice(index + 1).find((f) => f.boss === modelData.boss) || null
                height: 20
                AUi.Line { width: 260; text: modelData.boss; font.pixelSize: 11 }
                AUi.Line { width: 130; text: tab.ui.store.when(modelData.at); color: Theme.muted(); font.pixelSize: 11 }
                AUi.Line {
                    width: 90
                    text: tab.ui.fmt(modelData.dps) + (parent.older ? (modelData.dps >= parent.older.dps ? " ▲" : " ▼") : "")
                    color: parent.older ? (modelData.dps >= parent.older.dps ? "#7fdc9a" : "#ff8a7a") : Theme.text()
                    font.pixelSize: 11
                    font.bold: true
                }
                AUi.Line { width: 110; text: modelData.p != null ? tab.ui.fmt(modelData.p, 1) + " %" : "—"; color: "#c39bff"; font.pixelSize: 11 }
                AUi.Line { width: 80; text: modelData.v != null ? "v" + modelData.v : "—"; color: Theme.dim(); font.pixelSize: 11 }
            }
        }
        AUi.Note {
            visible: tab.fights.length > 0
            width: parent.width
            text: "▲ ▼ against the last fight with the same boss. Build then: its progress at the last reading before the fight."
        }
    }

    // ---- the readings ----
    Row {
        visible: tab.rows.length > 0
        Repeater {
            model: [["WHEN", 150], ["COMBAT POWER", 120], ["GEAR SCORE", 100], ["BUILD", 70], ["WHAT CHANGED", 400]]
            delegate: AUi.Head { required property var modelData; width: modelData[1]; text: modelData[0]; font.pixelSize: 10 }
        }
    }
    Repeater {
        model: tab.rows
        delegate: Row {
            required property var modelData
            readonly property var e: modelData.e
            readonly property var prev: modelData.prev
            Column {
                width: 150
                AUi.Line { text: tab.ui.store.when(parent.parent.e.at); font.pixelSize: 11 }
                AUi.Line { visible: !!parent.parent.e.seen; text: "same until " + tab.ui.store.when(parent.parent.e.seen); color: Theme.dim(); font.pixelSize: 10 }
            }
            Column {
                width: 120
                AUi.Line { text: tab.ui.fmt(e.cp); font.pixelSize: 11 }
                AUi.Line {
                    visible: !!prev && e.cp != null && prev.cp != null && e.cp !== prev.cp
                    text: prev ? tab.ui.plusMinus(e.cp - prev.cp) : ""
                    color: prev && e.cp > prev.cp ? "#7fdc9a" : "#ff8a7a"
                    font.pixelSize: 10
                }
            }
            Column {
                width: 100
                AUi.Line { text: tab.ui.fmt(e.gs); color: Theme.accentLight; font.pixelSize: 11 }
                AUi.Line {
                    visible: !!prev && e.gs !== prev.gs && e.gs != null && prev.gs != null
                    text: prev ? tab.ui.plusMinus(e.gs - prev.gs) : ""
                    color: prev && e.gs > prev.gs ? "#7fdc9a" : "#ff8a7a"
                    font.pixelSize: 10
                }
            }
            AUi.Line { width: 70; text: e.p != null && tab.build && e.b === tab.build.id ? tab.ui.fmt(e.p, 1) + " %" : ""; color: "#c39bff"; font.pixelSize: 11 }
            AUi.Note { width: tab.width - 440; text: modelData.changes; color: Theme.muted(); font.pixelSize: 11 }
        }
    }
}
