// The Jellyfin server's pictures for QML: `image://jellyfin/<item>/<kind>/<width>`.
// The Rust side fetches them (home network only, the key in the header)
// and keeps them in memory; QML never reaches the server itself.
#pragma once

class QQmlEngine;

void gc_register_jellyfin_pictures(QQmlEngine *engine);
