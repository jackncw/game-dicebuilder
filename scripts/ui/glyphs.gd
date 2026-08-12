class_name Glyphs
extends RefCounted
## Drawn keyword icons — one fixed pictogram per game term, in the same flat
## fill + heavy dark outline language as the pawns and the map nodes.
##
## Why drawn and not typed: the die faces are read at a glance at 76px, in three
## language modes, on six category colours. A CJK character shrinks into mush,
## an emoji depends on whatever fallback font the platform happens to ship, and
## neither survives being the *primary* read of a face. A polygon does.
##
## Everything is authored inside a 32×32 design box centred on the origin
## (coordinates run −16…+16) and scaled to whatever rect it is asked for, so one
## definition serves a 14px corner badge and a 120px detail card alike.
##
## `Glossary` owns which glyph belongs to which term; this file only draws.

## Terms that share another term's picture.
const ALIAS := {
	"random_atk": "atk", "team_heal": "heal", "self_heal": "heal",
	"team_block": "block", "team_thorns": "thorns", "team_regen": "regen",
	"mana_drain": "mana", "cleanse_self": "cleanse", "cleanse_target": "cleanse",
	"steal_die": "steal", "cancel_die": "cancel", "sweep": "aoe",
	"buff_next_atk": "charge", "rerolls": "insight",
	"reroll": "insight", "act_once": "cancel",
	# 2026-08 character overhaul
	"resonate_req": "resonate", "team_atk": "atk", "all_pierce": "pierce",
	"thorn_hold": "thorns", "thorns_double": "thorns", "atk_from_block": "block",
	"block_from_mana": "mana", "twin_dance": "multi",
	"self_atk_now": "charge", "heal_on_hit": "lifesteal",
	"next_dice_boost": "chargeup", "low_hp_atk": "pain",
	"old_sergeant": "block", "quilled_hide": "block", "held_breath": "pierce",
	"ancient_warden": "mana", "call_and_answer": "resonate", "cornered_fury": "pain",
}

## Every picture this file can draw. Anything else falls back to a plain disc,
## which is deliberately dull-looking so a missing icon is obvious in review.
const KEYS := ["atk", "block", "heal", "mana", "poison", "burn", "stun", "weaken",
	"expose", "taunt", "thorns", "lifesteal", "combo", "wild", "pierce", "cleave",
	"aoe", "growth", "pain", "lucky", "spell", "bind", "curse", "insight",
	"regen", "summon", "charge", "counter", "howl", "cancel", "steal", "down",
	"echo", "cleanse", "blank", "relic",
	# Four added by the 2026-08 character overhaul. 穿透 and 自損 are NOT here:
	# both mechanics already shipped, with pictures, and drawing them a second
	# time would have split one keyword across two symbols.
	"chargeup", "resonate", "multi", "lock",
	# One per relic, in the same 32×32 box and the same flat-fill + heavy-ink
	# language. They are object-shaped (a jar, a coin, a drum) rather than
	# symbol-shaped: a relic is a thing in your pack, and the silhouette is what
	# has to be recognisable in the 26px row along the top of the battle screen.
	"r_sigil", "r_whetstone", "r_crest", "r_acorn", "r_crystal", "r_honey",
	"r_spring", "r_coin", "r_vial", "r_tinderbox", "r_foot", "r_metronome",
	"r_kit", "r_spyglass", "r_rod", "r_loop",
	"r_twinmoon", "r_crown", "r_chalice", "r_bone", "r_heart", "r_drum"]


static func resolve(key: String) -> String:
	var k := String(ALIAS.get(key, key))
	return k if k in KEYS else ""


static func has(key: String) -> bool:
	return resolve(key) != ""


