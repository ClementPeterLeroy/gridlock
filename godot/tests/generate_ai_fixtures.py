"""Deterministic AI reference decisions from the unmodified Pygame Pathfinder."""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pygame"))
from game import Game
from ai.pathfinder import search

OUTPUT = Path(__file__).parent / "ai" / "python_ai_parity.json"


class FixedRandom:
    """Shared test policy: keep move order, zero noise, consider Casual walls."""

    def shuffle(self, values):
        pass

    def uniform(self, low, high):
        return low

    def random(self):
        return 0.1


def action(value, player):
    if value is None:
        return {}
    kind, target = value
    if kind == "move":
        return {"kind": kind, "player_id": player, "destination": [target[1], target[0]]}
    return {"kind": kind, "player_id": player,
            "anchor": [target[1], target[0]], "orientation": target[2]}


def case(name, game, level, budget=10.0):
    before = game.snapshot()
    proposals = list(search(game, level, time_limit=budget, rng=FixedRandom(), clock=lambda: 0.0))
    assert before == game.snapshot(), "Reference search mutated its state"
    return {
        "name": name + "_" + level,
        "mode": game.mode,
        "pawns": [None if p is None else [p[1], p[0]] for p in game.pawns],
        "walls": sorted([[c, r, d] for r, c, d in game.walls]),
        "walls_left": game.walls_left.copy(),
        "current_player": game.current_player,
        "eliminated": sorted(game.eliminated),
        "difficulty": level,
        "time_limit": budget,
        "expected": action(proposals[-1] if proposals else None, game.current_player),
    }


def build():
    fixtures = []
    near_goals = [(1, 2), (7, 6), (2, 7), (6, 1)]
    for level in ("Casual", "Challenging"):
        for mode in ("Versus", "Battle Royale"):
            fixtures.append(case("opening_" + mode, Game(mode), level))
        for player in range(4):
            game = Game("Battle Royale", current_player=player)
            game.pawns[player] = near_goals[player]
            fixtures.append(case(f"immediate_win_{player}", game, level))
            for opponent in range(4):
                if opponent == player:
                    continue
                game = Game("Battle Royale", current_player=player)
                game.pawns[opponent] = near_goals[opponent]
                fixtures.append(case(f"threat_{player}_from_{opponent}", game, level))
        fixtures.append(case("adjacent_no_walls", Game("Battle Royale",
            pawns=[(4, 4), (3, 4), (3, 5), (4, 5)], walls_left=[0] * 4), level))
        fixtures.append(case("blocked_jump", Game(pawns=[(4, 4), (3, 4)], walls={(2, 4, "H")}), level))
        blocked = Game("Battle Royale", pawns=[(8, 0), (7, 0), (6, 0), (5, 0)],
                       walls={(7, 0, "V"), (5, 0, "V")})
        fixtures.append(case("wall_fallback", blocked, level, 0.0))
        blocked.walls_left[0] = 0
        fixtures.append(case("no_legal_action", blocked, level))
        game = Game("Battle Royale")
        game.forfeit()
        fixtures.append(case("eliminated_player", game, level))
        fixtures.append(case("zero_budget", Game(), level, 0.0))
    return {"reference": "pygame/ai/pathfinder.py", "random_policy": "no shuffle, zero noise, random=0.1",
            "fixtures": fixtures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()
    data = json.dumps(build(), indent=2) + "\n"
    if options.check:
        if OUTPUT.read_text(encoding="utf-8") != data:
            raise SystemExit("Python AI fixtures are stale")
        print("Python AI fixtures match the current legacy Pathfinder")
    else:
        OUTPUT.parent.mkdir(exist_ok=True)
        OUTPUT.write_text(data, encoding="utf-8")
        print(f"Wrote {len(json.loads(data)['fixtures'])} Python AI reference decisions")


if __name__ == "__main__":
    main()
