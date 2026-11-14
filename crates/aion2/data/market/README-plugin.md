# Market (A2Tools plugin)

What the gathered materials bring on your server's market, what they cost
made from Odyle, what every recipe costs and brings, and where each material
goes.

- **Gatherables**: Odyle, ore, gemstones, logs, herbs and cooking ingredients
  in every grade: the lowest listing, how many are listed, how many sold in the
  last 28 days and at what average, and the change.
- **Odyle morph**: Substance Morph turns one Odyle into one gathered material of
  the same grade (Odyle → base, Fine → Fine / Fresh, Pure → Pure, Radiant →
  Radiant), always. For each of the 42 materials: its market price against
  the Odyle's, and what morphing one saves (or "buy" when the market is
  cheaper). What morphing makes is **bound**: it goes into your own crafting,
  not onto the market; the way to sell it is to craft something with it (see
  Recipes). Also what Odyle Energy (Bound), +40, costs through Substance
  Morph (25 Odyle, 5 Fine Odyle, 1 Pure Odyle and 50,000 Kina).
- **Recipes**: your faction's recipes (from the server picked), by profession,
  with a search over products and materials: what the product sells for (its
  lowest listing × how many, less the market's fee, 10 % unless changed), what
  the materials cost bought on the market, what they cost with Odyle morphed
  where that is cheaper, and the profit. A click shows each material, how
  many, its price on the market and the best price (morph or NPC marked), and
  the total; and the combo chance with what it adds. One craft that succeeds:
  failures and combos are not counted. The bound tools the NPC shops sell
  (catalysts, solvents, inks ...) count at their NPC prices, which can be
  changed at the bottom.
- **All listings**: everything listed on your server's market (about 580
  items on Marchutan), each with its picture, name in its grade's colour,
  grade and kind, the lowest listing, how many are listed, its **usual
  price** and the change; a search, the kinds (weapons, armour,
  accessories, skins and wings, artwork, consumables, materials, other), a
  lowest grade, a sort (name, price, listed, change, × usual) and listed
  now only. A click shows the item's course: its lowest listing over the
  last 48 hours and the last 30 days, the usual price as a dashed line.
- **Anomalies**: the lowest listings far from the usual price, each with
  why in words. **Far above** (5 × or more, and at least 50,000 apart):
  most often a single listing at a fantasy price left after the cheap ones
  sold (the Destruction Cloak at 10,000,123 on 10 Nov, usually about
  65,000). **Far below** (40 % or less): a bargain. **Coded** prices are
  pointed out: a round sum with a few odd digits (10,000,123; 20,000,003),
  as sellers use to mark a listing meant for one buyer (handing over Kinah
  bought for real money is one reason; a placeholder or moving Kinah to
  one's own other character are others; only the lowest listing is known,
  not whether anyone buys at it). The sign (×153, 30 %) also stands beside
  the item's name in the other tabs.
- **Usual price**: the median of the item's lowest listing over its last
  days (at least 3, today not counted), until then over its last hours (at
  least 6), else the average sale, else the lowest listing an hour before
  (aion2.exchange's change). The course comes with the hourly copy (below):
  `history/<server>.json` keeps every item's lowest listing for 48 hours
  and the median of each day for 30 days. `anomaly.js` decides; the
  Inventory plugin has the same file and counts an item far above its usual
  price at the usual price.
- **Materials**: every material your faction's recipes use, with its price
  and in how many recipes; a click lists those recipes with how many each
  needs, what that many cost, and what the product sells for. Filter by
  gathered materials, crafted materials, NPC tools or earlier tiers.

In every tab:

- **Each item's picture** before its name (0.4.2), the game's icon through
  the meter.

- **Asmodian / Elyos** beside Update (remembered; your server's side until
  picked): only that side's materials and recipes (Asvata, Azpha ... are
  Asmodian; Yggdrasil, Aria ... Elyos; Odyle and ore both).
- **One column layout** for a whole list, its header kept at the top while
  the list scrolls; the sales columns only while aion2.exchange has sales.
- **A star** before a name makes the item a favourite, in every tab. The
  favourites are **pinned at the top** of every tab (0.4.1): a copy of
  their rows that stays while the list under it scrolls, with the column
  heads, whatever the search or filter; the item also stays in its place
  in the list. **Favorites** in the bar hides or shows the pinned block.
  The list scrolls in its own box under the heads and the favourites, so
  they are as see-through as the rest of the window (0.4.3).
- **A click** on a material (Gatherables, Odyle morph, Materials) lists the
  recipes that need it, how many and what that many cost.
- **A map button** beside a gathered material (also in a recipe's materials)
  shows where it is gathered in the Map plugin, with the way there (permission
  `share`).

Prices: the server is picked from yours when the meter knows your character,
else from the list. They are [aion2.exchange](https://aion2.exchange)'s
(players' collected market prices, a new snapshot about every hour), read
when the window opens and every 30 minutes while it is open, through the
meter (`a2.web.get`, Clicktrough patch 0016; the plugin's page itself has no
network):

1. first from **Clicktrough's copy** on GitHub: aion2.exchange is slow and
   often briefly down ("database unavailable"), so the fork's workflow
   `market-prices.yml` asks it patiently once an hour (`dev/copy_prices.py`,
   the European servers) and publishes a small file per server on the
   branch `market-data`, which the plugin reads in a moment, and with it the
   course of each item's lowest listing (`history/`);
2. from aion2.exchange itself when the copy lacks your server or is older
   than 3 hours; and the old copy still when that fails.

The line at the top says which ("Clicktrough's copy" or "aion2.exchange")
and what went wrong ("could not connect: ...", "no answer in time", "the
service is down right now"). The last prices are kept for the next start.

## Data

`items.js` (every item's name, grade and icon, for All listings) is the
Inventory plugin's item list: `python3 -I dev/make_items.py
../inventory/data.js .`. The pictures come from the game's icon server
through the meter (`a2.web.image`, assets.playnccdn.com).

`data.js` is generated from SkeeveAN's
[Aion-DPS-Meter](https://github.com/SkeeveAN/Aion-DPS-Meter) (MIT, see
`NOTICE-SkeeveAN.txt`): the recipes and item names of the game client, with
`python3 -I dev/make_data.py <checkout> .`; `dev/provenance.json` names the
revision and every file read. The NPC prices are those MetaBot.GG's crafting
calculator lists from the game files. AION 2 names and game data belong to
their respective owners.

Unofficial, not affiliated with NCSOFT, A2Tools or aion2.exchange.

The plugin's own code: GPL-3.0-or-later, see `LICENSE`.
