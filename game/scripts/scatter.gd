## Draws thousands of copies of a few prototype meshes (building details or
## street props) from a placement list, with one MultiMesh per prototype and
## per square cell, so far-away cells can drop small things. Runs in the
## editor too, so the level looks complete there.
##
## data is a JSON file of {prototype: [entry, ...]}. Entries are
## [x, y, z, yaw, sx, sy, sz, r, g, b] for "details" (the colour tints the
## materials listed in tinted) and [x, z, yaw, scale] for "props".
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

var _built := false


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
				var basis := Basis(Vector3.UP, e[2]).scaled(Vector3.ONE * e[3])
				placements.append([Transform3D(basis, Vector3(e[0], 0.0, e[1])), Color.WHITE])
		_scatter(meshes[proto], placements, view_ranges.get(proto, default_range), not proto in no_shadows)
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


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell))


## One MultiMesh per cell; each placement is [Transform3D, Color].
func _scatter(mesh: Mesh, placements: Array, view_range: float, shadows: bool) -> void:
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
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = view_range
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
