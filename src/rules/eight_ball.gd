class_name EightBall
extends RefCounted
## Plain-language 8-ball rules for two players (pass-and-play or vs AI).

enum Group { NONE = -1, SOLIDS = 0, STRIPES = 1 }

var current := 0
var groups := [Group.NONE, Group.NONE]
var is_break := true
var ball_in_hand := false
var winner := -1
var win_reason := ""
var last_message := ""
var last_foul := false
var pocketed_by := [[], []]


## The whole state as plain data (an online match sends it to the other phone after every shot).
func to_dict() -> Dictionary:
	return {"current": current, "groups": groups.duplicate(), "is_break": is_break, "ball_in_hand": ball_in_hand, "winner": winner,
		"win_reason": win_reason, "last_foul": last_foul, "pocketed_by": [pocketed_by[0].duplicate(), pocketed_by[1].duplicate()]}


func from_dict(d: Dictionary) -> void:
	current = int(d.get("current", current))
	var g: Array = d.get("groups", groups)
	groups = [int(g[0]), int(g[1])]
	is_break = bool(d.get("is_break", is_break))
	ball_in_hand = bool(d.get("ball_in_hand", ball_in_hand))
	winner = int(d.get("winner", winner))
	win_reason = str(d.get("win_reason", win_reason))
	last_foul = bool(d.get("last_foul", last_foul))
	var pb: Array = d.get("pocketed_by", pocketed_by)
	pocketed_by = [(pb[0] as Array).duplicate(), (pb[1] as Array).duplicate()]


static func group_of(number: int) -> int:
	if number >= 1 and number <= 7:
		return Group.SOLIDS
	if number >= 9 and number <= 15:
		return Group.STRIPES
	return Group.NONE


static func group_name(g: int) -> String:
	return L.t("Solids" if g == Group.SOLIDS else ("Stripes" if g == Group.STRIPES else "Open"))


## "You're on solids" / "You're on stripes" as one sentence (word order differs between languages).
static func on_group_text(g: int) -> String:
	return L.t("You're on solids" if g == Group.SOLIDS else "You're on stripes")


func open_table() -> bool:
	return groups[0] == Group.NONE


func remaining_of(sim: PoolSim, g: int) -> int:
	var c := 0
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED and group_of(sim.num[i]) == g:
			c += 1
	return c


## Which ball numbers may the current player legally hit first?
func legal_targets(sim: PoolSim, player := -1) -> Array:
	var p := current if player < 0 else player
	var out := []
	var g: int = groups[p]
	if g == Group.NONE:
		for i in sim.n:
			if sim.st[i] != PoolSim.ST_POCKETED and sim.num[i] != 0 and sim.num[i] != 8:
				out.append(sim.num[i])
		return out
	if remaining_of(sim, g) == 0:
		return [8]
	for i in sim.n:
		if sim.st[i] != PoolSim.ST_POCKETED and group_of(sim.num[i]) == g:
			out.append(sim.num[i])
	return out


