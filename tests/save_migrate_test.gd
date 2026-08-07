extends Node
## The 2026-08-06 character overhaul replaced all six playable characters. This
## suite builds a representative PRE-overhaul save by hand — partial XP on some
## heroes, XP-pool faces already unlocked, one of the two locked heroes earned,
## a codex full of retired face ids, and an in-progress run mid-chapter — then
## loads it and asserts that nothing evaporated and nothing threw.
##   godot --headless --path . res://tests/save_migrate_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


## A meta.json exactly as the game wrote them before the overhaul.
##   H1 苔蛙遊俠 Moss   28 XP → level 5, all four pool faces earned
##   H2 墨羽武士 Kuro   10 XP → level 3
##   H3 珊瑚法師 Lily    4 XP → level 2
##   H4 燼靈     Ember   0 XP → level 1
##   H5 骨面狐   Vex    17 XP → level 3, and UNLOCKED (first clear went to him)
##   H6 荊棘貓巫 Bramble 0 XP → still locked
func _legacy_meta() -> Dictionary:
	return {
		"xp": {"H1": 28, "H2": 10, "H3": 4, "H4": 0, "H5": 17, "H6": 0},
		"unlocked_heroes": ["H1", "H2", "H3", "H4", "H5"],
		"clears": 1, "runs": 9, "wins": 1,
		"fastest_clear_sec": 1875,
		"pending_hero_pick": false,
		"used_face_ids": [
			# starting faces of three different retired heroes
			"moss_arrow", "moss_roll", "kuro_slash", "ember_bulwark",
			# XP-pool faces they actually earned and spent
			"moss_pierce", "moss_rain", "moss_mark", "moss_volley",
			"kuro_swallow", "vex_drink",
			# B-die faces
			"mossb_snap", "kurob_meditate", "vexb_bonewall",
			# shared-pool faces, whose ids did NOT change
			"sp_heavy_blow", "sp_cure", "sp_gambit",
		],
		"encountered_enemies": ["E01:1", "E07:2"],
		"encountered_bosses": ["B1", "B2"],
		"encountered_affixes": ["frenzied"],
	}


