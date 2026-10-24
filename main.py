"""Start Gridlock with: python main.py"""

from copy import deepcopy
import random
from time import perf_counter
import pygame

from board import (draw_board, draw_menu, draw_victory,
                   square_at, preview_wall, button_rects, menu_buttons,
                   draw_settings, settings_buttons, setup_buttons, draw_setup,
                   pause_buttons, draw_pause, draw_starting_player, victory_buttons)
from ai.pathfinder import search
from audio import load_audio, set_music, play_sound
from identity import IdentityAssets
from startup import play_startup
from game import Game
from match_config import MatchConfig, CONTROL_OPTIONS, NAME_LIMIT
from rules import valid_moves, wall_error
from settings import WINDOW_WIDTH, WINDOW_HEIGHT, FPS


def create_game(config):
    game = Game(config.mode)
    game.config = deepcopy(config)
    game.controllers = config.controllers.copy()
    if config.mode == "Rise of the Machines":
        game.difficulty = config.controllers[1].removeprefix("AI - ")
    game.time_left = [60.0 * config.blitz_minutes] * game.player_count
    if config.random_start:
        game.current_player = random.choice(game.active_players)
    game.message = f"{game.player_label(game.current_player)} starts."
    return game


def restart_game(game):
    config = deepcopy(game.config)
    config.controllers = game.controllers.copy()
    if game.mode == "Rise of the Machines" and not config.controllers:
        config.controllers = ["Human", f"AI - {game.difficulty}"]
    return create_game(config)


def undo_turn(game):
    game.undo()
    has_human = any(game.controller(i) == "Human" for i in game.active_players)
    while has_human and game.is_ai_turn and game.history:
        game.undo()


def position_key(game):
    return (id(game), game.current_player, tuple(game.pawns), frozenset(game.walls),
            tuple(game.walls_left), len(game.history))


