extends Control
## Post-battle spoils, settled in one fixed order: gold → relics → the
## three-face offer.
##
## The relic half is deliberately blocking. A relic changes how the rest of the
## run plays, and the old screen mentioned one in a grey line on a recap card
## that scrolled past in half a second — players finished runs without knowing
## what they were carrying. Now every relic gained raises its own card and waits
## to be acknowledged, and a boss's Advanced pair is a choice made on a screen
## of its own before anything else can be touched.
##
## The offer cards carry the full effect sentence rather than "攻5 穿刺", and
## the roster strip along the bottom answers the question those cards raise —
## "what has this character already got?" — with a die you can actually turn
## over and a hold that opens all twelve faces.

var _offer_box: VBoxContainer
## Which die each character's strip token is showing (0 = A, 1 = B).
var _strip_die := {}
var _strip_dice := {}      # hero index → Die3D
var _strip_labels := {}    # hero index → the A/B caption under it


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	var chapter := int(Game.run.chapter)
	add_child(UIKit.background(chapter, 104.0, 1042.0))
	add_child(RunWidgets.topbar())

	var pr: Dictionary = Game.pending_reward
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	Safe.pin_top(vb, 62)
	vb.offset_left = UIKit.S5
	vb.offset_right = -UIKit.S5
	vb.add_theme_constant_override("separation", UIKit.S3)
	add_child(vb)

	vb.add_child(UIKit.title(Data.t("ui_victory"), UIKit.F_H1))

	# ① gold + xp, on one card rather than four floating lines
	var recap := UIKit.card(chapter)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UIKit.S1)
	recap.add_child(rv)
	var money := HBoxContainer.new()
	money.alignment = BoxContainer.ALIGNMENT_CENTER
	money.add_theme_constant_override("separation", UIKit.S3)
	money.add_child(UIKit.chip("%s +%d" % [Data.t("ui_gold_reward"), int(pr.gold)],
			UIKit.YELLOW, UIKit.F_BODY, UIKit.S3))
	money.add_child(UIKit.chip("XP +%d" % int(pr.get("xp_amount", 1)),
			UIKit.BLUE, UIKit.F_BODY, UIKit.S3))
	rv.add_child(money)
	var ups: Dictionary = pr.get("xp_ups", {})
	for id in ups:
		var hdef: Dictionary = GameData.heroes[id]
		rv.add_child(UIKit.text_block(Data.bi("%s 升級了!新骰面已加入獎勵池" % hdef.zh,
				"%s levelled up! New face added to pools" % hdef.en),
				UIKit.F_BODY_SM, UITheme.CAT_ON_DARK.heal, 600.0))
	vb.add_child(recap)

	# ③ the offer (built now, revealed behind the relic cards)
	vb.add_child(UIKit.outlined(UIKit.text_block(Data.t("ui_offer_title"),
			UIKit.F_H2, UIKit.CREAM, 640.0)))
	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", UIKit.S3)
	vb.add_child(_offer_box)
	for offer in pr.offers:
		_offer_box.add_child(_offer_card(offer))

	add_child(_roster_strip(ROSTER_TOP))
	var tray := UIKit.footer(chapter, 116.0)
	add_child(tray)
	var skip := UIKit.button("%s (+%d💰)" % [Data.t("ui_skip"), int(GameData.balance.offer_skip_gold)],
			UIKit.CREAM_DARK, UIKit.F_BODY, Vector2(300, 72))
	skip.pressed.connect(func() -> void:
		Sfx.play("button")
		Game.run.gold = int(Game.run.gold) + int(GameData.balance.offer_skip_gold)
		Game.node_completed())
	tray.get_child(0).add_child(UIKit.button_row([skip]))

	# ② the relics, over the top of all of it — one card each, confirmed in turn
	_present_relics()


# ============================================================ relics

## Auto-granted relics first, one card at a time, then the boss's Advanced
## 2-pick. Each card blocks until it is acknowledged, so nothing is ever
## "collected" without having been read.
func _present_relics() -> void:
	var queue := []
	for rid in Game.pending_reward.get("extra_relics", []):
		if String(rid) != "" and GameData.relics.has(rid):
			queue.append(String(rid))
	_show_next_relic(queue, 0)


func _show_next_relic(queue: Array, i: int) -> void:
	if i >= queue.size():
		_present_advanced_choice()
		return
	Sfx.play("win")
	DetailCard.show_relic(self, String(queue[i]),
			func() -> void: _show_next_relic(queue, i + 1))


