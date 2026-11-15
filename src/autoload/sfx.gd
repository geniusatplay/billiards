extends Node
## Audio manager, autoloaded as `Sfx`.
##
## Table sounds (ball-ball, cushion, cue tip, pocket, cloth) go through impact(): the sample is picked
## from an intensity tier that matches the impact speed, with round-robin variations, a loudness curve,
## slight pitch scatter and playback at the 3D point of impact, so the sound comes from where the balls
## are (and moves as you walk around the table in AR). A quiet rolling loop follows the moving balls.
## UI sounds and jingles use play().
##
## The samples are listed in SfxBank (written by tools/build_sounds.py from the recordings in
## assets/audio/table/). When that bank is empty the older synthesized sounds are used instead.

const NAMES := ["ball_click_1", "ball_click_2", "ball_click_3", "cushion", "pocket", "cue_strike",
	"ui_tap", "ui_back", "ui_toggle", "turn_chime", "tick", "warning", "win", "lose", "foul", "rack",
	"bounce"]
const VOICES := 8          # 2D one-shots (UI, jingles)
const VOICES_3D := 22      # table impacts

## How each kind of impact maps speed (m/s) to loudness, and how often it may retrigger.
##   v_min   below this the impact is silent          v_ref   speed that plays at full level
##   floor   level (dB) of the quietest audible hit   pitch   random pitch scatter (+-)
##   gap_ms / burst   at most `burst` hits start inside any `gap_ms` window (a break is 15 contacts in
##                    a few milliseconds: the loudest few make the crack, the rest would only be mud)
const KIND := {
	"ball":    {"v_min": 0.03, "v_ref": 5.5, "floor": -30.0, "pitch": 0.035, "gap_ms": 14, "burst": 5, "curve": 0.42},
	"cushion": {"v_min": 0.06, "v_ref": 4.5, "floor": -27.0, "pitch": 0.045, "gap_ms": 22, "burst": 2, "curve": 0.5},
	"cue":     {"v_min": 0.0, "v_ref": 8.0, "floor": -17.0, "pitch": 0.02, "gap_ms": 80, "burst": 1, "curve": 0.6},
	"bed":     {"v_min": 0.45, "v_ref": 3.0, "floor": -22.0, "pitch": 0.06, "gap_ms": 30, "burst": 1, "curve": 0.6},
	"pocket":  {"v_min": 0.0, "v_ref": 3.5, "floor": -9.0, "pitch": 0.04, "gap_ms": 40, "burst": 2, "curve": 0.7},
	"pocket_roll": {"v_min": 0.0, "v_ref": 1.0, "floor": -8.0, "pitch": 0.05, "gap_ms": 120, "burst": 2, "curve": 1.0},
}
## Older single-sample sounds used when the recorded bank has nothing for a kind.
const LEGACY := {"ball": ["ball_click_1", "ball_click_2", "ball_click_3"], "cushion": ["cushion"],
	"cue": ["cue_strike"], "bed": ["bounce"], "pocket": ["pocket"], "pocket_roll": []}

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _voices3d: Array[AudioStreamPlayer3D] = []
var _next3d := 0
var _music: AudioStreamPlayer
var _roll: AudioStreamPlayer3D
var _roll_level := 0.0
var _roll_target := 0.0
var _sfx_bus := 0
var _music_bus := 0
var _last_play: Dictionary = {}
var _bank: Dictionary = {}        # kind -> Array of {"v": centre speed, "streams": Array[AudioStream]}
var _last_pick: Dictionary = {}   # "kind:tier" -> last variation index
var _last_hit: Dictionary = {}    # kind -> [window start (physics tick), hits started in it]
var _scale := -1.0
var _rng := RandomNumberGenerator.new()
## Test hook: every impact() that actually played, as {kind, tier, sample, db, pitch, pos, speed}.
var log_hits := false
var hits: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_sfx_bus = _ensure_bus("SFX")
	_music_bus = _ensure_bus("Music")
	_ensure_table_bus()
	for n in NAMES:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	_load_bank()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	for i in VOICES_3D:
		_voices3d.append(_make_3d())
	_roll = _make_3d()
	var rp := "res://assets/audio/table/roll_loop.wav"
	if ResourceLoader.exists(rp):
		var rs = load(rp)
		if rs is AudioStreamWAV:
			rs.loop_mode = AudioStreamWAV.LOOP_FORWARD
			rs.loop_begin = 0
			rs.loop_end = int(rs.get_length() * rs.mix_rate)
		_roll.stream = rs
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_song_finished)
	_scan_music()
	Game.settings_changed.connect(_on_settings)
	_apply_volumes()
	set_scene_scale(1.0)
	print("[audio] table bank: %s · music: %s" % [", ".join(KIND.keys().map(func(k): return "%s %dx%d" % [k, tier_count(k), variation_count(k, maxi(tier_count(k) - 1, 0))])), ", ".join(songs.map(func(p): return p.get_file()))])


