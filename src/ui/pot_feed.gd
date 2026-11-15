class_name PotFeed
extends Control
## v1.1.5 (Randy: "a nicely stylized popup lasting 2 seconds for each ball made in, stacking on each other so
## players know which balls were made in & also stacking, when it's decided, whether they are stripes or solids").
##
## A column on the left, under the player card. Every ball that drops adds a card at the bottom of the column:
## the ball itself (its number, solid or striped, in the colours of the ball set on the table), "3 ball", its group
## and who potted it. The cue ball shows as "Scratch!". When the table stops being open, a taller card says who is
## on solids and who is on stripes. Each card slides in, stays 2 seconds, fades, and the cards below close up.
## Both players see every card (they say what happened on the table; praise stays with the shooter).

const LIFE := 2.0
const MAX_CARDS := 6
const CLASSIC := ["f5c518", "1d4ed8", "dc2626", "6d28d9", "f97316", "15803d", "7f1d1d", "111216"]

var ball_set := "balls"
var max_height := 440.0           # the room under the player card (the HUD sets it); the oldest cards make way
var _col: VBoxContainer
static var test_hold := false      # (pictures in the automated tests: the cards stay until cleared)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 8)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_col)


## The colours of ball `n` (0 = cue ball) in the ball set on the table: [body, colour, number disc, ink].
func colours(n: int) -> Array:
	var e: Dictionary = Catalog.ball_set(ball_set)
	if e.has("pal"):
		var pal: Array = e["pal"]
		var c := Color(str(e.get("accent", "17b57d"))) if n == 0 else Color(str(pal[(n if n <= 8 else n - 8) - 1]))
		var body := Color(str(e.get("cue", e.get("base", "f6f4ec")))) if n == 0 else Color(str(e.get("base", "f6f4ec")))
		var ink := str(e.get("ink", "121216"))
		return [body, c, Color(str(e.get("disc", "f8f6f0"))), c if ink == "col" else Color(ink)]
	if n == 0:
		return [Color("f6f4ec"), Color("f6f4ec"), Color("f6f4ec"), Color("121216")]
	return [Color("f6f4ec"), Color(CLASSIC[(n if n <= 8 else n - 8) - 1]), Color("f8f6f0"), Color("121216")]


