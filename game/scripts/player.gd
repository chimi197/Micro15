## Third-person player: the boy (characters/kid/kid.glb and kid.json, built by
## blender/build_character.py). The scene is player/player.tscn.
##
## The parts, each its own script so they can be reused or replaced:
## * PlayerInput (player/player_input.gd): what the player wants this frame
##   (keyboard, mouse, gamepad). Nothing else reads Input, so a network peer
##   or a mini-game can drive the boy by filling the same intent.
## * CameraRig (player/camera_rig.gd): the follow camera on CameraPivot.
## * KidAnimator: the AnimationTree (blend spaces, modes, one-shots, hands).
## * FootPlacement + TwoBoneIK3D: feet on kerbs, stairs and slopes.
## * LookAtModifier3D on chest, neck and head, KidFace (blinks, eyes,
##   expressions), KidPersonality (where he looks, fidgets, reactions),
##   BodyDynamics (breathing).
##
## Controls: WASD or the left stick to move, mouse or right stick to look,
## Shift to jog (tap twice, or click the stick, to sprint), Space to jump
## (again in the air for a flip), Ctrl or C to crouch, E to use what is in
## front of him (sit, swing, climb, pick up, buy...), left click or F to
## punch, or to kick a ball at his feet. He climbs low walls and ledges by
## jumping at them.
##
## Clothes are separate meshes: wear() shows a set of garments and hides the
## body pieces they cover, so outfits and accessories can be swapped.
extends CharacterBody3D

signal landed(fall_height: float)
signal stepped(side: String, strength: float, surface: String)

const INFO := "res://characters/kid/kid.json"
const COYOTE_TIME := 0.15
const STAND_HEIGHT := 1.5
const CROUCH_HEIGHT := 1.0
const STEP_HEIGHT := 0.35
const CLIMB_MIN := 0.45                   ## ledge heights he climbs instead of jumping
const CLIMB_MAX := 1.15

@export var walk_speed := 1.3
@export var run_speed := 2.8
@export var sprint_speed := 4.3
@export var crouch_speed := 0.6
@export var jump_velocity := 4.6
@export var double_jump_velocity := 4.2
@export var acceleration := 9.0          ## m/s² speeding up
@export var deceleration := 13.0         ## m/s² slowing down
@export var air_control := 0.5
@export var turn_speed := 10.0
@export var noclip := false

@onready var input: PlayerInput = $Input
@onready var rig: CameraRig = $CameraPivot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var body_mesh: Node3D = $Model
@onready var collision: CollisionShape3D = $Collision
var anim: AnimationPlayer                ## the clips (driven by animator.tree)
var animator: KidAnimator
var face: KidFace
var personality: KidPersonality
var skeleton: Skeleton3D
var springs: SpringBoneSimulator3D
var feet_pre: FootPlacement
var feet_post: FootPlacement
var leg_ik: TwoBoneIK3D
var look_mods: Array[LookAtModifier3D] = []
var dynamics: BodyDynamics
var info: Dictionary
var outfit: Array = []
var crouching := false
var speed_multiplier := 1.0
var attached: Interactable = null        ## what he is sitting on, swinging on...
var carrying: Node3D = null              ## a ball in his hands
var focus: Interactable = null           ## what the use button would use
var frozen := false                      ## cut-scenes, photo mode
## While attached: where his hips should be (world), set by the interactable
## every frame; the model is shifted so the clip's hips land there.
var hips_pin := Vector3.INF
var hips_pin_weight := 0.0               ## 0..1, eased in by the interactable
var body_tilt := 0.0                     ## extra pitch of the model (the swing)
var _pin_offset := Vector3.ZERO
var _hips_bone := -1

var _air_time := 0.0
var _fall_from := 0.0
var _locked := 0.0
var _double_jumped := false
var _combo := 0
var _combo_window := 0.0
var _lean := Vector2.ZERO
var _last_yaw := 0.0
var _last_speed := 0.0
var _step_offset := Vector3.ZERO
var _model_at := Vector3.ZERO
var _climb: Dictionary = {}
var _look_target: Node3D


