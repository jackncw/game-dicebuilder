extends Node
## Round 11: the corruption-dissolve death, on tape deterministically.
##
## The browser capture cannot guarantee a kill (it taps blind), so this shoots
## the moment directly: build a battle, mark one enemy dead the way the engine
## would, refresh, and photograph the ghost card dissolving frame by frame.
## Touching bc.s is fine HERE — the parity guard fences sim and UI, tools are
## the sanctioned séance.
##
## Needs a REAL window (frame_post_draw never fires headless):
##   bash tools/dissolve_shots.sh

const BASE_W := 720
const BASE_H := 1280

var out_dir := "res://art_iterations/round11/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	GameData.load_all()
	Game.settings.lang_mode = "both"
	var sub := SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.size = Vector2i(BASE_W, BASE_H)
	add_child(sub)
	await get_tree().process_frame

	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E02", "E03"],
			"opts": {"chapter": 1}, "battle_seed": 91117})
	battle.instant_anim = true
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(battle)
	sub.add_child(holder)
	for i in 8:
		await get_tree().process_frame

	# kill the middle enemy the way battle_core would leave it
	battle.bc.s.enemies[1].dead = true
	battle.bc.s.enemies[1].hp = 0
	battle._refresh()

	# ~0.7s of dissolve at 12 fps of stills
	for k in 9:
		for f in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := sub.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(out_dir + "dissolve_%02d.png" % k))
		print("SHOT dissolve_%02d" % k)
	print("DISSOLVE SHOTS: DONE")
	get_tree().quit()
