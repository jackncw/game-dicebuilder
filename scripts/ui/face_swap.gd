class_name FaceSwap
extends RefCounted
## The one screen for putting a new face on a die — used by post-battle rewards,
## the shop, treasure chests and level-up unlocks alike.
##
## The old version was a wall of text with no sense of a die being changed, no
## character names, and no way to look at anyone else's dice. This one is built
## around the physical objects: the incoming face is shown large as a tile, the
## twelve faces the character already has are two rows of tiles with a small 3D
## die beside each, and committing the swap plays out — the old tile is thrown
## clear, the new one drops into its slot, the die spins and flashes.
##
## The party row along the bottom is browsable. Only the character the offer is
## bound to can actually be changed; tapping any of the others opens their dice
## read-only, clearly marked, because "what have my other three got?" is the
## question you need answered before you decide.

const TILE := 92.0
const PANEL_TOP := 52.0
## The bottom tray holds the prompt, the party row and the confirm bar. They
## share one container so they cannot land on top of each other.
const TRAY_H := 296.0


## `hero_i` is the character the offer is bound to (-1 to let the player pick
## any of them). `incoming` is the face id being installed, "" when forging.
## `filter` optionally restricts which of the 12 slots may be chosen.
## Calls `cb(hero_i, slot)` once the swap is confirmed and the animation ends.
## `view_only` opens the same screen with nothing selectable — the reward and
## shop screens use it for "let me look at what this character already has"
## before committing to anything.
static func open(parent: Control, hero_i: int, incoming: String, title: String,
		cb: Callable, filter := Callable(), view_only := false) -> Control:
	var screen := _Screen.new()
	screen.bound_hero = hero_i
	screen.viewing = maxi(hero_i, 0)
	screen.incoming = incoming
	screen.title_text = title
	screen.on_confirm = cb
	screen.filter = filter
	screen.view_only = view_only
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(screen)
	return screen


