extends Node
## Every character the game can put on screen is in the font the game ships.
##   godot --headless --path . res://tests/font_coverage_test.tscn
##
## Why this exists
## ---------------
## The game draws from one bundled face (`gui/theme/custom_font`), built by
## `python tools/font_build.py`, which cuts Noto down to just the glyphs the
## project uses. That subset is a snapshot: the moment somebody writes a face
## name, an event, or a button label containing a character the cut did not
## know about, that character renders as a tofu box — and ONLY in the web build,
## where there is no system font to fall back on. On Windows it looks fine,
## which is exactly how the first web export shipped as boxes end to end.
##
## `font_build.py` already refuses to write a face that misses a glyph it was
## asked for. What it cannot do is notice that the data has moved on since it
## last ran. That is this suite: it re-derives the character set the same way
## the builder does and asks the SHIPPED file whether it has each one, so
## "somebody added text and forgot to rebuild the font" fails here instead of
## on a phone.
##
## Round 6 is the case in point: eleven new faces, whose names brought seven
## Chinese characters the previous subset had never seen.
##
## Deliberately over-inclusive
## ---------------------------
## The scan reads whole files, so characters that only ever appear in a COMMENT
## or in a console table are required too. That is not an oversight: the builder
## scans exactly the same way, and a test that filtered where the builder does
## not would report a gap the builder had already closed (or worse, pass while
## the builder refused). The two have to agree on the set or neither is telling
## the truth. The price is a handful of glyphs — the whole face is 400KB.
##
## Note that this asks Godot for the IMPORTED font. Rebuilding the .ttf without
## re-importing leaves the old cmap in `.godot/imported/`, and this suite will
## correctly report the stale one.

const FONT := "res://assets/fonts/DiceGroveSans-Regular.ttf"

## Mirrors `SKIP_DIRS` in tools/font_build.py — reference art, screenshots and
## the exported build carry no text the game ever draws.
const SCAN_DIRS := ["res://data", "res://scripts", "res://tests", "res://tools"]

## Typed at runtime rather than written down, so a source scan cannot see them:
## the digits and punctuation the UI composes out of numbers. Same list as the
## builder's `EXTRA`; kept in step by hand, and a mismatch shows up as a failure
## here rather than as a box on a phone.
const EXTRA := "×·—–…“”‘’「」『』()《》【】、。,.!?:;%+-/✦♦●○■□▲▼◀▶★☆∞⭮✓✕✗→"

var fails := 0
var tests := 0


func _check(cond: bool, msg: String) -> void:
	tests += 1
	if not cond:
		fails += 1
		print("  FAIL: " + msg)


func _ready() -> void:
	var font: FontFile = load(FONT)
	_check(font != null, "the shipped font loads at all")
	if font == null:
		_finish()
		return

	var want := {}
	for dir in SCAN_DIRS:
		_scan(dir, want)
	for c in EXTRA:
		want[c] = "EXTRA (typed at runtime)"
	for code in range(0x20, 0x7F):
		want[char(code)] = "ASCII"

	# The interesting characters are the ones a system font would have covered
	# for us on a desktop and nothing covers in a browser.
	var cjk := 0
	var missing := []
	for c in want:
		var u: int = c.unicode_at(0)
		if u >= 0x2E80:
			cjk += 1
		if not font.has_char(u):
			missing.append("U+%04X %s (%s)" % [u, c, String(want[c])])
	print("font coverage: %d distinct characters in the project (%d CJK)"
			% [want.size(), cjk])
	# Named individually rather than as a count: the useful half of this failing
	# is knowing WHICH string introduced the character.
	for m in missing:
		print("  MISSING: " + m)
	_check(missing.is_empty(),
			"%d character(s) are used but not in the font — rerun tools/font_build.py"
					% missing.size())

	# The reverse direction is a warning, not a failure: a face carrying glyphs
	# nothing uses is only wasted bytes, and the subset is allowed a little slack
	# (the builder keeps whole ligature/kerning features).
	print("font carries %d glyphs" % font.get_supported_chars().length())
	_finish()


func _finish() -> void:
	print("FONTCOVERAGE: %d tests, %d failures" % [tests, fails])
	if fails == 0:
		print("FONTCOVERAGE OK")
	else:
		print("FONTCOVERAGE FAILED — %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Every printable character in every text file under `path`, mapped to the file
## it came from so a failure can name a culprit.
func _scan(path: String, out: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan(full, out)
		elif name.get_extension() in ["gd", "json", "tscn"]:
			var text := FileAccess.get_file_as_string(full)
			for c in text:
				if c.strip_edges() == "":
					continue
				if not out.has(c):
					out[c] = full
		name = d.get_next()
	d.list_dir_end()
