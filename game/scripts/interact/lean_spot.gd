## Somewhere to lean and hang about: the carpet beater's post, a wall by a
## block entrance. He leans (idle_lean) until he moves off.
##
## Node position: where his feet go; +z is the way he faces.
class_name LeanSpot
extends Interactable

var _t := 0.0


func _init() -> void:
	prompt = "Lean"
	reach = 1.0
	needs_facing = false


func interact(kid: Node3D) -> void:
	super.interact(kid)
	_t = 0.0
	var f := global_basis.z
	kid.attach(self, "lean", Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), global_position), "")


func drive(kid: Node3D, intent: Dictionary, delta: float) -> void:
	_t += delta
	if _t > 0.5 and (intent.interact or intent.jump or (intent.move as Vector2).length() > 0.5):
		kid.detach(global_position + global_basis.z * 0.15)
