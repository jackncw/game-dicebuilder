extends Control
## Event node: shows one of 12 events (no repeats within a run), resolves the
## chosen option, shows an outcome line, then completes the node.

var event_id := ""
var vb: VBoxContainer


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var rng := RunState.rng_of(Game.run)
	if not Game.run.has("seen_events"):
		Game.run["seen_events"] = []
	var pool := []
	for eid in GameData.events:
		if eid not in Game.run.seen_events:
			pool.append(eid)
	pool.sort()
	if pool.is_empty():
		pool = GameData.events.keys()
		pool.sort()
	event_id = pool[rng.randi_range(0, pool.size() - 1)]
	Game.run.seen_events.append(event_id)
	RunState.save_rng(Game.run, rng)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 104.0, 1010.0))
	add_child(RunWidgets.topbar())
	add_child(RunWidgets.party_strip(1014.0, 152.0))

	var ev: Dictionary = GameData.events[event_id]
	# 任務2 通用規則:選項多或者事件文長,內容區捲動,唔好逼埋 party strip。
	# 底界係 party strip 條地線(1014,由頂數,同背景嘅 horizon 綁埋一齊),
	# 所以呢度用固定 offset 而唔係 bottom pin。
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 0.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Safe.pin_top(scroll, 96)
	scroll.offset_bottom = 866.0
	scroll.offset_left = UIKit.S6
	scroll.offset_right = -UIKit.S6
	add_child(scroll)
	vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", UIKit.S4)
	scroll.add_child(vb)

	vb.add_child(UIKit.title(Data.bi(String(ev.zh), String(ev.en)), UIKit.F_H1))

	var panel := UIKit.panel(UIKit.CREAM, UIKit.R_LG, UIKit.B_STRONG)
	var psb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	psb.set_content_margin_all(UIKit.S5)
	psb.shadow_color = UITheme.SHADOW
	psb.shadow_size = 6
	psb.shadow_offset = UITheme.SHADOW_OFFSET
	panel.add_child(UIKit.text_block(Data.bi(String(ev.text_zh), String(ev.text_en)),
			UIKit.F_BODY, UITheme.INK, 560.0, HORIZONTAL_ALIGNMENT_LEFT))
	var pc := CenterContainer.new()
	pc.add_child(panel)
	vb.add_child(pc)
	vb.add_child(UIKit.spacer(UIKit.S2))

	for oi in ev.options.size():
		var opt: Dictionary = ev.options[oi]
		var disabled := false
		if opt.has("requires_gold") and int(Game.run.gold) < int(opt.requires_gold):
			disabled = true
		var opt_c := opt
		var b := RunWidgets.offer_card(Data.bi(String(opt.zh), String(opt.en)), "", "",
				UIKit.CREAM_DARK.darkened(0.35), func() -> void:
					Sfx.play("button")
					_resolve(opt_c), Vector2(624, 96))
		b.disabled = disabled
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)


