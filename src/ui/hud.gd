class_name HUD
extends Control
## In-match overlay. Reads PoolGame state, shows clocks / objectives / banners, hosts control widgets.

signal pause_requested

var game: PoolGame
var stage: Stage
var control_layer: Control
var _cards: Array = []
var _info_title: Label
var _info_sub: Label
var _toast: Label
var _toast_tw: Tween
var _toast_top := 150.0
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _curtain: Control
var _curtain_lbl: Label
var _spin: Widgets.SpinPad
var _elev: Widgets.ElevationSlider
var _tools: VBoxContainer
var _btn_hand: Button
var _btn_undo: Button
var _cue_held := false      # the cue was switched off because the AR table is not placed
var _btn_gear: Button
var _drawer: Control
var _btn_recenter: Button
var _btn_adjust: Button
var _btn_views: Array = []
var _scheme_chip: Button
var _ar_panel: PanelContainer
var _ar_lbl: Label
var _ar_badge: Label
var _hand_place: Button
var _adjust_panel: PanelContainer
var _adjust_lbl: Label
var _lift_dir := 0          # raise / lower button held: +1 / -1
var _lift_hold := 0.0
var _ar_detail: Label
var _ar_sizes: Control
var _ar_retry: Button
var _ar_settings: Button
var _ar_studio: Button
var _ar_place: Button
var _ar_install: Button
var _overlay: Control
var _overlay_live := false
var _power_col := Color.TRANSPARENT
var _fps: Label
var _power_lbl: Label
var _hint_lbl: Label
var _banner_tw: Tween
var _pending_turn := {}
var _feed: PotFeed
var _btn_free: Button
var _fl_panel: PanelContainer
var _fl_hold := Vector3.ZERO     # free-look button held: turn, tilt, zoom per second


func setup(p_game: PoolGame, p_stage: Stage) -> void:
	game = p_game
	stage = p_stage
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	game.turn_started.connect(_on_turn)
	game.message.connect(toast)
	game.ball_potted.connect(_on_potted)
	game.groups_set.connect(_on_groups_set)
	game.state_changed.connect(_on_state)
	game.stats_changed.connect(_refresh)
	stage.ar_message.connect(func(t: String): toast(t, "info"))
	stage.placement_changed.connect(_on_placed)
	stage.free_look_changed.connect(_on_free_look)
	Game.settings_changed.connect(_on_setting)


func _update_ar_badge() -> void:
	if stage.mode != Stage.Mode.WORLD_AR:
		_ar_badge.visible = false
		return
	_ar_badge.visible = true
	match stage.ar_state:
		Stage.ArState.RUNNING:
			var t := L.t("● WALK-AROUND AR")
			if stage.placed:
				t += L.t(" · table anchored") if stage.arcore.anchor_tracking == 2 else L.t(" · re-finding the table…")
			elif stage.arcore.tracking != 2:
				t += L.t(" · finding your room…")
			_ar_badge.text = t
			_ar_badge.add_theme_color_override("font_color", UIKit.EMERALD)
		Stage.ArState.BLOCKED:
			_ar_badge.text = "● AR IS NOT RUNNING"
			_ar_badge.add_theme_color_override("font_color", UIKit.CORAL)
		_:
			_ar_badge.text = "● STARTING AR…"
			_ar_badge.add_theme_color_override("font_color", UIKit.GOLD)


