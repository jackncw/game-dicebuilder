class_name Die3D
extends Control
## A real die: a chamfered cube in a SubViewport, six procedurally drawn faces,
## one key light and a flat cast shadow underneath.
##
## The first play test's verdict on the old widget was blunt — "冇骰子感,只係
## 色版換面". A die you can see three sides of, that tumbles through its own
## faces and can be picked up and turned over, is the whole point of a
## dice-builder, so this is geometry rather than a picture of geometry.
##
## ── Cost control ─────────────────────────────────────────────────
## Two SubViewports per die, and both sit idle nearly all the time:
##   · the face atlas renders ONCE per set of faces (six tiles in a 3×2 grid)
##     and then stops for good until those faces change;
##   · the 3D view renders once per settled pose, and only switches to
##     per-frame while a throw or a finger-spin is actually moving it.
## Eight resting dice therefore cost eight blits, not eight 3D scenes a frame.
## Measured numbers are in DECISIONS.md.
##
## The widget's own rect never moves. The hop, the squash and the spin all
## happen on the inner TextureRect, because the battle screen hit-tests drop
## zones against `get_global_rect()` and a die that wandered mid-animation
## would take its touch target with it.

signal pressed(hero: int, die: int)
signal long_pressed(hero: int, die: int)
## Emitted the moment a press turns into a drag. `pointer` is the touch index
## that owns the gesture, or -1 for the mouse. The battle screen takes the
## gesture from here: picking a die up rebuilds the hero row, which frees this
## widget, so it cannot deliver the rest of the drag itself.
signal drag_started(hero: int, die: int, at: Vector2, pointer: int)
## The instant the cube first hits the table during a throw.
signal landed()

## Canvas size of the whole widget, matching the old 2.5D die so the hero
## columns did not have to be re-laid-out around it.
const SIZE := Vector2(76, 76)
## The 3D view renders at 2× and is scaled down — a 76px cube with a 3px ink
## chamfer aliases badly at 1×.
const SS := 2
const CELL := 128                      # atlas cell, px
const ATLAS := Vector2i(CELL * 3, CELL * 2)
const DRAG_THRESHOLD := 12.0           # travel before a press becomes a drag
const LONG_PRESS := 0.5
## Free-spin inertia: the rate a flick bleeds off at, and the speed below which
## the die counts as stopped and starts easing back square. A hand flick starts
## it around 15 rad/s, so the whole coast runs a little under five seconds. Kept
## at the value the detail card was tuned to — the menu dice are the same toy.
const SPIN_DECAY := 1.6
const SPIN_STOP := 0.08

## Cube half-size and how much of each edge is chamfered off. The chamfer gives
## the die its rounded silhouette and, filled with the house ink colour, doubles
## as the thick outline every other object in the game wears.
const A := 1.0
const C := 0.17

## Face i of the die is drawn on cube face i. The rolled face is always brought
## to the top, so this order only decides which faces flank it.
const FACE_N := [Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0),
	Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)]
const FACE_U := [Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1),
	Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]

var hero := 0
var die := 0
var faces := []              # six resolved face dicts
var shown := 0               # index into `faces` that is face-up
var dimmed := false          # spent / unusable
var pinned := false          # the player pinned this die against rerolls
var locked_out := false      # the hero spent the other die this turn
var highlighted := false
var interactive := true
var draggable := true
var show_shadow := true

var _vp: SubViewport
var _atlas_vp: SubViewport
var _arts := []              # six _FaceArt, one per atlas cell
var _mesh: MeshInstance3D
var _tex: TextureRect
var _overlay: Control

var _spin := Vector3.ZERO    # angular velocity while free-spinning, rad/s
var _free := false           # detail-card mode: the finger can turn the die
var _turning := false        # a finger is on it right now
var _throwing := false
var _pump := 0               # frames of live rendering still owed
var _hop_base := Vector2.ZERO

