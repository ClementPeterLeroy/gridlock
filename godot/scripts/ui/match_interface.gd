extends CanvasLayer
## Compact HUD and modal pages. Emits intent; it never changes match state.

signal action_requested(action: String)
signal volume_changed(category: String, value: float)
signal animations_changed(enabled: bool)

const COLORS = [Color("#345B9A"), Color("#A84343"), Color("#3E7955"), Color("#78529A")]
const GOLD = Color("#F9D55E")
const ART_NAMES = ["sapphire", "crimson", "emerald", "violet"]

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
var setup_mode = "Versus"
var winner_text: Label
var victory_art: Control
var victory_buttons: Array[Button] = []
var volume_sliders: Dictionary = {}
var card_tweens: Array[Tween] = []
var music_volume = 0.2
var effects_volume = 0.5
var animations_enabled = true
var has_match = false

func _ready() -> void:
	hud = Control.new()
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hamburger = button("☰", "menu")
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
	overlay.color = Color(0.035, 0.03, 0.025, 0.76)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(layout_hud)
	show_page("main_menu")

func panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.06, 0.055, 0.86)
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
		name_label.tooltip_text = player.name + " · " + player.identity
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

func update_cards(state, elapsed: Array) -> void:
	for player_id in cards:
		var card = cards[player_id]
		card.walls.text = str(state.players[player_id].walls_remaining)
		card.timer.text = "%.1fs" % elapsed[player_id]
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
		page_panel.custom_minimum_size.x = minf(500, size.x - 32)
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
	if page != "game" or menu.visible:
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
	page = value
	menu.hide()
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
	if value == "game":
		return
	var center = CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_panel = PanelContainer.new()
	page_panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(page_panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	page_panel.add_child(column)
	match value:
		"main_menu":
			column.add_child(label("GRIDLOCK", 32))
			column.add_child(label("Local multiplayer", 16))
			column.add_child(button("Versus", "setup_versus"))
			column.add_child(button("Battle Royale", "setup_battle"))
			column.add_child(button("Settings", "settings"))
		"setup":
			column.add_child(label(setup_mode, 26))
			var text = "Sapphire vs Crimson\n2 local players · 10 walls each" if setup_mode == "Versus" \
				else "Sapphire → Emerald → Crimson → Violet\n4 local players · 5 walls each"
			column.add_child(label(text, 16))
			column.add_child(button("Start Match", "start"))
			column.add_child(button("Main Menu", "main_menu"))
		"pause":
			column.add_child(label("Paused", 26))
			column.add_child(button("Resume", "resume"))
			column.add_child(button("Restart Match", "restart"))
			column.add_child(button("Main Menu", "main_menu"))
		"settings":
			column.add_child(label("Settings", 26))
			add_volume(column, "Music", "music", music_volume)
			add_volume(column, "Sound Effects", "effects", effects_volume)
			var toggle = CheckButton.new()
			toggle.text = "Animations"
			toggle.button_pressed = animations_enabled
			toggle.toggled.connect(func(enabled): animations_changed.emit(enabled))
			column.add_child(toggle)
			column.add_child(button("Back", "settings_back"))
		"victory":
			add_victory_art(column, state)
			for item in [["Play Again", "restart"], ["Main Menu", "main_menu"]]:
				var control = button(item[0], item[1])
				column.add_child(control)
				victory_buttons.append(control)
	layout_hud()

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
