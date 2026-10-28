extends RefCounted
## Selection and board targeting only. All legal actions come from the engine.

const TILE_HALF_WIDTH = 0.44
const BOARD_EDGE = 4.44
const SLOT_TOLERANCE = 0.085

var engine
var selected = false
var orientation = "H"
var preview: Dictionary = {}
var feedback = ""
var suppressed_target: Dictionary = {}

func _init(match_engine) -> void:
	engine = match_engine

func available() -> bool:
	return engine.state.status == "running" and not engine.state.paused \
		and engine.state.players[engine.state.current_player].controller == "Human"

func clear_selection() -> void:
	selected = false
	preview = {}

func legal_destinations() -> Array:
	return engine.legal_moves() if selected and available() else []

func target_at(point: Variant) -> Dictionary:
	if point == null or absf(point.x) > BOARD_EDGE or absf(point.z) > BOARD_EDGE:
		return {}
	var grid = Vector2(point.x + 4.0, point.z + 4.0)
	var square = Vector2i(roundi(grid.x), roundi(grid.y))
	# Tile interiors always win over groove tolerance: tile clicks cannot place walls.
	if square.x >= 0 and square.x < 9 and square.y >= 0 and square.y < 9 \
		and absf(grid.x - square.x) <= TILE_HALF_WIDTH \
		and absf(grid.y - square.y) <= TILE_HALF_WIDTH:
		for player in engine.state.players:
			if player.position == square:
				return {"kind": "pawn", "player_id": player.id}
		return {"kind": "tile", "square": square}
	var anchor: Vector2i
	if orientation == "H":
		anchor = Vector2i(clampi(floori(grid.x), 0, 7), roundi(grid.y - 0.5))
		if absf(grid.y - anchor.y - 0.5) > SLOT_TOLERANCE:
			return {}
	else:
		anchor = Vector2i(roundi(grid.x - 0.5), clampi(floori(grid.y), 0, 7))
		if absf(grid.x - anchor.x - 0.5) > SLOT_TOLERANCE:
			return {}
	if anchor.x < 0 or anchor.x > 7 or anchor.y < 0 or anchor.y > 7:
		return {}
	return {"kind": "wall", "anchor": anchor}

func hover(target: Dictionary) -> void:
	preview = {}
	if target != suppressed_target:
		suppressed_target = {}
	if not available() or selected or target.is_empty() or target == suppressed_target:
		return
	if target.kind != "wall" or engine.state.players[engine.state.current_player].walls_remaining <= 0:
		return
	var action = wall_action(target.anchor)
	var outcome = engine.validate_action(action)
	preview = {"anchor": target.anchor, "orientation": orientation,
		"valid": outcome.accepted, "reason_code": outcome.reason_code}

func rotate() -> void:
	if not available():
		return
	orientation = "V" if orientation == "H" else "H"
	preview = {}
	suppressed_target = {}

func click(target: Dictionary) -> bool:
	if not available():
		clear_selection()
		return false
	feedback = ""
	if target.is_empty():
		clear_selection()
		return false
	if target.kind == "pawn":
		selected = not selected if target.player_id == engine.state.current_player else false
		preview = {}
		return false
	if selected:
		if target.kind == "tile":
			var destination = target.square
			var legal = engine.legal_moves()
			clear_selection()
			if destination in legal:
				return submit({"kind": "move", "player_id": engine.state.current_player,
					"destination": destination})
		return false
	if target.kind == "wall":
		var accepted = submit(wall_action(target.anchor))
		if accepted:
			suppressed_target = target.duplicate()
		else:
			suppressed_target = {}
			hover(target)
		return accepted
	return false

func wall_action(anchor: Vector2i) -> Dictionary:
	return {"kind": "wall", "player_id": engine.state.current_player,
		"anchor": anchor, "orientation": orientation}

func submit(action: Dictionary) -> bool:
	var outcome = engine.apply_action(action)
	if outcome.accepted:
		clear_selection()
	else:
		feedback = outcome.reason_code
	return outcome.accepted
