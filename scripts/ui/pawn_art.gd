class_name PawnArt
extends Node2D
## Character art. Origin is at the feet; art is drawn upward (negative y).
## Idle = 2-frame stepped bob.
##
## The six heroes are painted plates (cut off their background by
## `tools/art_cutout.py` and imported under `assets/heroes/`). Everything else —
## ten minions and six bosses — is procedural: flat colour shapes with a thick
## dark outline, no gradients. Both kinds answer the same API, so callers never
## branch on which one they are placing.
##
## ── The two sides ────────────────────────────────────────────────
## Heroes are warm forest colours. Everything hostile shares one visual
## language instead: a body sunk towards `UITheme.ROT_UNDER`, magenta cracks
## across it, lit magenta eyes, and black mist. Magenta belongs to the enemy
## and to nothing else in the game — see `UITheme.is_magenta`.
##
## ── Tiers ────────────────────────────────────────────────────────
## The same minion is fought in all three chapters, and the chapter is its
## tier. Tier is drawn, not just tabulated: a T1 slime is a smaller, paler,
## barely-cracked animal and a T3 slime is a bigger, darker one smoking at the
## edges. Four dials move together (bulk, tone, crack count, eye heat, mist),
## which is what makes the three read apart at a glance rather than needing a
## side-by-side. Bosses have no tier — they are always all the way gone.

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

## Bosses, including Sir Croak's dismounted second phase. Kept as a list rather
## than a `begins_with("B")` test because two of the heroes are a BADGER and a
## BOAR.
const BOSS_KINDS := ["B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]

## The main colour of each enemy — the one that covers most of its silhouette,
## before the rot is applied. Every entry is chosen so that `_rot()` at tier 3
## (its darkest) still clears 2.4:1 against all three chapter card surfaces;
## `_t_enemy_legibility` in `ui_smoke` holds that line.
##
## The references paint these creatures nearly black, which works on the cream
## sheet they were drawn on. Our enemy cards are `UITheme.surface(chapter)` —
## chapter 3's is `#1e1429` — so a near-black body would be a hole in the
## panel. The bodies here are lifted to a dark mid-tone and carry their
## "corrupted" reading through desaturation, the violet undertone, the cracks
## and the mist instead.
const BODY := {
	"E01": Color("6a8d53"),   # slime, still recognisably green
	"E02": Color("8a7f96"),   # fang rat
	"E03": Color("99779e"),   # sporecap — the cap is most of its outline
	"E04": Color("85808f"),   # stone beetle
	"E05": Color("8d7ba2"),   # gloom moth — the wings
	"E06": Color("9d7c68"),   # bramble vine
	"E07": Color("8d8079"),   # bone wolf — what hide is left on it
	"E08": Color("8d7ba5"),   # wraith
	"E09": Color("ab775d"),   # lava toad
	"E10": Color("6a8c65"),   # twin viper
	"B1": Color("8c7d96"), "B2": Color("8c7d96"),
	"B3": Color("8d7c9e"), "B3P2": Color("8a7d9c"),
	"B4": Color("8a7d9c"), "B5": Color("8a7e95"), "B6": Color("8b7d9a"),
}

## Bone, steel and wood keep their own identity through the rot — they are what
## tells a fishbone sword from a fishbone. Desaturated to sit in the same
## world, but never pulled into the violet.
const BONE := Color("d5cfc0")
const STEEL := Color("a9a3b0")
const WOOD := Color("8a6a4c")
const EMBER := Color("ff8a3c")     # lava toad's cracks: heat, not rot

## How much of its own art a design draws at each tier. The extents in `EXTENT`
## are measured at tier 3, the biggest, so a tier-1 minion simply sits smaller
## inside the same card — which is the point.
const TIER_BULK := {1: 0.90, 2: 1.0, 3: 1.12}

static var _tex_cache := {}


## The plate for a hero id, loaded once per run. Null for anything procedural.
static func hero_texture(p_kind: String) -> Texture2D:
	if not HERO_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(HERO_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]


static func is_boss(p_kind: String) -> bool:
	return p_kind in BOSS_KINDS


var kind := "BADGER"
var body_h := 140.0
var flip := false
var tier := 3
var _t := 0.0
var _bob_seed := 0.0
var _attack_offset := Vector2.ZERO


## How much space each design actually uses, as a fraction of the `body_h` it
## was asked for: x = how far it reaches above the feet, y = its half-width.
## Laying art out on nominal height alone leaves voids in some cards and
## collisions in others — a slime fills half its nominal height, a boss with a
## hat overshoots by a quarter.
##
## Procedural entries are measured by `tools/pawn_extents.gd` at tier 3, the
## fullest a design ever draws (re-run it after editing a `_draw_*` routine).
## The painted heroes are trimmed to their own silhouette so they fill exactly
## 1.0 of the height, and their half-width is the plate's aspect halved —
## printed by `tools/art_cutout.py`.
const EXTENT := {
	"BADGER": Vector2(1.00, 0.431), "HARE": Vector2(1.00, 0.388),
	"HEDGE": Vector2(1.00, 0.466), "OWL": Vector2(1.00, 0.475),
	"FOX": Vector2(1.00, 0.428), "BOAR": Vector2(1.00, 0.481),
	"E01": Vector2(0.65, 0.37), "E02": Vector2(0.59, 0.66), "E03": Vector2(0.72, 0.35),
	"E04": Vector2(0.73, 0.43), "E05": Vector2(0.66, 0.46), "E06": Vector2(0.77, 0.43),
	"E07": Vector2(0.70, 0.69), "E08": Vector2(0.80, 0.38), "E09": Vector2(0.56, 0.39),
	"E10": Vector2(0.83, 0.53), "B1": Vector2(1.45, 0.64), "B2": Vector2(1.47, 0.77),
	"B3": Vector2(1.24, 0.81), "B3P2": Vector2(1.12, 0.49), "B4": Vector2(1.22, 0.58),
	"B5": Vector2(1.26, 0.71), "B6": Vector2(1.54, 0.55),
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


static func make(p_kind: String, height := 140.0, p_flip := false, p_tier := 3) -> PawnArt:
	var pa := PawnArt.new()
	pa.kind = p_kind
	pa.body_h = height
	pa.flip = p_flip
	pa.tier = clampi(p_tier, 1, 3)
	pa._bob_seed = hash(p_kind) % 100 / 100.0 * TAU
	return pa


static func extent(p_kind: String) -> Vector2:
	return EXTENT.get(p_kind, Vector2(1.0, 0.35))


## What fraction of its art a design draws at `p_tier`. Bosses ignore tier.
static func bulk(p_kind: String, p_tier: int) -> float:
	if is_boss(p_kind) or HERO_TEX.has(p_kind):
		return 1.0
	return float(TIER_BULK.get(clampi(p_tier, 1, 3), 1.0))


## Half-width of a design as actually drawn at `p_tier`. The card is sized
## against the tier-3 envelope, but the ground shadow under a tier-1 minion
## should be the width of the tier-1 minion.
static func half_width(p_kind: String, p_tier: int) -> float:
	return extent(p_kind).y * bulk(p_kind, p_tier)


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
static func fitted(p_kind: String, box: Vector2, p_flip := false, p_tier := 3) -> PawnArt:
	return make(p_kind, fit_height(p_kind, box), p_flip, p_tier)


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


## An arc as a polyline. `draw_arc` sweeps in screen space, so a mirrored pawn
## would get its curls facing the wrong way; this one goes through `_c` point by
## point and mirrors properly. Every curve in this file uses it.
func _arc(center: Vector2, r: float, a0: float, a1: float, col: Color,
		w := OLW, steps := 16) -> void:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a: float = a0 + (a1 - a0) * float(i) / float(steps)
		pts.append(_c(center + Vector2(cos(a) * r, sin(a) * r)))
	draw_polyline(pts, col, w, true)


## Catmull-Rom through the control points, so a `_limb` laid on them turns
## gradually. Without it a tight corner makes the two offset edges cross and the
## limb tears itself into shards — which is precisely what the bramble did on
## the first pass.
func _smooth(points: Array, per_seg := 5) -> Array:
	if points.size() < 3:
		return points.duplicate()
	var out := []
	for i in points.size() - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		for k in per_seg:
			var t := float(k) / float(per_seg)
			var t2 := t * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (p3 - p0 + 3.0 * (p1 - p2)) * t2 * t))
	out.append(points[points.size() - 1])
	return out


