# Gridlock v3.0-alpha.3.3 - Match Customization

Godot 4.7.2 / GDScript. Human and Pathfinder AI matches in Versus, Battle Royale, and Blitz,
with the approved Design B compact HUD. The original rules, models, materials,
lighting, and camera presets are preserved.

## Play a match

Open `project.godot` in Godot and run the project. Choose a mode in the main menu,
then select each seat's controller and confirm Start Match. Each seat independently
offers Human, AI - Casual, or AI - Challenging, including fully automated matches.
The default is all Human. Versus uses Sapphire/Crimson and ten walls each.
Battle Royale uses four players, five walls each, and clockwise turns:
Sapphire, Emerald, Crimson, Violet. Every seat, including AI, accepts a custom name
of up to twelve printable characters. Empty names block Start; control characters
and markup delimiters are filtered. Duplicate names are allowed: IDs, color dots,
and identity tooltips distinguish seats. Controller changes never rename a seat.

Versus is always untimed, including when obsolete countdown preferences are loaded.
Battle Royale offers exactly one timing system:

- Per Turn: 15/30/60/120/180 seconds, default 30 seconds, reset for each turn.
- Per Game: 1/3/5/10/15 minutes per seat, default three minutes, retained across turns.

The timer dropdown remembers each type's preferred duration independently. Per Game
zero balance eliminates the pawn and retains placed walls, like Per Turn expiry.
Battle Royale never grants Blitz's minimum time, wall penalties, or overtime.
Blitz retains 1/3/5-minute clocks, default three minutes, with two players and ten walls.

Starting player offers Default (Sapphire) and Random (uniform participating-seat draw).
Start Match draws a starter when Random is selected. Restart Match / N restores the
same chosen starter, names/controllers, clocks and inventories. Play Again preserves
configuration and draws a fresh starter when Random is selected. Cyclic turn order
and starting positions never change.

Setup preferences persist per mode in `user://match_preferences.cfg`, using Godot's
local user-data directory. Names, controllers/difficulties, random-start preference,
both Battle Royale durations, and Blitz duration are saved after valid Start or
leaving setup. Reset to Defaults restores all mode preferences without restarting
an active match. Audio and animation settings remain session-only.

`scripts/core/match_preferences.gd` uses ConfigFile and repairs missing/invalid
fields to safe defaults; older timed Versus and unsupported duration values cannot
restore removed behavior. There was no previous persistent Godot match file to
migrate; compatible older field values are accepted. Actual starter draws, board
positions, clocks, history and results are never stored as setup preferences.
Disk failures leave current session choices available and emit a warning.

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
  elapsed times, turn countdowns, or Blitz clocks with an OT prefix for overtime.
  Countdown text turns amber at ten seconds and red at five. The active card has
  a thin golden border, matching the
  golden ring on the board. Cards wrap into two columns in narrow logical viewports.
- The top-left hamburger opens Settings, Pause/Resume, Restart Match, and Main Menu.
  While expanded, it blocks board input. Opening it alone does not pause the timer;
  choose Pause to freeze the match. No large instruction panel obscures the board.
- Esc deselects a selected pawn, closes the hamburger, or otherwise pauses/resumes.
  The pause page offers Resume, Restart Match, and Main Menu. Cameras remain available.
- Victory preserves the final board behind the existing color-specific trophy
  artwork. A single dynamic banner identifies the winner; the two buttons are
  Play Again and Main Menu. Play Again preserves configuration and redraws Random.
- Restart Match or N starts a fresh board with the same configuration and resets
  all clocks. N is available during play, pause, and victory.

All timing comes from the authoritative engine. Pause, in-match Settings, gameplay
transitions, main-menu pages, and victory freeze clocks. Untimed cards retain each
seat's last elapsed turn time; incoming turns reset elapsed/countdown turn time.
Standard timeout removes the active pawn, preserves its placed walls and stable ID,
skips it in rotation, and awards victory to the final survivor. A timeout victory
names the losing player below the existing sticker.

Blitz clock consumption and penalties follow `../pygame/game.py` exactly:

- At turn start, raise that player's clock to ten seconds only if it is lower.
  There is no continuously enforced floor and no time added above ten seconds.
- Running out of main time consumes one inventory wall and starts a fresh
  15-second overtime period for that turn. This does not place a wall on the board.
- Only one penalty is allowed per turn. Expiring overtime loses immediately;
  expiring main time with no walls also loses. Making a move or placing a legal
  wall ends overtime; another penalty is possible on a later turn.