## Evaluate a finished shot. `potted` = ball numbers pocketed this shot (in order),
## `jumped` = ball numbers that left the table (object balls are re-spotted by the caller).
## Returns {foul, keep_turn, message, game_over, respot_eight}
func evaluate(sim: PoolSim, first_hit_number: int, potted: Array, rail_after_contact: bool, jumped: Array = []) -> Dictionary:
	var shooter := current
	var cue_potted := 0 in potted
	var eight_potted := 8 in potted
	var legal_before := legal_targets_before
	var foul := false
	var reason := ""
	if cue_potted:
		foul = true
		reason = "Scratch!"
	elif 0 in jumped:
		foul = true
		reason = "Cue ball off the table!"
	elif not jumped.is_empty():
		foul = true
		reason = "Ball off the table (re-spotted)."
	elif first_hit_number < 0:
		foul = true
		reason = "No ball hit"
	elif not is_break and not (first_hit_number in legal_before):
		foul = true
		reason = "Wrong ball first"
	elif not is_break and potted.is_empty() and not rail_after_contact:
		foul = true
		reason = "No rail after contact"
	# "kind": who the message is for. "praise" and "group" speak to the shooter; "foul" concerns both players.
	var result := {"foul": foul, "keep_turn": false, "message": "", "game_over": false, "respot_eight": false, "kind": "", "shooter": shooter}
	# ---- jumping the 8 off the table loses the game (re-spotted if it happens on the break)
	if 8 in jumped:
		if is_break:
			result["respot_eight"] = true
		else:
			winner = 1 - shooter
			win_reason = "8-ball off the table"
			result["game_over"] = true
			result["message"] = win_reason
			last_message = win_reason
			return result
	# ---- 8-ball outcomes
	if eight_potted:
		if is_break:
			result["respot_eight"] = true
			reason = (L.t(reason) + " " if reason != "" else "") + L.t("8 on the break — re-spotted.")
		else:
			var g: int = groups[shooter]
			var cleared := g != Group.NONE and remaining_of(sim, g) == 0
			winner = shooter if (cleared and not foul) else 1 - shooter
			win_reason = "Sank the 8!" if winner == shooter else ("8-ball scratch" if cue_potted else ("8-ball too early" if not cleared else "Foul on the 8"))
			result["game_over"] = true
			result["message"] = win_reason
			result["xp_eight"] = winner == shooter
			last_message = win_reason
			return result
	# ---- group assignment on an open table
	var own_potted := 0
	if open_table() and not is_break and not foul:
		for nb in potted:
			var g := group_of(nb)
			if g != Group.NONE:
				groups[shooter] = g
				groups[1 - shooter] = 1 - g
				reason = on_group_text(g)
				result["kind"] = "group"
				break
	for nb in potted:
		if nb == 0 or nb == 8:
			continue
		var gg := group_of(nb)
		pocketed_by[shooter].append(nb)
		if groups[shooter] == Group.NONE or gg == groups[shooter]:
			own_potted += 1
	if is_break:
		var any_obj := false
		for nb in potted:
			if nb != 0 and nb != 8:
				any_obj = true
		result["keep_turn"] = any_obj and not foul
	else:
		result["keep_turn"] = own_potted > 0 and not foul
	is_break = false
	result["foul"] = foul
	result["xp_balls"] = 0 if foul else own_potted    # what the shot is worth in XP (see xp.gd)
	ball_in_hand = foul
	last_foul = foul
	if not result["keep_turn"]:
		current = 1 - current
	if foul:
		result["message"] = L.t("Foul — %s Ball in hand.") % L.t(reason)
		result["kind"] = "foul"
	elif reason != "":
		result["message"] = reason
	elif result["keep_turn"]:
		result["message"] = "Nice! Shoot again."
		result["kind"] = "praise"
	last_message = result["message"]
	return result


## The notice a player should see for a shot result. `shooter_is_here`: the shot was taken on this phone by
## someone playing here; `viewer` is the seat (0 / 1) of the player on this phone when it was not.
## Praise belongs to the shooter only, so an opponent's "Nice! Shoot again." is never shown. When the
## opponent claims a group, you are told your own group instead. Fouls concern both players.
func notice_for(result: Dictionary, shooter_is_here: bool, viewer := 0) -> String:
	var msg := str(result.get("message", ""))
	if shooter_is_here:
		return msg
	match str(result.get("kind", "")):
		"praise":
			return ""
		"group":
			return on_group_text(groups[viewer])
	return msg


var legal_targets_before: Array = []


func legal_before_contains(number: int) -> bool:
	return number in legal_targets_before


## Call right before the shot is struck so the "first hit" rule uses the pre-shot state.
func snapshot_before_shot(sim: PoolSim) -> void:
	legal_targets_before = legal_targets(sim)


func timeout(player: int) -> void:
	winner = 1 - player
	win_reason = "Time ran out"
