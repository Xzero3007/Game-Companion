# Handoff: where the work stands

Read CLAUDE.md first, then this. Updated after every finished step, so a
new session (or the same one after a usage limit) carries on from here.

## Channels

- `main` = stable. Only what the person accepted lands there. Every push
  publishes release `v{version}-{run}` (latest).
- `beta` = test builds. Every push publishes pre-release
  `v{version}-beta-{run}` and points the rolling release `beta-channel`
  (asset `latest.json`) at it. The app's Settings → General → "Beta updates"
  switches channel (`settings.beta_updates`, `Updates.beta`,
  `Updates.setChannel`); `GC_CHANNEL=beta` at build time marks a beta build
  (`updater::running_beta`). The root script accepts the latest stable or
  the newest beta build. Going back to stable installs stable's latest even
  if its build number is lower.
- When the person says a beta is good: merge `beta` into `main` (fast
  forward if possible), bump nothing extra, push.
- Milestones: a branch `milestone/<name>` at each working step on beta
  (`git branch milestone/x && git push origin milestone/x`; tag pushes are
  refused by this environment's git proxy), so a broken step can be reset
  without losing the rest.

## Done

- 0.7.0 beta (branch `integration` merged into beta, 2026-11-13): launch
  options and Proton per game (checker, suggestions by Proton build,
  CachyOS, ProtonDB extract, UI per boards L1-L3), tray icon and autostart
  choice, second start shows the hub, YouTube library / Twitch categories,
  VODs, clips, chat (from the thread "FreeTube und Streamlink-GUI
  ablösen"), not-installed games for Steam/Heroic/Lutris with INSTALL,
  "Installed only", covers from more local caches. Each part had a QA
  review and its findings fixed. Cover downloads: see the branch
  `cover-downloads` below; CLAUDE.md still describes the old "already
  running" second start and lacks tray/launch-options entries (an edit
  was refused by the permission check: ask the person).

- 0.4.2: every part on the primary screen (two monitors).
- 0.4.3: steady dragging (`Surface.held`), outline text under half
  opacity, no unlocked frame.
- 0.4.4 (stable): beta channel switch.
- 0.4.5 (stable): KDE's primary screen from kwinoutputconfig.json, "Show on"
  in Display.
- 0.5.0 beta (milestone/step4-first): Games panel (qml/GamesPanel.qml),
  Games bar button, detection and libraries (src/games.rs,
  src/games_object.rs, singleton Games: library JSON, running, started /
  stopped signals, launch, own entries, options, favourites, layouts per
  game), start with the desktop (now Companion.autostartMode, see the
  tray branch), on
  start: Streams preset, show hub, radio, layout (Main.qml Connections).

## Branch `cover-downloads` (from integration 0.7.0): missing covers

The person agreed 2026-11-13 (decision card "Nur Cover laden"): missing
covers may be downloaded once from Steam's, Epic's and GOG's image
servers; only the game's id in the picture address leaves the PC (no
Steam Web API, no library list). `src/covers.rs`:
- Allowed hosts, exact (`ALLOWED_HOSTS`, `allowed_host`: https only, no
  user, no port): shared.akamai.steamstatic.com, cdn.akamai.steamstatic.com,
  cdn.cloudflare.steamstatic.com, steamcdn-a.akamaihd.net,
  cdn1.epicgames.com, cdn1.unrealengine.com, cdn2.unrealengine.com,
  images.gog-statics.com, images-1..4.gog-statics.com, images.gog.com.
  The Epic/GOG list is from memory of Heroic's data (its source was not
  reachable from the sandbox): if real `art_square`/`art_cover` addresses
  use another image host, those games simply get no download; add the
  exact host after asking.
