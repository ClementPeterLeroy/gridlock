extends Node3D

const MatchConfig = preload("res://scripts/core/match_config.gd")
const MatchEngine = preload("res://scripts/core/game_engine.gd")
const HumanController = preload("res://scripts/controllers/human_controller.gd")
const AIController = preload("res://scripts/ai/ai_controller.gd")
const MatchInterface = preload("res://scripts/ui/match_interface.gd")
const MatchAudio = preload("res://scripts/match_audio.gd")
const MatchPreferences = preload("res://scripts/core/match_preferences.gd")
const UserSettings = preload("res://scripts/user_settings.gd")
const DisplaySettings = preload("res://scripts/display_settings.gd")
const StartupSequence = preload("res://scripts/ui/startup_sequence.gd")
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
var ai
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
var preferences_path = MatchPreferences.DEFAULT_PATH
var preferences
var settings_path = UserSettings.DEFAULT_PATH
var user_settings
var applying_settings = false
var screen_transitions_enabled = true
var display
var display_enabled = true
var intro_enabled = true
var intro_played = false
var intro
var intro_video_path = "res://assets/branding/gridlock_intro.ogv"
var settings_return = "main_menu"
var live_timing = true
var elapsed_turns: Array:
	get: return engine.state.elapsed_turns
var animations_enabled = true
var animation_busy = false
var gameplay_tween: Tween
var victory_shown = false

func _ready() -> void:
	if not settings_path.is_empty(): print("Gridlock ", ProjectSettings.get_setting("application/config/version"), " startup")
	preferences = MatchPreferences.new(preferences_path)
	user_settings = UserSettings.new(settings_path)
	get_tree().auto_accept_quit = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	set_camera_view(user_settings.camera_view, false)
	for identity in MatchConfig.IDENTITIES:
		pawn_nodes.append(get_node("Pieces/" + identity + "Pawn"))
	$Walls/Wall.hide()
	placed_walls = Node3D.new()
	placed_walls.name = "PlacedWalls"
	$Walls.add_child(placed_walls)
	create_preview()
	ui = MatchInterface.new()
	ui.screen_transitions_enabled = screen_transitions_enabled
	add_child(ui)
	ui.action_requested.connect(handle_ui_action)
	ui.volume_changed.connect(set_volume)
	ui.animations_changed.connect(set_animations)
	ui.camera_transitions_changed.connect(set_camera_transitions)
	ui.camera_view_changed.connect(set_camera_view)
	ui.display_changed.connect(change_display)
	ui.transition_started.connect(refresh_timing_gate)
	ui.transition_finished.connect(refresh_timing_gate)
	audio = MatchAudio.new()
	add_child(audio)
	display = DisplaySettings.new()
	add_child(display)
	display.initialize(user_settings, get_window(), display_enabled and get_viewport() == get_tree().root)
	ui.display_manager = display
	display.changed.connect(func(): ui.show_display_confirmation(display.remaining))
	display.confirmation_finished.connect(func(_kept):
		ui.hide_display_confirmation()
		if view == "settings": ui.show_page("settings"))
	apply_user_settings()
	start_match()
	show_main_menu()
	if intro_enabled: play_intro()

func start_match(options = null) -> void:
	if options != null and not options.resolved().validation_error().is_empty():
		push_error("Match initialization rejected invalid configuration; keeping current match.")
		return
	if ai != null:
		ai.cancel()
	cancel_transition()
	if options == null:
		options = MatchConfig.for_mode(board_mode)
		options.controllers.fill("Human")
	engine = MatchEngine.new(options)
	if live_timing:
		engine.set_time_source(func(): return Time.get_ticks_usec() / 1000000.0)
	controller = HumanController.new(engine)
	ai = AIController.new(engine)
	reset_match_presentation()

func reset_match_presentation() -> void:
	victory_shown = false
	ui.has_match = true
	ui.animations_enabled = animations_enabled
	ui.build_cards(engine.state)
	show_screen("game")
	sync_scene()

func restart_match(replay: bool = false) -> void:
	ai.cancel()
	cancel_transition()
	if replay: engine.play_again()
	else: engine.restart()
	controller.clear_selection()
	controller.feedback = ""
	controller.suppressed_target = {}
	reset_match_presentation()

func sync_scene(animate: bool = false) -> void:
	if not animate:
		cancel_transition()
		refresh_timing_gate()
	controller.clear_selection()
	var tween: Tween = null
	if animate and animations_enabled:
		engine.set_timing_active(false)
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
	refresh_timing_gate()
	present_victory()

func present_victory() -> void:
	if engine.state.winner < 0 or victory_shown or view != "game":
		return
	victory_shown = true
	ai.cancel()
	controller.clear_selection()
	show_screen("victory")
	update_interaction_visuals()
	audio.play_effect("victory")

func turn_token() -> Array:
	return [engine.state.current_player, engine.state.turn_number, engine.state.status]

