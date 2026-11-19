class_name Tutorial
extends Control
## v1.1.15 tutorial. Randy: "5 pretty fast tutorial versions so people can learn how to play first, they should be
## skippable" ... "i dont just want text tutorials... i want an in game tutorial with objectives which must be met
## one at a time." It runs on the real table (a practice match with `tutorial` set): the table is arranged for one
## objective, the next objective comes only when this one is met, Skip leaves at any time (and doesn't count), and the
## end gives the gift chest that opens at once. Five versions (VERSIONS) share the objectives and differ in which
## objectives and how they are shown:
##   0 Coach marks      - a pointer at the control to use, five objectives (the one the game plays)
##   1 Three challenges - a checklist of three set-up shots
##   2 Quick start      - three objectives, the fastest
##   3 Watch, then you  - each shot is shown first (the cue turns to the right line), then the player copies it
##   4 Mini match       - a 3-ball game with a coach who talks the player through it (it ends on the 8, potted
##                        after the coach's foul gives ball in hand)

signal finished(done: bool)

const VERSIONS := [
	{"name": "Coach marks", "steps": ["aim", "pot", "cut", "draw", "eight"]},     # (Randy, 18 Nov: no ball-in-hand step)
	{"name": "Three challenges", "steps": ["pot", "draw", "hand"]},
	{"name": "Quick start", "steps": ["aim", "pot", "eight"]},
	{"name": "Watch, then you", "steps": ["pot", "cut", "draw"]},
	{"name": "Mini match with a coach", "steps": ["break", "pot1", "pot2", "hand"]},
]
## What each objective asks, in the order: title, how to do it, and (version 4) what the coach says.
const TEXT := {
	"aim": ["Aim at the yellow ball", "Turn the cue until it points at the yellow 1-ball.", "Let's start with aiming: turn the cue to the yellow ball."],
	"pot": ["Pot the yellow ball", "Send the yellow ball into the far pocket.", "Now pot it into the far pocket."],
	"cut": ["Pot a ball at an angle", "Hit the yellow ball on its side to send it into the corner pocket.", "Angles next: clip it into the corner."],
	"draw": ["Pot it with backspin", "Drag the dot on the white ball (bottom left) down, then shoot: the white ball comes back.", "Hit low on the white ball and it comes back."],
	"hand": ["Ball in hand", "After a foul you get ball in hand: drag the white ball to a clear spot, then tap Place ball.", "My foul! Ball in hand: drag the white ball anywhere, then tap Place ball."],
	"hand2": ["Ball in hand", "Now pot the yellow ball from there.", "Now pot the yellow one from there."],
	"hand2_8": ["Sink the 8-ball", "The black 8 is always the last ball. Pot it from there to finish.", "Now the 8 from there. Sink it to win!"],
	"eight": ["Sink the 8-ball", "The black 8 is always the last ball. Pot it to finish.", "Last ball: the 8. Sink it to win!"],
	"break": ["Break the rack", "Shoot hard into the balls: full power.", "Let's play a quick 3-ball game. Break!"],
	"pot1": ["Pot the yellow 1", "Any pocket. Take your time: there's no clock here.", "Nice break! Now pot the yellow 1."],
	"pot2": ["Pot the blue 2", "Any pocket.", "Good! Now the blue 2."],
}
const AIM_TOL := 0.035          # radians (2°)
const MAX_TRIES := 2            # misses before a free-play objective gets an easier set-up

var version := 0
var main: Node
var game: PoolGame
var hud: Node
var stage: Stage
var step := 0
var phase := 0                  # (hand: 0 = move the ball, 1 = pot from there)
var tries := 0
var _busy := false              # between objectives: the table is being set up
var _shot_on := false
var _aim_hold := 0.0
var _cue_from := Vector2.ZERO
var _dir := Vector2.ZERO
var _max_proj := 0.0
var _hand_from := Vector2.ZERO
var _placed_at := Vector2.ZERO    # (ball in hand: where the player put the white ball)
var _was_state := -1
var _target_yaw := 0.0

