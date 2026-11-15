class_name UIKit
extends RefCounted
## Design tokens, theme builder and widget factory for the Emerald Break UI.

const INK := Color("0b1220")
const GLASS := Color(0.071, 0.110, 0.180, 0.90)
const GLASS_HI := Color(0.098, 0.149, 0.247, 0.94)
const EMERALD := Color("2be7a5")
const EMERALD_DK := Color("12a878")
const GOLD := Color("ffc857")
const CORAL := Color("ff5c7a")
const SKY := Color("4cc9f0")
const VIOLET := Color("b388ff")
const TEXT := Color("eaf2ff")
const MUTED := Color("93a4bf")
const LINE := Color(1, 1, 1, 0.09)
const P1_COLOR := Color("2be7a5")
const P2_COLOR := Color("4cc9f0")

const FONT_PATH := "res://assets/fonts/Outfit-Variable.ttf"

## Outfit only has Latin letters (and no Vietnamese accents). These Noto Sans files, built by
## tools/build_fonts.py, draw everything else.
const FALLBACK_FONTS := {
	"lat": "res://assets/fonts/NotoSans-Extra.ttf",        # Cyrillic, Greek, every Latin accent
	"ar": "res://assets/fonts/NotoSansArabic.ttf",          # Arabic, Urdu
	"hi": "res://assets/fonts/NotoSansDevanagari.ttf",      # Hindi, Marathi
	"th": "res://assets/fonts/NotoSansThai.ttf",
	"bn": "res://assets/fonts/NotoSansBengali.ttf",
	"ta": "res://assets/fonts/NotoSansTamil.ttf",
	"te": "res://assets/fonts/NotoSansTelugu.ttf",
	"pa": "res://assets/fonts/NotoSansGurmukhi.ttf",
	"he": "res://assets/fonts/NotoSansHebrew.ttf",
	"ja": "res://assets/fonts/NotoSansJP-Subset.ttf",
	"ko": "res://assets/fonts/NotoSansKR-Subset.ttf",
	"zh": "res://assets/fonts/NotoSansSC-Subset.ttf",
	"tc": "res://assets/fonts/NotoSansTC-Subset.ttf",
}

static var _fonts := {}
static var _lang := "en"
static var _theme: Theme = null


