class_name ShotSolver
extends RefCounted
## Candidate-shot generation + physical evaluation (the AI opponent's brain).

const POWERS := [0.24, 0.34, 0.46, 0.6, 0.78]
const SPINS := [Vector2(0, 0), Vector2(0, 0.3), Vector2(0, -0.3), Vector2(0, -0.12)]

var max_variants_per_candidate := 2   # stop trying powers/spins after this many good results


## ---------------------------------------------------------------- geometry
static func pocket_aim(sim: PoolSim, pk_i: int, lateral := 0.0) -> Vector2:
	var pk: Dictionary = sim.table.pockets[pk_i]
	return (pk["mid"] as Vector2) + (pk["axis"] as Vector2) * (0.3 * sim.R) + (pk["perp"] as Vector2) * (lateral * float(pk["half_w"]))


static func ghost(sim: PoolSim, obj: Vector2, toward: Vector2) -> Vector2:
	return obj - (toward - obj).normalized() * 2.0 * sim.R


## Is the straight path a->b clear of balls (excluding `ignore` indices) with clearance `rad`?
static func path_clear(sim: PoolSim, a: Vector2, b: Vector2, ignore: Array, rad: float) -> bool:
	var d := b - a
	var l := d.length()
	if l < 1e-6:
		return true
	var u := d / l
	for j in sim.n:
		if sim.st[j] == PoolSim.ST_POCKETED or j in ignore:
			continue
		var rel: Vector2 = sim.pos[j] - a
		var along := rel.dot(u)
		if along < 0.0 or along > l:
			continue
		if absf(rel.cross(u)) < rad:
			return false
	return true


static func mirror_lines(sim: PoolSim) -> Array:
	var R := sim.R
	var a := sim.table.a - R
	var b := sim.table.b - R
	return [["x", a], ["x", -a], ["z", b], ["z", -b]]


static func mirror(p: Vector2, line: Array) -> Vector2:
	if line[0] == "x":
		return Vector2(2.0 * float(line[1]) - p.x, p.y)
	return Vector2(p.x, 2.0 * float(line[1]) - p.y)


## Candidate aim directions (yaw) for potting `targets` (ball indices). Each: {yaw, kind, target, pocket, prio}
func candidates(sim: PoolSim, cue_i: int, targets: Array, allow_pockets := [], with_banks := true) -> Array:
	var out: Array = []
	var C: Vector2 = sim.pos[cue_i]
	var R := sim.R
	var pockets := allow_pockets if not allow_pockets.is_empty() else range(sim.table.pockets.size())
	for t in targets:
		var T: Vector2 = sim.pos[t]
		for pk_i in pockets:
			for lat in [0.0, -0.35, 0.35]:
				var Pa := pocket_aim(sim, pk_i, lat)
				var G := ghost(sim, T, Pa)
				var shot := G - C
				if shot.length() < 1e-4:
					continue
				var cut := absf(rad_to_deg(shot.angle_to(Pa - T)))
				if cut < 82.0:
					var clear := path_clear(sim, C, G, [cue_i, t], 2.0 * R) and path_clear(sim, T, Pa, [t, cue_i], 2.0 * R)
					out.append({"yaw": shot.angle(), "kind": "direct", "target": t, "pocket": pk_i,
						"prio": (0.0 if clear else 60.0) + cut * 0.5 + (C.distance_to(G) + T.distance_to(Pa)) * 6.0 + absf(lat) * 4.0})
				if not with_banks or lat != 0.0:
					continue
				# kick: cue ball off one cushion into the ghost position
				for ln in mirror_lines(sim):
					var Gm := mirror(G, ln)
					var ks := Gm - C
					out.append({"yaw": ks.angle(), "kind": "kick", "target": t, "pocket": pk_i,
						"prio": 90.0 + cut * 0.5 + ks.length() * 6.0})
				# bank: object ball off one cushion into the pocket
				for ln in mirror_lines(sim):
					var Pm := mirror(Pa, ln)
					var Gb := ghost(sim, T, Pm)
					var bs := Gb - C
					var bcut := absf(rad_to_deg(bs.angle_to(Pm - T)))
					if bcut < 75.0:
						out.append({"yaw": bs.angle(), "kind": "bank", "target": t, "pocket": pk_i,
							"prio": 70.0 + bcut * 0.6 + (bs.length() + T.distance_to(Pm)) * 6.0})
		# combinations: hit target t into another ball u that drops
		if with_banks:
			for u in targets:
				if u == t:
					continue
				var U: Vector2 = sim.pos[u]
				for pk_i in pockets:
					var Pa2 := pocket_aim(sim, pk_i)
					var GU := ghost(sim, U, Pa2)
					var GT := ghost(sim, T, GU)
					var cs := GT - C
					if absf(rad_to_deg(cs.angle_to(GU - T))) < 60.0 and absf(rad_to_deg((GU - T).angle_to(Pa2 - U))) < 60.0:
						out.append({"yaw": cs.angle(), "kind": "combo", "target": u, "pocket": pk_i,
							"prio": 80.0 + cs.length() * 6.0 + T.distance_to(GU) * 10.0})
	out.sort_custom(func(x, y): return x["prio"] < y["prio"])
	return out


## Simulate one shot on a clone. Returns a result dictionary.
## fast = half-rate physics (AI look-ahead): ~2x cheaper, still far more accurate than the AI's own aim noise.
static func evaluate(sim: PoolSim, cue_i: int, yaw: float, power: float, offset: Vector2, elev := 0.0, fast := false) -> Dictionary:
	var s := sim.clone()
	if fast:
		s.substep = 1.0 / 120.0
	s.record_events = true
	s.events.clear()
	s.strike(cue_i, yaw, power, offset, elev)
	s.run_to_rest(25.0)
	var potted: Array = []
	for e in s.events:
		if e["type"] == "pocket":
			potted.append({"number": s.num[e["ball"]], "pocket": e["pocket"], "index": e["ball"]})
	return {"sim": s, "potted": potted, "scratch": s.st[cue_i] == PoolSim.ST_POCKETED,
		"first_hit": s.first_hit, "rail_after": s.cushion_after_contact, "cue_pos": s.pos[cue_i]}


## Number of clear direct pots available for the cue ball at its current spot (position-play heuristic).
static func position_score(sim: PoolSim, cue_i: int, targets: Array) -> float:
	var C: Vector2 = sim.pos[cue_i]
	var best := 0.0
	var count := 0
	for t in targets:
		if sim.st[t] == PoolSim.ST_POCKETED:
			continue
		var T: Vector2 = sim.pos[t]
		for pk_i in sim.table.pockets.size():
			var Pa := pocket_aim(sim, pk_i)
			var G := ghost(sim, T, Pa)
			var cut := absf(rad_to_deg((G - C).angle_to(Pa - T)))
			if cut > 70.0:
				continue
			if not path_clear(sim, C, G, [cue_i, t], 2.0 * sim.R) or not path_clear(sim, T, Pa, [t, cue_i], 2.0 * sim.R):
				continue
			count += 1
			var q := (70.0 - cut) / 70.0 * (1.0 / (1.0 + C.distance_to(G) + T.distance_to(Pa)))
			best = maxf(best, q)
	return best * 10.0 + minf(count, 4) * 0.8
