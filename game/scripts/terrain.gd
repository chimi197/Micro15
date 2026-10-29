## The shape of the ground inside the playable area, changed with the map
## editor's Terrain tool: hills, hollows, slopes and flat terraces.
##
## Heights live on a grid of points every CELL metres (x = CELL * i,
## z = CELL * j); each grid square is split along its x - z diagonal into
## two triangles and the height is linear on each, which is exactly how
## blender/build_map.py dices the ground chunks (Ground's g_<i>_<j> meshes),
## so roads, sidewalks and lawns all bend together without poking through
## each other. The grid is kept flat under the buildings (footprints.json,
## plus a margin) and along the edge of the playable area, so buildings
## and the streets beyond the edge never float or sink.
##
## The map's trees, lamps and benches, the 3D grass, the paths drawn with
## the map editor and the things you place all follow the ground. Edits are
## saved in levels/micro15/terrain.json: {"cell": 2, "heights": {"i,j": h}}
## with only the points that are not flat.
class_name Terrain
extends Node3D

signal changed(area: Rect2)

const CELL := 2.0
const CHUNK := 32.0
const BUILDING_MARGIN := 1.5           ## metres of flat ground kept round a building
const EDGE_MARGIN := 4.0               ## and inside the edge of the playable area
const MAX_HEIGHT := 30.0

static var current: Terrain

@export var ground: NodePath = ^"../Ground"
@export var props: NodePath = ^"../Props"
@export var grass: NodePath = ^"../Grass"
@export_file("*.json") var data_file := "res://levels/micro15/terrain.json"
@export_file("*.json") var footprints_file := "res://levels/micro15/footprints.json"
@export_file("*.json") var area_file := "res://levels/micro15/play_area.json"

var saving := true                     # (the self-test turns saving off)
var _h := {}                           # Vector2i: height of a grid point (not 0)
var _locked := {}                      # Vector2i: true for points that stay flat
var _area := PackedVector2Array()
var _chunks := {}                      # Vector2i: MeshInstance3D (g_<i>_<j>)
var _base := {}                        # MeshInstance3D: [surface arrays as built, flat]
var _dirty := {}                       # chunk keys waiting for new meshes
var _dirty_area := Rect2()
var _collision_dirty := {}             # chunk keys waiting for new collision


func _ready() -> void:
	current = self
	var g := get_node_or_null(grass)
	if g and g.has_method("refresh"):
		changed.connect(g.refresh)
	_area = Boundary.load_polygon(area_file)
	_find_chunks()
	_lock_flat_points()
	_load()
	if not _h.is_empty():
		_mark(_edited_area())
		var area := _dirty_area
		_flush(true)
		changed.emit(area)


func _exit_tree() -> void:
	if current == self:
		current = null


## Height of the ground shape at (x, z) (0 where it was never changed).
static func height_at(x: float, z: float) -> float:
	return current.height(x, z) if current else 0.0


func height(x: float, z: float) -> float:
	return height_in(_h, x, z)


