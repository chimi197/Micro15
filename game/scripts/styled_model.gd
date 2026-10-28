## Put on the root of an imported glTF scene (or any node with meshes under
## it) to draw it with the game's materials (MaterialLibrary), in the
## editor too.
## With solid, its meshes also get trimesh collision when the game runs.
## With removed_file, single meshes (one building each, for Micro 15) can be
## taken out with the map editor; their names are listed in that file.
@tool
class_name StyledModel
extends Node3D

@export var solid := false
@export_file("*.json") var removed_file := ""

var saving := true                       # (the self-test turns saving off)
var _removed: Array = []                 # names of the meshes taken out
var _face_tables := {}                   # mesh: [first triangle of each surface]


func _ready() -> void:
	# a scene opened on its own in the editor keeps its plain glTF colours,
	# so the game's copies are never saved into it
	if Engine.is_editor_hint() and get_tree().edited_scene_root == self:
		return
	WorldStyle.shared().apply(self)
	if solid and not Engine.is_editor_hint():
		for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			mi.create_trimesh_collision()
	if not removed_file.is_empty() and FileAccess.file_exists(removed_file):
		_removed = JSON.parse_string(FileAccess.get_file_as_string(removed_file))
		for part_name: String in _removed.duplicate():
			var mi := find_child(part_name, true, false) as MeshInstance3D
			if mi:
				_show_part(mi, false)


## The mesh of this model that node (a mesh or its collision body) belongs to.
func part_of(node: Node) -> MeshInstance3D:
	while node and node != self:
		if node is MeshInstance3D:
			return node
		node = node.get_parent()
	return null


## The material name of the surface a ray hit (collider and face_index from
## intersect_ray) on one of this model's meshes, or "".
func surface_at(collider: Object, face_index: int) -> String:
	var mi := part_of(collider as Node)
	if mi == null or face_index < 0:
		return ""
	var mesh := mi.mesh
	if not _face_tables.has(mesh):
		var starts := []
		var total := 0
		for s in mesh.get_surface_count():
			starts.append(total)
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
			total += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		_face_tables[mesh] = starts
	var starts: Array = _face_tables[mesh]
	var surface := 0
	while surface + 1 < starts.size() and face_index >= starts[surface + 1]:
		surface += 1
	var m := mesh.surface_get_material(surface)
	return m.resource_name if m else ""


func remove_part(mi: MeshInstance3D) -> void:
	_show_part(mi, false)
	if not String(mi.name) in _removed:
		_removed.append(String(mi.name))
	_save()


func restore_part(mi: MeshInstance3D) -> void:
	_show_part(mi, true)
	_removed.erase(String(mi.name))
	_save()


func _show_part(mi: MeshInstance3D, on: bool) -> void:
	mi.visible = on
	for body in mi.get_children():
		if body is CollisionObject3D:
			body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _save() -> void:
	if removed_file.is_empty() or not saving:
		return
	var f := FileAccess.open(removed_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_removed))
