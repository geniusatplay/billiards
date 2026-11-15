extends Node
## App root: owns the 3D Stage, the UI layer, screen navigation and the active match.

var stage: Stage
var ui_layer: CanvasLayer
var ui_root: Control
var screen_host: Control
var overlay_host: Control
var hud: HUD
var game: PoolGame
var _stack: Array[String] = []
var _screen: Control
var _debug: Control
var _pause: Control
var _results: Control
var _ad_due := false   # in memory only, never saved: a game closed on the score screen skips that advert (showing it at the next launch would be an advert at app launch, which the store rules forbid)
var _last_cfg: Dictionary = {}
var _touch_count := 0
var _toast_lbl: Label
## Gear whose shaders are already built (drawn once behind a cover): "cue:<id>", "balls:<id>", "table:<id>".
var _warmed := {}
var warm_enabled := true     # (the automated tour runs without the warm-up unless it is given --warmup)
var _first_match := true     # the first match of a launch also starts behind the short cover (see _cover_and_warm)


func _ready() -> void:
	print("[boot] engine ready at %d ms" % Time.get_ticks_msec())
	# The first frame with the 3D table in it takes seconds on a phone (shaders are compiled on first use).
	# So a plain loading screen goes up first and is drawn before the table is even created.
	var loading := _make_loading()
	add_child(loading)
	add_child(FpsCounter.new())
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw   # (never fires without a screen)
	print("[boot] loading screen shown at %d ms" % Time.get_ticks_msec())
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	print("[boot] 3D stage built at %d ms" % Time.get_ticks_msec())
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	ui_root = UIKit.fullrect(Control.new())
	ui_root.theme = UIKit.theme()
	print("[boot] theme + fonts at %d ms" % Time.get_ticks_msec())
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)
	screen_host = UIKit.fullrect(Control.new())
	screen_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(screen_host)
	overlay_host = UIKit.fullrect(Control.new())
	overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(overlay_host)
	_toast_lbl = UIKit.label("", "H3Label", HORIZONTAL_ALIGNMENT_CENTER)
	_toast_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_lbl.offset_top = -140
	_toast_lbl.offset_left = -500
	_toast_lbl.offset_right = 500
	ui_root.add_child(_toast_lbl)
	stage.set_idle_spin(true)
	Sfx.music(true)
	get_viewport().size_changed.connect(_on_resize)
	_fit_safe_area()
	get_tree().create_timer(0.5).timeout.connect(_fit_safe_area)   # iOS knows the final safe area only once shown
	Loc.language_changed.connect(_on_language_changed)
	var tour := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			tour = a.substr(7)
	if tour != "":
		warm_enabled = "--warmup" in OS.get_cmdline_user_args()
		if warm_enabled:
			await _warm_up()
		loading.queue_free()
		stage.watch_frame_rate = false
		_run_tour(tour)
	else:
		await _warm_up()
		go("menu")
		print("[boot] menu built at %d ms" % Time.get_ticks_msec())
		await RenderingServer.frame_post_draw
		print("[boot] first frame drawn at %d ms" % Time.get_ticks_msec())
		await RenderingServer.frame_post_draw
		print("[boot] second frame drawn at %d ms" % Time.get_ticks_msec())
		var cover: Control = loading.get_child(0)
		var tw := create_tween()
		tw.tween_property(cover, "modulate:a", 0.0, 0.35)
		tw.tween_callback(loading.queue_free)


## Behind the loading screen, everything a first match shows is drawn once with the real lights (the player's
## balls and cue, the aim guide, the ball-in-hand ring, the pocket sparkle, a control's own marker; and on phones
## with walk-around AR the same again the way AR shows it). The phone builds those shaders now, while "Loading…" is
## up, instead of stalling the first shot (Randy, 11 Nov 2026: "compiling shaders on load"). Gear not known yet
## (the CPU's cue, an online opponent's cue, table and balls) is drawn under a short cover when a match starts.
## (The CPU's six cues were tried here too: on the emulator they made loading 21 s instead of about 8.)
func _warm_up() -> void:
	var t0 := Time.get_ticks_msec()
	FpsCounter.phase = "loading: preparing shaders"
	# the match's own screen too (its buttons, pads, the turn banner growing in, the hint line): the first match of
	# a launch used to stall for about a second while all of it was drawn for the first time
	var h := HUD.new()
	h.name = "WarmupHud"
	ui_root.add_child(h)
	var layer: Control = UIKit.fullrect(Control.new())
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(layer)
	var g := PoolGame.new()
	g.name = "Warmup"
	add_child(g)
	g.setup(stage, layer, {"mode": "practice", "warmup": true})
	h.setup(g, stage)
	g.begin()
	await g.warm_draw(2)
	if stage.auto_mode() != Stage.Mode.STUDIO:
		stage.warm_ar_look(true)
		await g.warm_draw(2)
		stage.warm_ar_look(false)
	var t_banner := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_banner < 450 and DisplayServer.get_name() != "headless":
		await get_tree().process_frame     # the banner's grow-in, frame by frame
	_mark_warm(g)      # (a practice match: both seats hold the player's own cue)
	g.queue_free()
	h.queue_free()
	print("[boot] shaders prepared in %d ms" % (Time.get_ticks_msec() - t0))


func _mark_warm(g: PoolGame) -> void:
	for c in g.cue_skins:
		_warmed["cue:" + str(c)] = true
	_warmed["balls:" + g.ball_set] = true
	_warmed["table:" + str(stage.table_style().get("id", ""))] = true


## True when the match on now uses gear not drawn yet (another player's, or gear just chosen).
func _needs_warm(g: PoolGame) -> bool:
	for c in g.cue_skins:
		if not _warmed.has("cue:" + str(c)):
			return true
	return not _warmed.has("balls:" + g.ball_set) or not _warmed.has("table:" + str(stage.table_style().get("id", "")))


## A match with gear the phone has not drawn yet (an online opponent's cue, table or balls; a cue or ball set just
## picked) starts behind a short fade from the menu's dark colour, while that gear is drawn once. So does the first
## match of a launch: on the emulator its second frame took most of a second although everything in it had been drawn
## on the loading screen (the graphics driver finishing its own work), so the cover stays until a frame comes in
## quick (at most 3 s). The match itself waits meanwhile (no clock runs).
func _cover_and_warm() -> void:
	var g := game
	var layer := CanvasLayer.new()
	layer.layer = 90
	var cover := ColorRect.new()
	cover.color = UIKit.INK
	UIKit.fullrect(cover)
	layer.add_child(cover)
	var lbl := UIKit.label("Loading…", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	lbl.theme = UIKit.theme()
	UIKit.fullrect(lbl)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cover.add_child(lbl)
	add_child(layer)
	FpsCounter.phase = "match start: preparing"
	await g.warm_draw(2)
	if is_instance_valid(g) and g.is_inside_tree():
		_mark_warm(g)
		g.set("_warming", true)
		var t0 := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		while is_instance_valid(g) and Time.get_ticks_msec() - t0 < 3000 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			var quick := now - last < 50000
			last = now
			if quick and Time.get_ticks_msec() - t0 > 150:
				break
		if is_instance_valid(g):
			g.set("_warming", false)
	var tw := create_tween()
	tw.tween_property(cover, "modulate:a", 0.0, 0.25)
	tw.tween_callback(layer.queue_free)


## The loading screen: the game's name and "Loading…" on the menu's dark background, above everything else.
func _make_loading() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var cover := UIKit.fullrect(Control.new())
	cover.theme = UIKit.theme()
	layer.add_child(cover)
	var bg := ColorRect.new()
	bg.color = UIKit.INK
	UIKit.fullrect(bg)
	cover.add_child(bg)
	var v := UIKit.vbox(26)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.fullrect(v)
	cover.add_child(v)
	var gem := IconGlyph.make("gem", 150, UIKit.EMERALD)
	gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(gem)
	var title := UIKit.label(Game.TITLE.to_upper(), "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 0)
	v.add_child(title)
	v.add_child(UIKit.label("Loading…", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER))
	return layer


func _on_resize() -> void:
	_fit_safe_area()


## iPhone / iPad (v1.1.12): keep the controls clear of the notch / Dynamic Island and the home bar. Only the
## controls move in: the 3D view and the AR camera picture still fill the whole screen. Other platforms: no change.
func _fit_safe_area() -> void:
	if OS.get_name() == "iOS":
		apply_safe_area(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size())


## safe: the part of the screen free of the notch and home bar, in screen pixels; win: the screen size in pixels.
func apply_safe_area(safe: Rect2i, win: Vector2i) -> void:
	if ui_root == null or win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return
	var k := get_viewport().get_visible_rect().size / Vector2(win)   # screen pixels -> UI units
	ui_root.offset_left = maxf(0.0, safe.position.x) * k.x
	ui_root.offset_top = maxf(0.0, safe.position.y) * k.y
	ui_root.offset_right = -maxf(0.0, win.x - safe.end.x) * k.x
	ui_root.offset_bottom = -maxf(0.0, win.y - safe.end.y) * k.y


## Labels and buttons translate themselves; anything put together in code is rebuilt here.
func _on_language_changed() -> void:
	if hud:
		hud.on_language_changed()
	if game == null and _screen and not _stack.is_empty():
		_reshow_top.call_deferred()
	elif _pause is MenuScreens.Screen:
		_pause.queue_free()
		pause_and_open.call_deferred("settings")


## Rebuilds the menu screen that is open now (looked up when it runs, not when it was asked for).
func _reshow_top() -> void:
	if game == null and not _stack.is_empty():
		_show(_stack.back())


# ================================================================== navigation
func go(name: String, replace := false) -> void:
	if replace and not _stack.is_empty():
		_stack.pop_back()
	if _stack.is_empty() or _stack.back() != name:
		_stack.append(name)
	_show(name)


func back() -> void:
	if game != null:
		# Settings opened from the pause menu: Back returns to the pause menu, the match stays as it is
		if _pause and is_instance_valid(_pause):
			_pause.queue_free()
		_pause = null
		pause()
		return
	if _stack.size() > 1:
		_stack.pop_back()
	_show(_stack.back())


func _show(name: String) -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	var s: Control
	match name:
		"menu": s = MenuScreens.MainMenu.new(self)
		"vs_ai": s = MenuScreens.MatchSetup.new(self, true)
		"pass_play": s = MenuScreens.MatchSetup.new(self, false)
		"online": s = MenuScreens.OnlineScreen.new(self)
		"gear": s = GearScreens.GearScreen.new(self)
		"packages": s = RewardScreens.PackageScreen.new(self)
		"chest": s = RewardScreens.ChestScreen.new(self)
		"controls": s = MenuScreens.ControlsScreen.new(self)
		"settings": s = SettingsScreens.SettingsScreen.new(self)
		"help": s = MenuScreens.HelpScreen.new(self)
		_: s = MenuScreens.MainMenu.new(self)
	_screen = s
	FpsCounter.phase = "screen " + name
	screen_host.add_child(s)
	if game == null:
		Sfx.music_context(false)
		stage.set_mode(Stage.Mode.STUDIO)
		stage.set_view(Stage.View.OVERVIEW)
		stage.set_idle_spin(true)


func toast(text: String) -> void:
	_toast_lbl.text = text
	_toast_lbl.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_toast_lbl, "modulate:a", 0.0, 0.4)


# ================================================================== matches
func start_match(cfg: Dictionary) -> void:
	_close_overlays()
	_end_match()
	if cfg.get("online", false):
		# both phones must play on exactly the same table with the same physics: the standard ones
		Game.reset_physics()
		Game.reset_table()
	_last_cfg = cfg
	if _screen:
		_screen.queue_free()
		_screen = null
	get_tree().paused = false
	stage.set_idle_spin(false)
	stage.set_view(Stage.View.OVERVIEW)
	stage.set_mode(stage.auto_mode())
	stage.new_match_scene()   # (only shows with "Scene background in AR" on, once the table is placed)
	Sfx.music_context(true)
	game = PoolGame.new()
	game.name = "Match"
	add_child(game)
	hud = HUD.new()
	ui_root.add_child(hud)
	ui_root.move_child(hud, 1)
	hud_setup(cfg)


func hud_setup(cfg: Dictionary) -> void:
	# HUD needs the game for layout, the game needs the HUD's control layer for widgets
	var layer := UIKit.fullrect(Control.new())
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layer)
	game.setup(stage, layer, cfg)
	hud.setup(game, stage)
	hud.move_child(layer, hud.get_child_count() - 1)
	hud.pause_requested.connect(pause)
	game.game_over.connect(_on_game_over)
	game.rack_cleared.connect(_on_rack_cleared)
	game.begin()
	FpsCounter.mark("match built")
	if warm_enabled and (_needs_warm(game) or _first_match):
		_cover_and_warm()
	_first_match = false


func _end_match() -> void:
	stage.match_table = ""     # (the menu shows the player's own table again once it is rebuilt)
	if game:
		game.queue_free()
		game = null
	if hud:
		hud.queue_free()
		hud = null


func restart() -> void:
	if _last_cfg.is_empty() or _last_cfg.get("online", false):
		return
	start_match(_last_cfg.duplicate())


func quit_match() -> void:
	quit_to("menu")


## Leaving the score screen: "restart", "rerack", "menu", "packages" or "online". The between-matches advert comes first
## (only once adverts are switched on, see ads.gd).
func after_results(action: String) -> void:
	var due := _ad_due
	_ad_due = false
	var carry_on := func():
		match action:
			"restart":
				restart()
			"rerack":
				_close_overlays()
				if game:
					game.reset_rack()
			"packages":
				quit_to("menu")
				go("packages")
			"online":
				quit_to("menu")
				go("online")
			_:
				quit_to("menu")
	if due:
		Ads.show("after_match", carry_on)
	else:
		carry_on.call()


func quit_to(where: String) -> void:
	_close_overlays()
	get_tree().paused = false
	_end_match()
	stage.rebuild_table()
	_stack.clear()
	go(where)


func is_online() -> bool:
	return game != null and game.online


func pause() -> void:
	if game == null or _pause:
		return
	get_tree().paused = not game.online       # an online match goes on: the other player is waiting
	FpsCounter.phase = "pause menu"
	_pause = Overlays.PauseMenu.new(self)
	overlay_host.add_child(_pause)


func resume() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
	get_tree().paused = false


## Pause menu -> "Move / raise / lower table" (AR only, once the table is placed).
func can_move_table() -> bool:
	return game != null and stage.is_ar() and stage.placed


func move_table() -> void:
	resume()
	if hud:
		hud.open_table_adjust()


## Pause menu -> "Place the table again" (AR): start over with finding a spot for it.
func replace_table() -> void:
	resume()
	if hud:
		hud.replace_table()


func view_is_ar() -> bool:
	return game != null and stage.is_ar()


## Pause menu -> View: walk-around AR ("auto") or the Studio view ("studio"), switched in the middle of the match.
## Going to AR closes the pause menu, because the room has to be seen to put the table down.
func switch_view(to: String) -> void:
	Game.set_s("ar_mode", to)
	if game == null:
		return
	var want: int = stage.auto_mode()
	if to != "studio" and want == Stage.Mode.STUDIO:
		toast(L.t("Walk-around AR isn't included in this build of the game."))
		return
	if want == stage.mode:
		return
	stage.switch_mode(want)
	if want != Stage.Mode.STUDIO:
		resume()


## Pause menu -> Scene: the scenes that can be shown right now (round an AR table only the ones with a sky).
func pause_scenes() -> Array:
	var ar := view_is_ar()
	return Catalog.SCENES.filter(func(e): return e.get("ready", true) and Game.owns("scene", str(e["id"])) and (not ar or int(e.get("sky", 0)) != 0))


func pause_scene_id() -> String:
	return stage.ar_scene_id() if view_is_ar() else str(Game.get_s("scene"))


func set_pause_scene(id: String) -> void:
	if view_is_ar():
		stage.set_ar_scene(id)
	else:
		Game.set_s("scene", id)


func settings() -> void:
	resume()
	pause_and_open("settings")


func pause_and_open(name: String) -> void:
	# settings over a live match: show as an overlay screen, return with Back
	get_tree().paused = not is_online()
	var s: Control = SettingsScreens.SettingsScreen.new(self)
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_host.add_child(s)
	_pause = s


func _on_game_over(res: Dictionary) -> void:
	if res.has("xp"):
		# the XP is banked at once (so quitting during the score screen loses nothing); the screen animates it
		res["gain"] = Game.add_xp(int(res["xp"]["total"]))
	Game.count_match()
	# the between-matches advert plays as the player leaves the score screen (never at the start of a match)
	_ad_due = true
	await get_tree().create_timer(0.9).timeout
	if game == null:
		return
	FpsCounter.phase = "score screen"
	_results = Overlays.Results.new(self, res)
	overlay_host.add_child(_results)


## Practice: the whole rack is down. Its own little score screen; the advert follows it like any score screen.
func _on_rack_cleared(info: Dictionary) -> void:
	_ad_due = true
	await get_tree().create_timer(0.7).timeout
	if game == null:
		return
	_results = Overlays.RackCleared.new(self, info)
	overlay_host.add_child(_results)


func _close_overlays() -> void:
	for n in [_pause, _results]:
		if n and is_instance_valid(n):
			n.queue_free()
	_pause = null
	_results = null
	close_debug()


# ================================================================== debug hooks
func open_debug() -> void:
	if _debug:
		return
	_debug = SettingsScreens.DebugMenu.new(self)
	overlay_host.add_child(_debug)


func close_debug() -> void:
	if _debug and is_instance_valid(_debug):
		_debug.queue_free()
	_debug = null


func tracking_status() -> String:
	return stage.tracking_status()


func recalibrate() -> void:
	stage.tracker.reset()
	toast("Sensors recalibrating — move the phone around gently")


# ================================================================== input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_touch_count = _touch_count + 1 if ev.pressed else maxi(_touch_count - 1, 0)
		if ev.pressed and _touch_count == 3:
			if _debug:
				close_debug()
			else:
				open_debug()
			get_viewport().set_input_as_handled()
			return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_F3:
				if _debug: close_debug()
				else: open_debug()
			KEY_ESCAPE:
				if _pause: resume()
				elif game: pause()
				elif _stack.size() > 1: back()
	if game == null or get_tree().paused:
		return
	# 2-finger camera / AR gestures take priority unless the cue control is mid-stroke
	var ctl_busy := game.control != null and game.control.power > 0.0
	if not ctl_busy and stage.handle_gesture(ev):
		if game.control and game.control.has_method("cancel_touch"):
			game.control.call("cancel_touch")
		get_viewport().set_input_as_handled()
		return
	if game.handle_input(ev):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and game and not get_tree().paused:
		# Nothing to pause while AR is still starting or the table isn't placed yet - and the camera
		# permission dialog, the Play Store and Android Settings all send the app to the background.
		if not (stage.is_ar() and not stage.placed):
			pause()


# ================================================================== automated screenshot tour (QA)
## Looks at every visible Label / Button: English left in a non-Latin language, or text wider than its box.
const _AUDIT_OK := ["AR", "AI", "IA", "KI", "Emerald Break", "EMERALD VORTEX GAMES", "Play", "Google", "ARCore", "Apple", "ARKit", "Store", "Outfit", "Noto Sans",
	"SIL Open Font License", "Pool And Billiards SFX", "Suraj Kispotta", "CC0", "Emerald Vortex Games LLC", "cm", "Services for", "Emerald", "Classic",
	"Obsidian Gold", "Neon Pulse", "Vortex Spiral", "Midnight Blue", "Crimson Club", "Vortex Violet", "Graphite", "Lounge", "Neon Night", "Sunset Deck", "Desert Dusk", "Firefly Grove", "Aurora Lake", "Coral Deep", "Neon Skyline", "Sky Temple", "Crystal Cavern", "Magma Forge", "Synth Horizon", "Orbit Station",
	"Aurora", "Player", "English", "Español", "Français", "Deutsch", "Português", "Italiano", "8-ball", "8-BALL", "Pro", "CPU", "online", "Online", "ONLINE", "Nederlands", "Svenska", "Polski", "Čeština", "Română", "Türkçe", "Bahasa Indonesia", "Bahasa Melayu", "Tiếng Việt", "fps", "EMERALD BREAK", "tap", "for developer tools"]


## Language audit: every button of the open pause menu must be on the screen (1 problem if one is not).
func _pause_fits(code: String, where: String) -> int:
	if _pause == null:
		return 0
	var vr := get_viewport().get_visible_rect().grow(1.0)
	for pb in _pause.find_children("*", "Button", true, false):
		var rr: Rect2 = (pb as Control).get_global_rect()
		if (pb as Control).is_visible_in_tree() and not vr.encloses(rr):
			print("  OFF SCREEN [%s/%s] the pause menu does not fit: %s ends at y %d" % [code, where, (pb as Button).text.substr(0, 30), rr.end.y])
			return 1
	return 0


## (tour) Is there a visible label showing exactly `text` on `root`?
func cbtn_text_on(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text == text:
			return true
	return false


func _audit_text(code: String, where: String) -> int:
	var bad := 0
	var latin := RegEx.create_from_string("[A-Za-z]{3,}")
	var vp := get_viewport().get_visible_rect()
	for n in ui_root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or not (c is Label or c is Button):
			continue
		var raw: String = c.get("text")
		if raw.strip_edges() == "" or c.modulate.a < 0.05:
			continue
		var shown := c.tr(raw) if c.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else raw
		if code in ["ru", "uk", "el", "ja", "ko", "zh", "zh_TW", "ar", "he", "ur", "hi", "mr", "bn", "pa", "ta", "te", "th"] and c.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
			var rest := shown
			var okws := _AUDIT_OK + ["simulated"]
			# item names are proper names and stay in English everywhere
			for list in [Catalog.CUES, Catalog.TABLES, Catalog.BALLS, Catalog.SCENES]:
				okws.append_array(Catalog.names(list))
			okws.sort_custom(func(x, y): return x.length() > y.length())
			for okw in okws:
				rest = rest.replace(okw, "")
			if latin.search(rest):
				bad += 1
				print("  UNTRANSLATED [%s/%s] %s" % [code, where, shown.substr(0, 70)])
		var font := c.get_theme_font("font")
		var fs := c.get_theme_font_size("font_size")
		if c is Button:
			var sb := c.get_theme_stylebox("normal")
			var room := c.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT)
			var w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > room + 2.0:
				bad += 1
				print("  TOO WIDE [%s/%s] button %.0f > %.0f px: %s" % [code, where, w, room, shown.substr(0, 50)])
		elif c is Label:
			var l := c as Label
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and not l.clip_text:
				var w2 := font.get_multiline_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w2 > l.size.x + 2.0:
					bad += 1
					print("  TOO WIDE [%s/%s] label %.0f > %.0f px: %s" % [code, where, w2, l.size.x, shown.substr(0, 50)])
			elif l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_line_count() > l.get_visible_line_count() and l.max_lines_visible < 0:
				bad += 1
				print("  CUT OFF [%s/%s] label shows %d of %d lines: %s" % [code, where, l.get_visible_line_count(), l.get_line_count(), shown.substr(0, 50)])
		var r := c.get_global_rect()
		if r.position.x < -2.0 or r.end.x > vp.size.x + 2.0:   # sideways only: screens scroll up and down
			bad += 1
			print("  OFF SCREEN [%s/%s] %s" % [code, where, shown.substr(0, 50)])
	return bad


