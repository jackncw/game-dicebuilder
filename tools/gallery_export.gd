extends Node
## Gallery exporter — one command walks the whole game and shoots every screen
## and state on the art-review list, at two resolutions and (where it matters)
## in all three language modes.
##
##   Godot --path . --log-file art_export/gallery.log tools/gallery_export.tscn -- --iter 1
##
## Optional user args (after `--`):
##   --iter N        output folder art_iterations/iter_N   (default 1)
##   --only a,b,c    only shoot tags containing one of these substrings
##   --res 720|540   only one resolution (default both)
##   --out PATH      override the output folder entirely
##
## Must run with a real window: the grab awaits RenderingServer.frame_post_draw,
## which never fires headless.

const BASE_W := 720
const BASE_H := 1280
const RESOLUTIONS := [Vector2i(720, 1280), Vector2i(540, 960)]
const TIMEOUT_S := 1500.0

var out_dir := "res://art_iterations/iter_1/"
var only: Array = []
var res_filter := 0
var sub: SubViewport
var scale_f := 1.0
var res_tag := "720"
var done := false
var shot_count := 0


# ============================================================ entry

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		if not done:
			push_warning("gallery_export timed out after %d shots" % shot_count)
			get_tree().quit())
	_parse_args()
	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)

	for r in RESOLUTIONS:
		if res_filter > 0 and r.x != res_filter:
			continue
		res_tag = str(r.x)
		scale_f = float(r.x) / float(BASE_W)
		sub.size = r
		DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(out_dir + res_tag + "/"))
		await get_tree().process_frame
		await _all_shots()
	done = true
	print("GALLERY: DONE ", shot_count, " shots")
	get_tree().quit()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		match a[i]:
			"--iter":
				if i + 1 < a.size():
					out_dir = "res://art_iterations/iter_%s/" % a[i + 1]
			"--only":
				if i + 1 < a.size():
					only = String(a[i + 1]).split(",", false)
			"--res":
				if i + 1 < a.size():
					res_filter = int(a[i + 1])
			"--out":
				if i + 1 < a.size():
					out_dir = String(a[i + 1])


func _wanted(tag: String) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if tag.contains(String(o)):
			return true
	return false


# ============================================================ world state

## Meta progression posed so that every "unlocked vs locked" branch of the UI
## shows up somewhere in the gallery: 4 heroes unlocked (2 silhouettes), some
## enemies/bosses/affixes met and some still ???.
func _prepare_meta() -> void:
	# a save a few clears in: the four starters plus one earned unlock, so the
	# gallery shows both an unlocked card and a silhouette
	Game.meta.unlocked_heroes = GameData.starter_hero_ids()
	Game.meta.unlocked_heroes.append(GameData.unlockable_hero_ids()[0])
	Game.meta.xp = {}
	var seed_xp := [26, 12, 5, 0, 0, 0]
	for i in GameData.hero_ids().size():
		Game.meta.xp[GameData.hero_ids()[i]] = seed_xp[i] if i < seed_xp.size() else 0
	Game.meta.runs = 9
	Game.meta.wins = 3
	Game.meta.fastest_clear_sec = 1875
	Game.meta.pending_hero_pick = false
	Game.meta.encountered_enemies = ["E01:1", "E01:2", "E02:1", "E03:1", "E03:2",
			"E04:1", "E05:1", "E06:2", "E07:1"]
	Game.meta.encountered_bosses = ["B1", "B2", "B3"]
	Game.meta.encountered_affixes = ["frenzied", "stoneskin"]
	Game.meta.used_face_ids = ["bdg_chop3", "bdg_heavy4", "hare_pierce2",
			"hedge_guard4", "owl_starfall", "sp_great_blade", "sp_insight"]


func _prepare_run(chapter := 1) -> void:
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 13579)
	Game.run.gold = 186
	Game.run.potions = ["P01", "P04"]
	Game.run.relics = ["N02", "N11", "A01"]
	Game.run.chapter = chapter
	if chapter > 1:
		var rng0 := RunState.rng_of(Game.run)
		Game.run.map = RunState.gen_map(chapter, rng0)
		Game.run.row = -1
		Game.run.col = 0
		RunState.save_rng(Game.run, rng0)
	# a few nodes already walked so the map shows past / current / available
	Game.run.row = 2
	Game.run.col = 0
	# battle scars: not a full-health party
	Game.run.team[1].hp = int(Game.run.team[1].max_hp * 0.55)
	Game.run.team[2].hp = int(Game.run.team[2].max_hp * 0.35)
	var rng := RunState.rng_of(Game.run)
	Game.pending_reward = {
		"gold": 16, "kind": "battle", "xp_amount": 1,
		"xp_ups": {"HARE": [2]}, "extra_relics": [],
		"offers": RunState.gen_offers(Game.run, rng, "battle", {}),
	}
	RunState.forge_face(Game.run.team[0], 0)
	RunState.forge_face(Game.run.team[0], 0)
	RunState.forge_face(Game.run.team[0], 7)
	RunState.save_rng(Game.run, rng)


func _lang(mode: String) -> void:
	Game.settings.lang_mode = mode


# ============================================================ the shot list