func _make_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Table"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_db = 0.0
	p.panning_strength = 0.75
	p.attenuation_filter_cutoff_hz = 20500.0   # no distance muffling: the table is always close
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


func _load_bank() -> void:
	_bank.clear()
	for kind in KIND.keys():
		var tiers: Array = []
		for t in SfxBank.TIERS.get(kind, []):
			var streams: Array = []
			for f in t[1]:
				var path := "res://assets/audio/table/%s.wav" % f
				if ResourceLoader.exists(path):
					streams.append(load(path))
			if not streams.is_empty():
				tiers.append({"v": float(t[0]), "streams": streams})
		if tiers.is_empty():
			var legacy: Array = []
			for n in LEGACY.get(kind, []):
				if _streams.has(n):
					legacy.append(_streams[n])
			if not legacy.is_empty():
				tiers.append({"v": 1.0, "streams": legacy})
		_bank[kind] = tiers


func _ensure_bus(bus_name: String, send := "Master") -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, send)
	return idx


## Table sounds get a touch of small-room ambience and a limiter (a break is 15 clacks in 50 ms).
func _ensure_table_bus() -> void:
	if AudioServer.get_bus_index("Table") >= 0:
		return
	var idx := _ensure_bus("Table", "SFX")
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.28
	rv.damping = 0.7
	rv.spread = 0.7
	rv.hipass = 0.25
	rv.predelay_msec = 14.0
	rv.predelay_feedback = 0.1
	rv.dry = 1.0
	rv.wet = 0.085
	AudioServer.add_bus_effect(idx, rv)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.8
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(idx, lim)


func _on_settings(key: String) -> void:
	if key in ["sfx_volume", "music_volume"]:
		_apply_volumes()
	if key == "music_in_game":
		_update_music()


func _apply_volumes() -> void:
	var sv := float(Game.get_s("sfx_volume"))
	var mv := float(Game.get_s("music_volume"))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(sv, 0.0001)))
	AudioServer.set_bus_mute(_sfx_bus, sv <= 0.001)
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(mv, 0.0001)))
	AudioServer.set_bus_mute(_music_bus, mv <= 0.001)


## Size of the table in the world (1 = life size, ~0.28 = mini): distances for the 3D falloff scale with it.
func set_scene_scale(s: float) -> void:
	s = clampf(s, 0.05, 4.0)
	if absf(s - _scale) < 0.0005:
		return
	_scale = s
	for p in _voices3d:
		p.unit_size = 3.0 * s
	_roll.unit_size = 3.0 * s


## Loudness (dB, <= 0) of an impact of `kind` at `speed` m/s; -INF when it is too gentle to hear.
func level_db(kind: String, speed: float) -> float:
	var k: Dictionary = KIND[kind]
	if speed < float(k["v_min"]):
		return -INF
	var x := clampf((speed - float(k["v_min"])) / (float(k["v_ref"]) - float(k["v_min"])), 0.0, 1.0)
	return lerpf(float(k["floor"]), 0.0, pow(x, float(k["curve"])))


## Which intensity tier plays for this speed. Between two tiers the choice is random, weighted by how
## close the speed is to each (on a log scale), so intensity changes gradually instead of in steps.
func pick_tier(kind: String, speed: float) -> int:
	var tiers: Array = _bank.get(kind, [])
	if tiers.size() <= 1:
		return 0 if tiers.size() == 1 else -1
	if speed <= float(tiers[0]["v"]):
		return 0
	for i in range(1, tiers.size()):
		var hi := float(tiers[i]["v"])
		if speed <= hi:
			var lo := float(tiers[i - 1]["v"])
			var t := log(speed / lo) / log(hi / lo)
			return i if _rng.randf() < t else i - 1
	return tiers.size() - 1


