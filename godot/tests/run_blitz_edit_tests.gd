extends "res://tests/run_timing_tests.gd"
## Reuse deterministic timing helpers and the real scene; no real-time waits.

const Preferences = preload("res://scripts/core/match_preferences.gd")
const TEST_PATH = "res://.godot/blitz-edit-preferences.cfg"

func run() -> void:
	for method in ["test_blitz_modes", "test_full_ai_exemption", "test_saved_blitz_choices"]:
		check(call(method) == true, method + " completed")
	game = Scene.instantiate()
	game.live_timing = false
	game.preferences_path = ""
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_animations(false)
	game.set_volume("effects", 0.0)
	check(await test_blitz_setup() == true, "test_blitz_setup completed")
	check(test_blitz_lifecycle() == true, "test_blitz_lifecycle completed")
	game.free()
	await create_timer(0.1).timeout
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	print("BLITZ EDIT TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func blitz(kind: String, seconds: int = 30, minutes: int = 3):
	var config = options("Blitz", seconds)
	config.timer_type = kind
	config.blitz_minutes = minutes
	return config

func test_blitz_modes() -> bool:
	check(Config.for_mode("Blitz").timer_type == "Per Game" and Config.for_mode("Blitz").blitz_minutes == 3, "Blitz defaults to Per Game, three minutes")
	for kind in Config.TIMER_TYPES:
		for value in (Config.TURN_SECONDS if kind == "Per Turn" else [1, 3, 5]):
			var config = blitz(kind, value if kind == "Per Turn" else 30, value if kind == "Per Game" else 3)
			var engine = MatchEngine.new(config)
			var initial = float(value if kind == "Per Turn" else value * 60)
			check(engine.state.remaining_turn_time == initial and engine.state.config.timing_mode == kind, "all Blitz durations initialize correctly")
			check(engine.state.config.turn_limit == 0 if kind == "Per Game" else engine.state.config.game_limit == 0, "only selected deadline is active")
			engine.tick(2)
			check(engine.state.remaining_turn_time == initial - 2, "human consumes selected countdown")
			check(engine.apply_action(move(0, Vector2i(4, 7))).accepted, "human completes first turn")
			engine.tick(1)
			check(engine.apply_action(move(1, Vector2i(4, 1))).accepted, "human completes opposing turn")
			check(engine.state.remaining_turn_time == (initial if kind == "Per Turn" else initial - 2), "Per Turn resets while Per Game accumulates")
			engine.state.time_left[1] = 2.0
			engine.advance_turn()
			check(engine.state.time_left[1] == (2.0 if kind == "Per Turn" else 10.0), "ten-second floor belongs only to Per Game")
			engine.tick(initial if kind == "Per Turn" else 10.0)
			if kind == "Per Turn":
				check(engine.state.status == "finished" and engine.state.winner == 0 and engine.state.players[1].eliminated, "Per Turn timeout uses standard forfeit")
				check(engine.state.players[1].walls_remaining == 10 and not engine.state.penalty_used and engine.state.overtime == 0, "Per Turn has no wall penalty or overtime")
			else:
				check(engine.state.status == "running" and engine.state.players[1].walls_remaining == 9 and engine.state.overtime == 15, "Per Game preserves first penalty and fresh overtime")
				engine.tick(14)
				check(engine.state.players[1].walls_remaining == 9 and engine.state.overtime == 1, "only one penalty within turn")
				engine.tick(1)
				check(engine.state.winner == 0 and not engine.state.players[1].eliminated, "Per Game overtime retains Classic loss behavior")
			engine.restart()
			check(engine.state.remaining_turn_time == initial and engine.state.players[1].walls_remaining == 10, "restart restores selected clocks and inventory")
	var invalid = blitz("Per Turn", 0)
	check(not MatchEngine.new().start_match(invalid).accepted, "zero Per Turn duration rejected")
	return true

func test_full_ai_exemption() -> bool:
	for mode in ["Versus", "Battle Royale", "Blitz"]:
		for kind in Config.TIMER_TYPES:
			for level in ["AI - Casual", "AI - Challenging"]:
				var config = blitz(kind) if mode == "Blitz" else options(mode, 15)
				config.timer_type = kind
				for id in range(config.player_count()):
					config.controllers.fill("Human")
					config.controllers[id] = level
					var engine = MatchEngine.new(config)
					engine.state.current_player = id
					engine.state.time_left[id] = 0.0
					engine.state.players[id].walls_remaining = 0
					if engine.state.uses_blitz_clock:
						engine.state.penalty_used = true
						engine.state.overtime = 0.0
					var clocks = engine.state.time_left.duplicate()
					engine.tick(1000)
					engine.tick(1000, 1000)
					check(engine.state.turn_elapsed == 2000 and engine.state.turn_clock_elapsed == 0, "all AI seats track elapsed but never charge countdown")
					check(engine.state.status == "running" and engine.state.winner == -1 and not engine.state.players[id].eliminated, "AI cannot lose at zero clock, zero overtime or zero walls")
					check(engine.state.time_left == clocks and engine.state.overtime == 0 and engine.state.history.is_empty(), "AI ticks cannot trigger penalties or forfeit")
					check(is_inf(engine.state.remaining_turn_time), "AI reports no scheduling deadline")
					engine.set_paused(true)
					var saved = engine.state.snapshot()
					engine.tick(1000)
					check(engine.state.snapshot() == saved, "pause freezes informational AI elapsed too")
					engine.set_paused(false)
					check(engine.apply_action(move(id, engine.legal_moves()[0])).accepted, "exempt AI can complete legal action")
					check(engine.state.current_player != id and engine.state.turn_clock_elapsed == 0, "new human turn inherits no AI time")
					engine.tick(0.5)
					check(engine.state.turn_clock_elapsed == 0.5, "human after AI is charged normally")
	return true

func test_saved_blitz_choices() -> bool:
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(TEST_PATH)
	var prefs = Preferences.new(TEST_PATH)
	var config = prefs.configs["Blitz"]
	config.timer_type = "Per Turn"
	config.turn_limit = 120
	config.blitz_minutes = 5
	check(prefs.save() == OK, "Blitz timer preferences saved")
	var loaded = Preferences.new(TEST_PATH)
	check(loaded.configs["Blitz"].timer_type == "Per Turn" and loaded.configs["Blitz"].turn_limit == 120 and loaded.configs["Blitz"].blitz_minutes == 5, "fresh instance restores type and both preferred durations")
	var file = ConfigFile.new()
	file.set_value("preferences", "version", 1)
	file.set_value("Blitz", "timer_type", "Per Turn")
	file.set_value("Blitz", "turn_limit", 0)
	file.set_value("Blitz", "blitz_minutes", 5)
	file.save(TEST_PATH)
	loaded = Preferences.new(TEST_PATH)
	check(loaded.configs["Blitz"].timer_type == "Per Game" and loaded.configs["Blitz"].blitz_minutes == 5, "v1 unused timer field cannot change old global-clock matches")
	check(loaded.configs["Blitz"].turn_limit == 30, "old zero turn limit repairs to new default")
	file.set_value("preferences", "version", 2)
	file.set_value("Blitz", "timer_type", "unknown")
	file.set_value("Blitz", "turn_limit", -1)
	file.set_value("Blitz", "blitz_minutes", 15)
	file.save(TEST_PATH)
	loaded = Preferences.new(TEST_PATH)
	check(loaded.configs["Blitz"].timer_type == "Per Game" and loaded.configs["Blitz"].blitz_minutes == 3 and loaded.configs["Blitz"].turn_limit == 30, "invalid current preferences fall back safely")
	loaded.reset()
	loaded.save()
	check(Preferences.new(TEST_PATH).configs["Blitz"].timer_type == "Per Game", "reset persists Per Game default")
	return true

func test_blitz_setup() -> bool:
	game.handle_ui_action("setup_blitz")
	await process_frame
	check(game.ui.timer_type_option.selected == 1 and game.ui.timing_option.selected == 1, "setup defaults to Per Game, three minutes")
	check(game.ui.timing_option.item_count == 3, "Per Game preserves 1/3/5-minute options")
	game.ui.timing_option.select(2)
	game.ui.timing_option.item_selected.emit(2)
	game.ui.timer_type_option.select(0)
	game.ui.timer_type_option.item_selected.emit(0)
	check(game.ui.timing_option.item_count == 5 and game.ui.timing_option.selected == 1, "Per Turn reuses shared presets and thirty-second default")
	game.ui.timing_option.select(3)
	game.ui.timing_option.item_selected.emit(3)
	game.ui.timer_type_option.select(1)
	game.ui.timer_type_option.item_selected.emit(1)
	check(game.ui.timing_option.selected == 2 and game.ui.setup_config.blitz_minutes == 5, "switching back restores Per Game duration")
	game.ui.timer_type_option.select(0)
	game.ui.timer_type_option.item_selected.emit(0)
	check(game.ui.timing_option.selected == 3 and game.ui.setup_config.turn_limit == 120, "switching back restores Per Turn duration")
	game.handle_ui_action("start")
	game._process(2)
	check(game.engine.state.config.timer_type == "Per Turn" and game.ui.cards[0].timer.text == "118.0s", "selected Per Turn reaches live HUD")
	for kind in Config.TIMER_TYPES:
		var config = blitz(kind)
		config.controllers[0] = "AI - Challenging"
		game.start_match(config)
		game._process(0.25)
		check(game.ui.cards[0].timer.text == "Exempt" and game.ui.cards[0].timer.tooltip_text.contains("do not consume"), "AI HUD explicitly represents full exemption")
		check(game.ui.feedback.text.contains("thinking"), "thinking indication retained")
		game.engine.tick(1000)
		game.update_hud()
		check(game.ui.cards[0].timer.text == "Exempt" and game.engine.state.status == "running", "long AI thinking cannot show an expiring clock")
		var pending = game.ai.search
		game.pause_match(true)
		var saved = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == saved, "paused AI clock and search cannot advance")
		game.pause_match(false)
		game.restart_match()
		check(pending.cancelled and game.engine.state.turn_elapsed == 0 and is_inf(game.engine.state.remaining_turn_time), "AI restart cancels search and retains full exemption")
		game._process(0.25)
		pending = game.ai.search
		game.handle_ui_action("play_again")
		check(pending.cancelled and game.engine.state.config.timer_type == kind and game.engine.state.turn_elapsed == 0, "AI Play Again cancels search and preserves chosen timing")
	return true

func test_blitz_lifecycle() -> bool:
	for kind in Config.TIMER_TYPES:
		var config = blitz(kind)
		game.start_match(config)
		game._process(2)
		game.pause_match(true)
		var saved = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == saved, "pause freezes both Blitz timer types")
		game.pause_match(false)
		game.handle_ui_action("settings")
		saved = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == saved, "settings freezes both timer types")
		game.handle_ui_action("settings_back")
		game._process(1)
		check(game.engine.state.remaining_turn_time == (27 if kind == "Per Turn" else 177), "resume charges only active human time")
		game.restart_match()
		check(game.engine.state.remaining_turn_time == (30 if kind == "Per Turn" else 180), "scene restart restores chosen timer")
		game.engine.state.winner = 0
		game.engine.state.status = "finished"
		game.sync_scene()
		game.handle_ui_action("play_again")
		check(game.engine.state.config.timer_type == kind and game.engine.state.remaining_turn_time == (30 if kind == "Per Turn" else 180), "Play Again preserves type and resets clocks")
		game.show_main_menu()
		saved = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == saved, "main menu cancels timing")
	return true
