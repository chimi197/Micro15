## Third-person player: the boy from docs/character_sheet.png
## (characters/kid/kid.glb and kid.json, built by blender/build_character.py).
## The scene is player/player.tscn: collision capsule, the model and a
## camera on a spring arm.
##
## WASD to move, mouse to look, Shift to run, Space to jump and Space again
## in the air for a double jump, Ctrl or C to crouch, left click or F to
## punch (jab, then a cross if pressed again quickly), Esc frees the mouse.
## Kerbs, single steps and stairs up to STEP_HEIGHT are walked up without a
## jump (the body and camera glide onto them instead of popping).
##
## Walk, run and crouch-walk cycles are sped up or slowed down to match the
## ground speed and switched at the same point of the stride. The body
## leans into turns and speed changes, and the hair bounces on spring bones.
##
## Clothes are separate meshes: wear() shows a set of garments and hides the
## body pieces they cover, so outfits and accessories can be swapped.
extends CharacterBody3D

const INFO := "res://characters/kid/kid.json"
const LOOPS := ["idle", "walk", "run", "fall", "crouch_idle", "crouch_walk"]
const STRIDES := ["walk", "run", "crouch_walk"]
const COYOTE_TIME := 0.15                ## seconds off the ground before the fall pose starts
const STAND_HEIGHT := 1.5
const CROUCH_HEIGHT := 1.0
const STEP_HEIGHT := 0.35                ## kerbs (0.12 m) and stairs are climbed without jumping

@export var walk_speed := 1.1
@export var run_speed := 3.6
@export var crouch_speed := 0.6
@export var jump_velocity := 4.6
@export var double_jump_velocity := 4.2
@export var acceleration := 14.0
@export var air_control := 0.5          ## share of the ground acceleration available in the air
@export var turn_speed := 10.0
@export var mouse_sensitivity := 0.003
@export var noclip := false             ## set by the admin tool: fly through everything

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var body_mesh: Node3D = $Model
@onready var collision: CollisionShape3D = $Collision
var anim: AnimationPlayer
var skeleton: Skeleton3D
var springs: SpringBoneSimulator3D
var info: Dictionary                     ## kid.json: gait speeds, garments, body pieces, spring bones
var outfit: Array = []
var crouching := false
var speed_multiplier := 1.0              ## the admin tool's speed boost

var _air_time := 0.0
var _locked := 0.0                       # seconds left of a clip that must finish (land, punch, hit)
var _double_jumped := false
var _combo := 0                          # punches thrown in a row
var _combo_window := 0.0
var _lean := Vector2.ZERO                # forward pitch, side roll
var _last_yaw := 0.0
var _last_speed := 0.0
var _step_offset := Vector3.ZERO         # how far the model and camera still trail a step up
var _model_at := Vector3.ZERO
var _pivot_at := Vector3.ZERO


func _ready() -> void:
	info = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	anim = body_mesh.find_child("AnimationPlayer", true, false)
	for anim_name in LOOPS:
		if anim.has_animation(anim_name):
			anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	skeleton = body_mesh.find_child("Skeleton3D", true, false)
	_add_hair_springs()
	wear(info.outfit)
	spring_arm.add_excluded_object(get_rid())
	floor_snap_length = STEP_HEIGHT       # follows the ground down off kerbs, too
	_model_at = body_mesh.position
	_pivot_at = camera_pivot.position


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
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 0.3)


func _physics_process(delta: float) -> void:
	if noclip:
		_fly(delta)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera_pivot.global_basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	dir = dir.normalized()
	_set_crouch(Input.is_action_pressed("crouch") and is_on_floor())

	var event := ""
	if is_on_floor():
		_double_jumped = false
		if Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = jump_velocity
			event = "jump"
	else:
		velocity += get_gravity() * delta
		if Input.is_action_just_pressed("jump") and not _double_jumped and _air_time > 0.08:
			velocity.y = double_jump_velocity
			_double_jumped = true
			event = "double_jump"
	if Input.is_action_just_pressed("punch") and is_on_floor() and not crouching and not Admin.building:
		event = "punch"

	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	if crouching:
		speed = crouch_speed
	if _locked > 0.0 and anim.current_animation.begins_with("punch"):
		speed *= 0.2
	var target := dir * speed * speed_multiplier
	var accel := acceleration * (1.0 if is_on_floor() else air_control)
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if dir.length() > 0.1:
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(dir.x, dir.z), turn_speed * delta)
	_step_up(delta)
	move_and_slide()
	_step_offset *= exp(-14.0 * delta)
	body_mesh.position = _model_at + _step_offset
	camera_pivot.position = _pivot_at + _step_offset
	_animate(delta, event)
	_lean_body(delta)


