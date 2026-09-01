## All gameplay tuning in one place, so balance changes never require hunting
## through behaviour scripts.
class_name Config
extends RefCounted

## Hard cap on local players. Raising this also needs a layout in
## SplitScreen.viewport_rect(), which only knows how to tile up to four.
const MAX_PLAYERS := 4

## Device id used for the single keyboard seat. Real joypads are 0 and up.
const KEYBOARD_DEVICE := -1

# --- arena ----------------------------------------------------------------
## The floor spans [-ARENA_HALF_EXTENT, +ARENA_HALF_EXTENT] on X and Z.
const ARENA_HALF_EXTENT := 24.0
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 1.0

# --- player ---------------------------------------------------------------
const PLAYER_RADIUS := 0.5
## Total capsule height, including both hemispherical caps.
const PLAYER_HEIGHT := 2.0
const PLAYER_SPEED := 9.0
## Higher turns the player toward the aim stick faster. Units: 1/seconds.
const PLAYER_TURN_RATE := 14.0
const STICK_DEADZONE := 0.22
const PLAYER_MAX_HEALTH := 100
const RESPAWN_SECONDS := 2.5
const GRAVITY := 24.0

# --- combat ---------------------------------------------------------------
const FIRE_COOLDOWN := 0.16
## Analog trigger pull past this counts as firing.
const TRIGGER_THRESHOLD := 0.3
const PROJECTILE_SPEED := 42.0
const PROJECTILE_RADIUS := 0.18
const PROJECTILE_LIFETIME := 1.6
const PROJECTILE_DAMAGE := 12
## Spawn offset ahead of the muzzle so a shot never collides with its shooter.
const MUZZLE_FORWARD := 1.0
const MUZZLE_HEIGHT := 1.0

# --- camera ---------------------------------------------------------------
const CAMERA_DISTANCE := 7.5
const CAMERA_HEIGHT := 9.0
## How far ahead of the player the camera aims, in metres.
const CAMERA_LOOK_AHEAD := 3.0
## Higher snaps the camera to the player faster. Units: 1/seconds.
const CAMERA_FOLLOW_RATE := 9.0
## Narrower than Godot's 75 default: it magnifies the character without
## flattening the camera angle, which would fill the frame with empty sky.
const CAMERA_FOV := 60.0

# --- physics layers -------------------------------------------------------
## Bit 1 in the inspector. Static arena geometry.
const LAYER_WORLD := 1
## Bit 2 in the inspector. Player bodies.
const LAYER_PLAYERS := 2


## Texture atlas per seat. Kenney's character pack ships four skins, which is
## exactly MAX_PLAYERS, so each player reads as a different person on screen.
const PLAYER_SKINS: Array[String] = [
	"res://assets/characters/survivorMaleB.png",
	"res://assets/characters/survivorFemaleA.png",
	"res://assets/characters/zombieA.png",
	"res://assets/characters/zombieC.png",
]


static func player_skin(index: int) -> String:
	return PLAYER_SKINS[index % MAX_PLAYERS]


## Stable per-player identity colour, shared by the capsule, its projectiles
## and its HUD, so a glance at any of the three tells you whose it is.
static func player_color(index: int) -> Color:
	match index % MAX_PLAYERS:
		0: return Color(0.95, 0.30, 0.32)
		1: return Color(0.30, 0.58, 0.95)
		2: return Color(0.35, 0.85, 0.42)
		_: return Color(0.96, 0.78, 0.25)


## Evenly spaced spawn points, so no two players start on top of each other
## regardless of the order they joined in.
static func spawn_point(index: int) -> Vector3:
	var inset := ARENA_HALF_EXTENT * 0.6
	match index % MAX_PLAYERS:
		0: return Vector3(-inset, PLAYER_HEIGHT * 0.5, -inset)
		1: return Vector3(inset, PLAYER_HEIGHT * 0.5, inset)
		2: return Vector3(inset, PLAYER_HEIGHT * 0.5, -inset)
		_: return Vector3(-inset, PLAYER_HEIGHT * 0.5, inset)
