# Games and Proton

Moved word for word from CLAUDE.md (2026-11-17); read it before working on this part.
Game detection, the Games tab, launch options and ProtonDB were never
written up here; their steps are in `docs/history.md` ("step 4", "games-launch").

- Get Proton (MN, 2026-11-16): `src/proton_get.rs` (logic),
  `src/proton_object.rs` (the `ProtonGet` singleton), `qml/ProtonDownloads.qml`
  at the top of the Proton overview. GE-Proton and Proton-CachyOS (its SLR
  build; x86_64_v3 when the CPU has it, `cpu_v3`) from GitHub: the latest
  release, its notes as plain text ("What's new"), the library's games the
  notes since the installed version name ("Worth it", `mentions`), Install
  for Steam (the first `steam_roots` folder's compatibilitytools.d) or
  Heroic (tools/proton). A job: checksum first (the release's `.sha512sum`,
  else GitHub's sha256 `digest`; none → refused), curl to
  ~/.cache/game-companion/proton/ (progress by the file's size every
  250 ms, only while it runs), tar into `.gc-partial-<tag>` beside the
  builds, the one folder with a `proton` file renamed into place (named as
  the archive when its own name is not a download's). curl and tar have
  PR_SET_PDEATHSIG; Cancel and `proton_get::stop` (main's `tidy`) kill
  them and remove the leftovers, which every look also removes after a
  crash. Remove: only folders named like a download, directly in a
  target, no links; asked first, with how many games use it. After an
  install or removal `TOOLS_STALE` makes the overview read the builds
  again (`ProtonGet.revision`). pacman's proton-cachyos(-slr): `pacman -Q`,
  `-Si` and `vercmp` only (no network), "comes with your system update".
  Release lists kept in ~/.cache/game-companion/proton-releases.json.
  Steam restarts after an install (MN, 2026-11-16; settings
  `proton_restart_steam`, default on, the box under GET PROTON;
  `restart_steam`: one detached `sh` (`RESTART_SCRIPT`, own session, so
  it finishes when the app quits meanwhile): `steam -shutdown`, up to 40 s
  (pgrep), then `steam -silent`; flatpak if no `steam`; the app only
  watches for Steam to come back), never while a Steam game runs
  (a "SteamLaunch" reaper, `steam_game_running`); then "Restart Steam"
  shows beside OK. A look also removes half downloads when no job runs.
  `GC_DEMO=games,proton[,protonjob]`; `GC_PROTON_FAKE=<dir>` reads
  `ge.json`/`cachyos.json` there instead of GitHub.
