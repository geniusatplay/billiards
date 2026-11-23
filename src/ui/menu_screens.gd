class_name MenuScreens
extends RefCounted
## Main menu, match setup (vs AI / pass & play), cue-control chooser, how-to-play.


## ------------------------------------------------------------ shared base
class Screen extends Control:
	var router: Node
	var body: VBoxContainer

	func _init(p_router: Node = null) -> void:
		router = p_router
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func scrim(alpha := 0.72) -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.05, 0.09, alpha)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		add_child(bg)

	func header(title: String, back := true) -> HBoxContainer:
		var h := UIKit.hbox(22)
		h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		h.offset_left = 48
		h.offset_right = -48
		h.offset_top = 36
		h.custom_minimum_size.y = 100
		if back:
			var b := UIKit.icon_button("back", 96, "Back")
			b.pressed.connect(func():
				Sfx.ui("back")
				router.call("back"))
			h.add_child(b)
		var t := UIKit.label(title, "H1Label")
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		add_child(h)
		return h

	func content(top := 160.0, side := 120.0) -> VBoxContainer:
		var sc := UIKit.scroll()
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sc.offset_top = top
		sc.offset_left = side
		sc.offset_right = -side
		sc.offset_bottom = -30
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(sc)
		body = UIKit.vbox(22)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(body)
		return body