## Draw `key` centred in `rect`. `tint` fills the shape, `ink` outlines it —
## pass a transparent ink for a silhouette.
static func draw_glyph(ci: CanvasItem, key: String, rect: Rect2, tint: Color,
		ink := UITheme.OUTLINE) -> void:
	var k := resolve(key)
	var c := rect.get_center()
	var u := minf(rect.size.x, rect.size.y) / 32.0
	if u <= 0.0:
		return
	match k:
		"atk": _atk(ci, c, u, tint, ink)
		"block": _block(ci, c, u, tint, ink)
		"heal": _heal(ci, c, u, tint, ink)
		"mana": _mana(ci, c, u, tint, ink)
		"poison": _poison(ci, c, u, tint, ink)
		"burn": _burn(ci, c, u, tint, ink)
		"stun": _stun(ci, c, u, tint, ink)
		"weaken": _weaken(ci, c, u, tint, ink)
		"expose": _expose(ci, c, u, tint, ink)
		"taunt": _taunt(ci, c, u, tint, ink)
		"thorns": _thorns(ci, c, u, tint, ink)
		"lifesteal": _lifesteal(ci, c, u, tint, ink)
		"combo": _combo(ci, c, u, tint, ink)
		"wild": _wild(ci, c, u, tint, ink)
		"pierce": _pierce(ci, c, u, tint, ink)
		"cleave": _cleave(ci, c, u, tint, ink)
		"aoe": _aoe(ci, c, u, tint, ink)
		"growth": _growth(ci, c, u, tint, ink)
		"pain": _pain(ci, c, u, tint, ink)
		"lucky": _lucky(ci, c, u, tint, ink)
		"spell": _spell(ci, c, u, tint, ink)
		"bind": _bind(ci, c, u, tint, ink)
		"curse": _curse(ci, c, u, tint, ink)
		"insight": _insight(ci, c, u, tint, ink)
		"regen": _regen(ci, c, u, tint, ink)
		"summon": _summon(ci, c, u, tint, ink)
		"charge": _charge(ci, c, u, tint, ink)
		"counter": _counter(ci, c, u, tint, ink)
		"howl": _howl(ci, c, u, tint, ink)
		"cancel": _cancel(ci, c, u, tint, ink)
		"steal": _steal(ci, c, u, tint, ink)
		"down": _down(ci, c, u, tint, ink)
		"echo": _echo(ci, c, u, tint, ink)
		"cleanse": _cleanse(ci, c, u, tint, ink)
		"blank": _blank(ci, c, u, tint, ink)
		"relic": _relic(ci, c, u, tint, ink)
		"chargeup": _chargeup(ci, c, u, tint, ink)
		"resonate": _resonate(ci, c, u, tint, ink)
		"multi": _multi(ci, c, u, tint, ink)
		"lock": _lock(ci, c, u, tint, ink)
		"r_sigil": _r_sigil(ci, c, u, tint, ink)
		"r_whetstone": _r_whetstone(ci, c, u, tint, ink)
		"r_crest": _r_crest(ci, c, u, tint, ink)
		"r_acorn": _r_acorn(ci, c, u, tint, ink)
		"r_crystal": _r_crystal(ci, c, u, tint, ink)
		"r_honey": _r_honey(ci, c, u, tint, ink)
		"r_spring": _r_spring(ci, c, u, tint, ink)
		"r_coin": _r_coin(ci, c, u, tint, ink)
		"r_vial": _r_vial(ci, c, u, tint, ink)
		"r_tinderbox": _r_tinderbox(ci, c, u, tint, ink)
		"r_foot": _r_foot(ci, c, u, tint, ink)
		"r_metronome": _r_metronome(ci, c, u, tint, ink)
		"r_rod": _r_rod(ci, c, u, tint, ink)
		"r_loop": _r_loop(ci, c, u, tint, ink)
		"r_kit": _r_kit(ci, c, u, tint, ink)
		"r_spyglass": _r_spyglass(ci, c, u, tint, ink)
		"r_twinmoon": _r_twinmoon(ci, c, u, tint, ink)
		"r_crown": _r_crown(ci, c, u, tint, ink)
		"r_chalice": _r_chalice(ci, c, u, tint, ink)
		"r_bone": _r_bone(ci, c, u, tint, ink)
		"r_heart": _r_heart(ci, c, u, tint, ink)
		"r_drum": _r_drum(ci, c, u, tint, ink)
		_: _unknown(ci, c, u, tint, ink)


# ============================================================ primitives

static func _poly(ci: CanvasItem, c: Vector2, u: float, pts: Array, fill: Color,
		ink: Color, w := 2.2) -> void:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(c + Vector2(p[0], p[1]) * u)
	if fill.a > 0.0:
		ci.draw_colored_polygon(poly, fill)
	if ink.a > 0.0:
		var closed := poly.duplicate()
		closed.append(poly[0])
		ci.draw_polyline(closed, ink, maxf(1.0, w * u), true)


static func _line(ci: CanvasItem, c: Vector2, u: float, a: Array, b: Array,
		col: Color, w := 3.0) -> void:
	ci.draw_line(c + Vector2(a[0], a[1]) * u, c + Vector2(b[0], b[1]) * u,
			col, maxf(1.0, w * u), true)


static func _disc(ci: CanvasItem, c: Vector2, u: float, at: Array, r: float,
		fill: Color, ink: Color, w := 2.2) -> void:
	var p := c + Vector2(at[0], at[1]) * u
	if fill.a > 0.0:
		ci.draw_circle(p, r * u, fill)
	if ink.a > 0.0:
		ci.draw_arc(p, r * u, 0.0, TAU, 26, ink, maxf(1.0, w * u), true)


static func _ring(ci: CanvasItem, c: Vector2, u: float, at: Array, r: float,
		col: Color, w := 2.6, from := 0.0, to := TAU) -> void:
	ci.draw_arc(c + Vector2(at[0], at[1]) * u, r * u, from, to, 30, col,
			maxf(1.0, w * u), true)


## n-pointed star, used by the dizzy sparks and the wild badge.
static func _star_pts(at: Array, r: float, r2: float, n: int, turn := 0.0) -> Array:
	var out := []
	for i in n * 2:
		var a := -PI * 0.5 + turn + PI * i / float(n)
		var rr := r if i % 2 == 0 else r2
		out.append([at[0] + cos(a) * rr, at[1] + sin(a) * rr])
	return out


## Chevron ">" as a filled arrow head, pointing along `dir` (unit-ish vector).
static func _chevron(ci: CanvasItem, c: Vector2, u: float, at: Array, size: float,
		ang: float, fill: Color, ink: Color) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var tip := Vector2(at[0], at[1]) + d * size
	var l := Vector2(at[0], at[1]) + n * size * 0.85
	var r := Vector2(at[0], at[1]) - n * size * 0.85
	var back := Vector2(at[0], at[1]) - d * size * 0.25
	_poly(ci, c, u, [[tip.x, tip.y], [l.x, l.y], [back.x, back.y], [r.x, r.y]], fill, ink, 1.8)


