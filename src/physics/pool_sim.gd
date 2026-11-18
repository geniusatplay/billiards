class_name PoolSim
extends RefCounted
## Deterministic billiards simulator (custom; Godot rigid bodies are not used).
##
## Model summary (see docs/DESIGN_PLAN.md §4):
## * Each ball: position/velocity on the table plane + full 3D angular velocity.
## * Sliding friction acts against the contact-point slip, so draw / follow / stun / masse emerge naturally.
## * Rolling resistance once slip vanishes; vertical (side) spin decays with spinning friction.
## * Continuous collision detection (time of impact) for balls, cushions and jaw tips.
## * Ball-ball contact has restitution + friction-limited tangential impulse (throw & spin transfer).
## * Cushion contact uses the nose-height contact point so english changes rebound angles.
## * Balls can leave the cloth: an elevated cue drives the ball into the slate and it bounces up (jump
##   shots); airborne balls fly ballistically, collide in 3D, land with a frictional bounce, clear
##   balls / cushions they pass over, and can leave the table.
## * Ball-ball friction falls with sliding speed (measured curve, Alciatore TP A-14) so slow cuts throw more.
## The same code runs gameplay, the aim preview and the AI.

enum { ST_REST, ST_MOVING, ST_POCKETED }
const OFF_TABLE := -2      # pocket_of value for a ball that jumped off the table
enum { K_CUE, K_OBJECT, K_EIGHT }

const G := 9.81
const MAX_EVENTS_PER_STEP := 160  # a frozen rack takes up to ~60 contacts in the break's first 1/240 s
const HOP_MIN := 0.06       # m/s: slower upward bounces don't leave the cloth

# ---- tunables (debug menu writes these) ----
var mu_slide := 0.20
var mu_roll := 0.0125
var mu_spin := 0.014
var e_ball := 0.95
var mu_ball := 0.046            # ball-ball friction at 1 m/s sliding speed (higher when slower)
var e_cushion := 0.80
var mu_cushion := 0.20
var e_jaw := 0.55
var cushion_nose := 1.27        # nose height in ball radii above the bed
var max_speed := 8.0
var break_scale := 2.0          # the break shot may be this many times faster than any other shot
var break_shot := false         # the next strike is the break (the rack has not been touched yet)
var squirt_deg := 1.4           # cue-ball deflection at full side offset
var substep := 1.0 / 240.0
var e_table := 0.5              # bed restitution for a ball driven into / landing on the cloth
var cushion_top := 1.55         # cushion top height in ball radii; balls whose bottom is above it fly over

# The cue stick is a solid object: it can't pass through the cushions or the wooden rail behind the
# cue ball. With cue_clearance on, every strike is raised to min_cue_elevation() (the game turns it on;
# the reference physics tests leave it off so their shots are exactly level).
var cue_clearance := false
## With ball_clearance on as well, the stick doesn't pass through other balls either: it rises over them
## (Randy, 11 Nov; a developer option, on by default, always on online). The tip may touch the cue ball.
var ball_clearance := false
const STROKE_BACK := 0.25       # how far the stick is drawn back for a stroke (it sweeps that part too)
var rail_height := 0.045        # top of the wooden rail above the cloth (m)
const CUSHION_DEPTH := 0.05     # cushion nose -> wooden rail (m); TableView builds the table from these too
const CUE_LENGTH := 1.47
const CUE_TIP_R := 0.0065
const CUE_BUTT_R := 0.015
const CUE_GAP := 0.002          # the stick may rest on the rail: clearance when "touching"

var table: TableGeom
var R := 0.028575

# ---- ball state (struct of arrays) ----
var n := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var spin := PackedVector3Array()
var st := PackedInt32Array()
var num := PackedInt32Array()      # ball number shown (0 = cue)
var kind := PackedInt32Array()
var pocket_of := PackedInt32Array() # pocket index if pocketed, OFF_TABLE if it left the table, else -1
var hz := PackedFloat64Array()      # height of the ball's lowest point above the cloth (0 = on the cloth)
var vz := PackedFloat64Array()      # vertical velocity
var n_air := 0                      # how many balls are airborne (fast path when 0)

# ---- bookkeeping ----
var time := 0.0
var events: Array = []    # gameplay consumes: {type, t, ...}
var record_events := true
var first_hit := -1       # index of the first ball the cue ball touched this shot
var cushion_after_contact := false
## The last answer of each "lowest elevation" search, with what it was asked (aim, tip, the balls where they
## are). While aiming, the match and the screen ask the same question several times a frame, and again every
## frame while the finger rests: the search (17 tries, every ball each time) is only run when something changed.
var _memo_cue := []
var _memo_ball := []

