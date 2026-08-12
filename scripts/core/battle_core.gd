class_name BattleCore
extends RefCounted
## Pure battle logic engine. No scene-tree dependency: the Battle UI and the
## headless balance simulator both drive this class. All randomness goes
## through the injected RandomNumberGenerator. State lives in plain
## Dictionaries/Arrays so snapshots (undo) are a deep duplicate away.

const MANA_CAP := 10

## ── 同權守衛(第十一輪)──────────────────────────────────────────────
## The ONLY BattleCore surface the battle UI (screen_battle) and the simulator's
## policy layer (sim_runner) may call. 呢兩個名單就係「玩家做得到嘅事」嘅正式
## 定義:政策層唔准調用名單以外嘅引擎方法,亦唔准直接寫 `bc.s` —— 第十輪發現
## 模擬器用緊真人冇得用嘅 `toggle_lock`(釘骰),BALANCE.md 嘅數字因此高估咗
## 成隊人。`tests/api_parity_test.gd` 逐行掃兩邊 source,名單以外嘅調用即紅。
## 讀 state(`bc.s.…` 唔帶賦值)係允許嘅 —— UI 都係咁樣顯示嘢。
## 想俾政策層一個新能力?先問「玩家喺 UI 度做唔做到同一件事」,做到先好加。
const PLAYER_ACTIONS := [
	"setup", "use_face", "reroll", "buy_reroll", "use_potion", "undo",
	"end_turn", "end_turn_begin", "enemy_step", "end_turn_finish",
]
const PLAYER_QUERIES := [
	"can_use", "can_reroll", "can_buy_reroll", "can_undo", "rerolls_unlimited",
	"hero_can_act", "twin_available", "legal_targets",
	"hero_face", "die_face", "live_face", "live_die_face",
	"preview_attack", "spell_cost", "charge_stacks",
	"resonate_met", "resonate_would_match", "passive_of",
	"peek_enemy_action", "forecast_enemy", "forecast_target", "boss_forecast",
	"enemy_face_value", "alive_enemies", "alive_heroes", "targetable_dice",
	"drain_events",
]

## ── U1: natural regeneration ────────────────────────────────────────
## The party draws this much Essence at the start of every turn, unconditionally
## and for everybody.
##
## Before round 6 Essence was the Owl's private resource: the only reliable
## source was his Gather faces, so a party without him watched a meter that
## could not move and every Ritual face in the shared pool was a face they could
## not use. Making the pool fill on its own is what turns Essence from one
## character's mechanic into a currency the whole cast can be built around — the
## Badger's Essence Guard is worth putting on a die precisely because there is
## always something in the pool to have spent it on.
##
## It also, deliberately, feeds the Owl. See `WARDEN_OVERFLOW`.
const MANA_REGEN := 1

## ── U2: Essence into rerolls ────────────────────────────────────────
## Any time in your own phase, once a turn, trade Essence for a reroll.
##
## This is the floor under the whole resource: it means Essence is NEVER dead.
## A party with no Ritual faces at all still has somewhere to put it, so the
## regeneration above is a real gain for everyone rather than a number that
## accumulates in the corner of the screen. Once a turn, because unlimited
## conversion at a fixed rate is just a longer turn.
const ESSENCE_REROLL_COST := 2

## 靈息迴環 pays out only if this much is still in the pool at end of turn. Set
## above `MANA_REGEN + 1` so the relic rewards actually HOLDING Essence rather
## than paying out every turn for doing nothing.
const ESSENCE_LOOP_FLOOR := 3
const CARRY_BLOCK_CAP := 10   # 棘甲 / quilled_hide
const DICE := 2          # dice per hero (A / B)
const FACES := 6         # faces per die
## 蓄力 stops paying after this many turns in the lock.
const CHARGE_TURN_CAP := 3

var s := {}                 # full battle state
var rng: RandomNumberGenerator
var _snapshots: Array = [] # undo stack (state + rng state)
var events: Array = []     # drained by the UI for animation / logging


# ============================================================ setup

## team: array of hero dicts from RunState:
##   {id, hp, max_hp, level, faces:[12 ids], face_mods:[12 int],
##    face_plus:[12 int], face_extras:[12 dict]}
## Slots 0-5 are the A die, slots 6-11 the B die.
## enemy_keys: e.g. ["E01","E01"] or ["B1"] for a boss
## opts: {chapter:int, elite:bool, affix:String, relics:[], potions:[],
##        marsh_poison:int, imp_escort:bool}
func setup(team: Array, enemy_keys: Array, opts: Dictionary, p_rng: RandomNumberGenerator) -> void:
	GameData.load_all()
	rng = p_rng
	s = {
		"turn": 0,
		"over": false,
		"victory": false,
		"chapter": int(opts.get("chapter", 1)),
		"is_boss": false,
		"is_elite": bool(opts.get("elite", false)),
		"mana": 0,
		"essence_reroll_used": false,   # U2, once a turn
		"spell_cast_this_turn": false,  # 導靈杖, once a TURN (see `_start_turn`)
		"essence_loop_due": 0,          # 靈息迴環, paid at next turn start
		"rerolls": 0,
		"reroll_carry": 0,
		"relics": opts.get("relics", []).duplicate(),
		"potions": opts.get("potions", []).duplicate(),
		"heroes": [],
		"enemies": [],
		"attack_used_this_turn": false,
		"echo_bonus": 0,
		"team_atk_buff": 0,
		"drum": 0,             # A06: attack bonus built up this turn
		"twin_hero": -1,       # A01: the hero who claimed the twin-dice slot
		"steal_last": -1,      # B4: last hero index stolen from
		"announce": [],        # pending boss announcements this turn
		"run_atk_buff": int(opts.get("run_atk_buff", 0)),
		"all_pierce": false,   # 鷹眼: every party attack ignores Block this turn
	}
	for h in team:
		s.heroes.append(_make_hero(h))
	for key in enemy_keys:
		if key.begins_with("B"):
			s.is_boss = true
			s.enemies.append(_make_boss(key))
		else:
			s.enemies.append(_make_enemy(key, opts))
	if s.is_boss and s.enemies.size() == 1 and s.enemies[0].get("boss_key", "") == "B6":
		_b6_summon_start()
	_battle_start_effects(opts)
	_start_turn()


func _make_hero(h: Dictionary) -> Dictionary:
	GameData.migrate_hero(h)
	return {
		"id": h.id,
		# Passives are dispatched on this key, never on the id. Six characters
		# have already been replaced wholesale once; the id is a save-file
		# handle, not a rule.
		"passive": String(GameData.heroes.get(String(h.id), {}).get("passive", "")),
		"hp": int(h.hp), "max_hp": int(h.max_hp),
		"level": int(h.get("level", 1)),
		"block": 0, "down": int(h.hp) <= 0,
		"faces": h.faces.duplicate(),
		"face_mods": h.face_mods.duplicate(),
		"face_plus": h.face_plus.duplicate(),
		"face_extras": h.face_extras.duplicate(true),
		"cursed": [],          # slot indices blanked this battle
		# one entry per die: the rolled slot index (-1 = no die this turn)
		"rolled": [-1, -1],
		# 蓄力(第十輪重定義):逐個 slot 計嘅層數。回合結束時一個蓄力面仍然
		# 展示喺骰上而未被使用,就 +1 層(上限 CHARGE_TURN_CAP);使用後歸零。
		# 舊版靠「釘住粒骰」累積 —— 但釘骰從未接上任何 UI,真人根本做唔到,
		# 第十輪連引擎一齊清走。
		"face_charge": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"bound_die": -1,       # 束縛:本回合被封住嘅骰(-1 = 冇)
		"die_boost": [0, 0],           # 孤注, live this turn
		"die_boost_next": [0, 0],
		"twin_dance": false,           # 雙舞 claimed this turn
		"atk_now": 0,                  # 暴走, this turn only
		"thorn_hold": false,           # 堅守, skips this turn's Thorns decay
		"used": false,         # this hero has acted this turn
		"used_die": -1,        # the first die spent (kept for save/UI compatibility)
		"used_dice": [],       # every die spent this turn (two only with A01)
		"bound": false, "bound_next": false,
		"stolen": false,
		"poison": 0, "burn": [], "burn_new": [], "regen": 0, "thorns": 0,
		"weaken": 0, "weaken_next": 0, "expose": false, "expose_next": false,
		"taunt": false,
		"zanshin": 0,          # attack bonus active this turn (蓄勢 / Focus)
		"zanshin_next": 0,
	}


## The passive key of hero i, e.g. "quilled_hide". Empty when they have none.
func passive_of(i: int) -> String:
	return String(s.heroes[i].get("passive", ""))


func _has_passive(h: Dictionary, key: String) -> bool:
	return String(h.get("passive", "")) == key


## One global multiplier on every minion and boss HP pool.
##
## The bluntest knife in the drawer, and round 6 is exactly what it is for. U1
## and U2 made the party materially stronger on purpose — Essence regenerates
## for everybody and converts into rerolls in a game whose base reroll count is
## zero — and the acceptance bands did not move. Something had to absorb that,
## and the choice was between quietly clawing back the rules the round was
## commissioned to add, or letting the forest hit back harder. This is the
## second one: one number, applied identically everywhere, easy to read off
## BALANCE.md and easy to move again.
##
## It is deliberately NOT a damage multiplier. More enemy HP lengthens fights
## (avg turns had fallen to 4.09, the floor of the 4-6 band); more enemy damage
## would shorten them and kill parties faster, which is a different game.
## Per chapter, because one number could not do the job. At a flat 1.10 the
## first two chapters landed exactly where they should (87% / 67%) and the full
## clear fell to 28% — chapter 3 compounds, since its minions are already tier 3
## and its boss is the longest fight in the game, so the same multiplier costs
## far more there than it does in chapter 1. Splitting the dial is what the
## round-5 notes asked for in so many words: "a lever that is strong early and
## does not scale late". This is that lever, pointed the other way.
static func _world_hp(chapter: int) -> float:
	var m = GameData.balance.get("enemy_hp_mult", 1.0)
	if m is Dictionary:
		return float(m.get(str(clampi(chapter, 1, 3)), 1.0))
	return float(m)


