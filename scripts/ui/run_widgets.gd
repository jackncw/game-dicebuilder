class_name RunWidgets
extends RefCounted
## Shared widgets for run screens (top bar, face cards, pickers).


static func data() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/Data")


static func game() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/Game")


## Gold / potions / relics / chapter summary bar (top of run screens).
static func topbar() -> Control:
	var d := data()
	var g := game()
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	Safe.pin_top(bar, UIKit.S3)
	bar.offset_left = UIKit.S4
	bar.offset_right = -UIKit.S4
	bar.add_theme_constant_override("separation", UIKit.S3)
	bar.add_child(UIKit.outlined(UIKit.label("%s %d" % [d.t("ui_chapter"),
			int(g.run.chapter)], UIKit.F_BODY, UIKit.CREAM)))
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)
	# resources as chips: the top bar sits straight on the chapter sky, where
	# loose coloured type never clears 4.5:1 on its own
	bar.add_child(UIKit.chip("💰%d" % int(g.run.gold), UIKit.YELLOW, UIKit.F_BODY_SM))
	# the potion chip is the way into the potion list from every non-battle
	# screen, and it wears the drawn bottle rather than the 🧪 emoji: the
	# same picture the shop card and the battle tray use
	var pot := UIKit.icon_chip("p_bottle", str(g.run.potions.size()), UIKit.GREEN,
			UIKit.F_BODY_SM)
	var open_p := Button.new()
	open_p.flat = true
	open_p.set_anchors_preset(Control.PRESET_FULL_RECT)
	open_p.pressed.connect(func() -> void:
		var host: Node = bar
		while host != null and host.get_parent() is Control:
			host = host.get_parent()
		if host is Control:
			Sfx.play("button")
			DetailCard.show_potion_list(host, g.run.potions))
	pot.add_child(open_p)
	bar.add_child(pot)
	# the relic count is the way into the relic list from every non-battle
	# screen — a run-long passive the player cannot re-read is a rule they will
	# simply forget they own
	var relics := UIKit.chip("%s%d" % [d.bi("寶", "R"), g.run.relics.size()],
			UIKit.ORANGE, UIKit.F_BODY_SM)
	var open := Button.new()
	open.flat = true
	open.set_anchors_preset(Control.PRESET_FULL_RECT)
	open.pressed.connect(func() -> void:
		# resolved at press time: the bar does not know its screen at build time
		var host: Node = bar
		while host != null and host.get_parent() is Control:
			host = host.get_parent()
		if host is Control:
			Sfx.play("button")
			show_relics(host))
	relics.add_child(open)
	bar.add_child(relics)
	return bar


## The current party standing on a ground line, used to fill the bottom of the
## non-battle run screens. Decorative only: no input, and PawnArt redraws just
## twice a second for its stepped idle.
static func party_strip(ground_y: float, height := 150.0) -> Control:
	var g := game()
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var team: Array = g.run.get("team", [])
	for i in team.size():
		var hero: Dictionary = team[i]
		var shadow := Panel.new()
		var sb := UIKit.flat_box(Color(0, 0, 0, 0.28), 999, 0, UIKit.OUTLINE, 0)
		sb.set_border_width_all(0)
		shadow.add_theme_stylebox_override("panel", sb)
		shadow.position = Vector2(116.0 + i * 163.0 - height * 0.29, ground_y - 4)
		shadow.size = Vector2(height * 0.58, 16)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(shadow)
		var pa := PawnArt.fitted(String(hero.id), Vector2(height, height))
		pa.position = Vector2(116.0 + i * 163.0, ground_y + 4)
		if int(hero.hp) <= 0:
			pa.modulate = Color(0.42, 0.4, 0.4, 0.85)
		stage.add_child(pa)
	return stage


## Width of the portrait gutter on an offer card bound to a character.
const PORTRAIT_COL := 80.0
## Same gutter, for an offer that is an object rather than a person.
const ICON_COL := 64.0