# the look
var _card: PanelContainer
var _count: Label
var _title: Label
var _how: Label
var _dots: HBoxContainer
var _check: IconGlyph
var _skip: Button
var _list: VBoxContainer       # version 1
var _marks := false             # version 0: the control to use is outlined and pulses
var _point_at: Control
var _coach: Label              # version 4
var _t := 0.0
var _fitted := false


func _init(p_main: Node, p_version: int) -> void:
	main = p_main
	version = clampi(p_version, 0, VERSIONS.size() - 1)
	name = "Tutorial"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func steps() -> Array:
	return VERSIONS[version]["steps"]


func current() -> String:
	var id: String = steps()[mini(step, steps().size() - 1)]
	if id == "hand" and phase == 1:
		return "hand2_8" if version == 4 else "hand2"
	return id


## The ball potted after ball in hand: the yellow 1, or in the mini match the 8 (the last ball left).
func _hand_ball() -> int:
	return 8 if version == 4 else 1


func _ready() -> void:
	game = main.get("game")
	hud = main.get("hud")
	stage = main.get("stage")
	_build_card()
	if version == 1:
		_build_list()
	if version == 0:
		_marks = true
	game.state_changed.connect(_on_state)
	game.shot_fired.connect(_on_shot)
	game.guide_override = 2          # the ghost ball: where the cue ball must touch
	game.call("_apply_assist")
	_begin_step.call_deferred()


# ------------------------------------------------------------------------------------------------ the card
func _build_card() -> void:
	_card = UIKit.panel()
	_card.name = "TutorialCard"
	_card.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.1, 0.17, 0.94), 26, 2, Color(UIKit.EMERALD, 0.55), Vector4(28, 12, 22, 14), 18))
	_card.custom_minimum_size = Vector2(1000, 0)
	add_child(_card)
	var row := UIKit.hbox(18)
	_card.add_child(row)
	_check = IconGlyph.make("check", 64, UIKit.EMERALD)
	_check.visible = false
	_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_check)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	# the top line: (the coach's gem,) OBJECTIVE n / m, the dots, and Skip at the right, so the texts below have the
	# card's whole width
	var top := UIKit.hbox(12)
	if version == 4:
		var gem := IconGlyph.make("gem", 40, UIKit.EMERALD)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(gem)
	_count = UIKit.label("", "AccentLabel")
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_count)
	_dots = UIKit.hbox(8)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_dots)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_skip = UIKit.button("Skip", "GhostButton")
	_skip.name = "TutorialSkip"
	_skip.add_theme_font_size_override("font_size", 26)
	_skip.custom_minimum_size = Vector2(130, 48)
	_skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip.pressed.connect(skip)
	top.add_child(_skip)
	v.add_child(top)
	for st in ["normal", "hover", "pressed"]:
		var sb := _skip.get_theme_stylebox(st)
		if sb:
			sb = sb.duplicate()
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
			_skip.add_theme_stylebox_override(st, sb)
	_title = UIKit.label("", "H2Label")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	if version == 4:
		_coach = UIKit.label("", "H3Label")
		_coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_coach.add_theme_color_override("font_color", UIKit.EMERALD)
		_coach.add_theme_constant_override("line_spacing", -8)
		_coach.add_theme_font_size_override("font_size", 30)
		v.add_child(_coach)
	_how = UIKit.label("", "MutedLabel")
	_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_how.add_theme_constant_override("line_spacing", -8)
	v.add_child(_how)
	resized.connect(_place_card)


