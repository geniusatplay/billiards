class_name Rack
extends RefCounted
## Standard racks. Foot spot sits at +a/2, head spot at -a/2 (cue ball side).

## Balls frozen (touching), like a tight rack on a real table. Each contact is then resolved at the same instant
## and the hit spreads through the whole rack, so a good break sends balls all over the table. Even a 0.1 mm gap
## turns it into a chain of separate hits that leaves half the rack near the foot spot (tests/break_spread.gd:
## at 13 m/s, 7 of 15 balls stayed near the rack with 0.4 mm gaps, 1-2 when frozen).
const GAP := 0.0


static func foot_spot(s: PoolSim) -> Vector2:
	return Vector2(s.table.a * 0.5, 0.0)


static func head_spot(s: PoolSim) -> Vector2:
	return Vector2(-s.table.a * 0.5, 0.0)


## Triangle slot positions (15), apex on the foot spot, rows growing toward the foot rail.
static func triangle_slots(s: PoolSim) -> PackedVector2Array:
	var R := s.R
	var step := 2.0 * R + GAP
	var dx := step * sqrt(3.0) * 0.5
	var apex := foot_spot(s)
	var out := PackedVector2Array()
	for row in 5:
		for k in row + 1:
			out.append(apex + Vector2(row * dx, (k - row * 0.5) * step))
	return out


static func rack_eight_ball(s: PoolSim, seed_v := 0, cue_pos := Vector2.INF) -> void:
	s.clear_balls()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	s.add_ball(head_spot(s) if cue_pos == Vector2.INF else cue_pos, 0, PoolSim.K_CUE)
	var slots := triangle_slots(s)
	var assign: Array = []
	assign.resize(15)
	assign[4] = 8                          # 8-ball in the centre of row three
	var solid_corner := rng.randi_range(0, 1) == 0
	assign[10] = 1 + rng.randi_range(0, 6) if solid_corner else 9 + rng.randi_range(0, 6)
	assign[14] = (9 + rng.randi_range(0, 6)) if solid_corner else (1 + rng.randi_range(0, 6))
	var rest: Array = []
	for b in range(1, 16):
		if b != 8 and b != assign[10] and b != assign[14]:
			rest.append(b)
	# Fisher-Yates with the seeded RNG (deterministic per seed)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	var ri := 0
	for slot in 15:
		if assign[slot] == null:
			assign[slot] = rest[ri]
			ri += 1
	for slot in 15:
		var number: int = assign[slot]
		s.add_ball(slots[slot], number, PoolSim.K_EIGHT if number == 8 else PoolSim.K_OBJECT)
