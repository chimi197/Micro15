## The whole Micro 15 neighbourhood (Satu Mare), built by
## blender/build_map.py from OpenStreetMap: every block of flats, house,
## school, church, shop and garage in full 3D, the street network, trees,
## lamps and benches, and 3D grass streamed around the camera.
##
## Everything is a node of micro15.tscn, so the level opens and can be
## edited in the Godot editor: Ground and Buildings (glTF scenes, cel-shaded
## by StyledModel), Details and Props (Scatter nodes that draw the repeated
## windows, balconies, trees... with MultiMeshes per 96 m cell), Grass,
## invisible Bounds, the Player, and Placed: the things placed with the
## admin tool (scripts/admin.gd), a scene of its own.
##
## Run normally to walk around. Run with `-- --shots` to save preview
## screenshots to ../docs/renders/ and quit, or with `-- --selftest` to
## drive the player through every move and print what the animations did.
extends Node3D

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
	"kid_crouch": [Vector3(130.6, 0.9, -344.6), Vector3(128.5, 0.5, -345.5), Vector3(128.5, 0.1, -345.5),
			"crouch_walk", 0.6, 1.2],
	"kid_punch": [Vector3(130.0, 1.2, -343.2), Vector3(128.5, 0.8, -345.5), Vector3(128.5, 0.1, -345.5),
			"punch_cross", 0.33, 1.2],
	"kid_double_jump": [Vector3(131.3, 1.4, -344.4), Vector3(128.5, 1.3, -345.5), Vector3(128.5, 0.8, -345.5),
			"double_jump", 0.3, 1.2],
	"kid_play": [Vector3(125.0, 2.0, -345.3), Vector3(131.0, 1.2, -345.6), Vector3(128.5, 0.1, -345.5),
			"walk", 0.1, 1.5708],
	"assets": [Vector3(136, 7, -331), Vector3(136, 1, -348), null],
	"map_street": [Vector3(124, 2.6, -341.5), Vector3(210, 4.0, -351), Vector3(128.5, 0.15, -345.5)],
	"map_facade": [Vector3(148, 2.2, -345.5), Vector3(166, 7.0, -356), Vector3(151, 0.15, -347.5)],
	"map_lawn": [Vector3(102, 1.4, -393), Vector3(85, 3.0, -417), Vector3(100, 0.15, -397)],
	"map_balconies": [Vector3(62, 9, -289), Vector3(105, 9, -330), null],
	"map_grid": [Vector3(-60, 45, -150), Vector3(-60, 5, -300), null],
	"map_south": [Vector3(60, 70, 260), Vector3(40, 0, 60), null],
	"map_overview": [Vector3(220, 170, 40), Vector3(-60, 0, -280), null],
	"trees_yard": [Vector3(165, 2.2, -342), Vector3(185, 6.0, -322), null],
	"time_morning": [Vector3(124, 2.6, -341.5), Vector3(210, 8.0, -351), Vector3(128.5, 0.15, -345.5)],
	"time_evening": [Vector3(124, 2.6, -341.5), Vector3(210, 8.0, -351), Vector3(128.5, 0.15, -345.5)],
	"time_night": [Vector3(124, 2.6, -341.5), Vector3(210, 8.0, -351), Vector3(128.5, 0.15, -345.5)],
}
# shots at another time of day (SunCycle); the rest are at its default
const SHOT_TIMES := {"time_morning": 8.0, "time_evening": 20.4, "time_night": 23.5}

@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()
	elif "--selftest" in OS.get_cmdline_user_args():
		_self_test.call_deferred()
	elif "--editor-shots" in OS.get_cmdline_user_args():
		_editor_shots.call_deferred()


func _take_shots() -> void:
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.far = 3000
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var lineup := Node3D.new()
	add_child(lineup)
	for shot_name in SHOTS:
		var shot: Array = SHOTS[shot_name]
		if shot_name == "assets":
			_line_up_assets(lineup, Vector3(106, 0.0, -348), 66.0)
		else:
			for n in lineup.get_children():
				n.queue_free()
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
		$SunCycle.time_of_day = SHOT_TIMES.get(shot_name, 12.0)
		$SunCycle.apply()
		for i in 30:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in 30:
			await get_tree().process_frame
		print("%-16s %.1f ms a frame" % [shot_name, (Time.get_ticks_usec() - t0) / 30000.0])
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	get_tree().quit()


