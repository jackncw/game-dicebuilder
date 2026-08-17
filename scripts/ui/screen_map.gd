extends Control
## StS-style map: 9 rows climbing bottom→top, tap a connected node to enter.
##
## 任務4(第十輪):the whole chapter lives inside a vertical ScrollContainer
## on its classic 1130→154 ladder — a phone-height canvas scrolls the climb
## instead of compressing it, and the current reachable rung is auto-scrolled
## into view. 呢個順手執埋一個潛藏 bug:節點以前行 inset-aware 座標而路徑/
## 樹行固定座標,一有 notch 兩者就對唔上;而家全部行同一套內容座標。

const NODE_R := 34.0
const TYPE_COLOR := {
	"battle": UIKit.RED, "event": UIKit.YELLOW, "elite": UIKit.PURPLE,
	"shop": UIKit.BLUE, "rest": UIKit.GREEN, "treasure": UIKit.ORANGE,
	"boss": UIKit.RED,
}
## 節點類型注釋(跟語言模式)。540 寬度實測(mockup 截圖自評)20px 帶
## outline 仲讀得出;再細先需要圖例條方案。
const TYPE_NAME := {
	"battle": ["戰鬥", "Battle"], "event": ["事件", "Event"],
	"elite": ["精英", "Elite"], "shop": ["商店", "Shop"],
	"rest": ["休息", "Rest"], "treasure": ["寶箱", "Chest"],
	"boss": ["頭目", "Boss"],
}
const TYPE_LABEL_FONT := 20

## Content-space ladder: bottom row at 1130, step 122, boss row at 154 — the
## geometry the map has always had, now on a scrollable 1200-tall sheet.
const MAP_H := 1200.0
const FOOT_H := 116.0
const TOP_BAND := 64.0

var _lp_timer: SceneTreeTimer = null
var _tooltip: Control = null
var _scroll: ScrollContainer = null
var _avail_btns: Array = []
var _marker: Node2D = null    # the party's pawn standing on the trail (PawnArt)
var _moving := false          # a walk animation is in flight; taps wait
var _bob: Tween = null        # the marker's idle bob; killed before a walk


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 96.0, 0.0))

	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 0.0
	_scroll.anchor_right = 1.0
	_scroll.anchor_top = 0.0
	_scroll.anchor_bottom = 1.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Safe.pin_top(_scroll, TOP_BAND)
	Safe.pin_bottom(_scroll, FOOT_H)
	add_child(_scroll)

	var graph := Control.new()
	graph.custom_minimum_size = Vector2(720.0, MAP_H)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(graph)
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
			var half := NODE_R * (1.35 if node.type == "boss" else 1.0)
			btn.position = pos - Vector2(half, half)
			graph.add_child(btn)
			var rr: int = r
			var cc: int = c
			if is_avail:
				_avail_btns.append(btn)
				btn.pressed.connect(func() -> void:
					if _moving:
						return
					Sfx.play("button")
					_walk_to(rr, cc))
			else:
				# 未去到(或者已經過咗)嘅節點:一撳彈類型名確認 —— 細螢幕下
				# 靠注釋唔夠嘅後備通道
				btn.pressed.connect(func() -> void:
					_show_type_tip(node, btn))
			# 類型注釋:icon 下面一行細字(戰鬥/精英/事件…),跟語言模式
			var nm: Array = TYPE_NAME.get(String(node.type), ["?", "?"])
			var lbl := UIKit.outlined(UIKit.text_block(
					Data.bi(String(nm[0]), String(nm[1])), TYPE_LABEL_FONT,
					UIKit.CREAM if (is_avail or is_current or not is_past) else UIKit.CREAM_DARK,
					150.0), 5)
			lbl.position = Vector2(pos.x - 75.0, pos.y + half - 2.0)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if is_past and not is_current:
				lbl.modulate = Color(1, 1, 1, 0.5)
			graph.add_child(lbl)

	# 玩家標記:隊伍嘅先鋒企喺而家所在嘅空地,行去下一個節點會真係行過去
	var lead := String(Game.run.team[0].id)
	_marker = PawnArt.fitted(lead, Vector2(84, 84))
	_marker.position = _marker_home()
	graph.add_child(_marker)
	if DisplayServer.get_name() != "headless" and not Fx.reduced():
		# a soft idle bob so the trail reads as "someone standing here"
		_bob = _marker.create_tween().set_loops()
		_bob.tween_property(_marker, "position:y", _marker.position.y - 5.0, 1.1) 				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_bob.tween_property(_marker, "position:y", _marker.position.y, 1.1) 				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# 拉埋 topbar 先加,等佢浮喺 scroll 上面
	add_child(RunWidgets.topbar())

	var tray := UIKit.footer(chapter, FOOT_H)
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

	_autoscroll.call_deferred()
	if _scroll.get_v_scroll_bar() != null:
		_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void:
			_publish_rects.call_deferred())

	# 新章開幕:row == -1 即係啱啱踏入呢一章 —— 出章節 title 卡先
	if int(Game.run.row) < 0 and DisplayServer.get_name() != "headless":
		_chapter_card(chapter)


## Where the marker stands right now: on the current node, or at the trailhead
## below the first rung when the chapter has only just begun.
func _marker_home() -> Vector2:
	var r := int(Game.run.row)
	if r < 0:
		return Vector2(360.0, 1224.0)
	var c := int(Game.run.col)
	var node: Dictionary = Game.run.map.rows[r][c]
	return node_pos(r, float(node.x)) - Vector2(0.0, NODE_R *
			(1.35 if String(node.type) == "boss" else 1.0) - 10.0)


