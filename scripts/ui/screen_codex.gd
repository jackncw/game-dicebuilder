extends Control
## Codex: two tabs of everything the player has met.
##
## Discovery rules (recorded live in battle, kept even on defeat):
##   · a hero's starting 12 faces are always readable;
##   · any other face shows as ??? until it has actually been used once — by
##     base id, so using it on one hero reveals it everywhere;
##   · a minion tier unlocks when that tier has been fought;
##   · bosses and elite affixes unlock on first encounter.

var tab := "chars"
var scroll: ScrollContainer
var body: VBoxContainer
var tab_buttons := {}


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	add_child(UIKit.background(3, 132.0, 0.0))

	var title := UIKit.title(Data.t("ui_codex"), UIKit.F_H1)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	Safe.pin_top(title, UIKit.S4)
	add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	tabs.anchor_left = 0.0
	tabs.anchor_right = 1.0
	Safe.pin_band(tabs, 72, 140)
	add_child(tabs)
	for pair in [["chars", "ui_codex_chars"], ["mobs", "ui_codex_mobs"]]:
		var key: String = pair[0]
		var b := UIKit.button(Data.t(pair[1]), UIKit.CREAM, UIKit.F_BODY, Vector2(236, 68))
		b.pressed.connect(func() -> void:
			Sfx.play("button")
			tab = key
			_build())
		tab_buttons[key] = b
		tabs.add_child(b)

	scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Safe.pin_top(scroll, 150)
	scroll.offset_left = UIKit.S4
	scroll.offset_right = -UIKit.S4
	Safe.pin_bottom(scroll, 128)
	add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", UIKit.S3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var tray := UIKit.footer(3, 120.0)
	add_child(tray)
	var back := UIKit.button(Data.t("ui_back"), UIKit.CREAM, UIKit.F_H2, Vector2(260, 74))
	back.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.goto("menu"))
	tray.get_child(0).add_child(UIKit.button_row([back]))

	_build()


func _build() -> void:
	for c in body.get_children():
		c.queue_free()
	for key in tab_buttons:
		var b: Button = tab_buttons[key]
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
		sb.border_color = UIKit.YELLOW if key == tab else UIKit.OUTLINE
	if tab == "chars":
		_build_chars()
	else:
		_build_mobs()


# ============================================================ shared bits

func _panel(children: Array, border := UIKit.OUTLINE) -> Control:
	var p := UIKit.card(3, UIKit.R_LG, UIKit.B_STRONG, border, UIKit.S3)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UIKit.S1)
	for c in children:
		vb.add_child(c)
	p.add_child(vb)
	return p


func _line(text: String, size := 19, color := UIKit.CREAM, width := 620.0) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


## A grid of face tiles — the same object the dice and the swap screen show, so
## a face read here is recognisable in a fight. Undiscovered faces keep their
## slot as a blank silhouette rather than vanishing, which is what makes the
## grid readable as "what this character can hold".
func _face_grid(ids: Array, cols := 6) -> Control:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", UIKit.S1)
	grid.add_theme_constant_override("v_separation", UIKit.S2)
	for entry in ids:
		var fid := String(entry[0])
		var revealed: bool = bool(entry[1])
		var fd: Dictionary = GameData.faces[fid].duplicate(true)
		fd["id"] = fid
		if not revealed:
			fd = {"zh": "???", "en": "???", "cat": "special", "blank": true, "id": "blank"}
		var tile := FaceTile.new(fd, 86.0, true)
		if not revealed:
			tile.dimmed = true
			tile.interactive = false
		else:
			tile.long_pressed.connect(func() -> void: DetailCard.show_face(self, fd))
			tile.pressed.connect(func() -> void: DetailCard.show_face(self, fd))
		grid.add_child(tile)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	return cc


# ============================================================ characters

