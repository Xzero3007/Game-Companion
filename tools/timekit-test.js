// The Schedule's rules (qml/aion2/timekit.js) without Qt: node tools/timekit-test.js
const fs = require('fs')
const path = require('path')
const src = (f) => fs.readFileSync(path.join(__dirname, '..', 'qml', 'aion2', f), 'utf8').split('\n').filter((l) => !l.startsWith('.pragma') && !l.startsWith('.import')).join('\n')
const S = {}
new Function('S', src('schedule.js') + '\nS.EVENTS=EVENTS; S.FIELD_BOSSES=FIELD_BOSSES;')(S)
const K = {}
new Function('S', 'K', src('timekit.js') + '\nfor (const n of ["regionOf","sideOf","offset","moment","wallOf","clock","nextOf","nextRefill","events","takeMap","bosses","learn","linkOf","nextAlert","span","MIN","HOUR"]) K[n]=eval(n);')(S, K)
const assert = require('assert')
const MIN = 60000, HOUR = 3600000

// Regions and sides by the server's number.
assert.equal(K.regionOf(2304), 3); assert.equal(K.sideOf(2304), 'asmodian'); assert.equal(K.sideOf(1101), 'elyos'); assert.equal(K.regionOf(null), 0)

// Daylight saving: Berlin +1 in winter, +2 in summer; the switch at 01:00 UTC.
assert.equal(K.offset(3, Date.UTC(2026, 10, 13, 12)), 60)
assert.equal(K.offset(3, Date.UTC(2026, 6, 1)), 120)
assert.equal(K.offset(3, Date.UTC(2026, 2, 29, 0, 59)), 60)
assert.equal(K.offset(3, Date.UTC(2026, 2, 29, 1, 0)), 120)
assert.equal(K.offset(3, Date.UTC(2026, 9, 25, 1, 0)), 60)
// New York: 8 March 2026 07:00 UTC to 1 November 2026 06:00 UTC.
assert.equal(K.offset(1, Date.UTC(2026, 2, 8, 6, 59)), -300)
assert.equal(K.offset(1, Date.UTC(2026, 2, 8, 7, 0)), -240)
assert.equal(K.offset(1, Date.UTC(2026, 10, 1, 5, 59)), -240)
assert.equal(K.offset(1, Date.UTC(2026, 10, 1, 6, 0)), -300)
assert.equal(K.offset(2, Date.UTC(2026, 6, 1)), -420)
assert.equal(K.offset(5, Date.UTC(2026, 6, 1)), 540)

// 21:00 in Berlin on 13 November 2026 is 20:00 UTC.
assert.equal(K.moment(3, 2026, 10, 13, 21 * 60), Date.UTC(2026, 10, 13, 20))
assert.equal(K.clock(3, Date.UTC(2026, 10, 13, 17, 4)), '18:04')
assert.equal(K.clock(3, Date.UTC(2026, 10, 14, 17, 4), Date.UTC(2026, 10, 13, 17)), 'Sat 18:04')

// Friday 13 November 2026, 17:52 UTC = 18:52 in Berlin.
const now = Date.UTC(2026, 10, 13, 17, 52)
const byId = (rows) => Object.fromEntries(rows.map((r) => [r.id, r]))
const ev = byId(K.events(3, 'asmodian', now))
// Shugo Festival every hour at :00 (7 minutes): next 19:00 Berlin = 18:00 UTC.
assert.equal(ev['festival-asmodian'].start, Date.UTC(2026, 10, 13, 18))
assert.ok(!ev['festival-elyos'], 'the other side is left out')
// Dimensional Invasion at :30 for 13 minutes: 18:30 Berlin runs 17:30-17:43 UTC, so next 19:30 Berlin.
assert.equal(ev['invasion-asmodian'].start, Date.UTC(2026, 10, 13, 18, 30))
// Artifact Siege Thursday and Saturday 21:00: Saturday the 14th, 20:00 UTC.
assert.equal(ev.artifact.start, Date.UTC(2026, 10, 14, 20))
// Resets: 07:00 UTC daily, Wednesday weekly.
assert.equal(ev.daily.start, Date.UTC(2026, 10, 14, 7))
assert.equal(ev.weekly.start, Date.UTC(2026, 10, 18, 7))
// Spacetime Rift every 3 h from 02:00 Berlin: 20:00 Berlin = 19:00 UTC.
assert.equal(ev.rift.start, Date.UTC(2026, 10, 13, 19))
// Energy +15 at 01:00, 04:00 ... UTC: 19:00 UTC.
assert.equal(ev.energy.start, Date.UTC(2026, 10, 13, 19))
// A running event: at 18:33 Berlin the invasion runs.
const running = byId(K.events(3, 'elyos', Date.UTC(2026, 10, 13, 17, 33)))['invasion-elyos']
assert.ok(running.running && running.start === Date.UTC(2026, 10, 13, 17, 30) && running.end === Date.UTC(2026, 10, 13, 17, 43))
// Sorted soonest first; without a server only the resets and energy.
const rows = K.events(3, '', now)
for (let i = 1; i < rows.length; i++) assert.ok(rows[i - 1].start <= rows[i].start)
assert.deepEqual(K.events(0, '', now).map((r) => r.id).sort(), ['daily', 'energy', 'weekly'])