var _press_pos := Vector2.ZERO
var _moved := 0.0            # travel during a free spin, to tell a tap from a flick
var _pressing := false
var _pointer := -1
var _lp_token: SceneTreeTimer = null


func _init(p_size := SIZE) -> void:
	custom_minimum_size = p_size
	size = p_size
	pivot_offset = p_size * 0.5
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_build_atlas()
	_build_scene()
	_overlay = _Overlay.new()
	_overlay.owner_die = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	set_process(false)
	_apply()


# ============================================================ public API

## Give the die its six faces and say which one is up.
func set_die(p_faces: Array, p_shown: int, p_dimmed := false, p_pinned := false,
		p_locked := false, p_highlight := false) -> void:
	var changed: bool = p_faces != faces or dimmed != p_dimmed
	faces = p_faces
	shown = clampi(p_shown, 0, 5)
	dimmed = p_dimmed
	pinned = p_pinned
	locked_out = p_locked
	highlighted = p_highlight
	if changed:
		_repaint_atlas()
	_apply()
	settle()


## Park the cube on `shown` and take one still frame.
func settle() -> void:
	if _mesh == null:
		return
	_mesh.basis = rest_basis(shown)
	if _tex != null:
		_tex.position = _hop_base
		_tex.scale = Vector2.ONE
	_orient_atlas()
	_render_once()


## Turn the face that is up so its type runs across the viewer.
##
## A cube cannot have all six faces upright at once — bringing a different face
## to the top rotates the others by a quarter or a half turn, which is why real
## dice have numbers pointing every which way. Only the face on top carries
## information the player has to read, so only that one is corrected; the two
## visible sides are left as the geometry puts them. They are steeply
## foreshortened at this camera angle anyway, so no quarter turn makes them
## "upright" — verified by rendering all four against a 440px die.
func _orient_atlas() -> void:
	if _arts.is_empty():
		return
	var m := rest_basis(shown)
	# where the camera stands, flattened to the ground plane
	var bearing := Vector3(1, 0, 1).normalized()
	for j in 6:
		var n: Vector3 = m * FACE_N[j]
		var art: Control = _arts[j]
		art.pivot_offset = Vector2(CELL, CELL) * 0.5
		if n.y <= 0.5:
			art.rotation = 0.0
			continue
		# which way "down the printed tile" points in the world. Measured, not
		# derived: it runs along the face's u axis (see tools/dice_bench.gd).
		var v: Vector3 = m * FACE_U[j]
		var best := 0.0
		var best_dot := -2.0
		for q in 4:
			var th := q * PI * 0.5
			var d: float = (v * cos(th) + n.cross(v) * sin(th)).dot(bearing)
			if d > best_dot:
				best_dot = d
				best = th
		art.rotation = -best
	_atlas_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func rest_basis(i: int) -> Basis:
	var n: Vector3 = FACE_N[clampi(i, 0, 5)]
	var u: Vector3 = FACE_U[clampi(i, 0, 5)]
	# The columns (u, n, u×n) are the face's own frame; its inverse is what
	# brings that face to the top. Confirmed against all four 90° stations in
	# tools/dice_bench.gd — this is the one where the printed face lands the
	# right way up under the camera below.
	return Basis(u, n, u.cross(n)).transposed()


## Let the player turn the die over with a finger — the long-press card does
## this, and so does the pile of dice on the main menu, which exists purely to
## be flicked. Safe to call before the widget is in the tree.
func enable_free_spin() -> void:
	_free = true
	interactive = true
	draggable = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _mesh != null:
		_render_once()


