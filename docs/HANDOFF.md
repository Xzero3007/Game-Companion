# Handoff: where the work stands

Read CLAUDE.md first, then this. Update "Now" after every finished step,
so a new session carries on from here; details of each step go to
`docs/history.md` (newest at the end, as before).

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
- When the person says a beta is good: a pull request "Stable X (#N)"
  into `main` carrying beta's tree (`git merge -s ours` of main into a
  branch from beta), squash-merged; bump nothing extra. (Until 2026-11-17
  this line said "merge beta into main, fast forward if possible", which
  was no longer how it was done.)
- Milestones: a branch `milestone/<name>` at each working step on beta
  (`git branch milestone/x && git push origin milestone/x`; tag pushes are
  refused by this environment's git proxy), so a broken step can be reset
  without losing the rest.


## Now (2026-11-18)

- 0.8.76 beta (2026-11-18): #174 HDR video: fall back when the picture stays black; Settings height.
- 0.8.75 beta (2026-11-18): #172 HDR video on a subsurface of its own.
- 0.8.74 beta (2026-11-18): #170 Video: the mouse wheel changes the volume.
- 0.8.73 beta (2026-11-18): #168 Video player: keys and a pointer that hides in full screen.
- Branch claude/project-thread-188og6 (2026-11-18): fixes for 0.8.76.
  - HDR video: mpv now draws into an FBO of ours, then a blit (MN's NVIDIA showed black).
  - Twitch after a fall back: the window reloads the stream.
  - HDR badge in the video bar.
  - HDR per source: YouTube and Jellyfin on, Twitch off.
  - The strip's wheel steps by `volume_step`.
  - Waiting for QA, a beta and MN's log line "[video] hdr mpv surface: …".
- 0.8.72 beta (2026-11-17): #166 Get Proton: readable title row and build names in the overview.
- 0.8.71 beta (2026-11-17): #164 Get Proton: full names, newest first, notes for every installed version.
- Stable is 0.8.69 (PR #160, MN's yes after own test); beta is 0.8.70
  (Get Proton, #161 via #163), waiting for MN's test.
- The live list of wishes, decisions and bugs is the project folder's
  `game-companion/BACKLOG.md` (kept by the backlog thread); open points
  noted on older steps are in `docs/history.md` ("Open", "Next").
- Working lean since 2026-11-16: draft pull requests build nothing, text
  changes start no build, notes per part in `docs/notes/` (CLAUDE.md).
- Next big topics: making Game Companion public (plan doc in the release
  thread).

## Testing

- Headless KWin 5.27 in the Ubuntu sandbox, with real frames, screenshots
  and injected clicks: /mnt/project-files/game-companion/kwin-test/
  (README: layer-shell-qt 6.0 patched for Qt 6.4). The DPS click bug did
  not show there after a growing live fight (0.7.3 and 0.7.4, locked and
  unlocked). MN plays in borderless fullscreen (always; do not ask again).
- Sandbox: Ubuntu, Qt 6.4, offscreen/xvfb (see CLAUDE.md).
- Real KWin: a separate thread on the environment "internet" (Arch
  mirrors allowed) builds an Arch chroot with KWin 6 and tests there; its
  scripts go to /mnt/project-files/game-companion/arch-test/.
- Before a release: idle CPU 0 ticks (scratchpad cpu.sh pattern: utime +
  stime from /proc/<pid>/stat over 10 s).


## History

Every step so far, with branches, decisions and open points: `docs/history.md`.
