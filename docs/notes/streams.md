# Streams: Twitch, YouTube, the video player, chat

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- Streams (`src/streams.rs`, `src/streams_object.rs`, `qml/StreamsPanel.qml`,
  `qml/VideoWindow.qml`): ported from meter patches 0047, 0059 to 0061, 0068
  and the plugin. Requests through curl with its settings on stdin
  (`--config -`: the token never shows in `ps`). Videos: `cpp/mpvvideo.cpp`,
  a `QQuickFramebufferObject` with libmpv loaded by `dlopen` (headers from
  the `mpv` package at build time); mpv needs its render context before
  `loadfile` (`play` waits for `renderReady`); no OpenGL (software
  renderer) means `vo=null`, sound only. The app asks Qt for OpenGL unless
  `QT_QUICK_BACKEND` is set. QML pictures go through `PictureNetwork`
  (`cpp/native.cpp`): https, three hosts, no redirects. Check video drawing
  in the sandbox with `xvfb-run` and `QT_QPA_PLATFORM=xcb` (llvmpipe GL);
  the sandbox's network blocks Twitch and YouTube (`--ignored` test).
  `GC_DEMO=streams[,youtube],video[,quality|,opacity]` for screenshots.
  Video orientation: mpv renders with FLIP_Y 0 and the item does **not**
  mirror (it stood on its head with mirroring); check with
  `GC_TEST_VIDEO=/abs/file.mp4` (a local file plays in the Twitch window)
  under xvfb, using a test video whose top is marked (`ffmpeg -f lavfi`
  with drawbox/drawtext): testsrc looks alike both ways up.
  Following: followedLiveUsers plus twitch.tv's ChannelFollows persisted
  query and `users(ids:)` (meter patch 0068); Twitch's partial errors ride
  along as `_errors`. Subscriptions: 8 feeds at once, kept 15 minutes
  (`Streams.forget()` on refresh). Lists scroll by `WheelScroll` (Qt's own
  wheel crept, glides 160 ms); history in `StreamsPanel` (`go`, `back`,
  `forward`). Videos: a watchdog reloads at the same spot after 4 s
  without progress (20 s loading, three tries); full screen fills the
  scene (z 100, Esc); SponsorBlock in `src/sponsorblock.rs`, segments by
  `Streams.loadSegments`. YouTube serves a stream only once the ad it
  would show first has run (yt-dlp's `available_at`, the ad's length; MN,
  0.8.33: "Stuck" after three reloads): mpv 0.42's ytdl hook waits and logs
  "Waiting N seconds…" (log level info, `MpvVideo.heldUntil`), the watchdog
  waits with it and shows a countdown; for older mpv ffmpeg knocks again
  for about a minute (`reconnect_delay_max=40`) and loading may take 65 s.
  mpv opens YouTube's separate streams after FILE_LOADED (EDL
  `delay_open`): until a video first moves on (`VideoWindow.moved`) the
  watchdog keeps the loading allowance (0.8.36 on MN's mpv 0.41: reloaded
  after 4 s, fetching a new ad wait each time). yt-dlp asks as the visionOS
  player first (`MpvVideo.ytdlOptions` → `ytdl-raw-options`
  `extractor-args=youtube:player_client=visionos`; MN's test: tv_samsung got
  a 6 to 15 s ad, visionos none); after a failure, a stall or an ad wait it asks
  as any player but the TV ones (`playerStep` 1, `default,-tv,-tv_samsung,…`;
  yt-dlp's default takes tv_samsung first, MN 2026-11-21: the ad came back),
  and only then lets yt-dlp choose (`playerStep` 2). The log says each
  load's player and any ad wait (`youtube as …`, `youtube held back …`). "Stuck" names mpv's or yt-dlp's last warning
  (`MpvVideo.why`). A YouTube video that plays on with sound but no
  picture for 3 s (`MpvVideo.hasPicture`, mpv's `width`) is loaded again
  at the same spot with yt-dlp choosing the player (MN, 0.8.40: sound
  only, Twitch fine). YouTube's feeds give the channel id at their top
  without its "UC": `streams::full_channel_id` (and QML `chanId`) adds it,
  an entry's own id and the asked channel win, stored videos are mended in
  `cached_videos` (MN, 0.8.40: "Go to channel" said "not a YouTube
  channel", "Channel into group" did nothing). With no group yet, "Channel
  into group" opens the name field at once (`startGroup`). The star beside a
  video or channel subscribes at once and asks before unsubscribing
  (`starChannel`, menu kind `unsub`; MN, 0.8.43). A YouTube video
  started from a list takes the shown list along (`playVideo`: `queue`,
  `index`; `through` only for a playlist or "Play all", which go on at
  once): the player's ⏭, "UP NEXT ▾" (`upNext`, up to 50 following, shown
  as tiles with picture, length, the whole title, channel and date,
  scrolled by the wheel, a click plays one; MN 0.8.51: the old picker
  lost the click because closing it destroyed the row, so a handler that
  closes its own list takes what it needs first), AUTOPLAY in its header
  and from 640 px in the bar (`Streams.autoplay`,
  settings `streams.autoplay`, default off) and, with AUTOPLAY on, the
  5 s "NEXT:" note (`nextItem`, shared with Jellyfin's next episode).
  Settings → Streams → Videos "Close the player when nothing follows"
  (`Streams.closeAtEnd`, `close_at_end`, default off): `nothingFollows`
  → `closeIfEnded` (via `Qt.callLater`, never inside the player's own
  signal) → `stop()`, which lets mpv go as the close button does; for
  YouTube, Twitch and Jellyfin (after no next episode or track came).
  Narrow windows: with UP NEXT the time buttons hide below 560 px and
  speed below 520 px (MN, 2026-11-15). The game's search with "Newest
  first" is also sorted here by date (YouTube's own order was loose).
  A video being dragged or resized stays still (`Surface.held` →
  `MpvVideo.frozen`, sound plays on, watchdog paused): redrawn with every
  move, the move stuttered (MN, 0.8.49). `GC_DEMO=video,upnext[,upnextlist|,nextnote],unlocked`.
  Searches asked in another language than English (`youtube:lang=`) come
  without dates (yt-dlp reads English time texts only): `dates_later`
  asks the feeds of up to 24 channels in the list not asked for 15 minutes,
  stores them in the feed cache and fills the shown list
  (`apply_known_from`; also History and playlists, whose entries keep what
  a video had when added). Order (MN, 0.8.43): "Sort ▾" left of the arrows,
  settings `streams.sorts` per view (`Streams.setSort`, in `filters`);
  the game's search asks YouTube in its order (`game_sp`: relevance, date,
  views), the others are sorted as loaded (`StreamsPanel.youtubeShown`,
  `sortVideos`; playlist Move up/down only in the playlist's own order).
  Videos no feed dates any more (a channel that uploads a lot) get one
  yt-dlp look each (`youtube_video_date`, at most 6 per list, kept in
  ~/.cache/game-companion/youtube-dates.json). Spectacle (Print): its
  selection is a layer surface on the same overlay layer as our parts;
  the apps watcher reports a "spectacle" window as big as its screen
  (`gcShot`, event `shot`) → `Apps.screenshot`: videos frozen (watchdog
  paused), every part's input region one pixel (Surface.applyInput), so
  nothing flickers over its frozen picture and clicks are Spectacle's
  (MN, 0.8.49). Spectacle's selection is full screen and takes the
  focus: `apps::desktop_tool` keeps it (and plasmashell, KRunner, the lock
  screen, polkit) out of the full-screen game logic; taken for a game
  while Brave was shown, it lost its full-screen mark, took it back, five
  times, and the screens flickered (MN, 0.8.51). `GC_DEMO=…,shot` sets it (under xcb the one-pixel mask
  also hides the windows: an X11 artifact).
  Subscriptions in the background (feeds, lengths) show only for the
  channels shown now (`subs_shown`, set with `SUBS_REQUEST`): a look
  started for All and finished after a group was chosen showed every
  channel's videos over the group (MN, 0.8.59); it shows the group's stored
  videos instead (`show_shown_subscriptions`). The top row's reload chip
  (MN, 2026-11-16, was a small ↻ in the footer) says when the list is from:
  `Streams.youtubeAsOf` (subscriptions: the newest feed ask of the shown
  channels, `feeds_as_of`), `twitchAsOf`, Jellyfin's by QML; its words and
  the sort chip's shorten to fit beside the tabs (`topRow.fit`). The
  Channels list swaps like the video list (`channelModel`,
  `swapChannels`): putting a channel into a group kept jumping to the top.
  A video window on SOUND ONLY (`VideoWindow.soundOnly`) goes with the hub,
  pinned or not, as the radio does, and is a slim strip without picture
  (`compact`: its bars, always shown, `compactHeight` 90; MN 0.8.62: the
  last picture stood still); `fullHeight` and the place with a picture are
  kept (`remember`), the bottom edge stays; lists and notes open above it
  and the surface grows upwards meanwhile (`overStrip`, Surface `extra`).
  Lists keep their place when their array is replaced (load more, the
  background subscriptions look, lengths coming in; MN 0.8.37: jumped to
  the top): `StreamsPanel.listModel` is set by `swapList` from
  `listWanted`, which finds the first row seen in the new array by
  `itemKey` when `listKey` (tab, view, arg, channel, search) is the same.
  Lengths: feeds have none, so `lengths_later` → `fill_lengths` asks yt-dlp
  for each stored channel's videos tab (15, 3 at once, 40 channels a time)
  when its newest video changed since (`lengths_for` in the feed cache);
  the channel view fills its own (`channel_lengths_later`). Dates: yt-dlp
  flat lists ask `youtubetab:approximate_date` (English time texts only),
  marked `rough`; `apply_known` takes the feed cache's exact dates and
  lengths. `ago(iso, rough)`: within a week how long ago, then the date (a
  rough one stays "3 weeks ago"). `VideoByline.qml`: channel name opens
  the channel (also ⋯ "Go to channel", "Channel into group ▸", which
  subscribes first); the GROUPS row shows in Subscriptions and Channels
  even without groups, saying how to make one. A grab first freezes a
  playing video (`Surface.settling` → `MpvVideo.frozen`: no frames, no
  position updates) and changes the surface's size 40 ms later
  (`holdLater`), unfrozen 250 ms after: a frame drawn at the old size and
  committed with the new one showed the whole window stretched over the
  screen (MN; Sway bench, about every second grab while playing, never
  paused; 0.8.38's freeze at the same moment as the resize didn't help).
  Bench check: `arch-test/video-drag.sh` (project folder).
  Under xvfb (llvmpipe) a large video shows
  stripes after some seconds (also without resizing): most likely a
  software-GL artifact; to be checked on the person's GPU. `GC_SCREENSHOT_DELAY` sets the screenshot's moment.

- YouTube library (`src/library.rs`, `src/library_object.rs`, the
  `Library` singleton; 0.6.x, replacing FreeTube): playlists (one is the
  quick bookmark's, "Watch later" by default), history with where each
  video stopped (`record` every 10 s from `VideoWindow.keepPosition`
  kept in memory, `change_quiet`; written in the background at most once a
  minute and at once on pause, end, close and quit, `save_soon`/`save_now`;
  `resumeAt` on start) and watched marks, in `youtube.json` beside
  settings.json. `take_freetube` (Streams) reads FreeTube's NeDB files
  (profiles → subscription groups, playlists, history, the quick bookmark
  target from settings.db) once; then FreeTube's subscriptions file is no
  longer read (`freetube_live` false). Streams lists: Shorts left out by
  default (`hide_shorts`), watched, channels and words left out, and
  titles or channel names in an Indian script (`hide_indian`, default on,
  `streams::indian_script`; MN, 2026-11-13); search
  filters as YouTube's `sp` (protobuf, `search_param`); Trending is yt-dlp
  searches per part (`TREND_SECTIONS`, words changeable in Settings), as
  YouTube's own trending page is gone. Video languages (`video_languages`,
  default the desktop's `LANG`): searches ask yt-dlp with `youtube:lang=`
  (hl; region follows the IP, yt-dlp has no `gl`), Trending once per
  language, Gaming/Europe/national with the language's word
  (`trend_searches`; MN saw Indian channels with plain "gaming"). Twitch: categories, a channel's
  past broadcasts and clips (played through yt-dlp), filters (language,
  reruns, order; `liveMore` falls back to plain `live` if Twitch refuses
  its fields; live lists, categories, past broadcasts and clips page by
  Twitch's cursors, `fetch_twitch`, `load_more_twitch` at the list's end
  or by "Load more", `GC_DEMO=…,more`; the cursor is written into the
  query as a string: a typed `$a: Cursor` variable brought nothing on
  MN's test; on 0.7.7 Twitch sent the first page again for a cursor, so
  when a page brings nothing new `load_more_twitch` asks for a longer list
  from the top instead (`{"first": n}`, `twitch_query_page`, 30 more each
  time, at most `TWITCH_LONGEST` 100; that helped Categories). All live
  still sent the same 30 for cursor and length (0.8.2), so live lists ask
  `options: { sort: VIEWER_COUNT }` as Twitch's directory does
  (`liveSorted`, `liveMoreSorted`), plain if Twitch refuses it. That still
  sent the same 30 (0.8.6), so All live now asks Twitch's own directory
  query first, the persisted `BrowsePage_Popular` (`twitch_browse`, the
  known ids in `BROWSE_POPULAR` tried in turn, the one that answered kept;
  cursor and `limit` as variables), the written-out query only if no id
  answers. Still the same 30 on 0.8.12, so when a page of All live brings
  nothing new, `load_more_twitch` sweeps categories instead: the streams of
  the next `SWEEP` (6) most watched categories in one aliased request
  (`twitch_sweep_query`, `sweep_cards`, `sweep_page`, `{"sweep": p}`, up
  to `SWEEP_LONGEST` 60 categories). "Twitch sent nothing new" names the
  ways tried (`TWITCH_WAY`, e.g. the directory query's refusal); why a page failed shows under the
  list, `twitchMoreNote`;
  YouTube pages too: `load_more_youtube`, yt-dlp `--playlist-items`,
  subscriptions 60 a page from the kept 300; each channel's feed gives its newest 15, a feed that fails is asked once more after 3 s, the rest shows as "N channels didn't answer", MN 0.8.33; every video a channel's feed brought is stored in ~/.cache/game-companion/youtube-feeds.json, up to 50 per channel (`merge_videos`; MN 0.8.36: a list that grows, only the new ones fetched): Subscriptions shows the stored list at once and asks only channels not asked for 15 minutes, in the background (`update_feeds`, `SUBS_UPDATING`, applied if `SUBS_REQUEST` is still the latest request, "looking for new ones…"), a channel that fails keeps its videos, ↻ asks all, `FEEDS_FORCED`; some channels' feeds answer 404 for good (Level1Techs): yt-dlp looks at their videos tab instead, `youtube_channel_newest`, in Subscriptions at most 12 channels, 5 videos each, without dates), channel pictures (0.8.4:
  once per channel, FreeTube's profiles file first, else yt-dlp
  `--playlist-items 0` on the channel page, `streams::channel_picture`;
  settings `channel_pictures`, the `channelPictures` property, shown
  square in the Channels list; yt3.ggpht.com only), quality per channel, live notes (a thread every 120 s while
  on, generation `ALERTS_RUN`; red count, no pop-up). Videos: chapters
  (mpv `chapter-list`), speed, "PLAYLIST ▾" (into a playlist or out), queue (playlists played through, shuffle,
  loop). `GC_DEMO=streams,yt-<view>` / `tw-<view>`, `news`, `groups`,
  `ytsettings`.
- Twitch chat (`cpp/twitchchat.cpp`, `TwitchChat` in `GameCompanion.Chat`;
  `qml/ChatPanel.qml`, panel id `chat`): QSslSocket to Twitch's IRC, CAP
  tags/commands, `justinfan…` to read or PASS `oauth:<token>` to write
  (`Streams.chatAuth()`: only when signed in and Settings → Streams →
  Twitch "Write in chat" is on; a refused sign-in falls back to reading),
  reconnects with a growing wait (dropping the old socket has its signals
  blocked, or one RECONNECT looped forever; check with
  `tools/chat-test/run.sh`, a made-up IRC server). Connected only while the panel shows
  (`running`). Lines come in batches every 250 ms (a timer only while lines
  wait), 200 kept, StyledText with emotes as `<img>` sized ahead (Twitch's
  static pictures, 7TV/BTTV from `src/emotes.rs` with their 1x sizes);
  pictures are still (first frame): nothing moves while idle. 7TV is WebP:
  qt6-imageformats (optdepends). Docked right of the Twitch video
  (`chat_docked`), moved by hand it stays; "Dock" in its header brings it
  back. Its own ground opacity (`opacityOf("chat")`, 10 to 100). Shown with
  the speech bubble on the Twitch video (`chat_open`). `GC_DEMO=video,chat`.

- Hardware decoding: `Streams.hwdec` (settings `streams.hwdec`, default on)
  sets mpv's `hwdec` (auto-safe or no), at once while playing.
- Video loudness (MN, 2026-11-14: videos quieter than the radio, which is
  mixed louder): Settings → Streams → Videos "Video loudness"
  (`Streams.videoBoost`, settings `streams.video_boost`, 0/3/6/9 dB;
  `VideoWindow.mpvVolume` multiplies by 10^(dB/60), mpv's `volume-max`
  150) and "Even out loudness" (`Streams.evenLoudness`, `MpvVideo.levelling`:
  mpv `af` = `lavfi=[dynaudnorm=f=250:g=15]`). The radio's own mpv is not
  touched.

- Video timing (MN, 2026-11-16: Jellyfin didn't play smoothly): mpv runs
  with `video-timing-offset=0`. With mpv's default (0.05) every
  `render_render` waited on Qt's render thread for the frame's time, about
  36 of every 42 ms at 24 fps (`GC_DEBUG_RENDER=1` prints each frame's
  render time). On stop or switch each video window logs `[video]` with
  `MpvVideo.playStats()` (codec, size, fps, hwdec, dropped and late
  frames). At a file's end mpv has already let it go (every value "-"):
  the values read while it played (on time-pos, every 2 s at most,
  `m_lastStats`) stand in.
- The video player (`MpvVideo`) exists only while something plays (a
  Loader in `VideoWindow`; `idleVideo` stands in): closing frees mpv and
  its video memory.
- Video checks under xvfb are flaky: the picture sometimes goes black or
  striped after a few seconds in one run and not the next (llvmpipe under
  load). Repeat a run before believing a regression.
- Player keys and pointer (MN, 2026-11-18): `qml/playerkeys.js` lists the
  actions and their default keys (Space/K pause, ←/→ step, J/L 10 s, ↑/↓
  volume, M mute, F full screen, Home/End, PgUp/PgDown chapters, [ ] and
  Backspace speed, N/P next/previous, S skip, V/A Jellyfin tracks, C chat,
  I bars; 0 to 9 and Esc fixed). `VideoWindow` makes one `Shortcut` per
  action (a Repeater of Items, so each finds its window), enabled while
  unlocked and the window plays; the surface has keys only after a click
  into it (Surface/native.cpp), so they work in the small window after a
  click and in full screen, never by themselves. A key's effect shows
  1.2 s in the window's top centre (`say`). Full screen: a single-shot
  timer (`idleTimer`, only while full screen) hides the pointer
  (`BlankCursor` on the MoveArea) and the bars after `hide_pointer` s;
  only a real move (≥ 2 px) brings them back: Qt sends hover again with
  every frame while a video plays. Settings `streams.player`
  (`PlayerPrefs`: hide_pointer 10, keys, seek_step 5, volume_step 5,
  key_map action → keys), `Streams.player` JSON, `Streams.savePlayer`;
  Settings → Streams → Videos "Pointer and keys" records a key
  (`PK.sequenceOf`), refuses one another action has. Check under
  `xvfb-run` with xcb: `GC_DEMO=unlocked GC_TEST_VIDEO=<file>`, click
  into the video, `xdotool windowfocus --sync` (no window manager), then
  `xdotool key` without `--window`. `GC_DEMO=settings,hwdec[,recordkey]`.
  The wheel over a video window changes its volume by `volume_step`
  (`wheel_volume`, default on; the MoveArea's `onWheel`, 120 per notch,
  a touchpad's small steps add up; MN, 2026-11-18); lists and the
  opacity button keep their own wheel.
- HDR video ("Weg C", MN, 2026-11-18; plan and pictures in the project
  folder `game-companion/hdr/hdr-plan-c.html`): Qt's overlay is 8-bit SDR,
  so the picture goes on a Wayland subsurface of its own right under the
  video window's surface (`HdrVideo`, cpp/hdrvideo.*): `place_below`,
  desync, empty input region, `wp_viewporter` for its size,
  `wp_alpha_modifier_v1` for the window's opacity, and
  `wp_color_management_v1` (PQ / BT.2020 parametric description) while an
  HDR video plays (`video-params/gamma` pq or hlg → mpv `target-trc=pq`,
  `target-prim=bt.2020`, no tone mapping by mpv; KWin fits it to the
  screen). A thread of its own draws it with an EGL context of its own on
  Qt's wl_display (10 bit, else 8; `eglSwapInterval 0`, paced by mpv's
  update callback; never `eglTerminate`); mpv's render context lives on
  that thread (`MpvCore::hdrRender`), Qt's renderer makes none and clears
  its frame buffer see-through, the window's backdrop hides
  (`VideoWindow.hdrSurface`). Placed on each `beforeSynchronizing` (Qt's
  render thread, GUI waiting): the subsurface's position takes hold with
  the window's next commit, so it moves with the window. Our own Wayland
  objects live on an event queue of ours (`WlColor`, cpp/wlcolor.*), Qt's
  are untouched; Qt's private `QPlatformNativeInterface` gives the
  wl_display and a window's wl_surface (build.rs finds QtGui's private
  headers through qmake). Setting `streams.player.hdr` (default on;
  Settings → Streams → Videos → HDR "HDR video"; on takes hold with the
  next video window, off at once). Falls back to Qt's drawing by itself:
  not Wayland, no colour management or no PQ ("unavailable: …"), no EGL
  context or mpv can't take it ("fell back: …" at start), or the EGL
  surface fails later (`HdrVideo::failed` → `dropHdr`: what played starts
  again where it was). The log says which: `[video] hdr <state>`
  (`MpvVideo.hdrState`: off, unavailable, fell back, "sdr (10 bit)",
  "hdr (10 bit)", "hdr refused: …"). HDR test picture: Settings → Streams
  → Videos "Show" (or `GC_DEMO=hdrtest`): grey patches 203, 400, 800, 1200
  and 1900 nits (MN's LG G5 with HGIG: 1900 peak, 800 paper white) and a
  0 → 2000 nit band on an shm subsurface (`HdrTest`), its findings in the
  log. Bench: Weston 15 (`session-weston.sh`, color-management=true)
  announces PQ but its LittleCMS can't build the transform and ends the
  client's connection ("no memory"): no use for PQ itself. Sway and KWin
  here have no colour management. So the surface is checked on Sway with
  `GC_HDR_FORCE=1` (everything but the PQ description): `video-hdr.sh`,
  `video-keys.sh`, `video-drag2.sh`, `video-opacity.sh`, `video-drop.sh`
  (`GC_HDR_DROP_AFTER=<ms>` makes it fail while playing). Real HDR
  brightness only on MN's screen.
  0.8.75 on MN's NVIDIA RTX 4090 (KWin): the picture stayed black while
  the time ran (SDR too); the test picture worked. Since then the drawing
  thread reads back 9 pixels every 60 frames until one isn't black; six
  black looks in a row fall back by themselves ("fell back: the picture
  stayed black"), a failed `eglSwapBuffers` too. The log line carries EGL's
  and GL's vendor, renderer and version (`MpvVideo.hdrInfo`). Bench:
  `VIDEO=/tmp/black.mp4 WAIT=20 video-drop.sh` falls back, a test picture
  doesn't.
  MN's 0.8.75 log said "8 bit": NVIDIA offers 10 bit only as RGB10_A2,
  so configurations with alpha are taken too (shown opaque with
  EGL_EXT_present_opaque), and the display is asked for as a platform
  display (as Qt does). A fall back starts a fresh mpv: one whose render
  context moved while playing went on without hwdec ("hwdec -"). mpv's
  lines about drawing and decoding go to the log while the surface draws
  (`hdrNote`, "[video] hdr mpv …", 30 per window).
  0.8.76 on MN's NVIDIA 620.70.06: still black (EGL NVIDIA, 8 bit), the
  fall back worked, but Twitch then played nothing: the fresh mpv was
  handed the old Streamlink pipe (`fdclose://`), gone with the old mpv.
  Now `reloadNeeded(position)` makes the window ask for the video again
  (`win.load`: a new Streamlink, a new Jellyfin session). mpv now draws
  into a frame buffer of ours (a texture of RGB10_A2 or RGBA8, its format
  passed to mpv as on Qt's way, which works on NVIDIA), copied upside down
  onto the window's with glBlitFramebuffer (`GC_HDR_DIRECT=1`: straight
  into the window as before). The log names the driver's 10-bit configs
  and, at the first black look, whether mpv's frame buffer or only the
  window's is black. Per source (MN: "bis dato jelly und yt"):
  `hdr_youtube` and `hdr_jellyfin` on, `hdr_twitch` off. The video
  window's bar shows a gold "HDR" while an HDR video shows in HDR, a grey
  "SDR" while one shows without (`MpvVideo.sourceHdr`). The strip's volume
  bars (and the video window's) step by the player's `volume_step`, one
  step per wheel notch (`VolumeBar` adds up angleDelta).
  0.8.77 on MN's NVIDIA 620.70.06: mpv's frame buffer was lit, the
  window's stayed 0/0/0, and EGL listed no 10-bit configs at all: NVIDIA's
  egl-wayland (the EGL window surface) was the broken part; the HDR test
  (an shm buffer of its own) showed PQ in 10 bit. Since 0.8.78 there is no
  EGL window surface: the drawing thread has a context only (surfaceless,
  `EGL_KHR_no_config_context`) and hands its frames over as buffers of
  ours (`HdrBuffers`, cpp/hdrbuffers.*), three of them, on an event queue
  of its own, a frame skipped (never waited for) when the compositor holds
  all three. First choice dmabuf: `zwp_linux_dmabuf_v1` version 3 (its
  format/modifier pairs in `WlColor::dmabufFormats`), libgbm loaded with
  dlopen on EGL's own render node (`EGL_EXT_device_query`), XB30 (10 bit)
  before XR30, XB24, XR24, a modifier both EGL
  (`eglQueryDmaBufModifiersEXT`, not external-only) and the compositor
  know, else the implicit layout if the compositor lists it; the buffer is
  an EGLImage texture mpv draws into, `glFinish` before the commit (NVIDIA
  has no implicit sync), the wl_buffer asked for with `create` and waited
  for (never `create_immed`: a refusal there ends Qt's connection). If any
  of that fails it switches to shm for good: mpv into a texture of ours,
  `glReadPixels` into an shm buffer (XB30 as RGBA + 2_10_10_10_REV, XR30
  and XR24 as BGRA), one copy per frame. `GC_HDR_PATH=dmabuf|shm` tries
  only that way. The log names it: `… ; dmabuf XB30 (10 bit)`, "buffers:
  dmabuf XB30, modifier 0x…, 1 plane(s)", "dmabuf failed (…): shm
  instead", "picture seen after 60 frames (…, shm XB30 (10 bit))". The
  black check reads mpv's frame buffer (the buffer itself). The bench
  (Sway pixman, no GPU, no /dev/dri) only checks shm; dmabuf only on MN's
  card.
  0.8.78 on MN's RTX 4090: "hdr (10 bit) … dmabuf XB30", modifier
  0x300000000606014, 1 plane, picture seen, 4K AV1 without drops.
- HDR badges on the lists' pictures (MN, 2026-11-19: "bei allen fenster wo
  videos angezeigt werden"; "geht das auch bei jelly"): a gold badge bottom
  left (`HdrBadge` in StreamsPanel, the same in the video window's Up next).
  Jellyfin: the list query asks `MediaStreams` too; the first video
  stream's VideoRangeType gives "DV" (DOVI*), "HDR10+", "HDR" (HDR10, HLG,
  or VideoRange HDR) as the item's `hdr` (`jellyfin::hdr_label`).
  YouTube: no list says it, so `yt_hdr` (src/yt_hdr.rs) looks at each
  video of the open list once (`yt-dlp --print
  "%(formats.:.dynamic_range)l"`, any HDR*, HLG or DV), two at once on two
  threads of their own, only while the list shows (`StreamsPanel.hdrIds` →
  `Streams.wantHdr`, "[]" stops), none while a game runs
  (`Games.running` → `Streams.setHdrPaused`); each yt-dlp ends with the app
  (PR_SET_PDEATHSIG from its waiting thread), 40 s at most. Answers kept
  for good in ~/.cache/game-companion/youtube-hdr.json (newest 5000), a
  failed look not asked again this session; a video the player shows in
  HDR is noted at once (`Streams.noteHdr`; SDR never: a video can play in
  an SDR format of its own). `Streams.hdrOf(id)` with `hdrRevision` for
  bindings. Bench: a fake yt-dlp on PATH (`demo000000N` ids).
