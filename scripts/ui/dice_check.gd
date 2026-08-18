class_name DiceCheck
extends Control
## An event's dice check, thrown by the player.
##
## An event that says "roll 4+" used to resolve the instant the option was
## tapped: the outcome line simply announced a number nobody saw happen. In a
## dice-builder that is the one moment that should never be narrated — so the
## die comes out, the player throws it, and the cube lands on the result.
##
## ── The honesty rule ────────────────────────────────────────────
## The number is rolled by the ENGINE, from the run's RNG, BEFORE this widget
## is built, and handed in as `roll`. The animation is only ever a way of
## showing that number: `Die3D.throw()` is told which face to finish on, and
## the face it settles on is asserted against `roll` by
## tests/dice_check_test.gd and by web/tests/round14dice.spec.js. There is no
## path here that draws a number after the tumble, and none that shows one
## number and returns another.
##
## Headless and reduced-motion skip the tumble and land on the same face — the
## simulator never opens this at all (`SimRunner._do_event` resolves the check
## itself), so no sim number moves because of this screen.

signal finished(success: bool)

const PANEL_W := 604.0
const DIE_PX := 184.0
## The throw, in seconds. Inside the 0.5–0.8s the round asked for: long enough
## to read as a tumble, short enough not to tax a player who rolls often.
const THROW_DUR := 0.66


var roll := 1                # the engine's result, 1…6
var need := 4                # success is `roll >= need`
var title_text := ""
var win_text := ""
var lose_text := ""

var die: Die3D
var confirm_button: Button = null
var _panel: PanelContainer
var _body: VBoxContainer
var _prompt: Label
var _thrown := false
var _done := false


## Six pip faces — a plain d6, in the same cube, the same atlas and the same
## flat-fill-and-ink language as every die in the game.
static func d6_faces() -> Array:
	var out := []
	for n in range(1, 7):
		out.append({"pip": n, "cat": "control"})
	return out


## `opts`: roll (int 1…6, already rolled by the engine), need (int),
## title (String), win (String), lose (String), on_done (Callable(success)).
static func open(parent: Control, opts: Dictionary) -> DiceCheck:
	var dc := DiceCheck.new()
	dc.roll = clampi(int(opts.get("roll", 1)), 1, 6)
	dc.need = int(opts.get("need", 4))
	dc.title_text = String(opts.get("title", ""))
	dc.win_text = String(opts.get("win", ""))
	dc.lose_text = String(opts.get("lose", ""))
	var cb: Callable = opts.get("on_done", Callable())
	if cb.is_valid():
		dc.finished.connect(func(ok: bool) -> void: cb.call(ok))
	dc.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dc)
	return dc


func succeeded() -> bool:
	return roll >= need


func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.66)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var panel := UIKit.panel(UIKit.CREAM, UIKit.R_LG, UIKit.B_STRONG)
	_panel = panel
	var psb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	psb.set_content_margin_all(UIKit.S5)
	psb.border_color = UITheme.YELLOW
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UIKit.S4)
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_body)

	if title_text != "":
		_body.add_child(UIKit.text_block(title_text, UIKit.F_BODY_SM, UITheme.INK_SOFT,
				PANEL_W - 16.0))
	# the condition, stated before the throw — a check the player reads only
	# afterwards is a coin flip with extra steps
	var cond := CenterContainer.new()
	cond.add_child(UIKit.chip(Data.bi("擲出 ≥%d 成功" % need, "Roll %d+ to succeed" % need),
			UITheme.YELLOW, UIKit.F_BODY, UIKit.S3))
	_body.add_child(cond)

	die = Die3D.new(Vector2(DIE_PX, DIE_PX))
	die.draggable = false
	die.show_shadow = true
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, DIE_PX + UIKit.S3)
	holder.add_child(die)
	_body.add_child(holder)
	die.pressed.connect(_on_die_pressed)
	# the faces go on after the widget is in the tree: the atlas viewport is
	# built in Die3D._ready
	die.set_die(d6_faces(), 0)

	_prompt = UIKit.text_block(Data.bi("點一下骰子擲出", "Tap the die to roll"),
			UIKit.F_BODY, UITheme.INK, PANEL_W - 16.0)
	_body.add_child(_prompt)
	# The rects are only real once the containers have laid out, and the browser
	# test taps them. Three signals, because one is not enough: the button's own
	# rect stops changing while the panel is still growing under the verdict,
	# and `item_rect_changed` does not fire for an ANCESTOR moving.
	_body.sort_children.connect(_publish_rects)
	_panel.item_rect_changed.connect(_publish_rects)
	die.item_rect_changed.connect(_publish_rects)
	_publish("ready")


