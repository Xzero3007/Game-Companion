# Plan (agreed 2026-11-12)

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.


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
   running game's (purple tag). Only while a game runs (MN, 2026-11-23); a
   game without its own search looks for its name.
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
