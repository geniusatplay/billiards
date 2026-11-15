class_name ControlCrank
extends ControlPrecision
## CRANK — turn a crank in circles like a precision instrument. One full turn = 18° in FINE gear
## or 90° in FAST gear (tap the gear button). Unlimited range, no lifting your finger.

const RATIOS := [20.0, 4.0]

var _knob: Widgets.CrankKnob
var _gear: Button
var _gear_i := 0


func scheme_id() -> String:
	return "crank"


func title() -> String:
	return L.t("Crank")


func help_lines() -> Array:
	return ["Turn the crank in circles to rotate the cue — clockwise turns it clockwise.",
		"FINE gear: one turn = 18°. FAST gear: one turn = 90°. Tap the gear button to switch.",
		"Tap the table to point straight at a spot; arrows nudge 0.05°.",
		"Pull the power piston down, then release to strike."]


func _build_fine() -> void:
	_knob = Widgets.CrankKnob.new()
	_add(_knob)
	_knob.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_cw = _cw_sign())
	_knob.turned.connect(func(da: float): turn_cw(da / RATIOS[_gear_i]))
	_gear = UIKit.button(L.t("FINE"), "GhostButton", "gear")
	_add(_gear)
	_gear.pressed.connect(func():
		_gear_i = 1 - _gear_i
		_gear.text = L.t("FINE") if _gear_i == 0 else L.t("FAST")
		_knob.ratio_label = "1:20" if _gear_i == 0 else "1:4"
		_knob.queue_redraw()
		Sfx.ui("toggle"))


func _layout_fine(vp: Vector2) -> Rect2:
	var s := _knob.custom_minimum_size
	_knob.position = Vector2(vp.x * 0.5 - s.x * 0.5, vp.y - s.y - 70)
	_gear.position = Vector2(vp.x * 0.5 + s.x * 0.5 + 120, vp.y - s.y * 0.5 - 110)
	return Rect2(_knob.position, s)
