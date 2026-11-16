# AION 2 module

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

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
