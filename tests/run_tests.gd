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
	_check(not second.visible, "a dead player is hidden")

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
