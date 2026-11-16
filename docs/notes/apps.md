# Brave, Legcord and the Legcord voice overlay

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

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
