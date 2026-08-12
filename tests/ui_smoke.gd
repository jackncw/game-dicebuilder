extends Node
## Headless UI smoke test: drives the battle screen through both its input
## paths — tap-to-select and drag-and-drop — until the battle ends, asserting
## no crashes and that the result overlay appears.
##   godot --headless --path . res://tests/ui_smoke.tscn

var fails := 0

## The three bounds `_t_enemy_legibility` holds the enemy silhouettes to. They
## live here, as literals this file owns, and not in `ui_theme.gd`: `rot_rim_for`
## already solves against `UITheme.ROT_RIM_TARGET`, so a check that read the same
## constant would move with the thing it is checking. See the header on
## `_t_enemy_legibility` for why there are three of them and not one.
const CARD_EDGE_FLOOR := 2.4      # lit edge vs the bare chapter card

## The one thing that makes a green run here mean something about the PICTURE.
##
## THE BAR IS STILL 2.4:1. This is not a tightened standard — it is the proxy's
## own measured error against the render, added on so that "the model clears the
## floor" implies "the render clears the floor" instead of merely suggesting it.
##
## Derived, not chosen, and then deliberately rounded UP. Two numbers bracket it,
## both off `tools/enemy_legibility.gd`, which renders all 37 rows while
## `_screen_band` models the same 37:
##   • the FLOOR it must clear — the largest amount by which the model reads
##     ABOVE the render, the optimistic direction and the only one that can hide
##     a failure — is **+0.0447** (E05 ch1: modelled 2.513:1, rendered 2.469:1;
##     next E10 ch1 +0.043, then E03 ch2 +0.032, so it is a shoulder and not a
##     lone outlier). The other direction runs to −0.028 and needs nothing.
##   • the CEILING it must not reach — the thinnest MODELLED row is E09 ch1 at
##     2.490, so anything past 0.090 would red a row the render passes at 2.494.
##
## **0.06**, which is 0.0447 plus half of what is left. It is not set to the
## measured worst plus a rounding digit, and the reason is what that measurement
## is: a MAX over 37 deterministic samples. A max over a sample is by
## construction a lower bound on the true worst, and the 37 are one card layout,
## one set of plates and one idle frame — the next plate cut or the next retuned
## box is not in them. Sitting a ten-thousandth above the largest number anyone
## happened to draw would be treating a lower bound as a bound.
##
## The other half of the reason is that the alarm is manual. The render prints
## `LEGIBILITY BOUND1 worst OPTIMISTIC bias ... COVERED` or `MARGIN TOO SMALL`
## against this very constant every run — but that run needs a real window and is
## NOT in `tools/test_all.sh`, so a stale margin is caught only when somebody
## remembers to look. A margin that carries slack degrades to a smaller true
## margin; a margin fitted to the last measured digit degrades to a false claim.
##
## Spent 0.06 of the 0.090 available, leaving E09 ch1 passing at 2.490 against
## 2.460, i.e. **+0.030**. That spare is the check's own headroom, not padding on
## the guarantee: the guarantee is that 0.06 > 0.0447.
##
## This covers BOUND 1 ONLY. Bound 2 is a cap that the model already overstates
## on all 37 rows (worst modelled 20.2% at B2 against 9.2% rendered), so it is
## conservative without help. Bound 3 gets no margin on purpose — its residual is
## two-sided at ±0.46 and a one-sided margin there would be a false guarantee,
## while one big enough to cover it would red rows the picture passes; see
## `MIST_EDGE_FLOOR` and `lit_edge`'s residual note for what stands in instead.
const CARD_EDGE_MARGIN := 0.06
## RE-PRICED IN TASK 6 FROM 1.9, AND THE REASON IS THE RULER, NOT THE BAR.
## Task 5 set 1.9 as "just below today's worst modelled row, 1.990". That 1.990
## came out of a `lit_edge()` that pinned the shader's `edge` scalar at 1.0 —
## a model Task 6's render then measured to be reading 0.99 to 1.326 HIGH on all
## 37 rows. So 1.9 was calibrated against numbers we now know were bad; it was
## never a measurement of the picture, it was a measurement of a broken proxy.
## Re-deriving it from the real render is not loosening a standard to pass. It is
## setting the standard against a ruler that works. Both numbers stay written
## down so the history is legible: OLD 1.9 (from modelled worst 1.990),
## NEW 1.55 (from RENDERED worst 1.600, E05 ch3 — `tools/enemy_legibility.gd`,
## 69 rendered band pixels). Same construction Task 5 used, just below the worst,
## and deliberately not padded further.
##
## That 1.600 was measured against `card_behind()`'s MODEL of the mist background,
## which was the last modelled term inside the instrument of record. The tool now
## reads that background off the render too, and the same row comes back at
## **1.604** — so the floor's margin is **+0.054**, and the derivation above stands
## with the number it was derived from confirmed rather than replaced. See
## `card_behind` for the measurement.
##
## What this bound now permits, concretely: E05 has the LOWEST mist coverage in
## the cast — 1.5% of its band at five wisps, against B2's 20.2% — so this floor
## lets roughly one and a half percent of the moth's outline sit at 1.6:1 while
## the rest of its contour clears the untouched 2.4:1 of `CARD_EDGE_FLOOR`.
## `MIST_COVER_CAP` is what keeps that "roughly one and a half percent" true.
##
## `rim_px` cannot buy this row back: rendered at 3/6/7/8/9/12 it reads
## 1.025 / 1.604 / 1.617 / 1.620 / 1.635 / 1.561 — flat past 6, falling past 9.
const MIST_EDGE_FLOOR := 1.55     # lit edge vs mist-over-card, where mist sits behind it
const MIST_COVER_CAP := 0.25      # how much of an edge band the mist may ever stand on

## Sub-rows per texture row when `_stamp_wisp` scan-converts a wisp. Four, and
## the x-spans round outward, so a pixel counts as veiled if the polygon touches
## it at all rather than if its centre happens to fall inside. That is the
## conservative direction for a CAP — and it is the convention the round-2
## measurement in `task-5-report.md` used, so the number this file prints is the
## number the 25% was chosen against. Centre sampling reads 0.3–1.5 points lower
## across the seventeen; both orderings are identical.
const SUB_ROWS := 4


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _make_battle() -> Control:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": ["E01", "E01"],
			"opts": {"chapter": 1}, "battle_seed": 555})
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	# the enemy phase is a timed sequence in the shipping game; the tests want
	# it resolved as fast as frames can be pumped
	battle.instant_anim = true
	add_child(battle)
	return battle


