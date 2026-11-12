.pragma library
.import GameCompanion as GC

// Colours and type of the Edge HUD design. No blue for controls: a
// control shows its state in the accent (gold).
var accent = "#e0a526"
var accentLight = "#f2c46b"
var red = "#d6453d"
var purple = "#9b6be8"
var purpleText = "#c4a8f0"

// White and grey text, darkened by the user's text brightness (Settings →
// General): functions, so that bindings follow the setting.
function shade(hex) {
    const level = GC.Companion.textLevel
    const c = Qt.color(hex)
    return Qt.rgba(c.r * level, c.g * level, c.b * level, c.a)
}
function text() { return shade("#f2f1f4") }
function textSoft() { return shade("#c9c6d0") }
function muted() { return shade("#a9a6b2") }
function dim() { return shade("#8d8996") }

// Almost see-through panels: text gets a thin dark shadow (Text.Raised)
// so it stays readable over the game.
var shadow = Qt.rgba(0, 0, 0, 0.85)
function textStyle() { return GC.Companion.alpha < 0.5 ? 2 : 0 }
var track = "#4a4752"
var trackDark = "#2a2830"
var divider = Qt.rgba(1, 1, 1, 0.08)
var rowLine = Qt.rgba(1, 1, 1, 0.05)
var headerTint = Qt.rgba(1, 1, 1, 0.03)

var display = "Rajdhani"
var body = "Inter"

// The panels' dark ground, as solid as the user set it (0.05 to 1).
function panel(alpha) {
    return Qt.rgba(12 / 255, 12 / 255, 15 / 255, alpha)
}
