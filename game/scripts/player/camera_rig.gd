## The third-person camera. It lives on the player's CameraPivot node but
## moves on its own (top level): it follows a target with a little lag, turns
## with the look intent, keeps out of walls with its spring arm, eases its
## distance back after a wall and widens the view a little when sprinting.
## A dip on hard landings and a gentle shoulder offset make the motion read
## as weight instead of a camera glued to the head.
##
## Nothing here belongs to one player: a second player (split screen, co-op)
## gets a CameraRig of its own pointed at its own target.
class_name CameraRig
extends Node3D

@export var target: Node3D                 ## what to follow (the player)
@export var height := 1.3                  ## metres above the target's origin
@export var follow_sharpness := 14.0       ## higher follows tighter
@export var distance := 3.6
@export var crouch_distance := 3.0
@export var shoulder := 0.25               ## metres to the right of the target
@export var pitch_min := -1.2
@export var pitch_max := 0.3
@export var base_fov := 60.0
@export var sprint_fov := 68.0

@onready var arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera

var pitch := -0.22
var _dip := 0.0
var _dip_v := 0.0
var _fov_target := 60.0
var _length := 3.6
var _snap := true
var _follow := Vector3.ZERO
var frozen := false                       ## photo mode and shots move the camera themselves


func _ready() -> void:
	top_level = true
	pitch = arm.rotation.x
	_length = distance
	_fov_target = base_fov


## Turns the camera by a look intent (radians).
func look(delta_angles: Vector2) -> void:
	rotation.y += delta_angles.x
	pitch = clampf(pitch + delta_angles.y, pitch_min, pitch_max)


## A downward nudge that springs back (landings); strength in metres.
func dip(strength: float) -> void:
	if not Save.setting("camera_shake"):
		return
	_dip_v -= strength * 9.0


## Jumps straight to the target (teleports, level start).
func snap() -> void:
	_snap = true


func set_sprinting(on: bool) -> void:
	_fov_target = sprint_fov if on else base_fov


func set_crouching(on: bool) -> void:
	_length = crouch_distance if on else distance


func _process(delta: float) -> void:
	if target == null or frozen:
		return
	var goal := target.global_position + Vector3.UP * height
	if _snap:
		_follow = goal
		_snap = false
	else:
		# vertical follow is softer than horizontal, so steps and kerbs do not
		# jolt the view
		var k := 1.0 - exp(-follow_sharpness * delta)
		var kv := 1.0 - exp(-follow_sharpness * 0.6 * delta)
		_follow = Vector3(lerpf(_follow.x, goal.x, k), lerpf(_follow.y, goal.y, kv), lerpf(_follow.z, goal.z, k))
	# critically damped spring for the landing dip
	_dip_v += (-_dip * 90.0 - _dip_v * 18.0) * delta
	_dip += _dip_v * delta
	global_position = _follow + Vector3.UP * _dip
	arm.rotation.x = pitch
	arm.spring_length = lerpf(arm.spring_length, _length, 1.0 - exp(-4.0 * delta))
	arm.position = Vector3(shoulder, 0.0, 0.0)
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-5.0 * delta))
