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
	for mode in MODES:
		var config = Config.for_mode(mode)
		config.controllers.fill("Human")
		configs[mode] = config

func load_preferences() -> void:
	if path.is_empty(): return
	var file = ConfigFile.new()
	if file.load(path) != OK: return
	var version = file.get_value("preferences", "version", 0)
	var blitz_timer_supported = version is int and version >= 2
	for mode in MODES:
		var config = configs[mode]
		var names = file.get_value(mode, "names", config.names)
		if names is Array:
			for id in range(mini(4, names.size())):
				if names[id] is String:
					var name = Config.clean_name(names[id])
					config.names[id] = Config.IDENTITIES[id] if name.is_empty() else name
		var controls = file.get_value(mode, "controllers", config.controllers)
		if controls is Array:
			for id in range(mini(config.player_count(), controls.size())):
				if controls[id] in Config.CONTROLLERS:
					config.controllers[id] = controls[id]
		var random = file.get_value(mode, "random_start", false)
		config.random_start = random if random is bool else false
		var timer = file.get_value(mode, "timer_type", config.timer_type)
		# In v1, Blitz saved an unused Per Turn field but always ran global clocks.
		if mode != "Blitz" or blitz_timer_supported:
			config.timer_type = timer if timer in Config.TIMER_TYPES else config.timer_type
		var turn = file.get_value(mode, "turn_limit", config.turn_limit)
		if (turn is int or turn is float) and turn in Config.TURN_SECONDS:
			config.turn_limit = int(turn)
		var budget = file.get_value(mode, "game_limit", config.game_limit)
		if (budget is int or budget is float) and budget in Config.GAME_SECONDS:
			config.game_limit = int(budget)
		var minutes = file.get_value(mode, "blitz_minutes", 3)
		if (minutes is int or minutes is float) and minutes in [1, 3, 5]:
			config.blitz_minutes = int(minutes)
		if mode == "Versus":
			config.turn_limit = 0
			config.game_limit = 0

func remember(config) -> void:
	configs[config.mode] = config.copy()

func save() -> Error:
	if path.is_empty(): return OK
	var file = ConfigFile.new()
	file.set_value("preferences", "version", 2)
	for mode in MODES:
		var values = configs[mode].to_dict()
		values.erase("starting_player")
		values.erase("mode")
		for key in values:
			file.set_value(mode, key, values[key])
	return file.save(path)
