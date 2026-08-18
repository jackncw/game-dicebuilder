class_name ItemIcon
extends Control
## One owned thing — a relic or a potion — drawn as a disc with its glyph on it,
## and holdable.
##
## Every place the player can see what they are carrying uses this: the strip
## under the battle top bar, the "carrying" row in the shop, the victory tally.
## Same picture, same size, same gesture, so "hold it to find out what it does"
## is learned once.
##
## The gesture is `PressGesture`, the die faces' one — travel deadzone and
## scroll-cancel included, because these icons live in scrolling rows.

signal pressed()
signal long_pressed()

const D := 46.0

var key := "relic"                  # glyph key
var hue := UITheme.ORANGE
var ring := false                   # a brighter rim: Advanced relics wear it
var selected := false
var dimmed := false
var interactive := true

var _press: PressGesture = null


func _init(p_key := "relic", p_hue := UITheme.ORANGE, p_d := D) -> void:
	key = p_key
	hue = p_hue
	custom_minimum_size = Vector2(p_d, p_d)
	size = Vector2(p_d, p_d)
	# PASS, not STOP: these sit inside ScrollContainers, and a STOP child eats
	# the ScreenDrag the container needs for finger scrolling (round 13).
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_flags(p_selected: bool, p_dimmed := false) -> void:
	selected = p_selected
	dimmed = p_dimmed
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0
	var fill := UITheme.deepen(hue)
	var tint := hue.lightened(0.45)
	if dimmed:
		fill = fill.lerp(Color("5c5c5c"), 0.45)
		tint = tint.lerp(Color("9a9a9a"), 0.5)
	draw_circle(c, r, fill)
	draw_arc(c, r, 0.0, TAU, 26, UITheme.OUTLINE, 2.5, true)
	if ring:
		draw_arc(c, r - 2.0, 0.0, TAU, 26, UITheme.YELLOW.lightened(0.25), 2.0, true)
	# opaque ink, unlike the glossary badge: an object glyph carries its detail
	# INSIDE the silhouette (the cross in the bottle, the hole in the coin), and
	# those marks are drawn in the ink colour — a transparent ink erases them
	# and leaves six identical bottles.
	Glyphs.draw_glyph(self, key, Rect2(c - Vector2(r, r) * 0.66, Vector2(r, r) * 1.32),
			tint, UITheme.OUTLINE)
	if selected:
		draw_arc(c, r + 3.0, 0.0, TAU, 30, UITheme.YELLOW, 3.0, true)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if _press == null:
		_press = PressGesture.new(self)
		# method callables, not lambdas: Godot drops a connection to a freed
		# object, but a lambda that captured `self` would still be called
		_press.tapped.connect(_emit_pressed)
		_press.long_pressed.connect(_emit_long)
	_press.feed(event)


func _emit_pressed() -> void:
	pressed.emit()


func _emit_long() -> void:
	long_pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN:
		cancel_press()


func cancel_press() -> void:
	if _press != null:
		_press.cancel()


## The two builders the screens actually call.
static func for_relic(rid: String, d := D) -> ItemIcon:
	var rd: Dictionary = GameData.relics[rid]
	var ic := ItemIcon.new(String(rd.get("glyph", "relic")), DetailCard.relic_hue(rid), d)
	ic.ring = GameData.relic_rarity(rid) == "advanced"
	return ic


static func for_potion(pid: String, d := D) -> ItemIcon:
	return ItemIcon.new(DetailCard.potion_glyph(pid), DetailCard.potion_hue(pid), d)