static func font(weight := 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = _base_font()
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	fv.fallbacks = _fallbacks(weight)
	_fonts[weight] = fv
	return fv


## Fallback fonts for one weight. Chinese, Japanese and Korean share many characters that each language
## draws a little differently, so the font of the language in use comes first.
static func _fallbacks(weight: int) -> Array[Font]:
	var order := ["lat", "ar", "hi", "th", "bn", "ta", "te", "pa", "he"]
	match _lang:
		"zh": order.append_array(["zh", "tc", "ja", "ko"])
		"zh_TW": order.append_array(["tc", "zh", "ja", "ko"])
		"ko": order.append_array(["ko", "ja", "zh", "tc"])
		_: order.append_array(["ja", "zh", "tc", "ko"])
	var ts := TextServerManager.get_primary_interface()
	var out: Array[Font] = []
	for k in order:
		var path: String = FALLBACK_FONTS[k]
		if not ResourceLoader.exists(path):
			continue
		var f := FontVariation.new()
		f.base_font = load(path)
		f.variation_opentype = {ts.name_to_tag("wght"): weight}
		out.append(f)
	var sys := SystemFont.new()   # last resort: whatever the phone has (emoji, rare characters in names)
	sys.font_names = PackedStringArray(["sans-serif"])
	sys.font_weight = weight
	out.append(sys)
	return out


## The main font. Vietnamese stacks accents Outfit doesn't have, and half a word in one font and half in
## another looks broken, so Vietnamese is set entirely in Noto Sans.
static func _base_font() -> Font:
	var path: String = FALLBACK_FONTS["lat"] if _lang == "vi" else FONT_PATH
	if not ResourceLoader.exists(path):
		path = FONT_PATH
	return load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font


## Called when the language changes (see Loc): picks the main font and puts the right CJK font first.
static func set_language(lang: String) -> void:
	if lang == _lang:
		return
	_lang = lang
	for w in _fonts:
		var fv := _fonts[w] as FontVariation
		fv.base_font = _base_font()
		fv.fallbacks = _fallbacks(w)


static func box(bg: Color, radius := 22, border := 0, border_col := LINE, pad := Vector4(24, 14, 24, 14), shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	s.corner_detail = 10
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_offset = Vector2(0, shadow * 0.35)
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 30
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	# Buttons
	var bn := box(GLASS_HI, 24, 2, LINE, Vector4(30, 16, 30, 16))
	var bh := box(Color(0.13, 0.2, 0.32, 0.96), 24, 2, Color(EMERALD, 0.55), Vector4(30, 16, 30, 16))
	var bp := box(EMERALD_DK, 24, 2, EMERALD, Vector4(30, 16, 30, 16))
	var bd := box(Color(0.1, 0.13, 0.2, 0.5), 24, 2, LINE, Vector4(30, 16, 30, 16))
	var bf := box(Color(0, 0, 0, 0), 24, 3, EMERALD, Vector4(30, 16, 30, 16))
	for st in [["normal", bn], ["hover", bh], ["pressed", bp], ["disabled", bd], ["focus", bf], ["hover_pressed", bp]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 34)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_constant("h_separation", "Button", 14)
	# Primary button variation
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(EMERALD, 28, 0, LINE, Vector4(40, 20, 40, 20), 10))
	t.set_stylebox("hover", "PrimaryButton", box(EMERALD.lightened(0.15), 28, 0, LINE, Vector4(40, 20, 40, 20), 12))
	t.set_stylebox("pressed", "PrimaryButton", box(EMERALD_DK, 28, 0, LINE, Vector4(40, 20, 40, 20), 4))
	t.set_stylebox("hover_pressed", "PrimaryButton", box(EMERALD_DK, 28, 0, LINE, Vector4(40, 20, 40, 20), 4))
	t.set_color("font_color", "PrimaryButton", INK)
	t.set_color("font_hover_color", "PrimaryButton", INK)
	t.set_color("font_pressed_color", "PrimaryButton", INK)
	t.set_font("font", "PrimaryButton", font(800))
	t.set_font_size("font_size", "PrimaryButton", 38)
	# Ghost button
	t.add_type("GhostButton")
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0), 24, 2, Color(1, 1, 1, 0.16), Vector4(26, 14, 26, 14)))
	t.set_stylebox("hover", "GhostButton", box(Color(1, 1, 1, 0.06), 24, 2, Color(EMERALD, 0.6), Vector4(26, 14, 26, 14)))
	t.set_stylebox("pressed", "GhostButton", box(Color(EMERALD, 0.2), 24, 2, EMERALD, Vector4(26, 14, 26, 14)))
	t.set_stylebox("hover_pressed", "GhostButton", box(Color(EMERALD, 0.2), 24, 2, EMERALD, Vector4(26, 14, 26, 14)))
	# Chip (toggle pill)
	t.add_type("ChipButton")
	t.set_type_variation("ChipButton", "Button")
	t.set_stylebox("normal", "ChipButton", box(Color(1, 1, 1, 0.06), 40, 2, Color(1, 1, 1, 0.12), Vector4(24, 10, 24, 10)))
	t.set_stylebox("hover", "ChipButton", box(Color(1, 1, 1, 0.1), 40, 2, Color(EMERALD, 0.5), Vector4(24, 10, 24, 10)))
	t.set_stylebox("pressed", "ChipButton", box(Color(EMERALD, 0.22), 40, 2, EMERALD, Vector4(24, 10, 24, 10)))
	t.set_stylebox("hover_pressed", "ChipButton", box(Color(EMERALD, 0.28), 40, 2, EMERALD, Vector4(24, 10, 24, 10)))
	t.set_font_size("font_size", "ChipButton", 28)
	# Icon round button
	t.add_type("RoundButton")
	t.set_type_variation("RoundButton", "Button")
	t.set_stylebox("normal", "RoundButton", box(Color(0.07, 0.11, 0.18, 0.78), 60, 2, Color(1, 1, 1, 0.12), Vector4(16, 16, 16, 16), 6))
	t.set_stylebox("hover", "RoundButton", box(Color(0.12, 0.18, 0.28, 0.9), 60, 2, Color(EMERALD, 0.6), Vector4(16, 16, 16, 16), 6))
	t.set_stylebox("pressed", "RoundButton", box(Color(EMERALD, 0.35), 60, 2, EMERALD, Vector4(16, 16, 16, 16), 2))
	t.set_stylebox("hover_pressed", "RoundButton", box(Color(EMERALD, 0.35), 60, 2, EMERALD, Vector4(16, 16, 16, 16), 2))
	# Panels
	t.set_stylebox("panel", "PanelContainer", box(GLASS, 30, 1, Color(1, 1, 1, 0.08), Vector4(34, 30, 34, 30), 22))
	t.set_stylebox("panel", "Panel", box(GLASS, 30, 1, Color(1, 1, 1, 0.08), Vector4(0, 0, 0, 0), 22))
	t.add_type("Card")
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(Color(0.09, 0.14, 0.23, 0.92), 26, 1, Color(1, 1, 1, 0.09), Vector4(26, 22, 26, 22), 12))
	t.add_type("HudPanel")
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", box(Color(0.04, 0.07, 0.12, 0.72), 24, 1, Color(1, 1, 1, 0.1), Vector4(22, 12, 22, 12), 8))
	# Label variations
	for v in [["TitleLabel", 900, 104, TEXT], ["H1Label", 800, 64, TEXT], ["H2Label", 700, 42, TEXT],
			["H3Label", 650, 34, TEXT], ["MutedLabel", 500, 28, MUTED], ["SmallLabel", 500, 24, MUTED],
			["AccentLabel", 800, 30, EMERALD], ["ClockLabel", 700, 40, TEXT]]:
		t.add_type(v[0])
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], font(v[1]))
		t.set_font_size("font_size", v[0], v[2])
		t.set_color("font_color", v[0], v[3])
	# Slider
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 8, 0, LINE, Vector4(0, 5, 0, 5)))
	t.set_stylebox("grabber_area", "HSlider", box(EMERALD, 8, 0, LINE, Vector4(0, 5, 0, 5)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(EMERALD.lightened(0.1), 8, 0, LINE, Vector4(0, 5, 0, 5)))
	var grab := _circle_tex(40, Color.WHITE, EMERALD)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(44, Color.WHITE, EMERALD.lightened(0.2)))
	t.set_icon("grabber_disabled", "HSlider", _circle_tex(40, Color(1, 1, 1, 0.4), MUTED))
	# CheckButton (switch)
	t.set_icon("checked", "CheckButton", _switch_tex(true))
	t.set_icon("unchecked", "CheckButton", _switch_tex(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_tex(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_tex(false))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckButton", box(Color(0, 0, 0, 0), 12, 0, LINE, Vector4(4, 8, 4, 8)))
	t.set_font_size("font_size", "CheckButton", 30)
	t.set_font("font", "CheckButton", font(500))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	# Option button & popup
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.12, 0.2, 0.98), 18, 1, Color(1, 1, 1, 0.12), Vector4(12, 12, 12, 12)))
	t.set_stylebox("hover", "PopupMenu", box(Color(EMERALD, 0.25), 12, 0, LINE, Vector4(10, 8, 10, 8)))
	t.set_font_size("font_size", "PopupMenu", 30)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_constant("v_separation", "PopupMenu", 16)
	# LineEdit
	t.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, 0.06), 16, 2, Color(1, 1, 1, 0.14), Vector4(18, 12, 18, 12)))
	t.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1, 0.08), 16, 2, EMERALD, Vector4(18, 12, 18, 12)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", EMERALD)
	# Scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.04), 6, 0, LINE, Vector4(4, 4, 4, 4)))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.22), 6, 0, LINE, Vector4(4, 4, 4, 4)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(EMERALD, 0.6), 6, 0, LINE, Vector4(4, 4, 4, 4)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(EMERALD, 6, 0, LINE, Vector4(4, 4, 4, 4)))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.08, 0.14, 0.96), 12, 1, LINE, Vector4(14, 10, 14, 10)))
	_theme = t
	return t


