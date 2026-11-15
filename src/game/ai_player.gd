class_name AIPlayer
extends RefCounted
## 8-ball opponent: Easy / Medium / Hard.
## Enumerates legal pots with the ShotSolver, simulates them with the real physics, scores pot + position,
## falls back to a safety (Medium/Hard). Difficulty = aim noise + power noise + search breadth + shot types.

const NAMES := ["Easy", "Medium", "Hard"]
## The CPU's own cue at each level (its stick is the one seen on its turns); the second is used when the player
## has the first, so the two players' cues always look different.
const CUES := [["cue_walnut", "cue_rosewood"], ["cue_carbon", "cue_sword_b"], ["cue_skull_c", "cue_dragon_b"]]


static func cue_for(level: int, avoid := "") -> String:
	var pair: Array = CUES[clampi(level, 0, CUES.size() - 1)]
	return pair[1] if pair[0] == avoid else pair[0]
## Per difficulty: aim error (deg, 1 sigma), power error, candidate shots examined.
const AIM_NOISE_DEG := [1.25, 0.42, 0.09]
const POWER_NOISE := [0.09, 0.04, 0.015]
const BREADTH := [6, 14, 22]
## Stop searching once a shot this good is found (pot + decent position).
const GOOD_ENOUGH := [40.0, 50.0, 58.0]

var level := 1
var solver := ShotSolver.new()
var rng := RandomNumberGenerator.new()


func _init(p_level := 1) -> void:
	level = clampi(p_level, 0, 2)
	rng.randomize()


## Thread-safe: works only on the passed simulator clone.
## legal: ball numbers that may be hit first; own: numbers that count as "own" pots; eight_ok: may pot the 8.
func choose(sim: PoolSim, legal: Array, own: Array, eight_ok: bool, is_break: bool) -> Dictionary:
	var cue := sim.cue_index()
	if is_break:
		return {"yaw": rng.randf_range(-0.012, 0.012), "power": 0.92 + 0.08 * level / 2.0, "offset": Vector2(0, -0.08), "elev": 0.0}
	var targets := []
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED and sim.num[i] in legal:
			targets.append(i)
	# Easy only sees straight pots; Medium/Hard also consider banks, kicks and combos.
	var cands := solver.candidates(sim, cue, targets, [], level >= 1)
	var best := {}
	var best_score := -INF
	# Phase 1: quick scan — every candidate line at two speeds, centre ball.
	var scored: Array = []
	var tried := 0
	for cand in cands:
		if tried >= BREADTH[level]:
			break
		tried += 1
		var cand_best := -INF
		var cand_shot := {}
		for pw in ([0.38, 0.55] if level == 0 else [0.32, 0.52]):
			var res := ShotSolver.evaluate(sim, cue, cand["yaw"], pw, Vector2.ZERO, 0.0, true)
			var sc := _score(res, sim, legal, own, eight_ok)
			if sc > cand_best:
				cand_best = sc
				cand_shot = {"yaw": cand["yaw"], "power": pw, "offset": Vector2.ZERO, "elev": 0.0}
		scored.append({"score": cand_best, "shot": cand_shot, "yaw": cand["yaw"]})
		if cand_best > best_score:
			best_score = cand_best
			best = cand_shot
		if best_score >= GOOD_ENOUGH[level] and tried >= 3 and level < 2:
			break
	# Phase 2 (Medium/Hard): refine the most promising lines with spin and more speeds for position play.
	if level >= 1 and not scored.is_empty():
		scored.sort_custom(func(x, y): return x["score"] > y["score"])
		var refine: int = [0, 2, 4][level]
		for k in mini(refine, scored.size()):
			if float(scored[k]["score"]) < 0.0:
				break
			for pw in [0.28, 0.42, 0.6]:
				for sp in [Vector2(0, 0.3), Vector2(0, -0.3), Vector2(0, -0.1)]:
					var res := ShotSolver.evaluate(sim, cue, scored[k]["yaw"], pw, sp, 0.0, true)
					var sc := _score(res, sim, legal, own, eight_ok)
					if sc > best_score:
						best_score = sc
						best = {"yaw": scored[k]["yaw"], "power": pw, "offset": sp, "elev": 0.0}
	if level >= 1 and (best.is_empty() or best_score < 5.0):
		var safe := _safety(sim, legal, own, eight_ok)
		if not safe.is_empty() and (best.is_empty() or safe["score"] > best_score):
			best = safe
	if best.is_empty():
		best = {"yaw": rng.randf() * TAU, "power": 0.4, "offset": Vector2.ZERO, "elev": 0.0}
	# human-like imperfection
	best["yaw"] = float(best["yaw"]) + deg_to_rad(rng.randfn(0.0, AIM_NOISE_DEG[level]))
	best["power"] = clampf(float(best["power"]) * (1.0 + rng.randfn(0.0, POWER_NOISE[level])), 0.05, 1.0)
	return best


