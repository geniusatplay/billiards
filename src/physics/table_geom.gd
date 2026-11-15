class_name TableGeom
extends RefCounted
## Playing-surface geometry shared by physics and visuals.
## Table plane coordinates are Vector2(x, z) in metres, origin at the table centre,
## x along the length, z along the width. Cushion nose lines sit at x = ±a and z = ±b.

const CORNER_FACING_DEG := 142.0   # angle between cushion face and pocket facing
const SIDE_FACING_DEG := 104.0

## Sizes follow the WPA equipment specifications (an 8 ft table, measured nose to nose):
##   playing surface 92 x 46 in; ball 2 1/4 in; corner mouth 4.5-4.625 in, side mouth 5-5.125 in (jaw tip to jaw
##   tip); mouth angles 142 and 104 degrees; shelf (mouth line to the slate cut) corner 1-2.25 in, side 0-0.375 in.
const SPEC_LENGTH := 2.3368     # 92 in
const SPEC_WIDTH := 1.1684      # 46 in
const CORNER_SHELF := 0.0270    # 1.06 in: a ball drops once its centre is past it
const SIDE_SHELF := 0.0086      # 0.34 in

var length := SPEC_LENGTH   # nose-to-nose playing length
var width := SPEC_WIDTH
var ball_r := 0.028575
var corner_mouth := 0.1159  # jaw tip to jaw tip, 4 9/16 in
var side_mouth := 0.1286    # 5 1/16 in
var pocket_scale := 1.0     # debug / easy-mode multiplier for both mouths

var a := SPEC_LENGTH * 0.5  # half length
var b := SPEC_WIDTH * 0.5   # half width

## Cushion & facing segments: Array of Dictionary {a, b, n, dir, len, jaw:bool}
var segments: Array = []
## Rounded jaw tips / throat corners treated as point obstacles.
var points: PackedVector2Array = PackedVector2Array()
## Pockets: Array of Dictionary {mid, axis, perp, half_w, drop, hole, hole_r, corner:bool, chain:PackedVector2Array}
var pockets: Array = []
## For visuals: the 6 cushion rail chains (throat, mouth, mouth, throat) in table coords.
var rail_chains: Array = []


func _init(p_len := SPEC_LENGTH, p_wid := SPEC_WIDTH, p_r := 0.028575, p_pocket_scale := 1.0) -> void:
	configure(p_len, p_wid, p_r, p_pocket_scale)


func configure(p_len: float, p_wid: float, p_r: float, p_pocket_scale := 1.0) -> void:
	length = maxf(p_len, 0.6)
	width = maxf(p_wid, 0.4)
	ball_r = clampf(p_r, 0.01, 0.06)
	pocket_scale = clampf(p_pocket_scale, 0.7, 1.8)
	a = length * 0.5
	b = width * 0.5
	_build()


func _build() -> void:
	segments.clear()
	pockets.clear()
	rail_chains.clear()
	points = PackedVector2Array()
	var R := ball_r
	var rs := R / 0.028575                      # mouths scale with ball size
	var cm := corner_mouth * pocket_scale * rs
	var sm := side_mouth * pocket_scale * rs
	var j := cm / sqrt(2.0)                      # corner mouth leg along each rail
	j = minf(j, minf(a, b) * 0.45)
	sm = minf(sm, a * 0.6)

	# Corner pockets -------------------------------------------------------
	var cf := deg_to_rad(180.0 - CORNER_FACING_DEG)
	var lf_c := 1.9 * R
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p_long := Vector2(sx * (a - j), sz * b)     # on long rail
			var p_short := Vector2(sx * a, sz * (b - j))   # on short rail
			var d_long := Vector2(sx * cos(cf), sz * sin(cf))
			var d_short := Vector2(sx * sin(cf), sz * cos(cf))
			var mid := (p_long + p_short) * 0.5
			var axis := Vector2(sx, sz).normalized()
			var t_long := p_long + d_long * lf_c
			var t_short := p_short + d_short * lf_c
			_add_facing(p_long, t_long, mid, axis)
			_add_facing(p_short, t_short, mid, axis)
			var shelf_c := CORNER_SHELF * rs
			var hole_c := _hole(mid, axis, shelf_c, t_long, t_short)
			pockets.append({
				"mid": mid, "axis": axis, "perp": Vector2(-axis.y, axis.x),
				"half_w": cm * 0.5, "drop": shelf_c,
				"hole": hole_c[0], "hole_r": hole_c[1],
				"corner": true, "p1": p_long, "p2": p_short, "t1": t_long, "t2": t_short,
			})

	# Side pockets -----------------------------------------------------------
	var sf := deg_to_rad(180.0 - SIDE_FACING_DEG)
	var lf_s := 1.55 * R
	for sz in [-1.0, 1.0]:
		var p_l := Vector2(-sm * 0.5, sz * b)
		var p_r := Vector2(sm * 0.5, sz * b)
		var d_l := Vector2(cos(sf), sz * sin(sf))     # from left mouth toward pocket (+x) & outward
		var d_r := Vector2(-cos(sf), sz * sin(sf))
		var mid := Vector2(0.0, sz * b)
		var axis := Vector2(0.0, sz)
		var t_l := p_l + d_l * lf_s
		var t_r := p_r + d_r * lf_s
		_add_facing(p_l, t_l, mid, axis)
		_add_facing(p_r, t_r, mid, axis)
		var shelf_s := SIDE_SHELF * rs
		var hole_s := _hole(mid, axis, shelf_s, t_l, t_r)
		pockets.append({
			"mid": mid, "axis": axis, "perp": Vector2(-axis.y, axis.x),
			"half_w": sm * 0.5, "drop": shelf_s,
			"hole": hole_s[0], "hole_r": hole_s[1],
			"corner": false, "p1": p_l, "p2": p_r, "t1": t_l, "t2": t_r,
		})

	# Cushion noses ----------------------------------------------------------
	for sz in [-1.0, 1.0]:
		var n := Vector2(0.0, -sz)
		_add_cushion(Vector2(-a + j, sz * b), Vector2(-sm * 0.5, sz * b), n)
		_add_cushion(Vector2(sm * 0.5, sz * b), Vector2(a - j, sz * b), n)
	for sx in [-1.0, 1.0]:
		_add_cushion(Vector2(sx * a, -b + j), Vector2(sx * a, b - j), Vector2(-sx, 0.0))

	# Point obstacles: mouth jaw tips and throat corners (deduplicated)
	for pk in pockets:
		for key in ["p1", "p2", "t1", "t2"]:
			_add_point(pk[key])

	# Rail chains for visuals: each cushion section from throat to throat.
	_build_rail_chains()


