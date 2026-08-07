extends Node
## Boss-layout screenshot regression.
##
## `tests/layout_test.gd` proves the cast pad and the enemy cards never share a
## pixel. This is the other half of that: it shoots the same cases so a human
## can see that a boss still reads as the biggest thing on screen after being
## squeezed into the enemy band, rather than merely being legally sized.
##
## Needs a REAL window — the grab awaits RenderingServer.frame_post_draw, which
## never fires headless.
##   bash tools/boss_shots.sh 4

const BASE_W := 720
const BASE_H := 1280

var out_dir := "res://art_iterations/boss_layout/"
var sub: SubViewport
var shots := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = String(a[i + 1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	GameData.load_all()
	Game.settings.lang_mode = "both"
	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.size = Vector2i(BASE_W, BASE_H)
	add_child(sub)
	await get_tree().process_frame

	for key in ["B1", "B2", "B3", "B4", "B5", "B6"]:
		await _shot("boss_%s" % key, [key], int(GameData.bosses[key].chapter))
	await _shot("four_minions", ["E01", "E02", "E03", "E04"], 2)
	await _shot("boss_plus_pack", ["B4", "E01", "E02"], 2)
	print("BOSS SHOTS: DONE %d" % shots)
	get_tree().quit()


func _shot(name: String, enemies: Array, chapter: int) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": enemies,
			"opts": {"chapter": chapter, "relics": ["N01", "N02", "A01", "A02"]},
			"battle_seed": 91117})
	battle.instant_anim = true
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(battle)
	sub.add_child(holder)
	for i in 6:
		await get_tree().process_frame
	# the worst case is a loaded card: statuses, and a die in hand so every
	# enemy also carries its damage-preview chip
	for e in battle.bc.s.enemies:
		e.poison = 3
		e.block = 4
		e.thorns = 2
	battle.sel = _attack_die(battle)
	battle._refresh()
	for i2 in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_dir + name + ".png"))
	shots += 1
	print("SHOT ", name)


func _attack_die(battle: Control) -> Dictionary:
	for i in battle.bc.s.heroes.size():
		for d in BattleCore.DICE:
			var c: Dictionary = battle.bc.can_use(i, d)
			if c.ok and c.face.has("atk") and String(c.face.get("target", "")) == "enemy":
				return {"hero": i, "die": d}
	return {}
