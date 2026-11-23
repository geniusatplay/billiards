class_name Stage
extends Node3D
## The 3D world: environment + lights, studio lounge, AR camera rig and table placement.
## Table-local coordinates live under `table_root` (metres, life size); its scale is the AR scale.

signal mode_changed(mode: int)
signal placement_changed(placed: bool)
signal ar_message(text: String)
signal free_look_changed(on: bool)

enum Mode { STUDIO, WORLD_AR }
## Walk-around AR start-up. AR is ARCore (Android) or ARKit (iPhone) or nothing: there is no gyro-only fallback.
enum ArState { OFF, CHECKING, PERMISSION, STARTING, RUNNING, BLOCKED }
enum View { OVERVIEW, AIM, TOP }

const STUDIO_FOV := 50.0          # vertical FOV on 16:9 and wider screens
const WIDE_ASPECT := 16.0 / 9.0

var mode := Mode.STUDIO
var view := View.OVERVIEW
var table_root: Node3D
var table_view: TableView
var env: Environment
var studio_cam: Camera3D
var ar_cam: Camera3D
var camera_bg: CameraBackground
var tracker: SensorTracker
var arcore := ARCoreBridge.new()
var placed := false
var adjusting := false
var aim_cam_override := false    # AR: temporarily view through the studio camera
var match_table := ""            # online: the table of the player who breaks ("" = this player's own table)

# studio orbit state
var _yaw := 0.0
var _pitch := deg_to_rad(38.0)
var _dist := 2.6
var _target := Vector3.ZERO
var _want_yaw := 0.0
var _want_pitch := deg_to_rad(38.0)
var _want_dist := 2.6
var _want_target := Vector3.ZERO
var _manual := false
## Free look (top view only, v1.1.5): the player turns, tilts, zooms and slides the camera; it never goes into the table.
var free_look := false
const FL_MIN_PITCH := deg_to_rad(14.0)
const FL_MAX_PITCH := deg_to_rad(89.5)
const FL_MIN_DIST := 0.28          # metres from the point looked at (life size)
const FL_MAX_DIST := 6.0
const FL_CLEAR := 0.14             # the camera stays this far above the cloth while it is over the table
var _focus := Vector2.ZERO
var _aim_yaw := 0.0
var _idle_spin := false

# AR placement state
var _ar_yaw := 0.0
## v1.1.15 (Randy, 18 Nov: "the player should be able to rotate and scale the table size before placing it"): how far
## the player has turned the table from its usual "long side across your view" while placing it. Kept for the launch.
var preview_turn := 0.0
var _ar_pos := Vector3.ZERO
var _ar_scale := 0.28
var _reticle: MeshInstance3D
var _shadow_catcher: MeshInstance3D
var _blob: MeshInstance3D
var _room: Node3D
var _dome: MeshInstance3D        # the scene's surroundings (far mountains, skyline, stars): follows the camera
var _fx: Node3D                  # the scene's drifting particles (snow, fireflies, embers ...)
var _scene: Dictionary = {}
var _ar_scene: Dictionary = {}   # the scene shown round an AR table when "Scene background in AR" is on (new every match)
var _fps_time := 0.0             # frame-rate watch for the showpiece scenes (see _watch_frame_rate)
var _fps_frames := 0
var _mirror_off := false
var watch_frame_rate := true     # (the automated tour turns this off: its software renderer is always slow)
## The scenery that only glows (the dome, the particles) is on its own render layer, which the lights are told to skip.
const UNLIT_LAYER := 1 << 9
## The floor further out than the lamp over the table can reach. The Compatibility renderer draws everything the
## shadow-casting lamp might touch a second time, to add its light; the far floor is kept out of that second
## pass (the lamp's light ends well before it, so the picture is the same).
const FAR_FLOOR_LAYER := 1 << 10
const NEAR_FLOOR_HALF := 5.0     # metres: the lamp's pool of light on the floor is at most about 4 m across
## Drawing order of the big, costly surfaces, so the phone does not work out pixels something nearer will cover
## anyway: first everything else (table, balls, cue), then the floor round it, then the scenery dome behind all.
const FLOOR_PRIORITY := 1
const DOME_PRIORITY := 2
static var _scene_shaders := {}
var _floor: MeshInstance3D
var _floor_far: MeshInstance3D
var _floor_half := -1.0
var _key_light: SpotLight3D
var _sun: DirectionalLight3D
var _touches := {}
var _gesture_start := {}
var _hover: MeshInstance3D
var ar_lift := 0.0             # how far the player has raised (+) / lowered (-) the table since placing it
var _anchor_hold := 0.0        # seconds to wait for ARCore to report a freshly placed anchor
var _preview_ok := false       # a spot on the floor / desk is under the screen centre
var _no_plane_time := 0.0      # walk-around AR: seconds tracking without finding a surface
var ar_state := ArState.OFF
var ar_block := ""             # why AR can't run (ArState.BLOCKED): see ar_block_text()
var _ar_detail := ""
var _ar_timer := 0.0
var _ar_tries := 0
var _ar_restart := false       # a failed start is waiting to be retried
var _perm_asked := false
var _perm_result := 0          # camera permission dialog: 0 waiting, 1 allowed, -1 denied
var _perm_back := false        # the app is in front again after the permission dialog


func _ready() -> void:
	tracker = SensorTracker.new()
	_build_environment()
	_build_room()
	table_root = Node3D.new()
	table_root.name = "TableRoot"
	add_child(table_root)
	table_view = TableView.new()
	table_view.name = "Table"
	table_root.add_child(table_view)
	studio_cam = Camera3D.new()
	studio_cam.fov = STUDIO_FOV
	studio_cam.near = 0.02
	studio_cam.far = 60.0
	add_child(studio_cam)
	ar_cam = Camera3D.new()
	ar_cam.near = 0.01
	ar_cam.far = 60.0
	add_child(ar_cam)
	camera_bg = CameraBackground.new()
	add_child(camera_bg)
	_build_ar_helpers()
	studio_cam.current = true
	rebuild_table()
	apply_scene(Game.scene_style())
	Game.table_changed.connect(rebuild_table)
	Game.settings_changed.connect(_on_setting)
	get_tree().on_request_permissions_result.connect(_on_permission)
	arcore.availability()   # ARCore's first availability check can be "checking": warm it up early


func _on_permission(permission: String, granted: bool) -> void:
	if permission.ends_with("CAMERA"):
		_perm_result = 1 if granted else -1


# ================================================================== building
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("14233a")
	psm.sky_horizon_color = Color("2a3f60")
	psm.ground_bottom_color = Color("05080e")
	psm.ground_horizon_color = Color("1b2a44")
	psm.sun_angle_max = 0.0
	psm.energy_multiplier = 1.0
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-62, 28, 0)
	_sun.light_energy = 1.1
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 8.0
	_sun.shadow_blur = 1.5
	add_child(_sun)
	_key_light = SpotLight3D.new()
	_key_light.position = Vector3(0, 2.0, 0)
	_key_light.rotation_degrees = Vector3(-90, 0, 0)
	_key_light.spot_angle = 58.0
	_key_light.spot_range = 6.0
	_key_light.light_energy = 3.6
	_key_light.spot_attenuation = 0.6
	_key_light.light_color = Color("fff3e0")
	_key_light.shadow_enabled = true
	add_child(_key_light)


