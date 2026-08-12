class_name RunState
extends RefCounted
## Run-level pure logic: map generation, reward offers, shop stock, economy.
## All functions are static and take the run dict + rng explicitly, so the
## headless simulator can reuse them.


# ============================================================ new run

static func new_run(team_ids: Array, seed_v: int, meta_levels := {}) -> Dictionary:
	GameData.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var team := []
	for id in team_ids:
		var h := GameData.new_hero(id, int(meta_levels.get(id, 1)))
		team.append(h)
	var run := {
		"seed": seed_v,
		"rng_state": 0,
		"chapter": 1,
		"row": -1, "col": -1,
		"team": team,
		# 第十輪:開局帶 50 金 —— 第一章商店見到藥水(35)買得起、普通面(45)
		# 掂到邊,「買唔買」先至係一個決定。旋鈕在 balance.json `start_gold`。
		"gold": int(GameData.balance.get("start_gold", 0)),
		"relics": [],
		"potions": [],
		"run_atk_buff": 0,
		"gold_pct": 100,
		"pending_marsh": 0,
		"pending_imp": false,
		"skip_row": false,
		"battle": {},        # in-progress encounter (seed + line-up), see GameState
		"map": {},
		"stats": {"battles": 0, "elites": 0, "start_msec": 0, "nodes": 0},
	}
	run.map = gen_map(1, rng)
	run.rng_state = rng.state
	return run


static func rng_of(run: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.seed)
	if int(run.rng_state) != 0:
		rng.state = int(run.rng_state)
	return rng


static func save_rng(run: Dictionary, rng: RandomNumberGenerator) -> void:
	run.rng_state = rng.state


# ============================================================ map generation

