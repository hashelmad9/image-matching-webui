## Free-for-all. Kills score, first to the target or most when time runs out.
extends GameMode

var _last_target: Player = null


func mode_id() -> String:
	return "deathmatch"


func title() -> String:
	return "DEATHMATCH"


func blurb() -> String:
	return "Every kill is a point. First to %d." % Config.DEATHMATCH_KILL_TARGET


func round_seconds() -> float:
	return Config.DEATHMATCH_SECONDS


## The outright score leader, or null when tied or nobody has scored.
func bounty_target() -> Player:
	var top := leaders(players())
	if top.size() == 1 and top[0].score > 0:
		return top[0]
	return null


## Killing the leader is worth extra, so everyone turns on whoever is ahead
## and last place is always one good round from being back in it.
func on_player_died(victim: Player, killer: Node) -> void:
	var bounty := victim == bounty_target()
	victim.schedule_respawn(Config.RESPAWN_SECONDS)
	if killer is Player and killer != victim:
		var points := Config.BOUNTY_POINTS if bounty else 1
		(killer as Player).score += points
		announce_kill(killer as Player, victim, points)
		if bounty:
			hub.toast_all("P%d COLLECTED THE BOUNTY" % ((killer as Player).index + 1), Config.player_color((killer as Player).index))
	var new_target := bounty_target()
	if new_target != null and new_target != _last_target:
		hub.toast(new_target, "BOUNTY ON YOU", Color(1, 0.85, 0.3))
	_last_target = new_target


func is_over() -> bool:
	for player in players():
		if player.score >= Config.DEATHMATCH_KILL_TARGET:
			return true
	return false


func finish() -> String:
	var top := leaders(players())
	if top.size() == 1:
		return "%s WINS" % names(top)
	return "DRAW  ·  %s" % names(top)


func winners() -> Array[Player]:
	var top := leaders(players())
	return top if top.size() == 1 else []


func hud_text(player: Player) -> String:
	return "HP %d  KILLS %d" % [maxi(player.health, 0), player.score]


func banner_text(player: Player) -> String:
	if not player.is_dead and player == bounty_target():
		return "BOUNTY ON YOU"
	return super.banner_text(player)


func status_line() -> String:
	var target := bounty_target()
	if target != null:
		return "FIRST TO %d  ·  BOUNTY ON P%d (worth %d)" % [
			Config.DEATHMATCH_KILL_TARGET, target.index + 1, Config.BOUNTY_POINTS
		]
	return "FIRST TO %d" % Config.DEATHMATCH_KILL_TARGET
