extends Node
## Measures how legible each enemy silhouette actually is on the card it fights
## on — by RENDERING it at the size the battle screen gives it, and reading the
## pixels back. Not by modelling it.
##
##   Godot --path . --log-file art_export/legib.log tools/enemy_legibility.tscn
##   sed -e 's/\r$//' art_export/legib.log | grep LEGIBILITY
##
## Must run with a REAL window: the grab awaits `RenderingServer.frame_post_draw`,
## which never fires under `--headless`, so the run would hang to its timeout and
## write nothing.
##
## ── What this reconciles against ─────────────────────────────────
## `ui_smoke._t_enemy_legibility` holds every enemy to THREE bounds, not one:
##   1. the card-backed edge reaches `CARD_EDGE_FLOOR` (2.4:1) against the bare
##      chapter card;
##   2. the mist stands on at most `MIST_COVER_CAP` (25%) of the edge band;
##   3. where it does stand, the edge still reaches `MIST_EDGE_FLOOR` (1.55:1)
##      against mist-over-card — a floor this tool's own render priced, after the
##      Task-5 1.9 turned out to have been derived from the pinned-`edge` model.
## The floors are read off the proxy at print time, never restated here.
## All three are computed from ONE modelled quantity — `lit_edge()`, the plate's
## `edge_rgb` lerped towards `UITheme.ROT_RIM` by `UITheme.rot_rim_for(chapter)`
## — plus `card_behind()` and `mist_coverage()`. So this tool measures the real
## counterpart of each of the three and reports all three deltas; the tolerance
## `DELTA_MAX` is a contrast tolerance and applies to bounds 1 and 3.
##
## The proxy is not re-implemented here. `ui_smoke.gd` is instantiated and its
## own `seen_edge` / `card_behind` / `mist_coverage` are called, so the numbers in
## the `proxy=` column are the numbers the headless suite actually asserts on,
## and there is no second copy to drift.
##
## What the RENDERED columns borrow from the proxy is only the ruler — the band
## `edge_rgb` was measured over, and the card sizes. Every colour in them comes
## off the frame buffer, including both backgrounds: bound 1's card and bound 3's
## mist-over-card. The mist background used to be taken from `card_behind()`,
## which left the one quantity separating bound 3 from bound 1 as the one quantity
## never read off the picture, inside the tool whose premise is that the picture
## wins. `_sample_mist` reads it now, and `LEGIBILITY MISTBG` prints what the
## model was worth (0.72 of one 8-bit step, worst channel, over 27 rows).
##
## ── What the deltas are FOR ──────────────────────────────────────
## `ui_smoke` cannot render. What it can do is be conservative about the fact,
## and `CARD_EDGE_MARGIN` is how: bound 1's headless check is `2.4 + 0.06`, that
## 0.06 covering the +0.0447 by which the model has been measured to read ABOVE
## this render. That is a claim about a number only this tool can produce,
## so this tool prints it — `LEGIBILITY BOUND1 worst OPTIMISTIC bias` — and says
## whether the margin still covers it. If that line ever reads MARGIN TOO SMALL,
## the headless suite has stopped implying anything about the picture and the
## constant has to move (or the term behind it has to be modelled).
##
## Bound 3 gets no such margin and is not reconcilable from here. It is still
## ASSERTED by `ui_smoke` — an unmargined `_check` that can fail the suite — but
## only as a loose regression guard: the model resolves that bound to about
## ±0.44 against a 1.55 floor, so its green neither implies nor refutes what this
## render says. The proof is on the record: at the old 1.9 floor the proxy redded
## E09 ch3 at 1.893 while this tool passed the same row at 1.930. See
## `LEGIBILITY BOUND3` at the bottom of the output.
##
## ── Which size is "the picture", and which renders happen ────────
## `rim_px` is in TEXTURE pixels (`rot_pawn.gdshader` multiplies it by
## `TEXTURE_PIXEL_SIZE`), so the rim's on-screen thickness is `rim_px × draw
## scale`, and the plates are stored at wildly different resolutions (143px tall
## to 512px). Each key is therefore rendered THREE times per (chapter, tier) row:
##   • at the SMALLEST box `screen_battle._enemy_metrics()` can hand it — four
##     minions up, or a boss. The bounds are FLOORS, so the smallest and most
##     minified box is the reconciliation target, and bounds 1 and 2 are read
##     off it;
##   • at draw scale 1.0, which is the ruler bound 3 is read off — on the
##     four-up card a row can land as few as 14 veiled pixels, and a mean over
##     14 pixels is not a measurement (see `_measure`'s note);
##   • at the smallest box again, DIMMED by the modulate `screen_battle` puts on
##     a non-target enemy card while the player is choosing a target. That state
##     is not modelled anywhere and is not bounded; this prints what it costs.
##
## Sizes come from `screen_battle` itself rather than being restated, so a
## retuned card layout moves this measurement with it.

