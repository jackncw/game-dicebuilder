extends Node
## Screenshots for the three play-test fixes — menu toy dice, portraits on offer
## cards, and the long-press card. Same mount/grab rig as `gallery_export.gd`,
## but posed for these three and, crucially, timed: half the point is proving
## the 3D die is on screen the frame the card opens, which no still of a settled
## screen can show.
##
##   Godot --path . --log-file art_export/fb.log tools/fb_shots.tscn -- --out res://final/fb/
##
## Needs a real window: the grab awaits RenderingServer.frame_post_draw.

const BASE_W := 720
const BASE_H := 1280

var out_dir := "res://final/fb/"
var sub: SubViewport
var shot_count := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = String(a[i + 1])
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		push_warning("fb_shots timed out after %d shots" % shot_count)
		get_tree().quit())

	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.size = Vector2i(BASE_W, BASE_H)
	add_child(sub)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Game.settings.lang_mode = "both"
	_prepare_run()
	await get_tree().process_frame

	await _menu_shots()
	await _offer_shots()
	await _detail_shots()

	print("FB SHOTS: DONE ", shot_count)
	get_tree().quit()


# ============================================================ 1 — menu dice

## Parked, mid-flick and settled again. The third shot is the regression: the
## die used to freeze one frame before its final pose, or never render at all.
func _menu_shots() -> void:
	var scr: Control = load("res://scripts/ui/screen_menu.gd").new()
	scr.setup({})
	await _mount(scr)
	for i in 10:
		await get_tree().process_frame
	await _grab("01_menu_parked")

	var dice := _dice_of(scr)
	print("menu dice found: ", dice.size())
	for d in dice:
		_flick(d, Vector2(26, -9))
	for i in 6:
		await get_tree().process_frame
	await _grab("02_menu_spinning")
	# long enough for the coast, the ease back upright and the two pumped frames
	for i in 600:
		await get_tree().process_frame
	await _grab("03_menu_settled")
	for d in dice:
		print("settled: still processing=%s, viewport=%s" % [d.is_processing(),
				"asleep" if d._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED
				else "LIVE"])


## The gesture the finger makes: press, a run of motion events, release. Feeding
## `_gui_input` directly keeps the shot honest — it is the same entry point a
## real touch lands on.
func _flick(d: Control, step: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = d.size * 0.5
	d._gui_input(down)
	for k in 4:
		var mv := InputEventMouseMotion.new()
		mv.position = d.size * 0.5 + step * float(k + 1)
		mv.relative = step
		d._gui_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = d.size * 0.5 + step * 4.0
	d._gui_input(up)


func _dice_of(root: Node) -> Array:
	var out := []
	for c in root.get_children():
		if c is Die3D:
			out.append(c)
		out.append_array(_dice_of(c))
	return out


# ============================================================ 2 — offer cards

func _offer_shots() -> void:
	for spec in [["10_reward", "reward"], ["11_shop", "shop"], ["12_treasure", "treasure"]]:
		var scr: Control = load("res://scripts/ui/screen_%s.gd" % spec[1]).new()
		scr.setup({})
		await _mount(scr)
		for i in 10:
			await get_tree().process_frame
		await _grab(String(spec[0]))

	# and one in each single-language mode, because the name under the portrait
	# is the part that has to survive a language switch
	for mode in ["zh", "en"]:
		Game.settings.lang_mode = mode
		var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
		rw.setup({})
		await _mount(rw)
		for i in 10:
			await get_tree().process_frame
		await _grab("13_reward_%s" % mode)
	Game.settings.lang_mode = "both"


# ============================================================ 3 — detail card

func _detail_shots() -> void:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var b: Control = load("res://scripts/ui/screen_battle.gd").new()
	b.setup({"team": team, "enemies": ["E01", "E03"],
			"opts": {"chapter": 1, "potions": ["P01", "P05"]}, "battle_seed": 20260806})
	await _mount(b)
	for i in 40:
		await get_tree().process_frame

	# the bug: long-press the die and the top of the card is a grey square until
	# you poke it. Shot as early as the rig can grab, then again once settled.
	b._on_die_long_pressed(0, 0)
	for i in 4:
		await get_tree().process_frame
	await _grab("20_detail_open_early")
	for i in 20:
		await get_tree().process_frame
	await _grab("21_detail_open_settled")

	# the same widget in the face-swap screen, which is the other place a die is
	# built before it enters the tree
	var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
	rw.setup({})
	await _mount(rw)
	for i in 6:
		await get_tree().process_frame
	RunWidgets.pick_hero_face(rw, Game.run.team[0], Data.t("ui_pick_replace"),
			"sp_great_blade", func(_slot: int) -> void: pass)
	for i in 10:
		await get_tree().process_frame
	await _grab("22_faceswap")

	# the other two shapes of the same card — a single face (codex, face swap)
	# and a single term (battle status chips). Both grew the close button too.
	var cx: Control = load("res://scripts/ui/screen_codex.gd").new()
	cx.setup({})
	await _mount(cx)
	for i in 6:
		await get_tree().process_frame
	var fd: Dictionary = GameData.faces["hare_pierce3"].duplicate()
	fd["id"] = "hare_pierce3"
	DetailCard.show_face(cx, fd)
	for i in 6:
		await get_tree().process_frame
	await _grab("23_detail_face")
	DetailCard.show_term(cx, "poison", ["burn"])
	for i in 6:
		await get_tree().process_frame
	await _grab("24_detail_term")


# ============================================================ rig

func _prepare_run() -> void:
	Game.meta.unlocked_heroes = ["HARE", "BADGER", "OWL", "HEDGE"]
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 13579)
	Game.run.gold = 186
	Game.run.potions = ["P01", "P04"]
	Game.run.relics = ["R03", "R14"]
	Game.run.chapter = 2
	Game.run.row = 2
	Game.run.col = 0
	var rng := RunState.rng_of(Game.run)
	Game.pending_reward = {
		"gold": 16, "kind": "battle", "xp_amount": 1,
		"xp_ups": {"HARE": [2]}, "extra_relics": [],
		"offers": RunState.gen_offers(Game.run, rng, false, {}),
	}
	RunState.save_rng(Game.run, rng)


func _mount(node: Control) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(node)
	sub.add_child(holder)
	for i in 5:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(out_dir) + name + ".png"
	sub.get_texture().get_image().save_png(path)
	shot_count += 1
	print("SHOT ", name)
