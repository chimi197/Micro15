## Cuts an asset's single mesh into parts, so pieces of a playground thing
## (a swing seat and its chains, the seesaw beam) can move on their own.
## part_of(centroid) returns the part index (0 stays with the asset) for
## each triangle, by where its middle is in the mesh's own space. Results are
## cached per mesh and rule name, so eleven swings share one set of meshes.
class_name MeshSplit
extends RefCounted

static var _cache := {}


## Returns [ArrayMesh per part]; a part with no triangles is an empty mesh.
static func split(mesh: Mesh, parts: int, rule: String, part_of: Callable) -> Array:
	var key := "%d|%s" % [mesh.get_instance_id(), rule]
	if _cache.has(key):
		return _cache[key]
	var out := []
	for i in parts:
		out.append(ArrayMesh.new())
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
				else PackedInt32Array(range(verts.size()))
		var buckets := []
		for i in parts:
			buckets.append(PackedInt32Array())
		for t in range(0, idx.size(), 3):
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			var p: int = clampi(part_of.call(c), 0, parts - 1)
			buckets[p].append(idx[t])
			buckets[p].append(idx[t + 1])
			buckets[p].append(idx[t + 2])
		for i in parts:
			if (buckets[i] as PackedInt32Array).is_empty():
				continue
			var a := arrays.duplicate()
			a[Mesh.ARRAY_INDEX] = buckets[i]
			var m: ArrayMesh = out[i]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			m.surface_set_material(m.get_surface_count() - 1, mesh.surface_get_material(s))
	_cache[key] = out
	return out


## Replaces the asset's Model mesh by part 0 and adds a MeshInstance3D per
## other part under a pivot node each (pivots[i] = its pivot point in the
## asset's space, or null for no pivot). Returns the pivot Node3Ds.
static func apply(asset: Node3D, parts: Array, pivots: Array) -> Array:
	var model := asset.get_node_or_null("Model") as MeshInstance3D
	var nodes := []
	if model == null:
		return nodes
	model.mesh = parts[0]
	WorldStyle.shared().apply(model)
	for i in range(1, parts.size()):
		var pivot := Node3D.new()
		pivot.name = "Moving%d" % i
		var at: Vector3 = pivots[i] if pivots[i] != null else Vector3.ZERO
		pivot.position = at
		asset.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i]
		mi.position = -at
		mi.visibility_range_end = model.visibility_range_end
		pivot.add_child(mi)
		WorldStyle.shared().apply(mi)
		nodes.append(pivot)
	return nodes