const MINIONS := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10"]
const BOSSES := ["B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]

## ── Which pixels get read back ───────────────────────────────────
## `proxy._edge_band(key)` — the band `enemy_cutout.py` averaged `edge_rgb` over
## (`alpha > 200`, minus three 3x3 erosions), asked for from `ui_smoke` itself so
## there is no second definition. A screen pixel counts if the texel it samples
## is in that band. That is deliberately the set the proxy's `lit` SPEAKS FOR,
## and not "the outermost 3 screen pixels of everything drawn": the first attempt
## used the latter and it measured the wrong thing. `alpha > 0.2` (the shader's
## rim gate) starts three pixels further out, in the anti-aliased skirt, so a
## 3-screen-pixel band anchored there ends BEFORE the rim's peak — on E02 at
## scale 1.04 it read the profile 1.03 / 1.30 / 1.97:1 and never reached the
## 2.71:1 the rim actually gets to two pixels further in. Same picture, wrong
## ruler. Anchoring on `alpha > 200` puts the two rulers on the same set.
##
## In SCREEN pixels that band is `3 x draw scale` wide: at scale 1.04 it is three
## pixels, at 0.12 a third of one, and a screen pixel then does a single bilinear
## tap at an arbitrary sub-texel phase rather than reading a texel. That was the
## last large term in the proxy's residual and it is no longer unmodelled —
## `ui_smoke._screen_band` walks this same grid at the same draw scale. What this
## tool now checks is whether that model matches the picture, which is a much
## sharper question than it used to be asking.
const DELTA_MAX := 0.15
const PAD := 10

## The modulate `screen_battle._refresh_enemies` puts on every NON-TARGET enemy
## card while `_targeting()` is true — i.e. exactly while a player is scanning
## the row of silhouettes to pick one. `modulate` propagates down the CanvasItem
## tree, so it reaches the card's own panel AND the pawn drawn inside it, and
## `rot_pawn.gdshader`'s last line is `COLOR = vec4(lit, src.a) * v_modulate`.
##
## COPIED from `scripts/ui/screen_battle.gd:585`, which is the only place it is
## written, because it is a literal inside `_refresh_enemies` and there is no
## way to ask a bare `.new()` screen for it. If that literal moves, this must.
const DIM_MODULATE := Color(0.55, 0.55, 0.6, 0.85)

## The same modulate with its ALPHA removed, rendered alongside as a bracket.
## The alpha lets 15% of whatever the card stands on through, and what it stands
## on is `Forest.scenery` — a painted scene whose local colour varies, so the
## real number sits between "over the arena's ground tone" (the bright end, the
## pessimistic one) and "over nothing at all". Measuring both says how much of
## the damage is the multiply, which no backdrop can argue away.
const DIM_MODULATE_OPAQUE := Color(0.55, 0.55, 0.6, 1.0)

var meta := {}
var sub: SubViewport
var proxy: Node          ## a live `tests/ui_smoke.gd`, used as the model
var battle: Control      ## a live `screen_battle.gd`, used for the card metrics
var _alpha_cache := {}
var _edge_cache := {}
var _ring_cache := {}

## Rendered mist backgrounds, keyed on `chapter` and `PawnArt.mist_alpha`.
##
## Those two are the WHOLE of what the colour is — `_wisp` fills one polygon with
## `ROT_MIST` at `mist_alpha(key, tier)` over `surface(chapter)`, and nothing about
## which creature it is enters — so two rows sharing the key share the pixel, and
## the engine's blend is deterministic. `mist_alpha` is `0.34 + 0.30 * rot_of`,
## and `rot_of` is tier (or boss), never the key.
##
## Why the sharing is needed rather than merely convenient: E09's wisps stand
## entirely BEHIND its silhouette. Measured off its own render, every one of the
## 2436 (tier 2) / 3898 (tier 3) pixels inside a wisp has plate alpha 0.79 / 0.13
## or more over it, so there is no pixel anywhere in E09's picture where
## mist-over-card is visible unoccluded. The colour is still a fact about the
## render; it is just a fact E01's render carries and E09's does not.
##
## Dimmed renders never touch this — see `_measure`.
var _mist_bg_cache := {}


func _ready() -> void:
	var f := FileAccess.open("res://assets/enemies/enemies.json", FileAccess.READ)
	if f == null:
		print("LEGIBILITY ABORT: assets/enemies/enemies.json is missing")
		get_tree().quit(1)
		return
	meta = JSON.parse_string(f.get_as_text())
	f.close()

	# `_ready` only fires on tree entry, so neither of these runs its own body.
	proxy = load("res://tests/ui_smoke.gd").new()
	battle = load("res://scripts/ui/screen_battle.gd").new()

	sub = SubViewport.new()
	sub.size = Vector2i(64, 64)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	var rows := []
	# one worst-delta per bound, not one overall. They are reconciled to
	# different standards now and rolling them together hid that: bound 1 is
	# modelled (minification included) and lands inside DELTA_MAX, bound 3 is not
	# and does not. A single "PROXY NEEDS FIXING" would have kept saying nothing
	# useful about the bound that IS fixed.
	var worst_d1 := 0.0
	var worst_d1_what := ""
	var worst_d3 := 0.0
	var worst_d3_what := ""
	# the signed worst in the OPTIMISTIC direction on bound 1 (proxy above
	# render), which is the number `ui_smoke.CARD_EDGE_MARGIN` has to cover for a
	# green suite to imply a passing picture
	var worst_hi := -99.0
	var worst_hi_what := ""
	var worst_card := 99.0
	var worst_card_what := ""
	var worst_card_row := []
	var worst_mist := 99.0
	var worst_mist_what := ""
	var worst_mist_row := []
	var worst_cover := -1.0
	var worst_cover_what := ""
	# what the targeting dim costs, on the same card-backed ruler as bound 1
	var worst_dim := 99.0
	var worst_dim_what := ""
	var worst_dim_op := 99.0
	var worst_dim_op_what := ""
	var best_dim := -99.0
	var best_dim_what := ""
	var worst_dim_drop := 0.0
	var worst_dim_drop_what := ""
	# how far the MEASURED mist background sits from `card_behind`'s model of it
	var worst_mbg := 0.0
	var worst_mbg_what := ""
	# and the same check on the BARE card, where the answer is already known:
	# an undimmed render's card pixels have to come back as `UITheme.surface()`,
	# or the screen->texel projection is not reading the image it thinks it is
	var worst_cbg := 0.0
	var worst_cbg_what := ""
	var mbg_rows := []
	var dim_rows := []

	for key in MINIONS + BOSSES:
		var chapters: Array = [int(PawnArt.BOSS_CHAPTER[key])] \
				if PawnArt.BOSS_CHAPTER.has(key) else [1, 2, 3]
		for ch_v in chapters:
			var ch := int(ch_v)
			# a minion's tier IS the chapter it is met in (`battle_core.gd:123`),
			# and `:179` files a boss under `int(def.chapter)` — so on both sides
			# the tier a pawn arrives here carrying is its chapter
			var tier := ch
			var box := _box(key)
			var small: Dictionary = await _measure(key, tier, ch, box)
			# ── why bound 3 is read off a SECOND, native-scale render ──
			# The mist-backed sample is a fraction of a fraction: on the smallest
			# card E05 ch3 lands 413 band pixels and a wisp stands behind 0.5% of
			# them — TWO pixels. A mean of two pixels, both of them on a wisp's own
			# rasterised boundary, is not a measurement, and at rim_px 3 that row
			# read 1.000:1 while its neighbours read 1.2–1.7.
			#
			# What bound 3 constrains is a pair of colours — lit edge against
			# mist-over-card — and that pair is scale-free: `rim_px` is a fixed
			# TEXEL radius, so the shader's output at a given UV does not know how
			# large the plate is drawn. Rendering the same row at draw scale 1.0
			# therefore measures the same quantity with 1/scale^2 (7x to 65x) the
			# samples. Both are printed — `mist real` is the native one, `mist@sm`
			# the small card's — and where the small card has enough pixels to be
			# worth anything the two agree.
			var nat: Dictionary = await _measure(key, tier, ch, box, -1.0, true)
			# ── the state nothing models: a non-target card while targeting ──
			# `screen_battle` dims every non-target enemy card the moment a die is
			# picked up, which is exactly when a player is scanning silhouettes to
			# choose one. Same smallest box as bound 1, so the two numbers are on
			# the same ruler and the drop between them is the cost.
			var dim: Dictionary = await _measure(key, tier, ch, box, -1.0, false,
					DIM_MODULATE)
			var dim_op: Dictionary = await _measure(key, tier, ch, box, -1.0, false,
					DIM_MODULATE_OPAQUE)

			var edge_v: Variant = proxy._edge_colour(meta, key)
			var edge: Color = edge_v if edge_v != null else Color.BLACK
			var card_bg: Color = UITheme.surface(ch)
			var mist_bg: Color = proxy.card_behind(ch, key, tier)
			# ── the proxy column, on the SAME ruler as the render beside it ──
			# `seen_edge` models this row at the draw scale the four-up card gives
			# it and composites at the alpha each fragment carries, which is what
			# `_measure` above just rendered. `lit_edge` alone is the un-minified,
			# un-composited colour and is no longer what the suite asserts on.
			var p_card: float = UITheme.contrast(
					proxy.seen_edge(edge, ch, key, tier, card_bg), card_bg)
			var p_cover: float = proxy.mist_coverage(key, tier)

			var d_card: float = absf(small["card"] - p_card)
			if d_card > worst_d1:
				worst_d1 = d_card
				worst_d1_what = "%s ch%d" % [key, ch]
			if p_card - small["card"] > worst_hi:
				worst_hi = p_card - small["card"]
				worst_hi_what = "%s ch%d" % [key, ch]
			var mist_real := 0.0
			var mist_n := 0
			# and bound 3's proxy on the ruler bound 3's RENDER was taken at —
			# native scale where the row is veiled (the four-up card leaves as
			# few as 14 veiled pixels), the four-up card where it is not and
			# bound 3 has collapsed onto bound 1. Model one scale against a
			# render of the other and the minification term lands in the delta
			# twice, which would read as a modelling failure that is not there.
			var mist_n_nat: int = nat["mist_n"]
			var mist_native: bool = mist_n_nat > 0
			if mist_native:
				mist_real = nat["mist"]
				mist_n = int(nat["mist_n"])
			elif int(PawnArt.MIST_COUNT[PawnArt.dial_row(key, tier)]) == 0:
				# no wisps at all: bound 3's background IS the bare card and it
				# collapses onto bound 1, exactly as `card_behind` says it does.
				# Read off the SMALL card, because that is the row bound 1 owns.
				mist_real = small["card"]
				mist_n = int(small["band_n"])
			var p_mist: float = UITheme.contrast(
					proxy.seen_edge(edge, ch, key, tier, mist_bg, mist_native), mist_bg)
			var mist_txt := "  n/a"
			var d_mist_txt := "  n/a"
			if mist_n > 0:
				var d_mist: float = absf(mist_real - p_mist)
				mist_txt = "%5.3f" % mist_real
				d_mist_txt = "%5.3f" % d_mist
				if d_mist > worst_d3:
					worst_d3 = d_mist
					worst_d3_what = "%s ch%d" % [key, ch]
				if mist_real < worst_mist:
					worst_mist = mist_real
					worst_mist_what = "%s ch%d tier%d" % [key, ch, tier]
					worst_mist_row = [key, ch, tier, box]

			# ── the background bound 3 is measured against, READ, not modelled ──
			# `card_behind()` is the proxy's model of mist-over-card, and until now
			# this tool borrowed it: the one quantity that separates bound 3 from
			# bound 1 was the one quantity never taken off the picture, inside the
			# tool whose whole premise is that the picture wins. It is measured now
			# — see `_sample_mist` — and this line is what says whether the model
			# was right. The rendered bound-3 contrasts above are against the
			# MEASURED background; the proxy column stays against `card_behind`,
			# because that is what the headless suite asserts on.
			if int(PawnArt.MIST_COUNT[PawnArt.dial_row(key, tier)]) > 0:
				var mb: Color = nat["mist_bg_c"]
				var dmb := maxf(maxf(absf(mb.r - mist_bg.r), absf(mb.g - mist_bg.g)),
						absf(mb.b - mist_bg.b))
				if dmb > worst_mbg:
					worst_mbg = dmb
					worst_mbg_what = "%s ch%d tier%d" % [key, ch, tier]
				mbg_rows.append(("LEGIBILITY MISTBG %-4s ch%d t%d rendered=%s modelled=%s "
						+ "worst channel delta=%.4f (%.2f/255) n=%d (%s)")
						% [key, ch, tier, mb.to_html(false), mist_bg.to_html(false),
						dmb, dmb * 255.0, int(nat["mist_bg_n"]),
						String(nat["mist_bg_src"])])

			var cbg: Color = small["card_seen"]
			var dcbg := maxf(maxf(absf(cbg.r - card_bg.r), absf(cbg.g - card_bg.g)),
					absf(cbg.b - card_bg.b))
			if dcbg > worst_cbg:
				worst_cbg = dcbg
				worst_cbg_what = "%s ch%d tier%d" % [key, ch, tier]

			if small["card"] < worst_card:
				worst_card = small["card"]
				worst_card_what = "%s ch%d tier%d" % [key, ch, tier]
				worst_card_row = [key, ch, tier, box]

			# the dim state, against the card AS THE DIM LEAVES IT — both the
			# silhouette and the panel behind it go through the same modulate, and
			# 15% of the arena behind the card comes through with it, so the
			# background this contrast is taken against has to be read off the
			# render too. `_sample_card` does that.
			var r_dim: float = dim["card"]
			var drop: float = small["card"] - r_dim
			if r_dim < worst_dim:
				worst_dim = r_dim
				worst_dim_what = "%s ch%d tier%d" % [key, ch, tier]
			if r_dim > best_dim:
				best_dim = r_dim
				best_dim_what = "%s ch%d tier%d" % [key, ch, tier]
			if float(dim_op["card"]) < worst_dim_op:
				worst_dim_op = float(dim_op["card"])
				worst_dim_op_what = "%s ch%d tier%d" % [key, ch, tier]
			if drop > worst_dim_drop:
				worst_dim_drop = drop
				worst_dim_drop_what = "%s ch%d tier%d" % [key, ch, tier]
			dim_rows.append(("LEGIBILITY DIM %-4s ch%d t%d card %5.3f:1 -> dimmed %5.3f:1 "
					+ "(%+.3f) | multiply only %5.3f:1 | card %s -> %s over arena %s "
					+ "| floor %.2f %s")
					% [key, ch, tier, small["card"], r_dim, -drop,
					float(dim_op["card"]),
					card_bg.to_html(false), (dim["card_seen"] as Color).to_html(false),
					UITheme.bg(ch).to_html(false), float(proxy.CARD_EDGE_FLOOR),
					"OK" if r_dim >= float(proxy.CARD_EDGE_FLOOR) else "UNDER"])
			# from the native render: the same fraction, resolved on 7x–65x the
			# pixels, so the cap is judged on a number that has samples behind it
			if nat["cover"] > worst_cover:
				worst_cover = nat["cover"]
				worst_cover_what = "%s ch%d tier%d" % [key, ch, tier]

			# what rim strength the render actually laid down, as a fraction of
			# the one `rot_rim_for` handed the shader — the coverage the proxy
			# is missing — and the two alpha-channel terms that predict it
			var se := _fit_strength(edge, ch, small["card_c"])
			var rim: float = UITheme.rot_rim_for(ch)
			var sh: Dictionary = _shader_edge(key)

			rows.append(("LEGIBILITY %-4s ch%d t%d scale=%.3f band=%d "
					+ "card real=%5.3f proxy=%5.3f delta=%5.3f "
					+ "mist real=%s n=%4d proxy=%5.3f delta=%s "
					+ "cover real=%4.1f%% proxy=%4.1f%% "
					+ "| s_eff=%.3f cov=%.3f edge=%.3f alpha=%.3f "
					+ "| rings %5.3f/%5.3f/%5.3f "
					+ "| nat card=%5.3f mist@sm=%5.3f n=%3d")
					% [key, ch, tier, small["scale"], small["band_n"],
					small["card"], p_card, d_card,
					mist_txt, mist_n, p_mist, d_mist_txt,
					nat["cover"] * 100.0, p_cover * 100.0,
					se, se / rim, float(sh["edge"]), float(sh["alpha"]),
					small["rings"][0], small["rings"][1], small["rings"][2],
					nat["card"], small["mist"], int(small["mist_n"])])

	for r in rows:
		print(r)
	for r in mbg_rows:
		print(r)
	print("LEGIBILITY MISTBG worst channel delta vs card_behind() %.4f (%.2f/255) at %s"
			% [worst_mbg, worst_mbg * 255.0, worst_mbg_what])
	print("LEGIBILITY CARDBG rendered bare card vs UITheme.surface() worst channel delta "
			+ "%.4f (%.2f/255) at %s — the projection reading the image it thinks it is"
			% [worst_cbg, worst_cbg * 255.0, worst_cbg_what])
	for r in dim_rows:
		print(r)
	print("LEGIBILITY DIM worst card-backed edge while targeting %.3f:1 at %s (bound-1 floor %.2f) %s"
			% [worst_dim, worst_dim_what, float(proxy.CARD_EDGE_FLOOR),
			"OK" if worst_dim >= float(proxy.CARD_EDGE_FLOOR) else "UNDER"])
	print("LEGIBILITY DIM best card-backed edge while targeting %.3f:1 at %s"
			% [best_dim, best_dim_what])
	print("LEGIBILITY DIM worst with the modulate's ALPHA removed (multiply only) %.3f:1 at %s"
			% [worst_dim_op, worst_dim_op_what])
	print("LEGIBILITY DIM worst drop from the undimmed card %+.3f at %s"
			% [-worst_dim_drop, worst_dim_drop_what])
	print("LEGIBILITY WORST-DELTA bound1 %.3f at %s (max allowed %.2f) %s"
			% [worst_d1, worst_d1_what, DELTA_MAX,
			"OK" if worst_d1 <= DELTA_MAX else "OVER"])
	print("LEGIBILITY WORST-DELTA bound3 %.3f at %s (max allowed %.2f) %s"
			% [worst_d3, worst_d3_what, DELTA_MAX,
			"OK" if worst_d3 <= DELTA_MAX else "OVER"])
	# THE number the headless suite's guarantee rests on. `ui_smoke` adds
	# `CARD_EDGE_MARGIN` to bound 1 so that a green model implies a passing
	# picture; that margin is only honest while it covers this.
	var m: float = proxy.CARD_EDGE_MARGIN
	# four decimals, not three: this is the number `CARD_EDGE_MARGIN` is SET to,
	# and a constant quoted at the same precision as the thing it must exceed can
	# land a thousandth under it. The rest of the table stays at three.
	print("LEGIBILITY BOUND1 worst OPTIMISTIC bias (proxy above render) %+.4f at %s "
			% [worst_hi, worst_hi_what]
			+ "vs ui_smoke.CARD_EDGE_MARGIN %.4f %s"
			% [m, "COVERED" if worst_hi <= m else "MARGIN TOO SMALL"])
	# the bounds are read off `ui_smoke` and not restated — a tool that carried
	# its own copy of the floor could report OK against a bar the suite no
	# longer holds
	var f_card: float = proxy.CARD_EDGE_FLOOR
	var f_mist: float = proxy.MIST_EDGE_FLOOR
	var f_cover: float = proxy.MIST_COVER_CAP
	print("LEGIBILITY BOUND1 card-backed edge worst real %.3f:1 at %s (floor %.2f) %s"
			% [worst_card, worst_card_what, f_card,
			"OK" if worst_card >= f_card else "FAIL"])
	print("LEGIBILITY BOUND3 mist-backed edge worst real %.3f:1 at %s (floor %.2f) %s"
			% [worst_mist, worst_mist_what, f_mist,
			"OK" if worst_mist >= f_mist else "FAIL"])
	print("LEGIBILITY BOUND2 mist cover worst real %.1f%% at %s (cap %.1f%%) %s"
			% [worst_cover * 100.0, worst_cover_what, f_cover * 100.0,
			"OK" if worst_cover <= f_cover else "FAIL"])
	# Per bound, because they are in genuinely different states and one verdict
	# for both was hiding it. Bound 1 is reconciled: the model carries the draw
	# geometry now and agrees with the picture inside DELTA_MAX. Bound 3 is not,
	# and cannot be from here — its residual is `edge_rgb` being ONE colour for a
	# whole band when the veil stands on a specific piece of it, which is a
	# change to what `tools/enemy_cutout.py` measures.
	print("LEGIBILITY BOUND1 %s" % ("CALIBRATED" if worst_d1 <= DELTA_MAX
			else "PROXY NEEDS FIXING"))
	print("LEGIBILITY BOUND3 %s" % ("CALIBRATED" if worst_d3 <= DELTA_MAX
			else "PROXY IS AN INDICATOR ONLY — THIS RENDER IS THE INSTRUMENT OF RECORD"))

	# ── the lever, priced ──
	# `edge = src.a * (1 - amin)` is a function of `rim_px`: a longer ray leaves
	# the silhouette from deeper in the band. So what `rim_px` buys is measurable,
	# and it is measured here rather than reasoned about — the worst row of EACH
	# failing bound is re-rendered across the sweep and read back the same way.
	# Both rows are swept even when one bound passes, because the question the
	# sweep answers is where the lever saturates, and that is what says whether a
	# bound is reachable at all.
	for what in [["BOUND1", worst_card_row], ["BOUND3", worst_mist_row]]:
		var row: Array = what[1]
		if row.is_empty():
			continue
		var k: String = row[0]
		var ch2: int = row[1]
		var ti: int = row[2]
		var bx: Vector2 = row[3]
		for rp in [3.0, 6.0, 7.0, 8.0, 9.0, 12.0]:
			# bound 1 off the small card (the box the player gets), bound 3 off
			# the native render (the only one with enough veiled pixels to mean
			# anything) — the same rulers the table above uses
			var sm: Dictionary = await _measure(k, ti, ch2, bx, rp)
			var nt: Dictionary = await _measure(k, ti, ch2, bx, rp, true)
			print(("LEGIBILITY LEVER %s %s ch%d rim_px=%4.1f edge=%.3f "
					+ "card=%.3f:1 (floor %.2f) mist=%.3f:1 n=%d (floor %.2f)")
					% [what[0], k, ch2, rp, float(proxy.rim_coverage(k, rp)),
					sm["card"], float(proxy.CARD_EDGE_FLOOR),
					nt["mist"] if int(nt["mist_n"]) > 0 else nt["card"],
					int(nt["mist_n"]), float(proxy.MIST_EDGE_FLOOR)])

	# ── the second-order cost of a wider rim ──
	# A rim is light taken off the painting. `rim_px` is a fixed TEXEL radius, so
	# doubling it eats a fixed number of texels inward on every plate — which is a
	# far bigger fraction of a small plate than of a large one, and the plates run
	# 266x143 (E02) to 808x448 (E05). Nothing in the contrast numbers above can
	# see this: they measure the band, and the band is where the rim is supposed
	# to be. This is the number that says how much of the CREATURE it has reached.
	for key in MINIONS + BOSSES:
		var a3 := _rim_area(key, 3.0)
		var a6 := _rim_area(key, float(PawnArt.ROT_RIM_PX))
		print(("LEGIBILITY RIMAREA %-4s plate=%dx%d body=%d px "
				+ "half-lit rim_px=3 %5.1f%% -> rim_px=%.0f %5.1f%% (x%.2f) "
				+ "| mean edge %.3f -> %.3f | inward reach %.1f%% of short side")
				% [key, int(a3["w"]), int(a3["h"]), int(a3["solid"]),
				float(a3["frac"]) * 100.0, float(PawnArt.ROT_RIM_PX),
				float(a6["frac"]) * 100.0,
				float(a6["frac"]) / maxf(float(a3["frac"]), 0.0001),
				float(a3["mean"]), float(a6["mean"]),
				100.0 * float(PawnArt.ROT_RIM_PX) / float(mini(int(a3["w"]), int(a3["h"])))])

	# `proxy.seen_edge` -> `_screen_band` -> `_art_box` builds a SECOND bare
	# `screen_battle` inside `ui_smoke` for its card metrics. Only
	# `_t_enemy_legibility` used to free it, so running this tool leaked one
	# Control and printed a leak warning into the very log that gets grepped.
	proxy.free_render_model()
	proxy.free()
	battle.free()
	get_tree().quit()


## How much of the silhouette the rim now stands on, at one `rim_px`.
##
## `solid` is the shader's own gate (`src.a > 0.2`) — every pixel the rim is
## allowed to touch. A pixel counts as rim if `edge = src.a * (1 - amin)` reaches
## HALF, i.e. the `mix()` has moved it at least half of `rim_strength` of the way
## to `ROT_RIM`; below that the plate's own paint still dominates. `mean` is the
## same `edge` averaged over the whole silhouette rather than over the band, so
## it says how much of the painting has been re-lit at all.
##
## Deliberately NOT the band: `rim_coverage()` already reports the band mean, and
## the band is where the rim belongs. What a wider rim costs is measured by how
## far past the band it reaches.
func _rim_area(key: String, r: float) -> Dictionary:
	var pa := _plate_alpha(key)
	var w := int(pa["w"])
	var h := int(pa["h"])
	var a: PackedFloat32Array = pa["a"]
	var ox := PackedFloat32Array()
	var oy := PackedFloat32Array()
	for i in 8:
		var ang := float(i) * 0.7853981
		ox.append(cos(ang) * r)
		oy.append(sin(ang) * r)
	var solid := 0
	var lit := 0
	var acc := 0.0
	for y in h:
		var row := y * w
		for x in w:
			var src_a := a[row + x]
			if src_a <= 0.2:
				continue
			solid += 1
			var amin := 1.0
			for i in 8:
				amin = minf(amin, proxy._bilinear_a(a, w, h,
						float(x) + ox[i], float(y) + oy[i]))
			var e := src_a * (1.0 - amin)
			acc += e
			if e >= 0.5:
				lit += 1
	return {"w": w, "h": h, "solid": solid,
			"frac": float(lit) / maxf(float(solid), 1.0),
			"mean": acc / maxf(float(solid), 1.0)}


## The SMALLEST art box the battle screen can hand this key — four minions up,
## or a boss (height-bound by the enemy band budget in every layout, so all of
## its boxes agree). Read off `screen_battle` rather than restated, so a retuned
## card layout moves this measurement with it.
##
## Only the smallest, because every bound here is a FLOOR and the smallest box
## is also the most minified. The largest box used to be measured alongside as
## scale evidence; that question was answered in round 1 (over a 2–2.2x scale
## change the ratio moved by at most 0.05) and the second render was dropped
## rather than left running unread. `_measure`'s `p_native` covers what is still
## needed from a bigger draw — sample count for bound 3.
func _box(key: String) -> Vector2:
	var m: Dictionary = battle._enemy_metrics(4, PawnArt.is_boss(key))
	return Vector2(float(m["w"]) - 2.0 * UIKit.S3, float(m["art"]))


## Renders one pawn on its chapter card at one box size and reads the band back.
##
## Returns `card` (the band's mean colour against the card, bound 1's real
## counterpart), `mist` (the mean over the band pixels a wisp is behind, against
## the MEASURED mist background, bound 3's), `cover` (what fraction of the band
## those are, bound 2's), the two backgrounds as they were actually rendered
## (`card_seen`, `mist_bg_c`) with their sample counts, plus the draw `scale`,
## the band's pixel count and the three-ring split.
##
## `p_dim` renders the same thing as a NON-TARGET card during targeting: the card
## and the pawn go under one Control carrying `DIM_MODULATE`, over the chapter's
## arena colour, because that modulate has an alpha and 15% of whatever is behind
## the card comes through with it. Both the silhouette and its background move,
## so both are read off the picture.
func _measure(key: String, tier: int, chapter: int, box: Vector2,
		p_rim_px := -1.0, p_native := false,
		p_dim := Color(0, 0, 0, 0)) -> Dictionary:
	var dimmed := p_dim.a > 0.0
	var tex := PawnArt.enemy_texture(key)
	var body_h := PawnArt.fit_height(key, box)
	if p_native:
		# draw scale exactly 1.0 — one screen pixel per texel
		body_h = float(tex.get_height()) / maxf(PawnArt.bulk(key, tier), 0.001)
	var h := body_h * PawnArt.bulk(key, tier)
	var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	var vw := int(ceil(w)) + PAD * 2
	var vh := int(ceil(h)) + PAD * 2
	var origin := Vector2(float(PAD) + w * 0.5, float(PAD) + h)

	for c in sub.get_children():
		sub.remove_child(c)
		c.queue_free()
	sub.size = Vector2i(vw, vh)
	var host: Node = sub
	if dimmed:
		# the arena the card stands on, so the modulate's 0.85 alpha has something
		# real to let through. `Forest.scenery` paints a whole scene over this and
		# its local colour varies; `UITheme.bg(chapter)` is that scene's ground
		# tone, and it is the BRIGHT end of what can be behind a card, which is the
		# pessimistic direction for a contrast taken against it.
		var arena := ColorRect.new()
		arena.color = UITheme.bg(chapter)
		arena.size = Vector2(vw, vh)
		sub.add_child(arena)
		var holder := Control.new()
		holder.modulate = p_dim
		sub.add_child(holder)
		host = holder
	var card := ColorRect.new()
	card.color = UITheme.surface(chapter)
	card.size = Vector2(vw, vh)
	host.add_child(card)
	var pa := PawnArt.make(key, body_h, false, tier, chapter)
	pa.position = origin
	host.add_child(pa)
	# Pin the stepped idle frame. `_t` and `_bob_seed` are the only state the
	# bob and the wisp phases read, so zeroing both and stopping `_process` puts
	# the render on frame 0 (`bob = 0`, `wisp_phase(i, 0)`) every time — the
	# measurement has to be reproducible, and a free-running idle would sample a
	# different instant on every run.
	pa.set_process(false)
	pa._t = 0.0
	pa._bob_seed = 0.0
	if p_rim_px > 0.0 and pa.material is ShaderMaterial:
		(pa.material as ShaderMaterial).set_shader_parameter("rim_px", p_rim_px)
	pa.queue_redraw()
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()

	# ── which screen pixels are "the edge" ──
	# The band `edge_rgb` was averaged over, taken from `ui_smoke` itself, then
	# projected: a screen pixel counts if the texel it samples is in the band.
	# Not a screen-space silhouette test — the wisps reach slightly outside the
	# plate's footprint (centres at 0.368w, swaying 0.092h and swelling 0.048h),
	# so a colour or alpha test in screen space would hand back smoke as
	# silhouette and then measure a contour that is not there.
	var band_info: Dictionary = proxy._edge_band(key)
	var tw := int(band_info["w"])
	var th := int(band_info["h"])
	var mask: PackedByteArray = band_info["px"]
	var ring: PackedByteArray = _rings(key)["px"]
	var polys := _wisp_polys(key, tier, w, h)
	var plate_a: PackedFloat32Array = _plate_alpha(key)["a"]

	# ── the two backgrounds, off the picture ──
	# The card first, because on an undimmed run its answer is already known and
	# that makes it a check on everything else: these pixels have to come back as
	# `UITheme.surface(chapter)`. On a dimmed run it is the only way to know what
	# the card became, since the modulate moves the background and the silhouette
	# together.
	var seen_card: Dictionary = _sample_card(img, vw, vh, origin, w, h, polys)
	var card_bg: Color = seen_card["c"] if dimmed else UITheme.surface(chapter)
	# Then the mist. This used to be `proxy.card_behind()` — the model — which
	# left the one quantity that distinguishes bound 3 from bound 1 as the one
	# quantity never read off the render.
	var seen_mist: Dictionary = _sample_mist(img, polys, origin, w, h, tw, th, plate_a)
	var mist_n_bg := int(seen_mist["n"])
	var mist_bg: Color = proxy.card_behind(chapter, key, tier)
	var mist_bg_src := "modelled"
	if not dimmed:
		# a dimmed render's mist is a different colour and must never land in the
		# shared cache, which is why this whole branch is skipped there
		var mbk := "%d/%.6f" % [chapter, PawnArt.mist_alpha(key, tier)]
		if mist_n_bg > 0:
			mist_bg = seen_mist["c"]
			mist_bg_src = "measured"
			_mist_bg_cache[mbk] = mist_bg
		elif _mist_bg_cache.has(mbk):
			mist_bg = _mist_bg_cache[mbk]
			mist_bg_src = "measured on another row of the same chapter and mist_alpha"

	var n_card := 0
	var n_mist := 0
	var acc_card := Color(0, 0, 0)
	var acc_mist := Color(0, 0, 0)
	var n_ring := [0, 0, 0]
	var acc_ring := [Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)]
	for py in vh:
		var ly := float(py) + 0.5 - origin.y
		var v := (ly + h) / h
		if v < 0.0 or v >= 1.0:
			continue
		var ty := clampi(int(v * float(th)), 0, th - 1) * tw
		for px in vw:
			var lx := float(px) + 0.5 - origin.x
			var u := (lx + w * 0.5) / w
			if u < 0.0 or u >= 1.0:
				continue
			var t := ty + clampi(int(u * float(tw)), 0, tw - 1)
			if mask[t] == 0:
				continue
			var veiled := false
			for poly in polys:
				if Geometry2D.is_point_in_polygon(Vector2(lx, ly), poly):
					veiled = true
					break
			var c2 := img.get_pixel(px, py)
			if veiled:
				n_mist += 1
				acc_mist += c2
			else:
				n_card += 1
				acc_card += c2
				var r := int(ring[t])
				if r >= 1 and r <= 3:
					n_ring[r - 1] += 1
					acc_ring[r - 1] += c2

	var out := {
		"scale": h / maxf(float(tex.get_height()), 1.0),
		"band_n": n_card + n_mist,
		"mist_n": n_mist,
		"cover": float(n_mist) / maxf(float(n_card + n_mist), 1.0),
		"card": 0.0,
		"mist": 0.0,
		"card_c": card_bg,
		"card_seen": seen_card["c"],
		"card_seen_n": int(seen_card["n"]),
		"mist_bg_c": mist_bg,
		"mist_bg_n": mist_n_bg,
		"mist_bg_src": mist_bg_src,
	}
	var rings := []
	for i in 3:
		rings.append(UITheme.contrast(_mean(acc_ring[i], maxi(int(n_ring[i]), 1)), card_bg)
				if int(n_ring[i]) > 0 else 0.0)
	out["rings"] = rings
	if n_card > 0:
		out["card_c"] = _mean(acc_card, n_card)
		out["card"] = UITheme.contrast(out["card_c"], card_bg)
	if n_mist > 0:
		out["mist"] = UITheme.contrast(_mean(acc_mist, n_mist), mist_bg)
	return out


