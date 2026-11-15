class_name CueControl
extends Node
## Base class for the three cue control schemes. Owns the shot state; the match controller reads it.

signal shot_requested
signal aim_updated

var game: Node              # PoolGame (duck-typed to avoid a circular class dependency)
var layer: Control          # HUD layer where the scheme adds its own widgets
var yaw := 0.0
var power := 0.0
var offset := Vector2.ZERO
var elevation := 0.0
var enabled := false
var _widgets: Array[Control] = []

const SCHEME_ID := "base"


func scheme_id() -> String:
	return "base"


func title() -> String:
	return L.t("Cue")


func help_lines() -> Array:
	return []


func activate(p_game: Node, p_layer: Control) -> void:
	game = p_game
	layer = p_layer
	_build_widgets()


func deactivate() -> void:
	for w in _widgets:
		if is_instance_valid(w):
			w.queue_free()
	_widgets.clear()


func _add(w: Control) -> Control:
	layer.add_child(w)
	_widgets.append(w)
	return w


func _build_widgets() -> void:
	pass


func set_enabled(on: bool) -> void:
	enabled = on
	for w in _widgets:
		if is_instance_valid(w):
			w.visible = on
	if not on:
		power = 0.0


## Called by the match controller at the start of each turn.
func reset_for_turn(p_yaw: float) -> void:
	yaw = p_yaw
	power = 0.0


## Return true when the event was consumed.
func handle_input(_ev: InputEvent) -> bool:
	return false


func tick(_delta: float) -> void:
	pass


func _vp() -> Vector2:
	return layer.get_viewport().get_visible_rect().size if layer else Vector2(1920, 1080)


## Mirror a bottom-corner anchor for left-handed players.
func _side(right: bool) -> bool:
	return right != bool(Game.get_s("left_handed"))
