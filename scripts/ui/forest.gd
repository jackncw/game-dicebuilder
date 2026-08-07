class_name Forest
extends RefCounted
## The scenery layer: what turns a chapter's colour palette into a place.
##
## Everything here is flat shapes with the house ink outline — the same drawing
## language as the pawns and the map icons, just applied to the world instead of
## the objects in it. Three static depth layers plus a thin drift of particles
## is enough to read as a forest without any of it competing with the UI:
##
##   far    distant ridge and canopy silhouette, low contrast, high up
##   mid    tree trunks standing on the horizon, chapter surface colour
##   near   grass tufts along the bottom edge and a corner vignette
##
## Nothing in here takes input, and nothing is drawn where body text lives: the
## near layer hugs the bottom edge and the vignette only darkens the corners,
## so `_t_contrast()` keeps measuring what it measured before.

## Per-chapter character. `motes` is what drifts through the air.
const CHAPTER := {
	1: {"motes": "firefly", "trunk_lean": 0.06},
	2: {"motes": "leaf", "trunk_lean": 0.14},
	3: {"motes": "spore", "trunk_lean": 0.02},
}


## Full-screen scenery for `chapter`. `horizon` is the canvas y the mid layer
## stands on (0 to skip it); `canopy` is where the overhead foliage hangs to.
static func scenery(chapter: int, canopy := 118.0, horizon := 0.0,
		with_motes := true) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base := ColorRect.new()
	base.color = UITheme.bg(chapter)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)

	var layers := _Layers.new()
	layers.chapter = chapter
	layers.canopy = canopy
	layers.horizon = horizon
	layers.set_anchors_preset(Control.PRESET_FULL_RECT)
	layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layers)

	if with_motes and _particles_on():
		var m := Motes.new()
		m.chapter = chapter
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(m)
	return root


static func _particles_on() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("/root/Game"):
		return false
	return bool(tree.root.get_node("/root/Game").settings.get("particles", true))


# ============================================================ the three layers

class _Layers:
	extends Control
	var chapter := 1
	var canopy := 118.0
	var horizon := 0.0

	# Deterministic tables rather than rng: the backdrop must not flicker
	# between frames, and two screenshots of the same screen have to match.
	const RIDGE := [0.42, 0.66, 0.30, 0.55, 0.80, 0.38, 0.62, 0.48, 0.74, 0.34,
		0.58, 0.70, 0.44, 0.64, 0.36]
	## Trunks live down the two edges. The middle third of the screen is where
	## every panel, button column and string sits, and a trunk behind those
	## reads as clutter rather than as depth.
	const TRUNK_X := [0.03, 0.10, 0.17, 0.25, 0.75, 0.83, 0.90, 0.97]
	const TRUNK_H := [0.62, 0.34, 0.76, 0.45, 0.56, 0.30, 0.68, 0.40]
	## Fraction of the canopy-to-horizon gap a trunk may fill.
	const TRUNK_SPAN := 0.42
	const TUFT := [0.03, 0.11, 0.17, 0.26, 0.34, 0.41, 0.49, 0.57, 0.63, 0.71,
		0.78, 0.85, 0.92, 0.98]

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var far: Color = UITheme.surface(chapter)
		var mid: Color = UITheme.surface_deep(chapter)
		var lean: float = Forest.CHAPTER.get(chapter, Forest.CHAPTER[1]).trunk_lean

		# --- far: a soft ridge line high up, and the canopy it hangs from
		if canopy > 0.0:
			var band := Rect2(Vector2.ZERO, Vector2(w, canopy))
			draw_rect(band, Color(mid.r, mid.g, mid.b, 0.5))
			var step := w / float(RIDGE.size())
			for i in RIDGE.size():
				var x: float = i * step + step * 0.5
				var lobe: float = RIDGE[i] * 62.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(x - step * 0.75, canopy - 2.0),
					Vector2(x - step * 0.3, canopy + lobe * 0.7),
					Vector2(x, canopy + lobe),
					Vector2(x + step * 0.3, canopy + lobe * 0.7),
					Vector2(x + step * 0.75, canopy - 2.0)]),
					Color(mid.r, mid.g, mid.b, 0.42))

		if horizon > 0.0:
			# ground plane
			draw_rect(Rect2(Vector2(0, horizon), Vector2(w, h - horizon)),
					Color(far.r, far.g, far.b, 0.34))
			draw_rect(Rect2(Vector2(0, horizon), Vector2(w, 4)), mid)

			# --- far treeline standing on the horizon
			var tstep := w / float(RIDGE.size())
			for i2 in RIDGE.size():
				var x2: float = i2 * tstep + tstep * 0.5
				var th: float = 40.0 + RIDGE[i2] * 58.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(x2 - tstep * 0.5, horizon), Vector2(x2, horizon - th),
					Vector2(x2 + tstep * 0.5, horizon)]),
					Color(far.r, far.g, far.b, 0.55))

			# --- mid: trunks, with a lean that gives each chapter its character
			for i3 in TRUNK_X.size():
				var tx: float = TRUNK_X[i3] * w
				var span: float = maxf(horizon - canopy, 0.0) * TRUNK_SPAN
				var top: float = horizon - TRUNK_H[i3] * span
				var bw: float = 8.0 + TRUNK_H[i3] * 8.0
				var skew: float = lean * (horizon - top) * (1.0 if i3 % 2 == 0 else -1.0)
				draw_colored_polygon(PackedVector2Array([
					Vector2(tx - bw, horizon), Vector2(tx - bw * 0.6 + skew, top),
					Vector2(tx + bw * 0.6 + skew, top), Vector2(tx + bw, horizon)]),
					Color(mid.r, mid.g, mid.b, 0.55))

			# --- near: grass tufts along the very bottom
			for i4 in TUFT.size():
				var gx: float = TUFT[i4] * w
				var gh: float = 16.0 + fmod(i4 * 7.0, 13.0)
				for b in 3:
					var off: float = (b - 1) * 6.0
					draw_line(Vector2(gx + off, h), Vector2(gx + off * 2.2, h - gh),
							Color(mid.r, mid.g, mid.b, 0.75), 3.0, true)

		# --- corner vignette: darkens the four corners only, so the middle of
		# the screen (where every panel and every string lives) is untouched
		var vg := 150.0
		for c in [[0.0, 0.0, 1.0, 1.0], [w, 0.0, -1.0, 1.0],
				[0.0, h, 1.0, -1.0], [w, h, -1.0, -1.0]]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(c[0], c[1]),
				Vector2(c[0] + c[2] * vg, c[1]),
				Vector2(c[0], c[1] + c[3] * vg)]), UITheme.SHADE_CORNER)


