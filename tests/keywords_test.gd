extends Node
## Per-keyword unit tests for BattleCore.
##   godot --headless --path . res://tests/keywords_test.tscn
## Tests manipulate bc.s directly (set rolled faces / craft enemy rolls) so
## every assertion is deterministic.

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _mk(team_ids: Array, enemy_keys: Array, opts := {}) -> BattleCore:
	var team := []
	for id in team_ids:
		team.append(GameData.new_hero(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var bc := BattleCore.new()
	bc.setup(team, enemy_keys, opts, rng)
	return bc


## Force hero i's A die to show face_id (injected into slot 0) and take the
## B die off the table, so each test drives exactly one face.
func _face(bc: BattleCore, i: int, face_id: String) -> void:
	bc.s.heroes[i].faces[0] = face_id
	bc.s.heroes[i].rolled = [0, -1]
	bc.s.heroes[i].used = false
	bc.s.heroes[i].used_die = -1
	bc.s.heroes[i].used_dice = []


## Same for the B die (slot 6), leaving the A die showing `a_face_id`.
func _face_b(bc: BattleCore, i: int, face_id: String, a_face_id := "") -> void:
	var h: Dictionary = bc.s.heroes[i]
	h.faces[6] = face_id
	h.rolled = [-1, 6]
	if a_face_id != "":
		h.faces[0] = a_face_id
		h.rolled[0] = 0
	h.used = false
	h.used_die = -1
	h.used_dice = []


## Both dice on the table at once: A shows `a_id`, B shows `b_id`. The 呼應 and
## 雙舞 tests need a real pair rather than one die and a hole.
func _face_pair(bc: BattleCore, i: int, a_id: String, b_id: String) -> void:
	var h: Dictionary = bc.s.heroes[i]
	h.faces[0] = a_id
	h.faces[6] = b_id
	h.rolled = [0, 6]
	h.used = false
	h.used_die = -1
	h.used_dice = []


## Replace enemy j's rolled dice with crafted faces.
func _enemy_rolls(bc: BattleCore, j: int, faces: Array) -> void:
	var rolls := []
	for f in faces:
		rolls.append({"face": f, "cancelled": false, "done": false})
	bc.s.enemies[j].rolls = rolls


func _silence_enemies(bc: BattleCore) -> void:
	for e in bc.s.enemies:
		for r in e.rolls:
			r.cancelled = true


func _ready() -> void:
	GameData.load_all()
	# Several assertions read bilingual output. The autoload picks the language
	# up from user://settings.json, i.e. from whatever the last person to open
	# the game happened to choose — pin it so the suite tests the code rather
	# than the developer's save file.
	Game.settings.lang_mode = "both"
	_t_block()
	_t_pierce()
	_t_cleave()
	_t_sweep()
	_t_poison()
	_t_burn_delayed()
	_t_stun()
	_t_weaken_enemy()
	_t_expose()
	_t_heal_revive_overflow()
	_t_regen()
	_t_taunt()
	_t_thorns_hero()
	_t_thorns_enemy()
	_t_lifesteal()
	_t_combo()
	_t_wild()
	_t_mana_spell()
	_t_growth()
	_t_pain()
	_t_lucky()
	_t_curse()
	_t_bind()
	_t_steal_b4()
	_t_zanshin()
	_t_settlement_order()
	_t_insight()
	_t_gambit()
	_t_time_stop()
	_t_die_theft()
	_t_reverb()
	_t_potions()
	_t_e04_passive()
	_t_e10_two_dice()
	_t_dual_dice()
	_t_reroll_sources()
	_t_reroll_skips_acted_heroes()
	_t_face_plus()
	# ---- 2026-08 character overhaul: the lock rule and the four new keywords
	_t_lock_persists()
	_t_charge_up()
	_t_charge_cap_and_reset()
	_t_charge_lost_on_unlock()
	_t_resonate()
	_t_resonate_timing()
	_t_resonate_requirement()
	_t_recoil_ignores_block()
	_t_all_pierce()
	_t_multi_hit()
	_t_multi_hit_thorns()
	# ---- the faces built on top of them
	_t_lock_boost()
	_t_twin_dance()
	_t_all_in()
	_t_shield_bash()
	_t_bristle()
	_t_essence_ward()
	_t_thorn_hold()
	_t_war_cry()
	_t_rampage()
	_t_heal_on_hit()
	_t_last_ditch()
	# ---- the six passives
	_t_passive_old_sergeant()
	_t_passive_held_breath()
	_t_passive_quilled_hide()
	_t_passive_ancient_warden()
	# round 6, task 3 — the Essence overhaul
	_t_u1_regen()
	_t_u2_essence_reroll()
	_t_essence_faces()
	_t_attuned_aim_charge()
	_t_passive_call_and_answer()
	_t_passive_cornered_fury()
	print("KEYWORDS: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("KEYWORDS OK")
	get_tree().quit(0 if fails == 0 else 1)


func _t_block() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_face(bc, 0, "hedge_guard4")
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].block == 4, "block 4 gained, got %d" % bc.s.heroes[0].block)
	_enemy_rolls(bc, 0, [{"atk": 4}])
	# force the target via taunt to be deterministic
	bc.s.heroes[0].taunt = true
	var hp0: int = bc.s.heroes[0].hp
	bc.end_turn()
	_check(bc.s.heroes[0].hp == hp0, "block absorbed all damage")


func _t_pierce() -> void:
	# On the Badger, not the Hare — 屏息 adds +2 to anything that pierces, and
	# this test is about the keyword, not about him.
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 5
	_face(bc, 0, "sp_armor_break")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 5, "pierce ignored block, 4 + sergeant 1 (hp %d→%d)" % [hp0, bc.s.enemies[0].hp])
	_check(bc.s.enemies[0].block == 5, "block untouched by pierce")


func _t_cleave() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E01", "E01", "E01"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_whirl_blade")
	var hps := []
	for e in bc.s.enemies:
		hps.append(e.hp)
	bc.use_face(0, 0, {"target": 1})
	for j in 3:
		_check(bc.s.enemies[j].hp == hps[j] - 6, "cleave hit enemy %d for 5 + sergeant 1" % j)


func _t_sweep() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E02", "E02", "E02"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_scatter")
	var hps := []
	for e in bc.s.enemies:
		hps.append(e.hp)
	bc.use_face(0, 0)
	for j in 3:
		_check(bc.s.enemies[j].hp == hps[j] - 2, "sweep hit enemy %d" % j)


func _t_poison() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E01"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_venom_knife")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].poison == 2, "poison 2 applied")
	_check(bc.s.enemies[0].hp == hp0 - 3, "venom knife dealt 3")
	var hp1: int = bc.s.enemies[0].hp
	bc.end_turn()
	_check(bc.s.enemies[0].hp == hp1 - 2, "poison tick 2")
	_check(bc.s.enemies[0].poison == 1, "poison decayed to 1")
	_silence_enemies(bc)
	var hp2: int = bc.s.enemies[0].hp
	bc.end_turn()
	_check(bc.s.enemies[0].hp == hp2 - 1, "poison tick 1")
	_check(bc.s.enemies[0].poison == 0, "poison gone")


