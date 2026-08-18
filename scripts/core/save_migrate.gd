class_name SaveMigrate
extends RefCounted
## Carries a pre-overhaul save across the 2026-08-06 character replacement.
##
## All six playable characters were replaced at once. Their ids, their twelve
## starting faces and their XP-unlock pools all changed, so a save written
## before that date names nothing the game still knows about. Rather than wipe
## it — the XP in there is hours of play — every value is moved to whichever
## new character inherited that slot.
##
## The mapping is by MECHANICAL ROLE, not by species: the old fox (Vex) was the
## glass-cannon, so his progress went to the Boar, and the old thorn-shaman
## (Bramble) was the trickster, so hers went to the Fox.
##
##     H1 苔蛙遊俠 Moss     ranged        → HARE   野兔神射手
##     H2 墨羽武士 Kuro     balanced      → BADGER 獾斧衛士
##     H3 珊瑚法師 Lily     caster        → OWL    梟賢者
##     H4 燼靈     Ember    tank          → HEDGE  刺蝟盾衛
##     H5 骨面狐   Vex      glass-cannon  → BOAR   蠻豬破軍   (unlockable)
##     H6 荊棘貓巫 Bramble  trickster     → FOX    狐影雙刃   (unlockable)
##
## Role order and slot order agree here (H1…H6 → the six in roster order), so
## the slot-order fallback the brief asks for produces the same table.

## Bumped whenever a save needs work on load. 1 = pre-B-die, 2 = dual dice,
## 3 = the character overhaul, 4 = faces deleted from the data (round 8),
## 5 = the round-13 pool restructure (class pools + unlock batches).
const SAVE_VERSION := 5

## Round 13 retired most of the old universal pool. Everything a save could be
## holding maps to its nearest surviving universal face — a die keeps a face
## of the same shape rather than being reseated to a starting face, and a
## codex flag lands on the successor. 寧鬆勿緊:錯就錯在畀多咗,唔好收走。
const ROUND13_FACE_MAP := {
	"sp_heavy_blow": "sp_torch", "sp_quick_jab": "sp_venom_knife",
	"sp_armor_break": "sp_lance", "sp_keen": "sp_torch",
	"sp_cure": "sp_first_aid", "sp_whirl_blade": "sp_lance",
	"sp_viper_needle": "sp_venom_knife", "sp_flame_strike": "sp_torch",
	"sp_scatter": "sp_lance", "sp_twin_strike": "sp_lance",
	"sp_godpierce": "sp_annihilate", "sp_reaper": "sp_annihilate",
	"sp_plague": "sp_venom_knife", "sp_dragon_breath": "sp_torch",
	"sp_absolute_guard": "sp_great_wall", "sp_citadel": "sp_great_wall",
	"sp_aegis": "sp_great_wall", "sp_cleansing_shield": "sp_shield_wall",
	"sp_life_bloom": "sp_miracle", "sp_sap": "sp_insight",
	"sp_mark": "sp_insight", "sp_evil_eye": "sp_deep_channel",
	"sp_chaos": "sp_insight", "sp_seed_blade": "sp_lance",
	"sp_seed_shield": "sp_great_wall", "sp_stasis": "sp_deep_channel",
	"sp_arcane_blast": "sp_annihilate",
}

const HERO_MAP := {
	"H1": "HARE", "H2": "BADGER", "H3": "OWL",
	"H4": "HEDGE", "H5": "BOAR", "H6": "FOX",
}

