extends SceneTree

const Config = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")
const Preferences = preload("res://scripts/core/match_preferences.gd")
const Scene = preload("res://scenes/game.tscn")
const TEST_PATH = "res://.godot/customization-test.cfg"

var checks = 0
var failures = 0
var game

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for method in ["test_names", "test_starters", "test_timing", "test_preferences"]:
		check(call(method) == true, method + " completed")
	game = Scene.instantiate()
	game.settings_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.screen_transitions_enabled = false
	game.live_timing = false
	game.preferences_path = ""
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_animations(false)
	game.set_volume("effects", 0.0)
	check(await test_setup() == true, "test_setup completed")
	check(test_lifecycle() == true, "test_lifecycle completed")
	game.free()
	await create_timer(0.1).timeout
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	print("CUSTOMIZATION TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func move(engine) -> Dictionary:
	return engine.apply_action({"kind": "move", "player_id": engine.state.current_player, "destination": engine.legal_moves()[0]})

func test_names() -> bool:
	for mode in Preferences.MODES:
		var config = Config.for_mode(mode)
		var engine = MatchEngine.new(config)
		for id in range(config.player_count()):
			check(engine.state.players[id].name == Config.IDENTITIES[id], "default identity names")
		config.names = ["  Alex  ", "Nova", "Nova", "abcdefghijklmnop"]
		config.controllers.fill("AI - Casual")
		engine = MatchEngine.new(config)
		check(engine.state.players[0].name == "Alex" and engine.state.players[1].name == "Nova", "AI names are editable and trimmed")
		if mode == "Battle Royale":
			check(engine.state.players[2].name == "Nova" and engine.state.players[2].id == 2, "duplicate names do not merge IDs")
			check(engine.state.players[3].name == "abcdefghijkl", "long names truncate at twelve characters")
		config.controllers.fill("Human")
		var changed = MatchEngine.new(config)
		check(changed.state.players[0].name == engine.state.players[0].name, "controller changes retain names")
		for blank in ["", " \t\n ", "<>[]"]:
			config.names[0] = blank
			var before = engine.state.snapshot()
			check(engine.start_match(config).reason_code == "invalid_name" and engine.state.snapshot() == before, "empty name rejected atomically")
	check(Config.clean_name("A\u200bB\n<[]>C") == "ABC", "controls and markup delimiters filtered")
	return true

func test_starters() -> bool:
	for mode in Preferences.MODES:
		var config = Config.for_mode(mode)
		check(MatchEngine.new(config).state.current_player == 0, "Default starts Sapphire")
		config.random_start = true
		var random = RandomNumberGenerator.new()
		random.seed = 293
		var reference = RandomNumberGenerator.new()
		reference.seed = 293
		var order = [0, 2, 1, 3] if mode == "Battle Royale" else [0, 1]
		var engine = MatchEngine.new(config, random)
		var seen: Dictionary = {}
		for trial in range(40):
			var expected = order[reference.randi_range(0, order.size() - 1)]
			check(engine.state.current_player == expected, "Random uses uniform participating-seat RNG range")
			seen[expected] = true
			engine.advance_turn()
			check(engine.state.current_player == order[(order.find(expected) + 1) % order.size()], "random start retains cyclic order")
			engine.restart()
			check(engine.state.current_player == expected and engine.state.history.is_empty(), "restart retains actual starter")
			engine.play_again()
		check(seen.size() == order.size(), "random draws reach every participating ID")
	return true

func test_timing() -> bool:
	for old_limit in [0, 15, 30, 60, 120, 999]:
		var config = Config.for_mode("Versus")
		config.turn_limit = old_limit
		config.timer_type = "Per Game"
		config.game_limit = 60
		var engine = MatchEngine.new(config)
		engine.tick(100000)
		check(engine.state.status == "running" and is_inf(engine.state.remaining_turn_time), "stale Versus timing cannot reactivate deadlines")
		check(engine.state.config.turn_limit == 0 and engine.state.config.game_limit == 0 and not engine.state.penalty_used, "Versus has no active countdown or penalty")
	for timer in Config.TIMER_TYPES:
		for duration in (Config.TURN_SECONDS if timer == "Per Turn" else Config.GAME_SECONDS):
			var config = Config.for_mode("Battle Royale")
			config.controllers.fill("Human")
			config.timer_type = timer
			if timer == "Per Turn": config.turn_limit = duration
			else: config.game_limit = duration
			var engine = MatchEngine.new(config)
			engine.tick(5)
			var saved = engine.state.snapshot()
			check(engine.state.remaining_turn_time == duration - 5, "selected Battle Royale clock consumes time")
			check(move(engine).accepted, "timed action valid")
			for id in [2, 1, 3]:
				engine.tick(1)
				check(move(engine).accepted, "complete four-player cycle")
			check(engine.state.current_player == 0 and engine.state.remaining_turn_time == (duration if timer == "Per Turn" else duration - 5), "turn clock resets, game clock retains balance")
			for count in range(4): engine.undo()
			check(engine.state.snapshot() == saved, "undo restores selected timing system")
			engine.state.walls[Vector3i(3, 3, 0)] = true
			engine.tick(duration)
			check(engine.state.players[0].eliminated and engine.state.current_player == 2 and engine.state.walls.size() == 1, "expiry eliminates stable ID and retains walls")
			check(not engine.state.penalty_used and engine.state.overtime == 0 and engine.state.players[0].walls_remaining == 5, "Battle Royale never applies Blitz penalties")
			check(engine.state.config.turn_limit == 0 if timer == "Per Game" else engine.state.config.game_limit == 0, "unselected timing system disabled")
			engine.restart()
			check(engine.state.remaining_turn_time == duration, "restart restores chosen clock")
	var config = Config.for_mode("Battle Royale")
	config.controllers.fill("Human")
	config.timer_type = "Per Game"
	var engine = MatchEngine.new(config)
	engine.state.time_left[2] = 3.0
	engine.advance_turn()
	check(engine.state.time_left[2] == 3.0, "Per Game has no ten-second floor")
	engine.tick(3)
	check(engine.state.players[2].eliminated and engine.state.current_player == 1, "Per Game zero balance immediately eliminates")
	config.controllers.fill("AI - Casual")
	engine = MatchEngine.new(config)
	engine.tick(1.25)
	check(engine.state.time_left[0] == 180.0 and engine.state.time_left[1] == 180.0, "Per Game AI turns consume neither player's clock")
	return true

func test_preferences() -> bool:
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	var prefs = Preferences.new(TEST_PATH)
	check(Preferences.DEFAULT_PATH.begins_with("user://"), "production preferences use Godot user storage")
	check(prefs.configs["Battle Royale"].turn_limit == 30 and prefs.configs["Battle Royale"].timer_type == "Per Turn", "missing file falls back to defaults")
	var config = prefs.configs["Battle Royale"]
	config.names[2] = "Orion"
	config.controllers = ["AI - Casual", "Human", "AI - Challenging", "Human"]
	config.random_start = true
	config.timer_type = "Per Game"
	config.turn_limit = 120
	config.game_limit = 600
	prefs.configs["Blitz"].blitz_minutes = 5
	check(prefs.save() == OK, "preferences saved to disk")
	var restored = Preferences.new(TEST_PATH)
	check(restored.configs["Battle Royale"].to_dict() == config.to_dict(), "fresh instance restores every setup preference")
	check(restored.configs["Blitz"].blitz_minutes == 5, "Blitz duration persists")
	var content = FileAccess.get_file_as_string(TEST_PATH)
	check(not content.contains("history") and not content.contains("time_left") and not content.contains("starting_player"), "file excludes transient match state")
	var file = ConfigFile.new()
	file.set_value("preferences", "version", 0)
	file.set_value("Versus", "turn_limit", 30)
	file.set_value("Battle Royale", "names", [" \n ", "<b>Nova</b>", false, "abcdefghijklmnop"])
	file.set_value("Battle Royale", "controllers", ["invalid", "AI - Challenging", 3, "Human"])
	file.set_value("Battle Royale", "timer_type", "obsolete")
	file.set_value("Battle Royale", "turn_limit", 0)
	file.set_value("Battle Royale", "game_limit", -60)
	file.set_value("Battle Royale", "random_start", "yes")
	file.set_value("Blitz", "blitz_minutes", 999)
	file.save(TEST_PATH)
	var migrated = Preferences.new(TEST_PATH)
	check(migrated.configs["Versus"].turn_limit == 0, "old timed Versus preferences migrate to untimed")
	check(migrated.configs["Battle Royale"].validation_error().is_empty(), "corrupt fields fall back to valid config")
	check(migrated.configs["Battle Royale"].names[0] == "Sapphire" and migrated.configs["Battle Royale"].names[3].length() == 12, "invalid names repaired and long names bounded")
	check(migrated.configs["Battle Royale"].controllers[1] == "AI - Challenging" and migrated.configs["Battle Royale"].controllers[0] == "Human", "valid controller fields survive migration")
	check(migrated.configs["Battle Royale"].turn_limit == 30 and migrated.configs["Battle Royale"].game_limit == 180, "obsolete durations repaired per timer type")
	check(not migrated.configs["Battle Royale"].random_start and migrated.configs["Blitz"].blitz_minutes == 3, "invalid starting/Blitz choices repaired")
	migrated.reset()
	migrated.save()
	check(Preferences.new(TEST_PATH).configs["Battle Royale"].names == Config.IDENTITIES, "Reset to Defaults persists")
	return true

func test_setup() -> bool:
	for mode in Preferences.MODES:
		game.handle_ui_action({"Versus": "setup_versus", "Battle Royale": "setup_battle", "Blitz": "setup_blitz"}[mode])
		await process_frame
		check(game.ui.name_inputs.size() == game.ui.setup_config.player_count(), "editable name for every participating seat")
		game.ui.name_inputs[0].text = " "
		game.ui.name_inputs[0].text_changed.emit(" ")
		check(game.ui.start_button.disabled and not game.ui.setup_error.text.is_empty(), "blank field blocks Start with feedback")
		var before = game.engine.state.snapshot()
		game.handle_ui_action("start")
		check(game.engine.state.snapshot() == before, "invalid setup cannot replace match")
		game.ui.name_inputs[0].text = "Nova"
		game.ui.name_inputs[0].text_changed.emit("Nova")
		if mode == "Versus":
			check(game.ui.controller_options.is_empty(), "Versus has no AI selectors")
		else:
			game.ui.controller_options[0].select(2)
			game.ui.controller_options[0].item_selected.emit(2)
		check(game.ui.setup_config.names[0] == "Nova" and not game.ui.start_button.disabled, "controller switch retains edited name")
		game.ui.starter_option.select(1)
		game.ui.starter_option.item_selected.emit(1)
		if mode == "Versus": check(game.ui.timing_option == null, "Versus has no timing selector")
		if mode == "Battle Royale":
			game.ui.timing_option.select(3)
			game.ui.timing_option.item_selected.emit(3)
			game.ui.timer_type_option.select(1)
			game.ui.timer_type_option.item_selected.emit(1)
			check(game.ui.timing_option.item_count == 5 and game.ui.timing_option.selected == 1, "Per Game defaults to three minutes")
			game.ui.timing_option.select(3)
			game.ui.timing_option.item_selected.emit(3)
			game.ui.timer_type_option.select(0)
			game.ui.timer_type_option.item_selected.emit(0)
			check(game.ui.setup_config.turn_limit == 120 and game.ui.timing_option.selected == 3, "Per Turn selection restored")
			game.ui.timer_type_option.select(1)
			game.ui.timer_type_option.item_selected.emit(1)
			check(game.ui.setup_config.game_limit == 600 and game.ui.timing_option.selected == 3, "Per Game selection restored")
			game.ui.setup_config.game_limit = 999
			game.ui.refresh_durations()
			check(game.ui.setup_config.game_limit == 180 and not game.ui.start_button.disabled, "invalid remembered duration falls back and revalidates Start")
		game.handle_ui_action("start")
		check(game.engine.state.players[0].name == "Nova" and game.engine.state.players[0].controller == ("Human" if mode == "Versus" else "AI - Challenging"), "complete setup reaches authoritative engine")
		check(game.ui.cards[0].name.text == "Nova", "custom AI name appears in compact HUD")
		var active = game.engine.state.snapshot()
		game.handle_ui_action("reset_preferences")
		check(game.engine.state.snapshot() == active, "reset preferences never restarts active match")
		game.show_main_menu()
		game.handle_ui_action({"Versus": "setup_versus", "Battle Royale": "setup_battle", "Blitz": "setup_blitz"}[mode])
		check(game.ui.setup_config.names == Config.IDENTITIES and not game.ui.setup_config.random_start, "reset restores default setup names and starter")
		game.show_main_menu()

	return true

func test_lifecycle() -> bool:
	var config = Config.for_mode("Battle Royale")
	config.random_start = true
	config.controllers = ["AI - Challenging", "Human", "AI - Casual", "Human"]
	config.names = ["abcdefghijkl", "Nova", "Nova", "Orion"]
	game.start_match(config)
	var retained = game.engine.state.current_player
	game._process(0.25)
	var pending = game.ai.search
	game.restart_match()
	check(game.engine.state.current_player == retained and game.engine.state.players[0].name == "abcdefghijkl", "scene Restart preserves names and starter")
	check(pending == null or pending.cancelled, "restart cancels any pending AI search")
	game.pause_match(true)
	var paused = game.engine.state.snapshot()
	game._process(1000)
	check(game.engine.state.snapshot() == paused, "custom mixed match freezes on pause")
	game.set_camera_view("classic", false)
	check(game.camera.position == game.camera_positions.classic, "camera remains available")
	game.pause_match(false)
	game.engine.state.current_player = 0
	game.engine.state.winner = 0
	game.engine.state.status = "finished"
	game.sync_scene()
	check(game.ui.winner_text.text == "ABCDEFGHIJKL WINS!", "victory uses long custom winner name")
	var control = RandomNumberGenerator.new()
	control.seed = 417
	game.engine.rng.seed = 417
	game.handle_ui_action("play_again")
	check(game.engine.state.current_player == [0, 2, 1, 3][control.randi_range(0, 3)], "Play Again draws random starter through engine")
	check(game.engine.state.players[0].name == "abcdefghijkl" and game.engine.state.config.controllers == config.controllers, "Play Again retains names and mixed difficulties")
	check(game.engine.state.config.turn_limit == 30 and game.engine.state.turn_clock_elapsed == 0 and game.engine.state.players.all(func(p): return p.walls_remaining == 5), "Play Again restores clocks and inventories")
	game.ui.setup_config.names[0] = "Changed"
	check(game.engine.state.players[0].name == "abcdefghijkl", "draft edits cannot mutate live match")
	game.show_main_menu()
	paused = game.engine.state.snapshot()
	game._process(1000)
	check(game.engine.state.snapshot() == paused and game.ai.search == null, "main menu ends AI and timing without changing preferences")
	return true
