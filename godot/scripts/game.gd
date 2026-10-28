extends Node3D

const MatchConfig = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")
const HumanController = preload("res://scripts/controllers/human_controller.gd")
const MatchInterface = preload("res://scripts/ui/match_interface.gd")
const MatchAudio = preload("res://scripts/match_audio.gd")
const WallScene = preload("res://scenes/Wall.tscn")

@export_enum("Versus", "Battle Royale") var board_mode: String = "Battle Royale"
@onready var camera: Camera3D = $Camera3D

var camera_positions = {
	"classic": Vector3(0, 18, 3),
	"isometric": Vector3(11, 13, 11),
	"cinematic": Vector3(10, 7, 12)
}
var camera_sizes = {"classic": 13.5, "isometric": 15.0, "cinematic": 17.0}
var camera_tween: Tween

var engine
var controller
var ui
var audio
var pawn_nodes: Array[Node3D] = []
var wall_nodes: Dictionary = {}
var placed_walls: Node3D
var preview_wall: Node3D
var preview_material: StandardMaterial3D
var shown_moves: Array = []
var scene_turn: Array = []
var view = "main_menu"
var setup_mode = "Versus"
var settings_return = "main_menu"
var elapsed_turns: Array = []
var clock_player = -1
var animations_enabled = true
var animation_busy = false
var gameplay_tween: Tween
var victory_shown = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	set_camera_view("isometric", false)
	for identity in MatchConfig.IDENTITIES:
		pawn_nodes.append(get_node("Pieces/" + identity + "Pawn"))
	$Walls/Wall.hide()
	placed_walls = Node3D.new()
	placed_walls.name = "PlacedWalls"
	$Walls.add_child(placed_walls)
	create_preview()
	ui = MatchInterface.new()
	add_child(ui)
	ui.action_requested.connect(handle_ui_action)
	ui.volume_changed.connect(set_volume)
	ui.animations_changed.connect(set_animations)
	audio = MatchAudio.new()
	add_child(audio)
	start_match()
	show_main_menu()

func start_match(options = null) -> void:
	cancel_transition()
	if options == null:
		options = MatchConfig.for_mode(board_mode)
		options.controllers.fill("Human")
	engine = MatchEngine.new(options)
	controller = HumanController.new(engine)
	reset_match_presentation()

func reset_match_presentation() -> void:
	elapsed_turns = []
	elapsed_turns.resize(engine.state.players.size())
	elapsed_turns.fill(0.0)
	clock_player = engine.state.current_player
	victory_shown = false
	view = "game"
	ui.has_match = true
	ui.animations_enabled = animations_enabled
	ui.build_cards(engine.state)
	ui.show_page("game")
	sync_scene()

func restart_match() -> void:
	cancel_transition()
	engine.restart()
	controller.clear_selection()
	controller.feedback = ""
	controller.suppressed_target = {}
	reset_match_presentation()