## The card sits at the top of the screen, between the player card and the tool buttons, so the table (and the
## ball the objective is about) stays in sight; on a narrow screen it goes under the player card. The pot messages
## move down under it.
func _place_card() -> void:
	var room := size.x - 2.0 * 470.0
	var want := 1000.0
	var top := 10.0
	if room < want * 0.8:
		room = size.x - 2.0 * 140.0
		top = 186.0
	_card.custom_minimum_size.x = minf(want, room)
	if not _fitted and _title.size.x > 200.0:
		# a long text (some languages) is set a little smaller rather than make the card cover the table
		_fitted = true
		if _title.get_line_count() > 1:
			_title.add_theme_font_size_override("font_size", 36)
		if _how.get_line_count() > 2:
			_how.add_theme_font_size_override("font_size", 23)
		if _coach and _coach.get_line_count() > 2:
			_coach.add_theme_font_size_override("font_size", 26)
	_card.size = Vector2.ZERO
	_card.reset_size()
	_card.position = Vector2((size.x - _card.size.x) * 0.5, top)
	if hud and hud.has_method("set_toast_top"):
		hud.call("set_toast_top", _card.position.y + _card.size.y + 14.0)
	if _list:
		_list.get_parent().position = Vector2(30, maxf(236.0, _card.position.y + _card.size.y + 20.0) if top > 100.0 else 236.0)


func _build_list() -> void:
	var p := UIKit.panel()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.1, 0.17, 0.9), 22, 1, UIKit.LINE, Vector4(22, 16, 22, 16), 12))
	p.name = "TutorialList"
	add_child(p)
	_list = UIKit.vbox(10)
	p.add_child(_list)


func _refresh_list() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(UIKit.label("Challenges", "H3Label"))
	for i in steps().size():
		var row := UIKit.hbox(12)
		var done := i < step
		var now := i == step
		row.add_child(IconGlyph.make("check" if done else ("chev_right" if now else "clock"), 34, UIKit.EMERALD if done else (UIKit.GOLD if now else UIKit.MUTED)))
		var l := UIKit.label(TEXT[steps()[i]][0], "MutedLabel" if not now else "")
		row.add_child(l)
		_list.add_child(row)


## How to do the objective (the spin pad is on the other side for left-handed players).
func _how_text(id: String) -> String:
	if id == "draw" and bool(Game.get_s("left_handed")):
		return "Drag the dot on the white ball (bottom right) down, then shoot: the white ball comes back."
	return TEXT[id][1]


## Lays the card out at the end of this frame and again on the next (one of each at a time).
func _place_soon() -> void:
	if not is_inside_tree():
		return
	_place_card.call_deferred()
	var pf := get_tree().process_frame
	if not pf.is_connected(_place_card):
		pf.connect(_place_card, CONNECT_ONE_SHOT)


## A message on the card (Done!, Watch, ...): in the coach's line in the mini match, else in the how-to line.
func _say(text: String) -> void:
	if _coach:
		_coach.text = text
	else:
		_how.text = text
	_place_soon()


func _show_text() -> void:
	var id := current()
	_title.remove_theme_font_size_override("font_size")
	_how.remove_theme_font_size_override("font_size")
	_fitted = false
	_count.text = L.t("OBJECTIVE %d / %d") % [step + 1, steps().size()]
	_title.text = TEXT[id][0]
	_how.text = _how_text(id)
	if _coach:
		# the mini match: the coach says it (the how-to line would say the same again, and the card would cover
		# the table)
		_coach.add_theme_font_size_override("font_size", 30)
		_coach.text = TEXT[id][2]
		_how.visible = false
	for c in _dots.get_children():
		c.queue_free()
	for i in steps().size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(26 if i == step else 12, 12)
		d.color = UIKit.EMERALD if i < step else (UIKit.GOLD if i == step else Color(1, 1, 1, 0.2))
		_dots.add_child(d)
	_check.visible = false
	_refresh_list()
	_place_soon()
	# (a wrapped text knows its height a frame later: shrink the card again then)
	get_tree().create_timer(0.0).timeout.connect(_place_soon)
	UIKit.fade_in(_card, 0.25, 14)


