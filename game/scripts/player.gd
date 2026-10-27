## Third-person player: the boy from docs/character_sheet.png
## (characters/kid/kid.glb, built by blender/build_character.py).
## WASD to move, mouse to look, Shift to run, Space to jump, Esc frees the
## mouse. Plays idle / walk / run / jump / fall / land, with the walk and
## run cycles sped up or slowed down to match the ground speed.
extends CharacterBody3D

const MODEL := preload("res://characters/kid/kid.glb")
const LOOPS := ["idle", "walk", "run", "fall"]
const WALK_CYCLE_SPEED := 1.6            ## m/s at which the walk cycle's feet do not slide
const RUN_CYCLE_SPEED := 4.9
const COYOTE_TIME := 0.15                ## seconds off the ground before the fall pose starts

@export var walk_speed := 2.2
@export var run_speed := 5.5
@export var jump_velocity := 4.6
@export var acceleration := 18.0
@export var mouse_sensitivity := 0.003

var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var body_mesh: Node3D
var anim: AnimationPlayer

var _air_time := 0.0
var _landing := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.75
	add_child(shape)

	body_mesh = MODEL.instantiate()
	add_child(body_mesh)
	WorldStyle.new().apply(body_mesh)
	anim = body_mesh.find_child("AnimationPlayer", true, false)
	for anim_name in LOOPS:
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")

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
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
	move_and_slide()
	_animate(delta, jumped)


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
	elif ground_speed <= walk_speed + 0.3:
		_play("walk", 0.2)
		anim.speed_scale = clampf(ground_speed / WALK_CYCLE_SPEED, 0.5, 1.8)
	else:
		_play("run", 0.2)
		anim.speed_scale = clampf(ground_speed / RUN_CYCLE_SPEED, 0.6, 1.6)


func _play(anim_name: String, blend: float) -> void:
	if anim.current_animation == anim_name:
		return
	anim.speed_scale = 1.0
	anim.play(anim_name, blend)


## Freezes the character in one frame of an animation (preview renders).
func show_pose(anim_name: String, time: float) -> void:
	anim.play(anim_name)
	anim.seek(time, true)
	anim.pause()
