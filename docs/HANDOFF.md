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
  game), start with the desktop (Companion.autostart, `--hidden`), on
  start: Streams preset, show hub, radio, layout (Main.qml Connections).

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

Open points: QA of the merged branch, test on real KWin (Arch thread), the person's test; the check follows the saved Proton build, not one picked but not saved yet.
Known limits: PoE 1 outside Steam counts as PoE 2; any process with a
game's folder in its command line counts as the game; Heroic covers only
for sideloaded games. Demo: GC_DEMO=games[,gameform]; GC_NO_GAMES=1 stops
detection.

## Testing

- Sandbox: Ubuntu, Qt 6.4, offscreen/xvfb (see CLAUDE.md).
- Real KWin: a separate thread on the environment "internet" (Arch
  mirrors allowed) builds an Arch chroot with KWin 6 and tests there; its
  scripts go to /mnt/project-files/game-companion/arch-test/.
- Before a release: idle CPU 0 ticks (scratchpad cpu.sh pattern: utime +
  stime from /proc/<pid>/stat over 10 s).
