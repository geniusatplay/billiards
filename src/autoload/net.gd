extends Node
## The link to the game's server (server/eb/api.php on emeraldvortexgames.com). Autoloaded as `Net`.
##
## What goes to the server: a random player id with its key, the player's name, level progress (XP, owned
## gear, unopened packages) and, during an online match, the shots. Nothing else. The game works without it:
## when the phone is offline, progress simply stays on the phone and is sent the next time.
## v1.1.13 (Randy): an account - email + password - is the player's id on every phone. The server keeps the
## password only as a hash; the phone keeps the email and its own key (never the password).

const URL := "https://emeraldvortexgames.com/eb/api.php"
## Online version: only players with the same one are matched. Bump it when a match between this version and the
## one before could go wrong (rules, physics, what is sent). Before v1.1.13 the full game version was used, so
## two phones a patch apart (new songs, new gear) never met.
const ONLINE_VERSION := "net2"

var fake = null            # tests: an object with handle(action, body) -> Dictionary instead of the real server
var last_error := ""
var _save_in := -1.0
var _saving := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.progress_changed.connect(func(): _save_in = 4.0)
	if registered() and not OS.get_cmdline_user_args().has("--offline"):
		_pull_when_drawn()


## The first frames of a launch can take seconds (the table's shaders are built then). A request started before
## them would sit unanswered and fail, so the progress is fetched once the game is actually drawing.
func _pull_when_drawn() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	pull_progress()


func _process(delta: float) -> void:
	if _save_in >= 0.0:
		_save_in -= delta
		if _save_in < 0.0:
			push_progress()


