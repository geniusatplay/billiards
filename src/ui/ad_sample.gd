class_name AdSample
extends Control
## A sample advert, laid out the way full-screen mobile game adverts are, for previewing how the game's adverts will
## look before real ones are switched on (v1.1.15, Randy, 21 Nov: "please create an apk version which lets me preview
## how the ads will look (with a fake ad showing in place of what the actual ads will look like so I can preview how
## it will look)").
##   between matches ("after_match"): an interstitial: the advert picture on the left, the advertised game's card on
##     the right (icon, name, stars, Install), "Ad" in the corner, and the close button after a 5-second countdown;
##   XP chest / package (rewarded): a 15-second "video" with "Reward in 15 s" counting down, a close button that asks
##     "Close video? You will lose your reward." before the reward is earned, and "Reward granted" after.
## The two advertised games (Lumen Lagoon, Turbo Orbit) and their studio are made up; a line along the bottom says it is
## a sample. Shown by Ads instead of the plain stand-in in the advert-preview build (export feature "adpreview",
## `tools/build_apk.py --adpreview`) or with Developer tools → "Stand-ins look like real adverts"; never in a store
## build. English only: a real advert comes in the advertiser's own words, and its close / reward words come from the
## advert SDK, not from the game.

## true: the reward was earned (or, for an interstitial, the advert was simply closed); false: closed early.
signal finished(earned: bool)

const INTER_CLOSE_AFTER := 5.0       # seconds before an interstitial can be closed
const REWARD_AFTER := 15.0           # seconds of "video" before the reward is earned
const CLOSE_SHOWS_AFTER := 3.0       # a rewarded advert's close button (with its warning) appears after this
const BLUE := Color(0.18, 0.5, 0.98)
const INK := Color(0.1, 0.11, 0.13)
const GREY := Color(0.42, 0.44, 0.48)

var rewarded := false
var granted := false
var t := 0.0
var _paused := false
var _ad := {}
var _close: Button
var _count: Label
var _pill: Label
var _pill_box: PanelContainer
var _bar: ColorRect
var _bar_back: ColorRect
var _dialog: Control
var _note: Label
var _frame: Control          # everything but the black background, inside the screen's safe area

const ADS := {
	"lagoon": {"name": "Lumen Lagoon", "line": "Match the glowing pearls!", "studio": "Sample Studio", "stars": 4.6,
		"reviews": "12K", "c1": Color(0.07, 0.75, 0.86), "c2": Color(0.47, 0.2, 0.75)},
	"orbit": {"name": "Turbo Orbit", "line": "Race through the rings!", "studio": "Sample Studio", "stars": 4.4,
		"reviews": "8K", "c1": Color(1.0, 0.55, 0.15), "c2": Color(0.85, 0.15, 0.45)},
}


func _init(p_rewarded := false) -> void:
	rewarded = p_rewarded
	_ad = ADS["orbit" if rewarded else "lagoon"]
	name = "AdSample"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fullrect(bg)
	add_child(bg)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fullrect(_frame)
	add_child(_frame)
	if rewarded:
		_build_rewarded()
	else:
		_build_interstitial()
	# the close button (the countdown in it first, for an interstitial)
	_close = Button.new()
	_close.name = "AdClose"
	_close.focus_mode = Control.FOCUS_NONE
	_close.custom_minimum_size = Vector2(76, 76)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		_close.add_theme_stylebox_override(st, UIKit.box(Color(0, 0, 0, 0.55), 38, 2, Color(1, 1, 1, 0.5), Vector4(0, 0, 0, 0)))
	_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_close.offset_left = -110
	_close.offset_right = -34
	_close.offset_top = 24
	_close.offset_bottom = 100
	var x := IconGlyph.make("close", 34, Color.WHITE)
	x.name = "AdCloseX"
	x.position = Vector2(21, 21)
	_close.add_child(x)
	_count = Label.new()
	_count.name = "AdCount"
	_count.add_theme_font_override("font", UIKit.font(700))
	_count.add_theme_font_size_override("font_size", 32)
	_count.add_theme_color_override("font_color", Color.WHITE)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.add_child(_count)
	_close.pressed.connect(_on_close)
	_frame.add_child(_close)
	# the line that says what this is
	var nb := PanelContainer.new()
	nb.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.72), 14, 0, Color.WHITE, Vector4(18, 4, 18, 4)))
	nb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	nb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	nb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	nb.offset_bottom = -6
	nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note = _text("Sample advert for previewing: the game in it is made up. Real adverts come from AdMob and will differ.",
		20, Color(1, 1, 1, 0.7), 500)
	_note.name = "AdNote"
	nb.add_child(_note)
	_frame.add_child(nb)
	_tick(0.0)


