## One player's heads-up display. Lives inside that player's SubViewport, so it
## is automatically clipped to their slice of the screen.
##
## Three layers of information, by urgency: a small panel in the corner for
## the always-true (name, health, mode status); toasts near the centre for
## things that just happened; and a banner low in the frame for the state the
## player is in right now (down, respawning, "you're it").
class_name HUD
extends Control

const TOAST_SECONDS := 2.2
const MAX_TOASTS := 3
const HEALTH_BAR_WIDTH := 196.0

@onready var _name: Label = $Panel/Rows/Name
@onready var _health_fill: ColorRect = $Panel/Rows/HealthBack/HealthFill
@onready var _status: Label = $Panel/Rows/Status
@onready var _toasts: VBoxContainer = $Toasts
@onready var _banner: Label = $Banner
@onready var _hit_marker: Label = $HitMarker

var _player: Player = null
var _marker_time := 0.0


## Attaches this HUD to a player. Safe to call before the node enters the
## tree, which is when the split-screen rig builds it.
func bind(player: Player) -> void:
	_player = player
	if is_node_ready():
		_apply_colour()


func _ready() -> void:
	_apply_colour()


func _apply_colour() -> void:
	if _player == null:
		return
	var colour := Config.player_color(_player.index)
	_name.text = "P%d" % (_player.index + 1)
	_name.add_theme_color_override("font_color", colour)
	_health_fill.color = colour
	_banner.add_theme_color_override("font_color", colour)


## A short line near the centre that fades out. Newest at the bottom.
func toast(text: String, colour := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	_toasts.add_child(label)
	while _toasts.get_child_count() > MAX_TOASTS:
		_toasts.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(TOAST_SECONDS * 0.6)
	tween.tween_property(label, "modulate:a", 0.0, TOAST_SECONDS * 0.4)
	tween.tween_callback(label.queue_free)


func toast_count() -> int:
	return _toasts.get_child_count()


## Drops whatever is still fading. Called when a new round starts, so the
## countdown is not crowded by the last round's kill feed.
func clear_toasts() -> void:
	for child in _toasts.get_children():
		child.free()


## Flashes the hit marker in the centre of this player's view.
func hit_marker() -> void:
	_marker_time = Config.HIT_FLASH_SECONDS
	if _hit_marker != null:
		_hit_marker.visible = true


func _process(delta: float) -> void:
	if _marker_time > 0.0:
		_marker_time -= delta
		if _marker_time <= 0.0 and _hit_marker != null:
			_hit_marker.visible = false
	if _player == null or not is_instance_valid(_player):
		return

	var ratio := clampf(float(_player.health) / float(maxi(_player.max_health, 1)), 0.0, 1.0)
	_health_fill.size.x = HEALTH_BAR_WIDTH * ratio
	# Spawn protection reads as a pulsing bar rather than a separate widget.
	_health_fill.modulate.a = 0.55 + 0.45 * sin(_player.protection * 24.0) if _player.protection > 0.0 else 1.0

	var status := _player.hud_status
	if status.is_empty():
		# No mode running: the plain warm-up readout.
		status = "HP %d  ·  KILLS %d" % [maxi(_player.health, 0), _player.score]
	_status.text = status
	_banner.text = _player.hud_banner


func health_ratio() -> float:
	return _health_fill.size.x / HEALTH_BAR_WIDTH
