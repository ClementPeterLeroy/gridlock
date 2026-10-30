extends "res://tests/run_timing_tests.gd"

const Settings = preload("res://scripts/user_settings.gd")
const TEST_PATH = "res://.godot/beta-settings-test.cfg"

func run() -> void:
	check(test_settings_file(), "settings persistence completed")
	game = Scene.instantiate()
	game.preferences_path = ""
	game.settings_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.live_timing = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_animations(false)
	settle()
	for method in ["test_visibility_and_navigation", "test_screen_transitions", "test_settings_controls"]:
		check(call(method) == true, method + " completed")
	check(await test_keyboard() == true, "keyboard navigation completed")
	check(await test_resolutions() == true, "responsive layout completed")
	game.free()
	await create_timer(0.1).timeout
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	print("BETA UI TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func settle() -> void:
	if game.ui.screen_tween != null:
		game.ui.screen_tween.pause()
		game.ui.screen_tween.custom_step(0.3)

func navigate(action: String) -> void:
	game.handle_ui_action(action)
	settle()

func board_visibility(expected: bool) -> void:
	check(game.visible == expected and game.get_node("Board").is_visible_in_tree() == expected, "screen owns full 3D visibility")
	for pawn in game.pawn_nodes:
		if pawn.visible:
			check(pawn.is_visible_in_tree() == expected, "pawn inherits presentation visibility")
	check(game.get_node("Walls").is_visible_in_tree() == expected, "walls inherit presentation visibility")
	check(game.ui.page == "game" or game.ui.page_panel.is_visible_in_tree(), "2D interface stays visible independently of 3D root")

func test_visibility_and_navigation() -> bool:
	game.show_main_menu()
	settle()
	board_visibility(false)
	check(game.ui.logo != null and game.ui.logo.texture != null, "official logo on main menu")
	for action in ["setup_versus", "setup_battle", "setup_blitz", "setup_ai", "settings", "exit"]:
		check(game.ui.page_panel.find_child(action.to_pascal_case(), true, false) is Button, "main menu action " + action)
	var saved = game.engine.state.snapshot()
	check(not game.click_at_screen(Vector2(400, 300)) and game.engine.state.snapshot() == saved, "hidden match cannot receive board actions")
	navigate("settings")
	board_visibility(false)
	navigate("settings_back")
	check(game.view == "main_menu", "menu settings returns to menu")
	for action in ["setup_versus", "setup_battle", "setup_blitz", "setup_ai"]:
		navigate(action)
		board_visibility(false)
		check(game.ui.name_inputs.size() == game.ui.setup_config.player_count(), "setup includes participating names")
		check((game.ui.timer_type_option != null) == (game.ui.setup_mode != "Versus"), "timer selectors retained for timed modes")
		if action == "setup_ai":
			check(game.ui.setup_mode == "Versus" and game.ui.setup_config.controllers[1] == "AI - Casual", "Machines seeds AI setup without a new ruleset")
		navigate("main_menu")
	navigate("setup_versus")
	navigate("start")
	board_visibility(true)
	navigate("pause")
	board_visibility(true)
	check(game.ui.page_panel.find_child("Settings", true, false) is Button, "pause includes Settings")
	navigate("settings")
	board_visibility(true)
	navigate("settings_back")
	check(game.view == "pause" and game.engine.state.paused, "pause settings returns paused")
	navigate("resume")
	navigate("settings")
	board_visibility(true)
	navigate("settings_back")
	check(game.view == "game" and not game.engine.state.paused, "active settings resumes active screen")
	game.engine.state.winner = 0
	game.engine.state.status = "finished"
	game.sync_scene()
	settle()
	board_visibility(true)
	check(game.ui.victory_buttons.size() == 2 and game.ui.winner_text.text == "SAPPHIRE WINS!", "victory retains sticker text and exactly two buttons")
	navigate("play_again")
	check(game.view == "game" and game.engine.state.winner == -1, "Play Again returns to active match")
	return true

func test_screen_transitions() -> bool:
	game.show_main_menu()
	settle()
	var count = game.ui.transition_count
	game.handle_ui_action("setup_versus")
	var tween = game.ui.screen_tween
	check(game.ui.transitioning and game.ui.input_shield.visible, "transition blocks mouse input")
	game.handle_ui_action("setup_battle")
	check(game.ui.screen_tween == tween and game.ui.transition_count == count + 1 and game.ui.setup_mode == "Versus", "rapid actions cannot start duplicate transitions")
	check(game.ui.overlay.get_child_count() == 1, "only one screen content tree exists")
	settle()
	game.handle_ui_action("start")
	var before = game.engine.state.snapshot()
	game._process(10)
	check(game.engine.state.snapshot() == before and not game.can_interact(), "gameplay, AI and clocks wait for screen fade")
	check(not game.click_at_screen(Vector2(400, 300)), "no gameplay click through transition shield")
	settle()
	check(not game.ui.transitioning and not game.ui.input_shield.visible and game.can_interact(), "transition completes and restores interaction")
	game._process(0.25)
	check(game.engine.state.turn_elapsed == 0.25, "clock resumes without charging transition duration")
	return true

func test_settings_file() -> bool:
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	var settings = Settings.new(TEST_PATH)
	check(settings.music_volume == 0.2 and settings.camera_view == "classic", "missing settings file uses defaults")
	settings.music_volume = 0.73
	settings.effects_volume = 0.12
	settings.camera_transitions = false
	settings.gameplay_animations = false
	settings.camera_view = "cinematic"
	check(settings.save() == OK, "settings written to isolated file")
	var loaded = Settings.new(TEST_PATH)
	check(loaded.music_volume == 0.73 and loaded.effects_volume == 0.12 and not loaded.camera_transitions and not loaded.gameplay_animations and loaded.camera_view == "cinematic", "all application preferences reload independently")
	var content = FileAccess.get_file_as_string(TEST_PATH)
	check(not content.contains("controllers") and not content.contains("time_left"), "application settings contain no match or transient state")
	var file = ConfigFile.new()
	file.set_value("settings", "music_volume", -5)
	file.set_value("settings", "effects_volume", "loud")
	file.set_value("settings", "camera_transitions", "no")
	file.set_value("settings", "gameplay_animations", 7)
	file.set_value("settings", "camera_view", "invalid")
	file.save(TEST_PATH)
	loaded = Settings.new(TEST_PATH)
	check(loaded.music_volume == 0.2 and loaded.effects_volume == 0.5 and loaded.camera_transitions and loaded.gameplay_animations and loaded.camera_view == "classic", "invalid preferences safely fall back")
	settings.reset()
	settings.save()
	check(Settings.new(TEST_PATH).music_volume == 0.2, "Reset to Defaults persists")
	return true

func test_settings_controls() -> bool:
	navigate("settings")
	game.user_settings.path = TEST_PATH
	var saved = game.engine.state.snapshot()
	game.ui.volume_sliders.music.value = 0.73
	game.ui.volume_sliders.effects.value = 0.12
	check(game.audio.music_volume == 0.73 and game.audio.effects_volume == 0.12, "volume settings apply immediately")
	game.ui.settings_toggles.camera_transitions.button_pressed = false
	game.ui.settings_toggles.animations.button_pressed = false
	game.ui.camera_option.select(2)
	game.ui.camera_option.item_selected.emit(2)
	check(game.camera.position == game.camera_positions.cinematic and not game.animations_enabled, "camera perspective and animation settings apply immediately")
	check(game.engine.state.snapshot() == saved, "application settings cannot change paused match")
	var loaded = Settings.new(TEST_PATH)
	check(loaded.camera_view == "cinematic" and not loaded.camera_transitions and loaded.music_volume == 0.73, "UI changes persist to application file")
	navigate("reset_settings")
	check(game.audio.music_volume == 0.2 and game.audio.effects_volume == 0.5 and game.user_settings.camera_transitions and game.animations_enabled, "settings reset applies all defaults")
	check(game.camera.position == game.camera_positions.classic and game.preferences.path.is_empty(), "settings reset preserves match preference separation")
	game.user_settings.path = ""
	navigate("settings_back")
	return true

func press(key: Key) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event, true)

