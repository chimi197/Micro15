## What makes the boy feel alive when the player is not telling him what to
## do: where he looks, what he does after standing about for a while, how
## hard he breathes after sprinting, and small reactions (a grin when he
## finds something, an effort face on a hard landing).
##
## Look targets, by priority: something to use nearby (the thing he could
## interact with), something that just happened (a bird taking off, a ball
## bouncing: `notice()`), and otherwise where the camera looks when he
## stands still, or a little ahead of him when he walks.
class_name KidPersonality
extends Node

## [clip, seconds to hold (0 = the clip's length), mode while holding or ""]
const FIDGETS := [
	["scratch_head", 0.0, ""],
	["look_back", 0.0, ""],
	["kick", 0.0, ""],
	["idle_arms", 6.0, "arms"],
	["shake_head", 0.0, ""],
	["nod", 0.0, ""],
]

var kid: CharacterBody3D
var animator: KidAnimator
var face: KidFace
var look_target: Node3D                   ## the node the head and eyes follow
var fatigue := 0.0                        ## 0..1, rises while sprinting
var _idle := 0.0
var _next_fidget := 8.0
var _holding := 0.0
var _hold_mode := ""
var _notice_at := Vector3.INF
var _notice_left := 0.0
var _look := Vector3.ZERO
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _last_fidget := -1


## Something caught his eye for a moment.
func notice(at: Vector3, seconds := 1.5) -> void:
	_notice_at = at
	_notice_left = seconds


func reset_idle() -> void:
	_idle = 0.0
	if _holding > 0.0:
		_holding = 0.0
		if animator.mode == _hold_mode:
			animator.set_mode("loco")


func update(delta: float, moving: bool, sprinting: bool, focus: Node3D) -> void:
	fatigue = clampf(fatigue + (delta / 6.0 if sprinting else -delta / 10.0), 0.0, 1.0)
	# fidgets after standing about
	var free: bool = kid.is_on_floor() and animator.mode == "loco" and not animator.is_playing() and not moving
	if moving or not kid.is_on_floor():
		reset_idle()
	elif free or _holding > 0.0:
		_idle += delta
		if _holding > 0.0:
			_holding -= delta
			if _holding <= 0.0 and animator.mode == _hold_mode:
				animator.set_mode("loco")
		elif _idle > _next_fidget:
			_fidget()
	# where to look
	var head := kid.global_position + Vector3.UP * 1.3
	var want: Vector3
	if _notice_left > 0.0:
		_notice_left -= delta
		want = _notice_at
	elif focus != null:
		want = focus.global_position + Vector3.UP * 0.4
	elif not moving and kid.camera:
		# idle: look roughly where the player is looking, with small glances about
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander = Vector2(randf_range(-0.5, 0.5), randf_range(-0.15, 0.2))
			_wander_t = randf_range(1.5, 4.0)
		var cam_fwd: Vector3 = -kid.camera.global_basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized().rotated(Vector3.UP, _wander.x)
		want = head + cam_fwd * 6.0 + Vector3.UP * (_wander.y * 6.0)
	else:
		want = head + kid.facing() * 6.0 + Vector3.DOWN * 0.6
	if _look == Vector3.ZERO:
		_look = want
	_look = _look.lerp(want, 1.0 - exp(-6.0 * delta))
	if look_target:
		look_target.global_position = _look
	if fatigue > 0.6 and not moving:
		face.express("tired", 0.5)


func _fidget() -> void:
	var i := randi() % FIDGETS.size()
	if i == _last_fidget:
		i = (i + 1) % FIDGETS.size()
	_last_fidget = i
	var f: Array = FIDGETS[i]
	_idle = 0.0
	_next_fidget = randf_range(7.0, 14.0)
	if f[2] != "":
		animator.set_mode(f[2])
		_hold_mode = f[2]
		_holding = f[1]
	else:
		animator.play(f[0])
