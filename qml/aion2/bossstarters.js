.pragma library
// Game Companion: dungeon cheat sheets the Boss panel starts with (MN,
// 2026-11-13: "what to do in each phase, for Ludra first"). A sheet is a
// boss's, as Boss Notes keeps them (keys: the boss data's, or "npc-<code>");
// an entry may name a role ("Party 1", "Soul Stone" ...): with MY ROLE set,
// entries for other roles fade. Entries without a trigger from the game
// ("none") are shown, never fired: tie them to the boss's cast in FIGHTS.
//
// The words are a starting point from public guides (metabot.gg,
// aion2-meta.com, aion2.gg, November 2026), unchecked and partly
// contradicting each other: change them after a run. Facts only, in own
// words.

var dungeons = {
    "600082": {
        name: "Abyssal Forge: Ludra",
        // The bosses in the order they are fought.
        bosses: [
            { key: "npc-2301008", name: "Fusion Reactor" },
            { key: "isolation-specialist-rahu", name: "Rahu" },
            { key: "abyssal-wings-ketu", name: "Ketu" },
            { key: "eternal-ludra", name: "Ludra" }
        ],
        // Monsters only met there: seeing one around means you are in.
        npcs: [2301001, 2301002, 2301003, 2301004, 2301005, 2301006, 2301007, 2301008, 2301009, 2301012, 2301013, 2301014],
        roles: ["Party 1", "Party 2", "Red orb", "Soul Stone"],
        notes: "10 players in two parties. Agree who does what before the first pull: parties, red orb, Soul Stones."
    }
}

var sheets = {
    "npc-2301008": {
        notes: "Starter from public guides, unchecked.",
        entries: [
            { id: "l-reactor", kind: "phase", name: "Reactor", role: "", when: { type: "start" },
              text: "Split as agreed: one party here, the other on the platforms." }
        ]
    },
    "isolation-specialist-rahu": {
        notes: "Starter from public guides, unchecked.",
        entries: [
            { id: "l-rahu", kind: "phase", name: "Rahu", role: "", when: { type: "start" },
              text: "Purple bomb on you: pass it to another player in the circle before it runs out." },
            { id: "l-rahu-pools", kind: "phase", name: "Purple pools", role: "", when: { type: "none" },
              text: "Clear the purple pools: three left in the arena wipe the raid." }
        ]
    },
    "abyssal-wings-ketu": {
        notes: "Starter from public guides, unchecked.",
        entries: [
            { id: "l-ketu", kind: "phase", name: "Ketu", role: "", when: { type: "start" },
              text: "Parties swap sides as agreed." },
            { id: "l-ketu-stones", kind: "phase", name: "Soul Stones", role: "Soul Stone", when: { type: "hp", value: 40 },
              text: "Under 40 %: break your Soul Stone for a moment of invulnerability. One each, as assigned." }
        ]
    },
    "eternal-ludra": {
        notes: "Starter from public guides, unchecked. Berserk after 10:00.",
        entries: [
            { id: "l-ludra", kind: "phase", name: "Pull", role: "", when: { type: "start" },
              text: "All ten together. Berserk after 10:00." },
            { id: "l-ludra-grid", kind: "phase", name: "Grid", role: "", when: { type: "none" },
              text: "36 tiles, one safe. Search your zone, call the safe tile." },
            { id: "l-ludra-colours", kind: "phase", name: "Colours", role: "", when: { type: "none" },
              text: "Step into the circle of your colour about 1 s before the breath." },
            { id: "l-ludra-orb", kind: "phase", name: "Red orb", role: "Red orb", when: { type: "none" },
              text: "The red-orb defender takes it (block or invulnerable)." },
            { id: "l-ludra-stagger", kind: "phase", name: "Stagger", role: "", when: { type: "none" },
              text: "He stays down 10 s: all cooldowns now." },
            { id: "l-ludra-berserk", kind: "alert", name: "Berserk in 30 s", role: "", when: { type: "time", value: 570 }, ms: 30000,
              text: "Burn him now." }
        ]
    }
}

/// The dungeon a boss key belongs to, if a cheat sheet knows it.
function dungeonOf(key) {
    for (var id in dungeons) {
        var d = dungeons[id]
        for (var i = 0; i < d.bosses.length; i++) if (d.bosses[i].key === key) return id
    }
    return ""
}
