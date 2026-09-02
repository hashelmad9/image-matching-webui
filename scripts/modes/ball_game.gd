## 2v2 ball game. Shoot or shove the ball into the other team's goal. Shots
## do no damage; the ball is the only thing worth hitting.
extends GameMode

var _ball: RigidBody3D = null
var _goals: Array[int] = [0, 0]
var _props: Array[Node] = []


func mode_id() -> String:
	return "ball_game"


func title() -> String:
	return "BALL GAME"


func blurb() -> String:
	return "Red vs Blue. Shoot or shove the ball into their goal. First to %d." % Config.BALL_GOALS_TO_WIN


func round_seconds() -> float:
	return Settings.match_round_seconds


func friendly_fire() -> bool:
	return false


## The ball is the only target; a rail gun would just be a harder kick.
func pickups() -> bool:
	return false


func begin() -> void:
	_goals = [0, 0]
	_ball = _build_ball()
	hub.world().add_child(_ball)
	_props.append(_ball)
	# Team 0 attacks the +X goal, team 1 the -X goal. Each goal is tinted in
	# the colour of the team that scores in it.
	_props.append(_build_goal(1.0, Config.player_color(0)))
	_props.append(_build_goal(-1.0, Config.player_color(1)))
	for side in [1.0, -1.0]:
		for z in [-Config.GOAL_HALF_WIDTH, Config.GOAL_HALF_WIDTH]:
			_props.append(_build_post(side, z))
	_reset_ball()


func _exit_tree() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()


func _build_ball() -> RigidBody3D:
	var ball := RigidBody3D.new()
	ball.collision_layer = Config.LAYER_BALL
	ball.collision_mask = Config.LAYER_WORLD | Config.LAYER_PLAYERS | Config.LAYER_BALL
	ball.mass = 1.0
	ball.linear_damp = 0.4
	ball.angular_damp = 0.6
	ball.continuous_cd = true
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.5
	ball.physics_material_override = bounce

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Config.BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = Config.BALL_RADIUS
	sphere_mesh.height = Config.BALL_RADIUS * 2.0
	mesh.mesh = sphere_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.9, 0.8)
	material.emission_energy_multiplier = 0.6
	mesh.material_override = material
	ball.add_child(mesh)
	return ball


func _build_goal(side: float, colour: Color) -> MeshInstance3D:
	var goal := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 3.0, Config.GOAL_HALF_WIDTH * 2.0)
	goal.mesh = box
	goal.position = Vector3(side * (Config.ARENA_HALF_EXTENT - 1.0), 1.5, 0.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	colour.a = 0.35
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = Color(colour.r, colour.g, colour.b)
	material.emission_energy_multiplier = 1.0
	goal.material_override = material
	hub.world().add_child(goal)
	return goal


func _build_post(side: float, z: float) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 4.0, 0.5)
	post.mesh = box
	post.position = Vector3(side * (Config.ARENA_HALF_EXTENT - 2.0), 2.0, z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.9)
	material.emission_enabled = true
	material.emission = Color(1, 1, 0.9)
	material.emission_energy_multiplier = 0.8
	post.material_override = material
	hub.world().add_child(post)
	return post


func _reset_ball() -> void:
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = Vector3(0.0, Config.BALL_RADIUS + 3.5, 0.0)


func projectile_hit(projectile: Projectile, body: Node3D) -> bool:
	if body != _ball:
		return false
	_ball.apply_central_impulse(projectile.direction * Config.BALL_KICK)
	return true


func tick(_delta: float) -> void:
	if not is_instance_valid(_ball):
		return
	var line := Config.ARENA_HALF_EXTENT - 2.0
	var x := _ball.global_position.x
	var in_width := absf(_ball.global_position.z) <= Config.GOAL_HALF_WIDTH
	if x > line and in_width:
		_score(0)
	elif x < -line and in_width:
		_score(1)
	elif _ball.global_position.y < -5.0:
		_reset_ball()


func _score(team: int) -> void:
	_goals[team] += 1
	for player in players():
		player.score = _goals[Config.team_of(player.index)]
	var colour := Config.player_color(team)
	hub.toast_all("GOAL!  %s   %d - %d" % [_team_name(team), _goals[0], _goals[1]], colour)
	hub.shake_all(Config.SHAKE_HURT)
	Sfx.play("goal")
	Effects.spark(hub.world(), _ball.global_position, colour)
	_reset_ball()


func is_over() -> bool:
	return _goals[0] >= Config.BALL_GOALS_TO_WIN or _goals[1] >= Config.BALL_GOALS_TO_WIN


func finish() -> String:
	if _goals[0] == _goals[1]:
		return "DRAW  %d - %d" % [_goals[0], _goals[1]]
	var team := 0 if _goals[0] > _goals[1] else 1
	return "%s TEAM WINS  %d - %d" % [_team_name(team), _goals[team], _goals[1 - team]]


func winners() -> Array[Player]:
	if _goals[0] == _goals[1]:
		return []
	var team := 0 if _goals[0] > _goals[1] else 1
	var side: Array[Player] = []
	for player in players():
		if Config.team_of(player.index) == team:
			side.append(player)
	return side


static func _team_name(team: int) -> String:
	return "RED" if team == 0 else "BLUE"


func hud_text(player: Player) -> String:
	var team := Config.team_of(player.index)
	return "%s TEAM  ·  %d - %d" % [_team_name(team), _goals[team], _goals[1 - team]]


func banner_text(player: Player) -> String:
	var team := Config.team_of(player.index)
	var teammates: PackedStringArray = []
	for other in players():
		if other != player and Config.team_of(other.index) == team:
			teammates.append("P%d" % (other.index + 1))
	if teammates.is_empty():
		return ""
	return "with %s" % " & ".join(teammates)


func status_line() -> String:
	return "RED %d  —  %d BLUE" % [_goals[0], _goals[1]]
