// Game Companion voice overlay: the part in the Discord page.
//
// Reads who is in your voice channel and who talks from Discord's own
// stores, found by their names through Legcord's built-in Shelter (no
// webpack numbers, no CSS classes, nothing read from the page), and tells
// Legcord's main process (main.mjs), which hands it to Game Companion.
// It reads only: nothing is changed in Discord and nothing is sent to it.
const PLUGIN = 1;
const TAG = "\u0001gcvoice ";
const NEEDED = {
  SelectedChannelStore: ["getVoiceChannelId"],
  VoiceStateStore: ["getVoiceStatesForChannel"],
  SpeakingStore: ["isSpeaking"],
  UserStore: ["getUser", "getCurrentUser"],
  ChannelStore: ["getChannel"],
};
const OPTIONAL = { GuildMemberStore: ["getNick"] };

module.exports = {
  activate(api) {
    const log = console.log.bind(console);
    const send = (obj) => {
      const s = JSON.stringify(obj);
      if (typeof window.gcVoice === "function") window.gcVoice(s);
      else log(TAG + s);
    };
    let tries = 0;
    const wait = () => {
      const sh = window.shelter;
      if (sh && sh.flux && sh.flux.storesFlat) return start(sh);
      // Shelter loads a moment after the page: a short wait, then give up.
      if (++tries > 120) return send({ t: "check", plugin: PLUGIN, ok: false, missing: ["shelter"] });
      setTimeout(wait, 500);
    };

    async function start(sh) {
      const flux = sh.flux;
      const stores = {};
      const missing = [];
      const pick = async (name, methods, optional) => {
        let s = null;
        try {
          s = flux.storesFlat[name] || null;
          if (!s && flux.awaitStore) s = await Promise.race([flux.awaitStore(name, false), new Promise((r) => setTimeout(() => r(null), 30000))]);
        } catch (e) { s = null; }
        const ok = s && methods.every((m) => typeof s[m] === "function");
        if (ok) stores[name] = s;
        else if (!optional) missing.push(name + (s ? "." + methods.filter((m) => typeof s[m] !== "function").join(",") : ""));
      };
      for (const [n, m] of Object.entries(NEEDED)) await pick(n, m, false);
      for (const [n, m] of Object.entries(OPTIONAL)) await pick(n, m, true);
      send({ t: "check", plugin: PLUGIN, ok: missing.length === 0, missing });
      if (missing.length) return;

      const joined = new Map(); // userId -> first seen (join order)
      let lastText = "";
      let pending = null;
      const name = (u, guild) => {
        let nick = "";
        try { if (guild && stores.GuildMemberStore) nick = stores.GuildMemberStore.getNick(guild, u.id) || ""; } catch (e) {}
        return nick || u.globalName || u.global_name || u.username || "?";
      };
      const compute = () => {
        pending = null;
        let out = { t: "state", plugin: PLUGIN, channel: null, me: "", members: [] };
        try {
          const me = stores.UserStore.getCurrentUser();
          out.me = me ? String(me.id) : "";
          const chId = stores.SelectedChannelStore.getVoiceChannelId();
          if (chId) {
            const ch = stores.ChannelStore.getChannel(chId);
            const guild = ch ? ch.guild_id || ch.guildId || "" : "";
            out.channel = { id: String(chId), name: ch ? ch.name || "" : "", guild: String(guild || "") };
            const states = stores.VoiceStateStore.getVoiceStatesForChannel(chId) || {};
            const now = Date.now();
            const here = new Set();
            for (const [id, v] of Object.entries(states)) {
              const uid = String((v && (v.userId || v.user_id)) || id);
              here.add(uid);
              if (!joined.has(uid)) joined.set(uid, now);
              const u = stores.UserStore.getUser(uid) || { id: uid };
              out.members.push({
                id: uid,
                name: name(u, guild),
                avatar: u.avatar || "",
                speaking: !!stores.SpeakingStore.isSpeaking(uid),
                muted: !!(v && (v.selfMute || v.mute || v.suppress)),
                deafened: !!(v && (v.selfDeaf || v.deaf)),
                joined: joined.get(uid),
              });
            }
            for (const id of [...joined.keys()]) if (!here.has(id)) joined.delete(id);
          } else joined.clear();
        } catch (e) {
          out = { t: "check", plugin: PLUGIN, ok: false, missing: ["read: " + String(e && e.message || e).slice(0, 80)] };
        }
        const text = JSON.stringify(out);
        if (text !== lastText) { lastText = text; send(out); }
      };
      // Changes come in bursts: one look after a moment, no timer otherwise.
      const soon = () => { if (!pending) pending = setTimeout(compute, 40); };
      for (const n of ["SelectedChannelStore", "VoiceStateStore", "SpeakingStore"]) {
        try { stores[n].addChangeListener(soon); } catch (e) {}
      }
      try {
        const d = await flux.getDispatcher?.() || flux.dispatcher;
        for (const ev of ["SPEAKING", "VOICE_STATE_UPDATES", "VOICE_CHANNEL_SELECT", "CONNECTION_OPEN"]) d.subscribe(ev, soon);
      } catch (e) {}
      // Game Companion (re)connected: main.mjs sends the last state itself.
      compute();
    }
    wait();
  },
};
