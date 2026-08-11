class_name SimRunner
extends RefCounted
## Headless run simulator: plays whole runs through RunState + BattleCore with
## a greedy policy (kill > disable big threats > damage > block vs expected
## damage > heal the wounded). Used for Phase 3+ flow verification and the
## Phase 6 balance harness.


## Simulate one full run. Returns:
## {win, died_chapter, battles, turns_total, avg_turns, dmg_taken, secs? }
## `opts.force_advanced` grants that Advanced relic at every boss instead of
## letting the policy choose. Only the distribution report uses it: rating the
## picks (which is what a player does) and then measuring win rate per relic
## measures the rating, not the relic. Forcing one removes that bias.
static func simulate_run(team_ids: Array, seed_v: int, meta_levels := {}, stop_after_chapter := 3, opts := {}) -> Dictionary:
	GameData.load_all()
	var run := RunState.new_run(team_ids, seed_v, meta_levels)
	var rng := RunState.rng_of(run)
	# `--commons`: hand the party this relic from the first fight, so the number
	# that comes back is the relic's and not the drop table's
	var forced_common := String(opts.get("force_common", ""))
	if forced_common != "":
		_add_relic(run, forced_common)
	var out := {
		"win": false, "died_chapter": 0, "died_at": "", "battles": 0,
		"turns_total": 0, "dmg_taken": 0, "nodes": 0,
		"chapter_reached": 1, "chapters_cleared": 0,
	}
	var guard := 0
	while guard < 200:
		guard += 1
		var avail := RunState.available_nodes(run)
		run.skip_row = false
		if avail.is_empty():
			break
		var pick: Array = avail[rng.randi_range(0, avail.size() - 1)]
		run.row = pick[0]
		run.col = pick[1]
		var node: Dictionary = run.map.rows[pick[0]][pick[1]]
		out.nodes += 1
		var node_type := String(node.type)
		var battle_res := {}
		match node_type:
			"battle":
				battle_res = _do_battle(run, rng, node.encounter.duplicate(), "battle", "", out, opts)
			"elite":
				battle_res = _do_battle(run, rng, [node.elite_key], "elite", String(node.affix), out, opts)
			"boss":
				battle_res = _do_battle(run, rng, [String(run.map.boss)], "boss", "", out, opts)
			"shop":
				_do_shop(run, rng)
			"rest":
				_do_rest(run)
			"treasure":
				_do_treasure(run, rng)
			"event":
				_do_event(run, rng, out)
		if battle_res.get("defeat", false):
			out.died_chapter = int(run.chapter)
			out.died_at = node_type
			out["relics"] = run.relics.duplicate()
			return out
		if node_type == "boss":
			out.chapters_cleared = int(run.chapter)
			if int(run.chapter) >= stop_after_chapter:
				out.win = true
				out["relics"] = run.relics.duplicate()
				return out
			run.chapter = int(run.chapter) + 1
			out.chapter_reached = int(run.chapter)
			run.map = RunState.gen_map(int(run.chapter), rng)
			run.row = -1
			run.col = -1
	out["relics"] = run.relics.duplicate()
	return out


## Batch report used by the --sim CLI and balance harness.
static func batch(n: int, base_seed := 20260805, team := [], opts := {}) -> Dictionary:
	if team.is_empty():
		team = GameData.starter_hero_ids()
	var r := {
		"n": n, "seed": base_seed, "wins": 0, "ch1": 0, "ch2": 0,
		"battles": 0, "turns": 0, "dmg": 0,
		"deaths": {},     # "ch<n>:<node type>" → count
		"advanced": {},   # relic id → {picks, wins} for the pick-rate report
		"relic_runs": {}, # relic id → runs that ended holding it (zero-use audit)
	}
	for i in n:
		var res := simulate_run(team, base_seed + i * 7919, {}, 3, opts)
		if res.win:
			r.wins += 1
		if int(res.chapters_cleared) >= 1:
			r.ch1 += 1
		if int(res.chapters_cleared) >= 2:
			r.ch2 += 1
		r.battles += int(res.battles)
		r.turns += int(res.turns_total)
		r.dmg += int(res.dmg_taken)
		if not res.win:
			var key := "ch%d:%s" % [int(res.died_chapter), String(res.died_at)]
			r.deaths[key] = int(r.deaths.get(key, 0)) + 1
		# every relic the run was still carrying when it ended — a relic that
		# turns up in no run at all is a drop-table bug, not a weak relic
		for held_v in res.get("relics", []):
			var held := String(held_v)
			r.relic_runs[held] = int(r.relic_runs.get(held, 0)) + 1
		# an Advanced relic is only ever picked once per boss, so a run's list is
		# the set of build axes it actually committed to
		for rid_v in res.get("advanced", []):
			var rid := String(rid_v)
			var row: Dictionary = r.advanced.get(rid, {"picks": 0, "wins": 0})
			row.picks = int(row.picks) + 1
			if res.win:
				row.wins = int(row.wins) + 1
			r.advanced[rid] = row
	return r


static func print_report(r: Dictionary) -> void:
	var n := int(r.n)
	print("=== SIM REPORT (%d runs, seed %d) ===" % [n, int(r.get("seed", 0))])
	print("ch1 clear: %d%%   ch2 clear: %d%%   full clear: %d%%" % [
			int(round(100.0 * r.ch1 / n)), int(round(100.0 * r.ch2 / n)),
			int(round(100.0 * r.wins / n))])
	if int(r.battles) > 0:
		print("avg battle turns: %.2f   avg dmg taken/battle: %.1f" % [
				float(r.turns) / r.battles, float(r.dmg) / r.battles])
	print("deaths by node:")
	var keys: Array = r.deaths.keys()
	keys.sort()
	for k in keys:
		print("  %s: %d" % [k, int(r.deaths[k])])
	print_advanced(r)


## Win rate per Advanced relic. The point of the tier is that each one carries
## a different build, so a relic sitting far off the pack in either direction
## is a number that needs changing rather than a lucky seed.
static func print_advanced(r: Dictionary) -> void:
	var adv: Dictionary = r.get("advanced", {})
	if adv.is_empty():
		return
	print("advanced relic pick → win rate:")
	var ids: Array = adv.keys()
	ids.sort()
	for rid in ids:
		var row: Dictionary = adv[rid]
		var picks := int(row.picks)
		var nm := String(GameData.relics.get(rid, {}).get("zh", rid))
		print("  %s %-6s picked %3d   win %3d  (%d%%)" % [rid, nm, picks,
				int(row.wins), int(round(100.0 * row.wins / maxi(picks, 1)))])


## Win rate with each Advanced relic FORCED at every boss, so the number is the
## relic's rather than the picking policy's. Two parties: the default one, and
## one built around Bramble and Vex — A02 (thorns) and A03 (lifesteal) are
## carried by those two, and the default party would never show what they are
## worth.
##   godot --headless --path . -- --relics [n]
static func print_relic_spread(n := 60, seed_v := 5150) -> void:
	var teams := {
		"starters": GameData.starter_hero_ids(),
		"HEDGE BOAR OWL FOX": ["HEDGE", "BOAR", "OWL", "FOX"],
	}
	for tname in teams:
		print("=== ADVANCED RELIC WIN RATE, forced, party %s (%d runs each) ===" % [tname, n])
		var base := batch(n, seed_v, teams[tname])
		print("  (policy pick)  win %3d  (%d%%)" % [int(base.wins),
				int(round(100.0 * base.wins / n))])
		for rid in GameData.relics_of_rarity("advanced"):
			var r := batch(n, seed_v, teams[tname], {"force_advanced": rid})
			print("  %s %-6s win %3d  (%d%%)" % [rid,
					String(GameData.relics[rid].zh), int(r.wins),
					int(round(100.0 * r.wins / n))])
		print("")


## Per-character acceptance: is anybody carrying the game, and is anybody dead
## weight?
##
## Two readings, because neither alone is honest. "solo" is a party of four
## copies of the one character — symmetric, so the six numbers are directly
## comparable, but it flatters self-sufficient characters and punishes
## specialists. "swap" puts the character into the reference party in place of
## whoever is not them, which is what a player actually does, but it can only
## be read as a difference from the reference row.
##   godot --headless --path . -- --chars [n]
static func print_character_table(n := 80, seed_v := 20260805) -> Array:
	var cast: Array = GameData.hero_ids()
	var reference: Array = GameData.starter_hero_ids()
	var base := batch(n, seed_v, reference)
	var base_win := int(round(100.0 * base.wins / n))
	print("=== PER-CHARACTER WIN RATE (%d runs each) ===" % n)
	print("reference party %s: ch1 %d%%  ch2 %d%%  win %d%%"
			% ["+".join(PackedStringArray(reference)),
			int(round(100.0 * base.ch1 / n)), int(round(100.0 * base.ch2 / n)), base_win])
	print("%-8s %5s %5s %5s   %7s %7s" % ["hero", "ch1", "ch2", "solo", "w/out", "misses"])
	var rows := []
	for h in cast:
		var solo := [h, h, h, h]
		var r := batch(n, seed_v, solo)
		# leave-one-out: the party you would field if this character did not
		# exist. A hero whose absence costs nothing is replaceable; one whose
		# absence collapses the run is carrying it.
		var without := []
		for other in cast:
			if other != h and without.size() < 4:
				without.append(other)
		var rs := batch(n, seed_v, without)
		var without_win := int(round(100.0 * rs.wins / n))
		var row := {
			"hero": h,
			"ch1": int(round(100.0 * r.ch1 / n)),
			"ch2": int(round(100.0 * r.ch2 / n)),
			"solo": int(round(100.0 * r.wins / n)),
			"without": without_win,
			"delta": base_win - without_win,
		}
		rows.append(row)
		print("%-8s %4d%% %4d%% %4d%%   %5d%% %+6d" % [h, row.ch1, row.ch2,
				row.solo, row.without, row.delta])
	var lo := 100
	var hi := 0
	for row2 in rows:
		lo = mini(lo, int(row2.solo))
		hi = maxi(hi, int(row2.solo))
	print("solo spread: %d%% … %d%%  (%d points)" % [lo, hi, hi - lo])
	return rows


## The acceptance seed sets. THREE of them, not two: a single seed reads ±5 on
## this harness and two seeds give you no way to tell which one is the outlier.
## The median of three is what the target bands are judged against.
const ACCEPT_SEEDS := [20260805, 987654, 424242]

## How close to a band edge still counts as "unresolved at n=150". One HP of a
## hero moves the full-clear rate about 5 points and two seed sets of an
## unchanged build differ by 2-6, so a reading within this many points of an
## edge has not actually decided anything — rerun at n=300.
const BAND_EDGE_MARGIN := 3