## Measuring (--only=perf --perf): first-time stalls along a player's first minutes, then the steady cost of
## every scene (aiming, the aim view, balls rolling). The software renderer of the test machine runs the shaders
## on the processor, so its milliseconds compare one scene / one change with another, not with a phone.
func _perf_tour(dir: String) -> void:
	var args := OS.get_cmdline_user_args()
	Game.set_s("ar_mode", "studio")
	Game.set_s("control_scheme", "pro_dial")
	var cold := not ("--warm-only" in args)
	if cold:
		FpsCounter.hitches.clear()
		var step := func(label: String, t: float) -> void:
			FpsCounter.phase = label
			await _wait(t)
		await step.call("menu", 2.0)
		go("menu")
		await step.call("menu", 1.5)
		start_match({"mode": "practice"})
		await step.call("practice start", 2.5)
		stage.set_view(Stage.View.AIM)
		await step.call("aim view", 1.5)
		game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
		FpsCounter.phase = "break shot"
		var t_roll := 0.0
		while game.state == PoolGame.State.ROLLING and t_roll < 9.0:
			await _wait(0.1)
			t_roll += 0.1
		await step.call("after the break", 1.5)
		start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
		await step.call("vs cpu start", 2.5)
		if game.state == PoolGame.State.BALL_IN_HAND:
			game.confirm_cue_placement()
		if game.state == PoolGame.State.AIM:
			game.fire(PI * 0.5, 0.15, Vector2.ZERO, 0.0)     # a soft miss: the CPU's turn
		var t_ai := 0.0
		while t_ai < 12.0 and game and not (game.state == PoolGame.State.AIM and game.is_human_turn() and t_ai > 2.0):
			FpsCounter.phase = "cpu turn" if not game.is_human_turn() else "rolling"
			await _wait(0.1)
			t_ai += 0.1
		if game:
			game._finish(0, "Sank the 8!")
		await step.call("score screen", 3.0)
		quit_to("menu")
		await step.call("menu again", 1.0)
		for scr in ["packages", "gear", "chest"]:
			go(scr)
			await step.call("screen " + scr, 2.0)
		go("menu")
		await step.call("menu again", 1.0)
		var total := 0.0
		print("PERF hitches (frames over %d ms): %d" % [int(FpsCounter.HITCH_MS), FpsCounter.hitches.size()])
		for h in FpsCounter.hitches:
			total += float(h[0])
			print("PERF   %6.0f ms (usual %4.0f)  %s" % [float(h[0]), float(h[2]), h[1]])
		print("PERF hitch total %.0f ms" % total)
	# steady cost, scene by scene
	var only_scene := ""
	for a in args:
		if a.begins_with("--scene="):
			only_scene = a.substr(8)
	var measure := func(n: int) -> Dictionary:
		var r := {"ms": 0.0, "draws": 0.0, "objs": 0.0, "prims": 0.0, "proc": 0.0, "phys": 0.0}
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for k in n:
			await get_tree().process_frame
			r["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			r["objs"] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			r["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			r["proc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			r["phys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		r["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		for k in r.keys():
			r[k] = float(r[k]) / n
		return r
	var frames := 20
	for a in args:
		if a.begins_with("--frames="):
			frames = int(a.substr(9))
	print("PERF scene            view     ms/frame  draws  objects  triangles  process ms  physics ms")
	var keep_scene: String = Game.get_s("scene")
	for e in Catalog.SCENES:
		if only_scene != "" and not (str(e["id"]) in only_scene.split(",")):
			continue
		Game.set_s("scene", e["id"])
		start_match({"mode": "practice"})
		hud.visible = not ("--no-hud" in args)
		await _wait(1.2)
		stage.set_view(Stage.View.OVERVIEW)
		await _wait(1.0)
		if "--census" in args:
			_census()
		# what-if switches, to see what each part of the picture costs (measuring only)
		for a in args:
			if a.begins_with("--x-floorsub="):
				var fpm3 := (stage.get("_floor") as MeshInstance3D).mesh as PlaneMesh
				fpm3.subdivide_width = int(a.substr(13))
				fpm3.subdivide_depth = int(a.substr(13))
			match a:
				"--x-nosun": (stage.get("_sun") as Light3D).shadow_enabled = false
				"--x-nospot": (stage.get("_key_light") as Light3D).shadow_enabled = false
				"--x-nolamp": (stage.get("_key_light") as Light3D).visible = false
				"--x-noglow": stage.env.glow_enabled = false
				"--x-nomsaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
				"--x-pssm2": (stage.get("_sun") as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				"--x-ortho": (stage.get("_sun") as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				"--x-floorcast":
					(stage.get("_floor") as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
					(stage.get("_floor_far") as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				"--x-farlit": (stage.get("_floor_far") as VisualInstance3D).layers = 1
				"--x-allshadows":
					TableView.debug_all_shadows = true
					stage.table_view.set("_built_key", "")
					stage.rebuild_table()
				"--x-onefloor":
					((stage.get("_floor") as MeshInstance3D).mesh as PlaneMesh).size = Vector2(18, 18)
					(stage.get("_floor_far") as Node3D).visible = false
				"--x-subdiv":
					var fpm := (stage.get("_floor") as MeshInstance3D).mesh as PlaneMesh
					fpm.size = Vector2(18, 18)
					fpm.subdivide_width = 60
					fpm.subdivide_depth = 60
					(stage.get("_floor_far") as Node3D).visible = false
				"--x-subnear":
					var fpm2 := (stage.get("_floor") as MeshInstance3D).mesh as PlaneMesh
					fpm2.subdivide_width = 40
					fpm2.subdivide_depth = 40
				"--x-nofar":
					(stage.get("_floor_far") as Node3D).visible = false
				"--x-noprio":
					(stage.get("_floor") as GeometryInstance3D).material_override.render_priority = 0
					var dm = (stage.get("_dome") as GeometryInstance3D).material_override
					if dm:
						dm.render_priority = 0
		var rows := []
		rows.append(["overview", await measure.call(frames)])
		stage.set_view(Stage.View.AIM)
		await _wait(1.2)
		rows.append(["aim", await measure.call(frames)])
		stage.set_view(Stage.View.OVERVIEW)
		await _wait(1.0)
		game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
		rows.append(["rolling", await measure.call(frames)])
		for rw in rows:
			var m: Dictionary = rw[1]
			print("PERF %-16s %-8s %8.1f %6.0f %8.0f %10.0f %10.2f %10.2f" % [e["id"], rw[0], m["ms"], m["draws"], m["objs"], m["prims"], m["proc"], m["phys"]])
		if "--shots" in args:
			# the same pictures before and after a change (compare them pixel by pixel): no HUD, no counter,
			# no breathing cue, the camera parked
			Game.settings["fps_counter"] = false     # (not saved: the counter comes back after the tour)
			Game.settings_changed.emit("fps_counter")
			Game.set_s("reduced_motion", true)
			hud.visible = false
			while game.state == PoolGame.State.ROLLING:
				game.fast_forward()
				await _wait(0.2)
			seed(4242)     # the same rack every time
			game.reset_rack()
			await _wait(0.5)
			var views := [["over", 42.0, 2.9, 0.6], ["low", 9.0, 2.9, 2.2], ["aim", -1.0, 0.0, 0.0]]
			for v in views:
				if float(v[1]) < 0.0:
					stage.reset_manual()
					stage.set_view(Stage.View.AIM)
				else:
					stage.set("_manual", true)
					stage.set("_want_pitch", deg_to_rad(float(v[1])))
					stage.set("_want_dist", float(v[2]))
					stage.set("_want_yaw", float(v[3]))
					stage.set("_want_target", Vector3.ZERO)
				stage.call("_snap_orbit")
				await _wait(0.6)
				stage.call("_snap_orbit")
				await _shot(dir, "perf_%s_%s" % [e["id"], v[0]])
			stage.reset_manual()
			Game.set_s("reduced_motion", false)
	Game.set_s("scene", keep_scene)
	_end_match()
	Game.set_s("ar_mode", "auto")
	Game.set_s("control_scheme", "slingshot")


## Everything 3D that is drawn: how many objects of each kind, and how many of them cast shadows.
func _census() -> void:
	var groups := {}
	for n in stage.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var key := "%s/%s" % [gi.get_parent().get_class() if gi.get_parent() else "", gi.get_class()]
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			key += " " + (gi as MeshInstance3D).mesh.get_class()
		var e: Array = groups.get(key, [0, 0, 0])
		e[0] += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			e[1] += 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			e[2] += (gi as MeshInstance3D).mesh.get_surface_count()
		groups[key] = e
	var total := [0, 0, 0]
	for k in groups.keys():
		print("CENSUS %-60s %4d shown  %4d cast shadows  %4d surfaces" % [k, groups[k][0], groups[k][1], groups[k][2]])
		for i in 3:
			total[i] += groups[k][i]
	print("CENSUS total %d shown, %d cast shadows, %d surfaces" % total)


func _shot(dir: String, name: String) -> void:
	if "--noshots" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("TOUR shot ", name, " ", img.get_size())


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run_tour(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Game.settings["unlock_all"] = false     # the tour looks at the game as a player has it (the default is on while testing)
	Game.settings["fps_counter"] = "--fps" in OS.get_cmdline_user_args()   # (pictures without it, unless asked)
	Game.settings_changed.emit("fps_counter")
	Game.set_s("ar_mode", "auto")
	Game.set_s("control_scheme", "slingshot")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var steps := ["menu", "vs_ai", "pass_play", "controls", "settings", "help", "practice", "top", "aim", "pro_dial", "orbit_ring", "trackpad", "crank", "ghost_target", "thumbstick", "phone_cue", "jump", "world_ar", "match_vs", "debug", "results", "ar", "input", "ar_blocked", "safe_area", "ios_check", "hand", "rail_cue", "sound", "adjust", "music", "rematch", "lang", "ballsets", "loading", "notices", "scenes", "breakpos", "wheelzone", "ar_scene", "cues", "tables", "icons", "rewards", "online", "pausemenu", "chest", "cueballs", "drawer", "pockets", "cushions", "feed", "freelook", "lang_feed", "lang_ads", "packages", "perf"]
	for s in steps:
		if only != "" and not (s in only.split(",")):
			continue
		if only == "" and s in ["perf", "ios_check"]:
			continue     # (measuring only: --only=perf; ios_check runs on an iPhone / the iOS simulator)
		await _tour_step(dir, s)
	print("TOUR done")
	get_tree().quit()


## Feed synthetic touches through the real input pipeline for each cue scheme and check a shot fires.
func _input_test() -> void:
	for scheme in Game.SCHEMES:
		Game.set_s("control_scheme", scheme)
		start_match({"mode": "practice"})
		await _wait(1.0)
		var ok := false
		var vp := get_viewport().get_visible_rect().size
		# fine-aim device must actually turn the cue
		var y0: float = game.control.yaw
		var fine_ok := true
		match scheme:
			"pro_dial":
				var w: Control = game.control.get("_wheel")
				var wc := w.get_global_rect().get_center()
				await _mouse(wc, true)
				for k in 8:
					await _mouse_move(wc + Vector2(k * 6.0, 0))
				await _mouse(wc + Vector2(42, 0), false)
			"trackpad":
				var pad: Control = game.control.get("_pad")
				var pc := pad.get_global_rect().get_center()
				await _mouse(pc, true)
				for k in 8:
					await _mouse_move(pc + Vector2(k * 4.0, 0))
				await _mouse(pc + Vector2(28, 0), false)
			"crank":
				var knob: Control = game.control.get("_knob")
				var kc := knob.get_global_rect().get_center()
				await _mouse(kc + Vector2(70, 0), true)
				for k in 12:
					await _mouse_move(kc + Vector2.from_angle(k * 0.4) * 70.0)
				await _mouse(kc + Vector2.from_angle(4.8) * 70.0, false)
			"thumbstick":
				var st: Control = game.control.get("_stick")
				var sc := st.get_global_rect().get_center()
				await _mouse(sc + Vector2(40, 0), true)
				await _wait(0.6)
				await _mouse(sc + Vector2(40, 0), false)
			"ghost_target":
				var mp: Control = game.control.get("_pad")
				var mc := mp.get_global_rect().get_center()
				await _mouse(mc, true)
				for k in 8:
					await _mouse_move(mc + Vector2(k * 8.0, 0))
				await _mouse(mc + Vector2(56, 0), false)
			"orbit_ring":
				var oc: Vector2 = (game.control as ControlOrbitRing).cue_screen()
				var start := oc + Vector2(ControlOrbitRing.RING_R, 0)
				await _touch(0, start, true)
				for k in 8:
					await _drag(0, oc + Vector2.from_angle(k * 0.05) * ControlOrbitRing.RING_R)
				await _touch(0, oc + Vector2.from_angle(0.35) * ControlOrbitRing.RING_R, false)
		if scheme not in ["slingshot", "phone_cue"]:
			var dy := absf(wrapf(float(game.control.yaw) - y0, -PI, PI))
			fine_ok = dy > 1e-5
			print("FINE %s %s (turned %.4f deg)" % ["PASS" if fine_ok else "FAIL", scheme, rad_to_deg(dy)])
		match scheme:
			"slingshot":
				await _touch(0, vp * 0.5, true)
				for k in 12:
					await _drag(0, vp * 0.5 + Vector2(-k * 22.0, k * 6.0))
				await _touch(0, vp * 0.5 + Vector2(-264, 72), false)
			"phone_cue":
				var btn0: Control = (game.control as ControlPhoneCue)._btn
				var bc0 := btn0.get_global_rect().get_center()
				await _mouse(bc0, true)
				await _wait(0.9)
				await _mouse(bc0, false)
			_:
				var piston: Control = game.control.get("_piston")
				var c := piston.get_global_rect().get_center() - Vector2(0, 150)
				await _mouse(c, true)
				for k in 10:
					await _mouse_move(c + Vector2(0, k * 25.0))
				await _mouse(c + Vector2(0, 250), false)
		await _wait(0.15)
		ok = game.state == PoolGame.State.ROLLING or game.shots_total > 0
		ok = ok and fine_ok
		print("INPUT %s %s (state %d, shots %d, power %.2f)" % ["PASS" if ok else "FAIL", scheme, game.state, game.shots_total, game.control.power])
	Game.set_s("control_scheme", "slingshot")


var _touch_at := {}   # finger index -> where it was last (so a simulated drag carries its movement)


func _touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = down
	_touch_at[i] = p
	Input.parse_input_event(e)
	await get_tree().process_frame


func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	e.relative = p - _touch_at.get(i, p)
	_touch_at[i] = p
	Input.parse_input_event(e)
	await get_tree().process_frame


var _last_mouse := Vector2.ZERO


func _mouse(p: Vector2, down: bool) -> void:
	_last_mouse = p
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p
	e.global_position = p
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)
	await get_tree().process_frame


func _mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = p - _last_mouse
	e.velocity = (p - _last_mouse) * 60.0
	_last_mouse = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	await get_tree().process_frame


func _tour_step(dir: String, s: String) -> void:
	match s:
		"menu", "vs_ai", "pass_play", "controls", "settings", "help":
			_end_match()
			_stack.clear()
			go(s)
			await _wait(0.8)
			await _shot(dir, s)
		"practice":
			start_match({"mode": "practice"})
			await _wait(2.2)
			await _shot(dir, "practice")
		"pro_dial", "orbit_ring", "trackpad", "crank", "ghost_target", "thumbstick", "phone_cue":
			Game.set_s("control_scheme", s)
			if game == null:
				start_match({"mode": "practice"})
				await _wait(2.0)
			stage.set_view(Stage.View.OVERVIEW)
			await _wait(1.0)
			await _shot(dir, "scheme_" + s)
			Game.set_s("control_scheme", "slingshot")
		"input":
			await _input_test()
		"world_ar":
			# simulated ARCore, life-size: aim at the floor, place the table standing on it, then walk all the
			# way around it. The table must not move in the world while the camera walks.
			stage.arcore.simulate = true
			stage.arcore.sim_floor = 0.0
			var centre := Vector3(0.0, 0.0, -2.4)
			var walk := {"a": 0.0}
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				var a: float = walk["a"]
				var eye := centre + Vector3(sin(a) * 2.9, 1.5, cos(a) * 2.9)
				return Transform3D(Basis.looking_at(centre + Vector3(0, 0.3, 0) - eye, Vector3.UP), eye)
			Game.set_s("ar_mode", "auto")
			Game.set_s("surface", "floor")
			start_match({"mode": "practice"})
			await _wait(1.5)
			await _shot(dir, "world_ar_preview")
			var pb: Button = hud.get("_ar_place")
			var pc := pb.get_global_rect().get_center()
			await _touch(0, pc, true)
			await _touch(0, pc, false)
			await _wait(0.3)
			var placed_xf: Transform3D = stage.table_root.global_transform
			var drift := 0.0
			var cam_moved := 0.0
			var cam0 := stage.ar_cam.global_position
			for step in [[0.0, "world_ar_front"], [PI * 0.5, "world_ar_side"], [PI * 0.85, "world_ar_back"], [PI * 1.5, "world_ar_other_side"]]:
				walk["a"] = step[0]
				for f in 4:
					await get_tree().process_frame
				drift = maxf(drift, stage.table_root.global_transform.origin.distance_to(placed_xf.origin))
				cam_moved = maxf(cam_moved, stage.ar_cam.global_position.distance_to(cam0))
				await _shot(dir, step[1])
			var on_floor := absf(stage.table_root.global_position.y - float(Game.get_s("table_height")) * stage.table_scale()) < 0.01
			var ok := stage.mode == Stage.Mode.WORLD_AR and stage.placed and drift < 0.001 and cam_moved > 4.0 and on_floor and not stage.floating()
			print("WORLD_AR %s (placed %s, walked %.1f m, table drift %.4f m, standing on floor %s, cloth at %.2f m)" % ["PASS" if ok else "FAIL", str(stage.placed), cam_moved, drift, str(on_floor), stage.table_root.global_position.y])
			stage.arcore.simulate = false
			Game.set_s("surface", "desk")
		"jump":
			# jump shot over a blocker: capture the cue ball in the air
			start_match({"mode": "practice"})
			await _wait(1.5)
			var c := game.cue_index()
			var sim: PoolSim = game.sim
			for i in sim.n:
				if i != c:
					sim.st[i] = PoolSim.ST_POCKETED
					game.views[i].visible = false
			sim.pos[c] = Vector2(-0.5, 0.0)
			var blk := sim.index_of_number(1)
			sim.st[blk] = PoolSim.ST_REST
			sim.pos[blk] = Vector2(-0.3, 0.0)
			game.views[blk].place(sim.pos[blk])
			game.views[c].place(sim.pos[c])
			stage.set_view(Stage.View.AIM)
			game.control.reset_for_turn(0.0)
			await _wait(1.0)
			game.fire(0.0, 0.62, Vector2.ZERO, 40.0)
			var peak := 0.0
			var shot_taken := false
			for k in 120:
				await get_tree().physics_frame
				peak = maxf(peak, game.sim.hz[c])
				if not shot_taken and game.sim.hz[c] > 0.05:
					shot_taken = true
					await _shot(dir, "jump")
			print("JUMP %s (peak %.1f cm)" % ["PASS" if peak > 0.02 else "FAIL", peak * 100.0])
		"ios_check":
			# Run on an iPhone or the iOS simulator (the cloud build does: ios_plugin/ci.sh sim): the real ARKit
			# plugin and the real notch. --only=ios_check
			var res := []
			var has := Engine.has_singleton("EmeraldAR")
			res.append(["EmeraldAR plugin loaded (the ARKit GDExtension)", has])
			var avail := "none"
			if has:
				var p: Object = Engine.get_singleton("EmeraldAR")
				avail = str(p.call("availability"))
				var st: PackedFloat32Array = p.call("getState")
				print("[ios] availability: %s | %s" % [avail, p.call("getInfo")])
				res.append(["getState() gives the 40 numbers of the Android plugin", st.size() == 40])
			res.append(["on iOS with the plugin, a match starts in walk-around AR", stage.auto_mode() == Stage.Mode.WORLD_AR])
			var win := DisplayServer.window_get_size()
			var safe := DisplayServer.get_display_safe_area()
			print("[ios] screen %s, safe area %s, controls inset L%.0f T%.0f R%.0f B%.0f" % [win, safe,
				ui_root.offset_left, ui_root.offset_top, -ui_root.offset_right, -ui_root.offset_bottom])
			res.append(["controls kept inside the safe area", safe.size == win or ui_root.offset_left > 0.0 or ui_root.offset_bottom < 0.0])
			await _shot(dir, "ios_menu")
			start_match({"mode": "practice"})
			await _wait(4.0)
			print("[ios] AR state %d, reason '%s': %s" % [stage.ar_state, stage.ar_block, stage.ar_block_text()])
			if avail == "unsupported":
				# the simulator (or a very old device): no world tracking -> the ARKit message and Play without AR
				res.append(["no world tracking here -> AR blocked with the Apple ARKit message", stage.ar_state == Stage.ArState.BLOCKED and stage.ar_block_text().contains("Apple ARKit")])
			else:
				res.append(["AR starting, waiting for the camera answer, or running", stage.ar_state in [Stage.ArState.STARTING, Stage.ArState.RUNNING]])
			await _shot(dir, "ios_practice")
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("IOS_CHECK %s" % ("PASS" if all_ok else "FAIL"))
		"safe_area":
			# iPhone (v1.1.12): the controls stay clear of the Dynamic Island and the home bar.
			# iPhone 15 Pro in landscape: 2556 x 1179 px, 177 px kept free left and right, 63 px at the bottom.
			var res := []
			var win := Vector2i(2556, 1179)
			var safe := Rect2i(177, 0, 2556 - 354, 1179 - 63)
			apply_safe_area(safe, win)
			await _wait(0.4)
			var canvas := get_viewport().get_visible_rect().size
			var k := canvas / Vector2(win)
			var free := Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k)
			var outside := []
			for b in ui_root.find_children("*", "Button", true, false):
				var btn := b as Button
				if btn.is_visible_in_tree() and not free.encloses(btn.get_global_rect().grow(-1.0)):
					outside.append(btn.text.substr(0, 24))
			res.append(["menu: every button inside the free area (%d px each side, %d px below)" % [int(177 * k.x), int(63 * k.y)], outside.is_empty(), str(outside)])
			await _shot(dir, "safe_area_menu")
			start_match({"mode": "practice"})
			await _wait(1.5)
			outside.clear()
			for b in ui_root.find_children("*", "Button", true, false):
				var btn := b as Button
				if btn.is_visible_in_tree() and not free.encloses(btn.get_global_rect().grow(-1.0)):
					outside.append(btn.text.substr(0, 24))
			res.append(["match: every HUD button inside the free area", outside.is_empty(), str(outside)])
			await _shot(dir, "safe_area_match")
			apply_safe_area(Rect2i(Vector2i.ZERO, win), win)
			res.append(["no notch -> no margins", is_zero_approx(ui_root.offset_left) and is_zero_approx(ui_root.offset_bottom)])
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s %s" % ["ok  " if r[1] else "FAIL", r[0], "" if r[1] or r.size() < 3 else r[2]])
			print("SAFE_AREA %s" % ("PASS" if all_ok else "FAIL"))
		"ar_blocked":
			# AR is ARCore or nothing. When it can't start the game must say why, offer the fix, retry when the
			# player comes back, and never fall back to a gyro-only "AR".
			var res := []
			stage.arcore.simulate = true
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				return Transform3D(Basis.looking_at(Vector3(0, -0.6, -1.0), Vector3.UP), Vector3(0, 1.4, 0))
			# 1. Google Play Services for AR missing -> install button; back from the store -> AR starts
			stage.arcore.sim_availability = "not_installed"
			start_match({"mode": "practice"})
			await _wait(1.0)
			var inst: Button = hud.get("_ar_install")
			var plc: Button = hud.get("_ar_place")
			res.append(["needs install -> blocked + store button", stage.ar_state == Stage.ArState.BLOCKED and stage.ar_block == "not_installed" and inst.visible and not plc.visible])
			await _shot(dir, "ar_blocked_install")
			stage.arcore.sim_availability = "installed"
			stage.notification(NOTIFICATION_APPLICATION_RESUMED)
			await _wait(0.8)
			res.append(["back from the store -> AR running", stage.ar_state == Stage.ArState.RUNNING and plc.visible])
			# 2. session fails to start -> 3 attempts, then the reason on screen + Try again
			stage.arcore.sim_fail = "FatalException: simulated"
			start_match({"mode": "practice"})
			await _wait(1.0)
			res.append(["start failing -> still retrying, not blocked yet", stage.ar_state == Stage.ArState.STARTING])
			await _wait(2.5)
			var retry: Button = hud.get("_ar_retry")
			var det: Label = hud.get("_ar_detail")
			res.append(["3 failed starts -> blocked with the error shown", stage.ar_state == Stage.ArState.BLOCKED and stage.ar_block == "failed" and retry.visible and det.visible and det.text.contains("FatalException")])
			await _shot(dir, "ar_blocked_failed")
			stage.arcore.sim_fail = ""
			var rc := retry.get_global_rect().get_center()
			await _touch(0, rc, true)
			await _touch(0, rc, false)
			await _wait(0.8)
			res.append(["Try again -> AR running", stage.ar_state == Stage.ArState.RUNNING])
			# 3. camera busy -> says so at once (no pointless retries)
			stage.arcore.sim_fail = "CameraNotAvailableException"
			start_match({"mode": "practice"})
			await _wait(0.8)
			res.append(["camera busy -> blocked 'camera'", stage.ar_state == Stage.ArState.BLOCKED and stage.ar_block == "camera"])
			# 4. unsupported phone -> Play without AR starts the match in the Studio view
			stage.arcore.sim_fail = ""
			stage.arcore.sim_availability = "unsupported"
			start_match({"mode": "practice"})
			await _wait(0.8)
			var stu: Button = hud.get("_ar_studio")
			res.append(["unsupported -> blocked, no AR pretending", stage.ar_state == Stage.ArState.BLOCKED and stage.is_ar() and not stage.table_root.visible])
			var sc := stu.get_global_rect().get_center()
			await _touch(0, sc, true)
			await _touch(0, sc, false)
			await _wait(1.0)
			res.append(["Play without AR -> Studio, match on", stage.mode == Stage.Mode.STUDIO and game.state == PoolGame.State.AIM])
			# 5. iPhone (ARKit, v1.1.12): the reasons name Apple ARKit and never the Play Store; while iOS asks
			#    "allow the camera?" AR waits for the answer instead of timing out; "Don't Allow" -> app settings
			stage.arcore.ios = true
			start_match({"mode": "practice"})
			await _wait(0.8)
			res.append(["iPhone without ARKit -> 'doesn't support Apple ARKit', no store button",
				stage.ar_block == "unsupported" and stage.ar_block_text().contains("Apple ARKit") and not (hud.get("_ar_install") as Button).visible])
			await _shot(dir, "ar_blocked_ios_unsupported")
			stage.arcore.sim_availability = "installed"
			stage.arcore.sim_asking = true
			start_match({"mode": "practice"})
			await _wait(0.8)
			stage.set("_ar_timer", 40.0)
			await _wait(0.5)
			res.append(["iPhone asking for the camera -> AR waits past the 25 s start limit", stage.ar_state == Stage.ArState.STARTING and stage.arcore.asking_permission])
			stage.arcore.sim_asking = false
			stage.arcore.sim_fail = "SecurityException: camera permission denied (allow the camera for Emerald Break in Settings)"
			await _wait(0.8)
			var sett: Button = hud.get("_ar_settings")
			res.append(["iPhone, camera refused -> blocked 'permission' + app settings button", stage.ar_state == Stage.ArState.BLOCKED and stage.ar_block == "permission" and sett.visible and not (hud.get("_ar_install") as Button).visible])
			await _shot(dir, "ar_blocked_ios_permission")
			stage.arcore.sim_fail = ""
			stage.retry_ar()
			await _wait(0.8)
			res.append(["...camera allowed in Settings, back in the game -> AR running", stage.ar_state == Stage.ArState.RUNNING])
			var keep_loc := TranslationServer.get_locale()
			TranslationServer.set_locale("de")
			var help_de := ARCoreBridge.ios_help("Choose Mini (on a desk) or Life-size (on the floor). Point the phone at the surface and sweep it slowly side to side until \"Floor found\" appears and the table stands there, then tap Place. The table stays fixed in your room: walk all the way around it, lean in, crouch. The move button lets you drag, pinch and twist the table; the recenter button places it again.\nAR uses Google ARCore (Google Play Services for AR). If AR can't start, the game tells you why and what to do; you can always play in the Studio view instead.")
			TranslationServer.set_locale(keep_loc)
			res.append(["iPhone help text (German): names Apple ARKit, not ARCore, rest translated",
				help_de.contains("AR nutzt Apple ARKit") and not help_de.contains("ARCore") and help_de.begins_with("Wähle") and help_de.count("\n") == 1])
			stage.arcore.ios = false
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("AR_BLOCKED %s" % ("PASS" if all_ok else "FAIL"))
			stage.arcore.sim_availability = "installed"
			stage.arcore.simulate = false
		"ar":
			# simulated ARCore, mini table on a desk 0.75 m high seen from a chair: find it, place it, play
			stage.arcore.simulate = true
			stage.arcore.sim_floor = 0.75
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				var eye := Vector3(0, 1.2, 0.55)
				return Transform3D(Basis.looking_at(Vector3(0, 0.78, -0.25) - eye, Vector3.UP), eye)
			Game.set_s("surface", "desk")
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--scheme="):
					Game.set_s("control_scheme", a.substr(9))
			start_match({"mode": "practice"})
			await _wait(1.2)
			await _shot(dir, "ar_place")
			# press the real Place button (touch, like a phone)
			var pb: Button = hud.get("_ar_place")
			var pc := pb.get_global_rect().get_center()
			await _touch(0, pc, true)
			await _wait(0.05)
			var hov := get_viewport().gui_get_hovered_control()
			await _touch(0, pc, false)
			await _wait(0.3)
			print("PLACE %s (button disabled=%s, under finger: %s)" % ["PASS" if stage.placed else "FAIL", pb.disabled, str(hov.get_path()) if hov else "none"])
			if not stage.placed:
				# what is in the way? every visible control whose box holds the touch point
				print("  touch at ", pc, " button box ", pb.get_global_rect(), " visible ", pb.is_visible_in_tree(), " state ", game.state, " ar_state ", stage.ar_state)
				for c in get_tree().root.find_children("*", "Control", true, false):
					var cc := c as Control
					if cc.is_visible_in_tree() and cc.get_global_rect().has_point(pc) and cc.mouse_filter != Control.MOUSE_FILTER_IGNORE:
						print("    ", cc.get_path(), " filter ", cc.mouse_filter, " ", cc.get_class())
			if not stage.placed:
				stage.place_table()
			await _wait(1.0)
			await _shot(dir, "ar_play")
			stage.arcore.simulate = false
		"hand":
			# ball in hand: move the cue ball as often as you like; only the Place button makes it final
			var res := []
			start_match({"mode": "practice"})
			await _wait(0.6)
			stage.set_view(Stage.View.TOP)
			await _wait(1.6)
			var R: float = game.sim.R
			var place_btn: Button = hud.get("_hand_place")
			game.start_ball_in_hand()
			await _wait(0.2)
			res.append(["hand button -> placing, Place button shown", game.state == PoolGame.State.BALL_IN_HAND and place_btn.visible])
			var pa := Vector2(-0.6, 0.2)
			var pb2 := Vector2(-0.2, -0.3)
			var pc2 := Vector2(-0.85, -0.1)
			var sa := stage.table_to_screen(pa, R)
			var sb := stage.table_to_screen(pb2, R)
			await _touch(0, sa, true)
			await _touch(0, sa, false)
			await _wait(0.1)
			res.append(["tap -> ball there, lifting the finger does NOT finish", game.cue_ball_pos().distance_to(pa) < 0.02 and game.state == PoolGame.State.BALL_IN_HAND])
			await _touch(0, sa, true)
			for k in 6:
				await _drag(0, sa.lerp(sb, (k + 1) / 6.0))
			await _touch(0, sb, false)
			await _wait(0.1)
			res.append(["drag -> ball follows, still placing", game.cue_ball_pos().distance_to(pb2) < 0.02 and game.state == PoolGame.State.BALL_IN_HAND])
			# finger on top of an object ball: the cue ball goes beside it, never inside it
			var ob := -1
			for i in game.sim.n:
				if game.sim.kind[i] != PoolSim.K_CUE and game.sim.st[i] != PoolSim.ST_POCKETED:
					ob = i
					break
			var so := stage.table_to_screen(game.sim.pos[ob], R)
			await _touch(0, so, true)
			await _touch(0, so, false)
			await _wait(0.1)
			var min_d := INF
			for i in game.sim.n:
				if game.sim.kind[i] != PoolSim.K_CUE and game.sim.st[i] != PoolSim.ST_POCKETED:
					min_d = minf(min_d, game.sim.pos[i].distance_to(game.cue_ball_pos()))
			res.append(["tap on another ball -> placed touching it, not overlapping (gap %.1f mm)" % ((min_d - 2.0 * R) * 1000.0), min_d >= 2.0 * R - 1e-4 and min_d < 2.0 * R + 0.03])
			# finger off the cloth (on the rail): stays on the table
			var s_out := stage.table_to_screen(Vector2(-game.sim.table.a - 0.08, 0.0), R)
			await _touch(0, s_out, true)
			await _touch(0, s_out, false)
			await _wait(0.1)
			res.append(["tap on the rail -> ball against the cushion, on the cloth", game.sim.table.in_bounds(game.cue_ball_pos()) and game.cue_ball_pos().x < -game.sim.table.a + R + 0.002])
			var sc2 := stage.table_to_screen(pc2, R)
			await _touch(0, sc2, true)
			await _touch(0, sc2, false)
			await _wait(0.3)
			await _shot(dir, "hand")
			var bc := place_btn.get_global_rect().get_center()
			await _touch(0, bc, true)
			await _touch(0, bc, false)
			await _wait(0.3)
			res.append(["Place -> aiming from the last spot, button gone", game.state == PoolGame.State.AIM and game.cue_ball_pos().distance_to(pc2) < 0.02 and not place_btn.visible and game.cue_view.visible])
			# versus: a foul gives ball in hand; same rules; after Place the hand button allows another go
			start_match({"mode": "versus", "vs_ai": false})
			await _wait(0.6)
			stage.set_view(Stage.View.TOP)
			await _wait(1.6)
			game.rules.ball_in_hand = true
			game.call("_start_turn")
			await _wait(0.2)
			place_btn = hud.get("_hand_place")
			res.append(["match: foul -> ball in hand with Place button", game.state == PoolGame.State.BALL_IN_HAND and place_btn.visible])
			sa = stage.table_to_screen(pa, R)
			await _touch(0, sa, true)
			await _touch(0, sa, false)
			sb = stage.table_to_screen(pb2, R)
			await _touch(0, sb, true)
			await _touch(0, sb, false)
			await _wait(0.1)
			res.append(["match: two placements in a row, still placing", game.cue_ball_pos().distance_to(pb2) < 0.02 and game.state == PoolGame.State.BALL_IN_HAND])
			game.confirm_cue_placement()
			await _wait(0.2)
			var hand_btn: Button = hud.get("_btn_hand")
			res.append(["match: placed -> aiming; hand button still offered before the shot", game.state == PoolGame.State.AIM and hand_btn.visible])
			game.start_ball_in_hand()
			await _wait(0.1)
			res.append(["match: hand button -> placing again", game.state == PoolGame.State.BALL_IN_HAND])
			game.confirm_cue_placement()
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("HAND %s" % ("PASS" if all_ok else "FAIL"))
		"rail_cue":
			# the stick can't pass through the rail: near a cushion it starts resting on it
			var res := []
			start_match({"mode": "practice"})
			await _wait(0.6)
			var sim: PoolSim = game.sim
			var c := game.cue_index()
			var elev_w: Widgets.ElevationSlider = hud.get("_elev")
			# 4 cm off the long rail, shooting straight away from it
			sim.pos[c] = Vector2(0.25, sim.table.b - sim.R - 0.04)
			game.views[c].place(sim.pos[c])
			game.control.reset_for_turn(-PI / 2.0)
			game.control.elevation = 0.0
			await _wait(0.4)
			var e_min := sim.min_cue_elevation(sim.pos[c], -PI / 2.0)
			res.append(["near the rail the cue starts on the rail (%.1f deg), slider floor matches" % game.cue_elevation(), e_min > 10.0 and absf(game.cue_elevation() - e_min) < 0.01 and absf(elev_w.floor_deg - e_min) < 0.1 and absf(elev_w.effective() - e_min) < 0.1])
			# camera low and side-on to look along the rail
			stage.set("_manual", true)
			stage.set("_want_target", stage.table_root.global_transform * Vector3(0.25, 0.03, sim.table.b - 0.05))
			stage.set("_want_yaw", PI / 2.0)
			stage.set("_want_pitch", deg_to_rad(4.0))
			stage.set("_want_dist", 0.75)
			await _wait(1.6)
			await _shot(dir, "rail_cue_side")
			# turn the aim along the rail: the stick is over the open table, so it comes down
			game.control.yaw = 0.0
			await _wait(0.3)
			var e_along := game.cue_elevation()
			res.append(["aim along the rail -> cue comes down by itself (%.1f deg)" % e_along, e_along < 4.0 and absf(elev_w.floor_deg - e_along) < 0.1])
			# hit high on the ball: lower minimum
			game.control.yaw = -PI / 2.0
			game.control.offset = Vector2(0, 0.45)
			await _wait(0.3)
			res.append(["top spin -> lower minimum (%.1f deg)" % game.cue_elevation(), game.cue_elevation() < e_min - 3.0])
			game.control.offset = Vector2.ZERO
			# asking for more than the minimum works, asking for less doesn't
			game.control.elevation = 45.0
			await _wait(0.2)
			res.append(["45 deg requested -> 45 deg", absf(game.cue_elevation() - 45.0) < 0.01])
			game.control.elevation = 5.0
			await _wait(0.2)
			res.append(["5 deg requested -> held at the rail", absf(game.cue_elevation() - e_min) < 0.01])
			# the shot itself is played at that angle
			game.control.elevation = 0.0
			sim.events.clear()
			game.fire(-PI / 2.0, 0.5, Vector2.ZERO, 0.0)
			await _wait(0.15)
			var flat := PoolSim.new(sim.table)
			var fc := flat.add_ball(Vector2.ZERO, 0, PoolSim.K_CUE)
			flat.strike(fc, 0.0, 0.5, Vector2.ZERO, 0.0)
			res.append(["shot played at the rail angle, not level", sim.cue_clearance and game.undo_sim != null])
			stage.set("_manual", false)
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("RAIL_CUE %s" % ("PASS" if all_ok else "FAIL"))
		"sound":
			# table sounds: intensity tiers follow impact speed, variations rotate, sound sits at the impact
			var res := []
			start_match({"mode": "practice"})
			await _wait(0.6)
			var tiers := Sfx.tier_count("ball")
			res.append(["bank loaded: ball %d tiers x %d, cushion %d, cue %d" % [tiers, Sfx.variation_count("ball", 0), Sfx.tier_count("cushion"), Sfx.tier_count("cue")], tiers >= 1 and Sfx.tier_count("cushion") >= 1 and Sfx.tier_count("cue") >= 1])
			# loudness rises with speed, silent below the threshold
			var mono := true
			var prev := -INF
			for v in [0.04, 0.1, 0.3, 0.8, 1.5, 3.0, 5.5]:
				var d := Sfx.level_db("ball", v)
				mono = mono and d > prev
				prev = d
			res.append(["ball loudness: silent < 3 cm/s, %.0f dB at 5 cm/s ... 0 dB at 5.5 m/s, always rising" % Sfx.level_db("ball", 0.05), mono and Sfx.level_db("ball", 0.02) == -INF and absf(Sfx.level_db("ball", 5.5)) < 0.01 and Sfx.level_db("ball", 0.05) < -20.0])
			# tier choice: gentle -> softest, hard -> hardest, in between a mix that leans with speed
			if tiers >= 3:
				var cnt := func(v: float) -> Array:
					var c := []
					c.resize(tiers)
					c.fill(0)
					for k in 400:
						c[Sfx.pick_tier("ball", v)] += 1
					return c
				var c_soft: Array = cnt.call(0.1)
				var c_hard: Array = cnt.call(5.0)
				var c_lo: Array = cnt.call(0.4)
				var c_hi: Array = cnt.call(0.9)
				res.append(["tiers: 0.1 m/s all soft %s, 5 m/s all hard %s, 0.4 -> %s, 0.9 -> %s" % [c_soft, c_hard, c_lo, c_hi],
					c_soft[0] == 400 and c_hard[tiers - 1] == 400 and c_lo[0] > c_lo[1] and c_hi[1] > c_hi[0] and c_lo[1] > 20])
			# a real break through the game: many clacks, loud ones from hard tiers, placed on the table
			Sfx.log_hits = true
			Sfx.hits.clear()
			game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
			var roll_peak := 0.0
			for k in 240:
				await get_tree().physics_frame
				roll_peak = maxf(roll_peak, float(Sfx.get("_roll_target")))
			var balls := Sfx.hits.filter(func(h): return h["kind"] == "ball")
			var cush := Sfx.hits.filter(func(h): return h["kind"] == "cushion")
			var cues := Sfx.hits.filter(func(h): return h["kind"] == "cue")
			var dbs := balls.map(func(h): return float(h["db"]))
			var tiers_used := {}
			var repeats := 0
			var last_s := {}
			var on_table := true
			var tbl: Vector3 = stage.table_root.global_position
			for h in balls:
				tiers_used[h["tier"]] = true
				if last_s.get(h["tier"], -1) == h["sample"] and Sfx.variation_count("ball", h["tier"]) > 1:
					repeats += 1
				last_s[h["tier"]] = h["sample"]
				var pp: Vector3 = h["pos"]
				on_table = on_table and absf(pp.x - tbl.x) < 1.3 and absf(pp.z - tbl.z) < 0.75 and absf(pp.y - tbl.y) < 0.2
			res.append(["break: the 23 contacts of the rack play as its %d loudest clacks (%.0f to %.0f dB), %d cushion hits, %d cue hit" % [balls.size(), dbs.min() if dbs.size() > 0 else 0.0, dbs.max() if dbs.size() > 0 else 0.0, cush.size(), cues.size()],
				balls.size() >= 5 and balls.size() <= 12 and cush.size() >= 2 and cues.size() == 1 and dbs.max() > -3.0 and dbs.min() < -6.0])
			res.append(["break uses %d intensity tiers, no sample twice in a row (%d repeats), all placed on the table" % [tiers_used.size(), repeats], tiers_used.size() >= mini(tiers, 2) and repeats == 0 and on_table])
			res.append(["cue hit at full power from the hardest tier, at the cue ball", cues.size() == 1 and cues[0]["tier"] == Sfx.tier_count("cue") - 1 and float(cues[0]["db"]) > -1.0])
			res.append(["rolling bed rose with the break (peak %.2f)" % roll_peak, roll_peak > 0.5])
			game.fast_forward()
			for k in 600:
				await get_tree().physics_frame
				if game.state != PoolGame.State.ROLLING:
					break
			await _wait(0.2)
			res.append(["balls stopped -> rolling bed off", float(Sfx.get("_roll_target")) == 0.0 and game.state == PoolGame.State.AIM])
			# a soft tap: quiet, from the softest tier
			Sfx.hits.clear()
			var c := game.cue_index()
			var o := -1
			for i in game.sim.n:
				if game.sim.kind[i] != PoolSim.K_CUE and game.sim.st[i] != PoolSim.ST_POCKETED:
					o = i
					break
			game.sim.pos[c] = game.sim.pos[o] + Vector2(-0.12, 0.0)
			# make room: park every other ball out of the way of this little test
			var yaw_to := 0.0
			game.fire(yaw_to, 0.04, Vector2.ZERO, 0.0)
			for k in 200:
				await get_tree().physics_frame
				if game.state != PoolGame.State.ROLLING:
					break
			var soft := Sfx.hits.filter(func(h): return h["kind"] == "ball")
			res.append(["gentle tap: %s" % (("%.0f dB, tier %d at %.2f m/s" % [soft[0]["db"], soft[0]["tier"], soft[0]["speed"]]) if soft.size() > 0 else "no contact"),
				soft.size() > 0 and float(soft[0]["db"]) < -12.0 and int(soft[0]["tier"]) <= 1])
			# pocket: drop + return-rail tail
			Sfx.hits.clear()
			game.call("_pocket_sound", game.sim.table.pockets[0]["hole"], 2.5)
			await _wait(0.4)
			var kinds := Sfx.hits.map(func(h): return h["kind"])
			res.append(["fast pot: %s" % str(kinds), "pocket" in kinds and "cushion" in kinds and (Sfx.tier_count("pocket_roll") == 0 or "pocket_roll" in kinds)])
			Sfx.log_hits = false
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("SOUND %s" % ("PASS" if all_ok else "FAIL"))
		"adjust":
			# AR: pause menu -> move / raise / lower the placed table (simulated ARCore)
			var res := []
			stage.arcore.simulate = true
			stage.arcore.sim_floor = 0.0
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				var eye := Vector3(0, 1.5, 0.6)
				return Transform3D(Basis.looking_at(Vector3(0, 0.3, -2.4) - eye, Vector3.UP), eye)
			Game.set_s("surface", "floor")
			start_match({"mode": "practice"})
			await _wait(1.2)
			res.append(["before the table is placed the pause menu has no move item", not can_move_table()])
			stage.place_table()
			await _wait(0.8)
			var y0: float = stage.table_root.global_position.y
			var p0: Vector3 = stage.table_root.global_position
			pause()
			await _wait(0.3)
			var labels := []
			for b in _pause.find_children("*", "Button", true, false):
				labels.append((b as Button).text.strip_edges())
			res.append(["pause menu offers it: %s" % str(labels.filter(func(t): return t.contains("table") or t.contains("Music"))), "Move / raise / lower table" in labels and "Music during the game: Off" in labels])
			await _shot(dir, "adjust_pause")
			move_table()
			await _wait(0.3)
			var panel: Control = hud.get("_adjust_panel")
			res.append(["-> game resumes with the move panel open", not get_tree().paused and panel.visible and stage.adjusting])
			for k in 5:
				hud.call("_start_lift", 1)
			hud.set("_lift_dir", 0)
			await _wait(0.2)
			res.append(["Raise x5 -> table 5 cm higher (%.1f cm)" % ((stage.table_root.global_position.y - y0) * 100.0), absf(stage.table_root.global_position.y - y0 - 0.05) < 0.001])
			hud.call("_start_lift", -1)   # press and hold Lower
			await _wait(1.35)
			hud.set("_lift_dir", 0)
			var held: float = stage.table_root.global_position.y - y0
			res.append(["hold Lower 1.35 s -> keeps going (now %.1f cm)" % (held * 100.0), held < -0.02 and held > -0.25])
			# drag the table a little with one finger
			var sp := get_viewport().get_visible_rect().size * Vector2(0.5, 0.45)
			await _touch(0, sp, true)
			for k in 5:
				await _drag(0, sp + Vector2(30.0 * (k + 1), 0))
			await _touch(0, sp + Vector2(150, 0), false)
			await _wait(0.2)
			var moved: float = Vector2(stage.table_root.global_position.x - p0.x, stage.table_root.global_position.z - p0.z).length()
			res.append(["one-finger drag moves it (%.0f cm) at the same height" % (moved * 100.0), moved > 0.05 and absf(stage.table_root.global_position.y - y0 - held) < 0.002])
			await _shot(dir, "adjust_panel")
			var before_done: Vector3 = stage.table_root.global_position
			hud.close_table_adjust()
			await _wait(0.8)
			res.append(["Done -> table stays exactly there, anchored", not stage.adjusting and not panel.visible and stage.table_root.global_position.distance_to(before_done) < 0.001 and stage.arcore.anchor_tracking == 2])
			hud.open_table_adjust()
			await _wait(0.2)
			for b in panel.find_children("*", "Button", true, false):
				if (b as Button).text.strip_edges() == "Place again":
					(b as Button).pressed.emit()
			await _wait(0.4)
			res.append(["Place again -> back to finding the floor, lift reset on the next placement", not stage.placed and not panel.visible and (hud.get("_ar_panel") as Control).visible])
			stage.place_table()
			await _wait(0.3)
			res.append(["placed again on the floor (lift %.0f cm)" % (stage.ar_lift * 100.0), stage.ar_lift == 0.0 and absf(stage.table_root.global_position.y - y0) < 0.002])
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("ADJUST %s" % ("PASS" if all_ok else "FAIL"))
			stage.arcore.simulate = false
			Game.set_s("surface", "desk")
		"music":
			# menu playlist: one song at a time, 1 s gap, random, never the last one, all songs cycle
			var res := []
			var real := Sfx.songs.duplicate()
			res.append(["songs found: %s" % str(real.map(func(p): return p.get_file())), real.size() >= 1 and real.all(func(p): return not p.to_lower().contains("trim"))])
			res.append(["menu: music playing (%s)" % Sfx.current_song.get_file(), Sfx.music_should_play() and (Sfx.get("_music") as AudioStreamPlayer).playing])
			# exactly the eight songs Randy wants (v1.1.11: the four "Soccer" songs from v1.1.10 are out again)
			var names: Array = real.map(func(p): return p.get_file())
			var want_songs := []
			for n in range(2, 10):
				want_songs.append("brass_breakbeats_%d.mp3" % n)
			res.append(["8 songs, brass_breakbeats_2-9, nothing else (no Soccer songs)", real.size() == 8 and want_songs.all(func(n): return n in names)])
			var lens := []
			var loads_ok := true
			for p in real:
				var st = load(p)
				var sec: float = st.get_length() if st is AudioStream else 0.0
				lens.append("%s %d s" % [p.get_file().get_basename(), int(sec)])
				loads_ok = loads_ok and st is AudioStream and sec > 50.0 and sec < 240.0
			res.append(["every song loads and runs 1-3 minutes (%s)" % ", ".join(lens), loads_ok])
			# the song the game starts with is random: 600 launches with the real songs
			var keep_last := str(Game.get_s("last_song"))
			var openers := {}
			var prev := ""
			var never_prev := true
			for k in 600:
				Game.set_s("last_song", prev)
				Sfx.set("_bag", [] as Array[String])
				var op := Sfx.next_song()
				never_prev = never_prev and op != prev
				openers[op] = int(openers.get(op, 0)) + 1
				prev = op
			var lo := 9999
			var hi := 0
			for v in openers.values():
				lo = mini(lo, v)
				hi = maxi(hi, v)
			res.append(["600 launches: every one of the %d songs starts the game sometimes (%d-%d times each), never the one heard last" % [real.size(), lo, hi],
				openers.size() == real.size() and lo >= 300 / real.size() and hi <= 900 / real.size() and never_prev])   # within half and one and a half times a fair share
			Game.set_s("last_song", keep_last)
			# the order logic, with three stand-in names
			Sfx.songs.assign(["res://a.ogg", "res://b.ogg", "res://c.ogg"])
			Sfx.set("_bag", [] as Array[String])
			var seq := []
			var rep_n := 0
			var bad_rounds := 0
			for k in 300:
				var nx := Sfx.next_song()
				if seq.size() > 0 and seq.back() == nx:
					rep_n += 1
				seq.append(nx)
				Game.set_s("last_song", nx)
			for k in range(0, 300, 3):
				var round_set := {}
				for j in 3:
					round_set[seq[k + j]] = true
				if round_set.size() != 3:
					bad_rounds += 1
			var firsts := {}
			for k in range(0, 300, 3):
				firsts[seq[k]] = true
			res.append(["300 picks: %d back-to-back repeats, %d rounds missing a song, order varies (%d different openers)" % [rep_n, bad_rounds, firsts.size()], rep_n == 0 and bad_rounds == 0 and firsts.size() == 3])
			# coming back (new menu visit or new launch): never the song that played last
			var ok_restart := true
			for k in 60:
				var last: String = ["res://a.ogg", "res://b.ogg", "res://c.ogg"][k % 3]
				Game.set_s("last_song", last)
				Sfx.set("_bag", [] as Array[String])
				ok_restart = ok_restart and Sfx.next_song() != last
			res.append(["fresh start 60 times: first song is never the last one played", ok_restart])
			Sfx.songs.assign(real)
			Sfx.set("_bag", [] as Array[String])
			# 1 second gap between songs
			var pl: AudioStreamPlayer = Sfx.get("_music")
			var first_song := Sfx.current_song
			Game.set_s("last_song", first_song)   # (the stand-in names above overwrote it)
			pl.stop()
			pl.finished.emit()
			await _wait(0.5)
			var silent_mid := not pl.playing
			await _wait(0.9)
			res.append(["song ends -> 1 s of silence -> next song%s" % ("" if real.size() < 2 else " (a different one)"), silent_mid and pl.playing and (real.size() < 2 or Sfx.current_song != first_song)])
			# no music during a match unless the player turns it on
			Game.set_s("music_in_game", false)
			start_match({"mode": "practice"})
			await _wait(1.0)
			res.append(["match starts -> music fades out and stops", not pl.playing and not Sfx.music_should_play()])
			Game.set_s("music_in_game", true)
			await _wait(0.3)
			res.append(["'Music during the game' on -> plays", pl.playing])
			Game.set_s("music_in_game", false)
			await _wait(0.8)
			res.append(["...off again -> stops", not pl.playing])
			var before_menu := str(Game.get_s("last_song"))
			quit_to("menu")
			await _wait(0.5)
			res.append(["back to the menu -> music again%s" % ("" if real.size() < 2 else ", not the song from before"), pl.playing and (real.size() < 2 or Sfx.current_song != before_menu)])
			var all_ok := true
			for r in res:
				all_ok = all_ok and r[1]
				print("  %s  %s" % ["ok  " if r[1] else "FAIL", r[0]])
			print("MUSIC %s" % ("PASS" if all_ok else "FAIL"))
		"rematch":
			# regression: leftover balls / cues from the previous match must not stay on the table
			var counts := func() -> Array:
				var c := [0, 0, 0, 0]
				for n in stage.table_root.get_children():
					if n.is_queued_for_deletion():
						continue
					if n is BallView: c[0] += 1
					elif n is CueView: c[1] += 1
					elif n is AimGuide: c[2] += 1
					elif n is MeshInstance3D and n != stage.table_view: c[3] += 1
				return c
			var ok := true
			var base: Array = counts.call()   # menu table: no balls, no cue
			for sc in ["ghost_target", "pro_dial"]:
				Game.set_s("control_scheme", sc)
				start_match({"mode": "practice"})
				await _wait(0.4)
				game.control.power = 0.8
				game.control.shot_requested.emit()
				await _wait(1.0)
				var c1: Array = counts.call()
				start_match({"mode": "versus", "vs_ai": true, "ai_level": 0})
				await _wait(0.4)
				var c2: Array = counts.call()
				restart()
				await _wait(0.4)
				var c3: Array = counts.call()
				quit_to("menu")
				await _wait(0.4)
				var c4: Array = counts.call()
				print("rematch %s: practice %s, new match %s, restart %s, menu %s" % [sc, c1, c2, c3, c4])
				var expect := [16, 1, 1]
				ok = ok and c2.slice(0, 3) == expect and c3.slice(0, 3) == expect and c4 == base
			print("REMATCH %s" % ("PASS" if ok else "FAIL"))
		"lang":
			# every screen in every language: screenshots + a check for text left in English or cut off
			var langs := Loc.codes()
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--langs="):
					langs = Array(arg.substr(8).split(","))
			var problems := 0
			Game.set_s("ar_mode", "studio")
			for code in langs:
				Loc.set_language(code)
				var keep_q: Array = Game.packages().duplicate()
				Game.progress["packages"] = [3, 45]        # so the package page and the menu's package button show
				# the XP chest waiting (its time, and the advert offer the stand-ins show) and the first package still unlocking
				var keep_chest: Array = [Game.progress.get("chest_at", 0), Game.progress.get("chest_from", 0), Game.progress.get("chest_cut", false), Game.get_s("ad_standins")]
				Game.progress["chest_from"] = Game.now() - 600
				Game.progress["chest_cut"] = false
				Game.progress["chest_at"] = Game.now() + XP.CHEST_WAIT - 600
				Game.settings["ad_standins"] = true
				if not Game.progress.has("pk_time"):
					Game.progress["pk_time"] = {}
				(Game.progress["pk_time"] as Dictionary)["3"] = Game.now()
				for scr in ["menu", "online", "gear", "packages", "chest", "vs_ai", "pass_play", "controls", "settings", "help"]:
					_stack.clear()
					go(scr)
					await _wait(0.5)
					problems += _audit_text(code, scr)
					if scr == "menu":
						# the daily gift and the packages sit under the buttons, never on them
						var corner: Control = _screen.get_node_or_null("MenuCorner")
						var col2: Control = _screen.get_node_or_null("MenuColumn")
						var card2: Control = _screen.find_child("GearCard", true, false)
						if corner and col2 and corner.get_global_rect().position.y < col2.get_global_rect().end.y - 1.0:
							problems += 1
							print("  OVERLAP [%s/menu] the corner starts at y %d, the buttons end at %d" % [code, corner.get_global_rect().position.y, col2.get_global_rect().end.y])
						if corner and card2 and corner.get_global_rect().position.x < card2.get_global_rect().end.x + 10.0:
							problems += 1
							print("  OVERLAP [%s/menu] the corner reaches the gear card" % code)
					if scr == "menu":
						# the button column must stay clear of the game's name beside it
						var ml: Control = _screen.get_node_or_null("MenuLeft")
						var mc: Control = _screen.get_node_or_null("MenuColumn")
						if ml and mc:
							print("  menu gap [%s] %d px" % [code, mc.get_global_rect().position.x - ml.get_global_rect().end.x])
						if ml and mc and mc.get_global_rect().position.x < ml.get_global_rect().end.x + 20.0:
							problems += 1
							print("  OVERLAP [%s/menu] buttons start at %d, the title ends at %d" % [code, mc.get_global_rect().position.x, ml.get_global_rect().end.x])
					await _shot(dir, "lang_%s_%s" % [code, scr])
					if scr in ["settings", "help", "controls"]:
						var sc := _screen.find_children("*", "ScrollContainer", true, false)
						if not sc.is_empty():
							(sc[0] as ScrollContainer).scroll_vertical = 100000
							await _wait(0.3)
							problems += _audit_text(code, scr + "_end")
							await _shot(dir, "lang_%s_%s_end" % [code, scr])
				Game.progress["packages"] = keep_q
				Game.progress["chest_at"] = keep_chest[0]
				Game.progress["chest_from"] = keep_chest[1]
				Game.progress["chest_cut"] = keep_chest[2]
				Game.settings["ad_standins"] = keep_chest[3]
				(Game.progress.get("pk_time", {}) as Dictionary).erase("3")
				if "--menus" in OS.get_cmdline_user_args():
					continue   # menu screens only (quick)
				if "--brk" in OS.get_cmdline_user_args():
					# the break only (quick): its turn banner and the place-the-cue-ball hint
					Game.set_s("control_scheme", "slingshot")
					start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
					await _wait(0.7)
					problems += _audit_text(code, "versus_banner")
					await _shot(dir, "lang_%s_versus_banner" % code)
					await _wait(1.8)
					game.start_ball_in_hand()
					await _wait(0.4)
					problems += _audit_text(code, "break_place")
					await _shot(dir, "lang_%s_break_place" % code)
					_end_match()
					continue
				for scheme in ["pro_dial", "phone_cue", "crank", "trackpad"]:
					Game.set_s("control_scheme", scheme)
					start_match({"mode": "practice"})
					await _wait(1.6)
					problems += _audit_text(code, "practice_" + scheme)
					await _shot(dir, "lang_%s_practice_%s" % [code, scheme])
				game.start_ball_in_hand()
				await _wait(0.4)
				problems += _audit_text(code, "ball_in_hand")
				await _shot(dir, "lang_%s_hand" % code)
				Game.set_s("control_scheme", "slingshot")
				start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
				await _wait(0.7)
				problems += _audit_text(code, "versus_banner")
				await _shot(dir, "lang_%s_versus_banner" % code)
				await _wait(1.8)
				game.start_ball_in_hand()   # the break: the cue ball may be moved behind the line
				await _wait(0.4)
				problems += _audit_text(code, "break_place")
				await _shot(dir, "lang_%s_break_place" % code)
				game.confirm_cue_placement()
				await _wait(0.2)
				pause()
				await _wait(0.4)
				problems += _audit_text(code, "pause")
				problems += _pause_fits(code, "pause")
				await _shot(dir, "lang_%s_pause" % code)
				resume()
				# the gear drawer (Choose Gear on the right, in a match)
				hud.open_gear()
				await _wait(0.6)
				problems += _audit_text(code, "gear_drawer")
				var gdp: Control = hud.find_child("GearDrawerPanel", true, false)
				if gdp and not get_viewport().get_visible_rect().grow(1.0).encloses(gdp.get_global_rect()):
					problems += 1
					print("  OFF SCREEN [%s/gear_drawer] %s" % [code, gdp.get_global_rect()])
				var gdh: Control = gdp.get_child(0).get_child(0) if gdp else null
				if gdh and gdh.get_combined_minimum_size().x > gdp.size.x - 40.0:
					problems += 1
					print("  TOO WIDE [%s/gear_drawer] the heading row needs %d px" % [code, gdh.get_combined_minimum_size().x])
				await _shot(dir, "lang_%s_drawer" % code)
				var gdr = hud.find_child("GearDrawer", true, false)
				if gdr:
					gdr.close()
				await _wait(0.4)
				# v1.1.5: the potted-ball cards and the groups card, and the top view's free look with its hint
				Game.set_s("reduced_motion", true)
				game.ball_potted.emit(12, 0)
				game.ball_potted.emit(0, 1)
				game.rules.groups = [EightBall.Group.STRIPES, EightBall.Group.SOLIDS]
				game.groups_set.emit()
				(hud.get("_btn_views")[2] as Button).pressed.emit()
				await _wait(0.3)
				stage.set_free_look(true)
				await _wait(0.4)
				problems += _audit_text(code, "pot_feed_free_look")
				var pf: PotFeed = hud.pot_feed()
				for slot in pf.get_child(0).get_children():
					var cr: Rect2 = (slot.get_child(0) as Control).get_global_rect()
					if not get_viewport().get_visible_rect().encloses(cr) or cr.size.x > 560.0:
						problems += 1
						print("  TOO WIDE / OFF SCREEN [%s/pot_feed] %s" % [code, cr])
				await _shot(dir, "lang_%s_feed" % code)
				stage.set_free_look(false)
				(hud.get("_btn_views")[0] as Button).pressed.emit()
				Game.set_s("reduced_motion", false)
				await _wait(0.3)
				# a win with every XP line showing, two levels gained and packages to open: the fullest the score screen gets
				var keep_q2: Array = Game.packages().duplicate()
				Game.progress["packages"] = range(6, 33)   # 27 waiting: the longest the button text gets in normal play
				_results = Overlays.Results.new(self, {"mode": "versus", "winner": 0, "winner_name": game.player_names[0], "reason": "Sank the 8!", "shots": 23, "vs_ai": true, "ai_level": 2,
					"xp": {"balls": 8, "ball_xp": 100, "streak_xp": 4, "combo_xp": 3, "eight_xp": 28, "win_xp": 40, "factor": 0.5, "total": 175, "best_streak": 2, "mode": "cpu"},
					"gain": {"from": 5, "to": 7, "xp_from": XP.total_for(6) - 40, "xp_to": XP.total_for(7) + 20}})
				overlay_host.add_child(_results)
				await _wait(4.6)
				problems += _audit_text(code, "results")
				for rb in _results.find_children("*", "Button", true, false):
					var rr: Rect2 = (rb as Control).get_global_rect()
					if (rb as Control).is_visible_in_tree() and (rr.end.y > get_viewport().get_visible_rect().size.y + 1.0 or rr.position.y < 0.0):
						problems += 1
						print("  OFF SCREEN [%s/results] the score screen is too tall: a button ends at y %d" % [code, rr.end.y])
				Game.progress["packages"] = keep_q2
				await _shot(dir, "lang_%s_results" % code)
				_results.queue_free()
				_results = null
				# Practice's rack-cleared screen, and what the XP chest gives (with a level gained)
				_results = Overlays.RackCleared.new(self, {"shots": 27, "seconds": 754})
				overlay_host.add_child(_results)
				await _wait(0.8)
				problems += _audit_text(code, "rack_cleared")
				await _shot(dir, "lang_%s_rack" % code)
				_results.queue_free()
				_results = null
				var xr := RewardScreens.XpReveal.new(self, {"xp": 69, "gain": {"from": 9, "to": 10, "xp_from": XP.total_for(10) - 30, "xp_to": XP.total_for(10) + 39}})
				overlay_host.add_child(xr)
				await _wait(2.4)
				problems += _audit_text(code, "xp_chest_reveal")
				await _shot(dir, "lang_%s_xp_reveal" % code)
				xr.queue_free()
				# AR panels (simulated ARCore): the "can't start" panel and the place-the-table panel
				Game.set_s("ar_mode", "auto")
				stage.arcore.simulate = true
				stage.arcore.sim_path = func(_t: float) -> Transform3D:
					return Transform3D(Basis.looking_at(Vector3(0, -0.6, -1.0), Vector3.UP), Vector3(0, 1.4, 0))
				stage.arcore.sim_availability = "not_installed"
				start_match({"mode": "practice"})
				await _wait(1.0)
				problems += _audit_text(code, "ar_blocked")
				await _shot(dir, "lang_%s_ar_blocked" % code)
				stage.arcore.sim_availability = "installed"
				stage.arcore.sim_floor = 0.0
				start_match({"mode": "practice"})
				await _wait(1.5)
				problems += _audit_text(code, "ar_place")
				await _shot(dir, "lang_%s_ar_place" % code)
				var pb2: Button = hud.get("_ar_place")
				var pc2 := pb2.get_global_rect().get_center()
				await _touch(0, pc2, true)
				await _touch(0, pc2, false)
				await _wait(0.6)
				hud.open_table_adjust()
				await _wait(0.5)
				problems += _audit_text(code, "ar_adjust")
				await _shot(dir, "lang_%s_ar_adjust" % code)
				hud.close_table_adjust()
				# the pause menu in AR with the scene background on: its card is at its tallest
				var keep_bg: bool = Game.get_s("ar_background")
				Game.set_s("ar_background", true)
				pause()
				await _wait(0.5)
				problems += _audit_text(code, "pause_ar")
				problems += _pause_fits(code, "pause_ar")
				await _shot(dir, "lang_%s_pause_ar" % code)
				resume()
				Game.set_s("ar_background", keep_bg)
				stage.arcore.simulate = false
				Game.set_s("ar_mode", "studio")
				_end_match()
			# changing the language inside a match updates the HUD at once
			Loc.set_language("en")
			Game.set_s("control_scheme", "pro_dial")
			start_match({"mode": "versus", "vs_ai": true, "ai_level": 0})
			await _wait(3.0)
			var before: String = (hud.get("_info_title") as Label).text
			Loc.set_language("de")
			await _wait(0.3)
			var after: String = (hud.get("_info_title") as Label).text
			var live_ok: bool = before == "8-BALL · VS CPU (EASY)" and after == "8-BALL · GEGEN KI (LEICHT)" and game.player_names[1] == "CPU · Leicht"
			print("  %s  language switch inside a match (%s -> %s, %s)" % ["ok  " if live_ok else "FAIL", before, after, game.player_names[1]])
			await _shot(dir, "lang_live_switch_de")
			var det_ok: bool = Loc.detect("pt_BR") == "pt" and Loc.detect("zh_Hans_CN") == "zh" and Loc.detect("en_US") == "en" and Loc.detect("sv_SE") == "sv" and Loc.detect("fi_FI") == "en" and Loc.detect("ar-EG") == "ar" and Loc.detect("ja") == "ja" and Loc.detect("hi_IN") == "hi" and Loc.detect("ko_KR") == "ko" and Loc.detect("ru_RU") == "ru" and Loc.detect("de_AT") == "de" and Loc.detect("fr_CA") == "fr" and Loc.detect("es_MX") == "es" and Loc.detect("it_IT") == "it" and Loc.detect("zh_TW") == "zh_TW" and Loc.detect("zh_Hant_HK") == "zh_TW" and Loc.detect("zh_Hans_SG") == "zh" and Loc.detect("in_ID") == "id" and Loc.detect("iw_IL") == "he" and Loc.detect("uk_UA") == "uk" and Loc.detect("th_TH") == "th" and Loc.detect("bn_BD") == "bn" and Loc.detect("ur_PK") == "ur" and Loc.detect("vi_VN") == "vi" and Loc.detect("ta_IN") == "ta" and Loc.detect("nb_NO") == "en"
			print("  %s  phone language -> game language" % ("ok  " if det_ok else "FAIL"))
			Loc.set_language("auto")
			print("LANG %s (%d text problems)" % ["PASS" if problems == 0 and live_ok and det_ok else "FAIL", problems])
			_end_match()
			Game.set_s("control_scheme", "slingshot")
			Game.set_s("ar_mode", "auto")
		"scenes":
			# every Studio scene from three places: the aim view, a low look across the table, the overview
			Game.set_s("ar_mode", "studio")
			var keep_scene: String = Game.get_s("scene")
			var only_scene := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--scene="):
					only_scene = arg.substr(8)
			for e in Catalog.SCENES:
				if (only_scene != "" and not (str(e["id"]) in only_scene.split(","))) or "--flick" in OS.get_cmdline_user_args():
					continue
				Game.set_s("scene", e["id"])
				start_match({"mode": "practice"})
				await _wait(0.8)
				hud.visible = false
				stage.set_view(Stage.View.OVERVIEW)
				stage.set("_idle_spin", false)
				await _wait(1.2)
				await _shot(dir, "scene_%s_over" % e["id"])
				# how heavy the scene is to draw, next to the plain Lounge (the software renderer makes this a fair ratio)
				var f0 := Engine.get_frames_drawn()
				var t0 := Time.get_ticks_usec()
				await _wait(1.5)
				print("SCENE COST %s: %.1f ms a frame" % [e["id"], (Time.get_ticks_usec() - t0) / 1000.0 / maxf(Engine.get_frames_drawn() - f0, 1)])
				for yaw_i in 3:
					if "--quick" in OS.get_cmdline_user_args() and yaw_i != 1:
						continue
					stage.set("_manual", true)
					stage.set("_want_pitch", deg_to_rad(9.0))
					stage.set("_want_dist", 2.9)
					stage.set("_want_yaw", [0.0, 2.2, 4.3][yaw_i])
					await _wait(1.3)
					await _shot(dir, "scene_%s_low%d" % [e["id"], yaw_i])
				stage.reset_manual()
				stage.set_view(Stage.View.AIM)
				await _wait(1.3)
				hud.visible = true
				await _shot(dir, "scene_%s_aim" % e["id"])
			# flicking through every scene twice, quickly: nothing left behind, nothing breaks
			if only_scene == "":
				start_match({"mode": "practice"})
				await _wait(0.5)
				for rep in 2:
					for e in Catalog.SCENES:
						Game.set_s("scene", e["id"])
						await _wait(0.12)
				await _wait(0.5)
				var fx_n: int = (stage.get("_fx") as Node).get_child_count()
				var last: Dictionary = Catalog.SCENES[-1]
				var flick_ok: bool = fx_n == (1 if str(last.get("fx", "")) != "" else 0) and (stage.get("_dome") as Node3D).visible == (int(last.get("sky", 0)) != 0)
				Game.set_s("scene", "lounge")
				await _wait(0.3)
				flick_ok = flick_ok and (stage.get("_fx") as Node).get_child_count() == 0 and not (stage.get("_dome") as Node3D).visible
				print("  %s  switching scenes back and forth leaves one set of particles and the right backdrop" % ("ok  " if flick_ok else "FAIL"))
				print("SCENES %s" % ("PASS" if flick_ok else "FAIL"))
			Game.set_s("scene", keep_scene)
			Game.set_s("ar_mode", "auto")
			_end_match()
		"wheelzone":
			# Pro Dial: the fine-aim wheel also answers one wheel-height above and below itself (run at 1920x1080)
			Game.set_s("ar_mode", "studio")
			Game.set_s("control_scheme", "pro_dial")
			start_match({"mode": "practice"})
			await _wait(1.5)
			var wz_bad: Array = []
			var wz_ref: Array = []
			var wheel: Control = game.control.get("_wheel")
			var wr := wheel.get_global_rect()
			var wz := func(label: String, y: float, expect_wheel: bool) -> void:
				var y0: float = game.control.yaw
				var px := wr.get_center().x - 120.0
				await _touch(0, Vector2(px, y), true)
				for k in 8:
					px += 30.0
					await _drag(0, Vector2(px, y))
				await _touch(0, Vector2(px, y), false)
				await _wait(0.2)
				var dy: float = absf(angle_difference(y0, game.control.yaw))
				# the same drag on the wheel always turns the aim by the same amount; a touch that reaches the table does something else
				if wz_ref.is_empty():
					wz_ref.append(dy)
				var by_wheel: bool = dy > 0.0005 and absf(dy - float(wz_ref[0])) < 0.0005
				var good: bool = by_wheel == expect_wheel
				if not good:
					wz_bad.append(label)
				print("  %s  %s  (aim moved %.3f deg)" % ["ok  " if good else "FAIL", label, rad_to_deg(dy)])
			await wz.call("drag on the wheel itself -> fine aim", wr.get_center().y, true)
			await wz.call("drag 80% of a wheel-height above it -> still fine aim", wr.position.y - wr.size.y * 0.8, true)
			await wz.call("drag 80% of a wheel-height below it -> still fine aim", minf(wr.end.y + wr.size.y * 0.8, get_viewport().get_visible_rect().size.y - 4.0), true)
			await wz.call("drag two wheel-heights above it -> not the wheel", wr.position.y - wr.size.y * 2.0, false)
			# no tap-to-aim in Pro Dial for now (Randy, 11 Nov 2026): a tap or a drag on the table leaves the aim alone
			var y_tap: float = game.control.yaw
			var mid_table := stage.table_to_screen(Vector2(0.4, 0.2))
			await _touch(0, mid_table, true)
			await _drag(0, mid_table + Vector2(60, 30))
			await _touch(0, mid_table + Vector2(60, 30), false)
			await _wait(0.2)
			var tap_ok: bool = is_equal_approx(y_tap, game.control.yaw)
			if not tap_ok:
				wz_bad.append("tap")
			print("  %s  a tap and a drag on the table do not swing the aim (Pro Dial has no tap-to-aim)" % ("ok  " if tap_ok else "FAIL"))
			await _shot(dir, "wheelzone")
			print("WHEELZONE %s" % ("PASS" if wz_bad.is_empty() else "FAIL"))
			_end_match()
			Game.set_s("control_scheme", "slingshot")
			Game.set_s("ar_mode", "auto")
		"ar_scene":
			# "Scene background in AR": camera picture until the table is placed, then a scene round the AR table
			var as_bad: Array = []
			var chk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					as_bad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			Game.set_s("ar_mode", "auto")
			Game.set_s("ar_background", true)
			stage.arcore.simulate = true
			stage.arcore.sim_floor = 0.0
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				return Transform3D(Basis.looking_at(Vector3(0, -0.45, -1.0), Vector3.UP), Vector3(0.3, 1.5, 1.2))
			Game.set_s("surface", "floor")
			if "--desk" in OS.get_cmdline_user_args():
				# a mini table on a desk 0.75 m high, seen from a chair
				Game.set_s("surface", "desk")
				stage.arcore.sim_floor = 0.75
				stage.arcore.sim_path = func(_t: float) -> Transform3D:
					var eye := Vector3(0.15, 1.25, 0.75)
					return Transform3D(Basis.looking_at(Vector3(0, 0.8, -0.2) - eye, Vector3.UP), eye)
			var room: Node3D = stage.get("_room")
			var dome: Node3D = stage.get("_dome")
			var seen_ids := {}
			for round_i in 3:
				start_match({"mode": "practice"})
				await _wait(1.6)
				if round_i == 0:
					chk.call("before the table is placed you see the camera picture", not room.visible and stage.env.background_mode == Environment.BG_CANVAS)
					await _shot(dir, "ar_scene_before")
				stage.place_table()
				await _wait(1.2)
				var sc_now: Dictionary = stage.get("_scene")
				seen_ids[sc_now.get("id", "?")] = true
				if round_i == 0:
					chk.call("table placed -> a scene round the table", room.visible and dome.visible and stage.env.background_mode == Environment.BG_SKY and int(sc_now.get("sky", 0)) != 0, str(sc_now.get("name", "")))
					await _wait(0.6)
					chk.call("... and the camera picture is really out of the way (it keeps arriving every frame)", not (stage.camera_bg.get("_rect") as Control).visible)
					var tr: Transform3D = stage.table_root.global_transform
					chk.call("the scene's floor is turned and sized with the table", room.global_transform.basis.get_scale().is_equal_approx(tr.basis.get_scale()) and absf(room.global_position.x - tr.origin.x) < 0.001 and absf(room.global_position.z - tr.origin.z) < 0.001 and room.global_position.y <= tr.origin.y + 0.001)
					chk.call("no shadow blob under the table on a scene floor", not (stage.get("_blob") as Node3D).visible and not (stage.get("_shadow_catcher") as Node3D).visible)
				hud.visible = false
				await _shot(dir, "ar_scene_%d" % round_i)
				hud.visible = true
			chk.call("three matches -> three different scenes", seen_ids.size() == 3, str(seen_ids.keys()))
			stage.unplace_table()
			await _wait(0.5)
			chk.call("moving the table again -> the camera picture is back", not room.visible and stage.env.background_mode == Environment.BG_CANVAS)
			stage.place_table()
			await _wait(0.5)
			Game.set_s("ar_background", false)
			await _wait(0.5)
			chk.call("switched off in Settings during a match -> camera picture", not room.visible and stage.env.background_mode == Environment.BG_CANVAS)
			Game.set_s("ar_background", true)
			await _wait(0.5)
			chk.call("switched on again -> the scene", room.visible)
			_end_match()
			stage.arcore.simulate = false
			Game.set_s("ar_mode", "studio")
			go("menu")
			stage.set_mode(Stage.Mode.STUDIO)
			await _wait(0.6)
			var back: Dictionary = stage.get("_scene")
			chk.call("back in the Studio view your own scene is shown", back.get("id", "") == Game.get_s("scene") and room.visible and room.transform.is_equal_approx(Transform3D.IDENTITY), str(back.get("id", "")))
			print("AR_SCENE %s" % ("PASS" if as_bad.is_empty() else "FAIL"))
			Game.set_s("ar_background", false)
			Game.set_s("ar_mode", "auto")
			Game.set_s("surface", "desk")
		"breakpos":
			# the break: the cue ball can be moved, but only behind the head string; the break is struck harder
			Game.set_s("ar_mode", "studio")
			Game.set_s("control_scheme", "pro_dial")
			var bp_bad: Array = []
			var bp := func(label: String, good: bool, detail := "") -> void:
				if not good:
					bp_bad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			start_match({"mode": "versus", "vs_ai": false})
			await _wait(3.2)
			var head_x: float = Rack.head_spot(game.sim).x
			bp.call("the hand button is offered before the break", (hud.get("_btn_hand") as Control).visible)
			await _shot(dir, "break_aim")
			game.start_ball_in_hand()
			await _wait(0.5)
			bp.call("hand button -> the cue ball can be moved", game.state == PoolGame.State.BALL_IN_HAND)
			game.move_cue_ball(Vector2(0.5, 0.2))
			bp.call("dragged past the line -> stops on the line", absf(game.cue_ball_pos().x - head_x) < 0.001 and absf(game.cue_ball_pos().y - 0.2) < 0.001, str(game.cue_ball_pos()))
			game.move_cue_ball(Vector2(-5.0, 5.0))
			bp.call("dragged off the table -> stays on the cloth", game.sim.table.in_bounds(game.cue_ball_pos(), -0.0001), str(game.cue_ball_pos()))
			game.move_cue_ball(Vector2(head_x - 0.25, -0.22))
			bp.call("anywhere behind the line is allowed", game.cue_ball_pos().distance_to(Vector2(head_x - 0.25, -0.22)) < 0.001)
			await _wait(0.4)
			await _shot(dir, "break_place")
			game.confirm_cue_placement()
			await _wait(0.3)
			bp.call("Place ball -> aiming, the ball stays put", game.state == PoolGame.State.AIM and game.cue_ball_pos().distance_to(Vector2(head_x - 0.25, -0.22)) < 0.001)
			game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
			var v1: float = game.sim.vel[game.cue_index()].length()
			bp.call("the break at full power leaves at twice the usual top speed", v1 > 1.9 * game.sim.max_speed and v1 < 2.001 * game.sim.max_speed, "%.1f m/s (a little is lost when the cue has to be raised over the rail)" % v1)
			while game.state == PoolGame.State.ROLLING:
				game.fast_forward()
				await _wait(0.3)
			await _wait(0.5)
			bp.call("after the break it is no longer a break", not game.break_pending() and not game.sim.break_shot)
			if game.state == PoolGame.State.BALL_IN_HAND:
				game.move_cue_ball(Vector2(0.4, 0.1))
				bp.call("ball in hand after the break: anywhere on the table", game.cue_ball_pos().x > 0.2, str(game.cue_ball_pos()))
				game.confirm_cue_placement()
			if game.state == PoolGame.State.AIM:
				game.fire(0.3, 1.0, Vector2.ZERO, 0.0)
				var v2: float = game.sim.vel[game.cue_index()].length()
				bp.call("every later shot keeps the usual top speed", absf(v2 - game.sim.max_speed) < 0.05, "%.1f m/s" % v2)
			# practice: the first shot is a break too (same speed), the cue ball may go anywhere
			start_match({"mode": "practice"})
			await _wait(1.5)
			game.start_ball_in_hand()
			game.move_cue_ball(Vector2(0.0, 0.3))
			bp.call("practice: the cue ball may be placed anywhere", game.cue_ball_pos().distance_to(Vector2(0.0, 0.3)) < 0.001)
			game.confirm_cue_placement()
			game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
			var v3: float = game.sim.vel[game.cue_index()].length()
			bp.call("practice: the first shot on a full rack is a break", v3 > 1.9 * game.sim.max_speed, "%.1f m/s" % v3)
			while game.state == PoolGame.State.ROLLING:
				game.fast_forward()
				await _wait(0.3)
			game.undo()
			await _wait(0.3)
			bp.call("practice: undoing the break makes the next shot the break again", game.break_pending() and game.sim.break_shot)
			print("BREAKPOS %s" % ("PASS" if bp_bad.is_empty() else "FAIL"))
			_end_match()
			Game.set_s("control_scheme", "slingshot")
			Game.set_s("ar_mode", "auto")
		"packages":
			# v1.1.7: the five packages and the XP chest as the game draws them, shut and opened (pictures for Randy)
			_stack.clear()
			go("menu")
			await _wait(0.5)
			var pk_bg := ColorRect.new()
			pk_bg.color = Color(0.043, 0.07, 0.125)
			pk_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			ui_root.add_child(pk_bg)
			var pk_ok := true
			for pk_i in 6:
				var pv: PackageView = PackageView.xp_chest(640.0) if pk_i == 5 else PackageView.new(pk_i + 1, 640.0)
				pv.position = (get_viewport().get_visible_rect().size - Vector2(640, 640)) * 0.5
				ui_root.add_child(pv)
				await _wait(1.2)
				var nm := "xp" if pk_i == 5 else str(pk_i + 1)
				pk_ok = pk_ok and pv.get("_lid") != null and (pv.get("_lid") as Node3D).get_child_count() > 0
				await _shot(dir, "pk_%s_shut" % nm)
				pv.open()
				await pv.opened
				await _wait(0.9)
				await _shot(dir, "pk_%s_open" % nm)
				pv.queue_free()
				await _wait(0.2)
			pk_bg.queue_free()
			print("PACKAGES %s" % ("PASS" if pk_ok else "FAIL (a model has no lid)"))
		"perf":
			await _perf_tour(dir)
		"loading":
			# the screen shown while the table is being built at startup
			var ls := _make_loading()
			add_child(ls)
			await _wait(0.3)
			await _shot(dir, "loading")
			ls.queue_free()
		"notices":
			# whose notices show up: your own praise yes, the opponent's praise no
			Game.set_s("ar_mode", "studio")
			var got: Array = []
			var grab := func(text: String, _kind: String) -> void: got.append(text)
			var shoot := func(cfg: Dictionary, shooter: int, ball: int, open: bool) -> Array:
				start_match(cfg)
				got.clear()
				game.message.connect(grab)
				game.rules.is_break = false
				game.rules.groups = [EightBall.Group.NONE, EightBall.Group.NONE] if open else [EightBall.Group.SOLIDS, EightBall.Group.STRIPES]
				game.rules.current = shooter
				game.rules.snapshot_before_shot(game.sim)
				var bi: int = game.sim.index_of_number(ball)
				game.sim.st[bi] = PoolSim.ST_POCKETED
				game.sim.first_hit = bi
				game.sim.cushion_after_contact = true
				game.potted_this_shot.clear()
				game.potted_this_shot.append({"number": ball, "pocket": 0, "index": bi})
				game.jumped_this_shot.clear()
				game._resolve_versus()
				return got.duplicate()
			var cpu := {"mode": "versus", "vs_ai": true, "ai_level": 0}
			var two := {"mode": "versus", "vs_ai": false}
			var n_ok := true
			var rows := [
				["vs CPU: the CPU pots its ball -> no notice for you", shoot.call(cpu, 1, 12, false), []],
				["vs CPU: you pot your ball -> 'Nice! Shoot again.'", shoot.call(cpu, 0, 3, false), ["Nice! Shoot again."]],
				["vs CPU: the CPU claims solids -> you are told you're on stripes", shoot.call(cpu, 1, 3, true), [EightBall.on_group_text(EightBall.Group.STRIPES)]],
				["vs CPU: you claim solids -> you are told you're on solids", shoot.call(cpu, 0, 3, true), [EightBall.on_group_text(EightBall.Group.SOLIDS)]],
				["vs CPU: the CPU fouls (wrong ball first) -> you are told (ball in hand)", shoot.call(cpu, 1, 3, false), ["foul"]],
				["local turn based: player 2 pots -> shown (same phone)", shoot.call(two, 1, 12, false), ["Nice! Shoot again."]],
			]
			for row in rows:
				var want: Array = row[2]
				var have: Array = row[1]
				var good: bool = have == want
				if want == ["foul"]:
					good = have.size() == 1 and str(have[0]).length() > 12 and str(have[0]) != "Nice! Shoot again."
				n_ok = n_ok and good
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", row[0], str(have)])
			print("NOTICES %s" % ("PASS" if n_ok else "FAIL"))
			_end_match()
			Game.set_s("ar_mode", "auto")
		"ballsets":
			# every ball set, racked, seen from above (for the look-over sheet)
			Game.set_s("ar_mode", "studio")
			var keep: String = Game.get_s("ball_set")
			var only_set := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--set="):
					only_set = arg.substr(6)
			# --test: the twenty sets designed on 12 Nov (ball shader styles 16-35), close up
			var set_list: Array = Catalog.BALLS.filter(func(e): return int(e.get("style", -1)) >= 16) if "--test" in OS.get_cmdline_user_args() else Catalog.BALLS
			for e in set_list:
				if only_set != "" and not (str(e["id"]) in only_set.split(",")):
					continue
				Game.set_s("ball_set", e["id"])
				start_match({"mode": "practice"})
				await _wait(0.6)
				hud.visible = false
				var mid := Vector3.ZERO
				var cnt := 0
				for i in game.sim.n:
					if i != game.cue_index():
						mid += game.views[i].position
						cnt += 1
				mid /= float(cnt)
				var cue_v: BallView = game.views[game.cue_index()]
				cue_v.position = mid + Vector3(-0.2, 0.0, 0.0)
				game.cue_view.visible = false
				if "--test" in OS.get_cmdline_user_args():
					# close-up: the cue ball and seven balls in two rows, each turned its own way so the look shows
					game.process_mode = Node.PROCESS_MODE_DISABLED
					var show := [0, 1, 3, 8, 9, 11, 14, 6]
					var rng := RandomNumberGenerator.new()
					rng.seed = 11
					var R: float = game.sim.R
					for i in game.sim.n:
						var num: int = game.sim.num[i]
						var slot := show.find(num)
						var v: BallView = game.views[i]
						if slot < 0:
							v.position = Vector3(0, -1.0, 0)
							continue
						var row := slot / 4
						var colm := slot % 4
						v.position = Vector3(0.62 + colm * 0.068 + row * 0.034, R, -0.05 + row * 0.07)
						v.basis = Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.9, 0.9) + 0.5, rng.randf_range(-0.4, 0.4)))
					mid = Vector3(0.62 + 0.12, 0.0, -0.015)
				# the game's own camera, moved in close (so the picture is lit exactly as in play)
				stage.set("_manual", true)
				stage.set("_want_target", stage.table_root.to_global(mid + (Vector3(0.012, 0.0, 0.0) if "--test" in OS.get_cmdline_user_args() else Vector3(-0.04, 0.0, 0.0))))
				var test_pic := "--test" in OS.get_cmdline_user_args()
				stage.set("_want_dist", 0.34 if test_pic else 0.5)
				stage.set("_want_pitch", deg_to_rad(24.0 if test_pic else 33.0))
				stage.set("_want_yaw", 0.25 if test_pic else 0.55)
				await _wait(2.4)
				await _shot(dir, "balls_" + str(e["id"]))
			stage.reset_manual()
			Game.set_s("ball_set", keep)
			Game.set_s("ar_mode", "auto")
			_end_match()
		"online":
			# a whole online match against a second "phone" (tests/online_ghost.gd) through an in-memory copy of
			# the server (tests/fake_server.gd), then the two ways a match can end early
			var srv = load("res://tests/fake_server.gd").new()
			var Ghost = load("res://tests/online_ghost.gd")
			Net.fake = srv
			var keep_pr: Dictionary = Game.progress.duplicate(true)
			Game.progress = Game.fresh_progress()
			Game.set_s("ar_mode", "studio")
			var on_ok := true
			var say := func(good: bool, what: String):
				print("  %s  %s" % ["ok  " if good else "FAIL", what])
				return good
			for round_no in 3:
				var ghost = Ghost.new()
				ghost.join(srv, "Ghost", 40, Game.VERSION)
				if round_no == 1:
					ghost.quit_after = 0      # leaves at its first turn
				_stack.clear()
				go("online")
				await _wait(0.4)
				if round_no == 0:
					await _shot(dir, "online_search")
				_screen.call("_search")
				var waited := 0.0
				while game == null and waited < 20.0:
					ghost.tick("Ghost", 40, Game.VERSION)
					await _wait(0.1)
					waited += 0.1
				if not say.call(game != null and game.online and game.net != null, "round %d: found an opponent and the match started" % (round_no + 1)):
					on_ok = false
					break
				if round_no == 0:
					on_ok = say.call(game.net.host and not ghost.host, "the faster connection hosts (this phone: host %s, the other: host %s)" % [game.net.host, ghost.host]) and on_ok
					on_ok = say.call(game.net_seat == 1 - ghost.seat and game.player_names[ghost.seat] == "Ghost", "seats %d / %d, opponent's name shown: %s" % [game.net_seat, ghost.seat, str(game.player_names)]) and on_ok
					on_ok = say.call(Net.registered() and srv.players.has(str(Game.progress.get("player", ""))), "this install registered itself as a player") and on_ok
					# whose gear: each player's own cue; the table of the player who breaks (seat 0), the other's balls
					var my_table := str(Game.get_s("table_style"))
					var my_balls := str(Game.get_s("ball_set"))
					var want_table: String = my_table if game.net_seat == 0 else ghost.table
					var want_balls: String = ghost.balls if game.net_seat == 0 else my_balls
					on_ok = say.call(game.cue_skins[ghost.seat] == ghost.cue and game.cue_skins[game.net_seat] == str(Game.get_s("cue_skin")), "each player holds their own cue (the other's: %s)" % game.cue_skins[ghost.seat]) and on_ok
					on_ok = say.call(str(stage.table_view.style.get("id")) == want_table and game.ball_set == want_balls,
						"the table of the player who breaks (%s), the other player's balls (%s); this phone is seat %d" % [str(stage.table_view.style.get("id")), game.ball_set, game.net_seat]) and on_ok
					on_ok = say.call(not hud.gear_drawer_allowed() and not (hud.get("_btn_gear") as Control).visible, "no gear drawer in an online match") and on_ok
					on_ok = say.call(game.gear_note() != "" and ("%s" in game.gear_note()) == false, "whose table and balls is said: \"%s\"" % game.gear_note()) and on_ok
				hud.visible = round_no == 0
				var ai2 := AIPlayer.new(2)
				var frames := 0
				var shot_pic := false
				var my_shots := 0
				while game != null and game.state != PoolGame.State.OVER and frames < 60000:
					srv.now = Time.get_ticks_msec() / 1000.0
					ghost.tick("Ghost", 40, Game.VERSION)
					frames += 1
					if game.plays_here(game.current) and game.state in [PoolGame.State.AIM, PoolGame.State.BALL_IN_HAND]:
						if round_no == 2 and my_shots >= 1:
							break      # this phone's player walks away
						var own2 := []
						var g2: int = game.rules.groups[game.current]
						for nn in range(1, 16):
							if nn != 8 and (g2 == EightBall.Group.NONE or EightBall.group_of(nn) == g2):
								own2.append(nn)
						if game.state == PoolGame.State.BALL_IN_HAND:
							game.move_cue_ball(ai2.choose_placement(game.sim.clone(), own2))
							game.confirm_cue_placement()
						var legal2: Array = game.rules.legal_targets(game.sim, game.current)
						var snap2: PoolSim = game.sim.clone()
						snap2.record_events = false
						var pick: Dictionary = ai2.choose(snap2, legal2, own2, legal2 == [8], game.rules.is_break)
						if round_no == 1:
							pick = {"yaw": 1.2, "power": 0.03, "offset": Vector2.ZERO, "elev": 0.0}     # a tap that reaches nothing: the turn passes
						game.fire(pick["yaw"], pick["power"], pick["offset"], pick["elev"])
						my_shots += 1
					elif game.state == PoolGame.State.ROLLING:
						game.time_scale = 4.0
						if round_no == 0 and not shot_pic and game.shots_total >= 3:
							shot_pic = true
							await _shot(dir, "online_play")
					await get_tree().process_frame
				match round_no:
					0:
						on_ok = say.call(game != null and game.state == PoolGame.State.OVER, "the match was played to the end (%d shots here, %d there)" % [my_shots, ghost.shots_sent]) and on_ok
						for i in 30:
							ghost.tick("Ghost", 40, Game.VERSION)
							await _wait(0.05)
						on_ok = say.call(game.rules.winner >= 0 and game.rules.winner == ghost.rules.winner, "both phones name the same winner (seat %d)" % game.rules.winner) and on_ok
						on_ok = say.call(ghost.drift == 0 and ghost.shots_seen == my_shots, "the other phone replayed all %d of this phone's shots to exactly the same table" % ghost.shots_seen) and on_ok
						on_ok = say.call(game.net_drift == 0, "this phone replayed all %d of the other phone's shots to exactly the same table" % ghost.shots_sent) and on_ok
						var same := true
						for i in game.sim.n:
							same = same and game.sim.st[i] == ghost.sim.st[i] and (game.sim.st[i] == PoolSim.ST_POCKETED or game.sim.pos[i].distance_to(ghost.sim.pos[i]) < 1e-9)
						on_ok = say.call(same, "the two tables are identical at the end") and on_ok
						await _wait(1.6)
						var xr: Dictionary = _results.get("res") if _results else {}
						on_ok = say.call(_results != null and xr.get("online", false) and float(xr.get("xp", {}).get("factor", 0.0)) == 1.0, "score screen: an online match pays full XP (+%d)" % int(xr.get("xp", {}).get("total", 0))) and on_ok
						await _wait(2.5)
						await _shot(dir, "online_results")
						await _wait(4.5)
						var saved: Dictionary = srv.players.get(str(Game.progress.get("player", "")), {})
						on_ok = say.call(int(saved.get("xp", -1)) == Game.xp() and Game.xp() > 0, "the XP reached the server (%d)" % int(saved.get("xp", -1))) and on_ok
					1:
						await _wait(1.4)
						on_ok = say.call(game != null and game.state == PoolGame.State.OVER and game.rules.winner == game.net_seat and _results != null and str(_results.get("res").get("reason", "")) == "Your opponent left the match",
							"the opponent leaves -> this player wins, with the reason shown") and on_ok
					2:
						var mid2: int = game.net.match_id
						quit_to("menu")
						await _wait(1.0)
						var told := false
						for ev in srv.events:
							if ev["match"] == mid2 and ev["type"] == "over":
								var od: Dictionary = Marshalls.base64_to_variant(str(ev["data"]))
								told = int(od.get("winner", -1)) == ghost.seat
						on_ok = say.call(told and game == null, "this player leaves -> the other phone is told it has won") and on_ok
				_close_overlays()
				_end_match()
				await _wait(0.3)
			# the server forgets this install (its data was reset): the game signs up again by itself
			var old_id := str(Game.progress.get("player", ""))
			srv.players.erase(old_id)
			await Net.push_progress()
			var dropped := not Net.registered()
			await Net.push_progress()
			on_ok = say.call(old_id != "" and dropped and Net.registered() and str(Game.progress.get("player", "")) != old_id and srv.players.has(str(Game.progress.get("player", ""))),
				"the server no longer knows this install -> it signs up again and saves") and on_ok
			print("ONLINE %s" % ("PASS" if on_ok else "FAIL"))
			Net.fake = null
			Game.progress = keep_pr
			Game.progress_changed.emit()
			Game.set_s("ar_mode", "auto")
			_stack.clear()
			go("menu")
		"pausemenu":
			# the pause menu's view / table / scene card: everything switches in the middle of a match
			var pm_bad: Array = []
			var pchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					pm_bad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			var pm_keep := {}
			for pk in ["ar_mode", "surface", "ar_background", "scene", "pass_curtain"]:
				pm_keep[pk] = Game.get_s(pk)
			Game.settings["unlock_all"] = true
			Game.set_s("ar_mode", "studio")
			Game.set_s("surface", "desk")
			Game.set_s("ar_background", false)
			Game.set_s("pass_curtain", false)
			Game.set_s("scene", "lounge")
			stage.arcore.simulate = true
			stage.arcore.sim_floor = 0.0
			stage.arcore.sim_path = func(_t: float) -> Transform3D:
				return Transform3D(Basis.looking_at(Vector3(0, -0.45, -1.0), Vector3.UP), Vector3(0.3, 1.5, 1.2))
			var pm_btn := func(txt: String) -> Button:
				if _pause == null:
					return null
				for pb in _pause.find_children("*", "Button", true, false):
					if (pb as Button).text == txt and (pb as Control).is_visible_in_tree():
						return pb
				return null
			var pm_tap := func(txt: String) -> bool:
				var pb: Button = pm_btn.call(txt)
				if pb == null:
					return false
				if pb.toggle_mode:
					pb.button_pressed = true
				pb.pressed.emit()
				return true
			var pm_fits := func() -> bool:
				var vr := get_viewport().get_visible_rect()
				for pb in _pause.find_children("*", "Button", true, false):
					var rr: Rect2 = (pb as Control).get_global_rect()
					if (pb as Control).is_visible_in_tree() and not vr.grow(1.0).encloses(rr):
						print("    off screen: %s %s" % [(pb as Button).text, rr])
						return false
				return true
			start_match({"mode": "versus"})
			await _wait(1.4)
			var pm_balls: PackedVector2Array = game.sim.pos.duplicate()
			# ---- Studio
			pause()
			await _wait(0.6)
			pchk.call("Studio: the card offers View and Scene, nothing about a table to move",
				pm_btn.call("Studio (no camera)") != null and (pm_btn.call("Studio (no camera)") as Button).button_pressed and pm_btn.call("Desk (mini)") == null
				and pm_btn.call("Move / raise / lower table") == null and pm_btn.call("Place the table again") == null and _pause.find_child("SceneNext", true, false) != null)
			pchk.call("Studio: every button of the pause menu is on the screen", pm_fits.call())
			(_pause.find_child("SceneNext", true, false) as Button).pressed.emit()
			await _wait(0.8)
			var sc1 := str(Game.get_s("scene"))
			pchk.call("Scene arrow -> the next scene, shown at once behind the menu", sc1 != "lounge" and str((stage.get("_scene") as Dictionary).get("id", "")) == sc1, sc1)
			(_pause.find_child("ScenePrev", true, false) as Button).pressed.emit()
			(_pause.find_child("ScenePrev", true, false) as Button).pressed.emit()
			await _wait(0.8)
			var sc2 := str(Game.get_s("scene"))
			pchk.call("... and the arrows go round both ways", sc2 != sc1 and sc2 != "lounge" and str((stage.get("_scene") as Dictionary).get("id", "")) == sc2, sc2)
			await _shot(dir, "pause_studio")
			# ---- to AR in the middle of the match
			pm_tap.call("AR (walk around)")
			await _wait(1.0)
			var arp: Control = hud.get("_ar_panel")
			pchk.call("View -> AR: the menu closes and the table is to be put down", _pause == null and stage.mode == Stage.Mode.WORLD_AR and not stage.placed and arp.visible and Game.get_s("ar_mode") == "auto")
			pchk.call("... the balls are where they were", game.sim.pos == pm_balls)
			var ck0: float = game.clocks[game.current]
			await _wait(1.2)
			pchk.call("... the clock waits and the cue is off while the table is not there", is_equal_approx(game.clocks[game.current], ck0) and not game.control.enabled, "%.2f -> %.2f" % [ck0, game.clocks[game.current]])
			await _shot(dir, "pause_to_ar")
			stage.place_table()
			await _wait(1.2)
			pchk.call("table placed -> play goes on: clock runs, cue is back", game.clocks[game.current] < ck0 - 0.5 and game.control.enabled and not arp.visible, "%.2f" % game.clocks[game.current])
			# ---- AR
			pause()
			await _wait(0.6)
			pchk.call("AR: the card offers View, Surface, moving the table, placing it again and the scene background",
				(pm_btn.call("AR (walk around)") as Button).button_pressed and pm_btn.call("Desk (mini)") != null and pm_btn.call("Move / raise / lower table") != null
				and pm_btn.call("Place the table again") != null and pm_btn.call("Scene background in AR") != null and _pause.find_child("SceneNext", true, false) == null)
			var sc_desk: float = stage.get("_ar_scale")
			pm_tap.call("Floor (life-size)")
			await _wait(0.5)
			pchk.call("Surface -> life-size at once", Game.get_s("surface") == "floor" and float(stage.get("_ar_scale")) > sc_desk * 2.0, "%.2f -> %.2f" % [sc_desk, float(stage.get("_ar_scale"))])
			(pm_btn.call("Scene background in AR") as Button).button_pressed = true
			await _wait(0.6)
			pchk.call("Scene background on -> a scene round the table and the Scene arrows appear", stage.ar_background_on() and (stage.get("_room") as Node3D).visible and _pause.find_child("SceneNext", true, false) != null)
			pchk.call("AR: every button of the pause menu is on the screen", pm_fits.call())
			var as0: String = stage.ar_scene_id()
			(_pause.find_child("SceneNext", true, false) as Button).pressed.emit()
			await _wait(0.8)
			var as1: String = stage.ar_scene_id()
			pchk.call("Scene arrow in AR -> another scene round the table", as1 != as0 and as1 != "" and str((stage.get("_scene") as Dictionary).get("id", "")) == as1 and int(Catalog.find(Catalog.SCENES, as1).get("sky", 0)) != 0, "%s -> %s" % [as0, as1])
			await _shot(dir, "pause_ar")
			pm_tap.call("Place the table again")
			await _wait(0.8)
			pchk.call("Place the table again -> menu closes, the table is to be put down afresh", _pause == null and not stage.placed and arp.visible and not game.control.enabled)
			stage.place_table()
			await _wait(0.8)
			pause()
			await _wait(0.5)
			pm_tap.call("Move / raise / lower table")
			await _wait(0.6)
			var adj: Control = hud.get("_adjust_panel")
			pchk.call("Move / raise / lower table -> menu closes, the table can be dragged", _pause == null and adj.visible and stage.adjusting)
			await _shot(dir, "pause_move")
			# ---- back to the Studio, while the table is still being moved
			pause()
			await _wait(0.5)
			pm_tap.call("Studio (no camera)")
			await _wait(1.0)
			pchk.call("View -> Studio: at once, the menu stays, the AR choices are gone", _pause != null and stage.mode == Stage.Mode.STUDIO and Game.get_s("ar_mode") == "studio"
				and pm_btn.call("Desk (mini)") == null and pm_btn.call("Place the table again") == null and (pm_btn.call("Studio (no camera)") as Button).button_pressed)
			pchk.call("... the move panel is closed and the balls are still where they were", not adj.visible and not stage.adjusting and game.sim.pos == pm_balls)
			pchk.call("... and the Studio shows the scene chosen for it", str((stage.get("_scene") as Dictionary).get("id", "")) == sc2, str((stage.get("_scene") as Dictionary).get("id", "")))
			resume()
			await _wait(0.8)
			pchk.call("Resume -> the cue is live", game.control.enabled and game.state == PoolGame.State.AIM)
			await _shot(dir, "pause_back_in_studio")
			_end_match()
			stage.arcore.simulate = false
			for pk in pm_keep.keys():
				Game.set_s(pk, pm_keep[pk])
			Game.settings["unlock_all"] = false
			go("menu")
			stage.set_mode(Stage.Mode.STUDIO)
			print("PAUSEMENU %s %s" % ["PASS" if pm_bad.is_empty() else "FAIL", str(pm_bad)])
		"drawer":
			# the gear drawer: change the cue, table and ball set in the middle of a match
			var dbad: Array = []
			var dchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					dbad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			var d_keep := {}
			for gk in Game.GEAR_KEYS.values():
				d_keep[gk] = Game.get_s(gk)
			var d_all = Game.settings.get("unlock_all")
			Game.set_s("ar_mode", "studio")
			Game.set_s("cue_skin", "cue_emerald_classic")
			Game.set_s("table_style", "emerald")
			Game.set_s("ball_set", "balls")
			Game.settings["unlock_all"] = true
			for darg in OS.get_cmdline_user_args():
				if darg.begins_with("--drawer-lang="):
					Loc.set_language(darg.substr(14))
			start_match({"mode": "versus", "vs_ai": true})
			await _wait(1.6)
			var gbtn: Button = hud.find_child("GearButton", true, false)
			dchk.call("the match's right-hand column has the gear button", gbtn != null and gbtn.is_visible_in_tree())
			var balls_before: PackedVector2Array = game.sim.pos.duplicate()
			var turn_before: int = game.current
			gbtn.pressed.emit()
			await _wait(0.6)
			var dr: Control = hud.find_child("GearDrawer", true, false)
			var dp: Control = dr.find_child("GearDrawerPanel", true, false) if dr else null
			var vr := get_viewport().get_visible_rect()
			dchk.call("it opens a drawer on the right, inside the screen", dr != null and dp != null and vr.grow(1.0).encloses(dp.get_global_rect()) and dp.get_global_rect().end.x > vr.size.x - 40.0,
				str(dp.get_global_rect()) if dp else "")
			dchk.call("... and the cue is held while it is open", not game.control.enabled)
			var n_cues := 0
			for tn in dr.find_children("Drawer_cue_*", "Button", true, false):
				n_cues += 1
			dchk.call("Cues: every cue the player owns (all 49 with unlock-all)", n_cues == Catalog.CUES.size(), str(n_cues))
			await _shot(dir, "drawer_cues")
			(dr.find_child("Drawer_cue_cue_dragon_c", true, false) as Button).button_down.emit()
			(dr.find_child("Drawer_cue_cue_dragon_c", true, false) as Button).pressed.emit()
			await _wait(0.5)
			dchk.call("tap a cue -> it is in the player's hand at once", Game.get_s("cue_skin") == "cue_dragon_c" and game.cue_view.skin == "cue_dragon_c", game.cue_view.skin)
			(dr.find_child("DrawerTab_table", true, false) as Button).pressed.emit()
			await _wait(0.4)
			var dt: Button = dr.find_child("Drawer_table_galaxy", true, false)
			dt.button_down.emit()
			dt.pressed.emit()
			await _wait(1.0)
			dchk.call("Tables tab, tap Galaxy -> the table is rebuilt in that look", Game.get_s("table_style") == "galaxy" and str(stage.table_view.style.get("id", "")) == "galaxy")
			await _shot(dir, "drawer_tables")
			(dr.find_child("DrawerTab_balls", true, false) as Button).pressed.emit()
			await _wait(0.4)
			var db: Button = dr.find_child("Drawer_balls_vortex", true, false)
			db.button_down.emit()
			db.pressed.emit()
			await _wait(0.8)
			var placed_ok := true
			for bi in game.views.size():
				if game.sim.st[bi] != PoolSim.ST_POCKETED and game.views[bi].position.distance_to(Vector3(game.sim.pos[bi].x, game.views[bi].position.y, game.sim.pos[bi].y)) > 0.001:
					placed_ok = false
			dchk.call("Ball sets tab, tap Emerald Vortex -> new balls, each exactly where its ball is", Game.get_s("ball_set") == "vortex" and game.views.size() == game.sim.n and placed_ok)
			await _shot(dir, "drawer_balls")
			dchk.call("the match is untouched: same balls, same turn", game.sim.pos == balls_before and game.current == turn_before)
			# a tap outside the drawer closes it
			var catch_ev := InputEventMouseButton.new()
			catch_ev.button_index = MOUSE_BUTTON_LEFT
			catch_ev.pressed = true
			(dr.get_child(0) as Control).gui_input.emit(catch_ev)
			await _wait(0.6)
			dchk.call("a tap outside closes it and the cue comes back", hud.find_child("GearDrawer", true, false) == null and game.control.enabled)
			await _shot(dir, "drawer_after")
			# a developer option (Randy, 11 Nov 2026: not there mid-game once the game is released)
			Game.set_s("gear_drawer", false)
			await _wait(0.2)
			dchk.call("developer option off -> no gear button in the match", not gbtn.is_visible_in_tree())
			Game.set_s("gear_drawer", true)
			await _wait(0.2)
			dchk.call("... on again -> the button is back", gbtn.is_visible_in_tree())
			# the CPU plays with its own cue: seen on its turn
			dchk.call("the CPU has its own cue, not the player's", game.cue_skins[1] in AIPlayer.CUES[game.ai_level] and game.cue_skins[1] != game.cue_skins[0], str(game.cue_skins))
			if game.state == PoolGame.State.BALL_IN_HAND:
				game.confirm_cue_placement()
			game.fire(PI * 0.5, 0.12, Vector2.ZERO, 0.0)
			var cpu_t := 0.0
			while cpu_t < 12.0 and not (game.current == 1 and game.state == PoolGame.State.AI_THINK and game.cue_view.visible):
				await _wait(0.1)
				cpu_t += 0.1
			await _wait(0.8)
			dchk.call("on the CPU's turn its cue is the one at the table", game.cue_view.skin == game.cue_skins[1], game.cue_view.skin)
			await _shot(dir, "cpu_cue")
			_end_match()
			for gk in d_keep.keys():
				Game.set_s(gk, d_keep[gk])
			if d_all == null:
				Game.settings.erase("unlock_all")
			else:
				Game.settings["unlock_all"] = d_all
			go("menu")
			print("DRAWER %s %s" % ["PASS" if dbad.is_empty() else "FAIL", str(dbad)])
		"pockets":
			# close-ups of a corner and a side pocket and of the cushions, in the Studio light and the AR light
			Game.set_s("ar_mode", "studio")
			Game.set_s("reduced_motion", true)
			start_match({"mode": "practice"})
			await _wait(1.4)
			hud.visible = false
			var gq: PoolSim = game.sim
			for bi in gq.n:
				if bi != game.cue_index():
					gq.pos[bi] = Vector2(0.15 + 0.065 * (bi % 5), -0.2 + 0.065 * int(bi / 5))
					game.views[bi].place(gq.pos[bi])
			var tg := stage.table_view.geom
			var corner: Dictionary = {}
			var side: Dictionary = {}
			for pk in tg.pockets:
				var hm: Vector2 = pk["hole"]
				if pk["corner"] and hm.x > 0 and hm.y > 0:
					corner = pk
				if not pk["corner"] and hm.y > 0:
					side = pk
			var rx := stage.table_root.global_transform
			var looks := [["top_corner", corner, 72.0, 0.42, 0.0], ["low_corner", corner, 24.0, 0.55, 0.0],
				["top_side", side, 72.0, 0.42, 0.0], ["low_side", side, 24.0, 0.55, 0.0],
				["player", {}, 20.0, 1.7, 0.0]]
			for ar_look in [false, true]:
				stage.warm_ar_look(ar_look)
				for lk in looks:
					var pkd: Dictionary = lk[1]
					var tgt := rx * Vector3.ZERO
					var yaw := 0.0
					if not pkd.is_empty():
						var hh: Vector2 = pkd["hole"]
						var ax: Vector2 = pkd["axis"]
						tgt = rx * Vector3(hh.x, 0.0, hh.y)
						yaw = atan2(-ax.x, -ax.y)       # the camera on the table side of the pocket, looking at it
					stage.set("_manual", true)
					stage.set("_want_pitch", deg_to_rad(float(lk[2])))
					stage.set("_want_dist", float(lk[3]))
					stage.set("_want_yaw", yaw)
					stage.set("_want_target", tgt)
					stage.call("_snap_orbit")
					await _wait(0.5)
					stage.call("_snap_orbit")
					await _shot(dir, "pk_%s_%s" % ["ar" if ar_look else "studio", lk[0]])
			stage.warm_ar_look(false)
			stage.reset_manual()
			hud.visible = true
			_end_match()
			Game.set_s("reduced_motion", false)
			go("menu")
			print("POCKETS DONE")
		"cushions":
			# every table's cushions and a corner pocket, Studio light and AR light, from a player's height
			Game.set_s("ar_mode", "studio")
			Game.set_s("reduced_motion", true)
			var keep_ts: String = Game.get_s("table_style")
			var only_t := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--tables="):
					only_t = a.substr(9)
			start_match({"mode": "practice"})
			await _wait(1.0)
			hud.visible = false
			for e in Catalog.TABLES:
				if only_t != "" and not (str(e["id"]) in only_t.split(",")):
					continue
				Game.set_s("table_style", e["id"])
				await _wait(0.3)
				var tg2 := stage.table_view.geom
				var cpk: Dictionary = {}
				for pk in tg2.pockets:
					if pk["corner"] and (pk["hole"] as Vector2).x > 0 and (pk["hole"] as Vector2).y > 0:
						cpk = pk
				var rx2 := stage.table_root.global_transform
				for ar_look in [false, true]:
					stage.warm_ar_look(ar_look)
					var hh2: Vector2 = cpk["hole"]
					var ax2: Vector2 = cpk["axis"]
					stage.set("_manual", true)
					stage.set("_want_pitch", deg_to_rad(16.0))
					stage.set("_want_dist", 0.9)
					stage.set("_want_yaw", atan2(-ax2.x, -ax2.y) + 0.35)
					stage.set("_want_target", rx2 * Vector3(hh2.x - ax2.x * 0.25, 0.0, hh2.y - ax2.y * 0.25))
					stage.call("_snap_orbit")
					await _wait(0.4)
					stage.call("_snap_orbit")
					await _shot(dir, "cu_%s_%s" % [e["id"], "ar" if ar_look else "studio"])
			stage.warm_ar_look(false)
			stage.reset_manual()
			hud.visible = true
			_end_match()
			Game.set_s("table_style", keep_ts)
			Game.set_s("reduced_motion", false)
			go("menu")
			print("CUSHIONS DONE")
		"feed":
			# v1.1.5: a card for every ball that drops (2 s each, stacking), and one when solids / stripes are decided
			var fbad: Array = []
			var fchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					fbad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			Game.set_s("ar_mode", "studio")
			start_match({"mode": "versus", "vs_ai": true})
			await _wait(1.6)
			var feed: PotFeed = hud.pot_feed()
			PotFeed.test_hold = true      # (the picture: this renderer is slow enough for 2 seconds to pass in a frame)
			game.ball_potted.emit(3, 0)
			await _wait(0.15)
			game.ball_potted.emit(11, 0)
			await _wait(0.15)
			game.ball_potted.emit(0, 0)
			await _wait(0.4)
			fchk.call("three balls drop: three cards, stacked", feed.count() == 3, "%d cards" % feed.count())
			var rects: Array = []
			for slot in feed.get_child(0).get_children():
				rects.append((slot.get_child(0) as Control).get_global_rect())
			var stacked: bool = rects.size() == 3 and rects[0].end.y <= rects[1].position.y + 1.0 and rects[1].end.y <= rects[2].position.y + 1.0
			fchk.call("... one under the other, the newest at the bottom", stacked)
			var vp := get_viewport().get_visible_rect()
			var chip_r: Rect2 = (hud.get("_scheme_chip") as Control).get_global_rect()
			var card_r: Rect2 = (hud.get("_cards")[0]["panel"] as Control).get_global_rect()
			var inside := true
			for r in rects:
				if not vp.encloses(r) or r.intersects(chip_r) or r.intersects(card_r):
					inside = false
			fchk.call("... on screen, clear of the player card and the cue-control chip", inside)
			# the table stops being open
			game.rules.groups = [EightBall.Group.SOLIDS, EightBall.Group.STRIPES]
			game.groups_set.emit()
			await _wait(0.45)
			fchk.call("groups decided: a card stacks under the balls", feed.count() == 4, "%d cards" % feed.count())
			# a break that drops seven at once: the oldest make way, the column never reaches the cue-control chip
			for nb in [1, 2, 4, 9, 10, 12, 13]:
				game.ball_potted.emit(nb, 0)
			await get_tree().process_frame
			var low := 0.0
			for slot in feed.get_child(0).get_children():
				low = maxf(low, (slot.get_child(0) as Control).get_global_rect().end.y)
			fchk.call("many at once: as many as fit, clear of the cue-control chip", feed.count() >= 3 and low < chip_r.position.y, "%d cards, bottom at %d (chip at %d)" % [feed.count(), low, chip_r.position.y])
			feed.clear()
			for nb in [3, 11, 0]:
				game.ball_potted.emit(nb, 0)
			game.groups_set.emit()
			await get_tree().process_frame
			await _shot(dir, "feed_cards")
			feed.clear()
			PotFeed.test_hold = false
			await get_tree().process_frame
			# lifetimes, on the game's own clock: a card shows, and 2 seconds after it came it has gone
			var gone_at := get_tree().create_timer(2.0 + 0.3)
			game.ball_potted.emit(5, 0)
			await get_tree().process_frame
			await get_tree().process_frame
			var shown: bool = feed.count() == 1 and gone_at.time_left > 0.3 and (feed.get_child(0).get_child(0).get_child(0) as Control).modulate.a > 0.5
			fchk.call("a card fades in at once", shown)
			while gone_at.time_left > 0.0:
				await get_tree().process_frame
			await get_tree().process_frame
			fchk.call("2 seconds after it came it has gone and its space closed up", feed.count() == 0, "%d cards" % feed.count())
			# a real shot: the break drops balls, a card for each ball that went down
			_end_match()
			start_match({"mode": "practice"})
			await _wait(1.4)
			feed = hud.pot_feed()
			var made := [0]
			game.ball_potted.connect(func(_n, _s): made[0] += 1)
			var tries := 0
			while made[0] == 0 and tries < 6:
				game.reset_rack()
				await _wait(0.3)
				game.fire(0.0, 1.0, Vector2.ZERO, 0.0)
				var tt := 0
				while game.state == PoolGame.State.ROLLING and tt < 400:
					await get_tree().process_frame
					tt += 1
				tries += 1
			fchk.call("a real break: a card for each ball that dropped", made[0] > 0, "%d balls in %d breaks" % [made[0], tries])
			_end_match()
			go("menu")
			print("FEED %s %s" % ["PASS" if fbad.is_empty() else "FAIL", str(fbad)])
		"freelook":
			# v1.1.5: the top view's free look (buttons, one-finger slide, pinch, never into the table)
			var lbad: Array = []
			var lchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					lbad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			Game.set_s("ar_mode", "studio")
			Game.set_s("control_scheme", "slingshot")
			start_match({"mode": "practice"})
			await _wait(1.4)
			var fbtn: Button = hud.get("_btn_free")
			lchk.call("not in the overview: no free-look button", not fbtn.visible)
			(hud.get("_btn_views")[2] as Button).pressed.emit()
			await _wait(0.8)
			lchk.call("top view: the free-look button is there", fbtn.visible)
			fbtn.pressed.emit()
			await _wait(0.3)
			var panel: Control = hud.get("_fl_panel")
			lchk.call("free look on: its buttons show", stage.free_look and panel.visible)
			lchk.call("... and the cue and its controls are put away (they sat where the buttons are)", not game.control.enabled)
			var d0: float = stage.get("_want_dist")
			var zin: Button = hud.free_look_button("plus")
			zin.button_down.emit()
			await _wait(0.5)
			zin.button_up.emit()
			var d1: float = stage.get("_want_dist")
			lchk.call("holding zoom in brings the camera closer", d1 < d0 * 0.8, "%.2f -> %.2f m" % [d0, d1])
			var y0: float = stage.get("_want_yaw")
			hud.free_look_button("chev_right").button_down.emit()
			await _wait(0.4)
			hud.free_look_button("chev_right").button_up.emit()
			lchk.call("turn right turns it", absf(angle_difference(y0, stage.get("_want_yaw"))) > deg_to_rad(15.0), "%.0f deg" % rad_to_deg(absf(angle_difference(y0, stage.get("_want_yaw")))))
			var p0: float = stage.get("_want_pitch")
			hud.free_look_button("chev_down").button_down.emit()
			await _wait(0.5)
			hud.free_look_button("chev_down").button_up.emit()
			lchk.call("tilt down lowers it", float(stage.get("_want_pitch")) < p0 - deg_to_rad(10.0), "%.0f -> %.0f deg" % [rad_to_deg(p0), rad_to_deg(float(stage.get("_want_pitch")))])
			await _wait(0.6)
			await _shot(dir, "freelook_turned")
			# one finger slides the camera at its height
			var tgt0: Vector3 = stage.get("_want_target")
			var cy0: float = stage.studio_cam.global_position.y
			var mid := get_viewport().get_visible_rect().size * 0.5
			await _touch(0, mid, true)
			for k in 10:
				await _drag(0, mid + Vector2(-24.0 * (k + 1), 0))
			await _touch(0, mid + Vector2(-240, 0), false)
			await _wait(0.6)
			var tgt1: Vector3 = stage.get("_want_target")
			lchk.call("a one-finger drag slides the view", tgt0.distance_to(tgt1) > 0.05 and absf(tgt1.y - tgt0.y) < 0.001, "moved %.2f m" % tgt0.distance_to(tgt1))
			lchk.call("... at the same height", absf(stage.studio_cam.global_position.y - cy0) < 0.03, "%.3f -> %.3f m" % [cy0, stage.studio_cam.global_position.y])
			lchk.call("... and the cue did not take it as a shot", game.state == PoolGame.State.AIM and game.shots_total == 0)
			# pinch: fingers together zoom in, apart zoom out (Randy)
			var dp0: float = stage.get("_want_dist")
			await _touch(0, mid + Vector2(-300, 0), true)
			await _touch(1, mid + Vector2(300, 0), true)
			for k in 8:
				await _drag(0, mid + Vector2(-300 + 25 * (k + 1), 0))
				await _drag(1, mid + Vector2(300 - 25 * (k + 1), 0))
			await _touch(0, mid + Vector2(-100, 0), false)
			await _touch(1, mid + Vector2(100, 0), false)
			var dp1: float = stage.get("_want_dist")
			lchk.call("pinching together zooms in", dp1 < dp0 * 0.8, "%.2f -> %.2f m" % [dp0, dp1])
			await _touch(0, mid + Vector2(-100, 0), true)
			await _touch(1, mid + Vector2(100, 0), true)
			for k in 8:
				await _drag(0, mid + Vector2(-100 - 25 * (k + 1), 0))
				await _drag(1, mid + Vector2(100 + 25 * (k + 1), 0))
			await _touch(0, mid + Vector2(-300, 0), false)
			await _touch(1, mid + Vector2(300, 0), false)
			var dp2: float = stage.get("_want_dist")
			lchk.call("pinching apart zooms out", dp2 > dp1 * 1.5, "%.2f -> %.2f m" % [dp1, dp2])
			# the worst it can be asked: all the way in, all the way down, slid to every edge and corner
			var worst := INF
			var inside_table := false
			var half: Vector2 = stage.table_view.outer_size() * 0.5
			for slide in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, -1)]:
				stage.free_look_step(0.0, -PI, 0.01)
				stage.set("_want_target", stage.table_root.global_transform * Vector3(slide.x * (half.x + 1.0), 0.0, slide.y * (half.y + 1.0)))
				stage.free_look_step(0.3, -PI, 0.01)
				for k in 12:
					await get_tree().process_frame
				stage.call("_snap_orbit")
				var cl: Vector3 = stage.table_root.global_transform.affine_inverse() * stage.studio_cam.global_position
				var over: bool = absf(cl.x) < half.x and absf(cl.y) >= -0.9 and absf(cl.z) < half.y
				if over:
					worst = minf(worst, cl.y)
				if absf(cl.x) < half.x and absf(cl.z) < half.y and cl.y < stage.table_view.rail_height + 0.01:
					inside_table = true
			lchk.call("all the way in and down, at every edge: the camera never goes into the table", not inside_table and (worst == INF or worst >= Stage.FL_CLEAR - 0.005), "lowest over the table %.3f m above the cloth" % worst)
			await _shot(dir, "freelook_low")
			hud.free_look_button("recenter").pressed.emit()
			await _wait(0.8)
			lchk.call("the middle button frames the whole table again", absf(float(stage.get("_want_pitch")) - deg_to_rad(88.0)) < 0.01 and stage.free_look)
			await _shot(dir, "freelook_panel")
			fbtn.pressed.emit()
			await _wait(0.3)
			lchk.call("the eye again: free look off, its buttons go", not stage.free_look and not panel.visible)
			lchk.call("... and the cue is back", game.control.enabled)
			fbtn.pressed.emit()
			await _wait(0.2)
			(hud.get("_btn_views")[0] as Button).pressed.emit()
			await _wait(0.3)
			lchk.call("another view: free look ends and the button goes", not stage.free_look and not fbtn.visible and not panel.visible)
			_end_match()
			go("menu")
			print("FREELOOK %s %s" % ["PASS" if lbad.is_empty() else "FAIL", str(lbad)])
		"lang_feed":
			# v1.1.5's new texts in every language, quickly: the potted-ball cards, the groups card, free look and its hint
			# (the full "lang" audit covers them too, but takes hours on the software renderer)
			var lf_langs := Loc.codes()
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--langs="):
					lf_langs = Array(arg.substr(8).split(","))
			var lf_problems := 0
			Game.set_s("ar_mode", "studio")
			Game.set_s("control_scheme", "pro_dial")
			Game.set_s("reduced_motion", true)
			PotFeed.test_hold = true
			for code in lf_langs:
				Loc.set_language(code)
				start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
				await _wait(0.6)
				game.ball_potted.emit(12, 0)
				game.ball_potted.emit(3, 1)
				game.ball_potted.emit(0, 1)
				game.rules.groups = [EightBall.Group.STRIPES, EightBall.Group.SOLIDS]
				game.groups_set.emit()
				(hud.get("_btn_views")[2] as Button).pressed.emit()
				await _wait(0.2)
				stage.set_free_look(true)
				await _wait(0.4)
				lf_problems += _audit_text(code, "pot_feed_free_look")
				var lpf: PotFeed = hud.pot_feed()
				var chip: Rect2 = (hud.get("_scheme_chip") as Control).get_global_rect()
				for slot in lpf.get_child(0).get_children():
					var cr: Rect2 = (slot.get_child(0) as Control).get_global_rect()
					if not get_viewport().get_visible_rect().encloses(cr) or cr.size.x > 560.0 or cr.intersects(chip):
						lf_problems += 1
						print("  TOO WIDE / OFF SCREEN [%s/pot_feed] %s" % [code, cr])
				var hint_l: Label = hud.get("_hint_lbl")
				if not get_viewport().get_visible_rect().encloses(hint_l.get_global_rect()):
					lf_problems += 1
					print("  OFF SCREEN [%s/free_look_hint] %s" % [code, hint_l.get_global_rect()])
				await _shot(dir, "lang_%s_feed" % code)
				stage.set_free_look(false)
				_end_match()
			PotFeed.test_hold = false
			Game.set_s("reduced_motion", false)
			Loc.set_language("auto")
			go("menu")
			print("LANG_FEED %d problems in %d languages" % [lf_problems, lf_langs.size()])
		"lang_ads":
			# v1.1.7's "Open 4 Hours Faster With Ad" (the XP chest) and the package page's advert button in every language
			var la_langs := Loc.codes()
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--langs="):
					la_langs = Array(arg.substr(8).split(","))
			var la_problems := 0
			var la_keep: Dictionary = Game.progress.duplicate(true)
			var la_stand = Game.settings.get("ad_standins")
			Game.set_s("ad_standins", true)
			Game.progress = Game.fresh_progress()
			Game.add_xp(XP.total_for(30))
			Game.progress["chest_from"] = Game.now() - 600
			Game.progress["chest_at"] = Game.now() - 600 + XP.CHEST_WAIT
			Game.progress["packages"] = [30]
			Game.progress["pk_time"] = {"30": Game.now() - 60}
			for code in la_langs:
				Loc.set_language(code)
				for page in ["chest", "packages", "pk1", "pk3", "pk4", "pk5"]:
					# pk1..pk5: the package of that rarity in front, so each package's (translated) name is checked
					if page.begins_with("pk"):
						var lv: int = [0, 1, 27, 53, 79, 105][int(page.substr(2))]
						Game.progress["packages"] = [lv]
						Game.progress["pk_time"] = {str(lv): Game.now() - 60}
					_stack.clear()
					go("chest" if page == "chest" else "packages")
					await _wait(0.8)
					var ab: Button = _screen.find_child("ChestAdButton" if page == "chest" else "PackageAdButton", true, false)
					if page.begins_with("pk"):
						var pr := int(page.substr(2))
						var t_ok := cbtn_text_on(_screen, L.t(PackageView.NAMES[pr]))
						if not t_ok:
							la_problems += 1
							print("  PACKAGE NAME NOT SHOWN TRANSLATED [%s/%s] %s" % [code, page, L.t(PackageView.NAMES[pr])])
						la_problems += _audit_text(code, "ad_" + page)
						if code in ["de", "pl", "ta", "ja"]:
							await _shot(dir, "lang_%s_%s" % [code, page])
						continue
					la_problems += _audit_text(code, "ad_" + page)
					# (the chest's button is set already translated; the package page's is translated by the engine as drawn)
					var want_txt := L.t("Open 4 Hours Faster With Ad") if page == "chest" else "Watch an ad to open it now"
					var ok_btn := ab != null and ab.visible and ab.text == want_txt and get_viewport().get_visible_rect().encloses(ab.get_global_rect())
					if not ok_btn:
						la_problems += 1
						print("  AD BUTTON MISSING / OFF SCREEN [%s/%s] %s" % [code, page, ab.get_global_rect() if ab else "none"])
					if code in ["en", "de", "ta", "ar"]:
						await _shot(dir, "lang_%s_ad_%s" % [code, page])
			Game.progress = la_keep
			if la_stand == null:
				Game.settings.erase("ad_standins")
			else:
				Game.set_s("ad_standins", la_stand)
			Loc.set_language("auto")
			_stack.clear()
			go("menu")
			print("LANG_ADS %s: %d problems in %d languages" % ["PASS" if la_problems == 0 else "FAIL", la_problems, la_langs.size()])
		"cueballs":
			# the stick rises over a ball in its way, keeps the player's own height, and refuses spin into a ball
			var qbad: Array = []
			var qchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					qbad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			Game.set_s("ar_mode", "studio")
			Game.set_s("control_scheme", "ghost_target")
			start_match({"mode": "practice"})
			await _wait(1.4)
			var gs: PoolSim = game.sim
			var ci: int = game.cue_index()
			# the cue ball in the open; one ball 13 cm behind it on the line the stick lies along now, the rest far off
			var ctl = game.control
			var yaw0: float = ctl.yaw
			var cpos := Vector2(0.3, 0.05)
			gs.pos[ci] = cpos
			var placed := 0
			var blocker := -1
			for bi in gs.n:
				if bi == ci:
					continue
				if placed == 0:
					blocker = bi
				gs.pos[bi] = Vector2(0.95 + 0.06 * (placed % 4), -0.4 + 0.06 * int(placed / 4))
				placed += 1
			for bi in gs.n:
				game.views[bi].place(gs.pos[bi])
			ctl.elevation = 0.0
			ctl.offset = Vector2.ZERO
			await _wait(0.6)
			# the aim settles for the new cue ball spot; then the blocker goes behind it, on the stick's line
			yaw0 = ctl.yaw
			gs.pos[blocker] = cpos - Vector2(cos(yaw0), sin(yaw0)) * 0.13
			game.views[blocker].place(gs.pos[blocker])
			await _wait(0.5)
			print("    aim %.3f -> %.3f" % [yaw0, ctl.yaw])
			yaw0 = ctl.yaw
			var e_over: float = game.cue_elevation()
			var el_sl = hud.get("_elev")
			qchk.call("a ball behind the cue ball: the stick rises over it", e_over > 8.0 and game.cue_on_ball(yaw0, Vector2.ZERO) and el_sl.on_ball, "%.1f deg" % e_over)
			qchk.call("... and is never inside it", gs.balls_gap(gs.pos[ci], yaw0, Vector2.ZERO, e_over) >= 0.0, "%.1f mm" % (gs.balls_gap(gs.pos[ci], yaw0, Vector2.ZERO, e_over) * 1000.0))
			await _shot(dir, "cue_over_ball")
			var yaw_clear := yaw0 + PI * 0.5            # a quarter of the way round the cue ball: nothing behind
			var e_clear: float = maxf(ctl.elevation, game.min_elevation(yaw_clear, ctl.offset))
			qchk.call("circling round to a clear spot: the stick comes back down", e_clear < 4.0 and not game.cue_on_ball(yaw_clear, Vector2.ZERO), "%.1f deg" % e_clear)
			# the player raises the stick above the lift: that height is theirs and is kept everywhere
			el_sl.changed.emit(25.0)
			el_sl.set_value(25.0)
			await _wait(0.3)
			var e_up: float = game.cue_elevation()
			var e_up_clear: float = maxf(ctl.elevation, game.min_elevation(yaw_clear, ctl.offset))
			qchk.call("raised to 25 deg over the ball, then circled to a clear spot: still 25 deg", is_equal_approx(e_up, 25.0) and is_equal_approx(e_up_clear, 25.0), "%.1f / %.1f" % [e_up, e_up_clear])
			el_sl.set_value(0.0)
			ctl.elevation = 0.0
			await _wait(0.3)
			# spin: a lower tip at this height would put the stick into the ball -> refused; a higher one is fine
			var sp = hud.get("_spin")
			sp.set_spin(Vector2(0, -0.45))
			sp.changed.emit(Vector2(0, -0.45))
			await _wait(0.2)
			qchk.call("moving the tip low (draw) would push the stick into the ball: refused, the pad goes back", ctl.offset == Vector2.ZERO and sp.offset == Vector2.ZERO, str(ctl.offset))
			sp.set_spin(Vector2(0, 0.4))
			sp.changed.emit(Vector2(0, 0.4))
			await _wait(0.2)
			qchk.call("moving the tip high clears: allowed", ctl.offset == Vector2(0, 0.4))
			await _shot(dir, "cue_over_ball_top")
			# with more height first, the low tip clears and is allowed
			el_sl.set_value(40.0)
			el_sl.changed.emit(40.0)
			sp.set_spin(Vector2(0, -0.45))
			sp.changed.emit(Vector2(0, -0.45))
			await _wait(0.2)
			qchk.call("raised to 40 deg first: now the low tip clears and is allowed", ctl.offset == Vector2(0, -0.45))
			# the developer switch off: the stick ignores balls again
			Game.set_s("cue_over_balls", false)
			el_sl.set_value(0.0)
			ctl.elevation = 0.0
			ctl.offset = Vector2.ZERO
			await _wait(0.3)
			qchk.call("developer switch off: the stick lies flat through the ball, as before", game.cue_elevation() < 4.0, "%.1f deg" % game.cue_elevation())
			Game.set_s("cue_over_balls", true)
			_end_match()
			Game.set_s("control_scheme", "slingshot")
			go("menu")
			print("CUEBALLS %s %s" % ["PASS" if qbad.is_empty() else "FAIL", str(qbad)])
		"chest":
			# the XP chest, the package waits, the rewarded-advert offers and the advert after every score screen
			var cbad: Array = []
			var cchk := func(label: String, good: bool, detail := "") -> void:
				if not good:
					cbad.append(label)
				print("  %s  %s  %s" % ["ok  " if good else "FAIL", label, detail])
			var c_keep: Dictionary = Game.progress.duplicate(true)
			var c_all = Game.settings.get("unlock_all")
			Game.set_s("ar_mode", "studio")
			Game.set_s("ad_standins", false)      # starts as a player has it: adverts off, no stand-ins
			Game.progress = Game.fresh_progress()
			Game.add_xp(XP.total_for(9) + 80)       # the chest's half level (50 XP) passes level 10
			Game.progress["pk_time"] = {}
			Game.progress_changed.emit()
			var ad_continue := func() -> bool:
				for k in 60:
					await _wait(0.1)
					for bn in Ads.find_children("*", "Button", true, false):
						if (bn as Button).text == L.t("Continue") and not (bn as Button).disabled and (bn as Control).is_visible_in_tree():
							(bn as Button).pressed.emit()
							return true
				return false
			var cbtn := func(where: Node, txt: String) -> Button:
				for bn in where.find_children("*", "Button", true, false):
					if (bn as Button).text == txt and (bn as Control).is_visible_in_tree():
						return bn
				return null
			# ---- the menu: a new player's chest is ready
			_stack.clear()
			go("menu")
			await _wait(1.6)
			var cb: Control = _screen.find_child("XpChest", true, false)
			var ct: Label = _screen.find_child("ChestTime", true, false)
			cchk.call("menu: the XP chest sits in the corner and is ready for a new player", cb != null and ct != null and ct.text == L.t("Ready!") and _screen.find_child("DailyGift", true, false) == null)
			await _shot(dir, "ch_menu_ready")
			# ---- its page; open it
			go("chest")
			await _wait(1.2)
			cchk.call("chest page: ready, +%d XP named, no advert button" % Game.chest_xp(), (_screen.find_child("OpenChest", true, false) as Control).visible and not (_screen.find_child("ChestAdButton", true, false) as Control).visible)
			await _shot(dir, "ch_page_ready")
			var cx0 := Game.xp()
			var c_amount := Game.chest_xp()
			_screen.call("_open")
			await _wait(0.75)
			await _shot(dir, "ch_opening")
			await _wait(1.0)
			var rev: Node = null
			for n in _screen.find_children("*", "", true, false):
				if n is RewardScreens.XpReveal:
					rev = n
			cchk.call("opening -> the reward card: +%d XP (half of level 9's %d), the XP is banked, the next chest is 6 hours away" % [c_amount, XP.need(9)], rev != null and c_amount == 50 and Game.xp() == cx0 + c_amount and Game.chest_left() > XP.CHEST_WAIT - 60,
				"%d -> %d, %s" % [cx0, Game.xp(), XP.clock(Game.chest_left())])
			await _wait(1.2)
			var lvup: Label = rev.find_child("ChestLevelUp", true, false) if rev else null
			cchk.call("... the bar fills over the next level and LEVEL UP shows (with its package)", lvup != null and lvup.modulate.a > 0.9 and Game.level() == 10 and 10 in Game.packages(), lvup.text if lvup else "")
			await _shot(dir, "ch_reveal")
			(cbtn.call(rev, L.t("Done")) as Button).pressed.emit()
			await _wait(1.0)
			# ---- waiting; with adverts off there is no advert offer, only the time
			cchk.call("waiting, adverts off: the time is shown and no advert is offered", not (_screen.find_child("OpenChest", true, false) as Control).visible
				and not (_screen.find_child("ChestAdButton", true, false) as Control).visible and (_screen.find_child("ChestStatus", true, false) as Label).text.begins_with(L.t("Ready in %s").get_slice("%s", 0)))
			# ---- with the advert stand-ins (what players will see once adverts are on)
			Game.set_s("ad_standins", true)
			Game.clock_shift = 3600
			_screen.call("_refresh")
			await _wait(0.4)
			var adb: Button = _screen.find_child("ChestAdButton", true, false)
			cchk.call("an hour later: the button 'Open 4 Hours Faster With Ad' is offered (5 hours left)", adb.visible and adb.text == L.t("Open 4 Hours Faster With Ad")
				and Game.chest_left() > 5 * 3600 - 300, adb.text)
			await _shot(dir, "ch_page_waiting")
			# the player closes the advert early: no reward
			_screen.call("_watch")
			await _wait(0.5)
			await _shot(dir, "ch_ad_standin")
			var quit_b: Button = cbtn.call(Ads, L.t("Close without the reward"))
			cchk.call("the rewarded stand-in can be closed early", quit_b != null)
			quit_b.pressed.emit()
			await _wait(0.4)
			cchk.call("... closed early: nothing changes (about 5 hours left, still offered)", Game.chest_left() > 5 * 3600 - 300 and Game.chest_left() <= 5 * 3600 and Game.can_cut_chest(), XP.clock(Game.chest_left()))
			# watched to the end: 4 hours sooner, ready 2 hours after opening (about 1 hour left), once per wait
			_screen.call("_watch")
			await ad_continue.call()
			await _wait(0.5)
			cchk.call("... watched: 4 hours sooner, ready 2 hours after it was opened (about 1 hour left), no second offer",
				int(Game.progress["chest_at"]) == int(Game.progress["chest_from"]) + XP.CHEST_WAIT_AD and Game.chest_left() > 0 and not (_screen.find_child("ChestAdButton", true, false) as Control).visible, XP.clock(Game.chest_left()))
			back()
			await _wait(0.8)
			var ct2: Label = _screen.find_child("ChestTime", true, false)
			cchk.call("menu: the chest keeps still and counts down", ct2 != null and ct2.text.length() >= 4 and ct2.text.contains(":") and ct2.text != L.t("Ready!") and Game.chest_left() < 3600, ct2.text if ct2 else "")
			# ---- packages: waiting, then the advert offer
			Game.progress["packages"] = [10]                                          # only the one just earned
			(Game.progress["pk_time"] as Dictionary)["10"] = Game.now() - 60        # a minute ago
			go("packages")
			await _wait(1.2)
			var pw: Label = _screen.find_child("UnlockTime", true, false)
			var pab: Button = _screen.find_child("PackageAdButton", true, false)
			cchk.call("packages: a common package earned a minute ago unlocks by itself in 29 minutes; the advert opens it now",
				pw.text.begins_with(L.t("Unlocks by itself in %s").get_slice("%s", 0) + "2") and Game.package_left(10) > 1500 and pab.visible and pab.text == L.t("Watch an ad to open it now") and cbtn.call(_screen, L.t("Open package")) == null, pw.text)
			await _shot(dir, "ch_packages_waiting")
			_screen.call("_open", false, true)
			await ad_continue.call()
			await _wait(1.8)
			var prev: Node = null
			for n in _screen.find_children("*", "", true, false):
				if n is RewardScreens.Reveal:
					prev = n
			cchk.call("... after the advert it opens at once", prev != null and Game.packages().is_empty())
			if prev:
				prev.closed.emit(false)
				prev.queue_free()
			await _wait(0.5)
			Game.set_s("ad_standins", false)
			# ---- Practice: a cleared rack is a natural break, and the advert follows its screen
			Game.set_s("ad_standins", true)
			start_match({"mode": "practice"})
			await _wait(1.2)
			for bi in game.sim.pos.size():
				if bi != game.cue_index():
					game.sim.st[bi] = PoolSim.ST_POCKETED
			game.call("_resolve_practice")
			await _wait(1.4)
			cchk.call("Practice: the last ball down -> the rack-cleared screen", _results is Overlays.RackCleared and game.state == PoolGame.State.OVER)
			await _shot(dir, "ch_rack_cleared")
			(cbtn.call(_results, L.t("Rack again")) as Button).pressed.emit()
			await _wait(0.6)
			var ad_up := Ads.find_children("*", "Button", true, false).size() > 0
			cchk.call("Rack again -> the between-matches advert first", ad_up)
			await ad_continue.call()
			await _wait(1.0)
			var on_table := 0
			for bi in game.sim.pos.size():
				if game.sim.st[bi] != PoolSim.ST_POCKETED:
					on_table += 1
			cchk.call("... then a fresh rack and the cue is live", _results == null and on_table == 16 and game.state == PoolGame.State.AIM, "%d balls" % on_table)
			_end_match()
			# ---- a versus match: the advert follows its score screen too
			start_match({"mode": "versus", "vs_ai": true})
			await _wait(1.0)
			game.call("_finish", 0, "Sank the 8!")
			await _wait(1.6)
			cchk.call("VS CPU: the score screen comes up and an advert is due", _results is Overlays.Results and _ad_due)
			# closing the game now must drop that advert: nothing about it goes into the save, so the next launch
			# cannot open with one (an advert at app launch is against the store rules)
			var ad_keys: Array = []
			for d in [Game.settings, Game.progress]:
				for k in (d as Dictionary).keys():
					var ks := str(k)
					if (ks.begins_with("ad_") or "advert" in ks) and ks != "ad_standins":
						ad_keys.append(ks)
			cchk.call("... closing the game here skips that advert: nothing about it is saved", ad_keys.is_empty(), ", ".join(ad_keys))
			after_results("menu")
			await _wait(0.5)
			cchk.call("... leaving it plays the advert first", Ads.find_children("*", "Button", true, false).size() > 0)
			await ad_continue.call()
			await _wait(0.8)
			cchk.call("... then the menu", game == null and _screen is MenuScreens.MainMenu)
			Game.set_s("ad_standins", false)
			Game.clock_shift = 0
			Game.progress = c_keep
			if c_all == null:
				Game.settings.erase("unlock_all")
			else:
				Game.settings["unlock_all"] = c_all
			Game.progress_changed.emit()
			_stack.clear()
			go("menu")
			print("CHEST %s %s" % ["PASS" if cbad.is_empty() else "FAIL", str(cbad)])
		"rewards":
			# levels, gear and packages: the menu, Choose Gear, the package page, an opening, the score screen
			var keep_prog: Dictionary = Game.progress.duplicate(true)
			var keep_gear := {}
			for gk in Game.GEAR_KEYS.values():
				keep_gear[gk] = Game.get_s(gk)
			Game.set_s("ar_mode", "studio")
			Game.progress = {"xp": XP.total_for(5) + 60, "owned": ["cue:cue_walnut", "cue:cue_sword_a", "cue:cue_skull_a", "table:midnight", "table:walnut", "balls:tournament", "balls:marble", "scene:desert"],
				"packages": [5, 27, 53, 79, 105], "pk_time": {}, "chest_at": 0, "chest_from": 0, "chest_cut": false, "matches": 0, "curve": 2}
			Game.set_s("cue_skin", "cue_sword_a")
			Game.set_s("table_style", "walnut")
			Game.set_s("ball_set", "marble")
			Game.progress_changed.emit()
			_stack.clear()
			go("menu")
			await _wait(1.6)
			await _shot(dir, "rw_menu")
			go("gear")
			await _wait(0.8)
			await _shot(dir, "rw_gear_cue")
			for gkind in ["table", "balls", "scene"]:
				_screen.set("kind", gkind)
				_screen.call("_fill")
				await _wait(0.5)
				await _shot(dir, "rw_gear_" + gkind)
			back()
			go("packages")
			await _wait(1.4)
			await _shot(dir, "rw_packages")
			_screen.call("_open", false, false)
			await _wait(0.75)
			await _shot(dir, "rw_opening")
			await _wait(1.3)
			await _shot(dir, "rw_reveal")
			for n in _screen.find_children("*", "", true, false):
				if n is RewardScreens.Reveal:
					n.closed.emit(false)
					n.queue_free()
			await _wait(0.6)
			# the last package (the vault)
			Game.progress["packages"] = [105]
			_screen.call("_refresh")
			await _wait(1.0)
			await _shot(dir, "rw_vault")
			_screen.call("_open", false, false)
			await _wait(0.8)
			await _shot(dir, "rw_vault_opening")
			await _wait(1.3)
			for n in _screen.find_children("*", "", true, false):
				if n is RewardScreens.Reveal:
					n.closed.emit(false)
					n.queue_free()
			await _wait(0.4)
			back()
			# the score screen of a won match against the CPU that takes the player up two levels
			start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
			await _wait(0.8)
			var tk := XP.Tracker.new()
			for i in 3:
				tk.shot(1)
				tk.shot(1)
				tk.turn_over()
			tk.shot(2)
			tk.shot(0, true)
			tk.won = true
			var xs: Dictionary = tk.summary("cpu")
			var x_from := XP.total_for(6) - 40
			_results = Overlays.Results.new(self, {"mode": "versus", "winner": 0, "winner_name": "Player 1", "reason": "Sank the 8!", "shots": 19, "vs_ai": true, "ai_level": 1,
				"xp": xs, "gain": {"from": 5, "to": 7, "xp_from": x_from, "xp_to": x_from + 40 + XP.need(6) + 30}})
			Game.progress["packages"] = range(6, 33)   # 27 waiting: the longest the button text gets in normal play
			overlay_host.add_child(_results)
			await _wait(2.2)
			await _shot(dir, "rw_results_mid")
			await _wait(3.4)
			await _shot(dir, "rw_results")
			_results.queue_free()
			_results = null
			_end_match()
			# the advert stand-in (adverts are off; the stand-in only shows with the developer switch)
			Game.set_s("ad_standins", true)
			var ad_done := [false]
			Ads.show("after_match", func(): ad_done[0] = true)
			await _wait(0.6)
			await _shot(dir, "rw_ad")
			await _wait(3.2)
			for n in Ads.find_children("*", "Button", true, false):
				(n as Button).pressed.emit()
			await _wait(0.3)
			print("AD STAND-IN %s" % ("PASS" if ad_done[0] else "FAIL"))
			Game.set_s("ad_standins", false)
			Game.progress = keep_prog
			for gk in keep_gear.keys():
				Game.set_s(gk, keep_gear[gk])
			Game.progress_changed.emit()
			Game.set_s("ar_mode", "auto")
			_stack.clear()
			go("menu")
		"icons":
			# the reward pictures for the Choose Gear page: one square shot per item (run in a small square window,
			# see tools/bake_icons.sh).  --kind=cues|tables|balls|scenes  [--ids=a,b]
			Game.set_s("ar_mode", "studio")
			var ik := "cues"
			var only_i := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--kind="):
					ik = arg.substr(7)
				if arg.begins_with("--ids="):
					only_i = arg.substr(6)
			var skey: String = {"cues": "cue_skin", "tables": "table_style", "balls": "ball_set", "scenes": "scene"}[ik]
			var ilist: Array = {"cues": Catalog.CUES, "tables": Catalog.TABLES, "balls": Catalog.BALLS, "scenes": Catalog.SCENES}[ik]
			var keep_i: String = Game.get_s(skey)
			var icon_cue: CueView = null
			var keep_sf: String = Game.get_s("surface")
			if ik == "tables" or ik == "scenes":
				Game.set_s("surface", "floor")
			var keep_tbl: String = Game.get_s("table_style")
			if ik == "cues" or ik == "balls":
				Game.set_s("table_style", "slate")     # a dark, neutral cloth shows every colour off
			if ik != "balls":
				start_match({"mode": "practice"})
				await _wait(0.5)
			for e in ilist:
				if only_i != "" and not (str(e["id"]) in only_i.split(",")):
					continue
				Game.set_s(skey, e["id"])
				if ik == "balls":
					start_match({"mode": "practice"})
				await _wait(0.4)
				hud.visible = false
				stage.set("_manual", true)
				match ik:
					"cues":
						# its own cue laid along the lit cloth, seen from just behind the butt
						for v in game.views:
							v.visible = false
						game.process_mode = Node.PROCESS_MODE_DISABLED    # or it keeps showing its own cue
						game.cue_view.visible = false
						(stage.get("_key_light") as Light3D).light_energy = 2.3
						if icon_cue == null:
							icon_cue = CueView.new()
							stage.table_root.add_child(icon_cue)
						icon_cue.set_skin(str(e["id"]))
						icon_cue.aim(Vector2(0.86, 0.1), 0.12, 2.5, Vector2.ZERO, 0.0)
						icon_cue.set_process(false)
						var cx2: Transform3D = icon_cue.global_transform
						var d2 := -cx2.basis.z.normalized()
						var off2 := (Vector3(-d2.z, 0.0, d2.x) * 0.62 - d2 * 0.78).normalized()
						stage.set("_want_target", cx2 * Vector3(0.0, 0.0, 1.35))
						stage.set("_want_dist", 0.235)
						stage.set("_want_pitch", deg_to_rad(40.0))
						stage.set("_want_yaw", atan2(off2.x, off2.z))
					"balls":
						var mid2 := Vector3.ZERO
						var cnt2 := 0
						for i in game.sim.n:
							if i != game.cue_index():
								mid2 += game.views[i].position
								cnt2 += 1
						mid2 /= float(cnt2)
						game.views[game.cue_index()].position = mid2 + Vector3(-0.2, 0.0, 0.0)
						game.process_mode = Node.PROCESS_MODE_DISABLED
						game.cue_view.visible = false
						(stage.get("_key_light") as Light3D).light_energy = 2.6
						stage.set("_want_target", stage.table_root.to_global(mid2 + Vector3(-0.02, 0.0, 0.0)))
						stage.set("_want_dist", 0.29)
						stage.set("_want_pitch", deg_to_rad(36.0))
						stage.set("_want_yaw", 0.55)
					"tables":
						game.cue_view.visible = false
						# more light than a match has, so dark frames and legs show in a small picture
						(stage.get("_sun") as Light3D).light_energy = 2.4
						for we in stage.find_children("*", "WorldEnvironment", true, false):
							(we as WorldEnvironment).environment.ambient_light_energy = 2.2
						var tv := [0.0, 2.3, 30.0]
						for arg in OS.get_cmdline_user_args():
							if arg.begins_with("--tv="):
								var parts := arg.substr(5).split(",")
								tv = [float(parts[0]), float(parts[1]), float(parts[2])]
						stage.set("_want_target", stage.table_root.global_position + Vector3(0, tv[0], 0))
						stage.set("_want_dist", tv[1])
						stage.set("_want_pitch", deg_to_rad(tv[2]))
						stage.set("_want_yaw", 0.62)
					"scenes":
						game.cue_view.visible = false
						stage.set("_want_target", stage.table_root.global_position + Vector3(0, 0.35, 0))
						stage.set("_want_dist", 3.3)
						stage.set("_want_pitch", deg_to_rad(9.0))
						stage.set("_want_yaw", -PI / 2.0 + 0.4)
				await _wait(1.8 if ik != "scenes" else 2.4)
				for settle in 14:      # a slow frame (a new table being built) must not leave the camera half-way
					await get_tree().process_frame
				await _shot(dir, "icon_%s_%s" % [ik, str(e["id"])])
				if ik == "balls":
					_end_match()
			if icon_cue:
				icon_cue.queue_free()
			stage.reset_manual()
			Game.set_s(skey, keep_i)
			Game.set_s("surface", keep_sf)
			Game.set_s("table_style", keep_tbl)
			Game.set_s("ar_mode", "auto")
			if game:
				_end_match()
			stage.apply_scene(Game.scene_style())
		"tables":
			# every table style, whole table with its legs (--table=id,id picks some; --play = from the player's view)
			Game.set_s("ar_mode", "studio")
			var keep_t: String = Game.get_s("table_style")
			var keep_surface: String = Game.get_s("surface")
			Game.set_s("surface", "floor")
			var only_t := ""
			var play_view := false
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--table="):
					only_t = arg.substr(8)
				if arg == "--play":
					play_view = true
			start_match({"mode": "practice"})
			await _wait(0.6)
			hud.visible = false
			game.cue_view.visible = false
			for e in Catalog.TABLES:
				if only_t != "" and not (str(e["id"]) in only_t.split(",")):
					continue
				Game.set_s("table_style", e["id"])
				await _wait(0.4)
				stage.set("_manual", true)
				stage.set("_want_target", stage.table_root.global_position + Vector3(0, -0.2 if not play_view else 0.0, 0))
				stage.set("_want_dist", 2.3 if play_view else 3.3)
				stage.set("_want_pitch", deg_to_rad(40.0 if play_view else 17.0))
				stage.set("_want_yaw", 0.0 if play_view else 0.62)
				await _wait(2.2)
				await _shot(dir, "table_" + str(e["id"]) + ("_play" if play_view else ""))
			stage.reset_manual()
			Game.set_s("table_style", keep_t)
			Game.set_s("surface", keep_surface)
			Game.set_s("ar_mode", "auto")
			_end_match()
		"cues":
			# every cue, close on the butt (--cue=id,id picks some; --close = tighter on the last 20 cm)
			Game.set_s("ar_mode", "studio")
			var keep_cue: String = Game.get_s("cue_skin")
			var only_cue := ""
			var close := false
			var aim_view := false      # --aimview: what the player sees while aiming (does the cue get in the way?)
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--cue="):
					only_cue = arg.substr(6)
				if arg == "--close":
					close = true
				if arg == "--aimview":
					aim_view = true
			start_match({"mode": "practice"})
			await _wait(0.6)
			hud.visible = false
			stage.set("_manual", true)
			# --test: the ten cues designed on 12 Nov
			for e in (Catalog.CUES.filter(func(e): return str(e.get("model", "")) in Cues.SHAPES_116) if "--test" in OS.get_cmdline_user_args() else Catalog.CUES):
				var hit := only_cue == ""
				for want in only_cue.split(",", false):
					if str(e["id"]).contains(want):
						hit = true
				if not hit:
					continue
				Game.set_s("cue_skin", e["id"])
				await _wait(0.3)
				if aim_view:
					stage.reset_manual()
					stage.set_view(Stage.View.AIM)
					hud.visible = true
					await _wait(2.0)
					await _shot(dir, "cue_" + str(e["id"]).trim_prefix("cue_") + "_aim")
					continue
				var cx: Transform3D = game.cue_view.global_transform
				var d := -cx.basis.z.normalized()
				var perp := Vector3(-d.z, 0.0, d.x)
				var off := (perp * 0.75 - d * 0.66).normalized()
				stage.set("_want_target", cx * Vector3(0.0, 0.0, 1.34 if close else 1.14))
				stage.set("_want_dist", 0.3 if close else 0.62)
				stage.set("_want_pitch", deg_to_rad(24.0))
				stage.set("_want_yaw", atan2(off.x, off.z))
				await _wait(2.0)
				await _shot(dir, "cue_" + str(e["id"]).trim_prefix("cue_") + ("_close" if close else ""))
			stage.reset_manual()
			Game.set_s("cue_skin", keep_cue)
			Game.set_s("ar_mode", "auto")
			_end_match()
		"match_vs":
			start_match({"mode": "versus", "vs_ai": true, "ai_level": 1})
			await _wait(0.6)
			await _shot(dir, "match_vs_banner")
			await _wait(1.8)
			await _shot(dir, "match_vs")
		"debug":
			open_debug()
			await _wait(0.5)
			await _shot(dir, "debug")
			close_debug()
		"results":
			_results = Overlays.Results.new(self, {"mode": "versus", "winner": 0, "winner_name": "Player 1", "reason": "Sank the 8!", "shots": 23, "vs_ai": true, "ai_level": 2})
			overlay_host.add_child(_results)
			await _wait(1.6)
			await _shot(dir, "results")
			_results.queue_free()
			_results = null
		"top":
			if game:
				stage.set_view(Stage.View.TOP)
				await _wait(1.2)
				await _shot(dir, "top")
		"aim":
			if game:
				stage.set_view(Stage.View.AIM)
				await _wait(1.2)
				await _shot(dir, "aim")
