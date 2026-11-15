class_name AimGuide
extends Node3D
## Optional aiming help. Default is OFF (the cue stick alone shows the aim, like real pool).
## LINE: a short straight pointer from the cue ball (no prediction).
## GHOST: line to the first contact + ghost ball.
## FULL: also the object-ball / cue-ball directions and the simulated spin path.

enum Guide { OFF, LINE, GHOST, FULL }

var assist := Guide.OFF
var width := 0.006
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()
var _mat := StandardMaterial3D.new()
var _ghost_mat := StandardMaterial3D.new()
var _cache_key := ""
var _sim_path := PackedVector2Array()

const COL_AIM := Color(1, 1, 1, 0.85)
const COL_OBJ := Color("2be7a5")
const COL_CUE := Color(0.75, 0.86, 1.0, 0.75)
const COL_PATH := Color("ffc857")
const COL_BAD := Color("ff5c7a")


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = false
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi.mesh = _mesh
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	var sm := SphereMesh.new()
	sm.radial_segments = 32
	sm.rings = 16
	_ghost.mesh = sm
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.22)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	hide_guide()


func hide_guide() -> void:
	_mesh.clear_surfaces()
	_ghost.visible = false
	_cache_key = ""


## Recompute and draw. `sim` is the live simulator (not modified); shot params as in PoolSim.strike.
func update_guide(sim: PoolSim, cue_i: int, yaw: float, power: float, offset: Vector2, elev: float, scale_hint := 1.0) -> void:
	if assist == Guide.OFF:
		if _cache_key != "off":
			hide_guide()
			_cache_key = "off"
		return
	var key := "%d|%.5f|%.3f|%.3f|%.3f|%.2f|%d" % [cue_i, yaw, power, offset.x, offset.y, elev, assist]
	if key == _cache_key:
		return
	_cache_key = key
	var R := sim.R
	var p: Vector2 = sim.pos[cue_i]
	var d := Vector2(cos(yaw), sin(yaw))
	var w := width * clampf(1.0 / sqrt(maxf(scale_hint, 0.05)), 1.0, 3.0)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if assist == Guide.LINE:
		_ghost.visible = false
		_ribbon(p + d * R * 1.05, p + d * (R + 0.3), w, Color(COL_AIM, 0.6), true)
		_mesh.surface_end()
		return
	var hit := _cast(sim, cue_i, p, d)
	var t_hit: float = hit["t"]
	var contact := p + d * t_hit
	_ribbon(p + d * R * 1.05, contact, w, COL_AIM, true)
	_ghost.visible = hit["type"] == "ball"
	if hit["type"] == "ball":
		var sm: SphereMesh = _ghost.mesh
		sm.radius = R
		sm.height = 2.0 * R
		_ghost.position = Vector3(contact.x, R, contact.y)
		var q: Vector2 = sim.pos[hit["ball"]]
		var nrm := (q - contact).normalized()
		var full := clampf(d.dot(nrm), 0.0, 1.0)
		_ghost_mat.albedo_color = Color(1, 1, 1, 0.22)
		_circle(contact, R, w * 0.6, Color(1, 1, 1, 0.65))
		if assist == Guide.FULL:
			var obj_len := 0.55 * (0.25 + 0.75 * full)
			_ribbon(q + nrm * R, q + nrm * (R + obj_len), w, Color(COL_OBJ, 0.95), false)
			var tan := d - nrm * d.dot(nrm)
			if tan.length() > 1e-3:
				_ribbon(contact, contact + tan.normalized() * 0.3 * (1.0 - full * 0.85), w * 0.8, COL_CUE, false)
	elif hit["type"] == "cushion" and assist == Guide.FULL:
		var nrm2: Vector2 = hit["n"]
		var refl := d - 2.0 * d.dot(nrm2) * nrm2
		_ribbon(contact, contact + refl * 0.32, w * 0.8, Color(COL_AIM, 0.5), false)
	# simulated cue-ball path (spin-aware)
	if assist == Guide.FULL:
		# throttled: physics preview is the expensive part (~1-5 ms), geometry above is instant
		var now := Time.get_ticks_msec()
		if now - _path_ms > 70 or _sim_path.is_empty():
			_path_ms = now
			_sim_path = _simulate_path(sim, cue_i, yaw, power, offset, elev)
			_path_dirty = false
		else:
			_path_dirty = true
		_dotted(_sim_path, w * 0.7, COL_PATH)
	_mesh.surface_end()