## The run size at which this harness has spent everything it can: three seed
## sets of 300 is 900 runs, and the seed-to-seed spread stops shrinking there.
## An edge reading at this size is a fact about the build, not about the sample.
const ACCEPT_N_FULL := 300

## Target bands, in the order they are printed.
const TARGET_BANDS := [
	{"label": "ch1 clear", "key": "ch1", "lo": 85, "hi": 92},
	{"label": "ch2 clear", "key": "ch2", "lo": 62, "hi": 72},
	{"label": "full clear", "key": "wins", "lo": 30, "hi": 45},
]


## Median of an Array of ints. Odd count in practice (three seeds), but the
## even case is defined so a caller passing four seeds does not get a surprise.
static func _median(vals: Array) -> float:
	var v := vals.duplicate()
	v.sort()
	var m: int = v.size() / 2
	if v.size() % 2 == 1:
		return float(v[m])
	return (float(v[m - 1]) + float(v[m])) / 2.0


## The acceptance run: three independent seed sets, `n` runs each, printed side
## by side against the spec targets, judged on the MEDIAN. This is what
## BALANCE.md's table is cut from.
##
## The zero-use audit at the bottom is not optional and not a separate command,
## because the one time it mattered it was found by accident: 豎棘 reported
## 0/3491 uses and it took a person noticing to tell "the policy has no branch
## for this face" apart from "this face is bad". Anything the harness never
## plays is a number BALANCE.md is quoting without evidence, so the report now
## says so itself.
##   godot --headless --path . -- --balance [n]
static func print_matrix(n := 150, seeds := ACCEPT_SEEDS, team := []) -> Array:
	if team.is_empty():
		team = GameData.starter_hero_ids()
	var reports := []
	# the audit rides along on the acceptance runs rather than costing its own
	# batch — these are the very runs the shipped numbers come from
	face_tel_begin()
	for sd in seeds:
		var r := batch(n, int(sd), team)
		reports.append(r)
		print_report(r)
		print("")
	print("=== TARGETS vs RESULT (%d seeds x %d runs, judged on median) ===" % [
			seeds.size(), n])
	var header := "%-20s" % "metric"
	for sd2 in seeds:
		header += "  %6d" % int(sd2)
	header += "  %7s  %s" % ["median", "verdict"]
	print(header)
	var needs_rerun := false
	for band in TARGET_BANDS:
		var label := "%s %d-%d%%" % [band.label, band.lo, band.hi]
		var line := "%-20s" % label
		var vals := []
		for rep in reports:
			var pct := int(round(100.0 * int(rep[band.key]) / n))
			vals.append(pct)
			line += "  %5d%%" % pct
		var med := _median(vals)
		var verdict := ""
		if med < float(band.lo):
			verdict = "UNDER by %.1f" % (float(band.lo) - med)
		elif med > float(band.hi):
			verdict = "OVER by %.1f" % (med - float(band.hi))
		else:
			verdict = "in band"
			var edge: float = minf(med - float(band.lo), float(band.hi) - med)
			if edge <= float(BAND_EDGE_MARGIN):
				# At n=300 the advice to "rerun at n=300" is the report arguing
				# with itself. Past that size the edge is not a sampling problem
				# you can spend your way out of — it is where the number lives.
				if n >= ACCEPT_N_FULL:
					verdict += " (edge, %.1fpt — at the resolution floor)" % edge
				else:
					verdict += " (edge, %.1fpt — rerun at n=%d)" % [edge, ACCEPT_N_FULL]
					needs_rerun = true
		print("%s  %6.1f%%  %s" % [line, med, verdict])
	var turns_line := "%-20s" % "avg turns 4-6"
	var turn_vals := []
	for rep2 in reports:
		var t := float(rep2.turns) / maxi(int(rep2.battles), 1)
		turn_vals.append(t)
		turns_line += "  %6.2f" % t
	turn_vals.sort()
	turns_line += "  %6.2f" % turn_vals[turn_vals.size() / 2]
	print(turns_line)
	if needs_rerun:
		print("")
		print("!! at least one median sits within %dpt of a band edge — that is "
				% BAND_EDGE_MARGIN + "inside this harness's noise. Rerun: --balance %d"
				% ACCEPT_N_FULL)
	# and the Advanced tier, pooled across both seed sets
	var pooled := {"advanced": {}}
	for rep3 in reports:
		for rid in rep3.advanced:
			var row2: Dictionary = pooled.advanced.get(rid, {"picks": 0, "wins": 0})
			row2.picks = int(row2.picks) + int(rep3.advanced[rid].picks)
			row2.wins = int(row2.wins) + int(rep3.advanced[rid].wins)
			pooled.advanced[rid] = row2
	print("")
	print("=== ADVANCED RELICS, all seed sets pooled ===")
	print_advanced(pooled)
	var face_t: Dictionary = face_tel.duplicate(true)
	face_tel_end()
	print_zero_use_audit(reports, face_t, n * seeds.size(), team)
	return reports


# ============================================================ zero-use audit
##
## What the harness NEVER played. Two readings, because a zero means two very
## different things depending on which column it sits in:
##
##   · a face that was rolled and never spent is either a bad face or a hole in
##     `_score_die` — the policy cannot pick up what it has no branch for, and
##     that failure looks exactly like a dead design;
##   · a face that was never even ROLLED never reached a die: it is out of the
##     drop pools this party can draw from, which is a data question, not a
##     design one;
##   · a relic held by no run is the same drop-table question, one tier up.
##
## Nothing here fails the build. It is a list of things that have to be
## EXPLAINED in BALANCE.md — the standing rule since round 6 is that an unused
## thing counts as understood only once somebody has written down which of the
## three it is. `tests/data_policy_test.gd` is the half of this that CAN fail:
## it checks statically that every face kind has a policy branch at all.

## At or below this share of its rolls actually being spent, a face is reported.
const AUDIT_DEAD_PCT := 0.5


static func print_zero_use_audit(reports: Array, face_t: Dictionary, runs: int,
		team := []) -> void:
	GameData.load_all()
	print("")
	print("=== ZERO-USE AUDIT (%d runs) — anything the harness never played ===" % runs)
	print("threshold: a face spent on %.1f%% or fewer of the turns it was rolled;" % AUDIT_DEAD_PCT)
	print("           a relic carried by %.1f%% or fewer of the runs." % AUDIT_DEAD_PCT)
	print("Every line below needs a written explanation in BALANCE.md before the")
	print("numbers in this report count as read — see round 6's 豎棘 (0/3491, a")
	print("missing policy branch rather than a dead face).")
	# --- faces: fold the per-hero/per-slot telemetry down to one row per face id
	var rolled := {}
	var used := {}
	for k in face_t.get("rolled", {}):
		var fid := String(k).split("|")[2]
		rolled[fid] = int(rolled.get(fid, 0)) + int(face_t.rolled[k])
	for k2 in face_t.get("used", {}):
		var fid2 := String(k2).split("|")[2]
		used[fid2] = int(used.get(fid2, 0)) + int(face_t.used[k2])
	var dead := []
	var never := []
	var face_ids: Array = GameData.faces.keys()
	face_ids.sort()
	for fid_v in face_ids:
		var fid3 := String(fid_v)
		# `_comment` is a String sitting next to the real entries in the JSON
		if fid3 == "blank" or not (GameData.faces[fid3] is Dictionary):
			continue   # the cursed-slot placeholder; it is not a face you play
		var rl := int(rolled.get(fid3, 0))
		if rl == 0:
			never.append(fid3)
			continue
		var us := int(used.get(fid3, 0))
		var rate := 100.0 * float(us) / float(rl)
		if rate <= AUDIT_DEAD_PCT:
			dead.append({"id": fid3, "rolled": rl, "used": us, "rate": rate})
	print("")
	print("--- faces rolled but (near enough) never spent: %d ---" % dead.size())
	if dead.is_empty():
		print("  (none)")
	for row in dead:
		var f: Dictionary = GameData.faces.get(String(row.id), {})
		print("  %-22s %-10s rolled %6d  used %5d  %5.2f%%" % [String(row.id),
				String(f.get("zh", "")), int(row.rolled), int(row.used), float(row.rate)])
	# Never-rolled faces split in two, because only one half is a question.
	# A face belonging to a hero who was not in the party could not possibly be
	# rolled — listing those individually would bury the ones that matter under
	# forty expected zeros. In scope: the shared pool, and the party's own
	# heroes' faces.
	var in_scope := []
	var off_party := {}
	for fid4 in never:
		var owner := String(GameData.faces[fid4].get("hero", ""))
		if owner != "" and owner not in team:
			off_party[owner] = int(off_party.get(owner, 0)) + 1
		else:
			in_scope.append(fid4)
	print("")
	print("--- faces never rolled at all, party %s: %d in scope ---"
			% ["+".join(PackedStringArray(team)), in_scope.size()])
	if in_scope.is_empty():
		print("  (none — every shared-pool and party face reached a die)")
	for fid5 in in_scope:
		var f2: Dictionary = GameData.faces[fid5]
		print("  %-22s %-10s %-6s owner %s" % [fid5, String(f2.get("zh", "")),
				String(f2.get("rarity", "")), String(f2.get("hero", "(shared)"))])
	if not off_party.is_empty():
		var owners: Array = off_party.keys()
		owners.sort()
		var parts := []
		for ow in owners:
			parts.append("%s %d" % [String(ow), int(off_party[ow])])
		print("  (plus %s faces belonging to heroes outside this party — expected)"
				% ", ".join(PackedStringArray(parts)))
	# --- relics
	var held := {}
	for rep in reports:
		for rid in rep.get("relic_runs", {}):
			held[rid] = int(held.get(rid, 0)) + int(rep.relic_runs[rid])
	print("")
	print("--- relics, share of runs that ended holding one ---")
	print("%-5s %-12s %8s %8s" % ["id", "name", "runs", "share"])
	var rids: Array = GameData.relics.keys()
	rids.sort()
	var cold := []
	for rid2_v in rids:
		var rid2 := String(rid2_v)
		if not (GameData.relics[rid2] is Dictionary):
			continue
		var h := int(held.get(rid2, 0))
		var share := 100.0 * float(h) / maxf(float(runs), 1.0)
		print("%-5s %-12s %8d %7.2f%%" % [rid2,
				String(GameData.relics[rid2].get("zh", "")), h, share])
		if share <= AUDIT_DEAD_PCT:
			cold.append(rid2)
	if cold.is_empty():
		print("  → every relic reached at least one party. No entries to explain.")
	else:
		print("  → EXPLAIN: %s" % ", ".join(PackedStringArray(cold)))