func _all_shots() -> void:
	_prepare_meta()
	_prepare_run(1)
	_lang("both")

	await _shoot_screen("01_menu", "menu")
	# Character select carries six names, six passives and six unlock lines, so
	# it is shot in each language mode rather than only bilingual — that is
	# where the cast is actually proof-read.
	for cmode in ["both", "zh", "en"]:
		_lang(cmode)
		await _shoot_screen("02_charselect_%s" % cmode, "charselect")
	_lang("both")

	for ch in [1, 2, 3]:
		if _wanted("03_map_ch%d" % ch):
			_prepare_run(ch)
			await _shoot_screen("03_map_ch%d" % ch, "map")
	_prepare_run(1)

	# ---- battle, all three language modes
	for mode in ["both", "zh", "en"]:
		await _battle_shots(mode)

	# ---- bosses (chapter-correct backgrounds), bilingual
	_lang("both")
	await _boss_shots()

	# ---- run screens
	_prepare_run(2)
	# the offer screen is the other place a hero's portrait has to identify them
	for rmode in ["both", "zh", "en"]:
		_lang(rmode)
		await _shoot_screen("30_reward_%s" % rmode, "reward")
	_lang("both")
	await _shoot_pick_replace()
	await _shoot_screen("32_shop", "shop")
	await _shoot_screen("33_rest", "rest")
	await _shoot_screen("34_treasure", "treasure")
	await _shoot_event("35_event_a", 0)
	await _shoot_event("36_event_b", 3)

	# ---- codex, all three language modes
	for mode2 in ["both", "zh", "en"]:
		_lang(mode2)
		await _shoot_screen("40_codex_chars_%s" % mode2, "codex")
		await _shoot_codex_mobs("41_codex_mobs_%s" % mode2)
	_lang("both")

	await _shoot_screen("50_settings", "settings")
	await _shoot_screen("51_meta", "metaprogress")
	await _shoot_tutorial()
	await _shoot_screen("53_gameover", "gameover")
	await _shoot_victory()


# ---------------------------------------------------------- simple screens

func _shoot_screen(tag: String, script: String, args := {}, frames := 8) -> void:
	if not _wanted(tag):
		return
	var scr: Control = load("res://scripts/ui/screen_%s.gd" % script).new()
	if scr.has_method("setup"):
		scr.setup(args)
	await _mount(scr)
	for i in frames:
		await get_tree().process_frame
	await _grab(tag)


func _shoot_event(tag: String, skip: int) -> void:
	if not _wanted(tag):
		return
	# events pick from the unseen pool in sorted order, so seeding `seen_events`
	# is how we choose which layout gets shot
	var ids: Array = GameData.events.keys()
	ids.sort()
	Game.run["seen_events"] = ids.slice(0, skip)
	await _shoot_screen(tag, "event")


func _shoot_codex_mobs(tag: String) -> void:
	if not _wanted(tag):
		return
	var scr: Control = load("res://scripts/ui/screen_codex.gd").new()
	scr.setup({})
	await _mount(scr)
	scr.tab = "mobs"
	scr._build()
	for i in 8:
		await get_tree().process_frame
	await _grab(tag)


func _shoot_pick_replace() -> void:
	if not _wanted("31_pick_replace"):
		return
	var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
	rw.setup({})
	await _mount(rw)
	for i in 4:
		await get_tree().process_frame
	RunWidgets.pick_hero_face(rw, Game.run.team[0], Data.t("ui_pick_replace"),
			"sp_great_blade", func(_slot: int) -> void: pass)
	for i in 8:
		await get_tree().process_frame
	await _grab("31_pick_replace")


func _shoot_tutorial() -> void:
	if not _wanted("52_tutorial"):
		return
	var tut := _make_battle(["E01", "E01"], 1, true)
	await _mount(tut)
	for i in 10:
		await get_tree().process_frame
	await _grab("52_tutorial")


func _shoot_victory() -> void:
	if not _wanted("54_victory"):
		return
	Game.meta.pending_hero_pick = true
	await _shoot_screen("54_victory", "victory",
			{"stats": {"battles": 17}, "duration": 1934})
	Game.meta.pending_hero_pick = false


# ---------------------------------------------------------- battle states

func _make_battle(enemies: Array, chapter: int, tutorial := false) -> Control:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var b: Control = load("res://scripts/ui/screen_battle.gd").new()
	b.setup({"team": team, "enemies": enemies,
			"opts": {"chapter": chapter, "potions": ["P01", "P05"]},
			"battle_seed": 20260806, "tutorial": tutorial})
	return b