func test_keyboard() -> bool:
	game.show_main_menu()
	settle()
	await process_frame
	var first = root.gui_get_focus_owner()
	check(first is Button, "main menu has initial keyboard focus")
	press(KEY_RIGHT)
	await process_frame
	check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner() != first, "arrow keys navigate menu actions")
	first.grab_focus()
	press(KEY_TAB)
	await process_frame
	var next = root.gui_get_focus_owner()
	check(next is Button and next != first, "Tab navigates menu actions")
	press(KEY_ENTER)
	check(game.view == "setup", "Enter activates focused mode action")
	settle()
	await process_frame
	check(root.gui_get_focus_owner() is LineEdit, "setup focuses player name")
	press(KEY_ESCAPE)
	check(game.view == "main_menu", "Escape leaves setup even with name field focused")
	settle()
	navigate("setup_versus")
	navigate("start")
	game.controller.selected = true
	press(KEY_ESCAPE)
	check(game.view == "pause" and not game.controller.selected, "Escape pauses gameplay including pawn selection")
	settle()
	press(KEY_ESCAPE)
	check(game.view == "game", "Escape resumes pause")
	settle()
	navigate("settings")
	press(KEY_ESCAPE)
	check(game.view == "game", "Escape returns from settings")
	settle()
	return true

