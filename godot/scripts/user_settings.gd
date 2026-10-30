extends RefCounted
## Application preferences only, separate from match setup and gameplay snapshots.

const DEFAULT_PATH = "user://user_settings.cfg"
const CAMERAS = ["classic", "isometric", "cinematic"]
var path: String
var music_volume = 0.2
var effects_volume = 0.5
var camera_transitions = true
var gameplay_animations = true
var camera_view = "classic"
const DISPLAY_MODES = ["Windowed", "Fullscreen", "Borderless Fullscreen"]
const RESOLUTIONS = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const SCALES = ["Automatic", "100%", "125%", "150%"]
const KEYS = ["music_volume", "effects_volume", "camera_transitions", "gameplay_animations", "camera_view", "display_mode", "window_resolution", "ui_scale", "vsync"]
var display_mode = "Windowed"
var window_resolution = Vector2i(1280, 720)
var ui_scale = "Automatic"
var vsync = true

func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	if path.is_empty(): return
	var file = ConfigFile.new()
	var load_path = path
	# Keep beta.1 preferences when the display name changes from GridLock_3D.
	if path == DEFAULT_PATH and not FileAccess.file_exists(path):
		var legacy = OS.get_user_data_dir().get_base_dir().path_join("GridLock_3D/" + path.get_file())
		if FileAccess.file_exists(legacy): load_path = legacy
	if file.load(load_path) != OK: return
	for key in ["music_volume", "effects_volume"]:
		var value = file.get_value("settings", key, get(key))
		if (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1:
			set(key, float(value))
	for key in ["camera_transitions", "gameplay_animations", "vsync"]:
		var value = file.get_value("settings", key, get(key))
		if value is bool: set(key, value)
	var view = file.get_value("settings", "camera_view", camera_view)
	if view in CAMERAS: camera_view = view
	var mode = file.get_value("settings", "display_mode", display_mode)
	if mode in DISPLAY_MODES: display_mode = mode
	var resolution = file.get_value("settings", "window_resolution", window_resolution)
	if resolution is Vector2i and resolution in RESOLUTIONS: window_resolution = resolution
	var scale = file.get_value("settings", "ui_scale", ui_scale)
	if scale in SCALES: ui_scale = scale

func reset() -> void:
	music_volume = 0.2
	effects_volume = 0.5
	camera_transitions = true
	gameplay_animations = true
	camera_view = "classic"
	display_mode = "Windowed"
	window_resolution = Vector2i(1280, 720)
	ui_scale = "Automatic"
	vsync = true

func save() -> Error:
	if path.is_empty(): return OK
	var file = ConfigFile.new()
	for key in KEYS:
		file.set_value("settings", key, get(key))
	return file.save(path)
