# Inventory (A2Tools plugin)

Your inventory, character storage and server storage, each item with its
picture and name and what the sellable ones bring on your server's market;
the drops of a session; your limits and keys, and a floater with the ones you
pick.

- **Inventory, Character storage, Server storage**: every item with its
  picture, name, grade and count, sorted by value (or name, count, grade), a
  search, and **Sellable only**. **Sellable** (gold) is an item traded on your
  server's market and not bound: the lowest listing on your server (else the
  average sale of the last 28 days), times how many, and the sum of each list
  (before the market's 10 % fee; after it in the sum's tip). An item whose
  lowest listing is far above its **usual price** (5 × or more: a single
  listing at a fantasy price, as Destruction Cloaks at 10,000,123 while they
  usually go for about 65,000) counts at the usual price, marked **Usual
  price** with the why on hover: `anomaly.js`, the same file as the Market
  plugin's, with the course the hourly price copy keeps. Bound items and
  currencies are listed without a value; the inventory's Kinah stands in the
  line above the list.
- **Drops**: what came into your inventory in a **session**, every item
  with its count and worth and **where it came from**: the buttons above
  the list show **All**, **Gathered** (the game's own gathering result for
  the item), **Loot** (picked up from the ground), **Rewards** (a chest or
  Hidden Cube opened with a key, or several items at once) and **Other**
  (bought, crafted, from mail or a quest). Kinah, Kinah per hour and Abyss
  Points gained stand in the line above.
  - **Gathering**: how often you gathered, at how many spots, how many items
    (and per gathering), the **great** gatherings the game marked, the
    **bonus** items it added, and what it is worth (in all and per hour);
    **Where** splits them by map and region (as the Map plugin knows them:
    with the Map's window or overlay open).
  - **Dismantled**: common gear the game breaks down for Enhance Stones as
    it comes in is **no drop**: it is taken out of the list, and the line
    says how many pieces, how many Enhance Stones and the bound Kinah it
    cost.
  - **Sessions**: a session goes on across restarts and changes of
    character, and a **new one starts by itself** when you play again after
    a break (3 hours at first; 1, 6 or 12 hours, or only by hand, in the
    menu on the right). **Played** counts the time something happened,
    pauses of 5 minutes or more left out, and the per-hour numbers go by it.
    The menu on the left shows the **earlier sessions** (the last 40).
    **New session** starts one at once.
- **Farm days** (0.5.0): each day from one daily reset (07:00 UTC) to the
  next, per character, with **where everything came from**: **Open world**
  (with its towns), **Dungeon**, **Abyss** (its three layers and the Abyss
  Corridor), **Shugo Festival**, **Dimensional Invasion** and **Other**
  (arenas, a zone not known yet). Per source: the time played there, Kinah,
  items, their worth and the gold items. The **Kinah cap**: when the
  1,000,000 of the open world was reached and after how long played there
  (and since its first Kinah); the farm goes on after it (no Kinah in the
  open world any more, the drops and the Abyss's Kinah still count), and
  the day says what came after the cap. Every **gold item** (Unique and
  higher) with when, from where and in which zone, and its worth.
  - **Whose** (0.5.1): the character picked at the top, or the **whole
    account**: every character's days added up (each gold item with its
    character; how many reached the cap, and the hours to it on average).
  - **Where and when** (0.5.2): each stretch of play at one place, from
    its first gain to its last (a break of 15 minutes or more starts a new
    one), with the time played, Kinah, worth and gold. The place is the
    Map's map and region in the open world and the Abyss (with the Map's
    window or overlay open), else the zone's name. The Drops tab shows the
    same for its session; the statistics add **By place** over all days:
    days, hours, Kinah, worth and gold per hour.
  - **Where from**: the zone you are in (the world's zone, permission
    `events:world`; the zone's kind as the meter's `zones.rs` reads the
    game's numbering, its name from the Map's data, `zones.js`). The
    Incursion of the Spirits counts as the Dimensional Invasion. A **Shugo
    Festival** or **Dimensional Invasion reward key** used (the game's count
    of it going down) makes the gains 20 seconds around it that event's,
    wherever you are. Bought (Kinah spent), crafted or broken-down items are
    no drop. The open world's Kinah is the game's own counter toward the cap;
    elsewhere the Kinah coming into the inventory. Worth: the market price
    when it dropped (valued later when the prices weren't read yet).
  - **Statistics**: for a source (or all) and **Kinah per hour** (the open
    world's up to the cap), **gold items per hour**, **item worth per hour**
    or **hours to the cap**: a bar a day with the **trend**'s line (a
    straight line by date: how much it rises or falls a week, and whether
    that is more than chance, p < 5 %), the **last 7 days against the days
    before** (Welch's t test; for gold items, which are rare, an exact test
    of the drops per hour played), how big a change the days at hand would
    show, and **gold items by the hour of the day**. **When it is
    meaningful**: a day counts for a source with half an hour played there;
    the numbers are meaningful from **7 such days**, gold items also from
    **30 drops**. Until then the page says how many days or drops are still
    missing and shows a trend only as a hint.
- **Dungeon drops** (0.6.0): each **run** (a visit of a dungeon) with the
  **reward boxes** taken (40 Odyle Energy spent there a box; the game's
  count of Odyle Energy going down, `events:character`) and the gold and
  rated items that came in, per character or for the whole account.
  Against **the game's own drop rates** (0.6.1: AION 2 Global, the game's
  reward tables, game version 2026.10.28; `dungeon-rates.js`): Fire
  Temple, Krao Cave, Urugugu Canyon, Ferocious Horn Den (Normal and Hard),
  Draupnir and Vakron Sky Island (Hard), Abyssal Forge: Ludra. A box rolls
  every boss's pools; the table gives each item's chance to drop at least
  once a box, and an item the game drops more often elsewhere is not in a
  dungeon's table (Fire Temple Hard's Wrathful Mind, Will and Ego are
  added from the game's Obtainable Rewards window: 3.6 + 1.2 + 1.2 %). The
  items go in groups by grade (Unique gear, Unique collectibles, Legend
  gear ...; hover a row for its items and chances), each with your count
  and rate a box, what was to expect (a range where the table can't say
  how often a common item drops in one box: between one roll and three
  bosses' rolls), the **range** 95 of 100 players with as many boxes land
  in, and the **verdict** (in range, above or below it: more than luck, an
  exact Poisson test, p < 5 %; faint while fewer than 5 drops are to
  expect); **Unique and up together**, the **last 7 days** and **week by
  week** (from the weekly reset); the last runs with what each brought. A
  dungeon or mode without rates shows its runs, boxes and gold a box. Which
  zone is which mode is taken from the game's numbering (a dungeon's id
  ending in 1 Normal, the others Hard) and shown with each dungeon.
  `python3 -I dev/make_dungeon_rates.py <rates.json> > dungeon-rates.js`
  writes the table.
  0.6.3: a group whose chances add up to about one or more (Legend gear
  in the Hard modes: about 8 pieces a box in Fire Temple Hard, from pools
  that drop every box and roll several times) shows **your count a box
  only** ("Rate only"): the table can't say how many to expect, and a
  verdict said "above" for nothing.
  0.6.2: each grade (Rare, Legend, Unique ...) with **a dot in the item's
  colour** after it, here and in the item lists.
