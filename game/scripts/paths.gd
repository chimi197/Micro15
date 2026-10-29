## Sidewalks, footpaths and trails drawn with the map editor's Paths tool.
## Each path is a line of points with a type and a width; it is built as a
## strip that follows the ground (Terrain): a sidewalk is raised paving with
## kerbs you can walk up, a footpath is paving level with the lawn and a
## trail is packed earth. Grass does not grow on them.
##
## Saved in levels/micro15/paths.json:
##   [{"type": "sidewalk", "width": 2.0, "points": [[x, z], ...]}, ...]
class_name PathNetwork
extends Node3D

const TYPES := {
	"sidewalk": {"name": "Sidewalk", "width": 2.0, "top": 0.12, "top_material": "C3_pavement",
			"side_material": "C3_kerb", "solid": true},
	"footpath": {"name": "Footpath", "width": 1.6, "top": 0.035, "top_material": "C3_pavement",
			"side_material": "", "solid": false},
	"trail": {"name": "Trail", "width": 1.2, "top": 0.03, "top_material": "C3_path_trail",
			"side_material": "", "solid": false},
}
const STEP := 0.5                       ## metres between the points of a strip, along and across
const GRID := 8.0                       ## metres; cells of the lookup grid

static var current: PathNetwork

@export_file("*.json") var data_file := "res://levels/micro15/paths.json"

var saving := true
var paths: Array = []                    # {"type", "width", "points": [[x, z], ...]}
var _nodes: Array = []                   # Node3D per path
var _grid := {}                          # Vector2i: [[path, a: Vector2, b: Vector2, half width], ...]
var _materials := {}


func _ready() -> void:
	current = self
	if not data_file.is_empty() and FileAccess.file_exists(data_file):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_file))
		if d is Array:
			paths = d
	_build_all()
	if Terrain.current:
		Terrain.current.changed.connect(_on_ground_changed)


func _exit_tree() -> void:
	if current == self:
		current = null


## Whether (x, z) is on one of the paths.
static func covers(x: float, z: float) -> bool:
	return current != null and current.path_at(x, z) >= 0


## The path under (x, z), or -1.
func path_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	for s: Array in _grid.get(Vector2i(floori(x / GRID), floori(z / GRID)), []):
		if Geometry2D.get_closest_point_to_segment(p, s[1], s[2]).distance_to(p) <= s[3]:
			return s[0]
	return -1


func add_path(path: Dictionary) -> int:
	return insert_path(paths.size(), path)


func insert_path(i: int, path: Dictionary) -> int:
	paths.insert(i, path)
	_changed(_bounds(path))
	return i


func remove_path(i: int) -> Dictionary:
	var path: Dictionary = paths[i]
	paths.remove_at(i)
	_changed(_bounds(path))
	return path


func _changed(area: Rect2) -> void:
	_build_all()
	_save()
	var grass := get_parent().get_node_or_null("Grass")
	if grass and grass.has_method("refresh"):
		grass.refresh(area)


func _on_ground_changed(area: Rect2) -> void:
	for i in paths.size():
		if _bounds(paths[i]).intersects(area):
			_build(i)


func _save() -> void:
	if not saving or data_file.is_empty():
		return
	var f := FileAccess.open(data_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(paths))


func _bounds(path: Dictionary) -> Rect2:
	var pts: Array = path.points
	var r := Rect2(Vector2(pts[0][0], pts[0][1]), Vector2.ZERO)
	for p: Array in pts:
		r = r.expand(Vector2(p[0], p[1]))
	return r.grow(path.width * 0.5 + 1.0)


# ----------------------------------------------------------------------------
# Building the strips
# ----------------------------------------------------------------------------
func _build_all() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes = []
	_grid = {}
	for i in paths.size():
		_nodes.append(null)
		_build(i)


