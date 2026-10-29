## The edge of the playable area and the town beyond it.
##
## The playable area is the polygon in area_file (levels/micro15/play_area.json,
## made by tools/make_play_area.py from the corner pins). The whole mapped
## neighbourhood is drawn, so the streets and blocks simply carry on past the
## edge; an invisible wall along the edge stops the player there. Beyond the
## mapped neighbourhood a ring of distant blocks of flats
## (shaders/boundary.gdshader) and the lawn fade into the sky's horizon
## colour, so the town seems to go on to the horizon. Runs in the editor too.
@tool
class_name Boundary
extends Node3D

const FLOOR := 2.8
## The mapped neighbourhood (blender/build_world.py extent, Godot x and z)
const MAPPED := Rect2(-620.0, -585.0, 1240.0, 1170.0)
const WALLS := ["#eadcb6", "#e9d18f", "#e4dfd2", "#adc5d3", "#c6bdd4", "#b6cfb4", "#e6bc9a", "#d49d85"]

@export_file("*.json") var area_file := "res://levels/micro15/play_area.json":
	set(v):
		area_file = v
		if is_inside_tree():
			_build()
@export var wall_height := 80.0            ## the invisible wall, so nothing jumps over
@export var far_reach := 1800.0            ## distant blocks go out this far from the middle
@export var far_spacing := 70.0
@export var seed := 15
@export var world_environment: NodePath = ^"../WorldEnvironment"
@export var outer_lawn: NodePath = ^"../OuterLawn"

var polygon: PackedVector2Array = []       # x, z
var _far_material: ShaderMaterial
var _lawn_material: ShaderMaterial


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	var colour := _horizon()
	if _far_material:
		_far_material.set_shader_parameter("haze_colour", colour)
	if _lawn_material:
		_lawn_material.set_shader_parameter("haze_colour", colour)


func _horizon() -> Color:
	var we := get_node_or_null(world_environment) as WorldEnvironment
	if we and we.environment and we.environment.sky and we.environment.sky.sky_material is ProceduralSkyMaterial:
		return (we.environment.sky.sky_material as ProceduralSkyMaterial).sky_horizon_color
	return Color(0.78, 0.86, 0.9)


func _build() -> void:
	for c in get_children():
		c.free()
	polygon = load_polygon(area_file)
	_build_walls()
	_build_far_blocks()
	var lawn := get_node_or_null(outer_lawn) as MeshInstance3D
	if lawn and lawn.get_surface_override_material(0) is ShaderMaterial:
		if Engine.is_editor_hint():
			return                               # (never save a changed lawn into the level)
		_lawn_material = lawn.get_surface_override_material(0).duplicate()
		_lawn_material.set_shader_parameter("haze_start", 500.0)
		_lawn_material.set_shader_parameter("haze_end", 1700.0)
		_lawn_material.set_shader_parameter("haze_max", 1.0)
		lawn.set_surface_override_material(0, _lawn_material)


## A tall invisible wall just outside every side of the playable area.
func _build_walls() -> void:
	if polygon.size() < 3:
		return
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
		var length := a.distance_to(b) + 8.0
		var mid := (a + b) * 0.5 + n * 1.0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, wall_height, 2.0)
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3(u.x, 0, u.y), Vector3.UP, Vector3(n.x, 0, n.y)),
				Vector3(mid.x, wall_height * 0.5 - 2.0, mid.y))
		body.add_child(shape)


## Blocks of flats scattered round the mapped neighbourhood, out to far_reach.
func _build_far_blocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var keep_out := MAPPED.grow(40.0)
	var n := 0
	var s := -far_reach
	while s <= far_reach:
		var t := -far_reach
		while t <= far_reach:
			var p := Vector2(s, t) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			var chance := rng.randf()
			t += far_spacing
			if p.length() > far_reach or keep_out.has_point(p) or chance > 0.62:
				continue
			var yaw := (PI * 0.5 if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.12, 0.12)
			var u := Vector2(cos(yaw), sin(yaw))
			var nrm := Vector2(-u.y, u.x)
			var tall := rng.randf() < 0.25
			var w := rng.randf_range(16.0, 24.0) if tall else rng.randf_range(30.0, 64.0)
			var d := rng.randf_range(12.0, 16.0) if tall else rng.randf_range(10.5, 13.0)
			var storeys: int = 10 if tall else [4, 4, 4, 8][rng.randi() % 4]
			var h := storeys * FLOOR + 1.0
			_add_block(st, p, u, nrm, w, d, h, Color(WALLS[rng.randi() % WALLS.size()]))
			n += 1
		s += far_spacing
	var mi := MeshInstance3D.new()
	mi.name = "FarBlocks"
	mi.mesh = st.commit()
	_far_material = ShaderMaterial.new()
	_far_material.shader = preload("res://shaders/boundary.gdshader")
	mi.material_override = _far_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 64.0
	add_child(mi)


## A box without a bottom: four walls and a roof. UV is in metres (along the
## wall, up); the colour is the wall colour (alpha 0 on the roof).
func _add_block(st: SurfaceTool, mid: Vector2, u: Vector2, n: Vector2, w: float, d: float, h: float,
		colour: Color) -> void:
	var U := Vector3(u.x, 0, u.y) * (w * 0.5)
	var N := Vector3(n.x, 0, n.y) * (d * 0.5)
	var c := Vector3(mid.x, 0, mid.y)
	var corners := [c - U - N, c + U - N, c + U + N, c - U + N]
	var lengths := [w, d, w, d]
	for k in 4:
		var p0: Vector3 = corners[k]
		var p1: Vector3 = corners[(k + 1) % 4]
		var L: float = lengths[k]
		var out := ((p0 + p1) * 0.5 - c).normalized()
		_quad(st, [p0, p1, p1 + Vector3.UP * h, p0 + Vector3.UP * h],
				[Vector2(0, 0), Vector2(L, 0), Vector2(L, h), Vector2(0, h)], colour, out)
	var top: Array = []
	for p: Vector3 in corners:
		top.append(p + Vector3.UP * h)
	_quad(st, top, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color(colour, 0.0), Vector3.UP)


## Two triangles facing `facing` (Godot draws clockwise faces as the front).
func _quad(st: SurfaceTool, p: Array, uv: Array, colour: Color, facing: Vector3) -> void:
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		if ((p[b] as Vector3) - p[a]).cross((p[c] as Vector3) - p[a]).dot(facing) > 0.0:
			var swap := b
			b = c
			c = swap
		for k: int in [a, b, c]:
			st.set_normal(facing)
			st.set_color(colour)
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
