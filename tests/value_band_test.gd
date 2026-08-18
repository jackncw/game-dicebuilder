extends Node
## Value-band linter (round 13, suite 17). Every acquirable face must sit
## inside its category's rarity band, priced in one shared currency.
##
## The currency: 1 point = 1 HP of value. Every face key has a price
## (VALUES / RIDERS below); a face's effective value is the sum of what it
## gives, minus what it costs:
##
##   eff = Σ(component values) − 1×pain − 2×spell
##
## The 2×spell term IS the essence exchange rate ("1 靈息 ≈ +2 價值"): a face
## that costs X essence must deliver the free band PLUS 2X on top, or nobody
## has a reason to bank essence. `eff ∈ band` enforces both directions at
## once — a paid face that under-delivers falls below band_min, one that
## over-delivers rises above band_max. Same shape for pain (自損): the raw
## number may leave the band, the net must come back inside.
##
## Bands (task B1, 2026-08-18): attack C5-7 / R6-8 / E7-9, heal C4-5 / R5-6 /
## E6-7; defense mirrors attack; resource and control are calibrated so the
## shipped set sits mid-band. S (starting) faces are exempt from the cap —
## they are deliberately weak — but a starting face with a spell cost still
## has to clear the C-band floor plus 2X (the 月癒 rule: a paid face weaker
## than a free common is an inverted exchange rate).
##
## Faces whose main effect has no sane point price (twin_dance, wild …) must
## be WHITELISTED with a one-line reason. A whitelist entry for an id that no
## longer exists fails the suite — the list cannot quietly outlive the data.
##
## The suite also guards the round-13 pool structure: universal pool 10-12
## faces (<15% of the acquirable pool), class pools 10-14 each, essence faces
## ≥ 1/3 of the acquirable pool and ≥3 per class pool, unlock batches of 2-3
## per level, and class pool == unlock table (both directions).
##
##   godot --headless --path . res://tests/value_band_test.tscn

var fails := 0
var tests := 0

const BANDS := {
	"attack": {"C": [5, 7], "R": [6, 8], "E": [7, 9]},
	"defense": {"C": [5, 7], "R": [6, 8], "E": [7, 9]},
	"heal": {"C": [4, 5], "R": [5, 6], "E": [6, 7]},
	"resource": {"C": [4, 5], "R": [6, 8], "E": [7, 9]},
	"control": {"C": [3, 5], "R": [6, 8], "E": [7, 9]},
}

## Per-point prices for numeric keys.
const VALUES := {
	"atk": 1.0, "block": 1.0, "heal": 1.0, "thorns": 1.0,
	"team_block": 3.0, "team_heal": 3.0, "team_thorns": 3.0, "team_atk": 3.0,
	"regen": 2.0, "poison": 1.5, "burn": 1.5,
	"mana": 2.0, "rerolls": 4.0, "weaken": 2.0, "stun": 4.0,
	"heal_on_hit": 1.0, "buff_next_atk": 1.0, "next_dice_boost": 2.0,
	"echo": 1.0, "resonate": 0.5, "charge_up": 0.0, "vs_full": 0.5,
}

## Flat prices for boolean riders.
const RIDERS := {
	"pierce": 2.0, "cleave": 2.0, "lifesteal": 2.0, "combo": 2.0,
	"lucky": 1.0, "taunt": 1.0, "growth": 2.0,
	"cleanse_self": 1.0, "cleanse_target": 1.0, "expose": 3.0,
}

## Keys the currency cannot price — a face carrying one must be whitelisted.
const UNPRICED := ["twin_dance", "wild", "steal_die", "all_pierce",
	"thorns_double", "atk_from_block", "block_from_mana", "low_hp_atk",
	"resonate_req", "thorn_hold"]

## 合理越帶 whitelist — one line of reason each, read by the checks below.
const WHITELIST := {
	"hare_hawkeye": "L7 capstone:全隊穿透係行動經濟,唔係數值",
	"hedge_bristle": "L7 capstone:荊棘翻倍係引擎面,價值隨局面複利",
	"hedge_shieldbash": "L8 capstone:傷害=當前格擋,上限6,由格擋池定價",
	"owl_gather3": "梟 brief:最深靈息引擎,純資源面容許 C 帶 +1",
	"owl_essenceward": "條件面:格擋=靈息×2(上限6),價值隨池深浮動",
	"fox_twindance": "L7 capstone:雙舞係行動經濟,唔係數值",
	"fox_phantom": "L8 capstone:呼應條件先開火,1×4 食盡平加成",
	"boar_lastditch": "背水條件面:半血以下先值 9,半血以上收 5",
	"sp_die_theft": "狐 L7 capstone:搶敵骰係行動經濟,唔係數值",
}


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _is_essence_face(fd: Dictionary) -> bool:
	return float(fd.get("mana", 0)) > 0 or float(fd.get("spell", 0)) > 0


## Σ component values − pain − 2×spell, in points.
func _effective_value(fd: Dictionary) -> float:
	var v := 0.0
	var hits := maxf(1.0, float(fd.get("hits", 1)))
	for key in VALUES:
		if not fd.has(key):
			continue
		var amount := float(fd[key])
		if key == "atk":
			amount *= hits
			if fd.get("aoe", false):
				amount *= 2.0        # hits the whole line; ~2 live targets
		v += amount * float(VALUES[key])
	for key2 in RIDERS:
		if fd.get(key2, false):
			v += float(RIDERS[key2])
	if fd.has("random_atk"):
		var r: Array = fd.random_atk
		v += (float(r[0]) + float(r[1])) * 0.5
	v -= float(fd.get("pain", 0))
	v -= 2.0 * float(fd.get("spell", 0))
	return v


