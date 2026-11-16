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
  corners, no gold line on top (MN, 2026-11-14: removed everywhere),
  capitals headers, underline tabs; panel ground
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
  assets.playnccdn.com, kept on disk (the person, 2026-11-13; src/market.rs); Aion 2 Timers' field boss feed
  (www.aion2timers.com/api/fieldboss.php?action=feed&server=<region-name>,
  read only, off until switched on, every 5 min while the Schedule is open
  or 15 while a boss alert waits; src/aion2timers.rs; the person,
  2026-11-13); the Armory's NC character pages (aion2.plaync.com,
  api-search.plaync.com, profileimg.plaync.com; read only, no account;
  src/armory.rs `allowed`; MN, 2026-11-13). The Legcord voice overlay
  (MN, 2026-11-14) opens no connection at all: its Legcord plugin talks to
  Game Companion over a Unix socket; avatars are fetched by Legcord itself
  (its session, cdn.discordapp.com, as it does anyway). The PoE 2 price check (MN, 2026-11-15:
  "bau ee2 nach"): www.pathofexile.com/api/trade2/ only (search, fetch,
  exchange, data; src/poe2.rs `allowed`), asked when an item is checked;
  "Trade site ↗" opens the same search on www.pathofexile.com/trade2/
  (search or exchange pages only, `trade_page_ok`) in the person's own
  browser through xdg-open, only on a click (MN, 2026-11-15: "es muss nur
  aufgehen wenn ich da was anklicken kann"). poe.ninja's PoE 2 economy
  (poe.ninja/poe2/api/economy/ only: leagues, exchange, stash; GET, no
  cookies; `ninja_allowed`), the league's currency overview once in 30
  minutes when an item is checked, on by default, off under Settings →
  Plugins → PoE 2 "poe.ninja prices" (MN, 2026-11-15: "standartmäßig an
  kann man aber auch aus klicken"). poeprices.info: not until it
  knows PoE 2 (MN chose so, 2026-11-15; EE2 itself switched it off).
  Brave Origin, Legcord and Rusty Path of Building are the
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
3. Brave Origin and Legcord (the person, 2026-11-14; plan and mockups in
   the project folder `brave-legcord-plan.md`, `mockups/brave-legcord/`):
   their real windows shown over the game by KWin scripts; bar buttons
   BRAVE and LEGCORD next to TV (variant A), right-click menu (C1),
   Alt+B / Alt+N; only over the game (no "screen 2"), they need not behave
   like the overlay's parts, and Game Companion draws nothing for them.
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
  zone -1, keyboard none; on-demand only after a click into the part
  while unlocked, `setKeyboard` + `eventFilter`, back to none on lock or
  hide: KWin activates an overlay surface the moment it accepts keys, which
  took the game's focus and mouse on unlock and when a part opened by
  itself, MN 2026-11-14; `_q_showWithoutActivating`; the input region is
  set before the first show), `place` sets the
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
  hangs, exits after 5 s anyway (the installer waits for its pid). On
  SIGTERM/SIGINT/SIGHUP it quits as "Turn off" does, ends hard after 10 s
  and logs the step it hung at (`main.rs` `QuitStep`; `gc_loop_ended`
  marks Qt's loop ending) as `end: forced`. Calls to KWin time out after
  2 s (`KWIN_CALL_TIMEOUT`; zbus waits for ever by default), after one
  timeout the rest are skipped (`Kwin.stuck`, reset by `watch`): at logout
  KWin kept its bus name but stopped answering and `apps::quit` hung (MN,
  0.8.57). Check: `dbus-run-session` with a made-up KWin that stops
  answering, then SIGTERM (project folder `arch-test/quit-hang/`).
  Logout on KDE (MN, 0.8.64) ends KWin first: Qt's Wayland connection
  breaks. KDE sets `QT_WAYLAND_RECONNECT`, Qt then connected again to
  nothing and `_exit`ed without a word (no end in the log, the next start
  "not clean"). `main.rs` takes that variable away (`GC_WAYLAND_RECONNECT=1`
  keeps it), so a broken connection reaches the message handler
  (cpp/native.cpp `logMessage`): `nativeWindow.ending` (Main.qml flushes
  LootStore and SessionStore), then `gc_display_lost` → `ending::run_hooks`
  (the meter's engine), `tidy()` as after Qt, `ending::children` (every
  child still in our session: SIGTERM, SIGKILL after 1.5 s; `setsid`
  programs such as the installer, Brave or Legcord are left to their own
  rules), `end: exit code 0`, `_exit(0)` (Qt's own clean-up would talk to
  the gone display). A KWin crash now also ends the app. Check: headless
  weston + Qt 6.12 from the PySide venv, end weston (project folder
  `arch-test/wayland-lost/`).
- The app's log (`src/log.rs`, MN 2026-11-15: "bau ein log ein", "nein zu
  persönlichen daten und mehr daten als nötig"):
  `~/.cache/game-companion/game-companion.log`, moved to `.log.1` past 2 MB,
  each line written at once. Start (version, Qt, platform, screens), end
  and why (signal, tray, Turn off, update), an unclean last session (the
  `running` marker), Qt warnings and errors (`gc_log_qt` from the message
  handler in cpp/native.cpp; each kind once per session, the JS lint never),
  a crash's signal and backtrace (handler with `write`/`backtrace_symbols_fd`
  only, then the signal goes on: core dump as before), the PoE 2 steps
  (copy seen item yes/no and its length, check, search, each trade request's
  endpoint kind and HTTP status, timers), children started and ended,
  shortcuts, the running game, the AION 2 meter. Never item or chat texts,
  tokens, accounts or request bodies; `log::clean` writes the home folder as
  `~` and cuts values after token marks. QML: `Companion.log(area, text)`.
  Settings → General "Log" (Open log folder, Copy log = last 300 lines),
  tray "Open log folder". `GC_LOG=stderr` mirrors it, `GC_LOG=off` stops it.
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
  A station that plays on none of its addresses is remembered
  (`settings.radio.dead`), greyed and listed last, hidden by the switch
  right of the tabs (`hide_dead`); playing again clears it (MN,
  2026-11-14).
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
  A game brings its own layout (MN, 2026-11-15): `games.layouts` by game
  id, picked in Settings → Layouts ("Games", `Games.layoutGames` = the
  watch list, built-in `known:` games too) or in the game's edit form;
  `Main` `onStarted` keeps the arrangement (`Companion.keepBeforeGame`,
  settings `before_game`/`before_game_for`, kept over a restart during
  that game) and loads the layout; `onStopped` → `backFromGame` brings it
  back if `layout_back` (default on). The Desktop layout (MN, 2026-11-16;
  settings `desktop_layout`, `Companion.setDesktop`, the "Desktop" chip
  under "Games") loads at the app's start (`restoreOpen` →
  `loadDesktop`) and when a game ends (wins over `before_game`). Layouts
  also keep `streams.video_opacity` (`opacities`: Twitch, YouTube,
  Jellyfin, chat, DPS; old layouts leave it); VideoWindow, ChatPanel and
  DpsPanel read it again on `layoutRevision`.
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
  a 6 to 15 s ad, visionos none); after a failure or a stall it lets yt-dlp
  choose (`anyPlayer`). "Stuck" names mpv's or yt-dlp's last warning
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
- Brave and Legcord (`src/apps.rs`, `src/apps_object.rs`, the `Apps`
  singleton; HudBar's `AppButton` and menu, Settings → Apps): a watcher
  KWin script (loaded over `org.kde.KWin /Scripting`, name
  `game-companion-apps`, only signals, no timer) reports the apps' windows
  and every focus change by `callDBus` to this process's own unique bus
  name (object `/io/github/xzero3007/GameCompanion/Apps`; calls from
  anyone but KWin's owner are ignored); each action is a one-off script
  (`command_script`: loaded, run, says "Done", unloaded) run on the
  `apps-kwin` worker thread. Every load ends with `/Scripting start`:
  KWin numbers a new script by how many it holds, so after another script
  went the number's D-Bus path can be another script's, and `run` there
  never ran ours (MN, 0.8.37: watcher loaded, no windows reported, every
  press started Brave again; `arch-test/apps/holes.sh`). With no window
  known, a press first asks KWin (`scan_body`, `look_then_start`) and loads
  the watcher again if it missed one; so does a game start. Show: unminimise, keepAbove, opacity, place
  on the overlay's screen (`nativeWindow.screenName`, place relative to it,
  kept when moved by hand), focus. Hide: minimise, focus back to the last
  other window. KWin 6.8 (Arch bench, 2026-11-14): a real full-screen game
  with the focus lies over keep-above windows (ActiveLayer); a borderless
  game window does not, and Proton marks a "borderless" game as full screen
  too (MN, 2026-11-14). So while an app is shown, the game's window on its
  screen loses its full-screen mark (`unfull_body`: same size, no border;
  again when the game asks for it, the watcher's `full` event, at most 5
  times per show) and gets it back when no app is shown (`refull_body`,
  `Runtime.unfull`, also on game end and quit). Settings → Apps "Stay over
  a full-screen game" (settings `apps_over_full`, default on); off, a
  full-screen game taking the focus minimises the apps on its screen. Game ended or app quits: each moved window back
  as it was (`Before`); `apps::quit` (main, after Qt) also closes what Game
  Companion started (SIGTERM, SIGKILL after 3 s) unless "Close it when Game
  Companion quits" is off; one the person started is never closed. Windows
  match by app id or class prefix (`brave`, `legcord`; Chromium site apps
  left out). `GC_DEMO=apps[,appmenu][,settings,appsettings]`. Check on the
  Arch bench: `arch-test/apps/` (stand-in windows, `test.sh`).
- Legcord voice overlay (MN, 2026-11-14; mockups and plan in the project
  folder `legcord-voice-plan.md`, `mockups/legcord-voice/`; N1 is the
  default, N2 to N5 are choices): `legcord/game-companion-voice/` is a
  Legcord plugin (Legcord 1.3's own plugin system, folder
  `~/.config/legcord/plugins/game-companion-voice`, switched on by the
  person in Legcord: in 1.3.1 its Plugins page shows only after Settings →
  Advanced → "Show experimental plugin menu"; "Extended plugin abilities"
  is not needed). Its renderer part reads Discord's stores by name
  through Legcord's built-in Shelter (`shelter.flux.storesFlat`:
  SelectedChannelStore, VoiceStateStore, SpeakingStore, UserStore,
  ChannelStore, GuildMemberStore; reports what it misses as `check`), and
  its main part gets that through a DevTools binding `gcVoice` (fallback: a
  console line tagged `\u0001gcvoice `). It hands it to Game Companion over
  `$XDG_RUNTIME_DIR/game-companion-voice.sock`. Legcord cancels WebSockets
  to localhost (except 1211, 1112, 6888) and its strict CSP leaves
  127.0.0.1 out, so there is no TCP. `src/voice_overlay.rs`: socket
  (peer uid checked), JSON lines `hello`/`check`/`state`/`picture`,
  avatars written as PNG to `$XDG_RUNTIME_DIR/game-companion-voice/`,
  shown by file URL (Qt's Image took no `data:` URL); plugin files built
  in (`include_str!`), "Install plugin" writes them, every start refreshes
  an installed copy. `src/voice_object.rs`: the `VoiceChat` singleton
  (`state`, `pictures`, `prefs` = settings `voice`). `qml/VoiceOverlay.qml`:
  its own surface, with the hub or without, no ground by default, moved
  while unlocked; one single-shot timer only while a talk mark fades
  ("Stays after talking"). `GC_DEMO=voice`. Check end to end: Electron 44
  with Legcord's loader and a made-up Discord page (project folder
  `mockups/legcord-voice/e2e/`).
