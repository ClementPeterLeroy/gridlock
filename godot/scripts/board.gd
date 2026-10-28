extends Node3D

const BOARD_SIZE = 9
const CELL_SIZE = 1.0
const CELL_GAP = 0.12
const TILE_SCENE = preload("res://assets/models/tile.glb")

var light_wood = Color("#C8A477")
var dark_wood = Color("#B58B5D")
var frame_wood = Color("#654321")


func _ready():
	create_board_squares()


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