func _build(i: int) -> void:
	if _nodes[i] and is_instance_valid(_nodes[i]):
		_nodes[i].queue_free()
	var path: Dictionary = paths[i]
	var kind: Dictionary = TYPES.get(path.type, TYPES.sidewalk)
	var pts := _resample(path.points)
	if pts.size() < 2:
		_nodes[i] = null
		return
	var half: float = path.width * 0.5
	for k in range(paths[i].points.size() - 1):
		var a := Vector2(path.points[k][0], path.points[k][1])
		var b := Vector2(path.points[k + 1][0], path.points[k + 1][1])
		_index(i, a, b, half)
	# left and right edge of each cross section, mitred at the bends
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for k in pts.size():
		var t_in := (pts[k] - pts[maxi(k - 1, 0)]).normalized()
		var t_out := (pts[mini(k + 1, pts.size() - 1)] - pts[k]).normalized()
		var t := (t_in + t_out).normalized() if (t_in + t_out).length() > 0.01 else t_out
		var n := Vector2(-t.y, t.x)
		var miter := clampf(1.0 / maxf(n.dot(Vector2(-t_out.y, t_out.x)), 0.3), 1.0, 2.5)
		lefts.append(pts[k] + n * half * miter)
		rights.append(pts[k] - n * half * miter)
	var top: float = kind.top
	var across := maxi(1, ceili(path.width / STEP))   # the strip is split across too, so it never
	var st := SurfaceTool.new()                       # cuts under the top of a bump
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pts.size() - 1:
		for c in across:
			var u0 := float(c) / across
			var u1 := float(c + 1) / across
			var l0 := _at(lefts[k].lerp(rights[k], u0), top)
			var r0 := _at(lefts[k].lerp(rights[k], u1), top)
			var l1 := _at(lefts[k + 1].lerp(rights[k + 1], u0), top)
			var r1 := _at(lefts[k + 1].lerp(rights[k + 1], u1), top)
			_quad(st, [l0, l1, r1, r0], Vector3.UP)
	var mesh := st.commit()
	mesh.surface_set_material(0, _material(kind.top_material))
	if not (kind.side_material as String).is_empty():
		var sides := SurfaceTool.new()
		sides.begin(Mesh.PRIMITIVE_TRIANGLES)
		for edge: PackedVector2Array in [lefts, rights]:
			for k in pts.size() - 1:
				var a := _at(edge[k], top)
				var b := _at(edge[k + 1], top)
				var out := Vector3(edge[k].x - pts[k].x, 0, edge[k].y - pts[k].y).normalized()
				_quad(sides, [a, b, b - Vector3(0, top + 0.06, 0), a - Vector3(0, top + 0.06, 0)], out)
		for k: int in [0, pts.size() - 1]:      # the two ends
			var a := _at(lefts[k], top)
			var b := _at(rights[k], top)
			var out := Vector3(pts[k].x - pts[1 if k == 0 else k - 1].x, 0,
					pts[k].y - pts[1 if k == 0 else k - 1].y).normalized()
			_quad(sides, [a, b, b - Vector3(0, top + 0.06, 0), a - Vector3(0, top + 0.06, 0)], out)
		sides.commit(mesh)
		mesh.surface_set_material(1, _material(kind.side_material))
	var mi := MeshInstance3D.new()
	mi.name = "Path%d" % i
	mi.mesh = mesh
	if kind.solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	add_child(mi)
	_nodes[i] = mi


func _at(p: Vector2, top: float) -> Vector3:
	return Vector3(p.x, Terrain.height_at(p.x, p.y) + top, p.y)


## Two triangles facing `facing` (Godot draws clockwise faces as the front).
func _quad(st: SurfaceTool, q: Array, facing: Vector3) -> void:
	for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		if (b - a).cross(c - a).dot(facing) > 0.0:
			var swap := b
			b = c
			c = swap
		var n := facing if facing != Vector3.UP else -(b - a).cross(c - a).normalized()
		for v: Vector3 in [a, b, c]:
			st.set_normal(n)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)


func _resample(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points.size():
		var p := Vector2(points[k][0], points[k][1])
		if k > 0:
			var q := out[out.size() - 1]
			var n := ceili(q.distance_to(p) / STEP)
			for s in range(1, n):
				out.append(q.lerp(p, float(s) / n))
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.05:
			out.append(p)
	return out


func _index(i: int, a: Vector2, b: Vector2, half: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(half, half)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(half, half)
	for cx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
		for cz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append([i, a, b, half])


func _material(material_name: String) -> Material:
	if not _materials.has(material_name):
		var src := StandardMaterial3D.new()
		src.resource_name = material_name
		_materials[material_name] = WorldStyle.shared().material_for(src)
	return _materials[material_name]
