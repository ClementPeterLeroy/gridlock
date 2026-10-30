class_name GridlockMatchConfig
extends RefCounted
## Session match options. Timing values are enforced by the gameplay engine.

const MODES = ["Versus", "Battle Royale", "Blitz", "Rise of the Machines"]
const IDENTITIES = ["Sapphire", "Crimson", "Emerald", "Violet"]
const CONTROLLERS = ["Human", "AI - Casual", "AI - Challenging"]
const NAME_LIMIT = 12
const TURN_SECONDS = [15, 30, 60, 120, 180]
const GAME_SECONDS = [60, 180, 300, 600, 900]
const TIMER_TYPES = ["Per Turn", "Per Game"]

var mode: String = "Versus"
var names: Array = IDENTITIES.duplicate()
var controllers: Array = ["Human", "Human"]
var random_start: bool = false
var starting_player: int = 0
var turn_limit: int = 0
var blitz_minutes: int = 3
var timer_type: String = "Per Turn"
var game_limit: int = 180

var timing_mode: String:
	get:
		if mode == "Versus": return "Untimed"
		if mode == "Blitz": return "Blitz"
		return timer_type if mode == "Battle Royale" else ("Per Turn" if turn_limit else "Untimed")

static func for_mode(value: String) -> GridlockMatchConfig:
	var config = new()
	config.mode = value
	if value == "Battle Royale":
		config.controllers = ["Human", "AI - Casual", "AI - Casual", "AI - Casual"]
		config.turn_limit = 30
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
	if turn_limit not in [0] + TURN_SECONDS or blitz_minutes not in [1, 3, 5]:
		return "invalid_config"
	if timer_type not in TIMER_TYPES or game_limit not in [0] + GAME_SECONDS:
		return "invalid_config"
	for value in names:
		if not value is String:
			return "invalid_config"
	for player in range(player_count()):
		if clean_name(names[player]).is_empty():
			return "invalid_name"
	if mode == "Battle Royale" and ((timer_type == "Per Turn" and turn_limit == 0) or (timer_type == "Per Game" and game_limit == 0)):
		return "invalid_config"
	for value in controllers:
		if value not in CONTROLLERS:
			return "invalid_config"
	return ""

static func clean_name(value: String) -> String:
	var cleaned = ""
	var expression = RegEx.new()
	expression.compile("^[^\\p{C}\\p{Z}]$|^ $")
	for character in value:
		# Match Python str.isprintable(), including Unicode separators/controls.
		if expression.search(character) != null and character not in ["[", "]", "<", ">"]:
			cleaned += character
	return cleaned.strip_edges().left(NAME_LIMIT)

func display_name(player: int) -> String:
	var cleaned = clean_name(names[player])
	return IDENTITIES[player] if cleaned.is_empty() else cleaned

func resolved() -> GridlockMatchConfig:
	var config = copy()
	if mode == "Versus":
		# Ignore obsolete saved countdowns even for callers outside the setup UI.
		config.turn_limit = 0
		config.game_limit = 0
	elif mode == "Battle Royale":
		if timer_type == "Per Game":
			config.turn_limit = 0
		else:
			config.game_limit = 0
	return config

func to_dict() -> Dictionary:
	return {"mode": mode, "names": names.duplicate(), "controllers": controllers.duplicate(),
		"random_start": random_start, "starting_player": starting_player,
		"turn_limit": turn_limit, "blitz_minutes": blitz_minutes,
		"timer_type": timer_type, "game_limit": game_limit}

func copy() -> GridlockMatchConfig:
	var config = new()
	var data = to_dict()
	for key in data:
		config.set(key, data[key])
	return config
