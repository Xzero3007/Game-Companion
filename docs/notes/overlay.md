# Overlay core: surfaces, settings, display, panels and layouts

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- One surface per part (0.4.0, the person, 2026-11-12, after stutters
  with a stream over the game): `qml/Surface.qml` is a `Window` holding one
  part (bar, player row, each panel, each video, the hub hint). No frame
  or note while unlocked (the person, 2026-11-12: in daily use it was in
  the way); the lock in the bar shows the state. While a part is dragged
  or resized, its surface holds the whole screen and stays still
  (`Surface.held`, `grab`; moves are ignored for 120 ms until `steady`;
  `qml/drag.js` `fix`: Sway measures the pointer from the window's place at
  the press, KWin from its place now; the first steady move picks the
  reading nearer the press, found on Sway by the Arch test thread): a surface
  moved per pointer event jumped about, because KDE places it a moment
  later and the next pointer place came from the old position. The part keeps x/y in **screen
  coordinates**: it lives in `Surface.scene` (screen-sized, shifted by the
  surface's place), its parent. `nativeWindow.attach` makes the window a
  layer-shell surface (overlay layer, anchored top and left, exclusive
  zone -1, keyboard none; on-demand only after a click into the part
  while unlocked, `setKeyboard` + `eventFilter`, back to none on lock or
  hide: KWin activates an overlay surface the moment it accepts keys, which
  took the game's focus and mouse on unlock and when a part opened by
  itself, MN 2026-11-14; `_q_showWithoutActivating`; the input region is
  set before the first show), `place` sets the
  margins (x, y) and size, `setInput` the input region (`QWindow::setMask`:
  unlocked everything, locked only the lock button or one pixel). X11:
  frameless on-top windows at that geometry. Dragging (`MoveArea`, the
  bar's `DragArea`, resize corners) measures in `target.parent` (screen
  coordinates), never `mapToItem(null)` (the window moves along). Popups
  must stay inside their part, or the part's surface must grow (`extra`,
  as the bar's tooltip). Stacking between surfaces is KWin's (no z across
  parts); `stack` only orders screenshots. Root of `Main.qml` is `Overlay` (a QtObject with a
  default list), **never an Item**: Qt 6.7+ embeds a Window declared inside
  an Item into that item's window (0.4.0 showed nothing on the person's Qt;
  the sandbox's Qt 6.4 does not do this). Screenshots (`GC_SCREENSHOT`): every part moves into one
  screen-sized window (`nativeWindow.shotScene`), grabbed whole (a
  software window's own grab has no alpha). Under `xvfb-run` with xcb, each
  part is its own X window (`xdotool search --onlyvisible --name "^Game
  Companion$"`, `getwindowgeometry`): good for checking places and drags.
  The radio's mpv: `--audio-buffer=1`, cache with `cache-pause-wait=4`
  (stutters when the system hangs briefly).

- `src/companion.rs`: the `Companion` QML singleton (CXX-Qt). The shortcut
  thread queues onto the Qt thread (`qt_thread().queue`).
- `src/shortcuts.rs`: the GlobalShortcuts portal, adapted from the meter's
  `hotkeys.rs`; ids `lock` (Alt+Q) and `toggle` (Alt+Y, hides the hub),
  the person's own KDE keys (2026-11-12). App id
  `io.github.xzero3007.GameCompanion` (the desktop file's name).
- Display settings (the person, 2026-11-12): `alpha` 0.05 to 1 (all
  parts); `text_level` and `accent_level` 0.4 to 1 for **the bar and the
  player row only** (the person: panels like Settings or YouTube stay as
  designed); `bar` {offset px from the centre, scale 0.6 to
  1}, three presets each (`alpha_presets`, `text_presets`,
  `accent_presets`); all in layouts (old layouts lack them: kept as they
  are). `Theme.text(hud)`, `textSoft(hud)`, `muted(hud)`, `dim(hud)` and
  `accentFor(hud)` are **functions** (theme.js imports `GameCompanion` and
  reads `Companion.textLevel`/`accentLevel` when `hud` is true, so
  bindings follow): HudBar, HudButton and PlayerRow pass true, IconButton
  and VolumeBar take a `hud` property; elsewhere `Theme.text()`;
  every `Text` has `style: Theme.textStyle(); styleColor: Theme.shadow`
  (a dark outline under half opacity): keep both for new text. The bar and
  the player row scale from their top left; the surface takes the scaled
  size.
- `qml/theme.js`: the design's colours and fonts (a JS library, not a QML
  singleton: files in `qml/` would otherwise see the implicit directory
  import's non-singleton type).
- Fonts ship in the binary (Qt resources): nothing is fetched.
- `src/settings.rs`: one shared settings file (`settings::read` /
  `settings::change`), used by every QML singleton.

- Hub hidden (`Companion.shown` false): the bar, the welcome and settings go;
  panels and the player row stay if their id is in `pins`. Locked with the
  hub hidden, nothing takes clicks (Alt+Q / Alt+Y still work).

- Panels (`qml/Panel.qml`) keep place and size in `settings.places`
  (`x`, `y`, `w` = 0 for its own width, `grow` = height added to a
  `stretchy` panel's list or video, which the panel's content adds to its
  own height). Layouts (`settings.layouts`, the person, 2026-11-12) copy
  places, pins, alpha and the open panels (`Main.openPanels()`); loading one
  raises `Companion.layoutRevision`, and every panel places itself again.
  A game brings its own layout (MN, 2026-11-15): `games.layouts` by game
  id, picked in Settings → Layouts ("Games", `Games.layoutGames` = the
  watch list, built-in `known:` games too) or in the game's edit form;
  `Main` `onStarted` keeps the arrangement (`Companion.keepBeforeGame`,
  settings `before_game`/`before_game_for`, kept over a restart during
  that game) and loads the layout; `onStopped` → `backFromGame` brings it
  back if `layout_back` (default on). The Desktop layout (MN, 2026-11-16;
  settings `desktop_layout`, `Companion.setDesktop`, the "Desktop" chip
  under "Games") loads at the app's start (`restoreOpen` →
  `loadDesktop`) and when a game ends (wins over `before_game`). Layouts
  also keep `streams.video_opacity` (`opacities`: Twitch, YouTube,
  Jellyfin, chat, DPS; old layouts leave it); VideoWindow, ChatPanel and
  DpsPanel read it again on `layoutRevision`.

- `WheelScroll`: a `Behavior` with `SmoothedAnimation` on `pos`, so wheel
  steps add to the goal without restarting the glide (MN: scrolling felt
  poor); lists keep `cacheBuffer: 600`. A notch is told by its angle (a
  multiple of 120): on KDE Wayland Qt gives a wheel notch a small pixel
  delta too, which was taken for a touchpad (MN: scrolled far too little).
  Settings → Display "Scroll speed" (`Companion.wheelSpeed`, 50 to 500 %)
  scales every step. `GC_DEMO=settings,display`.

- `HudIcon` is a picture from the icon provider (`cpp/icons.cpp`,
  `image://icon/<path>|<colour>|<line width>|<filled>`, QSvgRenderer at
  twice the size): one small texture per look, shared and cached. It was a
  multisampled layer per icon (shapes alone were not clipped by a list's
  clip in the software renderer), which cost video memory. Needs qt6-svg
  (sandbox: `apt install qt6-svg-dev`).
