extends Node
## Integration test for picking a die up and dropping it on a target.
##
## Drives REAL InputEvent sequences through the viewport — press, several
## motion steps, release — for the three input shapes the game actually sees:
##   mouse      pure mouse events (emulate_touch_from_mouse OFF)
##   mouse_emu  mouse events plus the synthesized touch pair Godot adds when
##              emulate_touch_from_mouse is ON (the project's default)
##   touch      a real touchscreen: ScreenTouch / ScreenDrag only
## and for the six drop cases: enemy, enemy intent chip, self, ally, cast pad
## and an illegal spot.
##
##   godot --headless --path . res://tests/drag_input_test.tscn

const MOUSE := "mouse"
const MOUSE_EMU := "mouse_emu"
const TOUCH := "touch"
const MODES := [MOUSE, MOUSE_EMU, TOUCH]

## Live, a stretched canvas means an event's `position` arrives in canvas space
## while its `global_position` stays in window pixels. Model a 1080x1920 window
## showing the 720x1280 canvas, so anything that reads global_position as if it
## were canvas space lands 1.5x away from where the finger is.
const WINDOW_SCALE := 1.5

var fails := 0
var _battle: Control = null


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)
	else:
		print("  ok: " + msg)


# ============================================================ input plumbing

func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos * WINDOW_SCALE
	_push(e)


func _mouse_motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos * WINDOW_SCALE
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(e)


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = pos
	_push(e)


func _touch_drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	_push(e)


func _send_press(mode: String, pos: Vector2) -> void:
	if mode == TOUCH:
		_touch(pos, true)
		return
	_mouse_button(pos, true)
	if mode == MOUSE_EMU:
		_touch(pos, true)


func _send_move(mode: String, pos: Vector2) -> void:
	if mode == TOUCH:
		_touch_drag(pos)
		return
	_mouse_motion(pos)
	if mode == MOUSE_EMU:
		_touch_drag(pos)


func _send_release(mode: String, pos: Vector2) -> void:
	if mode == TOUCH:
		_touch(pos, false)
		return
	_mouse_button(pos, false)
	if mode == MOUSE_EMU:
		_touch(pos, false)


## Press on `from` and walk to `to` without letting go.
func _drag_begin(mode: String, from: Vector2, to: Vector2) -> void:
	_send_press(mode, from)
	await get_tree().process_frame
	for k in range(1, 5):
		_send_move(mode, from.lerp(to, float(k) / 4.0))
		await get_tree().process_frame


func _drag_end(mode: String, to: Vector2) -> void:
	_send_release(mode, to)
	await get_tree().process_frame
	await get_tree().process_frame


func _drag(mode: String, from: Vector2, to: Vector2) -> void:
	await _drag_begin(mode, from, to)
	await _drag_end(mode, to)


# ============================================================ battle fixture

func _new_battle() -> Control:
	if is_instance_valid(_battle):
		_battle.queue_free()
		await get_tree().process_frame
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var b: Control = load("res://scripts/ui/screen_battle.gd").new()
	b.setup({"team": team, "enemies": ["E01", "E01"], "opts": {"chapter": 1},
			"battle_seed": 777})
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(b)
	for i in 6:
		await get_tree().process_frame
	_battle = b
	return b


## Put a known face on hero `hero`'s die `die` so a case does not depend on the
## roll. Slot 0 is the A die's first face, slot 6 the B die's first.
func _force(b: Control, hero: int, die: int, face_id: String) -> void:
	var h: Dictionary = b.bc.s.heroes[hero]
	var slot: int = die * BattleCore.FACES
	h.faces[slot] = face_id
	h.face_mods[slot] = 0
	h.face_plus[slot] = 0
	h.face_extras[slot] = {}
	h.rolled[die] = slot
	h.used = false
	h.used_die = -1
	h.locked = [false, false]
	b._refresh()
	# the rebuilt widgets have no rect until the containers sort them
	await get_tree().process_frame
	await get_tree().process_frame


func _die_center(b: Control, hero: int, die: int) -> Vector2:
	return b.die_widgets["%d:%d" % [hero, die]].get_global_rect().get_center()


