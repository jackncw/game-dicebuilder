class_name UIKit
extends RefCounted
## Shared UI construction helpers — flat colour blocks, one thick dark outline,
## rounded corners, cream paper. Every screen builds its tree through this so
## the whole game inherits one spacing/type/colour system.
##
## All raw values live in `UITheme`; this file only assembles widgets. When you
## need a number, take it from `UITheme` (S1–S6, R_*, B_*, F_*) rather than
## typing a literal.

# ── token re-exports (kept so existing call sites read naturally) ──
const OUTLINE := UITheme.OUTLINE
const CREAM := UITheme.CREAM
const CREAM_DARK := UITheme.CREAM_DARK
const INK := UITheme.INK
const INK_SOFT := UITheme.INK_SOFT
const RED := UITheme.RED
const BLUE := UITheme.BLUE
const GREEN := UITheme.GREEN
const PURPLE := UITheme.PURPLE
const YELLOW := UITheme.YELLOW
const ORANGE := UITheme.ORANGE

const CAT_COLORS := UITheme.CAT_COLORS
const CHAPTER_BG := UITheme.CHAPTER_BG

# spacing / type aliases so screens can say UIKit.S4 without a second import
const S1 := UITheme.S1
const S2 := UITheme.S2
const S3 := UITheme.S3
const S4 := UITheme.S4
const S5 := UITheme.S5
const S6 := UITheme.S6
const F_DISPLAY := UITheme.F_DISPLAY
const F_H1 := UITheme.F_H1
const F_H2 := UITheme.F_H2
const F_BODY := UITheme.F_BODY
const F_BODY_SM := UITheme.F_BODY_SM
const F_CAPTION := UITheme.F_CAPTION
const F_MICRO := UITheme.F_MICRO
const R_CHIP := UITheme.R_CHIP
const R_SM := UITheme.R_SM
const R_MD := UITheme.R_MD
const R_LG := UITheme.R_LG
const B_HAIR := UITheme.B_HAIR
const B_BASE := UITheme.B_BASE
const B_STRONG := UITheme.B_STRONG
const B_FOCUS := UITheme.B_FOCUS


static func cat_color(cat: String) -> Color:
	return UITheme.cat_color(cat)


static func cat_text(cat: String) -> Color:
	return UITheme.cat_text(cat)


static func surface(chapter: int) -> Color:
	return UITheme.surface(chapter)


static func surface_deep(chapter: int) -> Color:
	return UITheme.surface_deep(chapter)


static func accent(chapter: int) -> Color:
	return UITheme.accent(chapter)


# ============================================================ boxes

static func flat_box(bg: Color, corner := UITheme.R_MD, border := UITheme.B_STRONG,
		border_color := UITheme.OUTLINE, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(corner)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.set_content_margin_all(pad)
	return sb


## Same block, plus the house drop shadow. Used by anything that should read as
## a physical card sitting on the background.
static func card_box(bg: Color, corner := UITheme.R_LG, border := UITheme.B_STRONG,
		border_color := UITheme.OUTLINE, pad := UITheme.S3) -> StyleBoxFlat:
	var sb := flat_box(bg, corner, border, border_color, pad)
	sb.shadow_color = UITheme.SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = UITheme.SHADOW_OFFSET
	return sb


static func panel(bg := UITheme.CREAM, corner := UITheme.R_MD, border := UITheme.B_STRONG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_box(bg, corner, border))
	return p


## A card panel on a dark background: solid surface fill + shadow, so light
## text on it always clears 4.5:1 regardless of the chapter behind.
static func card(chapter: int, corner := UITheme.R_LG, border := UITheme.B_STRONG,
		border_color := UITheme.OUTLINE, pad := UITheme.S3) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
			card_box(UITheme.surface(chapter), corner, border, border_color, pad))
	# vine curls in the four corners only. The panel's content margin keeps
	# text clear of them, so nothing readable is ever underneath one.
	var vines := Forest.VineCorners.new()
	vines.hue = UITheme.accent(chapter)
	p.add_child(vines)
	p.move_child(vines, 0)
	return p


