extends Node
## Global game state: settings, save data, stats, haptics.
## Autoloaded as `Game`.

signal settings_changed(key: String)
signal table_changed
signal progress_changed          # XP, level, owned items or unopened packages changed

const TITLE := "Emerald Break"
const STUDIO := "Emerald Vortex Games"
const VERSION := "1.1.14"
const ALT_TITLES := ["Pocket Horizon", "Felt Realm", "Gemshot Billiards", "Cue Vortex"]
const SAVE_PATH := "user://emerald_break_save.json"

## Display name of a control scheme in the current language.
static func scheme_name(id: String) -> String:
	return L.t(SCHEME_NAMES.get(id, id))


const SCHEMES := ["pro_dial", "orbit_ring", "trackpad", "crank", "ghost_target", "thumbstick", "slingshot", "phone_cue"]
const SCHEME_NAMES := {"slingshot": "Slingshot", "phone_cue": "Phone Cue", "pro_dial": "Pro Dial",
	"orbit_ring": "Orbit Ring", "trackpad": "Trackpad", "crank": "Crank", "ghost_target": "Ghost Target",
	"thumbstick": "Thumbstick"}
const AI_NAMES := ["Easy", "Medium", "Hard"]

## Physics defaults (debug menu can change; "Reset physics" restores these).
const PHYS_DEFAULTS := {
	"mu_slide": 0.20, "mu_roll": 0.0125, "mu_spin": 0.014, "e_ball": 0.95, "mu_ball": 0.046,
	"e_cushion": 0.80, "mu_cushion": 0.20, "e_jaw": 0.55, "max_speed": 8.0, "break_scale": 2.0, "squirt_deg": 1.4,
	"substep_hz": 240.0, "e_table": 0.5, "cushion_top": 1.55,
}

const DEFAULTS := {
	# controls & assists
	"control_scheme": "pro_dial", "aim_guide": 0, "left_handed": false, "fine_aim_scale": 1.0,
	"phone_cue_tilt_elevation": false, "phone_cue_follow_phone": true,
	# feel
	"haptics": true, "sfx_volume": 0.9, "music_volume": 0.8, "music_in_game": false, "last_song": "", "language": "auto", "reduced_motion": false,
	# looks
	"ball_set": "balls", "cue_skin": "cue_emerald_classic", "table_style": "emerald", "scene": "lounge",
	# AR
	"ar_mode": "auto", "surface": "desk", "eye_height_desk": 0.42, "eye_height_floor": 1.35,
	"ar_scale_desk": 0.28, "ar_scale_floor": 1.0, "camera_fov": 52.0, "feed_rotation": -1,
	"feed_mirror": false, "gyro_mapping": -1, "gravity_mapping": -1, "show_tracking_axes": false,
	# table (life-size metres)
	"table_length": 2.3368, "table_width": 1.1684, "table_height": 0.775, "table_height_desk": 0.26, "float_dist_desk": 0.8, "float_dist_floor": 2.2, "float_drop_desk": 0.3, "float_drop_floor": 0.45, "ar_float": false, "ar_background": false, "rail_height": 0.045,
	"pocket_scale": 1.0, "ball_radius": 0.028575, "show_legs": true,
	# match
	"time_bank_minutes": 8.0, "pass_curtain": true, "p1_name": "Player 1", "p2_name": "Player 2",
	"ai_level": 1,
	# debug
	# unlock_all is ON while the game is being tested (Randy, 11 Nov): every cue, table, ball set and scene can be
	# used straight away. Switch the default to false before the game goes to the stores.
	# fps_counter is ON while testing too (Randy, 11 Nov: "add a fps counter"); switch it off before the stores.
	"show_fps": false, "fps_counter": true, "unlock_all": true, "ad_standins": false,
	# the stick rises over balls instead of passing through them (Randy, 11 Nov: a developer option, on by default)
	"cue_over_balls": true,
	# the gear drawer in matches (Randy, 11 Nov: a testing tool, gone mid-game once released; never online)
	"gear_drawer": true,
	"onboarded": {}, "first_run": true,
}

