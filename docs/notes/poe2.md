# Path of Exile 2

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- PoE 2 price check (MN 2026-11-15, Exiled Exchange 2 rebuilt because
  EE2 was unreliable on KDE Wayland): `tools/poe2-ee2/build.mjs <EE2
  checkout>` makes `qml/poe2/ee2kit.js` (EE2's parser, filters and trade
  code for Qt's ES2016: shims, polyfills, look-behind patch, named groups
  through `__gcMatch`/`__gcExec`, no setInterval) and `data/poe2/` (en, de;
  installed to /usr/share/game-companion/poe2, `GC_POE2_DATA`). Rebuild it
  when EE2 brings a new league's data (1.0 in December). `src/poe2.rs`:
  trade requests (one at a time, 429 respected, cookie jar in
  $XDG_RUNTIME_DIR) and the XFixes clipboard watcher on XWayland (the
  person's own Ctrl+C in the game; nothing is sent to the game).
  `qml/poe2/PriceStore.qml` + `PriceWindow.qml`, plugin `poe2.price`, only
  while PoE 2 runs. The kit does **not** run in Qt's JavaScript (Arch's Qt
  6.12 crashed in it, JIT and interpreter; MN 0.8.44, reproduced by QA):
  `src/poe2_kit.rs` runs it in QuickJS (rquickjs) in a child process
  (`/proc/self/exe --poe2-kit`, JSON lines on stdin/stdout,
  PR_SET_PDEATHSIG from the Qt thread, ends when stdin closes or the
  parent goes, `poe2_kit::stop` on quit); `PriceStore.kit(fn, args)` gives
  a promise; if the child dies only the price check starts again
  (`kitGone`). GC_DEMO=price answers inside the child (`DEMO`). The kit is
  still built without array iterators (Babel pass in build.mjs). Tests:
  `cargo test poe2_kit` (an item, a search, EE2's 27 samples in QuickJS).
  Tests: `node tools/poe2-ee2/test/run.js`, the ignored
  `copied_items_are_seen` under xvfb-run with xclip. `GC_DEMO=price[,results|,gloves]`,
  `settings,poe2prefs`, `price,results,listing` (a listing's item shown),
  `price,currency` (the exchange with poe.ninja's price). A click on a
  listing shows its item under the row (`ListedItem.qml`, the kit's
  `item` from EE2's DisplayItem: values, requirements, enchants, runes,
  implicits, mods with tiers, in the trade site's colours; MN, 2026-11-15).
  poe.ninja (`tools/poe2-ee2/ninja.ts`): the exchange's Currency overview
  (`core.rates.exalted` = ex per divine, `lines[].primaryValue` in divines,
  ids = the trade site's currency ids, `items[]` the names; shape from MN's
  copy, Runes of Aldur); each listing's `norm` (in ex, from one divine up in
  div), a currency item's `ninja` (div, ex, 7-day change) in the view and
  the result. Layout like the game (MN, 2026-11-15): with the
  advanced copy (Ctrl+C with Alt held) the kit's `view().mods` (from the
  item text's `{ … }` headers, matched to EE2's mods by name and tier)
  make the groups IMPLICIT · ENCHANT · RUNES, PREFIXES, SUFFIXES (each
  line with the tier's range in brackets, its tier, the stat line that
  searches for it, or "in the totals"/"in the item's values"); without it
  EE2's stat lines in VALUES, LINES, TOTALS. Min/max per line
  (`RangeField`, wheel works locked). EE2's settings in `PriceSettings.qml`
  (window ⚙ and Settings → Plugins → PoE 2), kept in settings.poe2,
  handed to the kit by `setPrefs`. The league is chosen there too (its
  list asked only while PoE 2 runs and the settings show; QA, 0.8.65; MN,
  0.8.55: the window's dropdown opened under the chips). `setStat`'s
  bound "keep" leaves it as it is (QML's `undefined` arrives as null
  through JSON and cleared the other bound). `tradeLink` adds
  `disabled: false` to every filter group (the site showed Equipment
  Filters unticked). Dropdowns at a panel's end open past its surface:
  use a list that opens in place (the session's "Add currency"). The clipboard watcher connects again by
  itself when XWayland's connection ends; `Poe2.watchError` shows in the
  window (0.8.44, MN: Ctrl+C did nothing). EE2's leagues come unencoded
  ("Runes of Aldur"): `encode_address` before `allowed`.
  PoE 2 session tracker (MN 2026-11-15, plugin `poe2.session`; no network):
  `src/poe2_log.rs` reads the game's own `logs/Client.txt` while PoE 2
  runs (from its end; only area, level-up, own death and AFK lines, never
  chat or whispers), `Poe2Log.heard`; rules in `qml/poe2/sessionkit.js`
  (`node tools/poe2-session-test.js`), `SessionStore.qml`,
  `SessionPanel.qml`, `SessionWindow.qml`; new session after 30 min / 1 h
  of pause or at midnight. `GC_DEMO=session`. Details: docs/HANDOFF.md.
  Loot by hand (part 2): currency with − / + or a copied stack and items
  by the price check's "+ Session", worth from poe.ninja's exchange
  overview (`SessionStore.needRates`, only while the session holds loot,
  30 min; the price check's "poe.ninja prices" switch). PoE 2 has no stash
  API (GGG: PoE 1 only); never read the game's memory.
  Path of Building is the third app (`pob`, `AppDef.args` "poe2",
  `AppDef.game` "poe2"; bar button while PoE 2 or PoB runs).
  Qt's JavaScript runs without its JIT (`main.rs` sets
  `QV4_FORCE_INTERPRETER=1`, `GC_JIT=1` keeps it): Arch's Qt 6.12 JIT
  crashed in the kit every run (QA 2026-11-15), Qt 6.12.0 from PySide did
  not; the interpreter cost no more CPU in the demos. Run Qt 6.12 in the
  sandbox from a PySide6-Essentials venv (`LD_LIBRARY_PATH`,
  `QT_PLUGIN_PATH`, `QML_IMPORT_PATH` to its `Qt/` folders): the app built
  on 6.4 runs on it.
