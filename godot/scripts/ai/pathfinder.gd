extends RefCounted
## Incremental translation of pygame/ai/pathfinder.py. One candidate per step.
## Search owns copies of board data and never writes to the live match.

const Rules = preload("res://scripts/core/rules.gd")
const Paths = preload("res://scripts/core/pathfinding.gd")

var player: int
var pawns: Array
var walls: Dictionary
var remaining: int
var opponents: Array = []
var difficulty: String
var rng
var best_action: Dictionary = {}
var best_score = -INF
var done = false
var cancelled = false
var phase = "opening"
var moves: Array = []
var candidates: Array = []
var index = 0
var routes: Dictionary = {}
var threats: Array = []
var leader = -1
var opponent_distance = 0.0
var started_us: int
var time_limit: float
var steps = 0
var max_step_us = 0

func _init(state, level: String = "Casual", random_source = null, budget: float = 10.0) -> void:
	player = state.current_player
	pawns = state.pawn_positions().duplicate()
	walls = state.walls.duplicate()
	remaining = state.players[player].walls_remaining
	difficulty = level
	rng = random_source
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for active in state.active_players():
		if active != player and pawns[active] != null:
			opponents.append(active)
	time_limit = clampf(budget, 0.0, 10.0)
	started_us = Time.get_ticks_usec()
	done = state.status != "running" or pawns[player] == null or opponents.is_empty()

func cancel() -> void:
	cancelled = true
	done = true
	best_action = {}

func step(active_seconds: float = -1.0) -> void:
	if done:
		return
	var start = Time.get_ticks_usec()
	var elapsed = (start - started_us) / 1000000.0 if active_seconds < 0 else active_seconds
	# As in Python, an initial legal fallback survives even a zero budget.
	if phase not in ["opening", "fallback"] and elapsed >= time_limit:
		done = true
	else:
		advance()
	steps += 1
	max_step_us = maxi(max_step_us, Time.get_ticks_usec() - start)

func advance() -> void:
	match phase:
		"opening":
			moves = Rules.valid_moves(pawns, player, walls)
			moves.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
			if moves.is_empty():
				if remaining <= 0:
					done = true
				else:
					candidates = all_walls()
					phase = "fallback"
				return
			for target in moves:
				if Paths.reached_goal(target, player):
					best_action = move_action(target)
					done = true
					return
			for i in range(moves.size() - 1, 0, -1):
				var other: int = rng.randi_range(0, i)
				var temporary = moves[i]
				moves[i] = moves[other]
				moves[other] = temporary
			best_action = move_action(moves[0])
			phase = "routes"
		"fallback":
			var wall: Vector3i = candidates[index]
			index += 1
			if legal_wall(wall):
				best_action = wall_action(wall)
				done = true
			elif index == candidates.size():
				done = true
		"routes":
			for opponent in opponents:
				routes[opponent] = distance(pawns[opponent], opponent, walls)
				if leader == -1 or routes[opponent] < routes[leader]:
					leader = opponent
				if immediate_win(pawns, opponent, walls):
					threats.append(opponent)
			opponent_distance = opposition_score(routes)
			phase = "moves"
		"moves":
			var target: Vector2i = moves[index]
			index += 1
			var positions = pawns.duplicate()
			positions[player] = target
			var score = opponent_distance - distance(target, player, walls) - 1000.0 * danger_count(positions, walls)
			if difficulty == "Casual":
				score += rng.randf_range(0.0, 1.2)
			if score > best_score:
				best_score = score
				best_action = move_action(target)
			if index == moves.size():
				phase = "prepare_walls"
		"prepare_walls":
			if remaining <= 0 or (threats.is_empty() and distance(pawns[player], player, walls) + 1 < routes[leader]):
				done = true
				return
			if difficulty == "Casual" and threats.is_empty() and rng.randf() > 0.2:
				done = true
				return
			candidates = all_walls()
			# Explicit tie order matches Python's stable row/column/H-V sorting.
			candidates.sort_custom(func(a, b):
				var first = wall_priority(a)
				var second = wall_priority(b)
				return first < second or (first == second and wall_order(a) < wall_order(b)))
			if difficulty == "Casual" and threats.is_empty():
				candidates.resize(20)
			index = 0
			phase = "walls"
		"walls":
			var wall: Vector3i = candidates[index]
			index += 1
			if legal_wall(wall):
				var proposed = walls.duplicate()
				proposed[wall] = true
				var danger = danger_count(pawns, proposed)
				var enemy_routes: Dictionary = {}
				for opponent in opponents:
					enemy_routes[opponent] = distance(pawns[opponent], opponent, proposed)
				var enemy_distance = opposition_score(enemy_routes)
				var useful = enemy_distance > opponent_distance or danger < threats.size()
				var score = enemy_distance - distance(pawns[player], player, proposed) - 0.6 - 1000.0 * danger
				if useful and score > best_score:
					best_score = score
					best_action = wall_action(wall)
			if index == candidates.size():
				done = true

static func distance(start: Vector2i, id: int, placed: Dictionary) -> float:
	var length = Paths.distance(start, id, placed)
	return INF if length < 0 else float(length)

static func immediate_win(positions: Array, id: int, placed: Dictionary) -> bool:
	for target in Rules.valid_moves(positions, id, placed):
		if Paths.reached_goal(target, id):
			return true
	return false

func danger_count(positions: Array, placed: Dictionary) -> int:
	var count = 0
	for opponent in opponents:
		if immediate_win(positions, opponent, placed):
			count += 1
	return count

static func opposition_score(lengths: Dictionary) -> float:
	var nearest = INF
	var total = 0.0
	for length in lengths.values():
		nearest = minf(nearest, length)
		total += length
	return nearest + 0.15 * (total / lengths.size() - nearest)

static func all_walls() -> Array:
	var result: Array = []
	for row in range(8):
		for col in range(8):
			for direction in range(2):
				result.append(Vector3i(col, row, direction))
	return result

static func wall_order(wall: Vector3i) -> int:
	return wall.y * 16 + wall.x * 2 + wall.z

func wall_priority(wall: Vector3i) -> int:
	var nearest = 100
	for target in ([leader] if threats.is_empty() else threats):
		nearest = mini(nearest, absi(wall.x - pawns[target].x) + absi(wall.y - pawns[target].y))
	return nearest

func legal_wall(wall: Vector3i) -> bool:
	return Rules.wall_error(Vector2i(wall.x, wall.y), "H" if wall.z == 0 else "V", walls, pawns, remaining).is_empty()

func move_action(target: Vector2i) -> Dictionary:
	return {"kind": "move", "player_id": player, "destination": target}

func wall_action(wall: Vector3i) -> Dictionary:
	return {"kind": "wall", "player_id": player, "anchor": Vector2i(wall.x, wall.y),
		"orientation": "H" if wall.z == 0 else "V"}
