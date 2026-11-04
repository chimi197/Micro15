## All the game's sound: the ambience bed (day birds and wind, night
## crickets, crossfaded by the time of day), the boy's footsteps by what he
## walks on (Surfaces), and one-off sounds at a place in the world from
## anything that asks (group "sound": play_at(name, position, strength)).
##
## The files are in game/audio/, made by tools/make_sounds.py; a real
## recording can replace any of them under the same name. Two buses,
## Ambience and Effects, follow the volume settings (Save).
class_name SoundDirector
extends Node

const POOL := 14
const VARIANTS := {"step": 4, "creak": 3, "life_carpet": 2}
## Unseen neighbours (no people in the world, but the yard is lived in):
## sound, hours it can be heard, and how far off it plays (metres).
const LIFE := [
	["life_carpet", 8.0, 19.0, 18.0, 45.0],
	["life_ball", 9.0, 20.5, 15.0, 40.0],
	["life_door", 6.0, 23.5, 10.0, 35.0],
	["life_window", 7.0, 23.0, 12.0, 40.0],
]

var player: Node3D
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _sun: Node
var _walls: PackedVector3Array = []          # corners of the buildings (footprints.json)
var _life_in := 8.0


func _ready() -> void:
	add_to_group("sound")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for bus in ["Ambience", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Effects"
		p.unit_size = 4.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_pool.append(p)
	_day = _loop("amb_day")
	_night = _loop("amb_night")
	Save.settings_changed.connect(_apply_volumes)
	_apply_volumes()
	if player:
		player.stepped.connect(_on_step)
		player.landed.connect(_on_land)
	var scene := get_tree().current_scene
	_sun = scene.get_node_or_null("SunCycle") if scene else null
	if scene:
		var fp := scene.scene_file_path.get_base_dir().path_join("footprints.json")
		if FileAccess.file_exists(fp):
			var rings: Variant = JSON.parse_string(FileAccess.get_file_as_string(fp))
			if rings is Dictionary:
				for ring: Array in rings.values():
					for c: Array in ring:
						_walls.append(Vector3(c[0], 1.5, c[1]))


func _loop(name: String) -> AudioStreamPlayer:
	var s := _stream(name) as AudioStreamWAV
	var p := AudioStreamPlayer.new()
	p.bus = "Ambience"
	if s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
	add_child(p)
	p.play()
	return p


func _apply_volumes() -> void:
	for pair: Array in [["Ambience", "volume_ambience"], ["Effects", "volume_effects"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(Save.setting(pair[1])), 0.0001)))


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := "res://audio/%s.wav" % name
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


## Plays name (a file in audio/, or a family with variants: "creak") at a
## place; strength 0..1 sets loudness and a little pitch.
func play_at(name: String, at: Vector3, strength := 1.0) -> void:
	var file := name
	if VARIANTS.has(name):
		file = "%s_%d" % [name, randi() % VARIANTS[name]]
	var s := _stream(file)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.global_position = at
	p.volume_db = linear_to_db(clampf(strength, 0.05, 1.0)) - 2.0
	p.pitch_scale = randf_range(0.94, 1.06) * lerpf(1.06, 0.96, clampf(strength, 0.0, 1.0))
	p.play()


func _on_step(side: String, strength: float, surface: String) -> void:
	var file := "step_%s_%d" % [surface, randi() % 4]
	if _stream(file) == null:
		file = "step_concrete_%d" % (randi() % 4)
	var s := _stream(file)
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	var foot: Vector3 = player.global_position + player.facing().cross(Vector3.UP) * (0.08 if side == "R" else -0.08)
	p.global_position = foot
	var crouch: bool = player.crouching
	p.volume_db = linear_to_db(clampf(strength * (0.45 if crouch else 0.8), 0.05, 1.0)) - 4.0
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _on_land(fall: float) -> void:
	if fall < 0.25:
		return
	var surface := Surfaces.at(player, player.global_position)
	play_at("land_" + surface, player.global_position, clampf(fall / 2.0, 0.3, 1.0))


func _process(delta: float) -> void:
	_life_in -= delta
	if _life_in <= 0.0:
		_life_in = randf_range(9.0, 24.0)
		_neighbours()
	var hour := 12.0
	if _sun and _sun.get("time_of_day") != null:
		hour = _sun.time_of_day
	# daylight weight: 0 at night, 1 by day, easing over dawn and dusk
	var day := smoothstep(4.8, 6.8, hour) * (1.0 - smoothstep(20.2, 22.0, hour))
	_day.volume_db = linear_to_db(maxf(day, 0.0001))
	_night.volume_db = linear_to_db(maxf(1.0 - day, 0.0001)) - 2.0


## Somebody, somewhere in the yard, doing something: played at a building
## corner at a distance from the boy.
func _neighbours() -> void:
	if player == null or _walls.is_empty():
		return
	var hour := 12.0
	if _sun and _sun.get("time_of_day") != null:
		hour = _sun.time_of_day
	var choices := LIFE.filter(func(l: Array) -> bool: return hour >= l[1] and hour <= l[2])
	if choices.is_empty():
		return
	var pick: Array = choices[randi() % choices.size()]
	var at: Vector3 = player.global_position
	for i in 40:
		var w := _walls[randi() % _walls.size()]
		var d := Vector2(w.x - at.x, w.z - at.z).length()
		if d > pick[3] and d < pick[4]:
			var p := _pool[_next]
			_next = (_next + 1) % POOL
			var file: String = pick[0]
			if VARIANTS.has(file):
				file = "%s_%d" % [file, randi() % VARIANTS[file]]
			p.stream = _stream(file)
			p.global_position = w
			p.volume_db = -6.0
			p.pitch_scale = randf_range(0.95, 1.05)
			p.play()
			return
