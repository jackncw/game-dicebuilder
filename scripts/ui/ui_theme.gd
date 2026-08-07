class_name UITheme
extends RefCounted
## Design tokens for 骰林 Dice Grove — the single source of truth for spacing,
## corner radii, border widths, type sizes and colour.
##
## Nothing here knows about game rules; it is pure presentation. `UIKit` builds
## widgets out of these tokens and every screen goes through `UIKit`, so a
## change here lands everywhere at once.
##
## ── Spacing scale ────────────────────────────────────────────────
## 4 / 8 / 12 / 16 / 24 / 32. Anything between two steps is a mistake; pick the
## nearer step. Gaps inside a widget use S1–S2, gaps between widgets S3–S4,
## gaps between groups S5–S6.
##
## ── Type scale (3 tiers) ─────────────────────────────────────────
## TITLE  : DISPLAY 60 / H1 38 / H2 28   — screen names, section heads
## BODY   : BODY 22 / BODY_SM 18         — everything the player reads
## SMALL  : CAPTION 15 / MICRO 12        — dense labels, only over solid ink
##
## ── Contrast rule ────────────────────────────────────────────────
## Light text only ever sits on `surface()`/`surface_deep()` (or darker), never
## straight on a chapter background, so every body string clears 4.5:1.

# ── spacing ────────────────────────────────────────────────────────
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32

# ── corner radii ───────────────────────────────────────────────────
const R_CHIP := 6     # intent chips, die icon chips
const R_SM := 10      # small cards, buttons in dense rows
const R_MD := 14      # standard panels and buttons
const R_LG := 20      # hero/enemy cards, modals

# ── border widths ──────────────────────────────────────────────────
const B_HAIR := 2     # chips
const B_BASE := 3     # default outline
const B_STRONG := 4   # cards, buttons
const B_FOCUS := 5    # selected / legal-target emphasis

# ── type scale ─────────────────────────────────────────────────────
const F_DISPLAY := 60
const F_H1 := 38
const F_H2 := 28
const F_BODY := 22
const F_BODY_SM := 18
const F_CAPTION := 15
const F_MICRO := 12

# ── shadow ─────────────────────────────────────────────────────────
const SHADOW := Color(0, 0, 0, 0.22)
const SHADOW_OFFSET := Vector2(0, 4)

# ── ink & paper ────────────────────────────────────────────────────
const OUTLINE := Color("2b2b2b")      # the one dark outline colour, everywhere
const CREAM := Color("f5efe0")        # paper / light text
const CREAM_DARK := Color("d9cfb4")   # secondary light text (>=4.5:1 on surface)
const INK := Color("2b2b2b")          # text on cream
const INK_SOFT := Color("5a544a")     # secondary text on cream

# ── category colours (six) ─────────────────────────────────────────
## Used identically on die chips, tooltips, codex rows, shop cards.
const RED := Color("d94f4f")      # attack
const BLUE := Color("4f7fd9")     # defense
const GREEN := Color("58b368")    # heal
const PURPLE := Color("9b6dd9")   # resource
const YELLOW := Color("e0a83c")   # control
const ORANGE := Color("e07b4f")   # special

const CAT_COLORS := {
	"attack": RED, "defense": BLUE, "heal": GREEN,
	"resource": PURPLE, "control": YELLOW, "special": ORANGE,
}

## Same six hues lifted for use as text/detail on a dark surface — the raw
## chips are readable as fills but too dark as type.
const CAT_ON_DARK := {
	"attack": Color("f08d8d"), "defense": Color("8fb2ef"), "heal": Color("8fd79b"),
	"resource": Color("c6a4f2"), "control": Color("f0c86e"), "special": Color("f0a482"),
}

## Chip fills. A saturated mid-tone hue carries neither cream nor ink text at
## 4.5:1 (red/blue/purple all land near 3.5), so every small coloured badge in
## the game is a deep fill + cream type + a bright rim of the true hue. The
## rim is what keeps the six categories instantly separable.
const CAT_DEEP := {
	"attack": Color("7d2626"), "defense": Color("26407d"), "heal": Color("1f5c31"),
	"resource": Color("4a2f7d"), "control": Color("6e4e10"), "special": Color("7a3820"),
}


## Deep fill for an arbitrary hue, for chips whose colour is picked ad hoc.
static func deepen(c: Color) -> Color:
	return c.darkened(0.55).lerp(Color("1a1a1a"), 0.15)

# ── chapter palettes ───────────────────────────────────────────────
## BG is the sky behind everything; SURFACE is the panel ink that carries
## light text; ACCENT tints silhouettes and headers.
const CHAPTER_BG := {1: Color("3a6b35"), 2: Color("7a5230"), 3: Color("3d2b52")}
const CHAPTER_SURFACE := {1: Color("1b3019"), 2: Color("362414"), 3: Color("1e1429")}
const CHAPTER_DEEP := {1: Color("122009"), 2: Color("241708"), 3: Color("140c1c")}
const CHAPTER_ACCENT := {1: Color("7fc46a"), 2: Color("e0a25c"), 3: Color("b48ce0")}

const NEUTRAL_SURFACE := Color("232326")
const DANGER_BG := Color("2a1e1e")

