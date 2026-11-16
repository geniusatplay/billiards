class_name AccountScreen
extends MenuScreens.Screen
## v1.1.13 (Randy: "prompt to create an account with email / password which gets saved locally to the device,
## uploaded to the server which gets stored at the server & counts as the user id").
## Create an account or log in. Shown when the game starts (until this phone is signed in), from Play Online and
## from Settings. The phone keeps the email and its own key; the password goes only to the server, which keeps a
## hash of it. Laid out in two columns so the fields stay above the on-screen keyboard in landscape.

var _login := false          # false: create an account, true: log in
var _email: LineEdit
var _pass: LineEdit
var _intro: Label
var _msg: Label
var _go: Button
var _switch: Button
var _busy := false


func _init(p_router: Node = null, start_with_login := false) -> void:
	super(p_router)
	_login = start_with_login


func _ready() -> void:
	scrim(0.8)
	header("Your account")
	content(170, 160)
	var card := UIKit.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UIKit.hbox(44)
	card.add_child(row)

	var left := UIKit.vbox(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var top := UIKit.hbox(18)
	top.add_child(IconGlyph.make("user", 52, UIKit.EMERALD))
	_intro = UIKit.label("", "")          # one line, so both fields sit above the on-screen keyboard
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_intro)
	left.add_child(top)
	_email = _field("Email", LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	_email.text = Net.email()
	left.add_child(_email)
	_pass = _field("Password", LineEdit.KEYBOARD_TYPE_PASSWORD)
	_pass.secret = true
	left.add_child(_pass)
	_msg = UIKit.label("", "SmallLabel")
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_msg)

	var right := UIKit.vbox(16)
	right.custom_minimum_size.x = 480
	row.add_child(right)
	_go = UIKit.button("Create account", "PrimaryButton", "user", 480)
	_go.pressed.connect(_submit)
	right.add_child(_go)
	_switch = UIKit.button("I already have an account", "GhostButton", "", 480)
	_switch.pressed.connect(func():
		Sfx.ui("toggle")
		_login = not _login
		_refresh())
	right.add_child(_switch)
	var later := UIKit.button("Not now", "GhostButton", "", 480)
	later.pressed.connect(func():
		Sfx.ui("back")
		router.call("back"))
	right.add_child(later)
	body.add_child(card)

	_email.text_submitted.connect(func(_t: String): _pass.grab_focus())
	_pass.text_submitted.connect(func(_t: String): _submit())
	_refresh()


func _field(hint: String, kind: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.virtual_keyboard_type = kind as LineEdit.VirtualKeyboardType
	e.max_length = 120
	e.custom_minimum_size = Vector2(0, 80)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


func _refresh() -> void:
	_intro.text = "Log in to play with your account on this phone." if _login else "Create an account to play online and keep your progress on all your phones."
	_pass.placeholder_text = "Password" if _login else "Password (at least 6 characters)"
	_go.text = "Log in" if _login else "Create account"
	_switch.text = "Create a new account" if _login else "I already have an account"
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
	var mail := _email.text.strip_edges()
	var pw := _pass.text
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
	if _login:
		r = await Net.log_in(mail, pw)
	else:
		r = await Net.sign_up(mail, pw)
	_busy = false
	if not is_inside_tree():
		return
	_go.disabled = false
	if r.get("ok", false):
		router.call("toast", L.t("Signed in as %s") % Net.email())
		router.call("back")
		return
	if str(r.get("error", "")) == "email_taken":
		_login = true          # that email has an account: offer to log in to it, email kept
		_refresh()
	_say(Net.account_error(r), true)
