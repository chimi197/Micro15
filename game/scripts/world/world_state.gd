## The world's moving conditions, shared by every shader through global
## uniforms (project.godot [shader_globals]):
##
## * wind: a slowly wandering direction and strength with gusts that roll
##   across the map; grass and tree crowns read it, so they move together
## * player_position: grass bends away from the boy's feet
## * world_night is set by SunCycle (lit windows, lamps, stars)
##
## It also lights the street lamps near the camera at night (a small pool
## of OmniLight3Ds moved to the nearest lamp heads; every lamp's glass glows
## through its material) and draws the stars and the moon (StarDome).
class_name WorldState
extends Node3D

const LAMP_HEAD := Vector3(1.35, 6.62, 0.0)     # under the lamp's head, in its own space
const LIGHTS := 10

@export var base_wind := 0.18
@export var player: Node3D

var _t := 0.0
var _lamps: PackedVector3Array = []
var _lights: Array[OmniLight3D] = []
var _relight := 0.0
var _night := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = 15
	_noise.frequency = 0.05
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.omni_range = 11.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_specular = 0.3
		l.visible = false
		add_child(l)
		_lights.append(l)
	var dome := StarDome.new()
	dome.name = "Stars"
	add_child(dome)
	_find_lamps.call_deferred()


func _find_lamps() -> void:
	var level := get_parent()
	var props := level.get_node_or_null("Props")
	if props and props.has_method("record_count"):
		for r in props.record_count():
			if props.record_proto(r) == "lamp" and not props.is_removed(r):
				_lamps.append(props.record_transform(r) * LAMP_HEAD)
	var placed := level.get_node_or_null("Placed")
	if placed:
		for c in placed.get_children():
			if c is Node3D and c.scene_file_path.ends_with("/lamp.tscn"):
				_lamps.append((c as Node3D).global_transform * LAMP_HEAD)


func _process(delta: float) -> void:
	_t += delta
	# the breeze wanders a little in direction and strength, with gusts
	var a := 0.33 + _noise.get_noise_1d(_t * 0.2) * 0.6
	var gust := maxf(_noise.get_noise_1d(_t * 1.3 + 100.0), 0.0) * 1.6
	var strength := base_wind * (0.8 + gust)
	RenderingServer.global_shader_parameter_set("wind", Vector4(cos(a), sin(a), strength, 1.0 + gust))
	if player:
		RenderingServer.global_shader_parameter_set("player_position", player.global_position)
	_night = SunCycle.night
	_relight -= delta
	if _relight <= 0.0:
		_relight = 0.5
		_place_lights()
	for l in _lights:
		l.light_energy = move_toward(l.light_energy, 1.6 * _night if l.visible else 0.0, delta * 2.0)


## Moves the light pool to the lamps nearest the camera.
func _place_lights() -> void:
	var cam := get_viewport().get_camera_3d()
	var on := _night > 0.05 and cam != null and not _lamps.is_empty()
	if not on:
		for l in _lights:
			l.visible = false
		return
	var at := cam.global_position
	var near: Array = []
	for p in _lamps:
		var d := p.distance_squared_to(at)
		if d < 90.0 * 90.0:
			near.append([d, p])
	near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for i in _lights.size():
		var l := _lights[i]
		if i < near.size():
			var p: Vector3 = near[i][1]
			if not l.visible or l.global_position.distance_to(p) > 0.1:
				l.global_position = p
				l.light_energy = 0.0 if not l.visible else l.light_energy
			l.visible = true
		else:
			l.visible = false
