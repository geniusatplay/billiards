class_name LoadingScreen
extends Control
## v1.1.15 (Randy: "a nice loading screen for when the app starts instead of the godot screen. it should have
## emerald vortex games & AR Pool Game"). Five designs (STYLE_NAMES), all drawn here, frame by frame:
##   0 Vortex   - the emerald gem in turning rings, a cue ball circling it
##   1 Break    - a cue ball breaks a rack on green cloth, then the title
##   2 Neon     - a neon table draws itself, the title flickers on
##   3 AR scan  - a scanning grid, corner brackets lock onto a table
##   4 Studio   - the studio's name first, then the title with a gold shimmer and bouncing balls
## Shown while the phone builds its shaders, when a frame can take a second or more: time advances at most 1/20 s
## a frame, so after such a frame the animation carries on instead of jumping.

const STYLE_NAMES := ["Vortex", "Break", "Neon", "AR scan", "Studio"]
const STUDIO := "EMERALD VORTEX GAMES"
const SUBTITLE := "AR POOL GAME"
const BALL_COLORS := [Color("f4f1ea"), Color("f7c52b"), Color("1d4fd8"), Color("e12d2d"), Color("6b2fb3"), Color("f07d1a"),
	Color("1f9d55"), Color("8a1c2b"), Color("101114")]

var style := 0
var t := 0.0
var progress := -1.0          # 0..1 when known; below 0: an endless loading line
var _shown := 0.0             # the line glides to `progress` instead of jumping
var status := ""
var title := "EMERALD BREAK"
var _bold: Font
var _semi: Font
var _med: Font
var _bg_tex: GradientTexture2D
var _band_tex: GradientTexture2D
var _balls: Array = []        # Break: [pos, vel, number]
var _cue := {}
var _broken := false


func _init(p_style := 0) -> void:
	style = clampi(p_style, 0, STYLE_NAMES.size() - 1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bold = UIKit.font(900)
	_semi = UIKit.font(700)
	_med = UIKit.font(560)
	if status == "":
		status = L.t("Loading…")
	_bg_tex = _make_bg()
	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.32, 0.68, 1.0])
	bg.colors = PackedColorArray([Color(0.01, 0.06, 0.04, 0.0), Color(0.01, 0.06, 0.04, 0.62), Color(0.01, 0.06, 0.04, 0.62), Color(0.01, 0.06, 0.04, 0.0)])
	_band_tex = GradientTexture2D.new()
	_band_tex.gradient = bg
	_band_tex.width = 4
	_band_tex.height = 128
	_band_tex.fill_from = Vector2(0, 0)
	_band_tex.fill_to = Vector2(0, 1)
	if style == 1:
		_rack()


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 20.0)
	t += dt
	if progress >= 0.0:
		_shown = minf(progress, _shown + maxf(progress - _shown, 0.05) * dt * 3.0)
	if style == 1:
		_step_break(dt)
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(_bg_tex, Rect2(Vector2.ZERO, size), false)
	match style:
		0: _draw_vortex()
		1: _draw_break()
		2: _draw_neon()
		3: _draw_scan()
		4: _draw_studio()


# ======================================================================== shared
func _make_bg() -> GradientTexture2D:
	var g := Gradient.new()
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	match style:
		0:
			g.set_color(0, Color("123a3a"))
			g.set_color(1, Color("070c16"))
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.38)
			tex.fill_to = Vector2(1.15, 1.1)
		1:
			g.set_color(0, Color("13724f"))
			g.set_color(1, Color("042218"))
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.45)
			tex.fill_to = Vector2(1.2, 1.2)
		2:
			g.set_color(0, Color("140a26"))
			g.set_color(1, Color("030409"))
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.42)
			tex.fill_to = Vector2(1.1, 1.0)
		3:
			g.set_color(0, Color("0b1a2c"))
			g.set_color(1, Color("04070d"))
			tex.fill_from = Vector2(0.5, 1.0)
			tex.fill_to = Vector2(0.5, 0.0)
		_:
			g.set_color(0, Color("0a1322"))
			g.set_color(1, Color("0b3a30"))
			tex.fill_from = Vector2(0.0, 0.0)
			tex.fill_to = Vector2(1.0, 1.0)
	tex.gradient = g
	return tex


