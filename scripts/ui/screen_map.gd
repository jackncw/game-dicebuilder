extends Control
## StS-style map: 9 rows climbing bottom→top, tap a connected node to enter.

const NODE_R := 34.0
const TYPE_CHAR := {
	"battle": "戰", "event": "事", "elite": "精",
	"shop": "店", "rest": "營", "treasure": "寶", "boss": "王",
}
const TYPE_COLOR := {
	"battle": UIKit.RED, "event": UIKit.YELLOW, "elite": UIKit.PURPLE,
	"shop": UIKit.BLUE, "rest": UIKit.GREEN, "treasure": UIKit.ORANGE,
	"boss": UIKit.RED,
}

var _lp_timer: SceneTreeTimer = null
var _tooltip: Control = null


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 96.0, 0.0))
	add_child(RunWidgets.topbar())

	var graph := Control.new()
	graph.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(graph)
	var lines := _EdgeLines.new()
	lines.map = Game.run.map
	lines.chapter = chapter
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph.add_child(lines)

	var avail: Array = RunState.available_nodes(Game.run)
	var avail_keys := {}
	for a in avail:
		avail_keys["%d_%d" % [a[0], a[1]]] = true

	var rows: Array = Game.run.map.rows
	for r in rows.size():
		for c in rows[r].size():
			var node: Dictionary = rows[r][c]
			var pos := node_pos(r, node.x)
			var key := "%d_%d" % [r, c]
			var is_avail: bool = avail_keys.has(key)
			var is_current: bool = r == int(Game.run.row) and c == int(Game.run.col)
			var is_past: bool = r <= int(Game.run.row)
			var btn := _make_node_btn(node, is_avail, is_current, is_past)
			btn.position = pos - Vector2(NODE_R, NODE_R) * (1.35 if node.type == "boss" else 1.0)
			graph.add_child(btn)
			if is_avail:
				var rr: int = r
				var cc: int = c
				btn.pressed.connect(func() -> void:
					Sfx.play("button")
					Game.enter_node(rr, cc))

	var tray := UIKit.footer(chapter, 116.0)
	add_child(tray)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UIKit.S4)
	var back := UIKit.button(Data.bi("主選單", "Menu"), UIKit.CREAM_DARK,
			UIKit.F_BODY, Vector2(180, 68))
	back.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.save_run()
		Game.goto("menu"))
	row.add_child(back)
	var hint := UIKit.label(Data.t("ui_next_node"), UIKit.F_BODY, UIKit.CREAM)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)
	tray.get_child(0).add_child(row)


## Where row `r` of the map sits. The nine rows are spread across whatever
## vertical band is left between the run top bar and the footer, so a phone that
## eats 94px of notch compresses the climb instead of pushing the boss clearing
## up underneath the status bar. With no insets this is the 1130 → 154 ladder
## the map has always had, step 122, to the pixel.
static func node_pos(r: int, x: float) -> Vector2:
	var bottom := 1280.0 - Safe.bottom - 150.0
	var top := Safe.top + 154.0
	var step := (bottom - top) / 8.0
	return Vector2(60.0 + x * 600.0, bottom - r * step)


func _make_node_btn(node: Dictionary, avail: bool, current: bool, past: bool) -> Button:
	var t := String(node.type)
	var size := NODE_R * (2.7 if t == "boss" else 2.0)
	var col: Color = TYPE_COLOR.get(t, UIKit.CREAM)
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	var sb := UIKit.flat_box(col.lightened(0.25) if avail else col.darkened(0.25), int(size / 2), 5 if avail else 3,
			UIKit.GREEN.lightened(0.3) if avail else (UIKit.CREAM if current else UIKit.OUTLINE))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)
	# every node is a clearing in the wood: bare earth ringed with stones, with
	# the type symbol standing in the middle of it
	var ring := _Clearing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ring)
	# drawn icons rather than a single CJK glyph: the map has to read the same
	# in every language mode, and a flat symbol beats a character at 34px
	var icon := _NodeIcon.new()
	icon.type = t
	icon.tint = UIKit.CREAM if (not past or current) else UIKit.CREAM.darkened(0.25)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	b.disabled = not avail
	if past and not current:
		b.modulate = Color(1, 1, 1, 0.45)
	# spyglass: preview enemies on battle nodes
	if GameData.has_relic_effect(Game.run.relics, "preview_battles") and node.has("encounter"):
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventMouseButton or ev is InputEventScreenTouch):
				if ev.pressed:
					var tm := get_tree().create_timer(0.5)
					_lp_timer = tm
					tm.timeout.connect(func() -> void:
						if _lp_timer == tm:
							_show_enemy_preview(node))
				else:
					_lp_timer = null)
	return b


