## A place to sit: benches, the chess table stools, the bus stop bench,
## picnic tables, the sandbox edge. Sits him down with sit_down, loops
## sit_idle (his hips held on the seat) and gets him up again with sit_up
## when the use button is pressed or he is told to walk off.
##
## Node position: the middle of the seat surface; its +z is the way he faces.
class_name Seat
extends Interactable

@export var seat_height := 0.46
@export var width := 1.6                  ## room along the seat (two can sit on a long bench)

var scatter: Node = null                  ## for the map's own benches: the Props scatter
var record := -1                          ## and the bench's record in it
var _t := 0.0
var _getting_up := 0.0
var _spot := Vector3.ZERO
var _stand := Vector3.ZERO


func _init() -> void:
	prompt = "Sit"
	reach = 1.3
	needs_facing = false


func can_interact(kid: Node3D) -> bool:
	return super.can_interact(kid) and (scatter == null or not scatter.is_removed(record))


func focus_point() -> Vector3:
	return global_position + global_basis.z * 0.35 - Vector3.UP * seat_height


func interact(kid: Node3D) -> void:
	super.interact(kid)
	# sit on the part of the bench nearest to him
	var local := to_local(kid.global_position)
	var along := clampf(local.x, -width * 0.5 + 0.3, width * 0.5 - 0.3)
	_spot = to_global(Vector3(along, 0.0, 0.0))
	var stand := _spot + global_basis.z * 0.28 - Vector3.UP * seat_height
	_stand = stand
	var xf := Transform3D(Basis(Vector3.UP, atan2(global_basis.z.x, global_basis.z.z)), stand)
	kid.attach(self, "sit", xf, "sit_down")
	kid.animator.set_hands("hand_relaxed", 0.0)
	_t = 0.0
	_getting_up = 0.0


func drive(kid: Node3D, intent: Dictionary, delta: float) -> void:
	_t += delta
	kid.hips_pin = _spot + Vector3.UP * 0.07 - global_basis.z * 0.02
	kid.hips_pin_weight = smoothstep(0.35, 0.9, _t)
	if _getting_up > 0.0:
		_getting_up -= delta
		kid.hips_pin_weight = clampf(_getting_up / 0.4, 0.0, 1.0)
		if _getting_up <= 0.0:
			kid.detach(_stand + global_basis.z * 0.08)
		return
	if _t > 0.8 and (intent.interact or intent.jump or (intent.move as Vector2).length() > 0.6):
		_getting_up = 0.4
		kid.animator.play("sit_up")


func prompt_for(_kid: Node3D) -> String:
	return "Sit"
