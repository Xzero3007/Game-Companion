.pragma library
.import GameCompanion as GC

// Colours and type of the Edge HUD design. No blue for controls: a
// control shows its state in the accent (gold).
var accent = "#e0a526"
var accentLight = "#f2c46b"
var red = "#d6453d"
var purple = "#9b6be8"
var purpleText = "#c4a8f0"

// White and grey text: functions taking `hud` (true in the bar and the
// player row under it, which the user may darken: Settings → Display;
// panels stay as designed), so that bindings follow the setting.
function shade(hex, level) {
    const c = Qt.color(hex)
    return Qt.rgba(c.r * level, c.g * level, c.b * level, c.a)
}
function textShade(hex, hud) { return hud ? shade(hex, GC.Companion.textLevel) : hex }
function text(hud) { return textShade("#f2f1f4", hud) }
function textSoft(hud) { return textShade("#c9c6d0", hud) }
function muted(hud) { return textShade("#a9a6b2", hud) }
function dim(hud) { return textShade("#8d8996", hud) }
// The gold in the bar and the player row, darkened as the user set it.
function accentFor(hud) { return hud ? shade(accent, GC.Companion.accentLevel) : accent }

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
