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
        "swords": "M14.5 17.5 3 6V3h3l11.5 11.5 M13 19l6-6 M16 16l4 4 M19 21l2-2 M14.5 6.5 18 3h3v3l-3.5 3.5 M5 14l4 4 M7 17l-3 3 M3 19l2 2",
        "wand": "M15 4V2 M15 16v-2 M8 9h2 M20 9h2 M17.8 11.8 19 13 M15 9h.01 M17.8 6.2 19 5 M3 21l9-9 M12.2 6.2 11 5",
        "warning": "M12 3 2 21h20z M12 10v5M12 18h.01",
        "proton": "M12 2l8.5 5v10L12 22l-8.5-5V7z M12 8l3.5 2v4L12 16l-3.5-2v-4z",
        "games": "M6 6h12a4 4 0 0 1 4 4v4a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4v-4a4 4 0 0 1 4-4z M6 12h4M8 10v4M15 11h.01M18 13h.01",
        "market": "M4 7h16l-1.5 12h-13z M8 7a4 4 0 0 1 8 0 M9 12h6",
        "loot": "M4 9h16v10H4z M4 9l2-4h12l2 4 M10 13h4",
        "characters": "M9 11a3.5 3.5 0 1 0 0-7a3.5 3.5 0 0 0 0 7z M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6 M16 4.5a3.2 3.2 0 0 1 0 6.2 M18 14c2 .8 3 2.8 3 6",
        "map": "M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z M9 3v15M15 6v15",
        "dps": "M4 20V11M10 20V5M16 20v-8M21 20H3",
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
        "bookmark": "M6 3h12v18l-6-4.5L6 21z",
        "more": "M5 11a1 1 0 1 1 0 2a1 1 0 1 1 0-2z M12 11a1 1 0 1 1 0 2a1 1 0 1 1 0-2z M19 11a1 1 0 1 1 0 2a1 1 0 1 1 0-2z",
        "shuffle": "M3 7h4l10 10h4M3 17h4l3-3M14 10l3-3h4M18 4l3 3-3 3M18 14l3 3-3 3",
        "loop": "M4 12V9a3 3 0 0 1 3-3h12M16 3l3 3-3 3M20 12v3a3 3 0 0 1-3 3H5M8 21l-3-3 3-3",
        "chat": "M4 5h16v11H9l-5 4z",
        "bell": "M6 16v-5a6 6 0 1 1 12 0v5l2 2H4z M10 20.5a2 2 0 0 0 4 0",
        "up": "M6 15l6-6 6 6",
        "trash": "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13",
        "history": "M3 12a9 9 0 1 0 2.6-6.4M3 4v5h5 M12 8v4l3 2",
        "send": "M4 12l16-8-6 16-3-7z",
        "plus": "M12 5v14M5 12h14",
        "volume": "M11 5 6 9H2v6h4l5 4z M15.5 8.5a5 5 0 0 1 0 7",
        "prev": "M19 5 9 12l10 7z M5 5v14",
        "next": "M5 5l10 7-10 7z M19 5v14",
        "tv": "M4 7h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M17 2l-5 5-5-5",
        "refresh": "M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7",
        "update": "M12 3v12M7 10l5 5 5-5M4 20h16",
        "power": "M12 3v9M6.4 6.4a8 8 0 1 0 11.2 0",
        "eye": "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6",
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
