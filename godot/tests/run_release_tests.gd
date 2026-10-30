extends "res://tests/run_beta_ui_tests.gd"
const Display = preload("res://scripts/display_settings.gd")
const Startup = preload("res://scripts/ui/startup_sequence.gd")
const Preferences = preload("res://scripts/core/match_preferences.gd")
const DISPLAY_PATH = "res://.godot/release-display-test.cfg"
const MATCH_PATH = "res://.godot/release-match-test.cfg"

func run() -> void:
	check(test_display_policy() == true, "display transaction coverage completed")
	check(test_versus_preferences() == true, "Versus preferences coverage completed")
	check(await test_intro() == true, "startup coverage completed")
	game = Scene.instantiate()
	game.settings_path = ""
	game.preferences_path = ""
	game.intro_enabled = false
	game.display_enabled = false
	game.screen_transitions_enabled = false
	game.live_timing = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_animations(false)
	check(await test_release_menus() == true, "single-page UI coverage completed")
	check(test_ui_display() == true, "display controls coverage completed")
	check(test_export_configuration() == true, "export coverage completed")
	game.free()
	await create_timer(0.1).timeout
	for path in [DISPLAY_PATH, MATCH_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("RELEASE TESTS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_display_policy() -> bool:
	if FileAccess.file_exists(DISPLAY_PATH): DirAccess.remove_absolute(DISPLAY_PATH)
	var settings = Settings.new(DISPLAY_PATH)
	check(settings.camera_view == "classic" and settings.display_mode == "Windowed" and settings.ui_scale == "Automatic" and settings.vsync, "safe first-launch defaults")
	var display = Display.new()
	root.add_child(display)
	display.set_process(false)
	display.initialize(settings, root, false)
	check(display.current.resolution == Vector2i(1280,720), "default window fits monitor")
	check(Vector2i(2560,1440) not in display.available_resolutions(), "oversized options excluded with desktop decoration allowance")
	for mode in Settings.DISPLAY_MODES:
		display.propose(mode, Vector2i(1600,900))
		check(display.pending and display.remaining == 10, "display proposal starts ten second confirmation")
		check(settings.display_mode == "Windowed" and settings.window_resolution == Vector2i(1280,720), "unconfirmed changes never enter saved preferences")
		display._process(9.9)
		check(display.pending, "confirmation remains before deadline")
		display._process(0.2)
		check(not display.pending and display.current == display.confirmed, "deadline restores last confirmed display")
	display.propose("Borderless Fullscreen", Vector2i(1600,900))
	display.confirm()
	var loaded = Settings.new(DISPLAY_PATH)
	check(loaded.display_mode == "Borderless Fullscreen" and loaded.window_resolution == Vector2i(1600,900), "confirmed mode and window resolution survive reload")
	display.propose("Fullscreen", Vector2i(1280,720))
	display.revert()
	check(display.current.mode == "Borderless Fullscreen" and loaded.display_mode == settings.display_mode, "explicit revert restores confirmed configuration")
	for scale in Settings.SCALES:
		settings.ui_scale = scale
		for size in Settings.RESOLUTIONS:
			var effective = display.scale_for(size)
			check(effective <= minf(size.x/1280.0,size.y/720.0), "scale constrained to fit complete menus")
			check(settings.ui_scale == scale, "scale cap preserves chosen preference")
	settings.ui_scale = "150%"
	settings.vsync = false
	settings.save()
	loaded = Settings.new(DISPLAY_PATH)
	check(loaded.ui_scale == "150%" and not loaded.vsync, "scale and VSync round trip")
	var file = ConfigFile.new()
	for entry in [["display_mode","broken"],["window_resolution",Vector2i(99999,1)],["ui_scale",10],["vsync","false"]]: file.set_value("settings",entry[0],entry[1])
	file.save(DISPLAY_PATH)
	loaded = Settings.new(DISPLAY_PATH)
	check(loaded.display_mode == "Windowed" and loaded.window_resolution == Vector2i(1280,720) and loaded.ui_scale == "Automatic" and loaded.vsync, "invalid stored display values fall back")
	display.usable_area = Rect2i(0,0,1024,700)
	check(display.safe_resolution(Vector2i(2560,1440)).x <= 1024 and display.safe_resolution(Vector2i(2560,1440)).y <= 700, "disconnected or smaller monitor gets safe fallback")
	display.free()
	return true

func test_versus_preferences() -> bool:
	var file = ConfigFile.new()
	file.set_value("Versus","controllers",["AI - Challenging","AI - Casual"])
	file.set_value("Battle Royale","controllers",["AI - Challenging","Human","AI - Casual","Human"])
	file.save(MATCH_PATH)
	var prefs = Preferences.new(MATCH_PATH)
	check(prefs.configs.Versus.controllers.slice(0,2) == ["Human","Human"], "saved Versus AI repaired")
	check(prefs.configs["Battle Royale"].controllers[0] == "AI - Challenging", "other mode preferences preserved")
	check(prefs.configs["Rise of the Machines"].controllers[1] == "AI - Casual", "Machines retains Casual AI")
	check(prefs.configs["Rise of the Machines"].controllers[0] == "AI - Challenging", "legacy shared Versus AI migrates to Machines before human normalization")
	var config = prefs.configs["Rise of the Machines"].copy()
	config.controllers[0] = "AI - Challenging"
	prefs.remember(config, "Rise of the Machines")
	prefs.save()
	prefs = Preferences.new(MATCH_PATH)
	check(prefs.configs["Rise of the Machines"].controllers[0] == "AI - Challenging" and prefs.configs.Versus.controllers[0] == "Human", "AI-oriented preferences independent of human Versus")
	return true

func test_intro() -> bool:
	var startup_game = Scene.instantiate()
	startup_game.settings_path = ""
	startup_game.preferences_path = ""
	startup_game.display_enabled = false
	startup_game.live_timing = false
	startup_game.screen_transitions_enabled = false
	root.add_child(startup_game)
	await process_frame
	startup_game.set_process(false)
	check(startup_game.view == "intro" and startup_game.intro_played and not startup_game.visible, "intro precedes menu and hides 3D")
	check(startup_game.intro.player != null and startup_game.intro.player.stream != null, "official converted intro stream available")
	var intro = startup_game.intro
	startup_game.handle_ui_action("setup_versus")
	startup_game._unhandled_input(InputEventKey.new())
	check(startup_game.view == "intro" and not startup_game.can_interact(), "startup blocks menu and gameplay input")
	intro.finish()
	check(startup_game.view == "main_menu" and startup_game.intro == null, "intro completion opens main menu")
	startup_game.play_intro()
	check(startup_game.intro == null, "returning to menu cannot replay intro")
	startup_game.free()
	var fallback = Startup.new()
	fallback.video_path = "res://missing-intro.ogv"
	root.add_child(fallback)
	check(fallback.fallback_active and fallback.animation != null, "missing animation uses bounded native branding fallback")
	fallback.animation.pause()
	fallback.animation.custom_step(2)
	check(fallback.finished, "fallback completes without black screen")
	await process_frame
	var corrupt_path = "res://.godot/corrupt-intro.ogv"
	var corrupt = FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_string("invalid video")
	corrupt.close()
	var broken = Startup.new()
	broken.video_path = corrupt_path
	root.add_child(broken)
	broken._process(9)
	check(broken.finished, "corrupt animation cannot leave startup stuck")
	await process_frame
	DirAccess.remove_absolute(corrupt_path)
	return true

func test_release_menus() -> bool:
	for size in Settings.RESOLUTIONS:
		root.size = size
		var bounds = Rect2(Vector2.ZERO,Vector2(size))
		game.show_main_menu()
		for action in ["setup_versus","setup_battle","setup_blitz","setup_ai","settings","how_to_play"]:
			navigate(action)
			await process_frame
			await process_frame
			check(bounds.encloses(game.ui.page_panel.get_global_rect()), "menu fits " + action + " " + str(size))
			check(game.ui.page_panel.find_children("*","ScrollContainer",true,false).filter(func(control): return control.is_visible_in_tree()).is_empty(), "no scroll containers on primary screen")
			for control in game.ui.page_panel.find_children("*","BaseButton",true,false) + game.ui.page_panel.find_children("*","LineEdit",true,false):
				check(bounds.encloses(control.get_global_rect()), "all controls simultaneously accessible " + action)
			if game.view == "setup":
				if action == "setup_versus":
					check(game.ui.controller_options.is_empty(), "Versus has no AI controls")
					game.ui.setup_config.controllers.fill("AI - Challenging")
					navigate("start")
					check(game.engine.state.players.size() == 2 and game.engine.state.config.controllers[0] == "Human" and game.engine.state.config.controllers[1] == "Human" and game.engine.state.config.timing_mode == "Untimed", "Versus launch always normalizes human-only untimed configuration")
				elif action == "setup_ai": check(game.ui.setup_config.controllers[1] != "Human", "Machines keeps working")
			game.show_main_menu()
	return true

func test_ui_display() -> bool:
	game.handle_ui_action("settings")
	check(game.ui.display_options.size() == 4, "all display controls present")
	var snapshot = game.engine.state.snapshot()
	var invalid = game.engine.state.config.copy()
	invalid.names[0] = ""
	game.start_match(invalid)
	check(game.engine.state.snapshot() == snapshot, "invalid initialization preserves match and logs diagnostic")
	game.change_display("mode", "Fullscreen")
	check(game.display.pending and game.ui.confirmation_overlay != null, "display proposal shows confirmation")
	game.handle_ui_action("settings_back")
	check(game.view == "settings", "cannot navigate behind confirmation")
	game.display._process(11)
	check(not game.display.pending and game.ui.confirmation_overlay == null, "automatic rollback closes dialog")
	game.change_display("mode", "Borderless Fullscreen")
	game.handle_ui_action("keep_display")
	check(game.user_settings.display_mode == "Borderless Fullscreen" and game.ui.display_options.resolution.disabled, "keep persists mode and disables fullscreen resolution selector")
	game.change_display("mode", "Windowed")
	game.ui.hide_display_confirmation()
	game._process(0)
	check(not game.display.pending and game.display.current.mode == "Borderless Fullscreen", "lost confirmation automatically restores last display")
	game.change_display("scale", "150%")
	game.change_display("vsync", false)
	check(game.user_settings.ui_scale == "150%" and not game.user_settings.vsync, "scale and vsync apply independently")
	check(game.engine.state.snapshot() == snapshot, "display settings never reset paused match state")
	game.handle_ui_action("reset_settings")
	check(game.display.pending, "reset display requires confirmation")
	game.handle_ui_action("keep_display")
	check(game.user_settings.display_mode == "Windowed" and game.user_settings.ui_scale == "Automatic" and game.user_settings.vsync, "reset restores confirmed display defaults")
	return true

func test_export_configuration() -> bool:
	var preset = ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "Windows export preset parses")
	check(preset.get_value("preset.0", "platform") == "Windows Desktop" and preset.get_value("preset.0.options","binary_format/architecture") == "x86_64", "Windows x86-64 target")
	check(not preset.get_value("preset.0.options","binary_format/embed_pck"), "package explicitly uses companion PCK")
	check(str(ProjectSettings.get_setting("application/config/version")) == "3.0-beta.2" and ProjectSettings.get_setting("application/config/name") == "Gridlock", "release branding synchronized")
	for path in ["assets/branding/gridlock_intro.ogv","assets/branding/gridlock_logo.png","assets/branding/gridlock_icon.png","assets/models/board.glb","assets/models/pawn.glb","assets/models/wall.glb","assets/fonts/Lato-Regular.ttf","assets/fonts/Cinzel.ttf","assets/audio/simple_move.wav","assets/audio/simple_happy_loop.mp3","assets/audio/electronic_victory_sound.mp3"]:
		check(ResourceLoader.exists("res://"+path), "release resource exists " + path)
	return true
