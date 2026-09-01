## Builds and lays out one viewport per player.
##
## Each player gets a SubViewportContainer holding a SubViewport with its own
## camera and HUD. The SubViewports deliberately share the root viewport's
## World3D, so every camera looks into the same arena rather than a copy of it.
##
## The layout is recomputed from the *live* player count, so the screen
## re-partitions itself as controllers come and go mid-match.
class_name SplitScreen
extends Control

const HUD_SCENE := preload("res://scenes/hud.tscn")


## One player's slice of the screen.
class View:
	var player: Player
	var container: SubViewportContainer
	var viewport: SubViewport
	var camera: Camera3D
	var hud: HUD


var _views: Array[View] = []


func _ready() -> void:
	# Fill the window and let children be positioned manually.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout_views)


func _process(delta: float) -> void:
	_follow_players(delta)


## Creates a viewport, camera and HUD for a newly joined player.
func add_view(player: Player) -> void:
	var view := View.new()
	view.player = player

	view.container = SubViewportContainer.new()
	# Render the SubViewport at the container's size rather than scaling a
	# fixed-size texture up, which would look soft.
	view.container.stretch = true
	view.container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view.container)

	view.viewport = SubViewport.new()
	# Share the main world so all cameras see the same arena.
	view.viewport.world_3d = get_viewport().world_3d
	view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.viewport.handle_input_locally = false
	view.container.add_child(view.viewport)

	view.camera = Camera3D.new()
	view.camera.current = true
	view.viewport.add_child(view.camera)
	_place_camera(view, 1.0)

	view.hud = HUD_SCENE.instantiate()
	view.viewport.add_child(view.hud)
	view.hud.bind(player)

	_views.append(view)
	_layout_views()


## Tears down the viewport belonging to a player who has left.
func remove_view(player: Player) -> void:
	for index in range(_views.size() - 1, -1, -1):
		if _views[index].player == player:
			_views[index].container.queue_free()
			_views.remove_at(index)
	_layout_views()


func view_count() -> int:
	return _views.size()


## Slot layout for `count` players. Slot 0 is top-left and slots fill left to
## right, top to bottom; with three players the fourth quadrant stays empty.
static func viewport_rect(slot: int, count: int, window: Vector2i) -> Rect2i:
	if count <= 1:
		return Rect2i(Vector2i.ZERO, window)
	if count == 2:
		var half := Vector2i(window.x / 2, window.y)
		return Rect2i(Vector2i(slot * half.x, 0), half)
	var quarter := Vector2i(window.x / 2, window.y / 2)
	return Rect2i(Vector2i((slot % 2) * quarter.x, (slot / 2) * quarter.y), quarter)


func _layout_views() -> void:
	# Order by stable player index, so a player keeps the same corner for as
	# long as the set of players is unchanged.
	_views.sort_custom(func(a: View, b: View) -> bool: return a.player.index < b.player.index)

	var window := Vector2i(size)
	if window.x <= 0 or window.y <= 0:
		return

	for slot in _views.size():
		var rect := viewport_rect(slot, _views.size(), window)
		var view := _views[slot]
		view.container.position = rect.position
		view.container.size = rect.size


func _follow_players(delta: float) -> void:
	# Framerate-independent exponential smoothing.
	var blend := 1.0 - exp(-Config.CAMERA_FOLLOW_RATE * delta)
	for view in _views:
		if is_instance_valid(view.player):
			_place_camera(view, blend)


## Moves one camera toward the pose that trails its player. A blend of 1.0
## snaps immediately, which is what a freshly spawned camera wants.
func _place_camera(view: View, blend: float) -> void:
	var player := view.player
	var basis := Basis(Vector3.UP, player.yaw)
	var eye: Vector3 = player.global_position + basis * Vector3(
		0.0, Config.CAMERA_HEIGHT, Config.CAMERA_DISTANCE
	)
	var focus: Vector3 = (
		player.global_position
		+ basis * Vector3.FORWARD * Config.CAMERA_LOOK_AHEAD
		+ Vector3.UP
	)

	view.camera.global_position = view.camera.global_position.lerp(eye, blend)
	# Re-aiming from the already-smoothed position each frame gives a stable
	# look without interpolating rotation separately.
	if not view.camera.global_position.is_equal_approx(focus):
		view.camera.look_at(focus, Vector3.UP)
