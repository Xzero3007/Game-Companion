# Game Companion: instructions for Claude

Read this first in every session on this repo. It holds the rules and an
index; the details of each part are in `docs/notes/` (see "Where things are").

## The person

- Writes in **German**: answer in German. Everything that gets built is in
  **English**: UI texts, README, code comments, commit messages, issues.
- Uses Arch with KDE Plasma on Wayland. Two monitors: the main one (Qt's
  primary screen) with the game and the meter, and an Acer X34A (DP-1, at
  0,0, left of it) with Brave. Every part stays on KDE's primary screen
  (0.4.5: Qt's primaryScreen on KWin is the first output KWin announced, not
  KDE's primary, found on real KWin 6.8; `NativeWindow::kdePrimary` reads
  `~/.config/kwinoutputconfig.json`: the "setups" entry whose enabled
  outputs equal the connected ones, its output with the lowest priority,
  1-based there, mapped by outputIndex to "outputs"[i].connectorName =
  QScreen::name(); Settings → Display "Show on" overrides it, settings
  `screen`; a layer surface's output is fixed when it is made, so `place`
  hides a visible window, sets the new screen and shows it again (0.4.7); `NativeWindow::screen`; `place` gives each window that screen's origin
  plus its place, else Qt moves it to the screen at that point: 0.4.1 drew
  on the Acer). Check with an offscreen `configfile` of two screens,
  `GC_SCREEN=<name>` (the offscreen platform makes the one at 0,0 primary)
  and `GC_DEBUG_SCREENS=1` (prints each window's screen and place).
- Wants results and a short, plain explanation of what changed and what to
  do, not a log of the work.

## Hard rules

- **As light as possible** (the person, 2026-11-12): the overlay runs over
  a game and must never make it or the desktop stutter. Nothing redraws
  while idle (no running animations, timers only while needed); every part
  is its own small overlay surface (never one window over the whole
  screen); a video redraws only its own surface; background work (mpv,
  curl) stays out of the UI thread. Before a release, measure the load
  (idle and with a stream): CPU of the app and its mpv, and that idle
  frames are zero.

- **Write down the plan before changing anything**, in plain words, and wait
  for the person's yes. They decide; don't take features away on your own.
- **Colours:** white, grey, gold, red, purple; blue is allowed too (the
  person, 2026-11-13: no aversion to blue; chat names keep their own
  colours). Accent gold `#e0a526` stays the accent for controls: a control
  shows its state in the accent, never in a fixed colour. Values the game
  colours stay so. Item grades in the game's colours with a colour dot:
  Rare green `#7fdc9a`, Legend blue `#4fa8ff`, Unique gold `#f2c46b`.
- **Design: direction B "Edge HUD"** (the person's choice, 2026-11-12): bar
  docked top centre with slanted ends and a thin gold line under it; 56 px
  bar buttons with the icon and a capitals label under it (Rajdhani 700),
  active = gold icon and 2 px gold underline; player row as a slanted strip
  under the bar (square status dots, bar-style volume); panels with square
  corners, no gold line on top (MN, 2026-11-14: removed everywhere),
  capitals headers, underline tabs; panel ground
  `rgba(12,12,15,0.9)` (the opacity setting); body text Inter. Purple
  `#9b6be8` / `#c4a8f0` tags the game module.
- **Nothing is sent without the person's yes.** No account, no pop-ups, no
  links out. Allowed so far (for the coming modules): the radio stations'
  streams (listening only); Twitch's public API, with Streamlink and the
  person's twitch.tv token (to Twitch only); YouTube's feeds and search
  through yt-dlp; Twitch's and YouTube's thumbnails; videos through mpv; the
  person's Jellyfin server, home network only (no server data in the repo);
  FreeTube's subscriptions file, read only; the update check (this repo's
  own GitHub releases only, the person, 2026-11-12); SponsorBlock
  (sponsor.ajay.app, hash-prefix lookup only, off until switched on; the
  person, 2026-11-12); FreeTube's settings file for its SponsorBlock
  choices, read only; FreeTube's playlists, history and profiles (groups),
  read only, taken over once by hand (Settings → Streams → YouTube); Twitch
  chat over IRC (irc.chat.twitch.tv:6697, TLS; anonymous to read, the
  person's twitch.tv token to write; the person, 2026-11-13); chat emotes
  from 7TV (7tv.io, cdn.7tv.app) and BTTV (api.betterttv.net,
  cdn.betterttv.net), asked with the channel's public Twitch id only. The AION 2 Market's prices (Clicktrough's hourly copy on
  raw.githubusercontent.com/Xzero3007/A2Tools-DPS-Meter_Clicktrough/market-data/
  and aion2.exchange's API, read only) and the game's item icons from
  assets.playnccdn.com, kept on disk (the person, 2026-11-13; src/market.rs); Aion 2 Timers' field boss feed
  (www.aion2timers.com/api/fieldboss.php?action=feed&server=<region-name>,
  read only, off until switched on, every 5 min while the Schedule is open
  or 15 while a boss alert waits; src/aion2timers.rs; the person,
  2026-11-13); the Armory's NC character pages (aion2.plaync.com,
  api-search.plaync.com, profileimg.plaync.com; read only, no account;
  src/armory.rs `allowed`; MN, 2026-11-13). The Legcord voice overlay
  (MN, 2026-11-14) opens no connection at all: its Legcord plugin talks to
  Game Companion over a Unix socket; avatars are fetched by Legcord itself
  (its session, cdn.discordapp.com, as it does anyway). The PoE 2 price check (MN, 2026-11-15:
  "bau ee2 nach"): www.pathofexile.com/api/trade2/ only (search, fetch,
  exchange, data; src/poe2.rs `allowed`), asked when an item is checked;
  "Trade site ↗" opens the same search on www.pathofexile.com/trade2/
  (search or exchange pages only, `trade_page_ok`) in the person's own
  browser through xdg-open, only on a click (MN, 2026-11-15: "es muss nur
  aufgehen wenn ich da was anklicken kann"). poe.ninja's PoE 2 economy
  (poe.ninja/poe2/api/economy/ only: leagues, exchange, stash; GET, no
  cookies; `ninja_allowed`), the league's currency overview once in 30
  minutes when an item is checked, on by default, off under Settings →
  Plugins → PoE 2 "poe.ninja prices" (MN, 2026-11-15: "standartmäßig an
  kann man aber auch aus klicken"). poeprices.info: not until it
  knows PoE 2 (MN chose so, 2026-11-15; EE2 itself switched it off).
  Proton downloads (MN, 2026-11-16, "ja"; plan in the project folder
  `proton-download/plan.md`): api.github.com's release lists of
  GloriousEggroll/proton-ge-custom and CachyOS/proton-cachyos only, their
  release files from github.com/<repo>/releases/download/ (the redirect
  checked first: objects.githubusercontent.com or
  release-assets.githubusercontent.com only; `proton_get::download_ok`,
  `redirect_ok`), asked when the Proton overview opens (at most every 6 h)
  or on its ↻; "Release ↗" opens the release page in the browser only on a
  click (`release_page_ok`).
  Brave Origin, Legcord and Rusty Path of Building are the
  person's own programs. Before saying something is done, grep for hosts and
  links: `grep -rnoE "https?://[a-z0-9.-]+" src cpp qml`.
- **Game modules only read** (like the AION 2 meter): never send anything to
  a game or its operator, never inject anything into a game (anti-cheat).
- **Packet captures** (`packets_*.txt` and anything worked out from them)
  never go in a repo, online, or anywhere public. Network analysis belongs in
  the private repo `Xzero3007/A2Tools-Clicktrough-Notes`.
- Never push to or open anything on `taengu/*` repos.
- Take data only where its licence allows it, and credit it as text.
- One project per repo. The Clicktrough meter stays in its own repos until
  the AION 2 module replaces it (plan step 5).
- Commit as `Claude <noreply@anthropic.com>` on `main` (or a branch and PR
  when the person wants to review first); end commit messages with the
  session's attribution lines.


## Working lean (MN, 2026-11-16)

Safety and quality come first; within that, spend as little time, build
minutes and usage as possible.

- Read this file, then only the note of the part you work on (table below)
  and the "Now" part of `docs/HANDOFF.md`. Don't read every note or the whole
  history.
- Collect changes: push a branch only when a step is done and green locally
  (`cargo test`, clippy, the checks of that part). No pushes of single small
  fixes, at night least of all.
- Open a pull request as a **draft**: GitHub builds nothing for drafts. Mark
  it ready when the step is finished and green locally; then the Arch check
  runs (tests and clippy on Arch with layer-shell-qt). Every later push to a
  ready pull request runs it again, so gather fixes into one push.
- Changes to text only (`*.md`, `docs/`, `mockups/`) start no build.
- Beta and stable stay as they are: full package, QA on the Arch bench
  before a beta goes out. Never skip or weaken a test to save minutes.
- New knowledge goes into the matching note in `docs/notes/`; here only
  rules and index lines. Keep this file short (under about 250 lines).
- A copy of the docs as they were before this split (2026-11-16) is kept in
  the project folder `archive/2026-11-16-vor-verschlankung/`.

## Plan

The agreed plan (steps 1 to 5, Plex later) and its decisions:
`docs/notes/plan.md`. Where each step stands: `docs/HANDOFF.md`.

## Where things are

Each note holds what earlier sessions learnt about that part, word for word
as it stood here before 2026-11-16. Read the one you need before changing
that part.

| Part | Note | Covers |
| --- | --- | --- |
| Overlay core | `docs/notes/overlay.md` | one surface per part (layer shell, drag, input regions, screenshots), `Companion`, shortcuts, display settings and `Theme`, settings file, hub hidden, panels and layouts (per game, Desktop), `WheelScroll`, `HudIcon` |
| Lifecycle | `docs/notes/lifecycle.md` | one copy at a time, ending cleanly (signals, KWin timeouts, logout, children), the app's log, updates and channels |
| Radio | `docs/notes/radio.md` | mpv child, station hosts, dead stations |
| Streams | `docs/notes/streams.md` | Twitch, YouTube (feeds, library, lengths, dates, sorting), video player (`MpvVideo`, watchdog, ads, freezing while dragged), Twitch chat, hwdec, loudness, video timing, xvfb checks |
| Jellyfin | `docs/notes/jellyfin.md` | home network only, account, pictures, playback, music, the fake server |
| Brave, Legcord, voice | `docs/notes/apps.md` | KWin watcher and scripts, full-screen handling, the Legcord voice overlay plugin |
| Sound | `docs/notes/sound.md` | channels, mic chain, echo canceller, ducking, front child, panel, meters, sound log, bench without hardware |
| AION 2 | `docs/notes/aion2.md` | parser crate and capture helper, Pet Finder, Schedule, Boss area, LOOT, Armory |
| Games and Proton | `docs/notes/games.md` | Get Proton (GE-Proton, Proton-CachyOS: release lists, checksums, install for Steam and Heroic, Steam restart); game detection, the Games tab and the launch option checker are described in `docs/history.md` ("step 4") |
| Path of Exile 2 | `docs/notes/poe2.md` | price check (EE2 kit in QuickJS, trade API, poe.ninja), session tracker, Path of Building, Qt JIT off |

## Checking a change

```bash
cargo test && cargo clippy --all-targets -- -D warnings
```

Screenshots without a desktop (see README): `QT_QPA_PLATFORM=offscreen`
(add `:configfile=screen.json` with a `screens` list for a 1600×900 screen),
`QT_QUICK_BACKEND=software`, `GC_NO_SHORTCUTS=1`, `GC_DEMO=...`,
`GC_SCREENSHOT=file.png`. The offscreen platform has no input regions; the
real click-through can only be checked on KDE Wayland by the person.

The sandbox is Ubuntu with Qt 6.4 and no layer-shell-qt 6: build there with
`--no-default-features`. The GitHub workflow builds on Arch with
layer-shell-qt, so it checks the layer-shell code. QML must work on Qt 6.4
for local checks (e.g. `Shape.preferredRendererType` is 6.6+).

## Known pitfalls

- `pkill -f <pattern>` also kills the shell running it: use `pkill -x`.
- GitHub starts scheduled workflows late (every 4 to 5 hours in practice).
- Wayland lets no app place or embed another app's window; only KWin
  scripts or rules can.