## Walking into a low step (a kerb, a stair): lifts the body onto it when
## there is a floor up to STEP_HEIGHT higher just ahead and room to stand.
func _step_up(delta: float) -> void:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if not is_on_floor() or velocity.y > 0.0 or motion.length() < 0.0005:
		return
	if not test_move(global_transform, motion):
		return                                    # nothing in the way
	var lift := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, lift):
		return                                    # no headroom
	var probe := motion.normalized() * ((collision.shape as CapsuleShape3D).radius + 0.05)
	var raised := global_transform.translated(lift)
	if test_move(raised, probe):
		return                                    # a wall, not a step
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), -lift, landing):
		return                                    # nothing to stand on
	if landing.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise := STEP_HEIGHT - landing.get_travel().length()
	if rise <= 0.01:
		return
	# onto the step: far enough in that the round bottom of the capsule
	# stands on its top rather than on its edge
	var move := probe + Vector3.UP * (rise + 0.01)
	global_position += move
	_step_offset -= move


## Admin noclip: fly where the camera looks, through walls. Space up,
## Ctrl down, Shift fast.
func _fly(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera.global_basis * Vector3(input.x, 0, input.y)
	if Input.is_action_pressed("jump"):
		dir.y += 1.0
	if Input.is_action_pressed("crouch"):
		dir.y -= 1.0
	var speed := (40.0 if Input.is_action_pressed("run") else 10.0) * speed_multiplier
	velocity = dir.normalized() * speed if dir.length() > 0.01 else Vector3.ZERO
	global_position += velocity * delta
	_play("fall", 0.2)


func set_noclip(on: bool) -> void:
	noclip = on
	collision.disabled = on
	velocity = Vector3.ZERO


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	if not on and _blocked_above():
		return
	crouching = on
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	collision.position.y = capsule.height / 2.0


## True when there is no room to stand up.
func _blocked_above() -> bool:
	return test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT))


## Plays the hit reaction (for when something hits the player).
func take_hit() -> void:
	_play("hit", 0.05)
	_locked = anim.current_animation_length * 0.8


## Leans into turns (more the faster he goes) and forward when speeding up,
## back when braking. The model pivots at the feet.
func _lean_body(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var yaw_rate := angle_difference(_last_yaw, body_mesh.rotation.y) / delta
	var accel := (ground_speed - _last_speed) / delta
	_last_yaw = body_mesh.rotation.y
	_last_speed = ground_speed
	var target := Vector2.ZERO
	if is_on_floor() and not crouching:
		target = Vector2(clampf(accel * 0.01, -0.1, 0.1), clampf(-yaw_rate * ground_speed * 0.01, -0.16, 0.16))
	_lean = _lean.lerp(target, 1.0 - exp(-8.0 * delta))
	body_mesh.rotation.x = _lean.x
	body_mesh.rotation.z = _lean.y


func _animate(delta: float, event: String) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_combo_window -= delta
	match event:
		"jump":
			_air_time = COYOTE_TIME
			_locked = 0.0
			_play("jump", 0.08)
			return
		"double_jump":
			_play("double_jump", 0.05)
			return
		"punch":
			# a new punch once the last one has landed; quickly after it, a cross
			if _locked <= 0.15 or (anim.current_animation.begins_with("punch") and _locked <= 0.3):
				_combo = _combo + 1 if _combo_window > 0.0 else 1
				var clip := "punch_cross" if _combo % 2 == 0 else "punch_jab"
				anim.stop()
				_play(clip, 0.06)
				_locked = anim.current_animation_length * 0.75
				_combo_window = anim.current_animation_length + 0.25
				return
	if not is_on_floor():
		_air_time += delta
		# the jump clips end in the air pose; carry on with the fall loop
		if _air_time >= COYOTE_TIME and not anim.current_animation in ["jump", "double_jump"]:
			_play("fall", 0.25)
		return
	if _air_time >= COYOTE_TIME:
		_locked = 0.0
		if ground_speed < 1.0:
			_play("land", 0.06)
			_locked = anim.current_animation_length * 0.6
	_air_time = 0.0
	if _locked > 0.0:
		_locked -= delta
		return
	if crouching:
		if ground_speed < 0.15:
			_play("crouch_idle", 0.2)
		else:
			_play("crouch_walk", 0.2, true)
			anim.speed_scale = clampf(ground_speed / info.gait_speed.crouch_walk, 0.5, 2.0)
	elif ground_speed < 0.2:
		_play("idle", 0.25)
	elif ground_speed <= walk_speed * speed_multiplier + 0.4:
		_play("walk", 0.25, true)
		anim.speed_scale = clampf(ground_speed / info.gait_speed.walk, 0.5, 1.8)
	else:
		_play("run", 0.25, true)
		anim.speed_scale = clampf(ground_speed / info.gait_speed.run, 0.6, 1.6)


## Cross-fades to another clip. With keep_phase, a switch between stride
## cycles starts the new one at the same point of the stride (all start on
## the same foot), so the feet do not skip.
func _play(anim_name: String, blend: float, keep_phase := false) -> void:
	if anim.current_animation == anim_name:
		return
	var phase := -1.0
	if keep_phase and anim.current_animation in STRIDES:
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
