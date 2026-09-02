## A horde enemy: chases the nearest player, swings when close, dies to shots.
##
## Deliberately simple. It walks straight at its target and sidesteps briefly
## when it hits a wall, which is enough for an open arena with a few blocks of
## cover. Anything smarter is a pathfinding job for later.
class_name Enemy
extends CharacterBody3D

signal died(enemy: Enemy, killer: Node)

@onready var _character: Node3D = $Character

## Stat blocks. A runner is fragile and quick; a brute is slow and hits hard.
const KINDS := {
	"walker": {"health": 1.0, "speed": 1.0, "damage": 1.0, "scale": 0.5, "tint": Color(0.8, 0.95, 0.8)},
	"runner": {"health": 0.5, "speed": 1.7, "damage": 0.6, "scale": 0.42, "tint": Color(1.0, 0.85, 0.6)},
	"brute": {"health": 3.0, "speed": 0.65, "damage": 2.2, "scale": 0.68, "tint": Color(0.7, 0.6, 0.9)},
}

var kind := "walker"
var health := Config.ENEMY_HEALTH
var speed := Config.ENEMY_SPEED
var damage := Config.ENEMY_DAMAGE

var _attack_cooldown := 0.0
var _detour_time := 0.0
var _detour_sign := 1.0
var _dead := false


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Config.LAYER_ENEMIES
	collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS | Config.LAYER_ENEMIES
	var skin: String = Config.ENEMY_SKINS[randi() % Config.ENEMY_SKINS.size()]
	var stats: Dictionary = KINDS[kind]
	CharacterRig.apply_skin(_character, skin, stats["tint"])
	_character.scale = Vector3.ONE * float(stats["scale"])
	var animation_player := CharacterRig.build_animation_player(_character)
	if animation_player != null and animation_player.has_animation("run"):
		animation_player.play("run")


## Sets the stat block. Call before adding to the tree; `wave_speed` is the
## base speed for the current wave, which the kind then scales.
func configure(new_kind: String, wave_speed: float) -> void:
	kind = new_kind
	var stats: Dictionary = KINDS[kind]
	health = int(Config.ENEMY_HEALTH * float(stats["health"]))
	speed = wave_speed * float(stats["speed"])
	damage = int(Config.ENEMY_DAMAGE * float(stats["damage"]))


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
			target.take_damage(damage, self)
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
