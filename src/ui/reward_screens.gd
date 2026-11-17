class_name RewardScreens
extends RefCounted
## Levels and packages on screen: the XP bar, the package page with its opening animation, the reward card.


## ------------------------------------------------------------ XP bar with the level badge
class XpBar extends Control:
	signal leveled(level: int)

	var shown := 0.0          # the XP total the bar is showing right now
	var _lvl := 0
	var _pulse := 0.0

	func _init(w := 520.0) -> void:
		custom_minimum_size = Vector2(w, 92)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_xp(float(Game.xp()))

	func set_xp(x: float) -> void:
		shown = x
		_lvl = XP.level_of(int(x))
		queue_redraw()

	## Fills from one XP total to another; `leveled` fires each time a level is passed.
	func run(from: float, to: float, dur := 1.4) -> Tween:
		set_xp(from)
		var tw := create_tween()
		tw.tween_method(_step, from, to, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return tw

	func _step(x: float) -> void:
		var l := XP.level_of(int(x))
		if l > _lvl:
			_lvl = l
			_pulse = 1.0
			leveled.emit(l)
		shown = x
		queue_redraw()

	func _process(delta: float) -> void:
		if _pulse > 0.0:
			_pulse = maxf(0.0, _pulse - delta * 1.6)
			queue_redraw()

	func _draw() -> void:
		var f := UIKit.font(800)
		var f2 := UIKit.font(600)
		var xp_i := int(shown)
		var lvl := XP.level_of(xp_i)
		var part: Array = XP.into_level(xp_i)
		var frac := clampf((shown - float(XP.total_for(lvl))) / float(part[1]), 0.0, 1.0) if lvl < XP.MAX_LEVEL else 1.0
		var rc := GearScreens.rarity_color(XP.rarity_of_level(mini(lvl + 1, XP.MAX_LEVEL)))
		# badge
		var c := Vector2(44, size.y * 0.5)
		var r := 40.0 + _pulse * 8.0
		draw_circle(c, r, Color(0.05, 0.08, 0.13, 0.95))
		draw_arc(c, r - 3.0, 0, TAU, 48, rc.lerp(Color.WHITE, _pulse), 5.0, true)
		var ls := str(lvl)
		var fs := 40 if lvl < 100 else 30
		var tw := f.get_string_size(ls, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), ls, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.TEXT)
		# bar
		var x0 := 104.0
		var w := size.x - x0
		var y := size.y * 0.5 + 6.0
		var back := StyleBoxFlat.new()
		back.bg_color = Color(1, 1, 1, 0.1)
		back.set_corner_radius_all(11)
		draw_style_box(back, Rect2(x0, y, w, 22))
		if frac > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = UIKit.EMERALD.lerp(Color.WHITE, _pulse * 0.7)
			fill.set_corner_radius_all(11)
			draw_style_box(fill, Rect2(x0, y, maxf(22.0, w * frac), 22))
		draw_string(f, Vector2(x0, y - 12.0), L.t("LEVEL %d") % lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.TEXT)
		var right := "%d / %d XP" % [int(part[0]), int(part[1])] if lvl < XP.MAX_LEVEL else "MAX"
		var rw := f2.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f2, Vector2(x0 + w - rw, y - 12.0), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.MUTED)


## ------------------------------------------------------------ rays behind a reward
class Rays extends Control:
	var color := Color.WHITE
	var _t := 0.0

	func _init(c: Color) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var rad := maxf(size.x, size.y) * 0.75
		for i in 14:
			var a := TAU * i / 14.0 + _t * 0.25
			var wdt := 0.11
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - wdt), sin(a - wdt)) * rad, c + Vector2(cos(a + wdt), sin(a + wdt)) * rad]),
				Color(color, 0.1 + 0.04 * sin(_t * 2.0 + i)))
		for k in 5:
			draw_circle(c, 210.0 - k * 34.0, Color(color, 0.05))


