class_name PressGesture
extends RefCounted
## The one press/hold gesture in the game, in one place.
##
## "Tap to act, hold to read" is a habit the player builds on the die faces and
## then expects everywhere — on a relic in the strip, on a potion in the tray,
## on a shop row. It was written twice: `FaceTile` had the careful version
## (a travel deadzone, and a cancel when the containing ScrollContainer claims
## the finger) and the battle screen had a bare timer that fired a card in the
## middle of a scroll. This is FaceTile's version, lifted out so both use it.
##
## Rules, all three of them:
##   · release before LONG_PRESS and within TAP_SLOP of the press point → tap;
##   · still held at LONG_PRESS → long press, and the release is NOT a tap;
##   · travel past TAP_SLOP, or a NOTIFICATION_SCROLL_BEGIN from a parent
##     ScrollContainer → the press was a scroll; neither signal fires.
##
## Usage — `attach()` for the common case, or drive `feed()` from an existing
## `_gui_input` when the host already has one.

signal tapped()
signal long_pressed()

const LONG_PRESS := 0.45
## A press that travels further than this (canvas px, from the press point) is
## a scroll or a drag, not a tap. Matches the ScrollContainer deadzone the list
## screens use (`UIKit.SCROLL_DEADZONE`).
const TAP_SLOP := 24.0

var _host: Control
var _pressing := false
var _press_at := Vector2.ZERO
var _lp_token: SceneTreeTimer = null
## True from the moment a hold fires until the next press begins — a host that
## also has its own `pressed` signal (Button) asks this before acting.
var fired_long := false


func _init(host: Control) -> void:
	_host = host


## Wire this gesture to `host.gui_input` and keep it alive on the host. Returns
## the gesture so the caller can connect to it.
static func attach(host: Control, on_tap := Callable(),
		on_long := Callable()) -> PressGesture:
	var g := PressGesture.new(host)
	# a RefCounted with no owner would be collected the moment this returns
	host.set_meta("press_gesture", g)
	host.gui_input.connect(func(ev: InputEvent) -> void: g.feed(ev))
	if on_tap.is_valid():
		g.tapped.connect(on_tap)
	if on_long.is_valid():
		g.long_pressed.connect(on_long)
	return g


## Feed one `_gui_input` event. Returns true when the event belonged to the
## gesture (so a host with other bindings can stop there).
func feed(event: InputEvent) -> bool:
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		# position, not relative: relative is unreliable across synthetic and
		# emulated event streams, the distance from the press point is not
		if _pressing and (event.position as Vector2).distance_to(_press_at) > TAP_SLOP:
			cancel()
		return false
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return false
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.pressed:
		_pressing = true
		fired_long = false
		_press_at = event.position
		if _host == null or not _host.is_inside_tree():
			return true
		var t := _host.get_tree().create_timer(LONG_PRESS)
		_lp_token = t
		t.timeout.connect(func() -> void:
			# the host check is not paranoia: a screen torn down mid-press leaves
			# this timer running, and firing into a freed widget is an error in
			# the console of a game that ships with a clean one
			if _lp_token == t and _pressing and is_instance_valid(_host) \
					and _host.is_inside_tree():
				_pressing = false
				fired_long = true
				long_pressed.emit())
	else:
		_lp_token = null
		if _pressing:
			_pressing = false
			tapped.emit()
	return true


## The press is off: a parent has claimed the finger, or the host went away.
func cancel() -> void:
	_pressing = false
	_lp_token = null


## True once per hold: the tap that is about to arrive from a Button's own
## `pressed` signal is the tail of a long press and must not act.
func consume_long() -> bool:
	if not fired_long:
		return false
	fired_long = false
	return true
