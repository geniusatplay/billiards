extends Node
## Analytics and crash reports through Firebase (Google Analytics for Firebase + Crashlytics). Autoloaded as `Analytics`.
##
## Randy, 27 Nov 2026: "prepare firebase & events like this" (his launch notes: Firebase, Crashlytics, about ten custom
## events, the same event names in the pool and the soccer game with game and mode as parameters, no event per shot,
## consent first in Europe, Data safety / privacy labels). Firebase project emerald-8-ball-pool-515719 (Spark plan);
## config files in firebase/ (google-services.json, GoogleService-Info.plist), built into the apps by
## tools/build_apk.py (Android string resources) and ios_plugin/ci.sh (iPhone).
##
## The native side is the EmeraldAR plugin (Android: FirebaseBridge.java, iPhone: emerald_ar.mm, both calling Firebase's
## own libraries). Without the plugin (desktop, the editor, an older build) every call only prints "[analytics] ..."
## and keeps the event in `recent` (the tours check the events there).
##
## Consent: nothing is collected until the player's choice is known where the law asks for one (the EEA, the UK and
## Switzerland, from the phone's region): the "Help improve the game" question at the first launch. Everywhere else
## collection is on, and Settings → "Share anonymous usage and crash data" turns it off for everyone. Firebase runs with
## collection off until then (the apps' manifest / Info.plist say so), no advertising ID, no user id.
##
## Event names and parameters (docs/ANALYTICS.md has the full list and the reports to watch). Every event carries
## game = "pool". Parameter values are short strings or numbers; names are Firebase-legal (letters, digits, _).

const GAME := "pool"
## Firebase limits: 40 characters for event and parameter names, 100 for string values, 25 parameters.
const NAME_MAX := 40
const VALUE_MAX := 100
const PARAMS_MAX := 25
## The EEA (EU + Iceland, Liechtenstein, Norway), the UK and Switzerland: ask before collecting.
const CONSENT_REGIONS := ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
	"LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "GB", "UK", "CH"]
## The custom dimensions registered in Google Analytics (Admin → Custom definitions), so these show in reports.
const DIMENSIONS := ["game", "mode", "ar", "opponent", "result", "outcome", "reason", "phase", "placement", "screen"]

## Kept for the tours and the debug menu: the last events, newest last ([name, params]).
var recent: Array = []
var _plugin: Object = null
var _native := false
## The match being played: when it started (msec) and what it is, for match_end / match_quit.
var _match := {}
var _search_t := 0
var _lobby_t := 0
var _ar_t := 0
var _pending: Array = []


func _ready() -> void:
	_apply()
	if OS.get_name() in ["Android", "iOS"]:
		# Firebase is reached once the game is up (not while it boots: the first frames are left alone), and again a
		# little later if the plugin isn't registered yet
		for k in 20:
			await get_tree().create_timer(2.0 if k == 0 else 0.5).timeout
			if _connect():
				break
		if _native and collecting():
			for e in _pending:
				_plugin.call("analyticsLog", e[0], e[1])
		_pending.clear()
		print("[analytics] Firebase %s, consent %s, collecting %s" % ["in this build" if _native else "not in this build",
			str(Game.get_s("analytics_consent")), str(collecting())])
		_apply()


## Finds the plugin's Firebase side; true when it is there.
func _connect() -> bool:
	if _native:
		return true
	if not Engine.has_singleton("EmeraldAR"):
		return false
	_plugin = Engine.get_singleton("EmeraldAR")
	# (called, not looked up with has_method: Android's plugin doesn't list its methods; an older build answers null)
	_native = Net.yes(_plugin.call("analyticsAvailable"))
	return _native


# ------------------------------------------------------------------ consent
## Tests: a region to pretend the phone has ("" = the phone's own).
static var test_region := ""


## The phone's region ("US", "DE", ... or "" when the phone doesn't say).
static func region() -> String:
	if test_region != "":
		return test_region
	var loc := OS.get_locale()
	var parts := loc.replace("-", "_").split("_")
	for i in range(1, parts.size()):
		var p := parts[i].to_upper()
		if p.length() == 2 and p == parts[i]:
			return p
	return ""


## Must the player be asked before anything is collected? (A phone that names no region is asked too.)
static func consent_region() -> bool:
	var r := region()
	return r == "" or r in CONSENT_REGIONS


## The first-launch question is due: asking region, nothing chosen yet.
func needs_asking() -> bool:
	return consent_region() and str(Game.get_s("analytics_consent")) == ""


## Are events and crash reports being sent?
func collecting() -> bool:
	var c := str(Game.get_s("analytics_consent"))
	if c == "no":
		return false
	if c == "yes":
		return true
	return not consent_region()       # outside the asking regions: on until the player turns it off


## The player's answer (the question, or the Settings switch): "yes" or "no".
func set_consent(yes: bool) -> void:
	Game.set_s("analytics_consent", "yes" if yes else "no")
	_apply()
	if yes:
		log_event("analytics_consent", {"granted": 1})


func _apply() -> void:
	var on := collecting()
	if _native:
		_plugin.call("analyticsSetEnabled", on)
	if OS.get_name() in ["Android", "iOS"]:
		print("[analytics] collection %s" % ("on" if on else "off"))


