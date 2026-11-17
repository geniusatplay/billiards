class_name CueView
extends Node3D
## The cue stick. Positioned from the shot state (aim yaw, elevation, tip offset, pull-back).

var skin := ""
var _model: Node3D
## Built cue models by skin, the newest last. The player's cue and the opponent's stay built, so changing hands
## between turns only shows one and hides the other (nothing is loaded or compiled mid-match).
var _models := {}
var _order: Array = []
const KEEP := 3
var ball_r := 0.028575
var pull := 0.0            # 0..1 visual pull-back (power preview)
var _strike_t := -1.0
var _strike_dur := 0.07     # the forward stroke: from where the stick is drawn back to through the ball
var _idle_t := 0.0
var _ball := Vector2.ZERO
var _yaw := 0.0
var _elev := 0.0
var _offset := Vector2.ZERO
var _fade := 1.0


func set_skin(p_skin: String) -> void:
	if p_skin == skin and _model:
		return
	skin = p_skin
	if _model:
		_model.visible = false
	_order.erase(skin)
	_order.append(skin)
	if _models.has(skin):
		_model = _models[skin]
		_model.visible = true
		return
	while _order.size() > KEEP:
		var old_skin: String = _order.pop_front()
		if _models.has(old_skin):
			(_models[old_skin] as Node).queue_free()
			_models.erase(old_skin)
	_model = build_model(skin)
	_models[skin] = _model
	add_child(_model)


## A cue model painted with its skin (also used to prepare cues on the loading screen).
static func build_model(p_skin: String) -> Node3D:
	var _model: Node3D
	var entry := Catalog.cue(p_skin)
	var path := Cues.model_path(entry)
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps:
		_model = ps.instantiate()
		Cues.paint(_model, entry)
	else:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0065
		cm.bottom_radius = 0.015
		cm.height = 1.47
		mi.mesh = cm
		mi.rotation.x = PI / 2.0
		mi.position.z = 0.735
		_model = Node3D.new()
		_model.add_child(mi)
	return _model


## The cues built so far (the loading screen shows each once so its shaders are ready).
func models() -> Array:
	return _models.values()


## ball: cue ball position (table coords). yaw: shot direction. offset: tip offset in R units.
func aim(ball: Vector2, yaw: float, elev_deg: float, offset: Vector2, p_pull: float) -> void:
	_ball = ball
	_yaw = yaw
	_elev = deg_to_rad(elev_deg)
	_offset = offset
	pull = p_pull
	_strike_t = -1.0
	_fade = 1.0
	visible = true
	_update(0.0)


## Starts the stroke from the current draw. Returns when the tip reaches the ball (seconds): the match starts
## the balls then (v1.1.14; before, the stroke always started at the ball and the ball left before the stick).
func strike_anim() -> float:
	var from_gap := 0.004 + pull * 0.22
	_strike_dur = 0.05 + 0.06 * clampf(pull, 0.0, 1.0)
	_strike_t = 0.0
	return _strike_dur * from_gap / (from_gap + 0.012)


func _process(delta: float) -> void:
	if not visible:
		return
	_idle_t += delta
	if _strike_t >= 0.0:
		_strike_t += delta
		if _strike_t > _strike_dur + 0.38:
			_fade = maxf(0.0, _fade - delta * 4.0)
			if _fade <= 0.0:
				visible = false
	_update(delta)


func _update(_dt: float) -> void:
	var d := Vector3(cos(_elev) * cos(_yaw), -sin(_elev), cos(_elev) * sin(_yaw))
	var side := d.cross(Vector3.UP).normalized()
	var up := side.cross(d).normalized()
	var R := ball_r
	var contact := Vector3(_ball.x, R, _ball.y) + (-d * R) + side * (_offset.x * R) + up * (_offset.y * R)
	var gap := 0.004 + pull * 0.22
	if _strike_t >= 0.0:
		# quick forward stroke through the ball, then recoil
		var k := clampf(_strike_t / _strike_dur, 0.0, 1.0)
		gap = lerpf(gap, -0.012, k)
		if _strike_t > _strike_dur:
			gap = -0.012 + minf((_strike_t - _strike_dur) * 0.08, 0.02)
	elif pull < 0.01 and not Game.get_s("reduced_motion"):
		gap += 0.006 + sin(_idle_t * 2.4) * 0.004   # gentle "breathing" while aiming
	var tip := contact - d * gap
	# model: tip at origin, butt toward local +Z  ->  local -Z must point along d
	var basis_z := -d
	var basis_x := Vector3.UP.cross(basis_z).normalized()
	if basis_x.length_squared() < 1e-6:
		basis_x = Vector3.RIGHT
	var basis_y := basis_z.cross(basis_x).normalized()
	transform = Transform3D(Basis(basis_x, basis_y, basis_z), tip)
	if _model:
		_model.visible = _fade > 0.02
