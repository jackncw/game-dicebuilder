extends Node
## The data files and the code that reads them cannot drift apart silently.
##   godot --headless --path . res://tests/data_policy_test.gd
##
## Why this exists
## ---------------
## Twice now a face has reported zero uses across thousands of rolls and looked
## like a design failure when it was a MEASUREMENT failure:
##
##   · round 6, 豎棘 (thorns with no Block on it): `_score_die` had no branch
##     that matched it, so the greedy policy could never pick it up. 0/3491.
##   · round 7, 靜滯場 (a sweeping weaken, target "none") and 竊骰 (steal_die):
##     same hole, one target type over. Both were found by the zero-use audit
##     that now prints at the bottom of every balance report.
##
## The audit is the empirical half and it can only report what the harness
## happened to roll. This suite is the static half, and it is the one that goes
## red: every face in data/faces.json must match at least one key the policy
## actually branches on FOR ITS OWN TARGET TYPE, or be named in
## `SimRunner.POLICY_BLIND` with a reason. A new keyword added to the data with
## no policy branch fails here, on the commit that adds it, instead of quietly
## costing the next balance round its evidence.
##
## The same argument applies one tier up, so relics get it too: a relic whose
## `effect` string is read by nothing is a relic that does nothing, and the only
## place that shows up otherwise is a player wondering why their pickup did not
## work.

## Face keys that describe the face rather than doing anything — structure, not
## effect. Everything else must be a term the glossary knows.
const STRUCTURAL := ["zh", "en", "cat", "rarity", "target", "hero", "die", "id",
	"mod", "slot", "resonate_cat"]