# ============================================================ the pictures

## 攻擊 — an upright sword: blade, crossguard, grip.
static func _atk(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [4, -8], [3.4, 4], [-3.4, 4], [-4, -8]], t, k)
	_poly(ci, c, u, [[-10, 4], [10, 4], [10, 8], [-10, 8]], t, k)
	_poly(ci, c, u, [[-2.6, 8], [2.6, 8], [2.6, 15], [-2.6, 15]], t, k)


## 格擋 — a heater shield.
static func _block(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -14], [12, -9], [12, 2], [0, 15], [-12, 2], [-12, -9]], t, k, 2.6)


## 治療 — a cross with two leaves at its foot: heal, but growing.
static func _heal(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-4, -14], [4, -14], [4, -4], [14, -4], [14, 4], [4, 4],
			[4, 14], [-4, 14], [-4, 4], [-14, 4], [-14, -4], [-4, -4]], t, k, 2.4)
	_poly(ci, c, u, [[4, 9], [12, 7], [11, 14], [4, 14]], t, k, 1.8)


## 靈息 — a faceted droplet crystal.
static func _mana(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [9, -1], [0, 15], [-9, -1]], t, k, 2.6)
	_line(ci, c, u, [-9, -1], [9, -1], k, 1.8)
	_line(ci, c, u, [0, -15], [0, 15], k, 1.4)


## 中毒 — a droplet with bubbles in it.
static func _poison(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [5, -6], [9, 1], [7, 9], [0, 14], [-7, 9],
			[-9, 1], [-5, -6]], t, k, 2.4)
	_disc(ci, c, u, [-2.5, 4], 2.6, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [3.5, 0], 1.8, k, Color(0, 0, 0, 0))


## 灼燒 — a flame: one tall licking tongue with a second curling off it, so it
## cannot be mistaken for the poison / lifesteal droplets.
static func _burn(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[1, -16], [-4, -6], [-2, -4], [-8, 2], [-8, 8], [-3, 14],
			[4, 15], [10, 10], [10, 2], [4, -6]], t, k, 2.4)
	_poly(ci, c, u, [[1, -3], [5, 4], [3, 10], [-2, 12], [-4, 7], [-1, 3]],
			k, Color(0, 0, 0, 0))


## 暈眩 — one big spark and one small, the classic "seeing stars".
static func _stun(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, _star_pts([-2, -3], 13.0, 4.2, 4), t, k, 2.0)
	_poly(ci, c, u, _star_pts([9, 9], 6.5, 2.2, 4, 0.5), t, k, 1.6)


## 弱化 — a snapped arrow: head and flight still lined up, shaft broken in the
## middle with the two ends kicked apart.
static func _weaken(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[16, -14], [4, -12], [10, -6]], t, k, 1.8)     # head
	_line(ci, c, u, [8, -8], [0, 0], t, 4.0)                        # upper shaft
	_line(ci, c, u, [8, -8], [0, 0], k, 1.6)
	_line(ci, c, u, [-3, 5], [-11, 13], t, 4.0)                     # lower shaft
	_line(ci, c, u, [-3, 5], [-11, 13], k, 1.6)
	_poly(ci, c, u, [[-16, 14], [-14, 7], [-7, 12]], t, k, 1.6)     # flight
	# the break itself
	_line(ci, c, u, [-1, 1], [2, 7], t, 2.4)
	_line(ci, c, u, [-4, 4], [-7, 1], t, 2.4)


## 易傷 — a target ring split by a crack.
static func _expose(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 14.0, Color(0, 0, 0, 0), t, 2.8)
	_disc(ci, c, u, [0, 0], 6.0, t, k, 1.6)
	_poly(ci, c, u, [[-3, -15], [1, -6], [-2, -1], [3, 6], [0, 15], [4, 15],
			[7, 5], [3, -1], [6, -7], [2, -15]], k, Color(0, 0, 0, 0))


## 嘲諷 — a grinning mask.
static func _taunt(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-12, -12], [12, -12], [12, 2], [0, 15], [-12, 2]], t, k, 2.4)
	_poly(ci, c, u, [[-8, -6], [-2, -6], [-5, -1]], k, Color(0, 0, 0, 0))
	_poly(ci, c, u, [[8, -6], [2, -6], [5, -1]], k, Color(0, 0, 0, 0))
	_poly(ci, c, u, [[-7, 4], [7, 4], [4, 8], [-4, 8]], k, Color(0, 0, 0, 0))


## 荊棘 — a barbed thorn.
static func _thorns(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [5, 6], [0, 13], [-5, 6]], t, k, 2.2)
	_poly(ci, c, u, [[-4, 0], [-14, 8], [-4, 7]], t, k, 1.6)
	_poly(ci, c, u, [[4, 3], [14, 11], [4, 10]], t, k, 1.6)


## 吸血 — a droplet with a highlight, no bubbles (that is Poison's tell).
static func _lifesteal(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [5, -6], [9, 1], [7, 9], [0, 14], [-7, 9],
			[-9, 1], [-5, -6]], t, k, 2.4)
	_poly(ci, c, u, [[-5, 2], [-2, -3], [-1, 4], [-4, 7]], k, Color(0, 0, 0, 0))