var settings: Dictionary = {}
var phys: Dictionary = {}
var stats: Dictionary = {"shots": 0, "pots": 0, "games": 0, "wins_vs_ai": [0, 0, 0], "games_vs_ai": [0, 0, 0]}
## The player's progress. Kept on this phone and copied to the server (see net.gd).
##   xp: total experience points;  owned: ["cue:cue_walnut", "table:marble", ...];  packages: the levels whose
##   package is still unopened, oldest first;  pk_time: {"<level>": when that package was earned (unix seconds)};
##   chest_at: when the XP chest is ready (0 = now);  chest_from: when it was last opened;  chest_cut: the
##   advert that shortens the wait has been used for this wait;  matches: finished matches;  curve: 2 = package
##   levels numbered for the 130-level curve of v1.1.7 (missing = the 100 levels before it; see migrate_levels_117).
var progress: Dictionary = fresh_progress()
## Seconds added to the clock (tests and the developer tools only).
var clock_shift := 0


static func fresh_progress() -> Dictionary:
	return {"xp": 0, "owned": [], "packages": [], "pk_time": {}, "chest_at": 0, "chest_from": 0, "chest_cut": false, "matches": 0, "curve": 2}


func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_shift
var _save_pending := false
var _save_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func _process(delta: float) -> void:
	if _save_pending:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_pending = false
			_save_now()


# ------------------------------------------------------------------ settings
## Player i's name (0 / 1). The built-in "Player 1" / "Player 2" are shown in the current language.
const DEFAULT_NAMES := ["Player 1", "Player 2"]


func player_name(i: int) -> String:
	var n := str(get_s("p%d_name" % (i + 1)))
	return L.t(n) if n in DEFAULT_NAMES else n


func store_player_name(i: int, text: String) -> void:
	var t := text.strip_edges()
	set_s("p%d_name" % (i + 1), DEFAULT_NAMES[i] if t == "" or t == L.t(DEFAULT_NAMES[i]) else t)


func get_s(key: String, fallback = null):
	if settings.has(key):
		return settings[key]
	return DEFAULTS.get(key, fallback)


func set_s(key: String, value) -> void:
	if settings.get(key) == value:
		return
	settings[key] = value
	settings_changed.emit(key)
	if key.begins_with("table_") or key in ["pocket_scale", "ball_radius", "rail_height", "show_legs"]:
		table_changed.emit()
	request_save()


func get_p(key: String) -> float:
	return float(phys.get(key, PHYS_DEFAULTS.get(key, 0.0)))


func set_p(key: String, value: float) -> void:
	phys[key] = value
	settings_changed.emit("phys_" + key)
	request_save()


func reset_physics() -> void:
	phys = PHYS_DEFAULTS.duplicate()
	settings_changed.emit("phys_all")
	request_save()


func reset_table() -> void:
	for k in ["table_length", "table_width", "table_height", "table_height_desk", "rail_height", "pocket_scale", "ball_radius", "show_legs"]:
		settings[k] = DEFAULTS[k]
	table_changed.emit()
	request_save()


func scheme() -> String:
	var s: String = get_s("control_scheme")
	return s if s in SCHEMES else "slingshot"


func table_style() -> Dictionary:
	return Catalog.table(get_s("table_style"))


func scene_style() -> Dictionary:
	return Catalog.scene(get_s("scene"))


## Build the table geometry from current settings.
func make_table() -> TableGeom:
	return TableGeom.new(float(get_s("table_length")), float(get_s("table_width")),
		float(get_s("ball_radius")), float(get_s("pocket_scale")))


## Push physics tunables into a simulator.
func configure_sim(sim: PoolSim) -> void:
	for k in PHYS_DEFAULTS.keys():
		if k == "substep_hz":
			sim.substep = 1.0 / clampf(get_p(k), 120.0, 960.0)
		else:
			sim.set(k, get_p(k))


# ------------------------------------------------------------------ levels, packages, gear
const GEAR_KEYS := {"cue": "cue_skin", "table": "table_style", "balls": "ball_set", "scene": "scene"}


func xp() -> int:
	return int(progress.get("xp", 0))


func level() -> int:
	return XP.level_of(xp())


