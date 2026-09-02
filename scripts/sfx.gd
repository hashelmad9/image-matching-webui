## Sound effects. A pool of non-positional players fed from a name → streams
## table; a name with several streams picks one at random, and every play
## gets a little pitch jitter so repeats do not sound stamped out.
##
## Non-positional on purpose: four cameras means four listeners, and one
## screen means one pair of speakers. Positional audio in split screen is a
## problem to solve deliberately later, not by default.
class_name Sfx
extends Node

const POOL_SIZE := 16
const SOUNDS := {
	"fire": ["fire_0", "fire_1", "fire_2", "fire_3"],
	"fire_scatter": ["fire_scatter"],
	"fire_rail": ["fire_rail"],
	"hit": ["hit_0", "hit_1"],
	"wall": ["wall_0", "wall_1"],
	"death": ["death"],
	"respawn": ["respawn"],
	"pickup": ["pickup"],
	"wave": ["wave"],
	"tick": ["tick"],
	"go": ["go"],
	"vote": ["vote"],
	"bell": ["bell"],
	"goal": ["goal"],
	"tag": ["tag"],
}
## Loudness per name, in dB. Shots are frequent, so they sit low.
const VOLUME := {
	"fire": -10.0, "fire_scatter": -8.0, "fire_rail": -4.0, "hit": -6.0, "wall": -14.0,
	"death": -3.0, "respawn": -6.0, "pickup": -4.0, "wave": 0.0, "tick": -8.0, "go": -2.0,
	"vote": -8.0, "bell": 0.0, "goal": 0.0, "tag": -4.0,
}
## Names that may not play again within this many milliseconds. Four players
## firing at once would otherwise stack sixteen lasers a second.
const MIN_INTERVAL_MS := {"fire": 45, "fire_scatter": 45, "wall": 60, "hit": 40}

static var instance: Sfx = null

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}
var _play_count := 0


func _ready() -> void:
	instance = self
	for name: String in SOUNDS:
		var streams: Array[AudioStream] = []
		for file: String in SOUNDS[name]:
			var stream := load("res://assets/audio/%s.ogg" % file) as AudioStream
			if stream != null:
				streams.append(stream)
			else:
				push_warning("Sfx: missing clip %s" % file)
		_streams[name] = streams
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Plays a named sound if one is loaded. Safe to call when no Sfx exists.
static func play(name: String, pitch_jitter := 0.08) -> void:
	if instance != null:
		instance._play(name, pitch_jitter)


func _play(name: String, pitch_jitter: float) -> void:
	var streams: Array = _streams.get(name, [])
	if streams.is_empty():
		return
	var now := Time.get_ticks_msec()
	var min_interval := int(MIN_INTERVAL_MS.get(name, 0))
	if min_interval > 0 and now - int(_last_played.get(name, -min_interval)) < min_interval:
		return
	_last_played[name] = now
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = streams[randi() % streams.size()]
	player.volume_db = float(VOLUME.get(name, 0.0)) + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()
	_play_count += 1


func has(name: String) -> bool:
	return not (_streams.get(name, []) as Array).is_empty()


func play_count() -> int:
	return _play_count