## The retired roster, exactly as `heroes.json` held it before the overhaul.
## Kept here rather than read from data because the data is gone: this is the
## only surviving description of what an old save's face ids meant.
const OLD_START := {
	"H1": ["moss_arrow", "moss_arrow", "moss_twin", "moss_twin", "moss_roll", "moss_hawkeye"],
	"H2": ["kuro_slash", "kuro_slash", "kuro_wide", "kuro_iai", "kuro_guard", "kuro_zanshin"],
	"H3": ["lily_channel", "lily_channel", "lily_spark", "lily_touch", "lily_spring", "lily_bolt"],
	"H4": ["ember_bulwark", "ember_bulwark", "ember_vigil", "ember_bash", "ember_daze", "ember_dampen"],
	"H5": ["vex_rend", "vex_rend", "vex_rite", "vex_claw", "vex_hex", "vex_shield"],
	"H6": ["bram_sting", "bram_sting", "bram_guard", "bram_overgrowth", "bram_mend", "bram_spore"],
}
const OLD_START_B := {
	"H1": ["moss_pierce", "mossb_snare", "mossb_snap", "mossb_marker", "mossb_backstep", "moss_hawkeye"],
	"H2": ["kurob_swallow", "kurob_steel", "kurob_blood", "kurob_challenge", "kurob_meditate", "kurob_sidestep"],
	"H3": ["lily_channel", "lilyb_surge", "lily_touch", "lilyb_purify", "lilyb_ward", "lilyb_ripple"],
	"H4": ["emberb_cinder", "emberb_smolder", "emberb_ashwall", "ember_vigil", "ember_daze", "emberb_snuff"],
	"H5": ["vexb_devour", "vexb_stalk", "vexb_hemorrhage", "vexb_wail", "vexb_soulmark", "vexb_bonewall"],
	"H6": ["bramb_vine", "bramb_barb", "bramb_miasma", "bramb_thicket", "bramb_leaf", "bramb_ward"],
}
## The old XP pools in pool order (levels 2-5). The new pools hold six, so
## these land on the first four slots and the last two start unearned.
const OLD_UNLOCKS := {
	"H1": ["moss_pierce", "moss_rain", "moss_mark", "moss_volley"],
	"H2": ["kuro_swallow", "kuro_helm", "kuro_wave", "kuro_mushin"],
	"H3": ["lily_frost", "lily_fireball", "lily_ward", "lily_torrent"],
	"H4": ["ember_bramble", "ember_quell", "ember_nova", "ember_undying"],
	"H5": ["vex_drink", "vex_howl", "vex_flurry", "vex_feast"],
	"H6": ["bram_bloom", "bram_whip", "bram_renewal", "bram_elder"],
}

static var _face_map := {}


## Retired face id → the face that took its place, built once from the tables
## above against the live `heroes.json`. Starting faces map by slot, XP-pool
## faces by pool index.
##
## An old id has to resolve to exactly ONE successor, or a codex flag has
## nowhere to land, so first-write-wins. The pools are walked first because a
## handful of ids sat in both places (貫穿箭 was the Frog's B die AND his first
## unlock) and the pool entry is the one the player earned — that is the
## mapping the brief pins down, so it is the one that gets to win.
static func face_map() -> Dictionary:
	if not _face_map.is_empty():
		return _face_map
	GameData.load_all()
	for old_id in HERO_MAP:
		var new_id: String = HERO_MAP[old_id]
		var def: Dictionary = GameData.heroes.get(new_id, {})
		if def.is_empty():
			continue
		# batch-shaped since round 13: flatten the unlock table in batch order
		var pool := GameData.class_pool(new_id)
		_map_list(OLD_UNLOCKS[old_id], pool)
		_map_list(OLD_START[old_id], def.get("start", []))
		_map_list(OLD_START_B[old_id], def.get("start_b", []))
	return _face_map


static func _map_list(old_list: Array, new_list: Array) -> void:
	for i in old_list.size():
		if i >= new_list.size():
			return
		var k := String(old_list[i])
		if not _face_map.has(k):
			_face_map[k] = String(new_list[i])


## Remap one meta array of face ids through both migration tables, dropping
## anything that still resolves to nothing.
static func remap_face_list(meta: Dictionary, key: String) -> void:
	GameData.load_all()
	var out := []
	for f in meta.get(key, []):
		var fid := String(f)
		fid = String(ROUND13_FACE_MAP.get(fid, fid))
		fid = String(face_map().get(fid, fid))
		fid = String(ROUND13_FACE_MAP.get(fid, fid))
		if GameData.faces.has(fid) and fid not in out:
			out.append(fid)
	meta[key] = out


static func is_legacy_hero(id: String) -> bool:
	return HERO_MAP.has(id)


## True when this meta/run dict predates the overhaul and needs the work below.
static func needs_meta_migration(meta: Dictionary) -> bool:
	if int(meta.get("save_version", 0)) >= SAVE_VERSION:
		return false
	for k in meta.get("xp", {}):
		if is_legacy_hero(String(k)):
			return true
	for k2 in meta.get("unlocked_heroes", []):
		if is_legacy_hero(String(k2)):
			return true
	return false