# ---- online replay (v1.1.14) ----
## Substeps since the last strike. The shooting phone numbers its snapshots of the table by it.
var step_no := 0
## The shooter's table while the shot ran, step -> snapshot (see NetMatch.make_path). The other phone's replay
## takes each one on the moment it reaches that step, so both tables move together even where two phones
## calculate a hair apart (an iPhone and an Android phone round some maths differently, and every collision of
## a break makes such a hair bigger).
var path := {}
var path_end := -1                 # the step the shooter's balls stopped at (-1: no path)
var path_fixes := 0                # snapshots that differed from this phone's own replay (tests, log)
var path_changed: Array = []       # balls a snapshot put into a pocket or back on the table (the game's pictures)
## A double-precision engine build keeps vectors in doubles; the snapshots then carry doubles too.
static var _wide := Vector2(1.0 + 1e-12, 0.0).x != 1.0


func _init(p_table: TableGeom = null) -> void:
	table = p_table if p_table != null else TableGeom.new()
	R = table.ball_r


# ======================================================================
# Setup
# ======================================================================

func clear_balls() -> void:
	n = 0
	pos = PackedVector2Array(); vel = PackedVector2Array(); spin = PackedVector3Array()
	st = PackedInt32Array(); num = PackedInt32Array(); kind = PackedInt32Array()
	pocket_of = PackedInt32Array()
	hz = PackedFloat64Array(); vz = PackedFloat64Array(); n_air = 0


func add_ball(p: Vector2, number: int, k: int) -> int:
	pos.append(p); vel.append(Vector2.ZERO); spin.append(Vector3.ZERO)
	st.append(ST_REST); num.append(number); kind.append(k)
	pocket_of.append(-1)
	hz.append(0.0); vz.append(0.0)
	n += 1
	return n - 1


func set_table(t: TableGeom) -> void:
	table = t
	R = t.ball_r


func clone() -> PoolSim:
	var s := PoolSim.new(table)
	s.copy_params_from(self)
	s.n = n
	s.pos = pos.duplicate(); s.vel = vel.duplicate(); s.spin = spin.duplicate()
	s.st = st.duplicate(); s.num = num.duplicate(); s.kind = kind.duplicate()
	s.pocket_of = pocket_of.duplicate()
	s.hz = hz.duplicate(); s.vz = vz.duplicate(); s.n_air = n_air
	s.time = time
	s.break_shot = break_shot
	return s


func copy_params_from(o: PoolSim) -> void:
	mu_slide = o.mu_slide; mu_roll = o.mu_roll; mu_spin = o.mu_spin
	e_ball = o.e_ball; mu_ball = o.mu_ball; e_cushion = o.e_cushion; mu_cushion = o.mu_cushion
	e_jaw = o.e_jaw; cushion_nose = o.cushion_nose; max_speed = o.max_speed; break_scale = o.break_scale
	squirt_deg = o.squirt_deg; substep = o.substep
	e_table = o.e_table; cushion_top = o.cushion_top
	cue_clearance = o.cue_clearance; rail_height = o.rail_height; ball_clearance = o.ball_clearance


func apply_params(d: Dictionary) -> void:
	for k in d.keys():
		if k in self:
			set(k, d[k])


# ======================================================================
# Shooting
# ======================================================================

## Strike ball `i` (normally the cue ball).
## yaw: aim direction angle in the table plane (radians, 0 = +x, PI/2 = +z)
## power: 0..1, offset: tip offset in units of R (x = right english, y = top spin), |offset| <= 0.5
## elevation_deg: cue butt raised (0 = level). Produces masse curves with side offset.
func strike(i: int, yaw: float, power: float, offset := Vector2.ZERO, elevation_deg := 0.0) -> void:
	power = clampf(power, 0.0, 1.0)
	if offset.length() > 0.5:
		offset = offset.normalized() * 0.5
	if cue_clearance:
		elevation_deg = maxf(elevation_deg, min_cue_elevation(pos[i], yaw, offset))
	var elev := deg_to_rad(clampf(elevation_deg, 0.0, 75.0))
	var speed := lerpf(0.12, max_speed * (break_scale if break_shot else 1.0), pow(power, 1.25))
	speed /= 1.0 + 0.6 * offset.length_squared()   # off-centre hits transfer less speed
	var yaw_eff := yaw - deg_to_rad(squirt_deg) * (offset.x / 0.5) * cos(elev)
	var d := Vector3(cos(elev) * cos(yaw_eff), -sin(elev), cos(elev) * sin(yaw_eff))
	var side := d.cross(Vector3.UP).normalized()
	var up := side.cross(d).normalized()
	var ao := offset.x * R
	var bo := offset.y * R
	var depth := sqrt(maxf(R * R - ao * ao - bo * bo, 0.0))
	var pc := -depth * d + ao * side + bo * up
	var v3 := d * speed
	var w := pc.cross(v3) / (0.4 * R * R)
	vel[i] = Vector2(v3.x, v3.z)
	spin[i] = w
	st[i] = ST_MOVING
	_set_air(i, 0.0, 0.0)
	# an elevated cue drives the ball into the slate: it bounces back up (jump) and the cloth grips it
	if v3.y < -1e-4:
		_bed_impulse(i, -v3.y, e_table)
	first_hit = -1
	cushion_after_contact = false
	_emit({"type": "cue", "ball": i, "speed": speed})
	step_no = 0
	if path_end >= 0 and path.has(0):
		_restore(path[0])         # the struck ball leaves exactly as on the shooter's phone


