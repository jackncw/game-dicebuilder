extends Control
## Battle screen: renders BattleCore state and routes input into engine calls.
## Declarative refresh: every action rebuilds the dynamic rows from bc.s.
##
## Primary interaction is drag-and-drop — pick a die up and drop it on the
## thing it should affect. Tapping a die still selects it and tapping a
## highlighted target resolves it, which keeps one-handed play and the
## headless input tests working.

var bc: BattleCore
var rng: RandomNumberGenerator
var args := {}

# selection / drag state
var sel := {}                # {hero, die} chosen by tapping
var drag := {}               # {hero, die} currently held
var pending_stuns := []      # collected enemy-die picks for multi-stun faces
var pending_wild_src := {}   # wild: {hero, die} chosen source
var pending_theft := {}      # die theft: picked die awaiting target
var pending_potion := -1     # potion slot awaiting an ally target

# tooltip long-press
var _lp_timer: SceneTreeTimer = null
var _tooltip: Control = null

# ui refs
var top_turn: Label
var essence_bar: Control
var top_reroll: Label
var relic_scroll: ScrollContainer
var relic_row: VBoxContainer
var enemy_row: HBoxContainer
var hero_row: HBoxContainer
var cast_zone: Control
var tray_panel: PanelContainer
var arena_bg: Control
var cast_panel: PanelContainer
var cast_label: Label
var cast_btn: Button
var btn_undo: Button
var btn_reroll: Button
var btn_buy_reroll: Button
var btn_end: Button
var overlay: Control = null
var float_layer: Control
var drag_layer: Control
var drag_ghost: Die3D = null

var enemy_cards := []
var hero_cards := []          # column panel per hero
var hero_arts := []           # PawnArt refs for attack lunges
var die_widgets := {}         # "h:d" → Die3D
var enemy_widgets := {}       # absolute enemy index → {card, art, chips}
var potion_row: HBoxContainer
var _float_pool: Array = []   # pooled floating-number labels
var _roll_pending := false    # a fresh roll is waiting to be tumbled

const HERO_COL_W := 172.0
const HERO_COL_PAD := 5      # tighter than the default panel margin: 4 columns must fit 720px

## How far a die has to travel from where it was picked up before letting go
## will actually spend it, in canvas pixels.
##
## This is the fix for the worst bug in the first play test: a self-targeting
## die sits *inside* its own hero card, so the tiniest wobble used to be a
## complete pick-up-and-drop onto a legal target, and the face was gone before
## the player knew they had touched it. 56px is wider than a die (and wider than
## a thumb's idle jitter), so leaving the die's own home is now a deliberate
## act. Under it, releasing cancels — even if the finger happens to be sitting
## on something droppable.
const DRAG_ARM := 56.0
## How much a hovered drop target swells to say "it lands here".
const HOVER_SCALE := 1.035

## Vertical bands of the battle canvas. Everything anchors to one of these, so
## there is no unclaimed slack: enemies own the top, the party owns the bottom
## half, and the action tray is pinned to the very bottom edge.
##
## The bands are also a contract. The cast pad is its own full-width strip
## between the enemy band and the party, and NOTHING from the enemy band is
## allowed to reach into it — the boss cards used to, because an enemy card is
## sized by its content and a boss card's content was simply taller than the
## band it was anchored in. `_enemy_art_budget()` is what enforces it now, and
## `tests/layout_test.gd` asserts the two rects never intersect for any of the
## six bosses or a four-enemy line-up.
##
## These were constants until round 6, when the game went on a real phone and
## the top bar turned out to be underneath the address bar. Two things changed:
## the canvas is now sized to the VISUAL viewport (`tools/web_shell.html`), and
## the bands are solved against `Safe`'s insets instead of against a hardcoded
## 1280. On a 720x1280 canvas with no insets `_solve_zones()` reproduces the old
## numbers exactly, so nothing about the desktop build moved.
var ZONE_TOPBAR := 10.0
var ZONE_RELICS := 46.0
var ZONE_ENEMY_TOP := 96.0
var ZONE_ENEMY_BOTTOM := 570.0
var ZONE_HORIZON := 576.0
var ZONE_CAST_TOP := 584.0
var ZONE_CAST_BOTTOM := 646.0
var ZONE_HERO_TOP := 654.0
var ZONE_HERO_BOTTOM := 1014.0
const TRAY_H := 244.0

## The fixed parts of the stack, measured off the shipping 720x1280 layout.
const HEAD_H := 96.0        # top bar + relic strip, above the enemy row
const HERO_BAND_H := 360.0  # the four hero columns
const TRAY_GAP := 22.0      # between the hero columns and the action tray
## 78, up from the 62 it was through round 5. The strip stopped being a label
## and became the game's running commentary — a whole bilingual effect sentence,
## which in the worst case (an attack that also poisons, pierces and costs
## Essence) is one Chinese line and two wrapped English ones. It is paid for out
## of the enemy band, so a boss is drawn 177px tall instead of 193; that is a
## real cost and it buys the player being able to read their own hand without
## long-pressing eight dice.
##
## CAST_MIN_H is unchanged on purpose: the inset budget in `_solve_zones` is
## solved against the FLOOR, so growing the resting height costs nothing on a
## phone with a deep notch — it just means the strip has further to give.
const CAST_H := 78.0        # the ✦ 施放 strip at rest
const CAST_MIN_H := 44.0    # …and as far as it may be squeezed
const GAP_HORIZON := 6.0
const GAP_CAST := 8.0
const GAP_HERO := 8.0

## How short the enemy band may get before the squeeze moves on to the cast
## strip. `ENEMY_CHROME_H` of it is name, HP, statuses and intents — none of
## which shrink — so this leaves the creature 96px, which is where a minion
## stops reading as a distinct animal at 540 wide.
const ENEMY_ART_MIN := 96.0

## …and the point past which there is no layout at all. The chrome does not
## shrink, so a card is never shorter than `ENEMY_CHROME_H` plus this, and a band
## shorter than that means enemy cards reaching into the cast pad — the exact
## overlap `tests/layout_test.gd` was written to prevent. This is a hard floor,
## not a comfort one: `ENEMY_ART_MIN` decides when the CAST STRIP starts giving,
## this decides when the INSETS stop being honoured.
const ENEMY_ART_HARD_MIN := 48.0

## The insets actually applied, which is `Safe`'s pair except on a device that
## demands more than the layout can pay (see `_solve_zones`).
var eff_top := 0.0
var eff_bottom := 0.0
## Numbers land on the pawn, not on the name plate at the top of the column.
const HERO_FLOAT_DROP := 96.0

## Everything on an enemy card that is not the creature: boss tag, name, HP row,
## status badges, intent chips, damage preview, the art holder's own headroom,
## padding and separations. The art gets whatever is left of the enemy band —
## see `_enemy_art_budget()`.
##
## Measured, not guessed: `tests/layout_test.gd` builds the tallest case there
## is (a boss carrying five statuses AND a damage-preview chip) and fails if a
## card reaches past the band, so this number cannot drift out of date quietly.
##
## 281, up from 274 on 2026-08-08, and the 7px is the font: the game used to
## render from whatever the OS supplied and now ships its own face (see
## `gui/theme/custom_font`), whose line height is not the same. This is the
## check working — the constant is downstream of text metrics, the metrics
## moved, and B6's card reached 577 against the band's 570 until it was
## re-measured. Not a tolerance to widen.
const ENEMY_CHROME_H := 281.0


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	rng = RandomNumberGenerator.new()
	# a run battle carries its own committed seed so a resume replays exactly
	if args.has("battle_seed"):
		rng.seed = int(args.battle_seed)
	elif args.has("rng_seed"):
		rng.seed = int(args.rng_seed)
		if args.has("rng_state"):
			rng.state = int(args.rng_state)
	else:
		rng.randomize()
	bc = BattleCore.new()
	bc.setup(args.team, args.enemies, args.get("opts", {}), rng)
	_record_encounter()
	_solve_zones()
	_build_static()
	# A phone's address bar slides in and out mid-play, and rotating the device
	# changes the canvas outright. Both arrive as one of these two.
	Safe.changed.connect(_on_viewport_changed)
	get_viewport().size_changed.connect(_on_viewport_changed)
	_refresh()
	_animate_roll()
	if args.get("tutorial", false):
		_show_tutorial(0)


## Codex: everything the party meets is recorded the moment it appears, so a
## defeat still leaves the entry unlocked.
func _record_encounter() -> void:
	for e in bc.s.enemies:
		if e.kind == "boss":
			Game.mark_boss_met(String(e.key))
		else:
			Game.mark_enemy_met(String(e.key), int(e.tier))
		if String(e.get("affix", "")) != "":
			Game.mark_affix_met(String(e.affix))


func _build_static() -> void:
	var chapter := int(args.get("opts", {}).get("chapter", 1))
	arena_bg = _build_arena_bg(chapter)
	add_child(arena_bg)

	var top := HBoxContainer.new()
	top.anchor_left = 0.0
	top.anchor_right = 1.0
	top.offset_top = ZONE_TOPBAR
	top.offset_left = UIKit.S4
	top.offset_right = -UIKit.S4
	top.add_theme_constant_override("separation", UIKit.S3)
	add_child(top)
	top_turn = UIKit.outlined(UIKit.label("", UIKit.F_H2, UIKit.CREAM))
	top_turn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(top_turn)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stretch)
	# 靈息 reads as a resource you fill and spend, so it is a meter rather than
	# a number. Hidden outright for a party that has no Essence faces at all —
	# a permanently empty bar is a rule the player cannot act on.
	essence_bar = _EssenceBar.new()
	essence_bar.visible = _party_uses_essence()
	top.add_child(essence_bar)
	_attach_longpress(essence_bar, func() -> void: _show_term("mana", ["spell"]))
	top_reroll = UIKit.outlined(UIKit.label("", UIKit.F_H2, UITheme.CAT_ON_DARK.control))
	top_reroll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(top_reroll)

	# what the party is carrying, as a strip of icons under the top bar
	relic_scroll = ScrollContainer.new()
	relic_scroll.anchor_left = 0.0
	relic_scroll.anchor_right = 1.0
	relic_scroll.offset_left = UIKit.S4
	relic_scroll.offset_right = -UIKit.S4
	relic_scroll.offset_top = ZONE_RELICS
	relic_scroll.offset_bottom = ZONE_ENEMY_TOP - 6.0
	relic_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	relic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(relic_scroll)
	# Two explicit rows, not an HFlowContainer: a flow container inside a
	# horizontally-scrolling ScrollContainer is handed its *minimum* width, which
	# is one pip wide, so it wraps into a column down the left edge.
	relic_row = VBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 2)
	relic_scroll.add_child(relic_row)
	_build_relic_row()

	enemy_row = HBoxContainer.new()
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.add_theme_constant_override("separation", UIKit.S3)
	enemy_row.anchor_left = 0.0
	enemy_row.anchor_right = 1.0
	enemy_row.offset_top = ZONE_ENEMY_TOP
	enemy_row.offset_bottom = ZONE_ENEMY_BOTTOM
	add_child(enemy_row)

	# The cast pad is its own full-width strip between the enemy band and the
	# party. It used to be a 360px island parked in the middle of the arena,
	# which is how the tallest boss card came to sit on top of it.
	cast_zone = Control.new()
	cast_zone.anchor_left = 0.0
	cast_zone.anchor_right = 1.0
	cast_zone.offset_left = UIKit.S4
	cast_zone.offset_right = -UIKit.S4
	cast_zone.offset_top = ZONE_CAST_TOP
	cast_zone.offset_bottom = ZONE_CAST_BOTTOM
	cast_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_panel = UIKit.panel(UITheme.surface_deep(chapter), UIKit.R_LG, UIKit.B_STRONG)
	# tighter than the house 10px: every pixel of padding is a pixel the
	# sentence cannot use, and the strip is already borrowing from the arena
	cast_panel.get_theme_stylebox("panel").set_content_margin_all(CAST_PAD)
	cast_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# One label doing two jobs: the drop-zone prompt when nothing is picked up,
	# and the full effect sentence for whatever die is. Autowrap and a small
	# size floor are what let a two-line bilingual sentence live in a 62px strip.
	cast_label = UIKit.label("✦ " + Data.t("ui_cast_zone"), UIKit.F_H2, UIKit.CREAM)
	cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# NOT `clip_text`. A Label with `clip_text` reports a minimum height of one
	# pixel, and a PanelContainer hands its child exactly its minimum — which is
	# how the first cut of this shipped an empty strip with the right text in it.
	# The fit is done properly instead, in `_cast_font_for()`.
	cast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cast_panel.add_child(cast_label)
	cast_zone.add_child(cast_panel)
	# tap path: with a no-target face selected the pad becomes a button, so the
	# gesture-free way to play a face is still select-then-tap-the-target
	cast_btn = Button.new()
	cast_btn.flat = true
	cast_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_btn.visible = false
	cast_btn.pressed.connect(_on_cast_tapped)
	cast_zone.add_child(cast_btn)
	# The pad is always on screen — it is where the middle band of the arena
	# goes, and a permanently visible landing spot teaches the gesture. It just
	# sits back until a no-target die is actually in the air.
	cast_zone.visible = true
	add_child(cast_zone)

	hero_row = HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", UIKit.S1)
	hero_row.anchor_left = 0.0
	hero_row.anchor_right = 1.0
	hero_row.offset_top = ZONE_HERO_TOP
	hero_row.offset_bottom = ZONE_HERO_BOTTOM
	add_child(hero_row)

	# --- action tray, pinned to the bottom edge so the screen has no tail of
	# --- empty background under the controls
	var tray := PanelContainer.new()
	tray_panel = tray
	var tray_box := UIKit.flat_box(UITheme.surface_deep(chapter), 0, 0, UIKit.OUTLINE, UIKit.S3)
	tray_box.set_border_width_all(0)
	tray_box.border_width_top = UIKit.B_STRONG
	tray_box.corner_radius_top_left = UIKit.R_LG
	tray_box.corner_radius_top_right = UIKit.R_LG
	tray_box.content_margin_top = UIKit.S4
	tray_box.content_margin_bottom = UIKit.S4
	tray.add_theme_stylebox_override("panel", tray_box)
	tray.anchor_left = 0.0
	tray.anchor_right = 1.0
	tray.anchor_top = 1.0
	tray.anchor_bottom = 1.0
	tray.offset_top = -TRAY_H
	add_child(tray)
	var tray_v := VBoxContainer.new()
	tray_v.add_theme_constant_override("separation", UIKit.S4)
	tray.add_child(tray_v)

	potion_row = HBoxContainer.new()
	potion_row.alignment = BoxContainer.ALIGNMENT_CENTER
	potion_row.add_theme_constant_override("separation", UIKit.S3)
	potion_row.custom_minimum_size = Vector2(0, 68)
	tray_v.add_child(potion_row)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", UIKit.S3)
	tray_v.add_child(actions)
	# F_BODY, not the F_H2 these wore through round 5. The row gained a fourth
	# control (the Essence-for-a-reroll trade) and a Button is never narrower
	# than its own text, so at heading size the bilingual labels added up to
	# 749px on a 720px canvas and "結束回合 End Turn" hung off the right edge.
	# One step down the type scale buys 90px and costs nothing legible — 22pt is
	# 16.5 physical pixels even on the 540 build.
	btn_undo = UIKit.button(Data.t("ui_undo"), UIKit.CREAM_DARK, UIKit.F_BODY, Vector2(140, 78))
	btn_undo.pressed.connect(_on_undo)
	actions.add_child(btn_undo)
	btn_reroll = UIKit.button("", UIKit.YELLOW.lightened(0.3), UIKit.F_BODY, Vector2(168, 78))
	btn_reroll.pressed.connect(_on_reroll)
	actions.add_child(btn_reroll)
	btn_buy_reroll = _build_buy_reroll()
	actions.add_child(btn_buy_reroll)
	btn_end = UIKit.button(Data.t("ui_end_turn"), UIKit.RED.lightened(0.35), UIKit.F_BODY, Vector2(176, 78))
	btn_end.pressed.connect(_on_end_turn)
	actions.add_child(btn_end)

	float_layer = Control.new()
	float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(float_layer)

	drag_layer = Control.new()
	drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drag_layer)

	_apply_zones()