## A stroke of the given width turned into a filled, outlined shape — for limbs
## and vines, where a plain thick line reads as a line and not as a body part.
func _limb(raw: Array, w: float, col: Color, taper := 1.0) -> void:
	var points := _smooth(raw)
	var left := []
	var right := []
	for i in points.size():
		var p: Vector2 = points[i]
		var f := float(i) / maxf(float(points.size() - 1), 1.0)
		var dir: Vector2 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)])
		if dir.length() < 0.001:
			dir = Vector2(1, 0)
		var n := dir.normalized().orthogonal() * (w * 0.5 * lerpf(1.0, taper, f))
		left.append(p + n)
		right.append(p - n)
	right.reverse()
	_poly(left + right, col)


## The point ring of a dome standing on `base_y` — the base shape of every low,
## heavy creature here. Hand-listing enough points to keep a big curve smooth
## made the designs unreadable as source, so the curve is generated and only the
## silhouette's character (the skirt, the lip) is written out at the call site.
func _dome_points(cx: float, base_y: float, rx: float, h: float, steps := 14) -> Array:
	var pts := []
	for i in steps + 1:
		var a := PI - PI * float(i) / float(steps)
		pts.append(Vector2(cx + cos(a) * rx, base_y - sin(a) * h))
	return pts


## A pointed oval on a stem — a leaf, and the tapered fin the fishbone ends in.
func _leaf(at: Vector2, along: Vector2, w: float, col: Color) -> void:
	var n := along.orthogonal().normalized() * w
	_poly([at, at + along * 0.45 + n, at + along, at + along * 0.45 - n], col)


# ============================================================ corruption

## 0.0 at tier 1, 1.0 at tier 3. Bosses are never anything but 1.0.
static func rot_of(p_kind: String, p_tier: int) -> float:
	if is_boss(p_kind):
		return 1.0
	return clampf((float(clampi(p_tier, 1, 3)) - 1.0) * 0.5, 0.0, 1.0)


## A body colour taken to a depth of rot: at 0 the animal keeps its own colour
## and is only lifted, at 1 it has sunk into the dead violet everything hostile
## ends up as.
static func rot_shade(base: Color, t: float) -> Color:
	if t <= 0.5:
		return base.lightened(0.28 * (0.5 - t))
	return base.lerp(UITheme.ROT_UNDER, 0.56 * (t - 0.5))


## What a design's main colour is actually painted as at `p_tier`, without
## needing a pawn in the tree. `_t_enemy_legibility` in `ui_smoke` walks every
## entry in `BODY` through this and checks it against the three chapter cards.
static func rot_body(p_kind: String, p_tier: int) -> Color:
	return rot_shade(BODY.get(p_kind, Color("8a7d9a")), rot_of(p_kind, p_tier))


func rot_level() -> float:
	return rot_of(kind, tier)


func _rot(base: Color) -> Color:
	return rot_shade(base, rot_level())


## This design's main colour, rotted.
func _body() -> Color:
	return _rot(BODY.get(kind, Color("8a7d9a")))


## Corruption cracks. `lines` is a list of polylines in authoring space, most
## important first — tier 1 draws roughly the first third of them, tier 3 draws
## all of them and lays a soft wide pass underneath so they glow.
func _veins(lines: Array) -> void:
	var t := rot_level()
	var col := UITheme.ROT_VEIN_DIM.lerp(UITheme.ROT_VEIN, t)
	_cracks(lines, col, 1.6 + 0.9 * t, 0.34 + 0.66 * t, 0.44 * t)


## The shared crack renderer. `keep` is the fraction of `lines` drawn, `glow`
## the strength of the wide soft pass under each one.
func _cracks(lines: Array, col: Color, w: float, keep := 1.0, glow := 0.0) -> void:
	var n := mini(int(ceil(lines.size() * keep)), lines.size())
	for i in n:
		var pts := PackedVector2Array()
		for p in lines[i]:
			pts.append(_c(p))
		if pts.size() < 2:
			continue
		if glow > 0.01:
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.18 * glow), w * 2.6, true)
		draw_polyline(pts, col, w, true)


## One lit eye. No outline: it is a light source, and ringing it in `OL` reads
## as a painted dot instead.
func _rot_eye(p: Vector2, r: float) -> void:
	var t := rot_level()
	var col := UITheme.ROT_EYE_DIM.lerp(UITheme.ROT_EYE, t)
	draw_circle(_c(p), r * (1.35 + 0.55 * t), Color(col.r, col.g, col.b, 0.11 + 0.13 * t))
	draw_circle(_c(p), r, col)
	draw_circle(_c(p), r * 0.38, col.lightened(0.6))


func _rot_eyes(center: Vector2, spread: float, r: float) -> void:
	for s in [-1.0, 1.0]:
		_rot_eye(center + Vector2(s * spread, 0), r)


## The smoke coming off a corrupted thing — `[x, y, height]` per wisp, drawn
## BEFORE the body so it rises from behind. Tier 1 has none, and that absence is
## most of what makes a T1 minion look merely sick rather than lost.
func _mist(spots: Array) -> void:
	var t := rot_level()
	if t <= 0.01:
		return
	var a := 0.34 + 0.30 * t
	var n := mini(int(ceil(spots.size() * (0.5 + 0.5 * t))), spots.size())
	var step := floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	for i in n:
		var s: Array = spots[i]
		_wisp(Vector2(float(s[0]), float(s[1])), float(s[2]), float(i) * 1.1 + step * 0.7, a)


## One curl of smoke: an S-shaped column that swells in the middle and closes
## to a point at the top.
func _wisp(base: Vector2, h: float, phase: float, a: float) -> void:
	var steps := 9
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in steps + 1:
		var f := float(i) / float(steps)
		var y := base.y - h * f
		var x := base.x + sin(phase + f * PI * 1.7) * h * 0.20
		var w := h * 0.17 * (1.0 - f) * (0.35 + f * 1.7)
		left.append(_c(Vector2(x - w, y)))
		right.append(_c(Vector2(x + w, y)))
	right.reverse()
	draw_colored_polygon(left + right,
			Color(UITheme.ROT_MIST.r, UITheme.ROT_MIST.g, UITheme.ROT_MIST.b, a))


## A lit edge along a silhouette. The corrupted bodies are dark on purpose and
## chapter 3's card is nearly black, so the two designs that are darkest by
## nature — the moth and the wraith — plus every boss carry one of these to keep
## their outline from dissolving into the panel.
func _rim(points: Array, w := 3.0, a := 0.8) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(_c(p))
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(UITheme.ROT_RIM.r, UITheme.ROT_RIM.g, UITheme.ROT_RIM.b, a),
			w, true)


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
	# unit scale: designs authored at 140px height, then taken down or up by
	# how far gone the creature is
	var u := body_h / 140.0 * bulk(kind, tier)
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
		"B3P2": _draw_sir_croak_afoot()
		"B4": _draw_fishbone_cat()
		"B5": _draw_purrceval()
		"B6": _draw_croakomancer()
		_: _draw_slime()


# ============================================================ minions

## E01 — a blob that has kept its green. Everything about it is the face: the
## reference sells the whole creature on one furious scowl.
func _draw_slime() -> void:
	var g := _body()
	_mist([[-28.0, -52.0, 24.0], [24.0, -56.0, 26.0], [0.0, -64.0, 18.0]])
	var pts := _dome_points(0.0, -3.0, 43.0, 61.0, 18)
	# the skirt it has run out into, so it sits on the ground rather than floats
	pts.append_array([Vector2(30, -1), Vector2(12, -7), Vector2(-10, -1),
			Vector2(-30, -7)])
	_poly(pts, g)
	_ellipse(Vector2(-18, -46), 12, 6, g.lightened(0.22), false)
	_veins([
		[Vector2(-4, -60), Vector2(-11, -52), Vector2(-8, -42), Vector2(-16, -32),
				Vector2(-13, -20)],
		[Vector2(12, -58), Vector2(17, -47), Vector2(12, -36), Vector2(20, -25),
				Vector2(16, -14)],
		[Vector2(-11, -52), Vector2(-22, -49), Vector2(-27, -41)],
		[Vector2(17, -47), Vector2(28, -44), Vector2(33, -37)],
		[Vector2(2, -62), Vector2(4, -54), Vector2(0, -47)],
		[Vector2(-16, -32), Vector2(-27, -28)],
	])
	# heavy brows and a jaw set right down
	_line(Vector2(-25, -46), Vector2(-9, -40), OL, 4)
	_line(Vector2(25, -46), Vector2(9, -40), OL, 4)
	_rot_eyes(Vector2(0, -35), 13, 4.5)
	_arc(Vector2(0, -11), 13, PI * 1.16, PI * 1.84, OL, 4, 12)


