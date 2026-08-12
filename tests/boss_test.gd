extends Node
## Boss gimmick tests (B1/B2 now; B3-B6 added in Phase 4).
##   godot --headless --path . res://tests/boss_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _mk(boss: String, chapter := 1) -> BattleCore:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var bc := BattleCore.new()
	bc.setup(team, [boss], {"chapter": chapter}, rng)
	return bc


func _silence(bc: BattleCore) -> void:
	for e in bc.s.enemies:
		for r in e.rolls:
			r.cancelled = true


func _ready() -> void:
	GameData.load_all()
	_t_b1_rage()
	_t_b1_rage_stunnable()
	_t_b2_combo_chain()
	_t_b2_counter()
	_t_boss_rolls_two_dice()
	print("BOSS: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("BOSS OK")
	get_tree().quit(0 if fails == 0 else 1)


func _t_boss_rolls_two_dice() -> void:
	var bc := _mk("B1")
	_check(bc.s.enemies[0].rolls.size() == 2, "boss rolls 2 dice")


func _t_b1_rage() -> void:
	var bc := _mk("B1")
	# advance to turn 3
	for t in 2:
		_silence(bc)
		bc.end_turn()
	_check(bc.s.turn == 3, "reached turn 3")
	_check(bc.s.announce.size() == 1 and bc.s.announce[0].kind == "rage_combo", "rage combo announced turn 3")
	_silence(bc)
	var hp_before := 0
	for h in bc.s.heroes:
		hp_before += maxi(int(h.hp), 0)
	bc.end_turn()
	var hp_after := 0
	for h in bc.s.heroes:
		hp_after += maxi(int(h.hp), 0)
	_check(hp_before - hp_after == 12, "rage combo dealt 6x2 (lost %d)" % (hp_before - hp_after))
	_check(bc.s.turn == 4 and bc.s.announce.is_empty(), "no announcement turn 4")


func _t_b1_rage_stunnable() -> void:
	var bc := _mk("B1")
	for t in 2:
		_silence(bc)
		bc.end_turn()
	# stun the announcement (die index -1 encodes announce 0)
	bc.s.heroes[0].faces[0] = "sp_trickery"
	bc.s.heroes[0].rolled = [0, -1]
	bc.s.heroes[0].used = false
	var targets := bc.targetable_dice()
	var found := false
	for t in targets:
		if int(t.die) < 0:
			found = true
			var res := bc.use_face(0, 0, {"die": t})
			_check(res.ok, "stun on announcement ok")
	_check(found, "announcement appears in stun targets")
	_check(bc.s.announce[0].cancelled, "announcement cancelled")
	_silence(bc)
	var hp_before := 0
	for h in bc.s.heroes:
		hp_before += maxi(int(h.hp), 0)
	bc.end_turn()
	var hp_after := 0
	for h in bc.s.heroes:
		hp_after += maxi(int(h.hp), 0)
	_check(hp_before == hp_after, "no rage damage after stun")


func _t_b2_combo_chain() -> void:
	var bc := _mk("B2")
	var e: Dictionary = bc.s.enemies[0]
	e.rolls = [
		{"face": {"atk": 3}, "cancelled": false, "done": false},
		{"face": {"atk": 3}, "cancelled": false, "done": false},
	]
	# all damage funnels to a taunter with no block for determinism
	bc.s.heroes[3].taunt = true
	bc.s.heroes[3].block = 0
	var hp0: int = bc.s.heroes[3].hp
	bc.end_turn()
	# first hit 3, second hit 3+1 = 4 → 7 total
	_check(hp0 - bc.s.heroes[3].hp == 7, "combo chain: 3 then 4 (lost %d)" % (hp0 - bc.s.heroes[3].hp))


func _t_b2_counter() -> void:
	var bc := _mk("B2")
	var e: Dictionary = bc.s.enemies[0]
	_silence(bc)
	e.counter = 4
	bc.s.heroes[0].faces[0] = "hare_quick3"
	bc.s.heroes[0].rolled = [0, -1]
	bc.s.heroes[0].used = false
	var hp0: int = bc.s.heroes[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(hp0 - bc.s.heroes[0].hp == 4, "counter stance retaliated 4 (lost %d)" % (hp0 - bc.s.heroes[0].hp))
