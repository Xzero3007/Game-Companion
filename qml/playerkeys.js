.pragma library

// The video player's keys (MN, 2026-11-18): what each does and its keys
// by default. Settings → Streams → Videos changes them; changed ones are
// kept in settings.streams.player.key_map (action → key sequences).
// They work after a click into a video window, and in full screen.
// 0 to 9 (jump to 0 % to 90 %) and Esc (leave full screen) are fixed.

var ACTIONS = [
    { id: "pause", name: "Pause and play", keys: ["Space", "K"] },
    { id: "back", name: "Back (step)", keys: ["Left"] },
    { id: "forward", name: "On (step)", keys: ["Right"] },
    { id: "backLong", name: "Back 10 seconds", keys: ["J"] },
    { id: "forwardLong", name: "On 10 seconds", keys: ["L"] },
    { id: "volumeUp", name: "Louder", keys: ["Up"] },
    { id: "volumeDown", name: "Quieter", keys: ["Down"] },
    { id: "mute", name: "Mute", keys: ["M"] },
    { id: "fullScreen", name: "Full screen on and off", keys: ["F"] },
    { id: "start", name: "To the start", keys: ["Home"] },
    { id: "end", name: "To the end", keys: ["End"] },
    { id: "chapterBack", name: "Chapter back", keys: ["PgUp"] },
    { id: "chapterNext", name: "Next chapter", keys: ["PgDown"] },
    { id: "slower", name: "Slower", keys: ["["] },
    { id: "faster", name: "Faster", keys: ["]"] },
    { id: "normalSpeed", name: "Normal speed", keys: ["Backspace"] },
    { id: "next", name: "Next video or episode", keys: ["N"] },
    { id: "previous", name: "Previous video or track", keys: ["P"] },
    { id: "skip", name: "Skip (intro, SponsorBlock part)", keys: ["S"] },
    { id: "subtitles", name: "Next subtitles (Jellyfin)", keys: ["V"] },
    { id: "audio", name: "Next sound track (Jellyfin)", keys: ["A"] },
    { id: "chat", name: "Twitch chat on and off", keys: ["C"] },
    { id: "info", name: "Show the bars for a moment", keys: ["I"] }
]

var SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

/// The player's settings (Streams.player) as an object, with defaults.
function prefs(json) {
    var p = {}
    try { p = JSON.parse(json || "{}") || {} } catch (e) { p = {} }
    return {
        hide_pointer: p.hide_pointer === undefined ? 10 : p.hide_pointer,
        keys: p.keys === undefined ? true : !!p.keys,
        seek_step: p.seek_step || 5,
        volume_step: p.volume_step || 5,
        key_map: p.key_map || {}
    }
}

function defaultsOf(id) {
    for (var i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].id === id) return ACTIONS[i].keys
    return []
}

/// The keys of an action now: changed by hand, else its defaults.
function keysOf(p, id) {
    var k = p.key_map[id]
    return k && k.length > 0 ? k : defaultsOf(id)
}

/// Another action that has this key already ("" none).
function takenBy(p, key, except) {
    for (var i = 0; i < ACTIONS.length; i++) {
        var a = ACTIONS[i]
        if (a.id !== except && keysOf(p, a.id).indexOf(key) >= 0) return a.id
    }
    if (/^[0-9]$/.test(key) || key === "Esc") return "fixed"
    return ""
}

var NAMED = {}
function named() {
    // Qt.Key_* values (Qt's enum, stable since Qt 4).
    if (NAMED[0x20] === undefined) {
        NAMED[0x20] = "Space"; NAMED[0x01000012] = "Left"; NAMED[0x01000014] = "Right"
        NAMED[0x01000013] = "Up"; NAMED[0x01000015] = "Down"; NAMED[0x01000010] = "Home"
        NAMED[0x01000011] = "End"; NAMED[0x01000016] = "PgUp"; NAMED[0x01000017] = "PgDown"
        NAMED[0x01000003] = "Backspace"; NAMED[0x01000007] = "Del"; NAMED[0x01000006] = "Ins"
        NAMED[0x01000004] = "Return"; NAMED[0x01000005] = "Enter"; NAMED[0x01000001] = "Tab"
        for (var f = 1; f <= 12; f++) NAMED[0x01000030 + f - 1] = "F" + f
    }
    return NAMED
}

/// A pressed key as a key sequence Qt's Shortcut takes ("" a modifier
/// alone or a key that can't be one). Shift is kept only with named keys
/// (Shift+[ gives "{" by itself).
function sequenceOf(key, text, modifiers) {
    var name = named()[key]
    if (!name) {
        if (key >= 0x41 && key <= 0x5a) name = String.fromCharCode(key)
        else if (key >= 0x30 && key <= 0x39) name = String.fromCharCode(key)
        else if (text && text.length === 1 && text.charCodeAt(0) > 32 && text.charCodeAt(0) !== 127) name = text.toUpperCase()
        else return ""
    }
    var parts = []
    if (modifiers & 0x04000000) parts.push("Ctrl")
    if (modifiers & 0x08000000) parts.push("Alt")
    if ((modifiers & 0x02000000) && (named()[key] || (key >= 0x41 && key <= 0x5a))) parts.push("Shift")
    parts.push(name)
    return parts.join("+")
}

/// How a key shows in the settings.
function shown(seq) {
    return seq.replace("PgUp", "Page ↑").replace("PgDown", "Page ↓")
        .replace("Left", "←").replace("Right", "→").replace("Up", "↑").replace("Down", "↓")
}
