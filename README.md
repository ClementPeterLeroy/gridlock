# Gridlock

Gridlock is transitioning from its Python/Pygame Classic Edition to a Godot-based
Gridlock v3.0. The original Pygame v2.8 implementation is preserved in `pygame/`.
Gridlock v3.0-alpha.2.1 - Core Game Engine is implemented in `godot/`.
It contains a scene-independent rules engine and the existing 3D prototype.
The prototype is not yet playable: connecting board interaction is the next milestone.

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
    |-- scenes/ and assets/ (3D prototype)
    |-- scripts/core/ (headless gameplay engine)
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

Open `godot/project.godot` with Godot 4.7.2 to view the 3D foundations.
Keys 1, 2, and 3 select Classic, Isometric, and Cinematic views.
The core engine is intentionally not connected to these scenes yet.

From the repository root, with the Godot executable available as `godot`:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
```

See the [Godot development guide](godot/README.md) for the engine API, testing,
known limitations, and roadmap. Godot release history lives in
[`godot/version_notice.txt`](godot/version_notice.txt); Classic history remains
in [`pygame/version_notice.txt`](pygame/version_notice.txt).