## Where a relic's `effect` may be read. The whole of `scripts/`, not just the
## core: 森林圖 and 鐵匠信物 are read by the map and the shop screens, and a
## check that only knew about BattleCore would have called both of them dead.
const EFFECT_READERS := "res://scripts"

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	GameData.load_all()
	_t_face_policy_coverage()
	_t_policy_table_matches_source()
	_t_blind_list_is_still_needed()
	_t_face_keys_are_known_terms()
	_t_relic_effects_are_read()
	print("DATAPOLICY: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("DATAPOLICY OK")
	else:
		print("DATAPOLICY FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## `legal_targets`' type for a face, which is what `_score_die` matches on.
## "self" and anything unrecognised both come back as "none" there, so they do
## here too — that mapping IS the thing being tested against.
func _target_type(fd: Dictionary) -> String:
	match String(fd.get("target", "none")):
		"enemy": return "enemy"
		"enemy_die": return "enemy_die"
		"ally": return "ally"
		"wild": return "wild"
		_: return "none"


## The data files carry a top-level `_comment` string next to the real entries.
## It is documentation, not a face, and iterating it as one gets you one failure
## per character.
func _defs(table: Dictionary) -> Dictionary:
	var out := {}
	for k in table:
		if table[k] is Dictionary:
			out[String(k)] = table[k]
	return out


func _covered_by(fd: Dictionary) -> Array:
	var kind := _target_type(fd)
	var hits := []
	for k in SimRunner.POLICY_KEYS.get(kind, []):
		if fd.has(k):
			hits.append(String(k))
	return hits


# ============================================================ 1. every face is playable

func _t_face_policy_coverage() -> void:
	var faces := _defs(GameData.faces)
	var uncovered := []
	for fid in faces:
		var fd: Dictionary = faces[fid]
		if String(fid) == "blank" or fd.get("blank", false):
			continue   # the cursed-slot placeholder is not a face anybody plays
		if _covered_by(fd).is_empty():
			uncovered.append(String(fid))
	for fid2 in uncovered:
		var fd2: Dictionary = faces[fid2]
		_check(SimRunner.POLICY_BLIND.has(fid2),
				"%s (%s, target %s) matches no key the sim policy branches on. "
				% [fid2, String(fd2.get("zh", "")), String(fd2.get("target", "none"))]
				+ "Add a branch to SimRunner._score_die, or declare it in "
				+ "SimRunner.POLICY_BLIND with the reason.")
	print("policy coverage: %d faces, %d unplayable (%d declared)"
			% [faces.size(), uncovered.size(), SimRunner.POLICY_BLIND.size()])


# ============================================================ 2. the table is not stale

## `POLICY_KEYS` is a hand-written mirror of `_score_die`, and a mirror rots.
## Both directions are checked: a key declared but no longer branched on would
## let a real hole through test 1, and a key branched on but not declared makes
## the table a lie the next reader will trust.
func _t_policy_table_matches_source() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/core/sim_runner.gd")
	_check(src != "", "could not read sim_runner.gd to check the policy table")
	if src == "":
		return
	var body := _function_body(src, "_score_die")
	_check(body != "", "could not find _score_die's body in sim_runner.gd")
	if body == "":
		return
	var declared := {}
	for kind in SimRunner.POLICY_KEYS:
		for k in SimRunner.POLICY_KEYS[kind]:
			declared[String(k)] = true
			_check(body.contains("\"%s\"" % String(k)),
					"POLICY_KEYS declares \"%s\" under %s but _score_die never "
					% [String(k), String(kind)] + "mentions it — the table is stale")
	for q in SimRunner.POLICY_QUALIFIERS:
		declared[String(q)] = true
	for k2 in _keys_read_in(body):
		_check(declared.has(k2),
				"_score_die branches on \"%s\" but POLICY_KEYS does not declare "
				% k2 + "it — add it to the right target row (or to "
				+ "POLICY_QUALIFIERS if it only narrows a branch)")


## Every `fd.has("x")` / `fd.get("x", …)` in a chunk of source.
func _keys_read_in(body: String) -> Array:
	var out := {}
	var re := RegEx.new()
	re.compile("fd\\.(?:has|get)\\(\"([a-z_0-9]+)\"")
	for m in re.search_all(body):
		out[m.get_string(1)] = true
	return out.keys()


## The source of one `static func`, from its signature to the next top-level
## `func`/`const`/`static`. Crude, and it only has to hold for this one file.
func _function_body(src: String, fn: String) -> String:
	var at := src.find("func %s(" % fn)
	if at < 0:
		return ""
	var rest := src.substr(at)
	var stop := rest.length()
	for marker in ["\nstatic func ", "\nfunc ", "\nconst "]:
		var idx := rest.find(marker, 1)
		if idx > 0:
			stop = mini(stop, idx)
	return rest.substr(0, stop)


# ============================================================ 3. no rotting exemptions

func _t_blind_list_is_still_needed() -> void:
	var faces := _defs(GameData.faces)
	for fid in SimRunner.POLICY_BLIND:
		var id := String(fid)
		_check(faces.has(id),
				"POLICY_BLIND names %s, which is not a face any more — drop it" % id)
		if not faces.has(id):
			continue
		_check(_covered_by(faces[id]).is_empty(),
				"POLICY_BLIND still names %s, but the policy CAN play it now — " % id
				+ "delete the exemption so the coverage test guards it")
		_check(String(SimRunner.POLICY_BLIND[id]).length() > 40,
				"POLICY_BLIND[%s] needs a real reason, not a shrug" % id)


# ============================================================ 4. keywords are terms

## A key on a face that the glossary has never heard of is either a typo or a
## mechanic the player is never told about. Both are bugs; the second is worse.
func _t_face_keys_are_known_terms() -> void:
	var known := {}
	for k in Glossary.MAIN_ORDER:
		known[String(k)] = true
	for k2 in Glossary.MOD_ORDER:
		known[String(k2)] = true
	for k3 in Glossary.FLAG_KEYS:
		known[String(k3)] = true
	for k4 in STRUCTURAL:
		known[String(k4)] = true
	var unknown := {}
	var faces := _defs(GameData.faces)
	for fid in faces:
		for key in faces[fid]:
			if not known.has(String(key)):
				unknown[String(key)] = String(fid)
	for u in unknown:
		_check(false, "face key \"%s\" (on %s) is in no glossary key list — "
				% [u, String(unknown[u])] + "add it to Glossary.MAIN_ORDER / "
				+ "MOD_ORDER / FLAG_KEYS, or to this suite's STRUCTURAL")
	_check(true, "face keys checked against the glossary vocabulary")


# ============================================================ 5. relics do something

func _t_relic_effects_are_read() -> void:
	var src := _all_source(EFFECT_READERS)
	_check(src != "", "could not read the effect readers")
	var relics := _defs(GameData.relics)
	for rid in relics:
		var eff := String(relics[rid].get("effect", ""))
		_check(eff != "", "relic %s has no `effect` key" % String(rid))
		if eff == "":
			continue
		_check(src.contains("\"%s\"" % eff),
				"relic %s's effect \"%s\" is read by nothing under %s — the relic "
				% [String(rid), eff, EFFECT_READERS] + "does nothing at all")


## Every .gd file under `dir`, concatenated.
func _all_source(dir: String) -> String:
	var out := ""
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out += _all_source(full)
		elif name.get_extension() == "gd":
			out += FileAccess.get_file_as_string(full)
		name = d.get_next()
	d.list_dir_end()
	return out
