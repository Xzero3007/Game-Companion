.pragma library

// Shared bits of the launch option views (LaunchTab, LaunchSuggestions,
// ProtonOverview): status colours and names, chips from a check, fixes.

var gold = "#e0a526"
var goldLight = "#f2c46b"
var red = "#ef7a72"
var purple = "#c4a8f0"
var grey = "#8d8996"
var mono = "monospace"

// A check status: its mark's colour, whether the mark is hollow, its name.
var statuses = {
    ok: { color: gold, hollow: false, label: "OK" },
    outdated: { color: purple, hollow: false, label: "OUTDATED" },
    invalid: { color: red, hollow: false, label: "INVALID" },
    no_effect: { color: grey, hollow: false, label: "NO EFFECT" },
    not_recommended: { color: red, hollow: true, label: "NOT RECOMMENDED" },
    unknown: { color: grey, hollow: true, label: "UNKNOWN" }
}
var order = ["ok", "outdated", "invalid", "no_effect", "not_recommended", "unknown"]

function status(s) { return statuses[s] || statuses.unknown }

function launcherName(l) {
    return l === "steam" ? "Steam" : l === "lutris" ? "Lutris" : l === "heroic" ? "Heroic" : "Own"
}

// Where a word starts and ends in the text, looked for from `from` on and
// only as a whole word (spaces or the ends around it).
function findWord(text, word, from) {
    let at = text.indexOf(word, from)
    while (at >= 0) {
        const before = at === 0 || /\s/.test(text[at - 1])
        const end = at + word.length
        const after = end === text.length || /\s/.test(text[end])
        if (before && after) return at
        at = text.indexOf(word, at + 1)
    }
    return -1
}

// The chips of the text as the checker read it: [{kind, label, text,
// status, token, start, end}] in text order, the game (%command% or an own
// entry's program) put in where it stands.
function chips(text, check, own) {
    const tokens = (check && check.tokens) || []
    const out = []
    let cursor = 0
    for (const t of tokens) {
        let at = findWord(text, t.text, cursor)
        if (at < 0) at = findWord(text, t.text, 0)
        out.push({
            kind: t.kind, text: t.text, status: t.status, token: t,
            start: at, end: at < 0 ? -1 : at + t.text.length
        })
        if (at >= 0) cursor = at + t.text.length
    }
    const missing = ((check && check.problems) || []).some((p) => p.kind === "command_missing")
    if (!missing && !out.some((c) => c.kind === "command")) {
        // The game itself: the first %command% (or an own entry's program,
        // the rest of the text after its settings and wrappers).
        let at, word
        if (own) {
            const lastSetting = out.filter((c) => c.kind === "env" || c.kind === "wrapper").reduce((m, c) => Math.max(m, c.end), 0)
            word = text.slice(lastSetting).trim()
            at = word.length > 0 ? text.indexOf(word, lastSetting) : -1
        } else {
            word = "%command%"
            at = findWord(text, word, 0)
        }
        if (at >= 0) {
            const chip = { kind: "command", text: word, status: "ok", token: null, start: at, end: at + word.length }
            let i = out.findIndex((c) => c.start > at)
            if (i < 0) i = out.length
            out.splice(i, 0, chip)
        }
    }
    for (const c of out) c.label = c.kind === "env" ? "ENV" : c.kind === "wrapper" ? "WRAPPER" : c.kind === "command" ? "GAME" : "ARG"
    return out
}

// The text with one chip's fix put in ("" takes the word out).
function applyFix(text, chip) {
    const fix = chip.token ? chip.token.fix : null
    if (fix === null || fix === undefined || chip.start < 0) return text
    const before = text.slice(0, chip.start)
    const after = text.slice(chip.end)
    if (fix.length > 0) return before + fix + after
    return (before.replace(/\s+$/, "") + " " + after.replace(/^\s+/, "")).trim()
}

// Words of `next` that are not in `base`: [{text, fresh}] for a preview.
function diffWords(base, next) {
    const have = {}
    for (const w of String(base || "").split(/\s+/)) if (w.length > 0) have[w] = true
    return String(next || "").split(/\s+/).filter((w) => w.length > 0).map((w) => ({ text: w, fresh: !have[w] }))
}

// A share (0 to 1) in whole percent ("<1%" for small ones).
function percent(share) {
    const p = Math.round((share || 0) * 100)
    return p === 0 && share > 0 ? "<1%" : p + "%"
}

// Where a launcher keeps its builds, for the group headers.
var sources = {
    steam: { name: "STEAM", path: "steamapps/common" },
    custom: { name: "CUSTOM", path: "compatibilitytools.d" },
    system: { name: "SYSTEM", path: "/usr/share/steam/compatibilitytools.d" },
    heroic: { name: "HEROIC", path: "heroic/tools" },
    lutris: { name: "LUTRIS", path: "lutris/runners" }
}
var sourceOrder = ["steam", "custom", "system", "heroic", "lutris"]

// The builds a game's launcher can use, as choices [{id, name}]; Steam's
// default first for Steam games.
function choicesFor(tools, launcher, steamDefault) {
    const out = []
    if (launcher === "steam") {
        const d = tools.find((t) => t.name === steamDefault)
        out.push({ id: "", name: "Steam default" + (d ? " (" + d.label + ")" : steamDefault ? " (" + steamDefault + ")" : "") })
    }
    for (const t of tools) {
        if (t.launchers.indexOf(launcher) < 0 || t.kind === "tool") continue
        out.push({ id: t.name, name: t.label + (t.source === "steam" ? " (Valve)" : "") })
    }
    return out
}
