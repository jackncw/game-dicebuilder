extends Node
## Run-structure tests: map guarantees, offers, save roundtrip, and full
## chapter-1 playthroughs via SimRunner.
##   godot --headless --path . res://tests/run_flow_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	GameData.load_all()
	_t_map_guarantees()
	_t_offers()
	_t_treasure_distinct()
	_t_save_roundtrip()
	_t_face_plus_persists()
	_t_retired_relics_migrate()
	_t_battle_seed_replay()
	_t_battle_resume_roundtrip()
	_t_chapter1_runs()
	print("RUNFLOW: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("RUNFLOW OK")
	get_tree().quit(0 if fails == 0 else 1)


## A treasure chest's three face offers are a choice between three things, so
## the same base id must never show up twice on the one screen.
func _t_treasure_distinct() -> void:
	print("treasure offers over 500 seeds …")
	var face_rolls := 0
	for s in 500:
		var run := {"chapter": 1, "relics": []}
		var rng := RandomNumberGenerator.new()
		rng.seed = 31000 + s
		var loot := RunState.gen_treasure(run, rng)
		if String(loot.kind) != "faces":
			continue
		face_rolls += 1
		var faces: Array = loot.faces
		_check(faces.size() == 3, "seed %d offered 3 faces, got %d" % [s, faces.size()])
		var seen := {}
		for fid in faces:
			_check(not seen.has(fid), "seed %d repeated face %s in %s" % [s, fid, faces])
			seen[fid] = true
	# the relic branch takes roughly half the seeds; if it took all of them the
	# assertions above would have been vacuous
	_check(face_rolls > 100, "enough face-branch rolls to be meaningful (%d)" % face_rolls)


func _t_map_guarantees() -> void:
	print("map guarantees over 60 seeds …")
	for chapter in [1, 2, 3]:
		for s in 20:
			var rng := RandomNumberGenerator.new()
			rng.seed = 9000 + chapter * 100 + s
			var map := RunState.gen_map(chapter, rng)
			var rows: Array = map.rows
			_check(rows.size() == 9, "9 rows")
			_check(rows[8].size() == 1 and rows[8][0].type == "boss", "row 9 boss")
			for c in rows[0].size():
				_check(rows[0][c].type == "battle", "row 1 all battle")
			var counts := {"shop": 0, "rest": 0, "treasure": 0, "elite": 0}
			for r in rows.size():
				for c2 in rows[r].size():
					var t := String(rows[r][c2].type)
					if counts.has(t):
						counts[t] += 1
					if t == "elite":
						_check(r >= 2, "elite from row 3 onward")
			_check(counts.shop >= 1, "≥1 shop (ch%d seed%d)" % [chapter, s])
			_check(counts.rest >= 1, "≥1 rest")
			_check(counts.treasure >= 1, "≥1 treasure")
			var need := int(GameData.balance.elites_per_chapter[str(chapter)])
			_check(counts.elite == need, "elite count %d == %d (ch%d)" % [counts.elite, need, chapter])
			# connectivity: walk every path forward
			for r2 in rows.size() - 1:
				var incoming := {}
				for c3 in rows[r2].size():
					_check(rows[r2][c3].edges.size() >= 1, "node has outgoing edge")
					for j in rows[r2][c3].edges:
						incoming[int(j)] = true
				for j2 in rows[r2 + 1].size():
					_check(incoming.has(j2), "row %d node %d has incoming" % [r2 + 1, j2])
			_check(String(map.boss).begins_with("B"), "boss picked")
			_check(int(GameData.bosses[map.boss].chapter) == chapter, "boss matches chapter")
	print("  ok")


func _t_offers() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 777)
	var rng := RunState.rng_of(run)
	for k in 20:
		var offers := RunState.gen_offers(run, rng, "battle", {})
		_check(offers.size() == 3, "3 offers")
		var heroes := {}
		for o in offers:
			heroes[int(o.hero)] = true
			_check(GameData.faces.has(String(o.face)), "offer face exists")
		_check(heroes.size() == 3, "offers bound to distinct heroes")
	# boss offers are R+
	for k2 in 20:
		var offers2 := RunState.gen_offers(run, rng, "boss", {})
		for o2 in offers2:
			var r: String = GameData.faces[o2.face].get("rarity", "C")
			_check(r in ["R", "E"], "boss offer rarity R+ got %s" % r)
	# --- the round-4 curve: an elite is 25/60/15, so over a decent sample its
	# offers have to be markedly rarer than a normal battle's 70/25/5
	var battle_c := 0
	var elite_c := 0
	for k3 in 200:
		for o3 in RunState.gen_offers(run, rng, "battle", {}):
			if String(GameData.faces[o3.face].get("rarity", "C")) == "C":
				battle_c += 1
		for o4 in RunState.gen_offers(run, rng, "elite", {}):
			if String(GameData.faces[o4.face].get("rarity", "C")) == "C":
				elite_c += 1
	_check(battle_c > elite_c * 2, "elite offers are far rarer than battle ones (C: %d vs %d)"
			% [battle_c, elite_c])


