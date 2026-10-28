extends RefCounted

const MatchEngine = preload("res://scripts/core/game_engine.gd")
const MatchConfig = preload("res://scripts/core/match_config.gd")
const Controller = preload("res://scripts/controllers/human_controller.gd")

var checks = 0
var failures = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	for method in ["test_selection", "test_wall_targets", "test_wall_actions", "test_input_gates"]:
		check(call(method) == true, method + " completed")

func test_selection() -> bool:
	var engine = MatchEngine.new()
	var controller = Controller.new(engine)
	check(not controller.click({"kind": "pawn", "player_id": 1}) and not controller.selected, "other pawn cannot be selected")
	controller.click({"kind": "pawn", "player_id": 0})
	check(controller.selected and controller.legal_destinations() == engine.legal_moves(), "highlights come from engine")
	controller.hover({"kind": "wall", "anchor": Vector2i(3, 3)})
	check(controller.preview.is_empty(), "selection disables wall preview")
	var before = engine.state.snapshot()
	controller.click({"kind": "tile", "square": Vector2i(0, 0)})
	check(not controller.selected and engine.state.snapshot() == before, "non-highlighted tile deselects without a move")
	controller.click({"kind": "pawn", "player_id": 0})
	check(controller.click({"kind": "tile", "square": Vector2i(4, 7)}), "selected legal move accepted")
	check(engine.state.players[0].position == Vector2i(4, 7) and engine.state.current_player == 1, "move advances engine")
	check(not controller.selected and controller.legal_destinations().is_empty(), "move clears selection")
	controller.click({"kind": "pawn", "player_id": 1})
	controller.click({"kind": "pawn", "player_id": 1})
	check(not controller.selected, "click pawn again deselects")
	return true

func test_wall_targets() -> bool:
	var engine = MatchEngine.new()
	var controller = Controller.new(engine)
	for row in range(9):
		for column in range(9):
			for orientation in ["H", "V"]:
				controller.orientation = orientation
				var point = Vector3(column - 4, 0.12, row - 4)
				check(controller.target_at(point).get("kind") != "wall", "tile center never targets wall")
				# Even the wood edge inside the aiming tolerance remains a tile.
				check(controller.target_at(point + Vector3(0.43, 0, 0.43)).get("kind") != "wall", "tile edge wins over groove tolerance")
	for row in range(8):
		for column in range(8):
			for orientation in ["H", "V"]:
				controller.orientation = orientation
				var point = Vector3(column - 3.5, 0.12, row - 3.5)
				check(controller.target_at(point) == {"kind": "wall", "anchor": Vector2i(column, row)}, "every wall anchor maps exactly")
	check(controller.target_at(null).is_empty(), "ray miss hides target")
	check(controller.target_at(Vector3(5, 0, 0)).is_empty(), "frame is not playable")
	check(controller.target_at(Vector3(-4.5, 0, -4.5)).is_empty(), "outside board has no target")
	controller.orientation = "H"
	check(controller.target_at(Vector3(0.2, 0.12, 0.5)).get("kind") == "wall", "horizontal groove detected")
	controller.rotate()
	check(controller.target_at(Vector3(0.2, 0.12, 0.5)).is_empty(), "wrong groove orientation has no preview")
	return true

func test_wall_actions() -> bool:
	var engine = MatchEngine.new()
	var controller = Controller.new(engine)
	var target = {"kind": "wall", "anchor": Vector2i(3, 3)}
	controller.hover(target)
	check(controller.preview.valid, "valid green preview")
	check(controller.click(target), "wall action submitted")
	check(engine.state.players[0].walls_remaining == 9 and engine.state.current_player == 1, "wall inventory and turn updated")
	check(controller.preview.is_empty(), "successful placement hides preview")
	controller.hover(target)
	check(controller.preview.is_empty(), "preview stays hidden until cursor leaves slot")
	check(not controller.click(target) and not controller.preview.is_empty() and not controller.preview.valid, "repeated placement shows red feedback")
	controller.hover({})
	controller.hover(target)
	check(not controller.preview.valid, "duplicate preview is invalid")
	var before = engine.state.snapshot()
	var history = engine.state.history.duplicate(true)
	check(not controller.click(target), "duplicate wall rejected")
	check(engine.state.snapshot() == before and engine.state.history == history, "rejected preview changes no state")
	controller.rotate()
	controller.hover(target)
	check(controller.orientation == "V" and not controller.preview.valid, "rotation revalidates crossing")
	controller.hover({})
	check(controller.preview.is_empty(), "off-board clears preview")
	engine.state.players[1].walls_remaining = 0
	controller.hover(target)
	check(controller.preview.is_empty(), "no inventory hides preview")
	return true

func test_input_gates() -> bool:
	var engine = MatchEngine.new()
	var controller = Controller.new(engine)
	for gate in ["paused", "finished", "AI"]:
		engine.state.paused = gate == "paused"
		engine.state.status = "finished" if gate == "finished" else "running"
		engine.state.players[0].controller = "AI - Casual" if gate == "AI" else "Human"
		var before = engine.state.snapshot()
		controller.click({"kind": "pawn", "player_id": 0})
		controller.hover({"kind": "wall", "anchor": Vector2i(3, 3)})
		controller.rotate()
		check(not controller.selected and controller.preview.is_empty(), "unavailable turn blocks input: " + gate)
		check(engine.state.snapshot() == before and controller.orientation == "H", "input gate has no side effects")
	return true
