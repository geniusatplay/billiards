class_name Widgets
extends RefCounted
## Touch widgets used by the HUD and the three control schemes.


## ------------------------------------------------------------ Spin pad (cue-ball face)
class SpinPad extends Control:
	signal changed(offset: Vector2)
	var offset := Vector2.ZERO        # in R units, |offset| <= 0.5
	var _drag := false
	var _last_tap := 0

	func _init() -> void:
		custom_minimum_size = Vector2(190, 190)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Spin: drag the dot. Double-tap to reset."

	func set_spin(o: Vector2) -> void:
		offset = o.limit_length(0.5)
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				var now := Time.get_ticks_msec()
				if now - _last_tap < 300:
					set_spin(Vector2.ZERO)
					changed.emit(offset)
					Sfx.ui("toggle")
				_last_tap = now
				_drag = true
				_set_from(ev.position)
			else:
				_drag = false
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_set_from(ev.position)
			accept_event()

	func _set_from(p: Vector2) -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		var v := (p - c) / r
		v.y = -v.y
		set_spin(v * 0.62)
		changed.emit(offset)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color("f3f1ea"))
		draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.5), 3.0, true)
		draw_arc(c, r * 0.5 / 0.62, 0, TAU, 48, Color(0.2, 0.25, 0.3, 0.35), 2.0, true)
		draw_line(c - Vector2(r * 0.85, 0), c + Vector2(r * 0.85, 0), Color(0.2, 0.25, 0.3, 0.18), 2.0)
		draw_line(c - Vector2(0, r * 0.85), c + Vector2(0, r * 0.85), Color(0.2, 0.25, 0.3, 0.18), 2.0)
		var dot := c + Vector2(offset.x, -offset.y) / 0.62 * r
		draw_circle(dot, r * 0.17, UIKit.CORAL)
		draw_arc(dot, r * 0.17, 0, TAU, 24, Color.WHITE, 2.0, true)
		var lbl := ""
		if offset.y > 0.12: lbl = L.t("FOLLOW")
		elif offset.y < -0.12: lbl = L.t("DRAW")
		elif offset.length() < 0.05: lbl = L.t("CENTER")
		if absf(offset.x) > 0.12:
			lbl = (L.t("RIGHT") if offset.x > 0 else L.t("LEFT")) + " " + lbl
		var f := UIKit.font(700)
		draw_string(f, Vector2(0, size.y + 30), lbl, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, UIKit.MUTED)