class _Screen:
	extends Control

	var bound_hero := 0
	var viewing := 0
	var incoming := ""
	var title_text := ""
	var on_confirm := Callable()
	var filter := Callable()
	var view_only := false

	var chosen := -1
	var _tiles := {}          # slot → FaceTile
	var _dice := {}           # die index → Die3D
	var _confirm: Button
	var _prompt: Label
	var _body: VBoxContainer
	var _busy := false        # an animation owns the screen

	func _ready() -> void:
		var scrim := ColorRect.new()
		# fully opaque: at 0.97 the screen underneath ghosted through and its
		# text collided with this one's
		scrim.color = Color(0.05, 0.06, 0.05)
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(scrim)
		_build()

	func _game() -> Node:
		return (Engine.get_main_loop() as SceneTree).root.get_node("/root/Game")

	func _hero(i: int) -> Dictionary:
		return _game().run.team[i]

	## Faces of `die` for the character being looked at, resolved the same way
	## BattleCore resolves them so forge marks and Growth show up here too.
	func _faces(i: int, die: int) -> Array:
		var hero := _hero(i)
		var out := []
		for k in GameData.FACES_PER_DIE:
			out.append(_face(hero, die * GameData.FACES_PER_DIE + k))
		return out

	func _face(hero: Dictionary, slot: int) -> Dictionary:
		var fd: Dictionary = GameData.faces[String(hero.faces[slot])].duplicate(true)
		fd["id"] = String(hero.faces[slot])
		fd["slot"] = slot
		fd["plus"] = int(hero.face_plus[slot])
		var mod := int(hero.face_mods[slot])
		fd["mod"] = mod
		if mod != 0:
			for k in ["atk", "block", "heal", "mana"]:
				if fd.has(k):
					fd[k] = int(fd[k]) + mod
					break
		return fd

	## A reward offer is bound to one character; a shop purchase or a forge is
	## not, and may be spent on anyone (bound_hero = -1).
	func _editable() -> bool:
		return not view_only and (bound_hero < 0 or viewing == bound_hero)

	# ------------------------------------------------------------ layout

	func _build() -> void:
		for c in get_children():
			if c is ColorRect:
				continue
			c.queue_free()
		_tiles = {}
		_dice = {}
		chosen = -1

		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.offset_top = PANEL_TOP
		scroll.offset_left = UITheme.S3
		scroll.offset_right = -UITheme.S3
		scroll.offset_bottom = -TRAY_H
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# same finger contract as the codex: scroll from anywhere, tap = choose
		scroll.scroll_deadzone = UIKit.SCROLL_DEADZONE
		add_child(scroll)
		_body = VBoxContainer.new()
		_body.add_theme_constant_override("separation", UITheme.S3)
		_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_body)

		_body.add_child(UIKit.text_block(title_text, UITheme.F_H2, UITheme.CREAM, 660.0))
		if incoming != "":
			_body.add_child(_incoming_block())
		_body.add_child(_who_block())
		for die in GameData.DICE_PER_HERO:
			_body.add_child(_die_block(die))
		UIKit.scroll_passthrough(_body)

		add_child(_tray())

	## The face being offered, shown big — this is the thing the player is
	## deciding about, so it gets the largest tile on the screen.
	func _incoming_block() -> Control:
		var fd: Dictionary = GameData.faces[incoming].duplicate(true)
		fd["id"] = incoming
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.S4)
		var tile := FaceTile.new(fd, 128.0, true)
		tile.long_pressed.connect(func() -> void: DetailCard.show_face(self, fd))
		row.add_child(tile)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UITheme.S1)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_child(UIKit.text_block(Data.face_name(fd), UITheme.F_BODY,
				UITheme.cat_text(String(fd.get("cat", "special"))), 420.0,
				HORIZONTAL_ALIGNMENT_LEFT))
		col.add_child(UIKit.text_block(Glossary.effect_sentence(fd), UITheme.F_CAPTION,
				UITheme.CREAM_DARK, 420.0, HORIZONTAL_ALIGNMENT_LEFT))
		col.add_child(UIKit.text_block(Data.t("ui_hold_for_details"),
				UITheme.F_MICRO, UITheme.CREAM_DARK, 420.0, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(col)
		var card := UIKit.card(1, UITheme.R_LG, UITheme.B_STRONG,
				UITheme.cat_color(String(fd.get("cat", "special"))), UITheme.S3)
		card.add_child(row)
		return card

	## Who am I looking at, and may I change them?
	func _who_block() -> Control:
		var hero := _hero(viewing)
		var def: Dictionary = GameData.heroes[hero.id]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.S3)
		row.add_child(UIKit.text_block(Data.bi(String(def.zh), String(def.en)),
				UITheme.F_H2, UITheme.CREAM, 0.0))
		if _editable():
			row.add_child(UIKit.chip(Data.t("ui_faceswap"), UITheme.GREEN, UITheme.F_CAPTION))
		else:
			row.add_child(UIKit.chip(Data.t("ui_view_only"), UITheme.YELLOW, UITheme.F_CAPTION))
		return row

	## One die: a small 3D copy of it, then its six faces as tiles.
	func _die_block(die: int) -> Control:
		var hero := _hero(viewing)
		var def: Dictionary = GameData.heroes[hero.id]
		var faces := _faces(viewing, die)
		var card := UIKit.card(1, UITheme.R_LG, UITheme.B_STRONG, UITheme.OUTLINE, UITheme.S3)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UITheme.S2)
		card.add_child(col)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITheme.S3)
		var d3 := Die3D.new(Vector2(64, 64))
		d3.interactive = false
		d3.set_die(faces, 0)
		_dice[die] = d3
		head.add_child(d3)
		var name_zh: String = def.get("die_a_zh", "") if die == 0 else def.get("die_b_zh", "")
		var name_en: String = def.get("die_a_en", "") if die == 0 else def.get("die_b_en", "")
		head.add_child(UIKit.text_block("%s  %s" % [
				Data.t("ui_die_a" if die == 0 else "ui_die_b"), Data.bi(name_zh, name_en)],
				UITheme.F_BODY, UITheme.YELLOW.lightened(0.3), 0.0))
		col.add_child(head)

		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", UITheme.S1)
		grid.add_theme_constant_override("v_separation", UITheme.S2)
		var allowed: Array = filter.call(hero) if filter.is_valid() else range(GameData.SLOTS)
		for k in GameData.FACES_PER_DIE:
			var slot: int = die * GameData.FACES_PER_DIE + k
			var fd: Dictionary = faces[k]
			var tile := FaceTile.new(fd, TILE, true)
			var s: int = slot
			tile.long_pressed.connect(func() -> void: DetailCard.show_face(self, fd))
			if _editable() and (slot in allowed):
				tile.pressed.connect(func() -> void: _pick(s))
			else:
				tile.dimmed = not _editable()
				tile.pressed.connect(func() -> void: DetailCard.show_face(self, fd))
			_tiles[slot] = tile
			grid.add_child(tile)
		var gc := CenterContainer.new()
		gc.add_child(grid)
		col.add_child(gc)
		return card

	## The bottom tray: what the swap will do, everyone's portraits, and the
	## confirm bar — stacked in one container so nothing overlaps.
	func _tray() -> Control:
		var tray := UIKit.footer(1, TRAY_H)
		var v: VBoxContainer = tray.get_child(0)
		v.add_theme_constant_override("separation", UITheme.S2)
		_prompt = UIKit.label(Data.t("ui_hold_for_details") if view_only 				else Data.bi("選擇一個要被換走的面", "Pick a face to replace"),
				UITheme.F_BODY_SM, UITheme.CREAM)
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_prompt.custom_minimum_size = Vector2(660, 34)
		v.add_child(_prompt)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.S1)
		var team: Array = _game().run.team
		for i in team.size():
			row.add_child(_party_button(i))
		v.add_child(row)
		v.add_child(_confirm_bar())
		return tray

	func _party_button(i: int) -> Control:
		var hero: Dictionary = _game().run.team[i]
		var def: Dictionary = GameData.heroes[hero.id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(172, 116)
		b.clip_contents = true
		var active: bool = i == viewing
		var hue: Color = UITheme.GREEN.lightened(0.3) if (bound_hero < 0 or i == bound_hero) \
				else UITheme.CREAM
		var box := UIKit.card_box(UITheme.surface(1), UITheme.R_MD, UITheme.B_STRONG,
				UITheme.YELLOW if active else UITheme.OUTLINE, UITheme.S1)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", box)
		b.add_theme_stylebox_override("pressed", box)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2(160, 68)
		art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art := PawnArt.fitted(String(hero.id), Vector2(160, 64.0))
		art.position = Vector2(80, 66)
		art_holder.add_child(art)
		col.add_child(art_holder)
		# the name, in the player's language mode — the old picker showed none,
		# which made "whose dice am I looking at" a guessing game. Bilingual mode
		# stacks the two names rather than running them together.
		var nm_text: String = Data.bi(String(def.zh), String(def.en))
		if Data.lang_mode() == "both":
			nm_text = "%s\n%s" % [def.zh, def.en]
		var nm := UIKit.label(nm_text, UITheme.F_MICRO, hue)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(160, 44)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		b.add_child(col)
		var idx: int = i
		b.pressed.connect(func() -> void:
			if _busy:
				return
			Sfx.play("button")
			viewing = idx
			_build())
		return b

	func _confirm_bar() -> Control:
		var bar := HBoxContainer.new()
		bar.alignment = BoxContainer.ALIGNMENT_CENTER
		bar.add_theme_constant_override("separation", UITheme.S4)
		_confirm = UIKit.button(Data.t("ui_confirm_swap"), UITheme.GREEN.lightened(0.3),
				UITheme.F_BODY, Vector2(240, 62))
		_confirm.disabled = true
		_confirm.pressed.connect(_commit)
		if not view_only:
			bar.add_child(_confirm)
		var cancel := UIKit.button(Data.t("ui_back") if view_only else Data.t("ui_cancel"),
				UITheme.CREAM_DARK, UITheme.F_BODY, Vector2(180, 62))
		cancel.pressed.connect(func() -> void:
			if not _busy:
				queue_free())
		bar.add_child(cancel)
		return bar

	# ------------------------------------------------------------ choosing

	func _pick(slot: int) -> void:
		if _busy:
			return
		Sfx.play("button")
		chosen = slot
		for s in _tiles:
			var t: FaceTile = _tiles[s]
			t.set_flags(int(s) == slot, t.dimmed)
		var old := _face(_hero(viewing), slot)
		if incoming == "":
			# same rule as the detail card's "擲出" line: the label is bilingual,
			# the already-bilingual face name is printed exactly once
			_prompt.text = "%s → %s" % [Data.face_name(old),
					Data.bi("數值 +1", "value +1")]
		else:
			var new_fd: Dictionary = GameData.faces[incoming]
			_prompt.text = "%s  ⇒  %s" % [Data.face_name(old), Data.face_name(new_fd)]
		_confirm.disabled = false

	# ------------------------------------------------------------ the swap

	## Old tile is flung off the die, the new one drops into the slot it left,
	## and the die spins and flashes. Only after that does the caller's callback
	## fire, so the player sees which face changed before the screen moves on.
	func _commit() -> void:
		if chosen < 0 or _busy:
			return
		_busy = true
		_confirm.disabled = true
		var slot: int = chosen
		var die: int = GameData.die_of_slot(slot)
		var old_tile: FaceTile = _tiles[slot]
		var origin: Vector2 = old_tile.global_position

		# --- old face thrown clear
		var fly_out := create_tween()
		fly_out.set_parallel(true)
		fly_out.tween_property(old_tile, "position",
				old_tile.position + Vector2(randf_range(-90, 90), -220), 0.26) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		fly_out.tween_property(old_tile, "rotation", randf_range(-1.2, 1.2), 0.26)
		fly_out.tween_property(old_tile, "modulate:a", 0.0, 0.26)
		Sfx.play("block", 0.6)
		await get_tree().create_timer(0.24).timeout
		if not is_instance_valid(self):
			return

		# --- new face flies in and seats itself
		var new_fd: Dictionary = {}
		if incoming != "":
			new_fd = GameData.faces[incoming].duplicate(true)
			new_fd["id"] = incoming
		else:
			new_fd = _face(_hero(viewing), slot)
			for k in ["atk", "block", "heal", "mana"]:
				if new_fd.has(k):
					new_fd[k] = int(new_fd[k]) + 1
					break
			new_fd["plus"] = int(new_fd.get("plus", 0)) + 1
		var flyer := FaceTile.new(new_fd, TILE, true)
		flyer.interactive = false
		add_child(flyer)
		flyer.global_position = origin + Vector2(0, 260)
		flyer.modulate.a = 0.0
		flyer.scale = Vector2(1.5, 1.5)
		var fly_in := create_tween()
		fly_in.set_parallel(true)
		fly_in.tween_property(flyer, "global_position", origin, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		fly_in.tween_property(flyer, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
		fly_in.tween_property(flyer, "modulate:a", 1.0, 0.16)
		await get_tree().create_timer(0.3).timeout
		if not is_instance_valid(self):
			return

		# --- the die takes the new face: a fast spin and a flash
		var d3: Die3D = _dice.get(die, null)
		if is_instance_valid(d3):
			var faces := _faces(viewing, die)
			faces[slot % GameData.FACES_PER_DIE] = new_fd
			d3.set_die(faces, slot % GameData.FACES_PER_DIE)
			d3.throw(slot % GameData.FACES_PER_DIE, 0.0, 0.4)
			var flash := create_tween()
			flash.tween_property(d3, "modulate", Color(2.2, 2.2, 2.2), 0.08)
			flash.tween_property(d3, "modulate", Color.WHITE, 0.28)
		Sfx.play("levelup")
		_prompt.text = "%s — %s" % [Data.t("ui_swap_done"), Data.face_name(new_fd)]
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return
		var hero_i := viewing
		var cb := on_confirm
		queue_free()
		if cb.is_valid():
			cb.call(hero_i, slot)
