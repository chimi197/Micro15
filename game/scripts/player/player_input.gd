## What the player wants to do this frame, read from the keyboard, mouse and
## gamepad. The character never reads Input itself: it only consumes the
## intent this node fills in, so the same character can later be driven by a
## network peer, a replay or a mini-game simply by filling `intent` some other
## way (set `local` to false and write the fields yourself).
##
## Gamepad: left stick moves, right stick looks, A jumps, B crouches (hold),
## X uses / interacts, Y punches or kicks, left trigger runs, clicking the
## left stick sprints, Back opens the photo camera, Start pauses.
class_name PlayerInput
extends Node

## true: filled from this machine's devices every physics frame
@export var local := true
@export var mouse_sensitivity := 0.003
@export var stick_sensitivity := 2.6        ## radians per second at full right-stick tilt
@export var invert_y := false

## The current intent. Fields:
## move: Vector2, stick-style (x right, y back), length 0..1
## run, sprint, crouch: held
## jump, interact, punch, photo: pressed this frame
## look: Vector2 radians to turn the camera this frame (yaw, pitch)
var intent := {}
var _look_accum := Vector2.ZERO
var _sprint_latch := false
var _last_run_tap := -10.0


func _ready() -> void:
	intent = empty_intent()


static func empty_intent() -> Dictionary:
	return {"move": Vector2.ZERO, "run": false, "sprint": false, "crouch": false, "jump": false,
			"interact": false, "punch": false, "photo": false, "look": Vector2.ZERO}


func _unhandled_input(event: InputEvent) -> void:
	if not local:
		return
	# clicking into the game window takes the mouse for looking about
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not get_tree().paused and not (Admin and Admin.active):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_accum += Vector2(-event.relative.x, -event.relative.y * (-1.0 if invert_y else 1.0)) \
				* mouse_sensitivity


func _physics_process(delta: float) -> void:
	if local:
		poll(delta)


## Fills `intent` from the devices; called every physics frame.
func poll(delta: float) -> void:
	var it := empty_intent()
	it.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	it.run = Input.is_action_pressed("run")
	# a second tap of run within 0.3 s, or clicking the stick, sprints until
	# run is let go
	if Input.is_action_just_pressed("run"):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_run_tap < 0.3:
			_sprint_latch = true
		_last_run_tap = now
	if Input.is_action_just_pressed("sprint"):
		_sprint_latch = true
	if not it.run and not Input.is_action_pressed("sprint"):
		_sprint_latch = false
	it.sprint = _sprint_latch and it.move.length() > 0.5
	it.run = it.run or it.sprint
	it.crouch = Input.is_action_pressed("crouch")
	it.jump = Input.is_action_just_pressed("jump")
	it.interact = Input.is_action_just_pressed("interact")
	it.punch = Input.is_action_just_pressed("punch")
	it.photo = Input.is_action_just_pressed("photo")
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var look := _look_accum
	look += Vector2(-stick.x, -stick.y * (-1.0 if invert_y else 1.0)) * stick_sensitivity * delta
	_look_accum = Vector2.ZERO
	it.look = look
	intent = it


## For network peers and tests: replaces the intent for this frame.
func set_intent(values: Dictionary) -> void:
	var it := empty_intent()
	it.merge(values, true)
	intent = it
