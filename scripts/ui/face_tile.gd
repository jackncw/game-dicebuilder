class_name FaceTile
extends Control
## One die face, drawn as a tile: category-coloured card, the main effect's
## glyph, the value in the middle, up to three secondary keywords as corner
## badges, and the face's name underneath.
##
## This is the atom of the whole face-reading system. The battle dice, the
## face-swap screen, the codex grids and the shop all show the same object, so
## a face the player learns in one place is recognisable in the others. What
## counts as "main" versus "secondary", and what number to print, is `Glossary`'s
## call — this file only lays it out.

signal pressed()
signal long_pressed()

## Room for two stacked lines at F_MICRO — bilingual mode prints the Chinese
## name over the English one, and clipping the second was worse than nothing.
const NAME_H := 42.0
const LONG_PRESS := 0.45

var fd := {}                 # a resolved face dict (see BattleCore.hero_face)
var tile := 92.0             # side of the square part
var show_name := true
var selected := false
var dimmed := false
var interactive := true

var _num: Label
var _name: Label
var _pressing := false
var _lp_token: SceneTreeTimer = null


func _init(p_fd := {}, p_tile := 92.0, p_show_name := true) -> void:
	fd = p_fd
	tile = p_tile
	show_name = p_show_name
	_resize()
	mouse_filter = Control.MOUSE_FILTER_STOP


func _resize() -> void:
	var h := tile + (NAME_H if show_name else 0.0)
	custom_minimum_size = Vector2(tile, h)
	size = Vector2(tile, h)
	pivot_offset = Vector2(tile, h) * 0.5


func _ready() -> void:
	_num = UIKit.label("", int(tile * 0.42), UITheme.CREAM)
	_num.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	_num.add_theme_constant_override("outline_size", maxi(3, int(tile * 0.07)))
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_num.position = Vector2.ZERO
	_num.size = Vector2(tile, tile)
	add_child(_num)

	if show_name:
		_name = UIKit.label("", UITheme.F_MICRO, UITheme.CREAM)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name.clip_text = true
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name.position = Vector2(-2, tile + 2)
		_name.size = Vector2(tile + 4, NAME_H)
		_name.custom_minimum_size = Vector2(tile + 4, NAME_H)
		add_child(_name)
	_apply()


func set_face(p_fd: Dictionary) -> void:
	fd = p_fd
	_apply()


func set_flags(p_selected: bool, p_dimmed: bool) -> void:
	selected = p_selected
	dimmed = p_dimmed
	_apply()


func _apply() -> void:
	if _num == null:
		return
	_num.text = Glossary.main_number(fd)
	if _name != null:
		var mode := Data.lang_mode() if Engine.get_main_loop() != null else "both"
		if mode == "both":
			_name.text = "%s\n%s" % [Data.face_name_zh(fd), Data.face_name_en(fd)]
			_name.add_theme_font_size_override("font_size", UITheme.F_MICRO)
		else:
			_name.text = Data.face_name(fd)
			_name.add_theme_font_size_override("font_size", UITheme.F_CAPTION)
		_name.add_theme_color_override("font_color",
				UITheme.CREAM if not dimmed else UITheme.CREAM.darkened(0.4))
	queue_redraw()


func hue() -> Color:
	if fd.get("blank", false):
		return Color("8a8a8a")
	return UITheme.cat_color(String(fd.get("cat", "special")))


# ============================================================ drawing