func _on_die_pressed(_hero: int, _die: int) -> void:
	throw_it()


## The throw. Public so a test can drive it without synthesising a tap.
func throw_it() -> void:
	if _thrown:
		return
	_thrown = true
	_prompt.text = ""
	Sfx.play("roll")
	if DisplayServer.get_name() == "headless" or Fx.reduced():
		die.set_die(d6_faces(), roll - 1)
		_land()
		return
	die.throw(roll - 1, 0.0, THROW_DUR)
	await get_tree().create_timer(THROW_DUR + 0.05).timeout
	if is_instance_valid(self):
		_land()


## The cube has stopped. Whatever it is showing is what the engine rolled —
## this only reads it back and says what it means.
func _land() -> void:
	var ok := succeeded()
	var shown_pip := _shown_pip()
	_prompt.text = Data.bi("擲出 %d" % shown_pip, "Rolled %d" % shown_pip)
	_prompt.add_theme_font_size_override("font_size", UIKit.F_H2)

	var verdict := CenterContainer.new()
	verdict.add_child(UIKit.chip(
			Data.bi("成功", "Success") if ok else Data.bi("失敗", "Failure"),
			UITheme.GREEN if ok else UITheme.RED, UIKit.F_H2, UIKit.S3))
	_body.add_child(verdict)

	var line := win_text if ok else lose_text
	if line != "":
		_body.add_child(UIKit.text_block(line, UIKit.F_BODY, UITheme.INK, PANEL_W - 16.0))

	# the result stays on screen until the player says they have read it. The
	# page is told the old (absent) confirm rect is gone first, so a browser
	# test cannot tap a rect from a previous card.
	Safe.publish_hud_value("dice_check_confirm", "null")
	var b := UIKit.button(Data.t("ui_confirm"), UIKit.CREAM, UIKit.F_H2, Vector2(260, 74))
	b.pressed.connect(_confirm)
	confirm_button = b
	_body.add_child(UIKit.button_row([b]))
	Sfx.play("win" if ok else "block", 1.0 if ok else 0.6)
	_publish("landed")
	_publish_rects()


func _confirm() -> void:
	if _done:
		return
	_done = true
	Sfx.play("button")
	var ok := succeeded()
	_publish("closed")
	finished.emit(ok)
	queue_free()


## The pip value the cube is actually showing, read off the widget rather than
## off `roll` — this is what the tests compare against the engine's number.
func _shown_pip() -> int:
	if die == null or die.shown >= die.faces.size():
		return 0
	return int((die.faces[die.shown] as Dictionary).get("pip", 0))


## Re-hand the two tappable rects to the page. Cheap: `publish_hud` is a
## no-op off the web, and these fire only on a layout pass.
func _publish_rects() -> void:
	# only once a widget has a real size: a zero rect published early would
	# be indistinguishable, to the page, from a settled one
	if die != null and is_instance_valid(die) and die.size.y > 1.0:
		Safe.publish_hud("dice_check_die", die.get_global_rect())
	if confirm_button != null and is_instance_valid(confirm_button) \
			and confirm_button.size.y > 1.0:
		Safe.publish_hud("dice_check_confirm", confirm_button.get_global_rect())


func _publish(state: String) -> void:
	Safe.publish_hud_value("dice_check", JSON.stringify(
			{"state": state, "need": need, "roll": roll, "shown": _shown_pip()}))
	_publish_rects()
