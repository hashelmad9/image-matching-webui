## Weapon stat blocks. The blaster is the default and never runs dry; the
## others come from pickups with a fixed clip and hand back to the blaster
## when it is empty. Models are Kenney's Blaster Kit (CC0).
class_name Weapons
extends RefCounted

const DEFAULT := "blaster"

const ALL := {
	"blaster": {
		"title": "BLASTER", "cooldown": 0.16, "damage": 12, "speed": 42.0, "lifetime": 1.6,
		"pellets": 1, "spread": 0.0, "ammo": -1, "bounces": Config.PROJECTILE_BOUNCES,
		"model": "res://assets/weapons/blaster.glb", "sound": "fire",
	},
	"scatter": {
		"title": "SCATTER", "cooldown": 0.6, "damage": 9, "speed": 34.0, "lifetime": 0.45,
		"pellets": 5, "spread": 0.24, "ammo": 8, "bounces": Config.PROJECTILE_BOUNCES,
		"model": "res://assets/weapons/scatter.glb", "sound": "fire_scatter",
	},
	"rail": {
		"title": "RAIL", "cooldown": 0.85, "damage": 60, "speed": 95.0, "lifetime": 1.2,
		"pellets": 1, "spread": 0.0, "ammo": 5, "bounces": 0,
		"model": "res://assets/weapons/rail.glb", "sound": "fire_rail",
	},
}

## What pickups hand out, in the order the spawn points cycle through.
const PICKUP_KINDS: Array[String] = ["scatter", "rail"]


static func stats(kind: String) -> Dictionary:
	return ALL.get(kind, ALL[DEFAULT])


static func title(kind: String) -> String:
	return stats(kind)["title"]
