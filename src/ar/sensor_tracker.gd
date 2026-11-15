class_name SensorTracker
extends RefCounted
## 3DoF orientation from gyroscope + gravity with automatic axis-convention calibration.
##
## Phones (and engine versions) disagree on sensor axis order/sign. Rather than trusting one convention:
## * gravity -> screen frame: 8 hypotheses (quarter-turn about the screen normal x sign). We pick the one
##   that matches how a person holds a phone (screen facing them, camera toward the floor/table).
## * gyro -> screen frame: 48 signed-permutation hypotheses scored by least-squares residual between the
##   measured change of the gravity vector and the change each predicts (dg/dt = -w x g).
## Output: `q` (device/screen frame -> world), world Y up, initial heading = world -Z.

signal calibrated(gyro_map: int, gravity_map: int)

const PERMS := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

var q := Quaternion.IDENTITY
var initialized := false
var has_gyro := false
var has_gravity := false
var gyro_map := 0
var gravity_map := 0
var gyro_locked := false
var gravity_locked := false
var confidence := 0.0
var yaw_offset := 0.0          # user swipe-orbit adds to heading (radians)

var _scores := PackedFloat32Array()
var _motion := 0.0
var _prev_g := Vector3.ZERO
var _tilt_time := 0.0
var _lp_acc := Vector3.ZERO
## Tests can inject raw readings instead of the Input singleton.
var inject := false
var inj_gravity := Vector3.ZERO
var inj_gyro := Vector3.ZERO


func _init() -> void:
	_scores.resize(48)
	_scores.fill(0.0)
	_apply_overrides()


func _apply_overrides() -> void:
	var gm := int(Game.get_s("gyro_mapping"))
	var gr := int(Game.get_s("gravity_mapping"))
	if gm >= 0:
		gyro_map = gm % 48
		gyro_locked = true
	if gr >= 0:
		gravity_map = gr % 8
		gravity_locked = true


func reset() -> void:
	initialized = false
	_motion = 0.0
	_scores.fill(0.0)
	gyro_locked = false
	gravity_locked = false
	_apply_overrides()


static func signed_perm(idx: int, v: Vector3) -> Vector3:
	var p: Array = PERMS[(idx / 8) % 6]
	var sgn := idx % 8
	return Vector3(v[p[0]] * (1.0 - 2.0 * float(sgn & 1)), v[p[1]] * (1.0 - 2.0 * float((sgn >> 1) & 1)), v[p[2]] * (1.0 - 2.0 * float((sgn >> 2) & 1)))


static func gravity_hyp(idx: int, g: Vector3) -> Vector3:
	var k := idx % 4
	var s := 1.0 if idx < 4 else -1.0
	var v := g * s
	match k:
		1: v = Vector3(-v.y, v.x, v.z)
		2: v = Vector3(-v.x, -v.y, v.z)
		3: v = Vector3(v.y, -v.x, v.z)
	return v


## How plausible is a screen-frame "down" vector for a person looking at their phone?
static func _plausibility(d: Vector3) -> float:
	# down should point toward the bottom of the screen and/or out of the back of the phone
	return -d.y - d.z - 1.6 * absf(d.x) - 2.0 * maxf(d.z, 0.0) * maxf(d.y, 0.0)


func _raw_gravity(dt: float) -> Vector3:
	var g := inj_gravity if inject else Input.get_gravity()
	if g.length() > 0.5:
		if not has_gravity and not inject:
			print("[sensors] gravity sensor ", g)
		has_gravity = true
		return g
	var a := Vector3.ZERO if inject else Input.get_accelerometer()
	if a.length() > 0.5:
		if not has_gravity and not inject:
			print("[sensors] accelerometer (no gravity sensor) ", a)
		has_gravity = true
		_lp_acc = _lp_acc.lerp(a, clampf(dt * 4.0, 0.0, 1.0)) if _lp_acc != Vector3.ZERO else a
		return _lp_acc
	return Vector3.ZERO


