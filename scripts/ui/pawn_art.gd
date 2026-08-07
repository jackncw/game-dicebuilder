class_name PawnArt
extends Node2D
## Character art. Origin is at the feet; art is drawn upward (negative y).
## Idle = 2-frame stepped bob.
##
## The six heroes are painted plates (cut off their background by
## `tools/art_cutout.py` and imported under `assets/heroes/`). Everything else —
## ten minions and six bosses — is still procedural: flat colour shapes with a
## thick dark outline, no gradients. Both kinds answer the same API, so callers
## never branch on which one they are placing.

const OL := Color("2b2b2b")
const OLW := 4.0

## Painted heroes, by id. A kind that is not in here falls through to a
## `_draw_*` routine.
const HERO_TEX := {
	"BADGER": "res://assets/heroes/badger_full.png",
	"HARE": "res://assets/heroes/hare_full.png",
	"HEDGE": "res://assets/heroes/hedge_full.png",
	"OWL": "res://assets/heroes/owl_full.png",
	"FOX": "res://assets/heroes/fox_full.png",
	"BOAR": "res://assets/heroes/boar_full.png",
}

static var _tex_cache := {}


## The plate for a hero id, loaded once per run. Null for anything procedural.
static func hero_texture(p_kind: String) -> Texture2D:
	if not HERO_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(HERO_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]

var kind := "BADGER"
var body_h := 140.0
var flip := false
var _t := 0.0
var _bob_seed := 0.0
var _attack_offset := Vector2.ZERO


## How much space each design actually uses, as a fraction of the `body_h` it
## was asked for: x = how far it reaches above the feet, y = its half-width.
## Laying art out on nominal height alone leaves voids in some cards and
## collisions in others — a slime fills half its nominal height, a boss with a
## hat overshoots by a quarter.
##
## Procedural entries are measured by `tools/pawn_extents.gd` (re-run it after
## editing a `_draw_*` routine). The painted heroes are trimmed to their own
## silhouette so they fill exactly 1.0 of the height, and their half-width is
## the plate's aspect halved — printed by `tools/art_cutout.py`.
const EXTENT := {
	"BADGER": Vector2(1.00, 0.431), "HARE": Vector2(1.00, 0.388),
	"HEDGE": Vector2(1.00, 0.466), "OWL": Vector2(1.00, 0.475),
	"FOX": Vector2(1.00, 0.428), "BOAR": Vector2(1.00, 0.481),
	"E01": Vector2(0.51, 0.31), "E02": Vector2(0.52, 0.37), "E03": Vector2(0.51, 0.31),
	"E04": Vector2(0.45, 0.42), "E05": Vector2(0.51, 0.34), "E06": Vector2(0.75, 0.25),
	"E07": Vector2(0.65, 0.40), "E08": Vector2(0.61, 0.35), "E09": Vector2(0.49, 0.32),
	"E10": Vector2(0.58, 0.28), "B1": Vector2(1.26, 0.57), "B2": Vector2(1.29, 0.41),
	"B3": Vector2(0.89, 0.44), "B4": Vector2(1.02, 0.41), "B5": Vector2(1.09, 0.39),
	"B6": Vector2(1.27, 0.41),
}


## Where a procedural design's head sits, in the 140px authoring space: x is the
## y of the head's centre (negative — the art is drawn upward from the feet), y
## is the radius that takes in the whole head, ears and hat. `MiniPortrait`
## crops a face out of the full-body art with this.
##
## Empty since the character overhaul: only the heroes ever needed portraits,
## and each of them now ships a dedicated `*_head.png` crop that `MiniPortrait`
## prefers. Kept (with its fallback) so a future procedural portrait works.
const HEAD := {}


static func make(p_kind: String, height := 140.0, p_flip := false) -> PawnArt:
	var pa := PawnArt.new()
	pa.kind = p_kind
	pa.body_h = height
	pa.flip = p_flip
	pa._bob_seed = hash(p_kind) % 100 / 100.0 * TAU
	return pa


static func extent(p_kind: String) -> Vector2:
	return EXTENT.get(p_kind, Vector2(1.0, 0.35))


