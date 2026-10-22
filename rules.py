"""Board rules. This module does not depend on Pygame."""

from collections import deque

SIZE = 9
DIRECTIONS = ((-1, 0), (0, 1), (1, 0), (0, -1))


def inside(square):
    row, col = square
    return 0 <= row < SIZE and 0 <= col < SIZE


def blocked(a, b, walls):
    """Return True if a wall separates two neighboring squares."""
    r1, c1 = a
    r2, c2 = b
    if r1 == r2:
        col = min(c1, c2)
        return (r1, col, "V") in walls or (r1 - 1, col, "V") in walls
    row = min(r1, r2)
    return (row, c1, "H") in walls or (row, c1 - 1, "H") in walls


def neighbors(square, walls):
    for dr, dc in DIRECTIONS:
        target = (square[0] + dr, square[1] + dc)
        if inside(target) and not blocked(square, target, walls):
            yield target


def valid_moves(pawns, player, walls):
    """Pawn moves, including jumps and side steps around occupied squares.

    In four-player games, a jump cannot land on another pawn.
    """
    own = pawns[player]
    occupied = set(pawns) - {own}
    moves = set()
    for dr, dc in DIRECTIONS:
        adjacent = (own[0] + dr, own[1] + dc)
        if not inside(adjacent) or blocked(own, adjacent, walls):
            continue
        if adjacent not in occupied:
            moves.add(adjacent)
            continue

        # Only one pawn can be jumped. An occupied or blocked landing
        # square permits a sidestep around the adjacent pawn instead.
        behind = (adjacent[0] + dr, adjacent[1] + dc)
        if (inside(behind) and behind not in occupied
                and not blocked(adjacent, behind, walls)):
            moves.add(behind)
            continue
        sides = ((0, -1), (0, 1)) if dr else ((-1, 0), (1, 0))
        for sr, sc in sides:
            side = (adjacent[0] + sr, adjacent[1] + sc)
            if inside(side) and side not in occupied and not blocked(adjacent, side, walls):
                moves.add(side)
    return moves


def reached_goal(square, player):
    row, col = square
    return (row == 0 if player == 0 else
            row == 8 if player == 1 else
            col == 8 if player == 2 else col == 0)


def has_path(start, player, walls):
    """Pawns do not count as permanent obstacles for wall legality."""
    queue = deque([start])
    visited = {start}
    while queue:
        square = queue.popleft()
        if reached_goal(square, player):
            return True
        for neighbor in neighbors(square, walls):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    return False


def wall_error(wall, walls, pawns, walls_remaining):
    row, col, direction = wall
    if walls_remaining <= 0:
        return "No walls remaining."
    if direction not in ("H", "V") or not (0 <= row < 8 and 0 <= col < 8):
        return "Wall is outside the board."
    if wall in walls or (row, col, "V" if direction == "H" else "H") in walls:
        return "Walls cannot overlap or cross."
    if direction == "H" and ((row, col - 1, "H") in walls or (row, col + 1, "H") in walls):
        return "Walls cannot overlap."
    if direction == "V" and ((row - 1, col, "V") in walls or (row + 1, col, "V") in walls):
        return "Walls cannot overlap."
    proposed = walls | {wall}
    if any(not has_path(pawn, i, proposed) for i, pawn in enumerate(pawns)):
        return "Every player must keep a path to the goal."
    return None
