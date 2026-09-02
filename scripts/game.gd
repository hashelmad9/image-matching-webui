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

enum State { MAIN_MENU, LOBBY, COUNTDOWN, PLAYING, RESULTS }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PICKUP_SCRIPT := preload("res://scripts/pickup.gd")
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
@onready var _countdown: Control = $Banner/Countdown
@onready var _countdown_title: Label = $Banner/Countdown/Title
@onready var _countdown_number: Label = $Banner/Countdown/Number
@onready var _countdown_blurb: Label = $Banner/Countdown/Blurb
@onready var _results: Control = $Banner/Results
@onready var _results_headline: Label = $Banner/Results/Rows/Headline
@onready var _results_standings: RichTextLabel = $Banner/Results/Rows/Standings
@onready var _results_next: Label = $Banner/Results/Rows/Next
@onready var _results_vote: RichTextLabel = $Banner/Results/Rows/Vote
@onready var _results_timer: Label = $Banner/Results/Rows/Timer
@onready var _lobby_panel: Control = $Banner/LobbyPanel
@onready var _lobby_seats: RichTextLabel = $Banner/LobbyPanel/Rows/Seats
@onready var _lobby_mode: Label = $Banner/LobbyPanel/Rows/Mode
@onready var _lobby_blurb: Label = $Banner/LobbyPanel/Rows/Blurb
@onready var _menu_layer: CanvasLayer = $Menus

## One entry per seat. Holds a device id, or null when the seat is free.
var _seats: Array = []
var _state := State.MAIN_MENU
## Open menus, top of the stack taking input. Any open menu pauses the tree
## unless we are on the main menu, where there is nothing to pause.
var _menus: Array[Menu] = []
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
## Set when a versus round ran out of clock while tied; the next point wins.
var _sudden_death := false
var _sfx: Sfx = null
var _navigation: NavigationRegion3D = null
var _last_countdown := -1


func _ready() -> void:
	_seats.resize(Config.MAX_PLAYERS)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Aiming the lobby camera here beats hand-writing a rotation basis in the
	# scene file, and keeps it correct if its position is ever moved.
	_lobby_camera.look_at(Vector3.ZERO, Vector3.UP)
	_sfx = Sfx.new()
	_sfx.name = "Sfx"
	# Menu sounds must play while the round is paused.
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)
	Settings.load_from_disk()
	Settings.apply_all()
	_build_arena(Settings.arena)
	_refresh_lobby()
	open_main_menu()
	_refresh_ui()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Menus take input first (they run above and handle it themselves); by the
	# time it reaches here no menu is open.
	if _wants_pause(event):
		open_pause_menu()
		return
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


## Escape, the pad's Back button, or Start during a round.
func _wants_pause(event: InputEvent) -> bool:
	if _state == State.MAIN_MENU:
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return false
		if button.button_index == JOY_BUTTON_BACK:
			return true
		return button.button_index == JOY_BUTTON_START and _state != State.LOBBY and _seats.has(button.device)
	return false


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
	player.weapon_changed.connect(_on_weapon_changed)
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


## Assembles the arena from its layout and bakes navigation over it.
func _build_arena(name: String) -> void:
	ArenaBuilder.build($World/Arena, name)
	if _navigation != null:
		_navigation.queue_free()
	_navigation = NavigationBuilder.build(_world, $World/Arena)


func arena_name() -> String:
	return ArenaBuilder.built_name($World/Arena)


## Starts a round of `mode_id`. `skip_countdown` is for tests and renders.
func start_round(mode_id: String, skip_countdown := false) -> void:
	_clear_arena()
	if arena_name() != Settings.arena:
		_build_arena(Settings.arena)
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

	_sudden_death = false
	_split_screen.clear_toasts()
	if _mode.pickups():
		_spawn_pickups()
	_state = State.COUNTDOWN
	_timer = Config.COUNTDOWN_SECONDS
	_last_countdown = -1
	if skip_countdown:
		_begin_play()
	_refresh_ui()


func _begin_play() -> void:
	_state = State.PLAYING
	_timer = _mode.round_seconds()
	for player in players():
		player.controls_enabled = true
	Sfx.play("go")
	_mode.begin()


