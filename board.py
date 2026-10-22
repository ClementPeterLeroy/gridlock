"""Pygame drawing and mouse position helpers."""

from pathlib import Path
import pygame
from settings import (BOARD_SIZE, CELL_SIZE, GAP, BOARD_X, BOARD_Y,
                      BOARD_PIXELS, WOOD, WOOD_LIGHT, GROOVE, GOLD,
                      PLAYER_COLORS, PLAYER_NAMES, TEXT, HIGHLIGHT, INVALID,
                      WINDOW_WIDTH, WINDOW_HEIGHT, BACKGROUND)
from rules import wall_error

STEP = CELL_SIZE + GAP
PANEL_X = 615


def square_at(pos):
    x, y = pos[0] - BOARD_X, pos[1] - BOARD_Y
    if x < 0 or y < 0:
        return None
    col, dx = divmod(x, STEP)
    row, dy = divmod(y, STEP)
    if row < BOARD_SIZE and col < BOARD_SIZE and dx < CELL_SIZE and dy < CELL_SIZE:
        return row, col
    return None


def wall_at(pos, direction):
    """Pick the nearest groove intersection for a wall preview."""
    x, y = pos[0] - BOARD_X, pos[1] - BOARD_Y
    if direction == "H":
        col = int((x - CELL_SIZE / 2) // STEP)
        row = int((y - CELL_SIZE) // STEP)
        if 0 <= row < 8 and 0 <= col < 8:
            center_x = (col + 1) * STEP - GAP / 2
            center_y = (row + 1) * STEP - GAP / 2
            if abs(y - center_y) <= 16 and abs(x - center_x) <= STEP:
                return row, col, "H"
    else:
        col = int((x - CELL_SIZE) // STEP)
        row = int((y - CELL_SIZE / 2) // STEP)
        if 0 <= row < 8 and 0 <= col < 8:
            center_x = (col + 1) * STEP - GAP / 2
            center_y = (row + 1) * STEP - GAP / 2
            if abs(x - center_x) <= 16 and abs(y - center_y) <= STEP:
                return row, col, "V"
    return None


def wall_rect(wall):
    row, col, direction = wall
    if direction == "H":
        return pygame.Rect(BOARD_X + col * STEP - 2,
                           BOARD_Y + (row + 1) * STEP - GAP - 2,
                           2 * CELL_SIZE + GAP + 4, GAP + 4)
    return pygame.Rect(BOARD_X + (col + 1) * STEP - GAP - 2,
                       BOARD_Y + row * STEP - 2,
                       GAP + 4, 2 * CELL_SIZE + GAP + 4)


def draw_text(screen, font, value, x, y, color=TEXT):
    screen.blit(font.render(str(value), True, color), (x, y))


def button_rects():
    return {
        "Wall": pygame.Rect(PANEL_X, 477, 130, 39),
        "Undo": pygame.Rect(PANEL_X + 140, 477, 130, 39),
        "New game": pygame.Rect(PANEL_X, 526, 130, 39),
        "Menu": pygame.Rect(PANEL_X + 140, 526, 130, 39),
    }


def menu_buttons():
    names = ("Versus", "Battle Royale", "Blitz", "Rise of the Machines", "Settings")
    return {name: pygame.Rect(290, 185 + i * 79, 350, 60) for i, name in enumerate(names)}


def draw_menu(screen, fonts):
    title_font, font, small = fonts
    screen.fill(BACKGROUND)
    heading = title_font.render("GRIDLOCK", True, TEXT)
    screen.blit(heading, heading.get_rect(center=(WINDOW_WIDTH // 2, 85)))
    sub = font.render("Race across. Block the way.", True, GROOVE)
    screen.blit(sub, sub.get_rect(center=(WINDOW_WIDTH // 2, 125)))
    for name, rect in menu_buttons().items():
        pygame.draw.rect(screen, (114, 82, 56), rect, border_radius=9)
        pygame.draw.rect(screen, (179, 143, 97), rect, 2, border_radius=9)
        label = font.render(name, True, (255, 248, 234))
        screen.blit(label, label.get_rect(center=rect.center))
    draw_text(screen, small, "Rise of the Machines: 2-player placeholder", 300, 596)
    draw_text(screen, small, "Settings: coming later", 300, 616)


def draw_board(screen, game, moves, action, direction, mouse, fonts):
    title_font, font, small = fonts
    screen.fill(BACKGROUND)
    pygame.draw.rect(screen, GROOVE, (BOARD_X - 10, BOARD_Y - 10,
                                     BOARD_PIXELS + 20, BOARD_PIXELS + 20), border_radius=7)
    for row in range(9):
        for col in range(9):
            x, y = BOARD_X + col * STEP, BOARD_Y + row * STEP
            shade = WOOD_LIGHT if (row + col) % 2 == 0 else WOOD
            if game.winner is None and (row, col) == game.pawns[game.current_player]:
                shade = GOLD
            pygame.draw.rect(screen, shade, (x, y, CELL_SIZE, CELL_SIZE), border_radius=3)
            if (row, col) in moves:
                pygame.draw.circle(screen, HIGHLIGHT,
                                   (x + CELL_SIZE // 2, y + CELL_SIZE // 2), 9)
    for wall in game.walls:
        pygame.draw.rect(screen, (69, 45, 30), wall_rect(wall), border_radius=3)
    if action == "wall" and game.winner is None:
        wall = wall_at(mouse, direction)
        if wall:
            error = wall_error(wall, game.walls, game.pawns, game.walls_left[game.current_player])
            overlay = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT), pygame.SRCALPHA)
            color = (*INVALID, 160) if error else (*HIGHLIGHT, 180)
            pygame.draw.rect(overlay, color, wall_rect(wall), border_radius=3)
            screen.blit(overlay, (0, 0))
    for player, (row, col) in enumerate(game.pawns):
        center = (BOARD_X + col * STEP + CELL_SIZE // 2,
                  BOARD_Y + row * STEP + CELL_SIZE // 2)
        pygame.draw.circle(screen, (73, 52, 36), (center[0] + 2, center[1] + 3), 19)
        pygame.draw.circle(screen, PLAYER_COLORS[player], center, 18)
        pygame.draw.circle(screen, (244, 228, 199), center, 18, 2)

    draw_text(screen, title_font, "GRIDLOCK", PANEL_X, 48)
    draw_text(screen, small, game.mode, PANEL_X, 91)
    pygame.draw.line(screen, GROOVE, (PANEL_X, 116), (885, 116), 1)
    for slot, player in enumerate((0, 2, 1, 3) if game.player_count == 4 else (0, 1)):
        y = 130 + slot * (67 if game.player_count == 4 else 86)
        active = game.winner is None and player == game.current_player
        if active:
            pygame.draw.rect(screen, (250, 223, 147), (PANEL_X - 6, y - 7, 276, 60), border_radius=6)
        pygame.draw.circle(screen, PLAYER_COLORS[player], (PANEL_X + 12, y + 12), 11)
        draw_text(screen, font, PLAYER_NAMES[player] + ("  • TURN" if active else ""), PANEL_X + 31, y)
        draw_text(screen, small, f"Walls: {game.walls_left[player]}", PANEL_X + 31, y + 27)
        if game.is_blitz:
            draw_text(screen, small, f"Clock: {game.time_left[player]:.1f}s", PANEL_X + 164, y + 27)
    timer_y = 422 if game.player_count == 4 else 340
    if game.is_blitz:
        value = game.overtime if game.penalty_used else game.time_left[game.current_player]
        timer_text = f"Time left: {value:.1f}s"
    else:
        timer_text = f"Turn: {game.turn_elapsed:.1f}s"
    draw_text(screen, font, timer_text, PANEL_X, timer_y)
    if game.is_blitz and game.penalty_used:
        draw_text(screen, small, "Wall penalty applied this turn", PANEL_X, timer_y + 27, INVALID)
    elif game.player_count == 2:
        draw_text(screen, small, "Click pawn, then a highlighted square", PANEL_X, 390)
    for label, rect in button_rects().items():
        pygame.draw.rect(screen, (114, 82, 56), rect, border_radius=5)
        draw_text(screen, font, label, rect.x + 10, rect.y + 9, (255, 248, 234))
    draw_text(screen, small, "R: rotate wall    Esc: cancel", PANEL_X, 580)
    draw_text(screen, small, game.message[:65], 38, 618)
    if action == "wall":
        draw_text(screen, small, f"Wall preview: {direction}", PANEL_X, 603)


def load_stickers():
    """PNG renderings are packaged alongside the original editable SVGs."""
    folder = Path(__file__).resolve().parent / "content" / "px"
    images = {}
    for name in ("blue", "red", "green", "violet"):
        path = folder / f"{name}_victory.png"
        if path.exists():
            image = pygame.image.load(str(path)).convert_alpha()
            images[name] = pygame.transform.smoothscale(image, (540, 312))
    return images


def draw_victory(screen, game, stickers, fonts):
    if game.winner is None:
        return
    _, font, small = fonts
    tint = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT), pygame.SRCALPHA)
    tint.fill((32, 23, 17, 165))
    screen.blit(tint, (0, 0))
    card = pygame.Rect(163, 92, 605, 466)
    pygame.draw.rect(screen, (247, 232, 205), card, border_radius=16)
    pygame.draw.rect(screen, GROOVE, card, 3, border_radius=16)
    name = PLAYER_NAMES[game.winner]
    sticker = stickers.get(name.lower())
    if sticker:
        screen.blit(sticker, sticker.get_rect(center=(WINDOW_WIDTH // 2, 297)))
    else:
        label = font.render(f"{name.upper()} WINS!", True, PLAYER_COLORS[game.winner])
        screen.blit(label, label.get_rect(center=(WINDOW_WIDTH // 2, 275)))
    draw_text(screen, small, game.message, 240, 475)
    draw_text(screen, font, "N: New game       M: Menu", 302, 510)