func _enemy_center(b: Control, j: int) -> Vector2:
	return b.enemy_widgets[j].card.get_global_rect().get_center()


func _chip_center(b: Control, j: int, d: int) -> Vector2:
	return b.enemy_widgets[j].chips[d].get_global_rect().get_center()


func _hero_center(b: Control, i: int) -> Vector2:
	return b.hero_cards[i].get_global_rect().get_center()


# ============================================================ the six cases

func _case_enemy(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 1, 0, "bdg_heavy4")            # 攻6,目標=敵人
	var hp0: int = b.bc.s.enemies[0].hp
	await _drag_begin(mode, _die_center(b, 1, 0), _enemy_center(b, 0))
	_check(b.drag.get("hero", -1) == 1 and b.drag.get("die", -1) == 0,
			"[%s] enemy: die is held mid-drag (drag=%s)" % [mode, b.drag])
	_check(b._drop_spec().enemies.size() == 2,
			"[%s] enemy: both live enemies highlight while held" % mode)
	await _drag_end(mode, _enemy_center(b, 0))
	_check(b.bc.s.enemies[0].hp < hp0,
			"[%s] enemy: drop damaged enemy 0 (%d -> %d)" % [mode, hp0, b.bc.s.enemies[0].hp])
	_check(b.bc.s.heroes[1].used, "[%s] enemy: hero 1 spent its action" % mode)
	_check(b.drag.is_empty(), "[%s] enemy: drag state cleared" % mode)


func _case_enemy_die(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 3, 0, "sp_trickery")            # 暈1,目標=敵人骰
	_check(not b.bc.s.enemies[0].rolls[0].cancelled, "[%s] chip: intent starts live" % mode)
	await _drag_begin(mode, _die_center(b, 3, 0), _chip_center(b, 0, 0))
	_check(b._drop_spec().enemy_dice, "[%s] chip: enemy dice are droppable while held" % mode)
	await _drag_end(mode, _chip_center(b, 0, 0))
	_check(b.bc.s.enemies[0].rolls[0].cancelled,
			"[%s] chip: dropping on the intent chip stunned that die" % mode)
	_check(b.drag.is_empty(), "[%s] chip: drag state cleared" % mode)


func _case_self(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 0, 0, "hareb_roll")              # 防3,目標=自己
	await _drag_begin(mode, _die_center(b, 0, 0), _hero_center(b, 0))
	_check(b._drop_spec().heroes == [0], "[%s] self: only the owner highlights" % mode)
	await _drag_end(mode, _hero_center(b, 0))
	_check(b.bc.s.heroes[0].block == 3,
			"[%s] self: drop granted 3 block (got %d)" % [mode, b.bc.s.heroes[0].block])
	_check(b.drag.is_empty(), "[%s] self: drag state cleared" % mode)


func _case_ally(mode: String) -> void:
	var b := await _new_battle()
	b.bc.s.heroes[0].hp = b.bc.s.heroes[0].max_hp - 6
	await _force(b, 2, 0, "owlb_moonheal")            # 療4,目標=隊友
	var hp0: int = b.bc.s.heroes[0].hp
	await _drag_begin(mode, _die_center(b, 2, 0), _hero_center(b, 0))
	_check(b._drop_spec().heroes.size() == 4, "[%s] ally: the whole party highlights" % mode)
	await _drag_end(mode, _hero_center(b, 0))
	_check(b.bc.s.heroes[0].hp == hp0 + 4,
			"[%s] ally: drop healed hero 0 (%d -> %d)" % [mode, hp0, b.bc.s.heroes[0].hp])
	_check(b.drag.is_empty(), "[%s] ally: drag state cleared" % mode)


func _case_cast(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 2, 0, "owl_gather2")          # 靈息+2,目標=無
	var mana0: int = b.bc.s.mana
	var pad: Vector2 = b.cast_zone.get_global_rect().get_center()
	await _drag_begin(mode, _die_center(b, 2, 0), pad)
	_check(b.cast_zone.visible, "[%s] cast: the cast pad appears while held" % mode)
	await _drag_end(mode, b.cast_zone.get_global_rect().get_center())
	_check(b.bc.s.mana == mana0 + 2,
			"[%s] cast: drop on the pad gave +2 mana (got %d)" % [mode, b.bc.s.mana])
	_check(b.drag.is_empty(), "[%s] cast: drag state cleared" % mode)


