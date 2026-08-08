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
const MIST_EDGE_FLOOR := 1.9      # lit edge vs mist-over-card, where mist sits behind it
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
		if guard == 1:
			battle.bc.toggle_lock(0, 0)
			battle._refresh()
			battle.bc.toggle_lock(0, 0)
			battle._refresh()
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
					var dice: Array = battle.bc._targetable_dice()
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
## worst real edge (E09 on chapter 1) falls to 2.35:1 and that test fires.
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
##      the original guarantee and it is not relaxed anywhere.
##   2. `MIST_COVER_CAP` — the mist may never stand on more than 25% of an edge
##      band. Today's worst is B2 at 20.2%. THIS is what makes bound 1
##      meaningful: without it, the veil could grow until "most of the contour
##      is on bare card" quietly stopped being true and bound 1 stopped
##      describing what anyone sees.
##   3. `MIST_EDGE_FLOOR` — where the veil does sit, the edge still reaches
##      1.9:1. Today's worst is E09 ch3 tier3 at 1.990:1. This bounds how bad
##      the veiled tenth is allowed to get.
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
	# per chapter: how many distinct edge colours went in, how many came out. A
	# lerp with strength < 1 is injective, so those two counts have to agree. They
	# stop agreeing exactly when the rim is strong enough to stop lighting the
	# plates and start replacing them — at strength 1.00 every row collapses onto
	# `ROT_RIM` itself and the rows below measure nothing about the sprite. That
	# is what chapter 3 was doing before `rot_rim_for` was solved instead of
	# ramped; this is the guard that keeps it from coming back.
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
			var lit := lit_edge(edge, ch)
			# keyed on the raw channels, not `to_html`: at s ≈ 0.5 the lerp
			# compresses differences by (1 - s), so two plates one 8-bit step
			# apart can round to the same hex and fire this guard for a reason
			# that has nothing to do with the rim. B3 (39,26,40) and B3P2
			# (40,26,38) are already that close.
			edges_in[ch][_colour_key(edge)] = true
			lits_out[ch][_colour_key(lit)] = true
			var wisps: int = PawnArt.MIST_COUNT[PawnArt.dial_row(String(key), tier)]
			var where := "%s ch%d tier%d (%d wisps)" % [key, ch, tier, wisps]

			# ── bound 1: the card-backed edge, at the full 2.4:1 ──
			var card := UITheme.surface(ch)
			var r_card := UITheme.contrast(lit, card)
			if r_card < worst_card:
				worst_card = r_card
				worst_card_what = where
			_check(r_card >= CARD_EDGE_FLOOR,
					"%s: lit edge %s over the bare card %s is %.3f:1, needs %.2f:1"
					% [where, lit.to_html(false), card.to_html(false), r_card,
					CARD_EDGE_FLOOR])

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
			var r_mist := UITheme.contrast(lit, bg)
			if r_mist < worst_mist:
				worst_mist = r_mist
				worst_mist_what = where
			_check(r_mist >= MIST_EDGE_FLOOR,
					"%s: lit edge %s over mist-on-card %s is %.3f:1, needs %.2f:1"
					% [where, lit.to_html(false), bg.to_html(false), r_mist,
					MIST_EDGE_FLOOR])
	for ch in [1, 2, 3]:
		_check(lits_out[ch].size() == edges_in[ch].size(),
				"chapter %d: %d distinct edge colours went in, %d came out — the rim is washing the plates out, not lighting them"
				% [ch, edges_in[ch].size(), lits_out[ch].size()])
	print("enemy legibility: card-backed edge worst is %s at %.3f:1 (floor %.2f, margin %+.3f)"
			% [worst_card_what, worst_card, CARD_EDGE_FLOOR, worst_card - CARD_EDGE_FLOOR])
	print("enemy legibility: mist-backed edge worst is %s at %.3f:1 (floor %.2f, margin %+.3f)"
			% [worst_mist_what, worst_mist, MIST_EDGE_FLOOR, worst_mist - MIST_EDGE_FLOOR])
	print("enemy legibility: mist covers at most %.1f%% of a band, at %s (cap %.1f%%, margin %+.1f pt)"
			% [worst_cover * 100.0, worst_cover_what, MIST_COVER_CAP * 100.0,
			(MIST_COVER_CAP - worst_cover) * 100.0])
	print("enemy legibility: distinct lit edges %d/%d/%d"
			% [lits_out[1].size(), lits_out[2].size(), lits_out[3].size()])


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
## of `rot_pawn.gdshader` with that line's two other inputs pinned: the `edge`
## scalar at 1.0 and `v_modulate` at white.
##
## SIX known ways this pair of functions is a model and not the picture, all six
## written out with numbers in `task-5-report.md`. There were seven: the mist
## used to be on this list as "one flat layer covering the whole edge", which was
## an approximation because a single number was being asked to stand for two
## different backgrounds. It is not on the list any more because it is no longer
## approximated — it is MODELLED, by `mist_coverage()` measuring how much contour
## the veil actually stands on and by the card-backed and mist-backed edges being
## bounded separately. What residual it still has lives on `card_behind` and
## `mist_coverage`, where the measurement is.
##
## Five of the six make the proxy read HIGH (i.e. the real picture is less
## legible than this says):
##  1. `edge` (`src.a * (1 - amin)`) is 1.0 only right at the alpha boundary and
##     falls off inward, so part of the measured band is lit less than this.
##     MEASURED in Task 6, and it is not a minor term — it is the whole
##     divergence. Averaged over this very band, `edge` is 0.562 (E09) to 0.677
##     (B6), never 1.0, because `rim_px` is 3 texels and the band is 3 texels:
##     a ray cast from the band's innermost texel only just reaches the alpha
##     boundary, so `1 - amin` collapses there. See `_t_enemy_legibility`'s
##     header for what that does to the numbers below.
##  2. `edge_rgb` was averaged over `alpha > 200` (`enemy_cutout.py`); the shader
##     lights everything with `alpha > 0.2`. Two different bands, and the extra
##     skirt the shader lights is the soft, semi-transparent part.
##  3. Minification. The band is 3 TEXTURE px; on an enemy battle card the
##     plates draw at 0.12–1.04 of source size, so that band is 0.37–3.11 SCREEN
##     px — per key, and with mipmaps off on every plate. Task 5 expected this to
##     be the term that broke Task 6's reconciliation. MEASURED: it does not
##     affect the ratio at all. Rendering every key at both its smallest and its
##     largest battle-card box — a 2–2.2x change in scale — moves the card-backed
##     edge by at most 0.05:1 (E03 ch1 1.810 vs 1.760; E05 ch1 1.566 vs 1.560).
##     With mipmaps off, a fragment's bilinear fetch spans 2x2 texels whatever
##     the scale, and `amin` is cast at a fixed 3-TEXEL radius, so the shader's
##     output at a given UV does not know how big the plate is being drawn. What
##     scale does change is how MANY screen pixels land in the band — the rim is
##     3 x scale px thick, i.e. sub-pixel on the big plates — which is a real
##     defect in how thin the light reads, but not one this ratio can see.
##  4. Alpha compositing at the cut boundary: the proxy compares an opaque colour
##     to the card, the renderer blends the boundary's own alpha into it.
##  5. `v_modulate` is white here, and the shader multiplies by it. Nothing puts
##     a non-white modulate on an enemy BATTLE-card pawn — the one place that
##     does, `screen_codex.gd`'s unseen-entry silhouette, is meant to be
##     unreadable, so this number does not speak for it.
## And one that makes it read LOW:
##  6. The bloom pass adds `glow * 0.055` before the rim mix. Small at the
##     silhouette's boundary — the mask it gathers is eyes and cracks, which are
##     interior — but it is real and it is unmodelled.
## Task 6 renders the real thing and reconciles at 0.15:1 — the render wins.
##
## ── AND IT DID NOT RECONCILE. READ THIS BEFORE TRUSTING A GREEN RUN ──
## `tools/enemy_legibility.gd` measured all 37 rows on a real render. Every row
## disagrees, in the same direction and by roughly the same amount: this function
## reads 0.99 to 1.33 HIGH on bound 1 and 0.53 to 1.33 high on bound 3. The
## card-backed edge is 1.516:1 (E09 ch1) to 2.202:1 (E08 ch3) in the picture, not
## the 2.752–3.376 printed below, so bound 1's 2.4:1 floor is met by NO enemy at
## any chapter, and bound 3's 1.9:1 by few. Bound 2 is the one that holds — the
## rendered mist cover is at or under the modelled figure on every key.
##
## Approximation #1 is the whole of it, confirmed two independent ways: the rim
## strength fitted back out of the rendered pixels (0.530–0.659 of
## `rot_rim_for`) matches the `edge` scalar computed straight off each plate's
## alpha channel with the shader's own 8-ray formula (0.562–0.677), worst
## agreement 0.041.
##
## The correction is one factor on the blend below — `rot_rim_for(chapter)` times
## that per-key coverage — and it is DELIBERATELY NOT APPLIED. Applying it turns
## 37 rows red, and the bounds do not move; which lever to pull instead is the
## controller's call, and the one the mechanism points at is `rim_px`, which is
## 3 texels precisely because the band is 3 texels. Re-rendered at `rim_px = 6`,
## E09 ch1 goes 1.516 -> 2.494:1 and `edge` goes 0.562 -> 0.957. So until that is
## decided, the numbers this function prints are an upper bound on the picture
## and not a description of it, and a passing `_t_enemy_legibility` says only
## that the MODEL clears the floor.
##
## `strength` defaults to `rot_rim_for(chapter)`; pass it only to ask what a
## DIFFERENT rim would do to this edge, as `_t_rot_rim`'s tightness check does.
## Both halves of that check go through here on purpose, so a term added to this
## function lands on both.
func lit_edge(edge: Color, chapter: int, strength := -1.0) -> Color:
	var s := UITheme.rot_rim_for(chapter) if strength < 0.0 else strength
	return edge.lerp(UITheme.ROT_RIM, clampf(s, 0.0, 1.0))


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
## makes it legitimate to hold this background to a different (1.9:1) bar than
## the bare card's 2.4:1 instead of applying one bar to a blend of the two.
##
## One flat layer is a measured claim, not a convenience: instrumenting
## `_stamp_wisp` to count band pixels claimed by a second wisp, over all
## seventeen plates and both idle frames, finds them on exactly one key — B2, 32
## px, 0.3% of its own band — and zero everywhere else. So alphas are not
## compounded. (Round 2's independent rasteriser found the same 32.)
##
## One approximation remains, and it reads LOW: `draw_colored_polygon` blends in
## sRGB under `gl_compatibility` exactly as this `lerp` does, but the wisp's own
## anti-aliased boundary is not modelled, so the true edge of a wisp is slightly
## more transparent than this says.
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
## aspect and on nothing else. Flip is irrelevant for the same reason —
## `_draw` mirrors the wisps (`_c`) and the plate (`draw_texture_rect`'s
## `flip_h`) about the same x = 0, so a flipped pawn is the mirror image of this
## one and covers the same count.
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
