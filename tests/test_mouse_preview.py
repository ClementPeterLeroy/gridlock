"""Real Pygame rendering smoke checks for hover feedback, without a window."""

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame
from board import (preview_wall, wall_at, wall_rect, draw_board, button_rects,
                   STEP)
from game import Game
from settings import (BOARD_X, BOARD_Y, CELL_SIZE, GAP, WINDOW_WIDTH,
                      WINDOW_HEIGHT)


def intersection(row=3, col=3):
    return (BOARD_X + (col + 1) * STEP - GAP // 2 - 1,
            BOARD_Y + (row + 1) * STEP - GAP // 2 - 1)


class MousePreviewTests(unittest.TestCase):
    def test_hover_follows_slots_and_disappears_off_grooves(self):
        game = Game()
        self.assertEqual(preview_wall(game, False, "H", intersection()), (3, 3, "H"))
        self.assertEqual(preview_wall(game, False, "H", intersection(4, 4)), (4, 4, "H"))
        for pos in ((0, 0), (BOARD_X + 3, BOARD_Y + 3),
                    *[r.center for r in button_rects().values()]):
            self.assertIsNone(preview_wall(game, False, "H", pos))
        # A small margin beside the groove helps aiming; square centers stay clear.
        self.assertEqual(wall_at((BOARD_X + CELL_SIZE - 1,
                                 BOARD_Y + CELL_SIZE - 1), "H"), (0, 0, "H"))
        self.assertIsNone(wall_at((BOARD_X + CELL_SIZE // 2,
                                   BOARD_Y + CELL_SIZE // 2), "H"))
        for direction in ("H", "V"):
            x, y = intersection()
            near = (x, y - 6) if direction == "H" else (x - 6, y)
            far = (x, y - 10) if direction == "H" else (x - 10, y)
            self.assertEqual(wall_at(near, direction), (3, 3, direction))
            self.assertIsNone(wall_at(far, direction))

    def test_preview_guards_and_rotation(self):
        game = Game()
        self.assertEqual(preview_wall(game, False, "V", intersection()), (3, 3, "V"))
        self.assertIsNone(preview_wall(game, True, "H", intersection()))
        game.walls_left[0] = 0
        self.assertIsNone(preview_wall(game, False, "H", intersection()))
        game.walls_left[0] = 10
        game.winner = 0
        self.assertIsNone(preview_wall(game, False, "H", intersection()))
        game = Game("Rise of the Machines", current_player=1)
        self.assertIsNone(preview_wall(game, False, "H", intersection()))

    def test_rendered_hover_color_and_removal(self):
        pygame.init()
        try:
            screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
            fonts = tuple(pygame.font.Font(None, size) for size in (36, 18, 15))
            game = Game()
            def render(selected, pos, direction="H"):
                draw_board(screen, game, set(), selected, direction, pos, fonts)
                return screen.get_at(wall_rect((3, 3, direction)).center)
            base = render(False, (0, 0))
            gold = render(False, intersection())
            self.assertNotEqual(base, gold)
            self.assertEqual(render(True, intersection()), base)
            self.assertEqual(render(False, (0, 0)), base)
            # A crossing wall is invalid, so its preview must be visibly red.
            game.walls.add((3, 3, "V"))
            red = render(False, intersection())
            self.assertGreater(red.r, red.g * 1.5)
            self.assertNotEqual(red, gold)
            pygame.display.flip()
        finally:
            pygame.quit()


if __name__ == "__main__":
    unittest.main()