## Returns {rows: [[node,…],…], boss: "B1"}  (9 rows; row 8 = boss)
## node = {type, x, edges: [indices in next row]}
static func gen_map(chapter: int, rng: RandomNumberGenerator) -> Dictionary:
	var n_rows := int(GameData.balance.map_rows)
	var counts := []
	for r in n_rows:
		if r == n_rows - 1:
			counts.append(1)
		else:
			counts.append(2 + (rng.randi_range(0, 1)))   # 2-3 nodes per row
	# node shells
	var rows := []
	for r in n_rows:
		var row := []
		for c in counts[r]:
			row.append({"type": "battle", "x": 0.0, "edges": []})
		rows.append(row)
	# x positions (spread evenly with jitter)
	for r in n_rows:
		var n: int = rows[r].size()
		for c in n:
			var base: float = (c + 1.0) / (n + 1.0)
			rows[r][c].x = clampf(base + rng.randf_range(-0.05, 0.05), 0.1, 0.9)
	# edges: monotonic windows guarantee every node has in+out links
	for r in n_rows - 1:
		var a: int = rows[r].size()
		var b: int = rows[r + 1].size()
		for i in a:
			var lo := int(floor(float(i) * b / a))
			var hi := int(floor(float(i + 1) * b / a))
			hi = mini(hi, b - 1)
			var edges := []
			for j in range(lo, hi + 1):
				edges.append(j)
			# occasionally add one extra branch
			if edges.size() == 1 and rng.randf() < 0.35:
				var extra: int = clampi(edges[0] + (1 if rng.randf() < 0.5 else -1), 0, b - 1)
				if extra not in edges:
					edges.append(extra)
			edges.sort()
			rows[r][i].edges = edges
	# ensure every next-row node has an incoming edge
	for r in n_rows - 1:
		var incoming := {}
		for i in rows[r].size():
			for j in rows[r][i].edges:
				incoming[j] = true
		for j in rows[r + 1].size():
			if not incoming.has(j):
				var nearest := 0
				var best := 99.0
				for i in rows[r].size():
					var d: float = abs(rows[r][i].x - rows[r + 1][j].x)
					if d < best:
						best = d
						nearest = i
				rows[r][nearest].edges.append(j)
				rows[r][nearest].edges.sort()
	# --- node types
	rows[n_rows - 1][0].type = "boss"
	for c in rows[0].size():
		rows[0][c].type = "battle"
	# collect assignable slots (rows 1..7)
	var slots := []
	for r in range(1, n_rows - 1):
		for c in rows[r].size():
			slots.append([r, c])
	# exact counts: elites (row>=2), 1 shop, 1 rest, 1 treasure
	var elites_needed := int(GameData.balance.elites_per_chapter[str(chapter)])
	var elite_slots := []
	for s in slots:
		if s[0] >= 2:
			elite_slots.append(s)
	_shuffle(elite_slots, rng)
	var used := {}
	var placed := 0
	for s in elite_slots:
		if placed >= elites_needed:
			break
		rows[s[0]][s[1]].type = "elite"
		used[str(s)] = true
		placed += 1
	for t in ["shop", "rest", "treasure"]:
		var free := []
		for s in slots:
			if not used.has(str(s)):
				free.append(s)
		_shuffle(free, rng)
		if free.size() > 0:
			var s: Array = free[0]
			rows[s[0]][s[1]].type = t
			used[str(s)] = true
	# remaining: battle vs event (55:20 ratio → ~73/27)
	for s in slots:
		if used.has(str(s)):
			continue
		rows[s[0]][s[1]].type = "event" if rng.randf() < 0.27 else "battle"
	# boss pick: 2 per chapter
	var boss_options := []
	for bk in GameData.bosses:
		if int(GameData.bosses[bk].chapter) == chapter:
			boss_options.append(bk)
	boss_options.sort()
	var boss: String = boss_options[rng.randi_range(0, boss_options.size() - 1)]
	# battle encounters: progressively stronger through the chapter
	var enc_list: Array = GameData.encounters[str(chapter)]
	for r in n_rows:
		for c in rows[r].size():
			var node: Dictionary = rows[r][c]
			if node.type == "battle":
				var prog := float(r) / float(n_rows - 2)
				var idx := int(floor(prog * (enc_list.size() - 1)))
				idx = clampi(idx + rng.randi_range(0, 1) - (1 if rng.randf() < 0.3 else 0), 0, enc_list.size() - 1)
				node["encounter"] = enc_list[idx].duplicate()
			elif node.type == "elite":
				var pool: Array = GameData.encounters.elite_pools[str(chapter)]
				node["elite_key"] = pool[rng.randi_range(0, pool.size() - 1)]
				var affixes := ["frenzied", "stoneskin", "venomous"]
				node["affix"] = affixes[rng.randi_range(0, 2)]
			elif node.type == "event":
				node["event"] = ""   # picked on entry (avoids duplicates via run)
	return {"rows": rows, "boss": boss}


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Node indices selectable from the current position.
static func available_nodes(run: Dictionary) -> Array:
	var rows: Array = run.map.rows
	var out := []
	if run.skip_row:
		var target := int(run.row) + 2
		if target < rows.size():
			for c in rows[target].size():
				out.append([target, c])
			return out
		return [[rows.size() - 1, 0]]
	if int(run.row) < 0:
		for c in rows[0].size():
			out.append([0, c])
		return out
	if int(run.row) >= rows.size() - 1:
		return []
	var node: Dictionary = rows[run.row][run.col]
	for j in node.edges:
		out.append([int(run.row) + 1, int(j)])
	return out


# ============================================================ rewards

