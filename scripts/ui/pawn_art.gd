class_name PawnArt
extends Node2D
## Character art. Origin is at the feet; art is drawn upward (negative y).
## Idle = 2-frame stepped bob.
##
## Every pawn in the game is a painted plate. The six heroes were cut off their
## background by `tools/art_cutout.py` into `assets/heroes/`; the ten minions and
## seven boss forms were cut off the reference sheets by `tools/enemy_cutout.py`
## into `assets/enemies/`. Both sides come down one path — `plate()` and a single
## `draw_texture_rect` — so callers never branch on which one they are placing.
##
## Nothing in this file draws a creature's shape, and a missing plate draws
## nothing at all rather than falling back to something. That is the point of
## the file, not an accident of it: a fallback that reached a drawing routine
## would be the back door the rule exists to close.
##
## ── The two sides ────────────────────────────────────────────────
## Heroes are warm forest colours and are drawn exactly as painted. Everything
## hostile gets a second pass — `assets/shaders/rot_pawn.gdshader` — which lights
## the eyes, the cracks and the lava the illustration already put down, and lays
## a rim inside the silhouette so a dark body cannot sink into a dark card.
## Magenta belongs to the enemy and to nothing else in the game — see
## `UITheme.is_magenta`.
##
## ── Tiers ────────────────────────────────────────────────────────
## The same minion is fought in all three chapters, and the chapter is its tier.
## Tier is meant to be drawn, not just tabulated: a T1 minion should read as a
## smaller animal with dim eyes and no smoke, a T3 one as bigger and alight
## along whatever eyes and cracks its `rot_mask_texture` carries. Five dials
## move together — body scale (`TIER_BULK`), eye glow (`EYE_GAIN`), crack glow
## (`VEIN_GAIN`), the mist (`MIST_COUNT`), and the rim (`UITheme.rot_rim_for`,
## the one dial keyed to the chapter's card instead of the creature) — which is
## what is meant to make the three tiers read apart at a glance rather than
## needing a side-by-side. Bosses have no tier of their own — `battle_core`
## files them under the chapter they are met in — and they are always all the
## way gone, so they run the top row of every dial.
##
## That intent is only as good as each plate's mask: eight of the seventeen
## sprites (the sheet-sourced minions — see `task-2-report.md`'s `PENDING_ART`
## table) have thin or empty eye/vein masks and are awaiting replacement art,
## so the eye-glow/crack-glow half of the dial is muted or absent on them
## today. `EYE_GAIN`/`VEIN_GAIN` must not be raised to compensate — that would
## overcorrect the nine plates that already have real masks.

## Painted heroes, by id.
const HERO_TEX := {
	"BADGER": "res://assets/heroes/badger_full.png",
	"HARE": "res://assets/heroes/hare_full.png",
	"HEDGE": "res://assets/heroes/hedge_full.png",
	"OWL": "res://assets/heroes/owl_full.png",
	"FOX": "res://assets/heroes/fox_full.png",
	"BOAR": "res://assets/heroes/boar_full.png",
}

## Painted enemy plates, by key. Cut off the reference art by
## `tools/enemy_cutout.py`; nothing in this file draws a creature any more.
const ENEMY_TEX := {
	"E01": "res://assets/enemies/E01.png", "E02": "res://assets/enemies/E02.png",
	"E03": "res://assets/enemies/E03.png", "E04": "res://assets/enemies/E04.png",
	"E05": "res://assets/enemies/E05.png", "E06": "res://assets/enemies/E06.png",
	"E07": "res://assets/enemies/E07.png", "E08": "res://assets/enemies/E08.png",
	"E09": "res://assets/enemies/E09.png", "E10": "res://assets/enemies/E10.png",
	"B1": "res://assets/enemies/B1.png", "B2": "res://assets/enemies/B2.png",
	"B3": "res://assets/enemies/B3.png", "B3P2": "res://assets/enemies/B3P2.png",
	"B4": "res://assets/enemies/B4.png", "B5": "res://assets/enemies/B5.png",
	"B6": "res://assets/enemies/B6.png",
}

