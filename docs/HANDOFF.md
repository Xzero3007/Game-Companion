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
  combineOptions, setLaunchOptions, protonVersions, setProton, systemInfo:
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

Open points: QA review done (fixes on the branch), test on real KWin (Arch thread), the person's test.
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
