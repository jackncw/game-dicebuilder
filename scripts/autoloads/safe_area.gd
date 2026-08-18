extends Node
## Where it is actually safe to put a HUD.
##
## The game is laid out on a 720x1280 canvas with `canvas_items` / `expand`
## stretch, which means the whole design rect is ALWAYS visible — the viewport
## grows in whichever direction the window is relatively longer, it never crops.
## So for the first five rounds "the top bar is on screen" was true by
## construction and nothing here existed.
##
## Then the game went on a real phone and the top bar was gone. Two separate
## reasons, and only one of them is Godot's:
##
##  1. `canvasResizePolicy: 2` (the exporter's default) sizes the canvas to
##     `window.innerWidth x window.innerHeight`. On a mobile browser
##     `innerHeight` is the LARGE viewport — the height the page would have if
##     the address bar were retracted — so the canvas is drawn taller than the
##     part of the page you can see, and the overflow is cut off the bottom
##     while the shrinking address bar slides over the top. `visualViewport`
##     is the API that reports what is really on screen, and it fires an event
##     when the address bar moves. `tools/web_shell.html` drives the canvas off
##     that, with `canvasResizePolicy: 0` so the engine keeps its hands off it.
##
##  2. Notches, status bars and home indicators. The shell asks for
##     `viewport-fit=cover`, because a letterboxed canvas with two black bars is
##     worse than a background that runs to the edge of the glass. The price of
##     cover is that the top and bottom strips of the canvas are underneath
##     hardware, and `env(safe-area-inset-*)` is what says how deep. The shell
##     measures those four numbers off a probe element and publishes them; this
##     autoload converts them into canvas units and hands them to the screens.
##
## Everything here is inert off the web (and in the editor): the insets are zero
## and `publish_hud()` does nothing, so the headless tests and the desktop build
## behave exactly as they did before. `force_insets()` is how a test or a
## screenshot tool asks for a phone's geometry on a desktop.

## Insets in CANVAS units (i.e. the coordinates screens lay out in), not CSS px.
var top := 0.0
var right := 0.0
var bottom := 0.0
var left := 0.0

## Emitted whenever any of the four changes, including on the first read.
signal changed

## How often the JS side is re-read. The address bar animating is the fastest
## thing this has to keep up with and it takes ~200ms, so a 10Hz poll costs
## nothing and never shows a stale bar for more than one frame of the animation.
const POLL := 0.1

var _forced := false
var _t := 0.0
var _last := Vector4.ZERO
## Cached so `publish_hud` does not re-measure per call.
var _css_per_canvas := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()


func _process(delta: float) -> void:
	if _forced or not OS.has_feature("web"):
		return
	_t += delta
	if _t < POLL:
		return
	_t = 0.0
	_refresh()


## The rect a screen may safely lay out in, in canvas units.
func usable() -> Rect2:
	var v := _canvas_size()
	return Rect2(left, top, maxf(v.x - left - right, 1.0), maxf(v.y - top - bottom, 1.0))


## Pretend the device has these insets, in CANVAS units. Used by
## `tests/layout_test.gd` and the screenshot tools to reproduce a phone's
## geometry on a machine that has none, and by `?insets=` in the web build so
## the Playwright regression can drive the same case through a real browser.
## Pass a negative top to hand control back to the platform.
func force_insets(t: float, r: float, b: float, l: float) -> void:
	if t < 0.0:
		_forced = false
		_refresh()
		return
	_forced = true
	_store(t, r, b, l)


## The canvas the screens lay themselves out on, in design units.
##
## Normally the root viewport, which under `canvas_items` / `expand` is exactly
## that. The override exists for the screenshot tools: they render a screen into
## a SubViewport sized in DEVICE pixels and scale the holder, so asking the
## viewport would answer 390x664 when the screen is in fact laid out on 752x1280.
var _canvas_override := Vector2.ZERO


