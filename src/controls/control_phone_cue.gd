class_name ControlPhoneCue
extends CueControl
## B. PHONE CUE — the phone is the cue.
## Aim follows where the phone points (AR) or how you turn it (Studio, gyro). One-finger swipe fine-tunes.
## Hold STROKE: aim locks; pull the phone back and push it forward — thrust speed sets power.
## No thrust? Releasing STROKE fires with the charged meter (accessible fallback).

var _btn: Widgets.StrokeButton
var _chip: Button
var _fine := 0.0
var _holding := false
var _charge := 0.0
var _vel := 0.0
var _peak := 0.0
var _swipe := -1
var _swipe_x := 0.0
var _base_heading := 0.0
var _base_yaw := 0.0
var _have_base := false
var follow_phone := true


func scheme_id() -> String:
	return "phone_cue"


func title() -> String:
	return L.t("Phone Cue")


func help_lines() -> Array:
	return ["Your phone is the cue: turn it to aim.",
		"Swipe left/right with one finger for fine adjustments.",
		"Hold STROKE, pull the phone back, then push it forward smoothly — faster push = harder shot.",
		"Prefer buttons? Just hold STROKE to charge and let go."]


func _build_widgets() -> void:
	follow_phone = bool(Game.get_s("phone_cue_follow_phone"))
	_btn = Widgets.StrokeButton.new()
	_add(_btn)
	_btn.pressed_down.connect(_on_down)
	_btn.released.connect(_on_up)
	_chip = UIKit.button(L.t("Aim: Phone") if follow_phone else L.t("Aim: Swipe"), "ChipButton")
	_chip.toggle_mode = true
	_chip.button_pressed = follow_phone
	_chip.toggled.connect(func(on: bool):
		follow_phone = on
		_have_base = false
		_chip.text = L.t("Aim: Phone") if on else L.t("Aim: Swipe")
		Game.set_s("phone_cue_follow_phone", on))
	_add(_chip)
	_layout()
	layer.resized.connect(_layout)


func _layout() -> void:
	if not is_instance_valid(_btn):
		return
	var vp := layer.size
	var right := _side(true)
	_btn.position = Vector2(vp.x - 400 if right else 170, vp.y - 280)
	_chip.position = Vector2(vp.x - 400 if right else 170, vp.y - 360)


func reset_for_turn(p_yaw: float) -> void:
	super.reset_for_turn(p_yaw)
	_fine = 0.0
	_have_base = false
	_charge = 0.0
	_holding = false
	if _btn:
		_btn.charge = 0.0
		_btn.queue_redraw()


func _heading() -> float:
	var st: Stage = game.stage
	if st.is_ar() and not st.aim_cam_override:
		return st.camera_yaw_on_table()
	var f := st.tracker.basis() * Vector3.FORWARD
	return atan2(f.z, f.x)


func _sensors_ok() -> bool:
	var st: Stage = game.stage
	return st.is_ar() or (st.tracker.initialized and st.tracker.has_gyro)


func tick(delta: float) -> void:
	if not enabled:
		return
	if follow_phone and not _holding and _sensors_ok():
		var h := _heading()
		var st: Stage = game.stage
		if st.is_ar() and not st.aim_cam_override:
			yaw = h + _fine
		else:
			if not _have_base:
				_base_heading = h
				_base_yaw = yaw - _fine
				_have_base = true
			yaw = _base_yaw + wrapf(h - _base_heading, -PI, PI) + _fine
		aim_updated.emit()
	if _holding:
		_charge = minf(1.0, _charge + delta / 1.5)
		power = ease(_charge, 1.6)
		_btn.charge = _charge
		_btn.queue_redraw()
		_track_thrust(delta)
		aim_updated.emit()


func _track_thrust(delta: float) -> void:
	var raw_a := Input.get_accelerometer()
	var raw_g := Input.get_gravity()
	if raw_a.length() < 0.5 or raw_g.length() < 0.5:
		return
	var st: Stage = game.stage
	# physical linear acceleration in the screen frame is -(mapped raw linear); forward = -Z
	var lin := SensorTracker.gravity_hyp(st.tracker.gravity_map, raw_a - raw_g)
	var thrust := lin.z
	_vel = _vel * (1.0 - clampf(2.5 * delta, 0.0, 1.0)) + thrust * delta
	if _vel > _peak:
		_peak = _vel
	if _peak > 0.35 and _vel < _peak * 0.7:
		power = clampf((_peak - 0.2) / 1.3, 0.06, 1.0)
		_fire()


func _on_down() -> void:
	_holding = true
	_charge = 0.0
	_vel = 0.0
	_peak = 0.0
	Game.vibrate(15)


func _on_up() -> void:
	if not _holding:
		return
	if power >= 0.04:
		_fire()
	else:
		_holding = false


func _fire() -> void:
	_holding = false
	_btn.holding = false
	_btn.charge = 0.0
	_btn.queue_redraw()
	shot_requested.emit()


func handle_input(ev: InputEvent) -> bool:
	if not enabled:
		return false
	if ev is InputEventScreenTouch:
		if ev.pressed and _swipe < 0:
			_swipe = ev.index
			_swipe_x = ev.position.x
			return true
		if not ev.pressed and ev.index == _swipe:
			_swipe = -1
			return true
	elif ev is InputEventScreenDrag and ev.index == _swipe:
		var dx: float = ev.position.x - _swipe_x
		_swipe_x = ev.position.x
		var k := 0.0009 if follow_phone and _sensors_ok() else 0.004
		_fine -= dx * k * float(Game.get_s("fine_aim_scale"))
		if not (follow_phone and _sensors_ok()):
			yaw -= dx * k * float(Game.get_s("fine_aim_scale"))
		aim_updated.emit()
		return true
	return false
