## A rubber football lying about the playgrounds. Kick it (punch button next
## to it), pick it up (use button) and throw it (use or punch again while
## carrying). Goals and hoops with a GoalZone count what goes in.
class_name Ball
extends RigidBody3D

const RADIUS := 0.11
signal bounced(strength: float)

var carrier: Node3D = null
var spot := Vector3.ZERO                  ## where it was put; it comes back if lost
var _last_touch := 0.0
var _grab: Interactable


func _ready() -> void:
	add_to_group("ball")
	mass = 0.42
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.6
	pm.rough = false
	physics_material_override = pm
	linear_damp = 0.15
	angular_damp = 0.6
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.resource_name = "ball_rubber"
	mat.albedo_color = Color("#d8432f")
	mat.roughness = 0.55
	mi.material_override = mat
	add_child(mi)
	# a white band so its spin reads
	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.985
	torus.outer_radius = RADIUS * 1.02
	torus.rings = 32
	band.mesh = torus
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#f1ece0")
	bm.roughness = 0.6
	band.material_override = bm
	add_child(band)
	_grab = BallGrab.new()
	_grab.ball = self
	add_child(_grab)
	body_entered.connect(_on_hit)
	spot = global_position


func kicked(kid: Node3D, dir: Vector3) -> void:
	_last_touch = 0.0
	sleeping = false
	var power := 5.5 + Vector2(kid.velocity.x, kid.velocity.z).length() * 0.8
	linear_velocity = dir.normalized() * power + Vector3.UP * 2.2
	angular_velocity = dir.cross(Vector3.UP) * -power / RADIUS * 0.5
	get_tree().call_group("sound", "play_at", "kick", global_position, 1.0)


func picked(kid: Node3D) -> void:
	carrier = kid
	freeze = true
	collision_layer = 0
	kid.pick_up(self)
	kid.animator.set_mode("carry")


func thrown(kid: Node3D, dir: Vector3) -> void:
	carrier = null
	freeze = false
	collision_layer = 1
	global_position = kid.global_position + kid.facing() * 0.45 + Vector3.UP * 1.25
	linear_velocity = dir * 7.0 + kid.velocity * 0.5
	_last_touch = 0.0


func _physics_process(delta: float) -> void:
	_last_touch += delta
	if carrier:
		var f: Vector3 = carrier.facing()
		global_position = global_position.lerp(carrier.global_position + f * 0.28 + Vector3.UP * 0.82,
				1.0 - exp(-25.0 * delta))
		if carrier.carrying != self and carrier.animator.action != "throw":      # dropped (sat down...)
			carrier = null
			freeze = false
			collision_layer = 1
		return
	# lost (off the map, stuck in a hedge for good): back where it was put
	if global_position.y < -20.0 or (_last_touch > 120.0 and global_position.distance_to(spot) > 60.0):
		global_position = spot
		linear_velocity = Vector3.ZERO


func _on_hit(_body: Node) -> void:
	var s := linear_velocity.length()
	if s > 1.2:
		bounced.emit(clampf(s / 8.0, 0.1, 1.0))
		get_tree().call_group("sound", "play_at", "bounce", global_position, clampf(s / 8.0, 0.1, 1.0))
		get_tree().call_group("kid_attention", "notice", global_position, 0.8)


## The use-button side of the ball: pick it up.
class BallGrab extends Interactable:
	var ball: Ball

	func _init() -> void:
		prompt = "Pick up the ball"
		reach = 0.9
		needs_facing = false

	func can_interact(kid: Node3D) -> bool:
		return ball.carrier == null and kid.carrying == null and ball.linear_velocity.length() < 2.5

	func interact(kid: Node3D) -> void:
		ball.picked(kid)