# ------------------------------------------------------------------------------------------------ objectives
## A table position, in metres from the table's centre: x along its length, y across (negative y = the far side).
func _geom() -> TableGeom:
	return game.sim.table


func _pocket(corner: bool, sx: float, sy: float) -> Vector2:
	var g := _geom()
	return Vector2(sx * g.a if corner else 0.0, sy * g.b)


func _layout(id: String) -> Dictionary:
	var g := _geom()
	var R := game.sim.R
	match id:
		"aim", "pot", "pot1_easy", "pot2_easy":
			var n := 2 if id == "pot2_easy" else 1
			return {n: Vector2(0.0, -g.b + 0.32), 0: Vector2(0.0, 0.25)}
		"cut":
			var c := _pocket(true, 1.0, -1.0)
			var o := c + Vector2(-1, 1).normalized() * 0.30
			return {1: o, 0: Vector2(0.35, -0.05)}
		"draw":
			# a straight shot into the corner along a 30° line: drawn back, the white ball runs to the near rail
			# between the pockets (on the 45° line it went straight back into the near middle pocket)
			var c2 := _pocket(true, 1.0, -1.0)
			var line := Vector2(-cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
			var o2 := c2 + line * 0.42
			return {1: o2, 0: o2 + line * 0.5}
		"hand":
			var one := Vector2(0.55, -0.25)
			var cue := Vector2(-g.a + 0.12, g.b - 0.1)
			if version == 4:
				return {8: one, 0: cue}
			return {1: one, 2: cue.lerp(one, 0.35), 0: cue}
		"eight":
			# a gentle cut (28°): the white ball then runs off along the far rail instead of following the 8 in
			var c3 := _pocket(true, 1.0, -1.0)
			var diag := Vector2(-1, 1).normalized()
			var e := c3 + diag * 0.40
			var ghost := e + diag * 2.0 * R
			return {8: e, 0: ghost + diag.rotated(deg_to_rad(-28.0)) * 0.55}
		"break":
			var f := Rack.foot_spot(game.sim)
			var dx := 2.0 * R * cos(deg_to_rad(30.0)) + 0.0005
			return {1: f, 2: f + Vector2(dx, -R - 0.0003), 8: f + Vector2(dx, R + 0.0003), 0: Rack.head_spot(game.sim)}
	return {}


## Puts exactly these balls on the table (the others are taken off), sliding them to their places.
func arrange(balls: Dictionary) -> void:
	var sim := game.sim
	for i in sim.n:
		var nb: int = sim.num[i]
		sim.vel[i] = Vector2.ZERO
		sim.spin[i] = Vector3.ZERO
		sim.hz[i] = 0.0
		sim.vz[i] = 0.0
		if balls.has(nb):
			var was_on := sim.st[i] != PoolSim.ST_POCKETED
			sim.st[i] = PoolSim.ST_REST
			sim.pocket_of[i] = -1
			sim.pos[i] = balls[nb]
			if was_on:
				game.views[i].glide_to(sim.pos[i], 0.35)
			else:
				game.views[i].place(sim.pos[i])
				game.views[i].scale = Vector3.ONE * 0.01
				var tw: Tween = game.views[i].create_tween()
				tw.tween_property(game.views[i], "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			sim.st[i] = PoolSim.ST_POCKETED
			sim.pocket_of[i] = -1
			game.views[i].visible = false


func _aim_yaw_for(n: int) -> float:
	# the ghost ball: where the cue ball must touch to send ball n into the pocket it lines up with best
	var sim := game.sim
	var i := sim.index_of_number(n)
	var o := sim.pos[i]
	var c := game.cue_ball_pos()
	var best := INF
	var yaw := 0.0
	for pk in _geom().pockets:
		var to: Vector2 = (pk["mid"] as Vector2) - o
		var d := to.normalized()
		var ghost := o - d * 2.0 * sim.R
		var shot := ghost - c
		var cut := absf(shot.angle_to(d))
		if cut < best:
			best = cut
			yaw = shot.angle()
	return yaw


func _target_ball() -> int:
	match current():
		"eight", "hand2_8": return 8
		"pot2": return 2
		"hand": return _hand_ball()
	return 1


func _begin_step() -> void:
	if not is_inside_tree():
		return
	_busy = true
	tries = 0
	phase = 0
	_aim_hold = 0.0
	var id: String = steps()[step]
	_show_text()
	game.control.set_enabled(false)
	if id in ["aim", "pot", "cut", "draw", "hand", "eight", "break"]:
		# a fresh set-up (pot right after aim keeps the aim objective's table)
		if not (id == "pot" and step > 0 and steps()[step - 1] == "aim"):
			arrange(_layout(id))
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree():
		return
	game.call("_sync_views", 0.0)
	_target_yaw = _aim_yaw_for(_target_ball()) if game.sim.st[game.sim.index_of_number(_target_ball())] != PoolSim.ST_POCKETED else 0.0
	game.control.reset_for_turn(_target_yaw + (0.5 if id == "aim" else 0.0))
	game.control.offset = Vector2.ZERO
	if version == 3 and id in ["pot", "cut", "draw"]:
		await _demo(id)
		if not is_inside_tree():
			return
	if id in ["pot1", "pot2"] and game.sim.st[game.sim.index_of_number(_target_ball())] == PoolSim.ST_POCKETED:
		_say(L.t("Already in, from the break!"))
		_done()
		return
	if id == "hand":
		# as after a real foul: the cue ball is in hand at once
		Sfx.play("foul", 0.6)
		game.start_ball_in_hand()
		_hand_from = game.cue_ball_pos()
	game.control.set_enabled(game.state == PoolGame.State.AIM)
	_busy = false
	_point()


## Version 3: the shot is shown first. The cue turns to the right line with the full prediction drawn, (for spin)
## the dot moves low on the white ball, then the player gets the cue back.
func _demo(id: String) -> void:
	_say(L.t("Watch: this is the shot."))
	game.guide_override = 3
	game.call("_apply_assist")
	var from := _target_yaw + 0.5
	var tw := create_tween()
	tw.tween_method(func(y: float): game.control.yaw = y, from, _target_yaw, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if id == "draw":
		# the dot moves down on the HUD's spin pad too, where the player will drag it
		var pad: Control = hud.get("_spin")
		var low := func(o: float) -> void:
			game.control.offset = Vector2(0, -o)
			if pad:
				pad.call("set_spin", game.control.offset)
		tw.tween_method(low, 0.0, 0.6, 0.6)
	tw.tween_interval(1.1)
	await tw.finished
	if not is_inside_tree():
		return
	game.control.reset_for_turn(_target_yaw + 0.5)
	game.control.offset = Vector2.ZERO
	var pad2: Control = hud.get("_spin")
	if pad2:
		pad2.call("set_spin", Vector2.ZERO)
	game.guide_override = 2
	game.call("_apply_assist")
	_say(L.t("Your turn: do the same."))
	# then the how-to line again, so the player still has it while trying
	var at_step := step
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_inside_tree() and step == at_step and not _busy:
			_how.text = _how_text(current())
			_place_card())


func _point() -> void:
	if not _marks:
		return
	_point_at = null
	match current():
		"draw": _point_at = hud.get("_spin")
		"hand": _point_at = hud.get("_hand_place")
		"aim":
			# the control's aiming part (the stick, wheel, ring, pad, crank...), not its power piston or nudge
			# arrows; none for the slingshot (drag anywhere) and the phone cue (point the phone)
			var c: Object = game.control
			var skip := [c.get("_piston"), c.get("_nudge_l"), c.get("_nudge_r"), c.get("_btn"), c.get("_chip")]
			for w in c.get("_widgets"):
				if is_instance_valid(w) and not (w in skip):
					_point_at = w
					break


## The ball the objective is about (or, for ball in hand, the white ball to move): a gold ring pulses round it.
func _ring_target() -> int:
	if _busy or game == null or game.sim == null:
		return -1
	var id := current()
	if id == "hand" and game.state == PoolGame.State.BALL_IN_HAND:
		return game.cue_index()
	if game.state != PoolGame.State.AIM or id == "break":
		return -1
	var i := game.sim.index_of_number(_target_ball())
	return i if i >= 0 and game.sim.st[i] != PoolSim.ST_POCKETED else -1


func _draw() -> void:
	_draw_mark()
	var i := _ring_target()
	if i < 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w: Vector3 = game.call("_wpos", game.sim.pos[i], 0.0)
	if cam.is_position_behind(w):
		return
	var sc := stage.table_root.global_transform.basis.get_scale().x
	var c := cam.unproject_position(w)
	var r := maxf(c.distance_to(cam.unproject_position(w + cam.global_transform.basis.x * game.sim.R * sc)), 5.0)
	c -= get_global_rect().position
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(c, r * (1.7 + 0.6 * pulse), 0.0, TAU, 48, Color(UIKit.GOLD, 0.9 - 0.5 * pulse), 4.0, true)
	draw_arc(c, r * 1.35, 0.0, TAU, 40, Color(UIKit.GOLD, 0.55), 2.0, true)


## Version 0's coach mark: the control to use now is outlined in gold and pulses; on the spin pad an arrow shows
## the drag (down = backspin).
func _draw_mark() -> void:
	if _busy or not is_instance_valid(_point_at) or not _point_at.is_visible_in_tree():
		return
	var r := _point_at.get_global_rect()
	r.position -= get_global_rect().position
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var col := Color(UIKit.GOLD, 0.95 - 0.45 * pulse)
	if current() == "draw":
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		draw_arc(c, rad + 10.0 + 8.0 * pulse, 0.0, TAU, 56, col, 5.0, true)
		# the drag: a dot slides from the middle down, again and again
		var k := fmod(_t, 1.2) / 1.2
		var from := c
		var to := c + Vector2(0, rad * 0.62)
		draw_line(from, to, Color(UIKit.GOLD, 0.8), 4.0, true)
		draw_line(to, to + Vector2(-12, -14), Color(UIKit.GOLD, 0.8), 4.0, true)
		draw_line(to, to + Vector2(12, -14), Color(UIKit.GOLD, 0.8), 4.0, true)
		draw_circle(from.lerp(to, ease(k, 0.6)), 9.0, UIKit.GOLD)
		return
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(5)
	sb.border_color = col
	sb.set_corner_radius_all(30)
	sb.anti_aliasing = true
	draw_style_box(sb, r.grow(8.0 + 6.0 * pulse))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _busy or game == null:
		return
	var id := current()
	if id == "aim" and game.state == PoolGame.State.AIM:
		var err := absf(angle_difference(game.control.yaw, _target_yaw))
		_aim_hold = _aim_hold + delta if err < AIM_TOL else 0.0
		if _aim_hold > 0.35:
			_done()
	if _shot_on and game.state == PoolGame.State.ROLLING:
		var p := game.cue_ball_pos()
		_max_proj = maxf(_max_proj, (p - _cue_from).dot(_dir))


func _on_shot() -> void:
	_shot_on = true
	_cue_from = game.cue_start
	var y := float(game.last_shot.get("yaw", 0.0))
	_dir = Vector2(cos(y), sin(y))
	_max_proj = 0.0
	_point_at = null


func _on_state(st: int) -> void:
	var was := _was_state
	_was_state = st
	if _busy:
		return
	if current() == "hand" and was == PoolGame.State.BALL_IN_HAND and st == PoolGame.State.AIM:
		if game.cue_ball_pos().distance_to(_hand_from) > 0.08:
			phase = 1
			_placed_at = game.cue_ball_pos()
			_show_text()
			_target_yaw = _aim_yaw_for(_hand_ball())
			game.control.reset_for_turn(_target_yaw)     # (lined up for the pot, as every objective starts)
		else:
			# Place ball without moving it: the objective is to move it, so ball in hand again
			game.message.emit(L.t("Drag the white ball to a clear spot first."), "warn")
			game.start_ball_in_hand.call_deferred()
		return
	if current() == "hand" and st == PoolGame.State.BALL_IN_HAND:
		_hand_from = game.cue_ball_pos()
		return
	if _shot_on and st in [PoolGame.State.AIM, PoolGame.State.BALL_IN_HAND, PoolGame.State.OVER]:
		_shot_on = false
		_judge()


## How the shot went, for the objective in hand.
func _judge() -> void:
	var sim := game.sim
	var potted: Array = []
	for p in game.potted_this_shot:
		potted.append(int(p["number"]))
	var scratch := 0 in potted
	var id := current()
	var ok := false
	var why := ""
	match id:
		"aim":
			ok = absf(angle_difference(float(game.last_shot.get("yaw", 99.0)), _target_yaw)) < AIM_TOL * 1.5
		"pot", "cut", "hand2", "pot1":
			ok = 1 in potted or (id == "pot1" and sim.st[sim.index_of_number(1)] == PoolSim.ST_POCKETED)
		"pot2":
			ok = 2 in potted or sim.st[sim.index_of_number(2)] == PoolSim.ST_POCKETED
		"draw":
			var back := _max_proj - (game.cue_ball_pos() - _cue_from).dot(_dir)
			ok = 1 in potted and not scratch and back > 0.12
			if 1 in potted and not ok:
				why = "Potted, but the white ball didn't come back: drag the dot lower." if float((game.last_shot.get("offset", Vector2.ZERO) as Vector2).y) > -0.3 else "Potted! Now hit a little harder so the backspin brings it back."
		"eight", "hand2_8":
			ok = 8 in potted and not scratch
			if 8 in potted and scratch:
				why = "The white ball went in too. Try a softer shot."
		"break":
			ok = float(game.last_shot.get("power", 0.0)) > 0.45
			if not ok:
				why = "Harder! Use full power."
	if version == 4 and 8 in potted and id != "hand2_8":
		game.call("_respot_eight")
		why = "Not the 8 yet: it's always the last ball."
	if str(main.get("_tour_dir")) != "":
		print("TUTORIAL judge %s: potted %s -> %s" % [id, str(potted), "met" if ok else "again"])
	if ok:
		_done()
		return
	tries += 1
	game.message.emit(L.t(why) if why != "" else L.t("Not quite. Try again!"), "warn")
	if id in ["pot", "cut", "draw", "eight", "aim"] or id.begins_with("hand2"):
		_busy = true
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree():
			return
		if id.begins_with("hand2"):
			# the same shot again: the ball back where it was, the white ball back where the player put it
			var hb := _hand_ball()
			var spot: Vector2 = _layout("hand")[hb]
			var cue := _placed_at
			if cue.distance_to(spot) < 2.5 * sim.R:
				cue = Rack.head_spot(sim)
			arrange({hb: spot, 0: cue})
		else:
			arrange(_layout("pot" if id == "aim" else id))
		await get_tree().create_timer(0.4).timeout
		_after_reset()
	elif id in ["pot1", "pot2"] and tries >= MAX_TRIES:
		# an easier one: the ball lined up straight in front of the far pocket
		_busy = true
		var keep := {}
		for i in sim.n:
			if sim.st[i] != PoolSim.ST_POCKETED:
				keep[sim.num[i]] = sim.pos[i]
		var easy := _layout("pot1_easy" if id == "pot1" else "pot2_easy")
		for n in keep.keys():
			if not easy.has(n):
				var p: Vector2 = keep[n]
				for q in easy.values():
					if p.distance_to(q) < 0.12 or absf(p.x) < 0.1:
						p = Vector2(-0.7, -0.2 if n == 2 else 0.2)
				easy[n] = p
		arrange(easy)
		game.message.emit(L.t("Here's an easier one."), "info")
		await get_tree().create_timer(0.4).timeout
		_after_reset()


func _after_reset() -> void:
	if not is_inside_tree():
		return
	game.call("_sync_views", 0.0)
	_target_yaw = _aim_yaw_for(_target_ball())
	game.control.reset_for_turn(_target_yaw + (0.5 if current() == "aim" else 0.0))
	game.control.offset = Vector2.ZERO
	_busy = false
	_point()


func _done() -> void:
	_busy = true
	game.control.set_enabled(false)
	Sfx.play("turn_chime", 0.8)
	Game.vibrate(25)
	_check.visible = true
	_say(L.t("Done!"))
	_point_at = null
	var tw := create_tween()
	_card.pivot_offset = _card.size * 0.5
	tw.tween_property(_card, "scale", Vector2(1.05, 1.05), 0.12)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.18)
	await get_tree().create_timer(1.1).timeout
	if not is_inside_tree():
		return
	step += 1
	if step >= steps().size():
		_complete()
	else:
		_begin_step()


# ------------------------------------------------------------------------------------------------ the end
func _complete() -> void:
	var first := Game.finish_tutorial()
	# the match is over: no aiming (the stick would lie across the table under the end screen)
	game.call("_set_state", PoolGame.State.OVER)
	game.cue_view.visible = false
	_card.visible = false
	if _list:
		_list.get_parent().visible = false
	Sfx.play("win", 0.7)
	var end := Control.new()
	end.name = "TutorialEnd"
	UIKit.fullrect(end)
	add_child(end)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.07, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.fullrect(bg)
	end.add_child(bg)
	var v := UIKit.vbox(16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.center_in(end, v)
	var t := UIKit.label("TUTORIAL COMPLETE", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_size_override("font_size", 76)
	t.add_theme_color_override("font_color", UIKit.EMERALD)
	v.add_child(t)
	var chest := PackageView.xp_chest(300.0)
	chest.set_live(true)
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(0, 260)
	cc.add_child(chest)
	v.add_child(cc)
	var sub := UIKit.label("Your gift: an XP chest. Open it now: no timer, no advert." if first or not Game.gift_chests().is_empty() else "You know the basics. Have fun!", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 900
	v.add_child(sub)
	var row := UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var open := UIKit.button("Open chest", "PrimaryButton", "gift", 380)
	open.name = "TutorialOpenChest"
	open.visible = not Game.gift_chests().is_empty()
	# (Randy, 18 Nov: bright green like the main theme, not small and blue)
	var menu := UIKit.button("Main menu", "PrimaryButton", "home", 380)
	menu.name = "TutorialMenu"
	row.add_child(open)
	row.add_child(menu)
	v.add_child(row)
	UIKit.fade_in(v, 0.35, 30)
	open.pressed.connect(func():
		open.disabled = true
		chest.open()
		await chest.opened
		var got: Dictionary = Game.open_gift_chest()
		if not got.is_empty() and is_inside_tree():
			var proxy := _Router.new()
			proxy.main = main
			end.add_child(proxy)
			var card := RewardScreens.XpReveal.new(proxy, got)
			end.add_child(card)
			await card.closed
		if is_inside_tree():
			open.visible = false)
	menu.pressed.connect(func():
		finished.emit(true)
		main.call("quit_to", "menu"))


## Skip (and the pause menu's Quit): back to the menu; the tutorial stays to be played.
func skip() -> void:
	finished.emit(false)
	main.call("quit_to", "menu")


## The XP card's buttons, from inside a match: "Open package" first leaves the tutorial for the menu.
class _Router extends Node:
	var main: Node

	func go(where: String, _replace := false) -> void:
		main.call("quit_to", "menu")
		if where != "menu":
			main.call("go", where)

	func toast(text: String) -> void:
		main.call("toast", text)