## Adds XP. Every level gained puts one package (of that level's rarity) in the queue.
## Returns {"from": level before, "to": level after, "xp_from": ..., "xp_to": ...}.
func add_xp(amount: int) -> Dictionary:
	var before := xp()
	var l0 := XP.level_of(before)
	var after := mini(before + maxi(amount, 0), XP.total_for(XP.MAX_LEVEL))
	var l1 := XP.level_of(after)
	progress["xp"] = after
	if l1 > l0:
		var q: Array = progress.get("packages", [])
		var times: Dictionary = progress.get("pk_time", {})
		for l in range(l0 + 1, l1 + 1):
			q.append(l)
			times[str(l)] = now()
		progress["packages"] = q
		progress["pk_time"] = times
	if amount > 0:
		progress_changed.emit()
		request_save()
	return {"from": l0, "to": l1, "xp_from": before, "xp_to": after}


func packages() -> Array:
	return progress.get("packages", [])


## Rarity 0 items belong to everyone; the rest come out of packages.
func owns(kind: String, id: String) -> bool:
	if bool(get_s("unlock_all")):
		return true
	if Catalog.rarity(Catalog.find(Catalog.kind_list(kind), id)) == 0:
		return true
	return (kind + ":" + id) in (progress.get("owned", []) as Array)


## Everything of one rarity the player does not have yet: [[kind, entry], ...].
func locked_items(rarity: int) -> Array:
	var out := []
	var have: Array = progress.get("owned", [])
	for kind in GEAR_KEYS.keys():
		for e in Catalog.kind_list(kind):
			if Catalog.rarity(e) == rarity and not ((kind + ":" + str(e["id"])) in have):
				out.append([kind, e])
	return out


## Seconds until the package of `level` unlocks by itself (0 = it can be opened). A package from a save made
## before packages had waits counts as unlocked.
func package_left(level: int) -> int:
	var times: Dictionary = progress.get("pk_time", {})
	if not times.has(str(level)):
		return 0
	var wait: int = XP.PACKAGE_WAIT[XP.rarity_of_level(level)]
	return maxi(0, int(times[str(level)]) + wait - now())


## How many packages can be opened right now (they unlock in order, the oldest first).
func packages_ready() -> int:
	var n := 0
	for l in packages():
		if package_left(int(l)) > 0:
			break
		n += 1
	return n


## Opens the oldest package: a random item of its rarity that the player does not own yet. It must have
## unlocked, unless `now_anyway` (the player watched an advert for it).
## Returns {"kind", "id", "name", "rarity", "level"}; or {"xp": n} in the (theoretical) case that nothing is left.
func open_package(rng: RandomNumberGenerator = null, now_anyway := false) -> Dictionary:
	var q: Array = progress.get("packages", [])
	if q.is_empty():
		return {}
	if not now_anyway and package_left(int(q[0])) > 0:
		return {}
	var lvl := int(q.pop_front())
	progress["packages"] = q
	(progress.get("pk_time", {}) as Dictionary).erase(str(lvl))
	var rar := XP.rarity_of_level(lvl)
	var pool := locked_items(rar)
	var step := 1
	while pool.is_empty() and step <= 4:      # that rarity is complete: the nearest one that is not
		for r2 in [rar - step, rar + step]:
			if pool.is_empty() and r2 >= 1 and r2 <= 5:
				pool = locked_items(r2)
		step += 1
	var out := {"level": lvl, "rarity": rar}
	if pool.is_empty():
		out["xp"] = 150
		add_xp(150)
	else:
		var r := rng if rng else RandomNumberGenerator.new()
		if rng == null:
			r.randomize()
		var pick: Array = pool[r.randi() % pool.size()]
		var owned: Array = progress.get("owned", [])
		owned.append(str(pick[0]) + ":" + str(pick[1]["id"]))
		progress["owned"] = owned
		out["kind"] = pick[0]
		out["id"] = pick[1]["id"]
		out["name"] = pick[1]["name"]
		out["rarity"] = Catalog.rarity(pick[1])
	progress_changed.emit()
	request_save()
	return out


# ------------------------------------------------------------------ the XP chest
## Seconds until the XP chest is ready (0 = ready).
func chest_left() -> int:
	var left := int(progress.get("chest_at", 0)) - now()
	if left > XP.CHEST_WAIT:
		# the phone's clock was turned back: never wait longer than a whole wait
		progress["chest_at"] = now() + XP.CHEST_WAIT
		left = XP.CHEST_WAIT
	return maxi(0, left)


