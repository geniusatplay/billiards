class_name FpsCounter
extends CanvasLayer
## Developer overlay (Settings → Developer tools → FPS counter, on while the game is being tested): a small pill
## at the top centre of every screen, the loading screen included, above everything else.
##   "60 FPS · 16.7 ms · max 18 ms"
## Frames drawn in the last half second, their average time, and the slowest of them (a hitch shows as a big
## "max" even when the average is fine). The dot is green at 55 frames a second or more, amber from 40, red below.
##
## While it is shown (or with --perf on the command line) every frame slower than HITCH_MS is also printed (the
## phone's log), with what was on screen (FpsCounter.phase), so first-time shader builds and other stalls can be
## found and removed.

const WINDOW := 0.5
const HITCH_MS := 50.0
const AMBER := Color("f5b942")

static var phase := "boot"         # what the game is doing now, for the hitch log
static var hitches: Array = []     # [[ms, phase], ...] since the last clear (only with --perf)
static var _marks: Array = []      # [[usec, what], ...]: things the game did lately (see mark())

var _pill: PanelContainer
var _dot: ColorRect
var _label: Label
var _t := 0.0
var _frames := 0
var _worst := 0.0
var _last_us := 0
var _log := false
var _recent: Array = []   # the last frame times, for "how long is a frame usually right now"


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = "--perf" in OS.get_cmdline_user_args()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", UIKit.box(Color(0.02, 0.04, 0.08, 0.78), 15, 1, Color(1, 1, 1, 0.10), Vector4(12, 1, 14, 1)))
	_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pill.offset_top = 3
	root.add_child(_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(10, 10)
	_dot.color = Color(1, 1, 1, 0.35)     # grey until the first half second has been measured
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_dot)
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # numbers and units, the same in every language
	_label.add_theme_font_override("font", UIKit.font(700))
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# room for the widest reading, so the pill does not twitch as the numbers change
	_label.custom_minimum_size = Vector2(_label.get_theme_font("font").get_string_size("888 FPS · 88.8 ms · max 888 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 4, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "– FPS"
	row.add_child(_label)
	_apply()
	Game.settings_changed.connect(func(k: String):
		if k == "fps_counter":
			_apply())


func _apply() -> void:
	visible = bool(Game.get_s("fps_counter")) or _log
	# with the counter on, the renderer also times its own work (for the hitch log)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
	_t = 0.0
	_frames = 0
	_worst = 0.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else delta * 1000.0
	_last_us = now
	# a hitch: slower than HITCH_MS, and (for the slow software renderer of the test machine) well over the usual
	# frame time of the moment
	_recent.append(ms)
	if _recent.size() > 30:
		_recent.pop_front()
	var usual := ms
	if _recent.size() >= 5:
		var sorted := _recent.duplicate()
		sorted.sort()
		usual = sorted[sorted.size() / 2]
	if (_log or visible) and ms > HITCH_MS and ms > usual * 2.2 and Engine.get_frames_drawn() > 2:
		if _log:
			hitches.append([ms, phase, usual])
		# where the time went: the game's own code, or drawing (for instance a shader being built)
		var done: Array = []
		for m in _marks:
			if now - int(m[0]) < int(ms * 1000.0) + 20000:
				done.append(str(m[1]))
		var vp := get_viewport().get_viewport_rid()
		print("[perf] hitch %.0f ms (usual %.0f) during %s · scripts %.0f ms, physics %.0f ms, drawing %.0f ms (+%.0f setup)%s" % [ms, usual, phase,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.get_frame_setup_time_cpu(),
			(" · just before: " + ", ".join(done)) if not done.is_empty() else ""])
	_marks = _marks.filter(func(m): return now - int(m[0]) < 3000000)
	if not visible:
		return
	_t += ms / 1000.0
	_frames += 1
	_worst = maxf(_worst, ms)
	if _t < WINDOW:
		return
	var fps := _frames / _t
	_label.text = "%d FPS · %.1f ms · max %.0f ms" % [roundi(fps), _t * 1000.0 / _frames, _worst]
	_dot.color = UIKit.EMERALD if fps >= 55.0 else (AMBER if fps >= 40.0 else UIKit.CORAL)
	_t = 0.0
	_frames = 0
	_worst = 0.0


## What the game is doing (screen or match moment), shown in the hitch log.
static func set_phase(p: String) -> void:
	phase = p


## Something the game just did that may take a moment (saving, starting a sound, a new cue...): named in the hitch
## log when a slow frame follows it.
static func mark(what: String) -> void:
	_marks.append([Time.get_ticks_usec(), what])