- A large tick reaching zero starts a full 15 seconds; excess delta is discarded,
  matching Classic. Tick-driven Blitz penalties/losses do not add undo snapshots;
  undo restores the last action snapshot, including its clocks and inventory.
- AI elapsed time starts immediately. Countdown charging exempts the first second
  of each decision, then charges thinking to that AI's clock. A wall penalty changes
  the decision position and restarts this exemption, as in Classic's UI scheduler.
  Human turns have no exemption; inactive clocks never consume another seat's time.

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
locks block board input. `game.gd` owns presentation tweens and clock suspension;
the engine owns clock values and timing decisions, and the HUD only reads them.
`scripts/match_audio.gd` owns persistent music and effect players. Reused audio,
stickers, and the licensed Cinzel font live inside the project for portable imports
and exports. See [asset provenance](assets/ASSETS.md).

`board.gd` maps cells/wall anchors into existing model coordinates and adds separate
translucent green planes and a golden ring. Original tile and pawn materials are
not replaced. Preview walls use instance-only overrides; permanent walls retain
their imported ivory/walnut materials. Pawn model offsets are preserved.

## Pathfinder AI

`scripts/ai/pathfinder.gd` incrementally evaluates a private copy of the match.
It ports Classic's BFS route heuristic: take immediate wins, penalize opponents'
winning threats, compare movement with useful walls, and conserve walls when ahead.
All surviving opponents matter. Casual adds move noise and usually considers fewer
walls; Challenging checks the complete candidate list. This is the existing shallow
heuristic, with no minimax or neural network.

`scripts/ai/ai_controller.gd` schedules candidates on the main thread, targeting
4 ms of work per update. This is a cooperative budget checked between candidates,
so a single candidate or OS scheduling can exceed it. Search stops at approximately
the lesser of 10 seconds and the starting remaining clock, retaining a legal
fallback. The minimum one-second presentation delay overlaps search; neither search
nor delay advances while paused.
Edit `presentation_delay`, `thinking_limit`, or the `update()` frame-budget argument
in this controller for experiments (the search clamps its limit to ten seconds).
The countdown exemption is separately defined by the engine's
`AI_PRESENTATION_DELAY`, fixed at one second to match Classic timing rules.

Every chosen action goes through `GameEngine.apply_action()` and the same animation
and sound path as human input. Restart, navigation, and victory cancel pending work;
position changes, elimination, and undo invalidate snapshots. Rejected proposals
and positions with no legal action stop retrying and display feedback. A thinking
message appears in the existing feedback area; card tooltips include controller
and difficulty without expanding the compact cards. Cameras remain usable.

## Core modules

All six scripts in `scripts/core/` extend `RefCounted`:

| Script | Responsibility |
| --- | --- |
| `match_config.gd` | Mode, names, controllers, starting player, timing options |
| `match_preferences.gd` | Validated local setup preferences, independent of live state |
| `game_state.gd` | Stable player records, board, turns, clocks, overtime, snapshots |
| `game_engine.gd` | Validated actions, timing/timeout rules, turns, victory, restart, undo |
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
Human and AI names use printable-character filtering and a twelve-character limit.
Names are presentation only; no movement, wall, timing, or AI logic uses them as IDs.

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
`orientation: "H"` or `"V"`. Pure validation leaves state untouched. Action submission
settles live time first: a rejected proposal cannot spend inventory, but real elapsed
time can legitimately trigger a penalty/timeout. Controllers never change live state.

`legal_moves()` returns current destinations. `legal_actions()` returns all legal
move/wall proposals. Both return no actions while paused or after victory.
Queries do not change the match. Always revalidate when committing a proposal.

Stable result codes are `ok`, `invalid_config`, `invalid_name`, `invalid_action`,
`not_active_player`, `player_eliminated`, `match_paused`, `match_finished`,
`illegal_move`, `no_walls_remaining`, `wall_outside_board`,
`wall_overlap_or_crossing`, `wall_overlap`, `path_blocked`, and `nothing_to_undo`.

`start_match(config)` validates configuration before replacing state. Construct an
engine with a valid config; for untrusted configuration, construct the default
engine first and inspect the result of `start_match(config)`.
`restart()` preserves configuration and the actual chosen starter.
`play_again()` preserves configuration and rerolls a random starter when enabled.
An optional `RandomNumberGenerator` constructor argument makes starting-player tests
deterministic. The default fixed starter is Sapphire; `starting_player` permits
an explicitly configured seat. The resolved live config records the actual starter.

