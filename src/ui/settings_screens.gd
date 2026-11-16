class_name SettingsScreens
extends RefCounted
## Settings + the Debug menu (live tuning of table, physics, AR and gameplay).


static func section(parent: Control, title: String) -> VBoxContainer:
	var card := UIKit.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(10)
	card.add_child(v)
	v.add_child(UIKit.label(title, "H2Label"))
	parent.add_child(card)
	return v


## Slider bound to a setting (or physics key with prefix "phys:").
static func slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f", on_change: Callable = Callable()) -> HSlider:
	var row := UIKit.hbox(18)
	var l := UIKit.label(label, "")
	l.custom_minimum_size.x = 360
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var s := Widgets.TouchSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 56
	var is_phys := key.begins_with("phys:")
	var k := key.substr(5) if is_phys else key
	s.value = Game.get_p(k) if is_phys else float(Game.get_s(k))
	var val := UIKit.label(fmt % s.value, "AccentLabel")
	val.custom_minimum_size.x = 150
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x: float):
		val.text = fmt % x
		if is_phys:
			Game.set_p(k, x)
		else:
			Game.set_s(k, x)
		if on_change.is_valid():
			on_change.call(x))
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)
	return s


static func toggle(parent: Control, label: String, key: String, on_change: Callable = Callable()) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = bool(Game.get_s(key))
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool):
		Game.set_s(key, on)
		Sfx.ui("toggle")
		if on_change.is_valid():
			on_change.call(on))
	parent.add_child(c)
	return c


static func choice(parent: Control, label: String, key: String, options: Array, names: Array) -> Control:
	var box := UIKit.vbox(8)
	box.add_child(UIKit.label(label, ""))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := ButtonGroup.new()
	for i in options.size():
		var b := UIKit.button(names[i], "ChipButton")
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = Game.get_s(key) == options[i]
		var v = options[i]
		b.pressed.connect(func(): Game.set_s(key, v))
		row.add_child(b)
	box.add_child(row)
	parent.add_child(box)
	return box


## v1.1.13: the account card (who is signed in; sign out; delete the account for good - both app stores ask for
## that in any game with accounts).
static func account_card(parent: Control, router: Node) -> void:
	var acc := section(parent, "Account")
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 14)
	buttons.add_theme_constant_override("v_separation", 12)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Net.signed_in():
		acc.add_child(UIKit.label("Not signed in", "MutedLabel"))
		var make := UIKit.button("Create account", "PrimaryButton", "user", 360)
		make.pressed.connect(func(): router.call("go", "account"))
		buttons.add_child(make)
		var login := UIKit.button("Log in", "", "", 300)
		login.pressed.connect(func(): router.call("go", "account_login"))
		buttons.add_child(login)
		acc.add_child(buttons)
		return
	var who := UIKit.label(L.t("Signed in as %s") % Net.email(), "")
	who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # already translated, with the email in it
	acc.add_child(who)
	var out := UIKit.button("Sign out", "", "", 300)
	out.pressed.connect(func():
		Sfx.ui("tap")
		Net.log_out()
		router.call("toast", L.t("Signed out. Your progress stays with your account."))
		router.call("go", "settings", true))
	buttons.add_child(out)
	var del := UIKit.button("Delete account", "GhostButton", "", 300)
	buttons.add_child(del)
	acc.add_child(buttons)
	# deleting asks for the password once more, right here
	var box := UIKit.vbox(10)
	box.visible = false
	var note := UIKit.label("This deletes your account and its progress for good. Enter your password to confirm.", "SmallLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var row := UIKit.hbox(14)
	var pw := LineEdit.new()
	pw.secret = true
	pw.placeholder_text = "Password"
	pw.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	pw.custom_minimum_size = Vector2(0, 76)
	pw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pw)
	var go := UIKit.button("Delete for good", "GhostButton", "", 340)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		go.add_theme_color_override(c, UIKit.CORAL)       # a warning colour, not the green "go" button
	row.add_child(go)
	box.add_child(row)
	var msg := UIKit.label("", "SmallLabel")
	msg.add_theme_color_override("font_color", UIKit.CORAL)
	box.add_child(msg)
	acc.add_child(box)
	del.pressed.connect(func():
		Sfx.ui("toggle")
		box.visible = not box.visible)
	go.pressed.connect(func():
		if pw.text.length() < 6:
			msg.text = "Wrong email or password."
			return
		go.disabled = true
		msg.text = "Please wait…"
		DisplayServer.virtual_keyboard_hide()
		var r: Dictionary = await Net.delete_account(pw.text)
		if not is_instance_valid(go):
			return
		go.disabled = false
		if r.get("ok", false):
			router.call("toast", L.t("Account deleted."))
			router.call("go", "settings", true)
		else:
			msg.text = Net.account_error(r))


