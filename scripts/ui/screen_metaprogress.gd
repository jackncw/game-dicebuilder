extends Control
## Roster / meta progression: 6 hero cards with XP bars, unlocked faces
## preview; locked heroes show silhouette + unlock condition. Global stats.

func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	add_child(UIKit.background(1, 118.0, 0.0))

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Safe.pin_top(scroll, UIKit.S5)
	scroll.offset_left = UIKit.S4
	scroll.offset_right = -UIKit.S4
	Safe.pin_bottom(scroll, 128)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UIKit.S3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_meta"), UIKit.F_H1))

	# stats line
	var wr := 0
	if int(Game.meta.runs) > 0:
		wr = int(round(float(Game.meta.wins) / int(Game.meta.runs) * 100.0))
	var fastest := int(Game.meta.fastest_clear_sec)
	var fast_s := "--" if fastest == 0 else "%02d:%02d" % [fastest / 60, fastest % 60]
	var stats := UIKit.label("%s %d   %s %d%%   %s %s" % [
			Data.t("ui_run_stats_battles"), int(Game.meta.runs),
			Data.t("ui_run_stats_winrate"), wr,
			Data.t("ui_run_stats_fastest"), fast_s], UIKit.F_BODY_SM, UIKit.CREAM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stats)

	var thresholds: Dictionary = GameData.balance.xp_levels
	for id in GameData.hero_ids():
		var hdef: Dictionary = GameData.heroes[id]
		var unlocked: bool = id in Game.meta.unlocked_heroes
		var panel := UIKit.card(1, UIKit.R_LG, UIKit.B_STRONG, UIKit.OUTLINE, UIKit.S3)
		if not unlocked:
			var lsb: StyleBoxFlat = panel.get_theme_stylebox("panel")
			lsb.bg_color = UITheme.surface(1).lightened(0.06)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		panel.add_child(hb)
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2(96, 116)
		var art := PawnArt.fitted(id, Vector2(96, 108.0))
		art.position = Vector2(48, 112)
		if not unlocked:
			art.modulate = Color(0.02, 0.03, 0.02, 1.0)
		art_holder.add_child(art)
		hb.add_child(art_holder)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		if not unlocked:
			info.add_child(UIKit.label(Data.t("ui_locked"), 24, UIKit.CREAM))
			info.add_child(UIKit.label(Data.bi("擊敗第3章Boss解鎖", "Beat the Ch.3 boss to unlock"), 17, UIKit.CREAM_DARK))
			vb.add_child(panel)
			continue
		info.add_child(UIKit.label(Data.bi(String(hdef.zh), String(hdef.en)), 24, UIKit.CREAM))
		var xp := int(Game.meta.xp.get(id, 0))
		var lvl := Game.hero_level(id)
		var next_xp := 0
		if lvl < 5:
			next_xp = int(thresholds[str(lvl + 1)])
		var xp_txt := "Lv%d  %s %d" % [lvl, Data.t("ui_xp"), xp]
		if next_xp > 0:
			xp_txt += " / %d" % next_xp
		info.add_child(UIKit.label(xp_txt, 18, UIKit.YELLOW.lightened(0.25)))
		if next_xp > 0:
			var prev_xp := 0
			if lvl >= 2:
				prev_xp = int(thresholds[str(lvl)])
			info.add_child(UIKit.hp_bar(xp - prev_xp, next_xp - prev_xp, Vector2(300, 12), UIKit.YELLOW))
		info.add_child(UIKit.label(Data.bi(String(hdef.passive_zh), String(hdef.passive_en)), 15, UIKit.CREAM_DARK))
		# unlocked faces
		var unlocks: Dictionary = hdef.unlocks
		var face_line := ""
		for l_key in ["2", "3", "4", "5"]:
			var fid: String = unlocks[l_key]
			var fdef: Dictionary = GameData.faces[fid]
			var got: bool = int(l_key) <= lvl
			var nm: String = Data.bi(String(fdef.zh), String(fdef.en))
			face_line += "%s Lv%s:%s  " % ["✓" if got else "✗", l_key, nm]
		var fl := UIKit.label(face_line, 15, UIKit.CREAM_DARK)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(fl)
		vb.add_child(panel)

	var tray := UIKit.footer(1, 120.0)
	add_child(tray)
	var back := UIKit.button(Data.bi("返回", "Back"), UIKit.CREAM, UIKit.F_H2, Vector2(260, 74))
	back.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([back]))
