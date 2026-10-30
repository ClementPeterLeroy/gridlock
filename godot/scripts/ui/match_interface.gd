extends CanvasLayer
## Compact HUD and modal pages. Emits intent; it never changes match state.

signal action_requested(action: String)
signal volume_changed(category: String, value: float)
signal animations_changed(enabled: bool)
signal camera_transitions_changed(enabled: bool)
signal camera_view_changed(view: String)
signal display_changed(field: String, value)
signal transition_started
signal transition_finished

const COLORS = [Color("#345B9A"), Color("#A84343"), Color("#3E7955"), Color("#78529A")]
const GOLD = Color("#F9D55E")
const ART_NAMES = ["sapphire", "crimson", "emerald", "violet"]
const CONTROL_OPTIONS = ["Human", "AI - Casual", "AI - Challenging"]
const Config = preload("res://scripts/core/match_config.gd")
const TURN_LIMITS = Config.TURN_SECONDS
const BLITZ_MINUTES = [1, 3, 5]

class WallIcon extends Control:
	func _draw() -> void:
		draw_rect(Rect2(0, 3, 14, 9), Color("#D6C3A4"))
		draw_line(Vector2(7, 3), Vector2(7, 12), Color("#71553B"), 1.0)

var hud: Control
var hamburger: Button
var menu: PanelContainer
var pause_button: Button
var cards_container: GridContainer
var cards: Dictionary = {}
var overlay: ColorRect
var page_panel: PanelContainer
var page = "main_menu"
var feedback: Label
var setup_config = Config.for_mode("Versus")
var setup_mode: String:
	get: return setup_config.mode
var setup_controllers: Array:
	get: return setup_config.controllers
	set(value): setup_config.controllers = value
var controller_options: Dictionary = {}
var setup_turn_limit: int:
	get: return setup_config.turn_limit
	set(value): setup_config.turn_limit = value
var setup_blitz_minutes: int:
	get: return setup_config.blitz_minutes
	set(value): setup_config.blitz_minutes = value
var timing_option: OptionButton
var timer_type_option: OptionButton
var starter_option: OptionButton
var name_inputs: Dictionary = {}
var setup_error: Label
var start_button: Button
var setup_scroll: ScrollContainer # Kept null; primary menus no longer scroll.
var setup_entry = "Versus"
var display_manager
var display_options: Dictionary = {}
var confirmation_overlay: ColorRect
var confirmation_label: Label
var setup_actions: VBoxContainer
var timeout_text: Label
var winner_text: Label
var victory_art: Control
var victory_buttons: Array[Button] = []
var volume_sliders: Dictionary = {}
var card_tweens: Array[Tween] = []
var music_volume = 0.2
var effects_volume = 0.5
var animations_enabled = true
var has_match = false
var match_background_visible = false
var screen_transitions_enabled = true
var transitioning = false
var screen_tween: Tween
var transition_count = 0
var input_shield: ColorRect
var page_content: Control
var logo: TextureRect
var setup_heading = ""
var camera_transitions_enabled = true
var preferred_camera = "isometric"
var settings_toggles: Dictionary = {}
var camera_option: OptionButton
var ui_theme: Theme

func _ready() -> void:
	ui_theme = make_theme()
	hud = Control.new()
	hud.theme = ui_theme
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hamburger = button("\u2630", "menu")
	hamburger.tooltip_text = "Match menu (Esc pauses)"
	hamburger.position = Vector2(14, 14)
	hamburger.custom_minimum_size = Vector2(44, 40)
	hud.add_child(hamburger)
	menu = PanelContainer.new()
	menu.position = Vector2(14, 62)
	menu.add_theme_stylebox_override("panel", panel_style())
	hud.add_child(menu)
	var menu_items = VBoxContainer.new()
	menu.add_child(menu_items)
	menu_items.add_child(button("Settings", "settings"))
	pause_button = button("Pause", "pause")
	menu_items.add_child(pause_button)
	menu_items.add_child(button("Restart Match", "restart"))
	menu_items.add_child(button("Main Menu", "main_menu"))
	menu.hide()
	cards_container = GridContainer.new()
	cards_container.add_theme_constant_override("h_separation", 6)
	cards_container.add_theme_constant_override("v_separation", 6)
	hud.add_child(cards_container)
	feedback = label("", 14)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feedback)
	overlay = ColorRect.new()
	overlay.theme = ui_theme
	overlay.color = Color(0.035, 0.03, 0.025, 0.76)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	input_shield = ColorRect.new()
	input_shield.color = Color.TRANSPARENT
	add_child(input_shield)
	input_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	input_shield.hide()
	get_viewport().size_changed.connect(layout_hud)

