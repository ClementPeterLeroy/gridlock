# Gridlock — version 2.6

A local desktop strategy board game made with Python and Pygame.

## Run

Use Python 3.13 (recommended) and install dependencies:

```powershell
python -m pip install -r requirements.txt
python main.py
```

## Modes

- **Versus:** two human players, 10 walls each; choose Untimed or a turn limit.
- **Battle Royale:** four seats, 5 walls each. The setup screen lets you click each seat to cycle between Human, AI - Casual, and AI - Challenging, then select Start Match or Back. Initially Blue is Human and the other three seats are Casual AI. Any combination works, including all humans or all AI. Turn order remains Blue (bottom), Green (left), Red (top), Violet (right), clockwise. Each pawn must reach the opposite edge.
- **Blitz:** two human players with a selectable 1-, 3-, or 5-minute starting clock (3 by default), paused outside their turns. At the start of each turn, remaining time is raised to 10 seconds **only when below 10**. When it runs out, the player loses one wall and gets 15 seconds to finish the turn. One wall penalty maximum per turn; subsequent time expiry in that turn loses the game. No walls to pay the penalty also loses the game.
- **Rise of the Machines:** play Blue against Red — Pathfinder. Choose Casual or Challenging in setup. Blue moves first unless Random Starting Player is enabled; both players start with 10 walls and use standard Versus rules. This mode remains untimed.
- **Settings:** Music, Sound Effects, and Animations On/Off toggles. Changes apply immediately and last until the app closes. Animations controls the starting-player reveal and brief incoming-turn highlights.
- **Exit Game:** closes the application from the bottom-right of the main menu.

## Match setup

Every mode opens the same setup layout before starting. Click a human name
field and type to enter up to 12 characters; Backspace edits and Enter ends
editing. Blank names default to the player's color. AI seats are always
named Pathfinder, with difficulty displayed separately. Versus and Blitz
retain two human seats; Battle Royale allows any human/AI combination.

Random Starting Player is off by default. When enabled, a starter is drawn
uniformly from the seats before each match, including restarts; the normal
clockwise/alternating order then continues from that seat. A short cycling
highlight reveals the result. Click or press Space, Enter, or Esc to skip;
turning Animations off skips the reveal automatically. Match clocks and AI
actions start after the reveal, and an AI starter plays automatically.

Versus and Battle Royale offer Untimed or 15-, 30-, 60-, and 120-second
turn limits. A timeout forfeits the match in Versus. In Battle Royale the
forfeiting pawn is removed, its placed walls remain, and remaining players
continue clockwise. Wall legality checks only surviving players' paths.
The last surviving player wins. Blitz retains its separate penalty rules.

Names, seats, difficulty, random-start preference, and timing rules are
preserved by New game, Restart Match, and Play Again. Setup choices remain
available during the application session; nothing is stored permanently.

## Controls

- Hover over a board groove to preview a wall, then **left-click** to place it.
  Valid previews are translucent golden brown; invalid previews are red.
  No Wall button or mode activation is needed. Previews disappear off grooves.
- **R** or **right-click** rotates the wall orientation, which stays selected
  until you change it again. At a groove intersection both orientations can
  be previewed; elsewhere the cursor must be on a groove matching the orientation.
- Click the current player's pawn to show legal destinations in green and
  hide wall previews. Click a highlighted square to move, or click the pawn
  again to deselect. Illegal destinations and wall-slot clicks keep the pawn
  selected without placing a wall.
- Successful moves and walls end the turn and clear pawn selection.
- Wall previews and placement are disabled with no walls left, during the
  computer's turn, and after the match ends.
- **Undo** or **Ctrl+Z** restores the previous completed move (including clocks and wall penalties stored at that time).
- **New game** restarts the current mode; **Menu** returns to the menu.
- **Esc** or **Pause** opens Resume Game, Restart Match, Settings, and Main
  Menu. Timers, AI search, and AI presentation delay freeze while paused,
  including while visiting Settings. Resume preserves pawn selection too.
- On victory: click **Play Again** to restart the same mode or **Main Menu** to return to mode selection. **N** and **M** remain available as shortcuts.
- Timeout defeats show a centered explanation beneath the winner's sticker.
- In both AI modes, Play Again and New game retain the seat configuration
  and difficulties. Undo returns to the previous human turn, undoing any
  intervening AI replies. In all-AI games it undoes one action, then play
  resumes automatically. Board input is ignored on the computer's turn;
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

See `version_notice.txt` for development history from 1.0 through 2.6.

## Pathfinder

`ai/pathfinder.py` proposes `(kind, target)` actions; the existing game engine
validates and executes them. BFS estimates route lengths, while the shared
rules engine checks legal moves, jumps, walls, and immediate wins or threats.
Casual mostly advances, varies reasonable moves, and occasionally considers
nearby walls. Challenging compares its own route against every opponent's
route and scans all wall positions. The closest opponent dominates the
evaluation; other opponents' distances break close ties. Immediate threats
from any opponent receive priority. Pathfinder conserves walls when their
benefit is small or it has a clear racing lead.

Search yields after each candidate. The event loop spends about 4 ms per
frame advancing it and uses its best legal proposal when finished or when
the 10-second search budget expires. Each AI turn also has a nonblocking
three-second minimum wait before executing its action. Thinking overlaps
this wait: fast decisions execute after three seconds; slower searches
execute when ready, with the search budget still capped at ten seconds.
This pacing applies to Rise of the Machines and every Battle Royale AI seat.
The three-second presentation portion does not consume an AI's clock.
Search is capped at the lesser of ten seconds and the available turn time;
its clock excludes paused time. Eliminated seats are excluded from AI
opponent evaluation, pawn occupancy, and wall-path validation.
Music, sound effects, victory stickers, and session settings remain available.

This is a temporary rule-based agent, with no neural networks, training,
or new dependencies. It does not search multiple turns ahead, and its BFS
route estimates ignore temporary pawn obstacles; actual moves still use the
full jump and sidestep rules. Difficulty is heuristic, not a skill rating.
Future neural agents can provide the same proposed-action interface.

Match options live in `match_config.py`, rule and timeout state in `game.py`,
and setup/pause presentation in `board.py` and `main.py`. Names are limited
to 12 characters and rely on the system font's character support. The start
reveal and turn highlight are deliberately simple; no profiles, records,
or new graphics/audio dependencies are included.

A v2.3 local seeded comparison on 2026-10-23 (seeds 0–9, each difficulty starting
once per seed) finished all 20 matches within 300 turns. Challenging won 16;
Casual won 4. Across 1,280 decisions, mean search time was 7.8 ms and maximum
was 53.2 ms; the longest incremental step measured 2.0 ms. These measurements
describe this small automated sample and local machine, not human difficulty
or a timing guarantee on every computer.

The v2.5 four-player check ran 12 matches (seeds 0–3; all Casual, all
Challenging, and alternating difficulties). All finished within 400 turns
with no illegal actions or crashes: 815 decisions and 147 wall placements.
Mean search time was 22.9 ms, maximum 112.8 ms, and longest incremental step
1.8 ms on the local machine. The script skips UI pacing to measure search
time. This small sample does not establish balanced win rates between seats.

## Tests

```powershell
python -m unittest discover -s tests -v
python tests/benchmark_pathfinder.py
python tests/benchmark_battle_ai.py
```