func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "StudioRoom"
	add_child(_room)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(NEAR_FLOOR_HALF * 2.0, NEAR_FLOOR_HALF * 2.0)
	# A grid of 83 cm squares rather than two big triangles: this renderer works out where the lamp's shadow falls
	# at the corners of each triangle, so on two huge triangles the table's shadow under the lamp landed slightly
	# off. With the grid it is where it really is (checked against a floor in 25 cm squares: no pixel differs).
	pm.subdivide_width = 11
	pm.subdivide_depth = 11
	floor_mi.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://src/game/shaders/studio_floor.gdshader")
	fm.render_priority = FLOOR_PRIORITY
	floor_mi.material_override = fm
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # nothing lies under the floor
	_room.add_child(floor_mi)
	_floor = floor_mi
	_floor_far = MeshInstance3D.new()
	_floor_far.material_override = fm
	_floor_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_far.layers = FAR_FLOOR_LAYER
	_room.add_child(_floor_far)
	_set_floor_size(9.0)
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 50.0
	sm.height = 100.0
	sm.radial_segments = 32
	sm.rings = 16
	_dome.mesh = sm
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.layers = UNLIT_LAYER
	_sun.light_cull_mask &= ~UNLIT_LAYER
	_sun.shadow_caster_mask &= ~UNLIT_LAYER
	_key_light.light_cull_mask &= ~(UNLIT_LAYER | FAR_FLOOR_LAYER)
	_key_light.shadow_caster_mask &= ~UNLIT_LAYER
	_dome.visible = false
	_room.add_child(_dome)
	_fx = Node3D.new()
	_room.add_child(_fx)


func _build_ar_helpers() -> void:
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.11
	tm.rings = 48
	_reticle.mesh = tm
	_reticle.scale = Vector3(1, 0.05, 1)
	_reticle.material_override = TableView.std_mat(UIKit.EMERALD, 0.5, 0.0, UIKit.EMERALD, 2.0)
	_reticle.visible = false
	add_child(_reticle)
	_shadow_catcher = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	_shadow_catcher.mesh = pm
	var sc := StandardMaterial3D.new()
	sc.shadow_to_opacity = true
	sc.albedo_color = Color(0, 0, 0, 0.9)
	sc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc.roughness = 1.0
	_shadow_catcher.material_override = sc
	_shadow_catcher.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_catcher.visible = false
	add_child(_shadow_catcher)
	_blob = MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(1, 1)
	_blob.mesh = bm
	var bs := ShaderMaterial.new()
	bs.shader = preload("res://src/game/shaders/contact_shadow.gdshader")
	_blob.material_override = bs
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.visible = false
	add_child(_blob)
	_hover = MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(1, 1)
	_hover.mesh = hm
	var hs := ShaderMaterial.new()
	hs.shader = preload("res://src/game/shaders/hover_glow.gdshader")
	_hover.material_override = hs
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)


## In AR the table stands on the real floor (or desk) like a real table. Debug → AR → "Floating table"
## hovers it in mid-air instead.
func floating() -> bool:
	return mode != Mode.STUDIO and bool(Game.get_s("ar_float"))


## Shadow / glow under the table depending on how it's shown.
func _update_ar_decor() -> void:
	var ar := mode != Mode.STUDIO and not aim_cam_override
	var show := ar and table_root.visible and not ar_background_on()   # a scene has its own floor
	_hover.visible = show and floating()
	_blob.visible = show and not floating()
	_shadow_catcher.visible = show and not floating()


## Height of the cloth above the table_root's base point: 0 when floating (the base IS the cloth).
func _table_height() -> float:
	return 0.0 if floating() else float(Game.get_s("table_height"))


func rebuild_table() -> void:
	var g := Game.make_table()
	table_view.build(g, table_style(), float(Game.get_s("rail_height")), float(Game.get_s("table_height")), bool(Game.get_s("show_legs")) and not floating())
	_layout_table()


## The look of the table on show: the player's own, or in an online match the one of the player who breaks.
func table_style() -> Dictionary:
	return Catalog.table(match_table) if match_table != "" else Game.table_style()


## One copy of a scene shader per scene: the copy has that scene's numbers written into it, so the phone
## only compiles the code of the scene being shown.
static func _scene_shader(path: String, floor_style: int, sky: int) -> Shader:
	if floor_style == 0 and sky == 0:
		return load(path)
	var key := "%s|%d|%d" % [path, floor_style, sky]
	if not _scene_shaders.has(key):
		var base: Shader = load(path)
		var sh := Shader.new()
		sh.code = base.code.replace("#define FLOOR_STYLE 0", "#define FLOOR_STYLE %d" % floor_style).replace("#define SCENE_STYLE 0", "#define SCENE_STYLE %d" % sky)
		_scene_shaders[key] = sh
	return _scene_shaders[key]


## Apply a Catalog.SCENES entry to the Studio room: floor, surroundings, particles and lighting.
func apply_scene(sc: Dictionary) -> void:
	FpsCounter.mark("scene " + str(sc.get("id", "")))
	_scene = sc
	var sky: int = sc.get("sky", 0)
	var ground: Color = sc.get("ground", Color(0.02, 0.03, 0.05))
	var gv := Vector3(ground.r, ground.g, ground.b)
	var fm: ShaderMaterial = _floor.material_override
	fm.shader = _scene_shader("res://src/game/shaders/studio_floor.gdshader", int(sc.get("floor_style", 0)), sky)
	var tint: Color = sc.get("floor", Color.WHITE)
	fm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	fm.set_shader_parameter("ground", gv)
	fm.set_shader_parameter("mirror_k", 0.0 if _mirror_off else 1.0)
	_set_floor_size(9.0 if sky == 0 else 45.0)
	_dome.visible = sky != 0
	if sky != 0:
		var dm := ShaderMaterial.new()
		dm.shader = _scene_shader("res://src/game/shaders/backdrop.gdshader", 0, sky)
		dm.set_shader_parameter("ground", gv)
		dm.set_shader_parameter("open_below", 1.0 if sc.get("open", false) else 0.0)
		dm.render_priority = DOME_PRIORITY
		_dome.material_override = dm
	_build_fx(str(sc.get("fx", "")))
	_apply_look()
	_fps_time = -3.0
	_fps_frames = 0


## Loading screen (main._warm_up): the table drawn once the way walk-around AR shows it (the camera picture
## behind, no lamp, the soft shadow under the table), so those versions of the shaders are ready too.
var _warm_ar := false

func warm_ar_look(on: bool) -> void:
	env.background_mode = Environment.BG_CANVAS if on else Environment.BG_SKY
	env.background_canvas_max_layer = -1
	_room.visible = not on
	_key_light.visible = not on
	_blob.visible = on
	_shadow_catcher.visible = on
	_hover.visible = on
	camera_bg.warm(on)
	_warm_ar = on
	_apply_look()
	if not on:
		_update_ar_decor()


