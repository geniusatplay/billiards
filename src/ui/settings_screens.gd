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
	var head := UIKit.label(label, "")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # (long words in some languages: never wider than the card)
	box.add_child(head)
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


## ------------------------------------------------------------ v1.1.15 options-menu pieces
## A card with an icon beside its title.
static func card(parent: Control, title: String, icon: String, tint := UIKit.EMERALD) -> VBoxContainer:
	var c := UIKit.panel("Card")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(14)
	c.add_child(v)
	var head := UIKit.hbox(14)
	head.add_child(IconGlyph.make(icon, 46, tint))
	var t := UIKit.label(title, "H2Label")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	v.add_child(head)
	parent.add_child(c)
	return v


## A slider with its name and value above it, and (optionally) what each end means under it.
## fmt turns the value into the text shown; set gets each new value.
static func big_slider(parent: Control, icon: String, label: String, value: float, lo: float, hi: float, step: float,
		fmt: Callable, set_value: Callable, ends := []) -> HSlider:
	var box := UIKit.vbox(2)
	var top := UIKit.hbox(12)
	top.add_child(IconGlyph.make(icon, 34, UIKit.MUTED))
	var l := UIKit.label(label, "H3Label")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	top.add_child(l)
	var val := UIKit.label(fmt.call(value), "AccentLabel")
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(val)
	box.add_child(top)
	var s := Widgets.TouchSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 56
	s.name = "Slider_" + label.replace(" ", "")
	s.value_changed.connect(func(x: float):
		val.text = fmt.call(x)
		set_value.call(x))
	box.add_child(s)
	if ends.size() == 2:
		var er := UIKit.hbox(0)
		var a := UIKit.label(ends[0], "SmallLabel")
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		er.add_child(a)
		er.add_child(UIKit.label(ends[1], "SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT))
		box.add_child(er)
	parent.add_child(box)
	return s


static func percent(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


## ------------------------------------------------------------ Settings
## v1.1.15 (Randy: "design a nice options menu with like music volume and game volume and world size ... the language
## should be an option when they click the language button, I want world height to be an option"). Two columns:
## Sound, Language, Matches, Account on the left; World and Cue & aiming on the right. The developer tools only in the
## testing builds.
class SettingsScreen extends MenuScreens.Screen:
	func _ready() -> void:
		scrim(0.78)
		header("Settings")
		content(170, 96)
		var S := SettingsScreens
		var in_match: bool = router != null and router.get("game") != null
		var cols := UIKit.hbox(26)
		cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(cols)
		var left := UIKit.vbox(22)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.0
		left.name = "SettingsLeft"
		cols.add_child(left)
		var right := UIKit.vbox(22)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 1.1
		right.name = "SettingsRight"
		cols.add_child(right)
		# ---- Sound
		var snd := S.card(left, "Sound", "sound")
		S.big_slider(snd, "music", "Music volume", float(Game.get_s("music_volume")), 0, 1, 0.05, S.percent,
			func(x: float): Game.set_s("music_volume", x))
		S.big_slider(snd, "sound", "Game sounds", float(Game.get_s("sfx_volume")), 0, 1, 0.05, S.percent,
			func(x: float): Game.set_s("sfx_volume", x))
		S.toggle(snd, "Music during matches", "music_in_game")
		S.toggle(snd, "Vibration", "haptics")
		# ---- Language: one button, the choices open over the screen
		var lng := S.card(left, "Language", "language")
		var lb := UIKit.button(WorldScreens.language_name(), "")
		lb.name = "SettingsLanguage"
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # (the language's own name)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.pressed.connect(func(): router.call("open_language"))
		lng.add_child(lb)
		# ---- Matches
		var m := S.card(left, "Matches", "flag")
		S.toggle(m, "Pass-the-phone screen between turns", "pass_curtain")
		S.toggle(m, "Reduced motion", "reduced_motion")
		# ---- Account
		SettingsScreens.account_card(left, router)
		# ---- World
		var w := S.card(right, "World", "place")
		var now := UIKit.hbox(14)
		var how := UIKit.label(_world_text(in_match), "MutedLabel")
		how.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED       # (already translated, two parts)
		how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.name = "WorldNow"
		now.add_child(how)
		if not in_match:
			var pw := UIKit.button("Place world", "", "place")
			pw.name = "SettingsPlaceWorld"
			pw.pressed.connect(func(): router.call("place_world_again"))
			now.add_child(pw)
		w.add_child(now)
		# (no "World background" here since 22 Nov: Play in place is the scene from Choose Gear, Randy: "scenes can be
		# chosen at equip gear")
		S.big_slider(w, "size", "World size", Game.world_size(), Game.WORLD_MIN, Game.WORLD_MAX, 0.01,
			func(x: float) -> String: return L.t("Life-size") if x >= 0.995 else "%d%%" % roundi(x * 100.0),
			func(x: float): Game.set_world_size(x), ["Mini", "Life-size"])
		S.big_slider(w, "height", "World height", float(Game.get_s("table_height")), 0.45, 1.1, 0.01,
			func(x: float) -> String: return "%d cm" % roundi(x * 100.0) if absf(x - 0.775) > 0.004 else L.t("Standard"),
			func(x: float): Game.set_s("table_height", x), ["Low", "High"])
		var wn := UIKit.label("World size and height are for the table in front of you (AR); height also sets how tall the table stands in Play in place.", "SmallLabel")
		wn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_child(wn)
		# ---- Cue & aiming
		var c := S.card(right, "Cue & aiming", "cue")
		S.choice(c, "Aim guide", "aim_guide", [0, 1, 2, 3], ["Off (real pool)", "Short line", "Ghost ball", "Full prediction"])
		S.big_slider(c, "target", "Fine-aim sensitivity", float(Game.get_s("fine_aim_scale")), 0.25, 3.0, 0.05,
			func(x: float) -> String: return "%.2f×" % x, func(x: float): Game.set_s("fine_aim_scale", x))
		S.toggle(c, "Left-handed layout", "left_handed")
		S.toggle(c, "Phone Cue: aim by pointing the phone", "phone_cue_follow_phone")
		if not in_match:
			var gear := UIKit.button("Choose Gear", "", "kit")
			gear.pressed.connect(func(): router.call("go", "gear"))
			c.add_child(gear)
		# ---- developer tools (the testing builds only; Randy: "keep the debug menu for now")
		if Game.dev_tools():
			var dv := S.card(body, "Developer tools", "debug", UIKit.GOLD)
			var dn := UIKit.label("Testing builds only: the store versions have no debug menu.", "SmallLabel")
			dn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dv.add_child(dn)
			var dbg := UIKit.button("Open debug menu", "GhostButton", "debug")
			dbg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			dbg.pressed.connect(func(): router.call("open_debug"))
			dv.add_child(dbg)
		# v1.1.15: the privacy policy (both stores ask for it inside the app too)
		var pp := UIKit.button("Privacy policy", "GhostButton", "lock")
		pp.name = "PrivacyPolicy"
		pp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pp.pressed.connect(func(): OS.shell_open(Net.PRIVACY_URL))
		body.add_child(pp)
		var credits := UIKit.label(L.t("%s v%s · © Emerald Vortex Games LLC · Fonts: Outfit and Noto Sans (SIL Open Font License). Table sound recordings: \"Pool And Billiards SFX\" by Suraj Kispotta (CC0).") % [Game.TITLE, Game.VERSION], "SmallLabel")
		credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(credits)
		_fit_columns.call_deferred(cols, left, right)

	## Narrow screens (or long words): one column under the other. (The room is the scroll area's width: the list
	## itself grows with what is too wide for it.)
	func _fit_columns(cols: HBoxContainer, left: Control, right: Control) -> void:
		if not is_inside_tree():
			return
		var room: float = (body.get_parent() as Control).size.x
		if room <= 0.0 or left.get_combined_minimum_size().x + right.get_combined_minimum_size().x + 26.0 <= room - 24.0:
			return
		var v := UIKit.vbox(22)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(v)
		body.move_child(v, cols.get_index())
		for col in [right, left]:
			cols.remove_child(col)
			v.add_child(col)
		cols.queue_free()

	func _world_text(in_match: bool) -> String:
		var t := "In your room (AR)" if Game.world_ready == "ar" else ("Play in place" if Game.world_ready == "studio" else "Not placed yet")
		if in_match:
			t = "In your room (AR)" if router.call("view_is_ar") else "Play in place"
		return L.t("Now: %s") % L.t(t)


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
		# v1.1.15 (Randy: "add a debug menu for zoom which sets the default placement backwords or forwards of the
		# game camera for ar & play in place")
		var cam := S.section(body, "Camera zoom")
		S.slider(cam, "Camera distance (1 = as designed; Play in place and the AR aim view)", "cam_zoom", 0.5, 2.0, 0.05, "%.2fx")
		S.slider(cam, "AR table placed further (+) or nearer (−) than where the phone points (m)", "ar_push", -1.0, 1.5, 0.05, "%+.2f m")
		var cz := UIKit.button("Reset camera zoom", "ChipButton", "refresh")
		cz.pressed.connect(func():
			Game.set_s("cam_zoom", 1.0)
			Game.set_s("ar_push", 0.0)
			_refresh())
		cam.add_child(cz)
		# v1.1.15: the five tutorials, to try them on a phone before one is picked (testing builds only)
		var tu := S.section(body, "Tutorial")
		var tnames := ["The game's pick"]
		for tv in Tutorial.VERSIONS:
			tnames.append(str(tv["name"]))
		S.choice(tu, "Version", "tut_version", [-1, 0, 1, 2, 3, 4], tnames)
		var tp := UIKit.button("Play it now", "ChipButton", "play")
		tp.pressed.connect(func(): router.call("debug_play_tutorial"))
		tu.add_child(tp)
		# v1.1.15: how this phone draws the XP chest and the packages (Randy: "the XP chests aren't visible")
		var pk := S.section(body, "Package pictures")
		var pk_l := UIKit.label({-1: "Not drawn yet this launch (open the main menu first)",
			0: "3D (the phone draws them)", 1: "Baked pictures: %s" % PackageView.flat_reason}[PackageView.flat_mode], "MutedLabel")
		pk_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pk.add_child(pk_l)
		var ar := S.section(body, "AR")
		S.toggle(ar, "Scene background in AR (a different one every match)", "ar_background")
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
		S.toggle(dg, "Stand-ins look like real adverts (sample adverts)", "ad_sample")
		# v1.1.15: one sample advert of each kind, at once
		var ad_row := HFlowContainer.new()
		ad_row.add_theme_constant_override("h_separation", 12)
		ad_row.add_theme_constant_override("v_separation", 12)
		for am in [["Sample advert: between matches", "after_match"], ["Sample advert: XP chest (rewarded)", "xp_chest"]]:
			var ab := UIKit.button(am[0], "ChipButton", "play")
			ab.pressed.connect(func(): Ads.preview(am[1]))
			ad_row.add_child(ab)
		dg.add_child(ad_row)
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
