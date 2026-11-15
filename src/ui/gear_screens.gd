class_name GearScreens
extends RefCounted
## The Choose Gear page (cues, tables, ball sets, scenes with their reward pictures) and helpers shared with
## the package screen: the pictures themselves, rarity colours and names.

const KINDS := ["cue", "table", "balls", "scene"]
const KIND_TITLES := {"cue": "Cues", "table": "Tables", "balls": "Ball sets", "scene": "Scenes"}
const KIND_ONE := {"cue": "Cue", "table": "Table", "balls": "Ball set", "scene": "Scene"}
const KIND_ICONS := {"cue": "cue", "table": "grid", "balls": "ball", "scene": "studio"}
const SHEETS := {"cue": "cues", "table": "tables", "balls": "balls", "scene": "scenes"}
const RARITY_COLORS := [Color("93a4bf"), Color("d2dae6"), Color("46dc96"), Color("50aaff"), Color("c878ff"), Color("ffc850")]

static var _tex := {}


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, 5)]


static func rarity_name(r: int) -> String:
	return L.t(XP.RARITY_NAMES[clampi(r, 0, 5)])


## The reward picture of an item (baked by tools/bake_icons.sh; null if the sheet is missing).
static func icon(kind: String, id: String) -> Texture2D:
	var key := kind + ":" + id
	if _tex.has(key):
		return _tex[key]
	var sheet_name: String = SHEETS.get(kind, "")
	var info: Dictionary = IconIndex.DATA.get(sheet_name, {})
	var at: int = (info.get("ids", []) as Array).find(id)
	var path := "res://assets/icons/%s.png" % sheet_name
	if at < 0 or not ResourceLoader.exists(path):
		_tex[key] = null
		return null
	var t := AtlasTexture.new()
	t.atlas = load(path)
	var tile := float(info["tile"])
	var cols := int(info["cols"])
	t.region = Rect2((at % cols) * tile, (at / cols) * tile, tile, tile)
	_tex[key] = t
	return t


## One item as a tile: picture, name, rarity. `state`: "on" (in use), "owned" or "locked".
static func tile(kind: String, e: Dictionary, state: String, side := 204.0) -> Button:
	var r := Catalog.rarity(e)
	var rc := rarity_color(r)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var k := side / 204.0       # text and spacing grow with the tile
	b.custom_minimum_size = Vector2(side + 16.0, side + 16.0 + 78.0 * k)
	b.clip_contents = true
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var on := state == "on"
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bx := UIKit.box(Color(0.06, 0.09, 0.15, 0.96), 18, 5 if on else 2, UIKit.EMERALD if on else Color(rc, 0.75 if state == "owned" else 0.3), Vector4(0, 0, 0, 0))
		b.add_theme_stylebox_override(st, bx)
	var pic := TextureRect.new()
	pic.texture = icon(kind, str(e["id"]))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.position = Vector2(8, 8)
	pic.size = Vector2(side, side)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	if state == "locked":
		pic.modulate = Color(0.52, 0.54, 0.6)
		var lock := IconGlyph.make("lock", 64, Color(1, 1, 1, 0.85))
		lock.position = Vector2(8 + side * 0.5 - 32, 8 + side * 0.5 - 32)
		b.add_child(lock)
	if on:
		var badge := Panel.new()
		badge.add_theme_stylebox_override("panel", UIKit.box(UIKit.EMERALD, 22, 0))
		badge.position = Vector2(side - 36, 14)
		badge.size = Vector2(44, 44)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ck := IconGlyph.make("check", 30, UIKit.INK)
		ck.position = Vector2(7, 7)
		badge.add_child(ck)
		b.add_child(badge)
	var nm := Label.new()
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # item names are proper names
	nm.text = str(e["name"])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.add_theme_font_override("font", UIKit.font(650))
	nm.add_theme_font_size_override("font_size", int((24 if str(e["name"]).length() <= 15 else 20) * k))
	nm.add_theme_color_override("font_color", UIKit.TEXT if state != "locked" else UIKit.MUTED)
	nm.position = Vector2(6, side + 12)
	nm.size = Vector2(side + 4, 32 * k)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var rl := Label.new()
	rl.text = rarity_name(r)        # translated here: the tile itself is not (item names are proper names)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.clip_text = true
	rl.add_theme_font_override("font", UIKit.font(700))
	rl.add_theme_font_size_override("font_size", int(18 * k))
	rl.add_theme_color_override("font_color", Color(rc, 1.0 if state != "locked" else 0.6))
	rl.position = Vector2(6, side + 12 + 34 * k)
	rl.size = Vector2(side + 4, 26 * k)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rl)
	return b


