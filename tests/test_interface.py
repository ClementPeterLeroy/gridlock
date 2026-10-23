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
                   difficulty_buttons, battle_setup_buttons, STEP)
from game import Game
from settings import BOARD_X, BOARD_Y, CELL_SIZE, GAP


def click(rect, button=1):
    return pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=rect.center, button=button)


def square(row, col):
    return pygame.Rect(BOARD_X + col * STEP, BOARD_Y + row * STEP,
                       CELL_SIZE, CELL_SIZE)


def groove(row=3, col=3):
    return pygame.Rect(BOARD_X + (col + 1) * STEP - GAP,
                       BOARD_Y + (row + 1) * STEP - GAP, GAP, GAP)


def start_mode(mode):
    events = [click(menu_buttons()[mode])]
    if mode == "Battle Royale":
        events.append(click(battle_setup_buttons()["Start Match"]))
    return events


class InterfaceTests(unittest.TestCase):
    def run_frames(self, frames, factory=Game, frame_seconds=0.016):
        states = []
        self.observed = []
        self.setup_observed = []
        draw_setup = main.draw_battle_setup
        def capture_setup(screen, fonts, controllers):
            self.setup_observed.append(controllers.copy())
            draw_setup(screen, fonts, controllers)
        def capture(*args):
            states.append((args[1].mode, args[3], args[4], args[1].winner))
            self.observed.append({"selected": args[3], "moves": set(args[2]),
                                  "snapshot": args[1].snapshot(), "direction": args[4],
                                  "history_len": len(args[1].history)})
        frames = iter(frames + [[pygame.event.Event(pygame.QUIT)]])
        now = 0.0
        def next_frame():
            nonlocal now
            now += frame_seconds
            return next(frames)
        def timer():
            nonlocal now
            now += 0.00005
            return now
        with patch.object(main.pygame.event, "get", side_effect=next_frame), \
             patch.object(main, "perf_counter", side_effect=timer), \
             patch.object(main.pygame.time, "Clock", return_value=SimpleNamespace(tick=lambda fps: 16)), \
             patch.object(main, "Game", side_effect=factory), \
             patch.object(main, "load_audio", return_value={}), \
             patch.object(main, "play_sound") as sound, \
             patch.object(main, "set_music") as music, \
             patch.object(main, "draw_board", side_effect=capture), \
             patch.object(main, "draw_battle_setup", side_effect=capture_setup), \
             patch.object(main, "draw_settings", wraps=main.draw_settings) as settings:
            main.main()
        return states, sound, music, settings

    def test_rotation_without_manual_wall_mode(self):
        states, _, _, _ = self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(pygame.Rect(0, 0, 1, 1), 3)],
            [click(pygame.Rect(0, 0, 1, 1), 3)],
            [pygame.event.Event(pygame.KEYDOWN, key=pygame.K_r, mod=0)],
        ])
        self.assertEqual([s[2] for s in states[:4]], ["H", "V", "H", "V"])
        self.assertNotIn("Wall", button_rects())

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
        _, sound, _, _ = self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(square(8, 4)), click(square(7, 4))],
        ])
        sound.assert_called_once_with({}, "move", True)

    def test_direct_wall_placement_in_all_modes(self):
        for mode in ("Versus", "Blitz", "Battle Royale", "Rise of the Machines"):
            games = []
            def factory(name):
                game = Game(name)
                games.append(game)
                return game
            frames = [start_mode(mode)]
            if mode == "Rise of the Machines":
                frames.append([click(difficulty_buttons()["Casual"])])
            frames.append([click(groove())])
            def pending(*args):
                while True:
                    yield "move", (1, 4)
            with self.subTest(mode=mode), patch.object(main, "search", side_effect=pending):
                self.run_frames(frames, factory)
                self.assertEqual(games[0].walls, {(3, 3, "H")})
                self.assertEqual(games[0].walls_left[0], 4 if mode == "Battle Royale" else 9)
                self.assertEqual(games[0].current_player, 2 if mode == "Battle Royale" else 1)

    def test_selected_pawn_blocks_walls_and_keeps_selection_on_illegal_click(self):
        self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(square(8, 4))],
            [click(groove())],
            [click(square(4, 4))],
            [click(square(7, 4))],
        ])
        for frame in self.observed[1:4]:
            self.assertTrue(frame["selected"])
            self.assertEqual(frame["moves"], {(7, 4), (8, 3), (8, 5)})
            self.assertEqual(frame["snapshot"][1], set())
            self.assertEqual(frame["snapshot"][0][0], (8, 4))
        self.assertFalse(self.observed[4]["selected"])
        self.assertEqual(self.observed[4]["moves"], set())
        self.assertEqual(self.observed[4]["snapshot"][0][0], (7, 4))

    def test_deselection_restores_direct_placement(self):
        self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(square(8, 4))],
            [click(square(8, 4))],
            [click(groove())],
        ])
        self.assertTrue(self.observed[1]["selected"])
        self.assertFalse(self.observed[2]["selected"])
        self.assertEqual(self.observed[2]["moves"], set())
        self.assertEqual(self.observed[3]["snapshot"][1], {(3, 3, "H")})

    def test_invalid_wall_and_empty_square_do_not_change_state(self):
        game = Game(walls={(3, 3, "H")})
        before = game.snapshot()
        self.run_frames([
            [click(menu_buttons()["Versus"])],
            [click(groove()), click(square(4, 4))],
            [click(groove(), 3), click(groove())],
        ], lambda mode: game)
        self.assertEqual(game.snapshot()[:5], before[:5])
        self.assertEqual(game.history, [])

    def test_zero_walls_and_finished_match_ignore_placement(self):
        for finished in (False, True):
            game = Game(walls_left=[0, 10])
            if finished:
                game.winner = 0
                game.walls_left[0] = 10
            before = game.snapshot()
            self.run_frames([
                [click(menu_buttons()["Versus"])],
                [click(groove()), click(square(8, 4))],
            ], lambda mode: game)
            self.assertEqual(game.snapshot()[:5], before[:5])
            self.assertEqual(game.history, [])

    def test_battle_royale_only_current_pawn_can_be_selected(self):
        game = Game("Battle Royale", current_player=2)
        self.run_frames([
            [click(menu_buttons()["Battle Royale"]),
             *[click(battle_setup_buttons()[i]) for i in (1, 1, 2, 2, 3, 3)],
             click(battle_setup_buttons()["Start Match"])],
            [click(square(8, 4)), click(square(0, 4)), click(square(4, 8))],
            [click(square(4, 0))],
        ], lambda mode: game)
        self.assertFalse(self.observed[1]["selected"])
        self.assertTrue(self.observed[2]["selected"])
        self.assertEqual(self.observed[2]["moves"], {(3, 0), (5, 0), (4, 1)})

    def test_wall_orientation_persists_and_undo_restores_wall(self):
        self.run_frames([
            [click(menu_buttons()["Versus"])],
            [pygame.event.Event(pygame.KEYDOWN, key=pygame.K_r, mod=0), click(groove())],
            [click(button_rects()["Undo"])],
        ])
        self.assertEqual(self.observed[1]["snapshot"][1], {(3, 3, "V")})
        self.assertEqual(self.observed[2]["direction"], "V")
        self.assertEqual(self.observed[2]["snapshot"][1], set())
        self.assertEqual(self.observed[2]["snapshot"][2], [10, 10])

    def test_battle_setup_defaults_and_back(self):
        states, _, _, _ = self.run_frames([
            [click(menu_buttons()["Battle Royale"])],
            [click(battle_setup_buttons()["Back"])],
        ])
        self.assertEqual(states, [])
        self.assertEqual(self.setup_observed[0], ["Human"] + ["AI - Casual"] * 3)

    def test_battle_setup_cycles_and_replay_preserves_configuration(self):
        games = []
        def factory(mode):
            game = Game(mode)
            if not games:
                game.winner = 2
            games.append(game)
            return game
        self.run_frames([
            [click(menu_buttons()["Battle Royale"])],
            [click(battle_setup_buttons()[0]), click(battle_setup_buttons()[0]),
             click(battle_setup_buttons()[1]), click(battle_setup_buttons()[2]),
             click(battle_setup_buttons()[2]), click(battle_setup_buttons()["Start Match"])],
            [click(victory_buttons()["Play Again"])],
            [click(button_rects()["New game"])],
        ], factory)
        expected = ["AI - Challenging", "AI - Challenging", "Human", "AI - Casual"]
        self.assertEqual(len(games), 3)
        self.assertTrue(all(g.controllers == expected for g in games))
        self.assertIsNot(games[0].controllers, games[1].controllers)
        self.assertIsNone(games[1].winner)

    def test_all_human_battle_match_smart_controls(self):
        self.run_frames([
            [click(menu_buttons()["Battle Royale"]),
             *[click(battle_setup_buttons()[i]) for i in (1, 1, 2, 2, 3, 3)],
             click(battle_setup_buttons()["Start Match"])],
            [click(square(8, 4)), click(square(7, 4))],
            [click(square(4, 0))],
        ])
        self.assertEqual(self.observed[1]["snapshot"][3], 2)
        self.assertTrue(self.observed[2]["selected"])
        self.assertEqual(self.observed[2]["moves"], {(3, 0), (5, 0), (4, 1)})

    def test_ai_waits_three_seconds_without_blocking(self):
        games = []
        def factory(mode):
            game = Game(mode, current_player=1, walls_left=[0, 0])
            games.append(game)
            return game
        self.run_frames([
            [click(menu_buttons()["Rise of the Machines"])],
            [click(difficulty_buttons()["Casual"])],
            [], [], [], [], [], [], [],
        ], factory, frame_seconds=0.5)
        self.assertTrue(all(f["history_len"] == 0 for f in self.observed[:6]))
        self.assertEqual(games[0].current_player, 0)
        self.assertEqual(len(games[0].history), 1)

    def test_all_ai_battle_advances_automatically_in_clockwise_order(self):
        games = []
        def factory(mode):
            game = Game(mode, walls_left=[0] * 4)
            games.append(game)
            return game
        self.run_frames([
            [click(menu_buttons()["Battle Royale"]),
             click(battle_setup_buttons()[0]), click(battle_setup_buttons()["Start Match"])],
            *[[] for _ in range(19)],
        ], factory, frame_seconds=1.0)
        changes = {}
        for frame in self.observed:
            changes.setdefault(frame["history_len"], frame["snapshot"][3])
        self.assertGreaterEqual(len(games[0].history), 4)
        self.assertEqual([changes[i] for i in range(5)], [0, 2, 1, 3, 0])

    def test_menu_cancels_pending_ai_action(self):
        games = []
        def factory(mode):
            game = Game(mode, current_player=1, walls_left=[0, 0])
            games.append(game)
            return game
        self.run_frames([
            [click(menu_buttons()["Rise of the Machines"])],
            [click(difficulty_buttons()["Casual"])],
            [click(button_rects()["Menu"])], [], [], [], [],
        ], factory, frame_seconds=1.0)
        self.assertEqual(games[0].history, [])

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
                states, _, _, _ = self.run_frames([start_mode(label)])
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
                [click(groove()), click(square(0, 4)),
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
            [click(difficulty_buttons()["Challenging"])], [], [], [], [],
        ], factory, frame_seconds=1.0)
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
            start_mode("Battle Royale"),
            [click(victory_buttons()["Main Menu"])],
            [click(menu_buttons()["Exit Game"])],
        ], factory)
        self.assertEqual(len(states), 1)
        self.assertFalse(pygame.get_init())


if __name__ == "__main__":
    unittest.main()
