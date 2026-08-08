extends Node
## Re-verifies `PawnArt.EXTENT` against what the plates actually render to.
##
## Every creature is a sprite now, trimmed to its own alpha bounds, so `EXTENT`
## is no longer something this tool discovers — it is derived offline by
## `tools/art_cutout.py` (heroes) and `tools/enemy_cutout.py` (enemies), which
## print it from the same alpha bounds they trim to. What this tool does is
## catch the ways that pasted block goes stale: a plate re-cut without
## re-pasting, or a block pasted into the wrong key.
##
##   Godot --path . --log-file art_export/extents.log tools/pawn_extents.tscn
##
## Must run with a real window: the grab awaits RenderingServer.frame_post_draw,
## which never fires headless.
##
## **The measurement is divided by `PawnArt.bulk()` before it is printed.** A
## rendered pawn carries its tier's body scale (0.90 / 1.00 / 1.12) and `EXTENT`
## does not — `fit_height` divides that back out via `max_bulk`. Comparing the
## raw render against `EXTENT` would report every minion as 12% too big at tier
## 3, and "fixing" that by pasting the raw numbers back would shrink every
## tier-3 minion to ~89% of its size. So the numbers below are per-tier
## measurements normalised to the same unit `EXTENT` is written in: all three
## tiers of one creature should print the same pair, and that pair should be the
## `EXTENT` row.
##
## The printed `PAWN_EXTENT:` block is a reference at this measurement's own
## resolution (a pixel is 0.005 of `H`, so it is good to ~0.01), not the
## authority. If it disagrees with `EXTENT`, re-run the cutout script for that
## plate and paste its block — do not paste this one.

const H := 200.0
const PAD := 320
## Tolerance for the comparison: pixel quantisation at `H` is 0.005 and each
## number is snapped to 0.01, so anything under 0.02 is measurement noise.
const TOL := 0.02

## Which tier's normalised measurement goes into the printed block. Any tier
## would do now that the bulk is divided out; tier 3 is the largest render, so
## it is the one where a pixel of quantisation costs the least.
const MEASURE_TIER := 3

var kinds: Array = []


func _ready() -> void:
	kinds = PawnArt.EXTENT.keys()
	var sub := SubViewport.new()
	sub.size = Vector2i(PAD * 2, PAD * 2)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = true
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	var out := {}
	for k in kinds:
		for t in [1, 2, 3]:
			var m := await _measure(sub, k, t)
			if t == MEASURE_TIER:
				out[k] = m
			print("  %-5s T%d  up %.2f  half %.2f   (drawn at bulk %.2f)"
					% [k, t, m[0], m[1], PawnArt.bulk(k, t)])

	var parts := []
	for k2 in kinds:
		parts.append('"%s": Vector2(%.2f, %.2f)' % [k2, out[k2][0], out[k2][1]])
	print("PAWN_EXTENT: {", ", ".join(parts), "}")

	# The plates are trimmed to their own alpha bounds, so the measured extent
	# has to agree with what `PawnArt.EXTENT` was told. A mismatch means the
	# block printed by the cutout script was pasted wrong, or a plate was re-cut
	# without re-pasting.
	var bad := 0
	for k3 in kinds:
		var have: Vector2 = PawnArt.extent(k3)
		var got: Array = out[k3]
		if absf(have.x - float(got[0])) > TOL or absf(have.y - float(got[1])) > TOL:
			bad += 1
			print("  MISMATCH %-5s EXTENT=(%.2f, %.2f) measured=(%.2f, %.2f)"
					% [k3, have.x, have.y, got[0], got[1]])
	print("EXTENTS: %d kinds, %d mismatches" % [kinds.size(), bad])
	get_tree().quit()


## One plate at one tier: how far above the feet it reaches and its half-width,
## both as a fraction of the height it was asked for, with the tier's body scale
## divided back out so the pair is directly comparable to `PawnArt.EXTENT`.
func _measure(sub: SubViewport, k: String, t: int) -> Array:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	var pa := PawnArt.make(k, H, false, t)
	pa.position = Vector2(PAD, PAD)   # feet at the centre of the canvas
	sub.add_child(pa)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var rect := img.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return [1.0, 0.5]
	# `H * bulk` is the height the pawn was actually drawn at (`PawnArt._draw`),
	# which is the unit `EXTENT` is a fraction of.
	var drawn := H * PawnArt.bulk(k, t)
	var up := float(PAD - rect.position.y) / drawn
	var half := maxf(float(PAD - rect.position.x),
			float(rect.position.x + rect.size.x - PAD)) / drawn
	return [snappedf(up, 0.01), snappedf(half, 0.01)]
