## Headless test suite.
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Covers the geometry and wiring that cannot be judged by looking at a diff:
## viewport tiling, stick-to-yaw orientation, and the join/spawn/score path.
## Anything about how the game *feels* still needs a human with a controller.
extends SceneTree

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n== pure geometry ==")
	_test_viewport_layout()
	_test_orientation()
	_test_deadzone()
	_test_config()

	print("\n== scene integration ==")
	await _test_join_and_spawn()

	print("\n== game modes ==")
	await _test_modes()

	print("\n== game feel ==")
	await _test_feel()

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


# --- pure geometry --------------------------------------------------------

func _test_viewport_layout() -> void:
	var window := Vector2i(1280, 720)

	_check(
		SplitScreen.viewport_rect(0, 1, window) == Rect2i(Vector2i.ZERO, window),
		"one player fills the window"
	)
	_check(
		SplitScreen.viewport_rect(1, 2, window) == Rect2i(Vector2i(640, 0), Vector2i(640, 720)),
		"two players split left and right"
	)
	_check(
		SplitScreen.viewport_rect(3, 4, window) == Rect2i(Vector2i(640, 360), Vector2i(640, 360)),
		"four players take a quadrant each"
	)

	# Odd sizes round down, which may leave a seam, but must never overflow
	# the window or overlap another player's view.
	for size in [Vector2i(1280, 720), Vector2i(1281, 721), Vector2i(640, 480)]:
		for count in range(1, Config.MAX_PLAYERS + 1):
			var rects: Array[Rect2i] = []
			for slot in count:
				rects.append(SplitScreen.viewport_rect(slot, count, size))
			var label := "layout %dp at %dx%d" % [count, size.x, size.y]
			_check(_all_inside(rects, size), "%s stays inside the window" % label)
			_check(_all_disjoint(rects), "%s has no overlap" % label)


func _all_inside(rects: Array[Rect2i], window: Vector2i) -> bool:
	for rect in rects:
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		if rect.position.x + rect.size.x > window.x:
			return false
		if rect.position.y + rect.size.y > window.y:
			return false
	return true


func _all_disjoint(rects: Array[Rect2i]) -> bool:
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return false
	return true


func _test_orientation() -> void:
	# A zero-yaw node faces -Z, so pushing the stick up must move that way.
	var cases := {
		"up": [Vector2(0, 1), Vector3.FORWARD],
		"right": [Vector2(1, 0), Vector3.RIGHT],
		"down": [Vector2(0, -1), Vector3.BACK],
		"left": [Vector2(-1, 0), Vector3.LEFT],
	}
	for name: String in cases:
		var stick: Vector2 = cases[name][0]
		var expected: Vector3 = cases[name][1]
		var yaw := PlayerInput.yaw_from_stick(stick)
		var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		_check(forward.distance_to(expected) < 0.0001, "stick %s faces %v" % [name, expected])


func _test_deadzone() -> void:
	_check(
		PlayerInput._deadzone(Vector2(0.05, 0.0)) == Vector2.ZERO,
		"deadzone suppresses stick drift"
	)
	_check(
		absf(PlayerInput._deadzone(Vector2(1.0, 0.0)).length() - 1.0) < 0.0001,
		"a fully deflected stick still reaches full magnitude"
	)
	_check(
		PlayerInput._deadzone(Vector2(Config.STICK_DEADZONE + 0.0001, 0.0)).length() < 0.001,
		"output ramps continuously from zero at the threshold"
	)


func _test_config() -> void:
	var limit := Config.ARENA_HALF_EXTENT - Config.PLAYER_RADIUS
	var points: Array[Vector3] = []
	for index in Config.MAX_PLAYERS:
		points.append(Config.spawn_point(index))
	var inside := true
	for point in points:
		if absf(point.x) > limit or absf(point.z) > limit:
			inside = false
	_check(inside, "every spawn point is inside the arena")

	var separated := true
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) <= Config.PLAYER_RADIUS * 4.0:
				separated = false
	_check(separated, "spawn points are well separated")

	_check(
		Config.PLAYER_MAX_HEALTH / Config.PROJECTILE_DAMAGE >= 2,
		"a kill takes more than one shot"
	)


# --- scene integration ----------------------------------------------------