func _ready() -> void:
	await get_tree().process_frame
	await _t_tap_playthrough()
	await _t_drag_targeting()
	await _t_float_anchors()
	await _t_die_render()
	_t_contrast()
	_t_no_player_magenta()
	_t_rot_rim()
	_t_enemy_legibility()
	await _t_enemy_sprites()
	if fails == 0:
		print("UI SMOKE OK")
	else:
		print("UI SMOKE FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Plays a whole battle through the tap path.
func _t_tap_playthrough() -> void:
	var battle := _make_battle()
	await get_tree().process_frame
	_check(battle.die_widgets.size() == 8, "8 dice on the table, got %d" % battle.die_widgets.size())

	var guard := 0
	while not battle.bc.s.over and guard < 40:
		guard += 1
		if guard == 2:
			battle.bc.s.rerolls = 1
			battle._on_reroll()
			await get_tree().process_frame
		for i in 4:
			if battle.bc.s.over:
				break
			for d in BattleCore.DICE:
				if battle.bc.s.over or not battle.bc.can_use(i, d).ok:
					continue
				battle._on_die_pressed(i, d)
				await get_tree().process_frame
				if battle.sel.is_empty():
					break     # a no-target face resolved on the first tap
				var spec: Dictionary = battle._drop_spec()
				if not spec.enemies.is_empty():
					battle._on_enemy_tapped(int(spec.enemies[0]))
				elif not spec.heroes.is_empty():
					battle._on_hero_tapped(int(spec.heroes[0]))
				elif bool(spec.enemy_dice):
					var dice: Array = battle.bc.targetable_dice()
					if dice.is_empty():
						battle._deselect()
						battle._refresh()
					else:
						battle._on_enemy_die_tapped(int(dice[0].enemy), int(dice[0].die))
				elif bool(spec.cast):
					battle._on_cast_tapped()       # tap the centre pad
				else:
					battle._deselect()
					battle._refresh()
				await get_tree().process_frame
				break
		if guard == 1 and battle.bc.can_undo():
			battle._on_undo()
			await get_tree().process_frame
		if not battle.bc.s.over:
			await battle.end_turn_and_wait()
			await get_tree().process_frame

	_check(battle.bc.s.over, "battle ended (guard=%d)" % guard)
	await get_tree().process_frame
	_check(battle.overlay != null, "result overlay shown")
	print("battle result: victory=%s turn=%d" % [battle.bc.s.victory, battle.bc.s.turn])
	battle.queue_free()


## Pick a die up and carry it to `to`, arming the drag on the way — the battle
## screen only lets go of a die that has actually travelled (see DRAG_ARM).
func _carry(battle: Control, i: int, d: int, to: Vector2) -> void:
	battle._on_drag_started(i, d, Vector2(100, 800), -1)
	await get_tree().process_frame
	if battle.drag.is_empty():
		return
	for k in range(1, 4):
		battle._on_drag_moved(Vector2(100, 800).lerp(to, float(k) / 3.0))
	await get_tree().process_frame


## Exercises the drag path: a legal drop resolves, an illegal one cancels.
func _t_drag_targeting() -> void:
	var battle := _make_battle()
	await get_tree().process_frame
	# force hero 0's A die to a single-target attack so the test is deterministic
	battle.bc.s.heroes[0].faces[0] = "hare_quick3"
	battle.bc.s.heroes[0].rolled = [0, 6]
	battle.bc.s.heroes[0].used = false
	battle._refresh()
	await get_tree().process_frame

	# --- illegal drop: released over empty space, nothing is spent
	await _carry(battle, 0, 0, Vector2(20, 1270))
	_check(not battle.drag.is_empty(), "drag started")
	_check(battle.drag_ghost != null, "drag ghost spawned")
	var spec: Dictionary = battle._drop_spec()
	_check(not spec.enemies.is_empty(), "enemies highlighted while dragging an attack")
	battle._on_drag_ended(Vector2(20, 1270))
	await get_tree().process_frame
	_check(battle.drag.is_empty(), "drag cleared after an illegal drop")
	_check(not battle.bc.s.heroes[0].used, "illegal drop spent nothing")
	_check(battle.drag_ghost == null, "ghost removed")

	# --- legal drop onto the first enemy card. Picking the die up rebuilds the
	# enemy row, so the point is measured ONCE up front and then reused — the
	# card node itself is gone by the time the drop happens.
	var hp_before: int = battle.bc.s.enemies[0].hp
	var at: Vector2 = battle.enemy_widgets[0].card.get_global_rect().get_center()
	await _carry(battle, 0, 0, at)
	_check(battle._armed(), "the carried die armed past the throw distance")
	battle._on_drag_ended(at)
	await get_tree().process_frame
	_check(battle.bc.s.heroes[0].used, "legal drop spent the die")
	_check(0 in battle.bc.s.heroes[0].used_dice, "the dragged die is the one spent")
	_check(battle.bc.s.enemies[0].hp < hp_before, "the enemy took damage")

	# --- the other die is now locked out and refuses a drag.
	# The enemy row was rebuilt by the drop above, so the card we measured
	# earlier is gone; re-read it rather than poking a freed node.
	var at2: Vector2 = battle.enemy_widgets[0].card.get_global_rect().get_center()
	await _carry(battle, 0, 1, at2)
	_check(battle.drag.is_empty(), "locked-out die cannot be dragged")
	battle.queue_free()


## A free-spin die has to draw itself and then stop drawing itself.
##
## Both halves were broken. `DetailCard.show_die` turns free spin on before the
## widget is in the tree, and `_render_once` used to refuse to take a still for a
## free-spin die — so the long-press card opened onto a grey square that only
## appeared once you poked it. At the other end, the die used to go to
## UPDATE_DISABLED in the same frame it set its final pose, one frame before that
## pose could reach the texture.
##
## `_process` is called by hand with a fixed delta: headless frames come as fast
## as the machine can make them, so a frame count would be timing noise.
func _t_die_render() -> void:
	var faces := []
	for fid in GameData.heroes["HARE"].start:
		var fd: Dictionary = GameData.faces[String(fid)].duplicate()
		fd["id"] = String(fid)
		faces.append(fd)

	var die := Die3D.new(Vector2(76, 76))
	# the exact order the detail card uses: configured, then mounted
	die.enable_free_spin()
	die.set_die(faces, 0)
	add_child(die)
	_check(die._vp.render_target_update_mode != SubViewport.UPDATE_DISABLED,
			"a free-spin die asks for a frame the moment it enters the tree")
	for i in 6:
		die._process(0.016)
	_check(die._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"and sleeps once the still has landed")
	_check(not die.is_processing(), "a parked die is off the process list")

	# --- a flick: spins, coasts, stops, and only then stops rendering
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = die.size * 0.5
	die._gui_input(down)
	for k in 3:
		var mv := InputEventMouseMotion.new()
		mv.position = die.size * 0.5 + Vector2(18, -6) * float(k + 1)
		mv.relative = Vector2(18, -6)
		die._gui_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = die.size * 0.5 + Vector2(54, -18)
	die._gui_input(up)
	_check(die.is_processing(), "a flicked die keeps rendering while it spins")

	var ticks := 0
	while die.is_processing() and ticks < 500:      # 500 x 20ms = 10 simulated s
		die._process(0.02)
		ticks += 1
	print("die free spin: coasted %.1fs after the flick" % (ticks * 0.02))
	_check(ticks < 500, "a flick coasts to a stop (ticks=%d)" % ticks)
	_check(ticks > 20, "and does not stop dead on release (ticks=%d)" % ticks)
	_check(die._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"a stopped die stops rendering")
	# the pose it stopped in is the one on the texture: sleeping is only ever
	# reached through the pump, never straight out of the settle branch
	_check(die._mesh.basis.is_equal_approx(die.rest_basis(die.shown)),
			"it stops square on the face that was up")
	die.queue_free()
	await get_tree().process_frame


## The art-review rule the whole palette was built around: any body text has to
## clear 4.5:1 against the surface it is printed on. Locks in the pairings so a
## future colour tweak cannot quietly push a screen back under the line.
func _t_contrast() -> void:
	for ch in [1, 2, 3]:
		var surf := UITheme.surface(ch)
		var deep := UITheme.surface_deep(ch)
		var sky := UITheme.bg(ch)
		_ratio(UITheme.CREAM, surf, "cream on chapter %d card" % ch)
		_ratio(UITheme.CREAM_DARK, surf, "cream-dark on chapter %d card" % ch)
		_ratio(UITheme.CREAM, deep, "cream on chapter %d tray" % ch)
		_ratio(UITheme.CREAM_DARK, deep, "cream-dark on chapter %d tray" % ch)
		# text printed straight on the sky only ever uses full cream
		_ratio(UITheme.CREAM, sky, "cream on chapter %d sky" % ch)
		for cat in UITheme.CAT_ON_DARK:
			_ratio(UITheme.CAT_ON_DARK[cat], surf, "%s accent on chapter %d card" % [cat, ch])
	# chips: cream on the deep fill, for every category
	for cat2 in UITheme.CAT_DEEP:
		_ratio(UITheme.CREAM, UITheme.CAT_DEEP[cat2], "chip text on %s chip" % cat2)
	# ink on paper, and the disabled-button pairing
	_ratio(UITheme.INK, UITheme.CREAM, "ink on cream")
	_ratio(UITheme.INK_SOFT, UITheme.CREAM, "soft ink on cream")
	_ratio(Color("3a372f"), Color("b0aba0"), "disabled button label")


func _ratio(fg: Color, bg: Color, what: String) -> void:
	var r := UITheme.contrast(fg, bg)
	_check(r >= 4.5, "%s is %.2f:1, needs 4.5:1" % [what, r])


## Magenta belongs to the enemy. Nothing the player owns — no theme token, no
## die, no button, no status icon, no pixel of a hero plate — may sit inside
## `UITheme.is_magenta()`, because a magenta pixel on screen is supposed to mean
## "this is not yours" without anyone having to be told.
##
## The theme half walks `ui_theme.gd`'s constant map rather than a hand-written
## list, so a colour added next month is covered the day it is added. The
## `ROT_*` family is the exception, and the test asserts those ARE magenta —
## a rule only worth having if the reserved side actually uses it.
func _t_no_player_magenta() -> void:
	var theme: Script = load("res://scripts/ui/ui_theme.gd")
	var consts: Dictionary = theme.get_script_constant_map()
	var checked := 0
	for name in consts:
		var v: Variant = consts[name]
		var enemy_side := String(name).begins_with("ROT_")
		for entry in _colors_in(v):
			var c: Color = entry
			checked += 1
			if enemy_side:
				continue
			_check(not UITheme.is_magenta(c),
					"UITheme.%s %s is in the enemy magenta wedge (h=%.0f s=%.2f v=%.2f)"
							% [name, c.to_html(false), c.h * 360.0, c.s, c.v])
	_check(checked > 40, "walked the whole theme, got %d colours" % checked)
	# and the reserved family really is reserved
	for rot in [UITheme.ROT_VEIN, UITheme.ROT_VEIN_DIM, UITheme.ROT_EYE, UITheme.ROT_EYE_DIM]:
		_check(UITheme.is_magenta(rot),
				"%s should be inside the enemy wedge" % rot.to_html(false))

	# the painted heroes, pixel by pixel — the plates are the one player-side
	# surface the theme cannot speak for
	for id in PawnArt.HERO_TEX:
		var tex := PawnArt.hero_texture(String(id))
		_check(tex != null, "hero plate %s loads" % id)
		if tex == null:
			continue
		var img := tex.get_image()
		var hits := 0
		var worst := Color.BLACK
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var px := img.get_pixel(x, y)
				if px.a < 0.16 or not UITheme.is_magenta(px):
					continue
				hits += 1
				if px.s > worst.s:
					worst = px
		_check(hits == 0, "hero plate %s has %d magenta pixels (worst %s)"
				% [id, hits, worst.to_html(false)])


## Colours reachable from one theme constant: a Color, or the values of a
## dictionary of them (the category tables).
func _colors_in(v: Variant) -> Array:
	if v is Color:
		return [v]
	if v is Dictionary:
		var out := []
		for k in v:
			if v[k] is Color:
				out.append(v[k])
		return out
	return []


## The rim light's strength is a single formula shared by GDScript and the
## shader, and it has to run the way the arithmetic runs, not the way "darker
## card needs more help" sounds.
##
## A contrast ratio is `(Lfg + 0.05) / (Lbg + 0.05)`. A BRIGHTER card raises the
## luminance the lit edge has to reach, so the brightest of the three cards —
## chapter 1's `#1b3019`, luminance 0.0242 against chapter 3's 0.0094 — is the
## one that takes the most rim, and chapter 3 the least. This test used to
## assert the opposite (`r1 <= r2 <= r3`); it was passing because the curve had
## the same mistake in it, and chapter 3 was being driven to 1.00, where the
## shader's `mix()` stops lighting the plate's ink outline and simply replaces
## it with flat `ROT_RIM`.
##
## So: the ordering, and that each chapter's strength is the MINIMUM that does
## the job. Both halves matter — an inflated rim passes any floor check while
## quietly flattening the artwork.
##
## The checks below read `UITheme.ROT_RIM_TARGET` because what they test is that
## the curve reaches its own declared target — they would follow that constant
## wherever it went. The 2.4:1 floor is therefore owned by this file instead, as
## `CARD_EDGE_FLOOR`, so lowering `ROT_RIM_TARGET` is caught in
## `_t_enemy_legibility` rather than nowhere. Measured: drop it to 2.0 and the
## worst modelled edge (E09 on chapter 1) falls to 2.234:1 and that test fires.
##
## The background here is the BARE card, deliberately: that is the quantity
## `rot_rim_for` solves against, and this test's job is to check the curve
## reaches its own declared target, not to re-litigate what that target should
## be. What is behind the veiled part of a silhouette is `card_behind()`, mist
## over the card — so clearing this bar is necessary and not sufficient, and
## `_t_enemy_legibility`'s three bounds are where that shows up.
func _t_rot_rim() -> void:
	var l1 := UITheme.luminance(UITheme.surface(1))
	var l2 := UITheme.luminance(UITheme.surface(2))
	var l3 := UITheme.luminance(UITheme.surface(3))
	_check(l1 > l2 and l2 > l3,
			"this test's premise is that card luminance falls ch1>ch2>ch3; it is now %.4f/%.4f/%.4f"
			% [l1, l2, l3])
	var r1 := UITheme.rot_rim_for(1)
	var r2 := UITheme.rot_rim_for(2)
	var r3 := UITheme.rot_rim_for(3)
	_check(r1 > r2 and r2 > r3,
			"rim must fall as the card darkens (ch1 is the brightest card): %.3f/%.3f/%.3f"
			% [r1, r2, r3])
	for ch in [1, 2, 3]:
		var s := UITheme.rot_rim_for(ch)
		_check(s > 0.0 and s <= 1.0, "chapter %d rim %.3f out of (0..1]" % [ch, s])
		# sufficient: even a pure-black edge — darker than any plate's — clears
		# the target once this rim is on it
		var black := lit_edge(Color.BLACK, ch)
		var got := UITheme.contrast(black, UITheme.surface(ch))
		_check(got >= UITheme.ROT_RIM_TARGET,
				"chapter %d rim %.3f only carries a black edge to %.2f:1, needs %.2f:1"
				% [ch, s, got, UITheme.ROT_RIM_TARGET])
		# and not one step more than sufficient: back it off and it must fail,
		# or the curve has been padded and the plates are being over-lit.
		# Through `lit_edge` and not a raw `lerp`, so that both halves of this
		# assertion keep modelling the same thing when a term is added to it.
		var weaker := UITheme.contrast(lit_edge(Color.BLACK, ch, s - 0.02),
				UITheme.surface(ch))
		_check(weaker < UITheme.ROT_RIM_TARGET,
				"chapter %d rim %.3f is padded — %.3f already reaches %.2f:1"
				% [ch, s, s - 0.02, weaker])
	print("rot rim: ch1 %.3f  ch2 %.3f  ch3 %.3f — black edge lands at %.2f/%.2f/%.2f:1"
			% [r1, r2, r3,
			UITheme.contrast(lit_edge(Color.BLACK, 1), UITheme.surface(1)),
			UITheme.contrast(lit_edge(Color.BLACK, 2), UITheme.surface(2)),
			UITheme.contrast(lit_edge(Color.BLACK, 3), UITheme.surface(3))])


## Can you still tell where the creature ends and the card begins?
##
## The old version measured a flat body colour this file used to own. The
## bodies are painted plates now, so the thing that has to survive the card is
## the LIT EDGE: the outermost band of the silhouette with the rim light on it.
##
## `edge_rgb` is measured off each cut PNG by `tools/enemy_cutout.py`; the
## blend below mirrors `rot_pawn.gdshader`'s rim line, and both take their
## strength from `UITheme.rot_rim_for`. This is a MODEL of the picture, not the
## picture — `tools/enemy_legibility.gd` renders the real thing, and the two
## are reconciled before this number is trusted. See DECISIONS.md.
##
## ── Why THREE bounds and not one ─────────────────────────────────
## `PawnArt._draw` lays `_auto_mist` down BEFORE the plate, inside the plate's
## own footprint, and `ROT_MIST` (luminance 0.0578) is brighter than every
## chapter card (0.0242 / 0.0210 / 0.0094). So a silhouette's contour is read
## against two different backgrounds at once: bare card over most of it, mist
## over the rest. Rolling those into one number means either measuring the easy
## case everywhere or the hard case everywhere, and neither is the picture.
##
## The mist is a deliberate soft veil — one of the five tier dials — and
## `mist_coverage()` measures that it occludes about a tenth of the contour: at
## five wisps, 1.5% (E05) to 20.2% (B2) per key and 16799 of 158496 band px
## (10.6%) over the seventeen; at three, 1.1% (E09) to 14.4% (E03), 7.9%
## overall. The eye reads the silhouette off the remaining nine tenths. So the
## mist-backed edge is accepted as a SEPARATE case, and the three bounds
## together are what make that safe:
##
##   1. `CARD_EDGE_FLOOR` — the card-backed edge keeps the full 2.4:1. This is
##      the original guarantee and it is not relaxed anywhere. What IS added is
##      `CARD_EDGE_MARGIN`, the model's own measured error against the render,
##      so that clearing the bar here means clearing it there. Rendered worst is
##      E05 ch1 at 2.469:1 (+0.069 on the floor); modelled worst is E09 ch1 at
##      2.490:1 (+0.030 on floor-plus-margin).
##   2. `MIST_COVER_CAP` — the mist may never stand on more than 25% of an edge
##      band. Today's worst is B2 at 20.2%. THIS is what makes bound 1
##      meaningful: without it, the veil could grow until "most of the contour
##      is on bare card" quietly stopped being true and bound 1 stopped
##      describing what anyone sees. It needs no margin: it is a cap and the
##      model sits at or above the render on all 37 rows (B2 is 9.2% in the
##      picture against the 20.2% modelled here).
##   3. `MIST_EDGE_FLOOR` — where the veil does sit, the edge still reaches
##      1.55:1. Re-priced in Task 6 from 1.9, off the RENDER rather than off a
##      model that had been measured wrong; the constant carries the derivation.
##      Rendered worst is E05 ch3 at 1.604:1 (margin +0.054, against a mist
##      background read off the render — see `card_behind`); modelled worst is
##      E09 ch3 tier3 at 1.816:1 (+0.266). The model cannot resolve this bound
##      better than ±0.46 and errs in BOTH directions, so no margin is added —
##      a one-sided one would be a false guarantee and a two-sided one would red
##      rows the picture passes.
##
##      WHAT THAT MAKES THE CHECK BELOW. It is a live, unmargined `_check`: it
##      can and does fail the suite. What it is NOT is a statement about the
##      picture. Read it as a LOOSE REGRESSION GUARD — it catches a change that
##      moves the modelled mist-backed edge by more than the model's own ±0.44,
##      and nothing finer. Its green does not imply the render passes and its
##      red does not imply the render fails; both have happened. In round 2 of
##      Task 6, at the then-floor of 1.9, this check redded E09 ch3 at 1.893
##      while the render passed the same row at 1.930, and passed E05 ch3 at
##      2.002 while the render failed it at 1.600. Both rows clear the current
##      floor on both rulers, but that is a fact about the render, not something
##      this check established.
##      `tools/enemy_legibility.gd` is this bound's instrument of record and has
##      to be re-run when a plate, a dial, a card layout or a chapter colour
##      moves. See `lit_edge`'s residual note for the two causes.
##
## Do not simplify these back into one. Bound 1 alone measures a background that
## a tenth of the contour does not have; bound 3 alone applies a veiled-case bar
## to nine tenths of a contour that is not veiled; and either one without
## bound 2 is an assertion about a fraction nothing is holding still.
##
## Which (chapter, tier) pairs a key is actually met at is not a free choice:
## `battle_core.gd:123` gives a minion `tier = chapter`, and `:179` files a
## boss under `int(def.chapter)` while `PawnArt.rot_of` puts every boss on the
## top dial row regardless. So a minion is met once per chapter at that
## chapter's tier, and a boss once, at row 2.
func _t_enemy_legibility() -> void:
	var f := FileAccess.open("res://assets/enemies/enemies.json", FileAccess.READ)
	_check(f != null, "assets/enemies/enemies.json is missing")
	if f == null:
		return
	# not `var meta: Dictionary = JSON.parse_string(...)`: on malformed JSON that
	# returns null and the typed assignment is a hard script error, which reads as
	# a crashed suite instead of a failed check
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	_check(parsed is Dictionary, "assets/enemies/enemies.json did not parse as an object")
	if not (parsed is Dictionary):
		return
	var meta: Dictionary = parsed
	# Identity, not cardinality. A key renamed on one side only would keep the
	# count at 17 and quietly measure a different set of sprites; `ENEMY_TEX` is
	# the list that actually gets drawn, so it is the one this has to match.
	var want: Array = PawnArt.ENEMY_TEX.keys()
	want.sort()
	var got: Array = meta.keys()
	got.sort()
	_check(got == want, "enemies.json describes %s; the drawn plates are %s" % [got, want])
	_check(want.size() == 17, "expected 17 enemy plates, PawnArt.ENEMY_TEX lists %d" % want.size())

	var worst_card := 99.0
	var worst_card_what := ""
	var worst_mist := 99.0
	var worst_mist_what := ""
	var worst_cover := -1.0
	var worst_cover_what := ""
	# per chapter: how many distinct inputs went in, how many distinct lit edges
	# came out. A lerp with strength < 1 is injective, so those two counts have
	# to agree. They stop agreeing exactly when the rim is strong enough to stop
	# lighting the plates and start replacing them — at strength 1.00 every row
	# collapses onto `ROT_RIM` itself and the rows below measure nothing about
	# the sprite. That is what chapter 3 was doing before `rot_rim_for` was
	# solved instead of ramped; this is the guard that keeps it from coming back.
	#
	# The INPUT is the pair (edge colour, rim coverage), not the edge colour
	# alone: `lit_edge` takes the plate's own measured coverage, so it is a
	# function of both and two plates can share an edge colour and still light
	# differently. They do — E01 and E10 both measure edge_rgb (24,15,29) —
	# and keying this on the colour alone reported 11 in against 12 out, a
	# collapse guard firing on the absence of a collapse.
	var edges_in := {1: {}, 2: {}, 3: {}}
	var lits_out := {1: {}, 2: {}, 3: {}}
	for key in meta:
		var edge_v: Variant = _edge_colour(meta, String(key))
		if edge_v == null:
			continue
		var edge: Color = edge_v
		# a minion's tier IS the chapter it is met in; a boss is met once
		var cases: Array = [[int(PawnArt.BOSS_CHAPTER[key]), int(PawnArt.BOSS_CHAPTER[key])]] \
				if PawnArt.BOSS_CHAPTER.has(key) else [[1, 1], [2, 2], [3, 3]]
		for c in cases:
			var ch: int = c[0]
			var tier: int = c[1]
			# with the MEASURED rim coverage, not the pinned 1.0 — the number this
			# row is about is what the band actually receives
			var cov := rim_coverage(String(key))
			var lit := lit_edge(edge, ch, -1.0, cov)
			# keyed on the raw channels, not `to_html`: at s ≈ 0.5 the lerp
			# compresses differences by (1 - s), so two plates one 8-bit step
			# apart can round to the same hex and fire this guard for a reason
			# that has nothing to do with the rim. B3 (39,26,40) and B3P2
			# (40,26,38) are already that close.
			edges_in[ch]["%s@%.9f" % [_colour_key(edge), cov]] = true
			lits_out[ch][_colour_key(lit)] = true
			var wisps: int = PawnArt.MIST_COUNT[PawnArt.dial_row(String(key), tier)]
			var where := "%s ch%d tier%d (%d wisps)" % [key, ch, tier, wisps]

			# ── bound 1: the card-backed edge, at the full 2.4:1 ──
			# `seen_edge`, not `lit`: on the four-up card this row is minified,
			# and the fragment the screen gets is a bilinear tap composited at
			# its own alpha, not a texel. That term used to be missing and it
			# read 0.09–0.26 HIGH on all 37 rows — the optimistic direction for
			# a floor. See `_screen_band`.
			var card := UITheme.surface(ch)
			var seen := seen_edge(edge, ch, String(key), tier, card)
			var r_card := UITheme.contrast(seen, card)
			if r_card < worst_card:
				worst_card = r_card
				worst_card_what = where
			_check(r_card >= CARD_EDGE_FLOOR + CARD_EDGE_MARGIN,
					"%s: lit edge %s over the bare card %s is %.3f:1, needs %.2f:1 + %.3f of proxy margin"
					% [where, seen.to_html(false), card.to_html(false), r_card,
					CARD_EDGE_FLOOR, CARD_EDGE_MARGIN])

			# ── bound 2: how much contour the veil is allowed to stand on ──
			# Measured off this plate's own alpha and `_auto_mist`'s own
			# polygons, so it moves the moment either does. It is what stops
			# bound 1 from being a claim about a majority nothing is holding.
			var cover := mist_coverage(String(key), tier)
			if cover > worst_cover:
				worst_cover = cover
				worst_cover_what = where
			_check(cover <= MIST_COVER_CAP,
					"%s: mist stands on %.1f%% of the edge band, cap is %.1f%% — the veil is covering the silhouette, not softening it"
					% [where, cover * 100.0, MIST_COVER_CAP * 100.0])

			# ── bound 3: and where it does stand, the edge still reads ──
			# `card_behind` is the bare card on a row with no wisps, so this
			# runs on every row; on those it is bound 1 again with a slacker
			# bar, which is what "no veil to allow for" ought to mean.
			var bg := card_behind(ch, String(key), tier)
			var seen_m := seen_edge(edge, ch, String(key), tier, bg)
			var r_mist := UITheme.contrast(seen_m, bg)
			if r_mist < worst_mist:
				worst_mist = r_mist
				worst_mist_what = where
			_check(r_mist >= MIST_EDGE_FLOOR,
					"%s: lit edge %s over mist-on-card %s is %.3f:1, needs %.2f:1"
					% [where, seen_m.to_html(false), bg.to_html(false), r_mist,
					MIST_EDGE_FLOOR])
	for ch in [1, 2, 3]:
		_check(lits_out[ch].size() == edges_in[ch].size(),
				"chapter %d: %d distinct edge colours went in, %d came out — the rim is washing the plates out, not lighting them"
				% [ch, edges_in[ch].size(), lits_out[ch].size()])
	print("enemy legibility: card-backed edge worst is %s at %.3f:1 (floor %.2f + %.4f proxy margin, spare %+.3f)"
			% [worst_card_what, worst_card, CARD_EDGE_FLOOR, CARD_EDGE_MARGIN,
			worst_card - CARD_EDGE_FLOOR - CARD_EDGE_MARGIN])
	print("enemy legibility: mist-backed edge worst is %s at %.3f:1 (floor %.2f, margin %+.3f)"
			% [worst_mist_what, worst_mist, MIST_EDGE_FLOOR, worst_mist - MIST_EDGE_FLOOR])
	print("enemy legibility: mist covers at most %.1f%% of a band, at %s (cap %.1f%%, margin %+.1f pt)"
			% [worst_cover * 100.0, worst_cover_what, MIST_COVER_CAP * 100.0,
			(MIST_COVER_CAP - worst_cover) * 100.0])
	print("enemy legibility: distinct lit edges %d/%d/%d"
			% [lits_out[1].size(), lits_out[2].size(), lits_out[3].size()])
	free_render_model()


## `edge_rgb` for one key as a Colour, or null with a named failure already
## reported. Every field is checked rather than assumed: `var e: Array = ...`
## on a non-array, or `e[2]` on a two-element list, is a hard script error, and
## a crashed suite is not the same signal as a failed check.
func _edge_colour(meta: Dictionary, key: String) -> Variant:
	if not (meta[key] is Dictionary):
		_check(false, "enemies.json entry %s is not an object" % key)
		return null
	var entry: Dictionary = meta[key]
	var raw: Variant = entry.get("edge_rgb")
	if not (raw is Array and (raw as Array).size() >= 3):
		_check(false, "enemies.json entry %s has no usable edge_rgb (got %s)" % [key, raw])
		return null
	var e: Array = raw
	for i in 3:
		if not (e[i] is float or e[i] is int):
			_check(false, "enemies.json entry %s edge_rgb is not three numbers: %s" % [key, e])
			return null
	return Color8(int(e[0]), int(e[1]), int(e[2]))


## A distinctness key that does not quantise. `to_html` rounds to 8 bits, and
## `lit_edge` compresses the gaps between plates by `1 - rim_strength`, so two
## sprites that genuinely differ can collapse onto one hex string well before
## the rim is anywhere near washing them out.
func _colour_key(c: Color) -> String:
	return "%.9f/%.9f/%.9f" % [c.r, c.g, c.b]


## The rim light applied to an edge colour, mirroring the `mix()` at the bottom
## of `rot_pawn.gdshader` with that line's remaining input, `v_modulate`, pinned
## at white. The `edge` scalar used to be pinned at 1.0 here too; it is now the
## `coverage` argument, and `rim_coverage()` / `_screen_band()` measure it.
##
## THIS FUNCTION IS ONE FRAGMENT. What the bounds are held to is `seen_edge()`,
## which calls this once per screen pixel the band lands on — each with that
## pixel's own coverage — and composites the results over the card at the alpha
## each one carries. This is the colour; that one is the geometry.
##
## THREE known ways the family is a model and not the picture, plus one newly
## named below, all written out with numbers in `task-5-report.md` and
## `task-6-report.md`. There were seven. FOUR have come off the list, every one
## for the same reason — they stopped being approximated and started being
## measured:
##   • the mist, which used to read "one flat layer covering the whole edge": a
##     single number standing for two different backgrounds. Now MODELLED, by
##     `mist_coverage()` measuring how much contour the veil actually stands on
##     and by the card-backed and mist-backed edges being bounded separately.
##     What residual it still has lives on `card_behind` and `mist_coverage`.
##   • the shader's `edge` scalar (`src.a * (1 - amin)`), which used to be PINNED
##     at 1.0 here and was the whole of the divergence: it reaches 1.0 only right
##     at the alpha boundary and falls off inward, so pinning it made this
##     function read 0.99–1.326 HIGH on every one of the 37 rows Task 6 rendered.
##     At the `rim_px = 3` that shipped then, the band mean was 0.562 (E09) to
##     0.677 (B6) — the ray from the band's innermost texel only just reached the
##     boundary. Now MODELLED, by `rim_coverage()`, which evaluates that same
##     expression over the same band off the plate's own alpha channel; and
##     `PawnArt.ROT_RIM_PX` went to 6 so the scalar is 0.957–0.982. Correcting it
##     took the worst bound-1 disagreement from 1.326 to 0.093 at the unchanged
##     `rim_px = 3`, which is the validation.
##   • MINIFICATION, which was the largest term left after `edge` and the
##     dangerous one, because it was one-directional in the OPTIMISTIC sense: the
##     model read 0.090 to 0.260 HIGH on all 37 rows, so a green suite did not
##     imply a passing picture. The band is 3 TEXELS and a four-up card draws it
##     at 0.12–0.49 of source size, so a screen pixel does one bilinear tap at an
##     arbitrary sub-texel phase rather than reading a texel. Now MODELLED, by
##     `_screen_band()` walking the renderer's own sampling grid at the draw
##     scale `screen_battle` gives the row. It is real and it is large: the same
##     row on its four-up card and at draw scale 1.0 differs by up to 0.20:1
##     (E05 ch1 2.469 vs 2.669; E10 ch1 2.568 vs 2.704).
##   • alpha compositing at the cut boundary, which used to be "the proxy
##     compares an opaque colour to the card, the renderer blends the boundary's
##     own alpha into it, worth ~2%". Now MODELLED by the same walk, per fragment
##     rather than as a band mean — `seen_edge` composites `bg.lerp(lit, src.a)`
##     with each sample's own alpha, which is what makes the covariance between a
##     weak rim and a thin alpha come out right instead of averaging separately.
##
## One of the four left makes the proxy read LOW and three read HIGH, and the
## worst measured optimistic bias — the only direction that can hide a failure —
## is +0.0447:1 on bound 1. `CARD_EDGE_MARGIN` covers that number with room to
## spare (0.06) and is added to the bound so the suite's green means something.
## `tools/enemy_legibility.gd` reprints the bias every run and says whether the
## margin still covers it.
##  1. `edge_rgb` was averaged over `alpha > 200` (`enemy_cutout.py`); the shader
##     lights everything with `alpha > 0.2`. Two different bands, and the extra
##     skirt the shader lights is the soft, semi-transparent part. HIGH.
##  2. `edge_rgb` is ONE colour for a whole band. The renderer samples the
##     plate's own RGB per texel and, at a minified tap, blends it with whatever
##     lies beyond the contour. Newly named here rather than newly discovered —
##     it was already written up as bound 3's residual — and promoted because
##     with minification modelled it is now the largest term left. It is what
##     makes bound 3 unresolvable from here: where a wisp stands on one specific
##     piece of contour, the mean colour of the whole band is the wrong colour
##     for it. Mixed direction, and closing it means a per-region `edge_rgb`,
##     i.e. a change to what `tools/enemy_cutout.py` measures.
##  3. `v_modulate` is white here, and the shader multiplies by it
##     (`COLOR = vec4(lit, src.a) * v_modulate`). It is NOT always white on a
##     battle card. `screen_battle._refresh_enemies` sets
##     `card.modulate = Color(0.55, 0.55, 0.6, 0.85)` on every NON-TARGET enemy
##     card whenever `_targeting()` is true, and `modulate` propagates down the
##     CanvasItem tree to the pawn inside — so it is on precisely while a player
##     is scanning the row of silhouettes to pick one. Nothing here or in
##     `tools/enemy_legibility.gd` models it and no bound covers it; what it
##     costs was rendered instead, and the answer is in `task-6-report.md` and in
##     the tool's own `LEGIBILITY DIM` lines. (`screen_codex.gd`'s unseen-entry
##     silhouette also carries one, and that one is meant to be unreadable.)
##     HIGH where it applies.
##  4. The bloom pass adds `glow * 0.055` before the rim mix. Small at the
##     silhouette's boundary — the mask it gathers is eyes and cracks, which are
##     interior — but it is real and it is unmodelled. LOW.
##
## ── WHAT IS LEFT, MEASURED. READ THIS BEFORE TRUSTING A GREEN RUN ──
## Task 6 rendered all 37 rows a third time with `_screen_band()` in place
## (`art_export/legib.log`; the picture did not change, and the rendered column
## is identical to the previous run's to the last digit, which is the
## determinism check):
##   bound 1 — RECONCILED. Worst disagreement 0.045 (E05 ch1), against a
##     DELTA_MAX of 0.15, and the residual is now two-sided: −0.028 (E01 ch3,
##     E02 ch2) to +0.045. It is no longer a bias with a direction, it is noise
##     around the picture. The one-sided part that remains, +0.0447, is what
##     `CARD_EDGE_MARGIN` (0.06) has to cover, and does.
##   bound 2 — CONSERVATIVE WITHOUT HELP. It is a CAP, and the model is at or
##     above the render on all 37 rows (worst modelled 20.2% at B2 against 9.2%
##     rendered; worst rendered anywhere 14.8%). Reading high is the safe
##     direction for a cap, so no margin is needed or added.
##   bound 3 — NOT RECONCILED, AND NOT RECONCILABLE FROM HERE. 0.000 to 0.459,
##     in BOTH directions, against a floor of 1.55. Two causes, both named and
##     neither correctable in a headless test: rows where the veil stands on
##     almost none of the contour, so the render's own mean is over a handful of
##     pixels sitting on a wisp's rasterised boundary (E09 ch2: 0.4% of the band,
##     14 rendered pixels, and the worst delta in the table); and #2 above, the
##     one-colour-per-band covariance — E05 ch3 renders at 1.604:1 where this
##     says 1.973:1, and it is the row the bound stands on. NOT one of the causes,
##     any more: the mist background itself, which the render now measures and
##     which agrees with `card_behind` to 0.72 of an 8-bit step.
##
## So: a green `_t_enemy_legibility` implies the render clears BOUND 1, because
## the model is reconciled to 0.045 and the check carries a larger margin than
## that on top of the floor; and it implies the render clears BOUND 2, because
## the model overstates a cap. It does NOT imply anything about bound 3 in
## either direction. Bound 3 IS still asserted — an unmargined `_check` that can
## fail the suite — but only as a loose regression guard on the model's own
## number; at ±0.46 against a 1.55 floor it has redded a row the render passes
## (E09 ch3, 1.893 modelled vs 1.930 rendered, at the old 1.9 floor) and passed
## the row the render failed (E05 ch3, 2.002 vs 1.600). A one-sided margin there
## would be a false guarantee — the model is wrong both ways — and one large
## enough to cover 0.459 would red rows the picture passes. BOUND 3'S INSTRUMENT
## OF RECORD IS `tools/enemy_legibility.gd`, and it has to be re-run whenever a
## plate, a mist dial, a card layout or a chapter colour moves. That is also
## true of `CARD_EDGE_MARGIN`, which is a measurement and goes stale like one;
## the tool prints `MARGIN TOO SMALL` the moment it does. See
## `task-6-report.md`.
##
## `strength` defaults to `rot_rim_for(chapter)`; pass it only to ask what a
## DIFFERENT rim would do to this edge, as `_t_rot_rim`'s tightness check does.
## Both halves of that check go through here on purpose, so a term added to this
## function lands on both.
## `coverage` is the shader's `edge` scalar averaged over this band, i.e. the
## fraction of the declared rim that the band actually receives — measure it with
## `rim_coverage(key)`. It defaults to 1.0, which is the PURE-CURVE case
## `_t_rot_rim` asks about ("does `rot_rim_for` reach its own declared target"),
## and is not the picture; every caller that is predicting a real silhouette
## passes the measured number.
func lit_edge(edge: Color, chapter: int, strength := -1.0, coverage := 1.0) -> Color:
	var s := UITheme.rot_rim_for(chapter) if strength < 0.0 else strength
	# ONE factor on the SAME curve, not a second copy of it: `rot_rim_for` still
	# owns how hard the rim is asked to work, and `coverage` says how much of that
	# ask lands on the band. Multiplying here means a retuned curve and a retuned
	# `rim_px` both move this number, and neither can move it alone.
	return edge.lerp(UITheme.ROT_RIM, clampf(s * coverage, 0.0, 1.0))


var _cover_rim_cache := {}
var _alpha_cache := {}


## The shader's own `edge` scalar — `src.a * (1.0 - amin)` from
## `rot_pawn.gdshader`'s rim line — averaged over exactly the band `_edge_band`
## marks and `lit_edge` speaks for. This is the term `lit_edge` used to pin at
## 1.0, and pinning it there was the whole of the 0.99–1.33 gap Task 6's render
## found on all 37 rows.
##
## COMPUTED, not tabulated, and computed from geometry rather than from a fitted
## constant: the plate's own alpha channel, the band `enemy_cutout.py` averaged
## `edge_rgb` over, and `PawnArt.ROT_RIM_PX`. That matters because `rim_px` is
## the tuning lever — a hardcoded 0.56 would have stopped tracking the moment the
## lever moved, which is precisely when it needs to track. Change `ROT_RIM_PX`
## and this follows on its own.
##
## Why it is not 1.0: `amin` is the minimum over 8 rays of length `rim_px`
## TEXELS, so a band texel at depth `d` inside the `alpha > 200` contour has its
## most-outward ray land `rim_px - d` texels OUTSIDE that contour. The band is 3
## texels deep. At `rim_px = 3` the innermost ring's ray lands on the contour
## itself, where alpha is still ~0.78, so `1 - amin` is ~0.2 there and the band
## mean comes out 0.562–0.677. At `rim_px = 6` every ring clears the skirt and
## the mean is 0.95–0.97, i.e. `lit_edge`'s old assumption becomes very nearly
## true — which is why the correction and the lever were applied together.
##
## Cross-checked against the picture two ways in Task 6 and it is the mechanism,
## not a fudge: the rim strength fitted back out of the RENDERED pixels
## (`enemy_legibility._fit_strength`, bisected on luminance) agrees with this to
## 0.041 worst over the seventeen plates, and orders the keys the same way.
##
## Bilinear, clamped at the plate's border, mipmaps off — what the GPU samples
## under the project's default linear canvas filter with repeat off, which is how
## every plate is imported.
func rim_coverage(p_kind: String, p_rim_px := -1.0) -> float:
	var r: float = PawnArt.ROT_RIM_PX if p_rim_px < 0.0 else p_rim_px
	var ck := "%s/%.3f" % [p_kind, r]
	if _cover_rim_cache.has(ck):
		return float(_cover_rim_cache[ck])
	# seeded before the work so a re-entrant call on a broken plate cannot loop,
	# and so a bail-out below leaves the neutral 1.0 rather than a stale number
	_cover_rim_cache[ck] = 1.0
	var band := _edge_band(p_kind)
	if band.is_empty() or int(band["n"]) <= 0:
		return 1.0
	var w: int = band["w"]
	var h: int = band["h"]
	var mask: PackedByteArray = band["px"]
	var a := _plate_alpha(p_kind)
	if a.is_empty():
		return 1.0
	# the shader's 8 fixed directions, resolved to texel offsets once
	var ox := PackedFloat32Array()
	var oy := PackedFloat32Array()
	for i in 8:
		var ang := float(i) * 0.7853981
		ox.append(cos(ang) * r)
		oy.append(sin(ang) * r)
	var acc := 0.0
	var n := 0
	for y in h:
		var row := y * w
		for x in w:
			if mask[row + x] == 0:
				continue
			var amin := 1.0
			for i in 8:
				amin = minf(amin, _bilinear_a(a, w, h, float(x) + ox[i], float(y) + oy[i]))
			acc += a[row + x] * (1.0 - amin)
			n += 1
	var out := acc / maxf(float(n), 1.0)
	_cover_rim_cache[ck] = out
	return out


## A plate's alpha channel as 0–1 floats, once per key.
func _plate_alpha(p_kind: String) -> PackedFloat32Array:
	if _alpha_cache.has(p_kind):
		return _alpha_cache[p_kind]
	var empty := PackedFloat32Array()
	_alpha_cache[p_kind] = empty
	var tex := PawnArt.enemy_texture(p_kind)
	if tex == null:
		_check(false, "%s has no plate to read a rim coverage off" % p_kind)
		return empty
	var img := tex.get_image()
	if img == null:
		_check(false, "%s plate has no image" % p_kind)
		return empty
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	var a := PackedFloat32Array()
	a.resize(img.get_width() * img.get_height())
	for i in a.size():
		a[i] = float(d[i * 4 + 3]) / 255.0
	_alpha_cache[p_kind] = a
	return a


## Bilinear alpha at TEXEL coordinates (`x + 0.5` is texel `x`'s centre), edges
## clamped. `fx` is already the shader's `UV.x * width - 0.5`, so a caller adds
## its ray offset in texels directly.
func _bilinear_a(a: PackedFloat32Array, w: int, h: int, fx: float, fy: float) -> float:
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var x1 := clampi(x0 + 1, 0, w - 1)
	var y1 := clampi(y0 + 1, 0, h - 1)
	x0 = clampi(x0, 0, w - 1)
	y0 = clampi(y0, 0, h - 1)
	return lerpf(lerpf(a[y0 * w + x0], a[y0 * w + x1], tx),
			lerpf(a[y1 * w + x0], a[y1 * w + x1], tx), ty)


var _screen_cache := {}
var _metrics: Control = null


## The SMALLEST art box `screen_battle` can hand this key — four minions on
## screen, or a boss (height-bound by the enemy band budget in every layout, so
## its boxes all agree). All three bounds are floors, so the smallest box is the
## one that has to hold, and it is also the most minified.
##
## Read off `screen_battle._enemy_metrics()` rather than restated, so a retuned
## card layout moves this check with it — the same reason `tools/enemy_legibility.gd`
## asks the screen for its render sizes instead of tabulating them. The instance
## is a bare `.new()`: no `_ready`, no tree, nothing used but the geometry.
func _art_box(p_kind: String) -> Vector2:
	if _metrics == null:
		_metrics = load("res://scripts/ui/screen_battle.gd").new()
	var m: Dictionary = _metrics._enemy_metrics(4, PawnArt.is_boss(p_kind))
	return Vector2(float(m["w"]) - 2.0 * UIKit.S3, float(m["art"]))


## Drop the bare `screen_battle` `_art_box` keeps for its geometry. It never
## entered the tree, so nothing else will free it and Godot reports it as a leak
## at exit — which matters beyond tidiness, because `tools/test_all.sh` greps the
## logs. `_t_enemy_legibility` calls this when it is done; anything else that
## drives the rendering model (`tools/enemy_legibility.gd`) has to as well, which
## is why this is a named method and not four lines at the end of the test.
func free_render_model() -> void:
	if _metrics != null:
		_metrics.free()
		_metrics = null


## The edge band AS THE SCREEN SAMPLES IT — one entry per screen pixel that
## lands on the band, at the draw scale this row is really given, carrying the
## two per-fragment quantities `rot_pawn.gdshader`'s last two lines need: the
## rim's `edge` scalar and `src.a`.
##
## ── Why this exists: minification ────────────────────────────────
## The band is 3 TEXELS deep and the plates are drawn at 0.12–0.49 of source
## size on a four-up card, so a screen pixel does not read a texel — it does ONE
## bilinear tap at an arbitrary sub-texel phase (mipmaps are off on every plate,
## so there is no second sample and no LOD). Two things follow, both of which
## pull the rendered contrast DOWN and neither of which a texel-wise band mean
## can see:
##   • `src.a` at that tap is a blend of band texels with the exterior beyond
##     them, so the fragment composites over the card at less than full opacity;
##   • `edge = src.a * (1 - amin)` is evaluated from that same blended alpha and
##     at a ray origin off the texel grid, so the rim is weaker there too.
## Task 6 measured the size of it: the same row rendered on its four-up card and
## at draw scale 1.0 differs by up to 0.20:1 (E05 ch1 2.469 vs 2.669), and the
## gap tracked draw scale. It was the largest remaining term in the proxy's
## residual, and it is the term this function exists to remove.
##
## The sampling grid is the renderer's, not an approximation of it: `PawnArt`
## draws the plate into `Rect2(-w/2, -h, w, h)`, so screen pixel `i`'s centre
## interpolates to `u = (i + 0.5) / w`, and the texel coordinate the GPU
## bilinearly filters around is `u * tex_w - 0.5`. Band membership is decided by
## the texel that pixel is IN (`int(u * tex_w)`), which is the same projection
## `tools/enemy_legibility.gd` uses to pick its screen pixels — the two rulers
## have to select the same set or the deltas mean nothing.
##
## `p_native` samples at draw scale 1.0 instead, where the grid lands on texel
## centres and this degenerates to the texel-wise band mean. That is the ruler
## `tools/enemy_legibility.gd` reads bound 3 off (the four-up card leaves as few
## as 14 veiled pixels, which is not a measurement), so the tool asks for it and
## compares like with like.
func _screen_band(p_kind: String, p_tier: int, p_native := false) -> Dictionary:
	var ck := "%s/%d/%s" % [p_kind, p_tier, p_native]
	if _screen_cache.has(ck):
		return _screen_cache[ck]
	var empty := {"edge": PackedFloat32Array(), "alpha": PackedFloat32Array(), "scale": 0.0}
	_screen_cache[ck] = empty
	var band := _edge_band(p_kind)
	if band.is_empty() or int(band["n"]) <= 0:
		return empty
	var a := _plate_alpha(p_kind)
	if a.is_empty():
		return empty
	var tw: int = band["w"]
	var th: int = band["h"]
	var mask: PackedByteArray = band["px"]

	# the height the card gives this row, and the scale that lands the plate at
	# it — `fit_height` sizes against tier 3, `bulk` puts the row back at its own
	# tier, exactly as `PawnArt.make` does when the battle screen builds the pawn
	var h := float(th)
	if not p_native:
		h = PawnArt.fit_height(p_kind, _art_box(p_kind)) * PawnArt.bulk(p_kind, p_tier)
	var w := h * float(tw) / maxf(float(th), 1.0)
	var scale := h / maxf(float(th), 1.0)

	# the shader's 8 fixed directions at `rim_px` TEXELS, resolved once
	var r: float = PawnArt.ROT_RIM_PX
	var ox := PackedFloat32Array()
	var oy := PackedFloat32Array()
	for i in 8:
		var ang := float(i) * 0.7853981
		ox.append(cos(ang) * r)
		oy.append(sin(ang) * r)
	# the column geometry does not depend on the row, so it is resolved once too
	var cx_n := PackedInt32Array()
	var cx_f := PackedFloat32Array()
	for px in int(ceil(w)):
		var u := (float(px) + 0.5) / w
		if u >= 1.0:
			break
		cx_n.append(clampi(int(u * float(tw)), 0, tw - 1))
		cx_f.append(u * float(tw) - 0.5)

	var e_out := PackedFloat32Array()
	var a_out := PackedFloat32Array()
	for py in int(ceil(h)):
		var v := (float(py) + 0.5) / h
		if v >= 1.0:
			break
		var fy := v * float(th) - 0.5
		var row := clampi(int(v * float(th)), 0, th - 1) * tw
		for i in cx_n.size():
			if mask[row + cx_n[i]] == 0:
				continue
			var fx := cx_f[i]
			var sa := _bilinear_a(a, tw, th, fx, fy)
			var e := 0.0
			# `rim_strength > 0.001 && src.a > 0.2` is the shader's own gate: a
			# tap that lands too far into the skirt gets no rim at all, which is
			# part of what minification costs and not a special case here
			if sa > 0.2:
				var amin := 1.0
				for k in 8:
					amin = minf(amin, _bilinear_a(a, tw, th, fx + ox[k], fy + oy[k]))
				e = sa * (1.0 - amin)
			e_out.append(e)
			a_out.append(sa)
	var out := {"edge": e_out, "alpha": a_out, "scale": scale}
	_screen_cache[ck] = out
	return out


## What the eye is actually handed: the modelled lit edge composited over `bg`
## at the alpha each fragment carries, averaged over the screen pixels the band
## lands on. This is the quantity bounds 1 and 3 are held to.
##
## Per-sample rather than mean-of-terms on purpose. `edge` and `src.a` fall off
## together across the band, so a lit colour built from the two means would miss
## their covariance; this composites each fragment the way the renderer does and
## then averages the result, which is what the render's own band mean is.
##
## The blend itself is still `lit_edge` — one source for the rim curve, called
## once per sample with that sample's own coverage instead of once with the band
## mean. `bg.lerp(lit, a)` is `COLOR = vec4(lit, src.a)` under the canvas
## blend mode, i.e. straight alpha over whatever is already there.
func seen_edge(edge: Color, chapter: int, p_kind: String, p_tier: int, bg: Color,
		p_native := false) -> Color:
	var s := _screen_band(p_kind, p_tier, p_native)
	var es: PackedFloat32Array = s["edge"]
	var als: PackedFloat32Array = s["alpha"]
	var n := es.size()
	if n <= 0:
		# no band to sample — fall back to the un-composited model rather than
		# silently reporting the background, which would read as a hard failure
		# for a reason that has nothing to do with the rim
		return lit_edge(edge, chapter, -1.0, rim_coverage(p_kind))
	var acc := Color(0.0, 0.0, 0.0)
	for i in n:
		acc += bg.lerp(lit_edge(edge, chapter, -1.0, es[i]), clampf(als[i], 0.0, 1.0))
	return Color(acc.r / float(n), acc.g / float(n), acc.b / float(n))


## What is behind the MIST-BACKED part of an enemy's silhouette on a battle
## card — the background bound 3 is measured against.
##
## Not the card. `PawnArt._draw` calls `_auto_mist` BEFORE `draw_texture_rect`,
## and inside the plate's own footprint, so wherever a wisp falls the local
## background is `ROT_MIST` over `surface(chapter)` — and `ROT_MIST` (luminance
## 0.0578) is brighter than every card (0.0242 / 0.0210 / 0.0094), so it RAISES
## the luminance the lit edge has to clear. On a row with no wisps this is the
## bare card and bound 3 collapses onto bound 1.
##
## HOW MUCH of the contour this speaks for is not assumed here — it is measured,
## per key, by `mist_coverage()`, and bounded by `MIST_COVER_CAP`. That is what
## makes it legitimate to hold this background to a different (1.55:1) bar than
## the bare card's 2.4:1 instead of applying one bar to a blend of the two.
##
## One flat layer is a measured claim, not a convenience: instrumenting
## `_stamp_wisp` to count band pixels claimed by a second wisp, over all
## seventeen plates and both idle frames, finds them on exactly one key — B2, 32
## px, 0.3% of its own band — and zero everywhere else. So alphas are not
## compounded. (Round 2's independent rasteriser found the same 32.)
##
## THIS COLOUR IS NOW CHECKED AGAINST THE RENDER, and it survives. It used to
## carry a residual on the wisp's "anti-aliased boundary", argued to be small and
## conservative. That residual does not exist: `PawnArt._wisp` draws with
## `draw_colored_polygon`, which performs no anti-aliasing, and this project sets
## no `msaa_2d` — a covered pixel is fully covered and an uncovered one is
## untouched. So there was nothing to be conservative about, and the claim was
## replaced by a measurement rather than by a smaller argument.
##
## `tools/enemy_legibility.gd:_sample_mist` reads the real thing out of the frame
## buffer — every pixel a wisp covers where the plate's own alpha tap is zero, so
## what is on screen there is exactly `ROT_MIST` at `mist_alpha` over
## `surface(chapter)` as the engine blended it, with pixels under a second wisp
## excluded because this models ONE flat layer. Against that, over all 27
## wisp-bearing rows, the worst disagreement on any channel is **0.0028, i.e. 0.72
## of one 8-bit step** (chapter 2; chapter 1 is 0.40/255 and chapter 3 is
## 0.16/255). Bound 3's binding row moves 1.600 -> 1.604 when measured against the
## rendered background instead of this one, so the floor's margin goes to +0.054.
## The `lerp` is right because `gl_compatibility` blends canvas items in sRGB,
## exactly as it does.
##
## 25 of the 27 are measured on their own render (123 to 8534 qualifying pixels).
## The other two are E09's, and the reason is worth knowing: E09's wisps stand
## entirely BEHIND its silhouette — every pixel inside one of them has plate alpha
## 0.79 (tier 2) / 0.13 (tier 3) or more over it, so there is nowhere in E09's
## picture that mist-over-card is visible unoccluded. The colour is a function of
## `chapter` and `mist_alpha` only, and `mist_alpha` is `0.34 + 0.30 * rot_of`
## where `rot_of` is tier, never the key, so the tool takes E09's from another row
## with the same pair rather than falling back here.
##
## `MIST_COUNT`, `mist_alpha` and `rot_of` are read from `PawnArt` rather than
## restated, so the mist has one source the way the rim has one.
func card_behind(chapter: int, kind: String, tier: int) -> Color:
	var row := PawnArt.dial_row(kind, tier)
	if int(PawnArt.MIST_COUNT[row]) <= 0:
		return UITheme.surface(chapter)
	return UITheme.surface(chapter).lerp(UITheme.ROT_MIST,
			clampf(PawnArt.mist_alpha(kind, tier), 0.0, 1.0))


var _band_cache := {}
var _cover_cache := {}


## What fraction of `p_kind`'s edge band has a wisp behind it at `p_tier` — the
## quantity `MIST_COVER_CAP` bounds, and the reason bounds 1 and 3 are allowed
## to be different numbers.
##
## Measured, not tabulated. `PawnArt.mist_spots` / `wisp_outline` / `wisp_phase`
## hand back the very polygons `_auto_mist` draws (statics, so there is one copy
## of the geometry and the test cannot drift from the picture), asked for in
## normalised units — `w = aspect, h = 1` — and scan-converted into the plate's
## own texture grid, where `_edge_band` has already marked the band
## `tools/enemy_cutout.py:295` averages `edge_rgb` over: `alpha > 200`, minus
## three 3×3 erosions.
##
## Both stepped idle frames are rasterised and the WORSE of the two is returned:
## only one of them is on screen at a time, so the max is the worst instant a
## player can be looking at, which is what a floor wants.
##
## Scale-free, so one number covers every card layout: `_auto_mist` places
## everything in units of the pawn's own `w` and `h`, and `w/h` is the texture's
## own aspect at every size, so the fraction depends on the silhouette and the
## aspect and on nothing else. Flip is irrelevant for the same reason — `_draw`
## mirrors the wisps (`_c`) and the plate (its own `draw_set_transform`, x scaled
## by -1) about the same x = 0, so a flipped pawn is the mirror image of this one
## and covers the same count. That was not true before the Task 7 fix: the plate
## used to be handed to `draw_texture_rect`'s `transpose` parameter, so a flipped
## pawn was rotated rather than mirrored and this paragraph described a picture
## the game was not drawing.
##
## Where it stops being exact: a wisp boundary cuts through pixels, and
## `SUB_ROWS` decides those in the conservative direction — touched counts as
## covered. Measured against the alternative, centre sampling reads 0.3–1.5
## points lower on every one of the seventeen and reorders none of them.
##
## Reconciles with the independent round-2 rasterisation recorded in
## `task-5-report.md`: identical band sizes (158496 px over the seventeen), and
## 16799 covered band px at five wisps against its 16785 — fourteen pixels apart
## in 158496, one of them on B2 (1874 here, 1875 there, i.e. 20.25% vs 20.26%).
func mist_coverage(p_kind: String, p_tier: int) -> float:
	var ck := "%s/%d" % [p_kind, p_tier]
	if _cover_cache.has(ck):
		return float(_cover_cache[ck])
	_cover_cache[ck] = 0.0
	var band := _edge_band(p_kind)
	if band.is_empty():
		return 0.0
	var w: int = band["w"]
	var h: int = band["h"]
	var total: int = band["n"]
	var mask: PackedByteArray = band["px"]
	if total <= 0:
		_check(false, "%s has no measurable edge band to put the mist fraction over" % p_kind)
		return 0.0
	var aspect := float(w) / float(h)
	var spots := PawnArt.mist_spots(p_kind, p_tier, aspect, 1.0)
	if spots.is_empty():
		return 0.0
	var worst := 0.0
	for step in [0.0, 1.0]:
		var hit := PackedByteArray()
		hit.resize(w * h)
		var covered := 0
		for i in spots.size():
			var s: Array = spots[i]
			covered += _stamp_wisp(PawnArt.wisp_outline(
					Vector2(float(s[0]), float(s[1])), float(s[2]),
					PawnArt.wisp_phase(i, step)), w, h, aspect, hit, mask)
		worst = maxf(worst, float(covered) / float(total))
	_cover_cache[ck] = worst
	return worst


## Scan-converts one wisp polygon into `hit` and returns how many BAND pixels it
## newly covered — newly, so two wisps overlapping cannot double-count the same
## pixel. Crossings are taken at each row's pixel-centre y, sorted, and filled
## in pairs (even-odd), which is the region `draw_colored_polygon` fills for a
## simple polygon like this one.
##
## Texture pixel (x, y) sits at drawing-space (`(x + 0.5) / w - 0.5`) * aspect,
## (`y + 0.5) / h - 1`: `_draw` places the plate in `Rect2(-w/2, -h, w, h)`, so
## texture row 0 is the TOP of the drawn rect, at y = -h.
func _stamp_wisp(poly: PackedVector2Array, w: int, h: int, aspect: float,
		hit: PackedByteArray, mask: PackedByteArray) -> int:
	var lo := poly[0].y
	var hi := poly[0].y
	for p in poly:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var y0 := maxi(0, int(floor((lo + 1.0) * float(h))))
	var y1 := mini(h - 1, int(floor((hi + 1.0) * float(h))))
	var n := poly.size()
	var added := 0
	for py in range(y0, y1 + 1):
		for sub in SUB_ROWS:
			var yu := (float(py) + (float(sub) + 0.5) / float(SUB_ROWS)) / float(h) - 1.0
			var xs := PackedFloat32Array()
			for i in n:
				var a := poly[i]
				var b := poly[(i + 1) % n]
				if (a.y <= yu) == (b.y <= yu):
					continue
				xs.append(a.x + (yu - a.y) / (b.y - a.y) * (b.x - a.x))
			if xs.size() < 2:
				continue
			xs.sort()
			var row := py * w
			var k := 0
			while k + 1 < xs.size():
				var x0 := maxi(0, int(floor((xs[k] / aspect + 0.5) * float(w))))
				var x1 := mini(w - 1, int(floor((xs[k + 1] / aspect + 0.5) * float(w))))
				for px in range(x0, x1 + 1):
					if hit[row + px] == 0:
						hit[row + px] = 1
						if mask[row + px] == 1:
							added += 1
				k += 2
	return added


## The outermost band of a plate's silhouette, as a `w * h` byte mask — the same
## set `tools/enemy_cutout.py:295` averages `edge_rgb` over, so the fraction
## `mist_coverage` reports is a fraction of exactly the pixels `lit_edge` is
## speaking for.
##
## `binary_erosion(solid, ones((3,3)), iterations=3)` is one erosion by a 7×7
## square, and a square structuring element is separable, so this is two
## run-length passes instead of 49 neighbour reads per pixel — 17 plates and
## 2.8M pixels is enough for that to matter in GDScript. `scipy`'s default
## `border_value=0` pads with background, so a window reaching outside the image
## does not erode; the `x >= 3 and x + 3 < w` guards are that padding.
func _edge_band(p_kind: String) -> Dictionary:
	if _band_cache.has(p_kind):
		return _band_cache[p_kind]
	_band_cache[p_kind] = {}
	var tex := PawnArt.enemy_texture(p_kind)
	if tex == null:
		_check(false, "%s has no plate to measure a mist fraction against" % p_kind)
		return {}
	var img := tex.get_image()
	if img == null:
		_check(false, "%s plate has no image" % p_kind)
		return {}
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var count := w * h
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(count)
	for i in count:
		solid[i] = 1 if data[i * 4 + 3] > 200 else 0
	# horizontal: run[i] = how many solid pixels end at i, so the 7-wide window
	# centred on x is all-solid exactly when run[x + 3] >= 7
	var run := PackedInt32Array()
	run.resize(count)
	var eroded_h := PackedByteArray()
	eroded_h.resize(count)
	for y in h:
		var row := y * w
		var r := 0
		for x in w:
			r = r + 1 if solid[row + x] == 1 else 0
			run[row + x] = r
		for x2 in w:
			eroded_h[row + x2] = 1 if (x2 >= 3 and x2 + 3 < w
					and run[row + x2 + 3] >= 7) else 0
	# vertical, over the horizontally-eroded mask
	for x3 in w:
		var r2 := 0
		for y2 in h:
			r2 = r2 + 1 if eroded_h[y2 * w + x3] == 1 else 0
			run[y2 * w + x3] = r2
	var band := PackedByteArray()
	band.resize(count)
	var n := 0
	for y3 in h:
		var row2 := y3 * w
		var inside := y3 >= 3 and y3 + 3 < h
		var ahead := (y3 + 3) * w
		for x4 in w:
			var b := 0
			if solid[row2 + x4] == 1 and not (inside and run[ahead + x4] >= 7):
				b = 1
				n += 1
			band[row2 + x4] = b
	var out := {"w": w, "h": h, "n": n, "px": band}
	_band_cache[p_kind] = out
	return out


## Every enemy is a plate now. This is the rule that keeps the hand-drawn
## routines from creeping back: if a key has no texture there is no fallback
## that could quietly draw a creature instead.
func _t_enemy_sprites() -> void:
	var keys := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10",
			"B1", "B2", "B3", "B3P2", "B4", "B5", "B6"]
	for k in keys:
		var tex := PawnArt.enemy_texture(k)
		_check(tex != null, "%s has no sprite in assets/enemies/" % k)
		if tex != null:
			_check(tex.get_width() > 40 and tex.get_height() > 40,
					"%s sprite is %dx%d, too small to be a real cut"
					% [k, tex.get_width(), tex.get_height()])
		# the corruption mask IS the glow mechanism (red=eye, green=vein,
		# blue=ember). A missing one is silent — set_shader_parameter(null) on a
		# hint_default_black uniform just reads as "no glow", not an error — so
		# it has to be checked here, not inferred from the glow being visible.
		_check(PawnArt.rot_mask_texture(k) != null,
				"%s has no corruption mask — rot_mask_texture() returned null" % k)

	# the pawn actually carries the corruption shader, and the shader itself
	# actually loaded (a ShaderMaterial with shader == null still stores and
	# returns shader parameters, so a dead ROT_SHADER load would pass every
	# get_shader_parameter() check below unless this is checked directly)
	var pa := PawnArt.make("E01", 140.0, false, 3, 3)
	add_child(pa)
	await get_tree().process_frame
	_check(pa.material is ShaderMaterial, "E01 pawn has no ShaderMaterial")
	var rim3 := -1.0
	if pa.material is ShaderMaterial:
		var m: ShaderMaterial = pa.material
		_check(m.shader != null,
				"chapter 3 pawn's ShaderMaterial has no shader — ROT_SHADER failed to load")
		rim3 = float(m.get_shader_parameter("rim_strength"))
		_check(is_equal_approx(rim3, UITheme.rot_rim_for(3)),
				"chapter 3 rim_strength is %.3f, must equal UITheme.rot_rim_for(3) = %.3f"
				% [rim3, UITheme.rot_rim_for(3)])
		_check(float(m.get_shader_parameter("vein_gain")) > 0.0,
				"tier 3 pawn got no vein glow")

	# a chapter-1 pawn, so rim_strength has something to differ from — the old
	# `> 0.0` check passed at any chapter because rot_rim_for(1) is well above 0
	var t1 := PawnArt.make("E01", 140.0, false, 1, 1)
	add_child(t1)
	await get_tree().process_frame
	var rim1 := -1.0
	if t1.material is ShaderMaterial:
		var m1: ShaderMaterial = t1.material
		_check(m1.shader != null,
				"chapter 1 pawn's ShaderMaterial has no shader — ROT_SHADER failed to load")
		rim1 = float(m1.get_shader_parameter("rim_strength"))
		_check(is_equal_approx(rim1, UITheme.rot_rim_for(1)),
				"chapter 1 rim_strength is %.3f, must equal UITheme.rot_rim_for(1) = %.3f"
				% [rim1, UITheme.rot_rim_for(1)])
		_check(float(m1.get_shader_parameter("vein_gain")) == 0.0,
				"tier 1 must have no vein glow — it is one of the five tier dials")
	_check(not is_equal_approx(rim1, rim3),
			"chapter 1 (%.3f) and chapter 3 (%.3f) rim_strength must differ — otherwise the 5th p_chapter parameter is doing nothing"
			% [rim1, rim3])
	pa.queue_free()
	t1.queue_free()

	# a boss, at the tier battle_core actually gives it. battle_core.gd:179
	# files a boss under "tier": int(def.chapter), so B1 (met in chapter 1)
	# arrives here carrying tier 1 — the same call a real battle makes. If
	# _dial_row() ever regresses to reading the raw tier instead of rot_of(),
	# B1/B2 would silently drop to the T1 dial row (cold eyes, no smoke) while
	# every other boss stayed fully corrupted.
	var boss1 := PawnArt.make("B1", 140.0, false, 1)
	add_child(boss1)
	await get_tree().process_frame
	_check(boss1.material is ShaderMaterial, "B1 pawn has no ShaderMaterial")
	if boss1.material is ShaderMaterial:
		var bm: ShaderMaterial = boss1.material
		_check(is_equal_approx(float(bm.get_shader_parameter("eye_gain")), PawnArt.EYE_GAIN[2]),
				"B1 at tier 1 got eye_gain %.2f, must be EYE_GAIN[2]=%.2f — a boss always runs the top dial row"
				% [float(bm.get_shader_parameter("eye_gain")), PawnArt.EYE_GAIN[2]])
		_check(is_equal_approx(float(bm.get_shader_parameter("vein_gain")), PawnArt.VEIN_GAIN[2]),
				"B1 at tier 1 got vein_gain %.2f, must be VEIN_GAIN[2]=%.2f — a boss is never on the T1 row"
				% [float(bm.get_shader_parameter("vein_gain")), PawnArt.VEIN_GAIN[2]])
	boss1.queue_free()

	# extents come off the sprites now: trimmed art always fills its height
	for k2 in keys:
		_check(is_equal_approx(PawnArt.extent(k2).x, 1.0),
				"%s extent.x is %.2f — trimmed sprites always reach 1.00"
				% [k2, PawnArt.extent(k2).x])