## ------------------------------------------------------------ main menu
class MainMenu extends Screen:
	var _taps := 0

	func _ready() -> void:
		var shade := TextureRect.new()
		var g := GradientTexture2D.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(0.03, 0.05, 0.09, 0.92))
		grad.set_color(1, Color(0.03, 0.05, 0.09, 0.0))
		g.gradient = grad
		g.fill_from = Vector2(0, 0)
		g.fill_to = Vector2(1, 0)
		shade.texture = g
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		shade.offset_right = 1250
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		var left := UIKit.vbox(10)
		left.position = Vector2(110, 150)
		left.name = "MenuLeft"
		add_child(left)
		var brand := UIKit.hbox(18)
		var gem := IconGlyph.make("gem", 72, UIKit.EMERALD)
		brand.add_child(gem)
		brand.add_child(UIKit.label("EMERALD VORTEX GAMES", "AccentLabel"))
		# v1.1.15: the language button (Randy: "the language should be an option when they click the language button"),
		# at the end of the studio's line, clear of the button column in every language
		brand.add_child(UIKit.spacer())
		var lg := UIKit.icon_button("language", 76, "Language")
		lg.name = "MenuLanguage"
		lg.pressed.connect(func(): router.call("open_language"))
		brand.add_child(lg)
		left.add_child(brand)
		var title := UIKit.label(Game.TITLE_LINES[0], "TitleLabel")
		title.name = "MenuTitle"
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED    # (the name)
		title.add_theme_constant_override("outline_size", 0)
		left.add_child(title)
		# v1.1.15: the rest of the game's full name, as on the loading screen and in the stores ("Emerald Online 8 Ball
		# Pool AR", Randy 22 Nov)
		var tag := UIKit.label(Game.TITLE_LINES[1], "H3Label")
		tag.name = "MenuSubtitle"
		tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # (part of the name)
		# (a FontVariation over UIKit's FontVariation loses its weight and drew the Outfit's thinnest: copy the weight)
		var f700 := UIKit.font(700) as FontVariation
		var spaced := FontVariation.new()
		spaced.base_font = f700.base_font
		spaced.variation_opentype = f700.variation_opentype
		spaced.fallbacks = f700.fallbacks
		spaced.spacing_glyph = 7
		tag.add_theme_font_override("font", spaced)
		tag.add_theme_color_override("font_color", UIKit.EMERALD)      # (as on the loading screen: the name's second line)
		left.add_child(tag)
		left.add_child(UIKit.spacer(false))
		# level and XP
		_xp_bar = RewardScreens.XpBar.new(560.0)
		left.add_child(_xp_bar)
		var rec := UIKit.vbox(6)
		var gp: Array = Game.stats.get("games_vs_ai", [0, 0, 0])
		var w: Array = Game.stats.get("wins_vs_ai", [0, 0, 0])
		for i in 3:
			var row := UIKit.hbox(10)
			row.add_child(IconGlyph.make("trophy", 30, [UIKit.EMERALD, UIKit.GOLD, UIKit.CORAL][i]))
			row.add_child(UIKit.label(L.t("%s CPU: %d wins / %d games") % [L.t(AIPlayer.NAMES[i]), int(w[i]), int(gp[i])], "MutedLabel"))
			rec.add_child(row)
		left.add_child(rec)
		left.add_child(UIKit.spacer(false))
		left.add_child(_gear_card())
		var col := UIKit.vbox(12)
		# pinned to the right edge; longer words (other languages) make it grow to the left, never off screen
		col.anchor_left = 1.0
		col.anchor_right = 1.0
		col.anchor_top = 0.5
		col.anchor_bottom = 0.5
		col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		col.offset_left = -620
		col.offset_right = -100
		col.offset_top = -486
		col.custom_minimum_size = Vector2(520, 0)
		col.name = "MenuColumn"
		add_child(col)
		# v1.1.15: the tutorial until it has been played to the end ("the play tutorial button should be above at the
		# main menu for anyone who hasnt completed it (skipping it doesnt count)"), and Place world after each start
		# ("if they restarted the game they should have the option at the main menu under tutorial. to place world"):
		# side by side in one compact row, so the column still fits above the chest
		var setup := UIKit.hbox(12)
		setup.name = "MenuSetupRow"
		if not Game.tutorial_done():
			var tb := _compact(UIKit.button("Play tutorial", "", "school"))
			tb.name = "MenuTutorial"
			(tb.get_meta("icon_glyph") as IconGlyph).color = UIKit.GOLD
			tb.add_theme_stylebox_override("normal", UIKit.box(Color(0.16, 0.13, 0.05, 0.92), 24, 2, Color(UIKit.GOLD, 0.7), Vector4(30 + 38 + 8, 12, 24, 12)))
			tb.pressed.connect(func(): router.call("play", "tutorial"))
			setup.add_child(tb)
		if Game.world_ready == "":
			var pw := _compact(UIKit.button("Place world", "", "place"))
			pw.name = "MenuPlaceWorld"
			(pw.get_meta("icon_glyph") as IconGlyph).color = UIKit.EMERALD
			pw.pressed.connect(func(): router.call("place_world_again"))
			setup.add_child(pw)
		if setup.get_child_count() > 0:
			col.add_child(setup)
		# every way to play goes through "Place world" first when the table hasn't been placed yet (router.play)
		var online := UIKit.button("Play Online", "PrimaryButton", "globe", 520)
		online.pressed.connect(func(): router.call("play", "online"))
		col.add_child(online)
		var vs := UIKit.button("Local Turn Based", "", "users", 520)
		vs.pressed.connect(func(): router.call("play", "pass_play"))
		col.add_child(vs)
		var play := UIKit.button("Play VS CPU", "", "robot", 520)
		play.pressed.connect(func(): router.call("play", "vs_ai"))
		col.add_child(play)
		var pr := UIKit.button("Practice", "", "practice", 520)
		pr.pressed.connect(func(): router.call("play", "practice"))
		col.add_child(pr)
		var row := UIKit.hbox(18)
		var st := UIKit.button("Settings", "GhostButton", "gear")
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.pressed.connect(func(): router.call("go", "settings"))
		var hp := UIKit.button("How to play", "GhostButton", "help")
		hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp.pressed.connect(func(): router.call("go", "help"))
		row.add_child(st)
		row.add_child(hp)
		col.add_child(row)
		var ver := Button.new()
		ver.flat = true
		ver.text = "v%s · tap 7× for developer tools" % Game.VERSION if Game.get_s("first_run") and Game.dev_tools() else "v%s" % Game.VERSION
		ver.add_theme_font_size_override("font_size", 22)
		ver.add_theme_color_override("font_color", Color(UIKit.MUTED, 0.6))
		ver.focus_mode = Control.FOCUS_NONE
		ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		ver.position = Vector2(110, -70)
		ver.pressed.connect(func():
			_taps += 1
			if _taps >= 7 and Game.dev_tools():
				_taps = 0
				router.call("open_debug"))
		add_child(ver)
		# bottom right: the XP chest and the packages waiting to be opened
		_corner = UIKit.hbox(16)
		_corner.anchor_left = 1.0
		_corner.anchor_right = 1.0
		_corner.anchor_top = 1.0
		_corner.anchor_bottom = 1.0
		_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_corner.offset_right = -100
		_corner.offset_bottom = -26
		_corner.alignment = BoxContainer.ALIGNMENT_END
		_corner.name = "MenuCorner"
		add_child(_corner)
		_fill_corner()
		Game.progress_changed.connect(_on_progress)
		UIKit.fade_in(left, 0.35, 30)
		UIKit.fade_in(col, 0.35, 30)
		UIKit.fade_in(_corner, 0.35, 30)
		_fit_column.call_deferred(left, col)

	var _xp_bar: RewardScreens.XpBar
	var _corner: HBoxContainer

	## A smaller button for the setup row (two share the column's width).
	func _compact(b: Button) -> Button:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 84
		b.add_theme_font_size_override("font_size", 28)
		return b

	func _on_progress() -> void:
		_xp_bar.set_xp(float(Game.xp()))
		_fill_corner()

	## The player's cue, table and balls in one card: tap to choose gear.
	func _gear_card() -> Button:
		var b := UIKit.button("Choose Gear", "", "", 560)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.custom_minimum_size = Vector2(560, 132)
		b.name = "GearCard"
		var pics := UIKit.hbox(10)
		pics.position = Vector2(14, 14)
		pics.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for kind in ["cue", "table", "balls"]:
			var t := TextureRect.new()
			t.texture = GearScreens.icon(kind, str(Game.get_s(Game.GEAR_KEYS[kind])))
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.custom_minimum_size = Vector2(104, 104)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pics.add_child(t)
		b.add_child(pics)
		b.pressed.connect(func(): router.call("go", "gear"))
		return b

	func _fill_corner() -> void:
		for c in _corner.get_children():
			c.queue_free()
		# the XP chest (hidden at the top level, where XP no longer counts)
		if Game.level() < XP.MAX_LEVEL:
			_corner.add_child(_chest_button())
		# packages: the next crate, "Packages" and how many, and "Ready!" or the time left, laid out like the XP chest
		# beside it (v1.1.15: "please label what the gift box is on the right side at the menu similarly to the xp
		# chests display")
		var q: Array = Game.packages()
		var pk := Button.new()
		pk.focus_mode = Control.FOCUS_NONE
		pk.custom_minimum_size = Vector2(360, 170)
		pk.name = "PackagesButton"
		pk.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var has := not q.is_empty()
		var pk_ready := has and Game.packages_ready() > 0
		var rc := GearScreens.rarity_color(XP.rarity_of_level(int(q[0]))) if has else Color(1, 1, 1, 0.14)
		for st in ["normal", "hover", "pressed", "focus"]:
			pk.add_theme_stylebox_override(st, UIKit.box(UIKit.BTN_BLACK, 22, 3 if has else 2, rc, Vector4(0, 0, 0, 0)))
		if has:
			var view := PackageView.new(XP.rarity_of_level(int(q[0])), 150.0)
			view.position = Vector2(6, 10)
			view.set_live(pk_ready)          # still unlocking: the crate keeps still, like the XP chest
			pk.add_child(view)
		else:
			var g2 := IconGlyph.make("gift", 84, Color(1, 1, 1, 0.3))
			g2.position = Vector2(39, 43)
			pk.add_child(g2)
		var pcol := UIKit.vbox(2)
		pcol.position = Vector2(160, 0)
		pcol.size = Vector2(186, 170)
		pcol.custom_minimum_size = Vector2(186, 170)
		pcol.alignment = BoxContainer.ALIGNMENT_CENTER
		pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pt := UIKit.label(L.t("Packages"), "H3Label")
		pt.name = "PackagesTitle"
		pt.clip_text = true
		pt.add_theme_color_override("font_color", rc if has else UIKit.TEXT)
		(func(): _fit_line(pt, 186.0)).call_deferred()       # (once it is in the tree and has its theme)
		pcol.add_child(pt)
		var ps: Label
		if not has:
			# two short lines at most (the game's labels leave a lot of room between lines; this keeps both in the tile)
			ps = UIKit.label(L.t("No packages to open"), "SmallLabel")
			ps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ps.max_lines_visible = 2
			ps.add_theme_constant_override("line_spacing", -16)
			ps.custom_minimum_size = Vector2(186, 0)
			ps.name = "PackagesStatus"
			pcol.add_theme_constant_override("separation", -8)
			pcol.add_child(ps)
			(func(): _fit_lines(ps, 2)).call_deferred()
		else:
			# "Ready!" or the time left, and how many are waiting
			var srow := UIKit.hbox(10)
			srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if pk_ready:
				ps = UIKit.label(L.t("Ready!"), "MutedLabel")
				ps.add_theme_color_override("font_color", UIKit.TEXT)
				ps.name = "PackagesStatus"
			else:
				ps = UIKit.label(XP.clock(Game.package_left(int(q[0]))), "MutedLabel")
				ps.name = "PackageWait"
			ps.clip_text = true
			ps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			srow.add_child(ps)
			var badge := UIKit.label("×%d" % q.size(), "MutedLabel")
			(func(): _fit_line(ps, 120.0)).call_deferred()       # (the room beside "×99")
			badge.name = "PackagesCount"
			badge.add_theme_color_override("font_color", rc)
			srow.add_child(badge)
			pcol.add_child(srow)
		pk.add_child(pcol)
		pk.pressed.connect(func(): router.call("go", "packages"))
		_corner.add_child(pk)
		# the times count down; the corner is rebuilt when the chest or a package becomes ready
		var chest_was := Game.chest_ready() or not Game.gift_chests().is_empty()
		var pk_was := Game.packages_ready()
		var tick := Timer.new()
		tick.wait_time = 1.0
		tick.autostart = true
		tick.timeout.connect(func():
			if (Game.chest_ready() or not Game.gift_chests().is_empty()) != chest_was or Game.packages_ready() != pk_was:
				_fill_corner()
				return
			var ct: Label = _corner.find_child("ChestTime", true, false)
			if ct and not chest_was:
				ct.text = XP.clock(Game.chest_left())
			var pw: Label = _corner.find_child("PackageWait", true, false)
			if pw and not Game.packages().is_empty():
				pw.text = XP.clock(Game.package_left(int(Game.packages()[0]))))
		_corner.add_child(tick)

	## The XP chest in the menu's corner: the chest itself, and "Ready!" or the time left.
	func _chest_button() -> Button:
		var ready := Game.chest_ready() or not Game.gift_chests().is_empty()     # (v1.1.15: gift chests open at once)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(360, 170)
		b.name = "XpChest"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, UIKit.box(UIKit.BTN_BLACK, 22, 3 if ready else 2,
				PackageView.XP_GOLD if ready else Color(1, 1, 1, 0.14), Vector4(0, 0, 0, 0)))
		var view := PackageView.xp_chest(150.0)
		view.position = Vector2(6, 10)
		view.set_live(ready)          # it sways when it can be opened, and keeps still while it waits
		b.add_child(view)
		var col := UIKit.vbox(2)
		col.position = Vector2(160, 0)
		col.size = Vector2(186, 170)
		col.custom_minimum_size = Vector2(186, 170)
		col.alignment = BoxContainer.ALIGNMENT_CENTER       # (centred, like the packages tile beside it: the titles line up)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UIKit.label(L.t("XP chest"), "H3Label")
		t.name = "ChestTitle"
		t.add_theme_color_override("font_color", PackageView.XP_GOLD)
		t.clip_text = true
		(func(): _fit_line(t, 186.0)).call_deferred()
		col.add_child(t)
		var st := UIKit.label(L.t("Ready!") if ready else XP.clock(Game.chest_left()), "MutedLabel")
		st.clip_text = true
		st.name = "ChestTime"
		if ready:
			(func(): _fit_line(st, 186.0)).call_deferred()
		if ready:
			st.add_theme_color_override("font_color", UIKit.TEXT)
		col.add_child(st)
		b.add_child(col)
		b.pressed.connect(func(): router.call("go", "chest"))
		return b

	## A one-line label in a corner tile: made smaller (down to `min_px`) when its words are wider than the room, so a
	## long language still shows the whole word (v1.1.15).
	## A wrapped label: made smaller (down to `min_px`) until its words take at most `lines` lines.
	static func _fit_lines(l: Label, lines: int, min_px := 18) -> void:
		if not is_instance_valid(l) or not l.is_inside_tree():
			return
		var px := l.get_theme_font_size("font_size")
		while l.get_line_count() > lines and px > min_px:
			px -= 2
			l.add_theme_font_size_override("font_size", px)

	static func _fit_line(l: Label, room: float, min_px := 22) -> void:
		if not is_instance_valid(l) or not l.is_inside_tree():
			return
		var f := l.get_theme_font("font")
		var px := l.get_theme_font_size("font_size")
		var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		if w > room and w > 0.0:
			l.add_theme_font_size_override("font_size", maxi(min_px, int(floor(px * room / w))))

	## Languages with long words make the button column wide. It must never run into the game's name on the
	## left, so when it would, the button text is made smaller until the column fits beside it.
	func _fit_column(left: Control, col: Control) -> void:
		# the game's name gives a little first, so there is always a clear gap beside the buttons (22 Nov: the longer
		# name "EMERALD ONLINE" came within 22 px of the Tamil buttons)
		var mt := left.find_child("MenuTitle", false, false) as Label
		if mt:
			# (the column keeps its width, so the gear card and the XP bar under the name stay as they are)
			left.custom_minimum_size.x = maxf(left.custom_minimum_size.x, left.get_combined_minimum_size().x)
			_fit_line(mt, size.x - 100.0 - col.get_combined_minimum_size().x - left.position.x - 72.0, 64)
		var room := size.x - 100.0 - (left.position.x + left.get_combined_minimum_size().x) - 48.0
		var need := col.get_combined_minimum_size().x
		if need <= room or room < 300.0:
			return
		var k := maxf(0.6, room / need)
		for n in col.find_children("*", "Button", true, false):
			var b := n as Button
			b.add_theme_font_size_override("font_size", int(floor(b.get_theme_font_size("font_size") * k)))
			b.custom_minimum_size.x = minf(b.custom_minimum_size.x, room)
			b.update_minimum_size()
		col.custom_minimum_size.x = minf(520.0, room)
		col.offset_left = col.offset_right - maxf(col.custom_minimum_size.x, col.get_combined_minimum_size().x)