## The floor reaches `half` metres out from the table's centre each way: a square under the lamp, and round it a
## frame out to the edge (the same surface, one shader; only the lamp's second pass leaves the frame out).
func _set_floor_size(half: float) -> void:
	if is_equal_approx(half, _floor_half):
		return
	_floor_half = half
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := NEAR_FLOOR_HALF
	var w := half - a
	# four strips round the middle square: two long ones (front and back), two short ones (the sides)
	for strip in [[Vector2(half * 2.0, w), Vector2(0, a + w * 0.5)], [Vector2(half * 2.0, w), Vector2(0, -(a + w * 0.5))],
			[Vector2(w, a * 2.0), Vector2(a + w * 0.5, 0)], [Vector2(w, a * 2.0), Vector2(-(a + w * 0.5), 0)]]:
		var pm := PlaneMesh.new()
		pm.size = strip[0]
		var at: Vector2 = strip[1]
		st.append_from(pm, 0, Transform3D(Basis(), Vector3(at.x, 0.0, at.y)))
	_floor_far.mesh = st.commit()


## AR with "Scene background in AR" on: once the table is placed, the camera picture gives way to a scene.
## (Not before: you need to see your room to find the floor and put the table down.)
func ar_background_on() -> bool:
	return mode != Mode.STUDIO and placed and bool(Game.get_s("ar_background")) and not aim_cam_override


## A different scene for every match played with the AR background.
func new_match_scene() -> void:
	_pick_ar_scene()
	_update_ar_scene()


## The scene round the AR table right now ("" = none picked yet), and choosing one by hand (pause menu).
func ar_scene_id() -> String:
	return str(_ar_scene.get("id", ""))


func set_ar_scene(id: String) -> void:
	var e: Dictionary = Catalog.find(Catalog.SCENES, id)
	if str(e.get("id", "")) != id or int(e.get("sky", 0)) == 0 or not e.get("ready", true):
		return
	_ar_scene = e
	_update_ar_scene()


func _pick_ar_scene() -> void:
	var pool := Catalog.SCENES.filter(func(e): return int(e.get("sky", 0)) != 0 and e.get("ready", true) and e.get("id") != _ar_scene.get("id", ""))
	if not pool.is_empty():
		_ar_scene = pool[randi() % pool.size()]


## Camera picture or scene behind the AR table, whichever applies right now.
func _update_ar_scene() -> void:
	if mode == Mode.STUDIO:
		if _scene != Game.scene_style():
			apply_scene(Game.scene_style())
		return
	if aim_cam_override:
		return
	var on := ar_background_on()
	if on and _ar_scene.is_empty():
		_pick_ar_scene()
	on = on and not _ar_scene.is_empty()
	if on and _scene != _ar_scene:
		apply_scene(_ar_scene)
	camera_bg.set_visible_feed(not on)
	env.background_mode = Environment.BG_SKY if on else Environment.BG_CANVAS
	_room.visible = on
	_key_light.visible = on
	_layout_table()
	_apply_look()
	_update_ar_decor()


## Lighting for what is on screen: the scene's own light in the Studio room, plain daylight on a real room (AR).
func _apply_look() -> void:
	FpsCounter.mark("lighting set")
	var sc: Dictionary = _scene if (_room and _room.visible) else {}
	_key_light.light_color = sc.get("lamp", Color("fff1d6"))
	_key_light.light_energy = sc.get("lamp_e", 3.6)
	_sun.light_color = sc.get("sun_col", Color.WHITE)
	_sun.light_energy = sc.get("sun_e", 1.1)
	_sun.shadow_opacity = sc.get("shadow", 1.0)
	if sc.has("sun"):
		# the scene's sun or moon; kept at least 40 degrees up so shadows on the cloth stay short
		var s: Vector3 = sc["sun"]
		var flat := Vector2(s.x, s.z)
		if flat.length() < 0.05:
			_sun.rotation_degrees = Vector3(-88, 0, 0)
		else:
			flat = flat.normalized()
			var el := maxf(atan2(s.y, Vector2(s.x, s.z).length()), deg_to_rad(40.0))
			var dir := Vector3(flat.x * cos(el), sin(el), flat.y * cos(el))
			_sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
	else:
		_sun.rotation_degrees = Vector3(-62, 28, 0)
	env.ambient_light_energy = sc.get("amb", 0.75)
	# Only when they really change: any change to the sky makes the renderer draw it again into the cube it lights
	# the balls and the cloth from (six views plus smoothing), a heavy job; the menu and every match start used to
	# ask for it with the same colours.
	var psm: ProceduralSkyMaterial = env.sky.sky_material
	# a real room (AR, camera picture): plain light from all round, as a room's. (Until v1.1.5 the dark blue of the
	# Studio night lit the AR table too: dark cloth, cushions hard to make out.)
	var real_room := (mode != Mode.STUDIO or _warm_ar) and not (_room and _room.visible)
	var top: Color = sc.get("sky_top", Color("8e949c") if real_room else Color("14233a"))
	var hor: Color = sc.get("sky_horizon", Color("7c8189") if real_room else Color("2a3f60"))
	if psm.sky_top_color != top:
		psm.sky_top_color = top
	if psm.sky_horizon_color != hor:
		psm.sky_horizon_color = hor
	if psm.ground_horizon_color != hor:
		psm.ground_horizon_color = hor