## Head centre and radius in authoring units — see `HEAD`. The fallback is a
## middle-of-the-road head so a creature without an entry still crops to
## something head-shaped rather than to its feet.
static func head(p_kind: String) -> Vector2:
	return HEAD.get(p_kind, Vector2(-100, 40))


## The `body_h` that makes this design draw as large as `box` allows without
## spilling out of it on either axis.
static func fit_height(p_kind: String, box: Vector2) -> float:
	var e := extent(p_kind)
	return minf(box.y / maxf(e.x, 0.05), box.x / maxf(2.0 * e.y, 0.05))


## A pawn sized to fill `box` (origin still at the feet, so position it at the
## bottom-centre of the box).
static func fitted(p_kind: String, box: Vector2, p_flip := false) -> PawnArt:
	return make(p_kind, fit_height(p_kind, box), p_flip)


var _last_frame := -1.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# redraw only when the stepped idle frame flips (or during a lunge)
	var frame := floorf(fmod(_t * 2.2 + _bob_seed, 2.0)) + floorf(fmod(_t * 4.0, 2.0)) * 0.1
	if frame != _last_frame or _attack_offset != Vector2.ZERO:
		_last_frame = frame
		queue_redraw()


## Quick attack lunge (called by the battle screen).
func play_attack() -> void:
	var tw := create_tween()
	var dir := 1.0 if flip else -1.0
	tw.tween_property(self, "_attack_offset", Vector2(dir * -26.0, -6.0), 0.08)
	tw.tween_property(self, "_attack_offset", Vector2.ZERO, 0.22)


# ============================================================ primitives

func _c(p: Vector2) -> Vector2:
	var q := p
	if flip:
		q.x = -q.x
	return q + _attack_offset


func _circle(center: Vector2, r: float, col: Color, outlined := true) -> void:
	draw_circle(_c(center), r, col)
	if outlined:
		draw_arc(_c(center), r, 0, TAU, 32, OL, OLW, true)


func _ellipse(center: Vector2, rx: float, ry: float, col: Color, outlined := true) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(_c(center + Vector2(cos(a) * rx, sin(a) * ry)))
	draw_colored_polygon(pts, col)
	if outlined:
		draw_polyline(pts, OL, OLW, true)


func _poly(points: Array, col: Color, outlined := true) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(_c(p))
	draw_colored_polygon(pts, col)
	if outlined:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, OL, OLW, true)


func _line(a: Vector2, b: Vector2, col: Color, w := OLW) -> void:
	draw_line(_c(a), _c(b), col, w, true)


func _eyes(center: Vector2, spread: float, r: float, sclera := true) -> void:
	for s in [-1.0, 1.0]:
		var p := center + Vector2(s * spread, 0)
		if sclera:
			_circle(p, r, Color.WHITE, false)
			draw_circle(_c(p), r * 0.45, OL)
		else:
			draw_circle(_c(p), r, OL)


# ============================================================ dispatch

func _draw() -> void:
	var bob := 3.0 * floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	draw_set_transform(Vector2(0, bob), 0, Vector2.ONE)
	var tex := hero_texture(kind)
	if tex != null:
		# Painted plate: reset to an unscaled transform (the plate is not
		# authored in the 140px procedural space) and stand it on the origin.
		draw_set_transform(Vector2(0, bob) + _attack_offset, 0, Vector2.ONE)
		var w := body_h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		var r := Rect2(-w * 0.5, -body_h, w, body_h)
		draw_texture_rect(tex, r, false, Color.WHITE, flip)
		return
	var u := body_h / 140.0   # unit scale: designs authored at 140px height
	draw_set_transform(Vector2(0, bob), 0, Vector2(u, u))
	match kind:
		"E01": _draw_slime()
		"E02": _draw_rat()
		"E03": _draw_sporecap()
		"E04": _draw_beetle()
		"E05": _draw_moth()
		"E06": _draw_vine()
		"E07": _draw_wolf()
		"E08": _draw_wraith()
		"E09": _draw_toad()
		"E10": _draw_viper()
		"B1": _draw_basher_bunny()
		"B2": _draw_boxer_hare()
		"B3": _draw_sir_croak()
		"B4": _draw_fishbone_cat()
		"B5": _draw_purrceval()
		"B6": _draw_croakomancer()
		_: _draw_slime()


