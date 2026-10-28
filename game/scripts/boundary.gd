## The edge of the playable area: a continuous row of dark, shadowed blocks
## of flats just outside it, which the player cannot pass. The area is the
## polygon in area_file (levels/micro15/play_area.json, made by
## tools/make_play_area.py from the corner pins); the map itself is cut to
## it by blender/build_map.py. Runs in the editor too.
@tool
class_name Boundary
extends Node3D

const FLOOR := 2.8

@export_file("*.json") var area_file := "res://levels/micro15/play_area.json":
	set(v):
		area_file = v
		if is_inside_tree():
			_build()
@export var depth := 14.0                  ## how deep each block is, metres
@export var width_range := Vector2(22, 46) ## block lengths along the edge
@export var floors := PackedInt32Array([4, 4, 4, 5, 8, 10, 10])   ## picked at random per block
@export var wall_height := 80.0            ## collision height, so nothing jumps over
@export var seed := 15

var polygon: PackedVector2Array = []       # x, z


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	polygon = load_polygon(area_file)
	if polygon.size() < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var centre := Vector2.ZERO
	for p in polygon:
		centre += p
	centre /= polygon.size()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var u := (b - a).normalized()
		var n := Vector2(u.y, -u.x)
		if n.dot(centre - a) > 0.0:
			n = -n
		# run past both ends by a block depth so the corners close
		var start := -depth
		var end := a.distance_to(b) + depth
		var s := start
		while s < end - 1.0:
			var w := minf(rng.randf_range(width_range.x, width_range.y), end - s)
			if end - (s + w) < width_range.x * 0.5:
				w = end - s                       # no sliver at the end
			var h := floors[rng.randi() % floors.size()] * FLOOR + 1.0
			var mid := a + u * (s + w * 0.5) + n * (depth * 0.5 - 0.5)     # covers the cut edge of the ground
			var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.18))
			_add_block(st, mid, u, n, w, depth, h, tint)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(w, wall_height, depth)
			shape.shape = box
			shape.transform = Transform3D(Basis(Vector3(u.x, 0, u.y), Vector3.UP, Vector3(n.x, 0, n.y)),
					Vector3(mid.x, wall_height * 0.5, mid.y))
			body.add_child(shape)
			s += w
	var mi := MeshInstance3D.new()
	mi.name = "Blocks"
	mi.mesh = st.commit()
	mi.material_override = preload("res://style/boundary.tres")
	add_child(mi)


## A box without a bottom: four walls and a roof. UV is in metres (along the
## wall, up), for the window grid in shaders/boundary.gdshader; the colour
## tints the block (alpha 0 on the roof).
func _add_block(st: SurfaceTool, mid: Vector2, u: Vector2, n: Vector2, w: float, d: float, h: float,
		tint: Color) -> void:
	var U := Vector3(u.x, 0, u.y) * (w * 0.5)
	var N := Vector3(n.x, 0, n.y) * (d * 0.5)
	var c := Vector3(mid.x, 0, mid.y)
	var corners := [c - U - N, c + U - N, c + U + N, c - U + N]   # inner side first
	var lengths := [w, d, w, d]
	for k in 4:
		var p0: Vector3 = corners[k]
		var p1: Vector3 = corners[(k + 1) % 4]
		var L: float = lengths[k]
		_quad(st, [p0, p1, p1 + Vector3.UP * h, p0 + Vector3.UP * h],
				[Vector2(0, 0), Vector2(L, 0), Vector2(L, h), Vector2(0, h)], tint)
	var top: Array = []
	for p: Vector3 in corners:
		top.append(p + Vector3.UP * h)
	var roof := Color(tint, 0.0)                  # alpha 0 marks the roof for the shader
	_quad(st, [top[3], top[2], top[1], top[0]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], roof)


func _quad(st: SurfaceTool, p: Array, uv: Array, tint: Color) -> void:
	var normal: Vector3 = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_color(tint)
		st.set_uv(uv[k])
		st.add_vertex(p[k])


## The play area polygon (x, z) from a play_area.json, or [] without one.
static func load_polygon(path: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		for p: Array in d.get("polygon", []):
			out.append(Vector2(p[0], p[1]))
	return out


## Whether the point (x, z) is inside the play area.
func contains(p: Vector2) -> bool:
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(p, polygon)
