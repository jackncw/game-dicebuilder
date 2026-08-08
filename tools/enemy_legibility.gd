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
##   3. where it does stand, the edge still reaches `MIST_EDGE_FLOOR` (1.9:1)
##      against mist-over-card.
## All three are computed from ONE modelled quantity — `lit_edge()`, the plate's
## `edge_rgb` lerped towards `UITheme.ROT_RIM` by `UITheme.rot_rim_for(chapter)`
## — plus `card_behind()` and `mist_coverage()`. So this tool measures the real
## counterpart of each of the three and reports all three deltas; the tolerance
## `DELTA_MAX` is a contrast tolerance and applies to bounds 1 and 3.
##
## The proxy is not re-implemented here. `ui_smoke.gd` is instantiated and its
## own `lit_edge` / `card_behind` / `mist_coverage` are called, so the numbers in
## the `proxy=` column are the numbers the headless suite actually asserts on,
## and there is no second copy to drift.
##
## ── Which size is "the picture" ──────────────────────────────────
## `rim_px` is in TEXTURE pixels (`rot_pawn.gdshader` multiplies it by
## `TEXTURE_PIXEL_SIZE`), so the rim's on-screen thickness is `3 × draw scale`,
## and the plates are stored at wildly different resolutions (143px tall to
## 512px). Each key is therefore rendered TWICE: at the smallest and the largest
## box `screen_battle._enemy_metrics()` can hand it. The three bounds are FLOORS,
## so the smallest box is the reconciliation target and the largest box is
## printed alongside as evidence of how far the number moves with scale.
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
## In SCREEN pixels that band is `3 x draw scale` wide, which is the whole
## minification story: at scale 1.04 it is three pixels, at 0.12 it is a third of
## one, and one screen pixel then averages eight texels of which at most three
## are lit.
const DELTA_MAX := 0.15
const PAD := 10

var meta := {}
var sub: SubViewport
var proxy: Node          ## a live `tests/ui_smoke.gd`, used as the model
var battle: Control      ## a live `screen_battle.gd`, used for the card metrics
var _alpha_cache := {}
var _edge_cache := {}
var _ring_cache := {}


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
	var worst_delta := 0.0
	var worst_what := ""
	var worst_card := 99.0
	var worst_card_what := ""
	var worst_card_row := []
	var worst_mist := 99.0
	var worst_mist_what := ""
	var worst_mist_row := []
	var worst_cover := -1.0
	var worst_cover_what := ""

	for key in MINIONS + BOSSES:
		var chapters: Array = [int(PawnArt.BOSS_CHAPTER[key])] \
				if PawnArt.BOSS_CHAPTER.has(key) else [1, 2, 3]
		for ch_v in chapters:
			var ch := int(ch_v)
			# a minion's tier IS the chapter it is met in (`battle_core.gd:123`),
			# and `:179` files a boss under `int(def.chapter)` — so on both sides
			# the tier a pawn arrives here carrying is its chapter
			var tier := ch
			var boxes := _boxes(key)
			var small: Dictionary = await _measure(key, tier, ch, boxes[0])
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
			var nat: Dictionary = await _measure(key, tier, ch, boxes[0], -1.0, true)

			var edge_v: Variant = proxy._edge_colour(meta, key)
			var edge: Color = edge_v if edge_v != null else Color.BLACK
			var lit: Color = proxy.lit_edge(edge, ch, -1.0, proxy.rim_coverage(key))
			var card_bg: Color = UITheme.surface(ch)
			var mist_bg: Color = proxy.card_behind(ch, key, tier)
			var p_card: float = UITheme.contrast(lit, card_bg)
			var p_mist: float = UITheme.contrast(lit, mist_bg)
			var p_cover: float = proxy.mist_coverage(key, tier)

			var d_card: float = absf(small["card"] - p_card)
			if d_card > worst_delta:
				worst_delta = d_card
				worst_what = "%s ch%d bound1" % [key, ch]
			var mist_real := 0.0
			var mist_n := 0
			if nat["mist_n"] > 0:
				mist_real = nat["mist"]
				mist_n = int(nat["mist_n"])
			elif int(PawnArt.MIST_COUNT[PawnArt.dial_row(key, tier)]) == 0:
				# no wisps at all: bound 3's background IS the bare card and it
				# collapses onto bound 1, exactly as `card_behind` says it does.
				# Read off the SMALL card, because that is the row bound 1 owns.
				mist_real = small["card"]
				mist_n = int(small["band_n"])
			var mist_txt := "  n/a"
			var d_mist_txt := "  n/a"
			if mist_n > 0:
				var d_mist: float = absf(mist_real - p_mist)
				mist_txt = "%5.3f" % mist_real
				d_mist_txt = "%5.3f" % d_mist
				if d_mist > worst_delta:
					worst_delta = d_mist
					worst_what = "%s ch%d bound3" % [key, ch]
				if mist_real < worst_mist:
					worst_mist = mist_real
					worst_mist_what = "%s ch%d tier%d" % [key, ch, tier]
					worst_mist_row = [key, ch, tier, boxes[0]]

			if small["card"] < worst_card:
				worst_card = small["card"]
				worst_card_what = "%s ch%d tier%d" % [key, ch, tier]
				worst_card_row = [key, ch, tier, boxes[0]]
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
	print("LEGIBILITY WORST-DELTA %.3f at %s (max allowed %.2f)"
			% [worst_delta, worst_what, DELTA_MAX])
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
	print("LEGIBILITY %s" % ("CALIBRATED" if worst_delta <= DELTA_MAX
			else "PROXY NEEDS FIXING"))

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
	return {"w": w, "h": h, "solid": solid, "lit": lit,
			"frac": float(lit) / maxf(float(solid), 1.0),
			"mean": acc / maxf(float(solid), 1.0)}


