"""Headless event-loop tests for setup, smart controls, pause, and AI pacing."""

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
import main
from board import (menu_buttons, setup_buttons, settings_buttons, pause_buttons,
                   button_rects, victory_buttons, STEP)
from game import Game
from preferences import DEFAULT_SETTINGS
from display import GameDisplay
from settings import BOARD_X, BOARD_Y, CELL_SIZE, GAP


def click(rect, button=1):
    return pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=rect.center, button=button)


def key(value):
    return pygame.event.Event(pygame.KEYDOWN, key=value, mod=0)


def square(row, col):
    return pygame.Rect(BOARD_X + col * STEP, BOARD_Y + row * STEP, CELL_SIZE, CELL_SIZE)


def groove(row=3, col=3):
    return pygame.Rect(BOARD_X + (col + 1) * STEP - GAP,
                       BOARD_Y + (row + 1) * STEP - GAP, GAP, GAP)


def start(mode):
    return [click(menu_buttons()[mode]), click(setup_buttons(mode)['Start Match'])]


class InterfaceTests(unittest.TestCase):
    def run_frames(self, frames, factory=Game, seconds=0.016, preferences=None):
        self.observed, self.games, self.setups = [], [], []
        self.saved_preferences = []
        now = 0.0
        frames = iter(frames + [[pygame.event.Event(pygame.QUIT)]])
        def next_frame():
            nonlocal now
            now += seconds
            return next(frames)
        def timer():
            nonlocal now
            now += 0.0001
            return now
        def make_game(mode):
            game = factory(mode)
            self.games.append(game)
            return game
        draw_setup, draw_board = main.draw_setup, main.draw_board
        def setup(*args):
            from copy import deepcopy
            self.setups.append(deepcopy(args[2]))
            draw_setup(*args)
        def board(*args):
            g = args[1]
            self.observed.append({'selected': args[3], 'direction': args[4],
                                  'moves': set(args[2]), 'state': g.snapshot(),
                                  'paused': g.paused, 'history': len(g.history)})
            draw_board(*args)
        with patch.object(main.pygame.event, 'get', side_effect=next_frame), \
             patch.object(main.pygame.time, 'Clock', return_value=SimpleNamespace(tick=lambda fps: seconds * 1000)), \
             patch.object(main, 'perf_counter', side_effect=timer), \
             patch.object(main, 'Game', side_effect=make_game), \
             patch.object(main, 'load_audio', return_value={}) as audio, \
             patch.object(main, 'load_settings', return_value=(preferences or DEFAULT_SETTINGS).copy()), \
             patch.object(main, 'save_settings', side_effect=lambda options: self.saved_preferences.append(options.copy())), \
             patch.object(main, 'play_startup', return_value=True) as startup, \
             patch.object(main, 'play_sound') as sound, \
             patch.object(main, 'set_music') as music, \
             patch.object(main, 'draw_setup', side_effect=setup), \
             patch.object(main, 'draw_board', side_effect=board):
            main.main()
        self.startup_calls = startup.call_count
        self.audio_options = audio.call_args.kwargs
        return sound, music

    def test_all_modes_open_setup_before_starting(self):
        for mode in ('Versus', 'Blitz', 'Battle Royale', 'Rise of the Machines'):
            self.run_frames([[click(menu_buttons()[mode])]])
            self.assertEqual(self.games, [])
            self.assertEqual(self.setups[0].mode, mode)
            self.run_frames([start(mode)])
            self.assertEqual(self.games[0].mode, mode)

    def test_custom_name_input_and_limit(self):
        b = setup_buttons('Versus')
        self.run_frames([
            [click(menu_buttons()['Versus']), click(b[('name', 0)])],
            [pygame.event.Event(pygame.TEXTINPUT, text='Alexabcdefghijk')],
            [key(pygame.K_BACKSPACE), key(pygame.K_RETURN), click(b['Start Match'])],
        ])
        self.assertEqual(self.games[0].display_name(0), 'Alexabcdefg')
        self.assertEqual(self.games[0].display_name(1), 'Crimson')

    def test_timer_selection_for_each_mode(self):
        for mode, expected in (('Versus', 15), ('Battle Royale', 15), ('Blitz', 5)):
            b = setup_buttons(mode)
            self.run_frames([[click(menu_buttons()[mode]), click(b['Timer']), click(b['Start Match'])]])
            game = self.games[0]
            self.assertEqual(game.config.blitz_minutes if mode == 'Blitz' else game.config.turn_limit, expected)
        self.assertNotIn('Timer', setup_buttons('Rise of the Machines'))

    def test_random_intro_is_skippable_and_ai_can_start(self):
        b = setup_buttons('Rise of the Machines')
        with patch.object(main.random, 'choice', return_value=1):
            sound, _ = self.run_frames([
                [click(menu_buttons()['Rise of the Machines']), click(b['Random Start']), click(b['Start Match'])],
                [key(pygame.K_SPACE)], [], [], [], [],
            ], seconds=1.0)
        self.assertEqual(len(self.games[0].history), 1)
        self.assertEqual(self.games[0].current_player, 0)
        self.assertIn('move', [c.args[1] for c in sound.call_args_list])

    def test_animations_toggle_skips_random_intro(self):
        b = setup_buttons('Versus')
        with patch.object(main.random, 'choice', return_value=1), patch.object(main, 'draw_starting_player') as intro:
            self.run_frames([
                [click(menu_buttons()['Settings']), click(settings_buttons()['Animations']), click(settings_buttons()['Back'])],
                [click(menu_buttons()['Versus']), click(b['Random Start']), click(b['Start Match'])],
            ])
        intro.assert_not_called()
        self.assertEqual(self.games[0].current_player, 1)

    def test_smart_selection_illegal_click_and_deselection(self):
        self.run_frames([start('Versus'), [click(square(8, 4))],
                         [click(groove()), click(square(4, 4))], [click(square(8, 4))], [click(groove())]])
        self.assertTrue(self.observed[1]['selected'])
        self.assertTrue(self.observed[2]['selected'])
        self.assertEqual(self.observed[2]['moves'], {(7, 4), (8, 3), (8, 5)})
        self.assertFalse(self.observed[3]['selected'])
        self.assertEqual(self.games[0].walls, {(3, 3, 'H')})

    def test_legal_move_sound_and_selection_reset(self):
        sound, _ = self.run_frames([start('Versus'), [click(square(8, 4)), click(square(7, 4))]])
        self.assertEqual(self.games[0].pawns[0], (7, 4))
        self.assertFalse(self.observed[-1]['selected'])
        sound.assert_called_once_with({}, 'move', True)

    def test_direct_wall_all_modes(self):
        for mode in ('Versus', 'Blitz', 'Battle Royale', 'Rise of the Machines'):
            self.run_frames([start(mode), [click(groove())]])
            self.assertEqual(self.games[0].walls, {(3, 3, 'H')})
            self.assertEqual(self.games[0].current_player, 2 if mode == 'Battle Royale' else 1)

    def test_rotation_and_invalid_placement(self):
        self.run_frames([start('Versus'), [click(groove(), 3), click(groove())],
                         [key(pygame.K_r), click(groove())]])
        self.assertEqual(self.games[0].walls, {(3, 3, 'V')})
        self.assertEqual(len(self.games[0].history), 1)
        self.assertEqual(self.observed[-1]['direction'], 'H')
        self.assertNotIn('Wall', button_rects())

    def test_zero_walls_ignore_click(self):
        self.run_frames([start('Versus'), [click(groove())]], lambda m: Game(m, walls_left=[0, 0]))
        self.assertEqual(self.games[0].walls, set())

    def test_pause_freezes_timers_and_input_then_resumes(self):
        self.run_frames([start('Versus'), [], [key(pygame.K_ESCAPE)],
                         [click(square(8, 4)), click(groove())], [],
                         [click(pause_buttons()['Resume Game'])], []], seconds=1.0)
        paused = [f for f in self.observed if f['paused']]
        self.assertTrue(paused)
        self.assertTrue(all(f['state'] == paused[0]['state'] for f in paused))
        self.assertEqual(self.games[0].walls, set())
        self.assertEqual(self.games[0].turn_elapsed, 3)

    def test_pause_settings_returns_to_pause_and_applies_music(self):
        _, music = self.run_frames([start('Versus'), [click(button_rects()['Pause'])],
                                   [click(pause_buttons()['Settings'])],
                                   [click(settings_buttons()['Music']), click(settings_buttons()['Back'])],
                                   [key(pygame.K_ESCAPE)]])
        music.assert_called_once_with(False)
        self.assertFalse(self.games[0].paused)

    def test_pause_restart_preserves_configuration(self):
        b = setup_buttons('Versus')
        self.run_frames([[click(menu_buttons()['Versus']), click(b['Timer']), click(b[('name', 0)])],
                         [pygame.event.Event(pygame.TEXTINPUT, text='Pat'), click(b['Start Match'])],
                         [key(pygame.K_ESCAPE)], [click(pause_buttons()['Restart Match'])]])
        self.assertEqual(len(self.games), 2)
        self.assertEqual(self.games[1].config.turn_limit, 15)
        self.assertEqual(self.games[1].display_name(0), 'Pat')
        self.assertFalse(self.games[1].paused)

    def test_pause_suspends_ai_delay_and_ai_clock_is_free(self):
        self.run_frames([start('Rise of the Machines'), [click(square(8, 4)), click(square(7, 4))],
                         [], [key(pygame.K_ESCAPE)], [], [], [], [],
                         [key(pygame.K_ESCAPE)], [], [], []], seconds=0.25)
        paused = [f for f in self.observed if f['paused']]
        self.assertTrue(all(f['history'] == 1 for f in paused))
        self.assertEqual(len(self.games[0].history), 2)
        # Search and presentation did not charge the computer's next human turn.
        self.assertEqual(self.games[0].time_left, [180.0, 180.0])

    def test_menu_cancels_pending_ai(self):
        self.run_frames([start('Rise of the Machines'), [click(square(8, 4)), click(square(7, 4))],
                         [key(pygame.K_ESCAPE)], [click(pause_buttons()['Main Menu'])], [], [], []], seconds=1.0)
        self.assertEqual(len(self.games[0].history), 1)

    def test_pause_suspends_search_budget_as_well_as_presentation(self):
        times = []
        def pending(game, difficulty, **kwargs):
            while True:
                times.append(kwargs['clock']())
                yield 'move', (1, 4)
        with patch.object(main, 'search', side_effect=pending):
            self.run_frames([start('Rise of the Machines'),
                             [click(square(8, 4)), click(square(7, 4))], [],
                             [key(pygame.K_ESCAPE)], *[[] for _ in range(10)],
                             [key(pygame.K_ESCAPE)], [], [key(pygame.K_m)]], seconds=1.0)
        self.assertTrue(times)
        self.assertLessEqual(max(times), 2)
        self.assertEqual(len(self.games[0].history), 1)

    def test_long_ai_search_fits_turn_limit_with_free_presentation(self):
        budgets = []
        def slow(game, difficulty, **kwargs):
            budgets.append(kwargs['time_limit'])
            until = kwargs['clock']() + kwargs['time_limit']
            from rules import valid_moves
            move = sorted(valid_moves(game.pawns, game.current_player, game.walls))[0]
            while kwargs['clock']() < until:
                yield 'move', move
        b = setup_buttons('Battle Royale')
        with patch.object(main, 'search', side_effect=slow):
            self.run_frames([[click(menu_buttons()['Battle Royale']), click(b[('control', 0)]),
                              click(b['Timer']), click(b['Start Match'])],
                             *[[] for _ in range(10)]], seconds=1.0)
        self.assertEqual(budgets[0], 10)
        self.assertEqual(len(self.games[0].history), 1)
        self.assertEqual(self.games[0].history[0][5], 10)
        self.assertEqual(self.games[0].history[0][10], 9)
        self.assertEqual(self.games[0].eliminated, set())

    def test_one_second_ai_pacing_and_live_elapsed_timer_in_both_modes(self):
        for mode in ('Rise of the Machines', 'Battle Royale'):
            events = start(mode)
            if mode == 'Battle Royale':
                b = setup_buttons(mode)
                events = [click(menu_buttons()[mode]), click(b[('control', 0)]), click(b['Start Match'])]
            factory = (lambda m: Game(m, current_player=1)) if mode == 'Rise of the Machines' else Game
            self.run_frames([events, [], [], [], []], factory, seconds=0.25)
            self.assertEqual([f['history'] for f in self.observed[:4]], [0, 0, 0, 0])
            self.assertEqual([f['state'][5] for f in self.observed[:4]], [0, 0.25, 0.5, 0.75])
            self.assertEqual(self.observed[4]['history'], 1)
            self.assertEqual(self.games[0].history[0][5], 1)
            self.assertEqual(self.games[0].history[0][10], 0)
            self.assertEqual(self.games[0].turn_elapsed, 0)

    def test_ai_countdown_appears_and_updates_without_charging_presentation(self):
        def pending(game, difficulty, **kwargs):
            while True:
                yield 'move', (7, 4)
        b = setup_buttons('Battle Royale')
        with patch.object(main, 'search', side_effect=pending):
            self.run_frames([[click(menu_buttons()['Battle Royale']), click(b[('control', 0)]),
                              click(b['Timer']), click(b['Start Match'])],
                             [], [], [], [], [], []], seconds=0.5)
        self.assertEqual([f['state'][5] for f in self.observed[:4]], [0, 0.5, 1, 1.5])
        self.assertEqual([f['state'][10] for f in self.observed[:4]], [0, 0, 0, 0.5])
        self.assertEqual(self.games[0].remaining_turn_time, 13)

    def test_expired_ai_countdown_forfeits_before_a_pending_action(self):
        b = setup_buttons('Battle Royale')
        def expired(mode):
            return Game(mode, turn_clock_elapsed=15)
        self.run_frames([[click(menu_buttons()['Battle Royale']), click(b[('control', 0)]),
                          click(b['Timer']), click(b['Start Match'])]], expired)
        self.assertEqual(self.games[0].eliminated, {0})
        self.assertIsNone(self.games[0].pawns[0])
        self.assertEqual(self.games[0].current_player, 2)
        self.assertEqual(self.games[0].walls, set())

    def test_battle_all_human_current_pawn_only(self):
        b = setup_buttons('Battle Royale')
        self.run_frames([[click(menu_buttons()['Battle Royale']),
                          *[click(b[('control', i)]) for i in (1, 1, 2, 2, 3, 3)], click(b['Start Match'])],
                         [click(square(4, 0))], [click(square(8, 4)), click(square(7, 4))],
                         [click(square(4, 0))]])
        self.assertFalse(self.observed[1]['selected'])
        self.assertTrue(self.observed[-1]['selected'])

    def test_battle_all_ai_advances_and_ignores_board(self):
        b = setup_buttons('Battle Royale')
        self.run_frames([[click(menu_buttons()['Battle Royale']), click(b[('control', 0)]), click(b['Start Match'])],
                         [click(groove()), click(square(8, 4))], *[[] for _ in range(17)]], seconds=1.0)
        self.assertGreaterEqual(len(self.games[0].history), 4)
        self.assertFalse(any(f['selected'] for f in self.observed))

    def test_replay_preserves_battle_controls(self):
        def factory(mode):
            game = Game(mode)
            if not self.games:
                game.winner = 2
            return game
        b = setup_buttons('Battle Royale')
        self.run_frames([[click(menu_buttons()['Battle Royale']), click(b[('control', 2)]), click(b['Start Match'])],
                         [click(victory_buttons()['Play Again'])]], factory)
        self.assertEqual(self.games[1].controllers[2], 'AI - Challenging')
        self.assertEqual(self.games[0].config, self.games[1].config)

    def test_ai_victory_move_and_sound_once(self):
        def factory(mode):
            return Game(mode, pawns=[(5, 0), (7, 4)], current_player=1)
        sound, _ = self.run_frames([start('Rise of the Machines'), [], [], [], [], [], []], factory, seconds=1.0)
        self.assertEqual(self.games[0].winner, 1)
        self.assertEqual([c.args[1] for c in sound.call_args_list], ['move', 'victory'])

    def test_undo_restores_walls_and_human_turn(self):
        self.run_frames([start('Versus'), [click(groove())], [click(button_rects()['Undo'])]])
        self.assertEqual(self.games[0].walls, set())
        self.assertEqual(self.games[0].walls_left, [10, 10])
        game = Game('Rise of the Machines')
        game.move((7, 4))
        game.move((1, 4))
        main.undo_turn(game)
        self.assertEqual(game.current_player, 0)
        self.assertEqual(game.pawns, [(8, 4), (0, 4)])

    def test_exit_closes_cleanly(self):
        self.run_frames([[click(menu_buttons()['Exit Game'])]])
        self.assertFalse(pygame.get_init())

    def test_returning_to_menu_does_not_repeat_startup(self):
        self.run_frames([start('Versus'), [key(pygame.K_m)],
                         start('Blitz'), [key(pygame.K_m)]])
        self.assertEqual(self.startup_calls, 1)

    def test_saved_preferences_load_and_toggles_save_immediately(self):
        self.run_frames([[click(menu_buttons()['Settings']), click(settings_buttons()['Music']),
                          click(settings_buttons()['Sound Effects']), click(settings_buttons()['Animations'])]])
        self.assertEqual(len(self.saved_preferences), 3)
        saved = self.saved_preferences[-1]
        self.assertEqual(saved, {name: False for name in DEFAULT_SETTINGS})
        self.run_frames([[click(menu_buttons()['Settings']), click(settings_buttons()['Music'])]], preferences=saved)
        self.assertEqual(self.audio_options, {'music_enabled': False})
        self.assertEqual(self.saved_preferences[-1], {'Music': True, 'Sound Effects': False, 'Animations': False})

    def test_fullscreen_menu_clicks_and_smart_mouse_controls(self):
        displays = []
        def create_display():
            display = GameDisplay()
            displays.append(display)
            return display
        # SDL's dummy desktop is 1024 x 768: the 930 x 650 canvas is centered.
        def physical(rect):
            return click(rect.move(47, 59))
        with patch.object(main, 'GameDisplay', side_effect=create_display):
            self.run_frames([
                [click(menu_buttons()['Settings'])],
                [click(settings_buttons()['Display Mode'])],
                [physical(settings_buttons()['Back'])],
                [physical(menu_buttons()['Versus'])],
                [physical(setup_buttons('Versus')['Start Match'])],
                [physical(square(8, 4)), physical(square(7, 4))],
                [physical(groove())],
            ])
        self.assertTrue(displays[0].fullscreen)
        self.assertEqual(self.games[0].pawns[0], (7, 4))
        self.assertEqual(self.games[0].walls, {(3, 3, 'H')})
        self.assertEqual(self.saved_preferences, [])

    def test_pause_settings_repeated_switch_keeps_match_and_ai_state(self):
        def physical(rect):
            return click(rect.move(47, 59))
        def pending(game, difficulty, **kwargs):
            while True:
                yield 'move', (1, 4)
        with patch.object(main, 'search', side_effect=pending) as search:
            self.run_frames([
                start('Rise of the Machines'),
                [click(square(8, 4)), click(square(7, 4))],
                [click(button_rects()['Pause'])],
                [click(pause_buttons()['Settings'])],
                [click(settings_buttons()['Display Mode'])],
                [physical(settings_buttons()['Display Mode'])],
                [click(settings_buttons()['Back'])],
                [click(pause_buttons()['Resume Game'])], [],
            ], seconds=0.25)
        self.assertEqual(len(self.games), 1)
        self.assertEqual(len(self.games[0].history), 1)
        self.assertEqual(search.call_count, 1)
        paused = [frame['state'] for frame in self.observed if frame['paused']]
        self.assertTrue(all(state == paused[0] for state in paused))
        self.assertEqual(self.saved_preferences, [])


if __name__ == '__main__':
    unittest.main()
