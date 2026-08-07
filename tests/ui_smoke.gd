extends Node
## Headless UI smoke test: drives the battle screen through both its input
## paths — tap-to-select and drag-and-drop — until the battle ends, asserting
## no crashes and that the result overlay appears.
##   godot --headless --path . res://tests/ui_smoke.tscn

var fails := 0


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
## wherever it went. The 2.4:1 floor is therefore spelled out as a literal in
## `_t_enemy_legibility` instead, so lowering `ROT_RIM_TARGET` is caught there
## rather than nowhere. Measured: drop it to 2.0 and the worst real edge (E09 on
## chapter 1) falls to 2.35:1 and that test fires.
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
		# or the curve has been padded and the plates are being over-lit
		var weaker := UITheme.contrast(Color.BLACK.lerp(UITheme.ROT_RIM, s - 0.02),
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

	var worst := 99.0
	var worst_what := ""
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
		if not (meta[key] is Dictionary and meta[key].has("edge_rgb")):
			_check(false, "enemies.json entry %s has no edge_rgb" % key)
			continue
		var e: Array = meta[key]["edge_rgb"]
		var edge := Color8(int(e[0]), int(e[1]), int(e[2]))
		var chapters: Array = [int(PawnArt.BOSS_CHAPTER[key])] if PawnArt.BOSS_CHAPTER.has(key) \
				else [1, 2, 3]
		for ch in chapters:
			var lit := lit_edge(edge, int(ch))
			var r := UITheme.contrast(lit, UITheme.surface(int(ch)))
			edges_in[int(ch)][edge.to_html(false)] = true
			lits_out[int(ch)][lit.to_html(false)] = true
			if r < worst:
				worst = r
				worst_what = "%s on chapter %d" % [key, ch]
			_check(r >= 2.4, "%s lit edge %s on chapter %d card is %.2f:1, needs 2.4:1"
					% [key, lit.to_html(false), ch, r])
	for ch in [1, 2, 3]:
		_check(lits_out[ch].size() == edges_in[ch].size(),
				"chapter %d: %d distinct edge colours went in, %d came out — the rim is washing the plates out, not lighting them"
				% [ch, edges_in[ch].size(), lits_out[ch].size()])
	print("enemy legibility (proxy): worst is %s at %.2f:1 (distinct lit edges %d/%d/%d)"
			% [worst_what, worst, lits_out[1].size(), lits_out[2].size(), lits_out[3].size()])


## The rim light applied to an edge colour, mirroring the `mix()` at the bottom
## of `rot_pawn.gdshader` with that line's two other inputs pinned: the `edge`
## scalar at 1.0 and `v_modulate` at white.
##
## Six known ways this is a model and not the picture, all six written out with
## numbers in `task-5-report.md`. Five of them make the proxy read HIGH:
##  1. `edge` (`src.a * (1 - amin)`) is 1.0 only right at the alpha boundary and
##     falls off inward, so part of the measured band is lit less than this.
##  2. `edge_rgb` was averaged over `alpha > 200` (`enemy_cutout.py`); the shader
##     lights everything with `alpha > 0.2`. Two different bands, and the extra
##     skirt the shader lights is the soft, semi-transparent part.
##  3. Minification. The band is 3 TEXTURE px; on an enemy battle card the
##     plates draw at 0.12–1.04 of source size, so that band is 0.37–3.11 SCREEN
##     px — per key, and with mipmaps off on every plate.
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
func lit_edge(edge: Color, chapter: int) -> Color:
	return edge.lerp(UITheme.ROT_RIM, clampf(UITheme.rot_rim_for(chapter), 0.0, 1.0))


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
