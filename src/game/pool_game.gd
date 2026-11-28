class_name PoolGame
extends Node
## Match controller: owns the simulator, ball visuals, cue, aim guide, 8-ball rules, turns and clocks.
## Modes: "versus" (vs AI or pass & play) and "practice" (free shooting, no clock).
## New modes (campaign, online) can reuse this: they only need their own rules + resolve function.

signal turn_started(player: int, info: Dictionary)
signal message(text: String, kind: String)
signal game_over(result: Dictionary)
signal rack_cleared(info: Dictionary)      # Practice: every ball is down (the "score screen" of Practice)
signal state_changed(state: int)
signal shot_fired
signal stats_changed
signal ball_potted(number: int, shooter: int)    # a ball dropped (0 = the cue ball), as it drops
signal groups_set                                 # the table stopped being open: rules.groups says who has which
signal match_void                                 # online: the other player left the ready-up as this match began (no match)

enum State { SETUP, PLACE_TABLE, AIM, BALL_IN_HAND, ROLLING, AI_THINK, OVER }

var mode := "practice"
var vs_ai := false
var ai_level := 1
## v1.1.15: Play Online found nobody within a minute: the AI plays under a screen name (FillIn.make), and the
## match looks, plays and pays like an online one. Empty for every other match.
var fill_in := {}
var _si_rng := RandomNumberGenerator.new()
var _si_t := 0.0             # seconds into the stand-in's turn
var _si_place: Array = []    # [[seconds, position]] the cue ball is dragged through (ball in hand)
var _si_place_i := 0
var _si_aim_from := -1.0
var si_last_track := PackedFloat32Array()    # the stand-in's aiming of its last stroke (tests)
## v1.1.15: the tutorial runs as a practice match (src/game/tutorial.gd arranges the table between objectives):
## no rack-cleared screen, no stats; the aim guide it asks for; the last stroke for its checks.
var tutorial := false
var warmup := false            # the silent match that prepares the shaders while loading: never moves the camera
var guide_override := -1
var last_shot := {}
var _ai_think := 0.0
var online := false          # an online match: one seat is played here, the other arrives over the network
var net_seat := 0            # which seat is played on this phone in an online match
var xp_track: XP.Tracker     # counts this phone's player's XP (matches only)
var net: NetMatch            # the link to the other phone (online matches)
var _remote_result := {}     # how the other player's shot ended, as their phone reported it
var _await_result := false   # our copy of their shot has stopped; waiting for their report
var _late := 0.0             # how long the other player's clock has been at zero without their phone reporting it
var _net_q: Array = []       # the other player's events, in order, not yet played back
var _catch_up := false       # this phone is behind the other player: replay briskly
var net_drift := 0           # shots of the other player that ended differently here than on their phone
var _rest_sum := 0           # fingerprint of the table at the moment the balls stopped
# ---- online, v1.1.14 (Randy: "make the game smooth and the opponent's pool stick & strike & balls all line up
# properly for both players"). This player's aiming is sampled 15 times a second and sent in small batches; the
# other phone plays it back a moment behind, smoothly, and the last sample is the stroke itself.
var _aim_clock := 0.0                       # seconds into this turn's aiming
var _aim_tick := 0.0
var _aim_pending := PackedFloat32Array()    # samples not sent yet, 6 numbers each: t, yaw, elev, tip x, tip y, pull
var _aim_last := PackedFloat32Array()
var _aim_send_t := 0.0
var _aim_buf := PackedFloat32Array()        # the other player's samples, being played back
var _aim_cursor := -1.0                     # where the playback is, in their seconds
var _remote_shot := {}                      # their stroke: struck when the playback reaches its last sample
var _path_thread: Thread                    # this phone's shot: its path for the other phone, on a thread
var _path_slot: Array = []                  # the shot's place in the send queue
var _path_shot := {}
var _stroke_wait := 0.0                     # the stick is still on its way to the ball: the balls wait for it
var net_path_fixes := 0                     # (tests, log) snapshots that put this phone's replay right
var remote_lineup: Array = []               # (tests) per stroke of theirs: [yaw gap, pull gap] of the stick at the strike
var remote_max_step := 0.0                  # (tests) the biggest turn of their stick between two frames (radians)
var _aim_started := false                   # their playback has drawn its first frame
var rules: EightBall
var sim: PoolSim
var stage: Stage
var views: Array = []
var cue_view: CueView
var aim_guide: AimGuide
var control: CueControl
var control_layer: Control
var state := State.SETUP
var clocks := [300.0, 300.0]
var current := 0
var player_names := ["Player 1", "Player 2"]
var time_scale := 1.0
var cue_start := Vector2.ZERO
var undo_sim: PoolSim = null
var potted_this_shot: Array = []
var jumped_this_shot: Array = []   # ball numbers that left the table this shot
var shots_total := 0
## (27 Nov 2026, analytics) balls potted and fouls per seat this match, and why it ended ("eight_ball", "opponent_left",
## "connection_lost", "timeout")
var stat_pots := [0, 0]
var stat_fouls := [0, 0]
var end_why := ""
var _rack_shots0 := 0         # Practice: shots_total when this rack started
var _rack_t0 := 0.0           # Practice: when this rack started (seconds of play)
var placing_cue := false
var placed_this_turn := false   # the cue ball was placed this turn ("Place cue ball"): the hand button stops blinking
var _hand_ring: MeshInstance3D   # glowing ring around the cue ball while it's in hand
var _kitchen: MeshInstance3D     # the area behind the head string, lit while the cue ball is being placed for the break
var _hand_t := 0.0
var match_seed := 0
var _ai_thread: Thread
var _warming := false        # warm_draw() is showing everything once (behind a cover)
static var _kitchen_shader: Shader   # built once a session, so it is compiled once
static var _spark_mesh: SphereMesh
static var _spark_mats := {}         # colour -> material of the pocket sparkle
var _ai_result := {}
var _ai_anim := 0.0
var _ai_from_yaw := 0.0
var _last_turn_player := -1
var _warned := [false, false]
var _rolling_time := 0.0
var _break_pending := false
var cue_skins := ["", ""]    # the cue each seat plays with: the CPU and an online opponent bring their own
var ball_set := ""           # this match's balls (online: one player's balls on the other player's table)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


# ================================================================== setup
## Player names in the current language (default names and the CPU's level are translated).
func refresh_names() -> void:
	player_names = [Game.player_name(0), ("CPU · " + L.t(AIPlayer.NAMES[ai_level])) if vs_ai else Game.player_name(1)]
	if not fill_in.is_empty():
		player_names[1] = str(fill_in.get("name", "Rina"))
	if online and net:
		var other := str(net.opp.get("name", "")).strip_edges()
		player_names[net_seat] = Game.player_name(0)
		player_names[1 - net_seat] = other if other != "" and other != Game.player_name(0) else L.t("Opponent")


## Is seat `p` played by a person on this phone? Both seats in a local turn-based match, seat 0 against the
## CPU (and, once online play exists, only your own seat).
func plays_here(p: int) -> bool:
	if online:
		return p == net_seat
	return not vs_ai or p == 0


## The seat of the player holding this phone when the other seat is not played here.
func local_seat() -> int:
	return net_seat if online else 0


## Which XP rate this match pays (see XP.MODE_FACTOR).
func xp_mode() -> String:
	if mode != "versus":
		return "practice"
	return "online" if looks_online() else ("cpu" if vs_ai else "local")


## An online match, or one Play Online started with a stand-in opponent: shown and played the same way.
func looks_online() -> bool:
	return online or not fill_in.is_empty()


## The other player, for the report / block card: [name, player id] ("" id for a stand-in).
func opponent() -> Array:
	var seat := 1 - local_seat()
	return [player_names[seat], net.opp_id if online and net else ""]


