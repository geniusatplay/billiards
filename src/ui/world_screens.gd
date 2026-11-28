class_name WorldScreens
extends RefCounted
## v1.1.15 (Randy, 17 Nov 2026): "the only way to place the table should be place table in front of me or play in
## place which always uses the world background" ... "to place world, which lets them place the ar world in front of
## them or use the non ar view". Also the language picker (Settings → Language, and the main menu's language button).


## ------------------------------------------------------------ the two pictures on the cards
class WorldArt extends Control:
	var kind := "ar"          # "ar": a phone showing a table in a room; "studio": the table in its own world
	var _t := 0.0

	func _init(p_kind: String) -> void:
		kind = p_kind
		custom_minimum_size = Vector2(440, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Vector2(w * 0.5, h * 0.56)
		if kind == "ar":
			# the room: a floor grid going away from you, the table standing on it, a phone frame round it all
			var floor_col := Color(UIKit.SKY, 0.22)
			for i in 7:
				var y := h * 0.5 + pow(float(i) / 6.0, 1.6) * h * 0.46
				draw_line(Vector2(w * 0.08, y), Vector2(w * 0.92, y), floor_col, 2.0, true)
			for i in 9:
				var x := (float(i) - 4.0) / 4.0
				draw_line(Vector2(c.x + x * w * 0.12, h * 0.5), Vector2(c.x + x * w * 0.5, h * 0.98), floor_col, 2.0, true)
			# the target ring under the table, breathing
			var k := 0.5 + 0.5 * sin(_t * 2.4)
			_ellipse(c + Vector2(0, h * 0.2), Vector2(w * 0.3, h * 0.09) * (1.0 + 0.05 * k), Color(UIKit.EMERALD, 0.45 + 0.3 * k), 3.0)
			_table(c + Vector2(0, h * 0.02), w * 0.44, h)
			# the camera's viewfinder corners
			var m := 14.0
			var L := 46.0
			for cx in [0.0, 1.0]:
				for cy in [0.0, 1.0]:
					var corner := Vector2(m + cx * (w - 2.0 * m), m + cy * (h - 2.0 * m))
					var dx: float = (1.0 - 2.0 * cx) * L
					var dy: float = (1.0 - 2.0 * cy) * L
					draw_polyline(PackedVector2Array([corner + Vector2(dx, 0), corner, corner + Vector2(0, dy)]), Color(1, 1, 1, 0.7), 5.0, true)
		else:
			# a warm room: a lamp over the table, the light falling on it
			var glow := PackedVector2Array([Vector2(c.x - w * 0.06, h * 0.16), Vector2(c.x + w * 0.06, h * 0.16), Vector2(c.x + w * 0.36, h * 0.84), Vector2(c.x - w * 0.36, h * 0.84)])
			draw_colored_polygon(glow, Color(UIKit.GOLD, 0.08))
			draw_line(Vector2(c.x, 0), Vector2(c.x, h * 0.1), Color(1, 1, 1, 0.35), 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - w * 0.09, h * 0.18), Vector2(c.x - w * 0.05, h * 0.1), Vector2(c.x + w * 0.05, h * 0.1), Vector2(c.x + w * 0.09, h * 0.18)]), Color(UIKit.EMERALD, 0.85))
			draw_circle(Vector2(c.x, h * 0.19), 7.0, Color(UIKit.GOLD, 0.9 + 0.1 * sin(_t * 3.0)))
			_ellipse(c + Vector2(0, h * 0.26), Vector2(w * 0.4, h * 0.07), Color(0, 0, 0, 0.35), -1.0)
			_table(c + Vector2(0, h * 0.06), w * 0.5, h)
			draw_rect(Rect2(w * 0.04, h * 0.04, w * 0.92, h * 0.92), Color(1, 1, 1, 0.14), false, 2.0)

	## The table seen from the side and a little above: the cloth, the rail, two legs, a few balls.
	func _table(at: Vector2, tw: float, h: float) -> void:
		var top := PackedVector2Array([at + Vector2(-tw * 0.4, -h * 0.1), at + Vector2(tw * 0.4, -h * 0.1), at + Vector2(tw * 0.5, h * 0.06), at + Vector2(-tw * 0.5, h * 0.06)])
		draw_colored_polygon(top, Color("0f7a55"))
		draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), Color("5a3a22"), 7.0, true)
		draw_rect(Rect2(at + Vector2(-tw * 0.5, h * 0.06), Vector2(tw, h * 0.05)), Color("4a2f1c"))
		for sx in [-0.42, 0.42]:
			draw_rect(Rect2(at + Vector2(tw * sx - 8, h * 0.11), Vector2(16, h * 0.13)), Color("3a2516"))
		var bc := [Color.WHITE, UIKit.GOLD, UIKit.CORAL, UIKit.SKY, Color(0.1, 0.1, 0.12)]
		for i in bc.size():
			var p := at + Vector2(tw * (-0.22 + i * 0.1), -h * (0.02 + (i % 2) * 0.03))
			draw_circle(p, 7.5, bc[i])

	func _ellipse(at: Vector2, r: Vector2, col: Color, wdt: float) -> void:
		var pts := PackedVector2Array()
		for i in 41:
			var a := TAU * i / 40.0
			pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
		if wdt < 0.0:
			draw_colored_polygon(pts, col)
		else:
			draw_polyline(pts, col, wdt, true)