## Lay out as if the canvas were this many design units. `Vector2.ZERO` hands
## the question back to the viewport.
func force_canvas(size: Vector2) -> void:
	_canvas_override = size


func canvas_size() -> Vector2:
	return _canvas_size()


func _canvas_size() -> Vector2:
	if _canvas_override != Vector2.ZERO:
		return _canvas_override
	var tree := get_tree()
	if tree == null or tree.root == null:
		return Vector2(720, 1280)
	return tree.root.get_visible_rect().size


func _store(t: float, r: float, b: float, l: float) -> void:
	var v := Vector4(t, r, b, l)
	if v.is_equal_approx(_last):
		return
	_last = v
	top = t
	right = r
	bottom = b
	left = l
	_repin()
	changed.emit()


func _refresh() -> void:
	if _forced:
		return
	if not OS.has_feature("web"):
		_store(0.0, 0.0, 0.0, 0.0)
		return
	# One eval, one string, four numbers: `JavaScriptBridge.eval` only marshals
	# scalars back, so an object or an array would arrive as null.
	var raw := str(JavaScriptBridge.eval("""
		(function () {
			var v = window.__dgViewport;
			if (!v) { return ''; }
			return [v.top, v.right, v.bottom, v.left, v.w, v.h].join(',');
		})()
	""", true))
	var parts := raw.split(",")
	if parts.size() < 6:
		return
	var css_h := float(parts[5])
	var css_w := float(parts[4])
	if css_h <= 0.0 or css_w <= 0.0:
		return
	var canvas := _canvas_size()
	# The canvas is `expand`-stretched, so one CSS pixel is the same number of
	# canvas units in both axes; taking it off the height is arbitrary but the
	# height is the axis this exists for.
	var per_css := canvas.y / css_h
	_css_per_canvas = 1.0 / per_css
	_store(float(parts[0]) * per_css, float(parts[1]) * per_css,
			float(parts[2]) * per_css, float(parts[3]) * per_css)


# ============================================================ pinning
##
## Twelve screens anchor a header to the top edge and nine hang a footer off the
## bottom one, and all of them have to move when the address bar does. Rather
## than teach every screen to listen for that, they hand the control over once
## and this re-applies the offset whenever the insets change. Entries whose
## control has been freed are dropped on the next pass, so a screen that has
## been swapped out costs nothing and nothing has to unregister.

var _pins: Array = []   # [{c: Control, base: float, edge: String}]


## `c.offset_top = Safe.top + base`, kept true. `c` must be anchored to the top.
func pin_top(c: Control, base := 0.0) -> Control:
	return _pin(c, base, "top")


## `c.offset_bottom = -(Safe.bottom + base)`, kept true.
func pin_bottom(c: Control, base := 0.0) -> Control:
	return _pin(c, base, "bottom")


## Both offsets measured from the TOP anchor — the shape a fixed-height strip
## takes (the codex's tab row). Pinning only the top of one of those would move
## its head and leave its feet behind.
func pin_band(c: Control, top_base: float, bottom_base: float) -> Control:
	var p := {"c": c, "base": top_base, "base2": bottom_base, "edge": "band"}
	_pins.append(p)
	_apply_pin(p)
	return c


## Both offsets measured from the BOTTOM anchor — a fixed-height strip hanging
## above the footer (the reward screen's roster band). `c` must have both
## vertical anchors on the bottom edge.
func pin_bottom_band(c: Control, top_base: float, bottom_base: float) -> Control:
	var p := {"c": c, "base": top_base, "base2": bottom_base, "edge": "bband"}
	_pins.append(p)
	_apply_pin(p)
	return c


## A bottom-pinned tray whose SLAB runs to the physical edge (so there is no bare
## background under the home indicator) while its CONTENTS clear the inset. The
## panel keeps whatever bottom content margin its stylebox already had.
func pin_footer(c: PanelContainer, height: float) -> PanelContainer:
	# stamped BEFORE the pin: `_pin` applies immediately and the footer branch
	# reads this meta to know what the stylebox's own margin was
	var box: StyleBoxFlat = c.get_theme_stylebox("panel")
	c.set_meta("safe_pad", box.content_margin_bottom if box != null else 0.0)
	_pin(c, height, "footer")
	return c