# ============================================================ battle

static func _do_battle(run: Dictionary, rng: RandomNumberGenerator, enemy_keys: Array,
		kind: String, affix: String, out: Dictionary, sim_opts := {}) -> Dictionary:
	if run.pending_imp and kind == "battle":
		var enc_pool: Array = GameData.encounters[str(run.chapter)]
		var extra: Array = enc_pool[rng.randi_range(0, enc_pool.size() - 1)]
		enemy_keys.append(extra[0])
		enemy_keys = enemy_keys.slice(0, 4)
	var opts := {
		"chapter": int(run.chapter), "elite": kind == "elite", "affix": affix,
		"relics": run.relics, "potions": run.potions,
		"marsh_poison": int(run.pending_marsh),
		"run_atk_buff": int(run.run_atk_buff),
	}
	run.pending_marsh = 0
	var bc := BattleCore.new()
	bc.setup(run.team, enemy_keys, opts, rng)
	var hp_before := _team_hp(run)
	if charge_tel.get("on", false):
		charge_tel.kind = kind
	play_battle(bc)
	out.battles += 1
	out.turns_total += bc.s.turn
	if not bc.s.victory:
		return {"defeat": true}
	# sync back
	for i in run.team.size():
		var h: Dictionary = run.team[i]
		var bh: Dictionary = bc.s.heroes[i]
		h.hp = 0 if bh.down else int(bh.hp)
		h.face_mods = bh.face_mods.duplicate()
	run.potions = bc.s.potions.duplicate()
	out.dmg_taken += maxi(hp_before - _team_hp(run), 0)
	run.gold = int(run.gold) + RunState.gold_for_battle(run, rng, kind)
	if kind == "elite":
		_add_relic(run, RunState.roll_relic(run, rng, "common"))
	if run.pending_imp and kind == "battle":
		_add_relic(run, RunState.roll_relic(run, rng, "common"))
	run.pending_imp = false
	if kind == "boss" and int(run.chapter) < 3:
		# the boss 2-pick. The sim takes whichever Advanced relic scores highest
		# for the party it actually has (see `_pick_advanced`).
		var choice := RunState.roll_advanced_choice(run, rng,
				int(GameData.balance.boss_advanced_picks))
		var forced := String(sim_opts.get("force_advanced", ""))
		var taken := _pick_advanced(run, choice)
		if forced != "" and forced not in run.relics:
			taken = forced
		_add_relic(run, taken)
		if taken != "":
			var seen: Array = out.get("advanced", [])
			seen.append(taken)
			out["advanced"] = seen
	RunState.post_battle_recovery(run)
	# offers: greedy pick (upgrade rarity), else skip for gold
	var offers := RunState.gen_offers(run, rng, kind, {})
	# the player now chooses which of the hero's 12 faces is replaced: the sim
	# swaps out that hero's weakest face when the offer beats it
	var took := false
	for offer in offers:
		var hi := int(offer.hero)
		var slot := _weakest_slot_of(run.team[hi])
		var old_r := _rarity_rank(String(run.team[hi].faces[slot]))
		var new_r := _rarity_rank(String(offer.face))
		if new_r > old_r:
			RunState.apply_face_swap(run, hi, slot, String(offer.face))
			took = true
			break
	if not took:
		run.gold = int(run.gold) + int(GameData.balance.offer_skip_gold)
	return {}


static func _team_hp(run: Dictionary) -> int:
	var t := 0
	for h in run.team:
		t += maxi(int(h.hp), 0)
	return t


static func _rarity_rank(face_id: String) -> int:
	match String(GameData.faces.get(face_id, {}).get("rarity", "S")):
		"E": return 4
		"R": return 3
		"U": return 3
		"C": return 2
		_: return 1


static func _add_relic(run: Dictionary, rid: String) -> void:
	if rid == "" or rid in run.relics or not GameData.relics.has(rid):
		return
	run.relics.append(rid)
	var bonus := int(GameData.relics[rid].get("value", 0)) 			if String(GameData.relics[rid].get("effect", "")) == "team_maxhp" else 0
	if bonus > 0:
		for h in run.team:
			h.max_hp = int(h.max_hp) + bonus
			if h.hp > 0:
				h.hp = int(h.hp) + bonus


## Greedy battle policy per the balance spec:
## kill > disable big threat (stun/weaken) > damage > block vs expected dmg
## > heal low allies.
static func play_battle(bc: BattleCore, max_turns := 60) -> void:
	if ess_tel.get("on", false):
		# the opening pool (Owl passive, 靈息水晶, U1's first tick) is income
		ess_tel.last = 0
		_ess_sample(bc)
	while not bc.s.over and bc.s.turn <= max_turns:
		_maybe_potion(bc)   # offensive potions before acting
		var guard := 0
		while not bc.s.over and guard < 40:
			guard += 1
			# Pins are re-decided every pass: spending one die changes what the
			# other one is worth pinning for.
			_manage_locks(bc)
			# Rerolls are re-checked on EVERY pass, not once at the top of the
			# turn. Insight faces and the Lucky keyword hand rerolls out in the
			# middle of a turn and sim v1 simply banked and wasted them, which
			# undervalued both of those keywords in every v1 number.
			_maybe_buy_reroll(bc)
			_spend_rerolls(bc)
			var best := _best_action(bc)
			if best.is_empty():
				break
			_charge_note_use(bc, best)
			_face_note_use(bc, best)
			_ess_note_use(bc, best)
			var res: Dictionary = bc.use_face(int(best.hero), int(best.die), best.params)
			if not res.get("ok", false):
				break
			_ess_sample(bc)
		_maybe_potion(bc)   # emergency heals after acting
		if not bc.s.over:
			_ess_note_turn_end(bc)
			bc.end_turn()
			# after the boundary, so the turn-start regeneration and 靈息迴環 are
			# booked as income rather than appearing from nowhere
			_ess_sample(bc)
	_charge_note_battle_end(bc)
	_face_note_rolls(bc)


# ============================================================ Essence economy
##
## Round 6's stated goal for Essence was "easier to come by, useful to more of
## the cast, and present". The first two are win-rate questions the balance
## matrix already answers. PRESENCE is not — a resource can be perfectly
## balanced and still be something the player never thinks about — so it gets
## its own measurement, and this is it:
##
##   · income and spend per turn, which is the size of the economy;
##   · the share of turns in which a Ritual actually goes off, which is whether
##     the pool is being SPENT rather than accumulated;
##   · how often the U2 trade is taken, which is whether Essence has a floor of
##     usefulness for a party holding no Rituals at all;
##   · per-hero Essence-face usage, which is whether the new faces are being
##     played or are simply sitting on the dice.
##
## Off unless `ess_tel_begin()` has been called, so the acceptance matrix pays
## nothing for it.
static var ess_tel := {}


static func ess_tel_begin() -> void:
	ess_tel = {
		"on": true, "last": 0, "turns": 0, "income": 0, "spend": 0,
		"cast_turns": 0, "casts": 0, "buys": 0, "turn_had_cast": false,
		"by_face": {},        # "HERO|face_id" → uses
		"capped": 0,          # turns that ended with the pool full
	}


static func ess_tel_end() -> void:
	ess_tel = {}


## Book the pool's movement since the last look. Every path that can change
## Essence runs through one of the two call sites (an action, or the turn
## boundary), so income and spend are measured rather than predicted.
static func _ess_sample(bc: BattleCore) -> void:
	if not ess_tel.get("on", false):
		return
	var now := int(bc.s.mana)
	var d := now - int(ess_tel.last)
	if d > 0:
		ess_tel.income += d
	elif d < 0:
		ess_tel.spend += -d
	ess_tel.last = now


static func _ess_note(kind: String) -> void:
	if not ess_tel.get("on", false):
		return
	if kind == "buy":
		ess_tel.buys += 1


static func _ess_note_use(bc: BattleCore, best: Dictionary) -> void:
	if not ess_tel.get("on", false):
		return
	var i := int(best.hero)
	var fd := bc.die_face(i, int(best.die))
	if fd.is_empty() or not (fd.has("mana") or fd.has("spell")):
		return
	var k := "%s|%s" % [String(bc.s.heroes[i].id), String(fd.get("id", "?"))]
	ess_tel.by_face[k] = int(ess_tel.by_face.get(k, 0)) + 1
	if fd.has("spell"):
		ess_tel.casts += 1
		ess_tel.turn_had_cast = true


static func _ess_note_turn_end(bc: BattleCore = null) -> void:
	if not ess_tel.get("on", false):
		return
	ess_tel.turns += 1
	# A turn that ends with the pool full is a turn whose regeneration was
	# thrown away. It is the honest counterweight to U1: income that cannot land
	# is not income, and if this number is large the answer is more to SPEND
	# Essence on, not more Essence.
	if bc != null and int(bc.s.mana) >= BattleCore.MANA_CAP:
		ess_tel.capped += 1
	if bool(ess_tel.turn_had_cast):
		ess_tel.cast_turns += 1
	ess_tel.turn_had_cast = false


## The Essence economy report.
##   godot --headless --path . -- --essence [n]
static func print_essence_report(n := 150, seed_v := 20260805) -> Dictionary:
	GameData.load_all()
	ess_tel_begin()
	# the reference party, then one solo party per hero — the starters alone
	# would never show what Fox or Boar do with the resource
	batch(n, seed_v, GameData.starter_hero_ids())
	for h in GameData.hero_ids():
		batch(maxi(n / 3, 20), seed_v, [String(h), String(h), String(h), String(h)])
	var t: Dictionary = ess_tel.duplicate(true)
	ess_tel_end()
	var turns := maxi(int(t.turns), 1)
	print("=== ESSENCE ECONOMY (%d reference runs + %d solo runs per hero) ==="
			% [n, maxi(n / 3, 20)])
	print("turns played          : %d" % turns)
	print("income  / turn        : %.2f" % (float(t.income) / turns))
	print("spend   / turn        : %.2f" % (float(t.spend) / turns))
	print("net     / turn        : %+.2f   (positive = the pool is filling faster than it drains)"
			% ((float(t.income) - float(t.spend)) / turns))
	print("turns with a Ritual   : %d%%  (%d of %d)" % [
			int(round(100.0 * float(t.cast_turns) / turns)), int(t.cast_turns), turns])
	print("Rituals cast          : %d  (%.2f per turn)" % [int(t.casts),
			float(t.casts) / turns])
	print("U2 trades taken       : %d  (%.1f%% of turns)" % [int(t.buys),
			100.0 * float(t.buys) / turns])
	print("turns ending at cap   : %d%%  — income thrown away above %d"
			% [int(round(100.0 * float(t.capped) / turns)), BattleCore.MANA_CAP])
	print("")
	print("--- Essence faces played, per hero ---")
	var per_hero := {}
	for k in t.by_face:
		var hero_id := String(k).split("|")[0]
		per_hero[hero_id] = int(per_hero.get(hero_id, 0)) + int(t.by_face[k])
	var hids: Array = GameData.hero_ids()
	for h2 in hids:
		print("  %-8s %d" % [String(h2), int(per_hero.get(String(h2), 0))])
	print("")
	print("%-8s %-22s %8s" % ["hero", "face", "uses"])
	var keys: Array = t.by_face.keys()
	keys.sort()
	for k2 in keys:
		var parts: PackedStringArray = String(k2).split("|")
		print("%-8s %-22s %8d" % [parts[0], parts[1], int(t.by_face[k2])])
	return t


