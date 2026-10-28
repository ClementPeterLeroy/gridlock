extends Node3D

const MatchConfig = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")
const HumanController = preload("res://scripts/controllers/human_controller.gd")
const WallScene = preload("res://scenes/Wall.tscn")

@export_enum("Versus", "Battle Royale") var board_mode: String = "Battle Royale"

@onready var camera: Camera3D = $Camera3D

var camera_positions = {
	"classic": Vector3(0, 18, 3),
	"isometric": Vector3(11, 13, 11),
	"cinematic": Vector3(10, 7, 12)
}

var camera_sizes = {
	"classic": 13.5,
	"isometric": 15.0,
	"cinematic": 17.0
}

var camera_tween: Tween

var engine
var controller
var pawn_nodes: Array[Node3D] = []
var wall_nodes: Dictionary = {}
var placed_walls: Node3D
var preview_wall: Node3D
var preview_material: StandardMaterial3D
var hud_panel: PanelContainer
var status_label: Label
var inventory_label: Label
var feedback_label: Label
var shown_moves: Array = []
var scene_turn: Array = []


func _ready():
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true

	set_camera_view("isometric", false)
	for identity in MatchConfig.IDENTITIES:
		pawn_nodes.append(get_node("Pieces/" + identity + "Pawn"))
	# Keep the authored demonstration node, but never display it as a placed wall.
	$Walls/Wall.hide()
	placed_walls = Node3D.new()
	placed_walls.name = "PlacedWalls"
	$Walls.add_child(placed_walls)
	create_preview()
	create_hud()
	start_match()


func start_match(options = null) -> void:
	if options == null:
		options = MatchConfig.for_mode(board_mode)
		# This milestone is local input only; AI execution is planned for alpha.3.
		options.controllers.fill("Human")
	engine = MatchEngine.new(options)
	controller = HumanController.new(engine)
	sync_scene()


func restart_match() -> void:
	engine.restart()
	controller.clear_selection()
	controller.feedback = ""
	controller.suppressed_target = {}
	sync_scene()


func sync_scene() -> void:
	controller.clear_selection()
	for player_id in range(pawn_nodes.size()):
		var pawn = pawn_nodes[player_id]
		pawn.visible = player_id < engine.state.players.size() \
			and engine.state.players[player_id].position != null
		if pawn.visible:
			pawn.global_position = $Board.to_global($Board.cell_position(engine.state.players[player_id].position))
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
	var active = engine.state.players[engine.state.current_player].position
	$Board.show_active_player(active if engine.state.status == "running" else null)
	scene_turn = turn_token()
	update_interaction_visuals()
	update_hud()


func turn_token() -> Array:
	return [engine.state.current_player, engine.state.turn_number, engine.state.status, engine.state.paused]


func position_wall(wall: Node3D, anchor: Vector2i, orientation: String) -> void:
	wall.global_transform = $Board.global_transform
	wall.position = wall.get_parent().to_local($Board.to_global($Board.wall_position(anchor)))
	wall.rotate_object_local(Vector3.UP, PI / 2.0 if orientation == "V" else 0.0)


func create_preview() -> void:
	preview_wall = WallScene.instantiate()
	preview_wall.name = "WallPreview"
	add_child(preview_wall)
	preview_material = $Board.overlay_material(Color(0.35, 0.85, 0.55, 0.4))
	# A rejected duplicate still needs a visible red preview over the permanent wall.
	preview_material.no_depth_test = true
	apply_preview_material(preview_wall)
	preview_wall.hide()


func apply_preview_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		apply_preview_material(child)


func _process(_delta: float) -> void:
	if controller == null:
		return
	if scene_turn != turn_token():
		sync_scene()
	# Reproject every frame, including while a camera tween is moving.
	controller.hover(target_at_screen(get_viewport().get_mouse_position()))
	update_interaction_visuals()
	update_hud()


func target_at_screen(screen_position: Vector2) -> Dictionary:
	if not get_viewport().get_visible_rect().has_point(screen_position):
		return {}
	if hud_panel.get_global_rect().has_point(screen_position):
		return {}
	var origin = $Board.to_local(camera.project_ray_origin(screen_position))
	var direction = $Board.global_basis.inverse() * camera.project_ray_normal(screen_position)
	var closest = INF
	var hit_player = -1
	# Test the pawn's volume, not only its tile: its head projects above the board.
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
	var point = Plane(Vector3.UP, 0.12).intersects_ray(origin, direction)
	return controller.target_at(point)


func click_at_screen(screen_position: Vector2) -> bool:
	var accepted = controller.click(target_at_screen(screen_position))
	if accepted:
		sync_scene()
	else:
		update_interaction_visuals()
		update_hud()
	return accepted


func update_interaction_visuals() -> void:
	var moves = controller.legal_destinations()
	if moves != shown_moves:
		shown_moves = moves.duplicate()
		$Board.show_legal_moves(moves)
	preview_wall.visible = not controller.preview.is_empty()
	if preview_wall.visible:
		var data = controller.preview
		position_wall(preview_wall, data.anchor, data.orientation)
		preview_material.albedo_color = Color(0.35, 0.85, 0.55, 0.4) if data.valid else Color(1.0, 0.18, 0.14, 0.55)


func create_hud() -> void:
	var layer = CanvasLayer.new()
	layer.name = "BoardInterface"
	add_child(layer)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(16, 16)
	layer.add_child(hud_panel)
	var margin = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	hud_panel.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#F9D55E"))
	column.add_child(status_label)
	inventory_label = Label.new()
	column.add_child(inventory_label)
	var controls = Label.new()
	controls.text = "Click your pawn, then a green tile.\nHover grooves to place a wall.\nR / right-click: rotate   Esc: deselect\n1 / 2 / 3: camera   N: restart"
	controls.add_theme_font_size_override("font_size", 13)
	column.add_child(controls)
	feedback_label = Label.new()
	feedback_label.custom_minimum_size.x = 235
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 13)
	column.add_child(feedback_label)
	var restart = Button.new()
	restart.name = "RestartMatch"
	restart.text = "Restart Match"
	restart.pressed.connect(restart_match)
	column.add_child(restart)


func update_hud() -> void:
	if engine.state.winner >= 0:
		status_label.text = engine.state.players[engine.state.winner].name.to_upper() + " WINS!"
	else:
		status_label.text = engine.state.players[engine.state.current_player].name + "'s turn"
	var lines: PackedStringArray = []
	for player_id in engine.state.active_players():
		var player = engine.state.players[player_id]
		lines.append("%s: %d walls" % [player.name, player.walls_remaining])
	inventory_label.text = "\n".join(lines)
	var reason = controller.feedback
	if not controller.preview.is_empty() and not controller.preview.valid:
		reason = controller.preview.reason_code
	feedback_label.text = "Match complete. Restart to play again." if engine.state.winner >= 0 \
		else reason.replace("_", " ").capitalize()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:

		if event.keycode == KEY_1:
			set_camera_view("classic")

		elif event.keycode == KEY_2:
			set_camera_view("isometric")

		elif event.keycode == KEY_3:
			set_camera_view("cinematic")
		elif event.keycode == KEY_R:
			controller.rotate()
			controller.hover(target_at_screen(get_viewport().get_mouse_position()))
			update_interaction_visuals()
		elif event.keycode == KEY_ESCAPE:
			controller.clear_selection()
			update_interaction_visuals()
		elif event.keycode == KEY_N:
			restart_match()
	elif event is InputEventMouseButton and event.pressed:
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
