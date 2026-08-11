class_name Glossary
extends RefCounted
## The one place the game explains itself.
##
## `data/glossary.json` holds every term — keywords, status effects, enemy
## intents and the mechanics that used to be invisible (蓄勢 / 居合 / 迴響 /
## 每回合一次). Battle tooltips, the face-swap screen, the codex, the shop and
## the status badges all call in here, so a term reads identically everywhere
## and there is exactly one file to edit when a rule changes.
##
## Nothing in here touches BattleCore: it describes faces, it does not resolve
## them. The numbers it prints come from the same resolved face dict the engine
## uses, so a forged "+1" or a Growth stack shows up in the text automatically.

## Priority order for "what is this face mainly doing" — the value that gets the
## big number on a tile and opens the effect sentence.
const MAIN_ORDER := ["atk", "random_atk", "atk_from_block", "block",
	"block_from_mana", "heal", "team_heal",
	"team_block", "team_thorns", "team_regen", "regen", "mana", "rerolls",
	"poison", "burn", "weaken", "stun", "buff_next_atk", "self_heal", "thorns",
	"thorns_double", "team_atk", "self_atk_now", "next_dice_boost",
	"expose", "taunt", "all_pierce", "twin_dance", "wild", "steal_die", "echo"]

## Modifiers, in the order they read on a tile and in a tooltip.
const MOD_ORDER := ["pierce", "hits", "charge_up", "resonate", "resonate_req",
	"cleave", "aoe", "combo", "lifesteal", "heal_on_hit", "poison",
	"burn", "weaken", "expose", "taunt", "thorns", "thorn_hold", "stun",
	"growth", "lucky", "low_hp_atk", "lock_boost",
	"pain", "spell", "echo", "cleanse_self", "cleanse_target", "self_heal",
	"buff_next_atk", "wild", "steal_die"]

## Keys that are a flag rather than a number.
const FLAG_KEYS := ["pierce", "cleave", "aoe", "sweep", "combo", "lifesteal",
	"expose", "taunt", "growth", "lucky", "wild", "steal_die", "cleanse_self",
	"cleanse_target", "blank", "all_pierce", "twin_dance", "thorn_hold"]

## Keys whose printed number is a ceiling, not the value you get.
const CAP_KEYS := ["atk_from_block", "block_from_mana", "thorns_double"]


static func _lang() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.has_node("/root/Data"):
		return String(tree.root.get_node("/root/Data").lang_mode())
	return "both"


## Bilingual join on one line ("中文 English").
static func _bi(zh: String, en: String) -> String:
	match _lang():
		"zh": return zh
		"en": return en
		_: return zh if zh == en else "%s %s" % [zh, en]


## Bilingual join on two lines — for sentences, where a run-on "中文English"
## is unreadable.
static func _bi2(zh: String, en: String) -> String:
	match _lang():
		"zh": return zh
		"en": return en
		_: return zh if zh == en else "%s\n%s" % [zh, en]


# ============================================================ term lookup

static func entry(key: String) -> Dictionary:
	GameData.load_all()
	var e = GameData.glossary.get(key, {})
	return e if e is Dictionary else {}


static func has(key: String) -> bool:
	return not entry(key).is_empty()


## The term's name, e.g. "連擊 Combo".
static func term_name(key: String) -> String:
	var e := entry(key)
	if e.is_empty():
		return key
	return _bi(String(e.get("zh", key)), String(e.get("en", key)))


## The term's explanation on its own.
static func desc(key: String) -> String:
	var e := entry(key)
	if e.is_empty():
		return ""
	return _bi2(String(e.get("d_zh", "")), String(e.get("d_en", "")))