## The smallest and the largest art box the battle screen can hand this key —
## `[smallest, largest]`. Read off `screen_battle` rather than restated: one
## enemy on screen is the biggest card, four the smallest, and a boss is
## height-bound by the band budget in every layout so both of its boxes agree.
func _boxes(key: String) -> Array:
	var boss := PawnArt.is_boss(key)
	var s: Dictionary = battle._enemy_metrics(4, boss)
	var l: Dictionary = battle._enemy_metrics(1, boss)
	return [Vector2(float(s["w"]) - 2.0 * UIKit.S3, float(s["art"])),
			Vector2(float(l["w"]) - 2.0 * UIKit.S3, float(l["art"]))]


## Renders one pawn on its chapter card at one box size and reads the outermost
## `BAND_PX` screen pixels of its silhouette back.
##
## Returns `card` (the band's mean colour against the bare card, bound 1's real
## counterpart), `mist` (the mean over the band pixels a wisp is behind, against
## `card_behind`, bound 3's), `cover` (what fraction of the band those are,
## bound 2's), plus the draw `scale` and the band's pixel count.
func _measure(key: String, tier: int, chapter: int, box: Vector2,
		p_rim_px := -1.0, p_native := false) -> Dictionary:
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
	var card := ColorRect.new()
	card.color = UITheme.surface(chapter)
	card.size = Vector2(vw, vh)
	sub.add_child(card)
	var pa := PawnArt.make(key, body_h, false, tier, chapter)
	pa.position = origin
	sub.add_child(pa)
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
	var mist_bg: Color = proxy.card_behind(chapter, key, tier)
	var card_bg: Color = UITheme.surface(chapter)

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
		"mist_c": mist_bg,
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
		out["mist_c"] = _mean(acc_mist, n_mist)
		out["mist"] = UITheme.contrast(out["mist_c"], mist_bg)
	return out


func _mean(acc: Color, n: int) -> Color:
	return Color(acc.r / float(n), acc.g / float(n), acc.b / float(n))


## The rim's own `edge` scalar averaged over the band — `src.a * (1 - amin)` —
## at the radius the game ships (`PawnArt.ROT_RIM_PX`) and at the two sweep
## points, plus the band's mean alpha, which is what the final `vec4(lit, src.a)`
## composites the lit colour over the card with.
##
## The scalar itself is NOT computed here: `proxy.rim_coverage()` is, and this
## asks it. That function is the one `lit_edge` now multiplies by, so asking it
## keeps the tool honest — if the proxy's model of `edge` were wrong, this column
## would show the same wrongness instead of quietly hiding it behind a second,
## correct implementation. What checks the model against the picture is the
## independent `s_eff`/`cov` fit, which comes out of the rendered pixels and
## touches none of this.
##
## The `rim_px` 3 / 6 / 9 sweep is the lever, priced. `LEGIBILITY LEVER`
## re-renders the worst row at each so the prediction is checked against the
## picture rather than trusted.
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
		"edge3": float(proxy.rim_coverage(key, 3.0)),
		"edge6": float(proxy.rim_coverage(key, 6.0)),
		"edge9": float(proxy.rim_coverage(key, 9.0)),
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