func _ready() -> void:
	# inside the screen's safe area (a notch or a rounded corner never hides the close button)
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x > 0 and win.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		var k := get_viewport().get_visible_rect().size / Vector2(win)
		_frame.offset_left = maxf(0.0, safe.position.x) * k.x
		_frame.offset_top = maxf(0.0, safe.position.y) * k.y
		_frame.offset_right = -maxf(0.0, win.x - safe.end.x) * k.x
		_frame.offset_bottom = -maxf(0.0, win.y - safe.end.y) * k.y


# ------------------------------------------------------------------------------------------------- interstitial
func _build_interstitial() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	UIKit.fullrect(row)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(row)
	# the advert's picture (a short looping "video")
	var pic := Control.new()
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.size_flags_stretch_ratio = 1.7
	pic.clip_contents = true
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var scene := AdScene.new("lagoon")
	UIKit.fullrect(scene)
	pic.add_child(scene)
	_add_ad_badge(pic, Vector2(28, 26))
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.25)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_back.offset_top = -6
	pic.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.82, 0.25)
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(0, 6)
	_bar_back.add_child(_bar)
	# the advertised game's card
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.98, 0.98, 0.99), 0, 0, Color.WHITE, Vector4(44, 40, 44, 50)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var icon := AdIcon.new("lagoon", 168.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var nm := _text(_ad["name"], 46, INK, 800)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var st := _text(_ad["studio"], 26, GREY, 500)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_theme_constant_override("separation", 10)
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sr.add_child(_text("%.1f" % float(_ad["stars"]), 28, INK, 700))
	sr.add_child(AdStars.new(float(_ad["stars"]), 26.0, Color(1.0, 0.72, 0.1)))
	sr.add_child(_text("(%s)  ·  Free" % _ad["reviews"], 26, GREY, 500))
	v.add_child(sr)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	v.add_child(gap)
	v.add_child(_install_button(420.0))


# ------------------------------------------------------------------------------------------------- rewarded
func _build_rewarded() -> void:
	var scene := AdScene.new("orbit")
	UIKit.fullrect(scene)
	_frame.add_child(scene)
	# top left: "Reward in 15 s" (then "Reward granted"), and the sound button a video advert has
	_pill_box = PanelContainer.new()
	_pill_box.name = "AdRewardPill"
	_pill_box.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.6), 30, 0, Color.WHITE, Vector4(26, 12, 26, 12)))
	_pill_box.position = Vector2(34, 30)
	_pill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_pill_box)
	_pill = _text("", 30, Color.WHITE, 700)
	_pill_box.add_child(_pill)
	var snd := PanelContainer.new()
	snd.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.6), 30, 0, Color.WHITE, Vector4(14, 14, 14, 14)))
	snd.position = Vector2(34, 112)
	snd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snd.add_child(IconGlyph.make("sound", 34, Color.WHITE))
	_frame.add_child(snd)
	_add_ad_badge(_frame, Vector2(112, 126))
	# the bottom: the video's progress, then the advertised game's strip
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UIKit.box(Color(0.98, 0.98, 0.99, 0.97), 0, 0, Color.WHITE, Vector4(34, 18, 34, 18)))
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -204
	strip.offset_bottom = -68
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(h)
	var icon := AdIcon.new("orbit", 100.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(_text(_ad["name"], 38, INK, 800))
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sr.add_child(_text("%s  ·  %.1f" % [_ad["studio"], float(_ad["stars"])], 24, GREY, 500))
	sr.add_child(AdStars.new(float(_ad["stars"]), 22.0, Color(1.0, 0.72, 0.1)))
	sr.add_child(_text("·  Free", 24, GREY, 500))
	v.add_child(sr)
	var ib := _install_button(300.0)
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ib)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.25)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_back.offset_top = -210
	_bar_back.offset_bottom = -204
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.82, 0.25)
	_bar.size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar)