## 0..1 as time goes from t0 to t0 + dur, eased.
func _in(t0: float, dur: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - t0) / dur, 0.0, 1.0))


## Text centred on (cx, cy), with extra space between letters; per-letter colour from `tint` if given.
func _text(font: Font, fs: int, text: String, at: Vector2, col: Color, spacing := 0.0, tint := Callable()) -> float:
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w
	total += spacing * maxf(0.0, text.length() - 1)
	var x := at.x - total * 0.5
	var base := at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	for i in text.length():
		var c := col
		if tint.is_valid():
			c = tint.call(x + widths[i] * 0.5, c)
		draw_string(font, Vector2(x, base), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		x += widths[i] + spacing
	return total


## The same, with a soft glow round the letters (neon).
func _glow_text(font: Font, fs: int, text: String, at: Vector2, col: Color, glow: Color, spacing := 0.0) -> void:
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w
	total += spacing * maxf(0.0, text.length() - 1)
	var base := at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	for pass_i in 3:
		var x := at.x - total * 0.5
		var ow: int = [26, 14, 6][pass_i]
		var oc := Color(glow, glow.a * [0.10, 0.20, 0.45][pass_i])
		for i in text.length():
			draw_string_outline(font, Vector2(x, base), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, oc)
			x += widths[i] + spacing
	_text(font, fs, text, at, col, spacing)


func _gem(c: Vector2, s: float, alpha := 1.0, shine := -1.0) -> void:
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	var facets := [
		[[p.call(-0.30, -0.40), p.call(-0.55, -0.12), p.call(-0.15, -0.12)], Color("5ef0c0")],
		[[p.call(-0.30, -0.40), p.call(0.30, -0.40), p.call(0.15, -0.12), p.call(-0.15, -0.12)], Color("9cf6d6")],
		[[p.call(0.30, -0.40), p.call(0.55, -0.12), p.call(0.15, -0.12)], Color("4fe2b4")],
		[[p.call(-0.55, -0.12), p.call(-0.15, -0.12), p.call(0.0, 0.58)], Color("22c991")],
		[[p.call(-0.15, -0.12), p.call(0.15, -0.12), p.call(0.0, 0.58)], Color("2be7a5")],
		[[p.call(0.15, -0.12), p.call(0.55, -0.12), p.call(0.0, 0.58)], Color("12a878")],
	]
	if s < 4.0:
		return
	for f in facets:
		draw_colored_polygon(PackedVector2Array(f[0]), Color(f[1], alpha))
	if shine >= 0.0:
		# a band of light crossing the stone
		var bx := lerpf(-0.9, 0.9, shine)
		var band := PackedVector2Array([p.call(bx - 0.10, -0.6), p.call(bx + 0.06, -0.6), p.call(bx - 0.14, 0.7), p.call(bx - 0.30, 0.7)])
		for f in facets:
			for part in Geometry2D.intersect_polygons(PackedVector2Array(f[0]), band):
				if part.size() >= 3 and absf(_area(part)) > 2.0:      # (a sliver at the stone's edge can't be filled)
					draw_colored_polygon(part, Color(1, 1, 1, 0.55 * alpha))
	var outline := PackedVector2Array([p.call(-0.30, -0.40), p.call(0.30, -0.40), p.call(0.55, -0.12), p.call(0.0, 0.58), p.call(-0.55, -0.12), p.call(-0.30, -0.40)])
	draw_polyline(outline, Color(1, 1, 1, 0.25 * alpha), maxf(1.0, s * 0.012), true)


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a * 0.5


func _ball(c: Vector2, r: float, num: int, alpha := 1.0) -> void:
	var base: Color = BALL_COLORS[num % 9] if num <= 8 else BALL_COLORS[num - 8]
	if num == 0:
		base = BALL_COLORS[0]
	# a soft shadow on the cloth
	draw_circle(c + Vector2(r * 0.12, r * 0.22), r * 1.02, Color(0, 0, 0, 0.30 * alpha))
	if num >= 9:
		draw_circle(c, r, Color(BALL_COLORS[0], alpha))
		var circ := PackedVector2Array()
		for k in 28:
			circ.append(c + Vector2.from_angle(TAU * k / 28.0) * r)
		var band := PackedVector2Array([c + Vector2(-r * 1.1, -r * 0.48), c + Vector2(r * 1.1, -r * 0.48), c + Vector2(r * 1.1, r * 0.48), c + Vector2(-r * 1.1, r * 0.48)])
		for part in Geometry2D.intersect_polygons(circ, band):
			draw_colored_polygon(part, Color(base, alpha))
	else:
		draw_circle(c, r, Color(base, alpha))
	if num > 0:
		draw_circle(c, r * 0.42, Color(1, 1, 1, alpha))
		var fs := int(r * 0.58)
		var s := str(num)
		var w := _semi.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_semi, c + Vector2(-w * 0.5, (_semi.get_ascent(fs) - _semi.get_descent(fs)) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.08, 0.1, alpha))
	# shade and shine
	draw_arc(c, r * 0.92, 0.15 * PI, 1.05 * PI, 18, Color(0, 0, 0, 0.22 * alpha), r * 0.16, true)
	draw_circle(c + Vector2(-r * 0.36, -r * 0.40), r * 0.20, Color(1, 1, 1, 0.55 * alpha))


