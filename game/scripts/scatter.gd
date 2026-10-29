## Draws thousands of copies of a few prototype meshes (building details or
## street props) from a placement list, with one MultiMesh per prototype and
## per square cell, so far-away cells can drop small things. Runs in the
## editor too, so the level looks complete there.
##
## data is a JSON file of {prototype: [entry, ...]}. Entries are
## [x, y, z, yaw, sx, sy, sz, r, g, b] for "details" (the colour tints the
## materials listed in tinted) and [x, z, yaw, scale] for "props".
##
## A prototype with a "<name>_far" mesh in the library (trees, bushes)
## draws its detailed mesh up to far_from metres and the lighter far one
## from there on. Distances count from the middle of a cell, so props use
## small cells.
##
## Props stand on the ground shaped with the map editor's terrain tool
## (scripts/terrain.gd): follow_ground() lifts them to it.
##
## Every placement is a record the map editor (scripts/admin.gd) can find
## under the mouse (pick), take out (remove_record) and put back. Taken out
## records are listed in removed_file ({prototype: [[x, z] or [x, y, z],
## ...]}) and left out from then on.
@tool
class_name Scatter
extends Node3D

const PICK_CELL := 8.0                    # metres; records are found through a grid of these

@export var library: PackedScene          ## glTF whose mesh nodes are the prototypes, by name
@export_file("*.json") var data: String
@export_enum("details", "props") var format := "details"
@export var cell := 96.0
@export var default_range := 300.0
@export var view_ranges := {}             ## prototype: metres it draws up to
@export var no_shadows: PackedStringArray ## prototypes that cast no shadow
@export var tinted: PackedStringArray     ## materials that take the per-entry colour
@export var solid := {}                   ## prototype: trunk radius of a 3 m collision cylinder
@export var far_from := 70.0              ## where "<name>_far" meshes take over
@export_file("*.json") var removed_file := ""   ## records taken out with the map editor

var _built := false
var _removed := {}                        # "proto|x|z" (props) or "proto|x|y|z" (details): true
var _aabbs := {}                          # prototype: AABB of its detailed mesh
var _protos: PackedStringArray = []
# one entry per record (placement)
var _rec_proto := PackedInt32Array()      # index into _protos
var _rec_xform: Array[Transform3D] = []
var _rec_links: Array = []                # [[MultiMesh, instance], ...]: the near and the far copy
var _rec_shape: Array = []                # CollisionShape3D or null
var _rec_removed := PackedByteArray()
var _pick_grid := {}                      # Vector2i: [record, ...]


func _ready() -> void:
	_build()


func _build() -> void:
	if _built or library == null or data.is_empty():
		return
	_built = true
	var lib := library.instantiate()
	var meshes := WorldStyle.shared().mesh_library(lib, Array(tinted))
	lib.free()
	var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data))
	_load_removed()
	var bodies := {}
	for proto: String in entries:
		if not meshes.has(proto):
			push_warning("%s has no prototype %s" % [library.resource_path, proto])
			continue
		_aabbs[proto] = (meshes[proto] as Mesh).get_aabb()
		var proto_id := _protos.size()
		_protos.append(proto)
		var placements := []
		for e: Array in entries[proto]:
			var t: Transform3D
			var colour := Color.WHITE
			if format == "details":
				var basis := Basis(Vector3.UP, e[3]) * Basis.from_scale(Vector3(e[4], e[5], e[6]))
				t = Transform3D(basis, Vector3(e[0], e[1], e[2]))
				colour = Color(e[7], e[8], e[9])
			else:
				t = Transform3D(Basis(Vector3.UP, e[2]).scaled(Vector3.ONE * e[3]), Vector3(e[0], 0.0, e[1]))
			var r := _rec_proto.size()
			_rec_proto.append(proto_id)
			_rec_xform.append(t)
			_rec_links.append([])
			_rec_shape.append(null)
			var gone := _removed.has(_key(proto, t.origin))
			_rec_removed.append(1 if gone else 0)
			placements.append([t, colour, r])
			var pc := _pick_cell(t.origin)
			if not _pick_grid.has(pc):
				_pick_grid[pc] = []
			_pick_grid[pc].append(r)
		var view_range: float = view_ranges.get(proto, default_range)
		var shadows := not proto in no_shadows
		if meshes.has(proto + "_far"):
			_scatter(meshes[proto], placements, minf(far_from, view_range), shadows)
			_scatter(meshes[proto + "_far"], placements, view_range, shadows, far_from)
		else:
			_scatter(meshes[proto], placements, view_range, shadows)
		if solid.has(proto) and not Engine.is_editor_hint():
			var cyl := CylinderShape3D.new()
			cyl.radius = solid[proto]
			cyl.height = 3.0
			for p: Array in placements:
				var key := _cell_of(p[0].origin)
				if not bodies.has(key):
					bodies[key] = StaticBody3D.new()
					add_child(bodies[key])
				var shape := CollisionShape3D.new()
				shape.shape = cyl
				shape.position = p[0].origin + Vector3(0, 1.5, 0)
				shape.disabled = _rec_removed[p[2]] == 1
				bodies[key].add_child(shape)
				_rec_shape[p[2]] = shape


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell))


