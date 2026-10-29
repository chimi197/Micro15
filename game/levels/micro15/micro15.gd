## The whole Micro 15 neighbourhood (Satu Mare), built by
## blender/build_map.py from OpenStreetMap: every block of flats, house,
## school, church, shop and garage in full 3D, the street network, trees,
## lamps and benches, and 3D grass streamed around the camera.
##
## Everything is a node of micro15.tscn, so the level opens and can be
## edited in the Godot editor: Ground and Buildings (glTF scenes styled by
## StyledModel), Details and Props (Scatter nodes that draw the repeated
## windows, balconies, trees... with MultiMeshes per 96 m cell), Grass,
## Boundary (the shadowed blocks around the playable area, which the map is
## cut to), the Player, and Placed: the things placed with the map editor
## (scripts/admin.gd), a scene of its own.
##
## Run normally to walk around. Run with `-- --shots` to save preview
## screenshots to ../docs/renders/<kind>/ and quit, or with `-- --selftest` to
## drive the player through every move and print what the animations did.
extends Node3D

# name: [camera position, look-at target, player position or null,
#        optional: animation, time in it, player yaw]
const SHOTS := {
	"kid_front": [Vector3(-27.9, 1.0, 221.1), Vector3(-30.0, 0.8, 220.6), Vector3(-30.0, 0.1, 220.6),
			"idle", 0.0, 1.34],
	"kid_face": [Vector3(-29.15, 1.27, 220.8), Vector3(-30.0, 1.24, 220.6), Vector3(-30.0, 0.1, 220.6),
			"idle", 0.0, 1.34],
	"kid_walk": [Vector3(-30.0, 0.95, 223.4), Vector3(-30.0, 0.8, 220.6), Vector3(-30.0, 0.1, 220.6),
			"walk", 0.2, 1.5708],
	"kid_run": [Vector3(-27.5, 1.1, 222.5), Vector3(-30.0, 0.8, 220.6), Vector3(-30.0, 0.1, 220.6),
			"run", 0.13, 1.5708],
	"kid_jump": [Vector3(-27.2, 1.3, 221.7), Vector3(-30.0, 1.3, 220.6), Vector3(-30.0, 0.7, 220.6),
			"jump", 0.33, 1.2],
	"kid_crouch": [Vector3(-27.9, 0.9, 221.5), Vector3(-30.0, 0.5, 220.6), Vector3(-30.0, 0.1, 220.6),
			"crouch_walk", 0.6, 1.2],
	"kid_punch": [Vector3(-28.5, 1.2, 222.9), Vector3(-30.0, 0.8, 220.6), Vector3(-30.0, 0.1, 220.6),
			"punch_cross", 0.33, 1.2],
	"kid_double_jump": [Vector3(-27.2, 1.4, 221.7), Vector3(-30.0, 1.3, 220.6), Vector3(-30.0, 0.8, 220.6),
			"double_jump", 0.3, 1.2],
	"kid_play": [Vector3(-33.5, 2.0, 220.8), Vector3(-27.5, 1.2, 220.5), Vector3(-30.0, 0.1, 220.6),
			"walk", 0.1, 1.5708],
	"assets": [Vector3(-19.5, 14, 248.1), Vector3(-19.5, 0, 222.1), null],
	"map_street": [Vector3(-34.5, 2.6, 224.6), Vector3(51.5, 4.0, 215.1), Vector3(-30.0, 0.15, 220.6)],
	"map_facade": [Vector3(-10.5, 2.2, 220.6), Vector3(7.5, 7.0, 210.1), Vector3(-7.5, 0.15, 218.6)],
	"map_lawn": [Vector3(-56.5, 1.4, 173.1), Vector3(-73.5, 3.0, 149.1), Vector3(-58.5, 0.15, 169.1)],
	"map_balconies": [Vector3(-96.5, 9, 277.1), Vector3(-53.5, 9, 236.1), null],
	"map_grid": [Vector3(60, 60, 330), Vector3(60, 5, 190), null],
	"map_south": [Vector3(80, 75, 590), Vector3(60, 0, 330), null],
	"map_overview": [Vector3(330, 200, 640), Vector3(50, 0, 200), null],
	"map_edge": [Vector3(-132, 4, 222), Vector3(-172, 9, 178), null],
	"trees_yard": [Vector3(6.5, 2.2, 224.1), Vector3(26.5, 6.0, 244.1), null],
	"time_morning": [Vector3(-34.5, 2.6, 224.6), Vector3(51.5, 8.0, 215.1), Vector3(-30.0, 0.15, 220.6)],
	"time_evening": [Vector3(-34.5, 2.6, 224.6), Vector3(51.5, 8.0, 215.1), Vector3(-30.0, 0.15, 220.6)],
	"time_night": [Vector3(-34.5, 2.6, 224.6), Vector3(51.5, 8.0, 215.1), Vector3(-30.0, 0.15, 220.6)],
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
	var lineup := Node3D.new()
	add_child(lineup)
	for shot_name in SHOTS:
		var shot: Array = SHOTS[shot_name]
		if shot_name == "assets":
			_line_up_assets(lineup, Vector3(-52.5, 0.0, 218.1), 66.0)
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
		get_viewport().get_texture().get_image().save_png(render_path(shot_name))
	get_tree().quit()


## Where a preview screenshot goes: docs/renders/<kind>/<name>.png, the kind
## being the start of its name (kid, time, editor, assets; the rest are map).
static func render_path(shot_name: String) -> String:
	var kind := shot_name.get_slice("_", 0)
	if kind not in ["kid", "time", "editor", "assets"]:
		kind = "map"
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders").path_join(kind)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join(shot_name + ".png")


## Screenshots of the map editor's panels (docs/renders/editor/*.png),
## without saving anything to the level.
func _editor_shots() -> void:
	var frames := func(n: int) -> void:
		for i in n:
			await get_tree().process_frame
	var shot := func(shot_name: String) -> void:
		await frames.call(8)
		get_viewport().get_texture().get_image().save_png(render_path(shot_name))
		print("saved ", shot_name)
	Admin.save_enabled = false
	$Props.removed_file = ""
	$Details.removed_file = ""
	$Buildings.saving = false
	player.camera.global_position = Vector3(-8.5, 9, 248.1)
	player.camera.look_at(Vector3(6.5, 1, 226.1))
	Admin.open_editor()
	var cam := get_viewport().get_camera_3d()
	cam.global_position = Vector3(-8.5, 9, 248.1)
	cam.look_at(Vector3(6.5, 1, 226.1))
	Admin._camera.copy_view(cam)
	Admin.set_tool("place")
	Admin.choose_asset("res://assets/tree_birch.tscn")
	await frames.call(60)
	Admin._cursor = Vector3(1.5, 0.0, 232.1)
	await shot.call("editor_place")
	Admin.set_tool("select")
	var props: Scatter = $Props
	var near := props.records_near(Vector3(6.5, 0, 233.1), 12.0)
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
	Admin._pin_at = Vector3(3.5, 0, 230.1)
	Admin.pin_add_confirm("move this tree 2 m left")
	await shot.call("editor_pins")
	# a hill and two paths, never saved
	var t: Terrain = $Terrain
	var net: PathNetwork = $Paths
	t.saving = false
	net.saving = false
	var hill := Vector2.INF
	for r in range(0, 30, 2):
		for a in 12:
			var c := Vector2(6.5, 234.1) + Vector2.from_angle(a * TAU / 12.0) * r
			if hill == Vector2.INF and t.editable(c.x, c.y):
				hill = c
	if hill != Vector2.INF:
		for i in 6:
			t.brush("raise", hill.x, hill.y, 8.0, 1.2, 0.5)
		t.finish_stroke()
		Admin.set_tool("terrain")
		Admin._cursor = Vector3(hill.x, t.height(hill.x, hill.y), hill.y)
		await shot.call("editor_terrain")
		Admin.set_tool("paths")
		net.add_path({"type": "trail", "width": 1.2, "points": [[hill.x - 12, hill.y + 6], [hill.x - 3, hill.y + 1],
				[hill.x + 4, hill.y - 1], [hill.x + 12, hill.y + 3]]})
		net.add_path({"type": "sidewalk", "width": 2.0, "points": [[hill.x - 10, hill.y - 6], [hill.x + 8, hill.y - 8]]})
		Admin._path_points = [Vector3(hill.x - 6, 0, hill.y + 9), Vector3(hill.x + 2, 0, hill.y + 7)]
		Admin._cursor = Vector3(hill.x + 9, 0, hill.y + 8)
		await shot.call("editor_paths")
		Admin._path_points.clear()
	Admin.set_tool("remove")
	Admin.ui.keys_panel.visible = true
	await shot.call("editor_keys")
	get_tree().quit()


## Every placeable asset side by side in rows of `length` metres, each row
## 7 m nearer the camera than the one before.
func _line_up_assets(parent: Node3D, start: Vector3, length: float) -> void:
	var x := 0.0
	var row := 0
	for f in DirAccess.get_files_at("res://assets/"):
		if not f.ends_with(".tscn"):
			continue
		var n: Node3D = load("res://assets/" + f).instantiate()
		var box := AABB()
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			box = box.merge(mi.transform * mi.get_aabb()) if box.has_volume() else mi.transform * mi.get_aabb()
		if x > 0.0 and x + box.size.x > length:
			row += 1
			x = 0.0
		n.position = start + Vector3(x - box.position.x, 0, row * 7.0)
		x += box.size.x + 1.2
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
	await _test_boundary()
	await _test_ground_and_paths()
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
	var x := -30.0
	for dz in [1.0, -1.0]:
		var z := 220.6
		while absf(z - 220.6) < 30.0 and height.call(x, z) > 0.05:
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
			if player.global_position.y > y0 + 0.06 and player.is_on_floor() and i > 10:
				break
		Input.action_release("move_forward")
		await get_tree().create_timer(0.3).timeout
		print("kerb: lawn at height %.2f, after walking %.2f (on floor %s, jumped %s), %s" % [y0,
				player.global_position.y, player.is_on_floor(), jumped,
				"stepped up" if player.global_position.y > y0 + 0.06 and not jumped else "STUCK"])
		return
	print("kerb: no lawn found next to the street")


## Runs the player at the edge of the playable area from just inside it:
## the shadowed blocks must stop him.
func _test_boundary() -> void:
	var boundary: Boundary = $Boundary
	var poly := boundary.polygon
	print("play area: %d corners, the player starts inside %s" % [poly.size(),
			boundary.contains(Vector2(player.global_position.x, player.global_position.z))])
	var a := poly[0]
	var b := poly[1]
	var mid := (a + b) * 0.5
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= poly.size()
	var inward := (centre - mid).normalized()
	var start := mid + inward * 4.0
	player.global_position = Vector3(start.x, 2.0, start.y)
	player.velocity = Vector3.ZERO
	player.camera_pivot.rotation.y = atan2(inward.x, inward.y)     # facing out
	await get_tree().create_timer(0.5).timeout
	Input.action_press("move_forward")
	Input.action_press("run")
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		Input.action_press("jump")
		await get_tree().physics_frame
		Input.action_release("jump")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("run")
	Input.action_release("move_forward")
	var p := Vector2(player.global_position.x, player.global_position.z)
	print("boundary: ran and jumped at the edge, still inside %s (%.1f m from where the edge is)" % [
			boundary.contains(p), Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)])
	player.global_position = Vector3(-30.0, 0.3, 220.6)


