extends SceneTree
## Match-flow regression checks using the real scene and UI.

const Scene = preload("res://scenes/game.tscn")
const Config = preload("res://scripts/core/match_config.gd")

class AudioRecorder extends Node:
	var events: Array = []
	func play_effect(event: String) -> void:
		events.append(event)

var checks = 0
var failures = 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	root.size = Vector2i(1280, 900)
	game = Scene.instantiate()
	game.settings_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.screen_transitions_enabled = false
	game.live_timing = false
	game.preferences_path = ""
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for method in ["test_startup_and_setup", "test_cards_and_timer", "test_menu_pause_settings",
		"test_animations", "test_victory", "test_restart_and_main_menu", "test_responsive_cameras",
		"test_complete_matches"]:
		check(await call(method) == true, method + " completed")
	game.free()
	await create_timer(0.1).timeout
	print("MATCH TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func click(position: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)

func press_page_button(action: String) -> void:
	var button = game.ui.page_panel.find_child(action.to_pascal_case(), true, false)
	check(button is Button, "page button exists: " + action)
	if button != null:
		click(button.get_global_rect().get_center())

func start_mode(mode: String, animated: bool = false) -> void:
	game.set_animations(animated)
	# Deterministic tests can execute whole matches in one mixer tick. Test sound
	# intent with AudioRecorder rather than queueing dozens of real sample playbacks.
	game.set_volume("effects", 0.0)
	var config = Config.for_mode(mode)
	config.controllers.fill("Human")
	game.start_match(config)
	game.set_camera_view("classic", false)

func screen(square: Vector2i, height = 0.12) -> Vector2:
	return game.camera.unproject_position(game.get_node("Board").cell_position(square) + Vector3(0, height, 0))

func move_current() -> bool:
	var player = game.engine.state.current_player
	var own: Vector2i = game.engine.state.players[player].position
	var target: Vector2i = game.engine.legal_moves()[0]
	game.click_at_screen(screen(own, 0.45))
	return game.click_at_screen(screen(target))

func finish_animation() -> void:
	if game.gameplay_tween != null:
		game.gameplay_tween.pause()
		game.gameplay_tween.custom_step(0.5)

func test_startup_and_setup() -> bool:
	check(game.view == "main_menu" and game.ui.overlay.visible, "launch opens main menu")
	check(not game.ui.hud.visible and not game.can_interact(), "no gameplay behind main menu")
	for mode in ["Versus", "Battle Royale"]:
		var action = "setup_versus" if mode == "Versus" else "setup_battle"
		press_page_button(action)
		await process_frame
		check(game.view == "setup" and game.ui.setup_mode == mode, "mode-specific setup")
		var before = game.engine.state.snapshot()
		check(not game.click_at_screen(screen(Vector2i(4, 8), 0.45)), "setup blocks board")
		check(game.engine.state.snapshot() == before, "setup does not mutate previous match")
		press_page_button("start")
		await process_frame
		var count = 2 if mode == "Versus" else 4
		check(game.engine.state.players.size() == count and game.ui.cards.size() == count, "participating cards only")
		check(game.engine.state.players.all(func(p): return p.controller == "Human"), "local human seats")
		check(game.engine.state.players.all(func(p): return p.walls_remaining == (10 if count == 2 else 5)), "mode inventory")
		check(not game.engine.state.paused and game.view == "game", "started match ready")
		game.handle_ui_action("main_menu")
		await process_frame
	return true

func test_cards_and_timer() -> bool:
	start_mode("Battle Royale")
	game.update_elapsed(1.25)
	game.update_hud()
	check(is_equal_approx(game.elapsed_turns[0], 1.25), "active timer advances")
	check(game.ui.cards[0].timer.text == "28.8s", "default Battle Royale countdown displayed; engine retains elapsed time")
	check(game.ui.cards[0].active and game.ui.cards[0].style.border_color == game.ui.GOLD, "gold active border")
	for id in [2, 1, 3]:
		check(not game.ui.cards[id].active and game.elapsed_turns[id] == 0.0, "inactive cards stay idle")
	check(move_current(), "move advances turn")
	check(game.elapsed_turns[2] == 0.0 and game.elapsed_turns[0] == 1.25, "incoming timer resets; outgoing time retained")
	game.update_elapsed(2.0)
	check(game.elapsed_turns[2] == 2.0, "next player timer advances")
	check(game.ui.cards[2].active and not game.ui.cards[0].active, "active border transfers")
	for index in range(3):
		check(move_current(), "complete clockwise cycle")
	check(game.engine.state.current_player == 0 and game.elapsed_turns[0] == 0.0, "timer resets on a player's next turn")
	var wall_screen = game.camera.unproject_position(Vector3(0.5, 0.12, 0.5))
	check(game.click_at_screen(wall_screen), "place wall from HUD test")
	check(game.ui.cards[0].walls.text == "4", "wall icon count updates")
	return true

func test_menu_pause_settings() -> bool:
	start_mode("Versus")
	await process_frame
	click(game.ui.hamburger.get_global_rect().get_center())
	await process_frame
	check(game.ui.menu.visible and not game.can_interact(), "hamburger blocks board while expanded")
	var before = game.engine.state.snapshot()
	game.click_at_screen(screen(Vector2i(4, 8), 0.45))
	check(game.engine.state.snapshot() == before, "menu prevents click-through")
	var pause = game.ui.menu.find_child("Pause", true, false)
	click(pause.get_global_rect().get_center())
	await process_frame
	check(game.view == "pause" and game.engine.state.paused, "menu pause uses engine flag")
	before = game.engine.state.snapshot()
	var times = game.elapsed_turns.duplicate()
	game._process(10.0)
	check(game.elapsed_turns == times and game.engine.state.snapshot() == before, "paused timer and state freeze")
	check(not game.click_at_screen(screen(Vector2i(4, 8), 0.45)), "paused mouse rejected")
	game.set_camera_view("cinematic", false)
	check(game.camera.position == game.camera_positions.cinematic, "camera available while paused")
	press_page_button("resume")
	await process_frame
	check(game.view == "game" and not game.engine.state.paused, "resume via pause UI")
	game.handle_ui_action("settings")
	await process_frame
	check(game.engine.state.paused and game.view == "settings", "in-match settings pause")
	var music_node = game.audio.music
	game.ui.volume_sliders.music.value = 0.0
	game.ui.volume_sliders.effects.value = 0.0
	check(game.audio.music.volume_db == -80 and game.audio.effects.move.volume_db == -80, "volume sliders immediately mute")
	press_page_button("settings_back")
	await process_frame
	check(not game.engine.state.paused and game.view == "game", "settings return resumes game")
	game.handle_ui_action("main_menu")
	game.handle_ui_action("settings")
	check(game.ui.volume_sliders.music.value == 0.0 and game.ui.volume_sliders.effects.value == 0.0, "volumes persist across pages")
	check(game.audio.music == music_node and (game.audio.music.playing or not game.audio.playback_enabled), "music is not recreated or restarted across menus")
	game.set_volume("music", 0.2)
	game.set_volume("effects", 0.5)
	return true

func test_animations() -> bool:
	start_mode("Versus", true)
	var old = game.pawn_nodes[0].global_position
	check(move_current(), "animated move accepted")
	check(game.animation_busy and game.engine.state.players[0].position != Vector2i(4, 8), "engine commits before animation")
	check(game.pawn_nodes[0].global_position == old, "pawn starts at old visual position")
	var before = game.engine.state.snapshot()
	check(not game.click_at_screen(screen(Vector2i(4, 0), 0.45)), "animation blocks conflicting actions")
	game.update_elapsed(5.0)
	check(game.elapsed_turns[1] == 0.0, "transition time not charged")
	game.gameplay_tween.pause()
	game.gameplay_tween.custom_step(0.1)
	check(game.pawn_nodes[0].global_position != old, "pawn translates smoothly")
	game.pause_match(true)
	var held = game.pawn_nodes[0].global_position
	await process_frame
	check(game.pawn_nodes[0].global_position == held and not game.gameplay_tween.is_running(), "pause freezes transition")
	game.pause_match(false)
	finish_animation()
	check(not game.animation_busy and game.engine.state.snapshot() == before, "animation ends without changing rules state")
	var square: Vector2i = game.engine.state.players[0].position
	check(game.pawn_nodes[0].global_position.is_equal_approx(game.get_node("Board").cell_position(square)), "pawn settles at authoritative position")
	check(is_zero_approx(game.get_node("Board").active_ring.transparency), "gold transition completes")
	var wall_screen = game.camera.unproject_position(Vector3(0.5, 0.12, 0.5))
	check(game.click_at_screen(wall_screen), "animated wall accepted")
	check(game.wall_nodes[Vector3i(4, 4, 0)].position.y > 0, "wall begins above groove")
	finish_animation()
	check(is_zero_approx(game.wall_nodes[Vector3i(4, 4, 0)].position.y), "wall settles into groove")
	check(move_current(), "start transition before restart")
	game.restart_match()
	await process_frame
	check(not game.animation_busy and game.engine.state.history.is_empty(), "restart cancels pending transitions")
	check(game.pawn_nodes[0].position == Vector3(0, 0, 4), "restart restores visual position")
	check(move_current(), "transition before disabling animations")
	game.handle_ui_action("settings")
	game.set_animations(false)
	check(not game.animation_busy, "Animations Off completes an interrupted transition")
	check(game.ui.cards[1].style.border_color == game.ui.GOLD, "Animations Off completes card highlight")
	game.handle_ui_action("settings_back")
	check(not game.engine.state.paused and game.view == "game", "resume after disabling animations")
	return true

func test_victory() -> bool:
	start_mode("Versus", true)
	var original_audio = game.audio
	var recorder = AudioRecorder.new()
	game.add_child(recorder)
	game.audio = recorder
	game.engine.state.players[0].position = Vector2i(2, 1)
	game.sync_scene()
	game.click_at_screen(screen(Vector2i(2, 1), 0.45))
	check(game.click_at_screen(screen(Vector2i(2, 0))), "winning move accepted")
	game.update_elapsed(10)
	check(game.elapsed_turns[0] == 0.0 and game.view == "game", "clock stops immediately; overlay awaits animation")
	finish_animation()
	check(game.view == "victory" and game.ui.victory_buttons.size() == 2, "victory has exactly two main buttons")
	check(game.ui.winner_text.text == "SAPPHIRE WINS!", "winner appears once on sticker banner")
	check(recorder.events == ["move", "victory"], "winning move and single victory audio")
	game.sync_scene()
	check(recorder.events == ["move", "victory"], "repeated scene sync does not repeat victory sound")
	var before = game.engine.state.snapshot()
	game.click_at_screen(screen(Vector2i(4, 0), 0.45))
	check(game.engine.state.snapshot() == before, "victory overlay blocks actions")
	check(game.pawn_nodes[0].position == Vector3(-2, 0, -4), "final board preserved behind victory")
	game.audio = original_audio
	recorder.free()
	await process_frame
	click(game.ui.victory_buttons[0].get_global_rect().get_center())
	await process_frame
	check(game.view == "game" and game.engine.state.winner == -1, "Play Again starts same mode")
	check(game.engine.state.config.mode == "Versus", "replay preserves mode")
	for player in range(4):
		var config = Config.for_mode("Battle Royale")
		config.controllers.fill("Human")
		game.start_match(config)
		game.engine.state.winner = player
		game.engine.state.status = "finished"
		game.sync_scene()
		check(game.ui.winner_text.text == Config.IDENTITIES[player].to_upper() + " WINS!", "correct victory identity")
		check(game.ui.victory_art.get_child(0).texture.resource_path.contains(game.ui.ART_NAMES[player]), "correct color artwork")
	start_mode("Versus", true)
	game.engine.state.players[0].position = Vector2i(2, 1)
	game.sync_scene()
	game.click_at_screen(screen(Vector2i(2, 1), 0.45))
	game.click_at_screen(screen(Vector2i(2, 0)))
	game.handle_ui_action("settings")
	game.set_animations(false)
	game.handle_ui_action("settings_back")
	game._process(0.0)
	check(game.view == "victory", "interrupted winning animation still presents victory")
	return true

func test_restart_and_main_menu() -> bool:
	start_mode("Battle Royale", true)
	move_current()
	game.handle_ui_action("main_menu")
	await process_frame
	check(game.view == "main_menu" and not game.animation_busy, "main menu cancels animation")
	check(game.engine.state.paused and not game.ui.hud.visible, "main menu freezes old match and hides cards")
	game.handle_ui_action("setup_versus")
	game.handle_ui_action("start")
	check(game.ui.cards.size() == 2 and game.elapsed_turns == [0.0, 0.0], "new mode clears cards and timers")
	game.update_elapsed(1.0)
	game.pause_match(true)
	await process_frame
	press_page_button("restart")
	await process_frame
	check(game.view == "game" and not game.engine.state.paused and game.elapsed_turns == [0.0, 0.0], "pause restart resets timer and pause")
	return true

func test_responsive_cameras() -> bool:
	# A SubViewport provides real logical resize events under the dummy display.
	# Root Window coordinates can remain stretched at the project base resolution.
	var original = game
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	root.add_child(viewport)
	game = Scene.instantiate()
	game.settings_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.screen_transitions_enabled = false
	viewport.add_child(game)
	game.set_process(false)
	start_mode("Battle Royale")
	for size in [Vector2i(1280, 900), Vector2i(800, 600), Vector2i(640, 480)]:
		viewport.size = size
		await process_frame
		await process_frame
		for card in game.ui.cards.values():
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(card.panel.get_global_rect()), "card stays in viewport " + str(size) + " " + str(card.panel.get_global_rect()))
			check(not card.panel.get_global_rect().intersects(game.ui.hamburger.get_global_rect()), "cards do not overlap hamburger")
		for view in ["classic", "isometric", "cinematic"]:
			game.set_camera_view(view, false)
			check(game.camera.position == game.camera_positions[view], "camera positions preserved")
			check(game.camera.size == game.camera_sizes[view], "camera sizes preserved")
		game.engine.state.winner = 0
		game.engine.state.status = "finished"
		game.sync_scene()
		await process_frame
		await process_frame
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(game.ui.page_panel.get_global_rect()), "victory fits viewport")
		var text = game.ui.winner_text
		var font_size = text.get_theme_font_size("font_size")
		check(text.get_theme_font("font").get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= text.size.x, "victory name fits banner")
		start_mode("Battle Royale")
	viewport.free()
	game = original
	await process_frame
	return true

func test_complete_matches() -> bool:
	for mode in ["Versus", "Battle Royale"]:
		start_mode(mode, true)
		for turn in range(100):
			var player = game.engine.state.current_player
			var moves = game.engine.legal_moves()
			moves.sort_custom(func(a, b):
				return game.engine.Paths.distance(a, player, game.engine.state.walls) \
					< game.engine.Paths.distance(b, player, game.engine.state.walls))
			game.click_at_screen(screen(game.engine.state.players[player].position, 0.45))
			check(game.click_at_screen(screen(moves[0])), mode + " full-match action")
			finish_animation()
			check(not game.animation_busy, "full-match transition completed")
			if game.engine.state.winner >= 0:
				break
		check(game.view == "victory" and game.ui.victory_buttons.size() == 2, mode + " opening-to-victory flow")
		game.restart_match()
		check(game.engine.state.config.mode == mode and game.engine.state.history.is_empty(), mode + " replay flow")
	return true
