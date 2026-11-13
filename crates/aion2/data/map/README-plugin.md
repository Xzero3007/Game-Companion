# Map (A2Tools plugin)

The map you are on, with where you are, and an overlay with a small map that
follows you over the game.

- **Your position**: the arrow points the way you walk (the game sends no
  facing). The game reports your exact place only with an action, an effect
  you put on, or a teleport; what your client tells the server as you walk is
  encrypted, so no tool can read it. In between, the meter takes the middle
  of the monsters and players moving around you (10 to 15 m off). The map
  weighs that against your last exact place by how far each is likely off,
  and moves the arrow there smoothly, no faster than one runs, instead of
  jumping; the ring around it is how far off it may be ("±12 m"). A Kibelisk
  teleport places you exactly at once (patch 0023, the teleport record as
  A2 Tools' Pet Soul Tracker 0.5.0 reads it). The header names the region you
  are in (Safe Haven, Black Claw Village ...) and, while the place is only
  about, how long ago it last was exact ("exact 21 s ago").
- **Which map**: the game names your zone at login and at each teleport or
  zone change. When what is around you clearly belongs to another map than
  the zone heard (3 or more monsters or spots, more than of the zone's map),
  the map goes by what is around you: a zone change the meter missed doesn't
  leave it on the wrong map. Started after that, the meter hasn't heard it yet: the map
  then goes by what is around you (pet monsters, gathering spots, Hidden
  Cubes), else it is the map you were on last time, marked "map as last
  time" (and a "?" in the overlay) until your next teleport.
- **Pets**: whose spawn points show (the selector beside the layers):
  **favourites** (Pet Finder's ★ and the pet you are farming), **not at level
  3** (those and every pet still needing souls, as the Pet Soul Tracker's map
  shows them) or **all**. Your favourites show as a **gold star** and the one
  you are farming as a **target** (white ring and dot); a pet not at level 3
  yet is filled in its **genus colour** (Cogni violet, Fera orange, Natura
  green, Varian cyan, as Pet Finder's list colours them). Pet Finder holds the Pet Soul Tracker's list
  now, so this is one list; while the Pet Soul Tracker still runs too, the map
  goes by Pet Finder's alone. With no pet followed, or with **All pets**,
  every pet's spawn points show: **red in a white ring** while the pet is not
  at level 3 yet, **small and grey** at level 3 (Pet Finder tells which once it
  has read your pet list; before, small and white). Which monster gives which pet's
  souls comes from the game's drop tables (Pet Finder's `sources.js`), so the
  map shows the same monsters as Pet Finder's list and Map button. The pet monsters around
  you right now are the large marks with a white halo, and every one not at
  level 3 yet shows, followed or not. A legend under the map explains them.
  **Under the map**, as the Pet Soul Tracker's map lists them: the nearest
  kinds of monster that drop souls you still need, up to four: name, level,
  how many are in range, which way and how far, the pet and the souls it still
  needs to level 3; with none in range, the nearest spawn points. A click
  shows that monster's spawn points. At the bottom: the next pet to go for,
  which way and how far (hover it for why it is followed), and how many pets
  this map has and how many are around you.
- **Next**: a favourite first (however far), then the one you are farming;
  among those, one that is there right now before a spawn point, then the
  nearest. **Next: off** shows none (a search still has its Next).
- **The game's own symbols** (0.11.0): every mark is drawn with the symbol
  the game's minimap uses for it (Kibelisk, gathering by kind, feather,
  field boss, dungeon entrance, Spacetime Rift, merchant, quest giver ...),
  the chips above the map and the search too; the Hidden Cubes keep their
  purple cube. Names show once zoomed in (merchants, quest givers and
  passages closer still), the most telling first and none over another.
  0.11.1: the symbols 40 % larger, in the chips and the search 20 px.
- **Click a mark** (0.11.0): that thing everywhere on the map, with a gold
  ring each and the way to the nearest (as the search shows it); the map
  stays where it is. A click on one with a gold ring turns it off again. A
  **field boss** (Bodyguard Teegant, Divine Ansas ...) has one place in the
  game, and the bar says so: "... is a field boss: the game has this one
  place for it" (0.11.1).
- **Monsters**: where every monster stands, as the game has them (small and
  grey; its name and level when the pointer is on it; about 17,000 in
  Verteron), and the monsters around you right now. The pet monsters the
  Pets layer shows aren't drawn twice.
- **Gathering**: the gathering spots by kind, each kind on or off (hover a kind
  for what it holds), all of them as the game has them (0.11.0: about 2,700
  in Verteron and in Altgard, 1,400 in Eltnen and in Morheim, 240 Odyle in the
  Abyss; before, the few players' meters had reported); those there right now
  framed white:
  - Herbs: Aria, Targena, Azpha, Calendula
  - Ore: Orichalcum, Silver, Gold, Platinum, Mithril
  - Wood: Yggdrasil, Asvata
  - Fibers (for cloth): Ruko, Fess, Remi, Linon, Lapageria and more
  - Cooking: Mela, Coriolus, Inina, Kukuru and about 30 more
  - Gemstones: Sapphire, Diamond, Ruby, Aquamarine, Topaz and more
  - Odyle: Odyle, Splendent Odyle, Mysterious Odyle

  Each kind says how many spots this map has (0.11.2). Fibers have no chip
  (0.11.3): the game places none of them (the client's object list has
  Ruko, Fess, Remi, Linon, Lapageria, Zoot, Xilix and Anathe with 0 places
  each, Aion 2 Timers has no fiber spots, and none of the game's 1,082
  recipes uses a fiber); the chip comes by itself once your meter sees a
  fiber spot.
- **Hidden Cubes**: purple cubes: the spots where a cube is known to stand
  (pale, about 110 per map), and a cube in range right now (solid with a white
  edge, it shows as soon as the game announces it).
- **Feathers**: the Monolith pieces to collect, the game's feather (560 in
  Verteron and in Altgard, about 200 in the Abyss). SkeeveAN's "Empyrean
  Traces" were the same pieces (541 of Verteron's 559 on one): no longer a
  gathering kind (0.11.0).
- **Kibelisks**: the Kibelisk camps, on every map (0.11.0: Eltnen and
  Morheim 20 each, the Abyss's layers, Poeta, Ishalgen), the light one on the
  Elyos side, the dark one on the Asmodian side, as the game draws them.
- **Places**: the **field bosses**, dungeon entrances, sealed dungeons,
  battlefields, outposts, Spacetime Rifts, flight circles, Monoliths,
  passages, field events, the Abyss's artifacts and corridors, villages, the
  names of the regions and areas.
- **Services** (0.11.0): merchants, storage, the crafting tables and the
  teleport towers, by name.
- **Quests** (0.11.0): who gives the hero and district quests, their quests
  when the pointer is on them; a quest can be searched for by its name.
- **NPCs** (0.11.0): every other NPC, by name.
- **Marks 100% to 175%**: how large the marks are, on the map and the
  overlay (125% to begin with).
- **Which map** (0.11.4): the picker beside Follow is the plugin's own list
  (the desktop drew the old one's chosen entry in its blue), the chosen map
  in gold, in groups: **Where you are**; **In the game** (Verteron, Altgard,
  the Abyss); **Coming later** (Eltnen, Morheim, the Abyss's middle and upper
  layers: in the game's files, not open yet, no pet's souls drop there);
  **Instances**; **Starting areas** (Poeta, Ishalgen). Buttons at its top
  hide the maps to come, the instances and the starting areas (these hidden
  at first), remembered. A map to come moves to In the game for good once
  the zone the meter hears says you are on it. A search and the map links
  show what is on a hidden map all the same.
- **The map's buttons** (0.11.2, its top right corner): **+** and **−**
  zoom; **Fit** puts the whole map in the window; **Results** (while
  something is shown) frames everything searched for or clicked again; **Big
  map** hides the rows of buttons above the map, so the map has their room
  (pressed: gold). A **scale** at the bottom left ("500 m"). A map that
  started in a small box (its tab hidden, the window still small) is fitted
  again when its box grows, until you move or zoom it.
- **Every pet monster's spawn points** (0.10.0): all of them, as the game
  has them (A2 Tools' Pet Soul Tracker's map data, from Aion 2 Timers'
  interactive map): 458 of the 465 pet monsters with exactly the number of
  spawn points the game's own tables give (Harsh Pino Worker 22, Hill
  Coradon 91; SkeeveAN's data, used before, had none and 9). Every build
  checks each pet monster against the game's count and lists what differs.
- **What your meter sees is learnt**: each gathering spot, Hidden Cube, pet
  monster, feather, Kibelisk and place (dungeon entrance, Spacetime Rift,
  flight circle, Monolith, passage, Abyss artifact ...) your meter sees where
  the map has none of its kind yet (8 m for a spot or a feather, 20 m for a
  monster, 30 m for a Kibelisk or a place), on the map the zone or what is
  around names, is added, kept and shown like the others ("12 spots your
  meter saw" at the bottom): when the game changes or a new area comes, the
  map completes itself as you play.
- **Where the game puts a monster the data lacks** (0.9.0, now a fallback
  for monsters the data doesn't have yet, such as a new area's): the game's
  own tables (Pet Finder's copy of the Pet Soul Tracker's data) know how
  many spawn points each pet monster has on a map, the middle one of them
  and the subzones they lie in. A monster the data lacks has that middle
  spawn point, so it shows, can be searched for and has the way there.
  Shown from a search or a map link while the map knows fewer of its spawn
  points than the game has, the subzones they lie in are outlined in gold
  where the map knows them, and the bar says how many it knows: "The game
  has 22 spawn points here in Aullaeu Village; the map knows 1 (the middle
  one). It adds each one your meter sees."

**Search** (two letters or more): gathering spots by name (Orichalcum, Aria
...), pets, every monster (the pets each drops souls for, its level), field
bosses, NPCs, Kibelisk camps (or all of them), **Hidden Cube** (the known
spots, or every place the game may put one: about 1,400 per map),
**Feathers** (also as "Monolith" or "Empyrean"), every kind of place and
service (each kind, or one by its name: "Alchemy Table", "Merchants"), quest
givers and their quests by name, regions and areas, each with the maps it is
on and how often, and the game's symbol.
Picking one shows all its places with a gold ring, the map framed around them
(the bar above the map switches between its maps), and **the way there**:
from your position, walking, or a teleport to the Kibelisk nearest the place
(gold ring, "Teleport: <name>") and a dashed line from there, whichever is
shorter (a teleport counts as 250 m of walking); to the cheapest of its
places when it has several. **Next** says it, in the overlay too: "teleport
to <Kibelisk>, then 186 m", or which way and how far. A map link in Pet
Finder (its Nearby tab, or Map beside a monster in a pet's sources) does the same for that pet or monster, a world
boss's map button in **Event Timers** for that boss, and a material's map
button in the **Market** for where it is gathered; each brings the Map
forward. It stays, after a restart too, until its **×** stops it: in the bar
above the map, or at the bottom of the overlay ("Showing ...", in gold).

Drag to move the map, the wheel zooms, a double-click goes back to following
you. **Overlay** opens the small map, always on the map you are on: drag it by
its title; **S, M, L, XL** in its title (shown while the pointer is on it) or
**Overlay size** here set its size, or drag one of its corners (the brackets)
for any other, which the window manager does as for any window; the wheel
zooms it; the slider in its title (or **Opacity** here) sets how much of the
game shows through (the marks stay solid). The meter's lock (in its title)
locks the overlay too: locked, clicks go through it to the game; unlocked,
it moves and its buttons work. **1 2 3** in its title are three places of your own: a right-click
on a number keeps where the overlay is and its size there, a click goes back
to it (a kept place's number is gold). With Clicktrough's meter (patch 0035)
a **map button in the meter's title** shows or hides the overlay without the
plugin window; the puzzle button leaves it as it is. The overlay keeps
following you while the Map's tab is closed or the dock hidden (0.12.2),
also when the Map's page was never opened since the meter started (0.12.3).

Your position (0.13.0, with meter patch 0041): standing, your mark stays
exactly where the game last placed you; walking, it moves on at your speed
until the game places you again (about 2 m off in between).

Maps: Verteron, Altgard, the Abyss (its lower, middle and upper layers),
Eltnen, Morheim, Poeta and Ishalgen, whole, as the game draws its world map
(on its parchment, the sea painted), and 25 instances. Eltnen and Morheim at
the game's full size (8192 px, 0.11.0; 2048 before), with their Kibelisks,
gathering spots, Hidden Cube places, places, services and quests.

## How it knows

The meter's `events:world` (Clicktrough patch 0010) reads where you and the
monsters, players and objects around you are from the game's own data, and the
pets to show come from other plugins through `events:shared` (patch 0011);
the Map shares each pet's nearest spawn point on your map back (`share`)
for Pet Finder's **Nearest** sort, with the map's name and the region you
are in (for the Inventory's gathering by place). The monsters' levels come from Pet
Finder's copy of the Pet Soul Tracker's game data (GPL-3.0). The
map pictures come through the meter (`a2.file`, patch 0012): WebKitGTK 2.54
lets a plugin load no file of its own once its page has started. No network.

## Data

`data.js`, `tiles/` and `icons/` are generated from SkeeveAN's
[Aion-DPS-Meter](https://github.com/SkeeveAN/Aion-DPS-Meter) (MIT, see
`NOTICE-SkeeveAN.txt`), the data of the
[AION2 Interactive Map](https://github.com/aion2-interactive-map/aion2-interactive-map)
by Yihao Liu (tc-imba) (CC BY-NC 4.0: non-commercial use only, see
`NOTICE-AION2-Interactive-Map.txt`; the game's minimap symbols as it
publishes them), A2 Tools' Pet Soul Tracker's map data
(`plugins/pet-souls/maps.js` and `maps/` in taengu/A2Tools-Plugins, at the
commit `original/PIN` names), and Aion 2 Timers' interactive map (the game
client's own spawn data, map by map, and its map pictures, see
`NOTICE-Aion2Timers.txt`): first
`python3 -I dev/fetch_aion2timers.py <cache> 1011:5 1111:5 22:3 23:3`
(Aion 2 Timers' data and the pictures of Eltnen, Morheim and the Abyss's
middle and upper layers into a cache folder; plain downloads, one at a
time), then
`python3 -I dev/make_data.py <Aion-DPS-Meter checkout> . --aim <aion2-interactive-map checkout> --game-maps <its gh-pages checkout> --pet-maps <A2Tools-Plugins checkout> --a2t <cache>`
(`--no-tiles` keeps `tiles/`, `--tiles <map,map>` writes only those maps'
tiles); `dev/provenance.json` names the revisions, the calibration and
every file read. Aion 2 Timers' Kibelisks, field bosses, gathering spots,
Hidden Cube places, places, services, quest givers, monsters, NPCs and area
names come in; where the AION2 Interactive Map has a sealed dungeon or
outpost, its own stays. Its pictures of Eltnen and Morheim match the Pet Soul
Tracker's smaller ones to the pixel (correlation 0.998). Its spawn points take the place of SkeeveAN's for every
monster it has: SkeeveAN's reader of the client's map files misses whole
spawn groups. Its pictures give Eltnen, Morheim and the Abyss's middle and
upper layers, checked against SkeeveAN's spawn points and field bosses
(all on land) and, for the middle layer, the AION2 Interactive Map's picture
of it (the same to the pixel). When a new area comes: take the original's
newer map data (`original/PIN`), run the command again with `--tiles` for
the new map, and `dev/tests/coverage.test.cjs` says which pet monsters still
lack spawn points or a map. The field bosses' places are SkeeveAN's
(`bosses/field_bosses.json`), their world-map ids the meter's
(`capture/field_bosses.rs`).

The gathering spots are the game's own (Aion 2 Timers' data, from the
client); what players collected by hand (allthings.how, The Hidden Gaming
Lair) isn't used.
`areas.js` (the fallback above: the count, the middle spawn point and the
subzones from the game's tables) is generated with
`python3 -I dev/make_areas.py` from Pet Finder's `sources.js` (the Pet Soul
Tracker's, A2 Tools, GPL-3.0).

The world maps are the game's own map pictures as the AION2 Interactive Map
publishes them (its `gh-pages` branch, `UI/Map/WorldMap`), the way the map
sites all show them: SkeeveAN's are the same pictures taken as a player had
explored them, so Altgard had dark holes (Black Claw Village, Immortal Isle
and more). Verteron keeps SkeeveAN's sharper picture (twice the pixels) where
it has one. Each picture covers a fixed rectangle of the world (the client's
map bounds, as the map sites use them), one pixel 99.6 cm on every map: that
is the calibration. No stripes where the pictures' tiles meet (0.11.1):
SkeeveAN's Verteron tiles have another place's pixels in their right 8
columns (a pink band in the grass), so the game's picture shows there and
SkeeveAN's is blended in from every tile edge; some of the game's own tiles
(Altgard, Ishalgen, the Abyss, Poeta) have a one-pixel edge line of another
colour, mended; and a tile made larger is resized with its neighbours
around it. The Kibelisks of both sources agree with it (60 and 61
pairs, 6 and 8 m apart on average); 99 % of the spawn points of Verteron and
the Abyss lie on land with it, and the Hidden Cube spots on places the game
may put a cube (7 m apart on average). SkeeveAN's own fit was 2 % too small,
up to 90 m off towards Altgard's edges.

The map pictures are the game's artwork (© NCSOFT); AION 2 names, maps and
game material belong to their respective owners.

Unofficial, not affiliated with NCSOFT or A2Tools. Third-party tools can put a
game account at risk.

The plugin's own code: GPL-3.0-or-later, see `LICENSE`. The monsters' levels
(`npcLevels` in `data.js`) and `areas.js` come from A2 Tools' Pet Soul
Tracker data (GPL-3.0, https://github.com/taengu/A2Tools-Plugins).