func _make_enemy(key: String, opts: Dictionary) -> Dictionary:
	var def: Dictionary = GameData.enemies[key]
	var tier: int = clampi(int(opts.get("chapter", 1)), 1, 3)
	var ti := tier - 1
	var hp := int(round(def.hp[ti] * _world_hp(tier)))
	var affix: String = opts.get("affix", "") if opts.get("elite", false) else ""
	if affix != "":
		hp = int(floor(hp * float(GameData.balance.elite_hp_mult)))
	var faces := []
	for f in def.faces:
		for i in int(f.count):
			faces.append(_resolve_enemy_face(f, ti, affix))
	var e := {
		"key": key, "kind": "minion", "tier": tier,
		"zh": def.zh, "en": def.en,
		"hp": hp, "max_hp": hp, "block": 0,
		"dice": int(def.get("dice", 1)),
		"faces": faces,
		"rolls": [],           # [{face:Dictionary, cancelled:bool, done:bool}]
		"poison": 0, "burn": [], "burn_new": [], "regen": 0, "thorns": 0,
		"weaken": 0, "expose": false,
		"charge": 0,           # bonus to attack faces next turn
		"howl": 0,             # bone-wolf pack buff this turn
		"affix": affix,
		"passive": def.get("passive", {}),
		"dead": false,
	}
	if affix == "stoneskin":
		var extra: Dictionary = GameData.encounters.elite_affixes.stoneskin
		if e.passive.is_empty():
			e.passive = {"type": "start_block", "value": [extra.start_block, extra.start_block, extra.start_block]}
		else:
			e["affix_block"] = int(extra.start_block)
	return e


func _resolve_enemy_face(f: Dictionary, ti: int, affix := "") -> Dictionary:
	var out := {"id": f.id, "zh": f.zh, "en": f.en}
	for k in ["atk", "block", "heal", "poison", "burn", "weaken", "howl"]:
		if f.has(k):
			out[k] = int(f[k][ti]) if f[k] is Array else int(f[k])
	for k in ["pierce", "aoe", "bind", "curse", "pack_bonus", "boss_combo", "charge", "counter", "cancel_die", "mana_drain", "summon", "expose"]:
		if f.has(k):
			out[k] = f[k]
	if affix == "frenzied" and out.has("atk"):
		out.atk += int(GameData.encounters.elite_affixes.frenzied.atk_bonus)
	if affix == "venomous" and out.has("atk"):
		out["poison"] = int(out.get("poison", 0)) + int(GameData.encounters.elite_affixes.venomous.poison_on_hit)
	return out


## 任務1(第十輪)的分類器:一個敵方面「即時生效」若且唯若佢係純防禦/增益 ——
## 帶格擋/蓄力/反擊/嚎叫,而且完全冇任何指向玩家(或者盤面)的行動 key。混合
## 面(如果將來出現「攻擊+格擋」)整面留返結算階段,寧願格擋半邊冇用都唔好
## 令攻擊提早結算。治療刻意唔喺名單入面。
const _ENEMY_INSTANT_KEYS := ["block", "charge", "counter", "howl"]
const _ENEMY_ACT_KEYS := ["atk", "heal", "poison", "burn", "weaken", "bind",
	"curse", "expose", "mana_drain", "summon", "cancel_die"]


static func _enemy_face_instant(f: Dictionary) -> bool:
	var defensive := false
	for k in _ENEMY_INSTANT_KEYS:
		if f.has(k):
			defensive = true
	if not defensive:
		return false
	for k in _ENEMY_ACT_KEYS:
		if f.has(k):
			return false
	return true


func _make_boss(key: String) -> Dictionary:
	var def: Dictionary = GameData.bosses[key]
	var faces := []
	for f in def.faces:
		for i in int(f.count):
			faces.append(_resolve_enemy_face(f, 0))
	var e := {
		"key": key, "boss_key": key, "kind": "boss", "tier": int(def.chapter),
		"zh": def.zh, "en": def.en,
		"hp": int(round(def.hp * _world_hp(int(def.chapter)))),
		"max_hp": int(round(def.hp * _world_hp(int(def.chapter)))), "block": 0,
		"dice": int(def.dice),
		"faces": faces,
		"rolls": [],
		"poison": 0, "burn": [], "burn_new": [], "regen": 0, "thorns": 0,
		"weaken": 0, "expose": false,
		"charge": 0, "howl": 0, "affix": "",
		"passive": def.get("passive", {}),
		"gimmick": def.gimmick,
		"phase": 1,
		"atk_bonus": 0,        # B5 unarmored / phase bonuses
		"combo_count": 0,      # B2 attacks made this turn
		"counter": 0,          # B2 counter stance value this turn
		"dead": false,
	}
	return e


func _battle_start_effects(opts: Dictionary) -> void:
	# 古老守林者: the Owl Sage opens every fight with Essence on the board
	for h in s.heroes:
		if _has_passive(h, "ancient_warden") and not h.down:
			s.mana = mini(s.mana + 3, MANA_CAP)
	var start_essence := _relic("battle_start_mana")
	if start_essence > 0:
		s.mana = mini(s.mana + start_essence, MANA_CAP)
	var crown := _relic("thorn_crown")
	if crown > 0:
		for h in s.heroes:
			if not h.down:
				h.thorns += crown
	var marsh := int(opts.get("marsh_poison", 0))
	if marsh > 0:
		for h in s.heroes:
			if not h.down:
				h.poison += marsh


func _b6_summon_start() -> void:
	for i in 2:
		_b6_summon_one()


func _b6_summon_one() -> void:
	if s.enemies.size() >= 4:
		return
	var pool: Array = GameData.bosses.B6.summon_pool
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]
	var minion := _make_enemy(key, {"chapter": 3})
	s.enemies.append(minion)
	_ev({"t": "summon", "enemy": s.enemies.size() - 1})


# ============================================================ turn flow

func _start_turn() -> void:
	s.turn += 1
	s.attack_used_this_turn = false
	s.echo_bonus = 0
	s.team_atk_buff = 0
	s.drum = 0
	s.twin_hero = -1
	s.announce = []
	s["all_pierce"] = false
	_snapshots.clear()
	# rerolls
	var r := int(GameData.balance.base_rerolls)
	# `reroll_plus` and `reroll_carry` (below) have no relic behind them since
	# round 6 — 森林徽章 and 節拍器 became the two Essence relics, because U2
	# turned Essence itself into the party's reroll economy and made a flat
	# "+1 throw a battle" the most redundant thing in the common pool. The two
	# effect keys stay wired: they cost nothing, and they are how a future relic
	# or event would grant a throw again.
	r += _relic("reroll_plus")
	if s.turn == 1:
		r += _relic("first_turn_rerolls")
	r += int(s.reroll_carry)
	s.reroll_carry = 0
	s.rerolls = r
	# U1: the grove breathes. Everybody, every turn, no condition.
	s.mana = mini(s.mana + MANA_REGEN, MANA_CAP)
	# A05 森之心: the forest keeps feeding you
	var heart := _relic("forest_heart")
	if heart > 0:
		s.mana = mini(s.mana + heart, MANA_CAP)
	# 靈息迴環: a pool you did not spend down pays a dividend
	if int(s.get("essence_loop_due", 0)) > 0:
		s.mana = mini(s.mana + int(s.essence_loop_due), MANA_CAP)
	s["essence_loop_due"] = 0
	s.essence_reroll_used = false
	# 導靈杖's discount is a per-TURN allowance, so it re-arms here rather than
	# once a battle. It sits next to the U2 reset because they are the same kind
	# of thing: a once-a-turn allowance the player is meant to plan around.
	s["spell_cast_this_turn"] = false
	# hero turn-start upkeep — every die rolls fresh every turn(釘骰機制已
	# 於第十輪移除,冇任何面會跨回合保留)
	for h in s.heroes:
		for d in DICE:
			h.rolled[d] = -1
		h.die_boost = h.die_boost_next.duplicate()
		h.die_boost_next = [0, 0]
		h.twin_dance = false
		h.atk_now = 0
		h.used = false
		h.used_die = -1
		h.used_dice = []
		h.taunt = false
		h.weaken = h.weaken_next
		h.weaken_next = 0
		h.expose = h.expose_next
		h.expose_next = false
		h.bound = h.bound_next
		h.bound_next = false
		# 束縛(第十輪重定義):被束縛的英雄本回合隨機一顆骰不可用。粒骰照
		# 擲照顯示(玩家見到自己失去咗乜),但唔用得;可被淨化解開。
		h["bound_die"] = rng.randi_range(0, DICE - 1) if h.bound else -1
		h.zanshin = h.zanshin_next
		h.zanshin_next = 0
		if h.stolen:
			h.stolen = false   # stolen dice come back this turn
		# 老班長: the Badger's guard is up before anybody rolls
		if _has_passive(h, "old_sergeant") and not h.down:
			h.block += 2
	# boss gimmicks at turn start
	for e in s.enemies:
		if e.dead:
			continue
		e.howl = 0
		e.combo_count = 0
		e.counter = 0
		if e.kind == "boss":
			_boss_turn_start(e)
		var p: Dictionary = e.passive
		if not p.is_empty() and p.get("type", "") == "start_block":
			var v = p.value
			var blk := int(v[e.tier - 1]) if v is Array else int(v)
			if e.get("boss_key", "") == "B5" and e.phase == 2:
				blk = int(GameData.bosses.B5.unarmored_block)
			e.block += blk
		if e.has("affix_block"):
			e.block += int(e.affix_block)
	# roll enemy intents
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		if e.dead:
			continue
		e.rolls = []
		for d in int(e.dice):
			var face: Dictionary = e.faces[rng.randi_range(0, e.faces.size() - 1)].duplicate(true)
			if e.charge > 0 and face.has("atk"):
				face.atk += e.charge
			e.rolls.append({"face": face, "cancelled": false, "done": false})
		e.charge = 0
	enemy_instant_pass()
	# roll player dice — every die that did not stay pinned
	for i in s.heroes.size():
		for d in DICE:
			if int(s.heroes[i].rolled[d]) < 0:
				_roll_hero_die(i, d)
	_ev({"t": "turn_start", "turn": s.turn})


