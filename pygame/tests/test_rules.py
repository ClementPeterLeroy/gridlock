import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from game import Game
from rules import valid_moves, wall_error, reached_goal, has_path


class GridlockTests(unittest.TestCase):
    def test_two_player_starts(self):
        g = Game('Versus')
        self.assertEqual(g.pawns, [(8, 4), (0, 4)])
        self.assertEqual(g.walls_left, [10, 10])

    def test_four_player_starts(self):
        g = Game('Battle Royale')
        self.assertEqual(g.pawns, [(8, 4), (0, 4), (4, 0), (4, 8)])
        self.assertEqual(g.walls_left, [5, 5, 5, 5])

    def test_clockwise_turn_order(self):
        g = Game('Battle Royale')
        order = []
        for _ in range(4):
            order.append(g.current_player)
            g.next_turn()
        self.assertEqual(order, [0, 2, 1, 3])

    def test_goals(self):
        for player, target in enumerate([(0, 6), (8, 1), (2, 8), (6, 0)]):
            self.assertTrue(reached_goal(target, player))

    def test_opening_moves(self):
        g = Game('Versus')
        self.assertEqual(valid_moves(g.pawns, 0, g.walls), {(7, 4), (8, 3), (8, 5)})

    def test_jump(self):
        self.assertIn((2, 4), valid_moves([(4, 4), (3, 4)], 0, set()))

    def test_diagonal_when_jump_blocked(self):
        moves = valid_moves([(4, 4), (3, 4)], 0, {(2, 4, 'H')})
        self.assertIn((3, 3), moves)
        self.assertIn((3, 5), moves)
        self.assertNotIn((2, 4), moves)

    def test_no_diagonal_if_jump_possible(self):
        moves = valid_moves([(4, 4), (3, 4)], 0, set())
        self.assertNotIn((3, 3), moves)

    def test_no_occupied_destinations(self):
        pawns = [(4, 4), (3, 4), (3, 5), (8, 8)]
        self.assertFalse(set(pawns[1:]) & valid_moves(pawns, 0, set()))

    def test_wall_crossing(self):
        g = Game('Versus')
        g.walls.add((3, 4, 'H'))
        self.assertIsNotNone(wall_error((3, 4, 'V'), g.walls, g.pawns, 10))

    def test_wall_path_validation_all_players(self):
        pawns = [(8, 4), (0, 4), (4, 0), (4, 8)]
        self.assertTrue(all(has_path(p, i, set()) for i, p in enumerate(pawns)))

    def test_turn_and_undo(self):
        g = Game('Versus')
        self.assertTrue(g.move((7, 4)))
        self.assertEqual(g.current_player, 1)
        self.assertTrue(g.undo())
        self.assertEqual(g.current_player, 0)
        self.assertEqual(g.pawns[0], (8, 4))

    def test_blitz_no_free_time_above_ten(self):
        g = Game('Blitz')
        g.time_left[1] = 25
        g.next_turn()
        self.assertEqual(g.time_left[1], 25)

    def test_blitz_minimum_ten(self):
        g = Game('Blitz')
        g.time_left[1] = 3
        g.next_turn()
        self.assertEqual(g.time_left[1], 10)

    def test_blitz_penalty_once_per_turn(self):
        g = Game('Blitz')
        g.time_left[0] = 1
        g.tick(1)
        self.assertEqual(g.walls_left[0], 9)
        self.assertEqual(g.overtime, 15)
        g.tick(15)
        self.assertEqual(g.walls_left[0], 9)
        self.assertEqual(g.winner, 1)

    def test_blitz_no_walls_forfeit(self):
        g = Game('Blitz')
        g.walls_left[0] = 0
        g.time_left[0] = 1
        g.tick(1)
        self.assertEqual(g.winner, 1)

    def test_regular_timer_no_penalty(self):
        g = Game('Versus')
        g.tick(200)
        self.assertEqual(g.walls_left[0], 10)
        self.assertEqual(g.turn_elapsed, 200)


if __name__ == '__main__':
    unittest.main()