func _band_group(fd: Dictionary) -> String:
	var cat := String(fd.get("cat", "special"))
	return cat if BANDS.has(cat) else ""


func _ready() -> void:
	GameData.load_all()
	var ids := GameData.face_ids()

	# ---- the band rule, face by face
	for id in ids:
		var fd: Dictionary = GameData.faces[id]
		var rarity := String(fd.get("rarity", ""))
		if WHITELIST.has(id):
			continue
		var unpriced := []
		for k in UNPRICED:
			if fd.has(k):
				unpriced.append(k)
		if rarity == "S":
			# starting faces are exempt from the cap, but a paid one must
			# still clear C-band floor + 2×cost (subsumed by eff ≥ floor)
			if float(fd.get("spell", 0)) > 0 and unpriced.is_empty():
				var g := _band_group(fd)
				if g != "":
					var floor_c: float = BANDS[g]["C"][0]
					var eff_s := _effective_value(fd)
					_check(eff_s >= floor_c,
							"%s (S, spell %d) eff %.1f < C floor %.1f — 匯率倒掛:付費面弱過免費帶"
							% [id, int(fd.spell), eff_s, floor_c])
			continue
		_check(rarity in ["C", "R", "E"],
				"%s: rarity '%s' — U 已退役,可獲得面只准 C/R/E" % [id, rarity])
		if not (rarity in ["C", "R", "E"]):
			continue
		_check(unpriced.is_empty(),
				"%s carries unpriced key(s) %s — whitelist it with a reason" % [id, unpriced])
		if not unpriced.is_empty():
			continue
		var group := _band_group(fd)
		_check(group != "", "%s: cat '%s' has no band — whitelist or recategorise"
				% [id, String(fd.get("cat", ""))])
		if group == "":
			continue
		var band: Array = BANDS[group][rarity]
		var eff := _effective_value(fd)
		_check(eff >= float(band[0]) - 0.01 and eff <= float(band[1]) + 0.01,
				"%s (%s %s %s) eff %.1f outside band [%d, %d]"
				% [id, String(fd.get("zh", "")), group, rarity, eff, band[0], band[1]])

	# ---- whitelist staleness
	for wid in WHITELIST:
		_check(GameData.faces.has(wid),
				"whitelist entry %s no longer exists — delete the line" % wid)

	# ---- pool structure (tasks C / E / F)
	var universal := GameData.shared_pool()
	_check(universal.size() >= 10 and universal.size() <= 12,
			"universal pool is %d faces, want 10-12" % universal.size())
	var class_total := 0
	var essence_total := 0
	for uid in universal:
		if _is_essence_face(GameData.faces[uid]):
			essence_total += 1
	for hid in GameData.hero_ids():
		var pool: Array = GameData.class_pool(String(hid))
		class_total += pool.size()
		_check(pool.size() >= 10 and pool.size() <= 14,
				"%s class pool is %d faces, want 10-14" % [hid, pool.size()])
		var essence_here := 0
		for fid in pool:
			var fd2: Dictionary = GameData.faces[fid]
			_check(String(fd2.get("hero", "")) == String(hid),
					"%s is in %s's unlock table but hero-bound to '%s'"
					% [fid, hid, String(fd2.get("hero", ""))])
			if _is_essence_face(fd2):
				essence_here += 1
		essence_total += essence_here
		_check(essence_here >= 3,
				"%s class pool has %d essence faces, want ≥3" % [hid, essence_here])
		# every hero-bound C/R/E face must be reachable through the table
		for fid_all in ids:
			var fda: Dictionary = GameData.faces[fid_all]
			if String(fda.get("hero", "")) == String(hid) \
					and String(fda.get("rarity", "")) in ["C", "R", "E"]:
				_check(fid_all in pool,
						"%s is %s-bound and acquirable but in no unlock batch" % [fid_all, hid])
		# batches of 2-3 per level (task F)
		var unlocks: Dictionary = GameData.heroes[hid].get("unlocks", {})
		for lvl in unlocks:
			var batch = unlocks[lvl]
			_check(batch is Array and batch.size() >= 2 and batch.size() <= 3,
					"%s L%s batch is %s — want an array of 2-3 faces" % [hid, lvl, str(batch)])
	var acquirable := class_total + universal.size()
	_check(float(universal.size()) / float(acquirable) < 0.15,
			"universal pool is %.1f%% of the acquirable pool, want <15%%"
			% (100.0 * universal.size() / acquirable))
	_check(essence_total * 3 >= acquirable,
			"essence faces are %d of %d acquirable (%.1f%%), want ≥1/3"
			% [essence_total, acquirable, 100.0 * essence_total / acquirable])

	print("value_band_test: %d checks, %d failed (whitelisted: %d)" % [tests, fails, WHITELIST.size()])
	for wid2 in WHITELIST:
		if GameData.faces.has(wid2):
			print("  越帶白名單 %-20s %s" % [wid2, WHITELIST[wid2]])
	print("VALUEBAND %s" % ("OK" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails > 0 else 0)
