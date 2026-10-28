"""Run 12 seeded four-AI matches without the UI's three-second pacing."""

import random
import sys
from pathlib import Path
from time import perf_counter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.pathfinder import search
from game import Game
from settings import PLAYER_NAMES


def main():
    timings = []
    wins = dict.fromkeys(PLAYER_NAMES, 0)
    unfinished = 0
    wall_actions = 0
    longest_step = 0.0
    for seed in range(4):
        for levels in (("Casual",) * 4, ("Challenging",) * 4,
                       ("Casual", "Challenging", "Casual", "Challenging")):
            rng = random.Random(seed)
            game = Game("Battle Royale", controllers=[f"AI - {s}" for s in levels])
            for turn in range(400):
                started = perf_counter()
                proposals = search(game, game.ai_difficulty, rng=rng)
                action = None
                while True:
                    step_started = perf_counter()
                    try:
                        action = next(proposals)
                    except StopIteration:
                        break
                    longest_step = max(longest_step, perf_counter() - step_started)
                timings.append(perf_counter() - started)
                if action is None:
                    raise AssertionError(f"No action, seed {seed}, turn {turn}")
                kind, target = action
                success = game.move(target) if kind == "move" else game.place_wall(target)
                if not success:
                    raise AssertionError(f"Illegal action: {action}")
                wall_actions += kind == "wall"
                if game.winner is not None:
                    wins[PLAYER_NAMES[game.winner]] += 1
                    break
            else:
                unfinished += 1
    print(f"12 matches, seeds 0-3; all Casual, all Challenging, mixed: {wins}")
    print(f"Unfinished at 400 turns: {unfinished}; wall actions: {wall_actions}")
    print(f"Decisions: {len(timings)}, mean: {sum(timings) / len(timings):.4f}s, "
          f"maximum: {max(timings):.4f}s, longest step: {longest_step:.4f}s")


if __name__ == "__main__":
    main()
