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
- When the person says a beta is good: merge `beta` into `main` (fast
  forward if possible), bump nothing extra, push.
- Milestones: a branch `milestone/<name>` at each working step on beta
  (`git branch milestone/x && git push origin milestone/x`; tag pushes are
  refused by this environment's git proxy), so a broken step can be reset
  without losing the rest.


## Now (2026-11-16)

- Stable and beta are both 0.8.69 (stable PR #160, MN's yes after own
  test); every build thread is closed.
- The live list of wishes, decisions and bugs is the project folder's
  `game-companion/BACKLOG.md` (kept by the backlog thread); open points
  noted on older steps are in `docs/history.md` ("Open", "Next").
- Working lean since 2026-11-16: draft pull requests build nothing, text
  changes start no build, notes per part in `docs/notes/` (CLAUDE.md).
- Next big topics: making Game Companion public (plan doc in the release
  thread), downloading Proton versions (N1, own build thread).

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