- **Limits**: Kinah gained today (of 1,000,000), the week's Abyss Points (of
  the week's limit), and the keys and entry counts the game keeps (Shugo
  Festival keys, Nightmare, Dimensional Invasion, the daily dungeons, the
  Ascension Trial, the Abyss's hours, the party dungeons' rewards ...), each
  with its bar. A tick puts it in the **floater**, a small card over the game
  (switched on here; dragged by its head, its sides set the width, the slider
  how much of the game shows through; the meter's lock locks it too:
  locked, clicks go through it to the game).
  **1 2 3** in its head are three places of your own: a right-click on a
  number keeps where the floater is and its width there, a click goes back
  to it (a kept place's number is gold). The **gauge button in the meter's
  title** (meter patch 0035) shows or hides the floater without the plugin
  window; the puzzle button leaves it as it is.
  **Complete at once** (0.4.1): the game sends the whole list only at a
  login, so a meter started later (after logging in, or again after an
  update) knew only what changed since, until the next character switch.
  The plugin keeps each character's last values and shows them until the
  game sends new ones, dimmed, with when the game said them on hover. Past
  a reset (daily 07:00 UTC, weekly Wednesday 07:00 UTC) Kinah today and the
  Abyss Points show 0, a key or count stays marked "before the reset"; Abyss
  Points gained meanwhile are added to the kept ones.
- **Another character**: the menu at the top shows the items of every
  character seen before, as they were last.

## Where it comes from

The game sends the inventory and both storages when you enter the world
(log in, or switch character), and each change after it: the meter reads
them (its patch 0034, permission `events:items`), and the plugin keeps
each character's (the server storage once per server). So:

- **Start the meter before the game** (or log in again once): a meter
  started later sees only what changes, until the next login.
- Moving items between the inventory and a storage sends nothing the meter
  can read: the storages are exact as of the last login, and after sorting
  your inventory (the sort resends it, and what it has more or less went to
  or came from a storage).
- Kinah today comes with each gain; the week's Abyss Points at login, and
  with patch 0034 each gain is added to them at once.
- The keys and entry counts come at login and each time one changes.
- The **server's gathering limit** is not read from the game yet.
- Gathering: the game reports each gathering's item, amount and bonus; the
  plugin reads it with its own decoder (`gathered`, permission
  `decoder:gathered`) and matches it to the item coming in. The map and
  region come from the Map plugin (`events:shared`).

Prices: aion2.exchange's (players' collected market prices), first from the
Clicktrough fork's hourly copy on GitHub, else from aion2.exchange itself,
read when the window opens and every 30 minutes (`a2.web.get`). Pictures:
the game's icon server (assets.playnccdn.com), through the meter
(`a2.web.image`). Nothing is sent anywhere.

## Data

`zones.js` (the zone names): `node dev/make_zones.cjs` from the Map's
`data.js`.

`data.js` is generated: `python3 -I dev/fetch_icons.py <cache>` (Aion2Data's
item lists, once), then `python3 -I dev/make_data.py <SkeeveAN checkout>
<cache>`. Item names, grades, the gear's and crafting items' icons and the
content tickets come from SkeeveAN's Aion-DPS-Meter (MIT, read from the game
client; NOTICE-SkeeveAN.txt), the other items' icon names from Aion2Data
(NOTICE-Aion2Data.txt). Tests: `bash dev/ci.sh`.
