extends Node
## Headless UI smoke test: drives the battle screen through both its input
## paths — tap-to-select and drag-and-drop — until the battle ends, asserting
## no crashes and that the result overlay appears.
##   godot --headless --path . res://tests/ui_smoke.tscn

var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _make_battle() -> Control:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E01"],
			"opts": {"chapter": 1}, "battle_seed": 555})
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	# the enemy phase is a timed sequence in the shipping game; the tests want
	# it resolved as fast as frames can be pumped
	battle.instant_anim = true
	add_child(battle)
	return battle


func _ready() -> void:
	await get_tree().process_frame
	await _t_tap_playthrough()
	await _t_drag_targeting()
	await _t_float_anchors()
	await _t_die_render()
	_t_contrast()
	if fails == 0:
		print("UI SMOKE OK")
	else:
		print("UI SMOKE FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Plays a whole battle through the tap path.
func _t_tap_playthrough() -> void:
	var battle := _make_battle()
	await get_tree().process_frame
	_check(battle.die_widgets.size() == 8, "8 dice on the table, got %d" % battle.die_widgets.size())

	var guard := 0
	while not battle.bc.s.over and guard < 40:
		guard += 1
		if guard == 1:
			battle.bc.toggle_lock(0, 0)
			battle._refresh()
			battle.bc.toggle_lock(0, 0)
			battle._refresh()
		if guard == 2:
			battle.bc.s.rerolls = 1
			battle._on_reroll()
			await get_tree().process_frame
		for i in 4:
			if battle.bc.s.over:
				break
			for d in BattleCore.DICE:
				if battle.bc.s.over or not battle.bc.can_use(i, d).ok:
					continue
				battle._on_die_pressed(i, d)
				await get_tree().process_frame
				if battle.sel.is_empty():
					break     # a no-target face resolved on the first tap
				var spec: Dictionary = battle._drop_spec()
				if not spec.enemies.is_empty():
					battle._on_enemy_tapped(int(spec.enemies[0]))
				elif not spec.heroes.is_empty():
					battle._on_hero_tapped(int(spec.heroes[0]))
				elif bool(spec.enemy_dice):
					var dice: Array = battle.bc._targetable_dice()
					if dice.is_empty():
						battle._deselect()
						battle._refresh()
					else:
						battle._on_enemy_die_tapped(int(dice[0].enemy), int(dice[0].die))
				elif bool(spec.cast):
					battle._on_cast_tapped()       # tap the centre pad
				else:
					battle._deselect()
					battle._refresh()
				await get_tree().process_frame
				break
		if guard == 1 and battle.bc.can_undo():
			battle._on_undo()
			await get_tree().process_frame
		if not battle.bc.s.over:
			await battle.end_turn_and_wait()
			await get_tree().process_frame

	_check(battle.bc.s.over, "battle ended (guard=%d)" % guard)
	await get_tree().process_frame
	_check(battle.overlay != null, "result overlay shown")
	print("battle result: victory=%s turn=%d" % [battle.bc.s.victory, battle.bc.s.turn])
	battle.queue_free()


## Pick a die up and carry it to `to`, arming the drag on the way — the battle
## screen only lets go of a die that has actually travelled (see DRAG_ARM).
func _carry(battle: Control, i: int, d: int, to: Vector2) -> void:
	battle._on_drag_started(i, d, Vector2(100, 800), -1)
	await get_tree().process_frame
	if battle.drag.is_empty():
		return
	for k in range(1, 4):
		battle._on_drag_moved(Vector2(100, 800).lerp(to, float(k) / 3.0))
	await get_tree().process_frame


## Exercises the drag path: a legal drop resolves, an illegal one cancels.
func _t_drag_targeting() -> void:
	var battle := _make_battle()
	await get_tree().process_frame
	# force hero 0's A die to a single-target attack so the test is deterministic
	battle.bc.s.heroes[0].faces[0] = "hare_quick3"
	battle.bc.s.heroes[0].rolled = [0, 6]
	battle.bc.s.heroes[0].used = false
	battle._refresh()
	await get_tree().process_frame

	# --- illegal drop: released over empty space, nothing is spent
	await _carry(battle, 0, 0, Vector2(20, 1270))
	_check(not battle.drag.is_empty(), "drag started")
	_check(battle.drag_ghost != null, "drag ghost spawned")
	var spec: Dictionary = battle._drop_spec()
	_check(not spec.enemies.is_empty(), "enemies highlighted while dragging an attack")
	battle._on_drag_ended(Vector2(20, 1270))
	await get_tree().process_frame
	_check(battle.drag.is_empty(), "drag cleared after an illegal drop")
	_check(not battle.bc.s.heroes[0].used, "illegal drop spent nothing")
	_check(battle.drag_ghost == null, "ghost removed")

	# --- legal drop onto the first enemy card. Picking the die up rebuilds the
	# enemy row, so the point is measured ONCE up front and then reused — the
	# card node itself is gone by the time the drop happens.
	var hp_before: int = battle.bc.s.enemies[0].hp
	var at: Vector2 = battle.enemy_widgets[0].card.get_global_rect().get_center()
	await _carry(battle, 0, 0, at)
	_check(battle._armed(), "the carried die armed past the throw distance")
	battle._on_drag_ended(at)
	await get_tree().process_frame
	_check(battle.bc.s.heroes[0].used, "legal drop spent the die")
	_check(0 in battle.bc.s.heroes[0].used_dice, "the dragged die is the one spent")
	_check(battle.bc.s.enemies[0].hp < hp_before, "the enemy took damage")

	# --- the other die is now locked out and refuses a drag.
	# The enemy row was rebuilt by the drop above, so the card we measured
	# earlier is gone; re-read it rather than poking a freed node.
	var at2: Vector2 = battle.enemy_widgets[0].card.get_global_rect().get_center()
	await _carry(battle, 0, 1, at2)
	_check(battle.drag.is_empty(), "locked-out die cannot be dragged")
	battle.queue_free()


## A free-spin die has to draw itself and then stop drawing itself.
##
## Both halves were broken. `DetailCard.show_die` turns free spin on before the
## widget is in the tree, and `_render_once` used to refuse to take a still for a
## free-spin die — so the long-press card opened onto a grey square that only
## appeared once you poked it. At the other end, the die used to go to
## UPDATE_DISABLED in the same frame it set its final pose, one frame before that
## pose could reach the texture.
##
## `_process` is called by hand with a fixed delta: headless frames come as fast
## as the machine can make them, so a frame count would be timing noise.
func _t_die_render() -> void:
	var faces := []
	for fid in GameData.heroes["HARE"].start:
		var fd: Dictionary = GameData.faces[String(fid)].duplicate()
		fd["id"] = String(fid)
		faces.append(fd)

	var die := Die3D.new(Vector2(76, 76))
	# the exact order the detail card uses: configured, then mounted
	die.enable_free_spin()
	die.set_die(faces, 0)
	add_child(die)
	_check(die._vp.render_target_update_mode != SubViewport.UPDATE_DISABLED,
			"a free-spin die asks for a frame the moment it enters the tree")
	for i in 6:
		die._process(0.016)
	_check(die._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"and sleeps once the still has landed")
	_check(not die.is_processing(), "a parked die is off the process list")

	# --- a flick: spins, coasts, stops, and only then stops rendering
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = die.size * 0.5
	die._gui_input(down)
	for k in 3:
		var mv := InputEventMouseMotion.new()
		mv.position = die.size * 0.5 + Vector2(18, -6) * float(k + 1)
		mv.relative = Vector2(18, -6)
		die._gui_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = die.size * 0.5 + Vector2(54, -18)
	die._gui_input(up)
	_check(die.is_processing(), "a flicked die keeps rendering while it spins")

	var ticks := 0
	while die.is_processing() and ticks < 500:      # 500 x 20ms = 10 simulated s
		die._process(0.02)
		ticks += 1
	print("die free spin: coasted %.1fs after the flick" % (ticks * 0.02))
	_check(ticks < 500, "a flick coasts to a stop (ticks=%d)" % ticks)
	_check(ticks > 20, "and does not stop dead on release (ticks=%d)" % ticks)
	_check(die._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"a stopped die stops rendering")
	# the pose it stopped in is the one on the texture: sleeping is only ever
	# reached through the pump, never straight out of the settle branch
	_check(die._mesh.basis.is_equal_approx(die.rest_basis(die.shown)),
			"it stops square on the face that was up")
	die.queue_free()
	await get_tree().process_frame


## The art-review rule the whole palette was built around: any body text has to
## clear 4.5:1 against the surface it is printed on. Locks in the pairings so a
## future colour tweak cannot quietly push a screen back under the line.
func _t_contrast() -> void:
	for ch in [1, 2, 3]:
		var surf := UITheme.surface(ch)
		var deep := UITheme.surface_deep(ch)
		var sky := UITheme.bg(ch)
		_ratio(UITheme.CREAM, surf, "cream on chapter %d card" % ch)
		_ratio(UITheme.CREAM_DARK, surf, "cream-dark on chapter %d card" % ch)
		_ratio(UITheme.CREAM, deep, "cream on chapter %d tray" % ch)
		_ratio(UITheme.CREAM_DARK, deep, "cream-dark on chapter %d tray" % ch)
		# text printed straight on the sky only ever uses full cream
		_ratio(UITheme.CREAM, sky, "cream on chapter %d sky" % ch)
		for cat in UITheme.CAT_ON_DARK:
			_ratio(UITheme.CAT_ON_DARK[cat], surf, "%s accent on chapter %d card" % [cat, ch])
	# chips: cream on the deep fill, for every category
	for cat2 in UITheme.CAT_DEEP:
		_ratio(UITheme.CREAM, UITheme.CAT_DEEP[cat2], "chip text on %s chip" % cat2)
	# ink on paper, and the disabled-button pairing
	_ratio(UITheme.INK, UITheme.CREAM, "ink on cream")
	_ratio(UITheme.INK_SOFT, UITheme.CREAM, "soft ink on cream")
	_ratio(Color("3a372f"), Color("b0aba0"), "disabled button label")


func _ratio(fg: Color, bg: Color, what: String) -> void:
	var r := UITheme.contrast(fg, bg)
	_check(r >= 4.5, "%s is %.2f:1, needs 4.5:1" % [what, r])


## The floating-number regression: a damage number has to land inside the rect
## of the thing it happened to. The old failure was that `_refresh()` frees and
## rebuilds the rows, so the number was measured against cards that had not
## been laid out yet and flew to the top-left corner.
func _t_float_anchors() -> void:
	var battle := _make_battle()
	for i in 6:
		await get_tree().process_frame

	# --- hero side: push a hit through the same event path the enemy turn uses
	var hero_rect: Rect2 = battle.hero_cards[2].get_global_rect()
	battle.bc._ev({"t": "enemy_hit", "hero": 2, "enemy": 0, "dmg": 6, "blocked": 0})
	battle._spawn_floats()
	_check(_float_lands_in(battle, "-6", hero_rect), "hero damage number lands on the hero")

	# --- enemy side, across the rebuild that used to break it
	var enemy_rect: Rect2 = battle.enemy_widgets[0].card.get_global_rect()
	var atk := {}
	for i2 in 4:
		for d in 2:
			var c: Dictionary = battle.bc.can_use(i2, d)
			if c.ok and c.face.has("atk"):
				atk = {"h": i2, "d": d}
				break
		if not atk.is_empty():
			break
	_check(not atk.is_empty(), "found an attack die to spend")
	if not atk.is_empty():
		var hp_before: int = battle.bc.s.enemies[0].hp
		battle._do_use(int(atk.h), int(atk.d), {"target": 0})
		var dealt := hp_before - int(battle.bc.s.enemies[0].hp)
		_check(dealt > 0, "the attack dealt damage")
		_check(_float_lands_in(battle, "-%d" % dealt, enemy_rect),
				"enemy damage number lands on the enemy across a refresh")
	battle.queue_free()


## Is there a visible float with this text whose centre sits inside `rect`?
func _float_lands_in(battle: Control, text: String, rect: Rect2) -> bool:
	for c in battle.float_layer.get_children():
		var l := c as Label
		if l == null or not l.visible or l.text != text:
			continue
		if rect.has_point(l.get_global_rect().get_center()):
			return true
		print("  (float '%s' centre %s outside %s)" % [text, l.get_global_rect().get_center(), rect])
	return false
