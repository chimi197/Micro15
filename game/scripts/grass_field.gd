## Scatters 3D grass clumps and little flowers over the lawn, using a mask
## image (white = lawn). Grass is built in square chunks around the active
## camera as it moves and freed again behind it, so a whole neighbourhood
## costs no more than the patch you can see.
##
## Grass painted or erased with the admin tool's grass brush is kept as a
## list of strokes in paint_file ([[x, z, radius, add], ...]) and drawn
## over the mask when the level loads.
class_name GrassField
extends Node3D

@export var mask: Texture2D
@export var size_m := 350.0              ## metres covered by the square mask, centred on the origin
@export var chunk_m := 16.0
@export var clumps_per_m2 := 6.0
@export var flowers_per_m2 := 0.12
@export var view_distance := 75.0
@export var max_radius := 0.0            ## no grass outside this circle around the origin (0 = no limit)
@export var chunks_per_frame := 3        ## build budget while walking; a camera jump builds all at once
@export_file("*.json") var paint_file := ""   ## grass brush strokes (admin tool)

var _material: ShaderMaterial
var _img: Image
var _clump: Mesh
var _flower: Mesh
var _chunks := {}                        # Vector2i -> Array of MultiMeshInstance3D
var _last := Vector2(INF, INF)
var _strokes: Array = []                 # [x, z, radius, add]


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/grass.gdshader")
	_load_mask()
	if not paint_file.is_empty() and FileAccess.file_exists(paint_file):
		_strokes = JSON.parse_string(FileAccess.get_file_as_string(paint_file))
		for s: Array in _strokes:
			_stamp(s[0], s[1], s[2], s[3])
	_clump = _make_clump_mesh()
	_flower = _make_flower_mesh()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	var jumped := p.distance_to(_last) > chunk_m * 4.0
	_last = p
	var reach := view_distance + chunk_m
	var wanted := []
	for cx in range(floori((p.x - reach) / chunk_m), floori((p.x + reach) / chunk_m) + 1):
		for cz in range(floori((p.y - reach) / chunk_m), floori((p.y + reach) / chunk_m) + 1):
			var key := Vector2i(cx, cz)
			if _chunks.has(key):
				continue
			var d := _centre(key).distance_to(p)
			if d <= reach:
				wanted.append([d, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	var budget := wanted.size() if jumped else mini(chunks_per_frame, wanted.size())
	for i in budget:
		_build(wanted[i][1])
	for key in _chunks.keys():
		if _centre(key).distance_to(p) > reach + chunk_m * 2.0:
			for n: Node in _chunks[key]:
				n.queue_free()
			_chunks.erase(key)


func _centre(key: Vector2i) -> Vector2:
	return Vector2((key.x + 0.5) * chunk_m, (key.y + 0.5) * chunk_m)


func _build(key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var x0 := key.x * chunk_m
	var z0 := key.y * chunk_m
	var nodes := []
	for spec in [[_clump, clumps_per_m2, Vector2(0.75, 1.35)], [_flower, flowers_per_m2, Vector2(0.8, 1.2)]]:
		var mmi := _make_chunk(spec[0], x0, z0, spec[1], spec[2], rng)
		if mmi:
			nodes.append(mmi)
	_chunks[key] = nodes


## Mask pixel under (x, z). The mask is grey (white = lawn); grass painted
## by hand is magenta, so it also grows outside max_radius.
func _pixel(x: float, z: float) -> Vector2i:
	return Vector2i(int((x + size_m / 2.0) / size_m * _img.get_width()),
			int((z + size_m / 2.0) / size_m * _img.get_height()))


func _lawn(x: float, z: float) -> bool:
	var px := _pixel(x, z)
	if px.x < 0 or px.y < 0 or px.x >= _img.get_width() or px.y >= _img.get_height():
		return false
	var c := _img.get_pixelv(px)
	if c.b > 0.5 and c.g < 0.5:
		return true
	if max_radius > 0.0 and Vector2(x, z).length() > max_radius:
		return false
	return c.r > 0.5


func _load_mask() -> void:
	_img = mask.get_image().duplicate()
	if _img.is_compressed():
		_img.decompress()
	_img.convert(Image.FORMAT_RGB8)


# ----------------------------------------------------------------------------
# Grass brush (admin tool)
# ----------------------------------------------------------------------------
## Grows (add) or clears grass in a circle and saves the stroke.
func paint(x: float, z: float, radius: float, add: bool) -> void:
	var s := [snappedf(x, 0.01), snappedf(z, 0.01), snappedf(radius, 0.01), add]
	_strokes.append(s)
	_stamp(s[0], s[1], s[2], add)
	_rebuild(Rect2(x - radius, z - radius, radius * 2.0, radius * 2.0))
	_save_strokes()


func stroke_count() -> int:
	return _strokes.size()


## Drops the strokes after the first n (undo) and redraws the grass.
func truncate_strokes(n: int) -> void:
	if n >= _strokes.size():
		return
	_strokes.resize(n)
	_load_mask()
	for s: Array in _strokes:
		_stamp(s[0], s[1], s[2], s[3])
	_rebuild(Rect2())
	_save_strokes()


func _stamp(x: float, z: float, radius: float, add: bool) -> void:
	var c := _pixel(x, z)
	var r := int(ceil(radius / size_m * _img.get_width()))
	var colour := Color(1, 0, 1) if add else Color(0, 0, 0)
	for py in range(maxi(c.y - r, 0), mini(c.y + r + 1, _img.get_height())):
		for px in range(maxi(c.x - r, 0), mini(c.x + r + 1, _img.get_width())):
			if Vector2(px - c.x, py - c.y).length() <= r:
				_img.set_pixel(px, py, colour)


## Frees the chunks touching area (all of them for an empty Rect2) so they
## are built again with the new mask.
func _rebuild(area: Rect2) -> void:
	for key: Vector2i in _chunks.keys():
		var r := Rect2(key.x * chunk_m, key.y * chunk_m, chunk_m, chunk_m)
		if area.has_area() and not r.intersects(area):
			continue
		for n: Node in _chunks[key]:
			n.queue_free()
		_chunks.erase(key)
	_last = Vector2(INF, INF)        # rebuild them all at once, next frame


func _save_strokes() -> void:
	if paint_file.is_empty():
		return
	var f := FileAccess.open(paint_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_strokes))


func _make_chunk(mesh: Mesh, x0: float, z0: float, density: float, scale_range: Vector2,
		rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var transforms: Array[Transform3D] = []
	var count := int(chunk_m * chunk_m * density)
	for i in count:
		var x := x0 + rng.randf() * chunk_m
		var z := z0 + rng.randf() * chunk_m
		if not _lawn(x, z):
			continue
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = view_distance
	mmi.visibility_range_end_margin = 12.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return mmi


## A clump of 7 curved, tapered blades. UV.y runs 0 (root) to 1 (tip).
func _make_clump_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var root := Color("#57823a")
	var tip := Color("#98b862")
	for b in 7:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.09)
		var lean_dir := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0, sin(a + rng.randf_range(-0.6, 0.6)))
		var height := rng.randf_range(0.14, 0.3)
		var width := rng.randf_range(0.035, 0.05)
		var side := Vector3(-lean_dir.z, 0, lean_dir.x) * width
		var segs := 3
		var prev_l := base - side
		var prev_r := base + side
		for s in range(1, segs + 1):
			var t := float(s) / segs
			var p := base + Vector3(0, height * t, 0) + lean_dir * (t * t) * height * 0.45
			var w := (1.0 - t) * 0.9 + 0.1 if s < segs else 0.0
			var l := p - side * w
			var r := p + side * w
			var t0 := float(s - 1) / segs
			for v in [[prev_l, t0], [prev_r, t0], [r, t], [prev_l, t0], [r, t], [l, t]]:
				st.set_color(root.lerp(tip, v[1]))
				st.set_uv(Vector2(0, v[1]))
				st.add_vertex(v[0])
			prev_l = l
			prev_r = r
	return st.commit()


## Tiny daisy / buttercup: a stem and a flat six-petal head.
func _make_flower_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color("#5a8a3c")
	var h := 0.32
	for v in [[Vector3(-0.012, 0, 0), 0.0], [Vector3(0.012, 0, 0), 0.0], [Vector3(0, h, 0), 1.0]]:
		st.set_color(stem)
		st.set_uv(Vector2(0, v[1]))
		st.add_vertex(v[0])
	var centre := Vector3(0, h, 0)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var r := 0.07
		for v in [centre, centre + Vector3(cos(a0), 0.15, sin(a0)) * r, centre + Vector3(cos(a1), 0.15, sin(a1)) * r]:
			st.set_color(Color("#fdfcf5") if v != centre else Color("#f6c945"))
			st.set_uv(Vector2(0, 1))
			st.add_vertex(v)
	return st.commit()
