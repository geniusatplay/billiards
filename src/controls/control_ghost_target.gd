class_name ControlGhostTarget
extends ControlPrecision
## GHOST TARGET — aim like a pro: put the ghost ball exactly where the cue ball should be at contact.
## Tap / drag the table to place it, the micro pad moves it in slow motion (1/12 speed), arrows
## shift it sideways by half a millimetre. The cue always points through the ghost ball.

const MICRO := 1.0 / 12.0

var ghost := Vector2.ZERO
var _pad: Widgets.MicroPad
var _marker: MeshInstance3D
var _ring: MeshInstance3D


func scheme_id() -> String:
	return "ghost_target"


func title() -> String:
	return L.t("Ghost Target")


func help_lines() -> Array:
	return ["Tap or drag on the table to place the ghost ball where the cue ball should be at contact.",
		"Use the micro pad to slide the ghost ball in slow motion; arrows shift it 0.5 mm.",
		"The cue always points through the ghost ball.",
		"Pull the power piston down, then release to strike."]


func _build_fine() -> void:
	_pad = Widgets.MicroPad.new()
	_add(_pad)
	_pad.moved.connect(_micro)
	_make_marker()


func _nudge(s: float) -> void:
	_shift(0.0005 * s)


func deactivate() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	super.deactivate()


func set_enabled(on: bool) -> void:
	super.set_enabled(on)
	if is_instance_valid(_marker):
		_marker.visible = on


func _layout_fine(vp: Vector2) -> Rect2:
	var s := _pad.custom_minimum_size
	_pad.position = Vector2(vp.x * 0.5 - s.x * 0.5, vp.y - s.y - 70)
	return Rect2(_pad.position, s)


func _make_marker() -> void:
	if game == null or game.stage == null:
		return
	_marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	var R: float = game.sim.R
	sm.radius = R
	sm.height = 2.0 * R
	sm.radial_segments = 32
	sm.rings = 16
	_marker.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	_marker.material_override = m
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R * 1.05
	tm.outer_radius = R * 1.3
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = UIKit.SKY
	rm.emission_enabled = true
	rm.emission = UIKit.SKY
	rm.emission_energy_multiplier = 1.5
	_ring.material_override = rm
	_ring.position = Vector3(0, -R + 0.0015, 0)
	_marker.add_child(_ring)
	game.stage.table_root.add_child(_marker)


func reset_for_turn(p_yaw: float) -> void:
	super.reset_for_turn(p_yaw)
	# start with the ghost ball touching the default target, or half a metre out
	var cue: Vector2 = game.cue_ball_pos()
	var dir := Vector2.from_angle(p_yaw)
	var sim: PoolSim = game.sim
	var best := 0.5
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED or sim.kind[i] == PoolSim.K_CUE:
			continue
		var rel: Vector2 = sim.pos[i] - cue
		var along := rel.dot(dir)
		var perp2 := rel.length_squared() - along * along
		if along > 0.0 and perp2 < 4.0 * sim.R * sim.R:
			best = minf(best, along - sqrt(4.0 * sim.R * sim.R - perp2))
	_set_ghost(cue + dir * maxf(best, sim.R * 2.5))


func tick(_delta: float) -> void:
	# keep the aim through the ghost ball even if the cue ball was moved
	if game and game.state == PoolGame.State.AIM:
		var cue: Vector2 = game.cue_ball_pos()
		if ghost.distance_to(cue) > game.sim.R:
			var y := (ghost - cue).angle()
			if absf(wrapf(y - yaw, -PI, PI)) > 1e-7:
				yaw = y
				aim_updated.emit()
	if is_instance_valid(_marker):
		_marker.visible = enabled and game.state == PoolGame.State.AIM


func _set_ghost(p: Vector2) -> void:
	var sim: PoolSim = game.sim
	ghost = Vector2(clampf(p.x, -sim.table.a + sim.R, sim.table.a - sim.R), clampf(p.y, -sim.table.b + sim.R, sim.table.b - sim.R))
	if is_instance_valid(_marker):
		_marker.position = Vector3(ghost.x, sim.R, ghost.y)
	var cue: Vector2 = game.cue_ball_pos()
	if ghost.distance_to(cue) > sim.R:
		yaw = (ghost - cue).angle()
		aim_updated.emit()


## Table tap / drag: place the ghost ball (no snapping — you choose the exact contact).
func _aim_at(sp: Vector2) -> void:
	var p = game.stage.screen_to_table(sp)
	if p != null:
		_set_ghost(p)


## Micro pad: finger motion in screen pixels -> slow-motion ghost movement on the table plane.
func _micro(d_px: Vector2) -> void:
	var cam: Camera3D = game.stage.active_camera()
	var c: Vector2 = game.stage.table_to_screen(ghost)
	var px = game.stage.screen_to_table(c + Vector2(40, 0))
	var py = game.stage.screen_to_table(c + Vector2(0, 40))
	if px == null or py == null or cam == null:
		return
	var ux: Vector2 = ((px as Vector2) - ghost) / 40.0
	var uy: Vector2 = ((py as Vector2) - ghost) / 40.0
	_set_ghost(ghost + (ux * d_px.x + uy * d_px.y) * MICRO)


## Arrow nudge: shift the ghost sideways to the aim line.
func _shift(metres: float) -> void:
	var side := Vector2.from_angle(yaw).orthogonal()
	_set_ghost(ghost + side * metres * _cw_sign())