## E02 — lean quadruped, hunched at the shoulder, snout open on a pair of
## fangs, naked tail whipping up behind it.
func _draw_rat() -> void:
	var f := _body()
	var dark := f.darkened(0.20)
	_mist([[20.0, -48.0, 26.0], [-18.0, -52.0, 22.0]])
	# tail: thick where it leaves the rump, whipping up behind
	_limb([Vector2(26, -26), Vector2(48, -22), Vector2(64, -34), Vector2(62, -58)],
			13.0, dark, 0.28)
	# legs, behind the barrel
	for lg in [[24.0, -26.0], [-10.0, -22.0]]:
		_limb([Vector2(float(lg[0]), float(lg[1])), Vector2(float(lg[0]) - 5.0, -3)],
				14.0, dark, 0.55)
	# barrel: one mass, arched at the shoulder and dropping to the neck
	_poly([Vector2(-30, -18), Vector2(-34, -38), Vector2(-16, -54), Vector2(12, -56),
			Vector2(32, -44), Vector2(36, -20), Vector2(18, -10), Vector2(-18, -11)], f)
	# head, driven forward and down off the shoulder
	_poly([Vector2(-26, -52), Vector2(-46, -54), Vector2(-66, -42), Vector2(-70, -26),
			Vector2(-48, -16), Vector2(-26, -24)], f)
	_circle(Vector2(-34, -55), 12, dark)
	# fore paws, under the chin
	for px in [-22.0, -6.0]:
		_limb([Vector2(px, -18), Vector2(px - 3, -3)], 10.0, dark, 0.65)
	# jaw and fangs
	_line(Vector2(-70, -30), Vector2(-46, -25), OL, 3)
	_poly([Vector2(-66, -30), Vector2(-60, -30), Vector2(-62, -17)], BONE, false)
	_poly([Vector2(-56, -29), Vector2(-50, -29), Vector2(-52, -17)], BONE, false)
	_line(Vector2(-64, -35), Vector2(-80, -43), OL, 2)
	_line(Vector2(-64, -33), Vector2(-80, -30), OL, 2)
	_veins([
		[Vector2(-14, -52), Vector2(-8, -42), Vector2(-13, -32), Vector2(-6, -20)],
		[Vector2(14, -50), Vector2(20, -38), Vector2(15, -27), Vector2(21, -16)],
		[Vector2(-44, -45), Vector2(-53, -40), Vector2(-58, -33)],
		[Vector2(-8, -42), Vector2(4, -39)],
		[Vector2(50, -26), Vector2(58, -34), Vector2(60, -48)],
		[Vector2(-30, -32), Vector2(-22, -26)],
	])
	_rot_eye(Vector2(-49, -40), 4.2)


## E03 — a mushroom that grew limbs. The cap is the silhouette; under it is a
## stubby little thing with a worried face.
func _draw_sporecap() -> void:
	var cap := _body()
	var stem := _rot(Color("a08e9c"))
	_mist([[-30.0, -60.0, 26.0], [28.0, -62.0, 28.0]])
	for s in [-1.0, 1.0]:
		_limb([Vector2(s * 11, -17), Vector2(s * 15, -3)], 12.0, stem.darkened(0.10), 0.9)
		_limb([Vector2(s * 16, -38), Vector2(s * 29, -30)], 8.0, stem.darkened(0.06), 0.7)
	_ellipse(Vector2(0, -31), 19, 21, stem)
	# cap: domed over, flat underneath, with a lip that overhangs the stalk
	var pts := _dome_points(0.0, -44.0, 40.0, 30.0, 16)
	pts.append_array([Vector2(24, -41), Vector2(0, -43), Vector2(-24, -41)])
	_poly(pts, cap)
	for spot in [[-21.0, -57.0, 6.5], [3.0, -63.0, 7.0], [23.0, -55.0, 5.5],
			[-7.0, -51.0, 4.5]]:
		_ellipse(Vector2(float(spot[0]), float(spot[1])), float(spot[2]),
				float(spot[2]) * 0.72, cap.lightened(0.26), false)
	_veins([
		[Vector2(-7, -42), Vector2(-11, -33), Vector2(-7, -25), Vector2(-13, -18)],
		[Vector2(8, -42), Vector2(12, -32), Vector2(8, -24), Vector2(13, -17)],
		[Vector2(-28, -50), Vector2(-34, -55)],
		[Vector2(25, -48), Vector2(32, -53)],
		[Vector2(-11, -33), Vector2(-19, -31)],
		[Vector2(12, -32), Vector2(20, -33)],
	])
	_rot_eyes(Vector2(0, -34), 8, 3.8)
	_arc(Vector2(0, -21), 7, PI * 1.16, PI * 1.84, OL, 3, 10)


## E04 — a slab of walking stone. The reference has an owl's face cut into its
## front plate, which would read as the Owl Sage from two cards away, so the
## head here is small, low and slotted, and the shoulders do the talking.
func _draw_beetle() -> void:
	var stone := _body()
	var dark := stone.darkened(0.20)
	_mist([[-34.0, -56.0, 26.0], [32.0, -58.0, 28.0]])
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 5, -15), Vector2(s * 31, -12), Vector2(s * 33, -1),
				Vector2(s * 5, -2)], dark)
		_limb([Vector2(s * 16, -36), Vector2(s * 20, -14)], 17.0, stone, 0.85)
	# torso: broad at the shoulder, narrow at the hip
	_poly([Vector2(-29, -30), Vector2(-39, -56), Vector2(-21, -69), Vector2(0, -73),
			Vector2(21, -69), Vector2(39, -56), Vector2(29, -30), Vector2(0, -25)], stone)
	_line(Vector2(-25, -47), Vector2(25, -47), OL, 3)
	_line(Vector2(0, -71), Vector2(0, -27), OL, 3)
	# pauldrons, and the arms hanging out of them
	for s2 in [-1.0, 1.0]:
		_limb([Vector2(s2 * 36, -54), Vector2(s2 * 44, -34), Vector2(s2 * 38, -18)],
				14.0, dark, 0.8)
		_poly([Vector2(s2 * 20, -70), Vector2(s2 * 46, -58), Vector2(s2 * 43, -40),
				Vector2(s2 * 19, -50)], dark)
	# head, sunk between the shoulders
	_poly([Vector2(-13, -64), Vector2(-15, -80), Vector2(0, -88), Vector2(15, -80),
			Vector2(13, -64)], stone)
	_poly([Vector2(-12, -78), Vector2(12, -78), Vector2(11, -70), Vector2(-11, -70)],
			OL, false)
	_veins([
		[Vector2(-3, -66), Vector2(-9, -56), Vector2(-4, -44), Vector2(-11, -32)],
		[Vector2(7, -64), Vector2(13, -53), Vector2(8, -41), Vector2(14, -30)],
		[Vector2(-9, -56), Vector2(-21, -52)],
		[Vector2(13, -53), Vector2(25, -49)],
		[Vector2(-30, -62), Vector2(-38, -55)],
		[Vector2(30, -60), Vector2(39, -53)],
	])
	_rot_eyes(Vector2(0, -74), 6, 3.2)


