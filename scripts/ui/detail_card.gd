class_name DetailCard
extends RefCounted
## The long-press popup. One card shape used by every surface in the game:
## battle dice, status badges, enemy intent chips, the face-swap screen, the
## codex and the shop all raise this, so "hold to find out what that means"
## is a single habit rather than six different behaviours.
##
## Structure, in order:
##   ① face name (per language mode) + rarity + forge "+" marks
##   ② the full effect sentence, built from the resolved face
##   ③ where it can be dropped
##   ④ every term the face uses, spelled out — all sourced from `Glossary`
##
## The caller passes a parent Control; the card adds itself as a child and
## removes itself when the scrim is tapped.

const PANEL_W := 618.0
## Side of the close button hung on the card's top-right corner.
const CLOSE_D := 58.0


## Long-press detail for a die face. `viewer` (optional) is a node shown at the
## top of the card — the 3D die parade uses it to let the player spin the die.
static func show_face(parent: Control, fd: Dictionary, viewer: Control = null) -> Control:
	var rows: Array = []

	# ① heading: the tile itself, then name / rarity / marks
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.S4)
	var tile := FaceTile.new(fd, 84.0, false)
	tile.interactive = false
	head.add_child(tile)
	var head_v := VBoxContainer.new()
	head_v.add_theme_constant_override("separation", UITheme.S1)
	head_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hue := UITheme.cat_color(String(fd.get("cat", "special")))
	head_v.add_child(UIKit.text_block(Data.face_name(fd), UITheme.F_H2,
			UITheme.deepen(hue), PANEL_W - 130.0, HORIZONTAL_ALIGNMENT_LEFT))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", UITheme.S2)
	tags.add_child(UIKit.chip(Glossary.rarity_name(String(fd.get("rarity", "C"))),
			_rarity_hue(String(fd.get("rarity", "C"))), UITheme.F_CAPTION, UITheme.S2))
	if int(fd.get("plus", 0)) > 0:
		tags.add_child(UIKit.chip(Data.bi("強化 %s" % "+".repeat(int(fd.plus)),
				"Forged %s" % "+".repeat(int(fd.plus))), UITheme.YELLOW,
				UITheme.F_CAPTION, UITheme.S2))
	if int(fd.get("mod", 0)) != 0:
		tags.add_child(UIKit.chip(Data.bi("數值 %+d" % int(fd.mod), "value %+d" % int(fd.mod)),
				UITheme.GREEN, UITheme.F_CAPTION, UITheme.S2))
	head_v.add_child(tags)
	head.add_child(head_v)
	rows.append(head)

	# ② + ③ what it does and where it goes
	rows.append(UIKit.text_block(Glossary.effect_sentence(fd), UITheme.F_BODY_SM,
			UITheme.INK, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	rows.append(UIKit.text_block(Glossary.target_line(fd), UITheme.F_BODY_SM,
			UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))

	# ④ the glossary — every noun in the sentence above, explained
	var terms := Glossary.face_terms(fd)
	if not terms.is_empty():
		rows.append(_rule())
		rows.append(UIKit.text_block(Data.bi("名詞解釋", "Glossary"), UITheme.F_BODY_SM,
				UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
		for key in terms:
			rows.append(term_row(String(key)))
	return _present(parent, rows, viewer)


## Long-press detail for a whole die: a copy you can turn over with a finger,
## the face that is currently up explained in full, and all six faces listed so
## the player can see what else this die can come up with.
static func show_die(parent: Control, faces: Array, shown: int) -> Control:
	var viewer := Die3D.new(Vector2(188, 188))
	viewer.set_die(faces, shown)
	viewer.show_shadow = true
	viewer.enable_free_spin()

	var rows: Array = [UIKit.text_block(
			Data.bi("拖動骰子可以轉動它,檢視六個面", "Drag the die to turn it over"),
			UITheme.F_CAPTION, UITheme.INK_SOFT, PANEL_W - 8.0)]
	var fd: Dictionary = faces[shown] if shown < faces.size() else {}
	rows.append(_rule())
	# "擲出:X" used to be a line of type on its own, which made the one face
	# that actually matters the only thing on the card with no picture. It gets
	# the same tile as everywhere else, small.
	#
	# The label is bilingual, the NAME is printed once. Feeding a already-
	# bilingual `Data.face_name()` into both halves of `Data.bi()` is what
	# produced "擲出:側身 Sidestep Rolled: 側身 Sidestep".
	var rolled := HBoxContainer.new()
	rolled.add_theme_constant_override("separation", UITheme.S3)
	var rolled_tile := FaceTile.new(fd, 64.0, false)
	rolled_tile.interactive = false
	rolled.add_child(rolled_tile)
	var rolled_label := UIKit.text_block("%s:%s" % [Data.t("ui_rolled"),
			Data.face_name(fd)], UITheme.F_BODY,
			UITheme.deepen(UITheme.cat_color(String(fd.get("cat", "special")))),
			PANEL_W - 88.0, HORIZONTAL_ALIGNMENT_LEFT)
	rolled_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rolled.add_child(rolled_label)
	rows.append(rolled)
	rows.append(UIKit.text_block(Glossary.effect_sentence(fd), UITheme.F_BODY_SM,
			UITheme.INK, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	rows.append(UIKit.text_block(Glossary.target_line(fd), UITheme.F_BODY_SM,
			UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))

	rows.append(_rule())
	rows.append(UIKit.text_block(Data.bi("這顆骰子的六個面", "The six faces of this die"),
			UITheme.F_BODY_SM, UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UITheme.S3)
	grid.add_theme_constant_override("v_separation", UITheme.S2)
	for i in faces.size():
		var t := FaceTile.new(faces[i], 90.0, true)
		t.selected = i == shown
		t.interactive = false
		grid.add_child(t)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	rows.append(gc)

	# every term across all six faces, each explained once
	var seen := {}
	var terms := []
	for f in faces:
		for k in Glossary.face_terms(f):
			if not seen.has(k):
				seen[k] = true
				terms.append(k)
	if not terms.is_empty():
		rows.append(_rule())
		rows.append(UIKit.text_block(Data.bi("名詞解釋", "Glossary"), UITheme.F_BODY_SM,
				UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
		for key in terms:
			rows.append(term_row(String(key)))
	return _present(parent, rows, viewer)


## Long-press detail for a single term — status badges and enemy intent chips
## come in through here.
static func show_term(parent: Control, key: String, extra_terms := []) -> Control:
	var rows: Array = [term_row(key, UITheme.F_BODY_SM)]
	for k in extra_terms:
		if String(k) != key:
			rows.append(term_row(String(k)))
	return _present(parent, rows, null)


## Free-form card: a title plus arbitrary term keys. Heroes and enemies use it.
static func show_info(parent: Control, title: String, body: String,
		terms := []) -> Control:
	var rows: Array = [UIKit.text_block(title, UITheme.F_H2, UITheme.INK,
			PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT)]
	if body != "":
		rows.append(UIKit.text_block(body, UITheme.F_BODY_SM, UITheme.INK,
				PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	if not terms.is_empty():
		rows.append(_rule())
		for k in terms:
			rows.append(term_row(String(k)))
	return _present(parent, rows, null)


## Free-form card built from ready-made rows (the enemy forecast uses this).
static func show_rows(parent: Control, rows: Array) -> Control:
	return _present(parent, rows, null)


# ============================================================ relics

static func relic_hue(rid: String) -> Color:
	return UITheme.YELLOW if GameData.relic_rarity(rid) == "advanced" else UITheme.ORANGE


## The heading block of a relic card: big glyph on a disc, bilingual name,
## rarity chip. Reused by the acquisition card and the relic list.
static func relic_head(rid: String, disc := 92.0) -> Control:
	var rd: Dictionary = GameData.relics[rid]
	var advanced: bool = GameData.relic_rarity(rid) == "advanced"
	var hue := relic_hue(rid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.S4)
	var badge := _IconBadge.new()
	badge.key = String(rd.get("glyph", "relic"))
	badge.hue = hue
	badge.custom_minimum_size = Vector2(disc, disc)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.S1)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(UIKit.text_block(Data.bi(String(rd.zh), String(rd.en)), UITheme.F_H2,
			UITheme.deepen(hue), PANEL_W - disc - 40.0, HORIZONTAL_ALIGNMENT_LEFT))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", UITheme.S2)
	tags.add_child(UIKit.chip(Data.t("ui_relic_advanced" if advanced else "ui_relic_common"),
			hue, UITheme.F_CAPTION, UITheme.S2))
	col.add_child(tags)
	head.add_child(col)
	return head


## The moment a relic is picked up: what it is, what it does, and an explicit
## confirm — a relic changes how the whole run plays, so it never slides past
## behind a screen transition.
##
## The scrim is deliberately inert here. Every other card in the game closes by
## tapping outside it; this one wants the player to have actually looked.
static func show_relic(parent: Control, rid: String, on_confirm := Callable()) -> Control:
	var rd: Dictionary = GameData.relics[rid]
	var advanced: bool = GameData.relic_rarity(rid) == "advanced"
	var rows: Array = [
		UIKit.text_block(Data.t("ui_relic_gained"), UITheme.F_BODY_SM, UITheme.INK_SOFT,
				PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT),
		relic_head(rid),
		_rule(),
		UIKit.text_block(Data.bi2(String(rd.desc_zh), String(rd.desc_en)), UITheme.F_BODY,
				UITheme.INK, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT),
	]
	if advanced:
		rows.append(UIKit.text_block(Data.t("ui_relic_pick_note"), UITheme.F_CAPTION,
				UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	rows.append(term_row("relic"))
	return _present(parent, rows, null, {
		"accent": relic_hue(rid), "glow": advanced,
		"confirm": Data.t("ui_confirm"), "on_confirm": on_confirm,
		"dismissible": false, "close_button": false,
	})


## Everything the party is carrying, as a scrolling list. Raised from the
## battle screen's relic row and from the run top bar.
static func show_relic_list(parent: Control, ids: Array) -> Control:
	var rows: Array = [UIKit.text_block(Data.t("ui_relics_mine"), UITheme.F_H2,
			UITheme.INK, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT)]
	if ids.is_empty():
		rows.append(UIKit.text_block(Data.t("ui_no_relics"), UITheme.F_BODY_SM,
				UITheme.INK_SOFT, PANEL_W - 8.0, HORIZONTAL_ALIGNMENT_LEFT))
	# advanced first: they are the ones that change how a turn is played
	var ordered := []
	for tier in ["advanced", "common"]:
		for rid in ids:
			if GameData.relics.has(rid) and GameData.relic_rarity(String(rid)) == tier:
				ordered.append(String(rid))
	for rid in ordered:
		rows.append(_rule())
		rows.append(relic_row(rid))
	return _present(parent, rows, null)


## One relic as a list row: icon, name, what it does.
static func relic_row(rid: String) -> Control:
	var rd: Dictionary = GameData.relics[rid]
	var hue := relic_hue(rid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.S3)
	var badge := _IconBadge.new()
	badge.key = String(rd.get("glyph", "relic"))
	badge.hue = hue
	badge.custom_minimum_size = Vector2(44, 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", UITheme.S2)
	title.add_child(UIKit.text_block(Data.bi(String(rd.zh), String(rd.en)),
			UITheme.F_BODY_SM, UITheme.deepen(hue), 0.0, HORIZONTAL_ALIGNMENT_LEFT))
	if GameData.relic_rarity(rid) == "advanced":
		title.add_child(UIKit.chip(Data.t("ui_relic_advanced"), UITheme.YELLOW,
				UITheme.F_MICRO, UITheme.S1))
	col.add_child(title)
	col.add_child(UIKit.text_block(Data.bi2(String(rd.desc_zh), String(rd.desc_en)),
			UITheme.F_CAPTION, UITheme.INK, PANEL_W - 64.0, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(col)
	return row


## One glossary entry as a row: its icon in a category-coloured disc, then the
## name and the rule. Reused by the tutorial and the codex.
static func term_row(key: String, font := UITheme.F_CAPTION) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.S3)
	var hue := Glossary.hue(key)
	var badge := _IconBadge.new()
	badge.key = Glossary.glyph_key(key)
	badge.hue = hue
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(UIKit.text_block(Glossary.term_name(key), UITheme.F_BODY_SM,
			UITheme.deepen(hue), PANEL_W - 58.0, HORIZONTAL_ALIGNMENT_LEFT))
	col.add_child(UIKit.text_block(Glossary.desc(key), font, UITheme.INK,
			PANEL_W - 58.0, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(col)
	return row


static func _rarity_hue(letter: String) -> Color:
	match letter:
		"E": return UITheme.ORANGE
		"R": return UITheme.PURPLE
		"U": return UITheme.GREEN
		_: return UITheme.BLUE


static func _rule() -> Control:
	var c := ColorRect.new()
	c.color = UITheme.INK_SOFT
	c.color.a = 0.35
	c.custom_minimum_size = Vector2(0, 2)
	return c


## The scrim + scrolling paper panel every variant lands in.
##
## `opts` (all optional):
##   accent        Color  — panel border colour instead of the house ink
##   glow          bool   — a wide warm shadow; the Advanced relic treatment
##   confirm       String — adds a confirm button at the foot of the card
##   on_confirm    Callable — fired after the card closes itself
##   dismissible   bool   — false makes the scrim inert (confirm is the only exit)
##   close_button  bool   — the corner ✕ (default true)
static func _present(parent: Control, rows: Array, viewer: Control, opts := {}) -> Control:
	var dismissible: bool = bool(opts.get("dismissible", true))
	var accent: Color = opts.get("accent", UITheme.OUTLINE)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var scrim := Button.new()
	scrim.flat = true
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim_a := 0.55 if dismissible else 0.68
	scrim.add_theme_stylebox_override("normal", UIKit.flat_box(Color(0, 0, 0, scrim_a), 0, 0))
	scrim.add_theme_stylebox_override("hover", UIKit.flat_box(Color(0, 0, 0, scrim_a), 0, 0))
	scrim.add_theme_stylebox_override("pressed", UIKit.flat_box(Color(0, 0, 0, scrim_a + 0.05), 0, 0))
	if dismissible:
		scrim.pressed.connect(func() -> void: root.queue_free())
	root.add_child(scrim)

	var panel := UIKit.panel(UITheme.CREAM, UITheme.R_LG, UITheme.B_STRONG)
	var pbox: StyleBoxFlat = panel.get_theme_stylebox("panel")
	pbox.set_content_margin_all(UITheme.S4)
	pbox.border_color = accent
	pbox.shadow_color = UITheme.SHADOW
	pbox.shadow_size = 10
	if bool(opts.get("glow", false)):
		# an Advanced relic has to look like a different class of object the
		# instant it lands: gold rim, no offset, and a halo instead of a shadow
		pbox.set_border_width_all(UITheme.B_FOCUS + 2)
		pbox.shadow_color = Color(accent.r, accent.g, accent.b, 0.55)
		pbox.shadow_size = 22
		pbox.shadow_offset = Vector2.ZERO
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(PANEL_W + 2 * UITheme.S4, 0)

	# the card can outgrow the screen once a face carries four keywords, so the
	# body scrolls rather than spilling off the bottom
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UITheme.S3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if viewer != null:
		var vc := CenterContainer.new()
		vc.add_child(viewer)
		vb.add_child(vc)
	for r in rows:
		vb.add_child(r)
	var confirm_text := String(opts.get("confirm", ""))
	if confirm_text != "":
		var bar := CenterContainer.new()
		var ok := UIKit.button(confirm_text, accent.lightened(0.3), UITheme.F_BODY,
				Vector2(260, 66))
		ok.pressed.connect(func() -> void:
			Sfx.play("button")
			root.queue_free()
			var cb: Callable = opts.get("on_confirm", Callable())
			if cb.is_valid():
				cb.call())
		bar.add_child(ok)
		vb.add_child(UIKit.spacer(UITheme.S2))
		vb.add_child(bar)
	elif dismissible:
		vb.add_child(UIKit.text_block(Data.bi("(按右上角的關閉鍵,或點卡片以外任何位置)",
				"(use the close button, or tap outside the card)"),
				UITheme.F_MICRO, UITheme.INK_SOFT, PANEL_W - 8.0))
	scroll.add_child(vb)
	panel.add_child(scroll)

	# An explicit way out. Tapping the scrim always worked, but the card fills
	# most of a phone screen and the one thing a player reaches for on a full
	# screen overlay is the close button — not finding one reads as being stuck.
	# A Control with no minimum size is free inside a PanelContainer: it fills
	# the content rect without changing what the panel measures.
	var corner := Control.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bool(opts.get("close_button", true)):
		root.add_child(panel)
		parent.add_child(root)
		_clamp_height.call_deferred(scroll, vb)
		return root
	var close := UIKit.button("", UITheme.WOOD, UITheme.F_H2, Vector2(CLOSE_D, CLOSE_D))
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -CLOSE_D + UITheme.S2
	close.offset_right = UITheme.S2
	close.offset_top = -UITheme.S2
	close.offset_bottom = CLOSE_D - UITheme.S2
	# drawn rather than typed: "✕" is a glyph the bundled font may not carry,
	# and a missing box in the corner of every card is not worth the risk
	var cross := _Cross.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	close.add_child(cross)
	close.pressed.connect(func() -> void:
		Sfx.play("button")
		root.queue_free())
	corner.add_child(close)
	panel.add_child(corner)

	root.add_child(panel)
	parent.add_child(root)
	# clamp after layout: 1280px tall screen, leave a margin top and bottom
	_clamp_height.call_deferred(scroll, vb)
	return root


static func _clamp_height(scroll: ScrollContainer, vb: VBoxContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(vb):
		return
	scroll.custom_minimum_size = Vector2(PANEL_W, minf(vb.size.y, 1000.0))


## The X on the close button: two strokes in the same cream-on-ink the rest of
## the game's small marks use.
class _Cross:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(c - d * r, c + d * r, UITheme.CREAM, 6.0, true)


## A glyph on a category-coloured disc — the icon side of a glossary row.
class _IconBadge:
	extends Control
	var key := "atk"
	var hue := UITheme.ORANGE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, UITheme.deepen(hue))
		draw_arc(c, r, 0.0, TAU, 26, UITheme.OUTLINE, 2.5, true)
		Glyphs.draw_glyph(self, key, Rect2(c - Vector2(r, r) * 0.66, Vector2(r, r) * 1.32),
				hue.lightened(0.45), Color(0, 0, 0, 0))
