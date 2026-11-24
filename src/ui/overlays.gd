class_name Overlays
extends RefCounted
## Pause menu and the match results screen.


class PauseMenu extends Control:
	var router: Node

	func _init(p_router: Node) -> void:
		router = p_router
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS

	var _side: VBoxContainer

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.04, 0.08, 0.7)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
		# the match's own top bar (names, clocks, title) is dimmed right down so the heading does not fight with it
		var band := TextureRect.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(0.02, 0.04, 0.08, 0.92))
		gr.set_color(1, Color(0.02, 0.04, 0.08, 0.0))
		gr.set_offset(0, 0.55)
		var gt := GradientTexture2D.new()
		gt.gradient = gr
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		band.texture = gt
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		band.offset_bottom = 300
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		var all := UIKit.vbox(14)
		all.add_child(UIKit.label("PAUSED", "H1Label", HORIZONTAL_ALIGNMENT_CENTER))
		var cols := UIKit.hbox(28)
		cols.alignment = BoxContainer.ALIGNMENT_CENTER
		all.add_child(cols)
		# ---- left: the match
		var v := UIKit.vbox(14)
		v.custom_minimum_size = Vector2(560, 0)
		cols.add_child(v)
		# 24 Nov (Randy: "at the settings page, Main Menu should be on top"): the way out first; leaving a match that
		# pays XP asks first (main.quit_match -> Overlays.Confirm)
		var items := [["Main menu", "home", "quit_match", "GhostButton"], ["Resume", "play", "resume", "PrimaryButton"],
			["Restart", "refresh", "restart", ""]]
		if router.call("is_online"):
			items.remove_at(2)      # an online match cannot be restarted, and the clock keeps running
			items.append(["Report or block player", "flag", "player_card", ""])     # (24 Nov 2026: app store rules)
		items.append([_music_text(), "sound", "toggle_music", ""])
		items.append(["Settings", "gear", "settings", ""])
		if Game.dev_tools():
			items.append(["Debug menu", "debug", "open_debug", ""])      # (not in the store builds)
		for it in items:
			var b := UIKit.button(it[0], it[3], it[1], 560)
			b.name = "Pause_" + str(it[2])
			var act: String = it[2]
			b.pressed.connect(func():
				if act == "toggle_music":
					Game.set_s("music_in_game", not bool(Game.get_s("music_in_game")))
					b.text = _music_text()
				else:
					router.call(act))
			v.add_child(b)
		# ---- right: where the table is and what is round it (changes apply at once, behind this menu)
		var card := UIKit.panel("Card")
		card.name = "ViewCard"
		card.custom_minimum_size = Vector2(660, 0)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_side = UIKit.vbox(8)
		card.add_child(_side)
		cols.add_child(card)
		_fill_side()
		UIKit.center_in(self, all)
		UIKit.fade_in(all, 0.2, 20)

	func _music_text() -> String:
		return L.t("Music during the game: On" if Game.get_s("music_in_game") else "Music during the game: Off")

	## A button of the card, a little lower than the menu's own so the whole card fits a phone screen.
	func _lower(b: Button) -> Button:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var sb: StyleBox = b.get_theme_stylebox(st).duplicate()
			sb.content_margin_top = 12
			sb.content_margin_bottom = 12
			b.add_theme_stylebox_override(st, sb)
		return b

	## Two chips of which one is lit; `pick` gets 0 or 1.
	func _pair(title: String, names: Array, lit: int, pick: Callable) -> void:
		_side.add_child(UIKit.label(title, ""))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_constant_override("v_separation", 10)
		var g := ButtonGroup.new()
		for i in 2:
			var b := UIKit.button(names[i], "ChipButton")
			b.toggle_mode = true
			b.button_group = g
			b.button_pressed = i == lit
			var idx := i
			b.pressed.connect(func(): pick.call(idx))
			row.add_child(b)
		_side.add_child(row)

	func _fill_side() -> void:
		for c in _side.get_children():
			_side.remove_child(c)
			c.queue_free()
		var ar: bool = router.call("view_is_ar")
		# v1.1.15: the same two ways as the main menu's "Place world"
		_pair("World", ["In front of me (AR)", "Play in place"], 0 if ar else 1, func(i: int):
			router.call("switch_view", "auto" if i == 0 else "studio")
			if is_inside_tree() and not is_queued_for_deletion():
				_fill_side())
		if ar:
			_pair("World size", ["Mini", "Life-size"], 1 if Game.get_s("surface") == "floor" else 0, func(i: int):
				if i == 1:
					Game.set_world_size(maxf(float(Game.get_s("ar_scale_floor")), Game.WORLD_FLOOR_FROM))
				else:
					Game.set_world_size(minf(float(Game.get_s("ar_scale_desk")), Game.WORLD_FLOOR_FROM - 0.01)))
			if router.call("can_move_table"):
				var mv := UIKit.button("Move / raise / lower table", "", "move")
				mv.pressed.connect(func(): router.call("move_table"))
				_side.add_child(_lower(mv))
			var again := UIKit.button("Place the table again", "", "recenter")
			again.pressed.connect(func(): router.call("replace_table"))
			_side.add_child(_lower(again))
			if Game.dev_tools():      # (a developer option since v1.1.15: Play in place is the way to a world background)
				SettingsScreens.toggle(_side, "Scene background in AR", "ar_background", func(_on: bool): _fill_side.call_deferred())
		if not ar or bool(Game.get_s("ar_background")):
			_scene_row()

	## Scene: its picture and name between two arrows; a tap on an arrow shows the next one at once.
	func _scene_row() -> void:
		var list: Array = router.call("pause_scenes")
		if list.is_empty():
			return
		_side.add_child(UIKit.label("Scene", ""))
		var ids: Array = Catalog.ids(list)
		var at := maxi(0, ids.find(str(router.call("pause_scene_id"))))
		var row := UIKit.hbox(14)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var prev := UIKit.icon_button("chev_left", 80)
		var next := UIKit.icon_button("chev_right", 80)
		prev.name = "ScenePrev"
		next.name = "SceneNext"
		var mid := UIKit.hbox(16)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.custom_minimum_size = Vector2(108, 108)
		mid.add_child(pic)
		var names := UIKit.vbox(2)
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.custom_minimum_size = Vector2(250, 0)
		var nm := UIKit.label("", "H3Label")
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # scene names are proper names
		nm.clip_text = true
		names.add_child(nm)
		var count := UIKit.label("", "SmallLabel")
		count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		names.add_child(count)
		mid.add_child(names)
		var show := func(i: int):
			var e: Dictionary = list[i]
			pic.texture = GearScreens.icon("scene", str(e["id"]))
			nm.text = str(e["name"])
			count.text = "%d / %d" % [i + 1, list.size()]
		var cur := [at]
		var step := func(d: int):
			cur[0] = posmod(cur[0] + d, list.size())
			show.call(cur[0])
			router.call("set_pause_scene", str(list[cur[0]]["id"]))
		prev.pressed.connect(func(): step.call(-1))
		next.pressed.connect(func(): step.call(1))
		prev.disabled = list.size() < 2
		next.disabled = list.size() < 2
		show.call(at)
		row.add_child(prev)
		row.add_child(mid)
		row.add_child(next)
		_side.add_child(row)


