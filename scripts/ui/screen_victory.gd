extends Control
## Full run cleared (chapter 3 boss down). Stats + hero unlock pick on first
## clear.

var args := {}


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	add_child(UIKit.background(1, 132.0, 1030.0))

	# 任務2 通用規則:內容(首爆機嗰陣有兩張解鎖卡)高過可視高度就捲動,
	# 唔好同 footer 迫
	var scroll := UIKit.scroll_screen(150.0, 124.0 + UIKit.S2)
	scroll.offset_left = UIKit.S5
	scroll.offset_right = -UIKit.S5
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", UIKit.S4)
	scroll.add_child(vb)

	# the title wraps: "The forest is at peace!" alongside the Chinese runs
	# well past 720px in bilingual mode
	vb.add_child(UIKit.outlined(UIKit.text_block(
			Data.bi("森林已回復平靜!", "The forest is at peace!"),
			UIKit.F_H1, UIKit.CREAM, 640.0), 6))

	var stats: Dictionary = args.get("stats", {})
	var dur := int(args.get("duration", 0))
	var card := UIKit.card(1)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", UIKit.S2)
	card.add_child(cv)
	cv.add_child(UIKit.text_block("%s: %d" % [Data.bi("戰鬥", "Battles"),
			int(stats.get("battles", 0))], UIKit.F_BODY, UIKit.CREAM, 600.0))
	cv.add_child(UIKit.text_block("%s: %02d:%02d" % [Data.bi("用時", "Time"),
			dur / 60, dur % 60], UIKit.F_BODY, UIKit.CREAM, 600.0))
	vb.add_child(card)

	if Game.meta.pending_hero_pick:
		vb.add_child(UIKit.spacer(UIKit.S2))
		vb.add_child(UIKit.outlined(UIKit.text_block(
				Data.bi("首次爆機!自選解鎖一位新英雄:", "First clear! Choose a hero to unlock:"),
				UIKit.F_BODY, UIKit.CREAM, 640.0)))
		for id in GameData.unlockable_hero_ids():
			vb.add_child(_unlock_card(String(id)))
	else:
		_build_party()

	var tray := UIKit.footer(1, 124.0)
	add_child(tray)
	var b := UIKit.button(Data.bi("返回主選單", "Back to Menu"), UIKit.CREAM,
			UIKit.F_H2, Vector2(320, 76))
	b.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([b]))


## One selectable hero: portrait beside the name and passive, all wrapped —
## the old version was a two-line Button that clipped in bilingual mode.
func _unlock_card(id: String) -> Control:
	var hdef: Dictionary = GameData.heroes[id]
	var card := UIKit.card(1)
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	sb.border_color = UITheme.accent(1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.S3)
	card.add_child(row)
	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(112, 118)
	var art := PawnArt.fitted(id, Vector2(112, 110))
	art.position = Vector2(56, 114)
	art_holder.add_child(art)
	row.add_child(art_holder)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", UIKit.S1)
	row.add_child(info)
	info.add_child(UIKit.text_block(Data.bi(String(hdef.zh), String(hdef.en)),
			UIKit.F_BODY, UIKit.CREAM, 470.0, HORIZONTAL_ALIGNMENT_LEFT))
	info.add_child(UIKit.text_block(Data.bi(String(hdef.passive_zh), String(hdef.passive_en)),
			UIKit.F_CAPTION, UIKit.CREAM_DARK, 470.0, HORIZONTAL_ALIGNMENT_LEFT))
	UIKit.mouse_passthrough(row)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func() -> void:
		Sfx.play("win")
		Game.meta.unlocked_heroes.append(id)
		Game.meta.pending_hero_pick = false
		Game.save_meta()
		Game.goto("menu"))
	card.add_child(tap)
	card.move_child(tap, 0)
	return card


## Nothing to pick: the party takes a bow along the bottom instead.
func _build_party() -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var ids := GameData.starter_hero_ids()
	for i in ids.size():
		var pa := PawnArt.fitted(String(ids[i]), Vector2(150, 150))
		pa.position = Vector2(116.0 + i * 163.0, 1032)
		stage.add_child(pa)
