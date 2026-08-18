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
		# the icon leads: this is the picture the relic will wear in the battle
		# strip for the rest of the run, so the chest is where it gets learned
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", UIKit.S4)
		card.add_child(crow)
		var cicon := ItemIcon.for_relic(rid, 84.0)
		cicon.interactive = false
		cicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crow.add_child(cicon)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", UIKit.S2)
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crow.add_child(cv)
		cv.add_child(UIKit.text_block(Data.bi(String(rdef.zh), String(rdef.en)),
				UIKit.F_H2, UITheme.CAT_ON_DARK.special, 500.0))
		cv.add_child(UIKit.text_block(Data.bi2(String(rdef.desc_zh), String(rdef.desc_en)),
				UIKit.F_BODY, UIKit.CREAM, 500.0))
		vb.add_child(card)
		var take := UIKit.button(Data.t("ui_take"), UIKit.GREEN.lightened(0.3),
				UIKit.F_H2, Vector2(300, 80))
		# the card is raised on pick-up here as well, so "what did I just get"
		# has the same answer whichever way the relic arrived
		take.pressed.connect(func() -> void:
			Sfx.play("chest")
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

	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		_reveal(vb)


## Opening the chest is a moment, not a page load: the latch clacks, a column
## of light stands up out of the dark, and the loot flips over into view.
func _reveal(content: Control) -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.85)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var vp := get_viewport().get_visible_rect().size
	var beam := ColorRect.new()
	beam.color = Color(1.0, 0.95, 0.7, 0.0)
	beam.size = Vector2(210, vp.y)
	beam.position = Vector2(vp.x * 0.5 - 105, 0)
	beam.pivot_offset = Vector2(105, vp.y * 0.5)
	beam.scale.x = 0.1
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_child(beam)
	content.modulate.a = 0.0
	content.scale.x = 0.0
	content.pivot_offset.x = 330.0
	Sfx.play("chest")
	var tw := create_tween()
	tw.tween_property(beam, "color:a", 0.5, Fx.dur(0.22))
	tw.parallel().tween_property(beam, "scale:x", 1.0, Fx.dur(0.3)) 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func() -> void:
		Fx.burst(scrim, Vector2(vp.x * 0.5, vp.y * 0.42), Color(1.0, 0.9, 0.55), 18, 300.0))
	# the loot flips over into view while the beam fades
	tw.tween_property(content, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(content, "scale:x", 1.0, Fx.dur(0.24)) 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(beam, "color:a", 0.0, Fx.dur(0.4))
	tw.parallel().tween_property(scrim, "color:a", 0.0, Fx.dur(0.45))
	tw.tween_callback(scrim.queue_free)


func _pick_slot_for(fid: String) -> void:
	Sfx.play("button")
	RunWidgets.pick_team_face(self, Data.t("ui_pick_replace"),
		func(hi: int, slot: int) -> void:
			RunState.apply_face_swap(Game.run, hi, slot, fid)
			Sfx.play("win")
			Game.node_completed(), Callable(), fid)
