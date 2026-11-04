## What the ground is made of at a point, for footsteps and landings:
## asphalt, paving, concrete, grass, dirt, gravel, sand, wood or metal.
##
## Looks, in order, at: a "surface" meta on whatever was hit (placed assets
## and interactables can set one), lawn grass (GrassField), paths drawn with
## the map editor, and otherwise the material of the ground mesh's triangle
## under the point (its name goes through MaterialLibrary's families).
class_name Surfaces
extends RefCounted

const FAMILY_SURFACE := {
	"asphalt": "asphalt", "paving": "paving", "concrete": "concrete", "plaster": "concrete",
	"gravel": "gravel", "soil": "dirt", "lawn": "grass", "wood": "wood", "painted_metal": "metal",
	"bare_metal": "metal", "rubber": "rubber", "roof": "concrete", "paint": "concrete",
}
const PATH_SURFACE := {"sidewalk": "paving", "footpath": "paving", "trail": "dirt", "trodden": "dirt"}
const ASSET_SURFACE := {
	"slide": "metal", "sandbox": "sand", "bench": "wood", "bench_wood": "wood", "picnic_table": "wood",
	"terrace_table": "wood", "chess_table": "concrete", "seesaw": "wood", "manhole": "metal",
	"dumpster": "metal", "fruit_stand": "wood", "bus_stop": "concrete",
}

static var _tris := {}                    # mesh instance id: [[PackedVector2Array tri xz..., surface name], ...]


static func at(from: Node3D, p: Vector3) -> String:
	var space := from.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * 0.6)
	if from is CollisionObject3D:
		q.exclude = [(from as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return "grass"
	var col := hit.collider as Node
	for n: Node in [col, col.get_parent()]:
		if n and n.has_meta("surface"):
			return n.get_meta("surface")
	var asset := _asset_name(col)
	if asset != "":
		return ASSET_SURFACE.get(asset, "concrete")
	if PathNetwork.current and PathNetwork.covers(p.x, p.z):
		return PATH_SURFACE.get(PathNetwork.current.type_at(p.x, p.z), "paving")
	if GrassField.current and GrassField.current.is_lawn(p.x, p.z):
		return "grass"
	var mi := col.get_parent() as MeshInstance3D
	if mi:
		var name := _material_under(mi, hit.position)
		if name != "":
			return _from_material(name)
	return "concrete"


static func _asset_name(n: Node) -> String:
	while n:
		if n.scene_file_path.begins_with("res://assets/"):
			return n.scene_file_path.get_file().get_basename()
		n = n.get_parent()
	return ""


static func _from_material(name: String) -> String:
	var base := name.trim_prefix("C3_").trim_prefix("CH_")
	for m: Array in MaterialLibrary.MATCH:
		if base.begins_with(m[0]):
			return FAMILY_SURFACE.get(m[1], "concrete")
	return "concrete"


## Name of the material of the triangle of mi straight under p.
static func _material_under(mi: MeshInstance3D, p: Vector3) -> String:
	var key := mi.get_instance_id()
	if not _tris.has(key):
		var list := []
		var mesh := mi.mesh
		if mesh == null:
			return ""
		for s in mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var name: String = mesh.surface_get_name(s) if mesh is ArrayMesh else ""
			if mat and mat.resource_name != "":
				name = mat.resource_name
			elif mesh.surface_get_material(s):
				name = mesh.surface_get_material(s).resource_name
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var flat := PackedVector2Array()
			if idx.is_empty():
				for v in verts:
					flat.append(Vector2(v.x, v.z))
			else:
				for i in idx:
					flat.append(Vector2(verts[i].x, verts[i].z))
			list.append([flat, name])
		_tris[key] = list
	var local := mi.global_transform.affine_inverse() * p
	var q := Vector2(local.x, local.z)
	for entry: Array in _tris[key]:
		var flat: PackedVector2Array = entry[0]
		for i in range(0, flat.size() - 2, 3):
			if Geometry2D.point_is_inside_triangle(q, flat[i], flat[i + 1], flat[i + 2]):
				return entry[1]
	return ""
