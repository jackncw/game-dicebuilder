class_name MiniPortrait
extends Control
## A character's head in a disc: the party art itself, cropped to the head, on a
## tinted circle inside the house outline.
##
## Play test note that produced it — an offer card said "強化匕首 / 攻4 穿刺 /
## 苔蛙遊俠" and the player still had to read the third line to know whose card
## it was. A face is somebody's face; the card should say so before any type is
## read. Reusable anywhere the answer to "whose?" matters: pass a hero id, a
## diameter, and (only if the crop can spill) the colour behind it.
##
## The crop is the pawn's own `_draw`, not a second drawing of the character —
## scaled so the head fills the disc and offset so the head's centre lands on
## the centre. `PawnArt.head()` says where to expect a head. Every hero now
## ships a `*_head.png` framed on the face, so that path is the fallback only.

const DEFAULT_D := 54.0

## Head crops for the painted heroes. Cutting a head out of the full plate the
## way the procedural pawns are cropped loses the face at 38px: the plates are
## painted at a distance, so the head is a small part of a busy silhouette.
## These are framed on the face by `tools/art_cutout.py`.
const HEAD_TEX := {
	"BADGER": "res://assets/heroes/badger_head.png",
	"HARE": "res://assets/heroes/hare_head.png",
	"HEDGE": "res://assets/heroes/hedge_head.png",
	"OWL": "res://assets/heroes/owl_head.png",
	"FOX": "res://assets/heroes/fox_head.png",
	"BOAR": "res://assets/heroes/boar_head.png",
}

static var _tex_cache := {}

var kind := "BADGER"
var diameter := DEFAULT_D
var tint := UITheme.CREAM_DARK
## What the portrait is sitting on. Only used by the fallback mask (see `_Ring`).
var behind := UITheme.CREAM


static func make(p_kind: String, d := DEFAULT_D, p_tint := UITheme.CREAM_DARK,
		p_behind := UITheme.CREAM) -> MiniPortrait:
	var mp := MiniPortrait.new()
	mp.kind = p_kind
	mp.diameter = d
	mp.tint = p_tint
	mp.behind = p_behind
	mp.custom_minimum_size = Vector2(d, d)
	mp.size = Vector2(d, d)
	return mp


static func _head_texture(p_kind: String) -> Texture2D:
	if not HEAD_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(HEAD_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	# Godot clips a CanvasItem's children against what that item itself drew, so
	# the disc below is both the backing colour and the circular crop.
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	var r := diameter * 0.5
	var head_tex := _head_texture(kind)
	if head_tex != null:
		var tr := TextureRect.new()
		tr.texture = head_tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var h := PawnArt.head(kind)
		var u := (r * 0.88) / maxf(h.y, 1.0)     # head radius → most of the disc
		var art := PawnArt.make(kind, 140.0 * u)
		# the pawn's origin is its feet; push it down until the head centre is
		# the disc centre
		art.position = Vector2(r, r - h.x * u)
		add_child(art)
		# a portrait is a still. The idle bob is 3px of vertical travel, which
		# inside a 54px crop reads as a twitch rather than as breathing.
		art.set_process(false)

	var ring := _Ring.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.behind = behind
	add_child(ring)


func _draw() -> void:
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, tint)


## The frame, drawn inside the disc so the outline is never itself clipped away,
## plus a ring of the surrounding colour just outside it. That second ring is
## dead weight whenever `clip_children` does its job (it is clipped off with
## everything else outside the disc) and is what hides the pawn's shoulders in
## the corners if a future Godot ever stops honouring it.
class _Ring:
	extends Control
	var behind := UITheme.CREAM

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r * 1.5, 0.0, TAU, 48, behind, r, false)
		draw_arc(c, r - 2.0, 0.0, TAU, 48, UITheme.OUTLINE, 4.0, true)