## The boss reward: two Advanced relics, take one. After the chapter 3 boss
## the run is already over, so the pair is shown for the look of the thing and
## marked as such rather than being quietly skipped.
func _present_advanced_choice() -> void:
	var choice: Array = Game.pending_reward.get("advanced", [])
	if choice.is_empty():
		return
	var showcase: bool = bool(Game.pending_reward.get("advanced_showcase", false))
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)

	# the column is inset from the canvas edges: a bilingual title at F_H1 is
	# wider than 720px, and an unwrapped one runs straight off both sides
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UIKit.S4
	col.offset_right = -UIKit.S4
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UIKit.S3)
	root.add_child(col)
	col.add_child(UIKit.outlined(UIKit.text_block(Data.t("ui_relic_pick"),
			UIKit.F_H2, UIKit.CREAM, 660.0), 6))
	col.add_child(UIKit.text_block(Data.bi2("高級遺物只會在頭目戰後出現,每一個都能撐起一種流派。",
			"Advanced relics only appear after a boss. Each one can carry a whole build."),
			UIKit.F_CAPTION, UIKit.CREAM_DARK, 640.0))
	if showcase:
		col.add_child(UIKit.text_block(Data.t("ui_showcase_only"), UIKit.F_BODY_SM,
				UITheme.CAT_ON_DARK.control, 640.0))
	for rid_v in choice:
		var rid := String(rid_v)
		var cc := CenterContainer.new()
		cc.add_child(_advanced_card(rid, root, showcase))
		col.add_child(cc)
	if showcase:
		var cc2 := CenterContainer.new()
		var close := UIKit.button(Data.t("ui_ok"), UIKit.CREAM_DARK, UIKit.F_BODY,
				Vector2(240, 66))
		close.pressed.connect(func() -> void:
			Sfx.play("button")
			root.queue_free())
		cc2.add_child(close)
		col.add_child(cc2)


## An Advanced relic on the pick screen: gold rim, glow, the full description.
## It has to be obvious at a glance that this is not the same class of object
## as the Common relic that fell out of the last elite.
func _advanced_card(rid: String, root: Control, showcase: bool) -> Control:
	var rd: Dictionary = GameData.relics[rid]
	const CARD_W := 640.0
	var b := UIKit.button("", UITheme.CREAM, UIKit.F_BODY, Vector2(CARD_W, 0))
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
	sb.border_color = UITheme.YELLOW
	sb.set_border_width_all(UIKit.B_FOCUS + 1)
	sb.shadow_color = Color(UITheme.YELLOW.r, UITheme.YELLOW.g, UITheme.YELLOW.b, 0.5)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2.ZERO
	# a Button lays its children out over its whole rect, so the content is one
	# VBox that measures itself and lets the card grow to fit. Anchoring the
	# description to the bottom (the first attempt) clipped it the moment the
	# bilingual text needed a third line.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UIKit.S3
	col.offset_right = -UIKit.S3
	col.offset_top = UIKit.S2
	col.offset_bottom = -UIKit.S2
	col.add_theme_constant_override("separation", UIKit.S2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(DetailCard.relic_head(rid, 68.0))
	col.add_child(UIKit.text_block(Data.bi2(String(rd.desc_zh), String(rd.desc_en)),
			UIKit.F_BODY_SM, UITheme.INK, CARD_W - 2 * UIKit.S4,
			HORIZONTAL_ALIGNMENT_LEFT))
	b.add_child(col)
	# grow the button to whatever the content measured, once it has measured
	_fit_card.call_deferred(b, col)
	b.pressed.connect(func() -> void:
		if showcase:
			Sfx.play("button")
			return
		Sfx.play("win")
		Game.add_relic(rid)
		root.queue_free()
		DetailCard.show_relic(self, rid))
	return b


## An offer card is as tall as its text. Deferred so the VBox has been sorted
## and actually knows what that is.
static func _fit_card(card: Control, content: Control) -> void:
	if not is_instance_valid(card) or not is_instance_valid(content):
		return
	card.custom_minimum_size.y = maxf(content.size.y + 2 * UITheme.S3, 120.0)


# ============================================================ the offer

## One offer, bound to one character. The card says what the face actually does
## in a full sentence — a player deciding whether to give up a slot on their die
## should not have to decode "攻4 穿刺" first.
func _offer_card(offer: Dictionary) -> Control:
	var hi := int(offer.hero)
	var hero: Dictionary = Game.run.team[hi]
	var fid := String(offer.face)
	var fd: Dictionary = GameData.faces[fid].duplicate(true)
	fd["id"] = fid
	var card := RunWidgets.offer_card(
			Data.face_name(fd), Glossary.effect_sentence(fd),
			Glossary.target_line(fd),
			UIKit.cat_color(String(fd.get("cat", "special"))),
			func() -> void:
				Sfx.play("button")
				RunWidgets.pick_hero_face(self, hero,
						"%s → %s" % [Data.t("ui_offer_title"), Data.face_name(fd)],
						fid,
						func(slot: int) -> void:
							RunState.apply_face_swap(Game.run, hi, slot, fid)
							Sfx.play("win")
							Game.node_completed()),
			Vector2(650, 200), -1, String(hero.id))
	var sb: StyleBoxFlat = card.get_theme_stylebox("normal")
	sb.border_color = RunWidgets.rarity_color(fid)
	var wrap := CenterContainer.new()
	wrap.add_child(card)
	return wrap


# ============================================================ roster strip

## The party along the bottom, but playable: each character carries a small die
## you can flick, tap to switch between their A and B die, and hold — anywhere
## on the token — to open all twelve of their faces. It is the answer to the
## question every offer card raises without making the player leave the screen.
## The strip sits between the offer list and the footer tray. Both of those are
## fixed, so the band it gets is fixed too — the token below is sized to fit it
## rather than the other way round.
const ROSTER_TOP := 1000.0
const ROSTER_H := 150.0


func _roster_strip(y: float) -> Control:
	var stage := Control.new()
	stage.anchor_left = 0.0
	stage.anchor_right = 1.0
	stage.offset_top = y
	stage.offset_bottom = y + ROSTER_H
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UIKit.S2)
	stage.add_child(row)
	for i in Game.run.team.size():
		row.add_child(_roster_token(i))
	# the caption goes ABOVE the tokens: below them it lands on the name plates,
	# and the band between the offer list and the footer has no slack to give
	var hint := UIKit.text_block(Data.t("ui_tap_die_swap"), UIKit.F_MICRO,
			UIKit.CREAM_DARK, 660.0)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.offset_top = -18.0
	hint.offset_bottom = 0.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hint)
	return stage


