## A single shot. Flies in a straight line at a fixed height until it hits
## something, leaves the arena, or times out.
##
## An Area3D is used rather than a physics body because projectiles should
## never push anything around — they only need to detect what they touch.
## The game mode can intercept hits (the ball game kicks the ball with them)
## and decide whether shots harm other players.
class_name Projectile
extends Area3D

var direction := Vector3.FORWARD
var shooter: Player = null
var damage := Config.PROJECTILE_DAMAGE
var speed := Config.PROJECTILE_SPEED
var lifetime := Config.PROJECTILE_LIFETIME
## False in co-op modes: shots pass straight through teammates.
var friendly_fire := true
## Optional `(projectile, body) -> bool`. Returning true means the mode
## handled the hit and the shot is spent.
var hit_handler := Callable()
## Bounces off cover left before the shot is spent.
var bounces_left := Config.PROJECTILE_BOUNCES
## Colour of the tracer, also used for its sparks.
var colour := Color.WHITE

@onready var _mesh: MeshInstance3D = $Mesh

## One material per tint, shared by every tracer of that colour. Four players
## firing six shots a second would otherwise allocate a material per shot.
static var _materials: Dictionary = {}

var _tint := Color.WHITE
var _remaining_life := Config.PROJECTILE_LIFETIME
## Guards against a second hit being processed in the same frame as the first,
## and against acting after queue_free() has already been called.
var _consumed := false


func _ready() -> void:
	add_to_group("projectiles")
	# Detect the arena, players, enemies and the ball; occupy no layer itself.
	collision_layer = 0
	collision_mask = (
		Config.LAYER_WORLD | Config.LAYER_PLAYERS | Config.LAYER_ENEMIES | Config.LAYER_BALL
	)
	body_entered.connect(_on_body_entered)
	_remaining_life = lifetime
	_apply_tint()


## Sets the tracer colour. Safe to call before the node enters the tree; the
## colour is applied on ready.
func tint(new_colour: Color) -> void:
	_tint = new_colour
	colour = new_colour
	if is_node_ready():
		_apply_tint()


func _apply_tint() -> void:
	_mesh.material_override = _material_for(_tint)


static func _material_for(colour: Color) -> StandardMaterial3D:
	if _materials.has(colour):
		return _materials[colour]
	var material := StandardMaterial3D.new()
	# Emission above 1.0 is what pushes the tracer past the environment's glow
	# threshold; a plain albedo colour caps at 1.0 and would never bloom.
	material.albedo_color = colour.darkened(0.6)
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 6.0
	_materials[colour] = material
	return material


func _physics_process(delta: float) -> void:
	if _consumed:
		return

	_remaining_life -= delta
	if _remaining_life <= 0.0:
		_consume()
		return

	# Cover is handled by a ray along this frame's travel rather than by the
	# overlap shape: a ray gives the surface normal for the bounce and cannot
	# tunnel through a thin wall at high speed.
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, Config.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var world := get_parent() as Node3D
		if world != null:
			Effects.spark(world, hit["position"], colour)
		Sfx.play("wall")
		if bounces_left <= 0:
			_consume()
			return
		bounces_left -= 1
		var normal: Vector3 = hit["normal"]
		direction = direction.bounce(normal)
		direction.y = 0.0
		direction = direction.normalized()
		global_position = hit["position"] + normal * (Config.PROJECTILE_RADIUS + 0.05)
		return

	global_position = to

	# A shot that somehow escapes the arena is cheaper to drop than to track.
	var bound := Config.ARENA_HALF_EXTENT + 2.0
	if absf(global_position.x) > bound or absf(global_position.z) > bound:
		_consume()


func _on_body_entered(body: Node3D) -> void:
	if _consumed or body == shooter:
		return
	if hit_handler.is_valid() and hit_handler.call(self, body):
		_consume()
		return
	if body is StaticBody3D:
		return  # Cover is resolved by the travel ray, which knows the normal.
	if body is Player and not friendly_fire:
		return  # Pass through a teammate rather than wasting the shot.
	if body.has_method("take_damage"):
		body.take_damage(damage, shooter)
		Sfx.play("hit")
		var world := get_parent() as Node3D
		if world != null:
			Effects.spark(world, global_position, colour)
	_consume()


func _consume() -> void:
	_consumed = true
	queue_free()