## 第十輪任務1:敵方防禦/增益面(格擋、蓄力、反擊架式、嚎叫)擲出嗰刻即時
## 生效。真人試玩揭發:呢啲面以前喺敵方結算階段先執行,而玩家攻擊全部喺
## 之前,回合尾又清 block —— 敵方格擋由出世到而家一點傷害都未擋過,反擊
## 架式一下都未反過。即時生效之後,玩家喺分配階段就睇住敵人嘅格擋值同反擊
## 姿態嚟落骰(穿刺面由此先有存在意義)。治療/攻擊/debuff/召喚照舊留喺敵方
## 結算階段 —— 即時回血會搞亂斬殺判斷。已生效嘅面標 done,結算階段自然跳
## 過;代價係佢哋唔再可以被暈眩/奪骰(已經生效,冇嘢好取消)。
## Public 係為咗測試可以 craft rolls 之後自己觸發;每回合 `_start_turn` 叫一次。
func enemy_instant_pass() -> void:
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		if e.dead:
			continue
		for d in e.rolls.size():
			var r: Dictionary = e.rolls[d]
			var f: Dictionary = r.face
			if r.done or r.cancelled or not _enemy_face_instant(f):
				continue
			r.done = true
			r["instant"] = true
			if f.has("block"):
				e.block += enemy_face_value(e, f, "block")
			if f.has("charge"):
				e.charge += int(f.charge)
			if f.has("counter"):
				e.counter = int(f.counter)
			if f.has("howl"):
				for k in s.enemies.size():
					var w: Dictionary = s.enemies[k]
					if not w.dead and w.key == "E07":
						w.howl += int(f.howl)
			_ev({"t": "enemy_instant", "enemy": i, "die": d, "face": f})


func _boss_turn_start(e: Dictionary) -> void:
	match e.get("boss_key", ""):
		"B1":
			if s.turn % 3 == 0:
				s.announce.append({"boss": e.key, "kind": "rage_combo", "hits": 2, "dmg": 6,
					"zh": "怒濤連擊", "en": "Raging Combo", "cancelled": false})
		"B6":
			if s.turn % 2 == 0:
				s.announce.append({"boss": e.key, "kind": "doom", "dmg": int(GameData.bosses.B6.doom_damage),
					"zh": "滅世咒", "en": "Doomsday", "cancelled": false})
		"B4":
			_b4_steal()


func _b4_steal() -> void:
	var candidates := []
	for i in s.heroes.size():
		var h: Dictionary = s.heroes[i]
		if not h.down and i != s.steal_last:
			candidates.append(i)
	if candidates.is_empty():
		return
	var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	s.heroes[pick].stolen = true
	s.steal_last = pick
	_ev({"t": "steal", "hero": pick})


func _roll_hero_die(i: int, d: int) -> void:
	var h: Dictionary = s.heroes[i]
	if h.down or h.stolen:
		h.rolled[d] = -1
		return
	var slot: int = d * FACES + rng.randi_range(0, FACES - 1)
	h.rolled[d] = slot
	_ev({"t": "roll", "hero": i, "die": d, "face": slot})
	var fd := hero_face(i, slot)
	if fd.get("lucky", false) and not _is_blank(h, slot):
		s.rerolls += 1
		_ev({"t": "lucky", "hero": i, "die": d})


func _is_blank(h: Dictionary, slot: int) -> bool:
	return slot in h.cursed or h.faces[slot] == "blank"


## A hero whose dice can still be rerolled: alive, present and not yet acted.
## (束縛唔再封重擲 —— 第十輪起佢封嘅係一顆骰的使用權,見 `can_use`。)
func _rerollable(h: Dictionary) -> bool:
	return not (h.down or h.stolen or h.used)


## Reroll both dice of every hero that has not acted yet; heroes who already
## acted are untouched entirely. Costs 1 reroll. 想保住一個好面?先用咗佢 ——
## 行動過的英雄唔會被重擲,呢個就係取代釘骰之後的「保面」方法。
## True while the reroll button should still work — 賭徒之骨 makes rerolls
## unlimited, so "how many are left" stops being the gate.
func rerolls_unlimited() -> bool:
	return _relic("gamblers_bone") > 0


func can_reroll() -> bool:
	return not s.over and (s.rerolls > 0 or rerolls_unlimited())


## U2: is the Essence-for-a-reroll trade available right now?
func can_buy_reroll() -> Dictionary:
	if s.over:
		return {"ok": false, "err": "over"}
	if bool(s.get("essence_reroll_used", false)):
		return {"ok": false, "err": "spent"}
	if int(s.mana) < ESSENCE_REROLL_COST:
		return {"ok": false, "err": "mana"}
	return {"ok": true}


## Take it. Buying does NOT reroll — it buys the throw, and the player still
## decides which dice to pin before spending it. Separating the two is what
## makes the trade a decision rather than a button that scrambles the table.
func buy_reroll() -> bool:
	if not can_buy_reroll().ok:
		return false
	s.mana -= ESSENCE_REROLL_COST
	s.rerolls += 1
	s.essence_reroll_used = true
	_ev({"t": "buy_reroll", "cost": ESSENCE_REROLL_COST})
	return true


func reroll() -> bool:
	if not can_reroll():
		return false
	var any := false
	for h in s.heroes:
		if not _rerollable(h):
			continue
		for d in DICE:
			if h.rolled[d] >= 0:
				any = true
	if not any:
		return false
	if rerolls_unlimited():
		# A04: the dice always turn, and the whole party pays for it
		for j in s.heroes.size():
			_hero_lose_hp(j, 1, "gamble")
			if s.over:
				return true
	else:
		s.rerolls -= 1
	for i in s.heroes.size():
		var h: Dictionary = s.heroes[i]
		if not _rerollable(h):
			continue
		for d in DICE:
			if h.rolled[d] < 0:
				continue
			_roll_hero_die(i, d)
	return true


## 蓄力層數(第十輪):slot 而唔係 die —— 層數跟住個面,重擲唔會洗走佢,
## 只有「使用」先歸零。回合結束時仍展示而未使用先會 +1(見結算)。
func charge_stacks(i: int, slot: int) -> int:
	if slot < 0:
		return 0
	return mini(int(s.heroes[i].face_charge[slot]), CHARGE_TURN_CAP)


# ============================================================ face access

## Merged face definition for hero i at slot idx (0-11): base + permanent mods
## + enchant extras. Values are NOT situationally buffed (see attack_value()).
func hero_face(i: int, idx: int) -> Dictionary:
	var h: Dictionary = s.heroes[i]
	if idx < 0 or _is_blank(h, idx):
		return {"id": "blank", "zh": "空白", "en": "Blank", "cat": "special", "target": "none",
			"blank": true, "slot": idx, "plus": 0}
	var base: Dictionary = GameData.faces[h.faces[idx]].duplicate(true)
	base["id"] = h.faces[idx]
	base["slot"] = idx
	base["plus"] = int(h.face_plus[idx])
	var extra: Dictionary = h.face_extras[idx]
	for k in extra:
		if extra[k] is bool or not base.has(k):
			base[k] = extra[k]
		else:
			base[k] = int(base[k]) + int(extra[k])
	var mod := int(h.face_mods[idx])
	base["mod"] = mod
	if mod != 0:
		for k in ["atk", "block", "heal", "mana"]:
			if base.has(k):
				base[k] = int(base[k]) + mod
				break
	return base


## The face currently showing on hero i's die d ({} if there is none).
func die_face(i: int, d: int) -> Dictionary:
	var slot: int = int(s.heroes[i].rolled[d])
	if slot < 0:
		return {}
	return hero_face(i, slot)


func _is_attack_face(fd: Dictionary) -> bool:
	return fd.has("atk") or fd.has("random_atk") or fd.has("atk_from_block")


## Does this attack ignore Block right now? Either the face itself pierces, or
## 鷹眼 has made everything the party throws this turn pierce.
func pierces(fd: Dictionary) -> bool:
	return fd.get("pierce", false) or bool(s.get("all_pierce", false))


## Is hero i's 呼應 condition satisfied for face fd? 第十輪重定義:讀嘅係同一
## 位英雄「另一顆骰本回合擲出」嘅面 —— 孖生骰而家展示緊乜,係玩家睇得到嘅
## 資訊,呼應 = 孖骰協同。舊版仲要求另一顆骰處於鎖定狀態;釘骰機制已移除。
func resonate_met(i: int, fd: Dictionary) -> bool:
	return resonate_would_match(i, fd)


## The actual test, kept under its historical name because the simulator and the
## UI hint both call it: does the face showing on the hero's other die match the
## named kind?
func resonate_would_match(i: int, fd: Dictionary) -> bool:
	var h: Dictionary = s.heroes[i]
	var slot := int(fd.get("slot", -1))
	if slot < 0:
		return false
	var other: int = 1 - (slot / FACES)
	if other < 0 or other >= DICE:
		return false
	var os := int(h.rolled[other])
	if os < 0 or _is_blank(h, os):
		return false
	var of := hero_face(i, os)
	match String(fd.get("resonate_cat", fd.get("resonate_req", "attack"))):
		"attack": return _is_attack_face(of)
		"block": return of.has("block") or of.has("block_from_mana")
		"heal": return of.has("heal") or of.has("team_heal")
		var other_cat: return String(of.get("cat", "")) == other_cat


## Essence overflow threshold for 古老守林者.
const WARDEN_OVERFLOW := 7


## Passive bonuses that lift every kind of value a face can carry, not just
## attack. Only the Owl has one: his storm brews while the party's Essence pool
## is full, which is what makes feeding the engine worth a die.
func passive_value_bonus(i: int) -> int:
	if _has_passive(s.heroes[i], "ancient_warden") and int(s.mana) >= WARDEN_OVERFLOW:
		return 2
	return 0


## Extra points this face earns from where it is sitting rather than from what
## it is: banked 蓄力 layers, a met 呼應, and any one-turn boost parked on the
## die by 孤注. Lands on the face's headline number only.
func face_bonus(i: int, fd: Dictionary) -> int:
	var h: Dictionary = s.heroes[i]
	var slot := int(fd.get("slot", -1))
	if slot < 0:
		return 0
	var d: int = slot / FACES
	if d < 0 or d >= DICE:
		return 0
	var v := int(h.die_boost[d])
	var cu := int(fd.get("charge_up", 0))
	if cu > 0:
		v += cu * charge_stacks(i, slot)
	if fd.has("resonate") and resonate_met(i, fd):
		v += int(fd.resonate)
		# 一唱一和: the Fox reads his own dice better than anyone
		if _has_passive(h, "call_and_answer"):
			v += 1
	return v