## E05 — dark by nature, and so the first design that needs its edge lit.
func _draw_moth() -> void:
	var wing := _body()
	var fur := wing.darkened(0.16)
	var flap := 5.0 * floorf(fmod(_t * 4.0, 2.0))
	_mist([[-24.0, -34.0, 24.0], [22.0, -36.0, 26.0]])
	for s in [-1.0, 1.0]:
		# hind wing
		_poly([Vector2(s * 7, -32), Vector2(s * 30, -26 + flap * 0.4),
				Vector2(s * 39, -10 + flap * 0.3), Vector2(s * 21, -2),
				Vector2(s * 8, -14)], wing.darkened(0.13))
		# fore wing, swept up and out
		_poly([Vector2(s * 6, -56), Vector2(s * 26, -70 + flap),
				Vector2(s * 54, -57 + flap), Vector2(s * 45, -35 + flap * 0.5),
				Vector2(s * 9, -28)], wing)
		_veins([
			[Vector2(s * 11, -50), Vector2(s * 27, -58 + flap * 0.8),
					Vector2(s * 44, -56 + flap * 0.8)],
			[Vector2(s * 11, -44), Vector2(s * 29, -46 + flap * 0.6),
					Vector2(s * 43, -42 + flap * 0.5)],
			[Vector2(s * 10, -36), Vector2(s * 25, -30 + flap * 0.3),
					Vector2(s * 32, -14 + flap * 0.2)],
		])
		_rim([Vector2(s * 6, -56), Vector2(s * 26, -70 + flap),
				Vector2(s * 54, -57 + flap)], 3.0, 0.66)
		_line(Vector2(s * 4, -66), Vector2(s * 14, -80), OL, 2)
	_ellipse(Vector2(0, -42), 10, 20, fur)
	_ellipse(Vector2(0, -54), 14, 7, fur.lightened(0.16), false)
	_circle(Vector2(0, -63), 9, fur)
	_rim([Vector2(-8, -67), Vector2(0, -72), Vector2(8, -67)], 3.0, 0.6)
	_rot_eyes(Vector2(0, -63), 5, 3.2)


## E06 — the one design in the sheet with no face at all: a knot of thorned
## runners. It still has to look at you, so a single lit pair sits deep in the
## middle of the tangle where it pulls tightest.
func _draw_vine() -> void:
	var v := _body()
	var dark := v.darkened(0.22)
	_mist([[-22.0, -64.0, 26.0], [24.0, -68.0, 28.0]])
	# three runners out of the ground, each curling back on itself
	# Three runners, each a long gentle S. Tight zigzags were what made this one
	# read as a pile of splinters: a vine has to bend, not fold.
	_limb([Vector2(-8, -2), Vector2(-18, -26), Vector2(-8, -50), Vector2(-24, -68),
			Vector2(-2, -78), Vector2(16, -66)], 13.0, v, 0.42)
	_limb([Vector2(16, -2), Vector2(26, -28), Vector2(12, -50), Vector2(28, -64),
			Vector2(44, -54)], 12.0, dark, 0.42)
	_limb([Vector2(-26, -3), Vector2(-34, -28), Vector2(-22, -44), Vector2(-40, -54)],
			11.0, v.lightened(0.12), 0.44)
	# thorns: short barbs raked back along the runner they grow off
	for th in [[-15.0, -22.0, -1.0, 0.5], [-11.0, -44.0, -1.0, -0.5],
			[-20.0, -66.0, -1.0, 0.5], [23.0, -28.0, 1.0, 0.5],
			[15.0, -48.0, 1.0, -0.5], [33.0, -60.0, 1.0, 0.5],
			[-32.0, -32.0, -1.0, -0.5], [6.0, -76.0, 1.0, -0.5]]:
		var o := Vector2(float(th[0]), float(th[1]))
		var d := Vector2(float(th[2]) * 11.0, float(th[3]) * 11.0)
		_poly([o + Vector2(-d.y, d.x) * 0.26, o + d, o - Vector2(-d.y, d.x) * 0.26],
				dark, false)
	_leaf(Vector2(-30, -38), Vector2(-16, -10), 7.0, v.lightened(0.16))
	_leaf(Vector2(32, -46), Vector2(17, -9), 7.0, v.lightened(0.16))
	_veins([
		[Vector2(-13, -12), Vector2(-16, -28), Vector2(-11, -44), Vector2(-18, -60)],
		[Vector2(21, -14), Vector2(23, -32), Vector2(16, -46), Vector2(27, -58)],
		[Vector2(-16, -28), Vector2(-27, -26)],
		[Vector2(-8, -72), Vector2(4, -74)],
		[Vector2(23, -32), Vector2(34, -30)],
		[Vector2(-11, -44), Vector2(0, -46)],
	])
	_rot_eyes(Vector2(0, -52), 8, 3.8)


## E07 — half a wolf. The hide has gone off its ribs and skull, and bone is the
## one thing in the enemy palette that stayed bright.
func _draw_wolf() -> void:
	var hide := _body()
	var dark := hide.darkened(0.22)
	_mist([[-20.0, -58.0, 24.0], [24.0, -56.0, 26.0]])
	_limb([Vector2(36, -40), Vector2(54, -46), Vector2(60, -64)], 10.0, hide, 0.32)
	for lx in [-20.0, -4.0, 24.0, 38.0]:
		_limb([Vector2(lx, -34), Vector2(lx + 4.0, -18), Vector2(lx - 4.0, -2)],
				13.0, dark, 0.52)
	# barrel: deep chest at the front, waist tucked, haunch high behind
	_poly([Vector2(-32, -28), Vector2(-34, -54), Vector2(-6, -62), Vector2(20, -58),
			Vector2(40, -62), Vector2(48, -44), Vector2(42, -26), Vector2(20, -22),
			Vector2(-10, -20)], hide)
	# the ribcage: the hide is gone off the front half, so a dark cavity shows
	# through and the bone sits over it. The cavity carries this design — it is
	# the only thing keeping a pale-boned wolf from reading as a pale blob.
	_poly([Vector2(-31, -29), Vector2(-33, -55), Vector2(4, -61), Vector2(8, -22)],
			hide.darkened(0.62), false)
	for i in 3:
		_arc(Vector2(-24 + i * 12, -42), 16, PI * 0.06, PI * 0.99, BONE, 4, 9)
	_line(Vector2(-31, -58), Vector2(42, -58), BONE, 5)
	# neck and skull
	_limb([Vector2(-26, -50), Vector2(-40, -52), Vector2(-50, -52)], 18.0, hide, 0.92)
	_poly([Vector2(-40, -42), Vector2(-48, -62), Vector2(-70, -63), Vector2(-82, -50),
			Vector2(-68, -36), Vector2(-44, -34)], BONE)
	_poly([Vector2(-58, -62), Vector2(-62, -82), Vector2(-45, -62)], BONE)
	_poly([Vector2(-45, -60), Vector2(-38, -78), Vector2(-34, -56)], BONE)
	_ellipse(Vector2(-62, -50), 5, 6, OL, false)
	_line(Vector2(-81, -45), Vector2(-58, -40), OL, 3)
	_poly([Vector2(-78, -44), Vector2(-73, -44), Vector2(-75, -33)], BONE, false)
	_poly([Vector2(-67, -43), Vector2(-62, -43), Vector2(-64, -33)], BONE, false)
	_veins([
		[Vector2(22, -52), Vector2(29, -41), Vector2(23, -30), Vector2(30, -20)],
		[Vector2(-16, -19), Vector2(-12, -30), Vector2(-19, -41)],
		[Vector2(-52, -57), Vector2(-61, -56)],
		[Vector2(29, -41), Vector2(39, -38)],
		[Vector2(44, -38), Vector2(52, -43)],
		[Vector2(-30, -21), Vector2(-24, -30)],
	])
	_rot_eye(Vector2(-62, -50), 4.4)


## E08 — the other design that is dark by nature. A cowl, nothing inside it but
## the two lights, and a hem that comes apart into smoke.
func _draw_wraith() -> void:
	var robe := _body()
	_mist([[-24.0, -58.0, 30.0], [24.0, -60.0, 32.0], [0.0, -80.0, 22.0]])
	# robe: shoulders wide, hem torn into four shallow points
	_poly([Vector2(-24, -58), Vector2(-18, -74), Vector2(0, -82), Vector2(18, -74),
			Vector2(24, -58), Vector2(33, -24), Vector2(27, -3), Vector2(16, -15),
			Vector2(4, -1), Vector2(-8, -15), Vector2(-20, -3), Vector2(-31, -22)],
			robe)
	# cowl
	_poly([Vector2(-21, -60), Vector2(-17, -77), Vector2(0, -85), Vector2(17, -77),
			Vector2(21, -60), Vector2(10, -53), Vector2(-10, -53)], robe.darkened(0.12))
	_ellipse(Vector2(0, -66), 12, 11, robe.darkened(0.56), false)
	_rim([Vector2(-21, -60), Vector2(-17, -77), Vector2(0, -85), Vector2(17, -77),
			Vector2(21, -60)], 3.5, 0.88)
	# sleeves, held out in front, ending in three long fingers
	for s in [-1.0, 1.0]:
		_limb([Vector2(s * 20, -62), Vector2(s * 34, -53), Vector2(s * 37, -39)],
				11.0, robe.darkened(0.16), 0.62)
		for k in 3:
			_line(Vector2(s * 37, -38), Vector2(s * (35 + k * 5), -25 + k * 2),
					robe.lightened(0.26), 3)
	_veins([
		[Vector2(-7, -54), Vector2(-12, -42), Vector2(-7, -30), Vector2(-14, -18)],
		[Vector2(8, -54), Vector2(13, -42), Vector2(8, -30), Vector2(15, -17)],
		[Vector2(-12, -42), Vector2(-23, -38)],
		[Vector2(13, -42), Vector2(25, -39)],
		[Vector2(0, -50), Vector2(2, -36)],
		[Vector2(-27, -50), Vector2(-33, -44)],
	])
	_rot_eyes(Vector2(0, -67), 6, 3.6)


