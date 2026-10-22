"""Start Gridlock with: python main.py"""

import pygame
from board import (draw_board, draw_menu, draw_victory, load_stickers,
                   square_at, wall_at, button_rects, menu_buttons)
from game import Game
from rules import valid_moves
from settings import WINDOW_WIDTH, WINDOW_HEIGHT, FPS


def main():
    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("Gridlock")
    fonts = (pygame.font.SysFont("georgia", 36, bold=True),
             pygame.font.SysFont("arial", 18),
             pygame.font.SysFont("arial", 15))
    stickers = load_stickers()
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
            if game is None:
                if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    for name, rect in menu_buttons().items():
                        if rect.collidepoint(event.pos) and name != "Settings":
                            game = Game("Versus" if name == "Rise of the Machines" else name)
                            action, selected = "pawn", False
                            break
                continue
            if event.type == pygame.KEYDOWN:
                if game.winner is not None and event.key == pygame.K_n:
                    game = Game(game.mode)
                    action, selected = "pawn", False
                elif event.key == pygame.K_m:
                    game = None
                    action, selected = "pawn", False
                elif event.key == pygame.K_ESCAPE:
                    action, selected = "pawn", False
                elif event.key == pygame.K_r and action == "wall":
                    direction = "V" if direction == "H" else "H"
                elif event.key == pygame.K_z and event.mod & pygame.KMOD_CTRL:
                    game.undo()
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
                    game = Game(game.mode)
                    action, selected = "pawn", False
                elif buttons["Undo"].collidepoint(pos):
                    game.undo()
                    action, selected = "pawn", False
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
                    else:
                        selected = False
        if game is None:
            draw_menu(screen, fonts)
        else:
            game.tick(elapsed)
            moves = (valid_moves(game.pawns, game.current_player, game.walls)
                     if selected and action == "pawn" and game.winner is None else set())
            draw_board(screen, game, moves, action, direction, pygame.mouse.get_pos(), fonts)
            draw_victory(screen, game, stickers, fonts)
        pygame.display.flip()
    pygame.quit()


if __name__ == "__main__":
    main()
