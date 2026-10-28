"""Optional reproducible comparison: python tests/benchmark_pathfinder.py."""

import random
import sys
from pathlib import Path
from time import perf_counter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.pathfinder import search
from game import Game


def main():
    wins = {"Casual": 0, "Challenging": 0}
    unfinished = 0
    times = []
    longest_step = 0.0
    for seed in range(10):
        for challenging_player in (0, 1):
            rng = random.Random(seed)
            game = Game()
            levels = ["Casual", "Casual"]
            levels[challenging_player] = "Challenging"
            for turn in range(300):
                started = perf_counter()
                proposals = search(game, levels[game.current_player], rng=rng)
                action = None
                while True:
                    step_started = perf_counter()
                    try:
                        action = next(proposals)
                    except StopIteration:
                        break
                    longest_step = max(longest_step, perf_counter() - step_started)
                times.append(perf_counter() - started)
                kind, target = action
                success = game.move(target) if kind == "move" else game.place_wall(target)
                if not success:
                    raise AssertionError(f"Illegal proposal: {action}")
                if game.winner is not None:
                    wins[levels[game.winner]] += 1
                    break
            else:
                unfinished += 1
    print(f"20 matches, seeds 0-9, alternating Sapphire/Crimson: {wins}")
    print(f"Unfinished at 300 turns: {unfinished}")
    print(f"Decisions: {len(times)}, mean: {sum(times) / len(times):.4f}s, "
          f"maximum: {max(times):.4f}s, longest search step: {longest_step:.4f}s")


if __name__ == "__main__":
    main()