## One call to the server. Always returns a Dictionary with "ok"; never throws.
func api(action: String, body: Dictionary = {}) -> Dictionary:
	var parsed = null
	if fake != null:
		await get_tree().process_frame
		parsed = fake.handle(action, body)
	else:
		if OS.get_cmdline_user_args().has("--offline") or DisplayServer.get_name() == "headless":
			return {"ok": false, "error": "offline"}
		var req := HTTPRequest.new()
		req.timeout = 8.0
		add_child(req)
		var err := req.request(URL + "?a=" + action, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			req.queue_free()
			last_error = "offline"
			return {"ok": false, "error": "offline"}
		var res: Array = await req.request_completed
		req.queue_free()
		if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
			last_error = "offline"
			return {"ok": false, "error": "offline"}
		# an empty or broken reply (a dropped connection, a server hiccup) counts as "no answer", quietly
		var reader := JSON.new()
		parsed = reader.data if reader.parse((res[3] as PackedByteArray).get_string_from_utf8()) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "bad reply"
		return {"ok": false, "error": "bad reply"}
	if not parsed.get("ok", false):
		last_error = str(parsed.get("error", ""))
		if last_error == "unknown player" and action != "register":
			# the server no longer knows this install (its data was reset): sign up afresh on the next call
			Game.progress["player"] = ""
			Game.progress["token"] = ""
			Game.progress.erase("email")
			Game.request_save()
	return parsed


func registered() -> bool:
	return str(Game.progress.get("player", "")) != "" and str(Game.progress.get("token", "")) != ""


func creds() -> Dictionary:
	return {"id": str(Game.progress.get("player", "")), "token": str(Game.progress.get("token", ""))}


## Signed in to an account (an email) on this phone.
func signed_in() -> bool:
	return registered() and email() != ""


func email() -> String:
	return str(Game.progress.get("email", ""))


## Creates an account. If this phone has been playing already (it has a player id), that player - and its
## progress - becomes the account's. Returns the server's reply ({ok, error}).
func sign_up(mail: String, password: String) -> Dictionary:
	var body := {"email": mail.strip_edges(), "password": password, "name": Game.player_name(0)}
	if registered():
		body.merge(creds())
	var r: Dictionary = await api("signup", body)
	if r.get("ok", false):
		_use_account(r)
		push_progress()
	return r


## Logs this phone in to an account: from now on it plays as that account's player. Of the two copies of the
## progress (the account's on the server, this phone's) the one further along is kept, as at every start.
func log_in(mail: String, password: String) -> Dictionary:
	var r: Dictionary = await api("login", {"email": mail.strip_edges(), "password": password})
	if r.get("ok", false):
		_use_account(r)
		var n := str(r.get("name", ""))
		if n != "" and not n in Game.DEFAULT_NAMES and str(Game.get_s("p1_name")) in Game.DEFAULT_NAMES:
			Game.store_player_name(0, n)
		await pull_progress()
		push_progress()
	return r


## Signs this phone out. The progress stays with the account (log in again to get it back); the phone starts
## afresh as a new, anonymous player.
func log_out() -> void:
	if registered():
		api("logout", creds())
	_forget_account()


## Deletes the account for good (the server asks for the password once more).
func delete_account(password: String) -> Dictionary:
	var body := creds()
	body["password"] = password
	var r: Dictionary = await api("delete_account", body)
	if r.get("ok", false):
		_forget_account()
	return r


func _use_account(r: Dictionary) -> void:
	Game.progress["player"] = str(r["id"])
	Game.progress["token"] = str(r["token"])
	Game.progress["email"] = str(r.get("email", ""))
	Game.request_save()


func _forget_account() -> void:
	_save_in = -1.0
	Game.progress = Game.fresh_progress()
	Game._fix_gear()
	Game.progress_changed.emit()
	Game.request_save()


## The words for a reply's error, for the account screens.
static func account_error(r: Dictionary) -> String:
	match str(r.get("error", "")):
		"bad_email": return "That doesn't look like an email address."
		"short_password": return "The password needs at least 6 characters."
		"email_taken": return "There is already an account with this email. Log in instead."
		"wrong_login": return "Wrong email or password."
		"too_many_tries": return "Too many wrong passwords. Try again in 15 minutes."
	return "The game server cannot be reached. Check your internet connection and try again."


## Makes sure this install has a player id on the server. False when the server cannot be reached.
func ensure_player() -> bool:
	if registered():
		return true
	var r: Dictionary = await api("register", {"name": Game.player_name(0)})
	if not r.get("ok", false):
		return false
	Game.progress["player"] = str(r["id"])
	Game.progress["token"] = str(r["token"])
	Game.request_save()
	return true


## The parts of Game.progress kept on the server.
const SYNCED := ["xp", "owned", "packages", "pk_time", "chest_at", "chest_from", "chest_cut", "matches", "curve"]


## Copies the progress to the server (a few seconds after it last changed).
func push_progress() -> void:
	if _saving:
		_save_in = 2.0
		return
	_saving = true
	if await ensure_player():
		var body := creds()
		body["name"] = Game.player_name(0)
		body["progress"] = {}
		for k in SYNCED:
			body["progress"][k] = Game.progress.get(k)
		await api("save", body)
	_saving = false


## At start-up: if the server holds more progress than this phone (same player id), take it.
func pull_progress() -> void:
	var r: Dictionary = await api("load", creds())
	if not r.get("ok", false) or typeof(r.get("progress")) != TYPE_DICTIONARY:
		return
	var p: Dictionary = r["progress"]
	if int(p.get("xp", 0)) > Game.xp():
		Game.progress.erase("curve")              # a copy saved by a version before v1.1.7 has none
		for k in SYNCED:
			if p.has(k):
				Game.progress[k] = p[k]
		Game.progress["xp"] = int(Game.progress["xp"])
		if typeof(Game.progress.get("pk_time")) != TYPE_DICTIONARY:
			Game.progress["pk_time"] = {}          # an empty one can come back as [] from older servers
		var q: Array = []
		for l in Game.progress.get("packages", []):
			q.append(int(l))
		Game.progress["packages"] = q
		if int(Game.progress.get("curve", 1)) < 2:
			Game.migrate_levels_117()               # that copy still has the 100-level numbering
		Game.progress_changed.emit()
		Game.request_save()
		_save_in = -1.0


## How fast this phone reaches the server, in milliseconds (the middle one of three tries; 9999 = not at all).
func measure_ping() -> int:
	var times: Array = []
	for i in 3:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await api("ping")
		if r.get("ok", false):
			times.append(Time.get_ticks_msec() - t0)
	if times.is_empty():
		return 9999
	times.sort()
	return int(times[times.size() / 2])