- Addresses (`candidates`): Steam by app id,
  `shared.akamai.steamstatic.com/store_item_assets/steam/apps/<id>/`
  library_600x900.jpg, library_600x900_2x.jpg, then
  `cdn.cloudflare.steamstatic.com/steam/apps/<id>/library_600x900.jpg`,
  then the shared header.jpg; Heroic: `Game.cover_url` (art_square, else
  art_cover, only on an allowed host; Epic's resized `?h=400&resize=1&w=300`
  first, as Heroic's card). Amazon, Lutris and own entries: none.
- curl `-q`, settings on stdin, `proto =https`, no `location` (a 3xx is a
  miss), max-time 20, max-filesize 5 MB; the status code after the body
  (`write-out`). Kept only if JPEG/PNG/WebP by magic bytes.
- Files: `~/.cache/game-companion/covers/<id with ':' as '-'>.<jpg|png|webp>`
  (atomic, `.part` then rename); misses in `covers/failed.json`
  (id → unix time), asked again after a week (`RETRY_AFTER`). No
  connection = nothing remembered, the run stops.
- `Games` (games_object.rs): after each library read, `fill_cached` gives
  games their downloaded covers (worker thread), then `start_covers`
  runs one "covers" thread (one at a time, 250 ms apart, installed games
  first; never two threads). Each saved cover → signal
  `coverArrived(id, picture)` → GamesPanel's `arrivedCovers` updates that
  card; the library JSON is rebuilt once at the end. Setting
  `games.download_covers` (default on), `Games.downloadCovers` /
  `saveDownloadCovers`, Settings → General → Games "Download missing
  covers"; off stops the thread before the next game. `GC_NO_COVER_DOWNLOADS=1`
  and every `GC_DEMO` mode download nothing.
- Unverified: real downloads (the sandbox's proxy refuses these hosts);
  tested with made-up fetch answers and curl's write-out/proto behaviour
  against a local server.

## In progress: tray icon and start options on branch `tray-autostart` (from beta)

Approved by the person 2026-11-13. Built, waiting for review and the
person's test on KDE:
- Tray icon (`src/tray.rs`): a StatusNotifierItem with a dbusmenu through
  the ksni crate (Unlicense, pure Rust, on the zbus 5 / async-io the
  shortcuts already use). Chosen over QSystemTrayIcon because that needs
  QtWidgets and a QApplication (plus KDE's platform theme deciding how it
  shows); ksni needs nothing new on the system and its threads sleep on
  the D-Bus socket (idle 0 ticks measured). Left click = Companion
  toggle_shown; menu: Show/Hide hub, Lock/Unlock, Settings, Check for
  updates, Quit (native::quit). Menu labels and tooltip follow
  shown/locked (`on_shown_changed` / `on_locked_changed` → `sync_tray`).
  Started on a "tray" thread with `assume_sni_available` (waits for
  Plasma's watcher when started before the panel; re-registers when
  plasmashell restarts). The icon: the bar's Games gamepad in #e0a526 at
  16 to 64 px, drawn by `gc_tray_icon` (cpp/icons.cpp) and sent as
  pixmaps. Settings `tray` (default on), `Companion.tray` /
  `setTrayOn`; `GC_NO_TRAY=1` skips it. Settings and Check for updates
  arrive in QML as `Companion.settingsRequested` / `updatesRequested`.
- Start (Settings → General): `Companion.autostartMode` "off" / "hidden" /
  "visible", `setAutostartTo`; read from the autostart entry's Exec line
  (`--hidden` = hidden, so entries from before stay hidden). "Show the hub
  when a game starts": settings `show_on_game` (default on), gates the
  per-game showOnStart in Main.qml.
- One copy (`src/instance.rs`): the flock as before plus
  `$XDG_RUNTIME_DIR/game-companion.sock` (0600); a second start writes
  "show" and exits 0 (a second `--hidden` start just ends). The listener
  thread sleeps in accept and queues onto the Qt thread.
- Checked in the sandbox: unit tests (menu, actions, autostart entries,
  socket); under dbus-run-session with a fake StatusNotifierWatcher
  (python3.12 dbus): registration, IconPixmap, left click, menu Unlock,
  Quit, a watcher that appears late, second start shows the hub, idle 0
  ticks with and without the tray. Only the person can check how Plasma
  draws it. Demo: `GC_DEMO=settings,startmenu`.

## Decisions 2026-11-13 (the person)

- AION module merged into beta as 0.6.0 for the person's in-game test.
- Map data: the AION2 Interactive Map's pictures and data are CC BY-NC 4.0
  (its author's licence): fine with credit (NOTICE file) while the app is
  free; nothing to replace.
- Launch options UI drafts approved (canvas page "Launch options (draft)",
  boards L1Options, L2Suggestions, L3Proton).
- Suggestions follow the Proton flavour set for the game (Valve, GE,
  proton-cachyos, Wine, native); CachyOS aware (game-performance,
  proton-cachyos defaults); an explanation text for every option; options
  already set are checked (ok, outdated, invalid, no effect, not
  recommended, unknown).
- Open: ProtonDB (on demand per game, a data extract in the app, or none);
  helper group (recommended no).

## In progress: AION 2 module on branch `aion-module` (from beta)

The person asked (2026-11-13) to port the meter; decisions in
/mnt/project-files/game-companion/aion-module-decisions.md. Done: crate
aion2 (parser, 300 tests), capture helper with cap_net_raw, engine, Aion2
singleton, DPS panel (Damage, Healing, Skills, History, Reset, boss HP),
QA fixes (helper hardened), Battle History (fights/*.json, 200 kept), world
state for the map (`world.rs` fed by `frame_tap`, `Aion2.world` JSON).
Next: the Map panel (needs a design draft and the person's yes; the
meter's map data is CC BY-NC: ask the person), the person's test in the
game (only they can play), then plugins in the agreed order. Not merged
into beta until reviewed. Open decision: install the helper 0750 with a
group as further hardening.

Branch `launch-options` (from beta): launch options, system check with
suggestions and Proton versions (logic done, 82 tests; Games invokables
launchOptions, suggestions, combineOptions, setLaunchOptions,
protonVersions, setProton, systemInfo). UI drafts on the canvas page
"Launch options (draft)" (boards L1Options, L2Suggestions, L3Proton),
waiting for the person's yes.

## In progress: step 4 (game detection, Games tab) on `beta`

Agreed with the person 2026-11-13 (see CLAUDE.md plan step 4):
- Detection: `/proc` every 3 s, process names per game; AION 2 and
  Path of Exile 2 built in; the bar shows the running game; the Streams
  panel's game tab follows it; optional layout per game.
- Autostart switch ("Start with the desktop", KDE autostart entry); starts
  hidden, shows when a game runs.
- Games tab per the approved canvas boards G4Library and G4AddGame
  (canvas https://claude.ai/artifact/82a3HqWJWbBRdp5FU7MvGZ, page
  "Games (step 4)"): Steam, Lutris, Heroic read from disk, own entries,
  start through the launcher; pictures only from the launchers' local
  caches; no network.
- Out of scope for now: PoE 2 helper programs, starting the AION meter
  (step 5).
- Later wishes (the person, 2026-11-13, to plan together): set launch
  options for games in the launchers; something for Proton.
  Backend done on branch `launch-options` (not merged, no UI yet):
  `src/launch_options.rs` (Steam localconfig.vdf / config.vdf, Lutris yml,
  Heroic GamesConfig; suggestions; Proton list), `src/system_info.rs`
  (GPU, driver, CPU, RAM, tools, session, main screen from
  kwinoutputconfig.json), `src/vdf_edit.rs` (changes one VDF value, every
  other byte kept). Games invokables: launchOptions, suggestions,
  combineOptions, setLaunchOptions, protonVersions, setProton, systemInfo,
  checkOptions:
  each returns a request number at once, works on a worker thread (one at
  a time) and answers by the signal `launchResult(request, json)`; the
  Proton list is cached (`protonVersions(true)` reads it again).
  combineOptions takes the ids that should be on (applied ones left out
  are taken out) and edits the user's text in place (settings in front,
  wrappers before the standalone `%command%`, MangoHud as gamescope's
  `--mangoapp`); text it cannot change safely (`$(`, redirection before
  the command, two `%command%`, ...) is refused, never rewritten.
  Writes refuse while the launcher runs ("Close Steam first", also when
  /proc cannot be read), back up the file as `<file>.gc-backup-<UTC time>`
  (newest three kept) and replace it by rename. setProton's answer has a
  `warning` (Heroic: Wine to Proton or back changes the prefix). serde_json
  now keeps key order (preserve_order) so Heroic's files keep theirs.

  Checker and flavour-aware suggestions (the person, 2026-11-13, same
  branch): `data/launch-options.json` (compiled in) lists ~170 known
  env vars, wrappers and args, each with kind, value type (bool, enum,
  flags with the exact flag list, number, version, size, hidraw,
  dll_overrides, dxvk_config), flavours (valve, experimental, ge,
  cachyos, wine, native), status (current, retired + replacement/since,
  discouraged, experimental, debug, unverified), per-flavour overrides,
  GPU vendor, explanation and `source` (keys of `sources`, the documents
  read on 2026-11-13: Valve/GE/proton-cachyos READMEs, scripts and
  changelog, vkd3d-proton README + source + history, DXVK README +
  source, DXVK-NVAPI, Mesa, NVIDIA README, CachyOS wiki, MangoHud,
  GameMode, SDL, WiVRn). `src/launch_check.rs`: `context` (family from
  the game's tool: Valve(major)/Hotfix, Experimental, GE, proton-cachyos,
  other Proton, Wine, native), `check(text, ctx)` per token: status
  ok / outdated / invalid (misspelt name or flag, bad value, wrapper not
  installed) / no_effect (wrong flavour or vendor, native game, set twice)
  / not_recommended / unknown (not in the list: said honestly), `fix` per
  token and `fixed` text; problems command_missing, command_twice,
  duplicate. `src/protondb.rs`: ProtonDB extract `data/protondb.json.gz`
  (from `tools/protondb-extract.py`, ODbL, NOTICE-ProtonDB.txt; installed
  to /usr/share/game-companion; `GC_PROTONDB` overrides), read on the
  worker per request, only the one game parsed (RawValue). Shares per
  system group: GPU in use, distro family, CPU (system_info: os-release
  ID/ID_LIKE, cpuinfo vendor, display card), groups under 5 reports fall
  back. Suggestions now depend on the build: Wayland only GE 10+ and
  proton-cachyos (Valve's builds have no winewayland); HDR on
  proton-cachyos = DXVK_HDR=1 (+ENABLE_HDR_WSI=1 on NVIDIA < 595), Valve =
  Vulkan HDR layer; NTSync is default (PROTON_NO_NTSYNC offered for
  troubleshooting only); FSR4/DLSS upgrade, local shader cache, NVIDIA
  libs, OptiScaler for GE 10+ and proton-cachyos (never recommended);
  game-performance on CachyOS (with powerprofilesctl) instead of
  gamemoderun, ananicy-cpp warning. Removed: the PROTON_USE_NTSYNC and
  PROTON_ENABLE_NVAPI suggestions (current scripts do not read them).
  `Games.suggestions` answers an object now
  (`{"suggestions","context","check","warnings","others"}`), new
  `Games.checkOptions(id, text)`; JSON in the doc comments of
  src/games_object.rs. Findings for Forza Horizon 6: `descriptor_heap`
  was an opt-in vkd3d-proton flag from 2026-05-27 (before:
  `i_want_broken_descriptor_heap`) until 2026-11-04, when vkd3d-proton
  master made descriptor heap the default (`no_descriptor_heap` opts out):
  ok, with that note; `enable_experimental_features` exists in the source
  (not the README); `PROTON_VKD3D_HEAP` was proton-cachyos-only, removed
  in 11.0-20260521 (outdated there, no_effect on Valve/GE).

  UI (same branch, design boards L1Options, L2Suggestions, L3Proton,
  approved 2026-11-13): the game form has tabs GENERAL / PRESET SEARCH /
  LAUNCH (`qml/LaunchTab.qml`, read when first opened, scrolls when the
  screen is short): options field (monospace, one line), chips ENV /
  WRAPPER / GAME / ARG from `checkOptions` (debounced 400 ms, only the
  newest answer counts) with a status mark (`StatusMark`, `launch.js`:
  ok gold, outdated purple, invalid red, no effect grey, not recommended
  hollow red, unknown hollow grey), a click opens a part's explanation,
  note, warning and flags with its fix ("Fix: …" / "Take it out"; FIX ALL
  uses `fixed`), all only into the field; red "CLOSE STEAM FIRST" banner
  while the launcher runs (`launchOptions` answers `running`;
  `Games.launcherState` asked every 3 s only while it shows; SAVE off);
  Proton choice (`SelectBox` + `ChoiceList`, a list over the whole panel,
  opens upwards when there is no room). SAVE writes options and Proton
  through the worker and closes when both answered; setProton's warning
  shows as a note over the list. SHOW opens `LaunchSuggestions.qml` over
  the form: system strip, rows with checkbox (recommended ones start on),
  groups as radio rows, unavailable ones (`available: false`,
  `unavailable_why`, from launch-fixes) greyed with the reason, PREVIEW
  from `combineOptions` (new words gold), WHAT OTHERS USE (shares on
  systems like this one and overall, check status, click for the note;
  Proton variants; "Data: ProtonDB export (ODbL)"; no one-click apply of
  others' text yet); APPLY puts the preview into the field (SAVE writes:
  one write path, deviation from the board's "APPLY writes"). PROTON in
  the list's header opens `ProtonOverview.qml` (new `Games.protonOverview(
  ids)`: builds by source with the games using each, STEAM DEFAULT, quick
  change per game; own entries left out). Backend additions:
  `launch_options::launcher_running`, `tool_name`, `tool_in_use`,
  `tool_choices` (config.vdf read once), `usage_json`; `launchOptions`
  answers `proton.name` / `proton.inUse` / `running`. Demo
  (`src/launch_demo.rs`, made-up PC, builds and games; the real checker,
  suggestions and ProtonDB extract run on it): GC_DEMO=games,launch
  [,detail][,picker][,launcherrunning], games,suggestions[,rows|,middle|
  ,others|,end], games,proton, games,launchown; `nowelcome` closes the
  welcome. Screenshots in /mnt/project-files/game-companion/screens/launch/.

  Second QA round (branch `launch-fixes`, 2026-11-13): retirements follow
  the exact build. `Family::CachyOs(major)` (from the build's name, else
  its `version` file; unknown = newest, and the note says so); byFlavour
  `from` works for Valve, proton-cachyos and GE (`from` + `fromRelease`).
  Version facts read from the tagged scripts: PROTON_USE_NTSYNC only in
  GE-Proton10-9 and proton-cachyos 10 (retired GE10-10 / cachyos 11),
  PROTON_ENABLE_HDR/USE_HDR until GE-Proton11-9 (HDR detection; `=0` still
  turns HDR off: `keepValues`, ok with a note) and proton-cachyos 10,
  PROTON_ENABLE_NVAPI until Proton 8 / GE-Proton8 (on by default from 9),
  PROTON_VKD3D_HEAP, PROTON_MEDIA_USE_GST, PROTON_VKREFLEX until
  proton-cachyos 10. Suggestions (the person): `ntsync`, `nvapi`,
  `vkd3d_heap`, `enable_hdr` (`launch_check::gated`) are listed for the
  builds of their family; each suggestion has `available` and
  `unavailable_why` (plain English, from the KB's `unavailable` text);
  unavailable ones are greyed out in the UI and `combineOptions` refuses
  to add them. Fixes keep values literal (a misspelt name changes only the
  name; rebuilt values are single-quoted when needed; the fixed text is
  lexed again and dropped if it would not split as meant). Misspelling
  fixes only for plain misspellings: a correction that swaps an on/off
  word, a number or a negation gets "did you mean" without a fix;
  NEVER_CORRECT lists real settings outside the KB; removed flags
  (VKD3D_CONFIG dxr11, RADV_PERFTEST aco/gpl/ngg/rt/emulate_rt/wave32) are
  outdated and taken out. A missing %command% after gamescope's words goes
  after its `--` (adding `--`), no fixed text when unsure. Fixes never set
  a setting twice; a bare known name (`PROTON_ENABLE_WAYLAND`) becomes
  `NAME=1`; a setting after a wrapper is moved in front. checkOptions only
  answers the newest request (older ones get no launchResult). ProtonDB
  values are quoted; the extractor drops values cut at 120 characters, with
  home/mount paths, or of LD_PRELOAD/*_PATH/*_RUNTIME/*_FILE/*_DIR, and
  tells GE by a word match (data regenerated from the 2026-11-02 export).
  display card picked by connector per card (two GPUs with the same
  connector name).

  Library with not-installed games and covers (branch `games-library`,
  2026-11-13, the person: "all launchers, a button to hide not-installed
  ones, load the pictures"; from disk only, no network): `Game.installed`
  (false = owned, not installed: greyed card, dimmed cover, "Not
  installed", INSTALL instead of PLAY; `launch` is then the launcher's
  install address, `Games.launch` finds it in `composed` and records no
  play time; `watch_list` leaves it out, so detection never looks for it),
  `Game.note` (shown on hover: "Known to Steam on this PC", "In Lutris's
  GOG library"). Steam: installed from appmanifests as before; the rest
  from `steam_seen_apps` (the last signed-in account from loginusers.vdf:
  localconfig.vdf and 7/remote/sharedconfig.vdf `Software/Valve/Steam/apps`
  keys, userdata/<id>/config/librarycache/<appid>.json, appcache/
  librarycache entries), kept only where `src/appinfo.rs` says type "game"
  (binary appinfo.vdf v27/v28/v29, streamed, unwanted entries skipped by
  size, results cached per file until its size or time changes); address
  `steam://install/<appid>`. Steam's full owned list is not on disk (the
  licences are not readable), so games never touched on this PC are
  missing. Heroic: installed lists as before plus `store_cache/
  legendary_library.json` (`library`), `gog_library.json` (`games`),
  `nile_library.json` (`library`), `sideload_apps/library.json`; DLC
  (`is_dlc`, `install.is_dlc`) skipped; not installed = not in the store's
  installed list and `is_installed` not true; address
  `heroic://launch?appName=..&runner=..` (Heroic's protocol.ts asks "not
  installed, install it?"; there is no "open game page" command). Lutris:
  `games` with installed 0 (`lutris:<slug>`), `service_games` except
  Steam's and ones already listed (`lutris:<slug>`, id
  `lutris:<service>:<appid>`). Covers: Steam `STEAM_COVERS` (600x900, _2x,
  library_capsule, header, library_header) flat, per app folder and one
  folder deeper; Heroic `images-cache/<sha256 of the URL>` (images_cache.ts;
  Epic's card asks `art_square?h=400&resize=1&w=300`, tried first, then
  art_square, art_cover, art_background; local files for added games);
  Lutris coverart, then banners, in data and cache. `Game.cover_url`
  (Heroic art URLs on allowed hosts) feeds the cover downloads (branch
  `cover-downloads`). UI: INSTALLED ONLY switch beside the
  search (`Games.installedOnly`, `saveInstalledOnly`, settings
  `games.installed_only`), tabs show installed/all, badge "n OF m
  INSTALLED", Recent puts installed before not installed among unplayed.
  Demo: GC_DEMO=games[,installedonly][,tabsteam|,tabheroic|,tablutris],
  `GC_DEMO_PICTURES=<folder>` with `<id, ':' as '_'>.png` for made-up
  covers. Screenshots in /mnt/project-files/game-companion/screens/library/.
  Unverified: real files of the person (appinfo.vdf v29 from a current
  Steam, Heroic's images-cache names), cover hit rates.

Open points: QA of the merged branch, test on real KWin (Arch thread), the person's test; the check follows the saved Proton build, not one picked but not saved yet.
Known limits: PoE 1 outside Steam counts as PoE 2; any process with a
game's folder in its command line counts as the game; Steam's not-installed
games only as far as this PC's Steam saw them. Demo: GC_DEMO=games[,gameform]; GC_NO_GAMES=1 stops
detection.

## Branch `claude/project-thread-lncux3` (from beta): replacing FreeTube and Streamlink Twitch GUI

Agreed with the person 2026-11-13 (plan: scratchpad streams-plan, approved
in the thread "replace FreeTube"). Done, not yet merged into beta (the
release thread merges it and sets the version):
- YouTube: Playlists tab (search, sort, quick bookmark), own subscriptions
  with groups, history with continue watching and progress marks, hide
  watched, Trending (Gaming, Football: Europe, national teams, Süper Lig,
  Bundesliga, Premier League, Ligue 1, Serie A, LaLiga; no podcasts),
  Shorts hidden by default, channel and word filters, search filters,
  chapters and speed, playlists played through. FreeTube taken over once
  in Settings → Streams → YouTube.
- Twitch: categories, live notes (off by default), quality per channel,
  filters (language, reruns, order), past broadcasts and clips, chat panel
  (read, write when signed in, Twitch/7TV/BTTV emotes as still pictures).
- Not wanted: YouTube comments. Left out for now: DeArrow, downloads.
Untested online (the sandbox reaches neither YouTube nor Twitch): Trending
searches, Twitch GQL fields for categories/VODs/clips/filters, chat login
and emotes. The person tests these.

## Testing

- Sandbox: Ubuntu, Qt 6.4, offscreen/xvfb (see CLAUDE.md).
- Real KWin: a separate thread on the environment "internet" (Arch
  mirrors allowed) builds an Arch chroot with KWin 6 and tests there; its
  scripts go to /mnt/project-files/game-companion/arch-test/.
- Before a release: idle CPU 0 ticks (scratchpad cpu.sh pattern: utime +
  stime from /proc/<pid>/stat over 10 s).