# ======================================================================
# Cue stick vs. rails
# ======================================================================
## Cushion nose height above the cloth: 63.5% of the ball's diameter (WPA).
static func cushion_height(ball_r: float) -> float:
	return clampf(ball_r * 1.27, 0.025, 0.06)


static func cushion_setback(ball_r: float) -> float:
	return ball_r * 0.25


## The edges the stick has to pass over, as [distance beyond the cushion nose line, height above the cloth]:
## the top edge of the cushion, then the (slightly higher) inner edge of the wooden rail.
func rail_edges() -> Array:
	var ch := cushion_height(R)
	return [[cushion_setback(R), ch], [CUSHION_DEPTH, maxf(rail_height, ch)]]


## Lowest cue elevation (degrees) at which the stick, lying behind a cue ball at `p` for a shot along
## `yaw` with tip offset `offset` (ball radii), clears the cushion and rail. 0 when nothing is in the way
## (the rail behind the ball is further than the stick is long).
func min_cue_elevation(p: Vector2, yaw: float, offset := Vector2.ZERO) -> float:
	var key := [p, yaw, offset, ball_clearance, rail_height, R, pos.duplicate(), st.duplicate()]
	if not _memo_cue.is_empty() and _memo_cue[0] == key:
		return _memo_cue[1]
	var v := _min_cue_elevation(p, yaw, offset)
	_memo_cue = [key, v]
	return v


func _min_cue_elevation(p: Vector2, yaw: float, offset: Vector2) -> float:
	if cue_clears(p, yaw, offset, 0.0):
		return 0.0
	var lo := 0.0
	var hi := 75.0
	if not cue_clears(p, yaw, offset, hi):
		return hi
	for k in 16:
		var mid := (lo + hi) * 0.5
		if cue_clears(p, yaw, offset, mid):
			hi = mid
		else:
			lo = mid
	return hi


## Smallest gap (m) between the underside of the stick and the rail edges; negative = cutting through.
func cue_gap(p: Vector2, yaw: float, offset: Vector2, elevation_deg: float) -> float:
	var e := deg_to_rad(elevation_deg)
	var ce := cos(e)
	var se := sin(e)
	var back := -Vector2(cos(yaw), sin(yaw))
	var oy := clampf(offset.y, -0.5, 0.5) * R
	var best := INF
	for edge in rail_edges():
		var ext: float = edge[0]
		var h: float = edge[1]
		# horizontal distance from the ball centre, going backwards, to this edge's rectangle
		var t := INF
		if absf(back.x) > 1e-6:
			t = minf(t, (signf(back.x) * (table.a + ext) - p.x) / back.x)
		if absf(back.y) > 1e-6:
			t = minf(t, (signf(back.y) * (table.b + ext) - p.y) / back.y)
		if t == INF or t <= 0.0:
			continue
		# stick axis: centre + up * oy + (back * ce, se) * u, with up = (forward * se, ce)
		var u := (t + oy * se) / maxf(ce, 1e-4)
		var along := u - R                     # distance from the tip along the stick
		if along > CUE_LENGTH:
			continue                           # the butt ends before this edge
		var axis_h := R + oy * ce + u * se
		# radius where it crosses, allowing for the stick being drawn back for the stroke
		var r := lerpf(CUE_TIP_R, CUE_BUTT_R, clampf((maxf(along, 0.0) + 0.25) / CUE_LENGTH, 0.0, 1.0))
		best = minf(best, axis_h - r / maxf(ce, 0.2) - h)
	return best


func cue_clears(p: Vector2, yaw: float, offset: Vector2, elevation_deg: float) -> bool:
	if cue_gap(p, yaw, offset, elevation_deg) < CUE_GAP:
		return false
	return not ball_clearance or balls_gap(p, yaw, offset, elevation_deg) >= 0.0


## Smallest gap (m) between the stick and any ball on the table other than the cue ball at `p` (negative =
## the stick would be inside that ball). The stick runs from its tip on the cue ball back for its whole
## length plus the draw-back of the stroke, getting thicker towards the butt.
func balls_gap(p: Vector2, yaw: float, offset: Vector2, elevation_deg: float) -> float:
	var e := deg_to_rad(elevation_deg)
	var ce := cos(e)
	var se := sin(e)
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var dirb := -fwd * ce + Vector3.UP * se             # along the stick, from the tip towards the butt
	var upv := fwd * se + Vector3.UP * ce               # square to the stick, upwards
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	var o := offset.limit_length(0.5) * R
	var base := Vector3(p.x, R, p.y) + upv * o.y + side * o.x
	var t0 := R                                          # the tip, on the cue ball's surface
	var t1 := R + CUE_LENGTH + STROKE_BACK
	var best := INF
	for j in n:
		if st[j] == ST_POCKETED or (pos[j] - p).length_squared() < R * R * 0.25:
			continue
		var q := Vector3(pos[j].x, R, pos[j].y)
		var t := clampf((q - base).dot(dirb), t0, t1)
		var along := t - t0
		var r := lerpf(CUE_TIP_R, CUE_BUTT_R, clampf(along / CUE_LENGTH, 0.0, 1.0))
		best = minf(best, (q - (base + dirb * t)).length() - R - r)
	return best


