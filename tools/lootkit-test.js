// LOOT's rules (qml/aion2/lootkit.js: the Inventory, Closet and Shugo Cards
// plugins' logic) without Qt: node tools/lootkit-test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = (f) => fs.readFileSync(path.join(__dirname, '..', 'qml', 'aion2', f), 'utf8').split('\n').filter((l) => !l.startsWith('.pragma') && !l.startsWith('.import')).join('\n');
const MK = {}; new Function('MK', src('marketkit.js') + '\nMK.G=G; MK.C=C; MK.A=A;')(MK);
const LK = {}; new Function('MK', 'LK', src('lootkit.js') + '\nLK.C=C; LK.F=F; LK.DG=DG; LK.L=L; LK.CD=CD; LK.S=S;')(MK, LK);
const { C, F, DG, L, CD, S } = LK;
const now = Date.UTC(2026, 10, 13, 12, 0);
// Items: the containers and a change.
const ev = { owner: 'A', snapshotAt: now, containers: { '1': [[1, 930100031, 500], [2, 610531001, 3]], '15': [], '2': [[7, 610531001, 40]] }, changes: [], pickups: [] };
const kept = C.apply({}, ev);
assert.equal(kept.inv[610531001], 3);
assert.equal(kept.acc[610531001], 40);
assert.ok(/^c-2004-[0-9a-z]+$/.test(C.charKey(2004, 'Nully')));
// Worth with a price.
const prices = new Map([['610531001', { price: 1000, listings: 4, sold: 2, soldAvg: 900, change: null, last: null }]]);
assert.equal(C.worth(610531001, 3, prices, 10, null).total, 3000);
assert.equal(C.list(kept.inv, prices, {}).sum.total, 3000);
// A session takes a drop.
let s = C.newSession(now);
s = C.addDrops(s, { changes: [[1, now + 1000, '1', 610531001, 2]], pickups: [[1, now + 900, 610531001, 2]] });
assert.equal(s.items[610531001], 2);
assert.equal(s.loot[610531001], 2);
// Farm days.
const day = F.addCounter(F.newDay(now), 50000, now, 1, 'Field');
assert.equal(F.dayOf(now), day.day);
assert.ok(F.summary(day));
// Dungeons: a run in a dungeon of the table.
const zone = Number(Object.keys(DG.RATES)[0]);
let r = DG.enter([], zone, now);
r = DG.spend(r, zone, 80, now + 1000);
assert.equal(DG.summarize(r, now + 2000)[0].total.boxes, 2);
// Closet: a list, a stock of the shop.
const ix = L.index(CD);
const look = Array.from(ix.looks.keys())[0];
const closet = L.closetFrom({ looks: [{ id: look, value: 1 }] });
assert.equal(closet.size, 1);
assert.equal(L.missing(closet, ix).length, ix.looks.size - 1);
const skin = Array.from(ix.items.values()).find((x) => x.look === look);
assert.equal(L.statusOf(skin.item, closet, ix, {}).status, 'owned');
// A shop frame: offer u32, item u32, left u64, discount u8, currency, list u64, price u64, then the refresh.
const hex = (n, bytes) => { let o = ''; let v = BigInt(n); for (let i = 0; i < bytes; i++) { o += Number(v & 0xffn).toString(16).padStart(2, '0'); v >>= 8n; } return o; };
const body = hex(7, 4) + hex(skin.item, 4) + hex(1, 8) + hex(1, 1) + hex(0x5d, 1) + hex(100000, 8) + hex(80000, 8) + hex(now + 1800000, 8);
const stock = L.stockFromShop({ tab: 104, count: 1, body }, now);
assert.equal(stock.tabName, 'Pets');
assert.equal(stock.offers[0].price, 80000);
// Cards: stats over no rounds, the kinds.
assert.equal(S.stats([], prices, null).rounds, 0);
assert.equal(S.kindOf({ event: 22020112, at: now }).kind, 'di');
console.log('lootkit: all good');
