class_name FillIn
extends RefCounted
## v1.1.15 (Randy: "I want the timer to look for a match to be 1 minute, if it doesn't find a game, they verse a
## cpu, please find a list of 100+ screen names so it feels more natural, dont label the ai opponents ... as cpu").
## When Play Online finds nobody within a minute, the match goes ahead against the game's own AI under a screen
## name, with a level near the player's, its own cue, and its table or balls (as an online opponent brings).
## The match plays and pays like an online match (full XP) and is not counted in the CPU records.

const NAMES := [
	"Marco84", "lily_p", "KevOnCue", "Tomasz_W", "AnaSofia", "Rina", "DeltaJay", "mike.r", "Sven K", "Priya_S",
	"BigBreakBen", "noah.t", "Lucia R", "ChalkDust", "Yusuf", "hannah_b", "Mateo10", "Kenji", "olivia.m", "Rafa_C",
	"SideSpin", "Amara", "jonas.k", "Leila", "GreenFelt", "dmitri", "Chloe P", "Ivan_83", "bankshot_bo", "Emre",
	"sofie_v", "Diego R", "Mia K", "CornerPocket", "Arjun", "tess", "Lukas_M", "Zara", "Nico_B", "eightball_eli",
	"Ines", "Owen T", "Hiro", "Fatima_A", "PeteTheCue", "marta.s", "Liam_O", "Aylin", "Bruno", "Sakura",
	"Theo", "kat_plays", "Andre", "Elif", "Max_R", "Noor", "Carlos", "Jade W", "Felix", "Anya",
	"Sami", "RackEmRoy", "Grace", "Tariq", "Elena V", "Jules", "Kofi", "Vera", "Oscar", "Mei",
	"Daniel K", "Yara", "Hugo", "Nadia", "Leo_P", "Isla", "Mateus", "Aiko", "Ravi", "Sara_L",
	"Viktor", "Lena", "Omar", "Clara", "Jasper", "Thandi", "Matteo", "Rosa", "Kai", "Ingrid",
	"Dev", "Lotte", "Ahmed", "Bianca", "Finn", "Mira", "Joao", "Hana", "Stefan", "Lucy",
	"Arman", "Paula", "Ryo", "Eva", "Kwame", "Signe", "Pablo", "Wren", "Tobias", "Anika",
	"cue_ball_cal", "Ruby", "Dario", "Esra", "Gus", "Linnea", "Malik", "Petra", "Sol", "TopSpinTia",
]


## Every name a stand-in can have: the ones above and (24 Nov 2026, Randy: "please obtain a large username list so it
## makes the cpus look even more human like") the thousands made by tools/name_filter/make_standin_names.py.
## Only stand-ins use them: against the CPU it is still "CPU · Medium".
static var _all: Array = []


static func all_names() -> Array:
	if _all.is_empty():
		_all = NAMES + FillInNames.LIST
	return _all


## A screen name (now and then with a number, as people pick), never the player's own.
## Names the player blocked (24 Nov 2026) are never used again.
static func pick_name(rng: RandomNumberGenerator, own: String) -> String:
	var blocked: Array = Game.progress.get("blocked_names", [])
	var all := all_names()
	for _i in 24:
		var n: String = all[rng.randi_range(0, all.size() - 1)]
		if not (" " in n or "_" in n or "." in n or n[n.length() - 1].is_valid_int()) and rng.randf() < 0.12:
			var num := rng.randi_range(7, 99)
			if num in [13, 14, 18, 69, 88]:
				num += 2
			n += str(num)
		if n.to_lower() != own.to_lower() and not n in blocked:
			return n
	return "Rina"