## Fully-buffed attack value for hero i using face fd (before enemy defenses).
func attack_value(i: int, fd: Dictionary, base_override := -1) -> int:
	var h: Dictionary = s.heroes[i]
	var v := int(fd.get("atk", 0)) if base_override < 0 else base_override
	# 背水 replaces the printed number outright once the user is at half HP
	if base_override < 0 and fd.has("low_hp_atk") and h.hp * 2 <= h.max_hp:
		v = int(fd.low_hp_atk) + int(fd.get("mod", 0))
	if fd.get("combo", false) and s.attack_used_this_turn:
		v += 2
	v += h.zanshin
	v += int(h.get("atk_now", 0))
	if _has_passive(h, "old_sergeant"):
		v += 1
	v += passive_value_bonus(i)
	if _has_passive(h, "cornered_fury") and h.hp * 2 <= h.max_hp:
		v += 2
	if _has_passive(h, "held_breath") and pierces(fd):
		v += 2
	v += face_bonus(i, fd)
	v += _relic("atk_plus")
	v += int(s.get("drum", 0))
	v += s.team_atk_buff
	v += s.get("run_atk_buff", 0)
	v -= h.weaken
	v += s.echo_bonus
	return maxi(v, 0)


func _block_value(i: int, fd: Dictionary, key := "block") -> int:
	var h: Dictionary = s.heroes[i]
	var v := int(fd.get(key, 0))
	if v > 0 and key == "block":
		v += _relic("block_plus")
	# the die's own bonus rides the headline number, and on a face that also
	# attacks the headline is the attack
	if key == "block" and not _is_attack_face(fd):
		v += face_bonus(i, fd)
	if v > 0:
		v += passive_value_bonus(i)
	v -= h.weaken
	if key == "block":
		v += s.echo_bonus
	return maxi(v, 0)


## Heal amount for hero i's face — same "headline number only" rule as Block.
func _heal_value(i: int, fd: Dictionary, key := "heal") -> int:
	var h: Dictionary = s.heroes[i]
	var v := int(fd.get(key, 0))
	if not _is_attack_face(fd) and not fd.has("block"):
		v += face_bonus(i, fd)
	if v > 0:
		v += passive_value_bonus(i)
	return maxi(v - int(h.weaken), 0) + s.echo_bonus


func _pain_value(fd: Dictionary) -> int:
	var p := int(fd.get("pain", 0))
	if p > 0:
		p = maxi(p - _relic("chalice"), 0)
	return p


## The face as it will ACTUALLY resolve for hero i, right now.
##
## `hero_face()` merges the data file with the run's permanent marks; this goes
## the rest of the way and folds in everything situational — Weaken, Charge
## banked in the lock, a met 呼應, passives, relics, 迴響, the die boosts. What
## comes back is a face dict of the same shape whose numbers are the numbers the
## engine is about to use.
##
## This exists so the UI never has to reimplement a rule to display it. The
## effect sentence in the cast strip and the shorthand pips under a die both take
## one of these and print `fd.atk` verbatim, which means a number on screen is
## wrong only if the engine is wrong.
##
## The three "up to N" faces keep their printed ceiling in `<key>_cap` and put
## what you would get right now in the key itself, because "≤6" and "4" are
## different pieces of information and the player wants the second one.
func live_face(i: int, fd: Dictionary) -> Dictionary:
	var out := fd.duplicate(true)
	if fd.get("blank", false):
		return out
	var h: Dictionary = s.heroes[i]
	if fd.has("atk"):
		out["atk"] = attack_value(i, fd)
	if fd.has("random_atk"):
		var r: Array = fd.random_atk
		out["random_atk"] = [attack_value(i, fd, int(r[0])), attack_value(i, fd, int(r[1]))]
	if fd.has("atk_from_block"):
		out["atk_from_block_cap"] = int(fd.atk_from_block)
		out["atk_from_block"] = attack_value(i, fd,
				mini(int(h.block), int(fd.atk_from_block)))
	if fd.has("block"):
		out["block"] = _block_value(i, fd)
	if fd.has("block_from_mana"):
		out["block_from_mana_cap"] = int(fd.block_from_mana)
		out["block_from_mana"] = mini(int(s.mana), int(fd.block_from_mana))
	if fd.has("team_block"):
		out["team_block"] = maxi(int(fd.team_block) + _relic("block_plus")
				- int(h.weaken), 0) + s.echo_bonus
	if fd.has("thorns_double"):
		out["thorns_double_cap"] = int(fd.thorns_double)
		out["thorns_double"] = mini(int(h.thorns), int(fd.thorns_double))
	if fd.has("heal"):
		out["heal"] = _heal_value(i, fd)
	if fd.has("team_heal"):
		out["team_heal"] = _heal_value(i, fd, "team_heal")
	if fd.has("poison"):
		out["poison"] = int(fd.poison) + _relic("poison_plus")
	if fd.has("burn"):
		out["burn"] = int(fd.burn) + _relic("burn_plus")
	if fd.has("mana") and not _is_attack_face(fd) and not fd.has("block") 			and not fd.has("heal"):
		out["mana"] = maxi(int(fd.mana) + face_bonus(i, fd), 0)
	if fd.has("spell"):
		out["spell"] = spell_cost(fd)
	if fd.has("pain"):
		out["pain"] = _pain_value(fd)
	return out


## Same, for whichever face is showing on hero i's die d ({} if there is none).
func live_die_face(i: int, d: int) -> Dictionary:
	var fd := die_face(i, d)
	if fd.is_empty():
		return fd
	return live_face(i, fd)


# ============================================================ usability / targets

## Can hero i act with die d this turn? A hero acts at most once per turn: the
## moment one die is spent the other is locked out until next turn.
func can_use(i: int, d: int) -> Dictionary:
	var h: Dictionary = s.heroes[i]
	if s.over:
		return {"ok": false, "err": "over"}
	if h.down:
		return {"ok": false, "err": "down"}
	if h.stolen:
		return {"ok": false, "err": "stolen"}
	if h.used:
		if d in h.get("used_dice", []):
			return {"ok": false, "err": "spent"}
		# 雙舞(第十輪重定義)buys the hero a second action with their other die
		var danced: bool = bool(h.get("twin_dance", false))
		if not danced and not twin_available(i):
			return {"ok": false, "err": "locked_out"}
	# 束縛:本回合被封住嗰顆骰唔用得(可被淨化解開)
	if d == int(h.get("bound_die", -1)):
		return {"ok": false, "err": "bound"}
	var slot: int = int(h.rolled[d])
	if slot < 0:
		return {"ok": false, "err": "no_roll"}
	if _is_blank(h, slot):
		return {"ok": false, "err": "blank"}
	var fd := hero_face(i, slot)
	if fd.has("spell") and s.mana < spell_cost(fd):
		return {"ok": false, "err": "mana"}
	# 絕影 and anything else gated on 呼應 simply cannot be spent until the
	# hero's other die is pinned on the right kind of face
	if fd.has("resonate_req") and not resonate_met(i, fd):
		return {"ok": false, "err": "resonate"}
	return {"ok": true, "face": fd}


## What this face actually costs to cast — 森之心 shaves a point off every
## Ritual, but never below 1.
func spell_cost(fd: Dictionary) -> int:
	if not fd.has("spell"):
		return 0
	var c := int(fd.spell)
	if _relic("forest_heart") > 0:
		c = maxi(c - 1, 1)
	# 導靈杖 Channeling Rod: the first Ritual of each TURN, not of each battle.
	# Queried rather than applied at payment time on purpose: `can_use` and the
	# UI both read this, so the discounted price is the price the player is
	# shown and the price the affordability check uses. Nothing can be greyed
	# out at a cost it will not actually charge.
	if not bool(s.get("spell_cast_this_turn", false)) and _relic("channeling_rod") > 0:
		c = maxi(c - _relic("channeling_rod"), 1)
	return c


## A01 雙月徽記: one hero a turn may spend BOTH dice. Nobody has claimed the
## slot until somebody actually spends a second die, so the player picks by
## playing rather than by declaring it up front.
func twin_available(i: int) -> bool:
	if _relic("twin_dice") <= 0:
		return false
	var tw := int(s.get("twin_hero", -1))
	return tw < 0 or tw == i


## True while hero i still has an action left this turn.
func hero_can_act(i: int) -> bool:
	for d in DICE:
		if can_use(i, d).ok:
			return true
	return false


## Target descriptor for the UI:
##   {type:"enemy"|"ally"|"enemy_die"|"none"|"wild", indices:[...]}
func legal_targets(i: int, d: int) -> Dictionary:
	var c := can_use(i, d)
	if not c.ok:
		return {"type": "none", "indices": []}
	var fd: Dictionary = c.face
	match String(fd.get("target", "none")):
		"enemy":
			return {"type": "enemy", "indices": alive_enemies()}
		"ally":
			var idx := []
			for j in s.heroes.size():
				idx.append(j)   # heal can target downed heroes (revive)
			return {"type": "ally", "indices": idx}
		"enemy_die":
			return {"type": "enemy_die", "indices": targetable_dice()}
		"wild":
			# copy any other die on the table this turn (own other die included)
			var srcs := []
			for j in s.heroes.size():
				var o: Dictionary = s.heroes[j]
				for od in DICE:
					if j == i and od == d:
						continue
					var src_slot: int = int(o.rolled[od])
					if src_slot < 0 or _is_blank(o, src_slot):
						continue
					if hero_face(j, src_slot).get("wild", false):
						continue
					srcs.append({"hero": j, "die": od})
			return {"type": "wild", "indices": srcs}
		_:
			return {"type": "none", "indices": []}


func alive_enemies() -> Array:
	var out := []
	for j in s.enemies.size():
		if not s.enemies[j].dead:
			out.append(j)
	return out


func alive_heroes() -> Array:
	var out := []
	for j in s.heroes.size():
		if not s.heroes[j].down:
			out.append(j)
	return out


