import QtQuick
import GameCompanion
import ".."
import "../theme.js" as Theme
import "lootkit.js" as LK

// The Closet's shop window (canvas board L3Closet, right): opens by itself
// at the Black Cloud shop and in the closet when Closet → "Open at the shop"
// is on, shows the last opened stock's skins and pets (new ones first) and
// the cheapest skins you lack on the Exchange. Goes when you walk away
// (6 m), change zone, after 3 minutes, or with its ×. While it shows it
// takes the mouse even when locked, so its list scrolls.
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
    badge: store && store.closet ? store.closet.size + " / " + store.goal : ""

    readonly property var gradeColors: ["#c8ccd2", "#c8ccd2", "#7fdc9a", "#4fa8ff", "#f2c46b", "#ffb066", "#ff7a6b", "#7fe0c8"]
    property int iconsRevision: 0
    Connections { target: Aion2; function onIconReady(name) { win.iconsRevision++ } }
    function iconUrl(name) { iconsRevision; return name ? Aion2.icon(name) : "" }
    function clock(ms) { const d = new Date(ms); return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes() }

    property var shop: ({ offers: [], owner: "", refresh: 0 })
    property var exch: ({ rows: [], total: 0, note: "" })
    property string todo: ""
    property var others: []
    function build() {
        if (!store || !visible) return
        shop = store.offersNow()
        exch = store.exchangeList(view === "exchange" ? 150 : 8)
        todo = store.todo()
        others = store.closetCharsNow().filter((c) => c.name !== shop.owner && (!c.looked || c.fresh)).map((c) => c.looked ? c.name + " " + c.fresh + " new" : c.name + " not looked")
    }
    Connections { target: win.store; function onRevisionChanged() { win.build() } }
    onVisibleChanged: build()
    onViewChanged: build()

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

        // The offers: a tile each (skins first, then pets).
        Item {
            visible: win.view === "shop"
            width: parent.width
            height: visible ? Math.min(tiles.implicitHeight, 300 + win.grow) : 0
          WheelScroll { flick: grid; step: 90 }
          Flickable {
            id: grid
            anchors.fill: parent
            contentHeight: tiles.implicitHeight
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            Flow {
                id: tiles
                width: grid.width
                spacing: 6
                Repeater {
                    model: win.shop.offers
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var o: modelData
                        width: (tiles.width - 18) / 4
                        height: 128
                        color: "#1b1a20"
                        border.color: o.status === "new" ? Theme.accent : "#2f2d36"
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
                                    source: win.iconUrl(o.icon)
                                }
                                Rectangle { width: 6; height: 6; x: 4; y: 4; color: win.gradeColors[o.grade] || "transparent"; visible: o.grade > 1 }
                            }
                            Text { width: parent.width; elide: Text.ElideRight; text: o.name; color: Theme.text(); font.family: Theme.body; font.pixelSize: 11; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Text { width: parent.width; elide: Text.ElideRight; text: o.sub; color: Theme.dim(); font.family: Theme.body; font.pixelSize: 10; style: Theme.textStyle(); styleColor: Theme.shadow }
                            Item {
                                width: parent.width
                                height: 16
                                Text { text: LK.C.kina(o.price); color: Theme.textSoft(); font.family: Theme.body; font.pixelSize: 11; style: Theme.textStyle(); styleColor: Theme.shadow }
                                Text {
                                    anchors.right: parent.right
                                    text: o.soldOut ? "BOUGHT" : o.status === "new" ? (o.pet ? "NOT YOURS" : "NEW") : o.status === "owned" ? "OWNED" : "?"
                                    color: o.status === "new" && !o.soldOut ? Theme.accent : Theme.dim()
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
          }
        }

        // The Exchange: the cheapest skins you lack.
        ListView {
            id: exList
            width: parent.width
            height: win.view === "exchange" ? 300 + win.grow : Math.min(contentHeight, 120)
            visible: count > 0
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: win.exch.rows
            WheelScroll { flick: exList; step: 90 }
            header: Text {
                visible: win.view === "shop"
                height: visible ? 24 : 0
                text: "ON THE EXCHANGE"
                verticalAlignment: Text.AlignVCenter
                color: Theme.accent
                font.family: Theme.display
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.4
                style: Theme.textStyle(); styleColor: Theme.shadow
            }
            delegate: Item {
                required property var modelData
                readonly property var e: modelData
                width: exList.width
                height: 28
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; color: win.gradeColors[e.grade] || "#c8ccd2" }
                Text {
                    x: 14
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
