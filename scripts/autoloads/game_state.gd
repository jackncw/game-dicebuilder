extends Node
## Autoload "Game": settings + meta progression + current run state.
## meta.json  — cross-run progress (XP, unlocks, stats)
## run.json   — in-progress run (saved at every completed node)

const META_PATH := "user://meta.json"
const RUN_PATH := "user://run.json"
const SETTINGS_PATH := "user://settings.json"

var settings := {
	"lang_mode": "both",   # both | zh | en
	"volume": 0.8,
	"tutorial_done": false,
	"fast_anim": false,    # dice throws squeezed to 0.3s, for repeat players
	"particles": true,     # ambient forest motes / leaves / spores
}

var meta := {
	"save_version": SaveMigrate.SAVE_VERSION,
	"xp": {},                     # filled from heroes.json in _ready
	"unlocked_heroes": [],
	"clears": 0,
	"runs": 0,
	"wins": 0,
	"fastest_clear_sec": 0,
	"pending_hero_pick": false,   # first clear: player picks one of the two locked heroes
	# --- codex discovery (recorded live during battle, kept even on defeat)
	"used_face_ids": [],          # base face ids the player has actually used
	"encountered_enemies": [],    # "E01:2" — minion id + tier met
	"encountered_bosses": [],     # "B1"
	"encountered_affixes": [],    # "frenzied" / "stoneskin" / "venomous"
}

var run := {}          # active run state (see RunState)
var screen_stack := [] # navigation handled by Main

signal screen_change_requested(name: String, args: Dictionary)


func _ready() -> void:
	GameData.load_all()
	_blank_meta_progress()
	load_settings()
	load_meta()


## The zeroed progress block, sized to whatever roster heroes.json describes.
func _blank_meta_progress() -> void:
	var xp := {}
	for id in GameData.hero_ids():
		xp[id] = 0
	meta.xp = xp
	meta.unlocked_heroes = GameData.starter_hero_ids()


# ------------------------------------------------------------ persistence

func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func save_settings() -> void:
	_save_json(SETTINGS_PATH, settings)


func load_settings() -> void:
	var d := _load_json(SETTINGS_PATH)
	for k in d:
		settings[k] = d[k]


func save_meta() -> void:
	_save_json(META_PATH, meta)


func load_meta() -> void:
	var d := _load_json(META_PATH)
	for k in d:
		meta[k] = d[k]
	# older meta.json predates the codex arrays
	for k2 in ["used_face_ids", "encountered_enemies", "encountered_bosses", "encountered_affixes"]:
		if not (meta.get(k2) is Array):
			meta[k2] = []
	# ...and older still predates the entire cast
	if SaveMigrate.needs_meta_migration(meta):
		var before := int(meta.xp.values().reduce(func(a, b): return int(a) + int(b), 0))
		SaveMigrate.migrate_meta(meta)
		var after := int(meta.xp.values().reduce(func(a, b): return int(a) + int(b), 0))
		print("Game: migrated meta to the new cast (%d XP carried, heroes: %s)"
				% [after, ", ".join(meta.unlocked_heroes)])
		assert(after == before, "SaveMigrate lost XP")
		save_meta()
	elif int(meta.get("save_version", 0)) < SaveMigrate.SAVE_VERSION:
		meta["save_version"] = SaveMigrate.SAVE_VERSION


# ------------------------------------------------------------ codex discovery

## Records a discovery in one of the meta arrays. Saves immediately so a
## defeat (or a killed app) never loses what the player just met.
func _discover(key: String, value: String) -> bool:
	if value == "":
		return false
	var arr: Array = meta[key]
	if value in arr:
		return false
	arr.append(value)
	save_meta()
	return true


## A face the player actually resolved in battle, keyed by base id — seeing it
## on any hero unlocks the codex entry everywhere.
func mark_face_used(base_id: String) -> void:
	_discover("used_face_ids", base_id)


func face_seen(base_id: String) -> bool:
	return base_id in meta.used_face_ids


func mark_enemy_met(key: String, tier: int) -> void:
	_discover("encountered_enemies", "%s:%d" % [key, tier])


func enemy_tier_seen(key: String, tier: int) -> bool:
	return ("%s:%d" % [key, tier]) in meta.encountered_enemies


func enemy_seen(key: String) -> bool:
	for t in [1, 2, 3]:
		if enemy_tier_seen(key, t):
			return true
	return false