# ------------------------------------------------------------------ events
## Logs one event. Names and values are trimmed to Firebase's limits; bools become 1 / 0. Nothing leaves the phone
## while collection is off (the event is still kept in `recent` for the tours, marked as not sent).
func log_event(event: String, params := {}) -> void:
	var p := {"game": GAME}
	for k in params:
		if p.size() >= PARAMS_MAX:
			break
		var v: Variant = params[k]
		if v is bool:
			v = 1 if v else 0
		elif v is float:
			v = snappedf(v, 0.01)
		elif not (v is int):
			v = str(v).left(VALUE_MAX)
		p[_clean(str(k))] = v
	var ev := _clean(event)
	var sent := collecting()
	recent.append([ev, p, sent])
	if recent.size() > 200:
		recent.pop_front()
	if sent and _native:
		_plugin.call("analyticsLog", ev, JSON.stringify(p))
	elif sent and _plugin == null and OS.get_name() in ["Android", "iOS"] and _pending.size() < 50:
		_pending.append([ev, JSON.stringify(p)])       # (logged before Firebase was reached: sent once it is)
	if OS.is_debug_build() or not _native:
		print("[analytics] %s %s%s" % [ev, JSON.stringify(p), "" if sent else " (not sent: collection off)"])


## The last logged event of this name ([] when none), for the tours.
func last(event: String) -> Array:
	for i in range(recent.size() - 1, -1, -1):
		if recent[i][0] == event:
			return recent[i]
	return []


func count(event: String) -> int:
	var n := 0
	for e in recent:
		if e[0] == event:
			n += 1
	return n


func _clean(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
	if out == "" or not (out[0] >= "a" and out[0] <= "z"):
		out = "e_" + out
	return out.left(NAME_MAX)


## A line in the crash report's log (Crashlytics breadcrumbs): what the player was doing before a crash.
func crash_note(text: String) -> void:
	if _native and collecting():
		_plugin.call("crashlyticsLog", text.left(200))


# ------------------------------------------------------------------ the game's moments (called from the game)
## mode: "solo" (against the CPU), "online", "local" (pass and play), "practice"; opponent: "cpu", "human", "bot"
## (the online stand-in), "local", "none".
func match_start(mode: String, ar: bool, opponent: String, extra := {}) -> void:
	_match = {"t": Time.get_ticks_msec(), "mode": mode, "ar": ar, "opponent": opponent}
	var p := {"mode": mode, "ar": "on" if ar else "off", "opponent": opponent}
	p.merge(extra)
	log_event("match_start", p)
	crash_note("match_start %s ar=%s %s" % [mode, ar, opponent])


func match_seconds() -> int:
	return 0 if _match.is_empty() else int((Time.get_ticks_msec() - int(_match["t"])) / 1000)


## result: "win", "loss", "draw" (pass and play: "p1_win" / "p2_win"), "abandoned"; stats: shots, fouls, balls_potted...
func match_end(result: String, stats := {}) -> void:
	if _match.is_empty():
		return
	var p := {"mode": _match["mode"], "ar": "on" if _match["ar"] else "off", "opponent": _match["opponent"],
		"result": result, "seconds": match_seconds()}
	p.merge(stats)
	log_event("match_end", p)
	_match = {}


## The player left a match before its end (score: their balls potted / the other side's).
func match_quit(score := {}) -> void:
	if _match.is_empty():
		return
	var p := {"mode": _match["mode"], "seconds": match_seconds()}
	p.merge(score)
	log_event("match_quit", p)
	match_end("abandoned", score)


func in_match() -> bool:
	return not _match.is_empty()


func matchmaking_start(mode := "online") -> void:
	_search_t = Time.get_ticks_msec()
	log_event("matchmaking_start", {"mode": mode})


## outcome: "matched", "cancelled", "timeout", "error"; opponent: "human" or "bot".
func matchmaking_result(outcome: String, opponent := "") -> void:
	if _search_t == 0:
		return
	var p := {"outcome": outcome, "wait_seconds": int((Time.get_ticks_msec() - _search_t) / 1000)}
	if opponent != "":
		p["opponent"] = opponent
	log_event("matchmaking_result", p)
	_search_t = 0


func lobby_joined(opponent: String) -> void:
	_lobby_t = Time.get_ticks_msec()
	log_event("lobby_joined", {"opponent": opponent})


## reason: "ready" (both ready, the match starts), "auto_start" (the countdown ran out), "quit", "opponent_left".
func lobby_left(reason: String) -> void:
	if _lobby_t == 0:
		return
	log_event("lobby_left", {"reason": reason, "seconds": int((Time.get_ticks_msec() - _lobby_t) / 1000)})
	_lobby_t = 0


func connection_lost(phase: String, was_host: bool, reconnected := false) -> void:
	var secs := match_seconds() if phase == "match" else (int((Time.get_ticks_msec() - _lobby_t) / 1000) if _lobby_t > 0 else 0)
	log_event("connection_lost", {"phase": phase, "seconds": secs, "was_host": was_host, "reconnected": reconnected})


## AR: the walk-around camera started ("granted") or the phone refused it ("denied").
var _camera_logged := ""


func camera_permission(granted: bool) -> void:
	var r := "granted" if granted else "denied"
	if _camera_logged == r:
		return
	_camera_logged = r
	log_event("camera_permission_result", {"result": r})


## AR: looking for a spot for the table starts (ar_placement then says how it went).
func ar_placing() -> void:
	_ar_t = Time.get_ticks_msec()


func ar_placement(success: bool, placement := "") -> void:
	if _ar_t == 0:
		return
	var p := {"success": success, "seconds": int((Time.get_ticks_msec() - _ar_t) / 1000)}
	if placement != "":
		p["placement"] = placement
	log_event("ar_placement", p)
	_ar_t = 0


## AR on or off, and why: "player_choice", "device_unsupported", "placement_failed", "camera_denied".
func ar_mode_set(on: bool, reason: String) -> void:
	log_event("ar_mode_set", {"ar": "on" if on else "off", "reason": reason})
