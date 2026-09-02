## Round modifiers voted on between rounds. Each is a name and a handful of
## numbers the hub applies to players and projectiles at the start of a round.
class_name Mutators
extends RefCounted

const NONE := "none"

const ALL := {
	"one_hit": {"title": "ONE-HIT KILLS", "damage": 10_000},
	"ricochet": {"title": "INFINITE RICOCHET", "bounces": Config.MUTATOR_BOUNCES},
	"fast_feet": {"title": "FAST FEET", "speed": 1.4},
	"rapid_fire": {"title": "RAPID FIRE", "fire_scale": 0.45},
	"glass_cannon": {"title": "GLASS CANNON", "damage": 40, "health": 40},
}

## Buttons players vote with, in option order. Keyboard uses 1, 2, 3.
const VOTE_BUTTONS: Array[int] = [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_B]
const VOTE_BUTTON_NAMES: Array[String] = ["X", "Y", "B"]
const VOTE_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3]


static func title(id: String) -> String:
	if id == NONE:
		return "PLAIN"
	return ALL[id]["title"]


## Three distinct options for a ballot.
static func ballot() -> Array[String]:
	var ids: Array[String] = []
	for id: String in ALL.keys():
		ids.append(id)
	ids.shuffle()
	var picked: Array[String] = []
	for i in mini(3, ids.size()):
		picked.append(ids[i])
	return picked


## The most-voted option; ties break randomly; no votes means NONE.
static func tally(votes: Dictionary, options: Array[String]) -> String:
	var counts: Dictionary = {}
	for option in votes.values():
		counts[option] = int(counts.get(option, 0)) + 1
	if counts.is_empty():
		return NONE
	var best := 0
	for count in counts.values():
		best = maxi(best, int(count))
	var tied: Array[String] = []
	for option in options:
		if int(counts.get(option, 0)) == best:
			tied.append(option)
	return tied[randi() % tied.size()]


## Whether a mutator sets a given stat, as opposed to leaving it to the weapon.
static func overrides(id: String, stat: String) -> bool:
	return (ALL.get(id, {}) as Dictionary).has(stat)


static func speed(id: String) -> float:
	return float(ALL.get(id, {}).get("speed", 1.0))


static func fire_scale(id: String) -> float:
	return float(ALL.get(id, {}).get("fire_scale", 1.0))


static func damage(id: String) -> int:
	return int(ALL.get(id, {}).get("damage", Config.PROJECTILE_DAMAGE))


static func bounces(id: String) -> int:
	return int(ALL.get(id, {}).get("bounces", Config.PROJECTILE_BOUNCES))


static func health(id: String) -> int:
	return int(ALL.get(id, {}).get("health", Config.PLAYER_MAX_HEALTH))