## ------------------------------------------------------------ match setup (vs AI or pass & play)
class MatchSetup extends Screen:
	var vs_ai := true
	var _ai_level := 1
	var _name1: LineEdit
	var _name2: LineEdit
	var _lvl_row: HBoxContainer

	func _init(p_router: Node = null, p_vs_ai := true) -> void:
		super(p_router)
		vs_ai = p_vs_ai

	func _ready() -> void:
		scrim(0.6)
		var hd := header("Play VS CPU" if vs_ai else "Local Turn Based")
		# v1.1.15: put the table down again (or switch to Play in place) right here, always in sight
		hd.add_child(UIKit.spacer())
		hd.add_child(WorldScreens.world_button(router))
		content(170, 300)
		_ai_level = int(Game.get_s("ai_level"))
		var card := UIKit.panel("Card")
		var cv := UIKit.vbox(16)
		card.add_child(cv)
		if vs_ai:
			cv.add_child(UIKit.label("Difficulty", "H3Label"))
			_lvl_row = UIKit.hbox(14)
			var descs := ["Relaxed — misses often, only plays straight pots", "Solid club player — banks, spin and safeties", "Sharp — precise aim and real position play"]
			var desc := UIKit.label(descs[_ai_level], "MutedLabel")
			for i in 3:
				var b := UIKit.button(L.t(AIPlayer.NAMES[i]), "ChipButton", "", 220)
				b.toggle_mode = true
				b.button_pressed = i == _ai_level
				var idx := i
				b.pressed.connect(func():
					_ai_level = idx
					desc.text = descs[idx]
					for j in _lvl_row.get_child_count():
						(_lvl_row.get_child(j) as Button).button_pressed = j == idx)
				_lvl_row.add_child(b)
			cv.add_child(_lvl_row)
			cv.add_child(desc)
		cv.add_child(UIKit.label("Your name" if vs_ai else "Player names", "H3Label"))
		_name1 = LineEdit.new()
		_name1.text = Game.player_name(0)
		_name1.max_length = 14
		cv.add_child(_name1)
		_name2 = LineEdit.new()
		_name2.text = Game.player_name(1)
		_name2.max_length = 14
		if not vs_ai:
			cv.add_child(_name2)
		body.add_child(card)
		var rules := UIKit.label(L.t("8-ball. Each player has a %d:00 time bank for the whole match — it only runs while you aim. A chime, a vibration and a banner tell you when it's your turn.") % int(Game.get_s("time_bank_minutes")), "MutedLabel")
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(rules)
		var start := UIKit.button("Break!", "PrimaryButton", "play", 460)
		start.pressed.connect(_start)
		var cc := CenterContainer.new()
		cc.add_child(start)
		body.add_child(cc)

	func _start() -> void:
		if Game.world_ready == "":
			router.call("place_world_again")
			return
		Game.store_player_name(0, _name1.text)
		Game.store_player_name(1, _name2.text)
		Game.set_s("ai_level", _ai_level)
		router.call("start_match", {"mode": "versus", "vs_ai": vs_ai, "ai_level": _ai_level})