## ------------------------------------------------------------ Choose Gear
class GearScreen extends MenuScreens.Screen:
	var kind := "cue"
	var _grid: HFlowContainer
	var _tabs := {}
	var _count: Label

	func _init(p_router: Node = null, p_kind := "cue") -> void:
		super(p_router)
		kind = p_kind

	func _ready() -> void:
		scrim(0.82)
		var h := header("Choose Gear")
		h.add_child(UIKit.spacer())
		_count = UIKit.label("", "MutedLabel")
		_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_count)
		var tabs := HFlowContainer.new()
		tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		tabs.offset_left = 120
		tabs.offset_right = -120
		tabs.offset_top = 150
		tabs.add_theme_constant_override("h_separation", 16)
		tabs.add_theme_constant_override("v_separation", 10)
		add_child(tabs)
		for k in GearScreens.KINDS:
			var tb := UIKit.button(GearScreens.KIND_TITLES[k], "ChipButton", GearScreens.KIND_ICONS[k])
			tb.toggle_mode = true
			tb.pressed.connect(func():
				Sfx.ui("tap")
				kind = k
				_fill())
			tabs.add_child(tb)
			_tabs[k] = tb
		content(236, 120)
		_grid = HFlowContainer.new()
		_grid.add_theme_constant_override("h_separation", 16)
		_grid.add_theme_constant_override("v_separation", 16)
		_grid.alignment = FlowContainer.ALIGNMENT_CENTER
		body.add_child(_grid)
		_fill()

	func _fill() -> void:
		for c in _grid.get_children():
			c.queue_free()
		for k in _tabs.keys():
			(_tabs[k] as Button).button_pressed = k == kind
		var key: String = Game.GEAR_KEYS[kind]
		var cur := str(Game.get_s(key))
		var have := 0
		# least exotic first: the lists are kept that way, but sort here too so it can never slip
		var list: Array = []
		for r_want in 6:
			for e0 in Catalog.kind_list(kind):
				if Catalog.rarity(e0) == r_want:
					list.append(e0)
		for e in list:
			var id := str(e["id"])
			var owned: bool = Game.owns(kind, id)
			if owned:
				have += 1
			var t := GearScreens.tile(kind, e, "on" if id == cur else ("owned" if owned else "locked"))
			t.pressed.connect(func():
				if Game.owns(kind, id):
					Sfx.ui("toggle")
					Game.set_s(key, id)
					_fill()
				else:
					Sfx.ui("back")
					var r := Catalog.rarity(e)
					router.call("toast", L.t("%s: in the packages for levels %d to %d") % [GearScreens.rarity_name(r), r * 20 - 19, r * 20]))
			_grid.add_child(t)
		_count.text = "%d / %d" % [have, list.size()]