func _build() -> void:
	control_layer = UIKit.fullrect(Control.new())
	control_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control_layer)
	_overlay = UIKit.fullrect(Control.new())
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	# ---------------- top bar
	var top := UIKit.hbox(20)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28
	top.offset_right = -140
	top.offset_top = 22
	add_child(top)
	top.add_child(_make_player_card(0))
	var mid := UIKit.vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_info_title = UIKit.label(_title_text(), "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	_info_sub = UIKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(_info_title)
	mid.add_child(_info_sub)
	# these sit straight on the picture: a dark outline keeps them readable over bright scenes
	for lbl in [_info_title, _info_sub]:
		lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.85))
		lbl.add_theme_constant_override("outline_size", 8)
	_info_sub.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	if game.tutorial:
		# the objective card takes this place
		_info_title.visible = false
		_info_sub.visible = false
	# which AR is running, always visible in AR (walk-around vs basic, and why)
	_ar_badge = UIKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_ar_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ar_badge.visible = false
	mid.add_child(_ar_badge)
	top.add_child(mid)
	if game.mode == "versus":
		top.add_child(_make_player_card(1))
	var pause := UIKit.icon_button("pause", 96, "Pause")
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-120, 24)
	pause.pressed.connect(func(): pause_requested.emit())
	add_child(pause)
	# ---------------- right tools
	_tools = UIKit.vbox(10)
	add_child(_tools)
	# the gear drawer: change the cue, table or ball set at any time (Randy, 11 Nov)
	_btn_gear = UIKit.icon_button("kit", 82, "Change cue, table and balls")
	_btn_gear.name = "GearButton"
	_btn_gear.pressed.connect(open_gear)
	_tools.add_child(_btn_gear)
	var v_over := UIKit.icon_button("cube", 82, "Overview")
	var v_aim := UIKit.icon_button("aim_cam", 82, "Aim cam")
	var v_top := UIKit.icon_button("top_view", 82, "Top view")
	_btn_views = [v_over, v_aim, v_top]
	for i in 3:
		var idx := i
		_btn_views[i].pressed.connect(func(): _set_view(idx))
		_tools.add_child(_btn_views[i])
		if i == 2:
			# free look, in the top view only (v1.1.5)
			_btn_free = UIKit.icon_button("eye", 82, "Free look")
			_btn_free.name = "FreeLookButton"
			_btn_free.pressed.connect(func(): stage.set_free_look(not stage.free_look))
			_tools.add_child(_btn_free)
	_btn_hand = UIKit.icon_button("hand", 82, "Move the cue ball")
	_btn_hand.pressed.connect(func(): game.start_ball_in_hand())
	_tools.add_child(_btn_hand)
	_btn_undo = UIKit.icon_button("undo", 82, "Undo last shot")
	_btn_undo.pressed.connect(func(): game.undo())
	_tools.add_child(_btn_undo)
	_btn_recenter = UIKit.icon_button("recenter", 82, "Re-place the table")
	_btn_recenter.pressed.connect(func():
		stage.recenter_ar()
		_show_ar_panel(true))
	_tools.add_child(_btn_recenter)
	_btn_adjust = UIKit.icon_button("move", 82, "Move / scale / rotate the table")
	_btn_adjust.toggle_mode = true
	_btn_adjust.toggled.connect(func(on: bool):
		if on:
			open_table_adjust()
		else:
			close_table_adjust())
	_tools.add_child(_btn_adjust)
	# ---------------- spin + elevation (bottom corner)
	var spin_box := UIKit.hbox(16)
	spin_box.name = "SpinBox"
	add_child(spin_box)
	_spin = Widgets.SpinPad.new()
	_spin.changed.connect(func(o: Vector2):
		if game.control:
			if game.offset_allowed(o):
				game.control.offset = o
			else:
				# that spot would put the stick inside a ball: the pad stays where the stick can be
				_spin.set_spin(game.control.offset))
	_elev = Widgets.ElevationSlider.new()
	_elev.changed.connect(func(d: float):
		if game.control:
			game.control.elevation = d)
	spin_box.add_child(_spin)
	spin_box.add_child(_elev)
	# ---------------- scheme chip + hint
	_scheme_chip = UIKit.button(Game.scheme_name(Game.scheme()), "ChipButton", "cue")
	_scheme_chip.tooltip_text = "Switch cue control"
	_scheme_chip.pressed.connect(_cycle_scheme)
	add_child(_scheme_chip)
	_hint_lbl = UIKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_hint_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.85))
	_hint_lbl.add_theme_constant_override("outline_size", 8)
	_hint_lbl.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	add_child(_hint_lbl)
	_power_lbl = UIKit.label("", "H2Label", HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_power_lbl)
	# ---------------- toast, banner, curtain, AR panel
	_toast = UIKit.label("", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.modulate.a = 0.0
	add_child(_toast)
	_build_free_look()
	# the potted balls and the groups, stacking on the left (Randy, v1.1.5)
	_feed = PotFeed.new()
	_feed.name = "PotFeed"
	add_child(_feed)
	_build_banner()
	_build_curtain()
	_build_ar_panel()
	_build_adjust_panel()
	# ball in hand: the cue ball can be moved as often as you like; this makes it final
	_hand_place = UIKit.button("Place ball", "PrimaryButton", "check", 340)
	_hand_place.pressed.connect(func(): game.confirm_cue_placement())
	_hand_place.visible = false
	add_child(_hand_place)
	_fps = UIKit.label("", "SmallLabel")
	_fps.position = Vector2(30, 1040)
	add_child(_fps)
	resized.connect(_layout)
	_layout()
	_refresh_tools()


func _make_player_card(i: int) -> PanelContainer:
	var p := UIKit.panel("HudPanel")
	p.custom_minimum_size = Vector2(400, 104)
	var h := UIKit.hbox(14)
	p.add_child(h)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 72)
	dot.color = UIKit.P1_COLOR if i == 0 else UIKit.P2_COLOR
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_l := UIKit.label(game.player_names[i], "H3Label")
	name_l.clip_text = true
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a player's own name is never translated
	var sub := UIKit.label("", "SmallLabel")
	v.add_child(name_l)
	v.add_child(sub)
	var clock := UIKit.label(UIKit.fmt_clock(game.clocks[i]), "ClockLabel")
	clock.custom_minimum_size.x = 104
	clock.visible = game.mode == "versus"
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(clock)
	_cards.append({"panel": p, "name": name_l, "sub": sub, "clock": clock, "dot": dot, "index": i})
	return p