## 連擊 — two chevrons, one behind the other.
static func _combo(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-14, -11], [-5, -11], [3, 0], [-5, 11], [-14, 11], [-6, 0]], t, k, 2.0)
	_poly(ci, c, u, [[-1, -11], [8, -11], [16, 0], [8, 11], [-1, 11], [7, 0]], t, k, 2.0)


## 百搭 — a question mark inside a spark. The mark is drawn heavy: at badge
## size a hairline "?" disappears into the star behind it.
static func _wild(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, _star_pts([0, 0], 16.0, 8.0, 6), t, k, 2.0)
	_ring(ci, c, u, [0, -5], 6.0, k, 4.0, PI * 0.95, TAU + PI * 0.3)
	_line(ci, c, u, [3, 0], [0, 5], k, 4.0)
	_disc(ci, c, u, [0, 11], 2.8, k, Color(0, 0, 0, 0))


## 穿刺 — an arrow that has gone straight through a shield.
static func _pierce(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-2, -11], [8, -7], [8, 1], [-2, 11], [-12, 1], [-12, -7]], t, k, 2.0)
	_line(ci, c, u, [-14, 12], [10, -12], k, 3.4)
	_poly(ci, c, u, [[15, -15], [7, -13], [13, -7]], t, k, 1.6)


## 橫掃 — a sweeping arc with a tail.
static func _cleave(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_ring(ci, c, u, [0, 4], 13.0, k, 5.0, PI * 1.08, TAU - PI * 0.08)
	_ring(ci, c, u, [0, 4], 13.0, t, 2.6, PI * 1.08, TAU - PI * 0.08)
	_poly(ci, c, u, [[15, -1], [7, -9], [6, 1]], t, k, 1.6)


## 全體 — three arrows leaving one point, so it reads as "goes to everything"
## rather than as three loose triangles.
static func _aoe(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	for a in [-PI * 0.5, PI * 0.8, PI * 0.2]:
		var d := Vector2(cos(a), sin(a))
		_line(ci, c, u, [d.x * 2.0, d.y * 2.0 + 3.0], [d.x * 10.0, d.y * 10.0 + 3.0], t, 3.4)
		_chevron(ci, c, u, [d.x * 11.0, d.y * 11.0 + 3.0], 5.4, a, t, k)


## 成長 — a sprout: stem plus two leaves.
static func _growth(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_line(ci, c, u, [0, 15], [0, -4], k, 3.0)
	_poly(ci, c, u, [[0, -1], [-13, -5], [-9, -13], [-1, -8]], t, k, 1.8)
	_poly(ci, c, u, [[0, 3], [13, -1], [9, -9], [1, -4]], t, k, 1.8)


## 自損 — a heart split by a jagged crack. The crack is strokes rather than a
## polygon: a zig-zag that narrow self-intersects, and Godot's triangulator
## rejects it outright.
static func _pain(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -8], [-5, -14], [-13, -12], [-15, -3], [0, 14],
			[15, -3], [13, -12], [5, -14]], t, k, 2.2)
	var zig := [[-1, -11], [3, -5], [-2, 0], [3, 6], [-1, 13]]
	for i in zig.size() - 1:
		_line(ci, c, u, zig[i], zig[i + 1], k, 2.6)


## 幸運 — a four-leaf clover.
static func _lucky(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	for a in [[-6, -7], [6, -7], [-6, 3], [6, 3]]:
		_disc(ci, c, u, a, 6.6, t, k, 1.8)
	_line(ci, c, u, [1, 2], [5, 15], k, 2.4)


## 靈術 — a rune circle with tick marks and an inner triangle.
static func _spell(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 14.0, Color(0, 0, 0, 0), t, 2.6)
	_disc(ci, c, u, [0, 0], 9.0, Color(0, 0, 0, 0), t, 1.8)
	_poly(ci, c, u, [[0, -8], [7, 5], [-7, 5]], t, k, 1.6)
	for a2 in [0.0, PI * 0.5, PI, PI * 1.5]:
		var p := Vector2(cos(a2 - PI * 0.25), sin(a2 - PI * 0.25))
		_line(ci, c, u, [p.x * 12.0, p.y * 12.0], [p.x * 16.0, p.y * 16.0], t, 2.4)


## 束縛 — two interlocking links.
static func _bind(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [-6, -5], 8.0, Color(0, 0, 0, 0), k, 4.6)
	_disc(ci, c, u, [-6, -5], 8.0, Color(0, 0, 0, 0), t, 2.4)
	_disc(ci, c, u, [6, 6], 8.0, Color(0, 0, 0, 0), k, 4.6)
	_disc(ci, c, u, [6, 6], 8.0, Color(0, 0, 0, 0), t, 2.4)


## 詛咒 — drifting bands of mist, each one a wave rather than a bar so it does
## not read as a stack of shelves.
static func _curse(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	for r in [[-9.0, 14.0, 1.0], [-1.0, 16.0, -1.0], [7.0, 12.0, 1.0]]:
		var y: float = r[0]
		var w: float = r[1]
		var s: float = r[2]
		var pts := PackedVector2Array()
		for i in 13:
			var x := -w + 2.0 * w * i / 12.0
			pts.append(c + Vector2(x, y + sin(i * 0.9) * 2.2 * s) * u)
		ci.draw_polyline(pts, t, maxf(1.0, 3.4 * u), true)
	_disc(ci, c, u, [-12, -14], 2.4, t, Color(0, 0, 0, 0))
	_disc(ci, c, u, [10, -15], 1.8, t, Color(0, 0, 0, 0))


## 洞察 — an eye.
static func _insight(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-15, 0], [-7, -8], [0, -10], [7, -8], [15, 0],
			[7, 8], [0, 10], [-7, 8]], t, k, 2.4)
	_disc(ci, c, u, [0, 0], 5.2, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [2, -2], 1.8, t, Color(0, 0, 0, 0))


## 再生 — a leaf with a turning arrow around it.
static func _regen(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-2, 12], [-10, 2], [-4, -11], [7, -3], [6, 8]], t, k, 2.0)
	_ring(ci, c, u, [0, 0], 15.0, t, 2.6, -PI * 0.2, PI * 0.95)
	_poly(ci, c, u, [[15, -5], [10, 2], [16, 3]], t, k, 1.4)


