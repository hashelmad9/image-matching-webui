## A single local player: movement, aiming, shooting, damage and respawn.
##
## Collision is handled by CharacterBody3D.move_and_slide(), so walls and cover
## are solved by the physics engine rather than by hand.
class_name Player
extends CharacterBody3D

## Emitted when this player is killed. `killer` may be null if the death was
## not caused by another player.
signal died(victim: Player, killer: Player)
## Emitted when the trigger fires. The game spawns the projectile, so the
## player does not need to know where projectiles live in the scene tree.
signal fired(shooter: Player, origin: Vector3, direction: Vector3)

@onready var _mesh: MeshInstance3D = $Mesh

## Stable identity. Picks the colour and spawn point, and survives other
## players leaving. This is NOT the split-screen slot.
var index := 0
## Joypad id, or Config.KEYBOARD_DEVICE for the keyboard seat.
var device := Config.KEYBOARD_DEVICE
var health := Config.PLAYER_MAX_HEALTH
var score := 0
## Facing angle in radians about +Y, smoothed toward the aim stick.
var yaw := 0.0
var is_dead := false

var _fire_cooldown := 0.0
var _respawn_countdown := 0.0


func _ready() -> void:
	collision_layer = Config.LAYER_PLAYERS
	# Collide with the arena and with other players.
	collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS
	_apply_colour()
	_move_to_spawn()


## Called by the game immediately after instancing, before the node enters the
## tree, so the first frame already has the right identity.
func setup(player_index: int, input_device: int) -> void:
	index = player_index
	device = input_device


func _physics_process(delta: float) -> void:
	if is_dead:
		_respawn_countdown -= delta
		if _respawn_countdown <= 0.0:
			_respawn()
		return

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	var input := PlayerInput.read(device)
	_update_facing(input, delta)
	_update_movement(input, delta)
	_update_firing(input)


func _update_facing(input: PlayerInput, delta: float) -> void:
	# The aim stick wins; otherwise face the direction of travel so a player is
	# never left running backwards.
	var target_yaw := yaw
	if input.aim_axis != Vector2.ZERO:
		target_yaw = PlayerInput.yaw_from_stick(input.aim_axis)
	elif input.move_axis != Vector2.ZERO:
		target_yaw = PlayerInput.yaw_from_stick(input.move_axis)
	else:
		return

	# Framerate-independent smoothing along the shortest path around the circle.
	var blend := 1.0 - exp(-Config.PLAYER_TURN_RATE * delta)
	yaw = lerp_angle(yaw, target_yaw, blend)
	rotation.y = yaw


func _update_movement(input: PlayerInput, delta: float) -> void:
	# Movement is camera-relative, and the camera shares the player's yaw, so
	# pushing forward always moves the way the player faces.
	var direction := Basis(Vector3.UP, yaw) * Vector3(input.move_axis.x, 0.0, -input.move_axis.y)
	velocity.x = direction.x * Config.PLAYER_SPEED
	velocity.z = direction.z * Config.PLAYER_SPEED

	# Gravity keeps the body settled on the floor; nothing here jumps.
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= Config.GRAVITY * delta

	move_and_slide()

	# The boundary walls are solid, but clamping as well means a physics
	# glitch can never put a player outside the arena.
	var limit := Config.ARENA_HALF_EXTENT - Config.PLAYER_RADIUS
	global_position.x = clampf(global_position.x, -limit, limit)
	global_position.z = clampf(global_position.z, -limit, limit)


func _update_firing(input: PlayerInput) -> void:
	if not input.firing or _fire_cooldown > 0.0:
		return
	_fire_cooldown = Config.FIRE_COOLDOWN

	var direction := forward()
	var origin := global_position + direction * Config.MUZZLE_FORWARD
	origin.y = Config.MUZZLE_HEIGHT
	fired.emit(self, origin, direction)


## The direction this player faces. A zero-yaw node faces -Z.
func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD


func take_damage(amount: int, attacker: Player) -> void:
	if is_dead:
		return
	health -= amount
	if health > 0:
		return
	health = 0
	_die(attacker)


func _die(killer: Player) -> void:
	is_dead = true
	_respawn_countdown = Config.RESPAWN_SECONDS
	visible = false
	# Stop colliding while down, so corpses do not block the arena.
	set_collision_layer_value(Config.LAYER_PLAYERS, false)
	velocity = Vector3.ZERO
	died.emit(self, killer)


func _respawn() -> void:
	is_dead = false
	health = Config.PLAYER_MAX_HEALTH
	visible = true
	set_collision_layer_value(Config.LAYER_PLAYERS, true)
	_move_to_spawn()


func _move_to_spawn() -> void:
	global_position = Config.spawn_point(index)
	# Face the middle of the arena rather than an arbitrary axis.
	var to_centre := Vector2(-global_position.x, global_position.z).normalized()
	yaw = PlayerInput.yaw_from_stick(to_centre)
	rotation.y = yaw
	velocity = Vector3.ZERO


func _apply_colour() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Config.player_color(index)
	material.roughness = 0.6
	_mesh.material_override = material
