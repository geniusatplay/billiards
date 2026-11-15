class_name ControlPrecision
extends CueControl
## Shared base of the precision family (same feature set as Pro Dial):
## tap / drag the table for coarse aim (snaps to a ball centre for full-ball aim), nudge arrows,
## a pull-down power piston (release to strike), plus the HUD's spin pad and elevation slider.
## Each subclass adds its own fine-aim device.

const NUDGE_DEG := 0.05

var _piston: Widgets.PowerPiston
var _nudge_l: Button
var _nudge_r: Button
var _touch := -1
var _cw := 1.0   # +1 when increasing yaw turns the cue clockwise on screen (cached per gesture)


func _build_widgets() -> void:
	_piston = Widgets.PowerPiston.new()
	_add(_piston)
	_piston.changed.connect(func(p: float):
		power = p
		aim_updated.emit())
	_piston.released.connect(func(p: float):
		power = p
		shot_requested.emit())
	_nudge_l = UIKit.icon_button("chev_left", 84, "Nudge aim (counter-clockwise)")
	_nudge_r = UIKit.icon_button("chev_right", 84, "Nudge aim (clockwise)")
	_add(_nudge_l)
	_add(_nudge_r)
	_nudge_l.pressed.connect(func(): _nudge(-1.0))
	_nudge_r.pressed.connect(func(): _nudge(1.0))
	_build_fine()
	_layout()
	layer.resized.connect(_layout)


## Arrow buttons: -1 = counter-clockwise, +1 = clockwise.
func _nudge(s: float) -> void:
	turn_cw(deg_to_rad(NUDGE_DEG) * s, true)


## Subclasses: create the fine-aim widget(s) with _add().
func _build_fine() -> void:
	pass


## Subclasses: position the fine-aim widget; return its rect so the nudge arrows can sit beside it.
func _layout_fine(_vp: Vector2) -> Rect2:
	return Rect2(_vp.x * 0.5 - 100, _vp.y - 178, 200, 92)


func _layout() -> void:
	if not is_instance_valid(_piston):
		return
	var vp := layer.size
	var right := _side(true)
	var r := _layout_fine(vp)
	var ny := r.position.y + r.size.y * 0.5 - 42.0
	_nudge_l.position = Vector2(r.position.x - 100, ny)
	_nudge_r.position = Vector2(r.end.x + 16, ny)
	_piston.position = Vector2(vp.x - 300 if right else 170, vp.y * 0.5 - 190)


## Screen-consistent turning: positive = clockwise on screen, from any camera angle.
func turn_cw(rad: float, refresh_sign := false) -> void:
	if refresh_sign:
		_cw = _cw_sign()
	yaw += rad * _cw
	aim_updated.emit()


func _cw_sign() -> float:
	if game == null or game.stage == null:
		return 1.0
	var cue: Vector2 = game.cue_ball_pos()
	var dir := Vector2.from_angle(yaw)
	var a: Vector2 = game.stage.table_to_screen(cue)
	var p1: Vector2 = game.stage.table_to_screen(cue + dir * 0.4)
	var p2: Vector2 = game.stage.table_to_screen(cue + dir.rotated(0.02) * 0.4)
	var r := p1 - a
	var d := p2 - p1
	return 1.0 if r.x * d.y - r.y * d.x >= 0.0 else -1.0


## Hook for devices that live on the table itself (orbit ring, ghost target). Return true if consumed.
func _fine_input(_ev: InputEvent) -> bool:
	return false


func handle_input(ev: InputEvent) -> bool:
	if not enabled:
		return false
	if _fine_input(ev):
		return true
	if ev is InputEventScreenTouch:
		if ev.pressed and _touch < 0:
			_touch = ev.index
			_aim_at(ev.position)
			return true
		if not ev.pressed and ev.index == _touch:
			_touch = -1
			return true
	elif ev is InputEventScreenDrag and ev.index == _touch:
		_aim_at(ev.position)
		return true
	return false


## Coarse aim: point the cue at a table spot (snaps to a ball centre when touched right on it).
func _aim_at(sp: Vector2) -> void:
	var p = game.stage.screen_to_table(sp)
	if p == null:
		return
	var cue: Vector2 = game.cue_ball_pos()
	var target: Vector2 = p
	var sim: PoolSim = game.sim
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED and sim.kind[i] != PoolSim.K_CUE and sim.pos[i].distance_to(target) < sim.R * 1.1:
			target = sim.pos[i]
			break
	if target.distance_to(cue) > sim.R:
		yaw = (target - cue).angle()
		aim_updated.emit()