## The card AS RENDERED, averaged over the `PAD` ring outside the plate's own
## draw rect — the only pixels in the viewport with nothing but card behind them.
## Anything a wisp's bounding box touches is skipped: `_auto_mist` puts the
## wisps' centres at 0.368w and they sway 0.092h, so on a native-scale render
## smoke does reach into the pad.
##
## On an undimmed run this is a CHECK, not an input — the answer has to be
## `UITheme.surface(chapter)` and the run prints how far off it is. On a dimmed
## run it is the background the contrast is taken against, because the modulate
## moved it.
func _sample_card(img: Image, vw: int, vh: int, origin: Vector2,
		w: float, h: float, polys: Array) -> Dictionary:
	var bbs := []
	for poly in polys:
		bbs.append(_poly_bounds(poly).grow(1.0))
	var acc := Color(0, 0, 0)
	var n := 0
	for py in vh:
		var ly := float(py) + 0.5 - origin.y
		var border_y := py < PAD or py >= vh - PAD
		for px in vw:
			if not border_y and px >= PAD and px < vw - PAD:
				continue
			var pt := Vector2(float(px) + 0.5 - origin.x, ly)
			var hit := false
			for b in bbs:
				if (b as Rect2).has_point(pt):
					hit = true
					break
			if hit:
				continue
			acc += img.get_pixel(px, py)
			n += 1
	return {"c": _mean(acc, maxi(n, 1)), "n": n}


