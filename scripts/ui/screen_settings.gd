extends Control
## Settings: volume, language display mode, reset data.

func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	add_child(UIKit.background(1, 118.0, 940.0))

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	vb.offset_top = UIKit.S6
	vb.offset_left = UIKit.S5
	vb.offset_right = -UIKit.S5
	vb.add_theme_constant_override("separation", UIKit.S5)
	add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_settings"), UIKit.F_H1))
	vb.add_child(UIKit.spacer(UIKit.S2))

	# --- volume
	var vol_card := UIKit.card(1)
	var vol_v := VBoxContainer.new()
	vol_v.add_theme_constant_override("separation", UIKit.S3)
	vol_card.add_child(vol_v)
	var vol_l := UIKit.text_block("%s: %d%%" % [Data.t("ui_volume"),
			int(Game.settings.volume * 100)], UIKit.F_H2, UIKit.CREAM, 600.0)
	vol_v.add_child(vol_l)
	var slider := UIKit.slider(Game.settings.volume * 100.0, 100.0, 560.0)
	slider.value_changed.connect(func(v: float) -> void:
		Game.settings.volume = v / 100.0
		vol_l.text = "%s: %d%%" % [Data.t("ui_volume"), int(v)]
		Game.save_settings())
	var sc := CenterContainer.new()
	sc.add_child(slider)
	vol_v.add_child(sc)
	vb.add_child(vol_card)

	# --- language mode
	var lang_card := UIKit.card(1)
	var lang_v := VBoxContainer.new()
	lang_v.add_theme_constant_override("separation", UIKit.S3)
	lang_card.add_child(lang_v)
	lang_v.add_child(UIKit.text_block(Data.t("ui_lang_mode"), UIKit.F_H2, UIKit.CREAM, 600.0))
	var modes := [["both", Data.t("ui_lang_both")], ["zh", Data.t("ui_lang_zh")], ["en", Data.t("ui_lang_en")]]
	var mrow := HBoxContainer.new()
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	mrow.add_theme_constant_override("separation", UIKit.S3)
	for m in modes:
		var active: bool = Game.settings.lang_mode == m[0]
		var b := UIKit.button(m[1], UIKit.GREEN.lightened(0.3) if active else UIKit.CREAM,
				UIKit.F_BODY, Vector2(186, 68))
		if active:
			var abox: StyleBoxFlat = b.get_theme_stylebox("normal")
			abox.set_border_width_all(UIKit.B_FOCUS)
		var mode: String = m[0]
		b.pressed.connect(func() -> void:
			Sfx.play("button")
			Game.settings.lang_mode = mode
			Game.save_settings()
			_build())
		mrow.add_child(b)
	lang_v.add_child(mrow)
	vb.add_child(lang_card)

	# --- presentation toggles
	var pres := UIKit.card(1)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", UIKit.S3)
	pres.add_child(pv)
	pv.add_child(UIKit.text_block(Data.bi("表現", "Presentation"), UIKit.F_H2, UIKit.CREAM, 600.0))
	pv.add_child(_toggle("fast_anim",
			Data.bi("快速動畫", "Fast animations"),
			Data.bi("擲骰縮短到 0.3 秒", "Dice throws squeezed to 0.3s")))
	pv.add_child(_toggle("particles",
			Data.bi("環境粒子", "Ambient particles"),
			Data.bi("螢火蟲、落葉、孢子", "Fireflies, falling leaves, spores")))
	vb.add_child(pres)

	# --- reset data (double confirm)
	var danger := UIKit.card(1)
	var dsb: StyleBoxFlat = danger.get_theme_stylebox("panel")
	dsb.border_color = UIKit.RED.darkened(0.15)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", UIKit.S3)
	danger.add_child(dv)
	dv.add_child(UIKit.text_block(Data.bi("危險區", "Danger zone"),
			UIKit.F_BODY_SM, UITheme.CAT_ON_DARK.attack, 600.0))
	var reset := UIKit.button(Data.t("ui_reset_data"), UIKit.RED.lightened(0.35),
			UIKit.F_BODY, Vector2(340, 70))
	reset.pressed.connect(func() -> void:
		Sfx.play("button")
		_confirm_reset())
	dv.add_child(UIKit.button_row([reset]))
	vb.add_child(danger)

	var tray := UIKit.footer(1, 124.0)
	add_child(tray)
	var back := UIKit.button(Data.bi("返回", "Back"), UIKit.CREAM, UIKit.F_H2, Vector2(260, 74))
	back.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([back]))


## One on/off row: label, one-line explanation, and a button whose colour and
## word both carry the state (colour alone is not a readable answer to "is this
## on?" for the ~8% of players who cannot separate the two hues).
func _toggle(key: String, label: String, hint: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.S4)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.text_block(label, UIKit.F_BODY, UIKit.CREAM, 400.0,
			HORIZONTAL_ALIGNMENT_LEFT))
	col.add_child(UIKit.text_block(hint, UIKit.F_CAPTION, UIKit.CREAM_DARK, 400.0,
			HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(col)
	var on: bool = bool(Game.settings.get(key, false))
	var b := UIKit.button(Data.t("ui_on") if on else Data.t("ui_off"),
			UIKit.GREEN.lightened(0.3) if on else UIKit.CREAM_DARK,
			UIKit.F_BODY, Vector2(150, 64))
	b.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.settings[key] = not bool(Game.settings.get(key, false))
		Game.save_settings()
		_build())
	row.add_child(b)
	return row


func _confirm_reset() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	overlay.add_child(vb)
	var l := UIKit.label(Data.bi("確定清除所有進度?此操作無法復原!", "Erase ALL progress? This cannot be undone!"),
			26, UIKit.CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var yes := UIKit.button(Data.t("ui_confirm"), UIKit.RED.lightened(0.3), 24, Vector2(200, 70))
	yes.pressed.connect(func() -> void:
		Game.reset_all_data()
		Sfx.play("lose")
		Game.goto("menu"))
	row.add_child(yes)
	var no := UIKit.button(Data.t("ui_cancel"), UIKit.CREAM, 24, Vector2(200, 70))
	no.pressed.connect(func() -> void: overlay.queue_free())
	row.add_child(no)
	var rc := CenterContainer.new()
	rc.add_child(row)
	vb.add_child(rc)
