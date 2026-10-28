extends RefCounted

const Config = preload("res://scripts/core/match_config.gd")
const GameEngine = preload("res://scripts/core/game_engine.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Paths = preload("res://scripts/core/pathfinding.gd")

var checks = 0
var failures = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func move_action(player: int, target: Vector2i) -> Dictionary:
	return {"kind": "move", "player_id": player, "destination": target}

func wall_action(player: int, anchor: Vector2i, orientation = "H") -> Dictionary:
	return {"kind": "wall", "player_id": player, "anchor": anchor, "orientation": orientation}

func run() -> void:
	for method in ["test_initialization", "test_turns_and_elimination", "test_movement",
		"test_walls", "test_victory", "test_history_and_restart", "test_rejected_actions",
		"test_python_parity", "test_version"]:
		# A script error returns null: it must not produce a successful test run.
		check(call(method) == true, method + " completed")

func test_initialization() -> bool:
	for mode in Config.MODES:
		var config = Config.for_mode(mode)
		config.names[0] = "  Alex  "
		var engine = GameEngine.new(config)
		var count = 4 if mode == "Battle Royale" else 2
		check(engine.state.players.size() == count, mode + " player count")
		check(engine.state.board_size == Vector2i(9, 9), "board dimensions")
		for player in range(count):
			var data = engine.state.players[player]
			check(data.id == player and data.identity == Config.IDENTITIES[player], "stable identity")
			check(data.position == GameEngine.State.STARTS[player], "starting position")
			check(data.goal == GameEngine.State.GOALS[player], "goal metadata")
			check(data.walls_remaining == (5 if count == 4 else 10), "initial inventory")
		check(engine.state.players[0].name == "Alex", "trim human name")
		check(engine.state.current_player == 0 and engine.state.walls.is_empty(), "opening state")
	config_names()
	return true

func config_names() -> void:
	var config = Config.for_mode("Battle Royale")
	config.names = ["abcdefghijklmnop", "ignored", " \t\n ", "A\u200bB"]
	config.controllers = ["Human", "AI - Challenging", "Human", "Human"]
	check(config.display_name(0) == "abcdefghijkl", "12 character names")
	check(config.display_name(1) == "Crimson", "AI identity ignores custom name")
	check(config.display_name(2) == "Emerald", "blank name fallback")
	check(config.display_name(3) == "AB", "nonprintable name filtering")
	var copy = config.copy()
	copy.names[0] = "Changed"
	check(config.names[0] != copy.names[0], "independent config copy")

func test_turns_and_elimination() -> bool:
	for mode in ["Versus", "Battle Royale"]:
		var config = Config.for_mode(mode)
		var order = [0, 2, 1, 3] if mode == "Battle Royale" else [0, 1]
		for start in order:
			config.starting_player = start
			var engine = GameEngine.new(config)
			for offset in range(order.size()):
				check(engine.state.current_player == order[(order.find(start) + offset) % order.size()], "turn rotation")
				engine.advance_turn()
	var engine = GameEngine.new(Config.for_mode("Battle Royale"))
	engine.apply_action(wall_action(0, Vector2i(3, 3)))
	check(engine.forfeit(2).accepted, "forfeit current seat")
	check(engine.state.players[2].position == null and engine.state.players[2].eliminated, "pawn removed")
	check(engine.state.walls.size() == 1 and engine.state.current_player == 1, "placed walls retained, seat skipped")
	check(engine.forfeit(1).accepted and engine.forfeit(3).accepted, "further forfeits")
	check(engine.state.winner == 0 and engine.state.status == "finished", "last survivor wins")
	check(engine.undo().accepted and engine.state.winner == -1, "undo last elimination")
	check(engine.state.active_players() == [0, 3], "stable survivor IDs")
	return true

func test_movement() -> bool:
	var engine = GameEngine.new()
	check(engine.legal_moves().size() == 3, "three opening moves")
	for direction in Paths.DIRECTIONS:
		var pawns = [Vector2i(4, 4), Vector2i(4, 4) + direction]
		var moves = Rules.valid_moves(pawns, 0, {})
		check(Vector2i(4, 4) + 2 * direction in moves, "jump in each direction")
		check(pawns[1] not in moves, "cannot land on adjacent pawn")
		var behind: Vector2i = pawns[1] + direction
		pawns.append(behind)
		var occupied_moves = Rules.valid_moves(pawns, 0, {})
		check(behind not in occupied_moves, "cannot jump onto another pawn")
		var side = Vector2i(-direction.y, direction.x)
		check(pawns[1] + side in occupied_moves and pawns[1] - side in occupied_moves, "occupied landing permits sides")
	var edge = Rules.valid_moves([Vector2i(4, 1), Vector2i(4, 0)], 0, {})
	check(Vector2i(3, 0) in edge and Vector2i(5, 0) in edge, "edge sidesteps")
	var walls = {Vector3i(4, 2, 0): true, Vector3i(3, 3, 1): true}
	var side_moves = Rules.valid_moves([Vector2i(4, 4), Vector2i(4, 3)], 0, walls)
	check(Vector2i(3, 3) not in side_moves and Vector2i(5, 3) in side_moves, "blocked side route")
	check(Rules.valid_moves([null, Vector2i(4, 0)], 0, {}).is_empty(), "eliminated pawn has no moves")
	return true

func test_walls() -> bool:
	for orientation in ["H", "V"]:
		var engine = GameEngine.new()
		check(engine.apply_action(wall_action(0, Vector2i(3, 3), orientation)).accepted, "place " + orientation)
		check(engine.state.players[0].walls_remaining == 9 and engine.state.current_player == 1, "wall spends inventory and turn")
		check(engine.validate_action(wall_action(1, Vector2i(3, 3), orientation)).reason_code == "wall_overlap_or_crossing", "duplicate wall")
		var other = "V" if orientation == "H" else "H"
		check(engine.validate_action(wall_action(1, Vector2i(3, 3), other)).reason_code == "wall_overlap_or_crossing", "crossing wall")
		var offset = Vector2i(1, 0) if orientation == "H" else Vector2i(0, 1)
		for sign_value in [-1, 1]:
			check(not engine.validate_action(wall_action(1, Vector2i(3, 3) + offset * sign_value, orientation)).accepted, "partial overlap")
		check(engine.validate_action(wall_action(1, Vector2i(3, 3) + offset * 2, orientation)).accepted, "end to end walls allowed")
	for player in range(4):
		var engine = GameEngine.new(Config.for_mode("Battle Royale"))
		engine.state.current_player = player
		var positions = [Vector2i(0, 8), Vector2i(0, 0), Vector2i(0, 0), Vector2i(8, 0)]
		var existing = [Vector3i(0, 7, 0), Vector3i(0, 0, 0), Vector3i(0, 0, 0), Vector3i(7, 0, 0)]
		var closing = [Vector2i(1, 7), Vector2i(1, 0), Vector2i(1, 0), Vector2i(6, 0)]
		engine.state.players[player].position = positions[player]
		engine.state.walls[existing[player]] = true
		check(Paths.has_path(positions[player], player, engine.state.walls), "route exists before closing")
		check(engine.validate_action(wall_action(player, closing[player], "V")).reason_code == "path_blocked", "protect final path for every goal")
		var other_actor = (player + 1) % 4
		engine.state.current_player = other_actor
		var before = engine.state.snapshot()
		check(engine.apply_action(wall_action(other_actor, closing[player], "V")).reason_code == "path_blocked", "protect opponent route too")
		check(engine.state.snapshot() == before and engine.state.history.is_empty(), "path rejection atomic")
		var trapped_walls = engine.state.walls.duplicate()
		trapped_walls[Rules.wall_key(closing[player], "V")] = true
		check(Paths.distance(positions[player], player, trapped_walls) == -1, "unreachable BFS sentinel")
		engine.state.players[player].position = null
		engine.state.players[player].eliminated = true
		var actor = engine.state.active_players()[0]
		engine.state.current_player = actor
		check(engine.validate_action(wall_action(actor, closing[player], "V")).accepted, "ignore eliminated route")
	var engine = GameEngine.new()
	for anchor in [Vector2i(-1, 0), Vector2i(8, 0), Vector2i(0, 8)]:
		check(engine.validate_action(wall_action(0, anchor)).reason_code == "wall_outside_board", "anchor boundary")
	check(engine.validate_action(wall_action(0, Vector2i.ZERO, "X")).reason_code == "wall_outside_board", "invalid orientation")
	engine.state.players[0].walls_remaining = 0
	check(engine.validate_action(wall_action(0, Vector2i.ZERO)).reason_code == "no_walls_remaining", "no inventory")
	return true

func test_victory() -> bool:
	var starts = [Vector2i(2, 1), Vector2i(6, 7), Vector2i(7, 2), Vector2i(1, 6)]
	var goals = [Vector2i(2, 0), Vector2i(6, 8), Vector2i(8, 2), Vector2i(0, 6)]
	for player in range(4):
		var engine = GameEngine.new(Config.for_mode("Battle Royale"))
		engine.state.current_player = player
		engine.state.players[player].position = starts[player]
		check(engine.apply_action(move_action(player, goals[player])).accepted, "winning move")
		check(engine.state.winner == player and engine.state.current_player == player, "goal wins without advancing turn")
		check(engine.legal_actions().is_empty(), "no actions after victory")
		check(engine.set_paused(true).reason_code == "match_finished", "pause cannot reopen a finished match")
		var before = engine.state.snapshot()
		var history = engine.state.history.duplicate(true)
		check(engine.apply_action(move_action(player, starts[player])).reason_code == "match_finished", "reject post-victory action")
		engine.advance_turn()
		check(engine.state.snapshot() == before and engine.state.history == history, "finished match unchanged")
		check(engine.undo().accepted and engine.state.winner == -1, "undo victory")
	return true

func test_history_and_restart() -> bool:
	var config = Config.for_mode("Battle Royale")
	config.turn_limit = 30
	config.blitz_minutes = 5
	config.names[0] = "Alex"
	var engine = GameEngine.new(config)
	var opening = engine.state.snapshot()
	var detached = engine.state.snapshot()
	detached.players[0].position = Vector2i.ZERO
	detached.config.names[0] = "Other"
	check(engine.state.players[0].position == Vector2i(4, 8) and engine.state.config.names[0] == "Alex", "snapshot deep independence")
	engine.apply_action(wall_action(0, Vector2i(3, 3)))
	engine.apply_action(move_action(2, Vector2i(1, 4)))
	check(engine.undo().accepted and engine.undo().accepted, "undo move and wall")
	check(engine.state.snapshot() == opening and engine.state.history.is_empty(), "undo restores complete state")
	check(engine.undo().reason_code == "nothing_to_undo", "empty undo")
	engine.state.restore(detached)
	detached.players[0].position = Vector2i(1, 1)
	check(engine.state.players[0].position == Vector2i.ZERO, "restore deep independence")
	engine.restart()
	check(engine.state.players[0].position == Vector2i(4, 8) and engine.state.history.is_empty(), "restart clean board")
	check(engine.state.config.turn_limit == 30 and engine.state.config.blitz_minutes == 5, "restart preserves timing options")
	var random_config = Config.for_mode("Battle Royale")
	random_config.random_start = true
	var random_source = RandomNumberGenerator.new()
	random_source.seed = 12
	var control = RandomNumberGenerator.new()
	control.seed = 12
	var order = [0, 2, 1, 3]
	var random_engine = GameEngine.new(random_config, random_source)
	check(random_engine.state.current_player == order[control.randi_range(0, 3)], "random starter uses injected RNG")
	for index in range(8):
		random_engine.restart()
		check(random_engine.state.current_player == order[control.randi_range(0, 3)], "restart rerolls starter")
	engine.apply_action(move_action(0, Vector2i(4, 7)))
	check(engine.set_paused(true).accepted, "pause through engine API")
	check(engine.undo().accepted and engine.state.paused, "undo preserves current pause state")
	return true

func test_rejected_actions() -> bool:
	var engine = GameEngine.new()
	var opening = engine.state.snapshot()
	var invalid = [{}, {"kind": "pass", "player_id": 0}, move_action(1, Vector2i(4, 1)),
		move_action(-1, Vector2i.ZERO), move_action(200, Vector2i.ZERO),
		move_action(0, Vector2i(-1, 8)), move_action(0, Vector2i(3, 7)),
		{"kind": "move", "player_id": 0, "destination": Vector2(4, 7)},
		{"kind": "wall", "player_id": 0}, wall_action(0, Vector2i(8, 8))]
	for action in invalid:
		check(not engine.apply_action(action).accepted, "invalid action rejected")
		check(engine.state.snapshot() == opening and engine.state.history.is_empty(), "rejection atomic")
	engine.state.paused = true
	check(engine.apply_action(move_action(0, Vector2i(4, 7))).reason_code == "match_paused", "pause rejects move")
	check(engine.legal_actions().is_empty(), "pause hides actions")
	check(engine.set_paused(false).accepted, "resume through engine API")
	var before = engine.state.snapshot()
	var actions = engine.legal_actions()
	check(actions.size() == 131 and engine.state.snapshot() == before, "legal query does not mutate")
	for action in actions:
		check(engine.validate_action(action).accepted, "every queried action validates")
	var invalid_config = Config.new()
	invalid_config.controllers = []
	check(not engine.start_match(invalid_config).accepted and engine.state.snapshot() == before, "invalid configuration atomic")
	var blocked = GameEngine.new(Config.for_mode("Battle Royale"))
	for player in range(4):
		blocked.state.players[player].position = Vector2i(0, 8 - player)
	blocked.state.walls = {Vector3i(0, 7, 1): true, Vector3i(0, 5, 1): true}
	blocked.state.players[0].walls_remaining = 0
	check(blocked.legal_actions().is_empty() and blocked.state.status == "running", "no invented pass or stalemate rule")
	check(Paths.has_path(Vector2i(0, 8), 0, blocked.state.walls), "permanent paths ignore pawn blockade")
	return true

func load_reference_state(data: Dictionary) -> GameEngine:
	var config = Config.for_mode("Battle Royale" if data.positions.size() == 4 else "Versus")
	var engine = GameEngine.new(config)
	for player in range(data.positions.size()):
		var position = data.positions[player]
		engine.state.players[player].position = null if position == null else Vector2i(int(position[0]), int(position[1]))
		engine.state.players[player].walls_remaining = int(data.walls_left[player])
		engine.state.players[player].eliminated = player in data.eliminated
	for wall in data.walls:
		engine.state.walls[Rules.wall_key(Vector2i(int(wall[0]), int(wall[1])), wall[2])] = true
	engine.state.current_player = int(data.current_player)
	return engine

func test_python_parity() -> bool:
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/core/python_parity.json"))
	check(fixtures is Dictionary, "Python reference fixtures load")
	if not fixtures is Dictionary:
		return false
	for fixture in fixtures.queries:
		var engine = load_reference_state(fixture.state)
		for player in range(engine.state.players.size()):
			var expected: Array[Vector2i] = []
			for point in fixture.moves[player]:
				expected.append(Vector2i(int(point[0]), int(point[1])))
			var actual = Rules.valid_moves(engine.state.pawn_positions(), player, engine.state.walls)
			check(actual.size() == expected.size() and actual.all(func(point): return point in expected), fixture.name + " moves")
			var position = engine.state.players[player].position
			var distance = -1 if position == null else Paths.distance(position, player, engine.state.walls)
			check(distance == int(fixture.distances[player]), fixture.name + " BFS distance")
		var query_index = 0
		for row in range(8):
			for column in range(8):
				for orientation in ["H", "V"]:
					var error = Rules.wall_error(Vector2i(column, row), orientation, engine.state.walls,
						engine.state.pawn_positions(), engine.state.players[engine.state.current_player].walls_remaining)
					check(error == fixture.wall_reasons[query_index], fixture.name + " wall parity " + str(query_index))
					query_index += 1
	for trace in fixtures.traces:
		var engine = GameEngine.new(Config.for_mode(trace.mode))
		for step in trace.steps:
			var action: Dictionary = step.action.duplicate()
			action.player_id = int(action.player_id)
			if action.kind == "move":
				action.destination = Vector2i(int(action.destination[0]), int(action.destination[1]))
			else:
				action.anchor = Vector2i(int(action.anchor[0]), int(action.anchor[1]))
			check(engine.apply_action(action).accepted, "Python trace action accepted")
			var expected = load_reference_state(step.expected)
			check(engine.state.players == expected.state.players, "Python trace positions and inventories")
			check(engine.state.walls == expected.state.walls, "Python trace walls")
			check(engine.state.current_player == int(step.expected.current_player), "Python trace active player")
			check(engine.state.winner == int(step.expected.winner), "Python trace winner")
	return true

func test_version() -> bool:
	var notice = FileAccess.get_file_as_string("res://version_notice.txt")
	var current = notice.get_slice("\n", 1).trim_prefix("Current version: ").strip_edges()
	check(current == ProjectSettings.get_setting("application/config/version", ""), "authoritative notice matches project version")
	check(notice.contains("VERSION " + current + " - "), "current version has release entry")
	return true
