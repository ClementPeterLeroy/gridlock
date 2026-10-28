extends SceneTree

const Config = preload("res://scripts/core/match_config.gd")
const GameEngine = preload("res://scripts/core/game_engine.gd")
const Pathfinder = preload("res://scripts/ai/pathfinder.gd")
const AIController = preload("res://scripts/ai/ai_controller.gd")
const Scene = preload("res://scenes/game.tscn")

class FixedRandom extends RefCounted:
	func randi_range(_low: int, high: int) -> int:
		return high
	func randf_range(low: float, _high: float) -> float:
		return low
	func randf() -> float:
		return 0.1

var checks = 0
var failures = 0
var game
var decisions_us: Array = []
var worst_step_us = 0
var worst_frame_us = 0
var wall_count = 0
var completed_matches = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for method in ["test_python_parity", "test_legality_and_tactics", "test_scheduling", "test_complete_matches"]:
		check(call(method) == true, method + " completed")
	game = Scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for method in ["test_setup", "test_scene_scheduling"]:
		check(await call(method) == true, method + " completed")
	game.free()
	await create_timer(0.1).timeout
	var total = 0.0
	for value in decisions_us:
		total += value
	print("AI BENCHMARK: %d matches, %d decisions, %d walls; mean %.3f ms, max %.3f ms; max step %.3f ms, max slice %.3f ms" % [
		completed_matches, decisions_us.size(), wall_count, total / max(1, decisions_us.size()) / 1000.0,
		float(decisions_us.max()) / 1000.0 if not decisions_us.is_empty() else 0.0,
		worst_step_us / 1000.0, worst_frame_us / 1000.0])
	print("AI TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func complete(search) -> Dictionary:
	for index in range(300):
		if search.done:
			break
		search.step()
	check(search.done, "search completes within its bounded candidate list")
	worst_step_us = maxi(worst_step_us, search.max_step_us)
	return search.best_action

func ai_config(mode: String, level: String = "Challenging"):
	var config = Config.for_mode(mode)
	config.controllers.fill("AI - " + level)
	return config

func fixture_engine(fixture):
	var engine = GameEngine.new(ai_config(fixture.mode, fixture.difficulty))
	engine.state.current_player = int(fixture.current_player)
	for id in range(fixture.pawns.size()):
		var position = fixture.pawns[id]
		engine.state.players[id].position = null if position == null else Vector2i(int(position[0]), int(position[1]))
		engine.state.players[id].walls_remaining = int(fixture.walls_left[id])
		engine.state.players[id].eliminated = float(id) in fixture.eliminated
	for wall in fixture.walls:
		engine.state.walls[Vector3i(int(wall[0]), int(wall[1]), 0 if wall[2] == "H" else 1)] = true
	return engine

func test_python_parity() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai/python_ai_parity.json"))
	check(data is Dictionary, "AI parity fixtures load")
	if not data is Dictionary:
		return false
	for fixture in data.fixtures:
		var engine = fixture_engine(fixture)
		var before = engine.state.snapshot()
		var search = Pathfinder.new(engine.state, fixture.difficulty, FixedRandom.new(), fixture.time_limit)
		var actual = complete(search)
		var expected: Dictionary = fixture.expected.duplicate()
		if not expected.is_empty():
			expected.player_id = int(expected.player_id)
			if expected.kind == "move":
				expected.destination = Vector2i(int(expected.destination[0]), int(expected.destination[1]))
			else:
				expected.anchor = Vector2i(int(expected.anchor[0]), int(expected.anchor[1]))
		check(actual == expected, "Python decision parity: " + fixture.name + " actual=" + str(actual) + " expected=" + str(expected))
		check(engine.state.snapshot() == before, "search never mutates state")
	return true

func test_legality_and_tactics() -> bool:
	for player in range(4):
		for level in ["Casual", "Challenging"]:
			var engine = GameEngine.new(ai_config("Battle Royale", level))
			engine.state.current_player = player
			var random = RandomNumberGenerator.new()
			random.seed = 71 + player
			var search = Pathfinder.new(engine.state, level, random)
			while not search.done:
				search.step()
				if not search.best_action.is_empty():
					check(engine.validate_action(search.best_action).accepted, "every incremental proposal is legal")
			engine.state.players[player].walls_remaining = 0
			var action = complete(Pathfinder.new(engine.state, level, random))
			check(action.kind == "move" and engine.validate_action(action).accepted, "empty inventory never proposes a wall")
	var engine = GameEngine.new(ai_config("Versus"))
	var search = Pathfinder.new(engine.state)
	search.step()
	search.cancel()
	search.step()
	check(search.cancelled and search.done and search.best_action.is_empty(), "cancel discards proposals")
	return true

func test_scheduling() -> bool:
	var engine = GameEngine.new(ai_config("Versus"))
	var controller = AIController.new(engine)
	controller.update(0.25)
	controller.update(0.25)
	controller.update(0.25)
	check(engine.state.history.is_empty(), "one-second presentation prevents early action")
	engine.set_paused(true)
	var before = engine.state.snapshot()
	var age = controller.age
	controller.update(100.0)
	check(controller.age == age and engine.state.snapshot() == before, "pause freezes search age and execution")
	engine.set_paused(false)
	for frame in range(100):
		var outcome = controller.update(0.25)
		if outcome.get("accepted", false):
			break
	check(engine.state.history.size() == 1, "AI executes via engine after delay")
	check(controller.age >= 1.0 and controller.age <= 10.25, "presentation and search budget bounded")
	controller.cancel()
	controller.update(0.0, 0.001)
	var old_search = controller.search
	engine.restart()
	controller.update(0.0, 0.001)
	check(old_search.cancelled and controller.search != old_search, "restart invalidates stale search")
	controller.cancel()
	controller.thinking_limit = 1000.0
	controller.update(0.0)
	check(controller.search.time_limit == 10.0, "hard ten-second search cap")
	controller.search.best_action = {"kind": "move", "player_id": engine.state.current_player, "destination": Vector2i(-1, -1)}
	controller.search.done = true
	before = engine.state.snapshot()
	var outcome = controller.update(1.0)
	check(not outcome.accepted and engine.state.snapshot() == before, "engine rejects invalid AI proposal atomically")
	for frame in range(5):
		check(controller.update(1.0).is_empty(), "rejected proposal is not retried forever")
	controller.cancel()
	check(controller.search == null and controller.token.is_empty(), "explicit cancellation drops pending work")
	controller.update(0.0, 0.001)
	check(not controller.search.done and engine.state.history.is_empty(), "search yields before completing, keeping the main thread available")
	var pending = controller.search
	engine.forfeit(engine.state.current_player)
	controller.update(1.0)
	check(pending.cancelled and controller.search == null, "match end cancels pending AI")
	engine = GameEngine.new(ai_config("Versus"))
	controller = AIController.new(engine)
	var fallback = controller.update(10.0)
	check(fallback.get("accepted", false) and controller.search.done, "expired search budget executes a validated fallback")
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai/python_ai_parity.json"))
	for fixture in fixtures.fixtures:
		if fixture.name == "no_legal_action_Challenging":
			engine = fixture_engine(fixture)
			controller = AIController.new(engine)
			controller.update(1.0)
			check(controller.blocked and controller.feedback == "No legal AI action available.", "undefined no-action position stops searching safely")
			before = engine.state.snapshot()
			controller.update(20.0)
			check(engine.state.snapshot() == before, "no-action position invents no pass or loss rule")
	return true

func test_complete_matches() -> bool:
	for mode in ["Versus", "Battle Royale"]:
		for level in ["Casual", "Challenging", "Mixed"]:
			for seed_value in range(2):
				var config = ai_config(mode, "Casual" if level == "Mixed" else level)
				if level == "Mixed":
					for id in range(config.controllers.size()):
						config.controllers[id] = "AI - Casual" if id % 2 == 0 else "AI - Challenging"
				var engine = GameEngine.new(config)
				var random = RandomNumberGenerator.new()
				random.seed = 137 + seed_value
				var scheduler = AIController.new(engine, random)
				scheduler.presentation_delay = 0.0
				for turn in range(400):
					var started = Time.get_ticks_usec()
					var outcome: Dictionary = {}
					for frame in range(300):
						outcome = scheduler.update(0.016)
						worst_frame_us = maxi(worst_frame_us, scheduler.last_frame_us)
						if not outcome.is_empty():
							break
					decisions_us.append(Time.get_ticks_usec() - started)
					if scheduler.search != null:
						worst_step_us = maxi(worst_step_us, scheduler.search.max_step_us)
					check(outcome.get("accepted", false), mode + " " + level + " legal full-match action")
					if not outcome.get("accepted", false):
						break
					if outcome.action.kind == "wall":
						wall_count += 1
					if engine.state.status == "finished":
						break
				check(engine.state.winner >= 0, mode + " " + level + " completes within 400 turns")
				if engine.state.winner >= 0:
					completed_matches += 1
	return true

func test_setup() -> bool:
	for mode in ["Versus", "Battle Royale"]:
		game.handle_ui_action("setup_versus" if mode == "Versus" else "setup_battle")
		await process_frame
		var count = 2 if mode == "Versus" else 4
		check(game.ui.controller_options.size() == count, "one controller selector per participating seat")
		var combinations = int(pow(3, count))
		for number in range(combinations):
			var value = number
			var expected: Array = []
			for id in range(count):
				var choice = value % 3
				value = int(value / 3)
				game.ui.controller_options[id].select(choice)
				game.ui.controller_options[id].item_selected.emit(choice)
				expected.append(Config.CONTROLLERS[choice])
			check(game.ui.setup_controllers == expected, "independent controller/difficulty choices")
		# Start with AI in the first seat: human player zero is never assumed.
		game.handle_ui_action("start")
		check(game.engine.state.players.all(func(p): return p.controller == "AI - Challenging"), "all-AI setup reaches live match")
		check(not game.can_interact(), "AI turn blocks human board input")
	return true

func test_scene_scheduling() -> bool:
	game.set_animations(false)
	game.set_volume("effects", 0.0)
	game.start_match(ai_config("Battle Royale"))
	game._process(0.25)
	check(game.ui.feedback.text.contains("thinking"), "thinking indication in compact HUD")
	check(game.elapsed_turns[0] == 0.25, "AI elapsed timer starts immediately")
	game.handle_ui_action("settings")
	game._process(20)
	check(game.ai.age == 0.25 and game.engine.state.history.is_empty(), "settings freezes pending AI")
	game.handle_ui_action("settings_back")
	check(game.view == "game" and not game.engine.state.paused, "settings returns to the pending turn")
	var before = game.engine.state.snapshot()
	game.pause_match(true)
	game._process(20)
	check(game.engine.state.history.is_empty(), "paused AI performs no action")
	check(game.ai.age == 0.25, "pause retains AI presentation age")
	game.set_camera_view("cinematic", false)
	check(game.camera.position == game.camera_positions.cinematic, "camera responsive during AI pause")
	game.pause_match(false)
	var old_search = game.ai.search
	game.restart_match()
	check(old_search.cancelled and game.ai.search == null, "scene restart cancels pending AI")
	game._process(0.25)
	old_search = game.ai.search
	game.show_main_menu()
	game._process(20)
	check(old_search.cancelled and game.engine.state.history.is_empty(), "main menu cancels AI execution")
	game.start_match(ai_config("Battle Royale"))
	for frame in range(500):
		game._process(0.25)
		await process_frame
		if game.engine.state.history.size() >= 4:
			break
	check(game.engine.state.history.size() >= 4, "all-AI scene advances through four seats")
	check(game.ui.cards[game.engine.state.current_player].active, "AI retains golden active card")
	game.engine.undo()
	game.sync_scene()
	for frame in range(500):
		game._process(0.25)
		await process_frame
		if game.engine.state.history.size() >= 4:
			break
	check(game.engine.state.history.size() >= 4, "AI resumes safely after engine undo")
	game.start_match(ai_config("Versus"))
	game.engine.state.players[0].position = Vector2i(2, 1)
	game.sync_scene()
	game._process(1.0)
	check(game.view == "victory" and game.engine.state.winner == 0, "AI win uses existing victory flow")
	before = game.engine.state.snapshot()
	game._process(100)
	check(game.engine.state.snapshot() == before, "AI stops after victory")
	for first in ["Human", "AI - Casual"]:
		var config = Config.for_mode("Versus")
		config.controllers = [first, "AI - Casual" if first == "Human" else "Human"]
		game.start_match(config)
		game.ai.presentation_delay = 0.0
		game.ai.thinking_limit = 0.0
		check(game.can_interact() == (first == "Human"), "mixed match input follows seat ownership")
		if first == "Human":
			game.engine.apply_action({"kind": "move", "player_id": 0, "destination": Vector2i(4, 7)})
			game.sync_scene()
		game._process(0.016)
		check(game.engine.state.current_player == (0 if first == "Human" else 1), "AI hands mixed match back to human")
		check(game.can_interact(), "human interaction resumes after AI action")
	return true