## The loading line: thin, with a glow; endless (a bright stretch running along) when progress is unknown.
func _bar(center: Vector2, width: float, col: Color, h := 4.0) -> void:
	var r := Rect2(center - Vector2(width * 0.5, h * 0.5), Vector2(width, h))
	draw_rect(r, Color(1, 1, 1, 0.10))
	if progress >= 0.0:
		draw_rect(Rect2(r.position, Vector2(width * clampf(_shown, 0, 1), h)), col)
	else:
		var k := fmod(t * 0.55, 1.0)
		var seg := width * 0.28
		var x0 := r.position.x + (width + seg) * k - seg
		var a := maxf(x0, r.position.x)
		var b := minf(x0 + seg, r.end.x)
		if b > a:
			draw_rect(Rect2(Vector2(a, r.position.y - 1), Vector2(b - a, h + 2)), Color(col, 0.35))
			draw_rect(Rect2(Vector2(a, r.position.y), Vector2(b - a, h)), col)


# ======================================================================== 0 Vortex
func _draw_vortex() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.36)
	var grow := _in(0.0, 0.9)
	var rings := [[165.0, 0.55, 230.0, 7.0, 0.85], [200.0, -0.35, 280.0, 5.0, 0.55], [235.0, 0.25, 200.0, 4.0, 0.35], [270.0, -0.18, 150.0, 3.0, 0.22]]
	for i in rings.size():
		var rg: Array = rings[i]
		var rr: float = rg[0] * (0.6 + 0.4 * grow)
		var a0: float = t * rg[1] * 2.2 + i * 1.3
		var span: float = deg_to_rad(rg[2]) * _in(0.1 + i * 0.12, 0.8)
		if span > 0.01:
			draw_arc(c, rr, a0, a0 + span, 72, Color(UIKit.EMERALD, rg[4] * 0.35), rg[3] * 3.0, true)
			draw_arc(c, rr, a0, a0 + span, 72, Color(UIKit.EMERALD, rg[4]), rg[3], true)
	# the gem, breathing, with light crossing it now and then
	var pulse := 1.0 + 0.025 * sin(t * 2.4)
	var sh := fmod(t, 2.8) / 1.1
	_gem(c, 215.0 * grow * pulse, grow, sh if sh <= 1.0 else -1.0)
	# a cue ball circling
	var ang := t * 1.6
	var bp := c + Vector2(cos(ang) * 235.0, sin(ang) * 235.0 * 0.92) * (0.6 + 0.4 * grow)
	if grow > 0.5:
		_ball(bp, 22.0, 0, _in(0.5, 0.4))
	var a1 := _in(0.6, 0.6)
	_text(_bold, 104, title, Vector2(w * 0.5, h * 0.705 + (1.0 - a1) * 18.0), Color(UIKit.TEXT, a1), 6.0)
	var a2 := _in(0.95, 0.6)
	_text(_semi, 34, SUBTITLE, Vector2(w * 0.5, h * 0.785), Color(UIKit.EMERALD, a2), 16.0)
	var a3 := _in(0.3, 0.8)
	_text(_med, 24, STUDIO, Vector2(w * 0.5, h * 0.885), Color(UIKit.MUTED, a3), 9.0)
	_bar(Vector2(w * 0.5, h * 0.93), 340.0, UIKit.EMERALD)