func sync_scene(animate: bool = false) -> void:
	if not animate:
		cancel_transition()
	controller.clear_selection()
	if clock_player != engine.state.current_player:
		clock_player = engine.state.current_player
		elapsed_turns[clock_player] = 0.0
	var tween: Tween = null
	if animate and animations_enabled:
		tween = create_tween().set_parallel(true)
		gameplay_tween = tween
		animation_busy = true
	for player_id in range(pawn_nodes.size()):
		var pawn = pawn_nodes[player_id]
		pawn.visible = player_id < engine.state.players.size() and engine.state.players[player_id].position != null
		if pawn.visible:
			var target = $Board.to_global($Board.cell_position(engine.state.players[player_id].position))
			if tween != null and not pawn.global_position.is_equal_approx(target):
				tween.tween_property(pawn, "global_position", target, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			else:
				pawn.global_position = target
	for key in wall_nodes.keys():
		if not engine.state.walls.has(key):
			wall_nodes[key].free()
			wall_nodes.erase(key)
	for key in engine.state.walls:
		if not wall_nodes.has(key):
			var wall = WallScene.instantiate()
			placed_walls.add_child(wall)
			position_wall(wall, Vector2i(key.x, key.y), "H" if key.z == 0 else "V")
			wall_nodes[key] = wall
			if tween != null:
				var target = wall.position
				wall.position.y += 0.14
				tween.tween_property(wall, "position", target, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var ring = $Board.active_ring
	var old_position: Vector3 = ring.position
	var active = engine.state.players[engine.state.current_player].position
	$Board.show_active_player(active if engine.state.status == "running" else null)
	if tween != null:
		var target_position: Vector3 = ring.position
		tween.tween_method(func(weight: float):
			ring.transparency = 1.0 - absf(2.0 * weight - 1.0)
			ring.position = old_position if weight < 0.5 else target_position,
			0.0, 1.0, 0.24)
		tween.finished.connect(finish_transition)
	else:
		ring.transparency = 0.0
	scene_turn = turn_token()
	update_interaction_visuals()
	update_hud()
	if not animation_busy:
		present_victory()

func cancel_transition() -> void:
	if gameplay_tween != null and gameplay_tween.is_valid():
		gameplay_tween.kill()
	gameplay_tween = null
	animation_busy = false

func finish_transition() -> void:
	animation_busy = false
	gameplay_tween = null
	present_victory()

func present_victory() -> void:
	if engine.state.winner < 0 or victory_shown or view != "game":
		return
	victory_shown = true
	view = "victory"
	controller.clear_selection()
	update_interaction_visuals()
	ui.show_page("victory", engine.state)
	audio.play_effect("victory")

func turn_token() -> Array:
	return [engine.state.current_player, engine.state.turn_number, engine.state.status]

func position_wall(wall: Node3D, anchor: Vector2i, orientation: String) -> void:
	wall.global_transform = $Board.global_transform
	wall.position = wall.get_parent().to_local($Board.to_global($Board.wall_position(anchor)))
	wall.rotate_object_local(Vector3.UP, PI / 2.0 if orientation == "V" else 0.0)

func create_preview() -> void:
	preview_wall = WallScene.instantiate()
	preview_wall.name = "WallPreview"
	add_child(preview_wall)
	preview_material = $Board.overlay_material(Color(0.35, 0.85, 0.55, 0.4))
	preview_material.no_depth_test = true
	apply_preview_material(preview_wall)
	preview_wall.hide()

func apply_preview_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		apply_preview_material(child)

func _process(delta: float) -> void:
	if controller == null:
		return
	if scene_turn != turn_token():
		sync_scene()
	update_elapsed(delta)
	controller.hover(target_at_screen(get_viewport().get_mouse_position()))
	update_interaction_visuals()
	update_hud()
	if not animation_busy:
		present_victory()

func update_elapsed(delta: float) -> void:
	if view == "game" and engine.state.status == "running" and not engine.state.paused and not animation_busy:
		elapsed_turns[engine.state.current_player] += maxf(0.0, delta)

func can_interact() -> bool:
	return controller != null and view == "game" and not ui.menu.visible and not animation_busy and controller.available()

func target_at_screen(screen_position: Vector2) -> Dictionary:
	if not can_interact() or not get_viewport().get_visible_rect().has_point(screen_position) or ui.blocks_board(screen_position):
		return {}
	var origin = $Board.to_local(camera.project_ray_origin(screen_position))
	var direction = $Board.global_basis.inverse() * camera.project_ray_normal(screen_position)
	var closest = INF
	var hit_player = -1
	for player in engine.state.players:
		if player.position == null:
			continue
		var base = $Board.cell_position(player.position)
		var bounds = AABB(base + Vector3(-0.23, 0.16, -0.23), Vector3(0.46, 0.57, 0.46))
		var hit = bounds.intersects_ray(origin, direction)
		if hit != null and origin.distance_to(hit) < closest:
			closest = origin.distance_to(hit)
			hit_player = player.id
	if hit_player >= 0:
		return {"kind": "pawn", "player_id": hit_player}
	return controller.target_at(Plane(Vector3.UP, 0.12).intersects_ray(origin, direction))

func click_at_screen(screen_position: Vector2) -> bool:
	if not can_interact():
		return false
	var target = target_at_screen(screen_position)
	var accepted = controller.click(target)
	if accepted:
		audio.play_effect("wall" if target.get("kind") == "wall" else "move")
		sync_scene(true)
	else:
		update_interaction_visuals()
		update_hud()
	return accepted

func update_interaction_visuals() -> void:
	var moves = controller.legal_destinations() if can_interact() else []
	if moves != shown_moves:
		shown_moves = moves.duplicate()
		$Board.show_legal_moves(moves)
	preview_wall.visible = can_interact() and not controller.preview.is_empty()
	if preview_wall.visible:
		var data = controller.preview
		position_wall(preview_wall, data.anchor, data.orientation)
		preview_material.albedo_color = Color(0.35, 0.85, 0.55, 0.4) if data.valid else Color(1.0, 0.18, 0.14, 0.55)

func update_hud() -> void:
	ui.update_cards(engine.state, elapsed_turns)
	var reason = controller.feedback
	if not controller.preview.is_empty() and not controller.preview.valid:
		reason = controller.preview.reason_code
	ui.feedback.text = reason.replace("_", " ").capitalize() if view == "game" else ""

func handle_ui_action(action: String) -> void:
	match action:
		"menu":
			ui.menu.visible = not ui.menu.visible
			controller.clear_selection()
			update_interaction_visuals()
		"setup_versus", "setup_battle":
			setup_mode = "Versus" if action == "setup_versus" else "Battle Royale"
			ui.setup_mode = setup_mode
			view = "setup"
			ui.show_page("setup")
		"start":
			var options = MatchConfig.for_mode(setup_mode)
			options.controllers.fill("Human")
			start_match(options)
		"pause":
			pause_match(not engine.state.paused)
		"resume":
			pause_match(false)
		"restart":
			restart_match()
		"main_menu":
			show_main_menu()
		"settings":
			settings_return = view
			if view == "game":
				set_match_paused(true)
			view = "settings"
			ui.show_page("settings")
			update_interaction_visuals()
		"settings_back":
			view = settings_return
			if view == "game":
				set_match_paused(false)
			ui.show_page(view)

func set_match_paused(value: bool) -> void:
	engine.set_paused(value)
	controller.clear_selection()
	if gameplay_tween != null and gameplay_tween.is_valid():
		if value:
			gameplay_tween.pause()
		else:
			gameplay_tween.play()

func pause_match(value: bool) -> void:
	if engine.state.status != "running":
		return
	set_match_paused(value)
	view = "pause" if value else "game"
	ui.show_page(view)
	update_interaction_visuals()
	update_hud()

func show_main_menu() -> void:
	cancel_transition()
	view = "main_menu"
	engine.set_paused(true)
	sync_scene()
	ui.has_match = false
	ui.show_page("main_menu")

func set_volume(category: String, value: float) -> void:
	audio.set_volume(category, value)
	if category == "music":
		ui.music_volume = audio.music_volume
	else:
		ui.effects_volume = audio.effects_volume

func set_animations(enabled: bool) -> void:
	animations_enabled = enabled
	ui.set_animations(enabled)
	if not enabled and animation_busy:
		cancel_transition()
		sync_scene()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and view != "closing":
		view = "closing"
		set_process(false)
		cancel_transition()
		audio.stop_all()
		# Let the audio mixer drain pending playback before releasing its resources.
		await get_tree().create_timer(0.1).timeout
		get_tree().quit()

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: set_camera_view("classic")
			KEY_2: set_camera_view("isometric")
			KEY_3: set_camera_view("cinematic")
			KEY_R:
				if can_interact():
					controller.rotate()
					controller.hover(target_at_screen(get_viewport().get_mouse_position()))
					update_interaction_visuals()
			KEY_ESCAPE:
				if view == "pause":
					pause_match(false)
				elif view == "settings":
					handle_ui_action("settings_back")
				elif view == "setup":
					show_main_menu()
				elif view == "game":
					if ui.menu.visible:
						ui.menu.hide()
					elif controller.selected:
						controller.clear_selection()
						update_interaction_visuals()
					else:
						pause_match(true)
			KEY_N:
				if view in ["game", "pause", "victory"]:
					restart_match()
	elif event is InputEventMouseButton and event.pressed and can_interact():
		if event.button_index == MOUSE_BUTTON_LEFT:
			click_at_screen(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			controller.rotate()
			controller.hover(target_at_screen(event.position))
			update_interaction_visuals()

func set_camera_view(view_name: String, animate: bool = true):

	if not camera_positions.has(view_name):
		return

	var target_position = camera_positions[view_name]
	var target_size = camera_sizes[view_name]

	if camera_tween:
		camera_tween.kill()

	if not animate:
		camera.position = target_position
		camera.look_at(Vector3.ZERO, Vector3.UP)
		camera.size = target_size
		return

	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.set_trans(Tween.TRANS_SINE)
	camera_tween.set_ease(Tween.EASE_IN_OUT)

	camera_tween.tween_property(
		camera,
		"position",
		target_position,
		0.8
	)

	camera_tween.tween_property(
		camera,
		"size",
		target_size,
		0.8
	)

	var target_transform = camera.transform.looking_at(
		Vector3.ZERO,
		Vector3.UP
	)

	var target_rotation = Transform3D(
		Basis.looking_at(
			Vector3.ZERO - target_position,
			Vector3.UP
		),
		target_position
	).basis.get_rotation_quaternion()

	camera_tween.tween_property(
		camera,
		"quaternion",
		target_rotation,
		0.8
	)
