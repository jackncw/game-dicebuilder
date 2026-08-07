extends Control
## Character select: pick 4 of the unlocked heroes, then embark.

var selected: Array = []
var grid: GridContainer
var embark: Button
var count_l: Label


func setup(_args: Dictionary) -> void:
	pass


const CARD_W := 336.0
const CARD_H := 268.0


func _ready() -> void:
	add_child(UIKit.background(1, 110.0, 0.0))

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	vb.offset_top = UIKit.S5
	vb.offset_left = UIKit.S4
	vb.offset_right = -UIKit.S4
	vb.add_theme_constant_override("separation", UIKit.S4)
	add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_select_team"), UIKit.F_H1))
	count_l = UIKit.outlined(UIKit.text_block("", UIKit.F_BODY, UIKit.CREAM, 640.0))
	vb.add_child(count_l)

	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UIKit.S3)
	grid.add_theme_constant_override("v_separation", UIKit.S3)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	vb.add_child(gc)
	_build_grid()

	var tray := UIKit.footer(1, 168.0)
	add_child(tray)
	embark = UIKit.button(Data.t("ui_start"), UIKit.GREEN.lightened(0.3),
			UIKit.F_H2 + 2, Vector2(340, 84))
	embark.pressed.connect(_on_embark)
	var back := UIKit.button(Data.t("ui_cancel"), UIKit.CREAM_DARK, UIKit.F_BODY, Vector2(200, 64))
	back.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([embark]))
	tray.get_child(0).add_child(UIKit.button_row([back]))
	_update_embark()


func _build_grid() -> void:
	for c in grid.get_children():
		c.queue_free()
	var text_w := CARD_W - 2 * UIKit.S4
	for id in GameData.hero_ids():
		var hdef: Dictionary = GameData.heroes[id]
		var unlocked: bool = id in Game.meta.unlocked_heroes
		var is_sel: bool = id in selected
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_W, CARD_H)
		var border := UIKit.GREEN.lightened(0.3) if is_sel else UIKit.OUTLINE
		# a silhouette needs a card lighter than itself, so a locked card keeps
		# the normal surface and only the pawn goes to ink
		var fill := UITheme.surface(1) if unlocked else UITheme.surface(1).lightened(0.06)
		card.add_theme_stylebox_override("panel", UIKit.card_box(fill, UIKit.R_LG,
				UIKit.B_FOCUS if is_sel else UIKit.B_STRONG, border, UIKit.S2))
		var cvb := VBoxContainer.new()
		cvb.add_theme_constant_override("separation", UIKit.S1)
		card.add_child(cvb)
		var name_l := UIKit.text_block(
				Data.bi(String(hdef.zh), String(hdef.en)) if unlocked else Data.t("ui_locked"),
				UIKit.F_BODY_SM, UIKit.CREAM if unlocked else UIKit.CREAM_DARK, text_w)
		cvb.add_child(name_l)
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2(text_w, 116)
		var art := PawnArt.fitted(id, Vector2(text_w, 108.0))
		art.position = Vector2(text_w * 0.5, 112)
		if not unlocked:
			art.modulate = Color(0.02, 0.03, 0.02, 1.0)   # silhouette
		art_holder.add_child(art)
		cvb.add_child(art_holder)
		if unlocked:
			var lvl := Game.hero_level(id)
			var info := UIKit.text_block("HP %d   Lv%d" % [int(hdef.hp), lvl],
					UIKit.F_BODY_SM, UITheme.accent(1), text_w)
			cvb.add_child(info)
			cvb.add_child(UIKit.text_block(
					Data.bi(String(hdef.passive_zh), String(hdef.passive_en)),
					UIKit.F_CAPTION, UIKit.CREAM_DARK, text_w))
			UIKit.mouse_passthrough(cvb)
			var tap := Button.new()
			tap.flat = true
			tap.set_anchors_preset(Control.PRESET_FULL_RECT)
			var hid: String = id
			tap.pressed.connect(func() -> void: _toggle(hid))
			card.add_child(tap)
			card.move_child(tap, 0)
		else:
			cvb.add_child(UIKit.text_block(
					Data.bi("擊敗第3章Boss解鎖", "Beat the Ch.3 boss to unlock"),
					UIKit.F_CAPTION, UIKit.CREAM_DARK, text_w))
		grid.add_child(card)


func _toggle(id: String) -> void:
	Sfx.play("button")
	if id in selected:
		selected.erase(id)
	elif selected.size() < 4:
		selected.append(id)
	_build_grid()
	_update_embark()


func _update_embark() -> void:
	embark.disabled = selected.size() != 4
	if count_l != null:
		count_l.text = Data.bi("已選 %d / 4" % selected.size(), "Chosen %d / 4" % selected.size())


func _on_embark() -> void:
	Sfx.play("win")
	Game.start_new_run(selected.duplicate())
