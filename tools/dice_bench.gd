extends Node
## Fast visual bench for the die / glyph / tile work — everything the art pass
## touches on one screen each, so a change can be eyeballed in one command
## instead of a full gallery run.
##
## Must run WITH a window (it awaits frame_post_draw and the dice are 3D):
##   Godot --path . --log-file art_export/dice_bench.log tools/dice_bench.tscn
##
## Shots land in art_export/bench_*.png.

const OUTDIR := "res://art_export/"
const WINDOW := Vector2i(720, 1280)

var root: Control


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	for i in 6:
		await get_tree().process_frame
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	await _sheet_big()
	await _sheet_glyphs()
	await _sheet_dice()
	await _sheet_tiles()
	await _sheet_detail()
	await _sheet_throw()
	await _stress()
	print("BENCH DONE")
	get_tree().quit(0)


func _clear() -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	root.add_child(UIKit.background(1, 90.0, 1120.0))


# ------------------------------------------------------------ sheets

## One die, big, on each of its six faces — for judging the rest pose and
## whether the face that is up actually reads.
func _sheet_big() -> void:
	_clear()
	# synthetic faces numbered 1..6 so the shot says exactly which cube face
	# ended up where, and which way up
	var faces := []
	for i in 6:
		faces.append({"zh": "面%d" % (i + 1), "en": "F%d" % (i + 1),
			"cat": ["attack", "defense", "heal", "resource", "control", "special"][i],
			"atk": i + 1, "target": "enemy", "id": "dbg%d" % i})
	var big: Die3D = null
	for k in 6:
		var dv := Die3D.new(Vector2(220, 220))
		dv.interactive = false
		dv.position = Vector2(20 + (k % 3) * 235.0, 100 + (k / 3) * 250.0)
		root.add_child(dv)
		dv.set_die(faces, k)
		var l := UIKit.outlined(UIKit.label("up=%d" % (k + 1), 20, UITheme.CREAM))
		l.position = dv.position + Vector2(4, -24)
		root.add_child(l)
		big = dv
	await _grab("bench_big")
	# and the raw atlas, so a UV question can be answered by looking rather
	# than by reasoning about which way a viewport's V axis runs
	await RenderingServer.frame_post_draw
	big._atlas_vp.get_texture().get_image().save_png(OUTDIR + "bench_atlas.png")
	print("saved bench_atlas.png")


