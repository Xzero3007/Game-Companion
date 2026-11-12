.pragma library

// Colours and type of the Edge HUD design. No blue for controls: a
// control shows its state in the accent (gold).
var accent = "#e0a526"
var accentLight = "#f2c46b"
var red = "#d6453d"
var purple = "#9b6be8"
var purpleText = "#c4a8f0"
var text = "#f2f1f4"
var textSoft = "#c9c6d0"
var muted = "#a9a6b2"
var dim = "#8d8996"
var track = "#4a4752"
var trackDark = "#2a2830"
var divider = Qt.rgba(1, 1, 1, 0.08)
var rowLine = Qt.rgba(1, 1, 1, 0.05)
var headerTint = Qt.rgba(1, 1, 1, 0.03)

var display = "Rajdhani"
var body = "Inter"

// The panels' dark ground, as solid as the user set it (0.5 to 1).
function panel(alpha) {
    return Qt.rgba(12 / 255, 12 / 255, 15 / 255, alpha)
}
