"""Generate deterministic reference data from the unmodified Classic engine.

Run from any directory. --check verifies committed fixtures without rewriting.
Only standard-library Python and the legacy pure rules/state modules are used.
"""

import argparse
import json
from pathlib import Path
import random
import sys

LEGACY = Path(__file__).resolve().parents[2] / "pygame"
sys.path.insert(0, str(LEGACY))
from game import Game
from rules import valid_moves, wall_error
from ai.pathfinder import distance

OUTPUT = Path(__file__).parent / "core" / "python_parity.json"
REASONS = {
    None: "",
    "No walls remaining.": "no_walls_remaining",
    "Wall is outside the board.": "wall_outside_board",
    "Walls cannot overlap or cross.": "wall_overlap_or_crossing",
    "Walls cannot overlap.": "wall_overlap",
    "Every player must keep a path to the goal.": "path_blocked",
}


def position(square):
    return None if square is None else [square[1], square[0]]


def wall(value):
    row, column, orientation = value
    return [column, row, orientation]


def normalized(game):
    return {
        "positions": [position(p) for p in game.pawns],
        "walls": sorted([wall(w) for w in game.walls]),
        "walls_left": game.walls_left.copy(),
        "current_player": game.current_player,
        "winner": -1 if game.winner is None else game.winner,
        "eliminated": sorted(game.eliminated),
    }


def query_case(name, game):
    return {
        "name": name,
        "state": normalized(game),
        "moves": [sorted(position(p) for p in valid_moves(game.pawns, i, game.walls))
                  for i in range(game.player_count)],
        "distances": [-1 if p is None else distance(p, i, game.walls)
                      for i, p in enumerate(game.pawns)],
        # Order: row, column, then H/V. Store only reasons to keep fixtures small.
        "wall_reasons": [
            REASONS[wall_error((r, c, d), game.walls, game.pawns,
                              game.walls_left[game.current_player])]
            for r in range(8) for c in range(8) for d in ("H", "V")
        ],
    }


def build():
    cases = [query_case("two_player_opening", Game()),
             query_case("four_player_opening", Game("Battle Royale"))]
    for dr, dc in ((-1, 0), (0, 1), (1, 0), (0, -1)):
        cases.append(query_case(f"jump_{dr}_{dc}", Game(
            pawns=[(4, 4), (4 + dr, 4 + dc)])))
        adjacent = (4 + dr, 4 + dc)
        behind = (4 + 2 * dr, 4 + 2 * dc)
        barrier = ((min(adjacent[0], behind[0]), adjacent[1], "H") if dr else
                   (adjacent[0], min(adjacent[1], behind[1]), "V"))
        cases.append(query_case(f"blocked_jump_{dr}_{dc}", Game(
            pawns=[(4, 4), adjacent], walls={barrier})))
    cases.append(query_case("wall_blocked_jump", Game(
        pawns=[(4, 4), (3, 4)], walls={(2, 4, "H")})))
    cases.append(query_case("boundary_sidestep", Game(pawns=[(1, 4), (0, 4)])))
    cases.append(query_case("occupied_landing", Game("Battle Royale",
        pawns=[(4, 4), (3, 4), (2, 4), (3, 5)])))
    cases.append(query_case("blocked_approach", Game(
        pawns=[(4, 4), (3, 4)], walls={(3, 4, "H")})))
    cases.append(query_case("no_pawn_moves", Game("Battle Royale",
        pawns=[(8, 0), (7, 0), (6, 0), (5, 0)], walls={(7, 0, "V"), (5, 0, "V")})))
    for player in range(4):
        game = Game("Battle Royale")
        game.pawns[player] = [(8, 0), (0, 0), (0, 0), (0, 8)][player]
        game.current_player = player
        game.walls = {[(7, 0, "H"), (0, 0, "H"), (0, 0, "H"), (0, 7, "H")][player]}
        cases.append(query_case(f"last_route_player_{player}", game))
    eliminated = Game("Battle Royale")
    eliminated.forfeit()
    cases.append(query_case("eliminated_player", eliminated))

    traces = []
    for mode in ("Versus", "Battle Royale"):
        game = Game(mode)
        rng = random.Random(231)
        steps = []
        for turn in range(32):
            moves = sorted(valid_moves(game.pawns, game.current_player, game.walls))
            candidates = [(r, c, d) for r in range(8) for c in range(8) for d in ("H", "V")
                          if wall_error((r, c, d), game.walls, game.pawns,
                                        game.walls_left[game.current_player]) is None]
            actor = game.current_player
            if turn % 3 == 0 and candidates:
                target = rng.choice(candidates)
                action = {"kind": "wall", "player_id": actor,
                          "anchor": position(target[:2]), "orientation": target[2]}
                assert game.place_wall(target)
            else:
                target = rng.choice(moves)
                action = {"kind": "move", "player_id": actor, "destination": position(target)}
                assert game.move(target)
            steps.append({"action": action, "expected": normalized(game)})
            if game.winner is not None:
                break
        traces.append({"mode": mode, "steps": steps})
    return {"reference": "pygame/rules.py, game.py and ai/pathfinder.py",
            "coordinate_order": "column,row", "queries": cases, "traces": traces}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()
    rendered = json.dumps(build(), indent=2, ensure_ascii=False) + "\n"
    if options.check:
        if OUTPUT.read_text(encoding="utf-8") != rendered:
            raise SystemExit("Python parity fixtures are stale")
        print("Python parity fixtures match the current legacy implementation")
    else:
        OUTPUT.write_text(rendered, encoding="utf-8")
        print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