## 召喚 — a portal ring with sparks rising out of it.
static func _summon(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-14, 8], [0, 2], [14, 8], [0, 14]], t, k, 2.0)
	_disc(ci, c, u, [0, -3], 3.4, t, k, 1.6)
	_disc(ci, c, u, [-7, -9], 2.4, t, k, 1.4)
	_disc(ci, c, u, [7, -11], 2.0, t, k, 1.4)


## 蓄力 / 蓄勢 — two chevrons stacked over a base bar.
static func _charge(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -15], [13, -4], [6, -4], [0, -10], [-6, -4], [-13, -4]], t, k, 2.0)
	_poly(ci, c, u, [[0, -4], [13, 7], [6, 7], [0, 1], [-6, 7], [-13, 7]], t, k, 2.0)
	_poly(ci, c, u, [[-12, 11], [12, 11], [12, 15], [-12, 15]], t, k, 1.8)


## 反擊 — an arrow bouncing off a wall. The strokes are the tint, not the ink:
## this glyph sits on a dark chip, where an ink line is invisible.
static func _counter(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[10, -15], [15, -15], [15, 15], [10, 15]], t, k, 2.0)
	_line(ci, c, u, [-14, -11], [8, -3], t, 3.6)
	_line(ci, c, u, [8, 1], [-11, 10], t, 3.6)
	_poly(ci, c, u, [[-16, 13], [-9, 5], [-6, 13]], t, k, 1.6)


## 嚎叫 — an open muzzle with sound rings.
static func _howl(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-15, -10], [-3, -3], [-3, 3], [-15, 10]], t, k, 2.0)
	for r in [6.0, 11.0, 16.0]:
		_ring(ci, c, u, [-3, 0], r, t, 2.4, -PI * 0.38, PI * 0.38)


## 消 / 取消 — a barred circle.
static func _cancel(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 14.0, Color(0, 0, 0, 0), k, 5.4)
	_disc(ci, c, u, [0, 0], 14.0, Color(0, 0, 0, 0), t, 3.0)
	_line(ci, c, u, [-9, 9], [9, -9], k, 5.4)
	_line(ci, c, u, [-9, 9], [9, -9], t, 3.0)


## 偷骰 — a hook lifting a small die away.
static func _steal(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-13, 0], [3, 0], [3, 15], [-13, 15]], t, k, 2.0)
	_disc(ci, c, u, [-8, 7], 2.0, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [-2, 11], 2.0, k, Color(0, 0, 0, 0))
	_ring(ci, c, u, [7, -6], 8.0, t, 3.0, PI * 0.1, PI * 1.4)
	_line(ci, c, u, [7, -14], [7, -16], t, 3.0)


## 倒下 — a skull.
static func _down(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-12, -12], [12, -12], [12, 3], [6, 8], [6, 14],
			[-6, 14], [-6, 8], [-12, 3]], t, k, 2.2)
	_disc(ci, c, u, [-5.5, -4], 3.6, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [5.5, -4], 3.6, k, Color(0, 0, 0, 0))
	_line(ci, c, u, [-6, 10], [6, 10], k, 2.0)


## 迴響 — nested arcs rippling outward.
static func _echo(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 3.6, t, k, 1.6)
	for r in [8.0, 13.0]:
		_ring(ci, c, u, [0, 0], r, t, 2.6, -PI * 0.75, PI * 0.25)


## 蓄力 — a gauge filling from the bottom, with the top notch still empty and a
## chevron pushing into it. `charge` next door is chevrons over a bar and means
## the enemy's wind-up; this one has to read as "mine, and it is filling", so it
## is a container rather than a direction.
static func _chargeup(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-8, -10], [8, -10], [8, 15], [-8, 15]], Color(0, 0, 0, 0), k, 2.4)
	_poly(ci, c, u, [[-6, 0], [6, 0], [6, 13], [-6, 13]], t, Color(0, 0, 0, 0))
	_line(ci, c, u, [-8, -2], [8, -2], k, 1.8)
	_line(ci, c, u, [-8, 6], [8, 6], k, 1.8)
	_poly(ci, c, u, [[0, -16], [7, -11], [3, -11], [3, -6], [-3, -6], [-3, -11], [-7, -11]], t, k, 1.8)


