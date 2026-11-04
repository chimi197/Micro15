## One seat of a swing. The seat and its chains are a pendulum hanging from
## the top bar; he pumps by pushing forward and back (W/S or the stick) in
## time with the swing, like on a real one: push forward on the way forward,
## back on the way back. Letting go of the stick lets it die down; the use
## button (or jump, at the front of a big swing) gets him off.
##
## Node position: the pivot on the top bar; `seat` is the moving part (the
## seat and chains) made by InteractionDirector with MeshSplit.
class_name SwingSeat
extends Interactable

@export var length := 1.71                ## pivot to seat surface
@export var max_angle := 1.15             ## radians
var seat: Node3D                          ## rotates about its local x
var angle := 0.0                          ## radians, + = forward (the way he faces)
var speed := 0.0                          ## radians a second
var _t := 0.0
var _off := 0.0
var _creak := 0.0
signal creaked(strength: float)


func _init() -> void:
	prompt = "Swing"
	reach = 1.1
	needs_facing = false


func focus_point() -> Vector3:
	return to_global(Vector3(0, -length - 0.43, 0.25))


func can_interact(kid: Node3D) -> bool:
	return super.can_interact(kid) and absf(angle) < 0.25


func interact(kid: Node3D) -> void:
	super.interact(kid)
	_t = 0.0
	_off = 0.0
	kid.attach(self, "swing", _seat_xf(), "")
	kid.animator.set_hands("hand_grip", 1.0)
	state = {"angle": angle, "speed": speed}


func _seat_xf() -> Transform3D:
	var b := global_basis * Basis(Vector3.RIGHT, -angle)
	var p := global_position + b * Vector3(0, -length, 0)
	return Transform3D(Basis(Vector3.UP, atan2(global_basis.z.x, global_basis.z.z)), p - Vector3.UP * 0.45)


func _physics_process(delta: float) -> void:
	if user == null:
		# a free swing settles down on its own
		speed += -9.8 / length * sin(angle) * delta
		speed *= exp(-0.6 * delta)
		angle += speed * delta
	if seat:
		seat.rotation.x = -angle
	var c := absf(speed)
	if c > 0.6 and signf(speed) != signf(_creak):
		creaked.emit(clampf(c / 3.0, 0.1, 1.0))
	_creak = speed


func drive(kid: Node3D, intent: Dictionary, delta: float) -> void:
	_t += delta
	var pump := -(intent.move as Vector2).y           # forward = +1
	# gravity, a little air drag, and the pump: leaning with the swing's
	# motion adds energy, against it takes it away
	var accel := -9.8 / length * sin(angle)
	accel += pump * signf(speed if absf(speed) > 0.05 else pump) * 2.2
	speed += accel * delta
	speed *= exp(-(0.18 if absf(pump) > 0.1 else 0.45) * delta)
	angle += speed * delta
	if absf(angle) > max_angle:
		angle = signf(angle) * max_angle
		speed *= -0.3
	state = {"angle": angle, "speed": speed}
	var b := global_basis * Basis(Vector3.RIGHT, -angle)
	kid.hips_pin = global_position + b * Vector3(0, -length + 0.09, -0.02)
	kid.hips_pin_weight = 1.0
	kid.body_tilt = -angle * 0.85
	kid.global_position = _seat_xf().origin
	if _off > 0.0:
		_off -= delta
		if _off <= 0.0:
			_leave(kid)
		return
	if _t > 0.6 and intent.interact:
		_off = 0.01
	elif _t > 0.6 and intent.jump and angle > 0.45 and speed > 0.0:
		_leave(kid, true)


func _leave(kid: Node3D, jump := false) -> void:
	var fwd := global_basis.z
	var at := _seat_xf().origin + fwd * 0.3
	if not jump:
		at.y = global_position.y - length - 0.45
	kid.detach(at)
	kid.animator.set_hands("hand_relaxed", 0.0)
	if jump:
		kid.velocity = fwd * (2.0 + speed * 0.8) + Vector3.UP * 3.2
		kid.face.express("grin", 1.2)
	user = null