## 3 post-battle offers: [{hero: idx, face: id}] bound to distinct heroes;
## rarity per the node kind's table ("battle" C70/R25/E5, "elite" C25/R60/E15,
## "boss" R60/E40); 30% hero-specific override. Which of the hero's 12 faces
## gets replaced is the player's choice at redemption time.
static func gen_offers(run: Dictionary, rng: RandomNumberGenerator, kind: String, unlocked_by_hero: Dictionary) -> Array:
	var hero_idx := []
	for i in run.team.size():
		hero_idx.append(i)
	_shuffle(hero_idx, rng)
	var offers := []
	for k in mini(3, hero_idx.size()):
		var hi: int = hero_idx[k]
		var hero: Dictionary = run.team[hi]
		var face_id := ""
		var unlocked: Array = unlocked_by_hero.get(hero.id, [])
		if unlocked.size() > 0 and rng.randi_range(1, 100) <= int(GameData.balance.hero_face_offer_chance):
			face_id = unlocked[rng.randi_range(0, unlocked.size() - 1)]
		else:
			face_id = _roll_shared_face(rng, kind)
		offers.append({"hero": hi, "face": face_id})
	return offers


## `kind` is the node the loot came from: "battle", "elite" or "boss".
static func _roll_shared_face(rng: RandomNumberGenerator, kind := "battle") -> String:
	var roll := rng.randi_range(1, 100)
	var rarity := "C"
	if kind == "boss":
		rarity = "R" if roll <= int(GameData.balance.offer_rarity_boss.R) else "E"
	else:
		var w: Dictionary = GameData.balance.offer_rarity_elite if kind == "elite" 				else GameData.balance.offer_rarity
		if roll <= int(w.C):
			rarity = "C"
		elif roll <= int(w.C) + int(w.R):
			rarity = "R"
		else:
			rarity = "E"
	var pool := GameData.shared_pool(rarity)
	return pool[rng.randi_range(0, pool.size() - 1)]


# ============================================================ relic draws

## Relic ids of `rarity` the party does not already hold, sorted so a seeded
## draw is reproducible.
static func relic_pool(run: Dictionary, rarity := "common") -> Array:
	var out := []
	for rid in GameData.relics_of_rarity(rarity):
		if rid not in run.relics:
			out.append(rid)
	return out


## One unowned relic of `rarity`, or "" when the tier is exhausted.
static func roll_relic(run: Dictionary, rng: RandomNumberGenerator, rarity := "common") -> String:
	var pool := relic_pool(run, rarity)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


## The boss 2-pick: `n` distinct unowned Advanced relics. Short-tier draws
## degrade to however many are left rather than repeating one.
static func roll_advanced_choice(run: Dictionary, rng: RandomNumberGenerator, n := 2) -> Array:
	var pool := relic_pool(run, "advanced")
	_shuffle(pool, rng)
	return pool.slice(0, mini(n, pool.size()))


static func gold_for_battle(run: Dictionary, rng: RandomNumberGenerator, kind: String) -> int:
	var ch := str(run.chapter)
	var g := 0
	match kind:
		"boss":
			g = int(GameData.balance.gold_boss[ch])
		"elite":
			var r: Array = GameData.balance.gold_battle[ch]
			g = rng.randi_range(int(r[0]), int(r[1])) * int(GameData.balance.gold_elite_mult)
		_:
			var r2: Array = GameData.balance.gold_battle[ch]
			g = rng.randi_range(int(r2[0]), int(r2[1]))
	var bonus := GameData.relic_value(run.relics, "gold_pct")
	if bonus > 0:
		g = int(floor(g * (1.0 + bonus / 100.0)))
	g = int(floor(g * int(run.gold_pct) / 100.0))
	return g


# ============================================================ shop