# ============================================================ face-usage telemetry
##
## One question, asked because round 6 has to answer it with data rather than
## taste: WHICH starting face does each hero give up to make room for their new
## Essence face?
##
## "Least used" is not "rolled least" — every face on a die is rolled equally
## often. It is "rolled and then not spent": a face the greedy policy keeps
## passing over in favour of the hero's other die is a face that is not earning
## its slot. So both numbers are collected and the rate is what decides.
##
## Off unless `face_tel_begin()` has been called.
static var face_tel := {}


static func face_tel_begin() -> void:
	face_tel = {"on": true, "rolled": {}, "used": {}}


static func face_tel_end() -> void:
	face_tel = {}


static func _face_key(hero_id: String, face_id: String, slot: int) -> String:
	return "%s|%d|%s" % [hero_id, slot, face_id]


static func _face_note_use(bc: BattleCore, best: Dictionary) -> void:
	if not face_tel.get("on", false):
		return
	var i := int(best.hero)
	var d := int(best.die)
	var slot := int(bc.s.heroes[i].rolled[d])
	if slot < 0:
		return
	var k := _face_key(String(bc.s.heroes[i].id),
			String(bc.s.heroes[i].faces[slot]), slot)
	face_tel.used[k] = int(face_tel.used.get(k, 0)) + 1


## Every roll the battle made, read off the event log after the fact — cheaper
## than a hook, and the log is already there.
static func _face_note_rolls(bc: BattleCore) -> void:
	if not face_tel.get("on", false):
		return
	for ev in bc.events:
		if String(ev.get("t", "")) != "roll":
			continue
		var i := int(ev.hero)
		var slot := int(ev.face)
		if i < 0 or i >= bc.s.heroes.size() or slot < 0:
			continue
		var k := _face_key(String(bc.s.heroes[i].id),
				String(bc.s.heroes[i].faces[slot]), slot)
		face_tel.rolled[k] = int(face_tel.rolled.get(k, 0)) + 1


## Per-hero starting-face usage.
##   godot --headless --path . -- --faces [n]
static func print_face_report(n := 120, seed_v := 20260805) -> Dictionary:
	GameData.load_all()
	face_tel_begin()
	# every hero has to actually play, so this is six solo parties rather than
	# the reference four — the starters would never exercise Fox or Boar
	for h in GameData.hero_ids():
		batch(n, seed_v, [String(h), String(h), String(h), String(h)])
	var t: Dictionary = face_tel.duplicate(true)
	face_tel_end()
	print("=== STARTING-FACE USAGE (%d runs per hero, solo parties) ===" % n)
	print("%-8s %-4s %-22s %8s %8s %7s" % ["hero", "slot", "face", "rolled", "used", "rate"])
	var worst := {}
	var keys: Array = t.rolled.keys()
	keys.sort()
	for k in keys:
		var parts: PackedStringArray = String(k).split("|")
		var hero_id := String(parts[0])
		var slot := int(parts[1])
		var fid := String(parts[2])
		# only the twelve STARTING slots are candidates; a face picked up mid-run
		# is not one this round is allowed to take away
		var hd: Dictionary = GameData.heroes.get(hero_id, {})
		var starts: Array = Array(hd.get("start", [])) + Array(hd.get("start_b", []))
		if slot >= starts.size() or String(starts[slot]) != fid:
			continue
		var rolled := int(t.rolled[k])
		var used := int(t.used.get(k, 0))
		var rate := 100.0 * float(used) / maxf(float(rolled), 1.0)
		print("%-8s %-4d %-22s %8d %8d %6.1f%%" % [hero_id, slot, fid, rolled, used, rate])
		var row: Dictionary = worst.get(hero_id, {"rate": 999.0})
		if rate < float(row.rate):
			worst[hero_id] = {"rate": rate, "slot": slot, "face": fid,
				"rolled": rolled, "used": used}
	print("")
	print("--- least-used starting face per hero (the round-6 replacement target) ---")
	var hids: Array = worst.keys()
	hids.sort()
	for h2 in hids:
		var w: Dictionary = worst[h2]
		print("  %-8s slot %-3d %-22s %d/%d used = %.1f%%" % [h2, int(w.slot),
				String(w.face), int(w.used), int(w.rolled), float(w.rate)])
	return worst


# ============================================================ common-relic impact
##
## The Advanced tier has a pick rate because the player CHOOSES one at each of
## the first two bosses. Commons have none — they fall out of elites, chests,
## events and the shop, from a flat pool — so "pick rate" is not a number that
## exists for them and asking for one would just measure the RNG.
##
## What does exist is impact: hand the party this relic for the whole run and
## see what the win rate does. That difference, against a baseline with nothing
## forced, is what round 6 uses to decide which two commons are doing the least.
##   godot --headless --path . -- --commons [n]
## How far a batch got, averaged: 0 to 3 chapters.
##
## Win rate alone cannot rank fourteen relics. It is one binary per run, so at
## n=120 its standard error is about 4.5 points and every relic in the middle of
## the table sits inside ±9 of every other — the first pass of this report had
## three relics tied at "-8.3", which is not a ranking, it is noise wearing a
## number. Chapters cleared is the same runs scored 0-3 instead of 0-1: it moves
## when a relic gets you further without getting you all the way, which is most
## of what a common relic does, and its variance per run is correspondingly
## smaller. Win rate stays in the table as the sanity column.
static func _progress(r: Dictionary, n: int) -> float:
	return float(int(r.ch1) + int(r.ch2) + int(r.wins)) / float(n)


static func print_common_impact(n := 400, seed_v := 20260805) -> Array:
	GameData.load_all()
	var team := GameData.starter_hero_ids()
	var base := batch(n, seed_v, team)
	var base_win := 100.0 * float(base.wins) / float(n)
	var base_prog := _progress(base, n)
	print("=== COMMON RELIC IMPACT, forced for the whole run (%d runs each) ===" % n)
	print("Seed-paired: the baseline and every forced batch play the SAME %d maps," % n)
	print("so a difference is the relic rather than the run of the cards.")
	print("baseline (nothing forced): chapters %.3f  win %.1f%%" % [base_prog, base_win])
	print("%-5s %-10s %9s %8s %8s" % ["id", "name", "chapters", "Δchap", "win"])
	var rows := []
	for rid in GameData.relics_of_rarity("common"):
		var r := batch(n, seed_v, team, {"force_common": String(rid)})
		var win := 100.0 * float(r.wins) / float(n)
		var prog := _progress(r, n)
		rows.append({"id": String(rid), "win": win, "prog": prog,
			"delta": prog - base_prog})
		print("%-5s %-10s %9.3f %+8.3f %7.1f%%" % [String(rid),
				String(GameData.relics[rid].zh), prog, prog - base_prog, win])
	rows.sort_custom(func(a, b): return float(a.delta) < float(b.delta))
	print("")
	print("--- weakest first (Δ chapters cleared vs the same maps without it) ---")
	for row in rows:
		print("  %-5s %-10s %+.3f   (win %.1f%%)" % [String(row.id),
				String(GameData.relics[row.id].zh), float(row.delta), float(row.win)])
	return rows


# ============================================================ 蓄力 telemetry
##
## One question: does banking a 蓄力 die actually beat just hitting things? The
## numbers are taken at the moment a die is spent, so they record what the
## policy did, not what the face promises on paper.
##
## Off unless `charge_tel_begin()` has been called, so the acceptance matrix
## pays nothing for it.
static var charge_tel := {}


static func charge_tel_begin(hero_id := "HARE") -> void:
	charge_tel = {
		"on": true, "hero": hero_id, "kind": "",
		# 蓄力 faces actually fired
		"fired": 0, "stacks_sum": 0, "dmg_sum": 0, "full_stack": 0,
		"boss_fired": 0, "boss_stacks_sum": 0, "boss_dmg_sum": 0,
		# 蓄力 faces spent with nothing banked (fired cold)
		"cold": 0, "cold_dmg_sum": 0,
		# banked value thrown away: pin dropped mid-charge, or the fight ended
		# with the shot still in the barrel
		"abandoned": 0, "stranded": 0,
		# the comparison: every OTHER attack this hero made
		"plain": 0, "plain_dmg_sum": 0,
		"boss_plain": 0, "boss_plain_dmg_sum": 0,
		# What holding actually costs. A charging hero is NOT idle — they still
		# act every turn with their other die. The only thing they give up is the
		# option of firing the charge face cold, so the cost of one held turn is
		# (what the pinned face would have done now) − (what they did instead),
		# floored at zero. Turns where the hero did something non-damaging are
		# counted but not priced, rather than guessing a damage value for a heal.
		"held_turns": 0, "held_priced": 0, "hold_cost_sum": 0,
		"by_face": {},    # face id → {n, stacks, dmg}
		"by_stack": {},   # stack count → {n, dmg} — the literal "is a FULL
		                  # charge better than just hitting things" question,
		                  # which an average over stack counts cannot answer
	}


static func charge_tel_end() -> void:
	charge_tel = {}


## Effective damage the chosen attack is about to land (Block already taken off,
## multi-hit summed). Returns -1 when the action is not an attack.
static func _charge_dmg_of(bc: BattleCore, i: int, d: int, params: Dictionary) -> int:
	var t := int(params.get("target", -1))
	if t < 0 or t >= bc.s.enemies.size():
		return -1
	var pv := bc.preview_attack(i, d, t)
	if not pv.has("hp_loss"):
		return -1
	return int(pv.hp_loss)