## ------------------------------------------------------------ Elevation slider (vertical)
class ElevationSlider extends Control:
	signal changed(deg: float)
	var value := 0.0          # what the player asked for
	var floor_deg := 0.0      # lowest angle at which the stick clears the rail and the balls (set every frame)
	var max_deg := 75.0
	var _drag := false

	func _init() -> void:
		custom_minimum_size = Vector2(84, 220)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Cue elevation: the stick can't go below the rail. 5-15 swerve, 25-50 jump, 60-75 masse"

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, max_deg)
		queue_redraw()

	var on_ball := false       # the floor comes from a ball in the way (not the rail)

	func set_floor(deg: float, p_on_ball := false) -> void:
		deg = clampf(deg, 0.0, max_deg)
		if absf(deg - floor_deg) > 0.05 or p_on_ball != on_ball:
			floor_deg = deg
			on_ball = p_on_ball
			queue_redraw()

	## The elevation the shot will have.
	func effective() -> float:
		return maxf(value, floor_deg)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if ev.pressed:
				_from(ev.position)
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_from(ev.position)
			accept_event()

	func _from(p: Vector2) -> void:
		var t := 1.0 - clampf((p.y - 20.0) / (size.y - 60.0), 0.0, 1.0)
		var v := roundf(t * max_deg / 5.0) * 5.0
		# anything at or below the rail means "as low as the rail allows"
		set_value(0.0 if v <= floor_deg else v)
		changed.emit(value)

	func _draw() -> void:
		var x := size.x * 0.5
		var top := 20.0
		var bot := size.y - 40.0
		var eff := effective()
		draw_line(Vector2(x, top), Vector2(x, bot), Color(1, 1, 1, 0.14), 10.0, true)
		var y := lerpf(bot, top, eff / max_deg)
		draw_line(Vector2(x, bot), Vector2(x, y), UIKit.SKY, 10.0, true)
		if floor_deg > 0.5:
			# the part of the scale the rail blocks
			var yf := lerpf(bot, top, floor_deg / max_deg)
			draw_line(Vector2(x, bot), Vector2(x, yf), Color(UIKit.GOLD, 0.85), 10.0, true)
			draw_line(Vector2(x - 16, yf), Vector2(x + 16, yf), UIKit.GOLD, 3.0, true)
		draw_circle(Vector2(x, y), 17.0, Color.WHITE)
		draw_circle(Vector2(x, y), 11.0, UIKit.GOLD if value <= floor_deg and floor_deg > 0.5 else UIKit.SKY)
		var f := UIKit.font(700)
		draw_string(f, Vector2(0, size.y - 6), "%d°" % int(roundf(eff)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, UIKit.TEXT)
		var kind := ""
		if eff >= 60.0: kind = L.t("MASSÉ")
		elif eff >= 25.0: kind = L.t("JUMP")
		elif value > floor_deg and eff >= 5.0: kind = L.t("SWERVE")
		elif floor_deg >= 5.0: kind = L.t("OVER A BALL") if on_ball else L.t("ON RAIL")
		if kind != "":
			draw_string(f, Vector2(-20, 12), kind, HORIZONTAL_ALIGNMENT_CENTER, size.x + 40, 18, UIKit.GOLD)


## ------------------------------------------------------------ Power piston (pull down, release)
class PowerPiston extends Control:
	signal released(power: float)
	signal changed(power: float)
	var power := 0.0
	var _drag := false
	var _y0 := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(130, 470)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_drag = true
				_y0 = ev.position.y
			else:
				_drag = false
				if power > 0.03:
					released.emit(power)
				power = 0.0
				changed.emit(power)
				queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			power = clampf((ev.position.y - _y0) / (size.y - 90.0), 0.0, 1.0)
			changed.emit(power)
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2(size.x * 0.5 - 30, 30), Vector2(60, size.y - 70))
		draw_style_box(UIKit.box(Color(0.04, 0.07, 0.12, 0.78), 30, 2, Color(1, 1, 1, 0.12)), r)
		var segs := 16
		for i in segs:
			var t := float(i) / segs
			var sy := r.position.y + 10 + t * (r.size.y - 20)
			var on := t < power
			var col := UIKit.EMERALD.lerp(UIKit.GOLD, t).lerp(UIKit.CORAL, maxf(t - 0.6, 0.0) * 2.5)
			draw_rect(Rect2(Vector2(r.position.x + 12, sy), Vector2(36, (r.size.y - 20) / segs - 5)), col if on else Color(1, 1, 1, 0.07))
		var hy := r.position.y + power * (r.size.y - 20)
		draw_style_box(UIKit.box(Color.WHITE, 14, 0, Color.WHITE), Rect2(Vector2(size.x * 0.5 - 46, hy - 6), Vector2(92, 28)))
		var f := UIKit.font(800)
		draw_string(f, Vector2(0, size.y - 6), "%d%%" % int(power * 100) if power > 0.0 else L.t("PULL"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, UIKit.TEXT)


## ------------------------------------------------------------ Aim wheel (fine rotation)
class AimWheel extends Control:
	signal rotated(delta_rad: float)
	var _drag := false
	var _phase := 0.0
	## Randy, 11 Nov 2026: twice the ribs and twice the turning speed, so one rib passing the centre line is
	## still the same turn of the cue (0.36 degrees at the normal sensitivity).
	const RIBS := 58             # spread evenly over the wheel, so they scroll round without a seam
	var sensitivity := 0.0007    # radians per pixel (~0.04 deg)

	func _init() -> void:
		custom_minimum_size = Vector2(560, 92)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Fine aim: drag left / right"

	## The wheel answers to touches one full wheel-height above and below itself as well, so a thumb that
	## lands a little off does not hit the table (which would swing the aim somewhere else entirely).
	func touch_zone() -> Rect2:
		return Rect2(Vector2(0, -size.y), Vector2(size.x, size.y * 3.0))

	func _has_point(point: Vector2) -> bool:
		return touch_zone().has_point(point)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			var dx: float = ev.relative.x
			var boost := 1.0 + clampf(absf(dx) - 6.0, 0.0, 40.0) * 0.08
			rotated.emit(dx * sensitivity * boost * float(Game.get_s("fine_aim_scale")))
			_phase += dx
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(Color(0.04, 0.07, 0.12, 0.8), 46, 2, Color(1, 1, 1, 0.12)), r)
		var span := size.x - 40.0
		var step := span / RIBS
		for i in RIBS:
			var x := fposmod(i * step + _phase, span) + 20.0
			var t := absf(x - size.x * 0.5) / (size.x * 0.5)
			var a := 0.75 * (1.0 - t * t)
			draw_line(Vector2(x, 20), Vector2(x, size.y - 20), Color(1, 1, 1, a), 2.0)
		draw_line(Vector2(size.x * 0.5, 10), Vector2(size.x * 0.5, size.y - 10), UIKit.EMERALD, 4.0)


