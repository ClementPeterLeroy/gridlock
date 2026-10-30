extends RefCounted
## Application preferences only, separate from match setup and gameplay snapshots.

const DEFAULT_PATH = "user://user_settings.cfg"
const CAMERAS = ["classic", "isometric", "cinematic"]
var path: String
var music_volume = 0.2
var effects_volume = 0.5
var camera_transitions = true
var gameplay_animations = true
var camera_view = "isometric"

func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	if path.is_empty(): return
	var file = ConfigFile.new()
	if file.load(path) != OK: return
	for key in ["music_volume", "effects_volume"]:
		var value = file.get_value("settings", key, get(key))
		if (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1:
			set(key, float(value))
	for key in ["camera_transitions", "gameplay_animations"]:
		var value = file.get_value("settings", key, get(key))
		if value is bool: set(key, value)
	var view = file.get_value("settings", "camera_view", camera_view)
	if view in CAMERAS: camera_view = view

func reset() -> void:
	music_volume = 0.2
	effects_volume = 0.5
	camera_transitions = true
	gameplay_animations = true
	camera_view = "isometric"

func save() -> Error:
	if path.is_empty(): return OK
	var file = ConfigFile.new()
	for key in ["music_volume", "effects_volume", "camera_transitions", "gameplay_animations", "camera_view"]:
		file.set_value("settings", key, get(key))
	return file.save(path)
