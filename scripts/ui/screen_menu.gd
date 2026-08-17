extends Control
## Main menu: new run / continue / roster / settings.
##
## Layout is a title block up top, the button column in the middle, and the
## party standing on the forest floor across the bottom — the screen has to
## carry the game's look before the player has seen a single battle.

## The forest floor the party idles on. A function rather than a constant since
## round 6: everything below it — the pawns, the loose dice, the "flick the
## dice" hint — hangs off this line, and on a phone with a home indicator the
## whole tableau has to come up with it or the hint ends up under the hardware.
const GROUND_BASE := 1074.0

static func ground() -> float:
	return GROUND_BASE - Safe.bottom


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	add_child(UIKit.background(1, 150.0, ground()))
	# the menu is allowed to be a picture rather than a backdrop: light comes
	# down through the canopy into the clearing the party is standing in
	var shafts := Forest.LightShafts.new()
	shafts.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shafts)
	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		# the light through the canopy breathes — slow enough to be felt, not seen
		var breathe := shafts.create_tween().set_loops()
		breathe.tween_property(shafts, "modulate:a", 0.55, 3.4) 				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		breathe.tween_property(shafts, "modulate:a", 1.0, 3.4) 				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_build_title()
	_build_party()
	_build_buttons()


func _build_title() -> void:
	var head := VBoxContainer.new()
	head.anchor_left = 0.0
	head.anchor_right = 1.0
	Safe.pin_top(head, 150)
	head.add_theme_constant_override("separation", UIKit.S2)
	add_child(head)

	# the title is a sign nailed up in the clearing: a plank, grain, pegs, and
	# two ropes running off the top corners
	var plate := CenterContainer.new()
	head.add_child(plate)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", Forest.wood_box(UITheme.WOOD_SIGN, UIKit.R_MD))
	var bsb: StyleBoxFlat = badge.get_theme_stylebox("panel")
	bsb.border_color = UITheme.OUTLINE
	bsb.shadow_color = UITheme.SHADOW
	bsb.shadow_size = 8
	bsb.shadow_offset = Vector2(0, 6)
	bsb.set_content_margin_all(UIKit.S5)
	bsb.content_margin_left = UIKit.S6 + UIKit.S4
	bsb.content_margin_right = UIKit.S6 + UIKit.S4
	var grain := Forest.WoodGrain.new()
	grain.tint = UITheme.SHADE_MED
	badge.add_child(grain)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", UIKit.S1)
	badge.add_child(bv)
	var t := UIKit.title("骰林", UIKit.F_DISPLAY + 16, UIKit.CREAM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(t)
	var sub := UIKit.text_block("DICE GROVE", UIKit.F_H2, UITheme.WOOD_TEXT, 0.0)
	# spaced caps: the plank reads as a carved lockup, not a caption
	sub.add_theme_constant_override("spacing_glyph", 6)
	bv.add_child(sub)
	plate.add_child(badge)

	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		# the sign drops into place once, then hangs with the slightest sway
		badge.pivot_offset = Vector2(200.0, 0.0)
		badge.rotation = -0.05
		badge.modulate.a = 0.0
		var drop := create_tween()
		drop.tween_property(badge, "modulate:a", 1.0, 0.25)
		drop.parallel().tween_property(badge, "rotation", 0.012, 0.5) 				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		drop.tween_callback(func() -> void:
			var sway := badge.create_tween().set_loops()
			sway.tween_property(badge, "rotation", -0.008, 2.6) 					.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			sway.tween_property(badge, "rotation", 0.008, 2.6) 					.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE))

	head.add_child(UIKit.spacer(UIKit.S3))
	head.add_child(UIKit.outlined(UIKit.text_block(
			Data.bi("四位夥伴,八顆骰子,一片會反擊的森林。",
					"Four companions, eight dice, one forest that fights back."),
			UIKit.F_BODY_SM, UIKit.CREAM, 540.0)))