# ============================================================ ambient motes

## A thin drift of whatever is in the air this chapter. Pooled — the array is
## allocated once and the same entries are recycled forever, and the whole node
## is simply never created when the player turns particles off.
class Motes:
	extends Control
	var chapter := 1
	const COUNT := 18

	var _p := []          # [pos, vel, phase, radius]
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242 + chapter
		for i in COUNT:
			_p.append({
				"pos": Vector2(rng.randf() * 720.0, rng.randf() * 1280.0),
				"vel": Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-14.0, 26.0)),
				"phase": rng.randf() * TAU,
				"r": rng.randf_range(1.6, 3.6),
			})
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		var kind: String = Forest.CHAPTER.get(chapter, Forest.CHAPTER[1]).motes
		for m in _p:
			var v: Vector2 = m.vel
			if kind == "firefly":
				# fireflies wander; they do not fall
				m.pos += Vector2(sin(_t * 0.7 + m.phase) * 14.0, cos(_t * 0.5 + m.phase) * 10.0) * delta
			elif kind == "leaf":
				m.pos += Vector2(v.x + sin(_t * 1.6 + m.phase) * 22.0, absf(v.y) + 12.0) * delta
			else:
				m.pos += Vector2(sin(_t * 0.9 + m.phase) * 8.0, absf(v.y) * 0.35) * delta
			# recycle rather than reallocate
			if m.pos.y > size.y + 12.0:
				m.pos = Vector2(fmod(m.pos.x + 137.0, maxf(size.x, 1.0)), -12.0)
			elif m.pos.y < -20.0:
				m.pos.y = size.y + 10.0
			m.pos.x = fposmod(m.pos.x, maxf(size.x, 1.0))
		queue_redraw()

	func _draw() -> void:
		var kind: String = Forest.CHAPTER.get(chapter, Forest.CHAPTER[1]).motes
		var accent: Color = UITheme.accent(chapter)
		for m in _p:
			match kind:
				"firefly":
					var pulse: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 3.0 + m.phase))
					draw_circle(m.pos, m.r * 2.6, Color(1.0, 0.96, 0.6, 0.10 * pulse))
					draw_circle(m.pos, m.r, Color(1.0, 0.97, 0.66, 0.85 * pulse))
				"leaf":
					var a: float = _t * 1.2 + m.phase
					draw_colored_polygon(PackedVector2Array([
						m.pos + Vector2(cos(a), sin(a)) * m.r * 2.4,
						m.pos + Vector2(cos(a + 2.1), sin(a + 2.1)) * m.r * 1.5,
						m.pos - Vector2(cos(a), sin(a)) * m.r * 2.4,
						m.pos + Vector2(cos(a - 2.1), sin(a - 2.1)) * m.r * 1.5]),
						Color(accent.r, accent.g, accent.b, 0.55))
				_:
					draw_circle(m.pos, m.r * 1.8, Color(accent.r, accent.g, accent.b, 0.16))
					draw_circle(m.pos, m.r * 0.7, Color(accent.r, accent.g, accent.b, 0.5))


