## One player's heads-up display. Lives inside that player's SubViewport, so it
## is automatically clipped to their slice of the screen.
class_name HUD
extends Control

@onready var _label: Label = $Margin/Label

var _player: Player = null


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
	_label.add_theme_color_override("font_color", Config.player_color(_player.index))


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _label == null:
		return
	var status := "DOWN" if _player.is_dead else "HP %d" % maxi(_player.health, 0)
	_label.text = "P%d  %s  KILLS %d" % [_player.index + 1, status, _player.score]
