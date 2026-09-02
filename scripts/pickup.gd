## A weapon lying in the arena. Walk over it to take it; it comes back after
## a while at the same spot, so the map has places worth fighting over.
class_name Pickup
extends Area3D

var kind := "scatter"
var _respawn := 0.0
var _model: Node3D = null


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = Config.LAYER_PLAYERS
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Config.PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)

	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = Config.PICKUP_RADIUS
	cylinder.bottom_radius = Config.PICKUP_RADIUS
	cylinder.height = 0.05
	disc.mesh = cylinder
	disc.position.y = -Config.PICKUP_HOVER + 0.03
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.9, 0.5, 0.35)
	material.emission_enabled = true
	material.emission = Color(1, 0.85, 0.4)
	material.emission_energy_multiplier = 1.2
	disc.material_override = material
	add_child(disc)

	var packed := load(Weapons.stats(kind)["model"]) as PackedScene
	if packed != null:
		_model = packed.instantiate()
		_model.scale = Vector3.ONE * Config.WEAPON_MODEL_SCALE * 1.6
		add_child(_model)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _respawn > 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			_show(true)
		return
	if _model != null:
		_model.rotate_y(delta * 1.8)
		_model.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if _respawn > 0.0 or not body is Player:
		return
	var player := body as Player
	if player.is_dead:
		return
	player.equip(kind)
	_show(false)
	_respawn = Config.PICKUP_RESPAWN_SECONDS


func _show(on: bool) -> void:
	visible = on
	set_deferred("monitoring", on)


func is_available() -> bool:
	return _respawn <= 0.0