func _test_join_and_spawn() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var players_root: Node3D = main.get_node("World/Players")
	var split: SplitScreen = main.get_node("Screens/SplitScreen")

	_check(players_root.get_child_count() == 0, "no players before anyone joins")
	_check(main.get_node("LobbyUI").visible, "the lobby prompt shows while empty")

	# Join two seats, as if two people pressed a button.
	main._try_join(Config.KEYBOARD_DEVICE)
	main._try_join(0)
	await process_frame

	_check(players_root.get_child_count() == 2, "two players spawned")
	_check(split.view_count() == 2, "two viewports exist")
	_check(not main.get_node("LobbyUI").visible, "the lobby prompt hides once playing")

	# A device already seated must not be able to claim a second seat.
	main._try_join(0)
	await process_frame
	_check(players_root.get_child_count() == 2, "a joined device cannot join twice")

	var first: Player = players_root.get_child(0)
	var second: Player = players_root.get_child(1)
	_check(first.index != second.index, "players get distinct seats")
	_check(
		Config.player_color(first.index) != Config.player_color(second.index),
		"players get distinct colours"
	)

	# Let physics settle, then confirm the body is resting on the floor rather
	# than sinking through it or hovering.
	for i in 20:
		await physics_frame
	var resting_height := first.global_position.y
	_check(
		absf(resting_height - Config.PLAYER_HEIGHT * 0.5) < 0.2,
		"the player rests on the floor (y=%.2f)" % resting_height
	)

	# The camera must trail the player, not sit inside their head.
	var camera: Camera3D = split._views[0].camera
	var to_camera := camera.global_position - first.global_position
	_check(to_camera.length() > Config.PLAYER_RADIUS * 2.0, "the camera stands off the player")
	_check(to_camera.y > 0.0, "the camera sits above the player")

	# Firing should put a projectile into the world.
	var before := _count_projectiles(main.get_node("World"))
	first.fired.emit(first, first.global_position, first.forward())
	await process_frame
	_check(_count_projectiles(main.get_node("World")) == before + 1, "firing spawns a projectile")

	# Damage and scoring wiring.
	var start_health := second.health
	second.take_damage(Config.PROJECTILE_DAMAGE, first)
	_check(second.health == start_health - Config.PROJECTILE_DAMAGE, "damage reduces health")

	second.take_damage(Config.PLAYER_MAX_HEALTH, first)
	await process_frame
	_check(second.is_dead, "lethal damage kills")
	_check(first.score == 1, "the killer is credited")
	_check(second.visible, "a dead player falls where they stood")

	# And they come back.
	for i in int((Config.RESPAWN_SECONDS + 0.5) * 60.0):
		await physics_frame
	_check(not second.is_dead, "a dead player respawns")
	_check(second.health == Config.PLAYER_MAX_HEALTH, "respawning restores health")

	# Dropping a controller frees its seat and its viewport.
	main._on_joy_connection_changed(0, false)
	await process_frame
	_check(split.view_count() == 1, "disconnecting removes that player's viewport")

	main.queue_free()
	await process_frame


func _count_projectiles(world: Node) -> int:
	var count := 0
	for child in world.get_children():
		if child is Projectile:
			count += 1
	return count


# --- game modes -------------------------------------------------------------

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame


