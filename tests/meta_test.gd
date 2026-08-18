extends Node
## Meta progression tests: XP levels, face unlocks entering offer pools,
## first-clear hero unlock flow, full data reset.
##   godot --headless --path . res://tests/meta_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame
	Game.reset_all_data()
	_t_xp_levels()
	_t_unlocked_faces_in_offers()
	_t_hero_unlock_flow()
	_t_reset()
	print("META: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("META OK")
	get_tree().quit(0 if fails == 0 else 1)


func _t_xp_levels() -> void:
	Game.reset_all_data()
	_check(Game.hero_level("HARE") == 1, "fresh hero level 1")
	var ups := Game.grant_xp(["HARE", "BADGER"], 3)
	_check(ups.is_empty(), "3 XP: no level up yet")
	ups = Game.grant_xp(["HARE"], 1)
	_check(ups.has("HARE"), "4 XP: H1 hits level 2")
	_check(Game.hero_level("HARE") == 2, "level 2 at 4 XP")
	_check(Game.hero_level("BADGER") == 1, "H2 still level 1 at 3 XP")
	Game.grant_xp(["HARE"], 24)   # 28 total → level 5
	_check(Game.hero_level("HARE") == 5, "level 5 at 28 XP")
	_check(Game.unlocked_faces("HARE").size() == 8, "all 8 unlock faces at level 5 (2-per-level batches)")
	_check("hare_pierce3" in Game.unlocked_faces("HARE"), "Lv2 face unlocked")
	# persists across reload (simulating cross-run)
	Game.load_meta()
	_check(Game.hero_level("HARE") == 5, "XP persisted to meta.json")


func _t_unlocked_faces_in_offers() -> void:
	var run := RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 999)
	var rng := RunState.rng_of(run)
	var unlocked := {"HARE": ["hare_pierce3", "hare_longshot"]}
	var hero_face_hits := 0
	for k in 300:
		var offers := RunState.gen_offers(run, rng, "battle", unlocked)
		for o in offers:
			if String(o.face).begins_with("hare_"):
				var hero: Dictionary = run.team[int(o.hero)]
				_check(hero.id == "HARE", "hero face offered to the right hero")
				hero_face_hits += 1
	_check(hero_face_hits > 10, "unlocked hero faces appear in offers (%d hits)" % hero_face_hits)


func _t_hero_unlock_flow() -> void:
	Game.reset_all_data()
	_check(Game.meta.unlocked_heroes.size() == 4, "4 starters unlocked")
	# first clear
	Game.meta.clears = 0
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 1)
	Game.run.chapter = 3
	Game.run.stats.start_msec = int(Time.get_unix_time_from_system()) - 100
	Game._on_chapter_cleared()
	_check(Game.meta.pending_hero_pick, "first clear → pending hero pick")
	_check(int(Game.meta.clears) == 1, "clears counted")
	_check(int(Game.meta.fastest_clear_sec) >= 100, "fastest time recorded")
	# player picks H5 (victory screen does this)
	Game.meta.unlocked_heroes.append("BOAR")
	Game.meta.pending_hero_pick = false
	# second clear → auto-unlock the other
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 2)
	Game.run.chapter = 3
	Game.run.stats.start_msec = int(Time.get_unix_time_from_system()) - 50
	Game._on_chapter_cleared()
	_check("FOX" in Game.meta.unlocked_heroes, "second clear unlocks the other hero")


func _t_reset() -> void:
	Game.grant_xp(["OWL"], 10)
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 3)
	Game.save_run()
	Game.reset_all_data()
	_check(int(Game.meta.xp.H3) == 0, "XP wiped")
	_check(Game.meta.unlocked_heroes.size() == 4, "hero unlocks wiped")
	_check(int(Game.meta.clears) == 0 and int(Game.meta.wins) == 0, "stats wiped")
	_check(not Game.has_saved_run(), "run save deleted")
	_check(not bool(Game.settings.tutorial_done), "tutorial reset")
