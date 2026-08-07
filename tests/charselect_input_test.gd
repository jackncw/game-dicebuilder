extends Node
## Reproduction test: drive the character-select screen with REAL input events
## (mouse press/release via Input.parse_input_event, so touch emulation applies,
## same path as live play).  Verifies card taps toggle selection and embark
## enables after 4 picks.
##   godot --headless --path . res://tests/charselect_input_test.tscn

var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)
	else:
		print("  ok: " + msg)


func _click(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var cs: Control = load("res://scripts/ui/screen_charselect.gd").new()
	cs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cs)
	for i in 4:
		await get_tree().process_frame

	print("viewport size: %s" % get_viewport().get_visible_rect().size)
	var cards: Array = cs.grid.get_children()
	print("cards in grid: %d" % cards.size())
	for i in cards.size():
		var card: Control = cards[i]
		print("  card %d rect global=%s size=%s" % [i, card.get_global_rect().position, card.get_global_rect().size])

	# click the first 4 unlocked cards, one at a time (grid rebuilds each tap)
	for pick in 4:
		var target := -1
		# grid order IS roster order — reading it from the data is what keeps
		# this test pointing at the card it thinks it is clicking
		var ids := GameData.hero_ids()
		for i in 6:
			if ids[i] in Game.meta.unlocked_heroes and not (ids[i] in cs.selected):
				target = i
				break
		if target < 0:
			break
		var card2: Control = cs.grid.get_children()[target]
		var center := card2.get_global_rect().get_center()
		var before: int = cs.selected.size()
		await _click(center)
		print("clicked card %d at %s -> selected=%s" % [target, center, str(cs.selected)])
		_check(cs.selected.size() == before + 1, "click %d selected a hero" % pick)

	_check(cs.selected.size() == 4, "4 heroes selected via clicks")
	_check(not cs.embark.disabled, "embark button enabled")

	# --- battle screen: real click on a die card must select it -----------
	cs.queue_free()
	await get_tree().process_frame
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E01"],
			"opts": {"chapter": 1}, "battle_seed": 555})
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(battle)
	for i in 6:
		await get_tree().process_frame
	# a real click on a die must select it (or resolve it, for no-target faces)
	var rect_a: Rect2 = battle.die_widgets["0:0"].get_global_rect()
	var rect_b: Rect2 = battle.die_widgets["0:1"].get_global_rect()
	_check(rect_a.get_center() != rect_b.get_center(),
			"the two dice occupy different screen positions")
	# measure in canvas units: the headless window scales global rects
	var die_size: Vector2 = battle.die_widgets["0:0"].size
	_check(die_size.x >= 72 and die_size.y >= 72,
			"die touch target is at least 72px (%s)" % [die_size])
	# the click rebuilds the hero row, so re-read the widget afterwards
	await _click(rect_a.get_center())
	_check(not battle.sel.is_empty() or battle.bc.s.heroes[0].used,
			"clicking a die selects it (sel=%s)" % [battle.sel])

	if fails == 0:
		print("CHARSELECT INPUT OK")
	else:
		print("CHARSELECT INPUT FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