## 呼應 — two crescents turned to face each other across a spark: one blade
## calls, the other answers. `echo` (迴響) is rings spreading from a point, so
## the two never read as the same idea.
static func _resonate(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_ring(ci, c, u, [-13, 0], 11.0, t, 3.2, -PI * 0.42, PI * 0.42)
	_ring(ci, c, u, [-13, 0], 11.0, k, 1.6, -PI * 0.42, PI * 0.42)
	_ring(ci, c, u, [13, 0], 11.0, t, 3.2, PI * 0.58, PI * 1.42)
	_ring(ci, c, u, [13, 0], 11.0, k, 1.6, PI * 0.58, PI * 1.42)
	_poly(ci, c, u, _star_pts([0, 0], 7.0, 2.4, 4), t, k, 1.6)


## 多重攻擊 — three parallel slashes, the tally you leave on something. Read
## against `combo`'s two nested chevrons it is "how many times", not "again".
static func _multi(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	for dx in [-9.0, 0.0, 9.0]:
		_poly(ci, c, u, [[dx - 3.0, -14], [dx + 3.0, -14], [dx + 1.0, 14],
				[dx - 5.0, 14]], t, k, 1.8)


## A padlock. 釘骰機制已於第十輪移除 —— 今日冇任何 glossary 條目再用呢個
## glyph,留低只係因為 die3d 的 locked-out badge 同一語彙(每回合一次)。
static func _lock(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_ring(ci, c, u, [0, -3], 8.0, k, 3.4, PI, TAU)
	_ring(ci, c, u, [0, -3], 8.0, t, 1.8, PI, TAU)
	_poly(ci, c, u, [[-12, -3], [12, -3], [12, 15], [-12, 15]], t, k, 2.4)
	_disc(ci, c, u, [0, 4], 3.0, k, Color(0, 0, 0, 0))
	_line(ci, c, u, [0, 4], [0, 10], k, 2.6)


## 淨化 — one big sparkle and two small.
static func _cleanse(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, _star_pts([-2, -1], 15.0, 4.0, 4), t, k, 2.0)
	_poly(ci, c, u, _star_pts([10, 10], 6.0, 1.8, 4), t, k, 1.4)
	_poly(ci, c, u, _star_pts([11, -10], 4.5, 1.4, 4), t, k, 1.2)


## 空白面 — a hollow square with a slash: nothing happens.
static func _blank(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-12, -12], [12, -12], [12, 12], [-12, 12]],
			Color(0, 0, 0, 0), t, 2.6)
	_line(ci, c, u, [-9, 9], [9, -9], t, 2.6)


static func _unknown(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 10.0, t, k, 2.0)


# ============================================================ relic pictures

## 遺物 — the generic chest, for the "what is a relic" glossary row.
static func _relic(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-14, -2], [14, -2], [14, 13], [-14, 13]], t, k, 2.2)
	_poly(ci, c, u, [[-14, -2], [-11, -12], [11, -12], [14, -2]], t, k, 2.2)
	_poly(ci, c, u, [[-3, -2], [3, -2], [3, 7], [-3, 7]], k, Color(0, 0, 0, 0))


## N01 森林徽章 — a round badge with a leaf pressed into it.
static func _r_sigil(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 14.0, t, k, 2.6)
	_poly(ci, c, u, [[0, 10], [-8, 0], [-3, -11], [7, -3], [6, 6]], k, Color(0, 0, 0, 0))
	_line(ci, c, u, [0, 11], [2, -6], t, 1.8)


## N01 導靈杖 — a staff with a bound crystal at its head, throwing a spark.
##
## Deliberately staff-shaped rather than badge-shaped: it replaced 森林徽章,
## whose glyph was a round badge, and two relics that read alike in the 26px
## strip along the top of the battle screen would be worse than either.
##
## Every structural shape is drawn in `t` with a `k` outline, never in `k`
## alone. `t` is the LIGHT colour and the disc behind a relic glyph is dark, so
## an ink-only stroke is invisible — which is exactly how the first cut of this
## shipped a rod with no rod in it.
static func _r_rod(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-11, 12], [-7, 16], [6, -3], [2, -7]], t, k, 1.8)
	_poly(ci, c, u, [[2, -9], [9, -15], [13, -7], [6, -1]], t, k, 2.2)
	_line(ci, c, u, [4, -6], [10, -10], k, 1.6)
	_line(ci, c, u, [11, -17], [13, -13], t, 2.0)
	_line(ci, c, u, [16, -13], [12, -11], t, 2.0)


## N12 靈息迴環 — a closed loop with a drop caught in it: what the pool pays
## back when you leave it standing.
static func _r_loop(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	# `draw_arc` measures from +X and runs clockwise on screen (Y is down), so
	# the gap has to be centred on -PI/2 to sit at the TOP, where the head is
	_ring(ci, c, u, [0, 0], 12.0, t, 3.6, -PI * 0.5 + 0.62, -PI * 0.5 + TAU - 0.62)
	# the open end, arrowed, so it reads as a cycle rather than as a letter
	_poly(ci, c, u, [[-1, -17], [7, -11], [-2, -6]], t, k, 1.6)
	_poly(ci, c, u, [[0, -3], [5, 3], [0, 9], [-5, 3]], t, k, 2.0)


## N02 磨刀石 — a canted block with a blade skimming its top edge.
static func _r_whetstone(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-15, 3], [13, -3], [15, 8], [-13, 14]], t, k, 2.4)
	_poly(ci, c, u, [[-11, -6], [9, -14], [11, -10], [-9, -2]], t, k, 1.8)
	_line(ci, c, u, [-13, 6], [11, 0], k, 1.4)