func _t_burn_delayed() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_torch")
	bc.use_face(0, 0, {"target": 0})
	var hp_after_hit: int = bc.s.enemies[0].hp
	bc.end_turn()   # burn was fresh → no tick this turn
	_check(bc.s.enemies[0].hp == hp_after_hit, "burn did NOT tick same turn")
	_silence_enemies(bc)
	var hp1: int = bc.s.enemies[0].hp
	bc.end_turn()   # now it ticks
	_check(bc.s.enemies[0].hp == hp1 - 2, "burn ticked 2 next turn")
	_check(bc.s.enemies[0].burn.is_empty() and bc.s.enemies[0].burn_new.is_empty(), "burn removed")


func _t_stun() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_enemy_rolls(bc, 0, [{"atk": 6}])
	_face(bc, 0, "sp_trickery")
	bc.use_face(0, 0, {"die": {"enemy": 0, "die": 0}})
	_check(bc.s.enemies[0].rolls[0].cancelled, "enemy die cancelled")
	var hps := []
	for h in bc.s.heroes:
		hps.append(h.hp)
	bc.end_turn()
	for i in 4:
		_check(bc.s.heroes[i].hp == hps[i], "no damage after stun (hero %d)" % i)


func _t_weaken_enemy() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_enemy_rolls(bc, 0, [{"atk": 4}])
	_face(bc, 0, "sp_sap")
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].weaken == 2, "weaken 2 applied")
	bc.s.heroes[0].taunt = true
	var hp0: int = bc.s.heroes[0].hp
	bc.s.heroes[0].block = 0
	bc.end_turn()
	_check(bc.s.heroes[0].hp == hp0 - 2, "weakened attack dealt 2 (4-2), lost %d" % (hp0 - bc.s.heroes[0].hp))


func _t_expose() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "sp_mark")
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].expose, "expose applied")
	_face(bc, 1, "sp_heavy_blow")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(1, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 12, "exposed 8→12 (ceil 1.5x), dealt %d" % (hp0 - bc.s.enemies[0].hp))


func _t_heal_revive_overflow() -> void:
	var bc := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	# normal heal
	bc.s.heroes[1].hp = 10
	_face(bc, 0, "sp_first_aid")
	bc.use_face(0, 0, {"target": 1})
	_check(bc.s.heroes[1].hp == 14, "heal 4")
	# revive
	bc.s.heroes[2].hp = 0
	bc.s.heroes[2].down = true
	_face(bc, 0, "sp_first_aid")
	bc.use_face(0, 0, {"target": 2})
	_check(not bc.s.heroes[2].down and bc.s.heroes[2].hp == 4, "revived at heal amount")
	# overflow: missing 1, heal 4 → +1 hp, overflow 3 → block 1
	bc.s.heroes[3].hp = bc.s.heroes[3].max_hp - 1
	bc.s.heroes[3].block = 0
	_face(bc, 0, "sp_first_aid")
	bc.use_face(0, 0, {"target": 3})
	_check(bc.s.heroes[3].hp == bc.s.heroes[3].max_hp, "healed to full")
	_check(bc.s.heroes[3].block == 1, "overflow 3 → block 1 (50%% floor), got %d" % bc.s.heroes[3].block)


func _t_regen() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	bc.s.heroes[0].hp = 10
	_face(bc, 0, "sp_regenerate")
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.heroes[0].regen == 3, "regen 3 applied")
	bc.end_turn()
	_check(bc.s.heroes[0].hp == 13, "regen healed 3")
	_check(bc.s.heroes[0].regen == 2, "regen decayed to 2")


func _t_taunt() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_enemy_rolls(bc, 0, [{"atk": 6}])
	_face(bc, 0, "sp_protect")
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].taunt, "taunt active")
	var hps := []
	for h in bc.s.heroes:
		hps.append(h.hp)
	bc.end_turn()
	_check(bc.s.heroes[0].hp == hps[0] - 1, "taunter took 6-5block=1, lost %d"
			% (hps[0] - bc.s.heroes[0].hp))
	for i in [1, 2, 3]:
		_check(bc.s.heroes[i].hp == hps[i], "non-taunter untouched (%d)" % i)


func _t_thorns_hero() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_enemy_rolls(bc, 0, [{"atk": 2}])
	_face(bc, 0, "sp_thorn_shield")   # block 3, thorns 3
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].thorns == 3, "thorns 3, got %d" % bc.s.heroes[0].thorns)
	bc.s.heroes[0].taunt = true
	var ehp: int = bc.s.enemies[0].hp
	bc.end_turn()
	_check(bc.s.enemies[0].hp == ehp - 3, "thorns reflected 3 ignoring block")


func _t_thorns_enemy() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E06"], {"chapter": 1})
	_silence_enemies(bc)
	_face(bc, 0, "sp_heavy_blow")
	var hp0: int = bc.s.heroes[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.heroes[0].hp == hp0 - 2, "E06 thorns 2 reflected to attacker")


func _t_lifesteal() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	bc.s.heroes[0].hp = 10           # 10/28 ≤ 50% → 背水之勢 +2
	_face(bc, 0, "sp_leech_bite")    # atk 5 lifesteal
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.heroes[0].hp == 10 + 3, "lifesteal healed floor(7*0.5)=3, hp=%d" % bc.s.heroes[0].hp)


func _t_combo() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "hare_quick3")
	bc.use_face(0, 0, {"target": 0})
	_face(bc, 1, "sp_quick_jab")     # atk 4, combo
	var fd := bc.hero_face(1, 0)
	_check(bc.attack_value(1, fd) == 7, "combo 4 + sergeant 1 + 2 = 7, got %d" % bc.attack_value(1, fd))


func _t_wild() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "sp_chaos")
	_face(bc, 1, "sp_heavy_blow")
	var hp0: int = bc.s.enemies[0].hp
	var res := bc.use_face(0, 0, {"copy_from": {"hero": 1, "die": 0}, "target": 0})
	_check(res.ok, "wild copy ok")
	_check(bc.s.enemies[0].hp == hp0 - 8, "wild copied heavy blow 7, +1 from the copier's passive")
	# a wild may also copy the caster's own other die
	var bc2 := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 0
	_face_b(bc2, 0, "sp_heavy_blow", "sp_chaos")
	var hp1: int = bc2.s.enemies[0].hp
	var res2 := bc2.use_face(0, 0, {"copy_from": {"hero": 0, "die": 1}, "target": 0})
	_check(res2.ok, "wild copies the caster's own B die")
	_check(bc2.s.enemies[0].hp == hp1 - 8, "own-die copy dealt 7 + sergeant 1")