static func _charge_note_use(bc: BattleCore, best: Dictionary) -> void:
	if not charge_tel.get("on", false):
		return
	var i := int(best.hero)
	if String(bc.s.heroes[i].id) != String(charge_tel.hero):
		return
	var d := int(best.die)
	var fd := bc.die_face(i, d)
	if fd.is_empty():
		return
	var params: Dictionary = best.get("params", {})
	var dmg := _charge_dmg_of(bc, i, d, params)
	# Is this a turn spent holding a charge on the OTHER die? Price what the hold
	# cost, before recording what was actually used.
	var other: int = 1 - d
	var oth := bc.die_face(i, other)
	if bool(bc.s.heroes[i].locked[other]) and not oth.is_empty() \
			and int(oth.get("charge_up", 0)) > 0 and bc.charge_turns(i, other) >= 0:
		charge_tel.held_turns += 1
		var cold_now := _charge_dmg_of(bc, i, other, params)
		if cold_now >= 0 and dmg >= 0:
			charge_tel.held_priced += 1
			charge_tel.hold_cost_sum += maxi(0, cold_now - dmg)
	if dmg < 0:
		return
	var boss := String(charge_tel.kind) == "boss"
	if int(fd.get("charge_up", 0)) <= 0:
		charge_tel.plain += 1
		charge_tel.plain_dmg_sum += dmg
		if boss:
			charge_tel.boss_plain += 1
			charge_tel.boss_plain_dmg_sum += dmg
		return
	var stacks := bc.charge_turns(i, d)
	if stacks <= 0:
		charge_tel.cold += 1
		charge_tel.cold_dmg_sum += dmg
		return
	charge_tel.fired += 1
	charge_tel.stacks_sum += stacks
	charge_tel.dmg_sum += dmg
	if stacks >= BattleCore.CHARGE_TURN_CAP:
		charge_tel.full_stack += 1
	if boss:
		charge_tel.boss_fired += 1
		charge_tel.boss_stacks_sum += stacks
		charge_tel.boss_dmg_sum += dmg
	var srow: Dictionary = charge_tel.by_stack.get(stacks, {"n": 0, "dmg": 0})
	srow.n = int(srow.n) + 1
	srow.dmg = int(srow.dmg) + dmg
	charge_tel.by_stack[stacks] = srow
	var fid := String(fd.get("id", "?"))
	var row: Dictionary = charge_tel.by_face.get(fid, {"n": 0, "stacks": 0, "dmg": 0})
	row.n = int(row.n) + 1
	row.stacks = int(row.stacks) + stacks
	row.dmg = int(row.dmg) + dmg
	charge_tel.by_face[fid] = row


## A pin the policy is about to drop. If it was mid-charge, that banked value is
## gone — count it, because "how often does the charge never go off" is half the
## answer to whether charging is worth doing.
static func _charge_note_unpin(bc: BattleCore, i: int, d: int) -> void:
	if not charge_tel.get("on", false):
		return
	if String(bc.s.heroes[i].id) != String(charge_tel.hero):
		return
	var fd := bc.die_face(i, d)
	if not fd.is_empty() and int(fd.get("charge_up", 0)) > 0 and bc.charge_turns(i, d) > 0:
		charge_tel.abandoned += 1


static func _charge_note_battle_end(bc: BattleCore) -> void:
	if not charge_tel.get("on", false):
		return
	for i in bc.s.heroes.size():
		if String(bc.s.heroes[i].id) != String(charge_tel.hero):
			continue
		for d in BattleCore.DICE:
			if not bool(bc.s.heroes[i].locked[d]):
				continue
			var fd := bc.die_face(i, d)
			if not fd.is_empty() and int(fd.get("charge_up", 0)) > 0 \
					and bc.charge_turns(i, d) > 0:
				charge_tel.stranded += 1


## 蓄力 usage report.
##   godot --headless --path . -- --charge [n] [hero]
static func print_charge_report(n := 150, hero_id := "HARE", seed_v := 20260805) -> Dictionary:
	GameData.load_all()
	charge_tel_begin(hero_id)
	var r := batch(n, seed_v)
	var t := charge_tel.duplicate(true)
	charge_tel_end()
	var nm := String(GameData.heroes.get(hero_id, {}).get("zh", hero_id))
	print("=== CHARGE (蓄力) USAGE — %s %s, %d runs, seed %d ===" % [hero_id, nm, n, seed_v])
	var fired := int(t.fired)
	var all_shots: int = fired + int(t.cold) + int(t.plain)
	print("attacks made by %s: %d   of which 蓄力 faces: %d banked + %d cold" % [
			hero_id, all_shots, fired, int(t.cold)])
	if fired > 0:
		print("banked shots: avg %.2f stacks before firing (cap %d), %d%% fired at full stack" % [
				float(t.stacks_sum) / fired, BattleCore.CHARGE_TURN_CAP,
				int(round(100.0 * int(t.full_stack) / fired))])
		print("              avg damage on release: %.2f" % (float(t.dmg_sum) / fired))
	if int(t.cold) > 0:
		print("cold shots  : %d, avg damage %.2f" % [int(t.cold),
				float(t.cold_dmg_sum) / int(t.cold)])
	if int(t.plain) > 0:
		print("plain shots : %d, avg damage %.2f   <- the steady-output baseline" % [
				int(t.plain), float(t.plain_dmg_sum) / int(t.plain)])
	# The verdict. A charging hero still acts every turn with the other die, so
	# the cost of holding is NOT a lost turn — it is only the option of firing
	# the pinned face at its current value, which is what `hold_cost` measures.
	# Over the whole sequence the two lines come out to:
	#     charge:  (turns spent with the other die) + release
	#     steady:  (same turns, but free to fire the charge face) + one plain turn
	# so charging pays exactly when  release − Σhold_cost > plain.
	if fired > 0 and int(t.plain) > 0:
		var per_shot := float(t.dmg_sum) / fired
		var plain_avg := float(t.plain_dmg_sum) / int(t.plain)
		var hold_per_release := float(t.hold_cost_sum) / fired
		var net := per_shot - hold_per_release
		print("hold cost   : %d held turns (%d priced), %.2f dmg given up per release" % [
				int(t.held_turns), int(t.held_priced), hold_per_release])
		print("VERDICT     : release %.2f − hold %.2f = %.2f  vs  plain %.2f  →  %+.2f  (%s)" % [
				per_shot, hold_per_release, net, plain_avg, net - plain_avg,
				"charging pays" if net > plain_avg else "steady output wins"])
	print("boss fights : %d banked shots (%d%% of all banked), avg %.2f stacks, avg dmg %.2f" % [
			int(t.boss_fired),
			int(round(100.0 * int(t.boss_fired) / maxi(fired, 1))),
			float(t.boss_stacks_sum) / maxi(int(t.boss_fired), 1),
			float(t.boss_dmg_sum) / maxi(int(t.boss_fired), 1)])
	if int(t.boss_plain) > 0:
		print("              boss plain shots %d, avg dmg %.2f" % [int(t.boss_plain),
				float(t.boss_plain_dmg_sum) / int(t.boss_plain)])
	var boss_total: int = int(t.boss_dmg_sum) + int(t.boss_plain_dmg_sum)
	if boss_total > 0:
		print("              share of %s's boss-fight damage from banked shots: %d%%" % [
				hero_id, int(round(100.0 * int(t.boss_dmg_sum) / boss_total))])
	print("wasted      : %d charges abandoned mid-bank, %d stranded when the fight ended" % [
			int(t.abandoned), int(t.stranded)])
	# "even a FULL charge does not beat steady output" is a claim about the top of
	# this table, not about its average — print the table so it can be checked.
	if not t.by_stack.is_empty() and int(t.plain) > 0:
		var plain_ref := float(t.plain_dmg_sum) / int(t.plain)
		var cost_per_turn := float(t.hold_cost_sum) / maxi(int(t.fired), 1) \
				/ maxf(float(t.stacks_sum) / maxi(int(t.fired), 1), 1.0)
		print("by stacks held (vs plain %.2f):" % plain_ref)
		var stacks_keys: Array = t.by_stack.keys()
		stacks_keys.sort()
		for k in stacks_keys:
			var srow: Dictionary = t.by_stack[k]
			var avg := float(srow.dmg) / int(srow.n)
			var net := avg - cost_per_turn * float(k)
			print("  %d stack(s)  n=%4d  avg dmg %5.2f  net of hold cost %5.2f  (%+.2f vs plain)" % [
					int(k), int(srow.n), avg, net, net - plain_ref])
	if not t.by_face.is_empty():
		print("by face:")
		var ids: Array = t.by_face.keys()
		ids.sort()
		for fid in ids:
			var row: Dictionary = t.by_face[fid]
			var f: Dictionary = GameData.faces.get(fid, {})
			print("  %-16s %-8s n=%3d  avg stacks %.2f  avg dmg %.2f  (base atk %d, +%d/stack)" % [
					fid, String(f.get("zh", "")), int(row.n),
					float(row.stacks) / int(row.n), float(row.dmg) / int(row.n),
					int(f.get("atk", 0)), int(f.get("charge_up", 0))])
	return t


## Total enemy HP still standing — the sim's stand-in for "how much fight is
## left", used to decide whether banking a 蓄力 face will ever pay off.
static func _enemy_hp_left(bc: BattleCore) -> int:
	var t := 0
	for e in bc.s.enemies:
		if not e.dead:
			t += maxi(int(e.hp), 0)
	return t


## Below this much enemy HP the fight is short enough that a banked shot never
## gets fired, and the die is worth more free.
const CHARGE_WORTH_BANKING := 30


## Would spending this die right now finish something off?
static func _would_kill(bc: BattleCore, i: int, d: int) -> bool:
	for j in bc.s.enemies.size():
		if bc.s.enemies[j].dead:
			continue
		var pv := bc.preview_attack(i, d, j)
		if pv.has("hp_loss") and int(pv.hp_loss) >= int(bc.s.enemies[j].hp):
			return true
	return false