## Enemy dice (and boss announcements) that can be stunned/stolen.
## Returns array of {enemy:int, die:int} ; die == -1 refers to announcement.
func targetable_dice() -> Array:
	var out := []
	for j in s.enemies.size():
		var e: Dictionary = s.enemies[j]
		if e.dead:
			continue
		for d in e.rolls.size():
			if not e.rolls[d].cancelled and not e.rolls[d].done:
				out.append({"enemy": j, "die": d})
	for a in s.announce.size():
		if not s.announce[a].cancelled and not bool(s.announce[a].get("done", false)):
			out.append({"enemy": _announce_owner(a), "die": -1 - a})
	return out


func _announce_owner(a_idx: int) -> int:
	var key: String = s.announce[a_idx].boss
	for j in s.enemies.size():
		if s.enemies[j].key == key:
			return j
	return 0


# ============================================================ use face

## d selects which of the hero's two dice is spent.
## params: {"target": int} for enemy/ally
##         {"die": {enemy, die}} for enemy_die faces (stun/steal)
##         {"die2": {enemy, die}} second stun target for Time Stop
##         {"copy_from": {hero, die}, ...} for wild (plus the copied face's params)
##         {"theft_target": int} enemy index for stolen attack faces
func use_face(i: int, d: int, params := {}) -> Dictionary:
	var c := can_use(i, d)
	if not c.ok:
		return c
	var fd: Dictionary = c.face
	if fd.get("wild", false):
		var src = params.get("copy_from", null)
		if not (src is Dictionary):
			return {"ok": false, "err": "need_copy"}
		var sh := int(src.get("hero", -1))
		var sd := int(src.get("die", -1))
		if sh < 0 or sh >= s.heroes.size() or sd < 0 or sd >= DICE:
			return {"ok": false, "err": "need_copy"}
		var src_slot: int = int(s.heroes[sh].rolled[sd])
		if src_slot < 0 or _is_blank(s.heroes[sh], src_slot):
			return {"ok": false, "err": "bad_copy"}
		fd = hero_face(sh, src_slot)
		if fd.get("wild", false):
			return {"ok": false, "err": "bad_copy"}
		if fd.has("spell") and s.mana < int(fd.spell):
			return {"ok": false, "err": "mana"}
		# A copy is not sitting where the original sat, so it inherits none of
		# the position-based bonuses — Charge belongs to the pinned die, and 呼應
		# reads the ORIGINAL owner's other die, which the copier does not have.
		for k in ["charge_up", "resonate", "resonate_cat", "resonate_req", "slot"]:
			fd.erase(k)
	_push_snapshot()
	var h: Dictionary = s.heroes[i]
	var second_die: bool = bool(h.used)
	h.used = true
	if int(h.used_die) < 0:
		h.used_die = d
	var spent: Array = h.get("used_dice", [])
	if d not in spent:
		spent.append(d)
	h["used_dice"] = spent
	# 雙舞's extra action is its own thing; it must not eat the Twin Moon Seal's
	# one-hero-a-turn slot as well.
	var danced: bool = second_die and bool(h.get("twin_dance", false))
	if second_die and not danced:
		s.twin_hero = i
	if fd.has("spell"):
		s.mana -= spell_cost(fd)
		s["spell_cast_this_turn"] = true
	# pain first (can down the user; effects still resolve)
	var pain := _pain_value(fd)
	if pain > 0:
		_hero_lose_hp(i, pain, "pain")
	var res := _resolve_player_face(i, fd, params)
	if not res.ok:
		var snap: Dictionary = _snapshots.pop_back()
		s = snap.state
		rng.state = snap.rng
		return res
	# growth: permanent +1 for this run (on the hero's own slot)
	var own_slot: int = int(h.rolled[d])
	var own := hero_face(i, own_slot)
	if own.get("growth", false):
		h.face_mods[own_slot] = int(h.face_mods[own_slot]) + 1
	# 蓄力歸零 AFTER the face resolves —— `face_bonus` 啱啱先讀完層數
	if own.has("charge_up"):
		h.face_charge[own_slot] = 0
	if _is_attack_face(fd):
		s.attack_used_this_turn = true
		# A06 獸王戰鼓 builds up *between* attacks: this one already resolved at
		# its own value, so the point banked here lands on the next attack.
		var drum := _relic("warlord_drum")
		if drum > 0:
			s.drum = int(s.get("drum", 0)) + drum
	# echo decays after the next face use
	if s.echo_bonus > 0 and not fd.has("echo"):
		s.echo_bonus = 0
	if fd.has("echo"):
		s.echo_bonus = int(fd.echo)
	_check_end()
	return {"ok": true}


func _resolve_player_face(i: int, fd: Dictionary, params: Dictionary) -> Dictionary:
	var h: Dictionary = s.heroes[i]
	var tgt_type := String(fd.get("target", "none"))
	# ---- dispatch
	if fd.get("steal_die", false):
		return _do_die_theft(i, params)
	if fd.has("stun"):
		return _do_stun(i, fd, params)
	if _is_attack_face(fd):
		var base := -1
		if fd.has("random_atk"):
			base = rng.randi_range(int(fd.random_atk[0]), int(fd.random_atk[1]))
			base += int(fd.get("mod", 0))
			_ev({"t": "gambit", "hero": i, "value": base})
		elif fd.has("atk_from_block"):
			# 盾擊: the shield you are already holding IS the weapon. It is not
			# spent — the Block stays up for the enemy phase.
			base = mini(int(h.block), int(fd.atk_from_block))
		if fd.get("aoe", false):
			_attack_enemies(i, fd, alive_enemies(), base)
		else:
			var t := int(params.get("target", -1))
			if t < 0 or t >= s.enemies.size() or s.enemies[t].dead:
				return {"ok": false, "err": "need_target"}
			var targets := [t]
			if fd.get("cleave", false):
				targets = _cleave_targets(t)
			_attack_enemies(i, fd, targets, base)
	elif fd.has("poison") and fd.get("aoe", false):
		# pure poison sweeps (Spore Cloud / Plague Burst)
		for j in alive_enemies():
			_apply_poison(s.enemies[j], int(fd.poison))
	elif fd.has("poison") and tgt_type == "enemy":
		var t := int(params.get("target", -1))
		if t < 0 or s.enemies[t].dead:
			return {"ok": false, "err": "need_target"}
		_apply_poison(s.enemies[t], int(fd.poison))
	elif fd.has("burn") and fd.get("aoe", false):
		# burn sweeps with no attack component (Smolder)
		var b := int(fd.burn) + _relic("burn_plus")
		for j in alive_enemies():
			s.enemies[j].burn_new.append(b)
	# ---- non-attack enemy debuffs (weaken / expose without atk)
	if (fd.has("weaken") or fd.get("expose", false)) and not _is_attack_face(fd) and not fd.has("stun"):
		if fd.get("aoe", false):
			for j in alive_enemies():
				_debuff_enemy(j, fd)
		elif tgt_type == "enemy":
			var t := int(params.get("target", -1))
			if t < 0 or s.enemies[t].dead:
				return {"ok": false, "err": "need_target"}
			_debuff_enemy(t, fd)
	# ---- self / team effects
	if fd.has("block"):
		h.block += _block_value(i, fd)
	if fd.has("block_from_mana"):
		# 靈息護體: reads the pool, does not drain it
		h.block += mini(int(s.mana), int(fd.block_from_mana))
	if fd.has("thorns_double"):
		# 豎刺 doubles what is already there — on zero Thorns it does nothing,
		# which is the cost of the face being free otherwise
		h.thorns += mini(int(h.thorns), int(fd.thorns_double))
	if fd.get("thorn_hold", false):
		h.thorn_hold = true
	if fd.has("team_atk"):
		s.team_atk_buff += int(fd.team_atk)
	if fd.has("self_atk_now"):
		h.atk_now = int(h.get("atk_now", 0)) + int(fd.self_atk_now)
	if fd.get("all_pierce", false):
		s["all_pierce"] = true
	if fd.get("twin_dance", false):
		h.twin_dance = true
	if fd.has("next_dice_boost"):
		for d2 in DICE:
			h.die_boost_next[d2] = int(h.die_boost_next[d2]) + int(fd.next_dice_boost)
	if fd.has("team_block"):
		var v := int(fd.team_block) + _relic("block_plus")
		v = maxi(v - h.weaken, 0) + s.echo_bonus
		for j in alive_heroes():
			s.heroes[j].block += v
	if fd.has("thorns"):
		h.thorns += int(fd.thorns)
	if fd.has("team_thorns"):
		for j in alive_heroes():
			s.heroes[j].thorns += int(fd.team_thorns)
	if fd.get("taunt", false):
		h.taunt = true
	if fd.has("mana"):
		var gain := int(fd.mana)
		# Same "headline number only" rule Block and Heal follow: when Essence is
		# what the face is FOR, it takes the die's positional bonus — the Charge
		# banked in the lock, a met 呼應, a 換位 boost. That is what makes 引靈瞄準
		# ("Essence +1, and +1 more per Charge layer") a rule rather than a
		# special case: it is `mana: 1, charge_up: 1`, and this line is the whole
		# of its implementation.
		if not _is_attack_face(fd) and not fd.has("block") and not fd.has("heal"):
			gain += face_bonus(i, fd)
		s.mana = mini(s.mana + maxi(gain, 0), MANA_CAP)
	if fd.has("rerolls"):
		s.rerolls += int(fd.rerolls)
	if fd.has("buff_next_atk"):
		h.zanshin_next += int(fd.buff_next_atk)
	if fd.get("cleanse_self", false):
		_cleanse(h)
	# ---- heals
	if fd.has("heal") and tgt_type == "ally":
		var t := int(params.get("target", -1))
		if t < 0 or t >= s.heroes.size():
			return {"ok": false, "err": "need_target"}
		_heal_hero(t, _heal_value(i, fd))
		if fd.get("cleanse_target", false):
			_cleanse(s.heroes[t])
	if fd.has("self_heal"):
		_heal_hero(i, int(fd.self_heal))
	if fd.has("team_heal"):
		var amt := _heal_value(i, fd, "team_heal")
		for j in alive_heroes():
			_heal_hero(j, amt)
	if fd.has("regen") and tgt_type == "ally":
		var t := int(params.get("target", i))
		if t < 0 or t >= s.heroes.size() or s.heroes[t].down:
			return {"ok": false, "err": "need_target"}
		s.heroes[t].regen += int(fd.regen)
	if fd.has("team_regen"):
		for j in alive_heroes():
			s.heroes[j].regen += int(fd.team_regen)
	return {"ok": true}


