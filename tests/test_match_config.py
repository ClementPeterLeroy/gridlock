"""Match options, timeout elimination, and pause model checks."""

import random
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from match_config import MatchConfig, clean_name
from game import Game, FOUR_PLAYER_ORDER
from main import create_game, restart_game
from ai.pathfinder import search
from rules import wall_error, valid_moves, has_path


class MatchConfigTests(unittest.TestCase):
    def test_names_defaults_limit_and_ai_identity(self):
        self.assertEqual(clean_name('  ', 2), 'Emerald')
        self.assertEqual(clean_name('abcdefghijklmnop', 0), 'abcdefghijkl')
        config = MatchConfig.for_mode('Battle Royale')
        config.names[0] = 'Alex'
        game = create_game(config)
        self.assertEqual(game.display_name(0), 'Alex')
        self.assertEqual(game.display_name(1), 'Crimson')

    def test_random_start_and_clockwise_order_for_every_seat(self):
        config = MatchConfig.for_mode('Battle Royale')
        config.random_start = True
        for player in range(4):
            with patch('main.random.choice', return_value=player):
                game = create_game(config)
            expected = list(FOUR_PLAYER_ORDER)
            index = expected.index(player)
            expected = expected[index:] + expected[:index]
            for p in expected:
                self.assertEqual(game.current_player, p)
                game.next_turn()
        config.random_start = False
        with patch('main.random.choice') as choice:
            self.assertEqual(create_game(config).current_player, 0)
        choice.assert_not_called()

    def test_random_two_player_alternation(self):
        for mode in ('Versus', 'Blitz', 'Rise of the Machines'):
            config = MatchConfig.for_mode(mode)
            config.random_start = True
            with patch('main.random.choice', return_value=1):
                game = create_game(config)
            self.assertEqual(game.current_player, 1)
            game.next_turn()
            self.assertEqual(game.current_player, 0)

    def test_restart_copies_configuration_and_rerolls_random_start(self):
        config = MatchConfig.for_mode('Battle Royale')
        config.names[0] = 'Alex'
        config.turn_limit, config.random_start = 30, True
        with patch('main.random.choice', side_effect=[2, 3]):
            game = create_game(config)
            restarted = restart_game(game)
        self.assertEqual(restarted.config, config)
        self.assertEqual(restarted.current_player, 3)
        restarted.config.names[0] = 'Pat'
        self.assertEqual(game.config.names[0], 'Alex')
        self.assertEqual(restarted.walls_left, [5] * 4)

    def test_turn_limits_and_untimed(self):
        for limit in (15, 30, 60, 120):
            config = MatchConfig.for_mode('Versus')
            config.turn_limit = limit
            game = create_game(config)
            game.tick(limit - 0.1)
            self.assertIsNone(game.winner)
            game.tick(0.1)
            self.assertEqual(game.winner, 1)
            self.assertIn('ran out of time', game.message)
        game = create_game(MatchConfig.for_mode('Versus'))
        game.tick(100000)
        self.assertIsNone(game.winner)

    def test_battle_timeout_removes_pawn_and_skips_seat(self):
        config = MatchConfig.for_mode('Battle Royale')
        config.turn_limit = 15
        game = create_game(config)
        game.walls.add((3, 3, 'H'))
        game.tick(15)
        self.assertIsNone(game.winner)
        self.assertEqual(game.eliminated, {0})
        self.assertIsNone(game.pawns[0])
        self.assertEqual(game.current_player, 2)
        self.assertIn((3, 3, 'H'), game.walls)
        self.assertEqual(valid_moves(game.pawns, 0, game.walls), set())
        self.assertIsNone(wall_error((5, 5, 'H'), game.walls, game.pawns, 5))
        for expected in (1, 3, 2, 1):
            game.next_turn()
            self.assertEqual(game.current_player, expected)

    def test_last_survivor_wins_and_undo_restores_elimination(self):
        config = MatchConfig.for_mode('Battle Royale')
        config.turn_limit = 15
        game = create_game(config)
        for _ in range(3):
            game.tick(15)
        self.assertEqual(game.winner, 3)
        self.assertEqual(game.active_players, [3])
        self.assertTrue(game.undo())
        self.assertIsNone(game.winner)
        self.assertEqual(game.active_players, [1, 3])
        self.assertIsNotNone(game.pawns[1])

    def test_blitz_clock_choices_keep_penalty_and_minimum(self):
        for minutes in (1, 3, 5):
            config = MatchConfig.for_mode('Blitz')
            config.blitz_minutes = minutes
            game = create_game(config)
            self.assertEqual(game.time_left, [minutes * 60] * 2)
            game.time_left[1] = 2
            game.next_turn()
            self.assertEqual(game.time_left[1], 10)
            game.tick(10)
            self.assertEqual(game.walls_left[1], 9)
            self.assertEqual(game.overtime, 15)
            game.tick(15)
            self.assertEqual(game.winner, 0)

    def test_paused_model_suspends_timers_and_actions(self):
        for mode in ('Versus', 'Battle Royale', 'Blitz'):
            config = MatchConfig.for_mode(mode)
            config.turn_limit = 15
            game = create_game(config)
            game.paused = True
            before = game.snapshot()
            game.tick(1000)
            self.assertFalse(game.move((7, 4)))
            self.assertFalse(game.place_wall((3, 3, 'H')))
            self.assertEqual(game.snapshot(), before)
            game.paused = False
            self.assertTrue(game.move((7, 4)))

    def test_ai_after_elimination_uses_live_players_only(self):
        game = create_game(MatchConfig.for_mode('Battle Royale'))
        game.forfeit()
        action = list(search(game, 'Challenging', rng=random.Random(3)))[-1]
        kind, target = action
        self.assertTrue(game.move(target) if kind == 'move' else game.place_wall(target))
        self.assertTrue(all(has_path(p, i, game.walls) for i, p in enumerate(game.pawns) if p is not None))

    def test_three_survivor_ai_match_completes_after_forfeit(self):
        config = MatchConfig.for_mode('Battle Royale')
        config.controllers = ['AI - Casual'] * 4
        game = create_game(config)
        game.forfeit()
        rng = random.Random(19)
        for _ in range(300):
            kind, target = list(search(game, game.ai_difficulty, rng=rng))[-1]
            self.assertTrue(game.move(target) if kind == 'move' else game.place_wall(target))
            if game.winner is not None:
                break
        self.assertIsNotNone(game.winner)
        self.assertNotEqual(game.winner, 0)


if __name__ == '__main__':
    unittest.main()