## E09 — squat, heavy, and cracked open on something molten. The heat keeps its
## own colour: orange is the toad's, magenta is still the rot's.
func _draw_toad() -> void:
	var hide := _body()
	var dark := hide.darkened(0.18)
	_mist([[-32.0, -44.0, 24.0], [30.0, -46.0, 26.0]])
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 14, -15), Vector2(s * 43, -11), Vector2(s * 45, -1),
				Vector2(s * 14, -2)], dark)
	var pts := _dome_points(0.0, -5.0, 44.0, 45.0, 18)
	pts.append_array([Vector2(30, -2), Vector2(0, -7), Vector2(-30, -2)])
	_poly(pts, hide)
	_cracks([
		[Vector2(-28, -40), Vector2(-21, -31), Vector2(-26, -21), Vector2(-19, -12)],
		[Vector2(-21, -31), Vector2(-8, -28), Vector2(0, -18)],
		[Vector2(12, -42), Vector2(16, -32), Vector2(28, -26), Vector2(32, -16)],
		[Vector2(16, -32), Vector2(6, -25)],
	], EMBER, 2.6, 1.0, 0.9)
	# a wide, flat, unamused mouth, then the eye bumps sat on top of the head
	_arc(Vector2(0, -72), 46, 0.78, PI - 0.78, OL, 4, 16)
	for s2 in [-1.0, 1.0]:
		_circle(Vector2(s2 * 18, -50), 11, hide)
	_rot_eyes(Vector2(0, -51), 18, 4.5)
	_veins([
		[Vector2(-34, -38), Vector2(-40, -30), Vector2(-37, -22)],
		[Vector2(33, -37), Vector2(40, -29), Vector2(38, -20)],
		[Vector2(-11, -50), Vector2(-16, -44)],
	])


## E10 — one body, two heads, and the coil is the whole silhouette.
func _draw_viper() -> void:
	var scale := _body()
	_mist([[-26.0, -56.0, 26.0], [26.0, -60.0, 28.0]])
	# tail tip, poking out from under the bottom loop
	_limb([Vector2(30, -16), Vector2(50, -24), Vector2(58, -42)], 11.0, scale, 0.26)
	# the coil: three loops, each set back and to the side of the one below, so
	# it reads as one rope wound up rather than as three stacked plates
	_ellipse(Vector2(-2, -15), 41, 16, scale)
	_ellipse(Vector2(10, -34), 33, 15, scale.lightened(0.08))
	_ellipse(Vector2(-6, -51), 24, 14, scale)
	for i in 5:
		_line(Vector2(-28 + i * 13, -5), Vector2(-27 + i * 13, -23),
				scale.lightened(0.24), 3)
	# two necks out of the top loop, and two heads
	for s in [-1.0, 1.0]:
		_limb([Vector2(s * 4, -58), Vector2(s * 16, -70), Vector2(s * 30, -86)],
				15.0, scale, 0.8)
		_poly([Vector2(s * 30 - 14, -89), Vector2(s * 30 - 4, -101),
				Vector2(s * 30 + 13, -99), Vector2(s * 30 + 17, -86),
				Vector2(s * 30 + 2, -81)], scale)
		_line(Vector2(s * 30 + 17, -90), Vector2(s * 30 + 32, -88), Color("d94f4f"), 2.5)
		_line(Vector2(s * 30 + 27, -89), Vector2(s * 30 + 34, -95), Color("d94f4f"), 2.5)
		_rot_eye(Vector2(s * 30 + 5, -93), 4)
	_veins([
		[Vector2(-24, -14), Vector2(-8, -19), Vector2(10, -14), Vector2(25, -19)],
		[Vector2(-20, -33), Vector2(-2, -38), Vector2(17, -32), Vector2(32, -37)],
		[Vector2(-19, -50), Vector2(-3, -55), Vector2(15, -49)],
		[Vector2(-8, -19), Vector2(-12, -29)],
		[Vector2(-2, -38), Vector2(0, -47)],
		[Vector2(48, -28), Vector2(54, -38)],
	])


# ============================================================ bosses
#
# Bosses run at full corruption always — the mist never lifts off them — and
# they are authored well above the 140-unit minion box, so a boss card is
# unmistakably the biggest thing on the screen.

## B1 — the one that hits you with a tree. Heavy through the shoulders, one ear
## folded over, club carried back across the far shoulder.
func _draw_basher_bunny() -> void:
	var fur := _body()
	var dark := fur.darkened(0.18)
	var inner := _rot(Color("a8788f"))
	_mist([[46.0, -108.0, 50.0], [-48.0, -96.0, 42.0], [60.0, -76.0, 38.0],
			[-30.0, -134.0, 32.0], [32.0, -138.0, 34.0]])
	# ---- club: a whole young tree, gripped low on the near side and carried up
	# ---- across the far shoulder. Routed high on purpose — on the first pass it
	# ---- ran through the torso and all you could see was the handle.
	_limb([Vector2(-56, -50), Vector2(4, -104), Vector2(78, -158)], 21.0, WOOD, 1.25)
	for sp in [[16.0, -116.0], [38.0, -132.0], [60.0, -148.0], [-4.0, -100.0]]:
		_poly([Vector2(float(sp[0]) - 11, float(sp[1]) - 2),
				Vector2(float(sp[0]) + 2, float(sp[1]) - 24),
				Vector2(float(sp[0]) + 10, float(sp[1]) - 6)], STEEL.darkened(0.28))
	_line(Vector2(-36, -66), Vector2(46, -128), WOOD.darkened(0.22), 3)
	# ---- stance
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 9, -17), Vector2(s * 47, -14), Vector2(s * 49, -1),
				Vector2(s * 9, -2)], dark)
		_limb([Vector2(s * 25, -68), Vector2(s * 33, -42), Vector2(s * 25, -17)],
				34.0, fur, 0.58)
	# ---- torso
	_poly([Vector2(-42, -36), Vector2(-51, -76), Vector2(-36, -106), Vector2(0, -117),
			Vector2(36, -106), Vector2(51, -76), Vector2(44, -36), Vector2(0, -28)], fur)
	_ellipse(Vector2(0, -62), 25, 30, fur.lightened(0.13))
	# ---- arms: the near one down on the haft, the far one up under the head of
	# ---- the club where it crosses the shoulder
	_limb([Vector2(-38, -98), Vector2(-64, -78), Vector2(-56, -56)], 25.0, dark, 0.7)
	_circle(Vector2(-54, -48), 16, dark)
	_limb([Vector2(38, -100), Vector2(56, -110), Vector2(44, -124)], 25.0, dark, 0.7)
	_circle(Vector2(40, -132), 15, dark)
	# ---- head
	_circle(Vector2(0, -136), 31, fur)
	_ellipse(Vector2(0, -125), 17, 11, fur.lightened(0.15), false)
	_circle(Vector2(0, -129), 4, OL, false)
	_line(Vector2(0, -125), Vector2(0, -117), OL, 3)
	# ears: one up, one folded, each with a lighter inner
	_poly([Vector2(5, -156), Vector2(11, -200), Vector2(31, -195), Vector2(25, -152)], fur)
	_poly([Vector2(10, -160), Vector2(15, -191), Vector2(25, -188), Vector2(21, -157)],
			inner, false)
	_poly([Vector2(-9, -154), Vector2(-33, -187), Vector2(-60, -182),
			Vector2(-45, -166), Vector2(-20, -149)], fur)
	_poly([Vector2(-16, -157), Vector2(-34, -180), Vector2(-51, -178),
			Vector2(-38, -166), Vector2(-22, -154)], inner, false)
	_rim([Vector2(-27, -148), Vector2(-20, -170), Vector2(0, -182), Vector2(20, -174)],
			3.5, 0.55)
	for s3 in [-1.0, 1.0]:
		_line(Vector2(s3 * 23, -148), Vector2(s3 * 9, -140), OL, 4)
	_rot_eyes(Vector2(0, -136), 14, 5.5)
	_veins([
		[Vector2(-5, -110), Vector2(-13, -92), Vector2(-6, -70), Vector2(-15, -48),
				Vector2(-9, -32)],
		[Vector2(7, -110), Vector2(17, -90), Vector2(10, -66), Vector2(20, -44)],
		[Vector2(-13, -92), Vector2(-30, -86), Vector2(-40, -78)],
		[Vector2(17, -90), Vector2(35, -84), Vector2(45, -76)],
		[Vector2(-48, -80), Vector2(-56, -68), Vector2(-47, -58)],
		[Vector2(50, -82), Vector2(57, -70), Vector2(45, -62)],
		[Vector2(12, -158), Vector2(19, -176), Vector2(17, -192)],
		[Vector2(-17, -156), Vector2(-33, -172), Vector2(-49, -178)],
		[Vector2(-4, -148), Vector2(2, -132)],
		[Vector2(-27, -40), Vector2(-33, -22)],
	])