func _ready() -> void:
	add_to_group("player")
	info = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	anim = body_mesh.find_child("AnimationPlayer", true, false)
	skeleton = body_mesh.find_child("Skeleton3D", true, false)
	animator = KidAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(body_mesh, info)
	animator.footstep.connect(_on_footstep)
	_add_hair_springs()
	_add_rig_modifiers()
	face = KidFace.new()
	face.name = "Face"
	add_child(face)
	face.setup(body_mesh, info)
	face.look_target = _look_target
	personality = KidPersonality.new()
	personality.name = "Personality"
	personality.kid = self
	personality.animator = animator
	personality.face = face
	personality.look_target = _look_target
	add_child(personality)
	personality.add_to_group("kid_attention")
	wear(info.outfit)
	spring_arm.add_excluded_object(get_rid())
	rig.target = self
	floor_snap_length = STEP_HEIGHT
	_model_at = body_mesh.position


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


## Puts on one garment in its slot (kid.json "slots"), taking off whatever
## was in that slot.
func wear_item(garment: String) -> void:
	var slots: Dictionary = info.get("slots", {})
	var slot: String = slots.get(garment, "")
	var out: Array = outfit.filter(func(g: String) -> bool: return slots.get(g, "?") != slot)
	out.append(garment)
	wear(out)


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


## Foot placement with leg IK, look-at on the spine and head, breathing.
## Modifiers run in child order after the animation: feet, IK, foot tilt,
## look, breathing, then the hair springs (added first, moved last).
func _add_rig_modifiers() -> void:
	_look_target = Marker3D.new()
	_look_target.name = "LookTarget"
	_look_target.top_level = true
	add_child(_look_target)
	feet_pre = FootPlacement.new()
	feet_pre.name = "FeetPre"
	feet_pre.body = self
	skeleton.add_child(feet_pre)
	leg_ik = TwoBoneIK3D.new()
	leg_ik.name = "LegIK"
	leg_ik.setting_count = 2
	var i := 0
	for side: String in ["L", "R"]:
		var t := Marker3D.new()
		t.name = "FootTarget" + side
		t.top_level = true
		add_child(t)
		var p := Marker3D.new()
		p.name = "KneePole" + side
		p.top_level = true
		add_child(p)
		feet_pre.targets[side] = t
		feet_pre.poles[side] = p
		leg_ik.set_root_bone_name(i, "thigh." + side)
		leg_ik.set_middle_bone_name(i, "shin." + side)
		leg_ik.set_end_bone_name(i, "foot." + side)
		i += 1
	skeleton.add_child(leg_ik)
	for j in 2:
		var side: String = ["L", "R"][j]
		leg_ik.set_target_node(j, leg_ik.get_path_to(feet_pre.targets[side]))
		leg_ik.set_pole_node(j, leg_ik.get_path_to(feet_pre.poles[side]))
	feet_post = FootPlacement.new()
	feet_post.name = "FeetPost"
	feet_post.stage = "post"
	feet_post.body = self
	feet_post.pre = feet_pre
	skeleton.add_child(feet_post)
	# look-at spread over chest, neck and head (the head does most)
	for spec: Array in [["chest", 0.25, 35.0, 0.6], ["neck", 0.4, 45.0, 0.45], ["head", 0.75, 60.0, 0.3]]:
		var la := LookAtModifier3D.new()
		la.name = "Look_" + spec[0]
		la.bone_name = spec[0]
		la.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
		la.primary_rotation_axis = Vector3.AXIS_Y
		la.use_secondary_rotation = true
		la.use_angle_limitation = true
		la.symmetry_limitation = true
		la.primary_limit_angle = deg_to_rad(spec[2])
		la.primary_damp_threshold = 0.6
		la.secondary_limit_angle = deg_to_rad(spec[2] * 0.6)
		la.secondary_damp_threshold = 0.6
		la.duration = spec[3]
		la.transition_type = Tween.TRANS_SINE
		la.ease_type = Tween.EASE_OUT
		la.influence = spec[1]
		skeleton.add_child(la)
		la.target_node = la.get_path_to(_look_target)
		look_mods.append(la)
	dynamics = BodyDynamics.new()
	dynamics.name = "Breathing"
	skeleton.add_child(dynamics)
	skeleton.move_child(springs, -1)


func facing() -> Vector3:
	return body_mesh.global_basis.z.normalized()


