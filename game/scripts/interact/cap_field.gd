## Bottle caps lying about: the pocket money of the game (shops take them).
## Every kid in a block yard collected them. They lie where kids drop
## things: by benches, playgrounds, kiosks, block entrances and along the
## paths, each with its own id (from where it lies) so a found cap stays
## found (Save).
##
## Drawn with one MultiMesh; a cap glints now and then so it can be spotted
## from a few metres. Walking over one picks it up.
class_name CapField
extends Node3D

const COLOURS := [Color("#c8312b"), Color("#2f6db5"), Color("#e2b33a"), Color("#3c8f45"), Color("#e9e4d8"),
		Color("#7a2a6b"), Color("#222222")]
const PICK_RADIUS := 0.55

signal found(id: String, total: int)

var caps := []                            # [id, Vector3, instance]
var _mm: MultiMeshInstance3D
var _player: Node3D
var _check := 0.0


## anchors: points near which caps may lie; count: how many to place.
func scatter(anchors: Array[Vector3], count: int, play_area: Callable, seed_value := 15) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var space := get_world_3d().direct_space_state
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < count and tries < count * 12 and not anchors.is_empty():
		tries += 1
		var a: Vector3 = anchors[rng.randi() % anchors.size()]
		var ang := rng.randf() * TAU
		var r := rng.randf_range(0.6, 2.2)
		var p := a + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not play_area.call(Vector2(p.x, p.z)):
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.85:
			continue
		var at: Vector3 = hit.position + Vector3.UP * 0.004
		var near := false
		for s in spots:
			if s.distance_to(at) < 6.0:
				near = true
				break
		if not near:
			spots.append(at)
	_build(spots, rng)


func _build(spots: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.018
	mesh.bottom_radius = 0.019
	mesh.height = 0.007
	mesh.radial_segments = 18
	mesh.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/cap.gdshader")
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var p := spots[i]
		var id := "cap_%d_%d" % [roundi(p.x * 2.0), roundi(p.z * 2.0)]
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
		var hidden := Save.has_found(id)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ZERO) if hidden else b, p))
		mm.set_instance_color(i, COLOURS[rng.randi() % COLOURS.size()])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
		if not hidden:
			caps.append([id, p, i])
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.visibility_range_end = 40.0
	add_child(_mm)


func total() -> int:
	return _mm.multimesh.instance_count if _mm else 0


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or caps.is_empty():
		return
	_check = 0.08
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var at := _player.global_position
	for i in range(caps.size() - 1, -1, -1):
		var c: Array = caps[i]
		var p: Vector3 = c[1]
		if absf(p.x - at.x) < PICK_RADIUS and absf(p.z - at.z) < PICK_RADIUS and absf(p.y - at.y) < 0.6:
			caps.remove_at(i)
			_mm.multimesh.set_instance_transform(c[2], Transform3D(Basis().scaled(Vector3.ZERO), p))
			Save.find_cap(c[0])
			found.emit(c[0], Save.caps())
			get_tree().call_group("sound", "play_at", "cap", p, 1.0)
			if _player.get("face"):
				_player.face.express("happy", 1.0)
