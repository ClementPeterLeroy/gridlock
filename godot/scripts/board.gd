extends Node3D

const BOARD_SIZE = 9
const CELL_SIZE = 1.0
const CELL_GAP = 0.12
const TILE_SCENE = preload("res://assets/models/tile.glb")

var light_wood = Color("#C8A477")
var dark_wood = Color("#B58B5D")
var frame_wood = Color("#654321")

var move_overlays: Node3D
var active_ring: MeshInstance3D


func _ready():
	create_board_squares()
	create_indicators()


static func cell_position(square: Vector2i) -> Vector3:
	return Vector3(square.x - 4, 0, square.y - 4)


static func wall_position(anchor: Vector2i) -> Vector3:
	return Vector3(anchor.x - 3.5, 0, anchor.y - 3.5)


func create_indicators() -> void:
	move_overlays = Node3D.new()
	move_overlays.name = "LegalMoves"
	add_child(move_overlays)
	active_ring = MeshInstance3D.new()
	active_ring.name = "ActivePlayer"
	var ring = TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.34
	ring.rings = 24
	ring.ring_segments = 12
	active_ring.mesh = ring
	active_ring.scale.y = 0.3
	active_ring.material_override = overlay_material(Color("#F9D55E"))
	active_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(active_ring)
	active_ring.hide()


static func overlay_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func show_legal_moves(squares: Array) -> void:
	for child in move_overlays.get_children():
		child.free()
	var material = overlay_material(Color(0.20, 0.85, 0.36, 0.42))
	for square in squares:
		var overlay = MeshInstance3D.new()
		overlay.name = "Move_%d_%d" % [square.y, square.x]
		var plane = PlaneMesh.new()
		plane.size = Vector2(0.76, 0.76)
		overlay.mesh = plane
		overlay.material_override = material
		overlay.position = cell_position(square) + Vector3(0, 0.128, 0)
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		move_overlays.add_child(overlay)


func show_active_player(square: Variant) -> void:
	active_ring.visible = square != null
	if square != null:
		active_ring.position = cell_position(square) + Vector3(0, 0.145, 0)


func create_material(color: Color) -> StandardMaterial3D:

	var material = StandardMaterial3D.new()

	material.albedo_color = color
	material.roughness = 0.65
	material.metallic = 0.0

	return material


func create_box(
	box_size: Vector3,
	box_position: Vector3,
	material: Material
):

	var mesh_instance = MeshInstance3D.new()

	var box_mesh = BoxMesh.new()
	box_mesh.size = box_size

	mesh_instance.mesh = box_mesh
	mesh_instance.position = box_position
	mesh_instance.material_override = material

	add_child(mesh_instance)

	return mesh_instance


func create_board_base():

	create_box(
		Vector3(9.8, 0.45, 9.8),
		Vector3(0, -0.30, 0),
	create_material(frame_wood)
)


func create_board_squares():

	var tiles_container = Node3D.new()
	tiles_container.name = "Tiles"
	add_child(tiles_container)

	var light_material = create_material(light_wood)
	var dark_material = create_material(dark_wood)

	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):

			# Instantiate Blender tile
			var tile = TILE_SCENE.instantiate()
			tile.name = "Tile_%d_%d" % [row, col]

			# Position the tile using its bottom-centre origin
			tile.position = Vector3(
				col - 4,
				-0.08,
				row - 4
			)

			# Apply alternating wood colours
			var tile_material = light_material

			if (row + col) % 2 == 1:
				tile_material = dark_material
			
			apply_material_to_meshes(tile, tile_material)

			tiles_container.add_child(tile)


func apply_material_to_meshes(node: Node, material: Material):

	if node is MeshInstance3D:
		node.material_override = material

	for child in node.get_children():
		apply_material_to_meshes(child, material)

func create_board_frame():

	var frame_material = create_material(frame_wood)

	# Top border
	create_box(
		Vector3(10.0, 0.35, 0.35),
		Vector3(0, 0.02, -4.7),
		frame_material
	)

	# Bottom border
	create_box(
		Vector3(10.0, 0.35, 0.35),
		Vector3(0, 0.02, 4.7),
		frame_material
	)

	# Left border
	create_box(
		Vector3(0.35, 0.35, 9.4),
		Vector3(-4.7, 0.02, 0),
		frame_material
	)

	# Right border
	create_box(
		Vector3(0.35, 0.35, 9.4),
		Vector3(4.7, 0.02, 0),
		frame_material
	)