# ============================================================ vertical bands

## Solve the vertical bands for the canvas we actually have and the insets the
## device actually imposes.
##
## The rule, in priority order:
##   · The TOP BAR — turn, Essence, rerolls — is below the top inset. It is the
##     one thing the player has to be able to see at all times and it is the one
##     thing that was missing on a real phone, so it is solved first and never
##     gives anything back.
##   · The ACTION TRAY and the HERO COLUMNS are above the bottom inset, at full
##     size. They are what you touch; a squeezed thumb target is a mis-play.
##   · The ENEMY BAND is the slack. It gets whatever is left, and
##     `_enemy_art_budget()` already turns a smaller band into smaller creatures
##     rather than into a card that reaches somewhere it shouldn't.
##   · Only once the enemy band is down to chrome + `ENEMY_ART_MIN` does the
##     CAST STRIP start giving, and only as far as `CAST_MIN_H`.
##
## Solved from the two edges inward rather than tabulated, so a phone whose
## insets nobody has seen yet still lands somewhere sane.
func _solve_zones() -> void:
	var h := Safe.canvas_size().y
	# everything under the enemy band, before the cast strip is priced
	var below := TRAY_H + TRAY_GAP + HERO_BAND_H + GAP_HERO + GAP_CAST + GAP_HORIZON
	# What is left for insets once every band is at its own floor. On the design
	# canvas this comes to 163 units, and the deepest real phone geometry the
	# game has to survive — a 360x640 visible strip on a device with a 47px notch
	# and a 34px home indicator, which scales to 94 + 68 — is 162. One unit of
	# margin is uncomfortably little, and it is the true number rather than a
	# padded one: this is what the 720x1280 design costs on today's phones.
	#
	# Past the budget the insets are CLAMPED, bottom first. That trades a home
	# indicator sitting over the tray's lower margin for an arena that still
	# obeys its own contract; the alternative is enemy cards growing through the
	# cast pad, which is the bug `tests/layout_test.gd` exists to prevent. No
	# shipping phone gets near it — it would have to claim a quarter of the glass.
	var budget := maxf(h - HEAD_H - below - CAST_MIN_H
			- (ENEMY_CHROME_H + ENEMY_ART_HARD_MIN), 0.0)
	var top_in := Safe.top
	var bot_in := Safe.bottom
	if top_in + bot_in > budget:
		top_in = minf(top_in, budget)
		bot_in = maxf(budget - top_in, 0.0)
	eff_top = top_in
	eff_bottom = bot_in
	var cast_h := CAST_H
	var band := h - top_in - bot_in - HEAD_H - below - cast_h
	if band < ENEMY_CHROME_H + ENEMY_ART_MIN:
		# the enemy band has run out; take the difference off the cast strip, but
		# no further than CAST_MIN_H — below that it stops reading as a drop zone
		var want := (ENEMY_CHROME_H + ENEMY_ART_MIN) - band
		var give := minf(want, CAST_H - CAST_MIN_H)
		cast_h -= give
		band += give
	ZONE_TOPBAR = top_in + 10.0
	ZONE_RELICS = top_in + 46.0
	ZONE_ENEMY_TOP = top_in + HEAD_H
	# The band is allowed to come out negative on a canvas that is absurdly short
	# (a desktop window dragged to a sliver). Clamping it to zero keeps the bands
	# ordered so the layout degrades into overlap-free nonsense instead of
	# inside-out nonsense.
	ZONE_ENEMY_BOTTOM = ZONE_ENEMY_TOP + maxf(band, 0.0)
	ZONE_HORIZON = ZONE_ENEMY_BOTTOM + GAP_HORIZON
	ZONE_CAST_TOP = ZONE_HORIZON + GAP_CAST
	ZONE_CAST_BOTTOM = ZONE_CAST_TOP + cast_h
	ZONE_HERO_TOP = ZONE_CAST_BOTTOM + GAP_HERO
	ZONE_HERO_BOTTOM = ZONE_HERO_TOP + HERO_BAND_H


## Push the solved bands onto the already-built tree. Called once at build time
## and again whenever the address bar moves or the phone is rotated.
func _apply_zones() -> void:
	var h := Safe.canvas_size().y
	if top_turn != null and top_turn.get_parent() != null:
		var top: Control = top_turn.get_parent()
		top.offset_top = ZONE_TOPBAR
		top.offset_left = Safe.left + UIKit.S4
		top.offset_right = -(Safe.right + UIKit.S4)
	if relic_scroll != null:
		relic_scroll.offset_top = ZONE_RELICS
		relic_scroll.offset_bottom = ZONE_ENEMY_TOP - 6.0
		relic_scroll.offset_left = Safe.left + UIKit.S4
		relic_scroll.offset_right = -(Safe.right + UIKit.S4)
	if enemy_row != null:
		enemy_row.offset_top = ZONE_ENEMY_TOP
		enemy_row.offset_bottom = ZONE_ENEMY_BOTTOM
	if cast_zone != null:
		cast_zone.offset_top = ZONE_CAST_TOP
		cast_zone.offset_bottom = ZONE_CAST_BOTTOM
		cast_zone.offset_left = Safe.left + UIKit.S4
		cast_zone.offset_right = -(Safe.right + UIKit.S4)
	if hero_row != null:
		hero_row.offset_top = ZONE_HERO_TOP
		hero_row.offset_bottom = ZONE_HERO_BOTTOM
	if tray_panel != null:
		# The tray is anchored to the bottom EDGE, not to the safe area: the slab
		# runs into the home-indicator strip so there is no bare background under
		# it. Its contents are what get pushed up, via the bottom content margin.
		tray_panel.offset_top = -(TRAY_H + eff_bottom)
		var box: StyleBoxFlat = tray_panel.get_theme_stylebox("panel")
		if box != null:
			box.content_margin_bottom = UIKit.S4 + eff_bottom
	_publish_hud_rects(h)


## The scenery's canopy hangs off the top of the enemy band and its horizon runs
## along the line the party stands on, so a band that moved leaves the painting
## behind. Redrawn rather than re-anchored: `Forest.scenery` bakes the two y
## positions into a `_draw`.
func _rebuild_arena_bg() -> void:
	if not is_instance_valid(arena_bg):
		return
	var idx := arena_bg.get_index()
	var old := arena_bg
	arena_bg = _build_arena_bg(int(args.get("opts", {}).get("chapter", 1)))
	add_child(arena_bg)
	move_child(arena_bg, idx)
	old.queue_free()


func _on_viewport_changed() -> void:
	if bc == null or top_turn == null or not is_instance_valid(top_turn):
		return
	_solve_zones()
	_apply_zones()
	_rebuild_arena_bg()
	_refresh()


## Hand the two rects that matter to the page, so the Playwright regression can
## assert they are on the glass. Deferred one frame: a container's rect is only
## real after its sort.
func _publish_hud_rects(_h: float) -> void:
	if not OS.has_feature("web"):
		return
	_publish_deferred.call_deferred()


func _publish_deferred() -> void:
	if top_turn != null and is_instance_valid(top_turn) and top_turn.get_parent() != null:
		Safe.publish_hud("topbar", (top_turn.get_parent() as Control).get_global_rect())
	if tray_panel != null and is_instance_valid(tray_panel):
		Safe.publish_hud("tray", tray_panel.get_global_rect())
	if essence_bar != null and is_instance_valid(essence_bar):
		Safe.publish_hud("essence", essence_bar.get_global_rect())


## The arena: chapter sky, a dark canopy the enemies stand under, a horizon
## line, and a lighter forest floor for the party's half. Three flat bands is
## enough to stop the screen reading as one slab of colour, and it gives the
## empty middle a reason to exist.
func _build_arena_bg(chapter: int) -> Control:
	# The arena is the same forest every other screen stands in, cut to the
	# battle's own bands: the canopy hangs just above the enemy row and the
	# horizon runs along the line the party stands on.
	return Forest.scenery(chapter, ZONE_ENEMY_TOP - 6.0, ZONE_HORIZON)


# ============================================================ refresh

func _refresh() -> void:
	# Snapshot where every card is BEFORE the rebuild frees it. Floating numbers
	# are spawned after _refresh(), by which point the new cards exist but have
	# not been laid out yet, so their get_global_rect() is still (0,0) — that is
	# what used to fling damage numbers into the top-left corner.
	_capture_anchors()
	# the rebuild frees whatever was swollen under the finger
	_hover = {}
	_clear_selection_if_stale()
	_refresh_top()
	_refresh_enemies()
	_refresh_heroes()
	_refresh_buttons()
	_refresh_potions()
	_refresh_cast_zone()
	# the container sort was queued during this rebuild; a deferred call runs
	# after it, so this is the one moment the new rects can be trusted
	_capture_anchors.call_deferred()
	if bc.s.over and overlay == null:
		_show_result()


func _clear_selection_if_stale() -> void:
	if sel.is_empty():
		return
	if not bc.can_use(int(sel.hero), int(sel.die)).ok:
		_deselect()


func _deselect() -> void:
	sel = {}
	pending_stuns = []
	pending_wild_src = {}
	pending_theft = {}
	pending_potion = -1


## The die currently driving target highlighting (dragged one wins).
func _active_die() -> Dictionary:
	if not drag.is_empty():
		return drag
	return sel


func _refresh_top() -> void:
	top_turn.text = "%s %d" % [Data.t("ui_turn"), bc.s.turn]
	if essence_bar != null and essence_bar.visible:
		essence_bar.set_value(int(bc.s.mana), BattleCore.MANA_CAP, _castable_cost())
	# U+2B6E, not the U+21BB this used to be: U+21BB is in no Noto face, so it
	# was only ever drawing because Windows had Segoe UI Symbol behind it, and
	# it came out a tofu box the moment the game ran in a browser. Same arrow,
	# in the face the game now ships. See tools/font_build.py.
	top_reroll.text = "⭮ ∞" if bc.rerolls_unlimited() else "⭮ %d" % bc.s.rerolls


## What a Ritual would cost the pool right now, for the meter's shimmer, or -1
## if nothing castable is on the table.
##
## The die in the player's hand wins: while a Ritual is picked up or lifted, the
## cells that ARE about to be spent are the ones that light, which makes the
## meter a preview of the action rather than a general statement about the
## party. With nothing held it falls back to the cheapest castable Ritual
## anywhere on the table — "there is something you can afford", which is the
## question a player asks before they pick anything up.
func _castable_cost() -> int:
	var a := _active_die()
	if not a.is_empty():
		var c := bc.can_use(int(a.hero), int(a.die))
		if c.ok and c.face.has("spell"):
			return bc.spell_cost(c.face)
	var best := -1
	for i in bc.s.heroes.size():
		for d in BattleCore.DICE:
			var uc := bc.can_use(i, d)
			if not uc.ok or not uc.face.has("spell"):
				continue
			var cost := bc.spell_cost(uc.face)
			if cost <= int(bc.s.mana) and (best < 0 or cost < best):
				best = cost
	return best


## Always, since round 6.
##
## This used to ask whether the party owned any Gather or Ritual face at all and
## hid the meter otherwise — a bar that can never move reads as a broken
## resource rather than an unused one. U1 and U2 retired the question: every
## party draws Essence at the start of every turn, and every party can spend it
## on a reroll, so there is no longer a party for whom the meter is dead.
##
## Kept as a function, and still called, rather than deleted: it is the one
## place that records WHY the meter is unconditional now, and if a mode ever
## turns Essence off again this is where that belongs.
func _party_uses_essence() -> bool:
	return true


