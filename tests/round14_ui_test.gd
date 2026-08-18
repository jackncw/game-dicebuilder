extends Node
## Round 14: the event check die, the potion confirm, and hold-to-read.
##
## Three contracts, all of them things that used to be true only by inspection:
##
##   ① HONESTY — the number the check die lands on is the number the engine
##      rolled. Every one of the six values is driven through, and the pip the
##      cube is showing is read back off the widget, not off the caller's copy.
##      The gamble event is then run end to end against an independent replay
##      of the run RNG, so "the die shows what the run rolled" is proved rather
##      than assumed. Nothing is applied before the player confirms.
##   ② A POTION IS ASKED ABOUT, NOT DRUNK — a tap raises a card and spends
##      nothing; only the card's Use button spends it. Holding reads it.
##   ③ ONE GESTURE — the relic icons answer a hold with that relic's card, a
##      tap with the pack, and a drag past the deadzone with neither, because
##      they run the same `PressGesture` as a die face.
##
##   godot --headless --path . res://tests/round14_ui_test.tscn

var fails := 0
var tests := 0
var holder: Control


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = pos
	_push(e)


func _drag_ev(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	_push(e)


func _tap(pos: Vector2) -> void:
	_touch(pos, true)
	await get_tree().process_frame
	_touch(pos, false)
	await get_tree().process_frame
	await get_tree().process_frame


## Press, hold past PressGesture.LONG_PRESS, release.
func _hold(pos: Vector2) -> void:
	_touch(pos, true)
	await get_tree().create_timer(PressGesture.LONG_PRESS + 0.15).timeout
	_touch(pos, false)
	await get_tree().process_frame


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _fresh_host() -> Control:
	var host := Control.new()
	host.position = Vector2.ZERO
	host.size = Vector2(720, 1280)
	host.custom_minimum_size = Vector2(720, 1280)
	holder.add_child(host)
	return host


func _ready() -> void:
	GameData.load_all()
	Game.settings.lang_mode = "both"
	holder = Control.new()
	holder.size = Vector2(720, 1280)
	holder.custom_minimum_size = Vector2(720, 1280)
	add_child(holder)
	await get_tree().process_frame

	await _t_dice_honesty()
	await _t_dice_tap()
	await _t_gamble_event()
	await _t_potion_confirm()
	await _t_relic_gestures()

	# a suite that silently stops asserting is a broken build reported green
	_check(tests > 40, "the suite actually ran its checks (%d)" % tests)
	print("round14_ui_test: %d tests, %d failures" % [tests, fails])
	print("ROUND14UI %s" % ("OK" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails > 0 else 0)


# ============================================================ ① the check die

func _t_dice_honesty() -> void:
	print("dice check: every value lands on the number the engine rolled")
	for roll in range(1, 7):
		var host := _fresh_host()
		var got := [-1]
		var dc := DiceCheck.open(host, {"roll": roll, "need": 4,
				"on_done": func(ok: bool) -> void: got[0] = 1 if ok else 0})
		await _frames(3)
		_check(dc.confirm_button == null,
				"roll %d: nothing is decided before the player throws" % roll)
		dc.throw_it()
		await _frames(3)
		_check(dc._shown_pip() == roll,
				"roll %d: the cube is showing %d — the engine's number, not a redraw"
				% [roll, dc._shown_pip()])
		_check(dc.succeeded() == (roll >= 4),
				"roll %d: verdict follows `roll >= need`" % roll)
		_check(dc.confirm_button != null, "roll %d: the result waits for a confirm" % roll)
		_check(got[0] == -1, "roll %d: the outcome is not applied before the confirm" % roll)
		dc._confirm()
		await _frames(2)
		_check(got[0] == (1 if roll >= 4 else 0),
				"roll %d: the callback gets the same verdict the card showed" % roll)
		host.queue_free()
		await get_tree().process_frame


func _t_dice_tap() -> void:
	print("dice check: the die itself is the thing you tap")
	var host := _fresh_host()
	var dc := DiceCheck.open(host, {"roll": 5, "need": 4})
	await _frames(4)
	var r: Rect2 = dc.die.get_global_rect()
	_check(r.size.x > 40.0, "the die has a real rect to aim at (%s)" % r)
	await _tap(r.get_center())
	await _frames(3)
	_check(dc.confirm_button != null, "a tap on the die threw it")
	_check(dc._shown_pip() == 5, "and it landed on 5")
	host.queue_free()
	await get_tree().process_frame


# ============================================================ ② the event

func _t_gamble_event() -> void:
	print("gamble event: the die shows what the run RNG rolled")
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 2468)
	Game.run.gold = 100
	Safe.boot_arg = "V03"
	var host := _fresh_host()
	var ev: Control = load("res://scripts/ui/screen_event.gd").new()
	ev.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(ev)
	await _frames(4)
	Safe.boot_arg = ""
	_check(ev.event_id == "V03", "the boot argument landed us on the gamble event")

	# what the run is ABOUT to roll, replayed off the saved state without
	# touching it — this is the number the die has to show
	var probe := RunState.rng_of(Game.run)
	var expect := probe.randi_range(1, 6)

	var opt := _first_button(ev)
	_check(opt != null, "the event offered a button to press")
	if opt == null:
		return
	opt.pressed.emit()
	await _frames(3)
	_check(int(Game.run.gold) == 70,
			"the stake left the purse up front (%d)" % int(Game.run.gold))
	var dc := _find_check(ev)
	_check(dc != null,
			"pressing the wager raised the check die instead of announcing a number")
	if dc == null:
		return
	_check(dc.roll == expect,
			"the die was given the run's own roll (%d, replay says %d)" % [dc.roll, expect])
	dc.throw_it()
	await _frames(3)
	_check(dc._shown_pip() == expect, "and it landed on it")
	_check(int(Game.run.gold) == 70, "the winnings do not land before the confirm")
	dc._confirm()
	await _frames(3)
	var want := 70 + (60 if expect >= 4 else 0)
	_check(int(Game.run.gold) == want,
			"the payout matches the face that was shown (%d, want %d)"
			% [int(Game.run.gold), want])
	host.queue_free()
	await get_tree().process_frame


# ============================================================ ③ potions

func _t_potion_confirm() -> void:
	print("potions: a tap asks, it does not drink")
	var host := _fresh_host()
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E02"],
			"opts": {"chapter": 1, "potions": ["P02", "P01"], "relics": ["N02", "A01"]},
			"battle_seed": 91117})
	battle.instant_anim = true
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(battle)
	await _frames(4)

	_check(battle.potion_row.get_child_count() == 2, "both potions are in the tray")
	var pb: Button = battle.potion_row.get_child(0)
	var before: int = battle.bc.s.potions.size()
	pb.pressed.emit()
	await _frames(2)
	_check(battle.bc.s.potions.size() == before,
			"a tap spent nothing — the potion is still in the bag")
	var card := _find_card(battle)
	_check(card != null, "a tap raised the use/cancel card")
	var use := _find_button_with(card, Data.bi("使用", "Use"))
	_check(use != null, "the card carries the Use button")
	if use != null:
		use.pressed.emit()
		await _frames(3)
		_check(battle.bc.s.potions.size() == before - 1,
				"confirming drank it (%d -> %d)" % [before, battle.bc.s.potions.size()])

	# holding reads it instead, and spends nothing
	await _frames(2)
	var pb2: Button = battle.potion_row.get_child(0)
	var n2: int = battle.bc.s.potions.size()
	await _hold(pb2.get_global_rect().get_center())
	await _frames(2)
	_check(battle.bc.s.potions.size() == n2, "holding a potion spends nothing")
	_check(_find_card(battle) != null, "holding a potion raised its card")
	host.queue_free()
	await get_tree().process_frame