## The throw. Hops up, tumbles on two axes, bounces twice with the spin dying
## away each time, then settles squarely on `final_face` with a squash.
## `dur` is the whole flight; the caller staggers dice with `delay`.
func throw(final_face: int, delay := 0.0, dur := 0.66) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self) or _mesh == null:
		return
	shown = clampi(final_face, 0, 5)
	_throwing = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# two axes so it reads as a tumble rather than a spinning coin, and a random
	# turn count so eight dice never move as one
	var ax1 := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized()
	var ax2 := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var turns := randf_range(2.0, 3.0)
	var turns2 := randf_range(0.7, 1.3)
	var hop := size.y * 0.42
	var landed_fired := [false]
	var step := func(t: float) -> void:
		if not is_instance_valid(self) or _mesh == null:
			return
		var decay := pow(1.0 - t, 1.7)
		_mesh.basis = rest_basis(shown) \
				* Basis(ax1, turns * TAU * decay) \
				* Basis(ax2, turns2 * TAU * decay)
		var h := _hop_curve(t)
		_tex.position = _hop_base + Vector2(0, -hop * h)
		# squash on each touchdown, stretch at the top of each arc
		var sq := _squash_curve(t)
		_tex.pivot_offset = Vector2(size.x * 0.5, size.y)
		_tex.scale = Vector2(1.0 + sq * 0.16, 1.0 - sq * 0.18)
		if not landed_fired[0] and t >= 0.42:
			landed_fired[0] = true
			landed.emit()
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		_throwing = false
		if is_instance_valid(self):
			settle())


## Height of the die above the table, 0…1, over the whole flight: one big arc,
## then two decaying bounces.
static func _hop_curve(t: float) -> float:
	if t < 0.42:
		return sin(t / 0.42 * PI)
	if t < 0.74:
		return sin((t - 0.42) / 0.32 * PI) * 0.32
	return sin((t - 0.74) / 0.26 * PI) * 0.11


## Squash amount, 0…1 — peaks the instant the die is on the table.
static func _squash_curve(t: float) -> float:
	for at in [[0.42, 0.07, 1.0], [0.74, 0.05, 0.55], [1.0, 0.05, 0.35]]:
		var d: float = absf(t - float(at[0]))
		if d < float(at[1]):
			return (1.0 - d / float(at[1])) * float(at[2])
	return 0.0


# ============================================================ construction

func _build_atlas() -> void:
	_atlas_vp = SubViewport.new()
	_atlas_vp.size = ATLAS
	_atlas_vp.transparent_bg = false
	_atlas_vp.disable_3d = true
	_atlas_vp.gui_disable_input = true
	_atlas_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_atlas_vp)
	for i in 6:
		var art := _FaceArt.new()
		art.position = Vector2((i % 3) * CELL, (i / 3) * CELL)
		art.size = Vector2(CELL, CELL)
		_atlas_vp.add_child(art)
		_arts.append(art)
	_repaint_atlas()


## The atlas is a still life: it only re-renders when the faces themselves
## change (a swap, a forge, a curse blanking one out).
func _repaint_atlas() -> void:
	if _arts.is_empty():
		return
	for i in 6:
		var art: _FaceArt = _arts[i]
		art.fd = faces[i] if i < faces.size() else {}
		art.dimmed = dimmed
		art.refresh()
	_atlas_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_scene() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(size.x) * SS, int(size.y) * SS)
	_vp.transparent_bg = true
	_vp.gui_disable_input = true
	# Each die needs its OWN 3D world. A SubViewport defaults to borrowing the
	# parent viewport's world, which would put all eight cubes, eight cameras
	# and sixteen lights in one space at the origin — the dice come out black
	# and z-fighting, which is exactly how this first came out.
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var world := Node3D.new()
	_vp.add_child(world)

	# no sky, just a flat ambient term so the faces turned away from the key
	# light stay readable — this is a flat-shaded game, not a lighting demo
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e0")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# tight enough that the cube nearly fills its widget: at 76px in a hero
	# column every spare pixel is a bigger number on the face that matters
	cam.size = 2.52
	cam.near = 0.05
	cam.far = 20.0
	# A steep, symmetric isometric station. Steep because the rolled face is the
	# one the player has to read and it lives on top — a shallower angle looks
	# more dramatic and squashes the only face that carries information. Two
	# side faces still show, which is what stops it reading as a flat square.
	# Built as a transform rather than look_at(): the camera is not in the tree
	# yet at this point, and look_at() needs it to be.
	cam.transform = Transform3D(Basis(), Vector3(1.55, 3.0, 1.55)) \
			.looking_at(Vector3(0, -0.02, 0), Vector3.UP)
	world.add_child(cam)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-52, 38, 0)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-18, -130, 0)
	world.add_child(fill)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_cube()
	_mesh.set_surface_override_material(0, _face_material())
	_mesh.set_surface_override_material(1, _edge_material())
	world.add_child(_mesh)
	add_child(_vp)

	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.size = size
	_tex.position = Vector2.ZERO
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hop_base = Vector2.ZERO
	add_child(_tex)
	settle()


