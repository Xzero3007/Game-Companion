import QtQuick
import QtQuick.Shapes
import "theme.js" as Theme

// A line icon on a 24 px grid, drawn in the given colour (stroke only).
Item {
    id: icon
    property string name
    property color color: Theme.muted
    property real size: 18
    property real lineWidth: 1.8

    readonly property var paths: ({
        "lock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 8 0v4",
        "unlock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 7.8-1.2",
        "settings": "M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6",
        "close": "M18 6 6 18M6 6l12 12",
        "hide": "M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6 0 10 7 10 7a17 17 0 0 1-3.2 4M6.6 6.6C3.9 8.4 2 12 2 12s4 7 10 7c1.9 0 3.6-.6 5-1.5M9.9 9.9a3 3 0 0 0 4.2 4.2"
    })

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: icon.size / 24
        ShapePath {
            strokeColor: icon.color
            strokeWidth: icon.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.paths[icon.name] || "" }
        }
    }
}