func show_screen(next: String) -> void:
	engine.set_timing_active(false)
	view = next
	# One 3D visibility boundary hides board, pawns, walls and all highlights.
	# The independent CanvasLayer remains visible on full-screen application pages.
	visible = view in ["game", "pause", "victory"] or (view == "settings" and settings_return in ["game", "pause", "victory"])
	ui.match_background_visible = visible
	ui.show_page(view, engine.state if view == "victory" else null)
	refresh_timing_gate()
	update_interaction_visuals()

func refresh_timing_gate() -> void:
	if engine != null:
		engine.set_timing_active(view == "game" and not animation_busy and not ui.transitioning)

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
	if display != null and display.pending:
		if ui.confirmation_overlay == null or not ui.confirmation_overlay.is_visible_in_tree(): display.revert()
		else: ui.show_display_confirmation(display.remaining)
	if controller == null:
		return
	if scene_turn != turn_token():
		sync_scene()
	update_elapsed(delta)
	if scene_turn != turn_token():
		ai.cancel()
		sync_scene()
		# The incoming seat must not inherit elapsed time from a timed-out turn.
		delta = 0.0
	if view == "game" and not engine.state.paused and not animation_busy and not ui.transitioning:
		var outcome = ai.update(delta)
		if outcome.get("accepted", false):
			finish_action(outcome.action)
	controller.hover(target_at_screen(get_viewport().get_mouse_position()))
	update_interaction_visuals()
	update_hud()
	if not animation_busy:
		present_victory()

func update_elapsed(delta: float) -> void:
	if view == "game" and engine.state.status == "running" and not engine.state.paused and not animation_busy and not ui.transitioning:
		if engine.time_source.is_valid():
			engine.poll_time()
		else:
			engine.tick(delta)

func can_interact() -> bool:
	return controller != null and visible and view == "game" and not ui.transitioning and not ui.menu.visible and not animation_busy and controller.available()

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
	engine.poll_time()
	if scene_turn != turn_token():
		ai.cancel()
		sync_scene()
		return false
	if not can_interact():
		return false
	var target = target_at_screen(screen_position)
	var accepted = controller.click(target)
	if accepted:
		finish_action({"kind": "wall" if target.get("kind") == "wall" else "move"})
	else:
		if scene_turn != turn_token():
			sync_scene()
		update_interaction_visuals()
		update_hud()
	return accepted

func finish_action(action: Dictionary) -> void:
	audio.play_effect(action.kind)
	sync_scene(true)

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
	ui.update_cards(engine.state)
	var reason = controller.feedback
	if not controller.preview.is_empty() and not controller.preview.valid:
		reason = controller.preview.reason_code
	ui.feedback.text = reason.replace("_", " ").capitalize() if view == "game" else ""
	if view == "game" and not engine.state.timing_notice.is_empty():
		ui.feedback.text = engine.state.timing_notice
	if view == "game" and not animation_busy and ai.is_ai_turn():
		ui.feedback.text = "%s is thinking..." % engine.state.players[engine.state.current_player].name \
			if ai.thinking() else ai.feedback
		if not engine.state.timing_notice.is_empty():
			ui.feedback.text += "  " + engine.state.timing_notice

func handle_ui_action(action: String) -> void:
	if view in ["closing", "intro"] or ui.transitioning: return
	if display.pending and action not in ["keep_display", "revert_display", "exit"]: return
	match action:
		"menu":
			ui.menu.visible = not ui.menu.visible
			controller.clear_selection()
			update_interaction_visuals()
		"setup_versus", "setup_battle", "setup_blitz", "setup_ai":
			var mode = {"setup_versus": "Versus", "setup_battle": "Battle Royale", "setup_blitz": "Blitz", "setup_ai": "Versus"}[action]
			ui.setup_entry = "Rise of the Machines" if action == "setup_ai" else mode
			ui.setup_config = preferences.configs[ui.setup_entry].copy()
			ui.setup_heading = "Rise of the Machines" if action == "setup_ai" else ""
			if action == "setup_versus": ui.setup_config.controllers.fill("Human")
			if action == "setup_ai" and ui.setup_config.controllers.all(func(c): return c == "Human"):
				ui.setup_config.controllers[1] = "AI - Casual"
			show_screen("setup")
		"start":
			if not ui.validate_setup(): return
			if ui.setup_entry == "Versus": ui.setup_config.controllers.fill("Human")
			persist_setup()
			start_match(ui.setup_config)
		"reset_preferences":
			preferences.reset()
			save_preferences()
			ui.setup_config = preferences.configs[ui.setup_entry].copy()
			if view == "setup": ui.show_page("setup")
		"pause":
			pause_match(not engine.state.paused)
		"resume":
			pause_match(false)
		"restart":
			restart_match()
		"play_again":
			restart_match(true)
		"main_menu":
			show_main_menu()
		"settings":
			settings_return = view
			if view == "game":
				set_match_paused(true)
				if engine.state.status == "finished":
					sync_scene()
					return
			show_screen("settings")
			update_interaction_visuals()
		"settings_back":
			if view != "settings":
				return
			if settings_return == "game":
				set_match_paused(false)
			show_screen(settings_return)
		"reset_settings":
			var old_mode = user_settings.display_mode
			var old_resolution = user_settings.window_resolution
			user_settings.reset()
			user_settings.display_mode = old_mode
			user_settings.window_resolution = old_resolution
			apply_user_settings()
			display.apply_window()
			save_user_settings()
			ui.show_page("settings")
			display.propose("Windowed", Vector2i(1280, 720))
		"how_to_play": show_screen("how_to_play")
		"keep_display": display.confirm()
		"revert_display": display.revert()
		"exit":
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)

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
	if engine.state.status == "finished":
		sync_scene()
		return
	show_screen("pause" if value else "game")
	update_interaction_visuals()
	update_hud()