func _resolve(opt: Dictionary) -> void:
	var rng := RunState.rng_of(Game.run)
	var outcome := ""
	match String(opt.effect):
		"none":
			Game.node_completed()
			return
		"team_heal":
			RunState.team_alive_heal_flat(Game.run, int(opt.value))
			outcome = Data.bi("全隊回復 %d HP" % int(opt.value), "Party healed %d HP" % int(opt.value))
		"gold":
			Game.run.gold = int(Game.run.gold) + int(opt.value)
			outcome = Data.bi("獲得 %d 金" % int(opt.value), "Gained %d gold" % int(opt.value))
		"lose_gold":
			Game.run.gold = maxi(int(Game.run.gold) - int(opt.value), 0)
			outcome = Data.bi("失去金幣", "Lost gold")
		"gamble":
			Game.run.gold = int(Game.run.gold) - int(opt.cost)
			var roll := rng.randi_range(1, 6)
			if roll >= 4:
				Game.run.gold = int(Game.run.gold) + int(opt.win)
				outcome = Data.bi("擲出 %d — 贏得 %d 金幣!" % [roll, int(opt.win)],
						"Rolled %d — won %d gold!" % [roll, int(opt.win)])
			else:
				outcome = Data.bi("擲出 %d — 全部輸掉……" % roll, "Rolled %d — lost it all…" % roll)
		"sacrifice_relic":
			for h in Game.run.team:
				if h.hp > 0:
					h.hp = maxi(int(h.hp) - int(opt.value), 1)
			var rid := Game._random_new_relic(rng)
			Game.add_relic(rid)
			if rid != "":
				# same as every other relic source: it gets its own card, and
				# the player has to acknowledge it before the node closes
				RunState.save_rng(Game.run, rng)
				var rdef2: Dictionary = GameData.relics[rid]
				DetailCard.show_relic(self, rid, func() -> void:
					_show_outcome("%s:%s" % [Data.t("ui_relic_gained"),
							Data.bi(String(rdef2.zh), String(rdef2.en))]))
				return
			outcome = Data.bi("祭壇沉寂下來,沒有回應。", "The altar falls silent.")
		"escort_imp":
			Game.run.pending_imp = true
			outcome = Data.bi("小妖跟著你們出發……", "The imp tags along…")
		"marsh_poison":
			Game.run.pending_marsh = int(opt.value)
			outcome = Data.bi("毒氣滲入皮膚……", "The fumes seep in…")
		"skip_row":
			Game.run.skip_row = true
			outcome = Data.bi("你們繞過了前方的道路", "You go the long way around")
		"free_forge":
			RunState.save_rng(Game.run, rng)
			RunWidgets.pick_team_face(self, Data.t("ui_forge"),
				func(hi: int, slot: int) -> void:
					RunState.forge_face(Game.run.team[hi], slot)
					Sfx.play("win")
					Game.node_completed(),
				func(hero: Dictionary) -> Array:
					return RunState.forgeable_slots(hero))
			return
		"team_heal_pct":
			RunState.team_alive_heal_pct(Game.run, int(opt.value))
			outcome = Data.bi("全隊回復 %d%% HP" % int(opt.value), "Party healed %d%%" % int(opt.value))
		"enchant_face":
			RunState.save_rng(Game.run, rng)
			RunWidgets.pick_team_face(self, Data.bi("選擇一個骰面附魔", "Choose a face to enchant"),
				func(hi: int, slot: int) -> void:
					var rng2 := RunState.rng_of(Game.run)
					var kws := [{"pierce": true}, {"lifesteal": true}, {"combo": true},
							{"lucky": true}, {"poison": 2}, {"burn": 2}, {"thorns": 2}]
					var kw: Dictionary = kws[rng2.randi_range(0, kws.size() - 1)]
					var hero: Dictionary = Game.run.team[hi]
					for k in kw:
						hero.face_extras[slot][k] = kw[k]
					RunState.save_rng(Game.run, rng2)
					Sfx.play("win")
					Game.node_completed())
			return
		"reforge_up":
			RunState.save_rng(Game.run, rng)
			RunWidgets.pick_team_face(self, Data.bi("選擇一個骰面重鑄", "Choose a face to reforge"),
				func(hi: int, slot: int) -> void:
					var rng2 := RunState.rng_of(Game.run)
					var hero: Dictionary = Game.run.team[hi]
					var cur_r: String = GameData.faces[hero.faces[slot]].get("rarity", "C")
					var target_r := "R"
					if cur_r == "R" or cur_r == "E" or cur_r == "U":
						target_r = "E"
					var pool := GameData.shared_pool(target_r)
					var nf: String = pool[rng2.randi_range(0, pool.size() - 1)]
					RunState.apply_face_swap(Game.run, hi, slot, nf)
					RunState.save_rng(Game.run, rng2)
					Sfx.play("win")
					Game.node_completed())
			return
		"caravan_shop":
			RunState.save_rng(Game.run, rng)
			_caravan()
			return
		"bless_hero":
			RunState.save_rng(Game.run, rng)
			_pick_hero(func(hi: int) -> void:
				var hero: Dictionary = Game.run.team[hi]
				hero.max_hp = int(hero.max_hp) + int(opt.value)
				hero.hp = int(hero.max_hp)
				Sfx.play("heal")
				Game.node_completed())
			return
		"thief_battle":
			Game.run["pending_thief"] = true
			RunState.save_rng(Game.run, rng)
			var pool2: Array = GameData.encounters.elite_pools[str(Game.run.chapter)]
			var key: String = pool2[rng.randi_range(0, pool2.size() - 1)]
			var affixes := ["frenzied", "stoneskin", "venomous"]
			RunState.save_rng(Game.run, rng)
			Game._start_battle([key], "elite", affixes[rng.randi_range(0, 2)])
			return
		"idol_light":
			Game.run.run_atk_buff = int(Game.run.run_atk_buff) + 1
			for h in Game.run.team:
				h.max_hp = maxi(int(h.max_hp) - 3, 1)
				h.hp = clampi(int(h.hp), 0 if h.hp <= 0 else 1, int(h.max_hp))
			outcome = Data.bi("力量湧入你們的武器", "Power floods your weapons")
		"idol_dark":
			for h in Game.run.team:
				h.max_hp = int(h.max_hp) + 6
			Game.run.gold_pct = 80
			outcome = Data.bi("你們感到更強壯,但錢袋變輕了", "You feel sturdier, but poorer")
	RunState.save_rng(Game.run, rng)
	_show_outcome(outcome)