func _show_enemy_preview(node: Dictionary) -> void:
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
	var names := []
	for key in node.encounter:
		var e: Dictionary = GameData.enemies[key]
		names.append(Data.bi(String(e.zh), String(e.en)))
	var panel := UIKit.panel(UIKit.CREAM, 14, 4)
	panel.add_child(UIKit.label("\n".join(names), 22, UIKit.OUTLINE))
	panel.position = Vector2(200, 560)
	add_child(panel)
	_tooltip = panel
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())


## The bare earth and ring of stones every node stands in. Drawn behind the
## type symbol, inside the button's own circle, so it costs the symbol nothing.
class _Clearing:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r * 0.82, Color(UITheme.DIRT, 0.55))
		for i in 8:
			var a := TAU * i / 8.0 + 0.3
			var p := c + Vector2(cos(a), sin(a)) * r * 0.84
			draw_circle(p, r * 0.11, Color(UITheme.STONE, 0.75))
			draw_arc(p, r * 0.11, 0.0, TAU, 10, UITheme.OUTLINE, 1.6, true)


## Flat node symbols, drawn in the same ink-outlined style as the pawns and
## sized off the button rect so one class serves normal and boss nodes.
class _NodeIcon:
	extends Control
	var type := "battle"
	var tint := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var u := size.x / 68.0     # designs authored for a 68px node
		match type:
			"battle": _swords(c, u)
			"elite": _star(c, 22.0 * u, 10.0 * u, 5)
			"boss": _crown(c, u)
			"shop": _coin(c, u)
			"rest": _tent(c, u)
			"treasure": _chest(c, u)
			_: _sign(c, u)

	func _blade(c: Vector2, u: float, dir: float) -> void:
		var pts := PackedVector2Array([
			c + Vector2(dir * -13, 16) * u, c + Vector2(dir * -7, 16) * u,
			c + Vector2(dir * 15, -14) * u, c + Vector2(dir * 9, -18) * u])
		draw_colored_polygon(pts, tint)
		draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.OUTLINE, 2.5 * u, true)

	func _swords(c: Vector2, u: float) -> void:
		_blade(c, u, 1.0)
		_blade(c, u, -1.0)

	func _star(c: Vector2, r: float, r2: float, n: int) -> void:
		var pts := PackedVector2Array()
		for i in n * 2:
			var a := -PI * 0.5 + PI * i / float(n)
			var rr := r if i % 2 == 0 else r2
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, tint)
		draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.OUTLINE, 2.5, true)

	func _crown(c: Vector2, u: float) -> void:
		var pts := PackedVector2Array([
			c + Vector2(-22, 16) * u, c + Vector2(-26, -14) * u, c + Vector2(-11, -1) * u,
			c + Vector2(0, -20) * u, c + Vector2(11, -1) * u, c + Vector2(26, -14) * u,
			c + Vector2(22, 16) * u])
		draw_colored_polygon(pts, tint)
		draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.OUTLINE, 3.0 * u, true)

	func _coin(c: Vector2, u: float) -> void:
		draw_circle(c, 19 * u, tint)
		draw_arc(c, 19 * u, 0, TAU, 28, UITheme.OUTLINE, 3.0 * u, true)
		draw_arc(c, 10 * u, 0, TAU, 20, UITheme.OUTLINE, 3.0 * u, true)

	func _tent(c: Vector2, u: float) -> void:
		var pts := PackedVector2Array([
			c + Vector2(-22, 16) * u, c + Vector2(0, -19) * u, c + Vector2(22, 16) * u])
		draw_colored_polygon(pts, tint)
		draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.OUTLINE, 3.0 * u, true)
		draw_line(c + Vector2(0, -19) * u, c + Vector2(0, 16) * u, UITheme.OUTLINE, 3.0 * u)

	func _chest(c: Vector2, u: float) -> void:
		var body := Rect2(c + Vector2(-21, -4) * u, Vector2(42, 20) * u)
		draw_rect(body, tint)
		draw_rect(body, UITheme.OUTLINE, false, 3.0 * u)
		var lid := PackedVector2Array([
			c + Vector2(-21, -4) * u, c + Vector2(-21, -12) * u,
			c + Vector2(21, -12) * u, c + Vector2(21, -4) * u])
		draw_colored_polygon(lid, tint)
		draw_polyline(lid + PackedVector2Array([lid[0]]), UITheme.OUTLINE, 3.0 * u, true)
		draw_rect(Rect2(c + Vector2(-4, -8) * u, Vector2(8, 12) * u), UITheme.OUTLINE)

	## Event: a question mark. Two crossed signpost arms turned into mush at
	## 34px; a "?" survives the shrink and needs no translation.
	func _sign(c: Vector2, u: float) -> void:
		var hook := c + Vector2(0, -8) * u
		draw_arc(hook, 11 * u, PI, TAU + PI * 0.35, 24, tint, 7.0 * u, true)
		draw_line(c + Vector2(4, -2) * u, c + Vector2(0, 8) * u, tint, 7.0 * u)
		draw_circle(c + Vector2(0, 17) * u, 4.5 * u, tint)