## The floating-number regression: a damage number has to land inside the rect
## of the thing it happened to. The old failure was that `_refresh()` frees and
## rebuilds the rows, so the number was measured against cards that had not
## been laid out yet and flew to the top-left corner.
func _t_float_anchors() -> void:
	var battle := _make_battle()
	for i in 6:
		await get_tree().process_frame

	# --- hero side: push a hit through the same event path the enemy turn uses
	var hero_rect: Rect2 = battle.hero_cards[2].get_global_rect()
	battle.bc._ev({"t": "enemy_hit", "hero": 2, "enemy": 0, "dmg": 6, "blocked": 0})
	battle._spawn_floats()
	_check(_float_lands_in(battle, "-6", hero_rect), "hero damage number lands on the hero")

	# --- enemy side, across the rebuild that used to break it
	var enemy_rect: Rect2 = battle.enemy_widgets[0].card.get_global_rect()
	var atk := {}
	for i2 in 4:
		for d in 2:
			var c: Dictionary = battle.bc.can_use(i2, d)
			if c.ok and c.face.has("atk"):
				atk = {"h": i2, "d": d}
				break
		if not atk.is_empty():
			break
	_check(not atk.is_empty(), "found an attack die to spend")
	if not atk.is_empty():
		var hp_before: int = battle.bc.s.enemies[0].hp
		battle._do_use(int(atk.h), int(atk.d), {"target": 0})
		var dealt := hp_before - int(battle.bc.s.enemies[0].hp)
		_check(dealt > 0, "the attack dealt damage")
		_check(_float_lands_in(battle, "-%d" % dealt, enemy_rect),
				"enemy damage number lands on the enemy across a refresh")
	battle.queue_free()


## Is there a visible float with this text whose centre sits inside `rect`?
func _float_lands_in(battle: Control, text: String, rect: Rect2) -> bool:
	for c in battle.float_layer.get_children():
		var l := c as Label
		if l == null or not l.visible or l.text != text:
			continue
		if rect.has_point(l.get_global_rect().get_center()):
			return true
		print("  (float '%s' centre %s outside %s)" % [text, l.get_global_rect().get_center(), rect])
	return false
