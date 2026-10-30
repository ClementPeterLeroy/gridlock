extends Control
## Official video, with a short native logo fallback and bounded failure recovery.

signal completed
var video_path = "res://assets/branding/gridlock_intro.ogv"
var logo_path = "res://assets/branding/gridlock_logo.png"
var player: VideoStreamPlayer
var logo: TextureRect
var animation: Tween
var elapsed = 0.0
var finished = false
var fallback_active = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = ColorRect.new()
	background.color = Color("#15191F")
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(video_path):
		var stream = load(video_path)
		if stream is VideoStream:
			player = VideoStreamPlayer.new()
			player.expand = true
			player.stream = stream
			var frame = AspectRatioContainer.new()
			frame.ratio = 16.0 / 9.0
			frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
			add_child(frame)
			frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			frame.add_child(player)
			player.finished.connect(finish)
			player.play()
			return
	start_fallback()

func start_fallback() -> void:
	if fallback_active: return
	fallback_active = true
	push_warning("Intro video unavailable; using native branding fallback.")
	if player != null:
		player.stop()
		player.queue_free()
		player = null
	var center = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo = TextureRect.new()
	logo.custom_minimum_size = Vector2(640, 300)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(logo_path): logo.texture = load(logo_path) as Texture2D
	center.add_child(logo)
	if logo.texture == null:
		var title = Label.new()
		title.text = "GRIDLOCK"
		title.add_theme_font_size_override("font_size", 48)
		center.add_child(title)
	logo.modulate.a = 0
	animation = create_tween()
	animation.tween_property(logo, "modulate:a", 1.0, 0.5)
	animation.tween_interval(1.0)
	animation.tween_property(logo, "modulate:a", 0.0, 0.3)
	animation.finished.connect(finish)

func _process(delta: float) -> void:
	elapsed += delta
	if not fallback_active and elapsed > 1 and player != null and not player.is_playing(): start_fallback()
	if elapsed > 8:
		push_warning("Startup playback exceeded its watchdog; continuing to Main Menu.")
		finish()

func finish() -> void:
	if finished: return
	finished = true
	if player != null: player.stop()
	if animation != null and animation.is_valid(): animation.kill()
	completed.emit()
	queue_free()