## ------------------------------------------------------------ the gear drawer (in a match, on the right)
## Randy, 11 Nov: "a menu on the right where I can always change the pool cue / table / ball set". It slides in
## over the right-hand edge of the match; a tap on a tile puts that cue, table or ball set on at once (the match
## goes on: balls, turn and score stay as they are). A tap outside it, or its close button, slides it away.
class GearDrawer extends Control:
	signal closed

	const DRAWER_KINDS := ["cue", "table", "balls"]
	const W := 640.0
	var kind := "cue"
	var _panel: PanelContainer
	var _grid: HFlowContainer
	var _scroll: ScrollContainer
	var _tabs := {}
	var _count: Label
	var _press_scroll := 0
	var _closing := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# a tap anywhere else closes it (and never reaches the cue controls underneath)
		var catcher := ColorRect.new()
		catcher.color = Color(0, 0, 0, 0.18)
		UIKit.fullrect(catcher)
		catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		catcher.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				close())
		add_child(catcher)
		_panel = UIKit.panel("Card")
		_panel.name = "GearDrawerPanel"
		_panel.anchor_left = 1.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -W - 16.0
		_panel.offset_right = -16.0
		_panel.offset_top = 16.0
		_panel.offset_bottom = -16.0
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		# solid, so the match's own cards behind it don't show through
		var sb := UIKit.box(Color(0.055, 0.08, 0.13, 1.0), 26, 2, Color(1, 1, 1, 0.12), Vector4(24, 22, 24, 22))
		_panel.add_theme_stylebox_override("panel", sb)
		add_child(_panel)
		var v := UIKit.vbox(12)
		_panel.add_child(v)
		var head := UIKit.hbox(10)
		var t := UIKit.label("Choose Gear", "H2Label")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		head.add_child(t)
		_fit_title.call_deferred(t)
		_count = UIKit.label("", "MutedLabel")
		_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(_count)
		var x := UIKit.icon_button("close", 72, "Close")
		x.name = "GearDrawerClose"
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x.pressed.connect(close)
		head.add_child(x)
		v.add_child(head)
		var tabs := HFlowContainer.new()
		tabs.add_theme_constant_override("h_separation", 10)
		tabs.add_theme_constant_override("v_separation", 8)
		for k in DRAWER_KINDS:
			var tb := UIKit.button(GearScreens.KIND_TITLES[k], "ChipButton", GearScreens.KIND_ICONS[k])
			tb.toggle_mode = true
			tb.name = "DrawerTab_" + k
			tb.pressed.connect(func():
				Sfx.ui("tap")
				kind = k
				_fill())
			tabs.add_child(tb)
			_tabs[k] = tb
		v.add_child(tabs)
		_scroll = UIKit.scroll()
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(_scroll)
		_grid = HFlowContainer.new()
		_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_theme_constant_override("h_separation", 12)
		_grid.add_theme_constant_override("v_separation", 12)
		_grid.alignment = FlowContainer.ALIGNMENT_CENTER
		_scroll.add_child(_grid)
		_fill()
		# slides in from the right
		if not Game.get_s("reduced_motion"):
			_panel.position.x += W
			var tw := create_tween()
			tw.tween_property(_panel, "position:x", _panel.position.x - W, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	## Long names (Russian, Tamil...) get a smaller heading, so it stays on one line and never widens the drawer.
	func _fit_title(t: Label) -> void:
		if not is_instance_valid(t) or not t.is_inside_tree():
			return
		await get_tree().process_frame             # laid out: the label now has its real width
		if not is_instance_valid(t):
			return
		var room := t.size.x - 4.0
		var fs := t.get_theme_font_size("font_size")
		var f := t.get_theme_font("font")
		var txt := L.t("Choose Gear")
		while fs > 24 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 2
		t.add_theme_font_size_override("font_size", fs)

	## Only what the player owns (everything while "unlock everything" is on), least exotic first.
	func _fill() -> void:
		for c in _grid.get_children():
			c.queue_free()
		for k in _tabs.keys():
			(_tabs[k] as Button).button_pressed = k == kind
		var key: String = Game.GEAR_KEYS[kind]
		var cur := str(Game.get_s(key))
		var shown := 0
		var total := 0
		for r_want in 6:
			for e in Catalog.kind_list(kind):
				if Catalog.rarity(e) != r_want:
					continue
				total += 1
				var id := str(e["id"])
				if not Game.owns(kind, id):
					continue
				shown += 1
				var tile := GearScreens.tile(kind, e, "on" if id == cur else "owned", 150.0)
				tile.name = "Drawer_%s_%s" % [kind, id]
				tile.mouse_filter = Control.MOUSE_FILTER_PASS        # a drag that starts on a tile still scrolls
				tile.button_down.connect(func(): _press_scroll = _scroll.scroll_vertical)
				tile.pressed.connect(func():
					# a drag to scroll is not a choice
					if absi(_scroll.scroll_vertical - _press_scroll) > 12:
						return
					pick(id))
				_grid.add_child(tile)
				if id == cur:
					_show_later(tile)
		_count.text = "%d / %d" % [shown, total]

	## Scrolls so the item in use can be seen (once the grid has been laid out).
	func _show_later(tile: Control) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(tile) and is_instance_valid(_scroll):
			_scroll.ensure_control_visible(tile)

	## Puts it on at once (the match updates itself from the setting).
	func pick(id: String) -> void:
		var key: String = Game.GEAR_KEYS[kind]
		if str(Game.get_s(key)) == id:
			return
		Sfx.ui("toggle")
		Game.set_s(key, id)
		_fill()

	func close() -> void:
		if _closing:
			return
		_closing = true
		closed.emit()
		if Game.get_s("reduced_motion"):
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(_panel, "position:x", _panel.position.x + W + 20.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
		tw.tween_callback(queue_free)
