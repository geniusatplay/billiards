class_name TableView
extends Node3D
## Procedural, size-adjustable pool table built from the same TableGeom the physics uses.
## Local origin = centre of the felt surface; units = metres (life size). The parent scales it for AR.
## Colours come from a Catalog.TABLES style so new table designs are data-only.

const CUSHION_DEPTH := PoolSim.CUSHION_DEPTH   # the cue-vs-rail rule in PoolSim uses the same numbers
const RAIL_WIDTH := 0.115
const SKIRT_DEPTH := 0.17

var geom: TableGeom
var felt_color := Color("0f6b4f")
var rail_height := 0.045
var table_height := 0.775
var show_legs := true
var accent := Color("2be7a5")
var wood_color := Color("2a160d")
var skirt_color := Color("15100c")
var style := {}            # the Catalog.TABLES entry this table was built from
static var _felt_shaders := {}   # cloth pattern number -> its own copy of the cloth shader

var _felt_mat: ShaderMaterial
var _liner_mat: StandardMaterial3D
var _built: Array[Node] = []
var _built_key := ""       # what the table now standing was built from (an identical request is not rebuilt)

static var _leg_scene: PackedScene
static var debug_all_shadows := false    # (measuring only: every part throws a shadow, as before v1.1.4)
static var _model_cache := {}


func build(p_geom: TableGeom, p_style: Dictionary, p_rail_h := 0.045, p_height := 0.775, p_legs := true) -> void:
	# Starting a match, going back to the menu and changing view each ask for the table again. Building it (the
	# cut-outs for the pockets above all) takes a moment on a phone, so the same table is simply kept.
	var key := str([p_geom.length, p_geom.width, p_geom.ball_r, p_geom.pocket_scale, p_style, p_rail_h, p_height, p_legs])
	if key == _built_key and geom != null and not _built.is_empty():
		return
	_built_key = key
	geom = p_geom
	style = p_style
	felt_color = style.get("felt", felt_color)
	wood_color = style.get("wood", Color("2a160d"))
	skirt_color = style.get("skirt", Color("15100c"))
	accent = style.get("accent", accent)
	rail_height = p_rail_h
	table_height = p_height
	show_legs = p_legs
	for n in _built:
		if is_instance_valid(n):
			n.queue_free()
	_built.clear()
	_build_bed()
	_build_cushions()
	_build_frame()
	_build_pockets()
	_build_diamonds()
	if show_legs:
		_build_legs()
	_build_chalk()


func _keep(n: Node) -> Node:
	add_child(n)
	_built.append(n)
	return n