# ============================================================ minions

func _draw_slime() -> void:
	var g := Color("6fbf5a")
	_ellipse(Vector2(0, -34), 40, 34, g)
	_ellipse(Vector2(-12, -48), 10, 6, Color(1, 1, 1, 0.35), false)
	_eyes(Vector2(0, -40), 13, 5)
	draw_arc(_c(Vector2(0, -28)), 9, 0.4, PI - 0.4, 10, OL, 3, true)


func _draw_rat() -> void:
	var brown := Color("9a8571")
	# tail
	draw_arc(_c(Vector2(34, -18)), 16, PI * 1.1, PI * 1.9, 12, Color("c98d8d"), 4, true)
	# body teardrop
	_poly([Vector2(-34, -10), Vector2(-10, -58), Vector2(16, -52), Vector2(34, -8)], brown)
	# ears
	_circle(Vector2(-12, -60), 10, Color("c98d8d"))
	_circle(Vector2(8, -58), 8, Color("c98d8d"))
	_eyes(Vector2(-6, -40), 8, 4, false)
	# teeth
	_poly([Vector2(-16, -26), Vector2(-10, -26), Vector2(-13, -18)], Color.WHITE, false)
	# whiskers
	_line(Vector2(-24, -28), Vector2(-38, -30), OL, 2)


func _draw_sporecap() -> void:
	var cap := Color("b06ac2")
	var stem := Color("e8ddc8")
	_poly([Vector2(-14, -36), Vector2(14, -36), Vector2(10, -4), Vector2(-10, -4)], stem)
	_ellipse(Vector2(0, -46), 40, 22, cap)
	for spot in [[-20.0, -52.0], [4.0, -60.0], [22.0, -48.0]]:
		draw_circle(_c(Vector2(spot[0], spot[1])), 5, Color("e3c9ef"))
	_eyes(Vector2(0, -24), 9, 4, false)


func _draw_beetle() -> void:
	var shell := Color("7d7f8a")
	_ellipse(Vector2(0, -30), 40, 28, shell)
	_line(Vector2(0, -58), Vector2(0, -4), OL, 3)
	# horn
	_poly([Vector2(-34, -40), Vector2(-52, -58), Vector2(-30, -50)], shell.darkened(0.15))
	# legs
	for i in 3:
		_line(Vector2(-18 + i * 16, -6), Vector2(-24 + i * 16, 2), OL, 3)
	_eyes(Vector2(-22, -34), 6, 3.5, false)


func _draw_moth() -> void:
	var wing := Color("5d5470")
	var body := Color("8c7fa8")
	var flap := 6.0 * floorf(fmod(_t * 4.0, 2.0))
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 6, -46), Vector2(s * 44, -66 + flap), Vector2(s * 38, -30 + flap * 0.5), Vector2(s * 8, -28)], wing)
		draw_circle(_c(Vector2(s * 28, -48 + flap * 0.7)), 6, Color("e0a83c"))
	_ellipse(Vector2(0, -36), 11, 22, body)
	_eyes(Vector2(0, -50), 6, 3.5, false)
	# antennae
	for s in [-1.0, 1.0]:
		_line(Vector2(s * 4, -56), Vector2(s * 12, -70), OL, 2)


func _draw_vine() -> void:
	var green := Color("4c7a3d")
	var leaf := Color("6fae5c")
	# stalk s-curve
	draw_arc(_c(Vector2(-8, -30)), 18, -PI * 0.5, PI * 0.5, 14, green, 8, true)
	draw_arc(_c(Vector2(6, -58)), 16, PI * 0.5, PI * 1.5, 14, green, 8, true)
	# head bud
	_circle(Vector2(6, -76), 14, leaf)
	_poly([Vector2(-2, -86), Vector2(6, -100), Vector2(12, -86)], leaf)
	_eyes(Vector2(6, -76), 7, 3.5, false)
	# thorns
	for th in [[-20.0, -36.0], [-14.0, -22.0], [16.0, -52.0]]:
		_poly([Vector2(th[0], th[1]), Vector2(th[0] - 8, th[1] - 4), Vector2(th[0] - 2, th[1] + 6)], green.darkened(0.15), false)
	# leaves
	_ellipse(Vector2(-24, -48), 10, 5, leaf, false)
	_ellipse(Vector2(20, -30), 10, 5, leaf, false)