func _build_chars() -> void:
	for id in GameData.hero_ids():
		var def: Dictionary = GameData.heroes[id]
		var unlocked: bool = id in Game.meta.unlocked_heroes
		var rows := []
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		# The codex is where the painted plate is actually worth looking at, so
		# it gets the biggest frame any screen gives it.
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2(168, 190)
		var art := PawnArt.fitted(id, Vector2(168, 184.0))
		art.position = Vector2(84, 186)
		if not unlocked:
			art.modulate = Color(0.02, 0.02, 0.03, 1.0)   # silhouette
		art_holder.add_child(art)
		head.add_child(art_holder)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		if unlocked:
			info.add_child(_line(Data.bi(String(def.zh), String(def.en)), 24, UIKit.CREAM, 500.0))
			info.add_child(_line("HP %d   Lv%d" % [int(def.hp), Game.hero_level(id)], 19, UIKit.CREAM_DARK, 500.0))
			info.add_child(_line(Data.bi(String(def.passive_zh), String(def.passive_en)), 17, UIKit.CREAM_DARK, 500.0))
			if def.has("lore_zh"):
				info.add_child(_line(Data.bi2(String(def.lore_zh), String(def.lore_en)),
						17, UITheme.accent(1), 460.0))
		else:
			info.add_child(_line(Data.t("ui_locked"), 24, UIKit.CREAM_DARK, 500.0))
			info.add_child(_line("%s: %s" % [Data.t("ui_unlock_cond"),
					Data.bi("通關一次後解鎖", "Unlocked after your first full clear")], 17, UIKit.CREAM_DARK, 500.0))
		head.add_child(info)
		rows.append(head)

		if unlocked:
			# the starting twelve are always legible
			rows.append(_line(Data.t("ui_start_faces"), 20, UIKit.YELLOW.lightened(0.3)))
			for die in GameData.DICE_PER_HERO:
				var die_name: String = Data.bi(String(def.get("die_a_zh", "")), String(def.get("die_a_en", "")))
				if die != 0:
					die_name = Data.bi(String(def.get("die_b_zh", "")), String(def.get("die_b_en", "")))
				rows.append(_line("%s  %s" % [Data.t("ui_die_a" if die == 0 else "ui_die_b"), die_name],
						18, UIKit.CREAM_DARK))
				var start: Array = def.start if die == 0 else def.start_b
				var pairs := []
				for fid in start:
					pairs.append([String(fid), true])
				rows.append(_face_grid(pairs))
			# everything else this hero can pick up; the undiscovered ones would
			# otherwise be forty identical "???" tiles, so they collapse to a count
			rows.append(_line(Data.t("ui_all_faces"), UIKit.F_BODY, UITheme.CAT_ON_DARK.control))
			var seen_pairs := []
			var hidden := 0
			for fid2 in _obtainable_faces(id):
				if Game.face_seen(fid2):
					seen_pairs.append([fid2, true])
				else:
					hidden += 1
			if not seen_pairs.is_empty():
				rows.append(_face_grid(seen_pairs))
			if hidden > 0:
				rows.append(_line("??? ×%d   %s" % [hidden,
						Data.bi("(用過一次就會解鎖)", "(unlocked once used)")],
						UIKit.F_BODY_SM, UIKit.CREAM_DARK))
		body.add_child(_panel(rows, Color(def.color) if unlocked else UIKit.OUTLINE))


## XP-unlock faces for this hero plus the shared pool everyone draws from.
func _obtainable_faces(id: String) -> Array:
	var out := []
	var start: Array = GameData.heroes[id].start.duplicate()
	start.append_array(GameData.heroes[id].start_b)
	var unlocks: Dictionary = GameData.heroes[id].unlocks
	for lvl in unlocks:
		var fid := String(unlocks[lvl])
		if fid not in start and fid not in out:
			out.append(fid)
	for fid2 in GameData.shared_pool():
		if fid2 not in out:
			out.append(fid2)
	return out


# ============================================================ monsters

func _build_mobs() -> void:
	body.add_child(_line(Data.bi("小怪", "Minions"), 24, UIKit.YELLOW.lightened(0.3)))
	for key in ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10"]:
		body.add_child(_mob_panel(key))
	body.add_child(_line("Boss", 24, UIKit.YELLOW.lightened(0.3)))
	for key2 in ["B1", "B2", "B3", "B4", "B5", "B6"]:
		body.add_child(_boss_panel(key2))
	body.add_child(_line(Data.t("ui_affixes"), 24, UIKit.YELLOW.lightened(0.3)))
	for key3 in ["frenzied", "stoneskin", "venomous"]:
		body.add_child(_affix_panel(key3))


