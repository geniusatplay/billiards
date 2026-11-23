class_name IconGlyph
extends Control
## Resolution-independent vector icons drawn with canvas primitives.

@export var icon := "gear"
@export var color := Color.WHITE
var line_w := 0.0


static func make(p_icon: String, p_size := 48.0, p_color := Color.WHITE) -> IconGlyph:
	var g := IconGlyph.new()
	g.icon = p_icon
	g.color = p_color
	g.custom_minimum_size = Vector2(p_size, p_size)
	g.size = Vector2(p_size, p_size)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func set_icon(p_icon: String) -> void:
	icon = p_icon
	queue_redraw()


## An arc from a0 to a1 (radians, screen angles) ending in an arrowhead that points the way the arc runs; the line
## stops at the head's back so no line pokes out past it.
func _arc_arrow(cen: Vector2, r: float, a0: float, a1: float, w: float, c: Color, s: float) -> void:
	var dir := signf(a1 - a0)
	var head := s * 0.2                       # the head's length along the arc
	var back := a1 - dir * (head * 0.55) / r   # where the line stops (the head's back)
	draw_arc(cen, r, a0, back, 32, c, w, true)
	var p := cen + Vector2(cos(a1), sin(a1)) * r
	var t := Vector2(-sin(a1), cos(a1)) * dir         # the way the arc runs at its end
	var n := Vector2(cos(a1), sin(a1))
	var base := p - t * head * 0.6
	var half := s * 0.13
	draw_colored_polygon(PackedVector2Array([p + t * head * 0.4, base + n * half, base - n * half]), c)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var w := line_w if line_w > 0.0 else maxf(2.0, s * 0.085)
	var c := color
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match icon:
		"gear":
			var cen: Vector2 = P.call(0.5, 0.5)
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var tooth := 1.0 if (i / 3) % 2 == 0 else 0.78
				pts.append(cen + Vector2(cos(a), sin(a)) * s * 0.42 * tooth)
			pts.append(pts[0])
			draw_polyline(pts, c, w * 0.8, true)
			draw_arc(cen, s * 0.14, 0, TAU, 24, c, w, true)
		"pause":
			draw_rect(Rect2(P.call(0.28, 0.2), Vector2(s * 0.14, s * 0.6)), c)
			draw_rect(Rect2(P.call(0.58, 0.2), Vector2(s * 0.14, s * 0.6)), c)
		"play":
			draw_colored_polygon(PackedVector2Array([P.call(0.3, 0.18), P.call(0.82, 0.5), P.call(0.3, 0.82)]), c)
		"back", "chev_left":
			draw_polyline(PackedVector2Array([P.call(0.62, 0.18), P.call(0.3, 0.5), P.call(0.62, 0.82)]), c, w * 1.2, true)
		"chev_right":
			draw_polyline(PackedVector2Array([P.call(0.38, 0.18), P.call(0.7, 0.5), P.call(0.38, 0.82)]), c, w * 1.2, true)
		"chev_up":
			draw_polyline(PackedVector2Array([P.call(0.18, 0.62), P.call(0.5, 0.3), P.call(0.82, 0.62)]), c, w * 1.2, true)
		"chev_down":
			draw_polyline(PackedVector2Array([P.call(0.18, 0.38), P.call(0.5, 0.7), P.call(0.82, 0.38)]), c, w * 1.2, true)
		"plus", "minus":
			# a magnifier with + or -: zoom in / out
			draw_arc(P.call(0.42, 0.42), s * 0.27, 0, TAU, 28, c, w, true)
			draw_line(P.call(0.62, 0.62), P.call(0.88, 0.88), c, w * 1.4, true)
			draw_line(P.call(0.3, 0.42), P.call(0.54, 0.42), c, w, true)
			if icon == "plus":
				draw_line(P.call(0.42, 0.3), P.call(0.42, 0.54), c, w, true)
		"close":
			draw_line(P.call(0.22, 0.22), P.call(0.78, 0.78), c, w * 1.2, true)
			draw_line(P.call(0.78, 0.22), P.call(0.22, 0.78), c, w * 1.2, true)
		"check":
			draw_polyline(PackedVector2Array([P.call(0.18, 0.52), P.call(0.42, 0.76), P.call(0.84, 0.26)]), c, w * 1.3, true)
		"camera":
			draw_rect(Rect2(P.call(0.1, 0.3), Vector2(s * 0.8, s * 0.52)), c, false, w)
			draw_rect(Rect2(P.call(0.34, 0.2), Vector2(s * 0.3, s * 0.1)), c)
			draw_arc(P.call(0.5, 0.56), s * 0.15, 0, TAU, 24, c, w, true)
		"cube", "studio":
			var pts2 := PackedVector2Array([P.call(0.5, 0.12), P.call(0.86, 0.32), P.call(0.86, 0.7), P.call(0.5, 0.9), P.call(0.14, 0.7), P.call(0.14, 0.32), P.call(0.5, 0.12)])
			draw_polyline(pts2, c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.14, 0.32), P.call(0.5, 0.52), P.call(0.86, 0.32)]), c, w, true)
			draw_line(P.call(0.5, 0.52), P.call(0.5, 0.9), c, w, true)
		"eye":
			var e1 := PackedVector2Array()
			for i in 25:
				var tt := float(i) / 24.0
				e1.append(P.call(0.08 + 0.84 * tt, 0.5 - 0.3 * sin(PI * tt)))
			for i in 25:
				var tt := float(i) / 24.0
				e1.append(P.call(0.92 - 0.84 * tt, 0.5 + 0.3 * sin(PI * tt)))
			draw_polyline(e1, c, w, true)
			draw_circle(P.call(0.5, 0.5), s * 0.12, c)
		"target", "aim_cam":
			draw_arc(P.call(0.5, 0.5), s * 0.36, 0, TAU, 32, c, w, true)
			draw_circle(P.call(0.5, 0.5), s * 0.08, c)
			for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				draw_line(P.call(0.5, 0.5) + d * s * 0.22, P.call(0.5, 0.5) + d * s * 0.48, c, w, true)
		"top_view":
			draw_rect(Rect2(P.call(0.12, 0.26), Vector2(s * 0.76, s * 0.48)), c, false, w)
			for q in [Vector2(0.12, 0.26), Vector2(0.88, 0.26), Vector2(0.12, 0.74), Vector2(0.88, 0.74), Vector2(0.5, 0.26), Vector2(0.5, 0.74)]:
				draw_circle(P.call(q.x, q.y), s * 0.06, c)
		"refresh", "recenter":
			# a clockwise circle, its arrowhead on the end, pointing the way it turns (22 Nov: the old head sat off the
			# line, Randy: "the arrow on the rotate thing doesnt look right")
			_arc_arrow(P.call(0.5, 0.52), s * 0.3, deg_to_rad(-60), deg_to_rad(235), w, c, s)
		"undo":
			_arc_arrow(P.call(0.52, 0.56), s * 0.3, deg_to_rad(40), deg_to_rad(-170), w, c, s)
		"rot_left", "rot_right":
			# turn the table: the circle arrow (Randy, 22 Nov, of the redrawn one: "I like this"), clockwise for
			# right, its mirror image for left
			if icon == "rot_right":
				_arc_arrow(P.call(0.5, 0.52), s * 0.3, deg_to_rad(-60), deg_to_rad(235), w, c, s)
			else:
				_arc_arrow(P.call(0.5, 0.52), s * 0.3, deg_to_rad(240), deg_to_rad(-55), w, c, s)
		"cue_ball":
			# the white ball (the button that moves it: Randy, 22 Nov, "please make the icon look like a cue ball"):
			# a white ball, shaded at the bottom right, with a small red spot
			var cb: Vector2 = P.call(0.5, 0.5)
			var rb := s * 0.38
			draw_circle(cb, rb, c.darkened(0.42), true, -1.0, true)
			draw_circle(cb + Vector2(-0.03, -0.03) * s, rb * 0.86, c, true, -1.0, true)
			draw_circle(cb + Vector2(-0.11, -0.12) * s, s * 0.07, Color(1, 1, 1, 0.95), true, -1.0, true)
			draw_circle(cb + Vector2(0.07, 0.07) * s, s * 0.065, Color("e12d2d"), true, -1.0, true)
		"star", "star_empty":
			var sp := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				var r := 0.46 if i % 2 == 0 else 0.2
				sp.append(P.call(0.5 + cos(a) * r, 0.53 + sin(a) * r))
			if icon == "star":
				draw_colored_polygon(sp, c)
			else:
				sp.append(sp[0])
				draw_polyline(sp, c, w * 0.8, true)
		"lock":
			draw_rect(Rect2(P.call(0.2, 0.44), Vector2(s * 0.6, s * 0.44)), c)
			draw_arc(P.call(0.5, 0.44), s * 0.2, PI, TAU, 16, c, w * 1.2, true)
		"help":
			draw_arc(P.call(0.5, 0.36), s * 0.18, deg_to_rad(180), deg_to_rad(400), 20, c, w * 1.1, true)
			draw_line(P.call(0.5, 0.54), P.call(0.5, 0.64), c, w * 1.1, true)
			draw_circle(P.call(0.5, 0.82), s * 0.06, c)
		"sliders", "debug":
			for i in 3:
				var y := 0.24 + i * 0.26
				draw_line(P.call(0.12, y), P.call(0.88, y), c, w, true)
				var kx: float = [0.32, 0.66, 0.46][i]
				draw_circle(P.call(kx, y), s * 0.09, c)
		"trophy":
			draw_arc(P.call(0.5, 0.28), s * 0.26, 0, PI, 16, c, w * 1.2, true)
			draw_line(P.call(0.24, 0.28), P.call(0.76, 0.28), c, w * 1.2, true)
			draw_line(P.call(0.5, 0.54), P.call(0.5, 0.74), c, w * 1.2, true)
			draw_rect(Rect2(P.call(0.3, 0.74), Vector2(s * 0.4, s * 0.1)), c)
		"globe":
			var gc: Vector2 = P.call(0.5, 0.5)
			draw_arc(gc, s * 0.4, 0, TAU, 40, c, w, true)
			draw_line(P.call(0.1, 0.5), P.call(0.9, 0.5), c, w * 0.8, true)
			draw_line(P.call(0.5, 0.1), P.call(0.5, 0.9), c, w * 0.8, true)
			var mer := PackedVector2Array()
			var mer2 := PackedVector2Array()
			for i in 25:
				var a := -PI * 0.5 + PI * i / 24.0
				mer.append(gc + Vector2(cos(a) * s * 0.2, sin(a) * s * 0.4))
				mer2.append(gc + Vector2(-cos(a) * s * 0.2, sin(a) * s * 0.4))
			draw_polyline(mer, c, w * 0.8, true)
			draw_polyline(mer2, c, w * 0.8, true)
		"user":
			draw_circle(P.call(0.5, 0.32), s * 0.16, c)
			draw_arc(P.call(0.5, 0.92), s * 0.36, PI, TAU, 20, c, w * 1.4, true)
		"users":
			draw_circle(P.call(0.36, 0.34), s * 0.13, c)
			draw_arc(P.call(0.36, 0.9), s * 0.28, PI, TAU, 16, c, w * 1.2, true)
			draw_circle(P.call(0.68, 0.3), s * 0.11, Color(c, 0.75))
			draw_arc(P.call(0.7, 0.8), s * 0.22, PI, TAU, 16, Color(c, 0.75), w, true)
		"robot":
			draw_rect(Rect2(P.call(0.18, 0.3), Vector2(s * 0.64, s * 0.5)), c, false, w)
			draw_circle(P.call(0.38, 0.52), s * 0.07, c)
			draw_circle(P.call(0.62, 0.52), s * 0.07, c)
			draw_line(P.call(0.5, 0.3), P.call(0.5, 0.14), c, w, true)
			draw_circle(P.call(0.5, 0.12), s * 0.05, c)
		"ball", "practice":
			draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 32, c, w, true)
			draw_circle(P.call(0.5, 0.5), s * 0.16, c)
		"levels", "grid":
			for gx in 2:
				for gy in 2:
					draw_rect(Rect2(P.call(0.14 + gx * 0.4, 0.14 + gy * 0.4), Vector2(s * 0.3, s * 0.3)), c, false, w)
		"hand":
			draw_rect(Rect2(P.call(0.28, 0.46), Vector2(s * 0.46, s * 0.4)), c, false, w)
			for i in 4:
				draw_line(P.call(0.32 + i * 0.12, 0.46), P.call(0.32 + i * 0.12, 0.18 + absf(i - 1.5) * 0.06), c, w, true)
		"sound":
			draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.38), P.call(0.3, 0.38), P.call(0.5, 0.2), P.call(0.5, 0.8), P.call(0.3, 0.62), P.call(0.12, 0.62)]), c)
			draw_arc(P.call(0.52, 0.5), s * 0.18, -0.9, 0.9, 12, c, w, true)
			draw_arc(P.call(0.52, 0.5), s * 0.32, -0.9, 0.9, 16, c, w, true)
		"vibrate":
			draw_rect(Rect2(P.call(0.34, 0.16), Vector2(s * 0.32, s * 0.68)), c, false, w)
			for sx in [-1.0, 1.0]:
				draw_polyline(PackedVector2Array([P.call(0.5 + sx * 0.28, 0.3), P.call(0.5 + sx * 0.38, 0.42), P.call(0.5 + sx * 0.28, 0.54), P.call(0.5 + sx * 0.38, 0.66)]), c, w * 0.8, true)
		"move":
			draw_line(P.call(0.5, 0.1), P.call(0.5, 0.9), c, w, true)
			draw_line(P.call(0.1, 0.5), P.call(0.9, 0.5), c, w, true)
			for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				var tipm: Vector2 = P.call(0.5, 0.5) + d * s * 0.42
				var side := Vector2(-d.y, d.x) * s * 0.1
				draw_colored_polygon(PackedVector2Array([tipm + d * s * 0.06, tipm - d * s * 0.1 + side, tipm - d * s * 0.1 - side]), c)
		"home":
			draw_polyline(PackedVector2Array([P.call(0.12, 0.5), P.call(0.5, 0.16), P.call(0.88, 0.5)]), c, w * 1.1, true)
			draw_polyline(PackedVector2Array([P.call(0.24, 0.42), P.call(0.24, 0.86), P.call(0.76, 0.86), P.call(0.76, 0.42)]), c, w, true)
		"kit":
			# a small table with a ball on it and a cue: "your cue, table and balls"
			draw_rect(Rect2(P.call(0.1, 0.56), Vector2(s * 0.8, s * 0.26)), c, false, w)
			draw_line(P.call(0.18, 0.82), P.call(0.18, 0.92), c, w, true)
			draw_line(P.call(0.82, 0.82), P.call(0.82, 0.92), c, w, true)
			draw_circle(P.call(0.38, 0.47), s * 0.09, c)
			draw_line(P.call(0.52, 0.42), P.call(0.92, 0.1), c, w * 1.2, true)
		"gift":
			draw_rect(Rect2(P.call(0.14, 0.44), Vector2(s * 0.72, s * 0.44)), c, false, w)
			draw_rect(Rect2(P.call(0.08, 0.28), Vector2(s * 0.84, s * 0.16)), c, false, w)
			draw_line(P.call(0.5, 0.28), P.call(0.5, 0.88), c, w, true)
			draw_arc(P.call(0.38, 0.2), s * 0.11, 0, TAU, 14, c, w * 0.9, true)
			draw_arc(P.call(0.62, 0.2), s * 0.11, 0, TAU, 14, c, w * 0.9, true)
		"gem":
			draw_colored_polygon(PackedVector2Array([P.call(0.28, 0.2), P.call(0.72, 0.2), P.call(0.9, 0.4), P.call(0.5, 0.88), P.call(0.1, 0.4)]), c)
			draw_polyline(PackedVector2Array([P.call(0.1, 0.4), P.call(0.9, 0.4)]), Color(0, 0, 0, 0.35), w * 0.6, true)
		"clock":
			draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 32, c, w, true)
			draw_line(P.call(0.5, 0.5), P.call(0.5, 0.26), c, w, true)
			draw_line(P.call(0.5, 0.5), P.call(0.68, 0.58), c, w, true)
		"flag":
			draw_line(P.call(0.24, 0.12), P.call(0.24, 0.9), c, w, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.24, 0.14), P.call(0.82, 0.3), P.call(0.24, 0.5)]), c)
		"cue":
			draw_line(P.call(0.12, 0.88), P.call(0.74, 0.26), c, w * 1.3, true)
			draw_circle(P.call(0.84, 0.16), s * 0.1, c)
		"spin":
			draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 32, c, w, true)
			draw_circle(P.call(0.6, 0.36), s * 0.08, c)
		# v1.1.15 (options menu, world placement, sharing)
		"music":
			draw_circle(P.call(0.3, 0.74), s * 0.12, c)
			draw_circle(P.call(0.74, 0.64), s * 0.12, c)
			draw_line(P.call(0.41, 0.74), P.call(0.41, 0.2), c, w * 1.1, true)
			draw_line(P.call(0.85, 0.64), P.call(0.85, 0.12), c, w * 1.1, true)
			draw_colored_polygon(PackedVector2Array([P.call(0.39, 0.16), P.call(0.87, 0.06), P.call(0.87, 0.2), P.call(0.39, 0.3)]), c)
		"language":
			# a speech bubble with an "A" in it
			draw_rect(Rect2(P.call(0.1, 0.14), Vector2(s * 0.8, s * 0.56)), c, false, w)
			draw_colored_polygon(PackedVector2Array([P.call(0.26, 0.68), P.call(0.44, 0.68), P.call(0.26, 0.88)]), c)
			draw_polyline(PackedVector2Array([P.call(0.36, 0.58), P.call(0.5, 0.24), P.call(0.64, 0.58)]), c, w, true)
			draw_line(P.call(0.41, 0.46), P.call(0.59, 0.46), c, w * 0.9, true)
		"size":
			# two corners pulled apart
			draw_line(P.call(0.2, 0.8), P.call(0.8, 0.2), c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.52, 0.2), P.call(0.8, 0.2), P.call(0.8, 0.48)]), c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.2, 0.52), P.call(0.2, 0.8), P.call(0.48, 0.8)]), c, w, true)
		"height":
			draw_line(P.call(0.5, 0.12), P.call(0.5, 0.88), c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.32, 0.3), P.call(0.5, 0.12), P.call(0.68, 0.3)]), c, w, true)
			draw_polyline(PackedVector2Array([P.call(0.32, 0.7), P.call(0.5, 0.88), P.call(0.68, 0.7)]), c, w, true)
			draw_line(P.call(0.14, 0.88), P.call(0.86, 0.88), c, w * 0.7, true)
		"place":
			# the AR viewfinder's corners round a small table
			for cx in [0.0, 1.0]:
				for cy in [0.0, 1.0]:
					var corner: Vector2 = P.call(0.1 + cx * 0.8, 0.1 + cy * 0.8)
					var dx: float = (1.0 - 2.0 * cx) * s * 0.2
					var dy: float = (1.0 - 2.0 * cy) * s * 0.2
					draw_polyline(PackedVector2Array([corner + Vector2(dx, 0), corner, corner + Vector2(0, dy)]), c, w, true)
			draw_rect(Rect2(P.call(0.28, 0.4), Vector2(s * 0.44, s * 0.14)), c)
			draw_line(P.call(0.33, 0.54), P.call(0.33, 0.68), c, w * 0.9, true)
			draw_line(P.call(0.67, 0.54), P.call(0.67, 0.68), c, w * 0.9, true)
		"image":
			draw_rect(Rect2(P.call(0.1, 0.18), Vector2(s * 0.8, s * 0.64)), c, false, w)
			draw_colored_polygon(PackedVector2Array([P.call(0.16, 0.76), P.call(0.42, 0.44), P.call(0.6, 0.64), P.call(0.7, 0.54), P.call(0.84, 0.76)]), c)
			draw_circle(P.call(0.7, 0.34), s * 0.07, c)
		"share":
			var a1: Vector2 = P.call(0.74, 0.2)
			var a2: Vector2 = P.call(0.26, 0.5)
			var a3: Vector2 = P.call(0.74, 0.8)
			draw_line(a1, a2, c, w, true)
			draw_line(a2, a3, c, w, true)
			for q in [a1, a2, a3]:
				draw_circle(q, s * 0.12, c)
		"copy":
			draw_rect(Rect2(P.call(0.3, 0.3), Vector2(s * 0.54, s * 0.58)), c, false, w)
			draw_polyline(PackedVector2Array([P.call(0.16, 0.66), P.call(0.16, 0.12), P.call(0.62, 0.12)]), c, w, true)
		"qr":
			for q in [Vector2(0.12, 0.12), Vector2(0.58, 0.12), Vector2(0.12, 0.58)]:
				draw_rect(Rect2(P.call(q.x, q.y), Vector2(s * 0.3, s * 0.3)), c, false, w)
				draw_rect(Rect2(P.call(q.x + 0.09, q.y + 0.09), Vector2(s * 0.12, s * 0.12)), c)
			for q in [Vector2(0.6, 0.6), Vector2(0.6, 0.76), Vector2(0.76, 0.76)]:
				draw_rect(Rect2(P.call(q.x, q.y), Vector2(s * 0.12, s * 0.12)), c)
		"school":
			# a mortarboard: the tutorial
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.18), P.call(0.94, 0.38), P.call(0.5, 0.58), P.call(0.06, 0.38)]), c)
			draw_polyline(PackedVector2Array([P.call(0.24, 0.48), P.call(0.24, 0.72), P.call(0.5, 0.84), P.call(0.76, 0.72), P.call(0.76, 0.48)]), c, w, true)
			draw_line(P.call(0.88, 0.4), P.call(0.88, 0.7), c, w * 0.8, true)
		_:
			draw_arc(P.call(0.5, 0.5), s * 0.36, 0, TAU, 24, c, w, true)
