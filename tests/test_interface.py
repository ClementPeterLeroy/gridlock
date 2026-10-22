"""Exercise real event handling without a window or audio device."""

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame
import main
from board import (menu_buttons, settings_buttons, button_rects, victory_buttons,
                   difficulty_buttons)
from game import Game


def click(rect, button=1):
    return pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=rect.center, button=button)


class InterfaceTests(unittest.TestCase):
    def run_frames(self, frames, factory=Game):
        states = []
        frames = iter(frames + [[pygame.event.Event(pygame.QUIT)]])
        with patch.object(main.pygame.event, "get", side_effect=lambda: next(frames)), \
             patch.object(main.pygame.time, "Clock", return_value=SimpleNamespace(tick=lambda fps: 16)), \
             patch.object(main, "Game", side_effect=factory), \
             patch.object(main, "load_audio", return_value={}), \
             patch.object(main, "play_sound") as sound, \
             patch.object(main, "set_music") as music, \
             patch.object(main, "draw_board", side_effect=lambda *args: states.append(
                 (args[1].mode, args[3], args[4], args[1].winner))), \
             patch.object(main, "draw_settings", wraps=main.draw_settings) as settings:
            main.main()
        return states, sound, music, settings

    def test_rotation_only_during_wall_placement(self):
        states, _, _, _ = self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(pygame.Rect(0, 0, 1, 1), 3)],
            [click(button_rects()["Wall"])],
            [click(pygame.Rect(0, 0, 1, 1), 3)],
            [pygame.event.Event(pygame.KEYDOWN, key=pygame.K_r, mod=0)],
        ])
        self.assertEqual([s[2] for s in states[:5]], ["H", "H", "H", "V", "H"])

    def test_settings_persist_when_reopened(self):
        _, _, music, settings = self.run_frames([
            [click(menu_buttons()["Settings"])],
            [click(settings_buttons()["Music"]),
             click(settings_buttons()["Sound Effects"]),
             click(settings_buttons()["Animations"])],
            [click(settings_buttons()["Back"])],
            [click(menu_buttons()["Versus"])],
            [pygame.event.Event(pygame.KEYDOWN, key=pygame.K_m, mod=0)],
            [click(menu_buttons()["Settings"])],
        ])
        music.assert_called_once_with(False)
        self.assertEqual(settings.call_args.args[2],
                         {"Music": False, "Sound Effects": False, "Animations": False})

    def test_successful_move_plays_sound(self):
        from settings import BOARD_X, BOARD_Y, CELL_SIZE
        from board import STEP
        def square(row, col):
            return pygame.Rect(BOARD_X + col * STEP, BOARD_Y + row * STEP,
                               CELL_SIZE, CELL_SIZE)
        _, sound, _, _ = self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(square(8, 4)), click(square(7, 4))],
        ])
        sound.assert_called_once_with({}, "move", True)

    def test_effect_toggle_suppresses_playback(self):
        from unittest.mock import Mock
        from audio import play_sound
        effect = Mock()
        play_sound({"move": effect}, "move", False)
        effect.play.assert_not_called()
        play_sound({"move": effect}, "move", True)
        effect.play.assert_called_once_with()

    def test_all_mode_entries_still_start(self):
        for label, mode in (("Versus", "Versus"),
                            ("Battle Royale", "Battle Royale"),
                            ("Blitz", "Blitz")):
            with self.subTest(label=label):
                states, _, _, _ = self.run_frames([[click(menu_buttons()[label])]])
                self.assertEqual(states[0][0], mode)

    def test_machine_difficulty_selection_and_restart(self):
        games = []
        def factory(mode):
            game = Game(mode)
            games.append(game)
            return game
        for difficulty in ("Casual", "Challenging"):
            games.clear()
            states, _, _, _ = self.run_frames([
                [click(menu_buttons()["Rise of the Machines"])],
                [click(difficulty_buttons()[difficulty])],
                [click(button_rects()["New game"])],
            ], factory)
            self.assertEqual(len(games), 2)
            self.assertTrue(all(g.mode == "Rise of the Machines" and
                                g.difficulty == difficulty for g in games))
            self.assertEqual(games[-1].current_player, 0)

    def test_computer_turn_ignores_board_input_and_remains_responsive(self):
        games = []
        def factory(mode):
            game = Game(mode, current_player=1)
            games.append(game)
            return game
        def pending_search(*args):
            while True:
                yield "move", (1, 4)
        with patch.object(main, "search", side_effect=pending_search):
            self.run_frames([
                [click(menu_buttons()["Rise of the Machines"])],
                [click(difficulty_buttons()["Challenging"])],
                [click(button_rects()["Wall"]),
                 click(pygame.Rect(0, 0, 930, 650), 3)],
                [click(button_rects()["Menu"])],
            ], factory)
        self.assertEqual(games[0].history, [])
        self.assertEqual(games[0].pawns[1], (0, 4))

    def test_machine_undo_returns_control_to_human(self):
        game = Game("Rise of the Machines")
        game.move((7, 4))
        game.move((1, 4))
        main.undo_turn(game)
        self.assertEqual(game.current_player, 0)
        self.assertEqual(game.pawns, [(8, 4), (0, 4)])

    def test_machine_victory_replay_preserves_difficulty(self):
        games = []
        def factory(mode):
            game = Game(mode)
            if not games:
                game.winner = 1
            games.append(game)
            return game
        self.run_frames([
            [click(menu_buttons()["Rise of the Machines"])],
            [click(difficulty_buttons()["Challenging"])],
            [click(victory_buttons()["Play Again"])],
        ], factory)
        self.assertEqual(len(games), 2)
        self.assertEqual(games[1].mode, "Rise of the Machines")
        self.assertEqual(games[1].difficulty, "Challenging")
        self.assertIsNone(games[1].winner)

    def test_difficulty_back_returns_to_menu(self):
        states, _, _, _ = self.run_frames([
            [click(menu_buttons()["Rise of the Machines"])],
            [click(difficulty_buttons()["Back to Main Menu"])],
            [click(menu_buttons()["Versus"])],
        ])
        self.assertEqual(states[0][0], "Versus")

    def test_computer_winning_move_uses_engine_and_audio(self):
        games = []
        def factory(mode):
            game = Game(mode, pawns=[(5, 0), (7, 4)], current_player=1)
            games.append(game)
            return game
        _, sound, _, _ = self.run_frames([
            [click(menu_buttons()["Rise of the Machines"])],
            [click(difficulty_buttons()["Challenging"])], [],
        ], factory)
        self.assertEqual(games[0].winner, 1)
        self.assertEqual(len(games[0].history), 1)
        self.assertEqual([call.args[1] for call in sound.call_args_list],
                         ["move", "victory"])

    def test_timeout_sound_once_and_victory_navigation(self):
        matches = []
        def factory(mode):
            game = Game(mode)
            if not matches:
                game.time_left[0] = 0
                game.walls_left[0] = 0
            matches.append(game)
            return game
        states, sound, _, _ = self.run_frames([
            [click(menu_buttons()["Blitz"])], [], [],
            [click(victory_buttons()["Play Again"])],
        ], factory)
        self.assertEqual(matches[0].winner, 1)
        self.assertIn("ran out of time", matches[0].message)
        self.assertEqual(matches[1].mode, "Blitz")
        self.assertIsNone(matches[1].winner)
        sound.assert_called_once_with({}, "victory", True)

    def test_victory_main_menu_and_exit(self):
        def factory(mode):
            game = Game(mode)
            game.winner = 0
            return game
        states, _, _, _ = self.run_frames([
            [click(menu_buttons()["Battle Royale"])],
            [click(victory_buttons()["Main Menu"])],
            [click(menu_buttons()["Exit Game"])],
        ], factory)
        self.assertEqual(len(states), 1)
        self.assertFalse(pygame.get_init())


if __name__ == "__main__":
    unittest.main()
