class_name ArPlacePanel
extends PanelContainer
## Putting the table down in the room (walk-around AR): starting up, can't start (why, and what to do), and
## placing. v1.1.15: one panel for the match (HUD) and the main menu's "Place world" (WorldScreens), which used to
## live inside the HUD.

signal without_ar          ## "Play in place" instead (no camera)

var stage: Stage
var lbl: Label
var detail: Label
var sizes: HBoxContainer
var adjust: HBoxContainer       ## turn and size the table before placing it
var turn_l: Button
var turn_r: Button
var size_slider: HSlider
var size_val: Label
var _desk: Button
var _floor: Button
var place: Button
var retry: Button
var install: Button
var settings_b: Button
var studio: Button
var hint: Label


func _init(p_stage: Stage) -> void:
	stage = p_stage
	var v := UIKit.vbox(14)
	add_child(v)
	lbl = UIKit.label("Starting walk-around AR…", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 760
	v.add_child(lbl)
	# small print when AR can't start: the exact error and device facts (a screenshot of this is all
	# that's needed to diagnose a phone-specific problem)
	detail = UIKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # (the phone's own error and the AR version, as reported)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 760
	detail.visible = false
	v.add_child(detail)
	# after "Open Play Store": how to come back (Randy: "make it easy for them to return to the game")
	hint = UIKit.label("After installing, come back to Emerald 8 Ball Pool: AR starts by itself.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 760
	hint.visible = false
	v.add_child(hint)
	sizes = UIKit.hbox(14)
	sizes.alignment = BoxContainer.ALIGNMENT_CENTER
	var desk := UIKit.button("Mini", "ChipButton")
	var floor_b := UIKit.button("Life-size", "ChipButton")
	_desk = desk
	_floor = floor_b
	desk.toggle_mode = true
	floor_b.toggle_mode = true
	var grp := ButtonGroup.new()
	desk.button_group = grp
	floor_b.button_group = grp
	desk.button_pressed = Game.get_s("surface") != "floor"
	floor_b.button_pressed = Game.get_s("surface") == "floor"
	# (each keeps the size last chosen for it in Settings → World size)
	desk.pressed.connect(func(): Game.set_world_size(minf(float(Game.get_s("ar_scale_desk")), Game.WORLD_FLOOR_FROM - 0.01)))
	floor_b.pressed.connect(func(): Game.set_world_size(maxf(float(Game.get_s("ar_scale_floor")), Game.WORLD_FLOOR_FROM)))
	sizes.add_child(desk)
	sizes.add_child(floor_b)
	v.add_child(sizes)
	# v1.1.15 (Randy, 18 Nov: "the player should be able to rotate and scale the table size before placing it"):
	# the arrows turn it 15° a tap, the slider sizes it (Settings → World size); two fingers on the screen do the
	# same (twist to turn, pinch to size)
	adjust = UIKit.hbox(12)
	adjust.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_l = UIKit.icon_button("rot_left", 76, "Turn left")
	turn_l.name = "TurnLeft"
	turn_l.pressed.connect(func(): stage.turn_preview(deg_to_rad(15.0)))
	turn_r = UIKit.icon_button("rot_right", 76, "Turn right")
	turn_r.name = "TurnRight"
	turn_r.pressed.connect(func(): stage.turn_preview(-deg_to_rad(15.0)))
	adjust.add_child(turn_l)
	adjust.add_child(turn_r)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	adjust.add_child(gap)
	adjust.add_child(IconGlyph.make("size", 40, UIKit.MUTED))
	size_slider = Widgets.TouchSlider.new()
	size_slider.name = "PlaceSize"
	size_slider.min_value = Game.WORLD_MIN
	size_slider.max_value = Game.WORLD_MAX
	size_slider.step = 0.01
	size_slider.value = Game.world_size()
	size_slider.custom_minimum_size = Vector2(330, 56)
	size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_slider.value_changed.connect(func(x: float): stage.resize_preview(x))
	adjust.add_child(size_slider)
	size_val = UIKit.label(_size_text(Game.world_size()), "AccentLabel")
	size_val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size_val.custom_minimum_size.x = 150
	adjust.add_child(size_val)
	v.add_child(adjust)
	var row2 := UIKit.hbox(14)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	place = UIKit.button("Place table", "PrimaryButton", "check", 360)
	place.pressed.connect(func(): stage.place_table())
	retry = UIKit.button("Try again", "PrimaryButton", "refresh", 280)
	retry.pressed.connect(func(): stage.retry_ar())
	retry.visible = false
	install = UIKit.button("Open Play Store", "PrimaryButton", "camera", 340)
	install.pressed.connect(func(): stage.install_world_ar())
	install.visible = false
	settings_b = UIKit.button("Open app settings", "PrimaryButton", "gear", 360)
	settings_b.pressed.connect(func(): stage.open_app_settings())
	settings_b.visible = false
	studio = UIKit.button("Play in place", "GhostButton", "cube")
	studio.pressed.connect(func(): without_ar.emit())
	row2.add_child(place)
	row2.add_child(install)
	row2.add_child(settings_b)
	row2.add_child(retry)
	row2.add_child(studio)
	v.add_child(row2)


static func _size_text(x: float) -> String:
	return L.t("Life-size") if x >= 0.995 else "%d%%" % roundi(x * 100.0)


## Bottom centre of `area`.
func place_in(area: Vector2) -> void:
	reset_size()
	position = Vector2((area.x - size.x) * 0.5, area.y - size.y - 28)


## Called every frame while shown: the face that fits what AR is doing now.
func refresh() -> void:
	var st: int = stage.ar_state if stage.mode == Stage.Mode.WORLD_AR else Stage.ArState.OFF
	var blocked := st == Stage.ArState.BLOCKED
	place.visible = not blocked
	place.disabled = not stage.can_place()
	sizes.visible = not blocked
	adjust.visible = not blocked
	# the size may have changed elsewhere (a pinch, the Mini / Life-size chips): show it
	var ws := Game.world_size()
	if absf(size_slider.value - ws) > 0.004:
		size_slider.set_value_no_signal(ws)
	var vt := _size_text(ws)
	if size_val.text != vt:
		size_val.text = vt
	var on_floor: bool = Game.get_s("surface") == "floor"
	if _floor.button_pressed != on_floor:
		_floor.set_pressed_no_signal(on_floor)
		_desk.set_pressed_no_signal(not on_floor)
	detail.visible = blocked
	install.visible = blocked and stage.ar_can_install()
	hint.visible = install.visible
	settings_b.visible = blocked and stage.ar_block == "permission"
	retry.visible = blocked
	var text := ""
	match st:
		Stage.ArState.BLOCKED:
			text = stage.ar_block_text()
			detail.text = stage.ar_detail()
		Stage.ArState.PERMISSION:
			text = "Allow camera access so the table can appear in your room."
		Stage.ArState.CHECKING, Stage.ArState.STARTING:
			text = "Starting walk-around AR…"
		Stage.ArState.RUNNING:
			if stage.arcore.tracking != 2:
				var why := stage.arcore.failure_text()
				text = (why + " · " if why != "" else "") + L.t("Move your phone slowly so it can learn the room…")
			elif stage.surface_found():
				text = "Floor found ✓  Point where the table should stand and tap Place — then walk around it, it stays put."
			elif stage.can_place():
				text = "Floor not locked yet — tap Place to use this spot, or keep sweeping the phone over the floor."
			else:
				text = "Point the phone at the floor and sweep it slowly side to side until the table appears."
	if lbl.text != text:
		lbl.text = text