func setup(p_stage: Stage, p_layer: Control, cfg: Dictionary) -> void:
	stage = p_stage
	control_layer = p_layer
	mode = cfg.get("mode", "practice")
	vs_ai = cfg.get("vs_ai", false)
	online = cfg.get("online", false)
	fill_in = cfg.get("fill_in", {}) if vs_ai else {}
	_si_rng.randomize()
	tutorial = cfg.has("tutorial")
	warmup = cfg.get("warmup", false)
	net = cfg.get("net") as NetMatch
	if online and net == null:
		online = false
	net_seat = net.seat if online else 0
	if mode == "versus":
		xp_track = XP.Tracker.new()
	ai_level = clampi(int(cfg.get("ai_level", Game.get_s("ai_level"))), 0, 2)
	refresh_names()
	_pick_gear()
	# 8 minutes each for the whole match (Randy, v1.1.5). Online both phones use the standard 8 minutes, whatever
	# either player has set for matches on their own phone.
	var bank := float(Game.DEFAULTS["time_bank_minutes"] if looks_online() else Game.get_s("time_bank_minutes")) * 60.0
	clocks = [bank, bank]
	current = 1 if fill_in.get("they_break", false) else 0
	shots_total = 0
	_rack_shots0 = 0
	_rack_t0 = Time.get_ticks_msec() / 1000.0
	stage.rebuild_table()
	sim = PoolSim.new(stage.table_view.geom)
	sim.cue_clearance = true
	sim.ball_clearance = looks_online() or bool(Game.get_s("cue_over_balls"))     # online: always, so both phones agree
	sim.rail_height = stage.table_view.rail_height
	Game.configure_sim(sim)
	match_seed = net.match_seed if online else randi()     # both phones of an online match rack from the same seed
	Rack.rack_eight_ball(sim, match_seed)
	rules = EightBall.new()
	_set_break(true)
	_build_views()
	if cue_view == null:
		cue_view = CueView.new()
		stage.table_root.add_child(cue_view)
	cue_view.ball_r = sim.R
	for p in [1 - local_seat(), local_seat()]:     # both built now (the opponent's is shown on their turns)
		cue_view.set_skin(cue_skins[p])
	if aim_guide == null:
		aim_guide = AimGuide.new()
		stage.table_root.add_child(aim_guide)
	if _hand_ring == null:
		_hand_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = sim.R * 1.35
		tm.outer_radius = sim.R * 1.8
		tm.rings = 48
		tm.ring_segments = 8
		_hand_ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.78, 0.34, 0.95)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hand_ring.material_override = rm
		_hand_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_ring.scale = Vector3(1, 0.12, 1)
		_hand_ring.visible = false
		stage.table_root.add_child(_hand_ring)
	if _kitchen == null:
		_kitchen = MeshInstance3D.new()
		var km := PlaneMesh.new()
		km.size = Vector2(sim.table.a * 0.5, sim.table.b * 2.0)
		_kitchen.mesh = km
		if _kitchen_shader == null:
			_kitchen_shader = Shader.new()
			# glows by emission on a black surface (see scene_fx.gdshader for why it is not "unshaded")
			_kitchen_shader.code = "shader_type spatial;\nrender_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled;\nvoid fragment() {\n\tfloat line = smoothstep(0.985, 0.995, UV.x);\n\tALBEDO = vec3(0.0);\n\tEMISSION = vec3(0.17, 0.9, 0.65) * (0.1 + 0.025 * sin(TIME * 3.0) + line * 0.8);\n\tSPECULAR = 0.0;\n\tROUGHNESS = 1.0;\n\tALPHA = 1.0;\n}\n"
		var kmat := ShaderMaterial.new()
		kmat.shader = _kitchen_shader
		_kitchen.material_override = kmat
		_kitchen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_kitchen.position = Vector3(-sim.table.a * 0.75, 0.0015, 0.0)
		_kitchen.visible = false
		stage.table_root.add_child(_kitchen)
	_apply_assist()
	set_control_scheme(Game.scheme())
	Game.settings_changed.connect(_on_setting)
	if not cfg.get("warmup", false) and not tutorial:
		Game.bump_stat("games")


## Whose gear is on the table. The player's own cue, table and balls, except: the CPU plays with its own cue;
## online, each player brings their cue, the table is the one of the player who breaks (seat 0) and the balls are
## the other player's (Randy, 11 Nov 2026). Each phone shows its own player's scene round the table.
func _pick_gear() -> void:
	var mine := str(Game.get_s("cue_skin"))
	cue_skins = [mine, mine]
	ball_set = str(Game.get_s("ball_set"))
	if tutorial:
		ball_set = "balls"      # the tutorial names the balls by colour (yellow 1, blue 2, black 8): the classic set
	stage.match_table = ""
	if not fill_in.is_empty():
		cue_skins[1] = str(Catalog.cue(str(fill_in.get("cue", "")))["id"])
		if fill_in.get("they_break", false):
			stage.match_table = str(Catalog.table(str(fill_in.get("table", "")))["id"])
		else:
			ball_set = str(Catalog.ball_set(str(fill_in.get("balls", "")))["id"])
	elif vs_ai:
		cue_skins[1] = AIPlayer.cue_for(ai_level, mine)
	elif online:
		var opp: Dictionary = net.opp
		cue_skins[1 - net_seat] = str(Catalog.cue(str(opp.get("cue", "")))["id"])
		if net_seat == 0:
			ball_set = str(Catalog.ball_set(str(opp.get("balls", "")))["id"])
		else:
			stage.match_table = str(Catalog.table(str(opp.get("table", "")))["id"])


## Online: whose table and whose balls, in words (shown when the match starts).
func gear_note() -> String:
	if not looks_online():
		return ""
	var me := local_seat()
	var other := str(player_names[1 - me])
	var i_break: bool = net_seat == 0 if online else not fill_in.get("they_break", false)
	return (L.t("Your table · %s's balls") % other) if i_break else (L.t("%s's table · your balls") % other)


func _build_views() -> void:
	for v in views:
		if is_instance_valid(v):
			v.queue_free()
	views.clear()
	for i in sim.n:
		var bv := BallView.make(sim.num[i], sim.R, ball_set)
		stage.table_root.add_child(bv)
		if sim.st[i] == PoolSim.ST_POCKETED:
			bv.visible = false
		else:
			bv.place(sim.pos[i])
		views.append(bv)


func _apply_assist() -> void:
	aim_guide.assist = guide_override if guide_override >= 0 else int(Game.get_s("aim_guide"))


func set_control_scheme(id: String) -> void:
	var yaw := control.yaw if control else 0.0
	if control:
		control.deactivate()
		control.queue_free()
	match id:
		"phone_cue": control = ControlPhoneCue.new()
		"pro_dial": control = ControlProDial.new()
		"orbit_ring": control = ControlOrbitRing.new()
		"trackpad": control = ControlTrackpad.new()
		"crank": control = ControlCrank.new()
		"ghost_target": control = ControlGhostTarget.new()
		"thumbstick": control = ControlThumbstick.new()
		_: control = ControlSlingshot.new()
	add_child(control)
	control.activate(self, control_layer)
	if sim != null and views.size() > 0:
		control.reset_for_turn(yaw)
	else:
		control.yaw = yaw
	control.shot_requested.connect(_on_shot_requested)
	control.set_enabled(state == State.AIM and is_human_turn())


func _on_setting(k: String) -> void:
	match k:
		"control_scheme", "left_handed":
			set_control_scheme(Game.scheme())
		"aim_guide":
			_apply_assist()
		"cue_skin":
			var mine := str(Game.get_s("cue_skin"))
			for p in 2:
				if plays_here(p) or (not online and not vs_ai):
					cue_skins[p] = mine
			if vs_ai and fill_in.is_empty() and cue_skins[1] == mine:
				cue_skins[1] = AIPlayer.cue_for(ai_level, mine)
			cue_view.set_skin(cue_skins[current])
		"ball_set":
			if not looks_online():
				ball_set = str(Game.get_s("ball_set"))
				_build_views()


func begin() -> void:
	if stage.is_ar() and not stage.placed:
		_set_state(State.PLACE_TABLE)
		return
	_start_turn(true)


func on_table_placed() -> void:
	if state == State.PLACE_TABLE:
		_start_turn(true)


# ================================================================== turns
func is_human_turn() -> bool:
	return plays_here(current)


func cue_index() -> int:
	return sim.cue_index()


func cue_ball_pos() -> Vector2:
	return sim.pos[sim.cue_index()]


func _set_state(s: int) -> void:
	if s == State.BALL_IN_HAND and is_human_turn() and state != State.BALL_IN_HAND and not warmup:
		if stage.mode == Stage.Mode.STUDIO:
			# Play in place: the cue ball is placed from the top view, and once it is placed the aim view follows
			stage.set_view(Stage.View.TOP)
			stage.set_meta("aim_after_place", true)
		elif stage.view == Stage.View.AIM:
			# AR's aim camera follows the cue ball: moving the ball from it would move the view under the finger, so
			# the overview while placing, and the aim view again once it is placed (as for a shot: restore_aim_view)
			stage.set_view(Stage.View.OVERVIEW)
			stage.set_meta("restore_aim_view", true)
	elif s == State.AIM and state == State.BALL_IN_HAND:
		for k in ["aim_after_place", "restore_aim_view"]:
			if stage.has_meta(k):
				stage.remove_meta(k)
				stage.set_view(Stage.View.AIM)
	state = s
	FpsCounter.phase = "match " + str(State.keys()[s]).to_lower()
	if control:
		control.set_enabled(s == State.AIM and is_human_turn())
	if s != State.AIM:
		aim_guide.hide_guide()
	state_changed.emit(s)