func _physics_process(delta: float) -> void:
	if noclip:
		_fly(delta)
		return
	var it: Dictionary = input.intent
	if not frozen:
		rig.look(it.look)
	if frozen:
		it = PlayerInput.empty_intent()
	_cast_feet()
	if attached != null:
		attached.drive(self, it, delta)
		_pin_hips(delta)
		_update_rig_weights(delta, 0.0)
		personality.update(delta, false, false, null)
		return
	if not _climb.is_empty():
		_climbing(delta)
		return

	var dir := rig.global_basis * Vector3(it.move.x, 0, it.move.y)
	dir.y = 0
	var amount := minf(dir.length(), 1.0)
	dir = dir.normalized()
	_set_crouch(it.crouch and is_on_floor())

	var event := ""
	if is_on_floor():
		_double_jumped = false
		if it.jump and not crouching and _locked <= 0.0:
			if not _try_climb(dir if amount > 0.1 else facing()):
				velocity.y = jump_velocity
				event = "jump"
	else:
		velocity += get_gravity() * delta
		if it.jump and not _double_jumped and _air_time > 0.08:
			velocity.y = double_jump_velocity
			_double_jumped = true
			event = "double_jump"
	_update_focus()
	if it.interact and _locked <= 0.0 and is_on_floor():
		if carrying:
			_throw()
		elif focus:
			personality.reset_idle()
			focus.interact(self)
			return
	if it.punch and is_on_floor() and not crouching and not Admin.building and _locked <= 0.0 or \
			it.punch and _combo_window > 0.0 and anim_action().begins_with("punch"):
		if carrying:
			_throw()
		elif not _kick_ball():
			event = "punch"

	var speed := walk_speed
	if it.run:
		speed = sprint_speed if it.sprint else run_speed
	if crouching:
		speed = crouch_speed
	if carrying:
		speed = minf(speed, run_speed * 0.8)
	speed *= amount
	if _locked > 0.0:
		speed *= 0.15
	# a sharp change of direction slows him first, then he sets off the new
	# way: reads as a stop and turn instead of an instant spin
	var ground_v := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor() and amount > 0.1 and ground_v.length() > 1.0:
		var c := ground_v.normalized().dot(dir)
		speed *= clampf((c + 0.4) / 1.4, 0.1, 1.0)
	var target := dir * speed * speed_multiplier
	var accel := acceleration if target.length() > ground_v.length() else deceleration
	accel *= 1.0 if is_on_floor() else air_control
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if amount > 0.1 and _locked <= 0.0:
		var turn := turn_speed * (0.6 if ground_v.length() > 3.0 else 1.0)
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(dir.x, dir.z), turn * delta)
	_step_up(delta)
	if is_on_floor():
		_fall_from = global_position.y
	else:
		_fall_from = maxf(_fall_from, global_position.y)
	var was_on_floor := is_on_floor()
	move_and_slide()
	_step_offset *= exp(-14.0 * delta)
	body_mesh.position = _model_at + _step_offset
	_animate(delta, event, was_on_floor)
	_lean_body(delta)
	var sprinting: bool = it.sprint and Vector2(velocity.x, velocity.z).length() > run_speed
	rig.set_sprinting(sprinting)
	rig.set_crouching(crouching)
	personality.update(delta, amount > 0.1 or ground_v.length() > 0.3, sprinting, focus)
	dynamics.fatigue = personality.fatigue
	_update_rig_weights(delta, 1.0 if is_on_floor() else 0.0)


func anim_action() -> String:
	return animator.action


