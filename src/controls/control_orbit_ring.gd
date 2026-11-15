class_name ControlOrbitRing
extends ControlPrecision
## ORBIT RING — a ring around the cue ball. Drag along it to swing the cue around the ball;
## slide your finger further out from the ring for a longer lever = finer control (down to 1/10).

const RING_R := 150.0
const BAND := 60.0

var _overlay: RingOverlay
var _ring_touch := -1
var _last_a := 0.0


func scheme_id() -> String:
	return "orbit_ring"


func title() -> String:
	return L.t("Orbit Ring")


func help_lines() -> Array:
	return ["Drag along the ring around the cue ball to swing the cue.",
		"Move your finger further out from the ball for a longer lever: finer aim.",
		"Tap the table to point straight at a spot; arrows nudge 0.05°.",
		"Pull the power piston down, then release to strike."]


func _build_fine() -> void:
	_overlay = RingOverlay.new()
	_overlay.ctl = self
	_add(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout_fine(vp: Vector2) -> Rect2:
	return Rect2(vp.x * 0.5 - 60, vp.y - 150, 120, 84)


func tick(_delta: float) -> void:
	if is_instance_valid(_overlay) and _overlay.visible:
		_overlay.queue_redraw()


func cue_screen() -> Vector2:
	return game.stage.table_to_screen(game.cue_ball_pos())


func _fine_input(ev: InputEvent) -> bool:
	if ev is InputEventScreenTouch:
		if ev.pressed and _ring_touch < 0 and _touch < 0:
			var r: float = (ev.position - cue_screen()).length()
			if absf(r - RING_R) < BAND:
				_ring_touch = ev.index
				_last_a = (ev.position - cue_screen()).angle()
				_cw = _cw_sign()
				_overlay.finger = ev.position
				return true
		elif not ev.pressed and ev.index == _ring_touch:
			_ring_touch = -1
			_overlay.finger = Vector2.INF
			return true
	elif ev is InputEventScreenDrag and ev.index == _ring_touch:
		var v: Vector2 = ev.position - cue_screen()
		var r := v.length()
		if r > 24.0:
			var a := v.angle()
			var da := wrapf(a - _last_a, -PI, PI)
			_last_a = a
			var lever := clampf(RING_R / maxf(r, RING_R), 0.1, 1.0)
			turn_cw(da * lever)
			_overlay.lever = lever
		_overlay.finger = ev.position
		return true
	return false


class RingOverlay extends Control:
	var ctl: ControlOrbitRing
	var finger := Vector2.INF
	var lever := 1.0

	func _draw() -> void:
		if ctl == null or ctl.game == null or ctl.game.state != PoolGame.State.AIM:
			return
		var c: Vector2 = ctl.cue_screen()
		var R := ControlOrbitRing.RING_R
		draw_arc(c, R, 0, TAU, 96, Color(1, 1, 1, 0.22), 10.0, true)
		draw_arc(c, R, 0, TAU, 96, Color(1, 1, 1, 0.5), 2.0, true)
		for k in 72:
			var a := TAU * k / 72.0
			var l := 12.0 if k % 6 == 0 else 6.0
			draw_line(c + Vector2.from_angle(a) * (R - l), c + Vector2.from_angle(a) * (R + l), Color(1, 1, 1, 0.35), 2.0, true)
		# knob where the cue points on screen
		var tip: Vector2 = ctl.game.stage.table_to_screen(ctl.game.cue_ball_pos() + Vector2.from_angle(ctl.yaw) * 0.3)
		var dir := (tip - c).normalized()
		if dir != Vector2.ZERO:
			draw_circle(c + dir * R, 18.0, Color.WHITE)
			draw_circle(c + dir * R, 11.0, UIKit.EMERALD)
		if finger != Vector2.INF:
			draw_dashed_line(c, finger, Color(1, 1, 1, 0.4), 3.0, 14.0, true)
			draw_circle(finger, 26.0, Color(1, 1, 1, 0.15))
			var f := UIKit.font(800)
			draw_string(f, finger + Vector2(-70, -40), "×1/%d" % int(round(1.0 / lever)) if lever < 0.95 else "×1", HORIZONTAL_ALIGNMENT_CENTER, 140, 24, UIKit.GOLD if lever < 0.95 else UIKit.TEXT)
