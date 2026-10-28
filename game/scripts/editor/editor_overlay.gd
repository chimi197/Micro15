## What the map editor draws in the 3D world: boxes around the selected and
## the hovered things, the brush ring, the coordinate grid with its labels
## and the pins. None of it casts shadows or is saved with the level.
class_name EditorOverlay
extends Node3D

const GRID_LABEL_STEP := 50.0
const GRID_LABEL_REACH := 160.0

var _boxes: MeshInstance3D
var _box_mesh := ImmediateMesh.new()
var _ring: MeshInstance3D
var _grid: MeshInstance3D
var _labels: Node3D
var _label_centre := Vector2.INF
var _pins: Node3D


func _ready() -> void:
	_boxes = MeshInstance3D.new()
	_boxes.mesh = _box_mesh
	_boxes.material_override = _line_material()
	_boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boxes)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 64
	_ring.mesh = torus
	_ring.material_override = _line_material()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	_grid = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_grid.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/editor_grid.gdshader")
	_grid.material_override = m
	_grid.extra_cull_margin = 16384.0
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.visible = false
	add_child(_grid)
	_labels = Node3D.new()
	_labels.visible = false
	add_child(_labels)
	_pins = Node3D.new()
	add_child(_pins)


func _line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 10
	return m


## boxes: [[AABB, Transform3D, Color], ...]
func show_boxes(boxes: Array) -> void:
	_box_mesh.clear_surfaces()
	if boxes.is_empty():
		return
	_box_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for b: Array in boxes:
		var box: AABB = b[0]
		var t: Transform3D = b[1]
		_box_mesh.surface_set_color(b[2])
		for e in 12:
			var ends := _edge(e)
			_box_mesh.surface_add_vertex(t * (box.position + box.size * ends[0]))
			_box_mesh.surface_add_vertex(t * (box.position + box.size * ends[1]))
	_box_mesh.surface_end()


func _edge(e: int) -> Array:
	var corners := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
			Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	var pairs := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	return [corners[pairs[e][0]], corners[pairs[e][1]]]


func show_ring(at: Vector3, radius: float, colour: Color) -> void:
	_ring.visible = at != Vector3.INF
	if _ring.visible:
		_ring.global_transform = Transform3D(Basis.from_scale(Vector3(radius, 0.3, radius)), at + Vector3.UP * 0.05)
		(_ring.material_override as StandardMaterial3D).albedo_color = colour


func set_grid(on: bool) -> void:
	_grid.visible = on
	_labels.visible = on
	_label_centre = Vector2.INF


func grid_on() -> bool:
	return _grid.visible


## Keeps "x, z" labels on the 50 m crossings around the camera.
func update_labels(camera: Camera3D) -> void:
	if not _labels.visible or camera == null:
		return
	var f := -camera.global_basis.z
	var look := camera.global_position + Vector3(f.x, 0, f.z).normalized() * 40.0
	var centre := Vector2(snappedf(look.x, GRID_LABEL_STEP), snappedf(look.z, GRID_LABEL_STEP))
	if centre == _label_centre:
		return
	_label_centre = centre
	for c in _labels.get_children():
		c.queue_free()
	var n := int(GRID_LABEL_REACH / GRID_LABEL_STEP)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var x := centre.x + i * GRID_LABEL_STEP
			var z := centre.y + j * GRID_LABEL_STEP
			var major := fmod(absf(x), 100.0) < 0.1 and fmod(absf(z), 100.0) < 0.1
			var l := Label3D.new()
			l.text = "%d, %d" % [x, z]
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.fixed_size = true
			l.pixel_size = 0.0011 if major else 0.0008
			l.font_size = 26
			l.outline_size = 8
			l.modulate = EditorTheme.YELLOW if major else Color(1, 1, 1, 0.85)
			l.outline_modulate = Color(0, 0, 0, 0.7)
			l.position = Vector3(x, 0.6, z)
			l.no_depth_test = false
			_labels.add_child(l)


## pins: [{id, x, y, z, note}, ...]
func show_pins(pins: Array) -> void:
	for c in _pins.get_children():
		c.queue_free()
	for pin: Dictionary in pins:
		var marker := Node3D.new()
		marker.position = Vector3(pin.x, pin.y, pin.z)
		var stick := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 2.2
		stick.mesh = cyl
		stick.position.y = 1.1
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = EditorTheme.DANGER
		stick.material_override = m
		stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(stick)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		head.mesh = sphere
		head.position.y = 2.3
		head.material_override = m
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(head)
		var l := Label3D.new()
		l.text = "#%d %s" % [pin.id, pin.note] if not String(pin.note).is_empty() else "#%d" % pin.id
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.001
		l.font_size = 30
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.75)
		l.position.y = 2.8
		l.no_depth_test = true
		marker.add_child(l)
		_pins.add_child(marker)


func set_pins_visible(on: bool) -> void:
	_pins.visible = on