func _start_turn(first := false) -> void:
	var info := {"first": first, "ball_in_hand": rules.ball_in_hand and mode == "versus",
		"changed": current != _last_turn_player, "group": rules.groups[current]}
	# Play in place: the break starts with placing the cue ball, from the top view, with a ring round it and a
	# "Place cue ball" button (Randy, 22 Nov: "please have a yellow circle around the actual cue ball pulsating and a
	# button saying Place Cue Ball so people know they need to place the cue ball from the top view... when they
	# place it, it automatically switches to the target aimer view (this is the non ar mode of course)")
	info["place_first"] = info["ball_in_hand"] or (_break_pending and stage.mode == Stage.Mode.STUDIO and not tutorial and not warmup)
	placed_this_turn = false
	if sim.st[cue_index()] == PoolSim.ST_POCKETED:
		_respawn_cue(Rack.break_spot(sim))
	control.reset_for_turn(_default_aim())
	control.offset = Vector2.ZERO
	control.elevation = 0.0
	_last_turn_player = current
	cue_view.set_skin(cue_skins[current])     # whoever is at the table holds their own cue
	FpsCounter.mark("turn starts")
	turn_started.emit(current, info)
	if online and is_human_turn():
		_reset_aim_stream()
	if info["place_first"] and is_human_turn():
		placing_cue = true
		_set_state(State.BALL_IN_HAND)
	elif is_human_turn():
		_set_state(State.AIM)
	else:
		_set_state(State.AI_THINK)
		if online:
			_start_remote()
		else:
			_start_ai(info["ball_in_hand"])


## Point the cue at the nearest legal ball so every turn starts with a sensible aim.
func _default_aim() -> float:
	var c := cue_ball_pos()
	var legal := rules.legal_targets(sim, current)
	var best := -1
	var bd := INF
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED or sim.kind[i] == PoolSim.K_CUE:
			continue
		if mode == "versus" and not rules.is_break and not (sim.num[i] in legal):
			continue
		var d := sim.pos[i].distance_to(c)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return 0.0
	return (sim.pos[best] - c).angle()


func _respawn_cue(p: Vector2) -> void:
	var c := cue_index()
	var spot := _free_spot_near(p, c, Vector2(-1, 0))
	sim.pos[c] = spot
	sim.vel[c] = Vector2.ZERO
	sim.spin[c] = Vector3.ZERO
	sim.st[c] = PoolSim.ST_REST
	sim.pocket_of[c] = -1
	views[c].place(spot)


## Balls that jumped off the table go back on the foot spot (or the nearest free spot behind it).
func _respot_jumped(include_eight: bool) -> void:
	for nb in jumped_this_shot:
		if nb == 0 or (nb == 8 and not include_eight):
			continue
		var i := sim.index_of_number(nb)
		if i < 0:
			continue
		var spot := _free_spot_near(Rack.foot_spot(sim), i, Vector2(1, 0))
		sim.pos[i] = spot
		sim.vel[i] = Vector2.ZERO
		sim.spin[i] = Vector3.ZERO
		sim.st[i] = PoolSim.ST_REST
		sim.pocket_of[i] = -1
		views[i].place(spot)


## Closest free spot to `p`, searching along `dir` first, then outward rings (always succeeds on a legal table).
func _free_spot_near(p: Vector2, ignore: int, dir := Vector2(1, 0)) -> Vector2:
	if sim.is_spot_free(p, ignore):
		return p
	var step := sim.R * 2.05
	for k in range(1, 30):
		for cand in [p + dir * step * k, p - dir * step * k]:
			if sim.is_spot_free(cand, ignore):
				return cand
	for ring in range(1, 40):
		for a in 24:
			var cand: Vector2 = p + Vector2.from_angle(TAU * a / 24.0) * sim.R * 1.1 * ring
			if sim.is_spot_free(cand, ignore):
				return cand
	return p


func _respot_eight() -> void:
	var i := sim.index_of_number(8)
	var spot := _free_spot_near(Rack.foot_spot(sim), i, Vector2(1, 0))
	sim.pos[i] = spot
	sim.st[i] = PoolSim.ST_REST
	sim.pocket_of[i] = -1
	views[i].place(spot)


# ================================================================== frame
func _process(delta: float) -> void:
	if sim == null or _warming:
		return
	if _path_thread and not _path_thread.is_alive():
		_send_shot()
	if online:
		_net_tick(delta)
		if state == State.OVER:
			return
	match state:
		State.AIM, State.BALL_IN_HAND:
			# an AR table that is being put down again (pause menu, re-place button) stops the clock, except
			# online, where the other player is waiting
			var table_away: bool = stage.is_ar() and not stage.placed
			if is_human_turn() and mode == "versus" and (online or not table_away):
				_tick_clock(delta)
			if state == State.AIM:
				control.tick(delta)
				_update_aim_visuals()
				if online:
					_sample_aim(delta)
		State.AI_THINK:
			if online:
				if _ai_result.is_empty() and _remote_shot.is_empty() and not _await_result:
					_tick_clock(delta)      # the other player is thinking: their clock runs here too
				_update_remote(delta)
			else:
				if not fill_in.is_empty():
					_tick_clock(delta)      # a stand-in opponent's clock runs all through its turn, as a person's does
				_update_ai(delta)
		State.ROLLING:
			_rolling_time += delta
	var in_hand := state == State.BALL_IN_HAND and is_human_turn()
	if _hand_ring.visible != in_hand:
		_hand_ring.visible = in_hand
	_kitchen.visible = in_hand and break_placement()
	if in_hand:
		_hand_t += delta
		var cp := cue_ball_pos()
		var pulse := 0.5 + 0.5 * sin(_hand_t * 5.0)
		var k := 1.0 + 0.16 * pulse
		_hand_ring.position = Vector3(cp.x, 0.004, cp.y)
		_hand_ring.scale = Vector3(k, 0.12, k)
		(_hand_ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.82, 0.25, 0.55 + 0.45 * (1.0 - pulse))
		cue_view.visible = false
	stage.set_focus(cue_ball_pos(), control.yaw if control else 0.0)


func _tick_clock(delta: float) -> void:
	clocks[current] = maxf(0.0, clocks[current] - delta)
	if clocks[current] <= 60.0 and not _warned[current]:
		_warned[current] = true
		if plays_here(current):   # the opponent's clock warning is theirs
			message.emit(L.t("1 minute left on %s's clock!") % player_names[current], "warn")
		if plays_here(current) or not online:
			Sfx.play("warning", 0.8)
	if clocks[current] <= 0.0 and plays_here(current):
		_on_timeout()
	elif clocks[current] <= 0.0 and online:
		# the other player's time is up; their phone should say so. If it stays silent, this phone calls it.
		_late += delta
		if _late > 8.0:
			_on_timeout()


## The stick can't pass through the cushion / rail behind the cue ball: the lowest elevation for this aim.
func min_elevation(yaw: float, offset: Vector2) -> float:
	sim.ball_clearance = online or bool(Game.get_s("cue_over_balls"))      # the developer switch acts at once
	return sim.min_cue_elevation(cue_ball_pos(), yaw, offset)


## Is the stick's lowest height set by a ball in the way (rather than the rail) for this aim?
func cue_on_ball(yaw: float, offset: Vector2) -> bool:
	if not sim.ball_clearance:
		return false
	var by_ball := sim.min_ball_elevation(cue_ball_pos(), yaw, offset)
	return by_ball > 0.0 and by_ball >= sim.min_cue_elevation(cue_ball_pos(), yaw, offset) - 0.05


## A new tip position on the cue ball (spin) is refused when, at the height the stick has now, it would put
## the stick inside another ball. Moving it is fine whenever it clears.
func offset_allowed(o: Vector2) -> bool:
	if not sim.ball_clearance or control == null:
		return true
	return sim.balls_gap(cue_ball_pos(), control.yaw, o, cue_elevation()) >= 0.0


## The elevation the shot will really have: what the player asked for, but never through the rail.
func cue_elevation() -> float:
	return maxf(control.elevation, min_elevation(control.yaw, control.offset))


func _update_aim_visuals() -> void:
	var c := cue_index()
	var elev := cue_elevation()
	cue_view.aim(cue_ball_pos(), control.yaw, elev, control.offset, control.power)
	var p := maxf(control.power, 0.35)
	aim_guide.update_guide(sim, c, control.yaw, p, control.offset, elev, stage.table_scale())
	aim_guide.tick(sim, c, control.yaw, p, control.offset, elev, stage.table_scale())


