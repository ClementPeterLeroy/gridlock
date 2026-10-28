# Gridlock v3.0-alpha.2.3 - Playable Matches

Godot 4.7.2 / GDScript. Complete local human matches in Versus and Battle Royale,
with the approved Design B compact HUD. The original rules, models, materials,
lighting, and camera presets are preserved.

## Play a match

Open `project.godot` in Godot and run the project. Choose a mode in the main menu,
then confirm Start Match in setup. Versus uses Sapphire/Crimson and ten walls each.
Battle Royale uses four local humans, five walls each, and clockwise turns:
Sapphire, Emerald, Crimson, Violet. No AI or Blitz option is exposed yet.

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
- Top-right cards display colored identity dots, names, wall icons/counts, and
  elapsed turn times. The active card has a thin golden border, matching the
  golden ring on the board. Cards wrap into two columns in narrow logical viewports.
- The top-left hamburger opens Settings, Pause/Resume, Restart Match, and Main Menu.
  While expanded, it blocks board input. Opening it alone does not pause the timer;
  choose Pause to freeze the match. No large instruction panel obscures the board.
- Esc deselects a selected pawn, closes the hamburger, or otherwise pauses/resumes.
  The pause page offers Resume, Restart Match, and Main Menu. Cameras remain available.
- Victory preserves the final board behind the existing color-specific trophy
  artwork. A single dynamic banner identifies the winner; the two buttons are
  Play Again and Main Menu. Play Again preserves the match configuration.
- Restart Match or N starts a fresh board with the same configuration and resets
  every elapsed timer. N is available during play, pause, and victory.

The active player's elapsed timer advances only during playable turn time.
Incoming players start a fresh timer; inactive cards retain their last turn time.
Pause, in-match Settings, gameplay transitions, main-menu pages, and victory stop
timer advancement. There are no countdowns, penalties, or timeouts.

Pawn movement takes 0.22 seconds, wall settling 0.20 seconds, and the golden
highlight transition 0.24 seconds. The engine accepts an action immediately; only
the scene is interpolated. Conflicting gameplay input is blocked until completion.
Pause freezes a pending transition; restart/main-menu navigation cancels it safely.
Settings can disable animations immediately, snapping to the authoritative state.

Settings provides Music and Sound Effects volume sliders plus Animations On/Off.
Changes persist for the application session. Music loops quietly across screens
and matches. Movement, wall placement, and victory reuse Classic placeholder audio;
the wall effect is the move recording at a lower pitch. Audio is not final.
The Dummy audio backend stays silent during headless runs or when no device is
available; resource, volume, and sound-event tests still run without a speaker.

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

`scripts/ui/match_interface.gd` owns the compact HUD and modal pages, emitting user
intent to `game.gd`. Modal pages, menu expansion, HUD hit regions, and transition
locks block board input. `game.gd` owns session timing and presentation tweens;
`scripts/match_audio.gd` owns persistent music and effect players. Reused audio,
stickers, and the licensed Cinzel font live inside the project for portable imports
and exports. See [asset provenance](assets/ASSETS.md).

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

`set_paused(bool)` changes the engine's existing pause flag through an explicit
API and rejects finished matches. Rule validation and state transitions are otherwise
unchanged. Elapsed presentation clocks live in the application, separately from
future countdown/Blitz rules; alpha.2.3 does not expose an Undo UI for these clocks.

`forfeit(player_id)` provides the existing timeout-removal transition: remove the
active pawn, keep placed walls, skip the seat, and declare the final survivor.
It does not run a clock or introduce a new player-facing surrender control.

## Tests

From the repository root, substitute your installed executable for `godot` if needed:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
godot --headless --path godot --script res://tests/run_interaction_tests.gd
godot --headless --path godot --script res://tests/run_match_tests.gd
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

The new match suite exercises actual menu/button input, both setup modes, compact
cards, timer reset/freeze, pause and settings, animation interruption, sound-event
ordering, all four victory stickers, responsive layouts, and complete opening-to-win
matches with replay. Existing board regression checks run with animations disabled
to isolate targeting/synchronization; match tests also verify enabled transitions.

Validation for alpha.2.3: 3359 core checks, 602 interaction checks, and 232 match
checks passed on Godot 4.7.2. Python parity fixtures matched the unchanged Classic
implementation. The Pygame suite passed all 100 tests on Python 3.13.12 / Pygame 2.6.1.
Actual D3D12/Forward+ captures were inspected for gameplay, menus, pause/settings,
and the personalized victory overlay, including an 800 x 600 window.

Manual verification before wider release:

1. In each camera view, select a pawn, move, deselect on an unrelated tile, and
   confirm the golden ring, active card, elapsed timer, and inventory update.
2. Aim along board-edge and central grooves, rotate with R and right-click, and
   place both orientations. Try an overlapping/crossing wall and confirm red feedback.
3. Move the cursor over the HUD and outside the board; previews must disappear.
   Switch cameras with the cursor stationary and click during a transition.
4. Run full human matches in Versus and Battle Royale. Pause during a pawn/wall
   transition, resume, restart, and return to the menu. Check clocks stay frozen
   behind overlays and the final position survives victory presentation.
5. Listen to music and all three effects, test both sliders including zero, and
   toggle animations during a transition. Confirm music continues across pages.
6. Resize the window, check cards and victory controls remain usable, and replay
   with both the victory buttons and N at your normal display resolution.

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
- Countdown turn limits and Blitz options remain engine configuration metadata;
  their clocks and penalties do not execute. Only elapsed timers run in this patch.
- Match customization, persistent Godot preferences, replay storage, records, and
  the broader UI/texture polish remain deferred. Settings are session-only.
- Audio remains placeholder material, including the reused wall sound. Auditory
  quality and long human play sessions need manual verification.
- A pawn can have no legal move while every permanent route still exists. If it
  also has no legal wall action, the engine returns an empty action list and keeps
  the match running, matching the unresolved legacy situation. No pass, draw, or
  automatic loss rule has been invented; this needs a future rules decision.
- Existing visual audit findings remain untouched: `wall.gd` creates an unused
  material, and `Wall.tscn` contains a null wall-color override. Review separately
  without changing the imported ivory/walnut appearance.

Next: **v3.0-alpha.3 - Game Modes & AI**.

## Version workflow

`version_notice.txt` is authoritative for Godot releases. Every implementation patch
must update its current-version line and release entry, then synchronize
`application/config/version` in `project.godot`. The headless suite rejects mismatches
or a missing current release entry. Include completion date, features, fixes,
limitations, actual verification, and next milestone. Do not rewrite the independent
Classic history in `../pygame/version_notice.txt`.