func _ready() -> void:
	GameData.load_all()
	_t_hero_mapping_is_total()
	_t_face_map_covers_the_old_roster()
	_t_meta_migration()
	_t_meta_migration_is_idempotent()
	_t_run_migration()
	_t_run_keeps_shared_pool_faces()
	_t_round_trip_through_game_state()
	print("SAVEMIGRATE: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("SAVEMIGRATE OK")
	get_tree().quit(0 if fails == 0 else 1)


func _t_hero_mapping_is_total() -> void:
	var seen := {}
	for old_id in SaveMigrate.HERO_MAP:
		var new_id: String = SaveMigrate.HERO_MAP[old_id]
		_check(GameData.heroes.has(new_id), "%s maps to a hero that exists (%s)" % [old_id, new_id])
		_check(not seen.has(new_id), "%s is the target of exactly one old hero" % new_id)
		seen[new_id] = true
	_check(seen.size() == GameData.hero_ids().size(),
			"every new hero inherits exactly one old one (%d of %d)"
			% [seen.size(), GameData.hero_ids().size()])
	# the two that have to be earned must inherit from the two that had to be
	# earned, or a save with one unlocked would silently unlock a starter
	var unlockable := GameData.unlockable_hero_ids()
	_check(String(SaveMigrate.HERO_MAP.H5) in unlockable
			and String(SaveMigrate.HERO_MAP.H6) in unlockable,
			"the two locked heroes map onto the two locked heroes")


func _t_face_map_covers_the_old_roster() -> void:
	var fmap := SaveMigrate.face_map()
	for old_id in SaveMigrate.HERO_MAP:
		for arr in [SaveMigrate.OLD_START[old_id], SaveMigrate.OLD_START_B[old_id],
				SaveMigrate.OLD_UNLOCKS[old_id]]:
			for fid_v in arr:
				var fid := String(fid_v)
				_check(fmap.has(fid), "retired face %s has a successor" % fid)
				if fmap.has(fid):
					var target := String(fmap[fid])
					_check(GameData.faces.has(target),
							"%s → %s, which exists" % [fid, target])
					_check(String(GameData.faces[target].get("hero", ""))
							== String(SaveMigrate.HERO_MAP[old_id]),
							"%s → %s, which belongs to %s"
							% [fid, target, SaveMigrate.HERO_MAP[old_id]])
	# XP-pool faces map by POOL INDEX, per the brief
	var pool_map := SaveMigrate.face_map()
	var hare_pool: Dictionary = GameData.heroes.HARE.unlocks
	_check(String(pool_map["moss_pierce"]) == String(hare_pool["2"]),
			"old pool slot 1 → new pool slot 1")
	_check(String(pool_map["moss_volley"]) == String(hare_pool["5"]),
			"old pool slot 4 → new pool slot 4")


func _t_meta_migration() -> void:
	var meta := _legacy_meta()
	_check(SaveMigrate.needs_meta_migration(meta), "a pre-overhaul meta is detected")
	var before_total := 28 + 10 + 4 + 0 + 17 + 0
	SaveMigrate.migrate_meta(meta)

	# --- XP moved, in full, onto the mapped characters
	_check(int(meta.xp.HARE) == 28, "Moss's 28 XP is the Hare's, got %d" % int(meta.xp.HARE))
	_check(int(meta.xp.BADGER) == 10, "Kuro's 10 XP is the Badger's, got %d" % int(meta.xp.BADGER))
	_check(int(meta.xp.OWL) == 4, "Lily's 4 XP is the Owl's, got %d" % int(meta.xp.OWL))
	_check(int(meta.xp.HEDGE) == 0, "Ember's 0 XP is the Hedgehog's")
	_check(int(meta.xp.BOAR) == 17, "Vex's 17 XP is the Boar's, got %d" % int(meta.xp.BOAR))
	_check(int(meta.xp.FOX) == 0, "Bramble's 0 XP is the Fox's")
	var after_total := 0
	for v in meta.xp.values():
		after_total += int(v)
	_check(after_total == before_total, "not one point of XP evaporated (%d → %d)"
			% [before_total, after_total])
	_check(meta.xp.size() == GameData.hero_ids().size(),
			"the XP table has one row per living hero")
	for k in meta.xp:
		_check(GameData.heroes.has(String(k)), "no retired id left in the XP table (%s)" % k)

	# --- the unlock the player earned came with them
	_check("BOAR" in meta.unlocked_heroes, "the earned unlock (Vex) became the Boar")
	_check("FOX" not in meta.unlocked_heroes, "the one never earned stays locked")
	for st in GameData.starter_hero_ids():
		_check(st in meta.unlocked_heroes, "starter %s is unlocked" % st)
	_check(meta.unlocked_heroes.size() == 5, "five heroes unlocked, got %d"
			% meta.unlocked_heroes.size())

	# --- codex flags followed their faces
	_check("hare_quick2" in meta.used_face_ids or "hare_quick3" in meta.used_face_ids,
			"a Moss starting face left a Hare face marked seen")
	_check(String(SaveMigrate.face_map()["moss_pierce"]) in meta.used_face_ids,
			"an earned pool face stayed seen through the remap")
	_check(String(SaveMigrate.face_map()["vex_drink"]) in meta.used_face_ids,
			"the Boar inherited Vex's codex entry")
	for f in ["sp_heavy_blow", "sp_cure", "sp_gambit"]:
		_check(f in meta.used_face_ids, "shared-pool face %s is untouched" % f)
	for f2 in meta.used_face_ids:
		_check(GameData.faces.has(String(f2)), "no dead face id left in the codex (%s)" % f2)

	# --- everything not about the cast is left alone
	_check(int(meta.clears) == 1 and int(meta.runs) == 9 and int(meta.wins) == 1,
			"run counters untouched")
	_check(int(meta.fastest_clear_sec) == 1875, "best time untouched")
	_check(meta.encountered_bosses == ["B1", "B2"], "boss codex untouched")
	_check(meta.encountered_enemies == ["E01:1", "E07:2"], "minion codex untouched")
	_check(int(meta.save_version) == SaveMigrate.SAVE_VERSION, "version stamped")


func _t_meta_migration_is_idempotent() -> void:
	var meta := _legacy_meta()
	SaveMigrate.migrate_meta(meta)
	var once := JSON.stringify(meta)
	_check(not SaveMigrate.needs_meta_migration(meta), "a migrated meta is not re-detected")
	SaveMigrate.migrate_meta(meta)
	_check(JSON.stringify(meta) == once, "running it twice changes nothing")


## A pre-overhaul run.json: mid-chapter-2, three of Moss's twelve slots already
## swapped for shop faces, forge marks and growth stacks on the board.
func _legacy_run() -> Dictionary:
	var run: Dictionary = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 31337)
	run.chapter = 2
	run.gold = 240
	run.relics = ["N02", "A01"]
	for i in run.team.size():
		var h: Dictionary = run.team[i]
		h["id"] = ["H1", "H2", "H3", "H4"][i]
		h["faces"] = SaveMigrate.OLD_START[h.id].duplicate()
		h.faces.append_array(SaveMigrate.OLD_START_B[h.id])
		h["max_hp"] = [22, 26, 18, 30][i]
		h["hp"] = [11, 26, 9, 30][i]     # the Frog and the Salamancer are at half
	# the player bought three shared faces during the run
	run.team[0].faces[2] = "sp_heavy_blow"
	run.team[0].faces[7] = "sp_cure"
	run.team[1].faces[4] = "sp_gambit"
	run.team[0].face_plus[0] = 2
	run.team[0].face_mods[0] = 2
	run.erase("save_version")
	return run


