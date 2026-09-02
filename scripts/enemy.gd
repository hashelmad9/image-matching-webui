## A horde enemy: chases the nearest player, swings when close, dies to shots.
##
## Deliberately simple. It walks straight at its target and sidesteps briefly
## when it hits a wall, which is enough for an open arena with a few blocks of
## cover. Anything smarter is a pathfinding job for later.
class_name Enemy
extends CharacterBody3D

signal died(enemy: Enemy, killer: Node)

@onready var _character: Node3D = $Character

var health := Config.ENEMY_HEALTH
var speed := Config.ENEMY_SPEED

var _attack_cooldown := 0.0
var _detour_time := 0.0
var _detour_sign := 1.0
var _dead := false


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Config.LAYER_ENEMIES
	collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS | Config.LAYER_ENEMIES
	var skin: String = Config.ENEMY_SKINS[randi() % Config.ENEMY_SKINS.size()]
	CharacterRig.apply_skin(_character, skin, Color(0.8, 0.95, 0.8))
	var animation_player := CharacterRig.build_animation_player(_character)
	if animation_player != null and animation_player.has_animation("run"):
		animation_player.play("run")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_detour_time = maxf(0.0, _detour_time - delta)

	var target := _nearest_target()
	if target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target / maxf(distance, 0.001)
	# A zero-yaw node faces -Z; see PlayerInput.yaw_from_stick for the maths.
	rotation.y = atan2(-direction.x, -direction.z)

	if distance <= Config.ENEMY_ATTACK_RANGE:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_cooldown <= 0.0:
			_attack_cooldown = Config.ENEMY_ATTACK_COOLDOWN
			target.take_damage(Config.ENEMY_DAMAGE, self)
	else:
		if _detour_time > 0.0:
			direction = Vector3(-direction.z * _detour_sign, 0.0, direction.x * _detour_sign)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	_apply_gravity(delta)
	move_and_slide()

	# Walked into cover: slide along it for a moment instead of grinding.
	if is_on_wall() and _detour_time <= 0.0:
		_detour_time = 0.5
		_detour_sign = 1.0 if randf() < 0.5 else -1.0


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= Config.GRAVITY * delta


func _nearest_target() -> Player:
	var best: Player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or player.is_dead:
			continue
		var d := global_position.distance_squared_to(player.global_position)
		if d < best_distance:
			best_distance = d
			best = player
	return best


func take_damage(amount: int, attacker: Node) -> void:
	if _dead:
		return
	health -= amount
	if health > 0:
		return
	_dead = true
	collision_layer = 0
	died.emit(self, attacker)
	queue_free()
