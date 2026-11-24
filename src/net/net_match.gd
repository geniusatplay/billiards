class_name NetMatch
extends Node
## One online match, as seen from this phone: it sends this player's events to the server and collects the
## other player's. Events arrive in the order they were sent and are never lost while the match lasts.
##
## The events (see PoolGame): "aim" (how the cue moved: 15 samples a second, sent in small batches), "place"
## (cue ball in hand), "shot" (the exact stroke, the last moment of aiming, and the path: snapshots of the
## shooter's table while the balls ran), "result" (how the shot ended: every ball, the rules, the clocks),
## "over" (the match ended some other way: time ran out, or a player left).
## v1.1.14: every event carries a number ("q"), so one that arrives twice (a request repeated after a dropped
## connection) is only used once; the two kinds of request each keep their own connection to the server open
## (Net.api lanes), which makes each one about four times quicker than opening a new secure connection.

var match_id := 0
var seat := 0              # 0 breaks
var host := false          # this phone has the faster connection: it is the match's referee
var opp_id := ""           # the other player's id (report / block)
var match_seed := 0        # both phones rack the balls from this
var opp := {}              # the other player: name, level, cue
var fast := false          # poll quickly (waiting for the other player's shot)
var opp_seen := 0.0        # seconds since the other phone last asked the server for news
var over := false
var silent := 0.0          # seconds since the server last answered at all

var _in: Array = []
var _after := 0
var _t := 0.0
var _polling := false
var _out: Array = []
var _sending := false
var _seq := 0              # this phone's events, numbered
var _last_q := 0           # the other phone's last event taken in
var dropped := 0           # repeated events left out (tests, log)


static func from_reply(r: Dictionary) -> NetMatch:
	var m := NetMatch.new()
	m.match_id = int(r.get("match", 0))
	m.seat = int(r.get("seat", 0))
	m.host = bool(r.get("host", false))
	m.match_seed = int(r.get("seed", 1))
	m.opp = r.get("opp", {})
	m.opp_id = str(r.get("opp_id", ""))      # (24 Nov 2026: to report or block them)
	return m


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.warm("send")          # the first "aim" of the match finds its connection open


## Queue an event for the other player. Numbers travel exactly (binary), so both tables stay identical.
func send(type: String, data: Dictionary) -> void:
	fill(reserve(type), data)


## Keeps a place in the queue for an event whose data is not ready yet (the shot, while its path is worked out
## on another thread): nothing after it goes out before it, so the other phone always gets them in order.
func reserve(type: String) -> Array:
	var it := [type, null]
	_out.append(it)
	return it


func fill(it: Array, data: Dictionary) -> void:
	_seq += 1
	data["q"] = _seq
	it[1] = Marshalls.variant_to_base64(data)
	_pump()


func _pump() -> void:
	if _sending:
		return
	_sending = true
	while not _out.is_empty() and is_inside_tree() and _out[0][1] != null:
		var it: Array = _out[0]
		var body := Net.creds()
		body["match"] = match_id
		body["type"] = it[0]
		body["data"] = it[1]
		var r: Dictionary = await Net.api("send", body, "send")
		if not is_inside_tree():
			return
		if r.get("ok", false):
			_out.pop_front()
		else:
			await get_tree().create_timer(1.0).timeout
	_sending = false


## The match is finished with on this phone: send what is still waiting, then go away.
func close() -> void:
	set_process(false)
	var waited := 0.0
	while is_inside_tree() and not _out.is_empty() and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if is_inside_tree():
		queue_free()


## The other player's events that arrived since the last call, oldest first: [{"type", "data"}].
func take() -> Array:
	var a := _in
	_in = []
	return a


## Takes only the other player's events of one type (the ready-up before the match, 24 Nov 2026: "ready",
## "cancel"); everything else stays for the match. How many there were.
func take_type(type: String) -> int:
	var n := 0
	var keep := []
	for e in _in:
		if str(e["type"]) == type:
			n += 1
		else:
			keep.append(e)
	_in = keep
	return n


func _process(delta: float) -> void:
	silent += delta
	_t -= delta
	if _t <= 0.0 and not _polling:
		# while the other player aims or shoots, ask often (each ask takes ~0.1 s on the kept-open connection)
		_t = 0.45 if fast else 1.5
		_poll()


func _poll() -> void:
	_polling = true
	var body := Net.creds()
	body["match"] = match_id
	body["after"] = _after
	var r: Dictionary = await Net.api("poll", body, "poll")
	if not is_inside_tree():
		return
	if r.get("ok", false):
		silent = 0.0
		for e in r.get("events", []):
			_after = maxi(_after, int(e["n"]))
			var d = Marshalls.base64_to_variant(str(e["data"])) if typeof(e["data"]) == TYPE_STRING else {}
			if typeof(d) != TYPE_DICTIONARY:
				d = {}
			if d.has("q"):
				if int(d["q"]) <= _last_q:
					dropped += 1
					continue        # the same event again (its request was repeated): already taken in
				_last_q = int(d["q"])
			_in.append({"type": str(e["type"]), "data": d})
		opp_seen = float(r.get("opp_seen", 0))
		over = bool(r.get("over", false))
	_polling = false