func _t_run_migration() -> void:
	var run := _legacy_run()
	_check(SaveMigrate.migrate_run(run), "an in-progress run migrates rather than being dropped")
	var ids := []
	for h in run.team:
		ids.append(String(h.id))
	_check(ids == ["HARE", "BADGER", "OWL", "HEDGE"], "team ids remapped, got %s" % [ids])
	for h2 in run.team:
		_check(h2.faces.size() == GameData.SLOTS, "%s still has twelve slots" % h2.id)
		for fid_v in h2.faces:
			_check(GameData.faces.has(String(fid_v)),
					"%s holds a face that exists (%s)" % [h2.id, fid_v])
	# HP is carried across as a PROPORTION — the Hare's smaller frame must not
	# leave a full-health hero looking wounded, or a wounded one at full
	_check(int(run.team[0].max_hp) == int(GameData.heroes.HARE.hp),
			"max HP is now the new character's")
	# 11/22 is exactly half; the Hare's frame is 23, so half of it rounds to 12.
	# Asserting the RATIO rather than a literal is what keeps this test alive
	# through the next balance pass.
	var kept := float(run.team[0].hp) / float(run.team[0].max_hp)
	_check(absf(kept - 0.5) <= 0.03, "half-health stayed half-health, got %d/%d (%.2f)"
			% [int(run.team[0].hp), int(run.team[0].max_hp), kept])
	_check(int(run.team[3].hp) == int(run.team[3].max_hp),
			"a full-health hero stayed full")
	_check(int(run.team[1].hp) == int(run.team[1].max_hp),
			"the Badger inherited a full bar too")
	# forge marks stay on their slot
	_check(int(run.team[0].face_plus[0]) == 2 and int(run.team[0].face_mods[0]) == 2,
			"forge marks stayed on slot 0")
	_check(int(run.chapter) == 2 and int(run.gold) == 240, "run progress untouched")
	_check(run.relics == ["N02", "A01"], "relics untouched")
	# and a battle can actually be started from the migrated team
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bc := BattleCore.new()
	bc.setup(run.team, ["E01"], {"chapter": 2, "relics": run.relics}, rng)
	_check(bc.s.heroes.size() == 4, "the migrated team boots a battle")
	var any_usable := false
	for i in 4:
		if bc.hero_can_act(i):
			any_usable = true
	_check(any_usable, "somebody on the migrated team can actually act")


func _t_run_keeps_shared_pool_faces() -> void:
	var run := _legacy_run()
	SaveMigrate.migrate_run(run)
	_check(String(run.team[0].faces[2]) == "sp_heavy_blow",
			"a bought shared face stayed in its slot, got %s" % run.team[0].faces[2])
	_check(String(run.team[0].faces[7]) == "sp_cure", "…on the B die too")
	_check(String(run.team[1].faces[4]) == "sp_gambit", "…and on another hero")
	# the hero-bound slots around them were re-seated from the new character
	_check(String(run.team[0].faces[0]) == String(GameData.heroes.HARE.start[0]),
			"slot 0 took the Hare's first starting face")
	_check(String(run.team[0].faces[6]) == String(GameData.heroes.HARE.start_b[0]),
			"slot 6 took the Hare's first B-die face")


## The path the player actually walks: an old meta.json on disk, then a launch.
func _t_round_trip_through_game_state() -> void:
	var f := FileAccess.open("user://meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_legacy_meta(), "\t"))
	f = null
	Game.meta = {
		"save_version": 0, "xp": {}, "unlocked_heroes": [],
		"clears": 0, "runs": 0, "wins": 0, "fastest_clear_sec": 0,
		"pending_hero_pick": false, "used_face_ids": [],
		"encountered_enemies": [], "encountered_bosses": [], "encountered_affixes": [],
	}
	Game._blank_meta_progress()
	Game.load_meta()
	_check(int(Game.meta.xp.get("HARE", -1)) == 28, "load_meta ran the migration")
	_check(Game.hero_level("HARE") == 5, "28 XP still reads as level 5, got %d"
			% Game.hero_level("HARE"))
	_check(Game.hero_level("BOAR") == 3, "17 XP still reads as level 3, got %d"
			% Game.hero_level("BOAR"))
	# the pool faces that level had earned are still earned
	var earned := Game.unlocked_faces("HARE")
	_check(earned.size() == 4, "level 5 still unlocks four pool faces, got %d" % earned.size())
	for fid in earned:
		_check(GameData.faces.has(String(fid)), "unlocked face %s exists" % fid)
	# a second launch must not touch it again
	Game.load_meta()
	_check(int(Game.meta.xp.get("HARE", -1)) == 28, "a second launch is a no-op")
	Game.reset_all_data()