# ======================================================================== 1 Break
const _RACK_R := 30.0


func _rack() -> void:
	_balls.clear()
	var apex := Vector2(size.x * 0.60, size.y * 0.42) if size.x > 0 else Vector2(1150, 450)
	var order := [1, 9, 2, 10, 8, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]
	var k := 0
	for row in 5:
		for j in row + 1:
			var p := apex + Vector2(row * _RACK_R * 1.74, (j - row * 0.5) * _RACK_R * 2.02)
			_balls.append([p, Vector2.ZERO, order[k]])
			k += 1
	_cue = {"p": Vector2(apex.x - 620.0, apex.y), "v": Vector2.ZERO}
	_broken = false


func _step_break(dt: float) -> void:
	if _balls.is_empty() or size.x <= 0:
		return
	if t < 0.05 and absf((_balls[0][0] as Vector2).x - size.x * 0.60) > 1.0:
		_rack()       # (the size is known now)
	var apex: Vector2 = _balls[0][0]
	if not _broken:
		# the stick draws back, then strikes; the cue ball runs into the apex ball
		if t > 0.75:
			_cue["v"] = Vector2(2600.0, 0.0)
		_cue["p"] += _cue["v"] * dt
		if (_cue["p"] as Vector2).x >= apex.x - _RACK_R * 2.0 and t > 0.75:
			_broken = true
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var center := apex + Vector2(_RACK_R * 3.5, 0)
			for b in _balls:
				var d: Vector2 = (b[0] as Vector2) - center + Vector2(-_RACK_R * 2.5, 0)
				var dir := d.normalized() if d.length() > 1.0 else Vector2.RIGHT
				dir = dir.rotated(rng.randf_range(-0.5, 0.5))
				b[1] = (dir + Vector2(0.55, 0)).normalized() * rng.randf_range(700.0, 1500.0)
			_cue["v"] = Vector2(260.0, -60.0)
		return
	var lo := Vector2(90, 90)
	var hi := size - Vector2(90, 90)
	var all := _balls.duplicate()
	all.append([_cue["p"], _cue["v"], 0])
	for b in all:
		var p: Vector2 = b[0]
		var v: Vector2 = b[1]
		p += v * dt
		v *= exp(-0.95 * dt)
		if p.x < lo.x or p.x > hi.x:
			v.x = -v.x * 0.8
			p.x = clampf(p.x, lo.x, hi.x)
		if p.y < lo.y or p.y > hi.y:
			v.y = -v.y * 0.8
			p.y = clampf(p.y, lo.y, hi.y)
		b[0] = p
		b[1] = v
	# the balls knock into each other
	for i in all.size():
		for j in range(i + 1, all.size()):
			var d: Vector2 = all[j][0] - all[i][0]
			var dist := d.length()
			if dist < _RACK_R * 2.0 and dist > 0.01:
				var nrm := d / dist
				var push := (_RACK_R * 2.0 - dist) * 0.5
				all[i][0] -= nrm * push
				all[j][0] += nrm * push
				var rel: float = (all[i][1] - all[j][1]).dot(nrm)
				if rel > 0.0:
					all[i][1] -= nrm * rel * 0.95
					all[j][1] += nrm * rel * 0.95
	_cue["p"] = all[all.size() - 1][0]
	_cue["v"] = all[all.size() - 1][1]