func test_resolutions() -> bool:
	var original = game
	var viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	root.add_child(viewport)
	game = Scene.instantiate()
	game.settings_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.preferences_path = ""
	game.live_timing = false
	game.screen_transitions_enabled = false
	viewport.add_child(game)
	game.set_process(false)
	game.set_animations(false)
	for size in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		viewport.size = size
		var bounds = Rect2(Vector2.ZERO, Vector2(size))
		game.show_main_menu()
		await process_frame
		await process_frame
		check(bounds.encloses(game.ui.page_panel.get_global_rect()), "main menu fits " + str(size))
		for action in ["setup_battle", "setup_blitz", "setup_ai"]:
			navigate(action)
			await process_frame
			await process_frame
			check(bounds.encloses(game.ui.page_panel.get_global_rect()), "setup panel fits " + str(size))
			for control in game.ui.setup_actions.find_children("*", "Button", true, false):
				check(bounds.encloses(control.get_global_rect()), "setup actions always accessible " + str(size))
			for control in game.ui.controller_options.values():
				await process_frame
				check(bounds.encloses(control.get_global_rect()), "complete controller selector visible without scrolling " + str(size))
			navigate("main_menu")
			navigate("settings")
			await process_frame
			await process_frame
			check(bounds.encloses(game.ui.page_panel.get_global_rect()), "settings fit " + str(size))
			navigate("settings_back")
		var config = options("Battle Royale", 30)
		config.names.fill("abcdefghijkl")
		game.start_match(config)
		await process_frame
		await process_frame
		for card in game.ui.cards.values():
			check(bounds.encloses(card.panel.get_global_rect()), "four-player HUD fits " + str(size))
			check(not card.panel.get_global_rect().intersects(game.ui.hamburger.get_global_rect()), "HUD avoids navigation button")
		game.engine.state.winner = 0
		game.engine.state.status = "finished"
		game.sync_scene()
		await process_frame
		await process_frame
		check(bounds.encloses(game.ui.page_panel.get_global_rect()), "victory fits " + str(size))
		var text = game.ui.winner_text
		check(text.get_theme_font("font").get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text.get_theme_font_size("font_size")).x <= text.size.x, "long winner name fits banner")
	viewport.free()
	game = original
	return true
