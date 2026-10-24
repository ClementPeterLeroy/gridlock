"""Pygame drawing and mouse position helpers."""

from pathlib import Path
import pygame
from settings import (BOARD_SIZE, CELL_SIZE, GAP, BOARD_X, BOARD_Y,
                      BOARD_PIXELS, WOOD, WOOD_LIGHT, GROOVE, GOLD,
                      PLAYER_COLORS, PLAYER_NAMES, TEXT, HIGHLIGHT, INVALID,
                      WINDOW_WIDTH, WINDOW_HEIGHT, BACKGROUND)
from rules import wall_error
from game import FOUR_PLAYER_ORDER
from match_config import clean_name

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
    """Pick a groove with three pixels of tolerance on either side."""
    x, y = pos[0] - BOARD_X, pos[1] - BOARD_Y
    if not (0 <= x < BOARD_PIXELS and 0 <= y < BOARD_PIXELS):
        return None
    tolerance = GAP / 2 + 3
    if direction == "H":
        row = round((y - CELL_SIZE - GAP / 2) / STEP)
        col = max(0, min(7, int((x - CELL_SIZE / 2) // STEP)))
        if 0 <= row < 8 and 0 <= col < 8:
            center_x = (col + 1) * STEP - GAP / 2
            center_y = (row + 1) * STEP - GAP / 2
            if abs(y - center_y) <= tolerance and abs(x - center_x) <= STEP:
                return row, col, "H"
    else:
        col = round((x - CELL_SIZE - GAP / 2) / STEP)
        row = max(0, min(7, int((y - CELL_SIZE / 2) // STEP)))
        if 0 <= row < 8 and 0 <= col < 8:
            center_x = (col + 1) * STEP - GAP / 2
            center_y = (row + 1) * STEP - GAP / 2
            if abs(x - center_x) <= tolerance and abs(y - center_y) <= STEP:
                return row, col, "V"
    return None


def preview_wall(game, selected, direction, mouse):
    """Shared hover/click target; unavailable board interactions return None."""
    if (selected or game.paused or game.winner is not None or square_at(mouse) in game.pawns
            or game.walls_left[game.current_player] <= 0
            or game.is_ai_turn):
        return None
    return wall_at(mouse, direction)


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
        "Undo": pygame.Rect(PANEL_X, 477, 130, 39),
        "Pause": pygame.Rect(PANEL_X + 140, 477, 130, 39),
        "New game": pygame.Rect(PANEL_X, 526, 130, 39),
        "Menu": pygame.Rect(PANEL_X + 140, 526, 130, 39),
    }


def menu_buttons():
    names = ("Versus", "Battle Royale", "Blitz", "Rise of the Machines", "Settings")
    buttons = {name: pygame.Rect(290, 185 + i * 79, 350, 60) for i, name in enumerate(names)}
    buttons["Exit Game"] = pygame.Rect(750, 594, 155, 40)
    return buttons


def draw_button(screen, font, label, rect):
    pygame.draw.rect(screen, (114, 82, 56), rect, border_radius=9)
    pygame.draw.rect(screen, (179, 143, 97), rect, 2, border_radius=9)
    text = font.render(label, True, (255, 248, 234))
    screen.blit(text, text.get_rect(center=rect.center))


def settings_buttons():
    return {name: pygame.Rect(260, 200 + i * 85, 410, 60)
            for i, name in enumerate(("Music", "Sound Effects", "Animations", "Back"))}


def draw_settings(screen, fonts, options):
    title_font, font, small = fonts
    screen.fill(BACKGROUND)
    title = title_font.render("SETTINGS", True, TEXT)
    screen.blit(title, title.get_rect(center=(WINDOW_WIDTH // 2, 110)))
    for name, rect in settings_buttons().items():
        label = name if name == "Back" else f"{name}: {'On' if options[name] else 'Off'}"
        draw_button(screen, font, label, rect)
    hint = small.render("Animations: starting-player reveal and incoming-turn highlights", True, GROOVE)
    screen.blit(hint, hint.get_rect(center=(WINDOW_WIDTH // 2, 570)))


def victory_buttons():
    return {"Play Again": pygame.Rect(245, 497, 200, 42),
            "Main Menu": pygame.Rect(485, 497, 200, 42)}


def setup_buttons(mode):
    players = FOUR_PLAYER_ORDER if mode == "Battle Royale" else (0, 1)
    buttons = {}
    for slot, player in enumerate(players):
        buttons[("name", player)] = pygame.Rect(240, 150 + slot * 72, 230, 48)
        if mode == "Battle Royale" or (mode == "Rise of the Machines" and player == 1):
            buttons[("control", player)] = pygame.Rect(490, 150 + slot * 72, 290, 48)
    buttons["Random Start"] = pygame.Rect(240, 453, 540, 42)
    if mode != "Rise of the Machines":
        buttons["Timer"] = pygame.Rect(240, 503, 540, 42)
    buttons["Start Match"] = pygame.Rect(240, 570, 260, 48)
    buttons["Back"] = pygame.Rect(520, 570, 260, 48)
    return buttons


def draw_setup(screen, fonts, config, editing=None):
    title_font, font, small = fonts
    screen.fill(BACKGROUND)
    title = title_font.render(config.mode.upper(), True, TEXT)
    screen.blit(title, title.get_rect(center=(WINDOW_WIDTH // 2, 70)))
    draw_text(screen, small, "Click a human name to edit; click an AI control to cycle difficulty.", 180, 112)
    players = FOUR_PLAYER_ORDER if config.mode == "Battle Royale" else (0, 1)
    buttons = setup_buttons(config.mode)
    for player in players:
        rect = buttons[("name", player)]
        pygame.draw.circle(screen, PLAYER_COLORS[player], (110, rect.centery), 12)
        draw_text(screen, font, PLAYER_NAMES[player], 135, rect.y + 12)
        human = config.controllers[player] == "Human"
        value = (config.names[player] if editing == player else clean_name(config.names[player], player)) if human else "Pathfinder"
        draw_button(screen, font, value + (" |" if editing == player else ""), rect)
        if editing == player:
            pygame.draw.rect(screen, GOLD, rect, 3, border_radius=9)
        if ("control", player) in buttons:
            draw_button(screen, font, config.controllers[player], buttons[("control", player)])
    draw_text(screen, small, "Human names: up to 12 characters. Blank names use the player color.", 240, 428)
    draw_button(screen, font, "Random Starting Player: " + ("On" if config.random_start else "Off"), buttons["Random Start"])
    if "Timer" in buttons:
        timer = f"Starting clock: {config.blitz_minutes} minutes" if config.mode == "Blitz" else (f"Turn Limit: {config.turn_limit} seconds" if config.turn_limit else "Untimed")
        draw_button(screen, font, timer, buttons["Timer"])
    for label in ("Start Match", "Back"):
        draw_button(screen, font, label, buttons[label])


def pause_buttons():
    return {label: pygame.Rect(280, 200 + i * 75, 370, 55)
            for i, label in enumerate(("Resume Game", "Restart Match", "Settings", "Main Menu"))}


def draw_pause(screen, fonts):
    shade = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT), pygame.SRCALPHA)
    shade.fill((32, 23, 17, 190))
    screen.blit(shade, (0, 0))
    title = fonts[0].render("PAUSED", True, GOLD)
    screen.blit(title, title.get_rect(center=(WINDOW_WIDTH // 2, 125)))
    for label, rect in pause_buttons().items():
        draw_button(screen, fonts[1], label, rect)


def draw_starting_player(screen, fonts, game, elapsed):
    screen.fill(BACKGROUND)
    title = fonts[0].render("WHO STARTS?", True, TEXT)
    screen.blit(title, title.get_rect(center=(WINDOW_WIDTH // 2, 130)))
    players = game.active_players
    highlighted = players[int(elapsed / 0.12) % len(players)] if elapsed < 1.1 else game.current_player
    for slot, player in enumerate(players):
        x = WINDOW_WIDTH // 2 + int((slot - (len(players) - 1) / 2) * 190)
        rect = pygame.Rect(x - 85, 240, 170, 100)
        pygame.draw.rect(screen, GOLD if player == highlighted else WOOD, rect, border_radius=9)
        label = fonts[1].render(PLAYER_NAMES[player], True, PLAYER_COLORS[player])
        screen.blit(label, label.get_rect(center=(x, 275)))
        name = fonts[2].render(game.display_name(player), True, TEXT)
        screen.blit(name, name.get_rect(center=(x, 310)))
    text = f"{game.player_label(game.current_player)} starts!" if elapsed >= 1.1 else "Selecting starting player..."
    label = fonts[1].render(text, True, TEXT)
    screen.blit(label, label.get_rect(center=(WINDOW_WIDTH // 2, 410)))
    hint = fonts[2].render("Click or press Space / Enter / Esc to skip", True, GROOVE)
    screen.blit(hint, hint.get_rect(center=(WINDOW_WIDTH // 2, 470)))


def draw_menu(screen, fonts):
    title_font, font, small = fonts
    screen.fill(BACKGROUND)
    heading = title_font.render("GRIDLOCK", True, TEXT)
    screen.blit(heading, heading.get_rect(center=(WINDOW_WIDTH // 2, 85)))
    sub = font.render("Race across. Block the way.", True, GROOVE)
    screen.blit(sub, sub.get_rect(center=(WINDOW_WIDTH // 2, 125)))
    for name, rect in menu_buttons().items():
        draw_button(screen, font, name, rect)
    draw_text(screen, small, "v2.6 - Match Customization", 24, WINDOW_HEIGHT - 30)


def draw_board(screen, game, moves, selected, direction, mouse, fonts, flash=False):
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
        pygame.draw.rect(screen, (92, 31, 37), wall_rect(wall), border_radius=3)
    wall = preview_wall(game, selected, direction, mouse)
    if wall:
        error = wall_error(wall, game.walls, game.pawns, game.walls_left[game.current_player])
        overlay = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT), pygame.SRCALPHA)
        color = (*INVALID, 160) if error else (255, 225, 140, 200)
        pygame.draw.rect(overlay, color, wall_rect(wall), border_radius=3)
        screen.blit(overlay, (0, 0))
    for player, square in enumerate(game.pawns):
        if square is None:
            continue
        row, col = square
        center = (BOARD_X + col * STEP + CELL_SIZE // 2,
                  BOARD_Y + row * STEP + CELL_SIZE // 2)
        pygame.draw.circle(screen, (73, 52, 36), (center[0] + 2, center[1] + 3), 19)
        pygame.draw.circle(screen, PLAYER_COLORS[player], center, 18)
        pygame.draw.circle(screen, (244, 228, 199), center, 18, 2)

    draw_text(screen, title_font, "GRIDLOCK", PANEL_X, 48)
    draw_text(screen, small, game.mode, PANEL_X, 91)
    if game.mode == "Rise of the Machines":
        draw_text(screen, small, game.difficulty, PANEL_X + 190, 91)
    pygame.draw.line(screen, GROOVE, (PANEL_X, 116), (885, 116), 1)
    for slot, player in enumerate((0, 2, 1, 3) if game.player_count == 4 else (0, 1)):
        y = 130 + slot * (67 if game.player_count == 4 else 86)
        active = game.winner is None and player == game.current_player
        if active:
            pygame.draw.rect(screen, (250, 223, 147), (PANEL_X - 6, y - 7, 276, 60), border_radius=6)
            if flash:
                pygame.draw.rect(screen, GOLD, (PANEL_X - 6, y - 7, 276, 60), 3, border_radius=6)
        pygame.draw.circle(screen, PLAYER_COLORS[player], (PANEL_X + 12, y + 12), 11)
        name = game.display_name(player)
        label = PLAYER_NAMES[player] if name == PLAYER_NAMES[player] else f"{PLAYER_NAMES[player]} - {name}"
        draw_text(screen, font, label, PANEL_X + 31, y)
        controller = game.controller(player)
        control_label = ("Forfeited" if player in game.eliminated else "Human" if controller == "Human"
                         else controller.removeprefix("AI - ") + " AI")
        draw_text(screen, small, control_label, PANEL_X + 31, y + 20)
        draw_text(screen, small, f"Walls: {game.walls_left[player]}", PANEL_X + 31, y + 40)
        if game.is_blitz:
            draw_text(screen, small, f"Clock: {game.time_left[player]:.1f}s", PANEL_X + 150, y + 40)
    timer_y = 422 if game.player_count == 4 else 340
    if game.is_blitz:
        value = game.overtime if game.penalty_used else game.time_left[game.current_player]
        timer_text = f"Time left: {value:.1f}s"
    elif game.config.turn_limit:
        timer_text = f"Turn left: {game.remaining_turn_time:.1f}s"
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
    draw_text(screen, small, "R / right-click: rotate   Esc: pause", PANEL_X, 580)
    if game.winner is None:
        draw_text(screen, small, game.message[:65], 38, 618)
    hint = ("Pathfinder thinking / preparing move..." if game.is_ai_turn else
            "Pawn selected: click again to deselect" if selected else
            f"Hover grooves to place walls ({direction})")
    draw_text(screen, small, hint, PANEL_X, 603)


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
    if "ran out of time" in game.message:
        message = small.render(game.message, True, TEXT)
        screen.blit(message, message.get_rect(center=(WINDOW_WIDTH // 2, 472)))
    for label, rect in victory_buttons().items():
        draw_button(screen, font, label, rect)
