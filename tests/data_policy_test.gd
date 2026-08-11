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

## Faces that are allowed to have no way in, and why. This list is meant to
## stay one entry long — it is an escape hatch for faces that are not loot,
## not a parking space for faces nobody got round to wiring up.
const NO_PATH_OK := {
	"blank": "The cursed-slot placeholder. It is what a slot shows after a "
		+ "boss blanks it, so it is WRITTEN onto a die rather than acquired — "
		+ "an acquisition path for it would be a bug, not a fix.",
}

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
	_t_every_face_has_a_way_in()
	_t_policy_table_matches_source()
	_t_blind_list_is_still_needed()
	_t_face_keys_are_known_terms()
	_t_relic_effects_are_read()
	_t_score_lens_prices_every_face()
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


# ============================================================ 1b. every face has a way in

## A face nobody can obtain is dead data, and dead data does not read as dead:
## it shows up in the codex-adjacent lists, in comments, in tests, and in the
## zero-use audit as a face "nobody plays". Round 6 evicted 獾's 格擋4 and
## 野豬's 暴走 from the starting kits to make room for the Essence faces and
## left both entries in `faces.json`; they sat there unobtainable for two
## rounds, and round 7's audit only found them because it went looking. This is
## the check that would have caught them the same day.
##
## The four ways a face can reach a die:
##   · a hero's starting six on either die;
##   · a hero's XP unlock table;
##   · the shared drop pool (no `hero`, rarity C/R/E) — offers, shop, chests;
##   · named by an event.
func _t_every_face_has_a_way_in() -> void:
	var faces := _defs(GameData.faces)
	var paths := {}
	for hid in _defs(GameData.heroes):
		var hd: Dictionary = GameData.heroes[hid]
		for fid in Array(hd.get("start", [])) + Array(hd.get("start_b", [])):
			_note_path(paths, String(fid), "%s start" % hid)
		var unlocks: Dictionary = hd.get("unlocks", {})
		for lvl in unlocks:
			_note_path(paths, String(unlocks[lvl]), "%s L%s" % [hid, String(lvl)])
	# the shared pool, asked of the same function the drop tables ask
	for fid2 in GameData.shared_pool():
		_note_path(paths, String(fid2), "shared pool")
	# events: no event names a face today, but the path exists in principle and
	# a check that ignored it would go red the day one does
	var ev_src := FileAccess.get_file_as_string("res://data/events.json")
	for fid3 in faces:
		if ev_src.contains("\"%s\"" % String(fid3)):
			_note_path(paths, String(fid3), "event")
	var orphans := []
	for fid4 in faces:
		if not paths.has(String(fid4)):
			orphans.append(String(fid4))
	for o in orphans:
		var fd: Dictionary = faces[o]
		_check(NO_PATH_OK.has(o),
				"%s (%s %s, owner %s) has no way in: not in any start six, no XP "
				% [o, String(fd.get("zh", "")), String(fd.get("rarity", "")),
				String(fd.get("hero", "(shared)"))]
				+ "unlock, not in the shared pool, named by no event. Wire it up, "
				+ "delete it, or declare it in NO_PATH_OK with the reason.")
	# and the whitelist itself has to stay honest
	for w in NO_PATH_OK:
		_check(faces.has(String(w)),
				"NO_PATH_OK names %s, which is not a face any more — drop it" % String(w))
		_check(not paths.has(String(w)),
				"NO_PATH_OK still names %s, but it IS obtainable now — delete the "
				% String(w) + "exemption so the check guards it")
		_check(String(NO_PATH_OK[w]).length() > 40,
				"NO_PATH_OK[%s] needs a real reason, not a shrug" % String(w))
	print("acquisition paths: %d faces, %d with no way in (%d declared)"
			% [faces.size(), orphans.size(), NO_PATH_OK.size()])


func _note_path(paths: Dictionary, fid: String, where: String) -> void:
	var lst: Array = paths.get(fid, [])
	lst.append(where)
	paths[fid] = lst


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


# ============================================================ 6. the score lens has no silent zeros

## `--accept=score` decides offers with `SimRunner._face_points`, which is a
## second hand-written mirror of the face vocabulary and rots the same way
## `POLICY_KEYS` does — except worse, because its failure is silent: a keyword
## it has never heard of prices at zero, and a face carrying only that keyword
## becomes one the lens will always refuse and never explain. That is the exact
## shape of the bug this whole suite was written for, one tier over.
##
## So: every key on every face is either read by `_face_points` or declared in
## `SimRunner.LENS_UNPRICED` with a reason, and every face the policy CAN play
## prices above zero.
func _t_score_lens_prices_every_face() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/core/sim_runner.gd")
	var body := _function_body(src, "_face_points")
	_check(body != "", "could not find _face_points' body in sim_runner.gd")
	if body == "":
		return
	var priced := {}
	for k in _keys_read_in(body):
		priced[String(k)] = true
	var structural := {}
	for s in STRUCTURAL:
		structural[String(s)] = true
	var faces := _defs(GameData.faces)
	var seen := {}
	for fid in faces:
		for key in faces[fid]:
			var k2 := String(key)
			seen[k2] = true
			if structural.has(k2):
				continue
			_check(priced.has(k2) or SimRunner.LENS_UNPRICED.has(k2),
					"face key \"%s\" (on %s) is read by neither SimRunner._face_points "
					% [k2, String(fid)] + "nor declared in SimRunner.LENS_UNPRICED — "
					+ "the score lens silently prices it at 0")
	for u in SimRunner.LENS_UNPRICED:
		var uk := String(u)
		_check(seen.has(uk), "LENS_UNPRICED names \"%s\", which is on no face any "
				% uk + "more — drop it")
		_check(not priced.has(uk), "LENS_UNPRICED names \"%s\", but _face_points "
				% uk + "DOES read it now — delete the exemption")
		_check(String(SimRunner.LENS_UNPRICED[uk]).length() > 40,
				"LENS_UNPRICED[%s] needs a real reason, not a shrug" % uk)
	# and the other direction: a face the greedy policy can play has to be worth
	# something to the lens, or the lens will refuse a face the sim would use
	var zeros := []
	for fid2 in faces:
		if String(fid2) == "blank" or _covered_by(faces[fid2]).is_empty():
			continue     # unplayable by construction — zero is the correct price
		if SimRunner._face_points(String(fid2)) <= 0.0:
			zeros.append(String(fid2))
	for z in zeros:
		_check(false, "%s (%s) is playable by _score_die but prices at 0 under the "
				% [z, String(faces[z].get("zh", ""))]
				+ "score lens, so --accept=score can never take it")
	print("score lens: %d face keys, %d unpriced (declared), %d playable faces at 0"
			% [seen.size(), SimRunner.LENS_UNPRICED.size(), zeros.size()])


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