func _physics_process(delta: float) -> void:
	if state != State.ROLLING or sim == null:
		return
	if _stroke_wait > 0.0:
		# v1.1.14: the stick travels from where it was drawn back to the ball; the balls start when it gets there
		_stroke_wait -= delta
		if _stroke_wait > 0.0:
			return
	sim.advance(delta * time_scale)
	Sfx.set_scene_scale(stage.table_scale())
	_consume_events()
	if not sim.path_changed.is_empty():
		_follow_path_changes()
	_update_roll_sound()
	_sync_views(delta * time_scale)
	if not sim.is_moving() and not sim.replay_pending():
		_on_balls_stopped()


func _sync_views(dt: float) -> void:
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED:
			views[i].sync(sim.pos[i], sim.spin[i], dt, sim.hz[i])


func _consume_events() -> void:
	# ball-ball clacks: loudest first, so that in a cluster (the break) the hard contacts are the ones heard
	var clacks := sim.events.filter(func(ev): return ev["type"] == "ball")
	if clacks.size() > 1:
		clacks.sort_custom(func(x, y): return float(x["speed"]) > float(y["speed"]))
	for ev in clacks:
		if not Sfx.impact("ball", float(ev["speed"]), _wpos((sim.pos[ev["a"]] + sim.pos[ev["b"]]) * 0.5, maxf(sim.hz[ev["a"]], sim.hz[ev["b"]]))):
			break
	for e in sim.events:
		match e["type"]:
			"cue":
				# tip on ball: harder strokes pick the harder recordings; an off-centre hit sounds thinner
				var off := control.offset.length() if control else 0.0
				Sfx.impact("cue", float(e["speed"]), _wpos(sim.pos[e["ball"]]), 0.0, 1.0 + 0.05 * off)
			"ball":
				var sp := float(e["speed"])
				if sp > 1.5:
					Game.vibrate(int(clampf(4.0 + sp * 2.5, 6.0, 22.0)))
			"cushion":
				Sfx.impact("cushion", float(e["speed"]), _wpos(sim.pos[e["ball"]]))
			"bounce":
				# ball landing on the cloth; the tiny hop of an ordinary, almost-level shot is silent
				Sfx.impact("bed", float(e["speed"]), _wpos(sim.pos[e["ball"]]))
			"off_table":
				var oi: int = e["ball"]
				views[oi].fly_off(e["vel"], float(e["h"]), float(e["vz"]))
				jumped_this_shot.append(sim.num[oi])
				Sfx.play("foul", 0.5)
				Game.vibrate(30)
			"pocket":
				var i: int = e["ball"]
				var pk: Dictionary = sim.table.pockets[e["pocket"]]
				views[i].drop_into(pk["hole"])
				_pocket_sound(pk["hole"], float(e["speed"]))
				Game.vibrate(25)
				potted_this_shot.append({"number": sim.num[i], "pocket": e["pocket"], "index": i})
				if sim.num[i] != 0:
					stat_pots[current] += 1
				_spark(pk["hole"], sim.num[i] == 0)
				ball_potted.emit(sim.num[i], current)
	sim.events.clear()


## Table point (+ height above the cloth) -> world position, for 3D sound.
func _wpos(p: Vector2, h := 0.0) -> Vector3:
	return stage.table_root.global_transform * Vector3(p.x, sim.R + h, p.y)


## A ball going down: a fast one cracks against the back of the pocket first, then the drop, then the
## ball running along the return rail underneath.
func _pocket_sound(hole: Vector2, speed: float) -> void:
	var at := _wpos(hole, -sim.R * 2.0)
	if speed > 1.6:
		Sfx.impact("cushion", speed * 0.8, at, -3.0, 0.9)
	Sfx.impact("pocket", speed, at)
	var tail := get_tree().create_timer(0.16 + randf() * 0.08)
	tail.timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			Sfx.impact("pocket_roll", 1.0, at, lerpf(-9.0, -3.0, clampf(speed / 3.0, 0.0, 1.0))))


## Rolling-on-cloth bed: louder and higher the faster the balls travel, placed where they are.
func _update_roll_sound() -> void:
	var total := 0.0
	var centre := Vector2.ZERO
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED or sim.hz[i] > 0.001:
			continue
		var v := sim.vel[i].length()
		if v > 0.02:
			total += v
			centre += sim.pos[i] * v
	if total <= 0.0:
		Sfx.rolling(0.0, _wpos(Vector2.ZERO))
		return
	Sfx.rolling(clampf(total / 7.0, 0.0, 1.0), _wpos(centre / total))


func _spark(at: Vector2, bad: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, -1.2, 0)
	p.scale_amount_min = 0.004
	p.scale_amount_max = 0.009
	# one material per colour and one tiny sphere, shared by every sparkle (nothing is built mid-shot)
	var col: Color = UIKit.CORAL if bad else stage.table_view.style.get("accent", UIKit.EMERALD)
	if not _spark_mats.has(col):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
		_spark_mats[col] = m
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.5
		_spark_mesh.height = 1.0
		_spark_mesh.radial_segments = 6
		_spark_mesh.rings = 3
	p.mesh = _spark_mesh
	p.material_override = _spark_mats[col]
	p.position = Vector3(at.x, 0.01, at.y)
	stage.table_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)   # (a connection goes away by itself if p is freed first)
	return p


## Draws everything a match can show at least once, behind a cover (the loading screen, or the short cover at the
## start of a match with gear not seen yet): the balls, every cue built so far, the ball-in-hand ring, the break
## area, the aim guide with its ghost ball, and the pocket sparkle in both colours. The phone builds their shaders
## now instead of in the middle of the first shot.
func warm_draw(frames := 2, extra: Array = []) -> void:
	_warming = true
	var keep_assist := aim_guide.assist
	var shown: Array = []
	cue_view.aim(cue_ball_pos(), 0.0, 0.0, Vector2.ZERO, 0.0)
	# everything on the table that is hidden now (other cues, the ball-in-hand ring, the break area, a control's
	# own 3D marker, a pocketed ball...) is shown for these frames
	for m in stage.table_root.find_children("*", "Node3D", true, false) + cue_view.models() + extra:
		if is_instance_valid(m) and not (m as Node3D).visible and not (m in shown):
			(m as Node3D).visible = true
			shown.append(m)
	aim_guide.assist = AimGuide.Guide.FULL
	aim_guide.update_guide(sim, cue_index(), 0.0, 0.6, Vector2.ZERO, 0.0, stage.table_scale())
	var sparks := [_spark(Vector2(sim.table.a * 0.3, 0.0), false), _spark(Vector2(-sim.table.a * 0.3, 0.0), true)]
	for i in frames:
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
	if not is_instance_valid(self) or not is_inside_tree():
		return
	for m in shown:
		if is_instance_valid(m):
			(m as Node3D).visible = false
	for sp in sparks:
		if is_instance_valid(sp):
			sp.queue_free()      # (they would still be falling when the cover lifts)
	aim_guide.assist = keep_assist
	aim_guide.hide_guide()
	cue_view.visible = state == State.AIM
	_warming = false


# ================================================================== shooting
func _on_shot_requested() -> void:
	if state != State.AIM:
		return
	fire(control.yaw, control.power, control.offset, control.elevation)


