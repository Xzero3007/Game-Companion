.pragma library
// The plugins Game Companion knows, grouped in packages (Settings →
// Plugins). Global plugins work with every game; a game's package loads
// only while that game runs. `built` false: listed so the choice can be
// made, the panel itself is still being moved over from the meter.

var packages = [
    {
        id: "global", name: "Global", game: false,
        about: "Work with every game and without one.",
        plugins: [
            { id: "radio", short: "R", name: "Radio", about: "Internet radio in the background, with the player row.", built: true, fixed: true },
            { id: "streams", short: "TV", name: "Streams", about: "Twitch, YouTube and Jellyfin, with videos over the game.", built: true, fixed: true }
        ]
    },
    {
        id: "aion2", name: "AION 2", game: true,
        about: "Loads only while AION 2 runs. Listens only: nothing is sent to the game.",
        plugins: [
            { id: "aion2.dps", short: "M", name: "DPS Meter", about: "Damage and healing of you and your party, skills (Details) and Battle History.", built: true },
            { id: "aion2.map", short: "MP", name: "Map", about: "The map you are on with your position, spawns, gathering spots, bosses and NPCs; a small map that follows you.", built: true },
            { id: "aion2.market", short: "MK", name: "Market", about: "Your server's market: usual prices, anomalies, materials and what recipes cost.", built: true },
            { id: "aion2.inventory", short: "I", name: "Inventory", about: "LOOT: inventory, storages, the session's drops, farm days and dungeon drop rates.", built: true },
            { id: "aion2.closet", short: "C", name: "Closet", about: "LOOT: the Black Cloud Merchant's skins and pets, the skins you miss, combining; a window at the shop.", built: true },
            { id: "aion2.armory", short: "A", name: "Armory", about: "Gear and its upgrades.", built: false },
            { id: "aion2.shugo", short: "S", name: "Shugo Cards", about: "LOOT: what lay behind the cards of each Shugo Festival and Invasion round, and which place pays.", built: true },
            { id: "aion2.timers", short: "T", name: "Event Timers", about: "Field bosses and events with their times.", built: false },
            { id: "aion2.pets", short: "P", name: "Pet Finder", about: "Pets, their souls and where to farm them.", built: false },
            { id: "aion2.characters", short: "CH", name: "Characters", about: "Your characters: Odyle energy and when it is full, the content each has left, the day's and week's limits.", built: true },
            { id: "aion2.boss", short: "B", name: "Boss Notes", about: "Phases and hints with a countdown in fights.", built: false }
        ]
    },
    {
        id: "poe2", name: "Path of Exile 2", game: true,
        about: "Loads only while Path of Exile 2 runs. Its helper programs are planned later.",
        plugins: []
    }
]

// A plugin's choice from Companion.plugins (parsed): on, and where its
// button sits. Not chosen yet: on, in the bar.
function choice(all, id) {
    var c = all && all.plugins ? all.plugins[id] : undefined
    return { on: c ? c.on !== false : true, place: c && c.place ? c.place : "bar" }
}

// Whether a game's package loads with the game.
function loads(all, id) {
    return !(all && all.packages && all.packages[id] === false)
}

// Whether a plugin's button shows in the bar.
function inBar(all, id) {
    var c = choice(all, id)
    return c.on && c.place === "bar"
}