## ------------------------------------------------------------ Stroke button (hold, thrust or release)
class StrokeButton extends Control:
	signal pressed_down
	signal released
	var charge := 0.0
	var holding := false
	var label := L.t("HOLD\nSTROKE")

	func _init() -> void:
		custom_minimum_size = Vector2(230, 230)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and not holding:
				holding = true
				pressed_down.emit()
			elif not ev.pressed and holding:
				holding = false
				released.emit()
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 10
		draw_circle(c + Vector2(0, 6), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color(0.05, 0.09, 0.15, 0.85) if not holding else Color(0.07, 0.25, 0.2, 0.92))
		draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.16), 3.0, true)
		if charge > 0.0:
			draw_arc(c, r - 9, -PI / 2, -PI / 2 + TAU * charge, 64, UIKit.EMERALD.lerp(UIKit.CORAL, maxf(charge - 0.6, 0.0) * 2.5), 14.0, true)
		var f := UIKit.font(800)
		var lines := label.split("\n")
		for i in lines.size():
			draw_string(f, Vector2(0, c.y - 8 + (i - (lines.size() - 1) * 0.5) * 34 + 12), lines[i], HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, UIKit.TEXT)


## HSlider that behaves well inside a touch-scrolled list: a vertical drag scrolls the list (instead of
## yanking the value), a horizontal drag or a tap sets the value. Mouse wheel scrolls the list.
class TouchSlider extends HSlider:
	const SLOP := 14.0
	var _pressed := false
	var _mode := 0              # 0 undecided, 1 sliding, 2 scrolling the list
	var _press := Vector2.ZERO
	var _scroll: ScrollContainer
	var _scroll_start := 0

	func _init() -> void:
		scrollable = false      # wheel events go to the ScrollContainer

	func _ready() -> void:
		var p := get_parent()
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		_scroll = p as ScrollContainer

	func _gui_input(ev: InputEvent) -> void:
		if not editable:
			return
		var mb := ev as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_mode = 0
				_press = mb.position
				_scroll_start = _scroll.scroll_vertical if _scroll else 0
				if _scroll == null:
					_mode = 1
					_set_from_x(mb.position.x)
			else:
				if _pressed and _mode == 0:
					_set_from_x(mb.position.x)   # a tap
				_pressed = false
				_mode = 0
			accept_event()
			return
		var mm := ev as InputEventMouseMotion
		if mm and _pressed:
			var d := mm.position - _press
			if _mode == 0:
				if absf(d.x) > SLOP and absf(d.x) > absf(d.y):
					_mode = 1
				elif absf(d.y) > SLOP:
					_mode = 2
			if _mode == 1:
				_set_from_x(mm.position.x)
			elif _mode == 2:
				_scroll.scroll_vertical = _scroll_start - int(d.y)
			accept_event()

	func _set_from_x(x: float) -> void:
		var gw := float(get_theme_icon("grabber").get_width())
		set_as_ratio(clampf((x - gw * 0.5) / maxf(size.x - gw, 1.0), 0.0, 1.0))


