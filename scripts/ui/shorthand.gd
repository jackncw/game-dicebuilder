class_name Shorthand
extends RefCounted
## The one-glance language: an effect written as two or three glyph+number pips.
##
## Round 5 left the battle screen saying a face's NAME and nothing else. "翻湧"
## / "Surge" tells a first-time player exactly nothing, and the only way to find
## out was a half-second long press on every die, every turn. Names are good for
## remembering a face you already know and useless for reading a table of eight
## you don't.
##
## So: under the name, what the face DOES, in the same pictures the game already
## uses everywhere else. `Glyphs` draws them, `Glossary` decides which term is
## the headline and which are riders, and the long-press card is still the place
## the words live. This module is only the compression.
##
## The same pips are what an enemy intent wears, deliberately: "⚔ 6" on an enemy
## card and "⚔ 6" under your die are the same claim about the same number, and a
## player who learns one has learned both.
##
## ── budget ──────────────────────────────────────────────────────────
## A die is 76px wide on a 720px canvas and the phone build renders that at 540,
## so a pip has about 19 physical pixels of width to be recognisable in. That is
## the whole reason for the rules below: three pips maximum, flags carry no
## number, and the COST pips come before the decorative ones — running out of
## room must never hide what a face charges you.

## Keys that are a cost rather than an effect. These jump the queue: a player who
## cannot see that a face wants 3 Essence will try to use it and be told no.
const COST_KEYS := ["spell", "pain"]


## The pips for one face, in reading order: headline, costs, then modifiers.
## Each entry is {key, text, hue}; `text` is empty for a flag.
##
## `fd` should be a LIVE face (see `BattleCore.live_face`) if there is a battle
## to read it against — the number a player acts on is the one after Weaken,
## Charge, relics and passives, not the one printed in the data file.
static func pips(fd: Dictionary, limit := 3) -> Array:
	if fd.get("blank", false):
		return [{"key": "blank", "text": "", "hue": UITheme.cat_color("special")}]
	var out := []
	var main := String(Glossary.main_effect(fd).key)
	out.append({"key": main, "text": Glossary.main_number(fd), "hue": Glossary.hue(main)})
	var subs: Array = Glossary.sub_terms(fd)
	for k in COST_KEYS:
		if k != main and k in subs:
			out.append(_pip(fd, String(k)))
	for k in subs:
		if out.size() >= limit:
			break
		if k in COST_KEYS:
			continue
		out.append(_pip(fd, String(k)))
	# the costs are never dropped, so a face carrying both of them plus a
	# headline can legitimately come out one over the caller's limit
	return out.slice(0, maxi(limit, 1 + COST_KEYS.size()))


static func _pip(fd: Dictionary, key: String) -> Dictionary:
	return {"key": key, "text": _number(fd, key), "hue": Glossary.hue(key)}


## What a rider prints. Flags print nothing — the picture IS the whole statement,
## and a "1" after a Pierce icon reads as "pierce 1" rather than "yes".
static func _number(fd: Dictionary, key: String) -> String:
	if key in Glossary.FLAG_KEYS:
		return ""
	var v = fd.get(key, 0)
	if v is bool or v is String or v is Array:
		return ""
	var n := int(v)
	if n == 0:
		return ""
	if key in ["charge_up", "resonate", "buff_next_atk", "echo"]:
		return "+%d" % n
	return str(n)


# ============================================================ widgets

## One pip. Not `UIKit.icon_chip`: that carries a 2px border and 8px of side
## padding, which is 20 of the 76px a die has to spend before any ink lands. This
## is the same object with the frame taken off — deep fill, bright glyph, cream
## number — so it still reads as a member of the chip family.
static func pip(p: Dictionary, font_size := UITheme.F_BODY_SM) -> Control:
	var hue: Color = p.hue
	var box := PanelContainer.new()
	# A 1px rim of the true hue, where `UIKit.chip` uses 2. Without any rim the
	# deep fill sits at almost the same value as the hero card behind it and the
	# pips read as smudges at 540; with the full 2px they cost 4 of the 76px a
	# die has. One pixel is what separates them from the card and still leaves
	# room for three of them.
	var sb := UIKit.flat_box(UITheme.deepen(hue), UITheme.R_CHIP, 1,
			hue.lightened(0.3), 0)
	sb.set_content_margin_all(1)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Glyphs.icon(Glossary.glyph_key(String(p.key)), font_size * 1.1,
			hue.lightened(0.5)))
	if String(p.text) != "":
		var l := UIKit.label(String(p.text), font_size, UITheme.CREAM)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	box.add_child(row)
	return box


## A row of pips for one face, centred and sized to fit `width`.
##
## The fit is a real shrink, not a clip: three numeric riders on a 76px die do
## not fit at caption size, and a clipped pip is worse than a small one — it
## looks like a different, unknown symbol. `scale` is uniform so the glyphs keep
## their proportions.
## Sized at F_BODY_SM rather than F_CAPTION even though three pips at that size
## do not fit a 76px die. `_fit` scales the row down when it has to, and MOST
## faces carry one or two pips — sizing for the common case and shrinking the
## crowded one is the way round that leaves the majority legible at 540. Sizing
## for the worst case would have made every face as small as the worst one.
static func row(fd: Dictionary, width: float, font_size := UITheme.F_BODY_SM,
		limit := 3) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, font_size + 7.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in pips(fd, limit):
		h.add_child(pip(p, font_size))
	holder.add_child(h)
	_fit.call_deferred(h, holder, width)
	return holder


## Centre `h` in `holder`, scaling it down if it is wider than the budget.
## Deferred by the caller: an HBoxContainer has no width until it has sorted.
static func _fit(h: HBoxContainer, holder: Control, width: float) -> void:
	if not is_instance_valid(h) or not is_instance_valid(holder):
		return
	var want := h.get_combined_minimum_size()
	if want.x <= 0.0:
		return
	var k := minf(1.0, width / want.x)
	h.scale = Vector2(k, k)
	h.size = want
	h.position = Vector2((width - want.x * k) * 0.5,
			(holder.custom_minimum_size.y - want.y * k) * 0.5)
