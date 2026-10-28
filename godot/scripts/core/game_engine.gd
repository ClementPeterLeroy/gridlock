class_name GridlockGameEngine
extends RefCounted
## The only action entry point. Rendering and controllers submit proposals here.

const Config = preload("res://scripts/core/match_config.gd")
const State = preload("res://scripts/core/game_state.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Paths = preload("res://scripts/core/pathfinding.gd")

var state: State
var rng = RandomNumberGenerator.new()

func _init(options = null, random_source = null) -> void:
	if random_source != null:
		rng = random_source
	else:
		rng.randomize()
	start_match(Config.new() if options == null else options)

static func result(reason: String = "") -> Dictionary:
	return {"accepted": reason.is_empty(), "reason_code": "ok" if reason.is_empty() else reason}

func start_match(options: Config) -> Dictionary:
	var error = options.validation_error()
	if not error.is_empty():
		return result(error)
	var fresh = State.new(options)
	if options.random_start:
		var active = fresh.active_players()
		fresh.current_player = active[rng.randi_range(0, active.size() - 1)]
	state = fresh
	return result()

func restart() -> Dictionary:
	return start_match(state.config)

func action_error(action: Dictionary) -> String:
	if state.status != "running":
		return "match_finished"
	if state.paused:
		return "match_paused"
	if typeof(action.get("player_id")) != TYPE_INT or action.get("kind") not in ["move", "wall"]:
		return "invalid_action"
	if action.player_id != state.current_player:
		return "not_active_player"
	if state.players[action.player_id].eliminated:
		return "player_eliminated"
	if action.kind == "move":
		if typeof(action.get("destination")) != TYPE_VECTOR2I:
			return "invalid_action"
		if action.destination not in Rules.valid_moves(state.pawn_positions(), state.current_player, state.walls):
			return "illegal_move"
	else:
		if typeof(action.get("anchor")) != TYPE_VECTOR2I or typeof(action.get("orientation")) != TYPE_STRING:
			return "invalid_action"
		return Rules.wall_error(action.anchor, action.orientation, state.walls,
			state.pawn_positions(), state.players[state.current_player].walls_remaining)
	return ""

func validate_action(action: Dictionary) -> Dictionary:
	return result(action_error(action))

func legal_moves() -> Array[Vector2i]:
	if state.paused or state.status != "running":
		return []
	return Rules.valid_moves(state.pawn_positions(), state.current_player, state.walls)

func legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if state.paused or state.status != "running":
		return actions
	for target in legal_moves():
		actions.append({"kind": "move", "player_id": state.current_player, "destination": target})
	for row in range(8):
		for column in range(8):
			for orientation in ["H", "V"]:
				var action = {"kind": "wall", "player_id": state.current_player,
					"anchor": Vector2i(column, row), "orientation": orientation}
				if action_error(action).is_empty():
					actions.append(action)
	return actions

func apply_action(action: Dictionary) -> Dictionary:
	var error = action_error(action)
	if not error.is_empty():
		return result(error)
	state.history.append(state.snapshot())
	var player = state.players[state.current_player]
	if action.kind == "move":
		player.position = action.destination
		if Paths.reached_goal(action.destination, state.current_player):
			state.winner = state.current_player
			state.status = "finished"
			state.result_reason = "goal_reached"
			return result()
	else:
		state.walls[Rules.wall_key(action.anchor, action.orientation)] = true
		player.walls_remaining -= 1
	advance_turn()
	return result()

func advance_turn() -> void:
	if state.paused or state.status != "running":
		return
	var order = [0, 2, 1, 3] if state.players.size() == 4 else [0, 1]
	var index = order.find(state.current_player)
	for step in range(1, order.size() + 1):
		var next_player: int = order[(index + step) % order.size()]
		if not state.players[next_player].eliminated:
			state.current_player = next_player
			state.turn_number += 1
			return

func forfeit(player_id: int) -> Dictionary:
	# Future timeout integration uses the same removal rules as Python Game.forfeit().
	if state.status != "running":
		return result("match_finished")
	if state.paused:
		return result("match_paused")
	if player_id != state.current_player:
		return result("not_active_player")
	state.history.append(state.snapshot())
	state.players[player_id].position = null
	state.players[player_id].eliminated = true
	var active = state.active_players()
	if active.size() == 1:
		state.winner = active[0]
		state.status = "finished"
		state.result_reason = "last_survivor"
	else:
		advance_turn()
	return result()

func undo() -> Dictionary:
	if state.history.is_empty():
		return result("nothing_to_undo")
	# Undo while paused must not accidentally resume the application.
	var paused = state.paused
	state.restore(state.history.pop_back())
	state.paused = paused
	return result()