func _t_save_roundtrip() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 12321)
	run.gold = 55
	run.relics.append("N02")
	var text := JSON.stringify(run)
	var back = JSON.parse_string(text)
	_check(back is Dictionary, "run parses back")
	_check(int(back.seed) == 12321 and int(back.gold) == 55, "fields preserved")
	_check(back.team.size() == 4 and back.team[0].faces.size() == 12, "team preserved (12 slots)")
	_check(back.team[0].face_plus.size() == 12, "enchant counters serialized")
	_check(back.map.rows.size() == 9, "map preserved")
	_check("N02" in back.relics, "relics preserved")
	# a reloaded (float-laden) run must still simulate fine after normalization
	for k in ["seed", "rng_state", "chapter", "row", "col", "gold"]:
		back[k] = int(back[k])
	var avail := RunState.available_nodes(back)
	_check(avail.size() > 0, "available_nodes works on reloaded run")


## Forge marks ("+") are part of the face instance and must survive a save.
func _t_face_plus_persists() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 777)
	RunState.forge_face(run.team[1], 7)      # a B-die slot
	RunState.forge_face(run.team[1], 7)
	RunState.forge_face(run.team[2], 0)
	Game.run = run
	Game.save_run()
	Game.run = {}
	_check(Game.load_run(), "run reloaded")
	_check(int(Game.run.team[1].face_plus[7]) == 2, "B-die slot kept its ++")
	_check(int(Game.run.team[1].face_mods[7]) == 2, "and its +2 value")
	_check(int(Game.run.team[2].face_plus[0]) == 1, "second hero kept its +")
	_check(int(Game.run.team[0].face_plus[3]) == 0, "untouched slots stay clean")
	Game.clear_run()


## Round 4 replaced all 18 relics. A save written before that carries ids that
## no longer resolve, and a run that silently loses four relics mid-chapter is
## worse than one that quietly swaps them — so each retired id is substituted
## with an unheld relic of the same tier, and the count is preserved.
func _t_retired_relics_migrate() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 5150)
	# what a sim-v1-era save looked like: four relics, none of which exist now
	run.relics = ["R01", "R05", "R11", "R18"]
	Game.run = run
	Game.save_run()
	Game.run = {}
	_check(Game.load_run(), "old-format run reloaded")
	var kept: Array = Game.run.relics
	_check(kept.size() == 4, "the party still holds 4 relics, got %d" % kept.size())
	for rid in kept:
		_check(GameData.relics.has(rid), "substitute %s is a real relic" % rid)
		_check(GameData.relic_rarity(String(rid)) == "common",
				"substitutes come from the Common tier, got %s" % rid)
	var seen := {}
	for rid2 in kept:
		_check(not seen.has(rid2), "no duplicate substitutes (%s twice)" % rid2)
		seen[rid2] = true
	# and it is stable: the same save reloaded twice yields the same relics
	Game.run = {}
	Game.load_run()
	_check(Game.run.relics == kept, "migration is deterministic for a given save")
	# a save that is already current is left completely alone
	Game.run.relics = ["N03", "A02"]
	Game.save_run()
	Game.run = {}
	Game.load_run()
	_check(Game.run.relics == ["N03", "A02"], "current relic ids are untouched")
	Game.clear_run()