## Screenshots of the map editor's panels (docs/renders/editor_*.png),
## without saving anything to the level.
func _editor_shots() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders")
	var frames := func(n: int) -> void:
		for i in n:
			await get_tree().process_frame
	var shot := func(shot_name: String) -> void:
		await frames.call(8)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
		print("saved ", shot_name)
	Admin.save_enabled = false
	$Props.removed_file = ""
	$Details.removed_file = ""
	$Buildings.saving = false
	player.camera.global_position = Vector3(150, 9, -318)
	player.camera.look_at(Vector3(165, 1, -340))
	Admin.open_editor()
	var cam := get_viewport().get_camera_3d()
	cam.global_position = Vector3(150, 9, -318)
	cam.look_at(Vector3(165, 1, -340))
	Admin._camera.copy_view(cam)
	Admin.set_tool("place")
	Admin.choose_asset("res://assets/tree_birch.tscn")
	await frames.call(60)
	Admin._cursor = Vector3(160, 0.0, -334)
	await shot.call("editor_place")
	Admin.set_tool("select")
	var props: Scatter = $Props
	var near := props.records_near(Vector3(165, 0, -333), 12.0)
	if not near.is_empty():
		Admin._set_selection([{"kind": "record", "scatter": props, "r": near[0]}])
	Admin.ui.grid_button.button_pressed = true
	Admin.set_grid(true)
	Admin.ui.map_button.button_pressed = true
	Admin.set_map(true)
	await frames.call(4)
	await shot.call("editor_select")
	Admin.set_grid(false)
	Admin.set_tool("light")
	Admin.look_preset("Golden hour")
	await shot.call("editor_light")
	Admin.look_preset("Summer noon")
	Admin.set_tool("pins")
	Admin._pin_at = Vector3(162, 0, -336)
	Admin.pin_add_confirm("move this tree 2 m left")
	await shot.call("editor_pins")
	Admin.set_tool("remove")
	Admin.ui.keys_panel.visible = true
	await shot.call("editor_keys")
	get_tree().quit()


## Puts one of each placeable asset in a row (preview of the admin palette).
func _line_up_assets(parent: Node3D, start: Vector3, length: float) -> void:
	var names := []
	for f in DirAccess.get_files_at("res://assets/"):
		if f.ends_with(".tscn"):
			names.append(f)
	for i in names.size():
		var n: Node3D = load("res://assets/" + names[i]).instantiate()
		n.position = start + Vector3(length * i / (names.size() - 1), 0, -4.0 if i % 2 else 0.0)
		parent.add_child(n)


func _self_test() -> void:
	var start := player.position
	var report := func(label: String) -> void:
		print("%-10s anim=%-12s speed_scale=%.2f on_floor=%s crouch=%s pos=%s" % [label,
				player.anim.current_animation, player.anim.speed_scale, player.is_on_floor(), player.crouching,
				player.position.round()])
	var phase := func() -> float:
		return player.anim.current_animation_position / player.anim.current_animation_length
	var wait := func(seconds: float) -> void:
		await get_tree().create_timer(seconds).timeout
	var tap := func(action: String) -> void:
		Input.action_press(action)
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release(action)
	var shown := []
	for n: Node3D in player.body_mesh.find_children("body_*", "", true, false):
		if n.visible:
			shown.append(n.name)
	print("outfit %s, body pieces shown %s, hair springs %d" % [player.outfit, shown, player.springs.setting_count])
	print("clips: ", player.anim.get_animation_list())
	print("assets: ", DirAccess.get_files_at("res://assets/"), " admin enabled: ", Admin.enabled)
	await wait.call(1.0)
	report.call("idle")
	Input.action_press("move_forward")
	await wait.call(1.0)
	report.call("walk")
	Input.action_press("run")
	var last := 0.0
	for i in 30:
		if player.anim.current_animation == "walk":
			last = phase.call()
		await get_tree().physics_frame
		if player.anim.current_animation == "run":
			print("walk phase %.2f -> run phase %.2f" % [last, phase.call()])
			break
	await wait.call(1.0)
	report.call("run")
	Input.action_release("run")
	Input.action_press("crouch")
	await wait.call(1.0)
	report.call("crouchwalk")
	Input.action_release("move_forward")
	await wait.call(0.8)
	report.call("crouch")
	Input.action_release("crouch")
	await wait.call(0.6)
	report.call("stand")
	await tap.call("jump")
	await wait.call(0.25)
	report.call("jump")
	await tap.call("jump")
	await wait.call(0.15)
	report.call("dbl_jump")
	for i in 10:
		await wait.call(0.15)
		report.call("air+%d" % i)
		if player.is_on_floor():
			break
	await wait.call(0.8)
	report.call("landed")
	await tap.call("punch")
	await wait.call(0.2)
	report.call("punch1")
	await wait.call(0.35)
	await tap.call("punch")
	await wait.call(0.2)
	report.call("punch2")
	await wait.call(1.0)
	player.take_hit()
	await wait.call(0.1)
	report.call("hit")
	await wait.call(1.0)
	report.call("after")
	player.set_noclip(true)
	Input.action_press("jump")
	await wait.call(0.5)
	Input.action_release("jump")
	report.call("noclip")
	player.set_noclip(false)
	print("moved %.1f m" % start.distance_to(player.position))
	await _test_kerb()
	await _test_tools()
	get_tree().quit()


