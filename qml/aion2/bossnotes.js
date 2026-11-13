.pragma library
// Game Companion: Boss Notes' rules (the Clicktrough Boss Notes plugin's
// logic.js, GPL-3.0), kept as they are so changes can be taken over again;
// only the wrapper and `||=` changed for QML, plus roles (`role` on an
// entry) for dungeon cheat sheets.
//
// Boss Notes' rules, apart from the page so they can be tried without one.
//
// What it hears:
//   combat (meter patch, events:combat)  the monsters fought now: entity, npc,
//                                        name, boss, hp, maxHp, since, lastHit
//   09 38  a cast bar starts: caster, skill        (decoder "cast")
//   02 38  a skill goes off: caster, skill         (decoder "skill")
//   2A 38  a buff lands: entity, instance, abnormal, length (ms)   ("buff-added")
//   2C 38  a buff ends: entity, the first ended buff's instance     ("buff-removed")
// The decoders hear every entity, players too: only the bosses being fought
// are kept, and nothing about players.
//
// A sheet is a boss's notes: general notes and entries. An entry is a phase
// (stays until the next phase) or an alert (shows for a while), started by a
// trigger: the fight's start, the boss's HP at or under a percent, the time
// since the pull, a cast or skill of the boss, a buff landing on it or ending.
// HP and time fire once a fight; a cast, skill or buff each time it comes.

  const FOLLOW_GAP_MS = 25000; // a boss not in the meter's list this long: the fight is over
  const BUFFER_MS = 15000; // a boss's casts kept this long before its fight is known
  const BUFFER_MAX = 400;
  const ALERT_MS = 8000; // an alert's time when the entry gives none
  const MAX_EVENTS = 1500; // a fight's recording
  const SAME_GAP_MS = 900; // the same event of a boss within this: once
  const BUFF_MAX_MS = 10 * 60 * 1000; // a buff longer than this is no countdown

  const TRIGGERS = ["start", "hp", "time", "cast", "skill", "buff", "buffEnd"];

  function norm(s) {
    return String(s || "").toLowerCase().normalize("NFKC").replace(/[\s:：·・'’\-–—]+/g, " ").trim();
  }

  // The game's data (bosses.js, Enhanced Boss Telegraph's): which boss a name
  // or a skill belongs to, and the line the game shows for a cast, skill or buff.
  function index(D) {
    const byName = new Map();
    const bySkill = new Map();
    const lines = new Map(); // "cast:id" | "skill:id" | "buff:id" -> [call]
    if (!D) return { byName, bySkill, lines };
    for (const [key, b] of Object.entries(D.bosses || {})) {
      const t = D.texts[b.n] || {};
      for (const name of Object.values(t)) if (name) byName.set(norm(name), key);
      for (const s of b.s || []) bySkill.set(s, key);
    }
    for (const c of D.calls || []) {
      const kind = c.t === "use" ? "skill" : c.t === "abnormal" ? "buff" : c.t;
      const k = `${kind}:${c.id}`;
      if (!lines.has(k)) lines.set(k, []);
      lines.get(k).push(c);
      if (kind !== "buff" && !bySkill.has(c.id)) bySkill.set(c.id, c.b);
    }
    return { byName, bySkill, lines };
  }

  // The key a fought monster's sheet goes by: the game data's boss, else its NPC code.
  function keyOf(ix, f) {
    return ix.byName.get(norm(f.name)) || `npc-${f.npc}`;
  }

  const pct = (f) => (f && f.hp != null && f.maxHp > 0 ? Math.max(0, Math.min(100, (f.hp / f.maxHp) * 100)) : null);

  // What an entry's trigger is in words, for the editor and the "next" line.
  function describe(when, line) {
    const w = when || {};
    switch (w.type) {
      case "start": return "At the pull";
      case "hp": return `HP at ${w.value} %`;
      case "time": return `${fmtTime((Number(w.value) || 0) * 1000)} into the fight`;
      case "cast": return `Cast ${w.value}${line ? ` (“${line}”)` : ""}`;
      case "skill": return `Skill ${w.value}${line ? ` (“${line}”)` : ""}`;
      case "buff": return `Buff ${w.value} lands${line ? ` (“${line}”)` : ""}`;
      case "buffEnd": return `Buff ${w.value} ends`;
      case "none": return "By hand";
      default: return "Never";
    }
  }
  function fmtTime(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  // Starter sheets: the mechanics Enhanced Boss Telegraph checked by hand
  // (its "act" words) as alerts.
  function starters(D, lang) {
    const out = {};
    if (!D) return out;
    const T = (i) => (i == null ? "" : (D.texts[i] && (D.texts[i][lang] || D.texts[i].en)) || "");
    for (const c of D.calls || []) {
      if (c.act == null) continue;
      const kind = c.t === "use" ? "skill" : c.t === "abnormal" ? "buff" : c.t;
      if (!out[c.b]) out[c.b] = { notes: "", entries: [], starter: true };
      const sheet = out[c.b];
      if (sheet.entries.some((e) => e.when.type === kind && e.when.value === c.id)) continue;
      sheet.entries.push({
        id: `s-${c.k}-${c.id}`,
        kind: "alert",
        name: T(c.act),
        text: c.phase ? `${T(c.phase.label)} until ${T(c.phase.n) || "the buff"} ends (${Math.round(c.phase.ms / 1000)} s).` : "",
        when: { type: kind, value: c.id },
        ms: c.phase ? Math.round(((c.lead || 0) + c.phase.ms) / 500) * 500 : 5000,
      });
    }
    return out;
  }

  function create(D, hooks) {
    const ix = index(D);
    const now = () => hooks.now();
    const sheetOf = (key) => hooks.sheet(key) || null;
    const fights = new Map(); // entity -> fight
    const buffer = []; // [entity, at, type, id, extra] before a fight knows the entity
    const instances = new Map(); // "entity:instance" -> { abnormal, at }
    let last = null; // the fight shown: the last of the boss list's first

    function follows(f) {
      if (f.boss) return true;
      const s = sheetOf(keyOf(ix, f));
      return !!(s && s.entries && s.entries.length);
    }

    function lineOf(type, id, lang) {
      const c = (ix.lines.get(`${type}:${id}`) || [])[0];
      if (!c || c.line == null) return "";
      const t = D.texts[c.line];
      return (t && (t[lang] || t.en)) || "";
    }

    function start(f, at) {
      const key = keyOf(ix, f);
      const since = Number.isFinite(f.since) && f.since > 0 ? Math.min(f.since, at) : at;
      const fight = {
        entity: f.entity,
        npc: f.npc,
        key,
        name: f.name || key,
        start: since,
        seen: at,
        hp: pct(f),
        events: [],
        fired: new Set(),
        current: null,
        alerts: [],
        lastSame: new Map(),
        hpMark: null,
        low: pct(f),
      };
      fights.set(f.entity, fight);
      // What the boss did before its first hit (an opening cast).
      for (let i = 0; i < buffer.length; i++) {
        const b = buffer[i];
        if (b[0] === f.entity && b[1] >= since - BUFFER_MS) apply(fight, b[2], b[3], b[4], b[1]);
      }
      for (let i = buffer.length - 1; i >= 0; i--) if (buffer[i][0] === f.entity) buffer.splice(i, 1);
      fire(fight, (e) => e.when.type === "start", since);
      checkLevels(fight, at);
      hooks.changed && hooks.changed();
      return fight;
    }

    function end(fight, at) {
      fights.delete(fight.entity);
      for (const k of [...instances.keys()]) if (k.startsWith(`${fight.entity}:`)) instances.delete(k);
      const record = {
        id: `${fight.start}-${fight.entity}`,
        key: fight.key,
        name: fight.name,
        npc: fight.npc,
        start: fight.start,
        end: Math.max(fight.seen, fight.start),
        hp: fight.hp,
        low: fight.low,
        events: fight.events,
      };
      if (last === fight) last = null;
      hooks.done && hooks.done(record);
      hooks.changed && hooks.changed();
      void at;
    }

    // The meter's list of the monsters fought now.
    function combat(ev) {
      const at = Number.isFinite(ev && ev.at) ? ev.at : now();
      const list = Array.isArray(ev && ev.fought) ? ev.fought : [];
      let first = null;
      for (const f of list) {
        if (!f || !Number.isFinite(f.entity) || !follows(f)) continue;
        let fight = fights.get(f.entity);
        if (!fight) fight = start(f, at);
        fight.seen = at;
        if (f.name) fight.name = f.name;
        const p = pct(f);
        if (p != null) {
          fight.hp = p;
          fight.low = fight.low == null ? p : Math.min(fight.low, p);
          const mark = Math.floor(p);
          if (mark !== fight.hpMark) {
            fight.hpMark = mark;
            record(fight, at, "h", mark, 0);
          }
        }
        checkLevels(fight, at);
        if (!first) first = fight;
      }
      for (const fight of [...fights.values()]) {
        const gone = !list.some((f) => f && f.entity === fight.entity);
        if (gone && (at - fight.seen > FOLLOW_GAP_MS || list.length === 0 || (fight.hp != null && fight.hp <= 0.5))) end(fight, at);
      }
      if (first) last = first;
      tick(at);
      hooks.changed && hooks.changed();
    }

    // The fight's HP and time triggers.
    function checkLevels(fight, at) {
      const p = fight.hp;
      fire(fight, (e) => e.when.type === "hp" && p != null && p <= Number(e.when.value), at, true);
      const t = (at - fight.start) / 1000;
      fire(fight, (e) => e.when.type === "time" && t >= Number(e.when.value), at, true);
    }

    function fire(fight, match, at, once, extra) {
      const sheet = sheetOf(fight.key);
      const entries = (sheet && sheet.entries) || [];
      for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        if (!e || !e.when || !match(e)) continue;
        if (once && fight.fired.has(e.id)) continue;
        fight.fired.add(e.id);
        if (e.kind === "alert") {
          let ms = Number(e.ms) > 0 ? Number(e.ms) : 0;
          if (!ms && e.when.type === "buff" && extra && extra.length > 0 && extra.length <= BUFF_MAX_MS) ms = extra.length;
          if (!ms) ms = ALERT_MS;
          fight.alerts = fight.alerts.filter((a) => a.id !== e.id);
          fight.alerts.push({ id: e.id, until: at + ms, ms, instance: extra && extra.instance, buff: e.when.type === "buff" ? e.when.value : null });
        } else {
          fight.current = { id: e.id, at };
        }
      }
    }

    function record(fight, at, type, id, extra) {
      if (type !== "h") {
        const k = `${type}:${id}`;
        const before = fight.lastSame.get(k);
        if (before != null && at - before < SAME_GAP_MS) return false;
        fight.lastSame.set(k, at);
      }
      if (fight.events.length < MAX_EVENTS) fight.events.push([Math.max(0, Math.round(at - fight.start)), type, id, extra || 0]);
      return true;
    }

    // A boss's own doing: kept, and its triggers fired.
    function apply(fight, type, id, extra, at) {
      if (type === "c" || type === "s") {
        if (!record(fight, at, type, id, 0)) return;
        fire(fight, (e) => e.when.type === (type === "c" ? "cast" : "skill") && Number(e.when.value) === id, at, false);
      } else if (type === "b") {
        if (!record(fight, at, type, id, extra.length > 0 ? Math.min(extra.length, 2147483647) : 0)) return;
        fire(fight, (e) => e.when.type === "buff" && Number(e.when.value) === id, at, false, extra);
      } else if (type === "e") {
        record(fight, at, type, id, 0);
        fire(fight, (e) => e.when.type === "buffEnd" && Number(e.when.value) === id, at, false);
        // An alert started by this buff ends with it.
        fight.alerts = fight.alerts.filter((a) => !(a.buff === id));
      }
    }

    function hear(entity, type, id, extra, at) {
      if (!Number.isFinite(entity) || !Number.isFinite(id)) return;
      const fight = fights.get(entity);
      if (fight) {
        apply(fight, type, id, extra || {}, at);
        hooks.changed && hooks.changed();
        return;
      }
      // Not (yet) a boss being fought: kept a moment, in case its fight is
      // about to be known, and only when the skill is a boss's.
      if ((type === "c" || type === "s") && !ix.bySkill.has(id) && !anySheetHas(type, id)) return;
      buffer.push([entity, at, type, id, extra || {}]);
      while (buffer.length > BUFFER_MAX || (buffer.length && at - buffer[0][1] > BUFFER_MS)) buffer.shift();
    }
    function anySheetHas(type, id) {
      const want = type === "c" ? "cast" : "skill";
      return (hooks.allEntries ? hooks.allEntries() : []).some((e) => e.when && e.when.type === want && Number(e.when.value) === id);
    }

    function cast(d, at) { hear(d.caster, "c", d.skill, null, at); }
    function skill(d, at) { hear(d.caster, "s", d.skill, null, at); }
    function added(d, at) {
      if (!Number.isFinite(d.entity) || !Number.isFinite(d.abnormal)) return;
      const length = Number(d.length);
      instances.set(`${d.entity}:${d.instance}`, { abnormal: d.abnormal, at });
      if (instances.size > 2000) instances.delete(instances.keys().next().value);
      // Only bosses' buffs: a player's are dropped at once.
      if (!fights.has(d.entity) && !buffer.some((b) => b[0] === d.entity)) return;
      hear(d.entity, "b", d.abnormal, { length: Number.isFinite(length) ? length : 0, instance: d.instance }, at);
    }
    function removed(d, at) {
      const k = `${d.entity}:${d.instance}`;
      const was = instances.get(k);
      instances.delete(k);
      if (!was || !fights.has(d.entity)) return;
      hear(d.entity, "e", was.abnormal, null, at);
    }

    function tick(at) {
      for (const fight of fights.values()) {
        fight.alerts = fight.alerts.filter((a) => a.until > at);
        checkLevels(fight, at);
      }
    }

    // What the window and the overlay show.
    function state(lang) {
      const at = now();
      tick(at);
      let fight = last && fights.has(last.entity) ? last : null;
      if (!fight) for (const f of fights.values()) if (!fight || f.seen > fight.seen) fight = f;
      if (!fight) return { fight: null, others: 0 };
      const sheet = sheetOf(fight.key) || { notes: "", entries: [] };
      const entries = sheet.entries || [];
      const byId = (id) => entries.find((e) => e.id === id);
      const phases = entries.filter((e) => e.kind !== "alert");
      const cur = fight.current ? byId(fight.current.id) : null;
      // The next phase: the first after the current one in the list not yet
      // fired (HP and time once), else none.
      let next = null;
      const from = cur ? phases.indexOf(cur) + 1 : 0;
      for (let i = from; i < phases.length; i++) {
        const e = phases[i];
        if (e.when.type === "start") continue;
        if ((e.when.type === "hp" || e.when.type === "time") && fight.fired.has(e.id)) continue;
        next = e;
        break;
      }
      const line = (e) => (e ? lineOf(e.when.type, e.when.value, lang) : "");
      return {
        fight: {
          key: fight.key,
          name: fight.name,
          npc: fight.npc,
          hp: fight.hp,
          elapsed: at - fight.start,
          recording: fight.events.length,
        },
        notes: sheet.notes || "",
        hasSheet: !!(entries.length || sheet.notes),
        hasPhases: phases.length > 0,
        phase: cur ? { id: cur.id, name: cur.name, text: cur.text || "", since: at - fight.current.at } : null,
        next: next ? { id: next.id, name: next.name, when: describe(next.when, line(next)) } : null,
        alerts: fight.alerts
          .map((a) => {
            const e = byId(a.id);
            return e ? { id: a.id, name: e.name, text: e.text || "", left: Math.max(0, a.until - at), ms: a.ms } : null;
          })
          .filter(Boolean),
        others: fights.size - 1,
        // Game Companion: the whole sheet, for a cheat sheet (each entry's
        // trigger in words, whether it came in this fight).
        list: entries.map((e) => ({ id: e.id, kind: e.kind, name: e.name, text: e.text || "", role: e.role || "",
          when: describe(e.when, line(e)), fired: fight.fired.has(e.id) })),
      };
    }

    function clear() {
      for (const fight of [...fights.values()]) end(fight, now());
      buffer.length = 0;
      instances.clear();
    }

    return { combat, cast, skill, added, removed, state, clear, tick, lineOf, fights };
  }

  // A recorded fight summed up: each cast, skill and buff once, with how often,
  // when first and the boss's HP then; the HP's course by tens.
  function summary(record, D, lang) {
    const ix = index(D);
    const groups = new Map();
    let hp = null;
    const marks = [];
    let lastTen = null;
    for (const [t, type, id, extra] of record.events || []) {
      if (type === "h") {
        hp = id;
        const ten = Math.floor(id / 10) * 10;
        if (ten !== lastTen) {
          if (lastTen != null) marks.push({ t, hp: id });
          lastTen = ten;
        }
        continue;
      }
      const kind = type === "c" ? "cast" : type === "s" ? "skill" : type === "b" ? "buff" : "buffEnd";
      const k = `${kind}:${id}`;
      let g = groups.get(k);
      if (!g) {
        const c = (ix.lines.get(`${kind === "buffEnd" ? "buff" : kind}:${id}`) || [])[0];
        const line = c && c.line != null ? (D.texts[c.line] && (D.texts[c.line][lang] || D.texts[c.line].en)) || "" : "";
        g = { kind, id, count: 0, first: t, firstHp: hp, times: [], line, length: 0 };
        groups.set(k, g);
      }
      g.count++;
      if (g.times.length < 40) g.times.push(t);
      if (type === "b" && extra > 0) g.length = extra;
    }
    const list = [...groups.values()].sort((a, b) => a.first - b.first);
    return { list, marks, duration: record.end - record.start };
  }