## The pin policy, and the whole of what the sim knows about 蓄力 / 呼應.
##
## Two reasons to pin, both mechanical rather than taste:
##   1. A 蓄力 face is worth more banked than spent, until its stack is full.
##      Pin it and take the turn's action with the other die.
##   2. A 呼應 face pays only while its partner is pinned on the right kind of
##      face. If the partner is already showing one, pin it.
## Anything else is unpinned, so the reroll policy can do its job.
##
## What this does NOT model is a player pinning a merely good face to protect it
## from a reroll — that is taste, it varies by player, and guessing at it would
## put a number in BALANCE.md that no real game produces.
static func _manage_locks(bc: BattleCore) -> void:
	for i in bc.s.heroes.size():
		var h: Dictionary = bc.s.heroes[i]
		if h.down or h.stolen or h.used:
			continue
		var want := [false, false]
		for d in BattleCore.DICE:
			if int(h.rolled[d]) < 0:
				continue
			var fd := bc.die_face(i, d)
			if fd.is_empty():
				continue
			var other: int = 1 - d
			if int(fd.get("charge_up", 0)) > 0:
				# Unpinning ZEROES the banked turns (`toggle_lock`), so a die
				# holding Charge must stay pinned until it is spent — including
				# the pass on which it tops out, and the pass on which the fight
				# gets too short to keep banking. Deciding to stop banking means
				# FIRE it, not throw it away; `_reserved` is what lets go.
				if bc.charge_turns(i, d) > 0:
					want[d] = true
				elif bc.can_use(i, other).ok \
						and _enemy_hp_left(bc) >= CHARGE_WORTH_BANKING:
					want[d] = true
			if (fd.has("resonate") or fd.has("resonate_req")) and bc.resonate_would_match(i, fd):
				want[other] = true
		for d2 in BattleCore.DICE:
			if int(h.rolled[d2]) >= 0 and bool(h.locked[d2]) != bool(want[d2]):
				if bool(h.locked[d2]):
					_charge_note_unpin(bc, i, d2)
				bc.toggle_lock(i, d2)


## A die the pin policy is holding back: spending it now would throw away the
## reason it was pinned. The greedy loop skips these.
static func _reserved(bc: BattleCore, i: int, d: int) -> bool:
	var h: Dictionary = bc.s.heroes[i]
	if not bool(h.locked[d]):
		return false
	var fd := bc.die_face(i, d)
	if fd.is_empty():
		return false
	# Still filling up — unless the fight will be over before it pays. Banking
	# costs the hero their CHOICE of die for three turns (they only get one
	# action either way), which is cheap in a boss race and pure waste in a
	# skirmish that ends on turn three. Holding a shot back to make it bigger
	# than the thing it was going to kill is the same mistake in miniature.
	if int(fd.get("charge_up", 0)) > 0 \
			and bc.charge_turns(i, d) < BattleCore.CHARGE_TURN_CAP \
			and bc.can_use(i, 1 - d).ok \
			and _enemy_hp_left(bc) >= CHARGE_WORTH_BANKING \
			and not _would_kill(bc, i, d):
		return true
	# feeding a partner's 呼應, which is the better die of the two
	var other: int = 1 - d
	var of := bc.die_face(i, other)
	if not of.is_empty() and (of.has("resonate") or of.has("resonate_req")) \
			and bc.resonate_met(i, of) and bc.can_use(i, other).ok:
		return true
	return false


## How much Essence the policy insists on leaving in the pool when it buys a
## reroll. Set to the most expensive Ritual the party is actually holding, so
## the trade never cannibalises a cast the party could make this turn — spending
## 2 to fix a bad die and thereby failing to afford a 4-cost Starfall is a bad
## trade that a naive "buy whenever you can afford it" policy makes constantly.
## How much Essence the pool is about to gain, for the "am I wasting it?" test.
## `MANA_REGEN` alone rather than every source (the Owl's passive is a battle-
## start one-off, 森之心 and 靈息迴環 are relics): the point is only to notice
## that the pool is at or one step from the ceiling.
const MANA_REGEN_HINT := BattleCore.MANA_REGEN


static func _essence_reserve(bc: BattleCore) -> int:
	var most := 0
	for i in bc.s.heroes.size():
		for d in BattleCore.DICE:
			var c := bc.can_use(i, d)
			if c.ok and c.face.has("spell"):
				most = maxi(most, bc.spell_cost(c.face))
	return most


## U2, as the policy sees it: buy the throw only when the dice on the table are
## genuinely bad AND the Essence is not already promised to something better.
##
## The bar is the same one `_spend_rerolls` uses — two or more heroes holding
## nothing worth playing — because the trade is only worth making for the same
## reason a free reroll is. Buying speculatively would flatter U2 in every
## number this harness produces.
static func _maybe_buy_reroll(bc: BattleCore) -> void:
	if not bc.can_buy_reroll().ok:
		return
	if int(bc.s.mana) - BattleCore.ESSENCE_REROLL_COST < _essence_reserve(bc):
		return
	# already holding a throw? spend that one first — it is free
	if bc.s.rerolls > 0 or bc.rerolls_unlimited():
		return
	# At the ceiling the next point of regeneration is thrown away, so the trade
	# costs literally nothing and the bar below does not apply. This branch is
	# not a flourish: the first cut of this policy took the trade on 1.0% of
	# turns while ENDING 12% of them with a full pool, which is a harness that
	# systematically under-plays the resource the round exists to add — and
	# therefore under-states how strong the party is when the bands are judged.
	var wasting: bool = int(bc.s.mana) + MANA_REGEN_HINT > BattleCore.MANA_CAP
	if wasting:
		if bc.buy_reroll():
			_ess_note("buy")
		return
	var weak := 0
	for i in bc.s.heroes.size():
		var h: Dictionary = bc.s.heroes[i]
		if h.down or h.stolen or h.used:
			continue
		var best := 0
		for d in BattleCore.DICE:
			if int(h.rolled[d]) >= 0 and not _reserved(bc, i, d):
				best = maxi(best, _die_score(bc, i, d))
		if best < 2:
			weak += 1
	if weak >= 2:
		if bc.buy_reroll():
			_ess_note("buy")


## With no base rerolls the reroll button is a scarce relic/potion resource:
## only spend it on heroes whose BOTH dice are weak, since the hero will
## already pick the better of the two.
static func _spend_rerolls(bc: BattleCore) -> void:
	var guard := 0
	var bone := bc.rerolls_unlimited()
	while bc.can_reroll() and guard < 6:
		guard += 1
		# A04 賭徒之骨: rerolls are free of charge but cost the party 1 HP each,
		# so they stop the moment the party is not comfortably healthy.
		if bone and not _bone_safe(bc):
			return
		# The bar for spending one does NOT drop when they are unlimited. That
		# was tried — one hero holding two dead dice was enough to reroll — and
		# it made the relic worse, not better: 20% win rate against 27% for the
		# careful policy, because four heroes paying 1 HP a throw outruns what
		# a greedy policy gets back from a better face. Measured, see BALANCE.md.
		var weak_heroes := 0
		# Dice pinned for a reason (banking 蓄力, feeding a 呼應) must survive
		# this: they are held across turns on purpose, and rerolling one throws
		# the stack away. Anything the policy pins here is a throwaway pin to
		# protect a good face for one throw, and is put back afterwards.
		var restore := []
		for i in bc.s.heroes.size():
			var h: Dictionary = bc.s.heroes[i]
			if h.down or h.stolen or h.used:
				continue
			var best := 0
			for d in BattleCore.DICE:
				if int(h.rolled[d]) < 0:
					continue
				var score := _die_score(bc, i, d)
				if not _reserved(bc, i, d):
					restore.append([i, d, bool(h.locked[d])])
					h.locked[d] = score >= 3
				best = maxi(best, score)
			if best < 2:
				weak_heroes += 1
		if weak_heroes >= 2:
			bc.reroll()
		for r in restore:
			bc.s.heroes[int(r[0])].locked[int(r[1])] = bool(r[2])
		if weak_heroes < 2:
			break


## A04 safety line: never gamble HP the party cannot spare. Every living hero
## must be above 3 HP and the party as a whole above 55% of its pool.
static func _bone_safe(bc: BattleCore) -> bool:
	var hp := 0
	var max_hp := 0
	for h in bc.s.heroes:
		if h.down:
			continue
		if int(h.hp) <= 3:
			return false
		hp += int(h.hp)
		max_hp += int(h.max_hp)
	return max_hp > 0 and float(hp) / float(max_hp) >= 0.55


## Rough die usefulness: 0 = dead face, higher = better.
static func _die_score(bc: BattleCore, i: int, d: int) -> int:
	var c := bc.can_use(i, d)
	if not c.ok:
		return 0
	var fd: Dictionary = c.face
	if fd.has("atk") or fd.has("random_atk") or fd.has("atk_from_block"):
		return 3
	if fd.has("stun") or fd.has("weaken"):
		return 2
	if fd.has("block") or fd.has("team_block") or fd.has("taunt") \
			or fd.has("block_from_mana") or fd.has("thorns") or fd.has("team_thorns"):
		return 2
	# the turn-shaping faces: 戰吼 / 暴走 / 鷹眼 / 雙舞 / 孤注 / 豎刺 / 堅守
	if fd.has("team_atk") or fd.has("self_atk_now") or fd.get("all_pierce", false) \
			or fd.get("twin_dance", false) or fd.has("next_dice_boost") \
			or fd.has("thorns_double") or fd.get("thorn_hold", false) \
			or fd.has("lock_boost"):
		return 2
	if fd.has("heal") or fd.has("team_heal"):
		var hurt := false
		for h in bc.s.heroes:
			if h.down or h.hp * 2 < h.max_hp:
				hurt = true
		return 3 if hurt else 1
	if fd.has("mana"):
		return 2 if bc.s.mana < 8 else 1
	return 1


static func _expected_damage(bc: BattleCore) -> int:
	var total := 0
	for e in bc.s.enemies:
		if e.dead:
			continue
		for r in e.rolls:
			if r.cancelled or r.done:
				continue
			var f: Dictionary = r.face
			if f.has("atk"):
				var v: int = bc._enemy_face_value(e, f, "atk")
				if f.get("aoe", false):
					v *= 2
				total += v
	for a in bc.s.announce:
		if not a.cancelled:
			total += int(a.get("dmg", 0)) * int(a.get("hits", 1))
	return total


## A01 雙月徽記 lets exactly one hero a turn spend both dice. Handed to the
## greedy loop unguarded it would go to whoever it reached first, so the slot
## is reserved here for whichever already-acted hero still holds the best die.
static func _twin_pick(bc: BattleCore) -> int:
	var claimed := int(bc.s.get("twin_hero", -1))
	if claimed >= 0:
		return claimed
	var best := -1
	var best_score := 0
	for i in bc.s.heroes.size():
		var h: Dictionary = bc.s.heroes[i]
		if h.down or not h.used:
			continue
		for d in BattleCore.DICE:
			if not bc.can_use(i, d).ok:
				continue
			var sc := _die_score(bc, i, d)
			if sc > best_score:
				best_score = sc
				best = i
	return best


