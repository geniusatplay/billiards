class_name StoreScreens
extends RefCounted
## v1.1.15, ready for the stores: "Update needed" (the server says this version is too old to play).


## Covers everything until the player updates from the store. Randy: "if there is a needed update, the people have
## to update it from the store".
class UpdateScreen extends CanvasLayer:
	func _init() -> void:
		layer = 95
		process_mode = Node.PROCESS_MODE_ALWAYS
		name = "UpdateScreen"

	func _ready() -> void:
		var root := UIKit.fullrect(Control.new())
		root.theme = UIKit.theme()
		root.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(root)
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.035, 0.06, 0.97)
		UIKit.fullrect(bg)
		root.add_child(bg)
		var cc := CenterContainer.new()
		UIKit.fullrect(cc)
		root.add_child(cc)
		var v := UIKit.vbox(26)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cc.add_child(v)
		var gem := IconGlyph.make("gem", 120, UIKit.EMERALD)
		gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(gem)
		v.add_child(UIKit.label("Update needed", "H1Label", HORIZONTAL_ALIGNMENT_CENTER))
		var store := "the App Store" if OS.get_name() == "iOS" else ("Google Play" if OS.get_name() == "Android" else "the store")
		var msg := UIKit.label(L.t("A new version of Emerald Online 8 Ball Pool AR is out. Update it from %s to keep playing — your progress stays with your account.") % L.t(store), "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		msg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.custom_minimum_size.x = 980
		v.add_child(msg)
		var b := UIKit.button("Update now", "PrimaryButton", "chev_down", 460)
		b.name = "UpdateNow"
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			Sfx.ui("tap")
			Net.open_store())
		v.add_child(b)
		var ver := UIKit.label(L.t("This version: %s · needed: %s or newer") % [Game.VERSION, str(Net.store_info.get("min", ""))], "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(ver)
		UIKit.fade_in(v, 0.3, 20)


## Share with friends (Randy: "a share with friends incentive to receive a free chest ... after 1 match, and every 30
## minutes as a closable popup with copy referral link and a QR code button"). Sharing (the phone's share sheet or
## copying the link) gives a gift chest once a day. The link is the same for everyone and carries nothing about the
## player: the stores reward sharing but not a friend's install, so no friend is ever tracked.
class SharePopup extends Control:
	signal closed

	var router: Node
	var _qr_box: Control
	var _note: Label
	var _card: PanelContainer
	var _chest_box: Control

	func _init(p_router: Node) -> void:
		router = p_router
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		process_mode = Node.PROCESS_MODE_ALWAYS
		name = "SharePopup"

	static func share_text() -> String:
		return L.t("Play pool with me in Emerald Online 8 Ball Pool AR!") + " " + Net.SHARE_URL

	func _ready() -> void:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.04, 0.07, 0.72)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		UIKit.fullrect(bg)
		add_child(bg)
		_card = UIKit.panel("Card")
		_card.custom_minimum_size = Vector2(860, 0)
		_card.add_theme_stylebox_override("panel", UIKit.box(Color(0.08, 0.13, 0.21, 0.98), 30, 3, Color(PackageView.XP_GOLD, 0.7), Vector4(34, 26, 34, 30), 24))
		UIKit.center_in(self, _card)
		var v := UIKit.vbox(14)
		_card.add_child(v)
		var top := UIKit.hbox(10)
		top.add_child(UIKit.spacer())
		var x := UIKit.icon_button("close", 80, "Close")
		x.name = "ShareClose"
		x.pressed.connect(close)
		top.add_child(x)
		v.add_child(top)
		var chest := PackageView.xp_chest(220.0)
		chest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chest.set_live(Game.share_chest_waiting())
		var cc := CenterContainer.new()
		cc.custom_minimum_size = Vector2(0, 170)
		cc.add_child(chest)
		_chest_box = cc
		v.add_child(cc)
		v.add_child(UIKit.label("Share Emerald 8 Ball Pool", "H1Label", HORIZONTAL_ALIGNMENT_CENTER))
		_note = UIKit.label("", "MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.custom_minimum_size.x = 800
		_note.name = "ShareNote"
		v.add_child(_note)
		var row := UIKit.hbox(16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var share := UIKit.button("Share", "PrimaryButton", "share", 250)
		share.name = "ShareSend"
		share.pressed.connect(_share)
		row.add_child(share)
		var copy := UIKit.button("Copy link", "", "copy", 250)
		copy.name = "ShareCopy"
		copy.pressed.connect(_copy)
		row.add_child(copy)
		var qr := UIKit.button("QR code", "", "qr", 250)
		qr.name = "ShareQr"
		qr.pressed.connect(_toggle_qr)
		row.add_child(qr)
		v.add_child(row)
		_qr_box = UIKit.vbox(8)
		_qr_box.visible = false
		_qr_box.name = "ShareQrBox"
		var code := QrCode.make(Net.SHARE_URL)
		if code:
			var t := TextureRect.new()
			t.texture = code.texture(8)
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.custom_minimum_size = Vector2(330, 330)
			t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			t.name = "ShareQrImage"
			_qr_box.add_child(t)
		_qr_box.add_child(UIKit.label("A friend scans this with their phone's camera.", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_qr_box)
		var link := UIKit.label(Net.SHARE_URL.trim_prefix("https://").trim_suffix("/"), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		link.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(link)
		_refresh()
		UIKit.fade_in(_card, 0.25, 26)

	func _refresh() -> void:
		_note.text = "Send the game to your friends and get a free XP chest. Once a day." if Game.share_chest_waiting() \
			else "Today's chest is yours. Share again tomorrow for another one."

	## The phone's share sheet; where there is none, the link is copied instead.
	func _share() -> void:
		Sfx.ui("tap")
		var stage: Stage = router.get("stage")
		if not (stage and stage.arcore.share(share_text(), L.t("Share Emerald 8 Ball Pool"))):
			DisplayServer.clipboard_set(share_text())
			router.call("toast", L.t("Link copied. Paste it in a message to a friend."))
		_reward()

	func _copy() -> void:
		Sfx.ui("tap")
		DisplayServer.clipboard_set(share_text())
		router.call("toast", L.t("Link copied. Paste it in a message to a friend."))
		_reward()

	func _toggle_qr() -> void:
		Sfx.ui("toggle")
		_qr_box.visible = not _qr_box.visible
		_chest_box.visible = not _qr_box.visible       # (room for the code on a phone screen)

	func _reward() -> void:
		if Game.claim_share_chest():
			Sfx.play("turn_chime", 0.8)
			router.call("toast", L.t("Thanks for sharing! A gift chest is waiting in the menu."))
			_refresh()

	func close() -> void:
		Sfx.ui("back")
		closed.emit()
		queue_free()