## ------------------------------------------------------------ cue control chooser
class ControlsScreen extends Screen:
	const INFO := {
		"pro_dial": {"icon": "target", "tag": "Maximum precision", "desc": "Ribbed aim wheel for 0.04° control (quick swipes turn faster), nudge arrows and a pull-down power piston."},
		"orbit_ring": {"icon": "recenter", "tag": "Swing it around", "desc": "Drag along a ring around the cue ball to swing the cue. Slide further out for a longer lever and finer aim."},
		"trackpad": {"icon": "sliders", "tag": "Laptop feel", "desc": "Slide on a touchpad: slow = ultra fine, quick swipes = big turns. Double-tap for a 4× precision lock."},
		"crank": {"icon": "gear", "tag": "Instrument grade", "desc": "Turn a crank in circles. Fine gear: one turn = 18°. Fast gear: one turn = 90°. Never lift your finger."},
		"ghost_target": {"icon": "ball", "tag": "Aim like a pro", "desc": "Place the ghost ball exactly where the cue ball should touch. Micro pad slides it in slow motion."},
		"thumbstick": {"icon": "move", "tag": "Controller style", "desc": "Push the stick and the cue keeps turning: a tiny push creeps at 0.02°/s, a full push swings 40°/s."},
		"slingshot": {"icon": "hand", "tag": "Fast & casual", "desc": "Touch anywhere, pull back, let go. Pull length is power. A second finger fine-tunes the aim."},
		"phone_cue": {"icon": "vibrate", "tag": "Most physical", "desc": "Your phone is the cue. Point to aim, hold STROKE and push the phone forward: your real stroke sets the power."},
	}

	func _ready() -> void:
		scrim(0.6)
		header("Cue Controls")
		content(170, 90)
		var note := UIKit.label("Every control has spin (drag the dot on the cue-ball pad), cue elevation for swerve, jump and massé shots, Aim Cam and top view. The precision family (first six) shares nudge arrows and the power piston; all of them except Pro Dial also aim with a tap on the table. Switch any time with the chip in a match.", "MutedLabel")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(note)
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 22)
		body.add_child(grid)
		var cards: Array[Control] = []
		for id in Game.SCHEMES:
			var c := _card(id)
			grid.add_child(c)
			cards.append(c)
		# Four cards per row in English. Languages with longer words get wider cards and fewer per row,
		# so nothing is ever pushed off the side of the screen.
		var widest := 412.0
		for c in cards:
			widest = maxf(widest, c.get_combined_minimum_size().x)
		var avail := get_viewport_rect().size.x - 2.0 * 90.0 - 24.0
		grid.columns = clampi(int((avail + 22.0) / (widest + 22.0)), 1, 4)
		var card_w := floorf((avail - 22.0 * (grid.columns - 1)) / grid.columns)
		for c in cards:
			c.custom_minimum_size.x = maxf(widest, card_w)

	func _card(id: String) -> Control:
		var selected := Game.scheme() == id
		var p := UIKit.panel("Card")
		p.custom_minimum_size = Vector2(412, 540)
		if selected:
			p.add_theme_stylebox_override("panel", UIKit.box(Color(0.09, 0.16, 0.22, 0.96), 26, 3, UIKit.EMERALD, Vector4(26, 22, 26, 22), 16))
		var v := UIKit.vbox(12)
		p.add_child(v)
		var inf: Dictionary = INFO[id]
		var top := UIKit.hbox(14)
		top.add_child(IconGlyph.make(inf["icon"], 64, UIKit.EMERALD if selected else UIKit.TEXT))
		var tv := UIKit.vbox(2)
		tv.add_child(UIKit.label(Game.scheme_name(id), "H2Label"))
		tv.add_child(UIKit.label(inf["tag"], "AccentLabel"))
		top.add_child(tv)
		v.add_child(top)
		var d := UIKit.label(inf["desc"], "MutedLabel")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 350
		v.add_child(d)
		v.add_child(UIKit.spacer(false))
		var use := UIKit.button("Selected" if selected else "Use this", "PrimaryButton" if not selected else "GhostButton", "check" if selected else "")
		use.disabled = selected
		use.pressed.connect(func():
			Game.set_s("control_scheme", id)
			router.call("go", "controls", true))
		v.add_child(use)
		var tr := UIKit.button("Try in practice", "GhostButton", "practice")
		tr.pressed.connect(func():
			Game.set_s("control_scheme", id)
			router.call("play", "practice"))
		v.add_child(tr)
		return p


