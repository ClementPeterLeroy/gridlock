# Gridlock — version 2.3

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
- **Rise of the Machines:** play Blue against Red — Pathfinder. Choose Casual or Challenging first. Blue moves first; both players start with 10 walls and use standard Versus rules.
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
- In Rise of the Machines, Play Again and New game retain the difficulty.
  Undo returns to the previous human turn, undoing the computer reply too
  if it has already played. Board input is ignored on the computer's turn;
  Menu, New game, Undo, and closing the window remain available.

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

See `version_notice.txt` for development history from 1.0 through 2.3.

## Pathfinder

`ai/pathfinder.py` proposes `(kind, target)` actions; the existing game engine
validates and executes them. BFS estimates route lengths, while the shared
rules engine checks legal moves, jumps, walls, and immediate wins or threats.
Casual mostly advances, varies reasonable moves, and occasionally considers
nearby walls. Challenging compares both routes and scans all wall positions,
conserving walls when their benefit is small or it has a clear racing lead.

Search yields after each candidate. The event loop spends about 4 ms per
frame advancing it and uses its best legal proposal when finished or when
the 10-second search budget expires. There are no artificial thinking delays.
Music, sound effects, victory stickers, and session settings remain available.

This is a temporary rule-based agent, with no neural networks, training,
or new dependencies. It does not search multiple turns ahead, and its BFS
route estimates ignore temporary pawn obstacles; actual moves still use the
full jump and sidestep rules. Difficulty is heuristic, not a skill rating.
Future neural agents can provide the same proposed-action interface.

A local seeded comparison on 2026-10-23 (seeds 0–9, each difficulty starting
once per seed) finished all 20 matches within 300 turns. Challenging won 16;
Casual won 4. Across 1,280 decisions, mean search time was 7.8 ms and maximum
was 53.2 ms; the longest incremental step measured 2.0 ms. These measurements
describe this small automated sample and local machine, not human difficulty
or a timing guarantee on every computer.

## Tests

```powershell
python -m unittest discover -s tests -v
python tests/benchmark_pathfinder.py
```