func _t_mana_spell() -> void:
	var bc := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	_check(bc.s.mana == 3 + BattleCore.MANA_REGEN, "ancient warden start mana %d, got %d"
			% [3 + BattleCore.MANA_REGEN, bc.s.mana])
	_face(bc, 0, "owl_gather2")
	bc.use_face(0, 0)
	_check(bc.s.mana == 5 + BattleCore.MANA_REGEN, "gather +2 → %d, got %d"
			% [5 + BattleCore.MANA_REGEN, bc.s.mana])
	bc.s.mana = 1
	_face(bc, 1, "owl_starfall")     # spell 3
	var c := bc.can_use(1, 0)
	_check(not c.ok and c.err == "mana", "spell unusable without mana")
	bc.s.mana = 10
	c = bc.can_use(1, 0)
	_check(c.ok, "spell usable with mana")
	bc.use_face(1, 0, {"target": 0})
	_check(bc.s.mana == 7, "spell cost deducted, got %d" % bc.s.mana)
	bc.s.mana = 9
	_face(bc, 0, "owl_gather2")
	bc.use_face(0, 0)
	_check(bc.s.mana == 10, "mana capped at 10")


func _t_growth() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "sp_seed_blade")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 3, "seed blade dealt 3")
	_check(bc.s.heroes[0].face_mods[0] == 1, "growth +1 recorded")
	var fd := bc.hero_face(0, 0)
	_check(int(fd.atk) == 4, "face now shows 4")


func _t_pain() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_great_blade")   # atk 10, pain 2
	var hp0: int = bc.s.heroes[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.heroes[0].hp == hp0 - 2, "pain 2 self damage")
	# pain can down yourself, attack still resolves
	var bc2 := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 0
	bc2.s.heroes[0].hp = 2
	_face(bc2, 0, "sp_great_blade")
	var ehp: int = bc2.s.enemies[0].hp
	bc2.use_face(0, 0, {"target": 0})
	_check(bc2.s.heroes[0].down, "downed self via pain")
	_check(bc2.s.enemies[0].hp == ehp - 11, "attack still resolved")


func _t_lucky() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	for k in GameData.SLOTS:
		bc.s.heroes[0].faces[k] = "sp_keen"
	var r0: int = bc.s.rerolls
	bc._roll_hero_die(0, 0)
	_check(bc.s.rerolls == r0 + 1, "lucky granted +1 reroll")
	bc._roll_hero_die(0, 1)
	_check(bc.s.rerolls == r0 + 2, "the B die rolls lucky independently")


func _t_curse() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E08"])
	_silence_enemies(bc)
	bc._do_curse()
	var total_cursed := 0
	for h in bc.s.heroes:
		total_cursed += h.cursed.size()
	_check(total_cursed == 1, "exactly one face cursed")
	for h in bc.s.heroes:
		if h.cursed.size() > 0:
			var slot: int = h.cursed[0]
			var die := GameData.die_of_slot(slot)
			h.rolled[die] = slot
			h.used = false
			var c := bc.can_use(bc.s.heroes.find(h), die)
			_check(not c.ok and c.err == "blank", "cursed face unusable")


func _t_bind() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E06"])
	_enemy_rolls(bc, 0, [{"bind": 1}])
	bc.s.heroes[0].taunt = true   # force bind target hero 0
	bc.end_turn()
	_check(bc.s.heroes[0].bound, "hero bound next turn")
	for i in [1, 2, 3]:
		bc.s.heroes[i].locked = [true, true]
	var rolled0: Array = bc.s.heroes[0].rolled.duplicate()
	bc.s.heroes[0].locked = [false, false]
	bc.s.rerolls = 1
	var consumed := bc.reroll()
	_check(not consumed, "reroll refused when only bound dice are eligible")
	_check(bc.s.heroes[0].rolled == rolled0, "bound dice not rerolled")


func _t_steal_b4() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["B4"], {"chapter": 2})
	var stolen1 := -1
	for i in 4:
		if bc.s.heroes[i].stolen:
			stolen1 = i
	_check(stolen1 >= 0, "B4 stole a die turn 1")
	_check(bc.s.heroes[stolen1].rolled == [-1, -1], "stolen hero has no dice")
	_silence_enemies(bc)
	bc.end_turn()
	var stolen2 := -1
	for i in 4:
		if bc.s.heroes[i].stolen:
			stolen2 = i
	_check(stolen2 >= 0 and stolen2 != stolen1, "turn 2 stole a different hero")


func _t_zanshin() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_focus")         # block 3, buff_next_atk 2
	bc.use_face(0, 0)
	# 老班長 already put 2 up at the top of the turn
	_check(bc.s.heroes[0].block == 5, "focus block 3 on top of the sergeant's 2, got %d"
			% bc.s.heroes[0].block)
	bc.end_turn()
	_check(bc.s.heroes[0].zanshin == 2, "focus +2 active next turn")
	_face(bc, 0, "bdg_heavy4")
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 7, "heavy chop 4 + sergeant 1 + focus 2 = 7, got %d" % bc.attack_value(0, fd))


func _t_settlement_order() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	var h: Dictionary = bc.s.heroes[0]
	h.hp = 5
	h.poison = 2
	h.burn = [2]     # pre-aged burn: ticks this settlement
	h.regen = 3
	bc.end_turn()
	# poison 2 → hp 3 (poison→1); burn 2 → hp 1; regen 3 → hp 4 (regen→2)
	_check(bc.s.heroes[0].hp == 4, "order poison→burn→regen: hp 4, got %d" % bc.s.heroes[0].hp)
	_check(bc.s.heroes[0].poison == 1 and bc.s.heroes[0].regen == 2, "stacks decayed")


func _t_insight() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_insight")
	var r0: int = bc.s.rerolls
	bc.use_face(0, 0)
	_check(bc.s.rerolls == r0 + 1, "insight +1 reroll")
	# the detail card (zh+en) and the codex / run-screen summary both read the
	# face value, so they must move with it rather than drift to a stale "+2"
	var fd: Dictionary = GameData.faces.sp_insight
	var tip := Data.face_tooltip(fd)
	_check("獲得 1 次重擲" in tip and "gain 1 reroll" in tip,
			"insight detail reads 1 in both languages: %s" % tip.replace("\n", " / "))
	# and it explains the term it just used, from the one glossary file
	_check(Glossary.line("rerolls") in tip, "insight detail explains 洞察 Insight")
	var summary := RunWidgets.face_summary("sp_insight")
	_check("重擲+1" in summary and "Reroll +1" in summary,
			"insight codex/run summary reads +1: %s" % summary)


func _t_gambit() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "sp_gambit")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	var dealt: int = hp0 - bc.s.enemies[0].hp
	_check(dealt >= 1 and dealt <= 12, "gambit dealt 1-12, got %d" % dealt)


