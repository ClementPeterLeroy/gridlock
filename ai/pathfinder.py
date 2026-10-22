"""Small, incremental rule-based agent. Actions are (kind, target) tuples."""

from collections import deque
import random
from time import perf_counter

from rules import neighbors, reached_goal, valid_moves, wall_error


def distance(start, player, walls):
    """BFS route length, ignoring temporary pawn obstacles."""
    queue = deque([(start, 0)])
    visited = {start}
    while queue:
        square, steps = queue.popleft()
        if reached_goal(square, player):
            return steps
        for target in neighbors(square, walls):
            if target not in visited:
                visited.add(target)
                queue.append((target, steps + 1))
    return float("inf")


def immediate_win(pawns, player, walls):
    return any(reached_goal(target, player)
               for target in valid_moves(pawns, player, walls))


def search(game, difficulty="Casual", time_limit=10.0, rng=None):
    """Yield the best legal action so far after each candidate evaluation.

    Consume in small frame budgets; the last yielded action is the result.
    Search never mutates the game. A legal pawn fallback is yielded first,
    even with a zero time budget. Intended for standard two-player matches.
    """
    rng = rng or random
    deadline = perf_counter() + min(10.0, max(0.0, time_limit))
    player = game.current_player
    opponent = 1 - player
    pawns, walls = game.pawns.copy(), game.walls.copy()
    moves = sorted(valid_moves(pawns, player, walls))
    if game.winner is not None or not moves:
        return
    for target in moves:
        if reached_goal(target, player):
            yield "move", target
            return

    # Casual varies ties and sometimes accepts a slightly longer route.
    rng.shuffle(moves)
    best = ("move", moves[0])
    yield best
    best_score = -float("inf")
    opponent_distance = distance(pawns[opponent], opponent, walls)
    threatened = immediate_win(pawns, opponent, walls)
    for target in moves:
        if perf_counter() >= deadline:
            return
        proposed = pawns.copy()
        proposed[player] = target
        danger = immediate_win(proposed, opponent, walls)
        score = opponent_distance - distance(target, player, walls)
        score -= 1000 if danger else 0
        if difficulty == "Casual":
            score += rng.uniform(0, 1.2)
        if score > best_score:
            best_score, best = score, ("move", target)
        yield best

    if game.walls_left[player] <= 0:
        return
    # With a clear racing lead, advancing is safer than spending more walls.
    if not threatened and distance(pawns[player], player, walls) + 1 < opponent_distance:
        return
    if difficulty == "Casual" and not threatened and rng.random() > 0.2:
        return
    candidates = [(row, col, direction) for row in range(8)
                  for col in range(8) for direction in ("H", "V")]
    # Check nearby walls first so a short budget can still find useful blocks.
    candidates.sort(key=lambda w: abs(w[0] - pawns[opponent][0])
                    + abs(w[1] - pawns[opponent][1]))
    if difficulty == "Casual" and not threatened:
        candidates = candidates[:20]
    for wall in candidates:
        if perf_counter() >= deadline:
            return
        if wall_error(wall, walls, pawns, game.walls_left[player]) is None:
            proposed = walls | {wall}
            danger = immediate_win(pawns, opponent, proposed)
            enemy_route = distance(pawns[opponent], opponent, proposed)
            own_route = distance(pawns[player], player, proposed)
            # Spending a wall must beat advancing a pawn, unless saving a game.
            useful = enemy_route > opponent_distance or (threatened and not danger)
            score = enemy_route - own_route - 0.6
            score -= 1000 if danger else 0
            if useful and score > best_score:
                best_score, best = score, ("wall", wall)
        yield best