## The mist background AS RENDERED — `ROT_MIST` composited over the card by the
## engine, which is what bound 3 is measured against.
##
## The render contains the pixels that settle it: anywhere a wisp polygon covers
## a spot the plate contributes NOTHING to, the frame buffer holds exactly
## `draw_colored_polygon(ROT_MIST at mist_alpha)` over `surface(chapter)`, blended
## the way the engine blends it. Three conditions, all of them there to make the
## sample the same thing `card_behind()` claims to model:
##   • the plate's bilinear tap at that fragment is zero, so no silhouette and no
##     anti-aliased skirt is mixed in;
##   • the pixel is wholly inside ONE wisp — all four of its corners are in the
##     polygon. `draw_colored_polygon` performs no anti-aliasing and this project
##     sets no `msaa_2d`, so a covered pixel is fully covered and an uncovered one
##     is untouched; the corner test is only there because the rasteriser's fill
##     rule and `is_point_in_polygon` can still disagree about a pixel the
##     boundary crosses;
##   • no second wisp is over it, because `card_behind()` models ONE flat layer
##     and a doubled alpha is a different colour.
## Scanned per wisp over that wisp's own bounding box, not over the viewport.
func _sample_mist(img: Image, polys: Array, origin: Vector2, w: float, h: float,
		tw: int, th: int, a: PackedFloat32Array) -> Dictionary:
	var acc := Color(0, 0, 0)
	var n := 0
	var vw := img.get_width()
	var vh := img.get_height()
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		var bb := _poly_bounds(poly)
		var x0 := maxi(int(floor(bb.position.x + origin.x)) - 1, 0)
		var x1 := mini(int(ceil(bb.end.x + origin.x)) + 1, vw)
		var y0 := maxi(int(floor(bb.position.y + origin.y)) - 1, 0)
		var y1 := mini(int(ceil(bb.end.y + origin.y)) + 1, vh)
		for py in range(y0, y1):
			var ly := float(py) + 0.5 - origin.y
			for px in range(x0, x1):
				var lx := float(px) + 0.5 - origin.x
				if not Geometry2D.is_point_in_polygon(Vector2(lx, ly), poly):
					continue
				if not (Geometry2D.is_point_in_polygon(Vector2(lx - 0.5, ly - 0.5), poly)
						and Geometry2D.is_point_in_polygon(Vector2(lx + 0.5, ly - 0.5), poly)
						and Geometry2D.is_point_in_polygon(Vector2(lx - 0.5, ly + 0.5), poly)
						and Geometry2D.is_point_in_polygon(Vector2(lx + 0.5, ly + 0.5), poly)):
					continue
				var doubled := false
				for j in polys.size():
					if j != i and Geometry2D.is_point_in_polygon(Vector2(lx, ly), polys[j]):
						doubled = true
						break
				if doubled:
					continue
				var u := (lx + w * 0.5) / w
				var v := (ly + h) / h
				if u >= 0.0 and u < 1.0 and v >= 0.0 and v < 1.0:
					if proxy._bilinear_a(a, tw, th, u * float(tw) - 0.5,
							v * float(th) - 0.5) > 0.0005:
						continue
				acc += img.get_pixel(px, py)
				n += 1
	return {"c": _mean(acc, maxi(n, 1)), "n": n}


