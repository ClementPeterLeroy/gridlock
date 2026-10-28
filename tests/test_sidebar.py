"""Measure rendered player labels against the visible highlight cards."""

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault('SDL_VIDEODRIVER', 'dummy')
os.environ.setdefault('SDL_AUDIODRIVER', 'dummy')
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame
import board
from identity import IdentityAssets, fit_image
from main import create_game
from match_config import MatchConfig
from game import FOUR_PLAYER_ORDER


class SidebarTests(unittest.TestCase):
    def test_actual_text_bounds_and_no_controller_labels(self):
        pygame.init()
        try:
            screen = pygame.display.set_mode((930, 650))
            fonts = IdentityAssets().fonts
            for mode in ('Versus', 'Battle Royale', 'Blitz', 'Rise of the Machines'):
                config = MatchConfig.for_mode(mode)
                config.names = ['W' * 12] * 4
                game = create_game(config)
                order = FOUR_PLAYER_ORDER if game.player_count == 4 else (0, 1)
                for slot, player in enumerate(order):
                    game.current_player = player
                    rendered = []
                    actual_draw = board.draw_text
                    def draw(screen, font, value, x, y, color=board.TEXT, width=None):
                        label = font.render(str(value), True, color)
                        if width and label.get_width() > width:
                            label = fit_image(label, (width, label.get_height()))
                        rendered.append((str(value), label.get_rect(topleft=(x, y))))
                        actual_draw(screen, font, value, x, y, color, width)
                    with patch.object(board, 'draw_text', side_effect=draw):
                        board.draw_board(screen, game, set(), False, 'H', (0, 0), fonts, True)
                    card = board.player_info_rect(slot, game.player_count)
                    labels = [(text, rect) for text, rect in rendered if rect.colliderect(card)]
                    self.assertTrue(any(text.startswith('Walls:') for text, _ in labels))
                    for text, rect in labels:
                        self.assertTrue(card.contains(rect), f'{mode}: {text} overflows {card}: {rect}')
                        self.assertNotIn(text, ('Human', 'AI', 'Casual AI', 'Challenging AI', 'Casual', 'Challenging'))
                    if mode == 'Blitz':
                        self.assertTrue(any(text.startswith('Clock:') for text, _ in labels))
        finally:
            pygame.quit()


if __name__ == '__main__':
    unittest.main()
