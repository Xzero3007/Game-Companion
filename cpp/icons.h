// The overlay's line icons as pictures: drawn once per name, colour and
// size by QSvgRenderer (smooth edges) and kept in QML's picture cache. One
// small texture per look, shared by every icon that looks alike, instead
// of a multisampled layer per icon (that cost video memory).
#pragma once

class QQmlEngine;

/// Registers "image://icon/<path>|<colour>|<line width>|<filled>".
void gc_register_icons(QQmlEngine *engine);
