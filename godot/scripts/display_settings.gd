extends Node
## Owns native window changes and the unconfirmed ten-second display transaction.

signal changed
signal confirmation_finished(kept: bool)
const Settings = preload("res://scripts/user_settings.gd")
var settings
var native_enabled = true
var window: Window
var current: Dictionary = {}
var confirmed: Dictionary = {}
var pending = false
var remaining = 0.0
var usable_area = Rect2i(0, 0, 1920, 1080)
var effective_scale = 1.0

func initialize(preferences, target: Window, use_native: bool) -> void:
	settings = preferences
	window = target
	native_enabled = use_native and DisplayServer.get_name() != "headless"
	if native_enabled:
		usable_area = DisplayServer.screen_get_usable_rect(window.current_screen)
	current = {"mode": settings.display_mode, "resolution": safe_resolution(settings.window_resolution)}
	confirmed = current.duplicate()
	apply_window()
	if native_enabled: window.size_changed.connect(update_scale)

func available_resolutions() -> Array:
	var result = []
	# Leave room for the native title bar and borders in windowed mode.
	var space = usable_area.size - Vector2i(32, 64)
	for value in Settings.RESOLUTIONS:
		if value.x <= space.x and value.y <= space.y: result.append(value)
	if result.is_empty(): result.append(Vector2i(maxi(320, space.x), maxi(240, space.y)))
	return result

func safe_resolution(value: Vector2i) -> Vector2i:
	var available = available_resolutions()
	return value if value in available else available[0]

func propose(mode: String, resolution: Vector2i) -> void:
	if pending or mode not in Settings.DISPLAY_MODES: return
	var proposal = {"mode": mode, "resolution": safe_resolution(resolution)}
	if proposal == current: return
	confirmed = current.duplicate()
	current = proposal
	pending = true
	remaining = 10.0
	apply_window()
	changed.emit()

func confirm() -> void:
	if not pending: return
	pending = false
	confirmed = current.duplicate()
	settings.display_mode = current.mode
	settings.window_resolution = current.resolution
	if settings.save() != OK: push_warning("Display preferences could not be saved.")
	confirmation_finished.emit(true)

func revert() -> void:
	if not pending: return
	pending = false
	current = confirmed.duplicate()
	apply_window()
	confirmation_finished.emit(false)

func _process(delta: float) -> void:
	if not pending: return
	remaining = maxf(0, remaining - delta)
	if remaining <= 0 or (native_enabled and (not window.visible or window.mode == Window.MODE_MINIMIZED)):
		revert()

func apply_window() -> void:
	if native_enabled:
		usable_area = DisplayServer.screen_get_usable_rect(window.current_screen)
		current.resolution = safe_resolution(current.resolution)
		window.mode = Window.MODE_WINDOWED
		window.borderless = false
		if current.mode == "Windowed":
			window.min_size = Vector2i(mini(1280, usable_area.size.x - 32), mini(720, usable_area.size.y - 64))
			window.size = current.resolution
			window.position = usable_area.position + (usable_area.size - window.size) / 2
		elif current.mode == "Fullscreen":
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		else:
			window.borderless = true
			window.mode = Window.MODE_FULLSCREEN
		apply_vsync()
	update_scale()

func apply_vsync() -> void:
	if native_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)

func scale_for(size: Vector2i) -> float:
	var fit = minf(size.x / 1280.0, size.y / 720.0)
	var desired = fit if settings.ui_scale == "Automatic" else float(settings.ui_scale.trim_suffix("%")) / 100.0
	return minf(desired, fit)

func update_scale() -> void:
	var size = window.size if native_enabled else Vector2i(1280, 720)
	effective_scale = scale_for(size)
	if native_enabled:
		var automatic = minf(size.x / 1280.0, size.y / 720.0)
		window.content_scale_factor = effective_scale / maxf(automatic, 0.1)

