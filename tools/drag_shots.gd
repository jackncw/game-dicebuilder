extends Node
## Visual re-check for the die drag fix, in a REAL window at a size that is not
## the design resolution — so the canvas_items stretch is actually active and
## any coordinate-space slip shows up on screen.
##
## Everything here goes through the same path as live play: window-pixel input
## pushed with push_input(ev, false), letting Godot apply the stretch transform
## itself. Shots land in art_export/drag_*.png.
##
## Must run WITH a window (it awaits frame_post_draw):
##   Godot --path . --log-file art_export/drag_shots.log tools/drag_shots.tscn

const OUTDIR := "res://art_export/"
const WINDOW := Vector2i(540, 960)   # 0.75x of the 720x1280 canvas

var battle: Control
var _scale := Vector2.ONE


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	for i in 8:
		await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	_scale = Vector2(WINDOW) / vp
	print("window=%s canvas=%s stretch=%s" % [WINDOW, vp, _scale])

	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	battle = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E01"],
			"opts": {"chapter": 1}, "battle_seed": 20260805})
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(battle)
	for i in 12:
		await get_tree().process_frame

	await _shot_drag_to_enemy()
	await _shot_drag_to_cast()
	get_tree().quit(0)


## Pick a die up, hold it halfway to the target, then drop it on the enemy.
func _shot_drag_to_enemy() -> void:
	_force(1, 0, "bdg_heavy4")
	for i in 4:
		await get_tree().process_frame
	var from: Vector2 = battle.die_widgets["1:0"].get_global_rect().get_center()
	var to: Vector2 = battle.enemy_widgets[0].card.get_global_rect().get_center()
	await _grab("drag_00_before")
	_press(from)
	for k in range(1, 5):
		_move(from.lerp(to, float(k) / 4.0))
		await get_tree().process_frame
	print("held: drag=%s ghost_at=%s (pointer canvas %s)"
			% [battle.drag, battle.drag_ghost.global_position, to])
	await _grab("drag_01_held")
	_release(to)
	for i in 6:
		await get_tree().process_frame
	print("after enemy drop: enemy0 hp=%d hero1.used=%s"
			% [battle.bc.s.enemies[0].hp, battle.bc.s.heroes[1].used])
	await _grab("drag_02_dropped_enemy")


## A no-target face: the centre cast pad must appear under the held die.
func _shot_drag_to_cast() -> void:
	_force(2, 0, "owl_gather2")
	for i in 4:
		await get_tree().process_frame
	var from: Vector2 = battle.die_widgets["2:0"].get_global_rect().get_center()
	var to: Vector2 = battle.cast_zone.get_global_rect().get_center()
	_press(from)
	for k in range(1, 5):
		_move(from.lerp(to, float(k) / 4.0))
		await get_tree().process_frame
	await _grab("drag_03_held_cast")
	_release(to)
	for i in 6:
		await get_tree().process_frame
	print("after cast drop: mana=%d hero2.used=%s"
			% [battle.bc.s.mana, battle.bc.s.heroes[2].used])
	await _grab("drag_04_dropped_cast")


func _force(hero: int, die: int, face_id: String) -> void:
	var h: Dictionary = battle.bc.s.heroes[hero]
	var slot: int = die * BattleCore.FACES
	h.faces[slot] = face_id
	h.face_mods[slot] = 0
	h.face_plus[slot] = 0
	h.face_extras[slot] = {}
	h.rolled[die] = slot
	h.used = false
	h.used_die = -1
	h.locked = [false, false]
	battle._refresh()


# --- input, in window pixels, exactly as the OS delivers it -----------------

func _win(canvas: Vector2) -> Vector2:
	return canvas * _scale


func _press(canvas: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = _win(canvas)
	e.global_position = _win(canvas)
	get_viewport().push_input(e, false)


func _move(canvas: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(canvas)
	e.global_position = _win(canvas)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, false)


func _release(canvas: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = _win(canvas)
	e.global_position = _win(canvas)
	get_viewport().push_input(e, false)


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUTDIR)
	img.save_png(OUTDIR + name + ".png")
	print("saved %s.png" % name)
