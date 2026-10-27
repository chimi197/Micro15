## Shared look of every outdoor level: sky, sun, ambient shadow tint,
## cel-shaded materials made from imported glTF colours, and the ink pass.
class_name WorldStyle
extends RefCounted

const SHADOW_TINT := Color(0.70, 0.72, 0.90)
const SKY := Color("#bfe6f7")
const FOLIAGE := ["leaf", "poplar", "bush"]

var _materials := {}


static func add_environment(parent: Node, fog_density := 0.0012, shadow_distance := 220.0) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = SHADOW_TINT
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = SKY
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 0.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5      # keeps round tree canopies free of shadow acne
	sun.directional_shadow_max_distance = shadow_distance
	# a small first split keeps shadows on and around the player crisp
	sun.directional_shadow_split_1 = 0.03
	sun.directional_shadow_split_2 = 0.1
	sun.directional_shadow_split_3 = 0.3
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)
	return sun


## Full-screen ink lines (see ink_outline.gdshader).
static func add_ink_outline(parent: Node) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ink_outline.gdshader")
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(quad)


## Turns an imported glTF material into the matching cel-shaded one, keyed
## by material name so identical colours share one material. With
## instance_tint the material also takes a per-instance colour from a
## MultiMesh's custom data. Character materials (CH_*) only get ink on their
## outer edges, so faces, hair and clothes are not covered in lines.
func material_for(src: Material, instance_tint := false) -> Material:
	var mname := src.resource_name if src else "default"
	var key := mname + ("#tinted" if instance_tint else "")
	if _materials.has(key):
		return _materials[key]
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
	elif FOLIAGE.any(func(k): return lower.contains(k)):
		mat.shader = preload("res://shaders/foliage.gdshader")
	else:
		mat.shader = preload("res://shaders/toon.gdshader")
		mat.set_shader_parameter("instance_tint", instance_tint)
		if mname.begins_with("CH_"):
			mat.set_shader_parameter("ink", 0.5)
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("shadow_tint", SHADOW_TINT)
	_materials[key] = mat
	return mat


## Swaps every surface material under root for its cel-shaded version.
func apply(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, material_for(mi.mesh.surface_get_material(s)))


## Meshes of a prototype library (details.glb, props.glb) by node name,
## with cel-shaded materials baked into copies of the meshes so they can be
## drawn by MultiMeshes. Surfaces whose material is listed in tinted read
## a per-instance colour.
func mesh_library(root: Node, tinted: Array = []) -> Dictionary:
	var out := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh.duplicate()
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			mesh.surface_set_material(s, material_for(src, src != null and src.resource_name in tinted))
		out[String(mi.name)] = mesh
	return out