## Walks the player from a lawn onto a sidewalk (a 12 cm kerb) without
## jumping: the step-up must lift him on.
func _test_kerb() -> void:
	var height := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2.0, z), Vector3(x, -1.0, z))
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if hit else -1.0
	# sideways from the street in front of the start until the lawn
	var x := 128.5
	for dz in [1.0, -1.0]:
		var z := -345.5
		while absf(z + 345.5) < 30.0 and height.call(x, z) > 0.05:
			z += dz * 0.05
		if height.call(x, z) > 0.05 or height.call(x, z) < -0.5:
			continue
		var walk_dir := Vector3(0, 0, -dz)              # back towards the sidewalk
		player.global_position = Vector3(x, height.call(x, z) + 0.05, z + dz * 1.2)
		player.velocity = Vector3.ZERO
		player.camera_pivot.rotation.y = atan2(-walk_dir.x, -walk_dir.z)
		await get_tree().create_timer(0.3).timeout
		var y0 := player.global_position.y
		var jumped := false
		Input.action_press("move_forward")
		for i in 150:
			await get_tree().physics_frame
			jumped = jumped or player.velocity.y > 1.0
			if player.global_position.y > y0 + 0.1 and player.is_on_floor() and i > 10:
				break
		Input.action_release("move_forward")
		await get_tree().create_timer(0.3).timeout
		print("kerb: lawn at height %.2f, after walking %.2f (on floor %s, jumped %s), %s" % [y0,
				player.global_position.y, player.is_on_floor(), jumped,
				"stepped up" if player.global_position.y > y0 + 0.1 and not jumped else "STUCK"])
		return
	print("kerb: no lawn found next to the street")


