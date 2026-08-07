extends Node
## Instantiates every screen headless with a live run to catch script errors.
##   godot --headless --path . res://tests/screens_crawl.tscn

var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame
	# prepare a run + pending reward
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 2468)
	Game.run.gold = 200
	Game.run.potions = ["P01", "P02"]
	var rng := RunState.rng_of(Game.run)
	Game.pending_reward = {
		"gold": 15, "kind": "battle", "xp_amount": 1, "xp_ups": {},
		"extra_relics": [], "advanced": [], "advanced_showcase": false,
		"offers": RunState.gen_offers(Game.run, rng, "battle", {}),
	}
	RunState.save_rng(Game.run, rng)

	var screens := ["menu", "charselect", "map", "reward", "shop", "rest",
			"treasure", "event", "settings", "metaprogress", "codex",
			"gameover", "victory"]
	for name in screens:
		print("crawl: " + name)
		var script: GDScript = load("res://scripts/ui/screen_%s.gd" % name)
		_check(script != null, "screen script %s loads" % name)
		if script == null:
			continue
		var inst: Control = script.new()
		inst.set_anchors_preset(Control.PRESET_FULL_RECT)
		if inst.has_method("setup"):
			inst.setup({"stats": {"battles": 3}, "duration": 300})
		add_child(inst)
		for i in 3:
			await get_tree().process_frame
		# exercise the modal face pickers the run screens open
		if name in ["reward", "shop", "treasure"]:
			RunWidgets.pick_hero_face(inst, Game.run.team[0], "pick", "sp_heavy_blow",
					func(_slot: int) -> void: pass)
			await get_tree().process_frame
			RunWidgets.pick_team_face(inst, "pick", func(_hi: int, _slot: int) -> void: pass)
			await get_tree().process_frame
		# Game.goto side effects from screens are ignored (no Main here)
		inst.queue_free()
		await get_tree().process_frame

	# --- the reward screen's two relic paths. Both raise a blocking card, and
	# --- neither had a crawl until a boss started handing out a choice of two.
	for case in [{"extra_relics": ["N05"], "advanced": []},
			{"extra_relics": [], "advanced": ["A01", "A04"]},
			{"extra_relics": ["N08"], "advanced": ["A02", "A06"], "advanced_showcase": true}]:
		print("crawl: reward %s" % [case])
		Game.pending_reward = {
			"gold": 40, "kind": "boss", "xp_amount": 3, "xp_ups": {},
			"extra_relics": case.get("extra_relics", []),
			"advanced": case.get("advanced", []),
			"advanced_showcase": bool(case.get("advanced_showcase", false)),
			"offers": RunState.gen_offers(Game.run, rng, "boss", {}),
		}
		var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
		rw.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(rw)
		for i2 in 4:
			await get_tree().process_frame
		rw.queue_free()
		await get_tree().process_frame

	# --- and the relic list, from an empty pack and a full one
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	DetailCard.show_relic_list(host, [])
	await get_tree().process_frame
	DetailCard.show_relic_list(host, GameData.relics_of_rarity("common")
			+ GameData.relics_of_rarity("advanced"))
	await get_tree().process_frame
	# every relic's own card, which is also every relic glyph drawn once
	for rid in GameData.relics_of_rarity("common") + GameData.relics_of_rarity("advanced"):
		DetailCard.show_relic(host, String(rid))
	await get_tree().process_frame
	host.queue_free()
	await get_tree().process_frame

	if fails == 0:
		print("CRAWL OK")
	else:
		print("CRAWL FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
