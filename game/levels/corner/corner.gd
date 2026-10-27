## Fully 3D corner of Micro 15: modelled blocks of flats with balconies,
## 3D trees and bushes, 3D grass, toon shading and ink outlines.
##
## Run normally to walk around. Run with `-- --shots` to save preview
## screenshots to ../docs/renders/ and quit.
extends Node3D

const SHADOW_TINT := Color(0.70, 0.72, 0.90)
const FOLIAGE := ["leaf", "poplar", "bush"]
const SOLID_PROPS := {"tree_a": 0.35, "tree_b": 0.4, "tree_c": 0.3, "poplar": 0.3, "lamp": 0.15}
# name: [camera position, look-at target, player position or null]
const SHOTS := {
	"corner_street": [Vector3(14, 2.6, 13.5), Vector3(100, 4.0, 4), Vector3(18.5, 0.15, 9.5)],
	"corner_facade": [Vector3(38, 2.2, 9.5), Vector3(56, 7.0, -1), Vector3(41, 0.15, 7.5)],
	"corner_alley": [Vector3(-66, 2.4, -12), Vector3(-70, 4, -80), Vector3(-68, 0.15, -17)],
	"corner_lawn": [Vector3(-8, 1.4, -38), Vector3(-25, 3.0, -62), Vector3(-10, 0.15, -42)],
	"corner_balconies": [Vector3(-48, 9, 66), Vector3(-5, 9, 25), null],
	"corner_high": [Vector3(60, 18, 50), Vector3(0, 4, -20), null],
	"corner_aerial": [Vector3(-95, 60, 95), Vector3(10, 0, -10), null],
}

var player: CharacterBody3D
var _materials := {}


func _ready() -> void:
	_setup_environment()
	_load_level()
	_spawn_props()
	var grass := GrassField.new()
	grass.mask = load("res://levels/corner/grass_mask.png")
	add_child(grass)
	_add_ink_outline_pass()
	player = preload("res://scripts/player.gd").new()
	player.position = Vector3(18, 0.3, 9)
	add_child(player)
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe6f7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = SHADOW_TINT
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("#bfe6f7")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 0.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5      # keeps round tree canopies free of shadow acne
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)


## Turns an imported glTF material into the matching cel-shaded one, keyed
## by material name so identical colours share one material.
func _convert(src: Material) -> Material:
	var mname := src.resource_name if src else "default"
	if _materials.has(mname):
		return _materials[mname]
	var colour := Color.WHITE
	if src is BaseMaterial3D:
		colour = (src as BaseMaterial3D).albedo_color
	var mat := ShaderMaterial.new()
	var lower := mname.to_lower()
	if lower.ends_with("lawn"):
		mat.shader = preload("res://shaders/lawn.gdshader")
		var noise := NoiseTexture2D.new()
		noise.seamless = true
		noise.noise = FastNoiseLite.new()
		noise.noise.frequency = 0.02
		mat.set_shader_parameter("noise_tex", noise)
		mat.set_shader_parameter("tint", colour)
	elif FOLIAGE.any(func(k): return lower.contains(k)):
		mat.shader = preload("res://shaders/foliage.gdshader")
		mat.set_shader_parameter("tint", colour)
	else:
		mat.shader = preload("res://shaders/toon.gdshader")
		mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("shadow_tint", SHADOW_TINT)
	_materials[mname] = mat
	return mat


func _apply_toon(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _convert(mi.mesh.surface_get_material(s)))


func _load_level() -> void:
	var outer := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	outer.mesh = plane
	outer.position.y = -0.05
	var lawn_src := StandardMaterial3D.new()
	lawn_src.resource_name = "C3_lawn"
	lawn_src.albedo_color = Color("#8cc456")
	outer.material_override = _convert(lawn_src)
	add_child(outer)

	var level: Node3D = load("res://levels/corner/corner.glb").instantiate()
	add_child(level)
	_apply_toon(level)
	for mi: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()


func _spawn_props() -> void:
	var lib: Node3D = load("res://levels/corner/props.glb").instantiate()
	_apply_toon(lib)
	var meshes := {}
	for mi: MeshInstance3D in lib.find_children("*", "MeshInstance3D", true, false):
		meshes[mi.name] = mi
	var f := FileAccess.open("res://levels/corner/props.json", FileAccess.READ)
	var props: Array = JSON.parse_string(f.get_as_text())
	for p in props:
		var src: MeshInstance3D = meshes.get(p["type"])
		if src == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		for s in src.mesh.get_surface_count():
			mi.set_surface_override_material(s, src.get_surface_override_material(s))
		var pos: Array = p["pos"]
		mi.position = Vector3(pos[0], 0.0, pos[1])
		mi.rotation.y = p["rot"]
		mi.scale = Vector3.ONE * float(p["scale"])
		add_child(mi)
		if SOLID_PROPS.has(p["type"]):
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = SOLID_PROPS[p["type"]]
			cyl.height = 3.0
			shape.shape = cyl
			shape.position.y = 1.5
			body.add_child(shape)
			mi.add_child(body)
	lib.queue_free()


func _add_ink_outline_pass() -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ink_outline.gdshader")
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


func _take_shots() -> void:
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.far = 2000
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for shot_name in SHOTS:
		var shot: Array = SHOTS[shot_name]
		cam.position = shot[0]
		cam.look_at(shot[1])
		player.visible = shot[2] != null
		if shot[2] != null:
			player.position = shot[2]
			player.body_mesh.rotation.y = atan2(shot[1].x - shot[0].x, shot[1].z - shot[0].z)
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	get_tree().quit()
