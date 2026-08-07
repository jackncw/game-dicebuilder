class_name GameData
extends RefCounted
## Static loader for all JSON game data. Usable from autoloads, scenes and
## headless test/sim scripts alike (no scene tree dependency).

static var faces := {}
static var heroes := {}
static var enemies := {}
static var bosses := {}
static var encounters := {}
static var relics := {}
static var potions := {}
static var events := {}
static var balance := {}
static var strings := {}
## Every keyword / mechanic explanation. Single source — see `Glossary`.
static var glossary := {}
static var loaded := false


static func load_all() -> void:
	if loaded:
		return
	faces = _load_json("res://data/faces.json")
	heroes = _load_json("res://data/heroes.json")
	enemies = _load_json("res://data/enemies.json")
	bosses = _load_json("res://data/bosses.json")
	encounters = _load_json("res://data/encounters.json")
	relics = _load_json("res://data/relics.json")
	potions = _load_json("res://data/potions.json")
	events = _load_json("res://data/events.json")
	balance = _load_json("res://data/balance.json")
	strings = _load_json("res://data/strings.json")
	glossary = _load_json("res://data/glossary.json")
	loaded = true


static func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		push_error("GameData: bad JSON in %s" % path)
		return {}
	return parsed


## Every hero id in display order (`order` in heroes.json). Nothing enumerates
## the roster by hand: the cast has already been replaced wholesale once, and
## the hand-written `["H1","H2",…]` lists were the bulk of that day's work.
static func hero_ids() -> Array:
	load_all()
	var out: Array = heroes.keys()
	out = out.filter(func(k: String) -> bool: return not k.begins_with("_"))
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(heroes[a].get("order", 99)) < int(heroes[b].get("order", 99)))
	return out


## The ids a fresh save starts with unlocked (`starter: true`).
static func starter_hero_ids() -> Array:
	var out := []
	for id in hero_ids():
		if bool(heroes[id].get("starter", false)):
			out.append(id)
	return out


## The two that have to be earned.
static func unlockable_hero_ids() -> Array:
	var out := []
	for id in hero_ids():
		if not bool(heroes[id].get("starter", false)):
			out.append(id)
	return out


## Faces per die and dice per hero. Slot index is die_index * FACES_PER_DIE +
## face_index, so slots 0-5 are the A die and 6-11 the B die.
const FACES_PER_DIE := 6
const DICE_PER_HERO := 2
const SLOTS := 12


static func die_of_slot(slot: int) -> int:
	return int(slot) / FACES_PER_DIE


static func slot_range(die: int) -> Array:
	return range(die * FACES_PER_DIE, (die + 1) * FACES_PER_DIE)


## Fresh hero run-state dict for a level-1 hero (used by new runs and tests).
## `faces` holds 12 base ids; `face_plus` counts forge/event enchants (shown as
## a "+" suffix) while `face_mods` is the total numeric bonus (forge + growth).
static func new_hero(id: String, level := 1) -> Dictionary:
	var def: Dictionary = heroes[id]
	var faces: Array = def.start.duplicate()
	faces.append_array(def.start_b.duplicate())
	var mods := []
	var plus := []
	var extras := []
	for i in SLOTS:
		mods.append(0)
		plus.append(0)
		extras.append({})
	return {
		"id": id,
		"hp": int(def.hp), "max_hp": int(def.hp),
		"level": level,
		"faces": faces,
		"face_mods": mods,
		"face_plus": plus,
		"face_extras": extras,
	}


## Older saves / hand-built team dicts may predate the B die and face_plus.
## Pads them to the 12-slot shape in place and returns the same dict.
static func migrate_hero(h: Dictionary) -> Dictionary:
	var def: Dictionary = heroes[String(h.id)]
	var faces: Array = h.get("faces", [])
	if faces.size() < SLOTS:
		faces.append_array(def.start_b.duplicate())
		h["faces"] = faces
	for key in ["face_mods", "face_plus"]:
		var arr: Array = h.get(key, [])
		while arr.size() < SLOTS:
			arr.append(0)
		h[key] = arr
	var extras: Array = h.get("face_extras", [])
	while extras.size() < SLOTS:
		extras.append({})
	h["face_extras"] = extras
	return h


# ============================================================ relics
## Relics are looked up by what they DO, never by id. The relic list has been
## rewritten once already; every call site that hard-coded "R05" had to be
## found by hand that time, and the effect string is the thing the engine
## actually cares about.

## Value of the held relic with this effect, 0 when the party has none.
static func relic_value(relic_ids: Array, effect: String) -> int:
	for rid in relic_ids:
		var rd: Dictionary = relics.get(rid, {})
		if String(rd.get("effect", "")) == effect:
			return int(rd.get("value", 1))
	return 0


static func has_relic_effect(relic_ids: Array, effect: String) -> bool:
	for rid in relic_ids:
		if String(relics.get(rid, {}).get("effect", "")) == effect:
			return true
	return false


## All relic ids of one tier ("common" / "advanced"), sorted so a seeded draw
## is reproducible.
static func relics_of_rarity(rarity: String) -> Array:
	var out := []
	for rid in relics:
		if rid.begins_with("_"):
			continue
		if String(relics[rid].get("rarity", "common")) == rarity:
			out.append(rid)
	out.sort()
	return out


static func relic_rarity(rid: String) -> String:
	return String(relics.get(rid, {}).get("rarity", "common"))


## Every real face id. The data files carry a leading `_comment` explaining
## their own shape, and a loop that hands that string to code expecting a face
## dict fails in a way that is miserable to trace back — it surfaced as
## "the shop has one item" rather than as an error.
static func face_ids() -> Array:
	load_all()
	var out := []
	for id in faces:
		if not String(id).begins_with("_"):
			out.append(id)
	return out


## Shared-pool face ids filtered by rarity letter ("C"/"R"/"E").
static func shared_pool(rarity := "") -> Array:
	var out := []
	for id in face_ids():
		var fc: Dictionary = faces[id]
		if fc.get("hero", "") != "" and fc.has("hero"):
			continue
		var r: String = fc.get("rarity", "")
		if r in ["C", "R", "E"] and (rarity == "" or r == rarity):
			out.append(id)
	out.sort()
	return out