func _cleave_targets(t: int) -> Array:
	var alive := alive_enemies()
	var pos := alive.find(t)
	var out := [t]
	if pos > 0:
		out.append(alive[pos - 1])
	if pos >= 0 and pos < alive.size() - 1:
		out.append(alive[pos + 1])
	return out


func _debuff_enemy(j: int, fd: Dictionary) -> void:
	var e: Dictionary = s.enemies[j]
	if fd.has("weaken"):
		e.weaken += int(fd.weaken)
		_apply_enemy_weaken(e)
	if fd.get("expose", false):
		e.expose = true
	_ev({"t": "debuff", "enemy": j})


## Weaken lowers the enemy's *rolled* face values immediately (visible).
func _apply_enemy_weaken(e: Dictionary) -> void:
	for r in e.rolls:
		var f: Dictionary = r.face
		f["weakened"] = e.weaken


func enemy_face_value(e: Dictionary, f: Dictionary, key: String) -> int:
	var v := int(f.get(key, 0))
	if key in ["atk", "block", "heal"]:
		v = maxi(v - int(e.weaken), 0)
	return v


## Resolve one attack face. `hits` (the "X×N" faces) repeats the whole strike
## N times: each pass is blocked separately, and each pass eats Thorns and
## Counter again. That is the point of the keyword — it is superb into naked
## HP and miserable into armour. Riders (poison / burn / weaken / expose) are
## applied on the first pass only, so a multi-hit face does not quietly stack
## its debuff N times.
func _attack_enemies(i: int, fd: Dictionary, targets: Array, base_override := -1) -> void:
	var total_dealt := 0
	var v := attack_value(i, fd, base_override)
	var pierced: bool = pierces(fd)
	var passes := maxi(int(fd.get("hits", 1)), 1)
	for pass_i in passes:
		for j in targets:
			var e: Dictionary = s.enemies[j]
			if e.dead:
				continue
			var dmg := v
			if e.expose:
				dmg = int(ceil(dmg * 1.5))
			var blocked := 0
			if not pierced:
				blocked = mini(e.block, dmg)
				e.block -= blocked
			var hp_loss: int = mini(dmg - blocked, e.hp)
			e.hp -= hp_loss
			total_dealt += hp_loss
			_ev({"t": "hit", "src": i, "enemy": j, "dmg": dmg, "blocked": blocked, "hp_loss": hp_loss})
			if pass_i == 0:
				if fd.has("poison"):
					_apply_poison(e, int(fd.poison))
				if fd.has("burn"):
					var b := int(fd.burn) + _relic("burn_plus")
					e.burn_new.append(b)
				if fd.has("weaken"):
					e.weaken += int(fd.weaken)
					_apply_enemy_weaken(e)
				if fd.get("expose", false):
					e.expose = true
			# thorns retaliation (ignores hero block)
			if e.thorns > 0 or (not e.passive.is_empty() and e.passive.get("type", "") == "thorns"):
				var th := int(e.thorns)
				if not e.passive.is_empty() and e.passive.get("type", "") == "thorns":
					var pv = e.passive.value
					th += int(pv[e.tier - 1]) if pv is Array else int(pv)
				if th > 0:
					_hero_lose_hp(i, th, "thorns")
			# B2 counter stance
			if e.get("counter", 0) > 0 and e.hp > 0:
				_hero_lose_hp(i, int(e.counter), "counter")
			if e.hp <= 0:
				_kill_enemy(j)
			if s.over:
				break
		if s.over:
			break
	if fd.get("lifesteal", false) and total_dealt > 0:
		# A03 血之聖杯 turns the sip into a full drink
		var rate := 1.0 if _relic("chalice") > 0 else 0.5
		_heal_hero(i, int(floor(total_dealt * rate)))
	# 嗜血擊: a flat top-up, but only if the blow actually reached HP
	if fd.has("heal_on_hit") and total_dealt > 0:
		_heal_hero(i, int(fd.heal_on_hit))


func _apply_poison(e_or_h: Dictionary, amount: int) -> void:
	var amt := amount
	if e_or_h.has("kind"):
		amt += _relic("poison_plus")
	e_or_h.poison += amt


func _kill_enemy(j: int) -> void:
	var e: Dictionary = s.enemies[j]
	if e.kind == "boss" and e.get("boss_key", "") == "B3" and e.phase == 1:
		# Sir Croak dismounts
		e.phase = 2
		# through the world multiplier, like every other pool in the game — B3's
		# second phase is a fresh HP bar, and a fresh bar that skipped the dial
		# would make him the one boss the difficulty setting does not touch
		e.hp = int(round(GameData.bosses.B3.phase2_hp * _world_hp(int(GameData.bosses.B3.chapter))))
		e.max_hp = e.hp
		e.dice = int(GameData.bosses.B3.phase2_dice)
		var faces := []
		for f in GameData.bosses.B3.phase2_faces:
			for k in int(f.count):
				faces.append(_resolve_enemy_face(f, 0))
		e.faces = faces
		e.block = 0
		e.poison = 0
		e.burn = []
		e.burn_new = []
		e.weaken = 0
		e.expose = false
		e.thorns = 0
		e.rolls = []   # loses remaining dice this turn
		_ev({"t": "boss_phase", "enemy": j})
		return
	e.dead = true
	e.hp = 0
	e.rolls = []
	_ev({"t": "enemy_die", "enemy": j})
	# cancel announcements from this boss
	for a in s.announce:
		if a.boss == e.key:
			a.cancelled = true


func _do_stun(i: int, fd: Dictionary, params: Dictionary) -> Dictionary:
	var picks := []
	if params.has("die"):
		picks.append(params.die)
	if params.has("die2") and int(fd.get("stun", 1)) > 1:
		picks.append(params.die2)
	if picks.is_empty():
		return {"ok": false, "err": "need_target"}
	for p in picks:
		var ej := int(p.enemy)
		var dj := int(p.die)
		if dj < 0:
			var a_idx := -1 - dj
			if a_idx < s.announce.size():
				s.announce[a_idx].cancelled = true
				_ev({"t": "stun_announce", "announce": a_idx})
		else:
			if ej >= s.enemies.size() or dj >= s.enemies[ej].rolls.size():
				return {"ok": false, "err": "bad_target"}
			s.enemies[ej].rolls[dj].cancelled = true
			_ev({"t": "stun", "enemy": ej, "die": dj})
		# rider debuffs (Freeze / Quell weaken the die's owner)
		if fd.has("weaken") and ej >= 0 and ej < s.enemies.size():
			var e: Dictionary = s.enemies[ej]
			e.weaken += int(fd.weaken)
			_apply_enemy_weaken(e)
	return {"ok": true}


func _do_die_theft(i: int, params: Dictionary) -> Dictionary:
	if not params.has("die"):
		return {"ok": false, "err": "need_target"}
	var ej := int(params.die.enemy)
	var dj := int(params.die.die)
	if dj < 0 or ej >= s.enemies.size() or dj >= s.enemies[ej].rolls.size():
		return {"ok": false, "err": "bad_target"}
	var roll: Dictionary = s.enemies[ej].rolls[dj]
	if roll.cancelled or roll.done:
		return {"ok": false, "err": "bad_target"}
	roll.cancelled = true
	var f: Dictionary = roll.face
	var e_src: Dictionary = s.enemies[ej]
	_ev({"t": "die_theft", "enemy": ej, "die": dj})
	if f.has("atk"):
		var t := int(params.get("theft_target", ej))
		if t >= s.enemies.size() or s.enemies[t].dead:
			t = ej
		var pseudo := {"atk": enemy_face_value(e_src, f, "atk"), "target": "enemy"}
		if f.get("pierce", false):
			pseudo["pierce"] = true
		if f.get("aoe", false):
			pseudo["aoe"] = true
			_attack_enemies(i, pseudo, alive_enemies())
		else:
			_attack_enemies(i, pseudo, [t])
	if f.has("block"):
		s.heroes[i].block += enemy_face_value(e_src, f, "block")
	if f.has("heal"):
		_heal_hero(i, enemy_face_value(e_src, f, "heal"))
	return {"ok": true}


# ============================================================ hero hp

func _heal_hero(j: int, amount: int) -> void:
	if amount <= 0:
		return
	var h: Dictionary = s.heroes[j]
	if h.down:
		h.down = false
		h.hp = mini(amount, h.max_hp)
		_ev({"t": "revive", "hero": j, "hp": h.hp})
		return
	var missing: int = h.max_hp - h.hp
	var applied := mini(amount, missing)
	h.hp += applied
	var overflow := amount - applied
	if overflow > 0:
		h.block += int(floor(overflow * float(GameData.balance.overheal_block_pct) / 100.0))
	_ev({"t": "heal", "hero": j, "amount": applied, "overflow": overflow})


func _hero_lose_hp(j: int, amount: int, kind := "dmg") -> void:
	if amount <= 0:
		return
	var h: Dictionary = s.heroes[j]
	if h.down:
		return
	h.hp -= amount
	_ev({"t": "hero_hp_loss", "hero": j, "amount": amount, "kind": kind})
	if h.hp <= 0:
		_down_hero(j)


func _down_hero(j: int) -> void:
	var h: Dictionary = s.heroes[j]
	h.hp = 0
	h.down = true
	h.block = 0
	h.poison = 0
	h.burn = []
	h.burn_new = []
	h.regen = 0
	h.thorns = 0
	h.weaken = 0
	h.expose = false
	h.taunt = false
	h.rolled = [-1, -1]
	h.used = true
	h.used_die = -1
	h["used_dice"] = [0, 1]
	_ev({"t": "hero_down", "hero": j})
	_check_end()