## How strong the stand-in plays, from the player's level: mostly a fair game.
static func ai_level_for(level: int, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if level < 3:
		return 0 if r < 0.7 else 1
	if level < 10:
		return 0 if r < 0.25 else (1 if r < 0.85 else 2)
	return 1 if r < 0.5 else 2


## Everything the match needs to show the opponent: name, level, cue, table, balls, and who breaks.
static func make(own_name: String, own_level: int, seed_no := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed_no >= 0:
		rng.seed = seed_no
	else:
		rng.randomize()
	var cues: Array = Catalog.ids(Catalog.CUES)
	var tables: Array = Catalog.ids(Catalog.TABLES)
	var balls: Array = Catalog.ids(Catalog.BALLS)
	return {
		"name": pick_name(rng, own_name),
		"level": maxi(0, own_level + rng.randi_range(-3, 3)),
		"ai_level": ai_level_for(own_level, rng),
		"cue": cues[rng.randi_range(0, cues.size() - 1)],
		"table": tables[rng.randi_range(0, tables.size() - 1)],
		"balls": balls[rng.randi_range(0, balls.size() - 1)],
		"they_break": rng.randf() < 0.5,
	}


## ------------------------------------------------------------ how a person aims (24 Nov)
## Randy, 24 Nov: "if a multiplayer match isnt found & people are versing cpu's, I dont want it to look like they are
## versing cpus at all"; "make it so the tuning movements look natural so cpu's playing in place of people (online
## only) dont just aim & fire instantly, they should never run out of time during the match but look realistic, not
## doing movements too fast after eachother, taking their time aiming, angling the stick etc. set minimum and maximum
## random delays between each, moving the stick a little further then back when aiming etc, more time sometimes on
## longer or tricker shots."
## A real online opponent's stick is shown from their own aiming, 15 samples a second ([time, yaw, elevation, tip x,
## tip y, pull]: PoolGame._aim_buf); the stand-in's stick goes through the very same playback, with aiming made the
## way people aim with the Pro Dial: a look at the table, a look at another ball or two, a drag to the shot that goes
## a little past it and comes back, smaller and smaller corrections with pauses between them, the stick raised for a
## jump or masse, the tip moved for spin, the piston drawn back (now and then let go and drawn again), a short hold,
## the stroke. Every pause and every movement has a shortest and a longest time; a long or tricky shot gets more
## thinking and more corrections; and the whole turn fits the time the stand-in has left (PoolGame._standin_budget), so
## it never runs out of time.
const SAMPLE_DT := 1.0 / 15.0
const PAUSE_MIN := 0.35          # between two movements (seconds)
const PAUSE_MAX := 1.1
const MOVE_MIN := 0.25           # the quickest movement of the stick
const LOOK_MIN := 0.6            # looking the table over before touching anything
const LOOK_MAX := 1.6
const TRICKY_EXTRA := 5.0        # at most this much more thinking for the trickiest shot
const LONG_THINK_CHANCE := 0.12  # now and then a long think (reading the table, a glance away)
const LONG_THINK := Vector2(3.0, 8.0)
const PULL_TIME := Vector2(0.6, 1.4)
const HOLD_TIME := Vector2(0.2, 0.7)  # the stick held drawn back before the stroke


static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


static func _pause(rng: RandomNumberGenerator, k := 1.0) -> float:
	return rng.randf_range(PAUSE_MIN, PAUSE_MAX) * k


## Adds one movement to `track` (yaw, elevation, tip and pull from where the last sample is to the given values) and
## returns the time it ends at. `pause` holds the end pose afterwards.
static func _move(track: PackedFloat32Array, t: float, dur: float, yaw: float, tip: Vector2, pull: float, elev: float,
		pause: float) -> float:
	var n := track.size()
	var y0: float = track[n - 5]
	var e0: float = track[n - 4]
	var x0: float = track[n - 3]
	var t0y: float = track[n - 2]
	var p0: float = track[n - 1]
	dur = maxf(dur, SAMPLE_DT)
	var steps := maxi(1, int(ceil(dur / SAMPLE_DT)))
	for i in range(1, steps + 1):
		var k := _ease(float(i) / float(steps))
		track.append_array(PackedFloat32Array([t + dur * float(i) / float(steps), lerp_angle(y0, yaw, k), lerpf(e0, elev, k),
			lerpf(x0, tip.x, k), lerpf(t0y, tip.y, k), lerpf(p0, pull, k)]))
	t += dur
	if pause > 0.0:
		var holds := int(pause / SAMPLE_DT)
		for i in range(1, holds + 1):
			track.append_array(PackedFloat32Array([t + SAMPLE_DT * i, yaw, elev, tip.x, tip.y, pull]))
		t += pause
	return t


## The whole aiming of one shot, starting `start` seconds into the turn. `level` 0-2 (how careful the opponent is);
## `tricky` 0-1 (a long, thin or blocked shot: more thinking, more corrections); `budget` the most seconds this turn
## may take (the stand-in's clock).
static func aim_track(rng: RandomNumberGenerator, from_yaw: float, to_yaw: float, elev: float, tip: Vector2,
		power: float, is_break: bool, level: int, start := 0.0, tricky := 0.3, budget := 60.0) -> PackedFloat32Array:
	tricky = clampf(tricky, 0.0, 1.0)
	var tr := PackedFloat32Array([start, from_yaw, 0.0, 0.0, 0.0, 0.0])
	var t := start
	var yaw := from_yaw
	var slow := 1.0 + 0.5 * tricky          # a tricky shot: slower, more careful pauses
	# a look at the table first (longer for a tricky one)
	var look := rng.randf_range(LOOK_MIN, LOOK_MAX) * (0.6 if is_break else 1.0) + tricky * rng.randf_range(0.0, TRICKY_EXTRA * 0.5)
	t = _move(tr, t, SAMPLE_DT, yaw, Vector2.ZERO, 0.0, 0.0, look)
	# a look at another ball or two (more when the shot is hard to find)
	if not is_break:
		for i in rng.randi_range(0, 1) + (1 if tricky > 0.45 else 0) + (1 if rng.randf() < 0.3 else 0):
			yaw = from_yaw + rng.randf_range(0.15, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
			t = _move(tr, t, rng.randf_range(0.35, 0.8), yaw, Vector2.ZERO, 0.0, 0.0, _pause(rng, slow))
	# now and then a long think
	if not is_break and rng.randf() < LONG_THINK_CHANCE + 0.15 * tricky:
		t = _move(tr, t, SAMPLE_DT, yaw, Vector2.ZERO, 0.0, 0.0, rng.randf_range(LONG_THINK.x, LONG_THINK.y) + tricky * rng.randf_range(0.0, TRICKY_EXTRA * 0.5))
	# the drag to the shot: a little past it, then back
	var dist := absf(wrapf(to_yaw - yaw, -PI, PI))
	var way := signf(wrapf(to_yaw - yaw, -PI, PI))
	if way == 0.0:
		way = 1.0
	# mostly a little too far, then back; now and then a little short, then on
	var past := deg_to_rad(rng.randf_range(0.8, 3.5) + rad_to_deg(dist) * 0.04) * (way if rng.randf() < 0.75 else -way)
	if is_break:
		past *= 0.5
	t = _move(tr, t, clampf(0.35 + 0.45 * dist, MOVE_MIN + 0.1, 1.3), to_yaw + past, Vector2.ZERO, 0.0, 0.0, _pause(rng, slow))
	# smaller and smaller corrections, each a little past and back again sometimes; a careful player and a tricky
	# shot make more of them. The stick is raised (jump, masse) and the tip moved for spin along the way.
	var err := past
	var fixes := rng.randi_range(1, 2 + level) + int(round(tricky * 2.0))
	if is_break:
		fixes = rng.randi_range(1, 2)       # (the break: lined up quickly, the power is what matters)
	var tip_at := rng.randi_range(0, fixes - 1)
	var elev_at := rng.randi_range(0, fixes - 1)
	var cur_tip := Vector2.ZERO
	var cur_elev := 0.0
	for i in fixes:
		var last := i == fixes - 1
		err = 0.0 if last else err * rng.randf_range(-0.45, 0.45)
		if i == tip_at and tip.length() > 0.01:
			cur_tip = tip
		if i == elev_at and elev > 0.01:
			cur_elev = elev
		t = _move(tr, t, rng.randf_range(MOVE_MIN, 0.5), to_yaw + err, cur_tip, 0.0, cur_elev, _pause(rng, slow))
	if cur_tip != tip or cur_elev != elev:
		t = _move(tr, t, rng.randf_range(0.3, 0.5), to_yaw, tip, 0.0, elev, _pause(rng, slow))
	# drawn back - now and then let go and drawn again
	if rng.randf() < 0.13 + 0.1 * tricky:
		t = _move(tr, t, rng.randf_range(0.35, 0.6), to_yaw, tip, power * rng.randf_range(0.3, 0.7), elev, rng.randf_range(0.2, 0.5))
		t = _move(tr, t, rng.randf_range(0.25, 0.4), to_yaw, tip, 0.0, elev, _pause(rng))
	var over := power * rng.randf_range(1.03, 1.08) if rng.randf() < 0.3 else power
	t = _move(tr, t, rng.randf_range(PULL_TIME.x, PULL_TIME.y) * (1.2 if is_break else 1.0), to_yaw, tip, minf(over, 1.0), elev, 0.0)
	if over != power:
		t = _move(tr, t, rng.randf_range(0.15, 0.3), to_yaw, tip, power, elev, 0.0)
	t = _move(tr, t, SAMPLE_DT, to_yaw, tip, power, elev, rng.randf_range(HOLD_TIME.x, HOLD_TIME.y))
	# never longer than the time it has: the whole turn plays faster then (every pause and movement in proportion)
	var total := t - start
	if total > budget and budget > 0.5:
		var k := budget / total
		for i in range(0, tr.size(), 6):
			tr[i] = start + (tr[i] - start) * k
	return tr


## A cue ball taken in hand and dragged to where it goes: [[seconds, position]], ending on `to`.
static func place_path(rng: RandomNumberGenerator, from: Vector2, to: Vector2, start := 0.0) -> Array:
	var out := []
	var t := start + rng.randf_range(0.6, 1.4)
	var p := from
	var legs := rng.randi_range(1, 3)
	for i in legs:
		var q := to if i == legs - 1 else from.lerp(to, rng.randf_range(0.35, 0.85)) + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		var dur := clampf(0.35 + p.distance_to(q) * 0.9, 0.35, 1.3)
		var steps := maxi(2, int(dur / 0.1))
		for s in range(1, steps + 1):
			var k := _ease(float(s) / float(steps))
			out.append([t + dur * float(s) / float(steps), p.lerp(q, k)])
		t += dur + rng.randf_range(0.2, 0.8)
		p = q
	return out