## The three tiers of one minion, side by side and to scale. Tier is drawn as
## depth of corruption — bulk, tone, cracks, eye heat, mist — and the codex is
## the only place in the game where you get to hold the three up against each
## other. A tier not yet fought stays a silhouette, same as a locked hero.
func _tier_strip(key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", UIKit.S5)
	for tier in [1, 2, 3]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(96, 100)
		# a minion's tier IS the chapter it is met in, so the rim the codex
		# shows is the rim the fight will show
		var art := PawnArt.fitted(key, Vector2(96, 92.0), false, tier, tier)
		art.position = Vector2(48, 96)
		if not Game.enemy_tier_seen(key, tier):
			art.modulate = Color(0.05, 0.04, 0.06, 1.0)
		holder.add_child(art)
		cell.add_child(holder)
		var cap := UIKit.label("T%d" % tier, UIKit.F_CAPTION, UIKit.CREAM_DARK)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(96, 0)
		cell.add_child(cap)
		hb.add_child(cell)
	var cc := CenterContainer.new()
	cc.add_child(hb)
	return cc


## A boss's own art, from the same `PawnArt` the fight uses. Sir Croak takes two
## slots: the codex is where you find out that the thing you killed was only the
## goose.
func _boss_strip(key: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", UIKit.S5)
	var art_keys := ["B3", "B3P2"] if key == "B3" else [key]
	for i in art_keys.size():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(140, 150)
		var art := PawnArt.fitted(String(art_keys[i]), Vector2(140, 142.0))
		art.position = Vector2(70, 146)
		holder.add_child(art)
		cell.add_child(holder)
		if art_keys.size() > 1:
			var cap := UIKit.label(Data.bi("第 %d 階段" % (i + 1), "Phase %d" % (i + 1)),
					UIKit.F_CAPTION, UIKit.CREAM_DARK)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cap.custom_minimum_size = Vector2(140, 0)
			cell.add_child(cap)
		hb.add_child(cell)
	var cc := CenterContainer.new()
	cc.add_child(hb)
	return cc


func _mob_panel(key: String) -> Control:
	var def: Dictionary = GameData.enemies[key]
	var any: bool = Game.enemy_seen(key)
	var rows := []
	if not any:
		rows.append(_line("%s  %s" % [key, Data.t("ui_unknown")], 22, UIKit.CREAM_DARK))
		return _panel(rows)
	rows.append(_line(Data.bi(String(def.zh), String(def.en)), 23))
	rows.append(_tier_strip(key))
	# each tier is its own unlock: fight the T2 version to read the T2 numbers
	for tier in [1, 2, 3]:
		var ti: int = int(tier) - 1
		if not Game.enemy_tier_seen(key, tier):
			rows.append(_line("  T%d  %s" % [tier, Data.t("ui_unknown")], 18, UIKit.CREAM_DARK))
			continue
		rows.append(_line("  T%d  HP %d   %s×%d" % [tier, int(def.hp[ti]),
				Data.t("ui_roll"), int(def.get("dice", 1))], 18, UIKit.CREAM))
		for f in def.faces:
			rows.append(_line("    %s ×%d — %s" % [Data.bi(String(f.zh), String(f.en)),
					int(f.count), _enemy_face_summary(f, ti)], 17, UIKit.CREAM_DARK))
	return _panel(rows)


func _boss_panel(key: String) -> Control:
	var def: Dictionary = GameData.bosses[key]
	var rows := []
	if not Game.boss_seen(key):
		rows.append(_line("%s  %s" % [key, Data.t("ui_unknown")], 22, UIKit.CREAM_DARK))
		return _panel(rows)
	rows.append(_line(Data.bi(String(def.zh), String(def.en)), 23, UIKit.RED.lightened(0.35)))
	rows.append(_boss_strip(key))
	rows.append(_line("  HP %d   %s×%d   %s %d" % [int(def.hp), Data.t("ui_roll"),
			int(def.dice), Data.t("ui_chapter"), int(def.chapter)], 18))
	rows.append(_line("  %s: %s" % [Data.t("ui_boss_gimmick"),
			Data.bi(String(def.gimmick_zh), String(def.gimmick_en))], 17, UIKit.CREAM_DARK))
	for f in def.faces:
		rows.append(_line("    %s ×%d — %s" % [Data.bi(String(f.zh), String(f.en)),
				int(f.count), _enemy_face_summary(f, 0)], 17, UIKit.CREAM_DARK))
	return _panel(rows)


func _affix_panel(key: String) -> Control:
	var def: Dictionary = GameData.encounters.elite_affixes[key]
	if not Game.affix_seen(key):
		return _panel([_line(Data.t("ui_unknown"), 20, UIKit.CREAM_DARK)])
	var desc := ""
	match key:
		"frenzied":
			desc = Data.bi("所有攻擊面 +%d" % int(def.atk_bonus), "All attack faces +%d" % int(def.atk_bonus))
		"stoneskin":
			desc = Data.bi("每回合開始格擋 %d" % int(def.start_block),
					"Gains Block %d each turn" % int(def.start_block))
		"venomous":
			desc = Data.bi("攻擊附帶中毒 %d" % int(def.poison_on_hit),
					"Attacks also inflict Poison %d" % int(def.poison_on_hit))
	return _panel([_line("%s — %s" % [Data.bi(String(def.zh), String(def.en)), desc], 19,
			UIKit.ORANGE.lightened(0.3))])


## Enemy faces store per-tier arrays; flatten one tier into a readable line.
func _enemy_face_summary(f: Dictionary, ti: int) -> String:
	var parts := []
	for k in ["atk", "block", "heal", "poison", "burn", "weaken", "howl"]:
		if not f.has(k):
			continue
		var v: int = int(f[k][ti]) if f[k] is Array else int(f[k])
		parts.append(UIKit.glyph_n(k, v))
	for k2 in ["pierce", "aoe", "bind", "curse", "summon", "expose", "counter",
			"charge", "cancel_die", "mana_drain"]:
		if f.has(k2) and (not (f[k2] is bool) or f[k2]):
			parts.append(UIKit.glyph(k2))
	return " ".join(parts) if not parts.is_empty() else "—"