func fire(yaw: float, power: float, offset: Vector2, elev: float) -> void:
	undo_sim = sim.clone()
	cue_start = cue_ball_pos()
	last_shot = {"yaw": yaw, "power": power, "offset": offset, "elev": elev}
	elev = maxf(elev, min_elevation(yaw, offset))
	var mine_online := online and plays_here(current)
	var theirs := online and not plays_here(current)
	var pre := NetMatch.table_sum(sim)
	# the stick strikes from where it is drawn back to (before v1.1.14 it jumped to the ball first)
	var from_pull := clampf(cue_view.pull, 0.0, 1.0)
	if mine_online:
		# the last sample of this player's aiming is the stroke itself: the other phone's stick ends exactly here
		_take_aim_sample(yaw, elev, offset, from_pull, true)
		_path_shot = {"n": shots_total + 1, "yaw": yaw, "power": power, "offset": offset, "elev": elev, "cue": cue_start, "pre": pre, "trail": _aim_pending}
		_aim_pending = PackedFloat32Array()
		_path_slot = net.reserve("shot")       # (filled once its path is worked out, see _send_shot)
	var their_shot := _remote_shot if not _remote_shot.is_empty() else _ai_result
	if theirs and their_shot.has("pre") and int(their_shot["pre"]) != pre:
		net_drift += 1
		print("[net] the tables differed before the other player's shot %d" % (shots_total + 1))
	if theirs:
		NetMatch.use_path(sim, their_shot)     # their snapshots: this replay follows their table exactly
	else:
		NetMatch.drop_path(sim)
	_remote_shot = {}
	if not fill_in.is_empty() and not plays_here(current):
		si_last_track = _aim_buf
	_aim_buf = PackedFloat32Array()
	_aim_started = false
	if theirs:
		# their stroke is used up. (Before v1.1.14 it stayed, and if their report of how it ended was slow to
		# come, the waiting phone struck the same stroke a second time.)
		_ai_result = {}
	potted_this_shot.clear()
	jumped_this_shot.clear()
	sim.events.clear()
	rules.snapshot_before_shot(sim)
	cue_view.aim(cue_start, yaw, elev, offset, from_pull)
	_stroke_wait = cue_view.strike_anim()
	aim_guide.hide_guide()
	Game.vibrate(int(12 + power * 25))
	sim.strike(cue_index(), yaw, power, offset, elev)   # the break may be struck harder (PoolSim.break_scale)
	if mine_online:
		# the other phone gets snapshots of this shot's table on the way to rest; working them out takes a
		# moment (a break: ~0.05 s here, longer on a phone), so it is done on a thread
		var struck := sim.clone()
		_path_thread = Thread.new()
		_path_thread.start(func(): return NetMatch.make_path(struck))
	_set_break(false)
	shots_total += 1
	Game.bump_stat("shots")
	time_scale = 3.0 if (theirs and _catch_up) else 1.0
	if theirs and _catch_up:
		_stroke_wait = 0.0
	_catch_up = false
	_rolling_time = 0.0
	_set_state(State.ROLLING)
	shot_fired.emit()
	if stage.view == Stage.View.AIM:
		stage.set_view(Stage.View.OVERVIEW)
		stage.set_meta("restore_aim_view", true)


func fast_forward() -> void:
	if state == State.ROLLING:
		time_scale = 3.0


func _on_balls_stopped() -> void:
	time_scale = 1.0
	Sfx.rolling(0.0, _wpos(Vector2.ZERO))
	_sync_views(0.0)
	if stage.has_meta("restore_aim_view"):
		stage.remove_meta("restore_aim_view")
		stage.set_view(Stage.View.AIM)
	for p in potted_this_shot:
		if p["number"] != 0:
			Game.bump_stat("pots")
	if online:
		_rest_sum = NetMatch.table_sum(sim)
		if sim.path_end >= 0:
			net_path_fixes += sim.path_fixes
			if sim.path_fixes > 0:
				print("[net] shot %d: %d of the other phone's snapshots put this replay right" % [shots_total, sim.path_fixes])
			sim.path_fixes = 0
		NetMatch.drop_path(sim)
	if mode == "versus":
		_resolve_versus()
	else:
		_resolve_practice()
	stats_changed.emit()


func _resolve_practice() -> void:
	_respot_jumped(true)
	if sim.st[cue_index()] == PoolSim.ST_POCKETED:
		message.emit("Cue ball off the table — back on the table." if 0 in jumped_this_shot else "Scratch — cue ball back on the table.", "warn")
		_respawn_cue(Rack.break_spot(sim))
	elif not jumped_this_shot.is_empty():
		message.emit("Ball off the table — re-spotted.", "warn")
	var left := sim.balls_on_table(PoolSim.K_OBJECT).size() + sim.balls_on_table(PoolSim.K_EIGHT).size()
	if left == 0 and not tutorial:
		# a natural break: the rack-cleared screen comes up (Rack again / Menu), as a match's score screen would
		Sfx.play("win", 0.7)
		Game.vibrate(40)
		_set_state(State.OVER)
		rack_cleared.emit({"shots": shots_total - _rack_shots0, "seconds": int(Time.get_ticks_msec() / 1000.0 - _rack_t0)})
		return
	if not potted_this_shot.is_empty() and sim.st[cue_index()] != PoolSim.ST_POCKETED:
		message.emit(["Nice!", "Clean!", "Great shot!", "Smooth!"][randi() % 4], "good")
	_start_turn()


func _resolve_versus() -> void:
	var remote := online and not plays_here(rules.current)
	if remote and _remote_result.is_empty():
		# the shooter's phone says how the shot ended; our copy of it has stopped first, so wait for the report
		_await_result = true
		_set_state(State.AI_THINK)
		return
	var first_num := -1
	if sim.first_hit >= 0:
		first_num = sim.num[sim.first_hit]
	var nums := []
	for p in potted_this_shot:
		nums.append(p["number"])
	var shooter := rules.current
	var was_open := rules.open_table()
	_respot_jumped(false)   # object balls go back before the rules count what's left
	var r := rules.evaluate(sim, first_num, nums, sim.cushion_after_contact, jumped_this_shot)
	if xp_track and plays_here(shooter):
		# XP is counted for the player on this phone only
		xp_track.shot(int(r.get("xp_balls", 0)), bool(r.get("xp_eight", false)))
		if not r.get("keep_turn", false):
			xp_track.turn_over()
	if r.get("respot_eight", false):
		_respot_eight()
	if not r["game_over"] and sim.st[cue_index()] == PoolSim.ST_POCKETED:
		_respawn_cue(Rack.break_spot(sim))
	if remote:
		# the two phones normally agree to the last digit; if they ever do not, the shooter's phone is right
		var auth := _remote_result
		_remote_result = {}
		if int(auth.get("sum", _rest_sum)) != _rest_sum:
			net_drift += 1      # (a count for the tests and the log; the report below puts it right)
			print("[net] shot %d of the other player ended differently here; using their result" % int(auth.get("n", 0)))
		NetMatch.apply_result(auth, sim, rules, clocks)
		r["game_over"] = rules.winner >= 0
		r["foul"] = bool(auth.get("foul", r["foul"]))
		r["keep_turn"] = bool(auth.get("keep", r["keep_turn"]))
		_resync_views()
	elif online:
		net.send("result", NetMatch.pack_result(sim, rules, clocks, r, shots_total, _rest_sum))
	if r["foul"]:
		stat_fouls[shooter] += 1
	if r["game_over"]:
		_finish(rules.winner, rules.win_reason)
		return
	if was_open and not rules.open_table():
		groups_set.emit()
	if r["foul"]:
		Sfx.play("foul", 0.7)
	var notice := rules.notice_for(r, plays_here(shooter), local_seat())
	if notice != "":
		message.emit(notice, "warn" if r["foul"] else ("good" if r["keep_turn"] and plays_here(shooter) else "info"))
	current = rules.current
	if current != shooter:
		_warned[current] = _warned[current] and clocks[current] <= 60.0
	_start_turn()


## `forfeit`: the other player left - this player wins and is paid as if they had cleared the rest of the rack.
func _finish(winner: int, reason: String, forfeit := false) -> void:
	_set_state(State.OVER)
	var human_won := not vs_ai or winner == 0
	if vs_ai and fill_in.is_empty():
		Game.record_ai_game(ai_level, winner == 0)
	Sfx.play("win" if human_won else "lose", 0.9)
	Game.vibrate(60)
	var info := {"mode": "versus", "winner": winner, "winner_name": player_names[winner],
		"reason": reason, "shots": shots_total, "vs_ai": vs_ai and fill_in.is_empty(), "ai_level": ai_level, "online": looks_online(), "seat": local_seat(),
		"opp_name": player_names[1 - local_seat()],
		"pots": stat_pots[local_seat()], "opp_pots": stat_pots[1 - local_seat()], "fouls": stat_fouls[local_seat()],
		"why": "opponent_left" if forfeit else ("connection_lost" if reason == "The connection was lost" else (end_why if end_why != "" else "eight_ball"))}
	if xp_track:
		xp_track.won = winner == local_seat()
		xp_track.match_shots = shots_total
		if forfeit and xp_track.won:
			var g: int = rules.groups[local_seat()]
			xp_track.forfeit = true
			xp_track.forfeit_balls = rules.remaining_of(sim, g) if g >= 0 else 7
		info["xp"] = xp_track.summary(xp_mode())
	if online and net:
		print("[net] match over (%s): %d requests on %d connections; %d snapshots put replays right; %d repeated events left out; XP %s" % [
			reason, Net.lane_requests, Net.lane_opened, net_path_fixes, net.dropped, str(info.get("xp", {}).get("total", 0))])
	game_over.emit(info)


func _on_timeout() -> void:
	if state == State.OVER:
		return
	rules.timeout(current)
	if online:
		net.send("over", {"winner": rules.winner, "why": "time"})
	end_why = "timeout"
	_finish(rules.winner, L.t("%s ran out of time") % player_names[current])


