extends Node
## Measures how much space each PawnArt design actually occupies relative to
## the `body_h` it was asked for. The designs are hand-drawn per creature and
## several of them (hats, antlers, staves) reach well above their nominal
## height, which is why cards kept colliding with the art.
##
##   Godot --path . --log-file art_export/extents.log tools/pawn_extents.tscn
##
## Prints a GDScript dict ready to paste into PawnArt.EXTENT.

const KINDS := ["HARE", "BADGER", "OWL", "HEDGE", "BOAR", "FOX",
		"E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10",
		"B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]

## Minions are measured at tier 3, the fullest they ever draw — the card is
## sized against the envelope, and the lower tiers sit smaller inside it. The
## per-tier numbers are printed too, so a tier that has quietly grown past the
## envelope is visible rather than silently clipped.
const MEASURE_TIER := 3
const H := 200.0
const PAD := 320


func _ready() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(PAD * 2, PAD * 2)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = true
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	var out := {}
	for k in KINDS:
		for t in [1, 2, 3]:
			var m := await _measure(sub, k, t)
			if t == MEASURE_TIER:
				out[k] = m
			print("  %-5s T%d  up %.2f  half %.2f" % [k, t, m[0], m[1]])

	var parts := []
	for k2 in KINDS:
		parts.append('"%s": Vector2(%.2f, %.2f)' % [k2, out[k2][0], out[k2][1]])
	print("PAWN_EXTENT: {", ", ".join(parts), "}")
	get_tree().quit()


## One design at one tier: how far above the feet it reaches and its half-width,
## both as a fraction of the height it was asked for.
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
	var up := float(PAD - rect.position.y) / H
	var half := maxf(float(PAD - rect.position.x),
			float(rect.position.x + rect.size.x - PAD)) / H
	return [snappedf(up, 0.01), snappedf(half, 0.01)]
