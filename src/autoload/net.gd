extends Node
## The link to the game's server (server/eb/api.php on emeraldvortexgames.com). Autoloaded as `Net`.
##
## What goes to the server: a random player id with its key, the player's name, level progress (XP, owned
## gear, unopened packages) and, during an online match, the shots. Nothing else. The game works without it:
## when the phone is offline, progress simply stays on the phone and is sent the next time.
## v1.1.13 (Randy): an account - email + password - is the player's id on every phone. The server keeps the
## password only as a hash; the phone keeps the email and its own key (never the password).

const URL := "https://emeraldvortexgames.com/eb/api.php"
## Tests point the game at a server on this computer instead (e.g. "http://127.0.0.1:8765/eb/api.php").
var url := URL
## Online version: only players with the same one are matched. Bump it when a match between this version and the
## one before could go wrong (rules, physics, what is sent). Before v1.1.13 the full game version was used, so
## two phones a patch apart (new songs, new gear) never met. net3 (v1.1.14): aiming is sent as samples, a shot
## carries its path, events are numbered; a 1.1.13 phone would also strike a late-reported shot twice.
const ONLINE_VERSION := "net5"     # (net4, 22 Nov: the break starts one ball behind the head string; net5, 24 Nov: the ready-up)

var fake = null            # tests: an object with handle(action, body) -> Dictionary instead of the real server
var last_error := ""
var _save_in := -1.0
var _saving := false
## v1.1.14: kept-open connections ("lanes") for the requests of matchmaking and of a match. Opening a secure
## connection costs about 0.25 s each time; a request on an open one about 0.07 s (measured on the server).
## Each lane carries one request at a time, in order; "poll" and "send" have one each so they never wait for
## each other.
var _lanes := {}
var lane_opened := 0        # connections opened (tests: kept-open lanes open far fewer than requests made)
var lane_requests := 0
var allow_headless := false # tests: talk to a local test server even in a run without a screen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.progress_changed.connect(func(): _save_in = 4.0)
	if registered() and not OS.get_cmdline_user_args().has("--offline"):
		_pull_when_drawn()
	if not OS.get_cmdline_user_args().has("--offline"):
		_version_when_drawn()


func _version_when_drawn() -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	check_version()


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