func _caravan() -> void:
	var rng := RunState.rng_of(Game.run)
	var faces := []
	for i in 3:
		faces.append(RunState._roll_shared_face(rng))
	RunState.save_rng(Game.run, rng)
	for c in vb.get_children():
		c.queue_free()
	var title := UIKit.label(Data.bi("流浪商隊(七折)", "Caravan (30% off)"), 30, UIKit.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for fid_v in faces:
		var fid: String = fid_v
		var price := int(floor(RunState.face_price(fid) * 0.7))
		var card := RunWidgets.face_card(fid, "", func() -> void:
			if int(Game.run.gold) < price:
				Sfx.play("block", 0.5)
				return
			RunWidgets.pick_team_face(self, Data.t("ui_pick_replace"),
				func(hi: int, slot: int) -> void:
					Game.run.gold = int(Game.run.gold) - price
					RunState.apply_face_swap(Game.run, hi, slot, fid)
					Sfx.play("win")
					Game.node_completed()), Vector2(648, 108), 0, price)
		var cc := CenterContainer.new()
		cc.add_child(card)
		vb.add_child(cc)
	var leave := UIKit.button(Data.t("ui_leave"), UIKit.CREAM_DARK, 24, Vector2(240, 70))
	leave.pressed.connect(func() -> void: Game.node_completed())
	var lc := CenterContainer.new()
	lc.add_child(leave)
	vb.add_child(lc)


func _pick_hero(cb: Callable) -> void:
	for c in vb.get_children():
		c.queue_free()
	var title := UIKit.label(Data.bi("選擇一位英雄", "Choose a hero"), 30, UIKit.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for hi in Game.run.team.size():
		var hero: Dictionary = Game.run.team[hi]
		var hdef: Dictionary = GameData.heroes[hero.id]
		var b := UIKit.button("%s  HP %d/%d" % [Data.bi(String(hdef.zh), String(hdef.en)), int(hero.hp), int(hero.max_hp)],
				UIKit.CREAM, 24, Vector2(520, 84))
		var idx: int = hi
		b.pressed.connect(func() -> void: cb.call(idx))
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)


func _show_outcome(text: String) -> void:
	for c in vb.get_children():
		c.queue_free()
	var panel := UIKit.panel(UIKit.CREAM, 16, 4)
	var l := UIKit.label(text, 26, UIKit.OUTLINE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	panel.add_child(l)
	var pc := CenterContainer.new()
	pc.add_child(panel)
	vb.add_child(UIKit.spacer(120))
	vb.add_child(pc)
	var b := UIKit.button(Data.t("ui_leave"), UIKit.CREAM, 26, Vector2(260, 76))
	b.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.node_completed())
	var bc := CenterContainer.new()
	bc.add_child(b)
	vb.add_child(bc)