## Lowest elevation (degrees) at which the stick clears the other balls alone (the rail not counted).
func min_ball_elevation(p: Vector2, yaw: float, offset := Vector2.ZERO) -> float:
	var key := [p, yaw, offset, ball_clearance, R, pos.duplicate(), st.duplicate()]
	if not _memo_ball.is_empty() and _memo_ball[0] == key:
		return _memo_ball[1]
	var v := _min_ball_elevation(p, yaw, offset)
	_memo_ball = [key, v]
	return v


func _min_ball_elevation(p: Vector2, yaw: float, offset: Vector2) -> float:
	if not ball_clearance or balls_gap(p, yaw, offset, 0.0) >= 0.0:
		return 0.0
	var lo := 0.0
	var hi := 75.0
	if balls_gap(p, yaw, offset, hi) < 0.0:
		return hi
	for k in 16:
		var mid := (lo + hi) * 0.5
		if balls_gap(p, yaw, offset, mid) >= 0.0:
			hi = mid
		else:
			lo = mid
	return hi


# ======================================================================
# Stepping
# ======================================================================

func is_moving() -> bool:
	for i in n:
		if st[i] == ST_MOVING:
			return true
	return false


## Advance by `dt` seconds using fixed substeps. Returns true while anything moves.
func advance(dt: float) -> bool:
	var steps := maxi(1, int(round(dt / substep)))
	for _s in steps:
		if not is_moving() and not replay_pending():
			return false
		_substep(substep)
		_stepped()
	return is_moving() or replay_pending()


## Online: the shooter's snapshots go on to a later step (this replay must keep going even if its own balls
## have stopped a moment early).
func replay_pending() -> bool:
	return path_end >= 0 and step_no < path_end


func _stepped() -> void:
	step_no += 1
	if path_end >= 0 and path.has(step_no):
		_restore(path[step_no])


## Run until everything stops (or max_time). Used by AI / solver / preview.
func run_to_rest(max_time := 25.0) -> void:
	var t0 := time
	while (is_moving() or replay_pending()) and time - t0 < max_time:
		_substep(substep)
		_stepped()
	if is_moving():
		for i in n:
			if st[i] == ST_MOVING:
				vel[i] = Vector2.ZERO; spin[i] = Vector3.ZERO; st[i] = ST_REST
				_set_air(i, 0.0, 0.0)


func _substep(h: float) -> void:
	var t_left := h
	var guard := 0
	while t_left > 1e-9 and guard < MAX_EVENTS_PER_STEP:
		guard += 1
		var ev := _earliest_event(t_left)
		var th: float = ev[0]
		if th > 0.0:
			_drift(th)
			t_left -= th
		if ev[1] == 0:
			break
		_resolve(ev)
	if t_left > 1e-9:
		_drift(t_left)
	_apply_friction(h)
	_post_step(h)
	time += h


func _drift(t: float) -> void:
	for i in n:
		if st[i] == ST_MOVING:
			pos[i] = pos[i] + vel[i] * t
	if n_air > 0:
		for i in n:
			if st[i] == ST_MOVING and (hz[i] > 0.0 or vz[i] != 0.0):
				# exact ballistic flight
				hz[i] = maxf(hz[i] + vz[i] * t - 0.5 * G * t * t, 0.0)
				vz[i] -= G * t


func is_airborne(i: int) -> bool:
	return hz[i] > 0.0 or vz[i] > 0.0


func _set_air(i: int, h: float, v: float) -> void:
	var was := hz[i] > 0.0 or vz[i] != 0.0
	hz[i] = h
	vz[i] = v
	var now := h > 0.0 or v != 0.0
	if now and not was:
		n_air += 1
	elif was and not now:
		n_air -= 1


## Vertical impulse from the bed: the ball arrives with downward speed v_in and leaves with e * v_in.
## Cloth friction acts on the contact-point slip (limited to what stops the slip).
func _bed_impulse(i: int, v_in: float, e: float) -> void:
	var jn := (1.0 + e) * v_in
	var v: Vector2 = vel[i]
	var w: Vector3 = spin[i]
	var ux := v.x + R * w.z
	var uz := v.y - R * w.x
	var ul := sqrt(ux * ux + uz * uz)
	if ul > 1e-7:
		var jt := minf(mu_slide * jn, ul / 3.5)
		var dvx := -ux / ul * jt
		var dvz := -uz / ul * jt
		v.x += dvx
		v.y += dvz
		w.x += -dvz / (0.4 * R)
		w.z += dvx / (0.4 * R)
	vel[i] = v
	spin[i] = w
	var up := e * v_in
	_set_air(i, hz[i], up if up > HOP_MIN else 0.0)
	if up > HOP_MIN:
		_emit({"type": "bounce", "ball": i, "speed": v_in})