## The walk: the pawn strolls the trail to the tapped clearing — footsteps and
## all — and only when it arrives does the node actually open. Headless goes
## straight in; fast_anim walks at double pace.
func _walk_to(r: int, c: int) -> void:
	if DisplayServer.get_name() == "headless" or _marker == null 			or not is_instance_valid(_marker):
		Game.enter_node(r, c)
		return
	_moving = true
	if _bob != null and _bob.is_valid():
		_bob.kill()
	var node: Dictionary = Game.run.map.rows[r][c]
	var to := node_pos(r, float(node.x)) - Vector2(0.0, NODE_R *
			(1.35 if String(node.type) == "boss" else 1.0) - 10.0)
	var from := _marker.position
	var t_walk := Fx.dur(0.42)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(_marker):
			return
		var p := from.lerp(to, t)
		p.y -= sin(t * PI * 3.0) * 7.0  # three little hops along the trail
		_marker.position = p,
		0.0, 1.0, t_walk)
	for k in 3:
		get_tree().create_timer(t_walk * (0.12 + 0.3 * k)).timeout.connect(
				func() -> void: Sfx.play("step", 0.7, randf_range(0.9, 1.12)))
	tw.tween_callback(func() -> void:
		Game.enter_node(r, c))


## 章節 title 卡:章號 + 氛圍一句,揸 1.5 秒(或者一撳)就散。
const CHAPTER_FLAVOR := {
	1: ["林緣", "The Fringe",
		"晨光仍然照得進來的邊界。", "Where morning light still reaches."],
	2: ["深林", "The Deepwood",
		"暮色滲進樹影,腐化的氣味越來越近。", "Dusk seeps in; the rot smells closer."],
	3: ["病竈", "The Blight Heart",
		"森林病得最重的地方,病源就在前面。", "The sickest reach of the wood. The source lies ahead."],
}


func _chapter_card(chapter: int) -> void:
	var fl: Array = CHAPTER_FLAVOR.get(chapter, CHAPTER_FLAVOR[1])
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.04, 0.03, 0.0)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UIKit.S3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_child(col)
	var head := UIKit.title("%s %d · %s" % [Data.t("ui_chapter"), chapter,
			String(fl[0])], UIKit.F_DISPLAY, UIKit.CREAM)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(head)
	col.add_child(UIKit.text_block(String(fl[1]), UIKit.F_H2, UIKit.CREAM_DARK, 640.0))
	col.add_child(UIKit.spacer(UIKit.S3))
	col.add_child(UIKit.text_block(Data.bi(String(fl[2]), String(fl[3])),
			UIKit.F_BODY, UIKit.CREAM, 620.0))
	Sfx.play("swoosh", 0.7)
	var tw := create_tween()
	tw.tween_property(scrim, "color:a", 0.82, Fx.dur(0.3))
	tw.tween_interval(Fx.dur(1.5))
	tw.tween_property(scrim, "modulate:a", 0.0, Fx.dur(0.45))
	tw.tween_callback(scrim.queue_free)
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
			scrim.queue_free())


## 當前可去嘅節點自動捲入視野 —— run 開頭喺梯底,尾段喺梯頂,唔應該要玩家
## 自己搵。
func _autoscroll() -> void:
	if not is_instance_valid(_scroll):
		return
	var target := MAP_H
	var avail: Array = RunState.available_nodes(Game.run)
	for a in avail:
		target = minf(target, node_pos(int(a[0]), 0.0).y)
	var vis := _scroll.size.y
	_scroll.scroll_vertical = int(clampf(target - vis * 0.55, 0.0, maxf(MAP_H - vis, 0.0)))
	_publish_rects.call_deferred()


## The reachable nodes' rects, for the browser-side regression (`__dgHUD`).
func _publish_rects() -> void:
	for i in _avail_btns.size():
		var b = _avail_btns[i]
		if is_instance_valid(b):
			Safe.publish_hud("map_avail%d" % i, (b as Control).get_global_rect())


## 撳未可去嘅節點:喺節點旁邊彈個類型名細牌,1.6 秒自動散
func _show_type_tip(node: Dictionary, btn: Control) -> void:
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
	var nm: Array = TYPE_NAME.get(String(node.type), ["?", "?"])
	var panel := UIKit.panel(UIKit.CREAM, 12, 3)
	panel.add_child(UIKit.label(Data.bi(String(nm[0]), String(nm[1])), UIKit.F_BODY, UIKit.OUTLINE))
	var g := btn.get_global_rect()
	add_child(panel)
	# beside the node, clamped onto the canvas
	panel.position = Vector2(clampf(g.position.x + g.size.x * 0.5 - 60.0, 8.0, 560.0),
			maxf(g.position.y - 64.0, 8.0))
	_tooltip = panel
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())


## Where row `r` of the map sits, in GRAPH CONTENT coordinates. One coordinate
## system for nodes, edges and trees alike — the scroll container does the
## phone-height work now, so no inset maths in here.
static func node_pos(r: int, x: float) -> Vector2:
	return Vector2(60.0 + x * 600.0, 1130.0 - r * 122.0)


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
	# 唔再 disabled:非可去節點都受撳 —— 撳落去彈類型名(任務4)。視覺上照舊
	# 靠底色深淺同 modulate 分可去/未可去。
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