static func _best_action(bc: BattleCore) -> Dictionary:
	var kill := {}
	var disable := {}
	var damage := {}
	var block := {}
	var heal := {}
	var other := {}
	var twin := _twin_pick(bc)
	for i in bc.s.heroes.size():
		for d in BattleCore.DICE:
			if bool(bc.s.heroes[i].used) and i != twin \
					and not bool(bc.s.heroes[i].get("twin_dance", false)):
				continue    # only the twin-seal (or 雙舞) hero gets a second action
			if _reserved(bc, i, d):
				continue    # pinned on purpose — see `_manage_locks`
			var c := bc.can_use(i, d)
			if not c.ok:
				continue
			var fd: Dictionary = c.face
			var lt := bc.legal_targets(i, d)
			_score_die(bc, i, d, fd, lt, kill, disable, damage, block, heal, other)
	for cand in [kill, disable, damage, block, heal, other]:
		if not cand.is_empty():
			return cand
	return {}


## What `_score_die` branches on, per target type, declared so a test can check
## it. `tests/data_policy_test.gd` reads BOTH this table and the source of
## `_score_die` below, and goes red when they disagree or when a face in
## data/faces.json matches nothing in its own target's row.
##
## The point is the failure mode this harness has now hit twice: a face the
## policy has no branch for is never played, reports 0 uses, and reads exactly
## like a face nobody wants (round 6: 豎棘 0/3491; round 7: 靜滯場, and 竊骰
## which could not even be resolved). Both were fixed rather than declared. What
## is left is `POLICY_BLIND`, which must carry a reason.
##
## Target types are `legal_targets`' types, not the face's `target` string:
## "self" and "none" faces both arrive as "none".
const POLICY_KEYS := {
	"enemy": ["atk", "random_atk", "atk_from_block", "weaken", "expose", "poison"],
	"enemy_die": ["stun", "steal_die"],
	"ally": ["heal", "regen"],
	"none": ["block", "team_block", "taunt", "block_from_mana", "thorns",
		"thorns_double", "thorn_hold", "atk", "poison", "burn", "weaken",
		"expose", "all_pierce", "team_atk", "self_atk_now", "twin_dance",
		"next_dice_boost", "mana", "rerolls", "team_heal", "team_thorns",
		"team_regen", "buff_next_atk"],
	"wild": [],
}

## Keys `_score_die` reads to QUALIFY a branch it is already in, rather than to
## open one: `aoe` picks the sweeping-burn case apart from the single-target
## one, `pain` is what stops 以血引靈 being cast on a hero who cannot pay. A
## face carrying only these is still unplayable, so they are declared here and
## not in `POLICY_KEYS`.
const POLICY_QUALIFIERS := ["aoe", "pain"]

## Faces the policy deliberately cannot play, and why. Anything in here is a
## declared blind spot: the numbers in BALANCE.md do not include it, and saying
## so is the whole point of the entry.
const POLICY_BLIND := {
	"sp_chaos": "混沌 copies another die on the table. Choosing WHICH die is a "
		+ "whole second policy — the copy inherits none of the original's "
		+ "position bonuses, so the sim would have to re-score every other die "
		+ "in the party from the copier's seat. Declared rather than guessed: a "
		+ "bad copy policy would understate the face just as badly as no policy.",
}


## Buckets one die into the greedy priority lists. Dictionaries are passed by
## reference, so a candidate written here survives the call.
static func _score_die(bc: BattleCore, i: int, d: int, fd: Dictionary, lt: Dictionary,
		kill: Dictionary, disable: Dictionary, damage: Dictionary,
		block: Dictionary, heal: Dictionary, other: Dictionary) -> void:
	match String(lt.type):
		"enemy":
			if lt.indices.is_empty():
				return
			# focus lowest-hp target; check kill
			var best_t: int = lt.indices[0]
			var low_hp := 999999
			for j_v in lt.indices:
				var j := int(j_v)
				var pv := bc.preview_attack(i, d, j)
				var e: Dictionary = bc.s.enemies[j]
				if pv.has("hp_loss") and int(pv.hp_loss) >= e.hp and kill.is_empty():
					_pick(kill, i, d, {"target": j})
				if e.hp < low_hp:
					low_hp = e.hp
					best_t = j
			if fd.has("atk") or fd.has("random_atk") or fd.has("atk_from_block"):
				var pv2 := bc.preview_attack(i, d, best_t)
				var dealt := int(pv2.get("hp_loss", 3))
				if damage.is_empty() or dealt > int(damage.get("dmg", 0)):
					_pick(damage, i, d, {"target": best_t})
					damage["dmg"] = dealt
			elif fd.has("weaken") or fd.get("expose", false) or fd.has("poison"):
				if disable.is_empty():
					# debuff the biggest-attack enemy
					_pick(disable, i, d, {"target": _biggest_threat(bc)})
		"enemy_die":
			if fd.has("stun") and disable.is_empty():
				var pick := _biggest_die(bc, lt.indices)
				if not pick.is_empty():
					var big_enough: bool = pick.get("value", 0) >= 5 or _expected_damage(bc) >= 10
					if big_enough:
						var params := {"die": pick.ref}
						if int(fd.get("stun", 1)) > 1:
							var second := _biggest_die(bc, lt.indices, pick.ref)
							params["die2"] = second.ref if not second.is_empty() else pick.ref
						_pick(disable, i, d, params)
			elif fd.get("steal_die", false) and disable.is_empty():
				# 竊骰 cancels the die AND fires it back, so it is strictly better
				# than stunning the same die and gets no size bar. Boss
				# announcements (`die < 0`) are stunnable but not stealable —
				# `_do_die_theft` rejects them — so they are filtered out here
				# rather than handed over to fail at resolve time.
				var stealable := []
				for ref_v in lt.indices:
					if int(ref_v.die) >= 0:
						stealable.append(ref_v)
				var take := _biggest_die(bc, stealable)
				if not take.is_empty():
					_pick(disable, i, d, {"die": take.ref})
		"ally":
			if fd.has("heal"):
				var worst := -1
				var worst_pct := 0.55
				for j2 in bc.s.heroes.size():
					var h2: Dictionary = bc.s.heroes[j2]
					var pct: float = 0.0 if h2.down else float(h2.hp) / h2.max_hp
					if h2.down or pct < worst_pct:
						worst_pct = 0.0 if h2.down else pct
						worst = j2
				if worst >= 0 and heal.is_empty():
					_pick(heal, i, d, {"target": worst})
			elif fd.has("regen") and heal.is_empty():
				var worst2 := 0
				var lowest := 2.0
				for j3 in bc.s.heroes.size():
					var h3: Dictionary = bc.s.heroes[j3]
					if not h3.down and float(h3.hp) / h3.max_hp < lowest:
						lowest = float(h3.hp) / h3.max_hp
						worst2 = j3
				if lowest < 0.8:
					_pick(heal, i, d, {"target": worst2})
		"none":
			if fd.has("block") or fd.has("team_block") or fd.get("taunt", false) \
					or fd.has("block_from_mana"):
				if block.is_empty() and _expected_damage(bc) > _team_block(bc):
					_pick(block, i, d, {})
			elif fd.has("thorns"):
				# `thorns` only, not `team_thorns`: the team version already had a
				# home further down this chain, and moving it would change how the
				# policy plays faces this round is not otherwise touching.
				#
				# Thorns is defence that answers back, so it is priced the way
				# Block is: worth a die when the enemy line threatens more than
				# the party can already absorb.
				#
				# This branch did not exist until round 6, and its absence was
				# not harmless — 豎棘 (`thorns` alone, no Block on it) matched no
				# case at all, so the policy could never pick it up and the face
				# reported 0 uses out of 3,509 rolls. A measurement bug that
				# reads exactly like a dead face, which matters because round 6
				# picks the face each hero gives up FROM THESE NUMBERS.
				if block.is_empty() and _expected_damage(bc) > _team_block(bc):
					_pick(block, i, d, {})
			elif fd.has("thorns_double") or fd.get("thorn_hold", false):
				# both are multipliers on Thorns already standing; with none up
				# they do nothing at all, so they wait
				if block.is_empty() and int(bc.s.heroes[i].thorns) >= 2:
					_pick(block, i, d, {})
			elif fd.has("atk") or fd.has("poison") or (fd.has("burn") and fd.get("aoe", false)):
				if damage.is_empty():
					_pick(damage, i, d, {})
			elif fd.has("weaken") or fd.get("expose", false):
				# 靜滯場: a sweeping debuff needs no target, so it arrives here
				# rather than in the "enemy" branch — and until round 7 nothing
				# caught it, which made an R-rarity shared-pool face unplayable
				# to the policy and invisible in every number this harness
				# produced. Same failure as 豎棘 in round 6, one target type over.
				if disable.is_empty():
					_pick(disable, i, d, {})
			elif fd.get("all_pierce", false) or fd.has("team_atk") or fd.has("self_atk_now"):
				# these pay only if somebody is left to swing afterwards
				if other.is_empty() and _party_can_still_act(bc, i):
					_pick(other, i, d, {})
			elif fd.get("twin_dance", false):
				# 雙舞 is only an action if the pinned die is worth spending
				if other.is_empty() and bc.s.heroes[i].locked[1 - d] \
						and bc.can_use(i, 1 - d).ok:
					_pick(other, i, d, {})
			elif fd.has("next_dice_boost"):
				# 孤注 pays next turn and costs HP now: only while comfortable
				if other.is_empty() and bc.s.heroes[i].hp * 2 > bc.s.heroes[i].max_hp:
					_pick(other, i, d, {})
			elif fd.has("mana"):
				var h5: Dictionary = bc.s.heroes[i]
				if fd.has("pain") and h5.hp * 2 <= h5.max_hp:
					# 以血引靈 buys Essence with HP. Not with the last of it.
					pass
				elif block.is_empty() and _gather_unlocks(bc, i, int(fd.mana)):
					# Somebody else is holding a Ritual this gather would pay for
					# THIS turn. That is a real play and it used to sit in the
					# bottom bucket with the do-nothing faces, which is why the
					# pre-round-6 numbers had the party gathering only when it had
					# nothing else at all to do.
					_pick(block, i, d, {})
				elif other.is_empty():
					_pick(other, i, d, {})
			elif fd.has("rerolls") or fd.has("team_heal") \
					or fd.has("team_thorns") or fd.has("team_regen") or fd.has("buff_next_atk"):
				if fd.has("team_heal"):
					var hurt2 := false
					for h4 in bc.s.heroes:
						if not h4.down and h4.hp * 2 < h4.max_hp:
							hurt2 = true
					if hurt2 and heal.is_empty():
						_pick(heal, i, d, {})
				elif other.is_empty():
					_pick(other, i, d, {})
		"wild":
			pass   # simple policy skips wilds