func _case_illegal(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 1, 0, "bdg_heavy4")
	var hp0: int = b.bc.s.enemies[0].hp
	var hp1: int = b.bc.s.enemies[1].hp
	await _drag(mode, _die_center(b, 1, 0), Vector2(14, 470))
	_check(b.bc.s.enemies[0].hp == hp0 and b.bc.s.enemies[1].hp == hp1,
			"[%s] illegal: nothing was damaged" % mode)
	_check(not b.bc.s.heroes[1].used, "[%s] illegal: the die returns unspent" % mode)
	_check(b.drag.is_empty(), "[%s] illegal: drag state cleared" % mode)
	_check(b.sel.is_empty(), "[%s] illegal: nothing left selected" % mode)
	_check(not is_instance_valid(b.drag_ghost), "[%s] illegal: the ghost is gone" % mode)


## Dropped on the enemy's body rather than a specific intent chip, an
## enemy_die face falls back to that enemy's biggest live die. The chip is a
## drop zone sitting inside the card, so the chip must win where they overlap
## (covered by _case_enemy_die) and the card must still catch everything else.
func _case_enemy_die_body(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 3, 0, "sp_trickery")
	var live0: bool = not b.bc.s.enemies[0].rolls[0].cancelled
	await _drag(mode, _die_center(b, 3, 0), _enemy_center(b, 0))
	_check(live0 and b.bc.s.enemies[0].rolls[0].cancelled,
			"[%s] body: dropping on the card body stunned the enemy's die" % mode)
	_check(not b.bc.s.enemies[1].rolls[0].cancelled,
			"[%s] body: the other enemy was left alone" % mode)


## Holding still long enough to raise the tooltip must not kill the drag: the
## pick-up dismisses the tooltip and the gesture carries on to its target.
func _case_longpress_then_drag(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 1, 0, "bdg_heavy4")
	var hp0: int = b.bc.s.enemies[0].hp
	var from := _die_center(b, 1, 0)
	_send_press(mode, from)
	await get_tree().create_timer(0.7).timeout
	_check(b._tooltip != null, "[%s] longpress: the tooltip opened while holding" % mode)
	var to := _enemy_center(b, 0)
	for k in range(1, 5):
		_send_move(mode, from.lerp(to, float(k) / 4.0))
		await get_tree().process_frame
	_check(not is_instance_valid(b._tooltip),
			"[%s] longpress: picking the die up dismissed the tooltip" % mode)
	await _drag_end(mode, to)
	_check(b.bc.s.enemies[0].hp < hp0,
			"[%s] longpress: the drag still resolved (%d -> %d)"
			% [mode, hp0, b.bc.s.enemies[0].hp])
	_check(b.drag.is_empty(), "[%s] longpress: drag state cleared" % mode)


## A die the hero cannot use must not lift off the table at all.
func _case_locked(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 1, 0, "bdg_heavy4")
	await _drag(mode, _die_center(b, 1, 0), _enemy_center(b, 0))
	_check(b.bc.s.heroes[1].used, "[%s] locked: setup spent hero 1's A die" % mode)
	var hp0: int = b.bc.s.enemies[0].hp
	await _drag_begin(mode, _die_center(b, 1, 1), _enemy_center(b, 0))
	_check(b.drag.is_empty(), "[%s] locked: the locked-out B die never lifts" % mode)
	_check(not is_instance_valid(b.drag_ghost), "[%s] locked: no ghost was spawned" % mode)
	await _drag_end(mode, _enemy_center(b, 0))
	_check(b.bc.s.enemies[0].hp == hp0, "[%s] locked: no damage from the dead drag" % mode)


