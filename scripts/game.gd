## The hub: seats, the round flow, and the rotation of game modes.
##
## Players join by pressing a button on an unclaimed device, so controllers can
## come and go without restarting. Seats are a fixed array: joining claims the
## lowest free seat and leaving frees it, which keeps a player's colour and
## spawn point stable while others come and go.
##
## Rounds run LOBBY → COUNTDOWN → PLAYING → RESULTS → next mode, forever. The
## rules of each round live in scripts/modes/; this file only drives them.
extends Node

enum State { LOBBY, COUNTDOWN, PLAYING, RESULTS }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const MODE_SCRIPTS := {
	"horde": preload("res://scripts/modes/horde.gd"),
	"deathmatch": preload("res://scripts/modes/deathmatch.gd"),
	"tag": preload("res://scripts/modes/tag.gd"),
	"king_of_the_hill": preload("res://scripts/modes/king_of_the_hill.gd"),
	"ball_game": preload("res://scripts/modes/ball_game.gd"),
}

## Buttons that will join a waiting player.
const JOIN_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_START]

@onready var _world: Node3D = $World
@onready var _players_root: Node3D = $World/Players
@onready var _split_screen: SplitScreen = $Screens/SplitScreen
@onready var _lobby_ui: CanvasLayer = $LobbyUI
@onready var _lobby_mode_line: Label = $LobbyUI/Panel/ModeLine
@onready var _lobby_camera: Camera3D = $World/LobbyCamera
@onready var _top_bar: Label = $Banner/TopBar
@onready var _centre: Control = $Banner/Centre
@onready var _centre_title: Label = $Banner/Centre/Title
@onready var _centre_subtitle: Label = $Banner/Centre/Subtitle

## One entry per seat. Holds a device id, or null when the seat is free.
var _seats: Array = []
var _state := State.LOBBY
var _mode: GameMode = null
var _rotation_index := 0
var _timer := 0.0
var _headline := ""
## Session wins per seat index, shown on every results screen.
var _session_wins: Dictionary = {}
## Mutator in force this round, and the vote for the next one.
var _mutator := Mutators.NONE
var _ballot: Array[String] = []
var _votes: Dictionary = {}


func _ready() -> void:
	_seats.resize(Config.MAX_PLAYERS)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Aiming the lobby camera here beats hand-writing a rotation basis in the
	# scene file, and keeps it correct if its position is ever moved.
	_lobby_camera.look_at(Vector3.ZERO, Vector3.UP)
	_refresh_lobby()
	_refresh_ui()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return
		if not _seats.has(button.device):
			if button.button_index in JOIN_BUTTONS:
				_try_join(button.device)
		elif _state == State.LOBBY:
			match button.button_index:
				JOY_BUTTON_START:
					_start_from_lobby()
				JOY_BUTTON_DPAD_LEFT:
					_cycle_mode(-1)
				JOY_BUTTON_DPAD_RIGHT:
					_cycle_mode(1)
		elif _state == State.RESULTS:
			var choice := Mutators.VOTE_BUTTONS.find(button.button_index)
			if choice != -1:
				vote(button.device, choice)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ENTER:
			if not _seats.has(Config.KEYBOARD_DEVICE):
				_try_join(Config.KEYBOARD_DEVICE)
			elif _state == State.LOBBY:
				_start_from_lobby()
		elif key.keycode == KEY_TAB and _state == State.LOBBY:
			_cycle_mode(1)
		elif _state == State.RESULTS:
			var choice := Mutators.VOTE_KEYS.find(key.keycode)
			if choice != -1:
				vote(Config.KEYBOARD_DEVICE, choice)


func _cycle_mode(step: int) -> void:
	var count := Config.MODE_ROTATION.size()
	_rotation_index = (_rotation_index + step + count) % count
	_refresh_ui()


func _start_from_lobby() -> void:
	var mode_id := current_mode_id()
	var preview: GameMode = MODE_SCRIPTS[mode_id].new()
	var enough := players().size() >= preview.min_players()
	preview.free()
	if enough:
		start_round(mode_id)


# --- seats -------------------------------------------------------------------

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
	player.damaged.connect(_on_player_damaged)
	player.respawned.connect(_on_player_respawned)
	_split_screen.add_view(player)
	_apply_mutator_to(player)
	if _mode != null and _state != State.LOBBY:
		player.can_fire = _mode.can_fire()
		player.controls_enabled = _state == State.PLAYING
		_mode.on_player_joined(player)