## Rays down under both feet for the foot placement.
func _cast_feet() -> void:
	var space := get_world_3d().direct_space_state
	for side: String in ["L", "R"]:
		var i := skeleton.find_bone("foot." + side)
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		var from := Vector3(at.x, global_position.y + 0.55, at.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			feet_pre.ground[side] = [global_position.y, Vector3.UP, false]
		else:
			feet_pre.ground[side] = [hit.position.y, hit.normal, true]


## Foot IK on when standing or walking on the ground, off in the air and
## while seated; the head looks about unless an action needs it.
func _update_rig_weights(delta: float, feet: float) -> void:
	var w := feet
	if animator.mode not in ["loco", "crouch"] or attached != null:
		w = 0.0
	feet_pre.weight = move_toward(feet_pre.weight, w, delta * 4.0)
	leg_ik.influence = feet_pre.weight
	var look := 1.0
	if animator.action in ["climb_up", "roll", "double_jump", "throw", "kick", "slide_start", "slide_exit"]:
		look = 0.2
	for la in look_mods:
		la.active = look > 0.05


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	var me := global_position
	var fwd := facing()
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.is_visible_in_tree() or not it.can_interact(self):
			continue
		var p := it.focus_point()
		var d := Vector2(p.x - me.x, p.z - me.z).length()
		if d > it.reach or absf(p.y - me.y) > 2.0:
			continue
		var to := Vector3(p.x - me.x, 0, p.z - me.z).normalized()
		var score := d - (to.dot(fwd) * 0.5 if it.needs_facing else 0.5)
		if it.needs_facing and to.dot(fwd) < -0.1 and d > 0.5:
			continue
		if score < best_d:
			best_d = score
			best = it
	focus = best


# ----------------------------------------------------------------------------
# Using things
# ----------------------------------------------------------------------------
## Holds the boy on an interactable (a seat, a swing...): he stops walking,
## stands at xf and loops the mode's animation until detach().
func attach(it: Interactable, mode: String, xf: Transform3D, intro_clip := "") -> void:
	attached = it
	it.user = self
	velocity = Vector3.ZERO
	_set_crouch(false)
	collision.disabled = true
	place(xf)
	animator.set_mode(mode)
	if intro_clip != "":
		animator.play(intro_clip)
	personality.reset_idle()


## Moves him to a transform (its basis' z is the way he faces).
func place(xf: Transform3D) -> void:
	global_position = xf.origin
	var z := xf.basis.z
	body_mesh.rotation.y = atan2(z.x, z.z)
	_step_offset = Vector3.ZERO
	body_mesh.position = _model_at


func detach(at := Vector3.INF, outro_clip := "") -> void:
	var it := attached
	attached = null
	hips_pin = Vector3.INF
	hips_pin_weight = 0.0
	body_tilt = 0.0
	_pin_offset = Vector3.ZERO
	body_mesh.rotation.x = 0.0
	body_mesh.position = _model_at
	if it:
		it.release(self)
	if at != Vector3.INF:
		global_position = at
	collision.disabled = false
	animator.set_mode("loco")
	if outro_clip != "":
		_locked = animator.play(outro_clip) * 0.7
	velocity = Vector3.ZERO


## Shifts the model so the hips of the playing clip sit on hips_pin.
func _pin_hips(delta: float) -> void:
	if _hips_bone < 0:
		_hips_bone = skeleton.find_bone("hips")
	body_mesh.rotation.x = body_tilt
	body_mesh.rotation.z = 0.0
	var want := Vector3.ZERO
	if hips_pin != Vector3.INF and hips_pin_weight > 0.0:
		var hips := skeleton.global_transform * skeleton.get_bone_global_pose(_hips_bone).origin
		var base := global_position + body_mesh.get_parent_node_3d().global_basis * _model_at
		var clip_hips := hips - (base + _pin_offset)
		want = (hips_pin - base - clip_hips) * hips_pin_weight
	_pin_offset = _pin_offset.lerp(want, 1.0 - exp(-14.0 * delta))
	body_mesh.position = _model_at + body_mesh.get_parent_node_3d().global_basis.inverse() * _pin_offset


## Plays a one-shot and holds him still for most of it.
func perform(clip: String, hold := 0.8) -> float:
	var length := animator.play(clip)
	_locked = length * hold
	return length


func pick_up(thing: Node3D) -> void:
	carrying = thing
	perform("pick_up", 0.6)
	animator.set_hands("hand_grip", 1.0)


## Drops whatever he carries and returns it.
func drop_carried() -> Node3D:
	var thing := carrying
	carrying = null
	animator.set_hands("hand_relaxed", 0.0)
	if animator.mode == "carry":
		animator.set_mode("loco")
	return thing


func _throw() -> void:
	var thing := drop_carried()
	perform("throw", 0.5)
	if thing and thing.has_method("thrown"):
		var aim := -camera.global_basis.z
		aim.y = maxf(aim.y, 0.0) + 0.45
		get_tree().create_timer(0.42).timeout.connect(func() -> void:
			thing.thrown(self, aim.normalized()))
	body_mesh.rotation.y = atan2(-camera.global_basis.z.x, -camera.global_basis.z.z)


## Kicks a ball lying at his feet; false when there is none.
func _kick_ball() -> bool:
	for b in get_tree().get_nodes_in_group("ball"):
		var ball := b as Node3D
		var d := ball.global_position - global_position
		d.y = 0.0
		if d.length() < 1.0 and d.normalized().dot(facing()) > 0.2:
			perform("kick", 0.6)
			get_tree().create_timer(0.36).timeout.connect(func() -> void:
				if ball.has_method("kicked"):
					ball.kicked(self, facing()))
			return true
	return false


# ----------------------------------------------------------------------------
# Climbing low walls and ledges
# ----------------------------------------------------------------------------
## Jumping at a wall with a top between CLIMB_MIN and CLIMB_MAX above his
## feet climbs it instead (garage plinths, low walls, the sandbox edge,
## fences: if there is room on the other side he climbs over).
func _try_climb(dir: Vector3) -> bool:
	if dir.length() < 0.1:
		return false
	var space := get_world_3d().direct_space_state
	var base := global_position
	var radius := (collision.shape as CapsuleShape3D).radius
	# something in the way at knee height?
	var q := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 0.35, base + Vector3.UP * 0.35 + dir * (radius + 0.5))
	q.exclude = [get_rid()]
	var wall := space.intersect_ray(q)
	if wall.is_empty() or wall.normal.y > 0.5:
		return false
	var into := -Vector3(wall.normal.x, 0, wall.normal.z).normalized()
	var over: Vector3 = wall.position + into * 0.3
	q = PhysicsRayQueryParameters3D.create(Vector3(over.x, base.y + CLIMB_MAX + 0.6, over.z),
			Vector3(over.x, base.y + 0.2, over.z))
	q.exclude = [get_rid()]
	var top := space.intersect_ray(q)
	if top.is_empty():
		return false
	var h: float = top.position.y - base.y
	if h < CLIMB_MIN or h > CLIMB_MAX or top.normal.y < 0.7:
		return false
	# room to stand up there?
	var stand := Transform3D(Basis(), Vector3(over.x, top.position.y + 0.02, over.z))
	if test_move(stand, Vector3.UP * 0.05):
		return false
	var clip := anim.get_animation("climb_up")
	var track := -1
	if clip:
		for t in clip.get_track_count():
			if clip.track_get_type(t) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(t)).ends_with(":hips"):
				track = t
	_climb = {"from": global_position, "to": stand.origin, "t": 0.0, "clip": clip, "track": track,
			"length": animator.play("climb_up", 1.0)}
	body_mesh.rotation.y = atan2(into.x, into.z)
	velocity = Vector3.ZERO
	collision.disabled = true
	feet_pre.weight = 0.0
	animator.set_hands("hand_grip", 1.0)
	face.express("effort", 1.0)
	return true


