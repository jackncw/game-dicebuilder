extends Node
## Phase 4 coverage: B3/B5/B6 gimmicks, every face usable, relic effects,
## elite affixes, full 3-chapter simulations.
##   godot --headless --path . res://tests/phase4_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _mk(enemies: Array, opts := {}, team_ids := ["HARE", "BADGER", "OWL", "HEDGE"]) -> BattleCore:
	var team := []
	for id in team_ids:
		team.append(GameData.new_hero(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 777888))
	var bc := BattleCore.new()
	bc.setup(team, enemies, opts, rng)
	return bc


func _silence(bc: BattleCore) -> void:
	for e in bc.s.enemies:
		for r in e.rolls:
			r.cancelled = true


func _face(bc: BattleCore, i: int, face_id: String) -> void:
	bc.s.heroes[i].faces[0] = face_id
	bc.s.heroes[i].rolled = [0, -1]
	bc.s.heroes[i].used = false


func _ready() -> void:
	GameData.load_all()
	_t_b3_two_phase()
	_t_b5_armor()
	_t_b6_summoner()
	_t_all_faces_usable()
	_t_relics()
	_t_elite_affixes()
	_t_full_runs()
	print("PHASE4: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("PHASE4 OK")
	get_tree().quit(0 if fails == 0 else 1)


func _t_b3_two_phase() -> void:
	var bc := _mk(["B3"], {"chapter": 2})
	var e: Dictionary = bc.s.enemies[0]
	# Boss pools go through the per-chapter world multiplier now (round 6), so
	# the expectation is derived rather than typed — the day that dial moves,
	# this follows it instead of failing.
	var p1_hp := int(round(int(GameData.bosses.B3.hp)
			* float(GameData.balance.enemy_hp_mult[str(int(GameData.bosses.B3.chapter))])))
	var p2_hp := int(round(int(GameData.bosses.B3.phase2_hp)
			* float(GameData.balance.enemy_hp_mult[str(int(GameData.bosses.B3.chapter))])))
	_check(e.hp == p1_hp and e.dice == 2, "B3 phase 1: %d HP, 2 dice" % p1_hp)
	e.poison = 5
	e.hp = 1
	_face(bc, 0, "hare_quick3")
	bc.use_face(0, 0, {"target": 0})
	_check(not e.dead, "B3 not dead after phase-1 kill")
	_check(e.phase == 2 and e.hp == p2_hp, "B3 phase 2: fresh %d HP" % p2_hp)
	_check(e.dice == 3, "B3 phase 2 rolls 3 dice")
	_check(e.poison == 0, "statuses cleared on phase change")
	var has_dance := false
	for f in e.faces:
		if String(f.id) == "b3_dance":
			has_dance = true
	_check(has_dance, "phase 2 faces loaded")
	# now killing it for real ends the battle
	e.hp = 1
	bc.s.heroes[1].faces[0] = "bdg_heavy4"
	bc.s.heroes[1].rolled = [0, -1]
	bc.s.heroes[1].used = false
	bc.use_face(1, 0, {"target": 0})
	_check(e.dead and bc.s.over and bc.s.victory, "B3 dies in phase 2")


func _t_b5_armor() -> void:
	var bc := _mk(["B5"], {"chapter": 3})
	var e: Dictionary = bc.s.enemies[0]
	var armor_block := int(GameData.bosses.B5.passive.value)
	var unarmored_block := int(GameData.bosses.B5.unarmored_block)
	var atk_bonus := int(GameData.bosses.B5.unarmored_atk_bonus)
	_check(e.block == armor_block, "B5 starts with block %d" % armor_block)
	# drop to half → unarmored
	e.hp = int(e.max_hp / 2.0)
	_face(bc, 0, "hare_quick3")
	bc.use_face(0, 0, {"target": 0})
	_check(e.phase == 2, "B5 sheds armor at ≤50%")
	_silence(bc)
	bc.end_turn()
	_check(bc.s.enemies[0].block == unarmored_block, "unarmored start block %d, got %d" % [unarmored_block, bc.s.enemies[0].block])
	var e2: Dictionary = bc.s.enemies[0]
	e2.rolls = [{"face": {"atk": 9}, "cancelled": false, "done": false}]
	bc.s.heroes[3].taunt = true
	bc.s.heroes[3].block = 0
	var hp0: int = bc.s.heroes[3].hp
	bc.end_turn()
	_check(hp0 - bc.s.heroes[3].hp == 9 + atk_bonus, "unarmored attacks +%d, lost %d" % [atk_bonus, hp0 - bc.s.heroes[3].hp])


func _t_b6_summoner() -> void:
	var bc := _mk(["B6"], {"chapter": 3})
	_check(bc.s.enemies.size() == 3, "B6 summons 2 minions at start")
	for j in [1, 2]:
		_check(bc.s.enemies[j].key in ["E01", "E03"], "summon from pool")
		_check(bc.s.enemies[j].tier == 3, "summons are T3")
	_check(bc.s.announce.is_empty(), "no doom on turn 1")
	_silence(bc)
	bc.end_turn()
	_check(bc.s.turn == 2, "turn 2")
	var doom_found := false
	for a in bc.s.announce:
		if a.kind == "doom":
			doom_found = true
	_check(doom_found, "doom announced turn 2")
	# let it fire
	_silence(bc)
	var doom := int(GameData.bosses.B6.doom_damage)
	var hp0 := 0
	for h in bc.s.heroes:
		hp0 += maxi(int(h.hp), 0)
	for h in bc.s.heroes:
		h.block = 0
	bc.end_turn()
	var hp1 := 0
	for h in bc.s.heroes:
		hp1 += maxi(int(h.hp), 0)
	_check(hp0 - hp1 >= doom * 4 - 2, "doom hit whole party ~%d each (lost %d)" % [doom, hp0 - hp1])
	# mana drain face
	var boss: Dictionary = bc.s.enemies[0]
	bc.s.mana = 5
	boss.hp = int(boss.max_hp) - 10
	bc._execute_enemy_face(0, {"mana_drain": 3, "heal": 5})
	_check(bc.s.mana == 2, "mana drained 5→2")
	_check(bc.s.enemies[0].hp == int(boss.max_hp) - 5, "boss healed 5")
	# summon refill when fewer than 2 minions alive
	for j in [1, 2]:
		bc.s.enemies[j].dead = true
	var n_before: int = bc.s.enemies.size()
	bc._execute_enemy_face(0, {"summon": 1})
	_check(bc.s.enemies.size() == n_before + 1, "summon face adds a minion")


func _t_all_faces_usable() -> void:
	print("all faces usable …")
	var count := 0
	for fid in GameData.face_ids():
		if fid == "blank":
			continue
		var fd: Dictionary = GameData.faces[fid]
		var bc := _mk(["E01", "E01"], {"seed": 424242 + count})
		count += 1
		_silence(bc)
		bc.s.mana = 10
		_face(bc, 0, fid)
		# give hero 1 a copyable arrow for wild faces
		bc.s.heroes[1].faces[0] = "hare_quick3"
		bc.s.heroes[1].rolled = [0, -1]
		# 呼應-gated faces (絕影) refuse to be spent unless the user's OTHER die
		# is pinned on the right kind of face, so give every sweep subject one.
		if fd.has("resonate_req") or fd.has("resonate"):
			bc.s.heroes[0].faces[6] = "hare_quick3"
			bc.s.heroes[0].rolled[1] = 6
			bc.s.heroes[0].locked[1] = true
		var params := {}
		match String(fd.get("target", "none")):
			"enemy":
				params = {"target": 0}
			"ally":
				params = {"target": 0}
			"enemy_die":
				var dice := bc._targetable_dice()
				# re-enable one die
				bc.s.enemies[0].rolls[0].cancelled = false
				dice = bc._targetable_dice()
				if dice.is_empty():
					_check(false, "no targetable die for %s" % fid)
					continue
				params = {"die": dice[0], "die2": dice[0], "theft_target": 1}
			"wild":
				params = {"copy_from": {"hero": 1, "die": 0}, "target": 0}
			_:
				params = {}
		var res := bc.use_face(0, 0, params)
		_check(res.get("ok", false), "face %s usable (err=%s)" % [fid, res.get("err", "")])
	print("  %d faces exercised" % count)


func _t_relics() -> void:
	# --- the Common tier: N05 essence +2, N11 first-turn rerolls +2
	var bc := _mk(["E01"], {"relics": ["N05", "N11"]})
	_check(bc.s.rerolls == 2, "N11 rerolls 2 (no base), got %d" % bc.s.rerolls)
	_check(bc.s.mana == 3 + 2 + BattleCore.MANA_REGEN,
			"N05 essence %d (Owl 3 + relic 2 + U1), got %d"
					% [3 + 2 + BattleCore.MANA_REGEN, bc.s.mana])
	_silence(bc)
	bc.end_turn()
	_check(bc.s.rerolls == 0, "turn 2: N11 has expired, got %d" % bc.s.rerolls)
	# N02 atk+1, N03 block+1
	var bc2 := _mk(["B1"], {"relics": ["N02", "N03"], "chapter": 1})
	_silence(bc2)
	_face(bc2, 1, "sp_great_blade")   # atk10 pain2
	var e: Dictionary = bc2.s.enemies[0]
	e.block = 0
	var ehp: int = e.hp
	var khp: int = bc2.s.heroes[1].hp
	bc2.use_face(1, 0, {"target": 0})
	_check(ehp - e.hp == 12, "N02: great blade 10 + whetstone 1 + sergeant 1 = 12, dealt %d" % (ehp - e.hp))
	_check(khp - bc2.s.heroes[1].hp == 2, "pain is untouched without the Chalice")
	_face(bc2, 0, "sp_quick_jab")   # combo: 4 +2 (an attack landed) +1 (N02) = 7
	var ehp2: int = e.hp
	bc2.use_face(0, 0, {"target": 0})
	_check(ehp2 - e.hp == 7, "combo w/ N02 dealt 7, dealt %d" % (ehp2 - e.hp))
	_face(bc2, 3, "hedge_guard4")
	bc2.use_face(3, 0)
	_check(bc2.s.heroes[3].block == 5, "N03 block 4+1=5, got %d" % bc2.s.heroes[3].block)
	# N09 poison +1, N10 burn +1
	var bc3 := _mk(["E01"], {"relics": ["N09", "N10"]})
	_silence(bc3)
	_face(bc3, 0, "sp_venom_knife")
	bc3.use_face(0, 0, {"target": 0})
	_check(bc3.s.enemies[0].poison == 3, "N09 poison 2+1=3")
	_face(bc3, 1, "sp_torch")
	bc3.s.heroes[1].used = false
	bc3.use_face(1, 0, {"target": 0})
	_check(int(bc3.s.enemies[0].burn_new[0]) == 3, "N10 burn 2+1=3")
	# --- N01 導靈杖: the FIRST Ritual of each TURN is a point cheaper, and only
	# --- the first. Asserted through `spell_cost` because that is what `can_use`
	# --- and the UI both read — a discount the player is shown but not charged
	# --- (or charged but not shown) would be the real bug here.
	var bc4 := _mk(["E01"], {"relics": ["N01"]})
	_silence(bc4)
	var ritual: Dictionary = GameData.faces.owl_starshower
	_check(bc4.spell_cost(ritual) == int(ritual.spell) - 1,
			"N01: first Ritual costs %d, got %d" % [int(ritual.spell) - 1,
					bc4.spell_cost(ritual)])
	bc4.s.mana = 10
	_face(bc4, 0, "owl_starshower")
	bc4.use_face(0, 0)
	_check(bc4.s.mana == 10 - (int(ritual.spell) - 1),
			"N01: the discounted price is what was actually taken, pool %d" % bc4.s.mana)
	_check(bc4.spell_cost(ritual) == int(ritual.spell),
			"N01: the second Ritual of the same turn is full price, got %d"
					% bc4.spell_cost(ritual))
	# and never below 1, however many discounts pile on
	var cheap := {"spell": 1}
	_check(bc4.spell_cost(cheap) == 1, "N01 never takes a Ritual under 1")
	# the whole point of the round-7 change: the allowance re-arms every turn,
	# so the discount is a thing you plan around rather than a one-off rebate
	bc4.end_turn()
	_check(bc4.spell_cost(ritual) == int(ritual.spell) - 1,
			"N01: next turn's first Ritual is discounted again, got %d"
					% bc4.spell_cost(ritual))
	bc4.s.mana = 10
	_face(bc4, 0, "owl_starshower")
	bc4.use_face(0, 0)
	_check(bc4.s.mana == 10 - (int(ritual.spell) - 1),
			"N01: and the second turn's discount is the price actually charged, pool %d"
					% bc4.s.mana)
	_check(bc4.spell_cost(ritual) == int(ritual.spell),
			"N01: still only the first of the turn, got %d" % bc4.spell_cost(ritual))

	# --- N12 靈息迴環: end a turn holding 3+ and next turn opens with an extra
	var bc5 := _mk(["E01"], {"relics": ["N12"]})
	_silence(bc5)
	bc5.s.mana = BattleCore.ESSENCE_LOOP_FLOOR
	var before := int(bc5.s.mana)
	bc5.end_turn()
	_check(bc5.s.mana == before + BattleCore.MANA_REGEN + 1,
			"N12: regen %d + loop 1 on top of %d, got %d"
					% [BattleCore.MANA_REGEN, before, bc5.s.mana])
	# …and pays nothing on a pool that was spent down
	var bc6 := _mk(["E01"], {"relics": ["N12"]})
	_silence(bc6)
	bc6.s.mana = BattleCore.ESSENCE_LOOP_FLOOR - 1
	var before2 := int(bc6.s.mana)
	bc6.end_turn()
	_check(bc6.s.mana == before2 + BattleCore.MANA_REGEN,
			"N12: under the floor pays nothing, got %d" % bc6.s.mana)
	_t_advanced_relics()


## The six Advanced relics, one assertion each — these are the ones that change
## how a turn is played, so a silent regression in any of them is a different
## game rather than a slightly different number.
func _t_advanced_relics() -> void:
	# --- A01 雙月徽記: one hero, both dice, once a turn
	var bc := _mk(["E01"], {"relics": ["A01"]})
	_silence(bc)
	bc.s.heroes[0].rolled = [0, 6]
	bc.s.heroes[0].used = false
	bc.s.heroes[0].used_dice = []
	bc.s.heroes[1].rolled = [0, 6]
	_check(bc.use_face(0, 0, {"target": 0}).ok, "A01: first die spends")
	_check(bc.can_use(0, 1).ok, "A01: the same hero's second die is still open")
	_check(bc.use_face(0, 1, {"target": 0}).ok, "A01: second die spends")
	_check(int(bc.s.twin_hero) == 0, "A01: the seal is claimed by that hero")
	_check(bc.use_face(1, 0, {"target": 0}).ok, "A01: another hero still acts once")
	_check(not bc.can_use(1, 1).ok, "A01: but only one hero gets two dice a turn")

	# --- A03 血之聖杯: lifesteal doubles, pain drops
	var bc2 := _mk(["E01"], {"relics": ["A03"]})
	_silence(bc2)
	bc2.s.enemies[0].block = 0
	bc2.s.enemies[0].hp = 40
	_face(bc2, 0, "sp_leech_bite")     # atk 5, lifesteal
	bc2.s.heroes[0].hp = 5
	bc2.use_face(0, 0, {"target": 0})
	_check(bc2.s.heroes[0].hp == 10, "A03: lifesteal healed the full 5, got %d"
			% int(bc2.s.heroes[0].hp))
	_face(bc2, 1, "sp_great_blade")          # pain 2 → 1
	var khp: int = bc2.s.heroes[1].hp
	bc2.use_face(1, 0, {"target": 0})
	_check(khp - int(bc2.s.heroes[1].hp) == 1, "A03: pain 2-1 = 1")

	# --- A04 賭徒之骨: rerolls never run out, and cost the party a point each
	var bc3 := _mk(["E01"], {"relics": ["A04"]})
	_silence(bc3)
	_check(bc3.s.rerolls == 0 and bc3.can_reroll(), "A04: reroll with 0 in the bank")
	var before := []
	for h in bc3.s.heroes:
		before.append(int(h.hp))
	_check(bc3.reroll(), "A04: the reroll went through")
	for i in bc3.s.heroes.size():
		_check(int(bc3.s.heroes[i].hp) == int(before[i]) - 1,
				"A04: hero %d paid 1 HP" % i)
	_check(bc3.s.rerolls == 0, "A04: the bank is not drawn down")

	# --- A05 森之心: rituals cost less, essence trickles in
	var bc4 := _mk(["E01"], {"relics": ["A05"]})
	_check(bc4.s.mana == 3 + 1 + BattleCore.MANA_REGEN,
			"A05: %d essence on turn 1 (Owl 3 + relic 1 + U1), got %d"
					% [3 + 1 + BattleCore.MANA_REGEN, int(bc4.s.mana)])
	var fireball: Dictionary = GameData.faces.owl_starfall    # spell 3
	_check(bc4.spell_cost(fireball) == 2, "A05: ritual 3 costs 2")
	var frost: Dictionary = GameData.faces.owl_wardshield     # spell 1
	_check(bc4.spell_cost(frost) == 1, "A05: a 1-cost ritual never goes free")
	_silence(bc4)
	var m := int(bc4.s.mana)
	bc4.end_turn()
	_check(int(bc4.s.mana) == mini(m + 1 + BattleCore.MANA_REGEN, BattleCore.MANA_CAP),
			"A05: +1 (relic) +%d (U1) again next turn, got %d"
					% [BattleCore.MANA_REGEN, int(bc4.s.mana)])

	# --- A06 獸王戰鼓: the SECOND attack of the turn is the one that gains
	var bc5 := _mk(["E01", "E01"], {"relics": ["A06"]})
	_silence(bc5)
	for en in bc5.s.enemies:
		en.block = 0
		en.hp = 60
	_face(bc5, 0, "sp_keen")           # atk 5, no combo
	var hp0: int = bc5.s.enemies[0].hp
	bc5.use_face(0, 0, {"target": 0})
	_check(hp0 - int(bc5.s.enemies[0].hp) == 5, "A06: the first attack is unbuffed")
	_face(bc5, 1, "bdg_smash6")        # atk 6 → 7
	var hp1: int = bc5.s.enemies[0].hp
	bc5.use_face(1, 0, {"target": 0})
	_check(hp1 - int(bc5.s.enemies[0].hp) == 8, "A06: the next attack is +1 (6 + sergeant 1 + drum 1), dealt %d"
			% (hp1 - int(bc5.s.enemies[0].hp)))
	_face(bc5, 2, "sp_armor_break")    # atk 4 pierce → 6 (two attacks banked)
	var hp2: int = bc5.s.enemies[0].hp
	bc5.use_face(2, 0, {"target": 0})
	_check(hp2 - int(bc5.s.enemies[0].hp) == 6, "A06: it stacks within the turn, dealt %d"
			% (hp2 - int(bc5.s.enemies[0].hp)))
	bc5.end_turn()
	_check(int(bc5.s.drum) == 0, "A06: the drum resets between turns")


func _t_elite_affixes() -> void:
	var bc := _mk(["E02"], {"elite": true, "affix": "frenzied", "chapter": 1})
	var found_atk := false
	# read the base value from the data so balance passes don't break the test
	var base_nip := 0
	for fd in GameData.enemies.E02.faces:
		if String(fd.id) == "e02_nip":
			base_nip = int(fd.atk[0])
	var bonus := int(GameData.encounters.elite_affixes.frenzied.atk_bonus)
	for f in bc.s.enemies[0].faces:
		if f.has("atk") and String(f.id) == "e02_nip":
			_check(int(f.atk) == base_nip + bonus,
					"frenzied nip %d+%d, got %d" % [base_nip, bonus, int(f.atk)])
			found_atk = true
			break
	_check(found_atk, "frenzied faces found")
	var base_hp := int(round(int(GameData.enemies.E02.hp[0])
			* float(GameData.balance.enemy_hp_mult["1"])))
	var want := int(floor(base_hp * float(GameData.balance.elite_hp_mult)))
	_check(bc.s.enemies[0].max_hp == want, "elite hp x1.5 = %d, got %d" % [want, bc.s.enemies[0].max_hp])
	var bc2 := _mk(["E02"], {"elite": true, "affix": "stoneskin", "chapter": 1})
	_check(bc2.s.enemies[0].block >= 3, "stoneskin start block 3")
	var bc3 := _mk(["E02"], {"elite": true, "affix": "venomous", "chapter": 1})
	var e3: Dictionary = bc3.s.enemies[0]
	e3.rolls = [{"face": e3.faces[0].duplicate(), "cancelled": false, "done": false}]
	bc3.s.heroes[0].taunt = true
	bc3.s.heroes[0].block = 99
	var hp_before: int = bc3.s.heroes[0].hp
	bc3.end_turn()
	# poison 1 applied on hit, then ticks at the same end-of-turn settlement
	_check(hp_before - bc3.s.heroes[0].hp == 1 and bc3.s.heroes[0].poison == 0,
			"venomous poison applied then ticked 1 (lost %d)" % (hp_before - bc3.s.heroes[0].hp))


func _t_full_runs() -> void:
	print("full 3-chapter simulations ×8 …")
	var wins := 0
	var ch_reached := []
	for s in 8:
		var res := SimRunner.simulate_run(["HARE", "BADGER", "OWL", "HEDGE"], 6000 + s, {}, 3)
		if res.win:
			wins += 1
			ch_reached.append(4)
		else:
			ch_reached.append(res.get("died_chapter", res.chapter_reached))
		_check(res.battles > 0, "run %d fought battles" % s)
	print("  full-run wins: %d/8  (progress: %s)" % [wins, str(ch_reached)])
	_check(true, "sims completed without crash")
