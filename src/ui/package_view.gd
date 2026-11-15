class_name PackageView
extends SubViewportContainer
## A reward package shown in 3D inside the UI: it sways while it waits and opens when asked.
## The five models (assets/models/packages/pk_1..5.glb) are the designs Randy chose. Since v1.1.8: Pine Crate
## (common), Flight Case (uncommon), Emerald Monolith (rare), Pink Neon Flight Case (epic), Ruby Vault (legendary);
## the XP chest is the orange XP Flight Case (since v1.1.7). (Up to v1.1.6: Pine Crate, Emerald Crate, Flight Case,
## Pink Neon Flight Case, Vortex Vault, and a walnut treasure chest.) They come unpainted; PAINT below gives every material its look with
## the same patterns the cues use (see Cues.material).

signal opened

## Shown as the Packages page's title, translated (assets/i18n/strings.csv has all five; v1.1.9).
const NAMES := ["", "Pine Crate", "Flight Case", "Emerald Monolith", "Pink Neon Flight Case", "Ruby Vault"]
const PAINT := {
	"pine": [20, "c9995a", "805226", 0.0, 0.6], "dark": [0, "050506", "", 0.0, 0.9], "ink": [0, "11141b", "", 0.0, 0.6],
	"iron": [0, "2a2c30", "", 1.0, 0.5], "rope": [0, "c0a070", "", 0.0, 1.0], "hole": [0, "050506", "", 0.0, 0.9],
	"emerald_paint": [0, "0c7f5a", "", 0.1, 0.3], "brass": [0, "c99a45", "", 0.45, 0.3],
	"navy": [0, "101a2e", "", 0.1, 0.5], "alu": [0, "b8bcc4", "", 0.45, 0.4], "steel": [0, "9aa0aa", "", 0.45, 0.3], "silver": [0, "dce0e8", "", 0.45, 0.18],
	"black": [0, "0c0d10", "", 0.2, 0.25], "g_blue": [16, "3fb6ff", "", 0.0, 0.3, 1.5],
	"g_pink": [16, "ff2f9a", "", 0.0, 0.3, 1.6], "gloss_black": [0, "07070b", "", 0.3, 0.1], "gunmetal": [0, "292b35", "", 1.0, 0.28], "chrome": [0, "e6e6f2", "", 0.5, 0.08],
	"gold_soft": [0, "c7731c", "", 1.0, 0.42], "gold": [0, "e3a93a", "", 0.45, 0.25, 0.06], "g_green": [16, "2be7a5", "", 0.0, 0.3, 1.5], "white": [0, "c9ced8", "", 0.0, 0.4],
	"gem_emerald": [9, "0fd98c", "9fffd8", 0.0, 0.05, 0.9, 0.3], "gem_diamond": [9, "dcebff", "ffffff", 0.0, 0.05, 0.9, 0.3], "gem_ruby": [9, "ff2d55", "ffb0c0", 0.0, 0.05, 0.9, 0.3],
	# the XP chest (assets/models/packages/xp_chest.glb, tools/make_xp_chest.py)
	"walnut": [20, "8a5428", "4f2c12", 0.0, 0.55], "coins": [0, "ffc24a", "", 1.0, 0.25, 1.1],
	# half-metallic so it reads as gold from every side (fully metallic gold mirrors the dark sky and looks black;
	# since v1.1.7 the packages' gold, brass, steel, aluminium, silver and chrome are half-metallic for the same reason)
	"chestgold": [0, "e3a93a", "", 0.45, 0.3, 0.08],
	# the Emerald Monolith (tools/blender/pk_designs2.py n1; rare since v1.1.8): a cut emerald block in a titanium frame
	"emerald_block": [21, "012a1a", "1fe892", 0.0, 0.14, 0.9], "titanium": [0, "c4c8d0", "", 0.45, 0.28],
	"g_em2": [16, "2be7a5", "", 0.0, 0.3, 2.2], "gem_emerald_hi": [9, "19ff9c", "b8ffe0", 0.0, 0.05, 1.2, 0.3], "g_em_txt": [0, "7dffd0", "", 0.0, 0.3, 1.6],
	# the Ruby Vault (n12): a cut ruby block, gold frame and door
	"ruby_vault": [21, "2a000a", "ff2a50", 0.0, 0.14, 0.9], "g_ruby3": [16, "ff2d55", "", 0.0, 0.3, 2.2],
	# the XP chest: the orange flight case with "XP" on it (x8)
	"carbon": [22, "141517", "2e3036", 0.3, 0.3], "safety_orange": [0, "ff6a10", "", 0.0, 0.3, 0.12], "chrome2": [0, "e6e6f2", "", 0.5, 0.1],
	"tyre": [0, "111216", "", 0.0, 0.8], "tag": [0, "f2f4f8", "", 0.0, 0.5], "ink2": [0, "1a1d24", "", 0.0, 0.5],
}
const XP_CHEST := "res://assets/models/packages/xp_chest.glb"
const XP_GOLD := Color("ffc850")     # (the XP chest's colour in the menu and its light, kept since it was gold)

var rarity := 1
var idle := true
var model_path := ""         # "" = the package of `rarity`
var glow := Color.WHITE      # the colour of the light that pours out
var burst_at := Vector3(0, 0.26, 0)
var _vp: SubViewport
static var _burst_shader: Shader
var _spin: Node3D
var _lid: Node3D
var _burst: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0
var _open := false


