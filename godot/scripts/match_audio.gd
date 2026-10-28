extends Node
## Reuses the Classic placeholders. Music keeps playing across pages and matches.

var music_volume = 0.2
var effects_volume = 0.5
var music: AudioStreamPlayer
var effects: Dictionary = {}
var playback_enabled = false

func _ready() -> void:
	# Dummy has no device/mixer to consume playback (headless tests or no audio device).
	playback_enabled = AudioServer.get_driver_name() != "Dummy"
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/simple_happy_loop.mp3").duplicate()
	music.stream.loop = true
	add_child(music)
	for event in ["move", "wall", "victory"]:
		var player = AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/electronic_victory_sound.mp3" if event == "victory" \
			else "res://assets/audio/simple_move.wav")
		player.pitch_scale = 0.75 if event == "wall" else 1.0
		add_child(player)
		effects[event] = player
	set_volume("music", music_volume)
	set_volume("effects", effects_volume)
	if playback_enabled:
		music.play()

func set_volume(category: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	var decibels = linear_to_db(value) if value > 0 else -80.0
	if category == "music":
		music_volume = value
		music.volume_db = decibels
	else:
		effects_volume = value
		for player in effects.values():
			player.volume_db = decibels

func play_effect(event: String) -> void:
	if playback_enabled and effects_volume > 0 and effects.has(event):
		effects[event].play()

func stop_all() -> void:
	for player in get_children():
		player.stop()
		player.stream = null

func _exit_tree() -> void:
	stop_all()
	effects.clear()
