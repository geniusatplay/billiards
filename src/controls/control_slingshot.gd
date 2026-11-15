class_name ControlSlingshot
extends CueControl
## A. SLINGSHOT — touch anywhere, pull back away from the target, release to shoot.
## Direction comes from the drag measured on the table plane (accurate in perspective);
## power from the on-screen drag length. A second finger fine-rotates the aim.

const DEAD_ZONE := 14.0
const CANCEL_RADIUS := 34.0

var _touch := -1
var _start := Vector2.ZERO
var _cur := Vector2.ZERO
var _fine := -1
var _fine_x := 0.0
var dragging := false


func scheme_id() -> String:
	return "slingshot"


func title() -> String:
	return L.t("Slingshot")


func help_lines() -> Array:
	return ["Touch anywhere and pull back — away from where you want the ball to go.",
		"Pull further for more power. Release to shoot.",
		"Slide back to where you started to cancel.",
		"While pulling, rest a second finger and slide it sideways for ultra-fine aim."]


func handle_input(ev: InputEvent) -> bool:
	if not enabled:
		return false
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if _touch < 0:
				_touch = ev.index
				_start = ev.position
				_cur = ev.position
				dragging = true
				return true
			if _fine < 0:
				_fine = ev.index
				_fine_x = ev.position.x
				return true
		else:
			if ev.index == _fine:
				_fine = -1
				return true
			if ev.index == _touch:
				_touch = -1
				dragging = false
				var fire := power >= 0.04 and _cur.distance_to(_start) > CANCEL_RADIUS
				if fire:
					shot_requested.emit()
				else:
					power = 0.0
					aim_updated.emit()
				return true
	elif ev is InputEventScreenDrag:
		if ev.index == _touch:
			_cur = ev.position
			_update()
			return true
		if ev.index == _fine:
			yaw -= (ev.position.x - _fine_x) * 0.00025 * float(Game.get_s("fine_aim_scale"))
			_fine_x = ev.position.x
			aim_updated.emit()
			return true
	return false


func _update() -> void:
	var pull := _cur - _start
	var px := pull.length()
	if px < DEAD_ZONE:
		power = 0.0
		aim_updated.emit()
		return
	power = clampf((px - DEAD_ZONE) / (_vp().y * 0.36), 0.0, 1.0)
	if _fine >= 0:
		aim_updated.emit()
		return   # direction locked while fine-tuning with the second finger
	var a = game.stage.screen_to_table(_start)
	var b = game.stage.screen_to_table(_cur)
	var dir := Vector2.ZERO
	if a != null and b != null and (a as Vector2).distance_to(b) > 1e-4:
		dir = -((b as Vector2) - (a as Vector2)).normalized()
	else:
		dir = -game.stage.screen_dir_to_table(pull)
	if dir.length() > 0.5:
		yaw = dir.angle()
	aim_updated.emit()


## Screen-space data for the HUD overlay (pull line + power ring).
func overlay() -> Dictionary:
	return {"active": dragging and _touch >= 0, "start": _start, "cur": _cur, "power": power,
		"cancel": _cur.distance_to(_start) <= CANCEL_RADIUS}