## The clip lifts his hips by its own amount; the model is moved so the hips
## follow the real ledge instead, and the capsule jumps up at the end.
func _climbing(delta: float) -> void:
	var c := _climb
	c.t += delta
	var length: float = maxf(c.length, 0.3)
	var t := clampf(c.t / length, 0.0, 1.0)
	var from: Vector3 = c.from
	var to: Vector3 = c.to
	var offset := Vector3.ZERO
	if c.track >= 0:
		var clip: Animation = c.clip
		var p0 := clip.position_track_interpolate(c.track, 0.0)
		var p1 := clip.position_track_interpolate(c.track, clip.length)
		var pt := clip.position_track_interpolate(c.track, t * clip.length)
		var rise := p1 - p0                     # in the skeleton's frame (y up, z forward)
		var now := pt - p0
		var k := clampf(now.y / rise.y, 0.0, 1.0) if absf(rise.y) > 0.01 else t
		var clip_world := body_mesh.global_basis * now * skeleton.global_basis.get_scale().y
		offset = (to - from) * k - clip_world
	else:
		offset = (to - from) * smoothstep(0.2, 0.8, t)
	global_position = from
	body_mesh.position = _model_at + body_mesh.get_parent_node_3d().global_basis.inverse() * offset
	if t >= 1.0:
		_climb = {}
		global_position = to
		body_mesh.position = _model_at
		collision.disabled = false
		animator.stop_action()
		animator.set_hands("hand_relaxed", 0.0)
		animator.set_mode("loco")


# ----------------------------------------------------------------------------
func _step_up(delta: float) -> void:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if not is_on_floor() or velocity.y > 0.0 or motion.length() < 0.0005:
		return
	if not test_move(global_transform, motion):
		return
	var lift := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, lift):
		return
	var probe := motion.normalized() * ((collision.shape as CapsuleShape3D).radius + 0.05)
	var raised := global_transform.translated(lift)
	if test_move(raised, probe):
		return
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), -lift, landing):
		return
	if landing.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise := STEP_HEIGHT - landing.get_travel().length()
	if rise <= 0.01:
		return
	var move := probe + Vector3.UP * (rise + 0.01)
	global_position += move
	_step_offset -= move