## Returns [time, type, i, j] with type 0=none, 1=ball, 2=segment (cushion/facing), 3=point (jaw tip)
func _earliest_event(t_max: float) -> Array:
	var best_t := t_max
	var best := [t_max, 0, -1, -1]
	var a_edge := table.a
	var b_edge := table.b
	var R2 := 2.0 * R
	var R2sq := R2 * R2
	for i in n:
		if st[i] != ST_MOVING:
			continue
		var pi: Vector2 = pos[i]
		var vi: Vector2 = vel[i]
		var reach := vi.length() * best_t
		var air_i := n_air > 0 and (hz[i] > 0.0 or vz[i] != 0.0)
		if air_i:
			reach += absf(vz[i]) * best_t + 0.5 * G * best_t * best_t
			# ---- landing on the cloth ----
			var tl := (vz[i] + sqrt(maxf(vz[i] * vz[i] + 2.0 * G * hz[i], 0.0))) / G
			if tl < best_t:
				best_t = tl
				best = [tl, 4, i, -1]
		# ---- balls ----
		for j in n:
			if j == i or st[j] == ST_POCKETED:
				continue
			if st[j] == ST_MOVING and j < i:
				continue  # pair handled when i was the lower moving index
			var d: Vector2 = pos[j] - pi
			var dv: Vector2 = vel[j] - vi
			var lim := R2 + reach + dv.length() * best_t + 1e-6
			if d.length_squared() > lim * lim:
				continue
			var bq := d.dot(dv)
			var c := d.length_squared() - R2sq
			var aq := dv.length_squared()
			if air_i or (n_air > 0 and (hz[j] > 0.0 or vz[j] != 0.0)):
				var dzz: float = hz[j] - hz[i]
				var dvz: float = vz[j] - vz[i]
				bq += dzz * dvz
				c += dzz * dzz
				aq += dvz * dvz
			if bq >= 0.0:
				continue  # separating
			var t := 0.0
			if c > 0.0:
				var disc := bq * bq - aq * c
				if disc < 0.0 or aq < 1e-14:
					continue
				t = (-bq - sqrt(disc)) / aq
				if t < 0.0:
					t = 0.0
			if t < best_t:
				best_t = t
				best = [t, 1, i, j]
		# ---- cushions & jaws (only near the edges) ----
		var near_edge := absf(pi.x) > a_edge - R - reach - 0.002 or absf(pi.y) > b_edge - R - reach - 0.002
		if near_edge and air_i and hz[i] > cushion_top * R:
			near_edge = false   # flying over the cushions
		if near_edge:
			for si in table.segments.size():
				var sg: Dictionary = table.segments[si]
				var nrm: Vector2 = sg["n"]
				var vn := vi.dot(nrm)
				if vn >= 0.0:
					continue
				var s0 := (pi - (sg["a"] as Vector2)).dot(nrm)
				if s0 < -R * 0.5:
					continue  # behind this segment
				var t := (R - s0) / vn
				if t < 0.0:
					t = 0.0 if s0 < R else INF
				if t >= best_t:
					continue
				var hit := pi + vi * t
				var u := (hit - (sg["a"] as Vector2)).dot(sg["dir"] as Vector2)
				if u < 0.0 or u > float(sg["len"]):
					continue
				best_t = t
				best = [t, 2, i, si]
			for pi_idx in table.points.size():
				var t := _toi_point(pi, vi, table.points[pi_idx], R, best_t)
				if t < best_t:
					best_t = t
					best = [t, 3, i, pi_idx]
	best[0] = best_t
	return best


func _toi_point(p: Vector2, v: Vector2, c: Vector2, rad: float, t_max: float) -> float:
	var d := p - c
	var bq := d.dot(v)
	if bq >= 0.0:
		return INF
	var cc := d.length_squared() - rad * rad
	var reach := rad + v.length() * t_max
	if d.length_squared() > reach * reach:
		return INF
	if cc <= 0.0:
		return 0.0
	var aq := v.length_squared()
	var disc := bq * bq - aq * cc
	if disc < 0.0:
		return INF
	var t := (-bq - sqrt(disc)) / aq
	return t if t >= 0.0 else 0.0


func _resolve(ev: Array) -> void:
	match int(ev[1]):
		1: _collide_balls(ev[2], ev[3])
		4:
			var i: int = ev[2]
			var v_in := maxf(-vz[i], 0.0)
			hz[i] = 0.0
			_set_air(i, 0.0, 0.0)
			_bed_impulse(i, v_in, e_table)
		2:
			var sg: Dictionary = table.segments[ev[3]]
			_collide_wall(ev[2], sg["n"], e_jaw if sg["jaw"] else _cushion_e(ev[2], sg["n"]), mu_cushion, true)
		3:
			var nrm := (pos[ev[2]] - table.points[ev[3]]).normalized()
			_collide_wall(ev[2], nrm, e_jaw, mu_cushion * 0.5, true)


func _cushion_e(i: int, nrm: Vector2) -> float:
	var vn := absf(vel[i].dot(nrm))
	return clampf(e_cushion + 0.06 - 0.025 * vn, 0.55, 0.92)


