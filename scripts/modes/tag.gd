## Tag. One player is "it" and faster; touch someone to pass it on. Score is
## seconds spent not being it. No shooting.
extends GameMode

var _it: Player = null
var _immunity := 0.0
var _safe_time: Dictionary = {}


func mode_id() -> String:
	return "tag"


func title() -> String:
	return "TAG"


func blurb() -> String:
	return "Don't be it. Touch someone to pass it on."


func round_seconds() -> float:
	return Config.TAG_SECONDS


func friendly_fire() -> bool:
	return false


func can_fire() -> bool:
	return false


func begin() -> void:
	var everyone := players()
	if everyone.is_empty():
		return
	_set_it(everyone[randi() % everyone.size()])


func on_player_joined(player: Player) -> void:
	player.can_fire = false


func tick(delta: float) -> void:
	if not is_instance_valid(_it) or _it.is_dead:
		var candidates := alive_players()
		if candidates.is_empty():
			return
		_set_it(candidates[randi() % candidates.size()])

	for player in alive_players():
		if player != _it:
			_safe_time[player] = _safe_time.get(player, 0.0) + delta
			player.score = int(_safe_time[player])

	_immunity = maxf(0.0, _immunity - delta)
	if _immunity > 0.0:
		return
	for player in alive_players():
		if player == _it:
			continue
		if player.global_position.distance_to(_it.global_position) <= Config.TAG_RANGE:
			_set_it(player)
			break


func _set_it(player: Player) -> void:
	if is_instance_valid(_it):
		_it.speed_multiplier = 1.0
		_it.highlight(false)
	_it = player
	_it.speed_multiplier = Config.TAG_IT_SPEED
	_it.highlight(true)
	_immunity = Config.TAG_IMMUNITY


func is_it(player: Player) -> bool:
	return player == _it


func finish() -> String:
	var top := leaders(players())
	if top.size() == 1:
		return "%s STAYED FREE LONGEST" % names(top)
	return "DRAW  ·  %s" % names(top)


func winners() -> Array[Player]:
	var top := leaders(players())
	return top if top.size() == 1 else []


func hud_text(player: Player) -> String:
	if player == _it:
		return "YOU'RE IT  ·  catch someone!"
	return "SAFE FOR %ds" % player.score


func status_line() -> String:
	if is_instance_valid(_it):
		return "P%d IS IT" % (_it.index + 1)
	return ""