func _fly(delta: float) -> void:
	var it: Dictionary = input.intent
	rig.look(it.look)
	var dir := camera.global_basis * Vector3(it.move.x, 0, it.move.y)
	if Input.is_action_pressed("jump"):
		dir.y += 1.0
	if Input.is_action_pressed("crouch"):
		dir.y -= 1.0
	var speed := (40.0 if Input.is_action_pressed("run") else 10.0) * speed_multiplier
	velocity = dir.normalized() * speed if dir.length() > 0.01 else Vector3.ZERO
	global_position += velocity * delta
	animator.set_mode("fall")


func set_noclip(on: bool) -> void:
	noclip = on
	collision.disabled = on
	velocity = Vector3.ZERO
	if not on:
		animator.set_mode("loco")


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	if not on and _blocked_above():
		return
	crouching = on
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	collision.position.y = capsule.height / 2.0


func _blocked_above() -> bool:
	return test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT))


func take_hit() -> void:
	_locked = animator.play("hit") * 0.8
	face.express("effort", 1.0)


func _lean_body(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var yaw_rate := angle_difference(_last_yaw, body_mesh.rotation.y) / delta
	var accel := (ground_speed - _last_speed) / delta
	_last_yaw = body_mesh.rotation.y
	_last_speed = ground_speed
	var target := Vector2.ZERO
	if is_on_floor() and not crouching:
		target = Vector2(clampf(accel * 0.012, -0.12, 0.1), clampf(-yaw_rate * ground_speed * 0.01, -0.16, 0.16))
	_lean = _lean.lerp(target, 1.0 - exp(-8.0 * delta))
	body_mesh.rotation.x = _lean.x
	body_mesh.rotation.z = _lean.y


func _animate(delta: float, event: String, was_on_floor: bool) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_combo_window -= delta
	if _locked > 0.0:
		_locked -= delta
	match event:
		"jump":
			_air_time = COYOTE_TIME
			_locked = 0.0
			animator.play("jump")
			animator.set_mode("fall")
			return
		"double_jump":
			animator.play("double_jump")
			face.express("grin", 1.0)
			return
		"punch":
			_combo = _combo + 1 if _combo_window > 0.0 else 1
			var clip := "punch_cross" if _combo % 2 == 0 else "punch_jab"
			var length := animator.play(clip)
			animator.set_hands("hand_fist", 1.0)
			get_tree().create_timer(length).timeout.connect(func() -> void:
				if not animator.action.begins_with("punch"):
					animator.set_hands("hand_relaxed", 0.0))
			_locked = length * 0.6
			_combo_window = length + 0.25
			face.express("focused", length)
			return
	if not is_on_floor():
		_air_time += delta
		if _air_time >= COYOTE_TIME:
			animator.set_mode("fall")
		return
	if _air_time >= COYOTE_TIME:
		var fall := _fall_from - global_position.y
		_land(fall, ground_speed)
	_air_time = 0.0
	if carrying:
		animator.set_mode("carry" if ground_speed > 0.2 else "loco")
		animator.set_speed(ground_speed, delta)
		return
	if crouching:
		animator.set_mode("crouch")
	elif animator.mode in ["loco", "crouch", "fall"]:
		animator.set_mode("loco")
	animator.set_speed(ground_speed, delta)


## Landings by height: a small hop just carries on, a real fall dips the
## camera and plays the landing, a big one also makes him wince.
func _land(fall: float, ground_speed: float) -> void:
	landed.emit(fall)
	animator.set_mode("crouch" if crouching else "loco")
	if animator.action in ["jump", "double_jump"]:
		animator.stop_action()
	if fall > 0.6:
		rig.dip(clampf(fall * 0.04, 0.02, 0.12))
		dynamics.jolt(clampf(fall / 3.0, 0.2, 1.0))
		if ground_speed < 1.5 or fall > 2.2:
			_locked = animator.play("land") * (0.6 if fall > 2.2 else 0.35)
		if fall > 2.2:
			face.express("effort", 0.8)
	elif fall > 0.25:
		dynamics.jolt(0.3)


func _on_footstep(side: String, strength: float) -> void:
	if not is_on_floor() or attached:
		return
	var g: Array = feet_pre.ground[side]
	stepped.emit(side, strength, Surfaces.at(self, Vector3(global_position.x, g[0], global_position.z)))


## Freezes the boy in one frame of an animation (preview renders).
func show_pose(anim_name: String, time: float) -> void:
	animator.show_pose(anim_name, time)
