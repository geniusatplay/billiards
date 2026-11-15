class_name ControlProDial
extends CueControl
## C. PRO DIAL — precision controls.
## The ribbed wheel turns the cue (slow drags for fine aim, quick swipes for big turns), nudge buttons for
## 0.05 degrees, and a pull-down piston for power (release to strike). Randy, 11 Nov 2026: no tap-to-aim on the
## table in this scheme for now (a stray touch on the table never swings the aim).

var _wheel: Widgets.AimWheel
var _piston: Widgets.PowerPiston
var _nudge_l: Button
var _nudge_r: Button


func scheme_id() -> String:
	return "pro_dial"


func title() -> String:
	return L.t("Pro Dial")


func help_lines() -> Array:
	return ["Drag the ribbed wheel to turn the cue: slowly for fine aim, a quick swipe for a big turn.",
		"Tap the arrows to nudge the aim 0.05°.",
		"Pull the power piston down, then release to strike.",
		"Tip: the Aim Cam button gives you a low view behind the cue."]


func _build_widgets() -> void:
	_wheel = Widgets.AimWheel.new()
	_add(_wheel)
	_wheel.rotated.connect(func(d: float):
		yaw -= d
		aim_updated.emit())
	_piston = Widgets.PowerPiston.new()
	_add(_piston)
	_piston.changed.connect(func(p: float):
		power = p
		aim_updated.emit())
	_piston.released.connect(func(p: float):
		power = p
		shot_requested.emit())
	_nudge_l = UIKit.icon_button("chev_left", 84, "Nudge aim")
	_nudge_r = UIKit.icon_button("chev_right", 84, "Nudge aim")
	_add(_nudge_l)
	_add(_nudge_r)
	_nudge_l.pressed.connect(func(): _nudge(1.0))
	_nudge_r.pressed.connect(func(): _nudge(-1.0))
	_layout()
	layer.resized.connect(_layout)


func _nudge(s: float) -> void:
	yaw += deg_to_rad(0.05) * s
	aim_updated.emit()


func _layout() -> void:
	if not is_instance_valid(_wheel):
		return
	var vp := layer.size
	var right := _side(true)
	_wheel.position = Vector2(vp.x * 0.5 - _wheel.custom_minimum_size.x * 0.5, vp.y - 178)
	_nudge_l.position = _wheel.position + Vector2(-100, 4)
	_nudge_r.position = _wheel.position + Vector2(_wheel.custom_minimum_size.x + 16, 4)
	# keep clear of the tool column on the outer edge
	_piston.position = Vector2(vp.x - 300 if right else 170, vp.y * 0.5 - 190)
