# Gridlock — version 2.1

A local desktop strategy board game made with Python and Pygame.

## Run

Use Python 3.13 (recommended) and install dependencies:

```powershell
python -m pip install -r requirements.txt
python main.py
```

## Modes

- **Versus:** two local players, 10 walls each; elapsed turn timer, no penalties.
- **Battle Royale:** four local players, 5 walls each. Turn order is Blue (bottom), Green (left), Red (top), Violet (right), clockwise. Each pawn must reach the opposite edge.
- **Blitz:** two local players with 180 seconds each, paused outside their turns. At the start of each turn, remaining time is raised to 10 seconds **only when below 10**. When it runs out, the player loses one wall and gets 15 seconds to finish the turn. One wall penalty maximum per turn; subsequent time expiry in that turn loses the game. No walls to pay the penalty also loses the game.
- **Rise of the Machines:** starts a regular two-player Versus game for now (no AI yet).
- **Settings:** Music, Sound Effects, and Animations On/Off toggles. Changes apply immediately and last until the app closes. Animations is a placeholder for future features.
- **Exit Game:** closes the application from the bottom-right of the main menu.

## Controls

- Click the current pawn, then a highlighted square to move.
- Click **Wall**, hover near a groove, and click to place a wall.
- **R** or **right-click** rotates the wall preview during wall placement; **Esc** cancels selection.
- **Undo** or **Ctrl+Z** restores the previous completed move (including clocks and wall penalties stored at that time).
- **New game** restarts the current mode; **Menu** returns to the menu.
- On victory: click **Play Again** to restart the same mode or **Main Menu** to return to mode selection. **N** and **M** remain available as shortcuts.
- Timeout defeats show a centered explanation beneath the winner's sticker.

The active player's square is gold. Original SVG stickers are in `content/px`; PNG renderings of the same stickers are bundled for reliable Pygame display without extra packages.

## Audio

Pygame's mixer plays `content/sound/simple_happy_loop.mp3` continuously at
20% volume. Switching between menus and games does not restart it. The Music
toggle pauses/resumes the loop. Successful pawn moves play `simple_move.wav`,
and each finished match plays `electronic_victory_sound.mp3` once (the loader
detects the victory file's extension). Sound Effects controls both effects.
The game remains playable if an audio device or file is unavailable.

The music and sound files are development placeholders: they are not final,
optimized, or tailor-made for Gridlock yet.

See `version_notice.txt` for development history from 1.0 through 2.1.

## Tests

```powershell
python -m unittest discover -s tests -v
```