## Every drawn keyword icon, on its category colour, at the two sizes that
## matter: the 56px main read and the 20px corner badge.
func _sheet_glyphs() -> void:
	_clear()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.position = Vector2(16, 60)
	root.add_child(grid)
	for key in Glyphs.KEYS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var hue := Glossary.hue(key) if Glossary.has(key) else UITheme.ORANGE
		var box := _Swatch.new()
		box.key = key
		box.hue = hue
		box.custom_minimum_size = Vector2(104, 78)
		cell.add_child(box)
		var l := UIKit.label(key, 11, UITheme.CREAM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(l)
		grid.add_child(cell)
	await _grab("bench_0_glyphs")


## Eight real dice in a row, the way the battle screen shows them.
func _sheet_dice() -> void:
	_clear()
	var ids := ["HARE", "BADGER", "OWL", "HEDGE"]
	var y := 120.0
	for id in ids:
		var lbl := UIKit.outlined(UIKit.label(id, 20, UITheme.CREAM))
		lbl.position = Vector2(20, y - 30)
		root.add_child(lbl)
		for d in 2:
			var faces := _faces_of(id, d)
			for k in 3:
				var dv := Die3D.new(Vector2(96, 96))
				dv.interactive = false
				dv.position = Vector2(30 + (d * 3 + k) * 108.0, y)
				root.add_child(dv)
				dv.set_die(faces, k * 2)
		y += 150.0
	# and the states: dimmed, pinned, locked, highlighted
	var states := [[false, false, false, false], [true, false, false, false],
			[false, true, false, false], [false, false, true, false],
			[false, false, false, true]]
	var f0 := _faces_of("BADGER", 0)
	for i in states.size():
		var dv2 := Die3D.new(Vector2(96, 96))
		dv2.interactive = false
		dv2.position = Vector2(30 + i * 120.0, y + 20.0)
		root.add_child(dv2)
		dv2.set_die(f0, 0, states[i][0], states[i][1], states[i][2], states[i][3])
	await _grab("bench_1_dice")


## The tile the face-swap screen, codex and shop all use.
func _sheet_tiles() -> void:
	_clear()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	grid.position = Vector2(20, 70)
	root.add_child(grid)
	var picks := ["hare_quick3", "sp_great_blade", "owl_starfall", "hedge_guard4thorn2",
			"owl_starshower", "sp_venom_knife", "sp_annihilate", "sp_die_theft",
			"sp_torch", "sp_focus", "sp_echo_crystal", "sp_gambit",
			"hare_galestorm", "boar_worldbreaker", "sp_freeze", "sp_great_wall",
			"sp_first_aid", "blank"]
	for fid in picks:
		var fd: Dictionary = GameData.faces[fid].duplicate()
		fd["id"] = fid
		if fid == "blank":
			fd["blank"] = true
		if fid == "sp_great_blade":
			fd["plus"] = 2
		grid.add_child(FaceTile.new(fd, 100.0, true))
	await _grab("bench_2_tiles")


## The long-press card, on a face that uses several terms at once.
func _sheet_detail() -> void:
	_clear()
	var faces := _faces_of("OWL", 0)
	DetailCard.show_die(root, faces, 5)      # sp_freeze: stun + spell
	for i in 8:
		await get_tree().process_frame
	await _grab("bench_3_detail")


## Mid-flight: the dice caught partway through a throw.
func _sheet_throw() -> void:
	_clear()
	var dice := []
	for i in 8:
		var dv := Die3D.new(Vector2(96, 96))
		dv.interactive = false
		dv.position = Vector2(30 + (i % 4) * 168.0, 300 + (i / 4) * 220.0)
		root.add_child(dv)
		dv.set_die(_faces_of("HARE", i % 2), i % 6)
		dice.append(dv)
	await get_tree().process_frame
	for i in dice.size():
		dice[i].throw(i % 6, 0.02 * i, 0.68)
	for i in 14:
		await get_tree().process_frame
	await _grab("bench_4_throw_mid")
	for i in 40:
		await get_tree().process_frame
	await _grab("bench_5_throw_settled")


## Frame-time budget check: eight dice in the battle's own layout, at rest and
## then all throwing at once, in a real 720x1280 window. Numbers go in the log
## and from there into DECISIONS.md.
func _stress() -> void:
	# vsync would peg every frame at 16.7ms and hide the actual cost
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_clear()
	var dice := []
	for i in 8:
		var dv := Die3D.new(Die3D.SIZE)
		dv.interactive = false
		dv.position = Vector2(30 + (i % 2) * 88.0 + (i / 2) * 172.0, 900)
		root.add_child(dv)
		dv.set_die(_faces_of(["HARE", "BADGER", "OWL", "HEDGE"][i / 2], i % 2), i % 6)
		dice.append(dv)
	for i in 20:
		await get_tree().process_frame

	var idle := await _measure(60, dice, false)
	var busy := await _measure(90, dice, true)
	print("STRESS idle  8 dice at rest : avg %.2f ms  worst %.2f ms" % [idle.avg, idle.max])
	print("STRESS throw 8 dice tumbling: avg %.2f ms  worst %.2f ms" % [busy.avg, busy.max])
	await _grab("bench_6_stress")


func _measure(frames: int, dice: Array, throwing: bool) -> Dictionary:
	if throwing:
		for i in dice.size():
			dice[i].throw(i % 6, randf() * 0.15, 0.68)
	var total := 0.0
	var worst := 0.0
	for f in frames:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	return {"avg": total / float(frames), "max": worst}


# ------------------------------------------------------------ helpers

func _faces_of(id: String, die: int) -> Array:
	var src: Array = GameData.heroes[id].start if die == 0 else GameData.heroes[id].start_b
	var out := []
	for i in 6:
		var fid := String(src[i % src.size()])
		var fd: Dictionary = GameData.faces[fid].duplicate()
		fd["id"] = fid
		out.append(fd)
	return out


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUTDIR)
	img.save_png(OUTDIR + name + ".png")
	print("saved %s.png" % name)


## One glyph shown big and small on its category fill.
class _Swatch:
	extends Control
	var key := "atk"
	var hue := UITheme.ORANGE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.deepen(hue))
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.OUTLINE, false, 2.0)
		Glyphs.draw_glyph(self, key, Rect2(Vector2(6, 8), Vector2(56, 56)),
				UITheme.CREAM, UITheme.OUTLINE)
		draw_circle(Vector2(80, 30), 13.0, UITheme.deepen(hue).darkened(0.2))
		Glyphs.draw_glyph(self, key, Rect2(Vector2(71, 21), Vector2(18, 18)),
				hue.lightened(0.45), Color(0, 0, 0, 0))
		Glyphs.draw_glyph(self, key, Rect2(Vector2(72, 50), Vector2(14, 14)),
				UITheme.CREAM, Color(0, 0, 0, 0))
