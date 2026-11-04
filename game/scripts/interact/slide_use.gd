## The courtyard slide: up the ladder, sit at the top, down the chute (he
## speeds up on the steep part and slows on the flat run-out) and off.
##
## Node position: the slide asset's origin (Godot axes: the ladder is on -z,
## the chute runs down towards +z), see blender/build_assets.py slide().
class_name SlideUse
extends Interactable

const DECK := 1.4
const LADDER_FOOT := Vector3(0, 0, -1.95)
const LADDER_TOP := Vector3(0, DECK, -0.85)
const SIT_AT := Vector3(0, DECK + 0.03, -0.3)
const RUN := 1.9                          # horizontal length of the slope

var phase := ""                           # climb, sit, slide, off
var _t := 0.0
var _s := 0.0                             # 0..1 along the chute
var _v := 0.0
signal slid(speed: float)


func _init() -> void:
	prompt = "Climb the slide"
	reach = 1.0
	needs_facing = false


func focus_point() -> Vector3:
	return to_global(LADDER_FOOT)


## Point on the chute floor at s (0 top .. 1 end of the run-out), local.
func chute(s: float) -> Vector3:
	var slope_part := 0.8                 # share of s on the slope, the rest is the run-out
	if s <= slope_part:
		var t := s / slope_part
		var e := t * t * (3.0 - 2.0 * t)
		return Vector3(0, DECK + 0.02 - (DECK - 0.32) * e, -0.37 + RUN * t)
	var r := (s - slope_part) / (1.0 - slope_part)
	return Vector3(0, 0.32, -0.37 + RUN + 0.45 * r)


func interact(kid: Node3D) -> void:
	super.interact(kid)
	phase = "climb"
	_t = 0.0
	_s = 0.0
	_v = 0.0
	var xf := Transform3D(global_basis.orthonormalized(), to_global(LADDER_FOOT))
	kid.attach(self, "loco", xf, "")
	kid.animator.play("climb_up", 0.7)
	kid.animator.set_hands("hand_grip", 1.0)


func drive(kid: Node3D, intent: Dictionary, delta: float) -> void:
	_t += delta
	var fwd := global_basis.z
	match phase:
		"climb":
			var t := clampf(_t / 1.7, 0.0, 1.0)
			var p := LADDER_FOOT.lerp(LADDER_TOP, t)
			kid.global_position = to_global(p)
			kid.hips_pin = to_global(p + Vector3(0, 0.72, 0.05))
			kid.hips_pin_weight = 1.0
			if t >= 1.0:
				phase = "sit"
				_t = 0.0
				kid.animator.stop_action()
				kid.animator.set_mode("sit")
		"sit":
			var t := clampf(_t / 0.6, 0.0, 1.0)
			var p := LADDER_TOP.lerp(SIT_AT, t)
			kid.global_position = to_global(p)
			kid.hips_pin = to_global(p + Vector3(0, 0.08, 0))
			if _t > 0.6 and (intent.jump or intent.interact or (intent.move as Vector2).y < -0.5 or _t > 2.5):
				phase = "slide"
				_t = 0.0
				kid.animator.set_mode("slide")
				kid.animator.play("slide_start")
				kid.face.express("happy", 2.0)
		"slide":
			var a := chute(minf(_s, 0.98))
			var b := chute(minf(_s + 0.02, 1.0))
			var dir := (b - a).normalized()
			var sin_a := -dir.y
			var cos_a := sqrt(maxf(0.0, 1.0 - sin_a * sin_a))
			# gravity down the slope against the chute's friction and a little drag
			_v = maxf(_v + (9.8 * (sin_a - 0.22 * cos_a) - 0.3 * _v) * delta, 0.25)
			var metres_per_s := a.distance_to(b) / 0.02
			_s = minf(_s + _v * delta / metres_per_s, 1.0)
			var p := chute(_s)
			kid.global_position = to_global(p)
			kid.hips_pin = to_global(p + Vector3(0, 0.08, 0))
			kid.body_tilt = clampf(asin(clampf(-dir.y, -1.0, 1.0)) * 0.6, 0.0, 0.5)
			if _s >= 1.0 or (_s > 0.85 and _v < 0.3):
				slid.emit(_v)
				phase = "off"
				_t = 0.0
				kid.animator.play("slide_exit")
		"off":
			kid.hips_pin_weight = clampf(1.0 - _t / 0.3, 0.0, 1.0)
			if _t > 0.3:
				var at := to_global(chute(1.0) + Vector3(0, 0, 0.35))
				at.y = global_position.y
				phase = ""
				kid.detach(at)
				kid.animator.set_hands("hand_relaxed", 0.0)
				kid.body_mesh.rotation.y = atan2(fwd.x, fwd.z)
