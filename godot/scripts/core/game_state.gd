class_name GridlockGameState
extends RefCounted
## Coordinates are Vector2i(column, row). Player IDs never change after elimination.

const Config = preload("res://scripts/core/match_config.gd")
const STARTS = [Vector2i(4, 8), Vector2i(4, 0), Vector2i(0, 4), Vector2i(8, 4)]
const GOALS = [Vector2i(1, 0), Vector2i(1, 8), Vector2i(0, 8), Vector2i(0, 0)]

var config = Config.new()
var board_size = Vector2i(9, 9)
var players: Array[Dictionary] = []
# A set of Vector3i(column, row, orientation): H = 0, V = 1.
var walls: Dictionary = {}
var current_player: int = 0
var status: String = "running"
var winner: int = -1
var paused: bool = false
var turn_number: int = 0
var result_reason: String = ""
var history: Array[Dictionary] = []
var turn_elapsed = 0.0
var turn_clock_elapsed = 0.0
var elapsed_turns: Array = []
var time_left: Array = []
var penalty_used = false
var overtime = 0.0
var timeout_player = -1
var timing_notice = ""
var ai_clock_age = 0.0

var is_blitz: bool:
	get: return config.mode == "Blitz"

var uses_blitz_clock: bool:
	get: return is_blitz and config.timing_mode == "Per Game"

var remaining_turn_time: float:
	get:
		if players[current_player].controller != "Human":
			return INF
		if uses_blitz_clock:
			return overtime if penalty_used else time_left[current_player]
		if config.timing_mode == "Per Game":
			return time_left[current_player]
		if config.timing_mode == "Untimed":
			return INF
		return maxf(0.0, config.turn_limit - turn_clock_elapsed) if config.turn_limit else INF

func _init(options = null) -> void:
	if options != null:
		config = options.copy()
	for player in range(config.player_count()):
		players.append({"id": player, "identity": Config.IDENTITIES[player],
			"name": config.display_name(player), "controller": config.controllers[player],
			"goal": GOALS[player], "position": STARTS[player],
			"walls_remaining": 5 if config.player_count() == 4 else 10, "eliminated": false})
	current_player = config.starting_player
	elapsed_turns.resize(players.size())
	elapsed_turns.fill(0.0)
	time_left.resize(players.size())
	time_left.fill(float(config.game_limit) if config.mode == "Battle Royale" and config.timing_mode == "Per Game" else 60.0 * config.blitz_minutes)

func pawn_positions() -> Array:
	var positions = []
	for player in players:
		positions.append(player.position)
	return positions

func active_players() -> Array:
	var active = []
	var order = [0, 2, 1, 3] if players.size() == 4 else [0, 1]
	for player in order:
		if not players[player].eliminated:
			active.append(player)
	return active

func snapshot() -> Dictionary:
	# History is intentionally excluded: snapshots must not recursively capture history.
	return {"config": config.to_dict(), "board_size": board_size,
		"players": players.duplicate(true), "walls": walls.duplicate(true),
		"current_player": current_player, "status": status, "winner": winner,
		"paused": paused, "turn_number": turn_number, "result_reason": result_reason,
		"turn_elapsed": turn_elapsed, "turn_clock_elapsed": turn_clock_elapsed,
		"elapsed_turns": elapsed_turns.duplicate(), "time_left": time_left.duplicate(),
		"penalty_used": penalty_used, "overtime": overtime, "timeout_player": timeout_player,
		"timing_notice": timing_notice, "ai_clock_age": ai_clock_age}

func restore(snapshot_data: Dictionary) -> void:
	var data = snapshot_data.duplicate(true)
	config = Config.new()
	for key in data.config:
		config.set(key, data.config[key])
	board_size = data.board_size
	players.assign(data.players)
	walls = data.walls
	current_player = data.current_player
	status = data.status
	winner = data.winner
	paused = data.paused
	turn_number = data.turn_number
	result_reason = data.result_reason
	turn_elapsed = data.turn_elapsed
	turn_clock_elapsed = data.turn_clock_elapsed
	elapsed_turns = data.elapsed_turns
	time_left = data.time_left
	penalty_used = data.penalty_used
	overtime = data.overtime
	timeout_player = data.timeout_player
	timing_notice = data.timing_notice
	ai_clock_age = data.ai_clock_age