## A ball dropped. `who`: the shooter's name ("" in Practice); `who_col`: their colour.
## One line, as a game's kill feed: the ball, "3 ball", then its group and who potted it in a quieter colour.
func add_ball(n: int, who := "", who_col := UIKit.EMERALD) -> void:
	var cols := colours(n)
	var accent: Color = cols[1] if n != 0 else UIKit.CORAL
	if n == 8:
		accent = Color("d9dde3")
	var card := _card(accent)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(BallBadge.new(n, cols, 40.0))
	# the cue ball: "Scratch!" (in several languages that word already says "cue ball in", so it stands alone)
	var title := _label(L.t("Scratch!") if n == 0 else (L.t("%d ball") % n), 24, 700, UIKit.CORAL if n == 0 else UIKit.TEXT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# a long word (Tamil's "Scratch!" is "cue ball in the pocket!") gets slightly smaller letters, never a wide card
	var tw := title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	if tw > 280.0:
		title.add_theme_font_size_override("font_size", maxi(17, int(floor(24.0 * 280.0 / tw))))
	row.add_child(title)
	var sub_parts: Array = []
	var sub_col := who_col.lerp(UIKit.MUTED, 0.35) if who != "" else UIKit.MUTED
	if n != 0 and n != 8:
		sub_parts.append(L.t("Solids") if n < 8 else L.t("Stripes"))
	if who != "":
		sub_parts.append(who)
	if not sub_parts.is_empty():
		var sub := _label(" · ".join(sub_parts), 18, 600, sub_col)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.clip_text = true
		sub.custom_minimum_size.x = minf(sub.get_theme_font("font").get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 4.0, 300.0)
		row.add_child(sub)
	_push(card, LIFE)


## The table is no longer open: who plays which group. `rows`: [[name, group (EightBall.Group), colour], ...]
func add_groups(rows: Array) -> void:
	var card := _card(UIKit.GOLD)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(_label(L.up(L.t("Groups are set")), 17, 800, UIKit.GOLD))
	for r in rows:
		var g: int = r[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		var sample := 1 if g == EightBall.Group.SOLIDS else 9
		row.add_child(BallBadge.new(sample, colours(sample), 34.0))
		var nm := _label(str(r[0]), 22, 700, r[2])
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # a player's name
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true      # a very long name is cut; anything up to 240 px shows whole
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size.x = minf(nm.get_theme_font("font").get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 4.0, 240.0)
		row.add_child(nm)
		var gl := _label(L.t("Solids") if g == EightBall.Group.SOLIDS else L.t("Stripes"), 22, 700, UIKit.TEXT)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(gl)
	_push(card, LIFE)


func _stack_height() -> float:
	var h := 0.0
	for c in _col.get_children():
		h += (c as Control).custom_minimum_size.y + 8.0
	return h - 8.0


## Every card away at once (tests).
func clear() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()


## How many cards are showing (tests).
func count() -> int:
	var k := 0
	for c in _col.get_children():
		if not c.is_queued_for_deletion():
			k += 1
	return k


func _card(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# dark glass, with the left edge in the ball's colour
	var sb := UIKit.box(Color(0.025, 0.04, 0.075, 0.88), 18, 0, accent, Vector4(16, 6, 22, 6), 10)
	sb.border_width_left = 6
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(300, 0)
	return p


func _label(text: String, size: int, weight: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # already translated
	l.add_theme_font_override("font", UIKit.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## In at the bottom of the column: slide in from the left, stay, fade and slide out, then the space closes up.
func _push(card: PanelContainer, life: float) -> void:
	# a slot that holds the card's place in the column, so the card itself can slide sideways freely
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	slot.clip_contents = false
	_col.add_child(slot)
	card.reset_size()
	var h := card.get_combined_minimum_size().y
	var w := maxf(card.get_combined_minimum_size().x, 300.0)
	card.size = Vector2(w, h)
	slot.custom_minimum_size = Vector2(w, h)
	# no more than fits: the oldest make way
	while _col.get_child_count() > 1 and (_col.get_child_count() > MAX_CARDS or _stack_height() > max_height):
		var old := _col.get_child(0)
		_col.remove_child(old)
		old.queue_free()
	card.position.x = -w - 40.0
	card.modulate.a = 0.0
	var reduced := bool(Game.get_s("reduced_motion"))
	if test_hold:
		card.position.x = 0.0
		card.modulate.a = 1.0
		return
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position:x", 0.0, 0.01 if reduced else 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.16)
	tw.chain().tween_interval(maxf(life - 0.28 - 0.32, 0.1))
	tw.chain().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.32)
	tw.tween_property(card, "position:x", -30.0, 0.32)
	tw.chain().tween_property(slot, "custom_minimum_size:y", 0.0, 0.01 if reduced else 0.18)
	tw.chain().tween_callback(slot.queue_free)


## A ball drawn flat: solid, or white with a coloured band; the number on a white disc; a soft highlight.
class BallBadge:
	extends Control
	var n := 1
	var cols: Array = []
	var d := 46.0

	func _init(p_n: int, p_cols: Array, p_d: float) -> void:
		n = p_n
		cols = p_cols
		d = p_d
		custom_minimum_size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(d, d) * 0.5
		var r := d * 0.5
		var body: Color = cols[0]
		var col: Color = cols[1]
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		if n == 0:
			draw_circle(c, r, body)
		elif n <= 8:
			draw_circle(c, r, col)
		else:
			draw_circle(c, r, body)
			# the band: the middle of the circle between two chords
			var band := r * 0.56
			var poly := PackedVector2Array()
			# right arc (top to bottom), then left arc (bottom to top)
			for k in 25:
				var a := lerpf(-asin(band / r), asin(band / r), k / 24.0)
				poly.append(c + Vector2(cos(a) * r, sin(a) * r))
			for k in 25:
				var a := lerpf(PI - asin(band / r), PI + asin(band / r), k / 24.0)
				poly.append(c + Vector2(cos(a) * r, sin(a) * r))
			draw_colored_polygon(poly, col)
		if n > 0:
			draw_circle(c, r * 0.47, cols[2])
			var f := UIKit.font(800)
			var fs := int(d * (0.42 if n < 10 else 0.36))
			var txt := str(n)
			var tsz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, c + Vector2(-tsz.x * 0.5, tsz.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[3])
		# a soft highlight up and to the left, and a thin edge
		draw_circle(c + Vector2(-r * 0.36, -r * 0.4), r * 0.22, Color(1, 1, 1, 0.22))
		draw_arc(c, r - 0.5, 0, TAU, 48, Color(0, 0, 0, 0.35), 1.0, true)
