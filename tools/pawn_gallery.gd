extends Node
## Shoots every enemy design on the surface it actually fights on, one file per
## pawn, so the round can be reviewed creature by creature instead of by
## squinting at a battle screenshot.
##
##   Godot --path . --log-file art_export/pawns.log tools/pawn_gallery.tscn -- --out res://art_iterations/rot_1/
##
## 10 minions x 3 tiers + 6 bosses (Sir Croak twice, mounted and afoot) = 37
## stills, plus one contact sheet per tier and one for the bosses.
##
## Each still is composed the way the game composes it: the chapter sky, an
## enemy card of `UITheme.surface(chapter)` on top of it, and the pawn standing
## on the card. That is the pairing the art has to survive — a creature that
## reads beautifully on white is worth nothing here.
##
## Must run with a real window: the grab awaits RenderingServer.frame_post_draw,
## which never fires headless.

const MINIONS := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10"]
## Which chapter each boss is met in — its surface, and so its contrast test.
const BOSS_CHAPTER := {"B1": 1, "B2": 1, "B3": 2, "B3P2": 2, "B4": 2, "B5": 3, "B6": 3}
const BOSSES := ["B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]

const CELL := Vector2i(300, 340)
const TIMEOUT_S := 600.0

var out_dir := "res://art_iterations/rot_1/"
var sub: SubViewport
var shot_count := 0
var done := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		if not done:
			push_warning("pawn_gallery timed out after %d shots" % shot_count)
			get_tree().quit())
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = String(a[i + 1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	sub = SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	# ---- one file per pawn
	for tier in [1, 2, 3]:
		for key in MINIONS:
			await _shoot_one(key, tier, tier)
	for bkey in BOSSES:
		await _shoot_one(bkey, 3, int(BOSS_CHAPTER[bkey]))

	# ---- contact sheets, for judging a tier as a set
	for tier2 in [1, 2, 3]:
		await _shoot_sheet("sheet_t%d" % tier2, MINIONS, tier2, tier2, 5)
	await _shoot_sheet("sheet_boss", BOSSES, 3, -1, 4)

	done = true
	print("PAWNS: DONE ", shot_count, " shots")
	get_tree().quit()


## The composition every still and every sheet cell uses: chapter sky, card,
## pawn standing on the card floor, key printed underneath.
func _cell(key: String, tier: int, chapter: int, size: Vector2i) -> Control:
	var root := Control.new()
	root.size = Vector2(size)
	var sky := ColorRect.new()
	sky.color = UITheme.bg(chapter)
	sky.size = Vector2(size)
	root.add_child(sky)

	var inset := 18.0
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UIKit.card_box(UITheme.surface(chapter),
			UITheme.R_LG, UITheme.B_STRONG, UITheme.OUTLINE, 0))
	card.position = Vector2(inset, inset)
	card.size = Vector2(size) - Vector2(inset * 2.0, inset * 2.0 + 26.0)
	root.add_child(card)

	var box := card.size - Vector2(24, 42)
	var art := PawnArt.fitted(key, box, true, tier)
	art.position = card.position + Vector2(card.size.x * 0.5, card.size.y - 18.0)
	root.add_child(art)

	var label := UIKit.label("%s  T%d  ch%d" % [key, tier, chapter],
			UITheme.F_CAPTION, UITheme.CREAM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(float(size.x), 22)
	label.position = Vector2(0, float(size.y) - 24.0)
	root.add_child(label)
	return root


func _shoot_one(key: String, tier: int, chapter: int) -> void:
	sub.size = CELL
	await _mount(_cell(key, tier, chapter, CELL))
	await _grab("%s_t%d" % [key.to_lower(), tier])


func _shoot_sheet(name: String, keys: Array, tier: int, chapter: int, cols: int) -> void:
	var rows := int(ceil(float(keys.size()) / float(cols)))
	sub.size = Vector2i(CELL.x * cols, CELL.y * rows)
	var root := Control.new()
	for i in keys.size():
		var key := String(keys[i])
		var ch := chapter if chapter > 0 else int(BOSS_CHAPTER.get(key, 1))
		var c := _cell(key, tier, ch, CELL)
		c.position = Vector2((i % cols) * CELL.x, (i / cols) * CELL.y)
		root.add_child(c)
	await _mount(root)
	await _grab(name)


func _mount(node: Control) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 6:
		await get_tree().process_frame


func _grab(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	sub.get_texture().get_image().save_png(
			ProjectSettings.globalize_path(out_dir) + name + ".png")
	shot_count += 1
	print("PAWN ", name)