func _init(p_rarity := 1, px := 360.0) -> void:
	rarity = clampi(p_rarity, 1, 5)
	model_path = "res://assets/models/packages/pk_%d.glb" % rarity
	glow = GearScreens.rarity_color(rarity)
	if rarity == 5:
		burst_at = Vector3(0, 0.29, 0.1)
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The XP chest (the main menu's corner and its own page) instead of a package.
static func xp_chest(px := 360.0) -> PackageView:
	var v := PackageView.new(1, px)
	v.model_path = XP_CHEST
	v.glow = XP_GOLD
	v.burst_at = Vector3(0, 0.31, 0)
	return v


## Off: the picture is drawn once and then kept (a waiting chest in the menu costs nothing per frame).
func set_live(on: bool) -> void:
	idle = on
	if _vp == null:
		return
	if on:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_spin.rotation.y = 0.0
		_spin.position.y = 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0.78, 0.74, 1.36)
	_vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.27, 0.0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 28, 0)
	key.light_energy = 1.5
	_vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 0.6, 1.2)
	fill.light_energy = 0.9
	fill.light_color = Color(0.7, 0.85, 1.0)
	fill.omni_range = 4.0
	_vp.add_child(fill)
	_spin = Node3D.new()
	_vp.add_child(_spin)
	_build()
	if not idle:
		# still: let it draw a few frames (the model and its shaders arrive), then keep that picture
		for i in 3:
			await RenderingServer.frame_post_draw
		if not idle and not _open and is_inside_tree():
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build() -> void:
	var path := model_path
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var body := Node3D.new()
	_lid = Node3D.new()
	_spin.add_child(body)
	_spin.add_child(_lid)
	var lid_box := AABB()
	var first := true
	var lids: Array = []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := str(mi.name)
		var mat_name := nm.get_slice("__", 1)
		if PAINT.has(mat_name):
			mi.material_override = Cues.material(PAINT[mat_name])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.owner = null
		mi.get_parent().remove_child(mi)
		if nm.begins_with("lid"):
			lids.append(mi)
			var bb := mi.get_aabb()
			lid_box = bb if first else lid_box.merge(bb)
			first = false
		else:
			body.add_child(mi)
	model.free()
	# the hinge: along the back of the lid (the vault's door hangs on its right-hand edge)
	var pivot := Vector3(lid_box.position.x + lid_box.size.x * 0.5, lid_box.position.y, lid_box.position.z)
	if rarity == 5 and model_path.ends_with("pk_5.glb"):
		pivot = Vector3(lid_box.end.x, 0.0, lid_box.position.z)
	_lid.position = pivot
	for mi in lids:
		_lid.add_child(mi)
		mi.position = -pivot
	# the light that pours out when it opens
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.3, 0.0)
	_light.light_color = glow
	_light.light_energy = 0.0
	_light.omni_range = 3.0
	_spin.add_child(_light)
	_burst = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	_burst.mesh = sm
	# a soft ball of light: brightest in the middle, fading to nothing at its edge
	if _burst_shader == null:
		_burst_shader = Shader.new()   # one for every package view, so it is compiled once
		_burst_shader.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, shadows_disabled;\nuniform vec3 col : source_color = vec3(1.0);\nvoid fragment() {\n\tfloat f = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);\n\tALBEDO = col * f * 1.6;\n\tALPHA = f;\n}\n"
	var bm := ShaderMaterial.new()
	bm.shader = _burst_shader
	bm.set_shader_parameter("col", glow.lerp(Color.WHITE, 0.35))
	_burst.material_override = bm
	_burst.position = burst_at
	_burst.scale = Vector3.ONE * 0.01
	_burst.visible = false
	_spin.add_child(_burst)


func _process(delta: float) -> void:
	if _spin == null:
		return
	_t += delta
	if idle and not _open and not Game.get_s("reduced_motion"):
		_spin.rotation.y = sin(_t * 0.7) * 0.22
		_spin.position.y = sin(_t * 1.4) * 0.012


## Shakes, pops the lid and lets the light out. Emits `opened` when the light is at its brightest.
func open(fast := false) -> void:
	if _open or _lid == null:
		opened.emit()
		return
	_open = true
	set_live(true)
	var k := 0.45 if fast else 1.0
	var tw := create_tween()
	tw.tween_property(_spin, "rotation:y", 0.0, 0.12 * k)
	for i in 6:
		tw.tween_property(_spin, "rotation:z", (0.07 if i % 2 == 0 else -0.07) * (1.0 + i * 0.25), 0.07 * k)
	tw.tween_property(_spin, "rotation:z", 0.0, 0.05 * k)
	tw.tween_callback(func():
		Sfx.play("rack", 0.8)
		Game.vibrate(40)
		_burst.visible = true)
	tw.set_parallel(true)
	if rarity == 5 and model_path.ends_with("pk_5.glb"):
		tw.tween_property(_lid, "rotation:y", deg_to_rad(118.0), 0.55 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(_lid, "rotation:x", deg_to_rad(-112.0), 0.5 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_lid, "position:y", _lid.position.y + 0.03, 0.25 * k)
	tw.tween_property(_light, "light_energy", 5.0, 0.4 * k)
	tw.tween_property(_burst, "scale", Vector3.ONE * 1.7, 0.5 * k).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func(): opened.emit())
	tw.tween_property(_burst, "scale", Vector3.ONE * 0.9, 0.5 * k)