func _test_modes() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._try_join(Config.KEYBOARD_DEVICE)
	main._try_join(0)
	await process_frame
	var players: Array = main.players()
	var first: Player = players[0]
	var second: Player = players[1]

	# --- horde ---------------------------------------------------------------
	main.start_round("horde", true)
	await process_frame
	_check(main.state() == main.State.PLAYING, "horde: round is playing")
	_check(main.current_mode_id() == "horde", "horde: mode id reported")
	await _wait_physics(int((Config.HORDE_FIRST_WAVE_DELAY + 2.5) * 60))
	var enemies := get_nodes_in_group("enemies")
	_check(enemies.size() >= Config.HORDE_BASE_ENEMIES, "horde: wave one spawned %d enemies" % enemies.size())
	var enemy: Enemy = enemies[0]
	var spawn_far := true
	for player in players:
		if enemy.global_position.distance_to(player.global_position) < 6.0:
			spawn_far = false
	_check(spawn_far, "horde: enemies spawn away from players")
	var before := first.score
	enemy.take_damage(10_000, first)
	await process_frame
	_check(first.score == before + 1, "horde: killing an enemy scores for the shooter")
	_check(get_nodes_in_group("enemies").size() == enemies.size() - 1, "horde: dead enemy leaves the arena")
	# A teammate cannot be shot in co-op.
	var projectile: Projectile = main.PROJECTILE_SCENE.instantiate()
	projectile.shooter = first
	projectile.friendly_fire = false
	main.world().add_child(projectile)
	var hp := second.health
	projectile._on_body_entered(second)
	_check(second.health == hp, "horde: shots pass through teammates")
	_check(not projectile.is_queued_for_deletion(), "horde: a pass-through shot is not spent")
	projectile.queue_free()
	# Down and revive.
	second.take_damage(10_000, null)
	await process_frame
	_check(second.is_downed and second.visible, "horde: a dead player is downed, not hidden")
	_check(main.state() == main.State.PLAYING, "horde: one player down does not end the round")
	first.global_position = second.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait_physics(int((Config.REVIVE_SECONDS + 0.5) * 60))
	_check(not second.is_downed and second.health == Config.PLAYER_MAX_HEALTH, "horde: a teammate nearby revives the downed player")
	# Everyone down ends it.
	first.take_damage(10_000, null)
	second.take_damage(10_000, null)
	await process_frame
	await process_frame
	_check(main.state() == main.State.RESULTS, "horde: all players down ends the round")
	_check(main._headline.begins_with("OVERRUN"), "horde: results headline reports the wave")

	# --- rotation --------------------------------------------------------------
	main.next_round()
	await process_frame
	_check(main.current_mode_id() == "deathmatch", "rotation: horde is followed by deathmatch")
	_check(main.state() == main.State.COUNTDOWN, "rotation: the next round starts with a countdown")
	_check(not first.controls_enabled, "rotation: controls are frozen during the countdown")
	_check(get_nodes_in_group("enemies").is_empty(), "rotation: enemies are cleared between rounds")
	_check(first.score == 0 and not first.is_dead, "rotation: players are reset for the new round")

	# --- deathmatch ----------------------------------------------------------
	main.start_round("deathmatch", true)
	await process_frame
	second.take_damage(10_000, first)
	await process_frame
	_check(first.score == 1, "deathmatch: a kill is a point")
	_check(second.is_dead and not second.is_downed, "deathmatch: the victim awaits a respawn, not a rescue")
	first.score = Config.DEATHMATCH_KILL_TARGET
	await process_frame
	_check(main.state() == main.State.RESULTS, "deathmatch: reaching the target ends the round")
	_check(main._headline == "P1 WINS", "deathmatch: the winner is announced")
	_check(int(main._session_wins.get(0, 0)) == 1, "deathmatch: the winner earns a session win")

	# --- tag -------------------------------------------------------------------
	main.start_round("tag", true)
	await process_frame
	var mode: GameMode = main._mode
	var it_count := 0
	for player in players:
		if mode.is_it(player):
			it_count += 1
	_check(it_count == 1, "tag: exactly one player starts as it")
	_check(not first.can_fire and not second.can_fire, "tag: nobody can shoot")
	var it: Player = first if mode.is_it(first) else second
	var runner: Player = second if it == first else first
	_check(it.speed_multiplier > 1.0, "tag: it is faster")
	runner.global_position = it.global_position + Vector3(0.8, 0.0, 0.0)
	await _wait_physics(int((Config.TAG_IMMUNITY + 0.3) * 60))
	_check(mode.is_it(runner), "tag: touching it passes the tag")
	_check(it.speed_multiplier == 1.0, "tag: the old it loses the speed boost")

	# --- king of the hill ----------------------------------------------------
	main.start_round("king_of_the_hill", true)
	await process_frame
	first.global_position = Vector3(0.0, Config.PLAYER_HEIGHT * 0.5, 4.0)
	await _wait_physics(int(1.6 * 60))
	_check(first.score >= 1, "hill: holding the centre alone scores (%d)" % first.score)
	_check(second.score == 0, "hill: a player outside the zone does not score")
	second.global_position = Vector3(0.0, Config.PLAYER_HEIGHT * 0.5, -4.0)
	var held := first.score
	await _wait_physics(int(1.5 * 60))
	_check(first.score == held, "hill: a contested hill scores for nobody")

	# --- ball game -------------------------------------------------------------
	main.start_round("ball_game", true)
	await process_frame
	var ball: RigidBody3D = main._mode._ball
	_check(is_instance_valid(ball), "ball: a ball is spawned")
	ball.global_position = Vector3(Config.ARENA_HALF_EXTENT - 1.0, 1.0, 0.0)
	await _wait_physics(3)
	_check(first.score == 1, "ball: crossing the +X line scores for red (P1)")
	_check(second.score == 0, "ball: blue does not score from red's goal")
	_check(ball.global_position.length() < 6.0, "ball: the ball resets to the centre after a goal")
	var kick := Projectile.new()
	kick.direction = Vector3.RIGHT
	_check(main._mode.projectile_hit(kick, ball), "ball: a shot hitting the ball is claimed by the mode")
	kick.free()
	await _wait_physics(2)
	_check(ball.linear_velocity.x > 0.5, "ball: the shot kicks the ball")

	main.queue_free()
	await process_frame


