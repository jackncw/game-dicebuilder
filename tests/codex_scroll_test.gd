extends Node
## Codex touch-scroll regression (round 13 task A).
##
## The real-phone report: the codex page does not scroll at all under a finger.
## This drives the same three input shapes as drag_input_test (mouse, mouse with
## touch emulation, pure touch) through the codex and asserts BOTH halves of the
## contract:
##   · a drag longer than the tap threshold scrolls the page and does NOT open
##     a face detail card;
##   · a short tap on a face tile still opens the detail card.
##
##   godot --headless --path . res://tests/codex_scroll_test.tscn

var fails := 0
var tests := 0
var codex: Control = null
var holder: Control = null
var _sc_touch_events := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)
	else:
		print("  ok: " + msg)


func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = pos
	_push(e)


func _touch_drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	_push(e)


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos * 1.5
	_push(e)


func _mouse_motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos * 1.5
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(e)


func _send(mode: String, kind: String, pos: Vector2, rel := Vector2.ZERO) -> void:
	match kind:
		"press":
			if mode != "touch":
				_mouse_button(pos, true)
			if mode != "mouse":
				_touch(pos, true)
		"move":
			if mode != "touch":
				_mouse_motion(pos)
			if mode != "mouse":
				_touch_drag(pos, rel)
		"release":
			if mode != "touch":
				_mouse_button(pos, false)
			if mode != "mouse":
				_touch(pos, false)


## Press at `from`, walk to `to` in 6 steps, release. Mirrors a finger fling.
func _drag(mode: String, from: Vector2, to: Vector2) -> void:
	_send(mode, "press", from)
	await get_tree().process_frame
	var prev := from
	for k in range(1, 7):
		var p := from.lerp(to, float(k) / 6.0)
		_send(mode, "move", p, p - prev)
		prev = p
		await get_tree().process_frame
	_send(mode, "release", to)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap(mode: String, pos: Vector2) -> void:
	_send(mode, "press", pos)
	await get_tree().process_frame
	_send(mode, "release", pos)
	await get_tree().process_frame
	await get_tree().process_frame


var _base_children := 0


## DetailCard._present adds one anonymous full-rect child to the screen; a
## fresh codex has a fixed child count, so "more children than at build time"
## means a card is up.
func _detail_open() -> bool:
	return codex.get_child_count() > _base_children


func _fresh_codex() -> void:
	if is_instance_valid(codex):
		codex.queue_free()
		await get_tree().process_frame
	codex = load("res://scripts/ui/screen_codex.gd").new()
	codex.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(codex)
	for i in 4:
		await get_tree().process_frame
	_base_children = codex.get_child_count()
	_sc_touch_events = 0
	# Headless has no touchscreen, so ScrollContainer's own finger-drag branch
	# never arms (DisplayServer.is_touchscreen_available()). What CAN be proved
	# here is the exact thing the bug broke: that touch events which start on a
	# tile or a panel actually REACH the ScrollContainer instead of being eaten.
	# The end-to-end finger scroll on a touchscreen is web/tests' job.
	codex.scroll.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenDrag or e is InputEventScreenTouch:
			_sc_touch_events += 1)


func _ready() -> void:
	GameData.load_all()
	Game.settings.lang_mode = "both"
	Game.meta.unlocked_heroes = GameData.starter_hero_ids()
	holder = Control.new()
	holder.size = Vector2(720, 1280)
	holder.custom_minimum_size = Vector2(720, 1280)
	add_child(holder)
	await get_tree().process_frame

	for mode in ["mouse", "mouse_emu", "touch"]:
		await _fresh_codex()
		var scroll: ScrollContainer = codex.scroll
		_check(scroll.get_v_scroll_bar().max_value > scroll.size.y + 10.0,
				"[%s] codex body is taller than the view (scrollable at all)" % mode)

		# drag upward across the face-grid area — the finger starts ON a tile.
		# Pure mouse drags are not a scroll gesture (desktop scrolls by wheel;
		# live, emulate_touch_from_mouse turns every real drag into the touch
		# pair) — so "mouse" asserts the wheel path instead.
		var start := Vector2(360, 900)
		var end := Vector2(360, 400)
		await _drag(mode, start, end)
		if mode != "mouse":
			_check(_sc_touch_events >= 6,
					"[%s] the touch drag reached the ScrollContainer (%d events; STOP tiles/panels used to eat them all)"
					% [mode, _sc_touch_events])
		_check(not _detail_open(),
				"[%s] a 500px drag did NOT open a face detail" % mode)

		# the wheel path scrolls for real, in every mode — it exercises the same
		# PASS chain the finger uses
		var v0 := scroll.scroll_vertical
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.factor = 1.0
		e.position = start
		e.global_position = start * 1.5
		_push(e)
		var er := InputEventMouseButton.new()
		er.button_index = MOUSE_BUTTON_WHEEL_DOWN
		er.pressed = false
		er.position = start
		er.global_position = start * 1.5
		_push(er)
		await get_tree().process_frame
		_check(scroll.scroll_vertical > v0,
				"[%s] wheel over a face tile scrolled the codex (v %d -> %d)" % [mode, v0, scroll.scroll_vertical])

		# a short tap on a face tile opens the detail card
		var tile := _find_tile()
		if tile == null:
			_check(false, "[%s] found a revealed face tile to tap" % mode)
			continue
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		await get_tree().process_frame
		var pos := tile.get_global_rect().get_center()
		await _tap(mode, pos)
		_check(_detail_open(), "[%s] tap on a face tile opened the detail card" % mode)

	print("codex_scroll_test: %d checks, %d failed" % [tests, fails])
	print("CODEXSCROLL %s" % ("OK" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails > 0 else 0)


func _find_tile() -> Control:
	return _find_tile_in(codex.body)


func _find_tile_in(n: Node) -> Control:
	if n is FaceTile and n.interactive and not n.dimmed:
		var r: Rect2 = n.get_global_rect()
		if r.position.y > 200 and r.position.y < 1100:
			return n
	for c in n.get_children():
		var hit := _find_tile_in(c)
		if hit != null:
			return hit
	return null