func tier_count(kind: String) -> int:
	return (_bank.get(kind, []) as Array).size()


func variation_count(kind: String, tier: int) -> int:
	var tiers: Array = _bank.get(kind, [])
	return (tiers[tier]["streams"] as Array).size() if tier >= 0 and tier < tiers.size() else 0


## A table impact. speed: closing speed in m/s. at: world position (null = not positional).
## gain_db: extra trim. Returns true when a sound was started.
func impact(kind: String, speed: float, at: Variant = null, gain_db := 0.0, pitch_mul := 1.0) -> bool:
	if not KIND.has(kind):
		return false
	var db := level_db(kind, speed)
	if db == -INF:
		return false
	db += gain_db
	var tier := pick_tier(kind, speed)
	if tier < 0:
		return false
	var k: Dictionary = KIND[kind]
	# retrigger control (callers submit a cluster loudest-first)
	# (counted in physics ticks, not wall-clock: a slow frame runs several ticks back to back)
	var now := Engine.get_physics_frames()
	var win: Array = _last_hit.get(kind, [-100000, 0])
	var ticks := maxi(1, roundi(float(k["gap_ms"]) * Engine.physics_ticks_per_second / 1000.0))
	if now - int(win[0]) >= ticks:
		win = [now, 0]
	if int(win[1]) >= int(k["burst"]):
		return false
	win[1] = int(win[1]) + 1
	_last_hit[kind] = win
	var streams: Array = _bank[kind][tier]["streams"]
	var key := "%s:%d" % [kind, tier]
	var idx := _rng.randi() % streams.size()
	if streams.size() > 1 and idx == int(_last_pick.get(key, -1)):
		idx = (idx + 1 + _rng.randi() % (streams.size() - 1)) % streams.size()
	_last_pick[key] = idx
	var x := clampf(speed / float(k["v_ref"]), 0.0, 1.0)
	var pitch := pitch_mul * (1.0 + _rng.randf_range(-1.0, 1.0) * float(k["pitch"]) + 0.02 * (x - 0.5))
	if at == null:
		var p2 := _voices[_next]
		_next = (_next + 1) % VOICES
		p2.stream = streams[idx]
		p2.volume_db = db
		p2.pitch_scale = clampf(pitch, 0.5, 2.0)
		p2.play()
	else:
		var p := _free_3d()
		p.stream = streams[idx]
		p.volume_db = db
		p.pitch_scale = clampf(pitch, 0.5, 2.0)
		p.global_position = at
		p.play()
	if log_hits:
		hits.append({"kind": kind, "tier": tier, "sample": idx, "db": db, "pitch": pitch, "pos": at, "speed": speed})
	return true


func _free_3d() -> AudioStreamPlayer3D:
	for k in VOICES_3D:
		var p := _voices3d[(_next3d + k) % VOICES_3D]
		if not p.playing:
			_next3d = (_next3d + k + 1) % VOICES_3D
			return p
	var q := _voices3d[_next3d]   # all busy: take the oldest
	_next3d = (_next3d + 1) % VOICES_3D
	return q


## Rolling-on-cloth bed: level 0..1 from how fast the balls are moving, at their centre of motion.
func rolling(level: float, at: Vector3) -> void:
	_roll_target = clampf(level, 0.0, 1.0)
	if _roll.stream == null:
		return
	_roll.global_position = at
	if _roll_target > 0.01 and not _roll.playing:
		_roll_level = 0.0
		_roll.volume_db = -60.0
		_roll.play()


func _process(delta: float) -> void:
	_music_tick(delta)
	if _roll == null or _roll.stream == null or not _roll.playing:
		return
	# fast attack, slower release
	var rate := 14.0 if _roll_target > _roll_level else 4.0
	_roll_level = lerpf(_roll_level, _roll_target, 1.0 - exp(-delta * rate))
	if _roll_level < 0.004 and _roll_target <= 0.0:
		_roll.stop()
		return
	_roll.volume_db = lerpf(-46.0, -13.0, pow(_roll_level, 0.5))
	_roll.pitch_scale = lerpf(0.82, 1.22, _roll_level)


func stop_table() -> void:
	_roll_target = 0.0
	_roll_level = 0.0
	if _roll and _roll.playing:
		_roll.stop()