# ================================================================== input / ball in hand
func handle_input(ev: InputEvent) -> bool:
	if state == State.BALL_IN_HAND and is_human_turn():
		# Tap or drag as often as you like; the ball only becomes final with the Place button
		# (confirm_cue_placement). One finger only: two fingers are camera / AR gestures.
		if (ev is InputEventScreenTouch and ev.pressed) or ev is InputEventScreenDrag:
			if ev.index != 0:
				return false
			var p = stage.screen_to_table(ev.position)
			if p != null:
				move_cue_ball(p)
			return true
		return ev is InputEventScreenTouch
	if state == State.ROLLING:
		if ev is InputEventScreenTouch and ev.pressed and _rolling_time > 0.8:
			fast_forward()
			return true
		return false
	if state == State.AIM and control and is_human_turn():
		return control.handle_input(ev)
	return false


## Practice: move the cue ball any time. Versus: only with ball in hand (before the shot).
## Pressing the hand button again while placing confirms, like the Place button.
func start_ball_in_hand() -> void:
	if state == State.BALL_IN_HAND:
		confirm_cue_placement()
	elif state == State.AIM and is_human_turn() and (mode == "practice" or rules.ball_in_hand or _break_pending):
		placing_cue = true
		_set_state(State.BALL_IN_HAND)


## The break has not been played yet (the rack is untouched).
func break_pending() -> bool:
	return _break_pending


## In a match the cue ball is placed behind the head string for the break. Practice stays free.
func break_placement() -> bool:
	return _break_pending and mode == "versus"


func _set_break(on: bool) -> void:
	_break_pending = on
	sim.break_shot = on


## Ball in hand: put the cue ball at (or as close as legally possible to) a table point.
func move_cue_ball(p: Vector2) -> void:
	var c := cue_index()
	var spot: Variant = _legal_cue_spot(p)
	if spot == null:
		return
	if (spot as Vector2).distance_to(sim.pos[c]) > sim.R * 0.5:
		Sfx.play("tick", 0.25)
	sim.pos[c] = spot
	sim.vel[c] = Vector2.ZERO
	sim.spin[c] = Vector3.ZERO
	views[c].place(spot)


## Nearest legal place for the cue ball to `p`: on the cloth, not overlapping another ball. A finger on
## top of another ball slides the cue ball to just beside it. null when there is no room right there.
func _legal_cue_spot(p: Vector2) -> Variant:
	var c := cue_index()
	var lim := Vector2(sim.table.a - sim.R, sim.table.b - sim.R)
	var hi := lim
	if break_placement():
		hi.x = Rack.kitchen_limit(sim)   # the break: behind the head string (the line itself is not behind it)
	var q := p.clamp(-lim, hi)
	for k in 12:
		if sim.is_spot_free(q, c):
			return q
		# push out of the nearest overlapping ball
		var near := -1
		var nd := INF
		for i in sim.n:
			if i == c or sim.st[i] == PoolSim.ST_POCKETED:
				continue
			var d := sim.pos[i].distance_to(q)
			if d < nd:
				nd = d
				near = i
		if near < 0:
			break
		var away := q - sim.pos[near]
		if away.length() < 1e-5:
			away = sim.pos[c] - sim.pos[near]
		if away.length() < 1e-5:
			away = Vector2(1, 0)
		q = (sim.pos[near] + away.normalized() * (sim.R * 2.0 + 0.0015 * (k + 1))).clamp(-lim, hi)
	return null


## The Place button: the cue ball stays where it is and aiming starts.
func confirm_cue_placement() -> void:
	if state != State.BALL_IN_HAND:
		return
	placing_cue = false
	placed_this_turn = true
	if online:
		net.send("place", {"p": cue_ball_pos()})
	control.reset_for_turn(_default_aim())
	Sfx.play("ui_tap", 0.6)
	_set_state(State.AIM)


func undo() -> void:
	if mode != "practice" or undo_sim == null or state != State.AIM:
		return
	sim = undo_sim
	undo_sim = null
	_break_pending = sim.break_shot   # undoing the break makes the next shot the break again
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED:
			views[i].visible = false
		else:
			views[i].place(sim.pos[i])
	message.emit("Shot undone", "info")
	_start_turn()


func reset_rack() -> void:
	_rack_shots0 = shots_total
	_rack_t0 = Time.get_ticks_msec() / 1000.0
	match_seed = randi()
	Rack.rack_eight_ball(sim, match_seed)
	rules = EightBall.new()
	_set_break(true)
	_build_views()
	_start_turn(true)


# ================================================================== AI
# ================================================================== the other player, over the network
## An online match. Each phone plays its own player's shots on its own table, at once, and tells the other
## phone the exact stroke; the other phone replays it. When the balls stop, the shooter's phone reports
## where every ball lies and what the rules say, and the other phone adopts that, so the two tables can
## never drift apart. The host (the phone with the faster connection) is only the referee for the clocks.
func _start_remote() -> void:
	_ai_result = {}
	_ai_anim = 0.0
	_ai_from_yaw = control.yaw
	_aim_buf = PackedFloat32Array()
	_aim_cursor = -1.0
	_remote_shot = {}
	_aim_started = false


## Every frame of an online match: take in what the other phone sent, notice a lost connection.
## The other player's events are played back strictly in order, each one only when this phone is ready for
## it (their next stroke waits until the replay of the one before has finished), so nothing is ever skipped
## even when they shoot faster than this phone can show it.
func _net_tick(_delta: float) -> void:
	net.fast = not plays_here(current)       # quick questions only while the other player aims or shoots
	_net_q.append_array(net.take())
	while not _net_q.is_empty() and state != State.OVER:
		var ev: Dictionary = _net_q[0]
		var d: Dictionary = ev["data"]
		var ready := not plays_here(current) and state == State.AI_THINK and _ai_result.is_empty() and _remote_shot.is_empty() and not _await_result
		match str(ev["type"]):
			"over":
				# the match ended on the other phone: they left (we win), they saw this phone go quiet for too
				# long (we lose), or a clock ran out. Who hosts makes no difference.
				var w := int(d.get("winner", net_seat))
				rules.winner = w
				var why := str(d.get("why", ""))
				var reason := "Your opponent left the match" if w == net_seat else "The connection was lost"
				if why == "time":
					reason = L.t("%s ran out of time") % player_names[1 - w]
					end_why = "timeout"
				elif w != net_seat:
					Analytics.connection_lost("match", net.host)    # (the other phone saw this one go quiet)
				_finish(w, reason, w == net_seat and why != "time")
			"cancel":
				# they left the ready-up (24 Nov 2026) just as this phone started the match: if nobody has played a
				# shot, there was no match - nobody wins, no XP, back to looking (main._on_match_void)
				if shots_total == 0:
					_set_state(State.OVER)
					match_void.emit()
					return
				rules.winner = net_seat
				_finish(net_seat, "Your opponent left the match", true)
			"aim":
				# how their cue moved (only for the turn being played: older batches are dropped)
				if not plays_here(current) and int(d.get("turn", shots_total)) == shots_total:
					_aim_feed(d.get("s"))
			"place":
				if not ready:
					return
				if d.has("p"):
					_put_cue(d["p"], true)
			"shot":
				if not ready:
					return
				if d.has("cue"):
					_put_cue(d["cue"])
				# running behind (their next stroke is already here)? then show this one briskly
				var behind := _net_q.any(func(x): return x != ev and str(x["type"]) == "shot")
				_catch_up = behind
				_aim_feed(d.get("trail"))
				if _aim_buf.is_empty():
					# none of their aiming came (an older version, a lost batch): the stick turns to the shot
					# and draws back by itself, then strikes
					_ai_result = {"yaw": float(d["yaw"]), "power": float(d["power"]), "offset": d["offset"], "elev": float(d["elev"])}
					for k in ["pre", "path", "plen"]:
						if d.has(k):
							_ai_result[k] = d[k]
					_ai_from_yaw = control.yaw
					_ai_anim = 1.35 if behind else 0.55
				else:
					_remote_shot = d          # struck when the playback of their aiming gets to its end
			"result":
				if not _await_result:
					return      # our replay of that shot is still running
				_await_result = false
				_remote_result = d
				_net_q.pop_front()
				_resolve_versus()
				continue
		_net_q.pop_front()
	if state == State.OVER:
		return
	if net.opp_seen > 45.0:
		# the other phone stopped asking the server for news (app closed, phone off): this player wins. The
		# server is told too, so that phone - should it come back - shows the match as lost, not as a second win.
		rules.winner = net_seat
		net.send("over", {"winner": net_seat, "why": "away"})
		_finish(net_seat, "Your opponent left the match", true)
	elif net.silent > 45.0:
		Analytics.connection_lost("match", net.host)
		rules.winner = 1 - net_seat
		_finish(1 - net_seat, "The connection was lost")


