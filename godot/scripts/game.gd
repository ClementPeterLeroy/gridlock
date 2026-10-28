extends Node3D

@onready var camera: Camera3D = $Camera3D

var camera_positions = {
	"classic": Vector3(0, 18, 3),
	"isometric": Vector3(11, 13, 11),
	"cinematic": Vector3(10, 7, 12)
}

var camera_sizes = {
	"classic": 13.5,
	"isometric": 15.0,
	"cinematic": 17.0
}

var camera_tween: Tween


func _ready():
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true

	set_camera_view("isometric", false)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:

		if event.keycode == KEY_1:
			set_camera_view("classic")

		elif event.keycode == KEY_2:
			set_camera_view("isometric")

		elif event.keycode == KEY_3:
			set_camera_view("cinematic")


func set_camera_view(view_name: String, animate: bool = true):

	if not camera_positions.has(view_name):
		return

	var target_position = camera_positions[view_name]
	var target_size = camera_sizes[view_name]

	if camera_tween:
		camera_tween.kill()

	if not animate:
		camera.position = target_position
		camera.look_at(Vector3.ZERO, Vector3.UP)
		camera.size = target_size
		return

	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.set_trans(Tween.TRANS_SINE)
	camera_tween.set_ease(Tween.EASE_IN_OUT)

	camera_tween.tween_property(
		camera,
		"position",
		target_position,
		0.8
	)

	camera_tween.tween_property(
		camera,
		"size",
		target_size,
		0.8
	)

	var target_transform = camera.transform.looking_at(
		Vector3.ZERO,
		Vector3.UP
	)

	var target_rotation = Transform3D(
		Basis.looking_at(
			Vector3.ZERO - target_position,
			Vector3.UP
		),
		target_position
	).basis.get_rotation_quaternion()

	camera_tween.tween_property(
		camera,
		"quaternion",
		target_rotation,
		0.8
	)
