extends Control
## Rest site: Camp (heal 30% / 45% with Honey Jar) or Forge (+1 a numeric face).

func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 104.0, CAMP_GROUND))
	add_child(RunWidgets.topbar())

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	Safe.pin_top(vb, 168)
	vb.offset_left = UIKit.S5
	vb.offset_right = -UIKit.S5
	vb.add_theme_constant_override("separation", UIKit.S5)
	add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_rest"), UIKit.F_H1))
	vb.add_child(UIKit.outlined(UIKit.text_block(
			Data.bi("營火燒得正旺。今晚要做什麼?", "The fire is burning. What will you do tonight?"),
			UIKit.F_BODY_SM, UIKit.CREAM, 600.0)))
	vb.add_child(UIKit.spacer(UIKit.S2))

	var pct := int(GameData.balance.rest_heal_pct)
	var relic_pct := GameData.relic_value(Game.run.relics, "rest_heal_pct")
	if relic_pct > 0:
		pct = relic_pct
	var c1 := CenterContainer.new()
	vb.add_child(c1)
	c1.add_child(RunWidgets.offer_card(Data.t("ui_camp"),
			Data.bi("全隊回%d%% HP" % pct, "Party heals %d%% HP" % pct), "",
			UIKit.GREEN, func() -> void:
				Sfx.play("heal")
				RunState.team_alive_heal_pct(Game.run, pct)
				Game.node_completed(), Vector2(586, 196)))

	var c2 := CenterContainer.new()
	vb.add_child(c2)
	c2.add_child(RunWidgets.offer_card(Data.t("ui_forge"),
			Data.bi("自選一個骰面,數值 +1", "A chosen face gets +1"), "",
			UIKit.YELLOW, _on_forge, Vector2(586, 196)))

	# a campsite rather than a menu: the party sits around a fire on the ground
	# line, which is also what fills the lower third of the screen
	add_child(_campsite(chapter))


const CAMP_GROUND := 1000.0


func _campsite(chapter: int) -> Control:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fire := _Campfire.new()
	fire.set_anchors_preset(Control.PRESET_FULL_RECT)
	fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire.ground = CAMP_GROUND
	fire.glow = UITheme.accent(chapter)
	stage.add_child(fire)
	var team: Array = Game.run.get("team", [])
	var xs := [108.0, 240.0, 480.0, 612.0]
	for i in team.size():
		var hero: Dictionary = team[i]
		var x: float = xs[i % xs.size()]
		var shadow := Panel.new()
		var sb := UIKit.flat_box(Color(0, 0, 0, 0.28), 999, 0, UIKit.OUTLINE, 0)
		sb.set_border_width_all(0)
		shadow.add_theme_stylebox_override("panel", sb)
		shadow.position = Vector2(x - 46, CAMP_GROUND - 4)
		shadow.size = Vector2(92, 16)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(shadow)
		var pa := PawnArt.fitted(String(hero.id), Vector2(158, 158), x > 360.0)
		pa.position = Vector2(x, CAMP_GROUND + 4)
		if int(hero.hp) <= 0:
			pa.modulate = Color(0.42, 0.4, 0.4, 0.85)
		stage.add_child(pa)
	return stage


## Flat-shaded campfire: two crossed logs, three flame blocks, a ring of
## stones. Static art — nothing animates, so it costs one draw call once.
class _Campfire:
	extends Control
	var ground := 906.0
	var glow := Color("7fc46a")

	func _draw() -> void:
		var c := Vector2(360.0, ground)
		draw_circle(c + Vector2(0, -30), 104.0, Color(glow.r, glow.g, glow.b, 0.12))
		# stone ring, drawn as a full squashed ellipse so it reads as a circle
		# of rocks seen from the side rather than a stray row of dots
		for i in 9:
			var a := TAU * i / 9.0
			var p := c + Vector2(cos(a) * 70.0, sin(a) * 13.0)
			draw_circle(p, 12.0, Color("8d8478"))
			draw_arc(p, 12.0, 0, TAU, 16, UITheme.OUTLINE, 3.0, true)
		for s in [-1.0, 1.0]:
			var pts := PackedVector2Array([
				c + Vector2(s * -62, -2), c + Vector2(s * -54, -22),
				c + Vector2(s * 46, -40), c + Vector2(s * 54, -20)])
			draw_colored_polygon(pts, Color("4a3018"))
			draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.OUTLINE, 4.0, true)
		var flames := [[0.0, 78.0, 30.0, UITheme.YELLOW], [-22.0, 52.0, 20.0, UITheme.ORANGE],
				[22.0, 46.0, 18.0, Color("f0d27a")]]
		for f in flames:
			var fx: float = f[0]
			var fh: float = f[1]
			var fw: float = f[2]
			var tri := PackedVector2Array([
				c + Vector2(fx - fw, -32), c + Vector2(fx, -32 - fh), c + Vector2(fx + fw, -32)])
			draw_colored_polygon(tri, f[3])
			draw_polyline(tri + PackedVector2Array([tri[0]]), UITheme.OUTLINE, 4.0, true)
		


func _on_forge() -> void:
	Sfx.play("button")
	RunWidgets.pick_team_face(self, Data.t("ui_forge"),
		func(hi: int, slot: int) -> void:
			RunState.forge_face(Game.run.team[hi], slot)
			Sfx.play("win")
			Game.node_completed(),
		func(hero: Dictionary) -> Array:
			return RunState.forgeable_slots(hero))
