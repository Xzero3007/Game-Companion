# Lifecycle: one copy, ending cleanly, the log, updates

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

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
