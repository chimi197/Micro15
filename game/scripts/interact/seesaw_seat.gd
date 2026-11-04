## One end of a seesaw. On his own he sits on the low end; jump pushes off
## the ground so his end goes up and drops back with a bump, the way a kid
## plays on one alone. (With a second player on the other end, each push
## tips it over: the beam simply follows whichever end is heavier.)
##
## Node position: the beam's pivot; `beam` is the moving part made by
## InteractionDirector. side is +1 or -1: which end (along local x).
class_name SeesawSeat
extends Interactable

const LIMIT := 0.14                      ## radians each way from level (8 degrees)
@export var side := 1
var beam: Node3D                         ## rotates about its local z
var other: SeesawSeat                    ## the seat on the other end
var tilt := -LIMIT                       ## absolute beam angle; -LIMIT = the +x end down
var spin := 0.0
var _t := 0.0
signal bumped(strength: float)


func _init() -> void:
	prompt = "Sit on the seesaw"
	reach = 1.0
	needs_facing = false


func focus_point() -> Vector3:
	return to_global(Vector3(side * 1.55, -0.6, 0))


func can_interact(kid: Node3D) -> bool:
	return super.can_interact(kid) and user_of_beam() != kid


func user_of_beam() -> Node3D:
	return user if user else (other.user if other else null)


func interact(kid: Node3D) -> void:
	super.interact(kid)
	_t = 0.0
	var xf := Transform3D(Basis(Vector3.UP, atan2(-side * global_basis.x.x, -side * global_basis.x.z)),
			to_global(Vector3(side * 1.75, -0.6, 0)))
	kid.attach(self, "sit", xf, "sit_down")
	kid.animator.set_hands("hand_grip", 1.0)


func _seat_point() -> Vector3:
	# the beam's top surface at this end, rotated with the beam
	var b := global_basis * Basis(Vector3.BACK, tilt)
	return global_position + b * Vector3(side * 1.45, 0.06, 0)


func _physics_process(delta: float) -> void:
	# whoever sits pulls their end down; nobody on it: it rests where it is
	var pull := 0.0
	if user:
		pull -= side
	if other and other.user:
		pull += side
	if is_zero_approx(pull) and other == null:
		pull = 0.0
	if side == 1 or other == null:       # one of the two ends runs the beam
		spin += pull * 2.4 * delta - spin * 1.2 * delta
		tilt += spin * delta
		if absf(tilt) > LIMIT:
			if absf(spin) > 0.3:
				bumped.emit(clampf(absf(spin) / 2.0, 0.1, 1.0))
				if user:
					user.dynamics.jolt(clampf(absf(spin) / 3.0, 0.1, 0.6))
			tilt = signf(tilt) * LIMIT
			spin *= -0.25
		if other:
			other.tilt = tilt
			other.spin = spin
		if beam:
			beam.rotation.z = tilt + LIMIT   # the mesh was built with the +x end down
		state = {"tilt": tilt, "spin": spin}


func drive(kid: Node3D, intent: Dictionary, delta: float) -> void:
	_t += delta
	kid.hips_pin = _seat_point() + Vector3.UP * 0.07
	kid.hips_pin_weight = smoothstep(0.3, 0.9, _t)
	# push off when his end is down
	var down := (tilt * -side) > LIMIT * 0.8
	if intent.jump and down and _t > 0.6:
		var runner := self if (side == 1 or other == null) else other
		runner.spin += side * 1.9
		kid.face.express("grin", 1.0)
	if _t > 0.8 and (intent.interact or (intent.move as Vector2).length() > 0.6 and down):
		var at := to_global(Vector3(side * 1.75, -0.6, 0.0))
		at.y = global_position.y - 0.6
		kid.animator.play("sit_up")
		kid.detach(at)
		kid.animator.set_hands("hand_relaxed", 0.0)
