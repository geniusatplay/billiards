class_name ControlThumbstick
extends ControlPrecision
## THUMBSTICK — game-controller style rate aiming: push the stick left / right and the cue keeps
## turning while you hold it. A tiny push creeps at 0.02°/s, a full push swings 40°/s.

var _stick: Widgets.Thumbstick
var _holding := false


func scheme_id() -> String:
	return "thumbstick"


func title() -> String:
	return L.t("Thumbstick")


func help_lines() -> Array:
	return ["Push the stick left or right — the cue keeps turning while you hold it.",
		"A tiny push creeps (0.02°/s); all the way swings fast (40°/s).",
		"Tap the table to point straight at a spot; arrows nudge 0.05°.",
		"Pull the power piston down, then release to strike."]


func _build_fine() -> void:
	_stick = Widgets.Thumbstick.new()
	_add(_stick)
	_stick.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_cw = _cw_sign())


func _layout_fine(vp: Vector2) -> Rect2:
	var s := _stick.custom_minimum_size
	_stick.position = Vector2(vp.x * 0.5 - s.x * 0.5, vp.y - s.y - 70)
	return Rect2(_stick.position, s)


func tick(delta: float) -> void:
	if enabled and is_instance_valid(_stick) and absf(_stick.deflection) > 0.005:
		turn_cw(deg_to_rad(Widgets.Thumbstick.rate_deg(_stick.deflection)) * delta * float(Game.get_s("fine_aim_scale")))