func chest_ready() -> bool:
	return chest_left() == 0


## What the chest holds right now.
func chest_xp() -> int:
	return XP.chest_xp(level())


## The advert that turns this wait into 2 hours (it "saves 4 hours"; the button: "Open 4 Hours Faster With Ad"):
## once per wait, and only while there is something to shorten.
func can_cut_chest() -> bool:
	return not chest_ready() and not bool(progress.get("chest_cut", false))


## After the advert: the chest is ready 2 hours after it was last opened (at once if that time has passed).
func cut_chest() -> void:
	if not can_cut_chest():
		return
	progress["chest_cut"] = true
	progress["chest_at"] = mini(int(progress.get("chest_at", 0)), int(progress.get("chest_from", 0)) + XP.CHEST_WAIT_AD)
	progress_changed.emit()
	request_save()


## Opens the XP chest: {"xp": amount, "gain": add_xp's answer}, or {} while it is not ready.
func open_chest() -> Dictionary:
	if not chest_ready() or level() >= XP.MAX_LEVEL:
		return {}
	var amount := chest_xp()
	progress["chest_from"] = now()
	progress["chest_at"] = now() + XP.CHEST_WAIT
	progress["chest_cut"] = false
	var gain := add_xp(amount)
	progress_changed.emit()
	request_save()
	return {"xp": amount, "gain": gain}


## Counts a finished match. Every score screen is followed by the between-matches advert (once adverts are
## on), so the first match of a session never has one before it.
func count_match() -> void:
	progress["matches"] = int(progress.get("matches", 0)) + 1
	request_save()


## A cue, table, ball set or scene that is no longer owned (or no longer exists) falls back to the starter one.
func _fix_gear() -> void:
	for kind in GEAR_KEYS.keys():
		var key: String = GEAR_KEYS[kind]
		var id := str(get_s(key))
		var e := Catalog.find(Catalog.kind_list(kind), id)
		if str(e.get("id", "")) != id or not owns(kind, id):
			settings[key] = DEFAULTS[key]


# ------------------------------------------------------------------ stats
func bump_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
	request_save()


func record_ai_game(level: int, won: bool) -> void:
	var g: Array = stats.get("games_vs_ai", [0, 0, 0])
	var w: Array = stats.get("wins_vs_ai", [0, 0, 0])
	g[level] = int(g[level]) + 1
	if won:
		w[level] = int(w[level]) + 1
	stats["games_vs_ai"] = g
	stats["wins_vs_ai"] = w
	request_save()


func reset_stats() -> void:
	stats = {"shots": 0, "pots": 0, "games": 0, "wins_vs_ai": [0, 0, 0], "games_vs_ai": [0, 0, 0]}
	request_save()


func is_onboarded(key: String) -> bool:
	return bool((get_s("onboarded") as Dictionary).get(key, false))


func mark_onboarded(key: String) -> void:
	var d: Dictionary = (get_s("onboarded") as Dictionary).duplicate()
	d[key] = true
	set_s("onboarded", d)


# ------------------------------------------------------------------ haptics
var _buzz_until := 0     # (msec) when the buzz running now ends


func vibrate(ms: int, amplitude := -1.0) -> void:
	if not get_s("haptics"):
		return
	if OS.has_feature("mobile"):
		# A buzz that would end before the one already running is left out: the phone would only cut the running
		# one short. (The break sends a dozen in a few frames; each is a call into Android that holds up the frame.)
		var now := Time.get_ticks_msec()
		if now + ms <= _buzz_until:
			return
		_buzz_until = now + ms
		FpsCounter.mark("buzz")
		Input.vibrate_handheld(ms, amplitude)


# ------------------------------------------------------------------ persistence
func request_save() -> void:
	_save_pending = true
	_save_timer = 0.6


func _save_now() -> void:
	FpsCounter.mark("save")
	var data := {"version": VERSION, "settings": settings, "phys": phys, "stats": stats, "progress": progress}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func flush() -> void:
	if _save_pending:
		_save_pending = false
		_save_now()