# ── corruption — THE ENEMY SIDE ONLY ───────────────────────────────
## Everything hostile in the grove is the same story: an animal gone over to
## the rot. Its body is pulled towards `ROT_UNDER`, magenta cracks the surface,
## the eyes light up, and black mist comes off it.
##
## Magenta is the enemy's colour and nobody else's. A hero, a die, a button, a
## player status icon may not be tinted anywhere inside `is_magenta()` — that
## is what makes a magenta pixel on screen mean "this is not yours" without a
## legend. `_t_no_player_magenta()` in `ui_smoke` enforces it.
const ROT_UNDER := Color("2c2038")      # the dead violet every body sinks toward
const ROT_VEIN := Color("e13cc0")       # corruption crack, at full depth
const ROT_VEIN_DIM := Color("a83a90")   # the same crack where the rot is young
const ROT_EYE := Color("ff5ad8")        # lit eye
const ROT_EYE_DIM := Color("d34aae")    # eye at tier 1: awake, not yet burning
## The smoke, laid down at low alpha. Grey-violet rather than the near-black it
## started as: black smoke over a chapter-3 card (`#1e1429`) is invisible, and
## the mist is one of the four things telling a tier-3 minion from a tier-1 one.
const ROT_MIST := Color("4a4055")
const ROT_RIM := Color("cfa8dd")        # rim light that keeps a dark body legible


## How hard the rim light has to work on a given chapter's enemy card.
##
## The enemy plates are painted nearly black — they were drawn on a cream
## sheet, where that reads fine. Our cards are `surface(chapter)`, and all
## three chapter surfaces are dark (this is a night-time grove), so the rim
## is always doing some work, but not equally: measured with `luminance()`,
## chapter 1's card (`#1b3019`) is 0.0242, chapter 2's (`#362414`) is 0.0210,
## chapter 3's (`#1e1429`) is 0.0094. Strength is read straight off the
## card's own luminance rather than tabulated per chapter, which keeps this
## honest if a chapter surface is ever retuned.
##
## This is the SINGLE SOURCE for rim strength: `rot_pawn.gdshader` is handed
## the result through its `rim_strength` uniform, and `_t_enemy_legibility`
## predicts the lit edge with it. Two copies of this curve would let the test
## and the picture drift apart silently.
static func rot_rim_for(chapter: int) -> float:
	var l := luminance(surface(chapter))
	# 0.0242 luminance (chapter 1's card) -> 0.35; 0.0094 (chapter 3's) -> 1.0
	return clampf(remap(l, 0.0094, 0.0242, 1.0, 0.35), 0.0, 1.0)

## The magenta wedge, in Godot's 0–1 hue. 285°–342°: everything from violet-
## magenta through to rose. Below it sits the game's existing purple family
## (the `resource` category and the chapter-3 palette all land at 260°–270°),
## which is why the band starts at 285 and not at 270 — the guard gap is
## deliberate, so a hue nudge cannot slide a player colour into enemy territory
## without the test noticing.
const MAGENTA_H_LO := 285.0 / 360.0
const MAGENTA_H_HI := 342.0 / 360.0
## Below these a hue is not read as a colour at all — near-grey or near-black —
## so the ban only covers pixels saturated and bright enough to actually say
## "magenta" to the player.
const MAGENTA_S_MIN := 0.35
const MAGENTA_V_MIN := 0.30


## Is this colour inside the reserved enemy wedge?
static func is_magenta(c: Color) -> bool:
	return (c.s >= MAGENTA_S_MIN and c.v >= MAGENTA_V_MIN
			and c.h >= MAGENTA_H_LO and c.h <= MAGENTA_H_HI)

# ── forest materials ───────────────────────────────────────────────
## Added in the second art pass. Buttons are planks, paths are trodden earth
## and map nodes are ringed with stones, so those three materials get named
## colours here rather than being typed at each call site.
const WOOD := Color("8a5a32")         # button plank
const WOOD_SIGN := Color("7a4f2c")    # the darker board the title hangs on
const WOOD_TEXT := Color("f2d9a8")    # warm cream, for type burnt into a sign
const DIRT := Color("4d3a24")         # path bed
const DIRT_STEP := Color("dbc799")    # the footfalls dashed along it
const STONE := Color("b8b5a3")        # the ring around a map clearing
const BARK := Color("3d2b1a")         # trunks on the map treeline

## Grain, pegs and the corner vignette are all "a bit of shadow" — one alpha
## ramp so they stay in step if the paper colour ever changes.
const SHADE_SOFT := Color(0, 0, 0, 0.13)
const SHADE_MED := Color(0, 0, 0, 0.2)
const SHADE_CORNER := Color(0, 0, 0, 0.16)


static func cat_color(cat: String) -> Color:
	return CAT_COLORS.get(cat, Color("8a8a8a"))


static func cat_text(cat: String) -> Color:
	return CAT_ON_DARK.get(cat, Color("c9c9c9"))


static func bg(chapter: int) -> Color:
	return CHAPTER_BG.get(chapter, CHAPTER_BG[1])


## Panel fill for cards sitting on a chapter background. Solid, not a white
## wash: a translucent panel takes its contrast from whatever is behind it,
## which is exactly how body text ends up at 3:1 on the bright chapters.
static func surface(chapter: int) -> Color:
	return CHAPTER_SURFACE.get(chapter, CHAPTER_SURFACE[1])


static func surface_deep(chapter: int) -> Color:
	return CHAPTER_DEEP.get(chapter, CHAPTER_DEEP[1])


static func accent(chapter: int) -> Color:
	return CHAPTER_ACCENT.get(chapter, CHAPTER_ACCENT[1])


## Relative luminance per WCAG, for the contrast self-check in the tests.
static func luminance(c: Color) -> float:
	var parts := [c.r, c.g, c.b]
	var lin := []
	for v in parts:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


static func contrast(fg: Color, bg_c: Color) -> float:
	var a := luminance(fg)
	var b := luminance(bg_c)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)