func _t_time_stop() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E10"], {"chapter": 2})
	_enemy_rolls(bc, 0, [{"atk": 4}, {"atk": 5}])
	_face(bc, 0, "sp_time_stop")
	bc.use_face(0, 0, {"die": {"enemy": 0, "die": 0}, "die2": {"enemy": 0, "die": 1}})
	_check(bc.s.enemies[0].rolls[0].cancelled and bc.s.enemies[0].rolls[1].cancelled, "both dice stunned")


func _t_die_theft() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01", "E01"])
	_enemy_rolls(bc, 0, [{"atk": 6}])
	_silence_enemies(bc)
	bc.s.enemies[0].rolls[0].cancelled = false
	bc.s.enemies[1].block = 0
	_face(bc, 0, "sp_die_theft")
	var hp1: int = bc.s.enemies[1].hp
	var res := bc.use_face(0, 0, {"die": {"enemy": 0, "die": 0}, "theft_target": 1})
	_check(res.ok, "die theft ok")
	_check(bc.s.enemies[0].rolls[0].cancelled, "stolen die consumed")
	_check(bc.s.enemies[1].hp == hp1 - 6, "stolen attack dealt 6 to chosen enemy")


## 迴響 Reverb — the party-wide "next face +X". Not to be confused with 呼應
## Echo, which reads the hero's own locked die (see `_t_resonate`).
func _t_reverb() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	bc.s.heroes[1].hp = 10
	_face(bc, 0, "sp_echo_crystal")
	bc.use_face(0, 0, {"target": 1})
	_check(bc.s.heroes[1].hp == 14, "reverb crystal healed 4")
	_check(bc.s.echo_bonus == 2, "reverb bonus armed")
	_face(bc, 1, "sp_heavy_blow")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(1, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 10, "next face 7 + sergeant 1 + reverb 2 = 10, dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	_check(bc.s.echo_bonus == 0, "reverb consumed")


func _t_potions() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"],
			{"potions": ["P01", "P04", "P06"]})
	_silence_enemies(bc)
	bc.s.heroes[0].hp = 5
	bc.use_potion(0, {"target": 0})
	_check(bc.s.heroes[0].hp == 13, "P01 healed 8")
	_check(bc.s.potions.size() == 2, "potion consumed")
	bc.use_potion(0)   # P04 poison all
	_check(bc.s.enemies[0].poison == 3, "P04 poisoned enemies 3")
	bc.use_potion(0)   # P06 team atk buff
	_check(bc.s.team_atk_buff == 3, "P06 armed +3")
	_face(bc, 1, "sp_heavy_blow")
	var fd := bc.hero_face(1, 0)
	_check(bc.attack_value(1, fd) == 11, "attack buffed 7 + sergeant 1 + potion 3, got %d" % bc.attack_value(1, fd))


func _t_e04_passive() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_check(bc.s.enemies[0].block == 2, "E04 starts each turn with block 2 (T1)")


func _t_e10_two_dice() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E10"], {"chapter": 2})
	_check(bc.s.enemies[0].rolls.size() == 2, "E10 rolls 2 dice")


# ============================================================ dual dice

func _t_dual_dice() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	for i in 4:
		var h: Dictionary = bc.s.heroes[i]
		_check(h.rolled.size() == 2, "hero %d has two dice" % i)
		_check(int(h.rolled[0]) >= 0 and int(h.rolled[0]) <= 5, "A die rolled a slot 0-5")
		_check(int(h.rolled[1]) >= 6 and int(h.rolled[1]) <= 11, "B die rolled a slot 6-11")
	# spending one die locks the other out for the rest of the turn
	_face_pair(bc, 0, "hare_guard2", "hareb_roll")
	_check(bc.can_use(0, 0).ok and bc.can_use(0, 1).ok, "both dice usable before acting")
	var res := bc.use_face(0, 0)
	_check(res.ok, "A die used")
	_check(bc.s.heroes[0].used_dice == [0], "used_dice records which die was spent")
	var locked := bc.can_use(0, 1)
	_check(not locked.ok and locked.err == "locked_out", "the other die is locked out")
	_check(not bc.hero_can_act(0), "hero has no action left this turn")
	# and both come back next turn
	bc.end_turn()
	_check(not bc.s.heroes[0].used, "hero free again next turn")
	_check(bc.s.heroes[0].used_dice.is_empty(), "used_dice cleared")
	_check(bc.s.heroes[0].rolled[0] >= 0 and bc.s.heroes[0].rolled[1] >= 6, "both dice re-rolled")


func _t_reroll_sources() -> void:
	# no base rerolls any more
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_check(bc.s.rerolls == 0, "base rerolls are 0, got %d" % bc.s.rerolls)
	# N11 幸運兔腳 (+2 on turn 1) is the last flat reroll relic standing — round 6
	# turned 森林徽章 and 節拍器 into the two Essence relics, because U2 made
	# Essence itself the party's reroll economy.
	var bc2 := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"], {"relics": ["N11"]})
	_check(bc2.s.rerolls == 2, "N11 gives 2 rerolls on turn 1, got %d" % bc2.s.rerolls)
	_silence_enemies(bc2)
	bc2.end_turn()
	_check(bc2.s.rerolls == 0, "turn 2 has none of them left, got %d" % bc2.s.rerolls)
	# …and U2 is where a party gets one now
	var bc2b := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	bc2b.s.mana = BattleCore.ESSENCE_REROLL_COST
	_check(bc2b.buy_reroll() and bc2b.s.rerolls == 1,
			"U2 is a reroll source, got %d" % bc2b.s.rerolls)
	# the Insight face is still a source
	var bc3 := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc3)
	_face(bc3, 0, "sp_insight")
	bc3.use_face(0, 0)
	_check(bc3.s.rerolls == 1, "insight granted +1")


func _t_reroll_skips_acted_heroes() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	bc.s.rerolls = 1
	# hero 0 acts; hero 1 pins its A die; heroes 2-3 are free
	_face_pair(bc, 0, "hare_guard2", "hareb_roll")
	bc.use_face(0, 0)
	var acted_rolled: Array = bc.s.heroes[0].rolled.duplicate()
	bc.toggle_lock(1, 0)
	var pinned: int = int(bc.s.heroes[1].rolled[0])
	var free_before: Array = bc.s.heroes[3].rolled.duplicate()
	_check(bc.reroll(), "reroll spent")
	_check(bc.s.heroes[0].rolled == acted_rolled, "acted hero's dice untouched")
	_check(bc.s.heroes[0].used and bc.s.heroes[0].used_dice == [0], "acted hero stays spent")
	_check(int(bc.s.heroes[1].rolled[0]) == pinned, "pinned die not rerolled")
	_check(bc.s.rerolls == 0, "one reroll consumed")
	# with a fixed rng this eventually differs; assert only that it may change
	_check(bc.s.heroes[3].rolled.size() == 2, "free hero still has two dice %s" % [free_before])


