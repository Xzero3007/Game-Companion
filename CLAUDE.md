# Game Companion: instructions for Claude

Read this first in every session on this repo. It holds what earlier sessions
learnt, so nothing has to be asked or worked out again.

## The person

- Writes in **German**: answer in German. Everything that gets built is in
  **English**: UI texts, README, code comments, commit messages, issues.
- Uses Arch with KDE Plasma on Wayland. Two monitors: the main one (Qt's
  primary screen) with the game and the meter, and an Acer X34A (DP-1, at
  0,0, left of it) with Brave. Every part stays on KDE's primary screen
  (0.4.5: Qt's primaryScreen on KWin is the first output KWin announced, not
  KDE's primary, found on real KWin 6.8; `NativeWindow::kdePrimary` reads
  `~/.config/kwinoutputconfig.json`: the "setups" entry whose enabled
  outputs equal the connected ones, its output with the lowest priority,
  1-based there, mapped by outputIndex to "outputs"[i].connectorName =
  QScreen::name(); Settings → Display "Show on" overrides it, settings
  `screen`; a layer surface's output is fixed when it is made, so `place`
  hides a visible window, sets the new screen and shows it again (0.4.7); `NativeWindow::screen`; `place` gives each window that screen's origin
  plus its place, else Qt moves it to the screen at that point: 0.4.1 drew
  on the Acer). Check with an offscreen `configfile` of two screens,
  `GC_SCREEN=<name>` (the offscreen platform makes the one at 0,0 primary)
  and `GC_DEBUG_SCREENS=1` (prints each window's screen and place).
- Wants results and a short, plain explanation of what changed and what to
  do, not a log of the work.

## Hard rules

- **As light as possible** (the person, 2026-11-12): the overlay runs over
  a game and must never make it or the desktop stutter. Nothing redraws
  while idle (no running animations, timers only while needed); every part
  is its own small overlay surface (never one window over the whole
  screen); a video redraws only its own surface; background work (mpv,
  curl) stays out of the UI thread. Before a release, measure the load
  (idle and with a stream): CPU of the app and its mpv, and that idle
  frames are zero.

- **Write down the plan before changing anything**, in plain words, and wait
  for the person's yes. They decide; don't take features away on your own.
- **Colours:** white, grey, gold, red, purple; blue is allowed too (the
  person, 2026-11-13: no aversion to blue; chat names keep their own
  colours). Accent gold `#e0a526` stays the accent for controls: a control
  shows its state in the accent, never in a fixed colour. Values the game
  colours stay so. Item grades in the game's colours with a colour dot:
  Rare green `#7fdc9a`, Legend blue `#4fa8ff`, Unique gold `#f2c46b`.
- **Design: direction B "Edge HUD"** (the person's choice, 2026-11-12): bar
  docked top centre with slanted ends and a thin gold line under it; 56 px
  bar buttons with the icon and a capitals label under it (Rajdhani 700),
  active = gold icon and 2 px gold underline; player row as a slanted strip
  under the bar (square status dots, bar-style volume); panels with square
  corners, 2 px gold top line, capitals headers, underline tabs; panel ground
  `rgba(12,12,15,0.9)` (the opacity setting); body text Inter. Purple
  `#9b6be8` / `#c4a8f0` tags the game module.
- **Nothing is sent without the person's yes.** No account, no pop-ups, no
  links out. Allowed so far (for the coming modules): the radio stations'
  streams (listening only); Twitch's public API, with Streamlink and the
  person's twitch.tv token (to Twitch only); YouTube's feeds and search
  through yt-dlp; Twitch's and YouTube's thumbnails; videos through mpv; the
  person's Jellyfin server, home network only (no server data in the repo);
  FreeTube's subscriptions file, read only; the update check (this repo's
  own GitHub releases only, the person, 2026-11-12); SponsorBlock
  (sponsor.ajay.app, hash-prefix lookup only, off until switched on; the
  person, 2026-11-12); FreeTube's settings file for its SponsorBlock
  choices, read only; FreeTube's playlists, history and profiles (groups),
  read only, taken over once by hand (Settings → Streams → YouTube); Twitch
  chat over IRC (irc.chat.twitch.tv:6697, TLS; anonymous to read, the
  person's twitch.tv token to write; the person, 2026-11-13); chat emotes
  from 7TV (7tv.io, cdn.7tv.app) and BTTV (api.betterttv.net,
  cdn.betterttv.net), asked with the channel's public Twitch id only. The AION 2 Market's prices (Clicktrough's hourly copy on
  raw.githubusercontent.com/Xzero3007/A2Tools-DPS-Meter_Clicktrough/market-data/
  and aion2.exchange's API, read only) and the game's item icons from
  assets.playnccdn.com, kept on disk (the person, 2026-11-13; src/market.rs). Brave Origin and Legcord are the
  person's own programs. Before saying something is done, grep for hosts and
  links: `grep -rnoE "https?://[a-z0-9.-]+" src cpp qml`.
- **Game modules only read** (like the AION 2 meter): never send anything to
  a game or its operator, never inject anything into a game (anti-cheat).
- **Packet captures** (`packets_*.txt` and anything worked out from them)
  never go in a repo, online, or anywhere public. Network analysis belongs in
  the private repo `Xzero3007/A2Tools-Clicktrough-Notes`.
- Never push to or open anything on `taengu/*` repos.
- Take data only where its licence allows it, and credit it as text.
- One project per repo. The Clicktrough meter stays in its own repos until
  the AION 2 module replaces it (plan step 5).
- Commit as `Claude <noreply@anthropic.com>` on `main` (or a branch and PR
  when the person wants to review first); end commit messages with the
  session's attribution lines.

## Plan (agreed 2026-11-12)

1. **Core** (done in 0.1.0): overlay on KDE's overlay layer, one lock with
   input region, shortcuts through the portal, Edge HUD bar, panels with
   remembered places, opacity, settings, Arch package.
2. Radio (done in 0.2.0: panel, player row, mpv in the background, pins and
   hub hiding, volume as one bar with − / +) and Streams (Twitch and YouTube
   done in 0.3.0; Jellyfin done in 0.3.5; design approved on the canvas
   https://claude.ai/artifact/82a3HqWJWbBRdp5FU7MvGZ page "Radio and Streams
   (B)") moved over from the meter's plugins (`Xzero3007/A2Tools-Clicktrough-Plugins`: `plugins/radio`,
   `plugins/streams`), rewritten in QML; their logic and allowed hosts kept.
   Video through libmpv (MpvQt). Then switched off in the meter by the person.
   Each game brings a preset search (the person, 2026-11-12): its Twitch
   category and YouTube search words; the Streams panel's first tab is the
   running game's (purple tag). Until game detection, AION 2 by default and
   changeable by hand.
3. Brave Origin and Legcord: **on hold** (the person, 2026-11-12). Options
   known: steer their real windows by KWin rules (as meter patch 0050), or
   try a nested Wayland compositor (Qt Wayland Compositor) to show them
   inside the app; test first.
4. Game detection with autostart (as meter patch 0037: `/proc` every 3 s, a
   list of process names per game, Proton/Steam, Lutris, Heroic). AION 2 and
   Path of Exile 2 (PoE 2 brings its own helper programs: plan them then).
   With it a **Games tab** (the person, 2026-11-12): the libraries of Steam,
   Lutris and Heroic read from disk (plus own entries), each game started
   through its launcher (e.g. `steam://rungameid/<id>`); no network. The same
   game list feeds the detection. Design approved (2026-11-12): canvas page
   "Games (step 4)", boards G4Library and G4AddGame.
5. AION 2 module (the person, 2026-11-12/13, replaces "only start the
   meter"): the Clicktrough meter becomes Game Companion's AION 2 module and
   the fork is retired once it is replaced. Decisions (what comes along,
   boss timer sources, pictures): `/mnt/project-files/game-companion/
   aion-module-decisions.md`. Order: helper, parser, DPS panel (done on
   branch `aion-module`), then Details and Battle History, then the plugins
   one by one (Map, Market, Inventory, Closet, Armory, Shugo, Event Timers,
   Pet Finder, Roster, Boss Notes with the Telegraph's parts). This replaces
   the rule "the meter stays in its own repos" for the module.
   Plex: later, home network only, as its own step.

## How it works

- One surface per part (0.4.0, the person, 2026-11-12, after stutters
  with a stream over the game): `qml/Surface.qml` is a `Window` holding one
  part (bar, player row, each panel, each video, the hub hint). No frame
  or note while unlocked (the person, 2026-11-12: in daily use it was in
  the way); the lock in the bar shows the state. While a part is dragged
  or resized, its surface holds the whole screen and stays still
  (`Surface.held`, `grab`; moves are ignored for 120 ms until `steady`;
  `qml/drag.js` `fix`: Sway measures the pointer from the window's place at
  the press, KWin from its place now; the first steady move picks the
  reading nearer the press, found on Sway by the Arch test thread): a surface
  moved per pointer event jumped about, because KDE places it a moment
  later and the next pointer place came from the old position. The part keeps x/y in **screen
  coordinates**: it lives in `Surface.scene` (screen-sized, shifted by the
  surface's place), its parent. `nativeWindow.attach` makes the window a
  layer-shell surface (overlay layer, anchored top and left, exclusive
  zone -1, keyboard none; on-demand while unlocked), `place` sets the
  margins (x, y) and size, `setInput` the input region (`QWindow::setMask`:
  unlocked everything, locked only the lock button or one pixel). X11:
  frameless on-top windows at that geometry. Dragging (`MoveArea`, the
  bar's `DragArea`, resize corners) measures in `target.parent` (screen
  coordinates), never `mapToItem(null)` (the window moves along). Popups
  must stay inside their part, or the part's surface must grow (`extra`,
  as the bar's tooltip). Stacking between surfaces is KWin's (no z across
  parts); `stack` only orders screenshots. Root of `Main.qml` is `Overlay` (a QtObject with a
  default list), **never an Item**: Qt 6.7+ embeds a Window declared inside
  an Item into that item's window (0.4.0 showed nothing on the person's Qt;
  the sandbox's Qt 6.4 does not do this). Screenshots (`GC_SCREENSHOT`): every part moves into one
  screen-sized window (`nativeWindow.shotScene`), grabbed whole (a
  software window's own grab has no alpha). Under `xvfb-run` with xcb, each
  part is its own X window (`xdotool search --onlyvisible --name "^Game
  Companion$"`, `getwindowgeometry`): good for checking places and drags.
  The radio's mpv: `--audio-buffer=1`, cache with `cache-pause-wait=4`
  (stutters when the system hangs briefly).
- One copy at a time (the person, 2026-11-12): `main.rs`
  `single_instance` holds `flock` on `$XDG_RUNTIME_DIR/game-companion.lock`
  (close-on-exec, so mpv and the installer never inherit it); a second
  start prints "already running" and ends. Ending cleanly: mpv children die
  with the app (PR_SET_PDEATHSIG); for an update the app quits and, if Qt
  hangs, exits after 5 s anyway (the installer waits for its pid).
- `src/companion.rs`: the `Companion` QML singleton (CXX-Qt). The shortcut
  thread queues onto the Qt thread (`qt_thread().queue`).
- `src/shortcuts.rs`: the GlobalShortcuts portal, adapted from the meter's
  `hotkeys.rs`; ids `lock` (Alt+Q) and `toggle` (Alt+Y, hides the hub),
  the person's own KDE keys (2026-11-12). App id
  `io.github.xzero3007.GameCompanion` (the desktop file's name).
- Display settings (the person, 2026-11-12): `alpha` 0.05 to 1 (all
  parts); `text_level` and `accent_level` 0.4 to 1 for **the bar and the
  player row only** (the person: panels like Settings or YouTube stay as
  designed); `bar` {offset px from the centre, scale 0.6 to
  1}, three presets each (`alpha_presets`, `text_presets`,
  `accent_presets`); all in layouts (old layouts lack them: kept as they
  are). `Theme.text(hud)`, `textSoft(hud)`, `muted(hud)`, `dim(hud)` and
  `accentFor(hud)` are **functions** (theme.js imports `GameCompanion` and
  reads `Companion.textLevel`/`accentLevel` when `hud` is true, so
  bindings follow): HudBar, HudButton and PlayerRow pass true, IconButton
  and VolumeBar take a `hud` property; elsewhere `Theme.text()`;
  every `Text` has `style: Theme.textStyle(); styleColor: Theme.shadow`
  (a dark outline under half opacity): keep both for new text. The bar and
  the player row scale from their top left; the surface takes the scaled
  size.
- `qml/theme.js`: the design's colours and fonts (a JS library, not a QML
  singleton: files in `qml/` would otherwise see the implicit directory
  import's non-singleton type).
- Fonts ship in the binary (Qt resources): nothing is fetched.
- `src/settings.rs`: one shared settings file (`settings::read` /
  `settings::change`), used by every QML singleton.
- The radio (`src/radio.rs`): the user's mpv as a child (`--idle`, JSON IPC
  on a socket, `--ytdl=no`, killed with the app through PR_SET_PDEATHSIG);
  `Player::load` refuses any address whose host is not in the station
  list. mpv's volume is cubic: `mpv_volume` maps the bar like a browser.
- Hub hidden (`Companion.shown` false): the bar, the welcome and settings go;
  panels and the player row stay if their id is in `pins`. Locked with the
  hub hidden, nothing takes clicks (Alt+Q / Alt+Y still work).
- Updates (`src/updater.rs`, `src/updates_object.rs`, like meter patch
  0040): the workflow publishes every push to main as release
  `v{version}-{run}` with `latest.json` (`version`, `build`, `archUrl`,
  `archSha256`, written compact: the root script reads it with sed). The app
  compares `build` with its `GC_BUILD` (0 by hand), downloads with curl
  (https, this repo's release downloads only), checks the SHA-256, and a
  detached sh waits for the app to close, runs
  `pkexec /usr/lib/game-companion-update < pkg` (the polkit policy allows it
  without a password; the script re-reads the checksum as root) or
  `pkexec pacman -U`, then starts the app again. Right before downloading it reads the latest release again (an older one found earlier would be refused by the root script, and the password asked: frequent pushes made that happen). The installer's output goes to `~/.cache/game-companion/update.log`. `GC_NO_UPDATES=1` turns the
  check off; `GC_DEMO=update` shows an update. Channels (0.4.4, the person,
  2026-11-13): `main` stable, `beta` test builds as pre-releases plus the
  rolling release `beta-channel` (its `latest.json`); Settings → General
  "Beta updates" (`Updates.beta`, `setChannel`); `GC_CHANNEL=beta` marks a
  beta build; the root script accepts stable's latest or beta's newest.
  Work in progress, milestones and the next steps: `docs/HANDOFF.md`
  (update it after every finished step).
- Panels (`qml/Panel.qml`) keep place and size in `settings.places`
  (`x`, `y`, `w` = 0 for its own width, `grow` = height added to a
  `stretchy` panel's list or video, which the panel's content adds to its
  own height). Layouts (`settings.layouts`, the person, 2026-11-12) copy
  places, pins, alpha and the open panels (`Main.openPanels()`); loading one
  raises `Companion.layoutRevision`, and every panel places itself again.
  Planned: a game can bring its own layout (step 4).
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
  `Streams.loadSegments`. Under xvfb (llvmpipe) a large video shows
  stripes after some seconds (also without resizing): most likely a
  software-GL artifact; to be checked on the person's GPU. `GC_SCREENSHOT_DELAY` sets the screenshot's moment.
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
  (`liveSorted`, `liveMoreSorted`), plain if Twitch refuses it; why a page failed shows under the
  list, `twitchMoreNote`;
  YouTube pages too: `load_more_youtube`, yt-dlp `--playlist-items`,
  subscriptions 60 a page from the kept 200), quality per channel, live notes (a thread every 120 s while
  on, generation `ALERTS_RUN`; red count, no pop-up). Videos: chapters
  (mpv `chapter-list`), speed, queue (playlists played through, shuffle,
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
- `WheelScroll`: a `Behavior` with `SmoothedAnimation` on `pos`, so wheel
  steps add to the goal without restarting the glide (MN: scrolling felt
  poor); lists keep `cacheBuffer: 600`. A notch is told by its angle (a
  multiple of 120): on KDE Wayland Qt gives a wheel notch a small pixel
  delta too, which was taken for a touchpad (MN: scrolled far too little).
  Settings → Display "Scroll speed" (`Companion.wheelSpeed`, 50 to 500 %)
  scales every step. `GC_DEMO=settings,display`.
- Hardware decoding: `Streams.hwdec` (settings `streams.hwdec`, default on)
  sets mpv's `hwdec` (auto-safe or no), at once while playing.
- `HudIcon` is a picture from the icon provider (`cpp/icons.cpp`,
  `image://icon/<path>|<colour>|<line width>|<filled>`, QSvgRenderer at
  twice the size): one small texture per look, shared and cached. It was a
  multisampled layer per icon (shapes alone were not clipped by a list's
  clip in the software renderer), which cost video memory. Needs qt6-svg
  (sandbox: `apt install qt6-svg-dev`).
- The video player (`MpvVideo`) exists only while something plays (a
  Loader in `VideoWindow`; `idleVideo` stands in): closing frees mpv and
  its video memory.
- Video checks under xvfb are flaky: the picture sometimes goes black or
  striped after a few seconds in one run and not the next (llvmpipe under
  load). Repeat a run before believing a regression.

- AION 2 module: `crates/aion2` is the meter's parser core (taengu's
  A2Tools DPS Meter v2.0.80, GPL-3.0, plus the Clicktrough backports and
  patches), files kept as they were so changes can be taken over again
  (clippy's style hints are off there). Feature `live`: the capture
  (libpcap by dlopen) and `CaptureDispatcher`. `platform/mod.rs` is the
  shim for what the meter asked of the OS (`window_detector::set_running`).
  The helper `game-companion-capture` (crates/aion2/src/bin) is the only
  part with `cap_net_raw` (packaging/arch/game-companion.install), runs
  only as the app's child (installed: the parent's exe must be the very
  file /usr/bin/game-companion, by device and inode, root's; a dev build
  checks the name only), dies with it, listens only while an AION2.exe
  process runs (ends 10 s after it), never narrows to a port below 1024,
  never drops its filter (the app's "game runs" is not taken), says why
  when it lacks the right (stderr → the panel, "Try again"), and writes
  TCP segments to stdout (`aion2::link`); the
  app writes the port detector's state back on its stdin so the capture
  filter follows the game. `aion2::engine::Engine` runs it all;
  `src/aion2_object.rs` (`Aion2` singleton) starts it when Games says
  AION 2 runs and hands QML the fight (`engine::summary`) every 500 ms only
  when it changed. `qml/DpsPanel.qml` (canvas board A4Window). The game's
  tables: crates/aion2/data → /usr/share/game-companion/aion2
  (`GC_AION2_DATA`), the helper `GC_AION2_HELPER`. `GC_DEMO=dps` shows a
  made-up fight (`,skills`, `,history`). The engine loads the tables and
  starts the helper on its own long-lived runner thread (PR_SET_PDEATHSIG
  follows the spawning thread). Battle History: `aion2::history`, the
  meter's FightRecord as JSON in ~/.local/share/game-companion/aion2/fights
  (200 kept), saved every 30 s, on Reset and on stop. Packet logging and
  the meter's sharing ring are left out: nothing captured is written down. Check the helper in the sandbox: copy
  /bin/bash to a folder as `game-companion` and run the helper from it
  (`libpcap0.8` installed), loopback traffic on a port other than 80/443.
- Pet Finder (Map's PETS tab, 2026-11-13): `aion2::pets` (frames 00/0D/14
  90, Pet Finder's checks, catalogue from `data/pets/pets.json`), kept per
  server in `~/.local/share/game-companion/aion2/pets.json`; QML gets
  `Aion2.pets` and `Aion2.petData()`. MapPanel turns it into mapkit's
  `tracked` (favourites `settings.petFavs` = "pinned", a soul within 30 min
  = "farming"), `needed` and `soulsLeft`; `qml/aion2/PetsTab.qml` is the
  list. Data and portraits: `node tools/aion2-pets-import.js`. Other
  threads read `Aion2.pets` (levels) rather than parse pet frames again.

## Checking a change

```bash
cargo test && cargo clippy --all-targets -- -D warnings
```

Screenshots without a desktop (see README): `QT_QPA_PLATFORM=offscreen`
(add `:configfile=screen.json` with a `screens` list for a 1600×900 screen),
`QT_QUICK_BACKEND=software`, `GC_NO_SHORTCUTS=1`, `GC_DEMO=...`,
`GC_SCREENSHOT=file.png`. The offscreen platform has no input regions; the
real click-through can only be checked on KDE Wayland by the person.

The sandbox is Ubuntu with Qt 6.4 and no layer-shell-qt 6: build there with
`--no-default-features`. The GitHub workflow builds on Arch with
layer-shell-qt, so it checks the layer-shell code. QML must work on Qt 6.4
for local checks (e.g. `Shape.preferredRendererType` is 6.6+).

## Known pitfalls

- `pkill -f <pattern>` also kills the shell running it: use `pkill -x`.
- GitHub starts scheduled workflows late (every 4 to 5 hours in practice).
- Wayland lets no app place or embed another app's window; only KWin
  scripts or rules can.
