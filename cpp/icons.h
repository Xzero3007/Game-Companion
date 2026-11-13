// The overlay's line icons as pictures: drawn once per name, colour and
// size by QSvgRenderer (smooth edges) and kept in QML's picture cache. One
// small texture per look, shared by every icon that looks alike, instead
// of a multisampled layer per icon (that cost video memory).
#pragma once

#include "rust/cxx.h"
#include <cstdint>

class QQmlEngine;

/// Registers "image://icon/<path>|<colour>|<line width>|<filled>".
void gc_register_icons(QQmlEngine *engine);

/// The tray icon (the gamepad in gold) at `size` px square, as ARGB32 in
/// network byte order; empty for a size out of range.
rust::Vec<std::uint8_t> gc_tray_icon(std::int32_t size);
