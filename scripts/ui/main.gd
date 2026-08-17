extends Node
## Root screen manager. Screens are Control-derived scripts under
## res://scripts/ui/screen_*.gd, switched via Game.goto(name, args).

var current: Control = null

## Transition state: a dark leaf-toned cover that slides over the old screen,
## hides the swap (screen builds are the 133ms hitch — behind a static cover a
## long frame is invisible), then slides off the other side.
var _cover: ColorRect = null
var _transitioning := false
var _pending: Array = []   # [path, args] the in-flight transition should land on
const COVER_COLOR := Color(0.055, 0.085, 0.055)


func _ready() -> void:
	# headless balance simulator:  godot --headless ... -- --sim 100 [seed]
	var cmd := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	var all := cmd + user
	# `--accept=<mode>` is a MODIFIER, not a command: it changes how the sim
	# decides to take a face offer and then lets whichever report was asked for
	# run as normal (`--accept=score --levels 150 1,5,8`). Parsed in its own pass
	# so it works whatever order the flags arrive in.
	for a in all:
		if a.begins_with("--accept="):
			var mode := a.substr(len("--accept="))
			if mode in SimRunner.ACCEPT_MODES:
				SimRunner.accept_mode = mode
			else:
				print("unknown --accept mode \"%s\" — expected one of: %s"
						% [mode, ", ".join(SimRunner.ACCEPT_MODES)])
				get_tree().quit(1)
				return
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
		if all[i] == "--levels":
			# the unlock table on trial: same matrix at several party levels.
			#   --levels [n] [lvl,lvl,…]
			var ln := 150
			var lv := [1, 5, 8]
			if i + 1 < all.size() and all[i + 1].is_valid_int():
				ln = int(all[i + 1])
			if i + 2 < all.size() and all[i + 2].contains(","):
				lv = []
				for part in all[i + 2].split(","):
					if part.is_valid_int():
						lv.append(int(part))
			print("level sweep: %s x 3 seed sets x %d runs…" % [str(lv), ln])
			SimRunner.print_level_compare(ln, lv)
			SimRunner.print_unlock_usage(ln, int(lv[lv.size() - 1]))
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
		"map":
			# 任務4 的 Playwright 幾何迴歸:新 run 嘅第一章地圖(可去節點喺梯底)
			Game.run = RunState.new_run(GameData.starter_hero_ids(), 4242)
			Game.goto("map")
		"bossbattle":
			# 第十一輪:boss 登場演出嘅錄影通道
			var bteam := []
			for id3 in GameData.starter_hero_ids():
				bteam.append(GameData.new_hero(String(id3)))
			Game.goto("battle", {"team": bteam, "enemies": ["B1"],
				"opts": {"chapter": 1}, "battle_seed": 91117, "kind": "boss"})
		"treasure", "shop", "rest", "event":
			# 呢啲 screen 要有個 run 先企得住;canned run 就夠
			Game.run = RunState.new_run(GameData.starter_hero_ids(), 4242)
			Game.goto(screen)
		"victory":
			Game.goto("victory", {"stats": {"battles": 9, "elites": 2, "nodes": 14},
				"duration": 1234})
		"gameover":
			Game.goto("gameover", {"chapter": 2, "stats": {"battles": 5, "nodes": 7}})
		"reward":
			# 任務2 的最壞情況:全隊四人同一場升級,加三張戰利品卡
			Game.run = RunState.new_run(GameData.starter_hero_ids(), 4242)
			var rng := RunState.rng_of(Game.run)
			var ups := {}
			for id2 in GameData.starter_hero_ids():
				ups[String(id2)] = 2
			Game.pending_reward = {
				"gold": 23, "xp_amount": 3, "xp_ups": ups, "kind": "battle",
				"offers": RunState.gen_offers(Game.run, rng, "battle", {}),
				"extra_relics": [], "advanced": [], "advanced_showcase": false,
			}
			Game.goto("reward")
		_:
			Game.goto(screen)


func _on_goto(screen: String, args: Dictionary) -> void:
	_set_music(screen, args)
	var path := "res://scripts/ui/screen_%s.gd" % screen
	if not ResourceLoader.exists(path):
		push_error("Unknown screen: " + screen)
		return
	# Headless (every test suite) and the very first screen take the old
	# instant path — tests depend on the swap being synchronous.
	if DisplayServer.get_name() == "headless" or current == null:
		_swap(path, args)
		return
	# A goto arriving mid-transition (a tap slipping past a half-way cover)
	# retargets the transition instead of racing it.
	_pending = [path, args]
	if not _transitioning:
		_transition(_dir_for(screen))


func _swap(path: String, args: Dictionary) -> void:
	if is_instance_valid(current):
		current.queue_free()
	var script: GDScript = load(path)
	current = script.new()
	current.set_anchors_preset(Control.PRESET_FULL_RECT)
	if current.has_method("setup"):
		current.setup(args)
	add_child(current)


## Which way the cover travels. Forward motion enters from the right, going
## back exits left, and entering a fight is a faster top-down slam.
func _dir_for(screen: String) -> String:
	match screen:
		"battle":
			return "battle"
		"menu":
			return "pop"
	return "push"


func _transition(dir: String) -> void:
	_transitioning = true
	var vp := get_viewport().get_visible_rect().size
	if _cover == null:
		var layer := CanvasLayer.new()
		layer.layer = 95
		add_child(layer)
		_cover = ColorRect.new()
		_cover.color = COVER_COLOR
		_cover.mouse_filter = Control.MOUSE_FILTER_STOP  # eat taps mid-swap
		layer.add_child(_cover)
	_cover.size = vp
	_cover.visible = true
	var t_in := Fx.dur(0.10 if dir == "battle" else 0.13)
	var from := Vector2(vp.x, 0)
	var out_to := Vector2(-vp.x, 0)
	if dir == "pop":
		from = Vector2(-vp.x, 0)
		out_to = Vector2(vp.x, 0)
	elif dir == "battle":
		from = Vector2(0, -vp.y)
		out_to = Vector2(0, vp.y)
	_cover.position = from
	Sfx.play("swoosh", 0.8)
	var tw := create_tween()
	tw.tween_property(_cover, "position", Vector2.ZERO, t_in) 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	# fully covered: the expensive part happens where nobody can see a long
	# frame. Whatever goto was asked for LAST is the one that lands.
	while _pending.size() == 2:
		var target: Array = _pending
		_pending = []
		_swap(target[0], target[1])
		await get_tree().process_frame
		await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_cover, "position", out_to, t_in) 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await tw2.finished
	_cover.visible = false
	_transitioning = false
	# a goto that landed during the reveal still has to happen
	if _pending.size() == 2:
		var target: Array = _pending
		_pending = []
		_swap(target[0], target[1])


## The standing music policy, applied at every screen change. The one carve-out
## is a boss battle: the screen's own entrance sequence owns that switch, so the
## chapter track keeps playing under the black-out until the banner lands.
func _set_music(screen: String, args: Dictionary) -> void:
	if screen == "battle" and String(args.get("kind", "")) == "boss":
		return
	var chapter := 1
	if not Game.run.is_empty():
		chapter = int(Game.run.get("chapter", 1))
	elif screen == "battle":
		chapter = int((args.get("opts", {}) as Dictionary).get("chapter", 1))
	var track := Music.track_for(screen, chapter)
	if track != "":
		Music.play(track)
