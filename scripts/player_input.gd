## Normalises gamepad and keyboard control into one shape, so behaviour scripts
## never branch on input device.
##
## Godot's action system maps poorly to local multiplayer: actions merge every
## device, which is exactly wrong when four pads must stay distinct. So input is
## polled per-device instead, keyed by the joypad id.
class_name PlayerInput
extends RefCounted

var move_axis: Vector2
var aim_axis: Vector2
var firing: bool


## Reads one frame of input for a single device. Pass Config.KEYBOARD_DEVICE
## for the keyboard seat.
static func read(device: int) -> PlayerInput:
	var input := PlayerInput.new()
	if device == Config.KEYBOARD_DEVICE:
		input.move_axis = _deadzone(Vector2(
			_key_axis(KEY_A, KEY_D),
			_key_axis(KEY_S, KEY_W),
		))
		input.aim_axis = _deadzone(Vector2(
			_key_axis(KEY_LEFT, KEY_RIGHT),
			_key_axis(KEY_DOWN, KEY_UP),
		))
		input.firing = Input.is_key_pressed(KEY_SPACE)
		return input

	# Godot reports the joypad Y axes with down as positive; negate so that up
	# is positive and the maths matches the keyboard path.
	input.move_axis = _deadzone(Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		-Input.get_joy_axis(device, JOY_AXIS_LEFT_Y),
	))
	var aim_y := -Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
	if Settings.invert_aim_y:
		aim_y = -aim_y
	input.aim_axis = _deadzone(Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), aim_y))
	input.firing = (
		Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > Config.TRIGGER_THRESHOLD
		or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
		or Input.is_joy_button_pressed(device, JOY_BUTTON_A)
	)
	return input


static func _key_axis(negative: Key, positive: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


## Rescales past the deadzone, so crossing the threshold ramps smoothly from
## zero instead of jumping straight to STICK_DEADZONE.
static func _deadzone(raw: Vector2) -> Vector2:
	var deadzone := Settings.stick_deadzone
	var length := raw.length()
	if length < deadzone:
		return Vector2.ZERO
	var scaled := clampf((length - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return raw / length * scaled


## Converts a stick direction into a yaw about +Y.
##
## A zero-yaw node faces -Z, and rotating by yaw maps that to
## (-sin yaw, 0, -cos yaw). Pushing the stick up should mean "away from the
## camera", i.e. -Z, so the desired forward is (stick.x, 0, -stick.y).
static func yaw_from_stick(stick: Vector2) -> float:
	return atan2(-stick.x, stick.y)