func _collide_balls(i: int, j: int) -> void:
	if n_air > 0 and (is_airborne(i) or is_airborne(j)):
		_collide_balls_3d(i, j)
		return
	var d: Vector2 = pos[j] - pos[i]
	var dist := d.length()
	if dist < 1e-9:
		return
	var nrm := d / dist
	var vi: Vector2 = vel[i]
	var vj: Vector2 = vel[j]
	var vn := (vi - vj).dot(nrm)
	if vn <= 0.0:
		return
	var jn := 0.5 * (1.0 + e_ball) * vn          # per-unit-mass normal impulse
	vi -= nrm * jn
	vj += nrm * jn
	# tangential (throw) — contact point surface velocities
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var wi: Vector3 = spin[i]
	var wj: Vector3 = spin[j]
	var ui := Vector3(vi.x, 0.0, vi.y) + wi.cross(n3 * R)
	var uj := Vector3(vj.x, 0.0, vj.y) + wj.cross(-n3 * R)
	var rel := ui - uj
	var rel_t := rel - n3 * rel.dot(n3)
	rel_t.y = 0.0
	var rl := rel_t.length()
	if rl > 1e-7:
		var tt := rel_t / rl
		var jt := minf(_mu_ball(rl) * jn, rl / 7.0)
		vi -= Vector2(tt.x, tt.z) * jt
		vj += Vector2(tt.x, tt.z) * jt
		var dw := n3.cross(-tt) * (jt / (0.4 * R))
		wi += dw
		wj += dw
	vel[i] = vi; vel[j] = vj
	spin[i] = wi; spin[j] = wj
	if st[j] != ST_MOVING:
		st[j] = ST_MOVING
	# rules bookkeeping
	if kind[i] == K_CUE and first_hit < 0:
		first_hit = j
	elif kind[j] == K_CUE and first_hit < 0:
		first_hit = i
	_emit({"type": "ball", "a": i, "b": j, "speed": vn})


## Ball-ball friction vs sliding speed: mu = a + b * exp(-c * v)  (Alciatore, TP A-14), scaled so that
## mu(1 m/s) == mu_ball.
func _mu_ball(slide: float) -> float:
	return mu_ball * (0.00995 + 0.108 * exp(-1.088 * slide)) / 0.04637


func _collide_balls_3d(i: int, j: int) -> void:
	var n3 := Vector3(pos[j].x - pos[i].x, hz[j] - hz[i], pos[j].y - pos[i].y)
	var dist := n3.length()
	if dist < 1e-9:
		return
	n3 /= dist
	var vi := Vector3(vel[i].x, vz[i], vel[i].y)
	var vj := Vector3(vel[j].x, vz[j], vel[j].y)
	var vn := (vi - vj).dot(n3)
	if vn <= 0.0:
		return
	var jn := 0.5 * (1.0 + e_ball) * vn
	vi -= n3 * jn
	vj += n3 * jn
	var wi: Vector3 = spin[i]
	var wj: Vector3 = spin[j]
	var rel := (vi + wi.cross(n3 * R)) - (vj + wj.cross(-n3 * R))
	var rel_t := rel - n3 * rel.dot(n3)
	var rl := rel_t.length()
	if rl > 1e-7:
		var tt := rel_t / rl
		var jt := minf(_mu_ball(rl) * jn, rl / 7.0)
		vi -= tt * jt
		vj += tt * jt
		var dw := n3.cross(-tt) * (jt / (0.4 * R))
		wi += dw
		wj += dw
	vel[i] = Vector2(vi.x, vi.z); vel[j] = Vector2(vj.x, vj.z)
	spin[i] = wi; spin[j] = wj
	for k in [i, j]:
		var vk: float = vi.y if k == i else vj.y
		if hz[k] <= 0.0 and vk < 0.0:
			vk = 0.0   # the slate absorbs a push into the cloth
		_set_air(k, hz[k], vk)
	if st[j] != ST_MOVING:
		st[j] = ST_MOVING
	if st[i] != ST_MOVING:
		st[i] = ST_MOVING
	if kind[i] == K_CUE and first_hit < 0:
		first_hit = j
	elif kind[j] == K_CUE and first_hit < 0:
		first_hit = i
	_emit({"type": "ball", "a": i, "b": j, "speed": vn})