func _cleanse(h: Dictionary) -> void:
	h.poison = 0
	h.burn = []
	h.burn_new = []
	h.weaken = 0
	h.weaken_next = 0
	h.expose = false
	h.expose_next = false
	# 束縛可被淨化移除(第十輪):今回合封住嘅骰即時解封,下回合嘅都拆埋
	h.bound = false
	h.bound_next = false
	h["bound_die"] = -1


# ============================================================ potions

func use_potion(slot: int, params := {}) -> Dictionary:
	if s.over or slot < 0 or slot >= s.potions.size():
		return {"ok": false, "err": "bad_slot"}
	var pid: String = s.potions[slot]
	var pd: Dictionary = GameData.potions[pid]
	_push_snapshot()
	match String(pd.effect):
		"heal":
			var t := int(params.get("target", -1))
			if t < 0 or t >= s.heroes.size():
				_snapshots.pop_back()
				return {"ok": false, "err": "need_target"}
			_heal_hero(t, int(pd.value))
		"team_heal":
			for j in alive_heroes():
				_heal_hero(j, int(pd.value))
		"rerolls":
			s.rerolls += int(pd.value)
		"poison_all":
			for j in alive_enemies():
				_apply_poison(s.enemies[j], int(pd.value))
		"team_block":
			for j in alive_heroes():
				s.heroes[j].block += int(pd.value)
		"team_atk_buff":
			s.team_atk_buff += int(pd.value)
	s.potions.remove_at(slot)
	_ev({"t": "potion", "id": pid})
	_check_end()
	return {"ok": true}


# ============================================================ undo

func _push_snapshot() -> void:
	_snapshots.append({"state": s.duplicate(true), "rng": rng.state})


func can_undo() -> bool:
	return not _snapshots.is_empty() and not s.over


func undo() -> bool:
	if not can_undo():
		return false
	var snap: Dictionary = _snapshots.pop_back()
	s = snap.state
	rng.state = snap.rng
	_ev({"t": "undo"})
	return true


# ============================================================ enemy resolution / end turn

## Resolve the whole enemy phase in one call. The simulator and the headless
## tests want it this way; the battle screen drives the same work one action at
## a time through the three functions below so it can put a beat between them.
func end_turn() -> void:
	if s.over:
		return
	end_turn_begin()
	while not s.over:
		if enemy_step().is_empty():
			break
	if s.over:
		return
	end_turn_finish()


## Close the player's half of the turn. After this the enemy phase is live and
## every pending intent is queued; nothing has resolved yet.
func end_turn_begin() -> void:
	if s.over:
		return
	_snapshots.clear()
	s["enemy_phase"] = true


## The next enemy action, WITHOUT resolving it — this is what lets the UI light
## up the acting enemy and fly its intent chip at the target before any damage
## lands. Enemies act left to right, dice in rolled order, boss announcements
## last.
##   {kind:"die", enemy:int, die:int, face:Dictionary}
##   {kind:"announce", index:int, enemy:int, announce:Dictionary}
##   {} once the phase is spent
func peek_enemy_action() -> Dictionary:
	if s.over:
		return {}
	for j in s.enemies.size():
		var e: Dictionary = s.enemies[j]
		if e.dead:
			continue
		for d in e.rolls.size():
			var r: Dictionary = e.rolls[d]
			if r.cancelled or r.done:
				continue
			return {"kind": "die", "enemy": j, "die": d, "face": r.face}
	for a in s.announce.size():
		var an: Dictionary = s.announce[a]
		if an.cancelled or bool(an.get("done", false)):
			continue
		var owner := _announce_owner_alive(an)
		if owner < 0:
			continue    # the boss died before its own announcement landed
		return {"kind": "announce", "index": a, "enemy": owner, "announce": an}
	return {}


## Resolve exactly one enemy action and return what it was ({} when done).
func enemy_step() -> Dictionary:
	var nxt := peek_enemy_action()
	if nxt.is_empty():
		return {}
	if String(nxt.kind) == "die":
		var e: Dictionary = s.enemies[int(nxt.enemy)]
		var roll: Dictionary = e.rolls[int(nxt.die)]
		roll.done = true
		_execute_enemy_face(int(nxt.enemy), roll.face)
		return nxt
	var a: Dictionary = s.announce[int(nxt.index)]
	a["done"] = true
	var j := int(nxt.enemy)
	match String(a.kind):
		"rage_combo":
			for k in int(a.hits):
				_enemy_attack_heroes(j, {"atk": int(a.dmg)}, false)
				if s.over:
					break
		"doom":
			_enemy_attack_heroes(j, {"atk": int(a.dmg), "aoe": true, "pierce": false}, false)
	return nxt


## Poison/burn/regen ticks, block clear, and the next turn's roll.
func end_turn_finish() -> void:
	if s.over:
		return
	s["enemy_phase"] = false
	_end_of_turn_settlement()
	if not s.over:
		_start_turn()


## When this boss's signature announced attack next goes off, for the forecast
## card: {kind, zh, en, dmg, hits, turns} — turns 0 means "it is already
## announced and lands at the end of THIS turn". {} for bosses without one.
func boss_forecast(e: Dictionary) -> Dictionary:
	var period := 0
	var info := {}
	match String(e.get("boss_key", "")):
		"B1":
			period = 3
			info = {"kind": "rage_combo", "zh": "怒濤連擊", "en": "Raging Combo",
				"dmg": 6, "hits": 2}
		"B6":
			period = int(GameData.bosses.B6.get("doom_turns", 2))
			info = {"kind": "doom", "zh": "滅世咒", "en": "Doomsday",
				"dmg": int(GameData.bosses.B6.doom_damage), "hits": 1}
		_:
			return {}
	for a in s.announce:
		if String(a.get("kind", "")) == String(info.kind) and not a.cancelled 				and not bool(a.get("done", false)):
			info["turns"] = 0
			return info
	var rem: int = period - (int(s.turn) % period)
	info["turns"] = period if rem == 0 else rem
	return info


func _announce_owner_alive(a: Dictionary) -> int:
	for j in s.enemies.size():
		if s.enemies[j].key == a.boss and not s.enemies[j].dead:
			return j
	return -1


func _execute_enemy_face(j: int, f: Dictionary) -> void:
	var e: Dictionary = s.enemies[j]
	_ev({"t": "enemy_act", "enemy": j, "face": f})
	if f.has("atk"):
		_enemy_attack_heroes(j, f, true)
	if f.has("block"):
		e.block += enemy_face_value(e, f, "block")
	if f.has("heal"):
		var v := enemy_face_value(e, f, "heal")
		e.hp = mini(e.hp + v, e.max_hp)
	if f.has("weaken") and not f.has("atk"):
		var t := _enemy_pick_target()
		if t >= 0:
			s.heroes[t].weaken_next += enemy_face_value(e, f, "weaken")
			_ev({"t": "hero_weakened", "hero": t})
	if f.has("poison") and not f.has("atk"):
		if f.get("aoe", false):
			for t in alive_heroes():
				s.heroes[t].poison += int(f.poison)
		else:
			var t := _enemy_pick_target()
			if t >= 0:
				s.heroes[t].poison += int(f.poison)
	if f.has("bind"):
		var t := _enemy_pick_target()
		if t >= 0:
			s.heroes[t].bound_next = true
			_ev({"t": "hero_bound", "hero": t})
	if f.has("curse"):
		_do_curse()
	if f.get("expose", false) and not f.has("atk"):
		var t := _enemy_pick_target()
		if t >= 0:
			s.heroes[t].expose = true
			s.heroes[t].expose_next = true
	if f.has("howl"):
		for k in s.enemies.size():
			var w: Dictionary = s.enemies[k]
			if not w.dead and w.key == "E07":
				w.howl += int(f.howl)
	if f.has("charge"):
		e.charge += int(f.charge)
	if f.has("counter"):
		e.counter = int(f.counter)
	if f.has("cancel_die"):
		var cands := []
		for k in s.heroes.size():
			var h: Dictionary = s.heroes[k]
			if h.down or h.used or h.stolen:
				continue
			for d2 in DICE:
				if int(h.rolled[d2]) >= 0:
					cands.append(k)
					break
		if not cands.is_empty():
			var pick: int = cands[rng.randi_range(0, cands.size() - 1)]
			s.heroes[pick].used = true
			_ev({"t": "die_cancelled", "hero": pick})
	if f.has("mana_drain"):
		s.mana = maxi(s.mana - int(f.mana_drain), 0)
	if f.has("summon"):
		var alive := 0
		for k in s.enemies.size():
			if not s.enemies[k].dead and s.enemies[k].kind == "minion":
				alive += 1
		if alive < 2:
			_b6_summon_one()


func _enemy_pick_target() -> int:
	var alive := alive_heroes()
	if alive.is_empty():
		return -1
	for j in alive:
		if s.heroes[j].taunt:
			return j
	return alive[rng.randi_range(0, alive.size() - 1)]


func _enemy_attack_heroes(j: int, f: Dictionary, allow_riders: bool) -> void:
	var e: Dictionary = s.enemies[j]
	var base := enemy_face_value(e, f, "atk")
	# wolf pack bite bonus
	if f.get("pack_bonus", 0) and _wolf_attacked_before(j):
		base += int(f.pack_bonus)
	base += int(e.howl)
	# B2 combo chain: each attack this turn +1 more than the last
	if e.get("gimmick", "") == "combo_chain":
		base += int(e.combo_count)
		e.combo_count += 1
	# boss combo face (B3 sword dance)
	if f.get("boss_combo", false) and e.combo_count > 0:
		base += 2
	if e.get("boss_key", "") == "B5" and e.phase == 2:
		base += int(GameData.bosses.B5.unarmored_atk_bonus)
	if e.get("gimmick", "") != "combo_chain":
		e.combo_count += 1
	var targets: Array
	if f.get("aoe", false):
		targets = alive_heroes()
	else:
		var t := _enemy_pick_target()
		if t < 0:
			return
		targets = [t]
	for t in targets:
		var h: Dictionary = s.heroes[t]
		if h.down:
			continue
		var dmg := base
		if h.expose:
			dmg = int(ceil(dmg * 1.5))
		var blocked := 0
		if not f.get("pierce", false):
			blocked = mini(h.block, dmg)
			h.block -= blocked
		var hp_loss := dmg - blocked
		_ev({"t": "enemy_hit", "enemy": j, "hero": t, "dmg": dmg, "blocked": blocked})
		if allow_riders:
			if f.has("poison"):
				h.poison += int(f.poison)
			if f.has("burn"):
				h.burn_new.append(int(f.burn))
			if f.has("weaken"):
				h.weaken_next += enemy_face_value(e, f, "weaken")
		# hero thorns retaliate (ignores enemy block)
		if h.thorns > 0 and not e.dead:
			e.hp -= h.thorns
			_ev({"t": "thorns", "hero": t, "enemy": j, "dmg": h.thorns})
			if e.hp <= 0:
				_kill_enemy(j)
		if hp_loss > 0:
			_hero_lose_hp(t, hp_loss, "atk")
		if s.over:
			return


