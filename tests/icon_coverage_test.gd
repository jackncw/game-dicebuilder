extends Node
## Icon coverage: every relic and every potion must have a picture.
##
## Round 14 gave the potions icons and put relic icons on every screen they
## appear on. The failure mode from here on is a NEW relic or potion shipping
## without one — it would not crash, it would just draw the deliberately dull
## `Glyphs._unknown` disc in the battle strip, the shop card and the tally, and
## nobody would notice until a play test.
##
## So this is a linter, not a rendering test. For every id in relics.json and
## potions.json it checks, in order:
##   ① the definition carries a `glyph` key;
##   ② that key is declared in `Glyphs.KEYS`;
##   ③ `glyphs.gd` really draws it — there is a `match` arm for the key, so it
##      cannot be a name that falls through to `_unknown`;
##   ④ no two items share a picture, within a kind or across the two.
##
##   godot --headless --path . res://tests/icon_coverage_test.tscn

var fails := 0
var tests := 0
var _src := ""


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


## Does glyphs.gd have a `match` arm that draws `key`? Reading the source is
## the only way to tell a key that is merely LISTED from one that is DRAWN —
## `Glyphs.has()` answers the first question, and the whole point of this suite
## is the second.
func _is_drawn(key: String) -> bool:
	if _src == "":
		_src = FileAccess.get_file_as_string("res://scripts/ui/glyphs.gd")
	return _src.contains('"%s":' % key) or _src.contains('"%s",' % key + " ") \
			or _src.contains('"%s", "' % key)


func _defs(d: Dictionary) -> Array:
	var out := []
	for k in d:
		if not String(k).begins_with("_"):
			out.append(String(k))
	out.sort()
	return out


func _ready() -> void:
	GameData.load_all()
	var used := {}          # glyph key -> the id that claimed it

	for kind in [["relic", GameData.relics], ["potion", GameData.potions]]:
		var label: String = kind[0]
		var table: Dictionary = kind[1]
		var ids := _defs(table)
		_check(not ids.is_empty(), "%s table is not empty" % label)
		for id in ids:
			var def: Dictionary = table[id]
			var g := String(def.get("glyph", ""))
			_check(g != "", "%s %s has a `glyph` key — no icon, no ship" % [label, id])
			if g == "":
				continue
			_check(Glyphs.has(g),
					"%s %s's glyph \"%s\" is declared in Glyphs.KEYS" % [label, id, g])
			_check(_is_drawn(g),
					"%s %s's glyph \"%s\" has a drawing in glyphs.gd (a key with no "
					% [label, id, g] + "match arm falls through to the blank _unknown disc)")
			_check(not used.has(g),
					"%s %s's glyph \"%s\" is its own — %s already uses it"
					% [label, id, g, used.get(g, "?")])
			used[g] = "%s %s" % [label, id]
		print("  %s: %d checked" % [label, ids.size()])

	# the check die's six pip faces are drawn by the same file and read by
	# DiceCheck; a missing one would land the event die on a blank cube
	for n in range(1, 7):
		_check(Glyphs.has("pip%d" % n), "pip%d is a declared glyph" % n)
	_check(_is_drawn("pip1"), "the pip faces have a drawing in glyphs.gd")

	# no duplicates in the key list itself: two entries for one name is how a
	# rename half-lands
	var seen := {}
	for k in Glyphs.KEYS:
		_check(not seen.has(k), "Glyphs.KEYS lists \"%s\" once" % String(k))
		seen[k] = true

	# informational, never fatal: pictures nothing currently claims. Kept
	# because a spare icon is cheap and a missing one is not.
	var spare := []
	for k in Glyphs.KEYS:
		var key := String(k)
		if (key.begins_with("r_") or key.begins_with("p_")) and not used.has(key):
			spare.append(key)
	if not spare.is_empty():
		print("  (unclaimed item icons, fine to keep: %s)" % ", ".join(spare))

	print("icon_coverage_test: %d checks, %d failures" % [tests, fails])
	print("ICONS %s" % ("OK" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails > 0 else 0)