## N03 盾徽 — a heater shield with a chevron cut through it.
static func _r_crest(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -14], [12, -9], [12, 2], [0, 15], [-12, 2], [-12, -9]], t, k, 2.6)
	_poly(ci, c, u, [[-9, -3], [0, -9], [9, -3], [9, 2], [0, -4], [-9, 2]],
			k, Color(0, 0, 0, 0))


## N04 橡果護符 — an acorn: hatched cap, round nut, little stalk.
static func _r_acorn(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-11, -2], [11, -2], [8, 8], [0, 15], [-8, 8]], t, k, 2.4)
	_poly(ci, c, u, [[-13, -10], [13, -10], [11, -2], [-11, -2]], t, k, 2.4)
	_line(ci, c, u, [-5, -10], [-4, -2], k, 1.4)
	_line(ci, c, u, [5, -10], [4, -2], k, 1.4)
	_line(ci, c, u, [0, -10], [0, -16], k, 2.4)


## N05 靈息水晶 — a tall shard with a smaller one beside it.
static func _r_crystal(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-2, -16], [7, -4], [4, 13], [-6, 13], [-9, -4]], t, k, 2.4)
	_line(ci, c, u, [-9, -4], [7, -4], k, 1.4)
	_poly(ci, c, u, [[10, -4], [15, 3], [13, 13], [7, 13]], t, k, 1.8)


## N06 蜜糖罐 — a squat pot with a lid and a drip running down it.
static func _r_honey(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-11, -5], [11, -5], [13, 8], [8, 15], [-8, 15], [-13, 8]], t, k, 2.4)
	_poly(ci, c, u, [[-13, -11], [13, -11], [12, -5], [-12, -5]], t, k, 2.2)
	_disc(ci, c, u, [0, -14], 2.6, t, k, 1.6)
	_poly(ci, c, u, [[3, -5], [7, -5], [6, 4], [3, 6], [1, 2]], k, Color(0, 0, 0, 0))


## N07 聖泉水 — a round flask with a wave inside it.
static func _r_spring(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 4], 11.0, t, k, 2.4)
	_poly(ci, c, u, [[-4, -16], [4, -16], [4, -6], [-4, -6]], t, k, 2.0)
	_line(ci, c, u, [-7, -16], [7, -16], k, 2.6)
	var pts := PackedVector2Array()
	for i in 11:
		var x := -8.0 + 16.0 * i / 10.0
		pts.append(c + Vector2(x, 4.0 + sin(i * 0.8) * 2.4) * u)
	ci.draw_polyline(pts, k, maxf(1.0, 2.2 * u), true)


## N08 銅錢 — the old square-holed coin.
static func _r_coin(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_disc(ci, c, u, [0, 0], 14.0, t, k, 2.6)
	_poly(ci, c, u, [[-5, -5], [5, -5], [5, 5], [-5, 5]], k, Color(0, 0, 0, 0))
	_ring(ci, c, u, [0, 0], 9.5, k, 1.6)


## N09 毒瓶 — a corked bottle with bubbles rising in it.
static func _r_vial(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-8, -6], [8, -6], [10, 8], [5, 15], [-5, 15], [-10, 8]], t, k, 2.4)
	_poly(ci, c, u, [[-4, -15], [4, -15], [4, -6], [-4, -6]], t, k, 2.0)
	_poly(ci, c, u, [[-6, -16], [6, -16], [6, -13], [-6, -13]], k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [-2, 6], 3.0, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [4, 1], 1.8, k, Color(0, 0, 0, 0))


## N10 火絨盒 — a shallow tin with a flame standing out of it.
static func _r_tinderbox(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-14, 4], [14, 4], [14, 14], [-14, 14]], t, k, 2.4)
	_line(ci, c, u, [-14, 8], [14, 8], k, 1.6)
	_poly(ci, c, u, [[0, -16], [-6, -6], [-4, -4], [-7, 1], [0, 4], [7, 1], [5, -5]],
			t, k, 2.2)


## N11 幸運兔腳 — a padded foot hung on a thong.
static func _r_foot(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-7, 1], [7, 1], [9, 8], [4, 15], [-4, 15], [-9, 8]], t, k, 2.2)
	for at in [[-7, -6], [0, -9], [7, -6]]:
		_disc(ci, c, u, at, 3.6, t, k, 1.6)
	_ring(ci, c, u, [0, -14], 4.0, k, 2.0)


## N12 節拍器 — the wedge body with its arm swung to one side.
static func _r_metronome(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-11, 14], [11, 14], [5, -12], [-5, -12]], t, k, 2.4)
	_line(ci, c, u, [0, 12], [6, -14], k, 2.6)
	_poly(ci, c, u, [[2, -2], [7, -2], [7, 3], [2, 3]], k, Color(0, 0, 0, 0))
	_line(ci, c, u, [-8, 8], [8, 8], k, 1.4)