// Field bosses from a map the game told.
const kept = {}
assert.ok(K.takeMap(kept, { map: 1010, seen: now - 6 * MIN, bosses: [
    { id: 101003, up: true, time: now - 21 * MIN }, { id: 101006, up: false, time: now + 12 * MIN },
    { id: 101002, up: false, time: now + 108 * MIN }, { id: 101001, up: false, time: now - 5 * MIN },
    { id: 101004, up: false, time: 0 }, { id: 2001, up: false, time: now + HOUR }] }))
assert.ok(!K.takeMap(kept, { map: 1010, seen: now - 7 * MIN, bosses: [{ id: 101003, up: false, time: now }] }), 'an older reading is not taken')
const b = byId(K.bosses(kept, now))
assert.equal(b['101003'].state, 'up'); assert.equal(b['101003'].name, 'Kernon of the West')
assert.equal(b['101006'].state, 'soon'); assert.equal(b['101002'].state, 'wait')
assert.equal(b['101001'].state, 'due'); assert.equal(b['101004'].state, 'unknown')
assert.ok(!b['2001'], 'a boss without a name is left out')
assert.deepEqual(K.bosses(kept, now).map((r) => r.id), ['101003', '101001', '101006', '101002', '101004'])
assert.equal(byId(K.bosses(kept, now + 3 * HOUR))['101003'].state, 'upOld')

// Alerts: 5 minutes before.
const on = { '101006': true, 'festival-asmodian': true }
const a = K.nextAlert(K.events(3, 'asmodian', now), K.bosses(kept, now), on, 5, false, now)
assert.equal(a.id, 'festival-asmodian'); assert.equal(a.at, Date.UTC(2026, 10, 13, 17, 55))
const a2 = K.nextAlert(K.events(3, 'asmodian', now), K.bosses(kept, now), on, 5, false, a.at)
assert.equal(a2.id, '101006'); assert.equal(a2.at, now + 7 * MIN)
const a3 = K.nextAlert(K.events(3, 'asmodian', now), K.bosses(kept, now), { '101006': true }, 5, true, a2.at)
assert.equal(a3.at, now + 12 * MIN, 'again as it starts')
assert.equal(K.nextAlert([], [], {}, 5, false, now), null)

// Aion 2 Timers: a name is learnt from a matching return, else guessed by its number.
const links = {}
const feed = { at: now, kills: {
    asmo03: { st: 'dead', ns: (now + 108 * MIN) / 1000 + 30, u: (now - 10 * MIN) / 1000 },
    asmo05: { st: 'dead', ns: (now + 50 * MIN) / 1000, u: (now - MIN) / 1000 },
    elyos07: { st: 'up', t: (now - 30 * MIN) / 1000, ra: (now - 30 * MIN) / 1000, u: (now - 2 * MIN) / 1000 },
    abyss02: { st: 'dead', ns: (now + HOUR) / 1000, u: now / 1000 } } }
assert.ok(K.learn(links, kept, feed.kills)); assert.equal(links.asmo03, 101002)
assert.ok(!K.learn(links, kept, feed.kills))
assert.deepEqual(K.linkOf('asmo05', {}), { id: '111005', sure: false })
assert.equal(K.linkOf('abyss02', {}), null)
const fb = byId(K.bosses(kept, now, feed, links))
assert.equal(fb['101002'].src, 'game', 'the game told it later than the site')
assert.equal(fb['111005'].src, 'a2t'); assert.equal(fb['111005'].state, 'wait'); assert.ok(fb['111005'].guessed)
assert.equal(fb['101007'].state, 'up'); assert.equal(fb['101007'].src, 'a2t')

assert.equal(K.span(12 * MIN), '12m'); assert.equal(K.span(108 * MIN), '1h 48m'); assert.equal(K.span(51 * HOUR), '2d 3h')
console.log('timekit: all good')
