## Base class for a round's rules. The hub (game.gd) owns the flow — lobby,
## countdown, play, results — and asks the current mode what the rules are.
##
## Override what a mode needs and leave the rest. The defaults describe a
## plain versus round: shots hurt everyone, deaths respawn after a delay, and
## a kill is worth a point.
class_name GameMode
extends Node

## Set by the hub before begin(). Gives access to players() and world().
var hub: Node = null


func mode_id() -> String:
	return "base"


func title() -> String:
	return "MODE"


## One line shown on the countdown and in the lobby.
func blurb() -> String:
	return ""


func min_players() -> int:
	return 2


func round_seconds() -> float:
	return 90.0


## Whether shots damage other players.
func friendly_fire() -> bool:
	return true


func can_fire() -> bool:
	return true


## Called when play starts, after the countdown.
func begin() -> void:
	pass


func tick(_delta: float) -> void:
	pass


## True ends the round before the timer does.
func is_over() -> bool:
	return false


## Called once when the round ends. Returns the results headline.
func finish() -> String:
	return ""


## Who gets a session win. Empty for co-op or a draw.
func winners() -> Array[Player]:
	return []


func on_player_died(victim: Player, killer: Node) -> void:
	victim.schedule_respawn(Config.RESPAWN_SECONDS)
	if killer is Player and killer != victim:
		(killer as Player).score += 1


func on_player_joined(_player: Player) -> void:
	pass


## Return true to claim a projectile hit; the shot is then spent.
func projectile_hit(_projectile: Projectile, _body: Node3D) -> bool:
	return false


## Per-player HUD line.
func hud_text(player: Player) -> String:
	return "HP %d  KILLS %d" % [maxi(player.health, 0), player.score]


## Shared line across the top of the screen.
func status_line() -> String:
	return ""


func players() -> Array[Player]:
	return hub.players()


func alive_players() -> Array[Player]:
	var alive: Array[Player] = []
	for player in players():
		if not player.is_dead:
			alive.append(player)
	return alive


## Everyone sharing the top score, so ties are reported honestly.
static func leaders(candidates: Array[Player]) -> Array[Player]:
	var best := -1
	for player in candidates:
		best = maxi(best, player.score)
	var top: Array[Player] = []
	for player in candidates:
		if player.score == best:
			top.append(player)
	return top


static func names(group: Array[Player]) -> String:
	var parts: PackedStringArray = []
	for player in group:
		parts.append("P%d" % (player.index + 1))
	return " & ".join(parts)


static func format_time(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