func _draw_wolf() -> void:
	var bone := Color("cfc9bc")
	# body
	_poly([Vector2(-36, -6), Vector2(-30, -40), Vector2(20, -46), Vector2(34, -6)], bone)
	# rib lines
	for i in 2:
		draw_arc(_c(Vector2(-4 + i * 12, -26)), 10, PI * 0.2, PI * 0.9, 8, bone.darkened(0.25), 3, true)
	# head
	_poly([Vector2(-46, -64), Vector2(-14, -70), Vector2(-8, -46), Vector2(-30, -40), Vector2(-52, -48)], bone)
	# ears
	_poly([Vector2(-38, -68), Vector2(-42, -86), Vector2(-26, -72)], bone)
	# eye socket
	_ellipse(Vector2(-34, -58), 5, 6, OL, false)
	# muzzle line + fangs
	_line(Vector2(-52, -48), Vector2(-40, -46), OL, 3)
	_poly([Vector2(-48, -47), Vector2(-45, -47), Vector2(-47, -40)], Color.WHITE, false)
	# tail
	_line(Vector2(34, -22), Vector2(48, -34), bone, 6)


func _draw_wraith() -> void:
	var ghost := Color("8fa8c9", 0.9)
	var pts := [Vector2(-30, -10), Vector2(-32, -60), Vector2(0, -84), Vector2(32, -60), Vector2(30, -10)]
	# wavy hem
	var hem := []
	for i in 5:
		hem.append(Vector2(30 - i * 15, -10 + (6 if i % 2 == 0 else 0)))
	_poly(pts.slice(0, 4) + [pts[4]] + hem, ghost)
	_eyes(Vector2(0, -60), 11, 5, false)
	# wisp arms
	_line(Vector2(-32, -48), Vector2(-46, -56), ghost.darkened(0.1), 6)
	_line(Vector2(32, -48), Vector2(46, -56), ghost.darkened(0.1), 6)


func _draw_toad() -> void:
	var lava := Color("c2543a")
	_ellipse(Vector2(0, -30), 42, 30, lava)
	# lava cracks
	for cr in [[-18.0, -36.0], [8.0, -24.0], [20.0, -42.0]]:
		draw_circle(_c(Vector2(cr[0], cr[1])), 4.5, Color("f2a541"))
	# eye bumps
	_circle(Vector2(-18, -58), 10, lava)
	_circle(Vector2(18, -58), 10, lava)
	_eyes(Vector2(0, -58), 18, 5)
	# wide mouth
	draw_arc(_c(Vector2(0, -30)), 22, 0.3, PI - 0.3, 14, OL, 3.5, true)
	# front feet
	_ellipse(Vector2(-20, -4), 12, 5, lava)
	_ellipse(Vector2(20, -4), 12, 5, lava)


func _draw_viper() -> void:
	var green := Color("5aa87c")
	# coiled body
	draw_arc(_c(Vector2(0, -24)), 26, 0, PI, 18, green, 12, true)
	draw_arc(_c(Vector2(0, -44)), 18, PI, TAU, 14, green, 10, true)
	# two heads
	for s in [-1.0, 1.0]:
		var hx: float = s * 20.0
		_ellipse(Vector2(hx, -70), 12, 9, green)
		_eyes(Vector2(hx, -72), 5, 2.5, false)
		# forked tongue
		_line(Vector2(hx + s * 10, -70), Vector2(hx + s * 18, -68), Color("d94f4f"), 2.5)
		# neck
		_line(Vector2(hx * 0.5, -52), Vector2(hx, -64), green, 9)


# ============================================================ bosses