func _collide_wall(i: int, nrm: Vector2, e: float, mu: float, is_cushion: bool) -> void:
	var v: Vector2 = vel[i]
	var vn := v.dot(nrm)
	if vn >= 0.0:
		return
	var jn := -(1.0 + e) * vn
	v += nrm * jn
	# friction at the cushion nose contact point (above the ball centre; lower on the ball when it's airborne)
	var h := clampf(cushion_nose - 1.0, 0.0, 0.6)
	var airborne := n_air > 0 and is_airborne(i)
	if airborne:
		h = clampf(cushion_nose - 1.0 - hz[i] / R, -0.9, 0.6)
	var cos_t := sqrt(maxf(1.0 - h * h, 0.0))
	if airborne:
		# the contact normal tilts with the contact height: below the centre it lifts the ball,
		# above the centre it pushes it down (on the cloth the slate takes that part)
		var vz_new: float = vz[i] - h * jn / maxf(cos_t, 0.3)
		if hz[i] <= 0.0 and vz_new < 0.0:
			vz_new = 0.0
		_set_air(i, hz[i], vz_new)
	var r := Vector3(-nrm.x * cos_t * R, h * R, -nrm.y * cos_t * R)
	var w: Vector3 = spin[i]
	var u := Vector3(v.x, 0.0, v.y) + w.cross(r)
	var t2 := Vector2(-nrm.y, nrm.x)
	var t3 := Vector3(t2.x, 0.0, t2.y)
	var s := u.dot(t3)
	if absf(s) > 1e-7:
		var jt := minf(mu * jn, absf(s) / 3.5) * signf(s)
		var dv := -t3 * jt
		v += Vector2(dv.x, dv.z)
		w += r.cross(dv) / (0.4 * R * R)
	# nose contact eats part of the roll component about the rail axis
	var axis_t := t3
	var roll_t := w.dot(axis_t)
	w -= axis_t * roll_t * 0.25
	vel[i] = v
	spin[i] = w
	if first_hit >= 0:
		cushion_after_contact = true
	if is_cushion:
		_emit({"type": "cushion", "ball": i, "speed": -vn})


func _apply_friction(h: float) -> void:
	for i in n:
		if st[i] != ST_MOVING:
			continue
		if n_air > 0 and (hz[i] > 0.0 or vz[i] != 0.0):
			continue   # ballistic flight (integrated in _drift): no cloth friction, spin is kept
		var v: Vector2 = vel[i]
		var w: Vector3 = spin[i]
		var fm := 1.0
		var ux := v.x + R * w.z
		var uz := v.y - R * w.x
		var ul := sqrt(ux * ux + uz * uz)
		var slide_dec := mu_slide * fm * G * h
		if ul > 1e-4:
			var dvx: float
			var dvz: float
			if ul <= 3.5 * slide_dec:
				dvx = -ux / 3.5
				dvz = -uz / 3.5
			else:
				dvx = -ux / ul * slide_dec
				dvz = -uz / ul * slide_dec
			v.x += dvx
			v.y += dvz
			w.x += -dvz / (0.4 * R)
			w.z += dvx / (0.4 * R)
		else:
			var sp := v.length()
			var dec := mu_roll * fm * G * h
			if sp > dec:
				v = v * ((sp - dec) / sp)
			else:
				v = Vector2.ZERO
			w.x = v.y / R
			w.z = -v.x / R
		# vertical spin decay
		var sd := 5.0 * mu_spin * G / (2.0 * R) * h
		if absf(w.y) <= sd:
			w.y = 0.0
		else:
			w.y -= signf(w.y) * sd
		vel[i] = v
		spin[i] = w
		if v.length_squared() < 2.5e-5 and (w.x * w.x + w.z * w.z) * R * R < 2.5e-5 and absf(w.y) < 0.6:
			vel[i] = Vector2.ZERO
			spin[i] = Vector3.ZERO
			st[i] = ST_REST
			_emit({"type": "rest", "ball": i})


func _post_step(_h: float) -> void:
	for i in n:
		if st[i] != ST_MOVING:
			continue
		var p: Vector2 = pos[i]
		var high := n_air > 0 and hz[i] > 0.6 * R
		# ---- off the table: flew over the cushion and beyond the rail line ----
		if n_air > 0 and hz[i] > 0.0 and (absf(p.x) > table.a + R or absf(p.y) > table.b + R) and not _over_pocket(p):
			_off_table(i)
			continue
		# ---- pockets ----
		if not high and (absf(p.x) > table.a - 3.0 * R or absf(p.y) > table.b - 3.0 * R):
			for pk_i in table.pockets.size():
				var pk: Dictionary = table.pockets[pk_i]
				var rel := p - (pk["mid"] as Vector2)
				var s := rel.dot(pk["axis"])
				if s > float(pk["drop"]) and absf(rel.dot(pk["perp"])) < float(pk["half_w"]) + R:
					_pocket(i, pk_i)
					break
			if st[i] == ST_POCKETED:
				continue
			# escaped through a gap at extreme speed: treat as pocketed in the nearest pocket
			if absf(p.x) > table.a + 2.5 * R or absf(p.y) > table.b + 2.5 * R:
				var best := 0
				var bd := INF
				for pk_i in table.pockets.size():
					var dd := p.distance_squared_to(table.pockets[pk_i]["mid"])
					if dd < bd:
						bd = dd
						best = pk_i
				_pocket(i, best)
				continue
	# ---- overlap repair (numerical safety) ----
	for i in n:
		if st[i] == ST_POCKETED:
			continue
		for j in range(i + 1, n):
			if st[j] == ST_POCKETED:
				continue
			var d: Vector2 = pos[j] - pos[i]
			var dl := d.length()
			if n_air > 0 and absf(hz[i] - hz[j]) > 1e-4:
				continue   # one passes over the other
			if dl < 2.0 * R - 1e-5 and dl > 1e-9:
				var push := (2.0 * R - dl) * 0.5
				var nd := d / dl
				if st[i] == ST_MOVING or st[j] != ST_MOVING:
					pos[i] = pos[i] - nd * push
				if st[j] == ST_MOVING or st[i] != ST_MOVING:
					pos[j] = pos[j] + nd * push