## B2 — B1's build with the club traded for a pair of gloves and a boxer's
## guard: lead hand up and out, rear hand cocked across the chest.
func _draw_boxer_hare() -> void:
	var fur := _body()
	var dark := fur.darkened(0.18)
	var inner := _rot(Color("a8788f"))
	var glove := _rot(Color("bc5340"))
	_mist([[48.0, -100.0, 46.0], [-50.0, -92.0, 40.0], [36.0, -136.0, 36.0],
			[-32.0, -132.0, 32.0], [58.0, -70.0, 32.0]])
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 9, -17), Vector2(s * 47, -14), Vector2(s * 49, -1),
				Vector2(s * 9, -2)], dark)
		_limb([Vector2(s * 25, -68), Vector2(s * 33, -42), Vector2(s * 25, -17)],
				34.0, fur, 0.58)
	_poly([Vector2(-42, -36), Vector2(-51, -76), Vector2(-36, -106), Vector2(0, -117),
			Vector2(36, -106), Vector2(51, -76), Vector2(44, -36), Vector2(0, -28)], fur)
	_ellipse(Vector2(0, -62), 25, 30, fur.lightened(0.13))
	# lead arm, thrown out clear of the body so the glove reads as held and not
	# as pinned on
	_limb([Vector2(-38, -100), Vector2(-64, -92), Vector2(-76, -76)], 23.0, dark, 0.8)
	_line(Vector2(-88, -72), Vector2(-64, -64), glove.darkened(0.30), 8)
	_circle(Vector2(-84, -56), 21, glove)
	_arc(Vector2(-84, -56), 13, PI * 0.9, PI * 1.5, glove.darkened(0.26), 4, 8)
	# rear arm, cocked in across the chest
	_limb([Vector2(38, -98), Vector2(56, -84), Vector2(38, -72)], 23.0, dark, 0.8)
	_line(Vector2(30, -84), Vector2(24, -60), glove.darkened(0.30), 8)
	_circle(Vector2(14, -68), 21, glove)
	_arc(Vector2(14, -68), 13, PI * 1.4, TAU, glove.darkened(0.26), 4, 8)
	_circle(Vector2(0, -136), 31, fur)
	_ellipse(Vector2(0, -125), 17, 11, fur.lightened(0.15), false)
	_circle(Vector2(0, -129), 4, OL, false)
	_line(Vector2(0, -125), Vector2(0, -117), OL, 3)
	_poly([Vector2(3, -156), Vector2(6, -202), Vector2(26, -198), Vector2(23, -152)], fur)
	_poly([Vector2(8, -160), Vector2(11, -193), Vector2(21, -191), Vector2(19, -157)],
			inner, false)
	_poly([Vector2(-9, -154), Vector2(-31, -189), Vector2(-58, -186),
			Vector2(-43, -169), Vector2(-20, -149)], fur)
	_poly([Vector2(-16, -157), Vector2(-32, -182), Vector2(-49, -181),
			Vector2(-36, -169), Vector2(-22, -154)], inner, false)
	_rim([Vector2(-27, -148), Vector2(-20, -170), Vector2(0, -182), Vector2(18, -176)],
			3.5, 0.55)
	for s2 in [-1.0, 1.0]:
		_line(Vector2(s2 * 23, -148), Vector2(s2 * 9, -140), OL, 4)
	_rot_eyes(Vector2(0, -136), 14, 5.5)
	_veins([
		[Vector2(-5, -110), Vector2(-13, -92), Vector2(-6, -70), Vector2(-15, -48),
				Vector2(-9, -32)],
		[Vector2(7, -110), Vector2(17, -90), Vector2(10, -66), Vector2(20, -44)],
		[Vector2(-13, -92), Vector2(-30, -86), Vector2(-42, -84)],
		[Vector2(17, -90), Vector2(35, -84), Vector2(45, -80)],
		[Vector2(-46, -94), Vector2(-56, -84)],
		[Vector2(44, -88), Vector2(52, -78)],
		[Vector2(9, -158), Vector2(15, -178), Vector2(13, -194)],
		[Vector2(-17, -156), Vector2(-31, -174), Vector2(-47, -182)],
		[Vector2(-4, -148), Vector2(2, -132)],
		[Vector2(29, -40), Vector2(35, -22)],
	])


## B3 phase 1 — the knight is the small half of this design. The goose is what
## fills the card: wings out, neck up, an armoured frog sat between them.
func _draw_sir_croak() -> void:
	var goose := _body()
	var wing := goose.darkened(0.18)
	var frog := _rot(Color("8c9e7a"))
	# the rider is deliberately a lighter steel than the bird he sits on: at
	# card size the two masses have to separate on tone, not only on outline
	var plate := _rot(Color("b6b0c2"))
	var web := _rot(Color("c08a52"))
	_mist([[52.0, -100.0, 40.0], [-52.0, -86.0, 34.0], [14.0, -142.0, 32.0]])
	# ---- wings, thrown open behind the bird: a long curved leading edge and
	# ---- four feather tips off the back of it
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 26, -78), Vector2(s * 50, -108), Vector2(s * 78, -116),
				Vector2(s * 92, -100), Vector2(s * 82, -93), Vector2(s * 89, -85),
				Vector2(s * 74, -79), Vector2(s * 78, -70), Vector2(s * 56, -64),
				Vector2(s * 34, -56)], wing)
		for k in 4:
			_line(Vector2(s * (40 + k * 14), -92 + k * 3),
					Vector2(s * (48 + k * 14), -74 + k * 4), OL, 2.5)
	# ---- legs and webbed feet
	for s2 in [-1.0, 1.0]:
		_limb([Vector2(s2 * 16, -34), Vector2(s2 * 20, -13)], 9.0, web, 0.9)
		_poly([Vector2(s2 * 5, -13), Vector2(s2 * 38, -9), Vector2(s2 * 36, -1),
				Vector2(s2 * 7, -2)], web)
	# ---- goose body: one long low hull, breast leading, tail cocked up behind
	_poly([Vector2(-58, -50), Vector2(-54, -66), Vector2(-30, -78), Vector2(12, -80),
			Vector2(46, -72), Vector2(72, -86), Vector2(80, -70), Vector2(56, -48),
			Vector2(16, -32), Vector2(-30, -34)], goose)
	_ellipse(Vector2(-22, -52), 22, 12, goose.lightened(0.16), false)
	# ---- neck and head: a goose's neck comes up and then forward and DOWN, and
	# ---- the head has to sit well under the rider's or the two read as one body
	_limb([Vector2(-46, -62), Vector2(-64, -82), Vector2(-74, -102)], 15.0, goose, 0.66)
	_poly([Vector2(-88, -102), Vector2(-82, -118), Vector2(-64, -117),
			Vector2(-60, -101), Vector2(-74, -94)], goose)
	_poly([Vector2(-88, -108), Vector2(-106, -103), Vector2(-88, -96)], web)
	_rot_eye(Vector2(-73, -109), 4.2)
	# ---- the rider, sat astride the back
	_poly([Vector2(-3, -82), Vector2(-7, -112), Vector2(12, -124), Vector2(31, -112),
			Vector2(29, -82), Vector2(12, -76)], plate)
	_line(Vector2(-4, -98), Vector2(29, -98), OL, 3)
	_line(Vector2(12, -123), Vector2(12, -80), OL, 3)
	for s3 in [-1.0, 1.0]:
		_poly([Vector2(12 + s3 * 13, -115), Vector2(12 + s3 * 34, -107),
				Vector2(12 + s3 * 30, -93), Vector2(12 + s3 * 11, -100)],
				plate.darkened(0.22))
		_limb([Vector2(12 + s3 * 28, -100), Vector2(12 + s3 * 34, -86)], 11.0,
				plate.darkened(0.30), 0.85)
	_circle(Vector2(12, -139), 17, frog)
	_circle(Vector2(1, -152), 8, frog)
	_circle(Vector2(23, -152), 8, frog)
	_rot_eyes(Vector2(12, -152), 11, 4.2)
	_arc(Vector2(12, -135), 12, 0.30, PI - 0.30, OL, 3, 10)
	_rim([Vector2(-7, -112), Vector2(12, -124), Vector2(31, -112)], 3.0, 0.5)
	# ---- sword, held down along the far flank
	_limb([Vector2(46, -98), Vector2(84, -46)], 8.0, STEEL, 0.5)
	_line(Vector2(38, -94), Vector2(56, -102), WOOD, 5)
	_veins([
		[Vector2(-30, -68), Vector2(-18, -56), Vector2(-28, -42)],
		[Vector2(26, -70), Vector2(38, -58), Vector2(28, -44)],
		[Vector2(-18, -56), Vector2(2, -50)],
		[Vector2(-52, -66), Vector2(-60, -78), Vector2(-68, -94)],
		[Vector2(52, -96), Vector2(72, -94)],
		[Vector2(-46, -90), Vector2(-62, -96)],
		[Vector2(8, -108), Vector2(16, -90)],
		[Vector2(4, -144), Vector2(14, -140)],
	])