## Would `gain` points of Essence turn somebody ELSE's unaffordable Ritual into
## one they can cast this turn?
##
## Somebody else, and still able to act: gathering to afford a face on a hero who
## has already spent their turn buys nothing until next turn, and gathering with
## one die to afford the Ritual on your OWN other die is impossible — a hero acts
## once (the Twin Moon Seal aside, which this deliberately does not chase).
static func _gather_unlocks(bc: BattleCore, i: int, gain: int) -> bool:
	if gain <= 0:
		return false
	var pool := int(bc.s.mana)
	for j in bc.s.heroes.size():
		if j == i or not bc.hero_can_act(j):
			continue
		for d in BattleCore.DICE:
			var fd := bc.die_face(j, d)
			if fd.is_empty() or not fd.has("spell"):
				continue
			var cost := bc.spell_cost(fd)
			if cost > pool and cost <= pool + gain:
				return true
	return false


## Writes a candidate into a bucket in place (rebinding the local would not
## reach the caller).
static func _pick(bucket: Dictionary, hero: int, die: int, params: Dictionary) -> void:
	bucket.clear()
	bucket["hero"] = hero
	bucket["die"] = die
	bucket["params"] = params


## Is there anybody besides hero `i` who could still swing this turn? 戰吼,
## 暴走 and 鷹眼 all buy value for LATER attacks, so spending the party's last
## action on one is spending it on nothing.
static func _party_can_still_act(bc: BattleCore, i: int) -> bool:
	for j in bc.s.heroes.size():
		if j == i:
			continue
		if bc.hero_can_act(j):
			return true
	# or the caster still has their own other die (Twin Moon Seal / 雙舞)
	return false


static func _team_block(bc: BattleCore) -> int:
	var t := 0
	for h in bc.s.heroes:
		if not h.down:
			t += int(h.block)
	return t


static func _biggest_threat(bc: BattleCore) -> int:
	var best := 0
	var best_v := -1
	for j in bc.s.enemies.size():
		var e: Dictionary = bc.s.enemies[j]
		if e.dead:
			continue
		var v := 0
		for r in e.rolls:
			if not r.cancelled and not r.done and r.face.has("atk"):
				v += bc._enemy_face_value(e, r.face, "atk")
		if v > best_v:
			best_v = v
			best = j
	return best


static func _biggest_die(bc: BattleCore, refs: Array, exclude = null) -> Dictionary:
	var best := {}
	var best_v := -1
	for ref_v in refs:
		var ref: Dictionary = ref_v
		if exclude != null and ref == exclude:
			continue
		var v := 0
		var dj := int(ref.die)
		if dj < 0:
			v = 12   # boss announcement — always juicy
		else:
			var e: Dictionary = bc.s.enemies[int(ref.enemy)]
			if dj >= e.rolls.size():
				continue
			var f: Dictionary = e.rolls[dj].face
			v = bc._enemy_face_value(e, f, "atk") if f.has("atk") else 1
		if v > best_v:
			best_v = v
			best = {"ref": ref, "value": v}
	return best


static func _maybe_potion(bc: BattleCore) -> void:
	var vs_boss := false
	var alive_enemies := 0
	for e in bc.s.enemies:
		if not e.dead:
			alive_enemies += 1
			if e.kind == "boss":
				vs_boss = true
	for slot in range(bc.s.potions.size() - 1, -1, -1):
		if slot >= bc.s.potions.size():
			continue
		var pid: String = bc.s.potions[slot]
		var pd: Dictionary = GameData.potions[pid]
		match String(pd.effect):
			"heal":
				var worst := -1
				var worst_pct := 0.3
				for i in bc.s.heroes.size():
					var h: Dictionary = bc.s.heroes[i]
					if not h.down and float(h.hp) / h.max_hp < worst_pct:
						worst_pct = float(h.hp) / h.max_hp
						worst = i
				if worst >= 0:
					bc.use_potion(slot, {"target": worst})
			"team_heal":
				var hurt := 0
				for h in bc.s.heroes:
					if not h.down and h.hp * 3 < h.max_hp:
						hurt += 1
				if hurt >= 2:
					bc.use_potion(slot)
			"team_atk_buff":
				# burn it on bosses (or crowded fights) once attacks are ready
				if vs_boss or alive_enemies >= 3:
					bc.use_potion(slot)
			"poison_all":
				if vs_boss or alive_enemies >= 2:
					bc.use_potion(slot)
			"team_block":
				if _expected_damage(bc) - _team_block(bc) >= 8:
					bc.use_potion(slot)
			"rerolls":
				if vs_boss and bc.s.rerolls == 0:
					bc.use_potion(slot)
			_:
				pass


# ============================================================ advanced relics

## Which of the two Advanced relics on offer this party actually wants. The
## scores are deliberately coarse: the point is that the sim never leaves a
## build-defining relic on the table, not that it plays each one perfectly.
## Relics the policy cannot exploit are declared in BALANCE.md.
## Scored by what the party's PASSIVES and face pools can exploit rather than by
## hero id — the roster has been replaced once already and every id named here
## was dead the next morning.
static func _rate_advanced(run: Dictionary, rid: String) -> int:
	var passives := {}
	for h in run.team:
		passives[String(GameData.heroes.get(String(h.id), {}).get("passive", ""))] = true
	match rid:
		"A01": return 9                                        # a whole extra action a turn
		"A02": return 8 if passives.has("quilled_hide") else 4  # Thorns need the Hedgehog
		"A03": return 8 if passives.has("cornered_fury") else 5 # the Boar pays in HP all day
		"A04": return 6
		"A05": return 8 if passives.has("ancient_warden") else 3  # Rituals are the Owl's
		"A06": return 7
	return 5


static func _pick_advanced(run: Dictionary, choice: Array) -> String:
	var best := ""
	var best_score := -1
	for rid_v in choice:
		var rid := String(rid_v)
		var sc := _rate_advanced(run, rid)
		if sc > best_score:
			best_score = sc
			best = rid
	return best


# ============================================================ non-battle nodes

static func _weakest_slot_of(hero: Dictionary) -> int:
	var best := 0
	var best_rank := 99
	for slot in GameData.SLOTS:
		var rank := _rarity_rank(String(hero.faces[slot])) + int(hero.face_mods[slot])
		if rank < best_rank:
			best_rank = rank
			best = slot
	return best


static func _weakest_slot(run: Dictionary) -> Array:
	var best := [0, 0]
	var best_rank := 99
	for hi in run.team.size():
		var hero: Dictionary = run.team[hi]
		for slot in GameData.SLOTS:
			var rank := _rarity_rank(String(hero.faces[slot])) + int(hero.face_mods[slot])
			if rank < best_rank:
				best_rank = rank
				best = [hi, slot]
	return best


static func _do_shop(run: Dictionary, rng: RandomNumberGenerator) -> void:
	var stock := RunState.gen_shop(run, rng)
	if stock.relic != "" and int(run.gold) >= int(GameData.balance.shop_prices.relic):
		run.gold = int(run.gold) - int(GameData.balance.shop_prices.relic)
		_add_relic(run, String(stock.relic))
	# buy the best rare+ face if affordable, replacing the weakest slot
	var best_face := ""
	var best_rank := 2
	for fid_v in stock.faces:
		var fid: String = fid_v
		var rank := _rarity_rank(fid)
		if rank > best_rank and int(run.gold) >= RunState.face_price(fid):
			best_rank = rank
			best_face = fid
	if best_face != "":
		run.gold = int(run.gold) - RunState.face_price(best_face)
		var w := _weakest_slot(run)
		RunState.apply_face_swap(run, w[0], w[1], best_face)
	var pi := 0
	while pi < stock.potions.size() and run.potions.size() < int(GameData.balance.potion_cap) \
			and int(run.gold) >= int(GameData.balance.shop_prices.potion):
		run.gold = int(run.gold) - int(GameData.balance.shop_prices.potion)
		run.potions.append(String(stock.potions[pi]))
		pi += 1


static func _do_rest(run: Dictionary) -> void:
	var total_pct := 0.0
	var alive := 0
	for h in run.team:
		if h.hp > 0:
			total_pct += float(h.hp) / int(h.max_hp)
			alive += 1
	var avg: float = total_pct / maxf(alive, 1.0)
	if avg < 0.75:
		var pct := int(GameData.balance.rest_heal_pct)
		var relic_pct := GameData.relic_value(run.relics, "rest_heal_pct")
		if relic_pct > 0:
			pct = relic_pct
		RunState.team_alive_heal_pct(run, pct)
	else:
		# forge the first hero's first forgeable slot
		for h in run.team:
			var slots := RunState.forgeable_slots(h)
			if slots.size() > 0:
				RunState.forge_face(h, slots[0])
				break


static func _do_treasure(run: Dictionary, rng: RandomNumberGenerator) -> void:
	var loot := RunState.gen_treasure(run, rng)
	if String(loot.kind) == "relic":
		_add_relic(run, String(loot.relic))
	else:
		# take the first face, replacing the weakest slot in the team
		var w := _weakest_slot(run)
		RunState.apply_face_swap(run, w[0], w[1], String(loot.faces[0]))


static func _do_event(run: Dictionary, rng: RandomNumberGenerator, out: Dictionary) -> void:
	if not run.has("seen_events"):
		run["seen_events"] = []
	var pool := []
	for eid in GameData.events:
		if eid not in run.seen_events:
			pool.append(eid)
	pool.sort()
	if pool.is_empty():
		return
	var eid: String = pool[rng.randi_range(0, pool.size() - 1)]
	run.seen_events.append(eid)
	match eid:
		"V01":
			RunState.team_alive_heal_flat(run, 8)
		"V02":
			var hi := rng.randi_range(0, run.team.size() - 1)
			var slot := rng.randi_range(0, GameData.SLOTS - 1)
			run.team[hi].face_extras[slot]["lucky"] = true
		"V03":
			pass   # sim never gambles
		"V04":
			for h in run.team:
				if h.hp > 0:
					h.hp = maxi(int(h.hp) - 4, 1)
			_add_relic(run, RunState.roll_relic(run, rng, "common"))
		"V05":
			run.gold = int(run.gold) + 15
		"V06":
			RunState.team_alive_heal_pct(run, 0)   # take the detour: skip row
			run.skip_row = true
		"V07":
			for h in run.team:
				var slots := RunState.forgeable_slots(h)
				if slots.size() > 0:
					RunState.forge_face(h, slots[0])
					break
		"V08":
			pass
		"V09":
			pass
		"V10":
			var hi2 := rng.randi_range(0, run.team.size() - 1)
			run.team[hi2].max_hp = int(run.team[hi2].max_hp) + 4
			run.team[hi2].hp = int(run.team[hi2].max_hp)
		"V11":
			run.gold = maxi(int(run.gold) - 40, 0)
		"V12":
			pass