static func _circle_tex(size: int, fill: Color, ring: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			var col := ring if d > c - 5.0 else fill
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


static func _switch_tex(on: bool) -> ImageTexture:
	var w := 92
	var h := 52
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := EMERALD if on else Color(1, 1, 1, 0.18)
	var knob_x := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, h * 0.5, w - h * 0.5)
			var dt := p.distance_to(Vector2(cx, h * 0.5))
			var a := clampf(h * 0.5 - dt, 0.0, 1.0)
			var col := Color(track, track.a * a)
			var dk := p.distance_to(Vector2(knob_x, h * 0.5))
			var ka := clampf(h * 0.5 - 6.0 - dk, 0.0, 1.0)
			if ka > 0.0:
				col = col.lerp(Color.WHITE, ka)
				col.a = maxf(col.a, ka)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ factories
static func label(text: String, variation := "", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, variation := "", icon := "", min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	b.focus_mode = Control.FOCUS_NONE
	if icon != "":
		var icol := INK if variation == "PrimaryButton" else TEXT
		var ic := IconGlyph.make(icon, 38, icol)
		b.add_child(ic)
		b.set_meta("icon_glyph", ic)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var place_icon := func():
			var tw := b.get_theme_font("font").get_string_size(b.tr(b.text), HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
			var x := (b.size.x - tw) * 0.5 - 38 - 14 if b.text != "" else (b.size.x - 38) * 0.5
			ic.position = Vector2(maxf(18.0, x), (b.size.y - 38) * 0.5)
		b.resized.connect(place_icon)
		b.ready.connect(place_icon)
		b.draw.connect(place_icon)   # the text (and its width) changes with the language
		if text != "":
			b.text = text
			var sb_l := 30 + 38 + 8
			var th := theme()
			var tv := variation if variation != "" else "Button"
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var base: StyleBox = th.get_stylebox(st, tv) if th.has_stylebox(st, tv) else th.get_stylebox(st, "Button")
				if base:
					var cp: StyleBox = base.duplicate()
					cp.content_margin_left = maxf(cp.content_margin_left, sb_l)
					b.add_theme_stylebox_override(st, cp)
	b.pressed.connect(func(): Sfx.ui("tap"))
	_add_press_bounce(b)
	return b


static func icon_button(icon: String, size := 96.0, tip := "") -> Button:
	var b := Button.new()
	b.theme_type_variation = "RoundButton"
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var ic := IconGlyph.make(icon, size * 0.46, UIKit.TEXT)
	b.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	b.set_meta("icon_glyph", ic)
	b.pressed.connect(func(): Sfx.ui("tap"))
	_add_press_bounce(b)
	return b


static func _add_press_bounce(b: Control) -> void:
	b.button_down.connect(func():
		if Game.get_s("reduced_motion"):
			return
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
	b.button_up.connect(func():
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


static func vbox(sep := 18) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(sep := 18) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func spacer(h := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Vertical list that can be drag-scrolled on touch screens even when the finger starts on a card
## (panels STOP input by default, which would swallow the drag before the ScrollContainer sees it).
static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.sort_children.connect(func(): _pass_panels(sc))
	return sc


static func _pass_panels(n: Node) -> void:
	for c in n.get_children():
		if c is PanelContainer or c is Panel:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_panels(c)


static func panel(variation := "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


static func fullrect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func center_in(parent: Control, child: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fullrect(cc)
	parent.add_child(cc)
	cc.add_child(child)
	return cc


static func fmt_clock(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]


## Fade + gentle scale-in. Safe inside containers (never touches position).
static func fade_in(c: CanvasItem, dur := 0.22, _from_y := 24.0) -> void:
	if Game.get_s("reduced_motion"):
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	# by id, not by reference: the thing may be gone again before the next frame (a screen opened and closed at once)
	_fade_start.bind(c.get_instance_id(), dur).call_deferred()


static func _fade_start(id: int, dur: float) -> void:
	var c := instance_from_id(id) as CanvasItem
	if c == null or not is_instance_valid(c):
		return
	if not c.is_inside_tree():
		c.modulate.a = 1.0
		return
	if c is Control:
		var ctl := c as Control
		ctl.pivot_offset = ctl.size * 0.5
		ctl.scale = Vector2(0.97, 0.97)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_ease(Tween.EASE_OUT)
	if c is Control:
		tw.tween_property(c, "scale", Vector2.ONE, dur * 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
