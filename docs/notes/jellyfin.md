# Jellyfin

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- Jellyfin (`src/jellyfin.rs`, `src/jellyfin_object.rs`, the `Jellyfin`
  singleton; meter patch 0053 and the plugin's `jellyfin.js`): the server
  must be a home network's (`parse_server`; a name counts only when all its
  addresses are local, `local_addresses`, checked again on every request).
  curl with `-q` (no curlrc), `noproxy *`, no `location`, the checked
  address pinned by `resolve`, the key in the Authorization header on
  stdin. Account in `jellyfin.json` (0600, beside settings.json; never in
  the repo), the password never kept. Pictures through the C++ provider
  `image://jellyfin/<item>/<kind>/<width>` (`cpp/jellyfinpictures.cpp`
  calls `gc_jellyfin_picture` in Rust), kept in memory. The Jellyfin video
  window's `MpvVideo` has `local: true` (no ytdl, no scripts,
  `stream-lavf-o=http_proxy=`: an empty proxy beats the environment's) and
  the key as `http-header-fields`. Plays from `prepare` → `prepared`
  (url, header, source, session, tracks); reports start/progress (10 s,
  pause)/stopped; segments from `/MediaSegments` or Intro Skipper; next
  episode by `find_next`. Check against the made-up server:
  `tools/fake-jellyfin.py <scratch dir>` (127.0.0.1:8096, user me / pw,
  token tok123; logs requests to `requests.log` in that folder) and
  `GC_FAKE_JELLYFIN=127.0.0.1:8096 XDG_CONFIG_HOME=<scratch> cargo test
  --no-default-features made_up -- --ignored`; the fake's mp4 needs
  faststart and Range answers, and without a sound card mpv ends a file
  with sound in an error (use a silent clip to see "ended"). xdotool under
  `xvfb-run` drives clicks (`QT_QPA_PLATFORM=xcb`). `GC_DEMO=streams,jellyfin`
  (made-up list, signed in), `jellyvideo` (its window with tracks and SKIP
  INTRO), `settings,jellyfin`, `settings,hwdec`.

- Jellyfin Continue and Next up (`series_first`): an episode shows the
  series' name, then code and episode, with the series' thumb (else
  backdrop, else poster); collections (boxsets) are a library.
- Jellyfin music (0.8.2, MN): a music library opens to its albums (by
  artist), an album to its tracks (`folder`, kind `MusicAlbum`); a track
  (`sound_only` source) plays its file as it is (`audio_path`, no
  segments asked) in the Jellyfin window with the album's cover over it,
  previous/next track buttons and the album played through
  (`find_track` → `album_track`). The fake server has a music library
  (`song.ogg`); without a sound card a `~/.asoundrc` with
  `pcm.!default { type null }` lets mpv play (and end) sound in the
  sandbox (remove it after).
