# Gridlock v3.0-alpha.2.2 - Interactive Board

Godot 4.7.2 / GDScript. The existing 3D board is now connected to the Classic
rules engine for local human movement, walls, turns, victory, and restart.
The original models, materials, lighting, and camera presets are preserved.

## Play the interactive board

Open `project.godot` in Godot and run the project. The default is four local
human players, preserving the prototype's four identities. For two players, set
the Game node's Board Mode to Versus in the Inspector. Match-setup menus are deferred.

- Left-click the active pawn to select it and show green legal destinations.
- Click a green tile to move. Click the pawn again or press Esc to deselect.
- Clicking an empty tile that is not highlighted clears selection without moving.
- With no pawn selected, hover a groove to preview a wall. Left-click places it.
- R or right-click rotates the orientation. Green previews are legal; red previews
  are rejected by the engine. Rejected walls never spend inventory or a turn.
- Tile interiors always take priority over groove tolerance; clicking a tile cannot
  accidentally place a wall. Selection suppresses wall previews.
- Keys 1, 2, and 3 select Classic, Isometric, and Cinematic. All existing camera
  positions, sizes, angles, and 0.8-second transitions are retained.
- The golden ring and status label identify the active player. Wall inventories
  update after accepted actions. Victory stops input and shows one winner message.
- Restart Match or N starts a fresh board with the same configuration.

Blender sources and exported models remain in their existing directories.
No core module loads these assets. The authored demonstration wall is hidden;
only walls in the authoritative state are rendered as permanent walls.

## Interaction architecture

`scripts/controllers/human_controller.gd` owns selection, groove targeting,
orientation, and preview state. It requests legal destinations and validates/submits
actions through the existing engine API; it does not calculate gameplay legality.

`game.gd` projects mouse rays through the current camera, tests pawn volumes, and
intersects the tile-top plane in board-local coordinates. It repeats targeting
every frame so stationary cursors also follow camera transitions. The HUD consumes
its own clicks and hides previews. Accepted actions synchronize pawn positions,
permanent walls, inventory, active player, and winner from GameState.

`board.gd` maps cells/wall anchors into existing model coordinates and adds separate
translucent green planes and a golden ring. Original tile and pawn materials are
not replaced. Preview walls use instance-only overrides; permanent walls retain
their imported ivory/walnut materials. Pawn model offsets are preserved.

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
godot --headless --path godot --script res://tests/run_interaction_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
python -B -m unittest discover -s pygame/tests -v
```

No test framework dependency is required. The runner prints a completion summary
and exits nonzero on failure. Check for both the completion summary and exit code;
a GDScript parse failure is not a completed run.

The interaction suite loads the actual imported scene. It checks controller
behavior, synchronization, GUI/keyboard/mouse events, model alignment, material
preservation, two/four-player behavior, and ray targeting in all camera views and
during their transitions. Unlike the core suite, it needs the project's imported
model assets. On a fresh checkout, open the project in Godot first to import them
(the preserved Blender source imports require a configured Blender installation).

Validation for alpha.2.2: 3353 core checks and 602 interaction checks passed on
Godot 4.7.2. Python parity fixtures matched the unchanged Classic implementation.
Rendered D3D12/Forward+ captures were inspected for the three camera views,
green move highlights, the golden active ring, and the translucent wall preview.
The existing Pygame regression suite also passed all 100 tests on Python 3.13.12.

Manual verification before wider release:

1. In each camera view, select a pawn, move, deselect on an unrelated tile, and
   confirm the golden ring and inventory panel update for the next player.
2. Aim along board-edge and central grooves, rotate with R and right-click, and
   place both orientations. Try an overlapping/crossing wall and confirm red feedback.
3. Move the cursor over the HUD and outside the board; previews must disappear.
   Switch cameras with the cursor stationary and click during a transition.
4. Play to victory, confirm gameplay stops, then restart using both the button
   and N. Repeat with Board Mode set to Versus, including at your display resolution.

`tests/core/python_parity.json` is generated from the unchanged Pygame rules/state
and BFS distance implementation. It covers 20 reference positions, all 128 wall
candidates per position, all players' legal moves/distances, and two deterministic
32-action match traces. The fixtures use column/row coordinates explicitly.

To deliberately regenerate after an approved reference change:

```powershell
python -B godot/tests/generate_python_fixtures.py
```

## Limitations and next milestones

- AI controllers are metadata only; Pathfinder execution remains deferred.
- Turn limits and Blitz clock options are stored, but clocks and penalties do not
  execute yet. A mode name does not imply that its complete timed/AI mode is playable.
- Full match flow/menus, richer victory presentation, replay storage, records, and
  application-preference migration remain deferred.
- A pawn can have no legal move while every permanent route still exists. If it
  also has no legal wall action, the engine returns an empty action list and keeps
  the match running, matching the unresolved legacy situation. No pass, draw, or
  automatic loss rule has been invented; this needs a future rules decision.
- Existing visual audit findings remain untouched: `wall.gd` creates an unused
  material, and `Wall.tscn` contains a null wall-color override. Review separately
  without changing the imported ivory/walnut appearance.

Next: **v3.0-alpha.2.3 - Playable Matches**, expanding match flow and presentation.
Game modes and AI follow in alpha.3.

## Version workflow

`version_notice.txt` is authoritative for Godot releases. Every implementation patch
must update its current-version line and release entry, then synchronize
`application/config/version` in `project.godot`. The headless suite rejects mismatches
or a missing current release entry. Include completion date, features, fixes,
limitations, actual verification, and next milestone. Do not rewrite the independent
Classic history in `../pygame/version_notice.txt`.