func _t_face_plus() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 4242)
	var hero: Dictionary = run.team[0]
	_check(hero.faces.size() == 12, "12 face slots per hero")
	_check(hero.face_plus.size() == 12, "12 plus counters per hero")
	RunState.forge_face(hero, 0)
	RunState.forge_face(hero, 0)
	_check(int(hero.face_plus[0]) == 2, "two forges → ++")
	_check(int(hero.face_mods[0]) == 2, "two forges → +2 value")
	# growth bumps the value without earning a "+"
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	_face(bc, 0, "sp_seed_blade")
	bc.s.enemies[0].block = 0
	bc.use_face(0, 0, {"target": 0})
	_check(int(bc.s.heroes[0].face_mods[0]) == 1, "growth raised the value")
	_check(int(bc.s.heroes[0].face_plus[0]) == 0, "growth earns no + mark")
	# a swap clears both counters
	RunState.apply_face_swap(run, 0, 0, "sp_heavy_blow")
	_check(int(hero.face_plus[0]) == 0 and int(hero.face_mods[0]) == 0, "swap resets the slot")


# ============================================================ the lock rule
# Locks survive the turn boundary. Everything the Hare, the Fox and the
# Hedgehog's 反震錘 do is built on that, so it gets tested on its own before
# any of the keywords that read it.

func _t_lock_persists() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E01"])
	_silence_enemies(bc)
	bc.toggle_lock(0, 0)
	var pinned: int = int(bc.s.heroes[0].rolled[0])
	_check(bc.s.heroes[0].locked[0], "die pinned")
	bc.end_turn()
	_check(bc.s.heroes[0].locked[0], "pin survived the turn boundary")
	_check(int(bc.s.heroes[0].rolled[0]) == pinned, "pinned die kept its face")
	_check(int(bc.s.heroes[0].lock_turns[0]) == 1, "one full turn banked, got %d"
			% int(bc.s.heroes[0].lock_turns[0]))
	# the unpinned die of the same hero rolls fresh every turn
	_check(int(bc.s.heroes[0].rolled[1]) >= 6, "the free die still rolled")
	# unpinning drops the banked turns
	bc.toggle_lock(0, 0)
	_check(not bc.s.heroes[0].locked[0] and int(bc.s.heroes[0].lock_turns[0]) == 0,
			"unpinning cleared the bank")


func _t_charge_up() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	bc.s.enemies[0].block = 0
	_face(bc, 0, "hare_aim4")        # atk 4, charge_up 2
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 5, "unpinned: no charge, got %d" % bc.attack_value(0, fd))
	bc.toggle_lock(0, 0)
	_check(bc.attack_value(0, fd) == 5, "pinned but no turn passed yet: still 5")
	_silence_enemies(bc)
	bc.end_turn()
	fd = bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 7, "one turn locked: 5+2=7, got %d" % bc.attack_value(0, fd))
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 9, "two turns locked: 5+4=9, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))


func _t_charge_cap_and_reset() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	bc.s.enemies[0].block = 0
	_face(bc, 0, "hare_aim4")
	bc.toggle_lock(0, 0)
	for _k in 5:
		_silence_enemies(bc)
		bc.end_turn()
	_check(int(bc.s.heroes[0].lock_turns[0]) == 5, "five turns actually elapsed")
	_check(bc.charge_turns(0, 0) == 3, "charge stops counting at 3, got %d" % bc.charge_turns(0, 0))
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 11, "capped at 5 + 3×2 = 11, got %d" % bc.attack_value(0, fd))
	# and spending it wipes the bank. E04 re-arms its 2 Block at every turn
	# start, so the reset has to happen here rather than at setup.
	bc.s.enemies[0].block = 0
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 11, "the charged shot actually landed for 11, dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	_check(int(bc.s.heroes[0].lock_turns[0]) == 0, "charge reset to zero after use")
	_check(not bc.s.heroes[0].locked[0], "the pin is released with the face")


func _t_charge_lost_on_unlock() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_face(bc, 0, "hare_aim4")
	bc.toggle_lock(0, 0)
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.charge_turns(0, 0) == 1, "banked one")
	bc.toggle_lock(0, 0)             # player changes their mind
	_check(bc.charge_turns(0, 0) == 0, "unpinning threw the charge away")
	_face(bc, 0, "hare_aim4")
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 5, "back to the printed 5")


func _t_resonate() -> void:
	# On the Hedgehog, whose 反震錘 answers a BLOCK face — the Fox's passive
	# would add its own +1 and blur the keyword's own number.
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	bc.s.enemies[0].block = 0
	_face_pair(bc, 0, "hedge_recoil4", "hedge_guard3")
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 5, "other die not pinned: no echo, got %d"
			% bc.attack_value(0, fd))
	bc.toggle_lock(0, 1)             # pin the B die, which shows 格擋
	_check(bc.resonate_met(0, fd), "echo condition met on a locked block face")
	_check(bc.attack_value(0, fd) == 7, "echo +2 → 7, got %d" % bc.attack_value(0, fd))
	# the wrong CATEGORY does not answer
	var bc2 := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_face_pair(bc2, 0, "hedge_recoil4", "hedgeb_hammer3")   # B die is an attack
	bc2.toggle_lock(0, 1)
	_check(not bc2.resonate_met(0, bc2.hero_face(0, 0)),
			"an attack face does not answer a block-category echo")
	_check(bc2.attack_value(0, bc2.hero_face(0, 0)) == 5, "no bonus from the wrong category")


## The condition is read when the face is SPENT, not when it is rolled: pinning
## the partner die later in the same turn still pays.
func _t_resonate_timing() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face_pair(bc, 0, "hedge_recoil4", "hedge_guard3")
	var hp0: int = bc.s.enemies[0].hp
	bc.toggle_lock(0, 1)
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 7, "echo applied at use time (5+2), dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	# an UNPINNED partner showing the right face is not enough — the lock is the
	# cost the keyword charges
	var bc2 := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 0
	_face_pair(bc2, 0, "hedge_recoil4", "hedge_guard3")
	var hp1: int = bc2.s.enemies[0].hp
	bc2.use_face(0, 0, {"target": 0})
	_check(bc2.s.enemies[0].hp == hp1 - 5, "no lock, no echo, dealt %d"
			% (hp1 - bc2.s.enemies[0].hp))


## 絕影 is gated rather than bonused: without the echo it cannot be spent at all.
func _t_resonate_requirement() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face_pair(bc, 0, "fox_phantom", "fox_stab3")   # atk 1 ×4, requires an attack echo
	var c := bc.can_use(0, 0)
	_check(not c.ok and c.err == "resonate", "gated face refuses without the echo, err=%s"
			% String(c.get("err", "")))
	bc.toggle_lock(0, 1)
	_check(bc.can_use(0, 0).ok, "usable once the partner die is pinned on an attack")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 4, "1×4 landed 4, dealt %d" % (hp0 - bc.s.enemies[0].hp))