## Many small parts with one material drawn as one object: the same shapes in the same places, but the phone
## draws them in one go instead of one by one (in every pass: the picture and each shadow map). `parts` holds
## [Mesh, Transform3D] pairs. Parts too small or too low to throw a visible shadow are built with shadows off.
func _keep_merged(parts: Array, mat: Material, shadows := true, p_name := "") -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var m: Mesh = part[0]
		for sfc in m.get_surface_count():
			st.append_from(m, sfc, part[1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows and not debug_all_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p_name != "":
		mi.name = p_name
	_keep(mi)
	return mi


# ------------------------------------------------------------------ materials
func _felt_material(darken := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var fx := int(style.get("felt_fx", 0))
	if not _felt_shaders.has(fx):
		var base_sh: Shader = preload("res://src/game/shaders/felt.gdshader")
		if fx == 0:
			_felt_shaders[fx] = base_sh
		else:
			var sh := Shader.new()
			sh.code = base_sh.code.replace("#define FELT_FX 0", "#define FELT_FX %d" % fx)
			_felt_shaders[fx] = sh
	m.shader = _felt_shaders[fx]
	m.set_shader_parameter("felt2", style.get("felt2", Color.BLACK))
	m.set_shader_parameter("felt_color", felt_color * darken)
	m.set_shader_parameter("half_size", Vector2(geom.a, geom.b))
	m.set_shader_parameter("marks", 1.0 if darken >= 0.99 else 0.0)
	return m


static func std_mat(col: Color, rough := 0.5, metal := 0.0, emission := Color.BLACK, e_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if e_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e_energy
	return m


func _wood() -> Material:
	if style.has("rail"):
		return Cues.material(style["rail"])
	var m := std_mat(wood_color, 0.3, 0.0)
	m.metallic_specular = 0.6
	return m


## A part of the table the style may paint with a cue-style pattern (see Cues.material), else `plain`.
func _part(key: String, plain: Material) -> Material:
	return Cues.material(style[key]) if style.has(key) else plain


# ------------------------------------------------------------------ bed / felt
func _build_bed() -> void:
	var csg := CSGCombiner3D.new()
	var slab := CSGBox3D.new()
	var w := geom.length + 2.0 * CUSHION_DEPTH + 0.01
	var d := geom.width + 2.0 * CUSHION_DEPTH + 0.01
	slab.size = Vector3(w, 0.03, d)
	slab.position = Vector3(0, -0.015, 0)
	_felt_mat = _felt_material()
	slab.material = _felt_mat
	csg.add_child(slab)
	for pk in geom.pockets:
		var cyl := CSGCylinder3D.new()
		cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
		cyl.radius = float(pk["hole_r"])
		cyl.height = 0.08
		cyl.sides = 48
		cyl.material = _liner()        # the cut edge of the slate shows inside the pocket: the dark liner, not grey
		var h: Vector2 = pk["hole"]
		cyl.position = Vector3(h.x, -0.02, h.y)
		csg.add_child(cyl)
	_keep(csg)


# ------------------------------------------------------------------ cushions
## The cushions: cloth-covered rubber shaped as on a real table. Seen end on (d = how far behind the nose line,
## y = height above the cloth): the nose, where a ball touches, at 63.5% of the ball's height; below it the face
## slopes back to the cloth (a ball resting on the cushion never touches it, and it reads as a dark line); above it
## a rounded edge that catches the light and the top, rising gently and tucking under the wooden rail. Each section
## runs along its rail and turns into the pockets along the jaw facings.
## (Until v1.1.5 the cushions were built inside out: from the table one saw through them, a black band, worst in AR.)
func _build_cushions() -> void:
	var ch := PoolSim.cushion_height(geom.ball_r)
	var top_h := maxf(rail_height - 0.0015, ch + 0.005)
	var back := CUSHION_DEPTH + 0.004            # 4 mm into the wood, so no seam shows
	var prof := PackedVector2Array([
		Vector2(0.011, 0.0),                     # foot of the face, on the cloth
		Vector2(0.0, ch),                        # the nose
		Vector2(0.0025, ch + 0.0028),            # the rounded edge
		Vector2(0.009, ch + 0.0045),
		Vector2(back, top_h),                    # the top meets the rail
		Vector2(back, 0.0)])                     # (back and underside: hidden, but they close the shape)
	var smooth := [false, true, true, true, false, false]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rc in geom.rail_chains:
		var chain: PackedVector2Array = rc["chain"]
		var out: Vector2 = rc["out"]
		var nseg := chain.size() - 1
		# each segment's outward direction (away from the cloth and the pocket channel)
		var segn: Array[Vector2] = []
		for k in nseg:
			var dvec := (chain[k + 1] - chain[k]).normalized()
			var nrm := Vector2(-dvec.y, dvec.x)
			segn.append(nrm if nrm.dot(out) > 0.0 else -nrm)
		# where each profile point lies at each chain point (mitred at the jaw tips)
		var offs: Array[Vector2] = []
		for k in chain.size():
			if k == 0:
				offs.append(segn[0])
			elif k == nseg:
				offs.append(segn[nseg - 1])
			else:
				var m := (segn[k - 1] + segn[k]).normalized()
				offs.append(m / maxf(m.dot(segn[k]), 0.3))
		var at := func(k: int, pp: Vector2) -> Vector3:
			var q: Vector2 = chain[k] + offs[k] * pp.x
			return Vector3(q.x, pp.y, q.y)
		for k in nseg:
			var o := segn[k]
			for i in prof.size():
				var i2 := (i + 1) % prof.size()
				var face := _prof_normal(prof, i, i2)
				var n_a := _prof_vertex_normal(prof, smooth, i, face, true)
				var n_b := _prof_vertex_normal(prof, smooth, i2, face, false)
				if i == 0:
					# the undercut face looks a little down, so no lamp reaches it and it drew as a black band; it is
					# lit as cloth facing the table instead (a real one gets light bounced off the cloth)
					n_a = Vector2(-1.0, 0.45).normalized()
					n_b = (n_b + n_a).normalized()
				var fa := Vector3(o.x * face.x, face.y, o.y * face.x).normalized()
				var na := Vector3(o.x * n_a.x, n_a.y, o.y * n_a.x).normalized()
				var nb := Vector3(o.x * n_b.x, n_b.y, o.y * n_b.x).normalized()
				var v00: Vector3 = at.call(k, prof[i])
				var v01: Vector3 = at.call(k, prof[i2])
				var v10: Vector3 = at.call(k + 1, prof[i])
				var v11: Vector3 = at.call(k + 1, prof[i2])
				_tri(st, [v00, v10, v11], [na, na, nb], fa)
				_tri(st, [v00, v11, v01], [na, nb, nb], fa)
		# the two ends (inside the pockets): the profile itself
		for e in [0, nseg]:
			var along := (chain[1] - chain[0]).normalized() if e == 0 else (chain[nseg] - chain[nseg - 1]).normalized()
			var cap_n := Vector3(-along.x, 0.0, -along.y) if e == 0 else Vector3(along.x, 0.0, along.y)
			var ring: Array = []
			for pp in prof:
				ring.append(at.call(e, pp))
			for i in range(1, ring.size() - 1):
				_tri(st, [ring[0], ring[i], ring[i + 1]], [cap_n, cap_n, cap_n], cap_n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _felt_material(0.9)
	mi.name = "Cushions"
	_keep(mi)


## The outward normal of profile edge i -> i2 (in profile coordinates: x = back from the nose, y = up).
static func _prof_normal(prof: PackedVector2Array, i: int, i2: int) -> Vector2:
	var d := prof[i2] - prof[i]
	return Vector2(-d.y, d.x).normalized()


## Rounded profile points share their normal with the neighbouring edge, so the nose shades smoothly.
static func _prof_vertex_normal(prof: PackedVector2Array, smooth: Array, i: int, face: Vector2, is_start: bool) -> Vector2:
	if not smooth[i]:
		return face
	var n := prof.size()
	var other := _prof_normal(prof, (i - 1 + n) % n, i) if is_start else _prof_normal(prof, i, (i + 1) % n)
	return (face + other).normalized()


## One triangle, turned so that its front (the side the renderer draws) faces `face_n`.
static func _tri(st: SurfaceTool, v: Array, n: Array, face_n: Vector3) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(face_n) > 0.0:
		order = [0, 2, 1]
	for idx in order:
		st.set_normal(n[idx])
		st.add_vertex(v[idx])


# ------------------------------------------------------------------ wooden frame, skirt, light strip
func _build_frame() -> void:
	var outer_w := geom.length + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH)
	var outer_d := geom.width + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH)
	var y_bot := -0.035
	var csg := CSGCombiner3D.new()
	var outer := CSGBox3D.new()
	outer.size = Vector3(outer_w, rail_height - y_bot, outer_d)
	outer.position.y = (rail_height + y_bot) * 0.5
	outer.material = _wood()
	csg.add_child(outer)
	var inner := CSGBox3D.new()
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.size = Vector3(geom.length + 2.0 * CUSHION_DEPTH, 0.5, geom.width + 2.0 * CUSHION_DEPTH)
	inner.material = _felt_material(0.8)      # the sliver of rail wall above the cushions: the cloth tucked under
	csg.add_child(inner)
	for pk in geom.pockets:
		var cyl := CSGCylinder3D.new()
		cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
		cyl.radius = float(pk["hole_r"]) + 0.006
		cyl.height = 0.5
		cyl.sides = 48
		cyl.material = _liner()        # the wall of the cut through the rail: the pocket's leather, not bare grey
		var h: Vector2 = pk["hole"]
		cyl.position = Vector3(h.x, 0, h.y)
		csg.add_child(cyl)
	_keep(csg)
	# top inlay strip (thin accent line along the rail top)
	var inlay_mat := std_mat(Color("0b1a14"), 0.25, 0.2)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(outer_w - 0.03, 0.002, outer_d - 0.03)
	strip.mesh = sm
	strip.position.y = rail_height - 0.0008
	strip.material_override = inlay_mat
	strip.visible = false
	_keep(strip)
	# skirt / body, with the pockets going down through it (before v1.1.5 its top closed every pocket 3.5 cm down,
	# and one saw the body's top through the hole)
	var skirt := CSGCombiner3D.new()
	var sbox := CSGBox3D.new()
	sbox.size = Vector3(outer_w - 0.03, SKIRT_DEPTH, outer_d - 0.03)
	sbox.material = _part("body", std_mat(skirt_color, 0.4))
	skirt.add_child(sbox)
	for pk in geom.pockets:
		var cut := CSGCylinder3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.radius = float(pk["hole_r"])
		cut.height = SKIRT_DEPTH * 0.5 + 0.01
		cut.sides = 32
		cut.material = _liner()
		var hp: Vector2 = pk["hole"]
		cut.position = Vector3(hp.x, SKIRT_DEPTH * 0.25 + 0.005, hp.y)     # the top half of the body
		skirt.add_child(cut)
	skirt.position.y = y_bot - SKIRT_DEPTH * 0.5
	_keep(skirt)
	# emerald LED strip under the rail lip (signature look)
	var led_mat := std_mat(accent, 0.4, 0.0, accent, float(style.get("led", 2.4)))
	var leds: Array = []
	for side in 4:
		var lm := BoxMesh.new()
		var along_x := side < 2
		var len_ := (outer_w - 0.12) if along_x else (outer_d - 0.12)
		lm.size = Vector3(len_, 0.006, 0.006) if along_x else Vector3(0.006, 0.006, len_)
		var off := (outer_d - 0.03) * 0.5 + 0.002 if along_x else (outer_w - 0.03) * 0.5 + 0.002
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var at := Vector3(0, y_bot - 0.012, sgn * off) if along_x else Vector3(sgn * off, y_bot - 0.012, 0)
		leds.append([lm, Transform3D(Basis(), at)])
	_keep_merged(leds, led_mat, false, "LightStrip")
	# brass corner caps (4 mm thin and flat on the rail: no shadow worth drawing)
	var brass := _part("trim", std_mat(Color("d2aa55"), 0.25, 1.0))
	var caps: Array = []
	var cm := BoxMesh.new()
	cm.size = Vector3(0.05, 0.004, 0.05)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * (outer_w * 0.5 - 0.03), rail_height + 0.001, sz * (outer_d * 0.5 - 0.03))
			caps.append([cm, Transform3D(Basis(Vector3.UP, PI / 4.0), at)])
	_keep_merged(caps, brass, false, "CornerCaps")


# ------------------------------------------------------------------ pockets
## The pocket liner: dark leather, matt (a shiny liner looked like a steel bucket).
func _liner() -> StandardMaterial3D:
	if _liner_mat == null:
		_liner_mat = std_mat(Color("0b0d10"), 0.95)
		_liner_mat.metallic_specular = 0.1
		_liner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _liner_mat


func _build_pockets() -> void:
	var leather := _liner()
	var rim := _part("trim", std_mat(Color("d9dde3"), 0.15, 1.0))
	var cups: Array = []
	var rims: Array = []
	for pk in geom.pockets:
		var h: Vector2 = pk["hole"]
		var r := float(pk["hole_r"])
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.99
		cm.bottom_radius = r * 0.8
		cm.height = 0.11
		cm.cap_top = false
		cm.radial_segments = 32
		cups.append([cm, Transform3D(Basis(), Vector3(h.x, -0.055, h.y))])
		rims.append([_rim_arc(pk, r), Transform3D(Basis(), Vector3(0, rail_height + 0.001, 0))])
	# both keep their shadows: together they are what makes the inside of a pocket dark
	_keep_merged(cups, leather, true, "PocketCups")
	_keep_merged(rims, rim, true, "PocketRims")


## The metal rim of a pocket: only the part of the circle that has rail (or cushion) under it. The part facing
## the table, over the open mouth between the jaws, is left out, so no ring hangs in the air above the hole.
func _rim_arc(pk: Dictionary, r: float) -> ArrayMesh:
	var h: Vector2 = pk["hole"]
	var axis: Vector2 = pk["axis"]
	var mid: Vector2 = pk["mid"]
	var p1: Vector2 = pk["p1"]
	var p2: Vector2 = pk["p2"]
	var t1: Vector2 = pk["t1"]
	var t2: Vector2 = pk["t2"]
	# the open mouth: between the jaw facings, carried on a little past the throat into the hole
	var mouth := PackedVector2Array([p1, t1 + (t1 - p1).normalized() * 0.008, t2 + (t2 - p2).normalized() * 0.008, p2])
	var rc := r + 0.010           # the middle of the tube
	var tube := 0.006
	var n := 96
	var solid: Array = []
	for i in n:
		var d := Vector2.from_angle(TAU * i / n)
		var ok := true
		for rr in [rc - tube, rc, rc + tube]:
			var q: Vector2 = h + d * rr
			if (q - mid).dot(axis) < 0.004 or Geometry2D.is_point_in_polygon(q, mouth):
				ok = false
		solid.append(ok)
	# runs of solid samples, going round the circle (a run may wrap past sample 0)
	var start := solid.find(false)
	if start < 0:
		start = 0
	var runs: Array = []
	var cur: Array = []
	for k in n + 1:
		var i := (start + k) % n
		if solid[i] and k < n:
			cur.append(i)
		elif not cur.is_empty():
			runs.append(cur)
			cur = []
	if solid.find(false) < 0:
		runs = [range(n + 1)]          # nothing open (never for a real pocket): the whole ring
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 10
	var flat := 0.35                   # the rim is a flattened tube, as the old ring was
	for run in runs:
		if run.size() < 2:
			continue
		var rows: Array = []
		for idx in run:
			var ang := TAU * float(idx) / n
			var rad := Vector3(cos(ang), 0, sin(ang))
			var c := Vector3(h.x, 0, h.y) + rad * rc
			var row: Array = []
			for j in segs + 1:
				var ph := TAU * float(j) / segs
				var off := rad * cos(ph) * tube + Vector3.UP * sin(ph) * tube * flat
				var nrm := (rad * cos(ph) + Vector3.UP * sin(ph) / flat).normalized()
				row.append([c + off, nrm])
			rows.append(row)
		for a in rows.size() - 1:
			for j in segs:
				var q00: Array = rows[a][j]
				var q01: Array = rows[a][j + 1]
				var q10: Array = rows[a + 1][j]
				var q11: Array = rows[a + 1][j + 1]
				for v in [q00, q10, q11, q00, q11, q01]:
					st.set_normal(v[1])
					st.add_vertex(v[0])
		# round the two ends off with small caps
		for e in [0, rows.size() - 1]:
			var centre := Vector3.ZERO
			for v in rows[e]:
				centre += v[0]
			centre /= float(rows[e].size())
			var along: Vector3 = (rows[1][0][0] - rows[0][0][0]).normalized() if e == 0 else (rows[e][0][0] - rows[e - 1][0][0]).normalized()
			var tip := centre + along * (tube * (-0.6 if e == 0 else 0.6))
			for j in segs:
				var va: Array = rows[e][j]
				var vb: Array = rows[e][j + 1]
				var tri := [tip, va[0], vb[0]] if e == 0 else [tip, vb[0], va[0]]
				for vv in tri:
					st.set_normal(((vv as Vector3) - centre).normalized() if vv != tip else along * (-1.0 if e == 0 else 1.0))
					st.add_vertex(vv)
	return st.commit()


func _build_diamonds() -> void:
	var pearl := std_mat(Color("f3efe6"), 0.2, 0.0, Color("ffffff"), 0.15)
	# WPA: 18 sights, their centres 3 11/16 in from the cushion nose, a quarter of the width / an eighth of the
	# length apart; diamond sights 1 x 7/16 in, the long way along the rail
	var mid := 0.0937
	var spots: Array = []
	for k in [-3, -2, -1, 1, 2, 3]:
		var x: float = geom.length * k / 8.0
		spots.append([Vector2(x, -(geom.b + mid)), true])
		spots.append([Vector2(x, geom.b + mid), true])
	for k in [-1, 0, 1]:
		var z: float = geom.width * k / 4.0
		spots.append([Vector2(-(geom.a + mid), z), false])
		spots.append([Vector2(geom.a + mid, z), false])
	var side := 0.011
	var dm := BoxMesh.new()
	dm.size = Vector3(side, 0.002, side)
	var long_k := 0.0254 / (side * sqrt(2.0))
	var short_k := 0.0111 / (side * sqrt(2.0))
	var parts: Array = []
	for sp in spots:
		var along_x: bool = sp[1]
		var sc := Vector3(long_k, 1.0, short_k) if along_x else Vector3(short_k, 1.0, long_k)
		var b := Basis.from_scale(sc) * Basis(Vector3.UP, PI / 4.0)      # a square turned on its corner, stretched
		var at: Vector2 = sp[0]
		parts.append([dm, Transform3D(b, Vector3(at.x, rail_height + 0.0006, at.y))])
	# 2 mm inlays flush with the rail: no shadow worth drawing
	_keep_merged(parts, pearl, false, "Diamonds")


func _build_legs() -> void:
	var kind := str(style.get("legs", "classic"))
	var leg_len := maxf(table_height - 0.035 - SKIRT_DEPTH, 0.05)
	var outer_w := geom.length + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH)
	var outer_d := geom.width + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH)
	var top_y := -0.035 - SKIRT_DEPTH
	var mat: Material = _part("leg", _wood())
	if kind == "hover":
		# no legs: four glowing lifters under the body
		var lift := std_mat(accent, 0.4, 0.0, accent, 3.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.07
				tm.outer_radius = 0.1
				ring.mesh = tm
				ring.position = Vector3(sx * (outer_w * 0.5 - 0.3), top_y - 0.015, sz * (outer_d * 0.5 - 0.22))
				ring.material_override = lift
				ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_keep(ring)
				var pod := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.12
				pm.bottom_radius = 0.085
				pm.height = 0.05
				pod.mesh = pm
				pod.position = ring.position + Vector3(0, 0.03, 0)
				pod.material_override = mat
				_keep(pod)
		return
	if kind == "slab":
		for sx in [-1.0, 1.0]:
			_leg_box(Vector3(sx * (outer_w * 0.5 - 0.32), top_y - leg_len * 0.5, 0), Vector3(0.1, leg_len, outer_d * 0.78), mat)
		return
	if kind == "pedestal":
		_leg_box(Vector3(0, top_y - leg_len * 0.5 + 0.03, 0), Vector3(outer_w * 0.46, leg_len - 0.06, outer_d * 0.4), mat)
		_leg_box(Vector3(0, top_y - leg_len + 0.03, 0), Vector3(outer_w * 0.62, 0.06, outer_d * 0.62), mat)
		return
	if kind == "classic" and _leg_scene == null and ResourceLoader.exists("res://assets/models/table_leg.glb"):
		_leg_scene = load("res://assets/models/table_leg.glb")
	var xs := [-1.0, 1.0] if geom.length < 2.6 else [-1.0, 0.0, 1.0]
	for sx in xs:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (outer_w * 0.5 - 0.14), top_y, sz * (outer_d * 0.5 - 0.14))
			if absf(sx) < 0.5:
				p.x = 0.0
			if kind == "classic" and _leg_scene:
				var leg: Node3D = _leg_scene.instantiate()
				leg.position = p
				leg.scale = Vector3(1.0, leg_len / 0.70, 1.0)
				if style.has("leg"):
					for n in leg.find_children("*", "MeshInstance3D", true, false):
						(n as MeshInstance3D).material_override = mat
				_keep(leg)
			elif kind == "block":
				_leg_box(p - Vector3(0, leg_len * 0.5, 0), Vector3(0.15, leg_len, 0.15), mat)
				_leg_box(p - Vector3(0, leg_len - 0.02, 0), Vector3(0.19, 0.04, 0.19), _part("trim", mat))
			elif kind == "crystal":
				# tapering six-sided pillars
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.height = leg_len
				cm.top_radius = 0.1
				cm.bottom_radius = 0.035
				cm.radial_segments = 6
				cm.rings = 1
				mi.mesh = cm
				mi.position = p - Vector3(0, leg_len * 0.5, 0)
				mi.material_override = mat
				_keep(mi)
			else:
				# "tech": slim struts that splay outwards onto round feet
				var foot_at := p + Vector3(sx * 0.16, -leg_len, sz * 0.16)
				_strut(p + Vector3(0, 0.02, 0), foot_at + Vector3(0, 0.02, 0), 0.042, 0.026, mat)
				var foot := MeshInstance3D.new()
				var fm := CylinderMesh.new()
				fm.top_radius = 0.05
				fm.bottom_radius = 0.065
				fm.height = 0.022
				foot.mesh = fm
				foot.position = foot_at + Vector3(0, 0.011, 0)
				foot.material_override = _part("trim", mat)
				_keep(foot)


## A round bar from `a` (radius ra) to `b` (radius rb).
func _strut(a: Vector3, b: Vector3, ra: float, rb: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = a.distance_to(b)
	cm.top_radius = ra
	cm.bottom_radius = rb
	cm.radial_segments = 16
	mi.mesh = cm
	var y := (a - b).normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	mi.material_override = mat
	_keep(mi)


func _leg_box(at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	_keep(mi)


# ------------------------------------------------------------------ decoration
func _build_chalk() -> void:
	var ps := model("res://assets/models/chalk.glb")
	if ps == null:
		return
	var c: Node3D = ps.instantiate()
	c.position = Vector3(geom.a * 0.62, rail_height, geom.b + CUSHION_DEPTH + RAIL_WIDTH * 0.5)
	c.rotation.y = 0.35
	_keep(c)


static func model(path: String) -> PackedScene:
	if not _model_cache.has(path):
		_model_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _model_cache[path]


## World-space footprint helpers for AR placement / cameras.
func outer_size() -> Vector2:
	return Vector2(geom.length + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH), geom.width + 2.0 * (CUSHION_DEPTH + RAIL_WIDTH))