var _path_ms := 0
var _path_dirty := false


## Call each frame while aiming so a throttled path refresh catches up after the finger stops.
func tick(sim: PoolSim, cue_i: int, yaw: float, power: float, offset: Vector2, elev: float, scale_hint := 1.0) -> void:
	if _path_dirty and Time.get_ticks_msec() - _path_ms > 70:
		_cache_key = ""
		update_guide(sim, cue_i, yaw, power, offset, elev, scale_hint)


func _simulate_path(sim: PoolSim, cue_i: int, yaw: float, power: float, offset: Vector2, elev: float) -> PackedVector2Array:
	var s := sim.clone()
	s.record_events = true
	s.events.clear()
	s.strike(cue_i, yaw, maxf(power, 0.25), offset, elev)
	var out := PackedVector2Array()
	var after_contact := -1.0
	var steps := 0
	while s.is_moving() and steps < 900:
		s._substep(s.substep)
		steps += 1
		if steps % 3 == 0:
			out.append(s.pos[cue_i])
		if after_contact < 0.0:
			for e in s.events:
				if e["type"] == "ball" and (e["a"] == cue_i or e["b"] == cue_i):
					after_contact = s.time
			s.events.clear()
		elif s.time - after_contact > 0.6:
			break
		if s.st[cue_i] == PoolSim.ST_POCKETED:
			break
	return out


## Ray-cast the cue ball path: first ball or cushion.
func _cast(sim: PoolSim, cue_i: int, p: Vector2, d: Vector2) -> Dictionary:
	var R := sim.R
	var best := {"t": 3.0, "type": "none"}
	for j in sim.n:
		if j == cue_i or sim.st[j] == PoolSim.ST_POCKETED:
			continue
		var q: Vector2 = sim.pos[j]
		var rel := q - p
		var along := rel.dot(d)
		if along <= 0.0:
			continue
		var perp2 := rel.length_squared() - along * along
		var rr := 4.0 * R * R
		if perp2 > rr:
			continue
		var t := along - sqrt(rr - perp2)
		if t < best["t"]:
			best = {"t": t, "type": "ball", "ball": j}
	for sg in sim.table.segments:
		var nrm: Vector2 = sg["n"]
		var vn := d.dot(nrm)
		if vn >= 0.0:
			continue
		var s0 := (p - (sg["a"] as Vector2)).dot(nrm)
		var t := (R - s0) / vn
		if t <= 0.0 or t >= best["t"]:
			continue
		var hp := p + d * t
		var u := (hp - (sg["a"] as Vector2)).dot(sg["dir"])
		if u < 0.0 or u > float(sg["len"]):
			continue
		best = {"t": t, "type": "cushion", "n": nrm}
	return best


# ------------------------------------------------------------------ drawing
func _ribbon(a: Vector2, b: Vector2, w: float, col: Color, fade_start: bool) -> void:
	var dir := b - a
	var l := dir.length()
	if l < 1e-4:
		return
	var n := Vector2(-dir.y, dir.x) / l * (w * 0.5)
	var y := 0.0012
	var ca := Color(col, col.a * (0.15 if fade_start else 1.0))
	var cb := col
	var v := [Vector3(a.x + n.x, y, a.y + n.y), Vector3(a.x - n.x, y, a.y - n.y), Vector3(b.x - n.x, y, b.y - n.y), Vector3(b.x + n.x, y, b.y + n.y)]
	var cs := [ca, ca, cb, cb]
	for idx in [0, 1, 2, 0, 2, 3]:
		_mesh.surface_set_color(cs[idx])
		_mesh.surface_add_vertex(v[idx])


func _circle(c: Vector2, r: float, w: float, col: Color) -> void:
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		_ribbon(p0, p1, w, col, false)


func _dotted(path: PackedVector2Array, w: float, col: Color) -> void:
	for i in range(0, path.size() - 1, 2):
		var fade := 1.0 - float(i) / maxf(path.size(), 1.0)
		_ribbon(path[i], path[i + 1], w, Color(col, 0.25 + 0.6 * fade), false)
