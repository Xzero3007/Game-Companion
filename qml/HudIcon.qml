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
    /// Filled instead of drawn (the star of a favourite, play).
    property bool filled: false

    readonly property var paths: ({
        "lock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 8 0v4",
        "unlock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 7.8-1.2",
        "settings": "M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6",
        "close": "M18 6 6 18M6 6l12 12",
        "radio": "M12 10a2 2 0 1 1 0 4a2 2 0 1 1 0-4z M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19.1 4.9a10 10 0 0 1 0 14.2M4.9 19.1a10 10 0 0 1 0-14.2",
        "pin": "M9 4h6l-1 6 4 4H6l4-4z M12 14v7",
        "play": "M7 4l13 8-13 8z",
        "pause": "M8 5v14M16 5v14",
        "star": "M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z",
        "search": "M11 4a7 7 0 1 1 0 14a7 7 0 1 1 0-14z M20 20l-3.5-3.5",
        "chevron": "M6 9l6 6 6-6",
        "minus": "M5 12h14",
        "plus": "M12 5v14M5 12h14",
        "volume": "M11 5 6 9H2v6h4l5 4z M15.5 8.5a5 5 0 0 1 0 7",
        "prev": "M19 5 9 12l10 7z M5 5v14",
        "next": "M5 5l10 7-10 7z M19 5v14",
        "hide": "M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6 0 10 7 10 7a17 17 0 0 1-3.2 4M6.6 6.6C3.9 8.4 2 12 2 12s4 7 10 7c1.9 0 3.6-.6 5-1.5M9.9 9.9a3 3 0 0 0 4.2 4.2"
    })

    implicitWidth: size
    implicitHeight: size
    // Drawn into a texture: clipped like any picture inside a list (a
    // shape alone is not clipped by every renderer), and smoother when small.
    layer.enabled: true
    layer.samples: 4
    layer.smooth: true

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: icon.size / 24
        ShapePath {
            strokeColor: icon.color
            strokeWidth: icon.lineWidth
            fillColor: icon.filled ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.paths[icon.name] || "" }
        }
    }
}
