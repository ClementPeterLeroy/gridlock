# Gridlock

Gridlock is transitioning from its Python/Pygame Classic Edition to a Godot-based
Gridlock v3.0. The original Pygame v2.8 implementation is preserved in `pygame/`.
Gridlock v3.0-alpha.3.4 - Blitz Edit is implemented in `godot/`.
Versus, Battle Royale, and Blitz support humans and Pathfinder AI, with Casual or
Challenging difficulty per seat. Names, controller choices, and starting-player
preferences are customizable and saved locally. Versus is untimed; Battle Royale
offers Per Turn or Per Game clocks. Blitz also offers both timer types; its Per Game
penalties and overtime preserve Classic behavior. AI turns consume no countdown time.
The compact HUD,
pause/settings, animations, audio, and victory/replay remain available.
UI/menu polish is the next milestone.

## Repository layout

```text
Gridlock/
|-- README.md
|-- .gitignore
|-- pygame/
|   |-- README.md
|   |-- main.py
|   |-- game.py
|   |-- board.py
|   |-- rules.py
|   |-- ai/
|   |-- content/
|   |-- tests/
|   |-- tools/
|   |-- requirements.txt
|   |-- settings.json
|   |-- version_notice.txt
|   `-- ... (supporting Python modules)
`-- godot/
    |-- README.md
    |-- project.godot
    |-- version_notice.txt
    |-- scenes/ and assets/ (interactive 3D board)
    |-- scripts/core/ (headless gameplay engine)
    |-- scripts/controllers/ (human board interaction)
    |-- scripts/ai/ (incremental Pathfinder and turn scheduling)
    |-- scripts/ui/ (compact HUD and match pages)
    `-- tests/
```

## Run the Pygame edition

Use Python 3.13. From the repository root, install dependencies and launch:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r pygame/requirements.txt
python pygame/main.py
```

An existing Python environment with the dependencies installed can also be used.
Alternatively, enter `pygame/` and run `python main.py`. Assets and saved application
settings resolve beside the legacy source files, independently of the launch directory.
The preference file is now `pygame/settings.json`.

See the [Pygame guide](pygame/README.md) for game modes, controls, settings, and
Classic Edition details. [Asset sources and licenses](pygame/content/ASSETS.md)
and the [development history](pygame/version_notice.txt) moved with the application.

## Test the Pygame edition

From the repository root:

```powershell
python -m unittest discover -s pygame/tests -v
python pygame/tests/benchmark_pathfinder.py
python pygame/tests/benchmark_battle_ai.py
```

## Godot development

Open `godot/project.godot` with Godot 4.7.2, run, and choose Versus, Battle Royale, or Blitz.
Select Human, AI - Casual, or AI - Challenging for each seat before starting.
Edit player names and choose Default or Random starter. Versus is always untimed.
Battle Royale offers 15/30/60/120/180-second turns or 1/3/5/10/15-minute player
budgets. Blitz offers 15/30/60/120/180-second turns or 1/3/5-minute Per Game clocks,
defaulting to Per Game / three minutes. Both types remember their selected duration.
Match preferences persist in Godot's `user://match_preferences.cfg`.
Restart keeps the chosen starter; Play Again redraws it when Random is selected.
AI turns show a thinking message and wait at least one second; pause freezes AI work.
Timed AI cards display Exempt; their thinking and presentation never consume clocks.
Keys 1, 2, and 3 select Classic, Isometric, and Cinematic views.
Click the active pawn and a green tile to move, or hover a groove and click to
place a wall. R / right-click rotates; Esc deselects a selected pawn or pauses.
The top-left hamburger opens Settings, Pause, Restart Match, and Main Menu.
Top-right cards show identity, walls, elapsed/countdown time, and Blitz overtime.

From the repository root, with the Godot executable available as `godot`:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
godot --headless --path godot --script res://tests/run_interaction_tests.gd
godot --headless --path godot --script res://tests/run_match_tests.gd
godot --headless --path godot --script res://tests/run_ai_tests.gd
godot --headless --path godot --script res://tests/run_timing_tests.gd
godot --headless --path godot --script res://tests/run_customization_tests.gd
godot --headless --path godot --script res://tests/run_blitz_edit_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
python -B godot/tests/generate_ai_fixtures.py --check
python -B godot/tests/generate_timing_fixtures.py --check
```

See the [Godot development guide](godot/README.md) for the engine API, testing,
known limitations, and roadmap. Godot release history lives in
[`godot/version_notice.txt`](godot/version_notice.txt); Classic history remains
in [`pygame/version_notice.txt`](pygame/version_notice.txt).