func _end_round() -> void:
	_headline = _mode.finish()
	for winner in _mode.winners():
		_session_wins[winner.index] = int(_session_wins.get(winner.index, 0)) + 1
	for player in players():
		player.controls_enabled = false
	_ballot = Mutators.ballot() if Settings.match_mutators else ([] as Array[String])
	_votes.clear()
	Sfx.play("bell")
	_state = State.RESULTS
	_timer = Config.RESULTS_SECONDS


## A tie at the whistle in a versus mode with real opposition goes to sudden
## death rather than a draw; someone should walk away with the round.
func _can_go_to_sudden_death() -> bool:
	return (
		not _sudden_death
		and _mode.supports_sudden_death()
		and _mode.winners().is_empty()
		and players().size() >= 2
	)


func in_sudden_death() -> bool:
	return _sudden_death


## A short message in one player's view.
func toast(player: Player, text: String, colour := Color.WHITE) -> void:
	var view := _split_screen.view_for(player)
	if view != null and view.hud != null:
		view.hud.toast(text, colour)


## The same message in everyone's view.
func toast_all(text: String, colour := Color.WHITE) -> void:
	for player in players():
		toast(player, text, colour)


func shake_all(amount: float) -> void:
	_split_screen.shake_all(amount)


## Records a seat's vote for the next round's mutator.
func vote(device: int, choice: int) -> void:
	if _state != State.RESULTS or choice < 0 or choice >= _ballot.size():
		return
	_votes[device] = _ballot[choice]
	Sfx.play("vote")


## Advances the rotation and starts the next round with the voted mutator.
func next_round() -> void:
	if players().is_empty():
		_return_to_lobby()
		return
	_mutator = Mutators.tally(_votes, _ballot) if not _ballot.is_empty() else Mutators.NONE
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
	for group in ["enemies", "projectiles", "effects", "pickups"]:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()


func _process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_timer -= delta
			var shown := int(ceil(_timer))
			if shown != _last_countdown and shown > 0:
				_last_countdown = shown
				Sfx.play("tick")
			if _timer <= 0.0:
				_begin_play()
		State.PLAYING:
			_mode.tick(delta)
			_timer -= delta
			if _mode.is_over() or (_sudden_death and not _mode.winners().is_empty()):
				_end_round()
			elif _timer <= 0.0:
				if _can_go_to_sudden_death():
					_sudden_death = true
					_timer = INF
					toast_all("SUDDEN DEATH  ·  next point wins", Color(1, 0.85, 0.3))
					_split_screen.shake_all(Config.SHAKE_HURT)
				else:
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
	var stats := Weapons.stats(shooter.weapon)
	projectile.speed = float(stats["speed"])
	projectile.lifetime = float(stats["lifetime"])
	# A mutator that sets damage or bounces overrides the weapon; otherwise
	# the weapon's own numbers stand.
	projectile.damage = Mutators.damage(_mutator) if Mutators.overrides(_mutator, "damage") else int(stats["damage"])
	projectile.bounces_left = Mutators.bounces(_mutator) if Mutators.overrides(_mutator, "bounces") else int(stats["bounces"])
	if _state == State.PLAYING:
		projectile.friendly_fire = _mode.friendly_fire()
		projectile.hit_handler = Callable(_mode, "projectile_hit")
	# The world sits at the origin, so a local position is already a world one.
	projectile.position = origin
	_world.add_child(projectile)
	Effects.muzzle_flash(_world, origin, Config.player_color(shooter.index))
	_split_screen.shake(shooter, Config.SHAKE_FIRE)
	Sfx.play(str(stats["sound"]))


func _on_player_damaged(victim: Player, _amount: int, attacker: Node) -> void:
	_split_screen.shake(victim, Config.SHAKE_DEATH if victim.health <= 0 else Config.SHAKE_HURT)
	if victim.health <= 0:
		Sfx.play("death")
	if attacker is Player and attacker != victim:
		var view := _split_screen.view_for(attacker as Player)
		if view != null and view.hud != null:
			view.hud.hit_marker()


func _on_player_respawned(player: Player) -> void:
	Effects.muzzle_flash(_world, player.global_position, Config.player_color(player.index))
	Sfx.play("respawn")


func _on_weapon_changed(player: Player, kind: String) -> void:
	if kind == Weapons.DEFAULT:
		toast(player, "BLASTER", Color(0.8, 0.8, 0.8))
	else:
		toast(player, "%s  ×%d" % [Weapons.title(kind), player.ammo], Color(1, 0.9, 0.5))
		Sfx.play("pickup")


