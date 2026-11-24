class_name GradientBox
extends StyleBox
## A rounded box filled top to bottom with a gradient, with an outline and a soft glow round it: the Ready button
## (Randy, 24 Nov 2026: "a green ready up button with a lighter green gradient to light green outline around the
## button"). StyleBoxFlat has no gradient, so this one draws its own: one rounded polygon with a colour at each
## point, an anti-aliased outline over its edge, and two faint wider outlines for the glow.

@export var top := Color("8dffd2")
@export var bottom := Color("12b97c")
@export var border_color := Color("c8ffe6")
@export var border := 3.0
@export var radius := 30.0
@export var glow := 0.22          # strength of the glow outside the outline (0: none)


static func make(p_top: Color, p_bottom: Color, p_border_color: Color, p_border := 3.0, p_radius := 30.0, p_glow := 0.22,
		pad := Vector4(44, 20, 44, 20)) -> GradientBox:
	var s := GradientBox.new()
	s.top = p_top
	s.bottom = p_bottom
	s.border_color = p_border_color
	s.border = p_border
	s.radius = p_radius
	s.glow = p_glow
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


## The outline of a rounded rectangle, clockwise from the top left corner's start.
static func outline(rect: Rect2, r: float, steps := 10) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
	]
	for c in corners:
		for i in steps + 1:
			var a: float = float(c[1]) + PI * 0.5 * float(i) / float(steps)
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if glow > 0.0:
		for k in [[7.0, 0.35], [3.5, 0.7]]:
			var g := outline(rect.grow(float(k[0]) * 0.5 + border * 0.5), radius + float(k[0]) * 0.5)
			g.append(g[0])
			var gc := border_color
			gc.a *= glow * float(k[1])
			rs.canvas_item_add_polyline(to_canvas_item, g, PackedColorArray([gc]), float(k[0]), true)
	var pts := outline(rect, radius)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
	rs.canvas_item_add_polygon(to_canvas_item, pts, cols)
	# a light band along the top half: the gradient reads as lit from above
	var shine := outline(Rect2(rect.position + Vector2(border + 4, border + 2), Vector2(rect.size.x - 2 * (border + 4), rect.size.y * 0.42)), maxf(radius - border - 4, 2.0))
	var sc := PackedColorArray()
	for p in shine:
		var f := clampf((p.y - rect.position.y) / maxf(rect.size.y * 0.45, 1.0), 0.0, 1.0)
		sc.append(Color(1, 1, 1, 0.16 * (1.0 - f)))
	rs.canvas_item_add_polygon(to_canvas_item, shine, sc)
	if border > 0.0:
		var o := outline(rect.grow(-border * 0.5), radius - border * 0.5)
		o.append(o[0])
		rs.canvas_item_add_polyline(to_canvas_item, o, PackedColorArray([border_color]), border, true)
