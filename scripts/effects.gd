## Short-lived visual punctuation: muzzle flashes, sparks, and the materialise
## pop on respawn. Everything here is a mesh that shrinks and frees itself,
## which costs nothing to author and reads clearly at split-screen size.
class_name Effects
extends RefCounted


static func muzzle_flash(world: Node3D, at: Vector3, colour: Color) -> void:
	_burst(world, at, colour, 0.35, 0.08)


static func spark(world: Node3D, at: Vector3, colour: Color) -> void:
	_burst(world, at, colour, 0.28, 0.16)


static func _burst(world: Node3D, at: Vector3, colour: Color, radius: float, seconds: float) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 8.0
	mesh.material_override = material
	mesh.position = at
	mesh.add_to_group("effects")
	world.add_child(mesh)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3.ZERO, seconds)
	tween.tween_callback(mesh.queue_free)