# =================================================== the mis-fire regression
#
# A self-targeting die sits inside its own hero card, so before the arm
# distance existed any wobble at all was a complete pick-up-and-drop onto a
# legal target and the face was spent. These three cases pin that shut: only a
# gesture that genuinely leaves the die's home may spend it.

## Press and let go without moving: selects, never uses.
func _case_tap_selects_only(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 0, 0, "hareb_roll")              # 防3,目標=自己
	var at := _die_center(b, 0, 0)
	_send_press(mode, at)
	await get_tree().process_frame
	_send_release(mode, at)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not b.bc.s.heroes[0].used, "[%s] tap: a tap on a self die spent nothing" % mode)
	_check(b.bc.s.heroes[0].block == 0,
			"[%s] tap: no block was granted (got %d)" % [mode, b.bc.s.heroes[0].block])
	_check(b.sel.get("hero", -1) == 0 and b.sel.get("die", -1) == 0,
			"[%s] tap: the die is selected instead (sel=%s)" % [mode, b.sel])
	# and tapping it again lets go of it
	_send_press(mode, at)
	await get_tree().process_frame
	_send_release(mode, at)
	await get_tree().process_frame
	_check(b.sel.is_empty(), "[%s] tap: a second tap deselects" % mode)
	_check(not b.bc.s.heroes[0].used, "[%s] tap: the second tap spent nothing either" % mode)


## A 30px wobble is under the arm distance: it cancels, even though the finger
## is still sitting on a perfectly legal target (the hero's own card).
func _case_short_drag_cancels(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 0, 0, "hareb_roll")
	var from := _die_center(b, 0, 0)
	var to := from + Vector2(0, -30)
	_send_press(mode, from)
	await get_tree().process_frame
	for k in range(1, 4):
		_send_move(mode, from.lerp(to, float(k) / 3.0))
		await get_tree().process_frame
	_check(not b.drag.is_empty(), "[%s] short: the die did lift off" % mode)
	_check(not b._armed(), "[%s] short: 30px is not armed" % mode)
	_check(b.hero_cards[0].get_global_rect().has_point(to),
			"[%s] short: the finger really is over a legal target" % mode)
	await _drag_end(mode, to)
	_check(not b.bc.s.heroes[0].used, "[%s] short: releasing short spent nothing" % mode)
	_check(b.bc.s.heroes[0].block == 0, "[%s] short: no block was granted" % mode)
	_check(b.drag.is_empty(), "[%s] short: drag state cleared" % mode)
	_check(not is_instance_valid(b.drag_ghost), "[%s] short: the ghost is gone" % mode)


## Past the arm distance and back onto the hero: this one is meant to resolve.
func _case_armed_self(mode: String) -> void:
	var b := await _new_battle()
	await _force(b, 0, 0, "hareb_roll")
	var from := _die_center(b, 0, 0)
	var to := _hero_center(b, 0)
	_check(from.distance_to(to) >= b.DRAG_ARM,
			"[%s] armed: the hero card centre is past the arm distance (%.0fpx)"
			% [mode, from.distance_to(to)])
	await _drag_begin(mode, from, to)
	_check(b._armed(), "[%s] armed: the drag armed on the way over" % mode)
	await _drag_end(mode, to)
	_check(b.bc.s.heroes[0].block == 3,
			"[%s] armed: a full drag onto yourself still works (block %d)"
			% [mode, b.bc.s.heroes[0].block])


# ============================================================ runner

func _ready() -> void:
	await get_tree().process_frame
	print("viewport size: %s" % get_viewport().get_visible_rect().size)
	for mode in MODES:
		print("--- input mode: %s" % mode)
		await _case_enemy(mode)
		await _case_enemy_die(mode)
		await _case_enemy_die_body(mode)
		await _case_self(mode)
		await _case_ally(mode)
		await _case_cast(mode)
		await _case_illegal(mode)
		await _case_locked(mode)
		await _case_longpress_then_drag(mode)
		await _case_tap_selects_only(mode)
		await _case_short_drag_cancels(mode)
		await _case_armed_self(mode)
	if fails == 0:
		print("DRAG INPUT OK")
	else:
		print("DRAG INPUT FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