static func gen_shop(run: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var faces := []
	# at least 1 R-or-above among 4
	faces.append(_roll_shared_face_min_r(rng))
	for i in 3:
		faces.append(_roll_shared_face(rng))
	# the shop only ever stocks Common relics — Advanced ones are boss loot
	var relic := roll_relic(run, rng, "common")
	var potion_ids := GameData.potions.keys()
	potion_ids.sort()
	var potions := [potion_ids[rng.randi_range(0, potion_ids.size() - 1)],
			potion_ids[rng.randi_range(0, potion_ids.size() - 1)]]
	return {
		"faces": faces, "faces_bought": [false, false, false, false],
		"relic": relic, "relic_bought": false,
		"potions": potions, "potions_bought": [false, false],
		"forge_used": false,
	}


static func _roll_shared_face_min_r(rng: RandomNumberGenerator) -> String:
	var rarity := "R" if rng.randi_range(1, 100) <= 80 else "E"
	var pool := GameData.shared_pool(rarity)
	return pool[rng.randi_range(0, pool.size() - 1)]


static func face_price(face_id: String) -> int:
	var r: String = GameData.faces[face_id].get("rarity", "C")
	return int(GameData.balance.shop_prices.get(r, 45))


# ============================================================ treasure

static func gen_treasure(run: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() < 0.5:
		var rid := roll_relic(run, rng, "common")
		if rid != "":
			return {"kind": "relic", "relic": rid}
	return {"kind": "faces", "faces": _distinct_min_r_faces(rng, 3)}


## `n` distinct rare-or-better face ids. Three offers on one screen are a
## choice, so two of them being the same face is a wasted pick — rolls that
## collide are simply re-rolled. The pool is far larger than three, but the
## draw is still bounded and then topped up deterministically, so a shrunken
## pool degrades into "as many distinct faces as exist" instead of looping.
static func _distinct_min_r_faces(rng: RandomNumberGenerator, n: int) -> Array:
	var out := []
	var tries := 0
	while out.size() < n and tries < 60:
		tries += 1
		var fid := _roll_shared_face_min_r(rng)
		if fid not in out:
			out.append(fid)
	if out.size() < n:
		var fallback := GameData.shared_pool("R")
		fallback.append_array(GameData.shared_pool("E"))
		for fid2 in fallback:
			if out.size() >= n:
				break
			if fid2 not in out:
				out.append(fid2)
	return out


# ============================================================ misc helpers

static func apply_face_swap(run: Dictionary, hero_i: int, slot: int, new_face: String) -> void:
	var hero: Dictionary = run.team[hero_i]
	hero.faces[slot] = new_face
	hero.face_mods[slot] = 0
	hero.face_plus[slot] = 0
	hero.face_extras[slot] = {}


## Forge / event enchant: +1 to the face's main value AND a visible "+" mark.
## (The growth keyword bumps face_mods only — no "+" is earned that way.)
static func forge_face(hero: Dictionary, slot: int) -> void:
	hero.face_mods[slot] = int(hero.face_mods[slot]) + 1
	hero.face_plus[slot] = int(hero.face_plus[slot]) + 1


static func forgeable_slots(hero: Dictionary) -> Array:
	## Slots whose face has a numeric main value (forge +1 targets).
	var out := []
	for i in GameData.SLOTS:
		var fd: Dictionary = GameData.faces.get(hero.faces[i], {})
		var has_num := false
		for k in ["atk", "block", "heal", "mana", "team_heal", "team_block",
				"team_thorns", "team_regen", "regen", "random_atk"]:
			if fd.has(k):
				has_num = true
		if has_num:
			out.append(i)
	return out


static func team_alive_heal_flat(run: Dictionary, amount: int) -> void:
	for h in run.team:
		if h.hp > 0:
			h.hp = mini(int(h.hp) + amount, int(h.max_hp))


static func team_alive_heal_pct(run: Dictionary, pct: int) -> void:
	for h in run.team:
		if h.hp > 0:
			h.hp = mini(h.hp + int(ceil(h.max_hp * pct / 100.0)), h.max_hp)


static func post_battle_recovery(run: Dictionary) -> void:
	var pct := int(GameData.balance.post_battle_heal_pct)
	var relic_pct := GameData.relic_value(run.relics, "post_battle_heal_pct")
	if relic_pct > 0:
		pct = relic_pct
	var revive_pct := int(GameData.balance.revive_hp_pct)
	for h in run.team:
		if h.hp <= 0:
			h.hp = maxi(1, int(floor(h.max_hp * revive_pct / 100.0)))
		else:
			h.hp = mini(h.hp + int(ceil(h.max_hp * pct / 100.0)), h.max_hp)