class Results extends Control:
	var router: Node
	var res: Dictionary

	func _init(p_router: Node, p_res: Dictionary) -> void:
		router = p_router
		res = p_res
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.04, 0.08, 0.7)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
		var card := UIKit.panel()
		card.custom_minimum_size = Vector2(980, 0)
		var v := UIKit.vbox(10 if res.has("xp") else 20)
		card.add_child(v)
		var w: String = res.get("winner_name", "")
		var online: bool = res.get("online", false)
		var solo: bool = res.get("vs_ai", false) or online      # one player on this phone: "you win" / "you lose"
		var you_lost: bool = solo and int(res.get("winner", 0)) != int(res.get("seat", 0))
		var sub := L.t("8-BALL · VS %s CPU") % L.up(L.t(AIPlayer.NAMES[int(res.get("ai_level", 1))])) if res.get("vs_ai", false) else ("8-BALL · ONLINE" if online else "8-BALL · LOCAL TURN BASED")
		v.add_child(UIKit.label(sub, "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER))
		var title2 := UIKit.label("YOU LOSE" if you_lost else L.up("YOU WIN!" if solo else L.t("%s WINS!") % w), "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
		title2.add_theme_font_size_override("font_size", 54 if res.has("xp") else 80)
		title2.add_theme_color_override("font_color", UIKit.CORAL if you_lost else UIKit.EMERALD)
		v.add_child(title2)
		var shots := int(res.get("shots", 0))
		var why := L.t(String(res.get("reason", "")))
		v.add_child(UIKit.label(L.t("%s  ·  1 shot") % why if shots == 1 else L.t("%s  ·  %d shots") % [why, shots], "H3Label", HORIZONTAL_ALIGNMENT_CENTER))
		if res.has("xp"):
			_xp_block(v)
		var row2 := UIKit.hbox(18)
		row2.alignment = BoxContainer.ALIGNMENT_CENTER
		var re := UIKit.button("New opponent" if online else "Rematch", "PrimaryButton", "globe" if online else "refresh", 340)
		re.pressed.connect(func(): router.call("after_results", "online" if online else "restart"))
		row2.add_child(re)
		var mn2 := UIKit.button("Main menu", "GhostButton", "home", 300)
		mn2.name = "ResultsMainMenu"
		mn2.pressed.connect(func(): router.call("after_results", "menu"))
		row2.add_child(mn2)
		# made with its text so the button keeps room for the gift picture (the number is filled in when it appears)
		_pk_btn = UIKit.button(L.t("Open packages (%d)") % maxi(1, Game.packages().size()), "", "gift", 440)
		_pk_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_pk_btn.pressed.connect(func(): router.call("after_results", "packages"))
		_pk_btn.visible = false
		row2.add_child(_pk_btn)
		v.add_child(row2)
		if online:
			var rp := UIKit.button(L.t("Report or block %s") % str(res.get("opp_name", "")), "GhostButton", "flag")
			rp.name = "ResultsReport"
			rp.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			rp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			rp.add_theme_font_size_override("font_size", 24)
			rp.pressed.connect(func(): router.call("player_card"))
			v.add_child(rp)
		UIKit.center_in(self, card)
		UIKit.fade_in(card, 0.3, 40)
		if not you_lost:
			_confetti()

	var _pk_btn: Button
	var _bar: RewardScreens.XpBar
	var _up: Label

	## What the match paid: each line counts up, then the bar fills and levels tick over.
	func _xp_block(v: VBoxContainer) -> void:
		var x: Dictionary = res["xp"]
		var gain: Dictionary = res.get("gain", {"from": Game.level(), "to": Game.level(), "xp_from": Game.xp(), "xp_to": Game.xp()})
		var box := UIKit.panel("Card")
		var bv := UIKit.vbox(2)
		box.add_child(bv)
		var lines := [[L.t("Balls potted × %d") % int(x["balls"]), int(x["ball_xp"])], ["Streak bonus", int(x["streak_xp"])], ["Combo bonus", int(x["combo_xp"])],
			["8-ball", int(x["eight_xp"])], ["Opponent left: the rest of the rack", int(x.get("forfeit_xp", 0))], ["Win bonus", int(x["win_xp"])]]
		var shown: Array = []
		for ln in lines:
			if int(ln[1]) <= 0:
				continue
			var row := UIKit.hbox(12)
			var name_l := UIKit.label(str(ln[0]), "MutedLabel")
			name_l.add_theme_font_size_override("font_size", 24)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_l)
			var val := UIKit.label("+0", "H3Label", HORIZONTAL_ALIGNMENT_RIGHT)
			val.add_theme_font_size_override("font_size", 26)
			val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			row.add_child(val)
			bv.add_child(row)
			shown.append([row, val, int(ln[1])])
		var total_row := UIKit.hbox(12)
		var note := ""
		match str(x.get("mode", "")):
			"cpu": note = "Matches against the CPU give half XP"
			"local": note = "Local Turn Based gives no XP"
		var note_l := UIKit.label(note, "SmallLabel")
		note_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		total_row.add_child(note_l)
		var total := UIKit.label("+0 XP", "H2Label", HORIZONTAL_ALIGNMENT_RIGHT)
		total.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		total.add_theme_color_override("font_color", UIKit.GOLD)
		total_row.add_child(total)
		bv.add_child(total_row)
		_bar = RewardScreens.XpBar.new(880.0)
		_bar.set_xp(float(gain["xp_from"]))
		bv.add_child(_bar)
		_up = UIKit.label("", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_up.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_up.add_theme_color_override("font_color", UIKit.GOLD)
		_up.modulate.a = 0.0
		bv.add_child(_up)
		v.add_child(box)
		var quick: bool = Game.get_s("reduced_motion")
		var tw := create_tween()
		tw.tween_interval(0.35)
		for it in shown:
			var row_c: Control = it[0]
			var val_l: Label = it[1]
			var amount: int = it[2]
			row_c.modulate.a = 0.0
			tw.tween_property(row_c, "modulate:a", 1.0, 0.12)
			tw.tween_method(func(n: float): val_l.text = "+%d" % int(n), 0.0, float(amount), 0.05 if quick else 0.3)
			tw.tween_callback(func(): Sfx.play("tick", 0.35))
		var sum := int(x["total"])
		tw.tween_method(func(n: float): total.text = "+%d XP" % int(n), 0.0, float(sum), 0.05 if quick else 0.45)
		var levels := int(gain["to"]) - int(gain["from"])
		_bar.leveled.connect(func(lv: int):
			Sfx.play("win", 0.55)
			Game.vibrate(50)
			_up.text = L.t("LEVEL UP!  Level %d · new package: %s") % [lv, GearScreens.rarity_name(XP.rarity_of_level(lv))]
			_up.add_theme_color_override("font_color", GearScreens.rarity_color(XP.rarity_of_level(lv)))
			_up.modulate.a = 1.0
			_up.pivot_offset = _up.size * 0.5
			_up.scale = Vector2(1.25, 1.25)
			create_tween().tween_property(_up, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_confetti())
		if sum > 0:
			tw.tween_callback(func(): _bar.run(float(gain["xp_from"]), float(gain["xp_to"]), 0.1 if quick else 1.0 + 0.8 * levels))
			tw.tween_interval(0.15 if quick else 1.05 + 0.8 * levels)
		tw.tween_callback(func():
			var n: int = Game.packages().size()
			if n > 0:
				_pk_btn.text = L.t("Open packages (%d)") % n
				_pk_btn.visible = true
				UIKit.fade_in(_pk_btn, 0.3))

	func _confetti() -> void:
		if Game.get_s("reduced_motion"):
			return
		var p := CPUParticles2D.new()
		p.amount = 160
		p.lifetime = 3.0
		p.one_shot = true
		p.explosiveness = 0.85
		p.position = Vector2(get_viewport_rect().size.x * 0.5, -20)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(900, 10)
		p.direction = Vector2(0, 1)
		p.spread = 30
		p.gravity = Vector2(0, 420)
		p.initial_velocity_min = 120
		p.initial_velocity_max = 420
		p.angular_velocity_min = -360
		p.angular_velocity_max = 360
		p.scale_amount_min = 6
		p.scale_amount_max = 12
		var grad := Gradient.new()
		grad.set_color(0, UIKit.EMERALD)
		grad.add_point(0.33, UIKit.GOLD)
		grad.add_point(0.66, UIKit.SKY)
		grad.set_color(grad.get_point_count() - 1, UIKit.CORAL)
		p.color_initial_ramp = grad
		add_child(p)
		p.emitting = true


## ------------------------------------------------------------ Practice: the rack is cleared
## Practice has no winner, so a cleared rack is its "score screen": a natural break where the between-matches
## advert may follow (once adverts are on), as it does after every other mode's score screen.
class RackCleared extends Results:
	func _init(p_router: Node, p_info: Dictionary) -> void:
		super(p_router, p_info)

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.04, 0.08, 0.62)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
		var card := UIKit.panel()
		card.custom_minimum_size = Vector2(860, 0)
		var v := UIKit.vbox(18)
		card.add_child(v)
		v.add_child(UIKit.label("PRACTICE", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER))
		var title := UIKit.label("RACK CLEARED!", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_font_size_override("font_size", 72)
		title.add_theme_color_override("font_color", UIKit.EMERALD)
		v.add_child(title)
		var shots := int(res.get("shots", 0))
		var t := XP.clock(int(res.get("seconds", 0)))
		var line := UIKit.label(L.t("All 15 balls  ·  1 shot  ·  %s") % t if shots == 1 else L.t("All 15 balls  ·  %d shots  ·  %s") % [shots, t], "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
		line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(line)
		var row := UIKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var again := UIKit.button("Rack again", "PrimaryButton", "refresh", 340)
		again.pressed.connect(func(): router.call("after_results", "rerack"))
		row.add_child(again)
		var mn := UIKit.button("Main menu", "GhostButton", "home", 300)
		mn.pressed.connect(func(): router.call("after_results", "menu"))
		row.add_child(mn)
		v.add_child(row)
		UIKit.center_in(self, card)
		UIKit.fade_in(card, 0.3, 40)
		_confetti()


## ------------------------------------------------------------ a yes / no question over everything
## 24 Nov (Randy: "if in a match, a popup confirmation saying something like they are in a match and they wont get
## any xp for the match"). `on_yes` runs when the first button is pressed; the second (the safe one, lit) just closes.
class Confirm extends Control:
	var _title: String
	var _text: String
	var _yes: String
	var _no: String
	var _on_yes: Callable

	func _init(title: String, text: String, yes: String, no: String, on_yes: Callable) -> void:
		_title = title
		_text = text
		_yes = yes
		_no = no
		_on_yes = on_yes
		name = "Confirm"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.01, 0.02, 0.05, 0.72)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
		var card := UIKit.panel()
		card.custom_minimum_size = Vector2(820, 0)
		var v := UIKit.vbox(22)
		card.add_child(v)
		var head := UIKit.hbox(16)
		head.add_child(IconGlyph.make("flag", 52, UIKit.GOLD))
		var t := UIKit.label(_title, "H2Label")
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(t)
		v.add_child(head)
		var body := UIKit.label(_text, "")
		body.name = "ConfirmText"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 760
		v.add_child(body)
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 18)
		row.add_theme_constant_override("v_separation", 14)
		var yes := UIKit.button(_yes, "GhostButton", "home", 340)
		yes.name = "ConfirmYes"
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			yes.add_theme_color_override(c, UIKit.CORAL)
		yes.pressed.connect(func():
			Sfx.ui("tap")
			queue_free()
			_on_yes.call())
		row.add_child(yes)
		var no := UIKit.button(_no, "PrimaryButton", "play", 340)
		no.name = "ConfirmNo"
		no.pressed.connect(func():
			Sfx.ui("back")
			queue_free())
		row.add_child(no)
		v.add_child(row)
		UIKit.center_in(self, card)
		UIKit.fade_in(card, 0.15, 16)


## ------------------------------------------------------------ report or block the other player
## 24 Nov 2026 (both app stores, for games where players see each other's names: a way to report a player and to
## block them). From the pause menu and the score screen of an online match. A stand-in opponent (Play Online found
## nobody) gets the very same card; its report goes nowhere and blocking it keeps that name out of later matches.
class PlayerCard extends Control:
	var router: Node
	var _name: String
	var _id: String          # "" = a stand-in
	var _block_b: Button
	var _note: Label

	func _init(p_router: Node, opp_name: String, opp_id: String) -> void:
		router = p_router
		_name = opp_name
		_id = opp_id
		name = "PlayerCard"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _blocked() -> bool:
		return Net.is_blocked(_id) if _id != "" else _name in Game.progress.get("blocked_names", [])

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.01, 0.02, 0.05, 0.72)
		UIKit.fullrect(bg)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		bg.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed:
				queue_free())
		add_child(bg)
		var card := UIKit.panel()
		card.custom_minimum_size = Vector2(860, 0)
		var v := UIKit.vbox(16)
		card.add_child(v)
		var head := UIKit.hbox(16)
		head.add_child(IconGlyph.make("user", 56, UIKit.EMERALD))
		var t := UIKit.label(_name, "H2Label")
		t.name = "PlayerCardName"
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED       # (a username)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(t)
		var close := UIKit.icon_button("close", 80, "Close")
		close.pressed.connect(func():
			Sfx.ui("back")
			queue_free())
		head.add_child(close)
		v.add_child(head)
		var why := UIKit.label("Report this player if their username is offensive or they play unfairly. Block them and you won't be matched with them again.", "MutedLabel")
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 800
		v.add_child(why)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		row.add_theme_constant_override("v_separation", 12)
		for rr in [["Offensive username", "name"], ["Cheating", "cheating"], ["Something else", "other"]]:
			var b := UIKit.button(rr[0], "ChipButton", "flag")
			b.name = "Report_" + str(rr[1])
			var reason: String = rr[1]
			b.pressed.connect(func(): _report(reason))
			row.add_child(b)
		v.add_child(UIKit.label("Report", "H3Label"))
		v.add_child(row)
		_block_b = UIKit.button("", "GhostButton", "lock", 420)
		_block_b.name = "PlayerCardBlock"
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_block_b.add_theme_color_override(c, UIKit.CORAL)
		_block_b.pressed.connect(_toggle_block)
		v.add_child(_block_b)
		_note = UIKit.label("", "SmallLabel")
		_note.name = "PlayerCardNote"
		_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # (put together translated, with a name)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(_note)
		_refresh()
		UIKit.center_in(self, card)
		UIKit.fade_in(card, 0.15, 16)

	func _refresh() -> void:
		_block_b.text = "Unblock player" if _blocked() else "Block player"

	func _report(reason: String) -> void:
		Sfx.ui("tap")
		if _id != "":
			Net.report_player(_id, reason)
		_note.text = L.t("Thanks for the report. We'll look into it.")
		router.call("toast", L.t("Thanks for the report. We'll look into it."))

	func _toggle_block() -> void:
		Sfx.ui("toggle")
		var on := not _blocked()
		if _id != "":
			Net.block_player(_id, _name, on)
		else:
			var names: Array = Game.progress.get("blocked_names", [])
			if on and not _name in names:
				names.append(_name)
			elif not on:
				names.erase(_name)
			Game.progress["blocked_names"] = names
			Game.request_save()
		_note.text = L.t("Blocked. You won't be matched with %s again.") % _name if on else L.t("%s is no longer blocked.") % _name
		_refresh()