func _pin(c: Control, base: float, edge: String) -> Control:
	_pins.append({"c": c, "base": base, "edge": edge})
	_apply_pin(_pins[-1])
	return c


func _apply_pin(p: Dictionary) -> void:
	var c: Control = p.c
	match String(p.edge):
		"top":
			c.offset_top = top + float(p.base)
		"bottom":
			c.offset_bottom = -(bottom + float(p.base))
		"band":
			c.offset_top = top + float(p.base)
			c.offset_bottom = top + float(p.base2)
		"bband":
			c.offset_top = -(bottom + float(p.base))
			c.offset_bottom = -(bottom + float(p.base2))
		"footer":
			c.offset_top = -(float(p.base) + bottom)
			var box: StyleBoxFlat = c.get_theme_stylebox("panel")
			if box != null:
				box.content_margin_bottom = float(c.get_meta("safe_pad", 0.0)) + bottom


func _repin() -> void:
	var live := []
	for p in _pins:
		if not is_instance_valid(p.c):
			continue
		live.append(p)
		_apply_pin(p)
	_pins = live


# ============================================================ test bridge

## Hand a laid-out rect to the page, in CSS pixels, so a browser-side test can
## assert it is really on screen. This is the only way to check the thing that
## actually broke: a Playwright test can see the canvas element, but everything
## the player looks at is drawn inside it and has no DOM at all.
##
## No-op off the web, so the call sites can be unconditional.
func publish_hud(key: String, r: Rect2) -> void:
	if not OS.has_feature("web"):
		return
	var k := _css_per_canvas
	JavaScriptBridge.eval("""
		(function () {
			window.__dgHUD = window.__dgHUD || {};
			window.__dgHUD['%s'] = {x: %f, y: %f, w: %f, h: %f};
		})()
	""" % [key, r.position.x * k, r.position.y * k, r.size.x * k, r.size.y * k], true)


## Same bridge, for a value that is not a rect: a state string, a number, a
## small object. `json_value` is written into `window.__dgHUD[key]` verbatim, so
## the caller supplies valid JSON.
func publish_hud_value(key: String, json_value: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
		(function () {
			window.__dgHUD = window.__dgHUD || {};
			window.__dgHUD['%s'] = %s;
		})()
	""" % [key, json_value], true)


## The part after the colon in `?boot=event:V03` — a deep-boot argument, so a
## browser test can land on one specific event rather than whatever the seed
## deals. Empty in normal play.
var boot_arg := ""


## `?boot=battle` in the web build, `--boot battle` natively: skip the menu and
## open one screen directly. The Playwright regression needs to photograph the
## battle HUD, and clicking a run together through a canvas that has no DOM is
## both slow and the wrong thing to be testing.
func boot_override() -> String:
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in all.size():
		if all[i] == "--boot" and i + 1 < all.size():
			return String(all[i + 1])
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('boot') || ''", true))


## `?insets=t,r,b,l` in CSS pixels — the browser-side half of `force_insets`.
## Applied once at boot; returns true if it took.
func apply_url_insets() -> bool:
	if not OS.has_feature("web"):
		return false
	var raw := str(JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('insets') || ''", true))
	var parts := raw.split(",")
	if parts.size() < 4:
		return false
	var css_h := float(str(JavaScriptBridge.eval(
			"(window.__dgViewport && window.__dgViewport.h) || 0", true)))
	if css_h <= 0.0:
		return false
	var per_css := _canvas_size().y / css_h
	force_insets(float(parts[0]) * per_css, float(parts[1]) * per_css,
			float(parts[2]) * per_css, float(parts[3]) * per_css)
	return true