func _face_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _atlas_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.roughness = 0.62
	m.metallic_specular = 0.3
	# closed convex solid: back faces are depth-rejected anyway, and not culling
	# takes the winding convention out of the equation entirely
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _edge_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = UITheme.OUTLINE
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Three vertices per cube corner, one per axis — exactly the vertex set a
## uniformly chamfered box needs.
##   surface 0 — the six face quads, mapped into the 3×2 atlas
##   surface 1 — twelve edge quads and eight corner triangles, flat ink
static func _build_cube() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const CORNERS := [[-1, -1], [1, -1], [1, 1], [-1, 1]]
	for i in 6:
		var n: Vector3 = FACE_N[i]
		var u: Vector3 = FACE_U[i]
		var v: Vector3 = u.cross(n)
		var uv0 := Vector2((i % 3) / 3.0, (i / 3) / 2.0)
		var duv := Vector2(1.0 / 3.0, 0.5)
		var p := []
		var uv := []
		for cn in CORNERS:
			p.append(n * A + u * (float(cn[0]) * (A - C)) + v * (float(cn[1]) * (A - C)))
			uv.append(uv0 + Vector2((float(cn[0]) + 1.0) * 0.5,
					(float(cn[1]) + 1.0) * 0.5) * duv)
		_tri(st, p[0], p[1], p[2], uv[0], uv[1], uv[2])
		_tri(st, p[0], p[2], p[3], uv[0], uv[2], uv[3])
	var mesh := st.commit()

	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# edge chamfers: for each cube edge (two fixed axes, one free) join the two
	# neighbouring faces' border vertices
	for a in 3:
		for b in range(a + 1, 3):
			var c := 3 - a - b
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var s0 := _signs(a, sa, b, sb, c, -1.0)
					var s1 := _signs(a, sa, b, sb, c, 1.0)
					var q := [_vtx(a, s0), _vtx(b, s0), _vtx(b, s1), _vtx(a, s1)]
					_tri(st, q[0], q[1], q[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					_tri(st, q[0], q[2], q[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# corner facets
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_tri(st, _vtx(0, s), _vtx(1, s), _vtx(2, s),
						Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	st.commit(mesh)
	return mesh


static func _signs(a: int, sa: float, b: int, sb: float, c: int, sc: float) -> Vector3:
	var v := [0.0, 0.0, 0.0]
	v[a] = sa
	v[b] = sb
	v[c] = sc
	return Vector3(v[0], v[1], v[2])


## The chamfered-box vertex sitting on `axis`'s face at corner `s`: full extent
## along that axis, pulled in by the chamfer on the other two.
static func _vtx(axis: int, s: Vector3) -> Vector3:
	var v := [s.x * (A - C), s.y * (A - C), s.z * (A - C)]
	var sg := [s.x, s.y, s.z]
	v[axis] = sg[axis] * A
	return Vector3(v[0], v[1], v[2])


## Add a triangle with an outward normal, flipping the winding if the authored
## order happened to face inwards (the solid is convex and centred on the
## origin, so the centroid direction *is* outwards).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.dot(a + b + c) < 0.0:
		var tp := b
		b = c
		c = tp
		var tu := ub
		ub = uc
		uc = tu
		nrm = -nrm
	nrm = nrm.normalized()
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(nrm)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## Take a fresh still of the cube.
##
## Not UPDATE_ONCE: the atlas is itself a viewport, and a single-frame update
## can land in the same frame the atlas is still drawing, which samples an
## empty texture and then never corrects itself (the dice come out black). A
## short pump costs three frames and is immune to the ordering.
##
## This deliberately does NOT skip free-spin dice. It used to, and that was the
## grey square at the top of the long-press card: `show_die` turns free spin on
## before the widget is in the tree, so the still `_ready` asks for was refused
## and the viewport had never rendered a single frame by the time the player was
## looking at it. Nothing about "the finger may turn this later" means "do not
## draw it now".
func _render_once(frames := 3) -> void:
	if _vp == null or _throwing:
		return
	_pump = maxi(_pump, frames)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)


## Stop rendering — but only when nothing still wants frames.
func _sleep() -> void:
	if _pump > 0 or _throwing or _turning or _spin.length() > SPIN_STOP:
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)


func _apply() -> void:
	if _overlay != null:
		_overlay.queue_redraw()
	queue_redraw()


# ============================================================ free spin

func _process(delta: float) -> void:
	if _mesh == null:
		return
	if _pump > 0:
		# a still is being taken: hold the viewport live until it has landed
		_pump -= 1
		if _pump == 0:
			_sleep()
		return
	if _throwing or not _free or _turning:
		return
	if _spin.length() > SPIN_STOP:
		_mesh.basis = Basis(_spin.normalized(), _spin.length() * delta) * _mesh.basis
		_spin = _spin.lerp(Vector3.ZERO, clampf(delta * SPIN_DECAY, 0.0, 1.0))
		return
	# inertia spent: drift back upright rather than stopping at a crooked angle
	_spin = Vector3.ZERO
	var target := rest_basis(shown)
	var b := _mesh.basis.orthonormalized().slerp(target, clampf(delta * 3.0, 0.0, 1.0))
	_mesh.basis = b
	if b.get_rotation_quaternion().angle_to(target.get_rotation_quaternion()) < 0.01:
		_mesh.basis = target
		# the pose that ends the spin still has to reach the texture. Going
		# straight to UPDATE_DISABLED here freezes the die one frame short of
		# where it stopped — a couple of pumped frames and only then sleep.
		_pump = 2


# ============================================================ input

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if _free:
		_free_spin_input(event)
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			_begin_press(event)
		else:
			_end_press()
	elif _pressing and draggable \
			and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		var at := _canvas_pos(event)
		if at.distance_to(_press_pos) > DRAG_THRESHOLD:
			# hand the gesture over and stop tracking: the pick-up rebuilds the
			# hero row, so this widget is about to be freed
			_pressing = false
			_lp_token = null
			drag_started.emit(hero, die, at, _pointer)


## Detail-card mode: the finger turns the cube, and letting go leaves it
## spinning on whatever it was given before it eases back upright.
##
## A free-spinning die still reports taps and holds. The reward screen's
## character strip needs all three from one widget: flick it to play with it,
## tap it to switch which of the character's two dice is on show, hold it to
## open their full twelve faces.
func _free_spin_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_turning = event.pressed
		if _turning:
			_spin = Vector3.ZERO
			_moved = 0.0
			set_process(true)
			_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var t := get_tree().create_timer(LONG_PRESS)
			_lp_token = t
			t.timeout.connect(func() -> void:
				if _lp_token == t and _turning:
					_lp_token = null
					_moved = 1e9      # a hold is not a tap
					long_pressed.emit(hero, die))
		else:
			_lp_token = null
			# a "spin" that never went anywhere was a tap
			if _moved < DRAG_THRESHOLD:
				pressed.emit(hero, die)
	elif _turning and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		var rel: Vector2 = event.relative if event is InputEventMouseMotion else event.relative
		_moved += absf(rel.x) + absf(rel.y)
		# drag right spins about the screen's up axis, drag down about its right
		var k := 0.012
		_mesh.basis = Basis(Vector3.UP, rel.x * k) \
				* Basis(Vector3(1, 0, -1).normalized(), rel.y * k) * _mesh.basis
		_spin = Vector3(rel.y, rel.x, 0.0) * 0.9


func _begin_press(event: InputEvent) -> void:
	_pressing = true
	_press_pos = _canvas_pos(event)
	_pointer = int(event.index) if event is InputEventScreenTouch else -1
	var t := get_tree().create_timer(LONG_PRESS)
	_lp_token = t
	t.timeout.connect(func() -> void:
		if _lp_token == t and _pressing:
			long_pressed.emit(hero, die))


func _end_press() -> void:
	_lp_token = null
	if _pressing:
		_pressing = false
		pressed.emit(hero, die)


## Canvas-space point of a GUI event — the space `get_global_rect()` and every
## drop zone live in. Inside `_gui_input` the event's `position` has been made
## local to this control, so our global transform maps it straight back; that
## undoes the viewport's stretch as well.
##
## Never read `event.global_position` here: it stays in raw window pixels and so
## only agrees with canvas space on an unscaled 720x1280 window. Touch events do
## not carry it at all.
func _canvas_pos(event: InputEvent) -> Vector2:
	return get_global_transform() * event.position


## Aborts an in-flight press so a rebuild of the row cannot leave a stuck drag.
func cancel_press() -> void:
	_pressing = false
	_lp_token = null


# ============================================================ 2D trimmings

## Under the cube: the cast shadow, and the selection ring when it is chosen.
func _draw() -> void:
	if show_shadow:
		var w := size.x * 0.62
		draw_set_transform(Vector2(size.x * 0.5, size.y * 0.93), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, w * 0.5, Color(0, 0, 0, 0.26 if not dimmed else 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if highlighted:
		var ring := UIKit.flat_box(Color(0, 0, 0, 0), int(size.x * 0.22),
				UITheme.B_FOCUS, UITheme.YELLOW)
		ring.set_content_margin_all(0)
		draw_style_box(ring, Rect2(Vector2(-3, -3), size + Vector2(6, 6)))


## Above the cube: the "off" veil and the pin / lock badges.
class _Overlay:
	extends Control
	var owner_die: Die3D = null

	func _draw() -> void:
		if owner_die == null:
			return
		var s := size
		if owner_die.dimmed or owner_die.locked_out:
			var veil := UIKit.flat_box(Color(0.28, 0.29, 0.33, 0.34), int(s.x * 0.2), 0)
			veil.set_content_margin_all(0)
			draw_style_box(veil, Rect2(Vector2.ZERO, s))
		var r := s.x * 0.17
		if owner_die.locked_out:
			_badge(Vector2(s.x - r - 2, r + 2), r, UITheme.BLUE)
			_padlock(Vector2(s.x - r - 2, r + 2), r * 0.9)
		elif owner_die.pinned:
			_badge(Vector2(s.x - r - 2, r + 2), r, UITheme.YELLOW)
			_pin(Vector2(s.x - r - 2, r + 2), r * 0.9)

	func _badge(c: Vector2, r: float, hue: Color) -> void:
		draw_circle(c, r, UITheme.deepen(hue))
		draw_arc(c, r, 0.0, TAU, 20, UITheme.OUTLINE, 2.0, true)

	func _padlock(c: Vector2, r: float) -> void:
		draw_arc(c + Vector2(0, -r * 0.25), r * 0.42, PI, TAU, 14, UITheme.CREAM, 2.4, true)
		draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.85)),
				UITheme.CREAM)

	func _pin(c: Vector2, r: float) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, -r * 0.5),
			c + Vector2(0, r * 0.35)]), UITheme.CREAM)
		draw_line(c + Vector2(0, r * 0.2), c + Vector2(0, r * 0.85), UITheme.CREAM, 2.2)


