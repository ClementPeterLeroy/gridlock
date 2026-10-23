"""Four-seat Pathfinder and controller regression tests."""

import itertools
import random
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.pathfinder import search, distance, immediate_win
from game import Game, CONTROL_OPTIONS, FOUR_PLAYER_ORDER
from rules import valid_moves, wall_error, has_path


def choose(game, level="Challenging", **kwargs):
    return list(search(game, level, rng=random.Random(7), **kwargs))[-1]


def execute(game, action):
    kind, target = action
    return game.move(target) if kind == "move" else game.place_wall(target)


class BattleAITests(unittest.TestCase):
    def test_all_seat_configurations_and_clockwise_turns(self):
        for controllers in itertools.product(CONTROL_OPTIONS, repeat=4):
            game = Game("Battle Royale", controllers=list(controllers))
            self.assertEqual(game.walls_left, [5] * 4)
            for player in FOUR_PLAYER_ORDER:
                self.assertEqual(game.current_player, player)
                self.assertEqual(game.is_ai_turn, controllers[player] != "Human")
                game.next_turn()

    def test_all_goals_and_immediate_victories(self):
        near_goals = [(1, 2), (7, 6), (2, 7), (6, 1)]
        for player in range(4):
            for level in ("Casual", "Challenging"):
                game = Game("Battle Royale", current_player=player)
                game.pawns[player] = near_goals[player]
                self.assertEqual(distance(game.pawns[player], player, set()), 1)
                self.assertTrue(execute(game, choose(game, level)))
                self.assertEqual(game.winner, player)

    def test_all_proposals_legal_with_four_players(self):
        for player in range(4):
            for level in ("Casual", "Challenging"):
                game = Game("Battle Royale", current_player=player)
                before = game.snapshot()
                for kind, target in search(game, level, rng=random.Random(8)):
                    if kind == "move":
                        self.assertIn(target, valid_moves(game.pawns, player, game.walls))
                    else:
                        self.assertIsNone(wall_error(target, game.walls, game.pawns, 5))
                        self.assertTrue(all(has_path(p, i, game.walls | {target})
                                            for i, p in enumerate(game.pawns)))
                self.assertEqual(game.snapshot(), before)

    def test_threat_recognition_from_each_opponent(self):
        threats = {1: (7, 2), 2: (2, 7), 3: (6, 1)}
        for opponent, pos in threats.items():
            for level in ("Casual", "Challenging"):
                game = Game("Battle Royale")
                game.pawns[opponent] = pos
                self.assertTrue(immediate_win(game.pawns, opponent, game.walls))
                action = choose(game, level)
                self.assertEqual(action[0], "wall")
                self.assertTrue(execute(game, action))
                self.assertFalse(immediate_win(game.pawns, opponent, game.walls))
                self.assertTrue(all(has_path(p, i, game.walls) for i, p in enumerate(game.pawns)))

    def test_adjacent_pawns_and_no_walls(self):
        for player in range(4):
            game = Game("Battle Royale", current_player=player,
                        pawns=[(4, 4), (3, 4), (3, 5), (4, 5)], walls_left=[0] * 4)
            for level in ("Casual", "Challenging"):
                action = choose(game, level)
                self.assertEqual(action[0], "move")
                self.assertIn(action[1], valid_moves(game.pawns, player, game.walls))

    def test_budget_fallback_and_ten_second_cap(self):
        for player in range(4):
            game = Game("Battle Royale", current_player=player)
            self.assertTrue(execute(game, choose(game, time_limit=0)))
        game = Game("Battle Royale")
        with patch("ai.pathfinder.perf_counter", side_effect=[0, 10.01]):
            proposals = list(search(game, time_limit=100))
        self.assertEqual(len(proposals), 1)
        self.assertTrue(execute(game, proposals[0]))

    def test_wall_fallback_when_pawns_block_all_moves(self):
        game = Game("Battle Royale", pawns=[(8, 0), (7, 0), (6, 0), (5, 0)],
                    walls={(7, 0, "V"), (5, 0, "V")})
        self.assertEqual(valid_moves(game.pawns, 0, game.walls), set())
        self.assertTrue(all(has_path(p, i, game.walls) for i, p in enumerate(game.pawns)))
        action = choose(game, time_limit=0)
        self.assertEqual(action[0], "wall")
        self.assertTrue(execute(game, action))

    def test_complete_four_ai_games(self):
        for levels in (("Casual",) * 4, ("Challenging",) * 4,
                       ("Casual", "Challenging", "Casual", "Challenging")):
            game = Game("Battle Royale", controllers=[f"AI - {s}" for s in levels])
            rng = random.Random(12)
            for turn in range(400):
                proposals = list(search(game, game.ai_difficulty, rng=rng))
                self.assertTrue(proposals, f"No legal fallback on turn {turn}")
                self.assertTrue(execute(game, proposals[-1]))
                if game.winner is not None:
                    break
            self.assertIsNotNone(game.winner, f"Unfinished: {levels}")


if __name__ == "__main__":
    unittest.main()