func _pick_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / PICK_CELL), floori(p.z / PICK_CELL))


## One MultiMesh per cell; each placement is [Transform3D, Color, record].
## Records taken out are drawn at zero size, so they can come back.
func _scatter(mesh: Mesh, placements: Array, view_range: float, shadows: bool, view_from := 0.0) -> void:
	var cells := {}
	for p: Array in placements:
		var key := _cell_of(p[0].origin)
		if not cells.has(key):
			cells[key] = []
		cells[key].append(p)
	for key in cells:
		var items: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			var r: int = items[i][2]
			mm.set_instance_transform(i, _hidden(items[i][0]) if _rec_removed[r] else items[i][0])
			mm.set_instance_custom_data(i, items[i][1])
			_rec_links[r].append([mm, i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_begin = view_from
		mmi.visibility_range_end = view_range
		mmi.visibility_range_begin_margin = 4.0 if view_from > 0.0 else 0.0
		mmi.visibility_range_end_margin = 4.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Puts the props standing in area (x, z) on the ground's current height.
func follow_ground(area: Rect2) -> void:
	if format != "props":
		return
	var c0 := _pick_cell(Vector3(area.position.x, 0, area.position.y))
	var c1 := _pick_cell(Vector3(area.end.x, 0, area.end.y))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for r: int in _pick_grid.get(Vector2i(cx, cz), []):
				var t := _rec_xform[r]
				var y := Terrain.height_at(t.origin.x, t.origin.z)
				if absf(y - t.origin.y) < 0.001:
					continue
				t.origin.y = y
				_rec_xform[r] = t
				for link: Array in _rec_links[r]:
					(link[0] as MultiMesh).set_instance_transform(link[1], _hidden(t) if _rec_removed[r] else t)
				if _rec_shape[r]:
					(_rec_shape[r] as CollisionShape3D).position = t.origin + Vector3(0, 1.5, 0)


func _hidden(t: Transform3D) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), t.origin)


# ----------------------------------------------------------------------------
# Records (map editor)
# ----------------------------------------------------------------------------
func record_count() -> int:
	return _rec_proto.size()


func record_proto(r: int) -> String:
	return _protos[_rec_proto[r]]


func record_transform(r: int) -> Transform3D:
	return _rec_xform[r]


## The record's box in its own space (with record_transform: where it is).
func record_aabb(r: int) -> AABB:
	return _aabbs[record_proto(r)]


func is_removed(r: int) -> bool:
	return _rec_removed[r] == 1


