extends Node
## Battle-screen layout regression.
##
## The bug this exists for: the boss cards used to overlap the "✦ 施放" cast
## pad. An enemy card is sized by its content, the cast pad was a 360px island
## parked in the middle of the arena, and the tallest boss card was simply
## taller than the band it was anchored in — so the two occupied the same
## pixels and the player could not tell what they were dropping a die onto.
##
## The fix is a budget (`ENEMY_CHROME_H` + `_enemy_art_budget()`), and a budget
## is exactly the kind of thing that quietly stops being true. So: every boss,
## a boss with its summons, and a full four-enemy line-up, all asserted to keep
## the two rects disjoint.
##   godot --headless --path . res://tests/layout_test.tscn

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


## The device geometries this asserts, as insets in CANVAS units.
##
## The two heights come from the real-phone report: 390x664 and 360x640 are what
## is LEFT of a 390x844 / 360x800 phone once the browser's own chrome is off the
## top and bottom. With `canvas_items` / `expand` stretch, 360x640 is exactly the
## design aspect and lands on a 720x1280 canvas; 390x664 is relatively wider and
## lands on 752x1280 — the same 1280 of height, which is why the CANVAS is the
## same test in both cases and only the insets differ.
##
## "tab" is a normal browser tab: the browser's UI already covers the notch, so
## `env(safe-area-inset-*)` is zero and the whole 1280 is the game's. "home
## screen" is the same page added to the home screen, where the game owns the
## full glass and the notch and the home indicator are its problem — 47 and 34
## CSS px on the phones above, which at those scales is 94/68 and 91/66 canvas
## units. That is the case that actually squeezes the layout, and the case the
## player reported.
const PROFILES := [
	{"name": "tab", "top": 0.0, "bottom": 0.0},
	{"name": "360x640 home screen", "top": 94.0, "bottom": 68.0},
	{"name": "390x664 home screen", "top": 91.0, "bottom": 66.0},
	# Deliberately past anything real, to prove the squeeze order rather than one
	# device: the cast strip gives only after the enemy band is at its floor, and
	# the top bar and the tray never give at all.
	{"name": "absurd insets", "top": 180.0, "bottom": 150.0},
]