func _draw() -> void:
	var h := hue()
	var fill := UITheme.deepen(h)
	var rim := h.lightened(0.25)
	if dimmed:
		fill = fill.lerp(Color("5c5c5c"), 0.45)
		rim = rim.lerp(Color("8a8a8a"), 0.5)
	var r := Rect2(Vector2.ZERO, Vector2(tile, tile))

	var box := UIKit.flat_box(fill, UITheme.R_MD, UITheme.B_BASE, UITheme.OUTLINE, 0)
	box.set_content_margin_all(0)
	draw_style_box(box, r)
	# a band of the true category hue across the top: the fill has to be deep
	# enough to carry cream type, which costs it most of its colour identity
	var band := UIKit.flat_box(rim, UITheme.R_MD, 0, UITheme.OUTLINE, 0)
	band.set_content_margin_all(0)
	band.corner_radius_bottom_left = 0
	band.corner_radius_bottom_right = 0
	draw_style_box(band, Rect2(Vector2(2, 2), Vector2(tile - 4, tile * 0.12)))

	# main glyph, centred; larger when there is no number competing with it
	var has_num: bool = _num != null and _num.text != ""
	var g := tile * (0.60 if has_num else 0.80)
	var gr := Rect2(Vector2((tile - g) * 0.5, (tile - g) * 0.5 + tile * 0.04), Vector2(g, g))
	var tint := UITheme.CREAM if not dimmed else UITheme.CREAM.darkened(0.35)
	Glyphs.draw_glyph(self, Glossary.glyph_key(String(Glossary.main_effect(fd).key)),
			gr, tint.lerp(h.lightened(0.5), 0.35 if has_num else 0.0), UITheme.OUTLINE)

	# secondary keywords, bottom-right, newest to the left — capped at three so
	# a busy face never turns into a wall of little symbols
	var subs := Glossary.sub_terms(fd)
	var n := mini(subs.size(), 3)
	var bs := tile * 0.28
	for i in n:
		var key := String(subs[n - 1 - i])
		var cx := tile - 3.0 - bs * 0.5 - i * (bs + 2.0)
		var cy := tile - 3.0 - bs * 0.5
		var bh := Glossary.hue(key)
		draw_circle(Vector2(cx, cy), bs * 0.5, UITheme.deepen(bh))
		draw_arc(Vector2(cx, cy), bs * 0.5, 0.0, TAU, 20, UITheme.OUTLINE, 2.0, true)
		Glyphs.draw_glyph(self, Glossary.glyph_key(key),
				Rect2(Vector2(cx, cy) - Vector2(bs, bs) * 0.34, Vector2(bs, bs) * 0.68),
				bh.lightened(0.45), Color(0, 0, 0, 0))

	# a "+" per forge mark, top-left, so an upgraded face is obvious in a grid
	var plus := int(fd.get("plus", 0))
	if plus > 0:
		var pw := 7.0 + 5.0 * plus
		var pb := UIKit.flat_box(UITheme.YELLOW.darkened(0.25), UITheme.R_CHIP, 2,
				UITheme.OUTLINE, 0)
		pb.set_content_margin_all(0)
		draw_style_box(pb, Rect2(Vector2(3, 3), Vector2(pw, 14)))
		for p in plus:
			var px := 6.0 + p * 5.0
			draw_line(Vector2(px, 10), Vector2(px + 4, 10), UITheme.CREAM, 2.0)
			draw_line(Vector2(px + 2, 8), Vector2(px + 2, 12), UITheme.CREAM, 2.0)

	if selected:
		var ring := UIKit.flat_box(Color(0, 0, 0, 0), UITheme.R_MD + 3,
				UITheme.B_FOCUS, UITheme.YELLOW)
		ring.set_content_margin_all(0)
		draw_style_box(ring, Rect2(Vector2(-3, -3), Vector2(tile + 6, tile + 6)))
	if dimmed:
		var veil := UIKit.flat_box(Color(0.22, 0.22, 0.26, 0.28), UITheme.R_MD, 0)
		veil.set_content_margin_all(0)
		draw_style_box(veil, r)


# ============================================================ input

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	if event.pressed:
		_pressing = true
		var t := get_tree().create_timer(LONG_PRESS)
		_lp_token = t
		t.timeout.connect(func() -> void:
			if _lp_token == t and _pressing:
				_pressing = false
				long_pressed.emit())
	else:
		_lp_token = null
		if _pressing:
			_pressing = false
			pressed.emit()


func cancel_press() -> void:
	_pressing = false
	_lp_token = null
