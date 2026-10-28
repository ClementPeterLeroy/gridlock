# Gridlock v3.0-alpha.2.1 - Core Game Engine

Godot 4.7.2 / GDScript. The scene-independent Classic rules engine is implemented
and tested. The existing 3D prototype remains visually unchanged and is not yet
connected to the engine. There is no playable Godot match interface yet.

## View the prototype

Open `project.godot` in Godot and run the project. Keys 1, 2, and 3 select the
existing Classic, Isometric, and Cinematic cameras. Blender sources and exported
models remain in their existing directories. No core module loads these assets.

## Core modules

All five scripts in `scripts/core/` extend `RefCounted`:

| Script | Responsibility |
| --- | --- |
| `match_config.gd` | Mode, names, controllers, starting player, future timing options |
| `game_state.gd` | Stable player records, walls, turns, status, independent snapshots |
| `game_engine.gd` | Validated actions, initialization, turns, victory, forfeit, restart, undo |
| `rules.gd` | Pawn moves, jumps, sidesteps, wall validation |
| `pathfinding.gd` | Permanent board graph, BFS reachability and shortest distance |

Coordinates are always `Vector2i(column, row)`. The Classic board is fixed at
9 x 9. IDs are Sapphire 0, Crimson 1, Emerald 2, Violet 3. Four-player turns
follow 0, 2, 1, 3. Goals and IDs remain unchanged after elimination.

Walls are dictionary-set keys `Vector3i(column, row, orientation)`, with H = 0
and V = 1. Wall anchors run from 0 to 7. Walls cannot overlap, cross, or remove
the final route of any active player. BFS ignores temporary pawn occupancy.
`distance()` returns -1 when no permanent route exists.

Player records contain identity, display name, controller, goal, position,
remaining walls, and elimination status. An eliminated pawn has a null position.
Custom human names retain the legacy printable-character filtering and 12-character
limit; AI seats use their color identity.

## Engine API

Use explicit preloads so callers and tests do not depend on editor class caches:

```gdscript
const MatchOptions = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")

var config = MatchOptions.for_mode("Battle Royale")
var engine = MatchEngine.new(config)
var outcome = engine.apply_action({
    "kind": "move",
    "player_id": 0,
    "destination": Vector2i(4, 7),
})
```

`apply_action()` and `validate_action()` return `{accepted: bool, reason_code: String}`.
Wall proposals use `kind: "wall"`, `player_id`, `anchor: Vector2i`, and
`orientation: "H"` or `"V"`. Validation and rejected actions leave state and
history untouched. Controllers should never change live state directly.

`legal_moves()` returns current destinations. `legal_actions()` returns all legal
move/wall proposals. Both return no actions while paused or after victory.
Queries do not change the match. Always revalidate when committing a proposal.

Stable result codes are `ok`, `invalid_config`, `invalid_action`,
`not_active_player`, `player_eliminated`, `match_paused`, `match_finished`,
`illegal_move`, `no_walls_remaining`, `wall_outside_board`,
`wall_overlap_or_crossing`, `wall_overlap`, `path_blocked`, and `nothing_to_undo`.

`start_match(config)` validates configuration before replacing state. Construct an
engine with a valid config; for untrusted configuration, construct the default
engine first and inspect the result of `start_match(config)`.
`restart()` preserves configuration and rerolls a random starter when enabled.
An optional `RandomNumberGenerator` constructor argument makes starting-player tests
deterministic. The default fixed starter is Sapphire; `starting_player` permits
an explicitly configured seat.

`state.snapshot()` deep-copies configuration and live position data, excluding
history to avoid recursive copies. `state.restore(snapshot)` also copies its input.
The engine records a snapshot before each accepted move, wall, or forfeit.
`undo()` restores that position while retaining the current pause state.
It undoes one action; future human/AI controllers may group multiple undo operations.

`forfeit(player_id)` provides the existing timeout-removal transition: remove the
active pawn, keep placed walls, skip the seat, and declare the final survivor.
It does not run a clock or introduce a new player-facing surrender control.

## Tests

From the repository root, substitute your installed executable for `godot` if needed:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
python -B -m unittest discover -s pygame/tests -v
```

No test framework dependency is required. The runner prints a completion summary
and exits nonzero on failure. Check for both the completion summary and exit code;
a GDScript parse failure is not a completed run.

`tests/core/python_parity.json` is generated from the unchanged Pygame rules/state
and BFS distance implementation. It covers 20 reference positions, all 128 wall
candidates per position, all players' legal moves/distances, and two deterministic
32-action match traces. The fixtures use column/row coordinates explicitly.

To deliberately regenerate after an approved reference change:

```powershell
python -B godot/tests/generate_python_fixtures.py
```

## Limitations and next milestones

- No mouse input, pawn selection, highlighting, or scene synchronization yet.
- AI controllers are metadata only; Pathfinder execution remains deferred.
- Turn limits and Blitz clock options are stored, but clocks and penalties do not
  execute yet. A mode name does not imply that its complete timed/AI mode is playable.
- No replay storage, records, menus, or application-preference migration yet.
- A pawn can have no legal move while every permanent route still exists. If it
  also has no legal wall action, the engine returns an empty action list and keeps
  the match running, matching the unresolved legacy situation. No pass, draw, or
  automatic loss rule has been invented; this needs a future rules decision.
- Existing visual audit findings remain untouched: `wall.gd` creates an unused
  material, and `Wall.tscn` contains a null wall-color override. Review separately
  without changing the imported ivory/walnut appearance.

Next: **v3.0-alpha.2.2 - Interactive Board**, connecting this engine to selection,
mouse targeting, legal-move highlights, and wall previews/placement. Keep coordinate
conversion in the visual/input adapter and use the active camera for targeting.
Game modes and AI follow in alpha.3.

## Version workflow

`version_notice.txt` is authoritative for Godot releases. Every implementation patch
must update its current-version line and release entry, then synchronize
`application/config/version` in `project.godot`. The headless suite rejects mismatches
or a missing current release entry. Include completion date, features, fixes,
limitations, actual verification, and next milestone. Do not rewrite the independent
Classic history in `../pygame/version_notice.txt`.