func _load() -> void:
	phys = PHYS_DEFAULTS.duplicate()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if typeof(parsed.get("settings")) == TYPE_DICTIONARY:
		settings = parsed["settings"]
		# older versions had a gyro-only "camera" AR choice: AR is walk-around (ARCore) only now
		if settings.get("ar_mode", "auto") not in ["auto", "studio"]:
			settings["ar_mode"] = "auto"
		# a save from before v1.1.1: music at the new 80%, and "unlock everything" on as the new default has it
		if _older(str(parsed.get("version", "")), "1.1.1"):
			settings["music_volume"] = DEFAULTS["music_volume"]
			settings.erase("unlock_all")
			request_save()
		# a save from before v1.1.5: the table now has the WPA sizes and the time bank is 8 minutes. Values still on
		# the old defaults move to the new ones; a size or time the player chose stays.
		if _older(str(parsed.get("version", "")), "1.1.5"):
			for old_new in [["table_length", 2.24], ["table_width", 1.12], ["table_height", 0.79], ["time_bank_minutes", 5.0]]:
				if settings.has(old_new[0]) and is_equal_approx(float(settings[old_new[0]]), float(old_new[1])):
					settings[old_new[0]] = DEFAULTS[old_new[0]]
			request_save()
	if typeof(parsed.get("phys")) == TYPE_DICTIONARY:
		for k in parsed["phys"].keys():
			if PHYS_DEFAULTS.has(k):
				phys[k] = float(parsed["phys"][k])
	if typeof(parsed.get("stats")) == TYPE_DICTIONARY:
		for k in parsed["stats"].keys():
			stats[k] = parsed["stats"][k]
	if typeof(parsed.get("progress")) == TYPE_DICTIONARY:
		progress.erase("curve")       # a save from before v1.1.7 has none (see migrate_levels_117)
		for k in parsed["progress"].keys():
			progress[k] = parsed["progress"][k]
		progress.erase("daily")       # the daily gift was replaced by the XP chest (v1.1.2)
		if typeof(progress.get("pk_time")) != TYPE_DICTIONARY:
			progress["pk_time"] = {}
		progress["xp"] = int(progress.get("xp", 0))
		if int(progress.get("curve", 1)) < 2:
			migrate_levels_117()
	_fix_gear()


## v1.1.7: 130 levels instead of 100 for the same XP, so a save's XP stands at a higher level now. Every package the
## player has received keeps its rarity; the ones still waiting are moved to the new level numbers of that rarity
## (their timers kept), and each level the player now stands on that has no package yet brings one, which starts
## unlocking now. Nothing the player has is ever taken away (the new count of each rarity is never below the old one).
func migrate_levels_117() -> void:
	var x := xp()
	var l_old := XP.old_level_of(x)
	var l_new := XP.level_of(x)
	var q_old: Array = progress.get("packages", [])
	var t_old: Dictionary = progress.get("pk_time", {})
	var queued := {1: [], 2: [], 3: [], 4: [], 5: []}       # rarity -> waiting packages' start times (oldest first)
	for l in q_old:
		var r := clampi(int(ceil(float(l) / 20.0)), 1, 5)
		(queued[r] as Array).append(t_old.get(str(l), -1))
	var q_new: Array = []
	var t_new := {}
	for r in range(1, 6):
		var got := clampi(l_old - 20 * (r - 1), 0, 20)          # packages of this rarity received before
		var opened := maxi(0, got - (queued[r] as Array).size())
		var levels: Array = []
		for l in range(XP.PER_RARITY * (r - 1) + 1, mini(XP.PER_RARITY * r, l_new) + 1):
			levels.append(l)
		var waiting := levels.slice(mini(opened, levels.size()))
		for i in waiting.size():
			var l: int = waiting[i]
			q_new.append(l)
			if i < (queued[r] as Array).size():
				if int(queued[r][i]) >= 0:
					t_new[str(l)] = int(queued[r][i])
			else:
				t_new[str(l)] = now()
	q_new.sort()
	progress["packages"] = q_new
	progress["pk_time"] = t_new
	progress["curve"] = 2


## True when version string `v` ("1.0.9") comes before `than` ("1.1.1"); an empty or odd `v` counts as older.
static func _older(v: String, than: String) -> bool:
	var a := v.split(".")
	var b := than.split(".")
	for i in b.size():
		var x := int(a[i]) if i < a.size() and a[i].is_valid_int() else -1
		var y := int(b[i])
		if x != y:
			return x < y
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


func _exit_tree() -> void:
	flush()
