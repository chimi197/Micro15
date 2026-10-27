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
}

@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()
	elif "--selftest" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


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
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
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
	Admin._set_active(true)
	player.set_noclip(true)
	Input.action_press("jump")
	await wait.call(0.5)
	Input.action_release("jump")
	report.call("noclip")
	player.set_noclip(false)
	print("moved %.1f m" % start.distance_to(player.position))
	get_tree().quit()