func _title_text() -> String:
	if game.tutorial:
		return "TUTORIAL"
	if game.mode != "versus":
		return "PRACTICE"
	if game.looks_online():
		return "8-BALL · ONLINE"
	return (L.t("8-BALL · VS CPU (%s)") % L.up(L.t(AIPlayer.NAMES[game.ai_level]))) if game.vs_ai else "8-BALL · LOCAL TURN BASED"


## The language was changed while a match is open: redo every text that was put together in code.
func on_language_changed() -> void:
	if game == null:
		return
	game.refresh_names()
	_info_title.text = _title_text()
	for c in _cards:
		(c["name"] as Label).text = game.player_names[c["index"]]
	if _scheme_chip:
		_scheme_chip.text = Game.scheme_name(Game.scheme())
	_refresh()
	_update_hint()
	propagate_call("queue_redraw")


func _build_banner() -> void:
	_banner = UIKit.panel()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(6)
	_banner.add_child(v)
	_banner_title = UIKit.label("", "H1Label", HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = UIKit.label("", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_banner_title)
	v.add_child(_banner_sub)
	_banner.visible = false
	add_child(_banner)


func _build_curtain() -> void:
	_curtain = UIKit.fullrect(ColorRect.new())
	(_curtain as ColorRect).color = Color(0.03, 0.05, 0.09, 0.97)
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UIKit.vbox(28)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_curtain_lbl = UIKit.label("", "H1Label", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(UIKit.label("PASS THE PHONE", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_curtain_lbl)
	var ready := UIKit.button("I'm ready", "PrimaryButton", "play", 420)
	ready.pressed.connect(func():
		_curtain.visible = false
		control_layer.visible = true
		_show_banner_for(_pending_turn))
	var rc := CenterContainer.new()
	rc.add_child(ready)
	v.add_child(rc)
	UIKit.center_in(_curtain, v)
	_curtain.visible = false
	add_child(_curtain)


# ------------------------------------------------------------------ AR: move / raise / lower the table
func _build_adjust_panel() -> void:
	_adjust_panel = UIKit.panel()
	var v := UIKit.vbox(12)
	_adjust_panel.add_child(v)
	_adjust_lbl = UIKit.label("", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_adjust_lbl)
	var tip := UIKit.label("Drag to move · pinch to resize · twist to turn", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(tip)
	var row := UIKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lower := UIKit.button("Lower", "", "chev_left", 230)
	var raise := UIKit.button("Raise", "", "chev_right", 230)
	# tap = 1 cm, hold = keeps going
	lower.button_down.connect(func(): _start_lift(-1))
	lower.button_up.connect(func(): _lift_dir = 0)
	raise.button_down.connect(func(): _start_lift(1))
	raise.button_up.connect(func(): _lift_dir = 0)
	var again := UIKit.button("Place again", "GhostButton", "recenter")
	again.pressed.connect(func():
		close_table_adjust()
		stage.recenter_ar()
		_show_ar_panel(true))
	var done := UIKit.button("Done", "PrimaryButton", "check", 220)
	done.pressed.connect(close_table_adjust)
	row.add_child(lower)
	row.add_child(raise)
	row.add_child(again)
	row.add_child(done)
	v.add_child(row)
	_adjust_panel.visible = false
	add_child(_adjust_panel)
	_adjust_panel.minimum_size_changed.connect(_place_adjust_panel)


func _place_adjust_panel() -> void:
	_adjust_panel.reset_size()
	_adjust_panel.position = Vector2((size.x - _adjust_panel.size.x) * 0.5, size.y - _adjust_panel.size.y - 28)


## Pause menu / move button: the table can be dragged, resized, turned, raised and lowered until Done.
func open_table_adjust() -> void:
	if not stage.is_ar() or not stage.placed:
		return
	stage.set_adjusting(true)
	_btn_adjust.set_pressed_no_signal(true)
	_lift_dir = 0
	_update_adjust_label()
	_adjust_panel.visible = true
	_place_adjust_panel()
	UIKit.fade_in(_adjust_panel)
	if game.control:
		game.control.set_enabled(false)   # hands off the cue while the table is being moved


func close_table_adjust() -> void:
	_lift_dir = 0
	stage.set_adjusting(false)
	_btn_adjust.set_pressed_no_signal(false)
	_adjust_panel.visible = false
	if game.control:
		game.control.set_enabled(game.state == PoolGame.State.AIM and game.is_human_turn())


func _start_lift(dir: int) -> void:
	_lift_dir = dir
	_lift_hold = 0.0
	stage.lift_table(0.01 * dir)
	_update_adjust_label()


func _update_adjust_label() -> void:
	var cm := roundi(stage.ar_lift * 100.0)
	_adjust_lbl.text = "Move the table" if cm == 0 else (L.t("Move the table · raised %d cm") if cm > 0 else L.t("Move the table · lowered %d cm")) % absi(cm)


func _build_ar_panel() -> void:
	# v1.1.15: the panel is shared with the main menu's "Place world" (ArPlacePanel); its parts keep their old names
	# here so the checks that look for them still find them
	var p := ArPlacePanel.new(stage)
	_ar_panel = p
	_ar_lbl = p.lbl
	_ar_detail = p.detail
	_ar_sizes = p.sizes
	_ar_place = p.place
	_ar_retry = p.retry
	_ar_install = p.install
	_ar_settings = p.settings_b
	_ar_studio = p.studio
	p.without_ar.connect(func():
		Game.world_ready = "studio"         # (and for the next matches too, until Place world is chosen again)
		Game.set_s("ar_mode", "studio")
		stage.set_mode(Stage.Mode.STUDIO)
		_show_ar_panel(false)
		game.on_table_placed())
	_ar_panel.visible = false
	add_child(_ar_panel)
	_ar_panel.minimum_size_changed.connect(_place_ar_panel)


func _layout() -> void:
	var vp := size
	var right := not bool(Game.get_s("left_handed"))
	_tools.position = Vector2(vp.x - 116 if right else 30, 150)
	var spin_box := get_node("SpinBox") as Control
	spin_box.position = Vector2(36 if right else vp.x - 320, vp.y - 290)
	_scheme_chip.position = Vector2(36 if right else vp.x - 330, vp.y - 380)
	_place_hint()
	_power_lbl.position = Vector2(vp.x * 0.5 - 200, vp.y * 0.5 + 140)
	_power_lbl.size = Vector2(400, 60)
	# free-look buttons: beside the tool column, half way down
	_fl_panel.reset_size()
	_fl_panel.position = Vector2(vp.x - 116 - 24 - _fl_panel.size.x if right else 30 + 82 + 24, vp.y * 0.5 - _fl_panel.size.y * 0.5 + 40)
	# the pot feed: under the player card, on the side away from the tool buttons
	_feed.position = Vector2(30 if right else vp.x - 360, 236)
	_feed.max_height = maxf(vp.y - 380.0 - 16.0 - 236.0, 160.0)    # down to the cue-control chip
	_toast.position = Vector2(vp.x * 0.5 - 600, _toast_top)
	_toast.size = Vector2(1200, 60)
	_banner.position = Vector2(vp.x * 0.5 - 420, vp.y * 0.36)
	_banner.custom_minimum_size = Vector2(840, 0)
	_ar_panel.custom_minimum_size = Vector2(860, 0)
	_place_ar_panel()
	_place_adjust_panel()
	_hand_place.reset_size()
	_hand_place.position = Vector2((vp.x - _hand_place.size.x) * 0.5, vp.y - _hand_place.size.y - 70)
	_fps.position = Vector2(30, vp.y - 44)


## Bottom-centre, sized to its content (the text and the install button change with the AR mode).
func _place_ar_panel() -> void:
	_ar_panel.reset_size()
	_ar_panel.position = Vector2((size.x - _ar_panel.size.x) * 0.5, size.y - _ar_panel.size.y - 28)


func _on_setting(k: String) -> void:
	if k == "left_handed":
		_layout()
	if k == "control_scheme":
		_scheme_chip.text = Game.scheme_name(Game.scheme())
		_update_hint()
	if k == "gear_drawer":
		_refresh_tools()


## Quick picker for the cue control (a popup grid instead of cycling through eight).
func _cycle_scheme() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := UIKit.panel("Card")
	var v := UIKit.vbox(14)
	panel.add_child(v)
	v.add_child(UIKit.label("Cue control", "H2Label"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for id in Game.SCHEMES:
		var cur: bool = id == Game.scheme()
		var b := UIKit.button(Game.scheme_name(id), "PrimaryButton" if cur else "GhostButton", "check" if cur else "")
		b.custom_minimum_size = Vector2(300, 74)
		b.pressed.connect(func():
			dim.queue_free()
			if id != Game.scheme():
				Game.set_s("control_scheme", id)
				toast(L.t("Cue control: %s") % Game.scheme_name(id), "info"))
		grid.add_child(b)
	dim.add_child(panel)
	panel.position = (get_viewport().get_visible_rect().size - Vector2(680, 470)) * 0.5
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			dim.queue_free())
	UIKit.fade_in(panel)


func _set_view(i: int) -> void:
	match i:
		0:
			stage.set_aim_cam(false)
			stage.set_view(Stage.View.OVERVIEW)
		1:
			if stage.is_ar():
				stage.set_aim_cam(not stage.aim_cam_override or stage.view != Stage.View.AIM)
			stage.set_view(Stage.View.AIM)
		2:
			if stage.is_ar():
				stage.set_aim_cam(true)
			stage.set_view(Stage.View.TOP)
	_refresh_tools()


func _refresh_tools() -> void:
	_btn_hand.visible = (game.mode == "practice" and game.state in [PoolGame.State.AIM, PoolGame.State.BALL_IN_HAND]) or ((game.rules.ball_in_hand or game.break_pending()) and game.is_human_turn() and game.state == PoolGame.State.AIM)
	_btn_undo.visible = game.mode == "practice" and not game.tutorial
	if game.tutorial:
		# the tutorial says when to move the cue ball (the Place ball button does it); free moves would skip objectives
		_btn_hand.visible = false
	_btn_recenter.visible = stage.is_ar()
	_btn_adjust.visible = stage.is_ar()
	_btn_gear.visible = gear_drawer_allowed()
	if not _btn_gear.visible and gear_open():
		_drawer.close()
	_btn_free.visible = stage.view == Stage.View.TOP
	_btn_free.modulate = Color(1, 1, 1, 1) if stage.free_look else Color(1, 1, 1, 0.6)
	_fl_panel.visible = stage.free_look
	for i in 3:
		var active := false
		match i:
			0: active = stage.view == Stage.View.OVERVIEW and not stage.aim_cam_override
			1: active = stage.view == Stage.View.AIM
			2: active = stage.view == Stage.View.TOP
		_btn_views[i].modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.6)


# ================================================================== events
func _on_turn(player: int, inf: Dictionary) -> void:
	_spin.set_spin(Vector2.ZERO)
	_elev.set_value(0.0)
	_refresh()
	_update_hint()
	var changed: bool = inf.get("changed", true) or inf.get("first", false)
	if game.mode == "versus" and changed:
		Sfx.play("turn_chime", 0.9)
		Game.vibrate(90)
		var pass_curtain: bool = Game.get_s("pass_curtain") and not game.vs_ai and not game.online and not inf.get("first", false)
		_pending_turn = {"player": player, "info": inf}
		if pass_curtain:
			_curtain_lbl.text = L.t("%s — your turn") % game.player_names[player]
			_curtain.visible = true
			_curtain.move_to_front()        # above every button, including Place ball
			control_layer.visible = false   # the next player's cue controls stay out of sight until they take the phone
			return
		_show_banner_for(_pending_turn)
	elif game.mode == "practice" and inf.get("first", false) and not game.tutorial:
		_show_banner("PRACTICE", "Shoot freely. Hand button moves the cue ball.", UIKit.SKY)
	if inf.get("first", false) and game.looks_online():
		# whose table and whose balls, once the turn banner has gone
		get_tree().create_timer(2.2).timeout.connect(func():
			if is_instance_valid(self) and is_inside_tree():
				toast(game.gear_note(), "info"))


func _show_banner_for(d: Dictionary) -> void:
	if d.is_empty():
		return
	var p: int = d["player"]
	var inf: Dictionary = d["info"]
	var you: bool = game.plays_here(p)
	var title := L.up(L.t("%s — YOUR TURN") % game.player_names[p]) if you else L.up(L.t("%s'S TURN") % game.player_names[p])
	var sub := ""
	if inf.get("ball_in_hand", false):
		# the how-to only for the player holding the phone; the CPU / the other player simply has ball in hand
		sub = "Ball in hand — move the cue ball, then tap Place ball" if you else "Ball in hand"
	elif game.break_pending() and you:
		sub = "Break shot · the hand button moves the cue ball behind the line"
	elif game.rules and game.rules.groups[p] >= 0:
		sub = EightBall.on_group_text(game.rules.groups[p])
	else:
		sub = "Open table"
	_show_banner(title, L.t(sub) + "  ·  " + L.t("%s left") % UIKit.fmt_clock(game.clocks[p]), UIKit.P1_COLOR if p == 0 else UIKit.P2_COLOR)


func _show_banner(title: String, sub: String, col: Color) -> void:
	FpsCounter.mark("turn banner")
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", col)
	_banner_sub.text = sub
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.92, 0.92)
	# a long line (other languages, the break hint) makes the banner wider: keep it in the middle of the screen
	_banner.reset_size()
	var bw := maxf(_banner.get_combined_minimum_size().x, 840.0)
	_banner.position.x = get_viewport_rect().size.x * 0.5 - bw * 0.5
	_banner.pivot_offset = Vector2(bw * 0.5, 70)
	if _banner_tw:
		_banner_tw.kill()
	_banner_tw = create_tween()
	_banner_tw.set_parallel(true)
	_banner_tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tw.tween_property(_banner, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tw.chain().tween_interval(1.5)
	_banner_tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tw.chain().tween_callback(func(): _banner.visible = false)


## The free-look buttons (top view): turn left / right, tilt up / down, zoom in / out, and back to the whole table.
## A tap moves a step; holding keeps it moving.
func _build_free_look() -> void:
	_fl_panel = UIKit.panel("HudPanel")
	_fl_panel.name = "FreeLookPanel"
	_fl_panel.visible = false
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_fl_panel.add_child(g)
	# [icon, tip, step on a tap (turn, tilt, zoom), speed while held (per second; zoom: factor a second)]
	var cells := [
		["plus", "Zoom in", Vector3(0, 0, 0.88), Vector3(0, 0, 0.4)],
		["chev_up", "Tilt up", Vector3(0, deg_to_rad(6), 1), Vector3(0, deg_to_rad(45), 1)],
		["minus", "Zoom out", Vector3(0, 0, 1.0 / 0.88), Vector3(0, 0, 2.5)],
		["chev_left", "Turn left", Vector3(deg_to_rad(-10), 0, 1), Vector3(deg_to_rad(-70), 0, 1)],
		["recenter", "Whole table", Vector3.ZERO, Vector3.ZERO],
		["chev_right", "Turn right", Vector3(deg_to_rad(10), 0, 1), Vector3(deg_to_rad(70), 0, 1)],
		["", "", Vector3.ZERO, Vector3.ZERO],
		["chev_down", "Tilt down", Vector3(0, deg_to_rad(-6), 1), Vector3(0, deg_to_rad(-45), 1)],
		["", "", Vector3.ZERO, Vector3.ZERO],
	]
	for c in cells:
		if str(c[0]) == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(76, 76)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			g.add_child(gap)
			continue
		var b := UIKit.icon_button(str(c[0]), 76, str(c[1]))
		b.name = "FL_" + str(c[0])
		g.add_child(b)
		if str(c[0]) == "recenter":
			b.pressed.connect(func(): stage.free_look_reset())
			continue
		var tap: Vector3 = c[2]
		var hold: Vector3 = c[3]
		b.button_down.connect(func():
			stage.free_look_step(tap.x, tap.y, tap.z)
			_fl_hold = hold)
		b.button_up.connect(func(): _fl_hold = Vector3.ZERO)
	add_child(_fl_panel)


## Free look is for looking: the cue and its controls are put away (they sat where the free-look buttons are) and
## come back when it ends.
func _on_free_look(on: bool) -> void:
	_fl_hold = Vector3.ZERO
	if game.control:
		game.control.set_enabled(not on and game.state == PoolGame.State.AIM and game.is_human_turn() and not gear_open())
	_on_state(game.state)
	_refresh_tools()
	_update_hint()
	_layout()


## The free-look buttons (tests).
func free_look_button(icon: String) -> Button:
	return _fl_panel.find_child("FL_" + icon, true, false) as Button


## A ball dropped: its card in the pot feed (with who potted it, in a two-player match).
func _on_potted(n: int, shooter: int) -> void:
	_feed.ball_set = game.ball_set if game.ball_set != "" else str(Game.get_s("ball_set"))
	var two := game.mode == "versus"
	_feed.add_ball(n, game.player_names[shooter] if two else "", UIKit.P1_COLOR if shooter == 0 else UIKit.P2_COLOR)


## The table is no longer open: who is on solids and who is on stripes.
func _on_groups_set() -> void:
	_feed.ball_set = game.ball_set if game.ball_set != "" else str(Game.get_s("ball_set"))
	var rows: Array = []
	for i in 2:
		rows.append([game.player_names[i], int(game.rules.groups[i]), UIKit.P1_COLOR if i == 0 else UIKit.P2_COLOR])
	_feed.add_groups(rows)


## The pot feed (tests and the language audit).
func pot_feed() -> PotFeed:
	return _feed


## The tutorial's objective card takes the top of the screen: the messages go under it.
func set_toast_top(y: float) -> void:
	_toast_top = y
	_toast.position.y = y


func toast(text: String, kind := "info") -> void:
	_toast.text = text
	var col := UIKit.TEXT
	match kind:
		"warn": col = UIKit.GOLD
		"good": col = UIKit.EMERALD
		"bad": col = UIKit.CORAL
		"gem": col = UIKit.EMERALD
	_toast.add_theme_color_override("font_color", col)
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast.modulate.a = 0.0
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_state(s: int) -> void:
	FpsCounter.mark("state %d" % s)
	if stage.free_look and game.control:
		game.control.set_enabled(false)     # (a new turn starting during free look: the cue stays put away)
	var aiming := s == PoolGame.State.AIM and game.is_human_turn() and not stage.free_look
	_spin.visible = aiming
	_elev.visible = aiming
	_scheme_chip.visible = aiming
	_show_ar_panel(s == PoolGame.State.PLACE_TABLE)
	_hand_place.visible = s == PoolGame.State.BALL_IN_HAND and game.is_human_turn()
	_update_hint()
	_refresh_tools()


func _on_placed(placed: bool) -> void:
	_show_ar_panel(not placed)
	if placed and stage.is_ar():
		Game.world_ready = "ar"       # (it stays in the room for the next match too)
	if _adjust_panel.visible and (not placed or not stage.is_ar()):
		close_table_adjust()
	if placed:
		game.on_table_placed()
	# no cue while the table is not there (it is being put down again in the middle of a match)
	if game.control:
		if not placed:
			_cue_held = true
			game.control.set_enabled(false)
		elif _cue_held:
			_cue_held = false
			game.control.set_enabled(game.state == PoolGame.State.AIM and game.is_human_turn())
	_refresh_tools()


## The gear drawer on the right. The match carries on behind it; the cue is held while it is open.
func open_gear() -> void:
	if (_drawer and is_instance_valid(_drawer)) or not gear_drawer_allowed():
		return
	Sfx.ui("tap")
	_drawer = GearScreens.GearDrawer.new()
	_drawer.name = "GearDrawer"
	add_child(_drawer)
	var held := game.control != null and game.control.enabled
	if held:
		game.control.set_enabled(false)
	_drawer.closed.connect(func():
		_drawer = null
		if held and game.control and game.state == PoolGame.State.AIM and game.is_human_turn():
			game.control.set_enabled(true))


## The gear drawer is a developer tool (Settings → Developer tools; on while the game is being tested). It is never
## offered in an online match: the table and the balls there come from the two players, and each sees the other's cue.
func gear_drawer_allowed() -> bool:
	return bool(Game.get_s("gear_drawer")) and not game.looks_online()


func gear_open() -> bool:
	return _drawer != null and is_instance_valid(_drawer)


## Pause menu: put the table down somewhere else from scratch (AR).
func replace_table() -> void:
	if not stage.is_ar():
		return
	if _adjust_panel.visible:
		close_table_adjust()
	stage.recenter_ar()
	_show_ar_panel(true)


func _show_ar_panel(on: bool) -> void:
	_ar_panel.visible = on
	if on:
		UIKit.fade_in(_ar_panel)


func _update_hint() -> void:
	var t := ""
	if stage.free_look:
		_hint_lbl.text = "Free look: drag to move the view · pinch to zoom · tap the eye to aim again"
		_place_hint()
		return
	match game.state:
		PoolGame.State.AIM:
			match Game.scheme():
				"slingshot": t = "Pull back anywhere · release to shoot · 2nd finger = fine aim"
				"phone_cue": t = "Point the phone to aim · hold STROKE and push forward"
				"pro_dial": t = "Drag the wheel to aim · arrows nudge · pull the piston"
				"orbit_ring": t = "Drag along the ring to swing the cue · further out = finer · pull the piston"
				"trackpad": t = "Tap table to aim · slide on the pad (slow = fine) · pull the piston"
				"crank": t = "Tap table to aim · turn the crank · pull the piston"
				"ghost_target": t = "Place the ghost ball · micro pad for fine moves · pull the piston"
				"thumbstick": t = "Tap table to aim · push the stick to turn · pull the piston"
		PoolGame.State.BALL_IN_HAND:
			t = "Ball in hand: tap or drag to move the cue ball as often as you like, then tap Place ball"
			if game.break_placement():
				t = "Break: move the cue ball anywhere behind the line, then tap Place ball"
		PoolGame.State.ROLLING:
			t = "Tap to fast-forward"
		PoolGame.State.AI_THINK:
			t = ""
	_hint_lbl.text = t
	_place_hint()


## Keeps the hint line inside the screen in every language: centred, and if the sentence is wider than the
## screen the letters shrink a little; if that is still not enough it wraps onto a second line (growing upwards).
func _place_hint() -> void:
	var vp := get_viewport_rect().size
	var room := vp.x - 80.0
	var f := _hint_lbl.get_theme_font("font")
	var base := 24
	var text := _hint_lbl.tr(_hint_lbl.text) if _hint_lbl.text != "" else ""
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, base).x
	var fs := base
	if w > room:
		fs = maxi(19, int(floor(base * room / w)))
	_hint_lbl.add_theme_font_size_override("font_size", fs)
	var lines := 1
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		lines = 2
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if lines > 1 else TextServer.AUTOWRAP_OFF
	var h := 40.0 * lines
	_hint_lbl.position = Vector2(vp.x * 0.5 - room * 0.5, vp.y - 12.0 - h)
	_hint_lbl.size = Vector2(room, h)


func _refresh() -> void:
	var d := game.info()
	for c in _cards:
		var i: int = c["index"]
		var active: bool = d["current"] == i and game.state != PoolGame.State.OVER
		var sb := UIKit.box(Color(0.04, 0.07, 0.12, 0.8 if active else 0.55), 24, 3 if active else 1,
			(UIKit.P1_COLOR if i == 0 else UIKit.P2_COLOR) if active else Color(1, 1, 1, 0.1), Vector4(22, 12, 22, 12), 10 if active else 4)
		(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
		if d["mode"] == "versus" and d.has("groups"):
			var g: int = d["groups"][i]
			(c["sub"] as Label).text = (L.t("%s · %d left") % [EightBall.group_name(g), d["remaining"][i]]) if g >= 0 else "Open table"
		elif d["mode"] == "practice":
			(c["sub"] as Label).text = "One objective at a time" if game.tutorial else "Free shooting · no clock"
	if game.tutorial:
		_info_sub.text = ""
	elif d["mode"] == "versus":
		_info_sub.text = "Ball in hand" if d.get("ball_in_hand", false) else ("Open table" if d.get("open", true) else "Groups set")
	else:
		_info_sub.text = "Free shooting · move the cue ball any time with the hand button"


func _process(_delta: float) -> void:
	if game == null:
		return
	if _fl_hold != Vector3.ZERO and stage.free_look:
		stage.free_look_step(_fl_hold.x * _delta, _fl_hold.y * _delta, pow(_fl_hold.z, _delta))
	var d := game.info()
	for c in _cards:
		var i: int = c["index"]
		var t: float = d["clocks"][i]
		var lbl: Label = c["clock"]
		lbl.text = UIKit.fmt_clock(t)
		var active: bool = d["current"] == i
		var col := UIKit.TEXT if t > 60.0 else (UIKit.GOLD if t > 30.0 else UIKit.CORAL)
		if active and t <= 30.0 and game.state in [PoolGame.State.AIM, PoolGame.State.BALL_IN_HAND]:
			col.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 220.0))
		var want := col if active else Color(col, 0.55)
		if c.get("col") != want:
			# (a new colour makes the label lay itself out again: only when it really changes)
			c["col"] = want
			lbl.add_theme_color_override("font_color", want)
	var c := game.control
	if c and game.state == PoolGame.State.AIM and c.power > 0.01:
		_power_lbl.text = "%d%%" % int(c.power * 100)
		var pc := UIKit.EMERALD.lerp(UIKit.CORAL, maxf(c.power - 0.6, 0.0) * 2.5)
		if _power_col != pc:
			_power_col = pc
			_power_lbl.add_theme_color_override("font_color", pc)
	elif _power_lbl.text != "":
		_power_lbl.text = ""
	_update_ar_badge()
	if _lift_dir != 0 and _adjust_panel.visible:
		# button held: after a short delay keep moving, 12 cm a second
		_lift_hold += get_process_delta_time()
		if _lift_hold > 0.35:
			stage.lift_table(0.12 * get_process_delta_time() * _lift_dir)
			_update_adjust_label()
	if _elev.visible and game.control:
		# the stick can't go through the rail: the slider's floor follows the aim and the cue ball
		_elev.set_floor(game.min_elevation(game.control.yaw, game.control.offset), game.cue_on_ball(game.control.yaw, game.control.offset))
	if Game.get_s("show_fps"):
		_fps.text = stage.tracking_status()     # (the frame rate has its own counter now: FpsCounter)
	elif _fps.text != "":
		_fps.text = ""
	# the overlay only draws the Slingshot's pull: redrawn while there is one, and once more to clear it
	var pull := game.state == PoolGame.State.AIM and c is ControlSlingshot
	if pull or _overlay_live:
		_overlay.queue_redraw()
	_overlay_live = pull
	if _ar_panel.visible:
		_update_ar_panel()


## The AR panel has three faces: starting up, can't start (why + what to do), and placing the table.
func _update_ar_panel() -> void:
	(_ar_panel as ArPlacePanel).refresh()


func _draw_overlay() -> void:
	if game == null or game.state != PoolGame.State.AIM:
		return
	var c := game.control
	if c is ControlSlingshot:
		var o: Dictionary = (c as ControlSlingshot).overlay()
		if o["active"]:
			var col := UIKit.CORAL if o["cancel"] else UIKit.EMERALD
			_overlay.draw_line(o["start"], o["cur"], Color(col, 0.75), 6.0, true)
			_overlay.draw_circle(o["start"], 16.0, Color(col, 0.5))
			_overlay.draw_arc(o["cur"], 46.0, -PI / 2, -PI / 2 + TAU * float(o["power"]), 48, col, 10.0, true)
			_overlay.draw_arc(o["cur"], 46.0, 0, TAU, 48, Color(1, 1, 1, 0.15), 3.0, true)
			if o["cancel"]:
				_overlay.draw_string(UIKit.font(700), Vector2(o["start"]) + Vector2(-80, -40), L.t("CANCEL"), HORIZONTAL_ALIGNMENT_CENTER, 160, 26, UIKit.CORAL)
