class_name ARCoreBridge
extends RefCounted
## 6DoF world tracking through the bundled "EmeraldAR" plugin: Google ARCore on Android (android_plugin/),
## Apple ARKit on iPhone and iPad (ios_plugin/, a GDExtension with the same methods and the same state layout).
## The Android plugin runs ARCore on its own thread; we poll it once per frame. When the plugin is missing
## (desktop, or a build without it) every call is a harmless no-op and AR is simply unavailable.

const FAILURES := ["", "Too dark — turn on a light", "Moving too fast — slow down", "Point at a surface with more detail", "Camera unavailable", "Tracking lost — move slowly"]

var plugin: Object = null
var running := false
var tracking := 0            # 0 none, 1 paused (searching), 2 tracking
var failure := 0
var pose := Transform3D()    # camera pose in ARCore world (metres, Y up)
var fov := 60.0
var frame := -1
var new_frame := false
var img_size := Vector2i.ZERO
var uv_o := Vector2.ZERO     # view-normalised -> camera-image-normalised affine map
var uv_x := Vector2(1, 0)
var uv_y := Vector2(0, 1)
var anchor_tracking := 0
var anchor_pose := Transform3D()
var status := 0              # 0 starting, 1 running, -1 failed to start
var hit_valid := false       # the view centre is on a detected horizontal surface
var hit_pos := Vector3.ZERO  # ...at this point (world)
var hit_dist := 0.0
var plane_count := 0         # tracked upward-facing surfaces (floor, tables)
var floor_y := 0.0           # height of the lowest one (valid when plane_count > 0)
var sim_floor := 0.0         # QA simulation: the floor height
var resume_failures := 0     # camera couldn't be opened this many times in a row (busy / no permission)
var sim_availability := "installed"   # QA simulation: what availability() reports
var sim_fail := ""           # QA simulation: start() fails with this error
var _avail_cache := ""
## iPhone / iPad: ARKit instead of ARCore (texts name Apple ARKit; iOS asks for the camera itself).
var ios := OS.get_name() == "iOS"
## iOS is showing its "allow the camera?" question: AR is waiting for the player, not stuck.
var asking_permission := false
var sim_asking := false      # QA simulation: the permission question is open
## QA: simulate an ARCore session (a person walking around the table) on any platform.
var simulate := false
var sim_t := 0.0
var sim_path := Callable()    # optional func(t) -> Transform3D camera pose
var _sim_img := PackedByteArray()
var _sim_start := 0


func _init() -> void:
	if Engine.has_singleton("EmeraldAR"):
		plugin = Engine.get_singleton("EmeraldAR")
	if OS.get_name() in ["Android", "iOS"]:
		print("[ar] EmeraldAR plugin (%s): %s" % ["ARKit" if ios else "ARCore", "present" if plugin else "not bundled"])


func has_plugin() -> bool:
	return plugin != null


## "installed", "not_installed", "too_old", "unsupported", "checking", "error" or "none" (no plugin).
func availability() -> String:
	if simulate:
		return sim_availability
	if plugin == null:
		return "none"
	var a: String = plugin.call("availability")
	if a != _avail_cache:
		print("[ar] %s availability: %s %s" % ["ARKit" if ios else "ARCore", a, last_error() if a == "error" else ""])
		_avail_cache = a
	return a


func available() -> bool:
	return availability() == "installed"


## True when walk-around AR is possible after installing Google Play Services for AR.
func installable() -> bool:
	var a := availability()
	return a == "not_installed" or a == "too_old"


func request_install() -> void:
	if plugin:
		plugin.call("requestInstall")


func open_app_settings() -> void:
	if plugin:
		plugin.call("openAppSettings")


## v1.1.15: the phone's share sheet. False when this build has no way to show it (the game copies the link instead).
func share(text: String, title: String) -> bool:
	if plugin:
		var r = plugin.call("share", text, title)    # (a build of the plugin without it answers null)
		return r == true
	return false


func start(view: Vector2i) -> bool:
	frame = -1
	tracking = 0
	status = 0
	resume_failures = 0
	hit_valid = false
	plane_count = 0
	anchor_tracking = 0
	asking_permission = false
	if simulate:
		running = true
		sim_t = 0.0
		_sim_start = Time.get_ticks_msec()
		return true
	if plugin == null:
		return false
	running = bool(plugin.call("start", view.x, view.y))
	return running


func stop() -> void:
	running = false
	tracking = 0
	status = 0
	if not simulate and plugin:
		plugin.call("stop")


func set_view_size(view: Vector2i) -> void:
	if plugin and running:
		plugin.call("setViewSize", view.x, view.y)


func last_error() -> String:
	if simulate:
		return sim_fail
	return str(plugin.call("getLastError")) if plugin else ""