# ============================================================ trimmings

## Vine corner ornaments for a panel: four short runners that hug the frame.
##
## They stay ON the border — about 22px along each edge and never more than
## `DEPTH` px inward — so they decorate the frame without ever entering the
## content box. The first version curled inward and promptly landed on top of
## the enemy names, which is exactly the thing the brief said not to do.
class VineCorners:
	extends Control
	var hue := UITheme.GREEN

	const RUN := 22.0     # how far the runner travels along each edge
	const DEPTH := 5.0    # how far it may reach into the panel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if size.x < RUN * 3.0 or size.y < RUN * 3.0:
			return    # too small to decorate without crowding
		var c := Color(hue.r, hue.g, hue.b, 0.8)
		for k in 4:
			var sx := 1.0 if k % 2 == 0 else -1.0
			var sy := 1.0 if k < 2 else -1.0
			var o := Vector2(2.0 if sx > 0 else size.x - 2.0,
					2.0 if sy > 0 else size.y - 2.0)
			for axis in 2:
				var pts := PackedVector2Array()
				for i in 8:
					var t := i / 7.0
					var along := RUN * t
					var into := sin(t * PI) * DEPTH
					pts.append(o + (Vector2(sx * along, sy * into) if axis == 0
							else Vector2(sx * into, sy * along)))
				draw_polyline(pts, c, 2.4, true)
			# a leaf at the end of each runner, pointing away from the content
			for axis2 in 2:
				var tip := o + (Vector2(sx * RUN, 0) if axis2 == 0 else Vector2(0, sy * RUN))
				var out := Vector2(0, -sy * 5.0) if axis2 == 0 else Vector2(-sx * 5.0, 0)
				var along2 := Vector2(sx * 7.0, 0) if axis2 == 0 else Vector2(0, sy * 7.0)
				draw_colored_polygon(PackedVector2Array([
					tip, tip + along2 + out, tip + along2 * 0.4 - out * 0.4]), c)


## Slanted shafts of light — used on the menu, where the scene is allowed to be
## more of a picture than a background.
class LightShafts:
	extends Control
	var tint := Color(1.0, 0.96, 0.78, 0.07)
	var count := 4

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in count:
			var x := size.x * (0.12 + 0.22 * i)
			var w := 60.0 + 26.0 * ((i * 5) % 3)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 0), Vector2(x + w, 0),
				Vector2(x + w + size.y * 0.34, size.y),
				Vector2(x + size.y * 0.34, size.y)]), tint)


## A wooden sign-board, for the menu title and the main buttons: plank fill,
## heavy outline, and two or three strokes of grain.
static func wood_box(bg := UITheme.WOOD, corner := UITheme.R_MD) -> StyleBoxFlat:
	return UIKit.flat_box(bg, corner, UITheme.B_STRONG, UITheme.OUTLINE, UITheme.S2)


class WoodGrain:
	extends Control
	var tint := UITheme.SHADE_SOFT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var h := size.y
		var w := size.x
		for i in 3:
			var y := h * (0.26 + 0.24 * i)
			var pts := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				pts.append(Vector2(w * t, y + sin(t * 6.0 + i * 2.0) * h * 0.045))
			draw_polyline(pts, tint, 2.0, true)
		# two pegs, one at each end
		for px in [w * 0.055, w * 0.945]:
			draw_circle(Vector2(px, h * 0.5), 3.4, UITheme.SHADE_MED)