func _over_pocket(p: Vector2) -> bool:
	for pk in table.pockets:
		var rel := p - (pk["mid"] as Vector2)
		if absf(rel.dot(pk["perp"])) < float(pk["half_w"]) + R and rel.dot(pk["axis"]) < 4.0 * R:
			return true
	return false


func _off_table(i: int) -> void:
	st[i] = ST_POCKETED
	pocket_of[i] = OFF_TABLE
	_emit({"type": "off_table", "ball": i, "pos": pos[i], "vel": vel[i], "h": hz[i], "vz": vz[i]})
	vel[i] = Vector2.ZERO
	spin[i] = Vector3.ZERO
	_set_air(i, 0.0, 0.0)


func _pocket(i: int, pk_i: int) -> void:
	st[i] = ST_POCKETED
	pocket_of[i] = pk_i
	_set_air(i, 0.0, 0.0)
	var speed := vel[i].length()
	vel[i] = Vector2.ZERO
	spin[i] = Vector3.ZERO
	_emit({"type": "pocket", "ball": i, "pocket": pk_i, "speed": speed})


func _space_free(p: Vector2, ignore: int) -> bool:
	for j in n:
		if j == ignore or st[j] == ST_POCKETED:
			continue
		if p.distance_squared_to(pos[j]) < 4.0 * R * R:
			return false
	return true


## For ball-in-hand: valid spot (inside cushions, not overlapping other balls)?
func is_spot_free(p: Vector2, ignore := -1) -> bool:
	if not table.in_bounds(p):
		return false
	return _space_free(p, ignore)


func _emit(e: Dictionary) -> void:
	if record_events:
		e["t"] = time
		events.append(e)


# ======================================================================
# Queries
# ======================================================================

func balls_on_table(k := -1) -> Array:
	var out := []
	for i in n:
		if st[i] != ST_POCKETED and (k < 0 or kind[i] == k):
			out.append(i)
	return out


func index_of_number(number: int) -> int:
	for i in n:
		if num[i] == number:
			return i
	return -1


func cue_index() -> int:
	for i in n:
		if kind[i] == K_CUE:
			return i
	return -1


# ======================================================================
# Snapshots (online play, v1.1.14)
# ======================================================================
## The whole table as it is now, exactly (binary, no rounding): each ball's place, state and pocket, and the
## motion of the balls that move. About 30 bytes a ball at rest, 70 moving.
func snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(n)
	for i in n:
		var moving := vel[i] != Vector2.ZERO or spin[i] != Vector3.ZERO or hz[i] != 0.0 or vz[i] != 0.0
		b.put_u8(1 if moving else 0)
		b.put_8(st[i])
		b.put_8(pocket_of[i])
		_put_r(b, pos[i].x)
		_put_r(b, pos[i].y)
		if moving:
			_put_r(b, vel[i].x)
			_put_r(b, vel[i].y)
			_put_r(b, spin[i].x)
			_put_r(b, spin[i].y)
			_put_r(b, spin[i].z)
			b.put_double(hz[i])
			b.put_double(vz[i])
	b.put_8(first_hit)
	b.put_u8(1 if cushion_after_contact else 0)
	return b.data_array


## Takes the table on from a snapshot. Balls that this changes from on the table to in a pocket (or back) are
## listed in path_changed for the game's pictures; path_fixes counts snapshots that changed anything at all.
func _restore(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u8() != n:
		return
	var changed := false
	n_air = 0
	for i in n:
		var moving := b.get_u8() == 1
		var s_new := b.get_8()
		var p_new := b.get_8()
		var p := Vector2(_get_r(b), _get_r(b))
		var v := Vector2.ZERO
		var w := Vector3.ZERO
		var h := 0.0
		var hv := 0.0
		if moving:
			v = Vector2(_get_r(b), _get_r(b))
			w = Vector3(_get_r(b), _get_r(b), _get_r(b))
			h = b.get_double()
			hv = b.get_double()
		if (s_new == ST_POCKETED) != (st[i] == ST_POCKETED):
			path_changed.append(i)
		changed = changed or s_new != st[i] or p != pos[i] or v != vel[i] or w != spin[i] or h != hz[i] or hv != vz[i]
		st[i] = s_new
		pocket_of[i] = p_new
		pos[i] = p
		vel[i] = v
		spin[i] = w
		hz[i] = h
		vz[i] = hv
		if h > 0.0 or hv != 0.0:
			n_air += 1
	first_hit = b.get_8()
	cushion_after_contact = b.get_u8() == 1
	if changed:
		path_fixes += 1


static func _put_r(b: StreamPeerBuffer, x: float) -> void:
	if _wide:
		b.put_double(x)
	else:
		b.put_float(x)


static func _get_r(b: StreamPeerBuffer) -> float:
	return b.get_double() if _wide else b.get_float()
