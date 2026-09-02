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


## Texture atlas per seat; see player_tint() for how four seats stay distinct.
const PLAYER_SKINS: Array[String] = [
	"res://assets/characters/survivorMaleB.png",
	"res://assets/characters/survivorFemaleA.png",
	"res://assets/characters/survivorMaleB.png",
	"res://assets/characters/survivorFemaleA.png",
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


# --- physics layers, continued -------------------------------------------
## Bit 3 in the inspector. Horde enemies.
const LAYER_ENEMIES := 4
## Bit 4 in the inspector. The ball in the ball game.
const LAYER_BALL := 8

# --- match flow -----------------------------------------------------------
const COUNTDOWN_SECONDS := 3.0
const RESULTS_SECONDS := 6.0
## Order modes are played in. The lobby lets players pick where to start.
const MODE_ROTATION: Array[String] = [
	"horde", "deathmatch", "tag", "king_of_the_hill", "ball_game",
]

# --- deathmatch -----------------------------------------------------------
const DEATHMATCH_SECONDS := 90.0
const DEATHMATCH_KILL_TARGET := 10

# --- horde ----------------------------------------------------------------
const HORDE_BASE_ENEMIES := 4
const HORDE_ENEMIES_PER_WAVE := 2
const HORDE_WAVE_BREATHER := 4.0
## Grace period before the first wave, so nobody is swarmed at the whistle.
const HORDE_FIRST_WAVE_DELAY := 2.5
const HORDE_SPAWN_INTERVAL := 0.5
const ENEMY_HEALTH := 36
const ENEMY_SPEED := 3.6
## Added to enemy speed every wave, so later waves close distance faster.
const ENEMY_SPEED_PER_WAVE := 0.15
const ENEMY_DAMAGE := 10
const ENEMY_ATTACK_RANGE := 1.6
const ENEMY_ATTACK_COOLDOWN := 0.9
## A downed player comes back when a teammate stands this close for this long.
const REVIVE_RANGE := 2.5
const REVIVE_SECONDS := 2.0

# --- tag ------------------------------------------------------------------
const TAG_SECONDS := 60.0
const TAG_RANGE := 1.6
const TAG_IT_SPEED := 1.15
## Seconds after a tag during which it cannot bounce straight back.
const TAG_IMMUNITY := 1.0

# --- king of the hill -----------------------------------------------------
const KOTH_SECONDS := 90.0
const KOTH_RADIUS := 6.0
## Seconds of uncontested hill time needed to win outright.
const KOTH_TARGET := 30.0

# --- ball game ------------------------------------------------------------
const BALL_SECONDS := 90.0
const BALL_GOALS_TO_WIN := 3
const BALL_RADIUS := 0.7
## Impulse a projectile gives the ball.
const BALL_KICK := 9.0
## Impulse per second a player gives the ball while running into it.
const BALL_PUSH := 60.0
const GOAL_HALF_WIDTH := 6.0

## Zombie skins from the same Kenney pack, used for horde enemies.
const ENEMY_SKINS: Array[String] = [
	"res://assets/characters/zombieA.png",
	"res://assets/characters/zombieC.png",
]


## Players use the two survivor skins with a colour tint, so all four seats
## stay distinct and the zombie skins are free for enemies.
static func player_tint(index: int) -> Color:
	return player_color(index).lerp(Color.WHITE, 0.45)


## Team for the 2v2 modes: seats alternate so P1+P3 face P2+P4.
static func team_of(index: int) -> int:
	return index % 2


# --- game feel ------------------------------------------------------------
## Seconds a freshly respawned player cannot be hurt.
const SPAWN_PROTECTION_SECONDS := 2.0
## How long a versus corpse stays visible before the respawn timer hides it.
const CORPSE_SECONDS := 0.7
const HIT_FLASH_SECONDS := 0.12
const RESPAWN_MATERIALISE_SECONDS := 0.35
const SHAKE_FIRE := 0.05
const SHAKE_HURT := 0.22
const SHAKE_DEATH := 0.4
## Higher decays screen shake faster. Units: 1/seconds.
const SHAKE_DECAY := 9.0
## How far the camera stays off any cover it would otherwise clip into.
const CAMERA_COLLISION_MARGIN := 0.35

# --- ricochet -------------------------------------------------------------
## Every shot bounces off cover this many times before it is spent. The
## signature mechanic: cover is a weapon, and bank shots are the point.
const PROJECTILE_BOUNCES := 1
const MUTATOR_BOUNCES := 8

# --- deathmatch bounty ----------------------------------------------------
## Killing the outright score leader is worth this many points.
const BOUNTY_POINTS := 2

# --- horde variety --------------------------------------------------------
## Wave from which runners can appear, and their share of a wave.
const HORDE_RUNNER_WAVE := 2
const HORDE_RUNNER_SHARE := 0.25
## Wave from which brutes appear; every Nth spawn is one.
const HORDE_BRUTE_WAVE := 4
const HORDE_BRUTE_EVERY := 4


# --- weapons and pickups --------------------------------------------------
const PICKUP_RADIUS := 1.1
const PICKUP_HOVER := 0.9
const PICKUP_RESPAWN_SECONDS := 12.0
## Kenney's blasters are authored at roughly a metre; this brings them to
## hand size on a character that is itself scaled to 0.5.
const WEAPON_MODEL_SCALE := 0.45

# --- horde boss -------------------------------------------------------------
## Every Nth wave ends with a boss as its last spawn.
const HORDE_BOSS_EVERY := 5
const HORDE_BOSS_POINTS := 5