## A ten-cell meter: current Essence lit, the rest sunk. Long-pressing it opens
## the same glossary entry a Ritual face's cost badge does.
##
## ── why it moves ────────────────────────────────────────────────────
## Round 5's meter was a static bar in the corner. It was also, for most
## parties, a bar that never changed, and the two facts reinforced each other:
## nothing drew the eye to it because nothing happened there. U1 and U2 mean
## something happens every single turn, so the meter now says so —
##
##   · a chip flies IN when the pool gains and OUT when it is spent, carrying
##     the signed amount, so a change is legible without watching the number;
##   · the cells a currently-affordable Ritual would consume shimmer, which
##     turns "can I cast anything?" from arithmetic into a glance;
##   · the whole bar pulses when Essence lands.
##
## All three are decoration over the same two integers. Nothing here can change
## what the pool is; if the animation and the number ever disagree, the number
## is right.
class _EssenceBar:
	extends Control

	const CELLS := 10
	const BAR := Vector2(268, 30)
	## How long a gain/spend chip takes to fly, and how far it travels.
	const CHIP_T := 0.55
	const CHIP_RISE := 26.0
	## Shimmer speed for the affordable cells, in radians a second.
	const SHIMMER_W := 3.4

	var value := 0
	var cap := 10
	var _label: Label
	## Cells [_glow_from, _glow_to) shimmer: the ones a castable Ritual would eat.
	var _glow_from := -1
	var _glow_to := -1
	var _shimmer := 0.0
	var _pulse := 0.0

	func _init() -> void:
		custom_minimum_size = BAR
		size = BAR
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		_label = UIKit.label("", UITheme.F_CAPTION, UITheme.CREAM)
		_label.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
		_label.add_theme_constant_override("outline_size", 5)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_apply()

	## `spend` is the cost of the cheapest Ritual the party could cast right now,
	## or -1 for none — that is what decides which cells shimmer.
	func set_value(v: int, c := 10, spend := -1) -> void:
		var lo := -1
		var hi := -1
		if spend > 0 and spend <= v:
			lo = v - spend
			hi = v
		var same: bool = v == value and c == cap and lo == _glow_from and hi == _glow_to
		if same:
			return
		var delta := v - value
		var had := _label != null   # no chip for the meter's very first fill
		value = v
		cap = maxi(c, 1)
		_glow_from = lo
		_glow_to = hi
		set_process(lo >= 0 or _pulse > 0.0)
		if had and delta != 0:
			_fly(delta)
			if delta > 0:
				pulse()
		_apply()

	## Flash the whole bar. Public because the things worth flashing for are not
	## all value changes — rolling an Essence face is news before it is spent.
	func pulse() -> void:
		_pulse = 1.0
		set_process(true)
		queue_redraw()

	## The signed amount, as a chip that flies into the bar on a gain and out of
	## it on a spend. Freed by the tween that moves it, so nothing accumulates.
	func _fly(delta: int) -> void:
		var chip := UIKit.chip("%+d" % delta,
				UITheme.BLUE if delta > 0 else UITheme.ORANGE, UITheme.F_CAPTION, UITheme.S2)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.z_index = 2
		add_child(chip)
		# laid out by hand: a chip parked in the middle of a meter is not a child
		# any container should be sorting
		chip.position = Vector2(size.x * 0.5 - 18.0,
				(-CHIP_RISE if delta > 0 else 0.0) + size.y * 0.1)
		chip.modulate.a = 0.0 if delta > 0 else 1.0
		var to_y: float = chip.position.y + (CHIP_RISE if delta > 0 else CHIP_RISE)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(chip, "position:y", to_y, CHIP_T).set_trans(Tween.TRANS_SINE)
		tw.tween_property(chip, "modulate:a", 0.0 if delta < 0 else 1.0, CHIP_T * 0.45)
		tw.chain().tween_property(chip, "modulate:a", 0.0, CHIP_T * 0.5)
		tw.chain().tween_callback(chip.queue_free)

	func _process(delta: float) -> void:
		if _pulse > 0.0:
			_pulse = maxf(_pulse - delta * 2.6, 0.0)
		if _glow_from >= 0:
			_shimmer += delta * SHIMMER_W
		elif _pulse <= 0.0:
			set_process(false)
		queue_redraw()

	func _apply() -> void:
		if _label != null:
			_label.text = "%d / %d" % [value, cap]
		queue_redraw()

	func _draw() -> void:
		var n := mini(cap, CELLS)
		var track := UIKit.flat_box(Color("14161d"), UITheme.R_CHIP, UITheme.B_BASE,
				UITheme.OUTLINE, 0)
		track.set_content_margin_all(0)
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var pad := 4.0
		var gap := 2.0
		var cw := (size.x - pad * 2.0 - gap * (n - 1)) / float(n)
		# 0 at rest, up to 0.30 at the top of a pulse
		var flash := _pulse * 0.30
		var shine := 0.18 + 0.17 * sin(_shimmer)
		for i in n:
			var r := Rect2(Vector2(pad + i * (cw + gap), pad),
					Vector2(cw, size.y - pad * 2.0))
			if i < value:
				draw_rect(r, UITheme.BLUE.lightened(0.12 + flash))
				draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.34)),
						Color(1, 1, 1, 0.22))
				# the cells a castable Ritual is about to take, breathing
				if i >= _glow_from and i < _glow_to:
					draw_rect(r, Color(1, 1, 1, shine))
			else:
				draw_rect(r, Color(0.30, 0.34, 0.46, 0.42 + flash * 0.5))


# ============================================================ relic strip

## Everything the party is carrying, small, along the top of the arena. Two
## rows at most; past that it scrolls sideways rather than eating the enemy
## band. Holding any icon opens that relic's card.
func _build_relic_row() -> void:
	for c in relic_row.get_children():
		c.queue_free()
	var ids: Array = bc.s.relics
	relic_scroll.visible = not ids.is_empty()
	if ids.is_empty():
		return
	# advanced first — those are the ones that change how a turn is played
	var ordered := []
	for tier in ["advanced", "common"]:
		for rid in ids:
			if GameData.relics.has(rid) and GameData.relic_rarity(String(rid)) == tier:
				ordered.append(String(rid))
	# one row up to PER_ROW, a second row past that, and nothing beyond two —
	# the strip is a reminder of what you are carrying, not a second inventory
	# screen, and the enemy band below it is not negotiable
	var rows := 1 if ordered.size() <= RELICS_PER_ROW else 2
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIKit.S1)
		relic_row.add_child(line)
		for k in range(r, ordered.size(), rows):
			line.add_child(_relic_pip(String(ordered[k])))


const RELIC_PIP := 36.0
## Past this the strip goes to two rows; past two rows' worth it scrolls
## sideways. Ten 36px pips plus their gaps is 396px, so a full 20-relic run
## still fits the 688px of usable width without ever scrolling.
const RELICS_PER_ROW := 10


func _relic_pip(rid: String) -> Control:
	var rd: Dictionary = GameData.relics[rid]
	var hue := DetailCard.relic_hue(rid)
	var advanced: bool = GameData.relic_rarity(rid) == "advanced"
	var pip := PanelContainer.new()
	var sb := UIKit.flat_box(UITheme.deepen(hue), UIKit.R_CHIP,
			UIKit.B_BASE if advanced else UIKit.B_HAIR,
			UITheme.YELLOW.lightened(0.25) if advanced else hue.lightened(0.25), 2)
	pip.add_theme_stylebox_override("panel", sb)
	pip.custom_minimum_size = Vector2(RELIC_PIP, RELIC_PIP)
	pip.add_child(Glyphs.icon(String(rd.get("glyph", "relic")), RELIC_PIP - 10.0,
			hue.lightened(0.5)))
	_attach_longpress(pip, func() -> void:
		_hide_tooltip()
		_tooltip = DetailCard.show_relic_list(self, bc.s.relics))
	return pip


## Where the active die may legally be dropped.
##   {enemies: [j…], heroes: [i…], enemy_dice: bool, cast: bool, wild: [refs]}
func _drop_spec() -> Dictionary:
	var none := {"enemies": [], "heroes": [], "enemy_dice": false, "cast": false, "wild": []}
	var a := _active_die()
	if a.is_empty():
		# a potion waiting for its target highlights the party
		if pending_potion >= 0:
			var all := []
			for i in bc.s.heroes.size():
				all.append(i)
			return {"enemies": [], "heroes": all, "enemy_dice": false, "cast": false, "wild": []}
		return none
	return _drop_spec_for(int(a.hero), int(a.die))


## Same, for an arbitrary die (used by the tools and by hit-testing).
func _drop_spec_for(i: int, d: int) -> Dictionary:
	var none := {"enemies": [], "heroes": [], "enemy_dice": false, "cast": false, "wild": []}
	var c := bc.can_use(i, d)
	if not c.ok:
		return none
	var fd: Dictionary = c.face
	# a wild that already picked its source targets like the copied face
	if not pending_wild_src.is_empty() and fd.get("wild", false):
		fd = bc.die_face(int(pending_wild_src.hero), int(pending_wild_src.die))
	# a theft that already picked its die now needs an enemy to hit
	if not pending_theft.is_empty():
		return {"enemies": bc._alive_enemies(), "heroes": [], "enemy_dice": false,
			"cast": false, "wild": []}
	var spec := none.duplicate(true)
	match String(fd.get("target", "none")):
		"enemy":
			spec.enemies = bc._alive_enemies()
		"ally":
			for j in bc.s.heroes.size():
				spec.heroes.append(j)     # healing a downed ally revives them
		"enemy_die":
			spec.enemy_dice = true
			spec.enemies = bc._alive_enemies()
		"self":
			spec.heroes = [i]
		"wild":
			spec.wild = bc.legal_targets(i, d).indices
		_:
			# target "none" covers three very different shapes
			if fd.get("aoe", false) and (fd.has("atk") or fd.has("poison") or fd.has("burn")):
				spec.enemies = bc._alive_enemies()
			elif fd.has("team_block") or fd.has("team_heal") or fd.has("team_thorns") \
					or fd.has("team_regen"):
				spec.heroes = bc._alive_heroes()
			else:
				spec.cast = true
	return spec


## The pad is permanent; only its emphasis changes. Live = a die that can land
## here is in the air, so it lights up green and the label goes full strength.
## The strip under the arena. Two states, and the second one is the round-6
## change:
##
##   idle    — "✦ 施放 Cast", the standing invitation that teaches the gesture.
##   holding — the full effect sentence for whatever die is picked up or lifted,
##             in both languages, with every number already worked out against
##             this hero, this turn, these relics.
##
## The pips under a die are the glance; this is the sentence. Between them a
## player can read their whole hand without opening anything, and the long-press
## card goes back to being what it should be — the place you go to look up a
## keyword, not the only place the game explains itself.
func _refresh_cast_zone() -> void:
	var spec := _drop_spec()
	var live: bool = not _active_die().is_empty() and bool(spec.cast)
	var chapter := int(args.get("opts", {}).get("chapter", 1))
	if cast_btn != null:
		cast_btn.visible = not sel.is_empty() and bool(spec.cast)
	_refresh_cast_text()
	if live:
		cast_panel.add_theme_stylebox_override("panel", UIKit.card_box(
				UITheme.surface(chapter), UIKit.R_LG, UIKit.B_FOCUS, UIKit.GREEN,
				CAST_PAD))
		cast_label.add_theme_color_override("font_color", UIKit.CREAM)
		cast_zone.modulate.a = 1.0
	else:
		var idle := UIKit.flat_box(UITheme.surface_deep(chapter), UIKit.R_LG,
				UIKit.B_BASE, UITheme.surface(chapter).lightened(0.18), CAST_PAD)
		cast_panel.add_theme_stylebox_override("panel", idle)
		cast_label.add_theme_color_override("font_color", UIKit.CREAM_DARK)
		# A held die that lands somewhere ELSE (an enemy, an ally) still gets its
		# sentence read out, so the strip stays at full strength whenever it is
		# saying something. It only sits back when it is an empty invitation.
		cast_zone.modulate.a = 1.0 if not _active_die().is_empty() else 0.55


## Font sizes for the strip. The prompt is a heading; a sentence is body text,
## and a bilingual one is two lines of it.
const CAST_PAD := 6
const CAST_F_PROMPT := UITheme.F_H2
## Sizes the sentence is allowed to shrink through, largest first. It stops at
## F_MICRO: below that the text is present but not readable, and a strip nobody
## can read is worse than one honest line of "…".
const CAST_F_STEPS := [UITheme.F_BODY_SM, UITheme.F_CAPTION, 13, UITheme.F_MICRO]


func _refresh_cast_text() -> void:
	if cast_label == null:
		return
	var a := _active_die()
	var fd := {}
	if not a.is_empty():
		fd = bc.die_face(int(a.hero), int(a.die))
	if fd.is_empty():
		cast_label.text = "✦ " + Data.t("ui_cast_zone")
		cast_label.add_theme_font_size_override("font_size", CAST_F_PROMPT)
		return
	var i := int(a.hero)
	# a wild that has already picked its source is describing the COPIED face,
	# which is the one that will actually resolve
	if not pending_wild_src.is_empty() and fd.get("wild", false):
		fd = bc.die_face(int(pending_wild_src.hero), int(pending_wild_src.die))
	var txt := "%s — %s" % [Data.face_name(fd), Glossary.effect_sentence(bc.live_face(i, fd))]
	cast_label.add_theme_font_size_override("font_size", _cast_font_for(txt))
	cast_label.text = txt


## The largest size from `CAST_F_STEPS` at which `txt` still fits the strip.
##
## Measured against the font rather than guessed from the string length: the
## sentences are bilingual, and a Chinese line and an English one of the same
## character count are nowhere near the same width. `get_multiline_string_size`
## wraps exactly the way the Label will, so what this returns is what fits.
func _cast_font_for(txt: String) -> int:
	var font := cast_label.get_theme_font("font")
	if font == null:
		return CAST_F_STEPS[1]
	# the strip, less its side margins, its border and the panel padding
	var avail_w := Safe.canvas_size().x - 2.0 * UIKit.S4 - 2.0 * (CAST_PAD + UIKit.B_STRONG)
	var avail_h := (ZONE_CAST_BOTTOM - ZONE_CAST_TOP) - 2.0 * (CAST_PAD + UIKit.B_STRONG)
	for fs in CAST_F_STEPS:
		var sz := font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER,
				avail_w, int(fs), -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND)
		if sz.y <= avail_h:
			return int(fs)
	return int(CAST_F_STEPS[CAST_F_STEPS.size() - 1])


func _refresh_enemies() -> void:
	for c in enemy_row.get_children():
		c.queue_free()
	enemy_cards = []
	enemy_widgets = {}
	var spec := _drop_spec()
	for j in bc.s.enemies.size():
		var e: Dictionary = bc.s.enemies[j]
		if e.dead:
			continue
		var is_target: bool = j in spec.enemies
		var card := _make_enemy_card(j, e, is_target, spec)
		enemy_row.add_child(card)
		enemy_cards.append(card)
		enemy_widgets[j]["card"] = card
		if _targeting() and not is_target:
			card.modulate = Color(0.55, 0.55, 0.6, 0.85)


## True while something is looking for a target (drag or tap selection).
func _targeting() -> bool:
	return not _active_die().is_empty() or pending_potion >= 0


## Flat dark ellipse a pawn stands on — the cheapest way to stop a creature
## looking like a sticker floating in its card.
func _ground_shadow(cx: float, cy: float, rx: float) -> Control:
	var c := Panel.new()
	var sb := UIKit.flat_box(Color(0, 0, 0, 0.30), 999, 0, UIKit.OUTLINE, 0)
	sb.set_border_width_all(0)
	c.add_theme_stylebox_override("panel", sb)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = Vector2(cx - rx, cy - 7.0)
	c.size = Vector2(rx * 2.0, 14.0)
	return c


## How tall an enemy's art may be before its card starts reaching out of the
## enemy band. This is the fix for the boss-card-over-the-cast-pad bug: the
## band is a fixed budget, the chrome around the art is a known constant, and
## whatever is left over is what the creature gets. An oversized boss now
## shrinks; it never pushes the cast pad out of the way.
func _enemy_art_budget() -> float:
	# Floored, because the band is now solved against the device rather than
	# fixed at 474: a phone with deep insets can hand the enemies less than their
	# own chrome, and a negative art height would flip the card inside out. At
	# the floor the creature is small and the card is honest about it; that beats
	# a broken rect.
	return maxf(ZONE_ENEMY_BOTTOM - ZONE_ENEMY_TOP - ENEMY_CHROME_H, ENEMY_ART_HARD_MIN)