func _score(res: Dictionary, sim: PoolSim, legal: Array, own: Array, eight_ok: bool) -> float:
	var s: PoolSim = res["sim"]
	if res["scratch"]:
		return -200.0
	var first: int = res["first_hit"]
	if first < 0 or not (s.num[first] in legal):
		return -150.0
	var sc := 0.0
	var potted_own := 0
	for p in res["potted"]:
		var nb: int = p["number"]
		if nb == 8:
			if not eight_ok:
				return -1000.0
			sc += 500.0
		elif nb in own:
			potted_own += 1
		else:
			sc -= 8.0
	if potted_own == 0 and res["potted"].is_empty() and not res["rail_after"]:
		return -120.0
	sc += potted_own * 40.0
	if potted_own > 0:
		var remaining := []
		for i in s.n:
			if s.st[i] != PoolSim.ST_POCKETED and (s.num[i] in own or (eight_ok and s.num[i] == 8)):
				remaining.append(i)
		sc += ShotSolver.position_score(s, s.cue_index(), remaining) * (2.0 if level == 2 else 1.0)
	return sc


func _safety(sim: PoolSim, legal: Array, own: Array, eight_ok: bool) -> Dictionary:
	var cue := sim.cue_index()
	var best := {}
	var best_sc := -INF
	for i in sim.n:
		if sim.st[i] == PoolSim.ST_POCKETED or not (sim.num[i] in legal):
			continue
		var base := (sim.pos[i] - sim.pos[cue]).angle()
		for dy in [-0.03, 0.0, 0.03]:
			for pw in [0.22, 0.32]:
				var res := ShotSolver.evaluate(sim, cue, base + dy, pw, Vector2.ZERO, 0.0, true)
				var sc := _score(res, sim, legal, own, eight_ok)
				if sc < -100.0:
					continue
				# prefer leaving the cue ball far from the opponent's balls
				var s: PoolSim = res["sim"]
				var opp := []
				for j in s.n:
					if s.st[j] != PoolSim.ST_POCKETED and s.num[j] != 0 and s.num[j] != 8 and not (s.num[j] in own):
						opp.append(j)
				sc -= ShotSolver.position_score(s, s.cue_index(), opp) * 3.0
				if sc > best_sc:
					best_sc = sc
					best = {"yaw": base + dy, "power": pw, "offset": Vector2.ZERO, "elev": 0.0, "score": sc}
	return best


## Ball-in-hand: sample spots and keep the one with the best potting options.
func choose_placement(sim: PoolSim, own: Array) -> Vector2:
	var cue := sim.cue_index()
	var best := sim.pos[cue]
	var best_sc := -INF
	var targets := []
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED and sim.num[i] in own:
			targets.append(i)
	var tries: int = [20, 45, 80][level]
	for k in tries:
		var p := Vector2(rng.randf_range(-sim.table.a + 0.06, sim.table.a - 0.06), rng.randf_range(-sim.table.b + 0.06, sim.table.b - 0.06))
		if not sim.is_spot_free(p, cue):
			continue
		var old: Vector2 = sim.pos[cue]
		sim.pos[cue] = p
		var sc := ShotSolver.position_score(sim, cue, targets)
		sim.pos[cue] = old
		if sc > best_sc:
			best_sc = sc
			best = p
	return best
