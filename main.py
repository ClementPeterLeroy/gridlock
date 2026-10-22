"""Start Gridlock with: python main.py"""

import pygame
from time import perf_counter
from board import (draw_board, draw_menu, draw_victory, load_stickers,
                   square_at, wall_at, button_rects, menu_buttons,
                   draw_settings, settings_buttons, victory_buttons,
                   draw_difficulty, difficulty_buttons)
from ai.pathfinder import search
from audio import load_audio, set_music, play_sound
from game import Game
from rules import valid_moves
from settings import WINDOW_WIDTH, WINDOW_HEIGHT, FPS


def undo_turn(game):
    game.undo()
    if game.mode == "Rise of the Machines" and game.current_player == 1:
        game.undo()


def main():
    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Gridlock v2.3")
    fonts = (pygame.font.SysFont("georgia", 36, bold=True),
             pygame.font.SysFont("arial", 18),
             pygame.font.SysFont("arial", 15))
    stickers = load_stickers()
    sounds = load_audio()
    options = {"Music": True, "Sound Effects": True, "Animations": True}
    settings_open = False
    difficulty_open = False
    ai_search = None
    ai_position = None
    ai_action = None
    victory_played = False
    clock = pygame.time.Clock()
    game = None
    action = "pawn"
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
                                    action, selected = "pawn", False
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
                            else:
                                game = Game(name)
                                action, selected = "pawn", False
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
                        mode, difficulty = game.mode, game.difficulty
                        game = Game(mode)
                        game.difficulty = difficulty
                    else:
                        game = None
                    action, selected = "pawn", False
                    victory_played = False
                continue
            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 3:
                if action == "wall" and not (game.mode == "Rise of the Machines" and game.current_player == 1):
                    direction = "V" if direction == "H" else "H"
                continue
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_m:
                    game = None
                    action, selected = "pawn", False
                elif event.key == pygame.K_ESCAPE:
                    action, selected = "pawn", False
                elif event.key == pygame.K_r and action == "wall":
                    direction = "V" if direction == "H" else "H"
                elif event.key == pygame.K_z and event.mod & pygame.KMOD_CTRL:
                    undo_turn(game)
                    action, selected = "pawn", False
            elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                pos = event.pos
                buttons = button_rects()
                if game.winner is not None:
                    continue
                if buttons["Menu"].collidepoint(pos):
                    game = None
                    action, selected = "pawn", False
                elif buttons["New game"].collidepoint(pos):
                    difficulty = game.difficulty
                    game = Game(game.mode)
                    game.difficulty = difficulty
                    action, selected = "pawn", False
                    victory_played = False
                elif buttons["Undo"].collidepoint(pos):
                    undo_turn(game)
                    action, selected = "pawn", False
                elif game.mode == "Rise of the Machines" and game.current_player == 1:
                    continue
                elif buttons["Wall"].collidepoint(pos):
                    action = "pawn" if action == "wall" else "wall"
                    selected = False
                elif action == "wall":
                    wall = wall_at(pos, direction)
                    if wall and game.place_wall(wall):
                        action = "pawn"
                else:
                    square = square_at(pos)
                    if square == game.pawns[game.current_player]:
                        selected = not selected
                    elif selected and square is not None:
                        if game.move(square):
                            selected = False
                            play_sound(sounds, "move", options["Sound Effects"])
                    else:
                        selected = False
        computer_turn = (game is not None and game.mode == "Rise of the Machines"
                         and game.current_player == 1 and game.winner is None)
        if computer_turn and running:
            position = (id(game), tuple(game.pawns), frozenset(game.walls),
                        tuple(game.walls_left), len(game.history))
            if position != ai_position:
                ai_position = position
                ai_search = search(game, game.difficulty)
                ai_action = None
            frame_deadline = perf_counter() + 0.004
            while perf_counter() < frame_deadline:
                try:
                    ai_action = next(ai_search)
                except StopIteration:
                    if ai_action:
                        kind, target = ai_action
                        if kind == "move":
                            if game.move(target):
                                play_sound(sounds, "move", options["Sound Effects"])
                        else:
                            game.place_wall(target)
                    action, selected = "pawn", False
                    ai_position = None
                    break
        else:
            ai_search = ai_position = ai_action = None
        if game is None:
            if difficulty_open:
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
                     if selected and action == "pawn" and game.winner is None else set())
            draw_board(screen, game, moves, action, direction, pygame.mouse.get_pos(), fonts)
            draw_victory(screen, game, stickers, fonts)
        pygame.display.flip()
    pygame.quit()


if __name__ == "__main__":
    main()
