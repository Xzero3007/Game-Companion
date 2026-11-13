import QtQuick
import "theme.js" as Theme

// A line icon on a 24 px grid, drawn in the given colour (stroke only).
Item {
    id: icon
    property string name
    property color color: Theme.muted()
    property real size: 18
    property real lineWidth: 1.8
    /// Filled instead of drawn (the star of a favourite, play).
    property bool filled: false

    readonly property var paths: ({
        "lock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 8 0v4",
        "unlock": "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V7a4 4 0 0 1 7.8-1.2",
        "settings": "M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6",
        "close": "M18 6 6 18M6 6l12 12",
        "games": "M6 6h12a4 4 0 0 1 4 4v4a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4v-4a4 4 0 0 1 4-4z M6 12h4M8 10v4M15 11h.01M18 13h.01",
        "edit": "M4 20h4L19 9l-4-4L4 16z M13.5 6.5l4 4",
        "radio": "M12 10a2 2 0 1 1 0 4a2 2 0 1 1 0-4z M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19.1 4.9a10 10 0 0 1 0 14.2M4.9 19.1a10 10 0 0 1 0-14.2",
        "pin": "M9 4h6l-1 6 4 4H6l4-4z M12 14v7",
        "play": "M7 4l13 8-13 8z",
        "pause": "M8 5v14M16 5v14",
        "star": "M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z",
        "search": "M11 4a7 7 0 1 1 0 14a7 7 0 1 1 0-14z M20 20l-3.5-3.5",
        "chevron": "M6 9l6 6 6-6",
        "back": "M15 5l-7 7 7 7",
        "forward": "M9 5l7 7-7 7",
        "grid": "M4 4h7v7H4z M13 4h7v7h-7z M4 13h7v7H4z M13 13h7v7h-7z",
        "list": "M4 6h16M4 12h16M4 18h16",
        "rewind": "M11 6l-6 6 6 6M19 6l-6 6 6 6",
        "forwardWind": "M5 6l6 6-6 6M13 6l6 6-6 6",
        "expand": "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5",
        "shrink": "M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5",
        "minus": "M5 12h14",
        "check": "M5 12.5l4.5 4.5L19 7",
        "plus": "M12 5v14M5 12h14",
        "volume": "M11 5 6 9H2v6h4l5 4z M15.5 8.5a5 5 0 0 1 0 7",
        "prev": "M19 5 9 12l10 7z M5 5v14",
        "next": "M5 5l10 7-10 7z M19 5v14",
        "tv": "M4 7h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M17 2l-5 5-5-5",
        "refresh": "M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7",
        "update": "M12 3v12M7 10l5 5 5-5M4 20h16",
        "power": "M12 3v9M6.4 6.4a8 8 0 1 0 11.2 0",
        "hide": "M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6 0 10 7 10 7a17 17 0 0 1-3.2 4M6.6 6.6C3.9 8.4 2 12 2 12s4 7 10 7c1.9 0 3.6-.6 5-1.5M9.9 9.9a3 3 0 0 0 4.2 4.2"
    })

    implicitWidth: size
    implicitHeight: size

    // Drawn once per look by the icon provider (cpp/icons.cpp) at twice the
    // size, shared by every icon alike: smooth, clipped like any picture,
    // and light on video memory.
    Image {
        anchors.centerIn: parent
        width: icon.size
        height: icon.size
        sourceSize: Qt.size(Math.ceil(icon.size * 2), Math.ceil(icon.size * 2))
        smooth: true
        mipmap: true
        source: icon.paths[icon.name]
            ? "image://icon/" + encodeURIComponent([icon.paths[icon.name], String(icon.color), icon.lineWidth, icon.filled ? 1 : 0].join("|"))
            : ""
    }
}
