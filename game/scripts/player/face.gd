## The boy's face: blinks, where the eyes look and simple expressions, all
## through the blend shapes of the head mesh (kid.json "face_shapes", built by
## blender/build_character.py add_face_shapes).
##
## The eyes lead the head: they turn to the look target at once, and the head
## (LookAtModifier3D) follows more slowly, so a glance reads as a glance.
class_name KidFace
extends Node

## expression name: {shape: weight}
const EXPRESSIONS := {
	"neutral": {},
	"happy": {"smile": 1.0, "brows_up": 0.3},
	"grin": {"smile": 1.0, "mouth_open": 0.35, "brows_up": 0.4},
	"surprised": {"brows_up": 1.0, "mouth_open": 0.8},
	"effort": {"brows_frown": 0.8, "mouth_open": 0.3},
	"sad": {"sad": 1.0, "brows_up": 0.25},
	"squint": {"brows_frown": 0.5, "blink": 0.35},
	"tired": {"blink": 0.25, "sad": 0.3},
	"focused": {"brows_frown": 0.4},
}

var mesh: MeshInstance3D
var skeleton: Skeleton3D
var look_target: Node3D
var _idx := {}
var _weights := {}
var _goal := {}
var _expression := "neutral"
var _expression_left := 0.0
var _blink_t := 0.0
var _next_blink := 2.0
var _blink_closed := 0.0
var _double := false
var _head := -1


func setup(model: Node3D, info: Dictionary) -> void:
	mesh = model.find_child(info.get("face_mesh", "kid_head"), true, false) as MeshInstance3D
	skeleton = model.find_child("Skeleton3D", true, false)
	_head = skeleton.find_bone("head") if skeleton else -1
	if mesh == null:
		return
	for s: String in info.get("face_shapes", []):
		var i := mesh.find_blend_shape_by_name(s)
		if i >= 0:
			_idx[s] = i
			_weights[s] = 0.0
	_next_blink = randf_range(1.5, 4.0)


## Shows an expression for some seconds (0 = until changed).
func express(expression: String, seconds := 2.0) -> void:
	_expression = expression if EXPRESSIONS.has(expression) else "neutral"
	_expression_left = seconds


func blink() -> void:
	_blink_t = 0.0
	_next_blink = 0.0


func _process(delta: float) -> void:
	if mesh == null or _idx.is_empty():
		return
	if _expression_left > 0.0:
		_expression_left -= delta
		if _expression_left <= 0.0:
			_expression = "neutral"
	var goal := {}
	for s: String in _idx:
		goal[s] = 0.0
	var expr: Dictionary = EXPRESSIONS[_expression]
	var lid := 0.0
	for s: String in expr:
		if s == "blink":
			lid = expr[s]
		elif goal.has(s):
			goal[s] = expr[s]
	# blinking: closes in 0.06 s, opens in 0.1 s, every 2 to 6 seconds,
	# sometimes twice
	_blink_t += delta
	if _blink_t >= _next_blink:
		var t := _blink_t - _next_blink
		_blink_closed = clampf(t / 0.06, 0.0, 1.0) if t < 0.06 else clampf(1.0 - (t - 0.06) / 0.1, 0.0, 1.0)
		if t > 0.16:
			_blink_t = 0.0
			_double = not _double and randf() < 0.2
			_next_blink = 0.12 if _double else randf_range(2.0, 6.0)
			_blink_closed = 0.0
	var closed := maxf(lid, _blink_closed)
	goal["blink_L"] = closed
	goal["blink_R"] = closed
	# eyes towards the look target, in the head's frame
	if look_target and _head >= 0:
		var hx := skeleton.global_transform * skeleton.get_bone_global_pose(_head)
		var eye := hx.origin + hx.basis.y.normalized() * 0.1
		var d := (look_target.global_position - eye)
		var fwd := hx.basis.z.normalized()
		var up := hx.basis.y.normalized()
		var right := hx.basis.x.normalized()
		var yaw := atan2(d.dot(right), d.dot(fwd))
		var pitch := atan2(d.dot(up), Vector2(d.dot(right), d.dot(fwd)).length())
		if d.dot(fwd) > -0.2:
			goal["look_left"] = clampf(yaw / 0.45, 0.0, 1.0)
			goal["look_right"] = clampf(-yaw / 0.45, 0.0, 1.0)
			goal["look_up"] = clampf(pitch / 0.35, 0.0, 1.0)
			goal["look_down"] = clampf(-pitch / 0.35, 0.0, 1.0)
	for s: String in _idx:
		var speed := 40.0 if s.begins_with("blink") else (18.0 if s.begins_with("look") else 6.0)
		_weights[s] = lerpf(_weights[s], goal[s], 1.0 - exp(-speed * delta))
		mesh.set_blend_shape_value(_idx[s], _weights[s])