func show_main_menu() -> void:
	if view == "setup": persist_setup()
	ai.cancel()
	cancel_transition()
	engine.set_paused(true)
	show_screen("main_menu")
	sync_scene()
	ui.has_match = false

func persist_setup() -> void:
	if ui.validate_setup():
		preferences.remember(ui.setup_config, ui.setup_entry)
		save_preferences()

func save_preferences() -> void:
	if preferences.save() != OK:
		push_warning("Match preferences could not be saved; current session settings remain available.")

func set_volume(category: String, value: float) -> void:
	audio.set_volume(category, value)
	if category == "music":
		ui.music_volume = audio.music_volume
	else:
		ui.effects_volume = audio.effects_volume
	user_settings.set("music_volume" if category == "music" else "effects_volume", value)
	save_user_settings()

func set_animations(enabled: bool) -> void:
	animations_enabled = enabled
	ui.set_animations(enabled)
	user_settings.gameplay_animations = enabled
	save_user_settings()
	if not enabled and animation_busy:
		cancel_transition()
		refresh_timing_gate()
		sync_scene()

func apply_user_settings() -> void:
	applying_settings = true
	set_volume("music", user_settings.music_volume)
	set_volume("effects", user_settings.effects_volume)
	set_animations(user_settings.gameplay_animations)
	ui.camera_transitions_enabled = user_settings.camera_transitions
	set_camera_view(user_settings.camera_view, false)
	applying_settings = false

func save_user_settings() -> void:
	if applying_settings: return
	if user_settings != null and user_settings.save() != OK:
		push_warning("Application settings could not be saved; session values remain available.")

func set_camera_transitions(enabled: bool) -> void:
	user_settings.camera_transitions = enabled
	ui.camera_transitions_enabled = enabled
	if not enabled: set_camera_view(user_settings.camera_view, false)
	save_user_settings()

func handle_escape() -> void:
	match view:
		"game": pause_match(true)
		"pause": pause_match(false)
		"settings": handle_ui_action("settings_back")
		"setup", "how_to_play": show_main_menu()

func _input(event) -> void:
	if view == "intro":
		get_viewport().set_input_as_handled()
		return
	if display != null and display.pending and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		display.revert()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not ui.transitioning: handle_escape()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and view != "closing":
		if view == "setup": persist_setup()
		view = "closing"
		engine.set_paused(true)
		engine.set_timing_active(false)
		set_process(false)
		cancel_transition()
		ai.cancel()
		audio.stop_all()
		# Let the audio mixer drain pending playback before releasing its resources.
		await get_tree().create_timer(0.1).timeout
		get_tree().quit()

func _unhandled_input(event) -> void:
	if view == "intro" or ui.transitioning or display.pending: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				if view in ["game", "pause", "victory"]:
					set_camera_view(["classic", "isometric", "cinematic"][event.keycode - KEY_1])
			KEY_R:
				if can_interact():
					controller.rotate()
					controller.hover(target_at_screen(get_viewport().get_mouse_position()))
					update_interaction_visuals()
			KEY_ESCAPE:
				handle_escape()
			KEY_N:
				if view in ["game", "pause", "victory"] and not ui.menu.visible:
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
	if user_settings != null:
		animate = animate and user_settings.camera_transitions
		if user_settings.camera_view != view_name:
			user_settings.camera_view = view_name
			save_user_settings()
	if ui != null: ui.preferred_camera = view_name

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

func play_intro() -> void:
	if intro_played: return
	intro_played = true
	show_screen("intro")
	ui.finish_screen_transition()
	intro = StartupSequence.new()
	intro.video_path = intro_video_path
	ui.add_child(intro)
	audio.music.stream_paused = true
	intro.completed.connect(func():
		intro = null
		audio.music.stream_paused = false
		if view != "closing": show_main_menu())

func change_display(field: String, value) -> void:
	if display.pending: return
	match field:
		"mode": display.propose(value, display.current.resolution)
		"resolution": display.propose(display.current.mode, value)
		"scale":
			user_settings.ui_scale = value
			display.update_scale()
			save_user_settings()
		"vsync":
			user_settings.vsync = value
			display.apply_vsync()
			save_user_settings()
