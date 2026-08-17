extends Node
## Autoload "Fx": the juice toolbox — hit-stop, particle one-shots, screen
## flash, haptics. Every screen reaches for these instead of rolling its own,
## which is what makes the two settings gates real: "reduce_fx" turns the
## whole drawer off in ONE place, and "fast_anim" scales every duration.
##
## Everything here is presentation. Nothing in this file may read or write
## game rules or state beyond Game.settings.

var _stopping := false
var _flash_layer: CanvasLayer = null


## The two gates, spelled as questions so call sites read as intent.
func reduced() -> bool:
	return bool(Game.settings.get("reduce_fx", false))


func fast() -> bool:
	return bool(Game.settings.get("fast_anim", false))


## Time multiplier for presentation tweens: 1.0 normally, 0.5 under fast_anim.
func dur(seconds: float) -> float:
	return seconds * (0.5 if fast() else 1.0)


# ------------------------------------------------------------ hit-stop

## Freeze the whole scene for `msec` of REAL time. The freeze reads as weight;
## 40-60ms is felt, not seen. Re-entrant calls are swallowed so a cleave that
## lands three heavy hits in one refresh stops once, not three times.
func hit_stop(msec := 50) -> void:
	if reduced() or _stopping:
		return
	if DisplayServer.get_name() == "headless":
		return
	_stopping = true
	Engine.time_scale = 0.05
	# SceneTreeTimer with ignore_time_scale, else the timer itself crawls
	await get_tree().create_timer(msec / 1000.0, true, false, true).timeout
	Engine.time_scale = 1.0
	_stopping = false


# ------------------------------------------------------------ particles

## A radial one-shot burst — impacts, level-ups, chest pops.
func burst(parent: CanvasItem, pos: Vector2, color: Color, n := 14,
		speed := 240.0, life := 0.55, gravity := 340.0) -> void:
	if reduced() or not is_instance_valid(parent):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.amount = n
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, gravity)
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.2
	p.scale_amount_max = 4.6
	p.color = color
	p.color_ramp = _fade_ramp(color)
	parent.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## A soft landing puff: low, slow, grey-green — dice hitting the forest floor.
func dust(parent: CanvasItem, pos: Vector2) -> void:
	burst(parent, pos, Color(0.72, 0.68, 0.55, 0.55), 8, 90.0, 0.45, -60.0)


## Corruption claiming a fallen enemy: the body fades while magenta motes
## stream upward and a rim of light blinks once. Returns the tween that ends
## when the body has gone, so the caller can await it before rebuilding rows.
func dissolve(target: Control, tint := Color(0.95, 0.35, 0.9)) -> Tween:
	var tw := create_tween()
	if not is_instance_valid(target):
		tw.tween_interval(0.01)
		return tw
	if reduced():
		tw.tween_property(target, "modulate:a", 0.0, 0.18)
		return tw
	var center := target.size * 0.5
	# rim flash: the whole card blinks bright once before it lets go
	target.modulate = Color(1.6, 1.3, 1.7)
	tw.tween_property(target, "modulate", Color(1, 1, 1), 0.12)
	tw.tween_property(target, "modulate:a", 0.0, dur(0.5)).set_ease(Tween.EASE_IN)
	var p := CPUParticles2D.new()
	p.position = center
	p.one_shot = true
	p.amount = 26
	p.lifetime = 0.9
	p.explosiveness = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = target.size * 0.35
	p.direction = Vector2.UP
	p.spread = 24.0
	p.gravity = Vector2(0, -260)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 130.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = tint
	p.color_ramp = _fade_ramp(tint)
	target.add_child(p)
	p.emitting = true
	return tw


func _fade_ramp(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(color, color.a))
	g.set_color(1, Color(color, 0.0))
	return g


# ------------------------------------------------------------ screen flash

## One full-screen wash of colour — big casts, boss warnings. Additive-feeling
## because alpha stays low; this must never strobe (photosensitivity), so
## callers keep alpha ≤ 0.25 and duration ≥ 0.15s.
func flash_screen(color: Color, alpha := 0.15, dur_s := 0.4) -> void:
	if reduced():
		return
	if _flash_layer == null:
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 90
		add_child(_flash_layer)
	var rect := ColorRect.new()
	rect.color = Color(color, alpha)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, dur_s)
	tw.tween_callback(rect.queue_free)


# ------------------------------------------------------------ haptics

## A short buzz on phones. Web: Vibration API via JS (iOS Safari lacks it —
## the `&&` makes that a silent no-op). Native mobile: vibrate_handheld.
func vibrate(msec := 20) -> void:
	if reduced() or not bool(Game.settings.get("haptics", true)):
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.vibrate && navigator.vibrate(%d)" % msec, true)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(msec)