## ------------------------------------------------------------ Place world
class PlaceWorldScreen extends MenuScreens.Screen:
	const ART_H := 250.0        # the card pictures' height when there is room
	const ART_MIN_H := 130.0    # ... and the least they give before the whole column is made smaller
	var _cards: Control         # everything shown while choosing
	var _placing: Control       # everything shown while putting the table down in the room
	var _panel: ArPlacePanel
	var _was := ""              # how the world was before this screen (to put back when placing is given up)
	var _mid: CenterContainer   # the room under the title
	var _col: VBoxContainer     # the line under the title and the two cards
	var _arts: Array = []       # the two card pictures

	func _ready() -> void:
		_was = Game.world_ready
		_cards = UIKit.fullrect(Control.new())
		_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_cards)
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.05, 0.09, 0.66)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		_cards.add_child(bg)
		var h := UIKit.hbox(22)
		h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		h.offset_left = 48
		h.offset_right = -48
		h.offset_top = 36
		h.custom_minimum_size.y = 100
		var b := UIKit.icon_button("back", 96, "Back")
		b.pressed.connect(func():
			Sfx.ui("back")
			router.call("back"))
		h.add_child(b)
		var t := UIKit.label("Place your world", "H1Label")
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		_cards.add_child(h)
		var mid := CenterContainer.new()
		UIKit.fullrect(mid)
		mid.offset_top = 150
		mid.offset_bottom = -20
		mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards.add_child(mid)
		var col := UIKit.vbox(26)
		mid.add_child(col)
		var sub := UIKit.label("Choose how the table appears. You can change it before any match.", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 1100
		col.add_child(sub)
		var row := UIKit.hbox(36)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(row)
		var ar_ok := _ar_possible()
		row.add_child(_card("ar", "place", "In front of me", "Augmented reality: the table stands in your room through the camera. Walk around it, lean in, crouch down.",
			"Uses the camera", "Place in front of me", ar_ok, _choose_ar))
		row.add_child(_card("studio", "cube", "Play in place", "No camera: the table in its own world, wherever you are. The world is the scene you picked in Choose Gear.",
			"No camera", "Play in place", true, _choose_studio))
		_mid = mid
		_col = col
		_cards.resized.connect(_fit)      # (the screen's size; not the centring box, which follows the cards)
		_fit.call_deferred()
		UIKit.fade_in(col, 0.3, 24)
		# placing (hidden until "Place in front of me")
		_placing = UIKit.fullrect(Control.new())
		_placing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_placing.visible = false
		add_child(_placing)
		var pb := UIKit.icon_button("back", 96, "Back")
		pb.position = Vector2(48, 36)
		pb.name = "PlacingBack"
		pb.pressed.connect(func():
			Sfx.ui("back")
			_stop_placing())
		_placing.add_child(pb)
		_panel = ArPlacePanel.new(router.get("stage"))
		_panel.custom_minimum_size = Vector2(860, 0)
		_panel.without_ar.connect(_choose_studio)
		_placing.add_child(_panel)
		_panel.minimum_size_changed.connect(func(): _panel.place_in(_placing.size))
		_placing.resized.connect(func(): _panel.place_in(_placing.size))

	func _process(_delta: float) -> void:
		if _placing.visible:
			_panel.refresh()

	## The cards fit the screen's height (26 Nov 2026: on a phone the screen is 1080 tall in the game's units, and with
	## the scene's name on the Play in place card the buttons ran off the bottom). The pictures give first, then
	## the whole column is made smaller. A tall screen (an iPad) keeps everything at full size.
	func _fit() -> void:
		if not is_instance_valid(_col):
			return
		# the room under the title on the screen (the centring box itself grows to whatever it holds)
		var avail := _cards.size.y - _mid.offset_top + _mid.offset_bottom
		if avail <= 0.0:
			return
		_mid.scale = Vector2.ONE
		for a in _arts:
			(a as Control).custom_minimum_size.y = ART_H
		var over := _col.get_combined_minimum_size().y - avail
		if over > 0.0:
			for a in _arts:
				(a as Control).custom_minimum_size.y = maxf(ART_MIN_H, ART_H - over)
			over = _col.get_combined_minimum_size().y - avail
		if over > 0.0:
			# still too tall (long words): the whole box made smaller from the middle of its top edge
			var k := avail / _col.get_combined_minimum_size().y
			_mid.pivot_offset = Vector2(_cards.size.x * 0.5, 0.0)
			_mid.scale = Vector2(k, k)

	## For the checks: the two cards' rectangle on the screen, and the room they have (under the title).
	func cards_rect() -> Rect2:
		var r := Rect2()
		for n in ["WorldCard_ar", "WorldCard_studio"]:
			var c := find_child(n, true, false) as Control
			if c:
				r = c.get_global_rect() if r.size == Vector2.ZERO else r.merge(c.get_global_rect())
		return r

	func room_rect() -> Rect2:
		return _mid.get_global_rect() if is_instance_valid(_mid) else Rect2()

	## Can this phone show the table in the room at all? (When not, the card says so and its button is off.)
	func _ar_possible() -> bool:
		var st: Stage = router.get("stage")
		return st.arcore.simulate or (OS.get_name() in ["Android", "iOS"] and st.arcore.has_plugin())

	func _card(id: String, icon: String, title: String, desc: String, tag: String, action: String, enabled: bool, on_go: Callable) -> Control:
		var p := UIKit.panel("Card")
		p.name = "WorldCard_" + id
		p.custom_minimum_size = Vector2(620, 0)
		var chosen := Game.world_ready == id
		if chosen:
			p.add_theme_stylebox_override("panel", UIKit.box(Color(0.09, 0.16, 0.22, 0.96), 26, 3, UIKit.EMERALD, Vector4(26, 22, 26, 22), 16))
		var v := UIKit.vbox(14)
		p.add_child(v)
		var art := WorldArt.new(id)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_arts.append(art)
		v.add_child(art)
		var top := UIKit.hbox(14)
		top.add_child(IconGlyph.make(icon, 56, UIKit.EMERALD if id == "ar" else UIKit.SKY))
		var tv := UIKit.vbox(0)
		tv.add_child(UIKit.label(title, "H2Label"))
		var tg := UIKit.label(tag if enabled else "Needs a phone with AR", "AccentLabel")
		if id == "studio":
			tg.add_theme_color_override("font_color", UIKit.SKY)
		elif not enabled:
			tg.add_theme_color_override("font_color", UIKit.MUTED)
		tv.add_child(tg)
		top.add_child(tv)
		v.add_child(top)
		var d := UIKit.label(desc, "MutedLabel")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(540, 0)
		v.add_child(d)
		if id == "studio":
			# Play in place is always the scene from Choose Gear (Randy, 22 Nov): its name (a proper name: English)
			var sc := UIKit.hbox(10)
			sc.name = "WorldScene"
			sc.add_child(IconGlyph.make("globe", 34, UIKit.SKY))
			var sn := UIKit.label(str(Game.scene_style().get("name", "")), "AccentLabel")
			sn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sn.add_theme_color_override("font_color", UIKit.SKY)
			sn.name = "WorldSceneName"
			sc.add_child(sn)
			v.add_child(sc)
		v.add_child(UIKit.spacer(false))
		var go := UIKit.button(action, "PrimaryButton" if id == "ar" or not _ar_possible() else "", "camera" if id == "ar" else "play")
		go.name = "WorldGo_" + id
		go.add_theme_font_size_override("font_size", 32)       # (long words in some languages)
		go.disabled = not enabled
		go.pressed.connect(func():
			Sfx.ui("tap")
			on_go.call())
		v.add_child(go)
		if chosen:
			var now := UIKit.label(L.t("Now: %s") % L.t(title), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
			now.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			now.name = "WorldNow"
			v.add_child(now)
		return p

	## "Place in front of me": the camera comes on and the placing panel takes over the screen.
	func _choose_ar() -> void:
		var st: Stage = router.get("stage")
		Analytics.ar_mode_set(true, "player_choice")
		Game.set_s("ar_mode", "auto")
		_cards.visible = false
		_placing.visible = true
		UIKit.fade_in(_panel)
		_panel.place_in(_placing.size)
		if st.mode == Stage.Mode.WORLD_AR:
			st.unplace_table()          # (put down again somewhere else)
		else:
			st.set_mode(Stage.Mode.WORLD_AR)
		if not st.placement_changed.is_connected(_on_placed):
			st.placement_changed.connect(_on_placed)

	func _on_placed(placed: bool) -> void:
		var st: Stage = router.get("stage")
		if not placed or st.mode != Stage.Mode.WORLD_AR or not _placing.visible:
			return
		st.placement_changed.disconnect(_on_placed)
		Game.world_ready = "ar"
		Sfx.ui("toggle")
		router.call("toast", L.t("Your table is in the room. Walk around it any time."))
		router.call("world_done")

	## Back from placing: the cards again, and no table in the room (the menus show Play in place meanwhile).
	func _stop_placing() -> void:
		var st: Stage = router.get("stage")
		Analytics.ar_placement(false, "back")
		if st.placement_changed.is_connected(_on_placed):
			st.placement_changed.disconnect(_on_placed)
		if _was == "ar":
			Game.world_ready = ""      # its table was taken away to be put down again
			_was = ""
		st.set_mode(Stage.Mode.STUDIO)
		_placing.visible = false
		_cards.visible = true

	## "Play in place": no camera, the table in the chosen world background.
	func _choose_studio() -> void:
		var st: Stage = router.get("stage")
		Analytics.ar_mode_set(false, "player_choice")
		if st.placement_changed.is_connected(_on_placed):
			st.placement_changed.disconnect(_on_placed)
		Game.set_s("ar_mode", "studio")
		Game.world_ready = "studio"
		if st.mode != Stage.Mode.STUDIO:
			st.set_mode(Stage.Mode.STUDIO)
		Sfx.ui("toggle")
		router.call("world_done")

	func _exit_tree() -> void:
		var st: Stage = router.get("stage") if router else null
		if st and st.placement_changed.is_connected(_on_placed):
			st.placement_changed.disconnect(_on_placed)


## ------------------------------------------------------------ the "Place world" button before a match
## Shown on Play Online (beside "Find a match") and on the VS CPU / Local screens (beside "Break!"): how the table
## appears now, and a tap to change it.
static func world_button(router: Node) -> Button:
	var b := UIKit.button("Place world", "GhostButton", "place")
	# how the table appears now, as the button's icon colour: emerald = in the room (AR), sky = Play in place
	(b.get_meta("icon_glyph") as IconGlyph).color = UIKit.EMERALD if Game.world_ready == "ar" else UIKit.SKY
	b.name = "PlaceWorldButton"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Sfx.ui("tap")
		router.call("place_world_again"))
	return b


## ------------------------------------------------------------ language picker
## Randy: "the language should be an option when they click the language button". Every language in its own name,
## two columns, the one in use marked.
class LanguagePicker extends Control:
	signal closed

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		name = "LanguagePicker"

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.04, 0.07, 0.78)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		bg.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				_close())
		add_child(bg)
		var cc := CenterContainer.new()
		UIKit.fullrect(cc)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cc)
		var p := UIKit.panel("Card")
		p.custom_minimum_size = Vector2(1260, 0)
		cc.add_child(p)
		var v := UIKit.vbox(18)
		p.add_child(v)
		var head := UIKit.hbox(16)
		head.add_child(IconGlyph.make("language", 56, UIKit.EMERALD))
		var t := UIKit.label("Language", "H1Label")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var x := UIKit.icon_button("close", 84, "Close")
		x.pressed.connect(_close)
		head.add_child(x)
		v.add_child(head)
		var sc := UIKit.scroll()
		sc.custom_minimum_size = Vector2(0, minf(820.0, get_viewport_rect().size.y - 230.0))
		v.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 12)
		sc.add_child(grid)
		var saved := str(Game.get_s("language"))
		for l in [["auto", "Automatic"]] + Loc.LANGS:
			var code: String = l[0]
			var on := saved == code or (code == "auto" and not saved in Loc.codes())
			var b := UIKit.button(l[1], "ChipButton", "", 390)
			b.name = "Lang_" + code
			b.toggle_mode = true
			b.button_pressed = on
			b.custom_minimum_size.y = 72
			if code != "auto":
				b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # each language keeps its own name
			b.pressed.connect(func():
				Sfx.ui("toggle")
				_close()
				Loc.set_language(code))
			grid.add_child(b)
		UIKit.fade_in(p, 0.2, 18)

	func _close() -> void:
		closed.emit()
		queue_free()


## The name of the language in use, in that language ("Automatic" in the current one).
static func language_name() -> String:
	var saved := str(Game.get_s("language"))
	for l in Loc.LANGS:
		if l[0] == saved:
			return l[1]
	return L.t("Automatic")