## Name + explanation, the shape the detail card lists terms in.
static func line(key: String) -> String:
	var e := entry(key)
	if e.is_empty():
		return key
	match _lang():
		"zh": return "%s:%s" % [e.get("zh", key), e.get("d_zh", "")]
		"en": return "%s: %s" % [e.get("en", key), e.get("d_en", "")]
		_: return "%s %s\n%s\n%s" % [e.get("zh", key), e.get("en", key),
				e.get("d_zh", ""), e.get("d_en", "")]


## Icon for a term. Falls back to the term key itself, which `Glyphs` may well
## know how to draw anyway.
static func glyph_key(key: String) -> String:
	var g := String(entry(key).get("glyph", key))
	return g if Glyphs.has(g) else Glyphs.resolve(key)


static func hue(key: String) -> Color:
	return UITheme.cat_color(String(entry(key).get("hue", "special")))


# ============================================================ reading a face

static func _is_on(fd: Dictionary, key: String) -> bool:
	if not fd.has(key):
		return false
	# A live "up to N" face can legitimately resolve to zero right now (Essence
	# Guard with an empty pool). The face is still that face — dropping it here
	# would make the headline fall through to whatever it carries second, and a
	# die would change what it claims to be depending on the pool.
	if fd.has(key + "_cap"):
		return true
	var v = fd[key]
	if v is bool:
		return v
	if v is int or v is float:
		return int(v) != 0
	return true


## The face's headline effect: {key, value, numeric}. `value` is already the
## resolved number (forge "+" marks and Growth stacks included) because the
## caller hands us the same dict BattleCore resolves against.
static func main_effect(fd: Dictionary) -> Dictionary:
	if fd.get("blank", false):
		return {"key": "blank", "value": 0, "numeric": false}
	for k in MAIN_ORDER:
		if not _is_on(fd, k):
			continue
		if k == "random_atk":
			var r: Array = fd[k]
			return {"key": "atk", "value": int(r[1]), "numeric": false,
				"range": [int(r[0]), int(r[1])]}
		if k in FLAG_KEYS:
			return {"key": k, "value": 0, "numeric": false}
		return {"key": k, "value": int(fd[k]), "numeric": true}
	return {"key": "blank", "value": 0, "numeric": false}


## Secondary keywords on the face, main effect excluded — these are the corner
## badges on a tile. Capped by the caller (a tile shows at most three).
static func sub_terms(fd: Dictionary) -> Array:
	var main := String(main_effect(fd).key)
	var out := []
	for k in MOD_ORDER:
		if k == main or not _is_on(fd, k):
			continue
		if k not in out:
			out.append(k)
	return out


## Every term the face touches, main first — the detail card explains all of it.
static func face_terms(fd: Dictionary) -> Array:
	var out := []
	var main := String(main_effect(fd).key)
	if has(main):
		out.append(main)
	for k in sub_terms(fd):
		if has(k) and k not in out:
			out.append(k)
	# a targeted face that lands on a *die* is teaching the stun rule whether or
	# not it carries the keyword
	if String(fd.get("target", "")) == "enemy_die" and "stun" not in out \
			and not _is_on(fd, "steal_die"):
		out.append("stun")
	return out


## The number a tile prints in the middle. Empty when the face's headline is a
## flag rather than a value (Wild, Taunt, Expose…).
static func main_number(fd: Dictionary) -> String:
	var m := main_effect(fd)
	if m.has("range"):
		return "%d-%d" % [int(m.range[0]), int(m.range[1])]
	if not bool(m.numeric):
		return ""
	var v := int(m.value)
	var k := String(m.key)
	# "X×N" is the multi-hit face's whole identity — the tile has to lead with
	# it, not with the value of one of the strikes.
	if k in ["atk", "atk_from_block"] and int(fd.get("hits", 1)) > 1:
		return "%d×%d" % [v, int(fd.hits)]
	if k in CAP_KEYS:
		# A LIVE face (see `BattleCore.live_face`) has already worked out what the
		# ceiling comes to right now and parked the ceiling itself in `<k>_cap`.
		# "4" is what the player is about to get; "≤6" is trivia they can read on
		# the long-press card.
		if fd.has(k + "_cap"):
			return str(v)
		return "≤%d" % v
	if k in ["mana", "rerolls", "buff_next_atk", "echo", "team_atk",
			"self_atk_now", "next_dice_boost"]:
		return "+%d" % v
	return str(v)


