# Game Companion

One overlay for every game on Linux (Arch, KDE Plasma, Wayland), so one
screen is enough. It sits above the game; locked, every click goes through
to the game.

![The overlay, unlocked, with the radio playing](docs/screenshot-radio.png)

## What it does now

- **An overlay on KDE's overlay layer** (layer-shell): above games in
  fullscreen, borderless or windowed mode. Not inside Gamescope (Steam Deck
  mode), where no other overlay can show.
- **One lock.** Locked (as it starts), every click goes to the game and only
  the lock button in the bar takes clicks. Unlocked, a thin gold frame shows,
  panels move by their header and their buttons work; the overlay only takes
  the keyboard when you click into it.
- **Global shortcuts through KDE**, suggested as:
  - `Alt+Q`: lock or unlock the overlay
  - `Alt+Y`: hide or show the hub (pinned things stay)

  Plasma asks once to confirm them. Change them in System Settings →
  Keyboard → Shortcuts → Game Companion.
- **The bar** at the top centre (the "Edge HUD" design): the name, the game
  module (none yet), lock, settings, hide.
- **Panels remember where they were left**; one opacity for the bar and all
  panels (Settings → General).
- **Hide the hub, keep what you pin.** `Alt+Y` (or the eye in the bar)
  hides the bar and the panels; anything pinned (the pin in a panel's header,
  or at the end of the player row) stays on screen.
- **Radio** (the bar's Radio button): 109 stations by country and genre,
  favourites, recent, search, Best FM first. Played by your **mpv** in the
  background, so it plays on with the panel closed or the hub hidden. Only
  the stations' own stream servers are played (a built-in list, checked
  before every address). The station list comes from the Clicktrough Radio
  plugin (`Xzero3007/A2Tools-Clicktrough-Plugins`, GPL-3.0); refresh it with
  `node dev/stations-from-plugin.mjs <plugins/radio/stations.js>`.
- **Player row** under the bar while the radio plays: state, pause, volume
  as one bar (− and + step by 5, a click on the bar sets it, the wheel
  steps), stop.
- **Updates from its own releases.** At the start, every 20 minutes and with
  Settings → General → Check for updates, it reads `latest.json` of this
  repo's latest GitHub release. A newer one shows a gold **Update** button in
  the bar: it downloads the package, checks its SHA-256, installs it (through
  pkexec, without a password by the package's own root script, which checks
  the checksum again itself; with the password if that is missing) and starts
  again. Only a copy installed by pacman updates itself this way.
- **Turn off** in Settings → General closes the whole app, with the radio.
- **Nothing else goes online.** The fonts ship with the app, the shortcuts
  are local D-Bus; the only network use is the radio stream you pick and the
  update check on GitHub.

## Coming next

1. ~~Core: overlay, lock, shortcuts, bar, settings~~
2. ~~Radio~~, then streams (Twitch, YouTube, Jellyfin) with a preset search
   per game, moved over from the Clicktrough meter's plugins
3. Brave Origin and Legcord (on hold)
4. Game detection: start and close with a game (AION 2, Path of Exile 2),
   and a Games tab that lists the Steam, Lutris and Heroic games and starts them
5. The AION 2 module (first: start the Clicktrough meter with the game)

## Build and install (Arch)

```bash
git clone https://github.com/Xzero3007/Game-Companion.git
cd Game-Companion/packaging/arch
makepkg -si
```

Then start **Game Companion** from the application menu, or `game-companion`.
Each push to `main` also builds the package on GitHub and publishes it as a
release (with `latest.json`, the update check's manifest). Installing a
release package (`sudo pacman -U game-companion-*.pkg.tar.zst`) works too;
after that the app updates itself.

Needs: `qt6-base`, `qt6-declarative`, `qt6-wayland`, `layer-shell-qt`,
`xdg-desktop-portal`, `polkit`, `curl`; `mpv` for the radio (and to build: `rust`, `clang`,
`base-devel`).

### Development

```bash
cargo run                          # on KDE Wayland
cargo test
cargo build --no-default-features  # without layer-shell-qt (not above fullscreen games)
```

Screenshots without a desktop (the backdrop stands in for a game):

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software GC_NO_SHORTCUTS=1 \
GC_DEMO=backdrop,unlocked,settings GC_SCREENSHOT=shot.png cargo run --no-default-features
```

`GC_DEMO` takes `backdrop`, `unlocked`, `settings`, `shortcuts`, `about`,
`radio`, `radio-playing`, `hidden`.

## How it is built

Qt 6 / QML for the interface, Rust for the logic, joined by
[CXX-Qt](https://github.com/KDAB/cxx-qt).

| Path | What |
|---|---|
| `src/companion.rs` | The overlay's state for QML: lock, shown, opacity, places, shortcuts |
| `src/settings.rs` | `~/.config/game-companion/settings.json` |
| `src/shortcuts.rs` | Global shortcuts through the GlobalShortcuts portal |
| `src/radio.rs`, `src/radio_object.rs` | Stations, the radio's network guard, the mpv player, the `Radio` QML singleton |
| `data/stations.json` | The station list |
| `cpp/native.cpp` | The Qt app, KDE's overlay layer, the input region |
| `qml/` | The interface (Edge HUD design, colours in `qml/theme.js`) |
| `packaging/` | Desktop file and the Arch package |

## Licence

GPL-3.0-or-later (see `LICENSE`). Parts are adapted from the Clicktrough
meter (`Xzero3007/A2Tools-DPS-Meter_Clicktrough`, GPL-3.0).

Fonts: Rajdhani by the Indian Type Foundry and Inter by The Inter Project
Authors, both under the SIL Open Font License 1.1 (`assets/fonts/OFL-*.txt`).
