## Small procedural motion on top of the clips: breathing (harder and
## faster after sprinting) and a little settle of the chest when he lands.
## Runs in the skeleton's modifier stack after the AnimationTree.
class_name BodyDynamics
extends SkeletonModifier3D

var fatigue := 0.0                       ## 0..1
var _t := 0.0
var _settle := 0.0
var _settle_v := 0.0
var _chest := -1
var _neck := -1


## A jolt down the spine (landings), 0..1.
func jolt(strength: float) -> void:
	_settle_v += strength * 6.0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _chest < 0:
		_chest = sk.find_bone("chest")
		_neck = sk.find_bone("neck")
	var rate := lerpf(0.28, 0.95, fatigue)          # breaths a second
	_t += delta * rate * TAU
	var amp := lerpf(0.018, 0.075, fatigue)
	_settle_v += (-_settle * 120.0 - _settle_v * 14.0) * delta
	_settle += _settle_v * delta
	var a := sin(_t) * amp + _settle * 0.25
	var q := sk.get_bone_pose_rotation(_chest)
	sk.set_bone_pose_rotation(_chest, q * Quaternion(Vector3.RIGHT, -a))
	if _neck >= 0:
		var qn := sk.get_bone_pose_rotation(_neck)
		sk.set_bone_pose_rotation(_neck, qn * Quaternion(Vector3.RIGHT, a * 0.6))