## The map editor's building blocks, without saving anything to the level.
func _test_tools() -> void:
	var props: Scatter = $Props
	var details: Scatter = $Details
	var buildings: StyledModel = $Buildings
	var grass: GrassField = $Grass
	var saved := [props.removed_file, details.removed_file, buildings.removed_file, grass.paint_file]
	props.removed_file = ""
	details.removed_file = ""
	buildings.saving = false
	grass.paint_file = ""
	Admin.save_enabled = false
	Admin.open_editor()
	# a bush, looked at from above and to the side: picked by its box
	var bush := -1
	for r in props.record_count():
		if props.record_proto(r) == "bush_a" and not props.is_removed(r):
			bush = r
			break
	var at := props.record_transform(bush).origin
	var from := at + Vector3(0, 9, 7)
	var picked: Dictionary = Admin.pick_ray(from, (at + Vector3(0, 0.4, 0) - from).normalized())
	print("pick bush: %s %s" % [picked.ref.get("kind"), props.record_proto(picked.ref.r) if picked.ref.get("kind") == "record" else ""])
	Admin._remove_refs([picked.ref], "Remove bush")
	var gone := props.is_removed(bush)
	Admin.undo()
	var back := not props.is_removed(bush)
	Admin.redo()
	var again := props.is_removed(bush)
	Admin.undo()
	print("remove bush: removed %s, undo brings it back %s, redo %s" % [gone, back, again])
	# a window: from in front of it
	var win := 0
	while details.record_proto(win) != "win":
		win += 1
	var wt := details.record_transform(win)
	var centre := wt * details.record_aabb(win).get_center()
	var found := ""
	for side in [wt.basis.z, -wt.basis.z, wt.basis.x, -wt.basis.x]:
		var eye: Vector3 = centre + side.normalized() * 6.0
		var p: Dictionary = Admin.pick_ray(eye, (centre - eye).normalized())
		if p.ref.get("kind") == "record" and p.ref.scatter == details:
			found = details.record_proto(p.ref.r)
			break
	print("pick window: %s" % found)
	# a whole building, from above
	var mi: MeshInstance3D = buildings.find_children("bld_*", "MeshInstance3D", true, false)[0]
	var top := mi.global_transform * mi.get_aabb().get_center() + Vector3(0, 60, 0)
	var hit_b: Dictionary = Admin.pick_ray(top, Vector3.DOWN)
	var kind: String = hit_b.ref.get("kind", "")
	if kind == "part":
		Admin._remove_refs([hit_b.ref], "Remove building")
		await get_tree().physics_frame
		var below: Dictionary = Admin.pick_ray(top, Vector3.DOWN)
		print("remove building %s: hidden %s, ray now hits %s" % [mi.name, not mi.visible,
				below.ref.get("kind", "the ground")])
		Admin.undo()
		await get_tree().physics_frame
	else:
		print("pick building: got %s" % kind)
	# moving a map tree turns it into a placed asset
	var tree := props.find_record(props.record_proto(0), props.record_transform(0).origin)
	var placed_before := $Placed.get_child_count()
	Admin._set_selection([{"kind": "record", "scatter": props, "r": tree}])
	var x0 := props.record_transform(tree).origin.x
	Admin.edit_selected("x", x0 + 2.0)
	var moved: Node3D = $Placed.get_child($Placed.get_child_count() - 1)
	print("move map %s: placed things %d -> %d, now at x %.1f (was %.1f), map record hidden %s" % [
			props.record_proto(tree), placed_before, $Placed.get_child_count(), moved.global_position.x, x0,
			props.is_removed(tree)])
	Admin.undo()
	Admin.undo()
	print("undo twice: placed things %d, map record back %s" % [$Placed.get_child_count(), not props.is_removed(tree)])
	Admin.clear_selection()
	var on_roads: int = Admin.remove_props_on_roads()
	Admin.undo()
	print("map things on roads: %d (undone)" % on_roads)
	# a placed bush (no collision): still picked, so it can be removed
	var placed_bush: Node3D = load("res://assets/bush_a.tscn").instantiate()
	$Placed.add_child(placed_bush)
	placed_bush.global_position = Vector3(128.5, 0.13, -345.5)
	var eye := Vector3(128.5, 6.0, -339.0)
	var pb: Dictionary = Admin.pick_ray(eye, (Vector3(128.5, 0.5, -345.5) - eye).normalized())
	print("pick placed bush on the street: %s" % ("found" if pb.ref.get("node") == placed_bush else "MISSED %s" % pb.ref))
	placed_bush.free()
	var spot := Vector2(128.5, -345.5)       # the street in front of the player
	var before := grass._lawn(spot.x, spot.y)
	grass.paint(spot.x, spot.y, 3.0, true)
	var painted := grass._lawn(spot.x, spot.y)
	grass.paint(spot.x, spot.y, 1.0, false)
	var cleared := grass._lawn(spot.x, spot.y)
	grass.truncate_strokes(0)
	print("grass brush: lawn %s -> grown %s -> cleared %s -> undone %s" % [before, painted, cleared,
			grass._lawn(spot.x, spot.y)])
	var cycle: SunCycle = $SunCycle
	for t in [6.0, 8.0, 12.0, 13.5, 20.4, 23.5]:
		cycle.time_of_day = t
		cycle.apply()
		print("sun %s: elevation %.1f, energy %.2f, light dir %s" % [cycle.clock(),
				rad_to_deg(asin(cycle.sun_direction(t).y)), $Sun.light_energy, (-$Sun.global_basis.z).snapped(Vector3.ONE * 0.01)])
	Admin.look_preset("Overcast")
	print("look Overcast: sun energy %.2f, fog %.4f, clouds %.1f, saturation %.2f" % [$Sun.light_energy,
			cycle._env.fog_density, cycle.look.clouds, cycle._env.adjustment_saturation])
	Admin.look_preset("Summer noon")
	print("coordinates: %s, parse \"x 357.6, z 18.5\" -> %s" % [Coordinates.text(Vector3(357.63, 0, 18.47)),
			Coordinates.parse("x 357.6, z 18.5")])
	Admin.close_editor()
	Admin.save_enabled = true
	props.removed_file = saved[0]
	details.removed_file = saved[1]
	buildings.saving = true
	grass.paint_file = saved[3]