## Play a one-shot. volume is linear 0..1, pitch is a multiplier.
func play(sound: String, volume := 1.0, pitch := 1.0) -> void:
	if not _streams.has(sound) or volume <= 0.01:
		return
	# rate-limit identical sounds
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -1000)) < 18:
		return
	_last_play[sound] = now
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()


func ui(kind := "tap") -> void:
	play("ui_" + kind, 0.7)


# ====================================================================== music
## Songs live in assets/audio/music/ (ogg / mp3 / wav; files with "trim" in the name are ignored).
## One song plays at a time, then a 1 second pause, then another: random order, every song once before
## any repeats, and never the song that played last - including the last one from the previous visit to
## the menus or the previous run of the game. The first song after the game starts is a random one too.
## Music plays in the menus; during a match only when the player turns on "Music during the game".
## Eight songs: brass_breakbeats_2..9 (the four "Soccer" songs added in v1.1.10 were taken out again in v1.1.11
## at Randy's request).
const MUSIC_DIR := "res://assets/audio/music"
const SONG_GAP := 1.0

var songs: Array[String] = []        # resource paths
var current_song := ""
var _bag: Array[String] = []         # songs still to play in this round
var _in_game := false
var _music_wanted := false
var _gap_left := 0.0
var _fade := 0.0                      # > 0: fading out, seconds left


func _scan_music() -> void:
	songs.clear()
	var seen := {}
	var d := DirAccess.open(MUSIC_DIR)
	if d:
		for f in d.get_files():
			# exported games list "song.ogg.import" / ".remap" instead of the file itself
			var n := f.trim_suffix(".import").trim_suffix(".remap")
			if not n.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
				continue
			if n.to_lower().contains("trim") or seen.has(n):
				continue
			seen[n] = true
			if ResourceLoader.exists(MUSIC_DIR + "/" + n):
				songs.append(MUSIC_DIR + "/" + n)
	songs.sort()
	if songs.is_empty() and ResourceLoader.exists("res://assets/audio/music_lounge.ogg"):
		songs.append("res://assets/audio/music_lounge.ogg")


## Menus (in_game = false) or a match (in_game = true).
func music_context(in_game: bool) -> void:
	_in_game = in_game
	_update_music()


func music(on: bool) -> void:
	_music_wanted = on
	_update_music()


func music_should_play() -> bool:
	return _music_wanted and not songs.is_empty() and (not _in_game or bool(Game.get_s("music_in_game")))


func _update_music() -> void:
	if music_should_play():
		_fade = 0.0
		_music.volume_db = 0.0
		if not _music.playing and _gap_left <= 0.0:
			_play_next_song()
	elif _music.playing and _fade <= 0.0:
		_fade = 0.45   # fade out, then stop (see _process)
	else:
		_gap_left = 0.0


## The next song: random, each song once per round, never the one that played last.
func next_song() -> String:
	if songs.is_empty():
		return ""
	var last: String = str(Game.get_s("last_song"))
	if _bag.is_empty():
		_bag = songs.duplicate()
	var choices := _bag.filter(func(p): return p != last)
	if choices.is_empty():
		# only the last-played song is left in this round: start a new round without it
		_bag = songs.duplicate()
		choices = _bag.filter(func(p): return p != last)
		if choices.is_empty():
			choices = _bag.duplicate()   # a single song in the folder
	var pick: String = choices[_rng.randi() % choices.size()]
	_bag.erase(pick)
	return pick


func _play_next_song() -> void:
	FpsCounter.mark("next song")
	var path := next_song()
	if path == "":
		return
	var st = load(path)
	if st == null:
		return
	if st is AudioStreamOggVorbis or st is AudioStreamMP3:
		st.loop = false
	elif st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	current_song = path
	print("[audio] song: %s" % path.get_file())
	Game.set_s("last_song", path)
	_music.stream = st
	_music.volume_db = 0.0
	_music.play()


func _on_song_finished() -> void:
	if music_should_play():
		_gap_left = SONG_GAP


func _music_tick(delta: float) -> void:
	if _fade > 0.0:
		_fade -= delta
		_music.volume_db = lerpf(-40.0, 0.0, clampf(_fade / 0.45, 0.0, 1.0))
		if _fade <= 0.0:
			FpsCounter.mark("music stops")
			_music.stop()
			_music.volume_db = 0.0
	if _gap_left > 0.0:
		_gap_left -= delta
		if _gap_left <= 0.0 and music_should_play() and not _music.playing:
			_play_next_song()