## 自損 is paid straight out of HP: the user's own Block never absorbs it.
func _t_recoil_ignores_block() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	var h: Dictionary = bc.s.heroes[0]
	h.block = 20
	h.hp = h.max_hp
	_face(bc, 0, "boar_crush6")       # atk 6, pain 2
	bc.use_face(0, 0, {"target": 0})
	_check(h.hp == h.max_hp - 2, "recoil 2 came off HP despite 20 block, hp=%d/%d"
			% [h.hp, h.max_hp])
	_check(h.block == 20, "recoil did not spend any block")


## 鷹眼 makes the whole party's attacks pierce for the turn, and it wears off.
func _t_all_pierce() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 10
	_face(bc, 0, "hare_hawkeye")
	bc.use_face(0, 0)
	_check(bc.s.all_pierce, "hawkeye armed")
	_face(bc, 1, "bdg_heavy4")        # the Badger, so no 屏息 on top
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(1, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 5, "party attack ignored 10 block, dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	_check(bc.s.enemies[0].block == 10, "block untouched")
	bc.end_turn()
	_check(not bc.s.all_pierce, "hawkeye expired at end of turn")


## "X×N" strikes N separate times, and Block eats each strike separately.
func _t_multi_hit() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face(bc, 0, "fox_stab1x2")       # atk 1 ×2
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 2, "1×2 dealt 2 into no block, dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	# into block, each strike is absorbed on its own — 1×2 into block 1 lands 1
	var bc2 := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 1
	_face(bc2, 0, "fox_stab1x2")
	var hp1: int = bc2.s.enemies[0].hp
	bc2.use_face(0, 0, {"target": 0})
	_check(bc2.s.enemies[0].hp == hp1 - 1, "first strike ate the block, second landed 1, dealt %d"
			% (hp1 - bc2.s.enemies[0].hp))


## …and Thorns bite once per strike, which is what makes multi-hit a trade.
func _t_multi_hit_thorns() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	bc.s.enemies[0].thorns = 1
	var hp0: int = bc.s.heroes[0].hp
	_face(bc, 0, "fox_stab1x2")
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.heroes[0].hp == hp0 - 2, "took thorns once per strike (2), lost %d"
			% (hp0 - bc.s.heroes[0].hp))


# ============================================================ faces built on the lock

func _t_lock_boost() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	_face_pair(bc, 0, "fox_shift", "fox_stab3")   # A: block 2 + lock_boost 1
	bc.toggle_lock(0, 1)
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].block == 2, "switch still gave its block")
	_check(int(bc.s.heroes[0].die_boost_next[1]) == 1, "boost parked on the pinned die")
	bc.end_turn()
	_check(int(bc.s.heroes[0].die_boost[1]) == 1, "boost is live the following turn")
	var fd := bc.hero_face(0, int(bc.s.heroes[0].rolled[1]))
	_check(bc.attack_value(0, fd) == 5, "the pinned 刺擊 is worth 4+1, got %d"
			% bc.attack_value(0, fd))


func _t_twin_dance() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	_face_pair(bc, 0, "fox_twindance", "fox_stab3")
	bc.toggle_lock(0, 1)
	var pinned_slot: int = int(bc.s.heroes[0].rolled[1])
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].twin_dance, "twin dance armed")
	_check(bc.can_use(0, 1).ok, "the pinned die is usable as a second action")
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 1, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 4, "the danced die dealt 4")
	_check(bc.s.heroes[0].locked[1], "the pin survived being spent")
	_check(bc.s.twin_hero == -1, "twin dance did not claim the Twin Moon Seal slot")
	bc.end_turn()
	_check(bc.s.heroes[0].locked[1] and int(bc.s.heroes[0].rolled[1]) == pinned_slot,
			"pinned die kept its face into the next turn")


func _t_all_in() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	var hp0: int = bc.s.heroes[0].hp
	_face_b(bc, 0, "boarb_allin")
	bc.use_face(0, 1)
	_check(bc.s.heroes[0].hp == hp0 - 2, "all-in cost 2 HP")
	_check(bc.s.heroes[0].die_boost_next == [2, 2], "both dice armed for +2, got %s"
			% [bc.s.heroes[0].die_boost_next])
	bc.end_turn()
	_check(bc.s.heroes[0].die_boost == [2, 2], "the boost is live next turn")
	_face(bc, 0, "boar_wild3")
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 5, "蠻擊3 is worth 5, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))


func _t_shield_bash() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	bc.s.heroes[0].block = 4
	_face(bc, 0, "hedge_shieldbash")   # damage = current block, capped 6
	var hp0: int = bc.s.enemies[0].hp
	bc.use_face(0, 0, {"target": 0})
	_check(bc.s.enemies[0].hp == hp0 - 4, "bash dealt the block value 4, dealt %d"
			% (hp0 - bc.s.enemies[0].hp))
	_check(bc.s.heroes[0].block == 4, "the block was not spent")
	# and the cap holds
	var bc2 := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 0
	bc2.s.heroes[0].block = 9
	_face(bc2, 0, "hedge_shieldbash")
	var hp1: int = bc2.s.enemies[0].hp
	bc2.use_face(0, 0, {"target": 0})
	_check(bc2.s.enemies[0].hp == hp1 - 6, "bash capped at 6, dealt %d" % (hp1 - bc2.s.enemies[0].hp))


func _t_bristle() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.heroes[0].thorns = 3
	_face(bc, 0, "hedge_bristle")
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].thorns == 6, "3 doubled to 6, got %d" % bc.s.heroes[0].thorns)
	# the cap bites, and doubling nothing gives nothing
	var bc2 := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.heroes[0].thorns = 7
	_face(bc2, 0, "hedge_bristle")
	bc2.use_face(0, 0)
	_check(bc2.s.heroes[0].thorns == 11, "7 + min(7,4) = 11, got %d" % bc2.s.heroes[0].thorns)
	var bc3 := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc3)
	bc3.s.heroes[0].thorns = 0
	_face(bc3, 0, "hedge_bristle")
	bc3.use_face(0, 0)
	_check(bc3.s.heroes[0].thorns == 0, "doubling zero thorns is still zero")


func _t_essence_ward() -> void:
	var bc := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	bc.s.mana = 4
	bc.s.heroes[0].block = 0
	_face(bc, 0, "owl_essenceward")
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].block == 4, "block equal to essence 4, got %d" % bc.s.heroes[0].block)
	_check(bc.s.mana == 4, "essence not spent")
	var bc2 := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.mana = 9
	bc2.s.heroes[0].block = 0
	_face(bc2, 0, "owl_essenceward")
	bc2.use_face(0, 0)
	_check(bc2.s.heroes[0].block == 6, "capped at 6, got %d" % bc2.s.heroes[0].block)


