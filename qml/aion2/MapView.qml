import QtQuick
import "../theme.js" as Theme
import "mapkit.js" as MK

// The map itself (the Map plugin's MapView, drawn in QML): the map's tiles
// as pictures (the small copies always, the sharp ones on top once zoomed
// in) and the marks on a canvas above them. World units are centimetres; a
// map's pixel is offset + scale * world (no flip, no rotation). Nothing is
// drawn while nothing changes.
Item {
    id: view
    clip: true

    /// The map shown (a key of the tables' maps), "" for none.
    property string mapKey: ""
    readonly property var map: mapKey.length > 0 ? MK.D.maps[mapKey] : null
    /// What to draw: the marks marks.js builds.
    property var marks: []
    /// How large the marks are drawn (1 = as designed).
    property real markScale: 1.25
    /// The pictures' folder (Aion2.mapDir()).
    property string dir: ""
    /// Whether it can be dragged, zoomed and clicked.
    property bool interactive: true
    /// How solid the map's pictures are (the overlay map: the marks stay solid).
    property real tileOpacity: 1
    /// Whether a drag moves the map (the overlay map follows you: no).
    property bool draggable: true

    // The view: the native pixel in the middle, screen px per native px.
    property real cx: 0
    property real cy: 0
    property real zoom: 0.05

    signal picked(var mark)
    signal dragged
    signal zoomed(real zoom)
    /// The map was fitted to the view (it has its size now).
    signal fittedNow

    function toNative(x, y) { return [map.ox + map.scale * x, map.oy + map.scale * y] }
    function screenOf(nx, ny) { return [(nx - cx) * zoom + width / 2, (ny - cy) * zoom + height / 2] }
    function fitZoom() { return map ? Math.max(0.005, Math.min(width, height) / (map.tile * map.grid)) : 0.05 }

    function fitMap() {
        if (!map) return
        const full = map.tile * map.grid
        cx = full / 2
        cy = full / 2
        zoom = fitZoom()
        redraw()
    }
    /// Shows these world points (x, y, x, y ...), not closer than ~400 m across.
    function fitPoints(pts) {
        if (!map || pts.length < 2) return
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (let i = 0; i < pts.length; i += 2) {
            const n = toNative(pts[i], pts[i + 1])
            x0 = Math.min(x0, n[0]); y0 = Math.min(y0, n[1]); x1 = Math.max(x1, n[0]); y1 = Math.max(y1, n[1])
        }
        const minSpan = 40000 * map.scale
        cx = (x0 + x1) / 2
        cy = (y0 + y1) / 2
        zoom = Math.max(fitZoom() * 0.5, Math.min(4, Math.min((width || 300) / Math.max(x1 - x0, minSpan), (height || 300) / Math.max(y1 - y0, minSpan)) * 0.85))
        redraw()
    }
    function centerOn(x, y) {
        if (!map) return
        const n = toNative(x, y)
        cx = n[0]
        cy = n[1]
        redraw()
    }
    function setZoom(z, atX, atY) {
        if (!map) return
        const next = Math.max(fitZoom() * 0.5, Math.min(4, z))
        if (atX !== undefined) {
            // The native pixel under the pointer stays where it is.
            const nx = cx + (atX - width / 2) / zoom
            const ny = cy + (atY - height / 2) / zoom
            cx = nx - (atX - width / 2) / next
            cy = ny - (atY - height / 2) / next
        }
        zoom = next
        redraw()
    }
    function zoomBy(f) { setZoom(zoom * f); zoomed(zoom) }
    function pxPerMetre() { return map ? map.scale * 100 * zoom : 0 }
    function setPxPerMetre(v) { if (map) setZoom(v / (map.scale * 100)) }
    function redraw() { marksCanvas.requestPaint() }

    // A map is fitted once the view has its size (before, fitZoom is a guess).
    property bool fitted: false
    function sized() {
        if (!fitted && map && width > 50 && height > 50) { fitted = true; fitMap(); fittedNow() }
        redraw()
    }
    onMapKeyChanged: { fitted = false; sized() }
    onMarksChanged: redraw()
    onMarkScaleChanged: redraw()
    onWidthChanged: sized()
    onHeightChanged: sized()

    // ---- the tiles: inside one item in native pixels, moved and scaled as a whole ----
    Item {
        id: tiles
        x: view.width / 2 - view.cx * view.zoom
        y: view.height / 2 - view.cy * view.zoom
        scale: view.zoom
        transformOrigin: Item.TopLeft
        opacity: view.tileOpacity
        // The sharp tiles once a tile shows a little bigger than its small copy.
        readonly property bool sharp: view.map ? view.map.tile * view.zoom > view.map.lo * 1.25 : false
        Repeater {
            model: view.map ? view.map.tiles : []
            delegate: Item {
                required property string modelData
                readonly property var cr: modelData.split("_").map(Number)
                readonly property real tx: cr[0] * view.map.tile
                readonly property real ty: cr[1] * view.map.tile
                // On screen now (with a tile's margin).
                readonly property bool seen: {
                    const x0 = view.cx - view.width / 2 / view.zoom, x1 = view.cx + view.width / 2 / view.zoom
                    const y0 = view.cy - view.height / 2 / view.zoom, y1 = view.cy + view.height / 2 / view.zoom
                    return !(tx > x1 || ty > y1 || tx + view.map.tile < x0 || ty + view.map.tile < y0)
                }
                x: tx
                y: ty
                width: view.map.tile + 0.5 / view.zoom
                height: width
                Image {
                    anchors.fill: parent
                    source: parent.seen && view.dir.length > 0 ? view.dir + "/tiles/" + view.mapKey + "/lo/" + parent.modelData + ".webp" : ""
                    asynchronous: true
                    cache: false
                    smooth: true
                }
                Image {
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: parent.seen && tiles.sharp && view.dir.length > 0 ? view.dir + "/tiles/" + view.mapKey + "/" + parent.modelData + ".webp" : ""
                    asynchronous: true
                    cache: false
                    smooth: true
                }
            }
        }
    }

    // ---- the marks ----
    readonly property var gatherColors: MK.K.GATHER_COLORS
    readonly property var placeColors: MK.K.PLACE_COLORS
    readonly property string gold: MK.K.GOLD
    readonly property string petRed: MK.K.PET_RED
    readonly property var cubeFaces: ["#d7a8ff", "#a35cf5", "#7434d0"]
    readonly property real iconSize: 5.9
    readonly property var namePrio: ({ teleport: 100, boss: 60, kibelisk: 55 })
    readonly property var minor: ["shop", "storage", "alchemy", "blacksmith", "cook", "jewelcraft", "tailor", "npcteleport", "heroquest", "districtquest", "door", "fieldevent", "flightring"]
    /// [sx, sy, reach, label, mark] of what was drawn: for the tooltip and clicks.
    property var drawn: []
    property var loadedIcons: ({})

    function iconUrl(name) { return view.dir + "/icons/" + name + ".webp" }

    Canvas {
        id: marksCanvas
        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        onImageLoaded: requestPaint()
        onPaint: view.paintMarks(getContext("2d"))
    }

    property real shrink: 1
    property var names: []
    function paintMarks(ctx) {
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        const out = []
        names = []
        if (!map) { drawn = out; return }
        const ordered = marks.slice().sort((a, b) => (a.z || 0) - (b.z || 0))
        shrink = Math.max(0.5, Math.min(1, 0.45 + map.scale * 100 * zoom))
        for (const m of ordered) {
            const n = toNative(m.x, m.y)
            const s = screenOf(n[0], n[1])
            const sx = s[0], sy = s[1]
            if (m.kind === "area") { drawArea(ctx, m); continue }
            if (m.kind === "route") {
                const f = screenOf.apply(null, toNative(m.from[0], m.from[1]))
                ctx.save()
                ctx.lineCap = "round"
                ctx.lineWidth = 6 * markScale
                ctx.strokeStyle = "rgba(0,0,0,0.45)"
                ctx.beginPath(); ctx.moveTo(f[0], f[1]); ctx.lineTo(sx, sy); ctx.stroke()
                dash(ctx, [9 * markScale, 7 * markScale])
                ctx.lineWidth = 3 * markScale
                ctx.strokeStyle = gold
                ctx.stroke()
                ctx.restore()
                continue
            }
            const pad = (m.r || 4) * markScale * 3.1 + 12
            if (sx < -pad || sy < -pad || sx > width + pad || sy > height + pad) continue
            const shown = drawMark(ctx, m, sx, sy)
            const reach = shown === "icon" ? (m.r || 4) * (iconSize / 2) * shrink * markScale + 2 : (m.r || 4) * markScale + 3
            if (m.label && shown !== false) out.push([sx, sy, reach, m.label, m])
        }
        drawNames(ctx)
        drawScale(ctx)
        drawn = out
    }

    function dash(ctx, d) { if (ctx.setLineDash) ctx.setLineDash(d) }

    function circle(ctx, sx, sy, r, fill, stroke, w) {
        ctx.beginPath()
        ctx.arc(sx, sy, Math.max(0.1, r), 0, Math.PI * 2)
        if (fill) { ctx.fillStyle = fill; ctx.fill() }
        if (stroke) { ctx.lineWidth = w === undefined ? 1.5 : w; ctx.strokeStyle = stroke; ctx.stroke() }
    }

    function drawScale(ctx) {
        const pxPerM = map.scale * 100 * zoom
        if (!(pxPerM > 0)) return
        const want = 110 / pxPerM
        const p = Math.pow(10, Math.floor(Math.log(want) / Math.LN10))
        const metres = [1, 2, 5, 10].map((k) => k * p).filter((m) => m <= want).pop() || p
        const len = metres * pxPerM
        const x = 12, y = height - 14
        const text = metres >= 1000 ? (metres / 1000) + " km" : metres + " m"
        ctx.save()
        ctx.lineCap = "round"
        for (const [w, c] of [[5, "rgba(0,0,0,0.6)"], [2, "rgba(255,255,255,0.9)"]]) {
            ctx.lineWidth = w
            ctx.strokeStyle = c
            ctx.beginPath()
            ctx.moveTo(x, y - 5); ctx.lineTo(x, y); ctx.lineTo(x + len, y); ctx.lineTo(x + len, y - 5)
            ctx.stroke()
        }
        ctx.font = "600 11px sans-serif"
        ctx.lineWidth = 3
        ctx.strokeStyle = "rgba(0,0,0,0.8)"
        ctx.fillStyle = "#ffffff"
        ctx.strokeText(text, x + 4, y - 7)
        ctx.fillText(text, x + 4, y - 7)
        ctx.restore()
    }

    // Where the game puts a monster the map knows only in part: its subzones' outlines.
    function drawArea(ctx, m) {
        ctx.save()
        ctx.beginPath()
        for (const ring of m.rings) {
            for (let i = 0; i < ring.length; i += 2) {
                const s = screenOf.apply(null, toNative(ring[i], ring[i + 1]))
                if (i) ctx.lineTo(s[0], s[1]); else ctx.moveTo(s[0], s[1])
            }
            ctx.closePath()
        }
        ctx.fillRule = Qt.OddEvenFill
        ctx.fillStyle = "rgba(255,214,102,0.12)"
        ctx.fill()
        ctx.lineJoin = "round"
        ctx.lineWidth = 4
        ctx.strokeStyle = "rgba(0,0,0,0.35)"
        ctx.stroke()
        dash(ctx, [8, 6])
        ctx.lineWidth = 2
        ctx.strokeStyle = gold
        ctx.stroke()
        ctx.restore()
        ctx.font = "600 12px sans-serif"
        ctx.textAlign = "center"
        for (const l of m.labels || []) {
            const s = screenOf.apply(null, toNative(l[1], l[2]))
            ctx.lineWidth = 3
            ctx.strokeStyle = "rgba(0,0,0,0.8)"
            ctx.fillStyle = gold
            ctx.strokeText(l[0], s[0], s[1])
            ctx.fillText(l[0], s[0], s[1])
        }
        ctx.textAlign = "start"
    }

    // A pet's spawn point or a pet monster there now ("live"), by how it stands.
    function pet(ctx, sx, sy, r, look, live, color) {
        color = color || petRed
        if (look === "fav") {
            const R = r * 1.8
            if (live) circle(ctx, sx, sy, R + 3, null, "rgba(255,255,255,0.9)", 2)
            ctx.beginPath()
            for (let i = 0; i < 10; i++) {
                const a = -Math.PI / 2 + (i * Math.PI) / 5
                const d = i % 2 ? R * 0.48 : R
                if (i) ctx.lineTo(sx + d * Math.cos(a), sy + d * Math.sin(a)); else ctx.moveTo(sx + d * Math.cos(a), sy + d * Math.sin(a))
            }
            ctx.closePath()
            ctx.fillStyle = gold
            ctx.lineJoin = "round"
            ctx.lineWidth = 1.75
            ctx.strokeStyle = "rgba(0,0,0,0.8)"
            ctx.fill()
            ctx.stroke()
            circle(ctx, sx, sy, R * 0.3, color, null)
            return
        }
        if (look === "max") { circle(ctx, sx, sy, r * 0.8, "rgba(175,175,175,0.7)", "rgba(0,0,0,0.5)", 1); return }
        if (look === "plain") {
            circle(ctx, sx, sy, r, "rgba(255,255,255,0.85)", "rgba(0,0,0,0.55)", 1)
            if (live) circle(ctx, sx, sy, r + 3, null, "rgba(255,255,255,0.7)", 1.5)
            return
        }
        const farm = look === "farm"
        if (live) circle(ctx, sx, sy, r + (farm ? 6.5 : 5), null, "rgba(255,255,255,0.75)", 1.5)
        circle(ctx, sx, sy, r + (farm ? 2.6 : 1.9), null, "rgba(0,0,0,0.6)", 1.2)
        circle(ctx, sx, sy, r + (farm ? 1.2 : 0.8), color, "#ffffff", farm ? 2.6 : 1.8)
        if (farm) circle(ctx, sx, sy, Math.max(1.5, r * 0.4), "#ffffff", null)
    }

    // A Hidden Cube seen from above at an angle: three faces around its centre.
    function cube(ctx, sx, sy, size, alpha, stroke, width) {
        const w = size * 0.866, h = size / 2
        const faces = [
            [[0, -size], [w, -h], [0, 0], [-w, -h]],
            [[-w, -h], [0, 0], [0, size], [-w, h]],
            [[0, 0], [w, -h], [w, h], [0, size]]
        ]
        ctx.save()
        ctx.globalAlpha = alpha
        faces.forEach((f, i) => {
            ctx.beginPath()
            f.forEach((p, j) => { if (j) ctx.lineTo(sx + p[0], sy + p[1]); else ctx.moveTo(sx + p[0], sy + p[1]) })
            ctx.closePath()
            ctx.fillStyle = cubeFaces[i]
            ctx.fill()
        })
        ctx.globalAlpha = 1
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(sx - w, sy - h); ctx.lineTo(sx, sy); ctx.lineTo(sx + w, sy - h)
        ctx.moveTo(sx, sy); ctx.lineTo(sx, sy + size)
        ctx.lineWidth = 1
        ctx.strokeStyle = "rgba(30,10,52,0.55)"
        ctx.stroke()
        ctx.beginPath()
        const hex = [[0, -size], [w, -h], [w, h], [0, size], [-w, h], [-w, -h]]
        hex.forEach((p, j) => { if (j) ctx.lineTo(sx + p[0], sy + p[1]); else ctx.moveTo(sx + p[0], sy + p[1]) })
        ctx.closePath()
        ctx.lineWidth = width
        ctx.strokeStyle = stroke
        ctx.stroke()
        ctx.restore()
    }

    function drawMark(ctx, m, sx, sy) {
        const r = (m.r || 4) * (m.kind === "me" ? 1 : shrink) * markScale
        // The game's own symbol where the mark has one (loaded once).
        if (m.icon && m.kind !== "teleport" && dir.length > 0) {
            const url = iconUrl(m.icon)
            if (marksCanvas.isImageLoaded(url)) {
                const size = r * iconSize
                if (m.live) circle(ctx, sx, sy, size * 0.5, "rgba(10,12,16,0.55)", "#ffffff", 2)
                ctx.drawImage(url, sx - size / 2, sy - size / 2, size, size)
                if (m.hit) circle(ctx, sx, sy, Math.max(size * 0.5 + 2, 7), null, gold, 2.5)
                drawName(m, sx, sy, size * 0.5)
                return "icon"
            }
            if (!marksCanvas.isImageLoading(url) && !marksCanvas.isImageError(url)) marksCanvas.loadImage(url)
        }
        switch (m.kind) {
        case "me": {
            if (!m.exact) {
                const ring = Math.max(r + 4, (m.acc || 10) * 100 * map.scale * zoom)
                circle(ctx, sx, sy, ring, "rgba(255,255,255,0.08)", "rgba(255,255,255,0.35)", 1)
            }
            ctx.save()
            ctx.translate(sx, sy)
            ctx.rotate(((m.heading || 0) * Math.PI) / 180)
            ctx.beginPath()
            ctx.moveTo(0, -r * 1.6); ctx.lineTo(r, r); ctx.lineTo(0, r * 0.45); ctx.lineTo(-r, r)
            ctx.closePath()
            ctx.fillStyle = "#ffffff"
            ctx.lineWidth = 2
            ctx.strokeStyle = "rgba(0,0,0,0.75)"
            ctx.stroke()
            ctx.fill()
            ctx.restore()
            break
        }
        case "petSpawn": pet(ctx, sx, sy, r, m.look || "need", false, m.color); break
        case "petLive": pet(ctx, sx, sy, r, m.look || "need", true, m.color); break
        case "monster": circle(ctx, sx, sy, r, "rgba(220,220,220,0.75)", "rgba(0,0,0,0.5)", 1); break
        case "gather":
            ctx.fillStyle = gatherColors[m.gather] || "#dddddd"
            ctx.strokeStyle = m.live ? "#ffffff" : "rgba(0,0,0,0.6)"
            ctx.lineWidth = m.live ? 2 : 1
            ctx.beginPath()
            ctx.rect(sx - r, sy - r, r * 2, r * 2)
            ctx.fill()
            ctx.stroke()
            break
        case "cube": cube(ctx, sx, sy, r * 1.25, 1, "#ffffff", 2); break
        case "boss":
            circle(ctx, sx, sy, r * 1.15, "rgba(30,10,8,0.85)", "#ff7a52", 2)
            ctx.beginPath()
            ctx.moveTo(sx - r * 0.7, sy + r * 0.45); ctx.lineTo(sx - r * 0.7, sy - r * 0.35); ctx.lineTo(sx - r * 0.35, sy)
            ctx.lineTo(sx, sy - r * 0.6); ctx.lineTo(sx + r * 0.35, sy); ctx.lineTo(sx + r * 0.7, sy - r * 0.35); ctx.lineTo(sx + r * 0.7, sy + r * 0.45)
            ctx.closePath()
            ctx.fillStyle = "#ffb199"
            ctx.fill()
            break
        case "teleport":
            circle(ctx, sx, sy, r + 5, "rgba(10,12,16,0.75)", gold, 2.5)
            ctx.beginPath()
            ctx.moveTo(sx, sy - r * 1.1); ctx.lineTo(sx + r * 0.85, sy + r * 0.65); ctx.lineTo(sx - r * 0.85, sy + r * 0.65)
            ctx.closePath()
            ctx.fillStyle = "#9ee6d8"; ctx.lineWidth = 1.5; ctx.strokeStyle = "rgba(0,0,0,0.7)"
            ctx.fill(); ctx.stroke()
            break
        case "kibelisk":
            ctx.beginPath()
            ctx.moveTo(sx, sy - r * 1.4); ctx.lineTo(sx + r, sy + r * 0.8); ctx.lineTo(sx - r, sy + r * 0.8)
            ctx.closePath()
            ctx.fillStyle = "#9ee6d8"; ctx.lineWidth = 1.5; ctx.strokeStyle = "rgba(0,0,0,0.7)"
            ctx.fill(); ctx.stroke()
            break
        case "cubeSpot": cube(ctx, sx, sy, r * 1.3, m.all ? 0.45 : 0.7, "rgba(20,8,36,0.85)", m.all ? 1 : 1.25); break
        case "npc": circle(ctx, sx, sy, r * 0.8, "rgba(255,240,200,0.9)", "rgba(0,0,0,0.6)", 1); break
        case "feather":
        case "monolith":
            ctx.fillStyle = "#d9c6ff"; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.lineWidth = 1
            ctx.beginPath()
            ctx.rect(sx - r * 0.55, sy - r * 1.2, r * 1.1, r * 2.4)
            ctx.fill(); ctx.stroke()
            break
        case "place": {
            const c = placeColors[m.place] || "#ffffff"
            circle(ctx, sx, sy, r, "rgba(10,12,16,0.7)", c, 2)
            circle(ctx, sx, sy, Math.max(1.5, r * 0.4), c, null)
            break
        }
        case "region":
            if (zoom * map.tile < 70) return false
            names.push({ text: m.text, x: sx, y: sy, prio: 50, region: true })
            return true
        default:
            circle(ctx, sx, sy, r, "#ffffff", "rgba(0,0,0,0.6)")
        }
        if (m.hit) circle(ctx, sx, sy, Math.max(r + 4, 7), null, gold, 2.5)
        drawName(m, sx, sy, r + (m.kind === "teleport" ? 5 : 0))
        return true
    }

    // Names once zoomed in (merchants and the like closer still), the most
    // telling first, none over another.
    function drawName(m, sx, sy, r) {
        if (!m.text) return
        const prio = m.hit ? 80 : (namePrio[m.kind] !== undefined ? namePrio[m.kind] : (minor.indexOf(m.place) >= 0 ? 20 : 40))
        const needs = prio === 100 ? 0 : prio <= 20 ? 360 : 180
        if (zoom * map.tile < needs) return
        names.push({ text: m.text, x: sx + r + 4, y: sy + 4, prio: prio, bold: m.kind === "teleport" })
    }
    function drawNames(ctx) {
        const placed = []
        const size = Math.round(11 * Math.min(1.4, markScale))
        names.sort((a, b) => b.prio - a.prio)
        for (const n of names) {
            ctx.font = n.region ? "600 12px sans-serif" : (n.bold ? "600 " : "") + size + "px sans-serif"
            const w = ctx.measureText(n.text).width
            const x0 = n.region ? n.x - w / 2 : n.x
            const box = [x0 - 2, n.y - size, x0 + w + 2, n.y + 4]
            if (n.prio < 100 && placed.some((b) => box[0] < b[2] && box[2] > b[0] && box[1] < b[3] && box[3] > b[1])) continue
            placed.push(box)
            ctx.lineWidth = 3
            ctx.strokeStyle = n.region ? "rgba(0,0,0,0.75)" : "rgba(0,0,0,0.8)"
            ctx.fillStyle = n.region ? "rgba(255,255,255,0.8)" : "#ffffff"
            ctx.strokeText(n.text, x0, n.y)
            ctx.fillText(n.text, x0, n.y)
        }
    }

    // The labelled mark under the pointer: one with a gold ring first, then
    // the one the pointer is most inside of, then the one on top.
    function markAt(px, py) {
        let best = null
        for (const d of drawn) {
            const dist = Math.hypot(d[0] - px, d[1] - py)
            const reach = Math.max(d[2], 7)
            if (dist > reach) continue
            const m = d[4]
            const score = dist / reach - (m && m.hit ? 1 : 0) - (m && m.z ? m.z : 0) * 1e-4
            if (!best || score <= best.score) best = { score: score, label: d[3], x: d[0], y: d[1], mark: m }
        }
        return best
    }

    // The tooltip of the mark under the pointer.
    property var tipMark: null
    Rectangle {
        visible: view.tipMark !== null
        x: view.tipMark ? Math.max(0, Math.min(view.tipMark.x + 10, view.width - width - 4)) : 0
        y: view.tipMark ? Math.max(0, view.tipMark.y - 30) : 0
        width: tipText.implicitWidth + 12
        height: tipText.implicitHeight + 6
        color: Qt.rgba(0.05, 0.05, 0.06, 0.92)
        border.color: Theme.divider
        Text {
            id: tipText
            anchors.centerIn: parent
            text: view.tipMark ? view.tipMark.label : ""
            color: Theme.text()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: view.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        property real startX: 0
        property real startY: 0
        property real startCx: 0
        property real startCy: 0
        property bool moved: false
        cursorShape: pressed && moved ? Qt.ClosedHandCursor : (view.tipMark && view.tipMark.mark && view.tipMark.mark.focus ? Qt.PointingHandCursor : Qt.OpenHandCursor)
        onPressed: (mouse) => { startX = mouse.x; startY = mouse.y; startCx = view.cx; startCy = view.cy; moved = false }
        onPositionChanged: (mouse) => {
            if (pressed && view.draggable) {
                const dx = mouse.x - startX, dy = mouse.y - startY
                if (!moved && Math.abs(dx) + Math.abs(dy) > 3) { moved = true; view.dragged() }
                if (moved) {
                    view.cx = startCx - dx / view.zoom
                    view.cy = startCy - dy / view.zoom
                    view.tipMark = null
                    view.redraw()
                }
            } else {
                view.tipMark = view.markAt(mouse.x, mouse.y)
            }
        }
        onReleased: (mouse) => {
            if (!moved) {
                const hit = view.markAt(mouse.x, mouse.y)
                if (hit && hit.mark && hit.mark.focus) view.picked(hit.mark)
            }
        }
        onExited: view.tipMark = null
        onDoubleClicked: view.zoomBy(1.6)
        onWheel: (wheel) => {
            view.setZoom(view.zoom * (wheel.angleDelta.y > 0 ? 1.25 : 0.8), wheel.x, wheel.y)
            view.zoomed(view.zoom)
        }
    }
}
