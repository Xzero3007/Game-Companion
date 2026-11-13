import QtQuick
import "launch.js" as Launch

// A check status as a small square: filled or hollow in the status's
// colour (gold ok, purple outdated, red invalid, grey no effect; hollow red
// not recommended, hollow grey unknown).
Rectangle {
    property string status: "ok"
    readonly property var look: Launch.status(status)
    width: 7
    height: 7
    color: look.hollow ? "transparent" : look.color
    border.width: look.hollow ? 1.5 : 0
    border.color: look.color
}