## The round hole cut in the slate behind a pocket: its edge nearest the table is `shelf` past the middle of the
## mouth line (where a ball drops, see PoolSim), and it reaches the two throats where the jaw facings end.
## Returns [centre, radius].
func _hole(mid: Vector2, axis: Vector2, shelf: float, t1: Vector2, t2: Vector2) -> Array:
	var s_t := ((t1 + t2) * 0.5 - mid).dot(axis)        # how far in the throats are
	var half := t1.distance_to(t2) * 0.5
	var deep := maxf(s_t - shelf, 0.2 * ball_r)
	var r := maxf((deep * deep + half * half) / (2.0 * deep), 1.1 * ball_r)
	return [mid + axis * (shelf + r), r]


func _add_cushion(pa: Vector2, pb: Vector2, n: Vector2) -> void:
	var d := pb - pa
	segments.append({"a": pa, "b": pb, "n": n, "dir": d.normalized(), "len": d.length(), "jaw": false})


func _add_facing(pa: Vector2, pb: Vector2, mid: Vector2, axis: Vector2) -> void:
	var d := pb - pa
	var dir := d.normalized()
	var n := Vector2(-dir.y, dir.x)
	# normal must point toward the pocket channel (toward the pocket axis line)
	var to_axis := (mid + axis * axis.dot(pa - mid)) - pa
	if n.dot(to_axis) < 0.0:
		n = -n
	segments.append({"a": pa, "b": pb, "n": n, "dir": dir, "len": d.length(), "jaw": true})


func _add_point(p: Vector2) -> void:
	for q in points:
		if q.distance_squared_to(p) < 1e-10:
			return
	points.append(p)


func _pocket_at(c: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for pk in pockets:
		var dd: float = (pk["mid"] as Vector2).distance_to(c)
		if dd < bd:
			bd = dd
			best = pk
	return best


func _build_rail_chains() -> void:
	# Long rails: corner(-x) -> side, side -> corner(+x). Short rails: corner -> corner.
	var pc := {}
	for pk in pockets:
		var key := "%d_%d" % [signi(int(round((pk["mid"] as Vector2).x * 1000.0))), signi(int(round((pk["mid"] as Vector2).y * 1000.0)))]
		pc[key] = pk
	for sz in [-1, 1]:
		var cl: Dictionary = pc["%d_%d" % [-1, sz]]
		var sd: Dictionary = pc["%d_%d" % [0, sz]]
		var cr: Dictionary = pc["%d_%d" % [1, sz]]
		rail_chains.append({"chain": PackedVector2Array([cl["t1"], cl["p1"], sd["p1"], sd["t1"]]), "out": Vector2(0, sz)})
		rail_chains.append({"chain": PackedVector2Array([sd["t2"], sd["p2"], cr["p1"], cr["t1"]]), "out": Vector2(0, sz)})
	for sx in [-1, 1]:
		var c1: Dictionary = pc["%d_%d" % [sx, -1]]
		var c2: Dictionary = pc["%d_%d" % [sx, 1]]
		rail_chains.append({"chain": PackedVector2Array([c1["t2"], c1["p2"], c2["p2"], c2["t2"]]), "out": Vector2(sx, 0)})


## True when a ball centre at p is inside the legal playing rectangle.
func in_bounds(p: Vector2, margin := 0.0) -> bool:
	return absf(p.x) <= a - ball_r - margin and absf(p.y) <= b - ball_r - margin


## Normalized level coords (-1..1) -> table coords, keeping a safe margin from cushions.
func from_norm(nrm: Vector2) -> Vector2:
	return Vector2(nrm.x * (a - ball_r), nrm.y * (b - ball_r))


func to_norm(p: Vector2) -> Vector2:
	return Vector2(p.x / (a - ball_r), p.y / (b - ball_r))