## ------------------------------------------------------------ play online (matchmaking arrives with the game server)
class OnlineScreen extends Screen:
	## v1.1.15: after this long without an opponent, the match starts against a stand-in (see FillIn)
	const SEARCH_SECONDS := 60.0
	var search_seconds := SEARCH_SECONDS      # (tests shorten it)
	var _status: Label
	var _find: Button
	var _searching := false
	var _t0 := 0
	var _world_b: Button

	func _ready() -> void:
		scrim(0.6)
		var hd := header("Play Online")
		_world_b = WorldScreens.world_button(router)
		hd.add_child(UIKit.spacer())
		hd.add_child(_world_b)
		content(170, 300)
		var card := UIKit.panel("Card")
		var v := UIKit.vbox(18)
		card.add_child(v)
		var top := UIKit.hbox(18)
		top.add_child(IconGlyph.make("globe", 72, UIKit.EMERALD))
		_status = UIKit.label("Play 8-ball against another player.", "H3Label")
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(_status)
		v.add_child(top)
		var info := UIKit.label("You are matched with the next player who is looking for a game. Online matches give full XP.", "MutedLabel")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
		body.add_child(card)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 14)
		body.add_child(gap)
		_find = UIKit.button("Find a match", "PrimaryButton", "globe", 520)
		_find.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_find.pressed.connect(func():
			if not Net.signed_in():
				router.call("go", "account")     # v1.1.13: online play is with an account
			elif _searching:
				_cancel()
			elif Game.world_ready == "":
				router.call("place_world_again")
			else:
				_search())
		if not Net.signed_in():
			_status.text = "Create an account or log in to play online."
			_find.text = "Create account or log in"
		body.add_child(_find)
		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(0, 26)
		body.add_child(gap2)
		# the other ways to play, one tap away
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 22)
		row.add_theme_constant_override("v_separation", 18)
		var cpu := UIKit.button("Play VS CPU", "", "robot", 440)
		cpu.pressed.connect(func(): router.call("go", "vs_ai", true))
		row.add_child(cpu)
		var local := UIKit.button("Local Turn Based", "", "users", 440)
		local.pressed.connect(func(): router.call("go", "pass_play", true))
		row.add_child(local)
		body.add_child(row)

	func _say(text: String) -> void:
		_status.text = text

	func _search() -> void:
		_searching = true
		_find.text = "Cancel"
		_find.icon = null
		if _world_b:
			_world_b.disabled = true       # (the world can't change while looking for a match)
		_say("Checking your connection…")
		if not await Net.ensure_player():
			return _failed()
		var ping: int = await Net.measure_ping()
		if not is_inside_tree() or not _searching:
			return
		if ping >= 9999:
			return _failed()
		_t0 = Time.get_ticks_msec()
		while _searching and is_inside_tree():
			var body_d := Net.creds()
			body_d["ping"] = ping
			body_d["ver"] = Net.ONLINE_VERSION
			# the other phone shows this player's cue, and uses this player's table (if they break) or balls
			body_d["info"] = {"name": Game.player_name(0), "level": Game.level(), "cue": str(Game.get_s("cue_skin")),
				"table": str(Game.get_s("table_style")), "balls": str(Game.get_s("ball_set"))}
			var r: Dictionary = await Net.api("queue", body_d)
			if not is_inside_tree() or not _searching:
				return
			if not r.get("ok", false):
				return _failed()
			if r.has("match"):
				_searching = false
				var m := NetMatch.from_reply(r)
				Net.add_child(m)
				Sfx.play("turn_chime", 0.9)
				router.call("start_match", {"mode": "versus", "online": true, "net": m})
				return
			var waited := (Time.get_ticks_msec() - _t0) / 1000.0
			if waited >= search_seconds:
				return _stand_in()
			var line := L.t("Looking for an opponent… %d s") % int(waited)
			if int(r.get("other_ver", 0)) > 0:
				# someone is looking too, on a version that can't play this one (v1.1.13: was the reason two
				# phones never met)
				line += "\n" + L.t("Players waiting on another version: %d. Update both phones to the latest version.") % int(r["other_ver"])
			_say(line)
			await get_tree().create_timer(1.5).timeout

	## Nobody came within a minute: a match against a stand-in opponent, shown and paid like an online one.
	func _stand_in() -> void:
		_searching = false
		Net.api("leave", Net.creds(), "poll")
		var f := FillIn.make(Game.player_name(0), Game.level())
		Sfx.play("turn_chime", 0.9)
		router.call("start_match", {"mode": "versus", "vs_ai": true, "ai_level": int(f["ai_level"]), "fill_in": f})

	func _failed() -> void:
		_searching = false
		if _world_b:
			_world_b.disabled = false
		if is_inside_tree():
			_find.text = "Find a match"
			_say("The game server cannot be reached. Check your internet connection and try again.")

	func _cancel() -> void:
		_searching = false
		if _world_b:
			_world_b.disabled = false
		_find.text = "Find a match"
		_say("Play 8-ball against another player.")
		if Net.registered():
			Net.api("leave", Net.creds())

	func _exit_tree() -> void:
		if _searching:
			_searching = false
			if Net.registered():
				Net.api("leave", Net.creds())