func _draw_break() -> void:
	var w := size.x
	var h := size.y
	# the cloth's nap: faint diagonal lines
	for i in 40:
		var x := -h + i * (w + h) / 40.0
		draw_line(Vector2(x, 0), Vector2(x + h, h), Color(1, 1, 1, 0.012), 2.0)
	if not _broken:
		var cp: Vector2 = _cue["p"]
		var draw_back := 0.0
		if t < 0.75:
			draw_back = 60.0 * _in(0.15, 0.5)
		var tip := cp - Vector2(_RACK_R + 6.0 + draw_back, 0)
		draw_line(tip - Vector2(760, 0), tip, Color("7a4a24"), 16.0, true)
		draw_line(tip - Vector2(120, 0), tip, Color("e9d8b8"), 12.0, true)
		draw_line(tip - Vector2(10, 0), tip, Color("3e6fb5"), 12.0, true)
	for b in _balls:
		_ball(b[0], _RACK_R, b[2])
	_ball(_cue["p"], _RACK_R, 0)
	# the title, once the balls are on their way
	var a := _in(1.25, 0.6)
	if a > 0.0:
		# a soft dark band behind the title, fading out at its edges
		draw_texture_rect(_band_tex, Rect2(0, h * 0.25, w, h * 0.44), false, Color(1, 1, 1, a))
		_text(_bold, 112, title, Vector2(w * 0.5 + 4, h * 0.42 + 5), Color(0, 0, 0, 0.45 * a), 6.0)
		_text(_bold, 112, title, Vector2(w * 0.5, h * 0.42 + (1.0 - a) * 16.0), Color(UIKit.TEXT, a), 6.0)
		_text(_semi, 36, SUBTITLE, Vector2(w * 0.5, h * 0.535), Color(UIKit.GOLD, _in(1.55, 0.5)), 18.0)
	_text(_med, 24, STUDIO, Vector2(w * 0.5, h * 0.885), Color(1, 1, 1, 0.62 * _in(0.2, 0.8)), 9.0)
	_bar(Vector2(w * 0.5, h * 0.93), 340.0, UIKit.GOLD)


