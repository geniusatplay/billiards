extends Node
## Adverts. Autoloaded as `Ads`.
##
## SWITCHED OFF (Randy, 10 Nov 2026: "prepare, do NOT switch on yet"). The moments (Randy, 11 Nov, checked
## against the Google Play, AdMob and App Store rules in docs/ADS.md):
##   "after_match"  full-screen advert as the player leaves any score screen (every mode, every match; Practice:
##                  the "rack cleared" screen). Never at the start of a match: Google Play forbids that.
##   "xp_chest"     rewarded, the player's choice: the XP chest is ready 2 hours after it was opened, not 6
##   "package"      rewarded, the player's choice: a package that is still unlocking opens at once
## Rewarded adverts are always offered next to the free way (waiting), with the reward named on the button.
## While adverts are off, show() simply carries on (and the rewarded offers are not shown at all). With "Show
## advert stand-ins" on (developer tools) a stand-in screen appears at each moment instead.
## To go live: add the AdMob plugin, put the unit ids below, show the real advert in _show_real() and set
## ENABLED = true.

const ENABLED := false
const APP_ID := ""                                   # AdMob app id (set when the AdMob app exists)
const UNITS := {"after_match": "", "xp_chest": "", "package": ""}
const REWARDED := ["xp_chest", "package"]

var _layer: CanvasLayer


func active() -> bool:
	return ENABLED or bool(Game.get_s("ad_standins"))


## Shows the advert for a moment, then calls `done`. For a rewarded moment `done` means the reward was earned;
## if the player closes the advert early, `skipped` is called instead (no reward). Never blocks when adverts are off.
func show(moment: String, done: Callable, skipped := Callable()) -> void:
	if not active():
		done.call()
		return
	if ENABLED and _show_real(moment, done, skipped):
		return
	_stand_in(moment, done, skipped)


func _show_real(_moment: String, _done: Callable, _skipped: Callable) -> bool:
	return false     # no advert plugin is built in yet


func _stand_in(moment: String, done: Callable, skipped: Callable) -> void:
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 90
		add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	_layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.fullrect(bg)
	root.add_child(bg)
	var v := UIKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.label("ADVERT", "AccentLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var what := UIKit.label("An advert will play here.", "H2Label", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(what)
	var note := UIKit.label("Stand-in screen: adverts are switched off.", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(note)
	var go := UIKit.button("Continue", "PrimaryButton", "chev_right", 360)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.disabled = true
	v.add_child(go)
	if moment in REWARDED:
		# a rewarded advert can be closed early, without the reward
		var quit := UIKit.button("Close without the reward", "GhostButton", "close", 360)
		quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quit.pressed.connect(func():
			root.queue_free()
			if skipped.is_valid():
				skipped.call())
		v.add_child(quit)
	UIKit.center_in(root, v)
	go.pressed.connect(func():
		root.queue_free()
		done.call())
	# a real advert cannot be skipped at once either
	var left := [3]
	go.text = L.t("Continue") + " (%d)" % left[0]
	go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var tick := Timer.new()
	tick.wait_time = 1.0
	root.add_child(tick)
	tick.timeout.connect(func():
		left[0] -= 1
		if left[0] <= 0:
			tick.stop()
			go.text = L.t("Continue")
			go.disabled = false
		else:
			go.text = L.t("Continue") + " (%d)" % left[0])
	tick.start()