# ============================================================ one die face

## What is printed on a single cube face: category fill, the main effect's
## glyph, the value, and up to three keyword badges. Deliberately edge-to-edge —
## the cube's chamfer supplies the rounded border.
class _FaceArt:
	extends Control
	var fd := {}
	var dimmed := false
	var _num: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_num = UIKit.label("", 80, UITheme.CREAM)
		_num.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
		_num.add_theme_constant_override("outline_size", 11)
		_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_num.position = Vector2.ZERO
		_num.size = Vector2(Die3D.CELL, Die3D.CELL)
		_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_num)
		refresh()

	func refresh() -> void:
		if _num == null:
			return
		# A pip face carries its value as dots, so there is no number to print
		# over them (see Glyphs._pips and DiceCheck).
		var txt := ""
		if not fd.is_empty() and not fd.has("pip"):
			txt = Glossary.main_number(fd)
		_num.text = txt
		_num.add_theme_font_size_override("font_size", 80 if txt.length() <= 2 else 50)
		_num.add_theme_color_override("font_color",
				UITheme.CREAM if not dimmed else UITheme.CREAM.darkened(0.3))
		queue_redraw()

	func _draw() -> void:
		var s := size
		var hue: Color = UITheme.cat_color(String(fd.get("cat", "special")))
		if fd.is_empty() or (fd.get("blank", false) and not fd.has("pip")):
			hue = Color("8a8a8a")
		var fill := UITheme.deepen(hue)
		var rim := hue.lightened(0.22)
		if dimmed:
			fill = fill.lerp(Color("5e5e5e"), 0.45)
			rim = rim.lerp(Color("8a8a8a"), 0.5)
		draw_rect(Rect2(Vector2.ZERO, s), fill)
		# a band of the true category hue: the fill has to be deep enough to
		# carry cream type, which costs it most of its colour identity
		draw_rect(Rect2(Vector2(0, 0), Vector2(s.x, s.y * 0.13)), rim)
		draw_rect(Rect2(Vector2(0, s.y * 0.13), Vector2(s.x, 3)), UITheme.OUTLINE)

		var has_num: bool = _num != null and _num.text != ""
		var g: float = s.x * (0.68 if has_num else 0.8)
		var tint := UITheme.CREAM.lerp(rim, 0.55 if has_num else 0.0)
		if dimmed:
			tint = tint.darkened(0.3)
		var gkey := Glossary.glyph_key(String(Glossary.main_effect(fd).key))
		if fd.has("pip"):
			gkey = "pip%d" % clampi(int(fd.pip), 1, 6)
			tint = UITheme.CREAM
		Glyphs.draw_glyph(self, gkey,
				Rect2(Vector2((s.x - g) * 0.5, (s.y - g) * 0.5 + s.y * 0.05), Vector2(g, g)),
				tint, UITheme.OUTLINE)

		var subs := Glossary.sub_terms(fd)
		var n := mini(subs.size(), 3)
		var bs := s.x * 0.26
		for i in n:
			var key := String(subs[n - 1 - i])
			var cx := s.x - 5.0 - bs * 0.5 - i * (bs + 3.0)
			var cy := s.y - 5.0 - bs * 0.5
			var bh := Glossary.hue(key)
			draw_circle(Vector2(cx, cy), bs * 0.5, UITheme.deepen(bh))
			draw_arc(Vector2(cx, cy), bs * 0.5, 0.0, TAU, 20, UITheme.OUTLINE, 2.5, true)
			Glyphs.draw_glyph(self, Glossary.glyph_key(key),
					Rect2(Vector2(cx, cy) - Vector2(bs, bs) * 0.33, Vector2(bs, bs) * 0.66),
					bh.lightened(0.45), Color(0, 0, 0, 0))

		var plus := int(fd.get("plus", 0))
		for p in plus:
			var px := 8.0 + p * 13.0
			draw_line(Vector2(px, s.y - 14), Vector2(px + 9, s.y - 14), UITheme.YELLOW, 3.5)
			draw_line(Vector2(px + 4.5, s.y - 18.5), Vector2(px + 4.5, s.y - 9.5),
					UITheme.YELLOW, 3.5)