## What each of enemy j's rolled dice will actually do if the turn ended now:
## values with every live modifier already folded in (weaken, charge, howl, the
## pack bite, B2's combo chain, B3's sword dance, B5's shed armour) and who it
## lands on. The long-press forecast card prints exactly this, so it is derived
## here beside `_enemy_attack_heroes` rather than re-guessed in the UI.
##   [{die, face, done, cancelled, atk?, block?, heal?, target:{kind, hero}}]
func forecast_enemy(j: int) -> Array:
	var e: Dictionary = s.enemies[j]
	var out := []
	var combo := int(e.get("combo_count", 0))
	for d in e.rolls.size():
		var r: Dictionary = e.rolls[d]
		var f: Dictionary = r.face
		var row := {"die": d, "face": f, "done": bool(r.done),
			"cancelled": bool(r.cancelled), "instant": bool(r.get("instant", false))}
		if f.has("atk"):
			var v := enemy_face_value(e, f, "atk")
			if f.get("pack_bonus", 0) and _wolf_attacked_before(j):
				v += int(f.pack_bonus)
			v += int(e.howl)
			if e.get("gimmick", "") == "combo_chain":
				v += combo
			if f.get("boss_combo", false) and combo > 0:
				v += 2
			if e.get("boss_key", "") == "B5" and int(e.phase) == 2:
				v += int(GameData.bosses.B5.unarmored_atk_bonus)
			row["atk"] = maxi(v, 0)
			if not (r.done or r.cancelled):
				combo += 1
		for k in ["block", "heal"]:
			if f.has(k):
				row[k] = enemy_face_value(e, f, k)
		row["target"] = forecast_target(f)
		out.append(row)
	return out


## Who a given enemy face lands on right now, as {kind, hero}:
##   "aoe"    everyone            "taunt"  this hero is forcing it
##   "random" nobody is forcing it   "self" the enemy itself / the board
func forecast_target(f: Dictionary) -> Dictionary:
	var hits_a_hero: bool = f.has("atk") or f.has("weaken") or f.has("poison") \
			or f.has("bind") or f.get("expose", false)
	if not hits_a_hero:
		return {"kind": "self", "hero": -1}
	if f.get("aoe", false):
		return {"kind": "aoe", "hero": -1}
	for t in alive_heroes():
		if s.heroes[t].taunt:
			return {"kind": "taunt", "hero": t}
	return {"kind": "random", "hero": -1}


func _wolf_attacked_before(j: int) -> bool:
	for k in s.enemies.size():
		if k == j:
			continue
		var e: Dictionary = s.enemies[k]
		if e.key == "E07" and not e.dead:
			for r in e.rolls:
				if r.done and r.face.has("atk"):
					return true
	return false


func _do_curse() -> void:
	var cands := []
	for i in s.heroes.size():
		var h: Dictionary = s.heroes[i]
		if h.down:
			continue
		for fi in DICE * FACES:
			if not _is_blank(h, fi):
				cands.append([i, fi])
	if cands.is_empty():
		return
	var pick: Array = cands[rng.randi_range(0, cands.size() - 1)]
	s.heroes[pick[0]].cursed.append(pick[1])
	_ev({"t": "curse", "hero": pick[0], "face": pick[1]})


func _end_of_turn_settlement() -> void:
	# order per spec: poison -> burn -> regen -> block clear
	for j in s.enemies.size():
		var e: Dictionary = s.enemies[j]
		if e.dead:
			continue
		if e.poison > 0:
			e.hp -= e.poison
			_ev({"t": "poison_tick", "enemy": j, "dmg": e.poison})
			e.poison -= 1
			if e.hp <= 0:
				_kill_enemy(j)
				continue
		if not e.burn.is_empty():
			var total := 0
			for b in e.burn:
				total += int(b)
			e.burn = []
			e.hp -= total
			_ev({"t": "burn_tick", "enemy": j, "dmg": total})
			if e.hp <= 0:
				_kill_enemy(j)
				continue
		e.burn = e.burn_new
		e.burn_new = []
		if e.regen > 0:
			e.hp = mini(e.hp + e.regen, e.max_hp)
			e.regen -= 1
	for i in s.heroes.size():
		var h: Dictionary = s.heroes[i]
		if h.down:
			continue
		if h.poison > 0:
			_hero_lose_hp(i, h.poison, "poison")
			if not h.down:
				h.poison -= 1
		if not h.burn.is_empty() and not h.down:
			var total := 0
			for b in h.burn:
				total += int(b)
			h.burn = []
			_hero_lose_hp(i, total, "burn")
		if not h.down:
			h.burn = h.burn_new
			h.burn_new = []
		if h.regen > 0 and not h.down:
			_heal_hero(i, h.regen)
			h.regen -= 1
	# 蓄力累積(第十輪):回合結束時一個蓄力面仍展示喺骰上而未使用 → +1 層。
	# 「未使用」包括「用咗另一顆骰」—— 引弓不發就係蓄力,唔使再另外釘骰。
	for i2 in s.heroes.size():
		var hc: Dictionary = s.heroes[i2]
		if hc.down or hc.stolen:
			continue
		var spent2: Array = hc.get("used_dice", [])
		for d2 in DICE:
			var slot2 := int(hc.rolled[d2])
			if slot2 < 0 or _is_blank(hc, slot2) or d2 in spent2:
				continue
			if hero_face(i2, slot2).has("charge_up"):
				hc.face_charge[slot2] = mini(int(hc.face_charge[slot2]) + 1, CHARGE_TURN_CAP)
	# block clear (Ember keeps up to 10) — enemy block persists only via passives
	var crown: bool = _relic("thorn_crown") > 0
	for h in s.heroes:
		if _has_passive(h, "quilled_hide") and not h.down:
			h.block = mini(h.block, CARRY_BLOCK_CAP)
		else:
			h.block = 0
		h.weaken = 0
		h.expose = false
		h.taunt = false
		h.zanshin = 0
		h.atk_now = 0
		# Thorns wear off a layer a turn. 荊棘王冠 stops that for the whole run;
		# 堅守 buys the same for one turn, which is what makes the Hedgehog's
		# quills stack instead of trickle.
		if not crown and not bool(h.get("thorn_hold", false)):
			h.thorns = maxi(int(h.thorns) - 1, 0)
		h.thorn_hold = false
	for e in s.enemies:
		e.block = 0
		e.weaken = 0
		e.expose = false
		e.counter = 0
		for r in e.rolls:
			r.done = true
	# 靈息迴環 Essence Loop: end the turn with a pool still standing and the
	# grove pays interest. Banked here and spent in `_start_turn`, so it reads as
	# "next turn" to the player rather than as a silent top-up now.
	var loop := _relic("essence_loop")
	if loop > 0 and int(s.mana) >= ESSENCE_LOOP_FLOOR:
		s["essence_loop_due"] = loop
	# reroll carry (Metronome)
	var carry := _relic("reroll_carry")
	if carry > 0:
		s.reroll_carry = mini(s.rerolls, carry)
	_check_end()


func _check_end() -> void:
	if s.over:
		return
	# B5 sheds armor the moment it drops to half HP
	for e in s.enemies:
		if not e.dead and e.get("boss_key", "") == "B5" and e.phase == 1 and e.hp * 2 <= e.max_hp:
			e.phase = 2
			_ev({"t": "boss_unarmored", "enemy": s.enemies.find(e)})
	var any_enemy := false
	for e in s.enemies:
		if not e.dead:
			any_enemy = true
	if not any_enemy:
		s.over = true
		s.victory = true
		_ev({"t": "victory"})
		return
	var any_hero := false
	for h in s.heroes:
		if not h.down:
			any_hero = true
	if not any_hero:
		s.over = true
		s.victory = false
		_ev({"t": "defeat"})


# ============================================================ helpers

func _has_relic(id: String) -> bool:
	return id in s.relics


## The value of whichever held relic provides `effect` (0 when none does).
## Every relic rule in the engine goes through here rather than naming an id,
## because the relic list has already been rewritten once.
func _relic(effect: String) -> int:
	return GameData.relic_value(s.relics, effect)


func _ev(e: Dictionary) -> void:
	events.append(e)


func drain_events() -> Array:
	var out := events
	events = []
	return out


## Damage preview for UI: what would hero i's die d do to enemy j?
func preview_attack(i: int, d: int, j: int) -> Dictionary:
	var c := can_use(i, d)
	if not c.ok:
		return {}
	var fd: Dictionary = c.face
	if not _is_attack_face(fd):
		return {}
	var base := -1
	if fd.has("atk_from_block"):
		base = mini(int(s.heroes[i].block), int(fd.atk_from_block))
	var v := attack_value(i, fd, base)
	if fd.has("random_atk"):
		return {"min": int(fd.random_atk[0]), "max": int(fd.random_atk[1])}
	var e: Dictionary = s.enemies[j]
	var dmg := v
	if e.expose:
		dmg = int(ceil(dmg * 1.5))
	# An "X×N" face previews the TOTAL it would land. Block is drained by the
	# first strikes, so the later ones get through — printing `hp_loss × N`
	# would under-read every multi-hit into a blocking enemy.
	var passes := maxi(int(fd.get("hits", 1)), 1)
	var block_left: int = 0 if pierces(fd) else int(e.block)
	var total := 0
	for _k in passes:
		var blocked: int = mini(block_left, dmg)
		block_left -= blocked
		total += dmg - blocked
	return {"dmg": dmg * passes, "hp_loss": total, "hits": passes}
