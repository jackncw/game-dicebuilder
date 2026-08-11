extends Control
## Shop: 4 faces (≥1 rare+), 1 relic, 2 potions, forge service. One purchase
## per item. Leave completes the node.

var stock := {}
var list_vb: VBoxContainer


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var rng := RunState.rng_of(Game.run)
	stock = RunState.gen_shop(Game.run, rng)
	RunState.save_rng(Game.run, rng)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 104.0, 0.0))
	add_child(RunWidgets.topbar())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Safe.pin_top(scroll, 56)
	scroll.offset_left = UIKit.S4
	scroll.offset_right = -UIKit.S4
	Safe.pin_bottom(scroll, 124)
	add_child(scroll)
	list_vb = VBoxContainer.new()
	list_vb.add_theme_constant_override("separation", UIKit.S3)
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vb)

	list_vb.add_child(UIKit.title(Data.t("ui_shop"), UIKit.F_H1))

	# faces
	for i in stock.faces.size():
		if stock.faces_bought[i]:
			continue
		var fid: String = stock.faces[i]
		var price := RunState.face_price(fid)
		var idx: int = i
		var card := RunWidgets.face_card(fid, "", func() -> void:
			_buy_face(idx), Vector2(648, 108), 0, price)
		var cc := CenterContainer.new()
		cc.add_child(card)
		list_vb.add_child(cc)

	# relic
	if stock.relic != "" and not stock.relic_bought:
		var rdef: Dictionary = GameData.relics[stock.relic]
		var price2 := int(GameData.balance.shop_prices.relic)
		var rb := RunWidgets.offer_card(Data.bi(String(rdef.zh), String(rdef.en)),
				Data.bi2(String(rdef.desc_zh), String(rdef.desc_en)),
				"", UIKit.ORANGE, Callable(), Vector2(648, 108), price2)
		var rid := String(stock.relic)
		rb.pressed.connect(func() -> void:
			if int(Game.run.gold) >= price2:
				Game.run.gold = int(Game.run.gold) - price2
				Game.add_relic(rid)
				stock.relic_bought = true
				Sfx.play("win")
				DetailCard.show_relic(self, rid, _build)
			else:
				Sfx.play("block", 0.5))
		var rc := CenterContainer.new()
		rc.add_child(rb)
		list_vb.add_child(rc)

	# potions
	for i in stock.potions.size():
		if stock.potions_bought[i]:
			continue
		var pid: String = stock.potions[i]
		var pdef: Dictionary = GameData.potions[pid]
		var price3 := int(GameData.balance.shop_prices.potion)
		var idx2: int = i
		var pb := RunWidgets.offer_card(Data.bi(String(pdef.zh), String(pdef.en)),
				Data.bi2(String(pdef.desc_zh), String(pdef.desc_en)),
				"", UIKit.GREEN, Callable(), Vector2(648, 108), price3)
		pb.pressed.connect(func() -> void:
			if Game.run.potions.size() >= int(GameData.balance.potion_cap):
				Sfx.play("block", 0.5)
				return
			if int(Game.run.gold) >= price3:
				Game.run.gold = int(Game.run.gold) - price3
				Game.run.potions.append(pid)
				stock.potions_bought[idx2] = true
				Sfx.play("potion")
				_build()
			else:
				Sfx.play("block", 0.5))
		var pc := CenterContainer.new()
		pc.add_child(pb)
		list_vb.add_child(pc)

	# forge service
	if not stock.forge_used:
		var fprice := int(GameData.balance.shop_prices.forge)
		if GameData.has_relic_effect(Game.run.relics, "forge_half"):
			fprice = int(fprice / 2.0)
		var fb := RunWidgets.offer_card(Data.t("ui_forge"),
				Data.bi("自選一個骰面,數值 +1", "A chosen face gets +1"),
				"", UIKit.YELLOW, Callable(), Vector2(648, 108), fprice)
		fb.pressed.connect(func() -> void:
			if int(Game.run.gold) < fprice:
				Sfx.play("block", 0.5)
				return
			RunWidgets.pick_team_face(self, Data.t("ui_forge"),
				func(hi: int, slot: int) -> void:
					Game.run.gold = int(Game.run.gold) - fprice
					RunState.forge_face(Game.run.team[hi], slot)
					stock.forge_used = true
					Sfx.play("win")
					_build(),
				func(hero: Dictionary) -> Array:
					return RunState.forgeable_slots(hero)))
		var fc := CenterContainer.new()
		fc.add_child(fb)
		list_vb.add_child(fc)

	var tray := UIKit.footer(chapter, 116.0)
	add_child(tray)
	var leave := UIKit.button(Data.t("ui_leave"), UIKit.CREAM, UIKit.F_H2, Vector2(300, 76))
	leave.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.node_completed())
	tray.get_child(0).add_child(UIKit.button_row([leave]))


func _buy_face(idx: int) -> void:
	var fid: String = stock.faces[idx]
	var price := RunState.face_price(fid)
	if int(Game.run.gold) < price:
		Sfx.play("block", 0.5)
		return
	RunWidgets.pick_team_face(self, Data.t("ui_pick_replace"),
		func(hi: int, slot: int) -> void:
			Game.run.gold = int(Game.run.gold) - price
			RunState.apply_face_swap(Game.run, hi, slot, fid)
			stock.faces_bought[idx] = true
			Sfx.play("win")
			_build(), Callable(), fid)
