## Hold the centre alone to score. Contested means nobody scores. Deathmatch
## rules otherwise: shots hurt, deaths respawn, but kills are worth nothing.
extends GameMode

var _zone: MeshInstance3D = null
var _zone_material: StandardMaterial3D = null
var _held: Dictionary = {}
var _holder: Player = null


func mode_id() -> String:
	return "king_of_the_hill"


func title() -> String:
	return "KING OF THE HILL"


func blurb() -> String:
	return "Hold the centre alone. %d seconds wins." % int(Config.KOTH_TARGET)


func round_seconds() -> float:
	return Settings.match_round_seconds


func begin() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = Config.KOTH_RADIUS
	mesh.bottom_radius = Config.KOTH_RADIUS
	mesh.height = 0.06
	_zone = MeshInstance3D.new()
	_zone.mesh = mesh
	_zone.position = Vector3(0.0, 0.04, 0.0)
	_zone_material = StandardMaterial3D.new()
	_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_material.emission_enabled = true
	_zone_material.emission_energy_multiplier = 1.2
	_zone.material_override = _zone_material
	_set_zone_colour(Color(1, 1, 1, 0.35))
	hub.world().add_child(_zone)


func _exit_tree() -> void:
	if is_instance_valid(_zone):
		_zone.queue_free()


func tick(delta: float) -> void:
	var inside: Array[Player] = []
	for player in alive_players():
		var flat := Vector2(player.global_position.x, player.global_position.z)
		if flat.length() <= Config.KOTH_RADIUS:
			inside.append(player)

	var previous := _holder
	_holder = inside[0] if inside.size() == 1 else null
	if _holder != null and _holder != previous:
		var colour := Config.player_color(_holder.index)
		hub.toast(_holder, "THE HILL IS YOURS", colour)
		for other in players():
			if other != _holder:
				hub.toast(other, "P%d TOOK THE HILL" % (_holder.index + 1), colour)
	elif _holder == null and previous != null and inside.size() > 1:
		hub.toast_all("HILL CONTESTED", Color(1, 0.55, 0.4))
	if _holder != null:
		_held[_holder] = _held.get(_holder, 0.0) + delta
		_holder.score = int(_held[_holder])
		var colour := Config.player_color(_holder.index)
		colour.a = 0.45
		_set_zone_colour(colour)
	elif inside.size() > 1:
		_set_zone_colour(Color(1, 0.4, 0.3, 0.45))
	else:
		_set_zone_colour(Color(1, 1, 1, 0.3))


func _set_zone_colour(colour: Color) -> void:
	_zone_material.albedo_color = colour
	_zone_material.emission = Color(colour.r, colour.g, colour.b)


func on_player_died(victim: Player, _killer: Node) -> void:
	# Kills are not the objective here.
	victim.schedule_respawn(Config.RESPAWN_SECONDS)


func is_over() -> bool:
	for seconds in _held.values():
		if seconds >= Config.KOTH_TARGET:
			return true
	return false


func finish() -> String:
	var top := leaders(players())
	if top.size() == 1:
		return "%s HELD THE HILL" % names(top)
	return "DRAW  ·  %s" % names(top)


func winners() -> Array[Player]:
	var top := leaders(players())
	return top if top.size() == 1 else []


func hud_text(player: Player) -> String:
	return "HILL %ds  HP %d" % [player.score, maxi(player.health, 0)]


func banner_text(player: Player) -> String:
	if player == _holder:
		return "HOLDING THE HILL"
	return super.banner_text(player)


func status_line() -> String:
	var top := leaders(players())
	if top.is_empty() or top[0].score == 0:
		return "TAKE THE HILL"
	return "%s LEADS  ·  %ds of %d" % [names(top), top[0].score, int(Config.KOTH_TARGET)]