func mark_boss_met(key: String) -> void:
	_discover("encountered_bosses", key)


func boss_seen(key: String) -> bool:
	return key in meta.encountered_bosses


func mark_affix_met(key: String) -> void:
	_discover("encountered_affixes", key)


func affix_seen(key: String) -> bool:
	return key in meta.encountered_affixes


func save_run() -> void:
	if run.is_empty():
		return
	_save_json(RUN_PATH, run)


func load_run() -> bool:
	var d := _load_json(RUN_PATH)
	if d.is_empty():
		return false
	if not SaveMigrate.migrate_run(d):
		push_warning("Game: in-progress run predates the character overhaul and could not be salvaged; dropping it")
		clear_run()
		return false
	run = d
	_normalize_run()
	return true


## JSON parses every number as float; re-int the fields used as indices.
func _normalize_run() -> void:
	for k in ["seed", "rng_state", "chapter", "row", "col", "gold",
			"run_atk_buff", "gold_pct", "pending_marsh"]:
		if run.has(k):
			run[k] = int(run[k])
	for h in run.team:
		for k2 in ["hp", "max_hp", "level"]:
			h[k2] = int(h[k2])
		GameData.migrate_hero(h)
		for arr_key in ["face_mods", "face_plus"]:
			var arr: Array = h[arr_key]
			for i in arr.size():
				arr[i] = int(arr[i])
	_migrate_relics()
	if run.has("battle") and run.battle is Dictionary and not run.battle.is_empty():
		run.battle.seed = int(run.battle.seed)
		run.battle.chapter = int(run.battle.get("chapter", run.chapter))
	for r in run.map.rows.size():
		for c in run.map.rows[r].size():
			var node: Dictionary = run.map.rows[r][c]
			var edges: Array = node.edges
			for i2 in edges.size():
				edges[i2] = int(edges[i2])


## Round 4 replaced all 18 relics with a new set of 20. A save from before that
## carries ids that no longer resolve, so each one is swapped for a random
## unheld relic of the same tier — the party keeps the same NUMBER of relics
## instead of quietly losing them mid-run. Seeded off the run seed so reloading
## the same save twice produces the same substitutes.
func _migrate_relics() -> void:
	var kept := []
	var lost := 0
	for rid in run.get("relics", []):
		if GameData.relics.has(rid) and not String(rid).begins_with("_"):
			kept.append(rid)
		else:
			lost += 1
	if lost > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(run.get("seed", 0)) + 977 * lost
		for k in lost:
			var sub := RunState.roll_relic({"relics": kept}, rng, "common")
			if sub == "":
				break
			kept.append(sub)
		print("Game: migrated %d retired relic(s) → %s" % [lost, kept])
	run["relics"] = kept


func has_saved_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


func clear_run() -> void:
	run = {}
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))


func reset_all_data() -> void:
	clear_run()
	if FileAccess.file_exists(META_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PATH))
	meta = {
		"save_version": SaveMigrate.SAVE_VERSION,
		"xp": {}, "unlocked_heroes": [],
		"clears": 0, "runs": 0, "wins": 0,
		"fastest_clear_sec": 0, "pending_hero_pick": false,
		"used_face_ids": [], "encountered_enemies": [],
		"encountered_bosses": [], "encountered_affixes": [],
	}
	_blank_meta_progress()
	settings.tutorial_done = false
	save_settings()


# ------------------------------------------------------------ meta helpers

func hero_level(id: String) -> int:
	var xp := int(meta.xp.get(id, 0))
	var lvl := 1
	var thresholds: Dictionary = GameData.balance.xp_levels
	# Driven off the table, not a hand-written level list: the XP pools grew
	# from four slots to six with the character overhaul and will move again.
	for l in thresholds.keys():
		if xp >= int(thresholds[l]) and int(l) > lvl:
			lvl = int(l)
	return lvl


## The highest level the XP curve defines.
func max_hero_level() -> int:
	var top := 1
	for l in GameData.balance.xp_levels.keys():
		top = maxi(top, int(l))
	return top


func grant_xp(hero_ids: Array, amount: int) -> Dictionary:
	## Returns {hero_id: [new_levels…]} for level-up notifications.
	var ups := {}
	for id in hero_ids:
		var before := hero_level(id)
		meta.xp[id] = int(meta.xp.get(id, 0)) + amount
		var after := hero_level(id)
		if after > before:
			ups[id] = range(before + 1, after + 1)
	save_meta()
	return ups