- Sound module (MN, 2026-11-15: "Sonar light" taken in; plan in the
  project folder `sound/` and the doc "Sound-Modul: Bauplan"; MN's logs:
  EasyEffects' 20 filters caused the dropouts, without it none):
  `src/sound.rs`, `src/sound_object.rs` (the `Sound` singleton). Channels
  `sonar_game/chat/media/music` (filter chains, pre-gain + 5 biquads,
  Sonar light's presets), WebRTC echo-cancel in monitor mode when the mic
  chain's echo is on (speakers instead of a headset; its reference
  `gc_aec.reference` listens to the default output's monitor; nothing
  plays through it: in 0.8.60 the channels played through its sink and
  everything heard was distorted on MN's UR22; its block is 1920 frames,
  `node.latency` 1920/48000, and its capture holds the graph at
  `node.force-quantum` 1920: PipeWire's echo-cancel hands its source one
  block per cycle, so 480 blocks in MN's 2048 graph lost three quarters of
  the voice, 0.8.61; bench: `pw-metadata -n settings 0 clock.force-quantum
  2048` reproduces it), mic chain → source `gc_mic` "Game Companion Mikro" (rnnoise
  with its VAD as the voice gate, voice EQ, sc4m compressor if installed;
  takes one input with `stream.dont-remix`; gate default 60 % / 500 ms
  with 100 ms let through before a voice, `GATE_LEAD_MS`; old 85/300
  moved once, `Mic::update_gate`; MN 2026-11-16: opened late, cut words),
  presets with little pre-gain (Sonar light's −5 dB ate its boosts); the
  mic chain is gain (`Mic.gain`, 0 to 30 dB, default 12: MN's UR22 was
  quiet without EasyEffects' auto gain) → rnnoise → mic EQ (`VOICE_BANDS`
  m1–m5, `VOICE_PRESETS`, own ones in `mic_presets`; gain, gate and EQ
  change live, `gate_params`), after rnnoise swh's gate as a level gate
  (`Mic.min_level`, "Floor", default −50 dBFS, −70 off, white mark
  on the meter; MN 0.8.66: a constant floor in Legcord) → clean up (hp + sc4m) → swh's
  fastLookaheadLimiter at −1 dBFS, both its inputs fed (one left open
  crashed the child on the bench) and the graph's `inputs`/`outputs`
  named; echo canceller switches `extra_ns` (WebRTC noise suppression,
  "aquarium" with music, default off) and `auto_level` (WebRTC AGC), stream mix: loopbacks from
  the channels' monitors and the mic into `gc_stream_in`, OBS records the
  source `gc_stream` (a client can't make a null sink: a copy filter chain).
  It all runs in a `pipewire -c $XDG_RUNTIME_DIR/game-companion-sound.conf`
  child (PR_SET_PDEATHSIG from the `sound` worker thread): nothing in
  ~/.config/pipewire, the system's PipeWire never restarted; virtual nodes
  have priority 0 and a default that became ours is put back. `pactl
  subscribe` → new streams moved (`channel_for`: fixed route, running game
  by comm/environ SteamAppId up the parents, Legcord → chat, players →
  music, rest → media); EQ (`pw-cli set-param` "bN:Gain"), volumes/ChatMix
  (`pactl set-sink-volume`), gate and sends live. Off by default
  (settings `sound`). Check without hardware: PipeWire 1.0 from apt,
  `pipewire &`, `dbus-run-session -- wireplumber &`, `pipewire-pulse &`,
  null sinks as fake devices, then the ignored test
  `write_config_for_bench` (GC_SOUND_CONF, GC_SOUND_MIC) and `pipewire -c`,
  or the app itself with `sound.on` in a scratch settings.json.
  Panel (canvas page "Sound", MIXER variant A; MN 2026-11-16):
  `qml/SoundPanel.qml` (MIXER: volume, preset and EQ in place per channel,
  ChatMix; MIC: input, Input 1/2 = FL/FR, mapped to AUX0/AUX1 on Pro Audio,
  gate, echo, voice, "Record 10 s and play back" = `Sound.hear`; APPS;
  STREAM: sends and the OBS tracks), SOUND always in the bar, a right click
  opens `qml/SoundRow.qml` (quick row under the player row, pinnable,
  id `sound-row`). The mic's meter (`Sound.level`, `Sound.talking`) is a
  `parec` of `gc_mic` (pw-record 1.0 has no raw output) read on its own
  thread, told only on a change, and runs only while the MIC tab or the
  quick row shows (`Main.soundMeter`; kept until the worker runs). MN
  switches Legcord's own noise filter, echo and auto gain off.
  `GC_DEMO=sound[,soundmic|,soundapps|,soundstream|,soundeq][,soundee]`,
  `soundrow`. Sound log (MN, 2026-11-16): `~/.cache/game-companion/sound.log`
  (`log::sound`): each start's settings and the whole config, the child
  pipewire's stderr (log.level 2, 400 lines a run), stream moves, volumes,
  and a snapshot (`sound::snapshot`: clock settings, cards and profiles,
  sinks with volumes, streams, pw-top's quantum/rate/ERR, the child's CPU)
  8 s after a start and on the panel's "Copy sound log" (`Sound.report`,
  then `Sound.logText(700)` to the clipboard). Each EQ change logs what
  was asked and what the filter holds (`pw-cli enum-params`, `held_params`).
  Channel meters in the MIXER (MN, 2026-11-16: "woran ich sehen kann das
  es funktioniert"): a `parec` per channel monitor (8 kHz mono, before the
  EQ), only while the MIXER shows (`Main.soundChannelMeters`,
  `Sound.setChannelMeters`, `Sound.channelLevels` "a,b,c,d"), told only on
  a change. The radio's mpv names itself `game-companion-radio`
  (`--audio-client-name`) and goes on Music. Test signal without hardware: `pactl load-module
  module-pipe-source source_name=pipe_mic file=/tmp/pipe_mic format=s16le
  rate=48000 channels=1` as the mic device and raw samples written to the
  fifo (our router moves every playing stream, also one aimed at a sink).
- Hardware decoding: `Streams.hwdec` (settings `streams.hwdec`, default on)
  sets mpv's `hwdec` (auto-safe or no), at once while playing.
- Video loudness (MN, 2026-11-14: videos quieter than the radio, which is
  mixed louder): Settings → Streams → Videos "Video loudness"
  (`Streams.videoBoost`, settings `streams.video_boost`, 0/3/6/9 dB;
  `VideoWindow.mpvVolume` multiplies by 10^(dB/60), mpv's `volume-max`
  150) and "Even out loudness" (`Streams.evenLoudness`, `MpvVideo.levelling`:
  mpv `af` = `lavfi=[dynaudnorm=f=250:g=15]`). The radio's own mpv is not
  touched.
- `HudIcon` is a picture from the icon provider (`cpp/icons.cpp`,
  `image://icon/<path>|<colour>|<line width>|<filled>`, QSvgRenderer at
  twice the size): one small texture per look, shared and cached. It was a
  multisampled layer per icon (shapes alone were not clipped by a list's
  clip in the software renderer), which cost video memory. Needs qt6-svg
  (sandbox: `apt install qt6-svg-dev`).
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

- Schedule (AION 2 Event Timers, 0.8.x, canvas page "Zeitplan (Event
  Timers)", boards T1–T3): `qml/aion2/TimerStore.qml` (in Main, lives with
  the app) keeps per server the bosses of every map the game told about
  (`Aion2.bossMaps` from `Engine::boss_maps`, the parser's `01 91` boss map
  sent when a map is opened; only home map and Abyss come) and the alert
  choices, in aion2-timers.json; one single-shot Timer waits for the next
  alert (`TK.nextAlert`), the banner (`AlertBanner.qml`, own surface, 20 s)
  and `Aion2.chime` (`src/alert.rs`: a WAV made in code, played by pw-play,
  paplay, aplay or mpv) / `Aion2.speak` (spd-say). Alerts only while AION 2
  runs unless "Also while AION 2 is closed". `qml/aion2/timekit.js`: server
  time per region (second digit of the server id; US/EU daylight rules in
  code, Qt's JS has no time zones), next showings, boss rows. Fixed times:
  `qml/aion2/schedule.js` from taengu's Event Timers (GPL-3.0) by
  `tools/aion2-schedule-import.py <A2Tools-Plugins checkout>`. Aion 2
  Timers' slugs (`asmo07`) map to world-map ids by matching the game's
  return times (`TK.learn`), else by number (A2T? tag). Test:
  `node tools/timekit-test.js`. `GC_DEMO=schedule[,events][,alert]`,
  `settings,timers`.

- Boss area (AION 2 "Kampf", the person 2026-11-13; canvas page "boss",
  boards K1 to K5): Boss Notes and Boss Callouts (A2Tools' Enhanced Boss
  Telegraph, GPL-3.0) in one panel `qml/aion2/BossPanel.qml` (NOW, SHEETS,
  FIGHTS, VOICE), the big call `BossCall.qml` (own surface, only while a
  call runs) and the sheet over the game `BossOverlay.qml`; the logic is
  the plugins' logic.js ported as `.pragma library` files (`callouts.js`,
  `bossnotes.js`), driven by `BossBrain.qml` (a ticker only while calls or
  a fight run). Frames: `aion2::boss::Feed` reads cast/use/wave/buff
  frames of the skills in `data/boss/watch.json` from bound casters and
  hands them to QML as `Aion2.bossHeard`; `Aion2.combat` lists the fought
  NPCs and the dungeon. Data: `tools/aion2-boss-import.py <A2Tools-Plugins
  dir>` writes `qml/aion2/bossdata.js`, `watch.json` and the Kokoro voice
  clips (`data/boss/voice`, played by mpv; own words by `spd-say`,
  `src/voice.rs`). Cheat sheets per dungeon (Ludra first) in
  `bossstarters.js`: starters from public guides, roles fade other roles'
  rows. Stores "boss", "boss-sheets", "boss-fights". Not done yet: overlay
  slots and resizing. Preview outside the dungeon (MN, 0.8.6 test): SHEETS →
  "Show over game" (`previewDungeon`, `previewKey`, not kept), ▶ on an entry
  or a click on its row over the game plays it (`playEntry`: big call and
  voice, `previewPhase` marked current). `GC_DEMO=boss[,bossfight|,ludra][,sheets|,fights|,voice]`,
  `boss,sheets,preview`.

- LOOT (`qml/aion2/LootPanel.qml`, `LootStore.qml`, `ClosetWindow.qml`,
  `PriceBook.qml`; logic `lootkit.js` from `tools/aion2-loot-import.py`):
  the Inventory, Closet and Shugo Cards plugins in one panel; game frames
  through `crates/aion2/src/decoders.rs` → `Aion2.decoded`; files in
  `~/.local/share/game-companion/aion2/loot/`. Details: docs/HANDOFF.md.
  The old meter's Inventory/Closet/Shugo files are read once (local, read
  only, `src/meter_import.rs`; MN, 2026-11-13). The farm window
  `FarmWindow.qml` opens itself while farming; the shop window's switches
  are per place (merchant, Market). Positions in `Aion2.world` are in cm.
  `short` is a reserved word in QML's JS: name helpers otherwise.

