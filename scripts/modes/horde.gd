## Co-op survival. Everyone against escalating waves; down players are revived
## by a teammate standing close. The round ends when nobody is standing.
extends GameMode

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

var wave := 0
var _to_spawn := 0
var _spawn_timer := 0.0
var _breather := 0.0
var _spawned_this_wave := 0
## Seconds of teammate contact accumulated per downed player.
var _revive_progress: Dictionary = {}


func mode_id() -> String:
	return "horde"


func title() -> String:
	return "HORDE"


func blurb() -> String:
	return "Survive the waves together. Stand by a downed friend to revive them."


func min_players() -> int:
	return 1


func round_seconds() -> float:
	return INF


func friendly_fire() -> bool:
	return false


func begin() -> void:
	wave = 0
	_breather = Config.HORDE_FIRST_WAVE_DELAY


func tick(delta: float) -> void:
	if _breather > 0.0:
		_breather -= delta
		if _breather <= 0.0:
			_start_wave()
	elif _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = Config.HORDE_SPAWN_INTERVAL
			_spawn_enemy()
	elif enemies_alive() == 0:
		# Wave cleared: everyone gets back up, then a moment to breathe.
		for player in players():
			if player.is_downed:
				player.revive_in_place()
		_breather = Config.HORDE_WAVE_BREATHER
		hub.toast_all("WAVE %d CLEARED" % wave, Color(0.6, 1, 0.6))
	_tick_revives(delta)


func _start_wave() -> void:
	wave += 1
	hub.toast_all("WAVE %d" % wave, Color(1, 0.6, 0.5))
	hub.shake_all(Config.SHAKE_FIRE)
	Sfx.play("wave")
	_to_spawn = Config.HORDE_BASE_ENEMIES + Config.HORDE_ENEMIES_PER_WAVE * (wave - 1)
	_spawned_this_wave = 0
	_spawn_timer = 0.0


func _spawn_enemy() -> void:
	_to_spawn -= 1
	_spawned_this_wave += 1
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	var wave_speed := Config.ENEMY_SPEED + Config.ENEMY_SPEED_PER_WAVE * (wave - 1)
	var total := Config.HORDE_BASE_ENEMIES + Config.HORDE_ENEMIES_PER_WAVE * (wave - 1)
	enemy.configure(kind_for_spawn(wave, _spawned_this_wave, total), wave_speed)
	enemy.position = _spawn_point()
	enemy.died.connect(_on_enemy_died)
	hub.world().add_child(enemy)
	if enemy.kind == "boss":
		hub.toast_all("BOSS INCOMING", Color(1, 0.4, 0.35))
		hub.shake_all(Config.SHAKE_DEATH)
		Sfx.play("wave")


## Which enemy the Nth spawn of a wave is. Early waves are all walkers;
## runners join from HORDE_RUNNER_WAVE, a brute every few spawns from
## HORDE_BRUTE_WAVE, and every HORDE_BOSS_EVERY waves the last spawn is a
## boss, so each wave feels different from the last.
static func kind_for_spawn(wave_number: int, ordinal: int, total: int) -> String:
	if wave_number % Config.HORDE_BOSS_EVERY == 0 and ordinal == total:
		return "boss"
	if wave_number >= Config.HORDE_BRUTE_WAVE and ordinal % Config.HORDE_BRUTE_EVERY == 0:
		return "brute"
	if wave_number >= Config.HORDE_RUNNER_WAVE and randf() < Config.HORDE_RUNNER_SHARE:
		return "runner"
	return "walker"


## A random point on the arena's edge, away from anyone still standing.
func _spawn_point() -> Vector3:
	var edge := Config.ARENA_HALF_EXTENT - 2.0
	var best := Vector3.ZERO
	var best_clearance := -1.0
	for attempt in 6:
		var along := randf_range(-edge, edge)
		var candidate: Vector3
		match randi() % 4:
			0: candidate = Vector3(along, 0.0, -edge)
			1: candidate = Vector3(along, 0.0, edge)
			2: candidate = Vector3(-edge, 0.0, along)
			_: candidate = Vector3(edge, 0.0, along)
		candidate.y = Config.PLAYER_HEIGHT * 0.5
		var clearance := INF
		for player in alive_players():
			clearance = minf(clearance, candidate.distance_to(player.global_position))
		if clearance > best_clearance:
			best_clearance = clearance
			best = candidate
		if clearance >= 8.0:
			break
	return best


func _on_enemy_died(enemy: Enemy, killer: Node) -> void:
	var points := Config.HORDE_BOSS_POINTS if enemy.kind == "boss" else 1
	if killer is Player:
		(killer as Player).score += points
	if enemy.kind == "boss":
		var who := "P%d" % ((killer as Player).index + 1) if killer is Player else "SOMEONE"
		hub.toast_all("BOSS DOWN  ·  %s  +%d" % [who, points], Color(0.6, 1, 0.6))
		hub.shake_all(Config.SHAKE_HURT)
		Sfx.play("bell")


func enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func on_player_died(victim: Player, _killer: Node) -> void:
	victim.set_downed()
	_revive_progress[victim] = 0.0
	var colour := Config.player_color(victim.index)
	for other in players():
		if other != victim:
			hub.toast(other, "P%d IS DOWN  ·  go revive them" % (victim.index + 1), colour)


func _tick_revives(delta: float) -> void:
	for player in players():
		if not player.is_downed:
			continue
		var helped := false
		for other in alive_players():
			if other.global_position.distance_to(player.global_position) <= Config.REVIVE_RANGE:
				helped = true
				break
		var progress: float = _revive_progress.get(player, 0.0)
		progress = progress + delta if helped else 0.0
		if progress >= Config.REVIVE_SECONDS:
			player.revive_in_place()
			_revive_progress.erase(player)
			hub.toast(player, "BACK UP", Color(0.6, 1, 0.6))
			Effects.spark(hub.world(), player.global_position + Vector3.UP, Config.player_color(player.index))
		else:
			_revive_progress[player] = progress


func is_over() -> bool:
	return not players().is_empty() and alive_players().is_empty()


func finish() -> String:
	var waves_cleared := maxi(wave - 1, 0)
	if enemies_alive() == 0 and _to_spawn == 0 and wave > 0:
		waves_cleared = wave
	return "OVERRUN ON WAVE %d  ·  %d WAVES CLEARED" % [wave, waves_cleared]


func hud_text(player: Player) -> String:
	return "WAVE %d  HP %d  KILLS %d" % [wave, maxi(player.health, 0), player.score]


func banner_text(player: Player) -> String:
	if player.is_downed:
		var progress: float = _revive_progress.get(player, 0.0)
		if progress > 0.0:
			return "REVIVING  %d%%" % int(progress / Config.REVIVE_SECONDS * 100.0)
		return "DOWN  ·  a friend can revive you"
	return ""


func supports_sudden_death() -> bool:
	return false


func status_line() -> String:
	if _breather > 0.0 and wave > 0:
		return "WAVE %d CLEARED  ·  next in %d" % [wave, int(ceil(_breather))]
	return "WAVE %d  ·  %d LEFT" % [wave, enemies_alive() + _to_spawn]
