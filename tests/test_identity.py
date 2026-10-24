"""Identity assets, personalized banner caching, and startup lifecycle."""

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import xml.etree.ElementTree as ET

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame
import main
from identity import IdentityAssets, ROOT, fit_image
from match_config import MatchConfig
from startup import play_startup


class IdentityTests(unittest.TestCase):
    def setUp(self):
        pygame.init()
        self.screen = pygame.display.set_mode((930, 650))

    def tearDown(self):
        pygame.quit()

    def test_color_defaults_for_humans_and_ai(self):
        game = main.create_game(MatchConfig.for_mode("Battle Royale"))
        self.assertEqual([game.display_name(i) for i in range(4)],
                         ["Sapphire", "Crimson", "Emerald", "Violet"])
        game.config.names[0] = "Ella"
        game.config.names[1] = "Ignored AI name"
        self.assertEqual(game.display_name(0), "Ella")
        self.assertEqual(game.display_name(1), "Crimson")

    def test_text_free_svg_and_transparent_templates(self):
        assets = IdentityAssets()
        for name, image in zip(("sapphire", "crimson", "emerald", "violet"), assets.templates):
            root = ET.parse(ROOT / "px" / f"{name}_victory.svg").getroot()
            self.assertFalse(any(node.tag.endswith("}text") for node in root.iter()))
            self.assertIsNotNone(image)
            self.assertEqual(image.get_at((0, 0)).a, 0)

    def test_dynamic_text_is_drawn_in_banner_only(self):
        assets = IdentityAssets()
        game = main.create_game(MatchConfig.for_mode("Versus"))
        game.config.names[0] = "Ella"
        first = assets.stickers_for(game)[0]
        game.config.names[0] = "Peter"
        second = assets.stickers_for(game)[0]
        self.assertNotEqual(pygame.image.tobytes(first, "RGBA"), pygame.image.tobytes(second, "RGBA"))
        self.assertEqual(pygame.image.tobytes(first.subsurface((0, 0, 540, 250)), "RGBA"),
                         pygame.image.tobytes(second.subsurface((0, 0, 540, 250)), "RGBA"))

    def test_correct_template_and_affected_cache_entries(self):
        assets = IdentityAssets()
        game = main.create_game(MatchConfig.for_mode("Battle Royale"))
        first = assets.stickers_for(game)
        for player, image in first.items():
            base = pygame.transform.smoothscale(assets.templates[player], (540, 312))
            self.assertEqual(pygame.image.tobytes(image.subsurface((0, 0, 540, 250)), "RGBA"),
                             pygame.image.tobytes(base.subsurface((0, 0, 540, 250)), "RGBA"))
        replay = assets.stickers_for(main.restart_game(game))
        self.assertTrue(all(first[i] is replay[i] for i in first))
        game.config.names[0] = "Changed"
        changed = assets.stickers_for(game)
        self.assertIsNot(first[0], changed[0])
        self.assertTrue(all(first[i] is changed[i] for i in (1, 2, 3)))
        self.assertEqual(len(assets._stickers), 4)

    def test_long_uppercase_names_fit_banner(self):
        assets = IdentityAssets()
        for text in ("W" * 12 + " WINS!", "SAPPHIRE WINS!", "ß".upper() * 12 + " WINS!"):
            label = assets.banner_text(text)
            self.assertLessEqual(label.get_width(), 196)
            self.assertLessEqual(label.get_height(), 29)

    def test_icon_logo_fonts_and_font_cache(self):
        assets = IdentityAssets()
        self.assertEqual(assets.icon.get_size(), (128, 128))
        self.assertEqual(tuple(assets.icon.get_at((0, 0)))[:3], (255, 255, 255))
        logo = fit_image(assets.logo, (560, 160))
        self.assertLessEqual(logo.get_width(), 560)
        self.assertLessEqual(logo.get_height(), 160)
        self.assertIs(assets.font("display", 32), assets.fonts[0])
        for license_name in ("Cinzel-OFL.txt", "Lato-OFL.txt"):
            self.assertIn("SIL OPEN FONT LICENSE", (ROOT / "fonts" / license_name).read_text())

    def test_missing_assets_and_fonts_have_fallbacks_and_warnings(self):
        folder = ROOT / "missing-test-assets"
        self.assertFalse(folder.exists())
        with self.assertLogs("identity", level="WARNING"):
            assets = IdentityAssets(folder)
            game = main.create_game(MatchConfig.for_mode("Versus"))
            stickers = assets.stickers_for(game)
        self.assertIsNone(assets.logo)
        self.assertGreater(assets.fonts[0].render("GRIDLOCK", True, "white").get_width(), 0)
        self.assertEqual(stickers[0].get_size(), (540, 312))

    def test_startup_does_not_skip_frames_on_keypress(self):
        decoded = []
        def reader(path):
            yield {"size": (2, 2), "fps": 20}
            for color in ((255, 0, 0), (0, 255, 0), (0, 0, 255)):
                decoded.append(color)
                yield bytes(color) * 4
        clock = SimpleNamespace(tick=lambda fps: 50)
        press = pygame.event.Event(pygame.KEYDOWN, key=pygame.K_SPACE)
        with patch("startup.pygame.event.get", return_value=[press]):
            self.assertTrue(play_startup(self.screen, clock, reader_factory=reader))
        self.assertEqual(len(decoded), 3)
        self.assertEqual(tuple(self.screen.get_at((465, 325)))[:3], (0, 0, 255))

    def test_startup_window_close_stops_decoder(self):
        closed = []
        def reader(path):
            try:
                yield {"size": (2, 2), "fps": 20}
                while True:
                    yield bytes((0, 0, 0)) * 4
            finally:
                closed.append(True)
        with patch("startup.pygame.event.get", return_value=[pygame.event.Event(pygame.QUIT)]):
            self.assertFalse(play_startup(self.screen, SimpleNamespace(tick=lambda fps: 16), reader_factory=reader))
        self.assertEqual(closed, [True])

    def test_missing_or_broken_startup_falls_through(self):
        with self.assertLogs("startup", level="WARNING"):
            self.assertTrue(play_startup(self.screen, SimpleNamespace(tick=lambda fps: 16), path="missing-gridlock.mp4"))
        def broken(path):
            raise RuntimeError("bad video")
        with self.assertLogs("startup", level="WARNING"), patch("startup.pygame.event.get", return_value=[]):
            self.assertTrue(play_startup(self.screen, SimpleNamespace(tick=lambda fps: 16), reader_factory=broken))

    def test_closing_startup_prevents_music_and_sets_icon(self):
        with patch.object(main, "play_startup", return_value=False) as intro, \
             patch.object(main, "load_audio") as music, \
             patch.object(main.pygame.display, "set_icon") as icon:
            main.main()
        intro.assert_called_once()
        music.assert_not_called()
        icon.assert_called_once()
        self.assertFalse(pygame.get_init())


if __name__ == "__main__":
    unittest.main()