## Card geometry shrinks as the fight gets crowded, so one boss reads huge and
## a boss plus two summons still fits inside 720px — then the whole thing is
## clamped to the band budget above.
func _enemy_metrics(n: int, is_boss: bool) -> Dictionary:
	var art := 200.0
	var w := 300.0
	if n == 2:
		art = 152.0
		w = 212.0
	elif n == 3:
		art = 124.0
		w = 172.0
	elif n >= 4:
		art = 104.0
		w = 148.0
	if is_boss:
		# a boss still reads as clearly the biggest thing on screen, even when
		# it drags two summons on with it
		art = maxf(art * 1.35, 210.0)
		w = maxf(w * 1.2, 236.0)
	return {"art": minf(art, _enemy_art_budget()), "w": w}


## Which `PawnArt` design draws this enemy. Only Sir Croak needs the indirection
## — he keeps the key `B3` all through the fight (the codex, the "met" flags and
## his stat block are all filed under it) but stops looking like a man on a
## goose the moment the goose goes down.
func _art_key(e: Dictionary) -> String:
	if String(e.get("boss_key", "")) == "B3" and int(e.get("phase", 1)) >= 2:
		return "B3P2"
	return String(e.key)


func _make_enemy_card(j: int, e: Dictionary, is_target: bool, spec: Dictionary) -> Control:
	var border := UIKit.GREEN if is_target else UIKit.OUTLINE
	var chapter := int(args.get("opts", {}).get("chapter", 1))
	var n := bc._alive_enemies().size()
	var m := _enemy_metrics(n, e.kind == "boss")
	var p := UIKit.card(chapter, UIKit.R_LG, UIKit.B_FOCUS if is_target else UIKit.B_STRONG,
			border, UIKit.S2)
	# cards stand on the ground line at the bottom of the enemy band rather
	# than floating in the middle of it
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	p.custom_minimum_size = Vector2(float(m.w), 0)
	var inner_w: float = float(m.w) - 2 * UIKit.S3
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UIKit.S1)
	p.add_child(vb)
	if e.kind == "boss":
		var tag := CenterContainer.new()
		tag.add_child(UIKit.chip(Data.bi("首領", "BOSS"), UIKit.RED, UIKit.F_CAPTION, UIKit.S3))
		vb.add_child(tag)
	var name_l := UIKit.text_block(Data.bi(e.zh, e.en),
			UIKit.F_BODY if e.kind == "boss" else UIKit.F_BODY_SM,
			UITheme.CAT_ON_DARK.attack if e.kind == "boss" else UIKit.CREAM, inner_w)
	vb.add_child(name_l)
	# art, standing on a shadow, with headroom so tall silhouettes (hats,
	# antlers) cannot climb into the name above
	var art_holder := Control.new()
	var art_h: float = m.art
	art_holder.custom_minimum_size = Vector2(inner_w, art_h + 10.0)
	var art_key := _art_key(e)
	var art_tier := int(e.get("tier", 1))
	art_holder.add_child(_ground_shadow(inner_w * 0.5, art_h + 4.0,
			PawnArt.half_width(art_key, art_tier) * PawnArt.fit_height(art_key,
					Vector2(inner_w, art_h)) * 0.95))
	var art := PawnArt.fitted(art_key, Vector2(inner_w, art_h), true, art_tier, chapter)
	art.position = Vector2(inner_w * 0.5, art_h + 4.0)
	art_holder.add_child(art)
	vb.add_child(art_holder)
	enemy_widgets[j] = {"art": art, "chips": {}}
	# hp
	var bar_w: float = float(m.w) - 2 * UIKit.S3 - 34.0
	var hp_h := HBoxContainer.new()
	hp_h.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_h.add_theme_constant_override("separation", UIKit.S1)
	hp_h.add_child(UIKit.hp_bar(e.hp, e.max_hp, Vector2(bar_w, 16), UIKit.RED))
	hp_h.add_child(UIKit.label("%d" % e.hp, UIKit.F_CAPTION, UIKit.CREAM))
	vb.add_child(hp_h)
	# status badges
	var sc := _status_chips(e)
	if sc != null:
		vb.add_child(sc)
	# intent chips
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", UIKit.S1)
	for d in e.rolls.size():
		var roll: Dictionary = e.rolls[d]
		var chip := _make_intent_chip(j, d, roll, spec)
		chips.add_child(chip)
		enemy_widgets[j]["chips"][d] = chip
	vb.add_child(UIKit.spacer(UIKit.S1))
	vb.add_child(chips)
	# damage preview
	var a := _active_die()
	if is_target and not a.is_empty() and pending_theft.is_empty():
		var pv := bc.preview_attack(int(a.hero), int(a.die), j)
		var pv_txt := ""
		if pv.has("hp_loss"):
			pv_txt = "-%d" % int(pv.hp_loss)
		elif pv.has("min"):
			pv_txt = "%d-%d" % [int(pv.min), int(pv.max)]
		if pv_txt != "":
			var pc := CenterContainer.new()
			# damage preview wears the attack hue like every other damage number:
			# green would read as "good for the thing you are about to hit"
			pc.add_child(UIKit.chip(pv_txt, UIKit.RED, UIKit.F_H2, UIKit.S3))
			vb.add_child(pc)
	# tap target. The forecast card is attached either way — "what is this thing
	# about to do to me" must not stop working just because the card happens to
	# be a legal drop zone this instant.
	UIKit.mouse_passthrough(vb)
	if is_target:
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(64, 64)
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.pressed.connect(func() -> void: _on_enemy_tapped(j))
		p.add_child(btn)
		_attach_longpress(btn, func() -> void: _show_enemy_card(j))
	else:
		_attach_longpress(p, func() -> void: _show_enemy_card(j))
	return p


## What an enemy die is threatening, as [glossary key, number] — the number is
## -1 when the term is a flag. First entry is the headline; the rest ride along
## as small extra badges.
func _intent_terms(e: Dictionary, f: Dictionary) -> Array:
	var out := []
	if f.has("atk"):
		out.append(["atk", bc._enemy_face_value(e, f, "atk")])
		if f.get("aoe", false):
			out.append(["aoe", -1])
		if f.get("pierce", false):
			out.append(["pierce", -1])
		if f.has("poison"):
			out.append(["poison", int(f.poison)])
		if f.has("burn"):
			out.append(["burn", int(f.burn)])
		return out
	for pair in [["block", "block"], ["heal", "heal"], ["weaken", "weaken"],
			["poison", "poison"], ["charge", "charge"], ["counter", "counter"],
			["mana_drain", "mana_drain"]]:
		if f.has(pair[0]):
			var v := int(f[pair[0]])
			if pair[0] in ["block", "heal"]:
				v = bc._enemy_face_value(e, f, String(pair[0]))
			out.append([String(pair[1]), v])
			if f.get("aoe", false):
				out.append(["aoe", -1])
			return out
	for flag in ["bind", "curse", "howl", "summon", "cancel_die", "expose"]:
		if f.get(flag, false) or f.has(flag):
			out.append([flag, -1])
			return out
	return [["blank", -1]]


## An enemy's threat, in the SAME pips the player's own dice wear.
##
## It used to be one chip carrying the headline glyph and then every rider's
## number glued onto it as bare digits — "⚔ 6 2" for an attack that also
## poisons, which reads as a number nobody can parse. Now each term is its own
## pip, in the shorthand grammar (`Shorthand`): the poison rider wears the
## poison glyph, exactly as it does under your Badger's die and on the status
## badge it will become. One picture, one meaning, on both sides of the arena.
func _make_intent_chip(j: int, d: int, roll: Dictionary, spec: Dictionary) -> Control:
	var f: Dictionary = roll.face
	var e: Dictionary = bc.s.enemies[j]
	var terms := _intent_terms(e, f)
	var head := String(terms[0][0])
	var col := Glossary.hue(head)
	var dimmed: bool = roll.cancelled or roll.done
	# the outer chip keeps the headline's hue and frame — that is what makes an
	# intent read as one threat rather than as loose badges
	var chip := UIKit.chip("", col, UIKit.F_BODY_SM, UIKit.S1)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in terms:
		var key := String(t[0])
		var n := int(t[1])
		inner.add_child(Shorthand.pip(
				{"key": key, "text": "" if n < 0 else str(n), "hue": Glossary.hue(key)},
				UIKit.F_BODY_SM))
	# `UIKit.chip` builds its own Label child; the pip row replaces it
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	chip.add_child(inner)
	var keys := []
	for t in terms:
		keys.append(String(t[0]))
	_attach_longpress(chip, func() -> void: _show_term(head, keys))
	var sb: StyleBoxFlat = chip.get_theme_stylebox("panel")
	if dimmed:
		# a spent or cancelled intent stays visible but stops competing
		sb.bg_color = sb.bg_color.lerp(Color("3a3a3a"), 0.6)
		sb.border_color = sb.border_color.lerp(Color("6a6a6a"), 0.65)
		chip.get_child(0).modulate = Color(0.72, 0.72, 0.74, 0.85)
	# stun / steal target tap
	var can_pick: bool = bool(spec.enemy_dice) and not roll.cancelled and not roll.done
	if can_pick:
		var b := Button.new()
		b.flat = true
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.pressed.connect(func() -> void: _on_enemy_die_tapped(j, d))
		chip.add_child(b)
		sb.border_color = UIKit.GREEN
		sb.set_border_width_all(UIKit.B_BASE)
	return chip


## Statuses as a wrapping row of badges rather than one run-on line of text.
## Every badge is the same shape as an enemy intent chip and a die's category
## strip, so the player learns one visual grammar.
const STATUS_HUES := {
	"block": UITheme.BLUE, "poison": UITheme.PURPLE, "burn": UITheme.ORANGE,
	"regen": UITheme.GREEN, "thorns": UITheme.ORANGE, "weaken": UITheme.YELLOW,
	"expose": UITheme.YELLOW, "taunt": UITheme.BLUE,
}


## Live statuses as [key, count] — count 0 means the status is a flag.
func _status_list(u: Dictionary) -> Array:
	var out := []
	if int(u.get("block", 0)) > 0:
		out.append(["block", int(u.block)])
	if int(u.poison) > 0:
		out.append(["poison", int(u.poison)])
	var burn_total := 0
	for b in u.burn:
		burn_total += int(b)
	for b2 in u.get("burn_new", []):
		burn_total += int(b2)
	if burn_total > 0:
		out.append(["burn", burn_total])
	if int(u.regen) > 0:
		out.append(["regen", int(u.regen)])
	if int(u.thorns) > 0:
		out.append(["thorns", int(u.thorns)])
	if int(u.weaken) > 0:
		out.append(["weaken", int(u.weaken)])
	if u.get("expose", false):
		out.append(["expose", 0])
	if u.get("taunt", false):
		out.append(["taunt", 0])
	return out


## Status badges wear the same drawn glyph as the die face that applied them and
## the enemy intent that threatens them, and holding one opens the same
## glossary entry. One picture, one meaning, one explanation.
func _status_chips(u: Dictionary, font := UITheme.F_CAPTION) -> Control:
	var items := _status_list(u)
	if items.is_empty():
		return null
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", UIKit.S1)
	flow.add_theme_constant_override("v_separation", 2)
	for it in items:
		var key := String(it[0])
		var n := int(it[1])
		var chip := UIKit.icon_chip(Glossary.glyph_key(key), "" if n == 0 else str(n),
				STATUS_HUES.get(key, UIKit.ORANGE), font, UIKit.S1)
		_attach_longpress(chip, func() -> void: _show_term(key))
		flow.add_child(chip)
	return flow


## Hold any badge, intent chip or icon anywhere in the battle to be told what
## that word means.
func _show_term(key: String, extra := []) -> void:
	_hide_tooltip()
	_tooltip = DetailCard.show_term(self, key, extra)


func _status_text(u: Dictionary) -> String:
	var parts := []
	if u.poison > 0:
		parts.append(UIKit.glyph_n("poison", int(u.poison)))
	var burn_total := 0
	for b in u.burn:
		burn_total += int(b)
	for b in u.get("burn_new", []):
		burn_total += int(b)
	if burn_total > 0:
		parts.append(UIKit.glyph_n("burn", burn_total))
	if u.regen > 0:
		parts.append(UIKit.glyph_n("regen", int(u.regen)))
	if u.thorns > 0:
		parts.append(UIKit.glyph_n("thorns", int(u.thorns)))
	if u.weaken > 0:
		parts.append(UIKit.glyph_n("weaken", int(u.weaken)))
	if u.get("expose", false):
		parts.append(UIKit.glyph("expose"))
	if u.get("taunt", false):
		parts.append(UIKit.glyph("taunt"))
	return " ".join(parts)


# ============================================================ hero columns

func _refresh_heroes() -> void:
	for c in hero_row.get_children():
		c.queue_free()
	hero_cards = []
	hero_arts = []
	die_widgets = {}
	var spec := _drop_spec()
	for i in bc.s.heroes.size():
		var h: Dictionary = bc.s.heroes[i]
		var is_target: bool = i in spec.heroes
		var col := _make_hero_column(i, h, is_target, spec)
		hero_row.add_child(col)
		hero_cards.append(col)