# ============================================================ text

static func label(text: String, size := UITheme.F_BODY, color := UITheme.OUTLINE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Centred, wrapping label constrained to `width` — the shape almost every
## screen title and blurb wants.
## `width` of 0 means "as wide as the text needs" — wrapping at a zero minimum
## width collapses the label to one character per line inside any shrinking
## container (CenterContainer, HBox), so wrapping is off in that case.
static func text_block(text: String, size := UITheme.F_BODY, color := UITheme.CREAM,
		width := 620.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, size, color)
	l.horizontal_alignment = align
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	return l


## Screen title: big cream type with a dark rim so it survives on any chapter
## sky without needing a panel behind it.
static func title(text: String, size := UITheme.F_H1, color := UITheme.CREAM) -> Label:
	var l := text_block(text, size, color, 0.0)
	l.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	l.add_theme_constant_override("outline_size", 6)
	return l


## Light text that must sit directly on a chapter background gets the same rim.
static func outlined(l: Label, thickness := 4) -> Label:
	l.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	l.add_theme_constant_override("outline_size", thickness)
	return l


# ============================================================ controls

## Every button in the game is a piece of the forest: a plank with a couple of
## strokes of grain and two pegs. The pressed state loses its shadow and darkens,
## which reads as the plank sinking into the board.
static func button(text: String, bg := UITheme.CREAM, font_size := UITheme.F_H2,
		min_size := Vector2(160, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	var sb := card_box(bg, UITheme.R_MD, UITheme.B_STRONG, UITheme.OUTLINE, UITheme.S2)
	var sb_hover := card_box(bg.lightened(0.08), UITheme.R_MD, UITheme.B_STRONG, UITheme.OUTLINE, UITheme.S2)
	# no shadow while held, and a step down: the plank presses into the board
	var sb_pressed := flat_box(bg.darkened(0.15), UITheme.R_MD, UITheme.B_STRONG, UITheme.OUTLINE, UITheme.S2)
	sb_pressed.content_margin_top = UITheme.S2 + 3
	sb_pressed.content_margin_bottom = maxi(UITheme.S2 - 3, 0)
	# One neutral for every disabled button, whatever its live colour: the point
	# is "this is off", and a tinted grey per button both muddles that read and
	# lands the label under 4.5:1 on the darker hues.
	var sb_disabled := flat_box(Color("b0aba0"), UITheme.R_MD,
			UITheme.B_BASE, UITheme.OUTLINE.lightened(0.15), UITheme.S2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("disabled", sb_disabled)
	b.add_theme_color_override("font_color", UITheme.INK)
	b.add_theme_color_override("font_pressed_color", UITheme.INK)
	b.add_theme_color_override("font_hover_color", UITheme.INK)
	# a disabled button must still be legible — it is information, not noise
	b.add_theme_color_override("font_disabled_color", Color("3a372f"))
	b.add_theme_font_size_override("font_size", font_size)
	# grain goes UNDER the label (added first, and ignoring input), so the wood
	# can never cost the text any contrast
	var grain := Forest.WoodGrain.new()
	grain.tint = UITheme.SHADE_SOFT
	b.add_child(grain)
	b.move_child(grain, 0)
	return b


## Fixed-height meter: dark rim, sunken track, flat fill. Every rect is sized
## explicitly and the root shrinks to fit — an anchored child would stretch to
## whatever height the surrounding container hands out, which is how the bars
## used to grow a black gutter under the fill inside an HBoxContainer.
static func hp_bar(value: int, max_value: int, size := Vector2(120, 16), fill := UITheme.GREEN) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true
	var bg := ColorRect.new()
	bg.color = UITheme.OUTLINE
	bg.position = Vector2.ZERO
	bg.size = size
	root.add_child(bg)
	var track := ColorRect.new()
	track.color = Color(0.14, 0.14, 0.15)
	track.position = Vector2(2, 2)
	track.size = size - Vector2(4, 4)
	root.add_child(track)
	var inner := ColorRect.new()
	inner.color = fill
	var pct := clampf(float(value) / maxf(float(max_value), 1.0), 0.0, 1.0)
	inner.position = Vector2(2, 2)
	inner.size = Vector2((size.x - 4) * pct, size.y - 4)
	root.add_child(inner)
	# a highlight along the top of the fill keeps it from reading as flat tape
	var gloss := ColorRect.new()
	gloss.color = Color(1, 1, 1, 0.22)
	gloss.position = Vector2(2, 2)
	gloss.size = Vector2(inner.size.x, maxf(2.0, size.y * 0.28))
	root.add_child(gloss)
	return root


## Small badge: deep fill + cream type + a bright rim of the true hue. Used for
## statuses, enemy intents and the category strip on a die, so those three
## always read as the same family of object.
static func chip(text: String, hue: Color, font_size := UITheme.F_CAPTION,
		pad_h := UITheme.S2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := flat_box(UITheme.deepen(hue), UITheme.R_CHIP, UITheme.B_HAIR,
			hue.lightened(0.25), 0)
	sb.set_content_margin_all(2)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(text, font_size, UITheme.CREAM)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## The same badge with a drawn glyph instead of a typed token. Statuses, enemy
## intents and die-face keywords all use this, so one picture means one thing
## everywhere. `text` is usually just the stack count; pass "" for a flag.
static func icon_chip(glyph_key: String, text: String, hue: Color,
		font_size := UITheme.F_CAPTION, pad_h := UITheme.S2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := flat_box(UITheme.deepen(hue), UITheme.R_CHIP, UITheme.B_HAIR,
			hue.lightened(0.25), 0)
	sb.set_content_margin_all(2)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the icon rides the type size so a chip stays one line tall at any scale
	row.add_child(Glyphs.icon(glyph_key, font_size * 1.15, hue.lightened(0.45)))
	if text != "":
		var l := label(text, font_size, UITheme.CREAM)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	p.add_child(row)
	return p


## Themed slider — the default Godot HSlider is the most obvious "unstyled"
## tell left in the game.
static func slider(value: float, max_value := 100.0, width := 420.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = max_value
	s.value = value
	s.custom_minimum_size = Vector2(width, 44)
	var track := flat_box(Color("1d1d20"), UITheme.R_CHIP, UITheme.B_BASE, UITheme.OUTLINE, 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	s.add_theme_stylebox_override("slider", track)
	var filled := flat_box(UITheme.GREEN, UITheme.R_CHIP, UITheme.B_BASE, UITheme.OUTLINE, 0)
	filled.content_margin_top = 8
	filled.content_margin_bottom = 8
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob := ImageTexture.create_from_image(_knob_image())
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)
	return s


static func _knob_image() -> Image:
	var d := 34
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(d * 0.5, d * 0.5)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dist <= d * 0.5 - 4.0:
				img.set_pixel(x, y, UITheme.CREAM)
			elif dist <= d * 0.5:
				img.set_pixel(x, y, UITheme.OUTLINE)
	return img


## Godot 4.4+ changed what MOUSE_FILTER_PASS does: an event now only travels up
## to the parent, and no longer falls through to a sibling underneath. Card
## contents (VBox, PanelContainer, Control — all PASS/STOP by default) swallow
## the click, so a full-card tap overlay Button laid underneath never sees one.
## This helper walks the content tree to IGNORE; real Buttons stay clickable.
static func mouse_passthrough(node: Control) -> void:
	if node is BaseButton:
		return
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		var ctrl := c as Control
		if ctrl:
			mouse_passthrough(ctrl)


static func spacer(h := float(UITheme.S3)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func hspacer(w := float(UITheme.S3)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## Full-screen chapter sky: flat base, a darker canopy band with a treeline
## hanging off it, a horizon and a lighter forest floor. Every screen in the
## game stands on this so none of them is one unbroken slab of colour.
##   `horizon` / `canopy` are canvas y positions; pass 0 to drop either band.
static func background(chapter: int, canopy := 118.0, horizon := 0.0,
		motes := true) -> Control:
	return Forest.scenery(chapter, canopy, horizon, motes)


## Bottom-pinned tray: the same slab the battle screen puts its controls on.
## Returns the tray; add rows to `tray.get_child(0)` (a VBoxContainer).
static func footer(chapter: int, height := 130.0) -> PanelContainer:
	var tray := PanelContainer.new()
	var box := flat_box(UITheme.surface_deep(chapter), 0, 0, UITheme.OUTLINE, UITheme.S3)
	box.set_border_width_all(0)
	box.border_width_top = UITheme.B_STRONG
	box.corner_radius_top_left = UITheme.R_LG
	box.corner_radius_top_right = UITheme.R_LG
	box.content_margin_top = UITheme.S4
	box.content_margin_bottom = UITheme.S4
	tray.add_theme_stylebox_override("panel", box)
	tray.anchor_left = 0.0
	tray.anchor_right = 1.0
	tray.anchor_top = 1.0
	tray.anchor_bottom = 1.0
	tray.offset_top = -height
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UITheme.S3)
	tray.add_child(v)
	return tray


## A centred row of buttons for a footer.
static func button_row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", UITheme.S4)
	for b in buttons:
		h.add_child(b)
	return h


## Small keyword badges. Single CJK chars: always renderable, language-neutral
## enough alongside the category colour (proper drawn icons land in polish).
const KW_GLYPH := {
	"pierce": "穿", "cleave": "掃", "aoe": "全", "poison": "毒", "burn": "燒",
	"stun": "暈", "weaken": "弱", "expose": "破", "regen": "生", "taunt": "嘲",
	"thorns": "棘", "lifesteal": "血", "combo": "連", "wild": "百", "spell": "文",
	"growth": "長", "pain": "損", "lucky": "運",
}

const ICON := {
	"atk": "攻", "block": "防", "heal": "療", "mana": "靈", "poison": "毒",
	"burn": "燒", "weaken": "弱", "expose": "破", "regen": "生", "taunt": "嘲",
	"thorns": "棘", "bind": "縛", "curse": "咒", "howl": "嚎", "charge": "蓄",
	"counter": "反", "summon": "召", "cancel": "消", "steal": "偷", "stun": "暈",
	"down": "倒", "aoe": "全", "wild": "百", "reroll": "擲",
}

## English-only mode gets Latin tokens for the same slots. A chip has room for
## one CJK character or three letters, never both, so the bilingual mode keeps
## the character (it is the denser of the two) and only pure-English swaps.
const ICON_EN := {
	"atk": "ATK", "block": "BLK", "heal": "HEA", "mana": "ESS", "poison": "PSN",
	"burn": "BRN", "weaken": "WKN", "expose": "EXP", "regen": "RGN", "taunt": "TNT",
	"thorns": "THN", "bind": "BND", "curse": "CRS", "howl": "HWL", "charge": "CHG",
	"counter": "CTR", "summon": "SUM", "cancel": "CNL", "steal": "STL", "stun": "STN",
	"down": "DWN", "aoe": "ALL", "wild": "WLD", "reroll": "RR",
}


## The short token for a status/intent/category slot, in the player's language.
static func glyph(key: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("/root/Data"):
		if String(tree.root.get_node("/root/Data").lang_mode()) == "en":
			return String(ICON_EN.get(key, key))
	return String(ICON.get(key, key))


## Same token with a number glued on, e.g. "攻5" / "ATK5".
static func glyph_n(key: String, value: int) -> String:
	return "%s%d" % [glyph(key), value]
