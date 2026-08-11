extends Control
## Treasure chest: a relic OR pick 1 of 3 rare+ faces (then choose whose face
## it replaces).

var loot := {}


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var rng := RunState.rng_of(Game.run)
	loot = RunState.gen_treasure(Game.run, rng)
	RunState.save_rng(Game.run, rng)

	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 104.0, 1000.0))
	add_child(RunWidgets.topbar())

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	Safe.pin_top(vb, 110)
	vb.offset_left = UIKit.S5
	vb.offset_right = -UIKit.S5
	vb.add_theme_constant_override("separation", UIKit.S4)
	add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_treasure"), UIKit.F_H1))

	if String(loot.kind) == "relic":
		var rid := String(loot.relic)
		var rdef: Dictionary = GameData.relics[rid]
		var hue := DetailCard.relic_hue(rid)
		var card := UIKit.card(chapter)
		var csb: StyleBoxFlat = card.get_theme_stylebox("panel")
		csb.border_color = hue
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", UIKit.S2)
		card.add_child(cv)
		cv.add_child(UIKit.text_block(Data.bi(String(rdef.zh), String(rdef.en)),
				UIKit.F_H2, UITheme.CAT_ON_DARK.special, 600.0))
		cv.add_child(UIKit.text_block(Data.bi2(String(rdef.desc_zh), String(rdef.desc_en)),
				UIKit.F_BODY, UIKit.CREAM, 600.0))
		vb.add_child(card)
		var take := UIKit.button(Data.t("ui_take"), UIKit.GREEN.lightened(0.3),
				UIKit.F_H2, Vector2(300, 80))
		# the card is raised on pick-up here as well, so "what did I just get"
		# has the same answer whichever way the relic arrived
		take.pressed.connect(func() -> void:
			Sfx.play("win")
			Game.add_relic(rid)
			DetailCard.show_relic(self, rid, func() -> void: Game.node_completed()))
		vb.add_child(UIKit.button_row([take]))
	else:
		vb.add_child(UIKit.outlined(UIKit.text_block(Data.t("ui_offer_title"),
				UIKit.F_BODY, UIKit.CREAM, 620.0)))
		for fid in loot.faces:
			var c2 := CenterContainer.new()
			vb.add_child(c2)
			c2.add_child(RunWidgets.face_card(String(fid), "", func() -> void:
				_pick_slot_for(String(fid))))
		var skip := UIKit.button(Data.t("ui_skip"), UIKit.CREAM_DARK,
				UIKit.F_BODY, Vector2(240, 70))
		skip.pressed.connect(func() -> void:
			Sfx.play("button")
			Game.node_completed())
		vb.add_child(UIKit.button_row([skip]))

	add_child(RunWidgets.party_strip(1004.0, 156.0))


func _pick_slot_for(fid: String) -> void:
	Sfx.play("button")
	RunWidgets.pick_team_face(self, Data.t("ui_pick_replace"),
		func(hi: int, slot: int) -> void:
			RunState.apply_face_swap(Game.run, hi, slot, fid)
			Sfx.play("win")
			Game.node_completed(), Callable(), fid)