## The party idles along the forest floor. Purely decorative — no input, no
## per-frame rebuilds; PawnArt only redraws when its stepped idle frame flips.
func _build_party() -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var ids := GameData.starter_hero_ids()
	for i in ids.size():
		var x := 116.0 + i * 163.0
		var shadow := Panel.new()
		var sb := UIKit.flat_box(Color(0, 0, 0, 0.28), 999, 0, UIKit.OUTLINE, 0)
		sb.set_border_width_all(0)
		shadow.add_theme_stylebox_override("panel", sb)
		shadow.position = Vector2(x - 50, ground() + 4)
		shadow.size = Vector2(100, 18)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(shadow)
		var pa := PawnArt.fitted(ids[i], Vector2(168, 168))
		pa.position = Vector2(x, ground() + 12)
		stage.add_child(pa)

	# A few dice scattered on the forest floor — the same 3D widget the battle
	# uses, and the player can pick a fight with them. Flick one and it spins,
	# coasts, and settles back square.
	#
	# They do nothing. That is the point: this is a game about dice and the menu
	# is where you find out they are objects, not icons, before anything is at
	# stake. Which faces they wear is decoration, so they wear the starting dice
	# of three of the cast.
	#
	# The cost is nil while nobody is touching them: a die renders its viewport
	# only while it is moving and puts it back to sleep two frames after it
	# stops (see Die3D._process), so three parked dice are three blits.
	var cast := GameData.hero_ids()
	var props := [[62.0, cast[0], 0, -0.16], [640.0, cast[3], 0, 0.13],
			[368.0, cast[5], 4, 0.05]]
	for p in props:
		var dv := Die3D.new(Vector2(96, 96))
		dv.position = Vector2(float(p[0]) - 48.0, ground() + 36.0)
		dv.rotation = float(p[3])
		stage.add_child(dv)
		dv.set_die(_hero_die_faces(String(p[1])), int(p[2]))
		dv.enable_free_spin()

	# the toy is not obvious unless somebody says so
	var hint := UIKit.outlined(UIKit.text_block(
			Data.bi("撥動骰子", "flick the dice"),
			UIKit.F_CAPTION, UITheme.CREAM_DARK, 300.0), 3)
	hint.position = Vector2(210, ground() + 140.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hint)


## The six A-die faces of a hero, straight from the data — the menu is on
## screen before any run exists, so there is no BattleCore to ask.
func _hero_die_faces(id: String) -> Array:
	var out := []
	for fid in GameData.heroes[id].start:
		var fd: Dictionary = GameData.faces[String(fid)].duplicate()
		fd["id"] = String(fid)
		out.append(fd)
	return out


func _build_buttons() -> void:
	var center := Control.new()
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	Safe.pin_top(center, 452)
	add_child(center)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", UIKit.S4)
	center.add_child(col)

	if Game.has_saved_run():
		var b_cont := UIKit.button(Data.t("ui_continue"), UIKit.GREEN.lightened(0.3),
				UIKit.F_H2 + 2, Vector2(360, 88))
		b_cont.pressed.connect(func() -> void:
			Sfx.play("button")
			Game.continue_run())
		col.add_child(b_cont)

	var b_new := UIKit.button(Data.t("ui_new_run"), UIKit.CREAM, UIKit.F_H2 + 2, Vector2(360, 88))
	b_new.pressed.connect(func() -> void:
		Sfx.play("button")
		if Game.has_saved_run():
			Game.clear_run()
		Game.goto("charselect"))
	col.add_child(b_new)

	for spec in [["ui_codex", "codex"], ["ui_meta", "metaprogress"], ["ui_settings", "settings"]]:
		var dest: String = spec[1]
		var b := UIKit.button(Data.t(spec[0]), UIKit.CREAM_DARK, UIKit.F_BODY + 2, Vector2(360, 72))
		b.pressed.connect(func() -> void:
			Sfx.play("button")
			Game.goto(dest))
		col.add_child(b)

	# the column walks in, one plank at a time
	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		var delay := 0.12
		for c in col.get_children():
			var ctrl := c as Control
			ctrl.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_property(ctrl, "modulate:a", 1.0, 0.22)
			delay += 0.07
