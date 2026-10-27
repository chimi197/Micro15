## The whole Micro 15 neighbourhood (Satu Mare), built by
## blender/build_map.py from OpenStreetMap: every block of flats, house,
## school, church, shop and garage in full 3D, the street network, trees,
## lamps and benches, and 3D grass streamed around the camera.
##
## Building shells are plain meshes. Repeated details (windows, balconies,
## entrances, AC units, dishes, drainpipes...) and props are drawn with one
## MultiMesh per type and per 96 m cell, so far-away cells drop small
## details and the whole map stays light.
##
## Run normally to walk around. Run with `-- --shots` to save preview
## screenshots to ../docs/renders/ and quit, or with `-- --selftest` to
## drive the player through idle, walk, run and a jump and print what the
## animations did.
extends Node3D

const LEVEL := "res://levels/micro15/"
const CELL := 96.0
const BOUNDS := Vector2(640, 605)        # half extent of the walkable map (x, z)
const SPAWN := Vector3(128.5, 0.3, -345.5)
# detail materials that read a per-instance colour from details.json
const TINTED := ["C3_glass", "C3_curtain_c", "C3_parapet_white", "C3_garage_door"]
# prototype: [visibility range in metres, casts shadows]
const DETAILS := {
	"win": [450.0, true], "win_brown": [450.0, true], "baldoor": [450.0, true],
	"balcony_open": [650.0, true], "balcony_closed": [650.0, true], "roof_hut": [650.0, true],
	"entrance": [300.0, true], "shopfront": [400.0, true], "garage_door": [300.0, false],
	"curtain": [220.0, false], "pipe": [250.0, false], "antenna": [300.0, false],
	"ac": [180.0, true], "dish": [180.0, true], "pots": [120.0, true], "vent": [120.0, false],
}
const PROPS := {
	"tree_a": 700.0, "tree_b": 700.0, "tree_c": 700.0, "poplar": 700.0,
	"bush_a": 220.0, "bush_b": 220.0, "lamp": 250.0, "bench": 140.0,
}
const SOLID_PROPS := {"tree_a": 0.35, "tree_b": 0.4, "tree_c": 0.3, "poplar": 0.3, "lamp": 0.15}
# name: [camera position, look-at target, player position or null,
#        optional: animation, time in it, player yaw]
const SHOTS := {
	"kid_front": [Vector3(130.6, 1.0, -345.0), Vector3(128.5, 0.8, -345.5), Vector3(128.5, 0.1, -345.5),
			"idle", 0.0, 1.34],
	"kid_face": [Vector3(129.35, 1.27, -345.3), Vector3(128.5, 1.24, -345.5), Vector3(128.5, 0.1, -345.5),
			"idle", 0.0, 1.34],
	"kid_walk": [Vector3(128.5, 0.95, -342.7), Vector3(128.5, 0.8, -345.5), Vector3(128.5, 0.1, -345.5),
			"walk", 0.2, 1.5708],
	"kid_run": [Vector3(131.0, 1.1, -343.6), Vector3(128.5, 0.8, -345.5), Vector3(128.5, 0.1, -345.5),
			"run", 0.13, 1.5708],
	"kid_jump": [Vector3(131.3, 1.3, -344.4), Vector3(128.5, 1.3, -345.5), Vector3(128.5, 0.7, -345.5),
			"jump", 0.33, 1.2],
	"kid_play": [Vector3(125.0, 2.0, -345.3), Vector3(131.0, 1.2, -345.6), Vector3(128.5, 0.1, -345.5),
			"walk", 0.1, 1.5708],
	"map_street": [Vector3(124, 2.6, -341.5), Vector3(210, 4.0, -351), Vector3(128.5, 0.15, -345.5)],
	"map_facade": [Vector3(148, 2.2, -345.5), Vector3(166, 7.0, -356), Vector3(151, 0.15, -347.5)],
	"map_lawn": [Vector3(102, 1.4, -393), Vector3(85, 3.0, -417), Vector3(100, 0.15, -397)],
	"map_balconies": [Vector3(62, 9, -289), Vector3(105, 9, -330), null],
	"map_grid": [Vector3(-60, 45, -150), Vector3(-60, 5, -300), null],
	"map_south": [Vector3(60, 70, 260), Vector3(40, 0, 60), null],
	"map_overview": [Vector3(220, 170, 40), Vector3(-60, 0, -280), null],
}

var player: CharacterBody3D
var style := WorldStyle.new()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	WorldStyle.add_environment(self, 0.0008)
	_load_ground_and_buildings()
	_spawn_details()
	_spawn_props()
	_add_bounds()
	var grass := GrassField.new()
	grass.mask = load(LEVEL + "grass_mask.png")
	grass.size_m = 1280.0
	add_child(grass)
	WorldStyle.add_ink_outline(self)
	player = preload("res://scripts/player.gd").new()
	player.position = SPAWN
	add_child(player)
	print("Micro 15 loaded in %d ms" % (Time.get_ticks_msec() - t0))
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()
	elif "--selftest" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


