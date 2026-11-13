import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "mapkit.js" as MK

// The AION 2 module's Map (the Clicktrough Map plugin, in QML): the map you
// are on with where you are, the pets' spawn points, monsters, gathering
// spots, Hidden Cubes, Monolith pieces, Kibelisks, field bosses and other
// places; a search over all of them; the nearest monsters with souls. Its
// logic and tables are the plugin's own (mapkit.js); it reads the world the
// module hears (Aion2.world) and never sends anything.
Panel {
    id: panel
    panelId: "map"
    title: "Map"
    tag: width < 420 ? "" : "AION 2"
    width: 540
    minWidth: 360
    maxWidth: 1400
    stretchy: true
    minGrow: -200
    badge: whereText

    readonly property string dir: Aion2.mapDir()

    // ---- what is kept (Aion2.mapSettings) ----
    property var settings: ({
        layers: { pets: true, monsters: false, gather: false, cubes: true, monoliths: false, kibelisks: true, places: true, services: false, quests: false, npcs: false },
        gatherKinds: {},
        petsMode: "all",
        nextFor: "all",
        follow: true,
        zoom: 0,
        pick: "auto",
        lastKey: "",
        focus: null,
        markScale: 1.25,
        overlay: overlayDefaults,
        // Pet Finder (the PETS tab): favourites (pet ids), the list's choices.
        tab: "map",
        petFavs: [],
        petShow: "needed",
        petSort: "nearest",
        petGenus: "",
        petFrom: []
    })
    // The overlay map (MapOverlay, Settings → Plugins → Map): a small map
    // that follows you over the game. `w` > 0: a side set by its corner
    // (else the size's); x < 0: not placed yet; `slots`: places 1 to 3.
    readonly property var overlayDefaults: ({
        on: false, size: "m", w: 0, x: -1, y: -1, opacity: 0.75, markScale: 1.25, zoom: 0,
        own: false,
        layers: { pets: true, monsters: false, gather: false, cubes: true, monoliths: false, kibelisks: true, places: true, services: false, quests: false, npcs: false },
        hideIn: { instance: true, arena: true, abyss: false },
        slot: -1, slots: [null, null, null],
        farm: true
    })
    /// The overlay map's part (Main sets it): places are kept from where it is.
    property Item overlayItem: null
    /// The overlay map is to take its kept place again (a place 1 to 3).
    signal overlayPlaced
    Component.onCompleted: {
        try {
            const saved = JSON.parse(Aion2.mapSettings())
            const s = Object.assign({}, settings, saved)
            s.layers = Object.assign({}, settings.layers, saved.layers || {})
            const o = Object.assign({}, overlayDefaults, saved.overlay || {})
            o.layers = Object.assign({}, overlayDefaults.layers, (saved.overlay || {}).layers || {})
            o.hideIn = Object.assign({}, overlayDefaults.hideIn, (saved.overlay || {}).hideIn || {})
            s.overlay = o
            settings = s
        } catch (e) { }
        // GC_DEMO=map,pets,petstab: the PETS tab, Fossa a favourite and one open.
        const demo = nativeWindow.demo.split(",")
        if (demo.indexOf("pets") >= 0) {
            const s = Object.assign({}, settings)
            s.petFavs = ["1004", "1005", "1003"]
            if (demo.indexOf("petstab") >= 0) s.tab = "pets"
            settings = s
        }
        takeWorld()
        takePets()
    }
    Timer { id: saveTimer; interval: 600; onTriggered: Aion2.saveMapSettings(JSON.stringify(panel.settings)) }
    function change(key, value) {
        const s = Object.assign({}, settings)
        s[key] = value
        settings = s
        saveTimer.restart()
        refresh()
    }
    /// Changes the overlay map's settings (an object of the keys that change).
    function changeOverlay(patch) {
        const s = Object.assign({}, settings)
        s.overlay = Object.assign({}, settings.overlay, patch)
        settings = s
        saveTimer.restart()
    }
    function toggleOverlay() { changeOverlay({ on: !settings.overlay.on }) }
    /// Place `i` (0 to 2): goes there, if one was kept.
    function useSlot(i) {
        const p = settings.overlay.slots[i]
        if (!p) return
        changeOverlay({ x: p.x, y: p.y, w: p.w || 0, size: p.size || settings.overlay.size, slot: i })
        overlayPlaced()
    }
    /// Keeps where the overlay map is now as place `i`.
    function keepSlot(i) {
        const o = settings.overlay
        const slots = o.slots.slice()
        slots[i] = { x: overlayItem ? Math.round(overlayItem.x) : o.x, y: overlayItem ? Math.round(overlayItem.y) : o.y, w: o.w, size: o.size }
        changeOverlay({ slots: slots, slot: i })
    }
    function toggleLayer(name) {
        const l = Object.assign({}, settings.layers)
        l[name] = !l[name]
        change("layers", l)
    }
    function toggleKind(kind) {
        const g = Object.assign({}, settings.gatherKinds)
        g[kind] = g[kind] === false
        change("gatherKinds", g)
    }

    // ---- the world: steadier than the module's guess, the way you walk ----
    property var world: null
    property var shownMe: null
    property real heading: 0
    property var headingFrom: null
    property var learned: ({})
    Connections {
        target: Aion2
        function onWorldChanged() { panel.takeWorld() }
        function onPetsChanged() { panel.takePets() }
    }

    // ---- Pet Finder: the collection the game sent, the favourites ----
    // (Clicktrough's Pet Finder, the Pet Soul Tracker's list: canvas page
    // "Pet Finder in der Map", MN 2026-11-13.) What the map follows comes
    // from here: favourites ("pinned"), the pets given a soul in the last 30
    // minutes ("farming"), every pet not at level 3 ("needed").
    readonly property var petData: { try { return JSON.parse(Aion2.petData()) } catch (e) { return ({}) } }
    property var pets: ({ synced: 0, levels: {}, souls: {}, farmed: {} })
    property var tracked: new Map()
    /// Pets not at level 3 (ids as strings); null before the game sent the list.
    property var needed: null
    /// Souls each pet still needs to level 3 (id -> count); null before.
    property var soulsLeft: null
    /// The pet farmed last (a soul in the last 30 minutes): { id, name, level, souls, goal }.
    property var farming: null
    /// A favourite's monster is around you now (a dot on the PETS tab).
    property bool favAround: false
    readonly property var petGoals: [5, 25, 75]
    readonly property var petToMax: [105, 100, 75, 0]
    function petName(id) { const p = petData.pets ? petData.pets[id] : null; return p ? p.name : "Pet " + id }
    function petLevel(id) { return pets.levels[id] || 0 }
    function petToGo(id) { const l = petLevel(id); return Math.max(0, petToMax[l] - (l < 3 ? (pets.souls[id] || 0) : 0)) }
    function isFav(id) { return (settings.petFavs || []).indexOf(String(id)) >= 0 }
    function toggleFav(id) {
        const f = (settings.petFavs || []).slice()
        const i = f.indexOf(String(id))
        if (i >= 0) f.splice(i, 1); else f.push(String(id))
        change("petFavs", f)
        takePets()
    }
    function takePets() {
        let p = null
        try { p = JSON.parse(Aion2.pets) } catch (e) { }
        p = Object.assign({ synced: 0, levels: {}, souls: {}, farmed: {} }, p || {})
        // A favourite that reaches level 3 stops being one (the map no
        // longer follows it); one made a favourite at level 3 stays.
        const before = pets.levels || {}
        const favs = (settings.petFavs || []).filter((id) => !((before[id] || 0) < 3 && (p.levels[id] || 0) >= 3 && pets.synced > 0))
        if (favs.length !== (settings.petFavs || []).length) {
            const s = Object.assign({}, settings); s.petFavs = favs; settings = s; saveTimer.restart()
        }
        pets = p
        const t = new Map()
        const now = Date.now()
        let last = null
        for (const id of Object.keys(p.farmed || {})) {
            const at = p.farmed[id]
            if (now - at > 30 * 60 * 1000 || (p.levels[id] || 0) >= 3) continue
            t.set(String(id), { mark: "farming", name: petName(id) })
            if (!last || at > last.at) last = { id: String(id), at: at }
        }
        for (const id of favs) t.set(String(id), { mark: "pinned", name: petName(id) })
        tracked = t
        if (p.synced > 0) {
            const n = new Set()
            const left = {}
            for (const id of Object.keys(petData.pets || {})) {
                if (petLevel(id) < 3) { n.add(String(id)); left[id] = petToGo(id) }
            }
            needed = n
            soulsLeft = left
        } else {
            needed = null
            soulsLeft = null
        }
        farming = last ? { id: last.id, name: petName(last.id), level: petLevel(last.id), souls: p.souls[last.id] || 0, goal: petGoals[petLevel(last.id)] || 0 } : null
        refresh()
    }
    /// Once a minute while a pet is farmed: the farming ends 30 minutes after its last soul.
    Timer { interval: 60000; repeat: true; running: panel.farming !== null; onTriggered: panel.takePets() }
    function takeWorld() {
        let w = null
        try { w = JSON.parse(Aion2.world) } catch (e) { }
        if (!w || (!w.me && !w.npcs)) { world = null; refresh(); return }
        const key = MK.M.mapOf(w)
        if (key && MK.D.maps[key] && MK.M.learnFrom(learned, key, w)) MK.M.setLearned(learned)
        shownMe = MK.M.steady(shownMe, w)
        world = Object.assign({}, w, { me: shownMe })
        const me = world.me
        if (me) {
            if (!headingFrom) headingFrom = [me.x, me.y]
            else if (Math.hypot(me.x - headingFrom[0], me.y - headingFrom[1]) >= 800) {
                heading = MK.K.bearing(headingFrom[0], headingFrom[1], me.x, me.y)
                headingFrom = [me.x, me.y]
            }
        }
        refresh()
    }

    // ---- which map ----
    function whereAmI() {
        const key = MK.M.mapOf(world)
        if (key) return { key: key, guess: false }
        if (world && world.me && world.zone == null && MK.D.maps[settings.lastKey]) return { key: settings.lastKey, guess: true }
        return null
    }
    function currentKey() {
        if (settings.pick !== "auto" && MK.D.maps[settings.pick]) return settings.pick
        const w = whereAmI()
        return (w && w.key) || (MK.D.maps[settings.lastKey] ? settings.lastKey : "verteron")
    }
    function titleOf(key) { return MK.D.maps[key] ? MK.D.maps[key].title : key }

    // ---- what is shown, worked out again when something changes ----
    property string key: "verteron"
    property var built: ({ marks: [], hits: [], next: null, petsHere: 0, around: 0 })
    property string whereText: ""
    property string noteText: ""
    property var nearKinds: []
    function refresh() {
        const k = currentKey()
        const where = whereAmI()
        const inZone = where ? where.key : null
        if (inZone && !where.guess && inZone !== settings.lastKey) {
            const s = Object.assign({}, settings); s.lastKey = inZone; settings = s; saveTimer.restart()
        }
        key = k
        built = MK.M.build({ key: k, world: world, tracked: tracked, needed: needed, heading: heading, layers: settings.layers,
            gatherKinds: settings.gatherKinds, petsMode: settings.petsMode, focus: settings.focus, nextFor: settings.nextFor })
        map.marks = built.marks
        const me = world ? world.me : null
        const onThisMap = !!me && inZone === k
        if (settings.follow && onThisMap) {
            if (settings.zoom > 0) map.setZoom(settings.zoom)
            else map.setPxPerMetre(2)
            map.centerOn(me.x, me.y)
        }
        const region = me && inZone ? MK.M.regionAt(inZone, me.x, me.y) : null
        whereText = region ? String(region.name || region) : ""
        const zone = world ? world.zone : null
        const zoneName = zone != null ? MK.D.zoneNames[String(zone)] : null
        if (!world || !me) noteText = Aion2.active ? "Waiting for your position: it comes with your next action or teleport." : "Shows where you are while AION 2 runs."
        else if (!where && zone == null) noteText = "Zone not known yet: it comes with your next teleport or zone change."
        else if (!where) noteText = "No map for " + (zoneName || "zone " + zone) + "."
        else if (!onThisMap) noteText = "You are in " + titleOf(where.key) + (where.guess ? "?" : "") + "."
        else {
            const fixAge = world.fix && isFinite(world.fix.at) ? Math.max(0, Math.round((Date.now() - world.fix.at) / 1000)) : -1
            const since = fixAge < 0 ? "" : fixAge < 90 ? "; exact " + fixAge + " s ago" : "; exact " + Math.round(fixAge / 60) + " min ago"
            noteText = (me.exact ? "Your position" : "Your position (about, from what's around you" + since + ")")
                + (where.guess ? " · map as last time" : "")
        }
        nearKinds = settings.layers.pets && onThisMap ? MK.M.nearestKinds({ key: k, world: world, tracked: tracked, needed: needed, souls: soulsLeft }) : []
        let fav = false
        for (const n of (world && world.npcs) || []) {
            const pet = MK.D.npcPets[n[1]]
            if (pet != null && isFav(pet)) { fav = true; break }
        }
        favAround = fav
    }
    onWidthChanged: if (settings.follow) refreshLater.restart()
    Timer { id: refreshLater; interval: 50; onTriggered: panel.refresh() }

    // ---- the focus: what the search or a click shows ----
    function sameFocus(a, b) { return !!a && !!b && a.type === b.type && String(a.ids) === String(b.ids) }
    function setFocus(focus, onMap) {
        const s = Object.assign({}, settings)
        s.focus = focus || null
        if (focus && onMap === undefined) {
            const maps = MK.M.focusMaps(focus)
            const here = whereAmI()
            const k = (here && maps[here.key] && here.key) || Object.keys(maps)[0] || null
            if (k) {
                s.pick = here && k === here.key ? "auto" : k
                s.follow = false
                settings = s
                saveTimer.restart()
                refresh()
                map.fitPoints(MK.M.focusFit(focus, k))
                return
            }
        }
        settings = s
        saveTimer.restart()
        refresh()
    }
    /// Where a gathered material grows (the Market's map button).
    function focusGather(name) {
        const f = MK.M.gatherFor(name)
        if (f) setFocus(f)
    }
    /// Where a field boss stands (the Schedule's map button), by its
    /// world-map id.
    function focusBoss(id, name) {
        const npc = MK.D.bossIds[String(id)]
        if (npc) setFocus({ type: "boss", ids: [String(npc)], label: name })
    }
    function showFocusOn(k) {
        const s = Object.assign({}, settings)
        const here = whereAmI()
        s.pick = here && k === here.key ? "auto" : k
        s.follow = false
        settings = s
        saveTimer.restart()
        refresh()
        map.fitPoints(MK.M.focusFit(settings.focus, k))
    }

    // ---- the maps to pick from ----
    readonly property var mapOptions: {
        const g = MK.M.mapGroups([])
        const out = [{ id: "auto", name: "Where you are" }]
        for (const k of g.inGame) out.push({ id: k, name: titleOf(k) })
        for (const k of g.starters) out.push({ id: k, name: titleOf(k) + " (start)" })
        for (const k of g.later) out.push({ id: k, name: titleOf(k) + " (coming)" })
        for (const k of g.instances) out.push({ id: k, name: titleOf(k) + " (instance)" })
        return out
    }

    Column {
        width: parent.width
        spacing: 8

        // The tabs: MAP and PETS (Pet Finder).
        Item {
            width: parent.width
            height: 32
            Row {
                spacing: 18
                Repeater {
                    model: [["map", "Map"], ["pets", "Pets"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: (panel.settings.tab || "map") === modelData[0]
                        width: tabText.implicitWidth + (dot.visible ? 10 : 0)
                        height: 32
                        Text {
                            id: tabText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.current ? Theme.accent : (tabMouse.containsMouse ? Theme.text() : Theme.muted())
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        // A favourite's monster is around you.
                        Rectangle {
                            id: dot
                            visible: modelData[0] === "pets" && panel.favAround && !parent.current
                            anchors.right: parent.right
                            y: 8
                            width: 6
                            height: 6
                            color: Theme.accent
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.change("tab", modelData[0]) }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData[1]
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        PetsTab {
            visible: panel.settings.tab === "pets"
            width: parent.width
            map: panel
        }

        Column {
        visible: panel.settings.tab !== "pets"
        width: parent.width
        spacing: 8

        // Which map, following, the size of the marks.
        Item {
            width: parent.width
            height: 32
            z: 30
            Dropdown {
                id: mapPick
                anchors.left: parent.left
                anchors.right: tools.left
                anchors.rightMargin: 8
                label: "Map"
                options: panel.mapOptions
                current: panel.settings.pick
                onChosen: (id) => { panel.change("pick", id); if (id === "auto") panel.change("follow", true) }
            }
            Row {
                id: tools
                anchors.right: parent.right
                spacing: 6
                Chip { anchors.verticalCenter: parent.verticalCenter; text: "Follow"; on: panel.settings.follow; onClicked: panel.change("follow", !panel.settings.follow) }
                Chip { anchors.verticalCenter: parent.verticalCenter; text: "−"; onClicked: { panel.map.zoomBy(0.8); if (panel.settings.follow) panel.change("zoom", panel.map.zoom) } }
                Chip { anchors.verticalCenter: parent.verticalCenter; text: "+"; onClicked: { panel.map.zoomBy(1.25); if (panel.settings.follow) panel.change("zoom", panel.map.zoom) } }
            }
        }

        // The layers.
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: [["pets", "Pets"], ["monsters", "Monsters"], ["gather", "Gathering"], ["cubes", "Hidden Cubes"], ["monoliths", "Feathers"],
                        ["kibelisks", "Kibelisks"], ["places", "Places"], ["services", "Services"], ["quests", "Quests"], ["npcs", "NPCs"]]
                delegate: Chip {
                    required property var modelData
                    text: modelData[1]
                    on: !!panel.settings.layers[modelData[0]]
                    onClicked: panel.toggleLayer(modelData[0])
                }
            }
        }
        // Which gathering spots, by kind.
        Flow {
            visible: !!panel.settings.layers.gather
            width: parent.width
            spacing: 6
            Repeater {
                model: panel.settings.layers.gather ? MK.M.KIND_ORDER : []
                delegate: Chip {
                    required property var modelData
                    text: MK.M.kindLabel(modelData)
                    dot: MK.K.GATHER_COLORS[modelData] || "#dddddd"
                    on: panel.settings.gatherKinds[modelData] !== false
                    onClicked: panel.toggleKind(modelData)
                }
            }
        }

        // The search: Orichalcum, Hidden Cube, a pet, a monster, an NPC, a place.
        Item {
            width: parent.width
            height: 32
            z: 20
            Rectangle {
                anchors.fill: parent
                color: "#1b1a20"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: search.activeFocus ? Theme.accent : "#3a3842" }
            }
            HudIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 13; lineWidth: 2; color: Theme.muted() }
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text()
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Theme.body
                font.pixelSize: 13
                clip: true
                property var found: []
                onTextChanged: found = text.trim().length >= 2 ? MK.M.search(text.trim(), 12) : []
                Keys.onEscapePressed: { text = ""; focus = false }
                onAccepted: if (found.length > 0) { panel.setFocus(found[0].focus); text = ""; focus = false }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text.length === 0
                    text: "Search: Orichalcum, Hidden Cube, a pet, a monster, an NPC, a place …"
                    color: Theme.dim()
                    font: search.font
                    elide: Text.ElideRight
                    width: parent.width
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
            // The results, over the map.
            Rectangle {
                visible: search.activeFocus && search.text.trim().length >= 2
                y: parent.height + 2
                width: parent.width
                height: Math.max(30, resultsCol.height)
                color: "#16151b"
                border.color: Theme.divider
                Column {
                    id: resultsCol
                    width: parent.width
                    Text {
                        visible: search.found.length === 0
                        x: 12
                        height: 30
                        verticalAlignment: Text.AlignVCenter
                        text: "Nothing with that name on these maps"
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Repeater {
                        model: search.found
                        delegate: Item {
                            required property var modelData
                            width: resultsCol.width
                            height: 32
                            Rectangle { anchors.fill: parent; color: resMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
                            Image {
                                id: resIcon
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                visible: !!modelData.icon
                                source: modelData.icon ? panel.dir + "/icons/" + modelData.icon + ".webp" : ""
                                sourceSize.width: 36
                                asynchronous: true
                            }
                            Rectangle {
                                visible: !modelData.icon
                                x: 15
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.mark === "pet" ? MK.K.PET_RED : modelData.mark === "cube" ? "#a35cf5" : modelData.mark === "monster" ? "#dcdcdc" : "#ffffff"
                            }
                            Text {
                                x: 36
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 46
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: "<b>" + modelData.label + "</b> <font color='" + Theme.dim() + "'>" + (modelData.sub || "") + " · "
                                    + Object.keys(modelData.maps || {}).slice(0, 3).map((k) => panel.titleOf(k) + " " + modelData.maps[k]).join(" · ") + "</font>"
                                color: Theme.text()
                                font.family: Theme.body
                                font.pixelSize: 12
                                style: Theme.textStyle(); styleColor: Theme.shadow
                            }
                            MouseArea {
                                id: resMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: { panel.setFocus(modelData.focus); search.text = ""; search.focus = false }
                            }
                        }
                    }
                }
            }
        }

        // What the search or a click shows, and on which maps.
        Item {
            visible: !!panel.settings.focus
            width: parent.width
            height: visible ? focusRow.height : 0
            Flow {
                id: focusRow
                width: parent.width - 70
                spacing: 6
                Text {
                    height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: panel.settings.focus ? "Showing " + panel.settings.focus.label : ""
                    color: Theme.accent
                    font.family: Theme.body
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Repeater {
                    model: {
                        if (!panel.settings.focus) return []
                        const maps = MK.M.focusMaps(panel.settings.focus)
                        return Object.keys(maps).slice(0, 6).map((k) => [k, maps[k]])
                    }
                    delegate: Chip {
                        required property var modelData
                        text: panel.titleOf(modelData[0]) + " " + modelData[1]
                        on: modelData[0] === panel.key
                        onClicked: panel.showFocusOn(modelData[0])
                    }
                }
            }
            Chip { anchors.right: parent.right; text: "Clear"; onClicked: panel.setFocus(null, false) }
        }

        // Where you are, in words.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: panel.noteText
            color: Theme.muted()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        // The map.
        MapView {
            id: mapView
            width: parent.width
            height: 380 + panel.grow
            dir: panel.dir
            mapKey: panel.key
            markScale: panel.settings.markScale
            interactive: !Companion.locked
            onFittedNow: refreshLater.restart()
            onDragged: if (panel.settings.follow) panel.change("follow", false)
            onZoomed: (z) => { if (panel.settings.follow) panel.change("zoom", z) }
            onPicked: (m) => panel.sameFocus(m.focus, panel.settings.focus) ? panel.setFocus(null, false) : panel.setFocus(m.focus, false)
            Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.divider }
        }

        // The nearest monsters with souls, as the Pet Soul Tracker's map listed them.
        Column {
            visible: panel.nearKinds.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: panel.nearKinds
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 24
                    Rectangle { anchors.fill: parent; color: kindMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
                    Rectangle {
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: modelData.genus && modelData.genus.color ? modelData.genus.color : MK.K.PET_RED
                    }
                    Text {
                        x: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 18 - farText.width - 8
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: "<b>" + modelData.name + "</b>" + (modelData.level != null ? " <font color='" + Theme.dim() + "'>Lv " + modelData.level + "</font>" : "")
                            + (modelData.live ? " ×" + modelData.count : "") + "  <font color='" + Theme.dim() + "'>" + modelData.petName + "</font>"
                        color: modelData.live ? Theme.text() : Theme.textSoft()
                        font.family: Theme.body
                        font.pixelSize: 12
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    Text {
                        id: farText
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: MK.M.arrow(modelData.bearing) + " " + Math.round(modelData.metres) + " m" + (modelData.live ? "" : " (spawn)")
                        color: Theme.muted()
                        font.family: Theme.body
                        font.pixelSize: 12
                        style: Theme.textStyle(); styleColor: Theme.shadow
                    }
                    MouseArea {
                        id: kindMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.setFocus({ type: "npc", ids: [String(modelData.npc)], label: modelData.name }, false)
                    }
                }
            }
        }

        // Next, and how many.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            text: {
                const n = panel.built.next
                const parts = []
                if (panel.settings.focus) parts.push((panel.built.hits.length / 2) + " on this map")
                else if (panel.settings.layers.pets) parts.push(panel.built.petsHere + " pet" + (panel.built.petsHere === 1 ? "" : "s") + " on this map", panel.built.around + " around you")
                const counts = parts.join(" · ")
                if (!n || !panel.world || !panel.world.me) return counts
                const way = n.via
                    ? "teleport to Kibelisk " + n.via.name + ", then " + Math.round(n.via.metres) + " m (walking: " + Math.round(n.metres) + " m)"
                    : MK.M.arrow(n.bearing) + " " + Math.round(n.metres) + " m" + (n.live ? " (there now)" : n.focus ? "" : " (spawn point)")
                return "<font color='" + Theme.accent + "'>NEXT</font> <b>" + n.name + "</b> " + way + (counts ? "<br><font color='" + Theme.dim() + "'>" + counts + "</font>" : "")
            }
            color: Theme.textSoft()
            font.family: Theme.body
            font.pixelSize: 12
            style: Theme.textStyle(); styleColor: Theme.shadow
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Listens only. Maps: the game's own; data from SkeeveAN's Aion-DPS-Meter (MIT), the AION2 Interactive Map (CC BY-NC 4.0, Yihao Liu), A2 Tools' Pet Soul Tracker (GPL-3.0), PetTracker (GPLv3) and Aion 2 Timers."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 10
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        }
    }
    property alias map: mapView
}