func _remove_player(device: int) -> void:
	var seat: int = _seats.find(device)
	if seat == -1:
		return
	_seats[seat] = null
	for player in players():
		if player.device == device:
			_split_screen.remove_view(player)
			player.queue_free()
	_refresh_lobby()
	print("player %d disconnected" % [seat + 1])
	if players().is_empty() and _state != State.LOBBY:
		_return_to_lobby()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_remove_player(device)


## Live players, excluding any freed this frame.
func players() -> Array[Player]:
	var live: Array[Player] = []
	for child in _players_root.get_children():
		var player := child as Player
		if player != null and not player.is_queued_for_deletion():
			live.append(player)
	return live


func world() -> Node3D:
	return _world


# --- round flow --------------------------------------------------------------

func current_mode_id() -> String:
	return Config.MODE_ROTATION[_rotation_index]


func state() -> State:
	return _state


## Starts a round of `mode_id`. `skip_countdown` is for tests and renders.
func start_round(mode_id: String, skip_countdown := false) -> void:
	_clear_arena()
	if _mode != null:
		_mode.queue_free()
	_mode = MODE_SCRIPTS[mode_id].new()
	_mode.hub = self
	add_child(_mode)
	_rotation_index = maxi(Config.MODE_ROTATION.find(mode_id), 0)

	for player in players():
		player.reset_for_round()
		player.can_fire = _mode.can_fire()
		player.controls_enabled = false
		_apply_mutator_to(player)

	_state = State.COUNTDOWN
	_timer = Config.COUNTDOWN_SECONDS
	if skip_countdown:
		_begin_play()
	_refresh_ui()


func _begin_play() -> void:
	_state = State.PLAYING
	_timer = _mode.round_seconds()
	for player in players():
		player.controls_enabled = true
	_mode.begin()


func _end_round() -> void:
	_headline = _mode.finish()
	for winner in _mode.winners():
		_session_wins[winner.index] = int(_session_wins.get(winner.index, 0)) + 1
	for player in players():
		player.controls_enabled = false
	_ballot = Mutators.ballot()
	_votes.clear()
	_state = State.RESULTS
	_timer = Config.RESULTS_SECONDS


## Records a seat's vote for the next round's mutator.
func vote(device: int, choice: int) -> void:
	if _state != State.RESULTS or choice < 0 or choice >= _ballot.size():
		return
	_votes[device] = _ballot[choice]


## Advances the rotation and starts the next round with the voted mutator.
func next_round() -> void:
	if players().is_empty():
		_return_to_lobby()
		return
	_mutator = Mutators.tally(_votes, _ballot)
	var count := Config.MODE_ROTATION.size()
	_rotation_index = (_rotation_index + 1) % count
	start_round(current_mode_id())


## Applies the round's mutator to one player. Sets, not multiplies, so it is
## safe to call again after reset_for_round().
func _apply_mutator_to(player: Player) -> void:
	player.mutator_speed = Mutators.speed(_mutator)
	player.mutator_fire_scale = Mutators.fire_scale(_mutator)
	player.max_health = Mutators.health(_mutator)
	player.health = mini(player.health, player.max_health)


func set_mutator(id: String) -> void:
	_mutator = id
	for player in players():
		_apply_mutator_to(player)


func mutator() -> String:
	return _mutator


func _return_to_lobby() -> void:
	_clear_arena()
	_mutator = Mutators.NONE
	if _mode != null:
		_mode.queue_free()
		_mode = null
	for player in players():
		player.reset_for_round()
	_state = State.LOBBY
	_refresh_ui()