## The scene's drifting particles: small, slow and few, decoration that never gets in the way of a shot.
## One mesh of quads; scene_fx.gdshader moves them (see the note there on why particle nodes are not used).
func _build_fx(kind: String) -> void:
	for c in _fx.get_children():
		c.queue_free()
	# kind: [half-size of the volume, height of its centre, drift, wander, size min, size max, colour, seconds per blink, blink, ring, (unused), how many]
	var specs := {
		"snow": [Vector3(5, 1.7, 5), 1.7, Vector3(0.03, -0.28, 0.02), 0.06, 0.022, 0.042, Color(1.0, 1.0, 1.0, 0.9), 6.0, 0.0, 0.0, true, 220],
		"fireflies": [Vector3(4.5, 0.8, 4.5), 1.15, Vector3.ZERO, 0.12, 0.02, 0.036, Color(1.6, 2.0, 0.5, 1.0), 5.0, 1.0, 0.0, true, 80],
		"embers": [Vector3(4.5, 1.6, 4.5), 1.6, Vector3(0.03, 0.42, 0.0), 0.1, 0.012, 0.026, Color(2.2, 0.8, 0.2, 1.0), 4.0, 1.0, 0.0, true, 90],
		"bubbles": [Vector3(4.5, 1.8, 4.5), 1.8, Vector3(0.0, 0.26, 0.0), 0.04, 0.03, 0.065, Color(0.8, 1.0, 1.0, 0.55), 6.0, 0.0, 1.0, false, 50],
		"sparkles": [Vector3(4.5, 1.2, 4.5), 1.4, Vector3.ZERO, 0.02, 0.014, 0.028, Color(0.8, 1.5, 1.9, 1.0), 3.5, 1.0, 0.0, true, 50],
		"motes": [Vector3(4.5, 1.2, 4.5), 1.3, Vector3(0.05, 0.01, 0.02), 0.04, 0.014, 0.026, Color(1.9, 1.45, 0.7, 1.0), 7.0, 1.0, 0.0, true, 40],
		"sand": [Vector3(5, 0.15, 5), 0.17, Vector3(0.8, 0.0, 0.25), 0.05, 0.007, 0.013, Color(1.0, 0.8, 0.55, 0.3), 5.0, 1.0, 0.0, true, 50],
		"stardust": [Vector3(5, 1.5, 5), 1.5, Vector3.ZERO, 0.015, 0.012, 0.022, Color(1.3, 1.5, 2.0, 1.0), 6.0, 1.0, 0.0, true, 36],
	}
	if not specs.has(kind):
		return
	var s: Array = specs[kind]
	var n: int = s[11]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var seed := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3.ZERO)
			uvs.append(corner)
			cols.append(seed)
		idx.append_array(PackedInt32Array([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/game/shaders/scene_fx.gdshader")
	var half: Vector3 = s[0]
	var col: Color = s[6]
	mat.set_shader_parameter("box", half)
	mat.set_shader_parameter("drift", s[2])
	mat.set_shader_parameter("wander", s[3])
	mat.set_shader_parameter("size_min", s[4])
	mat.set_shader_parameter("size_max", s[5])
	mat.set_shader_parameter("tint", Vector4(col.r, col.g, col.b, col.a))
	mat.set_shader_parameter("life", s[7])
	mat.set_shader_parameter("blink", s[8])
	mat.set_shader_parameter("ring", s[9])
	var foot := table_view.outer_size() * 0.5 if table_view and table_view.geom else Vector2(1.4, 0.8)
	mat.set_shader_parameter("keep_out", foot + Vector2(0.12, 0.12))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.custom_aabb = AABB(-half, half * 2.0)
	mi.position = Vector3(0, s[1], 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = UNLIT_LAYER
	_fx.add_child(mi)


func _on_setting(k: String) -> void:
	if k == "table_style":
		rebuild_table()
	if k == "scene" and (mode == Mode.STUDIO or not ar_background_on()):
		apply_scene(Game.scene_style())
	if k == "ar_background":
		_update_ar_scene()
	if k in ["surface", "ar_scale_desk", "ar_scale_floor", "eye_height_desk", "eye_height_floor", "table_height", "table_height_desk"]:
		_ar_scale = _surface_scale()
		if k == "table_height" and mode == Mode.STUDIO:
			rebuild_table()
		_layout_table()
	if k == "cam_zoom":
		_layout_table()
	if k == "camera_fov":
		ar_cam.fov = float(Game.get_s("camera_fov"))
	if k == "ar_float" and mode != Mode.STUDIO:
		rebuild_table()
		_update_ar_decor()


# ================================================================== modes
func is_ar() -> bool:
	return mode != Mode.STUDIO


func set_mode(m: int) -> void:
	mode = m
	aim_cam_override = false
	match mode:
		Mode.STUDIO:
			camera_bg.stop()
			arcore.stop()
			ar_state = ArState.OFF
			env.background_mode = Environment.BG_SKY
			_room.visible = true
			_key_light.visible = true
			_apply_look()
			_shadow_catcher.visible = false
			_blob.visible = false
			_hover.visible = false
			_reticle.visible = false
			studio_cam.current = true
			table_root.visible = true
			placed = true
		Mode.WORLD_AR:
			env.background_mode = Environment.BG_CANVAS
			env.background_canvas_max_layer = -1
			_room.visible = false
			_key_light.visible = false
			_apply_look()
			camera_bg.start_external()
			ar_cam.current = true
			table_root.visible = false   # until the floor is found
			_ar_scale = _surface_scale()
			_perm_asked = false
			_begin_ar()
	rebuild_table()
	_update_ar_scene()
	_update_ar_decor()
	mode_changed.emit(mode)
	if mode == Mode.STUDIO:
		# Studio never needs placement — release anything waiting on it (e.g. camera failed mid-setup)
		placement_changed.emit(true)


## Pause menu: change between the Studio view and walk-around AR in the middle of a match. The balls stay as
## they are; going to AR, the table has to be put down in the room first (the HUD shows its placing panel).
func switch_mode(m: int) -> void:
	if m == mode:
		return
	adjusting = false
	set_mode(m)
	if m != Mode.STUDIO:
		placement_changed.emit(false)


## What a match should start in: walk-around AR on phones that can run it, otherwise the Studio view.
func auto_mode() -> int:
	if Game.get_s("ar_mode") == "studio":
		return Mode.STUDIO
	if arcore.simulate or (OS.get_name() in ["Android", "iOS"] and arcore.has_plugin()):
		return Mode.WORLD_AR
	return Mode.STUDIO


# ------------------------------------------------------------------ walk-around AR start-up
func _has_camera_permission() -> bool:
	return OS.get_name() != "Android" or "android.permission.CAMERA" in OS.get_granted_permissions()


func _begin_ar() -> void:
	arcore.stop()
	ar_state = ArState.CHECKING
	ar_block = ""
	_ar_timer = 0.0
	_ar_tries = 0
	_ar_restart = false
	placed = false
	_preview_ok = false
	_no_plane_time = 0.0
	table_root.visible = false
	_update_ar_decor()


## "Try again" in the AR panel, and automatically when the player comes back from the Play Store / Settings.
func retry_ar() -> void:
	if mode != Mode.WORLD_AR:
		return
	_perm_asked = false
	camera_bg.start_external()
	_begin_ar()


func _block_ar(code: String) -> void:
	var err := arcore.last_error()
	var info := arcore.info()
	arcore.stop()
	ar_state = ArState.BLOCKED
	ar_block = code
	_ar_detail = "%s%s" % [(err + " · ") if err != "" else "", info]
	print("[ar] can't start (%s): %s" % [code, _ar_detail])


func _start_session() -> void:
	_ar_restart = false
	_ar_timer = 0.0
	ar_state = ArState.STARTING
	if not arcore.start(DisplayServer.window_get_size()):
		_block_ar("failed")


static func _classify(err: String) -> String:
	if err.contains("ArcoreNotInstalled"):
		return "not_installed"
	if err.contains("ApkTooOld"):
		return "too_old"
	if err.contains("DeviceNotCompatible"):
		return "unsupported"
	if err.contains("SdkTooOld"):
		return "sdk_old"
	if err.contains("SecurityException") or err.to_lower().contains("permission"):
		return "permission"
	if err.contains("CameraNotAvailable"):
		return "camera"
	return "failed"


func _ar_step(delta: float) -> void:
	_ar_timer += delta
	match ar_state:
		ArState.CHECKING:
			var a := arcore.availability()
			match a:
				"installed":
					if _has_camera_permission():
						_start_session()
					elif _perm_asked:
						_block_ar("permission")
					else:
						_perm_asked = true
						_perm_result = 0
						_perm_back = false
						ar_state = ArState.PERMISSION
						OS.request_permission("android.permission.CAMERA")
				"checking":
					if _ar_timer > 12.0:
						_block_ar("timeout")
				"none", "unsupported", "not_installed", "too_old":
					_block_ar(a)
				_:
					if _ar_timer > 3.0:
						_block_ar("failed")
		ArState.PERMISSION:
			if _has_camera_permission() or _perm_result == 1:
				ar_state = ArState.CHECKING
				_ar_timer = 0.0
			elif _perm_result == -1 or (_perm_back and _ar_timer > 1.5):
				_block_ar("permission")
		ArState.STARTING:
			if _ar_restart:
				if _ar_timer >= 0.0:
					_start_session()
				return
			arcore.poll()
			if arcore.status == 1:
				ar_state = ArState.RUNNING
				print("[ar] walk-around AR running: ", arcore.info())
			elif arcore.status == -1:
				_ar_tries += 1
				var code := _classify(arcore.last_error())
				if code == "failed" and _ar_tries < 3:
					print("[ar] start failed (%s), retrying" % arcore.last_error())
					_ar_restart = true
					_ar_timer = -0.8
				else:
					_block_ar(code)
			elif _ar_timer > 25.0 and not arcore.asking_permission:
				_block_ar("timeout")   # (not while iOS is asking the player for the camera: that waits for them)


## Plain-language reason AR isn't running, and what to do about it.
func ar_block_text() -> String:
	match ar_block:
		"none": return "Walk-around AR isn't included in this build of the game."
		"unsupported": return "This device doesn't support Apple ARKit, so AR can't run on it." if arcore.ios else "This phone doesn't support Google ARCore, so AR can't run on it."
		"not_installed": return "AR needs Google Play Services for AR (free, from Google). Install it, then come back to the game."
		"too_old": return "Google Play Services for AR needs an update. Update it, then come back to the game."
		"sdk_old": return "This version of the game is too old for the AR services on this phone."
		"permission": return "AR needs one permission: the camera, to find your floor (the picture stays on your phone). Allow camera access for Emerald 8 Ball Pool, then tap Try again, or play in place with no camera."
		"camera": return "The camera is being used by another app. Close other camera apps, then try again."
		"timeout": return "AR took too long to start. Try again."
	return "AR couldn't start. Try again."


## Technical line under it (error + device facts) so a screenshot is enough to diagnose a problem.
func ar_detail() -> String:
	return _ar_detail


func ar_can_install() -> bool:
	return ar_state == ArState.BLOCKED and ar_block in ["not_installed", "too_old"]


func install_world_ar() -> void:
	arcore.request_install()


func open_app_settings() -> void:
	arcore.open_app_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if ar_state == ArState.PERMISSION:
			_perm_back = true
			_ar_timer = 0.0
		elif what == NOTIFICATION_APPLICATION_RESUMED and ar_state == ArState.BLOCKED and ar_block in ["not_installed", "too_old", "permission", "camera"]:
			# back from the Play Store / Settings / another camera app: see if AR can start now
			retry_ar()
	elif what == NOTIFICATION_WM_SIZE_CHANGED and arcore.running:
		arcore.set_view_size(DisplayServer.window_get_size())


func _surface_scale() -> float:
	return float(Game.get_s("ar_scale_floor")) if Game.get_s("surface") == "floor" else float(Game.get_s("ar_scale_desk"))


func _eye_height() -> float:
	return float(Game.get_s("eye_height_floor")) if Game.get_s("surface") == "floor" else float(Game.get_s("eye_height_desk"))


func active_camera() -> Camera3D:
	if mode == Mode.STUDIO or aim_cam_override:
		return studio_cam
	return ar_cam


func set_aim_cam(on: bool) -> void:
	if mode == Mode.STUDIO:
		return
	aim_cam_override = on
	camera_bg.set_visible_feed(not on)
	env.background_mode = Environment.BG_SKY if on else Environment.BG_CANVAS
	_room.visible = on
	_key_light.visible = on
	_apply_look()
	_update_ar_decor()
	if on:
		studio_cam.current = true
		_snap_orbit()
	else:
		active_camera().current = true
		_update_ar_scene()   # camera picture or AR scene again


# ================================================================== layout & cameras
func table_scale() -> float:
	return 1.0 if mode == Mode.STUDIO else _ar_scale


func _layout_table() -> void:
	if table_root == null or table_view.geom == null:
		return
	var h := _table_height()
	if mode == Mode.STUDIO:
		table_root.transform = Transform3D(Basis(), Vector3(0, h, 0))
		_room.transform = Transform3D.IDENTITY
		_key_light.position = Vector3(0, h + 1.35, 0)
		_key_light.spot_range = 6.0
		_sun.directional_shadow_max_distance = 8.0
	else:
		var s := _ar_scale
		table_root.transform = Transform3D(Basis(Vector3.UP, _ar_yaw).scaled(Vector3.ONE * s), _ar_pos + Vector3(0, h * s, 0))
		# the scene's floor lies where the table stands, turned and sized with it (a floating table keeps its usual height above it)
		var drop := float(Game.get_s("table_height")) * s if floating() else 0.0
		_room.transform = Transform3D(Basis(Vector3.UP, _ar_yaw).scaled(Vector3.ONE * s), _ar_pos - Vector3(0, drop, 0))
		# the lamp over the table, for when a scene stands in for the room (same light at any table size)
		_key_light.position = _ar_pos + Vector3(0, (h + 1.35) * s, 0)
		_key_light.spot_range = 6.0 * s
		_shadow_catcher.position = _ar_pos + Vector3(0, 0.0005, 0)
		var fs := table_view.outer_size() * s
		_blob.position = _ar_pos + Vector3(0, 0.001, 0)
		_blob.scale = Vector3(fs.x * 1.25, 1, fs.y * 1.35)
		_blob.rotation.y = _ar_yaw
		# glow halo just under the floating table's body
		_hover.position = _ar_pos + Vector3(0, -(0.045 + TableView.SKIRT_DEPTH) * s, 0)
		_hover.scale = Vector3(fs.x * 1.6, 1, fs.y * 2.0)
		_hover.rotation.y = _ar_yaw
		_sun.directional_shadow_max_distance = 3.0 if s < 0.5 else 8.0
	var size := table_view.outer_size()
	_want_dist = (maxf(size.x, size.y) * 1.05 + 0.6) * _zoom()


## Developer tools → Camera zoom (v1.1.15): the camera's default distance from the table, nearer (< 1) or further
## back (> 1), in Play in place and in the views that look past the AR table (overview, aim).
static func _zoom() -> float:
	return clampf(float(Game.get_s("cam_zoom")), 0.4, 2.5)


func set_focus(ball_local: Vector2, aim_yaw: float) -> void:
	_focus = ball_local
	_aim_yaw = aim_yaw


func set_view(v: int) -> void:
	if free_look:
		set_free_look(false)
	view = v
	_manual = false


## Free look on / off (only in the top view). The camera starts from where it is; switching off leaves it there
## (aiming works from any view), and choosing the top view again frames the whole table.
func set_free_look(on: bool) -> void:
	on = on and view == View.TOP
	if on == free_look:
		return
	free_look = on
	_touches.clear()
	if on:
		_manual = true
		_want_target = _target
		_want_yaw = _yaw
		_want_pitch = clampf(_pitch, FL_MIN_PITCH, FL_MAX_PITCH)
		_want_dist = _dist
		_keep_clear()
	free_look_changed.emit(on)


## The top view's own framing: straight down on the whole table.
func _top_frame() -> void:
	var s := table_scale()
	var size := table_view.outer_size()
	_want_target = table_root.global_transform * Vector3.ZERO
	_want_pitch = deg_to_rad(88.0)
	_want_yaw = _closest_angle(_want_yaw, (_ar_yaw if mode != Mode.STUDIO else 0.0))
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_fov := deg_to_rad(studio_cam.fov * 0.5)
	var need_h := size.y * 0.5 * 1.08
	var need_w := size.x * 0.5 * 1.04 / aspect
	_want_dist = maxf(need_h, need_w) / tan(half_fov) * s


## Free look: back to the whole table seen from straight above (free look stays on).
func free_look_reset() -> void:
	if free_look:
		_top_frame()


## Buttons: turn left / right (`d_yaw`), tilt up / down (`d_pitch`, up = more from above), zoom (`zoom` < 1 = in).
func free_look_step(d_yaw: float, d_pitch: float, zoom := 1.0) -> void:
	if not free_look:
		return
	var s := table_scale()
	_want_yaw += d_yaw
	_want_pitch = clampf(_want_pitch + d_pitch, FL_MIN_PITCH, FL_MAX_PITCH)
	_want_dist = clampf(_want_dist * zoom, FL_MIN_DIST * s, FL_MAX_DIST * s)
	_keep_clear()


## One finger dragged from `a` to `b` on the screen: the camera slides at its height so the spot under the finger
## stays under the finger (as dragging a map).
func free_look_pan(a: Vector2, b: Vector2) -> void:
	var y := table_root.global_position.y
	var h0 = _plane_hit_cam(studio_cam, a, y)
	var h1 = _plane_hit_cam(studio_cam, b, y)
	if h0 == null or h1 == null:
		return
	var d: Vector3 = (h0 as Vector3) - (h1 as Vector3)
	var lim := 0.25 * maxf(_want_dist, 0.3)          # far off near the horizon a small finger move is a long way
	if d.length() > lim:
		d = d.normalized() * lim
	_want_target += Vector3(d.x, 0.0, d.z)
	_keep_clear()


## The point looked at stays on the table; the camera never goes into the table: over
## the table it keeps FL_CLEAR above the cloth, and beside it it stays above the rail.
func _keep_clear() -> void:
	var s := table_scale()
	var xf := table_root.global_transform
	var half := table_view.outer_size() * 0.5
	var local := xf.affine_inverse() * _want_target
	local.x = clampf(local.x, -half.x, half.x)
	local.z = clampf(local.z, -half.y, half.y)
	local.y = 0.0
	_want_target = xf * local
	for _i in 3:
		var off := Vector3(sin(_want_yaw) * cos(_want_pitch), sin(_want_pitch), cos(_want_yaw) * cos(_want_pitch)) * _want_dist
		var cam_local := xf.affine_inverse() * (_want_target + off)
		var over := absf(cam_local.x) < half.x + 0.08 and absf(cam_local.z) < half.y + 0.08
		var need := FL_CLEAR if over else (table_view.rail_height + 0.06)
		if cam_local.y >= need:
			break
		# lift it: closer to straight down first, then further away
		var want_up := need * s
		var sp := sin(_want_pitch)
		if _want_dist * sp < want_up:
			_want_dist = minf(want_up / maxf(sp, 0.05) * 1.02, FL_MAX_DIST * s)
			if _want_dist * sin(_want_pitch) < want_up:
				_want_pitch = minf(asin(clampf(want_up / _want_dist, 0.0, 1.0)) + 0.02, FL_MAX_PITCH)


## Where the screen point `sp` looks onto the horizontal plane at height `y` (world), through camera `cam`.
func _plane_hit_cam(cam: Camera3D, sp: Vector2, y: float) -> Variant:
	var o := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	if absf(dir.y) < 1e-4:
		return null
	var t := (y - o.y) / dir.y
	if t <= 0.0:
		return null
	return o + dir * t


func set_idle_spin(on: bool) -> void:
	_idle_spin = on


## The mirrored floors are the most expensive part of the showpiece scenes. If a phone cannot keep up (under
## 40 frames a second for four seconds running), the mirror is switched off for the rest of the session:
## the scene keeps its look, the floor just stops reflecting it.
func _watch_frame_rate(delta: float) -> void:
	if _mirror_off or not watch_frame_rate or int(_scene.get("sky", 0)) == 0:
		return
	_fps_time += delta
	if _fps_time < 0.0:
		return   # the first seconds of a scene include preparing its shaders
	_fps_frames += 1
	if _fps_time >= 4.0:
		if _fps_frames / _fps_time < 40.0 and DisplayServer.get_name() != "headless":
			_mirror_off = true
			(_floor.material_override as ShaderMaterial).set_shader_parameter("mirror_k", 0.0)
			print("[scene] slow frames (%.0f a second): floor mirror switched off" % (_fps_frames / _fps_time))
		_fps_time = 0.0
		_fps_frames = 0


func _process(delta: float) -> void:
	if _dome.visible and _room.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_dome.global_position = cam.global_position
		_watch_frame_rate(delta)
	match mode:
		Mode.WORLD_AR:
			if OS.has_feature("mobile"):
				tracker.update(delta)   # Phone Cue's stroke sensing
			if ar_state != ArState.RUNNING:
				if ar_state != ArState.BLOCKED and ar_state != ArState.OFF:
					_ar_step(delta)
				return
			if arcore.status == -1:
				_block_ar(_classify(arcore.last_error()))
				return
			if arcore.resume_failures >= 20 and arcore.frame < 0:
				_block_ar("camera")   # ~5 s of failing to open the camera
				return
			if arcore.poll():
				camera_bg.push_external(arcore.img_size, arcore.image_y(), arcore.image_uv(), arcore.uv_o, arcore.uv_x, arcore.uv_y)
			ar_cam.transform = arcore.pose
			ar_cam.fov = arcore.fov
			if not placed:
				if arcore.tracking == 2:
					_no_plane_time = 0.0 if arcore.hit_valid else _no_plane_time + delta
					_update_preview()
				else:
					_preview_ok = false
				if table_root.visible != (arcore.tracking == 2 and _preview_ok):
					table_root.visible = arcore.tracking == 2 and _preview_ok
					_update_ar_decor()
			elif _anchor_hold > 0.0:
				_anchor_hold -= delta
			elif arcore.anchor_tracking == 2 and not adjusting:
				_ar_pos = arcore.anchor_pose.origin
				var ax := arcore.anchor_pose.basis.x
				_ar_yaw = atan2(-ax.z, ax.x)
				_layout_table()
		Mode.STUDIO:
			if OS.has_feature("mobile"):
				tracker.update(delta)
	if mode == Mode.STUDIO or aim_cam_override:
		_update_orbit(delta)


## On screens narrower than 16:9 (tablets, foldables) widen the vertical FOV so the horizontal view
## matches 16:9 and the table isn't cropped at the sides.
func _fit_studio_fov() -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_v := deg_to_rad(STUDIO_FOV * 0.5)
	if aspect < WIDE_ASPECT:
		half_v = minf(atan(tan(half_v) * WIDE_ASPECT / maxf(aspect, 0.3)), deg_to_rad(55.0))
	studio_cam.fov = rad_to_deg(half_v * 2.0)


func _update_orbit(delta: float) -> void:
	_fit_studio_fov()
	var s := table_scale()
	var root_xf := table_root.global_transform
	var size := table_view.outer_size()
	if not _manual:
		match view:
			View.OVERVIEW:
				_want_target = root_xf * Vector3(0, 0, 0)
				_want_pitch = deg_to_rad(42.0)
				_want_dist = (maxf(size.x * 0.62, size.y * 1.0) + 0.75) * s * _zoom()
				if _idle_spin:
					_want_yaw += delta * 0.12
				else:
					_want_yaw = _closest_angle(_want_yaw, _ar_yaw if mode != Mode.STUDIO else 0.0)
			View.AIM:
				_want_target = root_xf * Vector3(_focus.x, 0.0, _focus.y)
				var dir_w := table_root.global_basis * Vector3(cos(_aim_yaw), 0.0, sin(_aim_yaw))
				_want_yaw = _closest_angle(_want_yaw, atan2(-dir_w.x, -dir_w.z))
				_want_pitch = deg_to_rad(17.0)
				_want_dist = 0.95 * s * _zoom()
			View.TOP:
				_top_frame()
	var k := 1.0 - exp(-delta * 6.0)
	_yaw = lerp_angle(_yaw, _want_yaw, k)
	_pitch = lerpf(_pitch, _want_pitch, k)
	_dist = lerpf(_dist, _want_dist, k)
	_target = _target.lerp(_want_target, k)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	studio_cam.position = _target + off
	var up := Vector3.UP
	if _pitch > deg_to_rad(80.0):
		up = Vector3(-sin(_yaw), 0, -cos(_yaw))
	studio_cam.look_at(_target, up)


func _snap_orbit() -> void:
	_update_orbit(10.0)


static func _closest_angle(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)


# ================================================================== coordinate helpers
## Screen point -> table-local Vector2 on the plane at ball-centre height. Returns null if no hit.
func screen_to_table(sp: Vector2) -> Variant:
	var cam := active_camera()
	if cam == null:
		return null
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var inv := table_root.global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * d)
	if absf(ld.y) < 1e-6:
		return null
	var y_plane := table_view.geom.ball_r
	var t := (y_plane - lo.y) / ld.y
	if t <= 0.0:
		return null
	var hit := lo + ld * t
	return Vector2(hit.x, hit.z)


func table_to_screen(p: Vector2, y := 0.0) -> Vector2:
	var cam := active_camera()
	return cam.unproject_position(table_root.global_transform * Vector3(p.x, y, p.y))


## Camera forward projected onto the table plane, as a table-local yaw angle.
func camera_yaw_on_table() -> float:
	var cam := active_camera()
	var f := -cam.global_basis.z
	var lf := table_root.global_basis.inverse() * f
	return atan2(lf.z, lf.x)


## Screen-space vector -> table-plane direction (fallback when rays miss the table plane).
func screen_dir_to_table(v: Vector2) -> Vector2:
	var cam := active_camera()
	var right := cam.global_basis.x
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 1e-3:
		fwd = cam.global_basis.y
		fwd.y = 0.0
	fwd = fwd.normalized()
	var w := right * v.x - fwd * v.y
	var l := table_root.global_basis.inverse() * w
	return Vector2(l.x, l.z).normalized()


# ================================================================== AR placement
## Placement preview: the table stands on the floor (or desk) where the centre of the screen points, its
## long side across your view, until you tap Place.
func _update_preview() -> void:
	if floating():
		_preview_ok = true
		_update_float_preview()
		return
	var r := ar_cam.global_basis.x
	r.y = 0.0
	if r.length() > 0.05:
		_ar_yaw = atan2(-r.z, r.x) + preview_turn
	var centre := get_viewport().get_visible_rect().size * 0.5
	var p: Variant = null
	if arcore.hit_valid:
		p = arcore.hit_pos
	elif _no_plane_time > 5.0:
		# no surface found yet (plain floors can be slow): use the lowest one seen, or a guess
		var gy := arcore.floor_y if arcore.plane_count > 0 else ar_cam.global_position.y - _eye_height()
		p = _plane_hit(centre, gy)
	_preview_ok = p != null
	if p != null:
		_ar_pos = p + _push_offset()
		_layout_table()


## Developer tools → AR placement (v1.1.15): the table goes down this many metres further away from (+) or nearer to
## (-) the spot the phone points at, along the floor.
func _push_offset() -> Vector3:
	var push := clampf(float(Game.get_s("ar_push")), -2.0, 3.0)
	if absf(push) < 0.001:
		return Vector3.ZERO
	var f := -ar_cam.global_basis.z
	f.y = 0.0
	if f.length() < 0.2:
		f = ar_cam.global_basis.y     # looking straight down: the phone's top edge
		f.y = 0.0
	return f.normalized() * push if f.length() > 1e-3 else Vector3.ZERO


## Floating preview (Debug → AR → Floating table): hovers in front of you, a bit below eye level.
func _update_float_preview() -> void:
	var f := -ar_cam.global_basis.z
	f.y = 0.0
	if f.length() < 0.2:
		f = ar_cam.global_basis.y   # looking straight down: use the phone's top edge
		f.y = 0.0
	if f.length() < 1e-3:
		return
	f = f.normalized()
	var mini: bool = Game.get_s("surface") != "floor"
	var d := maxf(0.2, float(Game.get_s("float_dist_desk" if mini else "float_dist_floor")) + clampf(float(Game.get_s("ar_push")), -2.0, 3.0))
	var drop := float(Game.get_s("float_drop_desk" if mini else "float_drop_floor"))
	var cp := ar_cam.global_position
	_ar_pos = Vector3(cp.x + f.x * d, cp.y - drop, cp.z + f.z * d)
	# long side across the screen (like standing at the side of a real table) — fits landscape phones
	var r := ar_cam.global_basis.x
	r.y = 0.0
	if r.length() > 0.05:
		_ar_yaw = atan2(-r.z, r.x) + preview_turn
	_layout_table()


## The table is shown where it will go and waits for Place: it can be turned and sized now.
func previewing() -> bool:
	return mode == Mode.WORLD_AR and not placed and ar_state == ArState.RUNNING


## Turn the table being placed by `d` radians (+ = anticlockwise seen from above).
func turn_preview(d: float) -> void:
	preview_turn = wrapf(preview_turn + d, -PI, PI)
	if mode == Mode.WORLD_AR and not placed:
		_ar_yaw = wrapf(_ar_yaw + d, -PI, PI)
		_layout_table()


## Size the table being placed (the same World size as Settings → World; Mini and Life-size follow it).
func resize_preview(v: float) -> void:
	Game.set_world_size(v)


## Can the player tap Place right now?
func can_place() -> bool:
	match mode:
		Mode.WORLD_AR:
			return ar_state == ArState.RUNNING and arcore.tracking == 2 and _preview_ok
	return true


## Walk-around AR: has a real surface been found under the screen centre?
func surface_found() -> bool:
	return mode == Mode.WORLD_AR and arcore.hit_valid


## Ray from the screen to the horizontal plane at height y (world). null when it misses.
func _plane_hit(sp: Vector2, y: float) -> Variant:
	var cam := active_camera()
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 1e-4:
		return null
	var t := (y - o.y) / d.y
	if t <= 0.0 or t > 12.0:
		return null
	return o + d * t


func place_table() -> void:
	ar_lift = 0.0
	placed = true
	_reanchor()
	table_root.visible = true
	_reticle.visible = false
	_layout_table()
	_update_ar_decor()
	placement_changed.emit(true)
	Game.vibrate(30)
	_update_ar_scene()


func unplace_table() -> void:
	if mode == Mode.STUDIO:
		return
	if mode == Mode.WORLD_AR:
		arcore.clear_anchor()
	placed = false
	placement_changed.emit(false)
	_update_ar_scene()   # back to the camera picture while the table is put down again


func recenter_ar() -> void:
	if placed:
		unplace_table()


func set_adjusting(on: bool) -> void:
	var was := adjusting
	adjusting = on and mode != Mode.STUDIO
	if was and not adjusting:
		_reanchor()


## Raise (+) or lower (-) the placed table by `dy` metres, e.g. to stand it on a real table or to
## correct a floor that was detected a little too high or low. Returns the total lift since placing.
func lift_table(dy: float) -> float:
	if mode == Mode.STUDIO or not placed:
		return ar_lift
	var new_lift := clampf(ar_lift + dy, -1.5, 2.5)
	_ar_pos.y += new_lift - ar_lift
	ar_lift = new_lift
	_layout_table()
	_reanchor()
	return ar_lift


## Pin the table where it is now. ARCore answers a moment later, so don't follow the (old) anchor meanwhile.
func _reanchor() -> void:
	if mode == Mode.WORLD_AR and placed:
		arcore.place_anchor(Transform3D(Basis(Vector3.UP, _ar_yaw), _ar_pos))
		_anchor_hold = 0.4


## Gestures: in AR adjust mode -> move / scale / rotate the table; in Studio -> orbit / zoom; in free look (top
## view) one finger slides the camera, two pinch to zoom (together = in, apart = out, as Randy asked) and twist to turn.
func handle_gesture(ev: InputEvent) -> bool:
	if free_look and not adjusting:
		return _free_look_gesture(ev)
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
			if adjusting and _touches.is_empty():
				_reanchor()
		_gesture_start = {"touches": _touches.duplicate(), "scale": _ar_scale, "yaw": _ar_yaw, "pos": _ar_pos,
			"dist": _dist, "oyaw": _yaw, "opitch": _pitch, "turn": preview_turn, "wsize": Game.world_size()}
		return _touches.size() >= 2 or (adjusting and _touches.size() == 1)
	if ev is InputEventScreenDrag:
		if not _touches.has(ev.index):
			return false
		var prev: Vector2 = _touches[ev.index]
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var keys := _touches.keys()
			var a0: Vector2 = _gesture_start["touches"].get(keys[0], _touches[keys[0]])
			var b0: Vector2 = _gesture_start["touches"].get(keys[1], _touches[keys[1]])
			var a1: Vector2 = _touches[keys[0]]
			var b1: Vector2 = _touches[keys[1]]
			var s0 := maxf(a0.distance_to(b0), 1.0)
			var ratio := a1.distance_to(b1) / s0
			var rot := (b1 - a1).angle() - (b0 - a0).angle()
			if previewing() and not adjusting:
				# placing: pinch sizes the table (World size), twist turns it
				var ws := clampf(float(_gesture_start["wsize"]) * ratio, Game.WORLD_MIN, Game.WORLD_MAX)
				if absf(ws - Game.world_size()) > 0.004:
					resize_preview(ws)
				turn_preview(wrapf(float(_gesture_start["turn"]) - rot - preview_turn, -PI, PI))
			elif adjusting:
				_ar_scale = clampf(float(_gesture_start["scale"]) * ratio, 0.08, 1.3)
				_ar_yaw = float(_gesture_start["yaw"]) - rot
				if floating():
					# both fingers sliding up / down raises / lowers the floating table
					var lift := ((a1 + b1) - (a0 + b0)).y * 0.5
					var p0: Vector3 = _gesture_start["pos"]
					var dist := maxf(ar_cam.global_position.distance_to(p0), 0.3)
					_ar_pos = Vector3(_ar_pos.x, p0.y - lift * 0.0012 * dist, _ar_pos.z)
				_layout_table()
			elif mode == Mode.STUDIO or aim_cam_override:
				_manual = true
				_want_dist = clampf(float(_gesture_start["dist"]) / ratio, 0.35, 9.0)
				var mid_d := ((a1 + b1) - (a0 + b0)) * 0.5
				_want_yaw = float(_gesture_start["oyaw"]) - mid_d.x * 0.006
				_want_pitch = clampf(float(_gesture_start["opitch"]) + mid_d.y * 0.004, deg_to_rad(8), deg_to_rad(89))
			return true
		if adjusting and _touches.size() == 1:
			var h0 = _plane_hit(prev, _ar_pos.y)
			var h1 = _plane_hit(ev.position, _ar_pos.y)
			if h0 != null and h1 != null:
				_ar_pos += Vector3((h1 - h0).x, 0.0, (h1 - h0).z)
				_layout_table()
			return true
	if ev is InputEventMouseButton and ev.pressed and (mode == Mode.STUDIO or aim_cam_override):
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_manual = true
			_want_dist = maxf(0.35, _want_dist * 0.9)
			return true
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_manual = true
			_want_dist = minf(9.0, _want_dist * 1.1)
			return true
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_RIGHT) and (mode == Mode.STUDIO or aim_cam_override):
		_manual = true
		_want_yaw -= ev.relative.x * 0.006
		_want_pitch = clampf(_want_pitch + ev.relative.y * 0.004, deg_to_rad(8), deg_to_rad(89))
		return true
	return false


func _free_look_gesture(ev: InputEvent) -> bool:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		_gesture_start = {"touches": _touches.duplicate(), "dist": _want_dist, "oyaw": _want_yaw}
		return true
	if ev is InputEventScreenDrag:
		if not _touches.has(ev.index):
			return false
		var prev: Vector2 = _touches[ev.index]
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			free_look_pan(prev, ev.position)
			return true
		var keys := _touches.keys()
		var a0: Vector2 = _gesture_start["touches"].get(keys[0], _touches[keys[0]])
		var b0: Vector2 = _gesture_start["touches"].get(keys[1], _touches[keys[1]])
		var a1: Vector2 = _touches[keys[0]]
		var b1: Vector2 = _touches[keys[1]]
		var ratio := a1.distance_to(b1) / maxf(a0.distance_to(b0), 1.0)
		var s := table_scale()
		# fingers together (ratio < 1) zoom in, apart zoom out
		_want_dist = clampf(float(_gesture_start["dist"]) * ratio, FL_MIN_DIST * s, FL_MAX_DIST * s)
		_want_yaw = float(_gesture_start["oyaw"]) - ((b1 - a1).angle() - (b0 - a0).angle())
		_keep_clear()
		return true
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			free_look_step(0.0, 0.0, 0.9)
			return true
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			free_look_step(0.0, 0.0, 1.0 / 0.9)
			return true
	return false


func reset_manual() -> void:
	_manual = false


func tracking_status() -> String:
	if mode == Mode.WORLD_AR:
		if ar_state == ArState.BLOCKED:
			return "AR not running (%s) · %s" % [ar_block, _ar_detail]
		if ar_state != ArState.RUNNING:
			return "AR starting… · " + arcore.info()
		return "Walk-around AR · %s%s" % [["not tracking", "searching", "tracking"][clampi(arcore.tracking, 0, 2)], (" · " + arcore.failure_text()) if arcore.failure > 0 else ""]
	return "Studio view"
