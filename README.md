# Gridlock — version 2

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
- **Settings:** placeholder button.

## Controls

- Click the current pawn, then a highlighted square to move.
- Click **Wall**, hover near a groove, and click to place a wall.
- **R** rotates the wall preview; **Esc** cancels selection.
- **Undo** or **Ctrl+Z** restores the previous completed move (including clocks and wall penalties stored at that time).
- **New game** restarts the current mode; **Menu** returns to the menu.
- On victory: **N** starts a new match, **M** returns to the menu.

The active player's square is gold. Original SVG stickers are in `content/px`; PNG renderings of the same stickers are bundled for reliable Pygame display without extra packages.

## Tests

```powershell
python -m unittest discover -s tests -v
```
