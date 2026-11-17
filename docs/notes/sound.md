# Sound module

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- Sound module (MN, 2026-11-15: "Sonar light" taken in; plan in the
  project folder `sound/` and the doc "Sound-Modul: Bauplan"; MN's logs:
  EasyEffects' 20 filters caused the dropouts, without it none):
  `src/sound.rs`, `src/sound_object.rs` (the `Sound` singleton). Channels
  `sonar_game/chat/media/music` (filter chains, pre-gain + 5 biquads,
  Sonar light's presets), WebRTC echo-cancel in monitor mode when the mic
  chain's echo is on (speakers instead of a headset; its reference
  `gc_aec.reference` listens to the default output's monitor; nothing
  plays through it: in 0.8.60 the channels played through its sink and
  everything heard was distorted on MN's UR22; its block is 1920 frames,
  `node.latency` 1920/48000, and its capture holds the graph at
  `node.force-quantum` 1920: PipeWire's echo-cancel hands its source one
  block per cycle, so 480 blocks in MN's 2048 graph lost three quarters of
  the voice, 0.8.61; bench: `pw-metadata -n settings 0 clock.force-quantum
  2048` reproduces it), mic chain → source `gc_mic` "Game Companion Mikro" (rnnoise
  with its VAD as the voice gate, voice EQ, sc4m compressor if installed;
  takes one input with `stream.dont-remix`; gate default 60 % / 500 ms
  with 100 ms let through before a voice, `GATE_LEAD_MS`; old 85/300
  moved once, `Mic::update_gate`; MN 2026-11-16: opened late, cut words),
  presets with little pre-gain (Sonar light's −5 dB ate its boosts); the
  mic chain is gain (`Mic.gain`, 0 to 30 dB, default 12: MN's UR22 was
  quiet without EasyEffects' auto gain) → rnnoise → mic EQ (`VOICE_BANDS`
  m1–m5, `VOICE_PRESETS`, own ones in `mic_presets`; gain, gate and EQ
  change live, `gate_params`), after rnnoise swh's gate as a level gate
  (`Mic.min_level`, "Floor", default −50 dBFS, −70 off, white mark
  on the meter; MN 0.8.66: a constant floor in Legcord) → Clean up (hp
  80 Hz, 5 Hz when off) → Even out (sc4m, gentle 2:1 above −24 dB, 300 ms
  release, 1:1 when off, default off; MN 2026-11-16: the old 3:1/150 ms in
  Clean up made the voice pump; both always in the chain and switched live)
  → swh's
  fastLookaheadLimiter at −1 dBFS, both its inputs fed (one left open
  crashed the child on the bench) and the graph's `inputs`/`outputs`
  named; echo canceller switches `extra_ns` (WebRTC noise suppression,
  "aquarium" with music, default off) and `auto_level` (WebRTC AGC), stream mix: loopbacks from
  the channels' monitors and the mic into `gc_stream_in`, OBS records the
  source `gc_stream` (a client can't make a null sink: a copy filter chain).
  What other programs pick lives in a second child, the front
  (`front_config`, game-companion-sound-front.conf: `gc_mic` as a copy fed
  by `gc_mic.feed`, and the stream mix), restarted only when the mic or the
  stream mix comes or goes: the chains' end `gc_mic.raw` (a plain output,
  autoconnect off) is linked to it with `pw-link -P` after either starts
  (`link_mic`), so OBS keeps its mic over a restart (MN 2026-11-16: had to
  pick it again after every change; bench: a running recording went on).
  Duck while I talk (`Mic.duck`, `duck_db` −3 to −30, default off / −12):
  every channel ends in a `duck` linear node; a `parec` of `gc_mic` (8 kHz,
  40 ms) on its own thread (`Ducking`: down at once, held 500 ms, up 4 dB
  per 40 ms) sets `duck:Mult` live, only while on (MN's HS7 monitors: the
  echo canceller took MN out while a video or Discord talked).
  The chains run in a `pipewire -c $XDG_RUNTIME_DIR/game-companion-sound.conf`
  child (PR_SET_PDEATHSIG from the `sound` worker thread): nothing in
  ~/.config/pipewire, the system's PipeWire never restarted; virtual nodes
  have priority 0 and a default that became ours is put back. `pactl
  subscribe` → new streams moved (`channel_for`: fixed route, running game
  by comm/environ SteamAppId up the parents, Legcord → chat, players →
  music, rest → media); EQ (`pw-cli set-param` "bN:Gain"), volumes/ChatMix
  (`pactl set-sink-volume`), gate and sends live. Off by default
  (settings `sound`). Check without hardware: PipeWire 1.0 from apt,
  `pipewire &`, `dbus-run-session -- wireplumber &`, `pipewire-pulse &`,
  null sinks as fake devices, then the ignored test
  `write_config_for_bench` (GC_SOUND_CONF, GC_SOUND_MIC) and `pipewire -c`,
  or the app itself with `sound.on` in a scratch settings.json.
  Panel (canvas page "Sound", MIXER variant A; MN 2026-11-16):
  `qml/SoundPanel.qml` (MIXER: volume, preset and EQ in place per channel,
  ChatMix; MIC: input, Input 1/2 = FL/FR, mapped to AUX0/AUX1 on Pro Audio,
  gate, echo, voice, "Record 10 s and play back" = `Sound.hear`; APPS;
  STREAM: sends and the OBS tracks), SOUND always in the bar, a right click
  opens `qml/SoundRow.qml` (quick row under the player row, pinnable,
  id `sound-row`). The mic's meter (`Sound.level`, `Sound.talking`) is a
  `parec` of `gc_mic` (pw-record 1.0 has no raw output) read on its own
  thread, told only on a change, and runs only while the MIC tab or the
  quick row shows (`Main.soundMeter`; kept until the worker runs). MN
  switches Legcord's own noise filter, echo and auto gain off.
  `GC_DEMO=sound[,soundmic|,soundapps|,soundstream|,soundeq][,soundee]`,
  `soundrow`. Sound log (MN, 2026-11-16): `~/.cache/game-companion/sound.log`
  (`log::sound`): each start's settings and the whole config, the child
  pipewire's stderr (log.level 2, 400 lines a run), stream moves, volumes,
  and a snapshot (`sound::snapshot`: clock settings, cards and profiles,
  sinks with volumes, streams, pw-top's quantum/rate/ERR, the child's CPU)
  8 s after a start and on the panel's "Copy sound log" (`Sound.report`,
  then `Sound.logText(700)` to the clipboard). Each EQ change logs what
  was asked and what the filter holds (`pw-cli enum-params`, `held_params`).
  Channel meters in the MIXER (MN, 2026-11-16: "woran ich sehen kann das
  es funktioniert"): a `parec` per channel monitor (8 kHz mono, before the
  EQ), only while the MIXER shows (`Main.soundChannelMeters`,
  `Sound.setChannelMeters`, `Sound.channelLevels` "a,b,c,d"), told only on
  a change. The radio's mpv names itself `game-companion-radio`
  (`--audio-client-name`) and goes on Music. Test signal without hardware: `pactl load-module
  module-pipe-source source_name=pipe_mic file=/tmp/pipe_mic format=s16le
  rate=48000 channels=1` as the mic device and raw samples written to the
  fifo (our router moves every playing stream, also one aimed at a sink).