## Weapon pickups at the four mid-edges, alternating what they hand out.
func _spawn_pickups() -> void:
	var inset := Config.ARENA_HALF_EXTENT * 0.66
	var spots := [
		Vector3(0.0, 0.0, -inset), Vector3(inset, 0.0, 0.0),
		Vector3(0.0, 0.0, inset), Vector3(-inset, 0.0, 0.0),
	]
	for i in spots.size():
		var pickup: Pickup = PICKUP_SCRIPT.new()
		pickup.kind = Weapons.PICKUP_KINDS[i % Weapons.PICKUP_KINDS.size()]
		pickup.position = spots[i] + Vector3.UP * Config.PICKUP_HOVER
		_world.add_child(pickup)


func navigation() -> NavigationRegion3D:
	return _navigation


func sfx() -> Sfx:
	return _sfx


func _on_player_died(victim: Player, killer: Node) -> void:
	if _state == State.PLAYING:
		_mode.on_player_died(victim, killer)
		return
	# Warm-up in the lobby: plain deathmatch rules, nothing counts for wins.
	victim.schedule_respawn(Config.RESPAWN_SECONDS)
	if killer is Player and killer != victim and is_instance_valid(killer):
		(killer as Player).score += 1
		toast(killer, "KILLED P%d" % (victim.index + 1), Config.player_color(victim.index))
		toast(victim, "KILLED BY P%d" % ((killer as Player).index + 1), Config.player_color((killer as Player).index))


# --- menus -----------------------------------------------------------------------

func open_menu(menu: Menu) -> void:
	menu.back_requested.connect(close_menu)
	_menu_layer.add_child(menu)
	_menus.append(menu)
	if _state != State.MAIN_MENU:
		get_tree().paused = true


func close_menu() -> void:
	if _menus.is_empty():
		return
	var menu: Menu = _menus.pop_back()
	menu.queue_free()
	Settings.save()
	if _menus.is_empty() and _state != State.MAIN_MENU:
		get_tree().paused = false


func close_all_menus() -> void:
	while not _menus.is_empty():
		close_menu()


func menus_open() -> int:
	return _menus.size()


func open_main_menu() -> void:
	var rows: Array[Dictionary] = [
		{"id": "play", "kind": "action", "label": "PLAY", "activate": play},
		{"id": "options", "kind": "action", "label": "OPTIONS", "activate": open_options_menu},
		{"id": "match", "kind": "action", "label": "MATCH SETUP", "activate": open_match_menu},
		{"id": "quit", "kind": "action", "label": "QUIT", "activate": quit_game},
	]
	open_menu(Menu.new("COUCH ARENA", rows, false))


## Leaves the main menu for the lobby.
func play() -> void:
	close_all_menus()
	_state = State.LOBBY
	_refresh_ui()


func open_pause_menu() -> void:
	var rows: Array[Dictionary] = [
		{"id": "resume", "kind": "action", "label": "RESUME", "activate": close_menu},
		{"id": "options", "kind": "action", "label": "OPTIONS", "activate": open_options_menu},
		{"id": "match", "kind": "action", "label": "MATCH SETUP", "activate": open_match_menu},
	]
	if _state != State.LOBBY:
		rows.append({"id": "lobby", "kind": "action", "label": "QUIT TO LOBBY", "activate": quit_to_lobby})
	rows.append({"id": "main", "kind": "action", "label": "QUIT TO MAIN MENU", "activate": quit_to_main_menu})
	open_menu(Menu.new("PAUSED" if _state != State.LOBBY else "LOBBY", rows))