## Bosses, including Sir Croak's dismounted second phase. Kept as a list rather
## than a `begins_with("B")` test because two of the heroes are a BADGER and a
## BOAR.
const BOSS_KINDS := ["B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]

## Which chapter each boss is met in. A minion's chapter is its tier — it is
## the same creature fought again — but a boss has no tier, so the rim light
## has nowhere else to learn how dark the card behind it will be.
const BOSS_CHAPTER := {"B1": 1, "B2": 1, "B3": 2, "B3P2": 2, "B4": 2, "B5": 3, "B6": 3}

const ROT_SHADER := "res://assets/shaders/rot_pawn.gdshader"

## Tier dials, as gains on colour the plate already carries. Index is the dial
## row from `_dial_row()`, not the raw tier — a boss sits on row 2 whatever
## chapter it belongs to.
const EYE_GAIN := [0.45, 0.85, 1.5]
const VEIN_GAIN := [0.0, 0.0, 1.1]     # T1/T2 dark, T3 alight
const MIST_COUNT := [0, 3, 5]

## How much of its own art a design draws at each tier. `fit_height` sizes every
## card against tier 3 — the biggest — so a tier-1 minion simply sits smaller
## inside the same card, which is the point.
const TIER_BULK := {1: 0.90, 2: 1.0, 3: 1.12}

static var _tex_cache := {}
static var _shader_cache: Shader = null


## The plate for a hero id, loaded once per run. Null for anything else.
static func hero_texture(p_kind: String) -> Texture2D:
	if not HERO_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(HERO_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]


static func enemy_texture(p_kind: String) -> Texture2D:
	if not ENEMY_TEX.has(p_kind):
		return null
	if not _tex_cache.has(p_kind):
		_tex_cache[p_kind] = load(String(ENEMY_TEX[p_kind])) as Texture2D
	return _tex_cache[p_kind]


## The corruption mask baked beside each plate: red where a lit eye is, green
## along the cracks, blue on the lava. `tools/enemy_cutout.py` decides this —
## see the shader for why it cannot be decided per-pixel at draw time.
static func rot_mask_texture(p_kind: String) -> Texture2D:
	if not ENEMY_TEX.has(p_kind):
		return null
	var key := p_kind + "_rot"
	if not _tex_cache.has(key):
		_tex_cache[key] = load("res://assets/enemies/%s_rot.png" % p_kind) as Texture2D
	return _tex_cache[key]


## The plate for any pawn, hero or enemy.
static func plate(p_kind: String) -> Texture2D:
	var t := hero_texture(p_kind)
	return t if t != null else enemy_texture(p_kind)


static func is_boss(p_kind: String) -> bool:
	return p_kind in BOSS_KINDS


## Which chapter's card this pawn will be standing on, when the caller has not
## said. Bosses are tabulated; a minion's tier IS its chapter.
static func chapter_of(p_kind: String, p_tier: int) -> int:
	if BOSS_CHAPTER.has(p_kind):
		return int(BOSS_CHAPTER[p_kind])
	return clampi(p_tier, 1, 3)


var kind := "BADGER"
var body_h := 140.0
var flip := false
var tier := 3
## The chapter card this pawn stands on. Only the rim light reads it.
var chapter := 1
var _t := 0.0
var _bob_seed := 0.0
var _attack_offset := Vector2.ZERO


## How much space each plate actually uses, as a fraction of the `body_h` it was
## asked for: x = how far it reaches above the feet, y = its half-width.
##
## Every plate is trimmed to its own alpha bounds, so x is 1.00 across the board
## and y is the plate's aspect halved. The heroes' numbers are printed by
## `tools/art_cutout.py`, the enemies' by `tools/enemy_cutout.py` (its
## `PAWN_EXTENT:` line). Re-cut the art and these are re-derived, not re-guessed.
##
## The table is kept even though it is now nearly uniform: `fit_height` needs
## the half-width to know whether a card is width-bound (E02 and E05 are almost
## twice as wide as they are tall) and `half_width` needs it for the ground
## shadow.
const EXTENT := {
	"BADGER": Vector2(1.00, 0.431), "HARE": Vector2(1.00, 0.388),
	"HEDGE": Vector2(1.00, 0.466), "OWL": Vector2(1.00, 0.475),
	"FOX": Vector2(1.00, 0.428), "BOAR": Vector2(1.00, 0.481),
	"E01": Vector2(1.00, 0.60), "E02": Vector2(1.00, 0.93), "E03": Vector2(1.00, 0.40),
	"E04": Vector2(1.00, 0.55), "E05": Vector2(1.00, 0.90), "E06": Vector2(1.00, 0.44),
	"E07": Vector2(1.00, 0.66), "E08": Vector2(1.00, 0.45), "E09": Vector2(1.00, 0.60),
	"E10": Vector2(1.00, 0.51), "B1": Vector2(1.00, 0.46), "B2": Vector2(1.00, 0.34),
	"B3": Vector2(1.00, 0.52), "B3P2": Vector2(1.00, 0.52), "B4": Vector2(1.00, 0.50),
	"B5": Vector2(1.00, 0.51), "B6": Vector2(1.00, 0.48),
}


static func make(p_kind: String, height := 140.0, p_flip := false, p_tier := 3,
		p_chapter := -1) -> PawnArt:
	var pa := PawnArt.new()
	pa.kind = p_kind
	pa.body_h = height
	pa.flip = p_flip
	pa.tier = clampi(p_tier, 1, 3)
	pa.chapter = chapter_of(p_kind, pa.tier) if p_chapter < 1 else clampi(p_chapter, 1, 3)
	pa._bob_seed = hash(p_kind) % 100 / 100.0 * TAU
	return pa


static func extent(p_kind: String) -> Vector2:
	return EXTENT.get(p_kind, Vector2(1.0, 0.35))


## What fraction of its art a design draws at `p_tier`. Bosses and heroes ignore
## tier: a boss is always the same size, and a hero has no tier at all.
static func bulk(p_kind: String, p_tier: int) -> float:
	if is_boss(p_kind) or HERO_TEX.has(p_kind):
		return 1.0
	return float(TIER_BULK.get(clampi(p_tier, 1, 3), 1.0))


## The largest `bulk` this design will ever draw at — what a card has to be
## sized against so the tier-3 form fits and the lower tiers sit smaller inside
## the same card.
static func max_bulk(p_kind: String) -> float:
	return bulk(p_kind, 3)


## Half-width of a design as actually drawn at `p_tier`. The card is sized
## against the tier-3 envelope, but the ground shadow under a tier-1 minion
## should be the width of the tier-1 minion.
static func half_width(p_kind: String, p_tier: int) -> float:
	return extent(p_kind).y * bulk(p_kind, p_tier)


## Head centre and radius in authoring units: x is the y of the head's centre
## (negative — art is drawn upward from the feet), y is the radius that takes in
## the whole head. `MiniPortrait` crops a face out of a full-body pawn with this.
##
## One value for everybody. It used to be a per-design table, which only made
## sense while this file owned each creature's geometry; a plate's head is
## wherever the painter put it and this file cannot know. Every hero — the only
## kind `MiniPortrait` is ever handed — ships a dedicated `*_head.png` crop that
## `MiniPortrait` prefers, so this is the fallback path only.
static func head(_p_kind: String) -> Vector2:
	return Vector2(-100, 40)


## The `body_h` that makes this design draw as large as `box` allows without
## spilling out of it on either axis.
##
## Sized against `max_bulk`, not against the pawn's own tier: the box is the
## tier-3 envelope, and asking a tier-1 minion to fill the same box would undo
## the bulk dial entirely — all three tiers would come out the same height.
static func fit_height(p_kind: String, box: Vector2) -> float:
	var e := extent(p_kind) * max_bulk(p_kind)
	return minf(box.y / maxf(e.x, 0.05), box.x / maxf(2.0 * e.y, 0.05))


## A pawn sized to fill `box` (origin still at the feet, so position it at the
## bottom-centre of the box).
static func fitted(p_kind: String, box: Vector2, p_flip := false, p_tier := 3,
		p_chapter := -1) -> PawnArt:
	return make(p_kind, fit_height(p_kind, box), p_flip, p_tier, p_chapter)


var _last_frame := -1.0


func _ready() -> void:
	set_process(true)
	_apply_rot_material()


func _process(delta: float) -> void:
	_t += delta
	# Redraw only when the stepped idle frame flips (or during a lunge). There
	# used to be a second, faster term in here for the moth's wing flap; the
	# moth is a plate now and nothing else ran at 4Hz, so every pawn was paying
	# for redraws that produced an identical frame.
	var frame := floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	if frame != _last_frame or _attack_offset != Vector2.ZERO:
		_last_frame = frame
		queue_redraw()


## Quick attack lunge (called by the battle screen).
func play_attack() -> void:
	var tw := create_tween()
	var dir := 1.0 if flip else -1.0
	tw.tween_property(self, "_attack_offset", Vector2(dir * -26.0, -6.0), 0.08)
	tw.tween_property(self, "_attack_offset", Vector2.ZERO, 0.22)


# ============================================================ corruption

## 0.0 at tier 1, 1.0 at tier 3. Bosses are never anything but 1.0.
static func rot_of(p_kind: String, p_tier: int) -> float:
	if is_boss(p_kind):
		return 1.0
	return clampf((float(clampi(p_tier, 1, 3)) - 1.0) * 0.5, 0.0, 1.0)


func rot_level() -> float:
	return rot_of(kind, tier)


## Which row of the tier dials this pawn runs on, 0..2.
##
## Not `tier - 1`: `battle_core` files a boss under the chapter it is met in, so
## B1 arrives here carrying tier 1, and reading the row off the tier directly
## would leave the first two bosses with cold eyes and no smoke at all. `rot_of`
## is the conversion that already knows a boss is always all the way gone.
func _dial_row() -> int:
	return int(roundf(rot_level() * 2.0))


## The corruption pass. Heroes never get one — magenta belongs to the enemy.
func _apply_rot_material() -> void:
	if not ENEMY_TEX.has(kind):
		return
	if _shader_cache == null:
		_shader_cache = load(ROT_SHADER) as Shader
	var m := ShaderMaterial.new()
	m.shader = _shader_cache
	var i := _dial_row()
	m.set_shader_parameter("rot_mask", rot_mask_texture(kind))
	m.set_shader_parameter("eye_gain", EYE_GAIN[i])
	m.set_shader_parameter("vein_gain", VEIN_GAIN[i])
	m.set_shader_parameter("ember_gain", 0.6)
	m.set_shader_parameter("rim_strength", UITheme.rot_rim_for(chapter))
	m.set_shader_parameter("rim_color", Vector3(UITheme.ROT_RIM.r, UITheme.ROT_RIM.g,
			UITheme.ROT_RIM.b))
	material = m


# ============================================================ mist

## Authoring-space point → drawing-space point: mirrors a flipped pawn and
## carries the attack lunge. Only the mist goes through it now; the plate itself
## is placed by `draw_set_transform` and flipped by `draw_texture_rect`.
func _c(p: Vector2) -> Vector2:
	var q := p
	if flip:
		q.x = -q.x
	return q + _attack_offset


## The smoke coming off a corrupted thing — `[x, y, height]` per wisp, drawn
## BEFORE the body so it rises from behind. Tier 1 has none, and that absence is
## most of what makes a T1 minion look merely sick rather than lost.
##
## The spot count is not decided here. `_auto_mist` is this function's only
## caller and it already sizes `spots` to `MIST_COUNT[_dial_row()]`; this used
## to re-trim that count again by `t`, and the two only ever agreed because
## both were fed by the same `_dial_row()` — a future edit to `MIST_COUNT`
## alone would have been silently clipped here. One place (`_auto_mist`) owns
## how many spots there are; this only sets how strongly they read.
func _mist(spots: Array) -> void:
	if spots.is_empty():
		return
	var t := rot_level()
	var a := 0.34 + 0.30 * t
	var step := floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	for i in spots.size():
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


## Black mist along the base of the silhouette. Its spots used to be listed per
## creature, which only worked while this file also owned the creature's shape;
## with the plates they are spread across the sprite's own width instead, so
## swapping a plate cannot leave the smoke hanging in the wrong place.
func _auto_mist(w: float, h: float) -> void:
	var n: int = MIST_COUNT[_dial_row()]
	if n <= 0:
		return
	var spots := []
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		spots.append([lerpf(-w * 0.46, w * 0.46, f), -h * 0.22,
				h * lerpf(0.30, 0.46, fmod(float(i) * 0.37, 1.0))])
	_mist(spots)


# ============================================================ draw

func _draw() -> void:
	var tex := plate(kind)
	if tex == null:
		return          # no fallback: nothing in this file draws a creature
	var bob := 3.0 * floorf(fmod(_t * 2.2 + _bob_seed, 2.0))
	var h := body_h * bulk(kind, tier)
	var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	# The mist rises from behind the body, so it goes down first. It draws
	# through `_c`, which carries the lunge itself — the transform under it must
	# not, or the smoke would lunge twice as far as the creature it comes off.
	draw_set_transform(Vector2(0, bob), 0, Vector2.ONE)
	if ENEMY_TEX.has(kind):
		_auto_mist(w, h)
	draw_set_transform(Vector2(0, bob) + _attack_offset, 0, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, Color.WHITE, flip)
