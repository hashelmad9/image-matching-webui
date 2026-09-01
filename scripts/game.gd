## Match controller: who is playing, spawning them, and wiring their shots.
##
## Players join by pressing a button on an unclaimed device, so controllers can
## come and go without restarting. Seats are a fixed array: joining claims the
## lowest free seat and leaving frees it, which keeps a player's colour and
## spawn point stable while others come and go.
extends Node

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

## Buttons that will join a waiting player.
const JOIN_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_START]

@onready var _world: Node3D = $World
@onready var _players_root: Node3D = $World/Players
@onready var _split_screen: SplitScreen = $Screens/SplitScreen
@onready var _lobby_ui: CanvasLayer = $LobbyUI
@onready var _lobby_camera: Camera3D = $World/LobbyCamera

## One entry per seat. Holds a device id, or null when the seat is free.
var _seats: Array = []


func _ready() -> void:
	_seats.resize(Config.MAX_PLAYERS)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Aiming the lobby camera here beats hand-writing a rotation basis in the
	# scene file, and keeps it correct if its position is ever moved.
	_lobby_camera.look_at(Vector3.ZERO, Vector3.UP)
	_refresh_lobby()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed and button.button_index in JOIN_BUTTONS:
			_try_join(button.device)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ENTER:
			_try_join(Config.KEYBOARD_DEVICE)


## Seats a device if it is not already playing and a seat is free.
func _try_join(device: int) -> void:
	if _seats.has(device):
		return
	var seat := _seats.find(null)
	if seat == -1:
		return  # All seats full; ignore further join presses.
	_seats[seat] = device
	_spawn_player(seat, device)
	_refresh_lobby()
	print("player %d joined on device %d" % [seat + 1, device])


func _spawn_player(index: int, device: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.setup(index, device)
	_players_root.add_child(player)
	player.fired.connect(_on_player_fired)
	player.died.connect(_on_player_died)
	_split_screen.add_view(player)


func _remove_player(device: int) -> void:
	var seat: int = _seats.find(device)
	if seat == -1:
		return
	_seats[seat] = null
	for child in _players_root.get_children():
		var player := child as Player
		if player != null and player.device == device:
			_split_screen.remove_view(player)
			player.queue_free()
	_refresh_lobby()
	print("player %d disconnected" % [seat + 1])


func _on_player_fired(shooter: Player, origin: Vector3, direction: Vector3) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.shooter = shooter
	projectile.direction = direction
	projectile.tint(Config.player_color(shooter.index))
	# The world sits at the origin, so a local position is already a world one.
	projectile.position = origin
	_world.add_child(projectile)


func _on_player_died(victim: Player, killer: Player) -> void:
	if killer != null and killer != victim and is_instance_valid(killer):
		killer.score += 1


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_remove_player(device)


## The lobby prompt covers the window until somebody joins; after that the
## split-screen viewports do.
func _refresh_lobby() -> void:
	var in_lobby := _split_screen.view_count() == 0
	_lobby_ui.visible = in_lobby
	_lobby_camera.current = in_lobby
	# Once the split views cover the window, the root viewport would still be
	# drawing the entire arena behind them: a fifth full render nobody sees.
	get_viewport().disable_3d = not in_lobby
