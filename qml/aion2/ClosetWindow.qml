import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "lootkit.js" as LK

// The Closet's shop window (canvas board L3Closet, right): opens by itself
// at the Black Cloud merchant and in the closet ("Open at the merchant"),
// at the game's Shop and Market only when "Open at the Shop and Market" is on, or by hand.
// One list that scrolls and grows with the lower corner: the last opened
// stock's skins and pets (new ones first), the pets you still lack (Pet
// Finder's levels, with their chests and monsters) and the cheapest skins
// you lack on the Exchange. Goes when you walk away (6 m), change zone,
// after 3 minutes, or with its ×. While it shows it takes the mouse even
// when locked, so its list scrolls.
Panel {
    id: win
    panelId: "closet-shop"
    title: "Closet"
    tag: "AION 2"
    width: 400
    minWidth: 320
    maxWidth: 800
    stretchy: true
    minGrow: -120
    pinnable: false

    property var store: null
    property var book: null
    readonly property string view: store && store.settings.windowView === "exchange" ? "exchange" : "shop"
    badge: store && store.closet ? store.closet.size + " / " + store.goal + " SKINS" : ""

    readonly property var gradeColors: ["#c8ccd2", "#c8ccd2", "#7fdc9a", "#4fa8ff", "#f2c46b", "#ffb066", "#ff7a6b", "#7fe0c8"]
    property int iconsRevision: 0
    Connections { target: Aion2; function onIconReady(name) { win.iconsRevision++ } }
    function iconUrl(name) { iconsRevision; return name ? Aion2.icon(name) : "" }
    function clock(ms) { const d = new Date(ms); return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes() }

    property var shop: ({ offers: [], owner: "", refresh: 0 })
    property var exch: ({ rows: [], total: 0, note: "" })
    property string todo: ""
    property var others: []
    property var pets: ({ synced: false, rows: [] })
    function build() {
        if (!store || !visible) return
        shop = store.offersNow()
        exch = store.exchangeList(view === "exchange" ? 150 : 8)
        todo = store.todo()
        pets = view === "shop" ? store.petsNeeded() : { synced: false, rows: [] }
        others = store.closetCharsNow().filter((c) => c.name !== shop.owner && (!c.looked || c.fresh)).map((c) => c.looked ? c.name + " " + c.fresh + " new" : c.name + " not looked")
    }
    Connections { target: win.store; function onRevisionChanged() { win.build() } }
    onVisibleChanged: build()
    onViewChanged: build()
    Connections { target: Aion2; ignoreUnknownSignals: true; function onPetsChanged() { win.build() } }
    readonly property string petDir: Aion2.mapDir().replace(/\/map$/, "") + "/pets/portraits/"
    function genusColor(g) { return ({ cogni: "#b99bff", fera: "#ff9f66", natura: "#74d99a", varian: "#5cc9e6", special: "#f2c46b" })[g] || "#8d8996" }

    Column {
        width: parent.width
        spacing: 8

        Item {
            width: parent.width
            height: 30
            Row {
                spacing: 16
                Repeater {
                    model: [["shop", "Shop"], ["exchange", "Exchange"]]
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: win.view === modelData[0]
                        width: t.implicitWidth
                        height: 30
                        Text {
                            id: t
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1].toUpperCase()
                            color: parent.current ? Theme.accent : (m.containsMouse ? Theme.text() : Theme.muted())
                            font.family: Theme.display
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: parent.current ? Theme.accent : "transparent" }
                        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.store.set("windowView", modelData[0]) }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // One list for everything below the tabs: scrolls with the wheel
        // and grows with the window's lower corner.
        Item {
            width: parent.width
            height: 420 + win.grow
          WheelScroll { flick: page; step: 90 }
          Flickable {
            id: page
            anchors.fill: parent
            contentHeight: pageColumn.implicitHeight
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: pageColumn
                width: page.width
                spacing: 8

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                    text: win.view === "shop"
                        ? (win.shop.owner ? win.shop.owner + "'s offers · change at " + win.clock(win.shop.refresh) : "Open a tab of the Black Cloud shop: its offers show here.")
                        : (win.exch.total ? win.exch.total + " skins you lack are on the Exchange, cheapest first" : win.exch.note)
                    color: Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                // Which pets to buy (Pet Finder's merchant list).
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: win.view === "shop" && !!win.shop.advice
                    text: win.shop.advice || ""
                    color: /^Buy/.test(win.shop.advice || "") ? Theme.accent : Theme.textSoft()
                    font.family: Theme.body
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }

                Flow {
                    visible: win.view === "shop"
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: win.view === "shop" ? win.shop.offers : []
                        delegate: Rectangle {
                            required property var modelData
                            readonly property var o: modelData
                            width: (pageColumn.width - 18) / 4
                            height: o.pet && (o.souls || o.from) ? 158 : 128
                            color: "#1b1a20"
                            // Framed in the item's grade colour, thicker when worth buying (MN).
                            readonly property bool hot: (o.status === "new" || o.status === "buy") && !o.soldOut
                            border.color: o.grade > 1 ? win.gradeColors[o.grade] : "#4a4852"
                            border.width: hot ? 2 : 1
                            opacity: o.status === "owned" || o.soldOut ? 0.55 : 1
                            Column {
                                x: 4
                                y: 4
                                width: parent.width - 8
                                spacing: 2
                                Rectangle {
                                    width: parent.width
                                    height: 58
                                    color: "#2a2930"
                                    Image {
                                        anchors.centerIn: parent
                                        width: 52
                                        height: 52
                                        asynchronous: true
                                        sourceSize.width: 104
                                        fillMode: Image.PreserveAspectFit
                                        source: o.portrait ? o.portrait : win.iconUrl(o.icon)
                                    }
                                    // No picture (NC's server lacks some skins'): the slot as text.
                                    Text {
                                        visible: !o.portrait && !win.iconUrl(o.icon)
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: String(o.sub || "").split(" · ").pop().toUpperCase()
                                        color: Theme.dim()
                                        font.family: Theme.display
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                    Rectangle { width: 6; height: 6; x: 4; y: 4; color: win.gradeColors[o.grade] || "transparent"; visible: o.grade > 1 }
                                }
                                Text { width: parent.width; elide: Text.ElideRight; text: o.name; color: Theme.text(); font.family: Theme.body; font.pixelSize: 11; style: Theme.textStyle(); styleColor: Theme.shadow }
                                Text { width: parent.width; elide: Text.ElideRight; text: o.sub; color: Theme.dim(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                                // A pet's souls (held / needed for its next level) and where it comes from (MN, 0.8.13).
                                Text { visible: !!o.souls; width: parent.width; elide: Text.ElideRight; text: o.souls || ""; color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                                Text { visible: !!o.from; width: parent.width; elide: Text.ElideRight; text: o.from || ""; color: o.status === "buy" ? Theme.accent : Theme.dim(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                                Item {
                                    width: parent.width
                                    height: 16
                                    Text { text: LK.C.kina(o.price); color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 11; style: Theme.textStyle(); styleColor: Theme.shadow }
                                    Text {
                                        anchors.right: parent.right
                                        text: o.soldOut ? "BOUGHT" : o.status === "new" ? "NEW" : o.status === "buy" ? "BUY" : o.status === "need" ? "NEED" : o.status === "owned" ? (o.pet ? "LV 3" : "OWNED") : "?"
                                        color: (o.status === "new" || o.status === "buy") && !o.soldOut ? Theme.accent : o.status === "need" && !o.soldOut ? Theme.text() : Theme.dim()
                                        font.family: Theme.display
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                        style: Theme.textStyle(); styleColor: Theme.shadow
                                    }
                                }
                            }
                        }
                    }
                }

                // The pets you don't have yet, from Pet Finder.
                Text {
                    visible: win.view === "shop"
                    width: parent.width
                    topPadding: 4
                    text: "PETS YOU DON'T HAVE YET" + (win.pets.synced ? " · " + win.pets.rows.length : "")
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Text {
                    visible: win.view === "shop" && (!win.pets.synced || !win.pets.rows.length)
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !win.pets.synced ? "Open the pet collection in the game once while the companion runs: then the pets you lack show here, with the chests and monsters they come from." : "You have every pet. The pets on offer above say which still lack levels."
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Repeater {
                    model: win.view === "shop" && win.pets.synced ? win.pets.rows : []
                    delegate: Item {
                        required property var modelData
                        readonly property var r: modelData
                        width: pageColumn.width
                        height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                        Rectangle { y: 4; width: 3; height: 32; color: win.genusColor(r.genus) }
                        Rectangle {
                            x: 6
                            y: 4
                            width: 32
                            height: 32
                            color: "#2a2930"
                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                sourceSize.width: 64
                                fillMode: Image.PreserveAspectCrop
                                source: win.petDir + r.id + ".webp"
                            }
                        }
                        Column {
                            x: 46
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            Text { width: parent.width; elide: Text.ElideRight; text: r.name; color: Theme.text(); font.family: Theme.body; font.pixelSize: 12; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Text { width: parent.width; elide: Text.ElideRight; text: r.from; color: r.chest ? Theme.textSoft() : Theme.dim(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                        }
                    }
                }

                // The Exchange: the cheapest skins you lack.
                Text {
                    visible: win.view === "shop" && win.exch.rows.length > 0
                    width: parent.width
                    topPadding: 4
                    text: "ON THE EXCHANGE"
                    color: Theme.accent
                    font.family: Theme.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
                Repeater {
                    model: win.exch.rows
                    delegate: Item {
                        required property var modelData
                        readonly property var e: modelData
                        width: pageColumn.width
                        height: 34
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                        Rectangle {
                            id: pic
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            color: "#2a2930"
                            Image {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                asynchronous: true
                                sourceSize.width: 52
                                source: win.iconUrl(e.icon)
                            }
                            Rectangle { width: 5; height: 5; x: 2; y: 2; color: win.gradeColors[e.grade] || "transparent"; visible: e.grade > 1 }
                        }
                        Text {
                            x: 36
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 150
                            elide: Text.ElideRight
                            text: e.name + "  · " + e.sub
                            color: Theme.text()
                            font.family: Theme.body
                            font.pixelSize: 12
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Text {
                            anchors.right: buy.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: LK.C.kina(e.price)
                            color: Theme.textSoft()
                            font.family: Theme.body
                            font.pixelSize: 12
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                        Text {
                            id: buy
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            horizontalAlignment: Text.AlignRight
                            text: e.good ? "BUY" : ""
                            color: Theme.accent
                            font.family: Theme.display
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                            style: Theme.textStyle(); styleColor: Theme.shadow
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                    text: [win.todo, win.others.length ? "Other characters: " + win.others.join(", ") : ""].filter((x) => x).join(" · ")
                    color: Theme.muted()
                    font.family: Theme.body
                    font.pixelSize: 11
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
          }
        }
    }
}