# ============================================================ effect sentence

## Bilingual "what happens when I use this" line, e.g.
##   對目標造成 4 點傷害,並使目標中毒 2 層
##   Deal 4 damage and inflict Poison 2 on the target
## Built from the resolved face, so it always agrees with the engine.
static func effect_sentence(fd: Dictionary) -> String:
	var zh := []
	var en := []
	if fd.get("blank", false):
		return _bi2("沒有任何效果。", "Nothing happens.")

	var aoe: bool = _is_on(fd, "aoe") or _is_on(fd, "sweep")
	var who_zh := "所有敵人" if aoe else "目標"
	var who_en := "every enemy" if aoe else "the target"

	if fd.has("random_atk"):
		var r: Array = fd.random_atk
		zh.append("對%s造成 %d-%d 點隨機傷害" % [who_zh, int(r[0]), int(r[1])])
		en.append("Deal %d-%d random damage to %s" % [int(r[0]), int(r[1]), who_en])
	elif _is_on(fd, "atk"):
		var n := int(fd.get("hits", 1))
		if n > 1:
			zh.append("對%s連續造成 %d 次 %d 點傷害" % [who_zh, n, int(fd.atk)])
			en.append("Hit %s %d times for %d each" % [who_en, n, int(fd.atk)])
		else:
			zh.append("對%s造成 %d 點傷害" % [who_zh, int(fd.atk)])
			en.append("Deal %d damage to %s" % [int(fd.atk), who_en])
	elif _is_on(fd, "atk_from_block") or fd.has("atk_from_block_cap"):
		# On a LIVE face the key holds what it comes to right now and `_cap` the
		# printed ceiling, so the sentence can lead with the real number and keep
		# the rule as a parenthetical. Off a live face there is no "right now" to
		# report and it stays the rule alone.
		if fd.has("atk_from_block_cap"):
			zh.append("對%s造成 %d 點傷害(等同你當前格擋,上限 %d)"
					% [who_zh, int(fd.atk_from_block), int(fd.atk_from_block_cap)])
			en.append("Deal %d damage to %s (your current Block, capped at %d)"
					% [int(fd.atk_from_block), who_en, int(fd.atk_from_block_cap)])
		else:
			zh.append("對%s造成等同你當前格擋的傷害(上限 %d)" % [who_zh, int(fd.atk_from_block)])
			en.append("Deal damage to %s equal to your current Block, up to %d" % [who_en, int(fd.atk_from_block)])
	if _is_on(fd, "block_from_mana") or fd.has("block_from_mana_cap"):
		if fd.has("block_from_mana_cap"):
			zh.append("獲得 %d 點格擋(等同隊伍靈息,上限 %d)"
					% [int(fd.block_from_mana), int(fd.block_from_mana_cap)])
			en.append("gain %d Block (the party's Essence, capped at %d)"
					% [int(fd.block_from_mana), int(fd.block_from_mana_cap)])
		else:
			zh.append("獲得等同隊伍靈息的格擋(上限 %d)" % int(fd.block_from_mana))
			en.append("gain Block equal to the party's Essence, up to %d" % int(fd.block_from_mana))
	if _is_on(fd, "thorns_double") or fd.has("thorns_double_cap"):
		if fd.has("thorns_double_cap"):
			zh.append("荊棘 +%d(當前層數翻倍,最多 +%d)"
					% [int(fd.thorns_double), int(fd.thorns_double_cap)])
			en.append("gain Thorns %d (double what you have, adding at most %d)"
					% [int(fd.thorns_double), int(fd.thorns_double_cap)])
		else:
			zh.append("當前荊棘層數翻倍(最多 +%d)" % int(fd.thorns_double))
			en.append("double your current Thorns, adding at most %d" % int(fd.thorns_double))
	if _is_on(fd, "team_atk"):
		zh.append("本回合全隊攻擊面 +%d" % int(fd.team_atk))
		en.append("every hero's attack faces get +%d this turn" % int(fd.team_atk))
	if _is_on(fd, "self_atk_now"):
		zh.append("本回合他的攻擊面 +%d" % int(fd.self_atk_now))
		en.append("his attack faces get +%d for the rest of this turn" % int(fd.self_atk_now))
	if _is_on(fd, "next_dice_boost"):
		zh.append("下回合他兩顆骰的數值 +%d" % int(fd.next_dice_boost))
		en.append("both his dice are worth +%d next turn" % int(fd.next_dice_boost))
	if _is_on(fd, "lock_boost"):
		zh.append("他鎖定中的骰下回合數值 +%d" % int(fd.lock_boost))
		en.append("the die he has locked is worth +%d next turn" % int(fd.lock_boost))
	if _is_on(fd, "all_pierce"):
		zh.append("本回合全隊所有攻擊無視格擋")
		en.append("every attack your party makes this turn ignores Block")
	if _is_on(fd, "twin_dance"):
		zh.append("本回合他可以額外使用鎖定中的那顆骰,而且鎖定不會解除")
		en.append("he may also spend the die he has locked this turn, and the lock survives it")
	if _is_on(fd, "thorn_hold"):
		zh.append("本回合結束時他的荊棘不會消退")
		en.append("his Thorns do not decay at the end of this turn")
	if _is_on(fd, "block"):
		zh.append("獲得 %d 點格擋" % int(fd.block))
		en.append("gain %d Block" % int(fd.block))
	if _is_on(fd, "team_block"):
		zh.append("全隊獲得 %d 點格擋" % int(fd.team_block))
		en.append("the whole party gains %d Block" % int(fd.team_block))
	if _is_on(fd, "heal"):
		zh.append("回復 %d 點 HP" % int(fd.heal))
		en.append("restore %d HP" % int(fd.heal))
	if _is_on(fd, "self_heal"):
		zh.append("自己回復 %d 點 HP" % int(fd.self_heal))
		en.append("restore %d HP to yourself" % int(fd.self_heal))
	if _is_on(fd, "team_heal"):
		zh.append("全隊回復 %d 點 HP" % int(fd.team_heal))
		en.append("the whole party restores %d HP" % int(fd.team_heal))
	if _is_on(fd, "regen"):
		zh.append("使目標獲得 %d 層再生" % int(fd.regen))
		en.append("give the target Regen %d" % int(fd.regen))
	if _is_on(fd, "team_regen"):
		zh.append("全隊獲得 %d 層再生" % int(fd.team_regen))
		en.append("the whole party gains Regen %d" % int(fd.team_regen))
	if _is_on(fd, "thorns"):
		zh.append("獲得 %d 層荊棘" % int(fd.thorns))
		en.append("gain Thorns %d" % int(fd.thorns))
	if _is_on(fd, "team_thorns"):
		zh.append("全隊獲得 %d 層荊棘" % int(fd.team_thorns))
		en.append("the whole party gains Thorns %d" % int(fd.team_thorns))
	if _is_on(fd, "mana"):
		zh.append("汲取 %d 點森林靈息" % int(fd.mana))
		en.append("draw %d Essence" % int(fd.mana))
	if _is_on(fd, "rerolls"):
		zh.append("獲得 %d 次重擲" % int(fd.rerolls))
		en.append("gain %d reroll%s" % [int(fd.rerolls), "" if int(fd.rerolls) == 1 else "s"])
	if _is_on(fd, "poison"):
		zh.append("使%s中毒 %d 層" % [who_zh, int(fd.poison)])
		en.append("inflict Poison %d on %s" % [int(fd.poison), who_en])
	if _is_on(fd, "burn"):
		zh.append("使%s灼燒 %d 點" % [who_zh, int(fd.burn)])
		en.append("inflict Burn %d on %s" % [int(fd.burn), who_en])
	if _is_on(fd, "weaken"):
		zh.append("使%s弱化 %d" % [who_zh, int(fd.weaken)])
		en.append("inflict Weaken %d on %s" % [int(fd.weaken), who_en])
	if _is_on(fd, "expose"):
		zh.append("使%s易傷" % who_zh)
		en.append("inflict Expose on %s" % who_en)
	if _is_on(fd, "stun"):
		var n := int(fd.stun)
		zh.append("取消 %d 顆敵人已擲的骰子" % n)
		en.append("cancel %d rolled enemy die/dice" % n)
	if _is_on(fd, "taunt"):
		zh.append("嘲諷:本回合敵人的單體攻擊必須以你為目標")
		en.append("Taunt: enemy single-target attacks must hit you this turn")
	if _is_on(fd, "buff_next_atk"):
		zh.append("下回合此英雄的攻擊面 +%d" % int(fd.buff_next_atk))
		en.append("this hero's attack faces get +%d next turn" % int(fd.buff_next_atk))
	if _is_on(fd, "echo"):
		zh.append("全隊下一個使用的骰面 +%d" % int(fd.echo))
		en.append("the party's next face used gets +%d" % int(fd.echo))
	if _is_on(fd, "cleanse_self"):
		zh.append("清除自己的負面狀態")
		en.append("cleanse your own debuffs")
	if _is_on(fd, "cleanse_target"):
		zh.append("清除目標的負面狀態")
		en.append("cleanse the target's debuffs")
	if _is_on(fd, "wild"):
		zh.append("複製隊伍本回合任何一個已擲出的面,並以該面結算")
		en.append("copy any face your party rolled this turn and resolve as it")
	if _is_on(fd, "steal_die"):
		zh.append("奪取敵人一顆已擲的骰子,再用它攻擊指定的敵人")
		en.append("take one rolled enemy die and fire it at an enemy of your choice")

	# modifiers that change how the above resolves rather than adding a clause
	var tail_zh := []
	var tail_en := []
	if _is_on(fd, "pierce"):
		tail_zh.append("無視格擋")
		tail_en.append("ignores Block")
	if _is_on(fd, "cleave"):
		tail_zh.append("同時命中左右相鄰的敵人")
		tail_en.append("also hits the neighbours")
	if _is_on(fd, "combo"):
		tail_zh.append("本回合若已使用過攻擊面則 +2")
		tail_en.append("+2 if an attack face was already used this turn")
	if _is_on(fd, "charge_up"):
		tail_zh.append("每在鎖定位渡過一回合 +%d,最多 +%d" % [int(fd.charge_up), int(fd.charge_up) * 3])
		tail_en.append("+%d per full turn spent locked, up to +%d" % [int(fd.charge_up), int(fd.charge_up) * 3])
	if _is_on(fd, "resonate"):
		tail_zh.append("呼應:另一顆骰鎖定在%s面時 +%d" % [
				_cat_word_zh(String(fd.get("resonate_cat", "attack"))), int(fd.resonate)])
		tail_en.append("Echo: +%d while the other die is locked on %s face" % [
				int(fd.resonate), _cat_word_en(String(fd.get("resonate_cat", "attack")))])
	if _is_on(fd, "resonate_req"):
		tail_zh.append("必須另一顆骰鎖定在%s面才可使用" % _cat_word_zh(String(fd.resonate_req)))
		tail_en.append("only usable while the other die is locked on %s face" % _cat_word_en(String(fd.resonate_req)))
	if _is_on(fd, "low_hp_atk"):
		tail_zh.append("HP 在 50%% 或以下時改為 %d" % int(fd.low_hp_atk))
		tail_en.append("becomes %d at 50%% HP or less" % int(fd.low_hp_atk))
	if _is_on(fd, "heal_on_hit"):
		tail_zh.append("真的扣到 HP 就回復 %d" % int(fd.heal_on_hit))
		tail_en.append("heals %d if it actually took HP off" % int(fd.heal_on_hit))
	if _is_on(fd, "lifesteal"):
		tail_zh.append("回復實際傷害的 50%")
		tail_en.append("heals for 50% of the damage dealt")
	if _is_on(fd, "growth"):
		tail_zh.append("每使用一次,此面在本次冒險中永久 +1")
		tail_en.append("each use permanently gives this face +1 for the run")
	if _is_on(fd, "lucky"):
		tail_zh.append("擲出時即 +1 重擲")
		tail_en.append("rolling it grants +1 reroll")

	var cost_zh := []
	var cost_en := []
	if _is_on(fd, "spell"):
		cost_zh.append("消耗 %d 點靈息" % int(fd.spell))
		cost_en.append("costs %d Essence" % int(fd.spell))
	if _is_on(fd, "pain"):
		cost_zh.append("使用者扣 %d 點 HP" % int(fd.pain))
		cost_en.append("the user loses %d HP" % int(fd.pain))

	if zh.is_empty():
		zh.append("沒有直接效果")
		en.append("No direct effect")
	var s_zh: String = zh[0] + ("" if zh.size() < 2 else ",並" + ",".join(zh.slice(1)))
	var s_en: String = en[0] + ("" if en.size() < 2 else " and " + ", ".join(en.slice(1)))
	if not tail_zh.is_empty():
		s_zh += "(%s)" % "、".join(tail_zh)
		s_en += " (%s)" % "; ".join(tail_en)
	if not cost_zh.is_empty():
		s_zh += "。代價:%s" % "、".join(cost_zh)
		s_en += ". Cost: %s" % "; ".join(cost_en)
	return _bi2(s_zh + "。", s_en + ".")