## Faces unlocked for a hero at its current meta level. The rule itself lives in
## GameData so the balance harness can ask it with a level of its own choosing —
## a simulator running a different unlock rule than the game is a simulator
## measuring a game nobody plays.
func unlocked_faces(id: String) -> Array:
	return GameData.unlocked_faces_at(id, hero_level(id))


# ------------------------------------------------------------ navigation

func goto(screen: String, args := {}) -> void:
	screen_change_requested.emit(screen, args)


# ============================================================ run flow

var pending_reward := {}   # set between battle end and reward screen


func start_new_run(team_ids: Array) -> void:
	var levels := {}
	for id in team_ids:
		levels[id] = hero_level(id)
	var seed_v := randi()
	run = RunState.new_run(team_ids, seed_v, levels)
	run.stats.start_msec = int(Time.get_unix_time_from_system())
	meta.runs = int(meta.runs) + 1
	save_meta()
	save_run()
	goto("map")


func continue_run() -> void:
	if not load_run():
		goto("menu")
		return
	# a battle was in progress: resume it from its stored seed so the enemy
	# line-up and every roll replay exactly (no save-scumming a bad turn)
	if _pending_battle():
		_goto_battle()
	else:
		goto("map")


func _pending_battle() -> bool:
	var b = run.get("battle", {})
	return b is Dictionary and not b.is_empty()


## Player taps an available map node.
func enter_node(r: int, c: int) -> void:
	run.skip_row = false
	run.row = r
	run.col = c
	var node: Dictionary = run.map.rows[r][c]
	match String(node.type):
		"battle":
			_start_battle(node.encounter.duplicate(), "battle", "")
		"elite":
			_start_battle([node.elite_key], "elite", String(node.affix))
		"boss":
			_start_battle([String(run.map.boss)], "boss", "")
		"shop":
			goto("shop")
		"rest":
			goto("rest")
		"treasure":
			goto("treasure")
		"event":
			goto("event")


## Locks in the encounter — line-up, options and a dedicated battle seed — and
## commits it to run.json *before* the first die is rolled. Everything random
## inside the battle comes from that seed, so quitting mid-fight and continuing
## replays the identical fight.
func _start_battle(enemy_keys: Array, kind: String, affix: String) -> void:
	var rng := RunState.rng_of(run)
	if run.pending_imp and kind == "battle":
		var enc_pool: Array = GameData.encounters[str(run.chapter)]
		var extra: Array = enc_pool[rng.randi_range(0, enc_pool.size() - 1)]
		enemy_keys.append(extra[0])
		enemy_keys = enemy_keys.slice(0, 4)
	var battle_seed := rng.randi()
	RunState.save_rng(run, rng)
	run["battle"] = {
		"seed": battle_seed,
		"enemies": enemy_keys,
		"kind": kind,
		"chapter": int(run.chapter),
		"elite": kind == "elite",
		"affix": affix,
		"marsh_poison": int(run.pending_marsh),
		"run_atk_buff": int(run.run_atk_buff),
	}
	run.pending_marsh = 0
	save_run()
	_goto_battle()


func _goto_battle() -> void:
	var b: Dictionary = run.battle
	goto("battle", {
		"team": run.team,
		"enemies": b.enemies.duplicate(),
		"opts": {
			"chapter": int(b.chapter),
			"elite": bool(b.elite),
			"affix": String(b.affix),
			"relics": run.relics,
			"potions": run.potions,
			"marsh_poison": int(b.marsh_poison),
			"run_atk_buff": int(b.run_atk_buff),
		},
		"kind": String(b.kind),
		"battle_seed": int(b.seed),
		"in_run": true,
		"tutorial": not bool(settings.tutorial_done),
	})