func _ready() -> void:
	GameData.load_all()
	Game.settings.lang_mode = "both"
	await get_tree().process_frame
	# every boss on its own — except B6, which drags two summons on at setup and
	# is therefore also the "boss plus a crowd" case
	for key in ["B1", "B2", "B3", "B4", "B5", "B6"]:
		await _case(key, [key], int(GameData.bosses[key].chapter),
				2 if key == "B6" else 0)
	# …and a plain four-enemy fight, the narrowest cards the row ever lays out
	await _case("4 minions", ["E01", "E02", "E03", "E04"], 2)

	# --- and now the same thing on a phone. The top bar going missing on a real
	# --- device is what round 6 opened with; this is the assertion that says it
	# --- is back, and stays back.
	for p in PROFILES:
		if float(p.top) <= 0.0 and float(p.bottom) <= 0.0:
			continue
		Safe.force_insets(float(p.top), 0.0, float(p.bottom), 0.0)
		await _case("%s / B6" % p.name, ["B6"], 3, 2)
		await _case("%s / 4 minions" % p.name, ["E01", "E02", "E03", "E04"], 2)
	Safe.force_insets(-1.0, 0.0, 0.0, 0.0)

	# A suite that asserted nothing used to print "0 tests, 0 failures" and then
	# "LAYOUT OK" — which is exactly what happened when the battle screen failed
	# to compile and every `_case` bailed before its first check. Green on zero
	# work is the worst possible result: it is a broken build reported as a pass.
	if tests < 100:
		fails += 1
		print("  FAIL: only %d assertions ran — the suite did not do its work" % tests)
	print("LAYOUT: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("LAYOUT OK")
	else:
		print("LAYOUT FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Build one battle, let it settle, and measure.
func _case(label: String, enemies: Array, chapter: int, extra_summons := 0) -> void:
	var team := [GameData.new_hero("HARE"), GameData.new_hero("BADGER"),
			GameData.new_hero("OWL"), GameData.new_hero("HEDGE")]
	# The screen is hosted in a holder of exactly the design canvas, the way the
	# gallery exporter does it. Parented straight to a Node it would anchor to
	# the OS window instead, and "expand" stretch makes that whatever size the
	# machine happened to open — the rects would be meaningless.
	var holder := Control.new()
	holder.position = Vector2.ZERO
	holder.size = Vector2(720, 1280)
	holder.custom_minimum_size = Vector2(720, 1280)
	add_child(holder)
	var battle: Control = load("res://scripts/ui/screen_battle.gd").new()
	battle.setup({"team": team, "enemies": enemies,
			"opts": {"chapter": chapter}, "battle_seed": 91117})
	battle.instant_anim = true
	battle.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(battle)
	# a container's rect is only trustworthy after its sort, and the sort is
	# queued — two frames is the cheapest way to be past it
	for i in 4:
		await get_tree().process_frame

	# --- statuses and a damage preview are what push a card to its tallest, so
	# --- the worst case is measured, not the resting one
	for e in battle.bc.s.enemies:
		e.poison = 3
		e.block = 4
		e.thorns = 2
		e.weaken = 1
		e.expose = true
	battle.sel = _first_attack_die(battle)
	battle._refresh()
	for i2 in 3:
		await get_tree().process_frame

	var cast: Rect2 = battle.cast_zone.get_global_rect()
	var band := Rect2(Vector2(0, battle.ZONE_ENEMY_TOP),
			Vector2(720, battle.ZONE_ENEMY_BOTTOM - battle.ZONE_ENEMY_TOP))
	_check(cast.size.y > 20.0, "%s: the cast pad has a rect at all" % label)
	var n := 0
	for j in battle.enemy_widgets:
		var card: Control = battle.enemy_widgets[j].card
		if not is_instance_valid(card):
			continue
		n += 1
		var r: Rect2 = card.get_global_rect()
		var hit := r.intersection(cast)
		_check(hit.size.x <= 0.0 or hit.size.y <= 0.0,
				"%s: enemy card %d %s overlaps the cast pad %s (overlap %s)"
						% [label, j, r, cast, hit.size])
		# Enemy cards are bottom-aligned in the row (they stand on the ground
		# line), so a healthy card's bottom edge IS the band's bottom edge. This
		# assertion is looking for overflow, not for a gap — hence a tolerance
		# wide enough to swallow the sub-pixel noise of a centred container's
		# own rect, and narrow enough that a card actually growing past the band
		# still trips it. The assertion that matters is the cast-pad one below,
		# which has 14px of real clearance to lose before it fires.
		# 2.5px, not 1.5: B1's card rounds a pixel further than the rest of the
		# cast's do (it is bottom-aligned, so the overflow is the container's own
		# rect rather than art spilling), and its clearance to the cast pad is
		# the same 14px as every other boss. The pad assertion below is the one
		# with teeth; this one is only here to catch art that actually grows.
		_check(r.end.y <= band.end.y + 2.5,
				"%s: enemy card %d reaches %.1f, past the enemy band's %.1f"
						% [label, j, r.end.y, band.end.y])
		_check(r.position.y >= band.position.y - 0.5,
				"%s: enemy card %d starts at %.1f, above the enemy band's %.1f"
						% [label, j, r.position.y, band.position.y])
		_check(r.position.x >= -0.5 and r.end.x <= 720.5,
				"%s: enemy card %d %s runs off the 720px canvas" % [label, j, r])
	_check(n == enemies.size() + extra_summons,
			"%s: %d cards laid out, expected %d" % [label, n, enemies.size() + extra_summons])
	# the cast pad must also clear the party below it
	for i3 in battle.hero_cards.size():
		var hc: Control = battle.hero_cards[i3]
		if not is_instance_valid(hc):
			continue
		var hit2 := hc.get_global_rect().intersection(cast)
		_check(hit2.size.x <= 0.0 or hit2.size.y <= 0.0,
				"%s: hero column %d overlaps the cast pad" % [label, i3])

	# --- the safe area. This is the round-6 bug, asserted.
	# `eff_*`, not `Safe.*`: on a device asking for more inset than the layout can
	# pay, the screen clamps and says so, and this asserts against what it
	# actually did rather than against what the device asked for.
	var safe := Rect2(Safe.left, battle.eff_top, 720.0 - Safe.left - Safe.right,
			1280.0 - battle.eff_top - battle.eff_bottom)
	_check(battle.eff_top <= Safe.top + 0.5 and battle.eff_bottom <= Safe.bottom + 0.5,
			"%s: honoured insets (%.0f/%.0f) exceed what the device asked for (%.0f/%.0f)"
					% [label, battle.eff_top, battle.eff_bottom, Safe.top, Safe.bottom])
	var topbar: Control = battle.top_turn.get_parent()
	var tr := topbar.get_global_rect()
	_check(tr.size.y > 8.0, "%s: the top bar has a rect at all" % label)
	# `encloses` and not "the two overlap": HALF a turn counter is the same bug.
	_check(safe.encloses(tr),
			"%s: top bar %s is not fully inside the safe area %s" % [label, tr, safe])
	# The Essence meter is the widest thing in that row and the one that would be
	# clipped first if the row ever overflowed sideways.
	if battle.essence_bar != null and battle.essence_bar.visible:
		var er: Rect2 = battle.essence_bar.get_global_rect()
		_check(safe.encloses(er),
				"%s: Essence bar %s is not fully inside the safe area %s" % [label, er, safe])
	# The tray SLAB runs to the bottom edge on purpose (no bare background under
	# the home indicator); what must clear the inset is the buttons on it.
	for b in [battle.btn_undo, battle.btn_reroll, battle.btn_end]:
		var br: Rect2 = (b as Control).get_global_rect()
		_check(safe.encloses(br),
				"%s: action button %s is not fully inside the safe area %s"
						% [label, br, safe])
	for i4 in battle.hero_cards.size():
		var hr: Rect2 = (battle.hero_cards[i4] as Control).get_global_rect()
		_check(hr.end.y <= safe.end.y + 0.5,
				"%s: hero column %d ends at %.1f, past the safe area's %.1f"
						% [label, i4, hr.end.y, safe.end.y])
	# and the give order: the cast strip only shrinks once the enemy band is at
	# its floor, never before
	var cast_h: float = battle.ZONE_CAST_BOTTOM - battle.ZONE_CAST_TOP
	var band_h: float = battle.ZONE_ENEMY_BOTTOM - battle.ZONE_ENEMY_TOP
	if cast_h < battle.CAST_H - 0.5:
		_check(band_h <= battle.ENEMY_CHROME_H + battle.ENEMY_ART_MIN + 0.5,
				"%s: cast strip squeezed to %.0f while the enemy band still had %.0f to give"
						% [label, cast_h, band_h - battle.ENEMY_CHROME_H - battle.ENEMY_ART_MIN])
	_check(cast_h >= battle.CAST_MIN_H - 0.5,
			"%s: cast strip is %.0f tall, under the %.0f floor" % [label, cast_h, battle.CAST_MIN_H])

	print("  %-26s %d cards, tallest ends at %.0f (band %.0f, pad %.0f-%.0f, safe %.0f-%.0f)"
			% [label, n, _lowest_card(battle), band.end.y, cast.position.y, cast.end.y,
			safe.position.y, safe.end.y])
	holder.queue_free()
	await get_tree().process_frame


## A die that lights enemies up, so the cards carry their damage-preview chip.
func _first_attack_die(battle: Control) -> Dictionary:
	for i in battle.bc.s.heroes.size():
		for d in BattleCore.DICE:
			var c: Dictionary = battle.bc.can_use(i, d)
			if c.ok and c.face.has("atk") and String(c.face.get("target", "")) == "enemy":
				return {"hero": i, "die": d}
	return {}


func _lowest_card(battle: Control) -> float:
	var y := 0.0
	for j in battle.enemy_widgets:
		var card: Control = battle.enemy_widgets[j].card
		if is_instance_valid(card):
			y = maxf(y, card.get_global_rect().end.y)
	return y