- Armory (MN 2026-11-13, canvas page "Armory mit Builds", boards AR1–AR4):
  the Clicktrough Armory plugin with builds tied to characters. The old
  meter's Armory files (history, readings, references, targets) are taken
  over once (`meter_import::read_armory`, `ArmoryStore.takeMeter`; MN,
  2026-11-14).
  `qml/aion2/armorykit.js` is the plugin's calc.js and nc.js unchanged
  (made by `tools/aion2-armory-import.py <A2Tools-Clicktrough-Plugins
  plugins dir>`, which also writes `crates/aion2/data/armory/data.json`,
  loaded by `Aion2.armoryData()` → `AK.load`); its tests
  `tools/armory-test/calc.test.cjs` (run each file with `node --test`).
  `buildkit.js` (+ `builds.test.cjs`): builds = reference + targets (soul
  wishes, skill levels, compared items, levels, picks, slots left out, goal
  GS), on several characters, one active each, versions within 10 min,
  progress per area, next steps (gone from the next reading = done).
  `ArmoryStore.qml` (in Main): state in store "armory", one snapshot and
  history per character ("armory-s-"/"armory-h-" + hash), reads NC's pages
  through `Aion2.webGet` (promises, no async on Qt 6.4), a played character
  by itself every 6 h while the plugin is on, the game's own CP/GS between
  readings; `progressOf(key)` feeds CHARACTERS' gear column. Panel
  `ArmoryPanel.qml` with tab files `Armory<Tab>.qml`, parts in `AUi.qml`
  (no Repeater inside inline components, no inline component made by a
  nested Repeater: Qt 6.4 crashed; no property named `top`, `scale`, `C`
  or a signal `set`). questlog.gg builds come from the Armory bookmark's
  file in Downloads (`armory-*.json`, `src/armory.rs`). Battle History
  entries carry `players` [[name, damage]] for HISTORY's boss fights.
  `GC_DEMO=armory[,gear[,compare]|,soul[,pick]|,askills|,daev|,stats|,goals|,builds|,ahistory]`.

