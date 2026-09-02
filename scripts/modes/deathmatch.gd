## Free-for-all. Kills score, first to the target or most when time runs out.
extends GameMode


func mode_id() -> String:
	return "deathmatch"


func title() -> String:
	return "DEATHMATCH"


func blurb() -> String:
	return "Every kill is a point. First to %d." % Config.DEATHMATCH_KILL_TARGET


func round_seconds() -> float:
	return Config.DEATHMATCH_SECONDS


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


func status_line() -> String:
	return "FIRST TO %d" % Config.DEATHMATCH_KILL_TARGET