## Winding dirt paths between the clearings, with trees scattered either side.
##
## A straight line between two nodes reads as a graph; a track that bends and
## breaks into footfalls reads as a walk through a wood. The bend is derived
## from the node coordinates, not from rng, so the map never redraws
## differently from one frame to the next.
class _EdgeLines:
	extends Control
	var map := {}
	var chapter := 1

	const DASH := 13.0
	const GAP := 9.0

	func _draw() -> void:
		var rows: Array = map.rows
		_trees(rows)
		for r in rows.size() - 1:
			for c in rows[r].size():
				var from: Vector2 = screen_map_pos(r, rows[r][c].x)
				for j in rows[r][c].edges:
					var to: Vector2 = screen_map_pos(r + 1, rows[r + 1][j].x)
					_track(from, to, r * 7 + c * 3 + int(j))

	## One path: a quadratic bend laid down as a broad soft track, with a dashed
	## line of footfalls along the middle of it.
	func _track(a: Vector2, b: Vector2, salt: int) -> void:
		var mid := (a + b) * 0.5
		var perp := (b - a).orthogonal().normalized()
		var bend: float = 22.0 * (1.0 if salt % 2 == 0 else -1.0) * (0.5 + fmod(salt * 0.37, 1.0))
		var ctrl := mid + perp * bend
		var pts := PackedVector2Array()
		for i in 15:
			var t := i / 14.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		draw_polyline(pts, Color(UITheme.DIRT, 0.42), 13.0, true)
		var walked := 0.0
		for i2 in pts.size() - 1:
			var seg: float = pts[i2].distance_to(pts[i2 + 1])
			if seg <= 0.001:
				continue
			var pos := walked
			while pos < walked + seg:
				var t0: float = (pos - walked) / seg
				var t1: float = minf((pos - walked + DASH) / seg, 1.0)
				if fmod(pos, DASH + GAP) < DASH:
					draw_line(pts[i2].lerp(pts[i2 + 1], t0), pts[i2].lerp(pts[i2 + 1], t1),
							Color(UITheme.DIRT_STEP, 0.5), 3.4, true)
				pos += DASH
			walked += seg

	## Blunt conifers down both sides of the column of nodes, so the map reads as
	## a wood the party is walking through rather than a flow chart.
	func _trees(rows: Array) -> void:
		var near: Color = UITheme.surface_deep(chapter)
		var far: Color = UITheme.surface(chapter)
		for r in rows.size():
			var y: float = screen_map_pos(r, 0.0).y
			for side in [0, 1]:
				var x: float = 22.0 + side * 664.0 + (14.0 if r % 2 == 0 else -10.0)
				var h: float = 54.0 + fmod(r * 23.0 + side * 17.0, 34.0)
				var w: float = 20.0 + fmod(r * 11.0, 9.0)
				var col: Color = near if (r + side) % 2 == 0 else far
				draw_rect(Rect2(Vector2(x - 3.0, y + 20.0), Vector2(6.0, 12.0)),
						Color(UITheme.BARK, 0.6))
				draw_colored_polygon(PackedVector2Array([
					Vector2(x - w, y + 24.0), Vector2(x, y + 24.0 - h),
					Vector2(x + w, y + 24.0)]), Color(col.r, col.g, col.b, 0.62))

	static func screen_map_pos(r: int, x: float) -> Vector2:
		return Vector2(60.0 + x * 600.0, 1130.0 - r * 122.0)