## The face category 呼應 is asking about, as a word that reads inside a
## sentence ("鎖定在攻擊面時" / "locked on an attack face").
static func _cat_word_zh(cat: String) -> String:
	match cat:
		"block": return "格擋"
		"heal": return "治療"
		_: return "攻擊"


static func _cat_word_en(cat: String) -> String:
	match cat:
		"block": return "a Block"
		"heal": return "a Heal"
		_: return "an attack"


## "目標:敵人" — where this face has to be dropped.
static func target_line(fd: Dictionary) -> String:
	var t := String(fd.get("target", "none"))
	var aoe: bool = _is_on(fd, "aoe") or _is_on(fd, "sweep")
	var zh := ""
	var en := ""
	match t:
		"enemy":
			zh = "敵人"; en = "an enemy"
		"ally":
			zh = "隊友(拖到他的卡片上)"; en = "an ally (drag onto their card)"
		"self":
			zh = "自己"; en = "yourself"
		"enemy_die":
			zh = "敵人的意圖骰"; en = "an enemy intent die"
		"wild":
			zh = "隊伍任何一顆已擲出的骰子"; en = "any die your party has rolled"
		_:
			if aoe:
				zh = "全體(拖到中央施放區)"; en = "everything (drag to the centre cast pad)"
			else:
				zh = "無(拖到中央施放區)"; en = "none (drag to the centre cast pad)"
	return _bi("目標:%s" % zh, "Target: %s" % en)


## "普通 / 稀有 / 史詩 / 起始" — the rarity letter spelled out.
static func rarity_name(letter: String) -> String:
	match letter:
		"E": return _bi("史詩", "Epic")
		"R": return _bi("稀有", "Rare")
		"U": return _bi("解鎖", "Unlockable")
		"S": return _bi("起始", "Starting")
		_: return _bi("普通", "Common")
