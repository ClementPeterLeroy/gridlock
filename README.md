# Gridlock

Gridlock is transitioning from its Python/Pygame Classic Edition to a Godot-based
Gridlock v3.0. The original Pygame v2.8 implementation is preserved in `pygame/`.
Gridlock v3.0 is under development; **no Godot implementation is included yet**.
The `godot/` directory is reserved for future integration.

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
    `-- README.md (reserved; no Godot project yet)
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

Phase 1 only reorganizes the existing application. It does not change gameplay,
AI algorithms, graphics, rules, or begin the Godot port.