## One offer in the run screens — face, relic, potion or service — all built to
## the same card shape so a shop list reads as one kind of thing.
##
## `hero_id` ("H1"…"H6") puts that character's face and name down the left edge.
## Anything the player has to hand to somebody in particular says whose it is
## before it says what it does.
##
## `icon` is a glyph key (a relic's or a potion's) shown in a disc down the
## left edge, where a character portrait would go. A shop row for an object the
## player will later have to recognise in a 36px strip has to show them that
## picture at the moment they buy it, or the strip is a row of strangers.
static func offer_card(title_text: String, summary: String, subtitle: String,
		hue: Color, on_press: Callable, min_size := Vector2(648, 108),
		price := -1, hero_id := "", icon := "") -> Button:
	var b := UIKit.button("", UIKit.CREAM, UIKit.F_BODY, min_size)
	b.clip_contents = true
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
	sb.border_color = hue
	sb.set_border_width_all(UIKit.B_STRONG)
	var has_portrait: bool = hero_id != "" and GameData.heroes.has(hero_id)
	var has_icon: bool = icon != "" and not has_portrait
	var text_w := min_size.x - 2 * UIKit.S5 - (84.0 if price >= 0 else 0.0) \
			- (PORTRAIT_COL + UIKit.S3 if has_portrait else 0.0) \
			- (ICON_COL + UIKit.S3 if has_icon else 0.0)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(UIKit.text_block(title_text, UIKit.F_BODY, hue.darkened(0.35), text_w))
	if summary != "":
		vb.add_child(UIKit.text_block(summary, UIKit.F_BODY_SM, UITheme.INK, text_w))
	if subtitle != "":
		vb.add_child(UIKit.text_block(subtitle, UIKit.F_BODY_SM, UITheme.INK_SOFT, text_w))
	# the portrait and the text share one row; the row is what stops short of
	# the price badge, or a long description slides under the chip
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", UIKit.S3)
	row.offset_left = UIKit.S2
	row.offset_right = -84.0 if price >= 0 else -float(UIKit.S2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_portrait:
		row.add_child(_portrait_col(hero_id, min_size.y))
	if has_icon:
		var badge := ItemIcon.new(icon, hue, minf(ICON_COL, min_size.y - 40.0))
		badge.interactive = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icc := CenterContainer.new()
		icc.custom_minimum_size = Vector2(ICON_COL, 0)
		icc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icc.add_child(badge)
		row.add_child(icc)
	row.add_child(vb)
	b.add_child(row)
	# a price is the one thing on a shop card the player scans for, so it gets
	# its own badge in the corner instead of a third grey line
	if price >= 0:
		var tag := UIKit.chip("💰%d" % price, UIKit.YELLOW, UIKit.F_BODY, UIKit.S2)
		tag.anchor_left = 1.0
		tag.anchor_right = 1.0
		tag.anchor_top = 0.5
		tag.anchor_bottom = 0.5
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tag.grow_vertical = Control.GROW_DIRECTION_BOTH
		tag.offset_left = -UIKit.S3
		tag.offset_right = -UIKit.S3
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Portrait + name, the left gutter of a bound offer card. The disc grows with
## the card so the roomier reward cards do not waste the space.
static func _portrait_col(hero_id: String, card_h: float) -> Control:
	var d := data()
	var def: Dictionary = GameData.heroes[hero_id]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size = Vector2(PORTRAIT_COL, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(MiniPortrait.make(hero_id, clampf(card_h - 54.0, 48.0, 72.0)))
	col.add_child(cc)

	# bilingual mode stacks the two names; running them together at F_MICRO in an
	# 80px gutter wraps into an unreadable ribbon
	var short_en: String = String(def.get("short", def.en))
	var text: String = d.bi(String(def.zh), short_en)
	if d.lang_mode() == "both":
		text = "%s\n%s" % [def.zh, short_en]
	var nm := UIKit.label(text, UIKit.F_MICRO, UITheme.INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(PORTRAIT_COL, 26)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	return col


## One-line face description, e.g. "攻5 穿刺" (localized keywords).
static func face_summary(face_id: String) -> String:
	var d := data()
	var fd: Dictionary = GameData.faces[face_id]
	var parts := []
	if fd.has("atk"):
		parts.append(d.bi("攻%d" % int(fd.atk), "Atk %d" % int(fd.atk)))
	if fd.has("random_atk"):
		parts.append(d.bi("攻%d-%d" % [int(fd.random_atk[0]), int(fd.random_atk[1])],
				"Atk %d-%d" % [int(fd.random_atk[0]), int(fd.random_atk[1])]))
	if fd.has("block"):
		parts.append(d.bi("擋%d" % int(fd.block), "Blk %d" % int(fd.block)))
	if fd.has("heal"):
		parts.append(d.bi("療%d" % int(fd.heal), "Heal %d" % int(fd.heal)))
	if fd.has("team_block"):
		parts.append(d.bi("隊擋%d" % int(fd.team_block), "Team blk %d" % int(fd.team_block)))
	if fd.has("team_heal"):
		parts.append(d.bi("隊療%d" % int(fd.team_heal), "Team heal %d" % int(fd.team_heal)))
	if fd.has("team_thorns"):
		parts.append(d.bi("隊棘%d" % int(fd.team_thorns), "Team thorns %d" % int(fd.team_thorns)))
	if fd.has("team_regen"):
		parts.append(d.bi("隊生%d" % int(fd.team_regen), "Team regen %d" % int(fd.team_regen)))
	if fd.has("mana"):
		parts.append(d.bi("靈息+%d" % int(fd.mana), "Essence +%d" % int(fd.mana)))
	if fd.has("rerolls"):
		parts.append(d.bi("重擲+%d" % int(fd.rerolls), "Reroll +%d" % int(fd.rerolls)))
	if fd.has("regen"):
		parts.append(d.bi("生%d" % int(fd.regen), "Regen %d" % int(fd.regen)))
	for kw in Glossary.sub_terms(fd):
		if kw in ["spell", "self_heal", "cleanse_self", "cleanse_target"]:
			continue    # printed separately below / not worth a summary slot
		var nm := Glossary.term_name(kw)
		if not (fd[kw] is bool):
			nm += str(int(fd[kw]))
		parts.append(nm)
	if fd.has("spell"):
		parts.append(d.bi("靈術%d" % int(fd.spell), "Ritual %d" % int(fd.spell)))
	return " ".join(parts)


static func rarity_color(face_id: String) -> Color:
	match String(GameData.faces[face_id].get("rarity", "C")):
		"E": return UIKit.ORANGE
		"R": return UIKit.PURPLE
		"U": return UIKit.GREEN
		_: return UIKit.OUTLINE


## Clickable face card (name + summary + rarity edge). `plus` appends the
## forge marks earned by this particular face instance.
##
## `hero_id` is the character the offer is bound to. Left empty it falls back to
## whoever the face itself belongs to, which is what gives the shop, the chest
## and the event rewards their portraits — a hero-specific face is somebody's
## signature move whether or not this particular offer was dealt to them. The
## shared `sp_*` pool belongs to nobody, so those cards keep the plain shape.
static func face_card(face_id: String, subtitle: String, on_press: Callable, min_size := Vector2(648, 108), plus := 0, price := -1, hero_id := "") -> Control:
	var d := data()
	var fd: Dictionary = GameData.faces[face_id]
	var mark := "+".repeat(maxi(plus, 0))
	var who: String = hero_id if hero_id != "" else String(fd.get("hero", ""))
	# the card's edge carries rarity, its title the category — both codes are
	# the same ones the codex and the dice use
	var card := offer_card(d.bi(String(fd.zh) + mark, String(fd.en) + mark),
			face_summary(face_id), subtitle,
			UIKit.cat_color(String(fd.get("cat", "special"))), on_press, min_size,
			price, who)
	var sb: StyleBoxFlat = card.get_theme_stylebox("normal")
	sb.border_color = rarity_color(face_id)
	return card


## Face-swap entry points. Both are thin wrappers over `FaceSwap`, which owns
## the actual screen — these two signatures are what the run screens already
## call, and keeping them means the shop, the treasure chest, the reward screen
## and the forge all reached the new UI in one change.

## One character's dice, bound to them: post-battle offers land here.
## cb(slot).
static func pick_hero_face(parent: Control, hero: Dictionary, title: String,
		incoming: String, cb: Callable, filter := Callable()) -> void:
	var g := game()
	var idx := 0
	for i in g.run.team.size():
		if g.run.team[i] == hero:
			idx = i
	FaceSwap.open(parent, idx, incoming, title,
			func(_hi: int, slot: int) -> void: cb.call(slot), filter)


## Anyone's dice: shop purchases, treasure and forging, where the player also
## chooses who gets it. cb(hero_i, slot).
static func pick_team_face(parent: Control, title: String, cb: Callable,
		filter := Callable(), incoming := "") -> void:
	FaceSwap.open(parent, -1, incoming, title, cb, filter)


## Just look: one character's twelve faces, nothing selectable. Raised by
## holding a character anywhere on the reward screen's roster strip.
static func view_hero_dice(parent: Control, hero_i: int) -> Control:
	var g := game()
	var hero: Dictionary = g.run.team[hero_i]
	var def: Dictionary = GameData.heroes[hero.id]
	return FaceSwap.open(parent, hero_i, "",
			"%s — %s" % [data().bi(String(def.zh), String(def.en)),
					data().t("ui_view_dice")],
			Callable(), Callable(), true)


## The party's relics, as a card. The run top bar and the battle screen both
## open the same one.
static func show_relics(parent: Control) -> Control:
	return DetailCard.show_relic_list(parent, game().run.get("relics", []))



## What the party is carrying, as one row of icons — relics first, then
## potions. Tap an icon for the full list, hold it to read that one thing.
##
## The shop is where this matters: "do I already own this?" and "what does the
## one I own actually do?" were both questions you had to leave the counter to
## answer. Same icons as the battle strip, same gesture as a die face.
## `source` overrides where the two lists come from — the victory tally
## passes the copy it was handed, because the run is already wiped by then.
static func owned_strip(host: Control, source := {}) -> Control:
	var g := game()
	var bag: Dictionary = source if not source.is_empty() else g.run
	var relics: Array = bag.get("relics", [])
	var potions: Array = bag.get("potions", [])
	var panel := UIKit.panel(UIKit.surface(int(g.run.get("chapter", 1))),
			UIKit.R_MD, UIKit.B_HAIR)
	var box: StyleBoxFlat = panel.get_theme_stylebox("panel")
	box.set_content_margin_all(UIKit.S3)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UIKit.S2)
	panel.add_child(col)
	col.add_child(UIKit.label(data().bi("攜帶中", "Carrying"), UIKit.F_CAPTION,
			UIKit.CREAM_DARK))
	if relics.is_empty() and potions.is_empty():
		col.add_child(UIKit.label(data().bi("(空)", "(nothing yet)"), UIKit.F_CAPTION,
				UIKit.CREAM_DARK))
		return panel
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UIKit.S2)
	flow.add_theme_constant_override("v_separation", UIKit.S2)
	col.add_child(flow)
	for rid_v in relics:
		var rid := String(rid_v)
		if not GameData.relics.has(rid):
			continue
		var ric := ItemIcon.for_relic(rid)
		ric.pressed.connect(func() -> void:
			Sfx.play("button")
			DetailCard.show_relic_info(host, rid))
		ric.long_pressed.connect(func() -> void: DetailCard.show_relic_info(host, rid))
		flow.add_child(ric)
	for pid_v in potions:
		var pid := String(pid_v)
		if not GameData.potions.has(pid):
			continue
		var pic := ItemIcon.for_potion(pid)
		pic.pressed.connect(func() -> void:
			Sfx.play("button")
			DetailCard.show_potion(host, pid))
		pic.long_pressed.connect(func() -> void: DetailCard.show_potion(host, pid))
		flow.add_child(pic)
	return panel