## Same battle seed + same actions ⇒ identical enemies and identical rolls.
## This is what stops a player from quitting to reroll a bad turn.
func _t_battle_seed_replay() -> void:
	var team_a := []
	var team_b := []
	for id in ["HARE", "BADGER", "OWL", "HEDGE"]:
		team_a.append(GameData.new_hero(id))
		team_b.append(GameData.new_hero(id))
	var trace_a := _play_scripted(team_a, 90210)
	var trace_b := _play_scripted(team_b, 90210)
	_check(trace_a == trace_b, "same seed replays identically")
	var trace_c := _play_scripted(team_b.duplicate(true), 90211)
	_check(trace_a != trace_c, "a different seed produces a different battle")


## Plays a fixed script (first legal action per hero, then end turn) and
## returns a digest of everything random that happened.
func _play_scripted(team: Array, battle_seed: int, turns := 4) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed
	var bc := BattleCore.new()
	bc.setup(team, ["E01", "E07"], {"chapter": 2}, rng)
	var trace := []
	for e in bc.s.enemies:
		trace.append("%s/%d" % [e.key, e.hp])
	for t in turns:
		if bc.s.over:
			break
		for i in bc.s.heroes.size():
			trace.append(str(bc.s.heroes[i].rolled))
			for d in BattleCore.DICE:
				if not bc.can_use(i, d).ok:
					continue
				var lt: Dictionary = bc.legal_targets(i, d)
				var res := {"ok": false}
				match String(lt.type):
					"enemy":
						if not lt.indices.is_empty():
							res = bc.use_face(i, d, {"target": lt.indices[0]})
					"ally":
						res = bc.use_face(i, d, {"target": i})
					"enemy_die":
						if not lt.indices.is_empty():
							res = bc.use_face(i, d, {"die": lt.indices[0]})
					"none":
						res = bc.use_face(i, d)
				if res.get("ok", false):
					break
		for e in bc.s.enemies:
			for r in e.rolls:
				trace.append(String(r.face.get("id", "?")))
		if not bc.s.over:
			bc.end_turn()
		for h in bc.s.heroes:
			trace.append(str(h.hp))
	return "|".join(trace)


## The encounter is committed to run.json before the first roll, so a
## continue mid-battle rebuilds exactly the same fight.
func _t_battle_resume_roundtrip() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 5150)
	Game.run = run
	Game.enter_node(0, 0)     # row 0 is always a battle node
	_check(Game._pending_battle(), "battle committed to the run")
	var seed_before := int(Game.run.battle.seed)
	var line_up: Array = Game.run.battle.enemies.duplicate()
	Game.save_run()
	# quit and come back
	Game.run = {}
	_check(Game.load_run(), "run reloaded mid-battle")
	_check(Game._pending_battle(), "pending battle survived the reload")
	_check(int(Game.run.battle.seed) == seed_before, "battle seed preserved")
	_check(Game.run.battle.enemies == line_up, "enemy line-up preserved")
	var a := _play_scripted(Game.run.team, seed_before)
	var b := _play_scripted(Game.run.team, int(Game.run.battle.seed))
	_check(a == b, "resumed battle replays identically")
	Game.clear_run()


func _t_chapter1_runs() -> void:
	print("chapter-1 playthroughs ×10 …")
	var wins := 0
	for s in 10:
		var res := SimRunner.simulate_run(["HARE", "BADGER", "OWL", "HEDGE"], 5000 + s, {}, 1)
		_check(res.battles > 0, "fought battles (seed %d)" % s)
		if res.win:
			wins += 1
	print("  ch1 completion: %d/10" % wins)
	_check(wins >= 5, "greedy AI clears chapter 1 at least half the time (got %d/10)" % wins)
