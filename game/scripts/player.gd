## Placeholder third-person character: WASD to move, mouse to look,
## Shift to run, Space to jump, Esc to free the mouse.
extends CharacterBody3D

@export var walk_speed := 4.5
@export var run_speed := 8.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.003

var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var body_mesh: Node3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)

	body_mesh = Node3D.new()
	add_child(body_mesh)
	body_mesh.add_child(_part(CapsuleMesh.new(), Color("#f28b3c"), Vector3(0, 0.75, 0), Vector3(0.75, 0.9, 0.75)))
	body_mesh.add_child(_part(SphereMesh.new(), Color("#f6d2b0"), Vector3(0, 1.55, 0), Vector3(0.45, 0.45, 0.45)))
	body_mesh.add_child(_part(BoxMesh.new(), Color("#3d5f8f"), Vector3(0, 1.72, -0.12), Vector3(0.48, 0.12, 0.5)))

	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.6
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.5
	spring_arm.rotation.x = -0.25
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = 60
	camera.far = 2000
	spring_arm.add_child(camera)

	for action in ["move_forward", "move_back", "move_left", "move_right", "run", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_bind("move_forward", KEY_W)
	_bind("move_back", KEY_S)
	_bind("move_left", KEY_A)
	_bind("move_right", KEY_D)
	_bind("run", KEY_SHIFT)
	_bind("jump", KEY_SPACE)


func _part(mesh: Mesh, color: Color, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("tint", color)
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	return mi


func _bind(action: String, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 0.3)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (camera_pivot.global_basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized()
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dir.length() > 0.1:
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
	move_and_slide()
