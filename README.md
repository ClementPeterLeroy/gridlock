# Gridlock

Gridlock is transitioning from its Python/Pygame Classic Edition to a Godot-based
Gridlock v3.0. The original Pygame v2.8 implementation is preserved in `pygame/`.
Gridlock v3.0-alpha.2.2 - Interactive Board is implemented in `godot/`.
The 3D board now supports local pawn movement, wall previews/placement, turns,
and basic victory/restart through the scene-independent engine. Full match menus,
AI, and live clocks are still under development.

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

Open `godot/project.godot` with Godot 4.7.2 and run the interactive board.
Keys 1, 2, and 3 select Classic, Isometric, and Cinematic views.
Click the active pawn and a green tile to move, or hover a groove and click to
place a wall. R / right-click rotates; Esc deselects; N or Restart Match restarts.
The default board is four local human players. Set the Game node's Board Mode
to Versus in the Inspector for a two-player board.

From the repository root, with the Godot executable available as `godot`:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
godot --headless --path godot --script res://tests/run_interaction_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
```

See the [Godot development guide](godot/README.md) for the engine API, testing,
known limitations, and roadmap. Godot release history lives in
[`godot/version_notice.txt`](godot/version_notice.txt); Classic history remains
in [`pygame/version_notice.txt`](pygame/version_notice.txt).
