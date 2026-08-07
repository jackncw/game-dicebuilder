extends Node
## art_export for 骰林 Dice Grove — screens are code-built Controls, so all
## shots are custom (instantiate screen scripts with args, mount, grab).

const OUTDIR := "res://art_export/"
const VW := 720
const VH := 1280
const TIMEOUT_S := 180.0

const SIMPLE_SCENES: Array = []


func _prepare_state() -> void:
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 13579)
	Game.run.gold = 180
	Game.run.potions = ["P01", "P04"]
	Game.run.relics = ["R03", "R14"]
	var rng := RunState.rng_of(Game.run)
	Game.pending_reward = {
		"gold": 16, "kind": "battle", "xp_amount": 1,
		"xp_ups": {"HARE": [2]}, "extra_relics": [],
		"offers": RunState.gen_offers(Game.run, rng, false, {}),
	}
	# a couple of forged faces so the "+" marks show up in the shots
	RunState.forge_face(Game.run.team[0], 0)
	RunState.forge_face(Game.run.team[0], 0)
	RunState.forge_face(Game.run.team[0], 7)
	RunState.save_rng(Game.run, rng)


func _custom_shots() -> void:
	# main menu
	var menu: Control = load("res://scripts/ui/screen_menu.gd").new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	await _mount(menu)
	await _grab("01_menu")

	# battle: fresh turn 1 (with potions)
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E01"],
			"opts": {"chapter": 1, "potions": ["P01", "P05"]}, "battle_seed": 20260805})
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	await _mount(battle)
	for i in 20:
		await get_tree().process_frame
	await _grab("02_battle_turn1")

	# select the first die with an attack face → target highlight + dmg preview
	var atk_i := -1
	for i in 4:
		var c: Dictionary = battle.bc.can_use(i, 0)
		if c.ok and c.face.has("atk"):
			atk_i = i
			break
	if atk_i >= 0:
		battle._on_die_pressed(atk_i, 0)
		for i in 5:
			await get_tree().process_frame
		await _grab("03_battle_target_preview")
		battle._deselect()

	# a die held mid-drag: legal targets lit, illegal dimmed, cast pad shown
	battle.bc.s.heroes[2].faces[6] = "sp_insight"
	battle.bc.s.heroes[2].rolled[1] = 6
	battle.bc.s.heroes[2].used = false
	battle._refresh()
	for i in 3:
		await get_tree().process_frame
	battle._on_drag_started(2, 1, Vector2(430, 700), -1)
	battle._on_drag_moved(Vector2(360, 470))
	for i in 5:
		await get_tree().process_frame
	await _grab("03b_battle_drag_cast")
	battle._on_drag_ended(Vector2(-100, -100))
	for i in 3:
		await get_tree().process_frame

	# tooltip
	battle._show_tooltip(Data.face_tooltip(battle.bc.die_face(0, 0)))
	for i in 5:
		await get_tree().process_frame
	await _grab("04_battle_tooltip")
	battle._hide_tooltip()

	# after an attack
	if atk_i >= 0:
		var lt: Dictionary = battle.bc.legal_targets(atk_i, 0)
		if lt.type == "enemy" and lt.indices.size() > 0:
			battle.bc.use_face(atk_i, 0, {"target": lt.indices[0]})
	battle._refresh()
	for i in 5:
		await get_tree().process_frame
	await _grab("05_battle_after_attack")

	# character gallery: all heroes / minions / bosses on one sheet
	var gallery := Control.new()
	gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gbg := ColorRect.new()
	gbg.color = Color("3a6b35")
	gbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gallery.add_child(gbg)
	var kinds := ["HARE", "BADGER", "OWL", "HEDGE", "BOAR", "FOX",
			"E01", "E02", "E03", "E04", "E05", "E06",
			"E07", "E08", "E09", "E10", "B1", "B2",
			"B3", "B3P2", "B4", "B5", "B6"]
	for i in kinds.size():
		var col_i := i % 4
		var row_i := i / 4
		var h := 150.0 if kinds[i].begins_with("B") else 120.0
		var pa := PawnArt.make(kinds[i], h)
		pa.position = Vector2(100 + col_i * 175, 190 + row_i * 210)
		gallery.add_child(pa)
		var lbl := Label.new()
		lbl.text = kinds[i]
		lbl.position = Vector2(80 + col_i * 175, 196 + row_i * 210)
		lbl.add_theme_font_size_override("font_size", 16)
		gallery.add_child(lbl)
	await _mount(gallery)
	for i in 6:
		await get_tree().process_frame
	await _grab("00_gallery")

	# tutorial overlay
	var tut: Control = load("res://scripts/ui/screen_battle.gd").new()
	tut.setup({"team": [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")],
			"enemies": ["E01", "E01"], "opts": {"chapter": 1},
			"battle_seed": 42, "tutorial": true})
	tut.set_anchors_preset(Control.PRESET_FULL_RECT)
	await _mount(tut)
	for i in 8:
		await get_tree().process_frame
	await _grab("13_tutorial")

	# run screens
	for shot in [["map", "06_map"], ["reward", "07_reward"], ["shop", "08_shop"],
			["event", "09_event"], ["charselect", "10_charselect"],
			["metaprogress", "11_meta"], ["settings", "12_settings"],
			["codex", "14_codex"]]:
		var scr: Control = load("res://scripts/ui/screen_%s.gd" % shot[0]).new()
		scr.set_anchors_preset(Control.PRESET_FULL_RECT)
		if scr.has_method("setup"):
			scr.setup({})
		await _mount(scr)
		for i in 6:
			await get_tree().process_frame
		await _grab(shot[1])

	# the face-replacement picker over the reward screen
	var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
	rw.set_anchors_preset(Control.PRESET_FULL_RECT)
	rw.setup({})
	await _mount(rw)
	for i in 4:
		await get_tree().process_frame
	RunWidgets.pick_hero_face(rw, Game.run.team[0], Data.t("ui_pick_replace"),
			"sp_great_blade", func(_slot: int) -> void: pass)
	for i in 6:
		await get_tree().process_frame
	await _grab("15_pick_replace")


func _galleries() -> void:
	pass

# ============================================================
# engine part (unchanged from template)
# ============================================================
var sub: SubViewport
var done := false

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func():
		if not done:
			push_warning("art_export timed out")
			get_tree().quit())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))

	await _prepare_state()

	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)

	await get_tree().process_frame
	for s in SIMPLE_SCENES:
		await _shoot_scene(s["path"], s["name"])
	await _custom_shots()
	_galleries()
	done = true
	print("ART_EXPORT: DONE")
	get_tree().quit()

func _save(img: Image, name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUTDIR) + name + ".png")
	print("EXPORT ", name, " ", img.get_size())

func _grab(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	_save(img, name)

func _mount(node: Node) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 4:
		await get_tree().process_frame

func _shoot_scene(path: String, name: String) -> void:
	var inst: Node = load(path).instantiate()
	await _mount(inst)
	await _grab(name)