## A fingerprint of the table (which balls are down, where the others lie), taken the moment the balls stop.
## Two phones that played the same stroke get the same number; if they ever do not, the report corrects it.
static func table_sum(sim: PoolSim) -> int:
	return hash(var_to_bytes([sim.st, sim.pos]))


## How a finished shot is described to the other phone: every ball, the rules, the clocks.
static func pack_result(sim: PoolSim, rules: EightBall, clocks: Array, r: Dictionary, shot_no: int, rest_sum := 0) -> Dictionary:
	return {"n": shot_no, "sum": rest_sum, "pos": sim.pos.duplicate(), "st": sim.st.duplicate(), "pocket": sim.pocket_of.duplicate(), "rules": rules.to_dict(),
		"clocks": [float(clocks[0]), float(clocks[1])], "foul": bool(r.get("foul", false)), "keep": bool(r.get("keep_turn", false))}


## Makes this phone's table and rules exactly what the shooter's phone reported.
static func apply_result(d: Dictionary, sim: PoolSim, rules: EightBall, clocks: Array) -> void:
	var pos: PackedVector2Array = d.get("pos", PackedVector2Array())
	var st: PackedInt32Array = d.get("st", PackedInt32Array())
	var pk: PackedInt32Array = d.get("pocket", PackedInt32Array())
	if pos.size() == sim.n and st.size() == sim.n:
		for i in sim.n:
			sim.pos[i] = pos[i]
			sim.st[i] = st[i]
			sim.vel[i] = Vector2.ZERO
			sim.spin[i] = Vector3.ZERO
			sim.hz[i] = 0.0
			sim.vz[i] = 0.0
			if pk.size() == sim.n:
				sim.pocket_of[i] = pk[i]
		sim.n_air = 0
	if typeof(d.get("rules")) == TYPE_DICTIONARY:
		rules.from_dict(d["rules"])
	var c: Array = d.get("clocks", [])
	if c.size() == 2:
		clocks[0] = float(c[0])
		clocks[1] = float(c[1])


# ---------------------------------------------------------------- the path of a shot (v1.1.14)
## Snapshot spacing in substeps (240 a second): close together in the first half second, where a break has most
## of its collisions, then every quarter second.
const PATH_EARLY := 24
const PATH_LATE := 60
const PATH_MAX_BYTES := 10000       # compressed; with base64 and the rest of the event it stays under the server's 20,000 characters


## Plays a just-struck table on to rest (on its own copy, on a thread) the way this phone's match will play it,
## and returns snapshots of it on the way: {"path": compressed bytes, "plen": their size, "end": last step}.
## The other phone takes each snapshot on at the same step of its replay.
static func make_path(struck: PoolSim) -> Dictionary:
	var s := struck.clone()
	s.record_events = false
	s.step_no = 0
	var snaps := {0: s.snapshot()}
	var steps := 0
	while s.is_moving() and steps < 25 * 240:
		s._substep(s.substep)
		steps += 1
		var every := PATH_EARLY if steps <= 120 else PATH_LATE
		if steps % every == 0 or not s.is_moving():
			snaps[steps] = s.snapshot()
	var keys: Array = snaps.keys()
	keys.sort()
	var out := _pack_path(snaps, keys, steps)
	while out["path"].size() > PATH_MAX_BYTES and keys.size() > 3:
		# a very long shot: keep every other snapshot (never the first or the last)
		var thin := [keys[0]]
		for k in range(1, keys.size() - 1):
			if k % 2 == 0:
				thin.append(keys[k])
		thin.append(keys[keys.size() - 1])
		keys = thin
		out = _pack_path(snaps, keys, steps)
	return out


static func _pack_path(snaps: Dictionary, keys: Array, end_step: int) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.put_u32(end_step)
	b.put_u16(keys.size())
	for k in keys:
		var d: PackedByteArray = snaps[k]
		b.put_u32(k)
		b.put_u16(d.size())
		b.put_data(d)
	var raw := b.data_array
	return {"path": raw.compress(FileAccess.COMPRESSION_DEFLATE), "plen": raw.size(), "end": end_step}


## Gives a replay the shooter's snapshots (from make_path's data, as it came in a "shot" event).
static func use_path(sim: PoolSim, d: Dictionary) -> bool:
	drop_path(sim)
	if typeof(d.get("path")) != TYPE_PACKED_BYTE_ARRAY or int(d.get("plen", 0)) <= 0:
		return false
	var raw: PackedByteArray = (d["path"] as PackedByteArray).decompress(int(d["plen"]), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(d["plen"]):
		return false
	var b := StreamPeerBuffer.new()
	b.data_array = raw
	var end_step := b.get_u32()
	var count := b.get_u16()
	var got_path := {}
	for _i in count:
		var k := b.get_u32()
		var size := b.get_u16()
		var got: Array = b.get_data(size)
		if int(got[0]) != OK:
			return false
		got_path[k] = got[1]
	sim.path = got_path
	sim.path_end = end_step
	return true


## Back to normal (this phone's own shots, practice): no snapshots.
static func drop_path(sim: PoolSim) -> void:
	sim.path = {}
	sim.path_end = -1
	sim.path_changed.clear()
