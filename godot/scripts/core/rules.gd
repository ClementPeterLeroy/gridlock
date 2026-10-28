class_name GridlockRules
extends RefCounted
## Pure rule queries. None of these functions mutate their input.

const Paths = preload("res://scripts/core/pathfinding.gd")

static func wall_key(anchor: Vector2i, orientation: String) -> Vector3i:
	return Vector3i(anchor.x, anchor.y, 0 if orientation == "H" else 1)

static func valid_moves(pawns: Array, player: int, walls: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if player < 0 or player >= pawns.size() or pawns[player] == null:
		return moves
	var own: Vector2i = pawns[player]
	for direction in Paths.DIRECTIONS:
		var adjacent: Vector2i = own + direction
		if not Paths.inside(adjacent) or Paths.blocked(own, adjacent, walls):
			continue
		if adjacent not in pawns:
			if adjacent not in moves:
				moves.append(adjacent)
			continue
		var behind: Vector2i = adjacent + direction
		if Paths.inside(behind) and behind not in pawns and not Paths.blocked(adjacent, behind, walls):
			if behind not in moves:
				moves.append(behind)
			continue
		var sides = [Vector2i(-1, 0), Vector2i(1, 0)] if direction.y != 0 else [Vector2i(0, -1), Vector2i(0, 1)]
		for side_direction in sides:
			var side: Vector2i = adjacent + side_direction
			if Paths.inside(side) and side not in pawns and not Paths.blocked(adjacent, side, walls):
				if side not in moves:
					moves.append(side)
	return moves

static func wall_error(anchor: Vector2i, orientation: String, walls: Dictionary, pawns: Array, remaining: int) -> String:
	if remaining <= 0:
		return "no_walls_remaining"
	if orientation not in ["H", "V"] or anchor.x < 0 or anchor.x >= 8 or anchor.y < 0 or anchor.y >= 8:
		return "wall_outside_board"
	var key = wall_key(anchor, orientation)
	if walls.has(key) or walls.has(Vector3i(key.x, key.y, 1 - key.z)):
		return "wall_overlap_or_crossing"
	var offset = Vector3i(1, 0, 0) if orientation == "H" else Vector3i(0, 1, 0)
	if walls.has(key - offset) or walls.has(key + offset):
		return "wall_overlap"
	var proposed = walls.duplicate()
	proposed[key] = true
	for player in range(pawns.size()):
		if pawns[player] != null and not Paths.has_path(pawns[player], player, proposed):
			return "path_blocked"
	return ""