## N13 骰匠工具 — a hammer standing over a small die.
static func _r_kit(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-14, 0], [-2, 0], [-2, 14], [-14, 14]], t, k, 2.2)
	_disc(ci, c, u, [-11, 4], 1.6, k, Color(0, 0, 0, 0))
	_disc(ci, c, u, [-5, 10], 1.6, k, Color(0, 0, 0, 0))
	_poly(ci, c, u, [[1, -15], [14, -15], [14, -7], [1, -7]], t, k, 2.0)
	_poly(ci, c, u, [[5, -7], [9, -7], [9, 12], [5, 12]], t, k, 1.8)


## N14 望遠鏡 — a tapering tube with two collars.
static func _r_spyglass(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-15, -3], [2, -7], [2, 7], [-15, 3]], t, k, 2.2)
	_poly(ci, c, u, [[2, -8], [15, -12], [15, 12], [2, 8]], t, k, 2.2)
	_line(ci, c, u, [2, -7], [2, 7], k, 1.8)
	_line(ci, c, u, [-9, -4], [-9, 4], k, 1.4)


## A01 雙月徽記 — two crescents turned away from each other.
static func _r_twinmoon(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	for sgn in [-1.0, 1.0]:
		var turn := 0.0 if sgn > 0.0 else PI
		_ring(ci, c, u, [sgn * 6.0, 0.0], 11.0, t, 4.4, turn - PI * 0.44, turn + PI * 0.44)
		_ring(ci, c, u, [sgn * 6.0, 0.0], 11.0, k, 1.8, turn - PI * 0.44, turn + PI * 0.44)
	_disc(ci, c, u, [0, 0], 2.6, t, k, 1.4)


## A02 荊棘王冠 — a crown whose points are thorns.
static func _r_crown(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-15, 10], [-15, -10], [-7, -1], [0, -14], [7, -1], [15, -10],
			[15, 10]], t, k, 2.4)
	_poly(ci, c, u, [[-15, 10], [15, 10], [15, 15], [-15, 15]], t, k, 2.0)
	for at in [[-11, -6], [0, -10], [11, -6]]:
		_disc(ci, c, u, at, 1.8, k, Color(0, 0, 0, 0))


## A03 血之聖杯 — a footed goblet with a drop above the bowl.
static func _r_chalice(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-11, -6], [11, -6], [7, 4], [-7, 4]], t, k, 2.4)
	_poly(ci, c, u, [[-2, 4], [2, 4], [2, 11], [-2, 11]], t, k, 1.8)
	_poly(ci, c, u, [[-9, 11], [9, 11], [9, 15], [-9, 15]], t, k, 2.0)
	_poly(ci, c, u, [[0, -16], [4, -10], [0, -7], [-4, -10]], k, Color(0, 0, 0, 0))


## A04 賭徒之骨 — a knucklebone with pips punched into it.
static func _r_bone(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-9, -8], [9, -8], [9, 8], [-9, 8]], t, k, 2.4)
	for at in [[-13, -11], [13, -11], [-13, 11], [13, 11]]:
		_disc(ci, c, u, at, 4.6, t, k, 2.0)
	for at2 in [[-4, -3], [4, 3], [-4, 3], [4, -3]]:
		_disc(ci, c, u, at2, 1.7, k, Color(0, 0, 0, 0))


## A05 森之心 — a heart with a leaf growing out of it.
static func _r_heart(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[0, -4], [-5, -11], [-13, -9], [-15, 0], [0, 15],
			[15, 0], [13, -9], [5, -11]], t, k, 2.2)
	_poly(ci, c, u, [[0, -2], [9, -8], [12, -16], [3, -13], [-1, -7]],
			k, Color(0, 0, 0, 0))


## A06 獸王戰鼓 — a barrel drum with a beater either side.
static func _r_drum(ci: CanvasItem, c: Vector2, u: float, t: Color, k: Color) -> void:
	_poly(ci, c, u, [[-10, -8], [10, -8], [12, 3], [10, 12], [-10, 12], [-12, 3]], t, k, 2.4)
	_line(ci, c, u, [-11, -4], [11, -4], k, 1.6)
	_line(ci, c, u, [-11, 8], [11, 8], k, 1.6)
	for sgn2 in [-1.0, 1.0]:
		_line(ci, c, u, [sgn2 * 13, -15], [sgn2 * 6, -6], k, 2.6)
		_disc(ci, c, u, [sgn2 * 14, -15], 2.6, t, k, 1.4)


# ============================================================ node wrapper

## A Control that draws one glyph filling its rect. Cheap: it only repaints when
## `set_glyph` actually changes something.
class Icon:
	extends Control
	var key := "atk"
	var tint := UITheme.CREAM
	var ink := UITheme.OUTLINE

	func _init(p_key := "atk", p_size := Vector2(24, 24), p_tint := UITheme.CREAM,
			p_ink := UITheme.OUTLINE) -> void:
		key = p_key
		tint = p_tint
		ink = p_ink
		custom_minimum_size = p_size
		size = p_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_glyph(p_key: String, p_tint := tint, p_ink := ink) -> void:
		if key == p_key and tint == p_tint and ink == p_ink:
			return
		key = p_key
		tint = p_tint
		ink = p_ink
		queue_redraw()

	func _draw() -> void:
		Glyphs.draw_glyph(self, key, Rect2(Vector2.ZERO, size), tint, ink)


## Convenience: a sized icon node for `key`.
static func icon(key: String, px := 24.0, tint := UITheme.CREAM,
		ink := UITheme.OUTLINE) -> Icon:
	return Icon.new(key, Vector2(px, px), tint, ink)