func open_options_menu() -> void:
	var percent := func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	var metres := func(v: float) -> String: return "%.1f m" % v
	var degrees := func(v: float) -> String: return "%d°" % int(round(v))
	var rows: Array[Dictionary] = [
		{"id": "master", "kind": "slider", "label": "MASTER VOLUME", "min": 0.0, "max": 1.0, "step": 0.1,
			"get": func() -> float: return Settings.master_volume,
			"set": func(v: float) -> void: Settings.master_volume = v; Settings.apply_audio(), "format": percent},
		{"id": "sfx", "kind": "slider", "label": "EFFECTS VOLUME", "min": 0.0, "max": 1.0, "step": 0.1,
			"get": func() -> float: return Settings.sfx_volume,
			"set": func(v: float) -> void: Settings.sfx_volume = v, "format": percent},
		{"id": "distance", "kind": "slider", "label": "CAMERA DISTANCE", "min": 0.5, "max": 10.0, "step": 0.5,
			"get": func() -> float: return Settings.camera_distance,
			"set": func(v: float) -> void: Settings.camera_distance = v, "format": metres},
		{"id": "height", "kind": "slider", "label": "CAMERA HEIGHT", "min": 0.5, "max": 10.0, "step": 0.5,
			"get": func() -> float: return Settings.camera_height,
			"set": func(v: float) -> void: Settings.camera_height = v, "format": metres},
		{"id": "fov", "kind": "slider", "label": "FIELD OF VIEW", "min": 40.0, "max": 110.0, "step": 5.0,
			"get": func() -> float: return Settings.camera_fov,
			"set": func(v: float) -> void: Settings.camera_fov = v, "format": degrees},
		{"id": "invert", "kind": "toggle", "label": "INVERT AIM Y",
			"get": func() -> bool: return Settings.invert_aim_y,
			"set": func(v: bool) -> void: Settings.invert_aim_y = v},
		{"id": "deadzone", "kind": "slider", "label": "STICK DEADZONE", "min": 0.05, "max": 0.6, "step": 0.05,
			"get": func() -> float: return Settings.stick_deadzone,
			"set": func(v: float) -> void: Settings.stick_deadzone = v, "format": percent},
		{"id": "shake", "kind": "slider", "label": "SCREEN SHAKE", "min": 0.0, "max": 1.0, "step": 0.25,
			"get": func() -> float: return Settings.screen_shake,
			"set": func(v: float) -> void: Settings.screen_shake = v, "format": percent},
		{"id": "flash", "kind": "slider", "label": "HIT FLASH", "min": 0.0, "max": 1.0, "step": 0.25,
			"get": func() -> float: return Settings.hit_flash,
			"set": func(v: float) -> void: Settings.hit_flash = v, "format": percent},
		{"id": "window", "kind": "choice", "label": "WINDOW", "values": Settings.WINDOW_MODES,
			"get": func() -> String: return Settings.window_mode,
			"set": func(v: String) -> void: Settings.window_mode = v; Settings.apply_window(),
			"format": func(v: String) -> String: return v.to_upper()},
		{"id": "vsync", "kind": "toggle", "label": "V-SYNC",
			"get": func() -> bool: return Settings.vsync,
			"set": func(v: bool) -> void: Settings.vsync = v; Settings.apply_window()},
		{"id": "defaults", "kind": "action", "label": "RESET TO DEFAULTS",
			"activate": func() -> void: Settings.reset_defaults(); Settings.apply_all(); _refresh_top_menu()},
		{"id": "back", "kind": "action", "label": "BACK", "activate": close_menu},
	]
	open_menu(Menu.new("OPTIONS", rows))


func open_match_menu() -> void:
	var seconds := func(v: float) -> String: return GameMode.format_time(v)
	var rows: Array[Dictionary] = [
		{"id": "length", "kind": "slider", "label": "ROUND LENGTH", "min": 30.0, "max": 300.0, "step": 30.0,
			"get": func() -> float: return Settings.match_round_seconds,
			"set": func(v: float) -> void: Settings.match_round_seconds = v, "format": seconds},
		{"id": "kills", "kind": "slider", "label": "DEATHMATCH KILL TARGET", "min": 3.0, "max": 30.0, "step": 1.0,
			"get": func() -> float: return float(Settings.match_kill_target),
			"set": func(v: float) -> void: Settings.match_kill_target = int(v),
			"format": func(v: float) -> String: return str(int(v))},
		{"id": "wave", "kind": "slider", "label": "HORDE STARTING WAVE", "min": 1.0, "max": 10.0, "step": 1.0,
			"get": func() -> float: return float(Settings.match_horde_start_wave),
			"set": func(v: float) -> void: Settings.match_horde_start_wave = int(v),
			"format": func(v: float) -> String: return str(int(v))},
		{"id": "arena", "kind": "choice", "label": "ARENA", "values": Arenas.names(),
			"get": func() -> String: return Settings.arena,
			"set": func(v: String) -> void: Settings.arena = v,
			"format": func(v: String) -> String: return Arenas.title(v)},
		{"id": "mutators", "kind": "toggle", "label": "MUTATOR VOTES",
			"get": func() -> bool: return Settings.match_mutators,
			"set": func(v: bool) -> void: Settings.match_mutators = v},
		{"id": "back", "kind": "action", "label": "BACK", "activate": close_menu},
	]
	open_menu(Menu.new("MATCH SETUP", rows))


