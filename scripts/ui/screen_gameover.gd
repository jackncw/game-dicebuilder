extends Control
## Run lost: all heroes down. No hard cut — the screen breathes in slowly,
## says how far the run got, and puts "one more run" front and centre.

var args := {}


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	Music.stop(1.4)
	Sfx.play("lose")
	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, Fx.dur(0.85))
	var bg := ColorRect.new()
	bg.color = UITheme.DANGER_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# the same wood as everywhere else, drained of colour and with nothing
	# alive drifting through the air
	var trees := Forest.scenery(3, 150.0, 980.0, false)
	trees.modulate = Color(0.62, 0.44, 0.44)
	add_child(trees)
	var ground := ColorRect.new()
	ground.color = Color("1c1313")
	ground.anchor_right = 1.0
	ground.anchor_top = 1.0
	ground.anchor_bottom = 1.0
	ground.offset_top = 980.0
	add_child(ground)

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	Safe.pin_top(vb, 380)
	vb.add_theme_constant_override("separation", UIKit.S5)
	add_child(vb)
	vb.add_child(UIKit.outlined(UIKit.text_block(Data.t("ui_defeat"),
			UIKit.F_DISPLAY, UITheme.CAT_ON_DARK.attack, 640.0), 8))
	vb.add_child(UIKit.text_block(
			Data.bi("冒險在森林深處終結……", "The run ends deep in the forest…"),
			UIKit.F_BODY, UIKit.CREAM_DARK, 600.0))

	# the party fallen on the forest floor, so the screen is not just a headline
	var lie := [[108.0, 0.3], [274.0, -0.22], [446.0, 0.2], [616.0, -0.28]]
	var fallen := GameData.starter_hero_ids()
	for i in mini(fallen.size(), lie.size()):
		var pa := PawnArt.fitted(String(fallen[i]), Vector2(150, 150))
		pa.position = Vector2(float(lie[i][0]), 1002.0)
		pa.rotation = float(lie[i][1])
		pa.modulate = Color(0.44, 0.37, 0.37, 0.92)
		add_child(pa)

	var toll := UIKit.card(1)
	var tbox: StyleBoxFlat = toll.get_theme_stylebox("panel")
	tbox.bg_color = Color("241717")
	tbox.border_color = UIKit.RED.darkened(0.35)
	toll.anchor_left = 0.5
	toll.anchor_right = 0.5
	toll.offset_left = -280
	toll.offset_right = 280
	toll.offset_top = 640
	toll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", UIKit.S2)
	toll.add_child(tv)
	# 安慰性統計:行到邊、打咗幾多場 — the run mattered even though it ended.
	# The numbers ride in on the goto args; the run save is already gone.
	var reached := int(args.get("chapter", Game.run.get("chapter", 1) if Game.run is Dictionary and not Game.run.is_empty() else 1))
	var stats: Dictionary = args.get("stats", {})
	var line := "%s %d" % [Data.t("ui_chapter"), reached]
	if int(stats.get("battles", 0)) > 0:
		line += "  ·  %s ×%d" % [Data.bi("戰鬥", "battles"), int(stats.get("battles", 0))]
	if int(stats.get("nodes", 0)) > 0:
		line += "  ·  %s ×%d" % [Data.bi("節點", "nodes"), int(stats.get("nodes", 0))]
	tv.add_child(UIKit.text_block(line, UIKit.F_H2, UIKit.CREAM, 500.0))
	tv.add_child(UIKit.text_block(
			Data.bi("森林記住了你們。下次再來。", "The grove remembers. Come back stronger."),
			UIKit.F_BODY_SM, UIKit.CREAM_DARK, 500.0))
	add_child(toll)

	var tray := UIKit.footer(1, 124.0)
	var tsb: StyleBoxFlat = tray.get_theme_stylebox("panel")
	tsb.bg_color = Color("140d0d")
	add_child(tray)
	# 「再嚟一局」is the big one; the menu is the side door
	var again := UIKit.button(Data.bi("再嚟一局", "One more run"),
			UIKit.GREEN.lightened(0.3), UIKit.F_H2, Vector2(340, 78))
	again.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("charselect"))
	var b := UIKit.button(Data.bi("主選單", "Menu"), UIKit.CREAM_DARK,
			UIKit.F_BODY, Vector2(220, 70))
	b.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([again, b]))