## "Close video? You will lose your reward."  CLOSE VIDEO / RESUME VIDEO
func _ask_close() -> void:
	_paused = true
	_dialog = ColorRect.new()
	_dialog.name = "AdCloseDialog"
	(_dialog as ColorRect).color = Color(0, 0, 0, 0.6)
	UIKit.fullrect(_dialog)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialog)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.99, 0.99, 1.0), 18, 0, Color.WHITE, Vector4(44, 36, 30, 22), 18))
	card.custom_minimum_size = Vector2(680, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	v.add_child(_text("Close video?", 38, INK, 800))
	v.add_child(_text("You will lose your reward.", 30, GREY, 500))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	for b in [["CLOSE VIDEO", "AdCloseVideo"], ["RESUME VIDEO", "AdResumeVideo"]]:
		var tb := Button.new()
		tb.text = b[0]
		tb.name = b[1]
		tb.flat = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_override("font", UIKit.font(700))
		tb.add_theme_font_size_override("font_size", 28)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			tb.add_theme_color_override(c, BLUE)
		for stn in ["normal", "hover", "pressed", "focus"]:
			tb.add_theme_stylebox_override(stn, UIKit.box(Color(BLUE, 0.1) if stn == "pressed" else Color(0, 0, 0, 0), 10, 0, Color.WHITE, Vector4(20, 14, 20, 14)))
		row.add_child(tb)
		if b[1] == "AdCloseVideo":
			tb.pressed.connect(func(): _finish(false))
		else:
			tb.pressed.connect(func():
				_dialog.queue_free()
				_dialog = null
				_paused = false)
	v.add_child(row)
	UIKit.center_in(_dialog, card)


func _on_close() -> void:
	if not rewarded:
		if t >= INTER_CLOSE_AFTER:
			_finish(true)
	elif granted:
		_finish(true)
	elif _dialog == null:
		_ask_close()


func _finish(earned: bool) -> void:
	set_process(false)
	finished.emit(earned)


func _process(delta: float) -> void:
	if not _paused:
		_tick(delta)


func _tick(delta: float) -> void:
	t += delta
	if rewarded:
		if not granted and t >= REWARD_AFTER:
			granted = true
			_pill_box.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.62, 0.32, 0.92), 30, 0, Color.WHITE, Vector4(26, 12, 26, 12)))
		_pill.text = "Reward granted" if granted else "Reward in %d s" % ceili(REWARD_AFTER - t)
		_close.visible = t >= CLOSE_SHOWS_AFTER or granted
		_count.visible = false
		if _bar_back.size.x > 0.0:
			_bar.size.x = _bar_back.size.x * clampf(t / REWARD_AFTER, 0.0, 1.0)
	else:
		var left := ceili(INTER_CLOSE_AFTER - t)
		_count.visible = left > 0
		_count.text = str(left)
		(_close.get_node("AdCloseX") as CanvasItem).visible = left <= 0
		_close.disabled = left > 0
		if _bar_back.size.x > 0.0:
			_bar.size.x = _bar_back.size.x * fmod(t / 12.0, 1.0)


func _install_button(w: float) -> Button:
	var b := Button.new()
	b.text = "Install"
	b.name = "AdInstall"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 88)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", UIKit.font(700))
	b.add_theme_font_size_override("font_size", 34)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, UIKit.box(BLUE.darkened(0.15) if st == "pressed" else BLUE, 44, 0, Color.WHITE, Vector4(24, 12, 24, 12)))
	b.pressed.connect(func():
		_note.text = "A real advert would open the game's store page here. (This one is a made-up sample.)")
	return b


func _add_ad_badge(parent: Control, at: Vector2) -> void:
	var badge := PanelContainer.new()
	badge.name = "AdBadge"
	badge.add_theme_stylebox_override("panel", UIKit.box(Color(1.0, 0.8, 0.18), 6, 0, Color.WHITE, Vector4(12, 3, 12, 3)))
	badge.position = at
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_text("Ad", 24, INK, 800))
	parent.add_child(badge)