## ------------------------------------------------------------ Settings
class SettingsScreen extends MenuScreens.Screen:
	func _ready() -> void:
		scrim(0.72)
		header("Settings")
		content(170, 200)
		SettingsScreens.account_card(body, router)
		var lang := SettingsScreens.section(body, "Language")
		var lrow := HFlowContainer.new()
		lrow.add_theme_constant_override("h_separation", 12)
		lrow.add_theme_constant_override("v_separation", 10)
		lrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lg := ButtonGroup.new()
		var saved := str(Game.get_s("language"))
		for l in [["auto", "Automatic"]] + Loc.LANGS:
			var b := UIKit.button(l[1], "ChipButton")
			b.toggle_mode = true
			b.button_group = lg
			b.button_pressed = saved == l[0] or (l[0] == "auto" and not saved in Loc.codes())
			if l[0] != "auto":
				b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # each language keeps its own name
			var code: String = l[0]
			b.pressed.connect(func():
				Sfx.ui("toggle")
				Loc.set_language(code))
			lrow.add_child(b)
		lang.add_child(lrow)
		var a := SettingsScreens.section(body, "Sound & feel")
		SettingsScreens.slider(a, "Effects volume", "sfx_volume", 0, 1, 0.05)
		SettingsScreens.slider(a, "Music volume", "music_volume", 0, 1, 0.05)
		SettingsScreens.toggle(a, "Music during the game (menus always have music)", "music_in_game")
		SettingsScreens.toggle(a, "Vibration (turn alerts, pots, strikes)", "haptics")
		SettingsScreens.toggle(a, "Reduced motion", "reduced_motion")
		var c := SettingsScreens.section(body, "Cue & aiming")
		SettingsScreens.choice(c, "Cue control", "control_scheme", Game.SCHEMES, Game.SCHEMES.map(func(k): return Game.scheme_name(k)))
		SettingsScreens.choice(c, "Aim guide", "aim_guide", [0, 1, 2, 3], ["Off (real pool)", "Short line", "Ghost ball", "Full prediction"])
		SettingsScreens.slider(c, "Fine-aim sensitivity", "fine_aim_scale", 0.25, 3.0, 0.05, "%.2fx")
		SettingsScreens.toggle(c, "Left-handed layout", "left_handed")
		SettingsScreens.toggle(c, "Phone Cue: aim by pointing the phone", "phone_cue_follow_phone")
		var l := SettingsScreens.section(body, "Look")
		# only what the player owns (everything else is on the Choose Gear page, with its lock)
		var own_cues := Catalog.CUES.filter(func(e): return Game.owns("cue", str(e["id"])))
		var own_tables := Catalog.TABLES.filter(func(e): return Game.owns("table", str(e["id"])))
		SettingsScreens.choice(l, "Cue", "cue_skin", Catalog.ids(own_cues), Catalog.names(own_cues))
		SettingsScreens.choice(l, "Table", "table_style", Catalog.ids(own_tables), Catalog.names(own_tables))
		var scenes := Catalog.SCENES.filter(func(e): return e.get("ready", true) and Game.owns("scene", str(e["id"])))
		SettingsScreens.choice(l, "Scene (Studio view)", "scene", Catalog.ids(scenes), Catalog.names(scenes))
		var own_balls := Catalog.BALLS.filter(func(e): return Game.owns("balls", str(e["id"])))
		SettingsScreens.choice(l, "Ball set", "ball_set", Catalog.ids(own_balls), Catalog.names(own_balls))
		var r := SettingsScreens.section(body, "Augmented reality")
		SettingsScreens.choice(r, "View", "ar_mode", ["auto", "studio"], ["AR (walk around)", "Studio (no camera)"])
		SettingsScreens.choice(r, "Surface", "surface", ["desk", "floor"], ["Desk (mini)", "Floor (life-size)"])
		SettingsScreens.toggle(r, "Scene background in AR (a different one every match)", "ar_background")
		var bg_note := UIKit.label("The scene replaces the camera picture once the table is placed. You will not see your room: play seated, or keep the floor around you clear.", "SmallLabel")
		bg_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(bg_note)
		var m := SettingsScreens.section(body, "Matches")
		SettingsScreens.toggle(m, "Pass-the-phone screen between turns", "pass_curtain")
		var dbg := UIKit.button("Open debug menu", "GhostButton", "debug")
		dbg.pressed.connect(func(): router.call("open_debug"))
		body.add_child(dbg)
		var credits := UIKit.label(L.t("%s v%s · © Emerald Vortex Games LLC · Fonts: Outfit and Noto Sans (SIL Open Font License). Table sound recordings: \"Pool And Billiards SFX\" by Suraj Kispotta (CC0).") % [Game.TITLE, Game.VERSION], "SmallLabel")
		credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(credits)


