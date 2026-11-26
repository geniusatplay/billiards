class_name AccountScreen
extends MenuScreens.Screen
## v1.1.13 (Randy: "prompt to create an account with email / password which gets saved locally to the device,
## uploaded to the server which gets stored at the server & counts as the user id").
## Create an account or log in. Shown when the game starts (until this phone is signed in), from Play Online and
## from Settings. The phone keeps the email and its own key; the password goes only to the server, which keeps a
## hash of it. Laid out in two columns so the fields stay above the on-screen keyboard in landscape.
## 24 Nov 2026 (Randy: "when first signing up, they should have the ability to choose their username and be able to
## edit it in settings"): creating an account asks for a username too (checked by NameFilter here and again by the
## server), with the line that creating it agrees to the player rules (both app stores ask for rules players accept
## before others can see what they write). Mode NAME asks only for a username: an account made before usernames, or
## one whose name a moderator took away.

enum Mode { CREATE, LOGIN, NAME }
const RULES_URL := "https://emeraldvortexgames.com/eb/rules/"

var mode := Mode.CREATE
var _user: LineEdit
var _email: LineEdit
var _pass: LineEdit
var _intro: Label
var _msg: Label
var _rules: Control
var _rules_line: Label
var _go: Button
var _switch: Button
var _busy := false
# 24 Nov 2026: sign in with Google, Facebook or Apple (Net.social_sign_in), under the fields
var _social: VBoxContainer
var _social_row: HFlowContainer
var _social_cancel: Button
var _attempt := 0


func _init(p_router: Node = null, start_mode := Mode.CREATE) -> void:
	super(p_router)
	mode = start_mode