## One hero = one vertical column: portrait + HP on top, that hero's two dice
## side by side underneath with the rolled face's name below each.
func _make_hero_column(i: int, h: Dictionary, is_target: bool, spec: Dictionary) -> Control:
	var border := UIKit.GREEN if is_target else UIKit.OUTLINE
	var chapter := int(args.get("opts", {}).get("chapter", 1))
	var inner_w := HERO_COL_W - 2 * HERO_COL_PAD
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(HERO_COL_W, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bgc := UITheme.surface(chapter)
	if h.down:
		bgc = UITheme.surface_deep(chapter).lerp(Color("120c0c"), 0.5)
	var col_box := UIKit.card_box(bgc, UIKit.R_LG,
			UIKit.B_FOCUS if is_target else UIKit.B_STRONG, border, HERO_COL_PAD)
	p.add_theme_stylebox_override("panel", col_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UIKit.S1)
	p.add_child(vb)

	var def: Dictionary = GameData.heroes[h.id]
	# portrait block: this is what dims when the column is not a legal target —
	# the dice below always stay at full contrast
	var portrait := VBoxContainer.new()
	portrait.add_theme_constant_override("separation", UIKit.S1)
	if _targeting() and not is_target:
		portrait.modulate = Color(0.6, 0.6, 0.64, 0.85)
	vb.add_child(portrait)

	var name_l := UIKit.label(String(def.short), UIKit.F_BODY_SM, UIKit.CREAM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.add_child(name_l)

	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(inner_w, 122)
	art_holder.add_child(_ground_shadow(inner_w * 0.5, 118.0, inner_w * 0.28))
	var art := PawnArt.fitted(String(h.id), Vector2(inner_w, 114.0))
	art.position = Vector2(inner_w * 0.5, 118)
	if h.down:
		art.modulate = Color(0.4, 0.4, 0.4, 0.7)
	art_holder.add_child(art)
	portrait.add_child(art_holder)
	hero_arts.append(art)

	var hp_h := HBoxContainer.new()
	hp_h.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_h.add_theme_constant_override("separation", UIKit.S1)
	hp_h.add_child(UIKit.hp_bar(h.hp, h.max_hp, Vector2(inner_w - 34.0, 15), UIKit.GREEN))
	hp_h.add_child(UIKit.label("%d" % h.hp, UIKit.F_CAPTION, UIKit.CREAM))
	portrait.add_child(hp_h)

	# status badges; downed/stolen are states, not stacks, so they read as words
	var st_box := VBoxContainer.new()
	st_box.add_theme_constant_override("separation", 2)
	st_box.custom_minimum_size = Vector2(inner_w, 26)
	if h.down or h.stolen:
		var word := Data.t("ui_downed") if h.down else Data.t("ui_stolen")
		var wl := UIKit.text_block(word, UIKit.F_CAPTION,
				UITheme.CAT_ON_DARK.attack if h.down else UITheme.CAT_ON_DARK.control, inner_w)
		st_box.add_child(wl)
	if not h.down:
		var sc := _status_chips(h, UIKit.F_CAPTION)
		if sc != null:
			st_box.add_child(sc)
	portrait.add_child(st_box)

	# --- the two dice
	var dice_h := HBoxContainer.new()
	dice_h.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_h.add_theme_constant_override("separation", UIKit.S2)
	var names_h := HBoxContainer.new()
	names_h.alignment = BoxContainer.ALIGNMENT_CENTER
	names_h.add_theme_constant_override("separation", UIKit.S2)
	for d in BattleCore.DICE:
		dice_h.add_child(_make_die(i, d, spec))
		names_h.add_child(_make_die_name(i, d))
	vb.add_child(UIKit.spacer(UIKit.S1))
	vb.add_child(dice_h)
	vb.add_child(names_h)

	# the column itself is the drop/tap target for ally-facing faces
	UIKit.mouse_passthrough(name_l)
	UIKit.mouse_passthrough(art_holder)
	UIKit.mouse_passthrough(hp_h)
	UIKit.mouse_passthrough(st_box)
	if is_target:
		# The tap target is the PORTRAIT ONLY. A hero column is a PanelContainer,
		# so a Button dropped straight into it gets stretched over the whole card
		# — dice included — and a selected self-targeting face turned its own die
		# into a "use" button. That is the mis-fire this whole pass exists to
		# kill, so the hit area is parked in a plain Control (which does not lay
		# its children out) and sized to the portrait once the column has sorted.
		var hit := Control.new()
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(hit)
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2.ZERO
		btn.size = Vector2(HERO_COL_W, 200.0)
		btn.pressed.connect(func() -> void: _on_hero_tapped(i))
		hit.add_child(btn)
		_fit_to.call_deferred(btn, portrait)
	else:
		_attach_longpress(p, func() -> void: _show_tooltip(_hero_tooltip(i)))
	return p


## Park `what` exactly over `over`'s laid-out rect. Deferred by the caller, so
## it runs after the container sort that gives `over` a real rect.
func _fit_to(what: Control, over: Control) -> void:
	if not is_instance_valid(what) or not is_instance_valid(over):
		return
	var r := over.get_global_rect()
	if r.size.y <= 1.0:
		return
	what.global_position = r.position
	what.size = r.size


## All six faces of one of a hero's dice, resolved (forge marks, Growth stacks
## and battle-long curses included) — this is what gets printed on the cube.
func _die_faces(i: int, d: int) -> Array:
	var out := []
	for k in BattleCore.FACES:
		out.append(bc.hero_face(i, d * BattleCore.FACES + k))
	return out


func _make_die(i: int, d: int, spec: Dictionary) -> Control:
	var h: Dictionary = bc.s.heroes[i]
	var slot: int = int(h.rolled[d])
	var holder := Control.new()
	holder.custom_minimum_size = Die3D.SIZE
	var dv := Die3D.new()
	dv.hero = i
	dv.die = d
	holder.add_child(dv)
	die_widgets["%d:%d" % [i, d]] = dv
	var faces := _die_faces(i, d)

	if slot < 0:
		# the hero is down or had this die stolen: the cube is still there, just
		# out of play, which reads better than an empty hole in the column
		dv.set_die(faces, 0, true, false, true, false)
		dv.interactive = false
		return holder

	var usable := bc.can_use(i, d)
	var spent: bool = d in h.get("used_dice", [])
	# with 雙月徽記 in play a hero's second die is NOT locked out, so "the hero
	# has acted" is no longer the test on its own — only a refused die is
	var locked_out: bool = bool(h.used) and not spent and not usable.ok
	var a := _active_die()
	var is_active: bool = not a.is_empty() and int(a.hero) == i and int(a.die) == d
	var is_wild_src := false
	for ref in spec.wild:
		if int(ref.hero) == i and int(ref.die) == d:
			is_wild_src = true
	dv.set_die(faces, slot % BattleCore.FACES, not usable.ok, bool(h.locked[d]),
			locked_out or spent, is_active or is_wild_src)
	dv.interactive = not bc.s.over
	# a spent, locked-out, blanked or unaffordable die still taps (for its
	# "no" cue) and still long-presses for its detail card, but never lifts
	dv.draggable = usable.ok
	dv.pressed.connect(_on_die_pressed)
	dv.long_pressed.connect(_on_die_long_pressed)
	dv.drag_started.connect(_on_drag_started)
	return holder


## Hold a die to open its detail card: a copy of the die you can turn over with
## a finger, the rolled face explained in full, and all six faces listed.
func _on_die_long_pressed(i: int, d: int) -> void:
	_hide_tooltip()
	var slot: int = int(bc.s.heroes[i].rolled[d])
	_tooltip = DetailCard.show_die(self, _die_faces(i, d),
			maxi(slot, 0) % BattleCore.FACES)


## Height of the name block: the face name, then its shorthand pips.
const NAME_H := 46.0
const PIPS_H := 26.0


## Under each die: the rolled face's NAME, and under that what it actually does.
##
## The name alone was the round-5 shape and it does not work. "翻湧 / Surge"
## identifies a face you have met before and tells a new player nothing, so the
## only way to read your own hand was to long-press all eight dice in turn. The
## pip row (see `Shorthand`) answers "what does this do" without a gesture; the
## long-press card is still where the sentence and the keyword definitions live.
##
## The pips are built from the LIVE face, so a Badger swinging with 老班長 and a
## Whetstone shows ⚔5 under a face the data file calls 3.
func _make_die_name(i: int, d: int) -> Control:
	var h: Dictionary = bc.s.heroes[i]
	var slot: int = int(h.rolled[d])
	# tall enough for two wrapped lines: an English face name like "Arrow Shot"
	# needs both, and bilingual mode stacks the Chinese name on top of it
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(Die3D.SIZE.x, NAME_H + PIPS_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if slot < 0:
		return box
	var fd := bc.hero_face(i, slot)
	var mode := Data.lang_mode()
	var text := ""
	if mode == "both":
		# two tight lines so an 8-die table still reads at a glance
		text = "%s\n%s" % [Data.face_name_zh(fd), Data.face_name_en(fd)]
	else:
		text = Data.face_name(fd)
	var l := UIKit.label(text, (UIKit.F_MICRO + 1) if mode == "both" else UIKit.F_CAPTION, UIKit.CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(Die3D.SIZE.x, NAME_H)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dimmed: bool = bool(h.used) and not bc.can_use(i, d).ok
	if dimmed:
		l.add_theme_color_override("font_color", UIKit.CREAM.darkened(0.45))
	box.add_child(l)
	var pips := Shorthand.row(bc.live_face(i, fd), Die3D.SIZE.x)
	if dimmed:
		# a spent die keeps its pips — "what did I just do with this" is a real
		# question — but stops competing with the dice still in play
		pips.modulate = Color(0.68, 0.68, 0.7, 0.9)
	box.add_child(pips)
	return box


func _refresh_buttons() -> void:
	btn_reroll.text = "%s ×∞" % Data.t("ui_reroll") if bc.rerolls_unlimited() \
			else "%s ×%d" % [Data.t("ui_reroll"), bc.s.rerolls]
	btn_reroll.disabled = not bc.can_reroll()
	btn_undo.disabled = not bc.can_undo()
	btn_end.disabled = bc.s.over
	btn_buy_reroll.disabled = not bc.can_buy_reroll().ok


## U2, as a button: "2🌿 → ⭮". Small, and next to the reroll counter it feeds,
## because it is a conversion rather than an action — the throw it buys is still
## spent with the button beside it.
##
## Built by hand rather than through `UIKit.button`'s text: the two symbols in
## it are the game's own drawn glyphs (the same Essence drop the meter and every
## Ritual cost badge wear), not characters, so there is nothing to type and
## nothing for the font subset to have to carry. A Button does not lay its
## children out, so the row is parked in a full-rect Control that ignores input.
func _build_buy_reroll() -> Button:
	var b := UIKit.button("", UITheme.BLUE.lightened(0.34), UIKit.F_BODY, Vector2(96, 78))
	b.pressed.connect(_on_buy_reroll)
	var hold := Control.new()
	hold.set_anchors_preset(Control.PRESET_FULL_RECT)
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UIKit.label(str(BattleCore.ESSENCE_REROLL_COST), UIKit.F_BODY, UIKit.INK)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	row.add_child(Glyphs.icon("mana", 24.0, UITheme.BLUE.darkened(0.4)))
	var arrow := UIKit.label("→⭮", UIKit.F_BODY, UIKit.INK)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	hold.add_child(row)
	b.add_child(hold)
	_attach_longpress(b, func() -> void: _show_term("essence_reroll", ["mana"]))
	return b


func _on_buy_reroll() -> void:
	if not bc.buy_reroll():
		return
	Sfx.play("button")
	if essence_bar != null:
		essence_bar.pulse()
	_refresh()


func _refresh_potions() -> void:
	for c in potion_row.get_children():
		c.queue_free()
	for slot in bc.s.potions.size():
		var pid: String = bc.s.potions[slot]
		var pd: Dictionary = GameData.potions[pid]
		var col := UIKit.GREEN if pd.effect in ["heal", "team_heal"] else UIKit.PURPLE
		if pending_potion == slot:
			col = UIKit.YELLOW
		var b := UIKit.button(Data.bi(String(pd.zh), String(pd.en)), col.lightened(0.35),
				UIKit.F_BODY_SM, Vector2(252, 66))
		b.clip_text = true
		b.pressed.connect(func() -> void: _on_potion_tapped(slot))
		_attach_longpress(b, func() -> void:
			_show_tooltip("%s\n%s" % [Data.bi(String(pd.zh), String(pd.en)),
					Data.bi2(String(pd.desc_zh), String(pd.desc_en))]))
		potion_row.add_child(b)


func _on_potion_tapped(slot: int) -> void:
	if bc.s.over:
		return
	var pid: String = bc.s.potions[slot]
	var pd: Dictionary = GameData.potions[pid]
	if String(pd.target) == "ally":
		if pending_potion == slot:
			pending_potion = -1
		else:
			_deselect()
			pending_potion = slot
		_refresh()
		return
	_deselect()
	var res := bc.use_potion(slot)
	if res.ok:
		Sfx.play("potion")
		_spawn_floats()
	_refresh()


# ============================================================ drag & drop

## While a die is in the air the screen — not the die widget — follows the
## pointer. Picking a die up rebuilds the hero row, which frees the widget that
## started the gesture, so it cannot deliver the rest of it. Handling the drag
## here also keeps it alive over widgets that would otherwise swallow the
## events (tap overlays, the tooltip scrim).
##
## `event.position` is already in canvas space at this level, matching the
## drop zones' `get_global_rect()`.
func _input(event: InputEvent) -> void:
	if drag.is_empty():
		return
	if not _is_our_pointer(event):
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		_on_drag_moved(event.position)
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) \
			and not event.pressed:
		_on_drag_ended(event.position)
	else:
		return
	get_viewport().set_input_as_handled()


## One pointer owns a drag: the touch index that picked the die up, or the
## left mouse button. A second finger elsewhere must not drop it.
func _is_our_pointer(event: InputEvent) -> bool:
	var p := int(drag.get("pointer", -1))
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return int(event.index) == p
	if event is InputEventMouseButton:
		return p < 0 and event.button_index == MOUSE_BUTTON_LEFT
	return p < 0


func _on_drag_started(i: int, d: int, at: Vector2, pointer: int) -> void:
	if bc.s.over or not bc.can_use(i, d).ok:
		return
	_hide_tooltip()
	pending_potion = -1
	sel = {}
	# `origin` is where the finger went down, not where the die is drawn: the
	# arm distance has to be measured against the gesture, so a die that was
	# grabbed by its corner is not half-armed already.
	drag = {"hero": i, "die": d, "pointer": pointer, "origin": at, "armed": false}
	Sfx.play("button")
	_spawn_ghost(i, d, at)
	_refresh()


## Has the held die travelled far enough from its home to be droppable?
func _armed() -> bool:
	return bool(drag.get("armed", false))


func _spawn_ghost(i: int, d: int, at: Vector2) -> void:
	_clear_ghost()
	var g := Die3D.new()
	g.interactive = false
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_layer.add_child(g)
	g.set_die(_die_faces(i, d), int(bc.s.heroes[i].rolled[d]) % BattleCore.FACES,
			false, false, false, true)
	# starts small and faint: the die is in the hand but not yet thrown
	g.scale = Vector2.ONE
	g.modulate.a = 0.55
	drag_ghost = g
	_move_ghost(at)


func _move_ghost(at: Vector2) -> void:
	if is_instance_valid(drag_ghost):
		drag_ghost.global_position = at - Die3D.SIZE * 0.5


func _clear_ghost() -> void:
	if is_instance_valid(drag_ghost):
		drag_ghost.queue_free()
	drag_ghost = null


func _on_drag_moved(at: Vector2) -> void:
	_move_ghost(at)
	var was := _armed()
	var far: bool = at.distance_to(Vector2(drag.get("origin", at))) >= DRAG_ARM
	drag["armed"] = far
	if far != was:
		# arming is a state change the hand should feel: the ghost goes from a
		# faint "I am holding this" to a solid "I can put it down"
		if is_instance_valid(drag_ghost):
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(drag_ghost, "modulate:a", 0.95 if far else 0.55, 0.09)
			tw.tween_property(drag_ghost, "scale",
					Vector2(1.15, 1.15) if far else Vector2(1.0, 1.0), 0.09)
		if far:
			Sfx.play("button", 0.35)
	_update_hover(at)


func _on_drag_ended(at: Vector2) -> void:
	if drag.is_empty():
		_clear_ghost()
		return
	var held := drag.duplicate()
	# below the arm distance the gesture never became a real throw, so it
	# cancels no matter what happens to be under the finger
	var hit := _hit_test(at) if _armed() else {}
	drag = {}
	_clear_hover()
	_clear_ghost()
	if hit.is_empty():
		# dropped short or on empty space → snap back, nothing spent
		Sfx.play("block", 0.5)
		_refresh()
		return
	_resolve_drop(held, hit)


# ------------------------------------------------------------ drop preview

## The drop zone the finger is currently over, as {node, scale, border, width}
## plus the hit key, so the swell can be undone exactly.
var _hover := {}


func _hit_key(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	return "%s:%s:%s:%s" % [hit.get("kind", ""), hit.get("index", -1),
			hit.get("enemy", -1), hit.get("die", hit.get("hero", -1))]


## The widget that should visibly react for a given hit.
func _hit_node(hit: Dictionary) -> Control:
	match String(hit.get("kind", "")):
		"enemy":
			var w = enemy_widgets.get(int(hit.index), null)
			return w.card if w != null and is_instance_valid(w.card) else null
		"enemy_die":
			var w2 = enemy_widgets.get(int(hit.enemy), null)
			if w2 == null:
				return null
			var chip = w2.chips.get(int(hit.die), null)
			return chip if is_instance_valid(chip) else null
		"hero":
			var i := int(hit.index)
			return hero_cards[i] if i < hero_cards.size() and is_instance_valid(hero_cards[i]) else null
		"wild":
			var dv = die_widgets.get("%d:%d" % [int(hit.hero), int(hit.die)], null)
			return dv if is_instance_valid(dv) else null
		"cast":
			return cast_panel
	return null


func _update_hover(at: Vector2) -> void:
	var hit := _hit_test(at) if _armed() else {}
	var key := _hit_key(hit)
	if key == String(_hover.get("key", "")):
		return
	_clear_hover()
	if key == "":
		return
	var node := _hit_node(hit)
	if node == null:
		return
	var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
	_hover = {"key": key, "node": node, "scale": node.scale,
		"border": sb.border_color if sb != null else Color.BLACK,
		"width": sb.border_width_top if sb != null else 0, "sb": sb}
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
	if sb != null:
		sb.border_color = UIKit.GREEN.lightened(0.25)
		sb.set_border_width_all(UIKit.B_FOCUS + 1)
	Sfx.play("button", 0.22)


func _clear_hover() -> void:
	if _hover.is_empty():
		return
	var node: Control = _hover.node
	if is_instance_valid(node):
		node.scale = _hover.scale
		var sb: StyleBoxFlat = _hover.sb
		if sb != null:
			sb.border_color = _hover.border
			sb.set_border_width_all(int(_hover.width))
	_hover = {}


## Which drop zone is under `at`? Enemy dice chips win over their enemy card.
func _hit_test(at: Vector2) -> Dictionary:
	var spec := _drop_spec()
	if bool(spec.enemy_dice):
		for j in enemy_widgets:
			for d in enemy_widgets[j].chips:
				var chip: Control = enemy_widgets[j].chips[d]
				if is_instance_valid(chip) and chip.get_global_rect().has_point(at):
					return {"kind": "enemy_die", "enemy": int(j), "die": int(d)}
	for j in spec.enemies:
		var w = enemy_widgets.get(int(j), null)
		if w != null and is_instance_valid(w.card) and w.card.get_global_rect().has_point(at):
			return {"kind": "enemy", "index": int(j)}
	for i in spec.heroes:
		if int(i) < hero_cards.size() and is_instance_valid(hero_cards[int(i)]) \
				and hero_cards[int(i)].get_global_rect().has_point(at):
			return {"kind": "hero", "index": int(i)}
	for ref in spec.wild:
		var dv = die_widgets.get("%d:%d" % [int(ref.hero), int(ref.die)], null)
		if dv != null and is_instance_valid(dv) and dv.get_global_rect().has_point(at):
			return {"kind": "wild", "hero": int(ref.hero), "die": int(ref.die)}
	if bool(spec.cast) and cast_zone.visible and cast_zone.get_global_rect().has_point(at):
		return {"kind": "cast"}
	return {}


func _resolve_drop(held: Dictionary, hit: Dictionary) -> void:
	var i := int(held.hero)
	var d := int(held.die)
	match String(hit.kind):
		"cast":
			_do_use(i, d, _wild_params({}))
		"hero":
			_do_use(i, d, _wild_params({"target": int(hit.index)}))
		"enemy":
			if not pending_theft.is_empty():
				_do_use(i, d, {"die": pending_theft, "theft_target": int(hit.index)})
			else:
				var fd := _effective_face(i, d)
				if String(fd.get("target", "")) == "enemy_die":
					# dropped on the body rather than a specific intent chip:
					# take that enemy's biggest live die
					var pick := _biggest_die_of(int(hit.index))
					if pick.is_empty():
						Sfx.play("block", 0.5)
						_refresh()
						return
					_stun_with(i, d, fd, pick)
				else:
					_do_use(i, d, _wild_params({"target": int(hit.index)}))
		"enemy_die":
			var fd2 := _effective_face(i, d)
			var ref := {"enemy": int(hit.enemy), "die": int(hit.die)}
			if fd2.get("steal_die", false):
				pending_theft = ref
				sel = {"hero": i, "die": d}
				_refresh()
				return
			_stun_with(i, d, fd2, ref)
		"wild":
			pending_wild_src = {"hero": int(hit.hero), "die": int(hit.die)}
			var copied := bc.die_face(int(hit.hero), int(hit.die))
			if String(copied.get("target", "none")) in ["none", "self"]:
				_do_use(i, d, {"copy_from": pending_wild_src})
			else:
				# the copied face still needs its own target: keep it selected
				sel = {"hero": i, "die": d}
				_refresh()


## The face that will actually resolve (wild resolves as its copy source).
func _effective_face(i: int, d: int) -> Dictionary:
	var fd := bc.die_face(i, d)
	if fd.get("wild", false) and not pending_wild_src.is_empty():
		return bc.die_face(int(pending_wild_src.hero), int(pending_wild_src.die))
	return fd


func _wild_params(params: Dictionary) -> Dictionary:
	if not pending_wild_src.is_empty():
		params["copy_from"] = pending_wild_src
	return params


func _stun_with(i: int, d: int, fd: Dictionary, ref: Dictionary) -> void:
	var params := _wild_params({"die": ref})
	if int(fd.get("stun", 1)) > 1:
		var second := _biggest_die_excluding(ref)
		params["die2"] = second if not second.is_empty() else ref
	_do_use(i, d, params)


func _biggest_die_of(j: int) -> Dictionary:
	var best := {}
	var best_v := -1
	var e: Dictionary = bc.s.enemies[j]
	for d in e.rolls.size():
		var r: Dictionary = e.rolls[d]
		if r.cancelled or r.done:
			continue
		var v := bc._enemy_face_value(e, r.face, "atk") if r.face.has("atk") else 1
		if v > best_v:
			best_v = v
			best = {"enemy": j, "die": d}
	return best


func _biggest_die_excluding(exclude: Dictionary) -> Dictionary:
	var best := {}
	var best_v := -1
	for ref in bc._targetable_dice():
		if ref == exclude:
			continue
		var v := 1
		if int(ref.die) < 0:
			v = 12    # boss announcement
		else:
			var e: Dictionary = bc.s.enemies[int(ref.enemy)]
			var f: Dictionary = e.rolls[int(ref.die)].face
			v = bc._enemy_face_value(e, f, "atk") if f.has("atk") else 1
		if v > best_v:
			best_v = v
			best = ref
	return best


# ============================================================ tap handlers

## A tap on a die only ever selects or deselects it. It never spends it — that
## takes a real drag past `DRAG_ARM`, or tapping the highlighted target the
## selection lit up. A selected die is a question ("where does this go?"), not
## a committed move, so nothing is lost by touching one to look at it.
func _on_die_pressed(i: int, d: int) -> void:
	if bc.s.over:
		return
	var spec := _drop_spec()
	# tapping a highlighted die while a wild is selected picks the copy source —
	# that is choosing a *target*, not using the die being tapped
	for ref in spec.wild:
		if int(ref.hero) == i and int(ref.die) == d:
			_resolve_drop(sel.duplicate(), {"kind": "wild", "hero": i, "die": d})
			return
	if not sel.is_empty() and int(sel.hero) == i and int(sel.die) == d:
		_deselect()
		_refresh()
		return
	if not bc.can_use(i, d).ok:
		Sfx.play("block", 0.5)
		return
	_deselect()
	sel = {"hero": i, "die": d}
	Sfx.play("button")
	_refresh()


## The centre pad is a target like any other: tapping it with a no-target face
## selected resolves that face. Keeps one-handed play possible without the die
## itself ever being a "use" button.
func _on_cast_tapped() -> void:
	if _consume_longpress() or sel.is_empty() or not bool(_drop_spec().cast):
		return
	_resolve_drop(sel.duplicate(), {"kind": "cast"})


func _on_enemy_tapped(j: int) -> void:
	if _consume_longpress() or sel.is_empty():
		return
	_resolve_drop(sel.duplicate(), {"kind": "enemy", "index": j})


func _on_hero_tapped(i: int) -> void:
	if _consume_longpress():
		return
	if pending_potion >= 0:
		var slot := pending_potion
		pending_potion = -1
		var res := bc.use_potion(slot, {"target": i})
		if res.ok:
			Sfx.play("potion")
			_spawn_floats()
		_refresh()
		return
	if sel.is_empty():
		return
	_resolve_drop(sel.duplicate(), {"kind": "hero", "index": i})


func _on_enemy_die_tapped(j: int, d: int) -> void:
	if sel.is_empty():
		return
	_resolve_drop(sel.duplicate(), {"kind": "enemy_die", "enemy": j, "die": d})


func _do_use(i: int, d: int, params: Dictionary) -> void:
	var pre := bc.can_use(i, d)
	var was_atk: bool = pre.get("face", {}).has("atk")
	var base_id := String(_effective_face(i, d).get("id", ""))
	var res := bc.use_face(i, d, params)
	if res.ok:
		Sfx.play("hit" if was_atk else "button")
		Game.mark_face_used(base_id)
	else:
		Sfx.play("block", 0.5)
	_deselect()
	drag = {}
	_clear_ghost()
	_refresh()
	if res.ok:
		_spawn_floats()


func _on_reroll() -> void:
	if bc.reroll():
		Sfx.play("roll")
		_deselect()
		_refresh()
		_spawn_floats()
		_animate_roll()


func _on_undo() -> void:
	if bc.undo():
		Sfx.play("button")
		bc.drain_events()
		_deselect()
		_refresh()


## Ending the turn hands the board to the enemies, and they take it one action
## at a time.
##
## The old version resolved the entire enemy phase inside a single frame and
## then printed the aftermath: four numbers appeared at once and the player had
## no idea which creature had done what. Now each rolled die gets its own beat —
## the acting enemy lights up and lunges, the intent chip it is spending swells
## and flies at whoever it is aimed at, and only then does the damage land.
const STEP_BEAT := 0.30
## The floats and the flight have to finish inside the beat, so they are cut
## from it rather than added to it.
const STEP_FLY := 0.20


func _on_end_turn() -> void:
	if _enemy_turn_running:
		return
	Sfx.play("button")
	_deselect()
	_hide_tooltip()
	_run_enemy_turn()


var _enemy_turn_running := false
## Headless tests and the gallery exporter set this: every beat collapses to
## nothing so a whole battle plays out in a handful of frames. Off in the game.
var instant_anim := false


## Run the enemy phase to completion and return. The End Turn button fires the
## same work and simply does not wait for it; anything that needs the board
## settled before it looks at it (the tests, the screenshot tools) awaits this.
func end_turn_and_wait() -> void:
	if _enemy_turn_running:
		return
	await _run_enemy_turn()


## Beat length, halved by the "fast animation" setting like every other timing
## in the battle screen.
func _beat(t: float) -> float:
	if instant_anim:
		return 0.0
	return t * (0.5 if bool(Game.settings.get("fast_anim", false)) else 1.0)


func _run_enemy_turn() -> void:
	_enemy_turn_running = true
	_set_controls_enabled(false)
	bc.end_turn_begin()
	var guard := 0
	while not bc.s.over and guard < 64:
		guard += 1
		var nxt := bc.peek_enemy_action()
		if nxt.is_empty():
			break
		await _telegraph(nxt)
		if not is_instance_valid(self):
			return
		bc.enemy_step()
		_refresh()
		_spawn_floats()
		await get_tree().create_timer(_beat(STEP_BEAT)).timeout
		if not is_instance_valid(self):
			return
	if not bc.s.over:
		bc.end_turn_finish()
		_refresh()
		_spawn_floats()
	_enemy_turn_running = false
	_set_controls_enabled(true)
	_refresh()
	if not bc.s.over:
		Sfx.play("roll")
		_animate_roll()


## Nothing in the tray may be touched while the enemies are acting — the state
## the buttons act on is changing under them.
func _set_controls_enabled(on: bool) -> void:
	for b in [btn_undo, btn_reroll, btn_end]:
		if is_instance_valid(b):
			b.disabled = not on
	if on:
		_refresh_buttons()


## The half-second before an enemy action lands: the creature brightens and
## leans in, the chip it is spending swells and pulses, then a copy of that
## chip flies at its target and pops. By the time the numbers appear the player
## already knows who is hitting whom.
func _telegraph(nxt: Dictionary) -> void:
	var j := int(nxt.get("enemy", -1))
	var w = enemy_widgets.get(j, null)
	if w == null:
		await get_tree().create_timer(_beat(STEP_BEAT * 0.4)).timeout
		return
	var card: Control = w.get("card", null)
	if is_instance_valid(card):
		var lift := create_tween()
		lift.set_parallel(true)
		lift.tween_property(card, "modulate", Color(1.35, 1.3, 1.2), _beat(0.10))
		lift.tween_property(card, "position:y", card.position.y - 12.0, _beat(0.10)) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var settle := create_tween()
		settle.tween_interval(_beat(0.22))
		settle.tween_property(card, "modulate", Color.WHITE, _beat(0.16))
		settle.parallel().tween_property(card, "position:y", card.position.y, _beat(0.16))
	if is_instance_valid(w.get("art", null)):
		w.art.play_attack()
	# the chip that is about to go off
	var chip: Control = null
	if String(nxt.get("kind", "")) == "die":
		chip = w.get("chips", {}).get(int(nxt.die), null)
	var to := _telegraph_target(nxt)
	if is_instance_valid(chip):
		var pulse := create_tween()
		chip.pivot_offset = chip.size * 0.5
		pulse.tween_property(chip, "scale", Vector2(1.35, 1.35), _beat(0.10)) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse.tween_property(chip, "scale", Vector2.ONE, _beat(0.08))
		await get_tree().create_timer(_beat(0.14)).timeout
		# the pulse's own await is long enough for a rebuild to have freed the
		# chip out from under us
		if not is_instance_valid(self) or not is_instance_valid(chip):
			return
		_fly_chip(chip, to)
	Sfx.play("button", 0.4)
	await get_tree().create_timer(_beat(STEP_FLY)).timeout


## Where the intent is headed, in float-layer space.
func _telegraph_target(nxt: Dictionary) -> Vector2:
	var j := int(nxt.get("enemy", -1))
	if String(nxt.get("kind", "")) == "announce":
		return _anchor_hero.get(0, _fallback_hero(0))
	var e: Dictionary = bc.s.enemies[j]
	var f: Dictionary = e.rolls[int(nxt.die)].face
	var t := bc.forecast_target(f)
	match String(t.kind):
		"aoe":
			# the party as a whole: aim at the middle of the hero row
			var n: int = maxi(bc.s.heroes.size(), 1)
			var mid := Vector2.ZERO
			for i in n:
				mid += _anchor_hero.get(i, _fallback_hero(i))
			return mid / float(n)
		"taunt":
			return _anchor_hero.get(int(t.hero), _fallback_hero(int(t.hero)))
		"self":
			return _anchor_enemy.get(j, _fallback_enemy(j))
	# nobody is forcing it: aim at the middle of the party, same as a sweep
	var mid2 := Vector2.ZERO
	var n2: int = maxi(bc.s.heroes.size(), 1)
	for i2 in n2:
		mid2 += _anchor_hero.get(i2, _fallback_hero(i2))
	return mid2 / float(n2)


## A throwaway copy of the intent chip, flung at the target and popped. The
## real chip stays put and is redrawn as "spent" by the refresh that follows.
func _fly_chip(chip: Control, to: Vector2) -> void:
	var ghost := Panel.new()
	var sb: StyleBoxFlat = chip.get_theme_stylebox("panel")
	if sb != null:
		ghost.add_theme_stylebox_override("panel", sb.duplicate())
	ghost.size = chip.size
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(ghost)
	ghost.position = _to_float_space(chip.get_global_rect().get_center()) - chip.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "position", to - chip.size * 0.5, _beat(STEP_FLY)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", Vector2(0.55, 0.55), _beat(STEP_FLY))
	tw.tween_property(ghost, "modulate:a", 0.0, _beat(STEP_FLY)).set_delay(_beat(STEP_FLY * 0.5))
	tw.chain().tween_callback(ghost.queue_free)


## Throw every die that has a fresh roll. Each one gets its own small delay so
## the table reads as a handful of dice leaving a cup rather than eight
## synchronised flickers, and each lands with its own knock.
func _animate_roll() -> void:
	var fast: bool = bool(Game.settings.get("fast_anim", false))
	var dur := 0.30 if fast else 0.68
	var spread := 0.06 if fast else 0.15
	_land_count = 0
	for key in die_widgets:
		var dv: Die3D = die_widgets[key]
		if not is_instance_valid(dv) or not dv.interactive:
			continue
		if not dv.landed.is_connected(_on_die_landed):
			dv.landed.connect(_on_die_landed)
		dv.throw(dv.shown, randf() * spread, dur)


var _land_count := 0


## One knock per die as it hits, quieter down the line, and a nudge of shake
## for the first few only — eight dice each shaking the screen adds up to an
## earthquake, which is exactly what a die landing should not feel like.
func _on_die_landed() -> void:
	_land_count += 1
	Sfx.play("die", clampf(0.75 - _land_count * 0.06, 0.28, 0.75))
	if _land_count <= 3:
		_shake(2.5)


func _shake(strength := 6.0) -> void:
	var tw := create_tween()
	for k in 3:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(self, "position", off, 0.04)
	tw.tween_property(self, "position", Vector2.ZERO, 0.05)


# ============================================================ feedback

func _spawn_floats() -> void:
	var evs := bc.drain_events()
	var shown := 0
	# two numbers landing on the same target used to print on top of each other
	# ("-1-1"); each extra one for a given target steps down and sideways
	_float_stack.clear()
	for e in evs:
		if shown > 12:
			break
		match String(e.t):
			"hit":
				_float_at_enemy(int(e.enemy), "-%d" % int(e.hp_loss), UIKit.RED)
				if int(e.src) < hero_arts.size() and is_instance_valid(hero_arts[int(e.src)]):
					hero_arts[int(e.src)].play_attack()
				_shake(4.0)
				shown += 1
			"enemy_hit":
				# what the shield ate and what got through are two different
				# facts, and a player who only sees "-0" cannot tell whether
				# their block worked or the attack missed
				var got_through := int(e.dmg) - int(e.blocked)
				if int(e.blocked) > 0:
					_float_at_hero(int(e.hero), UIKit.glyph_n("block", int(e.blocked)),
							UIKit.BLUE.lightened(0.25))
					_flash_hero(int(e.hero), UIKit.BLUE.lightened(0.4))
				if got_through > 0:
					_float_at_hero(int(e.hero), "-%d" % got_through, UIKit.RED)
					_flash_hero(int(e.hero), UIKit.RED)
					_recoil_hero(int(e.hero))
				_shake(6.0 if got_through > 0 else 2.5)
				shown += 1
			"hero_weakened":
				_float_at_hero(int(e.hero), UIKit.glyph("weaken"), UIKit.YELLOW)
				shown += 1
			"hero_bound":
				_float_at_hero(int(e.hero), UIKit.glyph("bind"), UIKit.YELLOW)
				shown += 1
			"steal":
				_float_at_hero(int(e.hero), UIKit.glyph("steal"), UIKit.PURPLE)
				shown += 1
			"die_cancelled":
				_float_at_hero(int(e.hero), UIKit.glyph("cancel"), UIKit.YELLOW)
				shown += 1
			"thorns":
				_float_at_enemy(int(e.enemy), UIKit.glyph_n("thorns", int(e.dmg)),
						UIKit.ORANGE)
				shown += 1
			"heal":
				_float_at_hero(int(e.hero), "+%d" % int(e.amount), UIKit.GREEN)
				shown += 1
			"hero_hp_loss":
				_float_at_hero(int(e.hero), "-%d" % int(e.amount), UIKit.ORANGE)
				shown += 1
			"poison_tick":
				if e.has("enemy"):
					_float_at_enemy(int(e.enemy), UIKit.glyph_n("poison", int(e.dmg)), UIKit.PURPLE)
					shown += 1
			"boss_phase", "boss_unarmored":
				_shake(10.0)
				shown += 1


## A hit reads on the hero, not just in the number above them: the column
## flashes the colour of what happened to it.
func _flash_hero(i: int, tone: Color) -> void:
	if i >= hero_cards.size() or not is_instance_valid(hero_cards[i]):
		return
	var card: Control = hero_cards[i]
	var tw := create_tween()
	tw.tween_property(card, "modulate", tone.lightened(0.35), _beat(0.07))
	tw.tween_property(card, "modulate", Color.WHITE, _beat(0.22))


## …and rocks back from the blow. The column's own position is restored at the
## end, so a rebuild landing mid-tween cannot leave it displaced.
func _recoil_hero(i: int) -> void:
	if i >= hero_cards.size() or not is_instance_valid(hero_cards[i]):
		return
	var card: Control = hero_cards[i]
	var home := card.position
	var tw := create_tween()
	tw.tween_property(card, "position", home + Vector2(0, 9.0), _beat(0.07))
	tw.tween_property(card, "position", home, _beat(0.18)).set_trans(Tween.TRANS_BACK)


## Last known on-screen anchor for each combatant, in canvas space. Kept across
## rebuilds so a number always lands on the thing it happened to.
var _anchor_enemy := {}    # absolute enemy index → Vector2
var _anchor_hero := {}     # hero index → Vector2


## A rect is only trustworthy once the container has actually sorted it.
##
## Careful: a freshly added child of the centred enemy row reports a *partly*
## sensible rect — the row's own y, but x still 0 — which sails past any naive
## "is it non-zero" test and is how a good anchor used to get overwritten with
## a bogus one. So the only place that reads live rects is `_capture_anchors()`,
## and it runs either before a rebuild or deferred until after the sort.
func _laid_out(c: Control) -> bool:
	if not is_instance_valid(c):
		return false
	var r := c.get_global_rect()
	return r.size.x > 1.0 and r.size.y > 1.0 and r.position.x > 0.5 and r.position.y > 0.5


## Card rects come back in canvas space; floats are children of `float_layer`
## and are positioned in its local space. The two agree in the shipping game
## (float_layer is a full-rect child at the origin) but not if the screen is
## ever nested under a transform — the gallery exporter does exactly that — so
## convert rather than assume.
func _to_float_space(p: Vector2) -> Vector2:
	if not is_instance_valid(float_layer):
		return p
	return float_layer.get_global_transform().affine_inverse() * p


func _card_anchor(c: Control, drop: float) -> Vector2:
	var r := c.get_global_rect()
	return _to_float_space(Vector2(r.get_center().x, r.position.y + drop))


func _capture_anchors() -> void:
	for j in enemy_widgets:
		var w = enemy_widgets[j]
		if w != null and w.has("card") and _laid_out(w.card):
			var card: Control = w.card
			_anchor_enemy[int(j)] = _card_anchor(card,
					minf(130.0, card.get_global_rect().size.y * 0.55))
	for i in hero_cards.size():
		if _laid_out(hero_cards[i]):
			_anchor_hero[i] = _card_anchor(hero_cards[i], HERO_FLOAT_DROP)


## Enemy cards are a centred row; heroes are four fixed-width columns. Good
## enough for the very first turn, before anything has been laid out once.
func _fallback_enemy(j: int) -> Vector2:
	var alive: Array = bc._alive_enemies()
	var slot := maxi(alive.find(j), 0)
	var n := maxi(alive.size(), 1)
	return Vector2(360.0 + (slot - (n - 1) * 0.5) * 148.0, 190.0)


func _fallback_hero(i: int) -> Vector2:
	var n: int = maxi(bc.s.heroes.size(), 1)
	return Vector2(360.0 + (i - (n - 1) * 0.5) * (HERO_COL_W + 4.0),
			ZONE_HERO_TOP + HERO_FLOAT_DROP)


func _float_at_enemy(j: int, text: String, color: Color) -> void:
	_float_text(_anchor_enemy.get(j, _fallback_enemy(j)) + _stack_offset("e%d" % j), text, color)


func _float_at_hero(i: int, text: String, color: Color) -> void:
	_float_text(_anchor_hero.get(i, _fallback_hero(i)) + _stack_offset("h%d" % i), text, color)


var _float_stack := {}    # target key → how many numbers already went up there


## Nth number on the same target this batch steps down and alternates sideways,
## so a multi-hit turn reads as a column of hits instead of one smear.
func _stack_offset(key: String) -> Vector2:
	var n := int(_float_stack.get(key, 0))
	_float_stack[key] = n + 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(18.0 * (1 if n % 2 == 1 else -1), 26.0 * n)


## Pooled floating damage/heal numbers (object pooling per spec).
func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var l: Label = null
	if not _float_pool.is_empty():
		l = _float_pool.pop_back()
	if l == null or not is_instance_valid(l):
		l = UIKit.label("", 34, color)
		l.add_theme_color_override("font_outline_color", UIKit.OUTLINE)
		l.add_theme_constant_override("outline_size", 8)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(120, 0)
		l.size = Vector2(120, 44)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		float_layer.add_child(l)
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.visible = true
	l.modulate.a = 1.0
	l.position = pos + Vector2(-60.0 + randf_range(-6, 6), -22.0)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tw.tween_callback(func() -> void:
		if is_instance_valid(l):
			l.visible = false
			_float_pool.append(l))


func _show_result() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 24)
	overlay.add_child(vb)
	var msg := Data.t("ui_victory") if bc.s.victory else Data.t("ui_defeat")
	var l := UIKit.label(msg, 60, UIKit.CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	Sfx.play("win" if bc.s.victory else "lose")
	var center := CenterContainer.new()
	vb.add_child(center)
	var b := UIKit.button(Data.t("ui_confirm"), UIKit.CREAM, 28, Vector2(260, 80))
	b.pressed.connect(_on_result_confirm)
	center.add_child(b)


func _on_result_confirm() -> void:
	Sfx.play("button")
	if args.get("in_run", false):
		Game.on_battle_finished(bc, String(args.get("kind", "battle")))
	elif args.has("on_finish"):
		var cb: Callable = args.on_finish
		cb.call(bc)
	else:
		Game.goto(String(args.get("return", "menu")))


# ============================================================ tutorial

const TUTORIAL_STEPS := [
	["歡迎!上方是敵人,他們本回合擲出的骰面意圖已經顯示在敵人卡上。長按任何一隻敵人,可以看到牠這回合每一顆骰子的完整預告。",
	 "Welcome! Enemies are on top — their rolled intents are already shown on their cards. Press and hold any enemy for a full breakdown of every die it has rolled this turn."],
	["下方每位隊員有兩顆骰子(A 骰與 B 骰),骰子下面寫著擲出的面名。紅=攻擊、藍=格擋、綠=治療、紫=資源、黃=控場。",
	 "Each hero below has two dice (A and B); the rolled face's name is under each. Red=attack, blue=block, green=heal, purple=resource, yellow=control."],
	["使用骰子只有一個方法:按住它,拖到目標上放手。拖到敵人=攻擊、拖到隊友=治療、拖到自己=自身效果、沒有目標的則拖到中央施放區。點一下骰子只是選取,不會使用它;拖得不夠遠(少於半顆骰子的距離)放手也會取消,所以不會誤觸。",
	 "There is exactly one way to spend a die: hold it and drag it onto its target. Enemy to attack, ally to heal, yourself for self-buffs, centre pad for no-target faces. A tap only selects — it never spends — and letting go before the die has really left its slot cancels, so you cannot fumble one away."],
	["看不懂某個詞?長按任何骰子、狀態圖示或敵人意圖,就會彈出詳情卡,寫明它的作用以及每個名詞的解釋。詳情卡裡的骰子還可以用手指撥動,檢視六個面。",
	 "Not sure what something means? Press and hold any die, status badge or enemy intent to open its detail card — what it does, and every term it uses spelled out. You can spin the die in that card to see all six faces."],
	["每位英雄每回合只能行動一次——使用了一顆骰子,另一顆即時鎖住,下回合才恢復。",
	 "Each hero acts once per turn — spending one die locks the other until next turn."],
	["頂端的藍色長條是靈息:向森林借來的力量,全隊共用,只有靈術面會消耗它。隊伍若完全沒有靈息相關的骰面,這條就不會顯示。",
	 "The blue meter at the top is Essence — power borrowed from the forest, shared by the whole party, and spent only by Ritual faces. It stays hidden for a party with no Essence faces at all."],
	["本作沒有基礎重擲,重擲要靠遺物、藥水和骰面。左上角是你已取得的遺物,長按可以查看。用錯了可以「復原」。準備好就按「結束回合」。",
	 "There are no free rerolls: they come from relics, potions and faces. Your relics sit in the strip at the top left — hold one to read them. Use Undo to take a move back, then End Turn when you are ready."],
]

var _tut_overlay: Control = null


func _show_tutorial(step: int) -> void:
	if is_instance_valid(_tut_overlay):
		_tut_overlay.queue_free()
		_tut_overlay = null
	if step >= TUTORIAL_STEPS.size():
		Game.settings.tutorial_done = true
		Game.save_settings()
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := UIKit.panel(UIKit.CREAM, 16, 4)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_top = 430
	panel.offset_left = -330
	panel.offset_right = 330
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	var l := UIKit.label(Data.bi(TUTORIAL_STEPS[step][0], TUTORIAL_STEPS[step][1]), 21, UIKit.OUTLINE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	pv.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var next_txt := Data.bi("下一步 (%d/%d)" % [step + 1, TUTORIAL_STEPS.size()],
			"Next (%d/%d)" % [step + 1, TUTORIAL_STEPS.size()])
	var next_b := UIKit.button(next_txt, UIKit.GREEN.lightened(0.3), 20, Vector2(220, 60))
	next_b.pressed.connect(func() -> void:
		Sfx.play("button")
		_show_tutorial(step + 1))
	row.add_child(next_b)
	var skip_b := UIKit.button(Data.t("ui_skip"), UIKit.CREAM_DARK, 20, Vector2(150, 60))
	skip_b.pressed.connect(func() -> void:
		Sfx.play("button")
		_show_tutorial(TUTORIAL_STEPS.size()))
	row.add_child(skip_b)
	pv.add_child(row)
	root.add_child(panel)
	add_child(root)
	_tut_overlay = root


# ============================================================ tooltips

## Attach a 0.5s long-press to any Control (works with Buttons via gui_input).
##
## A Control emits `gui_input` before it handles the event itself, so on a
## Button the release reaches this handler first and `_lp_fired` is already set
## by the time `pressed` goes off. Tap handlers call `_consume_longpress()` so
## holding an enemy card to read its forecast does not ALSO throw a die at it.
func _attach_longpress(ctrl: Control, cb: Callable) -> void:
	ctrl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			var pressed: bool = ev.pressed
			if pressed:
				var t := get_tree().create_timer(0.5)
				_lp_timer = t
				t.timeout.connect(func() -> void:
					if _lp_timer == t:
						_lp_fired = true
						cb.call())
			else:
				_lp_timer = null)


var _lp_fired := false


## True when the tap now ending was really a long press. Clears the flag.
func _consume_longpress() -> bool:
	if not _lp_fired:
		return false
	_lp_fired = false
	return true


func _show_tooltip(text: String) -> void:
	_hide_tooltip()
	var dim := Button.new()
	dim.flat = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.pressed.connect(_hide_tooltip)
	var panel := UIKit.panel(UIKit.CREAM, 16, 4)
	var l := UIKit.label(text, 22, UIKit.OUTLINE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	panel.add_child(l)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	root.add_child(panel)
	add_child(root)
	_tooltip = root


func _hide_tooltip() -> void:
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = null


func _hero_tooltip(i: int) -> String:
	var h: Dictionary = bc.s.heroes[i]
	var def: Dictionary = GameData.heroes[h.id]
	var lines := [Data.bi(String(def.zh), String(def.en))]
	lines.append("HP %d/%d" % [h.hp, h.max_hp])
	lines.append(Data.bi(String(def.passive_zh), String(def.passive_en)))
	var st := _status_text(h)
	if st != "":
		lines.append(st)
	if h.used:
		lines.append(Data.bi("本回合已行動", "Has already acted this turn"))
		if bc.twin_available(i):
			lines.append(Data.bi("雙月徽記:本回合仍可再使用一顆骰子",
					"Twin Moon Seal: may still spend a second die this turn"))
	return "\n".join(lines)


## Hold an enemy for the full read on it: who it is, what is keeping it alive,
## and — the part the fight actually turns on — every die it has already rolled
## spelled out as a sentence, with the numbers it will really hit for and the
## hero it will really hit. No mental arithmetic, no "roughly 6".
func _show_enemy_card(j: int) -> void:
	_hide_tooltip()
	_tooltip = DetailCard.show_rows(self, _enemy_rows(j))


func _enemy_rows(j: int) -> Array:
	var e: Dictionary = bc.s.enemies[j]
	var W := DetailCard.PANEL_W - 8.0
	var rows := []

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.S3)
	head.add_child(UIKit.text_block(Data.bi(String(e.zh), String(e.en)), UIKit.F_H2,
			UITheme.INK, 0.0, HORIZONTAL_ALIGNMENT_LEFT))
	head.add_child(UIKit.chip("HP %d/%d" % [int(e.hp), int(e.max_hp)], UIKit.RED,
			UIKit.F_CAPTION, UIKit.S2))
	if String(e.kind) == "boss":
		head.add_child(UIKit.chip(Data.bi("首領", "BOSS"), UIKit.RED, UIKit.F_CAPTION, UIKit.S2))
	rows.append(head)

	# Every line from here down is sentence-length, so the two languages stack
	# rather than running together with a space in the middle of them.
	if String(e.kind) == "boss":
		var bdef: Dictionary = GameData.bosses[e.boss_key]
		rows.append(UIKit.text_block(Data.bi2("機制:%s" % bdef.gimmick_zh,
				"Gimmick: %s" % bdef.gimmick_en),
				UIKit.F_BODY_SM, UITheme.INK, W, HORIZONTAL_ALIGNMENT_LEFT))
	if not e.passive.is_empty():
		var pt := String(e.passive.get("type", ""))
		var zh_p := ""
		var en_p := ""
		if pt == "start_block":
			zh_p = "每回合開始時獲得格擋"
			en_p = "gains Block at the start of each turn"
		elif pt == "thorns":
			zh_p = "荊棘 — 攻擊它會受到反傷"
			en_p = "Thorns — attacking it deals damage back to you"
		if zh_p != "":
			rows.append(UIKit.text_block(Data.bi2("被動:%s" % zh_p, "Passive: %s" % en_p),
					UIKit.F_BODY_SM, UITheme.INK, W, HORIZONTAL_ALIGNMENT_LEFT))
	if String(e.affix) != "":
		var af: Dictionary = GameData.encounters.elite_affixes[e.affix]
		rows.append(UIKit.text_block(Data.bi2("精英詞綴:%s" % af.zh,
				"Elite affix: %s" % af.en),
				UIKit.F_BODY_SM, UITheme.INK, W, HORIZONTAL_ALIGNMENT_LEFT))
	var st := _status_chips(e, UIKit.F_CAPTION)
	if st != null:
		rows.append(st)

	# --- this turn's dice, one sentence each
	rows.append(DetailCard._rule())
	rows.append(UIKit.text_block(Data.t("ui_actions_this_turn"), UIKit.F_BODY,
			UITheme.INK_SOFT, W, HORIZONTAL_ALIGNMENT_LEFT))
	var terms := {}
	var plan := bc.forecast_enemy(j)
	if plan.is_empty():
		rows.append(UIKit.text_block(Data.bi("這回合沒有行動。", "Nothing this turn."),
				UIKit.F_BODY_SM, UITheme.INK_SOFT, W, HORIZONTAL_ALIGNMENT_LEFT))
	for row in plan:
		rows.append(_enemy_action_row(e, row, W))
		for key in _intent_terms(e, row.face):
			terms[String(key[0])] = true

	# --- the announced attack every boss counts down to
	var fc := bc.boss_forecast(e)
	if not fc.is_empty():
		var when_zh := "本回合結束時發動" if int(fc.turns) == 0 \
				else "還有 %d 回合" % int(fc.turns)
		var when_en := "fires at the end of this turn" if int(fc.turns) == 0 \
				else "in %d turn(s)" % int(fc.turns)
		rows.append(DetailCard._rule())
		rows.append(UIKit.text_block(Data.bi2(
				"預告行動:%s(%d 點 ×%d)— %s" % [fc.zh, int(fc.dmg), int(fc.hits), when_zh],
				"Announced: %s (%d damage ×%d) — %s"
						% [fc.en, int(fc.dmg), int(fc.hits), when_en]),
				UIKit.F_BODY_SM, UITheme.deepen(UIKit.RED), W, HORIZONTAL_ALIGNMENT_LEFT))

	# --- and every keyword those sentences leaned on
	var keys := []
	for k in terms:
		if Glossary.has(String(k)) and String(k) != "blank":
			keys.append(String(k))
	if not keys.is_empty():
		rows.append(DetailCard._rule())
		rows.append(UIKit.text_block(Data.bi("名詞解釋", "Glossary"), UIKit.F_BODY_SM,
				UITheme.INK_SOFT, W, HORIZONTAL_ALIGNMENT_LEFT))
		for k2 in keys:
			rows.append(DetailCard.term_row(k2))
	return rows


## One rolled enemy die as a row: its icon, the sentence, and — once it has
## gone off or been stunned away — struck through in grey so the player can see
## what has already happened this turn as well as what is still coming.
func _enemy_action_row(e: Dictionary, plan: Dictionary, width: float) -> Control:
	var f: Dictionary = plan.face
	var head_key := String(_intent_terms(e, f)[0][0])
	var spent: bool = bool(plan.done) or bool(plan.cancelled)
	var hue: Color = Glossary.hue(head_key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.S3)
	var badge := UIKit.icon_chip(Glossary.glyph_key(head_key), "", hue,
			UIKit.F_BODY_SM, UIKit.S2)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	# the state suffix is appended per language, before the two are stacked —
	# tacked on after the join it would land on the English line only
	var said := _enemy_action_sentence(e, plan)
	if bool(plan.cancelled):
		said.zh += "(已取消)"
		said.en += " (cancelled)"
	elif bool(plan.done):
		said.zh += "(已執行)"
		said.en += " (resolved)"
	col.add_child(UIKit.text_block(Data.bi2(said.zh, said.en), UIKit.F_BODY_SM,
			UITheme.INK_SOFT if spent else UITheme.INK, width - 64.0,
			HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(col)
	if spent:
		row.modulate = Color(1, 1, 1, 0.62)
	return row


## "對嘲諷者 Ember 造成 6 點傷害,並使目標中毒 2 層" — the real number after
## every modifier, and the hero it is actually aimed at.
func _enemy_action_sentence(e: Dictionary, plan: Dictionary) -> Dictionary:
	var f: Dictionary = plan.face
	var tgt: Dictionary = plan.target
	var zh := []
	var en := []
	var who_zh := ""
	var who_en := ""
	match String(tgt.kind):
		"aoe":
			who_zh = "全隊"
			who_en = "the whole party"
		"taunt":
			var nm := String(GameData.heroes[bc.s.heroes[int(tgt.hero)].id].short)
			who_zh = "嘲諷者 %s" % nm
			who_en = "the taunting %s" % nm
		_:
			who_zh = "隨機一位英雄"
			who_en = "a random hero"
	if plan.has("atk"):
		zh.append("對%s造成 %d 點傷害" % [who_zh, int(plan.atk)])
		en.append("Deals %d damage to %s" % [int(plan.atk), who_en])
		if f.get("pierce", false):
			zh.append("無視格擋")
			en.append("ignoring Block")
	if plan.has("block"):
		zh.append("自身獲得 %d 點格擋" % int(plan.block))
		en.append("Gains %d Block" % int(plan.block))
	if plan.has("heal"):
		zh.append("自身回復 %d 點 HP" % int(plan.heal))
		en.append("Heals itself for %d HP" % int(plan.heal))
	if f.has("poison"):
		zh.append("使%s中毒 %d 層" % [who_zh, int(f.poison)])
		en.append("inflicts Poison %d on %s" % [int(f.poison), who_en])
	if f.has("burn"):
		zh.append("使%s灼燒 %d 點" % [who_zh, int(f.burn)])
		en.append("inflicts Burn %d on %s" % [int(f.burn), who_en])
	if f.has("weaken"):
		zh.append("使%s弱化 %d" % [who_zh, int(f.weaken)])
		en.append("inflicts Weaken %d on %s" % [int(f.weaken), who_en])
	if f.get("expose", false):
		zh.append("使%s易傷" % who_zh)
		en.append("inflicts Expose on %s" % who_en)
	if f.has("bind"):
		zh.append("束縛%s,使其下回合無法重擲" % who_zh)
		en.append("Binds %s — no reroll next turn" % who_en)
	if f.has("charge"):
		zh.append("蓄力 %d,下次攻擊會強得多" % int(f.charge))
		en.append("Charges %d — its next attack hits far harder" % int(f.charge))
	if f.has("counter"):
		zh.append("擺出反擊姿態:本回合攻擊它會受到 %d 點反傷" % int(f.counter))
		en.append("Braces to counter — attacking it costs you %d damage" % int(f.counter))
	if f.has("mana_drain"):
		zh.append("抽走隊伍 %d 點靈息" % int(f.mana_drain))
		en.append("Drains %d Essence from the party" % int(f.mana_drain))
	if f.has("cancel_die"):
		zh.append("取消一位英雄已擲的骰子")
		en.append("Cancels one hero's rolled die")
	if f.has("curse"):
		zh.append("使一個骰面在本場戰鬥變成空白")
		en.append("Blanks one of your die faces for this battle")
	if f.has("howl"):
		zh.append("嚎叫,強化敵方全體的攻擊")
		en.append("Howls, strengthening every enemy's attacks")
	if f.has("summon"):
		zh.append("召喚一隻新的小怪")
		en.append("Summons another minion")
	if zh.is_empty():
		zh.append("沒有動作")
		en.append("Does nothing")
	return {"zh": "%s。" % ",並".join(zh), "en": "%s." % ", ".join(en)}