func _t_thorn_hold() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_silence_enemies(bc)
	bc.s.heroes[0].thorns = 5
	bc.s.heroes[1].thorns = 5
	_face(bc, 0, "hedge_hold")
	bc.use_face(0, 0)
	bc.end_turn()
	_check(bc.s.heroes[0].thorns == 5, "hold fast stopped the decay, got %d" % bc.s.heroes[0].thorns)
	_check(bc.s.heroes[1].thorns == 4, "everyone else still decayed, got %d" % bc.s.heroes[1].thorns)
	# and it is only for the one turn
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.s.heroes[0].thorns == 4, "decay resumed the next turn, got %d" % bc.s.heroes[0].thorns)


func _t_war_cry() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E04"])
	_silence_enemies(bc)
	_face(bc, 0, "bdg_warcry")
	bc.use_face(0, 0)
	_check(bc.s.team_atk_buff == 1, "war cry armed +1 for the party")
	_face(bc, 1, "hare_quick3")
	_check(bc.attack_value(1, bc.hero_face(1, 0)) == 5, "an ally's 速射 is worth 4+1, got %d"
			% bc.attack_value(1, bc.hero_face(1, 0)))
	bc.end_turn()
	_check(bc.s.team_atk_buff == 0, "war cry expired")


func _t_rampage() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.heroes[0].hp = bc.s.heroes[0].max_hp   # above the fury line
	var hp0: int = bc.s.heroes[0].hp
	_face_pair(bc, 0, "boar_rampage", "boar_wild3")
	bc.use_face(0, 0)
	_check(bc.s.heroes[0].hp == hp0 - 1, "rampage cost 1 HP")
	_check(int(bc.s.heroes[0].atk_now) == 2, "rampage armed +2 for the turn")
	var fd := bc.hero_face(0, 6)
	_check(bc.attack_value(0, fd) == 5, "his 蠻擊3 is worth 5 this turn, got %d"
			% bc.attack_value(0, fd))
	bc.end_turn()
	_check(int(bc.s.heroes[0].atk_now) == 0, "rampage expired")


func _t_heal_on_hit() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	bc.s.enemies[0].block = 0
	bc.s.heroes[0].hp = 20                       # above 50% of 28, so no fury
	_face_b(bc, 0, "boarb_bloodhit3")            # atk 3, heal_on_hit 1
	bc.use_face(0, 1, {"target": 0})
	_check(bc.s.heroes[0].hp == 21, "bloodthirst healed 1 on a landed hit, hp=%d"
			% bc.s.heroes[0].hp)
	# fully blocked → no heal
	var bc2 := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc2)
	bc2.s.enemies[0].block = 30
	bc2.s.heroes[0].hp = 20
	_face_b(bc2, 0, "boarb_bloodhit3")
	bc2.use_face(0, 1, {"target": 0})
	_check(bc2.s.heroes[0].hp == 20, "no HP lost by the target → no heal, hp=%d"
			% bc2.s.heroes[0].hp)


func _t_last_ditch() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E04"])
	_silence_enemies(bc)
	_face(bc, 0, "boar_lastditch")               # atk 4, becomes 7 at ≤50%
	bc.s.heroes[0].hp = bc.s.heroes[0].max_hp
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 4, "healthy: prints 4, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))
	bc.s.heroes[0].hp = 12                       # 12/24 = 50%
	# 7 from the face, +2 from 背水之勢 which is live at the same threshold
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 9, "cornered: 7 + fury 2 = 9, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))


# ============================================================ passives

func _t_passive_old_sergeant() -> void:
	var bc := _mk(["BADGER", "HARE", "OWL", "HEDGE"], ["E01"])
	_check(bc.s.heroes[0].block == 2, "badger opens with 2 block, got %d" % bc.s.heroes[0].block)
	_check(bc.s.heroes[1].block == 0, "nobody else does")
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.s.heroes[0].block == 2, "and again next turn, got %d" % bc.s.heroes[0].block)


func _t_passive_held_breath() -> void:
	var bc := _mk(["HARE", "BADGER", "OWL", "HEDGE"], ["E04"])
	_face(bc, 0, "hare_pierce2")       # atk 2, pierce
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 5, "3 + 2 held breath = 5, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))
	_face(bc, 0, "hare_quick3")        # no pierce, no bonus
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 4, "non-piercing shot is plain 4, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))
	# 鷹眼 makes everything pierce, so it turns the passive on for the turn too
	bc.s["all_pierce"] = true
	_check(bc.attack_value(0, bc.hero_face(0, 0)) == 6, "under hawkeye it counts as piercing: 6, got %d"
			% bc.attack_value(0, bc.hero_face(0, 0)))


func _t_passive_quilled_hide() -> void:
	var bc := _mk(["HEDGE", "HARE", "BADGER", "OWL"], ["E01"])
	_silence_enemies(bc)
	bc.s.heroes[0].block = 12
	bc.s.heroes[1].block = 5
	bc.end_turn()
	_check(bc.s.heroes[0].block == 10, "hedgehog carries block capped 10, got %d" % bc.s.heroes[0].block)
	_check(bc.s.heroes[1].block == 0, "others lose block")


func _t_passive_ancient_warden() -> void:
	var bc := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E01"])
	_check(bc.s.mana == 3 + BattleCore.MANA_REGEN,
			"owl opens the fight with 3 essence + U1, got %d" % bc.s.mana)
	# U1 changed the second half of this: a party WITHOUT the Owl no longer
	# opens on nothing. That is the point of the rule — the Owl's passive is now
	# a head start on a resource everybody has, rather than the only tap.
	var bc2 := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	_check(bc2.s.mana == BattleCore.MANA_REGEN,
			"no owl, just the U1 regen, got %d" % bc2.s.mana)
	_check(bc.s.mana - bc2.s.mana == 3,
			"the Owl is still worth exactly his 3-point head start, got %d"
					% (bc.s.mana - bc2.s.mana))


# ============================================================ round 6: Essence

## U1 — the pool fills for everybody, every turn, with nobody's help.
func _t_u1_regen() -> void:
	var bc := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	_check(bc.s.mana == BattleCore.MANA_REGEN,
			"turn 1 opens on the regen alone, got %d" % bc.s.mana)
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.s.mana == BattleCore.MANA_REGEN * 2,
			"turn 2 adds another, got %d" % bc.s.mana)
	# and it does not push past the ceiling
	bc.s.mana = BattleCore.MANA_CAP
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.s.mana == BattleCore.MANA_CAP,
			"regen respects the cap, got %d" % bc.s.mana)


