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

Open points: QA review, test on real KWin (Arch thread), the person's test.
Known limits: PoE 1 outside Steam counts as PoE 2; any process with a
game's folder in its command line counts as the game; Heroic covers only
for sideloaded games. Demo: GC_DEMO=games[,gameform]; GC_NO_GAMES=1 stops
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
