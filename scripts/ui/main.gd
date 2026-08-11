extends Node
## Root screen manager. Screens are Control-derived scripts under
## res://scripts/ui/screen_*.gd, switched via Game.goto(name, args).

var current: Control = null


func _ready() -> void:
	# headless balance simulator:  godot --headless ... -- --sim 100 [seed]
	var cmd := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	var all := cmd + user
	for i in all.size():
		if all[i] == "--sim":
			var n := 100
			var seed_v := 20260805
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				n = int(all[i + 1])
			if i + 2 < all.size() and all[i + 2].is_valid_int():
				seed_v = int(all[i + 2])
			print("running %d simulated runs…" % n)
			var report := SimRunner.batch(n, seed_v)
			SimRunner.print_report(report)
			get_tree().quit()
			return
		if all[i] == "--relics":
			var rn := 60
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				rn = int(all[i + 1])
			print("advanced relic spread: %d runs per relic per team…" % rn)
			SimRunner.print_relic_spread(rn)
			get_tree().quit()
			return
		if all[i] == "--chars":
			# per-character acceptance: nobody dominant, nobody dead weight
			var cn := 80
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				cn = int(all[i + 1])
			print("per-character table: 6 heroes x %d runs…" % cn)
			SimRunner.print_character_table(cn)
			get_tree().quit()
			return
		if all[i] == "--charge":
			# 蓄力 payoff audit: is banking a die worth the turns it costs?
			var gn := 150
			var gh := "HARE"
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				gn = int(all[i + 1])
			if i + 2 < all.size() and not all[i + 2].is_valid_int():
				gh = all[i + 2]
			print("charge audit: %s over %d runs…" % [gh, gn])
			SimRunner.print_charge_report(gn, gh)
			get_tree().quit()
			return
		if all[i] == "--faces":
			# which starting face is each hero not using? (round 6, task 3)
			var fn := 120
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				fn = int(all[i + 1])
			print("starting-face usage: 6 heroes x %d runs…" % fn)
			SimRunner.print_face_report(fn)
			get_tree().quit()
			return
		if all[i] == "--essence":
			# the Essence economy report — the evidence for round 6's
			# "make the resource present" goal (task 3)
			var en := 150
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				en = int(all[i + 1])
			print("essence economy: %d reference runs + solo runs per hero…" % en)
			SimRunner.print_essence_report(en)
			get_tree().quit()
			return
		if all[i] == "--commons":
			# which common relics are doing the least? (round 6, task 3)
			var cmn := 120
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				cmn = int(all[i + 1])
			print("common relic impact: %d runs each…" % cmn)
			SimRunner.print_common_impact(cmn)
			get_tree().quit()
			return
		if all[i] == "--balance":
			# the acceptance matrix: three seed sets against the spec targets,
			# judged on the median
			var runs := 150
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				runs = int(all[i + 1])
			print("balance matrix: 3 seed sets x %d runs…" % runs)
			SimRunner.print_matrix(runs)
			get_tree().quit()
			return
	Game.screen_change_requested.connect(_on_goto)
	Safe.apply_url_insets()
	var boot := Safe.boot_override()
	if boot != "":
		_boot_direct(boot)
		return
	Game.goto("menu")


## `--boot battle` / `?boot=battle`: open one screen with a canned setup instead
## of the menu. The web layout regression has to photograph the battle HUD, and
## clicking a whole run together through a canvas with no DOM in it would be
## testing the click path rather than the layout.
func _boot_direct(screen: String) -> void:
	GameData.load_all()
	match screen:
		"battle":
			var team := []
			for id in GameData.starter_hero_ids():
				team.append(GameData.new_hero(String(id)))
			Game.goto("battle", {"team": team, "enemies": ["E01", "E02", "E03"],
				"opts": {"chapter": 1}, "battle_seed": 91117})
		_:
			Game.goto(screen)


func _on_goto(screen: String, args: Dictionary) -> void:
	if is_instance_valid(current):
		current.queue_free()
	var path := "res://scripts/ui/screen_%s.gd" % screen
	if not ResourceLoader.exists(path):
		push_error("Unknown screen: " + screen)
		return
	var script: GDScript = load(path)
	current = script.new()
	current.set_anchors_preset(Control.PRESET_FULL_RECT)
	if current.has_method("setup"):
		current.setup(args)
	add_child(current)
