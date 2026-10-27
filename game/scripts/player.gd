## Third-person player: the boy from docs/character_sheet.png
## (characters/kid/kid.glb and kid.json, built by blender/build_character.py).
## WASD to move, mouse to look, Shift to run, Space to jump, Esc frees the
## mouse. Plays idle / walk / run / jump / fall / land, with the walk and
## run cycles sped up or slowed down to match the ground speed and switched
## at the same point of the stride. The body leans into turns and speed
## changes, and the hair bounces on spring bones.
##
## Clothes are separate meshes: wear() shows a set of garments and hides the
## body pieces they cover, so outfits and accessories can be swapped.
extends CharacterBody3D

const MODEL := preload("res://characters/kid/kid.glb")
const INFO := "res://characters/kid/kid.json"
const LOOPS := ["idle", "walk", "run", "fall"]
const COYOTE_TIME := 0.15                ## seconds off the ground before the fall pose starts

@export var walk_speed := 1.4
@export var run_speed := 4.2
@export var jump_velocity := 4.6
@export var acceleration := 14.0
@export var turn_speed := 10.0
@export var mouse_sensitivity := 0.003

var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var body_mesh: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var springs: SpringBoneSimulator3D
var info: Dictionary                     ## kid.json: gait speeds, garments, body pieces, spring bones
var outfit: Array = []

var _air_time := 0.0
var _landing := 0.0
var _lean := Vector2.ZERO                # forward pitch, side roll
var _last_yaw := 0.0
var _last_speed := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.75
	add_child(shape)

	info = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	body_mesh = MODEL.instantiate()
	add_child(body_mesh)
	WorldStyle.new().apply(body_mesh)
	anim = body_mesh.find_child("AnimationPlayer", true, false)
	for anim_name in LOOPS:
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	skeleton = body_mesh.find_child("Skeleton3D", true, false)
	_add_hair_springs()
	wear(info.outfit)

	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.3
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 3.6
	spring_arm.rotation.x = -0.22
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = 60
	camera.far = 3000
	spring_arm.add_child(camera)

	for action in ["move_forward", "move_back", "move_left", "move_right", "run", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_bind("move_forward", KEY_W)
	_bind("move_back", KEY_S)
	_bind("move_left", KEY_A)
	_bind("move_right", KEY_D)
	_bind("run", KEY_SHIFT)
	_bind("jump", KEY_SPACE)


func _bind(action: String, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


## Shows the listed garments (node names from kid.json) and hides the rest,
## plus every body piece a worn garment covers.
func wear(garments: Array) -> void:
	var hidden := {}
	for garment: String in info.garments:
		var on := garment in garments
		var node := body_mesh.find_child(garment, true, false) as Node3D
		if node:
			node.visible = on
		if on:
			for part: String in info.garments[garment].hides:
				hidden[part] = true
	for part: String in info.body_parts:
		var node := body_mesh.find_child(info.body_parts[part], true, false) as Node3D
		if node:
			node.visible = not hidden.has(part)
	outfit = garments


## One spring per hair bone: the hair lags behind and overshoots when the
## head moves, then settles back into its modelled shape.
func _add_hair_springs() -> void:
	springs = SpringBoneSimulator3D.new()
	skeleton.add_child(springs)
	var bones: Array = info.spring_bones
	springs.setting_count = bones.size()
	for i in bones.size():
		springs.set_root_bone_name(i, bones[i])
		springs.set_end_bone_name(i, bones[i])
		springs.set_extend_end_bone(i, true)
		springs.set_end_bone_direction(i, SpringBoneSimulator3D.BONE_DIRECTION_PLUS_Y)
		springs.set_end_bone_length(i, 0.07)
		springs.set_radius(i, 0.02)
		springs.set_stiffness(i, 2.5)
		springs.set_drag(i, 0.35)
		springs.set_gravity(i, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 0.3)


func _physics_process(delta: float) -> void:
	var jumped := false
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		jumped = true
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera_pivot.global_basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	dir = dir.normalized()
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if dir.length() > 0.1:
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(dir.x, dir.z), turn_speed * delta)
	move_and_slide()
	_animate(delta, jumped)
	_lean_body(delta)


## Leans into turns (more the faster he goes) and forward when speeding up,
## back when braking. The model pivots at the feet.
func _lean_body(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var yaw_rate := angle_difference(_last_yaw, body_mesh.rotation.y) / delta
	var accel := (ground_speed - _last_speed) / delta
	_last_yaw = body_mesh.rotation.y
	_last_speed = ground_speed
	var target := Vector2.ZERO
	if is_on_floor():
		target = Vector2(clampf(accel * 0.012, -0.12, 0.12), clampf(-yaw_rate * ground_speed * 0.012, -0.2, 0.2))
	_lean = _lean.lerp(target, 1.0 - exp(-8.0 * delta))
	body_mesh.rotation.x = _lean.x
	body_mesh.rotation.z = _lean.y


func _animate(delta: float, jumped: bool) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if jumped:
		_air_time = COYOTE_TIME
		_play("jump", 0.08)
		return
	if not is_on_floor():
		_air_time += delta
		# the jump clip ends in the air pose; carry on with the fall loop
		if _air_time >= COYOTE_TIME and anim.current_animation != "jump":
			_play("fall", 0.2)
		return
	if _air_time >= COYOTE_TIME and ground_speed < 1.0:
		_landing = anim.get_animation("land").length
		_play("land", 0.06)
	_air_time = 0.0
	if _landing > 0.0:
		_landing -= delta
		return
	if ground_speed < 0.2:
		_play("idle", 0.25)
	elif ground_speed <= walk_speed + 0.4:
		_play("walk", 0.25, true)
		anim.speed_scale = clampf(ground_speed / info.gait_speed.walk, 0.5, 1.8)
	else:
		_play("run", 0.25, true)
		anim.speed_scale = clampf(ground_speed / info.gait_speed.run, 0.6, 1.6)


## Cross-fades to another clip. With keep_phase, a walk/run switch starts
## the new cycle at the same point of the stride (both start on the left
## heel), so the feet do not skip.
func _play(anim_name: String, blend: float, keep_phase := false) -> void:
	if anim.current_animation == anim_name:
		return
	var phase := -1.0
	if keep_phase and anim.current_animation in ["walk", "run"]:
		phase = anim.current_animation_position / anim.current_animation_length
	anim.speed_scale = 1.0
	anim.play(anim_name, blend)
	if phase >= 0.0:
		anim.seek(phase * anim.current_animation_length)


## Freezes the character in one frame of an animation (preview renders).
func show_pose(anim_name: String, time: float) -> void:
	anim.play(anim_name)
	anim.seek(time, true)
	anim.pause()