## ------------------------------------------------------------ Trackpad (relative drag with acceleration)
class TrackPad extends Control:
	signal turned(clockwise_rad: float)
	var precision := false
	var _drag := false
	var _last_tap := 0
	var _trail := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(560, 150)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Slide sideways to turn the cue. Slow = super fine. Double-tap for precision lock."

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				var now := Time.get_ticks_msec()
				if now - _last_tap < 280:
					precision = not precision
					Sfx.ui("toggle")
				_last_tap = now
			_drag = ev.pressed
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			var dx: float = ev.relative.x
			var speed := absf(ev.velocity.x)
			# acceleration curve: slow drags 0.004 deg/px, fast flicks up to 0.3 deg/px
			var deg_px := lerpf(0.004, 0.3, smoothstep(60.0, 1600.0, speed))
			if precision:
				deg_px *= 0.25
			turned.emit(deg_to_rad(dx * deg_px) * float(Game.get_s("fine_aim_scale")))
			_trail += dx
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(Color(0.04, 0.07, 0.12, 0.8), 28, 2, UIKit.GOLD if precision else Color(1, 1, 1, 0.12)), r)
		# dotted grid that slides with the finger
		for gx in range(0, 22):
			var x := fposmod(gx * 28.0 + _trail * 0.5, size.x - 30.0) + 15.0
			for gy in 4:
				var y := 30.0 + gy * (size.y - 60.0) / 3.0
				var t := absf(x - size.x * 0.5) / (size.x * 0.5)
				draw_circle(Vector2(x, y), 2.5, Color(1, 1, 1, 0.5 * (1.0 - t * t)))
		var f := UIKit.font(700)
		draw_string(f, Vector2(0, size.y - 14), L.t("PRECISION ×4") if precision else L.t("slide · double-tap = precision"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UIKit.GOLD if precision else UIKit.MUTED)


## ------------------------------------------------------------ Crank knob (turn in circles)
class CrankKnob extends Control:
	signal turned(knob_rad: float)
	var _drag := false
	var _last_a := 0.0
	var angle := 0.0
	var ratio_label := "1:20"

	func _init() -> void:
		custom_minimum_size = Vector2(192, 192)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Turn the crank in circles for continuous fine aim"

	func _gui_input(ev: InputEvent) -> void:
		var c := size * 0.5
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if ev.pressed:
				_last_a = (ev.position - c).angle()
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			var v: Vector2 = ev.position - c
			if v.length() < 18.0:
				accept_event()
				return   # too close to the hub to read an angle
			var a := v.angle()
			var da := wrapf(a - _last_a, -PI, PI)
			_last_a = a
			angle += da
			turned.emit(da)
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color(0.05, 0.08, 0.13, 0.9))
		draw_arc(c, r, 0, TAU, 72, Color(1, 1, 1, 0.16), 3.0, true)
		for k in 36:
			var a := angle + TAU * k / 36.0
			var p0 := c + Vector2.from_angle(a) * (r - 4.0)
			var p1 := c + Vector2.from_angle(a) * (r - (16.0 if k % 3 == 0 else 10.0))
			draw_line(p0, p1, Color(1, 1, 1, 0.55 if k % 3 == 0 else 0.25), 2.0, true)
		# crank handle
		var hp := c + Vector2.from_angle(angle - PI * 0.5) * (r * 0.62)
		draw_line(c, hp, Color(1, 1, 1, 0.25), 8.0, true)
		draw_circle(hp, 22.0, Color.WHITE)
		draw_circle(hp, 15.0, UIKit.EMERALD)
		draw_circle(c, 30.0, Color(0.1, 0.14, 0.2, 1.0))
		var f := UIKit.font(800)
		draw_string(f, c + Vector2(-40, 8), ratio_label, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, UIKit.TEXT)


