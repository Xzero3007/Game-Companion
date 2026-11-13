# Closet (A2Tools plugin)

Your skins against the 700 of the title **Empty Closet**: what the Black Cloud
Merchant offers each of your characters this hour, marked new or owned; one
window over the game when you open the shop; every skin you still lack with
its picture and price, and what the rest costs; and what to combine and
extract and what no longer pays.

- **Merchant**: each character's offers of this hour (Special and Skins tabs,
  and any other tab with skins), **New** (gold: a skin you lack), **Owned**
  (dimmed) or **?** (a skin whose closet entry is not known yet), with price
  and discount and when the stock changes. Which characters of the server you
  have not looked at this hour. **What the merchant brings**: from the stocks
  you open, how often a skin you lack is on offer and what a paid change of
  the stock (the shop's refresh button: 500 Kinah, then 1,000, 2,000 ...
  15,000) costs per new skin.
- **The Closet window** (one window): opening the game's Shop, a tab of
  the Black Cloud shop, or the closet opens it over the game (**Window at
  the shop**); opening the game's Market opens it too. On top the skins of
  the stock you opened last, with their pictures, new ones (gold) first and
  whose stock it is; under them **On the Exchange**: the 8 cheapest skins
  you lack that are listed there (**Buy** in gold where that is below the
  merchant's price); at the bottom two short lines: the characters of the
  server not looked at this hour, and what to combine in the closet (the
  Combine tab has the rest). Two tabs in its head: **Shop** (all that) and
  **Exchange**: every skin you lack that is listed on the Exchange, cheapest
  first, with its price, how many are listed and **Buy** where it is below
  the merchant's price; **Exchange list** on the Merchant tab opens the
  window on it. The window keeps the tab you chose. The pictures are big
  (72 px); each comes to the window in a message of its own (in parts: a
  message is at most 64 KB) and the window makes a small copy the plugin
  keeps, so they show at once the next time; one that didn't come is asked
  for again after 5 minutes (the meter keeps the game's icons on disk
  itself, patch 0070). It goes when you walk off or teleport
  to another zone, after 3 minutes, or with its × (until you come back;
  the × stays while the meter is locked); **Everywhere** (or the
  shirt button in the meter's title) keeps it up all the time. Drag it by
  its head and size it at its edges while the meter is unlocked, or with
  the size on the Merchant tab. At the shop and the closet it takes the
  mouse even with the meter locked, so its list scrolls (a wide
  scrollbar); it stays put then (meter patch 0064). Elsewhere a locked
  window lets clicks through to the game. When no picture comes from the
  icon server, the panel's top line says why. The Merchant tab says
  whether the window is open and why not (the tick off, closed with its ×),
  and when the last shop list came (and when a shop frame came that it
  couldn't read). The offers are found in the shop's message by their
  prices, so a changed layout around them doesn't lose a tab. **Note new skins**: a note
  when a skin you lack is on offer.
- **Missing**: every skin you lack (one per closet entry) with its picture,
  grade, slot and the merchant's list price, filterable by kind and grade,
  searchable; above, what the skins still needed for 700 cost: the cheapest
  all at 50 % off, an average mix at the usual discount, the dearest at 10 %
  off, and every merchant skin you lack. **On the Exchange** (the players'
  market): each skin you lack that is listed there, with its lowest price
  and how many are listed, in gold where that is below the merchant's
  price (he may never offer it); filter "On the Exchange" and order "By
  Exchange price" show only those, cheapest first. The prices come from
  this build's hourly price list (aion2.exchange's market prices, which
  know only the skins players' clients reported, often a few dozen a
  server, hours old).
- **Combine**: a combine takes 4 skins of a grade and gives one, the next
  grade at NCSOFT's published chance (Common 25 %, Rare 20 %, Epic 15 %,
  Unique 10 %; 35/30/25/15 % with a Lucky Aura), else a skin of the same
  grade (as seen in the game). A dyed skin can't be combined until its
  dye is removed. Per grade: the share you lack of it and of the next, new skins per
  combine (counting the copies it gives, which go into the next combines),
  Kinah per new skin, your spare copies and the combines they allow, and a
  verdict: **Combine**, **Only for <next grade>** (rarely new itself, but it
  feeds the next grade) or **Stop**.
- **Extract settings**: gear gives its look as a skin when extracted
  (Common, Rare, Epic one time in four, Unique one in ten). The game's
  Extract Settings dialog drawn again, ticked as it pays for your closet:
  Auto Extract on, a grade ticked when its pieces bring new skins (Epic) or
  do while they sell for little (Common, Rare), Unique off to extract
  by hand only the pieces with a new look; each with its chance of a new
  skin a piece, counting the copies that go into combines (a Rare copy can
  climb to Epic), and the sale price up to which extracting beats selling.
- **Combine now**: on the Combine tab (and as one line in the window), how many combines your
  spare copies allow per grade, lowest grade first (what climbs feeds the
  next grade), or how many more copies to collect. Waiting gains nothing. Grades in the game's
  colours and names (Epic blue).
  **In your bag**: the gear the meter saw in your inventory whose look you
  lack, with the chance to get it.
- **Inventory's floater**: the count goes to the Inventory plugin (`share`),
  whose Limits can show **Skins 622 / 700** in its floater.

## How it knows

- **Your closet**: the game sends it whole at login (every look you have,
  account-wide) and each new one when it comes. Start the meter before you
  log in.
- **The merchant's stock**: sent when you open a tab of the shop; ten offers
  a tab, each character its own, a new stock every full hour. The layout is
  Pet Finder's (PetTracker's).
- **Which skin fills which closet entry**: the skin's icon names the look's
  number (`WP_ST_0015` → weapons, look 15, staff), as every skin bought so
  far confirms. Sets and costumes whose icon has no number are learnt when
  one is bought.
- **Prices**: the merchant's list price depends only on grade and slot (a
  Epic weapon 960,000, Epic boots 403,200, Rare 2.5 times Common, Epic
  10 times); the discount is 10, 20, 30 or 50 %.
- **Spare copies**: the closet counts each look's copies (the small number
  on a skin in the game's closet is the copies beyond the first); those are
  what combining uses.
- **Gear looks**: a piece of gear's icon names its look as a skin's does.

## Permissions

`storage` (settings, your closet, the stocks seen), `notify` (a skin you
lack on offer), `widgets` (the Closet window), `share` (the count for the
Inventory), `events:character` (whose stock it is), `events:world` (walking off closes the windows), `events:items` (which
skin was just bought, for the looks it learns, and the gear in your bag), `web:assets.playnccdn.com`
(the skins' pictures from the game's icon server),
`web:raw.githubusercontent.com` (the hourly price list, this build's copy
of aion2.exchange's prices on the app repo's branch `market-data`, read
only), and one `decoder:` per game message it reads. Nothing is sent
anywhere.

## Data

Skin names, grades and icons: the Inventory plugin's item list, from AION 2's
client via SkeeveAN's Aion-DPS-Meter (MIT) and Aion2Data
(`dev/make_data.py`). AION 2 names and game data belong to NCSOFT. Exchange
prices: aion2.exchange, as this build copies them every hour.

## Tests

`bash dev/ci.sh <meter source>`: the decoders through the meter's own
`decoder.rs` on frames built from the layouts, and the logic.