func _draw_basher_bunny() -> void:
	var fur := Color("d8cbb4")
	# spiked club (behind, angled)
	_poly([Vector2(20, -60), Vector2(64, -104), Vector2(76, -92), Vector2(32, -48)], Color("8a6f4d"))
	for sp in [[52.0, -96.0], [62.0, -86.0], [44.0, -78.0]]:
		_poly([Vector2(sp[0], sp[1]), Vector2(sp[0] + 10, sp[1] - 10), Vector2(sp[0] + 6, sp[1] + 2)], Color("6b6b78"), false)
	# body
	_ellipse(Vector2(0, -44), 36, 42, fur)
	# belly
	_ellipse(Vector2(0, -36), 22, 26, fur.lightened(0.12), false)
	# head
	_circle(Vector2(0, -102), 28, fur)
	# long ears (one bent)
	_poly([Vector2(-16, -124), Vector2(-22, -170), Vector2(-2, -130)], fur)
	_poly([Vector2(14, -124), Vector2(34, -156), Vector2(26, -122)], fur)
	# angry eyes
	for s in [-1.0, 1.0]:
		_line(Vector2(s * 16, -116), Vector2(s * 6, -112), OL, 3)
		draw_circle(_c(Vector2(s * 10, -106)), 3.5, OL)
	# muzzle
	_circle(Vector2(0, -96), 4, OL, false)
	_ellipse(Vector2(-14, -5), 15, 7, fur)
	_ellipse(Vector2(14, -5), 15, 7, fur)


func _draw_boxer_hare() -> void:
	var fur := Color("d9c9b0")
	var glove := Color("d94f4f")
	# body lean
	_ellipse(Vector2(0, -46), 30, 42, fur)
	# head
	_circle(Vector2(4, -104), 26, fur)
	# tall straight ears
	_poly([Vector2(-8, -126), Vector2(-10, -174), Vector2(6, -128)], fur)
	_poly([Vector2(14, -126), Vector2(24, -170), Vector2(28, -124)], fur)
	# determined eyes
	for s in [-1.0, 1.0]:
		draw_circle(_c(Vector2(4 + s * 10, -108)), 3.5, OL)
		_line(Vector2(4 + s * 14, -118), Vector2(4 + s * 5, -114), OL, 3)
	# boxing gloves (big!)
	_circle(Vector2(-34, -66), 16, glove)
	_circle(Vector2(38, -80), 16, glove)
	_line(Vector2(-24, -58), Vector2(-12, -52), glove.darkened(0.2), 5)
	_line(Vector2(28, -72), Vector2(16, -62), glove.darkened(0.2), 5)
	_ellipse(Vector2(-10, -5), 14, 7, fur)
	_ellipse(Vector2(16, -5), 14, 7, fur)


func _draw_sir_croak() -> void:
	var goose := Color("f2f0e9")
	var frog := Color("6fae5c")
	# goose body
	_ellipse(Vector2(4, -36), 42, 26, goose)
	# goose neck + head
	_poly([Vector2(-30, -50), Vector2(-38, -96), Vector2(-24, -96), Vector2(-18, -52)], goose)
	_circle(Vector2(-30, -102), 12, goose)
	_poly([Vector2(-40, -104), Vector2(-54, -100), Vector2(-40, -96)], Color("e0a83c"))
	draw_circle(_c(Vector2(-32, -106)), 2.5, OL)
	# frog rider
	_circle(Vector2(14, -82), 18, frog)
	_circle(Vector2(8, -96), 6, frog)
	_circle(Vector2(22, -96), 6, frog)
	_eyes(Vector2(15, -96), 7, 3.5)
	# tiny helmet
	draw_arc(_c(Vector2(14, -88)), 17, PI, TAU, 12, Color("9aa0ad"), 5, true)
	# sword raised
	_line(Vector2(34, -84), Vector2(52, -122), Color("c8cad0"), 5)
	_line(Vector2(30, -90), Vector2(40, -86), Color("8a6f4d"), 5)
	# goose feet
	_line(Vector2(-6, -10), Vector2(-10, 0), Color("e0a83c"), 4)
	_line(Vector2(18, -10), Vector2(22, 0), Color("e0a83c"), 4)


