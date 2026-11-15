class_name NetMatch
extends Node
## One online match, as seen from this phone: it sends this player's events to the server and collects the
## other player's. Events arrive in the order they were sent and are never lost while the match lasts.
##
## The events (see PoolGame): "aim" (where the cue points, a few times a second), "place" (cue ball in hand),
## "shot" (the exact stroke), "result" (how the shot ended: every ball, the rules, the clocks), "over" (the
## match ended some other way: time ran out, or a player left).

var match_id := 0
var seat := 0              # 0 breaks
var host := false          # this phone has the faster connection: it is the match's referee
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


static func from_reply(r: Dictionary) -> NetMatch:
	var m := NetMatch.new()
	m.match_id = int(r.get("match", 0))
	m.seat = int(r.get("seat", 0))
	m.host = bool(r.get("host", false))
	m.match_seed = int(r.get("seed", 1))
	m.opp = r.get("opp", {})
	return m


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Queue an event for the other player. Numbers travel exactly (binary), so both tables stay identical.
func send(type: String, data: Dictionary) -> void:
	_out.append([type, Marshalls.variant_to_base64(data)])
	_pump()


func _pump() -> void:
	if _sending:
		return
	_sending = true
	while not _out.is_empty() and is_inside_tree():
		var it: Array = _out[0]
		var body := Net.creds()
		body["match"] = match_id
		body["type"] = it[0]
		body["data"] = it[1]
		var r: Dictionary = await Net.api("send", body)
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
	while is_inside_tree() and not _out.is_empty() and waited < 6.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if is_inside_tree():
		queue_free()


## The other player's events that arrived since the last call, oldest first: [{"type", "data"}].
func take() -> Array:
	var a := _in
	_in = []
	return a


func _process(delta: float) -> void:
	silent += delta
	_t -= delta
	if _t <= 0.0 and not _polling:
		_t = 0.6 if fast else 1.5
		_poll()


func _poll() -> void:
	_polling = true
	var body := Net.creds()
	body["match"] = match_id
	body["after"] = _after
	var r: Dictionary = await Net.api("poll", body)
	if not is_inside_tree():
		return
	if r.get("ok", false):
		silent = 0.0
		for e in r.get("events", []):
			_after = maxi(_after, int(e["n"]))
			var d = Marshalls.base64_to_variant(str(e["data"])) if typeof(e["data"]) == TYPE_STRING else {}
			_in.append({"type": str(e["type"]), "data": d if typeof(d) == TYPE_DICTIONARY else {}})
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