# --- game feel --------------------------------------------------------------

func _test_feel() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._try_join(Config.KEYBOARD_DEVICE)
	main._try_join(0)
	await process_frame
	var first: Player = main.players()[0]
	var second: Player = main.players()[1]
	var world: Node3D = main.world()
	var split: SplitScreen = main.get_node("Screens/SplitScreen")

	# --- death, corpse, respawn, protection ----------------------------------
	main.start_round("deathmatch", true)
	await process_frame
	second.take_damage(10_000, first)
	await process_frame
	_check(second.is_dead and second.visible, "feel: a versus corpse stays visible briefly")
	await _wait_physics(int((Config.CORPSE_SECONDS + 0.2) * 60))
	_check(not second.visible, "feel: the corpse is hidden before the respawn")
	await _wait_physics(int((Config.RESPAWN_SECONDS - Config.CORPSE_SECONDS) * 60) + 5)
	_check(not second.is_dead and second.visible, "feel: the player respawns")
	_check(second.protection > 0.0, "feel: a respawned player is protected")
	var hp := second.health
	second.take_damage(50, first)
	_check(second.health == hp, "feel: damage is ignored during spawn protection")
	await _wait_physics(int((Config.SPAWN_PROTECTION_SECONDS + 0.2) * 60))
	_check(second.protection == 0.0, "feel: protection expires")
	second.take_damage(10, first)
	_check(second.health == hp - 10, "feel: damage lands once protection is over")

	# --- hit marker, shake and effects -----------------------------------------
	var view := split.view_for(first)
	_check(view.hud.get_node("HitMarker").visible, "feel: landing a hit shows the shooter a hit marker")
	_check(split.view_for(second).shake > 0.0, "feel: taking a hit shakes the victim's view")
	var effects_before := get_nodes_in_group("effects").size()
	first.fired.emit(first, first.global_position + Vector3(0, 1, 0), first.forward())
	await process_frame
	_check(get_nodes_in_group("effects").size() > effects_before, "feel: firing spawns a muzzle flash")
	_check(split.view_for(first).shake > 0.0, "feel: firing kicks the shooter's view")

	# --- bounty ----------------------------------------------------------------
	first.score = 3
	second.score = 0
	var mode: GameMode = main._mode
	_check(mode.bounty_target() == first, "bounty: the outright leader carries the bounty")
	first.take_damage(10_000, second)
	await process_frame
	_check(second.score == Config.BOUNTY_POINTS, "bounty: killing the leader is worth %d" % Config.BOUNTY_POINTS)
	first.score = 3
	second.score = 3
	_check(mode.bounty_target() == null, "bounty: a tie carries no bounty")

	# --- ricochet --------------------------------------------------------------
	var shot: Projectile = main.PROJECTILE_SCENE.instantiate()
	shot.shooter = first
	# Aimed straight at the east wall from just in front of it.
	shot.position = Vector3(Config.ARENA_HALF_EXTENT - 1.5, Config.MUZZLE_HEIGHT, 0.0)
	shot.direction = Vector3.RIGHT
	world.add_child(shot)
	await _wait_physics(6)
	_check(is_instance_valid(shot) and not shot.is_queued_for_deletion(), "ricochet: a shot survives its first wall")
	_check(shot.direction.x < -0.9, "ricochet: and comes back the other way")
	_check(shot.bounces_left == 0, "ricochet: one bounce is spent")
	shot.direction = Vector3.RIGHT
	shot.position = Vector3(Config.ARENA_HALF_EXTENT - 1.5, Config.MUZZLE_HEIGHT, 0.0)
	await _wait_physics(6)
	_check(not is_instance_valid(shot) or shot.is_queued_for_deletion(), "ricochet: the second wall spends the shot")

	# --- mutators --------------------------------------------------------------
	main.set_mutator("fast_feet")
	_check(first.mutator_speed > 1.0, "mutator: FAST FEET speeds players up")
	main.set_mutator("glass_cannon")
	_check(first.max_health == 40 and first.health <= 40, "mutator: GLASS CANNON lowers max health")
	first.fired.emit(first, first.global_position + Vector3(0, 1, 0), first.forward())
	await process_frame
	var last: Projectile = null
	for node in get_nodes_in_group("projectiles"):
		last = node
	_check(last != null and last.damage == 40, "mutator: GLASS CANNON raises shot damage")
	main.set_mutator("ricochet")
	first.fired.emit(first, first.global_position + Vector3(0, 1, 0), first.forward())
	await process_frame
	for node in get_nodes_in_group("projectiles"):
		last = node
	_check(last.bounces_left == Config.MUTATOR_BOUNCES, "mutator: INFINITE RICOCHET adds bounces")
	# The vote: results screen, two seats vote for option 1, tally applies it.
	main.set_mutator(Mutators.NONE)
	first.score = Config.DEATHMATCH_KILL_TARGET
	await process_frame
	_check(main.state() == main.State.RESULTS, "vote: results screen reached")
	_check(main._ballot.size() == 3, "vote: three mutators on the ballot")
	var chosen: String = main._ballot[1]
	main.vote(Config.KEYBOARD_DEVICE, 1)
	main.vote(0, 1)
	main.next_round()
	_check(main.mutator() == chosen, "vote: the majority choice is applied next round")
	_check(first.mutator_speed == Mutators.speed(chosen), "vote: players carry the voted mutator")
	main.vote(0, 0)
	_check(main.mutator() == chosen, "vote: votes outside the results screen are ignored")

	# --- camera collision ------------------------------------------------------
	# Nothing in this arena is tall enough to block a camera nine metres up,
	# so the mechanism is proven against a temporary tall wall placed between
	# the player and where the camera wants to be.
	main.start_round("deathmatch", true)
	await process_frame
	first.global_position = Vector3(-15.0, Config.PLAYER_HEIGHT * 0.5, 15.0)
	first.yaw = 0.0  # facing -Z, so the camera sits at +Z
	await _wait_physics(60)
	var clear := view.camera.global_position.distance_to(first.global_position)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = Config.LAYER_WORLD
	var blocker_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 20.0, 1.0)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	blocker.position = first.global_position + Vector3(0.0, 5.0, 3.0)
	world.add_child(blocker)
	await _wait_physics(45)
	var blocked := view.camera.global_position.distance_to(first.global_position)
	_check(blocked < clear - 2.0, "camera: pulled in front of cover (%.1f < %.1f)" % [blocked, clear])
	_check(view.camera.global_position.z < blocker.global_position.z, "camera: stays on the player's side of the wall")
	blocker.queue_free()
	await _wait_physics(60)
	var restored := view.camera.global_position.distance_to(first.global_position)
	_check(absf(restored - clear) < 0.5, "camera: back to full distance once clear (%.1f)" % restored)

	# --- enemy variety ---------------------------------------------------------
	var walker: Enemy = load("res://scenes/enemy.tscn").instantiate()
	walker.configure("walker", Config.ENEMY_SPEED)
	var brute: Enemy = load("res://scenes/enemy.tscn").instantiate()
	brute.configure("brute", Config.ENEMY_SPEED)
	var runner: Enemy = load("res://scenes/enemy.tscn").instantiate()
	runner.configure("runner", Config.ENEMY_SPEED)
	_check(brute.health > walker.health and brute.speed < walker.speed, "horde: a brute is tougher and slower")
	_check(runner.health < walker.health and runner.speed > walker.speed, "horde: a runner is fragile and quick")
	_check(brute.damage > walker.damage, "horde: a brute hits harder")
	for enemy in [walker, brute, runner]:
		enemy.free()
	var horde_script := load("res://scripts/modes/horde.gd")
	_check(horde_script.kind_for_spawn(1, 4) == "walker", "horde: wave one is all walkers")
	_check(horde_script.kind_for_spawn(Config.HORDE_BRUTE_WAVE, Config.HORDE_BRUTE_EVERY) == "brute", "horde: brutes arrive on schedule")

	main.queue_free()
	await process_frame
