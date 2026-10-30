extends SceneTree
## Deterministic timing, Classic parity, and actual HUD/session integration.

const Config = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")
const AI = preload("res://scripts/ai/ai_controller.gd")
const Scene = preload("res://scenes/game.tscn")

class FakeClock extends RefCounted:
	var seconds = 0.0
	func now() -> float:
		return seconds

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
	test_python_parity()
	test_live_boundaries()
	test_ai_clocks()
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
	await test_setup_and_hud()
	test_session_lifecycle()
	game.free()
	await create_timer(0.1).timeout
	print("TIMING TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func options(mode: String, limit: int = 0):
	var config = Config.for_mode(mode)
	config.controllers.fill("Human")
	config.turn_limit = limit
	return config

func move(player: int, target: Vector2i) -> Dictionary:
	return {"kind": "move", "player_id": player, "destination": target}

func equivalent(actual, expected) -> bool:
	if actual is float or actual is int:
		return (expected is float or expected is int) and is_equal_approx(float(actual), float(expected))
	if actual is Array:
		if not expected is Array or actual.size() != expected.size():
			return false
		for index in range(actual.size()):
			if not equivalent(actual[index], expected[index]):
				return false
		return true
	return actual == expected

func normalized(state) -> Dictionary:
	var pawns: Array = []
	var walls: Array = []
	var left: Array = []
	for player in state.players:
		pawns.append(null if player.position == null else [player.position.x, player.position.y])
		left.append(player.walls_remaining)
	for wall in state.walls:
		walls.append([wall.x, wall.y, "H" if wall.z == 0 else "V"])
	walls.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and
		(a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	return {"turn_elapsed": state.turn_elapsed, "turn_clock_elapsed": state.turn_clock_elapsed,
		"time_left": state.time_left, "penalty_used": state.penalty_used, "overtime": state.overtime,
		"remaining": null if is_inf(state.remaining_turn_time) else state.remaining_turn_time,
		"current_player": state.current_player, "winner": state.winner, "pawns": pawns,
		"walls_left": left, "walls": walls, "active": state.active_players(),
		"paused": state.paused, "history_size": state.history.size()}

func test_python_parity() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/core/python_timing_parity.json"))
	check(data is Dictionary, "timing fixtures load")
	if not data is Dictionary:
		return
	var states = 0
	for trace in data.traces:
		# Versus is now expressly untimed. Retain every legacy countdown check
		# through the existing two-player engine mode, without changing fixtures.
		var mode = "Rise of the Machines" if trace.mode == "Versus" and trace.limit > 0 else trace.mode
		var config = options(mode, int(trace.limit))
		config.blitz_minutes = int(trace.minutes)
		var engine = MatchEngine.new(config)
		for step in trace.steps:
			var op = step.op
			var accepted = null
			match op.kind:
				"tick": engine.tick(op.seconds, op.get("charge", op.seconds))
				"pause": engine.set_paused(op.value)
				"next": engine.advance_turn()
				"undo": accepted = engine.undo().accepted
				"move": accepted = engine.apply_action(move(engine.state.current_player, Vector2i(int(op.target[0]), int(op.target[1])))).accepted
				"wall": accepted = engine.apply_action({"kind": "wall", "player_id": engine.state.current_player,
					"anchor": Vector2i(int(op.target[0]), int(op.target[1])), "orientation": op.target[2]}).accepted
				"set":
					for key in op.values:
						if key in ["pawns", "walls_left"]:
							for id in range(op.values[key].size()):
								if key == "pawns":
									engine.state.players[id].position = Vector2i(int(op.values[key][id][0]), int(op.values[key][id][1]))
								else:
									engine.state.players[id].walls_remaining = int(op.values[key][id])
						else:
							engine.state.set(key, op.values[key].duplicate() if op.values[key] is Array else op.values[key])
			var actual = normalized(engine.state)
			for key in step.state:
				check(equivalent(actual[key], step.state[key]), "%s %s parity %s: %s / %s" % [trace.name, op.kind, key, actual[key], step.state[key]])
			if step.has("accepted") and step.accepted != null:
				check(accepted == step.accepted, trace.name + " action acceptance parity")
			states += 1
	print("TIMING PARITY: %d Classic traces, %d states" % [data.traces.size(), states])

func test_live_boundaries() -> void:
	for mode in ["Versus", "Battle Royale", "Blitz"]:
		var engine = MatchEngine.new(options(mode, 15))
		var clock = FakeClock.new()
		engine.set_time_source(clock.now)
		clock.seconds = 2.0
		engine.poll_time()
		check(engine.state.turn_elapsed == 2, "monotonic source charges active seat")
		engine.set_paused(true)
		var before = engine.state.snapshot()
		clock.seconds += 1000
		engine.poll_time()
		check(engine.state.snapshot() == before, "paused clock cannot expire")
		engine.set_paused(false)
		clock.seconds += 1
		engine.poll_time()
		check(engine.state.turn_elapsed == 3, "resume discards paused interval")
		engine.set_timing_active(false)
		clock.seconds += 1000
		engine.set_timing_active(true)
		check(engine.state.turn_elapsed == 3, "presentation suspension excludes animation time")
		var saved = engine.state.snapshot()
		check(engine.apply_action(move(0, Vector2i(4, 7))).accepted, "live action accepted before timeout")
		clock.seconds += 5
		engine.undo()
		check(engine.state.snapshot() == saved, "undo restores complete engine clock snapshot")
		engine.poll_time()
		check(engine.state.turn_elapsed == 3, "undo reanchors wall clock")
		engine.restart()
		check(engine.state.time_left.all(func(t): return t == 180.0) and engine.state.turn_elapsed == 0, "restart resets clocks")
	for goal_first in [false, true]:
		var engine = MatchEngine.new(options("Rise of the Machines", 15))
		var clock = FakeClock.new()
		engine.set_time_source(clock.now)
		engine.state.players[0].position = Vector2i(2, 1)
		clock.seconds = 14.999 if goal_first else 15.0
		var outcome = engine.apply_action(move(0, Vector2i(2, 0)))
		check(outcome.accepted == goal_first and engine.state.winner == (0 if goal_first else 1), "expiry before action has priority; earlier goal wins")
		var saved = engine.state.snapshot()
		clock.seconds += 100
		engine.poll_time()
		check(engine.state.snapshot() == saved, "victory freezes clocks")
	var blitz = MatchEngine.new(options("Blitz"))
	var clock = FakeClock.new()
	blitz.set_time_source(clock.now)
	blitz.state.time_left[0] = 1.0
	clock.seconds = 1.0
	var rejected = blitz.apply_action({"kind": "wall", "player_id": 0, "anchor": Vector2i(-1, 0), "orientation": "H"})
	check(not rejected.accepted and blitz.state.penalty_used and blitz.state.players[0].walls_remaining == 9, "real expiry charges one penalty even if action is invalid")
	var before = blitz.state.snapshot()
	check(not blitz.apply_action(move(0, Vector2i(-1, -1))).accepted and blitz.state.snapshot() == before, "rejected action consumes no further penalty")
	clock.seconds = 16.0
	check(not blitz.apply_action(move(0, Vector2i(4, 7))).accepted and blitz.state.winner == 1, "overtime expiry beats player event")

func test_ai_clocks() -> void:
	for mode in ["Rise of the Machines", "Battle Royale", "Blitz"]:
		var config = options(mode, 15)
		config.controllers.fill("AI - Challenging")
		var engine = MatchEngine.new(config)
		engine.tick(0.75)
		engine.tick(0.5)
		check(engine.state.turn_elapsed == 1.25 and engine.state.turn_clock_elapsed == 0, "AI elapsed advances without countdown charging")
		if mode == "Blitz":
			check(engine.state.time_left[0] == 180.0, "AI thinking leaves its Blitz clock unchanged")
			check(engine.state.time_left[1] == 180.0, "AI thinking never charges the other player's clock")
		else:
			check(is_inf(engine.state.remaining_turn_time), "AI has no countdown deadline")
		var scheduler = AI.new(engine)
		scheduler.update(0.0, 0.001)
		check(scheduler.search.time_limit <= minf(10.0, engine.state.remaining_turn_time), "search budget bounded by remaining clock")
		var pending = scheduler.search
		engine.tick(1000)
		check(engine.state.status == "running" and not engine.state.players[0].eliminated and engine.state.turn_clock_elapsed == 0, "AI cannot expire during long thinking")
		# Retain stale-work cancellation coverage: an external change to a human
		# seat followed by its timeout must invalidate the pending AI proposal.
		engine.state.players[0].controller = "Human"
		if mode == "Blitz":
			engine.state.players[0].walls_remaining = 0
		engine.tick(1000)
		var position = engine.state.snapshot()
		scheduler.update(0.0, 0.001)
		check(pending.cancelled and engine.state.snapshot() == position, "human timeout invalidates stale AI before it can act")
		if mode == "Battle Royale":
			check(engine.state.current_player == 2, "four-player timeout retains clockwise IDs")
		engine.restart()
		engine.state.players[0].controller = "Human"
		engine.tick(0.5)
		check(engine.state.turn_clock_elapsed == 0.5, "human receives no AI exemption")
	var blitz = MatchEngine.new(options("Blitz"))
	blitz.state.time_left[1] = 20.0
	blitz.advance_turn()
	check(blitz.state.time_left[1] == 20.0, "turn start leaves clocks above minimum unchanged")
	blitz.state.time_left[1] = 9.0
	blitz.tick(1)
	check(blitz.state.time_left[1] == 8.0, "minimum is not continuously enforced")
	var untimed = MatchEngine.new(options("Versus"))
	untimed.tick(2, -5)
	check(untimed.state.turn_elapsed == 2 and untimed.state.turn_clock_elapsed == 0, "negative explicit clock charge clamps to zero")

func test_setup_and_hud() -> void:
	for mode in ["Versus", "Battle Royale", "Blitz"]:
		game.handle_ui_action({"Versus": "setup_versus", "Battle Royale": "setup_battle", "Blitz": "setup_blitz"}[mode])
		await process_frame
		var values = [1, 3, 5] if mode == "Blitz" else ([15, 30, 60, 120, 180] if mode == "Battle Royale" else [])
		if mode == "Versus": check(game.ui.timing_option == null, "Versus exposes no countdown")
		for index in range(values.size()):
			game.ui.timing_option.select(index)
			game.ui.timing_option.item_selected.emit(index)
			check((game.ui.setup_blitz_minutes if mode == "Blitz" else game.ui.setup_turn_limit) == values[index], "setup timing option applies")
		game.handle_ui_action("start")
		check(game.engine.state.config.mode == mode, "timed setup starts correct mode")
		game._process(2.0)
		check(game.engine.state.turn_elapsed == 2.0, "scene uses engine clock")
		if mode == "Blitz":
			check(game.ui.cards[0].timer.text == "4:58.0", "Blitz card displays player clock")
			game.engine.state.time_left[0] = 1.0
			game._process(1.0)
			check(game.ui.cards[0].timer.text == "OT 0:15.0" and game.ui.cards[0].walls.text == "9", "overtime and penalty displayed compactly")
			game._process(15.0)
		elif mode == "Battle Royale":
			check(game.ui.cards[0].timer.text == "178.0s", "standard card displays countdown")
			game._process(178.0)
		else:
			game._process(10000.0)
			check(game.engine.state.status == "running" and is_inf(game.engine.state.remaining_turn_time), "Versus cannot expire")
		if mode == "Blitz":
			check(game.view == "victory" and game.ui.timeout_text != null and game.ui.timeout_text.text.contains("ran out of time"), "timeout victory names losing player")
		elif mode == "Battle Royale":
			check(not game.ui.cards[0].panel.visible and game.engine.state.current_player == 2, "eliminated card removed without renumbering")
		game.show_main_menu()
	game.start_match(options("Battle Royale", 15))
	game._process(5)
	check(game.ui.cards[0].timer.get_theme_color("font_color") == Color("#F9CD70"), "low time amber")
	game._process(5)
	check(game.ui.cards[0].timer.get_theme_color("font_color") == Color("#EF7770"), "critical time red")
	game.start_match(options("Blitz"))
	game.engine.state.time_left[0] = 59.999
	game.update_hud()
	check(game.ui.cards[0].timer.text == "1:00.0", "clock rounding never displays sixty seconds within a minute")

func test_session_lifecycle() -> void:
	for mode in ["Versus", "Battle Royale", "Blitz"]:
		game.start_match(options(mode, 15))
		game._process(1)
		game.pause_match(true)
		var before = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == before, "pause page freezes all timing")
		game.pause_match(false)
		game.handle_ui_action("settings")
		before = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == before, "settings freezes all timing")
		game.handle_ui_action("settings_back")
		game._process(1)
		check(game.engine.state.turn_elapsed == 2, "resume does not charge overlays")
		game.show_main_menu()
		before = game.engine.state.snapshot()
		game._process(1000)
		check(game.engine.state.snapshot() == before, "main menu stops timing")
		game.restart_match()
		check(game.engine.state.turn_elapsed == 0 and game.engine.state.time_left == [180.0, 180.0, 180.0, 180.0].slice(0, game.engine.state.players.size()), "replay resets initial clocks")
