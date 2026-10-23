"""Start Gridlock with: python main.py"""

import pygame
from time import perf_counter
from board import (draw_board, draw_menu, draw_victory, load_stickers,
                   square_at, preview_wall, button_rects, menu_buttons,
                   draw_settings, settings_buttons, victory_buttons,
                   draw_difficulty, difficulty_buttons,
                   draw_battle_setup, battle_setup_buttons)
from ai.pathfinder import search
from audio import load_audio, set_music, play_sound
from game import Game, CONTROL_OPTIONS, DEFAULT_BR_CONTROLS
from rules import valid_moves, wall_error
from settings import WINDOW_WIDTH, WINDOW_HEIGHT, FPS


def undo_turn(game):
    game.undo()
    has_human = any(game.controller(i) == "Human" for i in range(game.player_count))
    while has_human and game.is_ai_turn and game.history:
        game.undo()


def restart_game(game):
    new_game = Game(game.mode)
    new_game.difficulty = game.difficulty
    new_game.controllers = game.controllers.copy()
    return new_game


def main():
    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Gridlock v2.5")
    fonts = (pygame.font.SysFont("georgia", 36, bold=True),
             pygame.font.SysFont("arial", 18),
             pygame.font.SysFont("arial", 15))
    stickers = load_stickers()
    sounds = load_audio()
    options = {"Music": True, "Sound Effects": True, "Animations": True}
    settings_open = False
    difficulty_open = False
    battle_setup_open = False
    battle_controllers = list(DEFAULT_BR_CONTROLS)
    ai_search = None
    ai_position = None
    ai_action = None
    ai_ready_at = 0.0
    victory_played = False
    clock = pygame.time.Clock()
    game = None
    direction = "H"
    selected = False
    running = True

    while running:
        elapsed = clock.tick(FPS) / 1000.0
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
                continue
            if not running:
                continue
            if game is None:
                if battle_setup_open:
                    if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                        battle_setup_open = False
                    elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                        for seat, rect in battle_setup_buttons().items():
                            if rect.collidepoint(event.pos):
                                if seat == "Back":
                                    battle_setup_open = False
                                elif seat == "Start Match":
                                    game = Game("Battle Royale")
                                    game.controllers = battle_controllers.copy()
                                    battle_setup_open = False
                                    selected = False
                                    victory_played = False
                                else:
                                    index = CONTROL_OPTIONS.index(battle_controllers[seat])
                                    battle_controllers[seat] = CONTROL_OPTIONS[(index + 1) % len(CONTROL_OPTIONS)]
                                break
                    continue
                if difficulty_open:
                    if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                        difficulty_open = False
                    elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                        for name, rect in difficulty_buttons().items():
                            if rect.collidepoint(event.pos):
                                difficulty_open = False
                                if name != "Back to Main Menu":
                                    game = Game("Rise of the Machines")
                                    game.difficulty = name
                                    selected = False
                                    victory_played = False
                                break
                    continue
                if settings_open:
                    if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                        settings_open = False
                    elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                        for name, rect in settings_buttons().items():
                            if rect.collidepoint(event.pos):
                                if name == "Back":
                                    settings_open = False
                                else:
                                    options[name] = not options[name]
                                    if name == "Music":
                                        set_music(options[name])
                                    elif name == "Sound Effects" and not options[name] and pygame.mixer.get_init():
                                        pygame.mixer.stop()
                                break
                    continue
                if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    for name, rect in menu_buttons().items():
                        if rect.collidepoint(event.pos):
                            if name == "Settings":
                                settings_open = True
                            elif name == "Exit Game":
                                running = False
                            elif name == "Rise of the Machines":
                                difficulty_open = True
                            elif name == "Battle Royale":
                                battle_setup_open = True
                            else:
                                game = Game(name)
                                selected = False
                                victory_played = False
                            break
                continue
            if game.winner is not None:
                choice = None
                if event.type == pygame.KEYDOWN:
                    choice = {pygame.K_n: "Play Again", pygame.K_m: "Main Menu"}.get(event.key)
                elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    choice = next((name for name, rect in victory_buttons().items()
                                   if rect.collidepoint(event.pos)), None)
                if choice:
                    if choice == "Play Again":
                        game = restart_game(game)
                    else:
                        game = None
                    selected = False
                    victory_played = False
                continue
            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 3:
                if not game.is_ai_turn:
                    direction = "V" if direction == "H" else "H"
                continue
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_m:
                    game = None
                    selected = False
                elif event.key == pygame.K_ESCAPE:
                    selected = False
                elif event.key == pygame.K_r and not game.is_ai_turn:
                    direction = "V" if direction == "H" else "H"
                elif event.key == pygame.K_z and event.mod & pygame.KMOD_CTRL:
                    undo_turn(game)
                    selected = False
            elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                pos = event.pos
                buttons = button_rects()
                if game.winner is not None:
                    continue
                if buttons["Menu"].collidepoint(pos):
                    game = None
                    selected = False
                elif buttons["New game"].collidepoint(pos):
                    game = restart_game(game)
                    selected = False
                    victory_played = False
                elif buttons["Undo"].collidepoint(pos):
                    undo_turn(game)
                    selected = False
                elif game.is_ai_turn:
                    continue
                else:
                    square = square_at(pos)
                    if square == game.pawns[game.current_player]:
                        selected = not selected
                    elif selected and square is not None:
                        if game.move(square):
                            selected = False
                            play_sound(sounds, "move", options["Sound Effects"])
                    elif not selected:
                        wall = preview_wall(game, selected, direction, pos)
                        if wall and wall_error(wall, game.walls, game.pawns,
                                               game.walls_left[game.current_player]) is None:
                            game.place_wall(wall)
        computer_turn = game is not None and game.is_ai_turn
        if computer_turn and running:
            position = (id(game), game.current_player, tuple(game.pawns), frozenset(game.walls),
                        tuple(game.walls_left), len(game.history))
            if position != ai_position:
                ai_position = position
                ai_search = search(game, game.ai_difficulty)
                ai_action = None
                ai_ready_at = perf_counter() + 3.0
            frame_deadline = perf_counter() + 0.004
            while ai_search is not None and perf_counter() < frame_deadline:
                try:
                    ai_action = next(ai_search)
                except StopIteration:
                    ai_search = None
                    break
            if ai_search is None and ai_action and perf_counter() >= ai_ready_at:
                kind, target = ai_action
                if kind == "move":
                    if game.move(target):
                        play_sound(sounds, "move", options["Sound Effects"])
                else:
                    game.place_wall(target)
                selected = False
                ai_position = None
        else:
            ai_search = ai_position = ai_action = None
        if game is None:
            if battle_setup_open:
                draw_battle_setup(screen, fonts, battle_controllers)
            elif difficulty_open:
                draw_difficulty(screen, fonts)
            elif settings_open:
                draw_settings(screen, fonts, options)
            else:
                draw_menu(screen, fonts)
        else:
            game.tick(elapsed)
            if game.winner is not None and not victory_played:
                play_sound(sounds, "victory", options["Sound Effects"])
                victory_played = True
            moves = (valid_moves(game.pawns, game.current_player, game.walls)
                     if selected and game.winner is None and not computer_turn else set())
            draw_board(screen, game, moves, selected, direction, pygame.mouse.get_pos(), fonts)
            draw_victory(screen, game, stickers, fonts)
        pygame.display.flip()
    pygame.quit()


if __name__ == "__main__":
    main()