## The nearest record the ray from `from` along `dir` (normalised) passes
## through, up to max_dist: [record, distance], or [] if none. With only,
## just records of those prototypes.
func pick(from: Vector3, dir: Vector3, max_dist: float, only: PackedStringArray = []) -> Array:
	var best := -1
	var best_d := max_dist
	var seen := {}
	var step := PICK_CELL * 0.5
	for s in int(max_dist / step) + 2:
		var c := _pick_cell(from + dir * minf(s * step, max_dist))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := c + Vector2i(dx, dz)
				if seen.has(k):
					continue
				seen[k] = true
				for r: int in _pick_grid.get(k, []):
					if _rec_removed[r] or (not only.is_empty() and not record_proto(r) in only):
						continue
					var t := _rec_xform[r]
					var inv := t.affine_inverse()
					var hit: Variant = record_aabb(r).intersects_ray(inv * from, inv.basis * dir)
					if hit == null:
						continue
					var d := from.distance_to(t * (hit as Vector3))
					if d < best_d:
						best_d = d
						best = r
	return [] if best < 0 else [best, best_d]


## Records standing within radius of p (on the ground plane), optionally only
## of the given prototypes.
func records_near(p: Vector3, radius: float, protos: PackedStringArray = []) -> Array[int]:
	var out: Array[int] = []
	var c0 := _pick_cell(p - Vector3(radius, 0, radius))
	var c1 := _pick_cell(p + Vector3(radius, 0, radius))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for r: int in _pick_grid.get(Vector2i(cx, cz), []):
				if _rec_removed[r] or (not protos.is_empty() and not record_proto(r) in protos):
					continue
				var o := _rec_xform[r].origin
				if Vector2(o.x - p.x, o.z - p.z).length() <= radius:
					out.append(r)
	return out


## The record of proto standing at (or within 5 cm of) origin, or -1.
func find_record(proto: String, origin: Vector3) -> int:
	for r: int in _pick_grid.get(_pick_cell(origin), []):
		if record_proto(r) == proto and _rec_xform[r].origin.distance_to(Vector3(origin.x,
				_rec_xform[r].origin.y if format == "props" else origin.y, origin.z)) < 0.05:
			return r
	return -1


## Takes a record out of the map (and saves the list); restore_record puts
## it back.
func remove_record(r: int, save := true) -> void:
	_set_removed(r, true)
	if save:
		save_removed()


func restore_record(r: int, save := true) -> void:
	_set_removed(r, false)
	if save:
		save_removed()


func _set_removed(r: int, gone: bool) -> void:
	_rec_removed[r] = 1 if gone else 0
	var t := _rec_xform[r]
	for link: Array in _rec_links[r]:
		(link[0] as MultiMesh).set_instance_transform(link[1], _hidden(t) if gone else t)
	if _rec_shape[r]:
		(_rec_shape[r] as CollisionShape3D).disabled = gone
	var key := _key(record_proto(r), t.origin)
	if gone:
		_removed[key] = true
	else:
		_removed.erase(key)


func _key(proto: String, o: Vector3) -> String:
	if format == "props":
		return "%s|%d|%d" % [proto, roundi(o.x * 100.0), roundi(o.z * 100.0)]
	return "%s|%d|%d|%d" % [proto, roundi(o.x * 100.0), roundi(o.y * 100.0), roundi(o.z * 100.0)]


func _load_removed() -> void:
	_removed = {}
	if removed_file.is_empty() or not FileAccess.file_exists(removed_file):
		return
	var listed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(removed_file))
	for proto: String in listed:
		for p: Array in listed[proto]:
			var o := Vector3(p[0], 0.0, p[1]) if p.size() == 2 else Vector3(p[0], p[1], p[2])
			_removed[_key(proto, o)] = true


func save_removed() -> void:
	if removed_file.is_empty():
		return
	var listed := {}
	for r in _rec_removed.size():
		if not _rec_removed[r]:
			continue
		var proto := record_proto(r)
		var o := _rec_xform[r].origin
		if not listed.has(proto):
			listed[proto] = []
		if format == "props":
			listed[proto].append([snappedf(o.x, 0.01), snappedf(o.z, 0.01)])
		else:
			listed[proto].append([snappedf(o.x, 0.01), snappedf(o.y, 0.01), snappedf(o.z, 0.01)])
	var f := FileAccess.open(removed_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(listed))
