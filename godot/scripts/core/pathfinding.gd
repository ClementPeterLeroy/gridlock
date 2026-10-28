class_name GridlockPathfinding
extends RefCounted
## The permanent board graph ignores pawn occupancy, as in pygame/rules.py.

const SIZE = 9
const DIRECTIONS = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func inside(square: Vector2i) -> bool:
	return square.x >= 0 and square.x < SIZE and square.y >= 0 and square.y < SIZE

static func blocked(a: Vector2i, b: Vector2i, walls: Dictionary) -> bool:
	if a.y == b.y:
		var column = mini(a.x, b.x)
		return walls.has(Vector3i(column, a.y, 1)) or walls.has(Vector3i(column, a.y - 1, 1))
	var row = mini(a.y, b.y)
	return walls.has(Vector3i(a.x, row, 0)) or walls.has(Vector3i(a.x - 1, row, 0))

static func neighbors(square: Vector2i, walls: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var target = square + direction
		if inside(target) and not blocked(square, target, walls):
			result.append(target)
	return result

static func reached_goal(square: Vector2i, player: int) -> bool:
	match player:
		0: return square.y == 0
		1: return square.y == 8
		2: return square.x == 8
		3: return square.x == 0
	return false

static func distance(start: Vector2i, player: int, walls: Dictionary) -> int:
	if not inside(start) or player < 0 or player > 3:
		return -1
	var queue: Array[Vector2i] = [start]
	var distances = {start: 0}
	var index = 0
	while index < queue.size():
		var square = queue[index]
		index += 1
		if reached_goal(square, player):
			return distances[square]
		for target in neighbors(square, walls):
			if not distances.has(target):
				distances[target] = distances[square] + 1
				queue.append(target)
	return -1

static func has_path(start: Vector2i, player: int, walls: Dictionary) -> bool:
	return distance(start, player, walls) >= 0