## Removes everything a round leaves lying around.
func _clear_arena() -> void:
	for group in ["enemies", "projectiles", "effects"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func _process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_begin_play()
		State.PLAYING:
			_mode.tick(delta)
			_timer -= delta
			if _timer <= 0.0 or _mode.is_over():
				_end_round()
		State.RESULTS:
			_timer -= delta
			if _timer <= 0.0:
				next_round()
	_refresh_ui()


# --- events from players -----------------------------------------------------

func _on_player_fired(shooter: Player, origin: Vector3, direction: Vector3) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.shooter = shooter
	projectile.direction = direction
	projectile.tint(Config.player_color(shooter.index))
	projectile.damage = Mutators.damage(_mutator)
	projectile.bounces_left = Mutators.bounces(_mutator)
	if _state == State.PLAYING:
		projectile.friendly_fire = _mode.friendly_fire()
		projectile.hit_handler = Callable(_mode, "projectile_hit")
	# The world sits at the origin, so a local position is already a world one.
	projectile.position = origin
	_world.add_child(projectile)
	Effects.muzzle_flash(_world, origin, Config.player_color(shooter.index))
	_split_screen.shake(shooter, Config.SHAKE_FIRE)


func _on_player_damaged(victim: Player, _amount: int, attacker: Node) -> void:
	_split_screen.shake(victim, Config.SHAKE_DEATH if victim.health <= 0 else Config.SHAKE_HURT)
	if attacker is Player and attacker != victim:
		var view := _split_screen.view_for(attacker as Player)
		if view != null and view.hud != null:
			view.hud.hit_marker()


func _on_player_respawned(player: Player) -> void:
	Effects.muzzle_flash(_world, player.global_position, Config.player_color(player.index))


func _on_player_died(victim: Player, killer: Node) -> void:
	if _state == State.PLAYING:
		_mode.on_player_died(victim, killer)
		return
	# Warm-up in the lobby: plain deathmatch rules, nothing counts for wins.
	victim.schedule_respawn(Config.RESPAWN_SECONDS)
	if killer is Player and killer != victim and is_instance_valid(killer):
		(killer as Player).score += 1


# --- presentation --------------------------------------------------------------

## The lobby prompt covers the window until somebody joins; after that the
## split-screen viewports do.
func _refresh_lobby() -> void:
	var nobody := players().is_empty()
	_lobby_ui.visible = nobody
	_lobby_camera.current = nobody
	# Once the split views cover the window, the root viewport would still be
	# drawing the entire arena behind them: a fifth full render nobody sees.
	get_viewport().disable_3d = not nobody


func _refresh_ui() -> void:
	var mode_title := ""
	var mode_blurb := ""
	if _mode != null and _state != State.LOBBY:
		mode_title = _mode.title()
		mode_blurb = _mode.blurb()
	else:
		var preview: GameMode = MODE_SCRIPTS[current_mode_id()].new()
		mode_title = preview.title()
		mode_blurb = preview.blurb()
		preview.free()

	_lobby_mode_line.text = "Next up: %s   (◄ ► or TAB to change)" % mode_title

	match _state:
		State.LOBBY:
			_centre.visible = false
			_top_bar.visible = not players().is_empty()
			_top_bar.text = "LOBBY  ·  NEXT: %s — %s  ·  ◄ ► change  ·  START to play" % [
				mode_title, mode_blurb
			]
		State.COUNTDOWN:
			_top_bar.visible = false
			_centre.visible = true
			_centre_title.text = mode_title
			_centre_subtitle.text = "%s\nstarting in %d" % [mode_blurb, int(ceil(_timer))]
		State.PLAYING:
			_centre.visible = false
			_top_bar.visible = true
			var clock := "" if is_inf(_timer) else "  ·  " + GameMode.format_time(_timer)
			var twist := "" if _mutator == Mutators.NONE else "  ·  " + Mutators.title(_mutator)
			_top_bar.text = "%s%s  ·  %s%s" % [mode_title, twist, _mode.status_line(), clock]
		State.RESULTS:
			_top_bar.visible = false
			_centre.visible = true
			_centre_title.text = _headline
			_centre_subtitle.text = "%s\nnext: %s\n\n%s" % [
				_standings(), _peek_next_title(), _ballot_text()
			]

	for player in players():
		player.hud_status = _mode.hud_text(player) if _state == State.PLAYING else ""


func _standings() -> String:
	var parts: PackedStringArray = []
	for player in players():
		parts.append("P%d ×%d" % [player.index + 1, int(_session_wins.get(player.index, 0))])
	return "SESSION WINS   " + "   ".join(parts)


func _ballot_text() -> String:
	var parts: PackedStringArray = []
	for i in _ballot.size():
		var count := 0
		for choice in _votes.values():
			if choice == _ballot[i]:
				count += 1
		var tally := "  (%d)" % count if count > 0 else ""
		parts.append("[%s / %d]  %s%s" % [
			Mutators.VOTE_BUTTON_NAMES[i], i + 1, Mutators.title(_ballot[i]), tally
		])
	return "VOTE THE NEXT MUTATOR      " + "      ".join(parts)


func _peek_next_title() -> String:
	var count := Config.MODE_ROTATION.size()
	var next_id: String = Config.MODE_ROTATION[(_rotation_index + 1) % count]
	var preview: GameMode = MODE_SCRIPTS[next_id].new()
	var title := preview.title()
	preview.free()
	return title
