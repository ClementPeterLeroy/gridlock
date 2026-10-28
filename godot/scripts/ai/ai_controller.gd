extends RefCounted
## Pause-aware main-thread scheduling. No scene nodes, threads, or physics access.

const Pathfinder = preload("res://scripts/ai/pathfinder.gd")

var engine
var rng = RandomNumberGenerator.new()
var presentation_delay = 1.0
var thinking_limit = 10.0
var search
var token: Array = []
var age = 0.0
var blocked = false
var feedback = ""
var last_frame_us = 0
var max_frame_us = 0

func _init(match_engine, random_source = null) -> void:
	engine = match_engine
	if random_source == null:
		rng.randomize()
	else:
		rng = random_source

func is_ai_turn() -> bool:
	return engine.state.status == "running" \
		and engine.state.players[engine.state.current_player].controller != "Human"

func position_token() -> Array:
	var left: Array = []
	for player in engine.state.players:
		left.append(player.walls_remaining)
	return [engine.state.get_instance_id(), engine.state.current_player, engine.state.turn_number,
		engine.state.pawn_positions(), engine.state.walls.duplicate(), left,
		engine.state.active_players(), engine.state.history.size(), engine.state.status,
		engine.state.players[engine.state.current_player].controller]

func cancel() -> void:
	if search != null:
		search.cancel()
	search = null
	token = []
	age = 0.0
	blocked = false
	feedback = ""

func thinking() -> bool:
	return is_ai_turn() and not blocked

func update(delta: float, frame_budget_ms: float = 4.0) -> Dictionary:
	if engine.state.paused:
		return {}
	if not is_ai_turn():
		cancel()
		return {}
	var current = position_token()
	if token != current:
		cancel()
		token = current
		var level: String = engine.state.players[engine.state.current_player].controller.trim_prefix("AI - ")
		search = Pathfinder.new(engine.state, level, rng, thinking_limit)
	if blocked:
		return {}
	age += maxf(0.0, delta)
	var started = Time.get_ticks_usec()
	var deadline = started + maxi(1, int(frame_budget_ms * 1000.0))
	while not search.done and Time.get_ticks_usec() < deadline:
		search.step(age)
	last_frame_us = Time.get_ticks_usec() - started
	max_frame_us = maxi(max_frame_us, last_frame_us)
	if not search.done or age < presentation_delay:
		return {}
	# Every proposal is revalidated at execution. A rejection/no-action latches until
	# the position changes, avoiding an infinite retry loop on unsupported positions.
	blocked = true
	if search.best_action.is_empty():
		feedback = "No legal AI action available."
		return {}
	var action = search.best_action.duplicate()
	var outcome = engine.apply_action(action)
	outcome["action"] = action
	if not outcome.accepted:
		feedback = "AI action rejected: " + outcome.reason_code.replace("_", " ")
	else:
		# Undo may restore exactly the position used by this search. It still
		# needs a fresh decision rather than retaining the executed-action latch.
		token = []
	return outcome
