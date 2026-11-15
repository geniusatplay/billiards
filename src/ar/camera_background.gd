class_name CameraBackground
extends CanvasLayer
## Draws the phone camera behind the 3D world (the 3D environment uses BG_CANVAS). The frames come
## from ARCore (see ARCoreBridge): the AR plugin owns the camera and hands us each image.

var active := false
var external := false
var _rect: ColorRect
var _mat: ShaderMaterial
var _ext_y: ImageTexture
var _ext_uv: ImageTexture
var _ext_size := Vector2i.ZERO
var _shown := true          # false while something else (an AR scene, the aim camera) stands in for the camera picture


func _ready() -> void:
	layer = -100
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/game/shaders/camera_feed.gdshader")
	_rect.material = _mat
	_rect.color = Color.BLACK
	_rect.visible = false
	add_child(_rect)


func start_external() -> void:
	external = true
	active = false
	_shown = true
	_mat.set_shader_parameter("affine", true)
	_mat.set_shader_parameter("ycbcr", true)
	_rect.visible = false


## One camera frame: Y plane (size.x * size.y bytes), interleaved CbCr at half resolution, and the
## view -> image UV mapping (rotation + crop) ARCore computed for the current screen.
func push_external(size: Vector2i, y: PackedByteArray, uv: PackedByteArray, o: Vector2, ux: Vector2, uy: Vector2) -> void:
	if not external or size.x < 2 or y.size() < size.x * size.y or uv.size() < (size.x / 2) * (size.y / 2) * 2:
		return
	var yi := Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, y)
	var ci := Image.create_from_data(size.x / 2, size.y / 2, false, Image.FORMAT_RG8, uv)
	if _ext_y == null or _ext_size != size:
		_ext_y = ImageTexture.create_from_image(yi)
		_ext_uv = ImageTexture.create_from_image(ci)
		_ext_size = size
		_mat.set_shader_parameter("tex_a", _ext_y)
		_mat.set_shader_parameter("tex_b", _ext_uv)
	else:
		_ext_y.update(yi)
		_ext_uv.update(ci)
	_mat.set_shader_parameter("uv_o", o)
	_mat.set_shader_parameter("uv_x", ux)
	_mat.set_shader_parameter("uv_y", uy)
	_rect.visible = _shown   # (a scene or the aim camera may be covering the room for now)
	active = true


## Loading screen: draw the (empty) camera picture once, so its shader is ready before AR starts.
func warm(on: bool) -> void:
	if on:
		_mat.set_shader_parameter("affine", true)
		_mat.set_shader_parameter("ycbcr", true)
	_rect.visible = on or (active and _shown)


func stop() -> void:
	external = false
	active = false
	_rect.visible = false


func set_visible_feed(v: bool) -> void:
	_shown = v
	_rect.visible = v and active