## B3 phase 2 — the goose is down and the knight is on his own feet: same
## armour, same head, now upright with the sword raised. Deliberately narrower
## and taller than phase 1, so the card visibly changes shape when he dismounts.
func _draw_sir_croak_afoot() -> void:
	var plate := _body()
	var dark := plate.darkened(0.22)
	var frog := _rot(Color("8c9e7a"))
	_mist([[36.0, -88.0, 42.0], [-36.0, -80.0, 38.0], [8.0, -122.0, 34.0]])
	for s in [-1.0, 1.0]:
		_limb([Vector2(s * 15, -60), Vector2(s * 21, -32), Vector2(s * 17, -9)],
				21.0, dark, 0.78)
		_poly([Vector2(s * 4, -13), Vector2(s * 33, -9), Vector2(s * 31, -1),
				Vector2(s * 6, -2)], frog.darkened(0.14))
	_poly([Vector2(-26, -54), Vector2(-31, -94), Vector2(0, -107), Vector2(31, -94),
			Vector2(26, -54), Vector2(0, -46)], plate)
	_line(Vector2(-25, -78), Vector2(25, -78), OL, 3)
	_line(Vector2(0, -105), Vector2(0, -50), OL, 3)
	for s2 in [-1.0, 1.0]:
		_poly([Vector2(s2 * 22, -98), Vector2(s2 * 45, -88), Vector2(s2 * 41, -71),
				Vector2(s2 * 20, -79)], dark)
	# shield arm
	_limb([Vector2(-36, -82), Vector2(-49, -62), Vector2(-41, -45)], 13.0, dark, 0.8)
	_poly([Vector2(-64, -76), Vector2(-38, -78), Vector2(-36, -41), Vector2(-51, -28),
			Vector2(-66, -43)], STEEL.darkened(0.28))
	_circle(Vector2(-51, -57), 7, STEEL, false)
	# sword arm, blade up
	_limb([Vector2(36, -86), Vector2(50, -72)], 13.0, dark, 0.8)
	_limb([Vector2(52, -76), Vector2(46, -146)], 8.0, STEEL, 0.4)
	_line(Vector2(40, -80), Vector2(62, -76), WOOD, 6)
	_circle(Vector2(0, -123), 18, frog)
	_circle(Vector2(-12, -138), 8, frog)
	_circle(Vector2(12, -138), 8, frog)
	_rot_eyes(Vector2(0, -138), 12, 4.2)
	_arc(Vector2(0, -119), 13, 0.30, PI - 0.30, OL, 3, 10)
	_rim([Vector2(-31, -94), Vector2(0, -107), Vector2(31, -94)], 3.0, 0.5)
	_veins([
		[Vector2(-8, -102), Vector2(-15, -80), Vector2(-8, -58), Vector2(-17, -36)],
		[Vector2(8, -102), Vector2(17, -80), Vector2(10, -56), Vector2(19, -34)],
		[Vector2(-15, -80), Vector2(-29, -74)],
		[Vector2(17, -80), Vector2(31, -76)],
		[Vector2(-38, -86), Vector2(-53, -80)],
		[Vector2(38, -90), Vector2(49, -82)],
		[Vector2(-10, -131), Vector2(0, -127)],
	])


## B4 — an upright cat with a fish skeleton for a sword: tail fin at the low
## end, ribs shortening towards both ends, the fish's own skull at the point.
func _draw_fishbone_cat() -> void:
	var fur := _body()
	var dark := fur.darkened(0.18)
	_mist([[-42.0, -94.0, 40.0], [42.0, -100.0, 42.0], [-18.0, -128.0, 32.0],
			[26.0, -130.0, 32.0]])
	_limb([Vector2(34, -42), Vector2(58, -48), Vector2(71, -68), Vector2(59, -88)],
			13.0, fur, 0.5)
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 9, -15), Vector2(s * 41, -12), Vector2(s * 43, -1),
				Vector2(s * 9, -2)], dark)
		_limb([Vector2(s * 21, -60), Vector2(s * 27, -36), Vector2(s * 21, -15)],
				28.0, fur, 0.68)
	_poly([Vector2(-36, -30), Vector2(-45, -68), Vector2(-32, -96), Vector2(0, -107),
			Vector2(32, -96), Vector2(45, -68), Vector2(38, -30), Vector2(0, -22)], fur)
	_ellipse(Vector2(0, -54), 22, 26, fur.lightened(0.13))
	_limb([Vector2(-38, -88), Vector2(-56, -68), Vector2(-46, -48)], 19.0, dark, 0.78)
	_limb([Vector2(34, -90), Vector2(52, -76), Vector2(46, -57)], 19.0, dark, 0.78)
	# ---- the fishbone blade
	var a := Vector2(-56, -30)
	var b := Vector2(58, -114)
	var n := (b - a).normalized().orthogonal()
	_limb([a, b], 5.0, BONE.darkened(0.20), 1.0)
	for k in 11:
		var f := float(k) / 10.0
		var p := a.lerp(b, f)
		var span := 17.0 * sin(PI * minf(f * 1.06, 1.0))
		_line(p, p + n * span, BONE, 3)
		_line(p, p - n * span, BONE, 3)
	_leaf(a, Vector2(-22, 6), 11.0, BONE)
	_poly([b + Vector2(-9, 7), b + Vector2(15, -12), b + Vector2(3, 11)], BONE)
	# ---- head
	_circle(Vector2(-4, -124), 25, fur)
	_poly([Vector2(-26, -138), Vector2(-33, -164), Vector2(-10, -146)], fur)
	_poly([Vector2(14, -138), Vector2(23, -164), Vector2(0, -146)], fur)
	_rim([Vector2(-28, -136), Vector2(-20, -150), Vector2(-4, -154)], 3.0, 0.5)
	_ellipse(Vector2(-4, -114), 14, 9, fur.lightened(0.14), false)
	_circle(Vector2(-4, -117), 4, OL, false)
	for s2 in [-1.0, 1.0]:
		_line(Vector2(-4 + s2 * 22, -134), Vector2(-4 + s2 * 8, -128), OL, 4)
	_rot_eyes(Vector2(-4, -124), 12, 5)
	_veins([
		[Vector2(-8, -100), Vector2(-17, -80), Vector2(-9, -58), Vector2(-18, -36)],
		[Vector2(6, -100), Vector2(16, -78), Vector2(9, -56), Vector2(18, -34)],
		[Vector2(-17, -80), Vector2(-34, -74)],
		[Vector2(16, -78), Vector2(36, -72)],
		[Vector2(-46, -76), Vector2(-54, -62)],
		[Vector2(46, -80), Vector2(54, -68)],
		[Vector2(-19, -138), Vector2(-27, -154)],
		[Vector2(58, -58), Vector2(68, -70)],
		[Vector2(-4, -142), Vector2(2, -130)],
	])