## ------------------------------------------------------------ Debug menu (overlay panel, works in-match)
class DebugMenu extends Control:
	var router: Node
	var body: VBoxContainer

	func _init(p_router: Node) -> void:
		router = p_router
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.35)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
		var panel := UIKit.panel()
		panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		panel.offset_left = -1020
		panel.offset_top = 20
		panel.offset_bottom = -20
		panel.offset_right = -20
		add_child(panel)
		var outer := UIKit.vbox(12)
		panel.add_child(outer)
		var head := UIKit.hbox(16)
		head.add_child(IconGlyph.make("debug", 48, UIKit.EMERALD))
		var t := UIKit.label("Debug Menu", "H1Label")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var close := UIKit.icon_button("close", 84, "Close")
		close.pressed.connect(func(): router.call("close_debug"))
		head.add_child(close)
		outer.add_child(head)
		outer.add_child(UIKit.label("Changes apply live and are saved.", "SmallLabel"))
		var sc := UIKit.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		outer.add_child(sc)
		body = UIKit.vbox(18)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(body)
		_fill()

	func _fill() -> void:
		var S := SettingsScreens
		var tb := S.section(body, "Table")
		S.slider(tb, "Table length (m, nose to nose)", "table_length", 1.2, 3.2, 0.01, "%.2f m")
		S.slider(tb, "Table width (m)", "table_width", 0.6, 1.6, 0.01, "%.2f m")
		S.slider(tb, "Table height (m, life-size)", "table_height", 0.3, 1.2, 0.01, "%.2f m")
		S.slider(tb, "Rail height (m)", "rail_height", 0.03, 0.08, 0.001, "%.3f m")
		S.slider(tb, "Pocket size", "pocket_scale", 0.7, 1.8, 0.01, "%.2fx")
		S.slider(tb, "Ball radius (m)", "ball_radius", 0.02, 0.04, 0.0005, "%.4f m")
		S.toggle(tb, "Show legs", "show_legs")
		var presets := HFlowContainer.new()
		presets.add_theme_constant_override("h_separation", 12)
		for p in [["7 ft", 1.98, 0.99], ["8 ft", 2.3368, 1.1684], ["9 ft", 2.54, 1.27], ["Snooker-ish", 3.2, 1.6]]:
			var b := UIKit.button(p[0], "ChipButton")
			var L: float = p[1]
			var W: float = p[2]
			b.pressed.connect(func():
				Game.set_s("table_length", L)
				Game.set_s("table_width", W)
				_refresh())
			presets.add_child(b)
		var rt := UIKit.button("Reset table", "ChipButton")
		rt.pressed.connect(func():
			Game.reset_table()
			_refresh())
		presets.add_child(rt)
		tb.add_child(presets)
		S.choice(tb, "Style", "table_style", Catalog.ids(Catalog.TABLES), Catalog.names(Catalog.TABLES))
		tb.add_child(UIKit.label("Table changes rebuild the 3D table now; the physics uses them from the next rack.", "SmallLabel"))
		var ar := S.section(body, "AR")
		S.slider(ar, "AR scale — mini", "ar_scale_desk", 0.08, 0.6, 0.01, "%.2fx")
		S.slider(ar, "AR scale — life-size", "ar_scale_floor", 0.3, 1.3, 0.01, "%.2fx")
		S.toggle(ar, "Floating table (hovers, no legs) instead of standing on the floor", "ar_float")
		S.slider(ar, "Float distance — mini (m)", "float_dist_desk", 0.3, 2.0, 0.05, "%.2f m")
		S.slider(ar, "Float distance — life-size (m)", "float_dist_floor", 1.0, 4.0, 0.05, "%.2f m")
		S.slider(ar, "Below eye level — mini (m)", "float_drop_desk", 0.0, 0.8, 0.02, "%.2f m")
		S.slider(ar, "Below eye level — life-size (m)", "float_drop_floor", 0.0, 1.2, 0.02, "%.2f m")
		S.slider(ar, "Phone Cue gyro mapping (-1 auto, 0-47)", "gyro_mapping", -1, 47, 1, "%d")
		S.slider(ar, "Phone Cue gravity mapping (-1 auto, 0-7)", "gravity_mapping", -1, 7, 1, "%d")
		var st := UIKit.label("", "SmallLabel")
		st.text = router.call("tracking_status")
		ar.add_child(st)
		var recal := UIKit.button("Recalibrate sensors", "ChipButton", "refresh")
		recal.pressed.connect(func(): router.call("recalibrate"))
		ar.add_child(recal)
		var ph := S.section(body, "Physics")
		S.slider(ph, "Sliding friction (cloth)", "phys:mu_slide", 0.05, 0.4, 0.005)
		S.slider(ph, "Rolling resistance", "phys:mu_roll", 0.002, 0.04, 0.0005, "%.4f")
		S.slider(ph, "Spin decay", "phys:mu_spin", 0.002, 0.06, 0.001, "%.3f")
		S.slider(ph, "Ball restitution", "phys:e_ball", 0.7, 1.0, 0.005, "%.3f")
		S.slider(ph, "Ball-ball friction at 1 m/s (throw)", "phys:mu_ball", 0.0, 0.15, 0.002, "%.3f")
		S.slider(ph, "Cushion restitution", "phys:e_cushion", 0.5, 0.98, 0.01)
		S.slider(ph, "Cushion friction (english)", "phys:mu_cushion", 0.0, 0.5, 0.01)
		S.slider(ph, "Max cue speed (m/s)", "phys:max_speed", 3, 14, 0.1, "%.1f")
		S.slider(ph, "Break shot: times the max speed", "phys:break_scale", 1, 3, 0.05, "%.2f×")
		S.slider(ph, "Squirt (deg at max side)", "phys:squirt_deg", 0, 4, 0.1, "%.1f°")
		S.slider(ph, "Bed bounce (jump shots)", "phys:e_table", 0.2, 0.8, 0.01)
		S.slider(ph, "Cushion top (ball radii)", "phys:cushion_top", 1.3, 2.2, 0.05)
		S.slider(ph, "Physics rate (Hz)", "phys:substep_hz", 120, 960, 60, "%d")
		var rp := UIKit.button("Reset physics", "ChipButton", "refresh")
		rp.pressed.connect(func():
			Game.reset_physics()
			_refresh())
		ph.add_child(rp)
		var gp := S.section(body, "Gameplay")
		S.slider(gp, "Time bank (minutes)", "time_bank_minutes", 0.5, 20, 0.5, "%.1f")
		S.choice(gp, "AI level", "ai_level", [0, 1, 2], AIPlayer.NAMES)
		S.toggle(gp, "Cue lifts over balls (never passes through one)", "cue_over_balls")
		S.toggle(gp, "Change cue, table and balls during a match (testing)", "gear_drawer")
		S.choice(gp, "Aim guide", "aim_guide", [0, 1, 2, 3], ["Off", "Short line", "Ghost ball", "Full"])
		var rs := UIKit.button("Reset stats", "ChipButton", "close")
		rs.pressed.connect(func():
			Game.reset_stats()
			router.call("toast", "Stats reset"))
		gp.add_child(rs)
		var dg := S.section(body, "Diagnostics")
		S.toggle(dg, "FPS counter (top of the screen)", "fps_counter")
		S.toggle(dg, "AR tracking status line", "show_fps")
		S.toggle(dg, "Unlock every cue, table, ball set and scene (testing)", "unlock_all")
		S.toggle(dg, "Show advert stand-ins (adverts are off)", "ad_standins")
		var xp_row := UIKit.hbox(12)
		for amount in [100, 1000, 5000]:
			var xb := UIKit.button("+%d XP" % amount, "ChipButton")
			xb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			xb.pressed.connect(func(): Game.add_xp(amount))
			xp_row.add_child(xb)
		var wipe := UIKit.button("Reset levels and gear", "ChipButton")
		wipe.pressed.connect(func():
			Game.progress = Game.fresh_progress()
			Game._fix_gear()
			Game.progress_changed.emit()
			Game.request_save())
		xp_row.add_child(wipe)
		dg.add_child(xp_row)
		# no waiting while testing: every package unlocked and the XP chest ready
		var now_b := UIKit.button("Packages and XP chest: ready now", "ChipButton", "clock")
		now_b.pressed.connect(func():
			Game.progress["pk_time"] = {}
			Game.progress["chest_at"] = 0
			Game.progress_changed.emit()
			Game.request_save()
			Sfx.ui("toggle"))
		dg.add_child(now_b)

	func _refresh() -> void:
		for c in body.get_children():
			c.queue_free()
		_fill()