const TOKEN_W := 156.0


func _roster_token(i: int) -> Control:
	var hero: Dictionary = Game.run.team[i]
	var def: Dictionary = GameData.heroes[hero.id]
	_strip_die[i] = int(_strip_die.get(i, 0))
	var panel := UIKit.card(int(Game.run.chapter), UIKit.R_MD, UIKit.B_STRONG,
			UIKit.OUTLINE, UIKit.S1)
	panel.custom_minimum_size = Vector2(TOKEN_W, 0)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	# the die, on top and turnable
	var dv := Die3D.new(Vector2(62, 62))
	dv.hero = i
	dv.die = _strip_die[i]
	dv.enable_free_spin()
	dv.set_die(_hero_faces(i, _strip_die[i]), 0)
	dv.pressed.connect(func(_h: int, _d: int) -> void: _flip_token(i))
	dv.long_pressed.connect(func(_h: int, _d: int) -> void:
		RunWidgets.view_hero_dice(self, i))
	_strip_dice[i] = dv
	var dc := CenterContainer.new()
	dc.add_child(dv)
	col.add_child(dc)

	var which := UIKit.label(Data.t("ui_die_a" if _strip_die[i] == 0 else "ui_die_b"),
			UIKit.F_MICRO, UITheme.CAT_ON_DARK.control)
	which.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip_labels[i] = which
	col.add_child(which)

	var pc := CenterContainer.new()
	pc.add_child(MiniPortrait.make(String(hero.id), 38.0, UITheme.CREAM_DARK,
			UITheme.surface(int(Game.run.chapter))))
	col.add_child(pc)

	var nm := UIKit.label(String(def.short), UIKit.F_MICRO, UIKit.CREAM)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	# holding anywhere on the token — not only the die — opens the 12 faces
	UIKit.mouse_passthrough(which)
	UIKit.mouse_passthrough(pc)
	UIKit.mouse_passthrough(nm)
	var hold := Button.new()
	hold.flat = true
	hold.set_anchors_preset(Control.PRESET_FULL_RECT)
	hold.pressed.connect(func() -> void: RunWidgets.view_hero_dice(self, i))
	panel.add_child(hold)
	panel.move_child(hold, 0)
	return panel


## Faces of one of a character's dice, resolved so forge marks and Growth
## stacks show on the strip exactly as they do in battle.
func _hero_faces(i: int, die: int) -> Array:
	var hero: Dictionary = Game.run.team[i]
	var out := []
	for k in GameData.FACES_PER_DIE:
		var slot: int = die * GameData.FACES_PER_DIE + k
		var fd: Dictionary = GameData.faces[String(hero.faces[slot])].duplicate(true)
		fd["id"] = String(hero.faces[slot])
		fd["plus"] = int(hero.face_plus[slot])
		var mod := int(hero.face_mods[slot])
		fd["mod"] = mod
		if mod != 0:
			for key in ["atk", "block", "heal", "mana"]:
				if fd.has(key):
					fd[key] = int(fd[key]) + mod
					break
		out.append(fd)
	return out


func _flip_token(i: int) -> void:
	Sfx.play("button")
	_strip_die[i] = 1 - int(_strip_die.get(i, 0))
	var dv = _strip_dice.get(i, null)
	if is_instance_valid(dv):
		dv.die = _strip_die[i]
		dv.set_die(_hero_faces(i, _strip_die[i]), 0)
		dv.throw(0, 0.0, 0.4)
	var label = _strip_labels.get(i, null)
	if is_instance_valid(label):
		label.text = Data.t("ui_die_a" if _strip_die[i] == 0 else "ui_die_b")
