// The PoE 2 session tracker's rules (qml/poe2/sessionkit.js) without Qt:
// node tools/poe2-session-test.js
const fs = require('fs')
const path = require('path')
const assert = require('assert')
const src = fs.readFileSync(path.join(__dirname, '..', 'qml', 'poe2', 'sessionkit.js'), 'utf8')
    .split('\n').filter((l) => !l.startsWith('.pragma')).join('\n')
const K = {}
new Function('K', src + '\nfor (const n of ["kindOf","actOf","nameFromId","newSession","apply","pause","view","cutAt","finish","carryOn","isEmpty","span","clock","MIN","HOUR"]) K[n]=eval(n);')(K)
const { MIN } = K

// Areas by id.
assert.equal(K.kindOf('MapCrypt', 'Crypt'), 'map')
assert.equal(K.kindOf('HideoutFelled', ''), 'hideout')
assert.equal(K.kindOf('', 'Felled Hideout'), 'hideout')
assert.equal(K.kindOf('G1_town', 'Clearfell Encampment'), 'town')
assert.equal(K.kindOf('G2_3', 'Traitor\'s Passage'), 'campaign')
assert.equal(K.kindOf('C_G1_2', ''), 'campaign')
assert.equal(K.kindOf('SanctumFloor1', ''), 'other')
assert.equal(K.actOf('G2_3'), 'Act 2')
assert.equal(K.actOf('C_G1_2'), 'Act 1 (Cruel)')
assert.equal(K.actOf('P1_1'), 'Interlude 1')
assert.equal(K.nameFromId('MapLostTowers'), 'Lost Towers')

const t0 = new Date(2026, 10, 15, 18, 0, 0).getTime()
const at = (m) => t0 + m * MIN
let s = K.newSession(t0)
assert.ok(K.isEmpty(s))
const area = (m, id, name, seed, level) => K.apply(s, { k: 'area', t: at(m), id, name: name || '', seed: seed || '', level: level || 0 })

area(0, 'HideoutFelled', '', '1')
K.apply(s, { k: 'named', t: at(0), name: 'Felled Hideout' })
area(2, 'MapCrypt', '', '777', 79)
K.apply(s, { k: 'named', t: at(2), name: 'Crypt' })
K.apply(s, { k: 'death', t: at(5) })
area(6, 'HideoutFelled', 'Felled Hideout', '2')
// Back through the portal: the same map.
area(7, 'MapCrypt', 'Crypt', '777', 79)
area(9, 'HideoutFelled', 'Felled Hideout', '3')
area(10, 'MapBluff', 'Bluff', '888', 80)
K.apply(s, { k: 'level', t: at(12), char: 'Kael', class: 'Mercenary', level: 81 })
area(14, 'HideoutFelled', 'Felled Hideout', '4')

let v = K.view(s, at(16))
assert.equal(v.mapCount, 2)
assert.equal(v.maps[0].name, 'Crypt')
assert.equal(v.maps[0].time, 6 * MIN)
assert.equal(v.maps[0].deaths, 1)
assert.equal(v.maps[1].time, 4 * MIN)
assert.equal(v.time.map, 10 * MIN)
assert.equal(v.time.hideout, 6 * MIN) // 2 + 1 + 1 + 2 (up to now)
assert.equal(v.played, 16 * MIN)
assert.equal(v.deaths, 1)
assert.deepEqual([v.char.from, v.char.to], [80, 81])
assert.equal(v.avgMap, 5 * MIN)
assert.ok(Math.abs(v.mapsPerHour - 7.5) < 1e-9)
assert.equal(v.current, null)

// AFK stops the clock.
K.apply(s, { k: 'afk', t: at(16), on: true })
v = K.view(s, at(40))
assert.equal(v.played, 16 * MIN)
assert.ok(v.idle)
// A break of 30 minutes ends the session; 20 do not.
assert.equal(K.cutAt(s, at(36), 30 * MIN), null)
assert.equal(K.cutAt(s, at(47), 30 * MIN), at(16))
assert.equal(K.cutAt(s, at(47), 60 * MIN), null)
K.apply(s, { k: 'afk', t: at(30), on: false })
v = K.view(s, at(32))
assert.equal(v.played, 18 * MIN)

// The game ends: paused; the old session goes to the list.
K.pause(s, at(33))
assert.equal(K.view(s, at(50)).played, 19 * MIN)
const done = K.finish(s, at(33))
assert.equal(done.end, at(33))
assert.equal(done.area, undefined)

// A new day starts a new session, still in the same map.
s = K.newSession(at(0))
const late = new Date(2026, 10, 15, 23, 50).getTime()
s = K.newSession(late)
K.apply(s, { k: 'area', t: late, id: 'MapCrypt', name: 'Crypt', seed: '5', level: 80 })
const after = new Date(2026, 10, 16, 0, 5).getTime()
const cut = K.cutAt(s, after, 30 * MIN)
assert.equal(cut, new Date(2026, 10, 16).getTime())
const old = K.finish(s, cut)
assert.equal(old.time.map, 10 * MIN)
const fresh = K.carryOn(s, cut)
assert.equal(fresh.maps.length, 1)
assert.equal(K.view(fresh, after).played, 5 * MIN)

assert.equal(K.span(2 * K.HOUR + 5 * MIN), '2h 05m')
assert.equal(K.span(12 * MIN), '12m')
assert.equal(K.clock(372000), '6:12')
console.log('poe2 session: all good')
