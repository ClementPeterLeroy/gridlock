import random
import sys
import unittest
from pathlib import Path
from time import perf_counter
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.pathfinder import search, immediate_win
from game import Game
from rules import has_path, valid_moves, wall_error


def choose(game, difficulty="Challenging", **kwargs):
    return list(search(game, difficulty, rng=random.Random(42), **kwargs))[-1]


def execute(game, action):
    kind, target = action
    return game.move(target) if kind == "move" else game.place_wall(target)


class PathfinderTests(unittest.TestCase):
    def test_every_proposal_legal_and_state_unchanged(self):
        game = Game()
        before = game.snapshot()
        for difficulty in ("Casual", "Challenging"):
            for kind, target in search(game, difficulty, rng=random.Random(1)):
                if kind == "move":
                    self.assertIn(target, valid_moves(game.pawns, 0, game.walls))
                else:
                    self.assertIsNone(wall_error(target, game.walls, game.pawns, 10))
                    self.assertTrue(all(has_path(p, i, game.walls | {target})
                                        for i, p in enumerate(game.pawns)))
        self.assertEqual(game.snapshot(), before)

    def test_immediate_win_both_difficulties(self):
        for difficulty in ("Casual", "Challenging"):
            game = Game(pawns=[(5, 0), (7, 4)], current_player=1)
            self.assertTrue(execute(game, choose(game, difficulty)))
            self.assertEqual(game.winner, 1)

    def test_stops_immediate_threat(self):
        for difficulty in ("Casual", "Challenging"):
            game = Game(pawns=[(1, 4), (4, 0)], current_player=1)
            self.assertTrue(immediate_win(game.pawns, 0, game.walls))
            self.assertTrue(execute(game, choose(game, difficulty)))
            self.assertFalse(immediate_win(game.pawns, 0, game.walls))

    def test_zero_walls_and_adjacent_pawns(self):
        for walls in (set(), {(5, 4, "H")}):
            game = Game(pawns=[(4, 4), (3, 4)], current_player=1,
                        walls=walls, walls_left=[0, 0])
            action = choose(game)
            self.assertEqual(action[0], "move")
            self.assertTrue(execute(game, action))

    def test_conserves_walls_without_useful_placement(self):
        # With a clear lead, advancing is more useful than delaying a distant pawn.
        game = Game(pawns=[(8, 0), (6, 8)], current_player=1)
        self.assertEqual(choose(game)[0], "move")

    def test_zero_budget_keeps_legal_fallback(self):
        game = Game(current_player=1)
        start = perf_counter()
        action = choose(game, time_limit=0)
        self.assertLess(perf_counter() - start, 0.1)
        self.assertTrue(execute(game, action))

    def test_deadline_interrupts_search(self):
        game = Game()
        with patch("ai.pathfinder.perf_counter", side_effect=[0, 0.1]):
            proposals = list(search(game, time_limit=0.01))
        self.assertEqual(len(proposals), 1)
        self.assertTrue(execute(game, proposals[0]))

    def test_complete_matches(self):
        for first in ("Casual", "Challenging"):
            game = Game()
            rng = random.Random(123)
            for turn in range(300):
                difficulty = first if game.current_player == 0 else (
                    "Challenging" if first == "Casual" else "Casual")
                proposals = list(search(game, difficulty, rng=rng))
                self.assertTrue(proposals)
                self.assertTrue(execute(game, proposals[-1]))
                if game.winner is not None:
                    break
            self.assertIsNotNone(game.winner, f"Match did not finish: {first}")


if __name__ == "__main__":
    unittest.main()