## The cue ball exactly where the other phone has it (glide: it slides there, for their ball in hand).
func _put_cue(p: Vector2, glide := false) -> void:
	var c := cue_index()
	var was_on: bool = sim.st[c] != PoolSim.ST_POCKETED and views[c].visible
	sim.pos[c] = p
	sim.vel[c] = Vector2.ZERO
	sim.spin[c] = Vector3.ZERO
	sim.st[c] = PoolSim.ST_REST
	sim.pocket_of[c] = -1
	if glide and was_on:
		views[c].glide_to(p)
	else:
		views[c].place(p)


## While the other player aims, their stick moves as theirs did: their samples are played back at their own
## pace, a moment behind (so a late batch doesn't make it stop and start). When their stroke has come, the
## playback runs on to its end - the stroke's own aim and draw - and the stick strikes from there.
func _update_remote(delta: float) -> void:
	if _await_result:
		return
	if not _ai_result.is_empty():
		_update_ai(delta)
		return
	if _aim_buf.is_empty():
		cue_view.aim(cue_ball_pos(), control.yaw, min_elevation(control.yaw, Vector2.ZERO), Vector2.ZERO, 0.0)
		return
	var newest: float = _aim_buf[_aim_buf.size() - 6]
	var behind := newest - _aim_cursor
	var rate := 1.0
	if not _remote_shot.is_empty():
		rate = 3.0 if _catch_up else (2.0 if behind > 0.6 else 1.25)
	elif behind > 0.9:
		rate = 1.5                 # fallen behind (a slow answer from the server): catch up gently
	_aim_cursor = minf(_aim_cursor + delta * rate, newest)
	var a := _aim_at(_aim_cursor)
	if _aim_started:
		remote_max_step = maxf(remote_max_step, absf(wrapf(float(a[0]) - control.yaw, -PI, PI)))
	_aim_started = true
	control.yaw = a[0]
	var off := Vector2(a[2], a[3])
	cue_view.aim(cue_ball_pos(), a[0], maxf(a[1], min_elevation(a[0], off)), off, a[4])
	if not _remote_shot.is_empty() and _aim_cursor >= newest:
		var sh := _remote_shot
		remote_lineup.append([absf(wrapf(float(a[0]) - float(sh["yaw"]), -PI, PI)), absf(float(a[4]) - float(sh["power"]))])
		fire(float(sh["yaw"]), float(sh["power"]), sh["offset"], float(sh["elev"]))


## Takes in a batch of the other player's samples (only ones newer than what is there).
func _aim_feed(samples) -> void:
	if typeof(samples) != TYPE_PACKED_FLOAT32_ARRAY or samples.size() < 6:
		return
	var last_t := -INF if _aim_buf.is_empty() else float(_aim_buf[_aim_buf.size() - 6])
	for k in range(0, samples.size() - 5, 6):
		if samples[k] > last_t:
			if _aim_buf.is_empty():
				_aim_cursor = samples[k]
			_aim_buf.append_array(samples.slice(k, k + 6))
			last_t = samples[k]
	# what has been played is let go (the sample just before the playback point is kept)
	while _aim_buf.size() >= 12 and _aim_buf[6] <= _aim_cursor:
		_aim_buf = _aim_buf.slice(6)


## Their stick at their time t: [yaw, elevation, tip x, tip y, pull], between the two samples around t.
func _aim_at(t: float) -> Array:
	var count := _aim_buf.size() / 6
	var i := 0
	while i + 1 < count and _aim_buf[(i + 1) * 6] <= t:
		i += 1
	var a := i * 6
	if i + 1 >= count:
		return [_aim_buf[a + 1], _aim_buf[a + 2], _aim_buf[a + 3], _aim_buf[a + 4], _aim_buf[a + 5]]
	var b := a + 6
	var k := clampf((t - _aim_buf[a]) / maxf(_aim_buf[b] - _aim_buf[a], 1e-4), 0.0, 1.0)
	return [lerp_angle(_aim_buf[a + 1], _aim_buf[b + 1], k), lerpf(_aim_buf[a + 2], _aim_buf[b + 2], k),
		lerpf(_aim_buf[a + 3], _aim_buf[b + 3], k), lerpf(_aim_buf[a + 4], _aim_buf[b + 4], k), lerpf(_aim_buf[a + 5], _aim_buf[b + 5], k)]


## This player's aiming, 15 samples a second (only when something moved), sent every 0.4 s.
func _sample_aim(delta: float) -> void:
	_aim_clock += delta
	_aim_tick -= delta
	if _aim_tick <= 0.0:
		_aim_tick = maxf(_aim_tick + 1.0 / 15.0, 0.0)
		_take_aim_sample(control.yaw, cue_elevation(), control.offset, control.power)
	_aim_send_t -= delta
	if _aim_send_t <= 0.0 and not _aim_pending.is_empty():
		_aim_send_t = 0.4
		net.send("aim", {"s": _aim_pending, "turn": shots_total})
		_aim_pending = PackedFloat32Array()


func _take_aim_sample(yaw: float, elev: float, off: Vector2, pull: float, always := false) -> void:
	if not always and _aim_last.size() == 6 and absf(wrapf(yaw - _aim_last[1], -PI, PI)) < 0.0004 and absf(elev - _aim_last[2]) < 0.05 \
			and absf(off.x - _aim_last[3]) < 0.004 and absf(off.y - _aim_last[4]) < 0.004 and absf(pull - _aim_last[5]) < 0.003:
		return
	if _aim_last.size() == 6 and _aim_clock - _aim_last[0] > 0.1:
		# it had been still: that pose is held until a moment ago, so the other stick doesn't drift through the pause
		var hold := _aim_last.duplicate()
		hold[0] = _aim_clock - 1.0 / 15.0
		_aim_pending.append_array(hold)
	_aim_last = PackedFloat32Array([_aim_clock, yaw, elev, off.x, off.y, pull])
	_aim_pending.append_array(_aim_last)


## A new turn of this player online: their aiming starts afresh.
func _reset_aim_stream() -> void:
	_aim_clock = 0.0
	_aim_tick = 0.0
	_aim_pending = PackedFloat32Array()
	_aim_last = PackedFloat32Array()
	_aim_send_t = 0.15


## This phone's shot, with its path, goes out (in its place in the queue) once the thread has worked it out.
func _send_shot() -> void:
	var p: Dictionary = _path_thread.wait_to_finish()
	_path_thread = null
	var d := _path_shot
	d.merge(p)
	_path_shot = {}
	if net and not _path_slot.is_empty():
		net.fill(_path_slot, d)
	_path_slot = []


## A snapshot of the shooter's table put a ball into a pocket that went in a hair differently here (or kept one
## out that dropped here): its picture follows, and so does what this shot potted.
func _follow_path_changes() -> void:
	for i in sim.path_changed:
		if sim.st[i] == PoolSim.ST_POCKETED:
			if sim.pocket_of[i] >= 0:
				views[i].drop_into(sim.table.pockets[sim.pocket_of[i]]["hole"])
				potted_this_shot.append({"number": sim.num[i], "pocket": sim.pocket_of[i], "index": i})
			else:
				views[i].visible = false
				if not sim.num[i] in jumped_this_shot:
					jumped_this_shot.append(sim.num[i])
		else:
			views[i].place(sim.pos[i])
			potted_this_shot = potted_this_shot.filter(func(x): return int(x["index"]) != i)
			jumped_this_shot.erase(sim.num[i])
	sim.path_changed.clear()


## Every ball's picture where the simulator has the ball (after adopting the other phone's report). A ball that
## is off by a little slides there instead of jumping.
func _resync_views() -> void:
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED:
			views[i].visible = false
		elif views[i].visible and not views[i].falling:
			views[i].glide_to(sim.pos[i])
		else:
			views[i].place(sim.pos[i])


func _start_ai(ball_in_hand: bool) -> void:
	_ai_result = {}
	_ai_anim = 0.0
	_ai_think = 0.0
	_ai_from_yaw = control.yaw
	var own := []
	var g: int = rules.groups[current]
	for n in range(1, 16):
		if n != 8 and (g == EightBall.Group.NONE or EightBall.group_of(n) == g):
			own.append(n)
	var legal := rules.legal_targets(sim, current)
	var eight_ok := legal == [8]
	var ai := AIPlayer.new(ai_level)
	var c := cue_index()
	var from_p := cue_ball_pos()
	if ball_in_hand:
		_respawn_cue(ai.choose_placement(sim.clone(), own))
	elif not fill_in.is_empty() and rules.is_break and _break_pending and _si_rng.randf() < 0.55:
		# a person often moves the cue ball along behind the line before breaking
		var want := Vector2(Rack.kitchen_limit(sim) - _si_rng.randf_range(0.0, 0.3),
			_si_rng.randf_range(-0.65, 0.65) * (sim.table.b - sim.R))
		var spot: Variant = _legal_cue_spot(want)
		if spot != null:
			sim.pos[c] = spot
	if not fill_in.is_empty():
		# the stand-in plays its turn the way an online opponent's turn is shown (FillIn.aim_track)
		_si_t = 0.0
		_si_place = []
		_si_place_i = 0
		_si_aim_from = -1.0
		_aim_buf = PackedFloat32Array()
		var to := cue_ball_pos()
		if to.distance_to(from_p) > sim.R * 0.25 and _standin_budget() >= 4.0:
			views[c].place(from_p)
			for wp in FillIn.place_path(_si_rng, from_p, to):
				var q: Variant = _legal_cue_spot(wp[1])
				_si_place.append([wp[0], q if q != null else to])
			_si_place[-1][1] = to
	var snapshot := sim.clone()
	snapshot.record_events = false
	var is_break := rules.is_break
	_ai_thread = Thread.new()
	_ai_thread.start(func(): return ai.choose(snapshot, legal, own, eight_ok, is_break))


