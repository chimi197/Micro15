## Keeps the boy's feet on the real ground: kerbs, stairs, slopes and the
## hills made with the Terrain tool. Two of these run in the skeleton's
## modifier stack around a TwoBoneIK3D per leg:
##
## * stage "pre": reads where each animated foot is, compares the ground
##   under it (rays cast by the player every physics frame, `ground`) with
##   the flat ground the clip was made for, lowers the hips by the lower
##   foot's difference and puts each leg's IK target where the foot should
##   be (and its pole in front of the knee);
## * the IK modifiers bend the legs to reach the targets;
## * stage "post": turns each foot that is down to lie along the slope.
##
## `weight` fades the whole thing in and out (off in the air, sitting...).
class_name FootPlacement
extends SkeletonModifier3D

@export_enum("pre", "post") var stage := "pre"
@export var max_adjust := 0.32           ## metres a foot may move up or down
@export var max_tilt := 0.5              ## radians a foot may tilt to a slope

var body: Node3D                         ## the player (its origin is the flat ground of the clips)
var ground := {"L": [0.0, Vector3.UP, false], "R": [0.0, Vector3.UP, false]}   ## [height, normal, hit]
var targets := {}                        ## side: Node3D, the IK target
var poles := {}                          ## side: Node3D, the IK pole
var pre: FootPlacement                   ## the post stage reads the pre stage's offsets
var weight := 1.0
var offsets := {"L": 0.0, "R": 0.0}
var foot_heights := {"L": 0.0, "R": 0.0}  ## animated height of each ankle over the clip's ground
var drop := 0.0
var _bones := {}


func _bone(name: String) -> int:
	if not _bones.has(name):
		_bones[name] = get_skeleton().find_bone(name)
	return _bones[name]


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or body == null:
		return
	if stage == "post":
		_align_feet(sk)
		return
	var xf := sk.global_transform
	var plane_y := body.global_position.y
	var k := 1.0 - exp(-16.0 * delta)
	var lowest := 0.0
	for side: String in ["L", "R"]:
		var foot := sk.get_bone_global_pose(_bone("foot." + side))
		var at := xf * foot.origin
		foot_heights[side] = at.y - plane_y
		var want := 0.0
		if ground[side][2] and weight > 0.0:
			want = clampf(float(ground[side][0]) - plane_y, -max_adjust, max_adjust)
		offsets[side] = lerpf(offsets[side], want * weight, k)
		lowest = minf(lowest, offsets[side])
		var knee := xf * sk.get_bone_global_pose(_bone("shin." + side)).origin
		if targets.has(side):
			(targets[side] as Node3D).global_position = at + Vector3.UP * offsets[side]
		if poles.has(side):
			var fwd: Vector3 = body.global_basis.z if not body.has_method("facing") else body.facing()
			(poles[side] as Node3D).global_position = knee + fwd * 0.6
	drop = lerpf(drop, lowest, k)
	var hips := _bone("hips")
	var pose := sk.get_bone_pose_position(hips)
	var up_local := (sk.global_basis.inverse() * Vector3.UP)
	var parent := sk.get_bone_parent(hips)
	if parent >= 0:
		up_local = sk.get_bone_global_pose(parent).basis.inverse() * up_local
	sk.set_bone_pose_position(hips, pose + up_local * drop)


## Lays each grounded foot along the slope under it.
func _align_feet(sk: Skeleton3D) -> void:
	if pre == null or pre.weight <= 0.0:
		return
	var basis_inv := sk.global_basis.inverse()
	for side: String in ["L", "R"]:
		var g: Array = pre.ground[side]
		if not g[2]:
			continue
		var n: Vector3 = g[1]
		var tilt := minf(Vector3.UP.angle_to(n), max_tilt)
		if tilt < 0.01:
			continue
		# only feet that are down (not mid-stride)
		var down := 1.0 - smoothstep(0.1, 0.22, float(pre.foot_heights[side]))
		var w := down * pre.weight
		if w <= 0.0:
			continue
		var axis := Vector3.UP.cross(n).normalized()
		var r := Basis((basis_inv * axis).normalized(), tilt * w) if axis.length() > 0.5 else Basis()
		var i := _bone("foot." + side)
		var gp := sk.get_bone_global_pose(i)
		gp.basis = r * gp.basis
		sk.set_bone_global_pose(i, gp)