## U2 — two Essence buys one reroll, once a turn.
func _t_u2_essence_reroll() -> void:
	var bc := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	bc.s.mana = 5
	var rr := int(bc.s.rerolls)
	_check(bc.can_buy_reroll().ok, "the trade is offered with 5 Essence")
	_check(bc.buy_reroll(), "the trade goes through")
	_check(bc.s.mana == 5 - BattleCore.ESSENCE_REROLL_COST,
			"it costs %d, got a pool of %d" % [BattleCore.ESSENCE_REROLL_COST, bc.s.mana])
	_check(bc.s.rerolls == rr + 1, "it buys exactly one throw, got %d" % (bc.s.rerolls - rr))
	# once a turn — even with plenty left
	var c := bc.can_buy_reroll()
	_check(not c.ok and c.err == "spent", "the second trade this turn is refused")
	_check(not bc.buy_reroll(), "…and refusing it means refusing it")
	# …and it comes back next turn
	_silence_enemies(bc)
	bc.end_turn()
	_check(bc.can_buy_reroll().ok, "the trade is back next turn")
	# not affordable is not offered
	bc.s.mana = BattleCore.ESSENCE_REROLL_COST - 1
	var c2 := bc.can_buy_reroll()
	_check(not c2.ok and c2.err == "mana", "an empty pool cannot buy a throw")


## The six new starting faces do what they say, and each hero has one.
func _t_essence_faces() -> void:
	# 靈甲: Block AND a point in the pool, off one die
	var bc := _mk(["BADGER", "HARE", "HEDGE", "FOX"], ["E01"])
	_silence_enemies(bc)
	var m0 := int(bc.s.mana)
	_face(bc, 0, "bdg_essenceguard")
	_check(bc.use_face(0, 0).ok, "Essence Guard resolves")
	_check(bc.s.heroes[0].block >= 3, "Essence Guard blocks, got %d" % bc.s.heroes[0].block)
	_check(bc.s.mana == m0 + 1, "Essence Guard also fills the pool, got %d" % bc.s.mana)

	# 以血引靈: 3 Essence bought with 2 HP
	var bc2 := _mk(["BOAR", "HARE", "HEDGE", "FOX"], ["E01"])
	_silence_enemies(bc2)
	var hp := int(bc2.s.heroes[0].hp)
	var m2 := int(bc2.s.mana)
	_face(bc2, 0, "boar_bloodtithe")
	_check(bc2.use_face(0, 0).ok, "Blood Tithe resolves")
	_check(bc2.s.mana == m2 + 3, "Blood Tithe draws 3, got %d" % (bc2.s.mana - m2))
	_check(bc2.s.heroes[0].hp == hp - 2, "Blood Tithe costs 2 HP, got %d" % (hp - bc2.s.heroes[0].hp))

	# 靈棘綻放: a Ritual that pays the whole party
	var bc3 := _mk(["HEDGE", "HARE", "BADGER", "FOX"], ["E01"])
	_silence_enemies(bc3)
	bc3.s.mana = 6
	_face(bc3, 0, "hedge_essencebloom")
	_check(bc3.use_face(0, 0).ok, "Essence Bloom resolves")
	_check(bc3.s.mana == 4, "Essence Bloom costs 2, got a pool of %d" % bc3.s.mana)
	for j in bc3.s.heroes.size():
		_check(int(bc3.s.heroes[j].thorns) >= 2,
				"Essence Bloom thorns hero %d, got %d" % [j, int(bc3.s.heroes[j].thorns)])
		_check(int(bc3.s.heroes[j].block) >= 2,
				"Essence Bloom blocks hero %d, got %d" % [j, int(bc3.s.heroes[j].block)])

	# 星落: an area Ritual, and one nobody can cast on an empty pool
	var bc4 := _mk(["OWL", "HARE", "BADGER", "HEDGE"], ["E01", "E02"])
	_silence_enemies(bc4)
	bc4.s.mana = 0
	_face(bc4, 0, "owl_starshower")
	_check(not bc4.can_use(0, 0).ok, "Starfall is unusable on an empty pool")
	bc4.s.mana = 9
	var before := [int(bc4.s.enemies[0].hp), int(bc4.s.enemies[1].hp)]
	_check(bc4.use_face(0, 0).ok, "Starfall resolves")
	_check(int(bc4.s.enemies[0].hp) < before[0] and int(bc4.s.enemies[1].hp) < before[1],
			"Starfall hits every enemy")
	_check(bc4.s.mana == 5, "Starfall costs 4, got a pool of %d" % bc4.s.mana)

	# every hero owns at least one Essence face among their twelve starters —
	# the round's stated goal, asserted rather than eyeballed
	for hid in GameData.hero_ids():
		var hd: Dictionary = GameData.heroes[hid]
		var got := false
		for fid in Array(hd.start) + Array(hd.start_b):
			var f: Dictionary = GameData.faces[String(fid)]
			if f.has("mana") or f.has("spell"):
				got = true
		_check(got, "%s starts with an Essence face" % hid)


## 引靈瞄準: Essence is the headline, so the die's banked Charge lands on it.
func _t_attuned_aim_charge() -> void:
	var bc := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	_silence_enemies(bc)
	_face(bc, 0, "hare_attunedaim")
	var m := int(bc.s.mana)
	# cold: the printed 1
	_check(bc.use_face(0, 0).ok, "Attuned Aim resolves cold")
	_check(bc.s.mana == m + 1, "cold Attuned Aim draws 1, got %d" % (bc.s.mana - m))
	# two turns in the lock: 1 + 2
	var bc2 := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	_silence_enemies(bc2)
	_face(bc2, 0, "hare_attunedaim")
	bc2.s.heroes[0].lock_turns[0] = 2
	var m2 := int(bc2.s.mana)
	_check(bc2.use_face(0, 0).ok, "Attuned Aim resolves charged")
	_check(bc2.s.mana == m2 + 3,
			"two layers of Charge make it 3, got %d" % (bc2.s.mana - m2))
	# and the sentence agrees with the engine, which is what the cast strip shows
	var bc3 := _mk(["HARE", "BADGER", "HEDGE", "FOX"], ["E01"])
	_face(bc3, 0, "hare_attunedaim")
	bc3.s.heroes[0].lock_turns[0] = 2
	var live := bc3.live_face(0, bc3.hero_face(0, 0))
	_check(int(live.mana) == 3, "the live face reports 3, got %d" % int(live.mana))


func _t_passive_call_and_answer() -> void:
	var bc := _mk(["FOX", "HARE", "BADGER", "OWL"], ["E04"])
	_face_pair(bc, 0, "fox_echo3", "fox_stab3")   # atk 3, resonate 2 on an attack
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 4, "unanswered: plain 4, got %d" % bc.attack_value(0, fd))
	bc.toggle_lock(0, 1)
	_check(bc.attack_value(0, fd) == 7, "4 + echo 2 + passive 1 = 7, got %d"
			% bc.attack_value(0, fd))


func _t_passive_cornered_fury() -> void:
	var bc := _mk(["BOAR", "HARE", "BADGER", "OWL"], ["E01"])
	_silence_enemies(bc)
	_face(bc, 0, "boar_wild3")
	var fd := bc.hero_face(0, 0)
	_check(bc.attack_value(0, fd) == 3, "full hp: no fury")
	bc.s.heroes[0].hp = 12   # 12/24 = 50%
	_check(bc.attack_value(0, fd) == 5, "at 50%%: fury +2, got %d" % bc.attack_value(0, fd))