func _ready() -> void:
	scrim(0.8)
	header("Your account")
	content(160, 160)
	var card := UIKit.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UIKit.hbox(44)
	card.add_child(row)

	var left := UIKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var top := UIKit.hbox(18)
	top.add_child(IconGlyph.make("user", 52, UIKit.EMERALD))
	_intro = UIKit.label("", "")          # one line, so the fields sit above the on-screen keyboard
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_intro)
	left.add_child(top)
	_user = _field("Username", LineEdit.KEYBOARD_TYPE_DEFAULT)
	_user.name = "AccountUsername"
	_user.max_length = NameWords.MAX_LEN
	_user.text = Net.username()
	_user.text_changed.connect(func(_t: String): _say(""))
	left.add_child(_user)
	_email = _field("Email", LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	_email.name = "AccountEmail"
	_email.text = Net.email()
	left.add_child(_email)
	_pass = _field("Password", LineEdit.KEYBOARD_TYPE_PASSWORD)
	_pass.name = "AccountPassword"
	_pass.secret = true
	left.add_child(_pass)
	_msg = UIKit.label("", "SmallLabel")
	_msg.name = "AccountMessage"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_msg)
	_social = UIKit.vbox(10)
	_social.name = "AccountSocial"
	_social.visible = false
	var orl := UIKit.label("or", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_social.add_child(orl)
	_social_row = HFlowContainer.new()
	_social_row.add_theme_constant_override("h_separation", 14)
	_social_row.add_theme_constant_override("v_separation", 12)
	_social.add_child(_social_row)
	_social_cancel = UIKit.button("Cancel", "GhostButton", "", 300)
	_social_cancel.name = "SocialCancel"
	_social_cancel.visible = false
	_social_cancel.pressed.connect(func():
		Sfx.ui("back")
		Net.cancel_social()
		_attempt += 1              # (the screen is free again at once; the waiting stops on its next look)
		_social_done()
		_say("Sign-in was cancelled.", true))
	_social.add_child(_social_cancel)
	left.add_child(_social)

	var right := UIKit.vbox(16)
	right.custom_minimum_size.x = 480
	row.add_child(right)
	_go = UIKit.button("Create account", "PrimaryButton", "user", 480)
	_go.name = "AccountGo"
	_go.pressed.connect(_submit)
	right.add_child(_go)
	_switch = UIKit.button("I already have an account", "GhostButton", "", 480)
	_switch.pressed.connect(func():
		Sfx.ui("toggle")
		mode = Mode.CREATE if mode == Mode.LOGIN else Mode.LOGIN
		_refresh())
	right.add_child(_switch)
	var later := UIKit.button("Not now", "GhostButton", "", 480)
	later.pressed.connect(func():
		Sfx.ui("back")
		router.call("back"))
	right.add_child(later)
	# "By creating an account you agree to the Player rules." + the rules, one tap away
	var rules := UIKit.vbox(4)
	rules.name = "AccountRules"
	_rules_line = UIKit.label("", "SmallLabel")
	_rules_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_line.custom_minimum_size.x = 480
	rules.add_child(_rules_line)
	var rb := UIKit.button("Player rules", "GhostButton", "flag", 480)
	rb.name = "AccountRulesLink"
	rb.pressed.connect(func(): OS.shell_open(RULES_URL))
	rules.add_child(rb)
	right.add_child(rules)
	_rules = rules
	body.add_child(card)

	_user.text_submitted.connect(func(_t: String):
		if mode == Mode.NAME:
			_submit()
		else:
			_email.grab_focus())
	_email.text_submitted.connect(func(_t: String): _pass.grab_focus())
	_pass.text_submitted.connect(func(_t: String): _submit())
	if mode == Mode.NAME and _user.text == "" and Net.name_suggestion != "":
		_user.text = Net.name_suggestion       # (the server's suggestion after the automatic sign-in)
	_refresh()
	_load_providers()


## The sign-ins the server has switched on, as buttons ("Continue with Google", ...).
func _load_providers() -> void:
	await Net.fetch_providers()
	if not is_inside_tree():
		return
	for c in _social_row.get_children():
		c.queue_free()
	if Net.platform_ready():
		# 26 Nov 2026: the phone's game account first (Google Play Games / Game Center)
		var g := UIKit.button(L.t("Continue with %s") % Net.provider_name(Net.platform()), "", "user", 330)
		g.name = "Social_platform"
		g.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		g.pressed.connect(func(): _social_go("platform"))
		_social_row.add_child(g)
	for p in Net.offered_providers():
		var b := UIKit.button(L.t("Continue with %s") % Net.provider_name(p), "", "user", 330)
		b.name = "Social_" + p
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # (already translated, with the name in it)
		var which: String = p
		b.pressed.connect(func(): _social_go(which))
		_social_row.add_child(b)
	_social.visible = mode != Mode.NAME and _social_row.get_child_count() > 0


func _social_done() -> void:
	_busy = false
	_go.disabled = false
	for b in _social_row.get_children():
		(b as Button).disabled = false
	_social_cancel.visible = false


func _exit_tree() -> void:
	if _social_cancel and _social_cancel.visible:
		Net.cancel_social()          # (left while the browser sign-in was still open)


func _social_go(p: String) -> void:
	if _busy:
		return
	Sfx.ui("tap")
	var typed := NameFilter.tidy(_user.text) if mode == Mode.CREATE else ""
	_busy = true
	_go.disabled = true
	for b in _social_row.get_children():
		(b as Button).disabled = true
	_social_cancel.visible = true
	_say("Signing in…" if Net.social_in_app() else "Finish signing in in your browser, then come back here.")
	DisplayServer.virtual_keyboard_hide()
	_attempt += 1
	var mine := _attempt
	var r: Dictionary
	if p == "platform":
		_social_cancel.visible = false        # (the platform's own screen has its own way out)
		r = await Net.platform_sign_in(true)
		if not r.get("ok", false) and str(r.get("error", "")) == "none":
			r = {"ok": false, "error": "cancelled"}
	else:
		r = await Net.social_sign_in(p, mode == Mode.CREATE)
	if not is_inside_tree() or mine != _attempt:
		return
	_social_done()
	if not r.get("ok", false):
		_say(Net.account_error(r), true)
		return
	if Net.need_name():
		# a new account (or one without a username): the username typed above, or the one the server suggests
		mode = Mode.NAME
		_user.text = typed if typed != "" and NameFilter.check(typed) == "" else str(r.get("suggest", ""))
		_refresh()
		_user.caret_column = _user.text.length()
		return
	router.call("toast", L.t("Signed in as %s") % Net.username())
	router.call("back")


func _field(hint: String, kind: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.virtual_keyboard_type = kind as LineEdit.VirtualKeyboardType
	e.max_length = 120
	e.custom_minimum_size = Vector2(0, 76)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


func _refresh() -> void:
	match mode:
		Mode.LOGIN:
			_intro.text = "Log in to play with your account on this phone."
			_go.text = "Log in"
			_switch.text = "Create a new account"
		Mode.CREATE:
			_intro.text = "Create an account to play online and keep your progress on all your phones."
			_go.text = "Create account"
			_switch.text = "I already have an account"
		Mode.NAME:
			_intro.text = "Choose the username other players will see."
			_go.text = "Save username"
	_user.visible = mode != Mode.LOGIN
	_email.visible = mode != Mode.NAME
	_pass.visible = mode != Mode.NAME
	_switch.visible = mode != Mode.NAME
	_rules.visible = mode != Mode.LOGIN
	_social.visible = mode != Mode.NAME and _social_row != null and _social_row.get_child_count() > 0
	_rules_line.text = "By choosing a username you agree to the Player rules." if mode == Mode.NAME \
		else "By creating an account you agree to the Player rules."
	_user.placeholder_text = "Username (3-16 letters or numbers)"
	_pass.placeholder_text = "Password" if mode == Mode.LOGIN else "Password (at least 6 characters)"
	_say("")


func _say(text: String, bad := false) -> void:
	_msg.text = text
	if bad:
		_msg.add_theme_color_override("font_color", UIKit.CORAL)
	else:
		_msg.remove_theme_color_override("font_color")


func _submit() -> void:
	if _busy:
		return
	var uname := NameFilter.tidy(_user.text)
	var mail := _email.text.strip_edges()
	var pw := _pass.text
	if mode != Mode.LOGIN:
		var why := NameFilter.check(uname)
		if why != "":
			return _say(NameFilter.message(why), true)
	if mode != Mode.NAME:
		if not ("@" in mail and "." in mail.get_slice("@", 1)):
			return _say("That doesn't look like an email address.", true)
		if pw.length() < 6:
			return _say("The password needs at least 6 characters.", true)
	Sfx.ui("tap")
	_busy = true
	_go.disabled = true
	_say("Please wait…")
	DisplayServer.virtual_keyboard_hide()
	var r: Dictionary
	match mode:
		Mode.LOGIN:
			r = await Net.log_in(mail, pw)
		Mode.CREATE:
			r = await Net.sign_up(mail, pw, uname)
		Mode.NAME:
			r = await Net.set_username(uname, true)
	_busy = false
	if not is_inside_tree():
		return
	_go.disabled = false
	if r.get("ok", false):
		if mode == Mode.NAME:
			router.call("toast", L.t("Your username is now %s") % Net.username())
			router.call("back")
			return
		router.call("toast", L.t("Signed in as %s") % (Net.username() if Net.username() != "" else Net.email()))
		if Net.need_name():
			mode = Mode.NAME          # (logged in to an account that has no username yet)
			_refresh()
			return
		router.call("back")
		return
	if str(r.get("error", "")) == "email_taken":
		mode = Mode.LOGIN          # that email has an account: offer to log in to it, email kept
		_refresh()
	_say(Net.account_error(r), true)
