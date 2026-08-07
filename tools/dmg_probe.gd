extends Node
## Where the party's damage actually comes from.
##
## The balance report says how often a run dies; it does not say which hero is
## carrying and which is a passenger. This plays a fixed set of encounters with
## the greedy policy and prints damage dealt per hero per turn, so a tuning pass
## can aim at the character that is short rather than at everything at once.
##   godot --headless --path . tools/dmg_probe.tscn -- [runs]

func _ready() -> void:
	GameData.load_all()
	var runs := 40
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			runs = int(a)
	var team_ids: Array = GameData.starter_hero_ids()
	print("team: %s" % [team_ids])
	for enc in [["E01", "E01"], ["E04", "E05"], ["B1"], ["B2"]]:
		_probe(team_ids, enc, runs)
	print("--- unlockables swapped in ---")
	_probe(["FOX", "BOAR", "OWL", "HEDGE"], ["B1"], runs)
	get_tree().quit(0)


func _probe(team_ids: Array, enemies: Array, runs: int) -> void:
	var per_hero := {}
	for id in team_ids:
		per_hero[id] = 0
	var turns := 0
	var wins := 0
	var chapter: int = 2 if String(enemies[0]).begins_with("B") else 1
	for k in runs:
		var team := []
		for id in team_ids:
			team.append(GameData.new_hero(id))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + k * 131
		var bc := BattleCore.new()
		bc.setup(team, enemies, {"chapter": chapter}, rng)
		var dealt := {}
		for i in team_ids.size():
			dealt[i] = 0
		var guard := 0
		while not bc.s.over and guard < 40:
			guard += 1
			SimRunner._manage_locks(bc)
			SimRunner._spend_rerolls(bc)
			var best := SimRunner._best_action(bc)
			if best.is_empty():
				bc.end_turn()
				continue
			var before := _enemy_hp(bc)
			bc.use_face(int(best.hero), int(best.die), best.params)
			dealt[int(best.hero)] = int(dealt[int(best.hero)]) + maxi(before - _enemy_hp(bc), 0)
		turns += int(bc.s.turn)
		if bc.s.victory:
			wins += 1
		for i2 in team_ids.size():
			per_hero[team_ids[i2]] = int(per_hero[team_ids[i2]]) + int(dealt[i2])
	var line := ""
	var total := 0
	for id2 in team_ids:
		total += int(per_hero[id2])
	for id3 in team_ids:
		line += "%s %.1f  " % [id3, float(per_hero[id3]) / float(runs)]
	print("%-14s win %2d/%d  turns %.1f  dmg/turn %.1f   %s"
			% [",".join(PackedStringArray(enemies)), wins, runs, float(turns) / runs,
			float(total) / maxf(float(turns), 1.0), line])


func _enemy_hp(bc: BattleCore) -> int:
	var t := 0
	for e in bc.s.enemies:
		t += maxi(int(e.hp), 0)
	return t
