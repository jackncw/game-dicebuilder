extends Node
## 第十輪 mockup 自評截圖:390×664 / 360×640 手機幾何下嘅地圖(節點類型注釋
## + 捲動)同勝利畫面(升四級最壞情況 + 摺疊摘要)。SubViewport 以 DEVICE
## 像素 render、holder 以 canvas 單位 layout 再縮細 —— 出嚟嘅 PNG 就係手機
## 玻璃上眼見嘅大小,細字讀唔讀到一眼分曉。
##
## Needs a REAL window.
##   bash tools/round10_shots.sh

var out_dir := "res://art_iterations/round10/"
var sub: SubViewport
var shots := 0

const GEOMS := [
	{"name": "390x664", "w": 390, "h": 664},
	{"name": "360x640", "w": 360, "h": 640},
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	GameData.load_all()
	Game.settings.lang_mode = "both"
	Game.settings.tutorial_done = true
	for g in GEOMS:
		await _shoot_geom(g)
	Safe.force_canvas(Vector2.ZERO)
	Safe.force_insets(-1, 0, 0, 0)
	print("ROUND10 SHOTS: DONE %d" % shots)
	get_tree().quit()


func _shoot_geom(g: Dictionary) -> void:
	var dev_w := int(g.w)
	var dev_h := int(g.h)
	var canvas := Vector2(720.0, 720.0 * dev_h / dev_w)
	if is_instance_valid(sub):
		sub.queue_free()
		await get_tree().process_frame
	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.size = Vector2i(dev_w, dev_h)
	add_child(sub)
	Safe.force_canvas(canvas)
	Safe.force_insets(0, 0, 0, 0)
	await get_tree().process_frame

	# --- 地圖:run 開頭(可去節點喺梯底,要自動捲到底)
	Game.run = RunState.new_run(GameData.starter_hero_ids(), 4242)
	var map := await _mount("res://scripts/ui/screen_map.gd", canvas)
	await _grab("map_start_%s" % g.name)

	# --- 地圖:行到中段(第 4 行),可去節點應該喺視野中間
	Game.run.row = 3
	Game.run.col = 0
	map = await _mount("res://scripts/ui/screen_map.gd", canvas)
	await _grab("map_mid_%s" % g.name)

	# --- 勝利畫面:全隊四人升級 + 三張戰利品卡(最壞情況)
	Game.run = RunState.new_run(GameData.starter_hero_ids(), 4242)
	var rng := RunState.rng_of(Game.run)
	var ups := {}
	for id in GameData.starter_hero_ids():
		ups[String(id)] = 2
	Game.pending_reward = {
		"gold": 23, "kind": "battle", "xp_amount": 3, "xp_ups": ups,
		"extra_relics": [], "advanced": [], "advanced_showcase": false,
		"offers": RunState.gen_offers(Game.run, rng, "battle", {}),
	}
	var rw := await _mount("res://scripts/ui/screen_reward.gd", canvas)
	await _grab("reward_4ups_top_%s" % g.name)
	# 捲到底 —— assert 嘅嘢:三張戰利品卡完整可見
	var sc: Variant = rw.get("_scroll")
	if sc is ScrollContainer:
		sc.scroll_vertical = 9999
		await _settle()
		await _grab("reward_4ups_bottom_%s" % g.name)


func _mount(script_path: String, canvas: Vector2) -> Control:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = canvas
	holder.scale = Vector2.ONE * (float(sub.size.x) / canvas.x)
	var scr: Control = load(script_path).new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	if scr.has_method("setup"):
		scr.setup({})
	holder.add_child(scr)
	sub.add_child(holder)
	await _settle()
	return scr


func _settle() -> void:
	for i in 10:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	sub.get_texture().get_image().save_png(
			ProjectSettings.globalize_path(out_dir + name + ".png"))
	shots += 1
	print("SHOT ", name)