## The terrain tool and the paths, without saving anything to the level.
func _test_ground_and_paths() -> void:
	var t: Terrain = $Terrain
	var net: PathNetwork = $Paths
	t.saving = false
	net.saving = false
	var spot := Vector2.INF
	for c: Vector2 in [Vector2(-30, 240), Vector2(-10, 245), Vector2(-50, 250), Vector2(10, 260), Vector2(-60, 200)]:
		if t.editable(c.x, c.y):
			spot = c
			break
	if spot == Vector2.INF:
		print("terrain: no editable spot found to test")
		return
	var ground_y := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if hit else NAN
	var before := t.snapshot()
	var y0: float = ground_y.call(spot.x, spot.y)
	if is_nan(y0):
		print("terrain: no ground under %s" % Coordinates.text(Vector3(spot.x, 0, spot.y)))
		return
	for i in 4:
		t.brush("raise", spot.x, spot.y, 7.0, 1.5, 0.5)
	t.finish_stroke()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var y1: float = ground_y.call(spot.x, spot.y)
	if is_nan(y1):
		print("terrain: no ground under the raised spot")
		t.restore(Rect2(spot - Vector2(12, 12), Vector2(24, 24)), before)
		return
	player.global_position = Vector3(spot.x, y1 + 1.0, spot.y)
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.8).timeout
	print("terrain: raised the ground at %s by %.2f m (ray %.2f -> %.2f), the player stands at %.2f (on floor %s)" % [
			Coordinates.text(Vector3(spot.x, 0, spot.y)), t.height(spot.x, spot.y), y0, y1,
			player.global_position.y, player.is_on_floor()])
	var a := Vector2(spot.x - 5.0, spot.y)
	var b := Vector2(spot.x + 5.0, spot.y + 1.0)
	var i := net.add_path({"type": "sidewalk", "width": 2.0, "points": [[a.x, a.y], [b.x, b.y]]})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var y2: float = ground_y.call(spot.x, spot.y + 0.5)
	print("paths: a sidewalk on the hill, its top %.2f m above the ground, grass makes way %s" % [
			y2 - t.height(spot.x, spot.y + 0.5), PathNetwork.covers(spot.x, spot.y + 0.5)])
	net.remove_path(i)
	t.restore(Rect2(spot - Vector2(12, 12), Vector2(24, 24)), before)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("terrain: undone, the ground is back at %.2f, paths %d" % [ground_y.call(spot.x, spot.y), net.paths.size()])
	player.global_position = Vector3(-30.0, 0.3, 220.6)
	t.saving = true
	net.saving = true


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
	placed_bush.global_position = Vector3(-30.0, 0.13, 220.6)
	var eye := Vector3(-30.0, 6.0, 227.1)
	var pb: Dictionary = Admin.pick_ray(eye, (Vector3(-30.0, 0.5, 220.6) - eye).normalized())
	print("pick placed bush on the street: %s" % ("found" if pb.ref.get("node") == placed_bush else "MISSED %s" % pb.ref))
	placed_bush.free()
	var spot := Vector2(-30.0, 220.6)       # the street in front of the player
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