def main():
    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Gridlock v2.7")
    assets = IdentityAssets()
    if assets.icon is not None:
        pygame.display.set_icon(assets.icon)
    fonts = assets.fonts
    clock = pygame.time.Clock()
    if not play_startup(screen, clock):
        pygame.quit()
        return
    stickers = {}
    sounds = load_audio()
    options = {"Music": True, "Sound Effects": True, "Animations": True}
    presets = {}
    config = None
    editing = None
    view = "menu"
    game = None
    selected = False
    direction = "H"
    ai_state = None
    active_time = 0.0
    intro_elapsed = 0.0
    turn_age = 0.0
    turn_key = None
    victory_played = False
    running = True

    def launch(new_game):
        nonlocal game, view, ai_state, selected, intro_elapsed, victory_played, turn_key, turn_age, stickers
        game = new_game
        stickers = assets.stickers_for(game)
        game.paused = False
        view = "intro" if game.config.random_start and options["Animations"] else "game"
        ai_state, selected = None, False
        intro_elapsed, turn_age = 0.0, 0.0
        turn_key, victory_played = None, False

    while running:
        elapsed = clock.tick(FPS) / 1000.0
        previous_view, previous_game = view, game
        previous_turn = position_key(game) if game else None
        events = pygame.event.get()
        if any(event.type == pygame.QUIT for event in events):
            break
        human_ticked = view == "game" and game is not None and not game.is_ai_turn
        if human_ticked:
            game.tick(elapsed)
            if position_key(game) != previous_turn:
                selected = False
        for event in events:
            if event.type == pygame.QUIT:
                running = False
                continue
            if not running:
                continue
            left_click = event.type == pygame.MOUSEBUTTONDOWN and event.button == 1
            key = event.key if event.type == pygame.KEYDOWN else None
            if view in ("settings", "pause_settings"):
                back = key == pygame.K_ESCAPE
                if left_click:
                    for name, rect in settings_buttons().items():
                        if rect.collidepoint(event.pos):
                            if name == "Back":
                                back = True
                            else:
                                options[name] = not options[name]
                                if name == "Music":
                                    set_music(options[name])
                                elif name == "Sound Effects" and not options[name] and pygame.mixer.get_init():
                                    pygame.mixer.stop()
                            break
                if back:
                    view = "pause" if view == "pause_settings" else "menu"
                continue
            if view == "menu":
                if left_click:
                    for name, rect in menu_buttons().items():
                        if rect.collidepoint(event.pos):
                            if name == "Exit Game":
                                running = False
                            elif name == "Settings":
                                view = "settings"
                            else:
                                config = deepcopy(presets.get(name) or MatchConfig.for_mode(name))
                                editing, view = None, "setup"
                            break
                continue
            if view == "setup":
                if key == pygame.K_ESCAPE:
                    view, editing = "menu", None
                    pygame.key.stop_text_input()
                elif event.type == pygame.TEXTINPUT and editing is not None:
                    text = "".join(c for c in event.text if c.isprintable())
                    config.names[editing] = (config.names[editing] + text)[:NAME_LIMIT]
                elif key == pygame.K_BACKSPACE and editing is not None:
                    config.names[editing] = config.names[editing][:-1]
                elif key == pygame.K_RETURN:
                    editing = None
                    pygame.key.stop_text_input()
                elif left_click:
                    editing = None
                    pygame.key.stop_text_input()
                    for item, rect in setup_buttons(config.mode).items():
                        if not rect.collidepoint(event.pos):
                            continue
                        if isinstance(item, tuple):
                            kind, seat = item
                            if kind == "name" and config.controllers[seat] == "Human":
                                editing = seat
                                pygame.key.start_text_input()
                            elif kind == "control":
                                choices = CONTROL_OPTIONS if config.mode == "Battle Royale" else CONTROL_OPTIONS[1:]
                                index = choices.index(config.controllers[seat])
                                config.controllers[seat] = choices[(index + 1) % len(choices)]
                        elif item == "Random Start":
                            config.random_start = not config.random_start
                        elif item == "Timer":
                            choices = (1, 3, 5) if config.mode == "Blitz" else (0, 15, 30, 60, 120)
                            value = config.blitz_minutes if config.mode == "Blitz" else config.turn_limit
                            value = choices[(choices.index(value) + 1) % len(choices)]
                            if config.mode == "Blitz":
                                config.blitz_minutes = value
                            else:
                                config.turn_limit = value
                        elif item == "Back":
                            view = "menu"
                        elif item == "Start Match":
                            presets[config.mode] = deepcopy(config)
                            launch(create_game(config))
                        break
                continue
            if view == "intro":
                if left_click or key in (pygame.K_SPACE, pygame.K_RETURN, pygame.K_ESCAPE):
                    view = "game"
                continue
            if view == "pause":
                choice = "Resume Game" if key == pygame.K_ESCAPE else None
                if left_click:
                    choice = next((name for name, rect in pause_buttons().items()
                                   if rect.collidepoint(event.pos)), None)
                if choice == "Resume Game":
                    view, game.paused = "game", False
                elif choice == "Restart Match":
                    launch(restart_game(game))
                elif choice == "Settings":
                    view = "pause_settings"
                elif choice == "Main Menu":
                    view, game, ai_state = "menu", None, None
                continue
            if game.winner is not None:
                choice = {pygame.K_n: "Play Again", pygame.K_m: "Main Menu"}.get(key)
                if left_click:
                    choice = next((name for name, rect in victory_buttons().items()
                                   if rect.collidepoint(event.pos)), None)
                if choice == "Play Again":
                    launch(restart_game(game))
                elif choice == "Main Menu":
                    view, game, ai_state = "menu", None, None
                continue
            if key == pygame.K_ESCAPE or (left_click and button_rects()["Pause"].collidepoint(event.pos)):
                view, game.paused = "pause", True
                continue
            if key == pygame.K_m or (left_click and button_rects()["Menu"].collidepoint(event.pos)):
                view, game, ai_state = "menu", None, None
                continue
            if left_click and button_rects()["New game"].collidepoint(event.pos):
                launch(restart_game(game))
                continue
            if ((key == pygame.K_z and event.mod & pygame.KMOD_CTRL) or
                    (left_click and button_rects()["Undo"].collidepoint(event.pos))):
                undo_turn(game)
                selected, ai_state = False, None
                continue
            if game.is_ai_turn:
                continue
            if key == pygame.K_r or (event.type == pygame.MOUSEBUTTONDOWN and event.button == 3):
                direction = "V" if direction == "H" else "H"
            elif left_click:
                square = square_at(event.pos)
                if square == game.pawns[game.current_player]:
                    selected = not selected
                elif selected and square is not None:
                    if game.move(square):
                        selected = False
                        play_sound(sounds, "move", options["Sound Effects"])
                elif not selected:
                    wall = preview_wall(game, selected, direction, event.pos)
                    if wall and wall_error(wall, game.walls, game.pawns, game.walls_left[game.current_player]) is None:
                        game.place_wall(wall)

        if not running:
            break
        if view == "intro":
            intro_elapsed += elapsed
            if intro_elapsed >= 1.8:
                view = "game"
        elif view == "game":
            # Do not charge a new turn for time spent in a menu or a prior turn.
            dt = elapsed if previous_view == "game" and previous_game is game and previous_turn == position_key(game) else 0.0
            active_time += dt
            token = position_key(game)
            if token != turn_key:
                turn_age, turn_key = 0.0, token
            else:
                turn_age += dt
            if game.is_ai_turn:
                if ai_state is None or ai_state["position"] != token:
                    ai_state = {"position": token, "age": 0.0, "action": None,
                                "search": search(game, game.ai_difficulty,
                                                 time_limit=min(10.0, game.remaining_turn_time),
                                                 clock=lambda: active_time)}
                old_age = ai_state["age"]
                ai_state["age"] += dt
                # Presentation time is free; only thinking beyond it uses a clock.
                game.tick(max(0.0, ai_state["age"] - 3) - max(0.0, old_age - 3))
                if position_key(game) == token and game.winner is None:
                    deadline = perf_counter() + 0.004
                    while ai_state["search"] is not None and perf_counter() < deadline:
                        try:
                            ai_state["action"] = next(ai_state["search"])
                        except StopIteration:
                            ai_state["search"] = None
                    if ai_state["search"] is None and ai_state["action"] and ai_state["age"] >= 3:
                        kind, target = ai_state["action"]
                        if kind == "move":
                            if game.move(target):
                                play_sound(sounds, "move", options["Sound Effects"])
                        else:
                            game.place_wall(target)
                        selected, ai_state = False, None
                else:
                    selected, ai_state = False, None
            else:
                ai_state = None
                if not human_ticked:
                    game.tick(dt)
                if position_key(game) != token:
                    selected = False
            if game.winner is not None and not victory_played:
                play_sound(sounds, "victory", options["Sound Effects"])
                victory_played = True

        if view == "menu":
            draw_menu(screen, fonts, assets.logo)
        elif view == "setup":
            draw_setup(screen, fonts, config, editing)
        elif view in ("settings", "pause_settings"):
            draw_settings(screen, fonts, options)
        elif view == "intro":
            draw_starting_player(screen, fonts, game, intro_elapsed)
        else:
            moves = valid_moves(game.pawns, game.current_player, game.walls) if selected and view == "game" and not game.is_ai_turn and game.winner is None else set()
            draw_board(screen, game, moves, selected, direction, pygame.mouse.get_pos(), fonts,
                       options["Animations"] and turn_age < 0.7)
            draw_victory(screen, game, stickers, fonts)
            if view == "pause":
                draw_pause(screen, fonts)
        pygame.display.flip()
    pygame.key.stop_text_input()
    pygame.quit()


if __name__ == "__main__":
    main()