- PoE 2 price check (MN 2026-11-15, Exiled Exchange 2 rebuilt because
  EE2 was unreliable on KDE Wayland): `tools/poe2-ee2/build.mjs <EE2
  checkout>` makes `qml/poe2/ee2kit.js` (EE2's parser, filters and trade
  code for Qt's ES2016: shims, polyfills, look-behind patch, named groups
  through `__gcMatch`/`__gcExec`, no setInterval) and `data/poe2/` (en, de;
  installed to /usr/share/game-companion/poe2, `GC_POE2_DATA`). Rebuild it
  when EE2 brings a new league's data (1.0 in December). `src/poe2.rs`:
  trade requests (one at a time, 429 respected, cookie jar in
  $XDG_RUNTIME_DIR) and the XFixes clipboard watcher on XWayland (the
  person's own Ctrl+C in the game; nothing is sent to the game).
  `qml/poe2/PriceStore.qml` + `PriceWindow.qml`, plugin `poe2.price`, only
  while PoE 2 runs. The kit does **not** run in Qt's JavaScript (Arch's Qt
  6.12 crashed in it, JIT and interpreter; MN 0.8.44, reproduced by QA):
  `src/poe2_kit.rs` runs it in QuickJS (rquickjs) in a child process
  (`/proc/self/exe --poe2-kit`, JSON lines on stdin/stdout,
  PR_SET_PDEATHSIG from the Qt thread, ends when stdin closes or the
  parent goes, `poe2_kit::stop` on quit); `PriceStore.kit(fn, args)` gives
  a promise; if the child dies only the price check starts again
  (`kitGone`). GC_DEMO=price answers inside the child (`DEMO`). The kit is
  still built without array iterators (Babel pass in build.mjs). Tests:
  `cargo test poe2_kit` (an item, a search, EE2's 27 samples in QuickJS).
  Tests: `node tools/poe2-ee2/test/run.js`, the ignored
  `copied_items_are_seen` under xvfb-run with xclip. `GC_DEMO=price[,results|,gloves]`,
  `settings,poe2prefs`, `price,results,listing` (a listing's item shown),
  `price,currency` (the exchange with poe.ninja's price). A click on a
  listing shows its item under the row (`ListedItem.qml`, the kit's
  `item` from EE2's DisplayItem: values, requirements, enchants, runes,
  implicits, mods with tiers, in the trade site's colours; MN, 2026-11-15).
  poe.ninja (`tools/poe2-ee2/ninja.ts`): the exchange's Currency overview
  (`core.rates.exalted` = ex per divine, `lines[].primaryValue` in divines,
  ids = the trade site's currency ids, `items[]` the names; shape from MN's
  copy, Runes of Aldur); each listing's `norm` (in ex, from one divine up in
  div), a currency item's `ninja` (div, ex, 7-day change) in the view and
  the result. Layout like the game (MN, 2026-11-15): with the
  advanced copy (Ctrl+C with Alt held) the kit's `view().mods` (from the
  item text's `{ … }` headers, matched to EE2's mods by name and tier)
  make the groups IMPLICIT · ENCHANT · RUNES, PREFIXES, SUFFIXES (each
  line with the tier's range in brackets, its tier, the stat line that
  searches for it, or "in the totals"/"in the item's values"); without it
  EE2's stat lines in VALUES, LINES, TOTALS. Min/max per line
  (`RangeField`, wheel works locked). EE2's settings in `PriceSettings.qml`
  (window ⚙ and Settings → Plugins → PoE 2), kept in settings.poe2,
  handed to the kit by `setPrefs`. The league is chosen there too (its
  list asked only while PoE 2 runs and the settings show; QA, 0.8.65; MN,
  0.8.55: the window's dropdown opened under the chips). `setStat`'s
  bound "keep" leaves it as it is (QML's `undefined` arrives as null
  through JSON and cleared the other bound). `tradeLink` adds
  `disabled: false` to every filter group (the site showed Equipment
  Filters unticked). Dropdowns at a panel's end open past its surface:
  use a list that opens in place (the session's "Add currency"). The clipboard watcher connects again by
  itself when XWayland's connection ends; `Poe2.watchError` shows in the
  window (0.8.44, MN: Ctrl+C did nothing). EE2's leagues come unencoded
  ("Runes of Aldur"): `encode_address` before `allowed`.
  PoE 2 session tracker (MN 2026-11-15, plugin `poe2.session`; no network):
  `src/poe2_log.rs` reads the game's own `logs/Client.txt` while PoE 2
  runs (from its end; only area, level-up, own death and AFK lines, never
  chat or whispers), `Poe2Log.heard`; rules in `qml/poe2/sessionkit.js`
  (`node tools/poe2-session-test.js`), `SessionStore.qml`,
  `SessionPanel.qml`, `SessionWindow.qml`; new session after 30 min / 1 h
  of pause or at midnight. `GC_DEMO=session`. Details: docs/HANDOFF.md.
  Loot by hand (part 2): currency with − / + or a copied stack and items
  by the price check's "+ Session", worth from poe.ninja's exchange
  overview (`SessionStore.needRates`, only while the session holds loot,
  30 min; the price check's "poe.ninja prices" switch). PoE 2 has no stash
  API (GGG: PoE 1 only); never read the game's memory.
  Path of Building is the third app (`pob`, `AppDef.args` "poe2",
  `AppDef.game` "poe2"; bar button while PoE 2 or PoB runs).
  Qt's JavaScript runs without its JIT (`main.rs` sets
  `QV4_FORCE_INTERPRETER=1`, `GC_JIT=1` keeps it): Arch's Qt 6.12 JIT
  crashed in the kit every run (QA 2026-11-15), Qt 6.12.0 from PySide did
  not; the interpreter cost no more CPU in the demos. Run Qt 6.12 in the
  sandbox from a PySide6-Essentials venv (`LD_LIBRARY_PATH`,
  `QT_PLUGIN_PATH`, `QML_IMPORT_PATH` to its `Qt/` folders): the app built
  on 6.4 runs on it.

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