## Device / Android / AR services version / camera permission / camera config, for the AR help panel.
func info() -> String:
	if simulate:
		return "simulated ARKit" if ios else "simulated ARCore"
	return str(plugin.call("getInfo")) if plugin else "AR plugin not in this build"


## Pull the latest state. Returns true when a new camera image is ready (read it with image_*()).
func poll() -> bool:
	new_frame = false
	if simulate and running:
		return _poll_sim()
	if plugin == null or not running:
		return false
	var s: PackedFloat32Array = plugin.call("getState")
	if s.size() < 28:
		return false
	var st := int(s[27])
	if st != status:
		status = st
		if st == -1:
			print("[ar] walk-around AR failed to start: ", last_error())
			running = false
		elif st == 1:
			print("[ar] walk-around AR session running")
	tracking = int(s[0])
	var q := Quaternion(s[4], s[5], s[6], s[7])
	if q.length_squared() > 0.25:   # all zeros until the first tracked frame
		pose = Transform3D(Basis(q.normalized()), Vector3(s[1], s[2], s[3]))
	if s[8] > 1.0:
		fov = s[8]
	img_size = Vector2i(int(s[10]), int(s[11]))
	uv_o = Vector2(s[12], s[13])
	uv_x = Vector2(s[14], s[15])
	uv_y = Vector2(s[16], s[17])
	anchor_tracking = int(s[18])
	var aq := Quaternion(s[22], s[23], s[24], s[25])
	if anchor_tracking > 0 and aq.length_squared() > 0.25:
		anchor_pose = Transform3D(Basis(aq.normalized()), Vector3(s[19], s[20], s[21]))
	failure = int(s[26])
	if s.size() >= 37:
		resume_failures = int(s[36])
	if s.size() >= 38:
		asking_permission = s[37] > 0.5
	if s.size() >= 36:
		hit_valid = s[28] > 0.5 and tracking == 2
		hit_pos = Vector3(s[29], s[30], s[31])
		plane_count = int(s[32])
		floor_y = s[33]
		hit_dist = s[35]
	var f := int(s[9])
	if f != frame and img_size.x > 0:
		frame = f
		new_frame = true
	return new_frame


func image_y() -> PackedByteArray:
	if simulate:
		return _sim_img
	return plugin.call("getImageY") if plugin else PackedByteArray()


func image_uv() -> PackedByteArray:
	if simulate:
		var uv := PackedByteArray()
		uv.resize(img_size.x / 2 * img_size.y / 2 * 2)
		uv.fill(128)
		return uv
	return plugin.call("getImageUV") if plugin else PackedByteArray()


func _poll_sim() -> bool:
	sim_t = (Time.get_ticks_msec() - _sim_start) / 1000.0
	asking_permission = sim_asking
	if sim_asking:
		status = 0
		tracking = 0
		return false
	if sim_fail != "":
		status = -1
		running = false
		tracking = 0
		return false
	tracking = 2
	status = 1
	fov = 60.0
	if sim_path.is_valid():
		pose = sim_path.call(sim_t)
	else:
		pose = Transform3D(Basis(), Vector3(0, 1.3, 0))
	img_size = Vector2i(64, 36)
	if _sim_img.is_empty():
		_sim_img.resize(64 * 36)
		for y in 36:
			for x in 64:
				_sim_img[y * 64 + x] = 60 + int(40.0 * float(y) / 36.0) + (20 if (x / 8 + y / 8) % 2 == 0 else 0)
	uv_o = Vector2.ZERO
	uv_x = Vector2(1, 0)
	uv_y = Vector2(0, 1)
	# a detected floor at sim_floor: hit-test the view centre against it
	var d := -pose.basis.z
	hit_valid = false
	plane_count = 1
	floor_y = sim_floor
	if d.y < -0.05:
		var t := (sim_floor - pose.origin.y) / d.y
		if t > 0.0 and t < 8.0:
			hit_valid = true
			hit_pos = pose.origin + d * t
			hit_dist = t
	frame += 1
	new_frame = true
	return true


func failure_text() -> String:
	return L.t(FAILURES[clampi(failure, 0, FAILURES.size() - 1)])


func place_anchor(xf: Transform3D) -> void:
	if simulate:
		anchor_pose = xf
		anchor_tracking = 2
		return
	if plugin == null or not running:
		return
	var q := xf.basis.get_rotation_quaternion()
	plugin.call("placeAnchor", PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w]))


func clear_anchor() -> void:
	if simulate:
		anchor_tracking = 0
		return
	if plugin and running:
		plugin.call("clearAnchor")
	anchor_tracking = 0


## The "Placing the table (AR)" help text on iPhone: its last line names Apple ARKit instead of Google ARCore.
static func ios_help(key: String) -> String:
	var lines := L.t(key).split("\n")
	lines[lines.size() - 1] = L.t("AR uses Apple ARKit. If AR can't start, the game tells you why and what to do; you can always play in place instead.")
	return "\n".join(lines)
