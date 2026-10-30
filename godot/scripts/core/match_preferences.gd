extends RefCounted
## Setup preferences only; live match state never enters this file.

const Config = preload("res://scripts/core/match_config.gd")
const MODES = ["Versus", "Battle Royale", "Blitz"]
const DEFAULT_PATH = "user://match_preferences.cfg"

var path: String
var configs: Dictionary = {}

func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	reset()
	load_preferences()

func reset() -> void:
	configs.clear()
	for mode in MODES + ["Rise of the Machines"]:
		var config = Config.for_mode("Versus" if mode == "Rise of the Machines" else mode)
		config.controllers.fill("Human")
		if mode == "Rise of the Machines": config.controllers[1] = "AI - Casual"
		configs[mode] = config

func load_preferences() -> void:
	if path.is_empty(): return
	var file = ConfigFile.new()
	var load_path = path
	# Keep beta.1 preferences when the display name changes from GridLock_3D.
	if path == DEFAULT_PATH and not FileAccess.file_exists(path):
		var legacy = OS.get_user_data_dir().get_base_dir().path_join("GridLock_3D/" + path.get_file())
		if FileAccess.file_exists(legacy): load_path = legacy
	if file.load(load_path) != OK: return
	var version = file.get_value("preferences", "version", 0)
	var blitz_timer_supported = version is int and version >= 2
	for mode in MODES + ["Rise of the Machines"]:
		var section = mode
		# Beta.1 shared Versus storage with the AI entry; retain those choices once.
		if mode == "Rise of the Machines" and not file.has_section(mode): section = "Versus"
		var config = configs[mode]
		var names = file.get_value(section, "names", config.names)
		if names is Array:
			for id in range(mini(4, names.size())):
				if names[id] is String:
					var name = Config.clean_name(names[id])
					config.names[id] = Config.IDENTITIES[id] if name.is_empty() else name
		var controls = file.get_value(section, "controllers", config.controllers)
		if controls is Array:
			for id in range(mini(config.player_count(), controls.size())):
				if controls[id] in Config.CONTROLLERS:
					config.controllers[id] = controls[id]
		var random = file.get_value(section, "random_start", false)
		config.random_start = random if random is bool else false
		var timer = file.get_value(section, "timer_type", config.timer_type)
		# In v1, Blitz saved an unused Per Turn field but always ran global clocks.
		if mode != "Blitz" or blitz_timer_supported:
			config.timer_type = timer if timer in Config.TIMER_TYPES else config.timer_type
		var turn = file.get_value(section, "turn_limit", config.turn_limit)
		if (turn is int or turn is float) and turn in Config.TURN_SECONDS:
			config.turn_limit = int(turn)
		var budget = file.get_value(section, "game_limit", config.game_limit)
		if (budget is int or budget is float) and budget in Config.GAME_SECONDS:
			config.game_limit = int(budget)
		var minutes = file.get_value(section, "blitz_minutes", 3)
		if (minutes is int or minutes is float) and minutes in [1, 3, 5]:
			config.blitz_minutes = int(minutes)
		if mode == "Versus": config.controllers.fill("Human")
		if mode in ["Versus", "Rise of the Machines"]:
			config.turn_limit = 0
			config.game_limit = 0

func remember(config, entry: String = "") -> void:
	var key = config.mode if entry.is_empty() else entry
	configs[key] = config.copy()
	if key == "Versus": configs[key].controllers.fill("Human")

func save() -> Error:
	if path.is_empty(): return OK
	var file = ConfigFile.new()
	file.set_value("preferences", "version", 2)
	for mode in MODES + ["Rise of the Machines"]:
		var values = configs[mode].to_dict()
		values.erase("starting_player")
		values.erase("mode")
		for key in values:
			file.set_value(mode, key, values[key])
	return file.save(path)