## A stand-in's turn (Play Online found nobody): the cue ball dragged to its place when it has ball in hand, then
## the stick moved by FillIn.aim_track through the same playback as a real online opponent's (_aim_at), then the stroke.
func _update_standin(delta: float) -> void:
	_si_t += delta
	var c := cue_index()
	while _si_place_i < _si_place.size() and float(_si_place[_si_place_i][0]) <= _si_t:
		views[c].glide_to(_si_place[_si_place_i][1], 0.1)
		if _si_place_i == _si_place.size() - 1:
			Sfx.play("tick", 0.25)
		_si_place_i += 1
	var placing := _si_place_i < _si_place.size()
	cue_view.visible = not placing
	if _ai_result.is_empty():
		if _ai_thread and not _ai_thread.is_alive():
			_ai_result = _ai_thread.wait_to_finish()
			_ai_thread = null
		if not placing:
			cue_view.aim(cue_ball_pos(), control.yaw, min_elevation(control.yaw, Vector2.ZERO), Vector2.ZERO, 0.0)
		return
	if _aim_buf.is_empty():
		var place_end: float = float(_si_place[-1][0]) if not _si_place.is_empty() else 0.0
		var start := maxf(_si_t, place_end + _si_rng.randf_range(0.3, 0.9))
		_aim_buf = FillIn.aim_track(_si_rng, control.yaw, float(_ai_result["yaw"]), float(_ai_result["elev"]),
			_ai_result["offset"], float(_ai_result["power"]), rules.is_break, ai_level, start,
			_shot_trickiness(float(_ai_result["yaw"]), _ai_result["offset"], float(_ai_result["elev"])), _standin_budget() - start)
		_si_aim_from = start
	if placing or _si_t < _si_aim_from:
		if not placing:
			cue_view.aim(cue_ball_pos(), control.yaw, min_elevation(control.yaw, Vector2.ZERO), Vector2.ZERO, 0.0)
		return
	var a := _aim_at(_si_t)
	control.yaw = a[0]
	var off := Vector2(a[2], a[3])
	cue_view.aim(cue_ball_pos(), a[0], maxf(a[1], min_elevation(a[0], off)), off, a[4])
	if _si_t >= float(_aim_buf[_aim_buf.size() - 6]):
		fire(float(_ai_result["yaw"]), float(_ai_result["power"]), _ai_result["offset"], float(_ai_result["elev"]))


## How long the stand-in may take over this turn: its clock shared out over the shots it may still need, with a
## minute kept back - so however the match goes, it never runs out of time.
func _standin_budget() -> float:
	if clocks[current] < 90.0:
		return clampf(clocks[current] / 18.0, 0.8, 3.0)      # (short of time: brisk, like a person in a hurry)
	var left: float = clocks[current] - 60.0
	var own_left := 7
	if rules.groups[current] >= 0:
		own_left = rules.remaining_of(sim, rules.groups[current])
	var shots_left := 3.0 + 2.2 * float(own_left + 1)
	return clampf(left / shots_left, 2.5, 30.0)


## 0 (easy) .. 1 (tricky): a long shot, a thin cut, a ball in the way or nothing hit straight (a bank or a safety),
## spin, the stick raised.
func _shot_trickiness(yaw: float, offset: Vector2, elev: float) -> float:
	var c := cue_index()
	var o := sim.pos[c]
	var d := Vector2(cos(yaw), sin(yaw))
	var best := INF
	var b_perp := 0.0
	for i in sim.n:
		if i == c or sim.st[i] == PoolSim.ST_POCKETED:
			continue
		var rel: Vector2 = sim.pos[i] - o
		var along := rel.dot(d)
		var perp := absf(rel.cross(d))
		if along > 0.0 and perp < 2.0 * sim.R and along < best:
			best = along
			b_perp = perp
	var k := 0.0
	if best == INF:
		k += 0.55                                                     # no ball straight on: a bank, a kick or a safety
	else:
		k += 0.35 * clampf(best / (2.0 * sim.table.a), 0.0, 1.0)      # long
		k += 0.45 * clampf(b_perp / (2.0 * sim.R), 0.0, 1.0)          # thin cut
	k += 0.15 * clampf(offset.length() / 0.5, 0.0, 1.0) + (0.2 if elev > 0.05 else 0.0)
	return clampf(k, 0.0, 1.0)


func _update_ai(delta: float) -> void:
	if not fill_in.is_empty() and not online:
		_update_standin(delta)
		return
	if _ai_result.is_empty():
		if _ai_thread and not _ai_thread.is_alive():
			_ai_result = _ai_thread.wait_to_finish()
			_ai_thread = null
			_ai_from_yaw = control.yaw
			if not fill_in.is_empty():
				# a person takes a moment to look the table over (less for the break)
				_ai_think = randf_range(0.6, 1.5) if rules.is_break else randf_range(1.2, 3.8)
		cue_view.aim(cue_ball_pos(), control.yaw, min_elevation(control.yaw, Vector2.ZERO), Vector2.ZERO, 0.0)
		return
	if _ai_think > 0.0:
		_ai_think -= delta
		var look := _ai_from_yaw + sin(_ai_think * 1.6) * 0.16      # the stick drifts as they consider the shot
		control.yaw = look
		cue_view.aim(cue_ball_pos(), look, min_elevation(look, Vector2.ZERO), Vector2.ZERO, 0.0)
		if _ai_think <= 0.0:
			_ai_from_yaw = control.yaw
		return
	_ai_anim += delta / (1.35 if not fill_in.is_empty() else 1.0)
	var k := clampf(_ai_anim / 1.0, 0.0, 1.0)
	var target_yaw: float = _ai_result["yaw"]
	var y := lerp_angle(_ai_from_yaw, target_yaw, ease(k, -2.2))
	control.yaw = y
	var pull := clampf((_ai_anim - 1.0) / 0.5, 0.0, 1.0) * float(_ai_result["power"])
	cue_view.aim(cue_ball_pos(), y, maxf(float(_ai_result["elev"]), min_elevation(y, _ai_result["offset"])), _ai_result["offset"], pull)
	if _ai_anim > 1.7:
		fire(target_yaw, _ai_result["power"], _ai_result["offset"], _ai_result["elev"])


func _exit_tree() -> void:
	if _ai_thread:
		_ai_thread.wait_to_finish()
	if _path_thread:
		_send_shot()              # the shot goes out before the leaving message (which follows it in the queue)
	if online and net:
		if state != State.OVER:
			net.send("over", {"winner": 1 - net_seat, "why": "left"})    # walking away from a live match gives it up
		net.close()
	if Game.settings_changed.is_connected(_on_setting):
		Game.settings_changed.disconnect(_on_setting)
	# The balls, cue and guide live under the stage's table (which outlives the match): remove them,
	# otherwise the next match draws its rack on top of this one's leftover balls.
	for v in views:
		if is_instance_valid(v):
			v.queue_free()
	views.clear()
	for n in [cue_view, aim_guide, _hand_ring, _kitchen]:
		if is_instance_valid(n):
			n.queue_free()
	if control:
		control.deactivate()
	Sfx.stop_table()


# ================================================================== HUD queries
func info() -> Dictionary:
	var d := {"mode": mode, "current": current, "clocks": clocks, "names": player_names, "state": state}
	d["groups"] = rules.groups
	d["open"] = rules.open_table()
	d["remaining"] = [rules.remaining_of(sim, rules.groups[0]) if rules.groups[0] >= 0 else 7, rules.remaining_of(sim, rules.groups[1]) if rules.groups[1] >= 0 else 7]
	d["ball_in_hand"] = rules.ball_in_hand
	d["break"] = _break_pending
	d["potted"] = rules.pocketed_by
	return d
