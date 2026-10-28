extends Node3D

@export var wall_color: Color = Color("#E8D9B5")


func _ready():
	apply_material()


func apply_material():
	var material = StandardMaterial3D.new()

	material.albedo_color = wall_color

	# Slightly polished finish
	material.roughness = 0.38
	material.metallic = 0.0

	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
