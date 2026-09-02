## Player-facing settings, persisted to user://settings.cfg.
##
## Static so every system reads the live value directly — the camera rig,
## the input layer, the shake and hit-flash code — with nothing to wire up.
## Defaults come from Config, so the constants there remain the single place
## to tune the baseline; this file is what the player changes at runtime.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"
const WINDOW_MODES: Array[String] = ["windowed", "borderless", "fullscreen"]

# --- audio ---------------------------------------------------------------
static var master_volume := 1.0
static var sfx_volume := 1.0

# --- camera and control --------------------------------------------------
static var camera_distance := Config.CAMERA_DISTANCE
static var camera_height := Config.CAMERA_HEIGHT
static var camera_fov := Config.CAMERA_FOV
static var invert_aim_y := false
static var stick_deadzone := Config.STICK_DEADZONE

# --- display -------------------------------------------------------------
static var window_mode := "windowed"
static var vsync := true

# --- feel ----------------------------------------------------------------
static var screen_shake := 1.0
static var hit_flash := 1.0

# --- match setup ---------------------------------------------------------
static var match_round_seconds := 90.0
static var match_kill_target := Config.DEATHMATCH_KILL_TARGET
static var match_horde_start_wave := 1
static var match_mutators := true

## Names of everything above, in save-file order.
const KEYS: Array[String] = [
	"master_volume", "sfx_volume",
	"camera_distance", "camera_height", "camera_fov", "invert_aim_y", "stick_deadzone",
	"window_mode", "vsync", "screen_shake", "hit_flash",
	"match_round_seconds", "match_kill_target", "match_horde_start_wave", "match_mutators",
]


static func reset_defaults() -> void:
	master_volume = 1.0
	sfx_volume = 1.0
	camera_distance = Config.CAMERA_DISTANCE
	camera_height = Config.CAMERA_HEIGHT
	camera_fov = Config.CAMERA_FOV
	invert_aim_y = false
	stick_deadzone = Config.STICK_DEADZONE
	window_mode = "windowed"
	vsync = true
	screen_shake = 1.0
	hit_flash = 1.0
	match_round_seconds = 90.0
	match_kill_target = Config.DEATHMATCH_KILL_TARGET
	match_horde_start_wave = 1
	match_mutators = true


## Reads the file if there is one; unknown or missing keys keep their default.
static func load_from_disk(path := PATH) -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	for key in KEYS:
		if file.has_section_key("settings", key):
			_write(key, file.get_value("settings", key))
	return true


static func save(path := PATH) -> bool:
	var file := ConfigFile.new()
	for key in KEYS:
		file.set_value("settings", key, _read(key))
	return file.save(path) == OK


static func _read(key: String) -> Variant:
	match key:
		"master_volume": return master_volume
		"sfx_volume": return sfx_volume
		"camera_distance": return camera_distance
		"camera_height": return camera_height
		"camera_fov": return camera_fov
		"invert_aim_y": return invert_aim_y
		"stick_deadzone": return stick_deadzone
		"window_mode": return window_mode
		"vsync": return vsync
		"screen_shake": return screen_shake
		"hit_flash": return hit_flash
		"match_round_seconds": return match_round_seconds
		"match_kill_target": return match_kill_target
		"match_horde_start_wave": return match_horde_start_wave
		"match_mutators": return match_mutators
	return null


static func _write(key: String, value: Variant) -> void:
	match key:
		"master_volume": master_volume = clampf(float(value), 0.0, 1.0)
		"sfx_volume": sfx_volume = clampf(float(value), 0.0, 1.0)
		"camera_distance": camera_distance = clampf(float(value), 0.5, 12.0)
		"camera_height": camera_height = clampf(float(value), 0.5, 12.0)
		"camera_fov": camera_fov = clampf(float(value), 40.0, 110.0)
		"invert_aim_y": invert_aim_y = bool(value)
		"stick_deadzone": stick_deadzone = clampf(float(value), 0.05, 0.6)
		"window_mode": window_mode = str(value) if str(value) in WINDOW_MODES else "windowed"
		"vsync": vsync = bool(value)
		"screen_shake": screen_shake = clampf(float(value), 0.0, 1.0)
		"hit_flash": hit_flash = clampf(float(value), 0.0, 1.0)
		"match_round_seconds": match_round_seconds = clampf(float(value), 30.0, 300.0)
		"match_kill_target": match_kill_target = clampi(int(value), 3, 50)
		"match_horde_start_wave": match_horde_start_wave = clampi(int(value), 1, 20)
		"match_mutators": match_mutators = bool(value)


## Pushes the audio settings to the mixer.
static func apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master != -1:
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(master_volume, 0.0001)))


## Pushes the display settings to the window. A no-op when there is no window.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
			DisplayServer.window_set_position(Vector2i.ZERO)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


static func apply_all() -> void:
	apply_audio()
	apply_window()
