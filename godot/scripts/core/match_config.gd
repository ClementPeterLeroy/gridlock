class_name GridlockMatchConfig
extends RefCounted
## Session match options. Timing values are enforced by the gameplay engine.

const MODES = ["Versus", "Battle Royale", "Blitz", "Rise of the Machines"]
const IDENTITIES = ["Sapphire", "Crimson", "Emerald", "Violet"]
const CONTROLLERS = ["Human", "AI - Casual", "AI - Challenging"]

var mode: String = "Versus"
var names: Array = ["", "", "", ""]
var controllers: Array = ["Human", "Human"]
var random_start: bool = false
var starting_player: int = 0
var turn_limit: int = 0
var blitz_minutes: int = 3

static func for_mode(value: String) -> GridlockMatchConfig:
	var config = new()
	config.mode = value
	if value == "Battle Royale":
		config.controllers = ["Human", "AI - Casual", "AI - Casual", "AI - Casual"]
	elif value == "Rise of the Machines":
		config.controllers = ["Human", "AI - Casual"]
	return config

func player_count() -> int:
	return 4 if mode == "Battle Royale" else 2

func validation_error() -> String:
	if mode not in MODES or names.size() != 4 or controllers.size() != player_count():
		return "invalid_config"
	if starting_player < 0 or starting_player >= player_count():
		return "invalid_config"
	if turn_limit not in [0, 15, 30, 60, 120] or blitz_minutes not in [1, 3, 5]:
		return "invalid_config"
	for value in names:
		if not value is String:
			return "invalid_config"
	for value in controllers:
		if value not in CONTROLLERS:
			return "invalid_config"
	return ""

func display_name(player: int) -> String:
	if controllers[player] != "Human":
		return IDENTITIES[player]
	var cleaned = ""
	var expression = RegEx.new()
	expression.compile("^[^\\p{C}\\p{Z}]$|^ $")
	for character in names[player]:
		# Match Python str.isprintable(), including Unicode separators/controls.
		if expression.search(character) != null:
			cleaned += character
	cleaned = cleaned.strip_edges().left(12)
	return IDENTITIES[player] if cleaned.is_empty() else cleaned

func to_dict() -> Dictionary:
	return {"mode": mode, "names": names.duplicate(), "controllers": controllers.duplicate(),
		"random_start": random_start, "starting_player": starting_player,
		"turn_limit": turn_limit, "blitz_minutes": blitz_minutes}

func copy() -> GridlockMatchConfig:
	var config = new()
	var data = to_dict()
	for key in data:
		config.set(key, data[key])
	return config
