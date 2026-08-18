extends Node
## Screenshots of everything round 4 added, so the new surfaces get looked at
## rather than merely compiled: the Essence meter (shown and hidden), the relic
## strip, a relic acquisition card at both tiers, the relic list, the enemy
## forecast card, and the rebuilt reward screen.
##
## Needs a REAL window.
##   bash tools/round4_shots.sh

const BASE_W := 720
const BASE_H := 1280

var out_dir := "res://art_iterations/round4/"
var sub: SubViewport
var shots := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	GameData.load_all()
	Game.settings.lang_mode = "both"
	Game.settings.tutorial_done = true
	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.size = Vector2i(BASE_W, BASE_H)
	add_child(sub)
	await get_tree().process_frame

	await _battle_shots()
	await _reward_shots()
	print("ROUND4 SHOTS: DONE %d" % shots)
	get_tree().quit()


# ============================================================ battle surfaces

func _battle_shots() -> void:
	# --- a party that uses Essence, carrying a full relic strip
	var battle := await _battle(["HARE", "BADGER", "OWL", "HEDGE"], ["E01", "E07"], 2,
			GameData.relics_of_rarity("common") + GameData.relics_of_rarity("advanced"))
	await _grab("battle_essence_and_relics")

	# --- the enemy forecast card
	battle._show_enemy_card(0)
	await _settle()
	await _grab("enemy_forecast_minion")
	battle._hide_tooltip()
	await _settle()

	# --- the relic list, raised from the strip
	battle._tooltip = DetailCard.show_relic_list(battle, battle.bc.s.relics)
	await _settle()
	await _grab("relic_list")
	battle._hide_tooltip()
	await _settle()

	# --- a boss forecast, with its announced attack counting down
	var boss := await _battle(["HARE", "BADGER", "OWL", "HEDGE"], ["B1"], 1, ["N01"])
	boss.bc.s.heroes[3].taunt = true      # so the card can name a real target
	boss._refresh()
	await _settle()
	boss._show_enemy_card(0)
	await _settle()
	await _grab("enemy_forecast_boss")

	# --- and a party with no Essence faces at all: the meter must be gone
	var dry := await _battle(["HARE", "BADGER", "BOAR", "FOX"], ["E01", "E01"], 1, [])
	for i in dry.bc.s.heroes.size():
		for slot in 12:
			if dry.bc.s.heroes[i].faces[slot] in ["owl_gather2", "sp_channel"]:
				dry.bc.s.heroes[i].faces[slot] = "sp_lance"
	dry.essence_bar.visible = dry._party_uses_essence()
	dry._refresh()
	await _settle()
	await _grab("battle_no_essence_bar")


func _battle(team_ids: Array, enemies: Array, chapter: int, relics: Array) -> Control:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	var team := []
	for id in team_ids:
		team.append(GameData.new_hero(String(id)))
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": enemies,
			"opts": {"chapter": chapter, "relics": relics}, "battle_seed": 4242})
	battle.instant_anim = true
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(battle)
	sub.add_child(holder)
	await _settle()
	return battle


# ============================================================ reward surfaces

func _reward_shots() -> void:
	Game.run = RunState.new_run(["HARE", "BADGER", "OWL", "HEDGE"], 2468)
	Game.run.gold = 240
	Game.run.relics = ["N02", "N05"]
	var rng := RunState.rng_of(Game.run)

	# the common relic card, over the reward screen
	Game.pending_reward = {
		"gold": 26, "kind": "elite", "xp_amount": 2, "xp_ups": {},
		"extra_relics": ["N09"], "advanced": [], "advanced_showcase": false,
		"offers": RunState.gen_offers(Game.run, rng, "elite", {}),
	}
	await _mount_reward()
	await _grab("relic_card_common")

	# then the offer screen itself, with the roster strip — same screen with no
	# relic in the spoils, so nothing is covering it
	Game.pending_reward = {
		"gold": 18, "kind": "battle", "xp_amount": 1, "xp_ups": {},
		"extra_relics": [], "advanced": [], "advanced_showcase": false,
		"offers": RunState.gen_offers(Game.run, rng, "battle", {}),
	}
	await _mount_reward()
	await _grab("reward_offers_and_roster")

	# the boss 2-pick
	Game.pending_reward = {
		"gold": 60, "kind": "boss", "xp_amount": 3, "xp_ups": {},
		"extra_relics": [], "advanced": ["A01", "A02"], "advanced_showcase": false,
		"offers": RunState.gen_offers(Game.run, rng, "boss", {}),
	}
	await _mount_reward()
	await _grab("advanced_relic_pick")


func _mount_reward() -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.size = Vector2(BASE_W, BASE_H)
	var rw: Control = load("res://scripts/ui/screen_reward.gd").new()
	rw.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(rw)
	sub.add_child(holder)
	await _settle()


# ============================================================ plumbing

func _settle() -> void:
	for i in 8:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	sub.get_texture().get_image().save_png(
			ProjectSettings.globalize_path(out_dir + name + ".png"))
	shots += 1
	print("SHOT ", name)
