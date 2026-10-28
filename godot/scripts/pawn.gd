extends Node3D

@export var player_color: Color = Color("#345B9A")

@onready var pawn_model: Node3D = $PawnModel


func _ready():
	apply_material()


func apply_material():
	var material = StandardMaterial3D.new()

	# Colour
	material.albedo_color = Color(
		player_color.r,
		player_color.g,
		player_color.b,
		1.0
	)

	# Matte painted wood
	material.metallic = 0.0
	material.roughness = 0.62
	material.metallic_specular = 0.35

	# Explicitly opaque
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	# No emission
	material.emission_enabled = false

	apply_to_meshes(pawn_model, material)


func apply_to_meshes(node: Node, material: Material):
	if node is MeshInstance3D:
		node.material_override = material

	for child in node.get_children():
		apply_to_meshes(child, material)