func _battle_shots(mode: String) -> void:
	_lang(mode)
	# --- turn start, all eight dice rolled
	if _wanted("10_battle_turn_%s" % mode):
		var b := _make_battle(["E01", "E03"], 1)
		await _mount(b)
		for i in 40:
			await get_tree().process_frame
		await _grab("10_battle_turn_%s" % mode)

	# --- a die in the air: ghost, legal targets lit, illegal dimmed
	if _wanted("11_battle_drag_%s" % mode):
		var b2 := _make_battle(["E01", "E03"], 1)
		await _mount(b2)
		for i in 20:
			await get_tree().process_frame
		var pick := _find_die(b2, "atk")
		if not pick.is_empty():
			# the screen positions its ghost in global space, which our holder
			# scales — feed it scaled points so the ghost lands where intended
			b2._on_drag_started(int(pick.hero), int(pick.die), Vector2(190, 700) * scale_f, -1)
			b2._on_drag_moved(Vector2(300, 300) * scale_f)
			for i in 6:
				await get_tree().process_frame
			await _grab("11_battle_drag_%s" % mode)
			b2._on_drag_ended(Vector2(-200, -200))

	# --- enemy turn resolving: floats in the air, lunges playing
	if _wanted("12_battle_enemy_%s" % mode):
		var b3 := _make_battle(["E01", "E03"], 1)
		await _mount(b3)
		for i in 20:
			await get_tree().process_frame
		b3._on_end_turn()
		for i in 8:
			await get_tree().process_frame
		await _grab("12_battle_enemy_%s" % mode)

	# --- proof shot for the floating-number fix: force a hero attack and a
	# --- guaranteed hit back, then grab while both numbers are still in the air
	if _wanted("14_battle_float_%s" % mode):
		var bf := _make_battle(["E01", "E03"], 1)
		await _mount(bf)
		for i in 20:
			await get_tree().process_frame
		var atk := _find_die(bf, "atk")
		if not atk.is_empty():
			bf._do_use(int(atk.hero), int(atk.die), {"target": 0})
			await get_tree().process_frame
		# and two landing on the same hero, pushed through the real event path
		# the enemy turn uses, so the shot also proves the stacking offset
		bf.bc.s.heroes[2].hp = maxi(int(bf.bc.s.heroes[2].hp) - 8, 1)
		bf.bc._ev({"t": "enemy_hit", "hero": 2, "enemy": 0, "dmg": 6, "blocked": 0})
		bf.bc._ev({"t": "enemy_hit", "hero": 2, "enemy": 1, "dmg": 2, "blocked": 0})
		bf._spawn_floats()
		# grab straight away: the float tween is wall-clock, and an export run
		# can take far longer than 60fps per frame
		await _grab("14_battle_float_%s" % mode)

	# --- status soup: poison + burn + thorns live on both sides at once
	if _wanted("13_battle_status_%s" % mode):
		var b4 := _make_battle(["E01", "E03"], 1)
		await _mount(b4)
		for i in 20:
			await get_tree().process_frame
		var st: Dictionary = b4.bc.s
		st.enemies[0].poison = 6
		st.enemies[0].burn = [4]
		st.enemies[0].thorns = 3
		st.enemies[0].weaken = 2
		st.enemies[0].block = 5
		st.enemies[1].poison = 3
		st.enemies[1].burn = [2, 2]
		st.enemies[1].expose = true
		st.heroes[0].poison = 4
		st.heroes[0].burn = [3]
		st.heroes[0].thorns = 4
		st.heroes[0].block = 7
		st.heroes[1].regen = 3
		st.heroes[1].thorns = 2
		st.heroes[1].taunt = true
		st.heroes[2].weaken = 2
		st.heroes[2].poison = 2
		st.heroes[3].hp = 0
		st.heroes[3].down = true
		b4._refresh()
		for i in 6:
			await get_tree().process_frame
		await _grab("13_battle_status_%s" % mode)


## First die of any hero whose rolled face carries `key`.
func _find_die(b: Control, key: String) -> Dictionary:
	for i in 4:
		for d in 2:
			var c: Dictionary = b.bc.can_use(i, d)
			if c.ok and c.face.has(key):
				return {"hero": i, "die": d}
	return {}


func _boss_shots() -> void:
	for key in ["B1", "B2", "B3", "B4", "B5", "B6"]:
		var chapter := int(GameData.bosses[key].chapter)
		var tag := "2%d_boss_%s" % [int(key.substr(1)), key]
		if _wanted(tag):
			var b := _make_battle([key], chapter)
			await _mount(b)
			for i in 30:
				await get_tree().process_frame
			await _grab(tag)
	# B3 dismounts into its second phase on the first kill
	if _wanted("23b_boss_B3_phase2"):
		var b3 := _make_battle(["B3"], int(GameData.bosses.B3.chapter))
		await _mount(b3)
		for i in 20:
			await get_tree().process_frame
		b3.bc._kill_enemy(0)
		b3.bc.end_turn()
		b3._refresh()
		for i in 10:
			await get_tree().process_frame
		await _grab("23b_boss_B3_phase2")


# ============================================================ engine

func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(out_dir + res_tag + "/") + name + ".png"
	img.save_png(path)
	shot_count += 1
	print("SHOT ", res_tag, "/", name)


func _grab(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(sub.get_texture().get_image(), name)


## Screens are authored against a 720x1280 canvas; a smaller device gets the
## same canvas scaled down (project stretch mode is canvas_items/expand and both
## targets are 9:16), so the shot is what the player actually sees.
func _mount(node: Control) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	holder.scale = Vector2(scale_f, scale_f)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(node)
	sub.add_child(holder)
	for i in 5:
		await get_tree().process_frame