func _text(s: String, px: int, col: Color, weight: int) -> Label:
	var l := Label.new()
	l.text = s
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", UIKit.font(weight))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ================================================================================================= the pictures
## The advert's moving picture, drawn: a lagoon under a moon with glowing pearls rising, or ships racing through rings
## in space. Each has the made-up game's name and line on it, as a real advert's video would.
class AdScene:
	extends Control
	var kind := "lagoon"
	var tt := 0.0
	var _stars: Array = []

	func _init(p_kind: String) -> void:
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 90:
			_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))

	func _process(delta: float) -> void:
		tt += delta
		queue_redraw()

	func _grad(r: Rect2, top: Color, bottom: Color) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))

	func _glow(at: Vector2, r: float, col: Color) -> void:
		for k in 5:
			draw_circle(at, r * (2.6 - k * 0.35), Color(col, 0.05 + k * 0.03))
		draw_circle(at, r, col)
		draw_circle(at - Vector2(r, r) * 0.3, r * 0.35, Color(1, 1, 1, 0.75))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		if kind == "lagoon":
			var hz := h * 0.58
			_grad(Rect2(0, 0, w, hz * 0.55), Color(0.08, 0.05, 0.25), Color(0.38, 0.16, 0.5))
			_grad(Rect2(0, hz * 0.55, w, hz * 0.45), Color(0.38, 0.16, 0.5), Color(0.98, 0.52, 0.42))
			for st in _stars:
				if st.y < 0.5:
					draw_circle(Vector2(st.x * w, st.y * hz), 1.6 * st.z, Color(1, 1, 1, 0.35 + 0.4 * absf(sin(tt * 2.0 + st.x * 40.0))))
			var moon := Vector2(w * 0.72, h * 0.25)
			for k in 6:
				draw_circle(moon, h * (0.2 - k * 0.022), Color(1.0, 0.95, 0.8, 0.05 + k * 0.02))
			draw_circle(moon, h * 0.085, Color(1.0, 0.96, 0.86))
			# hills on the horizon
			var hill := PackedVector2Array([Vector2(0, hz)])
			for i in 41:
				var x := w * i / 40.0
				hill.append(Vector2(x, hz - h * (0.065 + 0.035 * sin(i * 0.5) + 0.02 * sin(i * 1.7))))     # (always above the water line)
			hill.append(Vector2(w, hz))
			draw_colored_polygon(hill, Color(0.12, 0.06, 0.22))
			_grad(Rect2(0, hz, w, h - hz), Color(0.06, 0.35, 0.5), Color(0.02, 0.1, 0.2))
			for i in 9:
				var yy := hz + 12.0 + i * 16.0
				var half := w * (0.05 + i * 0.012) * (0.8 + 0.2 * sin(tt * 3.0 + i))
				draw_line(Vector2(moon.x - half, yy), Vector2(moon.x + half, yy), Color(1.0, 0.92, 0.75, 0.35 - i * 0.03), 3.0)
			var cols := [Color(0.3, 0.95, 1.0), Color(1.0, 0.45, 0.8), Color(1.0, 0.85, 0.3), Color(0.55, 1.0, 0.6)]
			for i in 16:
				var sp := 0.06 + 0.03 * float(i % 4)
				var ph := fmod(tt * sp + i * 0.137, 1.0)
				var p := Vector2(w * (0.06 + 0.88 * fmod(i * 0.381, 1.0)) + sin(tt * 1.3 + i) * 14.0, h * (1.05 - ph * 0.62))
				_glow(p, h * (0.022 + 0.008 * float(i % 3)), cols[i % 4])
			_title(w, h)
		else:
			_grad(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.1), Color(0.12, 0.07, 0.3))
			for st in _stars:
				var x := fposmod(st.x * w - tt * 260.0 * st.z, w)
				draw_line(Vector2(x, st.y * h), Vector2(x + 18.0 * st.z, st.y * h), Color(1, 1, 1, 0.3 + 0.5 * st.z), 2.0 * st.z)
			var planet := Vector2(w * 0.84, h * 0.92)
			draw_circle(planet, h * 0.42, Color(0.2, 0.32, 0.85))
			draw_circle(planet + Vector2(-h * 0.08, -h * 0.1), h * 0.3, Color(0.32, 0.46, 0.95, 0.6))
			draw_set_transform(planet, -0.25, Vector2(1.0, 0.28))
			draw_arc(Vector2.ZERO, h * 0.62, 0, TAU, 72, Color(1.0, 0.8, 0.5, 0.7), 10.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# rings to fly through
			for i in 3:
				var rx := fposmod(w * (1.2 + i * 0.45) - tt * 300.0, w * 1.35) - w * 0.1
				var ry := h * (0.38 + 0.12 * sin(i * 2.1 + tt * 0.5))
				draw_set_transform(Vector2(rx, ry), 0.0, Vector2(0.45, 1.0))
				for k in 3:
					draw_arc(Vector2.ZERO, h * 0.13, 0, TAU, 48, Color(1.0, 0.85, 0.25, 0.25 + k * 0.25), 14.0 - k * 4.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# the ship, bobbing, with its flame
			var sh := Vector2(w * 0.5, h * (0.55 + 0.06 * sin(tt * 2.2)))
			var sz := h * 0.07
			var fl := sz * (1.4 + 0.4 * sin(tt * 30.0))
			draw_colored_polygon(PackedVector2Array([sh + Vector2(-sz * 1.2, -sz * 0.35), sh + Vector2(-sz * 1.2 - fl, 0), sh + Vector2(-sz * 1.2, sz * 0.35)]), Color(1.0, 0.55, 0.15))
			draw_colored_polygon(PackedVector2Array([sh + Vector2(sz * 1.6, 0), sh + Vector2(-sz * 1.2, -sz * 0.8), sh + Vector2(-sz * 0.7, 0), sh + Vector2(-sz * 1.2, sz * 0.8)]), Color(0.95, 0.96, 1.0))
			draw_colored_polygon(PackedVector2Array([sh + Vector2(sz * 0.9, 0), sh + Vector2(sz * 0.1, -sz * 0.28), sh + Vector2(sz * 0.1, sz * 0.28)]), Color(0.2, 0.8, 1.0))
			_title(w, h)

	func _title(w: float, h: float) -> void:
		var ad: Dictionary = AdSample.ADS[kind]
		var f := UIKit.font(900)
		var px := int(h * 0.11)
		# (a narrow picture: smaller, so the whole name fits)
		var tw := f.get_string_size(str(ad["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		if tw > w * 0.86:
			px = int(px * w * 0.86 / tw)
		var at := Vector2(w * 0.06, h * 0.2) if kind == "lagoon" else Vector2(w * 0.07, h * 0.36)   # (the orbit one under the reward line)
		draw_string(f, at + Vector2(4, 5), str(ad["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.45))
		draw_string(f, at, str(ad["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)
		draw_string(UIKit.font(700), at + Vector2(4, px * 0.75), str(ad["line"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px * 0.42), ad["c1"].lightened(0.35))


## The advertised game's icon: a rounded square in its colours with its sign.
class AdIcon:
	extends Control
	var kind := "lagoon"

	func _init(p_kind: String, px: float) -> void:
		kind = p_kind
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ad: Dictionary = AdSample.ADS[kind]
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = ad["c2"]
		sb.set_corner_radius_all(int(size.x * 0.22))
		draw_style_box(sb, r)
		var c := size * 0.5
		draw_circle(c, size.x * 0.42, Color(ad["c1"], 0.45))
		if kind == "lagoon":
			for k in 4:
				draw_circle(c, size.x * (0.3 - k * 0.04), Color(1, 1, 1, 0.08 + k * 0.05))
			draw_circle(c, size.x * 0.17, Color(0.85, 1.0, 1.0))
			draw_circle(c - size * 0.05, size.x * 0.06, Color.WHITE)
		else:
			var s := size.x * 0.2
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 1.5, 0), c + Vector2(-s * 1.1, -s * 0.9), c + Vector2(-s * 0.6, 0), c + Vector2(-s * 1.1, s * 0.9)]), Color.WHITE)


## Five stars, filled to the rating.
class AdStars:
	extends Control
	var rating := 4.5
	var px := 26.0
	var col := Color.YELLOW

	func _init(p_rating: float, p_px: float, p_col: Color) -> void:
		rating = p_rating
		px = p_px
		col = p_col
		custom_minimum_size = Vector2(px * 5.4, px)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _star(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		return pts

	func _draw() -> void:
		for i in 5:
			var c := Vector2(px * 0.5 + i * px * 1.08, px * 0.5)
			draw_colored_polygon(_star(c, px * 0.52), Color(0.82, 0.84, 0.88))
			var fill := clampf(rating - i, 0.0, 1.0)
			if fill >= 0.75:
				draw_colored_polygon(_star(c, px * 0.52), col)
			elif fill >= 0.25:
				# half a star: the star's triangles (centre to each edge) on its left side
				var pts := _star(c, px * 0.52)
				for k in pts.size():
					var a: Vector2 = pts[k]
					var b: Vector2 = pts[(k + 1) % pts.size()]
					if (a.x + b.x + c.x) / 3.0 < c.x:
						draw_colored_polygon(PackedVector2Array([c, a, b]), col)
