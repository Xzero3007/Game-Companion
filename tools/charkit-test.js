// The Characters area's rules (qml/aion2/charkit.js) without Qt: node tools/charkit-test.js
const fs=require('fs');
const src=(f)=>fs.readFileSync(require('path').join(__dirname,'..','qml','aion2')+'/'+f,'utf8').split('\n').filter(l=>!l.startsWith('.pragma')&&!l.startsWith('.import')).join('\n');
const T={}; new Function('T', src('chartickets.js')+'\nT.TICKETS=TICKETS;')(T);
const K={}; new Function('T','K', src('charkit.js')+'\nfor (const n of ["merge","empty","estimate","fullAt","nextRefill","countNow","capFor","content","sumOfChars","ticketNow","nextDaily","nextWeekly","keepSiege","OTHER","CONTENT"]) K[n]=eval(n);')(T,K);
const assert=require('assert');
const now=Date.UTC(2026,10,13,12,0);
const s=K.empty();
assert.equal(K.merge(s,{name:"A"},now),null);
const c={name:"Nully",serverId:2004,class:"Cleric",level:45,combatPower:41210,gearScore:3100,
 odyleEnergy:{basic:600,charged:40},contentCounts:{"4":[12,2],"1":[15,0],"0":[3,5],"80000001":[2,0],"102":[5,0],"10000001":[0,0],"10000002":[0,0],"10000003":[0,0]},
 contentTimes:{"10000001":[7800000,now],"3":[3600000,now]},
 shopLimits:{"1209":[2,now+86400000]},crafts:{"32070001":[9],"32070002":[4]},kinahToday:640000,abyssPoints:[812400,2000000],
 seenAt:{odyleEnergy:now-3600000,contentCounts:{"4":now-3600000}},
 abyss:{observedAt:Math.floor(now/1000),wars:[{event:1001,since:1,until:Math.floor(now/1000)+86400*3}],artifacts:[{id:1001,owner:"asmodian"},{id:1002,owner:"elyos"},{id:1003,owner:"asmodian"}]}};
const key=K.merge(s,c,now);
assert.equal(key,"Nully@2004");
const ch=s.chars[key];
assert.equal(ch.cap,840); assert.equal(ch.energy.at,now-3600000);
assert.deepEqual(ch.counts["4"].v,[12,2]); assert.equal(ch.counts["4"].at, now-3600000);
assert.deepEqual(s.servers["2004"].counts["1"].v,[15,0]);
assert.deepEqual(ch.counts["0"].v,[3,5]);
assert.deepEqual(ch.tickets["102"].v,[5,0]);
assert.equal(ch.times["3"].v,3600000);
assert.equal(ch.counts["kinah:today"].v[0],640000);
assert.equal(ch.counts["abyss:week"].cap,2000000);
assert.equal(ch.counts["craft:32070002"].v[0],4);
assert.equal(s.servers["2004"].counts["craft:32070001"].v[0],9);
assert.equal(ch.counts["shop:1209"].reset,now+86400000);
// corridors: asmodian holds 1001 and 1003; 1001 left, 1003 used -> done 1 of 2
assert.deepEqual(ch.passages,["left","used","used"]);
assert.equal(ch.counts["abyss:corridors"].cap,2); assert.equal(ch.counts["abyss:corridors"].v[0],1);
// estimate
assert.deepEqual(K.estimate({basic:500,charged:0,at:now-7*3600000},now,840),{basic:530,charged:0,gained:30,full:false});
assert.equal(K.fullAt({basic:500,at:now},840),Date.UTC(2026,10,16,7));

// countNow: nightmare seen yesterday 12 -> +2 -> 14
const nm=K.content(4);
assert.deepEqual(K.countNow(nm,{v:[12,0],at:now-86400000},now).left,14);
const kin=K.OTHER[0]; assert.equal(K.countNow(kin,{v:[640000,0],at:now-86400000},now).left,0);
assert.equal(K.ticketNow('102', ch.tickets['102'], now+86400000).stale,true);
// unchanged values keep their time
const before=JSON.stringify(s); K.merge(s,Object.assign({},c,{seenAt:{}}),now+5000);
assert.equal(s.chars[key].counts["1"]===undefined,true);
assert.equal(s.servers["2004"].counts["1"].at, now);
console.log('ok');