Setup edits one MatchConfig draft. Preferences hold independent copies, and the
engine resolves a copy before validation: Versus disables both clock limits; Battle
Royale disables its unselected limit. `timing_mode` derives from mode/type, so there
is no separate UI clock policy. Saved setup copies retain each timer type's preferred
duration; resolved live configs contain only the selected active deadline.

`state.snapshot()` deep-copies configuration and live position data, excluding
history to avoid recursive copies. `state.restore(snapshot)` also copies its input.
The engine records a snapshot before each accepted move, wall, or forfeit.
`undo()` restores that position while retaining the current pause state.
It undoes one action; future human/AI controllers may group multiple undo operations.

`set_paused(bool)` settles active time, changes the engine pause flag, and reanchors
the live clock on resume. It rejects finished matches. There is no player-facing
Undo button yet; engine undo restores clock snapshots and preserves current pause.

`forfeit(player_id)` provides the existing timeout-removal transition: remove the
active pawn, keep placed walls, skip the seat, and declare the final survivor.
Standard turn expiry invokes this same removal transition. Blitz timeout instead
awards victory without removing the pawn, matching Classic.

Before alpha.3.2, Godot kept elapsed timers in `game.gd`; countdown options were
metadata and no clock penalties ran. Classic already owned elapsed time, chargeable
time, Blitz clocks, penalties/overtime, and history in its model, with AI exemption
calculated by its UI. Godot now owns these rules and AI charging in the engine.

Use `engine.tick(seconds, clock_seconds = null)` for deterministic simulation.
Elapsed and chargeable time are separate; passing an explicit charge reproduces
Classic's `Game.tick()`. With no explicit charge, the engine applies the Classic
AI exemption automatically. Live games install `set_time_source(callable)` with
`Time.get_ticks_usec() / 1000000.0`; `poll_time()` advances from monotonic seconds.
Choose one driver for a match. The engine polls before action submission and pause,
so expiry wins over an action at the exact deadline. A goal accepted earlier freezes
all clocks. One tick resolves only the old seat, discarding excess time rather than
charging a newly active player. `set_timing_active(false)` suspends clock charging
during presentation transitions; it does not introduce a gameplay pause rule.

Snapshots include elapsed values, player clocks, penalty/overtime, and timeout
feedback. Restart and undo reanchor the live source so stale wall-clock intervals
are discarded. Undo starts a fresh AI decision/exemption, matching Classic's UI
invalidation; it retains Godot's pre-existing pause-preserving undo behavior.

## Tests

From the repository root, substitute your installed executable for `godot` if needed:

