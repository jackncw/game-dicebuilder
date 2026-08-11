extends Node
## Instantiates every screen headless with a live run to catch script errors.
##   godot --headless --path . res://tests/screens_crawl.tscn

var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


## Anything at least this tall is a full-screen scrim or a tap-anywhere catcher
## — those are SUPPOSED to run under the notch, and asserting on them would only
## teach the test to be ignored. Below it, a Button or a Label is a thing the
## player reads or presses, and it belongs on the visible glass.
const CATCHER_H := 700.0


## Every readable/pressable descendant of `root` whose rect leaves `safe`.
##
## The walk stops at a ScrollContainer. Its contents are meant to run off the
## end — that is what scrolling is — so the only question worth asking about a
## scrolling list is whether the CONTAINER is on the visible glass, and the
## container itself is checked on the way past.
func _outside(root: Control, safe: Rect2) -> Array:
	var out := []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Control = stack.pop_back()
		if not (n is ScrollContainer):
			for c in n.get_children():
				if c is Control:
					stack.append(c)
		if not (n is Button or n is Label or n is ScrollContainer):
			continue
		var r := n.get_global_rect()
		if r.size.y <= 0.5 or r.size.x <= 0.5 or r.size.y >= CATCHER_H:
			continue
		if not n.is_visible_in_tree():
			continue
		if not safe.encloses(r):
			out.append("%s%s" % [n.get_class(), r])
			if out.size() >= 4:
				return out
	return out


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

	# --- and the same crawl on a phone. `tests/layout_test.gd` covers the battle
	# --- screen band by band; this is the other twelve, and the question it asks
	# --- is the blunt one: is anything the player has to read or press outside
	# --- the part of the glass they can actually see?
	for prof in [{"n": "360x640 home screen", "t": 94.0, "b": 68.0},
			{"n": "390x664 home screen", "t": 91.0, "b": 66.0}]:
		Safe.force_insets(float(prof.t), 0.0, float(prof.b), 0.0)
		var safe := Rect2(0.0, float(prof.t), 720.0, 1280.0 - float(prof.t) - float(prof.b))
		for name2 in screens:
			var sc: GDScript = load("res://scripts/ui/screen_%s.gd" % name2)
			var it: Control = sc.new()
			it.set_anchors_preset(Control.PRESET_FULL_RECT)
			if it.has_method("setup"):
				it.setup({"stats": {"battles": 3}, "duration": 300})
			# Hosted in a holder of exactly the design canvas, the way
			# `layout_test` does it: parented straight to a Node, a screen anchors
			# to the OS WINDOW, and `expand` stretch makes that whatever size the
			# machine happened to open — every rect below would be measured
			# against a canvas the player never sees.
			var holder := Control.new()
			holder.position = Vector2.ZERO
			holder.size = Vector2(720, 1280)
			holder.custom_minimum_size = Vector2(720, 1280)
			add_child(holder)
			holder.add_child(it)
			for i3 in 3:
				await get_tree().process_frame
			var bad := _outside(it, safe)
			_check(bad.is_empty(), "%s / %s: %s outside the safe area %s"
					% [prof.n, name2, bad, safe])
			holder.queue_free()
			await get_tree().process_frame
	Safe.force_insets(-1.0, 0.0, 0.0, 0.0)

	if fails == 0:
		print("CRAWL OK")
	else:
		print("CRAWL FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