## Height at (x, z) of a set of grid heights (a snapshot).
static func height_in(heights: Dictionary, x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var fx := x / CELL
	var fz := z / CELL
	var i := floori(fx)
	var j := floori(fz)
	fx -= i
	fz -= j
	var h00: float = heights.get(Vector2i(i, j), 0.0)
	var h11: float = heights.get(Vector2i(i + 1, j + 1), 0.0)
	if fx >= fz:                       # the triangle (0,0) (1,0) (1,1)
		var h10: float = heights.get(Vector2i(i + 1, j), 0.0)
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	var h01: float = heights.get(Vector2i(i, j + 1), 0.0)    # the triangle (0,0) (0,1) (1,1)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## The ground's slope normal at (x, z).
func normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height(x + e, z) - height(x - e, z)
	var dz := height(x, z + e) - height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _grid_h(i: int, j: int) -> float:
	return _h.get(Vector2i(i, j), 0.0)


## Whether (x, z) is somewhere the tool can shape (inside the playable area,
## away from its edge and from buildings).
func editable(x: float, z: float) -> bool:
	var k := Vector2i(roundi(x / CELL), roundi(z / CELL))
	return _inside(Vector2(k.x, k.y) * CELL, EDGE_MARGIN) and not _locked.has(k)


# ----------------------------------------------------------------------------
# Brush (map editor)
# ----------------------------------------------------------------------------
## One dab of the brush at (x, z): mode is "raise", "lower", "flatten" (to
## target), "smooth" or "reset"; strength is metres per second at the
## middle for raise / lower; dt the time the dab stands for.
func brush(mode: String, x: float, z: float, radius: float, strength: float, dt: float,
		target := 0.0) -> void:
	var i0 := floori((x - radius) / CELL)
	var i1 := ceili((x + radius) / CELL)
	var j0 := floori((z - radius) / CELL)
	var j1 := ceili((z + radius) / CELL)
	var new := {}
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var k := Vector2i(i, j)
			var p := Vector2(i, j) * CELL
			var d := p.distance_to(Vector2(x, z)) / radius
			if d >= 1.0 or _locked.has(k) or not _inside(p, EDGE_MARGIN):
				continue
			var w := 1.0 - smoothstep(0.0, 1.0, d)
			var h := _grid_h(i, j)
			match mode:
				"raise":
					h += strength * dt * w
				"lower":
					h -= strength * dt * w
				"flatten":
					h = lerpf(h, target, minf(1.0, 6.0 * dt * w))
				"smooth":
					var avg := (_grid_h(i - 1, j) + _grid_h(i + 1, j) + _grid_h(i, j - 1) + _grid_h(i, j + 1)) * 0.25
					h = lerpf(h, avg, minf(1.0, 8.0 * dt * w))
				"reset":
					h = lerpf(h, 0.0, minf(1.0, 6.0 * dt * w))
			new[k] = clampf(h, -MAX_HEIGHT, MAX_HEIGHT)
	for k: Vector2i in new:
		_put(k, new[k])
	_mark(Rect2(x - radius - CELL, z - radius - CELL, (radius + CELL) * 2.0, (radius + CELL) * 2.0))


func _put(k: Vector2i, h: float) -> void:
	if absf(h) < 0.002:
		_h.erase(k)
	else:
		_h[k] = h


## Every changed grid point, to undo a stroke: {Vector2i: height}.
func snapshot(area := Rect2(-1e6, -1e6, 2e6, 2e6)) -> Dictionary:
	var out := {}
	for k: Vector2i in _h:
		if area.has_point(Vector2(k.x, k.y) * CELL):
			out[k] = _h[k]
	return out


## Puts back the heights inside area as they were in a snapshot of it.
func restore(area: Rect2, snap: Dictionary) -> void:
	for k: Vector2i in _h.keys():
		if area.has_point(Vector2(k.x, k.y) * CELL):
			_h.erase(k)
	for k: Vector2i in snap:
		_h[k] = snap[k]
	_mark(area.grow(CELL))
	finish_stroke()


## Updates the meshes (call while brushing; collision waits for the end).
func update() -> void:
	_flush(false)


## Updates meshes and collision, tells the grass, props and paths, saves.
func finish_stroke() -> void:
	var area := _dirty_area
	_flush(true)
	if area.has_area():
		changed.emit(area)
	_save()


func _mark(area: Rect2) -> void:
	_dirty_area = area if not _dirty_area.has_area() else _dirty_area.merge(area)
	for ci in range(floori(area.position.x / CHUNK), floori(area.end.x / CHUNK) + 1):
		for cj in range(floori(area.position.y / CHUNK), floori(area.end.y / CHUNK) + 1):
			var key := Vector2i(ci, cj)
			if _chunks.has(key):
				_dirty[key] = true
				_collision_dirty[key] = true


func _flush(with_collision: bool) -> void:
	for key: Vector2i in _dirty:
		_rebuild_chunk(_chunks[key])
	_dirty.clear()
	if with_collision:
		for key: Vector2i in _collision_dirty:
			_rebuild_collision(_chunks[key])
		_collision_dirty.clear()
		var area := _dirty_area
		_dirty_area = Rect2()
		var p := get_node_or_null(props) as Scatter
		if p and area.has_area():
			p.follow_ground(area)


# ----------------------------------------------------------------------------
# Ground meshes
# ----------------------------------------------------------------------------
func _find_chunks() -> void:
	var g := get_node_or_null(ground)
	if g == null:
		return
	for mi: MeshInstance3D in g.find_children("g_*", "MeshInstance3D", true, false):
		var parts := String(mi.name).split("_")
		if parts.size() == 3:
			_chunks[Vector2i(int(parts[1]), int(parts[2]))] = mi


func _rebuild_chunk(mi: MeshInstance3D) -> void:
	if not _base.has(mi):
		var surfaces := []
		for s in mi.mesh.get_surface_count():
			surfaces.append([mi.mesh.surface_get_arrays(s), mi.mesh.surface_get_material(s)])
		_base[mi] = surfaces
	var to_world := mi.global_transform
	var to_local := to_world.affine_inverse()
	var mesh := ArrayMesh.new()
	for surface: Array in _base[mi]:
		var arrays: Array = (surface[0] as Array).duplicate()
		var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var normals: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() \
				if arrays[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		for v in verts.size():
			var w := to_world * verts[v]
			var h := height(w.x, w.z)
			if h == 0.0 and _h.is_empty():
				continue
			verts[v] = to_local * Vector3(w.x, w.y + h, w.z)
			if not normals.is_empty() and normals[v].y > 0.7:
				normals[v] = to_local.basis * normal(w.x, w.z)
		arrays[Mesh.ARRAY_VERTEX] = verts
		if not normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface[1])
	mesh.resource_name = mi.mesh.resource_name
	mi.mesh = mesh


func _rebuild_collision(mi: MeshInstance3D) -> void:
	for body in mi.get_children():
		if body is StaticBody3D:
			for shape in body.get_children():
				if shape is CollisionShape3D:
					shape.shape = mi.mesh.create_trimesh_shape()


# ----------------------------------------------------------------------------
# Where the ground stays flat
# ----------------------------------------------------------------------------
func _inside(p: Vector2, margin: float) -> bool:
	if _area.size() < 3:
		return false
	if not Geometry2D.is_point_in_polygon(p, _area):
		return false
	for i in _area.size():
		var a := _area[i]
		var b := _area[(i + 1) % _area.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
			return false
	return true


func _lock_flat_points() -> void:
	_locked = {}
	if not FileAccess.file_exists(footprints_file):
		return
	var feet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(footprints_file))
	for id: String in feet:
		var ring := PackedVector2Array()
		for p: Array in feet[id]:
			ring.append(Vector2(p[0], p[1]))
		var box := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			box = box.expand(p)
		box = box.grow(BUILDING_MARGIN + CELL)
		if _area.size() >= 3 and not _touches_area(box):
			continue
		var grown := Geometry2D.offset_polygon(ring, BUILDING_MARGIN)
		for i in range(floori(box.position.x / CELL), ceili(box.end.x / CELL) + 1):
			for j in range(floori(box.position.y / CELL), ceili(box.end.y / CELL) + 1):
				var p := Vector2(i, j) * CELL
				for poly: PackedVector2Array in grown:
					if Geometry2D.is_point_in_polygon(p, poly):
						_locked[Vector2i(i, j)] = true
						break


func _touches_area(box: Rect2) -> bool:
	var a := Rect2(_area[0], Vector2.ZERO)
	for p in _area:
		a = a.expand(p)
	return a.intersects(box)


# ----------------------------------------------------------------------------
# File
# ----------------------------------------------------------------------------
func _load() -> void:
	_h = {}
	if data_file.is_empty() or not FileAccess.file_exists(data_file):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_file))
	if not d is Dictionary:
		return
	for key: String in (d as Dictionary).get("heights", {}):
		var ij := key.split(",")
		var k := Vector2i(int(ij[0]), int(ij[1]))
		if not _locked.has(k):
			_h[k] = float(d.heights[key])


func _save() -> void:
	if not saving or data_file.is_empty():
		return
	var heights := {}
	for k: Vector2i in _h:
		heights["%d,%d" % [k.x, k.y]] = snappedf(_h[k], 0.001)
	var f := FileAccess.open(data_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cell": CELL, "heights": heights}))


func _edited_area() -> Rect2:
	var first := true
	var r := Rect2()
	for k: Vector2i in _h:
		var p := Vector2(k.x, k.y) * CELL
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r.grow(CELL * 2.0)


func edited_points() -> int:
	return _h.size()
