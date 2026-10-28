"""Fixed-size fullscreen rendering and coordinate translation checks."""

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault('SDL_VIDEODRIVER', 'dummy')
os.environ.setdefault('SDL_AUDIODRIVER', 'dummy')
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame
from display import GameDisplay
from settings import BACKGROUND
from board import preview_wall, wall_rect, draw_victory
from game import Game
from identity import IdentityAssets
from startup import play_startup


class DisplayTests(unittest.TestCase):
    def setUp(self):
        pygame.init()
        self.display = GameDisplay()

    def tearDown(self):
        pygame.quit()

    def test_centered_canvas_pixels_are_not_scaled(self):
        display = self.display
        display.window = pygame.Surface((1600, 900))
        display.canvas.fill('red')
        display.canvas.set_at((100, 100), 'blue')
        display.present()
        self.assertEqual(display.offset, (335, 125))
        self.assertEqual(display.canvas.get_size(), (930, 650))
        self.assertEqual(display.window.get_at((435, 225)), pygame.Color('blue'))
        self.assertEqual(tuple(display.window.get_at((0, 0)))[:3], BACKGROUND)
        self.assertEqual(display.window.get_at((336, 126)), pygame.Color('red'))
        self.assertEqual(tuple(display.window.get_at((1265, 775)))[:3], BACKGROUND)

    def test_click_motion_and_wall_hover_share_offset(self):
        display = self.display
        display.window = pygame.Surface((1600, 900))
        pos = wall_rect((3, 3, 'H')).center
        physical = (pos[0] + 335, pos[1] + 125)
        event = pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=physical, button=1)
        translated = display.translate_event(event)
        self.assertEqual(translated.pos, pos)
        self.assertEqual(event.pos, physical)
        self.assertEqual(preview_wall(Game(), False, 'H', translated.pos), (3, 3, 'H'))
        self.assertIsNone(preview_wall(Game(), False, 'H', display.to_logical((0, 0))))

    def test_repeated_real_sdl_mode_switches_preserve_canvas(self):
        display = self.display
        canvas = display.canvas
        canvas.fill('blue')
        desktop = pygame.display.get_desktop_sizes()[0]
        for _ in range(4):
            display.set_fullscreen(True)
            self.assertTrue(display.fullscreen)
            self.assertEqual(display.window.get_size(), desktop)
            display.present()
            display.set_fullscreen(False)
            self.assertFalse(display.fullscreen)
            self.assertEqual(display.window.get_size(), (930, 650))
            self.assertIs(display.canvas, canvas)
            self.assertEqual(canvas.get_at((10, 10)), pygame.Color('blue'))

    def test_small_desktop_stays_windowed(self):
        with patch('display.pygame.display.get_desktop_sizes', return_value=[(800, 600)]), \
             self.assertLogs('display', level='WARNING'):
            self.display.set_fullscreen(True)
        self.assertFalse(self.display.fullscreen)

    def test_startup_and_victory_present_on_fullscreen_canvas(self):
        display = self.display
        display.window = pygame.Surface((1600, 900))
        def reader(path):
            yield {'size': (2, 2), 'fps': 20}
            yield bytes((255, 0, 0)) * 4
        with patch('startup.pygame.event.get', return_value=[]):
            self.assertTrue(play_startup(display.canvas, SimpleNamespace(tick=lambda fps: 50),
                                         reader_factory=reader, present=display.present))
        self.assertEqual(display.window.get_at((800, 450)), pygame.Color('red'))
        assets = IdentityAssets()
        game = Game()
        game.winner = 0
        draw_victory(display.canvas, game, assets.stickers_for(game), assets.fonts)
        display.present()
        self.assertEqual(display.window.get_at((800, 450)), display.canvas.get_at((465, 325)))


if __name__ == '__main__':
    unittest.main()