## ------------------------------------------------------------ the reward card (after a package opens)
class Reveal extends Control:
	signal closed(open_next: bool)

	var got: Dictionary
	var more := 0

	func _init(p_got: Dictionary, p_more := 0) -> void:
		got = p_got
		more = p_more
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.03, 0.07, 0.9)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		add_child(bg)
		var r := int(got.get("rarity", 1))
		var rays := Rays.new(GearScreens.rarity_color(r))
		UIKit.fullrect(rays)
		add_child(rays)
		var v := UIKit.vbox(16)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var top := UIKit.label("NEW REWARD", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER)
		top.add_theme_color_override("font_color", GearScreens.rarity_color(r))
		v.add_child(top)
		var holder := CenterContainer.new()
		var card: Control
		if got.has("id"):
			var e := Catalog.find(Catalog.kind_list(str(got["kind"])), str(got["id"]))
			card = GearScreens.tile(str(got["kind"]), e, "owned", 400.0)
			(card as Button).disabled = true
			var kind_lbl := UIKit.label(GearScreens.KIND_ONE[str(got["kind"])], "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
			v.add_child(kind_lbl)
		else:
			card = UIKit.label("+%d XP" % int(got.get("xp", 0)), "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
		holder.add_child(card)
		v.add_child(holder)
		var row := UIKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if got.has("id"):
			var use := UIKit.button("Use it now", "", "check", 320)
			use.pressed.connect(func():
				Sfx.ui("toggle")
				Game.set_s(Game.GEAR_KEYS[str(got["kind"])], str(got["id"]))
				use.disabled = true)
			row.add_child(use)
		if more > 0:
			var nxt := UIKit.button(L.t("Open the next one (%d)") % more, "PrimaryButton", "chev_right", 360)
			nxt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			nxt.pressed.connect(func():
				Sfx.ui("tap")
				closed.emit(true)
				queue_free())
			row.add_child(nxt)
		var done := UIKit.button("Done", "GhostButton" if more > 0 else "PrimaryButton", "check", 260)
		done.pressed.connect(func():
			Sfx.ui("tap")
			closed.emit(false)
			queue_free())
		row.add_child(done)
		v.add_child(row)
		UIKit.center_in(self, v)
		# the card pops in
		card.pivot_offset = card.custom_minimum_size * 0.5
		if not Game.get_s("reduced_motion"):
			card.scale = Vector2(0.2, 0.2)
			card.modulate.a = 0.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "modulate:a", 1.0, 0.2)
		UIKit.fade_in(row, 0.5)
		Sfx.play("win", 0.5)


## ------------------------------------------------------------ the package page
class PackageScreen extends MenuScreens.Screen:
	var _stage: CenterContainer
	var _view: PackageView
	var _title: Label
	var _sub: Label
	var _wait: Label
	var _open_btn: Button
	var _ad_btn: Button
	var _all_btn: Button
	var _busy := false
	var _shown_level := -1
	var _tick: Timer

	func _ready() -> void:
		scrim(0.86)
		header("Packages")
		var v := UIKit.vbox(10)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		_stage = CenterContainer.new()
		_stage.custom_minimum_size = Vector2(620, 520)
		v.add_child(_stage)
		_title = UIKit.label("", "H2Label", HORIZONTAL_ALIGNMENT_CENTER)
		_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(_title)
		_sub = UIKit.label("", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(_sub)
		_wait = UIKit.label("", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
		_wait.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_wait.name = "UnlockTime"
		v.add_child(_wait)
		var row := UIKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_open_btn = UIKit.button("Open package", "PrimaryButton", "gift", 360)
		_open_btn.pressed.connect(func(): _open(false, false))
		row.add_child(_open_btn)
		# the free way is to wait; an advert (the player's choice) opens a package that is still unlocking
		_ad_btn = UIKit.button("Watch an ad to open it now", "PrimaryButton", "play", 480)
		_ad_btn.name = "PackageAdButton"
		_ad_btn.pressed.connect(func(): _open(false, true))
		row.add_child(_ad_btn)
		_all_btn = UIKit.button(" ", "", "gift", 340)
		_all_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_all_btn.pressed.connect(func(): _open(true, false))
		row.add_child(_all_btn)
		v.add_child(row)
		var holder := UIKit.center_in(self, v)
		holder.offset_top = 110
		_tick = Timer.new()
		_tick.wait_time = 1.0
		_tick.timeout.connect(func():
			if not _busy:
				_refresh())
		add_child(_tick)
		_tick.start()
		_refresh()

	func _refresh() -> void:
		var q: Array = Game.packages()
		var front := int(q[0]) if not q.is_empty() else -1
		if front != _shown_level or _view == null:
			for c in _stage.get_children():
				c.queue_free()
			_view = null
			_shown_level = front
			if q.is_empty():
				var none := UIKit.vbox(14)
				none.alignment = BoxContainer.ALIGNMENT_CENTER
				var ic := IconGlyph.make("gift", 150, Color(1, 1, 1, 0.25))
				ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				none.add_child(ic)
				_stage.add_child(none)
			else:
				_view = PackageView.new(XP.rarity_of_level(front), 500.0)
				_stage.add_child(_view)
		_open_btn.visible = false
		_ad_btn.visible = false
		_all_btn.visible = false
		_wait.text = ""
		if q.is_empty():
			_title.text = L.t("No packages to open")
			_title.remove_theme_color_override("font_color")
			_sub.text = L.t("Every new level brings one. Level %d is next.") % mini(Game.level() + 1, XP.MAX_LEVEL) if Game.level() < XP.MAX_LEVEL else ""
			return
		var r := XP.rarity_of_level(front)
		_title.text = L.t(PackageView.NAMES[r])      # translated since v1.1.9 (Randy: "if they show up in game to users yes")
		_title.add_theme_color_override("font_color", GearScreens.rarity_color(r))
		_sub.text = L.t("Level %d reward · %s · %d to open") % [front, GearScreens.rarity_name(r), q.size()]
		var left := Game.package_left(front)
		var ready := Game.packages_ready()
		if left <= 0:
			_open_btn.visible = true
			_all_btn.visible = ready > 1
			_all_btn.text = L.t("Open all (%d)") % ready
		else:
			_wait.text = L.t("Unlocks by itself in %s") % XP.clock(left)
			_ad_btn.visible = Ads.active()

	func _open(all: bool, by_ad: bool) -> void:
		if _busy or Game.packages().is_empty():
			return
		_busy = true
		for b in [_open_btn, _ad_btn, _all_btn]:
			b.disabled = true
		if by_ad:
			var got_it := [false]
			var finished := [false]
			var earned := func():
				got_it[0] = true
				finished[0] = true
			var closed_early := func(): finished[0] = true
			Ads.show("package", earned, closed_early)
			while not finished[0] and is_inside_tree():
				await get_tree().process_frame
			if not got_it[0]:
				_end_run()
				return
		_run(all, by_ad)

	func _end_run() -> void:
		_busy = false
		for b in [_open_btn, _ad_btn, _all_btn]:
			b.disabled = false
		_refresh()

	func _run(all: bool, first_by_ad: bool) -> void:
		var by_ad := first_by_ad
		while not Game.packages().is_empty() and is_inside_tree():
			if not by_ad and Game.packages_ready() == 0:
				break
			if _view == null:
				_shown_level = -1
				_refresh()
			_view.open(all)
			await _view.opened
			var got: Dictionary = Game.open_package(null, by_ad)
			by_ad = false
			var card := Reveal.new(got, Game.packages_ready())
			add_child(card)
			var again: bool = await card.closed
			_shown_level = -1
			_refresh()
			if not again:
				break
		_end_run()


## ------------------------------------------------------------ the XP chest page
## Randy, 11 Nov: the chest holds half of the current level's XP. It is ready every 6 hours; watching an advert
## (the player's choice, offered with the reward named on the button) makes the wait 2 hours instead. Randy, 12 Nov:
## the button says "Open 4 Hours Faster With Ad" (or, when the advert would open it at once, "Watch an ad to open it
## now").
class ChestScreen extends MenuScreens.Screen:
	var _stage: CenterContainer
	var _view: PackageView
	var _status: Label
	var _sub: Label
	var _note: Label
	var _open_btn: Button
	var _ad_btn: Button
	var _busy := false

	func _ready() -> void:
		scrim(0.86)
		header("XP chest")
		var v := UIKit.vbox(10)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		_stage = CenterContainer.new()
		_stage.custom_minimum_size = Vector2(620, 500)
		v.add_child(_stage)
		var title := UIKit.label("XP chest", "H2Label", HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_color_override("font_color", PackageView.XP_GOLD)
		v.add_child(title)
		_sub = UIKit.label("", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(_sub)
		_status = UIKit.label("", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
		_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_status.name = "ChestStatus"
		v.add_child(_status)
		var row := UIKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_open_btn = UIKit.button("Open XP chest", "PrimaryButton", "gift", 380)
		_open_btn.name = "OpenChest"
		_open_btn.pressed.connect(_open)
		row.add_child(_open_btn)
		_ad_btn = UIKit.button(" ", "PrimaryButton", "play", 520)
		_ad_btn.name = "ChestAdButton"
		_ad_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_ad_btn.pressed.connect(_watch)
		row.add_child(_ad_btn)
		v.add_child(row)
		_note = UIKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(_note)
		var holder := UIKit.center_in(self, v)
		holder.offset_top = 110
		var tick := Timer.new()
		tick.wait_time = 1.0
		tick.timeout.connect(func():
			if not _busy:
				_refresh())
		add_child(tick)
		tick.start()
		_new_view()
		_refresh()

	func _new_view() -> void:
		for c in _stage.get_children():
			c.queue_free()
		_view = PackageView.xp_chest(480.0)
		_stage.add_child(_view)

	func _refresh() -> void:
		var top := Game.level() >= XP.MAX_LEVEL
		var gifts := Game.gift_chests().size()
		var ready := Game.chest_ready() or gifts > 0
		_sub.text = L.t("Half a level of XP: +%d XP at level %d") % [Game.chest_xp(), Game.level()] if not top else L.t("You are at the top level.")
		_open_btn.visible = ready and not top
		_ad_btn.visible = false
		if top:
			_status.text = ""
		elif gifts > 0:
			# v1.1.15: a gift chest (the tutorial, sharing): open now, no timer, no advert
			var why := str(Game.gift_chests()[0])
			_status.text = L.t("A gift for sharing the game: open it now!") if why == "share" else L.t("A gift for finishing the tutorial: open it now!")
			if gifts > 1:
				_status.text += "  ×%d" % gifts
			_status.add_theme_color_override("font_color", PackageView.XP_GOLD)
		elif ready:
			_status.text = L.t("Ready to open!")
			_status.add_theme_color_override("font_color", PackageView.XP_GOLD)
		else:
			_status.text = L.t("Ready in %s") % XP.clock(Game.chest_left())
			_status.remove_theme_color_override("font_color")
			if Ads.active() and Game.can_cut_chest():
				# the reward is named on the button itself (AdMob: clear disclosure before the advert)
				var after := maxi(0, int(Game.progress.get("chest_from", 0)) + XP.CHEST_WAIT_AD - Game.now())
				_ad_btn.text = L.t("Watch an ad to open it now") if after == 0 else L.t("Open 4 Hours Faster With Ad")
				_ad_btn.visible = true
		_note.text = L.t("A new XP chest every 6 hours, or every 2 hours with an ad.") if Ads.active() else L.t("A new XP chest every 6 hours.")

	func _watch() -> void:
		if _busy or not Game.can_cut_chest():
			return
		_busy = true
		_ad_btn.disabled = true
		var finished := [false]
		var earned := func():
			Game.cut_chest()
			finished[0] = true
		var closed_early := func(): finished[0] = true
		Ads.show("xp_chest", earned, closed_early)
		while not finished[0] and is_inside_tree():
			await get_tree().process_frame
		_busy = false
		_ad_btn.disabled = false
		_refresh()

	func _open() -> void:
		var gift := not Game.gift_chests().is_empty()
		if _busy or not (Game.chest_ready() or gift):
			return
		_busy = true
		_open_btn.disabled = true
		_view.open()
		await _view.opened
		var got: Dictionary = Game.open_gift_chest() if gift else Game.open_chest()
		if not got.is_empty() and is_inside_tree():
			var card := XpReveal.new(router, got)
			add_child(card)
			await card.closed
		if not is_inside_tree():
			return
		_new_view()
		_busy = false
		_open_btn.disabled = false
		_refresh()


## ------------------------------------------------------------ what the XP chest gave
class XpReveal extends Control:
	signal closed

	var router: Node
	var got: Dictionary

	func _init(p_router: Node, p_got: Dictionary) -> void:
		router = p_router
		got = p_got
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.03, 0.07, 0.9)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		add_child(bg)
		var rays := Rays.new(PackageView.XP_GOLD)
		UIKit.fullrect(rays)
		add_child(rays)
		var v := UIKit.vbox(18)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var top := UIKit.label("XP CHEST", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER)
		top.add_theme_color_override("font_color", PackageView.XP_GOLD)
		v.add_child(top)
		var amount := UIKit.label("+%d XP" % int(got.get("xp", 0)), "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
		amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		amount.add_theme_font_size_override("font_size", 120)
		amount.add_theme_color_override("font_color", PackageView.XP_GOLD)
		amount.name = "ChestAmount"
		v.add_child(amount)
		var bar_box := CenterContainer.new()
		var bar := XpBar.new(640.0)
		bar_box.add_child(bar)
		v.add_child(bar_box)
		var up := UIKit.label(" ", "H2Label", HORIZONTAL_ALIGNMENT_CENTER)
		up.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		up.add_theme_color_override("font_color", UIKit.EMERALD)
		up.modulate.a = 0.0
		up.name = "ChestLevelUp"
		v.add_child(up)
		var row := UIKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var gain: Dictionary = got.get("gain", {})
		if int(gain.get("to", 0)) > int(gain.get("from", 0)):
			var pk := UIKit.button(L.t("Open packages (%d)") % Game.packages().size(), "", "gift", 440)
			pk.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			pk.pressed.connect(func():
				Sfx.ui("tap")
				closed.emit()
				router.call("go", "packages"))
			row.add_child(pk)
		var done := UIKit.button("Done", "PrimaryButton", "check", 260)
		done.pressed.connect(func():
			Sfx.ui("tap")
			closed.emit()
			queue_free())
		row.add_child(done)
		v.add_child(row)
		UIKit.center_in(self, v)
		Sfx.play("win", 0.5)
		# the number pops in, then the bar fills; each level passed flashes LEVEL UP!
		amount.pivot_offset = amount.get_combined_minimum_size() * 0.5
		var up_text := func(lv: int) -> String:
			return L.t("LEVEL UP!  Level %d · new package: %s") % [lv, GearScreens.rarity_name(XP.rarity_of_level(lv))]
		bar.leveled.connect(func(l: int):
			Sfx.play("rack", 0.6)
			Game.vibrate(40)
			up.text = up_text.call(l)
			up.modulate.a = 1.0
			up.pivot_offset = up.size * 0.5
			up.scale = Vector2(1.3, 1.3)
			create_tween().tween_property(up, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK))
		var from := float(gain.get("xp_from", Game.xp()))
		var to := float(gain.get("xp_to", Game.xp()))
		bar.set_xp(from)
		if Game.get_s("reduced_motion"):
			bar.set_xp(to)
			if int(gain.get("to", 0)) > int(gain.get("from", 0)):
				up.text = up_text.call(int(gain["to"]))
				up.modulate.a = 1.0
		else:
			amount.scale = Vector2(0.3, 0.3)
			amount.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(amount, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(amount, "modulate:a", 1.0, 0.2)
			tw.tween_interval(0.2)
			tw.tween_callback(func(): bar.run(from, to, 1.2))
		UIKit.fade_in(row, 0.6)
