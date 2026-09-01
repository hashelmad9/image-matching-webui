## A single shot. Flies in a straight line at a fixed height until it hits
## something, leaves the arena, or times out.
##
## An Area3D is used rather than a physics body because projectiles should
## never push anything around — they only need to detect what they touch.
class_name Projectile
extends Area3D

var direction := Vector3.FORWARD
var shooter: Player = null
var damage := Config.PROJECTILE_DAMAGE

@onready var _mesh: MeshInstance3D = $Mesh

var _tint := Color.WHITE
var _remaining_life := Config.PROJECTILE_LIFETIME
## Guards against a second hit being processed in the same frame as the first,
## and against acting after queue_free() has already been called.
var _consumed := false


func _ready() -> void:
	# Detect the arena and players, but occupy no layer of its own.
	collision_layer = 0
	collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS
	body_entered.connect(_on_body_entered)
	_apply_tint()


## Sets the tracer colour. Safe to call before the node enters the tree; the
## colour is applied on ready.
func tint(colour: Color) -> void:
	_tint = colour
	if is_node_ready():
		_apply_tint()


func _apply_tint() -> void:
	var material := StandardMaterial3D.new()
	# Emission above 1.0 is what pushes the tracer past the environment's glow
	# threshold; a plain albedo colour caps at 1.0 and would never bloom.
	material.albedo_color = _tint.darkened(0.6)
	material.emission_enabled = true
	material.emission = _tint
	material.emission_energy_multiplier = 6.0
	_mesh.material_override = material


func _physics_process(delta: float) -> void:
	if _consumed:
		return

	_remaining_life -= delta
	if _remaining_life <= 0.0:
		_consume()
		return

	global_position += direction * Config.PROJECTILE_SPEED * delta

	# A shot that somehow escapes the arena is cheaper to drop than to track.
	var bound := Config.ARENA_HALF_EXTENT + 2.0
	if absf(global_position.x) > bound or absf(global_position.z) > bound:
		_consume()


func _on_body_entered(body: Node3D) -> void:
	if _consumed or body == shooter:
		return
	if body is Player:
		(body as Player).take_damage(damage, shooter)
	_consume()


func _consume() -> void:
	_consumed = true
	queue_free()
