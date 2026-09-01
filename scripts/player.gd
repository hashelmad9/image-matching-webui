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

## Kenney ships each clip as its own FBX, so they are lifted out and re-hosted
## on a single AnimationPlayer built against our skeleton.
const ANIMATION_SOURCES := {
	"idle": ["res://assets/characters/animations/idle.fbx", "Root|Idle"],
	"run": ["res://assets/characters/animations/run.fbx", "Root|Run"],
}

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

var _fire_cooldown := 0.0
var _respawn_countdown := 0.0
var _animation_player: AnimationPlayer = null
var _current_animation := ""


func _ready() -> void:
	collision_layer = Config.LAYER_PLAYERS
	# Collide with the arena and with other players.
	collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS
	_apply_skin()
	_setup_animations()
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
	_update_animation(input)


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
	collision_layer = 0
	velocity = Vector3.ZERO
	died.emit(self, killer)


func _respawn() -> void:
	is_dead = false
	health = Config.PLAYER_MAX_HEALTH
	visible = true
	collision_layer = Config.LAYER_PLAYERS
	_move_to_spawn()


func _move_to_spawn() -> void:
	global_position = Config.spawn_point(index)
	# Face the middle of the arena rather than an arbitrary axis.
	var to_centre := Vector2(-global_position.x, global_position.z).normalized()
	yaw = PlayerInput.yaw_from_stick(to_centre)
	rotation.y = yaw
	velocity = Vector3.ZERO


func _update_animation(input: PlayerInput) -> void:
	if _animation_player == null:
		return
	var wanted := "run" if input.move_axis != Vector2.ZERO else "idle"
	if wanted == _current_animation or not _animation_player.has_animation(wanted):
		return
	_current_animation = wanted
	_animation_player.play(wanted)


func _apply_skin() -> void:
	var mesh := _find_mesh(_character)
	if mesh == null:
		push_warning("player %d: no mesh found under Character" % index)
		return
	var texture := load(Config.player_skin(index)) as Texture2D
	if texture == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 0.8
	mesh.material_override = material


func _setup_animations() -> void:
	var library := AnimationLibrary.new()
	for name: String in ANIMATION_SOURCES:
		var source: Array = ANIMATION_SOURCES[name]
		var clip := _load_animation(source[0], source[1])
		if clip != null:
			library.add_animation(name, clip)
	if library.get_animation_list().is_empty():
		push_warning("player %d: no animations loaded" % index)
		return

	_animation_player = AnimationPlayer.new()
	# Parenting to Character means the clips' "Root/Skeleton3D:bone" track
	# paths resolve against our own skeleton without rewriting them.
	_character.add_child(_animation_player)
	_animation_player.add_animation_library("", library)


func _load_animation(path: String, clip_name: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	var source := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var clip: Animation = null
	if source != null and source.has_animation(clip_name):
		clip = source.get_animation(clip_name).duplicate()
		clip.loop_mode = Animation.LOOP_LINEAR
	scene.free()
	return clip


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