## Axis-aligned bounds of a polygon, in the pawn's own drawing space.
func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


func _mean(acc: Color, n: int) -> Color:
	return Color(acc.r / float(n), acc.g / float(n), acc.b / float(n))


## The rim's own `edge` scalar averaged over the band — `src.a * (1 - amin)` — at
## the radius the game ships (`PawnArt.ROT_RIM_PX`), plus the band's mean alpha,
## which is what the final `vec4(lit, src.a)` composites the lit colour over the
## card with.
##
## The scalar itself is NOT computed here: `proxy.rim_coverage()` is, and this
## asks it. That function is the one `lit_edge` now multiplies by, so asking it
## keeps the tool honest — if the proxy's model of `edge` were wrong, this column
## would show the same wrongness instead of quietly hiding it behind a second,
## correct implementation. What checks the model against the picture is the
## independent `s_eff`/`cov` fit, which comes out of the rendered pixels and
## touches none of this.
##
## Only the shipping radius. What the OTHER radii are worth is a rendered
## question, not a modelled one, and `LEGIBILITY LEVER` answers it by re-rendering
## the worst row of each bound at 3 / 6 / 7 / 8 / 9 / 12.
func _shader_edge(key: String) -> Dictionary:
	if _edge_cache.has(key):
		return _edge_cache[key]
	var band_info: Dictionary = proxy._edge_band(key)
	var w := int(band_info["w"])
	var h := int(band_info["h"])
	var mask: PackedByteArray = band_info["px"]
	var a: PackedFloat32Array = _plate_alpha(key)["a"]
	var acc_a := 0.0
	var n := 0
	for y in h:
		var row := y * w
		for x in w:
			if mask[row + x] == 0:
				continue
			acc_a += a[row + x]
			n += 1
	var out := {
		"edge": float(proxy.rim_coverage(key)),
		"alpha": acc_a / maxf(float(n), 1.0),
	}
	_edge_cache[key] = out
	return out