## Called by the battle screen when a run battle ends (bc = BattleCore).
func on_battle_finished(bc, kind: String) -> void:
	# the fight is settled — its seed must not resurrect it on continue
	run["battle"] = {}
	# post-battle randomness continues from the run rng, not the battle rng
	var rng := RunState.rng_of(run)
	if not bc.s.victory:
		clear_run()
		goto("gameover")
		return
	# sync team state back from battle
	for i in run.team.size():
		var h: Dictionary = run.team[i]
		var bh: Dictionary = bc.s.heroes[i]
		h.hp = 0 if bh.down else int(bh.hp)
		h.face_mods = bh.face_mods.duplicate()
	run.potions = bc.s.potions.duplicate()
	run.stats.battles = int(run.stats.battles) + 1
	if kind == "elite":
		run.stats.elites = int(run.stats.elites) + 1
	# --- spoils are settled (and shown) in one fixed order: gold → relics →
	# --- the three-face offer. ① gold + xp
	var gold := RunState.gold_for_battle(run, rng, kind)
	run.gold = int(run.gold) + gold
	var xp_amount := int(GameData.balance.xp_reward.get(kind, 1))
	var ids := []
	for h in run.team:
		ids.append(h.id)
	var ups := grant_xp(ids, xp_amount)
	# recovery
	RunState.post_battle_recovery(run)
	# ② relics. An elite always hands over a Common relic; the escorted imp
	# adds a second one; a boss offers a choice of two Advanced relics.
	var extra_relics := []
	if kind == "elite":
		extra_relics.append(RunState.roll_relic(run, rng, "common"))
	if run.pending_imp and kind == "battle":
		extra_relics.append(RunState.roll_relic(run, rng, "common"))
	run.pending_imp = false
	if run.get("pending_thief", false):
		run.gold = int(run.gold) + 40
		run["pending_thief"] = false
	for rid in extra_relics:
		if rid != "":
			add_relic(rid)
	var advanced := []
	var showcase := false
	if kind == "boss":
		advanced = RunState.roll_advanced_choice(run, rng,
				int(GameData.balance.boss_advanced_picks))
		# chapter 3's boss ends the run: the pick is shown so the player sees
		# what was on the table, but nothing is actually granted
		showcase = int(run.chapter) >= 3
	# ③ the three-face offer
	var unlocked := {}
	for h in run.team:
		unlocked[h.id] = unlocked_faces(h.id)
	var offers := RunState.gen_offers(run, rng, kind, unlocked)
	RunState.save_rng(run, rng)
	pending_reward = {
		"gold": gold, "offers": offers, "kind": kind,
		"xp_ups": ups, "extra_relics": extra_relics, "xp_amount": xp_amount,
		"advanced": advanced, "advanced_showcase": showcase,
	}
	goto("reward")


## Kept for the event screens that hand out "a relic" with no tier of their
## own — those are all Common-tier sources.
func _random_new_relic(rng: RandomNumberGenerator, rarity := "common") -> String:
	return RunState.roll_relic(run, rng, rarity)


func add_relic(rid: String) -> void:
	if rid == "" or rid in run.relics or not GameData.relics.has(rid):
		return
	run.relics.append(rid)
	var bonus_hp := int(GameData.relics[rid].get("value", 0)) 			if String(GameData.relics[rid].get("effect", "")) == "team_maxhp" else 0
	if bonus_hp > 0:
		for h in run.team:
			h.max_hp = int(h.max_hp) + bonus_hp
			if h.hp > 0:
				h.hp = int(h.hp) + bonus_hp


## Node fully resolved (reward taken / shop left / event done) → save + map.
func node_completed() -> void:
	run.stats.nodes = int(run.stats.nodes) + 1
	var node: Dictionary = run.map.rows[run.row][run.col]
	if String(node.type) == "boss":
		_on_chapter_cleared()
		return
	save_run()
	goto("map")


func _on_chapter_cleared() -> void:
	if int(run.chapter) < 3:
		run.chapter = int(run.chapter) + 1
		var rng := RunState.rng_of(run)
		run.map = RunState.gen_map(int(run.chapter), rng)
		RunState.save_rng(run, rng)
		run.row = -1
		run.col = -1
		save_run()
		goto("map")
		return
	# run complete!
	meta.wins = int(meta.wins) + 1
	var dur := int(Time.get_unix_time_from_system()) - int(run.stats.start_msec)
	if int(meta.fastest_clear_sec) == 0 or dur < int(meta.fastest_clear_sec):
		meta.fastest_clear_sec = dur
	var first_clear := int(meta.clears) == 0
	meta.clears = int(meta.clears) + 1
	if first_clear:
		meta.pending_hero_pick = true
	else:
		# the second clear hands over whichever of the two was not chosen
		for id in GameData.unlockable_hero_ids():
			if id not in meta.unlocked_heroes:
				meta.unlocked_heroes.append(id)
				break
	save_meta()
	var stats: Dictionary = run.stats.duplicate()
	clear_run()
	goto("victory", {"stats": stats, "duration": dur})
