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
## Props can be taken out with the admin tool (remove_near); they are
## listed in removed_file ({prototype: [[x, z], ...]}) and left out from
## then on.
@tool
class_name Scatter
extends Node3D

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
@export_file("*.json") var removed_file := ""   ## props taken out with the admin tool

var _built := false
var _removed := {}                        # prototype: [[x, z], ...]
var _items: Array = []                    # props: [prototype, MultiMesh, index, Transform3D, CollisionShape3D]


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
	if not removed_file.is_empty() and FileAccess.file_exists(removed_file):
		_removed = JSON.parse_string(FileAccess.get_file_as_string(removed_file))
	var bodies := {}
	for proto: String in entries:
		if not meshes.has(proto):
			push_warning("%s has no prototype %s" % [library.resource_path, proto])
			continue
		var placements := []
		for e: Array in entries[proto]:
			if format == "details":
				var basis := Basis(Vector3.UP, e[3]) * Basis.from_scale(Vector3(e[4], e[5], e[6]))
				placements.append([Transform3D(basis, Vector3(e[0], e[1], e[2])), Color(e[7], e[8], e[9])])
			else:
				if _is_removed(proto, e[0], e[1]):
					continue
				var basis := Basis(Vector3.UP, e[2]).scaled(Vector3.ONE * e[3])
				placements.append([Transform3D(basis, Vector3(e[0], 0.0, e[1])), Color.WHITE])
		var first := _items.size()
		var view_range: float = view_ranges.get(proto, default_range)
		var shadows := not proto in no_shadows
		if meshes.has(proto + "_far"):
			_scatter(proto, meshes[proto], placements, minf(far_from, view_range), shadows)
			_scatter(proto, meshes[proto + "_far"], placements, view_range, shadows, far_from)
		else:
			_scatter(proto, meshes[proto], placements, view_range, shadows)
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
				bodies[key].add_child(shape)
			for i in range(first, _items.size()):
				_items[i][4] = _shape_at(bodies, _items[i][3].origin)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell))


func _shape_at(bodies: Dictionary, p: Vector3) -> CollisionShape3D:
	var body: StaticBody3D = bodies.get(_cell_of(p))
	if body:
		for shape: CollisionShape3D in body.get_children():
			if is_equal_approx(shape.position.x, p.x) and is_equal_approx(shape.position.z, p.z):
				return shape
	return null


## One MultiMesh per cell; each placement is [Transform3D, Color].
func _scatter(proto: String, mesh: Mesh, placements: Array, view_range: float, shadows: bool,
		view_from := 0.0) -> void:
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
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_custom_data(i, items[i][1])
			if format == "props":
				_items.append([proto, mm, i, items[i][0], null])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_begin = view_from
		mmi.visibility_range_end = view_range
		mmi.visibility_range_begin_margin = 4.0 if view_from > 0.0 else 0.0
		mmi.visibility_range_end_margin = 4.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ----------------------------------------------------------------------------
# Taking props out (admin tool)
# ----------------------------------------------------------------------------
func _is_removed(proto: String, x: float, z: float) -> bool:
	for r: Array in _removed.get(proto, []):
		if absf(r[0] - x) < 0.05 and absf(r[1] - z) < 0.05:
			return true
	return false


## Hides the prop nearest to p (within radius, on the ground plane) and
## saves it in removed_file. Returns [prototype, position], or [] if none.
func remove_near(p: Vector3, radius := 1.5) -> Array:
	var best := -1
	var best_d := radius
	for i in _items.size():
		var it: Array = _items[i]
		if it[1] == null:
			continue
		var o: Vector3 = it[3].origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return []
	var it: Array = _items[best]
	var o: Vector3 = it[3].origin
	for other: Array in _items:              # the detailed and the far mesh
		if other[0] == it[0] and other[3].origin.is_equal_approx(o):
			other[1].set_instance_transform(other[2], Transform3D(Basis.from_scale(Vector3.ZERO), o))
			if other[4]:
				other[4].disabled = true
	if not _removed.has(it[0]):
		_removed[it[0]] = []
	_removed[it[0]].append([snappedf(o.x, 0.01), snappedf(o.z, 0.01)])
	_save_removed()
	return [it[0], o]


## Puts back a prop taken out with remove_near (undo).
func restore(proto: String, at: Vector3) -> void:
	for it: Array in _items:
		if it[0] == proto and it[3].origin.is_equal_approx(at):
			it[1].set_instance_transform(it[2], it[3])
			if it[4]:
				it[4].disabled = false
	var kept := []
	for r: Array in _removed.get(proto, []):
		if absf(r[0] - at.x) >= 0.05 or absf(r[1] - at.z) >= 0.05:
			kept.append(r)
	_removed[proto] = kept
	_save_removed()


func _save_removed() -> void:
	if removed_file.is_empty():
		return
	var f := FileAccess.open(removed_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_removed))