## ------------------------------------------------------------ how to play
class HelpScreen extends Screen:
	func _ready() -> void:
		scrim(0.75)
		header("How to Play")
		content(170, 200)
		var sections := [
			["Placing the world", "Place world (on the main menu, and on the screen before a match) offers two ways. In front of me: point the phone at the floor or a desk and sweep it slowly until the table appears, then tap Place. It stays put in your room: walk all the way around it, lean in, crouch. Settings → World sets its size and height. Play in place: no camera, the table in its own world (the scene you picked in Choose Gear).\nAR uses Google ARCore (Google Play Services for AR). If AR can't start, the game tells you why and what to do; you can always play in place instead."],
			["Aiming", "Like real pool, only the cue shows your aim. If you want help, Settings → Aim guide adds a short line, a ghost ball, or a full prediction."],
			["Spin & elevation", "Drag the dot on the cue-ball pad: low = draw (comes back), high = follow, sides = english (changes rebound angles; the cue ball squirts slightly away from the side you hit).\nThe elevation slider raises the cue butt: 5-15° with side spin swerves the ball, 25-50° with a firm stroke makes the cue ball JUMP over blockers, and 60-75° with side spin bends it around balls (massé). Hit a jump too hard and the ball flies off the table."],
			["Balls off the table", "A ball that leaves the table is a foul. Object balls are re-spotted on the foot spot; the cue ball gives your opponent ball in hand; jumping the 8 off the table loses the game."],
			["Turns & clocks", "Every player has an 8-minute time bank for the whole match. It only runs while you are aiming. You'll hear a chime, feel a buzz and see a banner when it's your turn. Run out and you lose the frame."],
			["8-ball rules", "Break, then pot a ball to claim solids or stripes. Hit your own group first and make a ball or a cushion contact after hitting it. Fouls give your opponent ball in hand. Sink the 8 last — too early, or with a scratch, loses."],
			["Opponents", "The Easy CPU misses often and only takes straight pots. Medium plays banks, spin and safeties. Hard aims precisely and plays position for its next shot."],
		]
		for s in sections:
			var card := UIKit.panel("Card")
			var v := UIKit.vbox(8)
			card.add_child(v)
			v.add_child(UIKit.label(s[0], "H2Label"))
			var t := UIKit.label(s[1], "MutedLabel")
			if s[0] == "Placing the world" and OS.get_name() == "iOS":
				t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated, with the ARKit line
				t.text = ARCoreBridge.ios_help(s[1])
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(t)
			body.add_child(card)