## The band split into its three one-texel rings, outermost first — `1` for the
## ring against the `alpha > 200` boundary, `3` for the innermost. The rim decays
## across these (an outward ray at radius 3 texels leaves the silhouette from
## ring 1 and barely does from ring 3), and `edge_rgb` averages over all three,
## so a legibility number quoted for the band as a whole is not the number for
## the outer contour a player's eye actually traces. Both are printed.
##
## Three successive 3x3 erosions, which is the operator `enemy_cutout.py` uses
## (`binary_erosion(solid, ones((3,3)), iterations=3)`); their union is by
## construction the same band `proxy._edge_band` returns.
func _rings(key: String) -> Dictionary:
	if _ring_cache.has(key):
		return _ring_cache[key]
	var pa := _plate_alpha(key)
	var w := int(pa["w"])
	var h := int(pa["h"])
	var a: PackedFloat32Array = pa["a"]
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 if a[i] > 200.0 / 255.0 else 0
	var e1 := _erode(solid, w, h)
	var e2 := _erode(e1, w, h)
	var e3 := _erode(e2, w, h)
	var ring := PackedByteArray()
	ring.resize(w * h)
	for i2 in w * h:
		if solid[i2] == 1 and e1[i2] == 0:
			ring[i2] = 1
		elif e1[i2] == 1 and e2[i2] == 0:
			ring[i2] = 2
		elif e2[i2] == 1 and e3[i2] == 0:
			ring[i2] = 3
	var out := {"w": w, "h": h, "px": ring}
	_ring_cache[key] = out
	return out