## Move XP totals, hero unlocks and codex discovery onto the new cast.
## Idempotent: running it on an already-migrated dict changes nothing.
static func migrate_meta(meta: Dictionary) -> Dictionary:
	GameData.load_all()

	var xp: Dictionary = meta.get("xp", {})
	var new_xp := {}
	for id in GameData.hero_ids():
		new_xp[id] = 0
	for k in xp:
		var key := String(k)
		var target: String = String(HERO_MAP.get(key, key))
		if new_xp.has(target):
			# `+=`, not `=`: if a save somehow holds both the old and the new
			# key, the player keeps the total rather than the last one read.
			new_xp[target] = int(new_xp[target]) + int(xp[k])
	meta["xp"] = new_xp

	var unlocked := []
	for k2 in meta.get("unlocked_heroes", []):
		var t := String(HERO_MAP.get(String(k2), String(k2)))
		if t not in unlocked and t in new_xp:
			unlocked.append(t)
	if unlocked.is_empty():
		unlocked = GameData.starter_hero_ids()
	# Starters are never lockable, and a save that predates one of them would
	# otherwise leave the player short of a legal team.
	for st in GameData.starter_hero_ids():
		if st not in unlocked:
			unlocked.append(st)
	meta["unlocked_heroes"] = unlocked

	remap_face_list(meta, "used_face_ids")

	meta["save_version"] = SAVE_VERSION
	return meta


## Bring an in-progress run onto the new cast. Team ids are remapped and every
## die face is re-seated: a slot holding one of the retired hero faces takes
## whatever the new character has in that slot, while shared-pool faces the
## player bought or won are left exactly where they are — none of those ids
## were retired, and they are the part of a run the player chose.
##
## Returns false when the run cannot be salvaged, in which case the caller
## should drop it rather than load a broken team.
static func migrate_run(run: Dictionary) -> bool:
	GameData.load_all()
	if int(run.get("save_version", 0)) >= SAVE_VERSION:
		return true
	var team: Array = run.get("team", [])
	if team.is_empty():
		return false
	for h in team:
		var old_id := String(h.get("id", ""))
		if not is_legacy_hero(old_id):
			continue
		var new_id: String = HERO_MAP[old_id]
		var def: Dictionary = GameData.heroes.get(new_id, {})
		if def.is_empty():
			return false
		h["id"] = new_id
		var fresh: Array = def.start.duplicate()
		fresh.append_array(def.start_b.duplicate())
		var faces: Array = h.get("faces", [])
		while faces.size() < GameData.SLOTS:
			faces.append("blank")
		for i in GameData.SLOTS:
			var fid := String(faces[i])
			# a retired universal face first follows the round-13 successor map,
			# so a purchase keeps its shape instead of reverting to a start face
			fid = String(ROUND13_FACE_MAP.get(fid, fid))
			if GameData.faces.has(fid) and String(GameData.faces[fid].get("hero", "")) == "":
				faces[i] = fid    # a universal face: still valid, still theirs
				continue
			faces[i] = String(fresh[i])
		h["faces"] = faces
		# HP scales with the new character's constitution rather than dropping
		# the player to a stranger's max.
		var new_max := int(def.hp)
		var old_max: int = maxi(int(h.get("max_hp", new_max)), 1)
		var ratio := float(int(h.get("hp", new_max))) / float(old_max)
		h["max_hp"] = new_max
		h["hp"] = clampi(int(round(new_max * ratio)), 0, new_max)
	_reseat_deleted_faces(team)
	run["save_version"] = SAVE_VERSION
	return true


## Any die slot naming a face the data no longer has, re-seated to whatever that
## hero starts with in that slot.
##
## This is not about one deletion. `hero_face()` indexes `GameData.faces`
## directly, so a save holding a retired id is a hard runtime error the moment
## the player rolls that die — and saves live in the browser's IndexedDB, where
## nobody can go and fix them. Round 8 deleted 格擋4 and 暴走, both of which were
## STARTING faces on the build that was live until 2026-08-11, so this is not
## hypothetical: anyone mid-run with the Badger or the Boar has one of them on a
## die right now. Written as a general sweep so the next deletion is free.
static func _reseat_deleted_faces(team: Array) -> void:
	for h in team:
		var def: Dictionary = GameData.heroes.get(String(h.get("id", "")), {})
		if def.is_empty():
			continue
		var fresh: Array = def.start.duplicate()
		fresh.append_array(def.start_b.duplicate())
		var faces: Array = h.get("faces", [])
		while faces.size() < GameData.SLOTS:
			faces.append("blank")
		for i in GameData.SLOTS:
			var fid := String(faces[i])
			if fid == "blank" or GameData.faces.has(fid):
				continue
			# a retired universal face keeps its shape via the round-13 map;
			# only a face with no successor falls back to the starting slot
			var mapped := String(ROUND13_FACE_MAP.get(fid, ""))
			if mapped != "" and GameData.faces.has(mapped):
				faces[i] = mapped
			else:
				faces[i] = String(fresh[i]) if i < fresh.size() else "blank"
		h["faces"] = faces