# ======================================================================== 2 Neon
func _neon_path(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for cn in corners:
		for k in 9:
			pts.append((cn[0] as Vector2) + Vector2.from_angle(float(cn[1]) + PI * 0.5 * k / 8.0) * rad)
	pts.append(pts[0])
	return pts


func _partial(pts: PackedVector2Array, f: float) -> PackedVector2Array:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := total * clampf(f, 0.0, 1.0)
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= want:
			out.append(pts[i].lerp(pts[i + 1], (want - acc) / maxf(seg, 0.001)))
			return out
		out.append(pts[i + 1])
		acc += seg
	return out


func _neon_line(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(col, 0.07), 26.0, true)
	draw_polyline(pts, Color(col, 0.16), 13.0, true)
	draw_polyline(pts, Color(col, 0.9), 4.0, true)
	draw_polyline(pts, Color(1, 1, 1, 0.7), 1.5, true)


func _draw_neon() -> void:
	var w := size.x
	var h := size.y
	var pink := Color("ff3fa4")
	var cyan := Color("39e6ff")
	var tbl := Rect2(w * 0.5 - 600, h * 0.13, 1200, 560)
	var f := _in(0.1, 1.3)
	_neon_line(_partial(_neon_path(tbl, 46.0), f), UIKit.EMERALD)
	_neon_line(_partial(_neon_path(tbl.grow(-34), 26.0), _in(0.35, 1.2)), Color(UIKit.EMERALD, 0.6))
	var pockets := [tbl.position, Vector2(tbl.get_center().x, tbl.position.y - 6), Vector2(tbl.end.x, tbl.position.y),
		tbl.end, Vector2(tbl.get_center().x, tbl.end.y + 6), Vector2(tbl.position.x, tbl.end.y)]
	for i in pockets.size():
		var pa := _in(0.5 + i * 0.12, 0.25)
		if pa > 0.0:
			var pc: Vector2 = pockets[i] + ((tbl.get_center() - pockets[i]).normalized() * 18.0)
			draw_circle(pc, 30.0 * pa, Color(cyan, 0.10))
			draw_arc(pc, 22.0 * pa, 0, TAU, 32, Color(cyan, 0.9), 3.0, true)
	# the title flickers on like a neon sign, then holds
	var on := 1.0
	if t < 1.35:
		on = 0.0
	elif t < 2.0:
		var seq := [1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1]
		on = float(seq[int((t - 1.35) * 20.0) % seq.size()])
	else:
		on = 0.92 + 0.08 * sin(t * 13.0) * sin(t * 3.1)
	if on > 0.0:
		_glow_text(_bold, 108, title, Vector2(w * 0.5, h * 0.355), Color(1, 0.94, 0.98, on), Color(pink, on), 6.0)
		_glow_text(_semi, 36, SUBTITLE, Vector2(w * 0.5, h * 0.455), Color(0.9, 1, 1, on * _in(1.6, 0.4)), Color(cyan, on * _in(1.6, 0.4)), 18.0)
	# two neon balls rolling slowly on the table
	for i in 2:
		var ba := _in(1.0 + i * 0.3, 0.5)
		if ba > 0.0:
			var bp := tbl.get_center() + Vector2(sin(t * 0.7 + i * 2.0) * 420.0, 175.0 + cos(t * 0.5 + i * 1.3) * 40.0)
			draw_circle(bp, 26.0, Color([cyan, pink][i], 0.12 * ba))
			draw_arc(bp, 18.0, 0, TAU, 32, Color([cyan, pink][i], ba), 3.0, true)
	_text(_med, 24, STUDIO, Vector2(w * 0.5, h * 0.885), Color(0.85, 0.8, 1.0, 0.7 * _in(0.3, 0.8)), 9.0)
	var bar_c := Vector2(w * 0.5, h * 0.93)
	_neon_line(PackedVector2Array([bar_c - Vector2(170, 0), bar_c + Vector2(170, 0)]), Color(pink, 0.25))
	var k := fmod(t * 0.5, 1.0) if progress < 0.0 else clampf(_shown, 0, 1)
	if progress < 0.0:
		var x0 := -170.0 + 340.0 * k
		_neon_line(PackedVector2Array([bar_c + Vector2(maxf(-170.0, x0 - 70.0), 0), bar_c + Vector2(minf(170.0, x0 + 20.0), 0)]), pink)
	else:
		_neon_line(PackedVector2Array([bar_c - Vector2(170, 0), bar_c + Vector2(-170.0 + 340.0 * k, 0)]), pink)


# ======================================================================== 3 AR scan
func _draw_scan() -> void:
	var w := size.x
	var h := size.y
	var vp := Vector2(w * 0.5, h * 0.30)
	var horizon := h * 0.42
	var col := UIKit.EMERALD
	var ga := _in(0.0, 0.8)
	# the floor grid: lines to the vanishing point, and cross lines coming closer
	for i in range(-12, 13):
		var bottom := Vector2(w * 0.5 + i * 170.0, h)
		var a := vp.lerp(bottom, (horizon - vp.y) / (h - vp.y))
		draw_line(a, bottom, Color(col, 0.10 * ga), 1.5, true)
	var scroll := fmod(t * 0.35, 1.0)
	for j in 14:
		var z := (j + scroll) / 14.0
		var y := horizon + (h - horizon) * z * z
		draw_line(Vector2(0, y), Vector2(w, y), Color(col, 0.10 * ga * z), 1.5, true)
	# a scanning band
	var sy := horizon + fmod(t * 0.45, 1.0) * (h - horizon)
	draw_rect(Rect2(0, sy - 22, w, 44), Color(col, 0.05))
	draw_line(Vector2(0, sy), Vector2(w, sy), Color(col, 0.35), 2.0)
	# the table appears on the floor
	var ta := _in(0.9, 0.7)
	var tc := Vector2(w * 0.5, h * 0.66)
	var top := PackedVector2Array([tc + Vector2(-250, -70), tc + Vector2(250, -70), tc + Vector2(330, 95), tc + Vector2(-330, 95)])
	if ta > 0.0:
		var sc := 0.9 + 0.1 * ta
		var tp := PackedVector2Array()
		for p in top:
			tp.append(tc + (p - tc) * sc)
		var rail := PackedVector2Array([tp[0] + Vector2(-26, -14), tp[1] + Vector2(26, -14), tp[2] + Vector2(34, 20), tp[3] + Vector2(-34, 20)])
		draw_colored_polygon(rail, Color(0.22, 0.13, 0.08, 0.9 * ta))
		draw_colored_polygon(tp, Color(0.07, 0.45, 0.32, 0.95 * ta))
		draw_polyline(PackedVector2Array([tp[0], tp[1], tp[2], tp[3], tp[0]]), Color(col, 0.8 * ta), 2.0, true)
		for p in [tp[0], tp[1], tp[2], tp[3], (tp[0] + tp[1]) * 0.5, (tp[2] + tp[3]) * 0.5]:
			draw_circle(p, 9.0 * sc, Color(0, 0, 0, 0.8 * ta))
		for i in 3:
			_ball(tc + Vector2(-60 + i * 50, 10 + (i % 2) * 18) * sc, 12.0 * sc, [0, 8, 3][i], ta)
	# corner brackets close in from the screen's corners and lock onto it
	var lock := _in(0.3, 1.0)
	var box := Rect2(tc - Vector2(380, 150), Vector2(760, 300))
	var far := Rect2(Vector2(60, 60), size - Vector2(120, 120))
	var bx := Rect2(far.position.lerp(box.position, lock), far.size.lerp(box.size, lock))
	var pulse := 1.0 + (0.04 * sin(t * 5.0) if lock >= 1.0 else 0.0)
	bx = bx.grow((pulse - 1.0) * 120.0)
	var L := 58.0
	var bc := Color(col, 0.95)
	for cn in [[bx.position, Vector2(1, 1)], [Vector2(bx.end.x, bx.position.y), Vector2(-1, 1)], [bx.end, Vector2(-1, -1)], [Vector2(bx.position.x, bx.end.y), Vector2(1, -1)]]:
		var p: Vector2 = cn[0]
		var d: Vector2 = cn[1]
		draw_line(p, p + Vector2(L * d.x, 0), bc, 5.0, true)
		draw_line(p, p + Vector2(0, L * d.y), bc, 5.0, true)
	var a1 := _in(0.5, 0.6)
	_text(_bold, 96, title, Vector2(w * 0.5, h * 0.16 + (1.0 - a1) * 14.0), Color(UIKit.TEXT, a1), 6.0)
	_text(_semi, 34, SUBTITLE, Vector2(w * 0.5, h * 0.245), Color(col, _in(0.8, 0.5)), 18.0)
	var caret := "_" if fmod(t, 0.9) < 0.5 else " "
	var pct := "" if progress < 0.0 else "  %d%%" % int(_shown * 100.0)
	_text(_semi, 28, status + pct + caret, Vector2(w * 0.5, h * 0.905), Color(col, 0.9 * _in(0.2, 0.5)), 2.0)
	_text(_med, 22, STUDIO, Vector2(w * 0.5, h * 0.955), Color(UIKit.MUTED, 0.8 * _in(0.3, 0.8)), 8.0)


# ======================================================================== 4 Studio
func _draw_studio() -> void:
	var w := size.x
	var h := size.y
	# first the studio: its gem and name, then they make way for the game
	var s_in := _in(0.1, 0.6)
	var s_out := _in(1.6, 0.5)
	var sa := s_in * (1.0 - s_out)
	if sa > 0.0:
		_gem(Vector2(w * 0.5, h * 0.40), 150.0 * (0.92 + 0.08 * s_in), sa, fmod(t * 0.8, 1.6) / 1.0 if fmod(t * 0.8, 1.6) <= 1.0 else -1.0)
		_text(_semi, 40, STUDIO, Vector2(w * 0.5, h * 0.60), Color(UIKit.TEXT, sa), 14.0 + 6.0 * (1.0 - s_in))
	var g_in := _in(1.9, 0.7)
	if g_in > 0.0:
		var sweep := -400.0 + fmod(maxf(0.0, t - 2.2) * 700.0, w + 1200.0)
		var shimmer := func(x: float, base: Color) -> Color:
			var k := exp(-pow((x - sweep) / 90.0, 2.0))
			return base.lerp(Color(1.0, 0.86, 0.45, base.a), k)
		_text(_bold, 122, title, Vector2(w * 0.5, h * 0.40 + (1.0 - g_in) * 20.0), Color(UIKit.TEXT, g_in), 8.0, shimmer)
		var lw := 520.0 * _in(2.2, 0.6)
		draw_line(Vector2(w * 0.5 - lw * 0.5, h * 0.495), Vector2(w * 0.5 + lw * 0.5, h * 0.495), Color(UIKit.GOLD, 0.8), 2.0)
		_text(_semi, 36, SUBTITLE, Vector2(w * 0.5, h * 0.555), Color(UIKit.EMERALD, _in(2.4, 0.5)), 20.0)
		_text(_med, 22, STUDIO, Vector2(w * 0.5, h * 0.92), Color(UIKit.MUTED, 0.8 * _in(2.6, 0.6)), 9.0)
	# eight balls bounce in a wave while the game loads
	var ba := maxf(_in(0.4, 0.5) * (1.0 - s_out * 0.0), 0.0)
	for i in 8:
		var x := w * 0.5 + (i - 3.5) * 58.0
		var y := h * 0.78 - absf(sin(t * 4.0 - i * 0.45)) * 26.0
		_ball(Vector2(x, y), 17.0, i + 1, ba)
