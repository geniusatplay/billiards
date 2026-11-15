class_name BallView
extends MeshInstance3D
## Visual for one ball: textured clear-coat sphere with true rolling rotation and a pocket-drop animation.

static var _mesh_cache := {}
static var _mat_cache := {}

var number := 0
var radius := 0.028575
var falling := false
var _orient := Basis()
var _tw: Tween


static func make(p_number: int, p_radius: float, ball_set := "balls", special := "") -> BallView:
	var b := BallView.new()
	b.number = p_number
	b.radius = p_radius
	b.mesh = _sphere(p_radius)
	b.material_override = _material(p_number, ball_set, special)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# random initial orientation so racks don't look identical
	var rng := RandomNumberGenerator.new()
	rng.seed = p_number * 7919 + 13
	b._orient = Basis(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized(), rng.randf() * TAU)
	if p_number != 0:
		# keep the number roughly facing up/sideways for readability at rest
		b._orient = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.6))
	b.basis = b._orient
	return b


static func _sphere(r: float) -> SphereMesh:
	var key := snappedf(r, 0.0001)
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 48
		m.rings = 24
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _material(n: int, ball_set: String, special: String) -> Material:
	var key := "%s_%d_%s" % [ball_set, n, special]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var entry := Catalog.ball_set(ball_set)
	if not entry.has("textures"):
		var sm := _shader_material(n, entry)
		_mat_cache[key] = sm
		return sm
	ball_set = entry["textures"]
	var m := StandardMaterial3D.new()
	var path := "res://assets/textures/%s/ball_%d.png" % [ball_set, n]
	if not ResourceLoader.exists(path):
		path = "res://assets/textures/balls/ball_%d.png" % n
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.roughness = 0.1
	m.metallic_specular = 0.75
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.8
	_mat_cache[key] = m
	return m


## A special ball set drawn by the ball shader (see Catalog.BALLS).
static var _style_shaders := {}   # style number -> its own copy of the ball shader


static func _shader_material(n: int, e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var style := int(e.get("style", 0))
	if not _style_shaders.has(style):
		var base_sh: Shader = preload("res://src/game/shaders/ball.gdshader")
		if style == 0:
			_style_shaders[style] = base_sh
		else:
			var sh := Shader.new()
			sh.code = base_sh.code.replace("#define BALL_STYLE 0", "#define BALL_STYLE %d" % style)
			_style_shaders[style] = sh
	m.shader = _style_shaders[style]
	var pal: Array = e["pal"]
	var c := Color(str(e.get("accent", "17b57d"))) if n == 0 else Color(str(pal[(n if n <= 8 else n - 8) - 1]))
	m.set_shader_parameter("number", n)
	m.set_shader_parameter("striped", n > 8)
	m.set_shader_parameter("col", c)
	# "cue": the cue ball's own body colour, for sets whose "white" is dark
	var body := str(e.get("base", "f6f4ec"))
	if n == 0 and e.has("cue"):
		body = str(e["cue"])
	m.set_shader_parameter("base", Color(body))
	m.set_shader_parameter("col2", Color(str(e.get("col2", "000000"))))
	m.set_shader_parameter("disc", Color(str(e.get("disc", "f8f6f0"))))
	var ink := str(e.get("ink", "121216"))
	m.set_shader_parameter("ink", c if ink == "col" else Color(ink))
	m.set_shader_parameter("rough", float(e.get("rough", 0.1)))
	m.set_shader_parameter("metal", float(e.get("metal", 0.0)))
	m.set_shader_parameter("glow", float(e.get("glow", 0.0)))
	m.set_shader_parameter("ink_glow", float(e.get("ink_glow", 0.0)))
	m.set_shader_parameter("glyphs", preload("res://assets/textures/ball_glyphs.png"))
	return m


## Sync with simulator state (table-local metres).
func sync(p: Vector2, w: Vector3, dt: float, h := 0.0) -> void:
	if falling:
		return
	position = Vector3(p.x, radius + h, p.y)
	var wl := w.length()
	if wl > 1e-4 and dt > 0.0:
		_orient = Basis(w / wl, wl * dt) * _orient
		_orient = _orient.orthonormalized()
		basis = _orient


func place(p: Vector2) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	falling = false
	visible = true
	scale = Vector3.ONE
	position = Vector3(p.x, radius, p.y)


## Animate a ball that jumped off the table: keep flying, fall past the table edge, then vanish.
func fly_off(v: Vector2, h: float, vz: float) -> void:
	falling = true
	var start := position
	var vel3 := Vector3(v.x, vz, v.y)
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_method(func(tt: float):
		position = start + vel3 * tt + Vector3(0, -4.9 * tt * tt, 0), 0.0, 0.7, 0.7)
	_tw.tween_callback(func(): visible = false)


## Animate dropping into a pocket hole.
func drop_into(hole: Vector2, depth := 0.07) -> void:
	falling = true
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	var start := position
	var mid := Vector3(hole.x, radius * 0.6, hole.y).lerp(start, 0.35)
	_tw.tween_property(self, "position", mid, 0.08)
	_tw.tween_property(self, "position", Vector3(hole.x, -depth, hole.y), 0.22).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func(): visible = false)