# ============================================================ ④ relic icons

func _t_relic_gestures() -> void:
	print("relic icons: tap the pack, hold the rule, drag neither")
	var host := _fresh_host()
	var ic := ItemIcon.for_relic("N02", 64.0)
	ic.position = Vector2(200, 400)
	var taps := [0]
	var holds := [0]
	ic.pressed.connect(func() -> void: taps[0] += 1)
	ic.long_pressed.connect(func() -> void: holds[0] += 1)
	host.add_child(ic)
	await _frames(3)
	var c := ic.get_global_rect().get_center()

	await _tap(c)
	_check(taps[0] == 1 and holds[0] == 0,
			"a short tap is a tap (%d/%d)" % [taps[0], holds[0]])

	await _hold(c)
	_check(holds[0] == 1, "a hold is a hold")
	_check(taps[0] == 1, "and the release after a hold is not also a tap")

	# a finger that travels is a scroll: the icons live in scrolling rows
	_touch(c, true)
	await get_tree().process_frame
	for k in range(1, 5):
		var p := c + Vector2(0, -12.0 * k)
		_drag_ev(p, Vector2(0, -12))
		await get_tree().process_frame
	_touch(c + Vector2(0, -48), false)
	await _frames(2)
	_check(taps[0] == 1 and holds[0] == 1,
			"a drag past the deadzone is neither (%d/%d)" % [taps[0], holds[0]])
	host.queue_free()
	await get_tree().process_frame


# ============================================================ helpers

func _first_button(n: Node) -> Button:
	if n is Button and (n as Button).is_visible_in_tree() \
			and (n as Button).get_global_rect().size.x > 100.0:
		return n
	for c in n.get_children():
		var hit := _first_button(c)
		if hit != null:
			return hit
	return null


func _find_check(n: Node) -> DiceCheck:
	if n is DiceCheck:
		return n
	for c in n.get_children():
		var hit := _find_check(c)
		if hit != null:
			return hit
	return null


## The detail card is a full-rect child a screen picked up, script-free and
## the size of the whole canvas.
func _find_card(screen: Control) -> Control:
	for i in range(screen.get_child_count() - 1, -1, -1):
		var c := screen.get_child(i)
		if c is Control and c.get_script() == null and (c as Control).size.y > 900.0:
			return c
	return null


func _find_button_with(n: Node, text: String) -> Button:
	if n == null:
		return null
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var hit := _find_button_with(c, text)
		if hit != null:
			return hit
	return null