## B5 — full plate over a cat, an oversized notched greatsword laid back on the
## shoulder, and the only magenta in the game that is engraved rather than
## cracked: this one went and asked for it.
func _draw_purrceval() -> void:
	var plate := _body()
	var dark := plate.darkened(0.24)
	_mist([[-44.0, -96.0, 40.0], [46.0, -102.0, 42.0], [-22.0, -132.0, 30.0],
			[28.0, -134.0, 32.0]])
	_limb([Vector2(36, -36), Vector2(60, -42), Vector2(72, -62), Vector2(60, -82)],
			12.0, dark, 0.5)
	# ---- greatsword
	_poly([Vector2(14, -100), Vector2(32, -116), Vector2(84, -156), Vector2(95, -141),
			Vector2(43, -101), Vector2(25, -88)], STEEL.darkened(0.22))
	_cracks([
		[Vector2(30, -104), Vector2(52, -120), Vector2(78, -140)],
		[Vector2(46, -116), Vector2(43, -127)],
		[Vector2(62, -128), Vector2(67, -117)],
	], UITheme.ROT_VEIN, 2.6, 1.0, 1.0)
	_limb([Vector2(18, -96), Vector2(-34, -58)], 6.0, WOOD, 0.8)
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 7, -17), Vector2(s * 41, -13), Vector2(s * 43, -1),
				Vector2(s * 7, -2)], dark)
		_limb([Vector2(s * 21, -64), Vector2(s * 27, -38), Vector2(s * 21, -17)],
				27.0, plate, 0.72)
		_poly([Vector2(s * 7, -68), Vector2(s * 35, -62), Vector2(s * 33, -45),
				Vector2(s * 7, -50)], dark)
	_poly([Vector2(-34, -58), Vector2(-43, -96), Vector2(0, -111), Vector2(43, -96),
			Vector2(34, -58), Vector2(0, -50)], plate)
	_line(Vector2(-30, -80), Vector2(30, -80), OL, 3)
	_line(Vector2(0, -110), Vector2(0, -52), OL, 3)
	_poly([Vector2(-33, -58), Vector2(33, -58), Vector2(31, -45), Vector2(-31, -45)], dark)
	for s2 in [-1.0, 1.0]:
		_poly([Vector2(s2 * 26, -103), Vector2(s2 * 53, -92), Vector2(s2 * 49, -71),
				Vector2(s2 * 24, -82)], dark)
		_rot_eye(Vector2(s2 * 39, -86), 3.6)
	_circle(Vector2(-36, -56), 13, dark)
	# ---- helm
	_circle(Vector2(0, -127), 24, plate)
	_poly([Vector2(-20, -143), Vector2(-27, -170), Vector2(-4, -147)], plate)
	_poly([Vector2(20, -143), Vector2(27, -170), Vector2(4, -147)], plate)
	_rim([Vector2(-25, -137), Vector2(-14, -149), Vector2(4, -151)], 3.0, 0.55)
	_poly([Vector2(-19, -131), Vector2(19, -131), Vector2(17, -119), Vector2(-17, -119)],
			OL, false)
	_rot_eyes(Vector2(0, -125), 10, 4.6)
	_line(Vector2(0, -119), Vector2(0, -105), OL, 3)
	_veins([
		[Vector2(-6, -107), Vector2(-13, -86), Vector2(-6, -64), Vector2(-15, -48)],
		[Vector2(6, -107), Vector2(15, -84), Vector2(8, -62), Vector2(17, -46)],
		[Vector2(-13, -86), Vector2(-31, -80)],
		[Vector2(15, -84), Vector2(33, -78)],
		[Vector2(-24, -144), Vector2(-31, -160)],
		[Vector2(-41, -70), Vector2(-49, -58)],
		[Vector2(43, -72), Vector2(51, -60)],
		[Vector2(-19, -42), Vector2(-25, -24)],
		[Vector2(21, -40), Vector2(27, -22)],
	])


## B6 — hunched, robed, hatted, and the only thing in the game that is visibly
## casting: a lit ring of runes turns around him.
func _draw_croakomancer() -> void:
	var robe := _body()
	var frog := _rot(Color("8c9e7a"))
	var hat := robe.darkened(0.22)
	_mist([[-42.0, -100.0, 42.0], [44.0, -104.0, 44.0], [-16.0, -146.0, 34.0],
			[24.0, -148.0, 32.0]])
	for s in [-1.0, 1.0]:
		_poly([Vector2(s * 6, -13), Vector2(s * 35, -10), Vector2(s * 33, -1),
				Vector2(s * 6, -2)], frog.darkened(0.16))
	# ---- robe, wide at the hem and torn along it
	_poly([Vector2(-34, -100), Vector2(34, -100), Vector2(53, -32), Vector2(47, -8),
			Vector2(31, -19), Vector2(15, -6), Vector2(-2, -19), Vector2(-19, -6),
			Vector2(-35, -17), Vector2(-51, -8), Vector2(-53, -32)], robe)
	_limb([Vector2(-41, -42), Vector2(0, -50), Vector2(43, -42)], 8.0,
			robe.darkened(0.28), 1.0)
	# ---- sleeves
	_limb([Vector2(-30, -92), Vector2(-53, -78), Vector2(-58, -58)], 18.0,
			robe.darkened(0.13), 0.66)
	_limb([Vector2(32, -92), Vector2(51, -74), Vector2(47, -54)], 18.0,
			robe.darkened(0.13), 0.66)
	for k in 3:
		_line(Vector2(47, -52), Vector2(53 + k * 4, -40 + k * 4), frog, 3)
	# ---- head
	_circle(Vector2(0, -118), 26, frog)
	_circle(Vector2(-15, -138), 11, frog)
	_circle(Vector2(15, -138), 11, frog)
	_rot_eyes(Vector2(0, -138), 15, 5.5)
	_arc(Vector2(0, -112), 17, 0.28, PI - 0.28, OL, 3.5, 12)
	# ---- hat: wide brim, long point flopping forward
	_poly([Vector2(-44, -144), Vector2(44, -144), Vector2(35, -155), Vector2(-35, -155)],
			hat)
	_poly([Vector2(-27, -153), Vector2(27, -153), Vector2(36, -190),
			Vector2(56, -211), Vector2(32, -206), Vector2(13, -182)], hat)
	_rim([Vector2(-27, -155), Vector2(0, -161), Vector2(25, -175), Vector2(43, -201)],
			3.0, 0.55)
	# ---- staff
	_limb([Vector2(-58, -8), Vector2(-64, -84), Vector2(-60, -154)], 7.0, WOOD, 0.9)
	draw_circle(_c(Vector2(-60, -166)), 16,
			Color(UITheme.ROT_EYE.r, UITheme.ROT_EYE.g, UITheme.ROT_EYE.b, 0.22))
	_poly([Vector2(-72, -162), Vector2(-60, -183), Vector2(-48, -162),
			Vector2(-60, -152)], UITheme.ROT_VEIN)
	# ---- the rune ring, turning: two frames, stepped with the idle
	var spin := floorf(fmod(_t * 2.2 + _bob_seed, 2.0)) * 0.45
	for k2 in 7:
		var ang: float = TAU * (float(k2) / 7.0) + spin
		var p := Vector2(0, -64) + Vector2(cos(ang) * 64.0, sin(ang) * 21.0)
		_line(p + Vector2(-4, 4), p + Vector2(4, -4), UITheme.ROT_VEIN, 2.5)
		_line(p + Vector2(-3, -3), p + Vector2(3, 3), UITheme.ROT_VEIN, 2.5)
	_veins([
		[Vector2(-9, -96), Vector2(-17, -74), Vector2(-10, -50), Vector2(-21, -26)],
		[Vector2(9, -96), Vector2(19, -74), Vector2(12, -48), Vector2(23, -24)],
		[Vector2(-17, -74), Vector2(-35, -68)],
		[Vector2(19, -74), Vector2(39, -68)],
		[Vector2(-14, -126), Vector2(-4, -120)],
		[Vector2(-4, -150), Vector2(9, -166), Vector2(26, -186)],
		[Vector2(-48, -82), Vector2(-56, -70)],
		[Vector2(44, -84), Vector2(52, -72)],
		[Vector2(-32, -32), Vector2(-42, -18)],
	])