## ------------------------------------------------------------ Micro pad (slow-motion 2D mover)
class MicroPad extends Control:
	signal moved(delta_px: Vector2)
	var _drag := false
	var _knob := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(184, 184)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Drag to move the target in slow motion"

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if not ev.pressed:
				_knob = Vector2.ZERO
				queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			moved.emit(ev.relative)
			_knob = (_knob + ev.relative * 0.35).limit_length(minf(size.x, size.y) * 0.3)
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_style_box(UIKit.box(Color(0.04, 0.07, 0.12, 0.8), int(r), 2, Color(1, 1, 1, 0.12)), Rect2(Vector2(6, 6), size - Vector2(12, 12)))
		for k in 4:
			var d := Vector2.from_angle(TAU * k / 4.0)
			var tip := c + d * (r - 16.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 + d.orthogonal() * 9.0, tip - d * 14.0 - d.orthogonal() * 9.0]), Color(1, 1, 1, 0.35))
		draw_circle(c + _knob, 34.0, Color(1, 1, 1, 0.92))
		draw_arc(c + _knob, 34.0, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		draw_circle(c + _knob, 6.0, UIKit.SKY)
		var f := UIKit.font(700)
		draw_string(f, Vector2(0, -10), L.t("MICRO MOVE"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UIKit.MUTED)


## ------------------------------------------------------------ Thumbstick (rate control)
class Thumbstick extends Control:
	var deflection := 0.0      # -1..1 (x)
	var _drag := false
	var _knob := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(196, 196)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Push left / right to turn the cue — a little = very slow, all the way = fast"

	func _gui_input(ev: InputEvent) -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 34.0
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if ev.pressed:
				_set_knob(ev.position - c, r)
			else:
				_knob = Vector2.ZERO
				deflection = 0.0
				queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_set_knob(ev.position - c, r)
			accept_event()

	func _set_knob(v: Vector2, r: float) -> void:
		_knob = Vector2(clampf(v.x, -r, r), clampf(v.y, -r, r) * 0.25)
		deflection = _knob.x / r
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color(0.04, 0.07, 0.12, 0.85))
		draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.14), 3.0, true)
		# speed zones: fine (green) near the centre, fast (coral) at the edge
		var inner := r - 30.0
		for side in [-1.0, 1.0]:
			for k in 8:
				var t := (k + 0.5) / 8.0
				var x: float = c.x + side * t * inner
				var col := UIKit.EMERALD.lerp(UIKit.CORAL, t * t)
				draw_circle(Vector2(x, c.y), 3.0 + t * 3.0, Color(col, 0.6))
		draw_circle(c + _knob, 34.0, Color(1, 1, 1, 0.95))
		draw_circle(c + _knob, 13.0, UIKit.EMERALD.lerp(UIKit.CORAL, absf(deflection)))
		var f := UIKit.font(700)
		var rate := Widgets.Thumbstick.rate_deg(deflection)
		draw_string(f, Vector2(0, -10), ("%.2f°/s" % absf(rate)) if absf(deflection) > 0.01 else L.t("PUSH ◀ ▶"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UIKit.MUTED)

	## Turn speed for a deflection: cubic so small pushes are extremely slow.
	static func rate_deg(x: float) -> float:
		return signf(x) * (0.15 * absf(x) + 39.85 * pow(absf(x), 3.0))
