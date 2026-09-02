## Arena layouts. Each is a title plus a list of cover pieces; the floor and
## the perimeter walls are tiled automatically from ARENA_HALF_EXTENT.
##
## Pieces are Kenney's Modular Space Kit (CC0), on a 4-metre grid at one unit
## per metre, so positions here are metres. Rotation is degrees about +Y.
## `collide` is "auto" (a box round the piece's bounds, the default), "none",
## or a list of local boxes [[min_x, min_y, min_z, max_x, max_y, max_z], ...]
## for pieces with an opening.
##
## Rules every layout must keep, because systems assume them:
##   - the four corners (±0.6 half) are clear: players spawn there
##   - the four mid-edges (±0.66 half) are clear: pickups sit there
##   - nothing stands at ±4m on Z from the centre: the hill test walks there
class_name Arenas
extends RefCounted

const DEFAULT := "station"
const PIECE_DIR := "res://assets/kit/space/"

## A doorway: solid posts either side, open in the middle.
const GATE_BOXES := [
	[-2.1, 0.0, -0.7, -1.0, 4.6, 0.7],
	[1.0, 0.0, -0.7, 2.1, 4.6, 0.7],
	[-1.0, 3.6, -0.7, 1.0, 4.6, 0.7],
]

const LAYOUTS := {
	"station": {
		"title": "STATION",
		"blurb": "A block in the middle, gates on the lanes, pillars in the corners.",
		"cover": [
			{"piece": "template-floor-layer-raised", "x": 0.0, "z": 0.0, "rot": 0.0},
			{"piece": "gate", "x": 0.0, "z": -9.0, "rot": 0.0, "collide": GATE_BOXES},
			{"piece": "gate-door-window", "x": 0.0, "z": 9.0, "rot": 180.0, "collide": GATE_BOXES},
			{"piece": "template-wall-half", "x": 7.0, "z": 0.0, "rot": 90.0},
			{"piece": "template-wall-half", "x": -7.0, "z": 0.0, "rot": -90.0},
			{"piece": "template-detail", "x": 6.0, "z": 6.0, "rot": 0.0},
			{"piece": "template-detail", "x": -6.0, "z": 6.0, "rot": 0.0},
			{"piece": "template-detail", "x": 6.0, "z": -6.0, "rot": 0.0},
			{"piece": "template-detail", "x": -6.0, "z": -6.0, "rot": 0.0},
			{"piece": "cables", "x": 12.5, "z": 12.5, "rot": 45.0, "collide": "none"},
			{"piece": "cables", "x": -12.5, "z": -12.5, "rot": 225.0, "collide": "none"},
		],
	},
	"corridors": {
		"title": "CORRIDORS",
		"blurb": "Walls carve lanes round the centre; blocks guard the corners.",
		"cover": [
			{"piece": "template-floor-layer-raised", "x": 0.0, "z": 0.0, "rot": 0.0},
			{"piece": "template-wall", "x": 0.0, "z": -6.0, "rot": 0.0},
			{"piece": "template-wall", "x": 0.0, "z": 6.0, "rot": 180.0},
			{"piece": "template-wall", "x": -6.0, "z": 0.0, "rot": -90.0},
			{"piece": "template-wall", "x": 6.0, "z": 0.0, "rot": 90.0},
			{"piece": "template-floor-layer-raised", "x": 13.0, "z": 13.0, "rot": 0.0},
			{"piece": "template-floor-layer-raised", "x": -13.0, "z": -13.0, "rot": 0.0},
			{"piece": "template-wall-detail-a", "x": 13.0, "z": -13.0, "rot": 45.0},
			{"piece": "template-wall-detail-a", "x": -13.0, "z": 13.0, "rot": 225.0},
			{"piece": "gate-lasers", "x": 10.0, "z": 0.0, "rot": 90.0, "collide": GATE_BOXES},
			{"piece": "gate-lasers", "x": -10.0, "z": 0.0, "rot": -90.0, "collide": GATE_BOXES},
		],
	},
}


static func names() -> Array[String]:
	var out: Array[String] = []
	for key: String in LAYOUTS.keys():
		out.append(key)
	return out


static func layout(name: String) -> Dictionary:
	return LAYOUTS.get(name, LAYOUTS[DEFAULT])


static func title(name: String) -> String:
	return layout(name)["title"]
