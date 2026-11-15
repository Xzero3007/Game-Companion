import QtQuick
import ".."
import "../theme.js" as Theme

// The PoE 2 price check's settings, taken over from Exiled Exchange 2 (MN,
// 2026-11-15; plan poe2-price-plan.md): shown in the price window (⚙) and
// under Settings → Plugins → PoE 2. Every choice is kept in settings.poe2.
Column {
    id: ps
    property var store: null
    readonly property var p: store ? store.prefs : ({})
    spacing: 10

    function choose(key, value) { if (store) store.setPref(key, value) }

    PriceChoices {
        width: ps.width
        label: "Search range"
        hint: "The min each line starts with: your value minus this much (EE2: 10 %)."
        options: [{ id: 0, name: "0 %" }, { id: 5, name: "5 %" }, { id: 10, name: "10 %" }, { id: 15, name: "15 %" }, { id: 20, name: "20 %" }, { id: 30, name: "30 %" }]
        current: ps.p.statRange !== undefined ? ps.p.statRange : 10
        onChosen: (v) => ps.choose("statRange", v)
    }
    PriceChoices {
        width: ps.width
        label: "Max too"
        hint: "Also fill in a max: your value plus the same range."
        options: [{ id: false, name: "Off" }, { id: true, name: "On" }]
        current: ps.p.fillMax === true
        onChosen: (v) => ps.choose("fillMax", v)
    }
    PriceChoices {
        width: ps.width
        label: "Lines at first"
        hint: "Which lines are ticked when an item opens."
        options: [{ id: false, name: "The important ones" }, { id: true, name: "All" }]
        current: ps.p.allSelected === true
        onChosen: (v) => ps.choose("allSelected", v)
    }
    PriceChoices {
        width: ps.width
        label: "Search at once"
        hint: "Uniques, unidentified items and the like are searched as soon as they open."
        options: [{ id: true, name: "On" }, { id: false, name: "Off" }]
        current: ps.p.atOnce !== false
        onChosen: (v) => ps.choose("atOnce", v)
    }
    PriceChoices {
        width: ps.width
        label: "poe.ninja prices"
        hint: "Asks poe.ninja for the league's currency prices (once in 30 minutes, when an item is checked): each listing's price in exalted or divine orbs, and a currency's own price."
        options: [{ id: true, name: "On" }, { id: false, name: "Off" }]
        current: ps.p.ninja !== false
        onChosen: (v) => ps.choose("ninja", v)
    }
    PriceChoices {
        width: ps.width
        label: "Listings"
        options: [{ id: "securable", name: "Instant buyout" }, { id: "available", name: "In person" }, { id: "any", name: "Both" }]
        current: ps.p.listingType || "securable"
        onChosen: (v) => ps.choose("listingType", v)
    }
    PriceChoices {
        width: ps.width
        label: "Priced in"
        options: [{ id: "", name: "Any" }, { id: "exalted", name: "Exalted" }, { id: "divine", name: "Divine" }, { id: "chaos", name: "Chaos" }]
        current: ps.p.currency || ""
        onChosen: (v) => ps.choose("currency", v)
    }
    PriceChoices {
        width: ps.width
        label: "One seller"
        hint: "A seller's same item at the same price: counted once here (×2, ×3), or merged by the trade site."
        options: [{ id: "app", name: "Count here" }, { id: "api", name: "Trade site" }]
        current: ps.p.collapse || "app"
        onChosen: (v) => ps.choose("collapse", v)
    }
    PriceChoices {
        width: ps.width
        label: "Seller"
        options: [{ id: "account", name: "Account" }, { id: "ign", name: "Character" }, { id: "", name: "Hidden" }]
        current: ps.p.seller !== undefined ? ps.p.seller : "account"
        onChosen: (v) => ps.choose("seller", v)
    }
    PriceChoices {
        width: ps.width
        label: "Tiers"
        hint: "Tier and range beside each line (copied with Alt held, the game's advanced mod descriptions)."
        options: [{ id: true, name: "Show" }, { id: false, name: "Hide" }]
        current: ps.p.tiers !== false
        onChosen: (v) => ps.choose("tiers", v)
    }
    PriceChoices {
        width: ps.width
        label: "Opens on copy"
        hint: "Off: the window opens only from the game row's PRICE button."
        options: [{ id: true, name: "On" }, { id: false, name: "Off" }]
        current: ps.p.autoOpen !== false
        onChosen: (v) => ps.choose("autoOpen", v)
    }
    Column {
        width: ps.width
        spacing: 4
        Text {
            text: "YOUR ACCOUNT"
            color: Theme.dim()
            font.family: Theme.display
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
        Rectangle {
            width: Math.min(ps.width, 260)
            height: 28
            color: "#1b1a20"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: account.activeFocus ? Theme.accent : "#3a3842" }
            TextInput {
                id: account
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: ps.p.account || ""
                color: Theme.text()
                selectionColor: Theme.accent
                selectedTextColor: "#0c0c0f"
                font.family: Theme.body
                font.pixelSize: 12
                maximumLength: 60
                clip: true
                onEditingFinished: if (text !== (ps.p.account || "")) ps.choose("account", text.trim())
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: account.text.length === 0
                    text: "Name#1234 (optional)"
                    color: Theme.dim()
                    font: account.font
                    style: Theme.textStyle(); styleColor: Theme.shadow
                }
            }
        }
        Text {
            width: ps.width
            wrapMode: Text.WordWrap
            text: "Your own listings are marked in gold. Typing needs the overlay unlocked (Alt+Q)."
            color: Theme.dim()
            font.family: Theme.body
            font.pixelSize: 11
            style: Theme.textStyle(); styleColor: Theme.shadow
        }
    }
}