```powershell
godot --headless --path godot --script res://tests/run_core_tests.gd
godot --headless --path godot --script res://tests/run_interaction_tests.gd
godot --headless --path godot --script res://tests/run_match_tests.gd
godot --headless --path godot --script res://tests/run_ai_tests.gd
godot --headless --path godot --script res://tests/run_timing_tests.gd
godot --headless --path godot --script res://tests/run_customization_tests.gd
python -B godot/tests/generate_python_fixtures.py --check
python -B godot/tests/generate_ai_fixtures.py --check
python -B godot/tests/generate_timing_fixtures.py --check
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

Validation for alpha.3.3: 3367 core checks, 602 interaction checks, 232 match checks,
1736 AI checks, 2423 timing checks, and 575 customization checks passed on Godot 4.7.2. Python parity fixtures
matched the unchanged Classic implementation. The Pygame suite passed all 100 tests on Python 3.13.12 /
Pygame 2.6.1.
The AI suite includes 12 complete automated matches (both modes, both difficulties
and mixed levels, two seeds), 842 decisions, all 90 controller combinations,
engine rejection, pause, restart, cancellation, undo, elimination, and safe handling
of no-action positions. Full-match timing excludes presentation and animation waits.
The timing suite retains all 25 Classic traces / 163 states: elapsed/countdown
time, all turn limits and Blitz clock choices, minimum time, repeated penalties,
overtime, elimination, pause/resume, undo, and goal freeze. Historical timed Versus
traces now run through the existing two-player countdown engine mode (Rise of the
Machines); current Versus is tested separately as untimed. Fixtures and Blitz rules
are unchanged. This intentional product change is not a claim of timed Versus parity.
Fake monotonic clocks
test action/timeout ordering, AI charging and cancellation, and restart/undo anchors.
Scene checks exercise setup, countdown colors, overtime, timeout victory, and lifecycle
freeze. No real-time sleeps are used for timing assertions. D3D12/Forward+ captures
were inspected for timed four-seat setup at 800 x 600 and Blitz setup, overtime,
and timeout victory at 1280 x 900. Alpha.3.3 captures additionally cover custom setup
at 1280 x 900, 800 x 600 and 640 x 480, Per Game HUD and long-name victory.

The customization suite checks name validation/duplicates, every seat's identities,
controller choices, seeded starter selection/restart/replay, every duration preset,
Per Game accumulation/undo/elimination, timer exclusivity, saved duration switching,
invalid/older preference repair, reset, and live-state isolation. File round trips
use an isolated `.godot/` test path; separate Godot processes also verified a saved
configuration reload. Production storage uses the Godot user-data path above.

`tests/core/python_timing_parity.json` is generated by the unchanged Classic
`Game` model. Regenerate with `python -B godot/tests/generate_timing_fixtures.py`.
All representative timing states and action acceptance match; the live Godot
monotonic adapter and restrained HUD countdown colors are integration additions.

`tests/ai/python_ai_parity.json` adds 48 decisions from the unchanged Classic
Pathfinder: openings, every identity's immediate win, threats from each other seat,
jumps, wall fallback, empty inventories, eliminated players, and zero budgets.
All match with a shared deterministic policy (no shuffle, zero noise, random=0.1).
Runtime trajectories differ because Python uses MT randomization and Godot uses
PCG; equal numeric seeds do not imply equal moves. Cooperative deadlines can also
truncate search at different candidates. Heuristic weights and stable wall ties
are preserved. Regenerate with `python -B godot/tests/generate_ai_fixtures.py`.

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
7. Try Human/AI, AI/Human, AI/AI, and mixed four-player seats with both difficulties.
   While an AI thinks, switch cameras, open Settings, pause/resume, restart, and
   return to the menu. Confirm no stale move executes and replay retains controllers.
8. Try each turn limit and Blitz clock choice. Let main time expire, act during
   overtime, return to that seat, and check the ten-second minimum and repeated
   penalty. Let overtime expire and check the named loser and replay. In Battle
   Royale, time out multiple seats and confirm their placed walls remain.
9. Pause/open Settings during a low clock and an AI turn, wait, then resume.
   Check clocks and AI stay frozen behind overlays, and animations consume no time.
10. Edit human/AI names, switch controllers, try blank/duplicate/long names, and
    check HUD/victory text. Select Random, compare Restart with Play Again, then
    close/reopen the application to check preferences. Switch Battle Royale timer
    types and verify both duration choices return. Reset all defaults.

`tests/core/python_parity.json` is generated from the unchanged Pygame rules/state
and BFS distance implementation. It covers 20 reference positions, all 128 wall
candidates per position, all players' legal moves/distances, and two deterministic
32-action match traces. The fixtures use column/row coordinates explicitly.

To deliberately regenerate after an approved reference change:

```powershell
python -B godot/tests/generate_python_fixtures.py
```

## Limitations and next milestones

- Replay storage, records, and broader UI/texture polish remain deferred. Match
  preferences persist; audio/animation settings remain session-only.
- Audio remains placeholder material, including the reused wall sound. Auditory
  quality and long human play sessions need manual verification.
- A pawn can have no legal move while every permanent route still exists. If it
  also has no legal wall action, the engine returns an empty action list and keeps
  the match running, matching the unresolved legacy situation. No pass, draw, or
  automatic loss rule has been invented. Configured timeouts can resolve this
  situation; untimed matches still need a future rules decision.
- Existing visual audit findings remain untouched: `wall.gd` creates an unused
  material, and `Wall.tscn` contains a null wall-color override. Review separately
  without changing the imported ivory/walnut appearance.

Next: **v3.0-beta.1 - UI & Menu Polish**. Record for that milestone: hide the 3D
board on Main Menu and Match Setup; keep it visible in active, paused and completed
matches. This board-visibility change is deliberately not implemented in alpha.3.3.
Neural AI remains reserved for v3.1.

## Version workflow

`version_notice.txt` is authoritative for Godot releases. Every implementation patch
must update its current-version line and release entry, then synchronize
`application/config/version` in `project.godot`. The headless suite rejects mismatches
or a missing current release entry. Include completion date, features, fixes,
limitations, actual verification, and next milestone. Do not rewrite the independent
Classic history in `../pygame/version_notice.txt`.
