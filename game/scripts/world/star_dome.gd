## Stars and the moon for the night sky: a big dome round the camera drawn
## behind everything, fading in with world_night, and a soft moon disc where
## SunCycle puts the moonlight. (The sky itself stays SunCycle's
## ProceduralSkyMaterial, so the editor's sky colours keep working.)
class_name StarDome
extends Node3D

const RADIUS := 2400.0

var _dome: MeshInstance3D
var _moon: MeshInstance3D


func _ready() -> void:
	_dome = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.flip_faces = true
	_dome.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/stars.gdshader")
	_dome.material_override = mat
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.extra_cull_margin = 16384.0
	add_child(_dome)
	_moon = MeshInstance3D.new()
	var disc := SphereMesh.new()
	disc.radius = 34.0
	disc.height = 68.0
	_moon.mesh = disc
	var mm := ShaderMaterial.new()
	mm.shader = preload("res://shaders/moon.gdshader")
	_moon.material_override = mm
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon.extra_cull_margin = 16384.0
	add_child(_moon)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var night := SunCycle.night
	visible = night > 0.01
	if not visible:
		return
	global_position = cam.global_position
	var sun: DirectionalLight3D = get_tree().current_scene.get_node_or_null("Sun") as DirectionalLight3D if get_tree().current_scene else null
	if sun:
		var to_moon := sun.global_basis.z.normalized()      # the light shines along -z
		_moon.global_position = cam.global_position + to_moon * (RADIUS - 100.0)
