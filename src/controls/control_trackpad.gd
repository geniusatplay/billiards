class_name ControlTrackpad
extends ControlPrecision
## TRACKPAD — like a laptop touchpad: slide sideways to turn the cue. Slow slides are ultra fine
## (0.004°/px), quick swipes cover big angles. Double-tap the pad for a 4× precision lock.

var _pad: Widgets.TrackPad


func scheme_id() -> String:
	return "trackpad"


func title() -> String:
	return L.t("Trackpad")


func help_lines() -> Array:
	return ["Slide sideways on the pad to turn the cue — slow = ultra fine, fast = big turns.",
		"Double-tap the pad to lock 4× precision.",
		"Tap the table to point straight at a spot; arrows nudge 0.05°.",
		"Pull the power piston down, then release to strike."]


func _build_fine() -> void:
	_pad = Widgets.TrackPad.new()
	_add(_pad)
	_pad.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_cw = _cw_sign())
	_pad.turned.connect(func(rad: float): turn_cw(rad))


func _layout_fine(vp: Vector2) -> Rect2:
	_pad.position = Vector2(vp.x * 0.5 - _pad.custom_minimum_size.x * 0.5, vp.y - 216)
	return Rect2(_pad.position, _pad.custom_minimum_size)
