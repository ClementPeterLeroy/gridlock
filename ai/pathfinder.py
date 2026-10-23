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
    Search never mutates the game. A legal fallback is yielded first,
    even with a zero time budget. Supports two- and four-player matches.
    """
    rng = rng or random
    deadline = perf_counter() + min(10.0, max(0.0, time_limit))
    player = game.current_player
    opponents = [i for i in range(game.player_count) if i != player]
    pawns, walls = game.pawns.copy(), game.walls.copy()
    moves = sorted(valid_moves(pawns, player, walls))
    if game.winner is not None:
        return
    if not moves:
        # Several pawns can temporarily block a narrow corridor. Spend a
        # legal wall rather than stalling when no pawn move is available.
        if game.walls_left[player] > 0:
            for row in range(8):
                for col in range(8):
                    for direction in ("H", "V"):
                        wall = (row, col, direction)
                        if wall_error(wall, walls, pawns, game.walls_left[player]) is None:
                            yield "wall", wall
                            return
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
    routes = {i: distance(pawns[i], i, walls) for i in opponents}
    leader = min(opponents, key=routes.get)
    threats = [i for i in opponents if immediate_win(pawns, i, walls)]
    threatened = bool(threats)

    def opposition_score(lengths):
        # The closest opponent dominates; the other routes break close ties.
        nearest = min(lengths.values())
        return nearest + 0.15 * (sum(lengths.values()) / len(lengths) - nearest)

    def danger_count(positions, proposed_walls):
        return sum(immediate_win(positions, i, proposed_walls) for i in opponents)

    opponent_distance = opposition_score(routes)
    for target in moves:
        if perf_counter() >= deadline:
            return
        proposed = pawns.copy()
        proposed[player] = target
        danger = danger_count(proposed, walls)
        score = opponent_distance - distance(target, player, walls)
        score -= 1000 * danger
        if difficulty == "Casual":
            score += rng.uniform(0, 1.2)
        if score > best_score:
            best_score, best = score, ("move", target)
        yield best

    if game.walls_left[player] <= 0:
        return
    # With a clear racing lead, advancing is safer than spending more walls.
    if not threatened and distance(pawns[player], player, walls) + 1 < routes[leader]:
        return
    if difficulty == "Casual" and not threatened and rng.random() > 0.2:
        return
    candidates = [(row, col, direction) for row in range(8)
                  for col in range(8) for direction in ("H", "V")]
    # Check nearby walls first so a short budget can still find useful blocks.
    targets = threats or [leader]
    candidates.sort(key=lambda w: min(abs(w[0] - pawns[i][0])
                                     + abs(w[1] - pawns[i][1]) for i in targets))
    if difficulty == "Casual" and not threatened:
        candidates = candidates[:20]
    for wall in candidates:
        if perf_counter() >= deadline:
            return
        if wall_error(wall, walls, pawns, game.walls_left[player]) is None:
            proposed = walls | {wall}
            danger = danger_count(pawns, proposed)
            enemy_routes = {i: distance(pawns[i], i, proposed) for i in opponents}
            enemy_route = opposition_score(enemy_routes)
            own_route = distance(pawns[player], player, proposed)
            # Spending a wall must beat advancing a pawn, unless saving a game.
            useful = enemy_route > opponent_distance or danger < len(threats)
            score = enemy_route - own_route - 0.6
            score -= 1000 * danger
            if useful and score > best_score:
                best_score, best = score, ("wall", wall)
        yield best
