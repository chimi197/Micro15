## Shared look of every outdoor level (docs/art_direction.md): turns
## imported glTF materials into the game's materials (MaterialLibrary),
## plus helpers that add the environment (style/) and the optional ink pass
## to levels built from code. Runs in the editor too, so the scenes look
## the same there as in the game.
@tool
class_name WorldStyle
extends RefCounted

const ENVIRONMENT := "res://style/world_environment.tres"
const INK := "res://style/ink_outline.tres"

static var _shared: WorldStyle

var _materials := {}


## One style for the whole game, so identical colours share one material.
static func shared() -> WorldStyle:
	if _shared == null:
		_shared = WorldStyle.new()
	return _shared


## Sky, ambient shadow tint, fog and the sun (the micro15 scene has these
## as nodes; the corner test level adds them from code).
static func add_environment(parent: Node, fog_density := 0.0012, shadow_distance := 220.0) -> DirectionalLight3D:
	var we := WorldEnvironment.new()
	we.environment = load(ENVIRONMENT).duplicate()
	we.environment.fog_density = fog_density
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	setup_sun(sun, shadow_distance)
	parent.add_child(sun)
	return sun


static func setup_sun(sun: DirectionalLight3D, shadow_distance := 220.0) -> void:
	sun.rotation_degrees = Vector3(-46, 35, 0)       # same as the Sun in micro15.tscn
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5      # keeps round tree canopies free of shadow acne
	sun.directional_shadow_max_distance = shadow_distance
	# a small first split keeps shadows on and around the player crisp
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.1
	sun.directional_shadow_split_3 = 0.3
	sun.directional_shadow_blend_splits = true


## Full-screen ink lines (see ink_outline.gdshader). Off by default: the
## art direction draws forms with light; the admin tool can turn them on.
static func add_ink_outline(parent: Node) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = "InkOutline"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	quad.material_override = load(INK)
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.visible = false
	parent.add_child(quad)
	return quad


## The game's version of an imported glTF material (see
## MaterialLibrary), keyed by material name so identical materials share
## one. With instance_tint the material also takes a per-instance colour
## from a MultiMesh's custom data.
func material_for(src: Material, instance_tint := false) -> Material:
	if src is ShaderMaterial:
		return src                    # already one of ours
	var mname := src.resource_name if src else "default"
	var key := mname + ("#tinted" if instance_tint else "")
	if not _materials.has(key):
		var colour := (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color.WHITE
		_materials[key] = MaterialLibrary.make(mname, colour, instance_tint)
	return _materials[key]


## Swaps every surface material of root and the meshes under it for its
## game version. Surface overrides on nodes inside an instanced scene
## are not saved with the scene, so this is safe to run in the editor.
func apply(root: Node) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, material_for(mi.mesh.surface_get_material(s)))


## Meshes of a prototype library (details.glb, props.glb) by node name,
## with the game's materials baked into copies of the meshes so they can be
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
