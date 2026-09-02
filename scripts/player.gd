## A single local player: movement, aiming, shooting, damage and recovery.
##
## Collision is handled by CharacterBody3D.move_and_slide(), so walls and cover
## are solved by the physics engine rather than by hand. What happens after a
## death is *not* decided here: the game mode chooses between a timed respawn
## (versus modes) and staying down until a teammate arrives (horde).
class_name Player
extends CharacterBody3D

## `killer` is whatever dealt the final blow: a Player, an Enemy, or null.
signal died(victim: Player, killer: Node)
## The game spawns the projectile, so the player does not need to know where
## projectiles live in the scene tree.
signal fired(shooter: Player, origin: Vector3, direction: Vector3)

@onready var _character: Node3D = $Character

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
## Down but revivable. Distinct from being hidden and awaiting a respawn.
var is_downed := false
## Cleared by the hub during countdowns and results.
var controls_enabled := true
## Set by the current mode; tag turns shooting off entirely.
var can_fire := true
var speed_multiplier := 1.0
## Mode-provided HUD line. Empty falls back to health and kills.
var hud_status := ""

var _fire_cooldown := 0.0
var _respawn_countdown := -1.0
var _animation_player: AnimationPlayer = null
var _current_animation := ""
var _material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("players")
	collision_layer = Config.LAYER_PLAYERS
	collision_mask = (
		Config.LAYER_WORLD | Config.LAYER_PLAYERS | Config.LAYER_ENEMIES | Config.LAYER_BALL
	)
	_material = CharacterRig.apply_skin(
		_character, Config.player_skin(index), Config.player_tint(index)
	)
	_animation_player = CharacterRig.build_animation_player(_character)
	_move_to_spawn()


## Called by the game immediately after instancing, before the node enters the
## tree, so the first frame already has the right identity.
func setup(player_index: int, input_device: int) -> void:
	index = player_index
	device = input_device


func _physics_process(delta: float) -> void:
	if is_dead:
		if _respawn_countdown > 0.0:
			_respawn_countdown -= delta
			if _respawn_countdown <= 0.0:
				respawn()
		_play("idle")
		return

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	var input := PlayerInput.read(device) if controls_enabled else PlayerInput.new()
	_update_facing(input, delta)
	_update_movement(input, delta)
	if can_fire:
		_update_firing(input)
	_play("run" if input.move_axis != Vector2.ZERO else "idle")


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
	var speed := Config.PLAYER_SPEED * speed_multiplier
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Gravity keeps the body settled on the floor; nothing here jumps.
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= Config.GRAVITY * delta

	move_and_slide()

	# CharacterBody3D does not push rigid bodies on its own. Shoving the ball
	# by running into it is the whole point of the ball game.
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider()
		if body is RigidBody3D:
			(body as RigidBody3D).apply_central_impulse(
				-collision.get_normal() * Config.BALL_PUSH * delta
			)

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


func _play(animation: String) -> void:
	if _animation_player == null or animation == _current_animation:
		return
	if _animation_player.has_animation(animation):
		_current_animation = animation
		_animation_player.play(animation)


## The direction this player faces. A zero-yaw node faces -Z.
func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD


func take_damage(amount: int, attacker: Node) -> void:
	if is_dead:
		return
	health -= amount
	if health > 0:
		return
	health = 0
	is_dead = true
	# Stop colliding while down, so bodies do not block the arena.
	collision_layer = 0
	velocity = Vector3.ZERO
	died.emit(self, attacker)


## Vanish and come back at a spawn point after a delay. Versus modes.
func schedule_respawn(seconds: float) -> void:
	visible = false
	is_downed = false
	_respawn_countdown = seconds


## Stay on the field, lying down, until a teammate revives you. Horde.
func set_downed() -> void:
	is_downed = true
	visible = true
	_respawn_countdown = -1.0
	_character.rotation.x = -PI * 0.45


## Get back up where you fell.
func revive_in_place() -> void:
	_restore()


## Get back up at your spawn point.
func respawn() -> void:
	_restore()
	_move_to_spawn()


## Full reset between rounds: alive, healthy, unmarked, at spawn, score zero.
func reset_for_round() -> void:
	_restore()
	score = 0
	hud_status = ""
	speed_multiplier = 1.0
	can_fire = true
	highlight(false)
	_move_to_spawn()


## Glow in the player's colour. Tag uses it to mark who is "it".
func highlight(on: bool) -> void:
	if _material == null:
		return
	_material.emission_enabled = on
	_material.emission = Config.player_color(index)
	_material.emission_energy_multiplier = 1.5 if on else 0.0


func _restore() -> void:
	is_dead = false
	is_downed = false
	health = Config.PLAYER_MAX_HEALTH
	visible = true
	collision_layer = Config.LAYER_PLAYERS
	_respawn_countdown = -1.0
	_character.rotation.x = 0.0
	velocity = Vector3.ZERO


func _move_to_spawn() -> void:
	global_position = Config.spawn_point(index)
	# Face the middle of the arena rather than an arbitrary axis.
	var to_centre := Vector2(-global_position.x, global_position.z).normalized()
	yaw = PlayerInput.yaw_from_stick(to_centre)
	rotation.y = yaw
	velocity = Vector3.ZERO