func _draw_fishbone_cat() -> void:
	var fur := Color("6b6155")
	# tail
	draw_arc(_c(Vector2(36, -30)), 18, PI * 1.05, PI * 1.85, 12, fur, 7, true)
	# body (sneaky hunch)
	_ellipse(Vector2(0, -42), 32, 38, fur)
	# lighter belly
	_ellipse(Vector2(-2, -34), 18, 22, fur.lightened(0.15), false)
	# head
	_circle(Vector2(-6, -94), 26, fur)
	_poly([Vector2(-28, -108), Vector2(-34, -136), Vector2(-12, -116)], fur)
	_poly([Vector2(16, -108), Vector2(22, -136), Vector2(0, -116)], fur)
	# sly eyes (half-lidded)
	for s in [-1.0, 1.0]:
		_line(Vector2(-6 + s * 14, -98), Vector2(-6 + s * 4, -98), OL, 4)
	# fishbone in mouth
	_line(Vector2(-30, -84), Vector2(14, -78), Color("efe9df"), 4)
	for i in 3:
		_line(Vector2(-20 + i * 12, -88), Vector2(-18 + i * 12, -74), Color("efe9df"), 3)
	_circle(Vector2(-32, -85), 5, Color("efe9df"), false)
	_ellipse(Vector2(-12, -5), 13, 6, fur)
	_ellipse(Vector2(14, -5), 13, 6, fur)


func _draw_purrceval() -> void:
	var steel := Color("9aa0ad")
	var plume := Color("d94f4f")
	# armored body
	_poly([Vector2(-30, -80), Vector2(30, -80), Vector2(36, -8), Vector2(-36, -8)], steel)
	# chest plate lines
	_line(Vector2(-24, -56), Vector2(24, -56), OL, 3)
	_line(Vector2(-28, -32), Vector2(28, -32), OL, 3)
	# shield
	_poly([Vector2(-52, -70), Vector2(-30, -70), Vector2(-30, -30), Vector2(-41, -20), Vector2(-52, -30)], Color("4f7fd9"))
	_circle(Vector2(-41, -50), 6, Color("d4af37"), false)
	# sword
	_line(Vector2(40, -30), Vector2(46, -110), Color("c8cad0"), 6)
	_line(Vector2(33, -88), Vector2(52, -84), Color("8a6f4d"), 5)
	# helmet with cat ears
	_circle(Vector2(0, -106), 24, steel)
	_poly([Vector2(-20, -122), Vector2(-24, -146), Vector2(-6, -126)], steel)
	_poly([Vector2(20, -122), Vector2(24, -146), Vector2(6, -126)], steel)
	# visor slit: cat eyes glow
	_poly([Vector2(-18, -108), Vector2(18, -108), Vector2(16, -98), Vector2(-16, -98)], OL, false)
	for s in [-1.0, 1.0]:
		_ellipse(Vector2(s * 8, -103), 4, 2.5, Color("9fe07a"), false)
	# plume
	draw_arc(_c(Vector2(2, -128)), 12, PI, PI * 1.7, 8, plume, 6, true)


func _draw_croakomancer() -> void:
	var frog := Color("6fae5c")
	var robe := Color("3f6b35")
	# robe
	_poly([Vector2(-30, -84), Vector2(30, -84), Vector2(40, -6), Vector2(-40, -6)], robe)
	# rune trim
	for i in 3:
		_circle(Vector2(-16 + i * 16, -20), 3.5, Color("9fe07a"), false)
	# head
	_circle(Vector2(0, -104), 28, frog)
	_circle(Vector2(-15, -128), 10, frog)
	_circle(Vector2(15, -128), 10, frog)
	_eyes(Vector2(0, -128), 15, 5)
	# glowing pupils
	for s in [-1.0, 1.0]:
		draw_circle(_c(Vector2(s * 15, -128)), 2.2, Color("9b6dd9"))
	draw_arc(_c(Vector2(0, -98)), 13, 0.3, PI - 0.3, 12, OL, 3.5, true)
	# wizard hat (crooked)
	_ellipse(Vector2(0, -138), 30, 8, robe.darkened(0.15))
	_poly([Vector2(-16, -138), Vector2(16, -138), Vector2(20, -172), Vector2(8, -160)], robe.darkened(0.15))
	# staff with orb
	_line(Vector2(-40, -6), Vector2(-46, -110), Color("8a6f4d"), 5)
	var pulse := 2.0 * floorf(fmod(_t * 3.0, 2.0))
	_circle(Vector2(-46, -118), 9 + pulse, Color("9b6dd9"))