func _refresh_top_menu() -> void:
	if not _menus.is_empty():
		_menus.back().refresh()


func quit_to_lobby() -> void:
	close_all_menus()
	_return_to_lobby()


func quit_to_main_menu() -> void:
	close_all_menus()
	_return_to_lobby()
	_state = State.MAIN_MENU
	open_main_menu()
	_refresh_ui()


func quit_game() -> void:
	Settings.save()
	get_tree().quit()


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
	_countdown.visible = _state == State.COUNTDOWN
	_results.visible = _state == State.RESULTS
	_lobby_panel.visible = _state == State.LOBBY and not players().is_empty()
	_top_bar.visible = _state == State.PLAYING
	_lobby_ui.visible = players().is_empty() and _state in [State.LOBBY, State.MAIN_MENU]

	match _state:
		State.MAIN_MENU:
			pass
		State.LOBBY:
			_lobby_seats.text = _seats_text()
			_lobby_mode.text = "◄   %s   ►" % mode_title
			_lobby_blurb.text = "%s   ·   arena: %s" % [mode_blurb, Arenas.title(Settings.arena)]
		State.COUNTDOWN:
			_countdown_title.text = mode_title
			_countdown_number.text = str(int(ceil(_timer)))
			_countdown_blurb.text = mode_blurb
		State.PLAYING:
			var clock := ""
			if _sudden_death:
				clock = "  ·  SUDDEN DEATH"
			elif not is_inf(_timer):
				clock = "  ·  " + GameMode.format_time(_timer)
			var twist := "" if _mutator == Mutators.NONE else "  ·  " + Mutators.title(_mutator)
			_top_bar.text = "%s%s  ·  %s%s" % [mode_title, twist, _mode.status_line(), clock]
		State.RESULTS:
			_results_headline.text = _headline
			_results_standings.text = _standings_bbcode()
			_results_next.text = "next up: %s" % _peek_next_title()
			_results_vote.text = _ballot_bbcode() if not _ballot.is_empty() else ""
			$Banner/Results/Rows/VoteTitle.visible = not _ballot.is_empty()
			_results_timer.text = "next round in %d" % int(ceil(_timer))

	for player in players():
		if _state == State.PLAYING:
			player.hud_status = _mode.hud_text(player)
			player.hud_banner = _mode.banner_text(player)
		else:
			player.hud_status = ""
			player.hud_banner = ""


static func _hex(colour: Color) -> String:
	return colour.to_html(false)


func _seats_text() -> String:
	var parts: PackedStringArray = []
	for seat in Config.MAX_PLAYERS:
		var colour := _hex(Config.player_color(seat))
		if _seats[seat] == null:
			parts.append("[color=#666666]P%d  open[/color]" % (seat + 1))
		else:
			parts.append("[color=#%s]P%d  ready[/color]" % [colour, seat + 1])
	return "[center]" + "      ".join(parts) + "[/center]"


func _standings_bbcode() -> String:
	var parts: PackedStringArray = []
	for player in players():
		var wins := int(_session_wins.get(player.index, 0))
		parts.append("[color=#%s]P%d[/color]  ×%d" % [
			_hex(Config.player_color(player.index)), player.index + 1, wins
		])
	return "[center]SESSION WINS      " + "      ".join(parts) + "[/center]"


func _ballot_bbcode() -> String:
	var parts: PackedStringArray = []
	for i in _ballot.size():
		var count := 0
		for choice in _votes.values():
			if choice == _ballot[i]:
				count += 1
		var tally := "  [color=#ffd66b]●[/color]".repeat(count)
		parts.append("[color=#9ec5ff][%s / %d][/color]  %s%s" % [
			Mutators.VOTE_BUTTON_NAMES[i], i + 1, Mutators.title(_ballot[i]), tally
		])
	# One option per line: three titles side by side wrap at panel width.
	return "[center]" + "\n".join(parts) + "[/center]"


func _peek_next_title() -> String:
	var count := Config.MODE_ROTATION.size()
	var next_id: String = Config.MODE_ROTATION[(_rotation_index + 1) % count]
	var preview: GameMode = MODE_SCRIPTS[next_id].new()
	var title := preview.title()
	preview.free()
	return title