func _load_ground_and_buildings() -> void:
	var outer := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	outer.mesh = plane
	outer.position.y = -0.05
	var lawn_src := StandardMaterial3D.new()
	lawn_src.resource_name = "C3_lawn"
	lawn_src.albedo_color = Color("#8cc456")
	outer.material_override = style.material_for(lawn_src)
	add_child(outer)

	for file in ["ground.glb", "buildings.glb"]:
		var part: Node3D = load(LEVEL + file).instantiate()
		add_child(part)
		style.apply(part)
		for mi: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
			mi.create_trimesh_collision()


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Groups placements into CELL-sized squares and draws each square with one
## MultiMesh. Each entry of placements becomes [Transform3D, Color].
func _scatter(mesh: Mesh, placements: Array, view_range: float, shadows: bool) -> Dictionary:
	var cells := {}
	for p: Array in placements:
		var key := Vector2i(floori(p[0].origin.x / CELL), floori(p[0].origin.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(p)
	var nodes := {}
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
		nodes[key] = mmi
	return nodes


func _spawn_details() -> void:
	var lib: Node3D = load(LEVEL + "details.glb").instantiate()
	var meshes := style.mesh_library(lib, TINTED)
	lib.free()
	var data: Dictionary = _read_json(LEVEL + "details.json")
	for proto: String in data:
		if not meshes.has(proto):
			push_warning("details.glb has no prototype " + proto)
			continue
		var spec: Array = DETAILS.get(proto, [300.0, false])
		var placements := []
		for e: Array in data[proto]:
			var basis := Basis(Vector3.UP, e[3]) * Basis.from_scale(Vector3(e[4], e[5], e[6]))
			placements.append([Transform3D(basis, Vector3(e[0], e[1], e[2])), Color(e[7], e[8], e[9])])
		_scatter(meshes[proto], placements, spec[0], spec[1])


func _spawn_props() -> void:
	var lib: Node3D = load(LEVEL + "props.glb").instantiate()
	var meshes := style.mesh_library(lib)
	lib.free()
	var data: Dictionary = _read_json(LEVEL + "props.json")
	var bodies := {}
	for prop: String in data:
		if not meshes.has(prop):
			push_warning("props.glb has no prop " + prop)
			continue
		var placements := []
		for e: Array in data[prop]:
			var basis := Basis(Vector3.UP, e[2]).scaled(Vector3.ONE * e[3])
			placements.append([Transform3D(basis, Vector3(e[0], 0.0, e[1])), Color.WHITE])
		_scatter(meshes[prop], placements, PROPS.get(prop, 300.0), true)
		if SOLID_PROPS.has(prop):
			var cyl := CylinderShape3D.new()
			cyl.radius = SOLID_PROPS[prop]
			cyl.height = 3.0
			for p: Array in placements:
				var key := Vector2i(floori(p[0].origin.x / CELL), floori(p[0].origin.z / CELL))
				if not bodies.has(key):
					bodies[key] = StaticBody3D.new()
					add_child(bodies[key])
				var shape := CollisionShape3D.new()
				shape.shape = cyl
				shape.position = p[0].origin + Vector3(0, 1.5, 0)
				bodies[key].add_child(shape)


## Invisible walls around the edge of the mapped area.
func _add_bounds() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along_x: bool = side.z != 0
		box.size = Vector3(BOUNDS.x * 2 if along_x else 2.0, 60.0, 2.0 if along_x else BOUNDS.y * 2)
		shape.shape = box
		shape.position = Vector3(side.x * BOUNDS.x, 30.0, side.z * BOUNDS.y)
		body.add_child(shape)


func _take_shots() -> void:
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.far = 3000
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for shot_name in SHOTS:
		var shot: Array = SHOTS[shot_name]
		cam.position = shot[0]
		cam.look_at(shot[1])
		player.visible = shot[2] != null
		if shot[2] != null:
			player.position = shot[2]
			player.body_mesh.rotation.y = atan2(shot[1].x - shot[0].x, shot[1].z - shot[0].z)
			player.show_pose("idle", 0.0)
		if shot.size() > 3:
			player.show_pose(shot[3], shot[4])
			player.body_mesh.rotation.y = shot[5]
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	get_tree().quit()


func _self_test() -> void:
	var start := player.position
	var report := func(label: String) -> void:
		print("%-8s anim=%-5s speed_scale=%.2f on_floor=%s pos=%s" % [label, player.anim.current_animation,
				player.anim.speed_scale, player.is_on_floor(), player.position.round()])
	await get_tree().create_timer(1.0).timeout
	report.call("idle")
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	report.call("walk")
	Input.action_press("run")
	await get_tree().create_timer(1.0).timeout
	report.call("run")
	Input.action_release("run")
	Input.action_release("move_forward")
	await get_tree().create_timer(0.6).timeout
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 12:
		await get_tree().create_timer(0.1).timeout
		report.call("jump+%d" % i)
	await get_tree().create_timer(0.8).timeout
	report.call("after")
	print("moved %.1f m" % start.distance_to(player.position))
	get_tree().quit()