## One call to the server. Always returns a Dictionary with "ok"; never throws. `lane`: send it on that kept-open
## connection (matchmaking and match traffic); "" = a fresh connection (everything else, a few times a session).
func api(action: String, body: Dictionary = {}, lane := "") -> Dictionary:
	var parsed = null
	if fake != null:
		await get_tree().process_frame
		parsed = fake.handle(action, body)
	else:
		if OS.get_cmdline_user_args().has("--offline") or (DisplayServer.get_name() == "headless" and not allow_headless):
			return {"ok": false, "error": "offline"}
		var text = null
		if lane != "":
			text = await _lane_call(lane, action, JSON.stringify(body))
		else:
			var req := HTTPRequest.new()
			req.timeout = 8.0
			add_child(req)
			var err := req.request(url + "?a=" + action, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
			if err != OK:
				req.queue_free()
				last_error = "offline"
				return {"ok": false, "error": "offline"}
			var res: Array = await req.request_completed
			req.queue_free()
			if int(res[0]) == HTTPRequest.RESULT_SUCCESS:
				text = (res[3] as PackedByteArray).get_string_from_utf8()
		if text == null:
			last_error = "offline"
			return {"ok": false, "error": "offline"}
		# an empty or broken reply (a dropped connection, a server hiccup) counts as "no answer", quietly
		var reader := JSON.new()
		parsed = reader.data if reader.parse(str(text)) == OK else null
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


# ---------------------------------------------------------------- store updates (v1.1.15)
## Randy: "please make sure if there is a needed update, the people have to update it from the store". The server
## keeps one small file (server/eb/version.json) that says which version is the oldest still allowed, and where each
## store page is. Changing "min" there makes every older copy of the game ask for the update.
const VERSION_URL := "https://emeraldvortexgames.com/eb/version.json"
const PLAY_ID := "com.emeraldvortexgames.emeraldbreak"
const PLAY_URL := "https://play.google.com/store/apps/details?id=" + PLAY_ID
## The share link (Randy's landing page: it sends phones to their store, computers see both).
const SHARE_URL := "https://emeraldvortexgames.com/eb/get/"
const PRIVACY_URL := "https://emeraldvortexgames.com/eb/privacy/"
var store_info := {}        # version.json as last read ({} = not read)
var update_needed := false
signal update_required

## Reads version.json (a fresh copy each time, never a cached one). Offline or unreadable: nothing changes.
func check_version() -> void:
	var info: Dictionary = {}
	if fake != null and fake.has_method("version_info"):
		await get_tree().process_frame
		info = fake.version_info()
	else:
		if OS.get_cmdline_user_args().has("--offline") or DisplayServer.get_name() == "headless":
			return
		var req := HTTPRequest.new()
		req.timeout = 8.0
		add_child(req)
		if req.request(VERSION_URL + "?t=%d" % int(Time.get_unix_time_from_system())) != OK:
			req.queue_free()
			return
		var res: Array = await req.request_completed
		req.queue_free()
		if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
			return
		var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		info = parsed
	store_info = info
	if version_less(Game.VERSION, str(info.get("min", "0"))):
		update_needed = true
		update_required.emit()


## "1.1.9" < "1.1.15" (number by number).
static func version_less(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x < y
	return false


## The game's page in this phone's store: the Play Store app on Android, the App Store on iPhone (its address comes
## from version.json once the App Store has given the game its number), the web page anywhere else.
func store_url() -> String:
	match OS.get_name():
		"Android":
			return "market://details?id=" + PLAY_ID
		"iOS":
			return str(store_info.get("ios", ""))
	return str(store_info.get("web", SHARE_URL))


func open_store() -> void:
	var u := store_url()
	if u == "":
		u = SHARE_URL
	if OS.shell_open(u) != OK and OS.get_name() == "Android":
		OS.shell_open(PLAY_URL)       # (no Play Store app: the web page)


# ---------------------------------------------------------------- kept-open connections (v1.1.14)
class Lane extends RefCounted:
	var client := HTTPClient.new()
	var busy := false
	var to := ""            # the server the open connection goes to


func _parts() -> Dictionary:
	var u := url
	var tls := u.begins_with("https://")
	u = u.trim_prefix("https://").trim_prefix("http://")
	var slash := u.find("/")
	var hostport := u.substr(0, slash) if slash >= 0 else u
	var path := u.substr(slash) if slash >= 0 else "/"
	var port := 443 if tls else 80
	if ":" in hostport:
		port = int(hostport.get_slice(":", 1))
		hostport = hostport.get_slice(":", 0)
	return {"tls": tls, "host": hostport, "port": port, "path": path}


func _lane(name: String) -> Lane:
	if not _lanes.has(name):
		_lanes[name] = Lane.new()
	return _lanes[name]


## Opens a lane's connection ahead of its first request (a match's first "aim" then goes straight out).
func warm(name: String) -> void:
	if fake != null or OS.get_cmdline_user_args().has("--offline") or (DisplayServer.get_name() == "headless" and not allow_headless):
		return
	var ln := _lane(name)
	if ln.busy:
		return
	ln.busy = true
	ln.client.poll()
	if ln.client.get_status() == HTTPClient.STATUS_DISCONNECTED:
		await _lane_connect(ln, _parts())
	ln.busy = false


## One request on a lane: the reply's text, or null. A connection the server (or the phone network) has closed
## since the last request is noticed when the request fails; it is then reopened and the request made once more.
## (A repeated "send" can reach the server twice; the other phone drops the copy by its number, see NetMatch.)
func _lane_call(name: String, action: String, body: String):
	var ln := _lane(name)
	while ln.busy:
		await get_tree().process_frame
	ln.busy = true
	lane_requests += 1
	var parts := _parts()
	var text = await _lane_try(ln, parts, action, body)
	if text == null:
		ln.client.close()
		text = await _lane_try(ln, parts, action, body)
		if text == null:
			ln.client.close()
	ln.busy = false
	return text


func _lane_connect(ln: Lane, parts: Dictionary) -> bool:
	ln.client.close()
	lane_opened += 1
	ln.to = "%s:%d" % [parts["host"], parts["port"]]
	var tls_opt: TLSOptions = TLSOptions.client() if parts["tls"] else null
	if ln.client.connect_to_host(parts["host"], parts["port"], tls_opt) != OK:
		return false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		ln.client.poll()
		var st := ln.client.get_status()
		if st == HTTPClient.STATUS_CONNECTED:
			return true
		if st != HTTPClient.STATUS_RESOLVING and st != HTTPClient.STATUS_CONNECTING:
			return false
		await get_tree().process_frame
	return false


func _lane_try(ln: Lane, parts: Dictionary, action: String, body: String):
	ln.client.poll()
	if ln.client.get_status() != HTTPClient.STATUS_CONNECTED or ln.to != "%s:%d" % [parts["host"], parts["port"]]:
		if not await _lane_connect(ln, parts):
			return null
	if ln.client.request(HTTPClient.METHOD_POST, str(parts["path"]) + "?a=" + action, ["Content-Type: application/json"], body) != OK:
		return null
	var t0 := Time.get_ticks_msec()
	var got := PackedByteArray()
	var expect := -1
	while true:
		if Time.get_ticks_msec() - t0 > 8000:
			return null
		ln.client.poll()
		var st := ln.client.get_status()
		if st == HTTPClient.STATUS_REQUESTING:
			await get_tree().process_frame
			continue
		if st == HTTPClient.STATUS_BODY:
			expect = ln.client.get_response_body_length()
			var chunk := ln.client.read_response_body_chunk()
			if chunk.is_empty():
				await get_tree().process_frame
			else:
				got.append_array(chunk)
			continue
		if st == HTTPClient.STATUS_CONNECTED:
			break                  # the whole reply is in; the connection stays open for the next request
		# closed: fine if the whole reply came first (a server may close after replying), otherwise it failed
		if not got.is_empty() and (expect < 0 or got.size() >= expect):
			ln.client.close()
			break
		return null
	if got.is_empty():
		return null
	return got.get_string_from_utf8()


func registered() -> bool:
	return str(Game.progress.get("player", "")) != "" and str(Game.progress.get("token", "")) != ""


func creds() -> Dictionary:
	return {"id": str(Game.progress.get("player", "")), "token": str(Game.progress.get("token", ""))}


## Signed in to an account (an email) on this phone.
func signed_in() -> bool:
	return registered() and email() != ""


func email() -> String:
	return str(Game.progress.get("email", ""))


## 24 Nov 2026: the account's username - the name other players see. "" until it is chosen.
func username() -> String:
	return str(Game.progress.get("username", ""))


## The account has no username yet (made before usernames), or a moderator took it away: the game asks for one.
func need_name() -> bool:
	return signed_in() and (username() == "" or Game.progress.get("need_name", false) == true)


signal name_needed

## Gives the account a new username. Returns the server's reply ({ok} or {error: bad_name + why / name_taken}).
func set_username(name: String, rules := false) -> Dictionary:
	var body := creds()
	body["username"] = NameFilter.tidy(name)
	if rules:
		body["rules"] = true
	var r: Dictionary = await api("set_name", body)
	if r.get("ok", false):
		Game.progress["username"] = str(r.get("username", body["username"]))
		Game.progress["need_name"] = false
		Game.settings["p1_name"] = Game.DEFAULT_NAMES[0]
		Game.progress_changed.emit()
		Game.request_save()
	return r


## Report the other player (target = their player id; reason "name", "cheating" or "other").
func report_player(target: String, reason: String) -> Dictionary:
	var body := creds()
	body["target"] = target
	body["reason"] = reason
	return await api("report", body)


## Never be matched with that player again (either way). Keeps the list on this phone too.
func block_player(target: String, name: String, on := true) -> Dictionary:
	var body := creds()
	body["target"] = target
	var r: Dictionary = await api("block" if on else "unblock", body)
	var local: Dictionary = Game.progress.get("blocked", {})
	if on:
		local[target] = name
	else:
		local.erase(target)
	Game.progress["blocked"] = local
	Game.request_save()
	return r


func is_blocked(target: String) -> bool:
	return (Game.progress.get("blocked", {}) as Dictionary).has(target)


## Creates an account. If this phone has been playing already (it has a player id), that player - and its
## progress - becomes the account's. Returns the server's reply ({ok, error}).
func sign_up(mail: String, password: String, uname := "") -> Dictionary:
	var body := {"email": mail.strip_edges(), "password": password, "name": Game.player_name(0)}
	if uname != "":
		body["username"] = NameFilter.tidy(uname)
		body["rules"] = true          # (the screen says that creating the account agrees to the player rules)
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
		if username() == "" and n != "" and not n in Game.DEFAULT_NAMES and str(Game.get_s("p1_name")) in Game.DEFAULT_NAMES:
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
	Game.progress["username"] = str(r.get("username", ""))
	Game.progress["need_name"] = r.get("need_name", false) == true
	if username() != "":
		Game.settings["p1_name"] = Game.DEFAULT_NAMES[0]     # (the username is the player's name from now on)
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
		"bad_name": return NameFilter.message(str(r.get("why", "words")))
		"name_taken": return NameFilter.message("taken")
		"need_name": return "Choose a username to play online."
		"too_fast": return "Please wait a moment and try again."
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
const SYNCED := ["xp", "owned", "packages", "pk_time", "chest_at", "chest_from", "chest_cut", "matches", "curve", "tutorial", "gifts", "share_day"]


## Copies the progress to the server (a few seconds after it last changed).
func push_progress() -> void:
	if _saving:
		_save_in = 2.0
		return
	_saving = true
	if await ensure_player():
		var body := creds()
		body["name"] = username() if username() != "" else Game.player_name(0)
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
	if signed_in():
		# the account's username as the server has it (a moderator may have taken it away: then choose a new one)
		Game.progress["username"] = str(r.get("username", ""))
		Game.progress["need_name"] = r.get("need_name", false) == true
		Game.request_save()
		if need_name():
			name_needed.emit()
	var p: Dictionary = r["progress"]
	# v1.1.15: what pays once per player is kept whichever copy is ahead (the tutorial's chest, today's share chest)
	if p.get("tutorial", false) == true and not Game.tutorial_done():      # (null in a copy that never had it)
		Game.progress["tutorial"] = true
		Game.request_save()
	if str(p.get("share_day", "")) > str(Game.progress.get("share_day", "")):
		Game.progress["share_day"] = str(p["share_day"])
		Game.request_save()
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
		var r: Dictionary = await api("ping", {}, "poll")     # (also opens the lane matchmaking and the match use)
		if r.get("ok", false):
			times.append(Time.get_ticks_msec() - t0)
	if times.is_empty():
		return 9999
	times.sort()
	return int(times[times.size() / 2])