## One 3x3 erosion, separable (a square structuring element is), with the border
## padded as background exactly as `scipy`'s `border_value=0` does.
func _erode(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var run := PackedInt32Array()
	run.resize(w * h)
	var eh := PackedByteArray()
	eh.resize(w * h)
	for y in h:
		var row := y * w
		var c := 0
		for x in w:
			c = c + 1 if m[row + x] == 1 else 0
			run[row + x] = c
		for x2 in w:
			eh[row + x2] = 1 if (x2 >= 1 and x2 + 1 < w and run[row + x2 + 1] >= 3) else 0
	for x3 in w:
		var c2 := 0
		for y2 in h:
			c2 = c2 + 1 if eh[y2 * w + x3] == 1 else 0
			run[y2 * w + x3] = c2
	var out := PackedByteArray()
	out.resize(w * h)
	for y3 in h:
		var row2 := y3 * w
		if y3 < 1 or y3 + 1 >= h:
			continue
		var ahead := (y3 + 1) * w
		for x4 in w:
			out[row2 + x4] = 1 if run[ahead + x4] >= 3 else 0
	return out


## The plate's alpha channel as floats, once per key.
func _plate_alpha(key: String) -> Dictionary:
	if _alpha_cache.has(key):
		return _alpha_cache[key]
	var img := PawnArt.enemy_texture(key).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var a := PackedFloat32Array()
	a.resize(w * h)
	for i in w * h:
		a[i] = float(d[i * 4 + 3]) / 255.0
	var out := {"w": w, "h": h, "a": a}
	_alpha_cache[key] = out
	return out


## The rim strength that WOULD have produced the colour the render actually put
## down — `lit_edge`'s own blend, bisected on luminance (monotone in the blend
## factor, where `contrast` is V-shaped and cannot be bisected).
##
## Reported as a fraction of `rot_rim_for(chapter)`, which is the coverage factor
## the proxy is missing.
func _fit_strength(edge: Color, chapter: int, got: Color) -> float:
	var want := UITheme.luminance(got)
	if want <= UITheme.luminance(proxy.lit_edge(edge, chapter, 0.0)):
		return 0.0
	var lo := 0.0
	var hi := 1.0
	for _i in 30:
		var mid := (lo + hi) * 0.5
		if UITheme.luminance(proxy.lit_edge(edge, chapter, mid)) >= want:
			hi = mid
		else:
			lo = mid
	return hi


## The wisps `_auto_mist` lays down for this key at this tier, as polygons in the
## pawn's own drawing space. `PawnArt`'s statics hand back the very geometry
## `_wisp` draws, so there is one copy of it and this cannot drift from the
## picture — the same arrangement `ui_smoke.mist_coverage` uses.
##
## Frame 0 only, matching the pinned render. `mist_coverage` takes the worse of
## the two stepped frames; the two differ by which wisp leans where, not by how
## much smoke there is, so the fraction this returns is frame 0's and the proxy's
## is the max — see the `cover` columns.
func _wisp_polys(key: String, tier: int, w: float, h: float) -> Array:
	var spots := PawnArt.mist_spots(key, tier, w, h)
	var polys := []
	for i in spots.size():
		var s: Array = spots[i]
		polys.append(PawnArt.wisp_outline(Vector2(float(s[0]), float(s[1])),
				float(s[2]), PawnArt.wisp_phase(i, 0.0)))
	return polys