func make_theme() -> Theme:
	var theme = Theme.new()
	theme.default_font = load("res://assets/fonts/Lato-Regular.ttf")
	theme.default_font_size = 16
	for kind in ["Button", "OptionButton", "LineEdit"]:
		theme.set_color("font_color", kind, Color("#E5E7EA"))
		theme.set_color("font_hover_color", kind, Color("#FFF1C2"))
		for state in ["normal", "hover", "pressed", "focus"]:
			var style = panel_style()
			style.bg_color = Color("#272C33") if state == "normal" else Color("#343A42")
			style.border_color = Color("#BAA36B") if state in ["hover", "focus"] else Color("#42474E")
			if state == "focus": style.set_border_width_all(2)
			theme.set_stylebox(state, kind, style)
	return theme

func panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.075, 0.09, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.07)
	return style

func label(text: String, size: int = 16) -> Label:
	var item = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	return item

func button(text: String, action: String) -> Button:
	var item = Button.new()
	item.name = action.to_pascal_case()
	item.text = text
	item.custom_minimum_size.y = 38
	item.focus_mode = Control.FOCUS_ALL
	item.pressed.connect(func(): action_requested.emit(action))
	return item

func build_cards(state) -> void:
	for tween in card_tweens:
		if tween.is_valid():
			tween.kill()
	card_tweens.clear()
	for child in cards_container.get_children():
		child.free()
	cards.clear()
	for player_id in state.active_players():
		var player = state.players[player_id]
		var panel = PanelContainer.new()
		var style = panel_style()
		style.set_content_margin_all(7)
		panel.add_theme_stylebox_override("panel", style)
		cards_container.add_child(panel)
		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		panel.add_child(column)
		var row = HBoxContainer.new()
		column.add_child(row)
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(13, 13)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_style = StyleBoxFlat.new()
		dot_style.bg_color = COLORS[player_id]
		dot_style.set_corner_radius_all(7)
		dot.add_theme_stylebox_override("panel", dot_style)
		row.add_child(dot)
		var name_label = label(player.name, 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = player.name + "  |  " + player.identity + "  |  " + player.controller
		row.add_child(name_label)
		var details = HBoxContainer.new()
		column.add_child(details)
		var icon = WallIcon.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.tooltip_text = "Walls remaining"
		details.add_child(icon)
		var walls = label("", 13)
		details.add_child(walls)
		var timer = label("0.0s", 13)
		timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		timer.tooltip_text = "Elapsed turn time; inactive cards retain their last turn"
		details.add_child(timer)
		cards[player_id] = {"panel": panel, "style": style, "walls": walls,
			"timer": timer, "name": name_label, "active": false}
	layout_hud()

func update_cards(state) -> void:
	for player_id in cards:
		var card = cards[player_id]
		card.panel.visible = not state.players[player_id].eliminated
		card.walls.text = str(state.players[player_id].walls_remaining)
		var seconds: float = state.elapsed_turns[player_id]
		var countdown = state.config.timing_mode != "Untimed"
		var overtime = state.uses_blitz_clock and player_id == state.current_player and state.penalty_used
		if state.config.timing_mode == "Per Game":
			seconds = state.overtime if overtime else state.time_left[player_id]
		elif state.config.timing_mode == "Per Turn":
			seconds = state.remaining_turn_time if player_id == state.current_player and state.players[player_id].controller == "Human" else float(state.config.turn_limit)
		var tenths = ceili(maxf(0.0, seconds) * 10.0)
		var clock_text = "%d:%04.1f" % [tenths / 600, (tenths % 600) / 10.0]
		card.timer.text = ("OT " if overtime else "") + (clock_text if state.config.timing_mode == "Per Game" else "%.1fs" % seconds)
		var exempt = countdown and state.players[player_id].controller != "Human"
		if exempt: card.timer.text = "Exempt"
		card.timer.tooltip_text = "Overtime: one wall lost this turn" if overtime else \
			("Remaining time" if countdown else "Elapsed turn time; inactive cards retain their last turn")
		if exempt: card.timer.tooltip_text = "AI turns do not consume countdown time"
		var timer_color = Color("#EF7770") if seconds <= 5 else Color("#F9CD70")
		card.timer.add_theme_color_override("font_color", timer_color if countdown and not exempt and seconds <= 10 else Color("#DDDDDD"))
		var active = state.status == "running" and player_id == state.current_player
		if active != card.active:
			card.active = active
			var color = GOLD if active else Color(1, 1, 1, 0.07)
			if animations_enabled:
				# Finished tweens are discarded so long matches do not grow this list.
				card_tweens = card_tweens.filter(func(t): return t.is_valid())
				var tween = create_tween()
				card_tweens.append(tween)
				tween.tween_property(card.style, "border_color", color, 0.18)
			else:
				card.style.border_color = color
	pause_button.text = "Resume" if state.paused else "Pause"

func layout_hud() -> void:
	if cards_container == null:
		return
	var size = get_viewport().get_visible_rect().size
	var columns = 2 if size.x < 850 and cards.size() > 2 else 1
	cards_container.columns = columns
	var width = clampf((size.x - 90) / columns, 110, 188 if size.x < 850 else 204)
	for card in cards.values():
		card.panel.custom_minimum_size = Vector2(width, 54)
	# A standalone Container grows to its minimum, but does not shrink automatically.
	cards_container.size = Vector2(width * columns + 6 * (columns - 1), 0)
	cards_container.position = Vector2(size.x - (width * columns + 6 * (columns - 1)) - 14, 14)
	feedback.position = Vector2(16, size.y - 32)
	feedback.size = Vector2(maxf(0, size.x - 32), 24)
	if page_panel != null:
		page_panel.custom_minimum_size.x = minf(1000 if page in ["setup", "settings", "how_to_play"] else 540, size.x - 32)
	if logo != null:
		logo.custom_minimum_size = Vector2(minf(380, size.x - 80), minf(150, size.y * 0.21))
	if victory_art != null:
		var art_width = minf(480, minf(size.x - 72, maxf(80, size.y - 150) * 900.0 / 520.0))
		victory_art.custom_minimum_size = Vector2(art_width, art_width * 520.0 / 900.0)
		winner_text.position = Vector2(art_width * 172.0 / 540.0, victory_art.custom_minimum_size.y * 256.0 / 312.0)
		var bounds = Vector2(art_width * 196.0 / 540.0, victory_art.custom_minimum_size.y * 29.0 / 312.0)
		var font = winner_text.get_theme_font("font")
		var font_size = 20
		while font_size > 8 and (font.get_string_size(winner_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > bounds.x \
			or font.get_height(font_size) > bounds.y):
			font_size -= 1
		winner_text.add_theme_font_size_override("font_size", font_size)
		winner_text.size = bounds

func blocks_board(point: Vector2) -> bool:
	if transitioning or page != "game" or menu.visible:
		return true
	if hamburger.get_global_rect().has_point(point):
		return true
	for card in cards.values():
		if card.panel.get_global_rect().has_point(point):
			return true
	return false

func set_animations(enabled: bool) -> void:
	animations_enabled = enabled
	if not enabled:
		for tween in card_tweens:
			if tween.is_valid():
				tween.kill()
		card_tweens.clear()
		for card in cards.values():
			card.style.border_color = GOLD if card.active else Color(1, 1, 1, 0.07)

func show_page(value: String, state = null) -> void:
	var same_page = page == value and page_content != null
	finish_screen_transition(false)
	page = value
	menu.hide()
	overlay.color = Color(0.025, 0.03, 0.04, 0.74) if match_background_visible else Color("#15191F")
	overlay.visible = value != "game"
	hud.visible = value in ["game", "pause", "settings", "victory"] and has_match
	hamburger.visible = value == "game"
	if page_panel != null:
		var previous = page_panel.get_parent()
		overlay.remove_child(previous)
		previous.queue_free()
		page_panel = null
	victory_buttons.clear()
	winner_text = null
	victory_art = null
	volume_sliders.clear()
	controller_options.clear()
	name_inputs.clear()
	starter_option = null
	timer_type_option = null
	start_button = null
	setup_error = null
	setup_scroll = null
	setup_actions = null
	timing_option = null
	timeout_text = null
	logo = null
	settings_toggles.clear()
	camera_option = null
	if value == "game":
		page_content = hud
		begin_screen_transition(same_page)
		return
	var center = CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_panel = PanelContainer.new()
	page_panel.add_theme_stylebox_override("panel", panel_style())
	if value == "main_menu":
		page_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	center.add_child(page_panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	page_panel.add_child(column)
	column.add_theme_constant_override("separation", 8)
	match value:
		"main_menu":
			logo = TextureRect.new()
			logo.texture = load("res://assets/branding/gridlock_logo.png")
			logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			column.add_child(logo)
			var modes = GridContainer.new()
			modes.columns = 2
			modes.add_theme_constant_override("h_separation", 12)
			modes.add_theme_constant_override("v_separation", 12)
			column.add_child(modes)
			for item in [["Versus", "setup_versus"], ["Battle Royale", "setup_battle"], ["Blitz", "setup_blitz"], ["Rise of the Machines", "setup_ai"]]:
				var choice = button(item[0], item[1])
				choice.custom_minimum_size.y = 56
				choice.custom_minimum_size.x = 230
				choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				modes.add_child(choice)
			var secondary = HBoxContainer.new()
			secondary.add_theme_constant_override("separation", 12)
			column.add_child(secondary)
			for item in [["Settings", "settings"], ["How to Play", "how_to_play"], ["Exit Game", "exit"]]:
				var control = button(item[0], item[1])
				control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				secondary.add_child(control)
			var version = label(ProjectSettings.get_setting("application/config/version", ""), 12)
			version.add_theme_color_override("font_color", Color("#939BA6"))
			column.add_child(version)
		"setup":
			column.add_child(label(setup_heading if not setup_heading.is_empty() else setup_mode, 26))
			var text = "4 players  |  5 walls each" if setup_mode == "Battle Royale" else "2 players  |  10 walls each"
			if not setup_heading.is_empty(): text = setup_mode + "  |  " + text
			column.add_child(label(text, 16))
			column.add_child(section_label("Players"))
			add_controller_options(column)
			column.add_child(section_label("Match Rules"))
			var rules = HBoxContainer.new()
			column.add_child(rules)
			var starter_column = VBoxContainer.new()
			starter_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rules.add_child(starter_column)
			starter_option = setup_dropdown(starter_column, "Starting player", ["Default", "Random"])
			starter_option.select(1 if setup_config.random_start else 0)
			starter_option.item_selected.connect(func(index): setup_config.random_start = index == 1)
			var timer_column = VBoxContainer.new()
			timer_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rules.add_child(timer_column)
			add_timing_option(timer_column)
			setup_error = label("", 13)
			setup_error.add_theme_color_override("font_color", Color("#EF7770"))
			setup_actions = VBoxContainer.new()
			setup_actions.add_theme_constant_override("separation", 8)
			column.add_child(setup_actions)
			setup_actions.add_child(section_label("Actions"))
			setup_actions.add_child(setup_error)
			start_button = button("Start Match", "start")
			setup_actions.add_child(start_button)
			var secondary = HBoxContainer.new()
			secondary.add_theme_constant_override("separation", 12)
			setup_actions.add_child(secondary)
			for item in [["Back to Main Menu", "main_menu"], ["Reset to Defaults", "reset_preferences"]]:
				var control = button(item[0], item[1])
				control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				secondary.add_child(control)
			validate_setup()
		"pause":
			column.add_child(label("Paused", 26))
			column.add_child(button("Resume", "resume"))
			column.add_child(button("Settings", "settings"))
			column.add_child(button("Restart Match", "restart"))
			column.add_child(button("Main Menu", "main_menu"))
		"settings":
			build_settings(column)
		"how_to_play":
			column.add_child(label("How to Play", 28))
			var sections = GridContainer.new()
			sections.columns = 2
			sections.add_theme_constant_override("h_separation", 24)
			sections.add_theme_constant_override("v_separation", 12)
			column.add_child(sections)
			for entry in [
				["Objective & victory", "Reach your opposite edge first. Turns proceed clockwise.\nTimeouts use the selected mode's existing elimination rules."],
				["Movement", "Click your pawn, then a green tile. Move orthogonally.\nJump an adjacent pawn if the landing and steps are clear.\nIf a wall, edge or pawn blocks the landing, step diagonally\nto a free, unblocked side of that pawn."],
				["Walls", "Place a wall instead of moving. R / right-click rotates.\nWalls cannot overlap, cross, or remove any player's last\npath to their goal. Click your pawn to see legal moves."],
				["Versus & Rise of the Machines", "Versus: two local humans, no countdown.\nRise of the Machines: two-player AI-focused setup,\nusing the same movement and wall rules."],
				["Battle Royale", "Four players, optional AI, five walls each. Choose a\nPer Turn or Per Game clock. Timed-out seats are removed;\ntheir placed walls remain. AI countdowns are exempt."],
				["Blitz", "Two players, optional AI. Per Turn resets each turn.\nPer Game grants a 10s turn-start minimum; clock expiry\ncosts a wall and grants one 15s overtime per turn.\nExpiry with no walls, or overtime expiry, loses.\nAI countdowns are exempt."]]:
				var section = VBoxContainer.new()
				sections.add_child(section)
				section.add_child(section_label(entry[0]))
				section.add_child(label(entry[1], 16))
			column.add_child(label("Esc: pause / back   |   1 / 2 / 3: camera   |   Tab / arrows / Enter: menu navigation", 15))
			column.add_child(button("Back", "main_menu"))
		"victory":
			add_victory_art(column, state)
			if state.timeout_player >= 0 and state.result_reason != "goal_reached":
				timeout_text = label(state.timing_notice, 15)
				timeout_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				column.add_child(timeout_text)
			for item in [["Play Again", "play_again"], ["Main Menu", "main_menu"]]:
				var control = button(item[0], item[1])
				column.add_child(control)
				victory_buttons.append(control)
	layout_hud()
	page_content = page_panel
	begin_screen_transition(same_page)

func section_label(text: String) -> Label:
	var title = label(text.to_upper(), 12)
	title.add_theme_color_override("font_color", Color("#C6B785"))
	return title

func add_toggle(column: VBoxContainer, text: String, key: String, enabled: bool, callback: Callable) -> void:
	var toggle = CheckButton.new()
	toggle.text = text
	toggle.button_pressed = enabled
	toggle.toggled.connect(callback)
	column.add_child(toggle)
	settings_toggles[key] = toggle

func begin_screen_transition(skip: bool = false) -> void:
	if skip or not screen_transitions_enabled:
		focus_page.call_deferred()
		transition_finished.emit()
		return
	transitioning = true
	transition_count += 1
	input_shield.show()
	page_content.modulate.a = 0.0
	transition_started.emit()
	screen_tween = create_tween()
	screen_tween.tween_property(page_content, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	screen_tween.finished.connect(finish_screen_transition)

func finish_screen_transition(notify: bool = true) -> void:
	if screen_tween != null and screen_tween.is_valid(): screen_tween.kill()
	screen_tween = null
	transitioning = false
	if input_shield != null: input_shield.hide()
	if is_instance_valid(page_content): page_content.modulate.a = 1.0
	if notify:
		focus_page.call_deferred()
		transition_finished.emit()

func focus_page() -> void:
	if transitioning or page == "game" or page_panel == null: return
	if page == "setup" and name_inputs.has(0):
		name_inputs[0].grab_focus()
		return
	for control in page_panel.find_children("*", "Button", true, false):
		if control.is_visible_in_tree() and not control.disabled:
			control.grab_focus()
			return

func add_timing_option(column: VBoxContainer) -> void:
	if setup_mode == "Versus": return
	if setup_mode in ["Battle Royale", "Blitz"]:
		timer_type_option = setup_dropdown(column, "Timer Type", Config.TIMER_TYPES)
		timer_type_option.select(Config.TIMER_TYPES.find(setup_config.timer_type))
		timer_type_option.item_selected.connect(func(index):
			setup_config.timer_type = Config.TIMER_TYPES[index]
			refresh_durations())
	timing_option = setup_dropdown(column, "Time Limit", [])
	timing_option.item_selected.connect(func(index):
		if setup_mode == "Blitz" and setup_config.timer_type == "Per Game": setup_config.blitz_minutes = BLITZ_MINUTES[index]
		elif setup_config.timer_type == "Per Game": setup_config.game_limit = Config.GAME_SECONDS[index]
		else: setup_config.turn_limit = Config.TURN_SECONDS[index])
	refresh_durations()

func refresh_durations() -> void:
	var blitz_global = setup_mode == "Blitz" and setup_config.timer_type == "Per Game"
	var values = BLITZ_MINUTES if blitz_global else (Config.GAME_SECONDS if setup_config.timer_type == "Per Game" else Config.TURN_SECONDS)
	var selected = setup_blitz_minutes if blitz_global else (setup_config.game_limit if setup_config.timer_type == "Per Game" else setup_turn_limit)
	timing_option.clear()
	for value in values:
		timing_option.add_item(("%d minutes" % value) if blitz_global else ("%d seconds" % value if value < 60 else "%d minutes" % (value / 60)))
	if selected not in values:
		selected = 3 if blitz_global else (180 if setup_config.timer_type == "Per Game" else 30)
		if blitz_global: setup_config.blitz_minutes = selected
		elif setup_config.timer_type == "Per Game": setup_config.game_limit = selected
		else: setup_config.turn_limit = selected
	timing_option.select(values.find(selected))
	validate_setup()

func setup_dropdown(column: VBoxContainer, text: String, choices: Array) -> OptionButton:
	var row = HBoxContainer.new()
	column.add_child(row)
	var title = label(text, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var choice = OptionButton.new()
	choice.custom_minimum_size = Vector2(165, 32)
	for value in choices: choice.add_item(value)
	row.add_child(choice)
	return choice

func validate_setup() -> bool:
	var error = setup_config.validation_error()
	if setup_error != null:
		setup_error.text = "Enter a name for every player." if error == "invalid_name" else ("Invalid match settings." if not error.is_empty() else "")
		setup_error.visible = not error.is_empty()
	if start_button != null: start_button.disabled = not error.is_empty()
	return error.is_empty()

func add_controller_options(column: VBoxContainer) -> void:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var order = [0, 1, 2, 3] if setup_mode == "Battle Royale" else [0, 1]
	for player_id in order:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size.x = 460
		panel.add_theme_stylebox_override("panel", panel_style())
		grid.add_child(panel)
		var fields = VBoxContainer.new()
		panel.add_child(fields)
		var identity = label(ART_NAMES[player_id].capitalize(), 16)
		identity.add_theme_color_override("font_color", COLORS[player_id].lightened(0.4))
		fields.add_child(identity)
		var name = LineEdit.new()
		name.name = "Name%d" % player_id
		name.text = setup_config.names[player_id]
		name.max_length = Config.NAME_LIMIT
		name.custom_minimum_size = Vector2(125, 38)
		name.tooltip_text = "%s ? up to %d characters" % [Config.IDENTITIES[player_id], Config.NAME_LIMIT]
		name.text_changed.connect(func(value):
			setup_config.names[player_id] = Config.clean_name(value)
			validate_setup())
		fields.add_child(name)
		name_inputs[player_id] = name
		if setup_entry == "Versus": continue
		var choice = OptionButton.new()
		choice.name = "Controller%d" % player_id
		choice.custom_minimum_size = Vector2(165, 36)
		for option in CONTROL_OPTIONS: choice.add_item(option)
		choice.select(CONTROL_OPTIONS.find(setup_controllers[player_id]))
		choice.item_selected.connect(func(index): setup_controllers[player_id] = CONTROL_OPTIONS[index])
		fields.add_child(choice)
		controller_options[player_id] = choice

func add_volume(column: VBoxContainer, text: String, category: String, value: float) -> void:
	column.add_child(label(text, 15))
	var slider = HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 26)
	slider.value_changed.connect(func(volume): volume_changed.emit(category, volume))
	column.add_child(slider)
	volume_sliders[category] = slider

func add_victory_art(column: VBoxContainer, state) -> void:
	var player = state.players[state.winner]
	var texture = load("res://assets/victory/" + ART_NAMES[player.id] + "_victory.png")
	var width = minf(480, get_viewport().get_visible_rect().size.x - 72)
	var art = Control.new()
	art.custom_minimum_size = Vector2(width, width * 520.0 / 900.0)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	victory_art = art
	column.add_child(art)
	var image = TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	winner_text = label(player.name.to_upper() + " WINS!", 20)
	winner_text.clip_text = true
	winner_text.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	winner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	winner_text.position = Vector2(width * 172.0 / 540.0, art.custom_minimum_size.y * 256.0 / 312.0)
	winner_text.size = Vector2(width * 196.0 / 540.0, art.custom_minimum_size.y * 29.0 / 312.0)
	art.add_child(winner_text)

func build_settings(column: VBoxContainer) -> void:
	column.add_child(label("Settings", 28))
	var grid = HBoxContainer.new()
	grid.add_theme_constant_override("separation", 30)
	column.add_child(grid)
	var audio_column = VBoxContainer.new()
	var display_column = VBoxContainer.new()
	for side in [audio_column, display_column]:
		side.custom_minimum_size.x = 465
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(side)
	audio_column.add_child(section_label("Audio & presentation"))
	add_volume(audio_column, "Music", "music", music_volume)
	add_volume(audio_column, "Sound Effects", "effects", effects_volume)
	add_toggle(audio_column, "Gameplay animations", "animations", animations_enabled, animations_changed.emit)
	add_toggle(audio_column, "Camera transitions", "camera_transitions", camera_transitions_enabled, camera_transitions_changed.emit)
	camera_option = setup_dropdown(audio_column, "Camera", ["Classic", "Isometric", "Cinematic"])
	camera_option.select(["classic", "isometric", "cinematic"].find(preferred_camera))
	camera_option.item_selected.connect(func(index): camera_view_changed.emit(["classic", "isometric", "cinematic"][index]))
	display_column.add_child(section_label("Display"))
	display_options.clear()
	if display_manager != null:
		var settings = display_manager.settings
		var modes = settings.DISPLAY_MODES
		var mode = setup_dropdown(display_column, "Mode", modes)
		mode.select(modes.find(display_manager.current.mode))
		mode.item_selected.connect(func(index): display_changed.emit("mode", modes[index]))
		display_options.mode = mode
		var values = display_manager.available_resolutions()
		var names = values.map(func(size): return "%d x %d" % [size.x, size.y])
		var resolution = setup_dropdown(display_column, "Resolution", names)
		resolution.select(values.find(display_manager.current.resolution))
		resolution.disabled = display_manager.current.mode != "Windowed"
		resolution.item_selected.connect(func(index): display_changed.emit("resolution", values[index]))
		display_options.resolution = resolution
		var scale = setup_dropdown(display_column, "UI Scale", settings.SCALES)
		scale.select(settings.SCALES.find(settings.ui_scale))
		scale.item_selected.connect(func(index): display_changed.emit("scale", settings.SCALES[index]))
		display_options.scale = scale
		var vsync = setup_dropdown(display_column, "VSync", ["On", "Off"])
		vsync.select(0 if settings.vsync else 1)
		vsync.item_selected.connect(func(index): display_changed.emit("vsync", index == 0))
		display_options.vsync = vsync
		display_column.add_child(label("Scale is capped to keep every menu on screen.\nThe selected preference is retained.", 14))
	column.add_child(section_label("About"))
	column.add_child(label("Gridlock | " + str(ProjectSettings.get_setting("application/config/version")) + " | ClementPeterLeroy\nGodot Engine (MIT) | Lato / Cinzel (SIL OFL). See bundled third-party notices.", 14))
	var actions = HBoxContainer.new()
	column.add_child(actions)
	for entry in [["Reset to Defaults", "reset_settings"], ["Back", "settings_back"]]:
		var control = button(entry[0], entry[1])
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(control)

func show_display_confirmation(seconds: float) -> void:
	if confirmation_overlay == null:
		confirmation_overlay = ColorRect.new()
		confirmation_overlay.color = Color(0, 0, 0, 0.85)
		confirmation_overlay.theme = ui_theme
		add_child(confirmation_overlay)
		confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center = CenterContainer.new()
		confirmation_overlay.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", panel_style())
		center.add_child(panel)
		var column = VBoxContainer.new()
		panel.add_child(column)
		confirmation_label = label("", 22)
		column.add_child(confirmation_label)
		var keep = button("Keep Changes", "keep_display")
		column.add_child(keep)
		var revert = button("Revert", "revert_display")
		column.add_child(revert)
		revert.grab_focus()
	confirmation_label.text = "Keep this display configuration? Reverting in %d seconds." % ceili(seconds)

func hide_display_confirmation() -> void:
	if confirmation_overlay != null:
		remove_child(confirmation_overlay)
		confirmation_overlay.queue_free()
		confirmation_overlay = null
		confirmation_label = null
