extends SceneTree
## Loads the real scene for synchronization, GUI, and camera projection tests.

const ControllerTests = preload("res://tests/interaction/test_human_controller.gd")
const MatchConfig = preload("res://scripts/core/match_config.gd")
const Scene = preload("res://scenes/game.tscn")

var checks = 0
var failures = 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	var controller_tests = ControllerTests.new()
	controller_tests.run()
	checks += controller_tests.checks
	failures += controller_tests.failures
	root.size = Vector2i(1280, 900)
	game = Scene.instantiate()
	game.settings_path = ""
	game.screen_transitions_enabled = false
	game.live_timing = false
	game.preferences_path = ""
	root.add_child(game)
	await process_frame
	await process_frame
	# The board regression suite isolates immediate synchronization. Match-flow
	# tests exercise the new startup menus and enabled animations separately.
	game.animations_enabled = false
	game.ui.animations_enabled = false
	game.start_match()
	game.set_volume("effects", 0.0)
	# Synthetic input uses explicit screen positions, independent of the real cursor.
	game.set_process(false)
	for method in ["test_initial_scene", "test_selection_and_move", "test_walls",
		"test_four_player_order", "test_victory_and_restart"]:
		check(game != null and call(method) == true, method + " completed")
	await test_input_events()
	await test_cameras()
	game.free()
	# Audio teardown is asynchronous; allow the mixer to drain queued play/stop requests.
	await create_timer(0.1).timeout
	print("INTERACTION TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func screen_point(square: Vector2i, height = 0.12) -> Vector2:
	var position = game.get_node("Board").cell_position(square) + Vector3(0, height, 0)
	return game.camera.unproject_position(game.get_node("Board").to_global(position))

func key_event(code: Key) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func test_initial_scene() -> bool:
	check(not game.get_node("Walls/Wall").visible, "demo wall hidden")
	check(game.placed_walls.get_child_count() == 0 and game.engine.state.walls.is_empty(), "empty match has no permanent walls")
	for player in game.engine.state.players:
		var expected = game.get_node("Board").to_global(game.get_node("Board").cell_position(player.position))
		check(game.pawn_nodes[player.id].global_position.is_equal_approx(expected), "pawn positions come from engine")
		check(is_equal_approx(game.pawn_nodes[player.id].get_node("PawnModel").position.y, 0.16), "original pawn model offset")
	check(game.get_node("Board").active_ring.visible, "active golden indicator visible")
	check(game.ui.cards[0].walls.text == "5", "inventory synchronized")
	return true

func test_selection_and_move() -> bool:
	game.set_camera_view("classic", false)
	game.click_at_screen(screen_point(Vector2i(4, 0), 0.45))
	check(not game.controller.selected, "cannot select other player through screen input")
	game.click_at_screen(screen_point(Vector2i(4, 8), 0.45))
	check(game.controller.selected, "active pawn screen selection")
	check(game.get_node("Board").move_overlays.get_child_count() == game.engine.legal_moves().size(), "legal overlay count matches engine")
	for overlay in game.get_node("Board").move_overlays.get_children():
		check(overlay.position.y > 0.12 and overlay.material_override.albedo_color.g > 0.5, "green overlays above wood")
	game.click_at_screen(screen_point(Vector2i(2, 6)))
	check(not game.controller.selected and game.get_node("Board").move_overlays.get_child_count() == 0, "illegal tile clears highlights")
	check(game.engine.state.history.is_empty(), "illegal tile changes no state")
	game.click_at_screen(screen_point(Vector2i(4, 8), 0.45))
	check(game.click_at_screen(screen_point(Vector2i(4, 7))), "screen move accepted")
	check(game.pawn_nodes[0].position.is_equal_approx(Vector3(0, 0, 3)), "3D pawn moved")
	check(game.get_node("Board").active_ring.position.is_equal_approx(Vector3(-4, 0.145, 0)), "gold indicator follows next player")
	check(game.get_node("Board").move_overlays.get_child_count() == 0, "accepted move clears highlights")
	return true

func test_walls() -> bool:
	game.restart_match()
	var point = Vector3(0.5, 0.12, 0.5)
	var screen = game.camera.unproject_position(point)
	var target = game.target_at_screen(screen)
	check(target == {"kind": "wall", "anchor": Vector2i(4, 4)}, "screen ray maps wall anchor")
	game.controller.hover(target)
	game.update_interaction_visuals()
	check(game.preview_wall.visible and game.controller.preview.valid, "visible valid preview")
	check(game.preview_wall.position.is_equal_approx(Vector3(0.5, 0, 0.5)), "preview aligned to recessed slot")
	game._unhandled_input(key_event(KEY_R))
	check(game.controller.orientation == "V", "R rotates preview")
	var right_click = InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = screen
	game._unhandled_input(right_click)
	check(game.controller.orientation == "H", "right click rotates preview")
	check(game.click_at_screen(screen), "screen wall placement")
	check(game.wall_nodes.size() == 1 and game.placed_walls.get_child_count() == 1, "one permanent wall created")
	check(not game.preview_wall.visible, "accepted wall hides ghost")
	check(game.ui.cards[0].walls.text == "4", "HUD inventory decremented")
	var permanent = game.wall_nodes[Vector3i(4, 4, 0)]
	check(permanent.position.is_equal_approx(Vector3(0.5, 0, 0.5)), "permanent wall center")
	check_mesh_materials(permanent)
	game.controller.hover({})
	game.controller.hover(target)
	game.update_interaction_visuals()
	check(game.preview_wall.visible and not game.controller.preview.valid, "duplicate has red preview")
	check(game.preview_material.albedo_color.r > game.preview_material.albedo_color.g, "invalid material red")
	var before = game.engine.state.snapshot()
	check(not game.click_at_screen(screen) and game.engine.state.snapshot() == before, "invalid wall does not change turn")
	game.controller.rotate()
	var second_screen = game.camera.unproject_position(Vector3(-1.5, 0.12, -1.5))
	check(game.click_at_screen(second_screen), "vertical wall accepted")
	check(absf(game.wall_nodes[Vector3i(2, 2, 1)].rotation.y - PI / 2) < 0.001, "vertical rotation is ninety degrees")
	game.controller.hover(game.target_at_screen(Vector2(25, 25)))
	game.update_interaction_visuals()
	check(not game.preview_wall.visible, "HUD hides wall preview")
	return true

func check_mesh_materials(node: Node) -> void:
	if node is MeshInstance3D:
		check(node.material_override == null, "permanent wall retains imported materials")
	for child in node.get_children():
		check_mesh_materials(child)

func test_four_player_order() -> bool:
	game.restart_match()
	for player in [0, 2, 1, 3]:
		check(game.engine.state.current_player == player, "four player turn order")
		var target = game.engine.legal_moves()[0]
		game.controller.click({"kind": "pawn", "player_id": player})
		check(game.controller.click({"kind": "tile", "square": target}), "each human can move")
		game.sync_scene()
		check(game.ui.cards[game.engine.state.current_player].active, "active HUD updated")
	return true

func test_victory_and_restart() -> bool:
	var config = MatchConfig.for_mode("Versus")
	config.names[0] = "Alex"
	game.start_match(config)
	check(not game.pawn_nodes[2].visible and not game.pawn_nodes[3].visible, "two player mode hides extra pawns")
	# Fixture setup belongs to tests; scene code never changes authoritative positions.
	game.engine.state.players[0].position = Vector2i(2, 1)
	game.sync_scene()
	game.controller.click({"kind": "pawn", "player_id": 0})
	check(game.controller.click({"kind": "tile", "square": Vector2i(2, 0)}), "winning move accepted")
	game.sync_scene()
	check(game.ui.winner_text.text == "ALEX WINS!", "one personalized winner notification")
	check(not game.get_node("Board").active_ring.visible, "no active ring after victory")
	var before = game.engine.state.snapshot()
	game.click_at_screen(game.camera.unproject_position(Vector3(0.5, 0.12, 0.5)))
	check(game.engine.state.snapshot() == before, "victory blocks input")
	var button = game.ui.victory_buttons[0]
	button.pressed.emit()
	check(game.engine.state.winner == -1 and game.engine.state.history.is_empty(), "restart button clears victory")
	check(game.engine.state.players[0].name == "Alex" and game.pawn_nodes[0].position == Vector3(0, 0, 4), "restart preserves name, restores board")
	check(game.wall_nodes.is_empty() and game.get_node("Board").move_overlays.get_child_count() == 0, "restart clears walls and highlights")
	return true

func mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = position
	event.global_position = position
	event.pressed = pressed
	return event

func viewport_click(position: Vector2) -> void:
	root.push_input(mouse_button(position, true), true)
	root.push_input(mouse_button(position, false), true)

func test_input_events() -> void:
	game.start_match()
	game.set_camera_view("classic", false)
	await process_frame
	viewport_click(screen_point(Vector2i(4, 8), 0.45))
	check(game.controller.selected, "viewport mouse event selects pawn")
	viewport_click(screen_point(Vector2i(4, 7)))
	check(game.engine.state.players[0].position == Vector2i(4, 7), "viewport mouse event moves pawn")
	viewport_click(game.ui.hamburger.get_global_rect().get_center())
	await process_frame
	var button = game.ui.menu.find_child("Restart", true, false)
	viewport_click(button.get_global_rect().get_center())
	check(game.engine.state.history.is_empty() and game.engine.state.current_player == 0, "GUI restart receives click without board action")
	root.push_input(key_event(KEY_R))
	check(game.controller.orientation == "V", "viewport keyboard event rotates")
	var repeated = key_event(KEY_R)
	repeated.echo = true
	root.push_input(repeated)
	check(game.controller.orientation == "V", "held key repeat does not rotate repeatedly")
	check(game.target_at_screen(Vector2(-10, 100)).is_empty(), "outside viewport has no target")

func test_cameras() -> void:
	game.start_match()
	for view in ["classic", "isometric", "cinematic"]:
		game.set_camera_view(view, false)
		await process_frame
		check(game.camera.position == game.camera_positions[view] and game.camera.size == game.camera_sizes[view], view + " original camera preset")
		for player in game.engine.state.players:
			check(game.target_at_screen(screen_point(player.position, 0.45)) == {"kind": "pawn", "player_id": player.id}, view + " pawn body targeting")
		game.click_at_screen(screen_point(Vector2i(4, 8), 0.45))
		check(game.controller.selected, view + " selection")
		check(game.click_at_screen(screen_point(Vector2i(4, 7))), view + " legal tile targeting")
		game.restart_match()
		for orientation in ["H", "V"]:
			game.controller.orientation = orientation
			var point = game.camera.unproject_position(Vector3(0.5, 0.12, 0.5))
			check(game.target_at_screen(point) == {"kind": "wall", "anchor": Vector2i(4, 4)}, view + " wall projection " + orientation)
		game.controller.orientation = "H"
	# Advance a real camera tween manually and reproject at every intermediate pose.
	game.set_camera_view("classic", false)
	game._unhandled_input(key_event(KEY_3))
	var tween = game.camera_tween
	tween.pause()
	for step in range(4):
		tween.custom_step(0.2)
		var target = game.target_at_screen(screen_point(Vector2i(4, 8), 0.45))
		check(target == {"kind": "pawn", "player_id": 0}, "pawn targeting during tween")
		game.click_at_screen(screen_point(Vector2i(4, 8), 0.45))
		check(game.click_at_screen(screen_point(Vector2i(4, 7))), "actual move during camera tween")
		game.restart_match()
		var wall_screen = game.camera.unproject_position(Vector3(0.5, 0.12, 0.5))
		game.controller.hover(game.target_at_screen(wall_screen))
		game.update_interaction_visuals()
		check(game.preview_wall.visible and game.controller.preview.valid, "wall preview during camera tween")
	check(game.camera.position.is_equal_approx(game.camera_positions.cinematic), "camera tween keeps 0.8 second duration")
	game._unhandled_input(key_event(KEY_1))
	check(game.camera_tween != tween, "camera hotkey interrupts previous tween")
	game._unhandled_input(key_event(KEY_2))
	check(game.camera_tween != null, "isometric hotkey retained")