## Screen-frame down unit vector (or ZERO if no sensor).
func down_vector(dt := 0.016) -> Vector3:
	var raw := _raw_gravity(dt)
	if raw == Vector3.ZERO:
		return Vector3.ZERO
	if not gravity_locked:
		var best := 0
		var bs := -INF
		for h in 8:
			var s := _plausibility(gravity_hyp(h, raw).normalized())
			if s > bs:
				bs = s
				best = h
		gravity_map = best
		var d0 := gravity_hyp(best, raw).normalized()
		# once the phone is clearly tilted toward the floor the z-sign ambiguity is resolved
		if d0.z < -0.35:
			_tilt_time += dt
			if _tilt_time > 0.6:
				gravity_locked = true
				calibrated.emit(gyro_map, gravity_map)
		else:
			_tilt_time = 0.0
	return gravity_hyp(gravity_map, raw).normalized()


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var prev_map := gravity_map
	var g := down_vector(dt)
	if g == Vector3.ZERO:
		return
	if gravity_map != prev_map and int(Game.get_s("gyro_mapping")) < 0:
		# the screen frame changed, so gyro evidence gathered so far is invalid
		_scores.fill(0.0)
		_motion = 0.0
		gyro_locked = false
		initialized = false
	if not initialized:
		_init_from(g)
		_prev_g = g
		return
	var raw_w := inj_gyro if inject else Input.get_gyroscope()
	if not has_gyro and raw_w.length() > 0.0005 and not inject:
		print("[sensors] gyroscope ", raw_w)
	has_gyro = has_gyro or raw_w.length() > 0.0005
	if has_gyro and not gyro_locked and raw_w.length() > 0.2 and _prev_g != Vector3.ZERO:
		# least-squares: the right mapping predicts the measured change of gravity almost exactly
		var dg := g - _prev_g
		for h in 48:
			var w := signed_perm(h, raw_w)
			var pred := -w.cross(_prev_g) * dt
			_scores[h] += (dg - pred).length_squared()
		_motion += raw_w.length() * dt
		if _motion > 1.8:
			var best := 0
			for h in 48:
				if _scores[h] < _scores[best]:
					best = h
			var second := INF
			for h in 48:
				if h != best and _scores[h] < second:
					second = _scores[h]
			confidence = clampf(1.0 - _scores[best] / maxf(second, 1e-12), 0.0, 1.0)
			gyro_map = best
			if confidence > 0.6 or _motion > 6.0:
				gyro_locked = true
				calibrated.emit(gyro_map, gravity_map)
	# integrate body rates
	if has_gyro:
		var w := signed_perm(gyro_map, raw_w)
		var wl := w.length()
		if wl > 1e-5:
			q = (q * Quaternion(w / wl, wl * dt)).normalized()
	# tilt correction toward measured gravity (removes pitch/roll drift)
	var d_p := q.inverse() * Vector3.DOWN
	var axis := g.cross(d_p)
	var al := axis.length()
	if al > 1e-6:
		var ang := acos(clampf(g.dot(d_p), -1.0, 1.0))
		var k := 1.0 if gyro_locked else 6.0
		if not has_gyro:
			k = 12.0
		q = (q * Quaternion(axis / al, ang * clampf(k * dt, 0.0, 1.0))).normalized()
	_prev_g = g


func _init_from(down: Vector3) -> void:
	var q0 := Quaternion(down, Vector3.DOWN)
	var fwd := q0 * Vector3.FORWARD
	fwd.y = 0.0
	if fwd.length() < 0.15:
		fwd = q0 * Vector3.UP
		fwd.y = 0.0
	if fwd.length() > 1e-3:
		q = Quaternion(fwd.normalized(), Vector3.FORWARD) * q0
	else:
		q = q0
	q = q.normalized()
	initialized = true


## Re-zero heading so the camera's current facing becomes world -Z.
func recenter() -> void:
	var fwd := q * Vector3.FORWARD
	fwd.y = 0.0
	if fwd.length() > 0.1:
		q = (Quaternion(fwd.normalized(), Vector3.FORWARD) * q).normalized()


func basis() -> Basis:
	return Basis(Quaternion(Vector3.UP, yaw_offset) * q)


func describe() -> String:
	return "gyro map %d%s · gravity map %d%s · conf %.2f%s" % [gyro_map, " (locked)" if gyro_locked else "",
		gravity_map, " (locked)" if gravity_locked else "", confidence, "" if has_gyro else " · NO GYRO"]
